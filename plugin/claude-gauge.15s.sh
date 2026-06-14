#!/bin/bash
# Claude Code 用量 — SwiftBar 插件。每 15 秒读 cache.json/live.json 渲染。
# 数据由后台刷新器(LaunchAgent)写入；本插件只渲染+兜底。不碰对话文件。
# 配色：够用=默认(黑/自适应)，需关注=橙，紧急=红，无绿色。进度条为主，倒计时为辅。
# SwiftBar 元数据：隐藏宿主自动追加的页脚项（上次更新/命令行运行/停用插件/关于/SwiftBar 子菜单），
# 让下拉干净收尾在「立即刷新」，与落地页样图一致。这些只是宿主噪音，不影响任何渲染逻辑。
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
/usr/bin/python3 <<'PY'
import os, json, urllib.request, datetime, time, sys, subprocess, tempfile
CACHE=os.path.expanduser("~/.cache/claude-gauge/cache.json")
LIVE =os.path.expanduser("~/.cache/claude-gauge/live.json")
ATTN =os.path.expanduser("~/.cache/claude-gauge/attention.json")   # 完成提醒层：未读事件（装了可选层才有）
ACK  =os.path.expanduser("~/.cache/claude-gauge/ack.json")          # 完成提醒层：已读标记
os.makedirs(os.path.dirname(CACHE), exist_ok=True)
LOGO="gauge.with.needle"; STALE_SEC=900
CLAUDE_BUNDLE="com.anthropic.claudefordesktop"                      # 点击拉起 / 自动熄灭判定的目标 App
ALERT=os.path.expanduser("~/.claude/claude-gauge-alert.py")         # 左键点击动作脚本
# 有新消息态图标：把系统 SF 符号 gauge.with.needle 本体渲成彩虹的全彩 PNG（由 alert/sfgen.m 生成）。普通态用 sfimage 渲染同一符号，故两态形状 100% 一致。
# 为何不用 sfconfig：其 Palette 多色在实测 SwiftBar 上糊成单橙色，故彩虹用 image= 全彩位图。
RAINBOW_PNG="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"
WARN_TH,CRIT_TH=25.0,10.0
COL_WARN,COL_CRIT,COL_STALE="#e08a2b","#e0483d","#9a9a9a"
def _is_dark():
    try: return subprocess.run(["defaults","read","-g","AppleInterfaceStyle"],capture_output=True,text=True,timeout=2).stdout.strip()=="Dark"
    except Exception: return False
NORMAL = "#ededef" if _is_dark() else "#1d1d1f"
MUTE   = "#9a9aa0" if _is_dark() else "#8a8a8a"
MAXW,CD_CAP=11,"9h+"

def remain(b): return None if not b or b.get("utilization") is None else 100-float(b["utilization"])
def bar(used):
    f=max(0,min(10,round(used/10.0))); return "█"*f+"░"*(10-f)
def _secs_until(v):
    if v is None or v=="": return None
    try:
        if isinstance(v,(int,float)) or (isinstance(v,str) and v.replace('.','',1).isdigit()): return float(v)-time.time()
        s=str(v).strip().replace("Z","+00:00"); t=datetime.datetime.fromisoformat(s)
        if t.tzinfo is None: t=t.replace(tzinfo=datetime.timezone.utc)
        return (t-datetime.datetime.now(datetime.timezone.utc)).total_seconds()
    except Exception: return None
def _cd5(v):
    s=_secs_until(v)
    if s is None: return ""
    if s<=0: return "0m"
    if s>=36000: return CD_CAP
    m=int(round(s/60.0))
    if m>=60: h,mm=divmod(m,60); return f"{h}h{mm:02d}m"
    return f"{m}m"
def _cd7(v):
    s=_secs_until(v)
    if s is None: return ""
    if s<=0: return "0m"
    tm=int(round(s/60.0)); days,rem=divmod(tm,1440); hrs=rem//60
    if days>=1: return f"{days}d{hrs}h" if (days<3 and hrs>0) else f"{days}d"
    if rem>=60: return f"{rem//60}h"
    return f"{rem}m"
def _lvl(p):
    if p is None: return None
    if p<=CRIT_TH: return 2
    if p<=WARN_TH: return 1
    return 0
def _w(s): return sum(2 if ord(c)>0x2E80 else 1 for c in s)
def _used(rem): return None if rem is None else min(100,max(0,int(round(100-rem))))
def scol(rem):
    l=_lvl(rem)
    if l==2: return f" color={COL_CRIT}"
    if l==1: return f" color={COL_WARN}"
    return f" color={NORMAL}"

# ---- 完成提醒层（可选）：未装时 attention.json 不存在 → _armed 恒 False、渲染与今天逐字节一致 ----
def _loadj(p):
    try: return json.load(open(p))
    except Exception: return None
def _front_bundle():
    """当前前台 App 的 bundle id；仅用 lsappinfo（不弹辅助功能/自动化授权框）。取不到→None。"""
    try:
        asn=subprocess.run(["/usr/bin/lsappinfo","front"],capture_output=True,text=True,timeout=2).stdout.strip()
        if not asn: return None
        out=subprocess.run(["/usr/bin/lsappinfo","info","-only","bundleID",asn],capture_output=True,text=True,timeout=2).stdout
        if "=" in out:
            v=out.split("=",1)[1].strip().strip('"').strip()   # 形如 "CFBundleIdentifier"="com.…"
            if v and v!="NULL" and "." in v: return v
        return None
    except Exception: return None
def _awrite_ack(ts):
    try:
        dd=os.path.dirname(ACK); os.makedirs(dd,exist_ok=True)
        fd,tmp=tempfile.mkstemp(dir=dd)
        with os.fdopen(fd,"w") as f: json.dump({"ts":ts},f)
        os.replace(tmp,ACK)
    except Exception: pass
def _ts(x):
    try: return float(x or 0)
    except Exception: return 0.0
def _armed():
    """有未读完成/需关注事件，且事件发生时你不在 Claude 前台 → 点亮彩虹。"""
    att=_loadj(ATTN)
    if not att or "ts" not in att: return False
    if att.get("front")==CLAUDE_BUNDLE: return False
    return _ts(att.get("ts")) > _ts((_loadj(ACK) or {}).get("ts"))

def title_line(fh,wk,d,stale=False,armed=False):
    d=d if isinstance(d,dict) else {}
    if fh is None and wk is None: return f"额度⚠ | color={COL_WARN}"
    u5,u7=_used(fh),_used(wk); fl,wl=_lvl(fh),_lvl(wk)
    fr=(d.get("five_hour") or {}).get("resets_at"); wr=(d.get("seven_day") or {}).get("resets_at")
    ex=d.get("extra_usage") or {}
    spending=bool(ex.get("is_enabled")) and float(ex.get("used_credits") or 0)>0
    def s5(a): return f"{u5}% {_cd5(fr)}".rstrip() if a else f"{u5}%"
    def s7(a): return f"W{u7}% {_cd7(wr)}".rstrip() if a else f"W{u7}%"
    if fl in (0,None) and wl in (0,None):
        text,col=(f"W{u7}%" if fl is None and wl is not None else f"{u5}%"),None
    elif wl in (0,None): text,col=s5(True),(COL_CRIT if fl==2 else COL_WARN)
    elif fl in (0,None): text,col=s7(True),(COL_CRIT if wl==2 else COL_WARN)
    else:
        if wl==2 or wl>fl: text,col=s7(True),(COL_CRIT if wl==2 else COL_WARN)
        else:              text,col=s5(True),(COL_CRIT if fl==2 else COL_WARN)
    if spending and col is None and _w(f"{text}+$")<=MAXW: text=f"{text}+$"
    if armed:
        act=f"image={RAINBOW_PNG} width=22 height=21 bash=/usr/bin/python3 param0={ALERT} param1=open terminal=false"
        if stale:       return f"{text}~ | color={COL_STALE} {act}"
        if col is None: return f"{text} | {act}"                   # 够用态：不写 color，用菜单栏自适应色（深色壁纸下自动白字，别强制成黑）
        return f"{text} | color={col} {act}"                       # 数字额度色（橙/红，本就该恒定显色），图标彩虹
    if stale: return f"{text}~ | color={COL_STALE} sfimage={LOGO}"
    if col is None: return f"{text} | sfimage={LOGO}"
    return f"{text} | color={col} sfimage={LOGO}"

def section(label, icon, u, cd_str, col):
    print(f"{label} | sfimage={icon} size=12 color={NORMAL}")                       # 标签：默认色(清晰)
    print(f"已用 {u}%　·　还剩 {100-u}% | size=14{col}")              # 数字：默认/橙/红
    print(f"{bar(u)} | font=Menlo size=15{col}")                     # 进度条：放大(主信息)
    if cd_str: print(f"{cd_str} 后重置 | size=11 color={MUTE}")      # 倒计时：小灰(辅信息)

def render(d,ts):
    age=time.time()-ts; stale=age>STALE_SEC
    fh,wk=remain(d.get("five_hour")),remain(d.get("seven_day"))
    son=remain(d.get("seven_day_sonnet")); opus=remain(d.get("seven_day_opus"))
    # 完成提醒层：仅当装了该层(有 attention.json)才做前台检测；未装则零开销、输出同今天。
    att=_loadj(ATTN)
    if att and _front_bundle()==CLAUDE_BUNDLE:          # 正看着 Claude → 标记已读（回到 ≤15s 自动熄灭）
        if _ts(att.get("ts")) > _ts((_loadj(ACK) or {}).get("ts")): _awrite_ack(time.time())
    print(title_line(fh,wk,d,stale,_armed() if att else False))
    print("---")
    print(f"Claude Code 用量 | sfimage={LOGO} color={NORMAL}")                      # 标题：默认色(清晰)
    if stale:
        print("---")
        print(f"⚠️ 数据已 {int(age//60)} 分钟未更新 | color={COL_WARN}")
        print(f"闲置/限流；用一下 Claude Code 即刷新 | size=11 color={MUTE}")
    print("---")
    if fh is not None: section("当前 5 小时 · session","clock",_used(fh),_cd5((d.get('five_hour') or {}).get('resets_at')),scol(fh))
    if wk is not None: section("本周 · 7 天","calendar",_used(wk),_cd7((d.get('seven_day') or {}).get('resets_at')),scol(wk))
    extras=[]
    if son is not None: extras.append(f"Sonnet {_used(son)}%")
    if opus is not None: extras.append(f"Opus {_used(opus)}%")
    if extras: print("---"); print("按模型（本周）　"+" · ".join(extras)+f" | size=11 color={MUTE}")
    print("---")
    upd=datetime.datetime.fromtimestamp(ts).strftime("%H:%M")
    print((f"更新于 {upd}（{int(age//60)}分钟前）" if age>=60 else f"更新于 {upd}（刚刚）")+f" | size=11 color={MUTE}")
    home=os.path.expanduser("~"); print(f"立即刷新（强制拉最新）| shell={home}/.claude/claude-gauge-refresh.sh | param0=force | terminal=false | refresh=true | sfimage=arrow.clockwise")

def load(p):
    try:
        c=json.load(open(p)); return c if ("ts" in c and "data" in c) else None
    except Exception: return None
def read_token():
    try:
        raw=subprocess.run(["/usr/bin/security","find-generic-password","-s","Claude Code-credentials","-w"],capture_output=True,text=True,timeout=5).stdout
        if not raw:
            fp=os.path.expanduser("~/.claude/.credentials.json")
            if os.path.exists(fp): raw=open(fp).read()
        return json.loads(raw)["claudeAiOauth"]
    except Exception: return None

best=None
for c in (load(LIVE),load(CACHE)):
    if c and (best is None or c["ts"]>best["ts"]): best=c
if (best is None) or (time.time()-best["ts"]>150):   # 兜底：后台失效才自己拉
    tk=read_token()
    if tk and ((tk.get("expiresAt") is None) or (tk["expiresAt"]/1000>time.time()+30)):
        try:
            req=urllib.request.Request("https://api.anthropic.com/api/oauth/usage",headers={"Authorization":f"Bearer {tk['accessToken']}","anthropic-beta":"oauth-2025-04-20"})
            with urllib.request.urlopen(req,timeout=8) as r: d=json.load(r)
            obj={"ts":time.time(),"data":d}; json.dump(obj,open(CACHE,"w")); best=obj
        except Exception: pass
if best is None:
    print(f"额度⚠ | color={COL_WARN}"); print("---"); print("新开一个 Claude Code 会话发条消息即恢复实时 | size=12")
    print("---"); print("立即刷新 | refresh=true")
else:
    render(best["data"],best["ts"])
PY
