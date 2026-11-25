godot := env("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot")
# 引擎在没有 await 的同步循环里卡死时看门狗无效，外层再加一道超时
limit := "timeout 600"

# 运行游戏
run:
    {{godot}} --path .

# 全部测试：数据检查、战斗用例（含镜像检查、事件自洽）、回放检查、冒烟流程，再跑 Rust 版的测试
test:
    {{limit}} {{godot}} --headless --path . --script res://tests/run_tests.gd
    just rs-test

# 用当前引擎重录规则用例的期望值，并列出变化
record:
    {{limit}} {{godot}} --headless --path . --script res://tests/tools/record_cases.gd

# 重新生成冒烟用例里的随机对局（卡牌增删后）
gen-random:
    {{limit}} {{godot}} --headless --path . --script res://tests/tools/gen_random_cases.gd

# 枚举关卡的全部解，写入冒烟用例
levels:
    {{limit}} {{godot}} --headless --path . --script res://tests/tools/level_solutions.gd

# 检查关卡：枚举全部摆法，打印解数、通过率和全部解；可指定关卡文件（格式同 data/levels.json）
level-check *file:
    {{limit}} {{godot}} --headless --path . --script res://cli/levels.gd -- {{file}}

# 估算回放时长（1 倍速）：随机对局的平均、中位、P90 和各段落的占比；可指定场数、--stars 1,2 只用这些星级
replay-time *args:
    {{limit}} {{godot}} --headless --path . --script res://cli/replay_time.gd -- {{args}}

# 批量模拟（Rust 版，多核）：输入 JSONL 每行 {"p1": [...], "p2": [...]}，输出每行一个结果；--cards <文件> 加额外卡牌，--trace 带简要轨迹，--threads N
sim input output *flags: rs-build
    engine/target/release/engine-cli {{input}} {{output}} {{flags}}

# 批量模拟（Godot 版，cli/sim.gd，单进程）：格式同上；--log 带事件日志
sim-godot input output *flags:
    {{limit}} {{godot}} --headless --path . --script res://cli/sim.gd -- {{input}} {{output}} {{flags}}

# Rust 版结算（engine/，含 Python 绑定）：格式和静态检查，警告当错误
rs-check: _cargo
    cd engine && cargo fmt --all --check && cargo clippy --workspace --all-targets --quiet -- -D warnings

# Rust 版结算的测试，含 tests/cases/ 的共用用例
rs-test: _cargo
    cd engine && cargo test --quiet

# 发布构建 Rust 版：命令行 engine/target/release/engine-cli，以及 Python 绑定（装进 tools/.venv；tools 的命令运行时也会自动重新编译）
rs-build: _cargo
    cd engine && cargo build --release --quiet -p autochess-cli
    cd tools && uv sync --inexact --quiet

# 对拍：同一批随机对局（一半机制密集，固定种子）分别用 Godot 和 Rust 跑，逐场比较；默认 100 万场，可加 --seed N
diff-sim count="1000000" *flags: rs-build
    cd tools && uv run python -m autochess_tools.diff_sim {{count}} {{flags}}

# 测速：固定的一批随机对局，Rust 版单线程、多线程和 Godot 版单进程的场/秒
bench: rs-build
    cd tools && uv run python -m autochess_tools.bench

# 检查有没有装 Rust（版本由 engine/rust-toolchain.toml 指定，第一次运行时自动安装）
[private]
_cargo:
    @command -v cargo > /dev/null || { echo "没找到 cargo：Rust 版结算需要先装 rustup（https://rustup.rs），装好后重开终端"; exit 1; }

# Python 工具：代码检查和测试（含 Rust 版的 Python 绑定，源码变了 uv 会先重新编译）
tools-check:
    cd tools && uv run ruff check && uv run ruff format --check && uv run ty check && uv run pytest -q

# 运行平衡实验（tools/autochess_tools/experiments/<名字>.py），结果打印到终端
experiment name:
    cd tools && uv run python -m autochess_tools.experiments.{{name}}

# 数值试验（tools/autochess_tools/balance/<模块>.py）：run 六个阶段的阵容搜索，stage 单个阶段，check 复核一张卡，
# compare 比较两份报告，trend 趋势页，sheet 读写试验表，usage 把出场率填进设计表。用法见 tools/README.md
balance module *args:
    cd tools && uv run --group balance python -m autochess_tools.balance.{{module}} {{args}}

# 经济系统的估算（tools/autochess_tools/economy/<模块>.py）：price 给均衡阵容算价格和成型回合，report 做成一页图表。
# 规则在 docs/design/economic-system.xlsx，用法见 tools/README.md
economy module *args:
    cd tools && uv run --group balance python -m autochess_tools.economy.{{module}} {{args}}

# 字体子集化：从 Google Fonts 下载源字体，裁到常用字加翻译表用到的字，写到 assets/fonts/
fonts:
    cd tools && uv run --group art python -m autochess_tools.art.fonts

# 美术素材：图标、卡牌边框和法阵、界面贴图、战斗飘字的饰板（SVG 渲染成 PNG），之后重建主题
art:
    cd tools && uv run --group art python -m autochess_tools.art.icons
    cd tools && uv run --group art python -m autochess_tools.art.ornaments
    cd tools && uv run --group art python -m autochess_tools.art.ui
    cd tools && uv run --group art python -m autochess_tools.art.fx
    {{godot}} --headless --path . --import > /dev/null 2>&1
    just theme

# 用 cli/build_theme.gd 重建全局主题 assets/ui/theme.tres 和字体变体 assets/fonts/*.tres
theme:
    {{limit}} {{godot}} --headless --path . --script res://cli/build_theme.gd

# 界面截图：各界面截到指定目录（默认 /tmp/autochess_shots），默认 1920 × 1080，手机用 2376 宽。需要窗口
shots out="/tmp/autochess_shots" width="1920" height="1080":
    {{limit}} {{godot}} --path . --script res://tests/tools/capture.gd -- {{out}} {{width}} {{height}}
