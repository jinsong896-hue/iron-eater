class_name AffixData
extends Resource
## 词条数据 —— 装备/吞噬/融合通用

enum Operation { FLAT, PERCENT }

@export var id: StringName = &""
@export var stat: int = 0  ## EquipmentDefs.Stat
@export var operation: int = Operation.FLAT
@export var value: float = 0.0


func _init(p_stat: int = 0, p_value: float = 0.0, p_op: int = Operation.FLAT) -> void:
	stat = p_stat
	value = p_value
	operation = p_op


## 描述文本
func description() -> String:
	var stat_name: String = "属性"
	if 0 <= stat and stat < 11:
		stat_name = AttributeSystem.STAT_NAMES.get(stat, "属性")
	var prefix := "+" if value >= 0 else ""
	if operation == Operation.PERCENT:
		return "%s%s %.0f%%" % [stat_name, prefix, value * 100.0]
	return "%s%s %.1f" % [stat_name, prefix, value]
