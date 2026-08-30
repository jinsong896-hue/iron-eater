class_name LightingManager
extends RefCounted
## 光照管理器 —— HD-2D 重构版
## 管理场景光照配置

## 创建 HD-2D 默认光照设置
static func setup_default_lighting(parent: Node3D) -> void:
	# 主方向光（太阳）
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-45.0, 45.0, 0.0)
	sun.light_energy = 2.0
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.1
	sun.directional_shadow_split_2 = 0.3
	sun.directional_shadow_split_3 = 0.6
	parent.add_child(sun)

	# 环境光
	var ambient := DirectionalLight3D.new()
	ambient.name = "AmbientLight"
	ambient.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	ambient.light_energy = 0.3
	ambient.light_color = Color(0.4, 0.5, 0.7)
	ambient.shadow_enabled = false
	parent.add_child(ambient)


## 创建火把光源
static func create_torch_light(parent: Node3D, position: Vector3) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "TorchLight"
	light.position = position
	light.light_energy = 1.5
	light.light_color = Color(1.0, 0.7, 0.3)
	light.omni_range = 5.0
	light.shadow_enabled = false
	# 闪烁效果
	var tween := light.create_tween()
	tween.set_loops()
	tween.tween_property(light, "light_energy", 1.2, 0.1 + randf() * 0.2)
	tween.tween_property(light, "light_energy", 1.5, 0.1 + randf() * 0.2)
	parent.add_child(light)
	return light


## 创建窗户光（SpotLight）
static func create_window_light(parent: Node3D, position: Vector3, direction: Vector3) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = "WindowLight"
	light.position = position
	light.rotation = direction
	light.light_energy = 2.0
	light.light_color = Color(0.8, 0.85, 1.0)
	light.spot_range = 8.0
	light.spot_angle = 30.0
	light.shadow_enabled = false
	parent.add_child(light)
	return light