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


## 应用主题环境
func apply_theme(theme_id: String) -> void:
	ThemeLibrary.set_theme(theme_id)
	var theme := ThemeLibrary.get_current()
	if theme.is_empty():
		return

	if _environment:
		_environment.fog_light_color = theme.get("fog_color", Color.WHITE)
		_environment.ambient_light_color = theme.get("ambient_color", Color.WHITE)