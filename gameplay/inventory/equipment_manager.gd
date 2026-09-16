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
	# 通用属性词条：融合是分册明列的「附加到装备」的途径之一
	var gained := _grant_fusion_generic_affix(main)
	_recalc_fusion_bonus()
	remove_item(material)
	_emit_bus("inventory_changed")
	_emit_bus("stats_changed")
	return {"ok": true, "new_tier": main.fusion_tier(), "cost": cost,
		"affix": gained}


## 融合时按概率附加一条通用属性型词条（名词分册第 5 章）。
## 概率随后续融合次数递减——首融最容易附加，越往后越难出新词条，
## 避免一件装备融合 25 次就白拿 25 条词条（同 id 也不重复附加）。
## 返回附加的词条（未附加返回 null）。
func _grant_fusion_generic_affix(main: EquipmentInstance) -> AffixData:
	if main == null:
		return null
	# 概率：首次 60%，此后每融一次 -5%，下限 10%
	var chance: float = maxf(0.60 - 0.05 * float(main.fusion_count), 0.10)
	if rng == null:
		return null
	if rng.randf() > chance:
		return null
	var a := EquipmentDB.roll_generic_affix(main.rarity, rng)
	if a == null:
		return null
	if not main.add_extra_affix(a):
		return null   # 同 id 已存在，本次不附加
	# 已穿戴的话立刻生效（重挂 modifier）
	if _equipped.values().has(main):
		_remove_equipment_modifiers(main)
		_apply_equipment_modifiers(main)
	return a


## 商店/附魔：给指定装备附加一条通用词条（用 attach_generic_affix 的底层入口）。
## 该方法不带档位与次数校验——正式游戏流程走 enchant()，它按策划 4.3.2 计费。
## 返回 {ok, affix?/reason?}。
func attach_generic_affix(item: EquipmentInstance, rarity_bonus: int = 0) -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "无效物品"}
	var rar: int = clampi(item.rarity + rarity_bonus, 0, EquipmentDefs.Rarity.RED)
	var a := EquipmentDB.roll_generic_affix(rar, rng)
	if a == null:
		return {"ok": false, "reason": "暂无可附加的词条"}
	if not item.add_extra_affix(a):
		return {"ok": false, "reason": "该装备已有同名同名词条"}
	if _equipped.values().has(item):
		_remove_equipment_modifiers(item)
		_apply_equipment_modifiers(item)
	_emit_bus("inventory_changed")
	_emit_bus("stats_changed")
	return {"ok": true, "affix": a, "text": a.description()}


## 附魔装备（策划 4.3.2：低级 800 / 中级 2,000 / 高级 5,000；
## 单件最多 3 次）。档位决定附加词条的稀有度门槛——
## 低级只出白+ 词条，高级可出橙+（如元素穿透）。
##
## 与「属性灌注」（purchase_infusion）的区别：灌注给**玩家**加固定属性、
## 与装备无关；附魔把词条**附加到装备**上，装备卸下/丢弃时词条一起走。
## 返回 {ok, tier?, affix?, cost?, text?, reason?}。
func enchant(item: EquipmentInstance, tier: String) -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "无效物品"}
	if not SpecialRoomService.can_enchant(item.enchant_stacks):
		return {"ok": false, "reason": "该装备已附魔 %d 次（上限 %d）" % [
			item.enchant_stacks, SpecialRoomService.ENCHANT_MAX_STACKS]}
	var cost: int = int(SpecialRoomService.ENCHANT_COSTS.get(tier, 0))
	if cost <= 0:
		return {"ok": false, "reason": "未知附魔档位 %s" % tier}
	var gm = _game_manager()
	if gm and gm.gold < cost:
		return {"ok": false, "reason": "金币不足（需要 %d）" % cost}

	# 档位 → 词条稀有度门槛：低/中/高 对应 白/蓝/紫 起步
	var rarity_floor := {
		"low": EquipmentDefs.Rarity.WHITE,
		"mid": EquipmentDefs.Rarity.BLUE,
		"high": EquipmentDefs.Rarity.PURPLE,
	}
	var rar: int = maxi(int(rarity_floor.get(tier, 0)), item.rarity)
	var a := EquipmentDB.roll_generic_affix(rar, rng)
	if a == null:
		return {"ok": false, "reason": "暂无可附加的词条"}

	if gm:
		gm.gold -= cost
	item.enchant_stacks += 1
	if not item.add_extra_affix(a):
		# 同名词条已存在：退钱、不退次数
		if gm:
			gm.gold += cost
		item.enchant_stacks -= 1
		return {"ok": false, "reason": "该装备已有同名同名词条（本次不消耗）"}
	if _equipped.values().has(item):
		_remove_equipment_modifiers(item)
		_apply_equipment_modifiers(item)
	_emit_bus("inventory_changed")
	_emit_bus("stats_changed")
	return {"ok": true, "tier": tier, "affix": a, "cost": cost,
		"text": a.description(), "stacks": item.enchant_stacks}


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


## 汇总已装备的**触发型词条**（名词分册第 5 章装备可附加词条）。
## 返回 [{buff, chance, duration}, ...]，同名词条的**概率累加**——
## 两件装备各带 5% 眩晕就是 10%，与「同类词条可叠加」的分册口径一致。
## 命中链路（player._apply_hit）拿到后逐条 roll。
func equipped_trigger_affixes() -> Array:
	var merged := {}   # buff_id -> {chance, duration}
	for slot in _equipped:
		var inst = _equipped[slot]
		if inst == null:
			continue
		var tpl: EquipmentTemplate = inst.get_template()
		if tpl == null:
			continue
		for affix in tpl.trigger_affixes:
			if affix == null or not affix.is_trigger():
				continue
			var bid: String = affix.trigger_buff
			if bid.is_empty():
				continue
			if not merged.has(bid):
				merged[bid] = {"chance": 0.0, "duration": affix.trigger_duration}
			var e: Dictionary = merged[bid]
			e["chance"] = float(e["chance"]) + affix.trigger_chance
			# 时长取更长的那个（多件叠加时不缩短）
			e["duration"] = maxf(float(e["duration"]), affix.trigger_duration)
	var out: Array = []
	for bid in merged:
		out.append({
			"buff": bid,
			"chance": minf(float(merged[bid]["chance"]), 1.0),
			"duration": float(merged[bid]["duration"]),
		})
	return out


## 汇总已装备的**特殊修饰量**（非面板属性的那 6 种通用词条）。
## 返回 {life_steal, knockback_pct, debuff_dur_pct, elem_pen_pct,
##       reflect_pct, execute_bonus}，缺省 0.0。
## 这些不走 AttributeSystem（不是面板属性），由伤害结算自行读取。
func special_modifiers() -> Dictionary:
	var out := {
		"life_steal": 0.0, "knockback_pct": 0.0, "debuff_dur_pct": 0.0,
		"elem_pen_pct": 0.0, "reflect_pct": 0.0, "execute_bonus": 0.0,
	}
	for slot in _equipped:
		var inst = _equipped[slot]
		if inst == null:
			continue
		var tpl: EquipmentTemplate = inst.get_template()
		if tpl == null:
			continue
		# 模板三词条 + 实例的通用附加词条（附魔/融合附加的都在这）
		var all_affixes: Array = [tpl.base_affix, tpl.devour_affix, tpl.fusion_affix]
		all_affixes.append_array(inst.extra_affixes)
		for affix in all_affixes:
			if affix == null or not affix.is_stat():
				continue
			var out_key: String = EquipmentDB.special_out_key(affix.stat)
			if out_key.is_empty():
				continue
			out[out_key] = float(out[out_key]) + affix.value * inst.enhancement_mult()
	return out


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


## 应用装备词条到属性系统。
## 挂两类：模板的**基础词条**（穿戴自带）+ 实例的**通用附加词条**
## （融合/附魔/商店附加，见 EquipmentInstance.extra_affixes）。
##
## 注意：**只有面板属性走 AttributeSystem**。像「生命偷取/击退距离/
## 元素穿透」这类扩展修饰量（枚举值 100+）不在 AttributeSystem 的取值域里，
## 挂进去不会生效也读不出来——它们由 special_modifiers() 汇总、
## 由伤害结算自行消费，故这里跳过。
func _apply_equipment_modifiers(inst: EquipmentInstance) -> void:
	var gm = _game_manager()
	if gm == null or gm.attributes == null:
		return
	var src := "equip_%s" % inst.instance_id

	var template := inst.get_template()
	if template != null and template.base_affix != null:
		var affix := template.base_affix
		# 按 operation 二选一：FLAT 走固定值、PERCENT 走百分比。
		# **不能两个都传**——原实现无条件把 base_affix_value() 当 flat 传进去，
		# PERCENT 型词条于是同时吃到了「固定值 + 百分比」两份加成
		# （如「暴击率 +1%」实际变成 +1% 相对 且 再 +0.01 绝对值）。
		# 表里的 is_percent 标记就是唯一口径，与此分支一致。
		var val := 0.0
		var pct := 0.0
		if affix.operation == AffixData.Operation.PERCENT:
			pct = affix.value * inst.enhancement_mult()
		else:
			val = inst.base_affix_value()
		gm.attributes.add_modifier(src, affix.stat, val, pct)

	# 通用附加词条（同一 source，随装备一起挂/卸）
	for a in inst.extra_affixes:
		if a == null or not a.is_stat():
			continue
		if int(a.stat) >= 100:
			continue   # 扩展修饰量：走 special_modifiers，不挂面板
		var val := 0.0
		var pct := 0.0
		if a.operation == AffixData.Operation.PERCENT:
			pct = a.value * inst.enhancement_mult()
		else:
			val = a.value * inst.enhancement_mult()
		gm.attributes.add_modifier(src, a.stat, val, pct)


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
