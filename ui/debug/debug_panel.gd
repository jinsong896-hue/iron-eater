extends CanvasLayer
## F1 调试面板 —— 实机测试模式的按钮化工作台
##
## 所有按钮最终都走 DebugManager.execute(命令行) —— 与控制台**同一条路径**，
## 不另写一套逻辑（否则两边的行为会漂移）。
##
## 未开启 testmode 时 open() 不开、只在控制台回显提示。

@onready var _info: Label = get_node_or_null("Root/Panel/VBox/Info")
@onready var _room_list: VBoxContainer = get_node_or_null("Root/Panel/VBox/Cols/Nav/Scroll/RoomList")
@onready var _monster_list: VBoxContainer = get_node_or_null("Root/Panel/VBox/Cols/Spawn/Scroll/MonsterList")
@onready var _spawn_count: LineEdit = get_node_or_null("Root/Panel/VBox/Cols/Spawn/CountRow/SpawnCount")
@onready var _ts_slider: HSlider = get_node_or_null("Root/Panel/VBox/Cols/Time/TsRow/TsSlider")
@onready var _ts_label: Label = get_node_or_null("Root/Panel/VBox/Cols/Time/TsRow/TsLabel")
@onready var _dmg_input: LineEdit = get_node_or_null("Root/Panel/VBox/Cols/Time/DmgRow/DmgInput")

var _selected_monster := ""
var _room_buttons: Array = []
var _monster_buttons: Array = []


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	var dm := _dm()
	if dm and dm.has_method("register_panel"):
		dm.call("register_panel", self)
	_wire_buttons()
	if _ts_slider:
		_ts_slider.min_value = 0.1
		_ts_slider.max_value = 3.0
		_ts_slider.step = 0.05
		_ts_slider.value = 1.0
		_ts_slider.value_changed.connect(_on_ts_changed)


func _dm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("DebugManager")
	return null


func _exec(cmd: String) -> Dictionary:
	var dm := _dm()
	if dm == null or not dm.has_method("execute"):
		return {"ok": false, "error": "DebugManager 不可用"}
	var r: Dictionary = dm.call("execute", cmd)
	# 顺带回显到控制台，便于对照
	var con = dm.call("get_console")
	if con != null and con.has_method("_print_line"):
		con.call("_print_line", "> %s  %s" % [cmd, r.get("text", "") if r.get("ok") else r.get("error", "")])
	return r


# ============================================================
# 开关
# ============================================================

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_panel"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	var dm := _dm()
	if dm == null or not bool(dm.call("is_testmode")):
		_echo("调试模式未开启。请先按 ` 打开控制台，执行：testmode on")
		return
	visible = true
	_rebuild_rooms()
	_rebuild_monsters()
	_refresh_info()
	_reconcile()


func close() -> void:
	visible = false
	_reconcile()


func _reconcile() -> void:
	var dm := _dm()
	if dm and dm.has_method("reconcile_modal"):
		dm.call("reconcile_modal")


## 没开控制台时的提示出口：写到控制台回显里
func _echo(s: String) -> void:
	var dm := _dm()
	if dm == null:
		return
	var con = dm.call("get_console")
	if con != null and con.has_method("_print_line"):
		con.call("_print_line", "[面板] %s" % s)
	else:
		print("[DebugPanel] ", s)


# ============================================================
# 按钮接线（全部转成命令行）
# ============================================================

func _wire_buttons() -> void:
	_bind("Root/Panel/VBox/Cols/Player/BtnGod", "god")
	_bind("Root/Panel/VBox/Cols/Player/BtnHeal", "heal")
	_bind("Root/Panel/VBox/Cols/Player/BtnGold", "gold 1000")
	_bind("Root/Panel/VBox/Cols/Player/BtnCrit", "crit")
	_bind("Root/Panel/VBox/Cols/Player/BtnCd", "cdreset")
	_bind("Root/Panel/VBox/Cols/Nav/BtnClear", "clear")
	_bind("Root/Panel/VBox/Cols/Spawn/BtnSpawn", "")          # 特殊：带选中的怪
	for f in range(1, 10):
		_bind("Root/Panel/VBox/Cols/Nav/FloorRow/BtnF%d" % f, "floor %d" % f)
	if _ts_slider:
		_bind_dmg()


func _bind(path: String, cmd: String) -> void:
	var b := get_node_or_null(path) as Button
	if b == null:
		return
	if cmd == "":
		b.pressed.connect(_on_spawn_pressed)
		return
	b.pressed.connect(func(): _exec(cmd); _refresh_info())


func _bind_dmg() -> void:
	if _dmg_input == null:
		return
	_dmg_input.text_submitted.connect(func(t):
		if t.is_valid_float():
			_exec("dmgmult %s" % t)
	)


func _on_ts_changed(v: float) -> void:
	_exec("timescale %.2f" % v)
	if _ts_label:
		_ts_label.text = "%.2fx" % v


func _on_spawn_pressed() -> void:
	if _selected_monster == "":
		_echo("先在下方的怪物列表里点一只")
		return
	var n := 1
	if _spawn_count and _spawn_count.text.is_valid_int():
		n = maxi(_spawn_count.text.to_int(), 1)
	_exec("spawn %s %d" % [_selected_monster, n])
	_refresh_info()


# ============================================================
# 列表（纯鼠标点击 —— 项目里没有焦点导航的先例，不为调试面板新造一套）
# ============================================================

func _rebuild_rooms() -> void:
	if _room_list == null:
		return
	for c in _room_list.get_children():
		c.queue_free()
	_room_buttons.clear()
	var dm := _dm()
	var gr = dm.call("game_root") if dm else null
	if gr == null:
		return
	var graph: Array = gr.get("dungeon_graph")
	var cur := int(gr.get("current_room_index"))
	for i in graph.size():
		var b := Button.new()
		var mark := " ←当前" if i == cur else ""
		b.text = "%2d  %s%s" % [i, str(graph[i].get("type", "?")), mark]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			_exec("tp %d" % i)
			await get_tree().process_frame
			_rebuild_rooms()
			_refresh_info())
		_room_list.add_child(b)
		_room_buttons.append(b)


func _rebuild_monsters() -> void:
	if _monster_list == null:
		return
	for c in _monster_list.get_children():
		c.queue_free()
	_monster_buttons.clear()
	var dm := _dm()
	if dm == null:
		return
	var ids: Array = dm.call("monster_ids")
	for mid in ids:
		var b := Button.new()
		b.text = str(mid)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			_selected_monster = str(mid)
			_highlight_monster())
		_monster_list.add_child(b)
		_monster_buttons.append(b)


func _highlight_monster() -> void:
	for b in _monster_buttons:
		b.modulate = Color(1, 1, 1)
		if str(b.text) == _selected_monster:
			b.modulate = Color(1.0, 0.85, 0.4)


# ============================================================
# 信息栏
# ============================================================

func _process(_delta: float) -> void:
	if visible:
		_refresh_info()


func _refresh_info() -> void:
	if _info == null:
		return
	var dm := _dm()
	if dm == null:
		return
	var parts: Array = ["FPS %d" % Engine.get_frames_per_second()]
	parts.append("时间 %.2fx" % float(dm.get("debug_time_scale")))
	parts.append("无敌 %s" % ("开" if bool(dm.get("god_mode")) else "关"))
	parts.append("倍率 %.2f" % float(dm.get("damage_multiplier")))
	parts.append("强制暴击 %s" % ("开" if bool(dm.get("force_crit")) else "关"))
	var gr = dm.call("game_root")
	if gr != null:
		var graph: Array = gr.get("dungeon_graph")
		var idx := int(gr.get("current_room_index"))
		var gm = dm.call("game_manager")
		var fl := int(gm.get("run_info").get("floor", 1)) if gm else 1
		parts.append("第 %d 层" % fl)
		if idx < graph.size():
			parts.append("房 %d(%s)" % [idx, str(graph[idx].get("type", "?"))])
	var ctrl = dm.call("room_controller")
	if ctrl != null:
		parts.append("敌人 %d" % int(ctrl.get("enemies_alive")))
	_info.text = "   ".join(parts)
