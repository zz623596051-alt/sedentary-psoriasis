"""汇总本地版双向 MR 的全部结果，写成一张可读的表。

用法：python tools/summarize_mr_local.py
产出：output/tables/mr_local_summary.txt 与 .csv
"""
import csv
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAB = os.path.join(ROOT, "output", "tables")

LABELS = {
    "fwd_psoriasis": ("正向：屏幕时间 -> 银屑病", "FinnGen R12 (12,760 例)"),
    "fwd_psoriasis_vulg": ("正向：屏幕时间 -> 寻常型银屑病", "FinnGen R12 (7,912 例)"),
    "fwd_psoriasis_arth": ("正向：屏幕时间 -> 银屑病关节炎", "FinnGen R12 (4,290 例)"),
    "rev_sedentary_5192": ("反向：银屑病 -> 电视观看时间", "UKB (437,887 人)"),
    "rev_sedentary_4779": ("反向：银屑病 -> 玩电脑游戏", "UKB (462,433 人)"),
}
ORDER = list(LABELS)


def read(fn):
    p = os.path.join(TAB, fn)
    if not os.path.exists(p):
        return None
    with open(p, encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))


def fnum(x, d=3):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    rows, sens = [], []
    for tag in ORDER:
        rs = read("mr_local_%s_main.csv" % tag)
        if not rs:
            continue
        lab, outcome = LABELS[tag]
        for r in rs:
            rows.append({
                "analysis": tag, "label": lab, "outcome_dataset": outcome,
                "method": r.get("method", ""), "nsnp": r.get("nsnp", ""),
                "or": r.get("or", ""), "or_lci": r.get("or_lci", ""),
                "or_uci": r.get("or_uci", ""), "pval": r.get("pval", ""),
            })
        het = read("mr_local_%s_heterogeneity.csv" % tag)
        ple = read("mr_local_%s_pleiotropy.csv" % tag)
        q = ivw = ea = None
        if het:
            h = next((x for x in het if "Weighted" in x.get("method", "")), het[0])
            q = fnum(h.get("Q_pval"))
        if ple:
            ivw = fnum(ple[0].get("pval"))
            ea = fnum(ple[0].get("egger_intercept"))
        sens.append({"analysis": tag, "label": lab, "nsnp": rs[0].get("nsnp", ""),
                     "Q_pval_heterogeneity": q, "egger_intercept": ea,
                     "egger_intercept_pval": ivw})

    out_csv = os.path.join(TAB, "mr_local_summary.csv")
    cols = ["analysis", "label", "outcome_dataset", "method", "nsnp",
            "or", "or_lci", "or_uci", "pval"]
    with open(out_csv, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore",
                           delimiter="\t")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    sens_csv = os.path.join(TAB, "mr_local_sensitivity.csv")
    with open(sens_csv, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(sens[0].keys()),
                           extrasaction="ignore", delimiter="\t")
        w.writeheader()
        for r in sens:
            w.writerow(r)

    lines = []
    lines.append("=" * 108)
    lines.append("本地汇总统计版双向 MR 结果汇总")
    lines.append("=" * 108)
    lines.append("")
    for tag in ORDER:
        rs = [r for r in rows if r["analysis"] == tag]
        if not rs:
            continue
        lab, outcome = LABELS[tag]
        lines.append("【%s】  结局数据：%s" % (lab, outcome))
        lines.append("-" * 108)
        lines.append("  %-30s %5s %8s %20s %10s"
                     % ("方法", "SNP", "OR", "95% CI", "p"))
        for r in rs:
            star = "IVW" if "Inverse variance" in r["method"] else "   "
            lines.append("  %-30s %5s %8.3f  [%6.3f, %6.3f] %10.4f  %s"
                         % (r["method"][:30], r["nsnp"], fnum(r["or"]),
                            fnum(r["or_lci"]), fnum(r["or_uci"]),
                            fnum(r["pval"], 4), star))
        s = next((x for x in sens if x["analysis"] == tag), None)
        if s:
            lines.append("  异质性 Cochran Q p = %s   MR-Egger 截距 p = %s"
                         % (s["Q_pval_heterogeneity"], s["egger_intercept_pval"]))
        lines.append("")

    txt = "\n".join(lines)
    out_txt = os.path.join(TAB, "mr_local_summary.txt")
    with open(out_txt, "w", encoding="utf-8") as fh:
        fh.write(txt + "\n")
    print(txt)
    print("输出：%s" % os.path.relpath(out_csv, ROOT))
    print("      %s" % os.path.relpath(out_txt, ROOT))


if __name__ == "__main__":
    main()
