"""图标：种族、时机，以及界面用的几个通用图标。48 网格的实心剪影，颜色用 currentColor。

导出 PNG 到 assets/ui/icons/：
- <id>.png：白色剪影，在 Godot 里用 modulate 上色；
- <id>_outline.png：白色剪影加黑色描边，直接压在卡图上用（同样用 modulate 上色，描边保持黑色），只有种族和时机图标有；
- 下拉箭头不单独导出，ui.py 用它生成主题里的箭头。

用法：just art
"""

from autochess_tools.art.render import svg_to_png
from autochess_tools.data import REPO

SWORD = (
    '<path d="M20.6 7.5 24-1.5l3.4 9V33h-6.8z"/><rect x="12.5" y="32" width="23" height="6" rx="2"/>'
    '<rect x="21.6" y="37.5" width="4.8" height="8" rx="1.2"/><circle cx="24" cy="47.6" r="3.4"/>'
)

ICONS = {
    # 人族：燕尾旗
    "human": '<circle cx="11" cy="5.5" r="3.2"/><rect x="9.4" y="7" width="3.2" height="37" rx="1.2"/>'
    '<path d="M12.6 9.5c6-2.6 11.6 2.2 17.6.2 3.4-1.1 6.4-2.2 9.6-1.4l-5.6 8.2 5.6 8.6c-3.6-.6-6.8.6-10.2 1.6'
    '-6 1.8-11.2-2.6-17 0z"/>',
    # 动物：带爪的兽掌
    "beast": '<path d="M24 25.5c6.6 0 13 7.2 12.3 12.6-.6 4.6-5.3 5.4-8.6 4.4-1.4-.4-2.4-.8-3.7-.8s-2.3.4-3.7.8'
    'c-3.3 1-8-.2-8.6-4.4C11 32.7 17.4 25.5 24 25.5z"/>'
    '<ellipse cx="10.5" cy="22" rx="4.2" ry="5.4" transform="rotate(-24 10.5 22)"/>'
    '<ellipse cx="18.6" cy="14.6" rx="4.3" ry="5.8" transform="rotate(-8 18.6 14.6)"/>'
    '<ellipse cx="29.4" cy="14.6" rx="4.3" ry="5.8" transform="rotate(8 29.4 14.6)"/>'
    '<ellipse cx="37.5" cy="22" rx="4.2" ry="5.4" transform="rotate(24 37.5 22)"/>'
    '<path d="M6.2 16.2 4.6 9.4l5 4.6zM15.6 8.6l1.2-7 2.8 6.6zM32.4 8.6l-1.2-7-2.8 6.6zM41.8 16.2l1.6-6.8-5 4.6z"/>',
    # 神族：一对翅膀加光环
    "divine": '<path fill="none" stroke="currentColor" stroke-width="3" d="M15.5 8.5c0-2.4 3.8-4 8.5-4s8.5 1.6 8.5 4'
    '-3.8 4-8.5 4-8.5-1.6-8.5-4z"/>'
    '<path d="M22 21.5C18 15 9.6 12.6 2.5 15.8c3.2.8 5 2.2 6 3.8-3.6-.2-6 1-7.3 3.4 3.2-.4 5.6 0 7.6 1.4-2.8.8'
    '-4.6 2.6-5.2 5.2 3-1.4 6-1.6 8.8-.8-1.6 1.4-2.4 3.4-2.2 6 3.4-3 8.6-5.8 13.8-6.6z"/>'
    '<path d="M26 21.5C30 15 38.4 12.6 45.5 15.8c-3.2.8-5 2.2-6 3.8 3.6-.2 6 1 7.3 3.4-3.2-.4-5.6 0-7.6 1.4 2.8.8'
    ' 4.6 2.6 5.2 5.2-3-1.4-6-1.6-8.8-.8 1.6 1.4 2.4 3.4 2.2 6-3.4-3-8.6-5.8-13.8-6.6z"/>',
    # 精灵：蝴蝶翅膀
    "elf": '<path d="M22.4 22.6C19.6 12.4 11 5 5.2 7.4 1.6 9 2 15.2 5.4 19.2c3 3.4 9.4 4.8 17 3.4z"/>'
    '<path d="M22.6 25.4c-7.4-.6-13.2 2.6-14.4 7.6-1 4.4 2.4 8.6 6.8 7.4 4.6-1.2 7.6-8 7.6-15z"/>'
    '<path d="M25.6 22.6C28.4 12.4 37 5 42.8 7.4c3.6 1.6 3.2 7.8-.2 11.8-3 3.4-9.4 4.8-17 3.4z"/>'
    '<path d="M25.4 25.4c7.4-.6 13.2 2.6 14.4 7.6 1 4.4-2.4 8.6-6.8 7.4-4.6-1.2-7.6-8-7.6-15z"/>'
    '<rect x="22.6" y="16" width="2.8" height="22" rx="1.4"/>'
    '<path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"'
    ' d="M23.4 16.6c-.8-4-2.6-6.6-5-8M24.6 16.6c.8-4 2.6-6.6 5-8"/>',
    # 自然：叶子
    "nature": '<path fill-rule="evenodd" d="M7.5 41C5.8 24.6 17.6 8.6 42.5 5.5 42.8 30 28.4 42.6 7.5 41zm3.4-2.6'
    'c6.4-8.8 14-16.4 24-23.4l-1.6-1.8C23.2 20 15.6 27.8 9.2 36.6z"/>',
    # 财宝：钱币（外圈、内环、镂空星纹）
    "treasure": '<path fill-rule="evenodd" d="M24 3a21 21 0 1 1 0 42 21 21 0 0 1 0-42zm0 4.4a16.6 16.6 0 1 0 0 33.2'
    " 16.6 16.6 0 0 0 0-33.2zm0 2.6a14 14 0 1 1 0 28 14 14 0 0 1 0-28zM24 13.2l-3.3 7-7.6.8 5.7 5.2-1.6 7.5"
    ' 6.8-3.9 6.8 3.9-1.6-7.5 5.7-5.2-7.6-.8z"/>',
    # 战前：沙漏
    "pre_battle": '<path d="M9 3h30v4.4h-3.2c0 7.6-5.2 12.2-8.6 16.6 3.4 4.4 8.6 9 8.6 16.6H39V45H9v-4.4h3.2'
    'c0-7.6 5.2-12.2 8.6-16.6-3.4-4.4-8.6-9-8.6-16.6H9z"/>'
    '<path fill="#000" fill-opacity=".45" d="M16.4 7.4h15.2c-.2 3.2-1.6 5.8-3.4 8.2h-8.4c-1.8-2.4-3.2-5-3.4-8.2z'
    'M24 30.4c2.6 2.6 6.4 6 7 10.2H17c.6-4.2 4.4-7.6 7-10.2z"/>',
    # 入场：箭头进入门框
    "on_enter": '<path d="M24 4h17a3 3 0 0 1 3 3v34a3 3 0 0 1-3 3H24v-5h15V9H24z"/><path d="M3 21h18v-8l13 11-13 11v-8H3z"/>',
    # 交战：交叉双剑
    "on_engage": f'<g transform="translate(24 24) scale(.9) translate(-24 -24) rotate(45 24 24)">{SWORD}</g>'
    f'<g transform="translate(24 24) scale(.9) translate(-24 -24) rotate(-45 24 24)">{SWORD}</g>',
    # 通用：返回、锁、搜索、跳过、对号、下拉箭头
    "back": '<path d="M31 6 13 24l18 18 4-4-14-14 14-14z"/>',
    "lock": '<path fill-rule="evenodd" d="M14 20v-6a10 10 0 0 1 20 0v6h3a3 3 0 0 1 3 3v18a3 3 0 0 1-3 3H11a3 3 0 0 1'
    '-3-3V23a3 3 0 0 1 3-3zm5 0h10v-6a5 5 0 0 0-10 0z"/>',
    "search": '<path fill-rule="evenodd" d="M20 4a16 16 0 0 1 12.6 25.8l10.8 10.8-2.8 2.8-10.8-10.8A16 16 0 1 1 20 4z'
    'm0 4a12 12 0 1 0 0 24 12 12 0 0 0 0-24z"/>',
    "skip": '<path d="M6 10l16 14-16 14zM24 10l16 14-16 14zM40 10h4v28h-4z"/>',
    "check": '<path d="M18 32.4 9.6 24l-2.8 2.8L18 38 42 14l-2.8-2.8z"/>',
    "chevron_down": '<path d="M10 16l14 14 14-14 3.5 3.5L24 37 6.5 19.5z"/>',
}
## 压在卡图上的图标（种族、时机），要导出描边版
OUTLINED = ["human", "beast", "divine", "elf", "nature", "treasure", "pre_battle", "on_enter", "on_engage"]
## 只给 ui.py 当素材用，不导出
SOURCE_ONLY = ["chevron_down"]

SIZE = 96  # 导出尺寸：48 网格放大 2 倍
PAD = 4  # 描边版四周留的空（网格单位）


def svg(body: str, outline: bool) -> str:
    if not outline:
        return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" color="#fff" fill="#fff">{body}</svg>'
    view = f"{-PAD} {-PAD} {48 + 2 * PAD} {48 + 2 * PAD}"
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}">'
        '<defs><filter id="o" x="-20%" y="-20%" width="140%" height="140%">'
        '<feMorphology operator="dilate" radius="2.4"/></filter></defs>'
        f'<g filter="url(#o)" color="#000" fill="#000">{body}</g>'
        f'<g color="#fff" fill="#fff">{body}</g></svg>'
    )


def main() -> None:
    out = REPO / "assets" / "ui" / "icons"
    for name, body in ICONS.items():
        if name in SOURCE_ONLY:
            continue
        svg_to_png(svg(body, False), out / f"{name}.png", zoom=SIZE / 48)
        if name in OUTLINED:
            svg_to_png(svg(body, True), out / f"{name}_outline.png", zoom=SIZE / 48)
    print(f"图标：{len(ICONS) - len(SOURCE_ONLY)} 个，写到 {out.relative_to(REPO)}")


if __name__ == "__main__":
    main()
