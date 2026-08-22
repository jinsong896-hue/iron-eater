class_name DamagePopup
extends Label
## 伤害飘字：由 HUD 在 EventBus.damage_popup 时生成，上浮渐隐
## kind: "normal" 白 / "crit" 黄 / "player" 红

const COLORS := {
	"normal": Color(1.0, 1.0, 1.0),
	"crit": Color(1.0, 0.85, 0.25),
	"player": Color(1.0, 0.40, 0.35),
}

var _velocity := Vector2(0, -90.0)
var _age := 0.0
var _life := 0.8


func setup(world_pos: Vector2, amount: float, kind: String) -> void:
	text = "%d" % int(round(amount))
	if kind == "crit":
		text = "%d!" % int(round(amount))
	add_theme_font_size_override("font_size", 15 if kind != "crit" else 20)
	add_theme_color_override("font_color", COLORS.get(kind, COLORS["normal"]))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_theme_constant_override("outline_size", 4)
	position = _world_to_screen(world_pos)
	_velocity.x = randf_range(-24.0, 24.0)


func _world_to_screen(world_pos: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return world_pos
	var camera := viewport.get_camera_2d()
	var vp_size := viewport.get_visible_rect().size
	if camera == null:
		return world_pos
	var cam_center := camera.get_screen_center_position()
	return world_pos - cam_center + vp_size * 0.5


func _process(delta: float) -> void:
	_age += delta
	position += _velocity * delta
	modulate.a = clampf(1.0 - _age / _life, 0.0, 1.0)
	if _age >= _life:
		queue_free()
