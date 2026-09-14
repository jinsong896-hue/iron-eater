class_name MonsterDB
extends RefCounted
## 怪物数据库 —— 《噬铁者》怪物设计分册全量
##
## 数据源与口径：
##   第 4 章 基础怪 10 种 × 4 阶段 = 40（数值逐项对齐分册表格）
##   第 5 章 独特机制怪 16 种（第 2/4/6/8 层各 4）
##   第 6 章 第 9 层「混沌裂隙」终极池 8 种
##   第 7 章 词缀系统（见 affix_db.gd）
##
## 【假设 1 · 分册无防御值】分册只给血量/攻击/移速/间隔，无防御。
##   def 按类别推导：近战 3~8 / 远程 3~5 / 飞行 0，随阶段小幅递增。
##
## 【假设 2 · 独特怪无独立数值】第 5 章表格只有「类型 + 独特机制」，无数字。
##   故按「类型」映射到对应基础怪、取所在层对应阶段的数值。
##   例：矿道自爆者「缓慢近身·高威胁」→ 僵尸类第 2 层(阶段一)数值。
##
## 【假设 3 · 第 9 层无数值】第 6 章只给「类型 + 核心特征」，从阶段四推算。
##
## 机制实现现状：本版只落地「分裂 / 召唤 / 自爆」三种可复用机制，
## 其余约 50 个专属机制以 special 标记登记（见 docs/progress），引擎尚未实现。

static var _monsters: Dictionary = {}   ## id -> Dictionary
static var _initialized := false

## 阶段（每 2 层为一个阶段，分册 3.1）
const PHASE_OF_LAYER := {1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 3, 7: 4, 8: 4, 9: 5}


# ============================================================
# 基础怪 10 种 × 4 阶段
# 行格式：[key, ai, def, scale, weight, range, dodge%, fly_h,
#          [[名, 血, 攻, 移速%, 间隔, 机制标记] × 4 阶段]]
# 机制标记 none = 无；其余在引擎里未实现的以标记登记（见文件头说明）
# ============================================================
const BASE_TYPES := [
	# ① 缓慢近身（僵尸类）—— 分册 4.1
	["zombie", "melee", 5, 1.0, 1.0, 0.0, 0, 0.0, [
		["监牢僵尸",  120, 25,  50, 3.5, "none"],
		["墓穴僵尸",  180, 33,  55, 3.0, "summon_skeleton"],
		["熔炉僵尸",  270, 60,  66, 2.1, "summon_imp"],
		["虚空僵尸",  420, 98,  78, 1.5, "summon_rift"],
	]],
	# ② 缓慢近身·变体（毒/自爆类）—— 分册 4.2
	["miasma", "melee", 5, 1.0, 0.8, 0.0, 0, 0.0, [
		["毒瘴僵尸",  100, 20,  45, 3.0, "death_poison"],
		["腐毒僵尸",  150, 26,  50, 2.6, "death_poison_big"],
		["硫磺僵尸",  225, 47,  60, 1.8, "death_sulfur"],
		["熵毒僵尸",  350, 77,  71, 1.3, "death_entropy"],
	]],
	# ③ 移动低频低射程远程 —— 分册 4.3
	["archer", "kite", 3, 1.0, 1.0, 8.0, 0, 0.0, [
		["骷髅弓手",   70, 20,  80, 4.0, "none"],
		["骸骨弓手",  105, 26,  88, 3.4, "haste_when_melee"],
		["炎骨弓手",  158, 47,  96, 2.4, "arrow_explode"],
		["虚空弓手",  245, 77, 104, 1.7, "arrow_split"],
	]],
	# ④ 固定远射程（哨兵）—— 分册 4.4
	["sentry", "sentry", 5, 1.0, 0.7, 15.0, 0, 0.0, [
		["墓穴哨兵",   50, 25,   0, 5.0, "none"],
		["符文哨兵",   75, 33,   0, 4.3, "pierce_every_3"],
		["熔炉哨兵",  113, 60,   0, 3.0, "shot_fire_zone"],
		["虚空哨卫",  175, 98,   0, 2.1, "shot_void_echo"],
	]],
	# ⑤ 普通速度近身高伤害 —— 分册 4.5
	["berserker", "melee", 3, 1.1, 0.9, 0.0, 0, 0.0, [
		["狂暴囚犯",    80, 40, 105, 3.0, "none"],
		["狂乱囚徒",   120, 52, 116, 2.6, "enrage_low_hp"],
		["狂怒恶魔",   180, 94, 126, 1.8, "atk_stack_on_hit"],
		["虚空狂战士", 280, 154, 137, 1.3, "healcut_on_hit"],
	]],
	# ⑥ 突进近战（猎犬）—— 分册 4.6
	["hound", "rusher", 3, 0.9, 1.0, 0.0, 0, 0.0, [
		["狱卒猎犬",   90, 30, 120, 3.5, "dash_stun_self"],
		["骸骨猎犬",  135, 39, 132, 3.0, "dash_slow_trap"],
		["熔岩猎犬",  203, 70, 144, 2.1, "dash_lava_trail"],
		["虚空猎犬",  315, 115, 156, 1.5, "dash_root"],
	]],
	# ⑦ 飞行近战（蝙蝠）—— 分册 4.7
	["bat", "flyer_melee", 0, 0.7, 1.0, 0.0, 0, 1.5, [
		["石翼蝙蝠",   40, 15, 110, 3.0, "knockback_on_hit"],
		["墓穴蝙蝠",   60, 20, 121, 2.6, "split_on_hit"],
		["硫磺蝙蝠",   90, 36, 132, 1.8, "dodge_on_hit"],
		["虚空蝠群",  140, 59, 143, 1.3, "teleport_behind"],
	]],
	# ⑧ 飞行低血量远程（鬼火）—— 分册 4.8
	["wisp", "flyer_ranged", 0, 0.6, 0.8, 10.0, 0, 1.2, [
		["鬼火灵体",   30, 18,  90, 4.0, "backstep_on_shot"],
		["怨灵火",     45, 23,  99, 3.4, "triple_shot"],
		["硫磺幽魂",   68, 42, 108, 2.4, "slow_on_hit"],
		["熵能幽灵",  105, 69, 117, 1.7, "swap_positions"],
	]],
	# ⑨ 缓慢高血量大体积（巨鼠）—— 分册 4.9
	["rat", "melee", 8, 1.8, 0.5, 0.0, 0, 0.0, [
		["巨型变异老鼠", 250, 30, 35, 4.0, "none"],
		["墓穴巨鼠",     375, 39, 39, 3.4, "fear_roar"],
		["熔岩巨兽",     563, 70, 42, 2.4, "lava_aura"],
		["虚空巨兽",     875, 115, 46, 1.7, "void_gravity"],
	]],
	# ⑩ 高闪避低血量 —— 分册 4.10
	["phantom", "melee", 0, 0.9, 0.7, 0.0, 30, 0.0, [
		["迷雾幽灵",   60, 28,  85, 4.0, "dodge_break"],
		["暗影幽魂",   90, 36,  94, 3.4, "dodge_teleport"],
		["灰烬行者",  135, 65, 102, 2.4, "ash_form"],
		["虚空魅影",  210, 106, 111, 1.7, "stealth_ambush"],
	]],
]


# ============================================================
# 第 5 章 独特机制怪 16 种
# 行格式：[id, 名, 出现层, ai, 原型基础怪, 取该原型第几阶段, scale, weight, 机制标记]
# 数值按「原型基础怪 × 阶段」推导（见文件头假设 2）
# ============================================================
const UNIQUE_TABLE := [
	# 第 2 层（阶段一 · 4 种）
	["mine_bomber",     "矿道自爆者", 2, "melee",        "zombie",  2, 1.0, 0.8, "death_explode"],
	["orb_bomber",      "轨道投弹手", 2, "kite",         "archer",  2, 1.0, 0.8, "delayed_bomb"],
	["shadow_lurker",   "暗影潜伏者", 2, "melee",        "phantom", 2, 0.9, 0.8, "stealth"],
	["crystal_beetle",  "矿晶甲虫",   2, "melee",        "rat",     2, 1.0, 0.6, "armor_break"],
	# 第 4 层（阶段二 · 4 种）
	["water_spore",     "水孢行者",   4, "melee",        "miasma",  2, 1.0, 0.8, "death_split"],
	["venom_frog",      "毒腺蛙",     4, "kite",         "archer",  2, 1.0, 0.8, "poison_zone"],
	["wetland_ambusher","湿地伏击者", 4, "melee",        "phantom", 2, 0.9, 0.8, "ambush"],
	["swamp_giant",     "沼泽巨人",   4, "melee",        "rat",     2, 1.6, 0.5, "water_pulse"],
	# 第 6 层（阶段三 · 4 种）
	["sulfur_elemental","硫磺元素",   6, "flyer_ranged", "wisp",    3, 0.8, 0.8, "bounce_shot"],
	["forge_core",      "熔炉核心",   6, "sentry",       "sentry",  3, 1.2, 0.6, "pulse_invuln"],
	["ash_walker",      "灰烬行者",   6, "melee",        "phantom", 3, 1.0, 0.8, "ash_form"],
	["flame_spawn",     "炎魔幼体",   6, "melee",        "rat",     3, 1.3, 0.5, "flame_aura"],
	# 第 8 层（阶段四 · 4 种）
	["void_hunter",     "虚空猎手",   8, "rusher",       "hound",   4, 1.0, 0.8, "long_dash_root"],
	["entropy_float",   "熵能浮体",   8, "flyer_ranged", "wisp",    4, 0.8, 0.8, "mark_player"],
	["time_warp",       "时间畸变者", 8, "kite",         "archer",  4, 1.0, 0.8, "slow_haste"],
	["void_guard",      "虚无守卫",   8, "melee",        "rat",     4, 1.4, 0.5, "rage_on_hit"],
]


# ============================================================
# 第 6 章 第 9 层「混沌裂隙」终极池（8 种，全部精英）
# 行格式：[id, 名, ai, 原型基础怪, scale, weight, 机制标记, 最低词缀数]
# 数值从阶段四推算（见文件头假设 3）
# ============================================================
const LAYER9_TABLE := [
	["chaos_blade",   "混沌利刃",   "rusher",       "hound",  1.0, 1.0, "true_damage",    2],
	["rift_archer",   "裂隙射手",   "sentry",       "sentry", 1.0, 1.0, "triple_shot",    2],
	["warped_beast",  "扭曲巨兽",   "melee",        "rat",    1.5, 0.8, "gravity_pull",   2],
	["entropy_wraith","熵能幽魂",   "flyer_ranged", "wisp",   1.0, 1.0, "swap_positions", 2],
	["void_devourer", "虚空吞噬者", "melee",        "zombie", 1.2, 0.8, "devour_grow",    2],
	["chaos_spider",  "混沌幼蛛",   "flyer_melee",  "bat",    1.0, 1.0, "death_split",    2],
	["shadow_sentry", "暗影哨兵",   "sentry",       "sentry", 1.0, 1.0, "shield_immune",  3],
	["ruin_avatar",   "破坏神投影", "melee",        "rat",    1.6, 0.6, "boss_skill",     3],
]

## 第 9 层基准倍率（从阶段四推算；分册未给数值）
const LAYER9_MULT := 1.3

## 精英倍率（分册 3.2 注：血量 ×1.5~2.0，攻击 ×1.3~1.5）
const ELITE_HP_MIN := 1.5
const ELITE_HP_MAX := 2.0
const ELITE_ATK_MIN := 1.3
const ELITE_ATK_MAX := 1.5


## 初始化（幂等）
static func init() -> void:
	if _initialized:
		return
	_initialized = true
	_build_base_monsters()
	_build_unique_monsters()
	_build_layer9_monsters()


## 兼容旧接口名
static func init_layer1() -> void:
	init()


# ============================================================
# 构建
# ============================================================

## 基础怪：10 种 × 4 阶段。阶段一的 id 沿用旧名（保持刷怪点数据兼容）
static func _build_base_monsters() -> void:
	for row in BASE_TYPES:
		var key: String = row[0]
		var ai: String = row[1]
		var def_v: int = row[2]
		var scale: float = row[3]
		var weight: float = row[4]
		var rng_range: float = row[5]
		var dodge: float = row[6]
		var fly_h: float = row[7]
		var stages: Array = row[8]
		for i in stages.size():
			var st: Array = stages[i]
			var phase := i + 1
			var id := _base_id(key, phase)
			_monsters[id] = {
				"id": id,
				"name": st[0],
				"ai": ai,
				"hp": st[1],
				"atk": st[2],
				"defense": def_v + (phase - 1),   # 假设 1：随阶段小幅递增
				"speed_pct": st[3],
				"attack_interval": st[4],
				"attack_range": rng_range,
				"dodge_pct": dodge / 100.0,
				"scale": scale,
				"weight": weight,
				"special": _special_for(str(st[5])),
				"phase": phase,
				"base_key": key,
				"is_elite": false,
				"is_unique": false,
			}
			# 阶段一同时注册旧 id，保证既有生成点/测试不失效
			var legacy := _legacy_id(key)
			if phase == 1 and legacy != "":
				var alias: Dictionary = _monsters[id].duplicate()
				alias["id"] = legacy
				_monsters[legacy] = alias


## 独特机制怪：数值继承原型基础怪在指定阶段的数值
static func _build_unique_monsters() -> void:
	for row in UNIQUE_TABLE:
		var id: String = row[0]
		var layer: int = row[2]
		var ai: String = row[3]
		var proto: String = row[4]
		var proto_phase: int = row[5]
		var scale: float = row[6]
		var weight: float = row[7]
		var mech: String = row[8]
		var base: Dictionary = _monsters.get(_base_id(proto, proto_phase), {})
		if base.is_empty():
			continue
		_monsters[id] = {
			"id": id,
			"name": row[1],
			"ai": ai,
			"hp": int(base.hp * scale),
			"atk": base.atk,
			"defense": base.defense,
			"speed_pct": base.speed_pct,
			"attack_interval": base.attack_interval,
			"attack_range": base.attack_range,
			"dodge_pct": base.dodge_pct,
			"scale": scale,
			"weight": weight,
			"special": _special_for(mech),
			"phase": PHASE_OF_LAYER.get(layer, 1),
			"base_key": proto,
			"appears_layer": layer,      # 只在本层及相邻层出现
			"is_elite": false,
			"is_unique": true,
		}


## 第 9 层终极池：从阶段四推算倍率，全部为精英
static func _build_layer9_monsters() -> void:
	for row in LAYER9_TABLE:
		var id: String = row[0]
		var proto: String = row[3]
		var base: Dictionary = _monsters.get(_base_id(proto, 4), {})
		if base.is_empty():
			continue
		_monsters[id] = {
			"id": id,
			"name": row[1],
			"ai": row[2],
			"hp": int(base.hp * LAYER9_MULT),
			"atk": int(base.atk * LAYER9_MULT),
			"defense": base.defense,
			"speed_pct": base.speed_pct,
			"attack_interval": base.attack_interval,
			"attack_range": base.attack_range,
			"dodge_pct": base.dodge_pct,
			"scale": row[4],
			"weight": row[5],
			"special": _special_for(str(row[6])),
			"phase": 5,
			"base_key": proto,
			"appears_layer": 9,
			"is_elite": true,             # 第 9 层全部精英
			"min_affixes": row[7],
			"is_unique": false,
		}


## 基础怪 id：阶段一沿用旧名，2~4 用「键_阶段后缀」
static func _base_id(key: String, phase: int) -> String:
	if phase == 1:
		return _legacy_id(key)
	return "%s_p%d" % [key, phase]


## 阶段一的旧 id（与既有刷怪点/测试一致）
static func _legacy_id(key: String) -> String:
	match key:
		"zombie": return "zombie_prison"
		"miasma": return "zombie_miasma"
		"archer": return "skeleton_archer"
		"sentry": return "tomb_sentinel"
		"berserker": return "berserk_prisoner"
		"hound": return "hound_jailer"
		"bat": return "bat_stonewing"
		"wisp": return "wisp_ghostfire"
		"rat": return "rat_mutant"
		"phantom": return "mist_phantom"
	return ""


## 机制标记 → special 字典（引擎已实现的键保持原样，其余仅作登记）
static func _special_for(mech: String) -> Dictionary:
	match mech:
		# —— 引擎已实现的机制 ——
		"death_poison": return {"death_poison": true}
		"death_explode": return {"death_explode": true, "explode_damage": 40.0, "explode_radius": 3.0}
		"death_split": return {"death_split": true, "split_count": 2}
		"summon_skeleton": return {"summon": {"id": "skeleton_minion", "count": 1, "chance": 0.2}}
		"summon_imp": return {"summon": {"id": "forge_imp", "count": 2, "chance": 1.0}}
		"summon_rift": return {"summon": {"id": "void_rift", "count": 1, "chance": 1.0}}
		# —— 以下为登记（引擎尚未实现，见文件头说明）——
	return {"mechanic": mech}


# ============================================================
# 查询
# ============================================================

## 按 id 查询
static func get_monster(id: String) -> Dictionary:
	init()
	return _monsters.get(id, {})


## 全部怪物
static func all_monsters() -> Array:
	init()
	return _monsters.values()


## 全部基础怪（排除旧 id 别名与独特怪、第9层）
static func all_base_monsters() -> Array:
	init()
	var out: Array = []
	for m in _monsters.values():
		if not m.get("is_unique", false) and int(m.get("phase", 0)) <= 4:
			out.append(m)
	return out


## 指定层可用的怪物池
## 规则（分册 3.1）：基础怪取本层所在阶段；独特怪只在本层及相邻层出现；
## 第 9 层走独立终极池
static func pool_for_layer(layer: int) -> Array:
	init()
	if layer >= 9:
		var ult: Array = []
		for m in _monsters.values():
			if int(m.get("appears_layer", -1)) == 9:
				ult.append(m)
		return ult

	var phase: int = PHASE_OF_LAYER.get(clampi(layer, 1, 8), 1)
	var pool: Array = []
	for m in _monsters.values():
		if m.get("is_unique", false):
			# 独特怪：本层及相邻层（第 9 层的终极怪不走这条，见上层 early return）
			var al: int = int(m.get("appears_layer", -1))
			if al >= 2 and al <= 8 and absi(al - layer) <= 1:
				pool.append(m)
		elif int(m.get("phase", 0)) == phase and int(m.get("appears_layer", 0)) == 0:
			pool.append(m)
	return pool


## 指定层的精英池（偏高血/高攻者）
static func elite_pool_for_layer(layer: int) -> Array:
	var out: Array = []
	for m in pool_for_layer(layer):
		if str(m.get("ai", "")) == "melee" and int(m.get("hp", 0)) >= 150:
			out.append(m)
	return out if not out.is_empty() else pool_for_layer(layer)


## 按权重随机一只（指定层）
static func random_for_layer(layer: int, rng: RandomNumberGenerator) -> Dictionary:
	return _weighted_pick(pool_for_layer(layer), rng)


## 按权重随机一只精英（指定层）
static func random_elite_for_layer(layer: int, rng: RandomNumberGenerator) -> Dictionary:
	var m := _weighted_pick(elite_pool_for_layer(layer), rng)
	if m.is_empty():
		return m
	return apply_elite_scaling(m, rng)


## 精英倍率（分册 3.2 注）
static func apply_elite_scaling(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var e: Dictionary = m.duplicate()
	e["hp"] = int(float(m["hp"]) * rng.randf_range(ELITE_HP_MIN, ELITE_HP_MAX))
	e["atk"] = int(float(m["atk"]) * rng.randf_range(ELITE_ATK_MIN, ELITE_ATK_MAX))
	e["is_elite"] = true
	e["scale"] = float(m.get("scale", 1.0)) * 1.15
	return e


## 兼容旧接口：任意普通怪（默认第 1 层）
static func random_monster(rng: RandomNumberGenerator) -> Dictionary:
	return random_for_layer(1, rng)


## 兼容旧接口：任意精英（默认第 1 层）
static func random_elite(rng: RandomNumberGenerator) -> Dictionary:
	return random_elite_for_layer(1, rng)


## 兼容旧接口：Boss（第 1 层为鼠王·变异巨鼠）
static func boss_monster() -> Dictionary:
	init()
	var base := get_monster("rat_mutant").duplicate()
	base["name"] = "鼠王·变异巨鼠"
	base["hp"] = int(base.hp * 2.4)
	base["atk"] = int(base.atk * 1.3)
	base["scale"] = 2.2
	base["is_boss"] = true
	return base


## 加权随机
static func _weighted_pick(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	if pool.is_empty():
		return {}
	var total := 0.0
	for m in pool:
		total += float(m.get("weight", 1.0))
	var roll := rng.randf() * total
	for m in pool:
		roll -= float(m.get("weight", 1.0))
		if roll <= 0.0:
			return m
	return pool[pool.size() - 1]
