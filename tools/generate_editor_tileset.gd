extends SceneTree
## 生成编辑器瓦片集 .tres 文件（运行一次即可）
## 用法：Godot --headless --path . --script res://tools/generate_editor_tileset.gd
## 生成后可在 editor_tileset.tres 中修改 texture 路径替换为你的素材

func _init() -> void:
	var ts := TilesetFactory.get_tileset()
	if ts == null:
		print("错误：瓦片集构建失败")
		quit(1)
		return
	var path := "res://rooms/editor/editor_tileset.tres"
	var err := ResourceSaver.save(ts, path)
	if err == OK:
		print("瓦片集已生成：%s" % path)
		print("替换素材：在 Godot 中双击此文件，修改 Atlas 的 texture 路径即可")
		quit(0)
	else:
		print("保存失败：%d" % err)
		quit(1)
