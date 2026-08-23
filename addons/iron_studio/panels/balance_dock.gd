@tool
extends Control
## 数值平衡器 —— 模拟DPS/生存/Boss击杀时间
## 文档：ai/框架相关.md Balance Studio

const CHAR_DIR := "res://data/characters"
const WEAPON_DIR := "res://data/weapons"

@onready var _char_list: ItemList = $Main/Left/CharList
@onready var _weapon_list: ItemList = $Main/Left/WeaponList
@onready var _form_idx: SpinBox = $Main/Right/Scroll/VBox/Config/FormIdx
@onready var _floor_spin: SpinBox = $Main/Right/Scroll/VBox/Config/Floor
@onready var _result: Label = $Main/Right/Scroll/VBox/Result
@onready var _status: Label = $Main/Right/Scroll/VBox/Status


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	_char_list.clear(); _weapon_list.clear()
	for list in [_char_list, _weapon_list]:
		var dir_path := CHAR_DIR if list == _char_list else WEAPON_DIR
		var dir := DirAccess.open(dir_path)
		if dir == null: continue
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".tres"): list.add_item(f.trim_suffix(".tres"))
			f = dir.get_next()
		dir.list_dir_end()


func _show(msg: String) -> void:
	_status.text = msg
	print("[Balance] ", msg)


func _on_simulate_pressed() -> void:
	var char_sel := _char_list.get_selected_items()
	var wep_sel := _weapon_list.get_selected_items()
	if char_sel.is_empty(): _show("请选择角色"); return

	var char_name := _char_list.get_item_text(char_sel[0])
	var char: CharacterData = load(CHAR_DIR + "/" + char_name + ".tres")
	if char == null: _show("角色加载失败"); return

	var weapon: WeaponData = null
	if not wep_sel.is_empty():
		weapon = load(WEAPON_DIR + "/" + _weapon_list.get_item_text(wep_sel[0]) + ".tres")

	var form_i := int(_form_idx.value)
	var floor := int(_floor_spin.value)
	var report := BalanceCalculator.simulate(char, weapon, form_i, floor)

	var lines: PackedStringArray = []
	lines.append("=== 数值模拟报告 ===")
	lines.append("角色: %s | 形态: %d | 层数: %d" % [char.char_name, form_i, floor])
	lines.append("武器: %s" % (weapon.weapon_name if weapon else "无"))
	lines.append("")
	lines.append("-- 最终属性 --")
	var stats: Dictionary = report["final_stats"]
	for k in ["hp", "atk", "defense", "spd", "aspd", "crt", "crd"]:
		lines.append("  %s: %.1f" % [k, stats[k]])
	lines.append("")
	lines.append("-- 战斗模拟 --")
	lines.append("  DPS: %.1f" % report["dps"])
	lines.append("  生存: %.1f秒" % report["survival_seconds"])
	lines.append("  Boss击杀: %.1f秒" % report["ttk_seconds"])
	lines.append("  敌人HP: %.1f | 敌人ATK: %.1f" % [report["enemy_hp"], report["enemy_atk"]])
	_result.text = "\n".join(lines)
	_show("模拟完成 DPS:%.1f TTK:%.1fs" % [report["dps"], report["ttk_seconds"]])


func _on_refresh_pressed() -> void:
	_refresh(); _show("已刷新")
