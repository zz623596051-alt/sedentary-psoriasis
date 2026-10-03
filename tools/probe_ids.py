"""批量探测任意 GWAS ID 是否存在于 OpenGWAS。
用法：python tools/probe_ids.py <id1> <id2> ...
"""
import json
import os
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_token():
    with open(os.path.join(ROOT, ".Renviron"), encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith("OPENGWAS_JWT="):
                return line.strip().split("=", 1)[1].strip()
    sys.exit("未找到 OPENGWAS_JWT")


def main():
    ids = sys.argv[1:]
    if not ids:
        sys.exit("请传入至少一个 ID")
    tok = load_token()
    req = urllib.request.Request(
        "https://api.opengwas.io/api/gwasinfo",
        data=json.dumps({"id": ids}).encode(),
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode('utf-8','replace')[:300]}")
        return
    except Exception as e:
        print(f"网络失败: {type(e).__name__}: {e}")
        return

    found = {d["id"]: d for d in data} if isinstance(data, list) else {}
    for i in ids:
        d = found.get(i)
        if d:
            print(f"✅ {i}")
            print(f"   trait      : {d.get('trait')}")
            print(f"   sample_size: {d.get('sample_size')}  "
                  f"ncase={d.get('ncase')} ncontrol={d.get('ncontrol')}")
            print(f"   population : {d.get('population')}   nsnp={d.get('nsnp')}")
        else:
            print(f"❌ {i}  —— OpenGWAS 中不存在")


if __name__ == "__main__":
    main()
