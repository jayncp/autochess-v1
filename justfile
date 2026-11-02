godot := env("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot")
# 引擎在没有 await 的同步循环里卡死时看门狗无效，外层再加一道超时
limit := "timeout 600"

# 运行游戏
run:
    {{godot}} --path .

# 全部测试：战斗用例（含镜像检查）+ 冒烟流程
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
