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
const SPECIAL_STAT := {
	"lifesteal":    {"enum": 100, "out": "life_steal"},      # 造成伤害的 N% 转回血
	"knockback":    {"enum": 101, "out": "knockback_pct"},   # 击退距离 +N%
	"debuff_dur":   {"enum": 102, "out": "debuff_dur_pct"},  # 施加的负面词条时长 +N%
	"elem_pen":     {"enum": 103, "out": "elem_pen_pct"},    # 忽视目标 N% 元素抗性
	"reflect":      {"enum": 104, "out": "reflect_pct"},     # 受近战伤害反弹 N%
	"execute_line": {"enum": 105, "out": "execute_bonus"},   # 对低血目标增伤（分册 +30%）
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
static func _apply_affixes(t: EquipmentTemplate, base: Array, devour: Array, fusion: Array) -> void:
	t.base_affix = _make_affix(base)
	t.devour_affix = _make_affix(devour)
	t.fusion_affix = _make_affix(fusion)
	t.trigger_affixes = _generate_trigger_affixes(t.rarity, str(t.id))


## 构建词条数据
static func _make_affix(affix: Array) -> AffixData:
	var op := AffixData.Operation.PERCENT if affix[2] else AffixData.Operation.FLAT
	return AffixData.new(affix[0], affix[1], op)
