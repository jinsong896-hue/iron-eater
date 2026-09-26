class_name ArtBrowser
extends Control
## 美术资源浏览器（游戏内）—— 边玩边换模型，立即看到效果
##
## ## 与编辑器面板的关系
##
## 两者**共用同一份数据**（`data/art/default_profile.tres`）与同一个
## 预览组件（`ui/art/model_preview.gd`）。区别只在：
##   · 编辑器面板：批量配置、保存落盘（`ResourceSaver.save`）
##   · 本界面：快速试效果、**改完立即生效**（`ArtRegistry.set_profile` + 重建房间）
##
## ## 呼出
##
## `F2`（`debug_panel` 占了 F1、`debug_console` 占了小键盘 0）。
##
## ## 为什么不落盘
##
## 游戏内改的是**内存里的 profile**。想保留就按「导出到编辑器」——
## 但那需要重新加载关卡，且运行时写资源文件在导出后的游戏里不可用。
## 故本界面定位是「试」，定稿用编辑器面板。

const PROFILE_PATH := "res://data/art/default_profile.tres"
const MODEL_DIR := "res://assets/castle-kit/Models/GLB format"
const MODAL_GROUP := "modal_ui"

var _profile: ArtProfile = null
var _selected := ""

var _list: ItemList = null
var _preview: ModelPreview = null
var _model_picker: OptionButton = null
var _scale_spin: SpinBox = null
var _offset_spin: SpinBox = null
var _rot_spin: SpinBox = null
var _status: Label = null

var _model_files: Array[String] = []


func _ready() -> void:
	# **必须 ALWAYS**：`open()` 会把 `get_tree().paused` 设成 true，
	# 若本节点随暂停一起停处理，就再也收不到关闭按键了。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_scan_models()
	_load_profile()
	_refresh_list()
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("art_browser"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and (event.is_action_pressed("pause")
			or event.is_action_pressed("toggle_inventory")):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	show()
	add_to_group(MODAL_GROUP)
	get_tree().paused = true
	_refresh_list()


func close() -> void:
	hide()
	remove_from_group(MODAL_GROUP)
	get_tree().paused = false


# ============================================================
# UI
# ============================================================

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 背景遮罩
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.02, 0.03, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	var title := Label.new()
	title.text = "美术资源浏览器    [F2 关闭]"
	root.add_child(title)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 160
	root.add_child(split)

	# 左：用途列表
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 150
	split.add_child(left)
	var lt := Label.new()
	lt.text = "装饰用途"
	left.add_child(lt)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	left.add_child(_list)

	# 右：预览 + 表单
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	_preview = ModelPreview.new()
	_preview.custom_minimum_size = Vector2(300, 300)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_preview)

	var reset := Button.new()
	reset.text = "重置视角"
	reset.pressed.connect(func(): _preview.reset_view())
	right.add_child(reset)

	_model_picker = OptionButton.new()
	_model_picker.item_selected.connect(_on_model_picked)
	right.add_child(_model_picker)

	var grid := GridContainer.new()
	grid.columns = 2
	right.add_child(grid)
	grid.add_child(_mk_label("缩放"))
	_scale_spin = _mk_spin(0.05, 10.0, 0.05)
	_scale_spin.value_changed.connect(_on_transform_changed)
	grid.add_child(_scale_spin)
	grid.add_child(_mk_label("抬升 (米)"))
	_offset_spin = _mk_spin(-2.0, 4.0, 0.05)
	_offset_spin.value_changed.connect(_on_transform_changed)
	grid.add_child(_offset_spin)
	grid.add_child(_mk_label("朝向 (度)"))
	_rot_spin = _mk_spin(-180.0, 180.0, 5.0)
	_rot_spin.value_changed.connect(_on_transform_changed)
	grid.add_child(_rot_spin)

	var row := HBoxContainer.new()
	right.add_child(row)
	var apply := Button.new()
	apply.text = "应用到当前房间"
	apply.pressed.connect(_on_apply_pressed)
	row.add_child(apply)
	var reload := Button.new()
	reload.text = "重新载入配置"
	reload.pressed.connect(_on_reload_pressed)
	row.add_child(reload)

	_status = Label.new()
	_status.text = "改完点「应用到当前房间」立即看到效果"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func _mk_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _mk_spin(mn: float, mx: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


# ============================================================
# 数据
# ============================================================

func _scan_models() -> void:
	_model_files.clear()
	var d := DirAccess.open(MODEL_DIR)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".glb"):
			_model_files.append(MODEL_DIR + "/" + f)
		f = d.get_next()
	d.list_dir_end()
	_model_files.sort()
	_model_picker.clear()
	_model_picker.add_item("（未配置）")
	for p in _model_files:
		_model_picker.add_item(p.get_file().trim_suffix(".glb"))


func _load_profile() -> void:
	_profile = ArtRegistry.profile()
	if _profile == null:
		_profile = ArtProfile.new()


func _refresh_list() -> void:
	_list.clear()
	if _profile == null:
		return
	var names := {}
	for k in _profile.configured_props():
		names[str(k)] = true
	# 房间 JSON 里实际用到的类型也列出来（未配置的会走占位体）
	for t in _room_prop_types():
		names[t] = true
	var sorted: Array = names.keys()
	sorted.sort()
	for n in sorted:
		var configured := not _profile.prop_model(str(n)).is_empty()
		_list.add_item(("● " if configured else "○ ") + str(n))
		_list.set_item_metadata(_list.item_count - 1, str(n))


## 当前房间实际用到的装饰类型（让列表反映真实需求）
func _room_prop_types() -> Array:
	var out: Array = []
	for r in _all_rooms():
		var data = r.get("room_data")
		if data == null:
			continue
		for e in data.get("entities", []):
			var t := str(e.get("type", ""))
			if not t.is_empty() and not (t in out):
				out.append(t)
	return out


## 场景里的全部房间节点
##
## **用 `room_controller` 组**：`room_builder` 本身不加组，实际入组的是
## `room_controller`（`room_controller.gd:149`），它持有 `room_data`。
func _all_rooms() -> Array:
	return get_tree().get_nodes_in_group("current_room_controller")


# ============================================================
# 交互
# ============================================================

func _on_item_selected(idx: int) -> void:
	_selected = str(_list.get_item_metadata(idx))
	_sync_form_from(_selected)


func _sync_form_from(prop_type: String) -> void:
	var cfg := _profile.prop(prop_type)
	var path := str(cfg.get("model_path", ""))
	_scale_spin.set_value_no_signal(float(cfg.get("scale", 1.0)))
	_offset_spin.set_value_no_signal(float(cfg.get("y_offset", 0.0)))
	_rot_spin.set_value_no_signal(float(cfg.get("y_rotation_deg", 0.0)))
	_model_picker.select(0)
	for i in _model_files.size():
		if _model_files[i] == path:
			_model_picker.select(i + 1)
			break
	if path.is_empty():
		_preview.clear()
	else:
		_preview.show_model(path)


func _on_model_picked(idx: int) -> void:
	if _selected.is_empty():
		_status.text = "请先选一个用途"
		return
	var path := "" if idx == 0 else _model_files[idx - 1]
	if path.is_empty():
		_profile.clear_prop(_selected)
		_preview.clear()
		_status.text = "已取消「%s」的配置" % _selected
	else:
		if not _preview.show_model(path):
			_status.text = "⚠ 模型加载失败：%s" % path
			return
		_apply_form_to_profile(path)
		_status.text = "已选：%s（点「应用」生效）" % path.get_file()
	_refresh_list()


func _on_transform_changed(_v: float) -> void:
	if _selected.is_empty():
		return
	var path := _profile.prop_model(_selected)
	if not path.is_empty():
		_apply_form_to_profile(path)


func _apply_form_to_profile(path: String) -> void:
	_profile.set_prop(_selected, path,
		_scale_spin.value, _offset_spin.value, _rot_spin.value)


## 把改动推给注册表，并重建当前房间的装饰
func _on_apply_pressed() -> void:
	ArtRegistry.set_profile(_profile)
	var n := _rebuild_rooms()
	_status.text = "已应用（重建了 %d 个房间的装饰）" % n


func _on_reload_pressed() -> void:
	ArtRegistry.reload()
	_load_profile()
	_refresh_list()
	_status.text = "已从磁盘重新载入配置"


## 重建所有房间的装饰节点
##
## 做法：删掉 `$Props` 下所有子节点，再调 `DecorationBuilder.build`。
## **不重建整个房间**——那会连玩家/敌人一起重建，代价大且会打断游戏。
##
## `$Props` 是 `room_builder.gd:14` 声明的装饰挂载点，
## `DecorationBuilder.build(prop_root, data)` 把装饰全挂在那里，
## 故只需清空它即可，不必靠节点名猜哪些是装饰。
func _rebuild_rooms() -> int:
	var count := 0
	for r in _all_rooms():
		var data = r.get("room_data")
		if data == null:
			continue
		var room_node = r.get("room_node")
		var host: Node = room_node if room_node != null else r
		var props := host.get_node_or_null("Props")
		if not (props is Node3D):
			continue
		for c in props.get_children():
			c.queue_free()
		DecorationBuilder.build(props as Node3D, data)
		count += 1
	return count
