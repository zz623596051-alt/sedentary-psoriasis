# ============================================================================
# _dryrun_test.R —— 干跑测试：用合成 NHANES 数据跑通生产代码路径
# 运行：Rscript R/_dryrun_test.R
# 特点：直接调用 02 使用的 lib_derive.R 纯函数（测试即验证生产逻辑）
# ============================================================================
Sys.setlocale("LC_CTYPE", "en_US.UTF-8")
.libPaths(c("C:/Users/Lay/.workbuddy/binaries/R/library", .libPaths()))

source("R/config.R")
source("R/lib_derive.R")

out <- file("R/_dryrun_report.txt", open = "wt", encoding = "UTF-8")
sink(out, split = TRUE)

pass <- 0; fail <- 0
chk <- function(cond, label, detail = "") {
  if (isTRUE(cond)) { pass <<- pass + 1; cat(sprintf("[PASS] %s\n", label)) }
  else { fail <<- fail + 1; cat(sprintf("[FAIL] %s  %s\n", label, detail)) }
}

cat("=== 干跑测试（合成数据，走生产代码路径）", format(Sys.time()), "===\n\n")

# ---------- 1. 构造合成 NHANES 数据 ----------------------------------------
set.seed(20261003)
mk_cycle <- function(cyc, n, n_case) {
  tibble::tibble(
    SEQN = seq_len(n) + (match(cyc, NHANES_CYCLES) - 1) * 1e5,
    cycle = cyc,
    # 年龄避开 77/99（NHANES 缺失编码，否则会被 clean_num 置为 NA）
    age = sample(20:76, n, TRUE),
    sex = sample(1:2, n, TRUE),
    race = sample(1:5, n, TRUE),
    edu = sample(1:5, n, TRUE),
    # 妊娠标记放在最后一行（对照），避免与"病例在前"的构造冲突
    preg = replace(rep(NA_real_, n), n, 1),
    wt_2yr = runif(n, 2e4, 2e5),
    psu = sample(1:15, n, TRUE),
    strata = sample(1:15, n, TRUE),
    pir = round(runif(n, 0.5, 5), 2),
    # 银屑病结局
    psoriasis_ever   = c(rep(1L, n_case), rep(2L, n - n_case - 3),
                         7L, 9L, NA_integer_),
    psoriasis_degree = c(sample(1:4, n_case, TRUE), rep(NA_integer_, n - n_case)),
    arthritis_type   = c(rep(3L, max(1, round(n_case * .2))),
                         rep(99L, n - max(1, round(n_case * .2)))),
    med_psoriasis    = c(sample(c(TRUE, FALSE), n_case, TRUE, prob = c(.4, .6)),
                         rep(FALSE, n - n_case)),
    # 体力活动
    pa_vig_work_yn = 1, pa_vig_work_d = 3, pa_vig_work_min = 30,
    pa_mod_work_yn = 1, pa_mod_work_d = 5, pa_mod_work_min = 30,
    pa_vig_rec_yn  = 1, pa_vig_rec_d  = 2, pa_vig_rec_min  = 20,
    pa_mod_rec_yn  = 1, pa_mod_rec_d  = 4, pa_mod_rec_min  = 40,
    # 病例的协变量保持完整（否则会被排除，且这本身是另一条待测逻辑）
    sedentary_min  = c(sample(c(120, 300, 480, 600), n_case, TRUE),
                       sample(c(120, 300, 480, 600, 999), n - n_case, TRUE)),
    # 生化 / 体格
    chol = rnorm(n, 190, 35), scr = rnorm(n, 0.9, 0.2),
    crp  = rlnorm(n, 0.5, 0.7), hdl = rnorm(n, 52, 13),
    bmi  = rnorm(n, 28, 5), waist = rnorm(n, 98, 14),
    # 糖代谢
    hba1c = rnorm(n, 5.6, 0.8), glu_fast = rnorm(n, 100, 18),
    # 问卷
    dm_told = sample(1:2, n, TRUE), htn_told = sample(1:2, n, TRUE),
    smoke_100 = sample(1:2, n, TRUE), smoke_now = sample(1:3, n, TRUE),
    alc_12m = sample(1:2, n, TRUE), alc_freq = sample(1:6, n, TRUE),
    alc_amt = sample(0:5, n, TRUE)
  )
}
raw <- dplyr::bind_rows(
  mk_cycle("F", 2000, 15),
  mk_cycle("G", 1800, 14),
  mk_cycle("H", 1700, 13)
)
cat(sprintf("合成数据：n = %d，周期 = %s\n\n", nrow(raw), paste(unique(raw$cycle), collapse = "/")))

# ---------- 2. 变量推导 ------------------------------------------------------
dat <- derive_psoriasis_vars(raw)

chk(nrow(dat) == nrow(raw), "推导不改变行数")
need_cols <- c("female","met_total","pa_group","sed_q","smoke","alc_gday",
               "diabetes","hypertension","egfr","psoriasis","pso_severity",
               "pso_moderate_severe","psoriatic_arthritis","psoriasis_confirmed")
chk(all(need_cols %in% names(dat)), "派生变量齐全",
    paste(setdiff(need_cols, names(dat)), collapse = ","))

# --- 银屑病结局映射（含 7/9 → NA）---
tb <- table(dat$psoriasis, useNA = "ifany")
chk(sum(dat$psoriasis == 1, na.rm = TRUE) == 42, "病例数映射正确 (=42)",
    sprintf("实际 %d", sum(dat$psoriasis == 1, na.rm = TRUE)))
chk(sum(is.na(dat$psoriasis)) == 9, "7/9/NA → 缺失 (=9)",
    sprintf("实际 %d", sum(is.na(dat$psoriasis))))

# --- MET 计算：8*30*3 + 4*30*5 + 8*20*2 + 4*40*4 = 720+600+320+640 = 2280 ---
chk(all(dat$met_total == 2280, na.rm = TRUE), "MET-min/wk 计算 (=2280)",
    sprintf("示例 %.0f", dat$met_total[1]))
chk(all(as.character(dat$pa_group) == "moderate"), "PA 分组 (2280 → moderate)")
chk(sum(dat$sed_q == 1 & dat$sedentary_min == 120, na.rm = TRUE) > 0,
    "久坐四分位计算")

# --- 缺失编码清洗：sedentary_min=999 → NA ---
chk(sum(is.na(dat$sedentary_min)) > 0, "NHANES 缺失编码 999 已清洗为 NA")

# --- 严重度 ---
chk(all(is.na(dat$pso_severity[dat$psoriasis != 1 | is.na(dat$psoriasis)])),
    "严重度仅病例有值")
chk(sum(dat$pso_moderate_severe == 1, na.rm = TRUE) ==
      sum(dat$pso_severity >= 3, na.rm = TRUE), "中重度判定一致")
chk(sum(dat$psoriatic_arthritis == 1) == 9,
    "银屑病关节炎判定（MCQ195==3）",
    sprintf("实际 %d", sum(dat$psoriatic_arthritis == 1)))
chk(sum(dat$psoriasis_confirmed == 1) > 0 &&
      all(dat$psoriasis_confirmed[dat$psoriasis != 1 | is.na(dat$psoriasis)] == 0),
    "用药确认病例逻辑（仅病例可确认）")

# --- eGFR 合理性 ---
chk(all(dat$egfr > 0 & dat$egfr < 200, na.rm = TRUE), "eGFR 取值范围合理",
    sprintf("范围 %.1f-%.1f", min(dat$egfr, na.rm=T), max(dat$egfr, na.rm=T)))

# --- 饮酒换算 ---
chk(all(dat$alc_gday[dat$alc_12m == 2] == 0), "不饮酒者 g/d = 0")
chk(all(dat$alc_gday[dat$alc_12m == 1] == dat$alc_amt[dat$alc_12m == 1] * 14),
    "饮酒 g/d 换算 = 杯数 × 14")

# --- 吸烟三分类 ---
chk(setequal(na.omit(unique(as.character(dat$smoke))),
             c("never", "former", "current")), "吸烟三分类取值正确")

# ---------- 3. 排除流程 ------------------------------------------------------
ex <- apply_exclusions(dat)
d2 <- ex$dat
chk(nrow(ex$flow) == 5, "flow 记录 5 步", sprintf("实际 %d", nrow(ex$flow)))
chk(ex$flow$n[1] == nrow(dat), "flow 首行 = 原始行数")
chk(all(diff(ex$flow$n) <= 0), "flow 单调不增（排除逻辑正确）")
chk(all(d2$age >= 20), "排除年龄 < 20")
chk(!any(d2$preg == 1, na.rm = TRUE), "排除妊娠")
chk(!any(is.na(d2$psoriasis)), "排除银屑病结局缺失")
chk(!any(is.na(d2$smoke)), "排除吸烟缺失")
chk(!any(is.na(d2$edu)), "排除教育缺失")
# 病例数应保留（case 的协变量都是完整的）
chk(sum(d2$psoriasis == 1) == 42, "排除后病例数仍为 42",
    sprintf("实际 %d", sum(d2$psoriasis == 1)))

# ---------- 4. 权重与抽样单元 ------------------------------------------------
d3 <- attach_weights(d2)
chk(all(abs(d3$wt_combined - d3$wt_2yr / 3) < 1e-9), "合并权重 = wt_2yr / 3")
chk(all(grepl("^(F|G|H)_", d3$strata_u)), "strata_u 带周期前缀")
chk(all(grepl("^(F|G|H)_", d3$psu_u)), "psu_u 带周期前缀")
chk(length(unique(d3$strata_u)) == length(unique(paste(d3$cycle, d3$strata))),
    "strata_u 唯一化正确")

# ---------- 5. EPV 校验 ------------------------------------------------------
e <- epv_check(d3)
chk(e$case == 42 && e$ctrl == nrow(d3) - 42, "EPV 计数正确",
    sprintf("case=%d ctrl=%d", e$case, e$ctrl))
chk(e$epv == e$case / PSO_MAIN_PARAMS, "EPV 公式正确", sprintf("EPV=%.2f", e$epv))
chk(is.logical(e$ok), "EPV 返回判定标志")

# ---------- 6. 边界：真实规模的 EPV 是否符合预期 ------------------------------
real_epv <- PSO_EXPECTED_CASES / PSO_MAIN_PARAMS
chk(real_epv >= 10, "真实预期 EPV ≥ 10（核查数据 520 例 / 14 参数）",
    sprintf("EPV=%.1f", real_epv))

cat(sprintf("\n=== 干跑结果：PASS %d / FAIL %d ===\n", pass, fail))
sink(); close(out)
cat(sprintf("PASS %d, FAIL %d\n", pass, fail))
