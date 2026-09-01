class_name MonsterDB
extends RefCounted
## 第一层怪物数据库（表驱动，白装 DB 同模式）
## 数据源：《噬铁者》怪物设计分册 4.1~4.10（阶段一数值）
## 10 种：监牢僵尸/毒瘴僵尸/骷髅弓手/墓穴哨兵/狂暴囚犯/狱卒猎犬/
##       石翼蝙蝠/鬼火灵体/巨型变异老鼠/迷雾幽灵
## 注意：怪物无暴击、伤害为固定值（名词分册口径）；移速为玩家基准百分比

static var _monsters: Dictionary = {}  ## id -> Dictionary
static var _initialized := false

## AI 类型：melee（近战追击）/ kite（远程风筝）/ sentry（固定炮台）/
## rusher（突进）/ flyer_melee（飞行近战）/ flyer_ranged（飞行远程）
## [id, 名称, ai, hp, atk, def, spd%, 间隔s, 射程, 闪避%, 体型, 权重, 特殊标记]
const LAYER1_TABLE := [
	["zombie_prison", "监牢僵尸", "melee", 120, 25, 5, 50, 3.5, 0.0, 0, 1.0, 1.0, {}],
	["zombie_miasma", "毒瘴僵尸", "melee", 100, 20, 5, 45, 3.0, 0.0, 0, 1.0, 0.8, {"death_poison": true}],
	["skeleton_archer", "骷髅弓手", "kite", 70, 20, 3, 80, 4.0, 8.0, 0, 1.0, 1.0, {"kite_range": 5.0}],
	["tomb_sentinel", "墓穴哨兵", "sentry", 50, 25, 5, 0, 5.0, 15.0, 0, 1.0, 0.7, {}],
	["berserk_prisoner", "狂暴囚犯", "melee", 80, 40, 3, 105, 3.0, 0.0, 0, 1.1, 0.9, {}],
	["hound_jailer", "狱卒猎犬", "rusher", 90, 30, 3, 120, 3.5, 0.0, 0, 0.9, 1.0, {"dash_range": 2.0}],
	["bat_stonewing", "石翼蝙蝠", "flyer_melee", 40, 15, 0, 110, 3.0, 0.0, 0, 0.7, 1.0, {"fly_height": 1.5}],
	["wisp_ghostfire", "鬼火灵体", "flyer_ranged", 30, 18, 0, 90, 4.0, 10.0, 0, 0.6, 0.8, {"fly_height": 1.2}],
	["rat_mutant", "巨型变异老鼠", "melee", 250, 30, 8, 35, 4.0, 0.0, 0, 1.8, 0.5, {}],
	["mist_phantom", "迷雾幽灵", "melee", 60, 28, 0, 85, 4.0, 0.0, 30, 0.9, 0.7, {"dodge": 0.30}],
]


## 初始化（幂等）
static func init_layer1() -> void:
	if _initialized:
		return
	_initialized = true
	for row in LAYER1_TABLE:
		_monsters[row[0]] = _make_monster(row)


## 行数据 → 怪物字典
static func _make_monster(row: Array) -> Dictionary:
	return {
		"id": row[0],
		"name": row[1],
		"ai": row[2],
		"hp": row[3],
		"atk": row[4],
		"defense": row[5],
		"speed_pct": row[6],       # 玩家移速百分比
		"attack_interval": row[7],
		"attack_range": row[8],     # 远程射程（米）
		"dodge_pct": row[9] / 100.0,  # 闪避率（表里是百分数）
		"scale": row[10],           # 体型缩放
		"weight": row[11],          # 刷怪权重
		"special": row[12],         # 特殊行为标记
	}


## 查询：按 id
static func get_monster(id: String) -> Dictionary:
	return _monsters.get(id, {})


## 查询：全部
static func all_monsters() -> Array:
	return _monsters.values()


## 按权重随机一只（普通房）
static func random_monster(rng: RandomNumberGenerator) -> Dictionary:
	return _weighted_pick(all_monsters(), rng)


## 精英房池：偏高血/高攻（狂暴囚犯/猎犬/巨鼠/僵尸）
static func random_elite(rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = []
	for m in _monsters.values():
		if m.id in ["berserk_prisoner", "hound_jailer", "rat_mutant", "zombie_prison"]:
			pool.append(m)
	return _weighted_pick(pool, rng)


## Boss 房：鼠王·巨型变异老鼠（血 ×2.4 至 600 Boss 级，攻 ×1.3，精英体型）
static func boss_monster() -> Dictionary:
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
		total += m.weight
	var roll := rng.randf() * total
	for m in pool:
		roll -= m.weight
		if roll <= 0.0:
			return m
	return pool[pool.size() - 1]
