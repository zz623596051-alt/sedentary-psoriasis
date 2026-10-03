# ============================================================================
# 06_table1_stats.R —— Table 1 的加权统计与敏感性分析病例数
# 运行：Rscript R/06_table1_stats.R
# 产出：output/tables/table1_stats.csv（加权均值/SD/比例 + p 值）、
#       output/tables/sensitivity_case_counts.csv
#
# 为什么单独成脚本：03 输出的是 Table 1 的「骨架」（加权均值 + SE），
# 但投稿用的 Table 1 还需要 ① 加权 SD ② 分类变量各水平的百分比
# ③ 组间 p 值。这三样在 03 里没有，且计算成本很低，独立出来避免每次全量重跑。
# ============================================================================

Sys.setlocale("LC_CTYPE", "en_US.UTF-8")
source("R/config.R")

suppressPackageStartupMessages({ library(survey); library(dplyr) })
options(survey.lonely.psu = "adjust")

dat <- readRDS(file.path(PROJ_DIR, "data", "analytic.rds"))
des <- svydesign(ids = ~psu_u, strata = ~strata_u,
                 weights = ~wt_combined, nest = TRUE, data = dat)

CONT <- c("age","bmi","waist","chol","hdl","crp","egfr","met_total",
          "sedentary_min","pir")
CAT  <- c("female","diabetes","hypertension")
CAT_LV <- list(race = 1:5, edu = 1:5, pa_group_levels = NULL)

out <- list()

# ---------- 1. 连续变量：加权均值 ± SD，组间 p（加权线性回归）---------------
for (v in CONT) {
  m <- tryCatch(svyglm(as.formula(paste(v, "~ psoriasis")), design = des),
                error = function(e) NULL)
  mu <- svyby(as.formula(paste0("~", v)), ~psoriasis, des,
              svymean, na.rm = TRUE)
  sdg <- function(g) tryCatch(
    sqrt(as.numeric(svyvar(as.formula(paste0("~", v)),
                           subset(des, psoriasis == g), na.rm = TRUE))),
    error = function(e) NA_real_)
  out[[v]] <- data.frame(
    variable = v, type = "continuous",
    ctrl = mu[mu$psoriasis == 0, v], ctrl_sd = sdg(0),
    case = mu[mu$psoriasis == 1, v], case_sd = sdg(1),
    diff = if (is.null(m)) NA else coef(m)["psoriasis"],
    p    = if (is.null(m)) NA else summary(m)$coefficients["psoriasis", 4]
  )
}

# ---------- 2. 分类变量：加权比例 + 卡方 ------------------------------------
for (v in CAT) {
  mu <- svyby(as.formula(paste0("~", v)), ~psoriasis, des, svymean, na.rm = TRUE)
  ch <- tryCatch(svychisq(as.formula(paste0("~", v, " + psoriasis")), design = des),
                 error = function(e) NULL)
  out[[v]] <- data.frame(
    variable = v, type = "binary",
    ctrl = mu[mu$psoriasis == 0, v], ctrl_sd = NA,
    case = mu[mu$psoriasis == 1, v], case_sd = NA,
    diff = NA, p = if (is.null(ch)) NA else ch$p.value
  )
}

# 分类变量各水平构成（race / edu / pa_group / smoke）
# ★ svyby 的输出是「行 = 分组，列 = 各水平的统计量」，因此必须按**列名**取水平，
#   不能按行号取（按行号会把 "psoriasis" 组别列也当成水平，产出垃圾行——实测踩过）。
for (v in c("race","edu","pa_group","smoke")) {
  mu <- tryCatch(svyby(as.formula(paste0("~factor(", v, ")")), ~psoriasis, des,
                       svymean, na.rm = TRUE), error = function(e) NULL)
  if (is.null(mu)) next
  lv_cols <- grep("^factor", names(mu), value = TRUE)
  for (cl in lv_cols) {
    lab <- sub("^factor\\([^)]*\\)", "", cl)
    out[[paste0(v, "_", cl)]] <- data.frame(
      variable = paste0(v, " = ", lab), type = "level",
      ctrl = mu[[cl]][mu$psoriasis == 0], ctrl_sd = NA,
      case = mu[[cl]][mu$psoriasis == 1], case_sd = NA,
      diff = NA, p = NA
    )
  }
}
ch <- tryCatch(svychisq(~smoke + psoriasis, design = des), error = function(e) NULL)
if (!is.null(ch)) out[["smoke_overall"]] <- data.frame(
  variable = "smoke (overall)", type = "chisq",
  ctrl = NA, ctrl_sd = NA, case = NA, case_sd = NA, diff = NA, p = ch$p.value)

tbl <- bind_rows(out)
write.csv(tbl, file.path(TAB_DIR, "table1_stats.csv"), row.names = FALSE)
message("Table 1 统计已输出 → output/tables/table1_stats.csv")

# ---------- 3. 敏感性分析的病例数（★ EPV 自查）-----------------------------
sens <- data.frame(
  outcome = c("moderate-to-severe psoriasis (MCQ075>=3)",
              "medication-confirmed psoriasis",
              "psoriatic arthritis (MCQ195==3)"),
  cases = c(sum(dat$pso_moderate_severe == 1, na.rm = TRUE),
            sum(dat$psoriasis_confirmed == 1, na.rm = TRUE),
            sum(dat$psoriatic_arthritis == 1, na.rm = TRUE))
)
sens$n_params  <- PSO_MAIN_PARAMS
sens$epv       <- sens$cases / sens$n_params
sens$adequate  <- ifelse(sens$cases >= 10 * sens$n_params, "yes", "NO — exploratory only")
write.csv(sens, file.path(TAB_DIR, "sensitivity_case_counts.csv"), row.names = FALSE)

message("\n=== ★ 敏感性分析 EPV 自查 ===")
print(sens)
if (any(sens$adequate != "yes"))
  message("★ 注意：标注 NO 的敏感性分析功效不足，不得用于支持「结论稳健」的表述。")

cat("\n主要结果：\n")
print(tbl)
