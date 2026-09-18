class_name LootSystem
extends RefCounted
## 掉落系统 —— HD-2D 重构版
## 敌人死亡 → 金币直接入账 + 按掉率随机掉白装 → 掉落物可拾取/吞噬
## enemy_data 兼容 MonsterData（.tres）与动态 Dictionary 两种来源

var rng := RandomNumberGenerator.new()


## 生成掉落（enemy_data: MonsterData / EnemyBase / Dictionary）
## Boss 走独立的策划掉落表（保底装备 + 碎片 + 策划金币 + 额外掉落），
## 其余敌人用通用的金币 + 概率装备。
func generate_loot(enemy_data, position: Vector3, parent: Node3D) -> void:
	if _is_boss(enemy_data):
		_generate_boss_loot(enemy_data, position, parent)
		return

	# 金币掉落（直接入账）
	var gold := _roll_gold(enemy_data)
	var gm = _game_manager()
	var bus = _event_bus()
	if gold > 0 and gm:
		gm.gold += gold
		if bus:
			bus.gold_changed.emit(gm.gold)

	# 装备掉落：优先显式掉落表，否则按概率从白装池随机
	var template := _roll_template(enemy_data)
	if template == null:
		return

	var item := EquipmentInstance.create(template)
	_spawn_pickup(item, position, parent)


## Boss 掉落（关卡分册 6.2~6.9 各层「掉落标准」）。
## 四项独立结算：
##   ① 保底装备 ×1（按层稀有度：1~5 层橙、6~8 层红）
##   ② 钥匙碎片 ×1（按层概率 30~35%，集齐 8 片解锁隐藏层）
##   ③ 金币（按层区间，直接入账）
##   ④ 额外装备（按层概率与稀有度：蓝装/紫装）
func _generate_boss_loot(enemy_data, position: Vector3, parent: Node3D) -> void:
	var floor_num := _current_floor()
	var spec := FloorDefs.boss_drop(floor_num)
	var gm = _game_manager()
	var bus = _event_bus()

	# ③ 金币（直接入账）
	var gold_range := FloorDefs.boss_gold_range(floor_num)
	var gold := 0
	if gold_range.y > 0.0:
		gold = rng.randi_range(int(gold_range.x), int(gold_range.y))
		if gm:
			gm.gold += gold
			if bus:
				bus.gold_changed.emit(gm.gold)

	# ① 保底装备
	var offset := 0.0
	var pity := _random_template_of_rarity(int(spec.get("rarity", EquipmentDefs.Rarity.ORANGE)))
	if pity != null:
		_spawn_pickup(EquipmentInstance.create(pity),
			position + Vector3(offset, 0.0, 0.0), parent)
		offset += 0.7

	# ④ 额外装备
	var extra_chance := float(spec.get("extra_chance", 0.0))
	if extra_chance > 0.0 and rng.randf() < extra_chance:
		var extra := _random_template_of_rarity(int(spec.get("extra_rarity", EquipmentDefs.Rarity.BLUE)))
		if extra != null:
			_spawn_pickup(EquipmentInstance.create(extra),
				position + Vector3(offset, 0.0, 0.0), parent)
			offset += 0.7

	# ② 钥匙碎片（不生成拾取物——局内计数 + 局外累积，见 GameManager.add_key_fragment）
	var frag_chance := FloorDefs.boss_fragment_chance(floor_num)
	if frag_chance > 0.0 and rng.randf() < frag_chance:
		if gm and gm.has_method("add_key_fragment"):
			gm.call("add_key_fragment", floor_num)
			if bus:
				bus.message.emit("获得钥匙碎片（%d/8）" % int(gm.get("run_key_fragments")))


## 隐藏房奖励掉落（策划 3.2：专属橙色装备，带特殊词条）。
## 隐藏房是每层限量 2 间的高价值目标，故保底**橙装**而非按层加权随机，
## 且给两件（策划 3.2 列了「红装碎片 + 大量金币 + 稀有消耗品 + 专属橙装」四项，
## 装备部分按橙装 ×2 表达；消耗品与金币由宝箱本体结算）。
func generate_hidden_room_loot(position: Vector3, parent: Node3D) -> void:
	var orange := _random_template_of_rarity(EquipmentDefs.Rarity.ORANGE)
	if orange != null:
		_spawn_pickup(EquipmentInstance.create(orange),
			position + Vector3(-0.35, 0.0, 0.0), parent)
	# 第二件：按层加权（高层可能出红装，与"专属高价值"定位一致）
	var bonus := _random_template_of_rarity(_roll_rarity(_current_floor()))
	if bonus != null:
		_spawn_pickup(EquipmentInstance.create(bonus),
			position + Vector3(0.35, 0.0, 0.0), parent)


## 宝箱掉落：必掉 count 件，稀有度按层加权抽取（无金币——金币由 Chest 自身入账）
## 宝箱是策划指定的高稀有度补充渠道之一（总册 3.4）
func generate_chest_loot(position: Vector3, parent: Node3D, count: int = 1) -> void:
	var floor := _current_floor()
	for i in range(count):
		var template := _random_template_of_rarity(_roll_rarity(floor))
		if template == null:
			continue
		var item := EquipmentInstance.create(template)
		_spawn_pickup(item, position + Vector3(float(i) * 0.6 - 0.3, 0.0, 0.0), parent)


## 获取 GameManager autoload（--script 测试模式下不存在，返回 null）
func _game_manager():
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("GameManager")
	return null


## 获取 EventBus autoload（--script 测试模式下不存在，返回 null）
func _event_bus():
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("EventBus")
	return null


## 金币掉落（来源字段优先，否则击杀基线范围随机）
func _roll_gold(enemy_data) -> int:
	if enemy_data == null:
		return 0
	var base_lo := int(GameBalance.KILL_GOLD_RANGE.x)
	var base_hi := int(GameBalance.KILL_GOLD_RANGE.y)
	if enemy_data is Dictionary:
		return int(enemy_data.get("gold", rng.randi_range(base_lo, base_hi)))
	if "gold_min" in enemy_data and "gold_max" in enemy_data:
		return rng.randi_range(int(enemy_data.gold_min), int(enemy_data.gold_max))
	return rng.randi_range(base_lo, base_hi)


## 掉落装备模板：显式掉落表优先；Boss 必掉（按层保底）；精英高概率；否则按基础概率
## 稀有度由 _roll_rarity 加权抽取（权重随层数向高稀有度倾斜）
func _roll_template(enemy_data) -> EquipmentTemplate:
	# 显式掉落表
	var loot_id := _explicit_loot_id(enemy_data)
	if not loot_id.is_empty():
		return EquipmentDB.get_template(StringName(loot_id))

	var floor := _current_floor()

	# Boss：必掉，按层保底稀有度（1~5 层橙、6 层起红），不吃概率判定
	if _is_boss(enemy_data):
		return _random_template_of_rarity(_boss_pity_rarity(floor))

	# 精英：走 ELITE_DROP_CHANCE（此前该常量定义但无人使用）
	# 掉落率随层递减，避免后期"每房一地装备"淹没玩家（见 GameBalance 常量注释）
	var chance := GameBalance.ELITE_DROP_CHANCE if _is_elite(enemy_data) else GameBalance.BASE_DROP_CHANCE
	chance = _floor_decayed_chance(chance, floor)
	if rng.randf() > chance:
		return null
	return _random_template_of_rarity(_roll_rarity(floor))


## 按层数衰减掉落概率（向下取整到 DROP_CHANCE_MIN）。
## 稀有度权重向高稀有度倾斜已经提供了"越深越强"的收益，
## 数量侧必须反向收紧，否则后期刷怪密度 × 恒定掉落率的乘积会让背包长期爆满。
func _floor_decayed_chance(base_chance: float, floor_num: int) -> float:
	var f: int = maxi(floor_num, 1)
	return maxf(GameBalance.DROP_CHANCE_MIN,
		base_chance * pow(GameBalance.DROP_CHANCE_DECAY, f - 1))


## Boss 保底稀有度：由 FloorDefs 的掉落表给出（1~5 层橙、6 层起红）。
## 策划依据：关卡分册 6.2~6.9 各层「掉落标准」，
## 第 6 层明写「Boss 保底升级为红装 ×1（自第 6 层起）」。
func _boss_pity_rarity(floor_num: int) -> int:
	return FloorDefs.boss_rarity(floor_num)


## 按层数加权的稀有度抽取
## 权重 = 基础权重 × (1 + 层级加成 × (层数-1))，白色不随层数增长
## 红色权重为 0（不参与随机掉落，仅 Boss 保底产出）
func _roll_rarity(floor_num: int) -> int:
	var weights := rarity_weights_for_floor(floor_num)
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return EquipmentDefs.Rarity.WHITE

	# 加权抽取
	var roll := rng.randf() * total
	var acc := 0.0
	for r in weights.size():
		acc += float(weights[r])
		if roll < acc:
			return r
	return EquipmentDefs.Rarity.WHITE


## 按层数缩放后的稀有度权重（纯函数，供测试直接验证）
## 返回长度与 RARITY_WEIGHTS 一致的浮点数组
static func rarity_weights_for_floor(floor_num: int) -> Array:
	var weights: Array = []
	for r in GameBalance.RARITY_WEIGHTS.size():
		var w: float = float(GameBalance.RARITY_WEIGHTS[r])
		var gain: float = float(GameBalance.RARITY_FLOOR_GAIN[r])
		if gain > 0.0:
			w *= 1.0 + gain * float(maxi(floor_num - 1, 0))
		weights.append(w)
	return weights


## 从指定稀有度池随机取一件模板；该池为空时回退到白装池
func _random_template_of_rarity(rarity: int) -> EquipmentTemplate:
	var pool := EquipmentDB.get_templates_by_rarity(rarity)
	if pool.is_empty():
		pool = EquipmentDB.get_templates_by_rarity(EquipmentDefs.Rarity.WHITE)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


## 当前层数（无 GameManager 时按第 1 层）
func _current_floor() -> int:
	var gm = _game_manager()
	if gm == null:
		return 1
	var info = gm.get("run_info")
	if info is Dictionary:
		return int(info.get("floor", 1))
	return 1


## 是否 Boss（Dictionary 的 boss 字段 / Object 的 boss_loot meta）
func _is_boss(enemy_data) -> bool:
	if enemy_data == null:
		return false
	if enemy_data is Dictionary:
		return bool(enemy_data.get("boss", false))
	if enemy_data is Object and enemy_data.has_meta("boss_loot"):
		return bool(enemy_data.get_meta("boss_loot"))
	return false


## 是否精英（Dictionary 的 elite 字段 / Object 的 is_elite 属性）
func _is_elite(enemy_data) -> bool:
	if enemy_data == null:
		return false
	if enemy_data is Dictionary:
		return bool(enemy_data.get("elite", false))
	if enemy_data is Object and enemy_data.has_meta("elite_loot"):
		return true
	if "is_elite" in enemy_data:
		return bool(enemy_data.is_elite)
	return false


## 显式掉落 ID（loot_table 字段）
func _explicit_loot_id(enemy_data) -> String:
	if enemy_data == null:
		return ""
	if enemy_data is Dictionary:
		return str(enemy_data.get("loot", ""))
	if "loot_table" in enemy_data:
		return str(enemy_data.loot_table)
	return ""


## 创建掉落物节点（走近可拾取，F 可吞噬）
##
## **动画与查找交给 PickupField 集中管理**（见该文件）：
## 掉落物自身不跑 `_process`，拾取也不靠遍历 `group("pickups")`。
## 本函数只负责"造出这一件、给它正确的视觉与数据"。
func _spawn_pickup(item: EquipmentInstance, position: Vector3, parent: Node3D) -> void:
	var pickup := Node3D.new()
	pickup.name = "Pickup_%s" % item.display_name()
	pickup.position = position + Vector3(0.0, 0.5, 0.0)
	pickup.add_to_group("pickups")

	# 视觉：稀有度颜色的发光方块
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	mesh.mesh = box

	var rarity_color: Color = EquipmentDefs.RARITY_COLORS.get(item.rarity, Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = rarity_color
	mat.emission_enabled = true
	mat.emission = rarity_color
	mat.emission_energy_multiplier = 0.5
	mesh.material_override = mat

	pickup.set_meta("instance_id", item.instance_id)
	pickup.set_meta("template_id", str(item.template_id))
	pickup.set_meta("rarity", item.rarity)
	pickup.set_script(PICKUP_SCRIPT)
	pickup.set("item", item)

	pickup.add_child(mesh)
	parent.add_child(pickup)
	# 登记到集中管理器（接管动画 + 空间分桶 + 上限淘汰）
	_field_for(parent).register(pickup)


## 掉落物脚本（引擎预编译的资源，不再运行时生成 GDScript）
const PICKUP_SCRIPT := preload("res://gameplay/loot/pickup_item.gd")


## 取/建本房间的掉落物管理器。
##
## **统一挂到房间根**（而不是调用方传进来的 parent）：
## 调用方有两条——节点式敌人传的是 RoomController（敌人挂在它下面），
## 群体掉落传的是房间根。若不归一，同一个房间会出现**两个 PickupField**，
## 各自只看得见自己那半掉落物，拾取时漏掉一半。
func _field_for(parent: Node) -> PickupField:
	var root := _room_root_of(parent)
	var existing: Node = root.get_node_or_null("PickupField")
	if existing is PickupField:
		return existing
	var field := PickupField.new()
	field.name = "PickupField"
	root.add_child(field)
	return field


## 从任意房间内节点向上找到房间根（带 RoomController 的那个）。
## 找不到时回退用传入的节点（保证测试里裸建也能工作）。
func _room_root_of(node: Node) -> Node:
	var n := node
	while n != null:
		if n.get_node_or_null("RoomController") != null:
			return n
		n = n.get_parent()
	return node
