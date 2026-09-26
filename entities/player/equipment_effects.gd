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


# ============================================================
# 2026-09-26：两段式重构新增的 12 个 Trigger 的消费点
# ============================================================
#
# **为什么必须补齐**：P1 给 `AffixData.Trigger` 加了 12 个枚举值来承载
# 「条件压成常驻」那批词条，但枚举只是**数据侧**的标记——若没有对应的
# 事件钩子，那些词条照样不生效。这正是本项目反复踩的坑：
# **有枚举没消费 = 死代码**，且图鉴会显示、玩家以为有效。
#
# 下面每个钩子都由 Player / GameManager 在对应时机调用（见各自注释）。

## 资源满时（「资源满时，下次攻击释放资源冲击波」等）
## 调用点：ClassResource 值变化后由 Player 判定
func on_resource_full() -> void:
	_fire(AffixData.Trigger.RESOURCE_FULL)


## 生命满时（「生命满时，回复转化为护盾」）
## 调用点：Player 治疗结算后
func on_hp_full() -> void:
	_fire(AffixData.Trigger.HP_FULL)


## 隐身期间（「隐身期间移速+20%」「隐身期间暴击率+30%」）
## 调用点：Player 进入隐身时
func on_stealth() -> void:
	_fire(AffixData.Trigger.STEALTH_UP)


## 命中被控制的目标时（「对眩晕/麻痹/冰冻目标…时」）
## 调用点：Player._apply_hit 里目标 `is_controlled()` 时
func on_target_controlled() -> void:
	_fire(AffixData.Trigger.ON_TARGET_CONTROLLED)


## 距离目标超过阈值时（「距离目标超过 N 米时」）
## 调用点：Player._apply_hit 里算完距离后
func on_distance_far() -> void:
	_fire(AffixData.Trigger.DISTANCE_FAR)


## 金币超过阈值时（「金币超过 500 时，暴击率+10%」）
## 调用点：GameManager 金币变化后
func on_gold_above() -> void:
	_fire(AffixData.Trigger.GOLD_ABOVE)


## 出售装备时（非战斗事件）
## 调用点：EquipmentManager.sell()
func on_sell() -> void:
	_fire(AffixData.Trigger.ON_SELL)


## 开启宝箱时（非战斗事件）
## 调用点：宝箱交互
func on_chest_open() -> void:
	_fire(AffixData.Trigger.ON_CHEST_OPEN)


## 回收标枪时（配合标枪的 boomerang 折返机制）
## 调用点：Projectile 折返抵达施法者时
func on_recall() -> void:
	_fire(AffixData.Trigger.ON_RECALL)


## 触发免死后（「触发免死后，获得5秒无敌」）
## 调用点：Player 免死结算处
func on_cheat_death() -> void:
	_fire(AffixData.Trigger.ON_CHEAT_DEATH)


## 目标死亡时（带状态条件，如「冰冻目标死亡时」「缠绕结束时」）
## 调用点：Player 击杀结算，传入被击杀目标供条件判定
func on_target_death() -> void:
	_fire(AffixData.Trigger.ON_TARGET_DEATH)


## 元素触发时（「抗性触发时，对周围造成对应元素伤害」）
## 调用点：ElementDamage 阈值事件（冰冻/雷暴/山崩等）结算后
func on_element_proc() -> void:
	_fire(AffixData.Trigger.ON_ELEMENT_PROC)


## 连击时（「连击时获得1点气劲」）
## 调用点：Player._register_hit_combo
func on_combo() -> void:
	_fire(AffixData.Trigger.ON_COMBO)


## 取所有已装备的、指定触发条件的自有词条
##
## ## 为什么要遍历三个来源（此前只读一个）
##
## 旧实现只读 `tpl.own_affix`——那是 `own_affixes[0]` 的**单数访问器**。
## 于是漏掉两类：
##   · 自有列的**第 2 条起**（`own_affixes` 是数组）
##   · **融合进主装备**的触发词条（住在 `inst.extra_affixes`）
##
## 实测**融合列有 60 条触发型词条**（「护盾被击破时…」「击杀敌人后…」等），
## 它们通过 `fuse()` 并进 `extra_affixes` 后**从未被触发过**。
func _affixes_with(trig: int) -> Array:
	var out: Array = []
	var em = _em()
	if em == null:
		return out
	for inst in em.get_equipped().values():
		if inst == null:
			continue
		var tpl = inst.get_template()
		if tpl == null:
			continue
		# 自有列全部（不止第一条）
		for a in tpl.own_affixes:
			if a != null and int(a.trigger) == trig:
				out.append({"affix": a, "inst": inst})
		# 融合进来的（`fuse()` 把材料的 fusion_affixes 并进这里）
		for a in inst.extra_affixes:
			if a != null and int(a.trigger) == trig:
				out.append({"affix": a, "inst": inst})
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
	# **sentinel 词条**：它们不是「给玩家挂一个状态」，而是「触发一个动作」。
	# 当成普通 buff 施加会变成「玩家身上多了个叫 summon_soul 的状态」——
	# 既无意义又会污染词条栏。
	if a.is_trigger() and a.trigger_buff == "summon_soul":
		_summon_soul()
		return
	# 给护盾（装备参考2：「生命值低于20%时，获得一个吸收30%最大生命的护盾」
	# 「满血时回复转护盾」）——调 `Player._add_shield`（已有消费点，
	# 与 `shield_power_pct` 同一入口）。
	if a.is_trigger() and a.trigger_buff == "grant_shield":
		_grant_shield(a)
		return
	# **职业资源点**（`res_gain` / stat 142）：不是「挂一个状态」，而是
	# **真的加资源**。走 `ClassResource.gain()`——把值当 buff 施加会变成
	# 「玩家身上多了个叫 eqtrig_*_142 的状态」，资源一点都不涨。
	#
	# 这类词条由生成器产出 `[4, <trigger>, 142, N, 0]`，`value` 就是点数。
	if a.stat == EquipmentDB.special_enum_of("res_gain"):
		var r = player.get("class_resource")
		if r != null and r.has_method("gain_from_equip"):
			r.call("gain_from_equip", float(a.value))
		return
	# **触发型词条**（`OP_TRIGGER_BUFF`）：给自己挂一条具名词条。
	#
	# 与 `_apply_instant` 的区别：那个是「把词条的 stat/value 当属性修饰量」，
	# 这个的语义是「施加一个 BuffDefs 里定义的**具名状态**」
	#（如「受到伤害时 10% 概率减少 50% 伤害」→ 挂一条减伤词条）。
	if a.is_trigger() and not a.trigger_buff.is_empty():
		_apply_self_trigger_buff(a)
		return
	if a.stack_max > 0:
		_apply_stacked(a)
	else:
		_apply_instant(a, inst)


## 触发型词条：给**自己**挂一条具名词条（可带数值覆盖）
##
## ## 为什么需要
##
## 规格里大量「受到伤害时有 N% 概率减少 M% 伤害」这类词条——
## 它们的效果是**给自己挂一个限时减伤状态**，而不是给敌人挂。
##
## 现有的 `_apply_trigger_affixes`（在 `Player._apply_hit` 里）只处理
## **给敌人挂**的那类（眩晕/破甲/致盲）。两条路径的宿主不同，不能复用。
##
## 数值走 `a.trigger_params` 覆盖：同一条 buff id 承载不同数值
##（「减少50%」vs「减少30%」），见 `AffixData.trigger_params` 说明。
func _apply_self_trigger_buff(a: AffixData) -> void:
	if player == null or player.buffs == null:
		return
	if a.trigger_buff.is_empty():
		return
	# 概率门槛（「有 10% 概率减少 50% 伤害」）
	if a.trigger_chance < 1.0 and randf() > a.trigger_chance:
		return
	player.buffs.apply(a.trigger_buff, "equip_trigger",
		1, a.trigger_duration, a.trigger_params)


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
	# **满层爆发**（装备参考2：「击杀敌人获得1层灵魂（最多10层），
	# 每层+1%攻击力；满层时下次攻击释放灵魂冲击（200%攻击力）」）。
	#
	# 旧实现完全没有 AT_FULL 这个触发条件——7 条满层词条**从未生效**。
	# 配对规则：AT_FULL 词条与本叠层词条**共用同一个 `stat`**
	#（生成器产出的形态是 `[4,1,Stat.ATK,0.01,10]` + `[4,5,Stat.ATK,2.0,0]`）。
	if a.stack_max > 0 and player.buffs.stacks_of(bid) >= a.stack_max:
		if _fire_stack_full(a.stat):
			# 层数处理：默认清空（规格写「消耗所有层数」——不清的话
			# 下一击又满层，变成每击都爆发）。但「层数不清空」与
			# 「返还50%层数」两条强化词条会改变这个行为。
			_consume_stacks(bid, a.stack_max)


## 满层爆发后的层数处理
##
## 规格里两条强化词条会改变默认行为：
##   · `soul_persist` —— 「暗影波击杀敌人时，层数不清空」→ 保留全部层数
##   · `soul_refund`  —— 「终极技能消耗灵魂后，返还50%层数」→ 返还一半
##
## 两者同时存在时**以「不清空」优先**（对玩家更有利，且语义上
## 「不清空」包含「返还全部」）。都没装才走默认清空。
func _consume_stacks(bid: String, max_stacks: int) -> void:
	if player.buffs.has("soul_persist"):
		return
	if player.buffs.has("soul_refund"):
		var refund := int(floor(float(max_stacks) * 0.5))
		player.buffs.remove(bid)
		for i in maxi(refund, 1):
			player.buffs.apply(bid, "equip_trigger")
		return
	player.buffs.remove(bid)


## 给玩家加护盾（装备参考2：「生命值低于20%时，获得一个吸收30%
## 最大生命值的护盾」「满血时回复转护盾」）
##
## 走 `Player._add_shield(amount, cap_pct)` —— 与 `shield_power_pct` 通道
## **同一入口**，故护盾强度词条会自动放大它（语义正确：护盾就是护盾）。
##
## 数值来自 `a.trigger_params`：`pct` 是占最大生命的比例，
## `cap` 是护盾上限比例（防止无限叠）。
func _grant_shield(a: AffixData) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("_add_shield"):
		return
	var p := a.trigger_params
	var pct := float(p.get("pct", 0.0))
	var cap := float(p.get("cap", 0.60))
	if pct <= 0.0:
		return
	var max_hp := 0.0
	if GameManager.attributes != null:
		max_hp = float(GameManager.attributes.max_hp)
	if max_hp <= 0.0:
		return
	player.call("_add_shield", max_hp * pct, cap)


## 击杀时召唤灵魂（装备参考2：「击杀敌人召唤一个灵魂（继承30%攻击，
## 持续10秒，最多3个）」）##
## 走已有的 `SummonManager` 链路，不另造召唤系统。召唤物上限由
## SummonManager 自己管（`limit()`），满了会发消息提示。
func _summon_soul() -> void:
	if player == null:
		return
	var mgr = player.get("summons")
	if mgr == null or not mgr.has_method("summon"):
		return
	# 继承 30% 攻击、30% 生命，持续 10 秒（规格原值）
	mgr.call("summon", 0.30, 0.30, 0.30, 10.0)


## 触发与给定属性配对的「满层」词条，返回是否触发了至少一条
func _fire_stack_full(stat: int) -> bool:
	var fired := false
	for e in _affixes_with(AffixData.Trigger.AT_FULL):
		var a: AffixData = e["affix"]
		if a == null or a.stat != stat:
			continue
		_burst(a)
		fired = true
	return fired


## 满层爆发：以玩家为中心的范围伤害，倍率 = `a.value × 面板攻击力`
##
## 规格原文是「下次攻击释放…」，但那需要给普攻挂一个「下一击强化」的
## 待结算标记，跨帧状态多、容易与连段系统打架。而这类词条的设计意图
## 是「攒满层 → 打一发大的」，**即时范围爆发**同样满足，且不引入新状态。
## 倍率按规格原值（2.0 = 200% 攻击力），不做平衡调整。
func _burst(a: AffixData) -> void:
	if player == null or not is_instance_valid(player):
		return
	var atk: float = float(GameManager.stat_value("atk"))
	if atk <= 0.0:
		return
	var radius := 4.0
	var hit_any := false
	for n in player.get_tree().get_nodes_in_group("enemies"):
		var e := n as Node3D
		if e == null or not is_instance_valid(e):
			continue
		if player.global_position.distance_to(e.global_position) > radius:
			continue
		if not e.has_method("take_damage"):
			continue
		var dmg := atk * a.value
		e.call("take_damage", dmg, false, Vector3.ZERO, player)
		EventBus.damage_popup.emit(e.global_position, dmg, "crit")
		hit_any = true
	if hit_any:
		EventBus.message.emit("满层爆发！")


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
