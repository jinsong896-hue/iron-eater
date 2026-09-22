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

# —— 随机词条专属字段（装备参考2 规格）——
#
# 随机词条是「掉落时生成、无法升级、无法转移、不通过融合/吞噬继承」的
# 那一类。它们与上面的属性型/触发型走**同一套挂载通道**（挂进
# AttributeSystem），差别只在**生命周期**与**显示**：
#   · 生命周期：不参与融合/吞噬/强化（见 EquipmentInstance 的注释）
#   · 显示：按随机到的档位着色（白/绿/蓝/紫/橙/红），与装备稀有度无关
## 随机词条的三类（EquipmentDefs.RANDOM_KIND_*）：numeric / attribute / special
## 空串 = 不是随机词条（是融合/附魔等常规词条）
@export var random_kind: String = ""
## 档位显示色名（"白"/"绿"/"蓝"/"紫"/"橙"/"红"）。
## **与装备稀有度色是两套**：随机词条自带档位，装备稀有度是另一回事。
@export var tier_color: String = ""
## 属性词条的子类：physical / magic / element / true（仅 random_kind == attribute）
@export var attribute_kind: String = ""
## 具体元素（attribute_kind == "element" 时有效）：fire/frost/static/earth/wind/poison
@export var element_key: String = ""
## 是否来自特殊词条（借用某件装备的自有词条，**不可升级**）
@export var is_borrowed: bool = false
## 借用来源的装备稀有度（特殊词条的显示档位依据）
@export var source_rarity: int = -1


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
