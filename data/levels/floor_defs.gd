class_name FloorDefs
extends RefCounted
## 楼层定义表 —— 《噬铁者》9 层结构（依据关卡设计分册 1.2 / 2.1 / 5.3）
##
## **本文件是层级系统的唯一真相源**：主题配色、地图可用范围、房间数、
## 怪物强度倍率、Boss 血量基准，全部从这里取。
## 原先这些值散落在各处（房间配色硬编码在 floor_builder、房间数硬编码 13、
## 难度倍率不含层因子），导致「所有层长得一样、难度也一样」。
##
## 策划书口径：8 层常规 + 1 层隐藏；范围 14×14 → 30×30 逐层扩张；
## 难度「前慢后快」——1~2 层平缓、3~5 层成长、6~8 层考核、9 层纯挑战。

## 层数上限（超出即结算通关）
const MAX_FLOOR := 9

## 解锁隐藏层（第 9 层）所需的钥匙碎片总数。
## 策划书 1.3：第 9 层需集齐前 8 层 Boss 掉落的全部 8 片钥匙碎片解锁。
const KEY_FRAGMENTS_REQUIRED := 8

## 每层 Boss 掉落标准（关卡分册 6.2~6.9 各节末尾的「掉落标准」）。
## 下标 0 = 第 1 层。字段：
##   rarity      保底装备稀有度（EquipmentDefs.Rarity 枚举值）
##   gold        金币区间 [min, max]（策划书各层金币档位）
##   fragment    钥匙碎片掉落概率（0~1）
##   extra_*     额外掉落（蓝装/紫装等）概率与稀有度
##
## ⚠ 稀有度用整数值而非 EquipmentDefs.Rarity.X：FloorDefs 是纯数据层，
## 不应依赖 equipment_defs.gd（那个文件会反向引用 data 层，形成解析环）。
## 数值与 EquipmentDefs.Rarity 枚举一一对应：0白 1绿 2蓝 3紫 4橙 5红。
const RARITY_WHITE := 0
const RARITY_GREEN := 1
const RARITY_BLUE := 2
const RARITY_PURPLE := 3
const RARITY_ORANGE := 4
const RARITY_RED := 5

const BOSS_DROPS := [
	# 1 层：橙装 1 件（白装 2.5 倍）+ 碎片 35% + 金币 120~160 + 15% 蓝装
	{"rarity": RARITY_ORANGE, "gold": [120, 160], "fragment": 0.35,
		"extra_rarity": RARITY_BLUE, "extra_chance": 0.15},
	# 2 层：橙装 + 碎片 30% + 金币 140~200 + 20% 蓝装
	{"rarity": RARITY_ORANGE, "gold": [140, 200], "fragment": 0.30,
		"extra_rarity": RARITY_BLUE, "extra_chance": 0.20},
	# 3 层：橙装 + 碎片 35% + 金币 180~240 + 20% 紫装
	{"rarity": RARITY_ORANGE, "gold": [180, 240], "fragment": 0.35,
		"extra_rarity": RARITY_PURPLE, "extra_chance": 0.20},
	# 4 层：橙装 + 碎片 35% + 金币 190~250 + 20% 紫装
	{"rarity": RARITY_ORANGE, "gold": [190, 250], "fragment": 0.35,
		"extra_rarity": RARITY_PURPLE, "extra_chance": 0.20},
	# 5 层：橙装 + 碎片 35% + 金币 190~330 + 20% 紫装
	{"rarity": RARITY_ORANGE, "gold": [190, 330], "fragment": 0.35,
		"extra_rarity": RARITY_PURPLE, "extra_chance": 0.20},
	# 6 层：**保底升级为红装** + 碎片 35% + 金币 250~350 + 20% 紫装
	{"rarity": RARITY_RED, "gold": [250, 350], "fragment": 0.35,
		"extra_rarity": RARITY_PURPLE, "extra_chance": 0.20},
	# 7 层：红装 + 碎片 35% + 金币 300~400 + 20% 紫装
	{"rarity": RARITY_RED, "gold": [300, 400], "fragment": 0.35,
		"extra_rarity": RARITY_PURPLE, "extra_chance": 0.20},
	# 8 层：红装 + 碎片 35% + 金币 350~450（策划未给明数，对齐 7 层档位上浮）
	{"rarity": RARITY_RED, "gold": [350, 450], "fragment": 0.35,
		"extra_rarity": RARITY_PURPLE, "extra_chance": 0.20},
	# 9 层：隐藏层三连战，奖励走奖励大厅，不给常规 Boss 掉落
	{"rarity": RARITY_RED, "gold": [0, 0], "fragment": 0.0,
		"extra_rarity": RARITY_RED, "extra_chance": 0.0},
]

## 9 层定义。数组下标 0 = 第 1 层，下标 8 = 第 9 层（隐藏层）。
##
## 字段说明：
##   id            主题标识（用于资源映射/存档）
##   name          主题名（策划书 1.2 表）
##   range_half    地图可用范围的半边长（14×14 → range_half=7）
##   rooms_min/max 本层房间总数区间（策划书 1.2 表）
##   monster_mult  怪物 hp/atk 强度倍率（层因子，与玩家难度选择相乘）
##   boss_hp       本层 Boss 血量基准（策划书 5.3；9 层为三连战，取首战值）
##   env           环境机制标识（批次 D 实现；本批次只登记不生效）
##   colors        主题配色（房间地板/墙/点缀 + 环境光/雾/主光）
const FLOORS := [
	{
		"id": "prison", "name": "监牢入口",
		"range_half": 7, "rooms_min": 12, "rooms_max": 16,
		"monster_mult": 1.0, "boss_hp": 450, "env": "",
		"colors": {
			"floor": Color(0.30, 0.30, 0.33),
			"floor_alt": Color(0.36, 0.35, 0.37),
			"wall": Color(0.22, 0.22, 0.26),
			"accent": Color(0.45, 0.40, 0.30),
			"ambient": Color(0.16, 0.16, 0.19),
			"fog": Color(0.18, 0.18, 0.22),
			"light": Color(0.85, 0.78, 0.60),
		},
	},
	{
		"id": "mine", "name": "废弃矿道",
		"range_half": 8, "rooms_min": 12, "rooms_max": 16,
		"monster_mult": 1.15, "boss_hp": 570, "env": "collapse",
		"colors": {
			"floor": Color(0.26, 0.23, 0.20),
			"floor_alt": Color(0.32, 0.27, 0.22),
			"wall": Color(0.20, 0.16, 0.13),
			"accent": Color(0.25, 0.45, 0.75),   # 幽蓝矿石发光
			"ambient": Color(0.14, 0.13, 0.13),
			"fog": Color(0.16, 0.15, 0.16),
			"light": Color(0.55, 0.65, 0.95),
		},
	},
	{
		"id": "tomb", "name": "古老墓穴",
		"range_half": 9, "rooms_min": 14, "rooms_max": 18,
		"monster_mult": 1.35, "boss_hp": 1000, "env": "poison",
		"colors": {
			"floor": Color(0.22, 0.26, 0.22),
			"floor_alt": Color(0.26, 0.31, 0.25),
			"wall": Color(0.17, 0.20, 0.17),
			"accent": Color(0.35, 0.60, 0.30),   # 暗绿毒瘴
			"ambient": Color(0.11, 0.14, 0.11),
			"fog": Color(0.14, 0.20, 0.13),
			"light": Color(0.55, 0.85, 0.50),
		},
	},
	{
		"id": "swamp", "name": "地下沼泽",
		"range_half": 10, "rooms_min": 14, "rooms_max": 18,
		"monster_mult": 1.55, "boss_hp": 1400, "env": "mire",
		"colors": {
			"floor": Color(0.20, 0.19, 0.15),
			"floor_alt": Color(0.24, 0.23, 0.17),
			"wall": Color(0.15, 0.14, 0.11),
			"accent": Color(0.45, 0.25, 0.55),   # 荧光真菌/暗紫雾
			"ambient": Color(0.10, 0.09, 0.11),
			"fog": Color(0.16, 0.12, 0.20),
			"light": Color(0.70, 0.50, 0.90),
		},
	},
	{
		"id": "forge", "name": "符文熔炉",
		"range_half": 11, "rooms_min": 16, "rooms_max": 20,
		"monster_mult": 1.80, "boss_hp": 1900, "env": "lava",
		"colors": {
			"floor": Color(0.26, 0.16, 0.12),
			"floor_alt": Color(0.31, 0.18, 0.13),
			"wall": Color(0.19, 0.11, 0.08),
			"accent": Color(0.95, 0.40, 0.10),   # 熔岩橙红
			"ambient": Color(0.18, 0.09, 0.05),
			"fog": Color(0.24, 0.10, 0.05),
			"light": Color(1.00, 0.55, 0.25),
		},
	},
	{
		"id": "sulfur", "name": "硫磺深渊",
		"range_half": 12, "rooms_min": 18, "rooms_max": 22,
		"monster_mult": 2.10, "boss_hp": 2600, "env": "sulfur",
		"colors": {
			"floor": Color(0.28, 0.14, 0.14),
			"floor_alt": Color(0.33, 0.16, 0.15),
			"wall": Color(0.20, 0.09, 0.09),
			"accent": Color(0.90, 0.25, 0.20),   # 硫磺红暗光
			"ambient": Color(0.18, 0.07, 0.07),
			"fog": Color(0.26, 0.07, 0.06),
			"light": Color(1.00, 0.45, 0.40),
		},
	},
	{
		"id": "void", "name": "虚空回廊",
		"range_half": 13, "rooms_min": 18, "rooms_max": 24,
		"monster_mult": 2.45, "boss_hp": 2700,
		# 策划 4 章第 7 层写的是「重力降低（跳跃高度翻倍）+ 随机传送」。
		# **重力那半在本作不成立**：玩家是俯视角平面移动（只有 x/z），
		# 没有重力场也没有可跳跃高度——"跳跃攻击"是三段脚本化位移。
		# 故只实现能落地的那半（随机传送），环境标识据此取 void_warp。
		"env": "void_warp",
		"colors": {
			"floor": Color(0.16, 0.16, 0.24),
			"floor_alt": Color(0.20, 0.19, 0.30),
			"wall": Color(0.11, 0.11, 0.18),
			"accent": Color(0.45, 0.35, 0.95),   # 蓝紫虚空
			"ambient": Color(0.08, 0.08, 0.15),
			"fog": Color(0.10, 0.09, 0.22),
			"light": Color(0.60, 0.50, 1.00),
		},
	},
	{
		"id": "throne", "name": "地狱王座",
		"range_half": 14, "rooms_min": 20, "rooms_max": 28,
		"monster_mult": 2.85, "boss_hp": 5500, "env": "firestorm",
		"colors": {
			"floor": Color(0.24, 0.10, 0.10),
			"floor_alt": Color(0.30, 0.12, 0.11),
			"wall": Color(0.16, 0.06, 0.06),
			"accent": Color(1.00, 0.20, 0.15),   # 血红烈焰
			"ambient": Color(0.20, 0.06, 0.06),
			"fog": Color(0.30, 0.06, 0.06),
			"light": Color(1.00, 0.35, 0.30),
		},
	},
	{
		"id": "rift", "name": "混沌裂隙",
		"range_half": 15, "rooms_min": 5, "rooms_max": 5,
		"monster_mult": 3.30, "boss_hp": 4500, "env": "chaos_warp",
		"colors": {
			"floor": Color(0.12, 0.12, 0.14),
			"floor_alt": Color(0.20, 0.20, 0.23),
			"wall": Color(0.08, 0.08, 0.09),
			"accent": Color(0.90, 0.90, 0.95),   # 黑白闪烁
			"ambient": Color(0.10, 0.10, 0.12),
			"fog": Color(0.15, 0.15, 0.18),
			"light": Color(0.95, 0.95, 1.00),
		},
	},
]


## 取指定层的定义（越界钳制到 1..9）。
## 传入运行时可能出现的非法层数（存档损坏、调试跳层）也不会崩。
static func for_floor(floor_num: int) -> Dictionary:
	var idx: int = clampi(floor_num - 1, 0, FLOORS.size() - 1)
	return FLOORS[idx]


## 主题标识（如 "prison"）
static func theme_id(floor_num: int) -> String:
	return str(for_floor(floor_num).get("id", "prison"))


## 主题显示名（如 "监牢入口"）
static func theme_name(floor_num: int) -> String:
	return str(for_floor(floor_num).get("name", "未知"))


## 本层地图可用范围半边长（7 = 14×14，15 = 30×30）
static func range_half(floor_num: int) -> int:
	return int(for_floor(floor_num).get("range_half", 7))


## 本层房间总数（区间内按 rng 取值；无 rng 时取中值）
## 第 9 层固定 5 间（策划书：仅 5 间 = 奖励大厅 + Boss 连战 ×3 + 传送点）
static func room_count(floor_num: int, rng: RandomNumberGenerator = null) -> int:
	var d := for_floor(floor_num)
	var lo: int = int(d.get("rooms_min", 12))
	var hi: int = int(d.get("rooms_max", lo))
	if hi <= lo:
		return lo
	if rng == null:
		return int((lo + hi) / 2)
	return rng.randi_range(lo, hi)


## 本层怪物强度倍率（层因子）
static func monster_mult(floor_num: int) -> float:
	return float(for_floor(floor_num).get("monster_mult", 1.0))


## 本层 Boss 血量基准（策划书 5.3）
static func boss_hp(floor_num: int) -> float:
	return float(for_floor(floor_num).get("boss_hp", 500.0))


## 本层环境机制标识（批次 D 实现前为空字符串或已登记未生效的 id）
static func env_id(floor_num: int) -> String:
	return str(for_floor(floor_num).get("env", ""))


## 取某个配色键（floor / wall / accent / ambient / fog / light）。
## 键不存在时回退到 crypt 风格灰色，避免调用方拿到 null。
static func color_of(floor_num: int, key: String) -> Color:
	var d := for_floor(floor_num)
	var colors: Dictionary = d.get("colors", {})
	return colors.get(key, Color(0.3, 0.3, 0.35))


## 是否隐藏层（第 9 层：需集齐钥匙碎片进入，不可回头）
static func is_hidden(floor_num: int) -> bool:
	return floor_num >= MAX_FLOOR


## 本层 Boss 掉落标准（越界钳制到 1..9）。
## 返回 {rarity, gold:[min,max], fragment, extra_rarity, extra_chance}
static func boss_drop(floor_num: int) -> Dictionary:
	var idx: int = clampi(floor_num - 1, 0, BOSS_DROPS.size() - 1)
	return BOSS_DROPS[idx]


## 本层 Boss 保底装备稀有度（1~5 层橙、6 层起红）
static func boss_rarity(floor_num: int) -> int:
	return int(boss_drop(floor_num).get("rarity", RARITY_ORANGE))


## 本层 Boss 钥匙碎片掉落概率
static func boss_fragment_chance(floor_num: int) -> float:
	return float(boss_drop(floor_num).get("fragment", 0.0))


## 本层 Boss 金币区间 Vector2(min, max)
static func boss_gold_range(floor_num: int) -> Vector2:
	var g: Array = boss_drop(floor_num).get("gold", [0, 0])
	if g.size() < 2:
		return Vector2.ZERO
	return Vector2(float(g[0]), float(g[1]))
