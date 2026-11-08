"""字体子集化：把 Noto Sans SC、Noto Serif SC 裁到常用字，控制安装包大小。

- 字符：ASCII、GB2312 全部字符、几个常用符号，加上翻译表里出现的所有字；
- 黑体保留可变字重（正文 400，标签和数字 500–700）；宋体只用于卡名、标题、按钮，实例化成静态粗体，更重的字重在 Godot 里用加粗（embolden）。

源字体（Google Fonts 的可变字体）下载到 tools/.cache/fonts/，产物写到 assets/fonts/。
用法：just fonts
"""

import csv
import urllib.request
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

from autochess_tools.data import REPO

CACHE = REPO / "tools" / ".cache" / "fonts"
SOURCES = {
    "NotoSansSC[wght].ttf": "https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf",
    "NotoSerifSC[wght].ttf": "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf",
}
# 不在 GB2312 里、界面会用到的符号
EXTRA = "−×✓▸·…"


def source(name: str) -> Path:
    path = CACHE / name
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        print(f"下载 {name}")
        urllib.request.urlretrieve(SOURCES[name], path)
    return path


def charset() -> str:
    chars = {chr(c) for c in range(0x20, 0x7F)}
    for hi in range(0xA1, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                continue
    chars |= set(EXTRA)
    for table in (REPO / "i18n").glob("*.csv"):
        with table.open(encoding="utf-8") as f:
            for row in csv.reader(f):
                chars |= set("".join(row))
    return "".join(sorted(chars))


def subset_font(src: Path, text: str) -> TTFont:
    font = TTFont(src)
    options = subset.Options(layout_features=["*"], name_IDs=["*"], notdef_outline=True)
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    return font


def main() -> None:
    text = charset()
    out = REPO / "assets" / "fonts"
    sans = subset_font(source("NotoSansSC[wght].ttf"), text)
    sans.save(out / "NotoSansSC.ttf")
    serif = instancer.instantiateVariableFont(subset_font(source("NotoSerifSC[wght].ttf"), text), {"wght": 700})
    serif.save(out / "NotoSerifSC-Bold.ttf")
    for name in ["NotoSansSC.ttf", "NotoSerifSC-Bold.ttf"]:
        print(f"{name}: {(out / name).stat().st_size // 1024} KB，{len(text)} 个字符")


if __name__ == "__main__":
    main()
