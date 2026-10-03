"""从本地 GWAS Catalog 关联表按 rsID 提取结局效应（反向 MR 用）。

为什么需要这个
--------------
反向 MR（银屑病 → 屏幕时间）的结局是 GCST90104339「Leisure screen time」。
它**不在 OpenGWAS 里**，所以 TwoSampleMR 的 extract_outcome_data() 拿不到
（该函数只覆盖 OpenGWAS 收录的研究）。必须自己从 Catalog 全量关联表里取。

输入
----
data/finngen/<endpoint>.iv.tsv        暴露侧 SNP（fetch_finngen.py --mode both 产出）
       或任意含 snp / rsid 列的 TSV

输出
----
data/finngen/outcome_screentime.tsv   列与 TwoSampleMR 的 outcome 侧一致
                                       （SNP / beta.outcome / se.outcome / ...）

匹配口径
--------
Catalog 的 SNPS 列可能是单个 rsID，也可能是 "rs1;rs2"（同一位置多个 rsID）。
两种都处理：优先取完全相等的那个，否则取分号列表中第一个能对上的。
"""
import argparse
import csv
import io
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_ZIP = os.path.join(ROOT, "data", "raw", "gwas_catalog_associations.zip")

# 目标研究：GCST90104339 = Leisure screen time (Wang Z), n=526,725
# 用 (FIRST AUTHOR, DATE, DISEASE/TRAIT) 三元组宽松匹配 —— Catalog 里
# EBI 导入条目的 STUDY/DATE 文本与研究列表不一定完全一致，故不用四元组。
TARGETS = {
    "GCST90104339": {
        "author": "Wang Z",
        "trait_prefix": "Leisure screen time",
        "label": "Leisure screen time",
    },
}

COLS = {
    "snp": "SNPS",
    "trait": "DISEASE/TRAIT",
    "author": "FIRST AUTHOR",
    "date": "DATE",
    "chr": "CHR_ID",
    "pos": "CHR_POS",
    "risk_allele": "STRONGEST SNP-RISK ALLELE",
    "eaf": "RISK ALLELE FREQUENCY",
    "p_text": "P-VALUE",
    "p_mlog": "PVALUE_MLOG",
    "ob": "OR or BETA",
    "ci": "95% CI (TEXT)",
    "or_type": "OR or BETA",
}


def p_from_text_or_mlog(p_text, p_mlog):
    """优先用 P-VALUE 原文；否则用 PVALUE_MLOG = -log10(p) 反推。"""
    if p_text:
        t = p_text.strip()
        if t and t not in ("NR", "NA", ""):
            try:
                return float(t)
            except ValueError:
                m = re.search(r"([0-9.eE+-]+)", t)
                if m:
                    try:
                        return float(m.group(1))
                    except ValueError:
                        pass
    if p_mlog:
        try:
            return 10.0 ** (-float(p_mlog))
        except (ValueError, OverflowError):
            pass
    return None


def se_from_ci(ci_text):
    """从 '1.23 (1.10-1.36)' 形式的 95% CI 反推标准误。

    Catalog 的 OR or BETA 列没有 se，必须自己算：
        se = (log(upper) - log(lower)) / (2 * 1.96)
    """
    if not ci_text:
        return None
    nums = re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", ci_text)
    if len(nums) < 2:
        return None
    try:
        lo, hi = float(nums[0]), float(nums[1])
    except ValueError:
        return None
    if lo <= 0 or hi <= 0:
        return None
    if hi <= lo:                      # 顺序颠倒
        lo, hi = hi, lo
    try:
        return (abs(__import__("math").log(hi) - __import__("math").log(lo))) / 3.92
    except (ValueError, ZeroDivisionError):
        return None


def load_snp_set(path, snp_col=None):
    """从 TSV 读一批 rsID。"""
    delim = "\t" if path.lower().endswith((".tsv", ".txt")) else ","
    with open(path, encoding="utf-8-sig") as fh:
        rd = csv.DictReader(fh, delimiter=delim)
        cols = rd.fieldnames or []
        cand = snp_col or next(
            (c for c in ("snp", "rsid", "rs_id", "SNP", "rsids") if c in cols), None)
        if not cand:
            sys.exit("找不到 SNP 列，实际列：%s" % cols)
        s = set()
        for r in rd:
            v = (r.get(cand) or "").strip()
            if v:
                s.add(v)
    print("待匹配的 rsID：%d 个（列名 %s）" % (len(s), cand))
    return s


def extract(zip_path, wanted, targets, p_max=None):
    zf = zipfile.ZipFile(zip_path)
    member = [n for n in zf.namelist() if "split" not in n.lower()][0]
    rows = []
    scanned = 0
    with zf.open(member) as fh:
        t = io.TextIOWrapper(fh, encoding="utf-8", errors="replace")
        h = t.readline().rstrip("\n").split("\t")
        ix = {k: (h.index(v) if v in h else None) for k, v in COLS.items()}
        # OR or BETA 列：同名，取第一个即可
        if ix.get("or_type") is None:
            sys.exit("找不到 OR or BETA 列")
        for line in t:
            scanned += 1
            f = line.rstrip("\n").split("\t")
            if len(f) <= ix["snp"]:
                continue
            tr = f[ix["trait"]].strip() if ix["trait"] is not None else ""
            au = f[ix["author"]].strip() if ix["author"] is not None else ""
            acc = None
            for a, meta in targets.items():
                if (tr.startswith(meta["trait_prefix"])
                        and meta["author"] in au):
                    acc = a
                    break
            if acc is None:
                continue
            # SNPS 可能是 "rs123" 或 "rs1;rs2"
            raw = f[ix["snp"]].strip()
            if not raw or raw in ("NR", "NA"):
                continue
            ids = [x.strip() for x in raw.split(";")] if ";" in raw else [raw]
            hit = next((i for i in ids if i in wanted), None)
            if hit is None:
                continue
            p = p_from_text_or_mlog(
                f[ix["p_text"]] if ix["p_text"] is not None else "",
                f[ix["p_mlog"]] if ix["p_mlog"] is not None else "")
            if p is None or p > 1 or p <= 0:
                continue
            if p_max is not None and p > p_max:
                continue
            # 效应等位：STRONGEST SNP-RISK ALLELE 形如 "rs2214442-A"
            ra = f[ix["risk_allele"]].strip() if ix["risk_allele"] is not None else ""
            eff = ra.rsplit("-", 1)[-1] if "-" in ra else ""
            if not eff or eff == "?":
                continue
            eaf = f[ix["eaf"]].strip() if ix["eaf"] is not None else ""
            eaf = None if eaf in ("NR", "NA", "") else eaf
            rows.append({
                "accession": acc,
                "SNP": hit,
                "chr": (f[ix["chr"]] if ix["chr"] is not None else ""),
                "pos": (f[ix["pos"]] if ix["pos"] is not None else ""),
                "effect_allele.outcome": eff.upper(),
                "other_allele.outcome": "",     # Catalog 不提供，须由暴露侧反推
                "eaf.outcome": eaf,
                "pval.outcome": p,
                "beta.outcome": (f[ix["ob"]] if ix["ob"] is not None else ""),
                "ci.outcome": (f[ix["ci"]] if ix["ci"] is not None else ""),
                "se.outcome": se_from_ci(
                    f[ix["ci"]] if ix["ci"] is not None else ""),
            })
    print("扫描 %s 行，匹配 %d 条" % (format(scanned, ","), len(rows)))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-i", "--input", required=True,
                    help="含 rsID 的 TSV（暴露侧 IV）")
    ap.add_argument("-o", "--output",
                    default=os.path.join(ROOT, "data", "finngen",
                                         "outcome_screentime.tsv"))
    ap.add_argument("--snp-col", default=None, help="手动指定 SNP 列名")
    ap.add_argument("--p-max", type=float, default=1.0,
                    help="只保留结局 p <= 此值（默认不过滤）")
    a = ap.parse_args()

    if not os.path.exists(CATALOG_ZIP):
        sys.exit("缺少 %s" % CATALOG_ZIP)
    wanted = load_snp_set(a.input, a.snp_col)
    rows = extract(CATALOG_ZIP, wanted, TARGETS, p_max=a.p_max)
    if not rows:
        sys.exit("未匹配到任何位点")
    cols = ["accession", "SNP", "chr", "pos", "effect_allele.outcome",
            "other_allele.outcome", "eaf.outcome", "pval.outcome",
            "beta.outcome", "se.outcome", "ci.outcome"]
    os.makedirs(os.path.dirname(a.output), exist_ok=True)
    # ★ 必须显式 delimiter="\t"（默认逗号，踩过）
    with open(a.output, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore",
                           delimiter="\t")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    ok_se = sum(1 for r in rows if r["se.outcome"])
    ok_eaf = sum(1 for r in rows if r["eaf.outcome"])
    print("输出：%s  (%d 行)" % (os.path.relpath(a.output, ROOT), len(rows)))
    print("  有 se（可算 F）：%d   有 EAF：%d" % (ok_se, ok_eaf))
    print("  唯一 SNP：%d" % len({r["SNP"] for r in rows}))
    print("\n注意：other_allele.outcome 为空是正常的 —— "
          "反向 MR 的 other_allele 由暴露侧（银屑病 IV）的 other_allele 提供，"
          "harmonise 时由 effect/other 对齐推出。")


if __name__ == "__main__":
    main()
