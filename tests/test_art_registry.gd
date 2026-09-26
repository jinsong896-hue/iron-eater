extends Node
## 美术资源配置测试 —— 验证「用途 → 资源」链路
##
## ## 要回答的问题
##
## 1. 空配置时，查询是否返回空串（消费方走原逻辑，行为不变）？
## 2. `default_profile.tres` 里每条 `model_path` 是否**真的能加载**？
## 3. 热切换后消费方读到新值？
## 4. `DecorationBuilder` 的三级查找是否按顺序生效？
##
## ## 为什么「能加载」的判据是 `load()` 而不是 `ResourceLoader.exists()`
##
## 项目已知陷阱：`.import` 里 `valid=false` 的资源，`exists()` **仍返回
## true** 但 `load()` 返回 null。实测 castle-kit 76 个模型里 30 个如此
## （已在本轮修复）。用 `exists()` 校验会报「全部正常」的假绿灯。

var failed := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 40.0
	guard.timeout.connect(func(): print("ART REGISTRY TESTS FAILED: 超时"); get_tree().quit(1))
	add_child(guard); guard.start()
	await get_tree().process_frame
	await get_tree().process_frame

	EquipmentDB.init_equipment_db()

	_test_empty_profile_returns_empty()
	_test_default_profile_loads()
	_test_registry_hot_swap()
	_test_decoration_three_tier()

	if failed == 0:
		print("ALL ART REGISTRY TESTS PASSED")
		get_tree().quit(0)
	else:
		print("ART REGISTRY TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 1. 空 profile 时所有查询返回空串
##
## 这是**接入安全性的核心**：空配置 = 行为与接入前一致。
## 若这里返回了非空（比如某个默认模型），接入就会悄悄改变画面。
func _test_empty_profile_returns_empty() -> void:
	print("\n--- 空配置返回空串 ---")
	var saved := ArtRegistry.profile()
	ArtRegistry.set_profile(ArtProfile.new())
	_check(ArtRegistry.prop_model("pillar") == "",
		"空配置时 prop_model 返回空串")
	_check(ArtRegistry.prop_model("不存在的用途") == "",
		"未知用途返回空串")
	_check(ArtRegistry.unit_model("zombie") == "", "未配置的单位返回空串")
	_check(ArtRegistry.equipment_model("W01") == "", "未配置的装备返回空串")
	_check(ArtRegistry.effect_scene("hit") == "", "未配置的特效返回空串")
	var t := ArtRegistry.prop_transform("pillar")
	_check(is_equal_approx(float(t["scale"]), 1.0)
			and is_zero_approx(float(t["y_offset"]))
			and is_zero_approx(float(t["y_rotation_deg"])),
		"未配置时变换返回中性值（不缩放/不偏移/不旋转）", [str(t)])
	# 恢复
	ArtRegistry.set_profile(saved)


## 2. `default_profile.tres` 的每条 model_path 真的能加载
##
## **必须用 `load()`**——见文件头说明。
func _test_default_profile_loads() -> void:
	print("\n--- 默认配置的模型可用性 ---")
	ArtRegistry.reload()
	var p := ArtRegistry.profile()
	if p == null:
		_check(false, "default_profile.tres 可加载")
		return
	_check(true, "default_profile.tres 可加载")

	var configured := p.configured_props()
	_check(configured.size() > 0, "至少配置了一个用途", [str(configured)])

	var bad: Array = []
	for k in configured:
		var path := p.prop_model(str(k))
		# **判据是 load()**，不是 ResourceLoader.exists()
		if load(path) == null:
			bad.append("%s → %s" % [k, path])
	_check(bad.is_empty(), "%d 个用途的模型全部可加载" % configured.size(), [str(bad)])

	# `validate()` 自身也应报无问题
	var v := p.validate()
	_check(v.is_empty(), "ArtProfile.validate() 报无问题", [str(v)])


## 3. 热切换：set_profile 后查询立即反映新值
func _test_registry_hot_swap() -> void:
	print("\n--- 热切换 ---")
	var saved := ArtRegistry.profile()

	var a := ArtProfile.new()
	a.set_prop("pillar", "res://assets/castle-kit/Models/GLB format/wall.glb")
	ArtRegistry.set_profile(a)
	_check(ArtRegistry.prop_model("pillar").ends_with("wall.glb"),
		"切换后读到新模型 A")

	var b := ArtProfile.new()
	b.set_prop("pillar", "res://assets/castle-kit/Models/GLB format/rocks-small.glb")
	ArtRegistry.set_profile(b)
	_check(ArtRegistry.prop_model("pillar").ends_with("rocks-small.glb"),
		"再次切换后读到新模型 B")

	# **坏路径必须返回空串**（不能把坏路径透给消费方）
	var c := ArtProfile.new()
	c.set_prop("pillar", "res://不存在的模型.glb")
	ArtRegistry.set_profile(c)
	_check(ArtRegistry.prop_model("pillar") == "",
		"配置了加载不出来的路径时返回空串（消费方走占位）")

	ArtRegistry.set_profile(saved)


## 4. 装饰生成器的三级查找
##
## 1. ArtRegistry 配置的模型
## 2. PROP_PATHS 里的 .tscn
## 3. 程序化占位体
func _test_decoration_three_tier() -> void:
	print("\n--- 装饰三级查找 ---")
	var parent := Node3D.new()
	add_child(parent)

	# 第 1 级：配了模型 → 用模型
	var p := ArtProfile.new()
	p.set_prop("pillar", "res://assets/castle-kit/Models/GLB format/wall-pillar.glb")
	ArtRegistry.set_profile(p)
	DecorationBuilder.build(parent, {"entities": [
		{"type": "pillar", "x": 1, "y": 1},
	]})
	await get_tree().process_frame
	var n1 := parent.get_node_or_null("pillar_1_1")
	_check(n1 != null, "配了模型的用途被生成")
	# 模型实例的 MeshInstance3D 来自 .glb（有 mesh），占位体也有——
	# 区别在占位体的 mesh 是 BoxMesh（pillar 的占位是 0.5×4×0.5 的方块）
	if n1 != null:
		var mesh := _first_mesh(n1)
		_check(mesh != null and not (mesh.mesh is BoxMesh),
			"用的是 castle-kit 模型而非 BoxMesh 占位体",
			["mesh=%s" % (mesh.mesh.get_class() if mesh and mesh.mesh else "null")])

	# 第 2 级：未配模型但有 .tscn → 用 .tscn（chest）
	for c in parent.get_children():
		c.queue_free()
	await get_tree().process_frame
	DecorationBuilder.build(parent, {"entities": [{"type": "chest", "x": 2, "y": 2}]})
	await get_tree().process_frame
	_check(parent.get_node_or_null("chest_2_2") != null,
		"未配模型但有 .tscn 的用途走第二级（chest）")

	# 第 3 级：都没有 → 占位体
	for c in parent.get_children():
		c.queue_free()
	await get_tree().process_frame
	ArtRegistry.set_profile(ArtProfile.new())   # 空配置
	DecorationBuilder.build(parent, {"entities": [{"type": "pillar", "x": 3, "y": 3}]})
	await get_tree().process_frame
	var n3 := parent.get_node_or_null("pillar_3_3")
	_check(n3 != null, "完全未配置的用途仍会生成占位体（画面不会缺东西）")
	if n3 != null:
		var mesh3 := _first_mesh(n3)
		_check(mesh3 != null and mesh3.mesh is BoxMesh,
			"占位体是 BoxMesh（pillar 的占位形状）")

	parent.queue_free()


func _first_mesh(root: Node) -> MeshInstance3D:
	var stack: Array = [root]
	while not stack.is_empty():
		var cur = stack.pop_back()
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			return cur as MeshInstance3D
		for c in cur.get_children():
			stack.append(c)
	return null


func _check(c: bool, name: String, detail: Array = []) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
		for d in detail:
			print("    %s" % d)
