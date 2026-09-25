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
## 吞噬得到的**扩展通道**加成（stat >= 100 的部分）
##
## 与 `_devour_modifiers` 分开存：那张表是**按装备实例**记账（用于存档与
## 逐件撤销），这张是**按通道聚合**（供 `special_modifiers()` 直接合并）。
## 面板属性（stat < 100）不进来——它们走 `AttributeSystem`。
var _devour_specials: Dictionary = {}


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
##
## **旧装备只退回一次**：`unequip()` 内部已经把旧装备放回背包，
## 原先这里又 `_inventory.append(old)` 了一次 → 旧装备在背包里出现两份，
## 连续替换会让背包无限膨胀（实测 5 次替换净增 10 件），
## 且能突破容量上限（40 格塞进 41 件）。
## 现改为：只调 unequip，退回动作由它独家负责。
## 当前形态是否允许穿戴这件装备（策划 7.1~7.3、7.5 武僧前四形态「不可装备武器」；
## 7.4 破极用 can_equip_weapon 显式解锁）。
##
## 收口在这里而不是各个 UI 入口：穿戴路径有右键菜单、拖拽、初始装备发放
## 三条，逐个拦必然漏。护甲/饰品不受限——策划限制的是"武器"。
func _can_wear(inst: EquipmentInstance) -> bool:
	var tpl := inst.get_template()
	if tpl == null:
		return true
	if tpl.category != EquipmentDefs.Category.WEAPON:
		return true
	var gm = _game_manager()
	if gm == null:
		return true
	var ri: Dictionary = gm.run_info if gm.get("run_info") != null else {}
	var cid := str(ri.get("character", "warrior"))
	var slot := int(ri.get("form", 0))
	if ClassDefs.special_flag(cid, slot, "can_equip_weapon"):
		return true
	return not ClassDefs.special_flag(cid, slot, "no_weapon")


## 穿戴
func equip(slot: int, inst: EquipmentInstance) -> void:
	if inst == null:
		return
	if not _can_wear(inst):
		return
	# 武器类型互斥（装备参考2）：冲突时拒绝装备并提示，不做静默忽略
	var conflict = weapon_slot_conflict(inst, slot)
	if conflict != null:
		var bus0 = _event_bus()
		if bus0:
			bus0.message.emit(str(conflict))
		return
	# 若已穿戴在其他槽位，先卸下（unequip 会把它放回背包）
	for s in _equipped.keys():
		if _equipped[s] == inst:
			unequip(s)
			break
	# 目标槽位有旧装备：卸下即可（退回背包由 unequip 负责，不要再 append）
	if _equipped.has(slot):
		unequip(slot)
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


## 能否把 inst 装到 slot。
##
## 除职业限制外，还要过**武器类型互斥**（装备参考2 规格）：
## 两把武器同时装备时，类型不能冲突——近战/远程不共存、
## 单手/双手不共存、防御武器不能与远程/魔法/长杆共存。
## 冲突时返回 false（调用方据返回值提示玩家，见 equip 的调用方）。
func can_equip_in_slot(inst: EquipmentInstance, slot: int) -> bool:
	if inst == null:
		return false
	if not _can_wear(inst):
		return false
	return weapon_slot_conflict(inst, slot) == null


## 检查把 inst 装到 slot 时，是否与**另一个武器槽**上的装备类型冲突。
##
## 返回冲突说明文本（无冲突返回 null）。
## 非武器、或目标槽位不是武器槽时永远无冲突。
func weapon_slot_conflict(inst: EquipmentInstance, slot: int) -> Variant:
	if slot != EquipmentDefs.Slot.WEAPON_1 and slot != EquipmentDefs.Slot.WEAPON_2:
		return null
	var tpl := inst.get_template()
	if tpl == null or tpl.category != EquipmentDefs.Category.WEAPON:
		return null
	# 找另一个武器槽上的装备
	var other_slot := EquipmentDefs.Slot.WEAPON_2 if slot == EquipmentDefs.Slot.WEAPON_1 \
		else EquipmentDefs.Slot.WEAPON_1
	if not _equipped.has(other_slot):
		return null
	var other: EquipmentInstance = _equipped[other_slot]
	if other == null:
		return null
	var other_tpl := other.get_template()
	if other_tpl == null:
		return null
	var a := EquipmentDefs.weapon_tags_of(tpl.weapon_type, tpl.tags)
	var b := EquipmentDefs.weapon_tags_of(other_tpl.weapon_type, other_tpl.tags)
	var pair := EquipmentDefs.weapon_tag_conflict(a, b)
	if pair.is_empty():
		return null
	var n1: String = EquipmentDefs.WEAPON_TAGS.get(str(pair[0]), str(pair[0]))
	var n2: String = EquipmentDefs.WEAPON_TAGS.get(str(pair[1]), str(pair[1]))
	return "%s与%s不能共存" % [n1, n2]


## 装备离身时，清掉它在技能槽里占的位（装备参考2）。
##
## 规格：装备技能**来自装备**——「卸下装备则从池中移除
##（若它在槽里，槽位一并清空）」。
##
## 不清的话：玩家卸下「火球法杖」后，技能槽里那条 `eq_火球法杖`
## 仍在，`cast_skill` 也仍能放出来——**变成了一件没有来源的技能**。
func _clear_equipment_skills(inst: EquipmentInstance) -> void:
	if inst == null:
		return
	var tpl := inst.get_template()
	if tpl == null:
		return
	var d: Dictionary = EquipmentSkills.skill_of_equipment(tpl.display_name, int(tpl.rarity))
	if d.is_empty():
		return   # 这件装备不带技能，无需处理
	var sid := str(d.get("id", ""))
	if sid.is_empty():
		return
	var gm = _game_manager()
	if gm == null:
		return
	var lo = gm.get("skill_loadout")
	if lo == null:
		return
	# 清掉所有装着该技能 id 的槽位
	for i in lo.slots.size():
		if str(lo.slots[i]) == sid:
			lo.slots[i] = ""
	# 若该装备技能曾被当被动学会，也一并忘掉
	if lo.passives.has(sid):
		lo.passives.erase(sid)


## 卸下装备（退回背包）
##
## **容量不足时不退回**（而不是丢弃或越界）：背包满了就拒绝卸下，
## 否则装备会在"取下但无处可放"的过程中凭空消失。
## 返回是否卸下成功。
func unequip(slot: int) -> bool:
	if not _equipped.has(slot):
		return false
	var inst: EquipmentInstance = _equipped[slot]
	# 背包满 → 不卸下（调用方据返回值提示玩家）
	if _inventory.size() >= _max_inventory_size:
		return false
	# 卸下要清**全部**词条（基础 + 融合）——装备离身，两者都不该继续生效
	_clear_all_modifiers(inst)
	# 装备离身 → 它提供的技能也要从技能槽里撤掉（装备参考2）
	_clear_equipment_skills(inst)
	_equipped.erase(slot)
	_inventory.append(inst)
	# 卸下同理：武器槽空了，融合加成要跟着降下来
	_recalc_fusion_bonus()
	var bus = _event_bus()
	if bus:
		bus.equipment_changed.emit(slot, "")
		bus.stats_changed.emit()
	return true


## 吞噬装备（本局永久成长）
func devour(item: EquipmentInstance) -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "无效物品"}

	var template := item.get_template()
	if template == null or template.devour_affix == null:
		return {"ok": false, "reason": "该物品不可吞噬"}

	# 应用吞噬词条
	#
	# **按「同件累计」缩放**（装备参考2 规格：「吞噬同一件装备时会升级」）：
	# 吞第 1 件是原始值、第 2 件 ×1.25、第 3 件 ×1.5…（见 devour_value_at）。
	# 计数存在 GameManager（跨实例），本函数先自增再取用。
	var affix := template.devour_affix
	var gm = _game_manager()
	var times := 1
	if gm != null and gm.get("devour_template_counts") != null:
		var k := str(template.id)
		times = int(gm.devour_template_counts.get(k, 0)) + 1
		gm.devour_template_counts[k] = times
	var scaled := EquipmentInstance.devour_value_at(template, times)
	var flat := 0.0
	var percent := 0.0
	if affix.operation == AffixData.Operation.PERCENT:
		percent = scaled
	else:
		flat = scaled
	# **按 stat 的值域分流**——这里此前有个会静默失效的 bug：
	#
	# `affix.stat` 有**两套值域**：
	#   `0..10`   —— `AttributeSystem.Stat` 的面板属性（ATK/DEF/…/CRD）
	#   `100+`    —— `EquipmentDB.SPECIAL_STAT` 的扩展通道（lifesteal/elem_dmg/…）
	#
	# 旧代码无条件 `attributes.add_modifier(stat, ...)`。传 `>=100` 时
	# `AttributeSystem._base[stat]` 越界，**抛 `Out of bounds get index` 并
	# 静默失效**——实测 346 条吞噬词条里 **245 条（71%）** 如此，
	# 包括「生命偷取」「元素抗性」「召唤物伤害」这些本轮之前就有的通道。
	#
	# 现在：面板属性照旧走 AttributeSystem；扩展通道累加进 `_devour_modifiers`
	#（那张表本来就存在、且已存档，但**此前没人消费**），
	# 由 `special_modifiers()` 合并进汇总，从而真正生效。
	if affix.stat >= 100:
		_devour_specials[affix.stat] = float(_devour_specials.get(affix.stat, 0.0)) + percent + flat
	else:
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

	# **若装备正穿在身上，必须先摘下来**。
	# 原先只调 remove_item()（仅从背包 erase），已穿戴的装备不在背包里，
	# 于是「吞噬成功、装备还在身上」——实测复现。
	# 用 _clear_all_modifiers 而不是 unequip()：unequip 会把装备**退回背包**，
	# 而吞噬是要它消失，退回去就白吞了。
	for slot in _equipped.keys():
		if _equipped[slot] == item:
			_clear_all_modifiers(item)
			_clear_equipment_skills(item)
			_equipped.erase(slot)
			var bus_eq = _event_bus()
			if bus_eq:
				bus_eq.equipment_changed.emit(slot, "")
			break

	remove_item(item)
	# 卸下装备会改变武器构成 → 融合加成需重算
	_recalc_fusion_bonus()
	var bus = _event_bus()
	if bus:
		bus.item_devoured.emit(item.instance_id, item.display_name())
		bus.stats_changed.emit()
	return {"ok": true}


## 融合装备（main 吃 material：**同大类**校验 + 词条继承 + 金币计费）
func fuse(main: EquipmentInstance, material: EquipmentInstance) -> Dictionary:
	if main == null or material == null:
		return {"ok": false, "reason": "无效物品"}
	if not FusionRules.can_fuse(main.fusion_count):
		return {"ok": false, "reason": "已达最大融合等级"}

	# 融合材料校验（装备参考2 规格）：
	#   「武器只能和武器融合，但是其他部位装备可以和除武器以外的装备融合」
	#
	# **不再是「同槽位」**：原实现要求 `main_tpl.slot == mat_tpl.slot`
	#（头盔只能吃头盔），规格把口径放宽到「同大类」——
	# 武器吃任意武器、护甲/饰品可互相吃。用户 2026-09-22 明确以规格为准。
	var main_tpl := main.get_template()
	var mat_tpl := material.get_template()
	if main_tpl == null or mat_tpl == null:
		return {"ok": false, "reason": "装备数据异常"}
	if not FusionRules.can_fuse_together(main_tpl.category, mat_tpl.category):
		return {"ok": false, "reason": "武器只能和武器融合，其他部位不能和武器融合"}
	if material.is_locked:
		return {"ok": false, "reason": "材料已锁定"}

	# 金币计费（策划公式：BASE_COST × (1 + 融合数 × 0.3)）
	var cost := FusionRules.fusion_cost(main, material)
	var gm = _game_manager()
	if gm and gm.gold < cost:
		return {"ok": false, "reason": "金币不足（需要 %d）" % cost}

	main.fusion_count = FusionRules.next_fusion_count(main.fusion_count)
	# **同件累计**（装备参考2 规格：「融合同一件装备时会升级」）：
	# 记下「主装备融合了一件什么 id 的素材」，供自有/融合词条按次数升级。
	# 计在**主装备实例**上——升级的是它的自有词条，跨局随装备走。
	var mat_tpl_for_count := material.get_template()
	if mat_tpl_for_count != null:
		main.note_same_fuse(mat_tpl_for_count.id)
	# **素材的融合词条**（规格第 3 条）：「这件装备作为素材融合到其他装备上时
	# 产生的额外加成词条」——故取的是**素材**的 fusion_affix，不是主装备的。
	# 累加进主装备的 extra_affixes，成为它的一部分（可多件叠加）。
	# 数值按「同件累计」缩放（融合同一件多次 → 越融越强）。
	if mat_tpl_for_count != null and mat_tpl_for_count.fusion_affix != null:
		var fa := mat_tpl_for_count.fusion_affix
		var times := main.same_fuse_level(mat_tpl_for_count.id)
		var fv := EquipmentInstance.fusion_value_at(mat_tpl_for_count, times)
		var granted := AffixData.make_stat(fa.stat, fv,
			fa.operation == AffixData.Operation.PERCENT)
		# id 带素材 id，让「同素材重复融合」能识别为同一条并升级
		granted.id = StringName("fus_%s" % str(mat_tpl_for_count.id))
		_merge_fusion_affix(main, granted)
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
## 卸下装备（按实例查槽位）。返回是否成功（背包满时失败）
func unequip_item(item: EquipmentInstance) -> bool:
	for slot in _equipped.keys():
		if _equipped[slot] == item:
			return unequip(slot)
	return false


## 获取融合攻击总加成
func fusion_attack_bonus() -> float:
	return _fusion_attack_bonus


## 吞噬产生的永久属性加成（只读拷贝），供 UI 汇总展示。
## 返回 {source_instance_id: {"stat": int, "flat": float, "percent": float}}
func devour_modifiers() -> Dictionary:
	return _devour_modifiers.duplicate(true)


## 汇总已装备的**触发型词条**（名词分册第 5 章装备可附加词条）。
## 返回 [{buff, chance, duration}, ...]，同名词条的**概率累加**——
## 两件装备各带 5% 眩晕就是 10%，与「同类词条可叠加」的分册口径一致。
## 命中链路（player._apply_hit）拿到后逐条 roll。
## 汇总已装备的**命中时触发**词条（`Trigger.ON_HIT` 及其同类）。
##
## ## 为什么必须过滤 Trigger
##
## 旧实现把**所有** `is_trigger()` 的词条都收进来，不看触发条件。
## 但装备参考2 里有大量条件型词条——「护盾被击破时对周围造成伤害」
## 「陷阱触发时…」「旋风斩期间移速+20%」——它们的 `trigger` 各不相同。
## 不区分的话，这些效果会**在每次普攻命中时全部触发**，而不是在
## 各自的条件发生时。那是机制错误，不是数值偏差。
##
## 保留在「命中时」这一组的：ON_HIT / ON_ATTACK / ALWAYS
##（ALWAYS 的触发型词条没有别的时机，归到这里最合理）。
## 其余 Trigger 由各自的消费点单独取（见 `trigger_affixes_of`）。
func equipped_trigger_affixes() -> Array:
	return trigger_affixes_of([
		AffixData.Trigger.ALWAYS, AffixData.Trigger.ON_HIT,
		AffixData.Trigger.ON_ATTACK])


## 取**指定 Trigger 集合**的触发型词条（多件装备按 buff_id 合并）
##
## `triggers` 传 AffixData.Trigger 的枚举值数组。合并规则：概率相加
##（上限 1.0）、时长取更长的那个（多件叠加时不缩短）。
func trigger_affixes_of(triggers: Array) -> Array:
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
			if not (affix.trigger in triggers):
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
		# 2026-09-22 扩充的通道（见 EquipmentDB.SPECIAL_STAT 的说明）
		"elem_resist_pct": 0.0, "gold_gain_pct": 0.0, "sell_price_pct": 0.0,
		"key_drop_pct": 0.0, "block_pct": 0.0, "dodge_pct": 0.0,
		"ctrl_resist_pct": 0.0, "cd_refresh_pct": 0.0, "drop_rate_pct": 0.0,
		"pickup_range_pct": 0.0, "summon_dmg_pct": 0.0, "elem_dmg_pct": 0.0,
		"true_dmg_pct": 0.0, "exp_gain_pct": 0.0, "summon_limit": 0.0,
		# 2026-09-24：元素按种类拆分 + 非元素维度
		#（见 EquipmentDB.SPECIAL_STAT 的说明——旧实现把所有具体元素
		# 塌缩进 elem_dmg，导致六系法杖的数据一字不差）
		"fire_dmg_pct": 0.0, "frost_dmg_pct": 0.0, "static_dmg_pct": 0.0,
		"earth_dmg_pct": 0.0, "wind_dmg_pct": 0.0, "poison_dmg_pct": 0.0,
		"shadow_dmg_pct": 0.0,
		"fire_resist_pct": 0.0, "frost_resist_pct": 0.0, "static_resist_pct": 0.0,
		"earth_resist_pct": 0.0, "wind_resist_pct": 0.0, "poison_resist_pct": 0.0,
		"shadow_resist_pct": 0.0,
		"ranged_dmg_pct": 0.0, "aoe_dmg_pct": 0.0, "trap_dmg_pct": 0.0,
		"projectile_dmg_pct": 0.0, "debuff_resist_pct": 0.0,
		"shield_power_pct": 0.0, "frozen_dmg_pct": 0.0,
	}
	for slot in _equipped:
		var inst = _equipped[slot]
		if inst == null:
			continue
		var tpl: EquipmentTemplate = inst.get_template()
		if tpl == null:
			continue
		# **只收「穿戴时生效」的词条**（装备参考2 规格）：
		#   基础属性 base_affix —— 穿戴生效 ✅
		#   自有词条 own_affix  —— 穿戴生效 ✅（规格明写「只有装备在角色身上才会生效」）
		#   融合词条 fusion_affix —— **作为素材**时给主装备的，穿戴时不生效 ❌
		#   吞噬词条 devour_affix —— **作为素材被吞噬**时给角色的，穿戴时不生效 ❌
		#
		# 后两条若也收进来，穿一件装备就白拿了它的「素材价值」——
		# 等于装备和吞噬两条词条同时生效，与规格相反（且会虚高面板）。
		# 融合词条的生效路径是 fuse() 把它并进主装备的 extra_affixes。
		var all_affixes: Array = [tpl.base_affix, tpl.own_affix]
		all_affixes.append_array(inst.extra_affixes)
		for affix in all_affixes:
			if affix == null or not affix.is_stat():
				continue
			var out_key: String = EquipmentDB.special_out_key(affix.stat)
			if out_key.is_empty():
				continue
			# **自有词条走 own_affix_value**（含同件融合升级），
			# 其余走原值 × 强化倍率——两者成长规则不同，不能混用一个算式。
			var v: float
			if affix == tpl.own_affix:
				v = inst.own_affix_value()
			else:
				v = affix.value * inst.enhancement_mult()
			out[out_key] = float(out[out_key]) + v
	# **合并吞噬得到的扩展通道加成**
	#
	# 吞噬词条里 stat >= 100 的部分走 `_devour_specials`（见 `devour()` 的
	# 分流说明）——它们不是面板属性，没法进 `AttributeSystem`，
	# 但**必须在这里生效**，否则「吞噬 +1% 火焰伤害」加了没效果。
	for stat_enum in _devour_specials:
		var k: String = EquipmentDB.special_out_key(int(stat_enum))
		if not k.is_empty():
			out[k] = float(out[k]) + float(_devour_specials[stat_enum])
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

	# **自有词条**（装备参考2 规格第 2 条）：装备独有，仅穿戴时生效，
	# 融合同一件会升级（见 EquipmentInstance.own_affix_value）。
	#
	# 扩展修饰量（stat >= 100）不挂面板，由 special_modifiers 收集——
	# 与 extra_affixes 同口径（挂进 AttributeSystem 会因枚举越界而静默失效）。
	if template != null and template.own_affix != null:
		var oa := template.own_affix
		if int(oa.stat) < 100:
			var oval := 0.0
			var opct := 0.0
			if oa.operation == AffixData.Operation.PERCENT:
				opct = inst.own_affix_value()
			else:
				oval = inst.own_affix_value()
			gm.attributes.add_modifier(src, oa.stat, oval, opct)

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

	# 随机词条（装备参考2：掉落时定死，**不随强化成长**）
	#
	# 与上面 extra_affixes 的唯一差别就是**不吃 enhancement_mult**——
	# 规格明写「随机词条无法升级」。故这里直接取原值。
	for a in inst.random_affixes:
		if a == null or not a.is_stat():
			continue
		if int(a.stat) >= 100:
			continue
		var val := 0.0
		var pct := 0.0
		if a.operation == AffixData.Operation.PERCENT:
			pct = a.value
		else:
			val = a.value
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
	# **不再把 fusion_affix 挂成自身面板加成**（装备参考2 规格）。
	#
	# 规格原文：融合词条是「当这件装备**作为素材**融合到其他装备上时
	# 会产生」的——它属于**主装备**，不属于素材自己。
	# 旧实现把素材的 fusion_affix 当自身加成挂上，等于穿一件装备
	# 就白拿了它的「素材价值」，与规格相反。
	#
	# 素材的融合词条现在由 `fuse()` 并入主装备的 `extra_affixes`
	#（见 `_merge_fusion_affix`），那条路径才是规格要求的。
	#
	# 本函数保留为「清旧」的空壳：`_clear_fusion_affix` 仍要能移除历史遗留的
	# modifier（旧存档里可能挂着），故不删函数、只停止新挂。


## 把一条融合词条并入主装备的 extra_affixes（**同 id 则升级而非叠加**）。
##
## 规格：「融合同一件装备时会升级」——重复融同一素材时，
## 应把那条词条的值提到新的档位，而不是挂第二条同名词条
##（挂两条会让面板显示重复、也让「同件升级」失去意义）。
func _merge_fusion_affix(main: EquipmentInstance, a: AffixData) -> void:
	if main == null or a == null:
		return
	for i in main.extra_affixes.size():
		var e: AffixData = main.extra_affixes[i]
		if e != null and e.id == a.id:
			e.value = maxf(e.value, a.value)   # 升级取更高档
			return
	main.extra_affixes.append(a)


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
	_devour_specials.clear()

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
	_devour_specials.clear()
	if gm and gm.attributes:
		for iid in _devour_modifiers:
			var m: Dictionary = _devour_modifiers[iid]
			var st := int(m.get("stat", 0))
			# 与 `devour()` 同一套分流：面板属性进 AttributeSystem，
			# 扩展通道进 `_devour_specials`。不分流会让 stat>=100 的词条
			# 在**读档时**抛越界并丢失。
			if st >= 100:
				_devour_specials[st] = float(_devour_specials.get(st, 0.0)) \
					+ float(m.get("percent", 0.0)) + float(m.get("flat", 0.0))
			else:
				gm.attributes.add_modifier(
					"devour_%s" % iid, st,
					float(m.get("flat", 0.0)), float(m.get("percent", 0.0)))

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
