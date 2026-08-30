extends Node3D
## 像素后处理渲染器 —— HD-2D 重构版
## 将 3D 画面转为 2.5D 像素风格
## 挂在 Camera3D 下，作为全屏后处理

@export var enabled := true
@export var pixel_size := 2.0          # 像素化程度
@export var light_intensity := 1.25    # 光照强度
@export var line_alpha := 0.7          # 线条透明度
@export var line_highlight := 0.2      # 高光强度
@export var line_shadow := 0.55        # 阴影强度
@export var use_lighting := true

var _quad: MeshInstance3D
var _material: ShaderMaterial


func _ready() -> void:
	_setup_post_process()


func _setup_post_process() -> void:
	# 创建全屏四边形
	_quad = MeshInstance3D.new()
	_quad.name = "PostProcessQuad"
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0)
	_quad.mesh = quad_mesh

	# 加载着色器
	var shader := load("res://shaders/pixel_post_process.gdshader")
	if shader == null:
		push_error("PixelRenderer: failed to load shader")
		return

	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("lightIntensity", light_intensity)
	_material.set_shader_parameter("lineAlpha", line_alpha)
	_material.set_shader_parameter("lineHighlight", line_highlight)
	_material.set_shader_parameter("lineShadow", line_shadow)
	_material.set_shader_parameter("useLighting", use_lighting)

	_quad.material_override = _material
	add_child(_quad)

	# 放在相机前方
	_quad.position = Vector3(0, 0, -1.0)


func _process(_delta: float) -> void:
	if _quad:
		_quad.visible = enabled