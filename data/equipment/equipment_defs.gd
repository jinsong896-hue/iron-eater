class_name EquipmentDefs
extends RefCounted
## 装备系统常量定义

enum Rarity {
	WHITE,
	GREEN,
	BLUE,
	PURPLE,
	ORANGE,
	RED,
}

enum Category {
	WEAPON,
	ARMOR,
	ACCESSORY,
}

enum Slot {
	HEAD,
	CHEST,
	SHOULDERS,
	HANDS,
	LEGS,
	FEET,
	ACCESSORY_1,
	ACCESSORY_2,
	WEAPON_1,
	WEAPON_2,
}

enum ArmorClass {
	LIGHT,
	MEDIUM,
	HEAVY,
}

const RARITY_COLORS := {
	Rarity.WHITE: Color(0.85, 0.85, 0.85),
	Rarity.GREEN: Color(0.35, 0.85, 0.35),
	Rarity.BLUE: Color(0.35, 0.65, 0.95),
	Rarity.PURPLE: Color(0.85, 0.35, 0.95),
	Rarity.ORANGE: Color(0.95, 0.65, 0.15),
	Rarity.RED: Color(0.95, 0.15, 0.15),
}

const SINGLE_HAND_WEAPONS := ["sword", "dagger", "axe", "crossbow", "shield"]

# ============================================================
# 武器类型标签（装备参考2 规格）
# ============================================================
#
# 规格原文：装备池里**非武器**装备的词条是「部位词条」、可多词条共存；
# 但**武器**不行——下列类型互斥，一件武器不能同时带互斥的两个标签。
#
# | 标签 | 含义 |
# |---|---|
# | 近战武器 | 只能近战攻击 |
# | 远程武器 | 只能远程攻击 |
# | 防御武器 | 没有攻击效果，只提供属性加成 |
# | 魔法武器 | 攻击造成魔法伤害（没有则默认物理） |
# | 单手武器 | 只占一个武器栏，可同时装两把 |
# | 双手武器 | 占两个武器栏 |
# | 长杆武器 | 攻击范围更长，有独特攻击方式 |

## 武器类型标签 id → 显示名
const WEAPON_TAGS := {
	"melee": "近战武器",
	"ranged": "远程武器",
	"defensive": "防御武器",
	"magic": "魔法武器",
	"one_hand": "单手武器",
	"two_hand": "双手武器",
	"polearm": "长杆武器",
}

## 互斥对（规格原文逐条落地）：
##   · 近战武器 ↔ 远程武器
##   · 单手武器 ↔ 双手武器
##   · 防御武器 ↔ 远程武器 / 魔法武器 / 长杆武器
##   · 长杆武器 ↔ 远程武器 / 防御武器
##
## **写成无向对**（判定时两个方向都查），避免只写单向漏掉反向组合。
const WEAPON_TAG_CONFLICTS := [
	["melee", "ranged"],
	["one_hand", "two_hand"],
	["defensive", "ranged"],
	["defensive", "magic"],
	["defensive", "polearm"],
	["polearm", "ranged"],
]


## 两组武器标签是否互斥。
##
## 返回冲突的那一对（无冲突返回空数组），便于调用方给出可读的拒绝理由。
static func weapon_tag_conflict(a: Array, b: Array) -> Array:
	for pair in WEAPON_TAG_CONFLICTS:
		var x: String = pair[0]
		var y: String = pair[1]
		if (x in a and y in b) or (y in a and x in b):
			return pair
	return []


## 一组武器标签内部是否自相矛盾（同一件武器带互斥的两个标签）
static func weapon_tag_self_conflict(tags: Array) -> Array:
	return weapon_tag_conflict(tags, tags)


## 现有中文标签 → 规格的 7 类武器标签。
##
## **为什么需要这层映射**：现有数据表用的是中文标签（「近战」「远程」
## 「长杆」「法术」「其他」），而装备参考2 的互斥规则定义在 7 类
## （melee/ranged/defensive/magic/one_hand/two_hand/polearm）上。
## 直接改数据表会牵动所有既有测试与存档；加一层映射则两边都不动。
##
## 映射依据：
##   · 近战 → melee；远程 → ranged；长杆 → polearm；法术 → magic
##   · 「其他」（盾牌）→ defensive（防御武器：无攻击效果、只给属性）
##   · 单手/双手由 **weapon_type** 判定（见 `weapon_tags_of`），不由中文标签
const TAG_ALIAS := {
	"近战": "melee",
	"远程": "ranged",
	"长杆": "polearm",
	"法术": "magic",
	"其他": "defensive",
	"物理": "",        # 物理是伤害类型，不是武器类型标签
}


## 从武器类型 + 中文标签推出规格的武器标签集合。
##
## 单手/双手**按 weapon_type 判定**（与 EquipmentTemplate.is_one_handed_weapon
## 同源），因为中文标签里没有这一维。
static func weapon_tags_of(weapon_type: String, tags: Array) -> Array:
	var out: Array = []
	for t in tags:
		var mapped: String = TAG_ALIAS.get(str(t), "")
		if not mapped.is_empty() and not (mapped in out):
			out.append(mapped)
	# 单手/双手：盾牌与匕首等算单手，巨剑/巨斧/长枪等算双手
	if not weapon_type.is_empty():
		if weapon_type in SINGLE_HAND_WEAPONS:
			out.append("one_hand")
		else:
			out.append("two_hand")
	return out


# ============================================================
# 随机词条（装备参考2 规格）
# ============================================================
#
# 每件装备掉落时随机生成 1~4 条随机词条。**无法升级、无法转移、
# 不会通过融合或吞噬继承**——它是「这件掉落物」的独有属性。

## 生成条数概率：1条40% / 2条30% / 3条20% / 4条10%
const RANDOM_AFFIX_COUNT_WEIGHTS := {1: 40, 2: 30, 3: 20, 4: 10}

## 三类随机词条的抽取权重（总和 100）
const RANDOM_KIND_WEIGHTS := {"numeric": 60, "attribute": 30, "special": 10}

## —— 数值词条：总加成在角色基础值的 2%~30%，再随机分配到各属性 ——
## [上限, 权重, 显示色]（区间按上限升序，取第一个 >= 抽中值的档）
const NUMERIC_TOTAL_TIERS := [
	[0.05, 30, "白"], [0.08, 30, "绿"], [0.15, 20, "蓝"],
	[0.20, 10, "紫"], [0.25, 8, "橙"], [0.30, 2, "红"],
]

## —— 属性词条：加成值 8%~50% ——
## [上限, 权重, 显示色]
const ATTRIBUTE_VALUE_TIERS := [
	[0.10, 30, "绿"], [0.20, 30, "蓝"], [0.30, 20, "紫"],
	[0.40, 15, "橙"], [0.50, 5, "红"],
]

## 属性词条的子类权重（物理/魔法/属性/真实）
const ATTRIBUTE_KIND_WEIGHTS := {
	"physical": 15, "magic": 15, "element": 60, "true": 10,
}

## —— 特殊词条：随机借用某件装备的自有词条，**不可升级** ——
## 概率按来源装备的稀有度浮动（[稀有度, 权重, 显示色]）
const SPECIAL_SOURCE_WEIGHTS := [
	[0, 35, "绿"],   # 白装来源
	[1, 30, "蓝"],   # 绿装来源
	[2, 20, "紫"],   # 蓝装来源
	[3, 10, "橙"],   # 紫装来源
	[4, 5, "红"],    # 橙装来源
	[5, 0, "红"],    # 红装来源（0% = 不会出现）
]

## 随机词条的三类 kind（写进 AffixData 便于 UI 分类显示与存档）
const RANDOM_KIND_NUMERIC := "numeric"
const RANDOM_KIND_ATTRIBUTE := "attribute"
const RANDOM_KIND_SPECIAL := "special"


static func rarity_name(r: int) -> String:
	match r:
		Rarity.WHITE: return "白色"
		Rarity.GREEN: return "绿色"
		Rarity.BLUE: return "蓝色"
		Rarity.PURPLE: return "紫色"
		Rarity.ORANGE: return "橙色"
		Rarity.RED: return "红色"
	return "未知"


static func category_name(c: int) -> String:
	match c:
		Category.WEAPON: return "武器"
		Category.ARMOR: return "护甲"
		Category.ACCESSORY: return "饰品"
	return "未知"


static func slot_name(s: int) -> String:
	match s:
		Slot.HEAD: return "头盔"
		Slot.CHEST: return "胸甲"
		Slot.SHOULDERS: return "肩甲"
		Slot.HANDS: return "护手"
		Slot.LEGS: return "腿甲"
		Slot.FEET: return "鞋子"
		Slot.ACCESSORY_1: return "饰品 1"
		Slot.ACCESSORY_2: return "饰品 2"
		Slot.WEAPON_1: return "武器 1"
		Slot.WEAPON_2: return "武器 2"
	return "未知"
