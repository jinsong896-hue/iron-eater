extends CanvasLayer
## 小地图容器：《地图相关.md》——右上角面板

func _ready() -> void:
	layer = 120
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-300, 16)
	panel.custom_minimum_size = Vector2(260, 260)
	add_child(panel)
	var view := MinimapView.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(view)
