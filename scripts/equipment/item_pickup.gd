class_name ItemPickup
extends Area2D
## 掉落物：靠近自动拾取

var item: EquipmentInstance


func _ready() -> void:
	add_to_group("pickups")
	body_entered.connect(_on_body_entered)
	queue_redraw()


func _draw() -> void:
	var pts := PackedVector2Array([
		Vector2(0, -12), Vector2(12, 0), Vector2(0, 12), Vector2(-12, 0),
	])
	draw_colored_polygon(pts, Color(0.95, 0.72, 0.2))
	# 稀有度圆点（6 档色，索引越界时安全回落）
	draw_circle(Vector2.ZERO, 5.0, EquipmentDefs.rarity_color(item.rarity))


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		GameState.equipment_manager.add_item(item)
		EventBus.inventory_changed.emit()
		EventBus.message.emit("拾取：%s（%s）" % [item.display_name(), item.rarity_name()])
		AudioManager.play("pickup")
		queue_free()
