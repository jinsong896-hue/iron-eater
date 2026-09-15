class_name WorldEnvironmentManager
extends Node
## 世界环境管理器 —— HD-2D 重构版
## 管理 WorldEnvironment 节点和 Environment 资源

@export var world_environment: WorldEnvironment

var _environment: Environment


func _ready() -> void:
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		world_environment.name = "WorldEnvironment"
		get_parent().add_child(world_environment)

	_environment = world_environment.environment
	if _environment == null:
		_environment = Environment.new()
		world_environment.environment = _environment

	# 应用默认 HD-2D 设置
	PostProcess.apply_hd2d_settings(_environment)


## 获取 Environment 资源
func get_environment() -> Environment:
	return _environment


## 设置雾的颜色
func set_fog_color(color: Color) -> void:
	if _environment:
		_environment.fog_light_color = color


## 设置雾的密度
func set_fog_density(density: float) -> void:
	if _environment:
		_environment.fog_density = density


## 启用/禁用 SSAO
func set_ssao(enabled: bool) -> void:
	if _environment:
		_environment.ssao_enabled = enabled


## 设置泛光强度
func set_glow_intensity(intensity: float) -> void:
	if _environment:
		_environment.glow_intensity = intensity


## 应用主题环境（按 ThemeLibrary 的 4 套通用主题）。
## 注意：楼层系统用的是 FloorDefs 的 9 层主题，走 apply_floor()。
## 本方法保留给非楼层场景（编辑器预览等）。
func apply_theme(theme_id: String) -> void:
	ThemeLibrary.set_theme(theme_id)
	var theme := ThemeLibrary.get_current()
	if theme.is_empty():
		return

	if _environment:
		_environment.fog_light_color = theme.get("fog_color", Color.WHITE)
		_environment.ambient_light_color = theme.get("ambient_color", Color.WHITE)


## 按**楼层**应用主题环境（FloorDefs 的 9 层配色）。
## 由 GameRoot 在生成地牢时调用——每层雾色/环境光各不相同，
## 配合房间地板墙配色一起构成该层的视觉主题。
func apply_floor(floor_num: int) -> void:
	if _environment == null:
		return
	_environment.fog_light_color = FloorDefs.color_of(floor_num, "fog")
	_environment.ambient_light_color = FloorDefs.color_of(floor_num, "ambient")
	# 环境光强度：偏暗的层（虚空/裂隙）压暗，明亮层（熔炉/王座）提亮
	var amb := FloorDefs.color_of(floor_num, "ambient")
	var lum := (amb.r + amb.g + amb.b) / 3.0
	_environment.ambient_light_energy = clampf(0.4 + lum * 1.2, 0.3, 0.9)