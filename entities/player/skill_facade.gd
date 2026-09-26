class_name PlayerSkills
extends Node
## 玩家的职业 / 形态 / 技能组件 —— 技能执行机器。
##
## ## 边界：为什么 `class_id` / `form_slot` 留在 Player 上
##
## 这两个字段是**实体身份**，不是技能内部状态：`player.gd` 里有 **45 处**
## 战斗逻辑直接读它们（`ClassDefs.special_flag(class_id, form_slot, ...)`
## 遍布挥砍/受击/词条/连击各段）。把它们搬进组件会让 45 个调用点全部变成
## `skills.class_id` —— 改动面巨大而收益为零，且每多一次跨对象访问就多一个
## 出错点。
##
## 故本组件**读写 Player 的这三个字段**（`class_id` / `form_slot` /
## `class_resource`），而不是自己持有。组件负责"怎么装配、怎么施放"，
## 身份数据仍归实体。
##
## ## 职责
##
## · 装配：读 run_info → 写 class_id/form_slot → 建资源容器与技能系统
## · 属性落地：职业基础写进 AttributeSystem、形态增益挂 modifier
## · 技能执行：施放、冷却、按槽位派发、冲刺位移回调
## · 每帧推进：资源回复 + 冷却推进

## 玩家节点（构造时注入）。本组件通过它读写 class_id / form_slot /
## class_resource，以及速度（冲刺位移）与朝向（缺省施法方向）。
var player: Node3D = null

## 技能执行器（冷却 + kind 分派）
var _skills: SkillSystem = null


## 装配：注入玩家节点
func setup(owner_player: Node3D) -> void:
	player = owner_player


# ============================================================
# 装配
# ============================================================

## 装配职业与初始形态。取不到 run_info 时回退战士（保证任何场景都能玩）。
##
## 职业与形态都在**选人界面**选定（策划口径：形态是衍生职业的说法），
## 开局读取，整局固定——局内没有切换入口。
func setup_class() -> void:
	var gm: Node = player.get_node_or_null("/root/GameManager")
	if gm != null:
		player.class_id = str(gm.run_info.get("character", "warrior"))
		player.form_slot = int(gm.run_info.get("form", 0))
	if String(player.class_id).is_empty():
		player.class_id = "warrior"
	player.class_resource = ClassResource.create(player.class_id)
	_skills = SkillSystem.new()
	player.form_slot = clampi(int(player.form_slot), 0, ClassDefs.FORM_SLOTS - 1)
	_apply_class_base()
	apply_form_modifiers()
	grant_start_gear()
	# 技能槽兜底填充：玩家没在技能管理页配过时，至少装上本形态的技能。
	# 不填的话开局技能条全空——技能管理页没打开过就永远放不出技能。
	var lo = _loadout()
	if lo != null:
		lo.autofill_if_empty(String(player.class_id), int(player.form_slot))
	# 被动技能：学会即生效（不占槽位）。必须在 autofill 之后——
	# 填充可能刚把形态自带的被动加进 passives。
	apply_passives()


## 把职业基础属性写进 AttributeSystem。
##
## 必须在 apply_form_modifiers 之前跑：形态的 mods 是**在职业基础之上**
## 的百分比修正（get_value = base + flat + base×percent），
## 顺序反了会让百分比按旧的默认基础算，数值全错。
##
## 用 set_base 而不是 add_modifier：职业基础是"起点"不是"增益"，
## 挂成 modifier 的话会被任何一次 remove_modifiers 连带清掉。
func _apply_class_base() -> void:
	var gm: Node = player.get_node_or_null("/root/GameManager")
	if gm == null or gm.attributes == null:
		return
	var table := ClassBase.full_table(String(player.class_id))
	for stat_id in table:
		gm.attributes.set_base(int(stat_id), float(table[stat_id]))


## 发放当前形态的初始装备（策划每个形态都列了 start_gear）。
##
## 时机：必须在 EquipmentManager 就绪之后，且用 `resolve_or_white_fallback`
## 解析——策划点名的款式（如 A12 铁制护手）在白装层没有注册，
## 直接 get_template 会拿到 null 并静默跳过，玩家开局少装备却看不出来。
## 降级到同槽位白装后，"这个部位有装备"这件事仍然成立。
##
## 跳过已占用的槽位：切房重建玩家时会重跑本函数，不能反复塞装备。
func grant_start_gear() -> void:
	var gm: Node = player.get_node_or_null("/root/GameManager")
	if gm == null:
		return
	var em = gm.equipment_manager
	if em == null:
		return
	var form := ClassDefs.get_form(String(player.class_id), int(player.form_slot))
	for tid in form.get("start_gear", []):
		var tpl := EquipmentDB.resolve_or_white_fallback(StringName(str(tid)))
		if tpl == null:
			continue   # 连槽位都定位不到 = 真的打错了 id，静默跳过
		var slot_id: int = tpl.slot
		if em.get_equipped().has(slot_id):
			continue
		em.equip(slot_id, EquipmentInstance.create(tpl))


## 把当前形态的专属增益挂到属性系统上。
## 先清旧的（source="form"）再加新的——切换形态时不会叠加残留。
func apply_form_modifiers() -> void:
	var gm: Node = player.get_node_or_null("/root/GameManager")
	if gm == null or gm.attributes == null:
		return
	gm.attributes.remove_modifiers("form")
	gm.attributes.remove_modifiers("form_special")
	# 形态若提高了资源上限，同样要清掉再加（见下）
	if player.class_resource != null:
		player.class_resource.clear_max_bonus()
	var form := ClassDefs.get_form(String(player.class_id), int(player.form_slot))
	if form.is_empty():
		return
	for m in form.get("mods", []):
		var key := str(m.get("stat", ""))
		var sid: int = int(AttributeSystem.STAT_BY_NAME.get(key, -1))
		if sid < 0:
			continue
		gm.attributes.add_modifier("form", sid,
			float(m.get("flat", 0.0)), float(m.get("percent", 0.0)))
	_apply_form_resource()


## 形态对职业资源的修正（回复速度 / 上限）。
##
## 单独一个函数而不是塞进上面的 mods 循环：资源不是 AttributeSystem 的属性，
## 它有自己的容器（ClassResource）。策划里「回蓝效率 +20%」「魔力上限 +1.5」
## 这类增益必须落在资源对象上，挂到属性系统是无效的。
##
## `mana_regen_up` / `mana_regen_stack` 都是"回复速度乘区"，语义相同
##（前者是虚空化身的 +1.5 倍率，后者是奥术师的 +20%/层），合并累加。
func _apply_form_resource() -> void:
	if player.class_resource == null:
		return
	var regen := ClassDefs.special_num(String(player.class_id), int(player.form_slot), "mana_regen_up", 0.0)
	regen += ClassDefs.special_num(String(player.class_id), int(player.form_slot), "mana_regen_stack", 0.0)
	player.class_resource.set_regen_mult(1.0 + regen)


## 切换形态（策划：按通关层数解锁）。返回是否切换成功。
func switch_form(slot: int) -> bool:
	if slot == int(player.form_slot):
		return false
	var gm: Node = player.get_node_or_null("/root/GameManager")
	var cleared := 0
	if gm != null:
		# 「通关 N 层」= 当前层数 - 1（打过的层）
		cleared = maxi(int(gm.run_info.get("floor", 1)) - 1, 0)
	if slot > ClassDefs.max_available_form(cleared):
		return false
	player.form_slot = clampi(slot, 0, ClassDefs.FORM_SLOTS - 1)
	apply_form_modifiers()
	EventBus.message.emit("切换形态：%s" % str(
		ClassDefs.get_form(String(player.class_id), int(player.form_slot)).get("name", "?")))
	EventBus.stats_changed.emit()
	return true


# ============================================================
# 技能执行
# ============================================================

## 当前**已装备**的技能列表（HUD 技能条与输入派发共用）。
##
## **读技能槽而不是形态技能表**：玩家在技能管理页配置的 6 个槽才是
## 实际能放什么。形态技能表只是「可选池」——见 skill_loadout.gd 的说明。
##
## 兜底：技能槽尚未初始化时（测试直建 Player / 旧存档）回退到形态技能表，
## 保证任何情况下技能条都有内容。
func current_skills() -> Array:
	var lo = _loadout()
	if lo == null:
		return ClassDefs.skills_of(String(player.class_id), int(player.form_slot))
	return lo.equipped_skills()


## 取技能槽（GameManager 持有；取不到返回 null）
func _loadout():
	var gm: Node = player.get_node_or_null("/root/GameManager")
	if gm == null:
		return null
	return gm.get("skill_loadout")


# ============================================================
# 被动技能 —— 学会即生效，不占技能槽
# ============================================================
#
# 规格（装备参考2）：技能分主动/被动。**主动上槽（最多 6 个），被动不上槽**。
#
# 实现：被动 = 给玩家挂一条**永不过期词条**（`ps_*`，见 buff_defs.gd）。
# 复用 BuffHolder → AttributeSystem 的现成同步链路，不另造一套。

## 把已学会的被动全部挂到玩家身上（幂等）。
##
## 调用时机：装配职业后、切房重建 Player 后。
## 幂等很重要——切房会重建 Player，重复挂会让层数/修正叠加。
func apply_passives() -> void:
	var lo = _loadout()
	if lo == null or player.buffs == null:
		return
	for sid in lo.passives:
		var buff_id := _passive_buff_id(str(sid))
		if buff_id.is_empty():
			continue
		# BuffHolder.apply 内部按 id 记账，重复调用只会刷新而不叠加
		player.buffs.apply(buff_id, "passive")


## 被动技能 id → 词条 id。
##
## 规格里被动技能的 id 与词条 id 一一对应（`ps_vitality` ↔ `ps_vitality`），
## 但技能表用的是**技能 id**（可能与词条 id 不同名）。
## 目前两者同名；找不到时返回空串（静默跳过，不影响其它被动）。
func _passive_buff_id(skill_id: String) -> String:
	if skill_id.begins_with(SkillLoadout.PASSIVE_BUFF_PREFIX):
		return skill_id
	# 技能 id 与词条 id 不同名时，按词条表反查一次（get_buff 返回空数组 = 不存在）
	var guess := SkillLoadout.PASSIVE_BUFF_PREFIX + skill_id
	if not BuffDefs.get_buff(guess).is_empty():
		return guess
	return ""


## 当前形态的技能范围乘区（策划 4.1 元素使 +15%、4.5 共鸣师 +30%）。
## SkillSystem 在施法前用它放大技能的 reach/radius/range/dash_dist。
func skill_range_mult() -> float:
	return 1.0 + ClassDefs.special_num(
		String(player.class_id), int(player.form_slot), "skill_range_pct", 0.0)


## 释放技能（对外入口：HUD 点击 / 测试直调）。
## 返回 {ok, reason?}；方向缺省用面朝方向。
func cast_skill(skill_id: String, direction: Vector3 = Vector3.ZERO) -> Dictionary:
	if _skills == null:
		return {"ok": false, "reason": "技能系统未初始化"}
	var dir := direction
	if dir.length_squared() < 0.001:
		dir = InputManager.get_attack_direction_3d()
	if dir.length_squared() < 0.001:
		dir = player.get("_facing")
	var r: Dictionary = _skills.cast_skill(player, skill_id, dir, player.class_resource)
	if bool(r.get("ok", false)):
		EventBus.player_skill_cast.emit(skill_id, dir)
	else:
		EventBus.message.emit(str(r.get("reason", "无法施放")))
	return r


## 按槽位放技能（HUD 技能条 1~6 键）
func cast_skill_slot(slot: int) -> Dictionary:
	var list := current_skills()
	if slot < 0 or slot >= list.size():
		return {"ok": false, "reason": "该槽位无技能"}
	return cast_skill(str(list[slot].get("id", "")))


## 技能剩余冷却（HUD 冷却遮罩用）
func skill_cooldown_left(skill_id: String) -> float:
	return _skills.get_cooldown_remaining(skill_id) if _skills else 0.0


## 冲刺类技能的位移执行（SkillSystem 判定完伤害后回调这里）。
## 用速度脉冲而不是直接改位置——否则会穿过墙体。
func apply_skill_dash(dir: Vector3, dist: float) -> void:
	if dir.length_squared() < 0.001:
		return
	# 以固定速度冲刺：把速度设为 dir × (距离 / 假设冲刺时长)
	var dur := 0.18
	player.velocity.x = dir.normalized().x * (dist / dur)
	player.velocity.z = dir.normalized().z * (dist / dur)


## 技能输入轮询（由 player 的 _physics_process 转发；打字时不调）
func poll_input() -> void:
	for slot in range(6):
		if not InputManager.skill_pressed(slot):
			continue
		# 先消费再施放：即使施放被拒（冷却/资源不足）也不该在同一缓冲窗口里
		# 反复重试——那是「按一次放好几次」或「一直提示冷却中」的来源
		InputManager.consume_skill(slot)
		cast_skill_slot(slot)
		return   # 一帧只放一个技能，避免多键同按时连放


# ============================================================
# 每帧推进（由 player 转发）
# ============================================================

## 资源自然回复 + 技能冷却推进。**两者都无条件走**，不受状态机影响。
func tick(delta: float) -> void:
	if player.class_resource != null:
		var before: float = player.class_resource.value
		player.class_resource.tick(delta)
		# 装备触发条件（装备参考2：「资源满时，下次攻击释放资源冲击波」
		# 「储存满时…」等 4 条）——资源**刚好**填满的那一帧触发一次。
		#
		# 用「跨过满值」判定而不是「当前等于满值」：后者每帧都会命中，
		# 会让效果持续重放。`before < max` 且 `now >= max` 才是「填满的瞬间」。
		if before < player.class_resource.max_value() \
				and player.class_resource.value >= player.class_resource.max_value() - 0.001:
			if player.equip_fx != null:
				player.equip_fx.on_resource_full()
	if _skills != null:
		_skills.update_cooldowns(delta)


## 击杀时给职业资源充能（怒气/魔力等）
func on_kill() -> void:
	if player.class_resource != null:
		player.class_resource.on_kill()


## 命中时给职业资源充能（crit 影响充能量）
func on_hit(crit: bool) -> void:
	if player.class_resource != null:
		player.class_resource.on_hit(crit)


## 受伤时给职业资源充能
func on_damage_taken(amount: float) -> void:
	if player.class_resource != null:
		player.class_resource.on_damage_taken(amount)


## 清空所有技能冷却（装备词条·击杀刷新冷却用）
func reset_skill_cooldowns() -> void:
	if _skills != null:
		_skills.reset_cooldowns()
