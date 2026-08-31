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

	# 连段状态机测试
	test_attack_combo()

	# 房间编辑器核心测试（JSON 往返 + 矩形填充/围墙/校验）
	test_room_editor_core()

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


## 连段状态机测试：四段推进 / 窗口超时 / 特殊攻击接入
func test_attack_combo() -> void:
	_current_test = "AttackCombo"
	print("\n--- %s ---" % _current_test)

	var AC = _require_script("res://gameplay/combat/attack_combo.gd")
	if AC == null:
		return

	var combo = AC.new()
	# 注入测试配置（避免依赖 GameBalance 常量变更）
	combo.combo_stages = [
		[0.28, 1.0, 2.0, 60.0, 0.0],
		[0.28, 1.1, 2.2, 65.0, 0.0],
		[0.32, 1.3, 2.6, 75.0, 1.5],
		[0.45, 1.8, 3.2, 90.0, 4.0],
	]
	combo.combo_window = 0.45

	# --- 四段连击推进 ---
	var s1: int = combo.request_normal()
	_check(s1 == 1, "第一击为普攻1", [s1])
	combo.begin_attack()
	_check(combo.request_normal() == 0, "动作进行中拒绝输入")
	combo.end_attack()
	_check(combo.is_combo_active(), "攻击后处于连击窗口")

	var s2: int = combo.request_normal()
	_check(s2 == 2, "窗口内第二击接普攻2", [s2])
	combo.begin_attack()
	combo.end_attack()
	var s3: int = combo.request_normal()
	_check(s3 == 3, "第三击接普攻3", [s3])
	combo.begin_attack()
	combo.end_attack()
	var s4: int = combo.request_normal()
	_check(s4 == 4, "第四击接普攻4（终结）", [s4])

	# --- 段位参数 ---
	var p4: Array = combo.stage_params(4)
	_check(p4[1] == 1.8, "普攻4 倍率 1.8", [p4[1]])
	_check(p4[2] == 3.2, "普攻4 距离 3.2（范围递增）", [p4[2]])
	var p1: Array = combo.stage_params(1)
	_check(p1[2] < p4[2], "普攻1 范围 < 普攻4 范围")
	_check(combo.stage_params(1)[1] < combo.stage_params(2)[1]
		and combo.stage_params(2)[1] < combo.stage_params(3)[1]
		and combo.stage_params(3)[1] < combo.stage_params(4)[1],
		"四段伤害递增")

	# --- 第四段后窗口超时回普攻1 ---
	combo.begin_attack()
	combo.end_attack()
	combo.tick(0.5)  # 超过 0.45 窗口
	_check(not combo.is_combo_active(), "窗口超时连击断")
	var s_after: int = combo.request_normal()
	_check(s_after == 1, "超时后回到普攻1", [s_after])

	# --- 奔跑攻击接入普攻3 ---
	combo = AC.new()
	combo.combo_stages = [[0.3, 1.0], [0.3, 1.1], [0.3, 1.3], [0.3, 1.8]]
	combo.combo_window = 0.45
	_check(combo.request_sprint(), "奔跑攻击被接受")
	combo.begin_attack()
	combo.end_attack()
	var after_sprint: int = combo.request_normal()
	_check(after_sprint == 3, "奔跑攻击后接普攻3", [after_sprint])
	combo.begin_attack()
	combo.end_attack()
	var after_sprint2: int = combo.request_normal()
	_check(after_sprint2 == 4, "奔跑攻击→普攻3→普攻4", [after_sprint2])

	# --- 跳跃攻击接入普攻3 ---
	combo = AC.new()
	combo.combo_stages = [[0.3, 1.0], [0.3, 1.1], [0.3, 1.3], [0.3, 1.8]]
	combo.combo_window = 0.45
	_check(combo.request_jump(), "跳跃攻击被接受")
	combo.begin_attack()
	combo.end_attack()
	var after_jump: int = combo.request_normal()
	_check(after_jump == 3, "跳跃攻击后接普攻3", [after_jump])

	# --- 特殊攻击进行中拒绝 ---
	combo = AC.new()
	combo.combo_stages = [[0.3, 1.0], [0.3, 1.1], [0.3, 1.3], [0.3, 1.8]]
	combo.begin_attack()
	_check(not combo.request_sprint(), "动作中拒绝奔跑攻击")
	_check(not combo.request_jump(), "动作中拒绝跳跃攻击")

	# --- 普攻中断连击（tick 在非动作期推进窗口）---
	combo = AC.new()
	combo.combo_stages = [[0.3, 1.0], [0.3, 1.1], [0.3, 1.3], [0.3, 1.8]]
	combo.combo_window = 0.45
	combo.request_normal()
	combo.begin_attack()
	combo.end_attack()
	combo.tick(0.2)
	_check(combo.is_combo_active(), "窗口内连击保持")
	combo.tick(0.3)
	_check(not combo.is_combo_active(), "累计超窗连击断")


## 房间编辑器核心测试：JSON 往返一致性 + 矩形填充/自动围墙/校验
func test_room_editor_core() -> void:
	_current_test = "RoomEditorCore"
	print("\n--- %s ---" % _current_test)

	var RE = _require_script("res://addons/iron_studio/room_editor_core.gd")
	if RE == null:
		return

	# 构造编辑器节点树（容器结构同 room_editor_scene）
	var root := Node3D.new()
	root.name = "RoomEditorRoot"
	for c in ["Floor", "Walls", "Doors", "Spawns"]:
		var n := Node3D.new()
		n.name = c
		root.add_child(n)
	# 挂到场景树根（节点生命周期管理；编辑器核心是纯静态方法）
	self.root.add_child(root)

	# --- JSON 往返一致性 ---
	var source := {
		"version": 2, "id": "rt_test", "room_type": "normal",
		"width": 10, "height": 8, "tags": ["normal", "custom_tag"],
		"doors": [{"direction": "south", "id": "south_5_7", "x": 5, "y": 7}],
		"floor": [{"x": 1, "y": 1, "type": "stone"}, {"x": 2, "y": 1, "type": "wood"}],
		"walls": [{"x": 0, "y": 0, "direction": "north", "type": "normal_wall"}],
		"entities": [{"type": "enemy_spawn", "x": 3, "y": 3, "monster_id": "slime"}],
	}
	RE.build_editor_tree(root, source)
	var meta := {"id": "rt_test", "room_type": "normal", "width": 10, "height": 8, "tags": ["normal", "custom_tag"]}
	var round: Dictionary = RE.serialize_tree(root, meta)

	_check(round.get("tags") == ["normal", "custom_tag"], "tags 透传不丢失", [str(round.get("tags"))])
	_check(round.get("floor", []).size() == 2, "地板往返数量一致")
	_check(round.get("floor", [])[1].get("type") == "wood", "地板材质往返一致")
	_check(round.get("walls", []).size() == 1, "墙往返数量一致")
	var rt_door: Dictionary = round.get("doors", [])[0]
	_check(rt_door.get("id") == "south_5_7", "门 id 含坐标后缀（唯一）", [rt_door.get("id")])
	_check(rt_door.get("x") == 5 and rt_door.get("y") == 7, "门坐标往返一致")
	var rt_spawn: Dictionary = round.get("entities", [])[0]
	_check(rt_spawn.get("monster_id") == "slime", "刷怪点怪物绑定往返一致")

	# --- 门位置：编辑器与游戏 DoorBuilder 同口径 ---
	var DB = _require_script("res://world/rooms/door_builder.gd")
	if DB:
		var pos: Vector3 = DB._door_position_from_cell({"x": 5, "y": 7}, "south")
		_check(pos == Vector3(5.0, 1.5, 7.5), "门位置=格子边缘（编辑器=游戏口径）", [pos])
		var fallback: Vector3 = DB._door_position_from_cell({}, "south")
		_check(fallback == Vector3.INF, "旧数据无 x/y 返回回退标记")

	# --- 矩形填充 ---
	RE.clear_tree(root)
	var fill_op: Dictionary = RE.fill_rect_floor(root, Vector2i(1, 1), Vector2i(3, 3), "grass")
	_check(fill_op.get("added", []).size() == 9, "矩形填充 3x3=9 格", [str(fill_op.get("added", []).size())])
	var filled: Dictionary = RE.serialize_tree(root, meta)
	_check(filled.get("floor", []).size() == 9, "填充后序列化 9 块地板")

	# --- 橡皮擦清全部 ---
	var erase_op: Dictionary = RE.erase_cell(root, Vector2i(2, 2))
	_check(erase_op.get("removed", []).size() == 1, "橡皮擦清除该格地板")

	# --- 自动围墙（10x8 → 边界 2*(10+8)=36 段，角落双面墙）---
	RE.clear_tree(root)
	var wall_op: Dictionary = RE.auto_walls(root, 10, 8)
	var wall_count: int = wall_op.get("added", []).size()
	_check(wall_count == 2 * (10 + 8), "自动围墙 36 段（角落双面）", [str(wall_count)])

	# --- 校验 ---
	# 空房间 → 地板未铺满 + 无门问题不报（无门=没检查对象）
	var issues: Array = RE.validate_room(root, {"width": 10, "height": 8, "room_type": "normal"})
	_check(issues.size() > 0, "空房间校验发现问题（地板未铺满）", [str(issues)])
	var has_floor_issue := false
	for issue in issues:
		if str(issue).contains("地板"):
			has_floor_issue = true
	_check(has_floor_issue, "校验报出地板覆盖问题")

	# start 房无玩家出生点
	var issues2: Array = RE.validate_room(root, {"width": 10, "height": 8, "room_type": "start"})
	var has_spawn_issue := false
	for issue in issues2:
		if str(issue).contains("玩家出生"):
			has_spawn_issue = true
	_check(has_spawn_issue, "起始房缺玩家出生点被报出")

	root.queue_free()


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