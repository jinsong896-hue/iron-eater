class_name ElementDamage
extends RefCounted
## 元素伤害桥接层 —— 把「元素叠层 / 阈值触发 / 联动」接进战斗结算
##
## 这是 element_defs（数据）、buff_holder（状态）、element_combo（联动）
## 与战斗系统之间的唯一接口。战斗系统只需调一次 attack()，
## 不必把元素规则散落到各处。
##
## 一次元素攻击的完整流程（照分册 7.2~7.8）：
##   1. 给目标叠对应元素的层数
##   2. 检查阈值事件：冰满 3 层→冰冻；雷满 10 层→雷暴
##   3. 用叠加后的状态判定元素联动（4 组）
##   4. 返回本次攻击的伤害倍率与事件列表，由调用方消费
##
## 纯逻辑、不碰场景树，可单测。

## 元素 id（ElementDefs.Elem）→ 字符串键，用于怪物表的 element 字段
const ELEM_BY_KEY := {
	"fire": ElementDefs.Elem.FIRE, "frost": ElementDefs.Elem.FROST,
	"static": ElementDefs.Elem.STATIC, "earth": ElementDefs.Elem.EARTH,
	"wind": ElementDefs.Elem.WIND, "poison": ElementDefs.Elem.POISON,
}

## 无元素的物理攻击
const NO_ELEMENT := -1


## 字符串键 → 元素枚举（未知返回 NO_ELEMENT）
static func elem_from_key(key: String) -> int:
	return int(ELEM_BY_KEY.get(key, NO_ELEMENT))


## 执行一次元素攻击结算。
##
## attacker_buffs / target_buffs : BuffHolder（可为 null，表示该方无状态容器）
## element                       : ElementDefs.Elem，或 NO_ELEMENT（纯物理）
## damage_mult                   : 基础伤害倍率（由调用方的连段/技能决定）
## state                         : 额外场上状态 {tornado: bool, shatter_proc: bool}
##
## 返回 {
##   ok, element, damage_mult,          # 应用联动增幅后的倍率
##   events: Array[String],             # "freeze" / "thunderstorm"
##   combo: Dictionary,                 # 触发的联动 {组合名: 增幅}
##   stacks_applied: int,
## }
static func attack(target_buffs, element: int, damage_mult: float = 1.0,
		state: Dictionary = {}) -> Dictionary:
	if target_buffs == null or element == NO_ELEMENT:
		return {"ok": true, "element": element, "damage_mult": damage_mult,
			"events": [], "combo": {}, "stacks_applied": 0}

	var events: Array = []
	var stacks := 0

	# 1~2. 叠层 + 阈值事件（add_element 内部处理冰冻/雷暴的归零）
	if ElementDefs.stacks(element):
		events = target_buffs.add_element(element, 1)
		stacks = 1

	# 3. 联动判定：用叠加后的最新状态
	var snap := ElementCombo.state_from_holder(target_buffs)
	for k in state:
		snap[k] = state[k]
	var combos := ElementCombo.evaluate(snap)

	# 4. 联动对本次伤害的增幅
	var mult := damage_mult
	if combos.has(ElementDefs.COMBO_ICE_CONDUCT):
		# 冰晶电导：雷暴伤害提升（本次若是雷系触发即生效；此处按倍率整体放大）
		var ice: Dictionary = combos[ElementDefs.COMBO_ICE_CONDUCT]
		mult *= float(ice.get("burst_mult", 1.0)) / 4.0   # 4.0 为雷暴基准
	if combos.has(ElementDefs.COMBO_SHATTER_ROCK):
		var rock: Dictionary = combos[ElementDefs.COMBO_SHATTER_ROCK]
		mult *= float(rock.get("proc_mult", 1.0)) / 5.0   # 5.0 为山崩基准

	return {
		"ok": true,
		"element": element,
		"damage_mult": mult,
		"events": events,
		"combo": combos,
		"stacks_applied": stacks,
	}


## 结算某元素当前的 DOT 伤害（每秒）。
## 火：法强×0.04×层数；毒：法强×0.03×层数；其余无 DOT。
static func dot_per_second(holder: BuffHolder, ap: float) -> float:
	if holder == null:
		return 0.0
	var total := 0.0
	for elem in ElementDefs.all_elements():
		var cfg: Dictionary = ElementDefs.get_element(elem)
		var per := float(cfg.get("dot_per_stack", 0.0))
		if per <= 0.0:
			continue
		total += ap * per * float(holder.elem_stacks(elem))
	return total


## 把阈值事件转成应施加的控制词条 id（供调用方挂到目标上）
## 冰冻/麻痹/眩晕都是硬控，走 buff_defs 里已有的定义
static func control_for_event(event: String) -> String:
	match event:
		"freeze": return "freeze"
		"thunderstorm": return "paralyze"
	return ""


## 事件中文名（UI/日志用）
static func event_name(event: String) -> String:
	match event:
		"freeze": return "冰冻"
		"thunderstorm": return "雷暴"
	return event
