class_name BackpackMenu
extends Control
## 背包右键菜单 —— 弹窗式，按页签动态显示操作项
## 操作分发由 backpack_ui 接收信号后对接 EquipmentManager

signal action_requested(action: String, index: int)

## 操作定义：action -> 显示文本
var ACTIONS := {
	"equip": "穿戴",
	"unequip": "卸下",
	"enhance": "强化",
	"devour": "吞噬",
	"fusion_source": "选为融合主装备",
	"fusion_material": "作为融合材料",
	"fusion_cancel": "取消融合选择",
	"lock": "锁定",
	"unlock": "解锁",
	"drop": "丢弃",
}

var selected_index: int = -1
var _vbox: VBoxContainer
var _actions: Array = []


func _ready() -> void:
	_vbox = $VBox
	hide()


func _input(event: InputEvent) -> void:
	# 点击外部关闭菜单
	if visible and event is InputEventMouseButton and not event.pressed:
		var rect := Rect2(global_position, size)
		if not rect.has_point(event.position):
			hide()


## 弹出菜单到指定屏幕位置，只显示指定操作
func show_actions(pos: Vector2, idx: int, actions: Array) -> void:
	selected_index = idx
	_actions = actions
	_rebuild_buttons(actions)
	global_position = pos
	show()


## 兼容旧接口：显示全部操作
func show_at(pos: Vector2, idx: int) -> void:
	show_actions(pos, idx, ACTIONS.keys())


## 设置锁定按钮文字（由 backpack_ui 按物品实际状态调用后重建）
func set_lock_state(is_locked: bool) -> void:
	ACTIONS["lock"] = "解锁" if is_locked else "锁定"
	_rebuild_buttons(_actions)


## 按操作列表重建按钮
func _rebuild_buttons(actions: Array) -> void:
	for child in _vbox.get_children():
		child.queue_free()
	for action in actions:
		var btn := Button.new()
		btn.text = ACTIONS.get(action, action)
		btn.pressed.connect(_on_action_pressed.bind(action))
		_vbox.add_child(btn)


## 操作按钮回调
func _on_action_pressed(action: String) -> void:
	action_requested.emit(action, selected_index)
	hide()
