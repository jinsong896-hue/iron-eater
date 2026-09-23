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
	# —— 装备参考2 规格需要的效果类型（2026-09-23 补） ——
	#
	# **为什么必须补**：规格里大量词条的效果**不是面板属性**，
	# 而旧实现把一切压成 `Stat.X + 数值`——机制语义丢失。实测：
	#   「烈焰法杖：攻击附带 50% 火焰伤害」→ 被压成 `[Stat.ATK, 0.5]`
	#   于是六把元素法杖的数据**一字不差**，元素区别整个消失。
	BONUS_ELEMENT,  ## 攻击**附带** N% 元素伤害（不替代本体伤害，是额外一段）
	STACK_GAIN,     ## 事件触发时叠层（层数由 BuffHolder 记账）
	PERIODIC,       ## 周期性效果（如「每 5 秒获得 1 秒隐身」）
	CHARGE,         ## 蓄力/储存（如「静止时每秒储存 15% 攻击力」）
}

## **触发条件**（装备参考2 规格）。
##
## 规格里绝大多数自有词条不是常驻数值，而是「**在某个事件发生时**」生效：
## 「每击杀一个敌人，该武器所有数值增加1%」「每受到一次伤害，防御力增加1%」
## 「击杀敌人获得1层噬魂，满层时下次攻击释放范围收割」。
##
## 此前这些全被解析成常驻数值——机制丢失。本枚举承载那个「事件」。
##
## 枚举值**按规格的实际机制族穷举**（从 349 件装备的自有词条归类得出），
## 不是凭印象补的。归类见 `ai/装备数据重做计划.md` 第一节。
enum Trigger {
	ALWAYS,         ## 常驻（默认；纯属性词条都是这个）
	ON_KILL,        ## 击杀敌人时
	ON_HURT,        ## 受到伤害时
	ON_HIT,         ## 命中敌人时
	ON_DODGE,       ## 闪避成功时
	AT_FULL,        ## 叠满层时（配合 stack_max 使用）
	# —— 2026-09-23 补全（规格实测需要） ——
	ON_CRIT,        ## 暴击时（「暴击叠加1层预言」）
	ON_COMBO,       ## 连击时（「连续攻击同一目标，每次+1%」）
	ON_DASH,        ## 冲刺后（「冲刺后留下残影」）
	ON_BLOCK,       ## 格挡时（「格挡成功叠加1层守护」）
	ON_ATTACK,      ## 攻击时（「攻击有5%概率冰冻」——攻击动作本身触发）
	LOW_HP,         ## 生命低于阈值（「生命<50% 时减伤」）
	STATIONARY,     ## 静止时（「静止不动时每秒储存攻击力」）
	ON_ROOM_ENTER,  ## 进入新房间（「进入新房间后…」）
}

## 触发条件的中文名（供 UI 显示）
const TRIGGER_NAMES := {
	Trigger.ALWAYS: "常驻",
	Trigger.ON_KILL: "击杀时",
	Trigger.ON_HURT: "受击时",
	Trigger.ON_HIT: "命中时",
	Trigger.ON_DODGE: "闪避时",
	Trigger.AT_FULL: "满层时",
	Trigger.ON_CRIT: "暴击时",
	Trigger.ON_COMBO: "连击时",
	Trigger.ON_DASH: "冲刺后",
	Trigger.ON_BLOCK: "格挡时",
	Trigger.ON_ATTACK: "攻击时",
	Trigger.LOW_HP: "低血时",
	Trigger.STATIONARY: "静止时",
	Trigger.ON_ROOM_ENTER: "进房时",
}

@export var id: StringName = &""
@export var stat: int = 0  ## EquipmentDefs.Stat（仅属性型使用）
@export var operation: int = Operation.FLAT
@export var value: float = 0.0

# —— 触发条件（装备参考2 规格）——
## 这条词条**何时**生效。ALWAYS = 常驻（旧行为，默认）。
@export var trigger: int = Trigger.ALWAYS
## 触发后的**持续时长**（秒）。<=0 = 永久（直到条件不再满足）。
## 例：「防御力增加1%，持续10秒，可叠加5层」→ duration=10.0, stack_max=5。
@export var duration: float = 0.0
## **叠层上限**。0 = 不叠层（每次触发只刷新时长）。
## 例：「最多5层」→ 5。层数由玩家的 BuffHolder 记账（见 buff_defs 的叠层词条）。
@export var stack_max: int = 0
## 触发概率（0~1）。1.0 = 必触发。用于「5%概率额外掉落1枚金币」这类。
@export var chance: float = 1.0
## 满层时触发的**额外效果**描述（规格的「满层时下次攻击释放范围收割」）。
## 目前只承载描述与伤害倍率——真正的满层结算见 PlayerEquipmentEffects。
@export var full_stack_bonus: float = 0.0

# —— BONUS_ELEMENT 专属（规格：「攻击附带 N% 火焰伤害」）——
#
# 语义：**额外一段**元素伤害，不替代本体。与 `elem_dmg_pct`（元素伤害加成）
# 是两回事——后者放大已有的元素伤害，前者是凭空多出的一段。
#
# 数值存在 `value`（0.5 = 附带 50%），元素存在 `element_key`
#（fire/frost/static/earth/wind/poison，与随机词条的"属性词条"共用同一字段）。

# —— LOW_HP 专属（规格：「生命低于 50% 时，获得 20% 伤害减免」）——
## 生效的生命阈值（0.5 = 生命低于 50% 时生效）
@export var hp_threshold: float = 0.0

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
