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
## 能量储存参数的**跨条累积器**（见 `_merge_energy_store`）
var _energy_store_pending: Dictionary = {}
var _energy_store_dirty := false
## 残影参数的跨条累积器（自有列 + 融合列各自只带一部分）
var _afterimage_pending: Dictionary = {}
var _afterimage_dirty := false
## 预言自我增益参数的跨条累积器（融合列单独一条 affix）
var _prophecy_pending: Dictionary = {}
var _prophecy_dirty := false

## **规则型 sentinel**（常驻规则，不看 `trigger`）
##
## 这些是「装备穿着即生效的规则」，由 `reload_passives` 装配给 Player。
## 它们的 `trigger` 字段是从句切分推导出来的、**对规则无意义**——
## 故不能走 `_fire(trig)`，必须走 `_fire_all_sentinels`。
const _SENTINEL_RULES := [
	"stationary_buff", "aura_damage", "energy_store", "summon_death_boom",
	# B3 元素序列（2026-09-27）
	"elem_seq_distinct", "elem_seq_same_target", "elem_finale",
	"elem_finale_refresh", "elem_rotate", "elem_next_skill",
	# B4 免死（2026-09-27）
	"cheat_death",
	# B7 残影（2026-09-27）
	"afterimage",
	# B7 预言自我增益（2026-09-27）
	"prophecy_self",
]


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


## **重新装配常驻规则**（`Trigger.ALWAYS` 的 sentinel 词条）
##
## ## 为什么单独一条路径
##
## `_fire(trig)` 是**事件驱动**的——只在「击杀/受击/…」发生时遍历一次。
## 而 `stationary_buff` / `aura_damage` / `summon_death_boom` 这类是
## **常驻规则**（写成 `Trigger.ALWAYS`），需要一个「装备变化时」的时机
## 把规则交给 Player。
##
## ## 为什么先清空再装配
##
## 卸下装备后规则必须消失——否则「站立 buff」会永远挂着。
## 故每轮先清空三个规则槽，再按当前装备重建。
func reload_passives() -> void:
	if player == null:
		return
	# 先清空（卸下装备时规则要消失）
	if player.has_method("clear_passive_rules"):
		player.call("clear_passive_rules")
	# 跨条累积器也要清（否则上一件装备的能量储存参数会残留）
	_energy_store_pending.clear()
	_afterimage_pending.clear()
	_prophecy_pending.clear()
	_afterimage_dirty = false
	_prophecy_dirty = false
	_energy_store_dirty = false
	# 再按当前装备重建
	#
	# **必须扫描全部词条，不能只扫 `ALWAYS`**：这些是**规则型 sentinel**
	#（站立/光环/能量储存/召唤物爆炸），它们的 `trigger` 字段是**从句
	# 切分推导出来的、对规则无意义**。实测「受到伤害的20%储存为能量」
	# 被推成 `ON_HURT`，而「释放储存能量时对周围造成50%」无从句 → `ALWAYS`。
	# 只扫 `ALWAYS` 会让前者**整个丢失**（表现为「只放不攒」）。
	_fire_all_sentinels()
	# 重建完成后提交累积结果（能量储存需要三条合并后才完整）
	_flush_energy_store()
	_flush_afterimage()
	_flush_prophecy()


## 扫描**全部**已装备词条里的规则型 sentinel（忽略 `trigger`）
##
## 与 `_fire(trig)` 的分工：
##   `_fire`           —— **事件驱动**的词条（击杀/受击/…），按 trigger 取
##   `_fire_all_sentinels` —— **常驻规则**（站立/光环/能量储存），不看 trigger
##
## 判据是 `trigger_buff` 是否属于规则型 sentinel 集合——**不是** trigger 值。
func _fire_all_sentinels() -> void:
	if player == null:
		return
	for e in _all_affixes():
		var a: AffixData = e["affix"]
		if a == null or not a.is_trigger():
			continue
		if _SENTINEL_RULES.has(a.trigger_buff):
			_apply_trigger(a, e["inst"])


## 当前装备的**全部**词条（自有 + 融合），不分触发条件
func _all_affixes() -> Array:
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
		for a in tpl.own_affixes:
			if a != null:
				out.append({"affix": a, "inst": inst})
		for a in inst.extra_affixes:
			if a != null:
				out.append({"affix": a, "inst": inst})
	return out


## 装备变化时由 Player 调用（订阅 `equipment_changed`）
func on_equipment_changed() -> void:
	reload_passives()


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


## 治疗结算后（「治疗自身时，对周围敌人造成治疗量50%的圣光伤害」）
## 调用点：Player._on_healed（已挂在 AttributeSystem.heal_listeners 上）
func on_heal() -> void:
	_fire(AffixData.Trigger.ON_HEAL)


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
	# —— 2026-09-27：B1 五族的 sentinel 动作 ——
	# 与上面两个同理：它们是「触发一个动作」，不是「挂一个状态」。
	if a.is_trigger():
		match a.trigger_buff:
			"stationary_buff":
				_activate_stationary(a)
				return
			"spread_mark":
				# 这个动作需要「被击杀目标」才能判定，故不在这里结算——
				# 由 `Player._on_enemy_killed` 经 `on_marked_target_death` 触发。
				return
			"summon_death_boom":
				_register_summon_death_boom(a)
				return
			"aura_damage":
				_activate_aura(a)
				return
			"res_shockwave":
				_arm_res_shockwave(a)
				return
			"energy_store":
				_merge_energy_store(a)
				return
			# —— B3 元素序列（2026-09-27）——
			"elem_seq_distinct", "elem_seq_same_target", "elem_finale", \
			"elem_finale_refresh", "elem_rotate", "elem_next_skill":
				if player.has_method("add_elem_rule"):
					player.call("add_elem_rule", a.trigger_buff,
						a.trigger_params.duplicate(true))
				return
			# —— B7 残影（2026-09-27）——
			"prophecy_self":
				_merge_prophecy_self(a)
				return
			"afterimage":
				_merge_afterimage(a)
				return
			# —— B4 免死机制（2026-09-27）——
			"cheat_death":
				if player.has_method("set_cheat_death_rule"):
					player.call("set_cheat_death_rule",
						a.trigger_params.duplicate(true))
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
##
## ## 触发时机由调用方决定
##
## 旧实现在这里无条件 `buffs.apply` —— 那对「击杀时叠层」是对的
## （`_fire(ON_KILL)` 只在击杀那一刻调一次）。但**暴击叠层**（预言者王冠
## 「暴击叠加1层预言」）不一样：暴击可能在同一帧内发生多次，
## 需要的是「每次暴击 +1 层」而不是「每次事件重挂」。
## 故引入 `_on_crit_stack` 单独入口（见下）。
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


## 暴击时叠层（装备参考2：预言者王冠「暴击叠加1层"预言"（最多6层）」）
##
## ## 与 `_apply_stacked` 的分工
##
## `_apply_stacked` 走 `_fire(trig)`：每次事件遍历一次全部词条、
## **重挂**一条 buff（层数 +1）并检查满层。
## 这条路径对「击杀时叠层」够用，但暴击时**同一帧可能连续暴击多次**
## （多段攻击 / 群体命中），每次都要真的 +1 层。
##
## 故这里直接按 `ON_CRIT` 取词条、逐条 `apply` 一层，
## **不重挂已有的那层**——`BuffHolder.apply` 的语义是「叠一层并刷新时长」，
## 正好符合「暴击叠加1层」。
##
## 满层时触发 `AT_FULL` 配对的爆发（这里是「必暴 + 300% 伤害 + 传播」，
## 由 `_fire_stack_full` → `_burst` 落地），并按默认规则清空层数。
func on_crit_stack() -> void:
	if player == null or player.buffs == null:
		return
	for e in _affixes_with(AffixData.Trigger.ON_CRIT):
		var a: AffixData = e["affix"]
		if a == null or a.stack_max <= 0:
			continue
		var bid := _stack_buff_id(a)
		if bid.is_empty():
			continue
		BuffDefs.register_equipment_stack(bid, a.stat, a.value, a.duration, a.stack_max)
		player.buffs.apply(bid, "equip_trigger")
		if player.buffs.stacks_of(bid) >= a.stack_max:
			if _fire_stack_full(a.stat):
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


# ============================================================
# B1 五族（2026-09-27）
# ============================================================
#
# 这五条的机制基础设施都已存在，缺的只是「接线」。
# 全部走 sentinel 动作（`trigger_buff` 是动作名，不是 buff id）。

## ① 站立静止（「站立不动1秒后获得"大地守护"，移动后失效」）
##
## 把「站够 N 秒」的阈值与 buff 参数存到 player 上，由
## `Player._tick_stationary` 每帧判定。**不在本函数里计时**——
## 触发是「装备变更时」的一次性事件，而计时是每帧的事。
func _activate_stationary(a: AffixData) -> void:
	if player == null or not player.has_method("set_stationary_rule"):
		return
	var p: Dictionary = a.trigger_params
	player.call("set_stationary_rule",
		float(p.get("stationary_seconds", 1.0)),
		float(p.get("dr_pct", 0.0)),
		float(p.get("reflect_pct", 0.0)))


## ② 印记扩散（「印记目标死亡时，印记扩散至周围2名敌人」）
##
## 由 `Player._on_enemy_killed` 调用（那里能拿到被击杀目标）。
## 本函数只负责**取参数**，判定与扩散在 Player 侧（它持有敌人组查询）。
func spread_mark_from(enemy: Node, a: AffixData) -> void:
	if player == null or not player.has_method("spread_mark_from"):
		return
	var count := int(a.trigger_params.get("count", 2)) if a != null else 2
	player.call("spread_mark_from", enemy, count)


## ② 触发「印记目标死亡时」类词条（由 `Player._on_enemy_killed` 调用）
func on_marked_target_death(enemy: Node) -> void:
	for e in _affixes_with(AffixData.Trigger.ON_TARGET_DEATH):
		var a: AffixData = e["affix"]
		if a == null or a.trigger_buff != "spread_mark":
			continue
		spread_mark_from(enemy, a)


## ③ 召唤物死亡爆炸（「护卫死亡时爆炸，造成50%法强伤害」）
##
## 订阅 `SummonManager` 的召唤物死亡信号。**信号已存在**
##（`EnemyBase:43` 声明 `signal died`，`SummonBase` 继承并 emit）——
## 初版清单写「没有死亡事件」是错的（只 grep 了子类，没往上找父类）。
func _register_summon_death_boom(a: AffixData) -> void:
	var mgr = player.get("summons") if player != null else null
	if mgr == null or not mgr.has_method("set_death_boom"):
		return
	mgr.call("set_death_boom", float(a.trigger_params.get("mult", 0.5)))


## ④ 周期伤害光环（「周围3米敌人每秒受到15%攻击力伤害」）
##
## 常驻效果，由 `Player._tick_aura` 每帧推进。
func _activate_aura(a: AffixData) -> void:
	if player == null or not player.has_method("set_aura_rule"):
		return
	var p: Dictionary = a.trigger_params
	player.call("set_aura_rule",
		float(p.get("aura_radius", 3.0)),
		float(p.get("aura_mult", 0.15)),
		float(p.get("aura_interval", 1.0)))


## ⑤ 资源满时下次攻击释放冲击波（「资源满时，下次攻击释放资源冲击波」）
##
## 与已有的 `RESOURCE_FULL` 触发衔接：那条在资源填满的**那一帧**触发，
## 这里把「待释放」标记置位，下次普攻消费。
func _arm_res_shockwave(a: AffixData) -> void:
	if player == null or not player.has_method("arm_res_shockwave"):
		return
	player.call("arm_res_shockwave", float(a.trigger_params.get("mult", 1.0)))


## ⑥ 能量储存（「伤害储存护符」的**跨列单一机制**）
##
## 三行词条（自有 2 行 + 融合 1 行）各自只带**一部分参数**：
##   `{store_pct, cap_pct}` / `{release}` / `{splash_pct}`
## 故必须**累积合并**再交给 Player——逐条覆盖会让后一条冲掉前一条，
## 表现为「只攒不放」或「放但没有范围伤害」。
##
## 累积器在 `reload_passives` 开始时清空（跨装备变更不残留）。
func _merge_energy_store(a: AffixData) -> void:
	for k in a.trigger_params:
		_energy_store_pending[k] = a.trigger_params[k]
	_energy_store_dirty = true


## 把累积的能量储存参数提交给 Player
func _flush_energy_store() -> void:
	if not _energy_store_dirty or player == null:
		return
	if player.has_method("set_energy_store_rule"):
		player.call("set_energy_store_rule", _energy_store_pending.duplicate(true))
	_energy_store_dirty = false


## 满层爆发：以玩家为中心的范围伤害，倍率 = `a.value × 面板攻击力`
##
## 规格原文是「下次攻击释放…」，但那需要给普攻挂一个「下一击强化」的
## 待结算标记，跨帧状态多、容易与连段系统打架。而这类词条的设计意图
## 是「攒满层 → 打一发大的」，**即时范围爆发**同样满足，且不引入新状态。
## 倍率按规格原值（2.0 = 200% 攻击力），不做平衡调整。
func _burst(a: AffixData) -> void:
	if player == null or not is_instance_valid(player):
		return
	# —— 预言者王冠的满层效果（`burst = prophecy`）——
	#
	# 规格：「6层时下一次攻击必定暴击并造成300%伤害，
	#        同时将预言传播至周围2名敌人（各3层）」
	#
	# 这条路**不是**范围爆发，故必须在通用 AOE 之前分流——
	# 否则「必暴 + 300%」会被 `a.value`（0.0）吃成一个 0 伤害的空爆。
	if str(a.trigger_params.get("burst", "")) == "prophecy":
		_trigger_prophecy(a)
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
	# 其余扩展修饰量：挂一条词条
	#
	# **时长来自词条本身**（`a.trigger_params["seconds"]`）——规格里
	# 「击杀后获得3秒暴击率+15%」是**限时**增益，挂成永久会让强度
	# 翻几倍。生成器把从句里的「N秒」写进第 7 槽的参数字典；
	# 没有该键时退化为永久（与旧行为一致）。
	var dur := float(a.trigger_params.get("seconds", 0.0))
	var bid := _stack_buff_id(a)
	BuffDefs.register_equipment_stack(bid, a.stat, a.value, dur, 0)
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


## ⑦ 残影（装备参考2：踏虚神靴「位移·残影歼灭流」）
##
## ## 跨列机制，与能量储存同构
##
## 自有列给「留影 + 引爆」的参数，融合列给「引爆回血」。两列**各自只带
## 一部分参数**，故必须累积合并再交给 Player——逐条覆盖会让后一条
## 冲掉前一条，表现为「能引爆但不回血」或反之。
##
## 复用 `_energy_store_pending` 那套累积器模式：在 `reload_passives`
## 开头清空、末尾 flush。
func _merge_afterimage(a: AffixData) -> void:
	_afterimage_pending["afterimage"] = true
	for k in a.trigger_params:
		_afterimage_pending[k] = a.trigger_params[k]
	_afterimage_dirty = true


## 把累积的残影参数提交给 Player
func _flush_afterimage() -> void:
	if not _afterimage_dirty or player == null:
		return
	if player.has_method("set_afterimage_rule"):
		player.call("set_afterimage_rule", _afterimage_pending.duplicate(true))
	_afterimage_dirty = false
	_prophecy_dirty = false


## 预言满层触发（预言者王冠）
##
## ## 规格
##
## 「6层时下一次攻击必定暴击并造成300%伤害，同时将预言传播至
## 周围2名敌人（各3层）」
## 「融合：预言传播时，自身获得3秒+20%暴击率」
##
## ## 三件事分别怎么落地
##
## ① **必暴 + 300%** —— 挂两条短时词条，由 `Player._compute_basic_damage`
##    消费（`set_force_crit` + `_damage_multiplier`）。**不在这里直接结算伤害**：
##    满层是「下一次攻击」触发的，这一击的伤害必须走普攻的完整管线
##    （元素/护甲/暴击倍率），另算一笔会变成「多打了一下」而不是「这一下变强」。
##
## ② **传播** —— 给周围最近的 N 个敌人各挂 M 层预言。
##    直接 `buffs.apply` 叠层词条（复用同一套 `register_equipment_stack`）。
##
## ③ **融合的自我增益** —— 传播发生时给自己挂暴击率词条。
##    它**必须挂在「真的传播了」之后**（规格写「传播时」）——
##    附近没有敵人时不传播、也就不该给暴击率。
func _trigger_prophecy(a: AffixData) -> void:
	var p := a.trigger_params
	var mult := float(p.get("crit_mult", 3.0))
	var count := int(p.get("spread_count", 2))
	var layers := int(p.get("spread_layers", 3))
	var radius := float(p.get("spread_radius", 5.0))
	# ① 必暴 + 倍率（下一次攻击消费）
	player.call("arm_prophecy", mult)
	EventBus.message.emit("预言应验！")
	# ② 传播：给最近的 N 个敌人各叠 M 层
	#
	# 叠层用的 buff id 必须与玩家自己的预言**同源**（同一套
	# `register_equipment_stack` 的 id 规则），这样敌人身上的层数
	# 在数值上等价——但敌人没有 AT_FULL 词条，故不会自己触发满层爆发。
	# 这是设计意图（规格只说"传播"，没说被传播者也会引爆）。
	var stack_stat := int(p.get("spread_stat", 0))
	var stack_value := float(p.get("spread_value", 0.0))
	var stack_dur := float(p.get("spread_duration", 0.0))
	var stack_max := int(p.get("spread_max", 6))
	var targets: Array = []
	for n in player.get_tree().get_nodes_in_group("enemies"):
		var e := n as Node3D
		if e == null or not is_instance_valid(e):
			continue
		if player.global_position.distance_to(e.global_position) > radius:
			continue
		if e.get("buffs") == null:
			continue
		targets.append(e)
	# 按距离排序取最近的 N 个（`get_nodes_in_group` 顺序不保证）
	targets.sort_custom(func(x, y):
		return player.global_position.distance_to(x.global_position) \
			< player.global_position.distance_to(y.global_position))
	var spread_happened := false
	var bid := "prophecy_spread"
	BuffDefs.register_equipment_stack(bid, stack_stat, stack_value, stack_dur, stack_max)
	# 负效时长 +N%（`debuff_dur_pct` 通道）也作用于本次传播——
	# 传播的是**负面状态**，与命中时施加的其它 debuff 同口径。
	var dur_bonus := float(player.call("_equip_special_mods").get("debuff_dur_pct", 0.0))
	for i in mini(count, targets.size()):
		var tb = (targets[i] as Node3D).get("buffs")
		if tb == null:
			continue
		for j in layers:
			tb.call("apply", bid, "equip_prophecy")
		if dur_bonus > 0.0:
			player.call("extend_buff_duration", tb, bid, dur_bonus)
		spread_happened = true
	# ③ 传播时给自己暴击率（融合列）
	#
	# 参数来自**另一条 affix**（融合列的 `prophecy_self`），
	# 由 `_flush_prophecy` 累积后交给 Player 的 `_prophecy_self_rule`。
	if spread_happened:
		var self_rule: Dictionary = player.get("_prophecy_self_rule")
		var crt_bonus := float(self_rule.get("self_crt", 0.0))
		var crt_dur := float(self_rule.get("self_crt_seconds", 0.0))
		if crt_bonus > 0.0 and crt_dur > 0.0:
			BuffDefs.register_equipment_stack("prophecy_self_crt",
				AttributeSystem.Stat.CRT, crt_bonus, crt_dur, 0)
			player.buffs.apply("prophecy_self_crt", "equip_prophecy")


## 预言自我增益（预言者王冠的融合列）
##
## 规格：「预言传播时，自身获得3秒+20%暴击率」
##
## ## 为什么走累积器而不是直接给 Player
##
## 它必须**并进满层爆发规则**（`_trigger_prophecy`）——因为只在
## 「真的传播了」之后才生效。融合列与自有列是两条独立的 affix，
## 故只能累积合并（与能量储存 / 残影同一套模式）。
##
## `_merge_prophecy_self` 把参数塞进 `_prophecy_pending`；满层爆发词条
## 在自有列、其 `trigger_params` 里带 `burst: "prophecy"`。
## `_flush_prophecy` 把两者**合并**后交给 Player 的
## `set_prophecy_self_rule`。
func _merge_prophecy_self(a: AffixData) -> void:
	for k in a.trigger_params:
		_prophecy_pending[k] = a.trigger_params[k]
	_prophecy_dirty = true


## 把累积的预言自我增益提交给 Player
func _flush_prophecy() -> void:
	if not _prophecy_dirty or player == null:
		return
	if player.has_method("set_prophecy_self_rule"):
		player.call("set_prophecy_self_rule", _prophecy_pending.duplicate(true))
	_prophecy_dirty = false
