godot := env("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot")
# 引擎在没有 await 的同步循环里卡死时看门狗无效，外层再加一道超时
limit := "timeout 600"

# 运行游戏
run:
    {{godot}} --path .

# 全部测试：数据检查、战斗用例（含镜像检查、事件自洽）、回放检查、冒烟流程
test:
    {{limit}} {{godot}} --headless --path . --script res://tests/run_tests.gd

# 用当前引擎重录战斗用例的期望值，并列出变化
record:
    {{limit}} {{godot}} --headless --path . --script res://tests/tools/record_golden.gd

# 重新生成随机用例（卡牌增删后），之后运行 just record
gen-random:
    {{limit}} {{godot}} --headless --path . --script res://tests/tools/gen_random_cases.gd

# 枚举关卡的全部解，写入 level 组用例，之后运行 just record
levels:
    {{limit}} {{godot}} --headless --path . --script res://tests/tools/level_solutions.gd

# 检查关卡：枚举全部摆法，打印解数、通过率和全部解；可指定关卡文件（格式同 data/levels.json）
level-check *file:
    {{limit}} {{godot}} --headless --path . --script res://cli/levels.gd -- {{file}}

# 批量模拟：输入 JSONL 每行 {"p1": [...], "p2": [...]}，输出每行一个结果；加 --log 带事件日志，--cards <文件> 加额外卡牌
sim input output *flags:
    {{limit}} {{godot}} --headless --path . --script res://cli/sim.gd -- {{input}} {{output}} {{flags}}
