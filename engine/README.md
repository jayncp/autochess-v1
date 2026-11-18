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
| `rust-toolchain.toml` | 固定 Rust 版本和组件，换机器时自动安装同一版 |
| `Cargo.lock` | 依赖的确切版本，提交进仓库 |

命令行（`cli/`）和 Python 绑定（`py/`）在后两批加入。

## 环境

1. 装 rustup：<https://rustup.rs>（macOS、Linux 都是一行命令），装好后重开终端。
2. 第一次运行 `just rs-test` 时，rustup 按 `rust-toolchain.toml` 自动安装指定版本，之后就不用管了。

## 命令

| 命令 | 作用 |
|---|---|
| `just rs-test` | Rust 的全部测试（含共用用例），几秒钟；`just test` 最后也会跑它 |
| `just rs-check` | 格式检查（`cargo fmt --check`）和静态检查（`cargo clippy`，警告当错误） |

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

正常数据下结果完全一致。只有 GDScript 版会出错的数据，两边才可能不同：

- **校验更严一点**：基础技能的数值写 null 时直接报错（`CardDB` 校验时放过，合并时才出错）；阵容里角色的位置放了装备、装备的位置放了角色，也报错。
- 获得词条时，已有的值是 null 而获得的是数值（比如给已经有致命的角色获得"致命 3"），GDScript 版会出错，这里把 null 当 0。正式数据里没有这种写法。
- 一方超过 7 个单位时报错（游戏里最多 7 个卡位）。

## 改规则的流程

1. 改 GDScript 版，`just record` 重录用例，逐条核对变化（见 [tests/README.md](../tests/README.md)）。
2. 规则或事件格式变了，`BattleSim.VERSION` 加一。
3. 照着改 Rust 版的同名函数，`VERSION` 跟着改，`just rs-test` 通过。
