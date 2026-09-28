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
