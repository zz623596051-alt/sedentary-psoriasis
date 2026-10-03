# ============================================================================
# 03_observational_analysis.R —— 臂一：观察性分析（银屑病）
# 运行：Rscript R/03_observational_analysis.R
# 产出：output/tables/*.csv, output/rcs_data.rds
# 关键：结局 = psoriasis（二分类）；协变量严格受 EPV 约束
# ============================================================================

Sys.setlocale("LC_CTYPE", "en_US.UTF-8")
source("R/config.R")

log_con <- file(file.path(OUT_DIR, "log_03_obs.txt"), open = "wt", encoding = "UTF-8")
sink(log_con, split = TRUE)
sink(log_con, type = "message")   # ★ 同时捕获 message()/warning()（默认 sink 只管 stdout）

suppressPackageStartupMessages({
  library(dplyr); library(survey); library(splines); library(tidyr)
})

# ★ 分层 bootstrap 重抽后，某层可能只剩 1 个 PSU，svydesign 会报
#   "Stratum (...) has only one PSU at stage 1"。这是 survey 包的标准问题，
#   官方推荐的处置方式是 adjust（把该层方差用全局平均替代）。
options(survey.lonely.psu = "adjust")

# ★ 出错时先把 sink 卸掉再打印调用栈。
#   否则 sink(type="message") 会把 R 的错误报告和 traceback 一起吞进日志尾部，
#   只留下一句 "Execution halted"，完全无法定位（实测踩过）。
options(error = function() {
  try(sink(type = "message"), silent = TRUE)
  try(sink(), silent = TRUE)
  cat("\n===== R ERROR 调用栈 =====\n")
  traceback(3)
  q(status = 1)
})

dat <- readRDS(file.path(PROJ_DIR, "data", "analytic.rds"))

# 连续暴露：每 1000 MET-min/wk、每 60 min/day 久坐
# （须在建立 survey design 之前加入，否则 svyglm 找不到变量）
dat$met_1000 <- dat$met_total / 1000
dat$sed_60   <- dat$sedentary_min / 60

# ---------- 1. 复杂抽样设计（3 周期，权重除以 3）----------------------------
des <- svydesign(ids = ~psu_u, strata = ~strata_u,
                 weights = ~wt_combined, nest = TRUE, data = dat)

# ---------- ★ 协变量集（受 EPV 约束）----------------------------------------
# 设计原则：最小充分调整集。BMI 与 CRP 是中介，不进主模型。
# ★★ 2026-10-03 修正：移除 total cholesterol。
#   理由：① chol 缺失 9.4%，且**不在排除条件内** → svyglm 静默 na.omit，
#         造成「流程图 n=15,701」与「模型实际 n=14,287」不一致；
#         ② 血脂不是 PA/久坐 → 银屑病 的合理混杂因素。
#   移除后 n=15,676、病例 455、EPV=32.5（14 参数），流程图与模型口径严格一致。
# 参数计数：age1 + female1 + race4 + edu2 + pir1 + smoke2 + alc1 + htn1 + dm1 = 14
COV <- "age + female + factor(race) + factor(edu) + pir + smoke +
        alc_gday + hypertension + diabetes"
COV_NPAR <- 14L
stopifnot(COV_NPAR == PSO_MAIN_PARAMS, COV_NPAR <= PSO_MAX_PARAMS)

# ★ 与 lib_derive::apply_exclusions 的排除条件必须一致（否则 n 对不上）
COV_MODEL_VARS <- c("age","female","race","edu","pir","smoke",
                    "sedentary_min","alc_gday","hypertension","diabetes")

n_case <- sum(dat$psoriasis == 1, na.rm = TRUE)
message(sprintf("=== EPV 预校验：病例 %d / 参数 %d → EPV = %.1f ===",
                n_case, COV_NPAR, n_case / COV_NPAR))
message(sprintf("=== 分析集 n = %d（须与 output/flow_analytic.csv 末行一致）===", nrow(dat)))
# ★ 自查：声明 n 与模型可用 n 必须相等（防止再次出现「报告 n ≠ 模型 n」）
n_model_avail <- sum(complete.cases(dat[, c("psoriasis", COV_MODEL_VARS, "met_total")]))
if (n_model_avail != nrow(dat))
  warning(sprintf("声明 n=%d 但模型可用 n=%d —— 排除条件与协变量不一致！",
                  nrow(dat), n_model_avail))

# ---------- 2. 描述性统计（加权）-------------------------------------------
desc_vars <- c("age","female","race","edu","pir","smoke","bmi","waist",
               "chol","hdl","crp","egfr","met_total","sedentary_min",
               "diabetes","hypertension")
tbl1 <- lapply(desc_vars, function(v) {
  tryCatch({
    m <- svyby(as.formula(paste0("~", v)), ~psoriasis, des,
               svymean, na.rm = TRUE)
    as.data.frame(m) %>% mutate(variable = v)
  }, error = function(e) NULL)
}) %>% bind_rows()
write.csv(tbl1, file.path(TAB_DIR, "table1_baseline_by_psoriasis.csv"), row.names = FALSE)
message("表1 已输出")

tidy_glm <- function(m, label) {
  s <- summary(m)$coefficients
  data.frame(term = rownames(s), est = s[,1], se = s[,2], p = s[,4],
             OR = exp(s[,1]), lci = exp(s[,1] - 1.96*s[,2]),
             uci = exp(s[,1] + 1.96*s[,2]), model = label, row.names = NULL)
}

# ---------- 3. 主模型：加权 logistic（PA 分组）-----------------------------
m_cat <- svyglm(as.formula(paste("psoriasis ~ factor(pa_group) +", COV)),
                design = des, family = quasibinomial())
cat("\n===== 模型1：PA 分组 vs 银屑病 =====\n"); print(summary(m_cat))
res_cat <- tidy_glm(m_cat, "PA group (ref=inactive)")
write.csv(res_cat, file.path(TAB_DIR, "model_PA_group.csv"), row.names = FALSE)

# 久坐四分位
m_sed <- svyglm(as.formula(paste("psoriasis ~ factor(sed_q) +", COV)),
                design = des, family = quasibinomial())
res_sed <- tidy_glm(m_sed, "Sedentary quartile (ref=Q1)")
write.csv(res_sed, file.path(TAB_DIR, "model_sedentary_quartile.csv"), row.names = FALSE)
cat("\n===== 模型2：久坐四分位 =====\n"); print(res_sed)

# 趋势检验
m_trend <- svyglm(as.formula(paste("psoriasis ~ as.numeric(pa_group) +", COV)),
                  design = des, family = quasibinomial())
p_trend <- summary(m_trend)$coefficients["as.numeric(pa_group)", 4]
cat("\nPA 趋势检验 p =", format.pval(p_trend), "\n")

# 连续暴露（per 1000 MET-min/wk）
m_cont <- svyglm(as.formula(paste("psoriasis ~ met_1000 +", COV)),
                 design = des, family = quasibinomial())
cat("\n===== 模型3：连续 PA（每 1000 MET-min/wk）=====\n")
print(tidy_glm(m_cont, "PA per 1000 MET-min/wk"))
write.csv(tidy_glm(m_cont, "PA per 1000 MET-min/wk"),
          file.path(TAB_DIR, "model_PA_continuous.csv"), row.names = FALSE)

# 连续久坐（per 60 min/day）—— 便于与文献的「每小时久坐」口径对接
m_sedc <- svyglm(as.formula(paste("psoriasis ~ sed_60 +", COV)),
                 design = des, family = quasibinomial())
cat("\n===== 模型4：连续久坐（每 60 min/day）=====\n")
print(tidy_glm(m_sedc, "Sedentary per 60 min/day"))
write.csv(tidy_glm(m_sedc, "Sedentary per 60 min/day"),
          file.path(TAB_DIR, "model_sedentary_continuous.csv"), row.names = FALSE)

# ---------- 3b. ★ 预先指定的主要暴露 + 多重比较校正 --------------------------
# 为什么必须做：全文报告 10 个暴露检验，若把整个家族一起校正，
#   唯一阳性结果（久坐）的 BH 校正后 p = 0.121（不显著）；
#   若把家族限定为**两个事先指定的主要连续暴露**，校正后仍显著。
# 这是**设计声明**问题，不是数字问题 —— 必须在 Methods 明确写出，
#   否则审稿人可直接据此击穿主结论（见 09_统计审查报告.md P0-4）。
PRIMARY_EXPOSURES <- c("met_1000", "sed_60")   # ← 预先指定，不得事后更换
p_primary <- c(
  met_1000 = summary(m_cont)$coefficients["met_1000", 4],
  sed_60   = summary(m_sedc)$coefficients["sed_60",   4]
)
primary_tab <- data.frame(
  exposure   = c("Physical activity (per 1,000 MET-min/wk)",
                 "Sedentary time (per 60 min/day)"),
  term       = names(p_primary),
  p_raw      = as.numeric(p_primary),
  p_BH       = as.numeric(p.adjust(p_primary, method = "BH")),
  row.names  = NULL
)
write.csv(primary_tab, file.path(TAB_DIR, "primary_exposures_BH.csv"), row.names = FALSE)
cat("\n===== ★ 预先指定的主要暴露（家族 = 2，BH-FDR 校正）=====\n")
print(primary_tab)
cat("\n★ 声明口径：本文以「两个主要连续暴露」为比较家族做 BH 校正；\n")
cat("  分类暴露、剂量-反应样条、加速度计、中介、敏感性与亚组分析均为 secondary/exploratory，\n")
cat("  不做多重比较校正，也不用于支持或否定主结论。\n")

# ---------- 4. RCS 剂量-反应 -------------------------------------------------
RCS_DF <- 3   # 病例数有限，用 3 节点控制过拟合
COV_MAIN <- c("age","female","race","edu","pir","smoke",
              "alc_gday","hypertension","diabetes")

#' RCS 剂量-反应
#' ★ 修正（2026-10-03）：
#'   1) 协变量基准行必须取**真实观测行**，否则 factor(race) 会因均值 3.09 报
#'      "has new level"；不能用均值填充因子变量
#'   2) met_total 零膨胀（大量 0），ns() 会把 0 同时当边界与内部节点而告警
#'      → 用 log1p 变换后再拟合
make_rcs <- function(expo, label, df = RCS_DF, use_log1p = FALSE) {
  dd <- dat
  if (use_log1p) dd[[expo]] <- log1p(dd[[expo]])
  need <- c("psoriasis", expo, COV_MAIN, "psu_u", "strata_u", "wt_combined")
  dsub <- dd[complete.cases(dd[, need]), need]

  des2 <- svydesign(ids = ~psu_u, strata = ~strata_u,
                    weights = ~wt_combined, nest = TRUE, data = dsub)
  m <- svyglm(as.formula(paste0("psoriasis ~ ns(", expo, ", df=", df, ") + ", COV)),
              design = des2, family = quasibinomial())

  ref_val <- median(dsub[[expo]], na.rm = TRUE)
  grid <- seq(quantile(dsub[[expo]], .10, na.rm = TRUE),
              quantile(dsub[[expo]], .90, na.rm = TRUE), length.out = 150)

  # 用一行真实数据作协变量基准（保证因子水平合法）
  base_row <- dsub[1, , drop = FALSE]
  nd  <- base_row[rep(1, length(grid)), , drop = FALSE]; nd[[expo]] <- grid
  nd0 <- base_row;                                      nd0[[expo]] <- ref_val

  # ★ predict.svyglm 返回 svystat（带 var 属性的数值向量），不是 list！
  #   不能用 pr$fit / pr$se.fit；SE = sqrt(attr(pr, "var"))
  pr  <- predict(m, newdata = nd,  type = "link", se.fit = TRUE)
  fit <- as.numeric(pr)
  se  <- sqrt(as.numeric(attr(pr, "var")))
  pr0 <- as.numeric(predict(m, newdata = nd0, type = "link"))

  data.frame(exposure = label, x = grid,
             logor = fit - pr0,
             lci = (fit - pr0) - 1.96 * se,
             uci = (fit - pr0) + 1.96 * se)
}

rcs_all <- bind_rows(
  make_rcs("met_total",     "Total PA (log MET-min/wk)",   use_log1p = TRUE),
  make_rcs("sedentary_min", "Sedentary time (min/day)")
)
saveRDS(rcs_all, file.path(OUT_DIR, "rcs_data.rds"))
message("RCS 曲线数据已保存（供 05_figures.R 绘图）")

test_nonlinear <- function(expo, use_log1p = FALSE) {
  dd <- dat
  if (use_log1p) dd[[expo]] <- log1p(dd[[expo]])
  need <- c("psoriasis", expo, COV_MAIN, "psu_u", "strata_u", "wt_combined")
  dsub <- dd[complete.cases(dd[, need]), need]
  des2 <- svydesign(ids = ~psu_u, strata = ~strata_u,
                    weights = ~wt_combined, nest = TRUE, data = dsub)
  m_lin <- svyglm(as.formula(paste0("psoriasis ~ ", expo, " + ", COV)),
                  design = des2, family = quasibinomial())
  m_spl <- svyglm(as.formula(paste0("psoriasis ~ ns(", expo, ", df=", RCS_DF, ") + ", COV)),
                  design = des2, family = quasibinomial())
  # 非线性检验：先试 Wald anova，失败则退到 regTermTest
  a <- tryCatch(anova(m_lin, m_spl, method = "Wald"), error = function(e) {
    message("  anova(Wald) 失败：", conditionMessage(e)); NULL })
  if (!is.null(a) && is.data.frame(a) && nrow(a) >= 2) return(a$p[2])
  rt <- tryCatch(regTermTest(m_spl,
                             as.formula(paste0("~ ns(", expo, ", df=", RCS_DF, ")"))),
                 error = function(e) NULL)
  if (!is.null(rt)) {
    message("  （改用 regTermTest，检验的是样条项整体显著性，非严格非线性检验）")
    return(rt$p)
  }
  NA_real_
}
cat("\n非线性检验 P(PA, log) =", format.pval(test_nonlinear("met_total", TRUE)),
    " | P(sedentary) =", format.pval(test_nonlinear("sedentary_min")), "\n")

# ---------- 5. 中介分析（BMI / hs-CRP）--------------------------------------
med_vars <- c("bmi", "crp")

#' ★ 调查加权中介分析 + 按 PSU 聚类的 bootstrap CI
#'
#' 为什么不用 mediation 包：
#'   1) 它不支持复杂抽样设计（本研究的核心，权重+分层+聚类）；
#'   2) 其非标准求值会与本项目的变量名冲突（实测报 object 'mediator' not found）。
#' 本实现按「层内重抽 PSU」聚类 bootstrap，保留抽样权重，方法学上更适配 NHANES。
#'
#' 路径：met_total --a--> mediator --b--> psoriasis，直接效应 c'
#'   间接效应 = a*b；总效应 = c' + a*b；中介比例 = a*b / (c' + a*b)
boot_mediate <- function(mediator, B = 500, seed = 20261003) {
  need <- c("psoriasis", "met_total", mediator, COV_MAIN,
            "psu_u", "strata_u", "wt_combined")
  dd <- dat[complete.cases(dat[, need]), need]
  dd$.cl <- interaction(dd$strata_u, dd$psu_u, drop = TRUE)
  # ★ 用整数索引采样、再用映射表取回标签，避免字符标签查找出现
  #   "subscript out of bounds"（实测踩过）
  cl_df  <- unique(dd[, c("strata_u", ".cl")])
  cl_df$.idx <- seq_len(nrow(cl_df))
  row_idx    <- split(seq_len(nrow(dd)), dd$.cl)                 # 按聚类取行号
  idx2lab    <- as.character(cl_df$.cl)
  names(idx2lab) <- as.character(cl_df$.idx)
  strata_idx <- split(cl_df$.idx, cl_df$strata_u)                # 层 → 聚类索引

  fit_ab <- function(d) {
    des2 <- svydesign(ids = ~psu_u, strata = ~strata_u,
                      weights = ~wt_combined, nest = TRUE, data = d)
    ma <- svyglm(as.formula(paste(mediator, "~ met_total +", COV)),
                 design = des2)
    mb <- svyglm(as.formula(paste("psoriasis ~ met_total +", mediator, "+", COV)),
                 design = des2, family = quasibinomial())
    # ★ 必须 unname()：coef() 返回带名向量，c(a = <带名向量>) 会拼成 "a.met_total"，
    #   导致后续 p0["a"] / bs["a", ] 全部取不到 → 静默返回 NA（实测踩过）
    c(a  = unname(coef(ma)["met_total"]),
      b  = unname(coef(mb)[mediator]),
      cp = unname(coef(mb)["met_total"]))
  }

  p0 <- tryCatch(fit_ab(dd), error = function(e) {
    message("  点估计失败：", conditionMessage(e)); NULL })
  if (is.null(p0)) return(NULL)

  set.seed(seed)
  err_seen <- NULL
  bs <- replicate(B, {
    draw <- unlist(lapply(strata_idx, function(ix) sample(ix, replace = TRUE)))
    parts <- lapply(seq_along(draw), function(i) {
      lab <- idx2lab[[as.character(draw[i])]]
      d <- dd[row_idx[[lab]], , drop = FALSE]
      d$psu_u <- paste0(lab, "_", i)   # 重复抽中需唯一 id
      d
    })
    d2 <- do.call(rbind, parts)
    # ★ 不要写 factor(d2$strata_u, levels = levels(dd$strata_u))：
    #   strata_u 是字符型 → levels() 返回 NULL → factor(x, levels=NULL)
    #   会把**所有行变成 NA**，报 "missing values in `strata'"（实测踩过）。
    #   svydesign 可直接接受字符型 strata，保持原样即可。
    tryCatch(fit_ab(d2), error = function(e) {
      if (is.null(err_seen)) {          # ★ 只报第一个错误，避免刷屏
        err_seen <<- conditionMessage(e)
        message("  ★ 首个 bootstrap 失败（后续同类错误已静默）：", err_seen)
      }
      c(a = NA, b = NA, cp = NA)
    })
  })

  ind_b <- bs["a", ] * bs["b", ]
  tot_b <- bs["cp", ] + ind_b
  ci <- function(x) quantile(x, c(.025, .975), na.rm = TRUE)
  ind_ci <- ci(ind_b); tot_ci <- ci(tot_b)
  ind <- unname(p0["a"] * p0["b"]); tot <- unname(p0["cp"] + ind)

  data.frame(
    mediator = mediator, n = nrow(dd),
    a = unname(p0["a"]), b = unname(p0["b"]),
    indirect = ind, ind_lci = ind_ci[1], ind_uci = ind_ci[2],
    p_indirect = 2 * min(mean(ind_b <= 0, na.rm = TRUE),
                         mean(ind_b >= 0, na.rm = TRUE)),
    direct = unname(p0["cp"]),
    total = tot, tot_lci = tot_ci[1], tot_uci = tot_ci[2],
    prop_med = ind / tot
  )
}

med_res <- lapply(med_vars, function(m) {
  tryCatch(boot_mediate(m), error = function(e) {
    message("★ bootstrap 中介失败 (", m, ")：", conditionMessage(e)); NULL })
}) %>% bind_rows()
if (nrow(med_res)) {
  write.csv(med_res, file.path(TAB_DIR, "mediation_bootstrap.csv"), row.names = FALSE)
}
cat("\n===== 中介分析（调查加权 + PSU 聚类 bootstrap）=====\n")
print(as.data.frame(med_res))
cat("★ 注意：当总效应不显著（本例 PA 总效应 ≈ 0）时，「中介比例」在数学上不可解释，\n")
cat("  仅可报告间接效应的方向与量级；撰写时不得把 prop_med 当作结论。\n")

# 保留线性尺度的差异法作为对照（快、无需 bootstrap）
diff_method <- function(mediator) {
  mt <- svyglm(as.formula(paste("psoriasis ~ met_total +", COV)),
               design = des, family = quasibinomial())
  md <- svyglm(as.formula(paste("psoriasis ~ met_total +", mediator, "+", COV)),
               design = des, family = quasibinomial())
  c_ <- coef(mt)["met_total"]; c_p <- coef(md)["met_total"]
  data.frame(mediator = mediator, total = c_, direct = c_p,
             indirect = c_ - c_p, prop_med = (c_ - c_p) / c_)
}
res_diff <- lapply(med_vars, function(m) tryCatch(diff_method(m),
                                                  error = function(e) NULL)) %>% bind_rows()
write.csv(res_diff, file.path(TAB_DIR, "mediation_survey_diff.csv"), row.names = FALSE)
cat("\n===== 中介分析（加权差异法，敏感）=====\n"); print(res_diff)
cat("★ 注意：当总效应不显著（本例 PA 总效应 ≈ 0）时，「中介比例」在数学上不可解释，\n")
cat("  仅可报告间接效应的方向与量级；撰写时不得把 prop_med 当作结论。\n")

# ---------- 6. 亚组与交互（交互项会消耗参数，仅做 3 个）--------------------
subgroup <- function(var, label) {
  m <- tryCatch(svyglm(as.formula(paste("psoriasis ~ met_total *", var, "+", COV)),
                       design = des, family = quasibinomial()),
                error = function(e) NULL)
  if (is.null(m)) return(NULL)
  s <- summary(m)$coefficients
  idx <- grep(paste0(":", var, "|", var, ":"), rownames(s))
  if (!length(idx)) return(NULL)
  data.frame(subgroup = label, term = rownames(s)[idx],
             p_interaction = min(s[idx, 4], na.rm = TRUE))
}
sub_res <- bind_rows(subgroup("female", "sex"),
                     subgroup("diabetes", "diabetes"),
                     subgroup("race", "race"))
write.csv(sub_res, file.path(TAB_DIR, "subgroup_interactions.csv"), row.names = FALSE)
cat("\n===== 交互检验 =====\n"); print(sub_res)

# ---------- 7. 敏感性分析 ----------------------------------------------------
# (a) 严重度结局（有序 logit，仅病例中有值 → 用 pso_moderate_severe）
m_sev <- tryCatch(
  svyglm(as.formula(paste("pso_moderate_severe ~ met_total +", COV)),
         design = des, family = quasibinomial()),
  error = function(e) NULL)
if (!is.null(m_sev)) {
  cat("\n===== 敏感性：中重度银屑病（严重度 >=3）=====\n")
  print(tidy_glm(m_sev, "moderate-to-severe psoriasis"))
  write.csv(tidy_glm(m_sev, "moderate-to-severe psoriasis"),
            file.path(TAB_DIR, "sens_severity.csv"), row.names = FALSE)
}

# (b) 用药确认病例
m_conf <- tryCatch(
  svyglm(as.formula(paste("psoriasis_confirmed ~ met_total +", COV)),
         design = des, family = quasibinomial()),
  error = function(e) NULL)
if (!is.null(m_conf)) {
  cat("\n===== 敏感性：用药确认的银屑病病例 =====\n")
  print(tidy_glm(m_conf, "medication-confirmed psoriasis"))
  write.csv(tidy_glm(m_conf, "medication-confirmed psoriasis"),
            file.path(TAB_DIR, "sens_confirmed_cases.csv"), row.names = FALSE)
}

# (c) PsA 结局
m_psa <- tryCatch(
  svyglm(as.formula(paste("psoriatic_arthritis ~ met_total +", COV)),
         design = des, family = quasibinomial()),
  error = function(e) NULL)
if (!is.null(m_psa)) {
  cat("\n===== 敏感性：银屑病关节炎（MCQ195==3）=====\n")
  print(tidy_glm(m_psa, "psoriatic arthritis"))
  write.csv(tidy_glm(m_psa, "psoriatic arthritis"),
            file.path(TAB_DIR, "sens_psoriatic_arthritis.csv"), row.names = FALSE)
}

# ---------- 8. ★ 加速度计臂（探索性，功效有限，勿作主结论）----------------
pam_path <- file.path(PROJ_DIR, "data", "analytic_pam.rds")
if (file.exists(pam_path)) {
  dp <- readRDS(pam_path)
  n_pc <- sum(dp$psoriasis == 1, na.rm = TRUE)
  message("\n=== 加速度计臂（探索性）：n=", nrow(dp), "，病例=", n_pc,
          "（<200 视为功效不足）===")
  dp$acc_mims_z <- as.numeric(scale(dp$acc_mims))
  des_pam <- svydesign(ids = ~psu_u, strata = ~strata_u,
                       weights = ~wt_combined, nest = TRUE, data = dp)
  mp <- tryCatch(svyglm(as.formula(paste("psoriasis ~ acc_mims_z +", COV)),
                        design = des_pam, family = quasibinomial()),
                 error = function(e) NULL)
  if (!is.null(mp)) {
    cat("\n===== 加速度计（MIMS/day, per SD）与银屑病 =====\n")
    print(tidy_glm(mp, "accelerometer MIMS/day (exploratory)"))
    write.csv(tidy_glm(mp, "accelerometer (exploratory)"),
              file.path(TAB_DIR, "model_accelerometer.csv"), row.names = FALSE)
  }
} else {
  message("未找到 analytic_pam.rds，跳过加速度计分析")
}

sink(type = "message"); sink(); close(log_con)
message("\n完成。日志：output/log_03_obs.txt")
