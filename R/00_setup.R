# ============================================================================
# 00_setup.R —— 包检查与安装（装到隔离库，不需要管理员权限）
# 运行：Rscript R/00_setup.R
# ============================================================================

Sys.setlocale("LC_CTYPE", "en_US.UTF-8")   # ★ Windows 下必须
source("R/config.R")                       # ★ 载入 .libPaths（隔离库优先）
                                           #   同时会创建 data/ 与 output/ 目录

message("包库路径：\n"); print(.libPaths())
TARGET_LIB <- .libPaths()[1]
message("安装目标库：", TARGET_LIB)
if (grepl("Program Files", TARGET_LIB, fixed = TRUE)) {
  warning("安装目标仍在 Program Files 下，可能需要管理员权限！")
}

pkgs_cran <- c(
  # 数据获取与清洗
  "nhanesA", "dplyr", "tidyr", "purrr", "stringr", "readr", "tibble", "janitor",
  # 复杂抽样与统计
  "survey", "mice", "boot",
  # 中介
  "mediation",
  # 孟德尔随机化
  "TwoSampleMR", "ieugwasr", "MRPRESSO", "MVMR", "RadialMR", "gwasglue",
  # 绘图与制表
  "ggplot2", "patchwork", "ggpubr", "forestplot", "scales", "gt"
)
# splines / stats / utils 为 base R 自带，无需安装

install_if_missing <- function(p) {
  if (requireNamespace(p, quietly = TRUE)) { message("OK   : ", p); return(invisible(TRUE)) }
  message(">>> 安装: ", p)
  ok <- tryCatch({
    install.packages(p, lib = TARGET_LIB, repos = "https://cloud.r-project.org")
    requireNamespace(p, quietly = TRUE)
  }, error = function(e) FALSE)
  if (!isTRUE(ok)) message("FAIL : ", p, "（可稍后重试，不影响其他包）")
  invisible(ok)
}

message("\n=== CRAN 包 ===")
res <- vapply(pkgs_cran, install_if_missing, logical(1))

message("\n=== GitHub 包（CRAN 上没有或版本过旧时）===")
if (!requireNamespace("remotes", quietly = TRUE))
  try(install.packages("remotes", lib = TARGET_LIB,
                       repos = "https://cloud.r-project.org"), silent = TRUE)

if (requireNamespace("remotes", quietly = TRUE)) {
  gh <- c("MRCIEU/TwoSampleMR", "WSpiller/MVMR", "rondolab/MR-PRESSO")
  for (g in gh) {
    nm <- sub(".*/", "", g)
    if (requireNamespace(nm, quietly = TRUE)) { message("OK   : ", nm); next }
    message(">>> 安装 GitHub: ", g)
    try(remotes::install_github(g, lib = TARGET_LIB, upgrade = "never"), silent = TRUE)
  }
}

message("\n=== 安装结果 ===")
report <- data.frame(
  package = c(pkgs_cran, "remotes"),
  installed = vapply(c(pkgs_cran, "remotes"), requireNamespace, logical(1), quietly = TRUE)
)
print(report)
write.csv(report, file.path(OUT_DIR, "package_status.csv"), row.names = FALSE)

n_ok <- sum(report$installed)
message(sprintf("\n可用包：%d / %d", n_ok, nrow(report)))
if (any(!report$installed)) {
  message("缺失：", paste(report$package[!report$installed], collapse = ", "))
  message("→ 主流程必需：nhanesA（下载）、survey（加权分析）、ggplot2（出图）")
  message("→ MR 必需：TwoSampleMR、ieugwasr，且需 OPENGWAS_JWT")
}
message("\n完成。状态表：output/package_status.csv")
