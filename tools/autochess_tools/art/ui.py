"""界面控件和卡面面板的贴图，渲染成 PNG 写到 assets/ui/theme/ 和 assets/ui/card/。

风格和主菜单一致：深蓝渐变底板、细金线、黑色间隙、淡金内线。九宫格贴图的边距见 cli/build_theme.gd。
用法：just art
"""

from autochess_tools.art.render import svg_to_png
from autochess_tools.data import REPO

GOLD = "#ffd98a"
CARD_LINE = {1: "#b4bcc6", 2: "#dcab6a", 3: "#eef4ff", 4: "#ffd866", 5: "#e6d4ff"}  # 卡面面板的线色随星级
EQUIP_BG = {1: "#4b525e", 2: "#7c5a32", 3: "#4d6a90", 4: "#8c6a12", 5: "#5a3d93"}  # 装备底色随星级


def mix(a: str, b: str, t: float) -> str:
    """两种颜色按 t 混合（0 是 a，1 是 b）"""
    ca, cb = (tuple(int(c[i : i + 2], 16) for i in (1, 3, 5)) for c in (a, b))
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb, strict=True))


def svg(w: float, h: float, body: str, defs: str = "") -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}"><defs>{defs}</defs>{body}</svg>'


def vgrad(gid: str, top: str, bottom: str, top_opacity: float = 1, bottom_opacity: float = 1) -> str:
    return (
        f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{top}" stop-opacity="{top_opacity}"/>'
        f'<stop offset="1" stop-color="{bottom}" stop-opacity="{bottom_opacity}"/></linearGradient>'
    )


def plate(
    size: int,
    radius: float,
    fill: str,
    line: str,
    line_opacity: float,
    inner_opacity: float,
    pad: int = 0,
    defs: str = "",
    line_width: float = 1,
    glow: str = "",
) -> str:
    """底板：填充、外线、黑色间隙、淡内线。pad 是四周留给外发光的空"""
    s, p = size, pad
    inner = s - 2 * p
    glow_layer = ""
    if glow:
        defs += (
            '<filter id="g" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter>'
        )
        glow_layer = f'<rect x="{p}" y="{p}" width="{inner}" height="{inner}" rx="{radius}" fill="none" stroke="{glow}" stroke-width="4" stroke-opacity=".55" filter="url(#g)"/>'
    lw = line_width
    return svg(
        s,
        s,
        glow_layer
        + f'<rect x="{p}" y="{p}" width="{inner}" height="{inner}" rx="{radius}" fill="{fill}"/>'
        + f'<rect x="{p + lw / 2}" y="{p + lw / 2}" width="{inner - lw}" height="{inner - lw}" rx="{radius - lw / 2}" fill="none" stroke="{line}" stroke-opacity="{line_opacity}" stroke-width="{lw}"/>'
        + f'<rect x="{p + lw + 1.5}" y="{p + lw + 1.5}" width="{inner - 2 * lw - 3}" height="{inner - 2 * lw - 3}" rx="{max(radius - 2.5, 1)}" fill="none" stroke="#000" stroke-opacity=".45" stroke-width="3"/>'
        + f'<rect x="{p + lw + 3.5}" y="{p + lw + 3.5}" width="{inner - 2 * lw - 7}" height="{inner - 2 * lw - 7}" rx="{max(radius - 4, 1)}" fill="none" stroke="{line}" stroke-opacity="{inner_opacity}" stroke-width="1"/>',
        defs,
    )


def blue(gid: str = "bg", alpha: float = 0.92) -> tuple[str, str]:
    return f"url(#{gid})", vgrad(gid, "#182046", "#090c1e", alpha, min(alpha + 0.02, 1))


def theme_textures() -> dict[str, str]:
    fill, defs = blue()
    hover_fill, hover_defs = "url(#bg)", vgrad("bg", "#232c5e", "#0d1230", 0.95, 0.97)
    pressed_fill, pressed_defs = "url(#bg)", vgrad("bg", "#0b0f26", "#141a3c", 0.96, 0.97)
    gold_fill, gold_defs = "url(#bg)", vgrad("bg", "#5c4012", "#281a06", 0.96, 0.96)
    gold_hover, gold_hover_defs = "url(#bg)", vgrad("bg", "#74531a", "#33220a", 0.97, 0.97)
    gold_pressed, gold_pressed_defs = "url(#bg)", vgrad("bg", "#2a1b05", "#4a3310", 0.97, 0.97)
    dialog_defs = (
        '<radialGradient id="bg" cx=".5" cy="0" r="1.1"><stop offset="0" stop-color="#28305f" stop-opacity=".97"/>'
        '<stop offset=".7" stop-color="#0a0d22" stop-opacity=".98"/></radialGradient>'
    )
    return {
        # 面板：侧栏、选卡区、关卡牌
        "plate": plate(48, 6, fill, GOLD, 0.5, 0.15, defs=defs),
        # 按钮
        "button": plate(48, 4, fill, GOLD, 0.55, 0.15, defs=defs),
        "button_hover": plate(48, 4, hover_fill, GOLD, 0.85, 0.25, defs=hover_defs),
        "button_pressed": plate(48, 4, pressed_fill, GOLD, 0.7, 0.15, defs=pressed_defs),
        "button_disabled": plate(48, 4, fill, GOLD, 0.25, 0.08, defs=defs),
        "button_primary": plate(64, 4, gold_fill, GOLD, 1, 0.35, pad=8, defs=gold_defs, line_width=1.5, glow=GOLD),
        "button_primary_hover": plate(
            64, 4, gold_hover, "#fff0c4", 1, 0.45, pad=8, defs=gold_hover_defs, line_width=1.5, glow=GOLD
        ),
        "button_primary_pressed": plate(
            64, 4, gold_pressed, GOLD, 1, 0.3, pad=8, defs=gold_pressed_defs, line_width=1.5
        ),
        "button_primary_disabled": plate(64, 4, gold_fill, GOLD, 0.35, 0.1, pad=8, defs=gold_defs, line_width=1.5),
        # 输入框、下拉
        "input": plate(48, 4, "#04060f", GOLD, 0.4, 0.0, defs=""),
        "input_focus": plate(48, 4, "#04060f", GOLD, 0.85, 0.2, defs=""),
        # 对话框
        "dialog": plate(96, 8, "url(#bg)", GOLD, 1, 0.25, pad=16, defs=dialog_defs, line_width=1.5, glow=GOLD),
        # 勾选块
        "check_off": svg(
            22,
            22,
            '<rect x="1.75" y="1.75" width="18.5" height="18.5" rx="3" fill="none" stroke="#fff" stroke-opacity=".5" stroke-width="1.5"/>',
        ),
        "check_on": svg(
            22,
            22,
            f'<rect x="1" y="1" width="20" height="20" rx="3" fill="{GOLD}"/>'
            '<path d="M8.6 15.4 4.9 11.7l-1.4 1.4 5.1 5.1L18.6 8.2l-1.4-1.4z" fill="#231600"/>',
        ),
        # 开关
        "toggle_off": svg(
            68,
            38,
            '<rect x="2" y="2" width="64" height="34" rx="17" fill="#080b1c" stroke="#ffd98a" stroke-opacity=".5" stroke-width="1.5"/>'
            '<circle cx="19" cy="19" r="12" fill="#8a8f9e" stroke="#000" stroke-opacity=".6"/>',
        ),
        "toggle_on": svg(
            68,
            38,
            f'<rect x="2" y="2" width="64" height="34" rx="17" fill="url(#t)" stroke="{GOLD}" stroke-width="1.5"/>'
            '<circle cx="49" cy="19" r="12" fill="#ffe7a8" stroke="#000" stroke-opacity=".6"/>',
            vgrad("t", "#7a5516", "#3c2706"),
        ),
        # 菱形点缀（白色，用 modulate 上色）
        "diamond": svg(16, 16, '<path d="M8 1 15 8 8 15 1 8z" fill="#fff" stroke="#000" stroke-width="1"/>'),
    }


def card_textures() -> dict[str, str]:
    textures = {
        # 基础技能方块：白色渐变加暗边和顶部高光，用 modulate 上色
        "chip": svg(
            24,
            24,
            '<rect x=".5" y=".5" width="23" height="23" rx="3" fill="url(#c)" stroke="#000" stroke-opacity=".55"/>'
            '<path d="M3 2.2h18" stroke="#fff" stroke-opacity=".8" stroke-width="1.4" stroke-linecap="round"/>',
            '<linearGradient id="c" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/>'
            '<stop offset=".5" stop-color="#ececec"/><stop offset="1" stop-color="#c8c8c8"/></linearGradient>',
        ),
    }
    for tier, line in CARD_LINE.items():
        fill, defs = blue(alpha=1)
        textures[f"panel_{tier}"] = plate(24, 4, fill, line, 0.75, 0.22, defs=defs)
        bg = EQUIP_BG[tier]
        textures[f"equip_box_{tier}"] = svg(
            86,
            106,
            f'<rect x="1.5" y="1.5" width="83" height="103" rx="6" fill="url(#e)" stroke="{line}" stroke-width="1.5"/>'
            '<rect x="3" y="3" width="80" height="100" rx="5" fill="none" stroke="#000" stroke-opacity=".5"/>',
            f'<radialGradient id="e" cx=".5" cy=".42" r=".65"><stop offset="0" stop-color="{mix(bg, "#ffffff", 0.3)}"/>'
            f'<stop offset=".55" stop-color="{bg}"/><stop offset="1" stop-color="{mix(bg, "#000000", 0.6)}"/></radialGradient>',
        )
    return textures


def main() -> None:
    for folder, textures in (("theme", theme_textures()), ("card", card_textures())):
        out = REPO / "assets" / "ui" / folder
        for name, body in textures.items():
            # 装备框按原样缩放（不是九宫格），按 2 倍渲染，卡牌放大查看时也清楚
            svg_to_png(body, out / f"{name}.png", 2 if name.startswith("equip_box") else 1)
        print(f"{folder}：{len(textures)} 张贴图")


if __name__ == "__main__":
    main()
