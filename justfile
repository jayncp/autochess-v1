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

# 批量模拟：输入 JSONL 每行 {"p1": [...], "p2": [...]}，输出每行一个结果；加 --log 带事件日志，--cards <文件> 加额外卡牌
sim input output *flags:
    {{limit}} {{godot}} --headless --path . --script res://cli/sim.gd -- {{input}} {{output}} {{flags}}

# Rust 版结算（engine/）：格式和静态检查，警告当错误
rs-check: _cargo
    cd engine && cargo fmt --check && cargo clippy --all-targets --quiet -- -D warnings

# Rust 版结算的测试，含 tests/cases/ 的共用用例
rs-test: _cargo
    cd engine && cargo test --quiet

# 检查有没有装 Rust（版本由 engine/rust-toolchain.toml 指定，第一次运行时自动安装）
[private]
_cargo:
    @command -v cargo > /dev/null || { echo "没找到 cargo：Rust 版结算需要先装 rustup（https://rustup.rs），装好后重开终端"; exit 1; }

# Python 工具：代码检查和测试
tools-check:
    cd tools && uv run ruff check && uv run ruff format --check && uv run ty check && uv run pytest -q

# 运行平衡实验（tools/autochess_tools/experiments/<名字>.py），结果打印到终端
experiment name:
    cd tools && uv run python -m autochess_tools.experiments.{{name}}

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
