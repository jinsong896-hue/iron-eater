extends Node
## 存档管理器 —— HD-2D 重构版
## 三存档槽 + .bak 备份 + 版本化 JSON
## 支持 current_run.active 判断"继续游戏"

const SAVE_DIR := "user://saves/"
const SAVE_EXTENSION := ".sav"
const MAX_SLOTS := 3
const SAVE_VERSION := 2

var current_slot := 0


func _ready() -> void:
	_ensure_save_dir()


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)


## 保存存档到指定槽位（带 .tmp → .bak 安全写入）
func save(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		push_error("SaveManager: invalid slot %d" % slot)
		return false

	var data: Dictionary = _collect_save_data()
	var path := _slot_path(slot)
	var tmp_path := path + ".tmp"
	var bak_path := path + ".bak"

	# 写入临时文件
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: failed to write tmp %s" % tmp_path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	# 备份旧档
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, bak_path)

	# 替换主档
	DirAccess.rename_absolute(tmp_path, path)
	current_slot = slot
	return true


## 从指定槽位加载存档（损坏时尝试 .bak 恢复）
func load_slot(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	var data: Dictionary = _try_load_file(path)
	if data.is_empty():
		var bak_path := path + ".bak"
		data = _try_load_file(bak_path)
		if data.is_empty():
			return {"ok": false, "reason": "存档不存在或损坏"}
		DirAccess.copy_absolute(bak_path, path)

	current_slot = slot
	return {"ok": true, "data": data}


func _try_load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return json.data


## 删除存档槽位
func delete(slot: int) -> bool:
	var path := _slot_path(slot)
	var ok := false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		ok = true
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	return ok


## 列出所有存档槽位信息
func list_slots() -> Array:
	var slots: Array = []
	for i in MAX_SLOTS:
		var info: Dictionary = {
			"slot": i, "exists": false,
			"name": "空", "floor": 0, "time": "",
			"has_active_run": false, "character": ""
		}
		var result: Dictionary = load_slot(i)
		if result.get("ok", false):
			var d: Dictionary = result["data"]
			info["exists"] = true
			info["character"] = d.get("character", "warrior")
			info["name"] = _char_display_name(str(d.get("character", "warrior")))
			info["floor"] = d.get("floor", 1)
			info["time"] = str(d.get("play_time", ""))
			info["has_active_run"] = d.get("has_active_run", false)
		slots.append(info)
	return slots


## 标记当前局为激活（用于"继续游戏"）
func set_active_run(active: bool) -> void:
	var result: Dictionary = load_slot(current_slot)
	if not result.get("ok", false):
		return
	var data: Dictionary = result["data"]
	data["has_active_run"] = active
	_save_raw(current_slot, data)


func _save_raw(slot: int, data: Dictionary) -> void:
	var path := _slot_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d%s" % [slot, SAVE_EXTENSION]


func _collect_save_data() -> Dictionary:
	var gm := get_node_or_null("/root/GameManager")
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"character": "warrior",
		"floor": 1,
		"difficulty": "normal",
		"seed": 0,
		"gold": 0,
		"kills": 0,
		"devoured_count": 0,
		"fusion_count": 0,
		"play_time": "00:00",
		"saved_at": Time.get_datetime_string_from_system(),
		"has_active_run": false,
		# 局外累积：钥匙碎片跨局保留（策划书 6. 结算时写入局外记录）
		"meta_key_fragments": 0,
	}
	if gm:
		data["character"] = gm.run_info.get("character", "warrior")
		# 形态也进存档：职业+形态共同决定玩家数值。只存职业的话，
		# 读档会静默回到形态 0——玩家选了"虚空古神化身"，读档变回"元素使"。
		data["form"] = int(gm.run_info.get("form", 0))
		data["floor"] = gm.run_info.get("floor", 1)
		data["difficulty"] = gm.run_info.get("difficulty", "normal")
		data["seed"] = gm.run_info.get("seed", 0)
		data["gold"] = gm.gold
		data["kills"] = gm.kills
		data["devoured_count"] = gm.devoured_count
		data["fusion_count"] = gm.fusion_count
		data["play_time"] = _format_time(gm._run_start_ms)
		if "meta_key_fragments" in gm:
			data["meta_key_fragments"] = int(gm.meta_key_fragments)
		# 装备全量（已装备 + 背包 + 吞噬加成）。
		# **必须存**：这些实例（融合次数/强化等级/锁定）只活在内存里，
		# 而读档会重建 manager——不存的话玩家的装备全丢，
		# 但存档文件里"融合次数"这种计数还在，看起来一切正常。
		if gm.equipment_manager != null and gm.equipment_manager.has_method("to_dict"):
			data["equipment"] = gm.equipment_manager.call("to_dict")
		# 消耗品背包
		if gm.consumable_inventory != null and gm.consumable_inventory.has_method("to_dict"):
			data["consumables"] = gm.consumable_inventory.call("to_dict")
		# 仅当局内属性已初始化（DUNGEON/BOSS 阶段）才视为进行中
		if gm.attributes != null:
			data["has_active_run"] = true
	return data


## 读出存档里的局外碎片数（读档后由调用方写回 GameManager）
static func read_meta_key_fragments(data: Dictionary) -> int:
	return int(data.get("meta_key_fragments", 0))


## 把存档数据**应用回游戏状态**（"继续游戏"用）。
##
## 这是存档链路的最后一米：`_collect_save_data` 负责写、本函数负责读，
## 二者必须成对。**此前只有写没有读**——`_on_continue_pressed` 直接调
## `start_new_run`（全新开局），存档里的金币/击杀/装备/吞噬全被清零，
## 玩家读档后发现一切归零，而存档文件本身看起来完全正常。
##
## 调用顺序：先 start_new_run（建立干净的 manager 与属性系统），
## 再调本函数覆盖。反过来会在恢复后又被 _reset_run 清掉。
func restore_run(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return false

	# ① 先用存档的局信息开局（会重置一切，包括 manager）
	gm.start_new_run({
		"character": data.get("character", "warrior"),
		"form": int(data.get("form", 0)),
		"mode": data.get("mode", "dungeon"),
		"difficulty": data.get("difficulty", "normal"),
		"floor": data.get("floor", 1),
		"seed": data.get("seed", 0),
	})

	# ② 覆盖回存档里的局内状态
	gm.gold = int(data.get("gold", 0))
	gm.kills = int(data.get("kills", 0))
	gm.devoured_count = int(data.get("devoured_count", 0))
	gm.fusion_count = int(data.get("fusion_count", 0))
	if "meta_key_fragments" in gm:
		gm.meta_key_fragments = int(data.get("meta_key_fragments", 0))

	# ③ 装备全量恢复（已装备 + 背包 + 吞噬加成 + 词条重新挂载）
	var eq = data.get("equipment", {})
	if gm.equipment_manager != null and not eq.is_empty():
		if gm.equipment_manager.has_method("from_dict"):
			gm.equipment_manager.call("from_dict", eq)

	# ④ 消耗品背包
	var cons = data.get("consumables", {})
	if gm.consumable_inventory != null and not cons.is_empty():
		if gm.consumable_inventory.has_method("from_dict"):
			gm.consumable_inventory.call("from_dict", cons)

	EventBus.stats_changed.emit()
	return true


func _format_time(start_ms: int) -> String:
	var sec := float(Time.get_ticks_msec() - start_ms) / 1000.0
	var m := int(sec / 60.0)
	var s := int(sec) % 60
	return "%02d:%02d" % [m, s]


func _char_display_name(char_id: String) -> String:
	match char_id:
		"warrior":
			return "战士 · 狂怒之刃"
		"mage":
			return "法师 · 虚空织者"
		"hunter":
			return "猎人 · 铁血猎手"
		"judge":
			return "判官 · 裁决之秤"
		"monk":
			return "武僧 · 炼魂武者"
		_:
			return char_id