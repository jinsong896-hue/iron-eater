class_name ThemeLibrary
extends RefCounted
## 主题库 —— HD-2D 重构版
## 管理地牢主题的美术资源映射
## 同一房间蓝图可切换不同主题，实现换皮

# 主题定义
static var _themes := {
	"crypt": {
		"name": "墓穴",
		"floor_color": Color(0.25, 0.25, 0.3),
		"wall_color": Color(0.2, 0.2, 0.25),
		"ambient_color": Color(0.1, 0.1, 0.15),
		"fog_color": Color(0.15, 0.15, 0.25),
		"light_color": Color(0.3, 0.5, 1.0),
		"torch_color": Color(0.3, 0.5, 1.0),
	},
	"hell": {
		"name": "地狱",
		"floor_color": Color(0.3, 0.15, 0.1),
		"wall_color": Color(0.25, 0.1, 0.05),
		"ambient_color": Color(0.15, 0.05, 0.02),
		"fog_color": Color(0.2, 0.05, 0.0),
		"light_color": Color(1.0, 0.3, 0.1),
		"torch_color": Color(1.0, 0.4, 0.1),
	},
	"ice": {
		"name": "冰洞",
		"floor_color": Color(0.6, 0.7, 0.8),
		"wall_color": Color(0.5, 0.6, 0.7),
		"ambient_color": Color(0.2, 0.25, 0.3),
		"fog_color": Color(0.5, 0.6, 0.7),
		"light_color": Color(0.5, 0.7, 1.0),
		"torch_color": Color(0.5, 0.7, 1.0),
	},
	"forest": {
		"name": "森林",
		"floor_color": Color(0.2, 0.4, 0.15),
		"wall_color": Color(0.15, 0.3, 0.1),
		"ambient_color": Color(0.1, 0.15, 0.05),
		"fog_color": Color(0.15, 0.25, 0.1),
		"light_color": Color(0.3, 0.8, 0.3),
		"torch_color": Color(0.4, 0.8, 0.3),
	},
}

static var _current_theme := "crypt"


## 切换主题
static func set_theme(theme_id: String) -> void:
	if _themes.has(theme_id):
		_current_theme = theme_id


## 获取当前主题数据
static func get_current() -> Dictionary:
	return _themes.get(_current_theme, {})


## 获取指定主题属性
static func get_color(key: String) -> Color:
	var theme := get_current()
	return theme.get(key, Color.WHITE)


## 获取所有主题名称
static func get_theme_list() -> Array:
	var result: Array = []
	for key in _themes:
		result.append({"id": key, "name": _themes[key].get("name", key)})
	return result


## 获取地下城主题地板材质
static func get_floor_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = get_color("floor_color")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	return mat


## 获取墙壁材质
static func get_wall_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = get_color("wall_color")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	return mat