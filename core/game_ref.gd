class_name GameRef
extends RefCounted
## 跨层引用查找的**唯一入口**。
##
## ## 为什么要有这个类
##
## 在它出现之前，全项目有 **6 种**不同的"找 GameRoot / 找当前房间 /
## 找群体管理器"写法，散在 player / projectile_manager / room_controller /
## hidden_wall / minimap_view / hud 里。同一件事六份真相，于是：
##
##   · `hud.gd` 用 `get_tree().current_scene` 取 GameRoot —— 但 main.tscn 的根是
##     `MainScene`、GameRoot 是它的**子节点**，`get()` 返回 null 且不报错，
##     于是第 6 层毒气**照常扣真伤、HUD 上却永远没有数字**。
##   · `room_controller` / `hidden_wall` 用 `/root/GameRoot` 直取 —— 该路径
##     根本不存在（真实路径是 `/root/MainScene/GameRoot`），
##     靠后面的特征搜索兜底才没出事。
##
## 今后所有跨层引用**一律走本类**。别处再出现同类查找即为缺陷。
##
## ## 三条已验证的陷阱（写在这里免得下一个人再踩）
##
## 1. **`get_tree().current_scene` 不是 GameRoot**。它是 `MainScene`
##    （main.tscn 的根，无脚本），GameRoot 是它的子节点。
## 2. **`PickupField` 是懒创建的**（`LootSystem._field_for()` 在第一次掉落时才建），
##    故 `pickup_field()` 返回 null 是**正常状态**，不代表链路断了。
## 3. **`current_room_node` 存的是节点引用而非路径**，
##    所以 SubViewport 边界不影响它——不必绕开子视口。


## 缓存。**不能无条件信任**：场景重载后旧节点会被释放，
## 故每次取用前用 `is_instance_valid` + `is_inside_tree` 复核。
static var _cached_root: Node = null


## 取 GameRoot。
##
## 顺序：`game_root` 组 → 从 current_scene 按特征属性递归兜底。
## 组由 `game_root.gd:_ready()` 注册，是生产路径的**唯一**可靠来源；
## 特征搜索只为兜住"测试场景把 main.tscn 嵌在测试根之下"这种情况。
static func game_root() -> Node:
	if _cached_root != null and is_instance_valid(_cached_root) \
			and _cached_root.is_inside_tree():
		return _cached_root
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	# ① 组优先（生产路径）
	for n in tree.get_nodes_in_group("game_root"):
		if is_instance_valid(n):
			_cached_root = n
			return n
	# ② 特征属性兜底（测试路径）
	var scene := tree.current_scene
	if scene != null:
		_cached_root = find_game_root_feature(scene)
		return _cached_root
	return null


## 按 GameRoot 的**特征属性**递归查找（测试场景用）。
##
## 接受两个标记，因为项目里既有两种写法都出现过：
##   · `dungeon_graph` —— 生产 GameRoot 与 `hidden_wall.gd` 用的
##   · `room_state`    —— 生产 GameRoot 与 `room_controller.gd` 用的，
##                        以及 `tests/fake_game_root.gd` 这个最小替身
## 生产路径其实走不到这里（`game_root` 组命中即返回），
## 本函数只为兜住"测试把 main.tscn 或替身嵌在测试根之下"的场景。
static func find_game_root_feature(node: Node) -> Node:
	if node.get("dungeon_graph") != null or node.get("room_state") != null:
		return node
	for c in node.get_children():
		var found := find_game_root_feature(c)
		if found != null:
			return found
	return null


## 取当前房间节点。
##
## 经 GameRoot 持有的 `current_room_node` —— 那是**节点引用**，
## 所以房间住在 SubViewport 里也不影响（见文件头陷阱 3）。
static func current_room() -> Node:
	var gr := game_root()
	if gr == null:
		return null
	var room = gr.get("current_room_node")
	return room if is_instance_valid(room) else null


## 取当前房间的 RoomController（没有则 null）
static func room_controller() -> Node:
	var room := current_room()
	if room == null:
		return null
	return room.get_node_or_null("RoomController")


## 取当前房间的群体管理器（没有则 null）。
##
## 房间未启用群体路径时 `_crowd_mgr` 为 null —— **这是正常状态**，
## 不代表断链（`RoomController._should_use_crowd()` 决定是否创建）。
static func crowd_manager() -> Node:
	var ctrl := room_controller()
	if ctrl == null:
		return null
	var mgr = ctrl.get("_crowd_mgr")
	return mgr if (mgr != null and is_instance_valid(mgr)) else null


## 取当前房间的掉落物管理器。
##
## **返回 null 是正常状态**：`PickupField` 由 `LootSystem._field_for()`
## 在**第一次掉落时**懒创建，开局房间里根本不存在。
## 调用方（如 `Player._nearest_pickup()`）有全量遍历兜底，链路并未断。
static func pickup_field() -> PickupField:
	var room := current_room()
	if room == null:
		return null
	var f: Node = room.get_node_or_null("PickupField")
	return f if f is PickupField else null


## 取玩家节点（没有则 null）
static func player() -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p):
			return p as Node3D
	return null


## 清缓存。场景切换/新开局时调用，避免持有上一局的 GameRoot。
##
## 不调用也不会出错（缓存项会因 `is_instance_valid` 失败而自动失效），
## 但显式清理更干净、也便于测试隔离。
static func invalidate() -> void:
	_cached_root = null
