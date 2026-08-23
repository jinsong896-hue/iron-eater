@tool
extends Control
## 角色编辑器 —— 创建/编辑角色/形态/技能
## 文档：ai/框架相关.md Character Studio + Equipment Studio + Skill Studio

const DATA_DIR := "res://data/characters"
const FORMS_DIR := "res://data/forms"
const SKILLS_DIR := "res://data/skills"

var _editor_interface: EditorInterface = null
var _forms: Array[FormData] = []
var _skills: Array[SkillData] = []

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
@onready var _skill_list: ItemList = $Main/HSplit/EditPanel/Scroll/VBox/Skills/SkillList
@onready var _skill_name: LineEdit = $Main/HSplit/EditPanel/Scroll/VBox/Skills/SkillName
@onready var _skill_cd: SpinBox = $Main/HSplit/EditPanel/Scroll/VBox/Skills/SkillCD
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


## ---- 角色操作 ----

func _on_new_pressed() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("请输入角色名称")
		return
	_forms.clear()
	_skills.clear()
	_form_list.clear()
	_skill_list.clear()
	_save_character(name_str)
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
	# 基本
	_name_input.text = data.char_name
	for i in _class_opt.item_count:
		if _class_opt.get_item_text(i) == data.class_type:
			_class_opt.select(i)
			break
	_res_name.text = data.resource_name
	_res_max.value = data.resource_max
	# 属性
	if data.base_stats:
		_hp_spin.value = data.base_stats.hp
		_atk_spin.value = data.base_stats.atk
		_def_spin.value = data.base_stats.defense
		_spd_spin.value = data.base_stats.spd
	# 形态
	_forms = data.forms.duplicate()
	_refresh_form_list()
	_show("已加载: %s (%d形态)" % [data.char_name, _forms.size()])


func _on_save_pressed() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("请输入角色名称")
		return
	_save_character(name_str)
	_show("已保存: %s" % name_str)
	_refresh_list()


func _save_character(name_str: String) -> void:
	var data := CharacterData.new()
	data.char_id = name_str.to_lower()
	data.char_name = name_str
	data.class_type = _class_opt.get_item_text(_class_opt.selected)
	data.resource_name = _res_name.text
	data.resource_max = int(_res_max.value)
	var stats := StatsData.new()
	stats.hp = _hp_spin.value; stats.atk = _atk_spin.value
	stats.defense = _def_spin.value; stats.spd = _spd_spin.value
	data.base_stats = stats
	data.forms = _forms.duplicate()
	DirAccess.make_dir_recursive_absolute(DATA_DIR)
	ResourceSaver.save(data, DATA_DIR + "/" + name_str.to_lower() + ".tres")


## ---- 形态操作 ----

func _on_add_form_pressed() -> void:
	var name_str := _form_name.text.strip_edges()
	if name_str.is_empty():
		_show("请输入形态名称")
		return
	var form := FormData.new()
	form.form_id = name_str.to_lower()
	form.form_name = name_str
	form.unlock_floor = int(_form_floor.value)
	form.skills = _skills.duplicate()
	_forms.append(form)
	_refresh_form_list()
	_show("已添加形态: %s (第%d层, %d技能)" % [name_str, form.unlock_floor, _skills.size()])


func _on_remove_form_pressed() -> void:
	var sel := _form_list.get_selected_items()
	if sel.is_empty():
		return
	_forms.remove_at(sel[0])
	_refresh_form_list()
	_show("已删除形态")


func _refresh_form_list() -> void:
	_form_list.clear()
	for f in _forms:
		_form_list.add_item("%s (第%d层, %d技能)" % [f.form_name, f.unlock_floor, f.skills.size()])


## ---- 技能操作 ----

func _on_add_skill_pressed() -> void:
	var name_str := _skill_name.text.strip_edges()
	if name_str.is_empty():
		_show("请输入技能名称")
		return
	var skill := SkillData.new()
	skill.skill_id = name_str.to_lower()
	skill.skill_name = name_str
	skill.cooldown = _skill_cd.value
	_skills.append(skill)
	_refresh_skill_list()
	_show("已添加技能: %s (CD %.1fs)" % [name_str, skill.cooldown])


func _on_remove_skill_pressed() -> void:
	var sel := _skill_list.get_selected_items()
	if sel.is_empty():
		return
	_skills.remove_at(sel[0])
	_refresh_skill_list()
	_show("已删除技能")


func _refresh_skill_list() -> void:
	_skill_list.clear()
	for s in _skills:
		_skill_list.add_item("%s (CD %.1fs)" % [s.skill_name, s.cooldown])


## ---- 导出 ----

func _on_export_pressed() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("请输入角色名称")
		return
	_save_character(name_str)
	# 导出形态
	DirAccess.make_dir_recursive_absolute(FORMS_DIR)
	for f in _forms:
		ResourceSaver.save(f, FORMS_DIR + "/" + name_str.to_lower() + "_" + f.form_id + ".tres")
	_show("已导出角色+%d形态" % _forms.size())
ENDOFFILE