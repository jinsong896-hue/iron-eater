class_name SpawnRegistry
extends RefCounted
## 表现层工厂的**注册表** —— 让逻辑层不必 `load()` 表现层。
##
## ## 为什么需要它
##
## 分层约定是「逻辑层（gameplay/）不依赖表现层（entities/ / world/）」。
## 但逻辑层在生成实体时天然需要知道"怎么造一个敌人"，
## 于是出现了这类写法：
##
## ```gdscript
## var bm_script = load("res://entities/enemies/boss_mechanics.gd")
## if bm_script != null:
##     room._boss.boss_mech = bm_script.attach(room._boss, boss_def)
## ```
##
## 两个问题：
## 1. **依赖方向反了**：`gameplay/dungeon/spawn_director.gd` 直接引用
##    `entities/enemies/` 下的脚本。逻辑层从此无法脱离表现层单测。
## 2. **失败是静默的**：`load()` 返回 null 时那个 `if` 只是跳过——
##    Boss 少了整块机制，不报错、不警告，看起来像"这个 Boss 本来就没机制"。
##
## 注册表把这两点一起解决：表现层在启动时**注册**自己的工厂，
## 逻辑层按 key 取；取不到时 `push_warning` 点名（不再静默）。
##
## ## 用法
##
## 表现层（或装配层，如 `game_root.gd`）启动时：
## ```gdscript
## SpawnRegistry.register("boss_mechanics", func(target, def):
##     return BossMechanics.attach(target, def))
## ```
##
## 逻辑层：
## ```gdscript
## var mech = SpawnRegistry.create("boss_mechanics", [boss, boss_def])
## ```
##
## ## 为什么注册在 game_root 而不是各自 `_ready`
##
## 项目小、注册点少（当前只有 1 个），集中注册比散布自注册直观：
## 一眼能看全"哪些工厂被接上了"。将来注册项变多再考虑自注册。

## key → Callable。Callable 接收 args 数组，返回工厂产物。
static var _factories: Dictionary = {}


## 注册一个工厂。重复注册同一 key 会覆盖（便于测试替换替身）。
static func register(key: String, factory: Callable) -> void:
	_factories[key] = factory


## 注销（测试清理用）
static func unregister(key: String) -> void:
	_factories.erase(key)


## 调用工厂。未注册或调用失败时 `push_warning` 并返回 null。
##
## **警告而非静默**是刻意的：本项目反复出现"不崩溃、不报错、只是什么都不发生"
## 的缺陷（见 PROGRESS 的音效链路、门重入等）。工厂缺失属于配置错误，
## 必须能被看见。
static func create(key: String, args: Array = []) -> Variant:
	if not _factories.has(key):
		push_warning("SpawnRegistry：未注册的工厂 '%s'（调用方期望它存在）" % key)
		return null
	var f: Callable = _factories[key]
	if not f.is_valid():
		push_warning("SpawnRegistry：工厂 '%s' 的 Callable 已失效" % key)
		return null
	return f.callv(args)


## 该 key 是否已注册（供测试断言装配完整性）
static func has_factory(key: String) -> bool:
	return _factories.has(key)


## 已注册的 key 列表（供启动自检 / WiredCheck 打印）
static func registered_keys() -> Array:
	return _factories.keys()
