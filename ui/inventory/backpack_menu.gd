class_name BackpackMenu
extends Control
## 背包右键菜单 —— 弹窗式
## 操作：穿戴/吞噬/锁定·解锁/丢弃
## 具体逻辑由 backpack_ui 接收信号后对接 EquipmentManager

signal action_requested(action: String, index: int)

var selected_index: int = -1


func _input(event: InputEvent) -> void:
	# 点击外部关闭菜单
	if visible and event is InputEventMouseButton and not event.pressed:
		var rect := Rect2(global_position, size)
		if not rect.has_point(event.position):
			hide()


## 弹出菜单到指定屏幕位置
func show_at(pos: Vector2, idx: int) -> void:
	selected_index = idx
	global_position = pos
	show()


## 设置锁定按钮文字（由 backpack_ui 按物品实际状态调用）
func set_lock_state(is_locked: bool) -> void:
	var btn := get_node_or_null("VBox/LockBtn") as Button
	if btn:
		btn.text = "解锁" if is_locked else "锁定"


func _on_equip_pressed() -> void:
	action_requested.emit("equip", selected_index)
	hide()


func _on_devour_pressed() -> void:
	action_requested.emit("devour", selected_index)
	hide()


func _on_lock_pressed() -> void:
	action_requested.emit("lock", selected_index)
	hide()


func _on_drop_pressed() -> void:
	action_requested.emit("drop", selected_index)
	hide()
