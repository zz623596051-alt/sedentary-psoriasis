import csv, os
def show(f, pat):
    p = os.path.join("output/tables", f)
    if not os.path.exists(p): print(f"  <缺 {f}>"); return
    with open(p, encoding="utf-8-sig") as fh:
        r = list(csv.DictReader(fh))
    if not r: print(f"  <{f} 为空>"); return
    cols = r[0].keys(); print("  cols:", list(cols))
    for row in r:
        t = row.get("term","")
        if pat in t:
            orv = row.get("OR",""); lci=row.get("lci",""); uci=row.get("uci",""); pv=row.get("p","")
            print(f"  {t:<32} OR={float(orv):.3f} ({float(lci):.3f}-{float(uci):.3f})  p={float(pv):.4f}")
print("=== 模型1 PA 分组 ==="); show("model_PA_group.csv","pa_group")
print("=== 模型2 久坐四分位 ==="); show("model_sedentary_quartile.csv","sed_q")
print("=== 模型3 连续 PA ==="); show("model_PA_continuous.csv","met_1000")
print("=== 中介（未加权，mediation 包）===")
p="output/tables/mediation_uw.csv"
if os.path.exists(p):
    with open(p,encoding="utf-8-sig") as fh: print("  ", fh.read().strip()[:400] or "<空>")
print("=== 中介（加权差异法）===")
p="output/tables/mediation_survey_diff.csv"
if os.path.exists(p):
    with open(p,encoding="utf-8-sig") as fh: print("  ", fh.read().strip()[:400] or "<空>")
print("=== 亚组交互 ===")
p="output/tables/subgroup_interactions.csv"
if os.path.exists(p):
    with open(p,encoding="utf-8-sig") as fh: print("  ", fh.read().strip()[:400] or "<空>")
