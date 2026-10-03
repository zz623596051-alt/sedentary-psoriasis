Sys.setlocale("LC_CTYPE", "en_US.UTF-8")
out <- file("R/_syntax_report.txt", open = "wt", encoding = "UTF-8")
sink(out, split = FALSE)
files <- c("R/config.R", "R/lib_derive.R", "R/00_setup.R", "R/01_download_nhanes.R",
           "R/02_build_dataset.R", "R/03_observational_analysis.R",
           "R/04_mr_analysis.R",
           "R/04b_mr_local.R", "R/05_figures_tables.R", "R/06_table1_stats.R",
           "R/07_iv_check.R", "R/08_stats_audit_fixes.R")
for (f in files) {
  r <- tryCatch({ parse(f); "OK" }, error = function(e) paste("ERROR:", conditionMessage(e)))
  cat(sprintf("%-36s %s\n", f, r))
}
sink()
close(out)
