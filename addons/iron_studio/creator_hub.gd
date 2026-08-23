@tool
extends Control
## IronEater Creator Hub —— 统一编辑器入口

var _editor_interface: EditorInterface = null

# 编辑器列表：名称、场景路径、图标颜色
const EDITORS := [
	{"name": "角色编辑器", "scene": "res://addons/iron_studio/character_dock.tscn", "color": "4a90d9", "desc": "创建职业/形态/技能"},
	{"name": "装备编辑器", "scene": "res://addons/iron_studio/panels/equipment_dock.tscn", "color": "d94a4a", "desc": "武器/融合/词条"},
	{"name": "技能编辑器", "scene": "res://addons/iron_studio/panels/skill_dock.tscn", "color": "d9b84a", "desc": "效果组合/消耗/冷却"},
	{"name": "怪物编辑器", "scene": "res://addons/iron_studio/panels/monster_dock.tscn", "color": "4ad94a", "desc": "AI/进化/掉落"},
	{"name": "数值模拟器", "scene": "res://addons/iron_studio/panels/balance_dock.tscn", "color": "9a4ad9", "desc": "DPS/TTK/生存"},
	{"name": "资源浏览器", "scene": "res://addons/iron_studio/panels/asset_dock.tscn", "color": "4ad9d0", "desc": "项目资源扫描"},
	{"name": "Buff编辑器", "scene": "res://addons/iron_studio/panels/buff_dock.tscn", "color": "d96a4a", "desc": "Buff/Debuff"},
]

var _current_editor: Control = null

@onready var _content: Control = $Main/Content


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface


func _ready() -> void:
	_build_hub()


func _build_hub() -> void:
	# 清空内容区
	for child in _content.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.name = "Hub"
	vbox.add_theme_constant_override("separation", 12)
	_content.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "IronEater Creator"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "《噬铁者》游戏内容创作平台"
	sub.add_theme_font_size_override("font_size", 13)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	# 编辑器按钮网格
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	for ed in EDITORS:
		var btn := Button.new()
		btn.text = "%s\n%s" % [ed["name"], ed["desc"]]
		btn.custom_minimum_size = Vector2(160, 80)
		btn.add_theme_font_size_override("font_size", 13)
		btn.flat = false
		var c := Color(ed["color"])
		btn.add_theme_color_override("font_color", c)
		btn.pressed.connect(_launch_editor.bind(ed["scene"], ed["name"]))
		grid.add_child(btn)

	vbox.add_child(HSeparator.new())

	# 房间编辑器入口
	var room_btn := Button.new()
	room_btn.text = "房间编辑器 (独立打开)"
	room_btn.custom_minimum_size = Vector2(0, 40)
	room_btn.add_theme_font_size_override("font_size", 14)
	room_btn.pressed.connect(_open_room_editor)
	vbox.add_child(room_btn)

	# 状态
	var status := Label.new()
	status.text = "点击上方按钮打开对应编辑器"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	vbox.add_child(status)


func _launch_editor(scene_path: String, ed_name: String) -> void:
	# 清空内容区
	for child in _content.get_children():
		child.queue_free()

	# 添加返回按钮
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_content.add_child(vbox)

	var back_row := HBoxContainer.new()
	vbox.add_child(back_row)

	var back_btn := Button.new()
	back_btn.text = "< 返回主菜单"
	back_btn.pressed.connect(_build_hub)
	back_row.add_child(back_btn)

	var title := Label.new()
	title.text = ed_name
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_row.add_child(title)

	# 加载编辑器
	var scene: PackedScene = load(scene_path)
	if scene == null:
		print("[Hub] 加载失败: %s" % scene_path)
		return
	_current_editor = scene.instantiate()
	if _current_editor.has_method("setup"):
		_current_editor.setup(_editor_interface)
	elif _current_editor.has_method("_ready"):
		_current_editor._ready()
	vbox.add_child(_current_editor)
	print("[Hub] 已打开: %s" % ed_name)


func _open_room_editor() -> void:
	if _editor_interface:
		_editor_interface.set_main_screen_editor("2D")
		var scene := load("res://rooms/editor/room_editor.tscn")
		if scene:
			_editor_interface.open_scene_from_path("res://rooms/editor/room_editor.tscn")
		print("[Hub] 已打开房间编辑器")
