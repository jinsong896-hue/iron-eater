class_name EnemySpawner
extends RefCounted
## 敌人生成器 —— HD-2D 重构版
## 根据房间数据中的生成点，按难度和权重生成敌人

var rng := RandomNumberGenerator.new()
var _monster_cache: Dictionary = {}


## 从生成点生成敌人
func spawn_from_points(
	points: Array[Marker3D], difficulty: int, parent: Node3D
) -> Array[EnemyBase]:
	var spawned: Array[EnemyBase] = []
	for point in points:
		if rng.randf() < 0.7:  # 70% 概率生成
			var enemy := _create_enemy_at(point, difficulty)
			if enemy:
				parent.add_child(enemy)
				spawned.append(enemy)
	return spawned


## 在指定位置创建敌人
## 优先用 Marker3D 上 meta 的 monster_id 加载 MonsterData；无则用难度缩放的默认值
func _create_enemy_at(point: Marker3D, difficulty: int) -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.position = point.global_position

	var monster_id := str(point.get_meta("monster_id", ""))
	if monster_id != "":
		var data := _load_monster(monster_id)
		if data:
			enemy.max_hp = float(data.hp)
			enemy.atk = float(data.atk)
			enemy.defense = float(data.defense)
			enemy.move_speed = float(data.speed) / 40.0
			return enemy

	# 无 monster_id 或加载失败：按难度缩放的默认值
	var difficulty_mult := 1.0 + (difficulty - 1) * 0.2
	enemy.max_hp = 100.0 * difficulty_mult
	enemy.atk = 10.0 * difficulty_mult
	enemy.defense = 5.0 * difficulty_mult
	enemy.move_speed = 2.0 + difficulty * 0.2

	return enemy


## 加载怪物数据（带缓存）
func _load_monster(id: String) -> MonsterData:
	if _monster_cache.has(id):
		return _monster_cache[id]
	var data: MonsterData = load("res://data/monsters/" + id + ".tres")
	if data:
		_monster_cache[id] = data
	return data


## 生成 Boss
func spawn_boss(boss_data: EnemyData, position: Vector3, parent: Node3D) -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.position = position
	enemy.max_hp = boss_data.max_hp
	enemy.atk = boss_data.atk
	enemy.defense = boss_data.defense
	enemy.move_speed = boss_data.speed
	enemy.attack_range = boss_data.attack_range
	enemy.detect_range = boss_data.detect_range
	enemy.attack_interval = boss_data.attack_interval

	parent.add_child(enemy)
	return enemy