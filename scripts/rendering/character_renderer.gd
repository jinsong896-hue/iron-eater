class_name CharacterRenderer
extends Node2D
## 2.5D 像素化角色渲染管线
## 工作流：3D模型(卡通材质) → SubViewport → 后处理Shader → 像素化输出 → 12fps手绘效果

@export_category("Resolution")
@export var render_size := Vector2i(256, 256)
@export var target_fps := 12

@export_category("Camera")
@export var camera_angle := Vector3(-25.0, 0, 0)
@export var camera_distance := 5.0
@export var ortho_size := 3.0

@export_category("Model")
@export var character_model: PackedScene

var _viewport: SubViewport
var _texture_rect: TextureRect
var _camera: Camera3D
var _model_instance: Node3D
var _frame_timer: Timer
var _frame_count := 0
var _post_process_mesh: MeshInstance3D

var weapon_slot: Node3D
var helmet_slot: Node3D
var armor_slot: Node3D
var back_slot: Node3D


func _ready() -> void:
	_setup_viewport()
	_setup_camera()
	_setup_light()
	_setup_post_process()
	_setup_texture()
	_setup_frame_timer()
	if character_model:
		_setup_model(character_model)


func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = render_size
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.disable_3d = false
	add_child(_viewport)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ortho_size
	var rad_x := deg_to_rad(camera_angle.x)
	_camera.position = Vector3(0, camera_distance * sin(-rad_x), camera_distance * cos(-rad_x))
	_camera.look_at(Vector3(0, 1.5, 0))
	_viewport.add_child(_camera)


func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = false
	_viewport.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(0, 180, 0)
	fill.light_energy = 0.3
	fill.shadow_enabled = false
	_viewport.add_child(fill)


func _setup_post_process() -> void:
	# 全屏四边形用于后处理 Shader
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_post_process_mesh = MeshInstance3D.new()
	_post_process_mesh.mesh = quad
	_post_process_mesh.position = Vector3(0, 0, -1)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pixel_post_process.gdshader")
	_post_process_mesh.material_override = mat
	_viewport.add_child(_post_process_mesh)


func _setup_texture() -> void:
	_texture_rect = TextureRect.new()
	_texture_rect.texture = _viewport.get_texture()
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.custom_minimum_size = Vector2(render_size) / 4.0
	add_child(_texture_rect)


func _setup_frame_timer() -> void:
	_frame_timer = Timer.new()
	_frame_timer.wait_time = 1.0 / target_fps
	_frame_timer.timeout.connect(_on_frame_tick)
	_frame_timer.autostart = true
	add_child(_frame_timer)


func _on_frame_tick() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_frame_count += 1


func _setup_model(scene: PackedScene) -> void:
	if _model_instance:
		_model_instance.queue_free()
	_model_instance = scene.instantiate()
	_apply_toon_material(_model_instance)
	_viewport.add_child(_model_instance)
	# 把模型放在后处理四边形前面
	_viewport.move_child(_model_instance, _viewport.get_child_count() - 2)
	_find_bones(_model_instance)
	_create_slots()


func _apply_toon_material(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := ShaderMaterial.new()
			mat.shader = load("res://shaders/toon_material.gdshader")
			mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_toon_material(child)


func _find_bones(node: Node) -> void:
	for child in node.get_children():
		var bn := child.name.to_lower()
		if bn.find("hand") >= 0 or bn.find("weapon") >= 0:
			weapon_slot = child as Node3D
		elif bn.find("head") >= 0 or bn.find("helmet") >= 0:
			helmet_slot = child as Node3D
		elif bn.find("spine") >= 0 or bn.find("chest") >= 0:
			armor_slot = child as Node3D
		elif bn.find("back") >= 0:
			back_slot = child as Node3D
		_find_bones(child)


func _create_slots() -> void:
	if not weapon_slot:
		weapon_slot = Node3D.new(); weapon_slot.name = "WeaponSlot"
		_model_instance.add_child(weapon_slot)
	if not helmet_slot:
		helmet_slot = Node3D.new(); helmet_slot.name = "HelmetSlot"
		_model_instance.add_child(helmet_slot)
	if not armor_slot:
		armor_slot = Node3D.new(); armor_slot.name = "ArmorSlot"
		_model_instance.add_child(armor_slot)
	if not back_slot:
		back_slot = Node3D.new(); back_slot.name = "BackSlot"
		_model_instance.add_child(back_slot)


func equip_weapon(model_path: String) -> void:
	_equip_to_slot(weapon_slot, model_path)


func equip_helmet(model_path: String) -> void:
	_equip_to_slot(helmet_slot, model_path)


func equip_armor(model_path: String) -> void:
	_equip_to_slot(armor_slot, model_path)


func _equip_to_slot(slot: Node3D, model_path: String) -> void:
	if slot == null or model_path.is_empty(): return
	for child in slot.get_children(): child.queue_free()
	var res := load(model_path)
	if res == null: return
	if res is PackedScene:
		var mesh: Node = res.instantiate()
		_apply_toon_material(mesh)
		slot.add_child(mesh)


func set_model(scene: PackedScene) -> void:
	_setup_model(scene)


func play_animation(anim_name: String) -> void:
	if _model_instance and _model_instance.has_method("play_animation"):
		_model_instance.play_animation(anim_name)
ENDOFFILE