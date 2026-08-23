class_name CharacterData
extends Resource
## 角色数据 —— 职业模板
## 文档：ai/框架相关.md 三、CharacterData

@export_category("Identity")
@export var char_id: String = ""
@export var char_name: String = ""
@export_multiline var description: String = ""

@export_category("Class")
@export_enum("Warrior:战士", "Mage:法师", "Hunter:猎人", "Monk:武僧", "Judge:判官")
var class_type: String = "Warrior"

@export_category("Resource")
@export var resource_name: String = ""
@export var resource_max: int = 100

@export_category("Stats")
@export var base_stats: StatsData

@export_category("Forms")
@export var forms: Array[FormData] = []

@export_category("Visual")
@export var sprite_path: String = ""


func get_form(idx: int) -> FormData:
	if idx >= 0 and idx < forms.size():
		return forms[idx]
	return null


func summary() -> String:
	return "%s [%s] %d形态 %d资源" % [char_name, class_type, forms.size(), resource_max]
