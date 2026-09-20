class_name EnemyMovement
extends Node
## 敌人的位移/传送/潜伏/引力机制 —— 分册 4.x / 5.x / 6.x 的"移动类"机制。
##
## ## 为什么独立成组件
##
## 这 11 个函数（约 230 行）是**一族内聚机制**：突进（含沿途轨迹与减速陷阱）、
## 瞬移（绕背/射击后闪避/换位）、潜伏突袭、引力拉扯。它们互相关联
## （突进结束→陷阱、闪避成功→瞬移、引力窗口→每秒伤害），却与 EnemyBase
## 的 AI 状态机、受击结算、死亡流程无关。
##
## ## 字段归属
##
## 所有机制字段（`_dash_*` / `_reveal_timer` / `_shield*` / `_ambush_*` /
## `_pull_*` / `gravity_pull*`）**留在 EnemyBase 上**——`_physics_process`
## 与状态机直接读写它们，测试也读。故本组件按鸭子类型写 `owner_enemy.xxx`。
##
## ## 两个易错点（搬移时逐字保留的注释）
##
## · `_swap_with_player` 里的 `has_method("force_position")` 是**已知死守卫**
##   （该方法全项目不存在，分支恒走 else），但行为正确——**照搬不删**，
##   删它属于行为清理，另案处理。
## · `pull_player` 的伤害**按秒累加而非每帧结算**——每帧结算会把
##   「30/秒」变成「30×60/秒」。

## 敌人本体（构造时注入）
var owner_enemy: Node3D = null


## 装配：注入敌人节点
func setup(enemy: Node3D) -> void:
	owner_enemy = enemy


## 开始突进冲刺
func start_dash() -> void:
	if owner_enemy._player == null:
		return
	owner_enemy._dash_dir = (owner_enemy._player.global_position - owner_enemy.global_position)
	owner_enemy._dash_dir.y = 0.0
	owner_enemy._dash_dir = owner_enemy._dash_dir.normalized()
	owner_enemy._current_state = EnemyBase.EnemyState.DASH
	# 虚空猎犬：突进距离翻倍（乘在基础时长上）
	owner_enemy._dash_timer = 0.35 * owner_enemy.dash_range_mult
	owner_enemy._attack_timer = owner_enemy.eff_attack_interval()  # 冲完进入攻击冷却
	# 本次突进是否够到过玩家——狱卒猎犬的「突进失败」判定依据（见 _update_dash）
	owner_enemy._dash_hit = false


## 有效移速：基础值 × 减速系数（寒霜/侵蚀/泥沼等词条）
## 所有移动都走这里，减速才会真正生效


## 突进推进
func update_dash(delta: float) -> void:
	owner_enemy._dash_timer -= delta
	owner_enemy.velocity = owner_enemy._dash_dir * owner_enemy.eff_speed() * 2.2
	owner_enemy.move_and_slide()
	# 熔岩猎犬：突进沿途留岩浆轨迹
	owner_enemy._tick_trail(delta)

	if owner_enemy._dash_timer <= 0.0:
		# 骸骨猎犬：突进结束后在原地留下减速陷阱（50%，3 秒）
		if owner_enemy.trap_slow_buff != "":
			spawn_dash_trap()
		# 狱卒猎犬：突进**未命中**后硬直 0.5 秒（分册 4.6）。
		# 「突进失败」的判定口径：突进全程没有进入过攻击距离——
		# 撞墙与超时都归入这一类（分册没区分，且二者表现一致：
		# 这一扑没够着玩家）。命中的话 `_perform_attack` 会把状态推到
		# STAGGERED/CHASE，这里不再补硬直。
		if owner_enemy.dash_stun_seconds > 0.0 and not owner_enemy._dash_hit:
			owner_enemy._stagger_timer = owner_enemy.dash_stun_seconds
			owner_enemy._current_state = EnemyBase.EnemyState.STAGGERED
			return
		owner_enemy._current_state = EnemyBase.EnemyState.CHASE


## 突进减速陷阱：一片地面区域，玩家进入即被减速


## 突进减速陷阱：一片地面区域，玩家进入即被减速
func spawn_dash_trap() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var spec := {
		"position": owner_enemy.global_position, "radius": 2.0, "duration": 3.0,
		"damage": 0.0, "slow_buff": owner_enemy.trap_slow_buff,
		"color": Color(0.6, 0.5, 0.2, 0.4),
	}
	DamageZone.spawn(spec, parent)


# ============================================================
# 传送/位移 · 潜伏 · 护盾（分册 4.x / 5.x / 6.x）
# ============================================================

## 瞬移到目标背后：取目标前向的反方向落点


## 瞬移到目标背后：取目标前向的反方向落点
func teleport_behind_target() -> void:
	if owner_enemy._player == null or not is_instance_valid(owner_enemy._player):
		return
	var back: Vector3 = -(owner_enemy._player as Node3D).global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 0.001:
		back = Vector3.BACK
	owner_enemy.global_position = (owner_enemy._player as Node3D).global_position + back.normalized() * 1.5


## 射击后瞬移：朝远离玩家的方向闪 3 米（熵能幽灵）


## 射击后瞬移：朝远离玩家的方向闪 3 米（熵能幽灵）
func blink_after_shot(dist: float) -> void:
	if owner_enemy._player == null or dist <= 0.0:
		return
	var away: Vector3 = owner_enemy.global_position - (owner_enemy._player as Node3D).global_position
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3.FORWARD
	owner_enemy.global_position += away.normalized() * dist


## 与玩家交换位置（熵能幽魂，限 ≤8 米）


## 与玩家交换位置（熵能幽魂，限 ≤8 米）
func swap_with_player(max_dist: float = 8.0) -> void:
	if owner_enemy._player == null or not is_instance_valid(owner_enemy._player):
		return
	var mine := owner_enemy.global_position
	var theirs: Vector3 = (owner_enemy._player as Node3D).global_position
	if mine.distance_to(theirs) > max_dist:
		return
	owner_enemy.global_position = theirs
	if owner_enemy._player.has_method("force_position"):
		owner_enemy._player.call("force_position", mine)
	else:
		(owner_enemy._player as Node3D).global_position = mine


## 隐身视觉：常态半透明（暗影潜伏者）
##
## 用 `GeometryInstance3D.transparency` 而非材质 alpha——见
## ToonMaterial.set_model_transparency 的注释（改材质 alpha 会掉进透明队列，
## 既拖慢几何又破坏屏幕空间描边读的深度缓冲）。


## 隐身视觉：常态半透明（暗影潜伏者）
##
## 用 `GeometryInstance3D.transparency` 而非材质 alpha——见
## ToonMaterial.set_model_transparency 的注释（改材质 alpha 会掉进透明队列，
## 既拖慢几何又破坏屏幕空间描边读的深度缓冲）。
func apply_stealth_visual() -> void:
	ToonMaterial.set_model_transparency(owner_enemy._model, 0.35)

## 推进潜伏/隐身/护盾计时器
func tick_stealth_timers(delta: float) -> void:
	# 受击显形计时结束后回到隐身
	if owner_enemy._reveal_timer > 0.0:
		owner_enemy._reveal_timer = maxf(owner_enemy._reveal_timer - delta, 0.0)
		if owner_enemy._reveal_timer == 0.0:
			apply_stealth_visual()
	# 脉冲无敌
	if owner_enemy._pulse_timer > 0.0:
		owner_enemy._pulse_timer = maxf(owner_enemy._pulse_timer - delta, 0.0)
	# 护盾冷却
	if owner_enemy.shield_on_timer > 0.0 and owner_enemy._shield <= 0.0:
		owner_enemy._shield_cd -= delta
		if owner_enemy._shield_cd <= 0.0:
			owner_enemy._shield = owner_enemy.shield_amount
			owner_enemy._shield_cd = owner_enemy.shield_on_timer


## 潜伏突袭（湿地伏击者）：玩家进入 3 米内则高伤害突袭
## 返回 true 表示本次已触发突袭（调用方应跳过常规攻击）


## 潜伏突袭（湿地伏击者）：玩家进入 3 米内则高伤害突袭
## 返回 true 表示本次已触发突袭（调用方应跳过常规攻击）
func try_ambush() -> bool:
	if not owner_enemy.ambush or not owner_enemy._ambush_armed or owner_enemy._player == null:
		return false
	if owner_enemy.global_position.distance_to((owner_enemy._player as Node3D).global_position) > owner_enemy.ambush_range:
		return false
	owner_enemy._ambush_armed = false
	# 显形（潜伏态结束）
	ToonMaterial.set_model_transparency(owner_enemy._model, 1.0)
	# 突袭伤害：高倍率
	var dmg: float = float(owner_enemy.atk) * float(owner_enemy.ambush_damage_pct)
	# 传 **owner_enemy** 而非 self：伤害来源必须是敌人节点本身
	# （玩家 take_damage 的 from 参数要求 Node3D，组件不是）
	if (owner_enemy._player as Node3D).has_method("take_damage"):
		(owner_enemy._player as Node3D).call("take_damage", dmg, owner_enemy)
	var bus = owner_enemy._event_bus()
	if bus:
		bus.damage_popup.emit((owner_enemy._player as Node3D).global_position, dmg, "crit")
	return true


## 引力拉扯：把玩家朝自身拉（扭曲巨兽 / 虚空巨兽）
##
## 两种口径：
##   · `owner_enemy.gravity_pull_seconds == 0`（扭曲巨兽）——常驻拉扯，直到光环再次触发
##   · `owner_enemy.gravity_pull_seconds > 0`（虚空巨兽）——按 `owner_enemy._pull_timer` 开窗，
##     窗内**每秒**结算 `owner_enemy.gravity_pull_dps` 伤害（分册 4.9「牵引玩家 2 秒，
##     期间每秒 30 伤」）。伤害按秒累加而非每帧结算——
##     每帧结算会把 30/秒 变成 30×60/秒。


## 引力拉扯：把玩家朝自身拉（扭曲巨兽 / 虚空巨兽）
##
## 两种口径：
##   · `owner_enemy.gravity_pull_seconds == 0`（扭曲巨兽）——常驻拉扯，直到光环再次触发
##   · `owner_enemy.gravity_pull_seconds > 0`（虚空巨兽）——按 `owner_enemy._pull_timer` 开窗，
##     窗内**每秒**结算 `owner_enemy.gravity_pull_dps` 伤害（分册 4.9「牵引玩家 2 秒，
##     期间每秒 30 伤」）。伤害按秒累加而非每帧结算——
##     每帧结算会把 30/秒 变成 30×60/秒。
func pull_player(delta: float, strength: float = 6.0) -> void:
	if not owner_enemy.gravity_pull or owner_enemy._player == null:
		return
	if owner_enemy.gravity_pull_seconds > 0.0:
		if owner_enemy._pull_timer <= 0.0:
			return
		owner_enemy._pull_timer = maxf(owner_enemy._pull_timer - delta, 0.0)
		owner_enemy._pull_tick += delta
		if owner_enemy.gravity_pull_dps > 0.0 and owner_enemy._pull_tick >= 1.0:
			owner_enemy._pull_tick -= 1.0
			damage_pulled_player(owner_enemy.gravity_pull_dps)
	var p := owner_enemy._player as Node3D
	var to_me: Vector3 = owner_enemy.global_position - p.global_position
	to_me.y = 0.0
	if to_me.length() < 0.5:
		return
	p.global_position += to_me.normalized() * strength * delta


## 引力期间的每秒伤害（走玩家自己的 take_damage，与其它伤害同一条结算链）


## 引力期间的每秒伤害（走玩家自己的 take_damage，与其它伤害同一条结算链）
func damage_pulled_player(dmg: float) -> void:
	var p := owner_enemy._player as Node3D
	if p == null or not p.has_method("take_damage"):
		return
	p.call("take_damage", dmg)
	var bus = owner_enemy._event_bus()
	if bus:
		bus.damage_popup.emit(p.global_position, dmg, "aoe")
