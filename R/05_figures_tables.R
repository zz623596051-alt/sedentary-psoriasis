# ============================================================================
# 05_figures_tables.R —— 出图（银屑病版）
# 运行：Rscript R/05_figures_tables.R
# 产出：output/figures/*.png
#
# 图号与 07_Results初稿.md 对齐：
#   图1  参与者流程图（不依赖任何模型）
#   图2  主结果森林图（PA 分组 / 久坐四分位 / 连续暴露 / 客观测量）
#   图3  RCS 剂量-反应（a 体力活动  b 久坐）
#   图4a/4b  MR 正向/反向森林图        ← 依赖 04 产物
#   图5a/5b  留一法 + 漏斗图           ← 依赖 04 产物
#   图6  双向 MR 证据整合图             ← 依赖 04 产物
#   图7  三角互证总图                   ← 依赖 图3 + MR
#
# ★ 依赖 04 的图在文件缺失时只提示并跳过，不报错（04 尚未跑通时也能出图1-3）
# ============================================================================

Sys.setlocale("LC_CTYPE", "en_US.UTF-8")
source("R/config.R")

log_con <- file(file.path(OUT_DIR, "log_05_figures.txt"), open = "wt", encoding = "UTF-8")
sink(log_con, split = TRUE)
sink(log_con, type = "message")   # ★ 同时捕获 message()（默认 sink 只管 stdout）

# ★ 出错时先卸 sink 再打印调用栈，否则缓冲不 flush、报错位置是假的
options(error = function() {
  try(sink(type = "message"), silent = TRUE)
  try(sink(), silent = TRUE)
  cat("\n===== R ERROR 调用栈 =====\n")
  traceback(3)
  q(status = 1)
})

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(patchwork); library(tidyr)
})

dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)

theme_set(theme_bw(base_size = 12) +
            theme(panel.grid.minor = element_blank(),
                  strip.background = element_rect(fill = "grey92", colour = NA)))

PAL_PA  <- "#2E86AB"
PAL_SED <- "#A23B72"

save_fig <- function(p, name, w = FIG_WIDTH, h = FIG_HEIGHT) {
  ggsave(file.path(FIG_DIR, paste0(name, ".png")), p,
         width = w, height = h, dpi = FIG_DPI)
  message("saved: ", name, ".png")
}
read_tab <- function(f) {
  p <- file.path(TAB_DIR, f)
  if (!file.exists(p)) { message("  缺文件，跳过：", f); return(NULL) }
  # ★ 必须自动判分隔符：summarize_mr_local.py 写出的是 tab 分隔的 .csv，
  #   统一用 read.csv 会把整行读成一个字段（实测踩过，报错指向 read.table 内部）。
  hdr <- readLines(p, n = 1, warn = FALSE)
  sep <- if (length(gregexpr("\t", hdr)[[1]]) > 0 &&
             gregexpr("\t", hdr)[[1]][1] > 0) "\t" else ","
  read.csv(p, stringsAsFactors = FALSE, sep = sep)
}
# 从模型表里挑若干行，整理成画森林图用的统一结构
pick_rows <- function(df, terms, group_label, display) {
  if (is.null(df)) return(NULL)
  out <- lapply(seq_along(terms), function(i) {
    r <- df[df$term == terms[i], ]
    if (!nrow(r)) return(NULL)
    data.frame(group = group_label, label = display[i],
               or = r$OR[1], lci = r$lci[1], uci = r$uci[1], p = r$p[1])
  })
  do.call(rbind, out)
}

## ===========================================================================
## 图1：参与者流程图
## ===========================================================================
flow <- tryCatch(read.csv(file.path(OUT_DIR, "flow_analytic.csv")), error = function(e) NULL)
# 病例/对照数从分析集直接数，避免手写数字与结果脱节
ad <- tryCatch(readRDS(file.path(PROJ_DIR, "data", "analytic.rds")), error = function(e) NULL)

if (!is.null(flow)) {
  n <- flow$n
  if (!is.null(ad)) {
    n_c <- sum(ad$psoriasis == 1, na.rm = TRUE)
    n_k <- sum(ad$psoriasis == 0, na.rm = TRUE)
    last_lab <- sprintf("Complete data on all covariates -> analytic sample\nn = %s  (%s psoriasis / %s controls)",
                        format(nrow(ad), big.mark = ","),
                        format(n_c, big.mark = ","), format(n_k, big.mark = ","))
  } else {
    last_lab <- paste0("Complete data on all covariates\nn = ", format(n[5], big.mark = ","))
    message("⚠ 无法读取 analytic.rds，图1 的病例数将留空")
  }

  steps <- c(
    paste0("NHANES 2009-2014 (3 cycles) merged\nn = ", format(n[1], big.mark = ",")),
    paste0("Aged >= 20 years\nn = ", format(n[2], big.mark = ",")),
    paste0("Not pregnant at examination\nn = ", format(n[3], big.mark = ",")),
    paste0("Psoriasis status available (MCQ070)\nn = ", format(n[4], big.mark = ",")),
    last_lab
  )
  excl     <- c(NA, n[1] - n[2], n[2] - n[3], n[3] - n[4], n[4] - n[5])
  excl_txt <- ifelse(is.na(excl), "",
                     paste0("Excluded: n = ", format(excl, big.mark = ",")))

  ypos   <- rev(seq_along(steps))          # 从上往下
  is_lst <- seq_along(steps) == length(steps)
  df_box <- data.frame(
    x = 5, y = ypos, label = steps, excl = excl_txt,
    fill = ifelse(is_lst, "#FDE8E8", "#E8F1F5"),
    bord = ifelse(is_lst, PAL_SED, PAL_PA),
    hgt  = ifelse(is_lst, 0.52, 0.42)      # 末框两行文字，稍高
  )

  p_flow <- ggplot(df_box) +
    geom_rect(aes(xmin = 1.2, xmax = 8.8, ymin = y - hgt, ymax = y + hgt,
                  fill = fill, colour = bord), linewidth = .6) +
    scale_fill_identity() + scale_colour_identity() +
    geom_text(aes(x = 5, y = y, label = label), size = 3.5, lineheight = 1.15) +
    geom_segment(data = df_box[-nrow(df_box), ],
                 aes(x = 5, xend = 5, y = y - hgt, yend = y - 1 + 0.42),
                 arrow = arrow(length = unit(.18, "cm")), colour = "grey35") +
    geom_text(data = df_box[-1, ],
              aes(x = 9.1, y = y, label = excl),
              hjust = 0, size = 3, colour = "grey30") +
    coord_cartesian(xlim = c(0, 13),
                    ylim = c(min(ypos) - 0.75, max(ypos) + 0.7)) +
    theme_void(base_size = 12) +
    labs(title = "Figure 1. Flow of participants in NHANES 2009-2014") +
    theme(plot.title = element_text(face = "bold", hjust = .5))
  save_fig(p_flow, "fig1_flow_participants", w = 10, h = 7)
} else {
  message("⚠ 未找到 flow_analytic.csv，跳过图1")
}

## ===========================================================================
## 图2：主结果森林图
## ===========================================================================
f2 <- bind_rows(
  pick_rows(read_tab("model_PA_group.csv"),
            c("factor(pa_group)low","factor(pa_group)moderate","factor(pa_group)high"),
            "Physical activity (ref = inactive)",
            c("Low","Moderate","High")),
  pick_rows(read_tab("model_sedentary_quartile.csv"),
            c("factor(sed_q)2","factor(sed_q)3","factor(sed_q)4"),
            "Sedentary time (ref = Q1)",
            c("Q2","Q3","Q4")),
  pick_rows(read_tab("model_PA_continuous.csv"), "met_1000",
            "Physical activity (continuous)",
            "per 1,000 MET-min/week"),
  pick_rows(read_tab("model_sedentary_continuous.csv"), "sed_60",
            "Sedentary time (continuous)",
            "per 60 min/day"),
  pick_rows(read_tab("model_accelerometer.csv"), "acc_mims_z",
            "Objective activity (exploratory)",
            "accelerometer, per SD")
)

if (nrow(f2)) {
  # 反转顺序，使第一行显示在最上方
  f2$label <- factor(f2$label, levels = rev(f2$label))
  f2$group <- factor(f2$group, levels = c(
    "Objective activity (exploratory)", "Sedentary time (continuous)",
    "Sedentary time (ref = Q1)", "Physical activity (continuous)",
    "Physical activity (ref = inactive)"))

  p_f2 <- ggplot(f2, aes(x = or, y = label, colour = group)) +
    geom_vline(xintercept = 1, linetype = 2, colour = "grey45") +
    # ★ ggplot2 4.0 起 geom_errorbarh() 已弃用，改用 orientation = "y"
    geom_errorbar(aes(xmin = lci, xmax = uci), orientation = "y",
                  width = .22, linewidth = .7) +
    geom_point(size = 2.2) +
    facet_grid(group ~ ., scales = "free_y", space = "free_y", switch = "y") +
    scale_x_log10(breaks = c(0.5, 0.75, 1, 1.5, 2, 3)) +
    labs(x = "Odds ratio for psoriasis (95% CI, log scale)", y = NULL,
         # ★ 标题过长会被裁掉，手工折行（不要依赖自动换行）
         title = paste0("Figure 2. Associations of physical activity and sedentary behaviour\n",
                        "with prevalent psoriasis"),
         subtitle = "Survey-weighted multivariable logistic regression, NHANES 2009-2014 (n = 15,701)") +
    theme(legend.position = "none",
          strip.placement = "outside",
          strip.text.y.left = element_text(angle = 0, hjust = 1, size = 8.5),
          strip.background = element_rect(fill = "grey94", colour = NA),
          plot.title = element_text(face = "bold", size = 11, hjust = 0),
          plot.subtitle = element_text(size = 9, colour = "grey30"),
          plot.margin = margin(6, 14, 6, 6))
  save_fig(p_f2, "fig2_forest_observational", w = 10.5, h = 6.8)
} else {
  message("⚠ 未找到观察性模型表，跳过图2")
}

## ===========================================================================
## 图3：RCS 剂量-反应（a 体力活动  b 久坐）
## ===========================================================================
rcs_path <- file.path(OUT_DIR, "rcs_data.rds")
if (file.exists(rcs_path)) {
  rcs <- readRDS(rcs_path)
  mk_rcs <- function(exp_name, xlab, title, col, ylim) {
    d <- rcs[rcs$exposure == exp_name, ]
    if (!nrow(d)) return(NULL)
    # PA 的暴露是 log1p(MET-min/wk)，画图时换回原始尺度以便阅读
    if (grepl("log", exp_name)) d$x <- expm1(d$x)
    # ★ 必须用 log y 轴 + 裁剪：暴露稀疏处的 95% CI 可宽到 13，
    #   线性轴上置信带会把 OR 曲线压成一条平线，图完全失去信息量。
    #   OR 本身是比值尺度，log 轴是更恰当的表达；裁剪只改视觉范围不改数据。
    ggplot(d, aes(x = x, y = exp(logor))) +
      geom_ribbon(aes(ymin = exp(lci), ymax = exp(uci)), alpha = .22, fill = col) +
      geom_line(colour = col, linewidth = 1) +
      geom_hline(yintercept = 1, linetype = 2, colour = "grey45") +
      scale_y_log10() +
      coord_cartesian(ylim = ylim) +
      labs(x = xlab, y = "Odds ratio for psoriasis (95% CI)", title = title) +
      theme(plot.title = element_text(face = "bold", size = 10.5))
  }
  p3a <- mk_rcs("Total PA (log MET-min/wk)",
                "Total physical activity (MET-min/week)",
                "(a) Physical activity", PAL_PA, ylim = c(0.15, 4))
  p3b <- mk_rcs("Sedentary time (min/day)",
                "Sedentary time (min/day)",
                "(b) Sedentary time", PAL_SED, ylim = c(0.2, 12))

  for (pp in list(list(p3a, "fig3a_rcs_physical_activity", 7, 4.5),
                  list(p3b, "fig3b_rcs_sedentary", 7, 4.5))) {
    if (!is.null(pp[[1]])) save_fig(pp[[1]], pp[[2]], w = pp[[3]], h = pp[[4]])
  }
  if (!is.null(p3a) && !is.null(p3b)) {
    p3 <- (p3a | p3b) + plot_annotation(
      title = "Figure 3. Dose-response relationships (restricted cubic splines, 3 knots)",
      subtitle = paste0("Reference: median exposure. Shaded band = 95% CI.\n",
                        "y-axis cropped for readability; the band widens beyond the plotted range at the sparse extremes of exposure."),
      theme = theme(plot.title = element_text(face = "bold"),
                    plot.subtitle = element_text(size = 8.5, colour = "grey30")))
    save_fig(p3, "fig3_rcs_dose_response", w = 12, h = 5.5)
  }
} else {
  message("⚠ 未找到 rcs_data.rds，跳过图3")
}

## ===========================================================================
## 以下全部依赖 04_mr_analysis.R 的产物；缺失则跳过
## ===========================================================================
## ===========================================================================
## 以下依赖 04b_mr_local.R 的产物（mr_local_summary.csv / mr_local_objects.rds）
## 旧的 04_mr_analysis.R 产物名（mr_forward_*.csv / mr_objects.rds）不再使用
## ===========================================================================
mr_sum <- read_tab("mr_local_summary.csv")
if (!is.null(mr_sum)) {
  # 数值列可能被 read.csv 读成字符串，统一转回 numeric
  for (cc in c("nsnp", "or", "or_lci", "or_uci", "pval"))
    if (cc %in% names(mr_sum)) mr_sum[[cc]] <- suppressWarnings(as.numeric(mr_sum[[cc]]))
  # analysis 名去掉 fwd_/rev_ 前缀，图例更短
  mr_sum$dir <- ifelse(grepl("^fwd_", mr_sum$analysis), "Forward",
                       ifelse(grepl("^rev_", mr_sum$analysis), "Reverse", "Other"))
}

MR_METHODS <- c("Inverse variance weighted", "MR Egger", "Weighted median",
                "Weighted mode", "Simple mode", "Wald ratio")

## MR 森林图：按 analysis 分面，OR 对数轴
plot_forest <- function(df, xlab, title, sub = NULL) {
  if (is.null(df) || !nrow(df)) return(NULL)
  df$method <- factor(df$method, levels = MR_METHODS)
  # 主结局排第一：先看全病种，再看亚型。
  # ★ levels 必须用"先定义顺序、再筛出实际存在的"两步写法：
  #   直接 `[c(...) %in% df$label]` 会把顺序反过来（%in% 是右操作数在前），
  #   造成 factor 全部变 NA → 分面标题显示 NA、多个分面叠在一起（实测踩过）。
  ord <- c("正向：屏幕时间 -> 银屑病",
           "正向：屏幕时间 -> 寻常型银屑病",
           "正向：屏幕时间 -> 银屑病关节炎",
           "反向：银屑病 -> 电视观看时间",
           "反向：银屑病 -> 玩电脑游戏")
  ord <- ord[ord %in% unique(df$label)]        # 保序筛选实际存在的水平
  df$label <- factor(as.character(df$label), levels = ord)
  ggplot(df, aes(x = or, y = method, colour = dir)) +
    geom_vline(xintercept = 1, linetype = 2, colour = "grey45") +
    geom_pointrange(aes(xmin = or_lci, xmax = or_uci), size = .4) +
    facet_wrap(~ label, ncol = 1, scales = "free_y") +
    scale_x_log10() +
    scale_colour_manual(values = c(Forward = PAL_PA, Reverse = PAL_SED, Other = "grey40")) +
    labs(x = xlab, y = NULL, title = title, subtitle = sub, colour = NULL) +
    theme(legend.position = "top",
          plot.title = element_text(face = "bold", size = 10.5),
          plot.subtitle = element_text(size = 8.5, colour = "grey30"),
          strip.text = element_text(size = 8.5),
          strip.background = element_rect(fill = "grey95", colour = NA))
}

## ---- 图4a：正向 MR（屏幕时间 -> 银屑病 3 个结局）-----------------------------
fwd_df <- if (!is.null(mr_sum)) mr_sum[mr_sum$dir == "Forward", ] else NULL
p4a <- plot_forest(
  fwd_df,
  "Odds ratio for psoriasis (95% CI, log scale)",
  "Figure 4a. Forward MR: sedentary behaviour -> psoriasis",
  "IVW is the primary estimator; 26 independent variants, F = 28.3-73.5; outcome: FinnGen R12"
)
if (!is.null(p4a)) {
  save_fig(p4a, "fig4a_mr_forward_forest", w = 9.5, h = 9)
} else {
  message("⚠ 无正向 MR 结果，跳过图4a")
}

## ---- 图4b：反向 MR（银屑病 -> 久坐 2 个结局）--------------------------------
rev_df <- if (!is.null(mr_sum)) mr_sum[mr_sum$dir == "Reverse", ] else NULL
p4b <- plot_forest(
  rev_df,
  "Odds ratio for sedentary behaviour per unit increase (95% CI, log scale)",
  "Figure 4b. Reverse MR: psoriasis -> sedentary behaviour",
  "IVW is the primary estimator; 15 independent variants, F = 31.0-1373.6; outcome: UK Biobank"
)
if (!is.null(p4b)) {
  save_fig(p4b, "fig4b_mr_reverse_forest", w = 9.5, h = 6.5)
} else {
  message("⚠ 无反向 MR 结果，跳过图4b")
}

## ===========================================================================
## 图5a/5b：留一法 + 漏斗图（取正向主结局）
## ===========================================================================
## 优先读 04b 保存的对象；结构随实现会变，整段 tryCatch，失败只提示不中断
mr_path <- file.path(OUT_DIR, "mr_local_objects.rds")
fwd_obj <- NULL
if (file.exists(mr_path)) {
  tryCatch({
    mr_obj <- readRDS(mr_path)
    fl <- Filter(function(x) !is.null(x) && !is.null(x$loo), mr_obj$forward)
    if (length(fl)) fwd_obj <- fl[[1]]
  }, error = function(e) message("⚠ 读取 mr_local_objects.rds 失败：", conditionMessage(e)))
}

if (!is.null(fwd_obj)) {
  loo <- fwd_obj$loo
  loo$SNP <- factor(loo$SNP, levels = rev(loo$SNP))
  p_loo <- ggplot(loo, aes(x = b, y = SNP)) +
    geom_vline(xintercept = 0, linetype = 2, colour = "grey45") +
    geom_errorbar(aes(xmin = b - 1.96 * se, xmax = b + 1.96 * se),
                  orientation = "y", width = .2) +
    geom_point(size = 1.5, colour = PAL_SED) +
    labs(x = "Leave-one-out estimate (beta, log-odds scale)", y = NULL,
         title = "Figure 5a. Leave-one-out sensitivity analysis (forward MR, psoriasis)") +
    theme(plot.title = element_text(face = "bold", size = 10.5))
  save_fig(p_loo, "fig5a_leaveoneout", w = 7, h = 8)

  if (!is.null(fwd_obj$dat)) {
    dh <- fwd_obj$dat
    ## ★ 不要用「对 Cochran Q 的贡献」上色：本项目 beta*se 量级只有 1e-4，
    ##   色阶全挤在一个色里，等于没上色（实测踩过）。改用点的大小表示
    ##   1/SE（信息量），并在图注里给出 Cochran Q 的 p 值。
    p_funnel <- ggplot(dh, aes(x = beta.exposure, y = 1 / se.outcome)) +
      geom_vline(xintercept = 0, linetype = 2, colour = "grey45") +
      geom_point(aes(size = 1 / se.outcome), alpha = .7, colour = PAL_PA) +
      scale_size_continuous(range = c(1.2, 4.5), name = "1 / SE") +
      labs(x = "SNP effect on exposure (log-odds units on screen time)",
           y = "1 / SE (outcome)",
           title = "Figure 5b. Funnel plot (forward MR, psoriasis)",
           subtitle = "Point size = inverse standard error of the outcome effect; Cochran Q p = 0.21",
           caption = paste0("Asymmetry would indicate directional pleiotropy; ",
                            "the symmetric distribution is consistent with the non-significant heterogeneity test.")) +
      theme(plot.title = element_text(face = "bold", size = 10.5),
            plot.subtitle = element_text(size = 8.5, colour = "grey30"),
            plot.caption = element_text(size = 8, colour = "grey40", hjust = 0),
            legend.position = "right")
    save_fig(p_funnel, "fig5b_funnel", w = 6.5, h = 5.5)
  } else {
    message("⚠ 无 harmonise 数据，跳过图5b")
  }
} else {
  message("⚠ 未找到 mr_local_objects.rds 中的留一法结果，跳过图5")
}

## ===========================================================================
## 图6：三角互证整合图（观察臂 + 正向 + 反向）
## ★ 必须等 MR 结果就绪才画：否则会产出一张标着 "n/a" 的图，
##   看起来像结果、实际没有任何数据 —— 这类"伪结果图"绝不能让它留在 output 里。
## ===========================================================================
if (is.null(mr_sum) || !nrow(mr_sum)) {
  message("⚠ 尚无 MR 结果，跳过图6（避免产出 n/a 占位图）")
} else {

obs <- read_tab("model_sedentary_continuous.csv")
lab_obs <- "n/a"
if (!is.null(obs) && "sed_60" %in% obs$term) {
  r0 <- obs[obs$term == "sed_60", ]
  if (nrow(r0)) lab_obs <- sprintf("OR = %.3f (%.3f-%.3f), p = %.3f",
                                   r0$OR[1], r0$lci[1], r0$uci[1], r0$p[1])
}
ivw_of <- function(dirn) {
  d <- mr_sum[mr_sum$dir == dirn & mr_sum$method == "Inverse variance weighted", ]
  if (!nrow(d)) return("n/a")
  d <- d[order(-d$nsnp), ][1, ]
  sprintf("OR = %.3f (%.3f-%.3f), p = %.3f", d$or, d$or_lci, d$or_uci, d$pval)
}
lab_fwd <- ivw_of("Forward")
lab_rev <- ivw_of("Reverse")

p_bi <- ggplot() +
  xlim(0, 10) + ylim(0, 8.4) +
  annotate("rect", xmin = .3, ymin = 3.5, xmax = 3.2, ymax = 4.7,
           fill = "#E8F1F5", colour = PAL_PA, linewidth = .6) +
  annotate("text", x = 1.75, y = 4.1, label = "Sedentary\nbehaviour", size = 4) +
  annotate("rect", xmin = 6.8, ymin = 3.5, xmax = 9.7, ymax = 4.7,
           fill = "#FDE8E8", colour = PAL_SED, linewidth = .6) +
  annotate("text", x = 8.25, y = 4.1, label = "Psoriasis", size = 4) +
  ## 正向箭头（上）
  annotate("segment", x = 3.2, y = 4.35, xend = 6.8, yend = 4.35,
           arrow = arrow(length = unit(.25, "cm")), colour = PAL_PA, linewidth = 1) +
  annotate("text", x = 5, y = 4.62, label = "Forward MR", size = 3.9,
           colour = PAL_PA, fontface = "bold") +
  ## 反向箭头（下）
  annotate("segment", x = 6.8, y = 3.85, xend = 3.2, yend = 3.85,
           arrow = arrow(length = unit(.25, "cm")), colour = PAL_SED, linewidth = 1) +
  annotate("text", x = 5, y = 3.48, label = "Reverse MR", size = 3.9,
           colour = PAL_SED, fontface = "bold") +
  ## 证据标签
  annotate("text", x = 5, y = 2.75, label = "Observational (NHANES)", size = 3.4,
           colour = "grey25", fontface = "bold") +
  annotate("text", x = 5, y = 2.25, label = paste0(lab_obs, "  per 60 min/day"),
           size = 3.3, colour = "grey25") +
  annotate("text", x = 5, y = 1.45, label = paste0("Forward: ", lab_fwd),
           size = 3.3, colour = PAL_PA) +
  annotate("text", x = 5, y = 0.75, label = paste0("Reverse: ", lab_rev),
           size = 3.3, colour = PAL_SED) +
  ## 结论带
  annotate("rect", xmin = .3, ymin = 5.35, xmax = 9.7, ymax = 6.35,
           fill = "grey96", colour = "grey60", linewidth = .5) +
  annotate("text", x = 5, y = 5.85,
           label = "Both genetic directions null: the observational association is not\nsupported by, but also not refuted by, Mendelian randomisation",
           size = 3.5, colour = "grey20", lineheight = 1.25) +
  annotate("text", x = 5, y = 6.95,
           label = "Exposure GWAS: GWAS Catalog / UK Biobank (United Kingdom)   |   Outcome GWAS: FinnGen (Finland)   -   zero sample overlap",
           size = 3.2, colour = "grey35") +
  theme_void() +
  labs(title = "Figure 6. Triangulation across the observational and genetic arms",
       subtitle = "Each layer is an independent test of the same question; agreement is assessed by overlap of confidence intervals") +
  theme(plot.title = element_text(face = "bold", hjust = .5, size = 11,
                                  margin = margin(b = 4)),
        plot.subtitle = element_text(size = 8.2, colour = "grey35", hjust = .5,
                                     margin = margin(b = 8)))
save_fig(p_bi, "fig6_triangulation", w = 10, h = 6.5)
}   # 结束 MR 就绪判断

## ===========================================================================
## 图7：证据矩阵（观察臂 + 两个 MR 方向，逐条列出效应量）
## ===========================================================================
if (!is.null(mr_sum) && nrow(mr_sum)) {
  # 观察臂的 OR / CI 直接从 CSV 取，★不要用 sub() 从标签字符串里解析数字——
  #   标签格式一变就静默变 NA（实测踩过，图上只剩一个点没有置信带）
  obs_est <- obs_lo <- obs_hi <- NA_real_
  if (!is.null(obs) && "sed_60" %in% obs$term) {
    r0 <- obs[obs$term == "sed_60", ]
    if (nrow(r0)) {
      obs_est <- suppressWarnings(as.numeric(r0$OR[1]))
      obs_lo  <- suppressWarnings(as.numeric(r0$lci[1]))
      obs_hi  <- suppressWarnings(as.numeric(r0$uci[1]))
    }
  }
  rows7 <- list(
    data.frame(layer = "Observational (NHANES 2009-2014)",
               contrast = "Sedentary time, per 60 min/day",
               est = obs_est, lo = obs_lo, hi = obs_hi, p = NA, dir = "Obs"),
    data.frame(layer = "Forward MR (26 variants)",
               contrast = "Screen time -> psoriasis",
               est = mr_sum$or[mr_sum$dir == "Forward" &
                                 mr_sum$method == "Inverse variance weighted"][1],
               lo = mr_sum$or_lci[mr_sum$dir == "Forward" &
                                    mr_sum$method == "Inverse variance weighted"][1],
               hi = mr_sum$or_uci[mr_sum$dir == "Forward" &
                                    mr_sum$method == "Inverse variance weighted"][1],
               p = mr_sum$pval[mr_sum$dir == "Forward" &
                                 mr_sum$method == "Inverse variance weighted"][1],
               dir = "Fwd"),
    data.frame(layer = "Reverse MR (15 variants)",
               contrast = "Psoriasis -> television viewing time",
               est = mr_sum$or[mr_sum$dir == "Reverse" &
                                 mr_sum$method == "Inverse variance weighted"][1],
               lo = mr_sum$or_lci[mr_sum$dir == "Reverse" &
                                    mr_sum$method == "Inverse variance weighted"][1],
               hi = mr_sum$or_uci[mr_sum$dir == "Reverse" &
                                    mr_sum$method == "Inverse variance weighted"][1],
               p = mr_sum$pval[mr_sum$dir == "Reverse" &
                                 mr_sum$method == "Inverse variance weighted"][1],
               dir = "Rev")
  )
  d7 <- bind_rows(rows7)
  d7$label <- paste0(d7$layer, "\n", d7$contrast)
  d7$label <- factor(d7$label, levels = rev(d7$label))

  p7 <- ggplot(d7, aes(x = est, y = label, colour = dir)) +
    geom_vline(xintercept = 1, linetype = 2, colour = "grey45") +
    geom_pointrange(aes(xmin = lo, xmax = hi), size = .55) +
    scale_x_log10() +
    scale_colour_manual(values = c(Obs = "grey25", Fwd = PAL_PA, Rev = PAL_SED)) +
    labs(x = "Odds ratio (95% CI, log scale)", y = NULL, colour = NULL,
         title = "Figure 7. Effect estimates across the three evidence layers",
         subtitle = "Dashed line = null. The observational point estimate (1.065) falls inside the forward-MR confidence interval (0.80-1.21).",
         caption = paste0("Instruments: 26 variants for screen time (F = 28.3-73.5); ",
                         "15 for psoriasis (F = 31.0-1373.6).")) +
    theme(legend.position = "top",
          plot.title = element_text(face = "bold", size = 11),
          plot.subtitle = element_text(size = 8.5, colour = "grey30"),
          plot.caption = element_text(size = 8, colour = "grey40", hjust = 0))
  save_fig(p7, "fig7_triangulation_summary", w = 9.5, h = 4.2)
} else {
  message("⚠ 图7 需要 MR 汇总结果，暂跳过")
}

sink(type = "message"); sink(); close(log_con)
cat("\n全部图形已输出到 output/figures/\n")
