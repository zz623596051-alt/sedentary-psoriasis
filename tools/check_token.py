"""校验 OpenGWAS token：解码有效期 + 实测 API 认证。
不打印 token 内容与邮箱，只输出结构与认证结果。
运行：python tools/check_token.py
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_PATH = os.path.join(ROOT, ".Renviron")


def load_token(path):
    if not os.path.exists(path):
        sys.exit(f"找不到 {path}")
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("OPENGWAS_JWT="):
                return line.split("=", 1)[1].strip()
    sys.exit("未找到 OPENGWAS_JWT")


def b64url_decode(seg):
    seg += "=" * (-len(seg) % 4)
    return base64.urlsafe_b64decode(seg)


def main():
    tok = load_token(ENV_PATH)
    print(f"token 长度: {len(tok)}")
    parts = tok.split(".")
    print(f"JWT 段数: {len(parts)}  (正常应为 3)")
    if len(parts) != 3:
        print("⚠️ 格式异常，token 可能复制不完整")
        return

    try:
        header = json.loads(b64url_decode(parts[0]))
        payload = json.loads(b64url_decode(parts[1]))
    except Exception as e:
        print(f"⚠️ 无法解码 JWT: {e}")
        return

    print(f"算法: {header.get('alg')}, 类型: {header.get('typ')}")

    def show(key):
        v = payload.get(key)
        if isinstance(v, (int, float)):
            dt = datetime.fromtimestamp(v, tz=timezone.utc)
            print(f"  {key}: {dt:%Y-%m-%d %H:%M UTC}")
            return dt
        return None

    print("载荷时间字段:")
    iat = show("iat")
    exp = show("exp")
    sub = payload.get("sub", "")
    if sub:
        print(f"  账号: {sub[:2]}{'*' * max(len(sub) - 6, 0)}{sub[-4:]}")
    print(f"  issuer: {payload.get('iss')}")

    now = datetime.now(tz=timezone.utc)
    if exp:
        left = exp - now
        if left.total_seconds() < 0:
            print(f"\n❌ token 已过期 {-left.days} 天，需重新申请")
            return
        print(f"\n✅ token 有效，剩余 {left.days} 天")

    # ---- 实测认证 ----
    print("\n=== 实测 API 认证 (POST /api/gwasinfo) ===")
    req = urllib.request.Request(
        "https://api.opengwas.io/api/gwasinfo",
        data=json.dumps({"id": ["ukb-b-16998"]}).encode(),
        headers={
            "Authorization": f"Bearer {tok}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode("utf-8", "replace")
            print(f"HTTP {r.status}")
            try:
                j = json.loads(body)
                if isinstance(j, list) and j:
                    d = j[0]
                    print("返回数据集信息:")
                    for k in ("id", "trait", "sample_size", "population", "nsnp"):
                        if k in d:
                            print(f"  {k}: {d[k]}")
                    print("\n✅ token 认证成功，且 ukb-b-16998 可用")
                else:
                    print(f"返回: {body[:400]}")
            except json.JSONDecodeError:
                print(f"返回(非JSON): {body[:400]}")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:400]
        print(f"HTTP {e.code}\n返回: {body}")
        if e.code in (401, 403):
            print("\n❌ 认证失败：token 无效或未激活")
            print("→ 请回 https://api.opengwas.io/ 重新复制完整 token")
        elif e.code == 429:
            print("\n⚠️ 触发限流，稍后重试")
    except Exception as e:
        print(f"⚠️ 网络请求失败: {type(e).__name__}: {e}")
        print("→ 可能是沙箱网络限制，可在本机 Git Bash 手动执行：")
        print('  curl -s -X POST https://api.opengwas.io/api/gwasinfo \\')
        print('    -H "Authorization: Bearer $OPENGWAS_JWT" \\')
        print('    -H "Content-Type: application/json" \\')
        print('    -d \'{"id":["ukb-b-16998"]}\'')


if __name__ == "__main__":
    main()
