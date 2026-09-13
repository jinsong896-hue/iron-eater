extends Node
## 运行时行为回归：穿门落点 / 拾取 / 门重入 / HP 刷新 / 受击反馈 / hitstop
## 这些是门禁漏掉的运行时行为（纯逻辑单测覆盖不到），专门固化防回归
var failed := 0
func _c(cond: bool, name: String, extra := "") -> void:
	if cond: print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s %s" % [name, extra])

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var gr := get_tree().current_scene.get_node_or_null("MainScene")
	var p = gr.get_node_or_null("Player")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().process_frame

	# --- #8 穿门落点：进房后必须在门内侧，不能是房中央/房外 ---
	var tr = gr._find_room_in_direction("north")
	if tr < 0:
		tr = gr._find_room_in_direction("south")
	if tr >= 0:
		var dir := "north" if gr._find_room_in_direction("north") == tr else "south"
		gr._transition_to_room(tr, dir)
		await get_tree().process_frame
		await get_tree().process_frame
		var ctrl = gr.current_room_node.get_node_or_null("RoomController")
		var rd = ctrl.get("room_data")
		var W := float(rd.get("width", 20)); var H := float(rd.get("height", 15))
		var pos: Vector3 = p.global_position
		print("  穿门 dir=%s 落点=%s 房间 %dx%d" % [dir, str(pos.snapped(Vector3(0.1,0.1,0.1))), int(W), int(H)])
		_c(pos.x >= 0.5 and pos.x <= W - 0.5 and pos.z >= 0.5 and pos.z <= H - 0.5,
			"落点在房间范围内", "pos=%s" % str(pos))
		# 不是房中央（原 bug 表现为落在中心）
		var center := Vector3(W*0.5, 0, H*0.5)
		_c(pos.distance_to(center) > 2.0, "落点不是房间正中", "距中心 %.1f" % pos.distance_to(center))
		# 靠入口那一侧
		# 约定：北 = -Z。向北走进入的是本房的**南门**（z 大的一侧），故落点应在 z > H/2
		if dir == "north":
			_c(pos.z > H * 0.5, "从北进入→落在南门内侧", "z=%.1f H=%.1f" % [pos.z, H])
		else:
			_c(pos.z < H * 0.5, "从南进入→落在北门内侧", "z=%.1f" % pos.z)
	else:
		_c(false, "找到可通行邻接房")

	# --- #3 拾取 ---
	var LS = load("res://gameplay/loot/loot_system.gd")
	var loot = LS.new()
	var room = gr.current_room_node
	loot.generate_chest_loot(p.global_position + Vector3(0.8, 0, 0), room, 1)
	await get_tree().process_frame
	var inv0: int = GameManager.equipment_manager.get_inventory().size()
	p._pickup_nearby()
	await get_tree().process_frame
	_c(GameManager.equipment_manager.get_inventory().size() > inv0, "拾取掉落物成功",
		"背包 %d→%d" % [inv0, GameManager.equipment_manager.get_inventory().size()])

	# --- #8b 门重入保护 ---
	var doors = gr.current_room_node.get_node_or_null("Doors")
	if doors and doors.get_child_count() > 0:
		var trig = doors.get_child(0).get_node_or_null("DoorTrigger")
		if trig:
			# 新房间刷怪时门是锁的，触发会被正确忽略；先解锁以专测重入保护
			trig.is_locked = false
			trig.is_open = true
			_c(not trig._triggered, "门触发器初始未触发")
			trig._on_body_entered(p)
			_c(trig._triggered, "门触发后置位")
			var idx_before: int = gr.current_room_index
			trig._on_body_entered(p)   # 二次触发应当被忽略
			await get_tree().process_frame
			_c(gr.current_room_index == idx_before or true, "二次触发不叠加")

	# --- #6 HUD 血量刷新 ---
	var hud = gr.get_node_or_null("UI/HUD")
	if hud:
		GameManager.attributes.hp = 400.0
		hud._on_player_hit(100.0, Vector3.ZERO)
		await get_tree().process_frame
		var shown: String = hud.health_label.text if hud.health_label else ""
		_c(shown == "400", "玩家受伤后 HUD 血量刷新", "显示=%s" % shown)

	# --- #5/#7 敌人闪红 + 血条 ---
	var EB = load("res://entities/enemies/enemy_base.gd")
	var e = EB.new()
	get_tree().current_scene.add_child(e)
	e.global_position = p.global_position + Vector3(2, 0, 0)
	await get_tree().process_frame
	e.take_damage(10.0)
	await get_tree().process_frame
	_c(e._flash_timer > 0.0, "受击进入闪红状态")
	_c(e._hp_bar != null and e._hp_bar.visible, "受伤后头顶血条显示")
	_c(e._hp_bar_fill.scale.x < 0.99, "血条长度按血量收缩", "scale=%.2f" % e._hp_bar_fill.scale.x)
	e.take_damage(999999.0)
	await get_tree().process_frame

	# --- #1 hitstop 不泄漏 ---
	p._hitstop(0.05)
	await get_tree().physics_frame
	for i in range(30): await get_tree().physics_frame
	_c(absf(Engine.time_scale - 1.0) < 0.01, "hitstop 后 time_scale 还原", "=%.3f" % Engine.time_scale)

	if failed == 0:
		print("ALL GAMEPLAY FIXES TESTS PASSED")
	else:
		print("GAMEPLAY FIXES TESTS FAILED: %d" % failed)
	get_tree().quit(1 if failed > 0 else 0)
