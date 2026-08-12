class_name AffixData
extends Resource
## 词条模板（内容数据，可被多个装备模板共享）
## kind：BASE 穿戴生效 / DEVOUR 吞噬生效 / FUSION 作为融合材料时贡献

enum Kind { BASE, DEVOUR, FUSION }

@export var id := ""
@export var display_name := ""
@export var kind := Kind.BASE
@export var stat := "atk"
@export var operation := EquipmentDefs.ModifierOperation.FLAT
@export var value := 0.0
@export var tags: Array[String] = []


func describe() -> String:
	return EquipmentDefs.format_modifier(stat, operation, value)
