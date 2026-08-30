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
func _on_floor_btn_pressed() -> void: _on_tool_selected(0)
func _on_wall_edge_btn_pressed() -> void: _on_tool_selected(1)
func _on_wall_cell_btn_pressed() -> void: _on_tool_selected(2)
func _on_wall_line_btn_pressed() -> void: _on_tool_selected(3)
func _on_door_btn_pressed() -> void: _on_tool_selected(4)
func _on_spawn_btn_pressed() -> void: _on_tool_selected(5)
func _on_eraser_btn_pressed() -> void: _on_tool_selected(6)


## 选中工具按钮时调用
func _on_tool_selected(tool_idx: int) -> void:
	if _plugin == null or not _plugin.has_method("set_tool"):
		return
	# tool_idx 对应 RoomEditorCore.Tool 枚举顺序
	_plugin.set_tool(tool_idx)
	_show_tool_hint(tool_idx)


func _show_tool_hint(tool_idx: int) -> void:
	var hints := {
		0: "地板：左键涂地板，右键擦除",
		1: "墙-边缘：点击格子边缘放墙，朝向由边缘决定",
		2: "墙-格内：点击格子放墙，R 键旋转朝向",
		3: "墙-拖线：拖拽画一排墙，自动判断朝向",
		4: "门：点击格子边缘放门",
		5: "刷怪点：点击放刷怪点，绑定下方选中的怪物",
		6: "橡皮擦：点击删除该格所有元素",
	}
	var hint := hints.get(tool_idx, "") as String
	var label := get_node_or_null("%ToolHint") as Label
	if label:
		label.text = hint


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
	_show_status("已加载: %s" % path.get_file())


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


## 收集面板上的房间元信息
func _collect_meta() -> Dictionary:
	var ni := get_node_or_null("%NameInput") as LineEdit
	var ws := get_node_or_null("%WidthSpin") as SpinBox
	var hs := get_node_or_null("%HeightSpin") as SpinBox
	var to := get_node_or_null("%TypeOption") as OptionButton
	var types := ["start", "normal", "elite", "treasure", "boss"]
	var tidx := to.selected if to else 1
	return {
		"id": ni.text.strip_edges() if ni else "room_new",
		"room_type": types[tidx] if tidx >= 0 and tidx < types.size() else "normal",
		"width": int(ws.value) if ws else 20,
		"height": int(hs.value) if hs else 15,
		"theme": "crypt",
	}


func _show_status(msg: String) -> void:
	var st := get_node_or_null("%Status") as Label
	if st:
		st.text = msg
	print("[RoomDock] ", msg)
