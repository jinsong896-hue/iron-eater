@tool
extends Control
## 房间编辑器工具栏 —— 3D 笔刷编辑的 UI 控制面板
## 只负责工具选择和房间文件管理，实际编辑逻辑在 plugin.gd + room_editor_core.gd

const SAVE_DIR := "res://data/rooms/"
const MONSTER_DIR := "res://data/monsters/"

var _plugin: EditorPlugin = null

# 刷怪点配置
var _spawn_type := "enemy_spawn"
var _spawn_monster_id := ""

# 房间原 tags（加载时读出，保存时透传）
var _room_tags: Array = []

# 当前地板笔刷类型（矩形填充/涂地板共用）
var _floor_type := "stone"


## studio_tabs 调用：传入 editor_interface
func setup(editor_interface: EditorInterface) -> void:
	_refresh_monster_list()
	_refresh_room_list()


## plugin._enter_tree 调用：绑定插件引用
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


# ============================================================
# 工具选择
# ============================================================

## 各工具按钮回调（对应 RoomEditorCore.Tool 枚举）
## 枚举：FLOOR=0, RECT_FILL=1, WALL_EDGE=2, WALL_CELL=3, WALL_LINE=4,
##       DOOR=5, SPAWN=6, ERASER=7
func _on_floor_btn_pressed() -> void: _on_tool_selected(0)
func _on_rect_fill_btn_pressed() -> void: _on_tool_selected(1)
func _on_wall_edge_btn_pressed() -> void: _on_tool_selected(2)
func _on_wall_cell_btn_pressed() -> void: _on_tool_selected(3)
func _on_wall_line_btn_pressed() -> void: _on_tool_selected(4)
func _on_door_btn_pressed() -> void: _on_tool_selected(5)
func _on_spawn_btn_pressed() -> void: _on_tool_selected(6)
func _on_eraser_btn_pressed() -> void: _on_tool_selected(7)


## 选中工具按钮时调用
func _on_tool_selected(tool_idx: int) -> void:
	if _plugin == null or not _plugin.has_method("set_tool"):
		return
	# tool_idx 对应 RoomEditorCore.Tool 枚举顺序
	_plugin.set_tool(tool_idx)
	_show_tool_hint(tool_idx)
	highlight_tool(tool_idx)


## 高亮指定工具按钮（数字键切换时由 plugin 回调）
func highlight_tool(tool_idx: int) -> void:
	var grid := get_node_or_null("Scroll/VBox/ToolSection/ToolGrid")
	if grid == null:
		return
	var buttons := [
		"FloorBtn", "RectFillBtn", "WallEdgeBtn", "WallCellBtn",
		"WallLineBtn", "DoorBtn", "SpawnBtn", "EraserBtn",
	]
	for i in buttons.size():
		var btn := grid.get_node_or_null(buttons[i]) as Button
		if btn:
			btn.button_pressed = i == tool_idx
	_show_tool_hint(tool_idx)


func _show_tool_hint(tool_idx: int) -> void:
	var hints := {
		0: "地板：左键涂地板，右键擦除；材质用下方下拉选择",
		1: "矩形填充：拖一个矩形框填充地板，右键拖动清除",
		2: "墙-边缘：点击格子边缘放墙，朝向由边缘决定",
		3: "墙-格内：点击格子放墙，R 键旋转朝向",
		4: "墙-拖线：拖拽画一排墙（L 形路径：先横后纵）",
		5: "门：点击格子边缘放门（放在房间边界）",
		6: "刷怪点：点击放刷怪点，绑定下方选中的怪物",
		7: "橡皮擦：点击/拖动删除该格所有元素",
	}
	var hint := hints.get(tool_idx, "") as String
	var label := get_node_or_null("%ToolHint") as Label
	if label:
		label.text = hint


# ============================================================
# 地板材质
# ============================================================

## 地板材质下拉变化
func _on_floor_type_selected(idx: int) -> void:
	var opt := get_node_or_null("%FloorType") as OptionButton
	if opt == null:
		return
	var types := ["stone", "wood", "grass"]
	_floor_type = types[mini(idx, types.size() - 1)]
	if _plugin != null and _plugin.has_method("set_floor_type"):
		_plugin.set_floor_type(_floor_type)


# ============================================================
# 坐标放置（单点/两点矩形，全部元素）
# ============================================================

## P 键取点循环状态：0=单点 1=矩形起点 2=矩形终点
var _pick_slot := 0

## 坐标元素类型 → 内部标识
func _coord_element() -> String:
	var opt := get_node_or_null("%CoordElement") as OptionButton
	if opt == null:
		return "floor"
	return ["floor", "wall", "door", "spawn"][mini(opt.selected, 3)]


## 坐标朝向下拉 → 方向字符串
func _coord_direction() -> String:
	var opt := get_node_or_null("%CoordDirection") as OptionButton
	if opt == null:
		return "north"
	return ["north", "east", "south", "west"][mini(opt.selected, 3)]


## 单点放置按钮
func _on_coord_single_pressed() -> void:
	if _plugin == null or not _plugin.has_method("place_at_coord"):
		_show_status("插件未就绪")
		return
	var x := _spin_value("%SingleX")
	var y := _spin_value("%SingleY")
	var result: Dictionary = _plugin.place_at_coord(
		Vector2i(x, y), _coord_element(), _coord_direction(),
		_floor_type, _spawn_type, _spawn_monster_id
	)
	_show_status(result.get("msg", "已放置"))


## 矩形生成按钮
func _on_coord_rect_pressed() -> void:
	if _plugin == null or not _plugin.has_method("place_rect_at_coords"):
		_show_status("插件未就绪")
		return
	var x1 := _spin_value("%RectX1")
	var y1 := _spin_value("%RectY1")
	var x2 := _spin_value("%RectX2")
	var y2 := _spin_value("%RectY2")
	var result: Dictionary = _plugin.place_rect_at_coords(
		Vector2i(x1, y1), Vector2i(x2, y2), _coord_element(),
		_coord_direction(), _floor_type, _spawn_type, _spawn_monster_id
	)
	_show_status(result.get("msg", "已生成"))


## P 键取点回调（plugin 调用）：按 单点→矩形1→矩形2 循环填入
func fill_coord_from_pick(cell: Vector2i) -> void:
	match _pick_slot:
		0:
			_set_spin("%SingleX", cell.x)
			_set_spin("%SingleY", cell.y)
			_show_status("取点→单点 (%d,%d)" % [cell.x, cell.y])
			_pick_slot = 1
		1:
			_set_spin("%RectX1", cell.x)
			_set_spin("%RectY1", cell.y)
			_show_status("取点→矩形起点 (%d,%d)" % [cell.x, cell.y])
			_pick_slot = 2
		2:
			_set_spin("%RectX2", cell.x)
			_set_spin("%RectY2", cell.y)
			_show_status("取点→矩形终点 (%d,%d)" % [cell.x, cell.y])
			_pick_slot = 0


## 读 SpinBox 值
func _spin_value(path: String) -> int:
	var sp := get_node_or_null(path) as SpinBox
	return int(sp.value) if sp else 0


## 写 SpinBox 值
func _set_spin(path: String, value: int) -> void:
	var sp := get_node_or_null(path) as SpinBox
	if sp:
		sp.value = value


# ============================================================
# 快捷操作
# ============================================================

## 自动围墙：四周放墙，门位置自动留洞
func _on_auto_wall_pressed() -> void:
	if _plugin == null or not _plugin.has_method("auto_walls"):
		_show_status("插件未就绪")
		return
	var meta := _collect_meta()
	var result: Dictionary = _plugin.auto_walls(meta)
	_show_status("自动围墙：%s" % result.get("msg", "完成"))


## 校验房间：地板覆盖/门越界/spawn 撞墙
func _on_validate_pressed() -> void:
	if _plugin == null or not _plugin.has_method("validate_room"):
		_show_status("插件未就绪")
		return
	var meta := _collect_meta()
	var issues: Array = _plugin.validate_room(meta)
	var vr := get_node_or_null("%ValidateResult") as Label
	if issues.is_empty():
		if vr:
			vr.text = "房间校验通过：无问题"
			vr.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		_show_status("校验通过")
	else:
		var text := "发现问题 %d 项：\n" % issues.size()
		for issue in issues:
			text += "- %s\n" % issue
		if vr:
			vr.text = text
			vr.add_theme_color_override("font_color", Color(0.95, 0.55, 0.3))
		_show_status("校验发现 %d 个问题" % issues.size())


# ============================================================
# 刷怪点配置
# ============================================================

## 刷怪类型下拉变化
func _on_spawn_type_selected(idx: int) -> void:
	var opt := get_node_or_null("%SpawnType") as OptionButton
	if opt == null:
		return
	var types := ["enemy_spawn", "elite_spawn", "boss_spawn", "chest_spawn", "player_spawn"]
	_spawn_type = types[mini(idx, types.size() - 1)]
	_apply_spawn_config()


## 怪物下拉变化
func _on_monster_selected(idx: int) -> void:
	var opt := get_node_or_null("%MonsterList") as OptionButton
	if opt == null:
		return
	# idx=0 是"无绑定"，其余是怪物 ID
	_spawn_monster_id = "" if idx == 0 else opt.get_item_text(idx)
	_apply_spawn_config()


func _apply_spawn_config() -> void:
	if _plugin == null or not _plugin.has_method("set_spawn_config"):
		return
	_plugin.set_spawn_config(_spawn_type, _spawn_monster_id)


## 刷新怪物列表（读 data/monsters/*.tres）
func _refresh_monster_list() -> void:
	var opt := get_node_or_null("%MonsterList") as OptionButton
	if opt == null:
		return
	opt.clear()
	opt.add_item("（无绑定）", 0)
	var dir := DirAccess.open(MONSTER_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			opt.add_item(f.trim_suffix(".tres"))
		f = dir.get_next()
	dir.list_dir_end()


# ============================================================
# 房间文件管理
# ============================================================

## 刷新房间列表
func _refresh_room_list() -> void:
	var rl := get_node_or_null("%RoomList") as ItemList
	if rl == null:
		return
	rl.clear()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json") and not dir.current_is_dir():
			rl.add_item(f.trim_suffix(".json"))
		f = dir.get_next()
	dir.list_dir_end()


## 加载选中房间
func _on_load_pressed() -> void:
	var path := _get_selected_room_path()
	if path.is_empty():
		_show_status("请先选中房间")
		return
	if _plugin == null or not _plugin.has_method("load_room"):
		_show_status("插件未就绪")
		return
	# 读取房间元信息填入面板
	_read_room_meta(path)
	_plugin.load_room(path)
	_update_current_room_label()
	_show_status("已加载: %s" % path.get_file())


## 更新当前房间显示
func _update_current_room_label() -> void:
	var label := get_node_or_null("%CurrentRoom") as Label
	if label == null:
		return
	var ni := get_node_or_null("%NameInput") as LineEdit
	var name_str := ni.text.strip_edges() if ni else ""
	if name_str.is_empty():
		label.text = "（未加载房间）"
	else:
		label.text = "当前编辑：%s" % name_str


## 保存房间
func _on_save_pressed() -> void:
	var ni := get_node_or_null("%NameInput") as LineEdit
	var name_str := ni.text.strip_edges() if ni else "room_new"
	if name_str.is_empty():
		_show_status("请输入房间名")
		return
	if _plugin == null or not _plugin.has_method("save_room"):
		_show_status("插件未就绪")
		return
	var meta := _collect_meta()
	var path := SAVE_DIR + name_str + ".json"
	_plugin.save_room(path, meta)
	_show_status("已保存: %s" % path)
	_refresh_room_list()


## 新建空房间
func _on_new_pressed() -> void:
	if _plugin == null or not _plugin.has_method("new_room"):
		_show_status("插件未就绪")
		return
	_plugin.new_room()
	_room_tags = []
	_update_current_room_label()
	_show_status("已新建空房间")


## 删除选中房间
func _on_delete_pressed() -> void:
	var path := _get_selected_room_path()
	if path.is_empty():
		_show_status("请先选中房间")
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_show_status("已删除")
	_refresh_room_list()


## 应用尺寸
func _on_resize_pressed() -> void:
	if _plugin == null or not _plugin.has_method("resize_room"):
		_show_status("插件未就绪")
		return
	var meta := _collect_meta()
	_plugin.resize_room(meta)
	_show_status("尺寸已更新")


# ============================================================
# 辅助
# ============================================================

## 获取列表选中的房间路径
func _get_selected_room_path() -> String:
	var rl := get_node_or_null("%RoomList") as ItemList
	if rl == null:
		return ""
	var sel := rl.get_selected_items()
	if sel.is_empty():
		return ""
	var name_str := rl.get_item_text(sel[0])
	return SAVE_DIR + name_str + ".json"


## 读取房间 JSON 的元信息填入面板
func _read_room_meta(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var data = json.data
	var ni := get_node_or_null("%NameInput") as LineEdit
	var ws := get_node_or_null("%WidthSpin") as SpinBox
	var hs := get_node_or_null("%HeightSpin") as SpinBox
	var to := get_node_or_null("%TypeOption") as OptionButton
	var fl := get_node_or_null("%FloorType") as OptionButton
	if ni:
		ni.text = str(data.get("id", "room_new"))
	if ws:
		ws.value = int(data.get("width", 20))
	if hs:
		hs.value = int(data.get("height", 15))
	if to:
		var types := ["start", "normal", "elite", "treasure", "boss"]
		var rt := str(data.get("room_type", "normal"))
		var idx := types.find(rt)
		to.selected = idx if idx >= 0 else 1
	if fl:
		var floor_types := ["stone", "wood", "grass"]
		var ft := str(data.get("editor_floor_type", "stone"))
		var fidx := floor_types.find(ft)
		fl.selected = fidx if fidx >= 0 else 0
	# 保留原 tags（保存时透传，防止编辑器覆盖）
	_room_tags = data.get("tags", [])


## 收集面板上的房间元信息
func _collect_meta() -> Dictionary:
	var ni := get_node_or_null("%NameInput") as LineEdit
	var ws := get_node_or_null("%WidthSpin") as SpinBox
	var hs := get_node_or_null("%HeightSpin") as SpinBox
	var to := get_node_or_null("%TypeOption") as OptionButton
	var fl := get_node_or_null("%FloorType") as OptionButton
	var types := ["start", "normal", "elite", "treasure", "boss"]
	var tidx := to.selected if to else 1
	if fl:
		var floor_types := ["stone", "wood", "grass"]
		_floor_type = floor_types[fl.selected] if fl.selected >= 0 else "stone"
	var meta := {
		"id": ni.text.strip_edges() if ni else "room_new",
		"room_type": types[tidx] if tidx >= 0 and tidx < types.size() else "normal",
		"width": int(ws.value) if ws else 20,
		"height": int(hs.value) if hs else 15,
		"theme": "crypt",
		"editor_floor_type": _floor_type,
	}
	# tags 透传（有原 tags 用原的，否则按房间类型生成）
	if not _room_tags.is_empty():
		meta["tags"] = _room_tags
	return meta


func _show_status(msg: String) -> void:
	var st := get_node_or_null("%Status") as Label
	if st:
		st.text = msg
	print("[RoomDock] ", msg)
