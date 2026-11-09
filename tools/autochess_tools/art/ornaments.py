"""卡牌的星级边框、角色背景的法阵、装备背景的附魔阵，渲染成 PNG 写到 assets/ui/card/。

- frame_<星级>.png、frame_compact_<星级>.png：完整卡（300×420）和紧凑卡（300×300）的边框，
  四周各留 MARGIN 的空，给伸出卡外的装饰；星级越高越复杂：黑铁、黄铜、白银、黄金、棱彩。
- circle_<星级>.png：角色背景的圆形法阵；array_<星级>.png：装备背景的六边形附魔阵。线条颜色随星级，带一点辉光。

都按 ZOOM 倍渲染，卡牌放大查看时也清楚。用法：just art
"""

import math
import random

from autochess_tools.art.render import svg_to_png
from autochess_tools.data import REPO

W, R = 300, 16  # 卡宽、外圆角
MARGIN = 32  # 边框图四周留的空：棱彩的水晶冠伸出卡外约 30
ZOOM = 2
BORDER = {1: 8, 2: 10, 3: 11, 4: 12, 5: 13}  # 边框宽度随星级加宽
LINE = {1: "#b4bcc6", 2: "#dcab6a", 3: "#eef4ff", 4: "#ffd866"}  # 法阵线条颜色；棱彩是渐变
PRISM = ["#ff9ad8", "#ffd56e", "#8af5c6", "#7ab8ff", "#c58aff"]


def rrect(x, y, w, h, r):
    return (
        f"M{x + r},{y}H{x + w - r}A{r},{r} 0 0 1 {x + w},{y + r}V{y + h - r}A{r},{r} 0 0 1 {x + w - r},{y + h}"
        f"H{x + r}A{r},{r} 0 0 1 {x},{y + h - r}V{y + r}A{r},{r} 0 0 1 {x + r},{y}Z"
    )


MATERIAL = {
    1: ["#6a7079", "#2a2d33", "#4a4f57", "#1a1c20", "#3a3e45"],
    2: ["#e8c48c", "#8a6031", "#c99d5f", "#573c1c", "#b0844d"],
    3: ["#ffffff", "#a7b1bf", "#f3f6fa", "#7a8493", "#dfe6ee"],
    4: ["#fff6c4", "#d29a1c", "#ffe17a", "#916008", "#f6c84a"],
    5: ["#ffa6dc", "#ffe39a", "#a6f7d6", "#94cdff", "#d1a8ff"],
}
DARK = "rgba(0,0,0,.7)"


def grad(gid, stops, x2=1, y2=1):
    s = "".join(f'<stop offset="{i / (len(stops) - 1):.2f}" stop-color="{c}"/>' for i, c in enumerate(stops))
    return f'<linearGradient id="{gid}" x1="0" y1="0" x2="{x2}" y2="{y2}">{s}</linearGradient>'


def gem(cx, cy, r, colors, gid):
    """宝石：径向渐变 + 高光"""
    return (
        f'<radialGradient id="{gid}" cx=".35" cy=".3" r=".8"><stop offset="0" stop-color="{colors[0]}"/>'
        f'<stop offset=".55" stop-color="{colors[1]}"/><stop offset="1" stop-color="{colors[2]}"/></radialGradient>'
        f'<circle cx="{cx}" cy="{cy}" r="{r + 1.6}" fill="#1a1206" opacity=".85"/>'
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#{gid})"/>'
        f'<circle cx="{cx - r * 0.35:.1f}" cy="{cy - r * 0.38:.1f}" r="{r * 0.28:.1f}" fill="#fff" opacity=".85"/>'
    )


def rivet(cx, cy, r, light, dark):
    return (
        f'<circle cx="{cx}" cy="{cy}" r="{r + 1}" fill="rgba(0,0,0,.55)"/>'
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{dark}"/>'
        f'<circle cx="{cx - 0.6}" cy="{cy - 0.6}" r="{r * 0.7:.1f}" fill="{light}"/>'
        f'<circle cx="{cx - r * 0.35:.1f}" cy="{cy - r * 0.4:.1f}" r="{r * 0.25:.1f}" fill="#fff" opacity=".7"/>'
    )


def corners(svg, h):
    """把左上角的装饰复制到四个角"""
    return (
        f"<g>{svg}</g><g transform='translate({W} 0) scale(-1 1)'>{svg}</g>"
        f"<g transform='translate(0 {h}) scale(1 -1)'>{svg}</g><g transform='translate({W} {h}) scale(-1 -1)'>{svg}</g>"
    )


def top_bottom(svg, h):
    """上边中点的装饰镜像到下边"""
    return f"<g>{svg}</g><g transform='translate(0 {h}) scale(1 -1)'>{svg}</g>"


def sides(svg, h):
    """左边中点的装饰镜像到右边（装饰按卡高 420 画，中点 y=210，其他高度整体平移）"""
    dy = h / 2 - 210
    return f"<g transform='translate(0 {dy})'><g>{svg}</g><g transform='translate({W} 0) scale(-1 1)'>{svg}</g></g>"


def scroll(stroke, width, k=1.0):
    """角花：两条卷草，沿上边和左边伸出"""
    d = (
        "M8 46C8 30 14 22 24 20C18 25 17 31 21 34C25 37 30 33 28 28"
        "M46 8C30 8 22 14 20 24C25 18 31 17 34 21C37 25 33 30 28 28"
    )
    return (
        f'<g transform="scale({k})"><path d="{d}" fill="none" stroke="rgba(0,0,0,.65)" stroke-width="{width + 2.2}" stroke-linecap="round"/>'
        f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="{width}" stroke-linecap="round"/></g>'
    )


def beads(b, step, r, fill, h, skip=()):
    """沿边框中线排一圈珠子；skip 是 (x0, x1, y0, y1) 区域，避开角和冠饰"""
    out = []
    m = b / 2
    pts = [(x, m) for x in range(int(R + 24), int(W - R - 23), step)] + [
        (x, h - m) for x in range(int(R + 24), int(W - R - 23), step)
    ]
    pts += [(m, y) for y in range(int(R + 24), int(h - R - 23), step)] + [
        (W - m, y) for y in range(int(R + 24), int(h - R - 23), step)
    ]
    for x, y in pts:
        if any(x0 <= x <= x1 and y0 <= y <= y1 for x0, x1, y0, y1 in skip):
            continue
        out.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="rgba(0,0,0,.6)" stroke-width=".7"/>')
    return "".join(out)


def sparkle(cx, cy, r, fill="#fff"):
    return f'<path d="M{cx} {cy - r}Q{cx} {cy} {cx + r} {cy}Q{cx} {cy} {cx} {cy + r}Q{cx} {cy} {cx - r} {cy}Q{cx} {cy} {cx} {cy - r}Z" fill="{fill}"/>'


def shard(points, fill="url(#cr5)"):
    pts = " ".join(f"{x},{y}" for x, y in points)
    return f'<polygon points="{pts}" fill="{fill}" stroke="rgba(40,20,80,.75)" stroke-width="1"/>'


def frame(tier, h):
    b = BORDER[tier]
    inner = rrect(b, b, W - 2 * b, h - 2 * b, 8)
    outer = rrect(0, 0, W, h, R)
    ring_path = outer + inner
    m = MATERIAL[tier]
    defs = [grad(f"fm{tier}", m)]
    body = []
    if tier == 1:  # 黑铁：粗糙锤打颗粒
        defs.append(
            '<filter id="fx1" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" seed="3"/>'
            '<feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -1.3 1"/><feComposite in2="SourceGraphic" operator="in"/></filter>'
        )
    if tier == 2:  # 黄铜：氧化斑驳
        defs.append(
            '<filter id="fx2" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".09" numOctaves="3" seed="7"/>'
            '<feColorMatrix values="0 0 0 0 .1  0 0 0 0 .25  0 0 0 0 .2  0 0 0 -1.6 1.05"/><feComposite in2="SourceGraphic" operator="in"/></filter>'
        )
    if tier == 5:
        defs.append(
            '<linearGradient id="cr5" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff"/><stop offset=".4" stop-color="#c9b6ff"/>'
            '<stop offset=".7" stop-color="#8fe9ff"/><stop offset="1" stop-color="#ffb3e6"/></linearGradient>'
            '<filter id="glow5" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2.2"/></filter>'
        )
    body.append(f'<path d="{ring_path}" fill-rule="evenodd" fill="url(#fm{tier})"/>')
    if tier in (1, 2):
        body.append(
            f'<path d="{ring_path}" fill-rule="evenodd" fill="#000" filter="url(#fx{tier})" opacity="{0.6 if tier == 1 else 0.6}"/>'
        )
    if tier >= 3:  # 抛光高光
        defs.append(
            f'<linearGradient id="sh{tier}" x1="0" y1="0" x2="1" y2="1"><stop offset=".25" stop-color="#fff" stop-opacity="0"/>'
            f'<stop offset=".33" stop-color="#fff" stop-opacity=".75"/><stop offset=".4" stop-color="#fff" stop-opacity="0"/>'
            f'<stop offset=".68" stop-color="#fff" stop-opacity="0"/><stop offset=".73" stop-color="#fff" stop-opacity=".5"/><stop offset=".78" stop-color="#fff" stop-opacity="0"/></linearGradient>'
        )
        body.append(f'<path d="{ring_path}" fill-rule="evenodd" fill="url(#sh{tier})"/>')
    # 斜面：外缘暗线、内缘亮线、内侧阴影
    body.append(f'<path d="{outer}" fill="none" stroke="{DARK}" stroke-width="1.5"/>')
    body.append(
        f'<path d="{rrect(1.5, 1.5, W - 3, h - 3, R - 1.5)}" fill="none" stroke="rgba(255,255,255,.3)" stroke-width="1"/>'
    )
    body.append(f'<path d="{inner}" fill="none" stroke="rgba(255,255,255,.45)" stroke-width="1"/>')
    body.append(
        f'<path d="{rrect(b + 1, b + 1, W - 2 * b - 2, h - 2 * b - 2, 7)}" fill="none" stroke="rgba(0,0,0,.6)" stroke-width="2"/>'
    )
    if tier >= 2:  # 刻槽
        body.append(
            f'<path d="{rrect(3.5, 3.5, W - 7, h - 7, R - 3)}" fill="none" stroke="rgba(0,0,0,.45)" stroke-width="1"/>'
        )
    if tier >= 3:
        body.append(
            f'<path d="{rrect(b - 2.5, b - 2.5, W - 2 * b + 5, h - 2 * b + 5, 10)}" fill="none" stroke="rgba(0,0,0,.4)" stroke-width="1"/>'
        )
    if tier == 5:  # 内缘辉光
        body.append(
            f'<path d="{inner}" fill="none" stroke="#e8d8ff" stroke-width="3" filter="url(#glow5)" opacity=".9"/>'
        )

    if tier == 1:  # 黑铁：只有四颗铆钉
        body.append(corners(rivet(8.5, 8.5, 2.6, "#7c838d", "#2a2d33"), h))
    if tier == 2:  # 黄铜：角片 + 螺栓，侧边小螺栓
        plate = "M0 16A16 16 0 0 1 16 0H46L40 15H24A9 9 0 0 0 15 24V40L0 46Z"
        body.append(
            corners(
                f'<path d="{plate}" fill="url(#fm2)" stroke="{DARK}" stroke-width="1.2"/>'
                + rivet(10.5, 10.5, 3.2, "#e9c993", "#6a4a22"),
                h,
            )
        )
        body.append(
            rivet(5, h / 3, 2.4, "#e9c993", "#6a4a22")
            + rivet(5, h * 2 / 3, 2.4, "#e9c993", "#6a4a22")
            + rivet(W - 5, h / 3, 2.4, "#e9c993", "#6a4a22")
            + rivet(W - 5, h * 2 / 3, 2.4, "#e9c993", "#6a4a22")
        )
    if tier == 3:  # 白银：卷草、珠饰、上下菱形冠（略微凸出卡外）
        body.append(
            beads(
                b,
                12,
                1.5,
                "#f4f7fb",
                h,
                skip=[
                    (118, 182, 0, 20),
                    (118, 182, h - 20, h),
                    (0, 20, h / 2 - 14, h / 2 + 14),
                    (W - 20, W, h / 2 - 14, h / 2 + 14),
                ],
            )
        )
        body.append(corners(scroll("#f4f7fb", 2.2, 1.0) + rivet(10, 10, 3, "#ffffff", "#8c96a4"), h))
        body.append(
            top_bottom(
                '<path d="M150 -9L161 2L150 13L139 2Z" fill="url(#fm3)" stroke="rgba(0,0,0,.65)" stroke-width="1.1"/>'
                '<path d="M150 -3L155 2L150 7L145 2Z" fill="#7d8b9e"/>',
                h,
            )
        )
        body.append(
            sides(
                '<path d="M-5 210L5 200L15 210L5 220Z" fill="url(#fm3)" stroke="rgba(0,0,0,.65)" stroke-width="1.1"/>',
                h,
            )
        )
    if tier == 4:  # 黄金：外凸的角饰、上下冠饰、侧边徽章、珠饰、宝石
        body.append(
            beads(
                b,
                11,
                1.8,
                "#fff1b0",
                h,
                skip=[
                    (108, 192, 0, 24),
                    (108, 192, h - 24, h),
                    (0, 24, h / 2 - 18, h / 2 + 18),
                    (W - 24, W, h / 2 - 18, h / 2 + 18),
                ],
            )
        )
        fan = "M-7 30C-10 10 10 -10 30 -7L26 5C15 4 4 15 5 26Z"
        body.append(
            corners(
                scroll("#fff1b0", 2.4, 1.1)
                + f'<path d="{fan}" fill="url(#fm4)" stroke="{DARK}" stroke-width="1.1"/>'
                + '<path d="M-2 22C-3 9 9 -3 22 -2" fill="none" stroke="rgba(120,70,0,.7)" stroke-width="1"/>'
                + gem(8, 8, 6, ["#bfe3ff", "#2f6fd6", "#0b2a66"], "gs4"),
                h,
            )
        )
        crest = "M112 6C116 -2 124 -6 132 -6C136 -14 143 -19 150 -20C157 -19 164 -14 168 -6C176 -6 184 -2 188 6Z"
        body.append(
            top_bottom(
                f'<path d="{crest}" fill="url(#fm4)" stroke="{DARK}" stroke-width="1.2"/>'
                + '<path d="M120 3C126 -1 134 -2 140 0M180 3C174 -1 166 -2 160 0" fill="none" stroke="rgba(120,70,0,.8)" stroke-width="1.2"/>'
                + gem(150, -6, 6, ["#ffd0d0", "#d6262f", "#5a0710"], "gr4"),
                h,
            )
        )
        body.append(
            sides(
                '<circle cx="3" cy="210" r="12" fill="url(#fm4)" stroke="rgba(0,0,0,.7)" stroke-width="1.2"/>'
                + gem(3, 210, 5.5, ["#ffd0d0", "#d6262f", "#5a0710"], "gr4b"),
                h,
            )
        )
    if tier == 5:  # 棱彩：外凸的水晶簇、水晶冠、棱镜珠、星芒
        body.append(
            beads(
                b,
                10,
                2,
                "#f3e8ff",
                h,
                skip=[
                    (100, 200, 0, 28),
                    (100, 200, h - 28, h),
                    (0, 26, h / 2 - 24, h / 2 + 24),
                    (W - 26, W, h / 2 - 24, h / 2 + 24),
                ],
            )
        )
        cluster = (
            shard([(10, 3), (-16, -16), (3, 10)])
            + shard([(17, 2), (-1, -22), (8, -1)])
            + shard([(2, 17), (-22, -1), (-1, 8)])
            + '<path d="M10 3 -16 -16M17 2-1-22M2 17-22-1" stroke="rgba(255,255,255,.8)" stroke-width=".8"/>'
        )
        body.append(
            corners(
                scroll("#ffffff", 2.4, 1.15) + cluster + gem(9, 9, 5.6, ["#ffffff", "#c58aff", "#4a1b8a"], "gp5"), h
            )
        )
        crown = "".join(
            shard([(150 + dx - w, 6), (150 + dx, -ch), (150 + dx + w, 6)])
            for dx, ch, w in ((-30, 10, 6), (30, 10, 6), (-18, 18, 7), (18, 18, 7), (0, 30, 9))
        )
        body.append(
            top_bottom(
                crown
                + '<path d="M150 6V-30" stroke="rgba(255,255,255,.85)" stroke-width=".9"/>'
                + gem(150, 0, 6, ["#ffffff", "#7fd8ff", "#1b4a8a"], "gb5"),
                h,
            )
        )
        body.append(
            sides(
                shard([(6, 196), (-18, 210), (6, 224)])
                + shard([(6, 202), (-10, 182), (2, 206)])
                + shard([(6, 218), (-10, 238), (2, 214)]),
                h,
            )
        )
        for x, y, r in (
            (60, -6, 5),
            (240, -9, 4),
            (-8, h * 0.21, 4),
            (W + 7, h * 0.79, 5),
            (90, h + 7, 4),
            (W - 70, h + 5, 5),
            (-6, h * 0.86, 3),
            (W + 5, h * 0.29, 3),
        ):
            body.append(sparkle(x, y, r))
    return "".join(defs), "".join(body)


def pt(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def polygon(cx, cy, r, n, rot=-90, step=1, w=1.2):
    """正多边形或星形（step>1 时为星形连线）"""
    pts = [pt(cx, cy, r, rot + 360 * i / n) for i in range(n)]
    out = []
    seen = set()
    for s in range(n):
        if s in seen:
            continue
        loop, i = [], s
        while i not in seen:
            seen.add(i)
            loop.append(pts[i])
            i = (i + step) % n
        out.append('<polygon points="' + " ".join(f"{x:.1f},{y:.1f}" for x, y in loop) + f'" stroke-width="{w}"/>')
    return "".join(out)


def ring(cx, cy, r, w=1.2):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" stroke-width="{w}"/>'


def ticks(cx, cy, r1, r2, n, w=1):
    return "".join(
        f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke-width="{w}"/>'
        for i in range(n)
        for (x1, y1), (x2, y2) in [
            (pt(cx, cy, r1, 360 * i / n), pt(cx, cy, r2 if i % 2 else (r1 + r2) / 2, 360 * i / n))
        ]
    )


def runes(cx, cy, r, n, size, seed):
    """符文带：随机笔画的小字形，沿圆周排列"""
    rnd = random.Random(seed)
    grid = [(x, y) for x in (-1, 0, 1) for y in (-1.4, 0, 1.4)]
    out = []
    for i in range(n):
        deg = 360 * i / n
        x, y = pt(cx, cy, r, deg)
        strokes = []
        for _ in range(rnd.randint(2, 3)):
            a, b = rnd.sample(grid, 2)
            strokes.append(f"M{a[0] * size / 2:.1f} {a[1] * size / 2:.1f}L{b[0] * size / 2:.1f} {b[1] * size / 2:.1f}")
        out.append(
            f'<path transform="translate({x:.1f} {y:.1f}) rotate({deg + 90:.1f})" d="{"".join(strokes)}" stroke-width="1.1" stroke-linecap="round"/>'
        )
    return "".join(out)


def dots(cx, cy, r, n, size):
    return "".join(
        f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{size}" stroke-width="1"/>'
        for x, y in (pt(cx, cy, r, 360 * i / n + 15) for i in range(n))
    )


def circle(tier):
    c, R0 = 160, 150
    g = []
    if tier == 1:
        g += [ring(c, c, R0, 2), ring(c, c, R0 - 10), polygon(c, c, R0 - 10, 3), ring(c, c, 44)]
    if tier == 2:
        g += [ring(c, c, R0, 2), ring(c, c, R0 - 10), ticks(c, c, R0 - 10, R0 - 4, 36), ring(c, c, R0 - 30)]
        g += [polygon(c, c, R0 - 30, 4), polygon(c, c, R0 - 30, 4, rot=-45), dots(c, c, R0 - 30, 8, 4), ring(c, c, 52)]
    if tier == 3:
        g += [
            ring(c, c, R0, 2.2),
            ring(c, c, R0 - 6),
            ticks(c, c, R0 - 6, R0 - 16, 72),
            ring(c, c, R0 - 20),
            ring(c, c, R0 - 34, 1.6),
        ]
        g += [
            polygon(c, c, R0 - 34, 6, step=2, w=1.5),
            dots(c, c, R0 - 34, 6, 8),
            dots(c, c, R0 - 27, 12, 2),
            ring(c, c, 58),
            ring(c, c, 48),
        ]
    if tier >= 4:
        g += [
            ring(c, c, R0, 2.4),
            ring(c, c, R0 - 4),
            runes(c, c, R0 - 11, 30, 7, 11),
            ring(c, c, R0 - 18),
            ring(c, c, R0 - 22, 1.6),
        ]
        g += [
            ticks(c, c, R0 - 22, R0 - 30, 60),
            polygon(c, c, R0 - 34, 6, step=2, w=1.6),
            polygon(c, c, R0 - 34, 6, rot=0),
        ]
        g += [
            dots(c, c, R0 - 34, 6, 9),
            dots(c, c, R0 - 34, 6, 4),
            ring(c, c, 62),
            polygon(c, c, 62, 12, step=5),
            ring(c, c, 40),
            ring(c, c, 34),
        ]
    if tier == 5:
        g += [runes(c, c, 52, 16, 5, 23), polygon(c, c, 34, 8, step=3)]
        for i in range(12):
            a = 360 * i / 12
            (x1, y1), (x2, y2) = pt(c, c, R0 + 2, a), pt(c, c, R0 + 12 if i % 2 else R0 + 8, a)
            g.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke-width="1.6"/>')
        for i in range(4):
            a0 = 90 * i + 20
            (x1, y1), (x2, y2) = pt(c, c, R0 + 6, a0), pt(c, c, R0 + 6, a0 + 50)
            g.append(f'<path d="M{x1:.1f} {y1:.1f}A{R0 + 6} {R0 + 6} 0 0 1 {x2:.1f} {y2:.1f}" stroke-width="1.4"/>')
    return "".join(g)


def array(tier):
    """装备的六边形附魔阵"""
    c, R0 = 160, 148
    g = [polygon(c, c, R0, 6, rot=-90, w=2.2), polygon(c, c, R0 - 12, 6, rot=-90)]
    if tier >= 2:
        g += [ticks(c, c, R0 - 34, R0 - 28, 36), ring(c, c, R0 - 34), polygon(c, c, R0 - 34, 6, rot=0)]
    else:
        g += [ring(c, c, 60)]
    if tier >= 3:
        g += [
            polygon(c, c, R0 - 34, 6, step=2, w=1.5),
            dots(c, c, R0 - 12, 6, 6),
            ring(c, c, 56),
            polygon(c, c, 56, 6, rot=-90),
        ]
    if tier >= 4:
        g += [
            runes(c, c, R0 - 46, 24, 6, 31),
            ring(c, c, R0 - 54),
            polygon(c, c, 40, 3, rot=-90),
            polygon(c, c, 40, 3, rot=90),
        ]
    if tier == 5:
        g += [polygon(c, c, R0 + 10, 6, rot=0, w=1.2), dots(c, c, R0 + 10, 6, 5), polygon(c, c, 24, 6, step=2)]
    return "".join(g)


def frame_svg(tier: int, h: int) -> str:
    defs, body = frame(tier, h)
    view = f"{-MARGIN} {-MARGIN} {W + 2 * MARGIN} {h + 2 * MARGIN}"
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}"><defs>{defs}</defs>{body}</svg>'


def pattern_svg(tier: int, body: str) -> str:
    """法阵：线条按星级上色，下面垫一层暗描边和一层辉光"""
    if tier == 5:
        stops = "".join(f'<stop offset="{i / 4}" stop-color="{c}"/>' for i, c in enumerate(PRISM))
        paint = "url(#line)"
        defs = f'<linearGradient id="line" x1="0" y1="0" x2="1" y2="1">{stops}</linearGradient>'
        glow = "#e6d4ff"
    else:
        paint, defs, glow = LINE[tier], "", LINE[tier]
    defs += (
        '<filter id="glow" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="2.5"/></filter>'
        '<filter id="shade" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation=".8"/></filter>'
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 320" fill="none"><defs>{defs}</defs>'
        f'<g stroke="#000" stroke-opacity=".6" filter="url(#shade)">{body}</g>'
        f'<g stroke="{glow}" stroke-opacity=".7" filter="url(#glow)">{body}</g>'
        f'<g stroke="{paint}">{body}</g></svg>'
    )


def main() -> None:
    out = REPO / "assets" / "ui" / "card"
    for tier in range(1, 6):
        svg_to_png(frame_svg(tier, 420), out / f"frame_{tier}.png", ZOOM)
        svg_to_png(frame_svg(tier, 300), out / f"frame_compact_{tier}.png", ZOOM)
        svg_to_png(pattern_svg(tier, circle(tier)), out / f"circle_{tier}.png", ZOOM)
        svg_to_png(pattern_svg(tier, array(tier)), out / f"array_{tier}.png", ZOOM)
    print(f"边框和法阵：5 档，写到 {out.relative_to(REPO)}")


if __name__ == "__main__":
    main()
