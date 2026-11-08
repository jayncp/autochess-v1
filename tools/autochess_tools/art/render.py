"""SVG 渲染成 PNG（resvg，支持滤镜；Godot 自带的 SVG 导入不支持滤镜）。"""

from pathlib import Path

import resvg_py


def svg_to_png(svg: str, path: Path, zoom: float = 1.0) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(resvg_py.svg_to_bytes(svg_string=svg, zoom=zoom, skip_system_fonts=True)))
