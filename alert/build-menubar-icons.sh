#!/usr/bin/env bash
# 重新生成菜单栏图标的 base64（构建期一次性；产物内嵌在 plugin 的 ICON_* 常量里）。
#
# 形状来源 = 落地页 **GaugeMark**（设计蓝图的半圆表盘：半圆刻度 + 指针 + 圆心），
# 与 designonline-ui 换肤后的落地页/HeroLive 表盘**逐路径一致**，确保菜单栏工具与网页 demo 同形。
#   path 半圆刻度 = M3.6 16.4a8.4 8.4 0 0 1 16.8 0 ; 指针 = M12 16.4 16.6 10.6 ; 圆心 = (12,16.4) r1.7
# 用 24×24 方形视框（与落地页 GaugeMark 的 viewBox 0 0 24 24 同框），方形渲染→与 demo 取景一致。
# 描边 2.2（与落地页 GaugeMark 同值；在 18px 显示下有效 ~1.65px，与菜单栏 SF 符号和谐）。
#
# 五态各渲一张 @2x PNG：
#   ICON_OK    单色蒙版（templateImage 用 alpha，自动随真实菜单栏深浅变黑/白；RGB 被丢弃）
#   ICON_WARN  橙 #C2902E   ICON_CRIT 红 #C0492B   ICON_STALE 灰 #9CA0A2   （= DesignOnline token 值）
#   ICON_RAINBOW 五段光谱渐变弧+针+心（= 落地页 GaugeMark rainbow 本体，身份用）
#
# 依赖：仅构建期需要 `rsvg-convert`（`brew install librsvg`）。插件【运行期】只读内嵌 base64，零依赖。
# 用法：bash alert/build-menubar-icons.sh
#        → 把末尾打印的 5 个 base64 粘回 plugin/claude-gauge.15s.sh 的 ICON_OK/WARN/CRIT/STALE/RAINBOW。
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
command -v rsvg-convert >/dev/null || { echo "需要 rsvg-convert：brew install librsvg" >&2; exit 1; }

python3 - "$TMP" <<'PY'
import sys
tmp = sys.argv[1]
SW, HUB_R, VB = "2.2", "1.7", "0 0 24 24"
ARC    = "M3.6 16.4a8.4 8.4 0 0 1 16.8 0"   # 半圆刻度（= 落地页 GaugeMark）
NEEDLE = "M12 16.4 16.6 10.6"               # 指针
SPEC   = ["#8A43E6","#4FA8F0","#1FA45D","#F4811E","#E8482A"]  # 五段神经光谱（hex 不改）

def svg(defs, stroke):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{VB}">{defs}'
            f'<path d="{ARC}" fill="none" stroke="{stroke}" stroke-width="{SW}" stroke-linecap="round"/>'
            f'<path d="{NEEDLE}" fill="none" stroke="{stroke}" stroke-width="{SW}" stroke-linecap="round"/>'
            f'<circle cx="12" cy="16.4" r="{HUB_R}" fill="{stroke}"/></svg>')

def solid(c): return svg("", c)

def rainbow():
    stops = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in
                    zip(("0","0.28","0.55","0.78","1"), SPEC))
    defs = (f'<defs><linearGradient id="g" x1="2" y1="0" x2="22" y2="0" '
            f'gradientUnits="userSpaceOnUse">{stops}</linearGradient></defs>')
    return svg(defs, "url(#g)")

open(f"{tmp}/ic_ok.svg","w").write(solid("#1B1B1B"))     # 模板态：alpha 蒙版（色被丢弃）
open(f"{tmp}/ic_warn.svg","w").write(solid("#C2902E"))   # --color-warning
open(f"{tmp}/ic_crit.svg","w").write(solid("#C0492B"))   # --color-danger
open(f"{tmp}/ic_stale.svg","w").write(solid("#9CA0A2"))  # --color-text-subtle
open(f"{tmp}/ic_rain.svg","w").write(rainbow())          # 五段光谱（身份）
PY

for n in ok warn crit stale rain; do
  rsvg-convert -w 36 -h 36 "$TMP/ic_$n.svg" -o "$TMP/ic_$n.png"   # @2x（显示 18×18 逻辑点，方形与 demo 同框）
done

echo "=== 把下面 5 个常量粘回 plugin/claude-gauge.15s.sh（ICON_SZ 用 width=18 height=18）==="
for pair in OK:ok WARN:warn CRIT:crit STALE:stale RAINBOW:rain; do
  name="${pair%%:*}"; file="${pair##*:}"
  printf 'ICON_%s="%s"\n' "$name" "$(base64 < "$TMP/ic_$file.png" | tr -d '\n')"
done
