class_name EquipmentDefs
extends RefCounted
## 装备定义 —— HD-2D 重构版
## 所有装备相关的枚举和常量

# ============================================================
# 稀有度
# ============================================================
enum Rarity {
	WHITE,    # 普通
	BLUE,     # 魔法
	PURPLE,   # 稀有
	GOLD,     # 传说
}

const RARITY_NAMES := {
	Rarity.WHITE: "普通",
	Rarity.BLUE: "魔法",
	Rarity.PURPLE: "稀有",
	Rarity.GOLD: "传说",
}

const RARITY_COLORS := {
	Rarity.WHITE: Color(0.8, 0.8, 0.8),
	Rarity.BLUE: Color(0.3, 0.5, 1.0),
	Rarity.PURPLE: Color(0.7, 0.3, 1.0),
	Rarity.GOLD: Color(1.0, 0.75, 0.2),
}

# ============================================================
# 分类
# ============================================================
enum Category {
	WEAPON,   # 武器
	ARMOR,    # 防具
	ACCESSORY, # 饰品
}

const CATEGORY_NAMES := {
	Category.WEAPON: "武器",
	Category.ARMOR: "防具",
	Category.ACCESSORY: "饰品",
}

# ============================================================
# 装备槽位
# ============================================================
enum SlotCategory {
	WEAPON,
	HEAD,
	CHEST,
	LEGS,
	RING_1,
	RING_2,
	AMULET,
}

const SLOT_CATEGORY_NAMES := {
	SlotCategory.WEAPON: "武器",
	SlotCategory.HEAD: "头部",
	SlotCategory.CHEST: "胸甲",
	SlotCategory.LEGS: "腿部",
	SlotCategory.RING_1: "戒指1",
	SlotCategory.RING_2: "戒指2",
	SlotCategory.AMULET: "项链",
}

# ============================================================
# 武器类型
# ============================================================
enum WeaponType {
	SWORD,     # 剑
	AXE,       # 斧
	SPEAR,     # 枪
	DAGGER,    # 匕首
	STAFF,     # 法杖
	BOW,       # 弓
}

const WEAPON_TYPE_NAMES := {
	WeaponType.SWORD: "剑",
	WeaponType.AXE: "斧",
	WeaponType.SPEAR: "枪",
	WeaponType.DAGGER: "匕首",
	WeaponType.STAFF: "法杖",
	WeaponType.BOW: "弓",
}

# ============================================================
# 防具类型
# ============================================================
enum ArmorClass {
	LIGHT,    # 轻甲
	MEDIUM,   # 中甲
	HEAVY,    # 重甲
}

const ARMOR_CLASS_NAMES := {
	ArmorClass.LIGHT: "轻甲",
	ArmorClass.MEDIUM: "中甲",
	ArmorClass.HEAVY: "重甲",
}

# 标签
const TAG_WHITE := "普通"


static func rarity_name(rarity: int) -> String:
	return RARITY_NAMES.get(rarity, "未知")


static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS.get(rarity, Color.WHITE)


static func weapon_tags(weapon_type: int, traits: Array) -> Array:
	var tags: Array = []
	match weapon_type:
		WeaponType.SWORD:
			tags.append("近战")
		WeaponType.AXE:
			tags.append("近战")
		WeaponType.SPEAR:
			tags.append("长杆")
		WeaponType.DAGGER:
			tags.append("近战")
		WeaponType.STAFF:
			tags.append("法术")
		WeaponType.BOW:
			tags.append("远程")
	return tags