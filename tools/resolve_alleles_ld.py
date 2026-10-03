#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tools/resolve_alleles_ld.py —— 补齐另一等位基因 + 基于 1000G 的 r² 剪枝

解决 GWAS Catalog 关联表的两个硬缺口（实测）：
  1. 没有「另一等位基因」→ 无法 harmonise
  2. 没有 LD 参考面板 → 只能做距离剪枝（会丢过多 SNP、降低功效）

方案：用 **Ensembl REST** 一次解决两个，不下载 1 GB 参考面板、不装 PLINK。
  · /variation/human/rs{id}              → mappings[0].allele_string（全部等位基因）
                                           mappings[0].{seq_region_name,start}（校验基因组版本）
                                           ambiguity（V = 回文 SNP，需按频率规则处理）
  · /ld/human/rs{id}/1000GENOMES:phase_3:EUR → 该 SNP 在 1000G EUR 中的 LD 伙伴及 r²

LD 剪枝算法（与 PLINK clump 逻辑一致，只是数据源换成 REST）：
  按 p 升序遍历；对每个 lead SNP，查它与**已保留的** lead SNP 是否 r² > 阈值，
  是则丢弃当前较弱的那个。窗口由「已保留集合」隐式限定，无需另设 kb。

用法
----
    python tools/resolve_alleles_ld.py -i data/raw/iv_from_catalog.tsv \\
        -o data/raw/iv_resolved.tsv --r2 0.001
"""
import argparse
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.request

REST = "https://rest.ensembl.org"
CACHE = "data/raw/ensembl_cache.json"
UA = {"User-Agent": "MR-IV-resolver/1.0 (academic use)"}


def _get(url, tries=3, pause=0.15):
    for k in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 429:          # 限流：退避
                time.sleep(1.5 * (k + 1))
                continue
            return None
        except Exception:
            time.sleep(0.8 * (k + 1))
    return None


class Cache:
    def __init__(self, path):
        self.path = path
        self.d = {}
        if os.path.exists(path):
            try:
                self.d = json.load(open(path, encoding="utf-8"))
            except Exception:
                self.d = {}

    def get(self, key, fn):
        if key in self.d:
            return self.d[key]
        v = fn()
        self.d[key] = v
        return v

    def save(self):
        try:
            json.dump(self.d, open(self.path, "w", encoding="utf-8"))
        except Exception:
            pass


def parse_alleles(snp, cache, want_chr=None, want_pos=None):
    """→ dict(name, alleles, assembly, chrom, pos, ambiguous) 或 None

    ★ 必须**遍历所有 mappings** 挑最合适的一个，不能直接取 mappings[0]：
      Ensembl 的 response 里同一 rsID 会有多个 assembly 的 mapping，
      mappings[0] 未必是 Catalog 用的那个，其 allele_string 可能更长
      （实测：直接取 mappings[0] 会把 41/91 个位点误判为「多等位」而丢弃）。
      选取规则：① 染色体与 pos 与 Catalog 一致 > 仅染色体一致 > 任意；
                ② 同优先级下取 allele_string 最短（等位基因最少）的那条。
    """
    def q():
        return _get("%s/variation/human/%s?content-type=application/json" % (REST, snp))
    d = cache.get("var:" + snp, q)
    if not d:
        return None
    maps = d.get("mappings") or []
    if not maps:
        return None

    def rank(m):
        astr = m.get("allele_string") or ""
        n_all = len([a for a in astr.split("/") if a.strip()])
        same_chr = want_chr is not None and str(m.get("seq_region_name")) == str(want_chr)
        same_pos = want_pos is not None and str(m.get("start")) == str(want_pos)
        if same_chr and same_pos:
            pri = 0
        elif same_chr:
            pri = 1
        else:
            pri = 2
        return (pri, n_all)

    m = min(maps, key=rank)
    astr = m.get("allele_string") or ""
    alleles = [a.strip().upper() for a in astr.split("/") if a.strip()]
    return {"name": d.get("name"),
            "alleles": alleles,
            "assembly": m.get("assembly_name"),
            "chrom": str(m.get("seq_region_name")),
            "pos": m.get("start"),
            "ambiguous": d.get("ambiguity") == "V"}


def ld_partners(snp, cache, pop="1000GENOMES:phase_3:EUR"):
    def q():
        return _get("%s/ld/human/%s/%s?content-type=application/json" % (REST, snp, pop))
    d = cache.get("ld:" + snp, q)
    if not d:
        return {}
    out = {}
    for rec in d:
        v = rec.get("variation2")
        try:
            out[v] = float(rec.get("r2"))
        except (TypeError, ValueError):
            pass
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-i", "--infile", default="data/raw/iv_from_catalog.tsv")
    ap.add_argument("-o", "--out", default="data/raw/iv_resolved.tsv")
    ap.add_argument("--r2", type=float, default=0.001, help="LD 剪枝阈值")
    ap.add_argument("--palindromic-freq", type=float, default=0.42,
                    help="回文 SNP 的 EAF 上限（超过则剔除，方向不可靠）")
    a = ap.parse_args()

    rows = list(csv.DictReader(open(a.infile, encoding="utf-8-sig"), delimiter="\t"))
    print("读入 %d 个候选 IV" % len(rows), file=sys.stderr)
    cache = Cache(CACHE)

    # ---------- 第 1 步：补另一等位基因 + 校验位点 ----------
    print("[1/2] 补齐等位基因（Ensembl variation）…", file=sys.stderr)
    resolved, drop = [], {}
    for i, r in enumerate(rows, 1):
        try:
            d_beta_raw = float(r.get("beta"))
        except (TypeError, ValueError):
            d_beta_raw = None
        d_beta = d_beta_raw          # 默认不翻转；链翻转时才取反
        snp = (r.get("snp") or "").strip()
        if not snp.startswith("rs"):
            drop["非 rsID"] = drop.get("非 rsID", 0) + 1
            continue
        info = parse_alleles(snp, cache,
                             want_chr=(r.get("chr") or "").strip() or None,
                             want_pos=(r.get("pos") or "").strip() or None)
        if not info or not info["alleles"]:
            drop["Ensembl 无记录"] = drop.get("Ensembl 无记录", 0) + 1
            continue
        ea = (r.get("effect_allele") or "").strip().upper()
        al = info["alleles"]
        # ★ 链方向兜底：Catalog 与 Ensembl 可能记录在不同的链上，
        #   表现为「效应等位不在 Ensembl 列表里」。先试互补（A<->T, C<->G），
        #   仍不在才判为不一致 —— 否则会白丢掉一批完全可用的位点。
        comp = {"A": "T", "T": "A", "C": "G", "G": "C"}
        flipped = False
        if ea not in al:
            ea_c = comp.get(ea, "")
            if ea_c and ea_c in al:
                ea, flipped = ea_c, True
        if ea not in al:
            drop["效应等位不在 Ensembl 列表"] = drop.get("效应等位不在 Ensembl 列表", 0) + 1
            continue
        if len(al) < 2:
            drop["等位基因不足"] = drop.get("等位基因不足", 0) + 1
            continue
        # ★  indel（多核苷酸等位基因，如 "ATA" / "-"）在 harmonise 中极易出错
        #   （TwoSampleMR 的 palindromic / allele matching 对多碱基支持差），
        #   实测会产出 "ATA"、"-" 这类 other_allele。保守丢弃。
        if any(len(x) != 1 for x in al):
            drop["indel 位点"] = drop.get("indel 位点", 0) + 1
            continue
        if len(al) > 2:
            # 多等位：Catalog 未给频率，无法判断「另一个」是哪个 → 保守丢弃
            drop["多等位位点(无法定向)"] = drop.get("多等位位点(无法定向)", 0) + 1
            continue
        other = [x for x in al if x != ea][0]
        if flipped:
            # 链翻转后 beta 与 beta_allele 必须同步取反，否则效应方向会错
            d_beta = -float(d_beta_raw) if d_beta_raw is not None else None
        # 位点校验：Catalog 的 chr/pos 与 Ensembl 应一致（确认同一基因组版本）
        pos_ok = ""
        cat_chr = (r.get("chr") or "").strip()
        cat_pos = (r.get("pos") or "").strip()
        if cat_chr and cat_pos and cat_chr == info["chrom"] and str(cat_pos) == str(info["pos"]):
            pos_ok = "match"
        elif cat_chr and cat_chr == info["chrom"]:
            pos_ok = "chr_ok_pos_diff"
        else:
            pos_ok = "chr_mismatch"
        d = dict(r)
        d["beta_reported"] = (r.get("beta") or "")
        d["effect_allele_reported"] = (r.get("effect_allele") or "").strip().upper()
        d["strand_flipped"] = "yes" if flipped else "no"
        d["beta"] = d_beta
        d["other_allele"] = other
        d["ensembl_alleles"] = "/".join(al)
        d["assembly"] = info["assembly"]
        d["ensembl_chr"] = info["chrom"]
        d["ensembl_pos"] = info["pos"]
        d["position_check"] = pos_ok
        d["palindromic"] = "yes" if set(al) in ({"A", "T"}, {"C", "G"}) else "no"
        resolved.append(d)
        if i % 20 == 0:
            print("      %d/%d" % (i, len(rows)), file=sys.stderr)
    print("      成功 %d，丢弃 %s" % (len(resolved), drop), file=sys.stderr)
    if not resolved:
        raise SystemExit("全部失败 —— 检查 rsID 与 Ensembl 是否匹配")

    # ---------- 第 2 步：回文 SNP 的频率规则 ----------
    n_pal = 0
    keep = []
    for d in resolved:
        if d["palindromic"] == "yes":
            try:
                eaf = float(d.get("eaf") or "nan")
            except ValueError:
                eaf = float("nan")
            if eaf == eaf and (eaf > a.palindromic_freq or eaf < 1 - a.palindromic_freq):
                drop["回文 SNP 且 EAF 极端"] = drop.get("回文 SNP 且 EAF 极端", 0) + 1
                continue
            n_pal += 1
        keep.append(d)
    resolved = keep
    print("      回文 SNP：保留 %d 个（要求 EAF 在 %.2f–%.2f 之间）"
          % (n_pal, 1 - a.palindromic_freq, a.palindromic_freq), file=sys.stderr)

    # ---------- 第 3 步：基于 1000G phase3 EUR 的 r² 剪枝 ----------
    print("[2/2] LD 剪枝（Ensembl /ld，1000G phase_3 EUR，r² > %g）…" % a.r2,
          file=sys.stderr)
    resolved.sort(key=lambda d: float(d["p"]))
    lds = {}

    def partners(snp):
        if snp not in lds:
            lds[snp] = ld_partners(snp, cache)
        return lds[snp]

    kept, pruned = [], []
    for d in resolved:
        snp = d["snp"]
        conflict = None
        for k in kept:
            r2 = partners(snp).get(k["snp"])
            if r2 is not None and r2 > a.r2:
                conflict = (k["snp"], r2)
                break
            # 反向也要查（LD 关系对称，但对方可能还没被展开）
            r2b = partners(k["snp"]).get(snp)
            if r2b is not None and r2b > a.r2:
                conflict = (k["snp"], r2b)
                break
        if conflict:
            pruned.append((snp, conflict[0], conflict[1]))
        else:
            kept.append(d)
        if len(kept) + len(pruned) >= 20 and (len(kept) + len(pruned)) % 20 == 0:
            print("      已处理 %d/%d（保留 %d）"
                  % (len(kept) + len(pruned), len(resolved), len(kept)), file=sys.stderr)

    print("      r² 剪枝：%d → %d（剔除 %d）" % (len(resolved), len(kept), len(pruned)),
          file=sys.stderr)
    for s1, s2, r2 in pruned[:15]:
        print("         %s 与 %s r²=%.3f" % (s1, s2, r2), file=sys.stderr)

    # ---------- 输出 ----------
    cols = ["accession", "trait", "snp", "chr", "pos", "beta", "is_or",
            "effect_allele", "other_allele", "eaf", "p", "se", "F",
            "n_samples", "palindromic", "position_check", "assembly"]
    with open(a.out, "w", newline="", encoding="utf-8") as fh:
        # ★ 必须显式 delimiter="\t"：DictWriter 默认逗号，写 .tsv 却用逗号分隔，
        #   下游 read.delim 会把整行读成一个字段（实测踩过）。
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore", delimiter="\t")
        w.writeheader()
        w.writerows(kept)
    cache.save()

    by = {}
    for d in kept:
        by.setdefault(d["accession"], []).append(d)
    print("\n★ 最终工具变量集（写入 %s）" % a.out, file=sys.stderr)
    for acc, lst in sorted(by.items()):
        fv = []
        for d in lst:
            try:
                fv.append(float(d.get("F")))
            except (TypeError, ValueError):
                pass
        print("   %-14s n=%-4d F=%s  %s" % (
            acc, len(lst),
            ("%.1f-%.1f" % (min(fv), max(fv))) if fv else "NA",
            lst[0]["trait"][:44]), file=sys.stderr)
    print("   丢弃明细：%s" % drop, file=sys.stderr)


if __name__ == "__main__":
    main()
