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
static func _apply_affixes(t: EquipmentTemplate, base: Array, devour: Array, fusion: Array,
		own: Array = [], trigger: int = 0, dur: float = 0.0, stack: int = 0) -> void:
	t.base_affix = _make_affix(base)
	t.devour_affix = _make_affix(devour)
	t.fusion_affix = _make_affix(fusion)
	# 自有词条：策划表才有（白装克隆表没有），为空时留 null
	if not own.is_empty():
		t.own_affix = _make_affix(own)
		# **触发条件**（装备参考2 规格）：规格里大量自有词条不是常驻，
		# 而是「击杀时 / 受击时 / 命中时 / 满层时」生效。
		# 这一层此前完全没有承载——所有机制都被当成常驻数值。
		t.own_affix.trigger = trigger
		t.own_affix.duration = dur
		t.own_affix.stack_max = stack
	t.trigger_affixes = _generate_trigger_affixes(t.rarity, str(t.id))


## 构建词条数据
static func _make_affix(affix: Array) -> AffixData:
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
		# 注意参数顺序：_apply_affixes(base, devour, fusion, own)
		_apply_affixes(t, row[6], row[8], row[9], row[7], row[10], row[11], row[12])


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
  ["G000", "被腐蚀的长剑", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 56.0, false], [Stat.ATK, 0.01, true], [Stat.ATK, 0.005, true], [Stat.ATK, 0.1, true], 1, 0, 0],
  ["G001", "饮血重剑", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 89.6, false], [100, 0.1, true], [100, 0.005, true], [Stat.HP, 0.05, true], 0, 0, 0],
  ["G002", "烈焰法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 0.5, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["G003", "寒霜法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 0.5, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["G004", "雷霆法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 0.5, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["G005", "剧毒法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 0.5, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["G006", "大地法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 0.5, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["G007", "疾风法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 0.5, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["G008", "嗜血匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 42.0, false], [Stat.HP, 0.05, true], [100, 0.005, true], [Stat.HP, 0.1, true], 0, 0, 0],
  ["G009", "荆棘长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 56.0, false], [Stat.ATK, 0.1, true], [Stat.SPD, 0.005, true], [Stat.ATK, 0.2, true], 0, 2, 0],
  ["G010", "腐蚀头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [Stat.DEF, 6.7, false], [Stat.DEF, 0.01, true], [Stat.DEF, 0.005, true], [104, 0.1, true], 2, 10, 5],
  ["G011", "吸血脉甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 6.7, false], [Stat.HP, 0.02, true], [Stat.HP, 0.005, true], [100, 0.3, true], 1, 0, 0],
  ["G012", "荆棘肩甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 6.7, false], [104, 0.1, true], [Stat.DEF, 0.005, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["G013", "迅捷护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [Stat.DEF, 6.7, false], [Stat.ASPD, 0.05, true], [Stat.ASPD, 0.005, true], [Stat.ASPD, 0.1, true], 0, 0, 0],
  ["G014", "坚韧腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 6.7, false], [112, 0.1, true], [Stat.ATK, 0.005, true], [Stat.HP, 0.5, true], 2, 0, 0],
  ["G015", "踏风战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 6.7, false], [Stat.SPD, 0.05, true], [Stat.SPD, 0.005, true], [Stat.SPD, 0.2, true], 0, 0, 0],
  ["G016", "嗜血项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [100, 0.03, true], [100, 0.005, true], [Stat.HP, 0.05, true], 0, 0, 0],
  ["G017", "元素指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [117, 0.05, true], [117, 0.005, true], [117, 0.1, true], 0, 0, 0],
  ["G018", "守护护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [Stat.ATK, 0.05, true], [Stat.ATK, 0.002, true], [Stat.HP, 0.01, true], 0, 2, 0],
  ["G019", "淘金者之镐", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [107, 0.05, true], [107, 0.005, true], [107, 0.01, true], 1, 0, 0],
  ["G020", "寻宝者背包", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [Stat.ATK, 0.03, true], [114, 0.003, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["G021", "破碎的钥匙链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [109, 0.02, true], [109, 0.002, true], [109, 0.05, true], 0, 0, 0],
  ["G022", "记忆碎片护符", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 1, false], [Stat.ATK, 0.005, true], [Stat.ATK, 0.05, true], 1, 0, 0],
  ["G023", "冷却沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [Stat.CDR, 0.01, true], [Stat.CDR, 0.002, true], [Stat.CDR, 1, false], 0, 0, 0],
  ["G024", "迅捷之翼", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 6.7, false], [Stat.CDR, 0.05, true], [Stat.SPD, 0.003, true], [Stat.SPD, 0.05, true], 0, 0, 0],
  ["G025", "冰霜护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [Stat.ATK, 0.05, true], [Stat.ATK, 0.005, true], [Stat.ATK, 0.05, true], 0, 0, 0],
  ["G026", "烈焰之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [Stat.ATK, 0.03, true], [Stat.ATK, 0.005, true], [Stat.ATK, 0.1, true], 2, 0, 0],
  ["G027", "荆棘之甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 6.7, false], [104, 0.03, true], [Stat.DEF, 0.005, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["G028", "生命之泉护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [Stat.HP, 0.005, true], [Stat.HP, 0.005, true], [Stat.HP, 0.01, true], 0, 0, 0],
  ["G029", "元素抗性披风", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 6.7, false], [106, 0.03, true], [106, 0.005, true], [117, 0.1, true], 0, 0, 0],
  ["G030", "贪婪之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [108, 0.02, true], [108, 0.005, true], [107, 0.05, true], 0, 0, 0],
  ["G031", "召唤师之戒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [116, 0.03, true], [116, 0.005, true], [Stat.ATK, 0.02, true], 0, 0, 0],
  ["G032", "时光沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [102, 0.03, true], [Stat.ATK, 0.005, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["G033", "瘟疫之触", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 0.05, true], [Stat.ATK, 0.003, true], [Stat.ATK, 2, false], 0, 3, 0],
  ["G034", "冻结之息", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 0.05, true], [Stat.ATK, 0.003, true], [Stat.ATK, 1, false], 0, 2, 0],
  ["G035", "灼烧烙印", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 0.05, true], [Stat.ATK, 0.003, true], [Stat.ATK, 0.05, true], 0, 3, 0],
  ["G036", "虚弱诅咒", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 0.05, true], [102, 0.003, true], [Stat.ATK, 1, false], 0, 3, 0],
  ["G037", "护盾发生器", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 56.0, false], [Stat.HP, 0.05, true], [Stat.ATK, 0.005, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["G038", "格挡者之盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 56.0, false], [110, 0.03, true], [110, 0.003, true], [110, 0.1, true], 0, 0, 0],
  ["G039", "闪避之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 6.7, false], [113, 0.05, true], [111, 0.003, true], [Stat.SPD, 0.05, true], 4, 0, 0],
  ["G040", "荆棘护盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 56.0, false], [104, 0.05, true], [Stat.ATK, 0.005, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["G041", "连击指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [Stat.ATK, 0.01, true], [Stat.ATK, 0.003, true], [Stat.ATK, 5.0, false], 0, 0, 5],
  ["G042", "处决者之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 56.0, false], [Stat.HP, 0.15, true], [105, 0.002, true], [Stat.HP, 0.15, true], 0, 0, 0],
  ["G043", "背刺匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 42.0, false], [Stat.ATK, 0.1, true], [Stat.ATK, 0.005, true], [Stat.ATK, 3, false], 0, 0, 0],
  ["G044", "弱点探测器", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [Stat.ATK, 0.05, true], [Stat.ATK, 0.002, true], [Stat.ATK, 5.0, false], 2, 3, 0],
  ["G045", "分裂箭袋", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [Stat.ATK, 0.05, true], [Stat.ATK, 0.003, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["G046", "穿透弹头", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 56.0, false], [Stat.ATK, 0.05, true], [Stat.ATK, 0.002, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["G047", "爆炸符文", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 72.8, false], [Stat.ATK, 0.05, true], [Stat.ATK, 0.003, true], [Stat.ATK, 0.5, true], 3, 0, 0],
  ["G048", "远程精准镜", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [Stat.ATK, 0.03, true], [Stat.ATK, 0.003, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["G049", "元素穿透指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [106, 0.03, true], [Stat.ATK, 0.003, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["G050", "真实伤害护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 6.7, false], [Stat.ATK, 5.0, false], [Stat.ATK, 2, false], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B000", "暗影短刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 65.6, false], [Stat.CDR, 0.08, true], [Stat.ATK, 0.05, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B001", "穿刺长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.DEF, 0.4, true], [Stat.DEF, 0.1, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B002", "裂地战斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.5, true], [Stat.ATK, 0.1, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B003", "元素调和法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [117, 0.6, true], [117, 0.02, true], [Stat.HP, 0.1, true], 0, 0, 0],
  ["B004", "巨兽猎手", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.ATK, 0.15, true], [Stat.ATK, 0.03, true], [Stat.DEF, 0.2, true], 0, 0, 0],
  ["B005", "圣光壁垒", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 87.5, false], [110, 0.6, true], [110, 0.03, true], [Stat.HP, 0.1, true], 0, 0, 0],
  ["B006", "疾风长矛", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [117, 0.2, true], [117, 0.02, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["B007", "噬魂战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.03, true], [Stat.HP, 0.005, true], [100, 0.6, true], 5, 0, 5],
  ["B008", "暗影斗篷", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.1, true], [Stat.ATK, 5.0, false], 0, 5, 0],
  ["B009", "荆棘头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [104, 0.3, true], [Stat.DEF, 0.02, true], [104, 0.2, true], 2, 0, 0],
  ["B010", "守护肩甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.HP, 0.5, true], [Stat.ATK, 0.01, true], [Stat.HP, 0.3, true], 0, 0, 0],
  ["B011", "迅捷护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.ASPD, 0.08, true], [Stat.ASPD, 0.01, true], [Stat.ATK, 0.5, true], 0, 0, 5],
  ["B012", "坚韧腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [112, 0.3, true], [Stat.ATK, 0.02, true], [Stat.ATK, 3, false], 2, 0, 0],
  ["B013", "踏风战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [111, 0.4, true], [Stat.SPD, 0.02, true], [Stat.ATK, 0.3, true], 0, 0, 0],
  ["B014", "巨型方盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 87.5, false], [Stat.CDR, 15, false], [Stat.ATK, 0.05, true], [Stat.ATK, 0.3, true], 0, 0, 0],
  ["B015", "元素指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [117, 0.08, true], [117, 0.01, true], [Stat.ATK, 0.2, true], 0, 0, 0],
  ["B016", "猎手徽章", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.HP, 0.4, true], [Stat.CRT, 0.01, true], [Stat.ATK, 5.0, false], 1, 0, 0],
  ["B017", "守护护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.HP, 0.2, true], [Stat.HP, 0.02, true], [Stat.ATK, 5, false], 2, 0, 0],
  ["B018", "贪婪之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [107, 0.15, true], [107, 0.02, true], [107, 0.05, true], 0, 0, 0],
  ["B019", "唤灵短杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [Stat.AP, 0.3, true], [116, 0.02, true], [Stat.AP, 0.6, true], 0, 15, 0],
  ["B020", "捕兽长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.ATK, 0.08, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["B021", "反伤巨剑", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [104, 0.3, true], [104, 0.02, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B022", "空间匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 65.6, false], [Stat.ATK, 0.06, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.3, true], 0, 0, 0],
  ["B023", "标记重弩", "heavy_crossbow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.08, true], [Stat.ATK, 0.01, true], [Stat.ATK, 2, false], 2, 5, 0],
  ["B024", "元素战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [117, 0.3, true], [117, 0.02, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["B025", "守护者之盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 87.5, false], [110, 0.02, true], [110, 0.02, true], [Stat.ATK, 3, false], 0, 0, 5],
  ["B026", "毒牙短刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 65.6, false], [Stat.ATK, 0.08, true], [Stat.ATK, 0.02, true], [Stat.ATK, 2, false], 0, 3, 0],
  ["B027", "雷霆战锤", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.06, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.2, true], 0, 0, 0],
  ["B028", "疾风双刃", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ASPD, 0.1, true], [Stat.ASPD, 0.01, true], [Stat.ASPD, 0.5, true], 0, 0, 5],
  ["B029", "灵魂收割者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.ATK, 0.01, true], [Stat.HP, 0.005, true], [Stat.HP, 0.1, true], 5, 0, 10],
  ["B030", "冰霜长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.ATK, 0.08, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["B031", "暗影法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [Stat.AP, 0.4, true], [Stat.ATK, 0.02, true], [Stat.SPD, 0.3, true], 0, 0, 0],
  ["B032", "荆棘链刃", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.08, true], [Stat.ATK, 0.2, false], [Stat.ATK, 0.5, true], 2, 0, 0],
  ["B033", "圣光权杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [Stat.HP, 0.1, true], [Stat.ATK, 0.02, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B034", "陷阱头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.ATK, 0.1, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.2, true], 0, 3, 0],
  ["B035", "召唤胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.HP, 0.05, true], [Stat.HP, 0.02, true], [Stat.AP, 0.5, true], 0, 0, 0],
  ["B036", "反伤肩甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [104, 0.2, true], [104, 0.02, true], [Stat.ATK, 0.3, true], 2, 0, 0],
  ["B037", "护盾护手", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 87.5, false], [Stat.HP, 0.05, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["B038", "资源腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.ATK, 3, false], [Stat.ATK, 0.02, true], [Stat.SPD, 0.15, true], 1, 0, 0],
  ["B039", "位移战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 0.1, true], [Stat.SPD, 0.02, true], [Stat.ATK, 0.3, true], 0, 3, 0],
  ["B040", "标记头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.ATK, 0.06, true], [Stat.ATK, 0.01, true], [Stat.ATK, 5.0, false], 2, 5, 0],
  ["B041", "元素抗性胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [106, 0.05, true], [106, 0.01, true], [Stat.ATK, 5.0, false], 2, 0, 0],
  ["B042", "经济肩甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [107, 0.1, true], [107, 0.02, true], [107, 10, false], 1, 0, 0],
  ["B043", "钥匙护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [109, 0.03, true], [109, 0.01, true], [109, 0.1, true], 0, 0, 0],
  ["B044", "记忆腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.ATK, 1, false], [Stat.ATK, 0.02, true], [Stat.ATK, 0.05, true], 1, 0, 0],
  ["B045", "召唤战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.SPD, 0.1, true], [Stat.SPD, 0.02, true], [Stat.SPD, 0.3, true], 0, 0, 0],
  ["B046", "护盾头盔", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 87.5, false], [Stat.HP, 0.5, true], [Stat.ATK, 0.02, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B047", "反伤胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [104, 0.1, true], [104, 0.02, true], [104, 0.1, true], 2, 0, 0],
  ["B048", "召唤戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [116, 0.1, true], [116, 0.02, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["B049", "陷阱护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.ATK, 0.15, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["B050", "反伤徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [104, 0.1, true], [104, 0.02, true], [104, 0.1, true], 0, 0, 0],
  ["B051", "资源项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.ATK, 0.1, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.15, true], 0, 0, 0],
  ["B052", "位移戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.SPD, 0.1, true], [Stat.SPD, 0.02, true], [Stat.ATK, 0.3, true], 0, 3, 0],
  ["B053", "标记护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.ATK, 0.06, true], [Stat.ATK, 0.01, true], [Stat.HP, 0.05, true], 2, 5, 0],
  ["B054", "元素戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [117, 0.08, true], [117, 0.02, true], [Stat.ATK, 0.2, true], 0, 0, 0],
  ["B055", "经济项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [107, 0.15, true], [107, 0.02, true], [107, 0.05, true], 0, 0, 0],
  ["B056", "钥匙徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [109, 0.03, true], [109, 0.01, true], [109, 0.1, true], 0, 0, 0],
  ["B057", "野蛮冲撞战斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.3, true], 0, 0, 0],
  ["B058", "影闪匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 65.6, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.03, true], [Stat.CRT, 0.2, true], 0, 0, 0],
  ["B059", "火球法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [Stat.AP, 0.6, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.6, true], 0, 3, 0],
  ["B060", "冰霜陷阱长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["B061", "雷霆一击战锤", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.02, true], [Stat.ATK, 1.5, false], 0, 0, 0],
  ["B062", "治疗之光权杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [Stat.HP, 0.15, true], [Stat.ATK, 0.02, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B063", "召唤狼灵法书", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [Stat.AP, 0.4, true], [116, 0.02, true], [Stat.ATK, 0.1, true], 0, 20, 0],
  ["B064", "盾牌冲锋长矛", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [110, 0.6, true], [110, 0.02, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B065", "毒雾短刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 65.6, false], [Stat.CDR, 0.3, true], [Stat.ATK, 0.02, true], [Stat.SPD, 0.3, true], 0, 4, 0],
  ["B066", "旋风双斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.CDR, 0.6, true], [Stat.ASPD, 0.01, true], [Stat.SPD, 0.2, true], 0, 2, 0],
  ["B067", "圣光新星法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [Stat.HP, 0.6, true], [Stat.AP, 0.02, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["B068", "暗影突袭链刃", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.15, true], 0, 0, 0],
  ["B069", "爆裂射击重弩", "heavy_crossbow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.2, true], 0, 0, 0],
  ["B070", "风之箭长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [117, 0.6, true], [117, 0.02, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B071", "地刺法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [117, 0.6, true], [117, 0.02, true], [Stat.ATK, 0.5, false], 0, 0, 0],
  ["B072", "灵魂吸取战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.HP, 0.6, true], [100, 0.02, true], [Stat.ATK, 3, false], 0, 0, 0],
  ["B073", "无畏冲锋胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 15, false], [Stat.HP, 0.02, true], [Stat.ATK, 0.05, true], 0, 0, 0],
  ["B074", "闪现战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 5, false], [Stat.SPD, 0.02, true], [Stat.ATK, 0.3, true], 0, 0, 0],
  ["B075", "生命链接护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.HP, 0.5, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["B076", "能量护盾肩甲", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 87.5, false], [Stat.HP, 0.2, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.6, true], 0, 6, 0],
  ["B077", "荆棘爆发头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [104, 0.6, true], [104, 0.02, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B078", "战吼腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 0.2, true], [Stat.DEF, 0.02, true], [Stat.ATK, 1, false], 0, 5, 0],
  ["B079", "烟雾弹头盔", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.CDR, 3, false], [111, 0.02, true], [Stat.SPD, 0.2, true], 0, 0, 0],
  ["B080", "召唤护卫胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.HP, 0.4, true], [Stat.HP, 0.01, true], [Stat.AP, 0.4, true], 0, 12, 0],
  ["B081", "反击姿态护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [104, 0.5, true], [110, 0.02, true], [Stat.ATK, 0.3, true], 0, 0, 0],
  ["B082", "疾风步腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [111, 0.5, true], [Stat.SPD, 0.02, true], [Stat.ATK, 5.0, false], 0, 4, 0],
  ["B083", "冰霜新星胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 2.5, false], [Stat.ATK, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["B084", "火焰吐息头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.AP, 0.6, true], [Stat.ATK, 0.01, true], [Stat.AP, 0.2, true], 0, 0, 0],
  ["B085", "治疗之泉战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.HP, 0.02, true], [Stat.HP, 0.01, true], [Stat.ATK, 0.05, true], 0, 5, 0],
  ["B086", "暗影步斗篷", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 0.5, true], [Stat.ATK, 0.02, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B087", "加速护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.ASPD, 0.25, true], [Stat.ASPD, 0.01, true], [Stat.ATK, 5.0, false], 0, 5, 0],
  ["B088", "元素爆发戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.AP, 0.6, true], [117, 0.01, true], [Stat.ATK, 0.15, true], 0, 0, 0],
  ["B089", "护盾术项链", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 87.5, false], [Stat.HP, 0.08, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.08, true], 0, 8, 0],
  ["B090", "传送戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.CDR, 6, false], [Stat.SPD, 0.01, true], [111, 0.15, true], 0, 0, 0],
  ["B091", "治愈术护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.HP, 0.15, true], [Stat.ATK, 0.01, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B092", "荆棘领域徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [104, 3, false], [104, 0.01, true], [Stat.SPD, 0.15, true], 2, 0, 0],
  ["B093", "资源爆发项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.CDR, 0.5, true], [Stat.ATK, 0.02, true], [Stat.ATK, 0.2, true], 0, 0, 0],
  ["B094", "时间减缓沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.ASPD, 0.3, true], [Stat.CDR, 0.01, true], [Stat.ASPD, 0.15, true], 0, 3, 0],
  ["B095", "挑衅战锤", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.CDR, 0.6, true], [Stat.DEF, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["B096", "投掷飞斧", "axe", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["B097", "缠绕藤蔓法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [117, 0.6, true], [117, 0.01, true], [Stat.AP, 0.3, true], 0, 0, 0],
  ["B098", "驱散之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.CDR, 0.5, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["B099", "沉默重弩", "heavy_crossbow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.CDR, 2, false], [Stat.ATK, 0.01, true], [Stat.SPD, 0.2, true], 0, 0, 0],
  ["B100", "净化法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [Stat.CDR, 25, false], [Stat.ATK, 0.01, true], [Stat.HP, 0.05, true], 0, 0, 0],
  ["B101", "锁链拖拽链刃", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.CDR, 0.6, true], [Stat.ASPD, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["B102", "击退长矛", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [101, 0.6, true], [Stat.ATK, 0.01, true], [101, 0.5, true], 0, 0, 0],
  ["B103", "生命汲取战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.HP, 0.6, true], [100, 0.01, true], [Stat.ATK, 3, false], 0, 0, 0],
  ["B104", "火焰喷射法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [Stat.AP, 0.5, true], [Stat.ATK, 0.01, true], [Stat.AP, 0.2, true], 0, 2, 0],
  ["B105", "冰锥术法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [Stat.AP, 0.6, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.2, true], 0, 0, 0],
  ["B106", "落石术法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [117, 0.6, true], [117, 0.01, true], [Stat.ATK, 0.5, false], 0, 0, 0],
  ["B107", "风刃长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [117, 0.6, true], [117, 0.01, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["B108", "雷霆标枪", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 87.5, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["B109", "暗影箭匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 65.6, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.01, true], [Stat.HP, 0.03, true], 0, 0, 0],
  ["B110", "治疗图腾法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 113.8, false], [Stat.HP, 0.02, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.05, true], 0, 5, 0],
  ["B111", "石肤胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 0.2, true], [Stat.DEF, 0.01, true], [Stat.ATK, 5.0, false], 0, 5, 0],
  ["B112", "疾跑战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.SPD, 0.3, true], [Stat.SPD, 0.01, true], [111, 0.1, true], 0, 4, 0],
  ["B113", "护盾发生器肩甲", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 87.5, false], [Stat.HP, 0.1, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.5, true], 0, 6, 0],
  ["B114", "烟雾弹护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 2, false], [111, 0.01, true], [Stat.SPD, 0.15, true], 0, 0, 0],
  ["B115", "战吼头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 0.1, true], [Stat.DEF, 0.01, true], [Stat.ATK, 1, false], 0, 5, 0],
  ["B116", "荆棘护盾腿甲", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 87.5, false], [104, 0.5, true], [104, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["B117", "生命链接护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.HP, 0.3, true], [Stat.HP, 0.01, true], [Stat.ATK, 0.05, true], 0, 5, 0],
  ["B118", "闪现护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 4, false], [Stat.SPD, 0.01, true], [Stat.ATK, 0.2, true], 0, 0, 0],
  ["B119", "净化腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [Stat.CDR, 25, false], [Stat.ATK, 0.01, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["B120", "反击姿态肩甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 10.5, false], [104, 0.3, true], [110, 0.01, true], [Stat.ATK, 0.15, true], 0, 0, 0],
  ["B121", "资源回复项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 10.5, false], [Stat.CDR, 0.3, true], [Stat.ATK, 0.01, true], [Stat.ATK, 0.15, true], 0, 0, 0],
  ["P000", "腐蚀之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.15, true], [Stat.ATK, 0.03, true], [117, 0.6, true], 2, 4, 0],
  ["P001", "血怒巨斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 224.0, false], [Stat.HP, 0.03, true], [100, 0.03, true], [Stat.HP, 0.4, true], 1, 0, 0],
  ["P002", "影舞匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 105.0, false], [Stat.CRT, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.6, true], 0, 0, 5],
  ["P003", "猎杀者长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.04, true], [Stat.ATK, 0.03, true], [Stat.ATK, 5, false], 2, 8, 5],
  ["P004", "不灭壁垒", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 140.0, false], [104, 0.02, true], [Stat.DEF, 0.03, true], [104, 0.1, true], 5, 0, 10],
  ["P005", "预言者头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.CRD, 0.03, true], [Stat.CRT, 0.02, true], [113, 0.05, true], 0, 0, 5],
  ["P006", "踏虚战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.ATK, 0.5, true], [Stat.SPD, 0.03, true], [Stat.ATK, 5.0, false], 0, 0, 3],
  ["P007", "元素之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [106, 0.1, true], [106, 0.02, true], [106, 0.3, true], 2, 5, 3],
  ["P008", "霜噬巨剑", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 224.0, false], [Stat.SPD, 0.05, true], [Stat.ATK, 0.03, true], [Stat.ATK, 1.5, false], 2, 6, 8],
  ["P009", "雷霆之怒", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [Stat.ATK, 0.15, true], [Stat.ATK, 0.03, true], [Stat.ATK, 1, false], 2, 0, 0],
  ["P010", "剧毒之牙", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.2, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.2, true], 0, 5, 5],
  ["P011", "大地震击", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 224.0, false], [Stat.ATK, 0.5, true], [117, 0.03, true], [Stat.ATK, 0.15, true], 0, 0, 0],
  ["P012", "风语长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.3, true], [117, 0.03, true], [117, 0.6, true], 3, 0, 0],
  ["P013", "暗影收割者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.02, true], [Stat.ATK, 0.03, true], [Stat.ATK, 5.0, false], 5, 0, 15],
  ["P014", "虚空之刺", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.DEF, 0.3, true], [Stat.DEF, 0.03, true], [Stat.DEF, 0.6, true], 0, 0, 0],
  ["P015", "混沌之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [117, 0.5, true], [117, 0.03, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["P016", "生命之弦", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.HP, 0.01, true], [Stat.HP, 0.03, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["P017", "破晓之光", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [Stat.ATK, 0.15, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["P018", "深渊低语", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [Stat.ATK, 0.1, true], [116, 0.03, true], [Stat.AP, 0.5, true], 1, 10, 0],
  ["P019", "星辰碎片", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [Stat.AP, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.6, true], 3, 0, 0],
  ["P020", "复仇之刺", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.05, true], [Stat.ATK, 0.03, true], [Stat.ATK, 5.0, false], 2, 0, 5],
  ["P021", "冰霜之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.HP, 0.1, true], [Stat.ATK, 0.03, true], [Stat.ATK, 1, false], 0, 0, 0],
  ["P022", "烈焰之魂", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [Stat.ATK, 0.2, true], [Stat.ATK, 0.03, true], [Stat.ATK, 1, false], 2, 3, 0],
  ["P023", "雷霆护肩", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.ATK, 0.6, true], [Stat.ATK, 0.03, true], [Stat.CDR, 5, false], 5, 0, 5],
  ["P024", "大地守护", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.3, true], [Stat.DEF, 0.03, true], [Stat.ATK, 5.0, false], 0, 5, 0],
  ["P025", "风行者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.SPD, 0.02, true], [Stat.SPD, 0.03, true], [Stat.SPD, 3, false], 5, 0, 10],
  ["P026", "暗影斗篷", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.CRT, 0.3, true], [Stat.CRT, 0.02, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["P027", "圣光护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.HP, 0.3, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.1, true], 0, 0, 0],
  ["P028", "虚空之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.DEF, 0.15, true], [Stat.DEF, 0.03, true], [118, 0.1, true], 1, 0, 0],
  ["P029", "混沌之皮", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [106, 0.3, true], [106, 0.03, true], [117, 0.5, true], 0, 10, 0],
  ["P030", "生命之树", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [Stat.HP, 0.01, true], [Stat.HP, 0.03, true], [Stat.HP, 0.1, true], 0, 0, 0],
  ["P031", "星辰披风", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.ATK, 0.5, true], [111, 0.02, true], [Stat.ATK, 0.1, true], 4, 0, 0],
  ["P032", "复仇之甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.ATK, 0.02, true], [Stat.ATK, 0.02, true], [Stat.HP, 0.05, true], 5, 0, 10],
  ["P033", "元素调和者", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [117, 0.15, true], [117, 0.03, true], [117, 0.6, true], 2, 5, 0],
  ["P034", "灵魂锁链", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.02, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.2, true], 5, 0, 10],
  ["P035", "荆棘之环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [104, 0.15, true], [104, 0.03, true], [104, 0.15, true], 2, 0, 0],
  ["P036", "猎杀者徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CRT, 0.03, true], [Stat.CRT, 0.02, true], [Stat.ATK, 5.0, false], 0, 0, 5],
  ["P037", "元素之戒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [117, 0.2, true], [117, 0.03, true], [Stat.AP, 0.6, true], 0, 0, 0],
  ["P038", "生命之泉", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.HP, 0.04, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.1, true], 0, 6, 0],
  ["P039", "时空沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.08, true], [Stat.CDR, 0.02, true], [Stat.ATK, 3, false], 0, 0, 0],
  ["P040", "贪婪之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [107, 0.01, true], [107, 0.03, true], [107, 0.1, true], 0, 0, 0],
  ["P041", "记忆碎片", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [Stat.ATK, 0.005, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.1, true], 1, 0, 0],
  ["P042", "钥匙守护", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [109, 0.05, true], [109, 0.02, true], [109, 0.15, true], 0, 0, 0],
  ["P043", "召唤师之核", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [116, 0.05, true], [116, 0.03, true], [Stat.AP, 0.5, true], 0, 0, 0],
  ["P044", "荆棘领域", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [104, 3, false], [104, 0.03, true], [Stat.SPD, 0.2, true], 2, 0, 0],
  ["P045", "格挡反击者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [110, 0.06, true], [110, 0.02, true], [110, 0.5, true], 0, 0, 5],
  ["P046", "分裂弩", "heavy_crossbow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 224.0, false], [Stat.ATK, 0.2, true], [Stat.ATK, 0.03, true], [Stat.ATK, 1, false], 0, 0, 0],
  ["P047", "连击双刃", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 224.0, false], [Stat.ASPD, 0.03, true], [Stat.ASPD, 0.02, true], [Stat.ASPD, 3, false], 5, 0, 8],
  ["P048", "蓄能战锤", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 224.0, false], [Stat.ATK, 0.15, true], [Stat.ATK, 0.03, true], [Stat.ATK, 1.5, false], 0, 0, 0],
  ["P049", "荆棘长鞭", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.15, true], [Stat.ATK, 0.03, true], [Stat.ATK, 2, false], 2, 4, 3],
  ["P050", "猎手标枪", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 140.0, false], [Stat.ATK, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["P051", "元素之泉法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [Stat.ATK, 0.25, true], [117, 0.03, true], [Stat.AP, 0.6, true], 0, 0, 0],
  ["P052", "格挡者壁垒", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 140.0, false], [110, 0.03, true], [110, 0.02, true], [Stat.ATK, 0.6, true], 0, 0, 5],
  ["P053", "延迟伤害甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.ATK, 0.3, true], [Stat.ATK, 0.02, true], [Stat.ATK, 5.0, false], 1, 0, 0],
  ["P054", "图腾护肩", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.HP, 0.3, true], [Stat.HP, 0.03, true], [Stat.AP, 0.6, true], 0, 10, 0],
  ["P055", "镜像腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.ATK, 0.2, true], [Stat.SPD, 0.03, true], [Stat.ATK, 0.5, true], 0, 4, 0],
  ["P056", "吸血光环头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [100, 0.05, true], [100, 0.02, true], [Stat.HP, 0.02, true], 0, 0, 0],
  ["P057", "减伤叠层胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.ATK, 0.02, true], [Stat.DEF, 0.03, true], [Stat.CDR, 60, false], 5, 0, 8],
  ["P058", "技能连发护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.CDR, 0.15, true], [Stat.CDR, 0.02, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["P059", "陷阱大师战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 16.8, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["P060", "精英猎杀者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.ATK, 0.15, true], [Stat.ATK, 0.03, true], [Stat.HP, 0.1, true], 1, 0, 0],
  ["P061", "处决者印记", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.HP, 0.3, true], [105, 0.03, true], [Stat.ATK, 5.0, false], 1, 0, 0],
  ["P062", "增益窃取者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.ATK, 0.1, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.5, true], 1, 5, 0],
  ["P063", "多重射击徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.ATK, 0.15, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.2, true], 0, 0, 0],
  ["P064", "伤害储存护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.ATK, 5.0, false], [Stat.ATK, 0.5, false], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["P065", "裂空斩", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["P066", "烈焰风暴", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.AP, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.2, true], 0, 4, 0],
  ["P067", "冰封领域", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.AP, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.15, true], 0, 0, 0],
  ["P068", "雷霆万钧", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 2, false], 0, 0, 0],
  ["P069", "暗影突袭", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["P070", "荆棘囚笼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.2, true], 0, 0, 0],
  ["P071", "圣光审判", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.HP, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["P072", "毒雾弹", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.5, true], [Stat.ATK, 0.03, true], [Stat.SPD, 0.3, true], 0, 5, 0],
  ["P073", "旋风斩", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.6, true], [Stat.ASPD, 0.02, true], [Stat.SPD, 0.25, true], 0, 3, 0],
  ["P074", "穿透狙击", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.DEF, 0.6, true], [Stat.DEF, 0.03, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["P075", "星辰坠落", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.AP, 0.6, true], [Stat.ATK, 0.03, true], [Stat.AP, 0.3, true], 0, 0, 0],
  ["P076", "灵魂汲取", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.HP, 0.6, true], [100, 0.03, true], [Stat.ATK, 3, false], 0, 0, 0],
  ["P077", "风之屏障", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [104, 0.5, true], [110, 0.03, true], [110, 0.5, true], 0, 0, 0],
  ["P078", "地裂术", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [117, 0.6, true], [117, 0.03, true], [Stat.ATK, 0.8, false], 0, 0, 0],
  ["P079", "爆裂箭雨", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.03, true], [Stat.CRT, 0.1, true], 0, 3, 0],
  ["P080", "血怒爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.HP, 0.15, true], [Stat.ATK, 0.03, true], [Stat.HP, 0.5, true], 0, 0, 0],
  ["P081", "元素洪流", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [117, 0.6, true], [117, 0.03, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["P082", "暗影分身", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.3, true], [116, 0.03, true], [Stat.ATK, 0.6, true], 0, 8, 0],
  ["P083", "圣光护盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 140.0, false], [Stat.HP, 0.2, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.6, true], 0, 6, 0],
  ["P084", "时空加速", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.ASPD, 0.4, true], [Stat.ASPD, 0.02, true], [Stat.ATK, 2, false], 0, 5, 0],
  ["P085", "无畏冲锋", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.6, true], [Stat.HP, 0.03, true], [Stat.ATK, 0.15, true], 0, 0, 0],
  ["P086", "闪现", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 6, false], [Stat.SPD, 0.03, true], [Stat.ATK, 0.4, true], 0, 0, 0],
  ["P087", "能量护盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 140.0, false], [Stat.HP, 0.25, true], [Stat.ATK, 0.03, true], [Stat.ATK, 5.0, false], 0, 8, 0],
  ["P088", "荆棘爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [104, 0.6, true], [104, 0.03, true], [Stat.ATK, 0.2, true], 0, 0, 0],
  ["P089", "战吼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.SPD, 0.25, true], [Stat.DEF, 0.03, true], [Stat.ATK, 2, false], 0, 6, 0],
  ["P090", "烟雾弹", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.SPD, 0.3, true], [111, 0.03, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["P091", "召唤守卫", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.HP, 0.6, true], [Stat.HP, 0.03, true], [Stat.AP, 0.6, true], 0, 15, 0],
  ["P092", "反击姿态", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [104, 0.6, true], [110, 0.03, true], [Stat.ATK, 0.3, true], 0, 0, 0],
  ["P093", "疾风步", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [111, 0.6, true], [Stat.SPD, 0.03, true], [Stat.ATK, 0.4, true], 0, 4, 0],
  ["P094", "冰霜新星", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.AP, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.2, true], 0, 0, 0],
  ["P095", "火焰吐息", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.AP, 0.6, true], [Stat.ATK, 0.03, true], [Stat.AP, 0.4, true], 0, 0, 0],
  ["P096", "暗影步", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["P097", "风暴之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [117, 0.6, true], [117, 0.03, true], [Stat.ATK, 0.15, true], 0, 3, 0],
  ["P098", "灵魂链接", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.4, true], [Stat.HP, 0.03, true], [Stat.ATK, 0.15, true], 0, 6, 0],
  ["P099", "净化之光", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 182.0, false], [Stat.HP, 0.1, true], [Stat.ATK, 0.03, true], [Stat.ATK, 3, false], 0, 0, 0],
  ["P100", "元素爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.AP, 0.6, true], [117, 0.03, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["P101", "召唤元素灵", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.AP, 0.5, true], [116, 0.03, true], [Stat.ATK, 5.0, false], 0, 15, 0],
  ["P102", "护盾术", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 140.0, false], [Stat.HP, 0.2, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.15, true], 0, 8, 0],
  ["P103", "传送", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 8, false], [Stat.SPD, 0.03, true], [111, 0.2, true], 0, 0, 0],
  ["P104", "治愈术", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.HP, 0.25, true], [Stat.ATK, 0.03, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["P105", "资源爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.25, true], 0, 0, 0],
  ["P106", "时间减缓", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.ASPD, 0.5, true], [Stat.CDR, 0.02, true], [Stat.ASPD, 0.25, true], 0, 4, 0],
  ["P107", "灵魂爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 16.8, false], [Stat.CDR, 0.4, true], [Stat.ATK, 0.03, true], [Stat.HP, 0.05, true], 0, 0, 10],
  ["P108", "星辰护盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 140.0, false], [111, 0.15, true], [111, 0.02, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["O000", "血海狂潮", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [100, 0.05, true], [100, 0.05, true], [Stat.HP, 0.01, true], 1, 0, 0],
  ["O001", "影狱双刃", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 364.0, false], [Stat.ATK, 0.4, true], [Stat.ATK, 0.05, true], [Stat.ATK, 0.3, true], 1, 6, 0],
  ["O002", "猎神长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 227.5, false], [Stat.CDR, 0.05, true], [Stat.ATK, 0.05, true], [Stat.ATK, 5, false], 1, 10, 8],
  ["O003", "不朽壁垒", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 227.5, false], [104, 0.03, true], [Stat.DEF, 0.05, true], [Stat.ATK, 0.3, true], 5, 0, 15],
  ["O004", "预言者王冠", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.CRD, 0.06, true], [Stat.CRT, 0.03, true], [Stat.CRT, 0.2, true], 0, 0, 6],
  ["O005", "踏虚神靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 27.3, false], [113, 0.5, true], [Stat.SPD, 0.05, true], [Stat.HP, 0.03, true], 0, 5, 0],
  ["O006", "元素之心·终焉", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [106, 0.2, true], [106, 0.04, true], [Stat.HP, 0.15, true], 2, 8, 0],
  ["O007", "灵魂王座", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.HP, 0.03, true], [Stat.ATK, 0.04, true], [Stat.ATK, 0.5, true], 5, 0, 20],
  ["O008", "处决者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [118, 0.3, true], [Stat.ATK, 0.05, true], [105, 0.4, true], 0, 0, 0],
  ["O009", "血怒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [100, 0.5, true], [100, 0.05, true], [Stat.HP, 0.3, true], 0, 0, 0],
  ["O010", "元素洪流", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 0.6, true], [Stat.AP, 0.05, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["O011", "猎杀者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 0.6, true], [Stat.ATK, 0.05, true], [Stat.ATK, 5.0, false], 1, 0, 0],
  ["O012", "不朽者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.HP, 0.5, true], [Stat.HP, 0.05, true], [Stat.ATK, 5, false], 2, 0, 0],
  ["O013", "荆棘之王", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [104, 0.5, true], [Stat.DEF, 0.05, true], [104, 0.2, true], 2, 0, 0],
  ["O014", "疾风之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 27.3, false], [Stat.SPD, 0.5, true], [Stat.SPD, 0.05, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["O015", "暴君之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.HP, 0.25, true], [Stat.CRT, 0.03, true], [113, 0.05, true], 0, 0, 0],
  ["O016", "元素之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [117, 0.4, true], [117, 0.05, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["O017", "灵魂容器", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.HP, 0.15, true], [Stat.ATK, 0.05, true], [Stat.HP, 0.2, true], 1, 0, 0],
  ["O018", "裂地巨斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 364.0, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.05, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["O019", "流星法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 295.8, false], [Stat.AP, 0.6, true], [Stat.AP, 0.05, true], [Stat.AP, 0.6, true], 0, 0, 0],
  ["O020", "影袭匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 170.6, false], [Stat.CDR, 0.6, true], [Stat.ATK, 0.06, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["O021", "穿透长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 227.5, false], [Stat.DEF, 0.6, true], [Stat.ATK, 0.05, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["O022", "钢铁之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.CDR, 0.5, true], [Stat.HP, 0.06, true], [Stat.ATK, 5.0, false], 0, 6, 0],
  ["O023", "战吼头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [Stat.DEF, 27.3, false], [Stat.CDR, 0.6, true], [Stat.DEF, 0.05, true], [Stat.ATK, 0.3, true], 2, 0, 0],
  ["O024", "疾风战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 27.3, false], [101, 0.6, true], [Stat.SPD, 0.05, true], [Stat.SPD, 0.5, true], 2, 0, 0],
  ["O025", "元素爆发戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [117, 0.6, true], [117, 0.05, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["O026", "治疗之泉项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.HP, 0.4, true], [Stat.ATK, 0.06, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["O027", "召唤守护者护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.HP, 0.6, true], [Stat.HP, 0.05, true], [Stat.AP, 0.6, true], 0, 20, 0],
  ["O028", "弹射之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 227.5, false], [Stat.ATK, 0.6, true], [Stat.ATK, 0.05, true], [Stat.ATK, 1, false], 0, 0, 0],
  ["O029", "连击之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 227.5, false], [Stat.ATK, 0.15, true], [Stat.ASPD, 0.03, true], [Stat.ATK, 5.0, false], 0, 0, 5],
  ["O030", "金币猎手", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 227.5, false], [107, 10, false], [107, 0.05, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["O031", "灵魂收割者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 227.5, false], [Stat.ATK, 0.3, true], [116, 0.05, true], [Stat.ATK, 5.0, false], 1, 10, 0],
  ["O032", "双重打击", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 0.25, true], [Stat.ATK, 0.05, true], [Stat.ATK, 0.4, true], 0, 0, 0],
  ["O033", "幸运之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 227.5, false], [Stat.ATK, 0.15, true], [Stat.CRT, 0.03, true], [Stat.ATK, 0.25, true], 0, 0, 0],
  ["O034", "生命百分比之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 227.5, false], [Stat.HP, 0.05, true], [Stat.ATK, 0.05, true], [Stat.ATK, 0.08, true], 0, 0, 0],
  ["O035", "斩首者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 0.6, true], [Stat.ATK, 0.05, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["O036", "终结者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.HP, 0.3, true], [Stat.ATK, 0.05, true], [Stat.ATK, 0.4, true], 0, 0, 0],
  ["O037", "血怒之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 227.5, false], [Stat.HP, 0.1, true], [100, 0.05, true], [Stat.HP, 0.1, true], 0, 0, 0],
  ["O038", "吸血狂徒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [100, 0.05, true], [100, 0.05, true], [100, 0.5, true], 0, 0, 0],
  ["O039", "元素爆裂之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 227.5, false], [Stat.AP, 0.15, true], [117, 0.05, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["O040", "混沌之触", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.AP, 295.8, false], [Stat.ATK, 0.2, true], [117, 0.05, true], [Stat.ATK, 0.35, true], 0, 3, 0],
  ["O041", "闪避新星", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 0.6, true], [Stat.SPD, 0.05, true], [Stat.ATK, 0.3, true], 4, 0, 0],
  ["O042", "格挡反击者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [110, 0.6, true], [110, 0.03, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["O043", "火焰行者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.ATK, 227.5, false], [Stat.AP, 0.6, true], [Stat.ATK, 0.05, true], [Stat.ATK, 5.0, false], 0, 4, 0],
  ["O044", "闪电之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 27.3, false], [Stat.ATK, 0.6, true], [Stat.SPD, 0.05, true], [Stat.ATK, 5.0, false], 0, 0, 0],
  ["O045", "元素附魔师", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [117, 0.5, true], [117, 0.05, true], [Stat.ATK, 5.0, false], 2, 10, 0],
  ["O046", "冲击波之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [Stat.DEF, 27.3, false], [Stat.ATK, 0.6, true], [Stat.SPD, 0.05, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["O047", "不动堡垒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.HP, 0.3, true], [Stat.DEF, 0.05, true], [Stat.ATK, 0.5, true], 0, 0, 0],
  ["O048", "冷却之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.CDR, 1, false], [Stat.CDR, 0.03, true], [Stat.CDR, 2, false], 0, 0, 0],
  ["O049", "冲刺大师", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 5.0, false], [Stat.SPD, 0.05, true], [Stat.ATK, 0.5, true], 1, 0, 0],
  ["O050", "反击之甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [Stat.DEF, 27.3, false], [Stat.ATK, 0.6, true], [Stat.DEF, 0.05, true], [Stat.ATK, 0.6, true], 2, 0, 0],
  ["O051", "荆棘反弹", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [104, 0.6, true], [110, 0.03, true], [104, 0.6, true], 0, 0, 0],
  ["O052", "濒死新星", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.HP, 0.3, true], [Stat.HP, 0.05, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["O053", "伤害转盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 227.5, false], [Stat.HP, 0.5, true], [Stat.DEF, 0.05, true], [Stat.ATK, 0.6, true], 2, 0, 0],
  ["O054", "护盾爆裂", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 227.5, false], [Stat.ATK, 0.6, true], [Stat.ATK, 0.05, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["O055", "猎杀者勋章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ASPD, 10, false], [Stat.ATK, 0.03, true], [Stat.ATK, 5.0, false], 1, 15, 0],
  ["O056", "召唤领主", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 0.25, true], [116, 0.05, true], [Stat.ATK, 1, false], 0, 0, 0],
  ["O057", "资源爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 0.6, true], [Stat.ATK, 0.05, true], [Stat.ATK, 20, false], 0, 0, 0],
  ["O058", "技能强化者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 0.6, true], [Stat.AP, 0.05, true], [Stat.ATK, 0.6, true], 0, 0, 0],
  ["O059", "闪避强化者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 0.6, true], [111, 0.03, true], [Stat.ATK, 0.6, true], 4, 0, 0],
  ["O060", "不死之身", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 2, false], [Stat.HP, 0.05, true], [Stat.ATK, 3, false], 1, 0, 0],
  ["O061", "贪婪之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [107, 0.03, true], [107, 0.05, true], [107, 0.05, true], 0, 0, 0],
  ["O062", "传奇共鸣", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 0.08, true], [Stat.ATK, 0.03, true], [Stat.ATK, 0.12, true], 0, 0, 0],
  ["O063", "钥匙守护者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [109, 0.05, true], [109, 0.03, true], [109, 0.08, true], 0, 0, 0],
  ["O064", "记忆转化", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [Stat.ATK, 0.02, true], [Stat.ATK, 0.05, true], [Stat.ATK, 0.03, true], 0, 0, 0],
  ["O065", "金币替身", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [Stat.DEF, 27.3, false], [107, 3, false], [107, 0.05, true], [107, 2, false], 2, 0, 0],
  ["O066", "护盾强化", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [Stat.DEF, 227.5, false], [Stat.CRD, 0.05, true], [Stat.ATK, 0.04, true], [Stat.ATK, 0.1, true], 0, 0, 0],
]
