@tool
extends Control
## Buff/Debuff 编辑器 —— 创建临时属性修改效果

const DATA_DIR := "res://data/effects"

@onready var _list: ItemList = $Main/Left/List
@onready var _name: LineEdit = $Main/Right/Scroll/VBox/Name
@onready var _is_debuff: CheckBox = $Main/Right/Scroll/VBox/Debuff
@onready var _duration: SpinBox = $Main/Right/Scroll/VBox/Duration
@onready var _stacks: SpinBox = $Main/Right/Scroll/VBox/Stacks
@onready var _mod_list: ItemList = $Main/Right/Scroll/VBox/ModList
@onready var _mod_stat: OptionButton = $Main/Right/Scroll/VBox/ModStat
@onready var _mod_val: SpinBox = $Main/Right/Scroll/VBox/ModVal
@onready var _status: Label = $Main/Right/Scroll/VBox/Status
var _modifiers: Array[ModifierData] = []


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	_list.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null: return
	dir.list_dir_begin(); var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"): _list.add_item(f.trim_suffix(".tres"))
		f = dir.get_next()
	dir.list_dir_end()


func _show(msg: String) -> void:
	_status.text = msg
	print("[BuffStudio] ", msg)


func _on_new_pressed() -> void:
	var n := _name.text.strip_edges()
	if n.is_empty(): _show("请输入名称"); return
	_save(n); _show("已创建: %s" % n); _refresh()


func _on_load_pressed() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty(): return
	var n := _list.get_item_text(sel[0])
	var b: BuffData = load(DATA_DIR + "/" + n + ".tres")
	if b == null: _show("加载失败"); return
	_name.text = b.buff_name
	_is_debuff.button_pressed = b.is_debuff
	_duration.value = b.duration
	_stacks.value = b.max_stacks
	_modifiers = b.modifiers.duplicate(); _refresh_mods()
	_show("已加载: %s" % b.description())


func _on_save_pressed() -> void:
	var n := _name.text.strip_edges()
	if n.is_empty(): _show("请输入名称"); return
	_save(n); _show("已保存: %s" % n); _refresh()


func _save(name_str: String) -> void:
	var b := BuffData.new()
	b.buff_id = name_str.to_lower(); b.buff_name = name_str
	b.is_debuff = _is_debuff.button_pressed
	b.duration = _duration.value; b.max_stacks = int(_stacks.value)
	b.modifiers = _modifiers.duplicate()
	DirAccess.make_dir_recursive_absolute(DATA_DIR)
	ResourceSaver.save(b, DATA_DIR + "/" + name_str.to_lower() + ".tres")


func _on_add_mod_pressed() -> void:
	var m := ModifierData.new()
	m.target_stat = _mod_stat.get_item_text(_mod_stat.selected); m.value = _mod_val.value
	m.operation = ModifierData.Operation.MULTIPLY if m.value < 1.0 else ModifierData.Operation.ADD
	_modifiers.append(m); _refresh_mods()
	_show("已添加: %s" % m.description())


func _on_remove_mod_pressed() -> void:
	var sel := _mod_list.get_selected_items()
	if sel.is_empty(): return
	_modifiers.remove_at(sel[0]); _refresh_mods()


func _refresh_mods() -> void:
	_mod_list.clear()
	for m in _modifiers:
		_mod_list.add_item(m.description())
