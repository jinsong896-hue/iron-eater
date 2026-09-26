class_name ClassResource
extends RefCounted
## 职业资源运行时 —— 怒气 / 魔力 / 气劲
##
## 策划《角色设计分册》第 2 章原本给 5 职业各一种核心资源，但用户
## 2026-09-26 决定收敛为三种：
##
##   怒气（战士）—— 受击积攒、无自然回复
##   **魔力（法师 / 猎人 / 审判官）**—— 命中+暴击积攒 + 自动回复（三者统一）
##   气劲（武僧）  —— 连击驱动
##
## 本类只管「当前值 / 上限 / 获取 / 消耗 / 回复」，不含任何职业技能逻辑——
## 具体"什么时候加多少"由各职业技能调用方决定（见 SkillSystem 的 kind 分派）。
##
## 与 AttributeSystem 的分工：
##   AttributeSystem 管 11 项基础属性（含 MP 的**加成层**）
##   本类管资源的**当前值容器**（hp 的对偶物）
## 两者不重叠：属性层给的是"上限系数"，本类持有"现在有多少"。

## 资源显示名后缀的不足提示（中文不加空格）
func lack_reason() -> String:
	return "%s不足" % res_name

## 资源定义表：职业 id → {name, max, gain_on_hit, gain_on_taken, regen_per_sec}
##
## ## 三职业统一为「魔力」（2026-09-26 用户决策）
##
## 原本五职业各有一套独立资源（怒气/魔力/专注/裁决/气劲），
## 用户要求「不需要那么多独立资源点，把猎人、法师、审判官三人都改成
## 通用的蓝量」——**连积攒规则也一并统一**。
##
## 于是 mage / hunter / judge 三者现在是**同一套规则**：
##   命中 +5、暴击额外 +5、每秒自动回复 6
##
## **保留的差异**：
##   · `warrior`（怒气）—— 受击积攒、无自然回复，与蓝量手感完全不同，保留
##   · `monk`（气劲）—— 连击体系驱动、不耗武器，保留
##
## 数值取原法师的自动回复（6/秒）作基准，命中/暴击取原判官的档位
##（+5/+8 → 统一为 +5/+5，避免审判官比另外两家强一截）。
##
## ## 历史数值（如需回退参考）
##
##   法师魔力：自动回蓝 6/秒
##   猎人专注：命中 +4、暴击额外 +6
##   判官裁决：命中 +5、暴击额外 +8、击杀 +20
const DEFS := {
	"warrior": {
		"name": "怒气", "max": 100.0,
		"gain_on_hit": 5.0,        # 普攻命中 +5（策划 3.1）
		"gain_on_taken_pct": 0.10, # 受击按伤害比例积攒（策划：受击按比例）
		"regen_per_sec": 0.0,      # 无自然回复
	},
	# —— 以下三者规则完全相同，只是显示名都是「魔力」——
	"mage": {
		"name": "魔力", "max": 100.0,
		"gain_on_hit": 5.0,
		"gain_on_crit_bonus": 5.0,
		"gain_on_taken_pct": 0.0,
		"regen_per_sec": 6.0,      # 自动回蓝
	},
	"hunter": {
		"name": "魔力", "max": 100.0,
		"gain_on_hit": 5.0,
		"gain_on_crit_bonus": 5.0,
		"gain_on_taken_pct": 0.0,
		"regen_per_sec": 6.0,
	},
	"judge": {
		"name": "魔力", "max": 100.0,
		"gain_on_hit": 5.0,
		"gain_on_crit_bonus": 5.0,
		"gain_on_kill": 0.0,       # 统一后不再有击杀奖励（原为 +20）
		"gain_on_taken_pct": 0.0,
		"regen_per_sec": 6.0,
	},
	"monk": {
		"name": "气劲", "max": 100.0,
		"gain_on_hit": 3.0,        # 策划 7.2：命中 +3
		"gain_on_crit_bonus": 3.0, # 暴击额外 +3
		"gain_on_taken_pct": 0.0,
		"regen_per_sec": 2.0,      # 连击续航的兜底回复
	},
}

## 装备词条对**资源获取**的加成（装备参考2 的 `resource_gain_*` 通道）
##
## ## 为什么直接读 equipment_manager 而不是缓存字段
##
## 装备的穿戴/卸下/融合/吞噬都会改变这些值，缓存需要**在每条变更路径上
## 刷新**——而变更路径有 5+ 条（equip/unequip/fuse/devour/读档）。
## 漏掉任何一条就会出现「卸了装备加成还在」或反之。
##
## 直接读 `special_modifiers()` 是**无状态**的，永远与当前装备一致。
## 代价是每次积攒都查一次字典——但那是哈希查找，且积攒是低频事件
##（击杀/受击/命中，不是每帧）。
func _equip_res(key: String) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return 0.0
	var gm = tree.root.get_node_or_null("GameManager")
	if gm == null:
		return 0.0
	var em = gm.get("equipment_manager")
	if em == null or not em.has_method("special_modifiers"):
		return 0.0
	var sp: Dictionary = em.call("special_modifiers")
	return float(sp.get(key, 0.0))

## 当前资源所属职业（空 = 无资源系统）
var class_id := ""
## 资源显示名（怒气/魔力/…）
var res_name := ""
## 当前值
var value := 0.0
## 上限（可被 add_max_bonus 临时提高，如形态增益）
var base_max := 100.0
var _max_bonus := 0.0
## 累计小数部分：命中 +5 之类是整数，但每秒回复是小数，
## 攒够 1 点才进 value，避免 value 变成 12.333333 这种脏数
var _regen_accum := 0.0
## 自然回复速度乘区（形态增益用；1.0 = 无修正）。
## 不改 DEFS 表值——那是被 UI/测试共读的静态常量。
var regen_mult := 1.0


## 按职业初始化。未知职业 → 无资源（value 恒 0，所有操作空转）。
##
## **开局给一部分初始资源**：此前 value 恒从 0 开始，而技能消耗 20~40、
## 战士/猎人/判官又没有任何自然回复——玩家开局放不出任何技能，
## 必须先在怪堆里挨打/命中攒够才能用，实机感受就是"蓝量太低、技能用不了"。
## 给到上限的 50% 后，开局即可放 1~2 个技能，后续靠命中循环续上。
static func create(p_class_id: String) -> ClassResource:
	var r := ClassResource.new()
	r.class_id = p_class_id
	if DEFS.has(p_class_id):
		var d: Dictionary = DEFS[p_class_id]
		r.res_name = str(d.get("name", "资源"))
		r.base_max = float(d.get("max", 100.0))
	r.value = r.max_value() * START_RATIO
	return r


## 开局资源占上限的比例（策划未规定，按"开局能放 1~2 个技能"取半）
const START_RATIO := 0.5


## 是否有资源系统（未知职业为 false）
func is_active() -> bool:
	return DEFS.has(class_id)


## 当前上限（基础 + 形态加成 + 装备词条乘区）
##
## 装备参考2：「最大怒气/魔力/专注/裁决/气劲增加 3%」（`resource_max_pct`）。
## 走乘区而不是固定值——规格写的是百分比。
func max_value() -> float:
	var equip_pct := _equip_res("resource_max_pct")
	return maxf((base_max + _max_bonus) * (1.0 + equip_pct), 1.0)


## 资源比例（0~1），供 UI 画球
func ratio() -> float:
	return clampf(value / maxf(max_value(), 0.001), 0.0, 1.0)


## 提高/降低上限（形态增益用；负值可降但不能低于 1）
func add_max_bonus(delta: float) -> void:
	_max_bonus += delta
	value = minf(value, max_value())


## 清空上限加成（切换形态时调用，避免增益叠加残留）
func clear_max_bonus() -> void:
	_max_bonus = 0.0


## 获得资源。返回实际增加量（满值时为 0）。
func gain(amount: float) -> float:
	if not is_active() or amount <= 0.0:
		return 0.0
	var before := value
	value = minf(value + amount, max_value())
	return value - before


## 消耗资源。不足则**不扣**并返回 false（调用方据此拒绝技能）。
func spend(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if not is_active():
		return false
	if value < amount:
		return false
	value -= amount
	return true


## 是否够消耗
func has(amount: float) -> bool:
	if amount <= 0.0:
		return true
	return is_active() and value >= amount


## 每帧推进自然回复（策划 4.1：法师自动回蓝）。
## 小数累积——每秒 +6 不等于每帧 +0.1，攒够整数点再进 value。
##
## `regen_mult` 是形态对回复速度的乘区（策划 4.3 奥术师「回蓝效率 +20%/层」、
## 4.6 虚空化身「回蓝 +1.5」）。**必须走这个字段而不是改 DEFS 表值**：
## DEFS 是纯静态常量表（还被 UI/测试共读），按形态改写它会污染全局。
func tick(delta: float) -> void:
	if not is_active():
		return
	var d: Dictionary = DEFS[class_id]
	# 装备词条·每秒回复 N 点（`resource_regen_flat`）——与职业基础回复**叠加**。
	# 规格：「每秒回复1点魔力（法师）」。
	var regen := float(d.get("regen_per_sec", 0.0)) + _equip_res("resource_regen_flat")
	if regen <= 0.0:
		return
	_regen_accum += regen * maxf(regen_mult, 0.0) * delta
	var whole := floorf(_regen_accum)
	if whole >= 1.0:
		_regen_accum -= whole
		gain(whole)


## 设置回复速度乘区（形态增益；1.0 = 无修正）
func set_regen_mult(mult: float) -> void:
	regen_mult = maxf(mult, 0.0)


## 命中敌人时按职业规则积攒（普攻与技能命中都该调）
## crit=true 时享受暴击额外积攒（魔力 / 气劲）
func on_hit(crit: bool = false) -> void:
	if not is_active():
		return
	var d: Dictionary = DEFS[class_id]
	_gain_with_bonus(float(d.get("gain_on_hit", 0.0)))
	if crit:
		_gain_with_bonus(float(d.get("gain_on_crit_bonus", 0.0)))


## 击杀敌人时按职业规则积攒（策划 6.1：判官击杀 +20）
func on_kill() -> void:
	if not is_active():
		return
	_gain_with_bonus(float(DEFS[class_id].get("gain_on_kill", 0.0)))


## 连击时积攒（装备参考2：「连击时获得1点气劲」）
##
## 独立于 `on_hit`：规格把它写成单独的触发时机，与命中不是一回事。
func on_combo() -> void:
	if not is_active():
		return
	_gain_with_bonus(0.0)   # 基础为 0，全靠装备词条的 flat 提供


## 受到伤害时按比例积攒（战士怒气）
func on_damage_taken(damage: float) -> void:
	if not is_active() or damage <= 0.0:
		return
	var d: Dictionary = DEFS[class_id]
	var pct := float(d.get("gain_on_taken_pct", 0.0))
	if pct > 0.0:
		_gain_with_bonus(damage * pct)


## 装备词条直接给资源（装备参考2：「击杀敌人获得5点怒气」）
##
## **走这个入口而不是 `gain()`**：`gain` 是裸加法，不吃 `resource_gain_pct`
## 乘区。「怒气获取量 +50%」应该让「获得 5 点」变成 7.5 点——
## 但**不该**让固定值本身被放大（见 `_gain_with_bonus` 的说明）。
##
## 故这里传 `base = 0`，只让 `flat` 部分生效，再统一乘百分比。
func gain_from_equip(amount: float) -> void:
	if not is_active() or amount <= 0.0:
		return
	gain(amount * (1.0 + _equip_res("resource_gain_pct")))


## 带**装备加成**的资源积攒
##
## 装备参考2 里有两类加成：
##   · `resource_gain_flat` —— 「击杀敌人获得 5 点怒气」（固定值）
##   · `resource_gain_pct`  —— 「怒气获取量增加 0.5%」（乘区）
##
## 两者的先后：先乘百分比再叠加固定值。理由是固定值词条写的是
## 「获得 N 点」——那是**绝对点数**，不该被百分比放大
##（否则「获取量+50%」会让「+5点」变成 +7.5，与规格的绝对语义不符）。
func _gain_with_bonus(base: float) -> void:
	var flat := _equip_res("resource_gain_flat")
	if base <= 0.0 and flat <= 0.0:
		return
	gain(base * (1.0 + _equip_res("resource_gain_pct")) + flat)


## 新一层/新一局时重置（资源不跨层保留，避免开局满资源）
func reset() -> void:
	value = 0.0
	_regen_accum = 0.0
	_max_bonus = 0.0
	regen_mult = 1.0
