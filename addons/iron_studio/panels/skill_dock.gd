@tool
extends Control
## 技能编辑器 —— 创建技能 + 组合效果
## 文档：ai/框架相关.md Skill Studio

const DATA_DIR := "res://data/skills"
const SkillDataScript := preload("res://core/data/skill_data.gd")

var _effects: Array[EffectData] = []

@onready var _list: ItemList = $Main/Left/List
@onready var _name: LineEdit = $Main/Right/Scroll/VBox/Identity/Name
@onready var _hp_cost: SpinBox = $Main/Right/Scroll/VBox/Cost/HPCost
@onready var _mp_cost: SpinBox = $Main/Right/Scroll/VBox/Cost/MPCost
@onready var _cooldown: SpinBox = $Main/Right/Scroll/VBox/Cost/Cooldown
@onready var _anim: LineEdit = $Main/Right/Scroll/VBox/Visual/Anim
@onready var _vfx: LineEdit = $Main/Right/Scroll/VBox/Visual/VFX
@onready var _effect_list: ItemList = $Main/Right/Scroll/VBox/Effects/EffectList
@onready var _eff_type: OptionButton = $Main/Right/Scroll/VBox/Effects/EffType
@onready var _eff_val: SpinBox = $Main/Right/Scroll/VBox/Effects/EffVal
@onready var _eff_stat: OptionButton = $Main/Right/Scroll/VBox/Effects/EffStat
@onready var _status: Label = $Main/Right/Scroll/VBox/Status


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	_list.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null: return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"): _list.add_item(f.trim_suffix(".tres"))
		f = dir.get_next()
	dir.list_dir_end()


func _show(msg: String) -> void:
	_status.text = msg
	print("[SkillStudio] ", msg)


func _on_new_pressed() -> void:
	var n := _name.text.strip_edges()
	if n.is_empty(): _show("请输入名称"); return
	_save_skill(n); _show("已创建: %s" % n); _refresh()


func _on_load_pressed() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty(): return
	var n := _list.get_item_text(sel[0])
	var s: SkillData = load(DATA_DIR + "/" + n + ".tres")
	if s == null: _show("加载失败"); return
	_name.text = s.skill_name
	_hp_cost.value = s.hp_cost; _mp_cost.value = s.mp_cost
	_cooldown.value = s.cooldown
	_anim.text = s.animation_name; _vfx.text = s.vfx_path
	_effects = s.effects.duplicate()
	_refresh_effects()
	_show("已加载: %s" % s.skill_name)


func _on_save_pressed() -> void:
	var n := _name.text.strip_edges()
	if n.is_empty(): _show("请输入名称"); return
	_save_skill(n); _show("已保存: %s" % n); _refresh()


func _save_skill(name_str: String) -> void:
	var s := SkillData.new()
	s.skill_id = name_str.to_lower(); s.skill_name = name_str
	s.hp_cost = _hp_cost.value; s.mp_cost = _mp_cost.value
	s.cooldown = _cooldown.value
	s.animation_name = _anim.text; s.vfx_path = _vfx.text
	s.effects = _effects.duplicate()
	DirAccess.make_dir_recursive_absolute(DATA_DIR)
	ResourceSaver.save(s, DATA_DIR + "/" + name_str.to_lower() + ".tres")


func _on_add_effect_pressed() -> void:
	var eff: EffectData
	var t := _eff_type.selected
	var v := _eff_val.value
	if t == 0:
		eff = DamageEffect.new()
		eff.multiplier = v; eff.effect_name = "伤害x%.1f" % v
	else:
		eff = BuffEffect.new()
		eff.stat = _eff_stat.get_item_text(_eff_stat.selected)
		eff.add_value = v; eff.effect_name = "%s+%.0f" % [eff.stat, v]
	_effects.append(eff)
	_refresh_effects()
	_show("已添加效果: %s" % eff.description())


func _on_remove_effect_pressed() -> void:
	var sel := _effect_list.get_selected_items()
	if sel.is_empty(): return
	_effects.remove_at(sel[0])
	_refresh_effects()
	_show("已删除效果")


func _refresh_effects() -> void:
	_effect_list.clear()
	for e in _effects:
		_effect_list.add_item(e.description())
