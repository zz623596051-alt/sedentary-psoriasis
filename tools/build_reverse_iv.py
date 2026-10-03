"""从 FinnGen R12 银屑病汇总统计构建反向 MR 的暴露侧工具变量。

背景
----
反向 MR（银屑病 → 屏幕时间）的暴露 IV 必须自己从 FinnGen R12 汇总统计里提，
因为 OpenGWAS 的 extract_instruments() 端点当前 502 不可用。

流程
----
1. 读 fetch_finngen.py --mode both 产出的 <endpoint>.iv.tsv（全部 p<5e-8 的 SNP）
2. 距离剪枝（默认 10 kb / r² 阈值 0.001，保留 p 最小者）——第一道过滤
3. 拆分多 rsID 位点（FinnGen 的 rsids 列可能是 "rs1,rs2"）
4. 输出与 tools/resolve_alleles_ld.py 兼容的 TSV，
   再由该脚本补等位基因 + 做 Ensembl 1000G r² 剪枝

用法
----
    python tools/build_reverse_iv.py --endpoint psoriasis --prune-kb 10000
"""
import argparse
import csv
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FG_DIR = os.path.join(ROOT, "data", "finngen")

ENDPOINTS = {
    "psoriasis": "finngen_R12_L12_PSORIASIS",
    "psoriasis_vulg": "finngen_R12_L12_PSORI_VULG",
    "psoriasis_arth": "finngen_R12_M13_PSORIARTH",
}


def distance_prune(rows, kb, p_col="p"):
    """按 p 升序做距离剪枝：新位点若与已保留位点距离 < kb 则丢弃。"""
    rows = sorted(rows, key=lambda r: float(r[p_col]))
    kept = []
    for r in rows:
        try:
            c = int(r["chrom"])
            p = int(r["pos"])
        except (KeyError, ValueError):
            continue
        # ★ 伪染色体（XY / MT）不参与剪枝判断，位置无法线性比较
        if c > 25:
            kept.append(r)
            continue
        hit = False
        for k in kept:
            try:
                kc = int(k["chrom"])
                kp = int(k["pos"])
            except (KeyError, ValueError):
                continue
            if kc == c and abs(kp - p) < kb * 1000:
                hit = True
                break
        if not hit:
            kept.append(r)
    return kept


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", default="psoriasis", choices=list(ENDPOINTS))
    ap.add_argument("--prune-kb", type=int, default=10000)
    ap.add_argument("-o", "--output", default=None)
    a = ap.parse_args()

    ep = ENDPOINTS[a.endpoint]
    src = os.path.join(FG_DIR, "%s.iv.tsv" % ep)
    if not os.path.exists(src):
        sys.exit("缺少 %s\n请先运行 tools/fetch_finngen.py --mode both" % src)
    out = a.output or os.path.join(FG_DIR, "%s_iv_pruned.tsv" % a.endpoint)

    with open(src, encoding="utf-8-sig") as fh:
        rd = csv.DictReader(fh, delimiter="\t")
        rows = []
        multi = 0
        for r in rd:
            ids = (r.get("rsids") or "").strip()
            if not ids or ids == ".":
                continue
            parts = [x.strip() for x in ids.split(",") if x.strip()]
            if len(parts) > 1:
                multi += 1
            for rs in parts:
                if not rs.startswith("rs"):
                    continue
                rows.append({
                    "chrom": r.get("#chrom", ""),
                    "pos": r.get("pos", ""),
                    "ref": r.get("ref", ""),
                    "alt": r.get("alt", ""),
                    "snp": rs,
                    "p": r.get("pval", ""),
                    "beta": r.get("beta", ""),
                    "se": r.get("sebeta", ""),
                    "eaf": r.get("af_alt", ""),
                    "nearest_genes": r.get("nearest_genes", ""),
                })
    print("读入 %d 个 SNP 位点（其中 %d 个多 rsID 已展开）"
          % (len(rows), multi))
    print("p<5e-8 候选：%d" % len(rows))

    kept = distance_prune(rows, a.prune_kb)
    print("距离剪枝（%d kb）后：%d" % (a.prune_kb, len(kept)))

    # 兼容 resolve_alleles_ld.py 的列名：它读 effect_allele / n_samples_text
    for r in kept:
        r["effect_allele"] = r["alt"]
        r["n_samples_text"] = "12760"      # FinnGen R12 病例数（见 config 注释）
        r["accession"] = ep
        r["trait"] = a.endpoint

    cols = ["accession", "trait", "snp", "chrom", "pos", "ref", "alt",
            "effect_allele", "eaf", "p", "beta", "se", "nearest_genes",
            "n_samples_text"]
    with open(out, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore",
                           delimiter="\t")
        w.writeheader()
        for r in kept:
            w.writerow(r)
    print("输出：%s  (%d 行)" % (os.path.relpath(out, ROOT), len(kept)))
    print("\n下一步：把该文件复制为 data/finngen/<endpoint>_iv_r2.tsv "
          "（04b 读取该固定名），或直接用 --output 指定。")
    print("然后：tools/resolve_alleles_ld.py 补等位基因 + LD 剪枝，"
          "tools/extract_outcome_from_catalog.py 取屏幕时间结局。")


if __name__ == "__main__":
    main()
