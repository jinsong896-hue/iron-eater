class_name SummonBase
extends EnemyBase
## 玩家阵营的召唤物 —— 复用 EnemyBase 的 AI/视觉/受击，只换**阵营与目标**。
##
## ## 为什么继承而不是重写
##
## 召唤物与敌人在机制上高度重合：都要移动、追击、近战/远程攻击、受击、
## 有血条与闪避。差别只有三点：
##   1. **目标相反** —— 召唤物追敌人，敌人追玩家
##   2. **不掉落** —— 召唤物死亡不给金币/装备
##   3. **不进「enemies」组** —— 否则玩家的攻击会打到自己的召唤物
##
## 故继承 EnemyBase、覆写这三处即可，AI/状态机/视觉全部复用。
## 重写一套会立刻产生两份需要同步维护的 AI。
##
## ## 与 EnemyBase 的关键差异点（都在下面的覆写里）
##
## · `_find_player()` 覆写为「找最近的敌人」——`EnemyBase._physics_process`
##   每帧会调它刷新目标，故这是**唯一的换目标入口**
## · `_perform_attack()` 覆写为「打目标」而不是「打玩家」
## · 死亡不走 `die()` 的掉落分支

## 召唤者的攻击力/法强比例（由召唤时传入）
var owner_atk_ratio := 0.4
var owner_ap_ratio := 0.4
## 主人（玩家）——用于取属性比例与判断存在
var owner_player: Node3D = null
## 剩余存活时间（秒）。<=0 表示不限时（由召唤方决定）
var life_timer := 20.0


func _ready() -> void:
	super._ready()
	# **不进 enemies 组**：EnemyBase._ready 会 add_to_group("enemies")，
	# 但召唤物是友方——留在那个组里，玩家的扇形攻击会打到自己人。
	remove_from_group("enemies")
	add_to_group("summons")
	# 血条/精英标/词缀标都不需要（召唤物不显示这些）
	if _hp_bar != null:
		_hp_bar.visible = false
	if _affix_label != null:
		_affix_label.visible = false


## 覆写：目标从「玩家」改为「最近的敌人」。
##
## **这是换阵营的唯一入口**：EnemyBase 的状态机（IDLE/CHASE/ATTACK）
## 全部围绕 `_player` 这个字段运作，把它指向敌人，整套 AI 就自动变成
## 「追着敌人打」——不需要改状态机一行。
func _find_player() -> void:
	var best: Node3D = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if e == self:
			continue
		var d: float = global_position.distance_to((e as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = e
	_player = best


## 覆写：攻击目标（敌人）而不是玩家。
##
## 伤害公式与 EnemyBase 同口径（走 DamagePipeline），只是目标换成 `_player`
##（在召唤物语境下它指向敌人）。
func _perform_attack() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var target_def := float(_player.get("defense")) if _player.get("defense") != null else 0.0
	var result := DamagePipeline.elemental_attack(atk, 1.0, 0.0, target_def, attack_element)
	if _player.has_method("take_damage"):
		_player.call("take_damage", result.damage)
	EventBus.damage_popup.emit(_player.global_position, result.damage, "normal")


## 覆写：召唤物死亡**不计击杀、不掉落**。
##
## 不能直接 `super.die()` —— `EnemyBase.die()` 里有两处只该对敌人生效：
##   ① `gm.kills += 1`（击杀计数：召唤物消失不该算玩家击杀）
##   ② `LootSystem.generate_loot(...)`（掉落：召唤物不给金币/装备）
## 故这里只保留**死亡表现**（特效 + 信号 + 销毁），跳过那两处。
##
## 重入保护照抄父类：同一帧多个伤害来源可能重复触发。
func die() -> void:
	if _current_state == EnemyState.DEAD:
		return
	_current_state = EnemyState.DEAD
	var fx := _effect_field()
	if fx != null:
		fx.play("death", global_position, Color(0.4, 0.8, 1.0))
	died.emit(global_position)
	set_physics_process(false)
	hide()
	await get_tree().create_timer(0.4).timeout
	queue_free()


## 每帧推进存活时间；到点自行消散
func _physics_process(delta: float) -> void:
	if life_timer > 0.0:
		life_timer -= delta
		if life_timer <= 0.0:
			die()
			return
	super._physics_process(delta)


## 按主人属性初始化（召唤时调用）。
##
## `hp_ratio` / `atk_ratio` / `ap_ratio` 是规格里的「继承 N% 生命/攻击/法强」。
func configure_from_owner(owner: Node3D, hp_ratio: float, atk_ratio: float,
		ap_ratio: float, lifetime: float) -> void:
	owner_player = owner
	life_timer = lifetime
	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	var base_hp := float(gm.call("stat_value", "hp"))
	var base_atk := float(gm.call("stat_value", "atk"))
	var base_ap := float(gm.call("stat_value", "ap"))
	max_hp = maxf(base_hp * hp_ratio, 10.0)
	_hp = max_hp
	atk = maxf(base_atk * atk_ratio + base_ap * ap_ratio, 1.0)
