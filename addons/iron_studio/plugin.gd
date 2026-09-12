@tool
extends EditorPlugin
## IronEater Studio 主插件
## 管理 dock 面板 + 3D 房间笔刷编辑（_forward_3d_gui_input）

const ROOM_EDITOR_SCENE := "res://scenes/rooms/room_editor.tscn"
const SAVE_DIR := "res://data/rooms/"

var _dock: Control
var _room_dock: Control

# 笔刷状态
var _current_tool: int = 0  # RoomEditorCore.Tool
var _spawn_type := "enemy_spawn"
var _spawn_monster_id := ""
var _floor_type := "stone"  # 地板笔刷类型（room_dock 同步）
var _wall_cell_direction := "north"  # 墙-格内模式当前朝向（R 键旋转）
var _is_painting := false
var _is_erasing := false  # 右键拖动连续擦除
var _last_paint_cell := Vector2i(-1, -1)
var _line_start_cell := Vector2i(-1, -1)  # 墙-拖线/矩形填充起点
var _hover_cell := Vector2i(-1, -1)  # 鼠标悬停格子（预览用）
var _hover_direction := ""  # 悬停边缘方向（墙-边缘/门模式用）
var _hover_world_pos := Vector3.ZERO  # 鼠标悬停世界坐标


func _enter_tree() -> void:
	print("[IronStudio] Loading plugin...")
	_dock = preload("res://addons/iron_studio/studio_tabs.tscn").instantiate()
	_dock.setup(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	# 绑定 room_dock 的插件引用
	_room_dock = _dock.get_node_or_null("Tabs/房间")
	if _room_dock and _room_dock.has_method("set_plugin"):
		_room_dock.set_plugin(self)
	# 持续接收 3D 视口输入（不依赖选中特定节点）
	set_input_event_forwarding_always_enabled()
	print("[IronStudio] Plugin loaded successfully")


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()


# ============================================================
# dock 调用的接口
# ============================================================

## 设置当前笔刷工具
func set_tool(tool_idx: int) -> void:
	_current_tool = tool_idx


## 设置刷怪点配置
func set_spawn_config(type: String, monster_id: String) -> void:
	_spawn_type = type
	_spawn_monster_id = monster_id


## 设置地板笔刷类型（room_dock 的类型下拉同步）
func set_floor_type(floor_type: String) -> void:
	_floor_type = floor_type


## 加载房间：读 JSON → 打开编辑场景 → 构建节点树
func load_room(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("[RoomEditor] 文件不存在: %s" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[RoomEditor] JSON 解析失败")
		return
	var data: Dictionary = json.data

	# 打开编辑场景（如果当前不是编辑场景）
	_open_editor_scene()
	# 等场景切换完成后构建（call_deferred 一帧）
	call_deferred("_build_loaded_room", data)


## _build_loaded_room：在打开的编辑场景里构建节点树
func _build_loaded_room(data: Dictionary) -> void:
	var root := _get_editor_root()
	if root == null:
		push_error("[RoomEditor] 编辑场景未就绪")
		return
	# 刷新格子线
	if root.has_method("refresh_grid"):
		root.refresh_grid(int(data.get("width", 20)), int(data.get("height", 15)))
	RoomEditorCore.build_editor_tree(root, data)


## 保存房间：序列化节点树 → 写 JSON
func save_room(path: String, meta: Dictionary) -> void:
	var root := _get_editor_root()
	if root == null:
		push_error("[RoomEditor] 没有打开的编辑场景")
		return
	var data := RoomEditorCore.serialize_tree(root, meta)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var json_str := JSON.stringify(data, "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[RoomEditor] 保存失败: %s" % path)
		return
	f.store_string(json_str)
	f.close()
	print("[RoomEditor] 已保存: %s" % path)


## 新建空房间：打开编辑场景并清空
func new_room() -> void:
	_open_editor_scene()
	call_deferred("_clear_for_new")


func _clear_for_new() -> void:
	var root := _get_editor_root()
	if root == null:
		return
	if root.has_method("refresh_grid"):
		root.refresh_grid(20, 15)
	RoomEditorCore.clear_tree(root)


## 应用尺寸变化
func resize_room(meta: Dictionary) -> void:
	var root := _get_editor_root()
	if root == null:
		return
	if root.has_method("refresh_grid"):
		root.refresh_grid(int(meta.get("width", 20)), int(meta.get("height", 15)))


# ============================================================
# 3D 视口输入处理
# ============================================================

## 拦截 3D 视口鼠标事件（EditorPlugin API）
func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	var result := AFTER_GUI_INPUT_PASS
	var root := _get_editor_root()
	if root == null:
		return result  # 没有打开编辑场景，不拦截

	# 键盘快捷键
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		# 数字 1-8 切换工具
		if key >= KEY_1 and key <= KEY_8:
			_set_tool_by_index(key - KEY_1)
			return AFTER_GUI_INPUT_STOP
		# P 键取点（坐标放置：填入当前悬停格坐标）
		if key == KEY_P:
			_pick_hover_cell()
			return AFTER_GUI_INPUT_STOP
		# R 旋转墙-格内朝向
		if key == KEY_R and _current_tool == RoomEditorCore.Tool.WALL_CELL:
			_wall_cell_direction = _rotate_direction(_wall_cell_direction)
			return AFTER_GUI_INPUT_STOP

	if not (event is InputEventMouseButton) and not (event is InputEventMouseMotion):
		return result

	# 鼠标位置 → 世界坐标 → 格子坐标
	var world_pos := _mouse_to_world(viewport_camera, event)
	if world_pos == null:
		_hover_cell = Vector2i(-1, -1)
		return result
	var cell := RoomEditorCore.world_to_cell(world_pos)

	# 钳制到房间范围：视口里房间外也能点，不钳制会画出越界格子，
	# 保存后运行时不做钳制 → 地板渲染到房间外面
	var editor_root := _get_editor_root()
	if editor_root and "room_width" in editor_root:
		cell = RoomEditorCore.clamp_cell(
			cell, int(editor_root.room_width), int(editor_root.room_height)
		)

	# 更新悬停状态（预览光标用）
	_hover_cell = cell
	_hover_world_pos = world_pos
	if _current_tool in [RoomEditorCore.Tool.WALL_EDGE, RoomEditorCore.Tool.DOOR]:
		_hover_direction = RoomEditorCore.edge_direction_at(world_pos, cell)
	else:
		_hover_direction = ""

	# 鼠标按键
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_painting = mb.pressed
			if mb.pressed:
				_last_paint_cell = Vector2i(-1, -1)
				if _current_tool in [RoomEditorCore.Tool.WALL_LINE, RoomEditorCore.Tool.RECT_FILL]:
					_line_start_cell = cell  # 拖线/矩形填充起点
				else:
					_apply_brush(root, world_pos, cell, mb.button_index)
			else:
				# 松开：完成矩形填充 / 拖线
				if _current_tool == RoomEditorCore.Tool.RECT_FILL and _line_start_cell.x >= 0:
					_commit_rect_fill(root, _line_start_cell, cell)
				_line_start_cell = Vector2i(-1, -1)
			result = AFTER_GUI_INPUT_STOP
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_erasing = mb.pressed
			if mb.pressed:
				_last_paint_cell = Vector2i(-1, -1)
				# 右键：矩形填充模式下拖框清除，其他模式直接擦
				if _current_tool == RoomEditorCore.Tool.RECT_FILL:
					_line_start_cell = cell
				else:
					_apply_brush(root, world_pos, cell, mb.button_index)
			else:
				if _current_tool == RoomEditorCore.Tool.RECT_FILL and _line_start_cell.x >= 0:
					_commit_rect_clear(root, _line_start_cell, cell)
				_line_start_cell = Vector2i(-1, -1)
			result = AFTER_GUI_INPUT_STOP

	# 鼠标移动（拖动绘制/擦除）
	elif event is InputEventMouseMotion:
		if cell != _last_paint_cell:
			_last_paint_cell = cell
			if _is_painting and _current_tool == RoomEditorCore.Tool.WALL_LINE:
				# 拖线模式：从起点到当前格画 L 形墙排
				_paint_wall_line(root, _line_start_cell, cell)
			elif _is_painting and _current_tool != RoomEditorCore.Tool.RECT_FILL:
				_apply_brush(root, world_pos, cell, MOUSE_BUTTON_LEFT)
			elif _is_erasing and _current_tool != RoomEditorCore.Tool.RECT_FILL:
				# 右键拖动连续擦除
				_apply_brush(root, world_pos, cell, MOUSE_BUTTON_RIGHT)
		if _is_painting or _is_erasing:
			result = AFTER_GUI_INPUT_STOP

	return result


## 数字键切工具（同步 dock 按钮状态）
func _set_tool_by_index(tool_idx: int) -> void:
	_current_tool = tool_idx
	# 同步 dock 工具按钮高亮
	if _room_dock and _room_dock.has_method("highlight_tool"):
		_room_dock.highlight_tool(tool_idx)


## 提交矩形填充
func _commit_rect_fill(root: Node3D, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var op := RoomEditorCore.fill_rect_floor(root, from_cell, to_cell, _floor_type)
	_commit_brush_action(op)


## 提交矩形清除
func _commit_rect_clear(root: Node3D, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var op := RoomEditorCore.clear_rect_floor(root, from_cell, to_cell)
	_commit_brush_action(op)


## 应用笔刷（按当前工具），结果提交到撤销/重做栈
func _apply_brush(root: Node3D, world_pos: Vector3, cell: Vector2i, button: int) -> void:
	var is_erase := button == MOUSE_BUTTON_RIGHT
	var op := {}  # 操作记录
	match _current_tool:
		RoomEditorCore.Tool.FLOOR:
			if is_erase:
				op = RoomEditorCore.erase_cell(root, cell)
			else:
				op = RoomEditorCore.paint_floor(root, cell, _floor_type)
		RoomEditorCore.Tool.RECT_FILL:
			pass  # 拖框在 _commit_rect_fill 处理
		RoomEditorCore.Tool.WALL_EDGE:
			var dir := RoomEditorCore.edge_direction_at(world_pos, cell)
			if is_erase:
				op = RoomEditorCore.erase_wall(root, cell, dir)
			else:
				op = RoomEditorCore.paint_wall(root, cell, dir)
		RoomEditorCore.Tool.WALL_CELL:
			if is_erase:
				op = RoomEditorCore.erase_cell(root, cell)
			else:
				op = RoomEditorCore.paint_wall(root, cell, _wall_cell_direction)
		RoomEditorCore.Tool.WALL_LINE:
			# 拖线在 mouse motion 里处理
			pass
		RoomEditorCore.Tool.DOOR:
			var dir := RoomEditorCore.edge_direction_at(world_pos, cell)
			if is_erase:
				op = RoomEditorCore.erase_cell(root, cell)
			else:
				op = RoomEditorCore.paint_door(root, cell, dir)
		RoomEditorCore.Tool.SPAWN:
			if is_erase:
				op = RoomEditorCore.erase_cell(root, cell)
			else:
				op = RoomEditorCore.paint_spawn(root, cell, _spawn_type, _spawn_monster_id)
		RoomEditorCore.Tool.ERASER:
			op = RoomEditorCore.erase_cell(root, cell)
	_commit_brush_action(op)


## 自动围墙（dock 调用）
func auto_walls(meta: Dictionary) -> Dictionary:
	var root := _get_editor_root()
	if root == null:
		return {"msg": "没有打开的编辑场景"}
	var op := RoomEditorCore.auto_walls(
		root, int(meta.get("width", 20)), int(meta.get("height", 15))
	)
	_commit_brush_action(op)
	return op


## 校验房间（dock 调用）
func validate_room(meta: Dictionary) -> Array:
	var root := _get_editor_root()
	if root == null:
		return ["没有打开的编辑场景"]
	return RoomEditorCore.validate_room(root, meta)


# ============================================================
# 坐标放置（面板坐标输入 + P 键视口取点）
# ============================================================

## 单点放置（dock 坐标放置区调用）
## element: "floor" / "wall" / "door" / "spawn"
func place_at_coord(
	cell: Vector2i, element: String, direction: String = "north",
	tile_type: String = "stone", spawn_type: String = "enemy_spawn",
	monster_id: String = ""
) -> Dictionary:
	var root := _get_editor_root()
	if root == null:
		return {"ok": false, "msg": "没有打开的编辑场景"}
	# 钳制到房间范围
	var clamped := RoomEditorCore.clamp_cell(
		cell, _room_width(), _room_height()
	)
	var op := RoomEditorCore.place_single(
		root, clamped, element, direction, tile_type, spawn_type, monster_id
	)
	_commit_brush_action(op)
	var clamped_note := "" if clamped == cell else "（坐标已钳制 %d,%d）" % [clamped.x, clamped.y]
	return {"ok": true, "msg": "已放置 %s 于 (%d,%d)%s" % [element, clamped.x, clamped.y, clamped_note]}


## 矩形放置（dock 坐标放置区调用）
## 地板=铺满矩形；墙=四条边墙圈；门/刷怪点=对角两点
func place_rect_at_coords(
	from_cell: Vector2i, to_cell: Vector2i, element: String,
	direction: String = "north", tile_type: String = "stone",
	spawn_type: String = "enemy_spawn", monster_id: String = ""
) -> Dictionary:
	var root := _get_editor_root()
	if root == null:
		return {"ok": false, "msg": "没有打开的编辑场景"}
	var f := RoomEditorCore.clamp_cell(from_cell, _room_width(), _room_height())
	var t := RoomEditorCore.clamp_cell(to_cell, _room_width(), _room_height())
	var op: Dictionary
	var count := 0
	match element:
		"floor":
			op = RoomEditorCore.fill_rect_floor(root, f, t, tile_type)
		"wall":
			op = RoomEditorCore.place_wall_rect(root, f, t)
		"door":
			# 对角点门：from 用指定朝向，to 用相同朝向（调用方可两次单点放不同朝向）
			op = RoomEditorCore.place_corners(root, f, t, "door", direction, direction)
		"spawn":
			op = RoomEditorCore.place_corners(
				root, f, t, "spawn", direction, direction, spawn_type, monster_id
			)
		_:
			return {"ok": false, "msg": "未知元素类型"}
	count = op.get("added", []).size()
	_commit_brush_action(op)
	return {"ok": true, "msg": "已生成 %s 矩形 (%d,%d)~(%d,%d)：新增 %d 个" % [
		element, f.x, f.y, t.x, t.y, count]}


## 当前编辑房间尺寸（从编辑场景根读取）
func _room_width() -> int:
	var root := _get_editor_root()
	if root and "room_width" in root:
		return int(root.room_width)
	return 20


func _room_height() -> int:
	var root := _get_editor_root()
	if root and "room_height" in root:
		return int(root.room_height)
	return 15


## P 键取点：把当前悬停格坐标发给 dock 填入输入框
func _pick_hover_cell() -> void:
	if _hover_cell.x < 0:
		return
	if _room_dock and _room_dock.has_method("fill_coord_from_pick"):
		_room_dock.fill_coord_from_pick(_hover_cell)


## 提交笔刷操作到 EditorUndoRedoManager
func _commit_brush_action(op: Dictionary) -> void:
	if op.is_empty():
		return
	var ur := get_editor_interface().get_editor_undo_redo()
	var added: Array = op.get("added", [])
	var removed: Array = op.get("removed", [])
	if added.is_empty() and removed.is_empty():
		return
	ur.create_action("编辑房间笔刷")
	# 新增的节点：do=已添加（空操作，core 已执行），undo=移除
	for node: Node in added:
		var n: Node = node
		var parent: Node = n.get_parent()
		ur.add_do_method(self, "_noop")
		ur.add_undo_method(parent, "remove_child", n)
	# 删除的节点：do=已移除（空操作，core 已执行），undo=重新添加
	for entry: Dictionary in removed:
		var node: Node = entry["node"]
		var parent: Node = entry["parent"]
		ur.add_do_method(self, "_noop")
		ur.add_undo_method(parent, "add_child", node)
	ur.commit_action()


func _noop() -> void:
	pass


## 拖线画墙：从 start 到 end 的 L 形路径（先横后纵），墙朝向按线段方向
## 合并为单个 undo action
func _paint_wall_line(root: Node3D, start: Vector2i, end: Vector2i) -> void:
	if start.x < 0 or start.y < 0:
		return
	var all_added: Array = []
	# 第一段：横向（墙朝 north，沿 x 推进）
	var x0 := mini(start.x, end.x)
	var x1 := maxi(start.x, end.x)
	for x in range(x0, x1 + 1):
		var op := RoomEditorCore.paint_wall(root, Vector2i(x, start.y), "north")
		all_added.append_array(op.get("added", []))
	# 第二段：纵向（墙朝 west，沿 y 推进）
	var y0 := mini(start.y, end.y)
	var y1 := maxi(start.y, end.y)
	for y in range(y0, y1 + 1):
		var op := RoomEditorCore.paint_wall(root, Vector2i(end.x, y), "west")
		all_added.append_array(op.get("added", []))
	_commit_brush_action({"added": all_added, "removed": []})


## 旋转方向（R 键）：N→E→S→W→N
func _rotate_direction(dir: String) -> String:
	match dir:
		"north":
			return "east"
		"east":
			return "south"
		"south":
			return "west"
		"west":
			return "north"
	return "north"


## 鼠标事件 → 世界坐标（射线与 y=0 平面求交）
func _mouse_to_world(camera: Camera3D, event: InputEvent) -> Variant:
	# 获取 SubViewportContainer 处理半分辨率
	var vpc := camera.get_parent().get_parent()
	var mouse_pos: Vector2
	if vpc and vpc.has_method("get_local_mouse_position"):
		mouse_pos = vpc.get_local_mouse_position()
		if vpc.get("stretch_shrink") == 2:
			mouse_pos /= 2.0
	else:
		mouse_pos = event.position if event is InputEventMouse else Vector2.ZERO

	var origin := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	if dir.y >= 0:  # 射线向上或水平，不与地面相交
		return null
	var t := -origin.y / dir.y
	return origin + t * dir


# ============================================================
# 视口叠加绘制（笔刷预览）
# ============================================================

## 在视口上绘制笔刷预览光标（高亮当前悬停格子/边缘）
func _forward_3d_draw_over_viewport(viewport_control: Control) -> void:
	var root := _get_editor_root()
	if root == null or _hover_cell.x < 0:
		return
	var vp := get_editor_interface().get_editor_viewport_3d()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return

	var center := RoomEditorCore.cell_to_world(_hover_cell)
	var color := _brush_preview_color()
	# 画格子高亮方框（四个角投影到屏幕）
	_draw_cell_box(viewport_control, cam, center, color)

	# 墙-边缘/门模式：高亮对应边缘
	if _hover_direction != "":
		_draw_edge_highlight(viewport_control, cam, _hover_cell, _hover_direction, color)


## 笔刷预览颜色（按当前工具）
func _brush_preview_color() -> Color:
	match _current_tool:
		RoomEditorCore.Tool.FLOOR:
			return Color(0.3, 0.8, 0.3, 0.7)
		RoomEditorCore.Tool.RECT_FILL:
			return Color(0.3, 0.6, 0.9, 0.7)
		RoomEditorCore.Tool.WALL_EDGE, RoomEditorCore.Tool.WALL_CELL, RoomEditorCore.Tool.WALL_LINE:
			return Color(0.8, 0.3, 0.3, 0.7)
		RoomEditorCore.Tool.DOOR:
			return Color(0.8, 0.6, 0.2, 0.7)
		RoomEditorCore.Tool.SPAWN:
			return Color(0.9, 0.2, 0.9, 0.7)
		RoomEditorCore.Tool.ERASER:
			return Color(0.9, 0.2, 0.2, 0.7)
	return Color(1, 1, 1, 0.5)


## 画格子高亮方框（四个3D角投影到屏幕画线）
func _draw_cell_box(control: Control, cam: Camera3D, center: Vector3, color: Color) -> void:
	var s := RoomEditorCore.CELL_SIZE * 0.5
	# 格子四角（y 略高于地面避免被地板遮挡）
	var p1 := cam.unproject_position(center + Vector3(-s, 0.05, -s))
	var p2 := cam.unproject_position(center + Vector3(s, 0.05, -s))
	var p3 := cam.unproject_position(center + Vector3(s, 0.05, s))
	var p4 := cam.unproject_position(center + Vector3(-s, 0.05, s))
	control.draw_line(p1, p2, color, 2.0)
	control.draw_line(p2, p3, color, 2.0)
	control.draw_line(p3, p4, color, 2.0)
	control.draw_line(p4, p1, color, 2.0)


## 画格子边缘高亮（墙/门放置位置）
func _draw_edge_highlight(
	control: Control, cam: Camera3D, cell: Vector2i, direction: String, color: Color
) -> void:
	var s := RoomEditorCore.CELL_SIZE * 0.5
	var center := RoomEditorCore.cell_to_world(cell)
	var p1 := center
	var p2 := center
	match direction:
		"north":
			p1 = center + Vector3(-s, 0.1, -s)
			p2 = center + Vector3(s, 0.1, -s)
		"south":
			p1 = center + Vector3(-s, 0.1, s)
			p2 = center + Vector3(s, 0.1, s)
		"west":
			p1 = center + Vector3(-s, 0.1, -s)
			p2 = center + Vector3(-s, 0.1, s)
		"east":
			p1 = center + Vector3(s, 0.1, -s)
			p2 = center + Vector3(s, 0.1, s)
	var sp1 := cam.unproject_position(p1)
	var sp2 := cam.unproject_position(p2)
	control.draw_line(sp1, sp2, color, 4.0)


# ============================================================
# 辅助
# ============================================================

## 打开编辑场景（若当前不是）
func _open_editor_scene() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root != null and root.name == "RoomEditorRoot":
		return  # 已经是编辑场景
	get_editor_interface().open_scene_from_path(ROOM_EDITOR_SCENE)


## 获取当前编辑场景根（仅当是 RoomEditorRoot 时返回）
func _get_editor_root() -> Node3D:
	var root := get_editor_interface().get_edited_scene_root()
	if root != null and root.name == "RoomEditorRoot":
		return root
	return null
