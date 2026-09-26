extends Node
## 远程普攻测试 —— 验证「主手带远程标签的武器 → 普攻发射投射物」
##
## ## 要回答的问题
##
## 1. 武器标签判定正确吗？（弓/弩 → 远程；剑/斧 → 近战；空手 → 近战）
## 2. 装备远程武器后普攻**真的生成了投射物**，且不再走近战扇形？
## 3. 换回近战武器后能切回去？（状态不串）
## 4. 投射物命中后**结算是否走回 `Player._apply_hit`**——
##    即连击计数、生命偷取、装备触发这些普攻效果对远程同样生效？
##
## 第 4 点是本功能的关键：投射物自带的 `_deal_damage` 只做元素管线 + 裸
## `take_damage`，若远程走那条路，收益会比近战少一大截。

var failed := 0
var _test := ""


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 40.0
	guard.timeout.connect(func(): print("RANGED ATTACK TESTS FAILED: 超时"); get_tree().quit(1))
	add_child(guard); guard.start()
	await get_tree().process_frame
	await get_tree().process_frame

	var gr := get_tree().current_scene.get_node_or_null("MainScene/GameRoot")
	if gr == null:
		print("无 MainScene"); get_tree().quit(1); return

	_test_weapon_tag_detection()
	await _test_ranged_attack_spawns_projectile()
	await _test_melee_weapon_still_melee()
	await _test_hit_callback_reaches_player()
	await _test_javelin_is_ranged()
	await _test_boomerang_returns()

	if failed == 0:
		print("ALL RANGED ATTACK TESTS PASSED")
		get_tree().quit(0)
	else:
		print("RANGED ATTACK TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 5. 标枪是远程武器（用户决策：改为普通远程武器的攻击方式）
##
## 规格表里标枪的 `weapon_type` 是 `spear`（与长矛共用），生成器按
## **名字含「标枪」**细分成 `javelin`——因为攻击方式完全不同
##（长矛近战突刺、标枪投掷）。
func _test_javelin_is_ranged() -> void:
	print("\n--- 标枪是远程武器 ---")
	var tpl = EquipmentDB.get_template("B113")   # 雷霆标枪
	if tpl == null:
		_check(false, "找到「雷霆标枪」(B113)")
		return
	_check(str(tpl.weapon_type) == "javelin",
		"雷霆标枪的 weapon_type = javelin", ["实际=%s" % tpl.weapon_type])
	var tags: Array = EquipmentDefs.weapon_tags_of(tpl.weapon_type, tpl.tags)
	_check("ranged" in tags, "雷霆标枪带「远程」标签（走远程普攻链路）", [str(tags)])

	# 普通长矛不该被误判为远程（防「一刀切」）
	var spear = EquipmentDB.get_template("B107")   # 击退长矛（spear）
	if spear != null:
		var stags: Array = EquipmentDefs.weapon_tags_of(spear.weapon_type, spear.tags)
		_check(str(spear.weapon_type) == "spear" and not ("ranged" in stags),
			"普通长矛仍是近战（未被标枪规则误伤）", [str(stags)])


## 6. 标枪子弹到射程上限**折返**而非消失（用户决策）
func _test_boomerang_returns() -> void:
	print("\n--- 标枪回旋（boomerang）---")
	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return
	var em = GameManager.equipment_manager
	if em == null:
		_check(false, "equipment_manager 就绪")
		return

	# 装标枪
	if not _equip_by_id("B113", EquipmentDefs.Slot.WEAPON_1):
		_check(false, "装上「雷霆标枪」")
		return
	await get_tree().process_frame
	_check(player.call("_main_weapon_is_javelin"), "主手判定为标枪")

	# 发一弹，找到它
	var before := _projectiles()
	player.call("_start_normal_attack")
	await get_tree().process_frame
	var after := _projectiles()
	_check(after.size() > before.size(), "标枪普攻生成了投射物",
		["before=%d after=%d" % [before.size(), after.size()]])
	if after.is_empty():
		return
	var proj = after[0]
	_check(bool(proj.get("boomerang")), "该投射物启用了 boomerang 模式")

	# 推进到超过 lifetime，确认**没有销毁**而是进入折返
	var lt: float = float(proj.get("lifetime"))
	var frames := int(lt / 0.0166) + 10
	for i in frames:
		await get_tree().physics_frame
		if not is_instance_valid(proj):
			break
	_check(is_instance_valid(proj),
		"到达射程上限后**没有消失**（%.2fs 后仍在）" % lt,
		["投射物已销毁"])
	if is_instance_valid(proj):
		_check(bool(proj.get("_returning")), "已进入折返状态（_returning = true）")
		# 折返应朝玩家飞：距离缩小
		var d0: float = proj.global_position.distance_to(player.global_position)
		for i in 20:
			await get_tree().physics_frame
			if not is_instance_valid(proj):
				break
		if is_instance_valid(proj):
			var d1: float = proj.global_position.distance_to(player.global_position)
			_check(d1 < d0, "折返中距离玩家越来越近（%.1f → %.1f）" % [d0, d1])

	# 最终应被回收（飞抵玩家身边 1 米内销毁）
	for i in 200:
		await get_tree().physics_frame
		if not is_instance_valid(proj):
			break
	_check(not is_instance_valid(proj), "飞抵玩家身边后销毁（不会永久残留）")

	em.unequip(EquipmentDefs.Slot.WEAPON_1)


## 场景里全部投射物
func _projectiles() -> Array:
	var out: Array = []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Projectile:
			out.append(cur)
		for c in cur.get_children():
			stack.append(c)
	return out


func _equip_by_id(id: String, slot: int) -> bool:
	var tpl = EquipmentDB.get_template(id)
	if tpl == null:
		return false
	GameManager.equipment_manager.equip(slot, EquipmentInstance.create(tpl))
	return true


# ============================================================
# 1. 武器标签判定
# ============================================================

func _test_weapon_tag_detection() -> void:
	_test = "WeaponTag"
	print("\n--- %s ---" % _test)

	# 弓：带「远程」标签
	var bow: Array = EquipmentDefs.weapon_tags_of("bow", ["远程", "双手", "物理"])
	_check("ranged" in bow, "bow → ranged", [str(bow)])

	# 弩
	var xbow: Array = EquipmentDefs.weapon_tags_of("crossbow", ["远程", "物理"])
	_check("ranged" in xbow, "crossbow → ranged", [str(xbow)])

	# 剑：不带「远程」
	var sword: Array = EquipmentDefs.weapon_tags_of("sword", ["近战", "单手", "物理"])
	_check(not ("ranged" in sword), "sword → 不是 ranged", [str(sword)])

	# 法杖：W11 学徒长杖带「远程」标签
	var staff: Array = EquipmentDefs.weapon_tags_of("staff", ["远程", "长杆", "法术"])
	_check("ranged" in staff, "带「远程」标签的 staff → ranged", [str(staff)])

	# 策划表的六系法杖只带「魔法」，不带「远程」
	var magic_staff: Array = EquipmentDefs.weapon_tags_of("staff", ["魔法", "双手", "长杆", "法术"])
	_check(not ("ranged" in magic_staff), "只带「魔法」的 staff → 不是 ranged",
		[str(magic_staff)])


# ============================================================
# 2/3. 普攻形态随武器切换
# ============================================================

## 装远程武器 → 普攻出投射物；装近战武器 → 出扇形、不出投射物
func _test_ranged_attack_spawns_projectile() -> void:
	_test = "RangedAttackSpawns"
	print("\n--- %s ---" % _test)

	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return
	var em = GameManager.equipment_manager
	if em == null:
		_check(false, "equipment_manager 就绪")
		return

	# 装一把弓
	var bow_inst := _make_weapon_instance("W09")   # 猎人长弓（远程）
	if bow_inst == null:
		_check(false, "猎人长弓(W09) 可实例化")
		return
	em.equip(EquipmentDefs.Slot.WEAPON_1, bow_inst)
	await get_tree().process_frame

	_check(player.call("_main_weapon_is_ranged"), "装备长弓后判定为远程")

	var before := _count_projectiles(player)
	player.call("_start_normal_attack")
	await get_tree().process_frame
	var after := _count_projectiles(player)
	_check(after > before, "远程普攻生成了投射物",
		["before=%d after=%d" % [before, after]])


## 换回近战武器：不出投射物
func _test_melee_weapon_still_melee() -> void:
	_test = "MeleeStillMelee"
	print("\n--- %s ---" % _test)

	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return
	var em = GameManager.equipment_manager
	if em == null:
		_check(false, "equipment_manager 就绪")
		return

	var sword_inst := _make_weapon_instance("W01")   # 单手剑（近战）
	if sword_inst == null:
		_check(false, "单手剑(W01) 可实例化")
		return
	em.equip(EquipmentDefs.Slot.WEAPON_1, sword_inst)
	await get_tree().process_frame

	_check(not player.call("_main_weapon_is_ranged"), "装备单手剑后判定为近战")

	var before := _count_projectiles(player)
	player.call("_start_normal_attack")
	await get_tree().process_frame
	var after := _count_projectiles(player)
	_check(after == before, "近战普攻**不**生成投射物",
		["before=%d after=%d" % [before, after]])


# ============================================================
# 4. 命中回调接回 Player（关键）
# ============================================================

## 投射物命中后，结算必须走 `Player._apply_hit`——
## 验证方式是看连击数是否增长（那是 `_apply_hit` 独有的副作用）。
func _test_hit_callback_reaches_player() -> void:
	_test = "HitCallback"
	print("\n--- %s ---" % _test)

	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return
	var em = GameManager.equipment_manager
	if em == null:
		_check(false, "equipment_manager 就绪")
		return

	var bow_inst := _make_weapon_instance("W09")
	em.equip(EquipmentDefs.Slot.WEAPON_1, bow_inst)
	await get_tree().process_frame

	# 造一个敌人放在**玩家正前方**（按玩家实际朝向，不是写死 +X）
	#
	# 玩家初始 `_facing = Vector3.FORWARD`（-Z）。若写死放在 +X，
	# 投射物朝 -Z 飞出去、敌人站在侧面，永远打不中——那不是产品 bug，
	# 是测试摆错了位置。
	var facing: Vector3 = player.get("_facing")
	if facing.length_squared() < 0.001:
		facing = Vector3.FORWARD
	facing = Vector3(facing.x, 0.0, facing.z).normalized()
	var enemy := _make_enemy(player.global_position + facing * 4.0)
	if enemy == null:
		_check(false, "敌人替身创建成功")
		return
	# 碰撞体由 `_ready()` → `visuals.build()` → `_create_collision()` 建。
	# 投射物靠 Area3D.body_entered 命中，**没有碰撞体就永远打不中**。
	await get_tree().physics_frame
	_check(enemy.get("_collision") != null, "敌人替身已建碰撞体（投射物命中依赖它）")

	var combo_before: int = int(player.call("get_hit_combo"))
	var hp_before := float(enemy.get("_hp"))

	player.call("_start_normal_attack")
	# 推进若干帧让投射物飞到（4 米 / 18 m/s ≈ 0.22s ≈ 14 帧 @60fps）
	for i in 30:
		await get_tree().physics_frame

	var hp_after := float(enemy.get("_hp"))
	_check(hp_after < hp_before, "投射物命中了敌人并造成伤害",
		["before=%.1f after=%.1f" % [hp_before, hp_after]])

	# **关键断言**：连击数增长说明结算走的是 `_apply_hit` 而非投射物的简化路径
	var combo_after: int = int(player.call("get_hit_combo"))
	_check(combo_after > combo_before,
		"命中后连击数增长（证明结算走回 Player._apply_hit，不是投射物自带的简化路径）",
		["before=%d after=%d" % [combo_before, combo_after]])

	enemy.queue_free()


# ============================================================
# 辅助
# ============================================================

func _player() -> Node3D:
	var ps := get_tree().get_nodes_in_group("player")
	if ps.is_empty():
		return null
	return ps[0] as Node3D


## 数场景里的投射物（Projectile 是 Area3D）
func _count_projectiles(root: Node) -> int:
	var n := 0
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Projectile:
			n += 1
		for c in cur.get_children():
			stack.append(c)
	return n


## 造一件武器实例
func _make_weapon_instance(id: String) -> EquipmentInstance:
	var tpl = EquipmentDB.get_template(id)
	if tpl == null:
		return null
	return EquipmentInstance.create(tpl)


## 造一个敌人替身（走真实 EnemyBase，保证 take_damage/hp_ratio 接口齐全）
func _make_enemy(pos: Vector3) -> Node3D:
	var eb = load("res://entities/enemies/enemy_base.gd")
	if eb == null:
		return null
	var e = eb.new()
	# 挂在玩家所在的世界节点下，保证在 enemies 组里能被命中
	var world := get_tree().current_scene.get_node_or_null("MainScene/GameRoot")
	if world == null:
		return null
	world.add_child(e)
	e.global_position = pos
	e.add_to_group("enemies")
	return e


func _check(c: bool, name: String, detail: Array = []) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
		for d in detail:
			print("    %s" % d)
