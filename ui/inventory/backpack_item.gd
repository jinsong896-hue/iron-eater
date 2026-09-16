class_name BackpackItem
extends Button
## 背包格子 —— 显示一件 EquipmentInstance
## 用稀有度颜色块+装备名首字代替图标（项目装备模板暂无图标字段）
## 支持拖拽交换和右键菜单

signal swap_requested(from: int, to: int)
signal menu_requested(index: int, screen_pos: Vector2)
signal item_clicked(index: int)

## 当前格子的装备实例（null=空格）
var item: EquipmentInstance = null:
	set(value):
		item = value
		_update_display()

var index: int = -1

## 装备槽名称（仅"装备栏"里的格子设置；空槽时显示它，
## 让玩家一眼看出这格该放什么，而不是一片空白）。
var _slot_name: String = ""

@onready var _color_rect: ColorRect = $ColorRect
@onready var _name_label: Label = $NameLabel


## 标记本格为装备槽（显示槽位名）
func set_slot_label(slot_label: String) -> void:
	_slot_name = slot_label
	_update_display()


func _ready() -> void:
	pressed.connect(_on_pressed)
	_update_display()


## 左键按下：发出选中信号
func _on_pressed() -> void:
	if has_item():
		item_clicked.emit(index)


## 是否有物品
func has_item() -> bool:
	return item != null


## 清空格子
func clear() -> void:
	item = null


## 更新显示（稀有度颜色块 + 装备名首字；装备槽空置时显示槽位名）
func _update_display() -> void:
	if _color_rect == null or _name_label == null:
		return
	if item == null:
		_name_label.text = _slot_name
		# 装备槽空置：暗底色 + 槽名用灰字提示"这里该放什么"
		if _slot_name.is_empty():
			_color_rect.color = Color(0.15, 0.15, 0.18, 1)
		else:
			_color_rect.color = Color(0.13, 0.13, 0.16, 1)
			_name_label.add_theme_font_size_override("font_size", 10)
			_name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		return
	# 有物品：恢复常规字号/字色（可能被上面的空槽分支改过）
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	# 稀有度颜色
	var template := item.get_template()
	var color := Color(0.5, 0.5, 0.5)
	if template != null:
		color = template.rarity_color()
	_color_rect.color = color
	# 装备名首字
	_name_label.text = item.display_name().substr(0, 1)


## 右键弹菜单（左键走 pressed 信号）
func _gui_input(event: InputEvent) -> void:
	if not has_item():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var screen_pos := global_position + mb.position
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
