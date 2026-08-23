@tool
extends Control
## 角色编辑器 v3 —— 完整形态Modifier编辑 + Sprite + 技能选择
## 文档：ai/框架相关.md Character Studio

const DATA_DIR := "res://data/characters"
const FORMS_DIR := "res://data/forms"
const SKILLS_DIR := "res://data/skills"

var _editor_interface: EditorInterface = null
var _forms: Array[FormData] = []
var _skills: Array[SkillData] = []
var _available_skills: Array[String] = []

@onready var _char_list: ItemList = $Main/CharList/VBox/List
@onready var _name_input: LineEdit = $Main/EditPanel/Scroll/VBox/Identity/NameInput
@onready var _class_opt: OptionButton = $Main/EditPanel/Scroll/VBox/Identity/ClassOpt
@onready var _res_name: LineEdit = $Main/EditPanel/Scroll/VBox/Identity/ResName
@onready var _res_max: SpinBox = $Main/EditPanel/Scroll/VBox/Identity/ResMax
@onready var _sprite: LineEdit = $Main/EditPanel/Scroll/VBox/Identity/Sprite
@onready var _hp: SpinBox = $Main/EditPanel/Scroll/VBox/Stats/HP
@onready var _atk: SpinBox = $Main/EditPanel/Scroll/VBox/Stats/ATK
@onready var _def: SpinBox = $Main/EditPanel/Scroll/VBox/Stats/DEF
@onready var _spd: SpinBox = $Main/EditPanel/Scroll/VBox/Stats/SPD
@onready var _aspd: SpinBox = $Main/EditPanel/Scroll/VBox/Stats/ASPD
@onready var _crt: SpinBox = $Main/EditPanel/Scroll/VBox/Stats/CRT
@onready var _skill_list: ItemList = $Main/EditPanel/Scroll/VBox/Skills/SkillList
@onready var _avail_list: ItemList = $Main/EditPanel/Scroll/VBox/Skills/AvailList
@onready var _form_list: ItemList = $Main/EditPanel/Scroll/VBox/Forms/FormList
@onready var _form_name: LineEdit = $Main/EditPanel/Scroll/VBox/Forms/FormName
@onready var _form_floor: SpinBox = $Main/EditPanel/Scroll/VBox/Forms/FormFloor
@onready var _form_sp: LineEdit = $Main/EditPanel/Scroll/VBox/Forms/FormSprite
@onready var _mod_atk: SpinBox = $Main/EditPanel/Scroll/VBox/Forms/ModATK
@onready var _mod_hp: SpinBox = $Main/EditPanel/Scroll/VBox/Forms/ModHP
@onready var _mod_spd: SpinBox = $Main/EditPanel/Scroll/VBox/Forms/ModSPD
@onready var _status: Label = $Main/EditPanel/Scroll/VBox/Status


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface


func _ready() -> void:
	_refresh_list()
	_refresh_skill_pool()


func _refresh_list() -> void:
	_char_list.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null: return
	dir.list_dir_begin(); var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"): _char_list.add_item(f.trim_suffix(".tres"))
		f = dir.get_next()
	dir.list_dir_end()


func _refresh_skill_pool() -> void:
	_available_skills.clear(); _avail_list.clear()
	var dir := DirAccess.open(SKILLS_DIR)
	if dir == null: return
	dir.list_dir_begin(); var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			_available_skills.append(f.trim_suffix(".tres"))
			_avail_list.add_item(f.trim_suffix(".tres"))
		f = dir.get_next()
	dir.list_dir_end()


func _show(msg: String) -> void:
	_status.text = msg
	print("[IronStudio] ", msg)


## ---- 角色 ----

func _on_new_pressed() -> void:
	var n := _name_input.text.strip_edges()
	if n.is_empty(): _show("请输入名称"); return
	_forms.clear(); _skills.clear()
	_form_list.clear(); _skill_list.clear()
	_save_character(n); _show("已创建: %s" % n); _refresh_list()


func _on_load_pressed() -> void:
	var sel := _char_list.get_selected_items()
	if sel.is_empty(): return
	var n := _char_list.get_item_text(sel[0])
	var data: CharacterData = load(DATA_DIR + "/" + n + ".tres")
	if data == null: _show("加载失败"); return
	_name_input.text = data.char_name
	for i in _class_opt.item_count:
		if _class_opt.get_item_text(i) == data.class_type: _class_opt.select(i); break
	_res_name.text = data.res_name; _res_max.value = data.resource_max
	_sprite.text = data.sprite_path
	if data.base_stats:
		_hp.value = data.base_stats.hp; _atk.value = data.base_stats.atk
		_def.value = data.base_stats.defense; _spd.value = data.base_stats.spd
		_aspd.value = data.base_stats.aspd; _crt.value = data.base_stats.crt
	_forms = data.forms.duplicate(); _refresh_form_list()
	_show("已加载: %s (%d形态)" % [data.char_name, _forms.size()])


func _on_save_pressed() -> void:
	var n := _name_input.text.strip_edges()
	if n.is_empty(): _show("请输入名称"); return
	_save_character(n); _show("已保存: %s" % n); _refresh_list()


func _save_character(name_str: String) -> void:
	var data := CharacterData.new()
	data.char_id = name_str.to_lower(); data.char_name = name_str
	data.class_type = _class_opt.get_item_text(_class_opt.selected)
	data.res_name = _res_name.text; data.resource_max = int(_res_max.value)
	data.sprite_path = _sprite.text
	var stats := StatsData.new()
	stats.hp = _hp.value; stats.atk = _atk.value; stats.defense = _def.value
	stats.spd = _spd.value; stats.aspd = _aspd.value; stats.crt = _crt.value
	data.base_stats = stats
	data.forms = _forms.duplicate()
	DirAccess.make_dir_recursive_absolute(DATA_DIR)
	ResourceSaver.save(data, DATA_DIR + "/" + name_str.to_lower() + ".tres")


## ---- 技能 ----

func _on_add_skill_pressed() -> void:
	var sel := _avail_list.get_selected_items()
	if sel.is_empty(): _show("请从右侧技能池选择"); return
	var name := _avail_list.get_item_text(sel[0])
	var s: SkillData = load(SKILLS_DIR + "/" + name + ".tres")
	if s == null: _show("技能加载失败"); return
	_skills.append(s); _refresh_skill_list()
	_show("已添加技能: %s" % s.skill_name)


func _on_remove_skill_pressed() -> void:
	var sel := _skill_list.get_selected_items()
	if sel.is_empty(): return
	_skills.remove_at(sel[0]); _refresh_skill_list()
	_show("已删除技能")


func _refresh_skill_list() -> void:
	_skill_list.clear()
	for s in _skills:
		_skill_list.add_item("%s (CD %.1fs)" % [s.skill_name, s.cooldown])


## ---- 形态 ----

func _on_add_form_pressed() -> void:
	var n := _form_name.text.strip_edges()
	if n.is_empty(): _show("请输入形态名称"); return
	var form := FormData.new()
	form.form_id = n.to_lower(); form.form_name = n
	form.unlock_floor = int(_form_floor.value)
	form.visual_path = _form_sp.text
	form.skills = _skills.duplicate()
	# 构建 Modifier
	if _mod_hp.value != 0:
		form.modifiers.append(_make_mod("hp", _mod_hp.value))
	if _mod_atk.value != 0:
		form.modifiers.append(_make_mod("atk", _mod_atk.value))
	if _mod_spd.value != 0:
		form.modifiers.append(_make_mod("spd", _mod_spd.value))
	_forms.append(form); _refresh_form_list()
	_show("已添加形态: %s (第%d层, %d技能, %d修改器)" % [n, form.unlock_floor, _skills.size(), form.modifiers.size()])


func _on_remove_form_pressed() -> void:
	var sel := _form_list.get_selected_items()
	if sel.is_empty(): return
	_forms.remove_at(sel[0]); _refresh_form_list()
	_show("已删除形态")


func _refresh_form_list() -> void:
	_form_list.clear()
	for f in _forms:
		var mods := ""
		for m in f.modifiers:
			mods += " %s" % m.description()
		_form_list.add_item("%s (第%d层, %d技能)%s" % [f.form_name, f.unlock_floor, f.skills.size(), mods])


func _make_mod(stat: String, val: float) -> ModifierData:
	var m := ModifierData.new()
	m.target_stat = stat; m.value = val
	m.operation = ModifierData.Operation.MULTIPLY if val < 1.0 else ModifierData.Operation.ADD
	return m


## ---- 导出 ----

func _on_export_pressed() -> void:
	var n := _name_input.text.strip_edges()
	if n.is_empty(): _show("请输入名称"); return
	_save_character(n)
	DirAccess.make_dir_recursive_absolute(FORMS_DIR)
	for f in _forms:
		ResourceSaver.save(f, FORMS_DIR + "/" + n.to_lower() + "_" + f.form_id + ".tres")
	_show("已导出角色+%d形态" % _forms.size())
