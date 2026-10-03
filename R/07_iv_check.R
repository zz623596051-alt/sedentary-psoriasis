# ============================================================================
# 07_iv_check.R —— 【已废弃 / DEPRECATED，勿再运行】
#
# ★ 结论（2026-10-03 核实）：本脚本依赖的 OpenGWAS 端点已确认不可用，
#   本项目也不再需要它。所有 IV 与双向 MR 均由 04b 本地路线完成。
#
#   1) 端点现状（2026-10-03 实测，官方 swagger v4.0.0 为证）：
#      - GET  /api/snps/associations  → 404，v4 已移除该路由
#      - POST /api/tophits            → 502（真正的工具变量端点）
#        /api/status 里 SERVICES__PIPELINE = "Error"（clumping 流水线已挂）
#      - 502 在 ~1s 内返回（不再是旧的 ~66s 超时）→ 后端进程不在，不会自愈
#      - ieugwasr 把 HTML 错误页喂给 json 解析 → 伪装成
#        "lexical error: invalid char in json text"（这个报错具有误导性）
#
#   2) 本项目实际走的路线（见 R/04b_mr_local.R）：
#      暴露侧 IV ← tools/extract_iv_from_catalog.py + tools/resolve_alleles_ld.py
#                （GWAS Catalog 关联表 + Ensembl 补等位 + Ensembl LD 1000G phase3 EUR r² 剪枝）
#      结局侧   ← tools/fetch_finngen.py 流式筛 FinnGen R12 公开桶
#      → 完全不依赖 OpenGWAS 的 tophits
#
# ★ 本脚本仍留在仓库里，仅作历史留档。再次运行只会重现 iv_check.csv 里
#   那 5 个 NA + 每次约 66s 的等待，**不产生任何新信息**。
# ★ 保留原因：若 OpenGWAS 将来恢复并重新发布含 tophits 的版本，
#   可用本脚本做一次交叉核对（验证本地提取的 IV 与官方 tophits 是否一致）。
#
# 运行（仅在上述条件成立时）：Rscript R/07_iv_check.R
# 产出：output/log_07_iv_check.txt、output/tables/iv_check.csv
#   ⚠ 这两个文件当前内容为 2026-10-03 之前的失败记录（全 NA），
#     **不可解读为"工具变量数量不足"**，只是接口失败。
#     真实 IV 数量见 output/tables/mr_local_summary.txt：
#       正向 28 个 SNP / 反向 13 个 SNP（15 个 r² 剪枝后，harmonise 保留 13）
#
# 为什么当初单独成脚本：MR 全程是网络调用，若 IV 数量不够（<10），
#   后面所有分析都会白跑。这个检查便宜，且能在正式跑之前把风险挡掉。
# ★ 每行输出后立即 flush()：网络调用可能超时被杀，不 flush 会丢掉全部缓冲。
# ============================================================================

Sys.setlocale("LC_CTYPE", "en_US.UTF-8")
source("R/config.R")
suppressPackageStartupMessages({ library(ieugwasr); library(dplyr) })

o <- file(file.path(OUT_DIR, "log_07_iv_check.txt"), open = "wt", encoding = "UTF-8")
sink(o, split = TRUE); sink(o, type = "message")
options(error = function() {
  try(sink(type = "message"), silent = TRUE); try(sink(), silent = TRUE)
  cat("\n===== R ERROR 调用栈 =====\n"); traceback(3); q(status = 1)
})

cat("=== D3 预检：各暴露的可用工具变量数（p < 5e-8，未 clumping）===\n\n")

## ---------------------------------------------------------------------------
## 运行守卫（2026-10-03 加）
## 本脚本依赖的 OpenGWAS 端点已确认 404/502，不再是本项目的IV 来源。
## 除非显式设置 OPENGWAS_RECHECK=1，否则直接退出，避免白等 5×66s 并
## 覆写 iv_check.csv 里已有的失败记录。
## ---------------------------------------------------------------------------
if (Sys.getenv("OPENGWAS_RECHECK") != "1") {
  cat("⛔ 本脚本已废弃（见文件头 DEPRECATED 说明）。\n")
  cat("   OpenGWAS 工具变量端点 404/502，IV 已改由 04b 本地路线获取。\n")
  cat("   真实 IV 数量：output/tables/mr_local_summary.txt（正向 28 / 反向 13）\n")
  cat("   如确需重跑（仅当 OpenGWAS 恢复）：OPENGWAS_RECHECK=1 Rscript R/07_iv_check.R\n\n")
  sink(type = "message"); sink(); close(o)
  quit(status = 0)
}

ids <- c(pa_mvpa      = MR$pa_mvpa,
         sedentary_tv = MR$sedentary_tv,
         pa_accel     = MR$pa_accel,
         bmi          = MR$bmi,
         crp          = MR$crp)

res <- list()
for (nm in names(ids)) {
  id <- ids[[nm]]
  if (is.null(id) || !nzchar(id)) {
    cat(sprintf("%-14s %-22s %s\n", nm, "<未配置>", "跳过")); flush(o); next
  }
  t0 <- Sys.time()
  r <- tryCatch({
    x <- ieugwasr::tophits(id = id, pval = MR$p_threshold)
    if (is.null(x) || !nrow(x)) {
      list(n = 0L, note = "无全基因组显著 SNP")
    } else {
      fst <- if ("F_stat" %in% names(x)) x$F_stat else NA
      list(n = nrow(x), note = if (all(is.na(fst))) "—" else
             sprintf("F 统计量 %.1f - %.1f", min(fst, na.rm = TRUE), max(fst, na.rm = TRUE)))
    }
  }, error = function(e)
    list(n = NA_integer_, note = paste0("FAIL: ", substr(conditionMessage(e), 1, 70))))
  dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("%-14s %-22s SNP=%-5s %-44s [%.1fs]\n", nm, id,
              ifelse(is.na(r$n), "NA", r$n), r$note, dt)); flush(o)
  res[[nm]] <- data.frame(exposure = nm, id = id, n_snips = r$n,
                          note = r$note, seconds = round(dt, 1))
}

tab <- bind_rows(res)
write.csv(tab, file.path(TAB_DIR, "iv_check.csv"), row.names = FALSE)

cat("\n=== 判定 ===\n")
for (i in seq_len(nrow(tab))) {
  n <- tab$n_snips[i]
  verdict <- if (is.na(n)) "接口失败，需重试" else
             if (n >= 10) "可作主暴露" else
             if (n >= 3)  "偏少，建议降为敏感性分析" else "不可用"
  cat(sprintf("  %-14s n=%-5s %s\n", tab$exposure[i],
              ifelse(is.na(n), "NA", n), verdict))
}
cat("\n★ 判定口径：>=10 可作主暴露；3-9 仅作敏感性分析；<3 不可用。\n")
cat("  clumping（r2<0.001, 10kb）后数量只会更少，预检值是**上界**。\n")

sink(type = "message"); sink(); close(o)
cat("IV 预检完成 → output/tables/iv_check.csv\n")
