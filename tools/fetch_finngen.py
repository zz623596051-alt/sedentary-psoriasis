"""下载 FinnGen R12 汇总统计并按需筛选。

为什么要流式筛选：原始文件 814 MB（gz），直接读进 R 会占用大量内存且极慢。
本工具流式处理，只保留需要的行，输出体积通常 < 2 MB。

两种模式
--------
A) `--mode outcome`（正向 MR 用）
   输入：data/raw/iv_resolved.tsv 的 SNP 列（已解析好的暴露 IV）
   行为：流式扫描，只保留这些 SNP 在 FinnGen 结局上的效应值

B) `--mode exposure`（反向 MR 用）
   输入：无
   行为：流式扫描，保留 p < --p-threshold 的**全部**显著 SNP
        （银屑病作为暴露，其 IV 必须自己从 R12 汇总统计里提，
          因为 OpenGWAS 的 extract_instruments 端点当前 502 不可用）

用法
----
    python tools/fetch_finngen.py --mode outcome  --endpoints psoriasis
    python tools/fetch_finngen.py --mode exposure --endpoints psoriasis \
        --p-threshold 5e-8

产出
----
    data/finngen/<endpoint>.outcome.tsv   模式 A
    data/finngen/<endpoint>.iv.tsv        模式 B（含全部显著 SNP）
"""
import argparse
import csv
import gzip
import io
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "data", "finngen")
IV_FILE = os.path.join(ROOT, "data", "raw", "iv_resolved.tsv")

BASE = "https://storage.googleapis.com/finngen-public-data-r12/summary_stats/release/"

ENDPOINTS = {
    "psoriasis": "finngen_R12_L12_PSORIASIS",
    "psoriasis_vulg": "finngen_R12_L12_PSORI_VULG",
    "psoriasis_arth": "finngen_R12_M13_PSORIARTH",
    "psoriasis_nas": "finngen_R12_L12_PSORI_NAS",
}


def load_iv_snps():
    """从 iv_resolved.tsv 读暴露侧 IV 的 rsID。"""
    if not os.path.exists(IV_FILE):
        sys.exit("找不到 %s\n请先运行 tools/resolve_alleles_ld.py" % IV_FILE)
    with open(IV_FILE, encoding="utf-8-sig") as fh:
        rd = csv.DictReader(fh, delimiter="\t")
        if "snp" not in (rd.fieldnames or []):
            sys.exit("iv_resolved.tsv 中无 snp 列，实际列：%s" % (rd.fieldnames,))
        s = {r["snp"].strip() for r in rd if (r.get("snp") or "").strip()}
    print("暴露侧 IV（rsID）：%d 个" % len(s))
    return s


def fetch(endpoint_name, mode, wanted=None, p_thr=5e-8):
    """下载并筛选 FinnGen R12 汇总统计。

    mode="both" 时**单次扫描同时写两个文件**：
      - <endpoint>.outcome.tsv  只含 wanted 里的 SNP（正向 MR 的结局侧）
      - <endpoint>.iv.tsv       含全部 p<pthr 的 SNP（反向 MR 的暴露侧）
    """
    endpoint = ENDPOINTS[endpoint_name]
    url = "%s%s.gz" % (BASE, endpoint)
    do_out = mode in ("outcome", "both")
    do_exp = mode in ("exposure", "both")
    out_o = os.path.join(OUT_DIR, "%s.outcome.tsv" % endpoint)
    out_e = os.path.join(OUT_DIR, "%s.iv.tsv" % endpoint)
    print("\n--- %s [%s] ---" % (endpoint_name, mode))
    print("下载：%s" % url)

    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    hit_o = hit_e = total = 0
    with urllib.request.urlopen(req, timeout=900) as resp, \
            gzip.open(io.BufferedReader(resp), "rt", encoding="utf-8") as gz, \
            open(out_o if do_out else os.devnull, "w",
                 encoding="utf-8", newline="") as fw_o, \
            open(out_e if do_exp else os.devnull, "w",
                 encoding="utf-8", newline="") as fw_e:
        header = gz.readline()
        cols = header.rstrip("\n").split("\t")
        if do_out:
            fw_o.write(header)
        if do_exp:
            fw_e.write(header)
        i_rsids = cols.index("rsids") if "rsids" in cols else None
        i_pval = cols.index("pval") if "pval" in cols else None

        for line in gz:
            total += 1
            parts = line.rstrip("\n").split("\t")
            if do_out:
                if i_rsids is not None and len(parts) > i_rsids:
                    rs = parts[i_rsids]
                    if rs not in (".", ""):
                        ids = rs.split(",") if "," in rs else (rs,)
                        if any(i in wanted for i in ids):
                            fw_o.write(line)
                            hit_o += 1
            if do_exp:
                if i_pval is not None and len(parts) > i_pval:
                    try:
                        p = float(parts[i_pval])
                    except ValueError:
                        p = None
                    if p is not None and p < p_thr:
                        fw_e.write(line)
                        hit_e += 1
            if total % 2_000_000 == 0:
                sys.stdout.write("  已扫描 %s 行（结局 %d / 暴露 %d）\n"
                                 % (format(total, ","), hit_o, hit_e))
                sys.stdout.flush()

    if do_out:
        print("结局侧（模式 A）：保留 %s 行 → %s  (%.1f KB)"
              % (format(hit_o, ","), os.path.relpath(out_o, ROOT),
                 os.path.getsize(out_o) / 1024))
        if hit_o == 0:
            print("  ⚠️ 命中 0 —— rsids 列可能全为 '.'，需改用 #chrom:pos_ref/alt 匹配")
    if do_exp:
        print("暴露侧（模式 B）：保留 %s 行（p<%g）→ %s  (%.1f KB)"
              % (format(hit_e, ","), p_thr, os.path.relpath(out_e, ROOT),
                 os.path.getsize(out_e) / 1024))
    print("扫描总行数：%s" % format(total, ","))
    return hit_o, hit_e


def diagnose(endpoint_name, n=3):
    """打印表头与前几行原始内容，用于确认列名与 rsids 填充情况。"""
    endpoint = ENDPOINTS[endpoint_name]
    url = "%s%s.gz" % (BASE, endpoint)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    print("诊断：读取 %s 前 %d 行 …" % (endpoint, n + 1))
    with urllib.request.urlopen(req, timeout=300) as resp, \
            gzip.open(io.BufferedReader(resp), "rt", encoding="utf-8") as gz:
        for i, line in enumerate(gz):
            if i > n:
                break
            print("  " + line.rstrip("\n")[:320])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["outcome", "exposure", "both"],
                    default="outcome",
                    help="both = 单次扫描同时产出两套（推荐，省一次 814MB 下载）")
    ap.add_argument("--endpoints", default="psoriasis",
                    help="逗号分隔，可选：%s" % ",".join(ENDPOINTS))
    ap.add_argument("--p-threshold", type=float, default=5e-8,
                    help="exposure 模式下保留显著 SNP 的阈值")
    ap.add_argument("--diagnose", action="store_true",
                    help="只打印原始表头与前几行，不下载全量")
    a = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    eps = [e.strip() for e in a.endpoints.split(",") if e.strip()]
    for e in eps:
        if e not in ENDPOINTS:
            sys.exit("未知 endpoint：%s（可选：%s）" % (e, ",".join(ENDPOINTS)))

    if a.diagnose:
        diagnose(eps[0])
        return

    wanted = load_iv_snps() if a.mode in ("outcome", "both") else None
    for e in eps:
        try:
            fetch(e, a.mode, wanted=wanted, p_thr=a.p_threshold)
        except Exception as ex:
            print("❌ %s 失败：%s: %s" % (e, type(ex).__name__, ex))

    if a.mode in ("outcome", "both"):
        print("\n[正向] 下一步：把 config.R 中 FINNGEN$use_local 改为 TRUE，"
              "重跑 Rscript R/04_mr_analysis.R")
    if a.mode in ("exposure", "both"):
        print("\n[反向] 下一步：银屑病 IV 需补等位基因（Ensembl）+ "
              "结局数据从 GWAS Catalog 本地表取"
              "（extract_outcome_data 只覆盖 OpenGWAS，GCST90104339 不在其中）")


if __name__ == "__main__":
    main()
