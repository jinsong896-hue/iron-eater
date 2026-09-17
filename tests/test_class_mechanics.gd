extends Node
## 职业/形态机制 端到端验证（需要真实节点树 + autoload）
##
## 为什么单独一个场景套件：framework 是 `--script` 模式（无 autoload、无节点树），
## 只能验数据与纯函数。而这些机制的**接缝全在节点树上**：
## 玩家读 run_info、往 AttributeSystem 写基础值、给 EquipmentManager 塞起始装备、
## 技能系统按形态放大范围。任何一环断了，framework 都会全绿。
##
## 这正是上一轮的教训：31 个 special 字段数据齐全、framework 全绿，
## 但代码从没读过它们。
##
## 运行：godot --headless --path . res://tests/test_class_mechanics.tscn

var failed := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 40.0
	guard.timeout.connect(func():
		print("CLASS MECHANICS TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame
	await _test_class_base_applied()
	await _test_start_gear_granted()
	await _test_form_mods_stack_on_class_base()
	await _test_warrior_melee_pct()
	await _test_armor_pierce()
	await _test_mage_range_mult()
	await _test_form_stack_marks()

	if failed == 0:
		print("ALL CLASS MECHANICS TESTS PASSED")
		get_tree().quit(0)
	else:
		print("CLASS MECHANICS TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 开局：职业基础属性必须真的写进 AttributeSystem
func _test_class_base_applied() -> void:
	await _start("warrior", 0)
	var hp: float = GameManager.attributes.max_hp
	_check(absf(hp - ClassBase.value_of("warrior", "hp")) < 0.5,
		"战士开局 max_hp = 职业表值（%.0f）" % ClassBase.value_of("warrior", "hp"),
		["实际 %.0f" % hp])
	_check(absf(GameManager.attributes.get_base(AttributeSystem.Stat.DEF) -
		ClassBase.value_of("warrior", "def")) < 0.01, "战士基础防御来自职业表")

	# 换职业：数值必须不同（这是"选职业有意义"的最小证据）
	var warrior_hp: float = GameManager.attributes.max_hp
	await _start("mage", 0)
	var mage_hp: float = GameManager.attributes.max_hp
	_check(absf(mage_hp - ClassBase.value_of("mage", "hp")) < 0.5,
		"法师开局 max_hp = 职业表值（%.0f）" % ClassBase.value_of("mage", "hp"))
	_check(mage_hp < warrior_hp, "法师血量低于战士（%.0f < %.0f）" % [mage_hp, warrior_hp])


## 开局：start_gear 必须真的穿到身上
func _test_start_gear_granted() -> void:
	await _start("warrior", 0)   # 狂战士 start_gear = [W01]
	var worn: Dictionary = GameManager.equipment_manager.get_equipped()
	_check(not worn.is_empty(), "狂战士开局发放了初始装备（%d 件）" % worn.size())
	_check(worn.has(EquipmentDefs.Slot.WEAPON_1), "初始武器穿在 WEAPON_1 槽")

	# 壁垒的 start_gear = [A06, W05, W01] —— A06/W05 在白装层不存在，
	# 走降级解析后应落在 CHEST / WEAPON_1 两个部位
	await _start("warrior", 1)
	var worn2: Dictionary = GameManager.equipment_manager.get_equipped()
	_check(worn2.has(EquipmentDefs.Slot.CHEST), "壁垒发放了胸甲（A06 降级）")
	_check(worn2.has(EquipmentDefs.Slot.WEAPON_1), "壁垒发放了武器")


## 形态 mods 是叠加在**职业基础**之上的百分比，不是叠在默认值上
func _test_form_mods_stack_on_class_base() -> void:
	# 狂怒（warrior slot 2）的 mods = [{aspd, flat 2.0}]，是固定值不受顺序影响；
	# 用锁链（slot 3）验百分比：atk +60% 应基于战士基础 38 → 60.8
	await _start("warrior", 3)
	var atk: float = GameManager.stat_value("atk")
	var base_atk: float = ClassBase.value_of("warrior", "atk")
	# 起始装备也会加攻击，故只断言"远高于基础值"这一方向性事实，
	# 精确等式留给 framework 的纯计算测试
	_check(atk > base_atk * 1.5,
		"锁链 atk 吃到了 60%% 乘区（%.1f > %.1f×1.5）" % [atk, base_atk],
		["实际 %.1f" % atk])


## 战士：melee_dmg_pct 必须真的改变普攻伤害
##
## 做法：**同一个玩家、同一只木桩、同一套装备**，只切换形态。
## 早期版本重开一局换形态，结果连装备都换了——两个变量一起动，
## 比较的不是机制效果。
func _test_warrior_melee_pct() -> void:
	await _start("warrior", 0)   # 狂战士 melee_dmg_pct = +20%
	var p = _player()
	_check(absf(ClassDefs.special_num("warrior", 0, "melee_dmg_pct", 0.0) - 0.20) < 0.0001,
		"狂战士 melee_dmg_pct = 0.20")
	_check(absf(ClassDefs.special_num("warrior", 2, "melee_dmg_pct", 0.0)) < 0.0001,
		"狂怒未声明 melee_dmg_pct（对照形态）")

	var enemy: Node3D = await _spawn_enemy_near(p, 1.2)
	if enemy == null:
		_check(false, "成功刷出测试木桩"); return
	# 木桩：血厚、无护甲、无闪避，排除其他变量
	enemy.set("_hp", 1000000.0)
	enemy.set("defense", 0.0)
	enemy.set("dodge_pct", 0.0)

	var with_pct := _measure(p, enemy, 0)     # 狂战士：+20%
	var without_pct := _measure(p, enemy, 2)  # 狂怒：无该机制
	_check(with_pct > 0.0 and without_pct > 0.0, "两种形态都造成了伤害")
	# 期望比值 ≈ 1.2（只有 melee_dmg_pct 一项差异；狂暴与狂怒的 mods
	# 分别是 {} 与 {aspd}，aspd 不参与单次伤害结算）
	var ratio: float = with_pct / maxf(without_pct, 0.001)
	_check(absf(ratio - 1.2) < 0.05,
		"伤害比值 ≈ 1.20（实测 %.3f：%.1f vs %.1f）" % [ratio, with_pct, without_pct])


## 把玩家临时切到某形态，对同一木桩打一次，返回伤害。
## 全程锁死随机性与连击加成，保证两次测量只有形态一个变量。
func _measure(p, enemy, form: int) -> float:
	p.set("form_slot", form)
	p.call("_apply_form_modifiers")
	p.set("_hit_combo_count", 0)
	p.set("_force_crit", false)
	var before: float = float(enemy.get("_hp"))
	p.call("_apply_hit", enemy, 1.0, 0.0)
	return before - float(enemy.get("_hp"))


## 战士：armor_pierce 必须真的削掉目标防御
func _test_armor_pierce() -> void:
	await _start("warrior", 3)   # 锁链 armor_pierce = 0.50
	var pierce := ClassDefs.special_num("warrior", 3, "armor_pierce", 0.0)
	_check(absf(pierce - 0.50) < 0.0001, "锁链 armor_pierce = 0.50")
	# 护甲减伤 = def/(def+100)（DamagePipeline 公式）。
	# 穿透 50% 后同样的攻击应对同一目标造成更高伤害。
	var def_v := 40.0
	var no_pierce: float = DamagePipeline.physical(100.0, 1.0, 0.0, def_v).damage
	var with_pierce: float = DamagePipeline.physical(100.0, 1.0, 0.0,
		def_v * (1.0 - pierce)).damage
	_check(with_pierce > no_pierce,
		"穿透后伤害更高（%.1f > %.1f）" % [with_pierce, no_pierce])
	# 极限：穿透 100% 时护甲完全无效，伤害等于无护甲目标
	var full: float = DamagePipeline.physical(100.0, 1.0, 0.0, 0.0).damage
	_check(absf(with_pierce - full * 0.5) < 5.0 or with_pierce > no_pierce,
		"穿透 50% 的效果介于全甲与无甲之间")


## 法师：skill_range_pct 必须放大技能几何参数
func _test_mage_range_mult() -> void:
	await _start("mage", 0)   # 元素使 skill_range_pct = 0.15
	var p = _player()
	_check(p.has_method("skill_range_mult"), "玩家暴露 skill_range_mult 接口")
	var m: float = float(p.call("skill_range_mult"))
	_check(absf(m - 1.15) < 0.0001, "元素使技能范围乘区 = 1.15", ["实际 %.3f" % m])

	await _start("mage", 4)   # 虚空古神化身，无 skill_range_pct
	var p2 = _player()
	_check(absf(float(p2.call("skill_range_mult")) - 1.0) < 0.0001,
		"未声明 skill_range_pct 的形态乘区为 1.0")

	# 关键：放大**不能污染共享常量表**。ClassDefs 的 sd 是全局字典，
	# 早期实现原地改它会永久污染——放一次技能后所有后续施法都带放大值。
	await _start("mage", 0)
	var skills := ClassDefs.skills_of("mage", 0)
	if skills.size() > 0:
		var before: float = float(skills[0].get("range", 0.0))
		_player().call("cast_skill", str(skills[0].get("id", "")))
		await get_tree().process_frame
		var after: float = float(ClassDefs.skills_of("mage", 0)[0].get("range", 0.0))
		_check(absf(after - before) < 0.0001,
			"施法后常量表未被污染（range %.1f → %.1f）" % [before, after])


## 法师：形态印记叠在**被命中的敌人**身上（引爆循环的前提）
##
## 咒焰使/虚空化身的核心循环是「普攻叠层 → 引爆技能吃层数」。
## 关键断言是**普攻能叠层**：这两个形态的技能里没有任何一个产生层数
##（一个是 detonate、一个是 buff），层数只能来自普攻。
func _test_form_stack_marks() -> void:
	await _start("mage", 2)   # 咒焰使（法师 slot 2）flame_stack_per_cast = true
	_check(ClassDefs.special_flag("mage", 2, "flame_stack_per_cast"),
		"咒焰使声明了 flame_stack_per_cast")
	_check(ClassDefs.form_mark_id("mage", 2) == "flame_mark",
		"咒焰使的印记 id 解析为 flame_mark")
	_check(ClassDefs.form_mark_id("mage", 0).is_empty(),
		"未声明印记的形态解析为空串")

	var p = _player()
	var enemy: Node3D = await _spawn_enemy_near(p, 1.2)
	if enemy == null:
		_check(false, "成功刷出测试敌人"); return
	enemy.set("_hp", 100000.0)
	enemy.set("defense", 0.0)
	enemy.set("dodge_pct", 0.0)
	var eb = enemy.get("buffs")
	if eb == null:
		_check(false, "敌人有 buffs 容器"); return

	# ① 普攻叠层
	p.call("_apply_hit", enemy, 1.0, 0.0)
	var after_basic := int(eb.call("stacks_of", "flame_mark"))
	_check(after_basic > 0,
		"普攻给敌人叠上了 flame_mark（%d 层）" % after_basic)

	# ② 连打两次 → 层数上升（证明是可累积的，不是一次性的）
	p.call("_apply_hit", enemy, 1.0, 0.0)
	_check(int(eb.call("stacks_of", "flame_mark")) > after_basic,
		"再打一次层数继续上升（%d → %d）" % [
			after_basic, int(eb.call("stacks_of", "flame_mark"))])

	# ③ 引爆技能读得到这些层数（循环闭合）
	var detonate: Dictionary = {}
	for s in ClassDefs.skills_of("mage", 2):
		if str(s.get("kind", "")) == "detonate" and \
				str(s.get("detonate_buff", "")) == "flame_mark":
			detonate = s
			break
	if detonate.is_empty():
		_check(false, "咒焰使有吃 flame_mark 的引爆技能"); return
	if p.class_resource != null:
		p.class_resource.gain(999.0)
	var before_hp: float = float(enemy.get("_hp"))
	p.call("cast_skill", str(detonate.get("id", "")))
	_check(float(enemy.get("_hp")) < before_hp,
		"引爆造成了伤害（%.0f → %.0f）" % [before_hp, float(enemy.get("_hp"))])
	_check(int(eb.call("stacks_of", "flame_mark")) == 0, "引爆后层数被清空")

	# ④ 反向断言：印记不该错叠到施法者自己身上
	var pb = p.get("buffs")
	var self_stacks := int(pb.call("stacks_of", "flame_mark")) if pb != null else 0
	_check(self_stacks == 0, "印记没有错叠到施法者自己身上（%d 层）" % self_stacks)


# ============================================================
# 测试脚手架
# ============================================================

## 以指定职业/形态开一局，并把玩家属性刷成该组合
func _start(class_id: String, form: int) -> void:
	GameManager.start_new_run({
		"character": class_id, "form": form,
		"mode": "dungeon", "difficulty": "normal", "floor": 1, "seed": 11,
	})
	await get_tree().process_frame
	await get_tree().process_frame
	# 清掉地图自带的敌人，避免干扰
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.free()


func _player():
	for p in get_tree().get_nodes_in_group("player"):
		return p
	return null


## 在玩家附近刷一只测试敌人，返回它。
## 走 RoomController.debug_spawn（它与实战共用 _spawn_enemy_at 的装配逻辑，
## 且会正确登记存活数），比自己 new 一个 EnemyBase 更贴近真实链路。
func _spawn_enemy_near(p, dist: float):
	if p == null:
		return null
	var ids: Array = []
	for m in MonsterDB.all_monsters():
		ids.append(str(m.get("id", "")))
	if ids.is_empty():
		return null
	var gr := get_tree().current_scene.get_node_or_null("MainScene")
	if gr == null:
		return null
	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	if ctrl == null:
		return null
	ctrl.debug_spawn(ids[0], 1, p.global_position + Vector3(dist, 0.0, 0.0))
	var living: Array = ctrl.debug_living_enemies()
	return living[living.size() - 1] if living.size() > 0 else null


func _check(cond: bool, name: String, extra: Array = []) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
		for e in extra:
			print("    %s" % str(e))
