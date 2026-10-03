"""从 PubMed E-utilities 批量取文献元数据，用于引用核验。

用法：
    python tools/fetch_pubmed_meta.py --ids 123,456,789 --out data/refs/meta.csv
    python tools/fetch_pubmed_meta.py --query 'psoriasis AND exercise' --retmax 20

输出 CSV 列：pmid, year, journal, title, authors, doi, type
每条都带 PMID 与 DOI —— 供 nature-ref-verifier 逐条交叉核验。
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

EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _get(url, retries=3, pause=0.4):
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "MASLD-PA-Study/1.0"})
            with urllib.request.urlopen(req, timeout=45) as r:
                return r.read().decode("utf-8", errors="replace")
        except Exception as e:
            if i == retries - 1:
                print("  请求失败：%s" % e, file=sys.stderr)
                return ""
            time.sleep(1.2 * (i + 1))
    return ""


def search(query, retmax=30, sort="date"):
    url = ("%s/esearch.fcgi?db=pubmed&retmode=json&retmax=%d&sort=%s&term=%s"
           % (EUTILS, retmax, sort, urllib.parse.quote(query)))
    txt = _get(url)
    if not txt:
        return []
    try:
        return json.loads(txt)["esearchresult"].get("idlist", [])
    except (ValueError, KeyError) as e:
        print("  esearch 解析失败：%s" % e, file=sys.stderr)
        return []


def _year(rec):
    for f in ("pubdate", "epubdate", "sortpubdate"):
        d = rec.get(f)
        if d:
            m = re.search(r"(19|20)\d{2}", d)
            if m:
                return m.group(0)
    return ""


def _doi_of(rec):
    """从 ArticleIdList 里取 DOI（PubMed 的 efetch 会带上）。"""
    for aid in rec.get("articleids", []):
        if aid.get("idtype") == "doi":
            return aid.get("value", "")
    # 退回 ELocationID
    for el in rec.get("elocationid", []) or []:
        if el.get("eidtype") == "doi":
            return el.get("value", "")
    return ""


def fetch_meta(pmids):
    if not pmids:
        return []
    out = []
    B = 200
    for i in range(0, len(pmids), B):
        chunk = pmids[i:i + B]
        url = ("%s/efetch.fcgi?db=pubmed&retmode=xml&rettype=abstract&id=%s"
               % (EUTILS, ",".join(chunk)))
        xml = _get(url)
        if not xml:
            continue
        # 逐条切分 PubmedArticle
        for m in re.finditer(r"<PubmedArticle>(.*?)</PubmedArticle>", xml, re.S):
            blk = m.group(1)
            # ★★★ 关键：PubMed 的 abstract XML 里包含「参考文献列表」，
            #   整块的 <ReferenceList> 里有几十个 <ArticleId IdType="doi">。
            #   若直接全文正则匹配，抓到的是**别人论文的 DOI**（实测一篇记录
            #   有 35 个 DOI，最后一个被当成自己的 → 题名与 DOI 完全不匹配）。
            #   正确做法：只从 <PubmedData> 段的 ArticleIdList 取本篇 DOI。
            med = re.search(r"<MedlineCitation\b[^>]*>(.*?)</MedlineCitation>", blk, re.S)
            med = med.group(1) if med else blk
            pmd = re.search(r"<PubmedData\b[^>]*>(.*?)</PubmedData>", blk, re.S)
            pmd = pmd.group(1) if pmd else ""
            # 若 PubmedData 缺失（极老记录），退回只取 MedlineCitation 内的
            ref_list = re.search(r"<ReferenceList>(.*?)</ReferenceList>", med, re.S)
            if ref_list:
                med_norefs = med[:ref_list.start()] + med[ref_list.end():]
            else:
                med_norefs = med

            pm = re.search(r"<PMID[^>]*>(\d+)</PMID>", med_norefs)
            if not pm:
                continue
            ti = re.search(r"<ArticleTitle[^>]*>(.*?)</ArticleTitle>", med_norefs, re.S)
            ti_s = re.sub(r"<[^>]+>", "", ti.group(1)) if ti else ""
            ti_s = (ti_s.replace("&amp;", "&").replace("&lt;", "<")
                       .replace("&gt;", ">").replace("&quot;", '"')
                       .replace("&apos;", "'").strip())
            jr = re.search(r"<Title[^>]*>(.*?)</Title>", med_norefs, re.S)
            jr_s = re.sub(r"<[^>]+>", "", jr.group(1)).strip() if jr else ""
            # ★ 年份：JournalIssue 标签也带属性（CitedMedium="Print"），
            #   且 <PubDate> 与 <JournalIssue> 之间隔着 <Volume>/<Issue>。
            #   用"先切出 JournalIssue 段，再在里面找 PubDate/Year"两步最稳。
            yr = ""
            ji = re.search(r"<JournalIssue\b[^>]*>(.*?)</JournalIssue>",
                           med_norefs, re.S)
            seg = ji.group(1) if ji else med_norefs
            ym = re.search(r"<PubDate>.*?<Year>(\d{4})</Year>", seg, re.S)
            if ym:
                yr = ym.group(1)
            if not yr:      # PubDate 只有 MedlineDate（只有月日，年份在别处）
                ymd = re.search(r"<PubDate>.*?<MedlineDate>([^<]+)</MedlineDate>",
                                seg, re.S)
                if ymd:
                    y2 = re.search(r"(19|20)\d{2}", ymd.group(1))
                    if y2:
                        yr = y2.group(0)
            if not yr:
                y2 = re.search(r"<ArticleDate\b[^>]*>.*?<Year>(\d{4})</Year>",
                               med_norefs, re.S)
                if y2:
                    yr = y2.group(1)
            if not yr:      # 最后退回 PubmedData 的 medline 记录日期
                y3 = re.search(r'<PubMedPubDate PubStatus="medline">.*?<Year>(\d{4})</Year>',
                               pmd, re.S)
                if y3:
                    yr = y3.group(1)
            au = re.findall(r"<Author[^>]*>.*?<LastName>([^<]+)</LastName>",
                            med_norefs, re.S)
            ini = re.findall(r"<Author[^>]*>.*?<Initials>([^<]*)</Initials>",
                             med_norefs, re.S)
            # ★ DOI 只从 PubmedData 的 ArticleIdList 取（见上方说明）
            doi = ""
            for itype, ival in re.findall(
                    r"<ArticleId IdType=\"([a-z]+)\"[^>]*>([^<]+)</ArticleId>", pmd):
                if itype == "doi":
                    doi = ival
                    break
            if not doi:
                for ival in re.findall(
                        r"<ELocationID EIdType=\"doi\"[^>]*>([^<]+)</ELocationID>",
                        med_norefs):
                    doi = ival
                    break
            pt = re.search(r"<PublicationType[^>]*>([^<]+)</PublicationType>",
                           med_norefs)
            out.append({
                "pmid": pm.group(1), "year": yr, "journal": jr_s,
                "title": ti_s,
                "authors": "; ".join("%s %s" % (l, ini[k] if k < len(ini) else "")
                                     for k, l in enumerate(au[:8])),
                "n_authors": len(au),
                "doi": doi,
                "pubtype": pt.group(1) if pt else "journal-article",
            })
        print("  已取 %d / %d" % (len(out), len(pmids)), file=sys.stderr)
        time.sleep(0.4)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", default=None, help="逗号分隔的 PMID")
    ap.add_argument("--query", default=None, help="PubMed 检索式（与 --ids 二选一）")
    ap.add_argument("--retmax", type=int, default=30)
    ap.add_argument("--sort", default="date")
    ap.add_argument("-o", "--output", required=True)
    a = ap.parse_args()

    pmids = ([x.strip() for x in a.ids.split(",") if x.strip()] if a.ids
             else search(a.query, a.retmax, a.sort))
    print("PMID %d 个" % len(pmids), file=sys.stderr)
    rows = fetch_meta(pmids)
    os.makedirs(os.path.dirname(a.output), exist_ok=True)
    cols = ["pmid", "year", "journal", "title", "authors", "n_authors", "doi", "pubtype"]
    with open(a.output, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print("输出 %s（%d 条）" % (os.path.relpath(a.output, ROOT), len(rows)))
    for r in rows[:5]:
        print("  %s %s %s | %s" % (r["pmid"], r["year"], r["journal"][:28], r["title"][:70]))


if __name__ == "__main__":
    main()
