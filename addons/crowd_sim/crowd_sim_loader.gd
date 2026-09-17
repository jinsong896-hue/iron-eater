class_name CrowdSimLoader
extends RefCounted
## CrowdSim 加载器 —— 自动在「真扩展」与「GDScript 降级实现」之间选择
##
## 调用方**只用这一个入口**，不直接碰 ClassDB：
##
##     var crowd := CrowdSimLoader.create()
##     if crowd == null: ...   # 两条路径都不可用（不该发生）
##
## 为什么要有这层：C++ 扩展要编译产物，CI / 新克隆的机器上没有。
## 若调用方直接 `ClassDB.instantiate("CrowdSim")`，那些环境会拿到 null
## 并连锁崩掉房间生成与命中判定——门禁只能整片 SKIP，"测不到"等于没有防线。
##
## 降级路径是**纯 GDScript**，慢但对；逻辑正确性照样能测。

## 是否正在使用真扩展（性能测试与"慢路径"提示用）
static var using_extension := false


## 创建一个 CrowdSim 实例（真扩展优先，否则降级实现）。
## 返回 Node；两者都不可用时返回 null（调用方需判空）。
static func create() -> Node:
	if ClassDB.class_exists("CrowdSim"):
		using_extension = true
		return ClassDB.instantiate("CrowdSim")
	using_extension = false
	return CrowdSimFallback.new()


## 是否有真扩展（供 UI 提示"当前跑在慢路径上"）
static func has_extension() -> bool:
	return ClassDB.class_exists("CrowdSim")


## 当前路径的容量上限。降级路径刻意压到 200——
## GDScript 逐帧遍历 200 个实体已接近脚本层上限，再大就该编译扩展了。
static func capacity_limit() -> int:
	if has_extension():
		return 2048
	return CrowdSimFallback.FALLBACK_CAP


## 人类可读的路径名（日志/UI 用）
static func backend_name() -> String:
	return "GDExtension" if has_extension() else "GDScript fallback"
