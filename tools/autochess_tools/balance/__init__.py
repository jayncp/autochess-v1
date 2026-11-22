"""数值试验：分阶段的阵容搜索，看每张卡的出场率和带卡得分。方法和用法见 tools/README.md。

试验用的规则开关（engine/core/src/trial.rs）在导入这个包时全部打开；
想按正式规则搜索，先设环境变量 AUTOCHESS_OFFICIAL_RULES=1。
"""

import os
from pathlib import Path

DATA = Path(__file__).resolve().parents[2] / "balance"
"""试验的数据目录 tools/balance/：候选数值 trial.json、文字对照表 overrides.json、起点阵容 pools/、各轮的结果 runs/"""

SWITCHES = (
    "AUTOCHESS_RAISE_PER_TRIGGER",
    "AUTOCHESS_FULL_SKILL_SUM",
    "AUTOCHESS_TRIPLE_EQUIPMENT",
    "AUTOCHESS_COPY_ADD",
    "AUTOCHESS_BOX_STRENGTH",
    "AUTOCHESS_ANY_PER_RESOLVE",
)

# 引擎在第一次用到时读这些环境变量，所以要赶在创建引擎之前设好
if not os.environ.get("AUTOCHESS_OFFICIAL_RULES"):
    for name in SWITCHES:
        os.environ.setdefault(name, "1")
