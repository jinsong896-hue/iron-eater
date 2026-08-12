extends Control
## Loading 过渡页：《页面相关2.md》——世界观信息 + 进度条；进入地牢前短暂显示

const TIPS := [
	"铁锈并不是死亡，它只是另一种形式的生长。",
	"吞噬同一件装备，让它的力量成为你的骨与血。",
	"融合能叠加词条，但每一次尝试都需要金币。",
	"地牢越深，空气越沉重，也越接近深渊的真相。",
	"精英与 Boss 掉落的装备，往往藏着更强的词条。",
	"记忆残渣是局外成长的根本，击杀与深入都会带来它。",
]

var _title: Label
var _tip: Label
var _progress: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.custom_minimum_size = Vector2(520, 0)
	center.add_theme_constant_override("separation", 18)
	add_child(center)
	_title = Label.new()
	_title.text = "正在下潜……"
	_title.add_theme_font_size_override("font_size", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.modulate = Color(0.85, 0.55, 0.35)
	center.add_child(_title)
	_tip = Label.new()
	_tip.text = TIPS[randi() % TIPS.size()]
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.add_theme_font_size_override("font_size", 17)
	_tip.modulate = Color(0.75, 0.75, 0.75)
	center.add_child(_tip)
	_progress = Label.new()
	_progress.text = "生成地牢结构 ████░░░░░░"
	_progress.add_theme_font_size_override("font_size", 16)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_progress)
	visible = false


func begin() -> void:
	_tip.text = TIPS[randi() % TIPS.size()]
	_progress.text = "生成地牢结构 ████░░░░░░"
	visible = true


func set_progress(ratio: float) -> void:
	var filled := clampi(int(ratio * 20.0), 0, 20)
	_progress.text = "生成地牢结构 %s %d%%" % ["█".repeat(filled) + "░".repeat(20 - filled), int(ratio * 100.0)]


func end() -> void:
	visible = false
