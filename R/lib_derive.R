# ============================================================================
# lib_derive.R —— 纯函数：变量推导与排除流程
# 供 02_build_dataset.R 与 _dryrun_test.R 共用（同一套代码，测试即验证生产逻辑）
# 依赖：config.R 已 source（使用其中常量）
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(tibble)
})

NA_CODES <- c(7, 9, 77, 99, 777, 999, 7777, 9999, 5555, 6666)

#' ★ 仅这些**问卷变量**使用哨兵缺失码，需要清洗。
#' 连续变量（age/bmi/waist/chol/hdl/crp/scr/hba1c/glu_fast/pir）**不清洗**——
#' NHANES 对它们用空白表示缺失，其数字（如 HbA1c=7、腰围=99）都是真值。
QNA_VARS <- c("edu", "dm_told", "htn_told", "alc_12m", "smoke_100", "smoke_now",
              "sedentary_min", "alc_amt", "alc_freq")

clean_num <- function(x, codes = NA_CODES) { x[x %in% codes] <- NA; x }

#' ★ 从单个 NHANES 模块抽取所需变量，并统一列名
#'
#' 关键：NHANES 各模块行数不同（如 DEMO_F=10537 行、MCQ_F=10109 行），
#' **绝不能按行位置对齐**，必须以 SEQN 为键连接。
#'
#' @param df     模块数据框（含 SEQN）
#' @param keymap 命名列表：names = 标准列名，values = NHANES 原始变量名
#' @return tibble(SEQN, ...)，缺失变量补 NA；df 为 NULL 或缺 SEQN 时返回 NULL
pull_module <- function(df, keymap) {
  if (is.null(df) || !("SEQN" %in% names(df))) return(NULL)
  out <- tibble::tibble(SEQN = df$SEQN)
  for (k in names(keymap)) {
    v <- keymap[[k]]
    out[[k]] <- if (!is.null(v) && v %in% names(df)) df[[v]] else NA
  }
  out
}

#' 按 SEQN 依次左连接多个模块
#' @param base 必须含 SEQN 的基底 tibble
#' @param mods list of tibble（各含 SEQN）
join_modules <- function(base, mods) {
  out <- base
  for (m in mods) {
    if (is.null(m) || !nrow(m)) next
    out <- dplyr::left_join(out, m, by = "SEQN")
  }
  out
}

#' 合并后的原始 NHANES 数据（单周期）——纯函数，供 02 与测试共用
#'
#' @param modules list(模块名 = 模块数据框)，模块名用于查 config 的映射
#' @param cyc     周期字母
#' @return 标准列名的 tibble
build_cycle_frame <- function(modules, cyc) {
  demo <- modules[["DEMO"]]
  if (is.null(demo) || !("SEQN" %in% names(demo)))
    stop("周期 ", cyc, " 缺 DEMO 或 DEMO 无 SEQN")

  base <- tibble::tibble(SEQN = demo$SEQN)

  # 各模块 → 标准列名 的映射（取 config 的 VARMAP）
  # ★ 实测修正：pir(INDFMPIR) 在 DEMO 中，不在 INQ；
  #             crp(LBXCRP) 在独立 CRP 文件中，不在 BIOPRO
  mp <- list(
    DEMO   = c("age","sex","race","edu","preg","wt_2yr","psu","strata","pir"),
    MCQ    = c("psoriasis_ever","psoriasis_degree","arthritis_type"),
    PAQ    = c("pa_vig_work_yn","pa_vig_work_d","pa_vig_work_min",
               "pa_mod_work_yn","pa_mod_work_d","pa_mod_work_min",
               "pa_vig_rec_yn","pa_vig_rec_d","pa_vig_rec_min",
               "pa_mod_rec_yn","pa_mod_rec_d","pa_mod_rec_min","sedentary_min"),
    BIOPRO = c("chol","scr"),
    CRP    = c("crp"),
    HDL    = c("hdl"),
    BMX    = c("bmi","waist"),
    GHB    = c("hba1c"),
    GLU    = c("glu_fast"),
    DIQ    = c("dm_told"),
    BPQ    = c("htn_told"),
    SMQ    = c("smoke_100","smoke_now"),
    ALQ    = c("alc_12m","alc_freq","alc_amt")
  )

  mods <- list()
  for (nm in names(mp)) {
    keys <- intersect(mp[[nm]], names(VARMAP))   # 防 VARMAP 缺项导致 NA 列名
    if (!length(keys)) next
    m <- pull_module(modules[[nm]], VARMAP[keys])
    if (!is.null(m)) mods[[nm]] <- m
  }

  out <- join_modules(base, mods)
  out$cycle <- cyc
  out$year  <- NHANES_YEARS[match(cyc, NHANES_CYCLES)]
  out
}

#' 药物标记：从 RXQ_RX 折叠到个体（银屑病确认用药）
collapse_medications <- function(rx, keywords = PSO_MED_KEYWORDS) {
  if (is.null(rx) || !all(c("SEQN","RXDDRUG") %in% names(rx)))
    return(NULL)
  drug <- tolower(rx$RXDDRUG)
  hit <- Reduce(`|`, lapply(keywords, function(k) grepl(k, drug, fixed = TRUE)))
  if (is.null(hit)) hit <- rep(FALSE, nrow(rx))
  tibble::tibble(SEQN = rx$SEQN, .hit = hit) %>%
    dplyr::group_by(SEQN) %>%
    dplyr::summarise(med_psoriasis = any(.hit, na.rm = TRUE), .groups = "drop")
}

#' 从合并后的原始 NHANES 数据推导分析变量（含银屑病结局）
#' @param raw 含 SEQN/cycle 及各原始变量的 tibble
#' @return 含派生变量的 tibble（尚未做排除）
derive_psoriasis_vars <- function(raw) {
  dat <- raw %>%
    # ★★ 只对**问卷变量**清洗哨兵缺失码（7=拒答 / 9=不知道 / 77 / 99 / 7777 / 9999）。
    #    NHANES 的实验室与体测变量用「空白」表示缺失，其数字全是真值——
    #    实测反例：LBXGH 含 7 和 9（真实的 7%、9% HbA1c）；
    #              BMXWAIST / LBXSCH / LBDHDD / LBXGLU 含 77 和 99（真实测量值）；
    #              RIDAGEYR 含 77（真实年龄，仅 80 岁截尾）。
    #    早期版本把上述变量一并清洗，属错误，已修正。
    mutate(across(any_of(QNA_VARS), clean_num)) %>%
    mutate(
      female = as.integer(sex == 2),

      # --- 体力活动 MET-min/week（8 MET 剧烈 / 4 MET 中等）---
      met_vig = 8 * coalesce(pa_vig_work_min, 0) * coalesce(pa_vig_work_d, 0) +
                8 * coalesce(pa_vig_rec_min, 0)  * coalesce(pa_vig_rec_d, 0),
      met_mod = 4 * coalesce(pa_mod_work_min, 0) * coalesce(pa_mod_work_d, 0) +
                4 * coalesce(pa_mod_rec_min, 0)  * coalesce(pa_mod_rec_d, 0),
      met_total = met_vig + met_mod,
      pa_group  = cut(met_total, breaks = c(-1, 0, 600, 3000, Inf),
                      labels = c("inactive", "low", "moderate", "high")),
      sed_q     = ntile(sedentary_min, 4),

      # --- 吸烟 ---
      smoke = factor(case_when(
        smoke_100 == 1 & smoke_now %in% c(1, 2) ~ "current",
        smoke_100 == 1 & smoke_now == 3          ~ "former",
        smoke_100 == 2                            ~ "never",
        TRUE ~ NA_character_
      ), levels = c("never", "former", "current")),

      # --- 饮酒 g/d（1 标准杯 ≈ 14 g）---
      alc_gday = ifelse(!is.na(alc_12m) & alc_12m == 1, coalesce(alc_amt, 0) * 14, 0),

      # --- 糖尿病 / 高血压 ---
      diabetes = as.integer(dm_told == 1 | (!is.na(hba1c) & hba1c >= 6.5) |
                            (!is.na(glu_fast) & glu_fast >= 126)),
      hypertension = as.integer(htn_told == 1),

      # --- eGFR（CKD-EPI 2021, race-free）---
      egfr = {
        k <- ifelse(female == 1, 0.7, 0.9)
        a <- ifelse(female == 1, -0.241, -0.302)
        142 * pmin(scr / k, 1)^a * pmax(scr / k, 1)^(-1.200) *
          0.9938^age * ifelse(female == 1, 1.012, 1)
      },

      # --- ★ 银屑病结局（MCQ070：1=Yes 2=No；7/9 视为缺失）---
      psoriasis = case_when(
        psoriasis_ever == 1 ~ 1L,
        psoriasis_ever == 2 ~ 0L,
        TRUE ~ NA_integer_
      ),
      pso_severity = ifelse(!is.na(psoriasis_degree) & psoriasis_degree %in% 1:4,
                            as.integer(psoriasis_degree), NA_integer_),
      pso_moderate_severe = as.integer(!is.na(pso_severity) & pso_severity >= 3),
      psoriatic_arthritis = as.integer(!is.na(arthritis_type) &
                                         arthritis_type == PSO_ARTHRITIS_PSA_CODE),
      psoriasis_confirmed = as.integer(!is.na(psoriasis) & psoriasis == 1 &
                                         coalesce(med_psoriasis, FALSE))
    )
  dat
}

#' 应用排除流程，同时记录 flow
#' @return list(dat = 保留数据, flow = tibble(step, n))
apply_exclusions <- function(dat) {
  flow <- tibble(step = "0. 合并原始样本（2009-2014）", n = nrow(dat))
  step <- function(d, label) {
    flow <<- add_row(flow, step = label, n = nrow(d)); d
  }
  dat <- dat %>% filter(age >= AGE_MIN)                          %>% step("1. 年龄 >= 20")
  dat <- dat %>% filter(is.na(preg) | preg != 1)                 %>% step("2. 排除妊娠")
  dat <- dat %>% filter(!is.na(psoriasis))                       %>% step("3. 有银屑病结局（MCQ070）")
  # ★★ 2026-10-03 修正：排除条件必须与主模型协变量**完全相同**。
  #   原实现只查 7 个变量，而模型用了其中的 9 个 + chol，导致 chol 缺失的
  #   1,633 例被 svyglm 静默 na.omit ——「流程图 n」与「模型实际 n」不一致
  #   （15,701 vs 14,287）。现补齐 alc_gday / hypertension / diabetes，
  #   并已把 chol 移出模型，使两者严格相等。
  #   ★ 若将来改模型协变量，**必须同步改这一行**。
  MODEL_COVARS <- c("age","female","race","edu","pir","smoke",
                    "sedentary_min","alc_gday","hypertension","diabetes")
  dat <- dat %>% filter(if_all(all_of(MODEL_COVARS), ~ !is.na(.x))) %>%
                                                                  step("4. 协变量完整（主模型）")
  list(dat = dat, flow = flow)
}

#' 附着合并权重与唯一抽样单元 ID
attach_weights <- function(dat) {
  n_cyc <- length(unique(dat$cycle))
  dat %>% mutate(
    wt_combined = wt_2yr / n_cyc,
    strata_u = paste(cycle, strata, sep = "_"),
    psu_u    = paste(cycle, psu,    sep = "_")
  )
}

#' ★ EPV 功效校验
#' @return list(case, ctrl, epv, ok)
epv_check <- function(dat, n_params = PSO_MAIN_PARAMS) {
  n_case <- sum(dat$psoriasis == 1, na.rm = TRUE)
  n_ctrl <- sum(dat$psoriasis == 0, na.rm = TRUE)
  epv    <- n_case / n_params
  list(case = n_case, ctrl = n_ctrl, epv = epv, ok = epv >= 10)
}
