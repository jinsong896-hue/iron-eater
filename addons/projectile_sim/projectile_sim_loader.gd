class_name ProjectileSimLoader
extends RefCounted
## ProjectileSim 加载器 —— 自动在「真扩展」与「GDScript 降级实现」之间选择
##
## 与 `CrowdSimLoader` 同一模式：调用方只用这一个入口，不直接碰 ClassDB。
##
##     var sim := ProjectileSimLoader.create()
##     if sim == null: ...   # 两条路径都不可用（不该发生）

## 是否正在使用真扩展
static var using_extension := false


static func create() -> Node:
	if ClassDB.class_exists("ProjectileSim"):
		using_extension = true
		return ClassDB.instantiate("ProjectileSim")
	using_extension = false
	return ProjectileSimFallback.new()


static func has_extension() -> bool:
	return ClassDB.class_exists("ProjectileSim")


## 当前路径的容量上限（降级路径刻意压到 256）
static func capacity_limit() -> int:
	if has_extension():
		return 4096
	return ProjectileSimFallback.FALLBACK_CAP


static func backend_name() -> String:
	return "GDExtension" if has_extension() else "GDScript fallback"
