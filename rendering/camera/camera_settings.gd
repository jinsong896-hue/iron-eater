class_name CameraSettings
extends RefCounted
## 相机参数配置 —— HD-2D 重构版
## 管理 CameraAttributesPractical（DOF/物理相机参数）

## 创建 HD-2D 相机属性
static func create_hd2d_attributes() -> CameraAttributesPractical:
	var attr := CameraAttributesPractical.new()

	# 景深
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 20.0
	attr.dof_blur_far_transition = 10.0
	attr.dof_blur_near_enabled = true
	attr.dof_blur_near_distance = 2.0
	attr.dof_blur_near_transition = 1.0

	# 自动曝光
	attr.auto_exposure_enabled = true
	attr.auto_exposure_speed = 3.0

	return attr


## 创建默认相机属性
static func create_default_attributes() -> CameraAttributesPractical:
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = false
	attr.dof_blur_near_enabled = false
	attr.auto_exposure_enabled = true
	return attr


## 动态聚焦目标
static func focus_on_target(camera: Camera3D, target: Node3D) -> void:
	if camera == null or target == null:
		return
	var dist: float = camera.global_position.distance_to(target.global_position)
	var attrs := camera.attributes
	if attrs is CameraAttributesPractical:
		(attrs as CameraAttributesPractical).dof_blur_far_distance = dist + 2.0