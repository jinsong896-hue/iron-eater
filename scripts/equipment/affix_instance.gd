class_name AffixInstance
extends RefCounted
## 词条实例：装备实例上真正生效的词条（含叠层与来源）

var affix_id := ""
var display_name := ""
var stat := "atk"
var operation := EquipmentDefs.ModifierOperation.FLAT
var value := 0.0
var level := 1
var stack_count := 1


static func from_data(data: AffixData) -> AffixInstance:
	var inst := AffixInstance.new()
	inst.affix_id = data.id
	inst.display_name = data.display_name
	inst.stat = data.stat
	inst.operation = data.operation
	inst.value = data.value
	return inst


func effective_value() -> float:
	return value * float(stack_count) * float(level)


func describe() -> String:
	return EquipmentDefs.format_modifier(stat, operation, effective_value())


func to_dict() -> Dictionary:
	return {
		"affix_id": affix_id, "display_name": display_name, "stat": stat,
		"operation": operation, "value": value, "level": level, "stack_count": stack_count,
	}


static func from_dict(d: Dictionary) -> AffixInstance:
	var inst := AffixInstance.new()
	inst.affix_id = d.get("affix_id", "")
	inst.display_name = d.get("display_name", "")
	inst.stat = d.get("stat", "atk")
	inst.operation = d.get("operation", EquipmentDefs.ModifierOperation.FLAT)
	inst.value = d.get("value", 0.0)
	inst.level = d.get("level", 1)
	inst.stack_count = d.get("stack_count", 1)
	return inst
