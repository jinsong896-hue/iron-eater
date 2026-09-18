extends Node3D
## 掉落物 —— 拾取（pick_up）/ 吞噬（devour）
##
## **动画不在这里**：由 `PickupField` 集中驱动（见该文件的说明）。
## 早期版本每件掉落物各跑一个 `_process` 做自转+浮动，大规模团战下
## 600 件就是 600 个 `_process`，把群体模拟省下的收益吃回去。
##
## **为什么是独立文件而不是运行时生成的 GDScript**：
## 原实现用 `GDScript.new()` + `source_code` 在首次掉落时现场编译，
## 那是一次数十毫秒的卡顿，且编译器在不同平台行为不一。
## 落成文件后由引擎预编译，且能被静态检查覆盖。

## 注意：不能声明为 `var item: Resource`。
## EquipmentInstance 继承 RefCounted 而非 Resource，类型不符会让
## `set("item", ...)` 静默失败，item 恒为 null，拾取永远报"无效物品"。
var item


## autoload 运行时获取（--script 测试模式下不存在）
func _gm():
	return get_node_or_null("/root/GameManager")


func _bus():
	return get_node_or_null("/root/EventBus")


## 拾取进背包
func pick_up() -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "无效物品"}
	var gm = _gm()
	if gm == null:
		return {"ok": false, "reason": "GameManager 不可用"}
	if not gm.equipment_manager.add_item(item):
		return {"ok": false, "reason": "背包已满"}
	var bus = _bus()
	if bus:
		bus.item_picked_up.emit(item.instance_id, item.display_name())
		bus.message.emit("拾取：%s" % item.display_name())
	queue_free()
	return {"ok": true}


## 原地吞噬（本局永久成长）
func devour() -> Dictionary:
	var gm = _gm()
	if gm == null:
		return {"ok": false, "reason": "GameManager 不可用"}
	var result: Dictionary = gm.devour_item(item)
	if result.get("ok", false):
		queue_free()
	return result
