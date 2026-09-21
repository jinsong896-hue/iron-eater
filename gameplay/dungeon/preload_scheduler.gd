class_name PreloadScheduler
extends Node
## 房间预建调度 —— 把整层房间的构建成本挪到玩家看不见的时机。
##
## ## 为什么需要预建
##
## 实测单间构建 3.12ms + 入树 0.14ms。切房时同步构建会让玩家可感知地卡一下
##（真实 GPU 上材质首次编译更贵，收益更大）。预建把这段压到约 1/35。
##
## 两种节奏：
## · `preload_all()` —— **一次性建完整层**。给开场动画 / 切层传送特效期间用：
##   那时没有别的事在做，一次建完最划算。
## · `preload_step()` —— 每帧建 1 间。兜底补齐（正常路径用不到）。
##
## ## 字段归属
##
## `_room_cache` / `_preload_cursor` / `_preload_built` / `_preload_usec`
## **留在 GameRoot**：`load_current_room()` 要读缓存取出已建好的房间直接挂载
##（这是预建收益的兑现点）。故本组件按 `root.xxx` 访问。

## 宿主 GameRoot（构造时注入）
var root: Node = null

## 每帧预建房间数。1 间 ≈ 7ms；分散到帧里仍有微顿，
## 故只在**开场动画尚未覆盖**或缓存已空时才有意义——
## 正常情况下由 preload_all() 在动画期间一次建完，这里兜底补齐。
const PRELOAD_PER_FRAME := 1


## 装配：注入宿主 GameRoot
func setup(owner_root: Node) -> void:
	root = owner_root

## 逐帧 1 间 ≈ 7ms，放在游戏进行中会占掉一帧预算的四成、造成微顿；
## 开场动画期间没有别的事在做，一次建完最划算。
## 返回本次新建的房间数。
func preload_all() -> int:
	if not root.dungeon_generated:
		return 0
	var built := 0
	while root._preload_cursor < root.dungeon_graph.size():
		var i: int = root._preload_cursor
		root._preload_cursor += 1
		if i == root.current_room_index or root._room_cache.has(i):
			continue
		var t0 := Time.get_ticks_usec()
		var node: Node3D = root._build_room(i)
		root._preload_usec += Time.get_ticks_usec() - t0
		if node != null:
			root._room_cache[i] = node
			root._preload_built += 1
			built += 1
	return built


## 每帧预建房间数。1 间 ≈ 7ms；分散到帧里仍有微顿，
## 故只在**开场动画尚未覆盖**或缓存已空时才有意义——


## 增量预加载：每帧建少量房间，直到整层建完。



## 整层生成是否在策划预算内（总册 11.8：单房间加载 < 1 秒）
## 返回 {ok, seconds, budget}
func preload_budget_check() -> Dictionary:
	var budget := 1.0
	var sm := get_node_or_null("/root/SceneManager")
	if sm != null:
		budget = float(sm.get("LOAD_BUDGET_SECONDS"))
	var secs := float(root._preload_usec) / 1000000.0
	return {"ok": secs <= budget, "seconds": secs, "budget": budget}


func preload_step() -> void:
	if not root.dungeon_generated or root._preload_cursor >= root.dungeon_graph.size():
		return
	for _n in PRELOAD_PER_FRAME:
		if root._preload_cursor >= root.dungeon_graph.size():
			return
		var i: int = root._preload_cursor
		root._preload_cursor += 1
		if i == root.current_room_index or root._room_cache.has(i):
			continue
		var t0 := Time.get_ticks_usec()
		var node: Node3D = root._build_room(i)
		root._preload_usec += Time.get_ticks_usec() - t0
		if node != null:
			root._room_cache[i] = node
			root._preload_built += 1


## 丢弃预建缓存（重建地牢时必须调用，否则会挂上上一层的房间）
func clear_preload() -> void:
	for k in root._room_cache:
		var n = root._room_cache[k]
		if n != null and is_instance_valid(n):
			n.free()      # 未入树，free 即可
	root._room_cache.clear()
	root._preload_cursor = 0
	root._preload_built = 0
	root._preload_usec = 0


## 正在构建的房间索引。**不能用 root.current_room_index 代替**——
## 预加载时房间是提前建的，那时 root.current_room_index 指向别的房
## （与 _apply_topology_doors 的 idx 参数同一个原因）。
var _building_room_index := -1


## 预加载统计（供调试面板/测试断言）
func preload_stats() -> Dictionary:
	return {
		"total": root.dungeon_graph.size(),
		"built": root._preload_built,
		"cached": root._room_cache.size(),
		"cursor": root._preload_cursor,
		"avg_ms": (float(root._preload_usec) / float(maxi(root._preload_built, 1))) / 1000.0,
	}


## 整层预建是否完成
func preload_done() -> bool:
	return root.dungeon_generated and root._preload_cursor >= root.dungeon_graph.size()


## 房间 JSON 缓存：路径 → 解析后的字典。
## 原先每次切房都重新读盘 + JSON.parse（实测单次 0.97ms，占切房耗时的可观比例），
## 而房间模板在运行期不会变，读一次就够。
static var _json_cache := {}

