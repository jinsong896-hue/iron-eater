extends SceneTree
## 测试框架 —— HD-2D 重构版
## 用法：Godot --headless --path . --script res://tests/test_framework.gd
## 注意：--script 模式下 class_name 不可用，使用 load() 替代
## 注意：load() 返回 null（脚本编译失败）会被 _require_script 计入失败，
##       避免脚本加载失败导致整组测试被静默跳过形成"假绿灯"。

var _failed := 0
var _passed := 0
var _current_test := ""


func _init() -> void:
	print("=".repeat(60))
	print("测试框架启动 —— HD-2D 重构版")
	print("=".repeat(60))

	# 属性系统测试
	test_attribute_system()

	# 白装数据库测试（36 件 V1 基准池；先于通用装备测试，避免后者注册测试模板污染计数）
	test_white_equipment_db()

	# 装备系统测试
	test_equipment_system()

	# 伤害管线测试
	test_damage_pipeline()

	# 融合规则测试
	test_fusion_rules()

	# 房间数据测试
	test_room_data()

	# 房间刷怪闭环集成测试
	test_room_combat_loop()

	# Boss 房闭环测试
	test_boss_room_loop()

	print("=".repeat(60))
	if _failed == 0:
		print("ALL %d TESTS PASSED" % _passed)
	else:
		print("FAILED: %d / %d" % [_failed, _passed + _failed])
	print("=".repeat(60))
	quit(1 if _failed > 0 else 0)


## 加载被测脚本；编译失败（load 返回 null）计入失败并返回 null
func _require_script(path: String):
	var script = load(path)
	if script == null:
		_failed += 1
		print("  FAIL [%s]: 脚本加载失败（编译错误）: %s" % [_current_test, path])
	return script


func _check(condition: bool, desc: String, failed: Array = []) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL [%s]: %s" % [_current_test, desc])
		for f in failed:
			print("    %s" % f)


func test_attribute_system() -> void:
	_current_test = "AttributeSystem"
	print("\n--- %s ---" % _current_test)

	var AS = _require_script("res://data/attributes/attribute_system.gd")
	if AS == null:
		return
	var attrs = AS.new()
	_check(attrs.hp == 500.0, "初始 HP = 500", [attrs.hp])
	_check(attrs.max_hp == 500.0, "初始 max_hp = 500", [attrs.max_hp])

	attrs.take_damage(100.0)
	_check(attrs.hp == 400.0, "受到 100 伤害后 HP = 400", [attrs.hp])

	attrs.heal(50.0)
	_check(attrs.hp == 450.0, "治疗 50 后 HP = 450", [attrs.hp])

	_check(not attrs.is_dead(), "HP > 0 时未死亡")
	attrs.take_damage(500.0)
	_check(attrs.is_dead(), "HP <= 0 时死亡")

	# Modifier 测试
	var attrs2 = AS.new()
	attrs2.add_modifier("test", attrs2.STAT_BY_NAME.get("atk", 0), 10.0, 0.5)
	var atk: float = attrs2.get_value(attrs2.STAT_BY_NAME.get("atk", 0))
	_check(atk > 35.0, "加入 Modifier 后 ATK 增长", [atk])

	attrs2.remove_modifiers("test")
	var atk2: float = attrs2.get_value(attrs2.STAT_BY_NAME.get("atk", 0))
	_check(atk2 == 35.0, "移除 Modifier 后 ATK 恢复", [atk2])


func test_equipment_system() -> void:
	_current_test = "EquipmentSystem"
	print("\n--- %s ---" % _current_test)

	var ET = _require_script("res://data/equipment/equipment_template.gd")
	var ED = _require_script("res://data/equipment/equipment_defs.gd")
	var EI = _require_script("res://data/equipment/equipment_instance.gd")
	var EDB = _require_script("res://data/equipment/equipment_db.gd")
	var AD = _require_script("res://data/equipment/affix_data.gd")
	if ET == null or ED == null or EI == null or EDB == null or AD == null:
		return

	var template = ET.new()
	template.id = "test_sword"
	template.display_name = "测试剑"
	template.rarity = ED.Rarity.WHITE
	template.category = ED.Category.WEAPON

	var affix = AD.new()
	affix.id = "test_atk"
	affix.stat = 0
	affix.value = 10.0
	template.base_affix = affix

	EDB.register(template)

	var inst = EI.create(template)
	_check(inst.template_id == "test_sword", "实例 template_id 匹配")
	_check(inst.rarity == ED.Rarity.WHITE, "实例稀有度匹配")
	_check(inst.fusion_count == 0, "初始融合等级为 0")

	var d: Dictionary = inst.to_dict()
	var inst2 = EI.create(template)
	inst2.from_dict(d)
	_check(inst2.template_id == inst.template_id, "反序列化后 template_id 一致")


func test_white_equipment_db() -> void:
	_current_test = "WhiteEquipmentDB"
	print("\n--- %s ---" % _current_test)

	var EDB = _require_script("res://data/equipment/equipment_db.gd")
	var ED = _require_script("res://data/equipment/equipment_defs.gd")
	if EDB == null or ED == null:
		return

	EDB.init_white_equipment()

	_check(EDB.template_count() == 36, "白装总数 = 36（12 武器 + 18 护甲 + 6 饰品）", [EDB.template_count()])
	_check(EDB.get_templates_by_rarity(ED.Rarity.WHITE).size() == 36, "全部为白装稀有度")
	_check(EDB.get_templates_by_slot(ED.Slot.HEAD).size() == 3, "头部护甲 3 件（轻/中/重）")
	_check(EDB.get_templates_by_slot(ED.Slot.CHEST).size() == 3, "胸甲 3 件")

	# 抽查代表性条目
	var sword = EDB.get_template(&"W01")
	_check(sword != null, "W01 铁制单手剑存在")
	if sword:
		_check(sword.display_name == "铁制单手剑", "W01 名称正确", [sword.display_name])
		_check(sword.weapon_type == "sword", "W01 单手剑类型")
		_check(sword.is_one_handed_weapon(), "W01 判定为单手")
		_check(sword.base_affix.value == 35.0, "W01 基础 ATK +35", [sword.base_affix.value])
		_check(sword.devour_affix.value == 0.5, "W01 吞噬 ATK +0.5", [sword.devour_affix.value])
		_check(sword.fusion_affix.value == 0.03, "W01 融合 ATK +3%", [sword.fusion_affix.value])

	var greatsword = EDB.get_template(&"W06")
	_check(greatsword != null, "W06 铁制巨剑存在")
	if greatsword:
		_check(greatsword.is_two_handed_weapon(), "W06 判定为双手")
		_check(greatsword.base_affix.value == 56.0, "W06 基础 ATK +56", [greatsword.base_affix.value])

	var staff = EDB.get_template(&"W11")
	_check(staff != null, "W11 学徒长杖存在")
	if staff:
		_check(staff.base_affix.stat == 6, "W11 基础词条为 AP（Stat.AP=6）", [staff.base_affix.stat])

	var helm = EDB.get_template(&"A03")
	_check(helm != null, "A03 铁制头盔存在")
	if helm:
		_check(helm.armor_class == ED.ArmorClass.HEAVY, "A03 重甲")

	var boots = EDB.get_template(&"A16")
	_check(boots != null, "A16 布质软靴存在")
	if boots:
		_check(boots.armor_class == ED.ArmorClass.LIGHT, "A16 轻甲")

	var amulet = EDB.get_template(&"J03")
	_check(amulet != null, "J03 骨牙吊坠存在")
	if amulet:
		_check(amulet.base_affix.value == 25.0, "J03 基础 HP +25", [amulet.base_affix.value])


func test_damage_pipeline() -> void:
	_current_test = "DamagePipeline"
	print("\n--- %s ---" % _current_test)

	var DP = _require_script("res://gameplay/combat/damage_pipeline.gd")
	if DP == null:
		return

	var result = DP.physical(100.0, 1.0, 0.0, 50.0)
	_check(result.damage > 0.0, "物理伤害 > 0", [result.damage])
	_check(result.damage < 100.0, "有防御时伤害降低", [result.damage])

	var result2 = DP.physical(100.0, 1.5, 0.0, 0.0)
	_check(result2.damage == 150.0, "1.5倍技能倍率伤害 = 150", [result2.damage])

	var crit_damage: float = DP.with_crit(100.0, true, 0.5)
	_check(crit_damage == 200.0, "暴击伤害 = 200", [crit_damage])

	var no_crit: float = DP.with_crit(100.0, false, 0.5)
	_check(no_crit == 100.0, "非暴击伤害不变", [no_crit])


func test_fusion_rules() -> void:
	_current_test = "FusionRules"
	print("\n--- %s ---" % _current_test)

	var FR = _require_script("res://data/equipment/fusion_rules.gd")
	if FR == null:
		return

	_check(FR.attack_bonus_at(0) == 0.0, "融合 0 = 0%加成")
	_check(FR.attack_bonus_at(5) == 0.15, "融合 5 = 15%加成")
	_check(FR.attack_bonus_at(25) == 1.0, "融合 25 = 100%加成（满级）")
	_check(FR.can_fuse(0), "融合 0 可以继续融合")
	_check(FR.can_fuse(24), "融合 24 可以继续融合")
	_check(not FR.can_fuse(25), "融合 25 不可继续融合（上限 25）")
	_check(FR.next_fusion_count(0) == 1, "融合后等级 +1")


func test_room_data() -> void:
	_current_test = "RoomData"
	print("\n--- %s ---" % _current_test)

	var RD = _require_script("res://data/rooms/room_data.gd")
	if RD == null:
		return

	var room = RD.new()
	room.room_id = "test_room"
	room.room_type = "normal"
	room.width = 10
	room.height = 8

	room.doors.append({"direction": "north", "id": "north"})
	room.entities.append({"type": "player_spawn", "x": 5, "y": 4})
	room.entities.append({"type": "enemy_spawn", "x": 3, "y": 3})

	_check(room.has_door("north"), "有北门")
	_check(not room.has_door("south"), "没有南门")

	var spawns: Array = room.get_enemy_spawns()
	_check(spawns.size() == 1, "有 1 个敌人生成点", [spawns.size()])

	var player: Dictionary = room.get_player_spawn()
	_check(not player.is_empty(), "有玩家出生点")


## 房间刷怪闭环集成测试：建房间 → 激活 → 刷怪 → 全灭 → 清空
func test_room_combat_loop() -> void:
	_current_test = "RoomCombatLoop"
	print("\n--- %s ---" % _current_test)

	var RC = _require_script("res://gameplay/dungeon/room_controller.gd")
	var EB = _require_script("res://entities/enemies/enemy_base.gd")
	var EDB = _require_script("res://data/equipment/equipment_db.gd")
	if RC == null or EB == null or EDB == null:
		return

	EDB.init_white_equipment()

	# 构造房间结构：Room_N/{SpawnPoints, Doors, RoomController}
	var room_root := Node3D.new()
	room_root.name = "Room_Test"
	root.add_child(room_root)

	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	room_root.add_child(spawns)

	# 4 个生成点 → 70% 概率刷怪，为确定性直接种固定数量的敌人不好控制，
	# 改为验证：激活后 alive > 0（13 个点几乎必然 ≥1）与清空逻辑
	for i in range(13):
		var m := Marker3D.new()
		m.position = Vector3(float(i), 0.0, 0.0)
		spawns.add_child(m)

	var controller = RC.new()
	controller.name = "RoomController"
	controller.set("room_data", {"room_id": "test_room", "room_type": "normal"})
	room_root.add_child(controller)

	# 等待 _ready 收集节点
	await process_frame

	controller.activate()
	_check(controller.is_active, "房间激活")
	var alive: int = controller.enemies_alive
	_check(alive > 0, "激活后刷出敌人（alive=%d）" % alive, [alive])

	if alive > 0:
		# 杀死所有活敌 → 房间清空
		var enemies: Array = controller.get("_living_enemies")
		for e in enemies:
			if is_instance_valid(e):
				e.take_damage(99999.0)
		_check(controller.is_cleared, "全灭后房间清空")

	room_root.queue_free()


## Boss 房闭环测试：boss 房 JSON 可解析 → 刷 Boss → 杀 Boss → 传送门出现
func test_boss_room_loop() -> void:
	_current_test = "BossRoomLoop"
	print("\n--- %s ---" % _current_test)

	var RC = _require_script("res://gameplay/dungeon/room_controller.gd")
	var RD = _require_script("res://data/rooms/room_data.gd")
	if RC == null or RD == null:
		return

	# Boss 房 JSON 可解析且类型正确
	var boss_room = RD.load_from_file("res://data/rooms/room_boss.json")
	_check(boss_room != null, "boss 房 JSON 可加载")
	if boss_room:
		_check(boss_room.room_type == "boss", "boss 房类型为 boss", [boss_room.room_type])
		var boss_spawns: Array = []
		for e in boss_room.entities:
			if str(e.get("type", "")) == "boss_spawn":
				boss_spawns.append(e)
		_check(boss_spawns.size() == 1, "boss 房恰有 1 个 Boss 点", [boss_spawns.size()])
		var boss_spawn: Dictionary = boss_room.get_player_spawn()
		_check(not boss_spawn.is_empty(), "boss 房有玩家入口")

	# 构造 boss 房场景：boss_spawn 标记 → 激活 → Boss 生成 → 杀死 → 传送门
	var room_root := Node3D.new()
	room_root.name = "Room_Boss_Test"
	root.add_child(room_root)

	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	room_root.add_child(spawns)
	var boss_marker := Marker3D.new()
	boss_marker.position = Vector3(5, 0, 5)
	boss_marker.add_to_group("boss_spawn")
	spawns.add_child(boss_marker)

	var controller = RC.new()
	controller.name = "RoomController"
	controller.set("room_data", {"room_id": "room_boss", "room_type": "boss"})
	room_root.add_child(controller)
	await process_frame

	controller.activate()
	_check(controller.is_boss_room, "识别为 Boss 房")
	_check(controller.enemies_alive == 1, "刷出 1 只 Boss", [controller.enemies_alive])
	var boss = controller.get("_boss")
	_check(boss != null, "Boss 实例存在")
	if boss:
		_check(boss.max_hp >= 480.0, "Boss 血量 ≥ 480（普通难度 600×0.8 下限）", [boss.max_hp])

		# 杀 Boss → 房间清空 + 传送门出现
		boss.take_damage(999999.0)
		await process_frame
		_check(controller.is_cleared, "Boss 死后房间清空")
		var portal = controller.get("_portal")
		_check(portal != null and is_instance_valid(portal), "生成下一层传送门")

	room_root.queue_free()