# 《噬铁者》Godot 原型框架

引擎：Godot 4.7 mono（GDScript，Forward+ 渲染器，HD-2D 风格）

## 当前状态（2026-08-31：HD-2D 重构中期）

> 项目正处于旧 2D 版本向 HD-2D（3D 场景 + 像素表现）重构的中途。
> 下述条目为**重构后当前实际状态**，与旧 2D 版本能力有差异。

### 已完成（HD-2D 新架构）

- 四层分离架构：`core/`（Autoload）→ `data/`（纯数据）→ `gameplay/`（规则）→ `world/entities/rendering/ui/`（表现）
- HD-2D 渲染：WorldEnvironment（SSAO/Glow/Fog/色调映射）+ CameraRig + 像素渲染管线 + 伤害飘字
- 玩家 3D 控制：WASD 移动、双击/Shift 奔跑、空格翻滚（无敌帧）、方向键扇形攻击
- 属性系统：11 项基础属性 + Modifier 叠加（来源无关）
- 伤害管线：`ATK × 倍率 × (1+增伤) × (1 - 护甲减伤)` + 暴击
- 装备系统数据层（**7 件白装最小版**，36 件全量待补）：模板/实例分离、
  穿戴/吞噬/融合核心逻辑（融合上限 25 次、攻击加成分段至 +100%）
- 地下城：DungeonGenerator（种子随机）+ GameRoot 房间加载/切换 + RoomController 生命周期
- 房间构建：Floor/Wall/Door/Decoration Builder + 13 个 JSON 房间蓝图
- UI 骨架：主菜单 / 暂停菜单 / 设置 / 存档卡 / 结算 / HUD / 背包（背包待重接新数据层）
- 三存档 SaveManager（.bak 备份 + .tmp 原子写入）+ SettingsManager

### 进行中 / 待完成（见 docs/progress/ 任务清单）

- 装备管理界面重接新数据层（四页：装备/背包/强化+融合/吞噬）
- 36 件白装补全、强化系统 UI 入口、掉落链路（LootSystem ↔ 地牢互连）
- 房间刷怪闭环（EnemySpawner ↔ RoomController）、特殊房与 Boss 房
- 绿装及以上稀有度、12 件红武、六元素词条

## 操作

- `WASD` 移动　`Shift`/双击 奔跑　`空格` 翻滚
- 方向键（↑↓←→）切换朝向并攻击（扇形判定）
- `F` 吞噬附近掉落物　`I` 背包（入口待重接）
- 游戏内 `ESC`：暂停菜单

## 目录结构

```text
core/                   Autoload：EventBus, GameManager, SaveManager, AudioManager,
                        InputManager, SceneManager, SettingsManager, ResourceManager, DataValidator
data/                   数据层 Resource：attributes/ (11属性+Modifier), equipment/
                        (defs/template/instance/db/affix/fusion), rooms/ (room_data + JSON),
                        balance/ (game_balance), character/monster/weapon/skill/stats 等数据类
gameplay/               combat/ (damage_pipeline, combat_core), skills/, inventory/
                        (equipment_manager), loot/, enemies/, dungeon/, status/
world/                  rooms/ (floor/wall/door/decoration builders), navigation/, environment/, themes/
entities/               player/player.gd (CharacterBody3D), enemies/enemy_base.gd
rendering/              camera/, lighting/, shaders/, post_process/, effects/, materials/
ui/                     hud/, menu/ (main/pause/settings/settlement), inventory/ (backpack)
scenes/                 main.tscn (GameRoot), player.tscn, ui/, rooms/, props/, world/
tests/                  test_framework.gd（自研，--script 模式）
docs/progress/          进度文档（PROGRESS_YYYYMMDD.md）
ai/                     技术方案文档（装备 V0.9、HD-2D、关卡、框架等）
策划书/                  六分册设计文档（docx）
addons/                 gdUnit4, godot_ai, iron_studio, phantom_camera, terrain_3d
```

## 打开方式

用 Godot 4.7 mono 打开 `E:\unity`，运行主场景（`scenes/ui/main_menu.tscn`）。

命令行验证（注意：新克隆/清理后必须先跑 `--import` 重建类缓存，见 CLAUDE.md）：

```bash
GODOT="F:/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe"
"$GODOT" --headless --path . --import   # 重建 .godot/global_script_class_cache.cfg
"$GODOT" --headless --path . --script res://tests/test_framework.gd
```

## 下一步建议

1. 装备管理界面重接新数据层（P1 起点）
2. 36 件白装补全 + 掉落链路打通
3. 房间刷怪闭环 + 特殊房交互 + Boss 房逻辑
4. 职业形态切换 + 绿装及以上稀有度、从 CSV 导入数值表
