@tool
extends Control
## 美术资源管理器（编辑器面板）—— 把「用途 → 资源」可视化配置
##
## ## 解决什么
##
## 此前换一个装饰模型要改 `decoration_builder.gd` 的常量表、重启编辑器。
## 本面板让美术/策划直接在界面里选模型、调参数、保存。
##
## ## 界面
##
## ```
## ┌─ 用途列表 ──────┬─ 模型预览（3D，可拖拽旋转）─────────┐
## │ pillar          │                                    │
## │ torch           │  [拖拽旋转 / 滚轮缩放]  [重置视角]  │
## │ barrel          │                                    │
## │                 │  模型: castle-kit/.../wall.glb     │
## │ [+ 新增用途]    │  缩放: [1.00]  抬升: [0.00]        │
## │ [移除选中]      │  朝向: [0.0°]                      │
## │                 │  [选择模型 ▾]  [保存]  [还原]      │
## ├─────────────────┴────────────────────────────────────┤
## │ 状态栏                                                │
## └───────────────────────────────────────────────────────┘
## ```
##
## ## 保存
##
## 写 `res://data/art/default_profile.tres`（`ResourceSaver.save`），
## 与游戏内界面**共用同一份数据**——编辑器里改完，跑游戏即生效。

const PROFILE_PATH := "res://data/art/default_profile.tres"
const MODEL_DIR := "res://assets/castle-kit/Models/GLB format"

## 房间 JSON 里会出现的装饰类型（供「新增用途」的候选）
##
## 与 `decoration_builder.PROP_PATHS` 的键 + 常见房间实体类型对齐。
const KNOWN_PROP_TYPES := [
	"pillar", "torch", "barrel", "chest", "door", "statue",
	"rock", "tree", "fence", "banner", "gate",
]

var _editor_interface: EditorInterface = null

var _profile: ArtProfile = null
var _selected: String = ""

var _list: ItemList = null
var _preview: ModelPreview = null
var _model_label: Label = null
var _model_picker: OptionButton = null
var _scale_spin: SpinBox = null
var _offset_spin: SpinBox = null
var _rot_spin: SpinBox = null
var _new_type: LineEdit = null
var _status: Label = null

var _model_files: Array[String] = []   ## castle-kit 的全部模型路径


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface


func _ready() -> void:
	_build_ui()
	_scan_models()
	_load_profile()
	_refresh_list()


# ============================================================
# UI 构建
# ============================================================

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := HSplitContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.split_offset = 150
	add_child(root)

	# ---- 左：用途列表 ----
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 140
	root.add_child(left)

	var lt := Label.new()
	lt.text = "装饰用途"
	left.add_child(lt)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	left.add_child(_list)

	var add_row := HBoxContainer.new()
	left.add_child(add_row)
	_new_type = LineEdit.new()
	_new_type.placeholder_text = "新用途名"
	_new_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_new_type)
	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.tooltip_text = "新增用途"
	add_btn.pressed.connect(_on_add_pressed)
	add_row.add_child(add_btn)

	var del_btn := Button.new()
	del_btn.text = "移除选中"
	del_btn.pressed.connect(_on_remove_pressed)
	left.add_child(del_btn)

	# ---- 右：预览 + 表单 ----
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)

	_preview = ModelPreview.new()
	_preview.custom_minimum_size = Vector2(260, 260)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_preview)

	var reset_btn := Button.new()
	reset_btn.text = "重置视角"
	reset_btn.pressed.connect(func(): _preview.reset_view())
	right.add_child(reset_btn)

	var ml := Label.new()
	ml.text = "模型"
	right.add_child(ml)

	_model_label = Label.new()
	_model_label.text = "（未配置）"
	_model_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_model_label)

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

	var btn_row := HBoxContainer.new()
	right.add_child(btn_row)
	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(_on_save_pressed)
	btn_row.add_child(save_btn)
	var reload_btn := Button.new()
	reload_btn.text = "重新载入"
	reload_btn.pressed.connect(func(): _load_profile(); _refresh_list(); _show("已重新载入"))
	btn_row.add_child(reload_btn)
	var verify_btn := Button.new()
	verify_btn.text = "校验"
	verify_btn.pressed.connect(_on_verify_pressed)
	btn_row.add_child(verify_btn)

	_status = Label.new()
	_status.text = "就绪"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)


func _mk_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
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

## 扫描 castle-kit 全部模型，填进下拉框
func _scan_models() -> void:
	_model_files.clear()
	var d := DirAccess.open(MODEL_DIR)
	if d == null:
		_show("⚠ 打不开模型目录：%s" % MODEL_DIR)
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
	if ResourceLoader.exists(PROFILE_PATH):
		var r = load(PROFILE_PATH)
		_profile = r as ArtProfile
	if _profile == null:
		_profile = ArtProfile.new()


func _refresh_list() -> void:
	_list.clear()
	if _profile == null:
		return
	# 已配置的 + 常见类型（未配置的也列出来，方便直接点进去配）
	var names := {}
	for k in _profile.configured_props():
		names[str(k)] = true
	for k in KNOWN_PROP_TYPES:
		names[k] = true
	var sorted: Array = names.keys()
	sorted.sort()
	for n in sorted:
		var configured := not _profile.prop_model(str(n)).is_empty()
		_list.add_item(("● " if configured else "○ ") + str(n))
		_list.set_item_metadata(_list.item_count - 1, str(n))
		_list.set_item_tooltip(_list.item_count - 1,
			"已配置" if configured else "未配置（将走占位体）")


func _on_item_selected(idx: int) -> void:
	_selected = str(_list.get_item_metadata(idx))
	_sync_form_from(_selected)


## 把某用途的当前配置同步到表单 + 预览
func _sync_form_from(prop_type: String) -> void:
	if _profile == null:
		return
	var cfg := _profile.prop(prop_type)
	var path := str(cfg.get("model_path", ""))
	_model_label.text = path if not path.is_empty() else "（未配置 → 走占位体）"
	_scale_spin.set_value_no_signal(float(cfg.get("scale", 1.0)))
	_offset_spin.set_value_no_signal(float(cfg.get("y_offset", 0.0)))
	_rot_spin.set_value_no_signal(float(cfg.get("y_rotation_deg", 0.0)))

	# 下拉框选中对应项
	_model_picker.select(0)
	for i in _model_files.size():
		if _model_files[i] == path:
			_model_picker.select(i + 1)
			break

	if path.is_empty():
		_preview.clear()
	else:
		if not _preview.show_model(path):
			_show("⚠ 模型加载失败：%s" % path)


# ============================================================
# 交互
# ============================================================

func _on_model_picked(idx: int) -> void:
	if _selected.is_empty():
		_show("请先选一个用途")
		return
	var path := "" if idx == 0 else _model_files[idx - 1]
	if path.is_empty():
		_profile.clear_prop(_selected)
		_preview.clear()
		_model_label.text = "（未配置 → 走占位体）"
		_show("已取消配置（该用途将走占位体）")
	else:
		# 换模型后**重新取景**——不同模型的尺寸差很多
		if not _preview.show_model(path):
			_show("⚠ 模型加载失败：%s" % path)
			return
		_apply_form_to_profile(path)
		_model_label.text = path
		_show("已选：%s" % path.get_file())
	_refresh_list()


func _on_transform_changed(_v: float) -> void:
	if _selected.is_empty():
		return
	var path := _profile.prop_model(_selected)
	if path.is_empty():
		return
	_apply_form_to_profile(path)


func _apply_form_to_profile(path: String) -> void:
	_profile.set_prop(_selected, path,
		_scale_spin.value, _offset_spin.value, _rot_spin.value)


func _on_add_pressed() -> void:
	var n := _new_type.text.strip_edges()
	if n.is_empty():
		_show("请输入用途名")
		return
	_selected = n
	_new_type.text = ""
	_refresh_list()
	_show("已选中「%s」——从下方选一个模型即可配置" % n)


func _on_remove_pressed() -> void:
	if _selected.is_empty():
		_show("请先选中要移除的用途")
		return
	_profile.clear_prop(_selected)
	_preview.clear()
	_refresh_list()
	_show("已移除「%s」的配置" % _selected)


func _on_save_pressed() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/art")
	var err := ResourceSaver.save(_profile, PROFILE_PATH)
	if err != OK:
		_show("✗ 保存失败（错误码 %d）" % err)
		return
	# 让编辑器感知文件变化，否则资源面板不刷新
	if _editor_interface != null:
		_editor_interface.get_resource_filesystem().scan()
	_show("✓ 已保存 %d 个用途 → %s" % [_profile.configured_props().size(), PROFILE_PATH])


## 校验全部配置的模型能否真的加载
##
## **用 `load()` 而不是 `ResourceLoader.exists()`**——项目已知陷阱：
## `.import` 里 `valid=false` 的资源 `exists()` 返 true 但 `load()` 返 null。
func _on_verify_pressed() -> void:
	var bad := _profile.validate()
	if bad.is_empty():
		_show("✓ 全部 %d 个配置的模型均可加载" % _profile.configured_props().size())
		return
	var msg := "✗ %d 个模型加载失败：" % bad.size()
	for b in bad:
		msg += "\n  %s → %s" % [b["prop_type"], b["model_path"]]
	_show(msg)


func _show(msg: String) -> void:
	_status.text = msg
	print("[ArtStudio] ", msg)
