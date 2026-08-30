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

	# 装备系统测试
	test_equipment_system()

	# 伤害管线测试
	test_damage_pipeline()

	# 融合规则测试
	test_fusion_rules()

	# 房间数据测试
	test_room_data()

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