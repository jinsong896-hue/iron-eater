extends SceneTree
## 编辑器工具：把 36 件白装模板保存为 .tres（数据仍以 white_equipment_data.gd 为准）
## 运行：godot --headless --path <项目> --script res://tools/generate_equipment_tres.gd


func _init() -> void:
	EquipmentDB.ensure_built()
	var dir := "res://data/equipment/templates/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var saved := 0
	for t in EquipmentDB.all_templates():
		var tpl: EquipmentTemplate = t
		var path: String = dir + tpl.id + ".tres"
		var err := ResourceSaver.save(t, path)
		if err == OK:
			saved += 1
		else:
			print("保存失败 %s：%s" % [t.id, error_string(err)])
	print("已生成 %d/36 件白装模板 .tres" % saved)
	quit(0)
