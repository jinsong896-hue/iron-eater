class_name StatOrb
extends Control
## 圆形资源球（代码绘制）：HP 红球 / MP 蓝球，带平滑液面下降与数值文本

@export var orb_color := Color(0.78, 0.16, 0.18)
@export var orb_title := "生命"

var value := 1.0
var max_value := 1.0
var _display := 1.0
var _display_max := 1.0
var _label: Label

const BG := Color(0.10, 0.10, 0.13)
const RIM := Color(0.32, 0.32, 0.36)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	add_child(_label)
	resized.connect(_layout_label)
	_layout_label()


func set_stats(current: float, maximum: float) -> void:
	value = maxf(current, 0.0)
	max_value = maxf(maximum, 0.0001)
	queue_redraw()
	_update_label()


func _process(delta: float) -> void:
	_display = lerpf(_display, value, clampf(delta * 10.0, 0.0, 1.0))
	_display_max = lerpf(_display_max, max_value, clampf(delta * 10.0, 0.0, 1.0))
	if absf(_display - value) < 0.01 and absf(_display_max - max_value) < 0.01:
		_display = value
		_display_max = max_value
	queue_redraw()
	_update_label()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var ratio := clampf(_display / _display_max, 0.0, 1.0)
	# 背景
	draw_circle(c, r, BG)
	# 液面填充（圆与 y >= top_y 半平面的交集）
	if ratio > 0.0:
		var fill_r := r - 2.0
		var top_y := c.y + fill_r - fill_r * 2.0 * ratio
		if ratio >= 0.999:
			draw_circle(c, fill_r, orb_color)
		else:
			var dy := top_y - c.y
			if dy < fill_r:  # 液面在圆心以下（或以上但未满）
				var half_w := sqrt(maxf(fill_r * fill_r - dy * dy, 0.0))
				var left := Vector2(c.x - half_w, top_y)
				var right := Vector2(c.x + half_w, top_y)
				var pts := PackedVector2Array()
				pts.append(left)
				var steps := 28
				for i in range(steps + 1):
					var x := lerpf(left.x, right.x, float(i) / steps)
					var dx := x - c.x
					pts.append(Vector2(x, c.y + sqrt(maxf(fill_r * fill_r - dx * dx, 0.0))))
				pts.append(right)
				draw_colored_polygon(pts, orb_color)
				# 液面亮线
				draw_line(left, right, orb_color.lightened(0.45), 1.5)
	# 描边
	draw_arc(c, r, 0.0, TAU, 48, RIM, 2.0)
	# 顶部高光
	draw_arc(c + Vector2(0, -r * 0.25), r * 0.6, PI * 1.05, PI * 1.95, 20, Color(1, 1, 1, 0.15), 2.0)


func _update_label() -> void:
	_label.text = "%s\n%d / %d" % [orb_title, int(ceil(value)), int(max_value)]


func _layout_label() -> void:
	if _label == null:
		return
	_label.position = Vector2(0, size.y * 0.34)
	_label.size = Vector2(size.x, 40)
