# ============================================================================
# 04_mr_analysis.R —— 臂二 & 臂三：正向/反向 MR、多变量 MR、中介 MR（银屑病）
# 运行：Rscript R/04_mr_analysis.R
# 前置：1) 申请 OpenGWAS token 2) config.R 中 MR$ 已填入核查过的 ID（已完成）
# 产出：output/tables/mr_*.csv, output/mr_objects.rds
#
# ★ 本方案核心：双向 MR —— 回应 J Am Acad Dermatol 2026 提出的"鸡与蛋"问题
#   （是运动少导致银屑病，还是银屑病导致运动少）
# ============================================================================

Sys.setlocale("LC_CTYPE", "en_US.UTF-8")
source("R/config.R")

log_con <- file(file.path(OUT_DIR, "log_04_mr.txt"), open = "wt", encoding = "UTF-8")
sink(log_con, split = TRUE)
sink(log_con, type = "message")   # ★ 同时捕获 message()/warning()（默认 sink 只管 stdout）

suppressPackageStartupMessages({
  library(TwoSampleMR); library(ieugwasr); library(dplyr)
})

# ★ 出错时先卸 sink 再打印调用栈：MR 全程是网络调用，失败点若不定位极难重跑
options(error = function() {
  try(sink(type = "message"), silent = TRUE)
  try(sink(), silent = TRUE)
  cat("\n===== R ERROR 调用栈 =====\n")
  traceback(3)
  q(status = 1)
})

## ===========================================================================
## 0. Token（首次使用必做：https://api.opengwas.io/ 申请后写入 .Renviron）
## ===========================================================================
if (nzchar(Sys.getenv("OPENGWAS_JWT"))) {
  message("已读取 OPENGWAS_JWT")
} else {
  message("★ 未检测到 OPENGWAS_JWT，请在 .Renviron 设置 OPENGWAS_JWT 后重启 R")
}

## ===========================================================================
## 1. 数据集核对（防抄错 ID）
## ===========================================================================
verify_ids <- function(ids) {
  ids <- unlist(ids); ids <- ids[!is.na(ids) & nzchar(ids)]
  if (!length(ids)) { message("ID 全为空"); return(NULL) }
  info <- tryCatch(ieugwasr::gwasinfo(ids), error = function(e) {
    message("gwasinfo 失败：", conditionMessage(e)); NULL })
  if (!is.null(info)) {
    cols <- intersect(c("id","trait","sample_size","ncase","ncontrol","population","nsnp"),
                      names(info))
    print(info[, cols, drop = FALSE])
  }
  info
}

message("\n=== 核对 config.R 中的数据集 ID ===")
info <- verify_ids(MR[c("pa_mvpa","pa_accel","pa_walk_dur","pa_strenuous",
                        "sedentary_tv","psoriasis","psoriasis_vulg",
                        "psoriasis_arth","bmi","crp")])
if (!is.null(info)) write.csv(info, file.path(TAB_DIR, "gwas_info.csv"), row.names = FALSE)

## ===========================================================================
## 1b. ★ FinnGen R12 本地结局（可选，功效为旧版 finn-b-* 的 2.8 倍）
##     启用前提：先跑 tools/fetch_finngen.py 生成筛选后的 tsv
## ===========================================================================
read_finngen_local <- function(snps, endpoint, phenotype = "psoriasis") {
  f <- file.path(FINNGEN$dir, paste0(endpoint, ".sel.tsv"))
  if (!file.exists(f)) {
    message("未找到 ", f, " —— 请先运行 tools/fetch_finngen.py")
    return(NULL)
  }
  TwoSampleMR::read_outcome_data(
    snps = snps, filename = f, sep = "\t",
    snp_col = "rsids", beta_col = "beta", se_col = "sebeta",
    effect_allele_col = "alt", other_allele_col = "ref",
    eaf_col = "af_alt", pval_col = "pval",
    chr_col = "#chrom", pos_col = "pos", phenotype = phenotype
  )
}

## ===========================================================================
## 2. 通用两样本 MR 引擎
## ===========================================================================
run_mr <- function(exposure_id, outcome_id, label) {
  message("\n========== MR: ", label, " ==========")
  if (is.null(exposure_id) || is.null(outcome_id)) { message("跳过：ID 为空"); return(NULL) }

  exp_dat <- tryCatch(
    TwoSampleMR::extract_instruments(outcomes = exposure_id,
                                     p1 = MR$p_threshold, clump = TRUE,
                                     r2 = MR$clump_r2, kb = MR$clump_kb),
    error = function(e) { message("提取 IV 失败：", conditionMessage(e)); NULL })
  if (is.null(exp_dat) || !nrow(exp_dat)) { message("无可用 IV"); return(NULL) }

  exp_dat$F <- (exp_dat$beta.exposure^2) / (exp_dat$se.exposure^2)
  message("IV 数 = ", nrow(exp_dat), "；F 中位数 = ",
          round(median(exp_dat$F, na.rm = TRUE), 1),
          "；F<10 个数 = ", sum(exp_dat$F < MR$f_min, na.rm = TRUE))
  if (nrow(exp_dat) < 3) message("⚠️ IV 数 <3，MR 结果不稳定，仅作参考")
  exp_dat <- exp_dat[exp_dat$F >= MR$f_min, ]

  out_dat <- tryCatch(
    TwoSampleMR::extract_outcome_data(snps = exp_dat$SNP, outcomes = outcome_id),
    error = function(e) { message("提取结局失败：", conditionMessage(e)); NULL })
  if (is.null(out_dat) || !nrow(out_dat)) { message("结局无匹配 SNP"); return(NULL) }

  dat_h <- TwoSampleMR::harmonise_data(exp_dat, out_dat, action = 2)
  keep  <- !(dat_h$palindromic & dat_h$ambiguous)
  message("回文歧义位点剔除：", sum(!keep))
  dat_h <- dat_h[keep, ]

  meth <- c("mr_ivw", "mr_egger_regression", "mr_weighted_median",
            "mr_weighted_mode", "mr_simple_mode")
  if (nrow(dat_h) < 3) meth <- c("mr_wald_ratio", "mr_ivw")

  res <- TwoSampleMR::mr(dat_h, method_list = meth)
  res$exposure <- label

  pleio <- tryCatch(TwoSampleMR::mr_pleiotropy_test(dat_h), error = function(e) NULL)
  het   <- tryCatch(TwoSampleMR::mr_heterogeneity(dat_h),  error = function(e) NULL)
  loo   <- tryCatch(TwoSampleMR::mr_leaveoneout(dat_h),    error = function(e) NULL)
  steig <- tryCatch(TwoSampleMR::directionality_test(dat_h), error = function(e) NULL)

  presso <- tryCatch({
    p <- MRPRESSO::mr_presso(BetaOutcome = "beta.outcome", BetaExposure = "beta.exposure",
                             SdOutcome = "se.outcome", SdExposure = "se.exposure",
                             OUTLIERtest = TRUE, DISTORTIONtest = TRUE,
                             data = as.data.frame(dat_h),
                             NbDistribution = 1000, SignifThreshold = 0.05)
    list(global = p$`MR-PRESSO global test`, outliers = p$`MR-PRESSO outliers test`)
  }, error = function(e) { message("MR-PRESSO 失败：", conditionMessage(e)); NULL })

  list(exposure = label, res = res, dat = dat_h, pleiotropy = pleio,
       heterogeneity = het, leaveoneout = loo, steiger = steig, presso = presso)
}

collect <- function(x) if (is.null(x)) NULL else x$res
fmt_res <- function(res_all) {
  if (is.null(res_all) || !nrow(res_all)) return(res_all)
  res_all$outcome_label <- res_all$outcome
  res_all$or     <- exp(res_all$b)
  res_all$or_lci <- exp(res_all$b - 1.96 * res_all$se)
  res_all$or_uci <- exp(res_all$b + 1.96 * res_all$se)
  res_all
}

## ===========================================================================
## 3. ★ 正向 MR：PA / 久坐 → 银屑病
## ===========================================================================
exp_ids <- list(
  "MVPA levels (GCST006097)"      = MR$pa_mvpa,
  "Accelerometer acceleration"    = MR$pa_accel,
  "Duration of walks"             = MR$pa_walk_dur,
  "Strenuous sports"              = MR$pa_strenuous,
  "TV watching (sedentary)"       = MR$sedentary_tv
)

fwd <- lapply(names(exp_ids), function(nm)
  run_mr(exp_ids[[nm]], MR$psoriasis, paste0("FWD | ", nm)))

fwd_res <- fmt_res(bind_rows(lapply(fwd, collect)))
if (!is.null(fwd_res) && nrow(fwd_res)) {
  write.csv(fwd_res, file.path(TAB_DIR, "mr_forward_PA_to_psoriasis.csv"), row.names = FALSE)
  cat("\n===== ★ 正向 MR：PA/久坐 → 银屑病 =====\n")
  print(fwd_res[, c("exposure","method","nsnp","or","or_lci","or_uci","pval")])
}

## ===========================================================================
## 4. ★★ 反向 MR：银屑病 → PA / 久坐（回应"鸡与蛋"问题）
##     注：FinnGen（芬兰）作暴露，UKB（英国）作结局 → 零样本重叠
## ===========================================================================
rev_list <- lapply(names(exp_ids), function(nm)
  run_mr(MR$psoriasis, exp_ids[[nm]], paste0("REV | psoriasis -> ", nm)))

rev_res <- fmt_res(bind_rows(lapply(rev_list, collect)))
if (!is.null(rev_res) && nrow(rev_res)) {
  write.csv(rev_res, file.path(TAB_DIR, "mr_reverse_psoriasis_to_PA.csv"), row.names = FALSE)
  cat("\n===== ★★ 反向 MR：银屑病 → PA/久坐 =====\n")
  print(rev_res[, c("exposure","method","nsnp","b","se","pval")])
}

## ===========================================================================
## 5. 稳健性明细（多效性 / 异质性 / 方向性）
## ===========================================================================
all_objs <- c(fwd, rev_list)
for (nm in c("pleiotropy","heterogeneity","steiger")) {
  tab <- bind_rows(lapply(all_objs, function(x) {
    if (is.null(x) || is.null(x[[nm]])) return(NULL)
    d <- x[[nm]]; d$exposure <- x$exposure; d
  }))
  if (nrow(tab)) write.csv(tab, file.path(TAB_DIR, paste0("mr_", nm, ".csv")), row.names = FALSE)
}
cat("\n多效性 / 异质性 / 方向性结果已输出\n")

## ===========================================================================
## 6. 亚型验证：PA/久坐 → 银屑病亚型
## ===========================================================================
subtypes <- list(
  "Psoriasis vulgaris"  = MR$psoriasis_vulg,
  "Psoriatic arthritis" = MR$psoriasis_arth,
  "Psoriasis (NAS)"     = MR$psoriasis_nas
)
sub_list <- lapply(names(subtypes), function(nm)
  run_mr(MR$pa_mvpa, subtypes[[nm]], paste0("SUBTYPE | MVPA -> ", nm)))
sub_res <- fmt_res(bind_rows(lapply(sub_list, collect)))
if (!is.null(sub_res) && nrow(sub_res)) {
  write.csv(sub_res, file.path(TAB_DIR, "mr_subtypes.csv"), row.names = FALSE)
  cat("\n===== 亚型验证 =====\n")
  print(sub_res[, c("exposure","method","nsnp","or","or_lci","or_uci","pval")])
}

## ===========================================================================
## 7. 多变量 MR（MVMR）：校正 BMI 的直接效应
## ===========================================================================
mvmr_obj <- tryCatch({
  ids <- c(MR$pa_mvpa, MR$bmi)
  e <- MVMR::mv_extract_exposures(ids)
  o <- MVMR::mv_extract_outcomes(ids, MR$psoriasis)
  h <- MVMR::mv_harmonise_data(e, o)
  est <- MVMR::mv_multiple(h)
  print(est$result)
  write.csv(est$result, file.path(TAB_DIR, "mvmr_PA_BMI_psoriasis.csv"), row.names = FALSE)
  list(est = est, data = h)
}, error = function(e) { message("MVMR 失败：", conditionMessage(e)); NULL })

## ===========================================================================
## 8. 中介 MR：PA → BMI / CRP → 银屑病
## ===========================================================================
mediation_mr <- function(exp_id, med_id, out_id, label) {
  message("\n========== 中介MR: ", label, " ==========")
  if (any(vapply(list(exp_id, med_id, out_id), is.null, logical(1)))) {
    message("ID 缺失，跳过"); return(NULL)
  }
  s1 <- run_mr(exp_id, med_id,   paste0(label, " | step1 PA->mediator"))
  s2 <- run_mr(med_id,  out_id,  paste0(label, " | step2 mediator->outcome"))
  if (is.null(s1) || is.null(s2)) return(NULL)
  i1 <- s1$res[s1$res$method == "Inverse variance weighted", ]
  i2 <- s2$res[s2$res$method == "Inverse variance weighted", ]
  if (!nrow(i1) || !nrow(i2)) return(NULL)
  indirect <- i1$b * i2$b
  se_ind   <- sqrt(i1$b^2 * i2$se^2 + i2$b^2 * i1$se^2)   # delta 法
  out <- data.frame(label = label, b_step1 = i1$b, b_step2 = i2$b,
                    indirect = indirect,
                    ind_lci = indirect - 1.96*se_ind,
                    ind_uci = indirect + 1.96*se_ind,
                    p_indirect = 2*pnorm(-abs(indirect/se_ind)))
  print(out); out
}
med_all <- bind_rows(
  mediation_mr(MR$pa_mvpa, MR$bmi, MR$psoriasis, "PA -> BMI -> psoriasis"),
  mediation_mr(MR$pa_mvpa, MR$crp, MR$psoriasis, "PA -> CRP -> psoriasis")
)
if (nrow(med_all)) write.csv(med_all, file.path(TAB_DIR, "mediation_mr.csv"), row.names = FALSE)

## ===========================================================================
## 8b. ★ FinnGen R12 本地结局（可选验证臂，12,760 例）
##     流程：先跑本脚本一次 → 生成 data/finngen/snps_needed.txt
##           → 运行 tools/fetch_finngen.py → 把 FINNGEN$use_local 改为 TRUE
##           → 重跑本脚本
## ===========================================================================
fng_dir <- FINNGEN$dir
if (!dir.exists(fng_dir)) dir.create(fng_dir, recursive = TRUE)
needed <- unique(unlist(lapply(fwd, function(x) if (is.null(x)) NULL else x$dat$SNP)))
if (length(needed)) {
  writeLines(needed, file.path(fng_dir, "snps_needed.txt"))
  message("\n已写入待筛选 SNP 清单：", length(needed), " 个 → data/finngen/snps_needed.txt")
}

if (isTRUE(FINNGEN$use_local)) {
  message("\n=== 使用 FinnGen R12 本地文件作为主结局（验证臂）===")
  for (ep in names(FINNGEN$endpoints)) {
    exp0 <- fwd[[1]]
    if (is.null(exp0)) next
    od <- tryCatch(read_finngen_local(exp0$dat$SNP, FINNGEN$endpoints[[ep]], ep),
                   error = function(e) { message("读取失败：", conditionMessage(e)); NULL })
    if (is.null(od) || !nrow(od)) next
    h <- tryCatch(TwoSampleMR::harmonise_data(exp0$dat, od, action = 2),
                  error = function(e) NULL)
    if (is.null(h) || !nrow(h)) next
    r <- TwoSampleMR::mr(h, method_list = c("mr_ivw", "mr_egger_regression",
                                            "mr_weighted_median", "mr_weighted_mode"))
    r$exposure <- paste0("FinnGenR12 | MVPA -> ", ep)
    print(r[, c("exposure", "method", "nsnp", "b", "se", "pval")])
    write.csv(r, file.path(TAB_DIR, paste0("mr_finngen_r12_", ep, ".csv")), row.names = FALSE)
  }
} else {
  message("\n提示：FINNGEN$use_local = FALSE，本次使用 OpenGWAS 旧版 finn-b-* 结局（4,510 例）。")
  message("      如需 R12（12,760 例）作主结局，见上方 8b 说明。")
}

## ===========================================================================
## 9. 保存
## ===========================================================================
saveRDS(list(forward = fwd, reverse = rev_list, subtypes = sub_list,
             mvmr = mvmr_obj, mediation = med_all),
        file.path(OUT_DIR, "mr_objects.rds"))

sink(type = "message"); sink(); close(log_con)
message("\n完成。日志：output/log_04_mr.txt")
