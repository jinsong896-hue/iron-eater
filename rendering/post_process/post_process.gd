class_name PostProcess
extends RefCounted
## 后处理管理 —— HD-2D 重构版
## 统一管理 WorldEnvironment 的 Fog/Glow/SSAO/Color 等后期效果

## 应用 HD-2D 默认后处理设置
static func apply_hd2d_settings(env: Environment) -> void:
	if env == null:
		return

	# 雾
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 0.02
	env.fog_height = 0.0
	env.fog_height_density = 0.0
	env.fog_light_color = Color(0.3, 0.35, 0.5)
	env.fog_sun_scatter = 0.0

	# 泛光
	env.glow_enabled = true
	env.glow_levels[1] = 1.0
	env.glow_levels[2] = 0.0
	env.glow_levels[3] = 0.0
	env.glow_levels[4] = 0.4
	env.glow_levels[5] = 0.0
	env.glow_levels[6] = 0.0
	env.glow_levels[7] = 0.0
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_bleed_threshold = 1.0
	env.glow_hdr_bleed_scale = 2.0

	# SSAO
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.0
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98

	# 色调映射
	env.tonemap_mode = Environment.TONE_MAPPER_ACES

	# 色彩调整
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 0.9

	# 环境光
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.15, 0.15, 0.2)
	env.ambient_light_energy = 0.5


## 创建 HD-2D Environment 资源
static func create_hd2d_environment() -> Environment:
	var env := Environment.new()
	apply_hd2d_settings(env)
	return env


## 禁用所有后处理（调试用）
static func disable_all(env: Environment) -> void:
	if env == null:
		return
	env.fog_enabled = false
	env.glow_enabled = false
	env.ssao_enabled = false
	env.adjustment_enabled = false