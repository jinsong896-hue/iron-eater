extends SceneTree
## IronEater Studio 全框架验证测试

var failed := 0


func _init() -> void:
	await _test_modifier()
	await _test_stats()
	await _test_skill()
	await _test_form()
	await _test_character()
	await _test_weapon()
	await _test_monster()
	await _test_balance()
	await _test_combat_core()
	await _test_buff()
	await _test_validator()
	await _test_creator_core()
	await _test_runtime()

	if failed == 0:
		print("ALL IRONEATER STUDIO TESTS PASSED")
		quit(0)
	else:
		print("IRONEATER STUDIO TESTS FAILED: %d" % failed)
		quit(1)


func _test_modifier() -> void:
	var m := ModifierData.new()
	m.target_stat = "atk"
	m.operation = ModifierData.Operation.ADD
	m.value = 10.0
	_check(m.apply(100.0) == 110.0, "Modifier ADD")

	m.operation = ModifierData.Operation.MULTIPLY
	m.value = 0.3
	_check(m.apply(100.0) == 130.0, "Modifier MULTIPLY")

	m.operation = ModifierData.Operation.OVERRIDE
	m.value = 50.0
	_check(m.apply(100.0) == 50.0, "Modifier OVERRIDE")

	_check(m.description().length() > 0, "Modifier description")


func _test_stats() -> void:
	var s := StatsData.new()
	s.hp = 100.0; s.atk = 10.0; s.defense = 5.0
	s.spd = 100.0; s.aspd = 1.0
	_check(s.hp == 100.0, "Stats HP")
	_check(s.atk == 10.0, "Stats ATK")

	var s2 := s.clone()
	_check(s2.hp == 100.0, "Stats clone")

	var mods: Array[ModifierData] = []
	var m := ModifierData.new()
	m.target_stat = "atk"; m.operation = ModifierData.Operation.ADD; m.value = 20.0
	mods.append(m)
	var s3 := s.apply_modifiers(mods)
	_check(s3.atk == 30.0, "Stats apply_modifiers")


func _test_skill() -> void:
	var s := SkillData.new()
	s.skill_id = "test_skill"
	s.skill_name = "Test Skill"
	s.hp_cost = 15.0
	s.cooldown = 1.0
	_check(s.skill_name == "Test Skill", "Skill create")
	_check(s.description().length() > 0, "Skill description")


func _test_form() -> void:
	var f := FormData.new()
	f.form_id = "test_form"
	f.form_name = "Test Form"
	f.unlock_floor = 3
	_check(f.form_name == "Test Form", "Form create")
	_check(f.description().length() > 0, "Form description")


func _test_character() -> void:
	var c := CharacterData.new()
	c.char_id = "test_char"
	c.char_name = "Test Character"
	c.class_type = "Warrior"
	c.resource_max = 100
	var s := StatsData.new()
	s.hp = 120.0; s.atk = 15.0
	c.base_stats = s
	_check(c.char_name == "Test Character", "Character create")
	_check(c.summary().length() > 0, "Character summary")
	_check(c.get_form(0) == null, "Character get_form out of range")


func _test_weapon() -> void:
	var w := WeaponData.new()
	w.weapon_id = "test_sword"
	w.weapon_name = "Test Sword"
	w.base_atk = 10
	w.max_fusion = 25
	w.fusion_atk_growth = 5.0
	_check(w.current_atk() == 10, "Weapon base ATK")
	_check(w.can_fuse(), "Weapon can fuse")
	w.fuse()
	_check(w.current_atk() == 15, "Weapon ATK after 1 fusion")
	_check(w.description().length() > 0, "Weapon description")


func _test_monster() -> void:
	var m := MonsterData.new()
	m.monster_name = "Test Monster"
	m.ai_type = "melee_chase"
	m.hp = 200
	m.floor_min = 1; m.floor_max = 8
	m.hp_scale = 3.5
	_check(m.monster_name == "Test Monster", "Monster create")


func _test_balance() -> void:
	var c := CharacterData.new()
	c.char_id = "test"; c.char_name = "Test"
	var s := StatsData.new()
	s.hp = 100.0; s.atk = 10.0; s.defense = 5.0
	s.spd = 100.0; s.aspd = 1.0; s.crt = 0.1; s.crd = 0.5
	c.base_stats = s

	var w := WeaponData.new()
	w.weapon_id = "test"; w.weapon_name = "Test"
	w.base_atk = 10

	var report := BalanceCalculator.simulate(c, w, 0, 1)
	_check(report.has("dps"), "Balance has dps")
	_check(report["dps"] > 0, "Balance dps > 0")
	_check(report.has("ttk_seconds"), "Balance has ttk")
	_check(report.has("survival_seconds"), "Balance has survival")


func _test_combat_core() -> void:
	var dmg := CombatCore.calc_damage(100.0, 1.0, 50.0)
	_check(dmg > 0, "CombatCore damage > 0")

	var dps := CombatCore.calc_dps(100.0, 1.0, 0.1, 0.5, 50.0)
	_check(dps > 0, "CombatCore dps > 0")

	var ttk := CombatCore.calc_ttk(100.0, 500.0, 50.0)
	_check(ttk > 0, "CombatCore ttk > 0")


func _test_buff() -> void:
	var b := BuffData.new()
	b.buff_id = "test_buff"
	b.buff_name = "Test Buff"
	b.duration = 5.0
	b.max_stacks = 3
	_check(b.buff_name == "Test Buff", "Buff create")
	_check(b.description().length() > 0, "Buff description")


func _test_validator() -> void:
	var c := CharacterData.new()
	c.char_id = "test"; c.char_name = "Test"
	var s := StatsData.new()
	s.hp = 100.0; s.atk = 10.0
	c.base_stats = s
	var r := DataValidator.validate_character(c)
	_check(r["valid"] == true, "Validator valid character")
	_check(r["warnings"].size() > 0, "Validator warnings for no forms")

	var w := WeaponData.new()
	w.weapon_id = "test"; w.weapon_name = "Test"
	w.base_atk = 10
	var r2 := DataValidator.validate_weapon(w)
	_check(r2["valid"] == true, "Validator valid weapon")


func _test_creator_core() -> void:
	var cc := IronEaterCreator.new()
	var chars := cc.list_characters()
	_check(chars is Array, "CreatorCore list_characters returns array")
	var weps := cc.list_weapons()
	_check(weps is Array, "CreatorCore list_weapons returns array")


func _test_runtime() -> void:
	var rt := CharacterRuntime.new()
	var c := CharacterData.new()
	c.char_id = "test"; c.char_name = "Test"
	var s := StatsData.new()
	s.hp = 100.0; s.atk = 10.0; s.defense = 5.0
	s.spd = 100.0; s.aspd = 1.0
	c.base_stats = s
	rt.setup(c, 0)
	_check(rt.is_alive(), "Runtime is alive")
	_check(rt.description().length() > 0, "Runtime description")


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
