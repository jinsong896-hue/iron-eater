# CLAUDE.md — 《噬铁者》Godot 项目开发指南

> 本文件给 Claude Code（及其他 AI 助手）提供本项目的最小上下文。所有对话启动时自动加载，请勿删除。
> 项目另有一份 `AGENTS.md`（开发规范/收工流程），二者互补，均需遵守。

## 项目概览

- 项目名：《噬铁者》（config/name），Godot 4.7 **mono** 版，GDScript 为主（[dotnet] 段存在但主逻辑用 GDScript）。
- 类型：俯视角 Roguelike 动作游戏（随机地牢 + 装备系统 + 开始页面/存档）。
- 主场景：`res://scenes/ui/main_menu.tscn`。
- 详细功能清单见 `README.md`；策划/方案文档在 `ai/*.md`；进度文档在 `docs/progress/PROGRESS_YYYYMMDD.md`（收工前必须更新）。

## Godot 引擎位置

```text
F:\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe
```

- 无图形界面的验证用 `--headless`；本项目是 mono 版，命令行与普通版一致。
- 运行项目：`"<上面的exe>" --headless --path .` （或去掉 `--headless` 打开窗口）。

## 项目结构

```text
scripts/core/        核心系统（autoload：EventBus、GameState、SaveManager、AudioManager、InputSetup 等）
scripts/combat/      伤害管线（damage_pipeline.gd）
scripts/dungeon/     随机地牢（BSP、房间、导航网格 NavigationServer2D）
scripts/equipment/   装备系统（模板/实例、吞噬/融合/强化）
scripts/enemies/     敌人（木桩、追踪型 NavigationAgent2D）
scripts/player/      玩家
scripts/ui/          UI/HUD
rooms/               房间与瓦片相关
scenes/              场景（main.tscn、player.tscn、ui/）
tests/               测试（自研框架，见下）
data/                静态数据（如装备数据 white_equipment_data.gd，运行时唯一数据源）
ai/                  策划方案文档（关卡/装备/开始页面等）
addons/              编辑器插件（见下）
```

## 测试（自研框架，不是 gdUnit4）

项目用**自研轻量测试框架**：脚本 `extends SceneTree` 或 `extends Node`，在 `_init()` 里跑断言，用 `_check(条件, "描述", failed)` 累计，最后打印 `ALL ... TESTS PASSED` 或失败明细。

常用命令（在项目根目录执行）：

```bash
GODOT="F:/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe"

# 核心逻辑自测（属性/伤害/装备/吞噬融合）
"$GODOT" --headless --path . --script res://tests/test_framework.gd

# 装备系统
"$GODOT" --headless --path . --script res://tests/test_equipment.gd

# 房间/地牢
"$GODOT" --headless --path . --script res://tests/test_room.gd
"$GODOT" --headless --path . --script res://tests/test_dungeon.gd

# 场景型测试（直接跑场景，带 --flow-test 参数用于流程测试）
"$GODOT" --headless --path . res://tests/test_gameplay_scene.tscn
"$GODOT" --headless --path . -- --flow-test res://tests/test_enter_dungeon_flow.tscn
```

规则：**改完代码必须实跑对应测试并记录证据到进度文档**（见 `AGENTS.md`）。

## 已安装的编辑器插件（addons/，project.godot [editor_plugins] 已启用）

| 插件 | 用途 |
|------|------|
| godot_ai（v3.1.5） | Godot AI MCP 插件，编辑器与 AI 助手桥接；`_mcp_game_helper` autoload 属它 |
| gdUnit4（v6.2.1） | 单元测试框架（并行于自研框架；如要用它写 `GdUnitTestSuite` 测试可参考其 src/） |
| phantom_camera | 相机系统（PhantomCameraManager autoload） |
| ChineseNodeSelector | 中文节点选择器 |
| at-icons | 图标 |

## 全局可用工具（已装到本机，跨项目可用）

- **Claude Code 技能**（`~/.claude/skills/`）：superpowers 全套（TDD/调试/计划）+ godot 技能 + spiral/randroid/task-tracking 等，随对话自动可用。
- **gdtoolkit**（`~/.local/bin/`）：`gdformat` / `gdlint` / `gdparse` 格式化与检查 GDScript。
- **playgodot**（Python，装在 `E:/下载/godot/.venv`，需自定义自动化分支的 Godot 构建才可用，本项目暂不需要）。
- **MCP 服务器**：`godot-ai`（已连编辑器）、`godot-mcp`（GODOT_PATH 已指向本机 Godot）、`gdmcp.exe`（Godot MCP Native CLI，需编辑器内 Godot MCP Native 插件）。
- **GodotMaker 框架**（`E:/下载/godot/tools/GodotMaker/`）：ECS 文本生成游戏的多 agent 脚手架，用 `python tools/publish.py <目标游戏项目>` 发布，本项目未启用。

## 注意事项

- 项目是 git 仓库（master 分支）。收工流程见 `AGENTS.md`：更新进度文档 → commit → push。
- `ai/demo2` 里另有一个 project.godot，会被 Godot 忽略，勿混淆。
- 素材规则：优先 CC0 免费素材（Kenney 等），保留 License，见 `AGENTS.md` 第七节。
- 所有函数必须加注释（`AGENTS.md` 末尾硬性要求）。
