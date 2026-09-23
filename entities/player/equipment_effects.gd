class_name PlayerEquipmentEffects
extends Node
## 装备触发条件的结算器 —— 把「击杀时 / 受击时 / 命中时 / 闪避时 / 满层时」
## 的自有词条真正接进战斗。
##
## ## 为什么需要它
##
## 装备参考2 规格里，**绝大多数自有词条不是常驻数值**，而是事件驱动的：
##   · 「每击杀一个敌人，该武器所有数值增加 1%」（本局永久叠加）
##   · 「每受到一次伤害，防御力增加 1%，持续 10 秒，可叠加 5 层」
##   · 「击杀敌人获得 1 层噬魂（最多 5 层），满层时下次攻击释放范围收割」
##
## 此前这些全被解析成**常驻**面板数值——机制丢失。本组件负责：
##   ① 把已装备的触发型自有词条按条件归类
##   ② 在玩家侧的事件钩子里触发它们（叠层 / 给角色挂词条）
##   ③ 满层时结算额外效果
##
## ## 实现方式：复用 BuffHolder
##
## 叠层 + 时长 + 属性同步这条链路 `BuffHolder` 已经完整具备
##（`stacks` / `max_stacks` / `stacks_of`，`_sync_modifier` 会把层数乘进属性）。
## 故触发词条的落地方式 = **给玩家挂一条带 max_stacks 的词条**，
## 而不是另造一套计数器。这样「持续 10 秒、可叠加 5 层」这类规格
## 直接由现成机制满足。

## 玩家节点（构造时注入）
var player: Node3D = null


## 装配：注入玩家节点
func setup(owner_player: Node3D) -> void:
	player = owner_player


# ============================================================
# 事件入口（由 Player 的战斗钩子转发）
# ============================================================

## 击杀敌人时结算（规格：击杀时触发的自有词条）
func on_kill() -> void:
	_fire(AffixData.Trigger.ON_KILL)


## 受到伤害时结算（规格：受击叠层类，如「腐蚀头盔」）
func on_hurt() -> void:
	_fire(AffixData.Trigger.ON_HURT)


## 命中敌人时结算
func on_hit() -> void:
	_fire(AffixData.Trigger.ON_HIT)


## 闪避成功时结算
func on_dodge() -> void:
	_fire(AffixData.Trigger.ON_DODGE)


## 取所有已装备的、指定触发条件的自有词条
func _affixes_with(trig: int) -> Array:
	var out: Array = []
	var em = _em()
	if em == null:
		return out
	for inst in em.get_equipped().values():
		if inst == null:
			continue
		var tpl = inst.get_template()
		if tpl == null or tpl.own_affix == null:
			continue
		if int(tpl.own_affix.trigger) != trig:
			continue
		out.append({"affix": tpl.own_affix, "inst": inst})
	return out


## 触发某一类条件的所有词条
func _fire(trig: int) -> void:
	if player == null or player.buffs == null:
		return
	for e in _affixes_with(trig):
		var a: AffixData = e["affix"]
		# 概率门槛（规格里「有 5% 概率…」这类）
		if float(a.chance) < 1.0 and GameManager.rng.randf() > float(a.chance):
			continue
		_apply_trigger(a, e["inst"])


## 把一条触发词条落到玩家身上。
##
## 有 stack_max 的走「叠层词条」路径（BuffHolder 记账，自动按时长衰减）；
## 没有的走一次性直接结算（如「击杀回 2% 生命」）。
func _apply_trigger(a: AffixData, inst) -> void:
	if a == null:
		return
	if a.stack_max > 0:
		_apply_stacked(a)
	else:
		_apply_instant(a, inst)


## 叠层型：挂一条同名叠层词条。
##
## **用装备 id + 词条值做 buff id**：不同装备的同类触发要各自记账，
## 否则两件「受击叠层」装备会共享同一份层数。
func _apply_stacked(a: AffixData) -> void:
	var bid := _stack_buff_id(a)
	if bid.is_empty():
		return
	# 注册一条临时词条定义（值来自装备，故不能预置在 BuffDefs 表里）
	BuffDefs.register_equipment_stack(bid, a.stat, a.value, a.duration, a.stack_max)
	player.buffs.apply(bid, "equip_trigger")


## 一次性型：直接结算（回血 / 加资源 / 加属性）
func _apply_instant(a: AffixData, inst) -> void:
	if player == null:
		return
	# 生命回复类（规格里「每击杀一个敌人回复 2% 最大生命值」）
	var key := EquipmentDB.special_out_key(a.stat)
	if key == "life_steal":
		# 这里的 life_steal 语义是「回血」而非「吸血比例」——
		# 由规格文本「回复 N% 最大生命值」解析而来，故按最大生命百分比结算。
		if GameManager.attributes != null and not GameManager.attributes.is_dead():
			var amount: float = GameManager.attributes.max_hp * a.value
			var healed: float = GameManager.attributes.heal(amount)
			if healed > 0.0:
				EventBus.damage_popup.emit(player.global_position, healed, "heal")
		return
	# 其余扩展修饰量：挂一条永久词条（本局有效）
	var bid := _stack_buff_id(a)
	BuffDefs.register_equipment_stack(bid, a.stat, a.value, 0.0, 0)
	player.buffs.apply(bid, "equip_trigger")


## 叠层词条的 id（按「装备 id + 触发条件 + 属性」唯一化）
func _stack_buff_id(a: AffixData) -> String:
	if a == null:
		return ""
	return "eqtrig_%d_%d" % [int(a.trigger), int(a.stat)]


## 取 EquipmentManager（取不到返回 null）
func _em():
	var gm: Node = player.get_node_or_null("/root/GameManager") if player != null else null
	if gm == null:
		return null
	return gm.get("equipment_manager")
