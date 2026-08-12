extends Node
## 三存档系统：《开始页面相关.md》十七/十八 —— user://save_01.json + .bak 备份 + .tmp 原子写入 + 版本迁移

const SAVE_VERSION := 1
const SLOT_COUNT := 3

var active_slot := 0   # 当前进入的存档槽（1~3），0 = 未进入
var active_save := {}  # 当前存档数据缓存


func slot_path(slot: int, ext := "json") -> String:
	return "user://save_%02d.%s" % [slot, ext]


func default_save(slot: int) -> Dictionary:
	var now := Time.get_datetime_string_from_system()
	return {
		"save_version": SAVE_VERSION,
		"save_revision": 1,
		"save_id": "slot_%02d" % slot,
		"create_time": now,
		"last_play_time": now,
		"total_play_time": 0.0,
		"progression": {
			"story_progress": 0,
			"highest_floor": 0,
			"highest_cleared_floor": 0,
			"unlocked_classes": ["warrior", "mage", "hunter", "judge", "monk"],
			"unlocked_forms": {},
			"talents": {},
		},
		"currencies": {"memory_fragments": 0},
		"current_run": {
			"active": false, "character": "", "mode": "", "difficulty": "",
			"floor": 1, "seed": 0, "run_data": {},
		},
		"run_history": [],
	}


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## 读取存档：主档损坏时自动回退 .bak
func load_save(slot: int) -> Dictionary:
	if has_save(slot):
		var data := _read_json(slot_path(slot))
		if not data.is_empty() and data.get("save_version", -1) == SAVE_VERSION:
			return _with_status(_migrate(data), "normal")
		var bak := _read_json(slot_path(slot, "bak"))
		if not bak.is_empty():
			return _with_status(_migrate(bak), "bak_recovered")
	return default_save(slot)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## 原子写入：.tmp → 备份旧主档 → 替换主档
func write_save(slot: int, data: Dictionary) -> void:
	data["save_revision"] = int(data.get("save_revision", 0)) + 1
	var tmp := slot_path(slot, "tmp")
	var main := slot_path(slot)
	var bak := slot_path(slot, "bak")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("存档写入失败：无法创建临时文件 %s" % tmp)
		return
	f.store_string(JSON.stringify(data))
	f.close()
	if FileAccess.file_exists(main):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(main), ProjectSettings.globalize_path(bak))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(main))


func create_save(slot: int) -> Dictionary:
	var data := default_save(slot)
	write_save(slot, data)
	return data


func delete_save(slot: int) -> void:
	for ext in ["json", "bak", "tmp"]:
		var p := slot_path(slot, ext)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if active_slot == slot:
		active_slot = 0
		active_save = {}


func enter_save(slot: int) -> Dictionary:
	active_slot = slot
	active_save = load_save(slot)
	return active_save


func save_active() -> void:
	if active_slot > 0:
		active_save["last_play_time"] = Time.get_datetime_string_from_system()
		write_save(active_slot, active_save)


func start_run(config: Dictionary) -> void:
	if active_slot <= 0:
		return
	var run: Dictionary = active_save.get("current_run", {})
	run["active"] = true
	run["character"] = config.get("character", "warrior")
	run["mode"] = config.get("mode", "dungeon")
	run["difficulty"] = config.get("difficulty", "normal")
	run["floor"] = config.get("floor", 1)
	run["seed"] = config.get("seed", 0)
	run["start_time"] = Time.get_ticks_msec()
	active_save["current_run"] = run
	save_active()


func update_run_floor(floor: int) -> void:
	if active_slot <= 0:
		return
	var run: Dictionary = active_save.get("current_run", {})
	if not run.get("active", false):
		return
	run["floor"] = floor
	active_save["current_run"] = run
	save_active()


func finish_run(result: Dictionary) -> void:
	if active_slot <= 0:
		return
	var run: Dictionary = active_save.get("current_run", {})
	var prog: Dictionary = active_save.get("progression", {})
	var floor: int = run.get("floor", 1)
	prog["highest_floor"] = maxi(int(prog.get("highest_floor", 0)), floor)
	if result.get("cleared_floor", 0) > 0:
		prog["highest_cleared_floor"] = maxi(int(prog.get("highest_cleared_floor", 0)), int(result["cleared_floor"]))
	active_save["progression"] = prog
	var currencies: Dictionary = active_save.get("currencies", {})
	currencies["memory_fragments"] = int(currencies.get("memory_fragments", 0)) + int(result.get("fragments", 0))
	active_save["currencies"] = currencies
	var history: Array = active_save.get("run_history", [])
	var record := result.duplicate()
	record["finish_time"] = Time.get_datetime_string_from_system()
	history.append(record)
	active_save["run_history"] = history
	active_save["current_run"] = {
		"active": false, "character": "", "mode": "", "difficulty": "",
		"floor": 1, "seed": 0, "run_data": {},
	}
	save_active()


func _migrate(data: Dictionary) -> Dictionary:
	# V1 起预留迁移入口：低版本字段缺失时补默认
	if not data.has("progression"):
		var slot := 1
		if str(data.get("save_id", "")).begins_with("slot_0"):
			slot = int(str(data["save_id"]).substr(5, 2))
		var merged := default_save(slot)
		for key in data:
			merged[key] = data[key]
		return merged
	return data


func _with_status(data: Dictionary, status: String) -> Dictionary:
	var meta: Dictionary = data.get("_meta", {})
	meta["load_status"] = status
	data["_meta"] = meta
	return data
