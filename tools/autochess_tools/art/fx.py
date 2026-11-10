"""战斗特效的贴图：飘字的饰板，渲染成 PNG 写到 assets/ui/fx/。规格见 docs/plans/effects-pacing.md 第 3 节。

飘字按缩放 1 排版，高 64，饰板在 y 12–52 之间。贴图四周各留 16 给纹样和外发光（外发光直接画进贴图）：
- 基础技能：cap_<技能>.png 是左端饰（48 宽，覆盖 x -16–48、y -16–80），右端镜像（狂暴旋转 180°）；
  mid_<技能>.png 是中段（横向拉伸）；振奋另有 crest.png（顶部光芒），腐蚀另有 drip.png（底边水滴）；
- 词条：medal_<词条>.png 是左边的圆章（60 宽），kmid_<词条>.png 是中段，ktip_<词条>.png 是右边的尖头（28 宽）。
文字、数值在 Godot 里画（scenes/battle/fx/float_badge.gd）。

用法：just art
"""

import math

from autochess_tools.art.render import svg_to_png
from autochess_tools.art.ui import svg
from autochess_tools.data import REPO

PAD = 16
PLATE_TOP, PLATE_BOTTOM = 12, 52
ZOOM = 2


def claw(ax: float, ay: float, bx: float, by: float, w: float) -> str:
    """爪痕：从 A 到 B 的月牙形，最宽 w，中间一道白色高光"""
    mx, my = (ax + bx) / 2, (ay + by) / 2
    length = math.hypot(bx - ax, by - ay)
    nx, ny = (by - ay) / length, -(bx - ax) / length

    def at(k: float) -> str:
        return f"{mx + nx * w * k:.1f} {my + ny * w * k:.1f}"

    return (
        f'<path d="M{ax} {ay}Q{at(1.3)} {bx} {by}Q{at(0.15)} {ax} {ay}Z" fill="currentColor"/>'
        f'<path d="M{ax} {ay}Q{at(0.75)} {bx} {by}Q{at(0.35)} {ax} {ay}Z" fill="#fff" fill-opacity=".75"/>'
    )


def feather(x: float, y: float, angle: float, k: float) -> str:
    """羽毛：以 (x, y) 为根、向左伸出，angle 度（正值向上）"""
    return (
        f'<g transform="translate({x} {y}) rotate({angle}) scale({k})">'
        '<path d="M0 0C-6-5.5-19-6-28 0-19 4.5-6 4.5 0 0z" fill="url(#feather)" stroke="#7a5a10" stroke-width=".6"/>'
        '<path d="M0 0H-26" stroke="#fff" stroke-opacity=".7" stroke-width="1"/></g>'
    )


def sparkle(x: float, y: float, r: float) -> str:
    q = r * 0.26
    return f'<path d="M{x} {y - r}L{x + q} {y - q} {x + r} {y} {x + q} {y + q} {x} {y + r} {x - q} {y + q} {x - r} {y} {x - q} {y - q}Z" fill="#fff"/>'


def star(x: float, y: float, r: float, r2: float, color: str) -> str:
    points = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r2 if i % 2 else r
        points.append(f"{x + rr * math.cos(a):.1f} {y + rr * math.sin(a):.1f}")
    return f'<path d="M{"L".join(points)}Z" fill="{color}"/>'


def spikes(x: float, y: float, n: int, r1: float, r2: float) -> str:
    points = []
    for i in range(n * 2):
        a = -math.pi / 2 + i * math.pi / n
        rr = r1 if i % 2 else r2
        points.append(f"{x + rr * math.cos(a):.1f} {y + rr * math.sin(a):.1f}")
    return f'<path fill-rule="evenodd" d="M{"L".join(points)}Z M{x + 5} {y}A5 5 0 1 0 {x - 5} {y}A5 5 0 1 0 {x + 5} {y}Z"/>'


def drip(x: float, y: float) -> str:
    return f'<path d="M{x} {y}c0 3-3 6-3 8.5a3 3 0 0 0 6 0c0-2.5-3-5.5-3-8.5z" fill="currentColor"/>'


# 基础技能：颜色（名称和纹样）、外发光的深色、端部外形（plate 填充、edge 描边、inner 内线）、纹样；rotate 为真时右端旋转 180°
SKILLS = {
    # 狂暴：斜切的饰板，三道爪痕划过端部
    "rage": {
        "color": "#ff9d92",
        "deep": "#e5483b",
        "plate": "M48 12H27L15 52H48Z",
        "edge": "M48 12H27L15 52H48",
        "inner": "M48 15.5H29.6L19.8 48.5H48",
        "motif": "".join(claw(*c, 4.8) for c in [(44, -3, 16, 63), (35, -1, 7, 61), (26, 3, -1, 57)]),
    },
    # 集结：燕尾旗的端部，两道向内的箭形，边线上一枚菱形铆钉
    "rally": {
        "color": "#ffb66e",
        "deep": "#f28c28",
        "plate": "M48 12H5L17 32L5 52H48Z",
        "edge": "M48 12H5L17 32L5 52H48",
        "inner": "M48 15.5H11.4L21 32L11.4 48.5H48",
        "motif": '<path d="M22 23l7 9-7 9h5l7-9-7-9zM31 23l7 9-7 9h5l7-9-7-9z" fill="currentColor"/>'
        '<path d="M41 8.5l3.5 3.5-3.5 3.5-3.5-3.5zM41 48.5l3.5 3.5-3.5 3.5-3.5-3.5z" fill="currentColor" stroke="#000"/>',
    },
    # 支援：圆头饰板，端部伸出一对蝴蝶翅膀，带光点
    "support": {
        "color": "#8be8f2",
        "deep": "#29c4d6",
        "plate": "M48 12H30A20 20 0 0 0 30 52H48Z",
        "edge": "M48 12H30A20 20 0 0 0 30 52H48",
        "inner": "M48 15.5H30A16.5 16.5 0 0 0 30 48.5H48",
        "motif": '<path d="M26 14C20 2 8-4 3 1-1 5 3 13 12 17c4 2 9 1 14-3z" fill="currentColor" fill-opacity=".35" stroke="currentColor" stroke-width="1.6"/>'
        '<path d="M24 14C18 9 11 5 5 4M22 15c-5-1-10-1-14 1" fill="none" stroke="currentColor" stroke-opacity=".8"/>'
        '<path d="M24 50c-7 4-14 12-19 10-4-2-1-8 6-11 4-1 9-1 13 1z" fill="currentColor" fill-opacity=".35" stroke="currentColor" stroke-width="1.6"/>'
        + sparkle(4, 33, 4.5)
        + sparkle(14, 61, 3)
        + sparkle(40, 4, 3),
    },
    # 振奋：尖头饰板，端部展开羽翼（顶部光芒是单独的 crest.png）
    "inspire": {
        "color": "#ffe07a",
        "deep": "#e0a91c",
        "plate": "M48 12H26L13 32L26 52H48Z",
        "edge": "M48 12H26L13 32L26 52H48",
        "inner": "M48 15.5H27.9L17.2 32L27.9 48.5H48",
        "motif": "".join(feather(21, 31, a, k) for a, k in [(13, 1), (31, 1), (49, 0.86), (-16, 0.7), (-34, 0.6)]),
    },
    # 腐蚀：起伏的有机外形，带刺的藤蔓，底边挂着毒液（中段的水滴是单独的 drip.png）
    "corrode": {
        "color": "#a8e68c",
        "deep": "#4f9e2f",
        "plate": "M48 12H29C20 12 14 17 15 24c1 5-4 9-2 16 2 7 9 12 17 12H48Z",
        "edge": "M48 12H29C20 12 14 17 15 24c1 5-4 9-2 16 2 7 9 12 17 12H48",
        "inner": "M48 15.5H29.5C22.5 15.5 18.5 19.5 19 24.5c.5 5-3.5 9-2 15 1.5 5.5 6.5 9 13 9H48",
        "motif": '<path d="M28 55C15 60 3 51 5 39 7 28 19 26 21 34c1 5-5 7-8 3" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>'
        '<path d="M10 56l-5 3 1-6zM4.6 45l-4.6-1 3.6-3.4zM8 30.5l-3-3.8 5-.4zM18 27.6l1-4.8 3 4z" fill="currentColor"/>'
        '<path d="M22 11C17 3 9 2 4 6c5 5 11 7 18 5z" fill="currentColor" fill-opacity=".85"/>'
        '<path d="M21 10.4C15 8 10 6 6 6" stroke="#0b1a06" stroke-width=".8" fill="none"/>' + drip(38, 52),
    },
    # 湮灭：碎裂的端部，碎片飞散，裂纹伸进饰板
    "annihilate": {
        "color": "#d3cede",
        "deep": "#7d4bd0",
        "plate": "M48 12H25L29 20 19 26 25 33 15 41 23 46 19 52H48Z",
        "edge": "M48 12H25L29 20 19 26 25 33 15 41 23 46 19 52H48",
        "inner": "M48 15.5H31L33 21 24 26.5 29.5 33 21 40.5 27.5 45 25.5 48.5H48",
        "motif": '<path d="M10 13l7 4-6 4zM5 31l7 2-5 5zM9 47l6 4-7 4zM1 22l3 2-3 2zM14 58l3 1-2 3z" fill="currentColor"/>'
        '<path d="M29 20l7 3 6-2M25 33l8 2M23 46l7-1 4 3" fill="none" stroke="currentColor" stroke-opacity=".75"/>',
    },
    # 财富：钱币形的端部（铣边、星纹），周围有闪光
    "wealth": {
        "color": "#fab5dd",
        "deep": "#d8549e",
        "plate": "M48 12H30A20 20 0 0 0 30 52H48Z",
        "edge": "M48 12H30A20 20 0 0 0 30 52H48",
        "inner": "M48 15.5H30A16.5 16.5 0 0 0 30 48.5H48",
        "motif": '<circle cx="24" cy="32" r="16" fill="url(#gold)" stroke="#6b420c" stroke-width="1.5"/>'
        '<circle cx="24" cy="32" r="13.2" fill="none" stroke="#fff2c0" stroke-opacity=".75" stroke-width="1.4" stroke-dasharray="2 1.8"/>'
        + star(24, 32, 7.5, 3.2, "#c2457e")
        + sparkle(5, 10, 4.5)
        + sparkle(8, 57, 3.2)
        + sparkle(42, 5, 3),
    },
}
ROTATED = ["rage"]

# 词条：图标（48 网格）和所属种族的颜色
KEYWORDS = {
    "backlash": {"color": "#e5483b", "icon": spikes(24, 24, 8, 9, 21)},
    "sturdy": {
        "color": "#f28c28",
        "icon": '<path fill-rule="evenodd" d="M5 44V14h6V7h7v7h12V7h7v7h6v30zM9 22v2.4h30V22zm0 9v2.4h30V31zm14-17v8h2.4v-8zm-8 10.4v6.6h2.4v-6.6zm16 0v6.6h2.4v-6.6zm-8 9v10.6h2.4V33.4z"/>',
    },
    "awaken": {
        "color": "#29c4d6",
        "icon": '<path fill-rule="evenodd" d="M2 27c8-12 36-12 44 0-8 12-36 12-44 0zm22-8a8 8 0 1 0 0 16 8 8 0 0 0 0-16zm0 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8z"/>'
        '<path d="M22.6 3h2.8v8h-2.8zM8.5 7.6l2.4-1.4 4 6.9-2.4 1.4zM39.5 7.6l-2.4-1.4-4 6.9 2.4 1.4z"/>',
    },
    "shelter": {
        "color": "#f2c94c",
        "icon": '<path fill-rule="evenodd" d="M24 3c7 4 13 5 18 5 0 18-6 29-18 36C12 37 6 26 6 8c5 0 11-1 18-5zm-2.5 10v7h-7v5h7v11h5V25h7v-5h-7v-7z"/>',
    },
    "lethal": {
        "color": "#5dbb46",
        "icon": '<path d="M5 7c12-4 26-4 38 0l-2 6c-11-3-23-3-34 0z"/><path d="M10 12c1 11 4 20 9 27-1-9-1-18 1-27zM38 12c-1 11-4 20-9 27 1-9 1-18-1-27z"/>'
        '<path d="M29 38c0 3-3 5-3 7.4a3 3 0 0 0 6 0c0-2.4-3-4.4-3-7.4z"/>',
    },
}
SILVER = "#dfe6f3"

DEFS = (
    '<linearGradient id="plate" gradientUnits="userSpaceOnUse" x1="0" y1="12" x2="0" y2="52">'
    '<stop offset="0" stop-color="#1c2452" stop-opacity=".95"/><stop offset="1" stop-color="#070a18" stop-opacity=".95"/></linearGradient>'
    '<radialGradient id="gold" cx=".4" cy=".35" r=".7"><stop offset="0" stop-color="#fff4c2"/>'
    '<stop offset=".55" stop-color="#f2c14e"/><stop offset="1" stop-color="#a8701c"/></radialGradient>'
    '<linearGradient id="feather" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff8d8"/>'
    '<stop offset="1" stop-color="#ffd24a"/></linearGradient>'
)


def glow(color: str, size: float, opacity: float = 1, tight: bool = True) -> str:
    """外发光（颜色 color、半径 size）加向下的黑色投影；tight 时再加一圈贴边的光（基础技能用）"""
    tight_layer = (
        f'<feGaussianBlur in="SourceAlpha" stdDeviation="1" result="b2"/><feFlood flood-color="{color}" flood-opacity="{opacity}"/>'
        '<feComposite in2="b2" operator="in" result="g2"/>'
        if tight
        else ""
    )
    return (
        '<filter id="glow" filterUnits="userSpaceOnUse" x="-200" y="-200" width="600" height="600" color-interpolation-filters="sRGB">'
        f'<feGaussianBlur in="SourceAlpha" stdDeviation="{size / 2}" result="b1"/><feFlood flood-color="{color}" flood-opacity="{opacity}"/>'
        f'<feComposite in2="b1" operator="in" result="g1"/>{tight_layer}'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="1.5" result="b3"/><feOffset in="b3" dy="3" result="o3"/>'
        '<feFlood flood-color="#000" flood-opacity=".75"/><feComposite in2="o3" operator="in" result="s"/>'
        '<feMerge><feMergeNode in="s"/><feMergeNode in="g1"/>'
        + ('<feMergeNode in="g2"/>' if tight else "")
        + '<feMergeNode in="SourceGraphic"/></feMerge></filter>'
    )


def strip(x0: float, x1: float, color: str, inner: bool = True) -> str:
    """中段：饰板底和上下边线（x0 到 x1）；inner 为真时还有淡内线"""
    lines = f'<path d="M{x0} 12H{x1}M{x0} 52H{x1}" stroke="{color}" stroke-width="2"/>'
    if inner:
        lines += f'<path d="M{x0} 15.5H{x1}M{x0} 48.5H{x1}" stroke="{color}" stroke-width="1" stroke-opacity=".35"/>'
    return f'<rect x="{x0}" y="12" width="{x1 - x0}" height="40" fill="url(#plate)"/>{lines}'


def canvas(x: float, y: float, w: float, h: float, body: str, color: str, filter_defs: str) -> str:
    """viewBox 从 (x, y) 开始的贴图，内容套上外发光；color 是纹样里 currentColor 的颜色"""
    return svg(
        w,
        h,
        f'<g transform="translate({-x} {-y})"><g filter="url(#glow)" color="{color}">{body}</g></g>',
        DEFS + filter_defs,
    )


def textures() -> dict[str, str]:
    out = {}
    for skill, fx in SKILLS.items():
        effect = glow(fx["deep"], 5)
        # 端饰的右边接中段：饰板和边线往右多画一截，外发光在接缝处不变淡（超出贴图的部分被裁掉）
        cap = (
            strip(48, 120, fx["color"])
            + f'<path d="{fx["plate"]}" fill="url(#plate)"/><path d="{fx["edge"]}" fill="none" stroke="currentColor" stroke-width="2"/>'
            f'<path d="{fx["inner"]}" fill="none" stroke="currentColor" stroke-opacity=".35"/>{fx["motif"]}'
        )
        out[f"cap_{skill}"] = canvas(-PAD, -PAD, 48 + PAD, 64 + 2 * PAD, cap, fx["color"], effect)
        out[f"mid_{skill}"] = canvas(0, -PAD, 8, 64 + 2 * PAD, strip(-80, 88, fx["color"]), fx["color"], effect)
    # 振奋顶部的光芒：七道，从饰板上边向上放射（贴图覆盖光芒坐标 x -8–68、y -8–28）
    rays = ""
    for i in range(7):
        a = math.radians(-150 + i * 20)
        length = 9 if i % 2 else 13
        x0, y0 = 30 + 7 * math.cos(a), 18 + 7 * math.sin(a)
        x1, y1 = 30 + (7 + length) * math.cos(a), 18 + (7 + length) * math.sin(a)
        rays += f'<path d="M{x0:.1f} {y0:.1f}L{x1:.1f} {y1:.1f}" stroke="currentColor" stroke-width="{2 if i % 2 else 2.8}" stroke-linecap="round"/>'
    rays += '<circle cx="30" cy="18" r="3" fill="#fff"/>'
    out["crest"] = canvas(-8, -8, 76, 36, rays, SKILLS["inspire"]["color"], glow(SKILLS["inspire"]["deep"], 5))
    # 腐蚀中段底边的水滴（贴图覆盖 x -4–16、y -4–18，水滴挂在 (6, 0)）
    out["drip"] = canvas(-4, -4, 20, 22, drip(6, 0), SKILLS["corrode"]["color"], glow(SKILLS["corrode"]["deep"], 5))
    for keyword, fx in KEYWORDS.items():
        effect = glow(fx["color"], 6, 0.7, tight=False)
        medal = (
            strip(30, 120, SILVER, inner=False)
            + f'<circle cx="30" cy="32" r="24" fill="#0b0f22" stroke="{SILVER}" stroke-width="2"/>'
            f'<circle cx="30" cy="32" r="20" fill="none" stroke="{fx["color"]}" stroke-width="1.5" stroke-opacity=".7"/>'
            f'<g transform="translate(13 15) scale(.71)" fill="{fx["color"]}">{fx["icon"]}</g>'
        )
        out[f"medal_{keyword}"] = canvas(-PAD, -PAD, 60 + PAD, 64 + 2 * PAD, medal, SILVER, effect)
        out[f"kmid_{keyword}"] = canvas(0, -PAD, 8, 64 + 2 * PAD, strip(-80, 88, SILVER, inner=False), SILVER, effect)
        tip = (
            strip(-80, 1, SILVER, inner=False)
            + f'<path d="M0 12H10L24 32 10 52H0Z" fill="url(#plate)"/><path d="M0 12H10L24 32 10 52H0" fill="none" stroke="{SILVER}" stroke-width="2"/>'
        )
        out[f"ktip_{keyword}"] = canvas(0, -PAD, 28 + PAD, 64 + 2 * PAD, tip, SILVER, effect)
    return out


def main() -> None:
    folder = REPO / "assets" / "ui" / "fx"
    items = textures()
    for name, body in items.items():
        svg_to_png(body, folder / f"{name}.png", ZOOM)
    print(f"fx：{len(items)} 张贴图")


if __name__ == "__main__":
    main()
