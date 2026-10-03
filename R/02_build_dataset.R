# ============================================================================
# 02_build_dataset.R —— 合并 NHANES 2009-2014，构建银屑病分析数据集
# 运行：Rscript R/02_build_dataset.R
# 产出：data/analytic.rds  +  data/analytic_pam.rds  +  output/flow_analytic.csv
# 关键：结局 = MCQ070（自报银屑病）；周期由 config.R 控制（F/G/H）
# ============================================================================

Sys.setlocale("LC_CTYPE", "en_US.UTF-8")
source("R/config.R")
source("R/lib_derive.R")   # ★ 推导与排除逻辑抽为纯函数，供干跑测试复用

log_con <- file(file.path(OUT_DIR, "log_02_build.txt"), open = "wt", encoding = "UTF-8")
sink(log_con, split = TRUE)
sink(log_con, type = "message")   # ★ 同时捕获 message()/warning()（默认 sink 只管 stdout）

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(purrr); library(stringr)
})

# ---------- 工具函数 ---------------------------------------------------------
read_cyc <- function(prefix, cyc) {
  f <- file.path(RAW_DIR, paste0(prefix, "_", cyc, ".rds"))
  if (!file.exists(f)) return(NULL)
  readRDS(f)
}
pick <- function(df, varname, n) {
  if (is.null(df) || is.null(varname) || !(varname %in% names(df))) return(rep(NA, n))
  df[[varname]]
}

# ---------- 逐周期提取 -------------------------------------------------------
# ★★ 关键修正（2026-10-03）：NHANES 各模块行数不同（DEMO_F=10537、MCQ_F=10109），
#    **绝不能按行位置对齐**，必须以 SEQN 为键左连接。
#    原实现用 pick() 按位置取列，已废弃。
build_cycle <- function(cyc) {
  message("\n--- building cycle ", cyc, " (", NHANES_YEARS[match(cyc, NHANES_CYCLES)], ") ---")

  modules <- list(
    DEMO = read_cyc("DEMO", cyc), PAQ = read_cyc("PAQ", cyc),
    BIOPRO = read_cyc("BIOPRO", cyc), HDL = read_cyc("HDL", cyc),
    CRP = read_cyc("CRP", cyc),
    BMX = read_cyc("BMX", cyc), GHB = read_cyc("GHB", cyc),
    GLU = read_cyc("GLU", cyc), DIQ = read_cyc("DIQ", cyc),
    BPQ = read_cyc("BPQ", cyc), ALQ = read_cyc("ALQ", cyc),
    SMQ = read_cyc("SMQ", cyc), MCQ = read_cyc("MCQ", cyc),
    INQ = read_cyc("INQ", cyc)
  )

  # ★ 银屑病变量存在性告警（跨周期变量缺失是主要风险）
  mcq <- modules[["MCQ"]]
  if (is.null(mcq) || !(VARMAP$psoriasis_ever %in% names(mcq))) {
    warning("周期 ", cyc, " 缺少 ", VARMAP$psoriasis_ever, " —— 该周期将被排除于主分析")
  }

  # 各模块行数（用于诊断）
  message("  模块行数：",
          paste(sprintf("%s=%d", names(modules),
                        vapply(modules, function(x) if (is.null(x)) 0L else nrow(x), 1L)),
                collapse = " "))

  d <- build_cycle_frame(modules, cyc)

  # --- 药物：银屑病确认用药（按 SEQN 折叠后连接）---
  rx_flag <- collapse_medications(read_cyc("RXQ_RX", cyc))
  if (!is.null(rx_flag)) {
    d <- left_join(d, rx_flag, by = "SEQN")
  } else {
    d$med_psoriasis <- NA
  }
  d
}

dat_list <- lapply(NHANES_CYCLES, build_cycle)
raw <- bind_rows(dat_list)
message("\n合并后总记录数：", nrow(raw))

# ---------- ★★★ D1 关卡：排除前核对 MCQ070 病例数（应在 520 附近）----------
n_pso_raw <- sum(raw$psoriasis_ever == 1, na.rm = TRUE)
n_pso_dat <- sum(!is.na(raw$psoriasis_ever))
message("\n=== ★★★ D1 关卡：银屑病变量核对（排除前）===")
message(sprintf("MCQ070=1 病例数 = %d（核查预期 520，实测周期值 191/167/162）", n_pso_raw))
message(sprintf("有 MCQ070 数据者 = %d", n_pso_dat))
if (abs(n_pso_raw - PSO_EXPECTED_CASES) > 40) {
  message("⚠️ 偏差 >40，请核对变量定义或 NHANES 数据版本！")
} else {
  message("✅ 与核查预期一致，观察臂数据来源正确")
}

# ---------- 变量推导（★ 调用 lib_derive.R 中的纯函数）-----------------------
dat <- derive_psoriasis_vars(raw)

# ---------- 排除流程 ---------------------------------------------------------
ex <- apply_exclusions(dat)
dat <- ex$dat; flow <- ex$flow
print(flow)
write.csv(flow, file.path(OUT_DIR, "flow_analytic.csv"), row.names = FALSE)

# ---------- ★ EPV 功效校验（关键）------------------------------------------
chk <- epv_check(dat)
n_case <- chk$case; n_ctrl <- chk$ctrl
message("\n=== ★ 统计功效校验 ===")
message(sprintf("病例 = %d, 对照 = %d, 合计 = %d", n_case, n_ctrl, n_case + n_ctrl))
message(sprintf("主模型参数 = %d → EPV = %.1f（要求 >= 10）", PSO_MAIN_PARAMS, chk$epv))
if (!chk$ok) warning("EPV < 10，协变量过多，必须精简模型！")
message(sprintf("患病率 = %.2f%%（文献预期约 2.66%%）", n_case/(n_case+n_ctrl)*100))
message(sprintf("排除流程损失病例 %d 例（原始 %d → 分析 %d）：来自年龄<20、妊娠、协变量缺失",
                n_pso_raw - n_case, n_pso_raw, n_case))

# ---------- 合并权重与抽样单元 ----------------------------------------------
dat <- attach_weights(dat)

# ---------- 加速度计子样本（★ 探索性敏感性分析臂，功效有限）----------------
# ★ PAXDAY 是「一人一天一行」（最多 9 天），必须按个体聚合：
#   1) 逐日筛有效天（当日有效佩戴 ≥ ACC_MIN_VALID_MIN 分钟）
#   2) 保留有效天 ≥ ACC_MIN_VALID_DAYS 的个体
#   3) 个体暴露 = 有效天 PAXMTSD 的均值
pam_files <- file.path(RAW_DIR, paste0(ACC_PREFIX, "_", PAM_CYCLES, ".rds"))
pam_files <- pam_files[file.exists(pam_files)]
if (length(pam_files) > 0) {
  paxday <- map_dfr(pam_files, function(f) {
    x <- readRDS(f); cyc <- sub(paste0("^", ACC_PREFIX, "_(.*)\\.rds$"), "\\1", basename(f))
    tibble(SEQN = x$SEQN, cycle = cyc,
           day_mims  = pick(x, VARMAP$acc_day_mims,  nrow(x)),
           valid_min = pick(x, VARMAP$acc_valid_min, nrow(x)),
           day_no    = pick(x, VARMAP$acc_day_no,    nrow(x)))
  })
  message("\nPAXDAY 原始记录（人-日）：", nrow(paxday),
          "，申报个体数：", length(unique(paxday$SEQN)))

  paxday <- paxday %>%
    mutate(valid_day = !is.na(valid_min) & valid_min >= ACC_MIN_VALID_MIN &
                        !is.na(day_mims)  & day_mims > 0)

  acc_person <- paxday %>%
    group_by(SEQN, cycle) %>%
    summarise(n_valid_days = sum(valid_day, na.rm = TRUE),
              acc_mims     = mean(day_mims[valid_day], na.rm = TRUE),
              .groups = "drop") %>%
    filter(n_valid_days >= ACC_MIN_VALID_DAYS, is.finite(acc_mims))

  message("符合有效天标准（≥", ACC_MIN_VALID_MIN, " 分钟/天 且 ≥",
          ACC_MIN_VALID_DAYS, " 天）的个体：", nrow(acc_person))

  dat_pam <- dat %>% inner_join(acc_person, by = c("SEQN", "cycle"))
  n_pam_case <- sum(dat_pam$psoriasis == 1, na.rm = TRUE)
  message("加速度计子样本 n = ", nrow(dat_pam), "，其中银屑病病例 = ", n_pam_case)
  if (n_pam_case < 200)
    message("⚠️ 加速度计臂病例 < 200 → 仅作探索性敏感性分析，不得作为主结论依据")
  saveRDS(dat_pam, file.path(PROJ_DIR, "data", "analytic_pam.rds"))
} else {
  message("\n未找到 ", ACC_PREFIX, " 文件，跳过加速度计子样本")
}

# ---------- 保存 -------------------------------------------------------------
saveRDS(dat, file.path(PROJ_DIR, "data", "analytic.rds"))
message("\n主分析数据集 n = ", nrow(dat), "（病例 ", n_case, "）")

message("\n--- PA 分组分布 ---");      print(table(dat$pa_group, useNA = "ifany"))
message("\n--- 银屑病患病率（按 PA 分组）---")
print(round(prop.table(table(dat$pa_group, dat$psoriasis), 1) * 100, 2))

sink(type = "message"); sink(); close(log_con)
message("日志：output/log_02_build.txt")
