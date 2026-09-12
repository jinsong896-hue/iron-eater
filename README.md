# 《噬铁者》Godot 原型框架

引擎：Godot 4.7 mono（GDScript，Forward+ 渲染器，HD-2D 风格）

## 当前状态（2026-09-13）

> 项目正处于旧 2D 版本向 HD-2D（3D 场景 + 像素表现）重构的中途。
> 下述条目为**重构后当前实际状态**，与旧 2D 版本能力有差异。

### 已完成（HD-2D 新架构）

- 四层分离架构：`core/`（Autoload）→ `data/`（纯数据）→ `gameplay/`（规则）→ `world/entities/rendering/ui/`（表现）
- HD-2D 渲染：WorldEnvironment（SSAO/Glow/Fog/色调映射）+ CameraRig + 像素渲染管线 + 伤害飘字
- 玩家 3D 控制：WASD 移动、双击/Shift 奔跑、空格翻滚（无敌帧）、方向键 8 方向扇形攻击
- 战斗系统：四段普攻连段 + 奔跑冲撞 / 跳跃落地斩 + 取消窗口 / 派生 / 终结霸体 / 连击加成 / 击退硬直 / Hitstop
- 属性系统：11 项基础属性 + Modifier 叠加（来源无关）
- 伤害管线：`ATK × 倍率 × (1+增伤) × (1 - 护甲减伤)` + 暴击
- 装备系统：**36 件白装全量**（12 武器 + 18 护甲 + 6 饰品，表驱动）+ 穿戴/吞噬/融合
  （上限 25 次）/强化（+5%/级、上限 10 级）核心逻辑
- 地下城：DungeonGenerator（种子随机 + 房间类型分配）+ GameRoot 房间加载/切换 + RoomController 生命周期
- 房间闭环：进房锁门 → 刷怪 → 全灭开门 → 穿门切房；Boss 房 → 杀 Boss → 传送门 → 下一层
- **特殊房**：商店 / 泉水 / 事件房（占位交互物 + 按 E 交互结算 + 门锁闭环）
- 第一层 **10 种怪物**落地（表驱动 MonsterDB，含飞行/远程风筝/炮台/突进/闪避/死亡毒雾）
- 资源闭环：宝箱实体、击杀回血、层间满状态传送、金币档位经济
- UI：主菜单 / 暂停 / 设置 / 存档卡 / 结算 / HUD / 背包四页签 / 右上角拓扑小地图
- 三存档 SaveManager（.bak 备份 + .tmp 原子写入）+ SettingsManager

### 进行中 / 待完成（见 docs/progress/ 任务清单）

- 特殊房正式 UI（商店购买面板 / 事件分支选择）与事件房池内容（策划 9 种）
- 第 2~9 层主题模板（当前全层复用第一层模板池）、Boss 保底掉落与钥匙碎片
- 绿装及以上稀有度、六元素词条、12 件红武、融合词条品质递进
- 职业形态切换（5 职业 × 5 形态）、局外养成（天赋树/形态解锁/锻造）

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

用 Godot 4.7 打开 `E:\unity`，运行主场景（`scenes/ui/main_menu.tscn`）。

命令行验证（注意：新克隆/清理后必须先跑 `--import` 重建类缓存，见 CLAUDE.md）：

```bash
GODOT="F:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path . --import   # 重建 .godot/global_script_class_cache.cfg
bash tests/run_all.sh                   # 全量门禁：框架 160 项 + 8 套场景/脚本套件
```

## 下一步建议

1. 特殊房正式 UI（商店购买面板 / 事件分支选择）+ 事件房池内容落地
2. 第 2~9 层主题模板（每层主题/房间数/耗时见策划关卡分册）+ Boss 保底掉落
3. 绿装及以上稀有度 + 六元素词条 + 融合词条品质递进
4. 职业形态切换 + 局外养成（天赋树/形态解锁/锻造）
