class_name EquipmentDB
extends RefCounted
## 装备模板数据库
## 白装为**基础款**（每槽位 1 件，共 13 件）；绿～橙为完整目录（36 件）按稀有度系数缩放。
## 系数依据《噬铁者》总册 3.5：白 1.0 / 绿 1.6 / 蓝 2.5 / 紫 4.0 / 橙 6.5。
## 每件三词条：基础（穿戴）/ 吞噬（本局永久）/ 融合（作为材料贡献）

static var _templates: Dictionary = {}  ## id -> EquipmentTemplate
static var _initialized: bool = false

## 各稀有度数值系数；索引对应 EquipmentDefs.Rarity（白/绿/蓝/紫/橙/红）
const RARITY_SCALES := [1.0, 1.6, 2.5, 4.0, 6.5, 10.0]

## 各稀有度显示名后缀（白装无后缀）。策划未给具名表，暂用后缀占位
const RARITY_SUFFIX := ["", "·绿", "·蓝", "·紫", "·橙", "·红"]

## 各稀有度 id 后缀
const RARITY_ID_SUFFIX := ["", "_G", "_B", "_P", "_O", "_R"]

# ============================================================
# 通用词条池（名词设计分册第 5 章「装备可附加，21 种」）
# ============================================================
#
# 分两类：
#   · **属性型**（12 种）——改面板或战斗管线上的修饰量。
#     前 11 种的 stat 直接用 AttributeSystem.Stat；
#     后 6 种（生命偷取/击退距离/负效时长/元素穿透/伤害反弹/处决线）
#     不是面板属性，而是伤害结算时的修饰量，用下面的 SPECIAL_STAT 键。
#   · **触发型**（9 种）——命中时按概率给目标施加 BuffDefs 词条。
#     只有 5 种有实际语义（眩晕/破甲/致盲/缴械/范围伤害），
#     其余 4 种（负面时长+/击退距离+ 等）是属性型，归入上表。
#
# 稀有度要求决定该词条**从哪一档开始可能出现**（见 TRIGGER_MIN_RARITY）。

## 属性型通用词条：[id, 显示名, stat_key, 数值下限, 数值上限, 是否百分比, 最低稀有度]
## stat_key 为字符串：AttributeSystem 的 11 项用其枚举名（"atk"/"crt"…），
## 其余 6 项用 SPECIAL_STAT 的键（"lifesteal"/"knockback"/"debuff_dur"
## /"elem_pen"/"reflect"/"execute_line"）。
const GENERIC_STAT_POOL := [
	["gc_crt",      "暴击率+",   "crt",         0.03, 0.10, true,  2],  # 蓝+
	["gc_crd",      "暴击伤害+", "crd",         0.10, 0.30, true,  3],  # 紫+
	["gc_atk",      "攻击力+",   "atk",         0.05, 0.15, true,  0],  # 白+
	["gc_ap",       "法术强度+", "ap",          0.05, 0.15, true,  0],  # 白+
	["gc_def",      "防御+",     "def",         0.05, 0.20, true,  0],  # 白+
	["gc_hp",       "生命值+",   "hp",          0.05, 0.20, true,  0],  # 白+
	["gc_aspd",     "攻速+",     "aspd",        0.05, 0.20, true,  2],  # 蓝+
	["gc_spd",      "移速+",     "spd",         0.05, 0.15, true,  2],  # 蓝+
	["gc_cdr",      "冷却缩减+", "cdr",         0.05, 0.15, true,  2],  # 蓝+
	["gc_rng",      "射程+",     "rng",         0.05, 0.20, true,  3],  # 紫+
	["gc_lifesteal","生命偷取",  "lifesteal",   0.05, 0.15, true,  2],  # 蓝+
	["gc_knockback","击退距离+", "knockback",   0.20, 0.50, true,  2],  # 蓝+
	["gc_debuffdur","负效时长+", "debuff_dur",  0.15, 0.40, true,  3],  # 紫+
	["gc_elempen",  "元素穿透",  "elem_pen",    0.05, 0.15, true,  4],  # 橙+
	["gc_reflect",  "伤害反弹",  "reflect",     0.05, 0.15, true,  2],  # 蓝+
	["gc_execute",  "处决线",    "execute_line",0.15, 0.25, true,  3],  # 紫+
]

## 触发型通用词条：[id, 显示名, 施加的词条 id, 概率下限, 概率上限, 时长(0=用表定), 最低稀有度]
const GENERIC_TRIGGER_POOL := [
	["gt_stun",    "眩晕",     "stun",        0.03, 0.10, 1.0, 2],  # 蓝+
	["gt_armor",   "破甲",     "armor_break", 0.05, 0.15, 4.0, 3],  # 紫+
	["gt_blind",   "致盲",     "blind",       0.05, 0.10, 3.0, 3],  # 紫+
	["gt_disarm",  "缴械",     "disarm",      0.03, 0.08, 3.0, 4],  # 橙+
	["gt_splash",  "范围伤害", "splash",      1.00, 1.00, 0.0, 3],  # 紫+（必触发，见下）
]

## 非面板属性的修饰量键。**值域 100+ 开一个独立命名空间**：
## AttributeSystem.Stat 只到 10，这些扩展量用 100 起，两者不会撞。
## 这样 AffixData.stat 一个字段就能同时承载面板属性与扩展修饰量。
##
## 2026-09-22 扩充：装备参考.txt 里大量「原判不可实现」的机制其实只差一个
## 修饰量通道——加通道 + 在结算点读一次即可，不需要新系统。
## 故把元素抗性/金币/钥匙/格挡/闪避/免疫/冷却刷新/控制类都收进来。
const SPECIAL_STAT := {
	"lifesteal":    {"enum": 100, "out": "life_steal"},      # 造成伤害的 N% 转回血
	"knockback":    {"enum": 101, "out": "knockback_pct"},   # 击退距离 +N%
	"debuff_dur":   {"enum": 102, "out": "debuff_dur_pct"},  # 施加的负面词条时长 +N%
	"elem_pen":     {"enum": 103, "out": "elem_pen_pct"},    # 忽视目标 N% 元素抗性
	"reflect":      {"enum": 104, "out": "reflect_pct"},     # 受近战伤害反弹 N%
	"execute_line": {"enum": 105, "out": "execute_bonus"},   # 对低血目标增伤（分册 +30%）
	# —— 2026-09-22 扩充的通道 ——
	"elem_resist":  {"enum": 106, "out": "elem_resist_pct"}, # 受到的元素伤害 -N%
	"gold_gain":    {"enum": 107, "out": "gold_gain_pct"},   # 金币获取 +N%
	"sell_price":   {"enum": 108, "out": "sell_price_pct"},  # 出售价格 +N%
	"key_drop":     {"enum": 109, "out": "key_drop_pct"},    # 钥匙碎片掉落率 +N%
	"block":        {"enum": 110, "out": "block_pct"},       # 格挡率（完全免伤概率）
	"dodge":        {"enum": 111, "out": "dodge_pct"},       # 闪避率（完全免伤概率）
	"ctrl_resist":  {"enum": 112, "out": "ctrl_resist_pct"}, # 受控时长 -N%
	"cd_refresh":   {"enum": 113, "out": "cd_refresh_pct"},  # 击杀时刷新冷却的概率
	"drop_rate":    {"enum": 114, "out": "drop_rate_pct"},   # 装备掉落率 +N%
	"pickup_range": {"enum": 115, "out": "pickup_range_pct"},# 拾取范围 +N%
	"summon_dmg":   {"enum": 116, "out": "summon_dmg_pct"},  # 召唤物伤害 +N%
	"elem_dmg":     {"enum": 117, "out": "elem_dmg_pct"},    # 元素伤害 +N%
	"true_dmg":     {"enum": 118, "out": "true_dmg_pct"},    # 真实伤害 +N%
	"exp_gain":     {"enum": 119, "out": "exp_gain_pct"},    # 经验获取 +N%（预留）
	"summon_limit": {"enum": 120, "out": "summon_limit"},     # 召唤物上限 +N（整数）
	# —— 2026-09-24 扩充：元素/伤害来源通道拆分（见 ai/元素与自有词条重做计划.md）——
	#
	# **为什么必须拆**：旧实现把所有具体元素塌缩进同一个 `elem_dmg`，
	# 于是「烈焰法杖 +1% 火焰伤害」与「寒霜法杖 +1% 冰霜伤害」在数据层
	# **一字不差**——元素区别整个消失。抗性同理。
	#
	# 注意 `elem_dmg` / `elem_resist` **保留为全局通道**：规格里确有
	# 「元素伤害增加 N%」「元素抗性 N%」的写法，那是真·全元素。
	#
	# 暗影（shadow）**不是**名词设计分册定义的六元素之一（分册只有
	# 火冰雷土风毒），故它只做增伤/抗性，**不参与元素叠层**——
	# 没有灼烧/寒霜/静电那套阈值机制。
	"fire_dmg":     {"enum": 121, "out": "fire_dmg_pct"},
	"frost_dmg":    {"enum": 122, "out": "frost_dmg_pct"},
	"static_dmg":   {"enum": 123, "out": "static_dmg_pct"},
	"earth_dmg":    {"enum": 124, "out": "earth_dmg_pct"},
	"wind_dmg":     {"enum": 125, "out": "wind_dmg_pct"},
	"poison_dmg":   {"enum": 126, "out": "poison_dmg_pct"},
	"shadow_dmg":   {"enum": 127, "out": "shadow_dmg_pct"},
	"fire_resist":  {"enum": 128, "out": "fire_resist_pct"},
	"frost_resist": {"enum": 129, "out": "frost_resist_pct"},
	"static_resist":{"enum": 130, "out": "static_resist_pct"},
	"earth_resist": {"enum": 131, "out": "earth_resist_pct"},
	"wind_resist":  {"enum": 132, "out": "wind_resist_pct"},
	"poison_resist":{"enum": 133, "out": "poison_resist_pct"},
	"shadow_resist":{"enum": 134, "out": "shadow_resist_pct"},
	# —— 2026-09-24 扩充：非元素维度 ——
	#
	# 这些被旧生成器**错塞进元素通道**：「远程伤害增加 3%」变成元素增伤、
	# 「异常状态抗性」变成元素抗性。它们根本不是元素，是独立的维度。
	"ranged_dmg":     {"enum": 135, "out": "ranged_dmg_pct"},      # 远程伤害 +N%
	"aoe_dmg":        {"enum": 136, "out": "aoe_dmg_pct"},         # 范围伤害 +N%
	"trap_dmg":       {"enum": 137, "out": "trap_dmg_pct"},        # 陷阱伤害 +N%
	"projectile_dmg": {"enum": 138, "out": "projectile_dmg_pct"},  # 投射物伤害 +N%
	"debuff_resist":  {"enum": 139, "out": "debuff_resist_pct"},   # 异常状态抗性 +N%
	"shield_power":   {"enum": 140, "out": "shield_power_pct"},    # 护盾强度/获取量 +N%
	"frozen_dmg":     {"enum": 141, "out": "frozen_dmg_pct"},      # 对被冻结目标增伤 +N%
	# —— 2026-09-27：全局伤害减免 ——
	#
	# **为什么必须单独开一条**：装备参考里 5 处「获得 N% 伤害减免」
	# 被旧生成器**错映射成元素抗性**（`elem_resist` / 106）——语义完全不对：
	# 元素抗性只挡元素伤害，而「伤害减免」该挡全部来源。实测
	# 「守护肩甲：生命值低于50%时，获得20%伤害减免」在数据库里就是
	# `[4, 11, 106, 0.2, 0]`，玩家低血时只多了 20% 元素抗性。
	"dmg_reduction":  {"enum": 146, "out": "dmg_reduction_pct"},
	# —— 2026-09-28：受伤转化类 ——
	#
	# 这两条此前都**错映射成 `elem_resist`（元素抗性）**：
	#   「受到伤害的50%转化为护盾」→ 玩家多了 30% 元素抗性（毫不相干）
	#   「受到伤害的30%延迟至5秒内逐渐结算」→ 同上
	"dmg_to_shield":  {"enum": 151, "out": "dmg_to_shield_pct"},  # 受伤的 N% 转成护盾
	"delay_dmg":      {"enum": 152, "out": "delay_dmg_pct"},      # 受伤的 N% 延迟结算
	"dmg_to_shield_cap": {"enum": 153, "out": "dmg_to_shield_cap_pct"},  # 转盾的吸收上限（占最大生命）
	"execute_threshold": {"enum": 154, "out": "execute_threshold"},  # 处决线阈值（生命低于此比例才生效）
	# —— 2026-09-27：冷却刷新按**触发源**分键 ——
	#
	# `cd_refresh` 是个**合并池**，但表里的触发源有三种（击杀 / 闪避 / 暴击），
	# 而消费者只有「击杀」与「闪避」两处。混在一起的后果实测：
	# 「踏虚战靴：闪避成功时刷新冲刺」被当成「击杀时刷新」、
	# 「预言者头盔：暴击时5%概率刷新」同样落到击杀路径——
	# 三件装备的冷却刷新**触发时机全错**。
	#
	# 概率类与必定类也得分：`闪避时有5%概率刷新`（概率 0.05）与
	# `闪避成功时立即刷新`（概率 1.0）语义不同，消费者读同一个键时
	# 两者会互相污染。
	"cd_refresh_dodge": {"enum": 147, "out": "cd_refresh_dodge_pct"},  # 闪避时刷新
	"cd_refresh_crit":  {"enum": 148, "out": "cd_refresh_crit_pct"},   # 暴击时刷新
	# —— 2026-09-26：职业资源点（装备参考2 的「获得 N 点怒气/魔力/…」）——
	# 资源已统一为怒气/魔力/气劲三种，这些词条按「获得 N 点职业资源」处理，
	# 谁装备谁生效（不再绑死某个职业）。
	"res_gain":       {"enum": 142, "out": "resource_gain_flat"},   # 获得 N 点职业资源（固定值）
	"res_gain_pct":   {"enum": 143, "out": "resource_gain_pct"},    # 资源获取量 +N%
	"res_max":        {"enum": 144, "out": "resource_max_pct"},     # 资源上限 +N%
	"res_regen":      {"enum": 145, "out": "resource_regen_flat"},  # 每秒回复 N 点资源
}

## 扩展修饰量的枚举值 → 输出键（special_modifiers 用）
static func special_out_key(enum_val: int) -> String:
	for k in SPECIAL_STAT:
		if int(SPECIAL_STAT[k]["enum"]) == enum_val:
			return str(SPECIAL_STAT[k]["out"])
	return ""

## 扩展修饰量的键 → 枚举值（构造词条时用）
static func special_enum_of(key: String) -> int:
	if SPECIAL_STAT.has(key):
		return int(SPECIAL_STAT[key]["enum"])
	return -1

## 范围伤害词条（gt_splash）的固定参数（分册：攻击力×0.1，2 米内）
const SPLASH_RADIUS := 2.0
const SPLASH_ATK_RATIO := 0.1

## 属性型 stat_key → AttributeSystem.Stat 枚举值（找不到返回 -1）
static func stat_enum_of(key: String) -> int:
	for name in AttributeSystem.STAT_BY_NAME:
		if name == key:
			return int(AttributeSystem.STAT_BY_NAME[name])
	return -1


## 抽样一条**通用属性型词条**（分册第 5 章），用于融合/附魔/商店附加。
##
## 门槛：只从「最低稀有度 ≤ 传入稀有度」的行里抽（策划的稀有度要求：
## 攻击力+ 白+、攻速+ 蓝+、射程+ 紫+、元素穿透 橙+）。
## 数值在策划区间内按稀有度插值——越高级的装备附到越强的词条。
## rng 为空时取区间中点（供测试/无随机源场景），保证不返回 0 值词条。
static func roll_generic_affix(rarity: int, rng: RandomNumberGenerator = null) -> AffixData:
	var pool: Array = []
	for row in GENERIC_STAT_POOL:
		if rarity >= int(row[6]):
			pool.append(row)
	if pool.is_empty():
		return null
	var row: Array = pool[0] if rng == null else pool[rng.randi() % pool.size()]
	var lo: float = float(row[3])
	var hi: float = float(row[4])
	# 稀有度在 [白..红] 上插值：白取下限、红取上限
	var t: float = clampf(
		float(rarity) / float(maxi(EquipmentDefs.Rarity.RED, 1)), 0.0, 1.0)
	var value: float = (lo + hi) / 2.0 if rng == null else lerpf(lo, hi, t)

	var key := str(row[2])
	# 面板属性走 AttributeSystem 枚举；其余（生命偷取等）走 100+ 扩展命名空间
	var stat_id: int = stat_enum_of(key)
	if stat_id < 0:
		stat_id = special_enum_of(key)
	var a := AffixData.make_stat(stat_id, value, bool(row[5]))
	a.id = StringName(str(row[0]))   # 记住池 id，用于去重与展示
	return a


## 元素武器（**占位设计，待策划替换**）
##
## ⚠ 策划《武器设计分册》18 种白装**未给任何武器指定元素**——原文里元素机制
## 挂在红装（传奇）的专属机制上（如 R-01 狱火断头台的火焰爆炸）。
## 为了让元素系统在红装落地前就可用，这里为少数武器按「武器类型语义」指定
## 元素作为**占位**：法术类武器→火、远程穿刺类→毒。待策划出元素武器表后替换。
##
## 键为基础 id（不含稀有度后缀），稀有度变体自动继承。
const WEAPON_ELEMENT := {
	"W11": "fire",     # 学徒长杖 —— 法术武器
	"W09": "poison",   # 猎人长弓 —— 淬毒箭矢
}

## 元素亲和（分册 4.x 词条「所有元素伤害 +15%」）——只挂饰品/护甲，武器不带。
## 键为基础 id，稀有度变体继承；数值固定 15%（分册口径）。
const ELEMENT_AFFINITY_IDS := {
	"J02": 0.15,   # 蓝晶戒指 —— 法术系饰品
	"J04": 0.15,   # 铁链护符
}


## 取某件装备的攻击元素（按基础 id 查占位表；无则空）
static func element_for(template_id: StringName) -> String:
	var base := _base_id(String(template_id))
	return str(WEAPON_ELEMENT.get(base, ""))


## 取某件装备的元素亲和加成（无则 0）
static func affinity_for(template_id: StringName) -> float:
	var base := _base_id(String(template_id))
	return float(ELEMENT_AFFINITY_IDS.get(base, 0.0))


## 去掉稀有度 id 后缀，得基础 id（W11_G → W11）
static func _base_id(tid: String) -> String:
	for suffix in RARITY_ID_SUFFIX:
		if suffix != "" and tid.ends_with(suffix):
			return tid.substr(0, tid.length() - suffix.length())
	return tid


## 注册模板
static func register(template: EquipmentTemplate) -> void:
	if template == null:
		return
	# 元素与元素亲和：统一在此注入，白装与高稀有度克隆都覆盖
	template.element = element_for(template.id)
	template.element_affinity = affinity_for(template.id)
	_templates[template.id] = template


## 获取模板
static func get_template(id: StringName) -> EquipmentTemplate:
	return _templates.get(id)


## 创建并注册模板
static func create_template(id: StringName, display_name: String, rarity: int, category: int, slot: int) -> EquipmentTemplate:
	var t := EquipmentTemplate.new()
	t.id = id
	t.display_name = display_name
	t.rarity = rarity
	t.category = category
	t.slot = slot
	register(t)
	return t


## 按稀有度获取所有模板
static func get_templates_by_rarity(rarity: int) -> Array:
	var result: Array = []
	for t in _templates.values():
		if t.rarity == rarity:
			result.append(t)
	return result


## 按槽位获取模板
static func get_templates_by_slot(slot: int) -> Array:
	var result: Array = []
	for t in _templates.values():
		if t.slot == slot:
			result.append(t)
	return result


## 降级解析：先找精确 id，找不到就按该 id 的**槽位**回退到同槽位的白装。
##
## 为什么需要：`ClassDefs` 的 `start_gear` 是从**完整目录**（12 武器 +
## 18 护甲）里挑的，但白装层只注册了 13 件基础款（每槽位 1 件，这是刻意的
## 设计决定，见测试里"白装 = 基础款"的断言）。于是 11 个被策划点名的
## 起始装备在白装层根本不存在，开局会静默少发装备。
##
## 降级后玩家拿到的仍是"这件装备该在的部位"，只是具体款式退到基础款——
## 比"什么都不发"好，也比"悄悄把白装池扩成 36 件"（会改变掉落手感）克制。
##
## 返回 null 表示该 id 既不存在、其槽位也没有任何白装可回退。
static func resolve_or_white_fallback(id: StringName) -> EquipmentTemplate:
	var exact := get_template(id)
	if exact != null:
		return exact
	var slot := _catalog_slot_of(String(id))
	if slot < 0:
		return null
	var pool := get_templates_by_slot(slot)
	# 只回退白装：起始装备是新手装，不该给绿装以上
	for t in pool:
		if t.rarity == EquipmentDefs.Rarity.WHITE:
			return t
	return pool[0] if pool.size() > 0 else null


## 查完整目录里某 id 应属的槽位（白装层没有该 id 时用它定位部位）。
## 返回 -1 表示完整目录里也没有这个 id（真·打错的模板 id）。
static func _catalog_slot_of(id: String) -> int:
	for row in FULL_WEAPON_TABLE:
		if str(row[0]) == id:
			# 单/双手武器在白装层统一注册在 WEAPON_1 槽（见 init_equipment_db）
			return EquipmentDefs.Slot.WEAPON_1
	for row in FULL_ARMOR_TABLE:
		if str(row[0]) == id:
			return int(row[2])
	for row in FULL_ACCESSORY_TABLE:
		if str(row[0]) == id:
			return EquipmentDefs.Slot.ACCESSORY_1
	return -1


## 模板总数
static func template_count() -> int:
	return _templates.size()


## 获取全部模板
static func all_templates() -> Array:
	return _templates.values()


## 某稀有度的数值系数（越界时回退 1.0）
static func rarity_scale(rarity: int) -> float:
	if rarity < 0 or rarity >= RARITY_SCALES.size():
		return 1.0
	return RARITY_SCALES[rarity]


## 单行定义表：[id, 名称, 武器类型, 标签数组, 基础词条, 吞噬词条, 融合词条]
## 词条格式: [Stat 枚举值, 数值, 是否百分比]
## **白装只保留基础款**（每类 1 件做基准），完整武器目录见高稀有度生成
const WEAPON_TABLE := [
	["W01", "铁制单手剑", "sword", ["近战", "物理"], [Stat.ATK, 35.0, false], [Stat.ATK, 0.5, false], [Stat.ATK, 0.03, true]],
	["W06", "铁制巨剑", "greatsword", ["近战", "物理"], [Stat.ATK, 56.0, false], [Stat.ATK, 0.7, false], [Stat.ATK, 0.04, true]],
	["W09", "猎人长弓", "bow", ["远程", "物理"], [Stat.ATK, 44.0, false], [Stat.RNG, 0.002, true], [Stat.RNG, 0.05, true]],
	["W11", "学徒长杖", "staff", ["远程", "长杆", "法术"], [Stat.AP, 45.0, false], [Stat.AP, 0.5, false], [Stat.AP, 0.04, true]],
]

## 护甲表：[id, 名称, 部位槽位, 护甲类, 基础, 吞噬, 融合] —— 6 部位各 1 件基础款
const ARMOR_TABLE := [
	["A03", "铁制头盔", EquipmentDefs.Slot.HEAD, EquipmentDefs.ArmorClass.HEAVY, [Stat.DEF, 6.0, false], [Stat.DEF, 0.3, false], [Stat.DEF, 0.03, true]],
	["A05", "皮革胸甲", EquipmentDefs.Slot.CHEST, EquipmentDefs.ArmorClass.MEDIUM, [Stat.HP, 28.0, false], [Stat.HP, 1.5, false], [Stat.HP, 0.03, true]],
	["A08", "皮革护肩", EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.ArmorClass.MEDIUM, [Stat.ATK, 3.0, false], [Stat.ATK, 0.2, false], [Stat.ATK, 0.02, true]],
	["A11", "皮革手套", EquipmentDefs.Slot.HANDS, EquipmentDefs.ArmorClass.MEDIUM, [Stat.CRT, 0.01, true], [Stat.CRT, 0.001, true], [Stat.CRT, 0.02, true]],
	["A14", "皮革腿甲", EquipmentDefs.Slot.LEGS, EquipmentDefs.ArmorClass.MEDIUM, [Stat.HP, 24.0, false], [Stat.HP, 1.0, false], [Stat.HP, 0.03, true]],
	["A16", "布质软靴", EquipmentDefs.Slot.FEET, EquipmentDefs.ArmorClass.LIGHT, [Stat.SPD, 0.04, true], [Stat.SPD, 0.002, true], [Stat.SPD, 0.03, true]],
]

## 饰品表：[id, 名称, 基础, 吞噬, 融合]
const ACCESSORY_TABLE := [
	["J01", "铁戒指", [Stat.ATK, 4.0, false], [Stat.ATK, 0.3, false], [Stat.ATK, 0.03, true]],
	["J02", "蓝晶戒指", [Stat.AP, 4.0, false], [Stat.AP, 0.3, false], [Stat.AP, 0.03, true]],
	["J03", "骨牙吊坠", [Stat.HP, 25.0, false], [Stat.HP, 1.0, false], [Stat.HP, 0.03, true]],
]

## 高稀有度克隆用的**完整目录**（12 武器 + 18 护甲 + 6 饰品）
## 白装只取上表的子集，绿及以上保留全部类型——稀有度带来的是种类扩张
const FULL_WEAPON_TABLE := [
	["W01", "铁制单手剑", "sword", ["近战", "物理"], [Stat.ATK, 35.0, false], [Stat.ATK, 0.5, false], [Stat.ATK, 0.03, true]],
	["W02", "短匕首", "dagger", ["近战", "物理"], [Stat.ATK, 26.0, false], [Stat.ASPD, 0.002, true], [Stat.ASPD, 0.03, true]],
	["W03", "轻型手弩", "crossbow", ["远程", "物理"], [Stat.ATK, 30.0, false], [Stat.CRT, 0.001, true], [Stat.CRT, 0.02, true]],
	["W04", "铁制手斧", "axe", ["近战", "物理"], [Stat.ATK, 38.0, false], [Stat.ATK, 0.5, false], [Stat.CRD, 0.03, true]],
	["W05", "铁制圆盾", "shield", ["其他"], [Stat.DEF, 12.0, false], [Stat.DEF, 0.5, false], [Stat.DEF, 0.04, true]],
	["W06", "铁制巨剑", "greatsword", ["近战", "物理"], [Stat.ATK, 56.0, false], [Stat.ATK, 0.7, false], [Stat.ATK, 0.04, true]],
	["W07", "双手巨斧", "greataxe", ["近战", "物理"], [Stat.ATK, 60.0, false], [Stat.CRD, 0.003, true], [Stat.CRD, 0.05, true]],
	["W08", "铁制长枪", "spear", ["近战", "长杆", "物理"], [Stat.ATK, 48.0, false], [Stat.ATK, 0.5, false], [Stat.RNG, 0.04, true]],
	["W09", "猎人长弓", "bow", ["远程", "物理"], [Stat.ATK, 44.0, false], [Stat.RNG, 0.002, true], [Stat.RNG, 0.05, true]],
	["W10", "重型弩", "heavy_crossbow", ["远程", "物理"], [Stat.ATK, 52.0, false], [Stat.CRT, 0.001, true], [Stat.CRT, 0.03, true]],
	["W11", "学徒长杖", "staff", ["远程", "长杆", "法术"], [Stat.AP, 45.0, false], [Stat.AP, 0.5, false], [Stat.AP, 0.04, true]],
	["W12", "铁制战镰", "scythe", ["近战", "长杆", "物理"], [Stat.ATK, 50.0, false], [Stat.ATK, 0.5, false], [Stat.ASPD, 0.03, true]],
]

const FULL_ARMOR_TABLE := [
	["A01", "布质兜帽", EquipmentDefs.Slot.HEAD, EquipmentDefs.ArmorClass.LIGHT, [Stat.AP, 4.0, false], [Stat.AP, 0.3, false], [Stat.AP, 0.03, true]],
	["A02", "皮革头罩", EquipmentDefs.Slot.HEAD, EquipmentDefs.ArmorClass.MEDIUM, [Stat.CRT, 0.01, true], [Stat.CRT, 0.001, true], [Stat.CRT, 0.02, true]],
	["A03", "铁制头盔", EquipmentDefs.Slot.HEAD, EquipmentDefs.ArmorClass.HEAVY, [Stat.DEF, 6.0, false], [Stat.DEF, 0.3, false], [Stat.DEF, 0.03, true]],
	["A04", "布质长袍", EquipmentDefs.Slot.CHEST, EquipmentDefs.ArmorClass.LIGHT, [Stat.MP, 12.0, false], [Stat.MP, 1.0, false], [Stat.MP, 0.04, true]],
	["A05", "皮革胸甲", EquipmentDefs.Slot.CHEST, EquipmentDefs.ArmorClass.MEDIUM, [Stat.HP, 28.0, false], [Stat.HP, 1.5, false], [Stat.HP, 0.03, true]],
	["A06", "铁制胸甲", EquipmentDefs.Slot.CHEST, EquipmentDefs.ArmorClass.HEAVY, [Stat.HP, 40.0, false], [Stat.HP, 2.0, false], [Stat.HP, 0.04, true]],
	["A07", "布质披肩", EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.ArmorClass.LIGHT, [Stat.CDR, 0.01, true], [Stat.CDR, 0.001, true], [Stat.CDR, 0.02, true]],
	["A08", "皮革护肩", EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.ArmorClass.MEDIUM, [Stat.ATK, 3.0, false], [Stat.ATK, 0.2, false], [Stat.ATK, 0.02, true]],
	["A09", "铁制肩甲", EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.ArmorClass.HEAVY, [Stat.DEF, 7.0, false], [Stat.DEF, 0.3, false], [Stat.DEF, 0.03, true]],
	["A10", "布质手套", EquipmentDefs.Slot.HANDS, EquipmentDefs.ArmorClass.LIGHT, [Stat.ASPD, 0.02, true], [Stat.ASPD, 0.001, true], [Stat.ASPD, 0.02, true]],
	["A11", "皮革手套", EquipmentDefs.Slot.HANDS, EquipmentDefs.ArmorClass.MEDIUM, [Stat.CRT, 0.01, true], [Stat.CRT, 0.001, true], [Stat.CRT, 0.02, true]],
	["A12", "铁制护手", EquipmentDefs.Slot.HANDS, EquipmentDefs.ArmorClass.HEAVY, [Stat.DEF, 5.0, false], [Stat.DEF, 0.2, false], [Stat.DEF, 0.02, true]],
	["A13", "布质长裤", EquipmentDefs.Slot.LEGS, EquipmentDefs.ArmorClass.LIGHT, [Stat.MP, 10.0, false], [Stat.MP, 1.0, false], [Stat.MP, 0.03, true]],
	["A14", "皮革腿甲", EquipmentDefs.Slot.LEGS, EquipmentDefs.ArmorClass.MEDIUM, [Stat.HP, 24.0, false], [Stat.HP, 1.0, false], [Stat.HP, 0.03, true]],
	["A15", "铁制腿甲", EquipmentDefs.Slot.LEGS, EquipmentDefs.ArmorClass.HEAVY, [Stat.DEF, 8.0, false], [Stat.DEF, 0.4, false], [Stat.DEF, 0.03, true]],
	["A16", "布质软靴", EquipmentDefs.Slot.FEET, EquipmentDefs.ArmorClass.LIGHT, [Stat.SPD, 0.04, true], [Stat.SPD, 0.002, true], [Stat.SPD, 0.03, true]],
	["A17", "皮革战靴", EquipmentDefs.Slot.FEET, EquipmentDefs.ArmorClass.MEDIUM, [Stat.SPD, 0.02, true], [Stat.SPD, 0.001, true], [Stat.SPD, 0.02, true]],
	["A18", "铁制战靴", EquipmentDefs.Slot.FEET, EquipmentDefs.ArmorClass.HEAVY, [Stat.DEF, 5.0, false], [Stat.DEF, 0.2, false], [Stat.DEF, 0.02, true]],
]

const FULL_ACCESSORY_TABLE := [
	["J01", "铁戒指", [Stat.ATK, 4.0, false], [Stat.ATK, 0.3, false], [Stat.ATK, 0.03, true]],
	["J02", "蓝晶戒指", [Stat.AP, 4.0, false], [Stat.AP, 0.3, false], [Stat.AP, 0.03, true]],
	["J03", "骨牙吊坠", [Stat.HP, 25.0, false], [Stat.HP, 1.0, false], [Stat.HP, 0.03, true]],
	["J04", "铁链护符", [Stat.DEF, 4.0, false], [Stat.DEF, 0.2, false], [Stat.DEF, 0.03, true]],
	["J05", "猎手护符", [Stat.ASPD, 0.02, true], [Stat.ASPD, 0.001, true], [Stat.ASPD, 0.02, true]],
	["J06", "风纹护符", [Stat.SPD, 0.02, true], [Stat.SPD, 0.001, true], [Stat.SPD, 0.02, true]],
]

## Stat 枚举引用（与 AttributeSystem.Stat 一致，写表用）
enum Stat { HP, ATK, DEF, SPD, ASPD, RNG, AP, MP, CDR, CRT, CRD }

## 白装件数（基础款），供测试与文档引用
const WHITE_COUNT := 13


## 初始化装备数据：13 件白装基础款 + 绿～橙的完整目录克隆
## （红装按策划是逐件设计的独立机制，不在此按系数生成）
static func init_equipment_db() -> void:
	if _initialized:
		return
	_initialized = true

	# 白装：基础款
	for row in WEAPON_TABLE:
		var t := create_template(
			StringName(row[0]), row[1],
			EquipmentDefs.Rarity.WHITE, EquipmentDefs.Category.WEAPON,
			EquipmentDefs.Slot.WEAPON_1
		)
		t.weapon_type = row[2]
		for tag in row[3]:
			t.tags.append(str(tag))
		_apply_affixes(t, row[4], row[5], row[6])

	for row in ARMOR_TABLE:
		var t := create_template(
			StringName(row[0]), row[1],
			EquipmentDefs.Rarity.WHITE, EquipmentDefs.Category.ARMOR,
			row[2]
		)
		t.armor_class = row[3]
		_apply_affixes(t, row[4], row[5], row[6])

	for row in ACCESSORY_TABLE:
		var t := create_template(
			StringName(row[0]), row[1],
			EquipmentDefs.Rarity.WHITE, EquipmentDefs.Category.ACCESSORY,
			EquipmentDefs.Slot.ACCESSORY_1
		)
		_apply_affixes(t, row[2], row[3], row[4])

	# 绿～橙：完整目录按系数缩放
	for rarity in range(EquipmentDefs.Rarity.GREEN, EquipmentDefs.Rarity.ORANGE + 1):
		_generate_rarity(rarity)

	# 策划「装备参考2」筛选后的装备池（188 件）
	#
	# **在占位目录之后注册**：CURATED 用的是自己的 id（G001/B001/…），
	# 与 FULL_*_TABLE 克隆出的 id（W01_G 等）不冲突，两者并存。
	# 掉落池因此同时包含「占位克隆」与「策划实装」——
	# 前者保证每个部位/稀有度都有货，后者提供有设计感的装备。
	_load_curated_table()

	# 红装：策划口径是**逐件独立机制设计**（武器分册第 5 章，如"狱火断头台"
	# 的火焰爆炸），不是系数克隆。但第 6 层起 Boss 保底即红装
	# （FloorDefs.boss_drop / GameBalance.BOSS_PITY_ORANGE_MAX_FLOOR），
	# 池空会让 _random_template_of_rarity 回退到**白装**——
	# 第 6~8 层 Boss 掉白装，比占位红装更糟。
	# 故先按同系数模式生成占位红装，待策划给出逐件机制表后替换这行。
	# ⚠ 占位：这些红装的机制与普通装备无异，只有数值倍率更高。
	_generate_rarity(EquipmentDefs.Rarity.RED)


## 按稀有度生成完整目录（数值按系数缩放，名称加后缀）
static func _generate_rarity(rarity: int) -> void:
	var scale := rarity_scale(rarity)
	var suffix: String = RARITY_SUFFIX[rarity]
	var id_suffix: String = RARITY_ID_SUFFIX[rarity]

	for row in FULL_WEAPON_TABLE:
		var t := create_template(
			StringName(str(row[0]) + id_suffix), str(row[1]) + suffix,
			rarity, EquipmentDefs.Category.WEAPON, EquipmentDefs.Slot.WEAPON_1
		)
		t.weapon_type = row[2]
		for tag in row[3]:
			t.tags.append(str(tag))
		_apply_affixes(t, _scale_affix(row[4], scale), _scale_affix(row[5], scale), _scale_affix(row[6], scale))

	for row in FULL_ARMOR_TABLE:
		var t := create_template(
			StringName(str(row[0]) + id_suffix), str(row[1]) + suffix,
			rarity, EquipmentDefs.Category.ARMOR, row[2]
		)
		t.armor_class = row[3]
		_apply_affixes(t, _scale_affix(row[4], scale), _scale_affix(row[5], scale), _scale_affix(row[6], scale))

	for row in FULL_ACCESSORY_TABLE:
		var t := create_template(
			StringName(str(row[0]) + id_suffix), str(row[1]) + suffix,
			rarity, EquipmentDefs.Category.ACCESSORY, EquipmentDefs.Slot.ACCESSORY_1
		)
		_apply_affixes(t, _scale_affix(row[2], scale), _scale_affix(row[3], scale), _scale_affix(row[4], scale))


## 按系数缩放词条数值（百分比词条同步缩放，否则高稀有度只有面板涨）
## affix 格式: [stat, value, is_percent]
static func _scale_affix(affix: Array, scale: float) -> Array:
	return [affix[0], affix[1] * scale, affix[2]]


## 按稀有度生成**触发型通用词条**（分册第 5 章的 9 种触发型）。
##
## 数量随稀有度递增（白装没有、橙装 2 条），概率在策划区间内按稀有度取档：
## 稀有度越高越接近区间上限（蓝装取下限、橙装取上限）。
## rng 用固定种子（按 id 派生），保证同一件装备每次都生成相同的词条——
## 否则每次查表都换一套，背包里的装备词条会"漂移"。
static func _generate_trigger_affixes(rarity: int, id_seed: String) -> Array[AffixData]:
	var out: Array[AffixData] = []
	if rarity <= EquipmentDefs.Rarity.GREEN:
		return out   # 白/绿装无触发词条

	# 可选池：稀有度达到门槛的才进池
	var pool: Array = []
	for row in GENERIC_TRIGGER_POOL:
		if rarity >= int(row[6]):
			pool.append(row)
	if pool.is_empty():
		return out

	# 条数：蓝 1 / 紫 1 / 橙 2 / 红 2
	var count: int = 2 if rarity >= EquipmentDefs.Rarity.ORANGE else 1
	count = mini(count, pool.size())

	# 用 id 派生的确定性 rng 挑词条（同 id 每次结果一致）
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id_seed)

	var picked: Array = []
	var avail: Array = pool.duplicate()
	for _i in count:
		if avail.is_empty():
			break
		var idx: int = rng.randi() % avail.size()
		picked.append(avail[idx])
		avail.remove_at(idx)

	for row in picked:
		var lo: float = float(row[3])
		var hi: float = float(row[4])
		# 稀有度在 [蓝..红] 上的插值：蓝取下限、红取上限
		var t: float = clampf(
			float(rarity - EquipmentDefs.Rarity.BLUE) /
			float(maxi(EquipmentDefs.Rarity.RED - EquipmentDefs.Rarity.BLUE, 1)),
			0.0, 1.0)
		var chance: float = lerpf(lo, hi, t)
		out.append(AffixData.make_trigger(str(row[2]), chance, float(row[5])))
	return out


## 应用三词条到模板
## 装配一件装备的词条（装备参考2 规格）。
##
## 表列顺序（策划表）：
## `[id, 名, 武器类型, 标签, 槽位, 类别, 基础, 自有, 吞噬, 融合, 触发, 时长, 层数]`
## 白装克隆表只有前三项，故 own/触发三项带默认值。
## 装配一件装备的词条（装备参考2 规格）。
##
## **子表格式**：每个词条列是一个数组，元素是**单条词条规格**。
## 这样复合词条（用「；」分隔的两条效果）能各占一项，
## 而不是像旧实现那样只取前半句。
##
## 单条词条规格的形态（按 operation 分）：
##   [stat, value, is_percent]                      —— 面板属性
##   [Operation.BONUS_ELEMENT, elem, ratio]         —— 附带元素伤害
##   [Operation.STACK_GAIN, trigger, stat, value]   —— 触发叠层
##   [Operation.TRIGGER_BUFF, buff_id, chance, dur] —— 命中施加词条
##   [Operation.PERIODIC, interval, buff_id, dur]   —— 周期性效果
##   [Operation.CHARGE, stat, per_sec_pct, max_pct] —— 蓄力储存
##
## 注：**低血（Trigger.LOW_HP）不是效果类型而是触发条件**——
## 它走面板属性词条 + trigger 字段，不单开一个 Operation。
static func _apply_affixes(t: EquipmentTemplate, base, devour, fusion, own = [],
		own_txt := "", devour_txt := "", fusion_txt := "") -> void:
	t.base_affixes = _make_affix_list(base)
	t.devour_affixes = _make_affix_list(devour)
	t.fusion_affixes = _make_affix_list(fusion)
	t.own_affixes = _make_affix_list(own)
	t.trigger_affixes = _generate_trigger_affixes(t.rarity, str(t.id))
	# 三列原文（逐字）。图鉴按它渲染——机制型词条的 `stat` 恒为 0，
	# 只按属性渲染会输出「生命值 +0.0」（实测 46% 的词条如此）。
	t.own_text = own_txt
	t.devour_text = devour_txt
	t.fusion_text = fusion_txt


## 子表 → AffixData 列表。
##
## **向后兼容**：旧表传的是单条（`[stat, value, is_percent]`），
## 新表传的是子表（`[[...], [...]]`）。按首元素类型区分：
## 首元素是 Array → 子表；否则 → 单条，包成一项。
static func _make_affix_list(spec) -> Array[AffixData]:
	var out: Array[AffixData] = []
	if spec == null:
		return out
	if not (spec is Array) or spec.is_empty():
		return out
	# **嵌套数组**（多属性规格，如「全属性+3%」展开成的 8 条）
	#
	# ## 这里此前只认**一层**嵌套，更深的一律静默变 0 条
	#
	# 判据原本是 `spec[0] is Array`，然后对每个元素调 `_make_one_affix`——
	# 若元素本身还是数组（三层形态 `[[[…],[…]]]`），`_make_one_affix`
	# 拿到的不是规格而是数组，返回 null，**整条词条消失且不报错**。
	# 实测「被腐蚀的长剑 / 传奇共鸣」的多属性词条在 HEAD 里就是三层，
	# 一直解析成 0 条——忠实度检查器看不出来（它查的是 trace 里的文本，
	# 而文本格式是对的）。
	#
	# 现改为**递归展平到叶子**：只要当前是数组且首元素还是数组，
	# 就继续往下；找到「首元素不是数组」的那一层才当规格处理。
	if spec[0] is Array:
		for one in spec:
			# **只有「下一层还是数组」才继续递归**——
			# 否则 `one` 本身就是一条规格（如 `[8, {...}]`，size=2），
			# 递归进去会因 `size >= 3` 判据不成立而**整条丢失**。
			# 实测这么写会让全部 SKILL_MOD 词条变 0 条。
			if one is Array and not one.is_empty() and one[0] is Array:
				out.append_array(_make_affix_list(one))
			else:
				var a := _make_one_affix(one)
				if a != null:
					out.append(a)
		return out
	if spec.size() >= 3:
		var a2 := _make_one_affix(spec)
		if a2 != null:
			out.append(a2)
	return out


## 单条词条规格 → AffixData。
##
## ## 分派规则：**看第三项的类型，不看首项的数值**
##
## 面板属性形态是 `[stat, value, is_percent]`——第三项是 **bool**；
## 规格化词条形态是 `[Operation.X, ...]`——第三项是 **字符串或数字**。
##
## **不能用「首项 >= Operation.BONUS_ELEMENT」判断**：`Stat.AP = 6`
## 而 `Operation.BONUS_ELEMENT = 3`，`6 >= 3` 成立 → 面板属性会被
## 误判成 BONUS_ELEMENT（实测踩到：W11 学徒长杖的 AP 词条被吃掉）。
static func _make_one_affix(spec: Array) -> AffixData:
	if spec == null or spec.size() < 2:
		return null
	# 面板属性：[stat, value, is_percent]，第三项是 bool
	if spec.size() >= 3 and spec[2] is bool:
		return _make_affix(spec)
	# 规格化词条：[Operation.X, ...]
	var first = spec[0]
	if first is int:
		var a := AffixData.new(0, 0.0, int(first))
		match int(first):
			AffixData.Operation.BONUS_ELEMENT:
				a.element_key = str(spec[1])
				a.value = float(spec[2]) if spec.size() > 2 else 0.0
			AffixData.Operation.STACK_GAIN:
				a.trigger = int(spec[1])
				a.stat = int(spec[2])
				a.value = float(spec[3]) if spec.size() > 3 else 0.0
				a.stack_max = int(spec[4]) if spec.size() > 4 else 0
				# 第 6 项（可选）：条件阈值。目前只有 `Trigger.LOW_HP` 用得上
				# ——「生命低于30%时…」与「生命低于50%时…」是**两条不同的
				# 词条**，必须各自带阈值，否则会退化成「统一按 50% 判」。
				a.hp_threshold = float(spec[5]) if spec.size() > 5 else 0.0
				# 第 7 项（可选）：参数字典。用于「满层爆发要做什么」这类
				# **规格复杂到桩函数兜不住**的效果（预言者王冠的
				# 「必暴 + 300% 伤害 + 传播2人各3层」）。
				if spec.size() > 6 and spec[6] is Dictionary:
					a.trigger_params = (spec[6] as Dictionary).duplicate()
			AffixData.Operation.TRIGGER_BUFF:
				a.trigger_buff = str(spec[1])
				a.trigger_chance = float(spec[2]) if spec.size() > 2 else 0.0
				a.trigger_duration = float(spec[3]) if spec.size() > 3 else 0.0
				# 数值覆盖（第 5 项，可选）：同一条 buff id 承载不同数值
				# （「减少50%伤害」vs「减少30%伤害」），见 trigger_params 说明。
				if spec.size() > 4 and spec[4] is Dictionary:
					a.trigger_params = spec[4]
					# **触发时机覆盖**：默认 `TRIGGER_BUFF` 由命中路径消费，
					# 但有些词条的效果目标是**攻击者**而非自己
					#（「反弹伤害有10%概率眩晕攻击者」）——那类必须显式声明
					# `{"trigger": ON_REFLECT}`，否则会被挂到自己身上。
					if a.trigger_params.has("trigger"):
						a.trigger = int(a.trigger_params["trigger"])
			AffixData.Operation.PERIODIC:
				a.value = float(spec[1]) if spec.size() > 1 else 0.0
				a.trigger_buff = str(spec[2]) if spec.size() > 2 else ""
				a.duration = float(spec[3]) if spec.size() > 3 else 0.0
				# 第 5 项（可选）：参数字典。周期性 buff 的**数值**来自装备
				#（「每10秒获得随机元素抗性+30%」——BuffDefs 表里写不了这个 30%），
				# 故由施加方在 `register_equipment_stack` 时带上。
				if spec.size() > 4 and spec[4] is Dictionary:
					a.trigger_params = (spec[4] as Dictionary).duplicate()
			AffixData.Operation.CHARGE:
				a.stat = int(spec[1])
				a.value = float(spec[2]) if spec.size() > 2 else 0.0
				a.full_stack_bonus = float(spec[3]) if spec.size() > 3 else 0.0
			AffixData.Operation.GRANT_SKILL:
				# 装备参考2：133 件装备的自有词条**就是技能本身**。
				# 生成器把这类识别成「技能」放进 EquipmentSkills 后，
				# 若不在 own_affixes 留痕迹，图鉴/背包的【自有词条】就是空的
				#（实测 129 件如此）——玩家看不出这件装备为什么有技能。
				a.granted_skill = str(spec[1]) if spec.size() > 1 else ""
				a.granted_skill_name = str(spec[2]) if spec.size() > 2 else ""
			AffixData.Operation.SKILL_MOD:
				# 修改**某个已存在技能**的行为（装备参考2：融合列的
				# 「裂地斩命中3个以上敌人时伤害提升至700%」「战吼同时嘲讽敌人1秒」）。
				#
				# 参数整体存进 `trigger_params`——该字段本就存在（触发型词条
				# 用它传额外参数），语义相符，无需新增字段。
				#
				# **不能压成 STACK_GAIN**：那会变成「玩家某事件时获得属性」，
				# 与「改那个技能」完全是两回事。
				if spec.size() > 1 and spec[1] is Dictionary:
					a.trigger_params = (spec[1] as Dictionary).duplicate()
		return a
	return null


## 构建面板属性词条（旧形态：[stat, value, is_percent]）
static func _make_affix(affix: Array) -> AffixData:
	if affix == null or affix.size() < 3:
		return null
	var op := AffixData.Operation.PERCENT if affix[2] else AffixData.Operation.FLAT
	return AffixData.new(affix[0], affix[1], op)


## 策划「装备参考2」筛选后的装备池（188 件，2026-09-22 导入）
##
## 来源：ai/装备参考.txt（390 件原始设计）+ 策划书/装备参考2.docx（规格）
## 筛选规则（用户指定）：
##   1. 去掉功能重复的纯上位装备（同名跨稀有度只保留一件）
##   2. 稀有度定位不符的调整到对应稀有度
##   3. 去掉机制过于复杂的（叠层/循环/多段触发）
##   4. 去掉代码层面无法实现的（格挡/闪避率/元素抗性/金币/经验/掉落率/拾取范围/
##      召唤/免疫/霸体/无敌/刷新冷却/沉默/恐惧/嘲讽/击飞/牵引/弹射/残影）
##   5. 所有职业通用，无职业专属（去掉含怒气/魔力/专注/裁决/气劲的）
##
## 格式：[id, 名称, 武器类型, 标签, 槽位, 类别, 基础, 吞噬, 融合]
## **独立于 FULL_*_TABLE**：那三张表是白装克隆用的占位目录，
## 本表是策划实打实设计的装备，两者并存不冲突。


## 加载策划「装备参考2」筛选后的装备池。
##
## 表里每行是
## `[id, 名称, 武器类型, 标签, 槽位, 类别, 基础属性, 自有词条, 吞噬词条, 融合词条]`。
## 与 `_generate_rarity` 的区别：那三张表是**白装克隆**（名称加后缀、
## 数值按稀有度系数缩放），本表是**策划逐件设计**的装备，数值原样使用。
##
## **四词条与规格的对应**（装备参考2 规格）：
##   基础属性 = row[6]（武器攻击力这类面板数值）
##   自有词条 = row[7]（装备独有，仅穿戴时生效，同件融合会升级）
##   吞噬词条 = row[8]（被吞噬时给角色的加成，同件吞噬会升级）
##   融合词条 = row[9]（作为素材融合时给主装备的加成，同件融合会升级）
static func _load_curated_table() -> void:
	for row in CURATED_TABLE:
		var t := create_template(
			StringName(str(row[0])), str(row[1]),
			_rarity_of_id(str(row[0])), int(row[5]), int(row[4])
		)
		t.weapon_type = str(row[2])
		for tag in row[3]:
			t.tags.append(str(tag))
		# 注意参数顺序：_apply_affixes(base, devour, fusion, own, 三列原文)
		# 第 11/12/13 项是策划原文（逐字），旧表没有则留空 → 回退属性渲染。
		_apply_affixes(t, row[6], row[8], row[9], row[7],
			str(row[10]) if row.size() > 10 else "",
			str(row[11]) if row.size() > 11 else "",
			str(row[12]) if row.size() > 12 else "")


## 从策划表的 id 前缀推稀有度（G=绿 / B=蓝 / P=紫 / O=橙）。
##
## 表里不重复写稀有度列——id 前缀已经是它，再写一列就有两份真相，
## 改一处漏一处时会出现「id 说绿装、稀有度说橙装」的错位。
static func _rarity_of_id(id: String) -> int:
	if id.is_empty():
		return EquipmentDefs.Rarity.WHITE
	match id[0]:
		"G": return EquipmentDefs.Rarity.GREEN
		"B": return EquipmentDefs.Rarity.BLUE
		"P": return EquipmentDefs.Rarity.PURPLE
		"O": return EquipmentDefs.Rarity.ORANGE
		"R": return EquipmentDefs.Rarity.RED
	return EquipmentDefs.Rarity.WHITE
const CURATED_TABLE := [
  ["G000", "被腐蚀的长剑", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 56.0, false]], [[[4, 1, Stat.HP, 0.01, 0], [4, 1, Stat.ATK, 0.01, 0], [4, 1, Stat.DEF, 0.01, 0], [4, 1, Stat.SPD, 0.01, 0], [4, 1, Stat.ASPD, 0.01, 0], [4, 1, Stat.AP, 0.01, 0], [4, 1, Stat.CRT, 0.01, 0], [4, 1, Stat.CRD, 0.01, 0]]], [[[Stat.HP, 0.0050, true], [Stat.ATK, 0.0050, true], [Stat.DEF, 0.0050, true], [Stat.SPD, 0.0050, true], [Stat.ASPD, 0.0050, true], [Stat.AP, 0.0050, true], [Stat.CRT, 0.0050, true], [Stat.CRD, 0.0050, true]]], [[[4, 1, Stat.HP, 0.1000, 0, 0, {"seconds": 5.0000}], [4, 1, Stat.ATK, 0.1000, 0, 0, {"seconds": 5.0000}], [4, 1, Stat.DEF, 0.1000, 0, 0, {"seconds": 5.0000}], [4, 1, Stat.SPD, 0.1000, 0, 0, {"seconds": 5.0000}], [4, 1, Stat.ASPD, 0.1000, 0, 0, {"seconds": 5.0000}], [4, 1, Stat.AP, 0.1000, 0, 0, {"seconds": 5.0000}], [4, 1, Stat.CRT, 0.1000, 0, 0, {"seconds": 5.0000}], [4, 1, Stat.CRD, 0.1000, 0, 0, {"seconds": 5.0000}]]], "每击杀一个敌人，该武器所有数值增加1%（本局内永久叠加，换武器重置）", "角色所有基础属性增加0.5%", "获得被动——每击杀一个敌人，全属性增加10%，持续5秒，可无限叠加"],
  ["G001", "饮血重剑", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 89.6, false]], [[100, 0.1000, true]], [[100, 0.0050, true]], [[4, 3, Stat.HP, 0.0500, 0]], "攻击附带10%吸血效果", "获得0.5%吸血", "每击杀一个敌人回复5%最大生命值"],
  ["G002", "烈焰法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "fire", 0.5000]], [[121, 0.0100, true]], [[3, "fire", 0.1000]], "攻击附带50%火焰伤害", "获得1%火焰伤害提升", "攻击附带10%火焰伤害"],
  ["G003", "寒霜法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "frost", 0.5000]], [[122, 0.0100, true]], [[3, "frost", 0.1000]], "攻击附带50%冰霜伤害", "获得1%冰霜伤害提升", "攻击附带10%冰霜伤害"],
  ["G004", "雷霆法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "static", 0.5000]], [[123, 0.0100, true]], [[3, "static", 0.1000]], "攻击附带50%雷电伤害", "获得1%雷电伤害提升", "攻击附带10%雷电伤害"],
  ["G005", "剧毒法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "poison", 0.5000]], [[126, 0.0100, true]], [[3, "poison", 0.1000]], "攻击附带50%毒素伤害", "获得1%毒素伤害提升", "攻击附带10%毒素伤害"],
  ["G006", "大地法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "earth", 0.5000]], [[124, 0.0100, true]], [[3, "earth", 0.1000]], "攻击附带50%大地伤害", "获得1%大地伤害提升", "攻击附带10%大地伤害"],
  ["G007", "疾风法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "wind", 0.5000]], [[125, 0.0100, true]], [[3, "wind", 0.1000]], "攻击附带50%疾风伤害", "获得1%疾风伤害提升", "攻击附带10%疾风伤害"],
  ["G008", "嗜血匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 42.0, false]], [[100, 0.0500, true]], [[100, 0.0050, true]], [[4, 6, Stat.HP, 0.1000, 0]], "每次攻击回复造成伤害的5%生命", "获得0.5%生命偷取", "暴击时回复10%最大生命值"],
  ["G009", "荆棘长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 56.0, false]], [[2, "slow", 1.0, 2, {"slow": 0.1000}]], [[Stat.SPD, 0.0050, true]], [[2, "entangle", 0.2000, 1.0]], "攻击附带10%减速效果，持续2秒", "获得0.5%移动速度", "攻击有20%概率触发荆棘缠绕，使目标无法移动1秒"],
  ["G010", "腐蚀头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[4, 2, Stat.DEF,  0.0100,  5,  0]], [[Stat.DEF, 0.0050, true]], [[4, 2, 104, 0.5000, 0]], "每受到一次伤害，防御力增加1%，持续10秒，可叠加5层", "角色防御力增加0.5%", "受到伤害时，有10%概率反弹50%伤害给攻击者"],
  ["G011", "吸血脉甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[4, 3, Stat.HP, 0.0200, 0]], [[Stat.HP, 0.0050, true]], [[4, 11, Stat.ATK, 0.2000, 0, 0.3000]], "每击杀一个敌人回复2%最大生命值", "角色最大生命值增加0.5%", "生命值低于30%时，吸血效果提升20%"],
  ["G012", "荆棘肩甲", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[104, 0.1000, true]], [[Stat.DEF, 0.0050, true]], [[4, 2, 104, 0.5000, 0]], "反弹10%近战伤害", "角色护甲增加0.5%", "受到近战攻击时，对攻击者造成50%攻击力的伤害"],
  ["G013", "迅捷护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[Stat.ASPD, 0.0500, true]], [[Stat.ASPD, 0.0050, true]], [[2, "attack_bonus", 1.0, 0.0, {"quick_chance": 0.1000}]], "攻击速度增加5%", "角色攻击速度增加0.5%", "每次攻击命中，有10%概率使下次攻击速度翻倍"],
  ["G014", "坚韧腿甲", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[112, 0.1000, true]], [[139, 0.0050, true]], [[4, 11, 112, 0.50, 0, 0.5000]], "受到的控制效果持续时间减少10%", "角色异常状态抗性增加0.5%", "生命值低于50%时，免疫控制效果"],
  ["G015", "踏风战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[Stat.SPD, 0.0500, true]], [[Stat.SPD, 0.0050, true]], [[4, 1, Stat.SPD, 0.2000, 0, 0, {"seconds": 3.0000}]], "移动速度增加5%", "角色移动速度增加0.5%", "击杀敌人后，移动速度增加20%，持续3秒"],
  ["G016", "嗜血项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[100, 0.0300, true]], [[100, 0.0050, true]], [[4, 6, Stat.HP, 0.0500, 0]], "生命偷取增加3%", "角色生命偷取增加0.5%", "每次暴击回复5%最大生命值"],
  ["G017", "元素指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[117, 0.0500, true]], [[117, 0.0050, true]], [[4, 10, 117, 0.5000, 0]], "所有元素伤害增加5%", "角色元素伤害增加0.5%", "攻击时，有10%概率触发随机元素爆炸，造成50%攻击力的对应元素伤害"],
  ["G018", "猎人徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[[105, 0.1000, true], [154, 0.5000, true]]], [[Stat.CRT, 0.0050, true]], [[4, 1, Stat.CRT,  0.1000,  3,  0]], "对生命值低于50%的敌人造成额外10%伤害", "角色暴击率增加0.5%", "击杀敌人后，暴击率增加10%，持续5秒，可叠加3层"],
  ["G019", "守护护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[2, "gen_sustain_2", 0.1000, 0.0, {"dmg_taken_down": 0.5000}]], [[117, 0.0050, true]], [[2, "grant_shield", 1.0, 0.0, {"pct": 0.3000, "cap": 0.60}]], "受到伤害时，有10%概率减少50%伤害", "角色伤害减免增加0.5%", "生命值低于20%时，获得一个吸收30%最大生命值的护盾，持续10秒（冷却60秒）"],
  ["G020", "淘金者之镐", "axe", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 56.0, false]], [[2, "bonus_gold", 0.0500, 0.0]], [[107, 0.0050, true]], [[4, 1, 107,  0.0100,  5,  0]], "击杀敌人有5%概率额外掉落1枚金币", "金币获取量增加0.5%", "每击杀一个敌人，金币掉落增加1%，持续10秒，可叠加5层"],
  ["G021", "寻宝者背包", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[114, 0.0300, true]], [[114, 0.0030, true]], [[4, 32, 114, 0.1000, 0]], "宝箱开出装备的概率增加3%", "装备掉落率增加0.3%", "开启宝箱时，有10%概率额外获得1件白装"],
  ["G022", "破碎的钥匙链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[109, 0.0200, true]], [[109, 0.0020, true]], [[109, 0.0500, true]], "钥匙碎片掉落概率增加2%", "钥匙碎片掉落概率增加0.2%", "每层Boss额外掉落1片钥匙碎片的概率增加5%（可叠加）"],
  ["G023", "记忆碎片护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[4, 1, 119, 0.0100, 0]], [[119, 0.0050, true]], [[119, 0.0500, true]], "击杀精英敌人获得1点记忆残渣（每层限1次）", "记忆残渣获取量增加0.5%", "结算时额外获得5%记忆残渣"],
  ["G024", "怒气护腕", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[4, 2, 142, 2.0000, 0]], [[143, 0.0050, true]], [[4, 1, 142, 5.0000, 0]], "受到伤害时获得2点怒气（战士）", "怒气获取量增加0.5%", "击杀敌人时获得5点怒气"],
  ["G025", "魔力护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[145, 1.0000, true]], [[143, 0.0050, true]], [[4, 1, 142, 2.0000, 0]], "每秒回复1点魔力（法师）", "魔力回复速度增加0.5%", "击杀敌人回复2%最大魔力"],
  ["G026", "专注指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[4, 6, 142, 2.0000, 0]], [[143, 0.0050, true]], [[4, 1, 142, 3.0000, 0]], "暴击时获得2点专注（猎人）", "专注获取量增加0.5%", "击杀敌人获得3点专注"],
  ["G027", "裁决徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[4, 3, 142, 1.0000, 0]], [[143, 0.0050, true]], [[4, 1, 142, 5.0000, 0]], "攻击命中时获得1点裁决（判官）", "裁决获取量增加0.5%", "击杀敌人获得5点裁决"],
  ["G028", "气劲腰带", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[4, 7, 142, 1.0000, 0]], [[143, 0.0050, true]], [[4, 1, 142, 3.0000, 0]], "连击时获得1点气劲（武僧）", "气劲获取量增加0.5%", "击杀敌人获得3点气劲"],
  ["G029", "冷却沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[Stat.CDR, 0.0100, true]], [[Stat.CDR, 0.0020, true]], [[4, 1, Stat.CDR, 0.20, 0]], "技能冷却缩减1%", "冷却缩减增加0.2%", "击杀敌人后，下次技能冷却减少1秒"],
  ["G030", "迅捷之翼", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[Stat.CDR, 0.0500, true]], [[Stat.SPD, 0.0030, true]], [[4, 19, Stat.SPD, 0.0500, 0, 0, {"seconds": 2.0000}]], "冲刺冷却减少5%", "移动速度增加0.3%", "冲刺后获得5%移速，持续2秒"],
  ["G031", "冰霜护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[2, "freeze", 0.0500, 1.0]], [[122, 0.0050, true]], [[4, 28, 117, 0.0500, 0]], "攻击有5%概率冰冻敌人1秒", "冰霜伤害增加0.5%", "冰冻敌人时，对其造成额外5%冰霜伤害"],
  ["G032", "烈焰之心", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[106, 0.0300, true]], [[106, 0.0050, true]], [[2, "burn", 0.1000, 3.0]], "受到火焰伤害减少3%", "火焰抗性增加0.5%", "受到火焰伤害时，有10%概率对周围造成火焰爆炸"],
  ["G033", "荆棘之甲", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[104, 0.0300, true]], [[Stat.DEF, 0.0050, true]], [[2, "bleed", 0.1000, 3.0]], "反弹3%近战伤害", "护甲增加0.5%", "受到近战攻击时，有10%概率使攻击者流血3秒"],
  ["G034", "元素抗性披风", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[106, 0.0300, true]], [[106, 0.0050, true]], [[4, 2, 106, 0.1000, 0]], "所有元素抗性增加3%", "元素抗性增加0.5%", "受到元素伤害时，有10%概率获得对应元素护盾"],
  ["G035", "生命之泉护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[100, 0.0050, true]], [[100, 0.0050, true]], [[4, 1, Stat.HP, 0.0100, 0]], "每秒回复0.5%最大生命", "生命回复速度增加0.5%", "击杀敌人回复1%最大生命"],
  ["G036", "陷阱探测器", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [], [[137, 0.0050, true]], [[4, 16, 111, 0.2000, 0]], "显示附近陷阱（小地图）", "陷阱伤害减少0.5%", "触发陷阱时，有20%概率免疫伤害"],
  ["G037", "贪婪之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[108, 0.0200, true]], [[108, 0.0050, true]], [[4, 31, 107, 0.0500, 0]], "出售装备价格增加2%", "出售价格增加0.5%", "出售装备时，有5%概率获得双倍金币"],
  ["G038", "召唤师之戒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[116, 0.0300, true]], [[116, 0.0050, true]], [[4, 17, 117, 0.0200, 0]], "召唤物伤害增加3%", "召唤物伤害增加0.5%", "召唤物存在时，自身伤害增加2%"],
  ["G039", "时光沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[102, 0.0300, true]], [[102, 0.0050, true]], [[4, 18, 102, 0.10, 0]], "增益效果持续时间增加3%", "增益持续时间增加0.5%", "使用技能时，有10%概率使增益效果延长1秒"],
  ["G040", "瘟疫之触", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 42.0, false]], [[2, "poison_rot", 0.0500, 3, {"dot_atk": 0.0300, "vuln": 0.0100}]], [[126, 0.0030, true]], [[2, "burn", 0.30, 3.0]], "攻击有5%概率使目标中毒，每秒造成3%攻击力伤害，持续3秒", "毒素伤害增加0.3%", "中毒目标死亡时，毒素扩散至周围2米内敌人"],
  ["G041", "冻结之息", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[2, "slow", 0.0500, 2, {"slow": 0.1000}]], [[122, 0.0030, true]], [[2, "freeze", 1.0, 1.0]], "攻击有5%概率使目标减速10%，持续2秒", "冰霜伤害增加0.3%", "减速目标被击杀时，对周围造成冰冻1秒"],
  ["G042", "灼烧烙印", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 56.0, false]], [[2, "burn", 0.0500, 3, {"dot_atk": 0.0300}]], [[121, 0.0030, true]], [[4, 10, 105, 0.0500, 0]], "攻击有5%概率使目标燃烧，每秒造成3%攻击力伤害，持续3秒", "火焰伤害增加0.3%", "燃烧目标受到攻击时，额外承受5%伤害"],
  ["G043", "虚弱诅咒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[2, "fatigue", 0.0500, 3]], [[102, 0.0030, true]], [[2, "burn", 0.30, 3.0]], "攻击有5%概率使目标攻击力降低5%，持续3秒", "减益效果持续时间增加0.3%", "被减益的敌人死亡时，减益效果转移至周围1名敌人"],
  ["G044", "护盾发生器", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[106, 0.0500, true]], [[140, 0.0050, true]], [[4, 14, Stat.ATK, 0.5000, 0]], "进入新房间时获得5%最大生命值的护盾", "护盾获取量增加0.5%", "护盾被击破时，对周围造成50%攻击力的伤害"],
  ["G045", "格挡者之盾", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[110, 0.0300, true]], [[110, 0.0030, true]], [[4, 9, 117, 0.1000, 0]], "格挡时有3%概率完全免疫该次伤害", "格挡率增加0.3%", "成功格挡后，下次攻击伤害增加10%"],
  ["G046", "闪避之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[147, 0.0500, true]], [[111, 0.0030, true]], [[4, 4, Stat.SPD, 0.0500, 0, 0, {"seconds": 2.0000}]], "闪避时有5%概率立即刷新冲刺冷却", "闪避率增加0.3%", "成功闪避后获得5%移速，持续2秒"],
  ["G047", "荆棘护盾", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[4, 15, 104, 0.0500, 0]], [[140, 0.0050, true]], [[4, 14, Stat.ATK, 1.0000, 0]], "护盾存在时，反弹5%近战伤害", "护盾强度增加0.5%", "护盾被击破时，对攻击者造成100%攻击力伤害"],
  ["G048", "连击指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[4, 7, Stat.ATK,  0.0100,  5,  0]], [[4, 7, Stat.ATK, 0.0030, 0]], [[4, 7, Stat.ATK, 0.50, 0]], "连续攻击同一目标时，每次攻击伤害增加1%，最多5层", "连击伤害增加0.3%", "连击满层时，下次攻击必定暴击"],
  ["G049", "处决者之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 56.0, false]], [[[105, 0.1000, true], [154, 0.1500, true]]], [[105, 0.0020, true]], [[4, 1, Stat.HP, 0.0500, 0]], "对生命值低于15%的敌人造成额外10%伤害", "处决阈值增加0.2%", "击杀生命值低于15%的敌人时，回复5%最大生命值"],
  ["G050", "背刺匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 42.0, false]], [[Stat.CRD, 0.1000, true]], [[105, 0.0050, true]], [[4, 1, 111, 0.2000, 0, 0, {"seconds": 3.0000}]], "从背后攻击造成额外10%伤害", "背刺伤害增加0.5%", "背刺击杀敌人时，获得3秒隐身"],
  ["G051", "弱点探测器", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[2, "mark", 0.0500, 3.0]], [[105, 0.0020, true]], [[2, "burn", 0.30, 3.0]], "攻击有5%概率标记目标弱点，使其受到伤害增加5%，持续3秒", "标记触发概率增加0.2%", "被标记目标死亡时，标记转移至最近敌人"],
  ["G052", "分裂箭袋", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 56.0, false]], [[2, "attack_bonus", 1.0, 0.0, {"extra_hits": {"chance": 0.0500, "hits": 1, "mult": 0.5000}}]], [[138, 0.0030, true]], [[2, "attack_bonus", 1.0, 0.0, {"proj_bounce_chance": 0.1000}]], "远程攻击有5%概率额外发射1枚投射物（50%伤害）", "投射物伤害增加0.3%", "投射物命中时有10%概率弹射至最近敌人"],
  ["G053", "穿透弹头", "crossbow", ["远程", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 56.0, false]], [[2, "attack_bonus", 1.0, 0.0, {"proj_pierce_chance": 0.0500, "proj_pierce_count": 1}]], [[2, "attack_bonus", 1.0, 0.0, {"proj_pierce_chance": 0.0020, "proj_pierce_count": 1}]], [[138, 0.1000, true]], "投射物有5%概率穿透1个额外目标", "投射物穿透概率增加0.2%", "穿透后的投射物伤害增加10%"],
  ["G054", "爆炸符文", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[117, 0.3000, true]], [[136, 0.0030, true]], [[8, {"multi_hit_at": 3, "multi_hit_bonus": 0.5000}]], "技能命中时有5%概率触发小范围爆炸（30%攻击力）", "范围伤害增加0.3%", "爆炸命中3个以上敌人时，伤害提升至50%"],
  ["G055", "远程精准镜", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[4, 29, 117, 0.0300, 0]], [[135, 0.0030, true]], [[4, 1, Stat.CRT, 0.50, 0]], "距离目标超过5米时，伤害增加3%", "远程伤害增加0.3%", "击杀远距离敌人时，下次攻击必定暴击"],
  ["G056", "资源上限护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[144, 0.0300, true]], [[119, 0.0030, true]], [[4, 25, 117, 0.1000, 0]], "最大怒气/魔力/专注/裁决/气劲增加3%", "资源上限增加0.3%", "资源满时，下次技能伤害增加10%"],
  ["G057", "猎人印记", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[117, 0.0300, true]], [[117, 0.0030, true]], [[2, "spread_mark", 1.0, 0.0, {"count": 2}]], "攻击有5%概率施加猎人印记，被印记目标受到所有伤害增加3%，持续5秒", "印记增伤效果增加0.3%", "印记目标死亡时，印记扩散至周围2名敌人"],
  ["G058", "元素穿透指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[103, 0.0300, true]], [[103, 0.0030, true]], [[103, 0.30, true]], "攻击无视目标3%元素抗性", "元素穿透增加0.3%", "对带有元素状态的敌人，穿透效果翻倍"],
  ["G059", "真实伤害护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[4, 3, 118, 0.0500, 0]], [[118, 0.0030, true]], [[4, 1, 100, 0.0300, 0]], "攻击有3%概率造成额外5%攻击力的真实伤害", "真实伤害增加0.3%", "真实伤害击杀敌人时，回复3%最大生命值"],
  ["B000", "暗影短刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [[2, "attack_bonus", 1.0, 0.0, {"shadow_chance": 0.0800, "shadow_mult": 1.5000, "shadow_cd": 2}]], [[105, 0.0500, true]], [[4, 1, 113, 1.0, 0]], "攻击有8%概率触发“影袭”——瞬移至目标背后并造成150%攻击力伤害，冷却2秒", "背刺伤害增加5%", "影袭击杀敌人时，立即刷新影袭冷却"],
  ["B001", "穿刺长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[103, 0.4000, true]], [[103, 0.1000, true]], [[103, 0.30, true]], "攻击附带穿透效果，并无视敌人40%护甲", "攻击无视敌人10%护甲", "攻击附带穿透效果"],
  ["B002", "裂地战斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[3, "earth", 0.50]], [[3, "earth", 0.10]], [[117, 0.3000, true]], "被动——每次攻击附带50%岩石伤害，并造成范围震击（1.5米）", "攻击附带10%岩石伤害", "攻击造成范围震击"],
  ["B003", "元素调和法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_元素调和法杖", "元素调和"]], [[117, 0.0200, true]], [[106, 0.1000, true]], "主动技能“元素调和”——切换当前元素属性（火/冰/雷/毒/土/风），并对周围3米造成80%法强对应元素伤害，冷却8秒", "对应元素伤害增加2%", "切换元素时获得对应元素护盾（吸收10%最大生命值）"],
  ["B004", "巨兽猎手", "crossbow", ["远程", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[105, 0.1500, true], [2, "entangle", 0.0600, 1.5]], [[105, 0.0300, true]], [[8, {"armor_reduce": 0.2000, "armor_reduce_seconds": 5}]], "对精英/Boss造成额外15%伤害；攻击有6%概率发射束缚箭，使目标无法移动1.5秒", "对精英/Boss伤害增加3%", "束缚箭命中后，目标防御降低20%，持续5秒"],
  ["B005", "圣光壁垒", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [[7, "eq_圣光壁垒", "圣光格挡"]], [[110, 0.0300, true]], [[100, 0.1000, true]], "主动技能“圣光格挡”——格挡时释放圣光，对周围2米造成100%攻击力伤害并治疗自身5%最大生命值，冷却5秒", "格挡率增加3%", "圣光治疗量提升至10%最大生命值"],
  ["B006", "疾风长矛", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[117, 0.2000, true], [3, "wind", 0.3000]], [[125, 0.0200, true]], [[117, 0.5000, true]], "突刺距离增加20%；冲刺后下一次攻击附带30%额外风元素伤害", "风元素伤害增加2%", "冲刺路径留下风痕，对经过的敌人造成50%攻击力伤害"],
  ["B007", "噬魂战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[4, 1, Stat.ATK,  0.0300,  5,  0], [4, 5, Stat.ATK, 2.0000, 0]], [[4, 1, Stat.HP, 0.0050, 0]], [[4, 5, Stat.ATK, 3.0000, 0]], "击杀敌人获得1层“噬魂”（最多5层），每层提升3%攻击力；满层时下次攻击释放范围收割（200%攻击力）", "击杀敌人回复0.5%最大生命值", "噬魂满层时，收割伤害提升至300%并附带吸血"],
  ["B008", "暗影斗篷", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[111, 0.1000, true], [7, "eq_暗影斗篷", "暗影刺杀"]], [[111, 0.1000, true]], [[4, 13, 111, 0.1000, 0]], "主动技能“暗影刺杀”——进入隐身状态，持续5秒，隐身期间免疫所有伤害，下一次普攻伤害翻倍且必定暴击，并附带60%法术+40%物理加成伤害；首次命中后隐身解除，冷却20秒", "翻滚改为瞬步，对路径上敌人造成10%伤害", "每次进入未探索房间时，自动触发一次暗影刺杀效果"],
  ["B009", "荆棘头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[4, 2, 104, 0.3000, 0]], [[Stat.DEF, 0.0200, true]], [[2, "bleed", 0.2000, 3.0, {"trigger": 40}]], "受到近战攻击时，反弹30%伤害给攻击者", "护甲增加2%", "反弹伤害有20%概率使攻击者流血3秒"],
  ["B010", "守护肩甲", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[4, 11, 146, 0.2000, 0, 0.5000]], [[117, 0.0100, true]], [[4, 11, 106, 0.1500, 0, 0.3000]], "生命值低于50%时，获得20%伤害减免", "伤害减免增加1%", "生命值低于30%时，额外获得一个吸收15%最大生命值的护盾（冷却60秒）"],
  ["B011", "迅捷护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[Stat.ASPD, 0.0800, true], [4, 3, Stat.ASPD,  0.0200,  5,  0]], [[Stat.ASPD, 0.0100, true]], [[4, 5, Stat.ATK, 0.50, 0]], "攻击速度增加8%；每次命中叠加1层“迅捷”（最多5层），每层+2%攻速", "攻击速度增加1%", "迅捷满层时，下次攻击必定触发一次额外攻击（50%伤害）"],
  ["B012", "坚韧腿甲", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[112, 0.3000, true], [106, 0.1000, true]], [[139, 0.0200, true]], [[2, "control_immune", 1.0, 3.0]], "受到的控制效果持续时间减少30%；被控制时获得10%减伤", "异常状态抗性增加2%", "成功抵抗控制效果后，获得3秒霸体"],
  ["B013", "踏风战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_踏风战靴", "疾风步"]], [[Stat.SPD, 0.0200, true]], [[8, {"fire_path_seconds": 3.0, "fire_path_mult": 0.3000}]], "主动技能“疾风步”——3秒内移速+40%、闪避+20%，冷却12秒", "移动速度增加2%", "疾风步期间留下火焰路径，对经过敌人造成30%攻击力伤害"],
  ["B014", "巨型方盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [[7, "eq_巨型方盾", "盾击"]], [[111, 0.0500, true]], [[106, 0.3000, true]], "主动技能“盾击”——向前冲刺，击飞沿途所有敌人，期间免疫一切伤害，冷却15秒", "受到伤害时有5%概率免疫此次伤害", "角色减免30%来自正前方的伤害"],
  ["B015", "元素指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[117, 0.0800, true], [117, 1.0000, true]], [[117, 0.0100, true]], [[2, "burn", 0.15, 3.0]], "所有元素伤害增加8%；攻击有5%概率触发随机元素爆炸（100%攻击力对应元素伤害）", "元素伤害增加1%", "元素爆炸有20%概率附加对应元素状态（灼烧/冰冻/麻痹/中毒/眩晕/牵引）"],
  ["B016", "猎手徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[[105, 0.2000, true], [154, 0.4000, true]], [4, 1, Stat.CRT, 0.1500, 0, 0, {"seconds": 3.0000}]], [[Stat.CRT, 0.0100, true]], [[4, 1, 113, 1.0, 0]], "对生命值低于40%的敌人造成额外20%伤害；击杀后获得3秒暴击率+15%", "暴击率增加1%", "击杀精英/Boss时，重置所有技能冷却"],
  ["B017", "守护护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[4, 34, Stat.HP, 0.2000, 0]], [[Stat.HP, 0.0200, true]], [], "受到致命伤害时，免疫该次伤害并恢复20%最大生命值（每局1次）", "最大生命值增加2%", "触发免死后，获得5秒无敌"],
  ["B018", "贪婪之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[107, 0.1500, true], [108, 0.1000, true]], [[107, 0.0200, true]], [[2, "kill_gold", 1.0, 0.0, {"kill_gold": {"chance": 0.0500, "elite_only": false, "amount_min": 10, "amount_max": 50}}]], "金币获取量增加15%；出售装备价格增加10%", "金币获取量增加2%", "击杀敌人有5%概率掉落额外金币（10~50）"],
  ["B019", "时光沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[Stat.CDR, 0.0500, true], [102, 0.1000, true]], [[Stat.CDR, 0.0100, true]], [[4, 18, 113, 0.5000, 0]], "技能冷却缩减5%；增益效果持续时间增加10%", "冷却缩减增加1%", "使用技能时，有10%概率使该技能冷却立即减少50%"],
  ["B020", "唤灵短杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_唤灵短杖", "唤灵"]], [[116, 0.0200, true]], [[2, "summon_death_boom", 1.0, 0.0, {"mult": 1.0000, "by": "ap"}]], "主动技能“唤灵”——召唤1只持续15秒的灵体（继承30%法强），冷却20秒", "召唤物伤害增加2%", "灵体死亡时爆炸，对周围造成100%法强伤害"],
  ["B021", "捕兽长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[2, "entangle", 0.0800, 1.5]], [[137, 0.0200, true]], [[4, 16, Stat.ATK, 0.5000, 0]], "攻击有8%概率布置陷阱，触发后束缚敌人1.5秒", "陷阱伤害增加2%", "陷阱触发时对周围2米造成50%攻击力伤害"],
  ["B022", "反伤巨剑", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[104, 0.3000, true], [7, "eq_反伤巨剑", "反击风暴"]], [[104, 0.0200, true]], [[4, 21, Stat.DEF, 0.0, 0]], "格挡时反弹30%伤害；主动技能“反击风暴”——3秒内反弹100%伤害，冷却15秒", "反伤效果增加2%", "反击风暴期间免疫控制"],
  ["B023", "空间匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [[4, 10, 117, 0.5000, 0]], [[117, 0.0200, true]], [[117, 0.3000, true]], "攻击有6%概率瞬移至目标背后，下次攻击伤害+50%", "位移后伤害增加2%", "瞬移后留下残影，对路径敌人造成30%伤害"],
  ["B024", "标记重弩", "crossbow", ["远程", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[2, "mark", 0.0800, 5.0]], [[117, 0.0100, true]], [[2, "burn", 0.30, 3.0]], "攻击有8%概率标记目标，被标记目标受到所有伤害+10%，持续5秒", "标记增伤效果增加1%", "标记目标死亡时，标记扩散至最近2名敌人"],
  ["B025", "资源长矛", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[4, 3, 142, 2.0000, 0]], [[143, 0.0200, true]], [[2, "res_shockwave", 1.0, 0.0, {"mult": 1.0000}]], "攻击命中回复2点职业资源（怒气/魔力/专注/裁决/气劲）", "资源获取量增加2%", "资源满时，下次攻击释放资源冲击波（100%攻击力）"],
  ["B026", "元素战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[3, "fire", 0.3000]], [[117, 0.0200, true]], [[2, "elem_seq_same_target", 1.0, 0.0, {"count": 3, "mult": 1.5000}]], "攻击附带随机元素伤害（30%攻击力），每次攻击切换元素", "元素伤害增加2%", "连续攻击同一目标3次后，触发元素爆炸（150%攻击力）"],
  ["B027", "守护者之盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [[4, 9, 106,  0.0200,  5,  0]], [[110, 0.0200, true]], [[4, 5, 111, 0.5000, 0, 0, {"seconds": 3.0000}]], "格挡成功时，为自身叠加1层“守护”（最多5层），每层+2%减伤", "格挡率增加2%", "守护满层时，消耗全部层数获得3秒无敌"],
  ["B028", "毒牙短刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [[2, "poison_rot", 0.0800, 3, {"dot_atk": 0.0500, "vuln": 0.0100}]], [[126, 0.0200, true]], [[2, "burn", 0.30, 3.0]], "攻击有8%概率使目标中毒，每秒造成5%攻击力伤害，持续3秒", "毒素伤害增加2%", "中毒目标死亡时，毒素扩散至周围2米"],
  ["B029", "雷霆战锤", "axe", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[117, 0.8000, true]], [[123, 0.0200, true]], [[2, "paralyze", 0.2000, 1.0]], "攻击有6%概率触发雷击，对目标及周围1.5米造成80%攻击力雷电伤害", "雷电伤害增加2%", "雷击有20%概率麻痹目标1秒"],
  ["B030", "疾风双刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [[Stat.ASPD, 0.1000, true], [4, 7, Stat.ATK,  0.0200,  5,  0]], [[Stat.ASPD, 0.0100, true]], [[4, 5, Stat.ATK, 0.50, 0]], "攻击速度+10%；连续攻击同一目标时，每次+2%攻速（最多5层）", "攻击速度增加1%", "攻速满层时，下次攻击额外攻击一次（50%伤害）"],
  ["B031", "灵魂收割者", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[4, 1, Stat.ATK,  0.0100,  10,  0], [4, 5, Stat.ATK, 2.0000, 0]], [[4, 1, Stat.HP, 0.0050, 0]], [[4, 3, Stat.HP, 0.1000, 0]], "击杀敌人获得1层“灵魂”（最多10层），每层+1%攻击力；满层时下次攻击释放灵魂冲击（200%攻击力）", "击杀回复0.5%最大生命", "灵魂冲击命中3个以上敌人时，回复10%最大生命"],
  ["B032", "冰霜长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[2, "freeze", 0.0800, 1.0], [117, 0.2000, true]], [[122, 0.0200, true]], [[4, 35, 117, 1.0000, 0]], "攻击有8%概率冰冻目标1秒；对冰冻目标伤害+20%", "冰霜伤害增加2%", "冰冻目标死亡时，对周围造成冰冻爆炸（100%攻击力）"],
  ["B033", "暗影法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_暗影法环", "暗影领域"]], [[127, 0.0200, true]], [[2, "zone_slow", 1.0, 0.0, {"slow_pct": 0.3000}]], "主动技能“暗影领域”——在目标区域生成暗影领域（3秒），每秒造成40%法强伤害，冷却12秒", "暗影伤害增加2%", "暗影领域内敌人移速-30%"],
  ["B034", "荆棘链刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[2, "entangle", 0.0800, 1.0], [2, "judgement", 1.0, 0.0, {"vuln": 0.1000}]], [[102, 0.20, true]], [[4, 35, 117, 0.5000, 0]], "攻击有8%概率缠绕目标1秒；被缠绕目标受到伤害+10%", "缠绕持续时间增加0.2秒", "缠绕结束时，对目标造成前3次攻击总和50%的伤害"],
  ["B035", "圣光权杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_圣光权杖", "圣光术"]], [[100, 0.0200, true]], [[115, 0.2000, true]], "主动技能“圣光术”——治疗自身10%最大生命，并对周围2米造成50%法强伤害，冷却15秒", "治疗效果增加2%", "圣光术对友方召唤物同样生效"],
  ["B036", "陷阱头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[115, 0.2000, true], [4, 16, 106, 0.1000, 0, 0, {"seconds": 3.0000}]], [[137, 0.0200, true]], [[111, 0.2000, true]], "显示周围5米内的陷阱；触发陷阱时获得10%减伤，持续3秒", "陷阱伤害减少2%", "触发陷阱时有20%概率免疫伤害"],
  ["B037", "召唤胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[4, 17, 146, 0.0500, 0], [4, 1, Stat.HP, 0.0500, 0]], [[116, 0.0200, true]], [[2, "summon_death_boom", 1.0, 0.0, {"mult": 0.5000, "by": "ap"}]], "召唤物存在时，自身获得5%减伤；召唤物死亡时回复5%最大生命", "召唤物生命增加2%", "召唤物死亡时爆炸，对周围造成50%法强伤害"],
  ["B038", "反伤肩甲", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[104, 0.2000, true], [7, "eq_反伤肩甲", "荆棘爆发"]], [[104, 0.0200, true]], [[4, 24, Stat.DEF, 0.3000, 0]], "受到近战攻击时反弹20%伤害；主动技能“荆棘爆发”——3秒内反弹100%伤害，冷却18秒", "反伤效果增加2%", "荆棘爆发期间受到伤害减少30%"],
  ["B039", "护盾护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[106, 0.0500, true], [4, 15, Stat.ATK, 0.0500, 0]], [[140, 0.0200, true]], [[4, 14, Stat.ATK, 0.8000, 0]], "进入新房间时获得5%最大生命护盾；护盾存在时攻击+5%", "护盾获取量增加2%", "护盾被击破时，对周围造成80%攻击力伤害"],
  ["B040", "资源腿甲", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[4, 1, 142, 3.0000, 0]], [[119, 0.0200, true]], [[4, 25, Stat.SPD, 0.1500, 0]], "击杀敌人回复3点职业资源", "资源上限增加2%", "资源满时，移速+15%"],
  ["B041", "位移战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[Stat.CDR, 0.1000, true], [4, 4, 111, 0.0500, 0, 0, {"seconds": 3.0000}]], [[Stat.SPD, 0.0200, true]], [[117, 0.3000, true]], "冲刺冷却减少10%；冲刺后获得5%闪避，持续3秒", "移动速度增加2%", "冲刺路径留下火焰，对敌人造成30%攻击力伤害"],
  ["B042", "标记头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[2, "mark", 0.0600, 5.0]], [[105, 0.0100, true]], [[2, "burn", 0.30, 3.0]], "攻击有6%概率标记目标，被标记目标受到伤害+8%，持续5秒", "标记增伤增加1%", "标记目标死亡时，标记转移至最近敌人"],
  ["B043", "元素抗性胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[106, 0.0500, true], [106, 0.0500, true]], [[106, 0.0100, true]], [[4, 14, Stat.AP, 0.0, 0]], "所有元素抗性+5%；受到元素伤害时获得对应元素护盾（吸收5%最大生命）", "元素抗性增加1%", "元素护盾被击破时，对周围造成元素爆炸"],
  ["B044", "经济肩甲", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[107, 0.1000, true], [2, "kill_gold", 1.0, 0.0, {"kill_gold": {"chance": 0.0500, "elite_only": false, "amount": 1}}]], [[107, 0.0200, true]], [[2, "kill_gold", 1.0, 0.0, {"kill_gold": {"chance": 1.0, "elite_only": true, "amount_min": 10, "amount_max": 50}}]], "金币获取量+10%；击杀敌人有5%概率额外掉落1金币", "金币获取量增加2%", "击杀精英/Boss额外掉落10~50金币"],
  ["B045", "钥匙护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[109, 0.0300, true]], [[109, 0.0100, true]], [[109, 0.1000, true]], "钥匙碎片掉落概率+3%", "钥匙碎片掉落概率增加1%", "每层Boss额外掉落1片钥匙碎片的概率+10%"],
  ["B046", "记忆腿甲", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[4, 1, 119, 0.0100, 0]], [[119, 0.0200, true]], [[119, 0.0500, true]], "击杀精英获得1点记忆残渣（每层限1次）", "记忆残渣获取量增加2%", "结算时额外获得5%记忆残渣"],
  ["B047", "召唤战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[116, 0.1000, true], [4, 17, Stat.SPD, 0.0500, 0]], [[116, 0.0200, true]], [[2, "slow", 1.0, 3, {"slow": 0.3000}]], "召唤物移速+10%；召唤物存在时自身移速+5%", "召唤物移速增加2%", "召唤物死亡时留下减速区域（3秒，-30%移速）"],
  ["B048", "护盾头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[4, 11, 106, 0.1000, 0, 0.5000]], [[140, 0.0200, true]], [[2, "control_immune", 1.0, 0.0]], "生命低于50%时，获得10%最大生命护盾（冷却60秒）", "护盾强度增加2%", "护盾存在时免疫控制"],
  ["B049", "反伤胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[104, 0.1000, true], [104, 0.20, true]], [[104, 0.0200, true]], [[2, "bleed", 0.1000, 3.0, {"trigger": 40}]], "受到伤害时反弹10%伤害；生命低于30%时反弹效果翻倍", "反伤效果增加2%", "反弹伤害有10%概率使攻击者流血3秒"],
  ["B050", "召唤戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[116, 0.1000, true], [120, 1, false]], [[116, 0.0200, true]], [[2, "attack_bonus", 1.0, 0.0, {"summon_extra_chance": 0.1000}]], "召唤物伤害+10%；召唤物上限+1", "召唤物伤害增加2%", "召唤物攻击有10%概率触发额外攻击"],
  ["B051", "陷阱护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[137, 0.1500, true]], [[137, 0.0200, true]], [[4, 16, Stat.ATK, 0.5000, 0]], "陷阱伤害+15%；陷阱触发范围+20%", "陷阱伤害增加2%", "陷阱触发时对周围造成50%攻击力伤害"],
  ["B052", "反伤徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[104, 0.1000, true], [104, 0.20, true]], [[104, 0.0200, true]], [[2, "stun", 0.1000, 1.0, {"trigger": 40}]], "反弹伤害+10%；格挡时反弹效果翻倍", "反伤效果增加2%", "反弹伤害有10%概率眩晕攻击者1秒"],
  ["B053", "资源项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[119, 0.1000, true], [119, 0.1000, true]], [[119, 0.0200, true]], [[4, 25, 117, 0.1500, 0]], "职业资源上限+10%；资源回复速度+10%", "资源上限增加2%", "资源满时，下次技能伤害+15%"],
  ["B054", "位移戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[4, 19, Stat.SPD, 0.1000, 0, 0, {"seconds": 3.0000}], [Stat.CDR, 0.0500, true]], [[Stat.SPD, 0.0200, true]], [[4, 3, Stat.ATK, 0.3000, 0]], "冲刺后获得10%移速，持续3秒；冲刺冷却-5%", "移动速度增加2%", "冲刺后下次攻击附带30%额外伤害"],
  ["B055", "标记护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[2, "mark", 0.0600, 5.0]], [[105, 0.0100, true]], [[4, 1, Stat.HP, 0.0500, 0]], "攻击有6%概率标记目标，被标记目标受到伤害+8%，持续5秒", "标记增伤增加1%", "标记目标死亡时，回复5%最大生命"],
  ["B056", "元素戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[117, 0.0800, true], [117, 0.8000, true]], [[117, 0.0200, true]], [[2, "burn", 0.15, 3.0]], "所有元素伤害+8%；攻击有5%概率触发随机元素爆炸（80%攻击力）", "元素伤害增加2%", "元素爆炸有20%概率附加对应元素状态"],
  ["B057", "经济项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[107, 0.1500, true], [108, 0.1000, true]], [[107, 0.0200, true]], [[107, 0.0500, true]], "金币获取+15%；出售价格+10%", "金币获取增加2%", "出售装备有5%概率获得双倍金币"],
  ["B058", "钥匙徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[109, 0.0300, true]], [[109, 0.0100, true]], [[109, 0.1000, true]], "钥匙碎片掉落+3%", "钥匙碎片掉落增加1%", "每层Boss额外掉落1片钥匙碎片的概率+10%"],
  ["B059", "记忆护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[4, 1, 119, 0.0100, 0]], [[119, 0.0200, true]], [[119, 0.0500, true]], "击杀精英获得1点记忆残渣（每层限1次）", "记忆残渣获取量增加2%", "结算时额外获得5%记忆残渣"],
  ["B060", "野蛮冲撞战斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[7, "eq_野蛮冲撞战斧", "野蛮冲撞"]], [[Stat.ATK, 0.0200, true]], [[117, 0.3000, true]], "主动技能“野蛮冲撞”——向前冲锋5米，撞飞路径上所有敌人并造成120%攻击力伤害，冷却10秒", "攻击力增加2%", "冲撞后下一次攻击伤害+30%"],
  ["B061", "影闪匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [[7, "eq_影闪匕首", "影闪"]], [[105, 0.0300, true]], [[Stat.CRT, 0.2000, true]], "主动技能“影闪”——瞬移至前方5米，对路径上敌人造成80%攻击力伤害，冷却8秒", "背刺伤害增加3%", "影闪后3秒内暴击率+20%"],
  ["B062", "火球法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_火球法杖", "火球术"]], [[121, 0.0200, true]], [[8, {"multi_hit_at": 3, "multi_hit_bonus": 2.0000}]], "主动技能“火球术”——发射火球，造成150%法强火焰伤害，并在目标点留下燃烧地面（每秒30%法强，持续3秒），冷却6秒", "火焰伤害增加2%", "火球命中3个以上敌人时伤害提升至200%"],
  ["B063", "冰霜陷阱长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_冰霜陷阱长弓", "冰霜陷阱"]], [[122, 0.0200, true]], [[117, 0.5000, true]], "主动技能“冰霜陷阱”——在目标地点布置陷阱，触发后冰冻敌人1.5秒并造成80%攻击力冰霜伤害，冷却12秒", "冰霜伤害增加2%", "陷阱触发后对周围2米造成50%攻击力伤害"],
  ["B064", "雷霆一击战锤", "axe", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_雷霆一击战锤", "雷霆一击"]], [[123, 0.0200, true]], [[102, 0.30, true]], "主动技能“雷霆一击”——砸击地面，对周围3米造成120%攻击力雷电伤害并麻痹1秒，冷却10秒", "雷电伤害增加2%", "麻痹时间延长至1.5秒"],
  ["B065", "治疗之光权杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_治疗之光权杖", "治疗之光"]], [[100, 0.0200, true]], [[2, "__cleanse_one__", 1.0, 0.0]], "主动技能“治疗之光”——治疗自身及周围友方15%最大生命值，冷却15秒", "治疗效果增加2%", "治疗同时清除一个负面状态"],
  ["B066", "召唤狼灵法书", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_召唤狼灵法书", "召唤狼灵"]], [[116, 0.0200, true]], [[2, "bleed", 0.1000, 3.0]], "主动技能“召唤狼灵”——召唤1只狼灵（继承40%法强，持续20秒），冷却25秒", "召唤物伤害增加2%", "狼灵攻击有10%概率造成流血"],
  ["B067", "盾牌冲锋长矛", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_盾牌冲锋长矛", "盾牌冲锋"]], [[110, 0.0200, true]], [[4, 21, Stat.DEF, 0.0, 0]], "主动技能“盾牌冲锋”——举盾冲锋，格挡正面伤害，撞击敌人造成100%攻击力伤害并击退，冷却12秒", "格挡率增加2%", "冲锋期间免疫控制"],
  ["B068", "毒雾短刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [[7, "eq_毒雾短刃", "毒雾弹"]], [[126, 0.0200, true]], [[2, "zone_slow", 1.0, 0.0, {"slow_pct": 0.3000}]], "主动技能“毒雾弹”——投掷毒雾，在3米区域造成每秒30%攻击力毒素伤害，持续4秒，冷却10秒", "毒素伤害增加2%", "毒雾内敌人移速-30%"],
  ["B069", "旋风双斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[7, "eq_旋风双斧", "旋风斩"]], [[Stat.ASPD, 0.0100, true]], [[4, 22, Stat.SPD, 0.2000, 0]], "主动技能“旋风斩”——旋转攻击周围敌人，持续2秒，每0.5秒造成60%攻击力伤害，冷却8秒", "攻击速度增加1%", "旋风斩期间移速+20%"],
  ["B070", "圣光新星法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_圣光新星法环", "圣光新星"]], [[Stat.AP, 0.0200, true]], [[105, 0.5000, true]], "主动技能“圣光新星”——以自身为中心爆发圣光，造成100%法强伤害并治疗友方5%最大生命，冷却12秒", "法术强度增加2%", "圣光新星对亡灵额外造成50%伤害"],
  ["B071", "暗影突袭链刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_暗影突袭链刃", "暗影突袭"]], [[127, 0.0200, true]], [[2, "judgement", 1.0, 0.0, {"vuln": 0.1500, "seconds": 3.0000}]], "主动技能“暗影突袭”——向前突进并拉扯第一个命中的敌人，造成120%攻击力伤害，冷却10秒", "暗影伤害增加2%", "拉扯后目标受到伤害+15%，持续3秒"],
  ["B072", "爆裂射击重弩", "crossbow", ["远程", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_爆裂射击重弩", "爆裂射击"]], [[136, 0.0200, true]], [[8, {"radius_mult": 1.2000}]], "主动技能“爆裂射击”——发射爆炸弩箭，对目标区域造成150%攻击力范围伤害，冷却8秒", "范围伤害增加2%", "爆炸范围扩大20%"],
  ["B073", "风之箭长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_风之箭长弓", "风之箭"]], [[125, 0.0200, true]], [[117, 0.1500, true]], "主动技能“风之箭”——射出穿透风箭，穿透所有敌人，造成120%攻击力风元素伤害，冷却6秒", "风元素伤害增加2%", "风之箭命中后对路径敌人造成牵引"],
  ["B074", "地刺法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_地刺法杖", "地刺术"]], [[124, 0.0200, true]], [[2, "stun", 1.0, 0.5]], "主动技能“地刺术”——在目标区域召唤地刺，造成120%法强土元素伤害并击飞，冷却10秒", "土元素伤害增加2%", "地刺造成眩晕0.5秒"],
  ["B075", "灵魂吸取战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[7, "eq_灵魂吸取战镰", "灵魂吸取"]], [[100, 0.0200, true]], [[4, 3, Stat.HP, 0.05, 0]], "主动技能“灵魂吸取”——对周围敌人造成80%攻击力伤害，每命中一个敌人回复5%最大生命，冷却12秒", "生命偷取增加2%", "命中3个以上敌人时回复量翻倍"],
  ["B076", "无畏冲锋胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_无畏冲锋胸甲", "无畏冲锋"]], [[Stat.HP, 0.0200, true]], [[4, 19, 146, 0.0500, 0, 0, {"seconds": 5.0000}]], "主动技能“无畏冲锋”——向前冲锋，撞飞敌人，期间免疫伤害，冷却15秒", "最大生命值增加2%", "冲锋后获得5%减伤，持续5秒"],
  ["B077", "闪现战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_闪现战靴", "闪现"]], [[Stat.SPD, 0.0200, true]], [[4, 3, Stat.ATK, 0.3000, 0]], "主动技能“闪现”——瞬移5米，冷却10秒", "移动速度增加2%", "闪现后下次攻击+30%伤害"],
  ["B078", "生命链接护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_生命链接护手", "生命链接"]], [[100, 0.0200, true]], [[8, {"dr_pct": 0.1000}]], "主动技能“生命链接”——链接一名友方，分担其50%伤害并持续治疗，冷却20秒", "治疗效果增加2%", "链接期间自身获得10%减伤"],
  ["B079", "能量护盾肩甲", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_能量护盾肩甲", "能量护盾"]], [[140, 0.0200, true]], [[4, 14, Stat.ATK, 0.8000, 0]], "主动技能“能量护盾”——获得吸收20%最大生命值的护盾，持续6秒，冷却18秒", "护盾强度增加2%", "护盾被击破时对周围造成80%攻击力伤害"],
  ["B080", "荆棘爆发头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_荆棘爆发头盔", "荆棘爆发"]], [[104, 0.0200, true]], [[4, 24, Stat.DEF, 0.0, 0]], "主动技能“荆棘爆发”——3秒内反弹100%伤害，冷却15秒", "反伤效果增加2%", "荆棘爆发期间免疫控制"],
  ["B081", "战吼腿甲", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_战吼腿甲", "战吼"]], [[Stat.DEF, 0.0200, true]], [[8, {"on_cast_buff": "taunt", "on_cast_seconds": 1}]], "主动技能“战吼”——周围敌人攻击力降低20%，持续5秒，冷却20秒", "护甲增加2%", "战吼同时嘲讽敌人1秒"],
  ["B082", "烟雾弹头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_烟雾弹头盔", "烟雾弹"]], [[111, 0.0200, true]], [[4, 27, Stat.SPD, 0.2000, 0]], "主动技能“烟雾弹”——释放烟雾，自身进入隐身3秒，冷却15秒", "闪避率增加2%", "隐身期间移速+20%"],
  ["B083", "召唤护卫胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_召唤护卫胸甲", "召唤护卫"]], [[116, 0.0200, true]], [[2, "summon_death_boom", 1.0, 0.0, {"mult": 0.5000, "by": "ap"}]], "主动技能“召唤护卫”——召唤一个护卫（继承50%生命，30%攻击，持续15秒），冷却25秒", "召唤物生命增加2%", "护卫死亡时爆炸，造成50%法强伤害"],
  ["B084", "反击姿态护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_反击姿态护手", "反击姿态"]], [[110, 0.0200, true]], [[4, 24, Stat.DEF, 0.3000, 0]], "主动技能“反击姿态”——3秒内格挡所有攻击并反弹50%伤害，冷却18秒", "格挡率增加2%", "反击姿态期间受到伤害减少30%"],
  ["B085", "疾风步腿甲", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_疾风步腿甲", "疾风步"]], [[Stat.SPD, 0.0200, true]], [[8, {"fire_path_seconds": 3.0, "fire_path_mult": 0.0}]], "主动技能“疾风步”——移速+50%，闪避+30%，持续4秒，冷却15秒", "移动速度增加2%", "疾风步期间留下火焰路径"],
  ["B086", "冰霜新星胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_冰霜新星胸甲", "冰霜新星"]], [[122, 0.0200, true]], [[141, 0.1500, true]], "主动技能“冰霜新星”——冻结周围3米敌人1.5秒，冷却15秒", "冰霜伤害增加2%", "被冻结敌人受到伤害+15%"],
  ["B087", "火焰吐息头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_火焰吐息头盔", "火焰吐息"]], [[121, 0.0200, true]], [[8, {"fire_path_seconds": 3.0, "fire_path_mult": 0.0}]], "主动技能“火焰吐息”——向前方扇形区域造成150%法强火焰伤害，冷却10秒", "火焰伤害增加2%", "火焰吐息留下燃烧地面"],
  ["B088", "治疗之泉战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_治疗之泉战靴", "治疗之泉"]], [[100, 0.0200, true]], [[4, 18, Stat.DEF, 0.0500, 0]], "主动技能“治疗之泉”——在脚下生成治疗区域，每秒回复3%生命，持续5秒，冷却20秒", "生命回复增加2%", "治疗区域同时提供5%减伤"],
  ["B089", "暗影步斗篷", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_暗影步斗篷", "暗影步"]], [[127, 0.0200, true]], [[4, 27, Stat.DEF, 0.0, 0]], "主动技能“暗影步”——进入隐身2秒，下次攻击+50%伤害，冷却12秒", "暗影伤害增加2%", "隐身期间免疫控制"],
  ["B090", "加速护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_加速护符", "加速"]], [[Stat.ASPD, 0.0100, true]], [[4, 21, Stat.DEF, 0.0, 0]], "主动技能“加速”——移速+40%，攻速+20%，持续5秒，冷却20秒", "攻击速度增加1%", "加速期间免疫减速"],
  ["B091", "元素爆发戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_元素爆发戒指", "元素爆发"]], [[117, 0.0200, true]], [[2, "burn", 0.15, 3.0]], "主动技能“元素爆发”——对周围造成随机元素爆炸，伤害150%法强，冷却12秒", "元素伤害增加2%", "元素爆发有20%概率附加对应元素状态"],
  ["B092", "召唤元素戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_召唤元素戒指", "召唤元素"]], [[116, 0.0200, true]], [[2, "burn", 0.30, 3.0]], "主动技能“召唤元素”——召唤一个元素灵体（继承40%法强，持续15秒），冷却25秒", "召唤物伤害增加2%", "元素灵体攻击附带元素状态"],
  ["B093", "护盾术项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_护盾术项链", "护盾术"]], [[140, 0.0200, true]], [[4, 15, Stat.ATK, 0.1000, 0]], "主动技能“护盾术”——获得吸收15%最大生命的护盾，持续8秒，冷却18秒", "护盾强度增加2%", "护盾存在时攻击+10%"],
  ["B094", "传送戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_传送戒指", "传送"]], [[Stat.SPD, 0.0200, true]], [[4, 4, 111, 0.2000, 0, 0, {"seconds": 3.0000}]], "主动技能“传送”——瞬移至8米内指定位置，冷却15秒", "移动速度增加2%", "传送后获得3秒闪避+20%"],
  ["B095", "治愈术护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_治愈术护符", "治愈术"]], [[100, 0.0200, true]], [[8, {"on_cast_dispel": 1}]], "主动技能“治愈术”——治疗自身20%最大生命，冷却20秒", "治疗效果增加2%", "治愈术同时清除一个负面状态"],
  ["B096", "荆棘领域徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_荆棘领域徽章", "荆棘领域"]], [[104, 0.0200, true]], [[2, "zone_slow", 1.0, 0.0, {"slow_pct": 0.2000}]], "主动技能“荆棘领域”——3秒内周围敌人受到反弹伤害，冷却18秒", "反伤效果增加2%", "领域内敌人移速-20%"],
  ["B097", "猎人标记徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_猎人标记徽章", "猎人标记"]], [[Stat.CRT, 0.0100, true]], [[2, "burn", 0.30, 3.0]], "主动技能“猎人标记”——标记一个敌人，使其受到伤害+20%，持续8秒，冷却15秒", "暴击率增加1%", "标记目标死亡时，标记扩散至周围敌人"],
  ["B098", "资源爆发项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_资源爆发项链", "资源爆发"]], [[119, 0.0200, true]], [[117, 0.2000, true]], "主动技能“资源爆发”——立即回复50%职业资源，冷却25秒", "资源上限增加2%", "资源爆发后下次技能伤害+20%"],
  ["B099", "时间减缓沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_时间减缓沙漏", "时间减缓"]], [[Stat.CDR, 0.0100, true]], [[4, 23, Stat.ASPD, 0.2000, 0]], "主动技能“时间减缓”——周围敌人移速-50%，攻速-30%，持续3秒，冷却20秒", "冷却缩减增加1%", "时间减缓期间自身攻速+20%"],
  ["B100", "挑衅战锤", "axe", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_挑衅战锤", "挑衅"]], [[Stat.DEF, 0.0100, true]], [[4, 20, Stat.DEF, 0.1000, 0]], "主动技能“挑衅”——嘲讽周围3米敌人2秒，并造成60%攻击力伤害，冷却15秒", "护甲增加1%", "嘲讽期间受到伤害减少10%"],
  ["B101", "投掷飞斧", "axe", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_投掷飞斧", "投掷飞斧"]], [[Stat.ATK, 0.0100, true]], [[117, 0.1500, true]], "主动技能“投掷飞斧”——投掷飞斧，对路径敌人造成100%攻击力伤害，冷却8秒", "攻击力增加1%", "飞斧命中后弹射至最近敌人（50%伤害）"],
  ["B102", "缠绕藤蔓法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_缠绕藤蔓法杖", "缠绕藤蔓"]], [[124, 0.0100, true]], [[117, 0.3000, true]], "主动技能“缠绕藤蔓”——在目标区域召唤藤蔓，束缚敌人1秒并造成60%法强土元素伤害，冷却14秒", "土元素伤害增加1%", "藤蔓消失时对周围造成30%法强伤害"],
  ["B103", "驱散之刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [[7, "eq_驱散之刃", "驱散"]], [[139, 0.0100, true]], [[146, 0.1000, true]], "主动技能“驱散”——移除自身一个负面状态，并对周围造成50%攻击力伤害，冷却20秒", "异常状态抗性增加1%", "驱散成功后获得3秒10%减伤"],
  ["B104", "沉默重弩", "crossbow", ["远程", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_沉默重弩", "沉默箭"]], [[105, 0.0100, true]], [[2, "slow", 1.0, 3.0, {"slow": 0.2000}]], "主动技能“沉默箭”——发射沉默箭，使目标无法使用技能2秒，冷却18秒", "对精英/Boss伤害增加1%", "沉默箭命中后目标移速-20%"],
  ["B105", "净化法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_净化法环", "净化"]], [[100, 0.0100, true]], [[100, 0.0500, true]], "主动技能“净化”——清除自身及周围友方一个负面状态，冷却25秒", "治疗效果增加1%", "净化同时回复5%最大生命"],
  ["B106", "锁链拖拽链刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_锁链拖拽链刃", "锁链拖拽"]], [[Stat.ASPD, 0.0100, true]], [[2, "judgement", 1.0, 0.0, {"vuln": 0.1000, "seconds": 3.0000}]], "主动技能“锁链拖拽”——将前方8米内一个敌人拉至身前，造成80%攻击力伤害，冷却12秒", "攻击速度增加1%", "拖拽后目标受到伤害+10%，持续3秒"],
  ["B107", "击退长矛", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_击退长矛", "击退突刺"]], [[Stat.ATK, 0.0100, true]], [[101, 0.5000, true]], "主动技能“击退突刺”——向前突刺，击退路径敌人并造成100%攻击力伤害，冷却10秒", "攻击力增加1%", "击退撞墙敌人受到额外50%伤害"],
  ["B108", "生命汲取战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[7, "eq_生命汲取战镰", "生命汲取"]], [[100, 0.0100, true]], [[4, 3, Stat.HP, 0.05, 0]], "主动技能“生命汲取”——对周围敌人造成70%攻击力伤害，回复造成伤害的30%生命，冷却15秒", "生命偷取增加1%", "命中3个以上敌人时回复量翻倍"],
  ["B109", "火焰喷射法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_火焰喷射法杖", "火焰喷射"]], [[121, 0.0100, true]], [[8, {"fire_path_seconds": 2, "fire_path_mult": 0.2000}]], "主动技能“火焰喷射”——向前方扇形区域持续喷射火焰，每秒造成50%法强火焰伤害，持续2秒，冷却12秒", "火焰伤害增加1%", "火焰喷射留下燃烧地面（每秒20%法强，持续2秒）"],
  ["B110", "冰锥术法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_冰锥术法杖", "冰锥术"]], [[122, 0.0100, true]], [[117, 0.2000, true]], "主动技能“冰锥术”——发射3枚冰锥，每枚造成60%法强冰霜伤害，冷却8秒", "冰霜伤害增加1%", "冰锥命中同一目标时伤害递增20%"],
  ["B111", "落石术法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_落石术法环", "落石术"]], [[124, 0.0100, true]], [[2, "stun", 1.0, 0.5]], "主动技能“落石术”——在目标区域召唤落石，造成120%法强土元素伤害，冷却10秒", "土元素伤害增加1%", "落石造成眩晕0.5秒"],
  ["B112", "风刃长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_风刃长弓", "风刃"]], [[125, 0.0100, true]], [[117, 0.1500, true]], "主动技能“风刃”——射出风刃，穿透所有敌人，造成90%攻击力风元素伤害，冷却8秒", "风元素伤害增加1%", "风刃对路径敌人造成牵引"],
  ["B113", "雷霆标枪", "javelin", ["远程", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[7, "eq_雷霆标枪", "雷霆标枪"]], [[123, 0.0100, true]], [[117, 0.5000, true]], "主动技能“雷霆标枪”——投掷雷电标枪，对目标造成130%攻击力雷电伤害并麻痹0.5秒，冷却10秒", "雷电伤害增加1%", "标枪落点对周围造成50%攻击力伤害"],
  ["B114", "暗影箭匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [[7, "eq_暗影箭匕首", "暗影箭"]], [[127, 0.0100, true]], [[4, 1, Stat.HP, 0.0300, 0]], "主动技能“暗影箭”——发射暗影箭，造成100%攻击力暗影伤害，冷却6秒", "暗影伤害增加1%", "暗影箭击杀敌人时回复3%最大生命"],
  ["B115", "治疗图腾法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [[7, "eq_治疗图腾法杖", "治疗图腾"]], [[100, 0.0100, true]], [[4, 17, Stat.DEF, 0.0500, 0]], "主动技能“治疗图腾”——放置图腾，每秒回复周围友方2%最大生命，持续5秒，冷却25秒", "治疗效果增加1%", "图腾存在时自身获得5%减伤"],
  ["B116", "石肤胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_石肤胸甲", "石肤"]], [[Stat.DEF, 0.0100, true]], [[4, 21, Stat.DEF, 0.0, 0]], "主动技能“石肤”——获得20%减伤，持续5秒，冷却20秒", "护甲增加1%", "石肤期间免疫击退"],
  ["B117", "疾跑战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_疾跑战靴", "疾跑"]], [[Stat.SPD, 0.0100, true]], [[4, 19, 111, 0.1000, 0]], "主动技能“疾跑”——移速+30%，持续4秒，冷却15秒", "移动速度增加1%", "疾跑期间闪避+10%"],
  ["B118", "护盾发生器肩甲", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_护盾发生器肩甲", "护盾发生器"]], [[140, 0.0100, true]], [[4, 14, Stat.ATK, 0.5000, 0]], "主动技能“护盾发生器”——获得吸收10%最大生命的护盾，持续6秒，冷却20秒", "护盾强度增加1%", "护盾被击破时对周围造成50%攻击力伤害"],
  ["B119", "烟雾弹护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_烟雾弹护手", "烟雾弹"]], [[111, 0.0100, true]], [[4, 27, Stat.SPD, 0.1500, 0]], "主动技能“烟雾弹”——释放烟雾，自身进入隐身2秒，冷却18秒", "闪避率增加1%", "隐身期间移速+15%"],
  ["B120", "战吼头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_战吼头盔", "战吼"]], [[Stat.DEF, 0.0100, true]], [[8, {"on_cast_buff": "taunt", "on_cast_seconds": 1}]], "主动技能“战吼”——周围敌人攻击力降低10%，持续5秒，冷却22秒", "护甲增加1%", "战吼同时嘲讽敌人1秒"],
  ["B121", "荆棘护盾腿甲", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_荆棘护盾腿甲", "荆棘护盾"]], [[104, 0.0100, true]], [[4, 24, Stat.DEF, 0.1000, 0]], "主动技能“荆棘护盾”——3秒内反弹50%伤害，冷却18秒", "反伤效果增加1%", "荆棘护盾期间受到伤害减少10%"],
  ["B122", "生命链接护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_生命链接护符", "生命链接"]], [[Stat.HP, 0.0100, true]], [[8, {"dr_pct": 0.0500}]], "主动技能“生命链接”——链接一名友方，分担其30%伤害，持续5秒，冷却25秒", "最大生命值增加1%", "链接期间自身获得5%减伤"],
  ["B123", "冰霜新星胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_冰霜新星胸甲", "冰霜新星"]], [[122, 0.0100, true]], [[141, 0.1000, true]], "主动技能“冰霜新星”——冻结周围2.5米敌人1秒，冷却18秒", "冰霜伤害增加1%", "被冻结敌人受到伤害+10%"],
  ["B124", "火焰吐息头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_火焰吐息头盔", "火焰吐息"]], [[121, 0.0100, true]], [[8, {"fire_path_seconds": 2, "fire_path_mult": 0.2000}]], "主动技能“火焰吐息”——向前方扇形造成100%法强火焰伤害，冷却12秒", "火焰伤害增加1%", "火焰吐息留下燃烧地面（每秒20%法强，持续2秒）"],
  ["B125", "闪现护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_闪现护手", "闪现"]], [[Stat.SPD, 0.0100, true]], [[4, 3, Stat.ATK, 0.2000, 0]], "主动技能“闪现”——瞬移4米，冷却15秒", "移动速度增加1%", "闪现后下次攻击+20%伤害"],
  ["B126", "召唤护卫胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_召唤护卫胸甲", "召唤护卫"]], [[116, 0.0100, true]], [[117, 0.4000, true]], "主动技能“召唤护卫”——召唤一个护卫（继承40%生命，20%攻击，持续12秒），冷却28秒", "召唤物生命增加1%", "护卫死亡时对周围造成40%法强伤害"],
  ["B127", "净化腿甲", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_净化腿甲", "净化"]], [[139, 0.0100, true]], [[106, 0.1000, true]], "主动技能“净化”——清除自身一个负面状态，冷却25秒", "异常状态抗性增加1%", "净化后获得3秒10%减伤"],
  ["B128", "反击姿态肩甲", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_反击姿态肩甲", "反击姿态"]], [[110, 0.0100, true]], [[4, 24, Stat.DEF, 0.1500, 0]], "主动技能“反击姿态”——3秒内格挡所有攻击并反弹30%伤害，冷却20秒", "格挡率增加1%", "反击姿态期间受到伤害减少15%"],
  ["B129", "治疗之泉战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[7, "eq_治疗之泉战靴", "治疗之泉"]], [[100, 0.0100, true]], [[4, 18, Stat.DEF, 0.0500, 0]], "主动技能“治疗之泉”——脚下生成治疗区域，每秒回复2%生命，持续5秒，冷却25秒", "生命回复增加1%", "治疗区域同时提供5%减伤"],
  ["B130", "加速护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_加速护符", "加速"]], [[Stat.ASPD, 0.0100, true]], [[4, 21, Stat.DEF, 0.0, 0]], "主动技能“加速”——移速+25%，攻速+15%，持续5秒，冷却22秒", "攻击速度增加1%", "加速期间免疫减速"],
  ["B131", "元素爆发戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_元素爆发戒指", "元素爆发"]], [[117, 0.0100, true]], [[2, "burn", 0.15, 3.0]], "主动技能“元素爆发”——对周围造成随机元素爆炸，伤害100%法强，冷却14秒", "元素伤害增加1%", "元素爆发有15%概率附加对应元素状态"],
  ["B132", "传送戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_传送戒指", "传送"]], [[Stat.SPD, 0.0100, true]], [[4, 4, 111, 0.1500, 0, 0, {"seconds": 3.0000}]], "主动技能“传送”——瞬移至6米内指定位置，冷却18秒", "移动速度增加1%", "传送后获得3秒闪避+15%"],
  ["B133", "护盾术项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_护盾术项链", "护盾术"]], [[140, 0.0100, true]], [[4, 15, Stat.ATK, 0.0800, 0]], "主动技能“护盾术”——获得吸收8%最大生命的护盾，持续8秒，冷却20秒", "护盾强度增加1%", "护盾存在时攻击+8%"],
  ["B134", "治愈术护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_治愈术护符", "治愈术"]], [[100, 0.0100, true]], [[8, {"on_cast_dispel": 1}]], "主动技能“治愈术”——治疗自身15%最大生命，冷却25秒", "治疗效果增加1%", "治愈术同时清除一个负面状态"],
  ["B135", "猎人标记徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_猎人标记徽章", "猎人标记"]], [[Stat.CRT, 0.0100, true]], [[2, "burn", 0.30, 3.0]], "主动技能“猎人标记”——标记一个敌人，使其受到伤害+15%，持续8秒，冷却18秒", "暴击率增加1%", "标记目标死亡时，标记扩散至周围敌人"],
  ["B136", "资源回复项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_资源回复项链", "资源回复"]], [[119, 0.0100, true]], [[119, 0.1500, true]], "主动技能“资源回复”——立即回复30%职业资源，冷却28秒", "资源上限增加1%", "资源回复后下次技能伤害+15%"],
  ["B137", "时间减缓沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_时间减缓沙漏", "时间减缓"]], [[Stat.CDR, 0.0100, true]], [[4, 23, Stat.ASPD, 0.1500, 0]], "主动技能“时间减缓”——周围敌人移速-30%，攻速-20%，持续3秒，冷却25秒", "冷却缩减增加1%", "时间减缓期间自身攻速+15%"],
  ["B138", "荆棘领域徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_荆棘领域徽章", "荆棘领域"]], [[104, 0.0100, true]], [[2, "zone_slow", 1.0, 0.0, {"slow_pct": 0.1500}]], "主动技能“荆棘领域”——3秒内周围敌人受到反弹伤害，冷却20秒", "反伤效果增加1%", "领域内敌人移速-15%"],
  ["B139", "召唤元素戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[7, "eq_召唤元素戒指", "召唤元素"]], [[116, 0.0100, true]], [[2, "burn", 0.30, 3.0]], "主动技能“召唤元素”——召唤一个元素灵体（继承30%法强，持续12秒），冷却28秒", "召唤物伤害增加1%", "元素灵体攻击附带元素状态"],
  ["P000", "腐蚀之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[2, "burn", 0.1500, 4.0], [2, "judgement", 1.0, 0.0, {"vuln": 0.0500}]], [[117, 0.0300, true]], [[4, 10, 117, 0.8000, 0]], "攻击有15%概率施加随机异常（灼烧/冰冻/中毒/麻痹），持续4秒；目标每携带一种不同异常，受到伤害+5%（最多3种，+15%）", "异常状态伤害增加3%", "攻击命中携带3种异常的敌人时，引爆所有异常，每种造成80%攻击力对应元素伤害"],
  ["P001", "血怒巨斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[118, 2.0000, true], [4, 1, Stat.HP, 0.1500, 0]], [[100, 0.0300, true]], [[4, 11, 117, 0.2500, 0, 0.4000]], "攻击消耗3%当前生命，额外造成消耗生命200%的伤害；击杀敌人回复15%最大生命", "生命偷取增加3%", "生命低于40%时，攻击不再消耗生命，且伤害提升25%"],
  ["P002", "元素编织法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[117, 0.3000, true]], [[117, 0.0300, true]], [[2, "burn", 0.15, 3.0]], "每次施放技能自动切换元素（火→冰→雷→毒→土→风循环），切换后下一个技能伤害+30%并附带对应元素状态", "元素伤害增加3%", "连续使用同一元素3次后，触发元素爆发（200%法强范围伤害，冷却10秒）"],
  ["P003", "影舞匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 105.0, false]], [[105, 0.6000, true], [[4, 6, Stat.ASPD, 0.0400, 5], [4, 6, Stat.CRT, 0.0300, 5]]], [[105, 0.0300, true]], [[4, 5, Stat.CRD, 0.30, 0]], "背刺伤害+60%；每次背刺成功叠加1层“影舞”（最多5层），每层+4%攻速、+3%暴击率", "背刺伤害增加3%", "影舞满层时，下一次背刺必定暴击并造成300%伤害"],
  ["P004", "猎杀者长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[2, "judgement", 1.0, 0.0, {"vuln": 0.0400, "max_stacks": 5, "seconds": 8.0000}], [Stat.CRT, 0.30, true]], [[135, 0.0300, true]], [[2, "spread_mark", 1.0, 0.0]], "攻击施加“猎杀标记”（最多5层，持续8秒），每层目标受到伤害+4%；对5层标记目标攻击必定暴击", "远程伤害增加3%", "击杀5层标记目标时，标记转移至周围敌人并刷新持续时间"],
  ["P005", "不灭壁垒", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[[4, 2, 146, 0.0200, 10], [4, 2, 104, 0.0100, 10]], [4, 5, 106, 0.2000, 0]], [[Stat.DEF, 0.0300, true]], [[4, 14, Stat.ATK, 0.0, 0]], "每次受到伤害叠加1层“不灭”（最多10层），每层+2%减伤、+1%反伤；满层时消耗所有层数获得吸收20%最大生命的护盾", "护甲增加3%", "护盾被击破时，对周围造成（反伤层数×10%）攻击力的伤害"],
  ["P006", "预言者头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 6, Stat.CRD,  0.0300,  5,  0], [4, 5, Stat.ATK, 1.0000, 0, 0, {"burst": "prophecy", "crit_mult": 1.5, "spread_count": 0, "spread_layers": 0}]], [[Stat.CRT, 0.0200, true]], [[148, 0.0500, true]], "暴击叠加1层“预言”（最多5层），每层+3%暴击伤害；5层时下一次攻击必定暴击且暴击伤害+50%", "暴击率增加2%", "暴击时5%概率立即刷新一个技能冷却"],
  ["P007", "踏虚战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[116, 0.10, true], [4, 4, 111, 0.0500, 3]], [[Stat.SPD, 0.0300, true]], [[147, 1.0, true]], "冲刺后留下残影，残影爆炸造成50%攻击力伤害；每次冲刺叠加1层“踏虚”（最多3层），每层+5%闪避", "移动速度增加3%", "闪避成功时立即刷新冲刺冷却"],
  ["P008", "元素之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[106, 0.1000, true], [4, 2, 117, 0.1500, 3]], [[106, 0.0200, true]], [[3, "fire", 0.3000]], "所有元素抗性+10%；受到元素伤害时，获得对应元素伤害+15%（持续5秒，可叠加3层）", "元素抗性增加2%", "元素抗性超过30%时，攻击附带对应元素伤害（30%攻击力）"],
  ["P009", "灵魂容器", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[[4, 1, Stat.ATK, 0.0200, 10], [4, 1, 145, 0.0100, 10]], [4, 5, 119, 0.50, 0, 0, {"seconds": 5.0000}]], [[119, 0.0300, true]], [[8, {"ultimate_soul_per_stack": 0.2000}]], "击杀敌人获得1层“灵魂”（最多10层），每层+2%伤害、+1%资源回复；满层时技能消耗减半（持续5秒）", "资源上限增加3%", "释放终极技能时消耗所有灵魂，每层额外造成20%伤害"],
  ["P010", "霜噬巨剑", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[2, "judgement", 1.0, 0.0, {"vuln": 0.0400, "max_stacks": 8, "seconds": 6.0000}], [4, 5, Stat.ATK, 2.0000, 8]], [[122, 0.0300, true]], [[2, "freeze", 1.0, 1.5]], "攻击施加“霜噬”层数（最多8层，持续6秒），每层使目标移速-5%、受到冰霜伤害+4%；8层时触发冰爆（200%攻击力冰霜伤害，冷却8秒）", "冰霜伤害增加3%", "冰爆冻结目标1.5秒"],
  ["P011", "烈焰裁决者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[2, "burn", 0.2000, 4, {"dot_atk": 0.3000}], [2, "burn", 1.0, 4.0]], [[121, 0.0300, true]], [[2, "burn", 1.0, 4.0]], "攻击有20%概率点燃目标（每秒30%攻击力火焰伤害，持续4秒）；点燃目标死亡时，火焰扩散至周围2米", "火焰伤害增加3%", "被点燃目标受到暴击时，火焰持续时间刷新"],
  ["P012", "雷霆之怒", "axe", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[2, "paralyze", 0.1500, 1.0], [4, 28, 117, 0.6000, 0]], [[123, 0.0300, true]], [[117, 0.1500, true]], "攻击有15%概率麻痹目标1秒；麻痹目标受到雷电伤害时，雷电跳跃至最近2名敌人（60%伤害）", "雷电伤害增加3%", "跳跃次数+1"],
  ["P013", "剧毒之牙", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 105.0, false]], [[2, "poison_rot", 1.0, 5.0, {"dot_atk": 0.2000, "vuln": 0.0100, "max_stacks": 5}], [4, 5, Stat.ATK, 0.8000, 5]], [[126, 0.0300, true]], [[117, 0.2000, true]], "攻击必定施加中毒（每秒20%攻击力毒素伤害，持续5秒，最多5层）；5层时下一次攻击引爆所有毒层（每层80%攻击力毒素伤害）", "毒素伤害增加3%", "毒爆使目标受到的毒素伤害+20%，持续5秒"],
  ["P014", "大地震击", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[117, 0.5000, true], [117, 0.3000, true]], [[124, 0.0300, true]], [[2, "stun", 0.1500, 1.0]], "攻击造成范围震击（1.5米，50%攻击力）；对眩晕目标伤害+30%", "土元素伤害增加3%", "震击有15%概率眩晕1秒"],
  ["P015", "风语长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[3, "wind", 0.3000], [2, "pull", 1.0, 0.0]], [[125, 0.0300, true]], [[8, {"multi_hit_at": 3, "multi_hit_bonus": 1.5000}]], "攻击附带风元素（30%攻击力）；命中时牵引目标1米", "风元素伤害增加3%", "牵引3个以上敌人时，触发风爆（150%攻击力风元素伤害）"],
  ["P016", "暗影收割者", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[4, 1, Stat.ATK,  0.0200,  15,  0], [4, 5, Stat.ATK, 2.0000, 0]], [[127, 0.0300, true]], [[2, "soul_persist", 1.0, 0.0]], "击杀敌人获得1层“暗影”（最多15层），每层+2%攻击力；满层时下次攻击释放暗影波（200%攻击力暗影伤害）", "暗影伤害增加3%", "暗影波击杀敌人时，层数不清空"],
  ["P017", "圣光裁决", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[4, 37, Stat.AP, 0.5000, 0]], [[100, 0.0300, true]], [[2, "blind", 0.1500, 1.0000]], "治疗自身时，对周围敌人造成治疗量50%的圣光伤害", "治疗效果增加3%", "圣光伤害有15%概率致盲敌人1秒"],
  ["P018", "虚空之刺", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[103, 0.3000, true], [117, 0.2000, true]], [[103, 0.0300, true]], [[4, 1, 103, 1.0000, 0]], "攻击无视30%护甲；对护甲低于50%的敌人伤害+20%", "护甲穿透增加3%", "击杀敌人后，下次攻击无视100%护甲"],
  ["P019", "混沌之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[3, "fire", 0.5000], [117, 1.5000, true]], [[117, 0.0300, true]], [[2, "burn", 0.30, 3.0]], "每次攻击随机附带一种元素伤害（50%攻击力）；连续3次不同元素后触发混沌爆炸（150%攻击力全元素伤害）", "元素伤害增加3%", "混沌爆炸附加随机元素状态"],
  ["P020", "生命之弦", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[4, 3, Stat.HP, 0.0100, 0], [2, "grant_shield", 1.0, 0.0, {"pct": 0.1000, "cap": 0.1000}]], [[100, 0.0300, true]], [[4, 15, Stat.ATK, 0.1000, 0]], "攻击命中回复1%最大生命；生命满时，回复转化为护盾（最多10%最大生命）", "生命回复增加3%", "护盾存在时，攻击附带10%额外伤害"],
  ["P021", "破晓之光", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[103, 1.0000, true]], [[117, 0.0300, true]], [[4, 14, 117, 0.5000, 0]], "攻击有15%概率破除目标隐身/护盾，并造成100%攻击力光伤害", "光伤害增加3%", "破除护盾时，对周围造成50%攻击力光伤害"],
  ["P022", "深渊低语", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[2, "summon_soul", 0.10, 0.0]], [[116, 0.0300, true]], [[2, "summon_death_boom", 1.0, 0.0, {"mult": 0.5000, "by": "ap"}]], "击杀敌人有10%概率召唤其灵魂（继承30%攻击，持续10秒，最多3个）", "召唤物伤害增加3%", "灵魂死亡时爆炸，造成50%法强伤害"],
  ["P023", "星辰碎片", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[4, 18, 117, 0.8000, 0]], [[136, 0.0300, true]], [[8, {"multi_hit_at": 3, "multi_hit_bonus": 1.2000}]], "技能命中时，在目标位置召唤星辰碎片（1秒后坠落，造成80%法强伤害，冷却3秒）", "范围伤害增加3%", "星辰碎片命中3个以上敌人时，伤害提升至120%"],
  ["P024", "复仇之刺", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 105.0, false]], [[4, 2, Stat.ATK,  0.0500,  5,  0], [Stat.CRD, 0.30, true]], [[105, 0.0300, true]], [[4, 5, Stat.CRD, 0.30, 0]], "受到伤害时获得1层“复仇”（最多5层），每层+5%背刺伤害；背刺消耗所有层数并造成额外伤害", "背刺伤害增加3%", "复仇满层时，背刺必定暴击"],
  ["P025", "冰霜之心", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[106, 0.1000, true], [2, "zone_slow", 1.0, 0.0, {"slow_pct": 0.2000, "require_shield": true}]], [[106, 0.0300, true]], [[2, "freeze", 1.0, 1.0]], "获得冰霜护盾（吸收10%最大生命，冷却15秒）；护盾存在时，周围敌人移速-20%", "冰霜抗性增加3%", "护盾被击破时冻结周围1秒"],
  ["P026", "烈焰之魂", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[2, "burn", 1.0, 3.0], [2, "summon_death_boom", 1.0, 0.0, {"mult": 0.5000, "by": "atk"}]], [[121, 0.0300, true]], [[8, {"radius_mult": 1.0100}]], "受到近战攻击时，对攻击者施加燃烧（每秒20%攻击力，持续3秒）；燃烧目标死亡时爆炸（50%攻击力）", "火焰伤害增加3%", "燃烧爆炸范围+1米"],
  ["P027", "雷霆护肩", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 2, Stat.ATK,  0.02,  5,  0], [4, 5, Stat.ATK, 1.0000, 0]], [[123, 0.0300, true]], [[2, "soul_persist", 1.0, 0.0]], "受到伤害时获得1层“充能”（最多5层）；满层时释放雷电新星（100%攻击力雷电伤害，麻痹1秒）", "雷电伤害增加3%", "雷电新星触发后，充能层数不清空（改为冷却5秒）"],
  ["P028", "大地守护", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[2, "stationary_buff", 1.0, 0.0, {"stationary_seconds": 1, "dr_pct": 0.2000, "reflect_pct": 0.1000, "shield_pct": 0.0}]], [[Stat.DEF, 0.0300, true]], [[4, 21, Stat.DEF, 0.0, 0]], "站立不动1秒后获得“大地守护”（+20%减伤，+10%反伤），移动后失效", "护甲增加3%", "大地守护期间免疫击退"],
  ["P029", "风行者", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 10, Stat.SPD,  0.0200,  10,  0], [3, "wind", 1.0000]], [[Stat.SPD, 0.0300, true]], [[4, 5, Stat.SPD, 0.10, 0]], "移动时叠加“风行”（最多10层），每层+2%移速；满层时下次攻击附带风元素（100%攻击力）", "移动速度增加3%", "满层攻击后，移速加成保留3秒"],
  ["P030", "暗影斗篷", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[111, 0.30, true], [4, 27, Stat.CRT, 0.3000, 0]], [[Stat.CRT, 0.0200, true]], [[4, 27, 111, 0.30, 0]], "进入战斗后每5秒获得1秒隐身；隐身期间暴击率+30%", "暴击率增加2%", "隐身期间击杀敌人，刷新隐身"],
  ["P031", "圣光护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[2, "grant_shield", 1.0, 0.0, {"pct": 0.1500, "cap": 0.1500, "of_heal_ratio": 0.3000}]], [[100, 0.0300, true]], [[4, 15, Stat.DEF, 0.1000, 0]], "治疗时额外获得治疗量30%的护盾（最多15%最大生命）", "治疗效果增加3%", "护盾存在时，受到伤害减少10%"],
  ["P032", "虚空之眼", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[103, 0.1500, true], [4, 1, 117, 0.0500, 0]], [[103, 0.0300, true]], [[117, 0.1000, true]], "周围敌人护甲-15%；击杀敌人后，光环范围+1米（最多+3米）", "护甲穿透增加3%", "光环内敌人受到的真实伤害+10%"],
  ["P033", "混沌之皮", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[6, 10, "eq_periodic_elem_resist", 10, {"elem_resist_pct": 0.3000}]], [[106, 0.0300, true]], [[4, 36, 117, 0.5000, 0]], "每10秒获得随机元素抗性+30%，持续10秒", "元素抗性增加3%", "抗性触发时，对周围造成对应元素伤害（50%攻击力）"],
  ["P034", "生命之树", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[100, 0.0100, true], [2, "grant_shield", 1.0, 0.0, {"pct": 0.2000, "cap": 0.2000}]], [[100, 0.0300, true]], [[4, 14, Stat.HP, 0.1000, 0]], "每秒回复1%最大生命；生命满时，回复量转化为护盾（最多20%最大生命）", "生命回复增加3%", "护盾被击破时，回复10%最大生命"],
  ["P035", "星辰披风", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 4, 104, 0.5000, 0]], [[111, 0.0200, true]], [[4, 4, 111, 0.1000, 0, 0, {"seconds": 3.0000}]], "闪避成功时，对攻击者造成50%攻击力星辰伤害", "闪避率增加2%", "闪避成功后获得3秒+10%闪避"],
  ["P036", "复仇之甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 2, Stat.ATK,  0.0200,  10,  0], [4, 5, Stat.ATK, 1.5000, 0]], [[Stat.ATK, 0.0200, true]], [[4, 3, Stat.HP, 0.0500, 0]], "受到伤害时获得1层“复仇”（最多10层），每层+2%攻击力；满层时下次攻击释放复仇波（150%攻击力）", "攻击力增加2%", "复仇波命中敌人回复5%最大生命"],
  ["P037", "元素调和者", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 2, 117, 0.1500, 3]], [[117, 0.0300, true]], [[4, 5, Stat.ATK, 1.0000, 0]], "受到元素伤害时，获得对应元素伤害+15%，持续5秒（可叠3层）", "元素伤害增加3%", "叠满3层时，释放元素新星（100%法强对应元素伤害）"],
  ["P038", "灵魂锁链", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 1, Stat.ATK,  0.0200,  10,  0], [4, 5, 119, 0.50, 0]], [[119, 0.0300, true]], [[8, {"ultimate_soul_per_stack": 0.2000}]], "击杀敌人获得1层“灵魂”（最多10层），每层+2%资源回复；满层时技能消耗减半（5秒）", "资源上限增加3%", "释放终极技能消耗所有灵魂，每层+20%伤害"],
  ["P039", "荆棘之环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[104, 0.1500, true], [2, "aura_damage", 1.0, 0.0, {"aura_radius": 3.0, "aura_mult": 0.1000, "aura_interval": 1.0}]], [[104, 0.0300, true]], [[2, "bleed", 0.1500, 3.0, {"trigger": 40}]], "反弹15%近战伤害；周围敌人每秒受到10%攻击力伤害", "反伤效果增加3%", "反弹伤害有15%概率流血3秒"],
  ["P040", "猎杀者徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[2, "mark", 1.0, 0.0, {"max_stacks": 5}], [4, 5, Stat.ATK, 1.0000, 0, 0, {"burst": "prophecy", "crit_mult": 1.5, "spread_count": 0, "spread_layers": 0}]], [[Stat.CRT, 0.0200, true]], [[2, "spread_mark", 1.0, 0.0]], "攻击施加“猎杀标记”（最多5层），每层+3%暴击率；5层时下次攻击必定暴击", "暴击率增加2%", "暴击时标记扩散至周围敌人"],
  ["P041", "元素之戒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[117, 0.2000, true]], [[117, 0.0300, true]], [[2, "elem_seq_distinct", 1.0, 0.0, {"count": 3, "mult": 1.5000, "use_ap": true}]], "每次攻击切换元素，切换后下次攻击+20%对应元素伤害", "元素伤害增加3%", "连续3次不同元素后，触发元素爆炸（150%法强）"],
  ["P042", "生命之泉", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[100, 0.0150, true], [2, "grant_shield", 1.0, 0.0, {"pct": 0.1500, "cap": 0.1500}]], [[100, 0.0300, true]], [[4, 14, Stat.ATK, 0.5000, 0]], "每秒回复1.5%最大生命；满血时回复转护盾（最多15%）", "生命回复增加3%", "护盾被击破时，对周围造成50%攻击力伤害"],
  ["P043", "时空沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[Stat.CDR, 0.0800, true], [4, 18, Stat.CDR, 0.20, 0]], [[Stat.CDR, 0.0200, true]], [[4, 5, 119, 1.0, 0]], "技能冷却缩减8%；使用技能后，下次技能冷却-1秒（最多叠3层）", "冷却缩减增加2%", "叠满3层时，下次技能不消耗资源"],
  ["P044", "贪婪之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[2, "state_scaled", 1.0, 0.0, {"per_gold": 100.0, "gold_atk": 0.0100, "gold_max_pct": 0.2000}]], [[107, 0.0300, true]], [[4, 30, Stat.CRT, 0.1000, 0]], "每持有100金币，+1%攻击力（最多+20%）", "金币获取增加3%", "金币超过500时，暴击率+10%"],
  ["P045", "记忆碎片", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[4, 1, 119, 0.0200, 0], [[Stat.HP, 0.0050, true], [Stat.ATK, 0.0050, true], [Stat.DEF, 0.0050, true], [Stat.SPD, 0.0050, true], [Stat.ASPD, 0.0050, true], [Stat.AP, 0.0050, true], [Stat.CRT, 0.0050, true], [Stat.CRD, 0.0050, true]]], [[119, 0.0300, true]], [[119, 0.1000, true]], "击杀精英获得2点记忆残渣；每点记忆残渣+0.5%全属性（本局）", "记忆残渣获取增加3%", "结算时额外获得10%记忆残渣"],
  ["P046", "钥匙守护", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[109, 0.0500, true], [[Stat.HP, 0.0200, true], [Stat.ATK, 0.0200, true], [Stat.DEF, 0.0200, true], [Stat.SPD, 0.0200, true], [Stat.ASPD, 0.0200, true], [Stat.AP, 0.0200, true], [Stat.CRT, 0.0200, true], [Stat.CRD, 0.0200, true]]], [[109, 0.0200, true]], [[109, 0.1500, true]], "钥匙碎片掉落+5%；每持有一片钥匙碎片，+2%全属性", "钥匙碎片掉落增加2%", "Boss额外掉落1片钥匙碎片的概率+15%"],
  ["P047", "召唤师之核", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[120, 1, false], [116, 0.0500, true]], [[116, 0.0300, true]], [[2, "summon_death_boom", 1.0, 0.0, {"mult": 0.5000, "by": "ap"}]], "召唤物上限+1；每个召唤物+5%召唤物伤害", "召唤物伤害增加3%", "召唤物死亡时爆炸（50%法强）"],
  ["P048", "荆棘领域", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[2, "aura_damage", 1.0, 0.0, {"aura_radius": 3, "aura_mult": 0.1500, "aura_interval": 1.0}], [104, 0.1000, true]], [[104, 0.0300, true]], [[2, "zone_slow", 1.0, 0.0, {"slow_pct": 0.2000}]], "周围3米敌人每秒受到15%攻击力伤害；反弹10%近战伤害", "反伤效果增加3%", "领域内敌人移速-20%"],
  ["P049", "灵魂容器", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[4, 1, Stat.ATK,  0.0200,  10,  0], [4, 5, 119, 0.50, 0]], [[119, 0.0300, true]], [[8, {"ultimate_soul_per_stack": 0.2000}]], "击杀敌人获得1层“灵魂”（最多10层），每层+2%伤害；满层时技能消耗减半（5秒）", "资源上限增加3%", "释放终极技能消耗所有灵魂，每层+20%伤害"],
  ["P050", "格挡反击者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[4, 9, Stat.ATK,  0.0600,  5,  0], [4, 5, Stat.ATK, 1.0000, 0, 0, {"burst": "prophecy", "crit_mult": 2.0000, "spread_count": 0, "spread_layers": 0}]], [[110, 0.0200, true]], [[104, 0.5000, true]], "格挡成功叠加1层“反击”（最多5层），每层+6%下次攻击伤害；5层时下次攻击必定暴击并造成200%伤害", "格挡率增加2%", "格挡成功后立即对攻击者造成50%攻击力反击"],
  ["P051", "分裂弩", "crossbow", ["远程", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[2, "attack_bonus", 1.0, 0.0, {"extra_hits": {"chance": 0.2000, "hits": 2, "mult": 0.5000}}], [117, 0.3000, true]], [[138, 0.0300, true]], [[117, 0.1000, true]], "攻击有20%概率分裂为2枚额外弩箭（各50%伤害）；分裂箭命中后弹射至最近敌人（30%伤害）", "投射物伤害增加3%", "分裂箭弹射次数+1"],
  ["P052", "连击双刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 105.0, false]], [[4, 7, Stat.ATK,  0.0300,  8,  0], [4, 5, Stat.ATK, 0.40, 0]], [[Stat.ASPD, 0.0200, true]], [[Stat.ASPD, 0.10, true]], "连续攻击同一目标时，每次+3%攻速（最多8层）；满层时下次攻击额外攻击2次（各40%伤害）", "攻击速度增加2%", "满层攻击后攻速加成保留3秒"],
  ["P053", "蓄能战锤", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[6, Stat.ATK, 0.15, 1.50], [6, Stat.ATK, 0.15, 1.50]], [[Stat.ATK, 0.0300, true]], [[4, 25, 117, 0.50, 0]], "静止不动时每秒储存15%攻击力（最多储存150%）；下次攻击释放全部储存伤害", "攻击力增加3%", "储存满时，攻击附带范围震击（1.5米）"],
  ["P054", "荆棘长鞭", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[2, "bleed", 1.0, 4.0, {"dot_atk": 0.1500, "max_stacks": 3}], [2, "judgement", 1.0, 0.0, {"vuln": 0.1500}]], [[117, 0.0300, true]], [[2, "bleed", 0.30, 3.0]], "攻击必定施加流血（每秒15%攻击力，持续4秒，最多3层）；3层时目标受到伤害+15%", "流血伤害增加3%", "流血目标死亡时，流血扩散至周围2米"],
  ["P055", "猎手标枪", "javelin", ["远程", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[116, 0.10, true], [117, 0.1500, true], [7, "eq_猎手标枪", "投掷标枪"]], [[117, 0.0300, true]], [[4, 33, 117, 0.1500, 0]], "主动投掷标枪（120%攻击力），标枪留在目标位置；再次使用可回收标枪，对路径敌人造成80%伤害", "投掷伤害增加3%", "回收标枪时，对路径敌人造成牵引"],
  ["P056", "元素之泉法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[2, "elem_next_skill", 1.0, 0.0, {"bonus_pct": 0.2500}], [Stat.ATK, -0.1000, true]], [[117, 0.0300, true]], [[2, "burn", 0.15, 3.0]], "使用不同元素技能时，下一个技能伤害+25%并附带对应元素状态；同元素连用则伤害-10%", "元素伤害增加3%", "交替3次后，下次技能触发元素爆发（180%法强）"],
  ["P057", "格挡者壁垒", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 140.0, false]], [[4, 9, 106,  0.0300,  5,  0], [2, "grant_shield", 1.0, 0.0, {"pct": 0.2000, "cap": 0.60}]], [[110, 0.0200, true]], [[4, 14, Stat.ATK, 0.8000, 0]], "格挡成功获得1层“壁垒”（最多5层），每层+3%减伤；5层时消耗全部层数获得吸收20%最大生命护盾", "格挡率增加2%", "护盾被击破时，对周围造成80%攻击力伤害"],
  ["P058", "延迟伤害甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[152, 0.3000, true], [4, 1, Stat.ATK, 0.10, 0]], [[146, 0.0200, true]], [[4, 1, Stat.ATK, 0.10, 0]], "受到伤害的30%延迟至5秒内逐渐结算；期间若击杀敌人，则取消延迟伤害", "减伤增加2%", "取消延迟伤害时，对周围造成等量伤害"],
  ["P059", "图腾护肩", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[116, 0.10, true], [7, "eq_图腾护肩", "放置图腾"]], [[116, 0.0300, true]], [[2, "summon_death_boom", 1.0, 0.0, {"mult": 0.6000, "by": "ap"}]], "主动放置图腾（继承30%生命，持续10秒），图腾每秒为周围友方提供3%减伤，冷却25秒", "召唤物生命增加3%", "图腾死亡时爆炸，对周围造成60%法强伤害"],
  ["P060", "镜像腿甲", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[116, 0.10, true], [116, 0.3000, true]], [[Stat.SPD, 0.0300, true]], [[2, "summon_death_boom", 1.0, 0.0, {"mult": 0.5000, "by": "atk"}]], "冲刺后留下分身（继承20%攻击，持续4秒，最多2个）；分身攻击造成30%伤害", "移动速度增加3%", "分身死亡时爆炸（50%攻击力）"],
  ["P061", "吸血光环头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[100, 0.0500, true], [100, 0.1000, true]], [[100, 0.0200, true]], [[4, 1, Stat.HP, 0.0200, 0]], "周围3米友方获得5%生命偷取；自身生命低于50%时效果翻倍", "生命偷取增加2%", "光环内敌人死亡时，回复2%最大生命"],
  ["P062", "减伤叠层胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 2, 146, 0.0200, 8], [4, 5, 112, 0.30, 0]], [[Stat.DEF, 0.0300, true]], [[2, "cheat_death", 1.0, 0.0, {"heal_pct": 0.5, "boom_pct": 0.0, "cooldown": 60}]], "每次受到伤害叠加1层“坚韧”（最多8层），每层+2%减伤；满层时免疫下一次控制", "护甲增加3%", "满层时受到致命伤害，消耗全部层数免疫该次伤害（冷却60秒）"],
  ["P063", "技能连发护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 18, Stat.CDR, 0.1500, 0], [119, 1.0, true]], [[Stat.CDR, 0.0200, true]], [[2, "atk_up_self", 1.0, 0.0]], "使用技能后，下次技能冷却-15%（最多叠3层）；叠满后下次技能不消耗资源", "冷却缩减增加2%", "叠满时，下次技能额外释放一次（50%伤害）"],
  ["P064", "陷阱大师战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[116, 0.10, true], [7, "eq_陷阱大师战靴", "放置陷阱"]], [[137, 0.0300, true]], [[4, 16, Stat.ATK, 0.5000, 0]], "主动放置陷阱（100%攻击力，触发后束缚1秒），最多同时存在3个，冷却8秒", "陷阱伤害增加3%", "陷阱触发时对周围造成50%攻击力伤害"],
  ["P065", "精英猎杀者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[105, 0.1500, true], [4, 1, Stat.ATK, 1.0000, 0]], [[105, 0.0300, true]], [[4, 1, Stat.HP, 0.1000, 0]], "对精英/Boss伤害+15%；击杀精英后，下次攻击+100%伤害", "对精英/Boss伤害增加3%", "击杀精英后，回复10%最大生命"],
  ["P066", "处决者印记", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[[105, 0.2500, true], [154, 0.3000, true]], [4, 1, Stat.HP, 0.0500, 0]], [[117, 0.0300, true]], [[4, 1, 113, 1.0, 0]], "对生命值低于30%的敌人伤害+25%；击杀低血量敌人时，回复5%最大生命", "处决伤害增加3%", "击杀低血量敌人时，重置一个技能冷却"],
  ["P067", "多重射击徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[2, "attack_bonus", 1.0, 0.0, {"extra_hits": {"chance": 0.1500, "hits": 1, "mult": 0.6000}}], [117, 0.10, true]], [[138, 0.0300, true]], [[4, 3, Stat.ATK, 0.2000, 0]], "远程攻击有15%概率额外发射1枚投射物（60%伤害）；额外投射物可触发弹射", "投射物伤害增加3%", "额外投射物命中同一目标时，伤害递增20%"],
  ["P068", "伤害储存护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[2, "energy_store", 1.0, 0.0, {"store_pct": 0.2000, "cap_pct": 1.0000}], [2, "energy_store", 1.0, 0.0, {"release": true}]], [[Stat.HP, 0.0300, true]], [[2, "energy_store", 1.0, 0.0, {"splash_pct": 0.5000}]], "受到伤害的20%储存为“能量”（最多储存100%最大生命）；下次攻击释放全部储存能量", "最大生命值增加3%", "释放储存能量时，对周围造成50%范围伤害"],
  ["P069", "裂空斩", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[7, "eq_裂空斩", "裂空斩"]], [[Stat.ATK, 0.0300, true]], [[8, {"multi_hit_at": 3, "multi_hit_bonus": 2.5000}]], "主动技能“裂空斩”——向前方释放剑气，对路径敌人造成180%攻击力伤害，冷却10秒", "攻击力增加3%", "剑气命中3个以上敌人时，伤害提升至250%"],
  ["P070", "烈焰风暴", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[7, "eq_烈焰风暴", "烈焰风暴"]], [[121, 0.0300, true]], [[2, "judgement", 1.0, 0.0, {"vuln": 0.2000}]], "主动技能“烈焰风暴”——在目标区域召唤火焰风暴，每秒造成60%法强火焰伤害，持续4秒，冷却18秒", "火焰伤害增加3%", "风暴内敌人受到火焰伤害+20%"],
  ["P071", "冰封领域", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[7, "eq_冰封领域", "冰封领域"]], [[122, 0.0300, true]], [[141, 0.1500, true]], "主动技能“冰封领域”——冻结周围4米敌人1.5秒，并造成120%法强冰霜伤害，冷却20秒", "冰霜伤害增加3%", "被冻结敌人受到伤害+15%"],
  ["P072", "雷霆万钧", "axe", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[7, "eq_雷霆万钧", "雷霆万钧"]], [[123, 0.0300, true]], [[102, 0.30, true]], "主动技能“雷霆万钧”——召唤雷电轰击目标区域，造成200%攻击力雷电伤害并麻痹1.5秒，冷却15秒", "雷电伤害增加3%", "麻痹时间延长至2秒"],
  ["P073", "暗影突袭", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 105.0, false]], [[7, "eq_暗影突袭", "暗影突袭"]], [[105, 0.0300, true]], [[113, 1.0, true]], "主动技能“暗影突袭”——瞬移至目标背后，造成200%攻击力暗影伤害并必定暴击，冷却12秒", "背刺伤害增加3%", "击杀目标后刷新冷却"],
  ["P074", "荆棘囚笼", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[7, "eq_荆棘囚笼", "荆棘囚笼"]], [[102, 0.0300, true]], [[2, "judgement", 1.0, 0.0, {"vuln": 0.2000}]], "主动技能“荆棘囚笼”——在目标区域召唤荆棘囚笼，束缚敌人2秒并每秒造成60%攻击力伤害，冷却18秒", "控制持续时间增加3%", "囚笼内敌人受到伤害+20%"],
  ["P075", "圣光审判", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[7, "eq_圣光审判", "圣光审判"]], [[100, 0.0300, true]], [[117, 0.5000, true]], "主动技能“圣光审判”——对周围敌人造成150%法强圣光伤害，同时治疗友方10%最大生命，冷却20秒", "治疗效果增加3%", "圣光伤害对亡灵额外+50%"],
  ["P076", "毒雾弹", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 105.0, false]], [[7, "eq_毒雾弹", "毒雾弹"]], [[126, 0.0300, true]], [[2, "zone_slow", 1.0, 0.0, {"slow_pct": 0.3000}]], "主动技能“毒雾弹”——投掷毒雾，在4米区域每秒造成50%攻击力毒素伤害，持续5秒，冷却15秒", "毒素伤害增加3%", "毒雾内敌人移速-30%"],
  ["P077", "旋风斩", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[7, "eq_旋风斩", "旋风斩"]], [[Stat.ASPD, 0.0200, true]], [[4, 22, Stat.SPD, 0.2500, 0]], "主动技能“旋风斩”——旋转攻击周围敌人，持续3秒，每0.5秒造成80%攻击力伤害，冷却12秒", "攻击速度增加2%", "旋风斩期间移速+25%"],
  ["P078", "穿透狙击", "crossbow", ["远程", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[7, "eq_穿透狙击", "穿透狙击"]], [[103, 0.0300, true]], [[4, 1, 117, 0.5000, 0]], "主动技能“穿透狙击”——蓄力射击，穿透所有敌人，造成250%攻击力伤害并无视40%护甲，冷却15秒", "护甲穿透增加3%", "击杀敌人后，下次狙击伤害+50%"],
  ["P079", "星辰坠落", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[7, "eq_星辰坠落", "星辰坠落"]], [[136, 0.0300, true]], [[117, 0.3000, true]], "主动技能“星辰坠落”——在目标区域召唤星辰坠落，造成200%法强范围伤害，冷却14秒", "范围伤害增加3%", "坠落点留下星尘区域（每秒30%法强，持续3秒）"],
  ["P080", "灵魂汲取", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[7, "eq_灵魂汲取", "灵魂汲取"]], [[100, 0.0300, true]], [[4, 3, Stat.HP, 0.05, 0]], "主动技能“灵魂汲取”——对周围敌人造成120%攻击力伤害，每命中一个敌人回复8%最大生命，冷却16秒", "生命偷取增加3%", "命中3个以上敌人时回复量翻倍"],
  ["P081", "风之屏障", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[7, "eq_风之屏障", "风之屏障"]], [[110, 0.0300, true]], [[104, 0.5000, true]], "主动技能“风之屏障”——3秒内格挡所有远程攻击并反弹50%伤害，冷却18秒", "格挡率增加3%", "格挡成功时对攻击者造成50%攻击力风元素伤害"],
  ["P082", "地裂术", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[7, "eq_地裂术", "地裂术"]], [[124, 0.0300, true]], [[2, "stun", 1.0, 0.8]], "主动技能“地裂术”——在目标区域引发地裂，造成150%法强土元素伤害并击飞敌人，冷却14秒", "土元素伤害增加3%", "地裂造成眩晕0.8秒"],
  ["P083", "爆裂箭雨", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[7, "eq_爆裂箭雨", "爆裂箭雨"]], [[138, 0.0300, true]], [[105, 0.1000, true]], "主动技能“爆裂箭雨”——向目标区域射出箭雨，每秒造成80%攻击力伤害，持续3秒，冷却16秒", "投射物伤害增加3%", "箭雨内敌人受到暴击率+10%"],
  ["P084", "血怒爆发", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[7, "eq_血怒爆发", "血怒爆发"]], [[Stat.ATK, 0.0300, true]], [[4, 1, Stat.HP, 0.5000, 0]], "主动技能“血怒爆发”——消耗15%当前生命，对周围造成300%攻击力伤害，冷却15秒", "攻击力增加3%", "击杀敌人回复消耗生命的50%"],
  ["P085", "元素洪流", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[7, "eq_元素洪流", "元素洪流"]], [[117, 0.0300, true]], [[2, "burn", 0.15, 3.0]], "主动技能“元素洪流”——释放随机元素洪流，对路径敌人造成180%法强对应元素伤害，冷却12秒", "元素伤害增加3%", "洪流附加对应元素状态"],
  ["P086", "暗影分身", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 105.0, false]], [[7, "eq_暗影分身", "暗影分身"]], [[116, 0.0300, true]], [[2, "summon_death_boom", 1.0, 0.0, {"mult": 0.6000, "by": "atk"}]], "主动技能“暗影分身”——召唤2个分身（继承30%攻击，持续8秒），冷却20秒", "召唤物伤害增加3%", "分身死亡时爆炸（60%攻击力）"],
  ["P087", "圣光护盾", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[7, "eq_圣光护盾", "圣光护盾"]], [[140, 0.0300, true]], [[4, 14, Stat.ATK, 1.0000, 0]], "主动技能“圣光护盾”——获得吸收20%最大生命的护盾，持续6秒，护盾存在时攻击+15%，冷却18秒", "护盾强度增加3%", "护盾被击破时对周围造成100%攻击力伤害"],
  ["P088", "时空加速", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_时空加速", "时空加速"]], [[Stat.ASPD, 0.0200, true]], [[4, 1, Stat.ATK, 0.0, 0]], "主动技能“时空加速”——自身攻速+40%、移速+30%，持续5秒，冷却20秒", "攻击速度增加2%", "加速期间击杀敌人延长2秒"],
  ["P089", "无畏冲锋", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_无畏冲锋", "无畏冲锋"]], [[Stat.HP, 0.0300, true]], [[4, 19, 146, 0.1500, 0, 0, {"seconds": 5.0000}]], "主动技能“无畏冲锋”——向前冲锋6米，击飞路径敌人并造成150%攻击力伤害，期间免疫伤害，冷却18秒", "最大生命值增加3%", "冲锋后获得5秒15%减伤"],
  ["P090", "闪现", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_闪现", "闪现"]], [[Stat.SPD, 0.0300, true]], [[4, 3, Stat.ATK, 0.4000, 0]], "主动技能“闪现”——瞬移6米，冷却12秒", "移动速度增加3%", "闪现后下次攻击+40%伤害"],
  ["P091", "生命之泉", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_生命之泉", "生命之泉"]], [[100, 0.0300, true]], [[4, 18, Stat.DEF, 0.1000, 0]], "主动技能“生命之泉”——在脚下生成治疗区域，每秒回复4%生命，持续6秒，冷却22秒", "治疗效果增加3%", "治疗区域同时提供10%减伤"],
  ["P092", "能量护盾", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_能量护盾", "能量护盾"]], [[140, 0.0300, true]], [[2, "control_immune", 1.0, 0.0]], "主动技能“能量护盾”——获得吸收25%最大生命的护盾，持续8秒，冷却22秒", "护盾强度增加3%", "护盾存在时免疫控制"],
  ["P093", "荆棘爆发", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_荆棘爆发", "荆棘爆发"]], [[104, 0.0300, true]], [[4, 24, Stat.DEF, 0.2000, 0]], "主动技能“荆棘爆发”——3秒内反弹100%伤害，冷却18秒", "反伤效果增加3%", "荆棘爆发期间受到伤害减少20%"],
  ["P094", "战吼", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_战吼", "战吼"]], [[Stat.DEF, 0.0300, true]], [[8, {"on_cast_buff": "taunt", "on_cast_seconds": 2}]], "主动技能“战吼”——周围敌人攻击力-25%、移速-20%，持续6秒，冷却24秒", "护甲增加3%", "战吼同时嘲讽敌人2秒"],
  ["P095", "烟雾弹", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_烟雾弹", "烟雾弹"]], [[111, 0.0300, true]], [[4, 27, Stat.CRT, 0.30, 0]], "主动技能“烟雾弹”——进入隐身3秒，隐身期间移速+30%，冷却18秒", "闪避率增加3%", "隐身期间下次攻击必定暴击"],
  ["P096", "召唤守卫", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_召唤守卫", "召唤守卫"]], [[116, 0.0300, true]], [[2, "summon_death_boom", 1.0, 0.0, {"mult": 0.8000, "by": "ap"}]], "主动技能“召唤守卫”——召唤一个守卫（继承60%生命，40%攻击，持续15秒），冷却28秒", "召唤物生命增加3%", "守卫死亡时爆炸（80%法强）"],
  ["P097", "反击姿态", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_反击姿态", "反击姿态"]], [[110, 0.0300, true]], [[4, 24, Stat.DEF, 0.3000, 0]], "主动技能“反击姿态”——3秒内格挡所有攻击并反弹80%伤害，冷却20秒", "格挡率增加3%", "反击姿态期间受到伤害减少30%"],
  ["P098", "疾风步", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_疾风步", "疾风步"]], [[Stat.SPD, 0.0300, true]], [[8, {"fire_path_seconds": 3.0, "fire_path_mult": 0.4000}]], "主动技能“疾风步”——移速+60%、闪避+30%，持续4秒，冷却16秒", "移动速度增加3%", "疾风步期间留下火焰路径（每秒40%攻击力）"],
  ["P099", "冰霜新星", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_冰霜新星", "冰霜新星"]], [[122, 0.0300, true]], [[141, 0.2000, true]], "主动技能“冰霜新星”——冻结周围3.5米敌人1.5秒，造成100%法强冰霜伤害，冷却18秒", "冰霜伤害增加3%", "被冻结敌人受到伤害+20%"],
  ["P100", "火焰吐息", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_火焰吐息", "火焰吐息"]], [[121, 0.0300, true]], [[8, {"fire_path_seconds": 3, "fire_path_mult": 0.4000}]], "主动技能“火焰吐息”——向前方扇形区域造成200%法强火焰伤害，冷却12秒", "火焰伤害增加3%", "火焰吐息留下燃烧地面（每秒40%法强，持续3秒）"],
  ["P101", "暗影步", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_暗影步", "暗影步"]], [[127, 0.0300, true]], [[4, 27, Stat.DEF, 0.0, 0]], "主动技能“暗影步”——进入隐身2秒，下次攻击+80%伤害并必定暴击，冷却14秒", "暗影伤害增加3%", "隐身期间免疫控制"],
  ["P102", "大地守护", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_大地守护", "大地守护"]], [[Stat.DEF, 0.0300, true]], [[4, 21, Stat.DEF, 0.0, 0]], "主动技能“大地守护”——获得30%减伤，持续5秒，冷却20秒", "护甲增加3%", "守护期间免疫击退"],
  ["P103", "风暴之眼", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_风暴之眼", "风暴之眼"]], [[125, 0.0300, true]], [[2, "judgement", 1.0, 0.0, {"vuln": 0.1500}]], "主动技能“风暴之眼”——在目标区域生成风暴，牵引敌人并每秒造成60%法强风元素伤害，持续3秒，冷却20秒", "风元素伤害增加3%", "风暴内敌人受到伤害+15%"],
  ["P104", "灵魂链接", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_灵魂链接", "灵魂链接"]], [[Stat.HP, 0.0300, true]], [[8, {"dr_pct": 0.1500}]], "主动技能“灵魂链接”——链接一名友方，分担其40%伤害，持续6秒，冷却25秒", "最大生命值增加3%", "链接期间自身获得15%减伤"],
  ["P105", "净化之光", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_净化之光", "净化之光"]], [[139, 0.0300, true]], [[112, 0.5000, true]], "主动技能“净化之光”——清除自身及周围友方所有负面状态，并回复10%最大生命，冷却30秒", "异常状态抗性增加3%", "净化后获得3秒霸体"],
  ["P106", "荆棘领域", "", [], EquipmentDefs.Slot.LEGS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[7, "eq_荆棘领域", "荆棘领域"]], [[104, 0.0300, true]], [[2, "zone_slow", 1.0, 0.0, {"slow_pct": 0.3000}]], "主动技能“荆棘领域”——3秒内周围敌人每秒受到80%攻击力伤害，冷却22秒", "反伤效果增加3%", "领域内敌人移速-30%"],
  ["P107", "元素爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_元素爆发", "元素爆发"]], [[117, 0.0300, true]], [[2, "burn", 0.15, 3.0]], "主动技能“元素爆发”——对周围造成随机元素爆炸，伤害200%法强，冷却14秒", "元素伤害增加3%", "爆炸附加对应元素状态"],
  ["P108", "召唤元素灵", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_召唤元素灵", "召唤元素灵"]], [[116, 0.0300, true]], [[2, "burn", 0.30, 3.0]], "主动技能“召唤元素灵”——召唤一个元素灵体（继承50%法强，持续15秒），冷却28秒", "召唤物伤害增加3%", "元素灵体攻击附带元素状态"],
  ["P109", "护盾术", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_护盾术", "护盾术"]], [[140, 0.0300, true]], [[4, 15, Stat.ATK, 0.1500, 0]], "主动技能“护盾术”——获得吸收20%最大生命的护盾，持续8秒，冷却22秒", "护盾强度增加3%", "护盾存在时攻击+15%"],
  ["P110", "传送", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_传送", "传送"]], [[Stat.SPD, 0.0300, true]], [[4, 4, 111, 0.2000, 0, 0, {"seconds": 3.0000}]], "主动技能“传送”——瞬移至8米内指定位置，冷却18秒", "移动速度增加3%", "传送后获得3秒闪避+20%"],
  ["P111", "治愈术", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_治愈术", "治愈术"]], [[100, 0.0300, true]], [[8, {"on_cast_dispel": 1}]], "主动技能“治愈术”——治疗自身25%最大生命，冷却25秒", "治疗效果增加3%", "治愈术同时清除一个负面状态"],
  ["P112", "猎人标记", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_猎人标记", "猎人标记"]], [[Stat.CRT, 0.0200, true]], [[2, "burn", 0.30, 3.0]], "主动技能“猎人标记”——标记一个敌人，使其受到伤害+25%，持续10秒，冷却18秒", "暴击率增加2%", "标记目标死亡时，标记扩散至周围敌人"],
  ["P113", "资源爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_资源爆发", "资源爆发"]], [[119, 0.0300, true]], [[117, 0.2500, true]], "主动技能“资源爆发”——立即回复60%职业资源，冷却28秒", "资源上限增加3%", "资源爆发后下次技能伤害+25%"],
  ["P114", "时间减缓", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_时间减缓", "时间减缓"]], [[Stat.CDR, 0.0200, true]], [[4, 23, Stat.ASPD, 0.2500, 0]], "主动技能“时间减缓”——周围敌人移速-50%、攻速-40%，持续4秒，冷却25秒", "冷却缩减增加2%", "时间减缓期间自身攻速+25%"],
  ["P115", "荆棘领域", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_荆棘领域", "荆棘领域"]], [[104, 0.0300, true]], [[2, "zone_slow", 1.0, 0.0, {"slow_pct": 0.2000}]], "主动技能“荆棘领域”——3秒内周围敌人受到反弹伤害，冷却20秒", "反伤效果增加3%", "领域内敌人移速-20%"],
  ["P116", "灵魂爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_灵魂爆发", "灵魂爆发"]], [[119, 0.0300, true]], [[4, 1, Stat.HP, 0.0500, 0]], "主动技能“灵魂爆发”——消耗所有灵魂层数，每层造成40%攻击力伤害（最多10层），冷却30秒", "灵魂获取增加3%", "灵魂爆发击杀敌人时，回复5%最大生命"],
  ["P117", "星辰护盾", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_星辰护盾", "星辰护盾"]], [[111, 0.0200, true]], [[104, 0.5000, true]], "主动技能“星辰护盾”——获得吸收15%最大生命的护盾，护盾存在时闪避+20%，冷却20秒", "闪避率增加2%", "闪避成功时对攻击者造成50%攻击力星辰伤害"],
  ["P118", "混沌之门", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[7, "eq_混沌之门", "混沌之门"]], [[[Stat.HP, 0.0200, true], [Stat.ATK, 0.0200, true], [Stat.DEF, 0.0200, true], [Stat.SPD, 0.0200, true], [Stat.ASPD, 0.0200, true], [Stat.AP, 0.0200, true], [Stat.CRT, 0.0200, true], [Stat.CRD, 0.0200, true]]], [[8, {"chaos_times": 2, "chaos_scale": 0.5000}]], "主动技能“混沌之门”——随机释放以下之一：全屏伤害/全屏治疗/全屏护盾/全屏减速，冷却30秒", "全属性增加2%", "混沌之门触发时，额外释放一次随机效果（50%效果）"],
  ["O000", "终末裁决", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[4, 6, Stat.CRD,  0.0500,  8,  0], [4, 5, Stat.ATK, 1.0000, 0, 0, {"burst": "prophecy", "crit_mult": 1.5, "spread_count": 0, "spread_layers": 0}]], [[Stat.CRD, 0.0500, true]], [[2, "soul_persist", 1.0, 0.0]], "暴击叠加1层“裁决”（最多8层），每层+5%暴击伤害；8层时下一次攻击触发“终末裁决”——必定暴击、造成350%攻击力伤害，击杀目标后刷新所有技能冷却", "暴击伤害增加5%", "终末裁决击杀敌人时，裁决层数不清空并保留4层"],
  ["O001", "血海狂潮", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 364.0, false]], [[118, 3.0000, true], [[4, 11, Stat.ATK, 0.4000, 0, 0.5000], [4, 11, Stat.ASPD, 0.3000, 0, 0.5000], [4, 11, 100, 0.2500, 0, 0.5000]]], [[100, 0.0500, true]], [[4, 21, Stat.DEF, 0.0, 0]], "攻击消耗5%当前生命，额外造成消耗生命300%的伤害；生命低于50%时进入“血海狂暴”——攻击+40%、攻速+30%、吸血+25%，击杀回复20%最大生命", "生命偷取增加5%", "血海狂暴期间免疫控制，且每秒自动消耗1%生命转化为5%攻击力"],
  ["O002", "元素终焉", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 295.8, false]], [[2, "elem_rotate", 1.0, 0.0, {"rotate": true}], [117, 0.1500, true], [2, "elem_finale", 1.0, 0.0, {"mult": 6.0000, "clear": true}]], [[117, 0.0500, true]], [[2, "elem_finale_refresh", 1.0, 0.0, {"refresh": true}]], "技能自动轮转六元素；每种元素对敌人施加独立状态（灼烧/冰冻/麻痹/中毒/眩晕/牵引），每种状态使目标受到对应元素伤害+15%；六种状态同时存在时触发“元素终焉”——造成600%法强全元素伤害并清空所有状态", "元素伤害增加5%", "元素终焉触发后，六种状态重新施加且持续时间刷新"],
  ["O003", "影狱双刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 170.6, false]], [[116, 0.10, true], [Stat.CRD, 0.30, true], [Stat.CRD, 0.30, true]], [[105, 0.0500, true]], [[4, 17, 117, 0.3000, 0]], "背刺必定暴击并召唤1个影分身（继承40%攻击，持续6秒，最多3个）；影分身攻击视为背刺，可触发背刺效果；背刺击杀敌人时刷新所有分身持续时间", "背刺伤害增加5%", "影分身存在时，自身背刺伤害+30%"],
  ["O004", "猎神长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[2, "target_vuln", 1.0, 0.0, {"pct": 0.0500, "per_stack": true, "max_stacks": 8}], [Stat.CDR, 0.10, true], [7, "eq_猎神长弓", "猎神歼灭"]], [[135, 0.0500, true]], [[Stat.CRT, 0.30, true]], "攻击施加“猎神标记”（最多8层，持续10秒），每层+5%受到伤害；主动技能“猎神歼灭”——引爆所有标记，每层造成120%攻击力伤害，若击杀目标则标记扩散至全屏敌人；冷却18秒", "远程伤害增加5%", "歼灭射击对5层以上标记目标必定暴击"],
  ["O005", "不朽壁垒", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[[4, 2, 146, 0.0300, 15], [4, 2, 104, 0.0200, 15]], [2, "cheat_death", 1.0, 0.0, {"heal_pct": 0.3000, "boom_pct": 0.8000, "cooldown": 90}]], [[Stat.DEF, 0.0500, true]], [], "受到伤害叠加1层“不朽”（最多15层），每层+3%减伤、+2%反伤；满层时受到致命伤害触发“不朽壁垒”——免疫该次伤害、消耗所有层数、对周围造成（层数×80%）攻击力伤害，并回复30%最大生命（冷却90秒）", "护甲增加5%", "不朽壁垒触发后，10秒内减伤+30%且免疫控制"],
  ["O006", "预言者王冠", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[4, 6, Stat.CRD,  0.0600,  6,  0], [4, 5, Stat.CRD, 1.0, 0, 0, {"burst": "prophecy", "crit_mult": 3.0000, "spread_count": 2, "spread_layers": 3, "spread_radius": 5.0, "spread_stat": 10, "spread_value": 0.06, "spread_duration": 8.0, "spread_max": 6}]], [[Stat.CRT, 0.0300, true]], [[2, "prophecy_self", 1.0, 0.0, {"self_crt": 0.2000, "self_crt_seconds": 3}]], "暴击叠加1层“预言”（最多6层），每层+6%暴击伤害；6层时下一次攻击必定暴击并造成300%伤害，同时将预言传播至周围2名敌人（各3层）", "暴击率增加3%", "预言传播时，自身获得3秒+20%暴击率"],
  ["O007", "踏虚神靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[2, "afterimage", 1.0, 0.0, {"life": 5, "max_count": 4, "explode_mult": 1.5000, "refresh_cd": 3.0, "heal_pct": 0.0}], [2, "afterimage", 1.0, 0.0, {"explode_mult": 1.5000}], [2, "afterimage", 1.0, 0.0]], [[Stat.SPD, 0.0500, true]], [[2, "afterimage", 1.0, 0.0, {"heal_pct": 0.0300}]], "冲刺留下残影（继承50%攻击，持续5秒，最多4个）；残影存在时再次冲刺可引爆所有残影，每个造成150%攻击力伤害；引爆后冲刺冷却立即刷新（每3秒最多触发1次）", "移动速度增加5%", "引爆残影时，每个残影回复3%最大生命"],
  ["O008", "元素之心·终焉", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[106, 0.2000, true], [4, 36, 117, 0.2500, 5], [4, 5, 117, 4.0000, 0]], [[106, 0.0400, true]], [[2, "elem_finale_refresh", 1.0, 0.0, {"refresh": true}]], "所有元素抗性+20%；受到元素伤害时获得对应元素伤害+25%（持续8秒，可叠5层）；5层时触发“元素终焉”——对周围造成400%法强全元素伤害，并重置所有抗性层数", "元素抗性增加4%", "元素终焉触发后，获得对应元素护盾（吸收15%最大生命）"],
  ["O009", "灵魂王座", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[[4, 1, Stat.ATK, 0.0300, 20], [4, 1, 145, 0.0200, 20]], [8, {"ultimate_soul_per_stack": 0.3000}], [4, 1, Stat.HP, 0.10, 0]], [[119, 0.0400, true]], [[2, "soul_refund", 1.0, 0.0]], "击杀敌人获得1层“灵魂”（最多20层），每层+3%伤害、+2%资源回复；满层时释放终极技能消耗所有灵魂，每层额外造成30%伤害；击杀敌人时若灵魂已满，则改为回复10%最大生命", "资源上限增加4%", "终极技能消耗灵魂后，返还50%层数"],
  ["O010", "处决者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[4, 11, 105, 0.3000, 0, 0.3000], [4, 1, Stat.HP, 0.2000, 0]], [[Stat.ATK, 0.0500, true]], [[154, 0.4000, true]], "攻击生命值低于30%的敌人时，直接处决（造成9999点真实伤害）；处决成功后回复20%最大生命", "攻击力增加5%", "处决阈值提升至40%"],
  ["O011", "血怒", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 364.0, false]], [[[4, 11, Stat.ATK, 0.6000, 0, 0.5000], [4, 11, Stat.ASPD, 0.4000, 0, 0.5000], [4, 11, 100, 0.3000, 0, 0.5000]]], [[100, 0.0500, true]], [[4, 11, 146, 0.3000, 0, 0.3000]], "生命低于50%时，攻击力+60%、攻速+40%、吸血+30%", "生命偷取增加5%", "生命低于30%时，额外获得30%减伤"],
  ["O012", "元素洪流", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 295.8, false]], [[4, 18, 117, 0.8000, 0]], [[Stat.AP, 0.0500, true]], [[2, "atk_up_self", 1.0, 0.0]], "施放技能后，下一次技能不消耗资源且伤害+80%（每5秒最多触发1次）", "法术强度增加5%", "触发时额外释放一次该技能（50%伤害）"],
  ["O013", "猎杀者", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[105, 0.3000, true], [4, 1, Stat.ATK, 1.5000, 0]], [[135, 0.0500, true]], [[113, 1.0, true]], "远程攻击对满血敌人必定暴击；击杀敌人后，下次攻击+150%伤害", "远程伤害增加5%", "击杀敌人后刷新冲刺冷却"],
  ["O014", "不朽者", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[2, "cheat_death", 1.0, 0.0, {"heal_pct": 0.5000, "boom_pct": 0.0, "cooldown": 120}]], [[Stat.HP, 0.0500, true]], [[111, 0.5000, true]], "受到致命伤害时免疫该次伤害并回复50%最大生命（冷却120秒）", "最大生命值增加5%", "触发后获得5秒无敌"],
  ["O015", "荆棘之王", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[104, 0.5000, true], [104, 0.20, true]], [[Stat.DEF, 0.0500, true]], [[2, "stun", 0.2000, 1.0, {"trigger": 40}]], "反弹50%所有受到伤害；生命低于50%时反弹效果翻倍", "护甲增加5%", "反弹伤害有20%概率眩晕攻击者1秒"],
  ["O016", "疾风之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[Stat.CDR, 0.5000, true], [4, 4, Stat.SPD, 0.5000, 0, 0, {"seconds": 3.0000}]], [[Stat.SPD, 0.0500, true]], [[117, 1.0000, true]], "冲刺冷却减少50%；冲刺后获得3秒+50%移速、+30%闪避", "移动速度增加5%", "冲刺路径留下火焰（每秒100%攻击力，持续3秒）"],
  ["O017", "暴君之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[[Stat.CRT, 0.2500, true], [Stat.CRD, 0.5000, true]], [4, 6, Stat.HP, 0.0300, 0]], [[Stat.CRT, 0.0300, true]], [[148, 0.0500, true]], "暴击率+25%、暴击伤害+50%；暴击时回复3%最大生命", "暴击率增加3%", "暴击时5%概率刷新一个技能冷却"],
  ["O018", "元素之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[117, 0.4000, true], [2, "burn", 0.15, 3.0]], [[117, 0.0500, true]], [[102, 1.0, true]], "所有元素伤害+40%；攻击附带随机元素状态（灼烧/冰冻/麻痹/中毒）", "元素伤害增加5%", "元素状态持续时间翻倍"],
  ["O019", "灵魂容器", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 1, Stat.HP, 0.1500, 0], [106, 0.3000, true]], [[119, 0.0500, true]], [[4, 1, Stat.HP, 0.2000, 0]], "击杀敌人回复15%最大生命和20%职业资源；溢出回复转化为护盾（最多30%最大生命）", "资源上限增加5%", "击杀精英/Boss额外回复20%最大生命"],
  ["O020", "裂地巨斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 364.0, false]], [[7, "eq_裂地巨斧", "裂地斩"]], [[Stat.ATK, 0.0500, true]], [[8, {"multi_hit_at": 3, "multi_hit_bonus": 7.0000}]], "主动技能“裂地斩”——向前方劈砍，对路径所有敌人造成500%攻击力伤害并击飞，冷却20秒", "攻击力增加5%", "裂地斩命中3个以上敌人时，伤害提升至700%"],
  ["O021", "流星法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 295.8, false]], [[7, "eq_流星法杖", "流星火雨"]], [[Stat.AP, 0.0500, true]], [[8, {"fire_path_seconds": 5, "fire_path_mult": 0.8000}]], "主动技能“流星火雨”——在目标区域召唤流星，造成400%法强火焰伤害，冷却25秒", "法术强度增加5%", "流星火雨留下燃烧地面（每秒80%法强，持续5秒）"],
  ["O022", "影袭匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 170.6, false]], [[7, "eq_影袭匕首", "影袭"]], [[105, 0.0600, true]], [[113, 1.0, true]], "主动技能“影袭”——瞬移至目标背后，造成300%攻击力伤害并必定暴击，冷却15秒", "背刺伤害增加6%", "影袭击杀目标后刷新冷却"],
  ["O023", "穿透长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[7, "eq_穿透长弓", "穿透射击"]], [[135, 0.0500, true]], [[8, {"multi_hit_at": 3, "multi_hit_bonus": 5.0000}]], "主动技能“穿透射击”——射出一支穿透箭，对路径所有敌人造成350%攻击力伤害并无视50%护甲，冷却18秒", "远程伤害增加5%", "穿透射击命中3个以上敌人时，伤害提升至500%"],
  ["O024", "钢铁之心", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[7, "eq_钢铁之心", "钢铁之躯"]], [[Stat.HP, 0.0600, true]], [[4, 21, Stat.DEF, 0.0, 0]], "主动技能“钢铁之躯”——获得50%减伤，持续6秒，冷却45秒", "最大生命值增加6%", "钢铁之躯期间免疫控制"],
  ["O025", "战吼头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[7, "eq_战吼头盔", "战吼"]], [[Stat.DEF, 0.0500, true]], [[8, {"on_cast_buff": "fatigue", "on_cast_seconds": 6, "on_cast_params": {"atk_down": 0.3000}}]], "主动技能“战吼”——周围敌人恐惧3秒，并受到200%攻击力伤害，冷却40秒", "护甲增加5%", "战吼同时降低敌人30%攻击力，持续6秒"],
  ["O026", "疾风战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[7, "eq_疾风战靴", "疾风冲刺"]], [[Stat.SPD, 0.0500, true]], [[4, 19, Stat.SPD, 0.5000, 0, 0, {"seconds": 3.0000}]], "主动技能“疾风冲刺”——向前冲刺，路径敌人受到200%攻击力伤害并击退，冷却12秒", "移动速度增加5%", "冲刺后获得3秒+50%移速"],
  ["O027", "元素爆发戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[7, "eq_元素爆发戒指", "元素爆发"]], [[117, 0.0500, true]], [[2, "burn", 0.15, 3.0]], "主动技能“元素爆发”——对周围造成300%法强随机元素伤害，冷却20秒", "元素伤害增加5%", "元素爆发附加对应元素状态（灼烧/冰冻/麻痹/中毒）"],
  ["O028", "治疗之泉项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[7, "eq_治疗之泉项链", "治疗之泉"]], [[100, 0.0600, true]], [[2, "__cleanse_all__", 1.0, 0.0]], "主动技能“治疗之泉”——立即回复40%最大生命，并在5秒内每秒回复5%最大生命，冷却60秒", "治疗效果增加6%", "治疗之泉同时清除所有负面状态"],
  ["O029", "召唤守护者护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[7, "eq_召唤守护者护符", "召唤守护者"]], [[116, 0.0500, true]], [[2, "summon_death_boom", 1.0, 0.0, {"mult": 3.0000, "by": "ap"}]], "主动技能“召唤守护者”——召唤一个守护者（继承100%最大生命、60%攻击力，持续20秒），冷却60秒", "召唤物生命增加5%", "守护者死亡时爆炸，对周围造成300%法强伤害"],
  ["O030", "弹射之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[117, 0.7000, true]], [[Stat.ATK, 0.0500, true]], [[117, 0.1500, true]], "攻击会弹射到最近的另一个敌人，造成70%伤害", "攻击力+5%", "弹射次数+1"],
  ["O031", "连击之刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 170.6, false]], [[4, 7, Stat.ATK,  0.1500,  5,  0]], [[Stat.ASPD, 0.0300, true]], [[4, 5, Stat.ATK, 0.50, 0]], "连续攻击同一目标时，每次伤害提高15%，最多5层", "攻击速度+3%", "满层时额外攻击一次"],
  ["O032", "金币猎手", "axe", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[Stat.ATK, 1.00, true], [107, 0.1000, true]], [[107, 0.0500, true]], [[107, 0.1000, true]], "攻击消耗10金币，但伤害翻倍；金币不足时无法触发", "金币获取+5%", "消耗金币减半"],
  ["O033", "灵魂收割者", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 364.0, false]], [[2, "summon_soul", 1.0, 0.0]], [[116, 0.0500, true]], [[2, "summon_death_boom", 1.0, 0.0, {"mult": 0.5, "by": "ap"}]], "击杀敌人召唤一个灵魂（继承30%攻击，持续10秒，最多3个）", "召唤物伤害+5%", "灵魂死亡时爆炸"],
  ["O034", "双重打击", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[2, "attack_bonus", 1.0, 0.0, {"extra_hits": {"chance": 0.2500, "hits": 1, "mult": 0.5000}}]], [[Stat.ATK, 0.0500, true]], [[2, "attack_bonus", 1.0, 0.0, {"extra_hits": {"chance": 0.4000, "hits": 1, "mult": 0.5000}}]], "攻击有25%概率追加一次50%伤害的攻击", "攻击力+5%", "追加攻击概率提升至40%"],
  ["O035", "狂战士之怒", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 364.0, false]], [[8, {"basic_attack_aoe": true, "basic_attack_aoe_mult": 1.5000, "basic_attack_aoe_threshold": 0.5000}]], [[100, 0.0500, true]], [[8, {"basic_attack_expand_radius": 3.5000}]], "生命低于50%时，普通攻击变为范围攻击，造成150%伤害", "生命偷取+5%", "范围扩大"],
  ["O036", "幸运之刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 170.6, false]], [[2, "attack_bonus", 1.0, 0.0, {"double_chance": 0.1500}]], [[Stat.CRT, 0.0300, true]], [[2, "attack_bonus", 1.0, 0.0, {"double_chance": 0.2500}]], "攻击有15%概率造成双倍伤害", "暴击率+3%", "概率提升至25%"],
  ["O037", "生命百分比之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[118, 0.0500, true]], [[Stat.ATK, 0.0500, true]], [[118, 0.0800, true]], "攻击附加当前生命值5%的额外伤害", "攻击力+5%", "附加比例提升至8%"],
  ["O038", "斩首者", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 364.0, false]], [[[105, 0.6000, true], [154, 100.00, true]]], [[Stat.ATK, 0.0500, true]], [[[105, 1.0000, true], [154, 100.00, true]]], "对满血敌人造成额外60%伤害", "攻击力+5%", "对满血敌人伤害提升至100%"],
  ["O039", "终结者", "axe", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[[105, 0.6000, true], [154, 0.3000, true]]], [[Stat.ATK, 0.0500, true]], [[154, 0.4000, true]], "对生命低于30%的敌人造成额外60%伤害", "攻击力+5%", "阈值提升至40%"],
  ["O040", "血怒之刃", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 364.0, false]], [[2, "state_scaled", 1.0, 0.0, {"per_hp_loss_pct": 10, "per_hp_atk": 0.0800}]], [[100, 0.0500, true]], [[2, "state_scaled", 1.0, 0.0, {"per_hp_loss_pct": 10, "per_hp_atk": 0.1200}]], "每损失10%生命，攻击力提高8%", "生命偷取+5%", "每损失10%生命攻击力提高12%"],
  ["O041", "吸血狂徒", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 364.0, false]], [[100, 0.3000, true]], [[100, 0.0500, true]], [[100, 0.5000, true]], "攻击消耗5%生命，但吸血提高30%", "生命偷取+5%", "吸血提高至50%"],
  ["O042", "元素爆裂之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[117, 2.5000, true]], [[117, 0.0500, true]], [[8, {"radius_mult": 1.2000}]], "攻击有15%概率触发随机元素爆炸，造成250%法强伤害", "元素伤害+5%", "爆炸范围扩大"],
  ["O043", "混沌之触", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 295.8, false]], [[2, "burn", 0.15, 3.0]], [[117, 0.0500, true]], [[2, "attack_bonus", 1.0, 0.0, {"double_chance": 0.3500}]], "攻击有20%概率施加随机异常状态（灼烧/冰冻/中毒/麻痹），持续3秒", "元素伤害+5%", "概率提升至35%"],
  ["O044", "闪避新星", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[117, 2.0000, true]], [[Stat.SPD, 0.0500, true]], [[8, {"radius_mult": 1.3000}]], "闪避成功后释放一圈火焰新星，造成200%攻击力伤害", "移动速度+5%", "新星范围扩大30%"],
  ["O045", "格挡反击者", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 227.5, false]], [[4, 9, 117, 1.0000, 0]], [[110, 0.0300, true]], [[117, 0.5000, true]], "格挡成功后，下次攻击必定暴击且伤害+100%", "格挡率+3%", "反击伤害+50%"],
  ["O046", "火焰行者", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 295.8, false]], [[117, 0.8000, true]], [[121, 0.0500, true]], [[8, {"radius_mult": 1.2000}]], "释放技能后在地面留下火焰，每秒造成80%法强伤害，持续4秒", "火焰伤害+5%", "火焰范围扩大"],
  ["O047", "闪电之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[117, 1.0000, true]], [[Stat.SPD, 0.0500, true]], [[8, {"duration_mult": 2.0}]], "移动时留下闪电轨迹，对经过的敌人造成100%攻击力伤害", "移动速度+5%", "轨迹持续时间翻倍"],
  ["O048", "元素附魔师", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 295.8, false]], [[3, "fire", 0.50]], [[117, 0.0500, true]], [[8, {"duration_mult": 2.0}]], "受到元素伤害后，武器获得该元素附魔，持续10秒（攻击附加50%该元素伤害）", "元素伤害+5%", "附魔持续时间翻倍"],
  ["O049", "冲击波之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[117, 2.0000, true]], [[Stat.SPD, 0.0500, true]], [[117, 1.0000, true]], "每移动50米，释放一次冲击波，造成200%攻击力伤害", "移动速度+5%", "冲击波伤害+100%"],
  ["O050", "不动堡垒", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[2, "stationary_buff", 1.0, 0.0, {"stationary_seconds": 2, "dr_pct": 0.0, "reflect_pct": 0.0, "shield_pct": 0.3000}]], [[Stat.DEF, 0.0500, true]], [[140, 0.5000, true]], "站立不动2秒后获得一个吸收30%最大生命的护盾，移动后消失", "护甲+5%", "护盾值+50%"],
  ["O051", "冷却之眼", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[8, {"crit_reduce_cooldown_seconds": 1}]], [[Stat.CDR, 0.0300, true]], [[Stat.CDR, 0.20, true]], "暴击时减少所有技能冷却1秒", "冷却缩减+3%", "减少冷却提升至2秒"],
  ["O052", "冲刺大师", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[113, 1.0, true]], [[Stat.SPD, 0.0500, true]], [[4, 3, Stat.ATK, 0.5000, 0]], "击杀敌人后立即重置冲刺冷却", "移动速度+5%", "冲刺后下次攻击+50%"],
  ["O053", "反击之甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[4, 2, Stat.ATK, 1.5000, 0]], [[Stat.DEF, 0.0500, true]], [[117, 1.0000, true]], "受到伤害后，立即对周围造成一次150%攻击力的反击伤害", "护甲+5%", "反击伤害+100%"],
  ["O054", "荆棘反弹", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 227.5, false]], [[4, 9, 104, 2.0000, 0]], [[110, 0.0300, true]], [[104, 1.0000, true]], "格挡成功后，反弹200%伤害给攻击者", "格挡率+3%", "反弹伤害+100%"],
  ["O055", "濒死新星", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[2, "autocast_nova", 1.0, 0.0, {"threshold": 0.3000, "mult": 3.0000, "cooldown": 60}]], [[Stat.HP, 0.0500, true]], [[117, 1.0000, true]], "生命低于30%时自动释放新星，造成300%攻击力伤害，冷却60秒", "最大生命+5%", "新星伤害+100%"],
  ["O056", "伤害转盾", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[[151, 0.5000, true], [153, 0.3000, true]]], [[Stat.DEF, 0.0500, true]], [[[151, 0.7000, true], [153, 0.3000, true]]], "受到伤害的50%转化为护盾，最多吸收30%最大生命", "护甲+5%", "转化比例提升至70%"],
  ["O057", "护盾爆裂", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[4, 14, Stat.ATK, 3.0000, 0]], [[140, 0.0500, true]], [[4, 14, Stat.ATK, 5.0000, 0]], "护盾被击破时，对周围造成300%攻击力伤害", "护盾强度+5%", "伤害提升至500%"],
  ["O058", "猎杀者勋章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 1, Stat.ATK, 0.15, 0]], [[[Stat.HP, 0.0300, true], [Stat.ATK, 0.0300, true], [Stat.DEF, 0.0300, true], [Stat.SPD, 0.0300, true], [Stat.ASPD, 0.0300, true], [Stat.AP, 0.0300, true], [Stat.CRT, 0.0300, true], [Stat.CRD, 0.0300, true]]], [[119, 0.5000, true]], "每击杀10个敌人，获得一个随机增益（攻击/攻速/移速/护盾），持续15秒", "全属性+3%", "所需击杀数减半"],
  ["O059", "召唤领主", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 17, Stat.ATK, 0.2500, 0]], [[116, 0.0500, true]], [[120, 1, false]], "召唤物存在时，自身攻击力提高25%", "召唤物伤害+5%", "召唤物数量+1"],
  ["O060", "资源爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 3, Stat.ATK, 1.5000, 0]], [[119, 0.0500, true]], [[119, 0.2000, true]], "消耗30点职业资源，使下次攻击伤害提高150%", "资源上限+5%", "消耗降低至20点"],
  ["O061", "技能强化者", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 295.8, false]], [[2, "atk_up_self", 1.0, 0.0]], [[Stat.AP, 0.0500, true]], [[Stat.ATK, 1.5000, true]], "使用技能后，下次攻击伤害提高100%", "法术强度+5%", "强化效果提升至150%"],
  ["O062", "闪避强化者", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[4, 4, Stat.ATK, 1.0000, 0]], [[111, 0.0300, true]], [[Stat.ATK, 1.5000, true]], "闪避成功后，下次攻击伤害提高100%", "闪避率+3%", "强化效果提升至150%"],
  ["O063", "不死之身", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 1, 111, 0.5000, 0, 0, {"seconds": 2.0000}]], [[Stat.HP, 0.0500, true]], [[102, 0.30, true]], "击杀敌人后获得2秒无敌", "最大生命+5%", "无敌时间延长至3秒"],
  ["O064", "贪婪之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[Stat.ATK, 0.0300, true]], [[107, 0.0500, true]], [[Stat.ATK, 0.0500, true]], "每持有100金币，攻击力提高3%", "金币获取+5%", "每100金币攻击力提高5%"],
  ["O065", "传奇共鸣", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[[Stat.HP, 0.0800, true], [Stat.ATK, 0.0800, true], [Stat.DEF, 0.0800, true], [Stat.SPD, 0.0800, true], [Stat.ASPD, 0.0800, true], [Stat.AP, 0.0800, true], [Stat.CRT, 0.0800, true], [Stat.CRD, 0.0800, true]]], [[[Stat.HP, 0.0300, true], [Stat.ATK, 0.0300, true], [Stat.DEF, 0.0300, true], [Stat.SPD, 0.0300, true], [Stat.ASPD, 0.0300, true], [Stat.AP, 0.0300, true], [Stat.CRT, 0.0300, true], [Stat.CRD, 0.0300, true]]], [[[Stat.HP, 0.1200, true], [Stat.ATK, 0.1200, true], [Stat.DEF, 0.1200, true], [Stat.SPD, 0.1200, true], [Stat.ASPD, 0.1200, true], [Stat.AP, 0.1200, true], [Stat.CRT, 0.1200, true], [Stat.CRD, 0.1200, true]]], "每装备一件传奇装备，全属性提高8%", "全属性+3%", "每件传奇装备全属性提高12%"],
  ["O066", "钥匙守护者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[[Stat.HP, 0.0500, true], [Stat.ATK, 0.0500, true], [Stat.DEF, 0.0500, true], [Stat.SPD, 0.0500, true], [Stat.ASPD, 0.0500, true], [Stat.AP, 0.0500, true], [Stat.CRT, 0.0500, true], [Stat.CRD, 0.0500, true]]], [[109, 0.0300, true]], [[[Stat.HP, 0.0800, true], [Stat.ATK, 0.0800, true], [Stat.DEF, 0.0800, true], [Stat.SPD, 0.0800, true], [Stat.ASPD, 0.0800, true], [Stat.AP, 0.0800, true], [Stat.CRT, 0.0800, true], [Stat.CRD, 0.0800, true]]], "每持有一片钥匙碎片，全属性提高5%", "钥匙碎片掉落+3%", "每片钥匙碎片全属性提高8%"],
  ["O067", "记忆转化", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[Stat.ATK, 0.0200, true]], [[119, 0.0500, true]], [[Stat.ATK, 0.0300, true]], "每点记忆残渣，攻击力提高2%", "记忆残渣获取+5%", "每点记忆残渣攻击力提高3%"],
  ["O068", "金币替身", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[4, 2, 107, 0.10, 0]], [[107, 0.0500, true]], [[107, 0.2000, true]], "受到伤害时，消耗金币代替生命，每点伤害消耗3金币", "金币获取+5%", "消耗金币降低至2"],
  ["O069", "护盾强化", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 15, Stat.ATK, 0.4000, 0]], [[140, 0.0500, true]], [[4, 15, Stat.ATK, 0.6000, 0]], "护盾存在时，攻击力提高40%", "护盾强度+5%", "攻击力提高至60%"],
]
