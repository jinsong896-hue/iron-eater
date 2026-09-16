class_name AffixData
extends Resource
## 词条数据 —— 装备/吞噬/融合通用
##
## 两种词条形态（名词设计分册第 5 章「通用词条池（装备可附加，21 种）」）：
##   1. **属性型**（Operation.FLAT / PERCENT）——纯数值，挂进 AttributeSystem，
##      如「攻击力+ 5%~15%」「暴击率+ 3%~10%」。
##   2. **触发型**（Operation.TRIGGER_BUFF）——命中时按概率给目标施加一个
##      BuffDefs 词条，如「眩晕：攻击有 3%~10% 概率眩晕目标 1 秒」。
##      这类词条在此前的数据结构里**完全没有承载**（只有 Stat+value），
##      导致分册第 5 章的 9 种触发型词条无法落地。

enum Operation {
	FLAT,           ## 固定值（如 攻击力 +35）
	PERCENT,        ## 百分比（如 攻击力 +5%）
	TRIGGER_BUFF,   ## 命中时概率施加词条（如 5% 概率破甲 4 秒）
}

@export var id: StringName = &""
@export var stat: int = 0  ## EquipmentDefs.Stat（仅属性型使用）
@export var operation: int = Operation.FLAT
@export var value: float = 0.0

# —— 触发型专属字段（operation == TRIGGER_BUFF 时有效）——
## 要施加的 BuffDefs 词条 id（如 "stun" / "armor_break" / "blind" / "disarm"）
@export var trigger_buff: String = ""
## 触发概率（0~1）。分册给的是区间（如 3%~10%），具体值由调用方按稀有度取。
@export var trigger_chance: float = 0.0
## 覆盖词条时长（秒）。<=0 表示用 BuffDefs 表里的默认时长。
@export var trigger_duration: float = 0.0


func _init(p_stat: int = 0, p_value: float = 0.0, p_op: int = Operation.FLAT) -> void:
	stat = p_stat
	value = p_value
	operation = p_op


## 构造一个属性型词条
static func make_stat(p_stat: int, p_value: float, p_percent: bool) -> AffixData:
	return AffixData.new(p_stat, p_value,
		Operation.PERCENT if p_percent else Operation.FLAT)


## 构造一个触发型词条（命中时按概率施加 buff_id）
static func make_trigger(buff_id: String, chance: float, duration: float = 0.0) -> AffixData:
	var a := AffixData.new(0, 0.0, Operation.TRIGGER_BUFF)
	a.trigger_buff = buff_id
	a.trigger_chance = chance
	a.trigger_duration = duration
	return a


## 是否为触发型（命中时施加词条）
func is_trigger() -> bool:
	return operation == Operation.TRIGGER_BUFF


## 是否为属性型（可挂进 AttributeSystem）
func is_stat() -> bool:
	return operation == Operation.FLAT or operation == Operation.PERCENT


## 描述文本
func description() -> String:
	if is_trigger():
		var bname: String = trigger_buff
		var row: Array = BuffDefs.get_buff(trigger_buff)
		if not row.is_empty():
			bname = str(row[1])
		var dur := ""
		if trigger_duration > 0.0:
			dur = "（%.1f 秒）" % trigger_duration
		return "攻击有 %.0f%% 概率施加【%s】%s" % [
			trigger_chance * 100.0, bname, dur]
	var stat_name: String = "属性"
	if 0 <= stat and stat < 11:
		stat_name = AttributeSystem.STAT_NAMES.get(stat, "属性")
	var prefix := "+" if value >= 0 else ""
	if operation == Operation.PERCENT:
		return "%s%s %.0f%%" % [stat_name, prefix, value * 100.0]
	return "%s%s %.1f" % [stat_name, prefix, value]
