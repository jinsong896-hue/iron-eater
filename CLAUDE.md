# CLAUDE.md — 《噬铁者》Godot 项目开发指南

> 本文件给 Claude Code（及其他 AI 助手）提供本项目的最小上下文。所有对话启动时自动加载，请勿删除。
> 项目另有一份 `AGENTS.md`（开发规范/收工流程），二者互补，均需遵守。

## 项目概览

- 项目名：《噬铁者》（config/name），Godot 4.7 **mono** 版，GDScript 为主。
- 类型：HD-2D 俯视角 Roguelike 动作游戏（3D 空间 + 2D 美术风格，类似八方旅人+火炬之光+以撒的结合）
- 渲染：**Forward+** 渲染器，3D 场景 + 2D CanvasLayer UI
- 主场景：`res://scenes/main.tscn`（GameRoot Node3D）。
- 控制：WASD/上下左右 移动 + 方向键攻击
- 详细功能清单见 `README.md`；策划/方案文档在 `ai/*.md`（含 `ai/hd2d.md` HD-2D 完整方案）

## Godot 引擎位置

```text
F:\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe
```

- 无图形界面的验证用 `--headless`；本项目是 mono 版，命令行与普通版一致。
- 运行项目：`"<上面的exe>" --headless --path .` （或去掉 `--headless` 打开窗口）。

## 项目架构：四层分离

```
UI 层 (CanvasLayer)     →  HUD / Menu / Inventory / Dialog
表现层 (Presentation)   →  Player3D / Enemy3D / Room3D / Camera / Lighting
逻辑层 (Gameplay)       →  CombatSystem / SkillSystem / LootSystem / DungeonGen
数据层 (Data)           →  AttributeSystem / Equipment / SkillData / RoomData
核心层 (Core)           →  EventBus / GameManager / SaveManager / InputManager
```

## 项目结构

```text
core/                 核心系统 (Autoload)：EventBus, GameManager, SaveManager, AudioManager, InputManager, SceneManager, SettingsManager, ResourceManager
data/                 数据层（纯数据，不依赖表现）
  attributes/         attribute_system.gd — 11 属性 + Modifier 框架
  equipment/          equipment_defs, template, instance, db, affix_data, affix_instance, fusion_rules, enhancement_rules
  skills/             skill_data.gd
  enemies/            enemy_data.gd
  rooms/              room_data.gd — JSON 驱动的房间蓝图
  items/              item_data.gd
  balance/            game_balance.gd — 数值平衡配置
gameplay/             逻辑层（游戏规则）
  combat/             damage_pipeline.gd, combat_system.gd, hit_detection.gd
  skills/             skill_system.gd, projectile_system.gd
  inventory/          inventory_system.gd, equipment_manager.gd
  loot/               loot_system.gd
  enemies/            enemy_ai.gd, enemy_spawner.gd
  dungeon/            dungeon_generator.gd, room_controller.gd
  status/             status_effect.gd
world/                世界层（3D 场景构建）
  rooms/              room_builder.gd, floor_builder, wall_builder, door_builder, decoration_builder
  navigation/         navigation_builder.gd
  environment/        world_environment.gd
  themes/             theme_library.gd
entities/             实体层（3D 角色/怪物/道具）
  player/             player.gd (CharacterBody3D), player_movement, player_combat, player_view
  enemies/            enemy_base.gd, enemy_view, melee_enemy, ranged_enemy
  props/              chest, door, torch
  items/              item_pickup
rendering/            渲染/视觉层
  camera/             camera_rig.gd, camera_settings.gd
  lighting/           lighting_manager.gd
  shaders/            pixel_style.gdshader
  post_process/       post_process.gd
  effects/            damage_popup.gd, effect_manager.gd
  materials/          material_library.gd
ui/                   UI 层（CanvasLayer，纯 2D）
  hud/                hud.gd, stat_orb, skill_slot, minimap
  menu/               main_menu, pause_menu, settings_panel, save_slot_card, settlement_panel
  inventory/          equipment_screen
  common/             confirm_dialog, toast_manager, ui_theme
scenes/               场景文件 (.tscn)
  main.tscn, player.tscn
  enemies/, rooms/, props/, world/, ui/, items/
assets/               静态资源
tests/                测试（自研框架）
data/rooms/           房间 JSON 数据（编辑器导出）
tools/                编辑器工具
```

## 坐标系统

- 2D 逻辑坐标：`Vector2(x, y)` → 3D 世界坐标：`Vector3(x, 0, y)`
- `CELL_SIZE = 1.0`（1 格 = 1 米）
- 统一转换：`RoomBuilder.grid_to_world(x, y, height) -> Vector3`

## 测试（自研框架）

```bash
GODOT="F:/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe"

# 核心逻辑测试
"$GODOT" --headless --path . --script res://tests/test_framework.gd
```

## 注意事项

- 旧 2D 代码已归档到 `E:\unity_legacy_backup_*.zip`，不再保留在项目目录中
- 所有新代码使用新目录结构（`core/`, `data/`, `gameplay/`, `world/`, `entities/`, `rendering/`, `ui/`）
- 所有函数必须加注释
- 项目是 git 仓库（master 分支）。收工流程见 `AGENTS.md`：更新进度文档 → commit → push
- 素材规则：优先 CC0 免费素材（Kenney 等），保留 License