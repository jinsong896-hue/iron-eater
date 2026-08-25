class_name CharacterRenderer
extends Node2D
## 2.5D 像素化角色渲染器
## 将 3D 角色模型放入 SubViewport 渲染，输出像素化 2D 画面

@export_category("Resolution")
@export var render_size := Vector2i(256, 256)
@export var pixel_scale := 4.0
@export var color_limit := 32

@export_category("Camera")
@export var camera_angle := Vector3(-25.0, 0, 0)
@export var camera_distance := 5.0
@export var ortho_size := 3.0

@export_category("Model")
@export var character_model: PackedScene

var _viewport: SubViewport
var _viewport_container: SubViewportContainer
var _texture_rect: TextureRect
var _camera: Camera3D
var _model_instance: Node3D
var _bone_map: Dictionary = {}

var weapon_slot: Node3D
var helmet_slot: Node3D
var armor_slot: Node3D
var back_slot: Node3D


func _ready() -> void:
	_setup_viewport()
	_setup_camera()
	_setup_light()
	_setup_texture()
	if character_model:
		_setup_model(character_model)


func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = render_size
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = false
	add_child(_viewport)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ortho_size
	_camera.position = Vector3(0, camera_distance * sin(deg_to_rad(-camera_angle.x)), camera_distance)
	_camera.look_at(Vector3(0, 1.5, 0))
	_viewport.add_child(_camera)


func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = false
	_viewport.add_child(sun)

	var ambient := DirectionalLight3D.new()
	ambient.rotation_degrees = Vector3(0, 180, 0)
	ambient.light_energy = 0.3
	ambient.shadow_enabled = false
	_viewport.add_child(ambient)


func _setup_texture() -> void:
	_texture_rect = TextureRect.new()
	_texture_rect.texture = _viewport.get_texture()
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.custom_minimum_size = Vector2(render_size) * pixel_scale / 4.0
	_texture_rect.material = ShaderMaterial.new()
	_texture_rect.material.shader = load("res://shaders/pixelize.gdshader")
	_texture_rect.material.set_shader_parameter("pixel_size", pixel_scale)
	_texture_rect.material.set_shader_parameter("color_count", color_limit)
	add_child(_texture_rect)


func _setup_model(scene: PackedScene) -> void:
	if _model_instance:
		_model_instance.queue_free()
	_model_instance = scene.instantiate()
	_viewport.add_child(_model_instance)
	_find_bones(_model_instance)
	_create_slots()


func _find_bones(node: Node) -> void:
	for child in node.get_children():
		var bone_name := child.name.to_lower()
		if bone_name.find("hand") >= 0 or bone_name.find("weapon") >= 0:
			weapon_slot = child as Node3D
		elif bone_name.find("head") >= 0 or bone_name.find("helmet") >= 0:
			helmet_slot = child as Node3D
		elif bone_name.find("spine") >= 0 or bone_name.find("chest") >= 0:
			armor_slot = child as Node3D
		elif bone_name.find("back") >= 0:
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
	var mesh := res.instantiate() if res is PackedScene else null
	if mesh: slot.add_child(mesh)


func set_model(scene: PackedScene) -> void:
	_setup_model(scene)


func play_animation(anim_name: String) -> void:
	if _model_instance and _model_instance.has_method("play_animation"):
		_model_instance.play_animation(anim_name)
