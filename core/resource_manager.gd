extends Node
## 资源管理器 —— HD-2D 重构版
## 统一资源加载/缓存，避免到处 preload()
## 支持按主题切换资源映射

# 资源缓存
var _cache: Dictionary = {}

# 主题资源映射表
var _theme_maps := {
	"crypt": {
		"floor": "res://assets/textures/floors/stone_gray.png",
		"wall": "res://assets/textures/walls/stone_wall.png",
	},
	"hell": {
		"floor": "res://assets/textures/floors/lava.png",
		"wall": "res://assets/textures/walls/demon_wall.png",
	},
	"ice": {
		"floor": "res://assets/textures/floors/ice.png",
		"wall": "res://assets/textures/walls/ice_wall.png",
	},
}

var _current_theme := "crypt"


## 加载并缓存资源
func load_resource(path: String, type_hint: String = "") -> Resource:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		push_warning("ResourceManager: resource not found: %s" % path)
		return null
	var res: Resource
	if type_hint.is_empty():
		res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	else:
		res = ResourceLoader.load(path, type_hint, ResourceLoader.CACHE_MODE_REUSE)
	if res:
		_cache[path] = res
	return res


## 加载场景
func load_scene(path: String) -> PackedScene:
	var scene: PackedScene = load_resource(path, "PackedScene") as PackedScene
	return scene


## 加载贴图
func load_texture(path: String) -> Texture2D:
	var tex := load_resource(path, "Texture2D") as Texture2D
	return tex


## 切换主题
func set_theme(theme_id: String) -> void:
	if _theme_maps.has(theme_id):
		_current_theme = theme_id


## 获取当前主题下的资源路径
func get_themed_path(resource_type: String) -> String:
	var theme: Dictionary = _theme_maps.get(_current_theme, {})
	return theme.get(resource_type, "")


## 清除缓存
func clear_cache() -> void:
	_cache.clear()


## 预加载常用资源
func preload_common() -> void:
	# 预加载地板、墙壁等常用资源
	load_scene("res://scenes/world/floor_tile.tscn")
	load_scene("res://scenes/world/wall_segment.tscn")
	load_scene("res://scenes/props/door.tscn")