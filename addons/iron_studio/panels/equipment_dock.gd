@tool
extends Control
## 装备编辑器 v2 —— 武器/词条/融合/Sprite

const DATA_DIR := "res://data/weapons"
var _editor_interface: EditorInterface = null
var _modifiers: Array[ModifierData] = []

@onready var _list: ItemList = $Main/Left/List
@onready var _name: LineEdit = $Main/Right/Scroll/VBox/Identity/Name
@onready var _rarity: OptionButton = $Main/Right/Scroll/VBox/Identity/Rarity
@onready var _sprite: LineEdit = $Main/Right/Scroll/VBox/Identity/Sprite
@onready var _atk: SpinBox = $Main/Right/Scroll/VBox/Stats/ATK
@onready var _fusion: SpinBox = $Main/Right/Scroll/VBox/Growth/Fusion
@onready var _max_fusion: SpinBox = $Main/Right/Scroll/VBox/Growth/MaxFusion
@onready var _growth: SpinBox = $Main/Right/Scroll/VBox/Growth/Growth
@onready var _mod_list: ItemList = $Main/Right/Scroll/VBox/Mods/ModList
@onready var _mod_stat: OptionButton = $Main/Right/Scroll/VBox/Mods/ModStat
@onready var _mod_val: SpinBox = $Main/Right/Scroll/VBox/Mods/ModVal
@onready var _status: Label = $Main/Right/Scroll/VBox/Status


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
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
	print("[EquipStudio] ", msg)


func _on_new_pressed() -> void:
	var n := _name.text.strip_edges()
	if n.is_empty(): _show("请输入名称"); return
	_save_weapon(n); _show("已创建: %s" % n); _refresh()


func _on_load_pressed() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty(): return
	var n := _list.get_item_text(sel[0])
	var w: WeaponData = load(DATA_DIR + "/" + n + ".tres")
	if w == null: _show("加载失败"); return
	_name.text = w.weapon_name
	for i in _rarity.item_count:
		if _rarity.get_item_text(i) == w.rarity: _rarity.select(i); break
	_sprite.text = w.sprite_path
	_atk.value = w.base_atk; _fusion.value = w.fusion_level
	_max_fusion.value = w.max_fusion; _growth.value = w.fusion_atk_growth
	_modifiers = w.modifiers.duplicate(); _refresh_mods()
	_show("已加载: %s" % w.description())


func _on_save_pressed() -> void:
	var n := _name.text.strip_edges()
	if n.is_empty(): _show("请输入名称"); return
	_save_weapon(n); _show("已保存: %s" % n); _refresh()


func _save_weapon(name_str: String) -> void:
	var w := WeaponData.new()
	w.weapon_id = name_str.to_lower(); w.weapon_name = name_str
	w.rarity = _rarity.get_item_text(_rarity.selected)
	w.sprite_path = _sprite.text
	w.base_atk = int(_atk.value)
	w.fusion_level = int(_fusion.value); w.max_fusion = int(_max_fusion.value)
	w.fusion_atk_growth = _growth.value
	w.modifiers = _modifiers.duplicate()
	DirAccess.make_dir_recursive_absolute(DATA_DIR)
	ResourceSaver.save(w, DATA_DIR + "/" + name_str.to_lower() + ".tres")


func _on_fuse_pressed() -> void:
	var cur := int(_fusion.value)
	if cur < int(_max_fusion.value):
		_fusion.value = cur + 1
		_show("融合+1 → ATK:%d" % (int(_atk.value) + (cur + 1) * int(_growth.value)))
	else:
		_show("已达最大融合等级")


func _on_add_mod_pressed() -> void:
	var m := ModifierData.new()
	m.target_stat = _mod_stat.get_item_text(_mod_stat.selected)
	m.value = _mod_val.value
	m.operation = ModifierData.Operation.MULTIPLY if m.value < 1.0 else ModifierData.Operation.ADD
	_modifiers.append(m); _refresh_mods()
	_show("已添加词条: %s" % m.description())


func _on_remove_mod_pressed() -> void:
	var sel := _mod_list.get_selected_items()
	if sel.is_empty(): return
	_modifiers.remove_at(sel[0]); _refresh_mods()
	_show("已删除词条")


func _refresh_mods() -> void:
	_mod_list.clear()
	for m in _modifiers:
		_mod_list.add_item(m.description())
