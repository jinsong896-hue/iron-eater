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
- **随机地牢生成**（依据《关卡设计分册》与 `ai/关卡相关.md` 方案）：
  - BSP 布局：母网格 14×14 → 30×30（第 9 层线性链），房间 1～3 格
  - 初始房固定中心 (0,0)、Boss 房最远端、商店/宝箱/泉水/事件/隐藏房按距离规则分配、精英房 20%～30%
  - 瓦片规格：64×64 瓦片、2 瓦片墙、门洞自动开凿、走廊连通
  - 房间切换 + 相机边界锁定（RoomCamera，房间 < 视口时自动居中）
  - NavigationServer2D 寻路网格（手工构建：房间可用区 + 门洞桥接 + 走廊）
  - 追踪敌人（NavigationAgent2D）与木桩敌人

## 操作

- `WASD` 移动
- 鼠标左键 / `J` 攻击（朝鼠标方向，扇形判定）
- `R` 重新生成本层　`N` 下一层
- HUD 按钮：+金币 / 生成装备 / 重置单局 / **装备管理** / 重新生成本层 / 下一层
- 装备管理界面：ESC 关闭；左键查看+对比，右键功能条

## 目录结构

```text
scenes/
  main.tscn              # 地牢主场景（DungeonManager + Player + HUD）
  dungeon/               # room / chaser_enemy
  player.tscn            # 玩家（Camera2D = RoomCamera）
  ui/hud.tscn            # HUD
scripts/
  core/                  # 属性系统、事件总线、局内状态（吞噬/融合）、输入
  combat/                # 伤害管线
  equipment/             # 装备数据 Resource、掉落拾取
  equipment/             # 定义/词条/模板/实例/槽位/融合/强化/管理器/数据库
  player/                # 玩家控制器
  enemies/               # 木桩敌人、追踪敌人
  dungeon/               # BSP 节点、房间数据、章节配置、分配器、生成器、相机、触发器、层管理器
  ui/                    # HUD
data/
  equipment/templates/   # 36 件白装模板 .tres（由 tools/generate_equipment_tres.gd 生成）
  dungeon/layers/        # 9 层章节配置（Layer01~09.tres，含主题配色与房间数量）
tests/                   # test_framework / test_dungeon / test_equipment
tools/                   # generate_equipment_tres.gd（白装 .tres 生成工具）
```

## 打开方式

用 Godot 4.7 打开 `E:\unity`，运行主场景即可。

## 下一步建议

1. 房间主题模板（每层 5～8 种 PackedScene 布局，接入 ThemeConfig）
2. 商店 / 泉水 / 宝箱 / 事件房交互内容
3. Boss 房逻辑（第 8 层破坏神化身等）
4. 职业形态切换 + 绿装及以上稀有度、从 CSV 导入数值表
