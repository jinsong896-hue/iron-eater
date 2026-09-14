class_name ElementCombo
extends RefCounted
## 元素联动判定 —— 《噬铁者》名词设计分册 7.8
##
## 四组联动的触发条件与增幅（照分册转写）：
##   烈焰风暴（火+风） 灼烧≥20 且龙卷风存在 → 灼烧每秒 +5 层；溅射 80%→120%
##   腐化烈焰（火+毒） 灼烧≥20 且毒蚀≥15    → 每次命中同时叠灼烧+毒蚀；毒蚀易伤对灼烧生效
##   冰晶电导（雷+冰） 静电≥5 且冰冻中       → 雷暴伤害 法强×6.0；麻痹 2.5s；连锁范围 6m
##   碎裂岩击（冰+土） 冰冻中 且山崩触发     → 山崩 法强×7.0；眩晕 2s；冰裂额外触发 1 次
##
## 纯逻辑：输入是一份「场上元素状态快照」，输出是本次命中的联动增幅。
## 这样战斗系统只需在结算前问一次，不需要把元素规则散落各处。

## 联动门槛（分册 7.8）
const REQ_BURN_FOR_FLAME_STORM := 20
const REQ_BURN_FOR_CORRUPT := 20
const REQ_POISON_FOR_CORRUPT := 15
const REQ_STATIC_FOR_ICE_CONDUCT := 5

## 联动增幅（分册 7.8）
const FLAME_STORM_BURN_PER_SEC := 5.0     # 灼烧层数每秒 +5
const FLAME_STORM_SPLASH_UP := 1.20       # 溅射提升至 120%
const ICE_CONDUCT_BURST_MULT := 6.0       # 雷暴 法强×6.0（原 4.0）
const ICE_CONDUCT_PARALYZE := 2.5         # 麻痹 2.5s（原 1.5）
const ICE_CONDUCT_CHAIN_RADIUS := 6.0     # 连锁范围 6m（原 4m）
const SHATTER_ROCK_PROC_MULT := 7.0       # 山崩 法强×7.0（原 5.0）
const SHATTER_ROCK_STUN := 2.0            # 眩晕 2s（原 1s）
const SHATTER_ROCK_EXTRA_ICE_CRACK := 1   # 冰裂额外触发 1 次


## 判定当前场上状态触发了哪些联动。
## state 键（全部可选，缺省 0/false）：
##   burn / poison / static  —— 元素层数
##   tornado                 —— 场上是否有龙卷风
##   frozen                  —— 目标是否冰冻中
##   shatter_proc            —— 本次是否触发了山崩
## 返回 {组合名: 增幅字典}，空表示无联动。
static func evaluate(state: Dictionary) -> Dictionary:
	var out := {}
	var burn := int(state.get("burn", 0))
	var poison := int(state.get("poison", 0))
	var stat := int(state.get("static", 0))
	var tornado := bool(state.get("tornado", false))
	var frozen := bool(state.get("frozen", false))
	var shatter := bool(state.get("shatter_proc", false))

	# 烈焰风暴：灼烧≥20 且龙卷风存在
	if burn >= REQ_BURN_FOR_FLAME_STORM and tornado:
		out[ElementDefs.COMBO_FIRE_STORM] = {
			"burn_per_sec": FLAME_STORM_BURN_PER_SEC,
			"splash_ratio": FLAME_STORM_SPLASH_UP,
		}
	# 腐化烈焰：灼烧≥20 且毒蚀≥15
	if burn >= REQ_BURN_FOR_CORRUPT and poison >= REQ_POISON_FOR_CORRUPT:
		out[ElementDefs.COMBO_CORRUPT_FLAME] = {
			"dual_stack": true,        # 每次命中同时叠灼烧+毒蚀
			"poison_vuln_on_dot": true,
		}
	# 冰晶电导：静电≥5 且冰冻中
	if stat >= REQ_STATIC_FOR_ICE_CONDUCT and frozen:
		out[ElementDefs.COMBO_ICE_CONDUCT] = {
			"burst_mult": ICE_CONDUCT_BURST_MULT,
			"paralyze": ICE_CONDUCT_PARALYZE,
			"chain_radius": ICE_CONDUCT_CHAIN_RADIUS,
		}
	# 碎裂岩击：冰冻中 且山崩触发
	if frozen and shatter:
		out[ElementDefs.COMBO_SHATTER_ROCK] = {
			"proc_mult": SHATTER_ROCK_PROC_MULT,
			"stun": SHATTER_ROCK_STUN,
			"extra_ice_crack": SHATTER_ROCK_EXTRA_ICE_CRACK,
		}
	return out


## 从 BuffHolder 生成状态快照，供 evaluate 使用
static func state_from_holder(holder: BuffHolder) -> Dictionary:
	if holder == null:
		return {}
	return {
		"burn": holder.elem_stacks(ElementDefs.Elem.FIRE),
		"poison": holder.elem_stacks(ElementDefs.Elem.POISON),
		"static": holder.elem_stacks(ElementDefs.Elem.STATIC),
		"frozen": holder.is_frozen(),
	}


## 组合名 → 中文名
static func combo_name(combo_id: String) -> String:
	match combo_id:
		ElementDefs.COMBO_FIRE_STORM: return "烈焰风暴"
		ElementDefs.COMBO_CORRUPT_FLAME: return "腐化烈焰"
		ElementDefs.COMBO_ICE_CONDUCT: return "冰晶电导"
		ElementDefs.COMBO_SHATTER_ROCK: return "碎裂岩击"
	return combo_id


## 全部联动 id（4 组）
static func all_combos() -> Array:
	return [
		ElementDefs.COMBO_FIRE_STORM, ElementDefs.COMBO_CORRUPT_FLAME,
		ElementDefs.COMBO_ICE_CONDUCT, ElementDefs.COMBO_SHATTER_ROCK,
	]
