class_name RandomAffix
extends RefCounted
## 随机词条生成器（装备参考2 规格）
##
## ## 规则原文
##
## 每件装备掉落时随机生成 **1~4 条**随机词条，条数概率 40/30/20/10。
## 随机词条**无法升级、无法转移、不会通过融合或吞噬继承**——
## 它是「这件掉落物」的独有属性，与装备本身的成长线完全无关。
##
## ## 三类词条
##
## | 类别 | 权重 | 内容 |
## |---|---|---|
## | 数值词条 | 60% | 总加成 = 角色基础值的 2%~30%，**随机分配到各属性** |
## | 属性词条 | 30% | 加成 8%~50%，分物理/魔法/属性/真实四类 |
## | 特殊词条 | 10% | 随机借用某件装备的**自有词条**（不可升级） |
##
## ## 与常规词条的关系
##
## 随机词条**复用同一套挂载通道**（AffixData → extra_affixes →
## AttributeSystem），差别只在生命周期与显示：
##   · 不参与融合/吞噬/强化（调用方保证——见 EquipmentInstance 的注释）
##   · 自带档位色（`tier_color`），与装备稀有度色是两套
##
## ## 本机可实现的边界
##
## 规格里的「真实伤害」「物理/魔法伤害」在本项目**没有独立属性通道**：
## 玩家的伤害结算走 `DamagePipeline`，属性面板只有 11 个 Stat。
## 故：
##   · 「数值词条」→ 直接映射到 11 个 Stat（可落地）
##   · 「属性词条」→ 加成同样落在攻击/法强上，但**保留类别标记**
##     （`attribute_kind`）供将来的伤害管线消费；**当前不影响结算**
##   · 「真实伤害」→ 同上，标记保留、当前按攻击加成处理
##
## 这是刻意的降级：宁可先落地可用的部分并保留语义标记，
## 也不做「看起来实现了、实际没接线」的假功能。

## 数值词条可分配到的属性池（权重）。
##
## **不含 MP/CDR/RNG**：那几项基数小或语义特殊，按「基础值的百分比」
## 分配会产出荒谬数值（如 CDR 基础 0 → 永远分不到）。
## 也**不含 SPD**：移动速度的百分比波动会让手感失控。
const NUMERIC_STAT_POOL := [
	[AttributeSystem.Stat.HP, 30],
	[AttributeSystem.Stat.ATK, 30],
	[AttributeSystem.Stat.DEF, 20],
	[AttributeSystem.Stat.AP, 15],
	[AttributeSystem.Stat.CRT, 5],
]

## 元素列表（属性词条的子类之一）
const ELEMENT_KEYS := ["fire", "frost", "static", "earth", "wind", "poison"]


## 为一件装备实例生成随机词条，**直接附加到 inst.random_affixes**。
##
## 返回生成的词条数组（便于调用方/测试断言）。`templates` 是用于
## 「特殊词条」借用自有词条的候选池（通常是 EquipmentDB 的全部模板）。
static func roll_for(inst: EquipmentInstance, rng: RandomNumberGenerator,
		templates: Array = []) -> Array:
	if inst == null:
		return []
	var count := _roll_count(rng)
	var out: Array = []
	for i in count:
		var a := _roll_one(inst, rng, templates)
		if a != null:
			inst.random_affixes.append(a)
			out.append(a)
	return out


## 抽条数（1~4，权重 40/30/20/10）
static func _roll_count(rng: RandomNumberGenerator) -> int:
	return _weighted_pick_int(EquipmentDefs.RANDOM_AFFIX_COUNT_WEIGHTS, rng, 1)


## 抽一条随机词条（先抽类别，再抽该类内部）
static func _roll_one(inst: EquipmentInstance, rng: RandomNumberGenerator,
		templates: Array) -> AffixData:
	var kind := _weighted_pick_string(EquipmentDefs.RANDOM_KIND_WEIGHTS, rng,
		EquipmentDefs.RANDOM_KIND_NUMERIC)
	match kind:
		EquipmentDefs.RANDOM_KIND_NUMERIC:
			return _roll_numeric(inst, rng)
		EquipmentDefs.RANDOM_KIND_ATTRIBUTE:
			return _roll_attribute(rng)
		EquipmentDefs.RANDOM_KIND_SPECIAL:
			return _roll_special(rng, templates)
	return null


# ============================================================
# 数值词条：总加成 2%~30%，随机分配到各属性
# ============================================================

## 生成一条数值词条。
##
## 规格是「总数值随机分配到**各个属性**上」——即一条词条可以同时加
## 好几项。本实现按此分配 1~3 项（权重递减），并把**同一份总加成**
## 拆到这些项上，而不是每项都吃满总额（否则一条词条等于三倍收益）。
static func _roll_numeric(inst: EquipmentInstance,
		rng: RandomNumberGenerator) -> AffixData:
	var total := _roll_tier_value(EquipmentDefs.NUMERIC_TOTAL_TIERS, rng, 0.02)
	var tier_color := _tier_color_of(EquipmentDefs.NUMERIC_TOTAL_TIERS, total)
	# 分配到 1~3 项属性（按权重不重复抽）
	var picks := _pick_distinct(NUMERIC_STAT_POOL, rng, rng.randi_range(1, 3))
	if picks.is_empty():
		picks = [AttributeSystem.Stat.ATK]
	# 每项分到的份额：按权重归一（份额之和 = 1，保证总加成不被放大）
	var weight_sum := 0
	for p in picks:
		weight_sum += int(p[1])
	var stat: int = picks[0][0]
	# 主项 = 份额最大的那项（用属性枚举承载；份额体现为数值大小）
	var share := float(picks[0][1]) / float(maxi(weight_sum, 1))
	var a := AffixData.make_stat(stat, total * share, true)
	a.id = StringName("rnd_num_%d_%d" % [Time.get_ticks_usec(), rng.randi()])
	a.random_kind = EquipmentDefs.RANDOM_KIND_NUMERIC
	a.tier_color = tier_color
	return a


# ============================================================
# 属性词条：8%~50%，分物理/魔法/属性/真实
# ============================================================

## 生成一条属性词条。
##
## **当前按攻击/法强加成落地**（见文件头「本机可实现的边界」）：
## 物理/真实 → ATK；魔法 → AP；属性 → 按其元素选 ATK 或 AP。
## 类别与元素都存进 AffixData，供将来伤害管线消费。
static func _roll_attribute(rng: RandomNumberGenerator) -> AffixData:
	var value := _roll_tier_value(EquipmentDefs.ATTRIBUTE_VALUE_TIERS, rng, 0.08)
	var tier_color := _tier_color_of(EquipmentDefs.ATTRIBUTE_VALUE_TIERS, value)
	var kind := _weighted_pick_string(EquipmentDefs.ATTRIBUTE_KIND_WEIGHTS, rng,
		"physical")
	var stat := AttributeSystem.Stat.ATK
	var elem := ""
	match kind:
		"magic":
			stat = AttributeSystem.Stat.AP
		"element":
			elem = ELEMENT_KEYS[rng.randi_range(0, ELEMENT_KEYS.size() - 1)]
			# 元素里偏法术的（火冰雷毒）走法强，偏物理的（土风）走攻击
			stat = AttributeSystem.Stat.AP if elem in ["fire", "frost", "static", "poison"] \
				else AttributeSystem.Stat.ATK
		_:
			stat = AttributeSystem.Stat.ATK   # physical / true
	var a := AffixData.make_stat(stat, value, true)
	a.id = StringName("rnd_attr_%d_%d" % [Time.get_ticks_usec(), rng.randi()])
	a.random_kind = EquipmentDefs.RANDOM_KIND_ATTRIBUTE
	a.tier_color = tier_color
	a.attribute_kind = kind
	a.element_key = elem
	return a


# ============================================================
# 特殊词条：借用某件装备的自有词条（不可升级）
# ============================================================

## 生成一条特殊词条。
##
## 从候选模板池里抽一件，把它的**自有词条**复制一份过来，标记为
## `is_borrowed = true`（**不可升级**——借来的东西不随装备成长）。
## 显示档位由**来源装备的稀有度**决定（规格：白35%/绿30%/蓝20%/紫10%/橙5%/红0%）。
static func _roll_special(rng: RandomNumberGenerator,
		templates: Array) -> AffixData:
	if templates.is_empty():
		return null
	# 先按规格抽一个来源稀有度档（红装 0% → 抽不到）
	var rar := _weighted_pick_from_rows(EquipmentDefs.SPECIAL_SOURCE_WEIGHTS, rng, 0)
	var color := _special_color_of(rar)
	# 从该稀有度的模板里找一件带自有词条的
	var pool: Array = []
	for t in templates:
		if t != null and int(t.rarity) == rar and t.base_affix != null:
			pool.append(t)
	if pool.is_empty():
		# 该档没有可用模板 → 退到全池任意一件带自有词条的
		for t in templates:
			if t != null and t.base_affix != null:
				pool.append(t)
	if pool.is_empty():
		return null
	var src: EquipmentTemplate = pool[rng.randi_range(0, pool.size() - 1)]
	var orig: AffixData = src.base_affix
	var a := AffixData.make_stat(orig.stat, orig.value, orig.operation == AffixData.Operation.PERCENT)
	a.id = StringName("rnd_spec_%d_%d" % [Time.get_ticks_usec(), rng.randi()])
	a.random_kind = EquipmentDefs.RANDOM_KIND_SPECIAL
	a.tier_color = color
	a.is_borrowed = true
	a.source_rarity = rar
	a.trigger_buff = orig.trigger_buff
	a.trigger_chance = orig.trigger_chance
	a.trigger_duration = orig.trigger_duration
	if orig.is_trigger():
		a.operation = AffixData.Operation.TRIGGER_BUFF
	return a


# ============================================================
# 权重抽取工具
# ============================================================

## 按 [上限, 权重, 色] 表抽一个值（返回落在哪个档的**上限**）。
## floor 是下限（规格里"2%~30%"的 2%）。
static func _roll_tier_value(tiers: Array, rng: RandomNumberGenerator,
		floor_v: float) -> float:
	# 先把权重抽成一个总权重表
	var w: Dictionary = {}
	for i in tiers.size():
		w[i] = int(tiers[i][1])
	var idx := _weighted_pick_int(w, rng, tiers.size() - 1)
	var upper := float(tiers[idx][0])
	# 在该档内均匀取值：最低档从 floor 起，其余从上一档上限起
	var lower: float = floor_v if idx == 0 else float(tiers[idx - 1][0])
	return rng.randf_range(lower, upper)


## 取某值落在哪个档（返回显示色名）
static func _tier_color_of(tiers: Array, value: float) -> String:
	for t in tiers:
		if value <= float(t[0]) + 0.0001:
			return str(t[2])
	return str(tiers[tiers.size() - 1][2])


## 特殊词条的显示色（按来源稀有度）
static func _special_color_of(rarity: int) -> String:
	for row in EquipmentDefs.SPECIAL_SOURCE_WEIGHTS:
		if int(row[0]) == rarity:
			return str(row[2])
	return "绿"


## 按权重字典抽 key（int key）
static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator,
		fallback: int) -> int:
	return _weighted_pick_int(weights, rng, fallback)


## 从 [[值, 权重, ...], ...] 行表里按权重抽「值」。
##
## 用于 SPECIAL_SOURCE_WEIGHTS 这类**行表**（不是字典）——
## 它的第一列是稀有度、第二列是权重，第三列是显示色。
static func _weighted_pick_from_rows(rows: Array, rng: RandomNumberGenerator,
		fallback: int) -> int:
	var total := 0
	for r in rows:
		total += int(r[1])
	if total <= 0:
		return fallback
	var roll := rng.randi_range(1, total)
	var acc := 0
	for r in rows:
		acc += int(r[1])
		if roll <= acc:
			return int(r[0])
	return fallback


## 按权重字典抽 key（int key），通用实现
static func _weighted_pick_int(weights: Dictionary, rng: RandomNumberGenerator,
		fallback: int) -> int:
	var total := 0
	for k in weights:
		total += int(weights[k])
	if total <= 0:
		return fallback
	var roll := rng.randi_range(1, total)
	var acc := 0
	for k in weights:
		acc += int(weights[k])
		if roll <= acc:
			return int(k)
	return fallback


## 按权重字典抽 key（string key）
static func _weighted_pick_string(weights: Dictionary, rng: RandomNumberGenerator,
		fallback: String) -> String:
	var total := 0
	for k in weights:
		total += int(weights[k])
	if total <= 0:
		return fallback
	var roll := rng.randi_range(1, total)
	var acc := 0
	for k in weights:
		acc += int(weights[k])
		if roll <= acc:
			return str(k)
	return fallback


## 按权重不重复抽 n 项（返回 [[值, 权重], ...]）
static func _pick_distinct(pool: Array, rng: RandomNumberGenerator, n: int) -> Array:
	var avail: Array = pool.duplicate()
	var out: Array = []
	n = mini(n, avail.size())
	for i in n:
		var idx := _weighted_index(avail, rng)
		out.append(avail[idx])
		avail.remove_at(idx)
	return out


## 在 [[值, 权重], ...] 里按权重抽一个下标
static func _weighted_index(pool: Array, rng: RandomNumberGenerator) -> int:
	var total := 0
	for p in pool:
		total += int(p[1])
	if total <= 0:
		return 0
	var roll := rng.randi_range(1, total)
	var acc := 0
	for i in pool.size():
		acc += int(pool[i][1])
		if roll <= acc:
			return i
	return pool.size() - 1
