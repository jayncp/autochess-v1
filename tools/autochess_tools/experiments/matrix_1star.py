"""复现 docs/design/card-design.md 第 3 节的 1★ 基准对局矩阵（同名卡 n 张对 n 张，无装备），并与文档逐格对比。

用法：just experiment matrix_1star
"""

from autochess_tools import data
from autochess_tools.sim import Result, simulate

CHARACTERS = ["soldier", "tiger", "sludge", "angel", "pixie"]
DOC = data.REPO / "docs" / "design" / "card-design.md"


def cell(result: Result) -> str:
    """P1 视角：胜(胜方剩余人数/总战力)、负(...)、平。"""
    if result.winner == 3:
        return "平"
    survivors = result.p1 if result.winner == 1 else result.p2
    return f"{'胜' if result.winner == 1 else '负'}({len(survivors)}/{sum(survivors)})"


def compute(n: int) -> dict[tuple[str, str], str]:
    pairs = [(a, b) for a in CHARACTERS for b in CHARACTERS]
    results = simulate([([[a, ""]] * n, [[b, ""]] * n) for a, b in pairs])
    return {pair: cell(r) for pair, r in zip(pairs, results, strict=True)}


def documented(n: int) -> dict[tuple[str, str], str]:
    """文档里 n 张对 n 张的表格；格子里的加粗去掉。"""
    text = DOC.read_text(encoding="utf-8").split(f"**n = {n}**", 1)[1]
    by_name = {data.name(c): c for c in CHARACTERS}
    table = {}
    for line in text.splitlines():
        cells = [c.strip().strip("*") for c in line.strip().strip("|").split("|")]
        if cells[0] in by_name:
            for b, value in zip(CHARACTERS, cells[1:], strict=True):
                table[by_name[cells[0]], b] = value
        elif table:
            break
    return table


def matches(documented_cell: str, computed_cell: str) -> bool:
    """文档里有的格子只写了胜负、没写数字，这时只比胜负。"""
    if "(" in documented_cell:
        return documented_cell == computed_cell
    return computed_cell.startswith(documented_cell)


def main() -> None:
    for n in (1, 2, 3):
        got = compute(n)
        doc = documented(n)
        print(f"\n**n = {n}**\n")
        print("| P1 \\ P2 | " + " | ".join(data.name(c) for c in CHARACTERS) + " |")
        print("|---" * (len(CHARACTERS) + 1) + "|")
        for a in CHARACTERS:
            print(f"| {data.name(a)} | " + " | ".join(got[a, b] for b in CHARACTERS) + " |")
        diffs = [
            f"{data.name(a)} 对 {data.name(b)}：文档 {doc[a, b]}，实测 {got[a, b]}"
            for a, b in got
            if not matches(doc[a, b], got[a, b])
        ]
        print("\n与 card-design.md 一致" if not diffs else "\n与 card-design.md 不同：\n" + "\n".join(diffs))


if __name__ == "__main__":
    main()
