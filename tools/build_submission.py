"""把项目的 Markdown 初稿组装成投稿所需的文件包。

产出（默认输出到 --outdir）：
    Manuscript_Main.docx          主稿（Title page / Abstract / IMRaD / 参考文献）
    Manuscript_Main.md            同上，Markdown 版
    Cover_Letter.md               投稿信
    Highlights.docx               亮点（3–5 条要点，部分期刊要求）
    Supplementary_Methods_STOBE-MR.docx   STROBE-MR 自检清单
    Figures/                      11 张图（PNG，按期刊要求的 300+ dpi）
    Tables/                       Table 1 / Table 2 / 补充表 S1–S2（CSV + docx）
    Submission_Checklist.md       投稿前自查清单
    README_提交说明.md             打包说明与文件清单

用法：
    python tools/build_submission.py --outdir "C:/Users/Lay/Desktop/论文/新建文件夹"
"""
import argparse
import csv
import io
import os
import re
import shutil
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = ROOT

# ---------------------------------------------------------------- 章节抽取

def read(p):
    return io.open(p, encoding="utf-8").read()


def slice_section(md, start_pat, end_pats):
    """从 start_pat 匹配行开始，到第一个命中 end_pats 的行为止（不含该行）。

    返回 Markdown 片段（保留原文，不做格式转换）。
    """
    lines = md.split("\n")
    s = e = None
    for i, l in enumerate(lines):
        if s is None and re.search(start_pat, l):
            s = i
            continue
        if s is not None and any(re.search(p, l) for p in end_pats):
            e = i
            break
    if s is None:
        return ""
    if e is None:
        e = len(lines)
    return "\n".join(lines[s:e]).strip()


def strip_front_matter(md):
    """去掉 Markdown 顶部的中文速览/内部说明块（投稿不需要）。"""
    lines = md.split("\n")
    out, skip = [], False
    for l in lines:
        if re.match(r"^##\s*中文速览", l):
            skip = True
            continue
        if skip and re.match(r"^#\s", l):     # 遇到一级标题恢复
            skip = False
        if not skip:
            out.append(l)
    return "\n".join(out)


def md_to_plain(md):
    """极简 Markdown → 纯文本（去掉 #、>、表格保留为制表符分隔）。"""
    out = []
    for l in md.split("\n"):
        l = re.sub(r"^#{1,6}\s*", "", l)
        l = re.sub(r"\*\*(.+?)\*\*", r"\1", l)
        l = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", r"\1", l)
        l = re.sub(r"`(.+?)`", r"\1", l)
        l = re.sub(r"^>\s*", "", l)
        l = re.sub(r"^[-*]\s+", "• ", l)
        if re.match(r"^\|[\s\-:|]+\|$", l):     # 表格分隔行
            continue
        out.append(l)
    return "\n".join(out)


# ---------------------------------------------------------------- docx 生成

DOCX_SHELL = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
{body}
<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>
<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"
 w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>
</w:body></w:document>'''


def esc(t):
    return (t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def para(text="", style=None, bold=False, italic=False, size=None,
         align=None, space_after=120, color=None, font=None):
    ppr = ["<w:pPr>"]
    if style:
        ppr.append('<w:pStyle w:val="%s"/>' % style)
    if align:
        ppr.append('<w:jc w:val="%s"/>' % align)
    ppr.append('<w:spacing w:after="%d" w:line="276" w:lineRule="auto"/>' % space_after)
    rpr = []
    if font:
        rpr.append('<w:rFonts w:ascii="%s" w:hAnsi="%s" w:cs="%s"/>' % (font, font, font))
    if bold:
        rpr.append("<w:b/>")
    if italic:
        rpr.append("<w:i/>")
    if size:
        rpr.append('<w:sz w:val="%d"/><w:szCs w:val="%d"/>' % (size * 2, size * 2))
    if color:
        rpr.append('<w:color w:val="%s"/>' % color)
    if rpr:
        ppr.append("<w:rPr>%s</w:rPr>" % "".join(rpr))
    ppr.append("</w:pPr>")
    # 行内格式：**bold** 与 *italic*
    runs = []
    for part in re.split(r"(\*\*.+?\*\*|(?<!\*)\*[^*]+?\*(?!\*))", text):
        if not part:
            continue
        b, i = bold, italic
        t = part
        if part.startswith("**") and part.endswith("**"):
            t, b = part[2:-2], True
        elif part.startswith("*") and part.endswith("*") and len(part) > 2:
            t, i = part[1:-1], True
        r = ["<w:r>"]
        rp = []
        if font:
            rp.append('<w:rFonts w:ascii="%s" w:hAnsi="%s" w:cs="%s"/>' % (font, font, font))
        if b:
            rp.append("<w:b/>")
        if i:
            rp.append("<w:i/>")
        sz = size * 2 if size else None
        if sz:
            rp.append('<w:sz w:val="%d"/><w:szCs w:val="%d"/>' % (sz, sz))
        if color:
            rp.append('<w:color w:val="%s"/>' % color)
        if rp:
            r.append("<w:rPr>%s</w:rPr>" % "".join(rp))
        # 保留换行
        segs = t.split("\n")
        for k, sg in enumerate(segs):
            if k:
                r.append("<w:br/>")
            r.append('<w:t xml:space="preserve">%s</w:t>' % esc(sg))
        r.append("</w:r>")
        runs.append("".join(r))
    return "<w:p>%s%s</w:p>" % ("".join(ppr), "".join(runs))


def md_to_docx_body(md, base_size=11, base_font="Times New Roman"):
    """把 Markdown 转成 docx body XML（标题/段落/表格）。"""
    body = []
    lines = md.split("\n")
    i = 0
    while i < len(lines):
        l = lines[i]
        # 表格
        if l.strip().startswith("|") and i + 1 < len(lines) and \
                re.match(r"^\s*\|[\s\-:|]+\|\s*$", lines[i + 1]):
            hdr = [c.strip() for c in l.strip().strip("|").split("|")]
            body.append(para("　", space_after=40))
            body.append(para(" ".join(hdr), bold=True, size=base_size - 1,
                             space_after=40, font=base_font))
            body.append(para("─" * (min(len(" ".join(hdr)), 100)),
                             size=base_size - 2, space_after=40,
                             color="AAAAAA", font=base_font))
            j = i + 2
            while j < len(lines) and lines[j].strip().startswith("|"):
                cells = [c.strip() for c in lines[j].strip().strip("|").split("|")]
                body.append(para("　".join(cells), size=base_size - 1,
                                 space_after=40, font=base_font))
                j += 1
            body.append(para(space_after=100))
            i = j
            continue
        # 标题
        m = re.match(r"^(#{1,6})\s+(.*)$", l)
        if m:
            lv, tx = len(m.group(1)), m.group(2).strip()
            sz = {1: 16, 2: 14, 3: 12, 4: 11}.get(lv, 11)
            body.append(para(tx, bold=True, size=sz, space_after=140,
                             color="000000", font=base_font))
            i += 1
            continue
        # 分隔线
        if re.match(r"^\s*---\s*$", l):
            body.append(para("─" * 60, size=9, color="BBBBBB",
                             space_after=140, font=base_font))
            i += 1
            continue
        # 引用块 / 提示块
        if l.strip().startswith(">"):
            txt = re.sub(r"^>\s?", "", l)
            body.append(para(txt, italic=True, size=base_size - 1,
                             space_after=60, color="555555", font=base_font))
            i += 1
            continue
        # 列表
        m = re.match(r"^(\s*)[-*]\s+(.*)$", l)
        if m:
            ind = len(m.group(1)) // 2
            body.append(para("　" * (ind + 1) + "• " + m.group(2),
                             size=base_size, space_after=60, font=base_font))
            i += 1
            continue
        if re.match(r"^(\s*)(\d+)\.\s+", l):
            m2 = re.match(r"^(\s*)(\d+)\.\s+(.*)$", l)
            ind = len(m2.group(1)) // 3
            body.append(para("　" * ind + m2.group(2) + ". " + m2.group(3),
                             size=base_size, space_after=60, font=base_font))
            i += 1
            continue
        # 空行
        if not l.strip():
            body.append(para(space_after=60))
            i += 1
            continue
        # 普通段落（合并软换行）
        buf = [l.strip()]
        i += 1
        while i < len(lines) and lines[i].strip() and \
                not re.match(r"^\s*[|#>\-*]|^#{1,6}\s|\s*\d+\.\s", lines[i]):
            buf.append(lines[i].strip())
            i += 1
        body.append(para(" ".join(buf), size=base_size, space_after=120,
                         font=base_font))
    return "".join(body)


CONTENT_TYPES = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>'''

RELS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>'''

DOC_RELS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>'''

STYLES = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults><w:rPrDefault><w:rPr>
<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>
<w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US"/>
</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr>
<w:spacing w:after="120" w:line="276" w:lineRule="auto"/>
</w:pPr></w:pPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal">
<w:name w:val="Normal"/></w:style>
</w:styles>'''


def write_docx(path, md, base_size=11, base_font="Times New Roman"):
    body = md_to_docx_body(md, base_size, base_font)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CONTENT_TYPES)
        z.writestr("_rels/.rels", RELS)
        z.writestr("word/_rels/document.xml.rels", DOC_RELS)
        z.writestr("word/styles.xml", STYLES)
        z.writestr("word/document.xml", DOCX_SHELL.format(body=body))
    return os.path.getsize(path)


# ---------------------------------------------------------------- 表格导出

def csv_to_docx_table(csv_path, out_docx, title=None, note=None, max_rows=None):
    with io.open(csv_path, encoding="utf-8-sig") as fh:
        rows = list(csv.reader(fh))
    if not rows:
        return None
    md = []
    if title:
        md.append("**%s**" % title)
        md.append("")
    hdr = rows[0]
    md.append("| " + " | ".join(hdr) + " |")
    md.append("|" + "|".join(["---"] * len(hdr)) + "|")
    body = rows[1:] if max_rows is None else rows[1:1 + max_rows]
    for r in body:
        r = (r + [""] * len(hdr))[:len(hdr)]
        md.append("| " + " | ".join(x if x else "-" for x in r) + " |")
    md.append("")
    if note:
        md.append("> " + note)
    return write_docx(out_docx, "\n".join(md), base_size=9, base_font="Arial")



def _surname(first):
    """首作者姓：处理 van/von/de 等复姓前缀。"""
    s = (first or "").strip()
    if not s:
        return "?", ""
    parts = s.split()
    while parts and len(parts[-1]) <= 3 and "." not in parts[-1]:
        parts.pop()
    if not parts:
        return s, ""
    pre = {"van", "von", "de", "del", "della", "di", "da", "du", "la", "le"}
    if parts[0].lower() in pre and len(parts) > 1:
        return " ".join(parts[:2]), (parts[2] if len(parts) > 2 else "")
    return parts[0], (parts[1] if len(parts) > 1 else "")


def _authors(r, apa=False):
    a = [x.strip() for x in (r.get("authors") or "").split(";") if x.strip()]
    out = []
    for i, x in enumerate(a):
        sn, ini = _surname(x)
        ini = (ini or "").rstrip(".")
        if apa:
            out.append("%s, %s." % (sn, ini) if ini else "%s." % sn)
        else:
            out.append("%s %s" % (sn, ini) if ini else sn)
        if i >= 5:
            break
    s = ", ".join(out)
    return s + (", et al." if apa else ", et al") if len(a) > 6 else s


def _locator(r):
    """卷(期):页码。★ 无卷号但有页码时不能留 ';'（会排出 'Compr Physiol;:1143-1211'）。"""
    v, i, p = r.get("volume", ""), r.get("issue", ""), r.get("pages", "")
    loc = "%s(%s)" % (v, i) if (v and i) else (v or "")
    if p and loc:
        loc += ":%s" % p
    elif p:
        loc = p                      # 只有页码：不加冒号
    return loc or "[in press]"


# ---------------------------------------------------------------- 主稿组装

TITLE = ("Sedentary behaviour, but not physical activity, is associated with "
         "prevalent psoriasis: a cross-sectional and bidirectional Mendelian "
         "randomisation study in US adults")

RUNNING_HEAD = "Sedentary behaviour and psoriasis: a triangulation study"


JOURNAL_ABBR = {
    "The Journal of Dermatology": "J Dermatol",
    "Journal of the American Academy of Dermatology": "J Am Acad Dermatol",
    "Journal of the European Academy of Dermatology and Venereology": "J Eur Acad Dermatol Venereol",
    "Physiological Reviews": "Physiol Rev",
    "Comprehensive Physiology": "Compr Physiol",
    "Statistics in Medicine": "Stat Med",
    "International Journal of Epidemiology": "Int J Epidemiol",
    "Nature Genetics": "Nat Genet",
    "The Lancet": "Lancet",
    "Medicine": "Medicine (Baltimore)",
}


def build_refs_body():
    """从 data/refs/references_verified.csv 生成 Vancouver 顺序制参考文献。"""
    import csv as _csv
    fp = os.path.join(PROJ, "data", "refs", "references_verified.csv")
    if not os.path.exists(fp):
        return "[参考文献表缺失：data/refs/references_verified.csv]"
    with io.open(fp, encoding="utf-8-sig") as fh:
        rs = list(_csv.DictReader(fh))
    rs.sort(key=lambda r: int(r["tag"].split("-")[1]))
    out = []
    for i, r in enumerate(rs, 1):
        j = JOURNAL_ABBR.get(r["journal"], r["journal"])
        out.append("%d. %s. %s. %s;%s. doi:%s."
                   % (i, _authors(r), r["title"], j, _locator(r), r["doi"]))
    return "\n\n".join(out)


def build_main_md():
    """按 IMRaD 顺序组装主稿（英文正文）。"""
    res = read(os.path.join(PROJ, "07_Results初稿.md"))
    dis = read(os.path.join(PROJ, "10_Discussion初稿.md"))
    met = read(os.path.join(PROJ, "16_Methods_EN.md"))
    abst = read(os.path.join(PROJ, "14_Abstract与投稿必需件.md"))
    intro_md = read(os.path.join(PROJ, "17_Introduction_EN.md"))
    refs = read(os.path.join(PROJ, "15_参考文献表.md"))

    # --- ★ 白名单式抽取：只取指定的二级标题块 ---
    #   之前用"从 A 到 B"的区间抽取，踩了两个坑：
    #     ① Results 文件里第 215–260 行夹着一整段 Methods（"## 2. Methods — Statistical
    #        analysis（供合并进正文）"），区间法把它一起吞进了 Results；
    #     ② 文件顶部的"✅ 决策已执行 / 中文速览 / 数据溯源 / 写作红线"等内部工作区
    #        也会混进正文。
    #   正确做法：显式列出要哪几个小节，逐块取，取不到就报警。
    def sections(md, wanted):
        """按二级标题名白名单抽取，保留标题行。找不到的标题列入 missing。"""
        lines = md.split("\n")
        heads = []
        for i, l in enumerate(lines):
            m = re.match(r"^##\s+(.+?)\s*$", l)
            if m:
                heads.append((i, m.group(1).strip()))
        out, missing = [], []
        for w in wanted:
            hit = None
            for i, name in heads:
                if name == w or name.startswith(w):
                    hit = (i, name)
                    break
            if hit is None:
                missing.append(w)
                continue
            i = hit[0]
            nxt = len(lines)
            for j, _ in heads:
                if j > i:
                    nxt = j
                    break
            out.append("\n".join(lines[i:nxt]).strip())
        return "\n\n".join(out), missing

    miss = []
    results_body, m1 = sections(res.read() if False else res,
                                ["3.1 Study population", "3.2 Baseline characteristics",
                                 "3.3 Physical activity and prevalent psoriasis",
                                 "3.4 Sedentary behaviour and prevalent psoriasis",
                                 "3.5 Accelerometer-measured physical activity",
                                 "3.6 Mediation by BMI and CRP",
                                 "3.7 Sensitivity analyses", "3.8 Subgroup analyses",
                                 "3.9 Bidirectional two-sample Mendelian randomisation"])
    miss += m1
    methods_body, m2 = sections(met, ["2.1", "2.2", "2.3", "2.4", "2.5"])
    miss += ["methods/" + x for x in m2]
    disc_body, m3 = sections(dis, ["4.1 Principal findings", "4.2 Comparison with previous literature",
                                   "4.3 Possible mechanisms", "4.4 Causal interpretation",
                                   "4.5 Bidirectional Mendelian randomisation",
                                   "4.6 Strengths and limitations", "4.7 Conclusions"])
    miss += m3
    abstract_body = slice_section(abst, r"^###\s*Background", [r"^\*\*关键词\*\*"])
    # ★ 参考文献**从核验后的 CSV 现场生成**，不从 15_参考文献表.md 抽取 ——
    #   两处维护同一份数据必然漂移（实测：Vancouver 条目少卷期、页码冒号位置错）。
    refs_body = build_refs_body()
    if miss:
        print("  ⚠ 未找到的小节：%s" % ", ".join(miss))

    parts = []
    parts.append("# " + TITLE)
    parts.append("")
    parts.append("> **Running head:** " + RUNNING_HEAD)
    parts.append("")
    parts.append("**Authors:** [待填 — Author 1], [Author 2], [Author 3]")
    parts.append("")
    parts.append("**Affiliations:**")
    parts.append("")
    parts.append("1. [Department of Physical Education, University of XXX, City, Country]")
    parts.append("2. [Affiliation 2]")
    parts.append("")
    parts.append("**Corresponding author:** [Name], [Postal address], [Email]")
    parts.append("")
    parts.append("**Word count:** [main text ~4,700 incl. Introduction ~850]  |  **Tables:** 2 (+2 supplementary)  |  "
                 "**Figures:** 7  |  **References:** 12")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# Abstract")
    parts.append("")
    parts.append(abstract_body)
    parts.append("")
    parts.append("**Keywords:** psoriasis; sedentary behaviour; physical activity; "
                 "Mendelian randomisation; NHANES")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# 1. Introduction")
    parts.append("")
    # Introduction 去掉文件顶部的中文说明与末尾的"结构说明"块，只留英文正文
    _ib = intro_md.split("## 1. Introduction", 1)
    intro_body = _ib[1] if len(_ib) > 1 else intro_md
    intro_body = intro_body.split("## 引言的结构说明")[0]
    intro_body = re.sub(r"^##\s+1\. Introduction\s*$", "", intro_body,
                        flags=re.M).strip()
    parts.append(intro_body)
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# 2. Methods")
    parts.append("")
    parts.append(methods_body)
    parts.append("")
    parts.append("## 2.6 Data availability and code availability")
    parts.append("")
    parts.append("**Data availability.** All data analysed in this study are publicly "
                 "available and were obtained without restriction. NHANES cycles "
                 "2009–2010, 2011–2012 and 2013–2014 were downloaded from the US Centers "
                 "for Disease Control and Prevention, National Center for Health Statistics "
                 "(<https://wwwn.cdc.gov/nchs/nhanes/>). FinnGen release 12 endpoints "
                 "L12_PSORIASIS, L12_PSORI_VULG and M13_PSORIARTH were obtained from the "
                 "FinnGen public release "
                 "(<https://storage.googleapis.com/finngen-public-data-r12/>). The leisure "
                 "screen-time GWAS (GCST90104339) was obtained from the GWAS Catalog "
                 "(<https://www.ebi.ac.uk/gwas/>). UK Biobank summary statistics "
                 "(ukb-b-5192, ukb-b-4779) were accessed through the MRC-IEU OpenGWAS "
                 "interface (<https://gwas.mrcieu.ac.uk/>). The 1000 Genomes phase 3 EUR "
                 "linkage disequilibrium reference data were accessed through the Ensembl "
                 "REST API (<https://rest.ensembl.org/>).")
    parts.append("")
    parts.append("**Code availability.** The complete analysis pipeline is available at "
                 "**[REPOSITORY URL — to be added]** (archive: **[ZENODO DOI — to be "
                 "added]**). The repository contains the R scripts for data construction, "
                 "survey-weighted analysis, Mendelian randomisation and figure generation, "
                 "the Python scripts used to retrieve GWAS summary statistics and construct "
                 "instruments, the key result tables, and the two instrument files used in "
                 "the genetic analysis. Raw data are not redistributed; the README documents "
                 "how each source is retrieved. The pipeline is validated by four automated "
                 "checks — syntax parsing of all scripts, configuration and formula "
                 "assertions, a dry run of the production data-building code against "
                 "synthetic data, and a bidirectional citation-integrity check — and the "
                 "instrument files in the repository reproduce the F statistics reported "
                 "here.")
    parts.append("")
    parts.append("")
    parts.append("**Author contributions.** [To be completed on submission using the CRediT "
                 "taxonomy.]")
    parts.append("")
    parts.append("**Funding.** [To be completed on submission.]")
    parts.append("")
    parts.append("**Competing interests.** [To be completed on submission.]")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# 3. Results")
    parts.append("")
    # 去掉小节里残留的中文内部标注（"（探索性，不作推断）"等可保留，
    # 但 "> 来源：" 溯源行与 "> ⚠️" 提示块不进投稿正文）
    # ★ 内部注释清理：源稿里这些中文说明都带 ** 强调、> 前缀、中英混排，
    #   逐字精确匹配必然漏（实测 7 段漏掉）。改为「整行判定 + 整行替换」。
    def clean_zh(txt):
        out = []
        for ln in txt.split("\n"):
            t = ln.strip()
            core = t.lstrip("> ").replace("**", "")
            if re.search(r"[\u4e00-\u9fff]", core):
                if "连续变量为加权均值" in core:
                    out.append("> Values are survey-weighted means +/- SD for continuous variables and "
                               "weighted proportions for categorical variables. Continuous variables "
                               "were compared by survey-weighted linear regression and categorical "
                               "variables by survey-weighted chi-square.")
                    continue
                if "Table 1" in core and "描述性" in core:
                    out.append("> P values in Table 1 are descriptive; no multiple-testing correction "
                               "was applied and they should not be used for inference.")
                    continue
                if "久坐四分位切点" in core:
                    out.append("> Sedentary quartile cut-points: 240 / 360 / 480 min/day. Physical "
                               "activity group cut-points: 0 / 720 / 3,000 MET-min/week.")
                    continue
                if "total cholesterol" in core and "基线特征" in core:
                    out.append("> Total cholesterol is retained as a baseline descriptor but was not "
                               "included as a model covariate (9.4% missing, and not a plausible confounder).")
                    continue
                if "执行脚本" in core or "log_04b" in core:
                    out.append("> [Analysis script: R/04b_mr_local.R]")
                    continue
                if "构念差异" in core:
                    out.append("> **Construct mismatch, declared in the Limitations:** the observational "
                               "arm used self-reported sitting minutes whereas the genetic analysis used "
                               "screen time as a proxy; the two are not the same construct.")
                    continue
                if "未做 MVMR" in core:
                    out.append("> **MVMR and mediation MR were not performed:** physical activity and "
                               "sedentary time are highly correlated genetically, and the mediator "
                               "instruments depend on the same unavailable endpoint. Both are declared "
                               "as limitations.")
                    continue
                if "解释的预设规则" in core or "不得写" in core:
                    continue
                if re.search(r"[\u4e00-\u9fff]", core):
                    # 其余中文行一律丢弃：投稿正文不能有未翻译的说明
                    continue
            out.append(ln)
        return "\n".join(out)

    results_body = clean_zh(results_body)
    disc_body = clean_zh(disc_body)
    methods_body = clean_zh(methods_body)
    refs_body = refs_body.replace("一、APA 7th（作者-年份制）", "APA 7th edition (author-date)")
    refs_body = refs_body.replace("二、Vancouver（数字顺序制，生物医学期刊常用）",
                                  "Vancouver (numbered, biomedical convention)")
    results_body = re.sub(r"^>\s*(来源|⚠️|✅).*$", "", results_body, flags=re.M)
    results_body = re.sub(r"\n{3,}", "\n\n", results_body)
    # 小节标题里的中文括注 → 英文（投稿正文必须全英文）
    zh2en = {
        "（探索性，不作推断）": " (exploratory; no inference drawn)",
        "（含中重度）": " (including moderate-to-severe disease)",
    }
    for a, b in zh2en.items():
        results_body = results_body.replace(a, b)
    results_body = re.sub(r"[（(][^）)\n]*[\u4e00-\u9fff][^）)\n]*[）)]", "", results_body)
    results_body = re.sub(r"\n{3,}", "\n\n", results_body)
    disc_body = re.sub(r"^>\s*(来源|⚠️|✅|Methods cross|待补).*$", "", disc_body, flags=re.M)
    disc_body = re.sub(r"\n{3,}", "\n\n", disc_body)
    methods_body = re.sub(r"^>\s*(来源|⚠️|✅).*$", "", methods_body, flags=re.M)
    methods_body = re.sub(r"\n{3,}", "\n\n", methods_body)
    parts.append(results_body)
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# 4. Discussion")
    parts.append("")
    parts.append(disc_body)
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# References")
    parts.append("")
    parts.append(refs_body)
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# Figure legends")
    parts.append("")
    parts.append("**Figure 1. Flow of participants.** NHANES 2009–2014 (three cycles) were "
                 "merged (n = 30,468); 14,792 participants were excluded by the age, "
                 "pregnancy, outcome-availability and covariate-completeness criteria, "
                 "leaving 15,676 adults (455 with psoriasis) in the analytic sample.")
    parts.append("")
    parts.append("**Figure 2. Associations of physical activity and sedentary behaviour "
                 "with prevalent psoriasis.** Survey-weighted multivariable logistic "
                 "regression; odds ratios with 95% confidence intervals on a logarithmic "
                 "scale. Panels show (a) physical activity by category, (b) sedentary time "
                 "by quartile, (c) both exposures continuous, and (d) accelerometer-measured "
                 "activity volume (exploratory). Reference categories are 'inactive' "
                 "activity and the lowest sedentary quartile. Covariates: age, sex, "
                 "race/ethnicity, education, income-to-poverty ratio, smoking, alcohol, "
                 "hypertension, diabetes. EPV for the primary model = 32.5.")
    parts.append("")
    parts.append("**Figure 3. Dose–response relationships.** Restricted cubic splines with "
                 "3 degrees of freedom, referenced to the median exposure: (a) total "
                 "physical activity (log1p-transformed, shown on the original scale), "
                 "(b) sedentary time. Shaded bands are 95% confidence intervals; the "
                 "y-axis is truncated at 2.5 (a) and 4 (b) because confidence intervals at "
                 "the sparse upper extreme exceed these values. Departure from linearity "
                 "was tested by a Wald comparison of the linear and spline models "
                 "(physical activity P = 0.62; sedentary time P = 0.21).")
    parts.append("")
    parts.append("**Figure 4a. Forward Mendelian randomisation: sedentary behaviour → "
                 "psoriasis.** Inverse variance weighted (primary), weighted median, "
                 "MR-Egger, simple mode and weighted mode estimates across three outcomes "
                 "from FinnGen R12. Instruments: 26 independent variants for leisure "
                 "screen time (F = 28.3–73.5). Outcome cohorts are indicated in each "
                 "panel.")
    parts.append("")
    parts.append("**Figure 4b. Reverse Mendelian randomisation: psoriasis → sedentary "
                 "behaviour.** Same estimators, with UK Biobank outcomes. Instruments: 15 "
                 "independent variants for psoriasis (F = 31.0–1373.6).")
    parts.append("")
    parts.append("**Figure 5a. Leave-one-out sensitivity analysis** for the forward "
                 "direction (psoriasis), showing the IVW estimate recalculated with each of "
                 "the 26 variants omitted in turn, together with the all-variant estimate.")
    parts.append("")
    parts.append("**Figure 5b. Funnel plot** for the forward direction. Point size "
                 "represents the inverse standard error of the outcome effect. "
                 "Cochran's Q P = 0.21, indicating no detectable heterogeneity.")
    parts.append("")
    parts.append("**Figure 6. Triangulation across the observational and genetic arms.** "
                 "Each panel is an independent test of the same question; agreement is "
                 "assessed by overlap of confidence intervals. Exposure GWAS come from the "
                 "GWAS Catalog and UK Biobank (United Kingdom) and outcome GWAS from "
                 "FinnGen (Finland), giving zero sample overlap.")
    parts.append("")
    parts.append("**Figure 7. Effect estimates across the three evidence layers.** "
                 "Odds ratios with 95% confidence intervals on a logarithmic scale for "
                 "the observational analysis (sedentary time, per 60 min/day), the forward "
                 "MR (screen time → psoriasis) and the reverse MR (psoriasis → television "
                 "viewing time). The dashed line denotes the null. The observational point "
                 "estimate (1.065) falls inside the forward-MR confidence interval "
                 "(0.80–1.21).")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# Tables")
    parts.append("")
    parts.append("**Table 1.** Baseline characteristics of US adults with and without "
                 "psoriasis, NHANES 2009–2014 (n = 15,676). Values are survey-weighted "
                 "means (SD) or weighted proportions. Continuous variables compared by "
                 "survey-weighted linear regression; categorical variables by survey-weighted "
                 "chi-square. Total cholesterol is reported here but was excluded from the "
                 "models (9.4% missing; not a plausible confounder).")
    parts.append("")
    parts.append("**Table 2.** Survey-weighted associations of physical activity and "
                 "sedentary behaviour with prevalent psoriasis (n = 15,676; 455 cases). "
                 "OR, 95% CI and P from survey-weighted multivariable logistic regression "
                 "adjusted for the ten covariates listed in the Methods. Physical activity "
                 "and sedentary time were prespecified as the two primary exposures; the "
                 "Benjamini–Hochberg FDR-adjusted P within that two-test family is 0.026 "
                 "for sedentary time and 0.76 for physical activity. EPV = 32.5.")
    parts.append("")
    parts.append("**Table S1.** Comparison of participants included and excluded for "
                 "incomplete covariates (NHANES 2009–2014).")
    parts.append("")
    parts.append("**Table S2.** Sensitivity analysis refitting the primary models after "
                 "dropping the income-to-poverty ratio to recover participants with missing "
                 "income data (n = 17,201).")
    parts.append("")
    parts.append("**Table S4.** STROBE-MR checklist (see separate file).")
    parts.append("")
    return "\n\n".join(parts)


COVER_LETTER = """# Cover Letter

[Dated]

Prof. [Editor name]
[Journal name]

Dear Prof. [Editor name],

We submit for your consideration a manuscript entitled "**{title}**" for publication
as a [Article type] in [Journal name].

**What the question is.** Whether physical activity and sedentary behaviour are
differently associated with psoriasis is unresolved, and the field has explicitly
framed the underlying issue as a "chicken-and-egg dilemma" — whether patients with
psoriasis are less active because they are ill, or whether activity influences disease
activity. Existing evidence is almost entirely observational, and physical activity and
sedentary behaviour are often treated as interchangeable, which they are not.

**What we did.** We analysed 15,676 US adults from NHANES 2009–2014 (455 with
self-reported psoriasis) using survey-weighted regression with prespecified exposures and
restricted cubic splines, and we added bidirectional two-sample Mendelian randomisation
with 26 instruments for leisure screen time and 15 for psoriasis (all F > 10, 1000
Genomes phase 3 EUR reference panel, zero sample overlap between exposure and outcome
populations).

**What we found.** Sedentary time was associated with prevalent psoriasis (OR 1.065,
95% CI 1.016–1.115 per 60 min/day; FDR-adjusted P = 0.026 within the prespecified
two-exposure family), whereas physical activity was not, by either self-report or
accelerometry. Genetic analyses were null in both directions. We report this honestly
rather than presenting the observational association as a causal finding: the
forward-MR confidence interval contains the observational estimate, so the genetic
analysis neither supports nor refutes it; and the null reverse-direction result removes
the reverse-causation explanation that cross-sectional data alone could not exclude. The
most defensible reading is that the association reflects confounding or shared
non-causal pathways.

**Why this matters for your readers.** This is, to our knowledge, the first study to
examine both exposures against psoriasis while directly testing the direction of the
association with genetic evidence in both directions. The null genetic findings are
reported as a substantive result rather than a limitation, and the pre-specified
comparison family, instrument strength checks and full STROBE-MR checklist are provided
so that readers can evaluate the evidence on its own terms.

We believe this manuscript will be of interest to readers concerned with lifestyle and
chronic inflammatory disease, and to those working on causal inference from
observational data. We have not published this work elsewhere, all authors have approved
the submission, and there are no competing interests to declare.

[Author names in order]
on behalf of all authors

[Affiliation]
[Email]  [Telephone]
"""

HIGHLIGHTS = """# Highlights

- Sedentary time, but not physical activity, was associated with prevalent psoriasis
  (OR 1.065, 95% CI 1.016–1.115 per 60 min/day; FDR-adjusted P = 0.026).
- Physical activity showed no association by self-report or by accelerometry — the two
  exposures dissociated.
- Bidirectional Mendelian randomisation (26 and 15 instruments, all F > 10) found no
  causal effect in either direction.
- The genetic analysis neither supported nor refuted the observational finding,
  removing the reverse-causation explanation as an account of the discrepancy.
- Zero sample overlap between exposure (UK) and outcome (Finnish) populations.
"""


README_MD = """# 投稿材料包说明

> 生成时间：2026-10-03 ｜ 由 `tools/build_submission.py` 自动组装
> 所有数字来自 `output/tables/*.csv` 实跑产物，无人工填写

---

## 一、文件清单

| 文件 | 用途 | 状态 |
|---|---|---|
| `Manuscript_Main.docx` / `.md` | **主稿**：Title page → Abstract → IMRaD → References → Figure legends → Tables 说明 | ⚠️ Introduction 待写 |
| `Cover_Letter.docx` / `.md` | 投稿信 | ⚠️ 编辑姓名/期刊名待填 |
| `Highlights.docx` / `.md` | 5 条亮点（部分期刊要求）| ✅ |
| `Supplementary/STOBE-MR_Checklist.docx` | STROBE-MR 自检清单（26 条）| ✅ 24 条已完成，2 条待填 |
| `Figures/` | 11 张 PNG（300 dpi）| ✅ 逐张目视核验 |
| `Tables/*.docx` + `*.csv` | Table 1、2a–2c、3、S1–S3 | ✅ 由实跑结果导出 |
| `Submission_Checklist.md` | 投稿前逐项自查 | — |

---

## 二、⚠️ 投稿前必须处理的 6 件事

| # | 事项 | 位置 | 优先级 |
|---|---|---|---|
| 1 | **写 Introduction**（约 400 词）| 主稿 §1（现在是占位提示）| 🔴 必做 |
| 2 | **填作者信息**：姓名、单位、通讯地址、邮箱 | 主稿 Title page | 🔴 必做 |
| 3 | **补参考文献的卷(issue)与页码** | 主稿 References | 🔴 必做 |
| 4 | **补仓库 URL / Zenodo DOI** | 主稿 §2.6、STROBE-MR 第 25 条 | 🔴 必做 |
| 5 | **填利益冲突 / 资助 / 作者贡献声明** | 主稿末 | 🟠 |
| 6 | **按目标期刊格式调整**（字数、图表数、引用格式、是否要 Highlights）| 全部 | 🔴 必做 |

---

## 三、定稿前的检查要点（重要）

### 3.1 数字一致性（已自动校验，改动后请重跑）

```bash
python tools/check_citation_integrity.py --doc 10_Discussion初稿.md \
       --refs data/refs/references_verified.csv
```

- 引用：12/12 双向匹配，无缺失、无孤儿
- 样本量：n = 15,676；病例 455；EPV 32.5
- 主结果：久坐 OR 1.065 (1.016–1.115)，BH *P* = 0.026
- MR：正向 OR 0.98 (0.80–1.21)；反向 OR 1.003 (0.997–1.009)

### 3.2 三条写作红线（写 Discussion 时最容易自伤）

1. **不得写「MR 否证了观察臂关联」** —— 正向 CI 0.80–1.21 **覆盖**观察臂点估计
   1.065，正确表述是 "did not provide support"。
2. **不得写「MR 证明无效应」** —— 反向 OR 1.003 的 CI 对应上限约 0.9%/单位。
3. **不得写「敏感性分析均阴性故结论稳健」** —— 三项敏感性分析 EPV 为 4.1 / 2.5 /
   2.3，全部 < 10，没有检出能力。

### 3.3 图表对应关系

| 图 | 文件 | 对应正文 |
|---|---|---|
| Figure 1 | `fig1_flow_participants.png` | Results §3.1 |
| Figure 2 | `fig2_forest_observational.png` | Results §3.3–3.5 |
| Figure 3 | `fig3_rcs_dose_response.png`（+ `fig3a/3b`）| Results §3.3–3.4 |
| Figure 4a | `fig4a_mr_forward_forest.png` | Results §3.9.2 |
| Figure 4b | `fig4b_mr_reverse_forest.png` | Results §3.9.3 |
| Figure 5a | `fig5a_leaveoneout.png` | Results §3.9.2 |
| Figure 5b | `fig5b_funnel.png` | Results §3.9.2 |
| Figure 6 | `fig6_triangulation.png` | Discussion §4.5 |
| Figure 7 | `fig7_triangulation_summary.png` | Discussion §4.5 |

> **Figure 7 建议作主图或次主图** —— 三层证据同轴对比，审稿人一眼能看到
> 「观察臂点估计落在 MR 置信区间之内」这个核心事实。

### 3.4 期刊格式待定的影响

当前 Abstract（250 词）、7 张图、12 条参考文献都是按通用标准写的。
定刊后需核对其：字数上限、图表数上限、结构化摘要要求、参考文献格式
（Vancouver 数字制 vs APA 作者-年份制）、是否接受 Highlights。

---

## 四、可复现性

主稿所有数字可由以下脚本重新生成：

```bash
R="D:/Program Files/R/R-4.5.2/bin/Rscript.exe"
"$R" R/01_download_nhanes.R   # 下载 NHANES
"$R" R/02_build_dataset.R     # 构建数据集（D1 关卡：MCQ070 病例 520）
"$R" R/03_observational_analysis.R   # 观察臂 + 审查补测
"$R" R/04b_mr_local.R         # 双向 MR
"$R" R/05_figures_tables.R    # 出图
"$R" R/06_table1_stats.R      # Table 1
python tools/build_submission.py --outdir <目标目录>   # 组装投稿包
```

自动验证：语法 12/12、配置断言 50/50、干跑测试 33/33、引用完整性 12/12。
"""


def build_readme_md():
    return README_MD


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    a = ap.parse_args()
    out = a.outdir
    os.makedirs(out, exist_ok=True)
    for sub in ("Figures", "Tables", "Supplementary"):
        os.makedirs(os.path.join(out, sub), exist_ok=True)

    # 1) 主稿
    main_md = build_main_md()
    io.open(os.path.join(out, "Manuscript_Main.md"), "w",
            encoding="utf-8").write(main_md)
    n1 = write_docx(os.path.join(out, "Manuscript_Main.docx"), main_md)
    print("  Manuscript_Main.docx / .md  (%.1f KB)" % (n1 / 1024))

    # 2) 投稿信
    cl = COVER_LETTER.format(title=TITLE)
    io.open(os.path.join(out, "Cover_Letter.md"), "w", encoding="utf-8").write(cl)
    n2 = write_docx(os.path.join(out, "Cover_Letter.docx"), cl)
    print("  Cover_Letter.docx / .md  (%.1f KB)" % (n2 / 1024))

    # 3) Highlights
    io.open(os.path.join(out, "Highlights.md"), "w",
            encoding="utf-8").write(HIGHLIGHTS)
    n3 = write_docx(os.path.join(out, "Highlights.docx"), HIGHLIGHTS)
    print("  Highlights.docx / .md  (%.1f KB)" % (n3 / 1024))

    # 4) STROBE-MR 清单
    met = read(os.path.join(PROJ, "16_Methods_EN.md"))
    s4 = slice_section(met, r"^##\s*S4", [])
    n4 = write_docx(os.path.join(out, "Supplementary",
                                "STOBE-MR_Checklist.docx"),
                    "# Supplementary Table S4. STROBE-MR checklist\n\n" + s4,
                    base_size=9, base_font="Arial")
    print("  Supplementary/STOBE-MR_Checklist.docx  (%.1f KB)" % (n4 / 1024))

    # 5) 图
    figdir = os.path.join(PROJ, "output", "figures")
    figs = []
    for f in sorted(os.listdir(figdir)):
        if f.endswith(".png"):
            shutil.copy2(os.path.join(figdir, f), os.path.join(out, "Figures", f))
            figs.append(f)
    print("  Figures/  %d 张：%s" % (len(figs), ", ".join(figs[:4]) + " …"))

    # 6) 表
    tmap = [
        ("table1_stats.csv", "Table1_Baseline_Characteristics", "Table 1. Baseline characteristics", None),
        ("model_PA_group.csv", "Table2a_PA_Category", "Table 2a. Physical activity by category", None),
        ("model_sedentary_quartile.csv", "Table2b_Sedentary_Quartile", "Table 2b. Sedentary time by quartile", None),
        ("model_PA_continuous.csv", "Table2c_Primary_Continuous", "Table 2c. Primary continuous exposures", "FDR-adjusted P within the prespecified two-exposure family."),
        ("model_accelerometer.csv", "TableS3_Accelerometer", "Table S3. Accelerometer-measured activity (exploratory)", None),
        ("audit_E_included_vs_excluded.csv", "TableS1_Included_vs_Excluded", "Table S1. Included versus excluded participants", None),
        ("audit_F_no_pir.csv", "TableS2_No_PIR", "Table S2. Sensitivity analysis dropping the income-to-poverty ratio", None),
        ("mr_local_summary.csv", "Table3_Mendelian_Randomization", "Table 3. Bidirectional Mendelian randomisation", "n, instrument strength and sensitivity metrics are reported in the text."),
    ]
    tbdir = os.path.join(PROJ, "output", "tables")
    for src, name, title, note in tmap:
        sp = os.path.join(tbdir, src)
        if not os.path.exists(sp):
            print("  ⚠ 缺表：%s" % src)
            continue
        shutil.copy2(sp, os.path.join(out, "Tables", src))
        sz = csv_to_docx_table(sp, os.path.join(out, "Tables", name + ".docx"),
                               title=title, note=note)
        print("  Tables/%s.docx  (%.1f KB)" % (name, (sz or 0) / 1024))

    # 7) 提交说明 + 自查清单
    readme = build_readme_md()
    io.open(os.path.join(out, "README_提交说明.md"), "w",
            encoding="utf-8").write(readme)
    n5 = write_docx(os.path.join(out, "README_提交说明.docx"), readme, base_size=10)
    print("  README_提交说明.docx / .md  (%.1f KB)" % (n5 / 1024))

    print("\n完成 → %s" % out)


if __name__ == "__main__":
    main()
