#!/usr/bin/python3
# ClaudeGauge 完成提醒层（可选/opt-in）——「有新发现」彩虹态的事件入口。
# 被 Claude Code 的 Stop / Notification hook 调用，以及被菜单栏图标的左键点击调用。
#
# 隐私红线：本脚本【绝不读 stdin】。Claude Code 会把含 transcript_path 的 JSON
# 灌到 stdin，但我们整条忽略——事件类型由 hook 的 matcher 在 CC 层就分好了，
# 我们只记「时间戳 + 事件名 + 触发那刻的前台 App」。从不碰对话/代码/会话路径。
#
# 形态：极小、纯副作用、任何异常都安全降级、永远 exit 0（不阻塞 CC，也不破坏任何东西）。
import sys, os, json, time, tempfile, subprocess

CACHE = os.path.expanduser("~/.cache/claude-gauge")
ATTN  = os.path.join(CACHE, "attention.json")
ACK   = os.path.join(CACHE, "ack.json")
CLAUDE_BUNDLE = "com.anthropic.claudefordesktop"
PLUGIN_NAME   = "claude-gauge.15s.sh"


def awrite(path, obj):
    """原子写：先写临时文件再 os.replace，防菜单栏读到半截。失败静默降级。"""
    try:
        os.makedirs(CACHE, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=CACHE)
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, path)
    except Exception:
        pass


def front_bundle():
    """触发那刻的前台 App bundle id。仅用 lsappinfo（不弹辅助功能/自动化授权框）。
    取不到/解析异常一律 'unknown'——后续 arming 会照亮（宁可多提醒，不漏）。"""
    try:
        asn = subprocess.run(["/usr/bin/lsappinfo", "front"],
                             capture_output=True, text=True, timeout=2).stdout.strip()
        if not asn:
            return "unknown"
        out = subprocess.run(["/usr/bin/lsappinfo", "info", "-only", "bundleID", asn],
                             capture_output=True, text=True, timeout=2).stdout
        # 形如  "CFBundleIdentifier"="com.anthropic.claudefordesktop"  ；NULL 进程则  ...=NULL
        # （按首个 '=' 切分取值，兼容 CFBundleIdentifier / LSBundleID 两种键名）
        if "=" in out:
            val = out.split("=", 1)[1].strip().strip('"').strip()
            if val and val != "NULL" and "." in val:
                return val
        return "unknown"
    except Exception:
        return "unknown"


def ping_refresh():
    """让菜单栏即时重画（-g 不抢焦点）。失败静默。"""
    try:
        subprocess.run(["/usr/bin/open", "-g",
                        "swiftbar://refreshplugin?name=" + PLUGIN_NAME], timeout=3)
    except Exception:
        pass


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "event":
        ev = sys.argv[2] if len(sys.argv) > 2 else "stop"   # stop | permission
        # 注意：不读 sys.stdin。点亮只依赖 (事件名 + 当前前台)。
        awrite(ATTN, {"ts": time.time(), "event": ev, "front": front_bundle()})
        ping_refresh()
    elif mode == "open":
        # 左键点击：拉起 Claude 桌面 App，并确认（写 ack）让彩虹熄灭。
        try:
            subprocess.run(["/usr/bin/open", "-b", CLAUDE_BUNDLE], timeout=5)
        except Exception:
            pass
        awrite(ACK, {"ts": time.time()})
        ping_refresh()
    # 未知 mode：no-op


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
