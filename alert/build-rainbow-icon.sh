#!/usr/bin/env bash
# 重新生成菜单栏「有新发现」彩虹 gauge 的 base64（构建期一次性；产物已内嵌在 plugin 的 RAINBOW_PNG）。
#
# 管线：clang 编 sfgen.m → 渲染【真】SF 符号 gauge.with.needle 的黑色蒙版(2x@144dpi) →
#       PIL 清雾(alpha<18→0，去 macOS 淡框残留) + 按同一蒙版横向填彩虹 → 144dpi PNG → base64。
# 普通态用 sfimage 渲染同一符号，故两态形状一致；彩虹态用此 PNG 配 `image= width=22 height=21`。
#
# 依赖：仅构建期需要 macOS 自带 clang(CommandLineTools) + Pillow。插件【运行期】只用内嵌 base64，零依赖。
# 用法：bash alert/build-rainbow-icon.sh   → 末尾打印的 base64 粘进 plugin/claude-gauge.15s.sh 的 RAINBOW_PNG。
set -euo pipefail
cd "$(dirname "$0")"

clang -framework Cocoa -framework ImageIO -o /tmp/cg-sfgen sfgen.m
/tmp/cg-sfgen gauge.with.needle 24 23 /tmp/cg-mask.png 000000   # 逻辑 24x23 → 48x46px@144dpi 黑蒙版

/usr/bin/python3 - <<'PY'
from PIL import Image
import base64
STOPS=[(0xe0,0x48,0x3d),(0xe0,0x8a,0x2b),(0xe8,0xc9,0x4a),(0x1d,0x9e,0x75),(0x37,0x8a,0xdd),(0x7f,0x77,0xdd)]
def grad(t):
    x=t*(len(STOPS)-1); i=min(int(x),len(STOPS)-2); f=x-i; a,b=STOPS[i],STOPS[i+1]
    return tuple(round(a[j]+(b[j]-a[j])*f) for j in range(3))
m=Image.open("/tmp/cg-mask.png").convert("RGBA"); px=m.load(); W,H=m.size
for x in range(W):
    for y in range(H):
        if px[x,y][3]<18: px[x,y]=(0,0,0,0)          # 清雾：去掉符号边缘极淡 alpha 造成的方框
a=m.split()[3]; bb=a.getbbox(); x0,x1=bb[0],bb[2]
rb=Image.new("RGBA",(W,H),(0,0,0,0)); rp=rb.load()
for x in range(W):
    t=min(1,max(0,(x-x0)/max(1,(x1-1-x0)))); c=grad(t)  # 按字形横向铺彩虹（红左→紫右）
    for y in range(H):
        v=a.getpixel((x,y))
        if v>0: rp[x,y]=(c[0],c[1],c[2],v)
rb.save("/tmp/cg-rainbow.png", dpi=(144,144))
print("\n=== RAINBOW_PNG base64（粘进 plugin/claude-gauge.15s.sh）===")
print(base64.b64encode(open("/tmp/cg-rainbow.png","rb").read()).decode())
PY
