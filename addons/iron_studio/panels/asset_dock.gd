@tool
extends Control
## 资源浏览器 —— 扫描项目美术资源
## 文档：ai/框架相关.md Asset Browser

const SCAN_DIRS := [
	"res://assets",
	"res://material",
	"res://rooms",
]

@onready var _tree: Tree = $Main/Left/Tree
@onready var _preview: Label = $Main/Right/Preview
@onready var _info: Label = $Main/Right/Info
@onready var _status: Label = $Main/Right/Status


func _ready() -> void:
	_scan()


func _scan() -> void:
	_tree.clear()
	var root := _tree.create_item()
	root.set_text(0, "Assets")
	for dir_path in SCAN_DIRS:
		_scan_dir(dir_path, root)
	_show("扫描完成")


func _scan_dir(path: String, parent: TreeItem) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	var item := _tree.create_item(parent)
	item.set_text(0, path.replace("res://", ""))
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not f.begins_with("."):
			var child := _tree.create_item(item)
			child.set_text(0, f)
			child.set_metadata(0, path + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()


func _on_tree_selected() -> void:
	var item := _tree.get_selected()
	if item == null: return
	var path: String = item.get_metadata(0)
	if path == null: return
	_preview.text = "选中: %s" % path
	var info := ""
	if path.ends_with(".png") or path.ends_with(".jpg"):
		info = "类型: 纹理"
	elif path.ends_with(".gd"):
		info = "类型: 脚本"
	elif path.ends_with(".tscn"):
		info = "类型: 场景"
	elif path.ends_with(".tres"):
		info = "类型: 资源"
	elif path.ends_with(".glb") or path.ends_with(".fbx"):
		info = "类型: 3D模型"
	_info.text = info


func _show(msg: String) -> void:
	_status.text = msg
	print("[AssetBrowser] ", msg)


func _on_refresh_pressed() -> void:
	_scan()
