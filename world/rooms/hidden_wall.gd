class_name HiddenWall
extends Area3D
## 隐藏房破墙入口 —— 关卡设计分册 3.2「隐藏房发现规则」
##
## 策划三种发现方式，本实现合并为「靠近 → 裂缝提示 → 交互破墙」：
##   · 炸开墙壁（消耗炸弹或特殊技能）—— 本项目没有投掷物/炸弹道具，
##     改为**靠近后按 E 破墙**（与宝箱/特殊房同一套交互，操作一致）
##   · 靠近时墙壁出现裂缝 —— 本类的 _process 根据玩家距离切换裂缝视觉
##   · 地图上显示为「？」—— 小地图对 hidden 类型未探索时不显示（见 MinimapView）
##
## 挂在**锚房间**内、贴着隐藏房那一侧的墙上。破墙后把玩家送进隐藏房。
##
## 关于「消耗炸弹」：策划提到需要消耗品，但当前项目没有炸弹道具、
## 也没有对应的消耗品栏位。强制加一个道具会牵动背包/掉落/商店三处，
## 属独立工作量——现按"免费破墙"实现，留 TODO 待消耗品体系补齐后接入。

## 玩家进入此距离内显示裂缝提示（米）
const REVEAL_RANGE := 3.0
## 交互触发距离（米）——比提示距离近，避免隔着墙按 E
const INTERACT_RANGE := 2.0

var target_room_index := -1     ## 破墙后进入的隐藏房索引
var anchor_direction := ""      ## 从锚房间看隐藏房的方位（决定裂缝朝向）
var _revealed := false          ## 是否已进入提示范围
var _broken := false            ## 是否已破墙（防重复触发）
var _crack: MeshInstance3D = null
var _hint_label: Label3D = null


## 在锚房间内创建一个破墙入口
## parent:  锚房间节点（入口挂其下，随房间销毁）
## pos:     入口的世界位置（锚房间与隐藏房共用的墙格）
## room_index: 隐藏房在 dungeon_graph 里的索引
## direction:  从锚房间看隐藏房的方位
static func create(parent: Node3D, pos: Vector3, room_index: int, direction: String) -> HiddenWall:
	var hw := HiddenWall.new()
	hw.name = "HiddenWall"
	hw.target_room_index = room_index
	hw.anchor_direction = direction
	hw.position = pos
	parent.add_child(hw)
	hw._build()
	return hw


func _build() -> void:
	add_to_group("hidden_walls")
	# 不依赖物理回调，靠 _process 轮询距离（与 DamageZone 同思路，更可控）
	monitoring = false
	collision_layer = 0
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 0.6)
	shape.shape = box
	add_child(shape)

	# 裂缝视觉：细长的暗色条（初始不可见，靠近才显）
	_crack = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 2.4)
	_crack.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.04, 0.06, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	_crack.material_override = mat
	# 朝向锚房间内侧（裂缝在墙的玩家这一侧）
	_crack.rotation.y = _facing_rotation()
	add_child(_crack)
	_crack.visible = false

	# 提示文字（靠近时显示，与宝箱/交互物同风格）
	_hint_label = Label3D.new()
	_hint_label.text = "墙壁有裂缝（E 破开）"
	_hint_label.font_size = 40
	_hint_label.position = Vector3(0.0, 1.6, 0.0)
	_hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint_label.no_depth_test = true
	_hint_label.modulate = Color(0.9, 0.85, 0.6)
	_hint_label.outline_size = 8
	add_child(_hint_label)
	_hint_label.visible = false


## 裂缝朝向：让四边形面朝锚房间内部（即隐藏房的反方向）
func _facing_rotation() -> float:
	match anchor_direction:
		"north": return 0.0            # 隐藏房在北，裂缝朝南面（玩家侧）
		"south": return PI
		"west":  return PI * 0.5
		"east":  return -PI * 0.5
	return 0.0


func _process(_delta: float) -> void:
	if _broken:
		return
	var player := _player_node()
	if player == null:
		return
	var d := global_position.distance_to(player.global_position)
	# 策划 3.2：靠近时墙壁出现裂缝
	var should_reveal := d <= REVEAL_RANGE
	if should_reveal != _revealed:
		_revealed = should_reveal
		_crack.visible = should_reveal
		_hint_label.visible = should_reveal


## 玩家是否在交互距离内（供 Player 的 E 键调用）
func can_interact_with(player: Node3D) -> bool:
	if _broken or player == null:
		return false
	return global_position.distance_to(player.global_position) <= INTERACT_RANGE


## 破墙：把玩家送进隐藏房。
## 返回是否成功（成功后本入口失效）。
func break_wall(player: Node3D) -> bool:
	if _broken or player == null:
		return false
	_broken = true
	var gr := _game_root()
	if gr == null or not gr.has_method("_transition_to_room"):
		return false
	# 走正常的切房流程（会加载隐藏房、放置玩家、断开旧房间）
	gr.call("_transition_to_room", target_room_index, anchor_direction)
	return true


func _player_node() -> Node3D:
	var ps := get_tree().get_nodes_in_group("player")
	if ps.is_empty():
		return null
	return ps[0] as Node3D


func _game_root() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var by_name := tree.root.get_node_or_null("GameRoot")
	if by_name != null:
		return by_name
	# 测试场景把 main.tscn 嵌在别的父节点下，按特征属性回退查找
	var scene := tree.current_scene
	if scene != null:
		return _find_game_root(scene)
	return null


func _find_game_root(node: Node) -> Node:
	if node.get("dungeon_graph") != null:
		return node
	for child in node.get_children():
		var hit: Node = _find_game_root(child)
		if hit != null:
			return hit
	return null
