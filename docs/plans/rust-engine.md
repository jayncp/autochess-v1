# Rust 版结算

> **状态**：进行中（issue #30）。第 1 批开发完成，待审；执行记录见第 7 节。
> **依据**：规则以 [battle-rules.md](../design/battle-rules.md) 为准；基准实现是 `scripts/core/battle_sim.gd`（结算）和 `scripts/core/card_db.gd`（装备合并）；用例在 `tests/cases/`（说明见 [tests/README.md](../../tests/README.md)）。
> 用户不熟悉 Rust：代码要好读、好对照，每个 PR 的说明里写清楚怎么验证。规则或基准实现有不清楚的地方，先问用户。

## 1. 目标和范围

- 做一个只算结果的高速结算，供批量模拟用：强度测试、阵容搜索、以后的训练。
- **游戏本体不变**：GDScript 版仍然是规则的基准实现，Rust 版不接进 Godot。
- **只算结果**：胜负、原因、双方幸存角色的战斗力。不产生回放用的事件日志；另有一个可选的简要轨迹，只用于定位两边的差异（3.3）。
- **只做战斗结算**。局内的买卡、升级、经济还没有设计，不做。
- 验收的核心是**和 GDScript 版逐场一致**，其次才是速度。

## 2. 结构

### 2.1 目录

仓库里新建 `engine/`（放一个 `.gdignore`，Godot 不扫描它），是一个 Cargo 工作区：

| crate | 内容 |
|---|---|
| `core` | 纯逻辑库：读卡牌数据、装备合并、战斗结算。不依赖 Python，不做文件以外的 IO |
| `cli` | 命令行：和 `cli/sim.gd` 相同的输入输出（JSONL，`--cards <额外卡牌>`），多核并行，结束时打印场数和速度 |
| `py` | Python 绑定（PyO3 + maturin），供 `tools/` 调用 |

crate 的名字、是否再拆，实现时可以调整；`core` 不依赖另外两个这一点不变。

### 2.2 写法

- **结构照抄 GDScript 版**：同样的流程和函数名（`pre_battle_phase`、`entering_step`、`engage_step`、`resolve_timing`、`special_steps`、`resolve_beats`、`apply_skill`、`damage`、`settle_death` 等），注释里标出对应的 GDScript 函数。以后改规则可以逐函数对照。
- **只换数据表示**：技能和时机用枚举和定长数组，队列最多 7 个角色用定长容器，特殊技能的效果用枚举加 `match`；一场战斗的结算过程里不分配堆内存。
- **卡牌预处理**：加载时把 `data/cards.json` 解析成紧凑的结构；（角色，装备）合并的结果可以缓存。合并规则（格子模型、千机之匣和千机魔女的翻倍）照 `CardDB.combine_data`。
- **数据加载的校验**和 `CardDB` 一致：不认识的字段、技能、效果 id 直接报错，不静默跳过。这样正式数据加了新效果而 Rust 没跟上时，会立刻失败。
- **不用 `unsafe`**；依赖尽量少（JSON 解析、并行、Python 绑定、命令行参数各一个常用库）。
- 容易不一致的地方，实现时逐条对照并各有用例：
  - 四舍五入：GDScript 的 `roundi` 是 0.5 远离零（炼药师、沼泽之王）；
  - 同一步、同一拍里的遍历顺序，被动持有者的顺序；
  - 致命的 10000 和坚固、庇护的先后；
  - 战斗力 ≤0 还没判死的角色照常参与；
  - 平局计数（连续 20 次交战无人阵亡）什么时候清零。

### 2.3 接口

**命令行**（`just sim` 以后默认走它，Godot 版改名保留）：

```
engine-cli <输入.jsonl> <输出.jsonl> [--cards <额外卡牌.json>] [--trace] [--threads N]
```

输入输出和 `cli/sim.gd` 一样：每行 `{"p1": [[角色 id, 装备 id], ...], "p2": [...]}`，可带 `id`；输出每行 `{"id", "winner", "p1", "p2"}`，另加 `reason`。输出顺序和输入一致。

**Python**：

- 一个引擎对象，创建时加载卡牌（可以追加额外卡牌，对应现在的 `extra_cards`）。
- `simulate(battles)`：一批对局进、一批结果出，内部释放 GIL、多核并行，顺序和输入一致。
- `tools/autochess_tools/sim.py` 的 `simulate()` 签名不变，默认后端换成 Rust；Godot 后端保留为一个参数，只用于对拍。现有的实验（`effective_strength` 等）不用改就能跑。
- 大批量时用字符串 id 传参会成为瓶颈：另外提供按整数编号传阵容的接口（numpy 数组进、数组出），第 3 批做。

## 3. 怎么保证和 GDScript 版一致

### 3.1 共用用例

- Rust 的测试直接读 `tests/cases/battles.json`、`tests/cases/cards.json`（规则用例，完整期望值）和 `tests/cases/smoke.json`（正式卡；有 `expect` 的检查胜负）。
- 每条都做镜像检查（交换左右，结果对称）。
- 不在 Rust 这边另存一份期望值。

### 3.2 随机对拍

- 一个生成器（Python，固定种子）：随机阵容，1–7 人，各星级的正式卡，带装备的比例可调，允许同名卡。也生成一批"机制密集"的阵容：只从带描述型特殊技能和多一轮的卡里抽，让少见的组合出现得多。
- `just diff-sim [场数]`：同一批对局分别用 Godot 和 Rust 跑，逐场比较胜负、原因、幸存者的战斗力；不一致时打印阵容，并用 `--trace` 找出第一处不同。
- 验收时跑 100 万场以上，零差异。发现的差异如果是 GDScript 版的 bug，报告用户，先定规则再改，并补成规则用例。

### 3.3 简要轨迹

- `--trace` 时每次判死后记一行：时点的类型，双方每个角色的战斗力。
- GDScript 这边用现有的事件日志算出同样的东西（写一个小转换，不改 `BattleSim`）。
- 只用于对拍定位，不追求速度。

### 3.4 版本和流程

- Rust 里有同名的 `VERSION`，测试检查它等于 `BattleSim.VERSION`。
- 以后改规则的顺序：改 GDScript → `just record` 重录用例 → 改 Rust → `just rs-test` → `just diff-sim`。这条写进 `AGENTS.md` 的约定。

## 4. 环境和规范

- 工具链用 rustup 管理；`engine/rust-toolchain.toml` 固定稳定版的具体版本号和组件（rustfmt、clippy），换机器自动装同一版。版本号用开工时最新的稳定版，edition 用当时最新的。
- `Cargo.lock` 提交进仓库；`engine/target/` 加进 `.gitignore`。
- 格式化 `cargo fmt`；静态检查 `cargo clippy`，警告一律当错误；工作区的 `Cargo.toml` 里用 `[workspace.lints]` 统一配置。
- 发布构建打开 LTO，`codegen-units = 1`。
- Python 绑定用 maturin 作为构建后端，在 `tools/pyproject.toml` 里作为本地路径依赖，`uv sync` 时自动编译；不要求手动装 maturin。
- 开发在 macOS（Apple 芯片），大规模测试在 Linux（x86-64）。两边都要能构建和通过测试；不写平台相关的代码。Linux 上 Godot 的路径用环境变量 `GODOT`。
- `justfile` 新增：

| 命令 | 作用 |
|---|---|
| `just rs-check` | `cargo fmt --check` 和 `cargo clippy` |
| `just rs-test` | Rust 的测试（含共用用例） |
| `just rs-build` | 发布构建命令行和 Python 绑定 |
| `just diff-sim [场数]` | 随机对拍 |
| `just bench` | 固定的一批对局测速度，打印场/秒 |

- `just test` 加上 `rs-test`；`just tools-check` 照旧。没装 Rust 的机器上 `just test` 要给出清楚的提示，不是一串看不懂的报错。
- 文档：`engine/README.md`（结构、怎么构建、怎么对拍、和 GDScript 函数的对应表），并同步 `AGENTS.md`、`tools/README.md`、`tests/README.md`、`docs/decisions.md`。

## 5. 分批

一个 issue，三个 PR。每个 PR 开之前先给用户审，说明里写清楚用户自己怎么验证（跑哪条命令、应该看到什么）。

### 第 1 批：核心库和用例

- 工作区、工具链、检查命令；`core`：卡牌加载和校验、装备合并、完整结算。
- 共用用例全部通过（3.1），`VERSION` 检查。
- **验收**：`just rs-check`、`just rs-test` 通过；`just test` 仍然通过。

### 第 2 批：命令行和对拍

- `cli`、简要轨迹、对拍生成器和 `just diff-sim`、`just bench`。
- **验收**：100 万场随机对拍零差异（普通阵容和机制密集阵容各一半）；PR 里报告单线程和多线程的场/秒，以及和 Godot 版的对比。速度的目标是单线程比 Godot 版（约 6600 场/秒）快 50 倍以上；达不到时报告瓶颈在哪，不为了速度牺牲和 GDScript 版的对照关系。

### 第 3 批：Python 绑定

- `py`、`sim.py` 换后端、按编号传参的批量接口。
- **验收**：`just tools-check` 通过；`just experiment effective_strength` 用两个后端跑，结果一致；PR 里报告从 Python 调用时的场/秒，在 macOS 和 Linux 上都构建通过。

## 6. 之后的事（不在这次范围）

- 强度测试方案和数值迭代（方向见 [stage-3-high-stars.md](stage-3-high-stars.md) 第 8 节）。
- 训练环境（局内构筑的状态和动作），等局外规则设计之后。
- 重新启用 CI 时，把 Rust 的检查和对拍加进去。

## 7. 执行记录

### 第 1 批：核心库和用例（分支 `rust-engine-1`）

- **环境**：Rust 1.100.0（开工时最新的稳定版），edition 2024；依赖只有 `serde_json`。`rustfmt.toml` 行宽 120，和 Python 工具一致。
- **代码**：`engine/core/` 三个文件：`ids.rs`（各种 id）、`cards.rs`（读取和校验、装备合并）、`battle.rs`（结算）。函数和 GDScript 版一一对应，对照表见 [engine/README.md](../../engine/README.md)。
- **用例**：Rust 的测试读 `tests/cases/` 的规则用例和冒烟用例，都检查左右对称，另有校验、装备合并、四舍五入的单元测试。
  - 对照 2.2 列的易错点逐条看了现有用例：四舍五入（`rule-half-damage`、`rule-half-skill-sum`）、致命和庇护、≤0 照常参与（`rule-backlash-both`、`rule-assist-zero`）、协战的顺序都有用例。
  - 平局计数在有人阵亡时清零，原来没有用例，新增 `rule-no-death-reset`（手算后用 `just record` 录入，结果和手算一致）。
  - 故意改坏几处规则（多一轮少走一轮、庇护一次消耗两层、阵亡不清零计数），共用用例都能发现。
- **临时对拍**（正式的工具在第 2 批）：20 万场随机对局（1–7 人、各星级的正式卡，一半是机制密集的阵容）分别用 Godot 和 Rust 跑，**零差异**。Rust 发布构建单线程约 60 万场/秒，约为 Godot 版的 90 倍。
- **和 GDScript 版不同的地方**：只在 GDScript 版会出错的数据上（基础技能写 null、给值为 null 的词条加数值、阵容放错类型），见 [engine/README.md](../../engine/README.md)。
- `just test` 最后跑 `just rs-test`；没装 Rust 时提示去装 rustup。

