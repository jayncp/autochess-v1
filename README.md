# 牛马自走棋（autochess-v1）

用 Godot 4.7 制作的卡牌自走棋。

- 双方各排一个最多 7 人的队列，每个角色可以带 1 件装备，开战后按顺序自动交战，只有队首互相攻击。
- 游戏只有"战斗力"一个数值，既是攻击也是生命。
- 战斗没有随机，胜负取决于构筑和站位。

项目重启后持续开发中：战斗核心和 1★/2★ 卡牌已完成（部分新卡还没有卡图），正在重做 UI。

## 现状

- **可玩**：
  - 科研模式：自由摆双方阵容对战；
  - 闯关：2 个解谜关；
  - 图鉴；
  - 战斗演出，支持变速和跳过。
- **未实现**：冒险模式、局域网对战。
- **计划**：见 [docs/roadmap.md](docs/roadmap.md)；设计见 [docs/design/](docs/design/game-design.md)；文档索引见 [docs/README.md](docs/README.md)。

## 运行

用 Godot 4.7 打开本目录并运行主场景，或在命令行执行：

```sh
godot --path .
```

装了 [just](https://github.com/casey/just) 的话：`just run` 运行，`just test` 跑测试（说明见 [tests/README.md](tests/README.md)）。

## 协议

| 内容 | 协议 |
|---|---|
| 代码：GDScript、场景与工程配置、工具脚本 | [AGPL-3.0-or-later](LICENSE) |
| 美术资源（`assets/` 下的图片）、卡牌与关卡数据、文档（`docs/`） | [CC BY-SA 4.0](LICENSES/CC-BY-SA-4.0.txt) |
| 字体 Noto Sans SC、Noto Serif SC（`assets/fonts/`，按常用字子集化） | [SIL OFL 1.1](assets/fonts/OFL.txt)，© Adobe |

- 卡牌与关卡数据在 `data/`，翻译表在 `i18n/`，都按数据适用 CC BY-SA 4.0。
- 卡图和背景由 AI 辅助生成，并经过人工处理；还没有卡图的卡在卡面上显示淡显的种族图标。卡框、法阵、图标、界面贴图由 `tools/autochess_tools/art/` 的脚本生成。

Copyright © 2025–2026 jayncp
