class_name EquipmentManager
extends RefCounted
## 装备管理器 —— HD-2D 重构版
## 管理装备穿戴、吞噬、融合、背包

var rng: RandomNumberGenerator

# 最大强化等级（强化只提升基础词条，固定 +5%/级，无失败）
const MAX_ENHANCEMENT_LEVEL := 10

# 装备槽位
var _equipped: Dictionary = {}          # slot -> EquipmentInstance
var _inventory: Array[EquipmentInstance] = []
## 背包容量。**与 UI 的格子数必须是同一个数**——UI 按 CAPACITY 画 8×5 格，
## 而逻辑层原先写死 20，导致「界面有 40 格、实际只能装 20 件」，
## 玩家看到空格却放不进去。现由 UI 从这里读（见 BackpackUI.CAPACITY）。
const MAX_INVENTORY_SIZE := 40
var _max_inventory_size := MAX_INVENTORY_SIZE

# 融合攻击加成缓存
var _fusion_attack_bonus: float = 0.0

## 吞噬产生的永久属性加成（本局有效）。
## 格式：{source_instance_id: {"stat": int, "flat": float, "percent": float}}
## **必须存档**：这些加成是通过 AttributeSystem 的 modifier 生效的，
## 而 modifier 只活在内存里——不存的话读档后玩家会凭空少一大截属性
## （吞噬是"本局永久成长"，丢了等于白吞）。
var _devour_modifiers: Dictionary = {}


## 添加装备到背包
func add_item(inst: EquipmentInstance) -> bool:
	if _inventory.size() >= _max_inventory_size:
		return false
	_inventory.append(inst)
	_emit_bus("inventory_changed")
	return true


## 移除装备
func remove_item(inst: EquipmentInstance) -> void:
	_inventory.erase(inst)
	_emit_bus("inventory_changed")


## 装备到槽位（物品从背包转入槽位，旧装备退回背包）
func equip(slot: int, inst: EquipmentInstance) -> void:
	# 若已穿戴在其他槽位，先卸下
	for s in _equipped.keys():
		if _equipped[s] == inst:
			unequip(s)
	if _equipped.has(slot):
		var old: EquipmentInstance = _equipped[slot]
		unequip(slot)
		if old != inst:
			_inventory.append(old)
	_equipped[slot] = inst
	_inventory.erase(inst)
	_apply_equipment_modifiers(inst)
	_apply_fusion_affix(inst)
	# 穿戴会改变「已装备武器」的构成 → 融合攻击加成必须重算
	_recalc_fusion_bonus()
	var bus = _event_bus()
	if bus:
		bus.equipment_changed.emit(slot, inst.instance_id)
		bus.stats_changed.emit()


## 卸下装备（退回背包）
func unequip(slot: int) -> void:
	if not _equipped.has(slot):
		return
	var inst: EquipmentInstance = _equipped[slot]
	# 卸下要清**全部**词条（基础 + 融合）——装备离身，两者都不该继续生效
	_clear_all_modifiers(inst)
	_equipped.erase(slot)
	if _inventory.size() < _max_inventory_size:
		_inventory.append(inst)
	# 卸下同理：武器槽空了，融合加成要跟着降下来
	_recalc_fusion_bonus()
	var bus = _event_bus()
	if bus:
		bus.equipment_changed.emit(slot, "")
		bus.stats_changed.emit()


## 吞噬装备（本局永久成长）
func devour(item: EquipmentInstance) -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "无效物品"}

	var template := item.get_template()
	if template == null or template.devour_affix == null:
		return {"ok": false, "reason": "该物品不可吞噬"}

	# 应用吞噬词条
	var affix := template.devour_affix
	var gm = _game_manager()
	var flat := 0.0
	var percent := 0.0
	if affix.operation == AffixData.Operation.PERCENT:
		percent = affix.value
	else:
		flat = affix.value
	if gm and gm.attributes:
		gm.attributes.add_modifier(
			"devour_%s" % item.instance_id,
			affix.stat,
			flat,
			percent
		)
	# 记进可存档的表——modifier 只活在内存，不记的话读档会丢
	_devour_modifiers[item.instance_id] = {
		"stat": affix.stat, "flat": flat, "percent": percent,
	}

	remove_item(item)
	var bus = _event_bus()
	if bus:
		bus.item_devoured.emit(item.instance_id, item.display_name())
		bus.stats_changed.emit()
	return {"ok": true}


## 融合装备（main 吃 material：同槽位校验 + 词条继承 + 金币计费）
func fuse(main: EquipmentInstance, material: EquipmentInstance) -> Dictionary:
	if main == null or material == null:
		return {"ok": false, "reason": "无效物品"}
	if not FusionRules.can_fuse(main.fusion_count):
		return {"ok": false, "reason": "已达最大融合等级"}

	# 同槽位校验（策划口径：同部位装备才能作为融合材料）
	var main_tpl := main.get_template()
	var mat_tpl := material.get_template()
	if main_tpl == null or mat_tpl == null:
		return {"ok": false, "reason": "装备数据异常"}
	if main_tpl.slot != mat_tpl.slot:
		return {"ok": false, "reason": "材料必须为同部位装备"}
	if material.is_locked:
		return {"ok": false, "reason": "材料已锁定"}

	# 金币计费（策划公式：BASE_COST × (1 + 融合数 × 0.3)）
	var cost := FusionRules.fusion_cost(main, material)
	var gm = _game_manager()
	if gm and gm.gold < cost:
		return {"ok": false, "reason": "金币不足（需要 %d）" % cost}

	main.fusion_count = FusionRules.next_fusion_count(main.fusion_count)
	if gm:
		gm.gold -= cost
		gm.fusion_count += 1
	# 融合词条按新档位刷新（策划 3.2：品质随累计次数上涨）
	_apply_fusion_affix(main)
	_recalc_fusion_bonus()
	remove_item(material)
	_emit_bus("inventory_changed")
	_emit_bus("stats_changed")
	return {"ok": true, "new_tier": main.fusion_tier(), "cost": cost}


## 强化装备（只提升基础词条，固定 +5%/级，无失败）
func enhance(item: EquipmentInstance) -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "无效物品"}
	if item.enhancement_level >= MAX_ENHANCEMENT_LEVEL:
		return {"ok": false, "reason": "已达最大强化等级"}

	var cost := enhancement_cost(item)
	var gm = _game_manager()
	if gm and gm.gold < cost:
		return {"ok": false, "reason": "金币不足（需要 %d）" % cost}

	item.enhancement_level += 1
	if gm:
		gm.gold -= cost
	# 若已穿戴，词条数值变化需重挂 Modifier
	if _equipped.values().has(item):
		_remove_equipment_modifiers(item)
		_apply_equipment_modifiers(item)
	_emit_bus("inventory_changed")
	_emit_bus("stats_changed")
	return {"ok": true, "level": item.enhancement_level, "cost": cost}


## 强化费用（基础 20 + 等级 × 15）
func enhancement_cost(item: EquipmentInstance) -> int:
	return 20 + item.enhancement_level * 15


## 卸下装备（按实例查槽位）
func unequip_item(item: EquipmentInstance) -> void:
	for slot in _equipped.keys():
		if _equipped[slot] == item:
			unequip(slot)
			return


## 获取融合攻击总加成
func fusion_attack_bonus() -> float:
	return _fusion_attack_bonus


## 获取 GameManager autoload（--script 测试模式下不存在，返回 null）
func _game_manager():
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("GameManager")
	return null


## 获取 EventBus autoload（--script 测试模式下不存在，返回 null）
func _event_bus():
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("EventBus")
	return null


## 发射无参信号（EventBus 不存在时静默跳过）
func _emit_bus(signal_name: String) -> void:
	var bus = _event_bus()
	if bus:
		bus.emit_signal(signal_name)


## 获取背包所有物品
func get_inventory() -> Array:
	return _inventory.duplicate()


## 背包容量（UI 据此画格子，保证界面与实际能装的件数一致）
func get_capacity() -> int:
	return _max_inventory_size


## 交换背包内两个物品的顺序（拖拽排序用）
func swap_items(from: int, to: int) -> void:
	if from < 0 or to < 0 or from >= _inventory.size() or to >= _inventory.size():
		return
	if from == to:
		return
	var tmp = _inventory[from]
	_inventory[from] = _inventory[to]
	_inventory[to] = tmp
	_emit_bus("inventory_changed")


## 获取已装备物品
func get_equipped() -> Dictionary:
	return _equipped.duplicate()


## 应用装备基础词条到属性系统
func _apply_equipment_modifiers(inst: EquipmentInstance) -> void:
	var template := inst.get_template()
	if template == null or template.base_affix == null:
		return
	var affix := template.base_affix
	var value := inst.base_affix_value()
	var percent := 0.0
	if affix.operation == AffixData.Operation.PERCENT:
		percent = affix.value * inst.enhancement_mult()
	var gm = _game_manager()
	if gm and gm.attributes:
		gm.attributes.add_modifier(
			"equip_%s" % inst.instance_id,
			affix.stat,
			value,
			percent
		)


## 移除装备**基础词条**。
## **不要在这里连融合词条一起删**：enhance() 会调本函数后重挂基础词条，
## 若连融合词条也删了，强化一次就会永久丢失融合成长
## （融合次数还在、档位却丢了）。融合词条的生命周期由
## _apply_fusion_affix / _clear_fusion_affix 单独管。
func _remove_equipment_modifiers(inst: EquipmentInstance) -> void:
	var gm = _game_manager()
	if gm and gm.attributes:
		gm.attributes.remove_modifiers("equip_%s" % inst.instance_id)


## 清除某实例的**全部**词条（基础 + 融合）。卸下/丢弃时用。
func _clear_all_modifiers(inst: EquipmentInstance) -> void:
	if inst == null:
		return
	var gm = _game_manager()
	if gm and gm.attributes:
		gm.attributes.remove_modifiers("equip_%s" % inst.instance_id)
		gm.attributes.remove_modifiers("fusion_%s" % inst.instance_id)


## 应用/刷新**融合词条**（策划 3.2「融合词条品质成长」）。
##
## 策划：词条品质只看累计融合次数，满级效果 粗糙+3% → 神话+40%
## （以攻击加成为例）。故数值**随 fusion_count 逐档上涨**，不是模板里的固定值
## ——模板的 fusion_affix 只提供「这条词条加什么属性」，数值由档位决定。
##
## 用独立的 modifier 源名（fusion_<id>），与基础词条（equip_<id>）分开：
## 二者生命周期不同——基础词条随强化变，融合词条随融合次数变。
func _apply_fusion_affix(inst: EquipmentInstance) -> void:
	if inst == null:
		return
	var gm = _game_manager()
	if gm == null or gm.attributes == null:
		return
	# 先清旧的（融合次数变化时要覆盖，不是叠加）
	gm.attributes.remove_modifiers("fusion_%s" % inst.instance_id)
	var template := inst.get_template()
	if template == null or template.fusion_affix == null:
		return
	if inst.fusion_count <= 0:
		return   # 未融合过就没有融合词条
	var affix := template.fusion_affix
	# 按当前档位取比例（策划 3.2 的攻击加成档位表）
	var pct := FusionRules.tier_affix_attack(inst.fusion_count)
	gm.attributes.add_modifier(
		"fusion_%s" % inst.instance_id,
		affix.stat,
		0.0,
		pct
	)


## 重算融合攻击加成。
##
## 两个口径修正（原先都错）：
## ① **只算已穿戴的武器**——策划 1.2：「武器是融合系统的核心载体…
##    玩家对**一件武器**的长期投入是本作单件养成的仪式感来源，
##    换武器则所有融合投入归零」。故加成的载体是**当前装备的武器**，
##    不是背包里的东西（原先只遍历 _inventory，穿着的武器反而不算）。
## ② **只算武器类**——护甲/饰品的融合走的是词条成长，
##    不该贡献武器攻击力加成。
func _recalc_fusion_bonus() -> void:
	_fusion_attack_bonus = 0.0
	for slot in [EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Slot.WEAPON_2]:
		var inst = _equipped.get(slot)
		if inst == null:
			continue
		_fusion_attack_bonus += inst.fusion_bonus()

# ============================================================
# 序列化（存档用）
# ============================================================

## 导出完整状态（已装备 + 背包 + 吞噬加成）。
##
## **为什么要存这些**：装备实例（融合次数/强化等级/锁定）只活在内存里，
## 而 `_reset_run()` 会把整个 manager 重建。不存的话读档后玩家光着身子、
## 融合投入归零——但存档文件里"融合次数"计数还在，看起来一切正常。
##
## 槽位字典的键是 int 枚举，JSON 会转成字符串，故这里显式转 String 存储，
## 读回时再转回 int（见 from_dict 注释）。
func to_dict() -> Dictionary:
	var equipped := {}
	for slot in _equipped:
		var inst: EquipmentInstance = _equipped[slot]
		if inst != null:
			equipped[str(int(slot))] = inst.to_dict()
	var inv: Array = []
	for inst in _inventory:
		if inst != null:
			inv.append(inst.to_dict())
	return {
		"equipped": equipped,
		"inventory": inv,
		"devour_modifiers": _devour_modifiers.duplicate(true),
		"fusion_attack_bonus": _fusion_attack_bonus,
	}


## 从存档恢复状态。**会先把当前状态清空**（modifier 也一并撤掉），
## 避免与 `_reset_run()` 刚建的空实例叠加出双倍属性。
##
## 恢复内容：已装备（含槽位）、背包、吞噬加成，并把词条重新挂进属性系统。
func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	# 清空当前状态（含属性系统里的 modifier）
	for slot in _equipped.keys():
		var old: EquipmentInstance = _equipped[slot]
		if old != null:
			_clear_all_modifiers(old)
	_equipped.clear()
	_inventory.clear()
	# 撤掉旧的吞噬 modifier
	var gm = _game_manager()
	if gm and gm.attributes:
		for iid in _devour_modifiers:
			gm.attributes.remove_modifiers("devour_%s" % iid)
	_devour_modifiers.clear()

	# 恢复已装备
	var equipped: Dictionary = d.get("equipped", {})
	for slot_key in equipped:
		var inst := EquipmentInstance.new()
		inst.from_dict(equipped[slot_key])
		# JSON 的键是字符串，槽位枚举是 int——必须转回来，
		# 否则 `_equipped` 里会混入 "5" 这样的字符串键，
		# 后续 get_equipped() / _recalc_fusion_bonus 按 int 查全都落空
		_equipped[int(str(slot_key))] = inst

	# 恢复背包
	for entry in d.get("inventory", []):
		var inst2 := EquipmentInstance.new()
		inst2.from_dict(entry)
		_inventory.append(inst2)

	# 恢复吞噬加成（重新挂 modifier）
	_devour_modifiers = d.get("devour_modifiers", {}).duplicate(true)
	if gm and gm.attributes:
		for iid in _devour_modifiers:
			var m: Dictionary = _devour_modifiers[iid]
			gm.attributes.add_modifier(
				"devour_%s" % iid,
				int(m.get("stat", 0)),
				float(m.get("flat", 0.0)),
				float(m.get("percent", 0.0))
			)

	# 已装备的词条重新生效（基础 + 融合）
	for slot in _equipped:
		var inst3: EquipmentInstance = _equipped[slot]
		_apply_equipment_modifiers(inst3)
		_apply_fusion_affix(inst3)

	_recalc_fusion_bonus()
	_emit_bus("inventory_changed")
	_emit_bus("stats_changed")


## 是否有任何装备状态（用于判断存档里是否真有东西可恢复）
func has_any_items() -> bool:
	return not _equipped.is_empty() or not _inventory.is_empty()
