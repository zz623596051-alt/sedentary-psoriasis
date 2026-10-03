# ============================================================================
# 01_download_nhanes.R —— 下载 NHANES 2009-2014 全部所需文件（银屑病项目）
# 运行：Rscript R/01_download_nhanes.R  （工作目录 = 项目根目录）
# 产出：data/raw/<CODE>.rds  +  output/download_manifest.csv
# 说明：周期由 config.R 的 NHANES_CYCLES 控制（F/G/H = 2009-2014）
# ============================================================================

Sys.setlocale("LC_CTYPE", "en_US.UTF-8")   # ★ Windows 下必须

source("R/config.R")

log_con <- file(file.path(OUT_DIR, "log_01_download.txt"), open = "wt", encoding = "UTF-8")
sink(log_con, split = TRUE)
sink(log_con, type = "message")   # ★ 同时捕获 message()/warning()（默认 sink 只管 stdout）

suppressPackageStartupMessages({
  if (!requireNamespace("nhanesA", quietly = TRUE))
    stop("请先运行 Rscript R/00_setup.R 安装 nhanesA")
  library(nhanesA)
})

message("=== NHANES 下载开始 ", format(Sys.time()), " ===")
message("周期：", paste(NHANES_CYCLES, collapse = ", "),
        "  (", paste(NHANES_YEARS, collapse = ", "), ")")

manifest <- list()

for (i in seq_along(NHANES_CYCLES)) {
  cyc <- NHANES_CYCLES[i]
  message("\n--- 周期 ", cyc, " (", NHANES_YEARS[i], ") ---")

  for (f in NHANES_FILES) {
    if (f == ACC_PREFIX && !(cyc %in% PAM_CYCLES)) {
      message("  skip  : ", f, "_", cyc, "  (该周期无加速度计)")
      manifest[[paste0(f, "_", cyc)]] <- "skipped(no PAM)"
      next
    }
    code <- paste0(f, "_", cyc)
    out  <- file.path(RAW_DIR, paste0(code, ".rds"))

    if (file.exists(out)) {
      message("  cached: ", code)
      manifest[[code]] <- "cached"
      next
    }

    res <- tryCatch({
      # ★ translated = FALSE：保留原始数字编码（7/9 等缺失码、MCQ070 的 1/2）
      #   若用默认 translated = TRUE，MCQ070 会变成 "Yes"/"No" 因子，
      #   下游 psoriasis_ever == 1 的判断会静默失效！
      # ★ nhanesA 1.4.1 的 nhanes() 不接受 cache 参数（旧版才有）
      df <- nhanesA::nhanes(code, translated = FALSE)
      if (is.null(df) || nrow(df) == 0) stop("empty table")
      saveRDS(df, out)
      sprintf("ok(n=%d)", nrow(df))
    }, error = function(e) paste0("FAIL: ", conditionMessage(e)))
    message("  ", code, " -> ", res)
    manifest[[code]] <- res
  }
}

mf <- data.frame(code = names(manifest), status = unlist(manifest),
                 stringsAsFactors = FALSE)
mf$file <- file.path("data/raw", paste0(mf$code, ".rds"))
write.csv(mf, file.path(OUT_DIR, "download_manifest.csv"), row.names = FALSE)

ok <- sum(grepl("^ok|cached", mf$status))
message("\n=== 下载完成：成功 ", ok, " / 共 ", nrow(mf), " ===")
print(mf)

# --- ★ 关键校验：银屑病变量是否真的存在（防跨周期变量缺失）------------------
mcq_files <- file.path(RAW_DIR, paste0("MCQ_", NHANES_CYCLES, ".rds"))
mcq_files <- mcq_files[file.exists(mcq_files)]
message("\n=== 银屑病变量校验（MCQ070 / MCQ075 / MCQ195）===")
for (f in mcq_files) {
  x <- readRDS(f); cyc <- sub("^MCQ_(.*)\\.rds$", "\\1", basename(f))
  has070 <- VARMAP$psoriasis_ever   %in% names(x)
  has075 <- VARMAP$psoriasis_degree %in% names(x)
  has195 <- VARMAP$arthritis_type   %in% names(x)
  n070 <- if (has070) sum(x[[VARMAP$psoriasis_ever]] == 1, na.rm = TRUE) else NA
  message(sprintf("  %s (%s): MCQ070=%s (病例=%s) | MCQ075=%s | MCQ195=%s",
                  basename(f), NHANES_YEARS[match(cyc, NHANES_CYCLES)],
                  has070, ifelse(is.na(n070), "-", n070), has075, has195))
}
message("★ 预期病例数：F=191, G=167, H=162，合计 520（若不符请核对代码本版本）")

# --- 加速度计字段核对 --------------------------------------------------------
pam_pat  <- paste0("^", ACC_PREFIX, "_(", paste(PAM_CYCLES, collapse = "|"), ")\\.rds$")
pam_files <- list.files(RAW_DIR, pattern = pam_pat, full.names = TRUE)
if (length(pam_files) > 0) {
  pam <- readRDS(pam_files[1])
  message("\n=== PAM 字段核对（", basename(pam_files[1]), "）===")
  print(grep("^PAX", names(pam), value = TRUE))
  message("★ 请确认 config.R 中 acc_mean_mims 是否等于上述字段之一")
} else {
  message("\n未找到 PAM 文件（加速度计为敏感性分析臂，缺失不阻断主流程）")
}

sink(type = "message"); sink(); close(log_con)
message("日志已写入 output/log_01_download.txt")
