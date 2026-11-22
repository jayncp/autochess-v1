"""数值试验：分阶段的阵容搜索，看每张卡的出场率和带卡得分。方法和用法见 tools/README.md。"""

from pathlib import Path

DATA = Path(__file__).resolve().parents[2] / "balance"
"""试验的数据目录 tools/balance/：候选数值 trial.json、文字对照表 overrides.json、起点阵容 pools/、各轮的结果 runs/"""
