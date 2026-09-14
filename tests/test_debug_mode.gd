extends Node
## 调试模式测试：解析器 + 命令闸门 + 时间缩放 + 模态仲裁 + 场景集成
##
## 运行：godot --headless --path . res://tests/test_debug_mode.tscn

var failed := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 30.0
	guard.timeout.connect(func(): print("DEBUG MODE TESTS FAILED: 超时"); get_tree().quit(1))
	add_child(guard); guard.start()
	await get_tree().process_frame
	await get_tree().process_frame

	_test_tokenize()
	_test_validate()
	_test_suggest()
	_test_help_completeness()
	await _test_gate()
	_test_time_scale()
	await _test_modal()
	await _test_scene_integration()
	await _test_god_mode()

	if failed == 0:
		print("ALL DEBUG MODE TESTS PASSED")
		get_tree().quit(0)
	else:
		print("DEBUG MODE TESTS FAILED: %d" % failed)
		get_tree().quit(1)


func _dm() -> Node:
	return get_node_or_null("/root/DebugManager")


# ---------- 分词 ----------
func _test_tokenize() -> void:
	print("\n--- Tokenize ---")
	var DP = load("res://core/debug_parser.gd")

	var a: Dictionary = DP.tokenize("spawn rat_mutant 3")
	_check(a.get("ok", false) and a["tokens"] == ["spawn", "rat_mutant", "3"], "普通分词")

	var b: Dictionary = DP.tokenize("  gold   100  ")
	_check(b.get("ok", false) and b["tokens"] == ["gold", "100"], "多余空白/首尾空格")

	var c: Dictionary = DP.tokenize("say \"hello world\"")
	_check(c.get("ok", false) and c["tokens"] == ["say", "hello world"], "引号包裹含空格参数")

	var d: Dictionary = DP.tokenize("say \"unclosed")
	_check(not d.get("ok", false), "引号未闭合报错")

	var e: Dictionary = DP.tokenize("")
	_check(e.get("ok", false) and (e["tokens"] as Array).is_empty(), "空行得到空列表")

	var f: Dictionary = DP.tokenize("a\tb")
	_check(f.get("ok", false) and f["tokens"] == ["a", "b"], "制表符也算分隔")


# ---------- 命令校验 ----------
func _test_validate() -> void:
	print("\n--- Validate ---")
	var DP = load("res://core/debug_parser.gd")
	var dm := _dm()
	var reg: Dictionary = dm.get("COMMANDS")

	var v1: Dictionary = DP.validate(["gold", "100"], reg)
	_check(v1.get("ok", false) and v1["name"] == "gold" and v1["args"] == ["100"], "合法命令解析")

	var v2: Dictionary = DP.validate([], reg)
	_check(not v2.get("ok", false) and v2.get("error", "") == "", "空行静默（无错误文本）")

	var v3: Dictionary = DP.validate(["golld", "100"], reg)
	_check(not v3.get("ok", false) and v3.get("error", "").contains("gol"), "未知命令给近似候选",
		[str(v3.get("error"))])

	var v4: Dictionary = DP.validate(["gold"], reg)
	_check(not v4.get("ok", false) and v4.get("error", "").contains("参数"), "参数过少报错")

	var v5: Dictionary = DP.validate(["gold", "1", "2"], reg)
	_check(not v5.get("ok", false), "参数过多报错")

	var v6: Dictionary = DP.validate(["GOLD", "1"], reg)
	_check(v6.get("ok", false), "命令名大小写不敏感")


# ---------- 近似候选 ----------
func _test_suggest() -> void:
	print("\n--- Suggest ---")
	var DP = load("res://core/debug_parser.gd")
	var ids := ["rat_mutant", "zombie_prison", "skeleton_archer"]

	_check(DP.suggest("rat_mutnt", ids).has("rat_mutant"), "拼错一处仍能匹配")
	_check(DP.suggest("rat", ids).has("rat_mutant"), "前缀匹配")
	_check(DP.suggest("completely_different", ids).is_empty(), "毫无关系则无候选")

	var near: Array = DP.suggest("zombi", ids)
	_check(near.has("zombie_prison"), "短前缀能匹配到 zombie_prison", [str(near)])


# ---------- help 完整性 ----------
func _test_help_completeness() -> void:
	print("\n--- HelpCompleteness ---")
	var DP = load("res://core/debug_parser.gd")
	var dm := _dm()
	var reg: Dictionary = dm.get("COMMANDS")
	var txt: String = DP.help_text(reg)
	var missing: Array = []
	for k in reg:
		if not txt.contains(str(k)):
			missing.append(k)
	_check(missing.is_empty(), "help 覆盖全部命令（防新增命令漏写帮助）", [str(missing)])
	_check(txt.contains("timescale"), "help 含 timescale")


# ---------- 闸门（安全相关） ----------
func _test_gate() -> void:
	print("\n--- Gate ---")
	var dm := _dm()
	await get_tree().process_frame

	# 确保从关闭态开始
	dm.call("execute", "testmode off")
	_check(not bool(dm.call("is_testmode")), "testmode 初始为关")

	var gm := get_node_or_null("/root/GameManager")
	var before: int = int(gm.get("gold")) if gm else 0
	var r: Dictionary = dm.call("execute", "gold 100")
	_check(not r.get("ok", false), "未开启时 gold 被拒")
	_check(r.get("error", "").contains("testmode"), "拒绝信息提示先开 testmode",
		[str(r.get("error"))])
	var after: int = int(gm.get("gold")) if gm else 0
	_check(before == after, "被拒的命令没有副作用（金币未变）",
		["前 %d 后 %d" % [before, after]])

	# help 应被放行
	var h: Dictionary = dm.call("execute", "help")
	_check(h.get("ok", false), "未开启时 help 仍可用")

	# 开启后 gold 生效
	var on: Dictionary = dm.call("execute", "testmode on")
	_check(on.get("ok", false) and bool(dm.call("is_testmode")), "testmode on 生效")
	var r2: Dictionary = dm.call("execute", "gold 100")
	_check(r2.get("ok", false), "开启后 gold 可用")


# ---------- 时间缩放 ----------
func _test_time_scale() -> void:
	print("\n--- TimeScale ---")
	var dm := _dm()

	dm.call("execute", "timescale 0.5")
	_check(absf(float(dm.get("debug_time_scale")) - 0.5) < 0.001, "设置 0.5 生效")
	_check(absf(Engine.time_scale - 0.5) < 0.001, "Engine.time_scale 同步为 0.5")

	# 纯函数：hitstop 时乘 HITSTOP_TIME_SCALE(0.05)
	var eff: float = float(dm.call("effective_time_scale", true))
	_check(absf(eff - 0.05 * 0.5) < 0.001, "hitstop 时 = 0.05 × 倍率", [str(eff)])
	var eff2: float = float(dm.call("effective_time_scale", false))
	_check(absf(eff2 - 0.5) < 0.001, "非 hitstop 时 = 倍率本身", [str(eff2)])

	# 越界：**命令层拒绝**而不是静默钳制。
	# 0 会让引擎冻死且脚本无法恢复；静默改成 0.1 会让用户以为设成了 0。
	# 拒绝比钳制更不容易被误解。apply_time_scale() 内部的 clampf 是第二道防线。
	var r0: Dictionary = dm.call("execute", "timescale 0")
	_check(not r0.get("ok", false), "timescale 0 被拒（不是静默钳制）",
		[str(r0.get("error"))])
	_check(absf(float(dm.get("debug_time_scale")) - 0.5) < 0.001, "被拒时倍率保持原值 0.5",
		[str(dm.get("debug_time_scale"))])
	var r9: Dictionary = dm.call("execute", "timescale 99")
	_check(not r9.get("ok", false), "timescale 99 被拒")
	var rn: Dictionary = dm.call("execute", "timescale abc")
	_check(not rn.get("ok", false), "非数字被拒")

	# 第二道防线：apply_time_scale 自身钳制（即使有人绕过命令层直接调）
	dm.call("apply_time_scale", 0.0)
	_check(absf(float(dm.get("debug_time_scale")) - 0.1) < 0.001, "apply_time_scale 内部钳制下界到 0.1",
		[str(dm.get("debug_time_scale"))])
	dm.call("apply_time_scale", 99.0)
	_check(absf(float(dm.get("debug_time_scale")) - 3.0) < 0.001, "apply_time_scale 内部钳制上界到 3.0")

	# reset 复位
	dm.call("execute", "testmode off")
	_check(absf(float(dm.get("debug_time_scale")) - 1.0) < 0.001, "复位后倍率回 1.0")
	_check(absf(Engine.time_scale - 1.0) < 0.001, "复位后 Engine.time_scale 回 1.0")


# ---------- 模态仲裁（坑 3 回归） ----------
func _test_modal() -> void:
	print("\n--- ModalArbitration ---")
	var dm := _dm()
	dm.call("execute", "testmode on")

	# 控制台与面板同时「可见」的模拟：直接驱动 visible 再 reconcile
	var con = dm.call("get_console")
	var pan = dm.call("get_panel")
	_check(con != null, "控制台已注册")
	_check(pan != null, "面板已注册")

	con.set("visible", true)
	dm.call("reconcile_modal")
	await get_tree().process_frame
	_check(get_tree().paused, "控制台开着 → 暂停")

	pan.set("visible", true)
	dm.call("reconcile_modal")
	_check(dm.is_in_group("modal_ui"), "调试 UI 开着 → 加入 modal_ui 组")

	# 关键回归：关掉一个、另一个还开着 —— 不能恢复运行
	con.set("visible", false)
	dm.call("reconcile_modal")
	_check(get_tree().paused, "关控制台但面板还开着 → 仍暂停（回归：双 modal 误恢复）")

	pan.set("visible", false)
	dm.call("reconcile_modal")
	_check(not get_tree().paused, "两个都关 → 恢复运行")
	_check(not dm.is_in_group("modal_ui"), "两个都关 → 退出 modal_ui 组")


# ---------- 场景集成 ----------
func _test_scene_integration() -> void:
	print("\n--- SceneIntegration ---")
	var dm := _dm()
	dm.call("execute", "testmode on")

	var gr = dm.call("game_root")
	_check(gr != null, "找到 GameRoot")

	var ctrl = dm.call("room_controller")
	_check(ctrl != null, "找到 RoomController")
	if ctrl == null:
		return

	# 刷怪：必须复用 _spawn_enemy_at + register_summoned_enemy，否则清空判定会错
	var base: int = int(ctrl.get("enemies_alive"))
	var r: Dictionary = dm.call("execute", "spawn rat_mutant 3")
	_check(r.get("ok", false), "刷怪命令成功", [str(r.get("error"))])
	_check(int(ctrl.get("enemies_alive")) == base + 3, "存活数 +3",
		["前 %d 后 %d" % [base, int(ctrl.get("enemies_alive"))]])
	_check(not bool(ctrl.get("is_cleared")), "有敌人时不再标记清空")

	var alive: Array = ctrl.call("debug_living_enemies")
	_check(alive.size() >= 3, "运行时清单可读（%d 只）" % alive.size())

	# 未知怪物 id 要给近似候选
	var bad: Dictionary = dm.call("execute", "spawn rat_mutnt 1")
	_check(not bad.get("ok", false), "拼错的怪物 id 被拒")
	_check(bad.get("error", "").contains("rat_mutant"), "错误里给出最接近的 id",
		[str(bad.get("error"))])

	# 清房
	dm.call("execute", "clear")
	_check(int(ctrl.get("enemies_alive")) == 0, "清空后存活数 0")
	_check(bool(ctrl.get("is_cleared")), "清空后标记已清空")

	# 跳房
	var graph: Array = gr.get("dungeon_graph")
	if graph.size() > 1:
		dm.call("execute", "tp 1")
		await get_tree().process_frame
		await get_tree().process_frame
		_check(int(gr.get("current_room_index")) == 1, "跳房生效",
			[str(gr.get("current_room_index"))])

	# 越界跳房被拒
	var oob: Dictionary = dm.call("execute", "tp 999")
	_check(not oob.get("ok", false), "越界房间序号被拒")


# ---------- 无敌 ----------
func _test_god_mode() -> void:
	print("\n--- GodMode ---")
	var dm := _dm()
	dm.call("execute", "testmode on")

	var gr = dm.call("game_root")
	var p = gr.get("player") if gr else null
	if p == null:
		_check(false, "找到玩家")
		return
	var attrs = get_node_or_null("/root/GameManager").get("attributes")
	attrs.set("hp", float(attrs.get("max_hp")))

	# 开无敌：血量不变
	dm.call("execute", "god on")
	_check(bool(p.call("is_god_mode")), "无敌已开")
	var hp0: float = float(attrs.get("hp"))
	p.call("take_damage", 9999.0)
	_check(absf(float(attrs.get("hp")) - hp0) < 0.01, "无敌时血量不变",
		["%f → %f" % [hp0, float(attrs.get("hp"))]])

	# 关无敌：正常掉血
	dm.call("execute", "god off")
	_check(not bool(p.call("is_god_mode")), "无敌已关")
	p.call("take_damage", 50.0)
	_check(float(attrs.get("hp")) < hp0, "关掉后正常受伤",
		["%f → %f" % [hp0, float(attrs.get("hp"))]])


func _check(c: bool, name: String, detail: Array = []) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
		for d in detail:
			print("    %s" % d)
