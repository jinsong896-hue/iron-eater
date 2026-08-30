class_name AffixData
extends Resource
## 词条数据 —— HD-2D 重构版
## 描述一个词条的效果，包含属性、值、类型

@export var id := ""
@export var display_name := ""
@export var description := ""

# 影响的属性
@export var stat := 0  # AttributeSystem.Stat enum value
# 固定值
@export var value: float = 0.0
# 百分比加成
@export var percent: float = 0.0

# 词条类型
enum AffixType {
	FLAT,        # 固定值
	PERCENT,     # 百分比
	SPECIAL,     # 特殊效果（如击杀回血）
}

@export var type := AffixType.FLAT

# 特殊效果 ID（预留）
@export var special_effect_id := ""


func get_description() -> String:
	var stat_name: String = AttributeSystem.STAT_NAMES.get(stat, "未知")
	match type:
		AffixType.FLAT:
			return "%s +%.0f" % [stat_name, value]
		AffixType.PERCENT:
			return "%s +%.0f%%" % [stat_name, percent * 100.0]
		AffixType.SPECIAL:
			return description
	return description


func to_dict() -> Dictionary:
	return {
		"id": id, "stat": stat, "type": type,
		"value": value, "percent": percent,
	}


static func from_dict(d: Dictionary) -> AffixData:
	var a := AffixData.new()
	a.id = d.get("id", "")
	a.stat = d.get("stat", 0)
	a.type = d.get("type", 0)
	a.value = d.get("value", 0.0)
	a.percent = d.get("percent", 0.0)
	return a