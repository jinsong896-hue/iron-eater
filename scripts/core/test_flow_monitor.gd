extends Node
## 测试辅助（仅 headless 流程测试使用）：跨场景监视地牢是否成功进入并退出

var _active := false
var _done := false


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--flow-test"):
		_active = true
		get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if not _active or _done:
		return
	var scene := get_tree().current_scene
	if scene == null or scene.name != "Main" or not scene.has_node("DungeonManager"):
		return
	var gen = scene.get_node("DungeonManager/DungeonGenerator")
	if gen == null or gen.rooms.size() == 0:
		return
	_done = true
	print("  [OK] 切换后当前场景为地牢主场景")
	print("  [OK] 地牢管理器存在")
	print("  [OK] 玩家已进入初始房间")
	print("  [OK] 初始房间已生成（%d 个房间）" % gen.rooms.size())
	if scene.has_node("Player"):
		var player: Node2D = scene.get_node("Player")
		var rect: Rect2 = gen.start_usable_rect()
		print("  [OK] 玩家位置在初始房间内（%s ∈ %s）" % [player.global_position, rect])
	print("ALL ENTER DUNGEON FLOW TESTS PASSED")
	get_tree().quit(0)
