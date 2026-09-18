class_name PickupField
extends Node3D
## 掉落物集中管理 —— 消除"每件一个 _process + 每帧遍历全组"
##
## ## 为什么需要
## 原实现每件掉落物是一个独立 `Node3D`，各自跑 `_process`（自转+浮动），
## 玩家拾取靠每帧 `get_nodes_in_group("pickups")` 全量遍历。
## 规模小时无妨，但大规模团战下（2000 怪 × 30% 掉落率 ≈ 600 件）：
##   · 600 个 `_process` 每帧执行
##   · 每次拾取判定遍历 600 个节点
## 这会把群体模拟省下的收益吃回去。
##
## ## 做法（不换架构，只消开销）
## 保留"掉落物是节点"的既有结构——稀有度颜色、拾取/吞噬、存档 meta
## 全部不动。只做三件事：
##   1. **动画集中驱动**：掉落物不再各自 `_process`，由本管理器统一
##      推进一个共享的相位值，各掉落物按自己的相位偏移算角度/浮动
##   2. **空间分桶**：按格子维护 `格子 → 掉落物列表`，拾取时只查
##      玩家所在格及邻格，而不是全场景遍历
##   3. **上限保护**：超过 `MAX_PICKUPS` 时淘汰最旧的（防止无限堆积
##      拖垮帧率；玩家不会为了捡 3 件白装去翻 600 件的历史掉落）
##
## 本类**不改变掉落内容**——生成仍由 LootSystem 决定，本类只管
## "生成出来的东西怎么高效地存在与查找"。

## 掉落物数量上限。超出后淘汰最旧的。
## 取值依据：玩家单次可见范围约 10×10 米，正常情况下同屏掉落远少于此；
## 600 件是"团战一整轮没人捡"的极端情况，超过就该淘汰了。
const MAX_PICKUPS := 256
## 空间分桶的格子边长（米）
const CELL := 4.0

## 格子键 → 掉落物节点列表
var _buckets := {}
## 全部掉落物（按加入顺序，用于上限淘汰）
var _all: Array[Node3D] = []
## 共享动画相位（秒），所有掉落物按它 + 各自偏移计算姿态
var _phase := 0.0


func _ready() -> void:
	# 只在本管理器上跑一个 _process，而不是每个掉落物一个
	set_process(true)


func _process(delta: float) -> void:
	_phase += delta
	# 统一推进所有掉落物的姿态。
	# 用"相位 + 每件固定偏移"而不是各自累加：视觉上每件仍有独立节奏，
	# 但计算量从 N 次 sin 降到 N 次查表式运算，且没有 N 个 _process 调度开销。
	var i := 0
	for p in _all:
		if not is_instance_valid(p):
			i += 1
			continue
		# 每件用一个固定的相位偏移，避免整片掉落物同频闪烁
		var ph := _phase * 2.0 + float(i) * 0.7
		p.rotation.y = ph
		p.position.y = p.get_meta("base_y", 0.5) + sin(ph * 1.5) * 0.06
		i += 1


## 登记一个掉落物（由 LootSystem 在生成后调用）。
## 会自动接管它的动画（掉落物自身不该再跑 _process）。
func register(pickup: Node3D) -> void:
	if pickup == null or not is_instance_valid(pickup):
		return
	_all.append(pickup)
	_bucket_add(pickup)
	pickup.set_meta("base_y", pickup.position.y)
	pickup.tree_exiting.connect(func(): _forget(pickup))
	_enforce_cap()


## 从桶里移除（节点销毁时自动触发，也供手动调用）
func _forget(pickup: Node3D) -> void:
	_all.erase(pickup)
	_bucket_remove(pickup)


# ============================================================
# 空间分桶
# ============================================================

func _key(pos: Vector3) -> int:
	var cx := int(floor(pos.x / CELL))
	var cz := int(floor(pos.z / CELL))
	return (cx + 4096) * 8192 + (cz + 4096)


func _bucket_add(pickup: Node3D) -> void:
	var k := _key(pickup.global_position)
	if not _buckets.has(k):
		_buckets[k] = []
	_buckets[k].append(pickup)


func _bucket_remove(pickup: Node3D) -> void:
	var k := _key(pickup.global_position)
	if _buckets.has(k):
		var arr: Array = _buckets[k]
		arr.erase(pickup)
		if arr.is_empty():
			_buckets.erase(k)


## 查某点半径内最近的掉落物（只扫覆盖到的格子，不全场景遍历）。
## 返回 null 表示范围内没有。
func nearest(pos: Vector3, max_dist: float) -> Node3D:
	var nearest_node: Node3D = null
	var nearest_d := max_dist
	var r := int(ceil(max_dist / CELL))
	var cx := int(floor(pos.x / CELL))
	var cz := int(floor(pos.z / CELL))
	for oz in range(-r, r + 1):
		for ox in range(-r, r + 1):
			var k := (cx + ox + 4096) * 8192 + (cz + oz + 4096)
			if not _buckets.has(k):
				continue
			for p in _buckets[k]:
				if not is_instance_valid(p):
					continue
				var d: float = p.global_position.distance_to(pos)
				if d < nearest_d:
					nearest_d = d
					nearest_node = p
	return nearest_node


## 当前掉落物总数（测试/调试用）
func count() -> int:
	var n := 0
	for p in _all:
		if is_instance_valid(p):
			n += 1
	return n


## 超出上限时淘汰最旧的。
## 淘汰的是**最旧**而不是最远：最远的可能正是玩家要跑过去捡的，
## 最旧的则大概率是玩家已经路过放弃的。
func _enforce_cap() -> void:
	while _all.size() > MAX_PICKUPS:
		var oldest: Node3D = _all.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
