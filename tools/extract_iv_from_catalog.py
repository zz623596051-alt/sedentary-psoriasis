#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tools/extract_iv_from_catalog.py —— MR 工具变量的「B 路径」提取

背景
----
OpenGWAS 的「按研究取全基因组建联」端点持续 502（2026-10 实测多次），
TwoSampleMR 无法自行构建工具变量。本脚本直接从 GWAS Catalog 官方发布的
全量关联表取指定研究的 p<阈值 关联。

数据源（已实测可下，2026-10-03）
    https://ftp.ebi.ac.uk/pub/databases/gwas/releases/latest/
      gwas-catalog-associations-full.zip    66 MB（解压 573 MB）
      gwas-catalog-download-studies-*.txt   53 MB（含 STUDY ACCESSION 列）

★ 两个必须知道的结构事实（实测踩过）
------------------------------------
1. **关联表没有 STUDY_ACCESSION 列**。它的列是
   DATE ADDED / PUBMEDID / FIRST AUTHOR / DATE / JOURNAL / LINK / STUDY /
   DISEASE/TRAIT / INITIAL SAMPLE SIZE / ... / CHR_ID / CHR_POS /
   STRONGEST SNP-RISK ALLELE / SNPS / CONTEXT / RISK ALLELE FREQUENCY /
   P-VALUE / PVALUE_MLOG / P-VALUE (TEXT) / OR or BETA / 95% CI (TEXT) / ...
   → 必须用「研究列表文件」按 (FIRST AUTHOR, DATE, STUDY, DISEASE/TRAIT)
     映射出 GCST accession。
2. ★★ **关联表没有「另一等位基因」（other allele）**，CONTEXT 列是变异后果
   （intron_variant / intergenic_variant），不是侧翼序列。
   → **无法直接喂给 TwoSampleMR::harmonise_data**，它需要 both alleles。
   → 补齐办法（按代价排序）：
     a) 1000G 参考面板（同时也是 r² 剪枝所必需）——一次解决两个问题；
     b) Ensembl/dbSNP REST 按 rsID 查等位基因（几十到几百个 SNP 可行）；
     c) 不做 harmonise，只做「按效应等位基因方向」的简化分析（需在
        Methods 明确说明，不推荐）。

剪枝策略
--------
标准是 r² 剪枝（需 LD 参考面板 + PLINK）。本脚本提供**距离剪枝**作为不依赖
外部服务的降级方案：按 p 升序贪心保留，剔除与已保留 SNP 物理距离 < kb 的位点。

⚠️ 距离剪枝 **≠** r² 剪枝：它无法识别同区域内 LD 低的位点，会因此丢弃过多
SNP、降低功效。若用于正式分析，必须在 Methods 中报告为 distance-based
pruning 并做敏感性分析。真正的 r² 剪枝用
`TwoSampleMR::clump_data(dat, bfile=, plink_bin=)`。

用法
----
    python tools/extract_iv_from_catalog.py --accessions GCST006097,GCST90104339 \\
        --p-threshold 5e-8 --prune-kb 10000 -o data/raw/iv_from_catalog.tsv
"""
import argparse
import csv
import io
import math
import os
import sys
import zipfile

FTP = "https://ftp.ebi.ac.uk/pub/databases/gwas/releases/latest"
ASSOC_ZIP = "gwas-catalog-associations-full.zip"
STUDIES_TSV = "gwas-catalog-download-studies-v1.0.3.1.txt"


# ------------------------------------------------------------ 关联表 → 研究映射
def build_study_map(studies_path):
    """(FIRST AUTHOR, DATE, STUDY, DISEASE/TRAIT) → [meta, ...]

    ★★ 必须存 **列表** 而不是单个 meta。
    实测踩过：同一个 (作者, 日期, 研究标题, 表型) 四元组可能对应**多个 accession**
    （例：GCST90104339 与 GCST90104340 都是 Wang Z 2022-09-07 的 "Leisure screen time"）。
    若用 dict[key] = meta，后者会覆盖前者 —— 实测 97,715 行只留下 87,436 个研究，
    约 1 万个研究被静默丢弃，其中就包括我们最需要的久坐 GWAS。
    """
    print("[1/3] 读取研究列表 → accession 映射 …", file=sys.stderr)
    m = {}
    with open(studies_path, encoding="utf-8", errors="replace") as fh:
        rd = csv.DictReader(fh, delimiter="\t")
        need = {"FIRST AUTHOR", "DATE", "STUDY", "DISEASE/TRAIT",
                "STUDY ACCESSION", "INITIAL SAMPLE SIZE"}
        if not need.issubset(set(rd.fieldnames or [])):
            print("      研究列表列名不符：%s" % (rd.fieldnames,), file=sys.stderr)
            return m
        n = 0
        for r in rd:
            acc = (r.get("STUDY ACCESSION") or "").strip()
            if not acc.startswith("GCST"):
                continue
            n += 1
            key = ((r.get("FIRST AUTHOR") or "").strip(),
                   (r.get("DATE") or "").strip(),
                   (r.get("STUDY") or "").strip(),
                   (r.get("DISEASE/TRAIT") or "").strip())
            m.setdefault(key, []).append(
                {"accession": acc,
                 "n": (r.get("INITIAL SAMPLE SIZE") or "").strip(),
                 "trait": r.get("DISEASE/TRAIT") or ""})
    print("      数据行 %d → 唯一键 %d（碰撞 %d）"
          % (n, len(m), n - len(m)), file=sys.stderr)
    return m


# ------------------------------------------------------------ 主提取
def extract(zip_path, study_map, accessions, p_thr, require_alleles=True):
    acc_set = {a.strip().upper() for a in accessions}
    zf = zipfile.ZipFile(zip_path)
    names = [n for n in zf.namelist() if n.lower().endswith((".tsv", ".txt"))]
    member = [n for n in names if "split" not in n.lower()][0] if names else zf.namelist()[0]
    print("[2/3] 流式扫描关联表（解压后约 573 MB）…", file=sys.stderr)

    rows, n_scanned, dropped = [], 0, 0
    # 目标研究键（只保留目标研究，加速匹配）
    # meta 现在是 list，键 → [meta, ...]
    target_keys = {k: [x for x in v if x["accession"] in acc_set]
                   for k, v in study_map.items()
                   if any(x["accession"] in acc_set for x in v)}
    target_keys = {k: v for k, v in target_keys.items() if v}
    # ★ 兜底键：(DISEASE/TRAIT, FIRST AUTHOR) → [meta, ...]
    #   EBI 导入条目在关联表里的 DATE/STUDY 文本可能与研究列表不一致，故需宽松匹配。
    loose_keys = {}
    for k, v in target_keys.items():
        loose_keys.setdefault((k[3], k[0]), []).extend(v)
    print("      目标研究键：%d（四元组）/ %d（兜底二元组）"
          % (len(target_keys), len(loose_keys)), file=sys.stderr)

    with zf.open(member) as fh:
        t = io.TextIOWrapper(fh, encoding="utf-8", errors="replace")
        header = t.readline().rstrip("\n").split("\t")
        ix = {name: i for i, name in enumerate(header)}

        def col(*names):
            for n in names:
                if n in ix:
                    return ix[n]
            return None

        i_author = col("FIRST AUTHOR")
        i_date = col("DATE")
        i_study = col("STUDY")
        i_trait = col("DISEASE/TRAIT")
        i_chr = col("CHR_ID")
        i_pos = col("CHR_POS")
        i_snp = col("SNPS")
        i_ra = col("STRONGEST SNP-RISK ALLELE")
        i_eaf = col("RISK ALLELE FREQUENCY")
        i_mlog = col("PVALUE_MLOG")
        i_ptext = col("P-VALUE (TEXT)")
        i_ob = col("OR or BETA")
        i_ci = col("95% CI (TEXT)")

        for line in t:
            f = line.rstrip("\n").split("\t")
            n_scanned += 1
            try:
                key = (f[i_author].strip(), f[i_date].strip(),
                       f[i_study].strip(), f[i_trait].strip())
            except IndexError:
                continue
            metas = target_keys.get(key)
            if metas is None:     # 兜底：只按 trait + first author 匹配
                metas = loose_keys.get((key[3], key[0]))
            if not metas:
                continue
            # p 值：优先用 PVALUE_MLOG（-log10 p，数值稳），回退到文本
            p = None
            if i_mlog is not None:
                try:
                    p = 10 ** (-float(f[i_mlog]))
                except Exception:
                    p = None
            if p is None and i_ptext is not None:
                try:
                    p = float(f[i_ptext].split("E")[0]) * \
                        (10 ** int(f[i_ptext].split("E")[1][1:]))
                except Exception:
                    p = None
            if p is None or p > p_thr:
                continue
            ra = f[i_ra] if i_ra is not None else ""
            # "rs2214442-A" → rsid + effect allele
            if "-" in ra:
                rsid, eff = ra.rsplit("-", 1)
            else:
                rsid, eff = ra, ""
            eff = eff.strip().upper()
            eaf = (f[i_eaf] if i_eaf is not None else "").strip()
            # ★ 数据完整性守卫：Catalog 里部分研究（实测 GCST010084 休闲久坐 n=408,815）
            #   的 effect allele 全部是 '?'、频率全是 'NR' —— 提交者未提供、Catalog 也推不出。
            #   这种位点**无法给 beta 定向**，一律丢弃，否则会得到一堆方向随机的"工具变量"。
            if require_alleles and (eff in ("", "?", "NA") or eaf in ("", "NR", "NA")):
                dropped += 1
                continue
            for meta in metas:
              rows.append({
                "accession": meta["accession"],
                "trait": meta["trait"],
                "n_samples_text": meta["n"],
                "snp": f[i_snp] if i_snp is not None else rsid,
                "chr": f[i_chr] if i_chr is not None else "",
                "pos": f[i_pos] if i_pos is not None else "",
                "effect_allele": eff,
                "other_allele": "",              # ★ 关联表不提供，须外部补齐
                "eaf": eaf,
                "p": p,
                "or_or_beta": f[i_ob] if i_ob is not None else "",
                "ci_text": f[i_ci] if i_ci is not None else "",
            })
    print("      扫描 %d 行，p<%s 命中 %d 条；因缺等位基因/频率丢弃 %d 条"
          % (n_scanned, p_thr, len(rows), dropped), file=sys.stderr)
    return rows


# ------------------------------------------------------------ 整理 + 剪枝
def to_iv(rows, prune_kb=None):
    import re
    out = []
    for r in rows:
        ob = r["or_or_beta"]
        if not ob:
            continue
        try:
            v = float(ob)
        except ValueError:
            continue
        # 连续性状（CI 文本含 unit increase/decrease）→ 是 beta，不是 OR
        is_or = "unit" not in (r["ci_text"] or "").lower()
        beta = math.log(v) if (is_or and v > 0) else v
        d = dict(r)
        d["beta"] = beta
        d["is_or"] = is_or
        d["effect_allele"] = r["effect_allele"].upper()
        out.append(d)

    # 去重：同一 (研究, SNP) 保留 p 最小
    best = {}
    for d in out:
        k = (d["accession"], d["snp"])
        if k not in best or d["p"] < best[k]["p"]:
            best[k] = d
    iv = sorted(best.values(), key=lambda x: x["p"])

    # ---- 从 95% CI 文本反推标准误，再算 F = (beta/se)^2 -------------------
    # ★ 不能用 F = beta^2 / p：GWAS 的 p 常常小到 1e-300，会让 F 爆到 1e8
    #   （实测踩过：算出 42250~8e8 这种荒谬值）。必须从 CI 拿 se。
    for d in iv:
        ns = re.findall(r"[\d,]{5,}", d["n_samples_text"] or "")
        d["n_samples"] = int(ns[0].replace(",", "")) if ns else None
        d["se"] = None
        ci = d.get("ci_text") or ""
        m = re.search(r"\[?\s*([-\d.eE+]+)\s*(?:--|-|to|–)\s*([-\d.eE+]+)\s*\]?", ci)
        if m:
            try:
                lo, hi = float(m.group(1)), float(m.group(2))
                if d["is_or"] and lo > 0 and hi > 0:
                    # 对数尺度：se = (ln hi - ln lo) / (2 * 1.96)
                    d["se"] = (math.log(hi) - math.log(lo)) / (2 * 1.96)
                else:
                    d["se"] = (hi - lo) / (2 * 1.96)
            except Exception:
                pass
        d["F"] = (d["beta"] / d["se"]) ** 2 if d.get("se") else None

    if prune_kb:
        keep, last = [], {}
        for d in iv:                      # 已按 p 升序
            try:
                c, p_ = str(d["chr"]), int(d["pos"])
            except (ValueError, TypeError):
                keep.append(d)
                continue
            if any(c == k and abs(p_ - v) < prune_kb * 1000 for k, v in last.items()):
                continue
            last[c] = p_
            keep.append(d)
        iv = keep
        print("      距离剪枝（%d kb）后保留 %d 个" % (prune_kb, len(iv)),
              file=sys.stderr)
    return iv


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", default="data/raw/gwas_catalog_associations.zip")
    ap.add_argument("--studies", default="data/raw/gwas_catalog_study_accessions.tsv")
    ap.add_argument("--accessions", required=True)
    ap.add_argument("--p-threshold", type=float, default=5e-8)
    ap.add_argument("--prune-kb", type=int, default=None)
    ap.add_argument("--allow-missing-alleles", action="store_true",
                    help="不丢弃缺效应等位基因的位点（不建议：无法给 beta 定向）")
    ap.add_argument("-o", "--out", default="data/raw/iv_from_catalog.tsv")
    a = ap.parse_args()

    for p in (a.zip, a.studies):
        if not os.path.exists(p):
            raise SystemExit("缺少 %s" % p)

    smap = build_study_map(a.studies)
    rows = extract(a.zip, smap, a.accessions.split(","), a.p_threshold,
                   require_alleles=not a.allow_missing_alleles)
    iv = to_iv(rows, a.prune_kb)

    if not iv:
        raise SystemExit("未提取到任何 IV —— 检查 --accessions 是否与研究列表匹配")

    cols = ["accession", "trait", "snp", "chr", "pos", "beta", "is_or",
            "effect_allele", "other_allele", "eaf", "p", "se", "F", "n_samples"]
    with open(a.out, "w", newline="", encoding="utf-8") as fh:
        # ★ 必须显式 delimiter="\t"：DictWriter 默认逗号，
        #   写出的是 .tsv 文件却用逗号分隔，下游按 tab 读会整行塌成一个字段。
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore", delimiter="\t")
        w.writeheader()
        w.writerows(iv)

    print("[3/3] 写出 %d 个 IV → %s" % (len(iv), a.out), file=sys.stderr)
    by = {}
    for d in iv:
        by.setdefault(d["accession"], []).append(d)
    for acc, lst in by.items():
        fvals = [d["F"] for d in lst if d["F"]]
        print("      %-14s n=%-4d  F=%.1f-%.1f  %s" % (
            acc, len(lst), min(fvals) if fvals else float("nan"),
            max(fvals) if fvals else float("nan"),
            lst[0]["trait"][:44]), file=sys.stderr)
    print("      ★ other_allele 为空 —— 必须用 1000G 面板或 Ensembl/dbSNP 补齐"
          "后才能 harmonise", file=sys.stderr)


if __name__ == "__main__":
    main()
