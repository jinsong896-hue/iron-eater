class_name FormData
extends Resource
## 形态数据 —— 每个职业的5种形态
## 文档：ai/框架相关.md 五、FormData

@export_category("Identity")
@export var form_id: String = ""
@export var form_name: String = ""
@export var unlock_floor: int = 0

@export_category("Stats")
@export var modifiers: Array[ModifierData] = []

@export_category("Skills")
@export var skills: Array[SkillData] = []

@export_category("Visual")
@export var visual_path: String = ""


func description() -> String:
	var parts: PackedStringArray = []
	for m in modifiers:
		parts.append(m.description())
	parts.append("%d 个技能" % skills.size())
	return "%s (第%d层解锁): %s" % [form_name, unlock_floor, ", ".join(parts)]
