class_name RoomPortal
extends Node
## 传送门与楼层流转 —— Boss 房清空后生成传送门，触碰进入下一层。
##
## ## 职责
##
## · `show_portal()`：在 Boss 出生点建一个发光圆柱 Area3D（惰性，重复调用只显形）
## · `_on_portal_entered()`：玩家触碰 → 层数 +1 → 通知 GameRoot 重建地牢
## · `clear_player_buffs()`：换层"满状态"时清空词条与元素叠层
##
## ## 字段归属
##
## `_portal` / `_boss_spawn` 留在 RoomController：`deactivate()` 要销毁
## `_portal`，`_on_cleared` 要读 `_boss`。故本组件按 `room.xxx` 访问。
##
## ## 踩坑注释（随代码搬走，别丢）
##
## `_on_portal_entered` 里取 GameRoot **必须用 `room._game_root()`**，
## 不能用 `get_parent().get_parent()`：房间节点挂在 GameRoot/World 下，
## 父节点是 World 而非 GameRoot，那样取到的是 World
## → `has_method("next_floor")` 恒 false → 传送门只涨层数、地牢从不重建
##（玩家原地不动，以为传送没打通）。

## 宿主 RoomController（构造时注入）
var room: Node = null


## 装配：注入宿主房间控制器
func setup(owner_room: Node) -> void:
	room = owner_room

func show_portal() -> void:
	if room._portal != null and is_instance_valid(room._portal):
		room._portal.visible = true
		return

	var room_root := get_parent()
	if room_root == null:
		return

	# 传送门放在 Boss 出生点
	var pos: Vector3 = room._boss_spawn.global_position if room._boss_spawn else Vector3.ZERO
	room._portal = Area3D.new()
	room._portal.name = "NextFloorPortal"
	room._portal.position = pos + Vector3(0, 1.0, 0)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.2
	shape.height = 2.0
	col.shape = shape
	room._portal.add_child(col)

	# 视觉：发光圆柱
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 2.0
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	room._portal.add_child(mesh)

	room._portal.body_entered.connect(self._on_portal_entered)
	room_root.add_child(room._portal)

	var bus = room._event_bus()
	if bus:
		bus.message.emit("Boss 已击败！进入传送门前往下一层")


## 触碰传送门 → 进入下一层。
##
## **隐藏层门槛**（策划书 1.3）：第 9 层需集齐 8 片钥匙碎片才能进入。
## 未集齐时**拦下传送**（提示 + 不切层），玩家留在本层可继续探索，
## 但传送门已开、可反复尝试——策划原文「进入后不可回头」指的是进去之后，
## 不是「凑不齐就死局」。
func _on_portal_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var gm = room._game_manager()
	if gm:
		var cur: int = int(gm.run_info.get("floor", 1))
		var next_floor: int = cur + 1

		# 隐藏层门槛：进入第 9 层需集齐碎片
		if next_floor >= FloorDefs.MAX_FLOOR and not gm.has_all_key_fragments():
			var bus_deny = room._event_bus()
			if bus_deny:
				bus_deny.message.emit("混沌裂隙需要 %d 片钥匙碎片（当前 %d 片）" % [
					FloorDefs.KEY_FRAGMENTS_REQUIRED, int(gm.run_key_fragments)])
			return

		gm.run_info["floor"] = next_floor
		# 层间全恢复（满状态进新层）
		if GameBalance.FLOOR_TRANSITION_FULL_HEAL and gm.attributes:
			gm.attributes.hp = gm.attributes.max_hp
		# 同时清空词条与元素叠层——「满状态」必须包含这一项。
		# 毒蚀按策划「层数永不衰减、持续至目标死亡」，跨层不清的话
		# 玩家会带着上层的毒层数与三层毒负面（侵蚀/衰弱/虚弱）进新层，
		# 表现为「debuff 永远挂着、只有再吃一次才刷新」（实测报告）。
		if GameBalance.FLOOR_TRANSITION_FULL_HEAL:
			self.clear_player_buffs()
		# 超出层数上限即通关（第 9 层打完结算）
		if next_floor > FloorDefs.MAX_FLOOR:
			gm.finish_run("cleared")
			return
		var bus0 = room._event_bus()
		if bus0:
			bus0.stats_changed.emit()
	# 通知 GameRoot 重建地牢（下一层）。
	# **必须用 room._game_root() 而不是 get_parent().get_parent()**：
	# 房间节点挂在 GameRoot/World 下，父节点是 World 而非 GameRoot，
	# 原先这样取得的是 World → has_method("next_floor") 恒 false
	# → 传送门只涨层数、地牢从不重建（玩家原地不动，以为传送没打通）。
	var game_root: Node = room._game_root()
	if game_root != null and game_root.has_method("next_floor"):
		game_root.call("next_floor")


## 清空玩家身上的全部词条与元素叠层（换层"满状态"用）。
## 取不到玩家或 buffs 时静默跳过。
## 清空玩家身上的全部词条与元素叠层（换层"满状态"用）。
## 取不到玩家或 buffs 时静默跳过。
func clear_player_buffs() -> void:
	for p in room.get_tree().get_nodes_in_group("player"):
		var pb = p.get("buffs")
		if pb != null and pb.has_method("clear"):
			pb.call("clear")
			return
