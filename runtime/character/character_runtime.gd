class_name CharacterRuntime
extends Node
## 角色运行时 —— 从 CharacterData 生成可玩角色
## 文档：ai/框架相关.md Layer 3 Runtime

var data: CharacterData
var current_form: FormData
var base_stats: StatsData
var active_modifiers: Array[ModifierData] = []
var current_hp: float = 0.0


func setup(char_data: CharacterData, form_idx: int = 0) -> void:
	data = char_data
	base_stats = char_data.base_stats.clone() if char_data.base_stats else StatsData.new()
	switch_form(form_idx)
	_recalc()


func switch_form(idx: int) -> void:
	if idx < 0 or idx >= data.forms.size():
		current_form = null
		return
	current_form = data.forms[idx]
	active_modifiers.clear()
	active_modifiers.append_array(current_form.modifiers)
	_recalc()


func add_modifier(mod: ModifierData) -> void:
	active_modifiers.append(mod)
	_recalc()


func remove_modifier(mod: ModifierData) -> void:
	active_modifiers.erase(mod)
	_recalc()


func get_final_stats() -> StatsData:
	return base_stats.apply_modifiers(active_modifiers)


func take_damage(amount: float) -> void:
	current_hp = maxf(current_hp - amount, 0.0)


func is_alive() -> bool:
	return current_hp > 0.0


func _recalc() -> void:
	var stats := get_final_stats()
	current_hp = stats.hp


func description() -> String:
	var stats := get_final_stats()
	var form_name := current_form.form_name if current_form else "无形态"
	return "%s[%s] HP:%.0f ATK:%.0f" % [data.char_name, form_name, stats.hp, stats.atk]
