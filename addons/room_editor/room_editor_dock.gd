@tool
extends Control
## 房间编辑器底部面板 —— 调用 RoomEditor 节点的公开方法

const SAVE_DIR := "res://rooms/editor/saved"

var _editor_interface: EditorInterface = null

@onready var _name_input: LineEdit = $Main/NameBox/NameInput
@onready var _type_opt: OptionButton = $Main/TypeBox/TypeOption
@onready var _min_spin: SpinBox = $Main/EnemyBox/EnemyRow/MinEnemy
@onready var _max_spin: SpinBox = $Main/EnemyBox/EnemyRow/MaxEnemy
@onready var _room_list: ItemList = $Main/RoomList
@onready var _status: Label = $Main/Status


func _ready() -> void:
	_refresh_list()
	_show("就绪：打开 room_editor.tscn → 画瓦片 → 点保存")


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface


func _root() -> Node2D:
	if _editor_interface == null:
		return null
	return _editor_interface.get_edited_scene_root() as Node2D


func _show(msg: String) -> void:
	_status.text = msg
	print("[RoomEditor] ", msg)


func _refresh_list() -> void:
	_room_list.clear()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			_room_list.add_item(f.trim_suffix(".tres"))
		f = dir.get_next()
	dir.list_dir_end()


func _on_list_activated(_idx: int) -> void:
	_on_load_pressed()


## ---- 按钮 ----

func _on_new_pressed() -> void:
	var root := _root()
	if root == null:
		_show("错误：请先打开 room_editor.tscn")
		return
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("错误：请输入房间名")
		return
	root.new_room(name_str)
	_show("已新建 %s.tres，现在画瓦片" % name_str)
	_refresh_list()


func _on_save_pressed() -> void:
	var root := _root()
	if root == null:
		_show("错误：请先打开 room_editor.tscn")
		return
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("错误：请输入房间名")
		return
	root.save_room(name_str, _type_opt.selected, int(_min_spin.value), int(_max_spin.value))
	_show("已保存 %s.tres" % name_str)
	_refresh_list()


func _on_load_pressed() -> void:
	var sel := _room_list.get_selected_items()
	if sel.is_empty():
		_show("请先在列表中双击一个房间")
		return
	var name_str := _room_list.get_item_text(sel[0])
	var root := _root()
	if root == null:
		return
	root.load_room(name_str)
	_name_input.text = name_str
	# 从文件读取类型和敌人数
	var path := SAVE_DIR + "/" + name_str + ".tres"
	var data: Resource = load(path)
	if data:
		_type_opt.select(int(data.get("room_type")))
		_min_spin.value = float(data.get("min_enemies"))
		_max_spin.value = float(data.get("max_enemies"))
	_show("已加载 %s" % name_str)


func _on_clear_pressed() -> void:
	var root := _root()
	if root == null:
		return
	root.clear_all()
	_show("已清空")


func _on_next_pressed() -> void:
	_on_clear_pressed()
	var num := 1
	var old := _name_input.text.strip_edges()
	if old.begins_with("room_"):
		num = int(old.trim_prefix("room_")) + 1
	_name_input.text = "room_%02d" % num
	_show("已清空，准备画新房间：%s" % _name_input.text)


func _on_fill_pressed() -> void:
	var root := _root()
	if root == null:
		_show("错误：请先打开 room_editor.tscn")
		return
	root.fill_floor()
	_show("已填充地板 16×12")
