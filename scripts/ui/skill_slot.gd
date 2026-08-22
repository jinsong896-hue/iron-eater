class_name SkillSlot
extends Button
## 技能槽（代码绘制）：元素底色 + 冷却遮罩 + 快捷键角标
## 技能数据来自 GameBalance.DEMO_SKILLS（Q/W/E）

var skill_data: Dictionary = {}
var cooldown := 0.0
var cooldown_total := 0.0


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	# 空样式框，避免 Button 默认主题背景覆盖自绘
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty)
	add_theme_stylebox_override("hover", empty)
	add_theme_stylebox_override("pressed", empty)
	add_theme_stylebox_override("disabled", empty)
	add_theme_stylebox_override("focus", empty)
	var key_label := Label.new()
	key_label.name = "KeyLabel"
	key_label.position = Vector2(4, 2)
	key_label.add_theme_font_size_override("font_size", 12)
	key_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	key_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	key_label.add_theme_constant_override("outline_size", 3)
	add_child(key_label)


func setup(data: Dictionary) -> void:
	skill_data = data
	tooltip_text = "%s [%s]\n%s\n冷却 %.1fs" % [
		data.get("name", ""), data.get("key", ""), data.get("desc", ""), data.get("cooldown", 0.0)]
	var key_label := get_node_or_null("KeyLabel") as Label
	if key_label:
		key_label.text = str(data.get("key", ""))


func start_cooldown(duration: float) -> void:
	cooldown = duration
	cooldown_total = duration
	disabled = true
	queue_redraw()


func _process(delta: float) -> void:
	if cooldown <= 0.0:
		return
	cooldown = maxf(cooldown - delta, 0.0)
	queue_redraw()
	if cooldown <= 0.0:
		disabled = false


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.10, 0.10, 0.13))
	var element: String = skill_data.get("element", "")
	var color: Color = GameBalance.ELEMENT_COLORS.get(element, Color(0.45, 0.45, 0.5))
	draw_rect(r.grow(-2.0), color.darkened(0.35))
	if cooldown > 0.0 and cooldown_total > 0.0:
		var mask_h := size.y * (cooldown / cooldown_total)
		draw_rect(Rect2(0, 0, size.x, mask_h), Color(0, 0, 0, 0.72))
	draw_rect(r, Color(0.32, 0.32, 0.36), false, 1.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
