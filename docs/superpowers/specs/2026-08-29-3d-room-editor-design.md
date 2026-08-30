# 3D 房间编辑器设计

> 日期：2026-08-29
> 状态：设计已确认，待实现

## 背景

现有房间编辑器（room_launcher）用 2D 网格（ColorRect）编辑房间，有三个根本性问题：
1. **墙朝向丢失**：墙数据只存 `{x,y,type}`，没有 direction 字段。WallBuilder 的 `_get_edge_position`/`_get_edge_rotation` 依赖 direction，缺失时所有墙退化为同一朝向。
2. **2D 网格编辑 3D 房间是隔靴搔痒**：无法原位看到 3D 效果，操作不直观，网格区太小无法操作。
3. **刷怪点没绑定具体怪物**：实体只有 `{type,x,y,group}`，运行时 enemy_spawner 用硬编码属性生成通用敌人，忽略 MonsterData。

用户要求：直接在 3D 视口原位编辑（所见即所得），快速放置 3D 瓦片、墙（带朝向）、门、刷怪点，刷怪点能绑定具体怪物。

## 核心决策

- **编辑方式**：3D 视口直接绘制（`EditorPlugin._forward_3d_gui_input`，terrain_3d 已验证先例）。
- **架构**：方案 A——plugin.gd 统一管理输入和状态，dock 降为纯工具栏。
- **数据源**：编辑期间 3D 节点树是真实数据源，JSON 是存盘格式。加载时 JSON→节点树，保存时节点树→JSON。
- **墙**：数据加 direction 字段（north/south/east/west）。提供三种编辑方式（格子边缘放置、格子内放置+旋转、拖拽画线）。
- **刷怪点**：直接绑定 monster_id，从 `data/monsters/*.tres` 列表选。

## 整体架构

### 组件

```
plugin.gd (EditorPlugin)
  ├─ _forward_3d_gui_input()  ← 拦截 3D 视口鼠标事件
  ├─ 笔刷状态机（当前工具/选中瓦片/选中怪物）
  ├─ set_tool() / set_brush_tile() / set_spawn_monster()  ← dock 调用
  └─ 委托 room_editor_core.gd 做节点增删

room_dock.gd/.tscn (Control, dock 面板)
  ├─ 工具按钮组：地板/墙/门/刷怪/橡皮擦
  ├─ 墙模式子选项：边缘/格内/拖线
  ├─ 刷怪点配置：怪物下拉框（读 data/monsters/）
  ├─ 房间列表 + 加载/保存/新建
  └─ 房间元信息：名称/尺寸/类型

room_editor_core.gd (RefCounted)
  ├─ build_editor_tree(root, json_dict)  ← JSON → 3D 节点树
  ├─ serialize_tree(root) → Dictionary  ← 3D 节点树 → JSON
  ├─ paint_*(root, cell_x, cell_y, ...)  ← 笔刷操作（增删节点）
  └─ world_to_cell(world_pos) → Vector2i  ← 射线交点 → 格子坐标

room_editor.tscn (编辑专用场景)
  └─ RoomEditorRoot (Node3D)
      ├─ WorldEnvironment + 光照（取自 main.tscn 参数）
      ├─ Camera3D（俯瞰，可编辑时手动调整）
      ├─ FloorGrid (Node3D)  ← 可视化格子线（辅助定位）
      ├─ Floor (Node3D)
      ├─ Walls (Node3D)
      ├─ Doors (Node3D)
      └─ Spawns (Node3D)
```

### 数据流

```
加载：dock 选房间 → core.build_editor_tree(root, json) → FloorBuilder/WallBuilder(改)/DoorBuilder 构建 + 刷怪点 Marker3D
编辑：plugin._forward_3d_gui_input → 射线求交 → core.world_to_cell → core.paint_<tool>(root, x, y) → 增删节点
保存：dock 点保存 → core.serialize_tree(root) → JSON.stringify → 写 data/rooms/<id>.json
```

## 笔刷工具与交互

### 工具列表

| 工具 | 操作 | 数据影响 |
|------|------|----------|
| 地板 | 左键涂地板，右键擦 | floor 数组增删 {x,y,type:"stone"} |
| 墙-边缘 | 点击格子边缘放墙段，朝向由边缘决定 | walls 增 {x,y,direction,type} |
| 墙-格内 | 点击格子放墙，R 键旋转朝向 | walls 增 {x,y,direction,type} |
| 墙-拖线 | 拖拽画一排墙，自动判断朝向 | walls 批量增 |
| 门 | 点击格子边缘放门 | doors 增 {direction,id,x,y} |
| 刷怪点 | 点击放 Marker3D，绑定当前选中怪物 | entities 增 {type,x,y,monster_id} |
| 橡皮擦 | 点击删除该格所有元素 | 删 floor/wall/door/spawn |

### 射线 → 格子坐标

```
camera_pos = camera.project_ray_origin(mouse_pos)
camera_dir = camera.project_ray_normal(mouse_pos)
if camera_dir.y >= 0: return  # 射线向上/水平，不交
t = -camera_pos.y / camera_dir.y
world_pos = camera_pos + t * camera_dir
cell = Vector2i(floor(world_pos.x / CELL_SIZE), floor(world_pos.z / CELL_SIZE))
```

半分辨率适配：取 `camera.get_parent().get_parent()`（SubViewportContainer），用 `get_local_mouse_position()`，若 `stretch_shrink==2` 则除以 2。

### 墙朝向的格子边缘判定

格子 (x,y) 有 4 条边。鼠标点击时，比较交点在格子内的相对位置：
- 距北边（z 更小）最近 → direction=north
- 距南边最近 → south
- 距东边（x 更大）最近 → east
- 距西边最近 → west

墙段位置用 WallBuilder 现有 `_get_edge_position`/`_get_edge_rotation`（它们本来就按 direction 算），数据层补上 direction 即可正确工作。

### 笔刷预览

`_forward_3d_draw_over_viewport(viewport_control)` 在鼠标位置画方框预览，高亮当前格子/边缘。

## 数据格式变更

### walls

```json
// 旧（无 direction，bug 根因）
{"x": 5, "y": 0, "type": "normal_wall"}

// 新
{"x": 5, "y": 0, "direction": "north", "type": "normal_wall"}
```

WallBuilder 改造：`_create_wall_segment` 优先用 wall 里的 direction；无 direction 时（旧数据兼容）维持原行为。

### entities

```json
// 旧
{"type": "enemy_spawn", "x": 12, "y": 10, "group": "normal"}

// 新
{"type": "enemy_spawn", "x": 12, "y": 10, "monster_id": "slime"}
```

RoomData.load_from_dict：monster_id 可选，缺失时为空字符串。group 字段保留兼容旧数据。

### 运行时对接

enemy_spawner.gd 改造：生成敌人时若有 monster_id，用 `IronEaterCreator.load_monster(monster_id)` 加载 MonsterData，按其属性生成；无 monster_id 时维持原逻辑。

## 文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `addons/iron_studio/plugin.gd` | 改 | 加 `_forward_3d_gui_input` + `_handles` + `set_input_event_forwarding_always_enabled` + 笔刷逻辑 |
| `addons/iron_studio/panels/room_dock.gd` | 新建 | 工具栏脚本 |
| `addons/iron_studio/panels/room_dock.tscn` | 新建 | 工具栏场景 |
| `addons/iron_studio/room_editor_core.gd` | 新建 | 节点树↔JSON 转换、格子计算、笔刷操作 |
| `scenes/rooms/room_editor.tscn` | 新建 | 编辑专用场景 |
| `world/rooms/wall_builder.gd` | 改 | 支持 direction 字段 |
| `data/rooms/room_data.gd` | 改 | load_from_dict/to_dict 支持 direction + monster_id |
| `gameplay/enemies/enemy_spawner.gd` | 改 | 支持 monster_id 加载 MonsterData |
| `addons/iron_studio/panels/room_launcher.gd` | 删除 | 被 room_dock 替代 |
| `addons/iron_studio/panels/room_launcher.tscn` | 删除 | 被 room_dock 替代 |
| `addons/iron_studio/panels/room_preview.gd` | 删除 | 废弃 |
| `scenes/rooms/room_preview.tscn` | 删除 | 废弃 |
| `addons/iron_studio/studio_tabs.tscn` | 改 | "房间"标签页换为 room_dock |

## 验证

1. **headless 解析**：`Godot --headless --path . --quit` 0 错误
2. **gdlint**：所有新/改 .gd 通过
3. **编辑器 GUI**（godot-ai MCP）：
   - dock "房间"标签页显示工具栏，工具按钮齐全
   - 加载 room_02 → room_editor.tscn 打开，显示地板+墙（朝向正确）+门+刷怪点
   - 地板笔刷点击涂地板，3D 实时更新
   - 墙-边缘笔刷点击格子边缘，墙段朝向正确
   - 刷怪笔刷放点，下拉选怪物绑定
   - 保存后重新加载，数据一致
4. **数据兼容**：旧 room JSON（无 direction/monster_id）能加载不报错
