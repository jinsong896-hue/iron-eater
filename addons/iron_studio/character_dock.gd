@tool
extends Control
## 角色编辑器面板 —— 创建/编辑/预览角色数据
## 文档：ai/框架相关.md Character Studio

const DATA_DIR := "res://data/characters"
const CharacterDataScript := preload("res://core/data/character_data.gd")
const FormDataScript := preload("res://core/data/form_data.gd")
const SkillDataScript := preload("res://core/data/skill_data.gd")
const ModifierDataScript := preload("res://core/data/modifier_data.gd")
const StatsDataScript := preload("res://core/data/stats_data.gd")

var _editor_interface: EditorInterface = null

@onready var _char_list: ItemList = $Main/HSplit/CharList/VBox/List
@onready var _name_input: LineEdit = $Main/HSplit/EditPanel/Scroll/VBox/Identity/NameInput
@onready var _class_opt: OptionButton = $Main/HSplit/EditPanel/Scroll/VBox/Identity/ClassOpt
@onready var _res_name: LineEdit = $Main/HSplit/EditPanel/Scroll/VBox/Identity/ResName
@onready var _res_max: SpinBox = $Main/HSplit/EditPanel/Scroll/VBox/Identity/ResMax
@onready var _hp_spin: SpinBox = $Main/HSplit/EditPanel/Scroll/VBox/Stats/HP
@onready var _atk_spin: SpinBox = $Main/HSplit/EditPanel/Scroll/VBox/Stats/ATK
@onready var _def_spin: SpinBox = $Main/HSplit/EditPanel/Scroll/VBox/Stats/DEF
@onready var _spd_spin: SpinBox = $Main/HSplit/EditPanel/Scroll/VBox/Stats/SPD
@onready var _form_list: ItemList = $Main/HSplit/EditPanel/Scroll/VBox/Forms/FormList
@onready var _form_name: LineEdit = $Main/HSplit/EditPanel/Scroll/VBox/Forms/FormName
@onready var _form_floor: SpinBox = $Main/HSplit/EditPanel/Scroll/VBox/Forms/FormFloor
@onready var _status: Label = $Main/HSplit/EditPanel/Scroll/VBox/Status


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	_refresh_list()


func _refresh_list() -> void:
	_char_list.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			_char_list.add_item(f.trim_suffix(".tres"))
		f = dir.get_next()
	dir.list_dir_end()


func _show(msg: String) -> void:
	_status.text = msg
	print("[IronStudio] ", msg)


## ---- 按钮 ----

func _on_new_pressed() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("请输入角色名称")
		return
	var data := CharacterData.new()
	data.char_id = name_str.to_lower()
	data.char_name = name_str
	data.class_type = _class_opt.get_item_text(_class_opt.selected)
	data.resource_name = _res_name.text
	data.resource_max = int(_res_max.value)
	var stats := StatsData.new()
	stats.hp = _hp_spin.value; stats.atk = _atk_spin.value; stats.defense = _def_spin.value
	stats.spd = _spd_spin.value
	data.base_stats = stats
	DirAccess.make_dir_recursive_absolute(DATA_DIR)
	ResourceSaver.save(data, DATA_DIR + "/" + name_str.to_lower() + ".tres")
	_show("已创建角色: %s" % name_str)
	_refresh_list()


func _on_load_pressed() -> void:
	var sel := _char_list.get_selected_items()
	if sel.is_empty():
		return
	var name_str := _char_list.get_item_text(sel[0])
	var data: CharacterData = load(DATA_DIR + "/" + name_str + ".tres")
	if data == null:
		_show("加载失败")
		return
	_name_input.text = data.char_name
	_class_opt.select(_class_opt.get_item_index(_class_id(data.class_type)))
	_res_name.text = data.resource_name
	_res_max.value = data.resource_max
	if data.base_stats:
		_hp_spin.value = data.base_stats.hp
		_atk_spin.value = data.base_stats.atk
		_def_spin.value = data.base_stats.defense
		_spd_spin.value = data.base_stats.spd
	_form_list.clear()
	for f in data.forms:
		_form_list.add_item("%s (第%d层)" % [f.form_name, f.unlock_floor])
	_show("已加载: %s (%d形态)" % [data.char_name, data.forms.size()])


func _on_save_pressed() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("请输入角色名称")
		return
	var data := CharacterData.new()
	data.char_id = name_str.to_lower()
	data.char_name = name_str
	data.class_type = _class_opt.get_item_text(_class_opt.selected)
	data.resource_name = _res_name.text
	data.resource_max = int(_res_max.value)
	var stats := StatsData.new()
	stats.hp = _hp_spin.value; stats.atk = _atk_spin.value; stats.defense = _def_spin.value
	stats.spd = _spd_spin.value
	data.base_stats = stats
	var loaded: CharacterData = load(DATA_DIR + "/" + name_str.to_lower() + ".tres")
	if loaded:
		data.forms = loaded.forms
	ResourceSaver.save(data, DATA_DIR + "/" + name_str.to_lower() + ".tres")
	_show("已保存: %s" % name_str)
	_refresh_list()


func _on_add_form_pressed() -> void:
	var name_str := _form_name.text.strip_edges()
	if name_str.is_empty():
		_show("请输入形态名称")
		return
	var form := FormData.new()
	form.form_id = name_str.to_lower()
	form.form_name = name_str
	form.unlock_floor = int(_form_floor.value)
	_form_list.add_item("%s (第%d层)" % [name_str, form.unlock_floor])
	_show("已添加形态: %s" % name_str)


func _class_id(text: String) -> int:
	match text:
		"战士": return 0
		"法师": return 1
		"猎人": return 2
		"武僧": return 3
		"判官": return 4
	return 0
ENDOFFILE