## ===========================================================================
## 04b_mr_local.R —— 本地汇总统计版双向孟德尔随机化
## ===========================================================================
## 为什么不直接用 04_mr_analysis.R
##   OpenGWAS 的「按研究取全基因组建联」端点持续 502，extract_instruments()
##   无法自行构建工具变量。本脚本改为：
##     · 结局侧：从 FinnGen R12 公开桶流式筛出的本地文件读（tools/fetch_finngen.py）
##     · 暴露侧：从 GWAS Catalog 全量关联表自行提取 + Ensembl 补等位基因
##                  + Ensembl LD 做 1000G phase3 EUR 的 r² 剪枝
##                  （tools/extract_iv_from_catalog.py + tools/resolve_alleles_ld.py）
##
## 产出与 04 一致的 CSV，供 05_figures_tables.R 直接消费
## ===========================================================================

Sys.setlocale("LC_CTYPE", "en_US.UTF-8")
source("R/config.R")

suppressPackageStartupMessages({
  library(TwoSampleMR)
  library(dplyr)
})

LOG <- file.path(OUT_DIR, "log_04b_mr_local.txt")
log_con <- file(LOG, open = "wt", encoding = "UTF-8")
sink(log_con, split = TRUE)
sink(log_con, type = "message")   # ★ message()/warning() 也进日志
options(error = function() {
  try(sink(type = "message"), silent = TRUE); try(sink(), silent = TRUE)
  cat("\n===== R ERROR 调用栈 =====\n"); traceback(3)
  q(status = 1)
})
options(survey.lonely.psu = "adjust")

FG_DIR <- file.path(PROJ_DIR, "data", "finngen")

## ---- 暴露侧 IV（由 tools/resolve_alleles_ld.py 产出）------------------------
IV_EXP <- file.path(RAW_DIR, "iv_resolved.tsv")

## ---- 结局侧映射：逻辑名 → FinnGen R12 本地文件 -----------------------------
FG <- list(
  psoriasis      = "finngen_R12_L12_PSORIASIS",
  psoriasis_vulg = "finngen_R12_L12_PSORI_VULG",
  psoriasis_arth = "finngen_R12_M13_PSORIARTH"
)

## ===========================================================================
## 1. 工具函数
## ===========================================================================

## 读 FinnGen 本地结局文件 → TwoSampleMR outcome 侧格式
read_fg_outcome <- function(endpoint) {
  f <- file.path(FG_DIR, paste0(endpoint, ".outcome.tsv"))
  if (!file.exists(f)) { message("⚠ 缺 ", f); return(NULL) }
  # ★ check.names = FALSE：否则 read.delim 会把表头 '#chrom' 改成 'X.chrom'，
  #   随后 d$`#chrom` 返回 NULL（长度 0），data.frame 报
  #   "arguments imply differing number of rows: 28, 1, 0"（实测踩过，极难定位）
  d <- read.delim(f, stringsAsFactors = FALSE, check.names = FALSE)
  if (!nrow(d)) { message("⚠ ", endpoint, " 结局为空"); return(NULL) }
  # FinnGen 的标准误列名是 sebeta，不是 se
  if (!"sebeta" %in% names(d))
    stop(" FinnGen 文件缺少 sebeta 列，实际列：", paste(names(d), collapse = ", "))
  # rsids 列可能是 "rs1,rs2"（一行多个 rsID）→ 展宽为每个 rsID 一行，
  # 否则会与暴露侧 SNP 无法对上（实测 FinnGen 存在多 rsID 位点）
  d <- tidyr::separate_rows(d, "rsids", sep = ",")
  # 过滤掉非 rsID 的行（FinnGen 里少数位点 rsids 为 "." 或纯数字）
  d <- d[grepl("^rs", d$rsids), ]
  if (!nrow(d)) { message("⚠ ", endpoint, " 展开后无有效 rsID"); return(NULL) }
  # 暴露侧的 effect allele 取自 Catalog 的 alt；FinnGen 给出 ref/alt，
  # 这里按 FinnGen 原样给出（alt 作 effect），链方向对齐交给 harmonise
  data.frame(
    SNP = d$rsids,
    beta.outcome   = d$beta,
    se.outcome     = d$sebeta,
    effect_allele.outcome = d$alt,
    other_allele.outcome = d$ref,
    eaf.outcome    = d$af_alt,
    pval.outcome   = d$pval,
    samplesize.outcome = NA_integer_,
    chr.outcome = d[["#chrom"]], pos.outcome = d$pos,
    outcome = endpoint, id.outcome = endpoint,
    stringsAsFactors = FALSE
  )
}

## 构造 TwoSampleMR exposure 侧格式
mk_exposure <- function(iv, label, acc) {
  data.frame(
    SNP = iv$snp,
    beta.exposure = iv$beta,
    se.exposure = iv$se,
    effect_allele.exposure = iv$effect_allele,
    other_allele.exposure = iv$other_allele,
    pval.exposure = iv$p,
    eaf.exposure = iv$eaf,
    samplesize.exposure = iv$n_samples,
    chr.exposure = iv$chr, pos.exposure = iv$pos,
    exposure = label, id.exposure = acc,
    `mr(exposure)` = label, `mr(exposure_id)` = acc,
    stringsAsFactors = FALSE
  )
}

## 一次完整的 MR（主分析 + 稳健性 + 敏感性），返回 list
run_one <- function(exp_dat, out_dat, tag) {
  if (is.null(out_dat) || !nrow(out_dat)) {
    message("★ [", tag, "] 结局数据为空，跳过"); return(NULL)
  }
  common <- intersect(exp_dat$SNP, out_dat$SNP)
  message(sprintf("★ [%s] 暴露 %d / 结局 %d → 共同 SNP %d",
                  tag, nrow(exp_dat), nrow(out_dat), length(common)))
  if (length(common) < 3) {
    message("★ [", tag, "] 共同 SNP < 3，无法做 MR"); return(NULL)
  }
  dat_h <- tryCatch(harmonise_data(exp_dat, out_dat, action = 2),
                    error = function(e) {
                      message("★ [", tag, "] harmonise 失败：", conditionMessage(e))
                      NULL })
  if (is.null(dat_h) || !nrow(dat_h)) {
    message("★ [", tag, "] harmonise 后为空"); return(NULL)
  }
  message(sprintf("   harmonise 保留 %d；移除原因：%s",
                  nrow(dat_h),
                  paste(names(table(dat_h$mr_removed)),
                        table(dat_h$mr_removed), sep = "=", collapse = "; ")))

  res      <- mr(dat_h)
  het      <- tryCatch(mr_heterogeneity(dat_h), error = function(e) NULL)
  ple      <- tryCatch(mr_pleiotropy_test(dat_h), error = function(e) NULL)
  loo      <- tryCatch(mr_leaveoneout(dat_h), error = function(e) NULL)
  sing     <- tryCatch(mr_singlesnp(dat_h), error = function(e) NULL)

  res <- res %>% mutate(or = exp(b), or_lci = exp(b - 1.96 * se),
                        or_uci = exp(b + 1.96 * se), analysis = tag)
  res$nsnp_used <- nrow(dat_h)

  cat("\n===== [", tag, "] IVW 主分析 =====\n", sep = "")
  print(res %>% select(method, nsnp, b, se, or, or_lci, or_uci, pval))
  if (!is.null(het)) {
    cat("\n===== [", tag, "] 异质性 =====\n")
    print(het %>% select(method, Q, Q_df, Q_pval))
  }
  if (!is.null(ple)) {
    cat("\n===== [", tag, "] 多效性（MR-Egger 截距）=====\n")
    print(ple %>% select(egger_intercept, se, pval))
  }

  write.csv(res,      file.path(TAB_DIR, paste0("mr_local_", tag, "_main.csv")), row.names = FALSE)
  if (!is.null(het)) write.csv(het, file.path(TAB_DIR, paste0("mr_local_", tag, "_heterogeneity.csv")), row.names = FALSE)
  if (!is.null(ple)) write.csv(ple, file.path(TAB_DIR, paste0("mr_local_", tag, "_pleiotropy.csv")), row.names = FALSE)
  if (!is.null(loo)) write.csv(loo, file.path(TAB_DIR, paste0("mr_local_", tag, "_leaveoneout.csv")), row.names = FALSE)
  if (!is.null(sing)) write.csv(sing, file.path(TAB_DIR, paste0("mr_local_", tag, "_singlesnp.csv")), row.names = FALSE)
  keep <- intersect(c("SNP", "chr.exposure", "pos.exposure", "beta.exposure",
                      "se.exposure", "effect_allele.exposure", "other_allele.exposure",
                      "beta.outcome", "se.outcome", "effect_allele.outcome",
                      "other_allele.outcome", "eaf.outcome", "pval.outcome",
                      "mr_removed"), names(dat_h))
  write.csv(dat_h[, keep, drop = FALSE],
            file.path(TAB_DIR, paste0("mr_local_", tag, "_harmonised.csv")), row.names = FALSE)

  list(dat = dat_h, res = res, het = het, ple = ple, loo = loo, sing = sing,
       tag = tag)
}

## ===========================================================================
## 2. 检查输入
## ===========================================================================
cat("=== 04b 本地汇总统计版 MR ===\n\n")

if (!file.exists(IV_EXP)) {
  cat("✗ 缺暴露侧 IV：", IV_EXP, "\n")
  cat("  请先运行 tools/extract_iv_from_catalog.py 与 tools/resolve_alleles_ld.py\n")
  sink(type = "message"); sink(); close(log_con); quit(status = 1)
}
iv <- read.delim(IV_EXP, stringsAsFactors = FALSE)
cat("暴露侧 IV：", nrow(iv), " 个（", paste(unique(iv$accession), collapse = ", "), "）\n")
F_exp <- (iv$beta / iv$se)^2
cat(sprintf("工具变量 F 统计量：%.1f – %.1f\n", min(F_exp, na.rm = TRUE), max(F_exp, na.rm = TRUE)))
if (min(F_exp, na.rm = TRUE) < 10)
  message("⚠ 存在 F < 10 的弱工具变量，MR 解释需谨慎")

exp_dat <- mk_exposure(iv, "Leisure screen time", unique(iv$accession)[1])
out_ps  <- read_fg_outcome(FG$psoriasis)

## ===========================================================================
## 3. 正向 MR：屏幕时间 → 银屑病（FinnGen R12，主结局 + 2 个亚型）
## ===========================================================================
cat("\n\n########## 正向 MR：Leisure screen time → psoriasis ##########\n\n")
fwd <- list()
for (nm in names(FG)) {
  o <- read_fg_outcome(FG[[nm]])
  r <- run_one(exp_dat, o, paste0("fwd_", nm))
  if (!is.null(r)) fwd[[nm]] <- r
}

## ===========================================================================
## 4. 反向 MR：银屑病 → 久坐
##    暴露 IV 来自 FinnGen R12 自身的显著 SNP（tools/fetch_finngen.py --mode both
##    → tools/build_reverse_iv.py → tools/resolve_alleles_ld.py）
##
##    ★ 结局为什么不用 GCST90104339（Leisure screen time）：
##      该研究在 GWAS Catalog 关联表里只留下 2 个 top hit。**Catalog 关联表只收录
##      各研究自己上报的显著位点，不是全基因组统计**，因此拿不到「银屑病 IV 在
##      屏幕时间上的效应」。改用 OpenGWAS 收录的等价构念——电视观看时间
##      （ukb-b-5192, n=437,887），extract_outcome_data 可用（实测 13/15 直接
##      匹配，缺的 2 个由 OpenGWAS 自动找 r2>0.8 的 proxy，须在 Methods 声明）。
## ===========================================================================
cat("\n\n########## 反向 MR：psoriasis → 久坐 ##########\n\n")

IV_PS_FILE <- file.path(FG_DIR, "psoriasis_iv_r2.tsv")

## 反向 MR 的结局候选（按构念优先级）
REV_OUTCOMES <- list(
  list(id = "ukb-b-5192", label = "Time spent watching television (TV)"),
  list(id = "ukb-b-4779", label = "Plays computer games")
)

rev_res <- list()
if (file.exists(IV_PS_FILE)) {
  iv_ps <- read.delim(IV_PS_FILE, stringsAsFactors = FALSE)
  cat("银屑病 IV：", nrow(iv_ps), " 个\n")
  F_rev <- (iv_ps$beta / iv_ps$se)^2
  cat(sprintf("银屑病 IV 的 F 统计量：%.1f – %.1f\n",
              min(F_rev, na.rm = TRUE), max(F_rev, na.rm = TRUE)))
  if (min(F_rev, na.rm = TRUE) < 10)
    message("⚠ 存在 F<10 的弱工具变量")
  cat("\n")

  exp_rev <- data.frame(
    SNP = iv_ps$snp,
    beta.exposure = iv_ps$beta,
    se.exposure = iv_ps$se,
    effect_allele.exposure = iv_ps$effect_allele,
    other_allele.exposure = iv_ps$other_allele,
    pval.exposure = iv_ps$p,
    eaf.exposure = iv_ps$eaf,
    samplesize.exposure = NA_integer_,
    chr.exposure = iv_ps$chr, pos.exposure = iv_ps$pos,
    exposure = "Psoriasis (FinnGen R12)", id.exposure = "R12_L12_PSORIASIS",
    `mr(exposure)` = "Psoriasis (FinnGen R12)",
    `mr(exposure_id)` = "R12_L12_PSORIASIS",
    stringsAsFactors = FALSE
  )

  for (oc in REV_OUTCOMES) {
    o <- tryCatch(extract_outcome_data(snps = exp_rev$SNP, outcomes = oc$id),
                  error = function(e) {
                    message("⚠ 结局 ", oc$id, " 拉取失败：", conditionMessage(e))
                    NULL })
    if (is.null(o) || !nrow(o)) next
    ## proxy SNP 必须记录：OpenGWAS 会为无直接数据的 SNP 找替代（r2>0.8）
    n_proxy <- sum(!(o$SNP %in% exp_rev$SNP))
    if (n_proxy > 0)
      message(sprintf("  [%s] %d/%d 个 SNP 无直接数据，使用 OpenGWAS 找的 proxy（r2>0.8）",
                      oc$id, n_proxy, nrow(o)))
    r <- run_one(exp_rev, o,
                 paste0("rev_sedentary_", sub("^ukb-b-", "", oc$id)))
    if (!is.null(r)) rev_res[[oc$id]] <- r
  }
} else {
  message("⚠ 缺银屑病 IV：", IV_PS_FILE)
  message("  需先运行 tools/fetch_finngen.py --mode both 与 tools/build_reverse_iv.py")
}

## ===========================================================================
## 5. 汇总输出
## ===========================================================================
all_main <- bind_rows(lapply(c(fwd, list(rev_res)), function(x) x$res))
if (!is.null(all_main) && nrow(all_main)) {
  write.csv(all_main, file.path(TAB_DIR, "mr_local_all_main.csv"), row.names = FALSE)
  cat("\n\n########## 全部 MR 结果汇总 ##########\n")
  print(all_main %>% select(analysis, method, nsnp, or, or_lci, or_uci, pval))
}

## 供 05 出图用：把 harmonise 数据与结果打包
saveRDS(list(forward = fwd, reverse = rev_res),
        file.path(OUT_DIR, "mr_local_objects.rds"))

cat("\n\n=== 04b 完成 ===\n")
sink(type = "message"); sink(); close(log_con)
cat("done\n")
