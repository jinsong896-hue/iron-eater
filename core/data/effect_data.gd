class_name EffectData
extends Resource
## 效果基类 —— 技能/装备/词条/Buff 统一使用
## 文档：ai/框架相关.md 六、Effect系统

@export var effect_id: String = ""
@export var effect_name: String = ""


func execute(target: Node) -> void:
	pass


func description() -> String:
	return effect_name
