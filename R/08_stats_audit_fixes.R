# ============================================================================
# 08_stats_audit_fixes.R —— 统计审查（nature-statistics）触发的修正与补测
# 运行：Rscript R/08_stats_audit_fixes.R
# 产出：output/tables/audit_*.csv + output/log_08_audit.txt
#
# 修的是 03 里三处统计缺陷 + 补齐审查要求的报告项：
#   A) 「非线性检验」名不符实 —— 原实现用 regTermTest（样条整体显著性），
#      并不检验非线性。补真正的「线性 vs 样条」对比检验。
#   B) 敏感性分析的暴露单位错标 —— 模型用的是 met_total（每 1 MET-min/wk），
#      初稿却标成「per 1,000 MET-min/wk」，差 1000 倍。重算并补 EPV 合规模型。
#   C) 亚组交互：原实现把 race 当**数值**与主模型的 factor(race) 不一致；
#      且用 min(p) 汇总。改为设定一致的**联合 Wald 检验**。
#   D) 主要暴露家族的多重比较校正（BH-FDR）。
#   E) 缺失数据：逐变量缺失量 + 纳入/排除者的差异比较（选择性偏倚）
# ============================================================================

Sys.setlocale("LC_CTYPE", "en_US.UTF-8")
source("R/config.R")
source("R/lib_derive.R")

log_con <- file(file.path(OUT_DIR, "log_08_audit.txt"), open = "wt", encoding = "UTF-8")
sink(log_con, split = TRUE)
sink(log_con, type = "message")
options(error = function() {
  try(sink(type = "message"), silent = TRUE); try(sink(), silent = TRUE)
  cat("\n===== R ERROR 调用栈 =====\n"); traceback(3); q(status = 1)
})

suppressPackageStartupMessages({
  library(survey); library(dplyr); library(splines); library(tidyr); library(tibble)
})
options(survey.lonely.psu = "adjust")

dat <- readRDS(file.path(PROJ_DIR, "data", "analytic.rds"))
des <- svydesign(ids = ~psu_u, strata = ~strata_u,
                 weights = ~wt_combined, nest = TRUE, data = dat)

# 与 03 保持一致的主模型协变量（★ 2026-10-03 起已移除 total cholesterol）
COV_TERMS <- c("age","female","factor(race)","factor(edu)","pir","smoke",
               "alc_gday","hypertension","diabetes")
COV <- paste(COV_TERMS, collapse = " + ")
COV_MAIN <- c("age","female","race","edu","pir","smoke",
              "alc_gday","hypertension","diabetes")
# 去掉某个主效应（用于交互模型，避免重复主效应）
build_cov <- function(drop = NULL) {
  keep <- COV_TERMS
  if (!is.null(drop)) {
    keep <- keep[!vapply(keep, function(x)
      any(vapply(drop, function(d) grepl(d, x, fixed = TRUE), logical(1))), logical(1))]
  }
  paste(keep, collapse = " + ")
}

## ===========================================================================
## A) 真正的非线性检验
## ===========================================================================
#' 返回三个 p：
#'   p_overall_spline   = 样条项整体显著性（原实现，回答"有没有关联"）
#'   p_nonlinear_anova  = 线性 vs 样条 的 Wald 对比（回答"是否非线性"）
#'   p_nonlinear_manual = 手算 Wald（只检验非线性基函数），兜底
nonlin_test <- function(expo, use_log1p = FALSE, df = 3) {
  dd <- dat
  if (use_log1p) dd[[expo]] <- log1p(dd[[expo]])
  need <- c("psoriasis", expo, COV_MAIN, "psu_u", "strata_u", "wt_combined")
  dsub <- dd[complete.cases(dd[, need]), need]
  des2 <- svydesign(ids = ~psu_u, strata = ~strata_u,
                    weights = ~wt_combined, nest = TRUE, data = dsub)

  m_lin <- svyglm(as.formula(paste0("psoriasis ~ ", expo, " + ", COV)),
                  design = des2, family = quasibinomial())
  m_spl <- svyglm(as.formula(paste0("psoriasis ~ ns(", expo, ", df=", df, ") + ", COV)),
                  design = des2, family = quasibinomial())

  p_anova <- tryCatch({
    a <- anova(m_lin, m_spl, method = "Wald")
    if (is.data.frame(a) && nrow(a) >= 2) a$p[2] else NA_real_
  }, error = function(e) NA_real_)

  b <- coef(m_spl); V <- vcov(m_spl)
  idx <- grep(paste0("^ns\\(", expo), names(b))
  nl  <- idx[-1]                      # 第 1 个基函数近似线性，只留非线性部分
  p_manual <- NA_real_
  if (length(nl) && all(is.finite(b[nl]))) {
    bb <- b[nl]; VV <- V[nl, nl, drop = FALSE]
    W  <- tryCatch(as.numeric(t(bb) %*% solve(VV) %*% bb), error = function(e) NA_real_)
    if (is.finite(W)) {
      df1 <- length(nl); df2 <- degf(des2) - length(b)
      p_manual <- pf(W / df1, df1, df2, lower.tail = FALSE)
    }
  }

  rt <- tryCatch(regTermTest(m_spl,
                             as.formula(paste0("~ ns(", expo, ", df=", df, ")"))),
                 error = function(e) NULL)
  data.frame(exposure = expo, n = nrow(dsub),
             p_overall_spline   = if (is.null(rt)) NA_real_ else rt$p,
             p_nonlinear_anova  = p_anova,
             p_nonlinear_manual = p_manual)
}

audit_A <- bind_rows(
  nonlin_test("met_total",     use_log1p = TRUE),
  nonlin_test("sedentary_min", use_log1p = FALSE)
)
write.csv(audit_A, file.path(TAB_DIR, "audit_A_nonlinearity.csv"), row.names = FALSE)
cat("\n########## A) 非线性检验 ##########\n"); print(audit_A)

## ===========================================================================
## B) 敏感性分析：暴露单位修正 + EPV 合规模型
## ===========================================================================
sens_spec <- list(
  list(file = "sens_severity.csv",            outcome = "pso_moderate_severe",
       label = "Moderate-to-severe psoriasis"),
  list(file = "sens_confirmed_cases.csv",     outcome = "psoriasis_confirmed",
       label = "Medication-confirmed psoriasis"),
  list(file = "sens_psoriatic_arthritis.csv", outcome = "psoriatic_arthritis",
       label = "Psoriatic arthritis")
)

rows_B <- list()
for (s in sens_spec) {
  p <- file.path(TAB_DIR, s$file)
  if (!file.exists(p)) { message("缺 ", s$file); next }
  r <- read.csv(p, stringsAsFactors = FALSE)
  r <- r[r$term == "met_total", ]
  if (!nrow(r)) next
  # 原模型暴露单位是「每 1 MET-min/wk」，换算到「每 1,000 MET-min/wk」
  est1000 <- r$est * 1000; se1000 <- r$se * 1000

  n_case <- tryCatch(sum(dat[[s$outcome]] == 1, na.rm = TRUE), error = function(e) NA)
  # EPV 合规的最小调整模型：age + female（2 参数）
  m_red <- tryCatch(svyglm(as.formula(paste(s$outcome, "~ met_total + age + female")),
                           design = des, family = quasibinomial()),
                    error = function(e) NULL)
  est_r <- se_r <- NA
  if (!is.null(m_red)) {
    cc <- summary(m_red)$coefficients
    est_r <- cc["met_total", 1] * 1000; se_r <- cc["met_total", 2] * 1000
  }
  rows_B[[length(rows_B) + 1]] <- data.frame(
    outcome = s$label, cases = n_case,
    # ★ 用配置里的参数数，不要硬编码 15（换协变量集后会静默变陈旧）
    n_params = PSO_MAIN_PARAMS,
    epv_full = n_case / PSO_MAIN_PARAMS, epv_reduced = n_case / 2,
    or_full_per1000 = exp(est1000),
    lci_full = exp(est1000 - 1.96 * se1000), uci_full = exp(est1000 + 1.96 * se1000),
    p_full = r$p,
    or_reduced_per1000 = exp(est_r),
    lci_red = exp(est_r - 1.96 * se_r), uci_red = exp(est_r + 1.96 * se_r)
  )
}
audit_B <- bind_rows(rows_B)
write.csv(audit_B, file.path(TAB_DIR, "audit_B_sensitivity_units.csv"), row.names = FALSE)
cat("\n########## B) 敏感性分析（单位已修正为 per 1,000 MET-min/wk）##########\n")
print(audit_B)
message("\n★ 复核：原稿标注的 OR 是「每 1 MET-min/wk」的值，",
        "换算到每 1,000 MET-min/wk 后效应量放大约 1000 倍（指数），",
        "但 CI 同样变宽 —— 结论（不显著）不变，措辞必须改。")

## ===========================================================================
## C) 亚组交互：设定一致 + 联合 Wald 检验
## ===========================================================================
joint_int <- function(term_expr, label, drop_main) {
  f <- as.formula(paste0("psoriasis ~ met_total * ", term_expr,
                         " + ", build_cov(drop_main)))
  m <- tryCatch(svyglm(f, design = des, family = quasibinomial()),
                error = function(e) { message("  拟合失败 ", label, "：", conditionMessage(e)); NULL })
  if (is.null(m)) return(NULL)
  b <- coef(m); V <- vcov(m)
  idx <- grep(":", names(b))
  idx <- idx[is.finite(b[idx])]
  if (!length(idx)) return(NULL)
  bb <- b[idx]; VV <- V[idx, idx, drop = FALSE]
  W <- tryCatch(as.numeric(t(bb) %*% solve(VV) %*% bb), error = function(e) NA_real_)
  df1 <- length(idx); df2 <- degf(des) - length(b)
  data.frame(subgroup = label, n_int_terms = df1,
             Wald = W, df1 = df1, df2 = df2,
             p_joint = pf(W / df1, df1, df2, lower.tail = FALSE))
}
audit_C <- bind_rows(
  joint_int("female",          "Sex (female)",           "female"),
  joint_int("diabetes",        "Diabetes",               "diabetes"),
  joint_int("factor(race)",    "Race/ethnicity (4 df)",  "race")
)
write.csv(audit_C, file.path(TAB_DIR, "audit_C_interactions.csv"), row.names = FALSE)
cat("\n########## C) 亚组交互（联合 Wald 检验）##########\n"); print(audit_C)
cat("\n对照：03 原实现把 race 当数值、且用 min(p) 汇总 → 与主模型设定不一致\n")

## ===========================================================================
## D) 多重比较校正（BH-FDR）
## ===========================================================================
# ★ 必须全部从 CSV 读取，不可硬编码 —— 硬编码会在换协变量集后静默变成陈旧值
get_p <- function(file, term) {
  p <- file.path(TAB_DIR, file)
  if (!file.exists(p)) return(NA_real_)
  r <- read.csv(p, stringsAsFactors = FALSE)
  r <- r[r$term == term, ]
  if (!nrow(r)) NA_real_ else r$p[1]
}
p_family <- c(
  "PA, per 1,000 MET-min/wk"   = get_p("model_PA_continuous.csv", "met_1000"),
  "Sedentary, per 60 min/day"  = get_p("model_sedentary_continuous.csv", "sed_60"),
  "PA: low vs inactive"        = get_p("model_PA_group.csv", "factor(pa_group)low"),
  "PA: moderate vs inactive"   = get_p("model_PA_group.csv", "factor(pa_group)moderate"),
  "PA: high vs inactive"       = get_p("model_PA_group.csv", "factor(pa_group)high"),
  "Sedentary: Q2 vs Q1"        = get_p("model_sedentary_quartile.csv", "factor(sed_q)2"),
  "Sedentary: Q3 vs Q1"        = get_p("model_sedentary_quartile.csv", "factor(sed_q)3"),
  "Sedentary: Q4 vs Q1"        = get_p("model_sedentary_quartile.csv", "factor(sed_q)4"),
  "Accelerometer, per SD"      = get_p("model_accelerometer.csv", "acc_mims_z")
)
p_primary <- p_family[c("PA, per 1,000 MET-min/wk", "Sedentary, per 60 min/day")]

audit_D <- data.frame(test = names(p_family), p_raw = as.numeric(p_family),
                      row.names = NULL)
audit_D$is_primary   <- audit_D$test %in% names(p_primary)
audit_D$p_BH_all     <- p.adjust(audit_D$p_raw, method = "BH")
audit_D$p_BH_primary <- NA_real_
audit_D$p_BH_primary[audit_D$is_primary] <- p.adjust(p_primary, method = "BH")
audit_D <- audit_D[order(audit_D$p_raw), ]
write.csv(audit_D, file.path(TAB_DIR, "audit_D_multiplicity.csv"), row.names = FALSE)
cat("\n########## D) 多重比较校正（BH-FDR）##########\n"); print(audit_D)
cat("\n★ 若以全文 9 个暴露检验为家族，久坐连续 BH p =",
    round(audit_D$p_BH_all[audit_D$test == "Sedentary, per 60 min/day"], 4), "\n")
cat("★ 若按**预先指定**的 2 个主要暴露为家族，久坐连续 BH p =",
    round(audit_D$p_BH_primary[audit_D$test == "Sedentary, per 60 min/day"], 4),
    "（primary_exposures_BH.csv 应与此一致）\n")

## ===========================================================================
## E) 缺失数据：逐变量缺失量 + 纳入/排除者差异
## ===========================================================================
read_cyc <- function(pref, cyc) {
  f <- file.path(RAW_DIR, paste0(pref, "_", cyc, ".rds"))
  if (file.exists(f)) readRDS(f) else NULL
}
MODULES <- c("DEMO","PAQ","BIOPRO","HDL","CRP","BMX","GHB","GLU",
             "DIQ","BPQ","ALQ","SMQ","MCQ","INQ")
build_cycle_audit <- function(cyc) {
  mods <- lapply(MODULES, function(m) read_cyc(m, cyc))
  names(mods) <- MODULES
  d <- build_cycle_frame(mods, cyc)
  rx <- collapse_medications(read_cyc("RXQ_RX", cyc))
  if (!is.null(rx)) d <- left_join(d, rx, by = "SEQN") else d$med_psoriasis <- NA
  d
}
message("\n重建排除前数据集（用于缺失分析，耗时约 1 分钟）...")
step3 <- bind_rows(lapply(NHANES_CYCLES, build_cycle_audit)) %>%
  derive_psoriasis_vars() %>%
  filter(age >= AGE_MIN) %>%
  filter(is.na(preg) | preg != 1) %>%
  filter(!is.na(psoriasis))
step3 <- attach_weights(step3)
message("排除至「有银屑病结局」后 n = ", nrow(step3))

cov_used <- c("age","female","race","edu","pir","smoke","sedentary_min")
miss_tab <- data.frame(
  variable = cov_used,
  n_missing = vapply(cov_used, function(v) sum(is.na(step3[[v]])), 1L)
)
miss_tab$pct_missing <- round(100 * miss_tab$n_missing / nrow(step3), 2)
miss_tab <- miss_tab[order(-miss_tab$n_missing), ]
write.csv(miss_tab, file.path(TAB_DIR, "audit_E_missingness.csv"), row.names = FALSE)
cat("\n########## E1) 逐变量缺失量（分母 n =", nrow(step3), "）##########\n")
print(miss_tab)

# ★ 纳入/排除的判定必须与 lib_derive::apply_exclusions 用**同一组协变量**，
#   否则这里算出的 n 与流程图对不上（2026-10-03 实测踩过）。
MODEL_COVARS <- c("age","female","race","edu","pir","smoke",
                  "sedentary_min","alc_gday","hypertension","diabetes")
step3$included <- !Reduce(`|`, lapply(MODEL_COVARS, function(v) is.na(step3[[v]])))
n_incl_step3 <- sum(step3$included)
n_incl_dat  <- sum(complete.cases(dat[, c("psoriasis", MODEL_COVARS)]))
message(sprintf("[核对] step3 完整=%d | analytic.rds 完整=%d | nrow(dat)=%d",
                n_incl_step3, n_incl_dat, nrow(dat)))
# ★ stopifnot() 的所有参数都按「条件」求值，**不能传字符串当错误信息**
#   （字符串不是逻辑 TRUE，会报 "xxx is not TRUE"，掩盖真实比较结果）——
#   实测踩过：两个数明明相等却仍报错。要带信息就用 stop()。
if (n_incl_step3 != n_incl_dat)
  stop(sprintf("纳入判定与 analytic.rds 不一致（step3=%d, dat=%d）—— 排除条件已变，请同步",
               n_incl_step3, n_incl_dat))
message(sprintf("纳入 %d / 排除 %d（应与分析集 n 一致）",
                sum(step3$included), sum(!step3$included)))
cmp <- step3 %>% group_by(included) %>%
  summarise(n = n(),
            psoriasis_n = sum(psoriasis == 1, na.rm = TRUE),
            psoriasis_pct = round(100 * mean(psoriasis == 1, na.rm = TRUE), 2),
            age_mean = round(mean(age, na.rm = TRUE), 1),
            female_pct = round(100 * mean(female == 1, na.rm = TRUE), 1),
            sedentary_mean = round(mean(sedentary_min, na.rm = TRUE), 1),
            met_mean = round(mean(met_total, na.rm = TRUE), 1),
            .groups = "drop")
write.csv(cmp, file.path(TAB_DIR, "audit_E_included_vs_excluded.csv"), row.names = FALSE)
cat("\n########## E2) 纳入 vs 排除者比较 ##########\n"); print(as.data.frame(cmp))

# 患病率差异的卡方检验（未加权，仅作提示）
tb <- table(step3$included, step3$psoriasis)
p_chisq <- tryCatch(chisq.test(tb)$p.value, error = function(e) NA_real_)
cat(sprintf("\n纳入/排除 × 银屑病 卡方检验 p = %.4f（未加权）\n", p_chisq))

## ===========================================================================
## F) 中介变量缺失 + 主模型去掉 PIR 的稳健性（PIR 是唯一实质缺失来源）
## ===========================================================================
cat("\n########## F1) 中介变量与分析集缺失情况 ##########\n")
for (v in c("bmi", "crp")) {
  cat(sprintf("  %s：分析集中缺失 %d / %d (%.1f%%)\n",
              v, sum(is.na(dat[[v]])), nrow(dat), 100 * mean(is.na(dat[[v]]))))
}

# step3（n = 17,342）保留全部有结局者；PIR 缺失 1,552 例 → 去掉 PIR 可回收样本
s3 <- step3 %>%
  mutate(met_1000 = met_total / 1000, sed_60 = sedentary_min / 60)
des3 <- svydesign(ids = ~psu_u, strata = ~strata_u,
                  weights = ~wt_combined, nest = TRUE, data = s3)
COV_NOPIR <- build_cov("pir")

rows_F <- list()
for (nm in c("met_1000", "sed_60")) {
  m <- tryCatch(svyglm(as.formula(paste("psoriasis ~", nm, "+", COV_NOPIR)),
                       design = des3, family = quasibinomial()),
                error = function(e) { message("  拟合失败 ", nm, "：", conditionMessage(e)); NULL })
  if (is.null(m)) next
  cc <- summary(m)$coefficients
  rows_F[[length(rows_F) + 1]] <- data.frame(
    model = ifelse(nm == "met_1000", "PA per 1,000 MET-min/wk", "Sedentary per 60 min/day"),
    n = length(resid(m)),
    OR = exp(cc[nm, 1]),
    lci = exp(cc[nm, 1] - 1.96 * cc[nm, 2]),
    uci = exp(cc[nm, 1] + 1.96 * cc[nm, 2]),
    p = cc[nm, 4])
}
audit_F <- bind_rows(rows_F)
write.csv(audit_F, file.path(TAB_DIR, "audit_F_no_pir.csv"), row.names = FALSE)
cat("\n########## F2) 主模型剔除 PIR（回收 PIR 缺失者）##########\n")
print(audit_F)
cat("\n★ 与含 PIR 的主模型对照：n=15,701；PA 0.996 (0.974-1.018)；久坐 1.067 (1.016-1.120)\n")

sink(type = "message"); sink(); close(log_con)
cat("\n审查补测完成，结果见 output/tables/audit_*.csv\n")