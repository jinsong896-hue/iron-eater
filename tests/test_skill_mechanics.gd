extends Node
## 技能机制测试 —— 验证 133 条装备技能 + 40 条职业技能的**机制落地**
##
## ## 这个套件要回答的问题
##
## 2026-09-23 发现装备技能表把数值塞进了固定列，而执行端读的是
## `extra` 里的键——于是「护盾术」「冰封领域」「圣光审判」按下去
## 什么都不发生（`extra` 是空的，`_cast_buff` 是 `pass`）。
##
## 本套件**逐 kind 断言「施法后世界状态发生了预期变化」**：
## 敌人掉血 / 自己回血 / 获得 buff / 生成投射物 / 挂上控制。
## 只断言「技能存在」是不够的——那正是当初漏掉的地方。
##
## 全部走真实数据（`EquipmentSkills` / `ClassDefs`），不造假的技能表，
## 否则测的是测试自己而不是产品。

var failed := 0
var _test := ""

## 本次施法涉及的替身敌人（每个测试自建，测完 free）
var _enemies: Array = []


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 40.0
	guard.timeout.connect(func(): print("SKILL MECHANICS TESTS FAILED: 超时"); get_tree().quit(1))
	add_child(guard); guard.start()
	await get_tree().process_frame

	_test_equipment_skill_table()
	_test_kind_coverage()
	_test_buff_skill_shield()
	_test_buff_skill_heal()
	_test_buff_skill_self_buff()
	_test_aoe_at_aim()
	_test_cone_reach_fallback()
	_test_dash_range()
	_test_control_and_knockup()
	_test_persistent_zone()
	_test_reflect_and_block()
	_test_element_from_skill()
	_test_projectile_multi()
	_test_blood_rage_drain()
	_test_class_skills_regression()

	if failed == 0:
		print("ALL SKILL MECHANICS TESTS PASSED")
		get_tree().quit(0)
	else:
		print("SKILL MECHANICS TESTS FAILED: %d" % failed)
		get_tree().quit(1)


# ============================================================
# 数据层
# ============================================================

## 技能表完整性：133 条、extra 非空、字段值合法
func _test_equipment_skill_table() -> void:
	_test = "SkillTable"
	print("\n--- %s ---" % _test)

	var all: Array = EquipmentSkills.all_skills()
	_check(all.size() == 133, "装备技能共 133 条（含同名两版）", [str(all.size())])

	# 技能必须有可执行内容。**注意不能要求 extra 非空**：
	# 「暗影箭匕首」描述只有「发射暗影箭，造成 100% 攻击力暗影伤害」——
	# 暗影不是 ElementDefs 的元素、也没有别的机制键，extra 空是**正确的**
	#（伤害靠 damage_mult 走 kind=projectile 结算）。要求非空会逼着人编造数据。
	# 真正该断言的是「不是 133 条全空」——全空正是当初的故障形态。
	var empty: Array = []
	for d in all:
		var n := 0
		for k in d:
			if not _is_meta_key(k):
				n += 1
		if n == 0:
			empty.append(str(d.get("source_equip", "?")))
	_check(empty.size() <= 3, "空 extra 的技能不超过 3 条（全空=故障）",
		["实际 %d 条：%s" % [empty.size(), ", ".join(empty)]])

	# 元素值必须是 ElementDefs 真实存在的 6 种之一
	#（曾产出 "holy"/"shadow" 这种不存在的元素）
	var bad_elem: Array = []
	for d in all:
		var e := str(d.get("element", ""))
		if e.is_empty():
			continue
		if not _is_valid_element(e):
			bad_elem.append("%s=%s" % [str(d.get("source_equip", "?")), e])
	_check(bad_elem.is_empty(), "元素值全在 ElementDefs 内", [", ".join(bad_elem)])

	# 同名两版必须按稀有度取到不同的数值（否则后写覆盖前写）
	var blue: Dictionary = EquipmentSkills.skill_of_equipment("元素爆发戒指", EquipmentDefs.Rarity.BLUE)
	var orange: Dictionary = EquipmentSkills.skill_of_equipment("元素爆发戒指", EquipmentDefs.Rarity.ORANGE)
	_check(absf(float(blue.get("damage_mult", 0.0)) - 1.0) < 0.01,
		"元素爆发戒指·蓝 = 100% 倍率", [str(blue.get("damage_mult"))])
	_check(absf(float(orange.get("damage_mult", 0.0)) - 3.0) < 0.01,
		"元素爆发戒指·橙 = 300% 倍率", [str(orange.get("damage_mult"))])


## 每种 kind 都必须有执行函数（kind 写错会静默无效果）
func _test_kind_coverage() -> void:
	_test = "KindCoverage"
	print("\n--- %s ---" % _test)

	var kinds := {}
	for d in EquipmentSkills.all_skills():
		kinds[str(d.get("kind", ""))] = true
	var known := ["aoe", "cone", "dash", "pull", "buff", "projectile",
		"teleport", "multi_hit", "detonate", "spread", "summon", "stealth"]
	var unknown: Array = []
	for k in kinds:
		if not known.has(k):
			unknown.append(k)
	_check(unknown.is_empty(), "无未知 kind", [", ".join(unknown)])

	# 反伤类曾被误标成 projectile——它们应是自身状态（buff）
	var reflect_as_projectile: Array = []
	for d in EquipmentSkills.all_skills():
		if str(d.get("kind", "")) == "projectile" and d.has("reflect_pct") \
				and float(d.get("damage_mult", 0.0)) <= 0.0:
			reflect_as_projectile.append(str(d.get("source_equip", "?")))
	_check(reflect_as_projectile.is_empty(), "反伤类不再被误标为 projectile",
		[", ".join(reflect_as_projectile)])


# ============================================================
# buff 类：护盾 / 治疗 / 自身增益
# ============================================================

## 护盾术：`shield_pct` 必须真的加护盾
func _test_buff_skill_shield() -> void:
	_test = "BuffSkillShield"
	print("\n--- %s ---" % _test)

	var sd: Dictionary = EquipmentSkills.skill_by_id("eq_护盾术")
	_check(not sd.is_empty(), "护盾术在表中")
	_check(absf(float(sd.get("shield_pct", 0.0)) - 0.2) < 0.01,
		"护盾术 shield_pct = 0.20", [str(sd.get("shield_pct"))])

	var caster := _make_caster()
	var before: float = float(caster.get("shield"))
	_cast(caster, sd)
	var after: float = float(caster.get("shield"))
	_check(after > before, "施放后护盾增加", ["before=%.1f after=%.1f" % [before, after]])
	caster.queue_free()


## 治愈术：`heal_pct` 必须真的回血
func _test_buff_skill_heal() -> void:
	_test = "BuffSkillHeal"
	print("\n--- %s ---" % _test)

	var sd: Dictionary = EquipmentSkills.skill_by_id("eq_治愈术")
	_check(absf(float(sd.get("heal_pct", 0.0)) - 0.25) < 0.01,
		"治愈术 heal_pct = 0.25", [str(sd.get("heal_pct"))])

	# **治疗落在 `GameManager.attributes` 上**，不是施法者替身的 hp 字段：
	# `_apply_heal_and_shield` 优先取 `GameManager.attributes.max_hp`，
	# 只有拿不到才退回施法者自己的 max_hp。故这里查真实属性容器。
	if not _has_gm_attributes():
		_check(true, "无 GameManager.attributes，跳过回血断言")
		return
	var before := _gm_hp()
	_gm_set_hp(before - 50.0)
	var damaged := _gm_hp()
	var caster := _make_caster()
	_cast(caster, sd)
	var after := _gm_hp()
	_check(after > damaged, "施放后回血",
		["before=%.1f damaged=%.1f after=%.1f" % [before, damaged, after]])
	caster.queue_free()


## 大地守护：`dr_pct` 必须挂上减伤词条
func _test_buff_skill_self_buff() -> void:
	_test = "BuffSkillSelfBuff"
	print("\n--- %s ---" % _test)

	var sd: Dictionary = EquipmentSkills.skill_by_id("eq_大地守护")
	_check(absf(float(sd.get("dr_pct", 0.0)) - 0.3) < 0.01,
		"大地守护 dr_pct = 0.30", [str(sd.get("dr_pct"))])

	var caster := _make_caster()
	_cast(caster, sd)
	var holder = caster.get("buffs")
	_check(holder != null and holder.call("has", "eq_skill_buff"),
		"施放后挂上技能增益词条")
	var dr: float = float(holder.call("total_damage_reduction")) if holder != null else 0.0
	_check(absf(dr - 0.3) < 0.01, "减伤生效 30%", ["dr=%.2f" % dr])
	caster.queue_free()


# ============================================================
# aoe / cone / dash 几何
# ============================================================

## 地裂术：目标区域型——圆心是准心方向 range 米处，不是脚下
func _test_aoe_at_aim() -> void:
	_test = "AoeAtAim"
	print("\n--- %s ---" % _test)

	var sd: Dictionary = EquipmentSkills.skill_by_id("eq_地裂术")
	_check(bool(sd.get("at_aim", false)), "地裂术标记为 at_aim")

	var caster := _make_caster()
	caster.global_position = Vector3.ZERO
	# 准心方向 6 米处放一个敌人：自身圆心（半径默认 3）打不到，at_aim 能打到
	var far := _make_enemy(Vector3(6, 0, 0))
	var near := _make_enemy(Vector3(1, 0, 0))
	_cast(caster, sd, Vector3.RIGHT)
	_check(float(far.get("hp")) < 100.0, "准心方向 6 米处的敌人被打中",
		["hp=%.1f" % float(far.get("hp"))])
	_check(float(near.get("hp")) >= 100.0, "脚下的敌人**没有**被打中（证明不是自身圆心）",
		["hp=%.1f" % float(near.get("hp"))])
	_cleanup(caster)


## 裂空斩：描述未给射程的 cone 类必须兜底默认值，不能是 0
func _test_cone_reach_fallback() -> void:
	_test = "ConeReachFallback"
	print("\n--- %s ---" % _test)

	var sd: Dictionary = EquipmentSkills.skill_by_id("eq_裂空斩")
	_check(not sd.is_empty(), "裂空斩在表中")
	_check(float(sd.get("reach", 0.0)) <= 0.0,
		"裂空斩 reach 列为 0（旧表是倍率副本，已清零）",
		[str(sd.get("reach"))])

	var caster := _make_caster()
	caster.global_position = Vector3.ZERO
	# 3 米内的敌人：兜底默认 3.0 应能打到
	var e := _make_enemy(Vector3(2.5, 0, 0))
	_cast(caster, sd, Vector3.RIGHT)
	_check(float(e.get("hp")) < 100.0, "reach 缺失时兜底生效，扇形不是零射程",
		["hp=%.1f" % float(e.get("hp"))])
	_cleanup(caster)


## 野蛮冲撞：位移距离写在 extra.range，不能是 0
func _test_dash_range() -> void:
	_test = "DashRange"
	print("\n--- %s ---" % _test)

	var sd: Dictionary = EquipmentSkills.skill_by_id("eq_野蛮冲撞战斧")
	_check(absf(float(sd.get("range", 0.0)) - 5.0) < 0.01,
		"野蛮冲撞 range = 5 米", [str(sd.get("range"))])

	var caster := _make_caster()
	caster.global_position = Vector3.ZERO
	var e := _make_enemy(Vector3(4, 0, 0))
	_cast(caster, sd, Vector3.RIGHT)
	_check(float(e.get("hp")) < 100.0, "冲刺沿途的敌人被打中",
		["hp=%.1f" % float(e.get("hp"))])
	_cleanup(caster)


# ============================================================
# 控制 / 击飞 / 持续区域 / 反伤
# ============================================================

## 冰封领域：control=freeze 必须映射到存在的词条并挂上
func _test_control_and_knockup() -> void:
	_test = "ControlKnockup"
	print("\n--- %s ---" % _test)

	var sd: Dictionary = EquipmentSkills.skill_by_id("eq_冰封领域")
	_check(str(sd.get("control", "")) == "freeze", "冰封领域 control=freeze",
		[str(sd.get("control"))])

	var caster := _make_caster()
	caster.global_position = Vector3.ZERO
	var e := _make_enemy(Vector3(2, 0, 0))
	_cast(caster, sd, Vector3.RIGHT)
	var tb = e.get("buffs")
	_check(tb != null and tb.call("has", "freeze"), "敌人被冻结")
	_check(float(e.get("hp")) < 100.0, "同时造成伤害", ["hp=%.1f" % float(e.get("hp"))])
	_cleanup(caster)

	# 缠绕：类别 root → 词条 entangle（两者不同名，直接拿类别会失败）
	var sd2: Dictionary = EquipmentSkills.skill_by_id("eq_缠绕藤蔓法杖")
	_check(str(sd2.get("control", "")) == "root", "缠绕藤蔓 control=root")
	var caster2 := _make_caster()
	caster2.global_position = Vector3.ZERO
	var e2 := _make_enemy(Vector3(3, 0, 0))
	_cast(caster2, sd2, Vector3.RIGHT)
	var tb2 = e2.get("buffs")
	_check(tb2 != null and tb2.call("has", "entangle"), "root 类别映射到 entangle 词条")
	_cleanup(caster2)


## 毒雾弹：持续型必须开区域，而不是只结算一次
func _test_persistent_zone() -> void:
	_test = "PersistentZone"
	print("\n--- %s ---" % _test)

	var sd: Dictionary = EquipmentSkills.skill_by_id("eq_毒雾弹")
	_check(float(sd.get("tick_interval", 0.0)) > 0.0, "毒雾弹标记为持续型",
		[str(sd.get("tick_interval"))])

	var caster := _make_caster()
	caster.global_position = Vector3.ZERO
	var e := _make_enemy(Vector3(2, 0, 0))
	var zones_before := get_tree().get_nodes_in_group("damage_zones").size()
	_cast(caster, sd, Vector3.RIGHT)
	var zones_after := get_tree().get_nodes_in_group("damage_zones").size()
	_check(zones_after > zones_before, "施放后生成了持续区域",
		["before=%d after=%d" % [zones_before, zones_after]])
	# 推进若干帧让 tick 结算
	for i in 12:
		await get_tree().process_frame
	_check(float(e.get("hp")) < 100.0, "区域 tick 造成了伤害",
		["hp=%.1f" % float(e.get("hp"))])
	_cleanup(caster)


## 反击姿态：block_all + reflect_pct 必须挂上并生效
func _test_reflect_and_block() -> void:
	_test = "ReflectBlock"
	print("\n--- %s ---" % _test)

	var sd: Dictionary = EquipmentSkills.skill_by_id("eq_反击姿态")
	_check(bool(sd.get("block_all", false)), "反击姿态 block_all")
	_check(absf(float(sd.get("reflect_pct", 0.0)) - 0.8) < 0.01,
		"反击姿态 reflect_pct = 0.8", [str(sd.get("reflect_pct"))])

	var caster := _make_caster()
	_cast(caster, sd)
	var holder = caster.get("buffs")
	var p: Dictionary = holder.call("params_of_active", "eq_skill_buff") if holder != null else {}
	_check(absf(float(p.get("reflect_up", 0.0)) - 0.8) < 0.01,
		"反伤数值经 params 覆盖生效", [str(p.get("reflect_up"))])
	_check(bool(p.get("block_all", false)), "格挡标记生效")
	caster.queue_free()


# ============================================================
# 元素 / 投射物
# ============================================================

## 冰锥术：技能自身的 element 必须生效（不是退回武器元素）
func _test_element_from_skill() -> void:
	_test = "ElementFromSkill"
	print("\n--- %s ---" % _test)

	var sd: Dictionary = EquipmentSkills.skill_by_id("eq_冰锥术法杖")
	_check(str(sd.get("element", "")) == "frost", "冰锥术 element=frost",
		[str(sd.get("element"))])

	var ss := SkillSystem.new()
	var e: int = ss.call("_elem_from_key", "frost")
	_check(e == ElementDefs.Elem.FROST, "frost → Elem.FROST", [str(e)])
	_check(ss.call("_elem_from_key", "holy") == -1, "不存在的元素返回 -1（不静默错位）")


## 冰锥术：count=3 必须出 3 枚，不是 1 枚
func _test_projectile_multi() -> void:
	_test = "ProjectileMulti"
	print("\n--- %s ---" % _test)

	var sd: Dictionary = EquipmentSkills.skill_by_id("eq_冰锥术法杖")
	_check(int(sd.get("count", 1)) == 3, "冰锥术 count = 3", [str(sd.get("count"))])

	var caster := _make_caster()
	caster.global_position = Vector3.ZERO
	var before := _count_projectiles()
	_cast(caster, sd, Vector3.RIGHT)
	await get_tree().process_frame
	var after := _count_projectiles()
	_check(after - before == 3, "一次施法生成 3 枚投射物",
		["before=%d after=%d" % [before, after]])
	_cleanup(caster)


## 数场景里活着的投射物（Projectile 是 Area3D，按类型找）
func _count_projectiles() -> int:
	var n := 0
	for c in get_children():
		if c is Projectile:
			n += 1
	return n


# ============================================================
# 职业技能补线
# ============================================================

## 血怒：hp_drain_pct + atk_from_drain 必须真的扣血换攻
func _test_blood_rage_drain() -> void:
	_test = "BloodRageDrain"
	print("\n--- %s ---" % _test)

	var found := ClassDefs.find_skill("blood_rage")
	_check(not found.is_empty(), "血怒在职业表中")
	if found.is_empty():
		return
	var sd: Dictionary = found["skill"]
	_check(float(sd.get("hp_drain_pct", 0.0)) > 0.0, "血怒声明了 hp_drain_pct")
	_check(bool(sd.get("atk_from_drain", false)), "血怒声明了 atk_from_drain")

	var caster := _make_caster()
	_cast(caster, sd)
	var holder = caster.get("buffs")
	_check(holder != null and holder.call("has", "eq_blood_rage"),
		"血怒挂上了以血换攻词条")
	# 推进 tick：`drain` 分支**自己扣血**（不靠调用方读返回值——
	# player/enemy 两端都只读 `dot` 键，血怒曾因此不掉血）
	var hp_before: float = float(caster.get("hp"))
	for i in 70:
		holder.call("tick", 0.05)
	var hp_after: float = float(caster.get("hp"))
	_check(hp_after < hp_before, "每秒扣血生效",
		["before=%.1f after=%.1f" % [hp_before, hp_after]])
	_check(float(caster.get("atk")) > 50.0, "失去的生命转成了攻击力",
		["atk=%.1f" % float(caster.get("atk"))])
	caster.queue_free()


## 生存本能：heal_pct_max 必须被 _apply_heal_and_shield 认到
func _test_class_skills_regression() -> void:
	_test = "ClassSkillsRegression"
	print("\n--- %s ---" % _test)

	var total := 0
	for cid in ClassDefs.class_ids():
		for slot in ClassDefs.FORM_SLOTS:
			for s in ClassDefs.skills_of(str(cid), int(slot)):
				total += 1
	_check(total == 40, "职业技能共 40 条", [str(total)])

	# 生存本能：heal_pct_max 必须被 _apply_heal_and_shield 认到
	var si := ClassDefs.find_skill("survival_instinct")
	_check(not si.is_empty(), "生存本能在职业表中")
	if not si.is_empty():
		var sd: Dictionary = si["skill"]
		_check(float(sd.get("heal_pct_max", 0.0)) > 0.0,
			"生存本能声明了 heal_pct_max（旧实现只认 heal_pct，回血没发生）")
		if not _has_gm_attributes():
			_check(true, "无 GameManager.attributes，跳过回血断言")
			return
		_gm_set_hp(_gm_hp() - 50.0)
		var damaged := _gm_hp()
		var caster := _make_caster()
		_cast(caster, sd)
		_check(_gm_hp() > damaged, "生存本能真的回血了",
			["damaged=%.1f after=%.1f" % [damaged, _gm_hp()]])
		caster.queue_free()


# ============================================================
# GameManager 属性容器访问（治疗/护盾落在这里）
# ============================================================

func _has_gm_attributes() -> bool:
	return _ensure_gm_attributes()


## 确保 `GameManager.attributes` 存在
##
## 它只在**开局**（`GameManager.start_run` → `_reset_run`）时创建，
## 而测试不开局——于是 `_apply_heal_and_shield` 取不到最大生命，
## 治疗/护盾**静默跳过**，断言只能被跳过（那等于没测）。
## 这里补一个实例，让回血路径真的被执行。
func _ensure_gm_attributes() -> bool:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return false
	if gm.get("attributes") == null:
		gm.attributes = load("res://data/attributes/attribute_system.gd").new()
	return gm.get("attributes") != null


func _gm_hp() -> float:
	var gm := get_node_or_null("/root/GameManager")
	return float(gm.attributes.hp) if gm != null and gm.get("attributes") != null else 0.0


func _gm_set_hp(v: float) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.get("attributes") != null:
		gm.attributes.hp = maxf(v, 1.0)


# ============================================================
# 替身
# ============================================================

## 施法者替身：具备 SkillSystem 需要的全部接口
##
## 用**真实 Player** 代价太大（要场景树、GameManager、状态机），
## 故用替身只实现被调用到的那几个方法。`class_id` / `form_slot`
## 留空 → 形态修正一律走 fallback，不影响技能本身的效果断言。
func _make_caster() -> Node3D:
	var c := _CasterStub.new()
	_world().add_child(c)
	return c


## 敌人替身：`take_damage` 记 hp，`buffs` 挂真 BuffHolder
func _make_enemy(pos: Vector3) -> Node3D:
	var e := _EnemyStub.new()
	_world().add_child(e)
	e.global_position = pos
	e.add_to_group("enemies")
	_enemies.append(e)
	return e


## 所有替身的挂载点 —— 必须是 **Node3D**
##
## `SkillSystem._projectile_parent` 从施法者向上找最近的 Node3D 祖先，
## 找不到就 `return null` 并**静默不出投射物/区域**。测试根节点是 `Node`，
## 故必须显式提供一个 Node3D 容器，否则投射物与持续区域类断言
## 会因为「挂载点不存在」而失败——那不是产品问题，是测试环境问题。
var _world_node: Node3D = null

func _world() -> Node3D:
	if _world_node == null or not is_instance_valid(_world_node):
		_world_node = Node3D.new()
		_world_node.name = "TestWorld"
		add_child(_world_node)
	return _world_node


func _cleanup(caster: Node3D) -> void:
	if is_instance_valid(caster):
		caster.queue_free()
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()


## 施法：直接调 SkillSystem（绕过 Player 的输入/资源层）
##
## 注意 `_projectile_parent` 会从施法者**向上找最近的 Node3D**——
## 测试根节点是 `Node`（不是 Node3D），所以替身必须挂在一个
## **Node3D 容器**下，否则投射物/区域类技能会静默不出东西。
func _cast(caster: Node3D, sd: Dictionary, dir: Vector3 = Vector3.RIGHT) -> void:
	var ss := SkillSystem.new()
	# 走真实分派逻辑，而不是直接调 _cast_xxx——这样 kind 分派本身也被覆盖
	ss.call("cast_skill", caster, str(sd.get("id", "")), dir, null)


func _is_meta_key(k: String) -> bool:
	return k in ["id", "name", "kind", "cooldown", "damage_mult", "reach",
		"duration", "desc", "cost", "from_equipment", "source_equip"]


func _is_valid_element(key: String) -> bool:
	for e in ElementDefs.Elem.values():
		if ElementDefs.Elem.keys()[e].to_lower() == key.to_lower():
			return true
	return false


func _check(c: bool, name: String, detail: Array = []) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
		for d in detail:
			print("    %s" % d)


# ============================================================
# 替身类
# ============================================================

## 施法者替身
class _CasterStub extends Node3D:
	var hp := 500.0
	var max_hp := 500.0
	var shield := 0.0
	var buffs: BuffHolder = null
	var atk := 50.0
	var ap := 30.0
	var attack_element := -1
	var class_id := ""
	var form_slot := 0
	var summons = null
	var _stealth := 0.0

	func _init() -> void:
		buffs = BuffHolder.new(self)

	func stat_value(key: String) -> float:
		match key:
			"atk": return atk
			"ap": return ap
			"hp": return max_hp
			"crt": return 0.05
			"crd": return 0.5
			_: return 0.0

	func eff_atk() -> float: return atk
	func eff_ap() -> float: return ap

	## 属性修正：BuffHolder._sync_modifier 会调
	func add_modifier(_src: String, stat: int, flat: float, _pct: float) -> void:
		if stat == AttributeSystem.Stat.ATK:
			atk += flat
	func remove_modifiers(_src: String) -> void: pass

	func heal(amount: float) -> float:
		var before := hp
		hp = minf(hp + amount, max_hp)
		return hp - before

	func take_damage(amount: float) -> void:
		hp = maxf(hp - amount, 0.0)

	## 技能护盾接口
	func _add_shield(amount: float, cap_pct: float) -> void:
		shield = minf(shield + amount, max_hp * cap_pct)

	## 冲刺位移（技能位移走这里）
	func apply_skill_dash(dir: Vector3, dist: float) -> void:
		global_position += dir * dist

	func enter_stealth(_s: float, _spd: float, _nb: float, _inv: bool) -> void:
		_stealth = 1.0

	func skill_range_mult() -> float: return 1.0


## 敌人替身：`take_damage(amount, crit, push, from)` 与真实敌人同签名
class _EnemyStub extends Node3D:
	var hp := 100.0
	var max_hp := 100.0
	var defense := 0.0
	var buffs: BuffHolder = null
	var push := Vector3.ZERO

	func _init() -> void:
		buffs = BuffHolder.new(self)

	func take_damage(amount: float, _crit: bool = false, p: Vector3 = Vector3.ZERO,
			_from: Node3D = null) -> void:
		hp = maxf(hp - amount, 0.0)
		push = p

	func hp_ratio() -> float:
		return hp / maxf(max_hp, 1.0)

	func add_modifier(_src: String, _stat: int, _flat: float, _pct: float) -> void: pass
	func remove_modifiers(_src: String) -> void: pass
	func eff_atk() -> float: return 10.0
	func eff_ap() -> float: return 10.0
