extends Node
## IronEater Creator 游戏运行时接入 —— autoload 单例
## 文档：ai/框架相关.md 总体架构 Runtime Layer

var creator: IronEaterCreator
var player_runtime: CharacterRuntime
var equipment_runtime: EquipmentRuntime
var skill_runtime: SkillRuntime


func _ready() -> void:
	creator = IronEaterCreator.new()
	player_runtime = CharacterRuntime.new()
	equipment_runtime = EquipmentRuntime.new()
	skill_runtime = SkillRuntime.new()
	add_child(player_runtime)
	add_child(equipment_runtime)
	add_child(skill_runtime)


## 从编辑器数据创建玩家
func create_player(char_id: String, weapon_id: String = "", form_idx: int = 0) -> void:
	var char_data := creator.load_character(char_id)
	if char_data == null:
		print("[GameCreator] 角色不存在: %s" % char_id)
		return
	player_runtime.setup(char_data, form_idx)
	if weapon_id != "":
		var weapon := creator.load_weapon(weapon_id)
		if weapon:
			equipment_runtime.equip(weapon)
	# 加载形态技能
	if player_runtime.current_form:
		skill_runtime.load_skills(player_runtime.current_form.skills)
	print("[GameCreator] 创建玩家: %s" % player_runtime.description())


## 切换形态
func switch_form(idx: int) -> void:
	player_runtime.switch_form(idx)
	if player_runtime.current_form:
		skill_runtime.load_skills(player_runtime.current_form.skills)


## 释放技能
func cast_skill(skill_id: String, target: Node = null) -> Dictionary:
	var skill: SkillData = creator.load_skill(skill_id)
	if skill == null:
		return {"ok": false, "reason": "技能不存在"}
	return skill_runtime.cast(skill, target)


## 获取最终属性
func get_final_stats() -> StatsData:
	var stats := player_runtime.get_final_stats()
	# 叠加装备属性
	if equipment_runtime.weapon:
		var atk_mod := ModifierData.new()
		atk_mod.target_stat = "atk"
		atk_mod.operation = ModifierData.Operation.ADD
		atk_mod.value = equipment_runtime.get_atk()
		stats = stats.apply_modifiers([atk_mod])
		stats = stats.apply_modifiers(equipment_runtime.modifiers)
	return stats
