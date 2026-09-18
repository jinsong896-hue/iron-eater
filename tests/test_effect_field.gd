extends Node
## 特效池 —— 行为与池化不变量回归
##
## 覆盖 `EffectField` 的核心承诺：
##   ① **节点数不随播放次数增长**（池化的本质）
##   ② 播放后能归还（不是只借不还）
##   ③ 超过池上限时复用最旧的，而不是无限新建
##   ④ 未知类型有兜底（不崩）
##
## ## 为什么这条最要紧
## 池化优化最容易"看起来做了但没生效"——比如归还路径没接上，
## 结果是"借出去的永远不还"，节点数照旧线性增长，性能一点没改善。
## 所以要断言的不是"有池这个类"，而是**节点总数被钉死在池上限**。
##
## 运行：godot --headless --path . res://tests/test_effect_field.tscn

var failed := 0


func _ready() -> void:
	await get_tree().process_frame
	await _test_play_and_recycle()
	await _test_pool_cap()
	_test_unknown_kind()
	_test_presets_complete()

	if failed == 0:
		print("ALL EFFECT FIELD TESTS PASSED")
		get_tree().quit(0)
	else:
		print("EFFECT FIELD TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 播放 → 到期归还 → 复用（节点数不增长）
func _test_play_and_recycle() -> void:
	var field := EffectField.new()
	add_child(field)
	_check(field.play("hit", Vector3.ZERO), "播放 hit 特效成功")
	_check(field.play_count() == 1, "播放计数递增")
	var st := field.pool_state("hit")
	_check(int(st["live"]) == 1, "播放后 1 个发射器处于活跃（%d）" % st["live"])
	_check(int(st["total"]) == 1, "池里共 1 个发射器（%d）" % st["total"])

	# 等过 lifetime + 兜底延时，应归还
	await get_tree().create_timer(1.0, true, false, true).timeout
	st = field.pool_state("hit")
	_check(int(st["live"]) == 0, "到期后归还（活跃 %d）" % st["live"])
	_check(int(st["free"]) == 1, "归还到空闲池（空闲 %d）" % st["free"])

	# 播放 → 等归还 → 再播，循环 10 轮：节点总数不该增长。
	#
	# **注意不能连播不等归还**：那样是 10 个**同时活跃**的特效，
	# 物理上就需要 10 个发射器（一个发射器不可能同时播两个位置）。
	# 池化的不变量是"串行复用不增长"，不是"并发也不增长"。
	for i in 10:
		field.play("hit", Vector3.ZERO)
		await get_tree().create_timer(0.8, true, false, true).timeout
	_check(field.total_emitters() == 1,
		"串行播放 10 轮后节点总数仍是 1（实际 %d）——池化生效" % field.total_emitters())
	_check(field.play_count() == 11, "累计播放 11 次（1 + 循环 10，实际 %d）" % field.play_count())
	field.queue_free()


## 超过池上限时复用最旧的，而不是无限新建
func _test_pool_cap() -> void:
	var field := EffectField.new()
	add_child(field)
	# 一次播满 + 超出（不等待归还，全部同时活跃）
	var n := EffectField.POOL_PER_KIND + 20
	for i in n:
		field.play("death", Vector3(float(i), 0, 0))
	_check(field.total_emitters() == EffectField.POOL_PER_KIND,
		"节点数被钉在池上限 %d（实际 %d）" % [EffectField.POOL_PER_KIND, field.total_emitters()])
	var st := field.pool_state("death")
	_check(int(st["live"]) == EffectField.POOL_PER_KIND,
		"全部发射器都在活跃态（%d）" % st["live"])
	field.queue_free()


## 未知类型走兜底预设，不崩
func _test_unknown_kind() -> void:
	var field := EffectField.new()
	add_child(field)
	var ok := field.play("no_such_kind", Vector3.ZERO)
	_check(ok, "未知特效类型有兜底（不崩）")
	field.queue_free()


## 预设表完整性：每种预设都要有关键字段，否则建出来的发射器参数缺失
func _test_presets_complete() -> void:
	for kind in EffectField.PRESETS:
		var p: Dictionary = EffectField.PRESETS[kind]
		var missing: Array = []
		for key in ["amount", "lifetime", "speed", "spread", "gravity", "size"]:
			if not p.has(key):
				missing.append(key)
		_check(missing.is_empty(),
			"预设 %s 字段完整%s" % [kind, ("（缺 %s）" % str(missing)) if not missing.is_empty() else ""])
	# 群体死亡预设的粒子数必须**明显低于**普通死亡——
	# 它可能同时几百个触发，粒子数不减会把 GPU 预算吃满
	var swarm := int((EffectField.PRESETS["swarm_death"] as Dictionary)["amount"])
	var normal := int((EffectField.PRESETS["death"] as Dictionary)["amount"])
	_check(swarm < normal,
		"群体死亡粒子数低于普通死亡（%d < %d）——防同屏爆量" % [swarm, normal])


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
