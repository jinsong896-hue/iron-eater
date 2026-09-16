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
	var found := ClassDefs.find_skill(skill_id)
	if found.is_empty():
		return {"ok": false, "reason": "未知技能 %s" % skill_id}
	var sd: Dictionary = found["skill"]

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
	_cooldowns[skill_id] = float(sd.get("cooldown", 1.0))

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

	# 自身增益：不分 kind，任何技能都能配 self_buffs
	_apply_self_buffs(caster, sd)
	# 施法后回资源（策划 4.3 奥术汲取「恢复 10 点魔力」等）。
	# 放在扣费之后：否则「消耗 30 回 10」会被算成净消耗 20 的假象——
	# 实际是先扣后回，玩家看到的是净变化。
	var restore := float(sd.get("restore_resource", 0.0))
	if restore > 0.0 and resource != null:
		resource.gain(restore)
	# 「每次施法叠 1 层」的形态被动（策划 4.4 咒焰使：每次施法 +1 层咒焰）。
	# 与 self_buffs 的区别：那个是固定挂一次，这个是可累积的层数上限词条。
	var stack_buff := str(sd.get("stack_buff_per_cast", ""))
	if not stack_buff.is_empty():
		var pb = caster.get("buffs")
		if pb != null:
			pb.call("apply", stack_buff, "skill")
	# 施放后加连击数（策划 7.5 疾风连打「连击计数翻倍增长」/ 风之步「连击 +3」）
	var cg := int(sd.get("combo_gain", 0))
	if cg > 0 and caster.has_method("add_hit_combo"):
		caster.call("add_hit_combo", cg)
	return {"ok": true, "skill": skill_id, "name": str(sd.get("name", skill_id))}


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

## 范围伤害：以自身为圆心
func _cast_aoe(caster: Node3D, sd: Dictionary, _dir: Vector3) -> void:
	var radius := float(sd.get("radius", 3.0))
	var mult := float(sd.get("damage_mult", 1.0))
	var knockback := float(sd.get("knockback", 0.0))
	var hits := 0
	for e in _enemies():
		if caster.global_position.distance_to(e.global_position) > radius:
			continue
		_deal_damage(caster, e, mult, knockback)
		hits += 1
	# 鲜血献祭：每命中 1 敌回复已损失生命的 N%（策划 3.6）
	var heal_pct := float(sd.get("heal_per_hit_pct", 0.0))
	if heal_pct > 0.0 and hits > 0:
		_heal_lost_hp(caster, heal_pct * float(hits))


## 扇形伤害：面朝方向
func _cast_cone(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var reach := float(sd.get("reach", 3.0))
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
		_deal_damage(caster, e, mult, knockback)


## 冲刺：玩家沿 dir 位移 dash_dist，沿途矩形内敌人受伤
## 位移本身交给玩家的 `apply_skill_dash`（它知道怎么动 CharacterBody3D）
func _cast_dash(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var dist := float(sd.get("dash_dist", 4.0))
	var width := float(sd.get("reach", 1.6))
	var mult := float(sd.get("damage_mult", 1.0))
	var knockback := float(sd.get("knockback", 0.0))
	var origin := caster.global_position
	var dest := origin + dir * dist

	# 判定：以原点→终点为轴的胶囊（用点到线段距离近似）
	for e in _enemies():
		if _dist_to_segment(e.global_position, origin, dest) > width:
			continue
		_deal_damage(caster, e, mult, knockback)

	# 位移由施法者自己执行（它持有 velocity / move_and_slide）
	if caster.has_method("apply_skill_dash"):
		caster.call("apply_skill_dash", dir, dist)


## 拉拽：命中射程内最近的敌人 → 伤害 + 施加 debuff + 施法者被拉到目标面前
func _cast_pull(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var rng := float(sd.get("range", 8.0))
	var target := _nearest_enemy_in_cone(caster, dir, rng, 35.0)
	if target == null:
		return
	_deal_damage(caster, target, float(sd.get("damage_mult", 1.0)), 0.0)
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


## 纯增益：只给自身挂词条（效果全由 self_buffs 承载）
func _cast_buff(_caster: Node3D, _sd: Dictionary) -> void:
	pass  # self_buffs 在 cast_skill 统一处理


## 投射物：复用 Projectile（它已走完整元素管线）
func _cast_projectile(caster: Node3D, sd: Dictionary, dir: Vector3) -> void:
	var parent := caster.get_parent()
	if parent == null:
		return
	var data := {
		"skill_id": sd.get("id", ""),
		"direction": dir,
		"speed": float(sd.get("speed", 12.0)),
		"damage": _panel_atk(caster) * float(sd.get("damage_mult", 1.0)),
		"lifetime": float(sd.get("lifetime", 2.0)),
		"element": str(sd.get("element", "")),
		"pierce_count": int(sd.get("pierce_count", 0)),
	}
	# spawn 返回生成好的投射物节点，直接摆到施法者身前
	var proj = ProjectileSystem.spawn(data, parent)
	if proj != null:
		proj.global_position = caster.global_position + dir * 0.6


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
			_deal_damage(caster, target, float(sd["damage_mult"]), 0.0, true)
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
		_deal_damage(caster, target, mult, 0.0)
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
		_deal_damage(caster, e, mult, 0.0)
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
	_deal_damage(caster, src, float(sd.get("damage_mult", 1.0)), 0.0)
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
func _deal_damage(caster: Node3D, enemy: Node3D, mult: float, knockback: float,
		backstab: bool = false) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not enemy.has_method("take_damage"):
		return
	if backstab:
		mult *= _form_special_float(caster, "backstab_mult", 1.0)
	var atk := _panel_atk(caster)
	var target_def := float(enemy.get("defense")) if enemy.get("defense") != null else 0.0
	var result := DamagePipeline.physical(atk, mult, 0.0, target_def)
	var crt := _stat(caster, "crt", 0.05)
	var crd := _stat(caster, "crd", 0.5)
	var crit := _rng.randf() < crt
	var total := DamagePipeline.with_crit(float(result.damage), crit, crd)

	var push := Vector3.ZERO
	if knockback > 0.0:
		push = (enemy.global_position - caster.global_position)
		push.y = 0.0
		if push.length_squared() > 0.001:
			push = push.normalized() * knockback
	enemy.call("take_damage", total, crit, push)
	EventBus.damage_popup.emit(enemy.global_position, total, "crit" if crit else "normal")
	# 技能也能叠元素（走与普攻相同的阈值/联动路径）。
	# 元素来源：施法者的攻击元素（武器赋予）——技能自身若声明了 element
	# 应在这里覆盖，目前战士技能全为物理，留待法系职业实装时扩展。
	ElementDamage.attack(enemy.get("buffs"), _skill_element(caster, null))
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


## 技能元素：优先技能自身声明，其次施法者的攻击元素（武器赋予）
func _skill_element(caster: Node3D, _sd) -> int:
	var e = caster.get("attack_element")
	return int(e) if e != null else -1


## 读施法者当前连击数（武僧技能缩放用；取不到按 0）
func _combo_count(caster: Node3D) -> int:
	if caster.has_method("get_hit_combo"):
		return int(caster.call("get_hit_combo"))
	return 0


## 读施法者当前形态的 special 数值（如 backstab_mult）。
## 取不到时返回 fallback——形态增益是"锦上添花"，缺失不该让技能失效。
func _form_special_float(caster: Node3D, key: String, fallback: float) -> float:
	var cid = caster.get("class_id")
	var slot = caster.get("form_slot")
	if cid == null or slot == null:
		return fallback
	var form := ClassDefs.get_form(str(cid), int(slot))
	var sp: Dictionary = form.get("special", {})
	if not sp.has(key):
		return fallback
	return float(sp[key])


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
