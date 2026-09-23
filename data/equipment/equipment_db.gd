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
static func _apply_affixes(t: EquipmentTemplate, base, devour, fusion, own = []) -> void:
	t.base_affixes = _make_affix_list(base)
	t.devour_affixes = _make_affix_list(devour)
	t.fusion_affixes = _make_affix_list(fusion)
	t.own_affixes = _make_affix_list(own)
	t.trigger_affixes = _generate_trigger_affixes(t.rarity, str(t.id))


## 子表 → AffixData 列表。
##
## **向后兼容**：旧表传的是单条（`[stat, value, is_percent]`），
## 新表传的是子表（`[[...], [...]]`）。按首元素类型区分：
## 首元素是 Array → 子表；否则 → 单条，包成一项。
static func _make_affix_list(spec) -> Array[AffixData]:
	var out: Array[AffixData] = []
	if spec == null:
		return out
	if spec is Array and spec.size() > 0 and spec[0] is Array:
		for one in spec:
			var a := _make_one_affix(one)
			if a != null:
				out.append(a)
	elif spec is Array and spec.size() >= 3:
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
			AffixData.Operation.TRIGGER_BUFF:
				a.trigger_buff = str(spec[1])
				a.trigger_chance = float(spec[2]) if spec.size() > 2 else 0.0
				a.trigger_duration = float(spec[3]) if spec.size() > 3 else 0.0
			AffixData.Operation.PERIODIC:
				a.value = float(spec[1]) if spec.size() > 1 else 0.0
				a.trigger_buff = str(spec[2]) if spec.size() > 2 else ""
				a.duration = float(spec[3]) if spec.size() > 3 else 0.0
			AffixData.Operation.CHARGE:
				a.stat = int(spec[1])
				a.value = float(spec[2]) if spec.size() > 2 else 0.0
				a.full_stack_bonus = float(spec[3]) if spec.size() > 3 else 0.0
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
		# 注意参数顺序：_apply_affixes(base, devour, fusion, own)
		_apply_affixes(t, row[6], row[8], row[9], row[7])


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
  ["G000", "被腐蚀的长剑", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 56.0, false]], [[4, 1, Stat.ATK, 0.01, 0]], [[Stat.ATK, 0.0050, true]], [[Stat.ATK, 0.1000, true]]],
  ["G001", "饮血重剑", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 89.6, false]], [[100, 0.1000, true]], [[100, 0.0050, true]], [[4, 3, Stat.HP, 0.0500, 0]]],
  ["G002", "烈焰法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "fire", 0.5000]], [[117, 0.0100, true]], [[3, "fire", 0.1000]]],
  ["G003", "寒霜法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "frost", 0.5000]], [[117, 0.0100, true]], [[3, "frost", 0.1000]]],
  ["G004", "雷霆法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "static", 0.5000]], [[117, 0.0100, true]], [[3, "static", 0.1000]]],
  ["G005", "剧毒法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "poison", 0.5000]], [[117, 0.0100, true]], [[3, "poison", 0.1000]]],
  ["G006", "大地法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "earth", 0.5000]], [[117, 0.0100, true]], [[3, "earth", 0.1000]]],
  ["G007", "疾风法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[3, "wind", 0.5000]], [[117, 0.0100, true]], [[3, "wind", 0.1000]]],
  ["G008", "嗜血匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 42.0, false]], [[100, 0.0500, true]], [[100, 0.0050, true]], [[4, 6, Stat.HP, 0.1000, 0]]],
  ["G009", "荆棘长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 56.0, false]], [[2, "slow", 1.0, 2.0]], [[Stat.SPD, 0.0050, true]], [[2, "entangle", 0.2000, 1.0]]],
  ["G010", "腐蚀头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[4, 2, Stat.DEF, 0.0100, 5]], [[Stat.DEF, 0.0050, true]], [[104, 0.5000, true]]],
  ["G011", "吸血脉甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[4, 3, Stat.HP, 0.0200, 0]], [[Stat.HP, 0.0050, true]], [[Stat.ATK, 0.2000, true]]],
  ["G012", "荆棘肩甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[104, 0.1000, true]], [[Stat.DEF, 0.0050, true]], [[104, 0.5000, true]]],
  ["G013", "迅捷护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[Stat.ASPD, 0.0500, true]], [[Stat.ASPD, 0.0050, true]], [[Stat.ASPD, 0.1000, true]]],
  ["G014", "坚韧腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[112, 0.1000, true]], [[106, 0.0050, true]], [[112, 0.50, true]]],
  ["G015", "踏风战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[Stat.SPD, 0.0500, true]], [[Stat.SPD, 0.0050, true]], [[Stat.SPD, 0.2000, true]]],
  ["G016", "嗜血项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[100, 0.0300, true]], [[100, 0.0050, true]], [[4, 6, Stat.HP, 0.0500, 0]]],
  ["G017", "元素指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[117, 0.0500, true]], [[117, 0.0050, true]], [[117, 0.5000, true]]],
  ["G018", "守护护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [], [], []],
  ["G019", "淘金者之镐", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[2, "bonus_gold", 0.0500, 0.0]], [[107, 0.0050, true]], [[4, 1, 107, 0.0100, 5]]],
  ["G020", "寻宝者背包", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[114, 0.0300, true]], [[114, 0.0030, true]], [[114, 0.1000, true]]],
  ["G021", "破碎的钥匙链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[109, 0.0200, true]], [[109, 0.0020, true]], [[109, 0.0500, true]]],
  ["G022", "记忆碎片护符", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[4, 1, 119, 0.0100, 0]], [[119, 0.0050, true]], [[119, 0.0500, true]]],
  ["G023", "冷却沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[Stat.CDR, 0.0100, true]], [[Stat.CDR, 0.0020, true]], [[Stat.CDR, 0.20, true]]],
  ["G024", "迅捷之翼", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[Stat.CDR, 0.0500, true]], [[Stat.SPD, 0.0030, true]], [[Stat.SPD, 0.0500, true]]],
  ["G025", "冰霜护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[2, "freeze", 0.0500, 1.0]], [[117, 0.0050, true]], [[117, 0.0500, true]]],
  ["G026", "烈焰之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[106, 0.0300, true]], [[106, 0.0050, true]], [[2, "burn", 0.1000, 3.0]]],
  ["G027", "荆棘之甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[104, 0.0300, true]], [[Stat.DEF, 0.0050, true]], [[2, "bleed", 0.1000, 3.0]]],
  ["G028", "生命之泉护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[100, 0.0050, true]], [[100, 0.0050, true]], [[4, 1, Stat.HP, 0.0100, 0]]],
  ["G029", "元素抗性披风", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[106, 0.0300, true]], [[106, 0.0050, true]], [[106, 0.1000, true]]],
  ["G030", "贪婪之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[108, 0.0200, true]], [[108, 0.0050, true]], [[107, 0.0500, true]]],
  ["G031", "召唤师之戒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[116, 0.0300, true]], [[116, 0.0050, true]], []],
  ["G032", "时光沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[102, 0.0300, true]], [[102, 0.0050, true]], [[102, 0.10, true]]],
  ["G033", "瘟疫之触", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[2, "poison_rot", 0.0500, 3.0]], [[117, 0.0030, true]], [[2, "burn", 0.30, 3.0]]],
  ["G034", "冻结之息", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[2, "slow", 0.0500, 3.0]], [[117, 0.0030, true]], [[2, "freeze", 1.0, 1.0]]],
  ["G035", "灼烧烙印", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[2, "burn", 0.0500, 3.0]], [[117, 0.0030, true]], [[105, 0.0500, true]]],
  ["G036", "虚弱诅咒", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[2, "fatigue", 0.0500, 3.0]], [[102, 0.0030, true]], [[2, "burn", 0.30, 3.0]]],
  ["G037", "护盾发生器", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 56.0, false]], [[106, 0.0500, true]], [[106, 0.0050, true]], []],
  ["G038", "格挡者之盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 56.0, false]], [[110, 0.0300, true]], [[110, 0.0030, true]], [[117, 0.1000, true]]],
  ["G039", "闪避之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 6.7, false]], [[113, 0.0500, true]], [[111, 0.0030, true]], [[Stat.SPD, 0.0500, true]]],
  ["G040", "荆棘护盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 56.0, false]], [], [[106, 0.0050, true]], []],
  ["G041", "连击指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[4, 7, Stat.ATK, 0.0100, 5]], [[4, 7, Stat.ATK, 0.0030, 0]], [[4, 3, Stat.ATK, 0.50, 0]]],
  ["G042", "处决者之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 56.0, false]], [[105, 0.1000, true]], [[105, 0.0020, true]], [[4, 1, Stat.HP, 0.0500, 0]]],
  ["G043", "背刺匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 42.0, false]], [[Stat.CRD, 0.1000, true]], [[105, 0.0050, true]], [[111, 0.2000, true]]],
  ["G044", "弱点探测器", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[2, "mark", 0.0500, 3.0]], [[105, 0.0020, true]], [[2, "burn", 0.30, 3.0]]],
  ["G045", "分裂箭袋", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[117, 0.0500, true]], [[117, 0.0030, true]], [[117, 0.1000, true]]],
  ["G046", "穿透弹头", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 56.0, false]], [[103, 0.0500, true]], [[103, 0.0020, true]], [[117, 0.1000, true]]],
  ["G047", "爆炸符文", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 72.8, false]], [[117, 0.3000, true]], [[117, 0.0030, true]], [[117, 0.5000, true]]],
  ["G048", "远程精准镜", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[117, 0.0300, true]], [[117, 0.0030, true]], [[4, 1, Stat.CRT, 0.50, 0]]],
  ["G049", "元素穿透指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [[103, 0.0300, true]], [[103, 0.0030, true]], [[103, 0.30, true]]],
  ["G050", "真实伤害护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 6.7, false]], [], [], []],
  ["B000", "暗影短刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [[117, 0.0800, true]], [[105, 0.0500, true]], [[113, 1.0, true]]],
  ["B001", "穿刺长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[103, 0.4000, true]], [[103, 0.1000, true]], [[103, 0.30, true]]],
  ["B002", "裂地战斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[3, "earth", 0.50]], [[3, "earth", 0.10]], [[117, 0.3000, true]]],
  ["B003", "元素调和法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[117, 0.0200, true]], [[106, 0.1000, true]]],
  ["B004", "巨兽猎手", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[105, 0.1500, true], [2, "entangle", 0.0600, 1.5]], [[105, 0.0300, true]], [[103, 0.2000, true]]],
  ["B005", "圣光壁垒", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [], [[110, 0.0300, true]], [[100, 0.1000, true]]],
  ["B006", "疾风长矛", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[117, 0.2000, true], [3, "wind", 0.3000]], [[117, 0.0200, true]], [[117, 0.5000, true]]],
  ["B007", "噬魂战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[4, 1, Stat.ATK, 0.0300, 5], [4, 5, Stat.ATK, 2.0000, 0]], [[4, 1, Stat.HP, 0.0050, 0]], [[117, 0.2000, true]]],
  ["B008", "暗影斗篷", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[111, 0.1000, true]], [[111, 0.1000, true]], [[111, 0.1000, true]]],
  ["B009", "荆棘头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[104, 0.3000, true]], [[Stat.DEF, 0.0200, true]], [[104, 0.2000, true]]],
  ["B010", "守护肩甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[106, 0.2000, true]], [[117, 0.0100, true]], [[106, 0.1500, true]]],
  ["B011", "迅捷护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[Stat.ASPD, 0.0800, true], [4, 3, Stat.ASPD, 0.0200, 5]], [[Stat.ASPD, 0.0100, true]], [[4, 3, Stat.ATK, 0.50, 0]]],
  ["B012", "坚韧腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[112, 0.3000, true], [106, 0.1000, true]], [[106, 0.0200, true]], [[112, 0.30, true]]],
  ["B013", "踏风战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[Stat.SPD, 0.0200, true]], []],
  ["B014", "巨型方盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [], [[111, 0.0500, true]], [[106, 0.3000, true]]],
  ["B015", "元素指环", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[117, 0.0800, true], [117, 1.0000, true]], [[117, 0.0100, true]], [[2, "burn", 0.15, 3.0]]],
  ["B016", "猎手徽章", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[105, 0.2000, true], [Stat.CRT, 0.1500, true]], [[Stat.CRT, 0.0100, true]], [[113, 1.0, true]]],
  ["B017", "守护护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[4, 2, Stat.HP, 0.2000, 0]], [[Stat.HP, 0.0200, true]], [[111, 0.5000, true]]],
  ["B018", "贪婪之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[107, 0.1500, true], [108, 0.1000, true]], [[107, 0.0200, true]], [[107, 0.0500, true]]],
  ["B019", "唤灵短杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[116, 0.0200, true]], [[117, 1.0000, true]]],
  ["B020", "捕兽长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[2, "entangle", 0.0800, 1.5]], [[117, 0.0200, true]], []],
  ["B021", "反伤巨剑", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[104, 0.3000, true]], [[104, 0.0200, true]], [[112, 0.30, true]]],
  ["B022", "空间匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [[117, 0.5000, true]], [[117, 0.0200, true]], [[117, 0.3000, true]]],
  ["B023", "标记重弩", "heavy_crossbow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[2, "mark", 0.0800, 5.0]], [[117, 0.0100, true]], [[2, "burn", 0.30, 3.0]]],
  ["B024", "元素战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[3, "fire", 0.3000]], [[117, 0.0200, true]], [[117, 1.5000, true]]],
  ["B025", "守护者之盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [[4, 9, 106, 0.0200, 5]], [[110, 0.0200, true]], [[111, 0.5000, true]]],
  ["B026", "毒牙短刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [[2, "poison_rot", 0.0800, 3.0]], [[117, 0.0200, true]], [[2, "burn", 0.30, 3.0]]],
  ["B027", "雷霆战锤", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[117, 0.8000, true]], [[117, 0.0200, true]], [[2, "paralyze", 0.2000, 1.0]]],
  ["B028", "疾风双刃", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[Stat.ASPD, 0.1000, true], [4, 7, Stat.ATK, 0.0200, 5]], [[Stat.ASPD, 0.0100, true]], [[4, 3, Stat.ATK, 0.50, 0]]],
  ["B029", "灵魂收割者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[4, 1, Stat.ATK, 0.0100, 10], [4, 5, Stat.ATK, 2.0000, 0]], [[4, 1, Stat.HP, 0.0050, 0]], [[4, 3, Stat.HP, 0.1000, 0]]],
  ["B030", "冰霜长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [[2, "freeze", 0.0800, 1.0], [117, 0.2000, true]], [[117, 0.0200, true]], [[117, 1.0000, true]]],
  ["B031", "暗影法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[117, 0.0200, true]], [[2, "slow", 1.0, 3.0]]],
  ["B032", "荆棘链刃", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[2, "entangle", 0.0800, 1.0], [117, 0.1000, true]], [[102, 0.20, true]], [[117, 0.5000, true]]],
  ["B033", "圣光权杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[100, 0.0200, true]], [[115, 0.2000, true]]],
  ["B034", "陷阱头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[115, 0.2000, true], [106, 0.1000, true]], [[106, 0.0200, true]], [[111, 0.2000, true]]],
  ["B035", "召唤胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[4, 1, Stat.HP, 0.0500, 0]], [[116, 0.0200, true]], [[116, 0.10, true]]],
  ["B036", "反伤肩甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[104, 0.2000, true]], [[104, 0.0200, true]], []],
  ["B037", "护盾护手", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [[106, 0.0500, true]], [[106, 0.0200, true]], []],
  ["B038", "资源腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[4, 1, 119, 0.0300, 0]], [[119, 0.0200, true]], [[Stat.SPD, 0.1500, true]]],
  ["B039", "位移战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[Stat.CDR, 0.1000, true], [111, 0.0500, true]], [[Stat.SPD, 0.0200, true]], [[117, 0.3000, true]]],
  ["B040", "标记头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[2, "mark", 0.0600, 5.0]], [[105, 0.0100, true]], [[2, "burn", 0.30, 3.0]]],
  ["B041", "元素抗性胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[106, 0.0500, true], [106, 0.0500, true]], [[106, 0.0100, true]], []],
  ["B042", "经济肩甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[107, 0.1000, true], [107, 0.0500, true]], [[107, 0.0200, true]], [[107, 0.2000, true]]],
  ["B043", "钥匙护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[109, 0.0300, true]], [[109, 0.0100, true]], [[109, 0.1000, true]]],
  ["B044", "记忆腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[4, 1, 119, 0.0100, 0]], [[119, 0.0200, true]], [[119, 0.0500, true]]],
  ["B045", "召唤战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[116, 0.1000, true]], [[116, 0.0200, true]], []],
  ["B046", "护盾头盔", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [[106, 0.1000, true]], [[106, 0.0200, true]], []],
  ["B047", "反伤胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [[104, 0.1000, true], [104, 0.20, true]], [[104, 0.0200, true]], [[104, 0.1000, true]]],
  ["B048", "召唤戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[116, 0.1000, true], [120, 1, false]], [[116, 0.0200, true]], [[116, 0.1000, true]]],
  ["B049", "陷阱护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[117, 0.1500, true], [117, 0.2000, true]], [[117, 0.0200, true]], []],
  ["B050", "反伤徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[104, 0.1000, true], [104, 0.20, true]], [[104, 0.0200, true]], [[104, 0.1000, true]]],
  ["B051", "资源项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[119, 0.1000, true], [119, 0.1000, true]], [[119, 0.0200, true]], [[117, 0.1500, true]]],
  ["B052", "位移戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[Stat.SPD, 0.1000, true], [Stat.CDR, 0.0500, true]], [[Stat.SPD, 0.0200, true]], [[4, 3, Stat.ATK, 0.3000, 0]]],
  ["B053", "标记护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[2, "mark", 0.0600, 5.0]], [[105, 0.0100, true]], [[4, 1, Stat.HP, 0.0500, 0]]],
  ["B054", "元素戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[117, 0.0800, true], [117, 0.8000, true]], [[117, 0.0200, true]], [[2, "burn", 0.15, 3.0]]],
  ["B055", "经济项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[107, 0.1500, true], [108, 0.1000, true]], [[107, 0.0200, true]], [[107, 0.0500, true]]],
  ["B056", "钥匙徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [[109, 0.0300, true]], [[109, 0.0100, true]], [[109, 0.1000, true]]],
  ["B057", "野蛮冲撞战斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [], [[Stat.ATK, 0.0200, true]], [[117, 0.3000, true]]],
  ["B058", "影闪匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [], [[105, 0.0300, true]], [[Stat.CRT, 0.2000, true]]],
  ["B059", "火球法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[117, 0.0200, true]], [[117, 2.0000, true]]],
  ["B060", "冰霜陷阱长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [], [[117, 0.0200, true]], [[117, 0.5000, true]]],
  ["B061", "雷霆一击战锤", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [], [[117, 0.0200, true]], [[102, 0.30, true]]],
  ["B062", "治疗之光权杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[100, 0.0200, true]], []],
  ["B063", "召唤狼灵法书", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[116, 0.0200, true]], [[2, "bleed", 0.1000, 3.0]]],
  ["B064", "盾牌冲锋长矛", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [], [[110, 0.0200, true]], []],
  ["B065", "毒雾短刃", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [], [[117, 0.0200, true]], [[2, "slow", 1.0, 3.0]]],
  ["B066", "旋风双斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [], [[Stat.ASPD, 0.0100, true]], []],
  ["B067", "圣光新星法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[Stat.AP, 0.0200, true]], [[105, 0.5000, true]]],
  ["B068", "暗影突袭链刃", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [], [[117, 0.0200, true]], [[117, 0.1500, true]]],
  ["B069", "爆裂射击重弩", "heavy_crossbow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [], [[117, 0.0200, true]], [[117, 0.1000, true]]],
  ["B070", "风之箭长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [], [[117, 0.0200, true]], [[117, 0.1500, true]]],
  ["B071", "地刺法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[117, 0.0200, true]], [[2, "stun", 1.0, 0.5]]],
  ["B072", "灵魂吸取战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [], [[100, 0.0200, true]], [[4, 3, Stat.HP, 0.05, 0]]],
  ["B073", "无畏冲锋胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[Stat.HP, 0.0200, true]], [[106, 0.0500, true]]],
  ["B074", "闪现战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[Stat.SPD, 0.0200, true]], [[4, 3, Stat.ATK, 0.3000, 0]]],
  ["B075", "生命链接护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[100, 0.0200, true]], [[106, 0.05, true]]],
  ["B076", "能量护盾肩甲", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [], [[106, 0.0200, true]], []],
  ["B077", "荆棘爆发头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[104, 0.0200, true]], []],
  ["B078", "战吼腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[Stat.DEF, 0.0200, true]], []],
  ["B079", "烟雾弹头盔", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [], [[111, 0.0200, true]], [[Stat.SPD, 0.20, true]]],
  ["B080", "召唤护卫胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[116, 0.0100, true]], [[117, 0.4000, true]]],
  ["B081", "反击姿态护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[110, 0.0200, true]], []],
  ["B082", "疾风步腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[Stat.SPD, 0.0200, true]], []],
  ["B083", "冰霜新星胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[117, 0.0100, true]], [[117, 0.1000, true]]],
  ["B084", "火焰吐息头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[117, 0.0100, true]], [[117, 0.2000, true]]],
  ["B085", "治疗之泉战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[100, 0.0100, true]], []],
  ["B086", "暗影步斗篷", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[117, 0.0200, true]], [[112, 0.30, true]]],
  ["B087", "加速护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [], [[Stat.ASPD, 0.0100, true]], []],
  ["B088", "元素爆发戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [], [[117, 0.0100, true]], [[2, "burn", 0.15, 3.0]]],
  ["B089", "护盾术项链", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [], [[106, 0.0100, true]], []],
  ["B090", "传送戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [], [[Stat.SPD, 0.0100, true]], [[111, 0.1500, true]]],
  ["B091", "治愈术护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [], [[100, 0.0100, true]], []],
  ["B092", "荆棘领域徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [], [[104, 0.0100, true]], [[2, "slow", 1.0, 3.0]]],
  ["B093", "资源爆发项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [], [[119, 0.0200, true]], [[117, 0.2000, true]]],
  ["B094", "时间减缓沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [], [[Stat.CDR, 0.0100, true]], []],
  ["B095", "挑衅战锤", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [], [[Stat.DEF, 0.0100, true]], []],
  ["B096", "投掷飞斧", "axe", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [], [[Stat.ATK, 0.0100, true]], [[117, 0.1500, true]]],
  ["B097", "缠绕藤蔓法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[117, 0.0100, true]], [[117, 0.3000, true]]],
  ["B098", "驱散之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [], [[106, 0.0100, true]], [[106, 0.1000, true]]],
  ["B099", "沉默重弩", "heavy_crossbow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [], [[105, 0.0100, true]], [[2, "slow", 1.0, 3.0]]],
  ["B100", "净化法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[100, 0.0100, true]], []],
  ["B101", "锁链拖拽链刃", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [], [[Stat.ASPD, 0.0100, true]], [[117, 0.1000, true]]],
  ["B102", "击退长矛", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [], [[Stat.ATK, 0.0100, true]], [[101, 0.5000, true]]],
  ["B103", "生命汲取战镰", "scythe", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [], [[100, 0.0100, true]], [[4, 3, Stat.HP, 0.05, 0]]],
  ["B104", "火焰喷射法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[117, 0.0100, true]], [[117, 0.2000, true]]],
  ["B105", "冰锥术法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[117, 0.0100, true]], [[117, 0.2000, true]]],
  ["B106", "落石术法环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[117, 0.0100, true]], [[2, "stun", 1.0, 0.5]]],
  ["B107", "风刃长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [], [[117, 0.0100, true]], [[117, 0.1500, true]]],
  ["B108", "雷霆标枪", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 87.5, false]], [], [[117, 0.0100, true]], [[117, 0.5000, true]]],
  ["B109", "暗影箭匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 65.6, false]], [], [[117, 0.0100, true]], [[4, 1, Stat.HP, 0.0300, 0]]],
  ["B110", "治疗图腾法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 113.8, false]], [], [[100, 0.0100, true]], []],
  ["B111", "石肤胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[Stat.DEF, 0.0100, true]], [[112, 0.30, true]]],
  ["B112", "疾跑战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[Stat.SPD, 0.0100, true]], []],
  ["B113", "护盾发生器肩甲", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [], [[106, 0.0100, true]], []],
  ["B114", "烟雾弹护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[111, 0.0100, true]], [[Stat.SPD, 0.20, true]]],
  ["B115", "战吼头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[Stat.DEF, 0.0100, true]], []],
  ["B116", "荆棘护盾腿甲", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 87.5, false]], [], [[104, 0.0100, true]], []],
  ["B117", "生命链接护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [], [[Stat.HP, 0.0100, true]], [[106, 0.05, true]]],
  ["B118", "闪现护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[Stat.SPD, 0.0100, true]], [[4, 3, Stat.ATK, 0.2000, 0]]],
  ["B119", "净化腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[106, 0.0100, true]], [[106, 0.1000, true]]],
  ["B120", "反击姿态肩甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 10.5, false]], [], [[110, 0.0100, true]], []],
  ["B121", "资源回复项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 10.5, false]], [], [[119, 0.0100, true]], [[119, 0.1500, true]]],
  ["P000", "腐蚀之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[2, "burn", 0.1500, 4.0], [117, 0.0500, true]], [[117, 0.0300, true]], [[117, 0.8000, true]]],
  ["P001", "血怒巨斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[118, 2.0000, true], [4, 1, Stat.HP, 0.1500, 0]], [[100, 0.0300, true]], [[117, 0.2500, true]]],
  ["P002", "影舞匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 105.0, false]], [[105, 0.6000, true], [Stat.ASPD, 0.0400, true]], [[105, 0.0300, true]], [[Stat.CRD, 0.30, true]]],
  ["P003", "猎杀者长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[117, 0.0400, true], [Stat.CRT, 0.30, true]], [[117, 0.0300, true]], [[105, 0.0500, true]]],
  ["P004", "不灭壁垒", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 140.0, false]], [[117, 0.0200, true], [106, 0.2000, true]], [[Stat.DEF, 0.0300, true]], []],
  ["P005", "预言者头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 6, Stat.CRD, 0.0300, 5], [117, 0.5000, true]], [[Stat.CRT, 0.0200, true]], [[113, 0.0500, true]]],
  ["P006", "踏虚战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[116, 0.10, true], [111, 0.0500, true]], [[Stat.SPD, 0.0300, true]], [[113, 1.0, true]]],
  ["P007", "元素之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[106, 0.1000, true], [117, 0.1500, true]], [[106, 0.0200, true]], [[3, "fire", 0.3000]]],
  ["P008", "霜噬巨剑", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[117, 0.0400, true], [4, 3, Stat.ATK, 2.0000, 8]], [[117, 0.0300, true]], [[2, "freeze", 1.0, 1.5]]],
  ["P009", "雷霆之怒", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[2, "paralyze", 0.1500, 1.0], [117, 0.6000, true]], [[117, 0.0300, true]], [[117, 0.1500, true]]],
  ["P010", "剧毒之牙", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[2, "poison_rot", 1.0, 5.0], [4, 3, Stat.ATK, 0.8000, 5]], [[117, 0.0300, true]], [[117, 0.2000, true]]],
  ["P011", "大地震击", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[117, 0.5000, true], [117, 0.3000, true]], [[117, 0.0300, true]], [[2, "stun", 0.1500, 1.0]]],
  ["P012", "风语长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[3, "wind", 0.3000], [2, "pull", 1.0, 0.0]], [[117, 0.0300, true]], [[117, 1.5000, true]]],
  ["P013", "暗影收割者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[4, 1, Stat.ATK, 0.0200, 15], [4, 5, Stat.ATK, 2.0000, 0]], [[117, 0.0300, true]], [[4, 15, Stat.ATK, 0.02, 0]]],
  ["P014", "虚空之刺", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[103, 0.3000, true], [117, 0.2000, true]], [[103, 0.0300, true]], [[103, 1.0000, true]]],
  ["P015", "混沌之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[3, "fire", 0.5000], [117, 1.5000, true]], [[117, 0.0300, true]], [[2, "burn", 0.30, 3.0]]],
  ["P016", "生命之弦", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[4, 3, Stat.HP, 0.0100, 0], [106, 0.1000, true]], [[100, 0.0300, true]], []],
  ["P017", "破晓之光", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[103, 1.0000, true]], [[117, 0.0300, true]], [[117, 0.5000, true]]],
  ["P018", "深渊低语", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[116, 0.10, true]], [[116, 0.0300, true]], [[116, 0.10, true]]],
  ["P019", "星辰碎片", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[117, 0.8000, true]], [[117, 0.0300, true]], [[117, 1.2000, true]]],
  ["P020", "复仇之刺", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[4, 2, Stat.ATK, 0.0500, 5], [Stat.CRD, 0.30, true]], [[105, 0.0300, true]], [[Stat.CRD, 0.30, true]]],
  ["P021", "冰霜之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[106, 0.1000, true]], [[106, 0.0300, true]], []],
  ["P022", "烈焰之魂", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[2, "burn", 1.0, 3.0], [117, 0.5000, true]], [[117, 0.0300, true]], [[117, 0.1000, true]]],
  ["P023", "雷霆护肩", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 2, Stat.ATK, 0.02, 5], [4, 5, Stat.ATK, 1.0000, 0]], [[117, 0.0300, true]], [[4, 15, Stat.ATK, 0.02, 0]]],
  ["P024", "大地守护", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.DEF, 0.0300, true]], [[106, 0.05, true]]],
  ["P025", "风行者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[4, 10, Stat.SPD, 0.0200, 0], [3, "wind", 1.0000]], [[Stat.SPD, 0.0300, true]], [[Stat.SPD, 0.10, true]]],
  ["P026", "暗影斗篷", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[111, 0.30, true], [Stat.CRT, 0.3000, true]], [[Stat.CRT, 0.0200, true]], [[111, 0.30, true]]],
  ["P027", "圣光护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[106, 0.3000, true]], [[100, 0.0300, true]], []],
  ["P028", "虚空之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[103, 0.1500, true], [117, 0.0500, true]], [[103, 0.0300, true]], [[117, 0.1000, true]]],
  ["P029", "混沌之皮", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[106, 0.3000, true]], [[106, 0.0300, true]], [[117, 0.5000, true]]],
  ["P030", "生命之树", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[100, 0.0100, true], [100, 0.1000, true]], [[100, 0.0300, true]], []],
  ["P031", "星辰披风", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[104, 0.5000, true]], [[111, 0.0200, true]], [[111, 0.1000, true]]],
  ["P032", "复仇之甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[4, 2, Stat.ATK, 0.0200, 10], [4, 5, Stat.ATK, 1.5000, 0]], [[Stat.ATK, 0.0200, true]], [[4, 3, Stat.HP, 0.0500, 0]]],
  ["P033", "元素调和者", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[117, 0.1500, true]], [[117, 0.0300, true]], [[4, 5, Stat.ATK, 1.0000, 0]]],
  ["P034", "灵魂锁链", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[4, 1, Stat.ATK, 0.0200, 10], [119, 0.50, true]], [[119, 0.0300, true]], [[4, 15, Stat.ATK, 0.2000, 0]]],
  ["P035", "荆棘之环", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[104, 0.1500, true], [117, 0.1000, true]], [[104, 0.0300, true]], [[104, 0.1500, true]]],
  ["P036", "猎杀者徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[Stat.CRT, 0.0300, true], [4, 3, Stat.CRT, 0.50, 0]], [[Stat.CRT, 0.0200, true]], [[105, 0.0500, true]]],
  ["P037", "元素之戒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[117, 0.2000, true]], [[117, 0.0300, true]], [[117, 1.5000, true]]],
  ["P038", "生命之泉", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[100, 0.0300, true]], []],
  ["P039", "时空沙漏", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[Stat.CDR, 0.0800, true], [Stat.CDR, 0.20, true]], [[Stat.CDR, 0.0200, true]], [[119, 1.0, true]]],
  ["P040", "贪婪之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[Stat.ATK, 0.0100, true]], [[107, 0.0300, true]], [[Stat.CRT, 0.1000, true]]],
  ["P041", "记忆碎片", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[4, 1, 119, 0.0200, 0], [Stat.ATK, 0.0050, true]], [[119, 0.0300, true]], [[119, 0.1000, true]]],
  ["P042", "钥匙守护", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[109, 0.0500, true], [Stat.ATK, 0.0200, true]], [[109, 0.0200, true]], [[109, 0.1500, true]]],
  ["P043", "召唤师之核", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[120, 1, false], [116, 0.0500, true]], [[116, 0.0300, true]], [[116, 0.10, true]]],
  ["P044", "荆棘领域", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[104, 0.0300, true]], [[2, "slow", 1.0, 3.0]]],
  ["P045", "格挡反击者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[4, 9, Stat.ATK, 0.0600, 5], [4, 3, Stat.CRT, 0.50, 0]], [[110, 0.0200, true]], [[104, 0.5000, true]]],
  ["P046", "分裂弩", "heavy_crossbow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[117, 0.2000, true], [117, 0.3000, true]], [[117, 0.0300, true]], [[117, 0.1000, true]]],
  ["P047", "连击双刃", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[4, 7, Stat.ATK, 0.0300, 8], [4, 5, Stat.ATK, 0.40, 0]], [[Stat.ASPD, 0.0200, true]], [[Stat.ASPD, 0.10, true]]],
  ["P048", "蓄能战锤", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 224.0, false]], [[6, Stat.ATK, 0.15, 1.50], [6, Stat.ATK, 0.15, 1.50]], [[Stat.ATK, 0.0300, true]], [[117, 0.50, true]]],
  ["P049", "荆棘长鞭", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[2, "poison_rot", 1.0, 4.0], [117, 0.1500, true]], [[117, 0.0300, true]], [[2, "bleed", 0.30, 3.0]]],
  ["P050", "猎手标枪", "spear", ["近战", "双手", "长杆", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 140.0, false]], [[116, 0.10, true], [117, 0.1500, true]], [[117, 0.0300, true]], [[117, 0.1500, true]]],
  ["P051", "元素之泉法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [[117, 0.2500, true], [Stat.ATK, -0.1000, true]], [[117, 0.0300, true]], [[2, "burn", 0.15, 3.0]]],
  ["P052", "格挡者壁垒", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 140.0, false]], [[4, 9, 106, 0.0300, 5], [106, 0.2000, true]], [[110, 0.0200, true]], []],
  ["P053", "延迟伤害甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[106, 0.3000, true], [4, 1, Stat.ATK, 0.10, 0]], [[106, 0.0200, true]], [[4, 1, Stat.ATK, 0.10, 0]]],
  ["P054", "图腾护肩", "", [], EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[116, 0.10, true]], [[116, 0.0300, true]], [[116, 0.10, true]]],
  ["P055", "镜像腿甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[116, 0.10, true], [116, 0.3000, true]], [[Stat.SPD, 0.0300, true]], [[116, 0.10, true]]],
  ["P056", "吸血光环头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[100, 0.0500, true], [100, 0.1000, true]], [[100, 0.0200, true]], [[4, 1, Stat.HP, 0.0200, 0]]],
  ["P057", "减伤叠层胸甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[117, 0.0200, true], [112, 0.30, true]], [[Stat.DEF, 0.0300, true]], [[4, 2, Stat.HP, 0.30, 0]]],
  ["P058", "技能连发护手", "", [], EquipmentDefs.Slot.HANDS, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[Stat.CDR, 0.1500, true], [119, 1.0, true]], [[Stat.CDR, 0.0200, true]], [[2, "atk_up_self", 1.0, 0.0]]],
  ["P059", "陷阱大师战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 16.8, false]], [[116, 0.10, true]], [[117, 0.0300, true]], []],
  ["P060", "精英猎杀者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[105, 0.1500, true], [4, 1, Stat.ATK, 1.0000, 0]], [[105, 0.0300, true]], [[4, 1, Stat.HP, 0.1000, 0]]],
  ["P061", "处决者印记", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[117, 0.2500, true], [4, 1, Stat.HP, 0.0500, 0]], [[117, 0.0300, true]], [[113, 1.0, true]]],
  ["P062", "增益窃取者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[4, 1, Stat.ATK, 0.1000, 0], [117, 0.1000, true]], [[102, 0.0300, true]], [[117, 0.5000, true]]],
  ["P063", "多重射击徽章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [[117, 0.1500, true], [117, 0.10, true]], [[117, 0.0300, true]], [[117, 0.2000, true]]],
  ["P064", "伤害储存护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.1000, true]], [[117, 0.1000, true]]],
  ["P065", "裂空斩", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.ATK, 0.0300, true]], [[117, 2.5000, true]]],
  ["P066", "烈焰风暴", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[117, 0.2000, true]]],
  ["P067", "冰封领域", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[117, 0.1500, true]]],
  ["P068", "雷霆万钧", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[102, 0.30, true]]],
  ["P069", "暗影突袭", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[105, 0.0300, true]], [[113, 1.0, true]]],
  ["P070", "荆棘囚笼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[102, 0.0300, true]], [[117, 0.2000, true]]],
  ["P071", "圣光审判", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[100, 0.0300, true]], [[117, 0.5000, true]]],
  ["P072", "毒雾弹", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[2, "slow", 1.0, 3.0]]],
  ["P073", "旋风斩", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.ASPD, 0.0200, true]], []],
  ["P074", "穿透狙击", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[103, 0.0300, true]], [[117, 0.5000, true]]],
  ["P075", "星辰坠落", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[117, 0.3000, true]]],
  ["P076", "灵魂汲取", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[100, 0.0300, true]], [[4, 3, Stat.HP, 0.05, 0]]],
  ["P077", "风之屏障", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[110, 0.0300, true]], [[104, 0.5000, true]]],
  ["P078", "地裂术", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[2, "stun", 1.0, 0.8]]],
  ["P079", "爆裂箭雨", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[105, 0.1000, true]]],
  ["P080", "血怒爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.ATK, 0.0300, true]], [[4, 1, Stat.HP, 0.5000, 0]]],
  ["P081", "元素洪流", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[2, "burn", 0.15, 3.0]]],
  ["P082", "暗影分身", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[116, 0.0300, true]], [[116, 0.10, true]]],
  ["P083", "圣光护盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 140.0, false]], [], [[106, 0.0300, true]], []],
  ["P084", "时空加速", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.ASPD, 0.0200, true]], []],
  ["P085", "无畏冲锋", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.HP, 0.0300, true]], [[106, 0.1500, true]]],
  ["P086", "闪现", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.SPD, 0.0300, true]], [[4, 3, Stat.ATK, 0.4000, 0]]],
  ["P087", "能量护盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 140.0, false]], [], [[106, 0.0300, true]], []],
  ["P088", "荆棘爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[104, 0.0300, true]], []],
  ["P089", "战吼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.DEF, 0.0300, true]], []],
  ["P090", "烟雾弹", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[111, 0.0300, true]], [[Stat.CRT, 0.30, true]]],
  ["P091", "召唤守卫", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[116, 0.0300, true]], [[116, 0.10, true]]],
  ["P092", "反击姿态", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[110, 0.0300, true]], []],
  ["P093", "疾风步", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.SPD, 0.0300, true]], []],
  ["P094", "冰霜新星", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[117, 0.2000, true]]],
  ["P095", "火焰吐息", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[117, 0.4000, true]]],
  ["P096", "暗影步", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[112, 0.30, true]]],
  ["P097", "风暴之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[117, 0.1500, true]]],
  ["P098", "灵魂链接", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.HP, 0.0300, true]], [[106, 0.05, true]]],
  ["P099", "净化之光", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 182.0, false]], [], [[106, 0.0300, true]], [[112, 0.5000, true]]],
  ["P100", "元素爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[117, 0.0300, true]], [[2, "burn", 0.15, 3.0]]],
  ["P101", "召唤元素灵", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[116, 0.0300, true]], [[2, "burn", 0.30, 3.0]]],
  ["P102", "护盾术", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 140.0, false]], [], [[106, 0.0300, true]], []],
  ["P103", "传送", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.SPD, 0.0300, true]], [[111, 0.2000, true]]],
  ["P104", "治愈术", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[100, 0.0300, true]], []],
  ["P105", "资源爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[119, 0.0300, true]], [[117, 0.2500, true]]],
  ["P106", "时间减缓", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[Stat.CDR, 0.0200, true]], []],
  ["P107", "灵魂爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 16.8, false]], [], [[119, 0.0300, true]], [[4, 1, Stat.HP, 0.0500, 0]]],
  ["P108", "星辰护盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 140.0, false]], [], [[111, 0.0200, true]], [[104, 0.5000, true]]],
  ["O000", "血海狂潮", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[118, 3.0000, true], [Stat.ATK, 0.40, true]], [[100, 0.0500, true]], [[112, 0.30, true]]],
  ["O001", "影狱双刃", "greatsword", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 364.0, false]], [[116, 0.10, true], [Stat.CRD, 0.30, true], [Stat.CRD, 0.30, true]], [[105, 0.0500, true]], [[117, 0.3000, true]]],
  ["O002", "猎神长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[105, 0.0500, true], [Stat.CDR, 0.10, true]], [[117, 0.0500, true]], [[Stat.CRT, 0.30, true]]],
  ["O003", "不朽壁垒", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 227.5, false]], [[117, 0.0300, true], [4, 2, Stat.HP, 0.30, 0]], [[Stat.DEF, 0.0500, true]], [[106, 0.3000, true]]],
  ["O004", "预言者王冠", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 6, Stat.CRD, 0.0600, 6], [4, 3, Stat.CRT, 0.50, 0]], [[Stat.CRT, 0.0300, true]], [[Stat.CRT, 0.2000, true]]],
  ["O005", "踏虚神靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[106, 0.2000, true], [113, 1.0, true]], [[Stat.SPD, 0.0500, true]], [[4, 1, Stat.HP, 0.0300, 0]]],
  ["O006", "元素之心·终焉", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[106, 0.2000, true], [117, 0.2500, true], [117, 4.0000, true]], [[106, 0.0400, true]], [[106, 0.1500, true]]],
  ["O007", "灵魂王座", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 1, Stat.ATK, 0.0300, 20], [4, 15, Stat.ATK, 0.3000, 0], [4, 1, Stat.HP, 0.10, 0]], [[119, 0.0400, true]], [[4, 1, Stat.HP, 0.10, 0]]],
  ["O008", "处决者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[105, 0.3000, true], [4, 1, Stat.HP, 0.2000, 0]], [[Stat.ATK, 0.0500, true]], [[105, 0.4000, true]]],
  ["O009", "血怒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[Stat.ATK, 0.6000, true]], [[100, 0.0500, true]], [[106, 0.3000, true]]],
  ["O010", "元素洪流", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[117, 0.8000, true]], [[Stat.AP, 0.0500, true]], [[2, "atk_up_self", 1.0, 0.0]]],
  ["O011", "猎杀者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[105, 0.3000, true], [4, 1, Stat.ATK, 1.5000, 0]], [[117, 0.0500, true]], [[113, 1.0, true]]],
  ["O012", "不朽者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 2, Stat.HP, 0.5000, 0]], [[Stat.HP, 0.0500, true]], [[111, 0.5000, true]]],
  ["O013", "荆棘之王", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[104, 0.5000, true], [104, 0.20, true]], [[Stat.DEF, 0.0500, true]], [[104, 0.2000, true]]],
  ["O014", "疾风之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[Stat.CDR, 0.5000, true], [Stat.SPD, 0.5000, true]], [[Stat.SPD, 0.0500, true]], [[117, 1.0000, true]]],
  ["O015", "暴君之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[Stat.CRT, 0.2500, true], [4, 6, Stat.HP, 0.0300, 0]], [[Stat.CRT, 0.0300, true]], [[113, 0.0500, true]]],
  ["O016", "元素之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[117, 0.4000, true], [2, "burn", 0.15, 3.0]], [[117, 0.0500, true]], []],
  ["O017", "灵魂容器", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 1, Stat.HP, 0.1500, 0], [106, 0.3000, true]], [[119, 0.0500, true]], [[4, 1, Stat.HP, 0.2000, 0]]],
  ["O018", "裂地巨斧", "greataxe", ["近战", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 364.0, false]], [], [[Stat.ATK, 0.0500, true]], [[117, 0.2000, true]]],
  ["O019", "流星法杖", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 295.8, false]], [], [[Stat.AP, 0.0500, true]], [[117, 0.8000, true]]],
  ["O020", "影袭匕首", "dagger", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 170.6, false]], [], [[105, 0.0600, true]], [[113, 1.0, true]]],
  ["O021", "穿透长弓", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [], [[117, 0.0500, true]], [[117, 0.2000, true]]],
  ["O022", "钢铁之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [], [[Stat.HP, 0.0600, true]], [[112, 0.30, true]]],
  ["O023", "战吼头盔", "", [], EquipmentDefs.Slot.HEAD, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [], [[Stat.DEF, 0.0500, true]], []],
  ["O024", "疾风战靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [], [[Stat.SPD, 0.0500, true]], [[Stat.SPD, 0.5000, true]]],
  ["O025", "元素爆发戒指", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [], [[117, 0.0500, true]], [[2, "burn", 0.15, 3.0]]],
  ["O026", "治疗之泉项链", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [], [[100, 0.0600, true]], []],
  ["O027", "召唤守护者护符", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [], [[116, 0.0500, true]], [[117, 3.0000, true]]],
  ["O028", "弹射之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[117, 0.7000, true]], [[Stat.ATK, 0.0500, true]], [[117, 0.1500, true]]],
  ["O029", "连击之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[4, 7, Stat.ATK, 0.1500, 5]], [[Stat.ASPD, 0.0300, true]], [[4, 3, Stat.ATK, 0.50, 0]]],
  ["O030", "金币猎手", "bow", ["远程", "双手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[Stat.ATK, 1.00, true], [107, 0.1000, true]], [[107, 0.0500, true]], [[107, 0.1000, true]]],
  ["O031", "灵魂收割者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[116, 0.10, true]], [[116, 0.0500, true]], [[116, 0.10, true]]],
  ["O032", "双重打击", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[118, 0.2500, true]], [[Stat.ATK, 0.0500, true]], [[118, 0.2500, true]]],
  ["O033", "幸运之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[118, 0.1500, true]], [[Stat.CRT, 0.0300, true]], [[117, 0.2000, true]]],
  ["O034", "生命百分比之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[118, 0.0500, true]], [[Stat.ATK, 0.0500, true]], [[117, 0.2000, true]]],
  ["O035", "斩首者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[105, 0.6000, true]], [[Stat.ATK, 0.0500, true]], [[105, 1.0000, true]]],
  ["O036", "终结者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[105, 0.6000, true]], [[Stat.ATK, 0.0500, true]], [[117, 0.2000, true]]],
  ["O037", "血怒之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[Stat.ATK, 0.0800, true]], [[100, 0.0500, true]], [[Stat.ATK, 0.1200, true]]],
  ["O038", "吸血狂徒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[100, 0.3000, true]], [[100, 0.0500, true]], [[100, 0.5000, true]]],
  ["O039", "元素爆裂之刃", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[117, 2.5000, true]], [[117, 0.0500, true]], [[117, 0.2000, true]]],
  ["O040", "混沌之触", "staff", ["魔法", "双手", "长杆", "法术"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.AP, 295.8, false]], [[2, "burn", 0.15, 3.0]], [[117, 0.0500, true]], [[117, 0.2000, true]]],
  ["O041", "闪避新星", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[117, 2.0000, true]], [[Stat.SPD, 0.0500, true]], [[117, 0.2000, true]]],
  ["O042", "格挡反击者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[117, 1.0000, true]], [[110, 0.0300, true]], [[117, 0.5000, true]]],
  ["O043", "火焰行者", "sword", ["近战", "单手", "物理"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.ATK, 227.5, false]], [[117, 0.8000, true]], [[117, 0.0500, true]], [[117, 0.2000, true]]],
  ["O044", "闪电之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[117, 1.0000, true]], [[Stat.SPD, 0.0500, true]], [[117, 0.2000, true]]],
  ["O045", "元素附魔师", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[3, "fire", 0.50]], [[117, 0.0500, true]], [[117, 0.2000, true]]],
  ["O046", "冲击波之靴", "", [], EquipmentDefs.Slot.FEET, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[117, 2.0000, true]], [[Stat.SPD, 0.0500, true]], [[117, 1.0000, true]]],
  ["O047", "不动堡垒", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[106, 0.3000, true]], [[Stat.DEF, 0.0500, true]], [[106, 0.5000, true]]],
  ["O048", "冷却之眼", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[Stat.CDR, 0.20, true]], [[Stat.CDR, 0.0300, true]], [[Stat.CDR, 0.20, true]]],
  ["O049", "冲刺大师", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[113, 1.0, true]], [[Stat.SPD, 0.0500, true]], [[4, 3, Stat.ATK, 0.5000, 0]]],
  ["O050", "反击之甲", "", [], EquipmentDefs.Slot.CHEST, EquipmentDefs.Category.ARMOR, [[Stat.DEF, 27.3, false]], [[4, 2, Stat.ATK, 1.5000, 0]], [[Stat.DEF, 0.0500, true]], [[117, 1.0000, true]]],
  ["O051", "荆棘反弹", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[104, 2.0000, true]], [[110, 0.0300, true]], [[104, 1.0000, true]]],
  ["O052", "濒死新星", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[117, 3.0000, true]], [[Stat.HP, 0.0500, true]], [[117, 1.0000, true]]],
  ["O053", "伤害转盾", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 227.5, false]], [[106, 0.3000, true]], [[Stat.DEF, 0.0500, true]], [[106, 0.7000, true]]],
  ["O054", "护盾爆裂", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 227.5, false]], [], [[106, 0.0500, true]], [[117, 0.2000, true]]],
  ["O055", "猎杀者勋章", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 1, Stat.ATK, 0.15, 0]], [[Stat.ATK, 0.0300, true]], [[119, 0.5000, true]]],
  ["O056", "召唤领主", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [], [[116, 0.0500, true]], [[120, 1, false]]],
  ["O057", "资源爆发", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 3, Stat.ATK, 1.5000, 0]], [[119, 0.0500, true]], [[119, 0.2000, true]]],
  ["O058", "技能强化者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[2, "atk_up_self", 1.0, 0.0]], [[Stat.AP, 0.0500, true]], [[Stat.ATK, 1.5000, true]]],
  ["O059", "闪避强化者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[4, 4, Stat.ATK, 1.0000, 0]], [[111, 0.0300, true]], [[Stat.ATK, 1.5000, true]]],
  ["O060", "不死之身", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[111, 0.5000, true]], [[Stat.HP, 0.0500, true]], [[102, 0.30, true]]],
  ["O061", "贪婪之心", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[Stat.ATK, 0.0300, true]], [[107, 0.0500, true]], [[Stat.ATK, 0.0500, true]]],
  ["O062", "传奇共鸣", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[Stat.ATK, 0.0800, true]], [[Stat.ATK, 0.0300, true]], [[Stat.ATK, 0.10, true]]],
  ["O063", "钥匙守护者", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[Stat.ATK, 0.0500, true]], [[109, 0.0300, true]], [[Stat.ATK, 0.0800, true]]],
  ["O064", "记忆转化", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[Stat.ATK, 0.0200, true]], [[119, 0.0500, true]], [[Stat.ATK, 0.0300, true]]],
  ["O065", "金币替身", "", [], EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Category.ACCESSORY, [[Stat.DEF, 27.3, false]], [[107, 0.10, true]], [[107, 0.0500, true]], [[107, 0.2000, true]]],
  ["O066", "护盾强化", "shield", ["防御"], EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Category.WEAPON, [[Stat.DEF, 227.5, false]], [[Stat.ATK, 0.0500, true], [Stat.CRD, 0.1000, true]], [[Stat.ATK, 0.0400, true]], [[Stat.ATK, 0.10, true]]],

]
