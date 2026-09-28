extends Node
## 加载前置检查 —— 主场景能否正常实例化
##
## ## 为什么单列一套
##
## 2026-09-28 实机「进游戏卡在加载界面」，根因是 `player.gd` 里一个
## **解析期**错误（调用了不存在的方法）→ 脚本加载失败 →
## 主场景里的 Player 实例化不出来 → 卡死。
##
## 当时三套门禁（affix_wire / ranged_atk / fixes2）都 FAIL 了，
## 但那些套件的失败信息是「找到玩家节点」这种**症状**，
## 被误判成「偶发」。本套件把根因**单列并指名道姓**。
##
## ## 判据
##
## 主场景实例化后，`MainScene/GameRoot` 下必须有 Player，
## 且它挂着脚本、关键子组件都在。少任何一样都说明
## 「某个脚本编译不过」——这是阻塞性故障，必须最先拦住。
var failed := 0


func _c(cond: bool, name: String, extra := "") -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s %s" % [name, extra])


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("\n--- 加载前置检查 ---")

	var root := get_tree().current_scene
	_c(root != null, "主场景已实例化")

	var gr := root.get_node_or_null("MainScene/GameRoot") if root else null
	_c(gr != null, "MainScene/GameRoot 存在")

	var p = gr.find_child("Player", true, false) if gr != null else null
	_c(p != null, "Player 节点存在（脚本解析失败时这里会是 null）")

	if p != null:
		_c(p.get_script() != null, "Player 挂着脚本（不是空节点）")
		# 脚本真加载了的话，这些由它创建的组件必然在
		for field in ["buffs", "skills", "equip_fx"]:
			_c(p.get(field) != null, "Player.%s 已初始化（脚本真的跑起来了）" % field)

	await _test_ui_scenes_loadable()

	# 装备数据库是全局依赖，也一并确认
	_test_summon_instantiable()
	_c(not EquipmentDB.all_templates().is_empty(),
		"装备数据库已加载（%d 件）" % EquipmentDB.all_templates().size())

	if failed == 0:
		print("ALL LOAD SANITY TESTS PASSED")
	else:
		print("LOAD SANITY TESTS FAILED: %d" % failed)
	get_tree().quit(1 if failed > 0 else 0)


## 召唤物能否实例化（**运行时才加载的脚本**）
##
## ## 背景：`_rng()` 那次（2026-09-28）
##
## `summon_base.gd` 里调了**不存在的方法** `_rng()`（全项目只有
## `_rng_mult` / `_rng_percent`）——`--check-only` 能验出解析错误，
## 后果是「一召唤就崩」。
##
## ## 本断言的**能力边界**（别高估它）
##
## 实测：**它抓不到那个错**——`SummonBase` 在类缓存里仍可见、
## `new()` 也仍成功（Godot 对「方法不存在」的解析错误不一定阻断实例化）。
## 故它只是「召唤物脚本至少能被引用」的最低保障。
##
## 真正能拦住的是 `--check-only` 逐个脚本扫（见 AGENTS 的收工流程想法），
## 以及**实机跑一遍**。留这条是为了防「整类被删/改名」这种更粗的错。
func _test_summon_instantiable() -> void:
	print("\n--- 召唤物脚本可实例化 ---")
	_c(SummonBase != null, "SummonBase 类可见（解析期错误会让它为 null）")
	if SummonBase == null:
		return
	var s = SummonBase.new()
	_c(s != null, "SummonBase.new() 成功（未触发解析/编译错误）")
	if s != null:
		_c(s.has_method("_perform_attack"),
			"召唤物有攻击方法（额外攻击／暴击都在这里）")
		s.free()


## UI 面板全量加载检查
##
## ## 为什么需要（2026-09-29 加）
##
## 图鉴曾在 `_first_designed(all)` 那里因 `var first := <Variant>` 报
## **解析错误**（`Cannot infer the type ... doesn't have a set type`）——
## 脚本编译不过 → 打开图鉴时游戏直接崩。
##
## 而当时的门禁**全绿**：没有任何套件加载过 `codex_panel.tscn`。
## 「主场景能起来」不等于「每个界面都能打开」——本检查补上这一环。
##
## 判据是**实例化后 `_ready` 真的跑过**（`is_node_ready()`），
## 而不仅是 `load()` 不返回 null——解析错误会让 load 静默返回 null，
## 用 `load()` 判会漏（正是本项目反复踩的「假绿灯」）。
const UI_SCENES := [
	"res://ui/codex/codex_panel.tscn",
	"res://ui/inventory/backpack_ui.tscn",
	"res://ui/inventory/backpack_item.tscn",
	"res://ui/inventory/backpack_menu.tscn",
	"res://scenes/ui/hud.tscn",
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/pause_menu.tscn",
	"res://scenes/ui/settings_panel.tscn",
	"res://scenes/ui/settlement_panel.tscn",
]


func _test_ui_scenes_loadable() -> void:
	print("\n--- UI 面板加载检查 ---")
	for p in UI_SCENES:
		var ps := load(p)
		_c(ps != null, "%s 可加载（解析错误会让它变 null）" % p.get_file(), "load() 返回 null")
		if ps == null:
			continue
		var inst = ps.instantiate()
		_c(inst != null, "%s 可实例化" % p.get_file())
		if inst != null:
			add_child(inst)
			await get_tree().process_frame
			# **关键判据：脚本真的挂上了**。
			#
			# 只查「场景能加载 / 能实例化 / _ready 跑了」**抓不到解析错误**——
			# 实测把 `var first := <Variant>` 那个错加回去，三条断言**全过**：
			# 脚本解析失败时 Godot 让节点**不带脚本**，空 Control 照样
			# 能加载、能实例化、`is_node_ready()` 也为 true。
			# 与 Player 那条同一个教训（那里用的是 `get_script() != null`）。
			var scr = inst.get_script()
			_c(scr != null, "%s 挂着脚本（解析失败时脚本会丢失）" % p.get_file())
			inst.queue_free()
