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

### 已完成（09-13 ~ 09-19）

- **层级系统**：9 层主题/范围/房间数/难度全落地（`data/levels/floor_defs.gd`），
  2~8 层机制逐层分化（坍塌/毒气/泥潭/符文熔炉/硫磺/虚空扭曲/火焰风暴）
- **Boss 体系**：53 个 Boss 轮换 + 机制归并 + 通用原语；保底掉落与钥匙碎片
- **职业系统**：5 职业 × 25 形态 × 40 技能，31 个形态机制全部接线
- **装备**：白~红六档稀有度程序化生成（系数 1.0/1.6/2.5/4.0/6.5/10.0）+ 附魔 + 融合
- **元素系统**：六元素词条 / 叠层 / 阈值控制 / 元素联动伤害 / 抗性穿透反弹
- **怪物**：64 种全量入库（基础 40 / 独特 16 / 第 9 层 8），59 个机制标记中 54 个已实装
- **精英词缀**：9 个全部实装；**事件房池** 9 种；**特殊房正式 UI**
- **性能规模化**：CrowdSim（2000 单位 137fps）、ProjectileSim（4096 发弹幕）、
  特效池、海量文本单 draw call、房间预加载（切房 10.48ms → 2.28ms）

### 待完成（见 docs/progress/ 任务清单）

- 5 个怪物机制里的 4 个已补（`dash_stun_self` / `lava_aura` / `void_gravity` / `devour_grow`）；
  剩 `boss_skill` 待策划指明"继承最终 Boss 的哪个技能"
- 局外养成（天赋树 / 形态解锁 / 局外锻造 / 图鉴）——`main_menu.gd` 仍是"开发中..."
- 商店出售装备；手柄映射；消耗品体系
- 等策划给数：元素武器表、红装逐件机制表、稀有度具名后缀

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
bash tests/run_all.sh                   # 全量门禁：框架 + 21 套场景/脚本套件（共 22 套）
```

## 下一步建议

1. `boss_skill`（破坏神投影）——需策划指明继承最终 Boss 的哪个技能；
   其余 4 个怪物专属机制已于 09-19 补齐
2. 局外养成整块（天赋树 / 形态解锁 / 锻造 / 图鉴）——唯一未动的大系统
3. 商店出售装备 + 消耗品体系（两者互相牵连：加炸弹道具会动背包/掉落/商店三处）
4. 手柄映射（`input_manager.gd` 自述解耦但零 joypad 映射）
5. 等策划给数再动：元素武器表 / 红装逐件机制表 / 稀有度具名后缀
