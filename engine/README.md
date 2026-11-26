# Rust 版结算

只算结果的高速战斗结算，供批量模拟用（强度测试、阵容搜索）。计划见 [docs/plans/rust-engine.md](../docs/plans/rust-engine.md)。

- **GDScript 版是规则的基准实现**（`scripts/core/battle_sim.gd`、`scripts/core/card_db.gd`），游戏只用它；Rust 版不接进 Godot。
- **只算结果**：胜负、原因、双方幸存角色的战斗力，不产生回放用的事件日志。
- 和 GDScript 版用同一份卡牌数据（`data/cards.json`）和同一份用例（`tests/cases/`），要求逐场一致。

## 结构

Cargo 工作区，目录里有 `.gdignore`，Godot 不扫描它。

| 位置 | 内容 |
|---|---|
| `core/`（crate `autochess-core`） | 纯逻辑库：读卡牌数据、装备合并、战斗结算 |
| `core/src/ids.rs` | 各种 id（时机、基础技能、特殊技能、范围、对象……）和它们的顺序，对应 `CardDB` 开头的常量 |
| `core/src/cards.rs` | 读取和校验卡牌数据、按 id 查询、装备合并，对应 `CardDB` |
| `core/src/battle.rs` | 战斗结算，对应 `BattleSim` |
| `core/tests/cases.rs` | 共用用例：`tests/cases/` 的规则用例和冒烟用例，都检查交换左右后对称；`VERSION` 和 `BattleSim.VERSION` 一致 |
| `cli/`（crate `autochess-cli`，程序 `engine-cli`） | 批量模拟的命令行，输入输出同 `cli/sim.gd`，多核并行 |
| `py/`（crate `autochess-py`，Python 模块 `autochess_engine`） | Python 绑定（PyO3），`tools/` 通过它批量模拟；`pyproject.toml` 是 maturin 的配置，`autochess_engine.pyi` 是给类型检查看的接口说明；`src/search.rs` 是数值试验用的阵容搜索（爬山，多核） |
| `rust-toolchain.toml` | 固定 Rust 版本和组件，换机器时自动安装同一版 |
| `rustfmt.toml` | 排版：行宽 120 |
| `Cargo.lock` | 依赖的确切版本，提交进仓库 |

依赖：`serde_json`（读 JSON）、`rayon`（多核并行）、`pyo3` 和 `numpy`（Python 绑定）。
`cargo build`、`cargo test` 不写 `-p` 时只管 `core` 和 `cli`；`py` 由 maturin 构建（见下）。

## 环境

1. 装 rustup：<https://rustup.rs>（macOS、Linux 都是一行命令），装好后重开终端。
2. 第一次运行 `just rs-test` 时，rustup 按 `rust-toolchain.toml` 自动安装指定版本，之后就不用管了。
3. Python 绑定不用另外装什么：`tools/` 的 uv 环境把它当作本地路径依赖，第一次运行 `just tools-check`、`just experiment` 等命令时用 maturin 编译（约 1 分钟），之后 Rust 源码变了才重新编译。

macOS（Apple 芯片）和 Linux（x86-64）都能构建、通过测试，不写平台相关的代码。

## 命令

| 命令 | 作用 |
|---|---|
| `just rs-test` | Rust 的全部测试（含共用用例），几秒钟；`just test` 最后也会跑它 |
| `just rs-check` | 格式检查（`cargo fmt --check`）和静态检查（`cargo clippy`，警告当错误） |
| `just rs-build` | 发布构建命令行 `target/release/engine-cli`，并更新 `tools/` 里的 Python 绑定；下面几条会自动先做 |
| `just sim <输入> <输出> [--cards <文件>] [--trace] [--threads N]` | 批量模拟，格式见下 |
| `just diff-sim [场数] [--seed N]` | 和 Godot 版对拍，默认 100 万场，约 45 秒 |
| `just bench` | 测速：固定的一批对局，Godot 版、命令行、从 Python 调用的场/秒 |

## 批量模拟（`engine-cli`）

输入输出和 `cli/sim.gd` 一样，是 JSONL：

- 输入每行一场 `{"p1": [[角色 id, 装备 id], ...], "p2": [...]}`，可带 `"id"`（原样写回）；
- 输出每行一个结果 `{"id", "winner", "reason", "p1", "p2"}`，顺序和输入一致：`winner` 1/2 = 该方胜、3 = 平局，`reason` 是 `wipe`（全灭）或 `no_death`（连续 20 次交战无人阵亡），`p1`、`p2` 是双方幸存角色的战斗力；
- `--cards <文件>`：额外的卡牌（格式同 `data/cards.json`），同 id 覆盖原卡，只在本次有效；
- `--trace`：每个结果带简要轨迹 `"trace": [[步骤, [P1 战斗力...], [P2 战斗力...]], ...]`，每一步（`pre_battle` / `enter` / `engage`）判死之后记一条。Godot 版的 `--trace` 由事件日志算出同样的东西，对拍时用来找第一处不同；
- `--threads N`：线程数，默认用全部核心。

结束时打印场数、结算用时和场/秒（只算结算本身，不含读写）。12 核的 Mac 上单线程约 57 万场/秒，12 线程约 500 万场/秒；Godot 版单进程约 4300 场/秒（随机 1–7 人的对局）。

## 对拍（`just diff-sim`）

`tools/autochess_tools/diff_sim.py`：用固定种子生成一批随机对局（`lineups.py`：每方 1–7 人、各星级的正式卡、允许同名卡，一半是机制密集的阵容），
分别用 Godot 版（多进程）和 Rust 版跑，逐场比较胜负、原因、幸存者的战斗力。不一致时列出前几场的阵容和两边的结果，
再用 `--trace` 跑一遍，指出第一处不同的步骤和那一步双方的战斗力。有不一致时以非 0 退出。

发现不一致，先看是哪一边的问题：是 GDScript 版的 bug 就报告，先定规则再改，并补成规则用例。

## Python 绑定（`autochess_engine`）

平衡实验一般用 `tools/autochess_tools/sim.py` 的 `simulate(对局列表, extra_cards)`，默认就走 Rust 版。直接用绑定：

```python
from autochess_tools.sim import engine

rust = engine()  # 读入 data/cards.json；engine(extra_cards) 加额外卡牌
rust.simulate([([["tiger_man", ""]], [["vulture", "iron_sword"]])])  # [(2, 'wipe', [], [8])]
```

- `simulate(对局列表, threads=0)`：字符串 id，返回 `[(winner, reason, P1 幸存者的战斗力, P2 幸存者的战斗力), ...]`。
- `simulate_ids(p1, p2, threads=0)`：按编号传 numpy 数组，形状 `(场数, 位置数 ≤7, 2)`，每格 `[角色编号, 装备编号]`，`-1` 表示空位、不带装备；编号见 `ids()`、`index(id)`。
  返回 `winner`、`reason`（0 = 全灭、1 = 连续无人阵亡）和双方幸存者的战斗力（`(场数, 7)`，后面补 0）四个数组。大批量时用它：省掉 Python 字符串的转换，快 5 倍以上。
- `cross(mine, theirs)`：两批阵容（编号数组）两两对战的得分矩阵，胜 1、平 0.5、负 0。
- `climb(...)`：数值试验的爬山（`tools/autochess_tools/balance/meta.py` 的 `Meta.climb` 调它，参数见 `autochess_engine.pyi`）：每个起点反复试几个变异，对一批带权重的对手得分不降就换过去。给了 `gold` 就按金币约束（期望花费不超过预算，觉醒的角色按 3 张原卡算；`balance/gold.py` 用）。
- `Prices(...)`：经济系统的期望花费（动态规划，和 `tools/autochess_tools/economy/model.py` 的 `Plan.cost` 一致），`costs(阵容要的卡)` 一次算一批。
- 结算时释放 GIL、多核并行，结果顺序和输入一致；`threads` 为 0 时用全部核心。阵容或卡牌数据有误时报 `ValueError`。

速度（`just bench`，12 核 Mac，30 万场随机对局）：

| 调用方式 | 单线程 | 12 线程 |
|---|---:|---:|
| 命令行 `engine-cli`（只算结算） | 约 57 万场/秒 | 约 500 万 |
| Python `simulate`（字符串 id，含转换） | 约 34 万 | 约 75 万（转换要持有 GIL，是瓶颈） |
| Python `simulate_ids`（编号数组） | 约 53 万 | 约 420 万 |

Godot 版单进程约 4300 场/秒。

在 `engine/` 里也可以直接用 cargo：`cargo test`、`cargo fmt`（自动排版）、`cargo clippy --all-targets`。

## 怎么对照 GDScript 版读代码

`battle.rs` 的结构照抄 `battle_sim.gd`：同样的流程，同样的函数名（去掉开头的下划线，如 `_on_trigger` → `on_trigger`），
每个函数的注释末尾写着对应的 GDScript 函数。名字不同的只有这几处：

| GDScript | Rust | 说明 |
|---|---|---|
| `BattleSim.new(p1, p2)` | `Battle::new(&deck, &p1, &p2)` | 卡牌数据作为参数传进来 |
| `_record`、`_records` | `Records` | 一个单位这一轮"记"下的场面，只在 `special_steps` 里用 |
| `_holders` | `holders`（`Holders`） | 同样只在开战和这一方有人阵亡时重建 |
| `CardDB.combine`、`combine_data` | `Deck::combine` | 只算战斗用的数，卡面上印的数（`printed`）是界面的事 |
| `CardDB._load`、`add_cards` | `Deck::from_file`、`add_file`、`add_json` | |
| `CardDB._normalize`、`_check`、`_check_params` | `parse_card`、`parse_params` | 读的同时校验 |

数据表示的不同（只影响写法，不影响结果）：

- 单位放在一个定长数组里，用下标（`UnitId`）指代；队列、持有者、一组单位都是下标的定长列表（`Line`，最多 7 个）。一场战斗不分配堆内存。
- 技能、时机这些 id 是枚举；基础技能和特殊技能是按 id 排的定长数组（`BaseSkills`、`Specials`），"有没有"就是这一格有没有值。
- 双方用 0、1 表示（GDScript 是 1、2）；胜负的取值不变：1/2 = 该方胜，3 = 平局。
- 只为事件日志服务的部分（uid、效果来自哪个单位、多一轮多一次来自哪个持有者）省略，只留下数量。

## 和 GDScript 版不同的地方

卡牌数据的校验和 `CardDB.problems` 完全一致（共用 `tests/cases/card_checks.json`，规则见 [data/README.md](../data/README.md)），结算结果逐场一致。
为卡牌觉醒加的两样东西只有 Rust 版认，GDScript 版还没有（正式数据里也没有用到，所以对拍不受影响；见 [docs/design/awakening.md](../docs/design/awakening.md)）：多结算、多触发、额外获得可以多写一个次数 `times`；对象多了 `next_four`（下四位）、`enemy_first_four`（对方前四位）。在游戏里实现觉醒时要按下面的流程补到 GDScript 版。
阵容的检查更严：角色的位置放了装备、装备的位置放了角色，或者一方超过 7 个单位（游戏里最多 7 个卡位），都直接报错。

## 改规则的流程

1. 改 GDScript 版，`just record` 重录用例，逐条核对变化（见 [tests/README.md](../tests/README.md)）。
2. 规则或事件格式变了，`BattleSim.VERSION` 加一。
3. 照着改 Rust 版的同名函数，`VERSION` 跟着改，`just rs-test` 通过。
4. `just diff-sim`：零差异。
