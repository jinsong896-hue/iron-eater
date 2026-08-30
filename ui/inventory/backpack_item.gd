class_name BackpackItem
extends Button
## 背包格子 —— 显示一件 EquipmentInstance
## 用稀有度颜色块+装备名首字代替图标（项目装备模板暂无图标字段）
## 支持拖拽交换和右键菜单

signal swap_requested(from: int, to: int)
signal menu_requested(index: int, screen_pos: Vector2)

## 当前格子的装备实例（null=空格）
var item: EquipmentInstance = null:
	set(value):
		item = value
		_update_display()

var index: int = -1

@onready var _color_rect: ColorRect = $ColorRect
@onready var _name_label: Label = $NameLabel


func _ready() -> void:
	_update_display()


## 是否有物品
func has_item() -> bool:
	return item != null


## 清空格子
func clear() -> void:
	item = null


## 更新显示（稀有度颜色块 + 装备名首字）
func _update_display() -> void:
	if _color_rect == null or _name_label == null:
		return
	if item == null:
		_color_rect.color = Color(0.15, 0.15, 0.18, 1)
		_name_label.text = ""
		return
	# 稀有度颜色
	var template := item.get_template()
	var color := Color(0.5, 0.5, 0.5)
	if template != null:
		color = template.rarity_color()
	_color_rect.color = color
	# 装备名首字
	_name_label.text = item.display_name().substr(0, 1)


## 右键弹菜单
func _gui_input(event: InputEvent) -> void:
	if not has_item():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var screen_pos := global_position + (event as InputEventMouseButton).position
			menu_requested.emit(index, screen_pos)


## 拖起物品
func _get_drag_data(_at_position: Vector2) -> Variant:
	if not has_item():
		return null
	# 拖拽预览：小色块
	var preview := ColorRect.new()
	preview.color = _color_rect.color
	preview.custom_minimum_size = Vector2(48, 48)
	set_drag_preview(preview)
	return {"from_index": index, "from_item": item}


## 允许放下
func _can_drop_data(_at_position: Vector2, _data: Variant) -> bool:
	return true


## 放下：触发交换
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var from := int(data["from_index"])
	if from != index:
		swap_requested.emit(from, index)
