class_name SkillData
extends Resource
## 技能数据 —— 效果组合 + 消耗 + 冷却 + 表现
## 文档：ai/框架相关.md 四、SkillData

@export_category("Identity")
@export var skill_id: String = ""
@export var skill_name: String = ""

@export_category("Cost")
@export var hp_cost: float = 0.0
@export var mp_cost: float = 0.0
@export var cooldown: float = 1.0

@export_category("Effects")
@export var effects: Array[EffectData] = []

@export_category("Visual")
@export var animation_name: String = ""
@export var vfx_path: String = ""
@export var sound_path: String = ""


func execute(target: Node) -> void:
	for effect in effects:
		effect.execute(target)


func description() -> String:
	var parts: PackedStringArray = []
	if hp_cost > 0: parts.append("HP-%.0f" % hp_cost)
	if mp_cost > 0: parts.append("MP-%.0f" % mp_cost)
	if cooldown > 0: parts.append("CD %.1fs" % cooldown)
	for e in effects:
		parts.append(e.description())
	return "%s: %s" % [skill_name, ", ".join(parts)]
