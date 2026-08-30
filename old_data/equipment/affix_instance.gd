class_name AffixInstance
extends RefCounted
## 词条实例 —— HD-2D 重构版
## 词条在装备实例上的运行时表现

var affix_id := ""
var value: float = 0.0
var percent: float = 0.0
var source_template_id := ""


static func from_data(data: AffixData) -> AffixInstance:
	var inst := AffixInstance.new()
	inst.affix_id = data.id
	inst.value = data.value
	inst.percent = data.percent
	return inst


func to_dict() -> Dictionary:
	return {
		"affix_id": affix_id,
		"value": value,
		"percent": percent,
		"source_template_id": source_template_id,
	}


static func from_dict(d: Dictionary) -> AffixInstance:
	var inst := AffixInstance.new()
	inst.affix_id = d.get("affix_id", "")
	inst.value = d.get("value", 0.0)
	inst.percent = d.get("percent", 0.0)
	inst.source_template_id = d.get("source_template_id", "")
	return inst