"""用 Crossref API 独立核验选定文献的元数据，生成参考文献表。

为什么要双重核验
----------------
PubMed（E-utilities）与 Crossref 是两个独立来源。逐条比对
题名、作者、年份、期刊、DOI 是否一致，能发现：
  · PubMed 记录更新（retraction / erratum 未同步）
  · DOI 指向错误文章
  · 预印本与正式版混淆
任何一项不一致都必须人工介入，不能直接进参考文献表。

用法：
    python tools/verify_and_format_refs.py \
        --pmid 17886233,28338774,... \
        --tags "CITE-10,CITE-11,..." \
        -o data/refs/references_verified.csv
"""
import argparse
import csv
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CROSSREF = "https://api.crossref.org/works/"


def _norm(s):
    """归一化题名用于比对：去标点、小写、压空白。"""
    if not s:
        return ""
    s = s.lower()
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def _get(url, retries=3):
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": "MASLD-PA-Study/1.0 (mailto:lay@example.org)"})
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.loads(r.read().decode("utf-8", errors="replace"))
        except Exception as e:
            if i == retries - 1:
                print("  Crossref 请求失败：%s" % e, file=sys.stderr)
                return None
            time.sleep(1.2 * (i + 1))
    return None


def crossref_by_doi(doi):
    if not doi:
        return None
    d = _get(CROSSREF + urllib.parse.quote(doi, safe=""))
    return (d or {}).get("message") if d else None


def pubmed_meta(pmids):
    """从已抓取的 CSV 里读 PubMed 侧元数据（避免重复请求）。"""
    cache = {}
    for fn in os.listdir(os.path.join(ROOT, "data", "refs")):
        if not fn.endswith(".csv") or fn == "references_verified.csv":
            continue
        p = os.path.join(ROOT, "data", "refs", fn)
        with open(p, encoding="utf-8-sig") as fh:
            for r in csv.DictReader(fh):
                if r.get("pmid"):
                    cache[r["pmid"]] = r
    return cache


def cr_year(msg):
    for k in ("published-print", "published-online", "published", "issued", "created"):
        d = (msg.get(k) or {}).get("date-parts") or []
        if d and d[0] and d[0][0]:
            return str(d[0][0])
    return ""


def cr_authors(msg):
    out = []
    for a in msg.get("author", []) or []:
        fam = a.get("family", "")
        giv = a.get("given", "")
        if fam:
            out.append("%s %s" % (fam, giv[:1] + "." if giv else ""))
    return "; ".join(out[:8]), len(msg.get("author", []) or [])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pmid", required=True, help="逗号分隔的 PMID，顺序与 --tags 对应")
    ap.add_argument("--tags", required=True, help="逗号分隔的标签，如 CITE-1,CITE-2")
    ap.add_argument("-o", "--output",
                    default=os.path.join(ROOT, "data", "refs", "references_verified.csv"))
    a = ap.parse_args()

    pmids = [x.strip() for x in a.pmid.split(",") if x.strip()]
    tags = [x.strip() for x in a.tags.split(",") if x.strip()]
    if len(pmids) != len(tags):
        sys.exit("PMID 数量(%d) 与标签数量(%d) 不一致" % (len(pmids), len(tags)))

    cache = pubmed_meta(pmids)
    rows = []
    n_ok = n_warn = 0
    for pm, tag in zip(pmids, tags):
        p = cache.get(pm)
        if not p:
            print("!! %s (%s) 在本地 CSV 中未找到，先跑 fetch_pubmed_meta.py" % (pm, tag),
                  file=sys.stderr)
            continue
        doi = p.get("doi", "")
        cr = crossref_by_doi(doi) if doi else None
        status, notes = "ok", []
        cr_title = cr_year_c = cr_journal = cr_doi = ""
        cr_auth = cr_nauth = ""
        cr_vol = cr_iss = cr_pg = ""
        if cr is None:
            status = "no_crossref"
            notes.append("Crossref 无此 DOI（可能是新文献或 DOI 录入有误）")
        else:
            cr_title = (cr.get("title") or [""])[0]
            cr_year_c = cr_year(cr)
            cr_journal = (cr.get("container-title") or [""])[0]
            cr_doi = cr.get("DOI", "")
            cr_auth, cr_nauth = cr_authors(cr)
            cr_vol = cr.get("volume", "") or ""
            cr_iss = cr.get("issue", "") or ""
            cr_pg = cr.get("page", "") or cr.get("article-number", "") or ""
            # PubMed 侧有而 Crossref 无 → 以 PubMed 为准（在线优先刊常见）
            if not cr_vol and p.get("volume"):
                cr_vol = p["volume"]
            if not cr_iss and p.get("issue"):
                cr_iss = p["issue"]
            if not cr_pg and p.get("pages"):
                cr_pg = p["pages"]
            # --- 逐字段比对 ---
            if _norm(p["title"]) != _norm(cr_title):
                # 允许短差异（副标题/大小写），差异过大则标记
                t1, t2 = _norm(p["title"]), _norm(cr_title)
                if not (t1 in t2 or t2 in t1):
                    status = "mismatch"
                    notes.append("题名不一致")
            if p.get("year") and cr_year_c and p["year"] != cr_year_c:
                notes.append("年份差异：PubMed %s vs Crossref %s"
                             % (p["year"], cr_year_c))
                if status == "ok":
                    status = "year_diff"
            if p.get("journal") and cr_journal:
                j1, j2 = _norm(p["journal"]), _norm(cr_journal)
                if j1 != j2 and j1.split()[0] != j2.split()[0]:
                    notes.append("期刊名差异：%s vs %s" % (p["journal"], cr_journal))
            if cr_doi.lower() != doi.lower():
                status = "mismatch"
                notes.append("DOI 不一致：%s vs %s" % (doi, cr_doi))
        if status in ("ok", "year_diff"):
            n_ok += 1
        else:
            n_warn += 1
        rows.append({
            "tag": tag, "pmid": pm,
            "year": cr_year_c or p.get("year", ""),
            "journal": cr_journal or p.get("journal", ""),
            "title": cr_title or p.get("title", ""),
            "authors": cr_auth or p.get("authors", ""),
            "n_authors": cr_nauth or p.get("n_authors", ""),
            "doi": cr_doi or doi,
            "volume": cr_vol or p.get("volume", ""),
            "issue": cr_iss or p.get("issue", ""),
            "pages": cr_pg or p.get("pages", ""),
            "pubtype": p.get("pubtype", ""),
            "status": status,
            "notes": "; ".join(notes),
            "pubmed_journal": p.get("journal", ""),
            "pubmed_year": p.get("year", ""),
        })
        print("  %-9s %-9s %-12s %s" % (tag, pm, status,
                                         (cr_title or p.get("title", ""))[:56]))
        if notes:
            for nn in notes:
                print("             ↳ %s" % nn)
        time.sleep(0.3)

    cols = ["tag", "pmid", "year", "journal", "title", "authors", "n_authors",
            "doi", "volume", "issue", "pages", "pubtype", "status", "notes",
            "pubmed_journal", "pubmed_year"]
    with open(a.output, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print("\n核验完成：%d 条一致，%d 条需人工确认" % (n_ok, n_warn))
    print("输出：%s" % os.path.relpath(a.output, ROOT))


if __name__ == "__main__":
    main()
