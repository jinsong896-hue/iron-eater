@tool
extends Control
## 怪物编辑器 —— 怪物模板创建与配置

const DATA_DIR := "res://data/monsters"

@onready var _list: ItemList = $Main/Left/List
@onready var _name: LineEdit = $Main/Right/Scroll/VBox/Identity/Name
@onready var _ai_type: OptionButton = $Main/Right/Scroll/VBox/Identity/AIType
@onready var _hp: SpinBox = $Main/Right/Scroll/VBox/Stats/HP
@onready var _atk: SpinBox = $Main/Right/Scroll/VBox/Stats/ATK
@onready var _def: SpinBox = $Main/Right/Scroll/VBox/Stats/DEF
@onready var _spd: SpinBox = $Main/Right/Scroll/VBox/Stats/SPD
@onready var _floor_min: SpinBox = $Main/Right/Scroll/VBox/Stage/FloorMin
@onready var _floor_max: SpinBox = $Main/Right/Scroll/VBox/Stage/FloorMax
@onready var _hp_scale: SpinBox = $Main/Right/Scroll/VBox/Stage/HPScale
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
	print("[MonsterStudio] ", msg)


func _on_new_pressed() -> void:
	var n := _name.text.strip_edges()
	if n.is_empty(): _show("请输入名称"); return
	var data := _collect()
	DirAccess.make_dir_recursive_absolute(DATA_DIR)
	ResourceSaver.save(data, DATA_DIR + "/" + n.to_lower() + ".tres")
	_show("已创建怪物: %s" % n)
	_refresh()


func _on_load_pressed() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty(): return
	var n := _list.get_item_text(sel[0])
	var data = load(DATA_DIR + "/" + n + ".tres")
	if data == null: _show("加载失败"); return
	_name.text = data.get("monster_name")
	_hp.value = data.get("hp"); _atk.value = data.get("atk")
	_def.value = data.get("defense"); _spd.value = data.get("speed")
	_floor_min.value = data.get("floor_min"); _floor_max.value = data.get("floor_max")
	_hp_scale.value = data.get("hp_scale")
	_show("已加载: %s" % n)


func _on_save_pressed() -> void:
	var n := _name.text.strip_edges()
	if n.is_empty(): _show("请输入名称"); return
	ResourceSaver.save(_collect(), DATA_DIR + "/" + n.to_lower() + ".tres")
	_show("已保存: %s" % n)
	_refresh()


func _collect() -> Resource:
	var data := Resource.new()
	data.set_script(preload("res://core/data/monster_data.gd"))
	data.set("monster_name", _name.text.strip_edges())
	data.set("ai_type", _ai_type.get_item_text(_ai_type.selected))
	data.set("hp", int(_hp.value)); data.set("atk", int(_atk.value))
	data.set("defense", int(_def.value)); data.set("speed", int(_spd.value))
	data.set("floor_min", int(_floor_min.value)); data.set("floor_max", int(_floor_max.value))
	data.set("hp_scale", _hp_scale.value)
	return data
