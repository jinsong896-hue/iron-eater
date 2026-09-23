class_name PickupComponent
extends Node
## 玩家拾取与交互组件 —— 从 `Player` 拆出的第 1 块职责。
##
## ## 为什么单独成组件
##
## `player.gd` 原有 2231 行 / 119 个函数，把移动、战斗、技能、特效、相机、
## 音效、拾取七类职责挤在一个文件里——改任何一处都要在两千行的海洋里航行。
## 拾取这块（E 键交互 + 自动拾取 + 就近查找）边界最清晰、与移动/战斗零耦合，
## 故第一个搬出来。
##
## ## 职责
##
## · `update(delta)` —— 自动拾取节流检测（由 Player 每帧转发）
## · `try_interact()` —— E 键交互（由 Player 的 `_unhandled_input` 转发）
## · `try_devour()` —— F 键吞噬
##
## ## **E 键的分流顺序是行为的一部分，不能动**
##
## 破墙（隐藏房）→ 特殊房 → 拾取。这个顺序是实测修过的：
## 若把拾取放前面，站在隐藏墙前按 E 会先去捡脚下的东西而不是破墙。
## 另注意 `_interact_special_room()` **必须能在非特殊房返回 false**——
## 每个房间都有控制器，若无条件返回 true，拾取逻辑将永不执行。

## 拾取/吞噬的作用距离（米）。超过视为够不着——
## 原先返回全场景最近的掉落物，隔着半张地图也能捡。
const PICKUP_RANGE := 2.5

## 自动拾取的检测间隔（秒），避免每帧遍历掉落物
const AUTO_PICKUP_INTERVAL := 0.25

## 宿主玩家节点（构造时注入）
var player: Node3D = null

var _auto_pickup_timer := 0.0


## 绑定宿主。**必须在 add_child 之后调用**（Player 在 _ready 里装配组件）。
func setup(owner_player: Node3D) -> void:
	player = owner_player


## 每帧推进：自动拾取节流检测。由 Player 的 `_physics_process` 无条件调用。
func update(delta: float) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null or not bool(sm.get_setting("auto_pickup")):
		return
	_auto_pickup_timer -= delta
	if _auto_pickup_timer > 0.0:
		return
	_auto_pickup_timer = AUTO_PICKUP_INTERVAL
	var nearest := nearest_pickup()
	if nearest == null:
		return
	if nearest.has_method("pick_up"):
		nearest.call("pick_up")   # 失败（背包满等）静默，等玩家腾出位置再来


## E 键交互：破墙（隐藏房）→ 特殊房 → 拾取。
## 返回 true 表示本次交互已被处理。
func try_interact() -> bool:
	if interact_hidden_wall():
		return true
	if interact_special_room():
		return true
	pickup_nearby()
	return false


## F 键吞噬最近掉落物（本局永久成长）
func try_devour() -> void:
	devour_nearby()


## 切换拾取方式（按 E 手动 ↔ 自动拾取）。
## 仅由设置面板调用——不再绑定按键，避免与游戏内操作抢键。
func toggle_auto_pickup() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		return
	var now: bool = not bool(sm.get_setting("auto_pickup"))
	sm.set_setting("auto_pickup", now)
	EventBus.message.emit("自动拾取：%s" % ("开" if now else "关"))


## 破墙进入隐藏房（策划 3.2：靠近出现裂缝 → 破开）。
## 返回 true 表示本次交互已被处理（破墙成功），调用方不再尝试其它交互。
func interact_hidden_wall() -> bool:
	var walls := get_tree().get_nodes_in_group("hidden_walls")
	for w in walls:
		if not is_instance_valid(w):
			continue
		if w.has_method("can_interact_with") and bool(w.call("can_interact_with", player)):
			var ok: bool = bool(w.call("break_wall", player))
			if ok:
				PlayerSfx.on_break_wall()
				EventBus.message.emit("你破开了墙壁")
				return true
	return false


## 交互当前房间的商店、泉水或事件服务。
## 返回 false 表示"本房不是特殊房"，让位给 `pickup_nearby()`——
## 注意每个房间都有控制器（activate 对所有房型都加组），
## 若无条件返回 true，拾取逻辑将永不执行。
func interact_special_room() -> bool:
	var controller := get_tree().get_first_node_in_group("current_room_controller")
	if controller == null or not controller.has_method("is_special_room"):
		return false
	if not bool(controller.call("is_special_room")):
		return false

	# 打开交互面板；面板缺失时回退到旧的"按 E 直接结算"
	var ui := get_tree().get_first_node_in_group("special_room_ui")
	if ui != null and ui.has_method("open"):
		var ctx: Dictionary = controller.call("get_special_context")
		if ctx.get("ok", false):
			ui.call("open", ctx, controller)
			return true
		EventBus.message.emit(ctx.get("reason", "无法交互"))
		return true

	var result: Dictionary = controller.interact_special()
	if result.get("ok", false):
		EventBus.message.emit("特殊房交互完成")
	else:
		EventBus.message.emit(result.get("reason", "无法交互"))
	return true


## 查找最近的掉落物（拾取/吞噬共用）。有距离上限，超过视为够不着。
##
## **走 PickupField 的空间分桶查询**，不再遍历 `group("pickups")`：
## 大规模团战下掉落物可达数百件，全量遍历是每帧的固定开销。
## 分桶后只查玩家所在格及邻格。
func nearest_pickup() -> Node3D:
	# **拾取范围可被装备放大**（装备参考2 的 `pickup_range_pct` 通道）。
	# 该通道此前零消费者——「拾取范围 +20%」这类装备加了没效果。
	var rng_bonus := _pickup_range_mult()
	var range_now := PICKUP_RANGE * rng_bonus
	var field := pickup_field()
	if field != null:
		return field.nearest(player.global_position, range_now)
	# 兜底：没有 PickupField（旧场景/测试直建）时退回全量遍历
	var nearest: Node3D = null
	var nearest_d := range_now
	for node in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(node):
			continue
		var d: float = (node as Node3D).global_position.distance_to(player.global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = node
	return nearest


## 拾取范围倍率（1.0 + 装备的 pickup_range_pct）
func _pickup_range_mult() -> float:
	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		return 1.0
	var em = gm.get("equipment_manager")
	if em == null or not em.has_method("special_modifiers"):
		return 1.0
	var sp: Dictionary = em.call("special_modifiers")
	return 1.0 + float(sp.get("pickup_range_pct", 0.0))


## 当前房间的掉落物管理器（没有则返回 null）
##
## 查找逻辑统一在 `GameRef.pickup_field()`（跨层引用的唯一入口）。
## **返回 null 是正常状态**：开局房间没有 PickupField——它由
## `LootSystem._field_for()` 在第一次掉落时懒创建，此时由
## `nearest_pickup()` 的全量遍历兜底，链路并未断。
func pickup_field() -> PickupField:
	return GameRef.pickup_field()


## 拾取最近掉落物进背包
func pickup_nearby() -> void:
	var nearest := nearest_pickup()
	if nearest == null:
		EventBus.message.emit("附近没有可拾取的掉落物")
		return

	if nearest.has_method("pick_up"):
		var result: Dictionary = nearest.call("pick_up")
		if not result.get("ok", false):
			EventBus.message.emit(result.get("reason", "拾取失败"))


## 吞噬最近掉落物（本局永久成长）
func devour_nearby() -> void:
	var nearest := nearest_pickup()
	if nearest == null:
		EventBus.message.emit("附近没有可吞噬的掉落物")
		return

	if nearest.has_method("devour"):
		var result: Dictionary = nearest.call("devour")
		if result.get("ok", false):
			EventBus.message.emit("吞噬成功！")
			PlayerSfx.on_devour()
		else:
			EventBus.message.emit(result.get("reason", "吞噬失败"))
