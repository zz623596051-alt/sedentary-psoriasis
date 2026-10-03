"""批量核对 config.R 中的全部 GWAS 数据集 ID（OpenGWAS）。
运行：python tools/check_gwas_ids.py
产出：output/gwas_id_check.csv 与终端报告
"""
import base64
import csv
import json
import os
import re
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_PATH = os.path.join(ROOT, ".Renviron")
CONFIG = os.path.join(ROOT, "R", "config.R")
OUT_CSV = os.path.join(ROOT, "output", "gwas_id_check.csv")


def load_token():
    with open(ENV_PATH, encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith("OPENGWAS_JWT="):
                return line.strip().split("=", 1)[1].strip()
    sys.exit("未找到 OPENGWAS_JWT")


def parse_config_ids():
    """从 config.R 的 MR <- list(...) 中提取 键 = "ID" 对（行内注释一并取）"""
    with open(CONFIG, encoding="utf-8") as f:
        txt = f.read()
    m = re.search(r"MR\s*<-\s*list\((.*?)\n\)", txt, re.S)
    if not m:
        sys.exit("无法解析 config.R 中的 MR 列表")
    body = m.group(1)
    # 只取 键 = "值" 形式（值为字符串的才是数据集 ID）
    pairs = re.findall(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"\s*,?\s*(?:#\s*(.*))?$',
                       body, re.M)
    return pairs


def main():
    tok = load_token()
    pairs = parse_config_ids()
    if not pairs:
        sys.exit("未解析到任何 ID")

    ids = [p[1] for p in pairs]
    label = {p[1]: (p[2] or "") for p in pairs}
    print(f"从 config.R 解析到 {len(ids)} 个 ID\n")

    req = urllib.request.Request(
        "https://api.opengwas.io/api/gwasinfo",
        data=json.dumps({"id": ids}).encode(),
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"},
        method="POST",
    )

    found = {}
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.loads(r.read().decode("utf-8", "replace"))
            if isinstance(data, list):
                found = {d["id"]: d for d in data}
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode('utf-8','replace')[:300]}")
        return
    except Exception as e:
        print(f"网络失败: {type(e).__name__}: {e}")
        return

    rows = []
    print(f"{'键':<16} {'ID':<32} {'状态':<6} 真实表型 / 备注")
    print("-" * 110)
    for key, gid, note in pairs:
        d = found.get(gid)
        if d:
            trait = d.get("trait", "")
            n = d.get("sample_size") or d.get("ncase") or ""
            pop = d.get("population", "")
            rows.append(dict(key=key, id=gid, status="OK", trait=trait,
                             sample_size=n, population=pop,
                             config_note=note.strip()))
            print(f"{key:<16} {gid:<32} {'OK':<6} {trait}")
            print(f"{'':<16} {'':<32} {'':<6} n={n} pop={pop}")
        else:
            rows.append(dict(key=key, id=gid, status="NOT_FOUND", trait="",
                             sample_size="", population="",
                             config_note=note.strip()))
            print(f"{key:<16} {gid:<32} {'缺失':<6} ⚠️ OpenGWAS 中不存在该 ID")

    os.makedirs(os.path.dirname(OUT_CSV), exist_ok=True)
    with open(OUT_CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["key", "id", "status", "trait",
                                          "sample_size", "population", "config_note"])
        w.writeheader()
        w.writerows(rows)

    ok = sum(1 for r in rows if r["status"] == "OK")
    print(f"\n可用 {ok} / {len(rows)}；明细见 output/gwas_id_check.csv")


if __name__ == "__main__":
    main()
