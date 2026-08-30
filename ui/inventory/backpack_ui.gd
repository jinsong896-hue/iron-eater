class_name BackpackUI
extends CanvasLayer
## 背包主界面 —— 网格 + 拖拽交换 + 右键菜单
## 对接 GameManager.equipment_manager 的 EquipmentInstance 列表
## Tab 键开关，EventBus.inventory_changed 驱动刷新

const ITEM_SCENE := preload("res://ui/inventory/backpack_item.tscn")
const CAPACITY := 40  # 背包容量（8列 × 5行）
const COLUMNS := 8

var _grids: Array[BackpackItem] = []
var _menu: BackpackMenu


func _ready() -> void:
	_menu = $Menu
	_build_grid()
	# 连接库存变化信号
	if EventBus != null:
		EventBus.inventory_changed.connect(_refresh)
	_refresh()


## 构建格子网格
func _build_grid() -> void:
	var grid := $SafeZone/Panel/Margin/VBox/Scroll/Grid
	grid.columns = COLUMNS
	for i in range(CAPACITY):
		var n := ITEM_SCENE.instantiate() as BackpackItem
		n.index = i
		n.swap_requested.connect(_on_swap_requested)
		n.menu_requested.connect(_on_menu_requested)
		_grids.push_back(n)
		grid.add_child(n)


## 从装备管理器刷新所有格子
func _refresh() -> void:
	var inventory: Array = []
	if GameManager != null and GameManager.equipment_manager != null:
		inventory = GameManager.equipment_manager.get_inventory()
	# 填充前 N 格
	for i in range(_grids.size()):
		if i < inventory.size():
			_grids[i].item = inventory[i]
		else:
			_grids[i].clear()


## 拖拽交换：交换两格的物品
func _on_swap_requested(from: int, to: int) -> void:
	GameManager.equipment_manager.swap_items(from, to)


## 右键菜单弹出
func _on_menu_requested(idx: int, screen_pos: Vector2) -> void:
	if idx < 0 or idx >= _grids.size():
		return
	if not _grids[idx].has_item():
		return
	var item: EquipmentInstance = _grids[idx].item
	_menu.set_lock_state(item.is_locked)
	_menu.show_at(screen_pos, idx)


## 菜单操作
func _on_action_requested(action: String, idx: int) -> void:
	if idx < 0 or idx >= _grids.size() or not _grids[idx].has_item():
		return
	var item: EquipmentInstance = _grids[idx].item
	match action:
		"equip":
			_try_equip(item)
		"devour":
			GameManager.devour_item(item)
		"lock":
			item.is_locked = not item.is_locked
			_refresh()
		"drop":
			GameManager.equipment_manager.remove_item(item)


## 尝试穿戴（按物品槽位类型）
func _try_equip(item: EquipmentInstance) -> void:
	var template := item.get_template()
	if template == null:
		return
	GameManager.equipment_manager.equip(template.slot_category, item)


## Tab 键开关
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory") and not visible:
		_open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_inventory") and visible:
		_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and visible:
		_close()
		get_viewport().set_input_as_handled()


## 打开背包
func _open() -> void:
	get_tree().paused = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


## 关闭背包
func _close() -> void:
	_menu.hide()
	visible = false
	get_tree().paused = false
