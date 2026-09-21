class_name RoomTransitionService
extends Node
## 房间切换服务 —— 门触发、防抖、重入保护、落点与门的协调。
##
## ## 这是全项目最精细的一段，搬动时**逐字照搬**
##
## 「进一格却穿两房」曾是一个顽固缺陷，修它换来了四道防线，缺一不可：
##   ① `_on_door_entered` 的**全局防抖**（TRANSITION_COOLDOWN 0.15s）
##      —— 与门无关的总闸，挡住落点抖动/奔跑大位移造成的紧邻帧重触发
##   ② `transition_to_room` 的**重入保护**（_is_transitioning）
##      —— 挡同一次调用的重入（旧房间的门本帧还活着）
##   ③ **先抑制全部门再放玩家**（suppress_all_doors → _place_player →
##      release_suppressed_doors）—— Godot 在 Area3D 进树时会对已重叠的
##      body 派发 body_entered；若先放玩家、出生点又恰在门内，
##      信号会在我们能禁用之前发出去
##   ④ `disarm_entry_door` 的**几何复核**（player_touches_door）
##      —— 容差必须 ≥ 物理重叠包络（x±1.5 / z±1.25），
##      比物理窄会留下缝隙带 → 幽灵派发穿透 → 连锁切房
##
## 改动顺序或容差前请先读 `docs/progress/room_flow_chain_flaky_analysis.md`。
##
## ## 字段归属
##
## `_is_transitioning` / `_last_transition_time` / `current_room_index` /
## `current_room_node` 留在 GameRoot（生成、预建、调试共用），
## 组件按 `root.xxx` 访问。

## 宿主 GameRoot（构造时注入）
var root: Node = null

## 玩家是否压在某个门触发器上的容差（半长，米）。
##
## **必须 ≥ 物理重叠包络**，否则会漏判：
##   物理包络 = 触发盒半长 + 玩家胶囊半径 = x ±(1.0+0.5) / z ±(0.75+0.5)
##            = x ±1.5 / z ±1.25
## 原先取的是 x±1.3 / z±1.05（比物理窄 0.2 米），留下的**缝隙带**会导致：
## 落点物理上压着门（Area3D 会派发 body_entered）、几何上却判"没碰"
## → release_suppressed_doors 把这扇门 reset 释放 → 下一物理帧
## 幽灵派发穿透 → 连锁切房（表现为 room_flow 偶发「期望房 N 实际房 M」）。
## 这与 door_trigger 里的几何复核是同一个包络口径，两处必须一致。
const DOOR_TOUCH_HALF_X := 1.5
const DOOR_TOUCH_HALF_Z := 1.25


## 装配：注入宿主 GameRoot
func setup(owner_root: Node) -> void:
	root = owner_root

func on_door_entered(direction: String, _door_id: String) -> void:
	if not root.dungeon_generated:
		return
	# 全局防抖：刚切完房的一小段时间内忽略所有门信号。
	# 落点靠近门、或奔跑时一帧位移大，都可能在同一帧/紧邻帧再次踩门；
	# 旧房间的门要到帧末才销毁，也在此时仍可被触发 → 「进一格穿两房」。
	# 单靠入口门自身的失效不够，这里再加一道与门无关的总闸。
	var now := Time.get_ticks_msec() / 1000.0
	if now - root._last_transition_time < root.TRANSITION_COOLDOWN:
		return
	var target_idx := self.find_room_in_direction(direction)
	if target_idx < 0:
		return
	# 只在「门触发的切房」时启动防抖；程序性切房（下一层、测试直调）不启动，
	# 否则会误伤正常玩法与测试里的连续切房
	root._last_transition_time = now
	self.transition_to_room(target_idx, direction)


func find_room_in_direction(direction: String) -> int:
	var data: Dictionary = root.get_current_room_data()
	if data.is_empty():
		return -1
	var current_pos: Vector2i = data.get("position", Vector2i.ZERO)
	var dir_vec := Vector2i.ZERO
	match direction:
		"north": dir_vec = Vector2i(0, -1)
		"south": dir_vec = Vector2i(0, 1)
		"west":  dir_vec = Vector2i(-1, 0)
		"east":  dir_vec = Vector2i(1, 0)
	var target_pos := current_pos + dir_vec
	for i in root.dungeon_graph.size():
		var pos: Vector2i = root.dungeon_graph[i].get("position", Vector2i.ZERO)
		if pos == target_pos:
			return i
	return -1


func transition_to_room(target_idx: int, enter_direction: String = "") -> void:
	if target_idx == root.current_room_index:
		return
	# 重入保护：一次触发只切一次房。
	# 旧房间的门在本帧内仍然活着（queue_free 要到帧末），落点又靠近门，
	# 没有这道闸门时同一帧可能被第二扇门再触发一次 → 「进一格却穿两房」。
	if root._is_transitioning:
		return
	root._is_transitioning = true

	# 离开当前房间
	if root.current_room_node:
		var ctrl: Node = root.current_room_node.get_node_or_null("RoomController")
		if ctrl and ctrl is RoomController:
			(ctrl as RoomController).deactivate()

	# 销毁旧房间
	if root.current_room_node:
		root.current_room_node.queue_free()
		root.current_room_node = null

	# 更新索引
	root.current_room_index = target_idx

	# 加载新房间
	root.load_current_room()
	self.activate_current_room()
	# 顺序关键：**先把门标记为已触发，再放玩家**。
	# Godot 在 Area3D 进树时会对「已与其重叠的 body」派发 body_entered。
	# 若先放玩家、出生点又恰在某扇门的触发区内，信号会在我们能禁用之前就发出去
	# → 切房连锁（实测：期望房10 实际房8，玩家落在 (11,0,2) 的出生点、并不在门旁）。
	# root._is_transitioning 只挡同一次调用的重入，跨调用无效，挡不住这个。
	self.suppress_all_doors()
	root._place_player(enter_direction)
	self.release_suppressed_doors()
	# 再按落点收尾：只禁玩家真正压着的那扇（保留回头路）
	self.disarm_entry_door(enter_direction)

	root._is_transitioning = false


## 把本房所有门临时标为「已触发」，挡住 Area3D 进树时对重叠 body 的派发。
## 必须配合 self.release_suppressed_doors()：否则门会一直哑掉，正常穿门失灵。
func suppress_all_doors() -> void:
	for trig in self.room_door_triggers():
		trig.set("_triggered", true)


## 解除抑制，但**保留玩家当前压着的那扇**（否则会被重叠派发再次触发）
func release_suppressed_doors() -> void:
	for trig in self.room_door_triggers():
		if not self.player_touches_door(trig):
			if trig.has_method("reset_trigger"):
				trig.call("reset_trigger")


## 本房所有门触发器
func room_door_triggers() -> Array:
	var out: Array = []
	if root.current_room_node == null:
		return out
	var doors_node: Node = root.current_room_node.get_node_or_null("Doors")
	if doors_node == null:
		return out
	for door in doors_node.get_children():
		if not str(door.name).begins_with("Door_"):
			continue
		var trig = door.get_node_or_null("DoorTrigger")
		if trig != null:
			out.append(trig)
	return out


## 让门短暂失效，避免玩家落点踩门导致连锁切房。
##
## 两种落点都会踩门，必须都覆盖：
##  ① 穿门切房：落点在本房入口门内侧（DOOR_ENTRY_OFFSET=2.0，不重叠），
##     但为稳妥仍把入口那扇禁用。
##  ② **无方向切房**（开局 / 传送门 / 直接调用）：走 player_spawn 分支，
##     而绝大多数模板的 player_spawn 距南门只有 1 格——门在**格边缘**
##     （world z = 格子 +0.5），触发器 Z 跨度 ±0.75，于是出生点实际**落在
##     触发器内**（重叠约 0.25m）。若本房恰有南邻，门立刻触发 → 连传两格。
##     （只有有南邻时才会连，故表现为偶发）
##
## 判定用**几何**而非 get_overlapping_bodies()：刚设置完 root.player 位置的
## 那一帧，Area3D 的重叠列表还没更新（要等物理帧），用重叠检测会漏判。
func disarm_entry_door(enter_direction: String) -> void:
	if root.current_room_node == null:
		return
	var doors_node: Node = root.current_room_node.get_node_or_null("Doors")
	if doors_node == null:
		return

	var entry_dir: String = "" if enter_direction.is_empty() else root._opposite_dir(enter_direction)
	for door in doors_node.get_children():
		if not str(door.name).begins_with("Door_"):
			continue
		var trig = door.get_node_or_null("DoorTrigger")
		if trig == null or not trig.has_method("disarm_until_clear"):
			continue
		# 禁用条件：玩家正压在门上（任何情况都要），或有方向时的入口那扇。
		# 注意**不要**在无方向时无差别禁用全部门——那会挡掉紧随其后的合法切房。
		var touching: bool = self.player_touches_door(trig)
		var is_entry: bool = entry_dir != "" and str(trig.get("direction")) == entry_dir
		if not touching and not is_entry:
			continue
		trig.call("disarm_until_clear")


## 玩家是否压在某个门触发器上（在触发器局部空间做盒判定，自动兼容门朝向）
## 触发器尺寸 2×3×1.5（半长 1.0 / 1.5 / 0.75），放宽容差。
## 玩家是否压在某个门触发器上（在触发器局部空间做盒判定，自动兼容门朝向）。
##
## **容差必须 ≥ 物理重叠包络**，否则会漏判：
##   物理包络 = 触发盒半长 + 玩家胶囊半径 = x ±(1.0+0.5) / z ±(0.75+0.5)
##            = x ±1.5 / z ±1.25
## 原先取的是 x±1.3 / z±1.05（比物理窄 0.2 米），留下的**缝隙带**会导致：
## 落点物理上压着门（Area3D 会派发 body_entered）、几何上却判"没碰"
## → _release_suppressed_doors 把这扇门 reset 释放 → 下一物理帧
## 幽灵派发穿透 → 连锁切房（表现为 room_flow 偶发「期望房 N 实际房 M」）。
## 这与 door_trigger 里的几何复核是同一个包络口径，两处必须一致。


func player_touches_door(trig: Node) -> bool:
	if root.player == null or not is_instance_valid(root.player):
		return false
	if not (trig is Node3D):
		return false
	var t := trig as Node3D
	var local: Vector3 = t.global_transform.affine_inverse() * root.player.global_position
	return absf(local.x) <= DOOR_TOUCH_HALF_X and absf(local.z) <= DOOR_TOUCH_HALF_Z


func activate_current_room() -> void:
	if root.current_room_node == null:
		return
	var ctrl: Node = root.current_room_node.get_node_or_null("RoomController")
	if ctrl and ctrl is RoomController:
		(ctrl as RoomController).activate()
