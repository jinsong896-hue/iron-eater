extends Node
## DebugManager —— 实机测试模式的唯一状态源（autoload）
##
## 三条设计约束（都是踩过的坑，不要"优化"掉）：
##
## 1) **不引用任何游戏 class_name**。全走 get_node_or_null + duck typing，
##    与 room_controller.gd 的既有做法一致：避免编译期循环依赖，
##    也保证 --script 测试模式能加载本文件。
##
## 2) **时间缩放只持倍率，不持瞬时值**。Engine.time_scale 有两个参与者：
##    本管理器（倍率）与 Player 的 hitstop（瞬时）。绝不在 _process 里轮询覆写，
##    否则每帧都在跟 hitstop 抢。真正写入 Engine.time_scale 的只有
##    Player._hitstop / _end_hitstop 与 apply_time_scale() 三处。
##
## 3) **暂停是派生状态**。控制台与 F1 面板是本项目第一对会同时存在的 modal，
##    各自写 get_tree().paused 会导致"关掉一个、另一个还开着却恢复游戏"。
##    故统一由 reconcile_modal() 裁决。

const GROUP_MODAL := "modal_ui"

## 时间缩放允许范围。0.0 在 Godot 里合法但会让引擎冻死且脚本无法恢复，
## 故上下界都钳制（命令层与本层双重防护）。
const TS_MIN := 0.1
const TS_MAX := 3.0

# —— 状态 ——
var testmode_enabled := false
var debug_time_scale := 1.0
var god_mode := false
var damage_multiplier := 1.0
var force_crit := false

var _console: Node = null
var _panel: Node = null
var _monster_ids: Array = []      ## 懒加载缓存（避免每帧 load）
var _monster_cache: Array = []

## 命令表。min/max 为参数个数；范围校验在对应处理器里（需要运行时上下文）。
const COMMANDS := {
	"testmode": {"min": 1, "max": 1, "usage": "testmode on|off",
		"desc": "总开关（off 时复位全部调试状态）"},
	"help": {"min": 0, "max": 1, "usage": "help [命令]",
		"desc": "查看命令说明"},
	"list": {"min": 1, "max": 1, "usage": "list monsters|rooms|entities",
		"desc": "列出怪物 / 房间 / 当前存活实体"},
	"god": {"min": 0, "max": 1, "usage": "god [on|off]",
		"desc": "无敌（省略参数则切换）"},
	"heal": {"min": 0, "max": 0, "usage": "heal", "desc": "回满血"},
	"gold": {"min": 1, "max": 1, "usage": "gold <数量>", "desc": "加金币"},
	"tp": {"min": 1, "max": 1, "usage": "tp <房间序号>",
		"desc": "跳到本层指定房间（序号从 0 起）"},
	"floor": {"min": 1, "max": 1, "usage": "floor <1-9>", "desc": "跳到指定层"},
	"clear": {"min": 0, "max": 0, "usage": "clear", "desc": "清空当前房间"},
	"spawn": {"min": 1, "max": 2, "usage": "spawn <怪物id> [数量]",
		"desc": "在玩家位置刷怪"},
	"timescale": {"min": 1, "max": 1, "usage": "timescale <0.1-3.0>",
		"desc": "时间缩放（慢动作看判定）"},
	"dmgmult": {"min": 1, "max": 1, "usage": "dmgmult <倍率>",
		"desc": "玩家出手伤害倍率"},
	"crit": {"min": 0, "max": 1, "usage": "crit [on|off]",
		"desc": "强制暴击（绕过法术不可暴击）"},
	"cdreset": {"min": 0, "max": 0, "usage": "cdreset", "desc": "重置玩家冷却"},
	"item": {"min": 1, "max": 2, "usage": "item <white|green|blue|purple|orange> [数量]",
		"desc": "给装备"},
	"potion": {"min": 1, "max": 1, "usage": "potion <数量>", "desc": "给生命药水"},
}


func _ready() -> void:
	# 常驻监听：控制台/面板自行注册进来，避免它们硬编码路径
	process_mode = Node.PROCESS_MODE_ALWAYS


## 离开场景树兜底：时间缩放松不得，泄漏出去整个游戏变慢动作
func _exit_tree() -> void:
	apply_time_scale(1.0)
	Engine.time_scale = 1.0


# ============================================================
# 状态查询
# ============================================================

func is_testmode() -> bool:
	return testmode_enabled


## InputManager 的闸门：控制台开着时，打字不应操作角色
func is_text_input_active() -> bool:
	var c := get_console()
	return c != null and bool(c.get("visible"))


## 供 Player._hitstop 读取（避免它们直接摸 autoload 字段名）
func get_debug_scale() -> float:
	return debug_time_scale


## 纯函数：便于单测，无需 Player 实例
func effective_time_scale(hitstopping: bool) -> float:
	if hitstopping:
		return maxf(Engine.time_scale * 0.0 + 0.05 * debug_time_scale, 0.001)
	return debug_time_scale


## 把倍率应用到引擎（唯一允许写 Engine.time_scale 的调试入口）
func apply_time_scale(v: float) -> void:
	debug_time_scale = clampf(v, TS_MIN, TS_MAX)
	Engine.time_scale = debug_time_scale


# ============================================================
# 模态仲裁（坑 3）
# ============================================================

## 暂停由本管理器统一裁决，控制台与面板不各写各的
func reconcile_modal() -> void:
	var any_open := _console_open() or _panel_open()
	var other := _other_modal_open()
	if any_open:
		if not is_in_group(GROUP_MODAL):
			add_to_group(GROUP_MODAL)
	elif is_in_group(GROUP_MODAL):
		remove_from_group(GROUP_MODAL)
	var tree := get_tree()
	if tree:
		tree.paused = any_open or other


## 只统计**别人**，不数自己——否则自己一在组里就永远认为有 modal
func _other_modal_open() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(GROUP_MODAL):
		if n != self:
			return true
	return false


func _console_open() -> bool:
	var c := get_console()
	return c != null and bool(c.get("visible"))


func _panel_open() -> bool:
	var p := get_panel()
	return p != null and bool(p.get("visible"))


func register_console(node: Node) -> void:
	_console = node


func register_panel(node: Node) -> void:
	_panel = node


func get_console() -> Node:
	return _console if is_instance_valid(_console) else null


func get_panel() -> Node:
	return _panel if is_instance_valid(_panel) else null


# ============================================================
# 命令执行（控制台与面板共用同一条路径）
# ============================================================

## 返回 {ok, text, error}
func execute(line: String) -> Dictionary:
	var tk := DebugParser.tokenize(line)
	if not tk.get("ok", false):
		return _err(str(tk.get("error", "")))
	var v := DebugParser.validate(tk.get("tokens", []), COMMANDS)
	if v.get("error", "") == "" and not v.get("ok", false):
		return {"ok": true, "text": "", "error": ""}   # 空行静默
	if not v.get("ok", false):
		return _err(str(v.get("error", "")))

	var name: String = v["name"]
	# 真闸门：未开启测试模式时只放行 testmode / help
	if not testmode_enabled and name not in ["testmode", "help"]:
		return _err("调试模式未开启。先执行：testmode on")

	match name:
		"testmode": return _cmd_testmode(v["args"])
		"help": return _cmd_help(v["args"])
		"list": return _cmd_list(v["args"])
		"god": return _cmd_god(v["args"])
		"heal": return _cmd_heal()
		"gold": return _cmd_gold(v["args"])
		"tp": return _cmd_tp(v["args"])
		"floor": return _cmd_floor(v["args"])
		"clear": return _cmd_clear()
		"spawn": return _cmd_spawn(v["args"])
		"timescale": return _cmd_timescale(v["args"])
		"dmgmult": return _cmd_dmgmult(v["args"])
		"crit": return _cmd_crit(v["args"])
		"cdreset": return _cmd_cdreset()
		"item": return _cmd_item(v["args"])
		"potion": return _cmd_potion(v["args"])
	return _err("命令未接线：%s" % name)


func _ok(text: String) -> Dictionary:
	return {"ok": true, "text": text, "error": ""}


func _err(text: String) -> Dictionary:
	return {"ok": false, "text": "", "error": text}


# ============================================================
# 各命令处理器
# ============================================================

func _cmd_testmode(args: Array) -> Dictionary:
	var a := str(args[0]).to_lower()
	if a == "on":
		testmode_enabled = true
		return _ok("调试模式已开启。F1 打开面板，~ 打开控制台。")
	if a == "off":
		reset_all()
		return _ok("调试模式已关闭，全部调试状态已复位。")
	return _err("用法：testmode on|off")


func _cmd_help(args: Array) -> Dictionary:
	return _ok(DebugParser.help_text(COMMANDS, str(args[0]) if args.size() > 0 else ""))


func _cmd_list(args: Array) -> Dictionary:
	var what := str(args[0]).to_lower()
	match what:
		"monsters":
			_ensure_monsters()
			var lines: Array = ["怪物 %d 种：" % _monster_ids.size()]
			for i in _monster_ids.size():
				lines.append("  %-18s %s" % [_monster_ids[i], _monster_cache[i].get("name", "")])
			return _ok("\n".join(lines))
		"rooms":
			var gr := game_root()
			if gr == null:
				return _err("不在游戏场景中")
			var graph: Array = gr.get("dungeon_graph")
			var lines2: Array = ["本层 %d 间房（当前 %d）：" % [graph.size(), int(gr.get("current_room_index"))]]
			for i in graph.size():
				var mark := " ←当前" if i == int(gr.get("current_room_index")) else ""
				lines2.append("  %2d  %-9s %s%s" % [i, str(graph[i].get("type", "?")),
					str(graph[i].get("position", "")), mark])
			return _ok("\n".join(lines2))
		"entities":
			var ctrl := room_controller()
			if ctrl == null:
				return _err("不在游戏场景中")
			var alive: Array = ctrl.call("debug_living_enemies")
			var lines3: Array = ["当前存活 %d 只：" % alive.size()]
			for e in alive:
				if is_instance_valid(e):
					lines3.append("  %s  血 %.0f" % [str(e.get("monster_name")), float(e.get("_hp"))])
			# 群体单位（CrowdSim）不是场景节点，上面那份清单里没有它们——
			# 不单独报一行的话，玩家会看到"存活 0 只"却仍在战斗中。
			var crowd = ctrl.get("_crowd_mgr")
			if crowd != null and is_instance_valid(crowd):
				lines3.append("  [群体模拟] %d 只" % int(crowd.get("active")))
			return _ok("\n".join(lines3))
	return _err("用法：list monsters|rooms|entities")


func _cmd_god(args: Array) -> Dictionary:
	god_mode = args.is_empty() if args.is_empty() else str(args[0]).to_lower() == "on"
	if not args.is_empty():
		var a := str(args[0]).to_lower()
		if a != "on" and a != "off":
			return _err("用法：god [on|off]")
		god_mode = a == "on"
	_apply_god()
	return _ok("无敌：%s" % ("开" if god_mode else "关"))


func _cmd_heal() -> Dictionary:
	var gm := game_manager()
	if gm == null:
		return _err("GameManager 不可用")
	var attrs = gm.get("attributes")
	if attrs == null:
		return _err("属性系统未初始化")
	attrs.set("hp", float(attrs.get("max_hp")))
	_emit_stats()
	return _ok("已回满血")


func _cmd_gold(args: Array) -> Dictionary:
	var n := _to_int(str(args[0]))
	if n < 0:
		return _err("数量必须是非负整数")
	var gm := game_manager()
	if gm == null:
		return _err("GameManager 不可用")
	gm.set("gold", int(gm.get("gold")) + n)
	var bus := event_bus()
	if bus:
		bus.emit_signal("gold_changed", int(gm.get("gold")))
	return _ok("金币 %d（+%d）" % [int(gm.get("gold")), n])


func _cmd_tp(args: Array) -> Dictionary:
	var idx := _to_int(str(args[0]))
	if idx < 0:
		return _err("房间序号必须是非负整数")
	var gr := game_root()
	if gr == null:
		return _err("不在游戏场景中")
	var graph: Array = gr.get("dungeon_graph")
	if idx >= graph.size():
		return _err("序号越界：本层只有 %d 间房（0~%d）" % [graph.size(), graph.size() - 1])
	gr.call("debug_goto_room", idx)
	return _ok("已跳到房间 %d（%s）" % [idx, str(graph[idx].get("type", "?"))])


func _cmd_floor(args: Array) -> Dictionary:
	var n := _to_int(str(args[0]))
	# 上限在这里钳制——next_floor() 自身没有 1..9 检查（那在传送门那边）
	if n < 1 or n > 9:
		return _err("层数范围 1~9（收到 %d）" % n)
	var gm := game_manager()
	var gr := game_root()
	if gm == null or gr == null:
		return _err("不在游戏场景中")
	var info = gm.get("run_info")
	info["floor"] = n          # next_floor() 自己不写层数，必须先设
	gr.call("debug_goto_floor", n)
	return _ok("已进入第 %d 层" % n)


func _cmd_clear() -> Dictionary:
	var ctrl := room_controller()
	if ctrl == null:
		return _err("不在游戏场景中")
	ctrl.call("debug_clear_enemies")
	return _ok("已清空当前房间")


func _cmd_spawn(args: Array) -> Dictionary:
	var mid := str(args[0])
	var count := 1
	if args.size() > 1:
		count = _to_int(str(args[1]))
		if count < 1:
			return _err("数量必须是正整数")
	var ctrl := room_controller()
	if ctrl == null:
		return _err("不在游戏场景中")
	var gr := game_root()
	var at: Vector3 = gr.get("player").global_position if gr and gr.get("player") else Vector3.ZERO
	var r: Dictionary = ctrl.call("debug_spawn", mid, count, at)
	if not r.get("ok", false):
		return _err(str(r.get("error", "刷怪失败")))
	return _ok("已生成 %d 只 %s" % [count, str(r.get("name", mid))])


func _cmd_timescale(args: Array) -> Dictionary:
	var v := _to_float(str(args[0]))
	if v < TS_MIN or v > TS_MAX:
		return _err("时间缩放范围 %.1f~%.1f（收到 %s）" % [TS_MIN, TS_MAX, str(args[0])])
	apply_time_scale(v)
	return _ok("时间缩放 %.2fx" % debug_time_scale)


func _cmd_dmgmult(args: Array) -> Dictionary:
	var v := _to_float(str(args[0]))
	if v < 0.0 or v > 1000.0:
		return _err("倍率范围 0~1000")
	damage_multiplier = v
	_apply_player()
	return _ok("伤害倍率 %.2fx" % damage_multiplier)


func _cmd_crit(args: Array) -> Dictionary:
	if args.is_empty():
		force_crit = not force_crit
	else:
		var a := str(args[0]).to_lower()
		if a != "on" and a != "off":
			return _err("用法：crit [on|off]")
		force_crit = a == "on"
	_apply_player()
	return _ok("强制暴击：%s" % ("开" if force_crit else "关"))


func _cmd_cdreset() -> Dictionary:
	var gr := game_root()
	if gr == null or gr.get("player") == null:
		return _err("不在游戏场景中")
	var p = gr.get("player")
	if p.has_method("reset_cooldowns"):
		p.call("reset_cooldowns")
	return _ok("玩家冷却已重置")


func _cmd_item(args: Array) -> Dictionary:
	var rarity_names := ["white", "green", "blue", "purple", "orange"]
	var rn := str(args[0]).to_lower()
	var ri := rarity_names.find(rn)
	if ri < 0:
		# 显式排除 red：枚举里有 Rarity.RED，朴素的 0..4 范围检查会误收
		return _err("稀有度只能是 %s（不含 red）" % ", ".join(rarity_names))
	var count := 1
	if args.size() > 1:
		count = _to_int(str(args[1]))
		if count < 1:
			return _err("数量必须是正整数")
	var gm := game_manager()
	if gm == null:
		return _err("GameManager 不可用")
	var em = gm.get("equipment_manager")
	if em == null:
		return _err("装备系统未初始化")
	var DB = load("res://data/equipment/equipment_db.gd")
	var Inst = load("res://data/equipment/equipment_instance.gd")
	if DB == null or Inst == null:
		return _err("装备数据层加载失败")
	var pool: Array = DB.get_templates_by_rarity(ri)
	if pool.is_empty():
		return _err("该稀有度暂无装备数据")
	var got := 0
	for _i in count:
		var tpl = pool[int(randi()) % pool.size()]
		var item = Inst.create(tpl)
		if em.add_item(item):
			got += 1
	var bus := event_bus()
	if bus:
		bus.emit_signal("inventory_changed")
	return _ok("已发放 %d 件 %s 装备（背包 %d）" % [got, rn, em.get_inventory().size()])


func _cmd_potion(args: Array) -> Dictionary:
	var n := _to_int(str(args[0]))
	if n < 1:
		return _err("数量必须是正整数")
	var gm := game_manager()
	if gm == null:
		return _err("GameManager 不可用")
	var inv = gm.get("consumable_inventory")
	if inv == null:
		return _err("消耗品背包未初始化")
	var r: Dictionary = inv.add_health_potion(n)
	if not r.get("ok", false):
		return _err(str(r.get("reason", "添加失败")))   # 容量上限由背包自己报，不静默钳制
	return _ok("药水 %d/%d" % [int(r.get("quantity", 0)), int(inv.get("capacity"))])


# ============================================================
# 复位
# ============================================================

func reset_all() -> void:
	testmode_enabled = false
	god_mode = false
	damage_multiplier = 1.0
	force_crit = false
	apply_time_scale(1.0)
	Engine.time_scale = 1.0
	_apply_god()
	_apply_player()


# ============================================================
# 与游戏侧对接（全部 get_node_or_null，无 class_name 依赖）
# ============================================================

func game_manager() -> Node:
	return _root_child("GameManager")


func event_bus() -> Node:
	return _root_child("EventBus")


func game_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("game_root")
	return nodes[0] if nodes.size() > 0 else null


func room_controller() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("current_room_controller")
	return nodes[0] if nodes.size() > 0 else null


func _root_child(name: String) -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)


func _emit_stats() -> void:
	var bus := event_bus()
	if bus:
		bus.emit_signal("stats_changed")


func _apply_god() -> void:
	var gr := game_root()
	if gr == null or gr.get("player") == null:
		return
	var p = gr.get("player")
	if p.has_method("set_god_mode"):
		p.call("set_god_mode", god_mode)


func _apply_player() -> void:
	var gr := game_root()
	if gr == null or gr.get("player") == null:
		return
	var p = gr.get("player")
	if p.has_method("set_damage_multiplier"):
		p.call("set_damage_multiplier", damage_multiplier)
	if p.has_method("set_force_crit"):
		p.call("set_force_crit", force_crit)


## 怪物清单懒加载（MonsterDB 是 class_name，用 load 避免编译期依赖）
func _ensure_monsters() -> void:
	if not _monster_ids.is_empty():
		return
	var DB = load("res://data/monsters/monster_db.gd")
	if DB == null:
		return
	DB.init()
	_monster_cache = DB.all_monsters()
	for m in _monster_cache:
		_monster_ids.append(str(m.get("id", "")))


func monster_ids() -> Array:
	_ensure_monsters()
	return _monster_ids


## 自动补全入口：把运行时上下文（怪物库/房间数）注入解析器。
## 解析器本身不认识 MonsterDB / dungeon_graph，故候选来源由这里提供。
func complete(line: String) -> Dictionary:
	var ctx := {"monster_ids": monster_ids(), "room_count": 0}
	var gr := game_root()
	if gr != null:
		ctx["room_count"] = (gr.get("dungeon_graph") as Array).size()
	return DebugParser.complete(line, COMMANDS, ctx)


# ============================================================
# 小工具
# ============================================================

func _to_int(s: String) -> int:
	if not s.is_valid_int():
		return -1
	return s.to_int()


func _to_float(s: String) -> float:
	if not s.is_valid_float():
		return -999.0
	return s.to_float()
