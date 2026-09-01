extends Node3D
## 宝箱实体 —— treasure 房可交互掉落（金币 + 装备）
## 走近自动开箱（一次性），掉落由 LootSystem 处理

var is_opened := false
var gold_min := 20
var gold_max := 50

var _lid: MeshInstance3D = null
var _body: MeshInstance3D = null


func _ready() -> void:
	_build_visual()
	var area := get_node_or_null("InteractArea") as Area3D
	if area:
		area.body_entered.connect(_on_body_entered)


## 宝箱视觉（脚本构建：箱体 + 盖子，木色金属边）
func _build_visual() -> void:
	_body = MeshInstance3D.new()
	_body.name = "Body"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.0, 0.6, 0.7)
	_body.mesh = body_mesh
	_body.position = Vector3(0, 0.3, 0)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.45, 0.3, 0.15)
	body_mat.emission_enabled = true
	body_mat.emission = Color(0.9, 0.7, 0.2)
	body_mat.emission_energy_multiplier = 0.15  # 微光提示可交互
	_body.material_override = body_mat
	add_child(_body)

	_lid = MeshInstance3D.new()
	_lid.name = "Lid"
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.05, 0.15, 0.75)
	_lid.mesh = lid_mesh
	_lid.position = Vector3(0, 0.68, -0.33)
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.55, 0.4, 0.2)
	lid_mat.emission_enabled = true
	lid_mat.emission = Color(0.9, 0.7, 0.2)
	lid_mat.emission_energy_multiplier = 0.25
	_lid.material_override = lid_mat
	add_child(_lid)


## 玩家靠近自动开箱
func _on_body_entered(body: Node3D) -> void:
	if is_opened:
		return
	if not body.is_in_group("player"):
		return
	open_chest()


## 开箱：金币入账 + 装备掉落 + 视觉变化
func open_chest() -> void:
	if is_opened:
		return
	is_opened = true

	var tree := Engine.get_main_loop() as SceneTree
	var gm = tree.root.get_node_or_null("GameManager") if tree and tree.root else null
	var bus = tree.root.get_node_or_null("EventBus") if tree and tree.root else null

	# 金币直接入账
	var gold := randi_range(gold_min, gold_max)
	if gm:
		gm.gold += gold
	if bus:
		bus.gold_changed.emit(gm.gold if gm else gold)
		bus.message.emit("宝箱：金币 +%d" % gold)

	# 装备掉落（宝箱必掉一件，走 LootSystem 白装池）
	if gm and get_parent() != null:
		var loot := LootSystem.new()
		loot.generate_chest_loot(global_position, get_parent(), 1)

	_open_visual()


## 宝箱视觉：盖子打开 + 发光
func _open_visual() -> void:
	if _lid:
		var tween := create_tween()
		tween.tween_property(_lid, "rotation:x", -1.2, 0.25)
		tween.parallel().tween_property(_lid, "position:y", 0.85, 0.25)
	if _body:
		var mat := _body.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 0.6
