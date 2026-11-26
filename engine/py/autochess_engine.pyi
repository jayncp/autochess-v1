"""牛马自走棋的 Rust 版结算（Python 绑定），和 scripts/core/battle_sim.gd 逐场一致。说明见 engine/README.md。"""

from collections.abc import Sequence

import numpy as np
import numpy.typing as npt

type Lineup = Sequence[Sequence[str]]
"""阵容：[[角色 id, 装备 id], ...]，装备为空字符串表示不带"""

VERSION: int
"""和 BattleSim.VERSION 相同"""

class Engine:
    """结算引擎：创建时读入卡牌，之后只读。"""

    def __init__(self, cards: str, extra_cards: str | None = None) -> None:
        """cards：卡牌文件（通常是 data/cards.json）；extra_cards：额外卡牌的 JSON 文本（数组，同 id 覆盖原卡）。"""

    def ids(self) -> list[str]:
        """全部卡牌的 id，下标就是 simulate_ids 用的编号。"""

    def index(self, id: str) -> int:
        """一张卡的编号。"""

    def simulate(
        self, battles: Sequence[tuple[Lineup, Lineup]], threads: int = 0
    ) -> list[tuple[int, str, list[int], list[int]]]:
        """一批对局 [(p1, p2), ...]，阵容是 [[角色 id, 装备 id], ...]；
        返回 [(winner, reason, p1 幸存者的战斗力, p2 幸存者的战斗力), ...]。threads 为 0 时用全部核心。"""

    def simulate_ids(
        self, p1: npt.NDArray[np.int32], p2: npt.NDArray[np.int32], threads: int = 0
    ) -> tuple[npt.NDArray[np.uint8], npt.NDArray[np.uint8], npt.NDArray[np.int32], npt.NDArray[np.int32]]:
        """按编号传阵容：int32 数组，形状 (场数, 位置数 ≤7, 2)，每格 [角色编号, 装备编号]，-1 表示空。
        返回 (winner, reason, p1, p2)：reason 0 = 全灭、1 = 连续无人阵亡；p1、p2 是 (场数, 7) 的幸存者战斗力，后面补 0。"""

    def cross(self, mine: npt.NDArray[np.int32], theirs: npt.NDArray[np.int32]) -> npt.NDArray[np.float64]:
        """得分矩阵（试验）：mine 里每套对 theirs 里每套，胜 1、平 0.5、负 0。阵容数组的格式同 simulate_ids。"""

    def climb(
        self,
        starts: npt.NDArray[np.int32],
        keeps: list[int],
        opponents: npt.NDArray[np.int32],
        weights: list[float],
        steps: int,
        mutations: int,
        seed: int,
        chars: list[int],
        equips: list[int],
        star: list[int],
        limit: list[int],
        options: list[tuple[int, int]],
        max_equips: int,
        gold: tuple[Prices, float, list[int], list[int]] | None = None,
    ) -> tuple[npt.NDArray[np.int32], npt.NDArray[np.float64]]:
        """并行爬山（试验）：返回（各起点最后的阵容，一维、每套 7×2 格、空位 -1；各起点的得分）。
        gold 给了就按金币约束（limit、options、max_equips 不用）：（经济系统, 预算, 各卡的原卡编号, 角色的另一个形态或 -1）。"""

class Prices:
    """经济系统（试验）：凑齐一套阵容的期望花费，和 autochess_tools.economy.model.Plan 的口径相同。"""

    def __init__(
        self,
        odds: Sequence[Sequence[float]],
        slots: Sequence[int],
        xp: Sequence[float],
        kinds: Sequence[Sequence[float]],
        copies: Sequence[Sequence[float]],
        shop: Sequence[int],
        refresh: float,
    ) -> None:
        """odds[等级-1][星级-1]；slots 各等级的卡位；xp 升到下一级的经验；kinds、copies 是 [角色, 装备] 各星级的种类数、张数；
        shop 是商店里 [角色格, 装备格] 的个数。"""

    def costs(self, lineups: Sequence[tuple[Sequence[tuple[int, int, int]], int]]) -> list[float]:
        """一批阵容的期望花费（含买卡）。每套是（要的卡 [(类型 0 角色 / 1 装备, 星级, 张数), ...]，上阵人数）；凑不齐是 inf。"""

    def cached(self) -> int:
        """记住了多少种算过的结果。"""
