"""校验正文引文与参考文献表的一致性（双向）。

检查两类问题：
  1. 正文有引文，但文献表缺条目  → 必须补文献
  2. 文献表有条目，但正文未引用  → 孤儿条目，应删除或补引用
外加：格式合规（作者-年 或 数字顺序）、占位符残留。

★ 复姓处理：`van Kippersluis H.` 的姓氏是「van Kippersluis」而非「van」。
  直接 `.split()[0]` 会取到 "van"，把复姓作者误判为孤儿（实测踩过）。
  正确做法：取首作者名后**去掉末尾的首字母缩写**，剩下的才是姓。

用法：
    python tools/check_citation_integrity.py \
        --doc 10_Discussion初稿.md \
        --refs data/refs/references_verified.csv
"""
import argparse
import csv
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 常见的姓氏前缀（复姓/贵族姓氏）
NAME_PREFIX = ("van ", "von ", "de ", "del ", "della ", "di ", "da ",
               "du ", "la ", "le ", "ten ", "ter ", "dos ", "das ")


def surname(first_author_field):
    """从 'van Kippersluis H.' 提取姓氏 'van Kippersluis'。"""
    s = (first_author_field or "").strip()
    if not s:
        return ""
    parts = s.split()
    # 去掉末尾的缩写（无点、长度 <= 3）
    while parts and len(parts[-1]) <= 3 and "." not in parts[-1]:
        parts.pop()
    if not parts:
        return s
    # 若首词是已知前缀，与次词合并
    if parts[0].lower() in [p.strip().lower() for p in NAME_PREFIX]:
        return " ".join(parts[:2])
    return parts[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--doc", required=True, help="含引文的 Markdown 文件")
    ap.add_argument("--refs", required=True, help="核验后的参考文献 CSV")
    ap.add_argument("--placeholder", default="CITE-",
                    help="占位符前缀，残留即报错")
    a = ap.parse_args()

    doc = io.open(a.doc, encoding="utf-8").read()
    with io.open(a.refs, encoding="utf-8-sig") as fh:
        refs = list(csv.DictReader(fh))

    # ---- 1) 正文引文：(姓, 年) ----
    cites = set()
    for grp in re.findall(r"\(([A-Z][^()]*?\d{4}(?:\s*;\s*[^()]*?)?)\)", doc):
        for piece in grp.split(";"):
            m = re.match(
                r"\s*((?:van|von|de|del|della|di|da|du|la|le|ten|ter|dos|das)\s+)?"
                r"([A-Z][A-Za-z\-]+)"
                r"(?:\s+et\s+al\.)?(?:\s*&\s*(?:van\s+|von\s+)?[A-Z][A-Za-z\-]+)?"
                r"\s*,\s*(\d{4})", piece, re.I)
            if m:
                pre = (m.group(1) or "").strip()
                nm = m.group(2).strip()
                cites.add(((pre + " " + nm).strip() if pre else nm, m.group(3)))

    # ---- 2) 文献表条目：(姓, 年) ----
    tab = {}
    for r in refs:
        a0 = (r.get("authors", "").split(";")[0] if r.get("authors") else "")
        tab[(surname(a0), r.get("year", ""))] = r

    # ---- 3) 双向比对 ----
    print("=" * 78)
    print("引用完整性校验：%s" % os.path.basename(a.doc))
    print("=" * 78)
    print("文献表条目：%d    正文引文：%d" % (len(tab), len(cites)))

    missing = sorted(c for c in cites if c not in tab)
    orphan = sorted(t for t in tab if t not in cites)

    print()
    if missing:
        print("❌ 正文有引文但文献表缺条目（必须补）：")
        for c in missing:
            print("     %s (%s)" % c)
    else:
        print("✅ 正文所有引文在文献表中均有对应条目")
    if orphan:
        print("⚠  文献表有条目但正文未引用（应删除或补引用）：")
        for t in orphan:
            print("     %s (%s)  [%s]" % (t[0], t[1], tab[t].get("tag", "")))
    else:
        print("✅ 文献表所有条目都在正文被引用（无孤儿条目）")

    # ---- 4) 占位符残留 ----
    ph_all = re.findall(re.escape(a.placeholder) + r"\d+", doc)
    # 合法出现：在「引用对照表」的行首（| CITE-n |）—— 那是标签，不是未替换的引用
    ph = [m for m in ph_all if not re.search(r"\|\s*" + re.escape(m) + r"\s*\|", doc)]
    n_tag = len(ph_all) - len(ph)
    print()
    if ph:
        print("❌ 仍有 %d 处未替换的引用占位符：%s"
              % (len(ph), ", ".join(sorted(set(ph))[:12])))
    else:
        print("✅ 正文无未替换的引用占位符（另有 %d 处在对照表中作标签，合法）" % n_tag)

    # ---- 5) 明细 ----
    print()
    print("--- 逐条明细 ---")
    for c in sorted(cites):
        r = tab.get(c)
        if r:
            print("  %-8s %-24s %-30s %s" % (
                r.get("tag", ""), "%s (%s)" % c, r.get("journal", "")[:30],
                r.get("doi", "")))
        else:
            print("  %-8s %-24s ❌ 文献表缺失" % ("??", "%s (%s)" % c))

    # ---- 6) 汇总 ----
    n_bad = len(missing) + len(orphan) + len(ph)
    print()
    print("=" * 78)
    print("校验%s：%s" % ("通过" if n_bad == 0 else "未通过",
                          "无缺失、无孤儿、无占位符" if n_bad == 0
                          else "共 %d 项待处理" % n_bad))
    print("=" * 78)
    sys.exit(0 if n_bad == 0 else 1)


if __name__ == "__main__":
    main()
