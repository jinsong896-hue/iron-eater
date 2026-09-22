class_name SummonManager
extends Node
## 召唤物管理器 —— 生成、上限、存活跟踪。
##
## ## 为什么需要它
##
## 召唤物是**友方单位**，但玩家侧此前完全没有"友方单位"的概念。
## 管理器负责三件父类管不了的事：
##   1. **上限**：同屏召唤物数量封顶（规格里的「召唤物上限 +1」改的就是它）
##   2. **生成**：按主人的属性比例造出 SummonBase 并挂到房间下
##   3. **清场**：换房/死亡时统一回收（否则召唤物会跨房间残留）
##
## ## 挂在玩家身上
##
## 与其它玩家组件同构（见 entities/player/ 下的各 component）：
## 由 Player 在 `_ready` 装配，`setup(self)` 注入主人。

## 主人（玩家）
var player: Node3D = null
## 当前存活的召唤物
var _alive: Array[Node] = []
## 上限（装备的 summon_limit 词条可提升）
var base_limit := 3


func setup(owner_player: Node3D) -> void:
	player = owner_player


## 当前召唤物数量
func count() -> int:
	_prune()
	return _alive.size()


## 上限（基础 + 装备加成）
func limit() -> int:
	var bonus := 0
	var gm = get_node_or_null("/root/GameManager")
	if gm != null:
		var em = gm.get("equipment_manager")
		if em != null and em.has_method("special_modifiers"):
			var sp: Dictionary = em.call("special_modifiers")
			bonus = int(round(float(sp.get("summon_limit", 0.0))))
	return maxi(base_limit + bonus, 1)


## 召唤一个单位。返回是否成功（超上限/无主人时失败）。
##
## `hp_ratio` / `atk_ratio` / `ap_ratio` 是规格里的「继承 N% 生命/攻击/法强」。
## 返回新建的召唤物节点（失败返回 null）。
func summon(hp_ratio: float, atk_ratio: float, ap_ratio: float,
		lifetime: float) -> Node:
	if player == null or not is_instance_valid(player):
		return null
	_prune()
	if _alive.size() >= limit():
		EventBus.message.emit("召唤物已达上限（%d）" % limit())
		return null
	var parent := _spawn_parent()
	if parent == null:
		return null
	var s := SummonBase.new()
	s.name = "Summon"
	parent.add_child(s)
	# 生成在主人身前一点，避免与主人重叠
	var facing: Vector3 = player.get("_facing")
	if facing.length_squared() < 0.001:
		facing = Vector3.FORWARD
	s.global_position = player.global_position + facing.normalized() * 1.2
	s.configure_from_owner(player, hp_ratio, atk_ratio, ap_ratio, lifetime)
	# 召唤物伤害加成（装备的 summon_dmg_pct）：直接乘在攻击上
	var gm = get_node_or_null("/root/GameManager")
	if gm != null:
		var em = gm.get("equipment_manager")
		if em != null and em.has_method("special_modifiers"):
			var sp: Dictionary = em.call("special_modifiers")
			s.atk *= 1.0 + float(sp.get("summon_dmg_pct", 0.0))
	_alive.append(s)
	return s


## 回收全部召唤物（换房/玩家死亡时调用）
func clear_all() -> void:
	for s in _alive:
		if is_instance_valid(s):
			s.queue_free()
	_alive.clear()


## 召唤物挂载点：优先当前房间（随房间销毁），否则挂主人父节点。
func _spawn_parent() -> Node:
	var room := GameRef.current_room()
	if room != null:
		return room
	if player != null and player.get_parent() != null:
		return player.get_parent()
	return null


## 清掉已失效的引用
func _prune() -> void:
	var kept: Array[Node] = []
	for s in _alive:
		if is_instance_valid(s):
			kept.append(s)
	_alive = kept
