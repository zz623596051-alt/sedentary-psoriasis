import csv, os, io, sys
sys.stdout.reconfigure(encoding='utf-8')
T="output/tables"
def rd(f):
    p=os.path.join(T,f)
    if not os.path.exists(p): return None
    with open(p, encoding="utf-8-sig") as fh: return list(csv.DictReader(fh))

def fmt(x, d=4):
    try:
        v=float(x)
        if v==0: return "0"
        if abs(v)<1e-3 or abs(v)>=1e4: return f"{v:.3e}"
        return f"{v:.{d}f}"
    except: return str(x)

print("="*70)
print("A) 主模型：PA 分组")
for r in rd("model_PA_group.csv"):
    print(f"  {r['term']:<28} OR={fmt(r['OR'],3)} ({fmt(r['lci'],3)}-{fmt(r['uci'],3)})  p={fmt(r['p'])}")

print("="*70)
print("B) 主模型：久坐四分位")
for r in rd("model_sedentary_quartile.csv"):
    print(f"  {r['term']:<28} OR={fmt(r['OR'],3)} ({fmt(r['lci'],3)}-{fmt(r['uci'],3)})  p={fmt(r['p'])}")

print("="*70)
print("C) 主模型：PA 连续 / 久坐连续")
for r in rd("model_PA_continuous.csv"):
    print(f"  {r['term']:<28} OR={fmt(r['OR'],3)} ({fmt(r['lci'],3)}-{fmt(r['uci'],3)})  p={fmt(r['p'])}")

print("="*70)
print("D) 加速度计臂（探索性）")
for r in rd("model_accelerometer.csv"):
    print(f"  {r['term']:<28} OR={fmt(r['OR'],3)} ({fmt(r['lci'],3)}-{fmt(r['uci'],3)})  p={fmt(r['p'])}")

print("="*70)
print("E) 敏感性分析")
for f,lab in [("sens_severity.csv","中重度病例"),("sens_confirmed_cases.csv","用药确认病例"),("sens_psoriatic_arthritis.csv","银屑病关节炎")]:
    rs=rd(f) or []
    for r in rs:
        if r['term'] in ('met_total','met_1000'):
            print(f"  {lab:<14} {r['term']:<12} OR={fmt(r['OR'],6)} ({fmt(r['lci'],6)}-{fmt(r['uci'],6)})  p={fmt(r['p'])}")

print("="*70)
print("F) 中介")
for r in rd("mediation_bootstrap.csv") or []:
    print("  boot:", dict(r))
for r in rd("mediation_survey_diff.csv") or []:
    print("  diff:", dict(r))

print("="*70)
print("G) 亚组交互")
for r in rd("subgroup_interactions.csv") or []:
    print(f"  {r['subgroup']:<10} {r['term']:<24} p_int={fmt(r['p_interaction'])}")

print("="*70)
print("H) Table 1 基线（长格式解析）")
rows = rd("table1_baseline_by_psoriasis.csv") or []
if rows:
    print("  columns:", list(rows[0].keys()))
    # 结构：每 variable 两行（psoriasis 0/1）
    cur=None
    for r in rows:
        v=r.get('variable','')
        if v!=cur:
            print(f"  --- {v} ---"); cur=v
        print("    ", {k:fmt(x,3) for k,x in r.items() if x not in ('','NA',None)})
