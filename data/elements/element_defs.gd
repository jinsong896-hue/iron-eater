class_name ElementDefs
extends RefCounted
## 六元素系统定义 —— 《噬铁者》名词设计分册 第 7 章
##
## 伤害类型口径（分册 7.1）：
##   物理：土(50%)、风(50%)、普通攻击 —— 受护甲减免，可暴击
##   法术：火、冰、雷、毒、土(50%)、风(50%) —— 无视护甲，**不可暴击**
##   真实：土系额外附加 —— 无视一切减免
##   ＊土/风每次攻击同时造成物理与法术两部分，各自独立结算
##
## 本文件只放**数据**；叠层的运行时行为见 element_stack.gd。

## 元素 id
enum Elem { FIRE, FROST, STATIC, EARTH, WIND, POISON }

## 元素中文名
const NAMES := {
	Elem.FIRE: "火", Elem.FROST: "冰", Elem.STATIC: "雷",
	Elem.EARTH: "土", Elem.WIND: "风", Elem.POISON: "毒",
}

## 叠层名称（与词条列表一致）
const STACK_NAMES := {
	Elem.FIRE: "灼烧", Elem.FROST: "寒霜", Elem.STATIC: "静电",
	Elem.EARTH: "岩裂", Elem.WIND: "裂风", Elem.POISON: "毒蚀",
}

## 每元素的完整参数（照分册 7.2~7.7 逐条转写）
## max_stacks      叠层上限
## duration        单层持续时间（0 = 永久，直至目标死亡）
## decay_per_sec   停止攻击后每秒衰减层数（0 = 不衰减）
## dot_per_stack   DOT 每层每秒系数（× 法强）；0 = 无 DOT
## pure_dot        该元素是否纯 DOT（火/毒是；冰/雷是控制+爆发；土/风是混合）
const ELEMENTS := {
	Elem.FIRE: {
		"name": "火", "stack_name": "灼烧", "damage_type": "magic",
		"max_stacks": 50, "duration": 4.0, "decay_per_sec": 5.0,
		"dot_per_stack": 0.04, "pure_dot": true,
		"note": "层数≥20 溅射 3m/40%；≥40 提升至 80%；50 层时每秒法强×2.0",
		"thresholds": {"splash_40": 20, "splash_80": 40},
	},
	Elem.FROST: {
		"name": "冰", "stack_name": "寒霜", "damage_type": "magic",
		"max_stacks": 3, "duration": 3.0, "decay_per_sec": 0.0,
		"dot_per_stack": 0.0, "pure_dot": false,
		"slow_per_stack": 0.25, "aspd_down_per_stack": 0.20,
		"note": "每层移速-25%/攻速-20%；叠满 3 层自动冰冻 1.5s，冰冻结束层数归零",
		"thresholds": {"freeze": 3},
		"freeze_duration": 1.5,
	},
	Elem.STATIC: {
		"name": "雷", "stack_name": "静电", "damage_type": "magic",
		"max_stacks": 10, "duration": 0.0, "decay_per_sec": 0.0,
		"dot_per_stack": 0.0, "pure_dot": false,
		"note": "层数永不衰减；叠满 10 层触发雷暴（法强×4.0 + 4m 内 80% 连锁 + 麻痹 1.5s），触发后归零",
		"thresholds": {"thunderstorm": 10},
		"burst_mult": 4.0, "chain_radius": 4.0, "chain_ratio": 0.8,
		"paralyze_duration": 1.5,
	},
	Elem.EARTH: {
		"name": "土", "stack_name": "岩裂", "damage_type": "mixed",
		"max_stacks": 0, "duration": 0.0, "decay_per_sec": 0.0,
		"dot_per_stack": 0.0, "pure_dot": false,
		"note": "不叠层。每次命中附加真实伤害(攻+法强)×0.2 + 永久降甲 1%（上限 -30%）；20% 概率山崩（法强×5.0 真实 + 眩晕 1s）",
		"true_dmg_ratio": 0.2, "armor_shred_per_hit": 0.01, "armor_shred_cap": 0.30,
		"proc_chance": 0.20, "proc_mult": 5.0, "proc_stun": 1.0,
	},
	Elem.WIND: {
		"name": "风", "stack_name": "裂风", "damage_type": "mixed",
		"max_stacks": 0, "duration": 0.0, "decay_per_sec": 0.0,
		"dot_per_stack": 0.0, "pure_dot": false,
		"note": "不叠层。每次命中击飞 3m；20% 概率生成龙卷风（3s，每秒法强×1.0 物理+法术，牵引）；命中≥3 敌延至 5s 且牵引翻倍",
		"knockup_dist": 3.0, "proc_chance": 0.20,
		"tornado_duration": 3.0, "tornado_duration_multi": 5.0,
		"tornado_dps_mult": 1.0, "multi_target": 3,
	},
	Elem.POISON: {
		"name": "毒", "stack_name": "毒蚀", "damage_type": "magic",
		"max_stacks": 30, "duration": 0.0, "decay_per_sec": 0.0,
		"dot_per_stack": 0.03, "pure_dot": true,
		"vuln_per_stack": 0.01,
		"note": "层数永不衰减；每层全局易伤 +1%（满 30 层 +30%）；10/20/30 层解锁侵蚀/衰弱/虚弱",
		"thresholds": {"erosion": 10, "weakness": 20, "frailty": 30},
		"erosion_slow": 0.20, "weakness_dmg_down": 0.20, "frailty_heal_down": 0.50,
	},
}

## 元素联动的叠层门槛（分册 7.8）——组合定义见 element_combo.gd
const COMBO_FIRE_STORM := "flame_storm"      # 火+风：灼烧≥20 且龙卷风存在
const COMBO_CORRUPT_FLAME := "corrupt_flame" # 火+毒：灼烧≥20 且毒蚀≥15
const COMBO_ICE_CONDUCT := "ice_conduct"     # 雷+冰：静电≥5 且冰冻中
const COMBO_SHATTER_ROCK := "shatter_rock"   # 冰+土：冰冻中且山崩触发


## 按元素取参数
static func get_element(elem: int) -> Dictionary:
	return ELEMENTS.get(elem, {})


## 全部元素 id
static func all_elements() -> Array:
	return ELEMENTS.keys()


## 该元素是否参与叠层（土/风不叠层）
static func stacks(elem: int) -> bool:
	return int(get_element(elem).get("max_stacks", 0)) > 0


## 该元素是否可暴击（只有物理部分可暴击；火冰雷毒与土风法术部分均不可）
static func can_crit(elem: int) -> bool:
	var dt := str(get_element(elem).get("damage_type", "magic"))
	return dt == "physical" or dt == "mixed"   # mixed 的物理部分可暴击，法术部分不可


## 该元素是否无视护甲（法术/真实部分）
static func ignores_armor(elem: int) -> bool:
	var dt := str(get_element(elem).get("damage_type", "magic"))
	return dt != "physical"


## 元素名
static func elem_name(elem: int) -> String:
	return str(NAMES.get(elem, "?"))
