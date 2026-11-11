# 存档

> 活文档：存档放在哪、有哪些文件、字段、版本和升级规则。以后要存新内容时更新这里。
> 设置页面的布局见 [art-direction.md](art-direction.md) 第 5.8 节；计划和讨论见 [../plans/settings-save.md](../plans/settings-save.md)。

## 1. 位置

存档目录是 Godot 的 `user://`，项目设置里改成了固定的名字 `niuma_autochess`（`application/config/use_custom_user_dir`、`custom_user_dir_name`），和游戏名无关，以后游戏改名也不变。

| 平台 | 存档位置 |
|---|---|
| Windows | `%APPDATA%\niuma_autochess\` |
| macOS | `~/Library/Application Support/niuma_autochess/` |
| Linux | `~/.local/share/niuma_autochess/` |
| Android | 应用内部存储（`/data/data/<包名>/files/`），玩家看不到，卸载时一起删除 |

- 不支持修改位置。设置页面显示路径，PC 上可以复制、打开文件夹。
- 从编辑器运行（`just run`）用的也是这个目录，本机试玩的记录就是正式记录。
- 同一个目录里还有引擎自己的 `logs/`、着色器缓存这类，和存档无关。
- **Android 包名**：现在是占位的 `com.example.autochess`，正式发布前要定下来，之后再改就等于换了一个应用，存档会丢。

## 2. 文件

| 文件 | 内容 | 代码 |
|---|---|---|
| `settings.cfg` | 设置 | `GameSettings`（`scripts/core/game_settings.gd`） |
| `save.json` | 进度 | `SaveData`（`scripts/core/save_data.gd`） |

两个都是静态类，启动时（场景管理器）读一次，改了立刻写。文件路径是静态变量，测试和截图用各自的文件名（`test_*`、`capture_*`），不读写玩家的存档。

### settings.cfg

Godot 的 `ConfigFile`（文本）。缺的项用默认值，不认识的项和不合法的值忽略。

| 节 | 键 | 默认 | 说明 |
|---|---|---|---|
| `battle` | `speed` | `1.0` | 默认速度，1、2、5、20 之一。每场开战时读 |
| `board` | `compact` | `false` | 默认紧凑模式。每次进入构筑阶段、科研模式时读 |

默认值只在进入时读，当次可以临时改，临时改的不写回。从战斗回到构筑阶段或科研模式不算重新进入，保持刚才临时切的。

### save.json

```json
{
  "version": 1,
  "levels": {
    "boar_rush": {"cleared": true, "first_cleared": "2026-11-11T16:52:25"}
  }
}
```

| 字段 | 说明 |
|---|---|
| `version` | 存档格式的版本，现在是 1 |
| `levels` | 闯关记录：关卡 id → 记录。没有记录的关卡不出现 |
| `levels.<id>.cleared` | 已通关。只有我方胜才算，平局、失败不算；科研模式的战斗不记 |
| `levels.<id>.first_cleared` | 第一次通关的本地时间，不显示；再次通关不改 |

- 关卡选择里已通关的关卡显示绿框和右上角的绿色对号。不做解锁，所有关卡一直都能进。
- 设置页面的"清除闯关记录"清空 `levels`，不动设置。

## 3. 写入和读取

- **写入**：先写到 `save.json.tmp`，原来的 `save.json` 改名为 `save.json.bak`，再把 `.tmp` 改名为 `save.json`。写到一半出错，原来的存档还在。
- **读取**：

  | 情况 | 处理 | 主菜单通知 |
  |---|---|---|
  | 没有存档 | 空进度 | 无 |
  | `save.json` 读不了或格式不对 | 改名为 `save.json.broken` 留着，读 `.bak` | "存档读取失败，已用备份恢复。" |
  | 备份也不行 | 从空进度开始 | "存档读取失败，进度已重置。" |
  | 版本比游戏新（旧游戏打开新存档） | 能读的照常读，只读不写 | "存档来自更新版本的游戏，这次的进度不会保存。" |

  "格式不对"指：不是 JSON 对象、没有数字的 `version`（至少 1）、`levels` 不是对象。

## 4. 加新内容

1. 能加字段就加字段，旧存档缺这个字段时用默认值，不用升版本。
2. 改了已有字段的含义或结构时 `VERSION` 加 1，在 `SaveData.load()` 里按版本号逐级升级旧存档（1 → 2 → 3），下次保存时写成新版本。现在只有版本 1，还没有升级代码。
3. 更新本文档的字段表，测试里加旧版本升级的用例。

以后可能要存的：冒险进度、金币、重播。到时再定。
