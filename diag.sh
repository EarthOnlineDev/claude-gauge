#!/bin/bash
# ClaudeGauge 诊断脚本 — 排查数据不一致问题
# 用法: bash diag.sh
# 输出不含任何 token/密钥，可以安全分享
set -euo pipefail
/usr/bin/python3 <<'PY'
import json, subprocess, time, os, urllib.request, urllib.error

SEC="/usr/bin/security"; SERVICE="Claude Code-credentials"

print("=" * 60)
print("ClaudeGauge 诊断报告")
print("=" * 60)

# 1. 读 token（不打印）
try:
    raw = subprocess.run([SEC, "find-generic-password", "-s", SERVICE, "-w"],
                         capture_output=True, text=True, timeout=5).stdout
    blob = json.loads(raw)
    tk = blob["claudeAiOauth"]
    print(f"\n✓ Token 读取成功 (尾4位: ...{tk['accessToken'][-4:]})")
except Exception as e:
    print(f"\n✗ Token 读取失败: {e}"); raise SystemExit(1)

# 2. Bootstrap — 查组织信息
print("\n--- Bootstrap 组织信息 ---")
try:
    req = urllib.request.Request("https://api.anthropic.com/api/claude_cli/bootstrap",
        headers={"Authorization": f"Bearer {tk['accessToken']}", "anthropic-beta": "oauth-2025-04-20"})
    bs = json.load(urllib.request.urlopen(req, timeout=10))
    oa = bs.get("oauth_account", {})
    print(f"  org_uuid: {oa.get('organization_uuid')}")
    print(f"  org_name: {oa.get('organization_name')}")
    print(f"  org_type: {oa.get('organization_type')}")
    print(f"  rate_limit_tier: {oa.get('organization_rate_limit_tier')}")
    print(f"  user_rate_limit_tier: {oa.get('user_rate_limit_tier')}")
    print(f"  seat_tier: {oa.get('seat_tier')}")
    org_uuid = oa.get("organization_uuid")
except Exception as e:
    print(f"  ✗ Bootstrap 失败: {e}"); org_uuid = None

# 3. 本地缓存
print("\n--- 本地缓存 (CG 当前显示的数据) ---")
cache_path = os.path.expanduser("~/.cache/claude-gauge/cache.json")
org_path = os.path.expanduser("~/.cache/claude-gauge/org.json")
state_path = os.path.expanduser("~/.cache/claude-gauge/refresh-state.json")
try:
    c = json.load(open(cache_path))
    d = c.get("data", {})
    age = time.time() - c.get("ts", 0)
    print(f"  缓存时间: {int(age)}秒前")
    for k in ("five_hour", "seven_day", "seven_day_sonnet", "seven_day_opus"):
        v = d.get(k)
        if v: print(f"  {k}: utilization={v.get('utilization')}, resets_at={v.get('resets_at')}")
except Exception as e:
    print(f"  ✗ 缓存读取失败: {e}")

try:
    oj = json.load(open(org_path))
    print(f"  cached org_uuid: {oj.get('uuid')}")
    cached_org = oj.get("uuid")
except Exception:
    print("  cached org_uuid: (无)"); cached_org = None

try:
    sj = json.load(open(state_path))
    print(f"  poll_fail_streak: {sj.get('poll_fail_streak')}")
    print(f"  last_5h: {sj.get('last_5h')}, last_7d: {sj.get('last_7d')}")
except Exception:
    print("  refresh-state: (无)")

# 4. 调 Usage API（带重试）
print("\n--- Usage API 原始返回 ---")
hdrs = {"Authorization": f"Bearer {tk['accessToken']}",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-cli/1.0.119 (external, cli)"}
# 4a. 带 org_uuid
if org_uuid:
    hdrs["x-organization-uuid"] = org_uuid

j = None
for attempt in range(8):
    try:
        req = urllib.request.Request("https://api.anthropic.com/api/oauth/usage", headers=hdrs)
        j = json.load(urllib.request.urlopen(req, timeout=10))
        break
    except urllib.error.HTTPError as e:
        if e.code == 429:
            wait = 45 * (attempt + 1)
            print(f"  429 限流，等 {wait}秒... (第{attempt+1}次)")
            time.sleep(wait)
        else:
            print(f"  HTTP {e.code}"); break
    except Exception as e:
        print(f"  异常: {e}"); break

if j:
    print(f"\n  顶层 keys: {list(j.keys())}")
    print(f"\n  limits 数组 ({len(j.get('limits', []))} 条):")
    for i, e in enumerate(j.get("limits", [])):
        print(f"    [{i}] kind={e.get('kind')}, percent={e.get('percent')}, "
              f"is_active={e.get('is_active')}, group={e.get('group')}")
        if e.get("scope"):
            print(f"        scope={json.dumps(e['scope'])}")

    print(f"\n  legacy 字段:")
    for k in ("five_hour", "seven_day", "seven_day_sonnet", "seven_day_opus",
              "seven_day_oauth_apps", "seven_day_cowork", "seven_day_omelette"):
        v = j.get(k)
        if v: print(f"    {k}: utilization={v.get('utilization')}, resets_at={v.get('resets_at')}")

    # 4b. 不带 org_uuid 再调一次看是否不同
    if org_uuid:
        print(f"\n--- 不带 org_uuid 的 Usage API ---")
        hdrs2 = {k: v for k, v in hdrs.items() if k != "x-organization-uuid"}
        for attempt in range(4):
            try:
                req2 = urllib.request.Request("https://api.anthropic.com/api/oauth/usage", headers=hdrs2)
                j2 = json.load(urllib.request.urlopen(req2, timeout=10))
                for e in j2.get("limits", []):
                    print(f"    kind={e.get('kind')}, percent={e.get('percent')}, is_active={e.get('is_active')}")
                fh2 = j2.get("five_hour", {}).get("utilization")
                sd2 = j2.get("seven_day", {}).get("utilization")
                print(f"    legacy: five_hour={fh2}, seven_day={sd2}")
                if fh2 != j.get("five_hour", {}).get("utilization") or sd2 != j.get("seven_day", {}).get("utilization"):
                    print("    ⚠️ 数据不同！去掉 org_uuid 后返回了不同的用量！")
                else:
                    print("    ✓ 数据一致")
                break
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    print(f"    429 限流，等 {60*(attempt+1)}秒...")
                    time.sleep(60 * (attempt + 1))
                else:
                    print(f"    HTTP {e.code}"); break
            except Exception as e:
                print(f"    异常: {e}"); break
else:
    print("  ✗ API 调用全部失败")

print("\n" + "=" * 60)
print("请把以上输出发给开发者排查。输出不含任何 token 或密钥。")
print("=" * 60)
PY
