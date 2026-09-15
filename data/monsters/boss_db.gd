class_name BossDB
extends RefCounted
## Boss 数据表 —— 《噬铁者》关卡设计分册 6.2~6.10
##
## **设计取舍：机制归并而非逐个实现。**
## 策划列了 53 个 Boss、每个一句机制描述。逐条实现会是 53 份高度重复的
## 代码（且互相之间只差参数），维护成本远超收益。实际做法是把描述归并成
## **9 类通用机制**，每个 Boss 声明「它由哪几类组成 + 参数」：
##
##   SUMMON  召唤系   —— 定期召唤小怪（有的死亡自爆）
##   SPLIT   分裂系   —— 死亡/受击分裂为小型同类
##   PHASE   阶段系   —— 血量降到阈值触发增益或换招（半血狂暴等）
##   SHIELD  护盾系   —— 高减伤/需先破除（绕背、打柱子、降温）
##   STEALTH 潜行系   —— 隐身/潜伏，现身窗口才能打
##   FIELD   场地系   —— 地面区域（毒/泥潭/熔岩/焦油/重力/传送）
##   RANGED  远程系   —— 弹幕/投掷/激光/箭雨
##   CONTROL 控制系   —— 定身/恐惧/减速/拉拽
##   CHARGE  冲锋系   —— 突进/俯冲/跳跃砸地
##
## 复用：多数类别直接对应 EnemyBase 已有的机制原语（召唤/分裂/隐身/瞬移/
## 护盾/减速/灰烬/潜伏…），本表只做「哪几类 + 参数」的声明。
## 阶段转换与场地障碍是 C3 新加的通用原语。

## 机制类标识
const M_SUMMON := "summon"
const M_SPLIT := "split"
const M_PHASE := "phase"
const M_SHIELD := "shield"
const M_STEALTH := "stealth"
const M_FIELD := "field"
const M_RANGED := "ranged"
const M_CONTROL := "control"
const M_CHARGE := "charge"

## 全部机制类（供测试校验完整性）
const ALL_MECHANICS := [
	M_SUMMON, M_SPLIT, M_PHASE, M_SHIELD, M_STEALTH,
	M_FIELD, M_RANGED, M_CONTROL, M_CHARGE,
]

## Boss 定义。按层分组：层号 → Boss 数组（每层 7 个，第 8 层固定、第 9 层三连战）。
##
## 字段：
##   id       "1-1" 形式，与策划书编号一致
##   name     概念名（策划书原文）
##   mechs    机制类数组（见上）
##   hp_pct   相对本层 boss_hp 基准的倍率（1.0 = 基准）
##   atk_pct  相对本层怪物攻击基准的倍率
##   ai       行为模式（AIBehavior 名："melee"/"kite"/"sentry"/"rusher"）
##   params   机制参数（如召唤 id/数量、阶段阈值、区域类型）
static var BOSSES := {
	1: [
		{"id": "1-1", "name": "狱卒·卡恩", "mechs": [M_SUMMON, M_PHASE],
			"hp_pct": 1.0, "atk_pct": 1.0, "ai": "melee",
			"params": {"summon": {"id": "zombie", "count": 2, "chance": 1.0},
				"phase_at": 0.5, "phase_haste": 0.2}},
		{"id": "1-2", "name": "剥皮者·裂爪", "mechs": [M_CHARGE, M_CONTROL],
			"hp_pct": 0.9, "atk_pct": 1.1, "ai": "melee",
			"params": {"dash_range": 6.0, "dot_on_hit": "bleed"}},
		{"id": "1-3", "name": "典狱长·铁壁", "mechs": [M_SHIELD],
			"hp_pct": 1.1, "atk_pct": 0.9, "ai": "melee",
			"params": {"shield_reduction": 0.7, "shield_break": "backstab"}},
		{"id": "1-4", "name": "疯鼠王", "mechs": [M_SUMMON, M_SPLIT],
			"hp_pct": 1.0, "atk_pct": 0.9, "ai": "melee",
			"params": {"summon": {"id": "rat", "count": 2, "chance": 1.0,
				"death_explode": true, "explode_damage": 25.0, "explode_radius": 2.5}}},
		{"id": "1-5", "name": "断头台·重刃", "mechs": [M_PHASE],
			"hp_pct": 1.0, "atk_pct": 1.3, "ai": "melee",
			"params": {"windup_scale": 3.0, "interruptible": true}},
		{"id": "1-6", "name": "铁处女·拘束", "mechs": [M_CONTROL],
			"hp_pct": 1.0, "atk_pct": 1.0, "ai": "melee",
			"params": {"fear_radius": 4.0, "fear_push": 3.0}},
		{"id": "1-7", "name": "枷锁幽灵", "mechs": [M_CONTROL, M_RANGED],
			"hp_pct": 0.9, "atk_pct": 1.0, "ai": "kite",
			"params": {"root_seconds": 2.0, "exec_damage_pct": 2.5}},
	],
	2: [
		{"id": "2-1", "name": "矿道巨人·碎石者", "mechs": [M_FIELD, M_RANGED],
			"hp_pct": 1.1, "atk_pct": 1.0, "ai": "melee",
			"params": {"aoe_radius": 4.0, "field": "collapse"}},
		{"id": "2-2", "name": "掘地虫·突袭者", "mechs": [M_STEALTH, M_CHARGE],
			"hp_pct": 1.0, "atk_pct": 1.1, "ai": "rusher",
			"params": {"burrow_seconds": 3.0, "dash_range": 7.0}},
		{"id": "2-3", "name": "矿车巨魔", "mechs": [M_CHARGE, M_PHASE],
			"hp_pct": 1.2, "atk_pct": 1.0, "ai": "rusher",
			"params": {"dash_range": 9.0, "stun_after_wall": 5.0}},
		{"id": "2-4", "name": "尘肺亡灵", "mechs": [M_FIELD, M_CONTROL],
			"hp_pct": 1.0, "atk_pct": 0.9, "ai": "kite",
			"params": {"field": "poison", "slow_pct": 0.3}},
		{"id": "2-5", "name": "黑火药投弹手", "mechs": [M_RANGED, M_FIELD],
			"hp_pct": 0.9, "atk_pct": 1.2, "ai": "kite",
			"params": {"bomb": true, "bomb_reflectable": true}},
		{"id": "2-6", "name": "岩层巨人", "mechs": [M_FIELD, M_SHIELD],
			"hp_pct": 1.3, "atk_pct": 0.9, "ai": "melee",
			"params": {"field": "rocks", "spawn_obstacle_on_hit": true}},
		{"id": "2-7", "name": "暗影矿工", "mechs": [M_STEALTH, M_CHARGE],
			"hp_pct": 0.9, "atk_pct": 1.3, "ai": "melee",
			"params": {"stealth_always": true, "reveal_on_attack": true}},
	],
	3: [
		{"id": "3-1", "name": "墓穴领主·亡灵祭司", "mechs": [M_SUMMON, M_PHASE, M_RANGED],
			"hp_pct": 1.0, "atk_pct": 1.0, "ai": "kite",
			"params": {"summon": {"id": "skeleton", "count": 2, "chance": 0.5},
				"phase_at": 0.5, "phase_haste": 1.0}},
		{"id": "3-2", "name": "石棺守卫", "mechs": [M_SPLIT],
			"hp_pct": 1.2, "atk_pct": 1.0, "ai": "melee",
			"params": {"death_split": true, "split_count": 1}},
		{"id": "3-3", "name": "诅咒木乃伊", "mechs": [M_CONTROL],
			"hp_pct": 1.0, "atk_pct": 1.0, "ai": "melee",
			"params": {"healcut_on_hit": 0.3}},
		{"id": "3-4", "name": "骨龙幼崽", "mechs": [M_CHARGE, M_CONTROL],
			"hp_pct": 1.1, "atk_pct": 1.1, "ai": "rusher",
			"params": {"dash_range": 8.0, "knockback": 5.0}},
		{"id": "3-5", "name": "死灵学徒", "mechs": [M_SUMMON],
			"hp_pct": 0.9, "atk_pct": 1.0, "ai": "kite",
			"params": {"summon": {"id": "skeleton", "count": 3, "chance": 1.0,
				"interval": 20.0}}},
		{"id": "3-6", "name": "贪噬宝箱怪", "mechs": [M_STEALTH],
			"hp_pct": 1.0, "atk_pct": 1.2, "ai": "melee",
			"params": {"disguise": "chest", "steal_equipment": true}},
		{"id": "3-7", "name": "灵魂灯笼", "mechs": [M_SUMMON, M_PHASE],
			"hp_pct": 1.0, "atk_pct": 0.9, "ai": "kite",
			"params": {"summon": {"id": "wisp_ghostfire", "count": 2, "chance": 0.6},
				"absorb_buff_pct": 0.1}},
	],
	4: [
		{"id": "4-1", "name": "沼泽巨兽·腐化之息", "mechs": [M_FIELD, M_RANGED],
			"hp_pct": 1.1, "atk_pct": 1.1, "ai": "melee",
			"params": {"field": "mire", "spray": true}},
		{"id": "4-2", "name": "腐化树精", "mechs": [M_CONTROL, M_FIELD],
			"hp_pct": 1.2, "atk_pct": 1.0, "ai": "sentry",
			"params": {"root_seconds": 3.0, "aoe_radius": 5.0, "interruptible": true}},
		{"id": "4-3", "name": "剧毒史莱姆王", "mechs": [M_SPLIT],
			"hp_pct": 1.3, "atk_pct": 0.9, "ai": "melee",
			"params": {"death_split": true, "split_count": 3, "split_hp_pct": 0.35,
				"chain_split": 2}},
		{"id": "4-4", "name": "蚊群女王", "mechs": [M_SUMMON, M_FIELD],
			"hp_pct": 1.0, "atk_pct": 1.0, "ai": "kite",
			"params": {"summon": {"id": "mosquito", "count": 3, "chance": 0.8,
				"lifesteal": true}}},
		{"id": "4-5", "name": "泥泞潜行者", "mechs": [M_STEALTH, M_CHARGE],
			"hp_pct": 0.9, "atk_pct": 1.5, "ai": "melee",
			"params": {"ambush": true, "ambush_range": 4.0, "ambush_damage_pct": 2.5}},
		{"id": "4-6", "name": "真菌巨人", "mechs": [M_FIELD, M_CONTROL],
			"hp_pct": 1.2, "atk_pct": 0.9, "ai": "sentry",
			"params": {"field": "spore", "confuse": true}},
		{"id": "4-7", "name": "诅咒鱼人祭祀", "mechs": [M_RANGED, M_CONTROL],
			"hp_pct": 1.0, "atk_pct": 1.1, "ai": "kite",
			"params": {"spear": true, "slow_pct": 0.3, "reflectable": true}},
	],
	5: [
		{"id": "5-1", "name": "幽魂骑士·无头之影", "mechs": [M_CHARGE, M_PHASE, M_RANGED],
			"hp_pct": 1.0, "atk_pct": 1.1, "ai": "melee",
			"params": {"dash_range": 7.0, "phase_at": 0.5, "phase_haste": 0.4}},
		{"id": "5-2", "name": "熔炉守卫·魔像", "mechs": [M_SHIELD, M_FIELD],
			"hp_pct": 1.3, "atk_pct": 1.0, "ai": "melee",
			"params": {"reflect_damage": 0.3, "cool_zone": true}},
		{"id": "5-3", "name": "烈焰工匠", "mechs": [M_RANGED, M_FIELD],
			"hp_pct": 1.0, "atk_pct": 1.1, "ai": "kite",
			"params": {"gear_projectile": true, "field": "lava"}},
		{"id": "5-4", "name": "暴躁铁砧", "mechs": [M_CHARGE, M_FIELD],
			"hp_pct": 1.2, "atk_pct": 1.0, "ai": "melee",
			"params": {"slam": true, "ring_flame": true}},
		{"id": "5-5", "name": "焦油元素", "mechs": [M_FIELD, M_CONTROL],
			"hp_pct": 1.0, "atk_pct": 0.9, "ai": "melee",
			"params": {"field": "tar", "ignitable": true}},
		{"id": "5-6", "name": "爆破工程师", "mechs": [M_FIELD, M_SUMMON],
			"hp_pct": 0.9, "atk_pct": 1.2, "ai": "kite",
			"params": {"timed_bomb": true, "bomb_countdown": 6.0}},
		{"id": "5-7", "name": "灰烬凤凰", "mechs": [M_SPLIT, M_PHASE],
			"hp_pct": 1.1, "atk_pct": 1.1, "ai": "melee",
			"params": {"ash_revive": true, "revive_window": 5.0}},
	],
	6: [
		{"id": "6-1", "name": "深渊恶魔·炎魔领主", "mechs": [M_RANGED, M_SUMMON, M_PHASE],
			"hp_pct": 1.1, "atk_pct": 1.1, "ai": "kite",
			"params": {"summon": {"id": "forge_imp", "count": 2, "chance": 0.5},
				"phase_at": 0.5, "fire_aura": true}},
		{"id": "6-2", "name": "恶魔卫士·碎颅者", "mechs": [M_CHARGE, M_CONTROL],
			"hp_pct": 1.2, "atk_pct": 1.2, "ai": "rusher",
			"params": {"dash_range": 8.0, "stun_on_hit": 1.0}},
		{"id": "6-3", "name": "地狱三头犬", "mechs": [M_PHASE, M_RANGED],
			"hp_pct": 1.3, "atk_pct": 1.0, "ai": "melee",
			"params": {"three_heads": true, "elements": ["fire", "frost", "poison"]}},
		{"id": "6-4", "name": "痛苦魔女", "mechs": [M_CONTROL, M_FIELD],
			"hp_pct": 1.0, "atk_pct": 1.1, "ai": "kite",
			"params": {"chain_pull": true, "lifesteal_aura": true}},
		{"id": "6-5", "name": "深渊凝视者", "mechs": [M_RANGED],
			"hp_pct": 1.0, "atk_pct": 1.3, "ai": "sentry",
			"params": {"tracking_laser": true}},
		{"id": "6-6", "name": "混沌幼崽", "mechs": [M_STEALTH, M_FIELD],
			"hp_pct": 0.9, "atk_pct": 1.4, "ai": "rusher",
			"params": {"teleport": true, "self_destruct": true, "fuse": 3.0}},
		{"id": "6-7", "name": "熔核魔像", "mechs": [M_SHIELD, M_FIELD],
			"hp_pct": 1.4, "atk_pct": 1.0, "ai": "melee",
			"params": {"heat_buildup": true, "explode_at_full": true, "cool_zone": true}},
	],
	7: [
		{"id": "7-1", "name": "虚空领主·时空畸变体", "mechs": [M_CHARGE, M_FIELD, M_PHASE],
			"hp_pct": 1.1, "atk_pct": 1.1, "ai": "melee",
			"params": {"teleport": true, "field": "rift", "phase_at": 0.5}},
		{"id": "7-2", "name": "时间畸变者", "mechs": [M_CONTROL, M_PHASE],
			"hp_pct": 1.0, "atk_pct": 1.2, "ai": "kite",
			"params": {"haste_self_pct": 0.6, "slow_target_pct": 0.3}},
		{"id": "7-3", "name": "镜像幻术师", "mechs": [M_SUMMON, M_SHIELD],
			"hp_pct": 1.1, "atk_pct": 1.1, "ai": "kite",
			"params": {"summon": {"id": "player_clone", "count": 1, "chance": 1.0}},
		},
		{"id": "7-4", "name": "重力破坏者", "mechs": [M_FIELD],
			"hp_pct": 1.2, "atk_pct": 1.1, "ai": "melee",
			"params": {"field": "gravity_flip", "interval": 8.0}},
		{"id": "7-5", "name": "星界猎手", "mechs": [M_RANGED, M_FIELD],
			"hp_pct": 1.0, "atk_pct": 1.3, "ai": "sentry",
			"params": {"arrow_rain": true, "coverage": 0.6, "safe_zone": "boss_center"}},
		{"id": "7-6", "name": "虚无吞噬者", "mechs": [M_FIELD],
			"hp_pct": 1.3, "atk_pct": 1.1, "ai": "melee",
			"params": {"field": "devour", "devours_cover": true}},
		{"id": "7-7", "name": "熵之眼", "mechs": [M_CONTROL, M_FIELD],
			"hp_pct": 1.0, "atk_pct": 1.2, "ai": "sentry",
			"params": {"random_debuff_interval": 30.0, "purify_circle": true}},
	],
}

## 第 8 层固定 Boss：破坏神化身·末日之焰（策划 6.9）
## 四阶段（100% / 70% / 45% / 20%），P4 破防后护甲从 25% 降到 10%
static var BOSS_FLOOR_8 := {
	"id": "8-1", "name": "破坏神化身·末日之焰",
	"mechs": [M_PHASE, M_FIELD, M_SHIELD],
	"hp_pct": 1.0, "atk_pct": 1.0, "ai": "melee",
	"params": {
		"phases": [0.70, 0.45, 0.20],
		"armor_reduction": 0.25,
		"armor_reduction_p4": 0.10,
		"burn_per_second": 20.0,     # 地狱灼烧：无视护甲每秒 20
		"field": "firestorm",
	},
}

## 第 9 层三连战（策划 6.10）
static var BOSS_FLOOR_9 := [
	{"id": "9-1", "name": "混沌守卫·壁垒之骸",
		"mechs": [M_SHIELD, M_FIELD],
		"hp_pct": 1.0, "atk_pct": 1.0, "ai": "melee",
		"params": {"energy_pillars": 3, "shield_reduction": 0.7}},
	{"id": "9-2", "name": "虚空双子·影与焰",
		"mechs": [M_PHASE, M_RANGED],
		"hp_pct": 0.71, "atk_pct": 1.1, "ai": "kite",
		"params": {"twin": true, "shared_hp": true, "enrage_atk": 1.0, "enrage_speed": 0.5}},
	{"id": "9-3", "name": "破坏神完全体·终焉之翼",
		"mechs": [M_PHASE, M_FIELD, M_RANGED, M_SUMMON],
		"hp_pct": 2.67, "atk_pct": 1.2, "ai": "melee",
		"params": {"phases": [0.70, 0.45, 0.20], "forced_teleport_interval": 15.0}},
]


## 取某层的 Boss 池（第 8/9 层返回固定配置）
static func pool_for_floor(floor_num: int) -> Array:
	var f: int = clampi(floor_num, 1, FloorDefs.MAX_FLOOR)
	if f == 8:
		return [BOSS_FLOOR_8]
	if f == 9:
		return BOSS_FLOOR_9
	return BOSSES.get(f, [])


## 随机抽一个本层 Boss（不同局不同）。rng 为空时取第一个。
static func random_for_floor(floor_num: int, rng: RandomNumberGenerator) -> Dictionary:
	var pool := pool_for_floor(floor_num)
	if pool.is_empty():
		return {}
	if rng == null:
		return pool[0]
	return pool[rng.randi_range(0, pool.size() - 1)]


## 按 id 精确取（存档 / 第 9 层三连战按序取用）
static func get_boss(boss_id: String) -> Dictionary:
	for f in BOSSES:
		for b in BOSSES[f]:
			if str(b.get("id", "")) == boss_id:
				return b
	if str(BOSS_FLOOR_8.get("id", "")) == boss_id:
		return BOSS_FLOOR_8
	for b in BOSS_FLOOR_9:
		if str(b.get("id", "")) == boss_id:
			return b
	return {}


## 总 Boss 数（供测试断言：53 个轮换位 + 第 8 层固定 + 第 9 层三连战 = 57）
static func total_count() -> int:
	var n := 0
	for f in BOSSES:
		n += BOSSES[f].size()
	n += 1 + BOSS_FLOOR_9.size()
	return n


## 展开成 EnemyBase 可用的怪物配置字典。
##
## 把 BossDB 的字段翻译成 MonsterDB 同口径的配置（hp/atk/speed_pct/ai/
## special/mech），这样 RoomController 走的是与普通怪同一条
## apply_monster_config 路径，不需要给 Boss 单独一套加载逻辑。
##
## boss_hp_base 由调用方传入本层的 boss_hp（FloorDefs），
## 使「层难度」与「Boss 个体差异」两个维度相乘。
static func to_monster_config(boss: Dictionary, floor_num: int,
		boss_hp_base: float) -> Dictionary:
	if boss.is_empty():
		return {}
	var m: Dictionary = {
		"id": "boss_%s" % str(boss.get("id", "")),
		"name": str(boss.get("name", "BOSS")),
		"hp": boss_hp_base * float(boss.get("hp_pct", 1.0)),
		# Boss 攻击：以本层怪物强度为基准（第 1 层约 28，逐层上调）
		"atk": 28.0 * FloorDefs.monster_mult(floor_num) * float(boss.get("atk_pct", 1.0)),
		"defense": 10.0 + float(floor_num) * 2.0,
		"speed_pct": 60.0 if str(boss.get("ai", "")) == "melee" else 75.0,
		"attack_interval": 2.2,
		"attack_range": 2.6,
		"scale": 2.2,
		"is_boss": true,
		"ai": str(boss.get("ai", "melee")),
		"mechs": boss.get("mechs", []),
		"params": boss.get("params", {}),
		"special": _special_of(boss),
	}
	return m


## 从 Boss 的 params 推导 EnemyBase 的 special 字典（复用既有原语）
static func _special_of(boss: Dictionary) -> Dictionary:
	var p: Dictionary = boss.get("params", {})
	var s: Dictionary = {}
	if p.has("summon"):
		s["summon"] = p["summon"]
	if p.has("death_split"):
		s["death_split"] = true
		s["split_count"] = int(p.get("split_count", 2))
	if p.has("dash_range"):
		s["dash_range"] = float(p["dash_range"])
	return s


## 该 Boss 是否在某机制类下（供测试与运行时分支）
static func has_mech(boss: Dictionary, mech: String) -> bool:
	var mechs: Array = boss.get("mechs", [])
	return mechs.has(mech)
