# 《噬铁者》Godot 原型框架

引擎：Godot 4.7（GDScript）

## 当前内容（M0 最小可玩闭环 + 随机地牢 + 装备系统）

- 俯视角移动（WASD）+ 鼠标朝向普攻（左键 / J）
- 属性系统：11 项基础属性 + Modifier 叠加（口径见《名词设计分册》）
- 伤害管线：物理伤害公式 `ATK × 倍率 × (1+增伤) × (1 - 护甲减伤)`
- 装备 Resource 数据 + 吞噬 / 融合核心逻辑 + HUD（属性 / 金币 / 背包 / 调试按钮）
- **装备系统**（依据 `ai/基础装备相关.md` 方案 V0.9）：
  - 模板/实例分离：`EquipmentTemplate`（.tres）只描述装备，运行时数据全部在 `EquipmentInstance`
  - 36 件白装基准池：12 武器 + 18 护甲 + 6 饰品（`data/equipment/templates/*.tres`）
  - 10 槽位（6 防具 + 饰品×2 + 武器×2）、单手/双手自动判定、双手占槽属性只计一次
  - 每件装备三词条：基础（穿戴）/ 吞噬（本局永久）/ 融合（作为材料贡献）
  - 吞噬：确定成功、批量多选、当前→本次→最终汇总
  - 融合：策划公式计费、同槽位校验、同名升级/异名继承、失败原因提示
  - 强化：只提升基础词条、固定 +5%/级、无失败
  - 装备管理界面：装备 / 背包 / 强化（强化+融合）/ 吞噬 四页，左键查看完整对比，右键功能条（装备/查看/吞噬/强化/锁定/丢弃），背包筛选+排序+清除筛选
- **开始页面系统**（依据 `ai/开始页面相关.md`）：
  - 主菜单（世界观美术 + 文字选项）→ 三存档（创建/进入/删除，二次确认）→ 存档主页（开始/继续/升级/退出）→ 新游戏配置（五职业/模式/难度）
  - `SaveManager`：user:// 三存档 + .bak 备份 + .tmp 原子写入 + 版本/修订号 + 坏档回退 + 局外数据与当前局
  - `SettingsManager`：显示/音频/游戏设置，持久化 user://settings.cfg，主菜单与暂停菜单共用
  - 游戏内 ESC 暂停（真暂停）：继续 / 设置 / 返回主菜单（保留探索）/ 放弃探索（结算）/ 退出桌面
  - 结算页：层数/击杀/金币/时长/记忆残渣，写入存档历史
- **随机地牢生成**（依据《关卡设计分册》与 `ai/关卡相关.md` 方案）：
  - BSP 布局：母网格 14×14 → 30×30（第 9 层线性链），房间 1～3 格
  - 初始房固定中心 (0,0)、Boss 房最远端、商店/宝箱/泉水/事件/隐藏房按距离规则分配、精英房 20%～30%
  - 瓦片规格：64×64 瓦片、2 瓦片墙、门洞自动开凿、走廊连通
  - 房间切换 + 相机边界锁定（RoomCamera，房间 < 视口时自动居中）
  - NavigationServer2D 寻路网格（手工构建：房间可用区 + 门洞桥接 + 走廊）
  - 追踪敌人（NavigationAgent2D）与木桩敌人
- **房间生成系统**（依据 `ai/房间生成.md` 方案）：
  - `RoomBase` 统一房间生命周期：玩家进入 → 锁门 → 刷怪 → 清怪 → 开门
  - `RoomDoor` 门系统：检测门（Area2D）与实体门（StaticBody2D）分离，战斗锁门/完成后解锁
  - 瓦片集工厂：从 Kenney roguelike 精灵表构建 16×16 瓦片集（地/墙/草/栅栏，墙带碰撞）
  - 初始安全房：中央暖光、四周草地、南入口/北出口（`rooms/layer_01/start_room.tscn`）
  - 第一层 10 种普通战斗房模板（T01~T10，`rooms/layer_01/normal/L1_Normal_T*.tscn`），40×24 格、3~5 怪、可配置四向门
  - 已接入地牢生成器：第一层初始房/普通房/精英房自动使用模板池，按走廊入口动态开凿门洞并加门锁

## 操作

- `WASD` 移动
- 鼠标左键 / `J` 攻击（朝鼠标方向，扇形判定）
- `R` 重新生成本层　`N` 下一层
- HUD 按钮：+金币 / 生成装备 / 重置单局 / **装备管理** / 重新生成本层 / 下一层
- 装备管理界面：ESC 关闭；左键查看+对比，右键功能条

## 目录结构

```text
scenes/
  ui/main_menu.tscn      # 开始页面（主菜单/存档/新游戏配置/设置/升级）
  ui/pause_menu.tscn     # 游戏内暂停菜单（含结算页）
  main.tscn              # 地牢主场景（DungeonManager + Player + HUD）
  dungeon/               # room / chaser_enemy
  player.tscn            # 玩家（Camera2D = RoomCamera）
  ui/hud.tscn            # HUD
scripts/
  core/                  # 属性系统、事件总线、局内状态（吞噬/融合）、输入、存档/设置/目录
  combat/                # 伤害管线
  equipment/             # 装备数据 Resource、掉落拾取
  equipment/             # 定义/词条/模板/实例/槽位/融合/强化/管理器/数据库
  player/                # 玩家控制器
  enemies/               # 木桩敌人、追踪敌人
  dungeon/               # BSP 节点、房间数据、章节配置、分配器、生成器、相机、触发器、层管理器
rooms/
  base/                  # room_base / room_door / tileset_factory / room_base_carve
  layer_01/              # start_room + 10 种普通房模板（T01~T10）
  ui/                    # HUD
  ui/menu/               # 主菜单控制器、存档卡、设置面板、确认弹窗、过渡、结算、暂停菜单
data/
  equipment/templates/   # 36 件白装模板 .tres（由 tools/generate_equipment_tres.gd 生成）
  dungeon/layers/        # 9 层章节配置（Layer01~09.tres，含主题配色与房间数量）
tests/                   # test_framework / test_dungeon / test_equipment / test_room / test_menu
tools/                   # generate_equipment_tres.gd（白装 .tres 生成工具）
```

## 打开方式

用 Godot 4.7 打开 `E:\unity`，运行主场景（开始页面）即可；主菜单进入存档后开始/继续游戏进入地牢。

## 下一步建议

1. 房间主题模板（每层 5～8 种 PackedScene 布局，接入 ThemeConfig）
2. 商店 / 泉水 / 宝箱 / 事件房交互内容
3. Boss 房逻辑（第 8 层破坏神化身等）
4. 职业形态切换 + 绿装及以上稀有度、从 CSV 导入数值表
