class_name SkillSystem
extends RefCounted
## 技能系统 —— 职业形态专属技能的释放、冷却与效果结算
##
## 数据源：ClassDefs（职业 × 形态 × 技能），非 GameBalance 的旧字典钩子。
## 本类是**唯一**的技能执行入口：输入 → Player.cast_skill → 这里。
##
## 与普攻的分工：
##   普攻走 Player._apply_hit（扇形/矩形/AOE 判定 + 元素 + 连击）
##   技能走本类，复用同一套 DamagePipeline / ElementDamage / BuffHolder
##   —— 伤害口径必须一致，否则「技能不如普攻」或反之，手感会崩。
##
## kind 分派（策划技能按机制归类，同类共用一个执行函数）：
##   aoe        范围伤害（跺脚 / 旋风斩 / 鲜血献祭）
##   cone       扇形伤害（肘击）
##   dash       冲刺位移 + 沿途伤害（撞击）
##   pull       拉拽：伤害首个目标 + 施加 debuff + 把自己拉过去
##   buff       纯增益：给自身挂词条（血怒 / 血刃狂舞）
##   projectile 投射物（法师/猎人用，走 Projectile）
##   teleport   瞬移到目标位置或目标背后（影步 / 暗影突袭）
##   multi_hit  对单目标连续 N 次伤害（疾风连打 / 影子风暴）
##   detonate   引爆目标身上的某词条，按层数结算伤害（连锁引爆）
##   spread     把某词条复制给范围内所有敌人（裁决锁链 / 共鸣引爆）

var _cooldowns: Dictionary = {}   # skill_id -> remaining_time
var _rng := RandomNumberGenerator.new()


## 释放技能。
## caster: 施法者（玩家）。resource: 职业资源容器（可为 null）。
## 返回 {ok, reason?, skill?}。
func cast_skill(caster: Node3D, skill_id: String, direction: Vector3,
		resource: ClassResource = null) -> Dictionary:
	# **先查装备技能表**（装备参考2：133 件装备自带主动技能）。
	# 装备技能不属于任何职业，故不在 ClassDefs 里——先查它，
	# 查不到再退回职业技能表。顺序不能反：反过来会因
	# find_skill 返回空而把装备技能当成"未知技能"拒绝。
	var sd: Dictionary = EquipmentSkills.skill_by_id(skill_id)
	if sd.is_empty():
		var found := ClassDefs.find_skill(skill_id)
		if found.is_empty():
			return {"ok": false, "reason": "未知技能 %s" % skill_id}
		sd = found["skill"]

	if _is_on_cooldown(skill_id):
		return {"ok": false, "reason": "技能冷却中（%.1fs）" % get_cooldown_remaining(skill_id)}

	# 资源检查：不足直接拒绝，且**不进入冷却**（否则玩家白等）
	var cost := float(sd.get("cost", 0.0))
	if resource != null and cost > 0.0 and not resource.has(cost):
		return {"ok": false, "reason": resource.lack_reason()}
	# 生命消耗型技能（鲜血献祭）：血量不足也拒绝，避免自杀
	var hp_cost_pct := float(sd.get("hp_cost_pct", 0.0))

	# 先扣资源再进冷却——两处都通过后才算"真的放出去了"
	if resource != null and cost > 0.0:
		resource.spend(cost)
	if hp_cost_pct > 0.0:
		_apply_hp_cost(caster, hp_cost_pct)
	# **冷却缩减（CDR）**——此前全项目零消费点：技能冷却直接取表值，
	# 装备上的 12 条 CDR 词条（`[Stat.CDR, x, true]`）完全没用。
	#
	# ## 必须用减法，且必须 clamp
	#
	# CDR 的语义是「缩短百分之多少」，故 `cd × (1 - cdr)`。
	# **写成加法会让 CD 反而变长**——职业给的 `flat=0.30` 会变成 ×1.3
	#（用户明确要求防这个）。
	#
	# 上界 0.75：防止叠满后 0 冷却（技能无限连放，战斗失去节奏）。
	# 下界 0.0：防止负 CDR 把减法反转成加长。
	var cdr := _cdr_of(caster)
	_cooldowns[skill_id] = maxf(float(sd.get("cooldown", 1.0)) * (1.0 - cdr), 0.05)

	var dir := direction.normalized()
	if dir.length_squared() < 0.001:
		dir = Vector3.FORWARD

	# 连击缩放（策划 7.6 武僧破极：「连击无上限」「破极拳蓄力 1.5~3.5 倍」）。
	# combo_scaled 的技能伤害随当前连击数放大：每 10 连击 +10%，
	# 上限 +100%——不设上限会让武僧在长连击下数值失控。
	if bool(sd.get("combo_scaled", false)):
		var combo := _combo_count(caster)
		var bonus: float = minf(float(combo) / 10.0 * 0.10, 1.0)
		sd = sd.duplicate()
		sd["damage_mult"] = float(sd.get("damage_mult", 1.0)) * (1.0 + bonus)

	# 形态·技能范围（策划 4.1 元素使 +15%、4.5 共鸣师 +30%）。
	# 在这一处统一放大几何参数，所有 _cast_* 自动受益，不必逐个改。
	# **必须 duplicate 后再改**：sd 是 ClassDefs 常量表里的字典，
	# 原地修改会永久污染全局表——放一次技能后所有后续施法都带着放大值。
	var range_mult := _form_range_mult(caster)
	if absf(range_mult - 1.0) > 0.0001:
		sd = sd.duplicate()
		for key in ["radius", "reach", "range", "dash_dist", "behind_offset"]:
			if sd.has(key):
				sd[key] = float(sd[key]) * range_mult

	match str(sd.get("kind", "aoe")):
		"aoe":        _cast_aoe(caster, sd, dir)
		"cone":       _cast_cone(caster, sd, dir)
		"dash":       _cast_dash(caster, sd, dir)
		"pull":       _cast_pull(caster, sd, dir)
		"buff":       _cast_buff(caster, sd)
		"projectile": _cast_projectile(caster, sd, dir)
		"teleport":   _cast_teleport(caster, sd, dir)
		"multi_hit":  _cast_multi_hit(caster, sd, dir)
		"detonate":   _cast_detonate(caster, sd, dir)
		"spread":     _cast_spread(caster, sd, dir)
		"summon":     _cast_summon(caster, sd)
		"stealth":    _cast_stealth(caster, sd)
		_:
			# 未知 kind：报错并**退化为 aoe**，而不是什么都不做。
			#
			# 没有这条时，技能表里写错一个 kind（如 "cone " 带空格、
			# "AOE" 大小写不符）会**静默无效果**——玩家按了技能、资源扣了、
			# 冷却进了，但场上没有任何反馈，排查时也看不到任何日志。
			# 退化成 aoe 至少保留了"打出去了"的可见行为，配合告警能立刻定位。
			#
			# 注意 kind 缺失（不是写错）走的是上面的 "aoe" 默认值，
			# 不会到这里——这条只管"有值但不认识"。
			push_warning("[SkillSystem] 未知技能 kind '%s'（技能 %s），已退化为 aoe；" % [
				str(sd.get("kind", "")), str(sd.get("id", "?"))])
			_cast_aoe(caster, sd, dir)

	# 自身增益：不分 kind，任何技能都能配 self_buffs
	_apply_self_buffs(caster, sd)
	# **治疗与护盾结算**（装备参考2：装备技能大量带「治疗自身 N% 最大生命」
	# /「获得吸收 N% 最大生命的护盾」）。
	#
	# 这两个是**按最大生命百分比**的数值型效果，与 `self_buffs` 的
	# 固定属性词条是两回事——`self_buffs` 只能挂「+X% 属性」这类修饰量，
	# 表达不了「回复 10% 最大生命」这种一次性结算。故单列两条通道。
	_apply_heal_and_shield(caster, sd)
	# 施法后回资源（策划 4.3 奥术汲取「恢复 10 点魔力」等）。
	# 放在扣费之后：否则「消耗 30 回 10」会被算成净消耗 20 的假象——
	# 实际是先扣后回，玩家看到的是净变化。
	var restore := float(sd.get("restore_resource", 0.0))
	# 形态·施法返还（策划 4.3 奥术师「15% 概率返还消耗」）。
	# cast_refund_pct 是无条件返还比例，与下面的 resonance_chance（概率型）分开：
	# 前者是"稳定回一点"，后者是"偶尔放个免费技能"。
	var refund_pct := _form_special_float(caster, "cast_refund_pct", 0.0)
	if restore > 0.0 and resource != null:
		resource.gain(restore * (1.0 + refund_pct))
	if refund_pct > 0.0 and cost > 0.0 and resource != null:
		resource.gain(cost * refund_pct)
	# 「每次施法叠 1 层」的印记。
	#
	# **两个来源指向同一件事**：技能数据的 `stack_buff_per_cast`（策划在
	# 咒焰冲击/虚空湮灭上写死的）与形态 special 的 `*_per_cast` 开关。
	# 它们表达的都是"这个形态每次施法给命中目标叠 1 层印记"，同时生效会
	# 让一次施法叠 2 层——层数上限被提前打满，引爆伤害翻倍。
	# 故合并成一次：技能声明了就用技能声明的 id，否则查形态开关，
	# 最终只叠 1 层，且**叠在被命中的敌人身上**（引爆读的是目标层数）。
	var mark := str(sd.get("stack_buff_per_cast", ""))
	if mark.is_empty():
		mark = _form_mark_id(caster)
	_pending_stack_marks = [mark] if (not mark.is_empty() and _skill_hits_enemies(sd)) else []
	# 形态·共鸣（策划 4.5 共鸣师「20% 概率不消耗资源」）。
	# 放在所有返还之后：它表达的是"这一次白放"，把消耗整体退回去最直观。
	var resonance := _form_special_float(caster, "resonance_chance", 0.0)
	if resonance > 0.0 and cost > 0.0 and resource != null and _rng.randf() < resonance:
		resource.gain(cost)
	# 施放后加连击数（策划 7.5 疾风连打「连击计数翻倍增长」/ 风之步「连击 +3」）
	var cg := int(sd.get("combo_gain", 0))
	if cg > 0 and caster.has_method("add_hit_combo"):
		caster.call("add_hit_combo", cg)
	return {"ok": true, "skill": skill_id, "name": str(sd.get("name", skill_id))}


## 技能是否会对敌人造成命中（决定形态印记要不要生效）
func _skill_hits_enemies(sd: Dictionary) -> bool:
	var kind := str(sd.get("kind", "aoe"))
	return kind in ["aoe", "cone", "dash", "pull", "projectile", "multi_hit",
		"detonate", "spread"]


## 本次施法要叠给命中目标的印记 id（施法开始时确定，_deal_damage 时消费）。
## 必须是实例状态而非局部变量：`cast_skill` 与 `_deal_damage` 之间有
## `_cast_*` 一层间接调用。
var _pending_stack_marks: Array = []


## 给刚被命中的那个敌人叠一层形态印记。
## 在 `_deal_damage` 内调用，故只作用于**真正挨打**的敌人。
func _stack_form_marks_on(caster: Node3D, enemy: Node3D) -> void:
	if enemy == null or caster == null or _pending_stack_marks.is_empty():
		return
	var eb = enemy.get("buffs")
	if eb == null or not eb.has_method("apply"):
		return
	for bid in _pending_stack_marks:
		eb.call("apply", str(bid), "form")


## 施法者当前形态声明的印记 id（无则空串）。
## 映射表在 ClassDefs（普攻也要用同一张）。
func _form_mark_id(caster: Node3D) -> String:
	var cid = caster.get("class_id")
	var slot = caster.get("form_slot")
	if cid == null or slot == null:
		return ""
	return ClassDefs.form_mark_id(str(cid), int(slot))


## 每帧推进冷却（由 Player._physics_process 驱动）
func update_cooldowns(delta: float) -> void:
	for skill_id in _cooldowns.keys():
		var left: float = maxf(float(_cooldowns[skill_id]) - delta, 0.0)
		if left <= 0.0:
			_cooldowns.erase(skill_id)
		else:
			_cooldowns[skill_id] = left


func _is_on_cooldown(skill_id: String) -> bool:
	return _cooldowns.has(skill_id) and float(_cooldowns[skill_id]) > 0.0


func get_cooldown_remaining(skill_id: String) -> float:
	return float(_cooldowns.get(skill_id, 0.0))


## 清空全部冷却（调试/换层用）
func reset_cooldowns() -> void:
	_cooldowns.clear()


# ============================================================
# 各 kind 的执行
# ============================================================

## 范围伤害
##
## 两种形态，由 `sd.at_aim` 决定圆心：
##   · 自身光环型（战吼 / 跺脚 / 冰霜新星）——圆心是**施法者自己**
##   · 目标区域型（地裂术 / 星辰坠落 / 缠绕藤蔓）——圆心是**准心方向
##     `range` 米处**。规格里这类技能写的是「在目标区域召唤…」，
##     若按自身圆心结算会**打错位置**（技能打在脚下而不是指的地方）。
##
## 持续型（`tick_interval` > 0，如毒雾 / 烈焰风暴）交给 `SkillZone` 按 tick
## 结算，本函数只负责开一个区域；否则立即结算一次。
func _cast_aoe(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var radius := float(sd.get("radius", 3.0))
	var center := caster.global_position
	if bool(sd.get("at_aim", false)):
		center += dir * float(sd.get("range", 6.0))
		center.y = caster.global_position.y

	# 持续型：开区域，不在这里结算
	if float(sd.get("tick_interval", 0.0)) > 0.0:
		_spawn_zone(caster, sd, center, radius)
		return

	var mult := float(sd.get("damage_mult", 1.0))
	var knockback := float(sd.get("knockback", 0.0))
	var hits := 0
	for e in _enemies():
		if center.distance_to(e.global_position) > radius:
			continue
		_deal_damage(caster, e, mult, knockback, false, sd)
		_apply_control(e, sd)
		hits += 1
	# 鲜血献祭：每命中 1 敌回复已损失生命的 N%（策划 3.6）
	var heal_pct := float(sd.get("heal_per_hit_pct", 0.0))
	if heal_pct > 0.0 and hits > 0:
		_heal_lost_hp(caster, heal_pct * float(hits))


## 扇形伤害：面朝方向
##
## `reach` 必须**显式兜底**：派生后的技能表里 cone 类的第 5 列（旧 reach）
## 已清零（那列原本是 damage_mult 的副本，会让裂空斩的扇形半径等于 1.8），
## 描述又没给米数（「向前方劈砍」）。若写 `sd.get("reach", 3.0)`，
## 拿到的是 `0.0` 而不是 3.0——**扇形退化成零射程，技能看似没反应**。
## 故用 `maxf` 而不是默认值。
func _cast_cone(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var reach := maxf(float(sd.get("reach", 0.0)), 3.0)
	if sd.has("radius"):
		reach = float(sd["radius"])
	var half := deg_to_rad(float(sd.get("half_angle", 60.0)))
	var mult := float(sd.get("damage_mult", 1.0))
	var knockback := float(sd.get("knockback", 0.0))
	var cos_th := cos(half)
	for e in _enemies():
		var to_e: Vector3 = e.global_position - caster.global_position
		if to_e.length() > reach:
			continue
		if to_e.normalized().dot(dir) < cos_th:
			continue
		_deal_damage(caster, e, mult, knockback, false, sd)
		_apply_control(e, sd)


## 冲刺：玩家沿 dir 位移 dash_dist，沿途矩形内敌人受伤
## 位移本身交给玩家的 `apply_skill_dash`（它知道怎么动 CharacterBody3D）
##
## 装备技能的位移距离写在 `extra.range`（「向前冲锋 6 米」），
## 职业技能写在 `dash_dist`。两者都要认，否则装备的冲锋类技能位移 0 米。
func _cast_dash(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var dist := float(sd.get("dash_dist", 0.0))
	if dist <= 0.0:
		dist = float(sd.get("range", 4.0))
	var width := maxf(float(sd.get("reach", 0.0)), 1.6)
	var mult := float(sd.get("damage_mult", 1.0))
	var knockback := float(sd.get("knockback", 0.0))
	var origin := caster.global_position
	var dest := origin + dir * dist

	# 判定：以原点→终点为轴的胶囊（用点到线段距离近似）
	for e in _enemies():
		if _dist_to_segment(e.global_position, origin, dest) > width:
			continue
		_deal_damage(caster, e, mult, knockback, false, sd)
		_apply_control(e, sd)

	# 位移由施法者自己执行（它持有 velocity / move_and_slide）
	if caster.has_method("apply_skill_dash"):
		caster.call("apply_skill_dash", dir, dist)


## 拉拽：命中射程内最近的敌人 → 伤害 + 施加 debuff + 施法者被拉到目标面前
func _cast_pull(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var rng := float(sd.get("range", 8.0))
	var target := _nearest_enemy_in_cone(caster, dir, rng, 35.0)
	if target == null:
		return
	_deal_damage(caster, target, float(sd.get("damage_mult", 1.0)), 0.0, false, sd)
	# 目标减益（策划 3.5：-30% 攻速/移速）
	_apply_target_buffs(target, sd)
	# 把自己拉到目标面前（留 1.2 米身位，避免重叠）
	var to_target: Vector3 = target.global_position - caster.global_position
	to_target.y = 0.0
	var d := to_target.length()
	if d > 1.2:
		var stop := target.global_position - to_target.normalized() * 1.2
		stop.y = caster.global_position.y
		caster.global_position = stop


## 增益类技能 —— **不是空实现**，按描述里的语义分派。
##
## ## 为什么这里必须做事
##
## 职业技能的 buff 类效果全由 `self_buffs` 字段承载（`cast_skill` 里统一
## `_apply_self_buffs`），所以这条曾经写成 `pass` 是对的。
##
## **但装备技能一条 `self_buffs` 都没有**——它们的语义写在描述里，
## 数值在 `extra` 里（`heal_pct` / `shield_pct` / `radius` / `dr_pct`…）。
## 若继续 `pass`，装备参考2 里 30 多条 buff 类技能（护盾术 / 冰封领域 /
## 圣光审判 / 大地守护…）**按下去什么都不发生**。
##
## 故改为：把 `extra` 里的语义**翻译成三件事**——
##   1. 范围伤害（有 `radius` 或 `damage_mult` 且描述作用于敌人）
##   2. 自身增益词条（`dr_pct` / `spd_pct` / `aspd_pct` / `reflect_pct` /
##      `block_all` / `dodge_pct` → 挂 BuffDefs 词条，数值由 params 覆盖）
##   3. 治疗 / 护盾 / 驱散（`heal_pct` / `shield_pct` / `dispel`）
##
## 三者**可同时生效**——「圣光审判」就是「范围伤害 + 治疗」，
## 「大地守护」是「纯自身减伤」，用同一段代码处理。
func _cast_buff(caster: Node3D, sd: Dictionary) -> void:
	# 1. 范围伤害：描述作用于敌人且伤害倍率 > 0
	if float(sd.get("damage_mult", 0.0)) > 0.0 and not bool(sd.get("self_only", false)):
		var radius := float(sd.get("radius", 3.0))
		var mult := float(sd.get("damage_mult", 1.0))
		for e in _enemies():
			if caster.global_position.distance_to(e.global_position) > radius:
				continue
			_deal_damage(caster, e, mult, 0.0, false, sd)
			_apply_control(e, sd)
	# 2. 自身增益词条（数值走 params 覆盖，不依赖 BuffDefs 的静态值）
	_apply_extra_self_buffs(caster, sd)
	# 3. 治疗 / 护盾 / 驱散 —— 治疗与护盾已在 cast_skill 统一处理，
	#    这里只补驱散。
	if int(sd.get("dispel", 0)) > 0:
		_dispel_self(caster, int(sd["dispel"]))
	# 4. 以血换攻（策划 3.x 血怒：「每秒失去 1% 最大生命换等量攻击力」）
	#
	# `hp_drain_pct` + `atk_from_drain` 此前**零消费者**——技能表里写了、
	# 描述里也写了，但没有任何代码读它们，血怒只有攻速/移速加成生效。
	if float(sd.get("hp_drain_pct", 0.0)) > 0.0 and bool(sd.get("atk_from_drain", false)):
		var b = caster.get("buffs")
		if b != null:
			b.call("apply", "eq_blood_rage", "skill", 1,
				float(sd.get("duration", 8.0)),
				{"hp_drain_pct": float(sd["hp_drain_pct"]), "atk_from_drain": true})


## 把技能 `extra` 里的自身增益语义翻译成 buff 词条
##
## 每个键对应一个 `BuffDefs` 里的**结构词条**，具体数值通过
## `BuffHolder.apply` 的 `override_params` 传入——这样 133 条技能
## 不必为「移速 +25%」「+30%」「+60%」各造一个词条。
func _apply_extra_self_buffs(caster: Node3D, sd: Dictionary) -> void:
	var buffs = caster.get("buffs")
	if buffs == null:
		return
	var dur := float(sd.get("duration_seconds", sd.get("duration", 0.0)))
	var p := {
		"spd_up": float(sd.get("spd_pct", 0.0)),
		"aspd_up": float(sd.get("aspd_pct", 0.0)),
		"atk_up": float(sd.get("atk_pct", 0.0)),
		"dmg_taken_down": float(sd.get("dr_pct", 0.0)),
		"dodge_up": float(sd.get("dodge_pct", 0.0)),
		"reflect_up": float(sd.get("reflect_pct", 0.0)),
		"block_all": bool(sd.get("block_all", false)),
	}
	# 没有任何增益语义时直接返回，避免挂一个全 0 的空词条
	var has_any := false
	for k in p:
		var v = p[k]
		if (v is bool and v) or (v is float and absf(v) > 0.0001):
			has_any = true
			break
	if not has_any:
		return
	buffs.call("apply", "eq_skill_buff", "skill", 1, dur, p)


## 驱散自身负面状态（装备参考2：「清除自身一个/所有负面状态」）
##
## `n` 为要清除的条数，99 表示全部。只清**负面**类别
##（DOT/减速/控制/易伤/削弱），正面词条不受影响。
func _dispel_self(caster: Node3D, n: int) -> void:
	var buffs = caster.get("buffs")
	if buffs == null or not buffs.has_method("active_ids"):
		return
	var debuff_kinds := [BuffDefs.Kind.DOT, BuffDefs.Kind.SLOW, BuffDefs.Kind.CONTROL,
		BuffDefs.Kind.VULN, BuffDefs.Kind.WEAKEN, BuffDefs.Kind.DISPLACE]
	var removed := 0
	# 先收集再删——遍历中改字典会出错
	var victims: Array = []
	for id in buffs.call("active_ids"):
		var row := BuffDefs.get_buff(str(id))
		if row.is_empty() or not debuff_kinds.has(int(row[2])):
			continue
		victims.append(str(id))
		if victims.size() >= n:
			break
	for id in victims:
		buffs.call("remove", id)
		removed += 1
	if removed > 0:
		EventBus.message.emit("驱散 %d 个负面状态" % removed)


## 控制词条（装备参考2：冻结/束缚/嘲讽/恐惧/麻痹/沉默）
##
## `extra.control` 是控制**类别**，需映射到 `BuffDefs` 里实际的词条 id。
## 两者**不同名**：类别 `root`（定身）对应的词条叫 `entangle`（缠绕）——
## 直接拿类别当词条 id 会 `apply` 失败并静默无事发生。
##
## 击退/击飞不在这里做：`_deal_damage` 的 `push` 参数已覆盖，
## 且敌人侧没有 `apply_knockback`（只有 `take_damage` 接受 push 向量）。
const CONTROL_BUFF := {
	"freeze": "freeze", "root": "entangle", "stun": "stun",
	"taunt": "taunt", "fear": "fear", "silence": "silence",
	"paralyze": "paralyze",
}


## 开一个持续型效果区域（装备参考2：毒雾 / 烈焰风暴 / 箭雨 / 风暴之眼）
##
## 复用 `DamageZone`（已解决「节点 free 时协程悬挂」与「像素管线透明不渲染」
## 两个坑），只通过 `on_tick` 回调把伤害结算接回本类——这样区域伤害走的是
## **与技能同一条管线**（面板 ATK × 倍率 + 元素 + 暴击 + 飘字），
## 而不是 `DamageZone` 默认的裸 `take_damage`。
func _spawn_zone(caster: Node3D, sd: Dictionary, center: Vector3, radius: float) -> void:
	var parent := _projectile_parent(caster)
	if parent == null:
		return
	var dur := float(sd.get("duration_seconds", sd.get("duration", 3.0)))
	if dur <= 0.0:
		dur = 3.0
	var mult := float(sd.get("damage_mult", 1.0))
	# 回调：对区域内每个敌人走一次完整结算，返回 true 表示已处理
	var cb := func(_zone, node: Node3D) -> bool:
		if not is_instance_valid(node):
			return true
		_deal_damage(caster, node, mult, 0.0, false, sd)
		_apply_control(node, sd)
		return true
	DamageZone.spawn({
		"radius": radius,
		"duration": dur,
		"tick_interval": maxf(float(sd.get("tick_interval", 1.0)), 0.2),
		"damage": 0.0,          # 伤害由 on_tick 接管
		"target_group": DamageZone.TARGET_ENEMY,
		"position": center,
		"on_tick": cb,
		"color": Color(0.8, 0.4, 0.2, 0.35),
	}, parent)


func _apply_control(enemy: Node3D, sd: Dictionary) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var tb = enemy.get("buffs")
	if tb == null:
		return
	var ctl := str(sd.get("control", ""))
	var dur := float(sd.get("control_seconds", 0.0))
	if ctl.is_empty() or dur <= 0.0:
		return
	var bid := str(CONTROL_BUFF.get(ctl, ctl))
	tb.call("apply", bid, "skill", 1, dur)


## 投射物：复用 Projectile（它已走完整元素管线）
func _cast_projectile(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	# **必须是 Node3D**：`ProjectileSystem.spawn` 的 parent 参数类型就是 Node3D，
	# 且投射物要读父节点的 world_3d / 挂碰撞体。施法者的直接父节点不一定是
	# Node3D——3D 世界被挪进 SubViewport 后，**SubViewport 自己继承的是
	# Viewport 而不是 Node3D**（它是 Node3D 的父级），若施法者恰好挂在
	# SubViewport 直属之下，直接取 get_parent() 会把 SubViewport 传进去，
	# spawn 抛 "not a subclass of the expected argument class" 而静默不出弹。
	var parent := _projectile_parent(caster)
	if parent == null:
		return
	# 形态·远程伤害倍率（策划 3.2 壁垒「远程伤害 -50%」）。
	# 只能在这里乘：投射物一旦生成就与施法者脱钩（ProjectileSystem.spawn
	# 只拿到一个 damage 数值，没有 caster/form 引用），出去之后没法再按形态修正。
	var ranged_mult := 1.0 + _form_special_float(caster, "ranged_dmg_pct", 0.0)
	# 装备词条·投射物伤害 +N%（`projectile_dmg_pct`）——此前零消费。
	# 与上面的形态倍率**叠加**：一个来自职业形态，一个来自装备，语义正交。
	ranged_mult *= 1.0 + _equip_affix_pct(caster, "projectile_dmg_pct")
	# **多发**（装备参考2：冰锥术「发射 3 枚冰锥，每枚造成 60% 法强伤害」）。
	# 旧实现只出一枚，与描述不符。多发时以扇形铺开，避免三枚叠在一条线上
	# 打同一个目标（那等于把倍率乘了 3 倍，手感也不对）。
	var count := maxi(int(sd.get("count", 1)), 1)
	# 散射角：2 枚 12°、3 枚 24°、更多按 12°×n 递增，上限 60°
	var spread_deg: float = 0.0 if count <= 1 else minf(12.0 * float(count - 1), 60.0)
	for i in count:
		var d := dir
		if count > 1:
			var t: float = 0.0 if count == 1 else float(i) / float(count - 1) - 0.5
			d = dir.rotated(Vector3.UP, deg_to_rad(spread_deg * t))
		_spawn_one_projectile(caster, sd, d, parent, ranged_mult)


## 生成一枚投射物（多发循环的单次体）
func _spawn_one_projectile(caster: Node3D, sd: Dictionary, dir: Vector3,
		parent: Node3D, ranged_mult: float) -> void:
	var data := {
		"skill_id": sd.get("id", ""),
		"direction": dir,
		# 出生点必须进 data：走模拟核时投射物**不是节点**，
		# spawn 返回 null，下面那行 `proj.global_position = ...` 就落空了，
		# 子弹会从世界原点射出（表现：技能放出去毫无效果）。
		# 两条路径共用这一份 data，故这里给死。
		"position": caster.global_position + dir * 0.6,
		"speed": float(sd.get("speed", 12.0)),
		"damage": _panel_atk(caster) * float(sd.get("damage_mult", 1.0)) * ranged_mult,
		"lifetime": float(sd.get("lifetime", 2.0)),
		"element": str(sd.get("element", "")),
		"pierce_count": int(sd.get("pierce_count", 0)),
		# 标枪类技能：到射程上限折返（用户决策，见 Projectile.boomerang）。
		# 由技能表声明 `"boomerang": true`，或技能 id/名字含「标枪」自动判定
		#（规格里「雷霆标枪」就是投掷类，但表里没写这个标记）。
		"boomerang": bool(sd.get("boomerang", false))
			or str(sd.get("name", "")).contains("标枪"),
	}
	# 旧节点路径：spawn 返回节点，位置也在这里摆一次（幂等）。
	# 核路径下 spawn 返回 null，位置已由上面的 data["position"] 带进去。
	var proj = ProjectileSystem.spawn(data, parent)
	if proj != null:
		proj.global_position = caster.global_position + dir * 0.6


## 给投射物挑一个合法的 Node3D 父节点。
##
## 优先施法者的直接父节点（投射物随之销毁，房间切走时一起清掉）；
## 直接父节点不是 Node3D 时（SubViewport 是 Viewport，非 Node3D），
## 向上找最近的 Node3D 祖先兜底。
func _projectile_parent(caster: Node3D) -> Node3D:
	var n := caster.get_parent()
	while n != null:
		if n is Node3D:
			return n as Node3D
		n = n.get_parent()
	return null


## 瞬移：去找 dir 方向上射程内最近的敌人，落到它的「背后」（反方向侧）。
## `behind_offset` 决定站位距离；找不到目标时沿 dir 位移 `dash_dist` 兜底
## （影步/暗影突袭要的是"位移能力"，不该因为没敌人就放空）。
func _cast_teleport(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var rng := float(sd.get("range", 6.0))
	var offset := float(sd.get("behind_offset", 1.2))
	var target := _nearest_enemy_in_cone(caster, dir, rng, 90.0)
	if target != null:
		# 「背后」= 目标当前朝向的反侧。敌人没有朝向字段时用我方来向兜底：
		# 把落点放在"目标远离施法者"的那一侧背面
		var from_caster: Vector3 = target.global_position - caster.global_position
		from_caster.y = 0.0
		if from_caster.length_squared() < 0.001:
			from_caster = dir
		var stop := target.global_position + from_caster.normalized() * offset
		stop.y = caster.global_position.y
		caster.global_position = stop
		# 瞬移本身不造成伤害；伤害由 backstab 逻辑接管（见 _deal_damage 的 multiplier）
		if float(sd.get("damage_mult", 0.0)) > 0.0:
			_deal_damage(caster, target, float(sd["damage_mult"]), 0.0, true, sd)
		_apply_target_buffs(target, sd)
		return
	# 无目标：按冲刺位移兜底
	var dist := float(sd.get("dash_dist", 3.0))
	if caster.has_method("apply_skill_dash"):
		caster.call("apply_skill_dash", dir, dist)


## 多段伤害：对射程内最近的目标连打 N 次（疾风连打 10 次 / 影子风暴 5 次）。
## 每次伤害单独结算与飘字——玩家要看到"哒哒哒"的连击感。
func _cast_multi_hit(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var rng := float(sd.get("range", 2.5))
	var hits := maxi(int(sd.get("hit_count", 5)), 1)
	var mult := float(sd.get("damage_mult", 0.4))
	var target := _nearest_enemy_in_cone(caster, dir, rng, 90.0)
	if target == null:
		return
	for i in range(hits):
		if not is_instance_valid(target):
			break
		_deal_damage(caster, target, mult, 0.0, false, sd)
	_apply_target_buffs(target, sd)


## 引爆：把目标身上 `detonate_buff` 声明的词条按层数结算伤害后清除。
## 层数越高伤害越高（策划：连锁引爆每层法强×0.6，3 层时 ×1.8）。
func _cast_detonate(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var rng := float(sd.get("range", 8.0))
	var buff_id := str(sd.get("detonate_buff", ""))
	var per := float(sd.get("per_stack_mult", 0.6))
	var full_bonus := float(sd.get("full_stack_mult", 1.8))
	var full_at := maxi(int(sd.get("full_stack_count", 3)), 1)
	# 引爆范围内**所有**带该词条的敌人（不止最近一个——"引爆所有印记"）
	var any := false
	for e in _enemies():
		if e.global_position.distance_to(caster.global_position) > rng:
			continue
		var tb = e.get("buffs")
		if tb == null:
			continue
		var n: int = int(tb.call("stacks_of", buff_id)) if tb.has_method("stacks_of") else 0
		if n <= 0:
			continue
		var mult := per * float(n)
		if n >= full_at:
			mult = full_bonus
		_deal_damage(caster, e, mult, 0.0, false, sd)
		tb.call("remove", buff_id)
		any = true
	if not any:
		# 没有目标带印记：退化为普通范围伤害（避免技能完全空放）
		_cast_aoe(caster, sd, dir)


## 扩散：把源目标身上的 `spread_buff` 复制给范围内所有敌人（印记连锁）。
func _cast_spread(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var rng := float(sd.get("range", 8.0))
	var radius := float(sd.get("radius", 3.0))
	var buff_id := str(sd.get("spread_buff", ""))
	var src := _nearest_enemy_in_cone(caster, dir, rng, 90.0)
	if src == null:
		return
	_deal_damage(caster, src, float(sd.get("damage_mult", 1.0)), 0.0, false, sd)
	# 把源身上的层数复制给周围敌人
	var src_tb = src.get("buffs")
	var stacks := 1
	if src_tb != null and src_tb.has_method("stacks_of"):
		stacks = maxi(int(src_tb.call("stacks_of", buff_id)), 1)
	for e in _enemies():
		if e == src:
			continue
		if e.global_position.distance_to(src.global_position) > radius:
			continue
		var tb = e.get("buffs")
		if tb != null:
			tb.call("apply", buff_id, "skill", stacks)


# ============================================================
# 结算辅助
# ============================================================

## 对单个敌人结算伤害（与 Player._apply_hit 同口径：面板 ATK × 倍率 × 护甲 × 暴击）
## backstab=true 时套用形态的背刺倍率（策划 6.6 暗影主宰 ×2.5）。
##
## `sd`：技能数据。用于读**技能自身的**元素 / 击飞 / 击退 / 保证暴击。
## 默认空字典——老的调用点不必逐个改（改了也等价于"没有技能级修饰"）。
func _deal_damage(caster: Node3D, enemy: Node3D, mult: float, knockback: float,
		backstab: bool = false, sd: Dictionary = {}) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not enemy.has_method("take_damage"):
		return
	if backstab:
		mult *= _form_special_float(caster, "backstab_mult", 1.0)
	var atk := _panel_atk(caster)
	var target_def := float(enemy.get("defense")) if enemy.get("defense") != null else 0.0
	# 形态·护甲穿透（与普攻同口径，见 player._apply_hit）。
	# 不在这里也做一遍的话，"锁链"形态的穿透只对普攻生效、对技能无效。
	var pierce := _form_special_float(caster, "armor_pierce", 0.0)
	# 技能自身的护甲穿透（装备参考2：「无视 40% 护甲」）
	pierce = maxf(pierce, float(sd.get("armor_pierce", 0.0)))
	target_def *= 1.0 - clampf(pierce, 0.0, 1.0)
	# 形态·近战伤害倍率。技能无远近之分，统一按近战口径结算。
	mult *= 1.0 + _form_special_float(caster, "melee_dmg_pct", 0.0)
	# —— 装备词条·按伤害形状/来源增伤 ——
	#
	# 这两个通道此前**零消费**（数据里有、图鉴会显示、实际无效果）：
	#   `aoe_dmg_pct`        范围伤害 +N%   —— 走 AOE 几何的技能
	#   `projectile_dmg_pct` 投射物伤害 +N% —— 投射物类技能（在 _cast_projectile 接）
	#
	# **按 kind 判定**而不是「有没有 radius」：`cone`/`aoe`/`detonate`/`spread`
	# 都是范围伤害，`pull`/`multi_hit`/`teleport` 是对单，不该吃范围加成。
	if _kind_is_aoe(str(sd.get("kind", ""))):
		mult *= 1.0 + _equip_affix_pct(caster, "aoe_dmg_pct")
	# 装备词条·陷阱伤害 +N%（`trap_dmg_pct`）——此前零消费。
	# 陷阱是「范围伤害」的子集，故**两者叠加**：陷阱技能同时吃
	# aoe_dmg_pct 与 trap_dmg_pct（语义正交——一个是形状、一个是来源）。
	if bool(sd.get("is_trap", false)):
		mult *= 1.0 + _equip_affix_pct(caster, "trap_dmg_pct")
	var result := DamagePipeline.physical(atk, mult, 0.0, target_def)
	var crt := _stat(caster, "crt", 0.05)
	var crd := _stat(caster, "crd", 0.5)
	# 「必定暴击」（装备参考2：影袭「造成 300% 攻击力伤害并必定暴击」）
	var crit := true if bool(sd.get("guaranteed_crit", false)) else _rng.randf() < crt
	var total := DamagePipeline.with_crit(float(result.damage), crit, crd)

	# 击退 / 击飞。**技能声明的击退优先**：`knockback` 参数是调用点给的，
	# 技能表里的 `knockback` / `knockup` 更具体（如「击飞路径敌人」）。
	var kb := knockback
	if float(sd.get("knockback", 0.0)) > 0.0:
		kb = float(sd["knockback"])
	if bool(sd.get("knockup", false)):
		kb = maxf(kb, 6.0)
	var push := Vector3.ZERO
	if kb > 0.0:
		push = (enemy.global_position - caster.global_position)
		push.y = 0.0
		if push.length_squared() > 0.001:
			push = push.normalized() * kb
	enemy.call("take_damage", total, crit, push, caster)
	EventBus.damage_popup.emit(enemy.global_position, total, "crit" if crit else "normal")
	# 技能也能叠元素（走与普攻相同的阈值/联动路径）。
	# 元素来源优先级：**技能自身声明** > 施法者的攻击元素（武器赋予）。
	# 技能级元素是装备参考2 的「造成冰霜伤害」这类——不接的话六把元素
	# 法杖打出来全是同一段无色伤害，元素区别整个消失。
	_stack_form_marks_on(caster, enemy)
	ElementDamage.attack(enemy.get("buffs"), _skill_element(caster, sd))
	# 命中攒资源（策划各职业资源系统）
	_gain_resource_on_hit(caster, crit)


## 给自己挂 self_buffs 声明的词条
func _apply_self_buffs(caster: Node3D, sd: Dictionary) -> void:
	var buffs = caster.get("buffs")
	if buffs == null:
		return
	for b in sd.get("self_buffs", []):
		buffs.apply(str(b.get("id", "")), "skill", int(b.get("stacks", 1)))


## 给目标挂 target_buffs 声明的词条
func _apply_target_buffs(enemy: Node3D, sd: Dictionary) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var tb = enemy.get("buffs")
	if tb == null:
		return
	for b in sd.get("target_buffs", []):
		tb.apply(str(b.get("id", "")), "skill")


## 结算技能的**治疗**与**护盾**（按最大生命百分比）。
##
## 技能表字段：
##   · `heal_pct`      —— 回复自身 `最大生命 × N`
##   · `heal_pct_max`  —— 同上（策划在「生存本能」上用的名字）
##   · `heal_lost_pct` —— 回复**已损失生命**的 N%（策划「背水一战」）
##   · `shield_pct`    —— 获得吸收 `最大生命 × N` 的护盾
##
## **三个治疗字段名必须都认**：`heal_pct` 是装备参考2 的写法，
## `heal_pct_max` / `heal_lost_pct` 是职业技能表的写法（`ClassDefs`）。
## 早期只读 `heal_pct`，于是「生存本能」和「背水一战」两条技能
## **回血完全没发生**——数据在表里、函数也存在（`_heal_lost_hp`），
## 只是键名对不上。
##
## 两者都作用在**施法者**身上（装备技能的描述都是"治疗自身"/"获得护盾"）。
## 施法者没有对应接口时静默跳过——不报错（测试环境的替身可能没实现）。
func _apply_heal_and_shield(caster: Node3D, sd: Dictionary) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var heal_pct := float(sd.get("heal_pct", 0.0))
	if heal_pct <= 0.0:
		heal_pct = float(sd.get("heal_pct_max", 0.0))
	# 回复「已损失生命」的 N%（背水一战）——复用已有的 _heal_lost_hp
	var lost_pct := float(sd.get("heal_lost_pct", 0.0))
	# 周期性治疗（治疗之泉 / 治疗图腾「每秒回复 N% 生命」）
	var tick_pct := float(sd.get("heal_tick_pct", 0.0))
	var shield_pct := float(sd.get("shield_pct", 0.0))
	if heal_pct <= 0.0 and lost_pct <= 0.0 and tick_pct <= 0.0 and shield_pct <= 0.0:
		return
	if lost_pct > 0.0:
		_heal_lost_hp(caster, lost_pct)
	# 取最大生命：优先玩家的 AttributeSystem（`GameManager.attributes`），
	# 回退到施法者自己的 max_hp 字段（敌人/替身）。
	var max_hp := 0.0
	var gm = caster.get_node_or_null("/root/GameManager")
	if gm != null and gm.get("attributes") != null:
		max_hp = float(gm.attributes.max_hp)
	if max_hp <= 0.0:
		var mh = caster.get("max_hp")
		if mh != null:
			max_hp = float(mh)
	if max_hp <= 0.0:
		return

	if heal_pct > 0.0 and gm != null and gm.get("attributes") != null:
		var healed: float = gm.attributes.heal(max_hp * heal_pct)
		if healed > 0.0:
			EventBus.damage_popup.emit(caster.global_position, healed, "heal")

	# 周期性治疗：开一个跟随自身的治疗区域（复用 DamageZone 的 friendly 通道）
	if tick_pct > 0.0:
		_spawn_heal_zone(caster, sd, max_hp * tick_pct)

	if shield_pct > 0.0 and caster.has_method("_add_shield"):
		# 上限取 60%（与形态「溢出转护盾」同一口径，防止无限叠成无敌）
		caster.call("_add_shield", max_hp * shield_pct, 0.60)


## 开一个跟随施法者的治疗区域（治疗之泉 / 治疗图腾 / 生命之泉）
##
## 复用 `DamageZone` 的 `friendly_group` + `heal_per_tick` 通道——
## 那套已经解决了「跟随时长」「节点 free 悬挂」「像素管线透明不渲染」。
## 目标组设为 `player`，故对玩家自己生效。
func _spawn_heal_zone(caster: Node3D, sd: Dictionary, per_tick: float) -> void:
	var parent := _projectile_parent(caster)
	if parent == null:
		return
	var dur := float(sd.get("duration_seconds", sd.get("duration", 5.0)))
	if dur <= 0.0:
		dur = 5.0
	DamageZone.spawn({
		"radius": float(sd.get("radius", 2.0)),
		"duration": dur,
		"tick_interval": 1.0,
		"damage": 0.0,
		"target_group": "",
		"friendly_group": "player",
		"heal": per_tick,
		"follow": caster,
		"color": Color(0.3, 0.9, 0.4, 0.30),
	}, parent)


## 生命消耗型技能（鲜血献祭：消耗 15% 当前生命）
func _apply_hp_cost(caster: Node3D, pct: float) -> void:
	var gm := _game_manager()
	if gm == null or gm.attributes == null:
		return
	var cur: float = gm.attributes.hp
	gm.attributes.take_damage(cur * pct)


## 回复「已损失生命」的 N%（策划 3.6 鲜血献祭）
func _heal_lost_hp(caster: Node3D, pct: float) -> void:
	var gm := _game_manager()
	if gm == null or gm.attributes == null:
		return
	var lost: float = maxf(gm.attributes.max_hp - gm.attributes.hp, 0.0)
	var healed: float = gm.attributes.heal(lost * pct)
	if healed > 0.0:
		EventBus.damage_popup.emit(caster.global_position, healed, "heal")


# ============================================================
# 查询辅助
# ============================================================

func _enemies() -> Array:
	var out: Array = []
	for n in Engine.get_main_loop().get_nodes_in_group("enemies"):
		if n is Node3D and is_instance_valid(n):
			out.append(n)
	return out


## 射程内、面朝方向 cone 角度内最近的敌人（拉拽用）
func _nearest_enemy_in_cone(caster: Node3D, dir: Vector3, max_range: float, half_deg: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_range
	var cos_th := cos(deg_to_rad(half_deg))
	for e in _enemies():
		var to_e: Vector3 = e.global_position - caster.global_position
		to_e.y = 0.0
		var d := to_e.length()
		if d > max_range or d < 0.01:
			continue
		if to_e.normalized().dot(dir) < cos_th:
			continue
		if d < best_d:
			best_d = d
			best = e
	return best


## 点到线段的最短距离（冲刺沿途判定用）
func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var pa := Vector3(p.x - a.x, 0.0, p.z - a.z)
	var ba := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var denom := ba.length_squared()
	if denom < 0.0001:
		return pa.length()
	var t := clampf(pa.dot(ba) / denom, 0.0, 1.0)
	var proj := ba * t
	return (pa - proj).length()


## 施法者面板攻击力
func _panel_atk(caster: Node3D) -> float:
	var gm := _game_manager()
	if gm != null and gm.has_method("stat_value"):
		return float(gm.call("stat_value", "atk"))
	var v = caster.get("atk")
	return float(v) if v != null else 10.0


## 施法者某项属性（取不到用兜底）
func _stat(caster: Node3D, key: String, fallback: float) -> float:
	var gm := _game_manager()
	if gm != null and gm.has_method("stat_value"):
		return float(gm.call("stat_value", key))
	return fallback


## 技能元素：优先**技能自身声明**，其次施法者的攻击元素（武器赋予）。
##
## 装备参考2 里大量技能写「造成冰霜伤害」「雷电伤害」——这是技能级元素，
## 与武器赋予的攻击元素是两回事。不接技能级的话，六把元素法杖打出来
## 全是同一段无色伤害，元素区别整个消失。
func _skill_element(caster: Node3D, sd = null) -> int:
	# sd 可能是 null（老调用点）或空字典（无技能级元素）
	if sd is Dictionary and not (sd as Dictionary).is_empty():
		var key := str((sd as Dictionary).get("element", ""))
		if not key.is_empty():
			var e := _elem_from_key(key)
			if e >= 0:
				return e
		# 「随机元素」：每次施法 roll 一种（装备参考2：元素洪流/元素爆发）
		if bool((sd as Dictionary).get("random_element", false)):
			return _rng.randi_range(0, ElementDefs.Elem.size() - 1)
	var e2 = caster.get("attack_element")
	return int(e2) if e2 != null else -1


## 元素字符串（"fire"/"frost"…）→ `ElementDefs.Elem` 枚举。
## 认不出返回 -1（调用方退回攻击元素）。
##
## 用枚举**名**匹配而不是硬编码数字：`Elem` 的成员顺序若调整，
## 硬编码会静默错位（火变成冰）。
func _elem_from_key(key: String) -> int:
	for e in ElementDefs.Elem.values():
		if ElementDefs.Elem.keys()[e].to_lower() == key.to_lower():
			return e
	return -1


## 读施法者当前连击数（武僧技能缩放用；取不到按 0）
func _combo_count(caster: Node3D) -> int:
	if caster.has_method("get_hit_combo"):
		return int(caster.call("get_hit_combo"))
	return 0


## 读施法者当前形态的 special 数值（如 backstab_mult）。
## 取不到时返回 fallback——形态增益是"锦上添花"，缺失不该让技能失效。
## 实现转发到 ClassDefs.special_num：player 的普攻链路读同一批字段，
## 两处各写一份迟早分叉（见 ClassDefs 里的注释）。
func _form_special_float(caster: Node3D, key: String, fallback: float) -> float:
	var cid = caster.get("class_id")
	var slot = caster.get("form_slot")
	if cid == null or slot == null:
		return fallback
	return ClassDefs.special_num(str(cid), int(slot), key, fallback)


## 施法者的技能范围乘区。优先问 caster 自己（Player 有缓存的 class/form），
## 拿不到就退回按 cid+slot 查表。非玩家施法者（测试桩）返回 1.0。
func _form_range_mult(caster: Node3D) -> float:
	if caster != null and caster.has_method("skill_range_mult"):
		return float(caster.call("skill_range_mult"))
	var cid = caster.get("class_id") if caster != null else null
	var slot = caster.get("form_slot") if caster != null else null
	if cid == null or slot == null:
		return 1.0
	return 1.0 + ClassDefs.special_num(str(cid), int(slot), "skill_range_pct", 0.0)


## 命中攒职业资源（普攻与技能共用规则）
func _gain_resource_on_hit(caster: Node3D, crit: bool) -> void:
	var r = caster.get("class_resource")
	if r != null and r.has_method("on_hit"):
		r.call("on_hit", crit)


func _game_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("GameManager")
	return null


## 读**装备通道**的某个百分比修饰量（如 `aoe_dmg_pct` / `projectile_dmg_pct`）
##
## **不要与 `_form_special_float` 混用**：后者读的是**职业形态**的 special 键。
## 两者有同名键（`ranged_dmg_pct` 既存在于形态、也存在于装备），
## 但来源与语义都不同——混用会让「壁垒形态远程 -50%」和
## 「装备远程 +3%」互相污染。
func _equip_affix_pct(caster: Node3D, key: String) -> float:
	var gm := _game_manager()
	if gm == null:
		return 0.0
	var em = gm.get("equipment_manager")
	if em == null or not em.has_method("special_modifiers"):
		return 0.0
	var sp: Dictionary = em.call("special_modifiers")
	return float(sp.get(key, 0.0))


## 施法者的冷却缩减（0~0.75）
##
## 走 `AttributeSystem.ratio_stat_value` 而**不是** `GameManager.stat_value`：
## 后者走 `get_value`，公式是 `base + flat + base × percent`——
## CDR 的 base 是 0，故 **percent 通道恒失效**。
## 而装备的 CDR 词条恰恰全写在 percent 通道（实测「冷却沙漏 G029」装上后
## `get_value(CDR)` 仍是 0），只有职业的 `flat=0.30` 有效。
##
## `ratio_stat_value` 把 flat 与 percent 直接相加——对 CDR 这类
## 「值本身就是百分比」的属性，两者语义相同，只是数据来源不同。
func _cdr_of(caster: Node3D) -> float:
	var gm := _game_manager()
	if gm == null or gm.get("attributes") == null:
		return 0.0
	var attrs = gm.attributes
	# 施法者不是玩家时不吃 CDR（CDR 来自装备，装备只挂玩家）
	if caster != null and caster.has_method("is_in_group") \
			and not caster.is_in_group("player"):
		return 0.0
	return clampf(float(attrs.ratio_stat_value(AttributeSystem.Stat.CDR)), 0.0, 0.75)


## 该 kind 是否属于「范围伤害」（吃 `aoe_dmg_pct`）
##
## 判据是**几何形状**：以一点/一扇形/一区域覆盖多个目标。
## `pull`（拉单个）/`multi_hit`（打单个多次）/`teleport`（位移）不算范围。
func _kind_is_aoe(kind: String) -> bool:
	return kind in ["aoe", "cone", "detonate", "spread"]


## 召唤类技能（装备参考2：狼灵/护卫/元素灵）。
##
## 技能表字段：
##   · `hp_ratio` / `atk_ratio` / `ap_ratio` —— 继承主人的生命/攻击/法强比例
##   · `lifetime` —— 存活秒数
##   · `count` —— 一次召唤几只（默认 1）
##
## 召唤物由 `SummonManager` 管理（上限、存活跟踪、换房回收）。
## 施法者没有召唤管理器时静默跳过——不报错（装备可能在测试环境用）。
func _cast_summon(caster: Node3D, sd: Dictionary) -> void:
	var mgr = caster.get("summons")
	if mgr == null or not mgr.has_method("summon"):
		return
	var n := maxi(int(sd.get("count", 1)), 1)
	for i in n:
		mgr.call("summon",
			float(sd.get("hp_ratio", 0.4)),
			float(sd.get("atk_ratio", 0.4)),
			float(sd.get("ap_ratio", 0.4)),
			float(sd.get("lifetime", 20.0)))


## 隐身类技能（装备参考2：暗影步/烟雾弹/暗影刺杀）。
##
## 技能表字段：
##   · `stealth_seconds` —— 隐身时长
##   · `speed_pct` —— 隐身期间移速加成
##   · `next_hit_bonus` —— 破隐一击的伤害倍率加成
##   · `invuln` —— 隐身期间是否免疫伤害
##
## 实现落在玩家的 `_stealth_timer` 上（见 Player 的同名字段注释）：
## 隐身=视觉半透明 + 敌人不再以你为目标；破隐=下次攻击吃加成。
func _cast_stealth(caster: Node3D, sd: Dictionary) -> void:
	if not caster.has_method("enter_stealth"):
		return
	caster.call("enter_stealth",
		float(sd.get("stealth_seconds", 3.0)),
		float(sd.get("speed_pct", 0.0)),
		float(sd.get("next_hit_bonus", 0.0)),
		bool(sd.get("invuln", false)))
