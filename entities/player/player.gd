class_name Player
extends CharacterBody3D
## 玩家控制器 —— HD-2D 重构版
## 移动：WASD | 攻击：方向键 | 技能：Q/E/R/F
## 奔跑：Shift 或双击方向 | 翻滚：空格
## 连段：普攻1→2→3→4；奔跑攻击→3→4；空格+方向键=跳跃攻击→3→4

@export var move_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var acceleration: float = 20.0
@export var deceleration: float = 25.0
@export var base_attack_interval := 0.6
@export var dodge_speed := 12.0
@export var dodge_duration := 0.2
@export var dodge_cooldown := 0.8

var buffs = null                  # BuffHolder：词条与元素叠层容器（_ready 创建）
var attack_element := -1          # 攻击附带元素（ElementDefs.Elem；装备赋予，-1 = 纯物理）
var _attack_timer := 0.0          # 当前攻击冷却
var _facing := Vector3.FORWARD
var _is_sprinting := false
var _is_dodging := false
var _dodge_cooldown_timer := 0.0

# 以下四个字段由 entities/player/states/*.gd 通过 player.xxx 跨文件读写，
# 故不加下划线前缀——加了会被单文件作用域分析的静态检查误判为「未使用」。
## 方向键「按下沿」的检测用：记录上一次见到的方向，方向变化时才算新按下沿。
## 不能靠每帧刷新的时间戳判定双击——那会让窗口退化成「任意两帧方向一致」。
var prev_raw_input := Vector3.ZERO
## 距离上一次「方向按下沿」的时长（秒），用于双击判定
var since_dir_press := 99.0
## 已持续奔跑的时长（秒）。冲撞需要它超过 SPRINT_ATTACK_MIN_HOLD。
var sprint_hold := 0.0

# 翻滚状态用（dodge_state.gd 读写）
## 翻滚无敌帧剩余时间（秒）
var dodge_timer := 0.0

# 连段状态机
var _combo: AttackCombo = null

# 奔跑攻击：冲撞状态
var _sprint_attack_timer := 0.0
var _sprint_attack_dir := Vector3.ZERO

# 跳跃攻击：三阶段（后跳蓄力→俯冲→落地恢复）
enum JumpPhase { NONE, BACKHOP, DIVE, LAND }
var _jump_phase: JumpPhase = JumpPhase.NONE
var _jump_phase_timer := 0.0
var _jump_attack_dir := Vector3.ZERO

# 连击计数（HUD 显示 + 连击伤害加成）
var _hit_combo_count := 0
var _hit_combo_time := 0.0

# 连段动作状态
var _current_combo_stage := 0        # 正在执行的段位（霸体/朝向锁判定用）
var _current_attack_cooldown := 0.0  # 本次攻击的总冷却（取消窗口比例计算）
var _finisher_armor_timer := 0.0     # 终结技霸体剩余时间

# 状态机：把 _physics_process 里手搓的四个模式（移动/翻滚/冲撞/跳跃）拆成状态类
# 每个状态 = 原分支的逐行搬移；数据与共享动作仍留在 Player 上
var _state_machine: StateMachine = null

# 受击闪红（与敌人同款反馈；玩家此前完全没有任何受击视觉）
var _model: MeshInstance3D = null       # 模型节点（player.tscn 的 Model）
var _flash_timer := 0.0                 # 闪红剩余时间
var _base_color := Color.WHITE          # 模型本色（闪红退回用）
## 受击闪红时长（秒）
const HIT_FLASH_DURATION := 0.18

const ATTACK_REACH := 2.0

## 顿帧时的时间缩放（配合 _hitstop，必须保证还原）
const HITSTOP_TIME_SCALE := 0.05

## 拾取/吞噬的可达距离（米）
const PICKUP_RANGE := 2.5


func _ready() -> void:
	add_to_group("player")
	_combo = AttackCombo.new()
	# 词条/元素容器：敌人的元素攻击会往这里叠层，控制/易伤也从这里读
	if buffs == null:
		buffs = BuffHolder.new(self)
	_setup_state_machine()
	_setup_hit_model()
	# 击杀回血（监听全局敌死信号）
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("enemy_died"):
		bus.enemy_died.connect(_on_enemy_killed)
	# 装备变更 → 重算攻击元素（武器决定元素，护甲/饰品只给元素亲和）
	if bus and bus.has_signal("equipment_changed"):
		bus.equipment_changed.connect(func(_s, _i): _refresh_attack_element())
	_refresh_attack_element()


## 装配受击闪红用的模型引用。
## 复制一份材质再挂到模型上——直接改 scene 里的共享材质会让
## 同场景的多个玩家实例（或复用的资源）互相影响。
func _setup_hit_model() -> void:
	_model = get_node_or_null("Model") as MeshInstance3D
	if _model == null:
		return
	var src := _model.get_active_material(0) as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	if src != null:
		mat = src.duplicate() as StandardMaterial3D
	_base_color = mat.albedo_color
	_model.material_override = mat


## 装配状态机：注册五个状态并进入默认的 MoveState
## 用 load() 而非 preload()：状态类引用 Player（PlayerState.player 的类型），
## preload 会让 player.gd ↔ 状态类在解析期形成循环依赖，缓存失效时无法解析
func _setup_state_machine() -> void:
	_state_machine = StateMachine.new()
	var move_state = load("res://entities/player/states/move_state.gd").new()
	var dodge_state = load("res://entities/player/states/dodge_state.gd").new()
	var sprint_state = load("res://entities/player/states/sprint_attack_state.gd").new()
	var jump_state = load("res://entities/player/states/jump_attack_state.gd").new()
	var dead_state = load("res://entities/player/states/dead_state.gd").new()
	var entrance_state = load("res://entities/player/states/entrance_state.gd").new()

	for s in [move_state, dodge_state, sprint_state, jump_state, dead_state, entrance_state]:
		s.setup(self)

	_state_machine.add_state("MoveState", move_state)
	_state_machine.add_state("DodgeState", dodge_state)
	_state_machine.add_state("SprintAttackState", sprint_state)
	_state_machine.add_state("JumpAttackState", jump_state)
	_state_machine.add_state("DeadState", dead_state)
	_state_machine.add_state("EntranceState", entrance_state)
	_state_machine.set_initial("MoveState")


## 播放入场动作（进入初始房间时由 GameRoot 调用）。
## 期间玩家原地不动、不接受任何操作；播完自动回 MoveState。
## duration <= 0 时用 EntranceState 的默认时长。
func play_entrance(duration: float = -1.0) -> void:
	if _state_machine == null:
		return
	var data := {} if duration <= 0.0 else {"duration": duration}
	_state_machine.transition_to("EntranceState", data)


## 当前状态名（供调试/测试观察）
func current_state_name() -> String:
	return _state_machine.current_state_name() if _state_machine else ""


## 切换到指定状态（供测试与外部强制切换）
## 注意：正常游玩由 MoveState 在检测到输入时自行转移；
## 这里直接切状态会走 enter()，即同步执行该状态的一次性初始化。
func enter_state(state_name: String) -> void:
	if _state_machine:
		_state_machine.transition_to(state_name)


## 击杀回血回调
func _on_enemy_killed(_enemy: Node, _pos: Vector3, _loot: Array) -> void:
	if GameBalance.KILL_HEAL <= 0.0:
		return
	if GameManager.attributes and not GameManager.attributes.is_dead():
		var healed: float = GameManager.attributes.heal(GameBalance.KILL_HEAL)
		# 绿色回血飘字
		var bus := get_node_or_null("/root/EventBus")
		if bus and healed > 0.0:
			bus.damage_popup.emit(global_position, healed, "heal")


func _physics_process(delta: float) -> void:
	# 定时器无条件递减（在任何状态里都要走，移入状态会改变语义）
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)
	_sprint_attack_timer = maxf(_sprint_attack_timer - delta, 0.0)
	_finisher_armor_timer = maxf(_finisher_armor_timer - delta, 0.0)
	# 受击闪红衰减
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		_update_flash()
	# 自动拾取（设置开启时生效）
	_update_auto_pickup(delta)

	# 连击窗口推进 + 连击数计时
	if _combo:
		_combo.tick(delta)
	if _hit_combo_time > 0.0:
		_hit_combo_time = maxf(_hit_combo_time - delta, 0.0)
		if _hit_combo_time == 0.0:
			_hit_combo_count = 0

	# 词条/元素推进：DOT 结算 + 元素衰减 + 控制判定
	if buffs != null:
		var tick_out: Dictionary = buffs.tick(delta)
		var dot: float = float(tick_out.get("dot", 0.0))
		if dot > 0.0:
			take_damage(dot)
			if GameManager.attributes and GameManager.attributes.is_dead():
				return
		# 硬控（冰冻/麻痹/眩晕/定身）：期间不能移动也不能出招，只保留击退位移
		if buffs.is_controlled():
			velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
			move_and_slide()
			return
		# 减速：移速按词条比例下调（寒霜/泥沼等）
		var slow: float = buffs.total_slow()
		if slow > 0.0:
			velocity.x *= (1.0 - slow)
			velocity.z *= (1.0 - slow)

	# 具体行为交给当前状态（移动/翻滚/冲撞/跳跃/死亡）
	_state_machine.physics_update(delta)


# ============================================================
# 攻击系统：四段普攻 + 奔跑攻击 + 跳跃攻击
# ============================================================


## 是否处于攻击后摇取消窗口（冷却后半段）
func _in_cancel_window() -> bool:
	if _current_attack_cooldown <= 0.0:
		return false
	var elapsed := _current_attack_cooldown - _attack_timer
	return elapsed >= _current_attack_cooldown * GameBalance.CANCEL_WINDOW_RATIO


## 取消当前攻击后摇（清冷却；连段保持——下一击按段位推进）
func _cancel_current_attack() -> void:
	_attack_timer = 0.0
	_current_attack_cooldown = 0.0


## 普攻：取段位参数 → 判定 → 冷却
func _start_normal_attack() -> void:
	if _combo == null:
		return
	var stage: int = _combo.request_normal()
	if stage == 0:
		return
	var params: Array = _combo.stage_params(stage)
	_combo.begin_attack()
	var aspd := GameManager.stat_value("aspd")
	_attack_timer = params[0] / maxf(aspd, 0.1)
	_current_attack_cooldown = _attack_timer
	_current_combo_stage = stage
	# 终结技（第 4 段）霸体
	if stage == combo_stages_size() and GameBalance.FINISHER_SUPERARMOR:
		_finisher_armor_timer = _attack_timer
		_spawn_armor_visual()
	_perform_melee_attack(params[1], params[2], deg_to_rad(params[3]), params[4])
	# 挥砍视觉：终结技（第 4 段）金色大扇形，其余白
	if stage == combo_stages_size():
		_spawn_slash_visual(params[2], deg_to_rad(params[3]), Color(1.0, 0.8, 0.2, 0.55))
	else:
		_spawn_slash_visual(params[2], deg_to_rad(params[3]))
	_combo.end_attack()


## 连段总段数（从 GameBalance 取，终结技判定用）
func combo_stages_size() -> int:
	return GameBalance.COMBO_STAGES.size()


## 霸体视觉：玩家金色描边光（终结技期间）
## 材质与网格静态缓存——原先每次放终结技都新建 SphereMesh + StandardMaterial3D，
## 真实 GPU 上新材质会触发着色器编译，造成终结技瞬间掉帧。
static var _armor_mat: StandardMaterial3D = null
static var _armor_mesh: SphereMesh = null

func _spawn_armor_visual() -> void:
	if _armor_mesh == null:
		_armor_mesh = SphereMesh.new()
		_armor_mesh.radius = 0.7
		_armor_mesh.height = 1.4
	if _armor_mat == null:
		_armor_mat = StandardMaterial3D.new()
		_armor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_armor_mat.albedo_color = Color(1.0, 0.8, 0.3, 0.25)
		_armor_mat.emission_enabled = true
		_armor_mat.emission = Color(1.0, 0.75, 0.2)
		_armor_mat.emission_energy_multiplier = 1.2
		_armor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var aura := MeshInstance3D.new()
	aura.mesh = _armor_mesh
	aura.material_override = _armor_mat
	aura.position = Vector3(0, 0.9, 0)
	add_child(aura)
	# 随霸体计时消失
	var tween := create_tween()
	tween.tween_interval(_finisher_armor_timer)
	tween.tween_callback(aura.queue_free)


## 奔跑攻击：突进冲撞（矩形判定），攻击后退出奔跑
func _start_sprint_attack() -> void:
	if _combo == null or not _combo.request_sprint():
		return
	var params: Array = GameBalance.SPRINT_ATTACK
	_combo.begin_attack()
	var aspd := GameManager.stat_value("aspd")
	_attack_timer = params[0] / maxf(aspd, 0.1)

	# 冲撞：朝面向方向冲刺
	_sprint_attack_dir = _facing
	_sprint_attack_timer = 0.18
	_is_sprinting = false  # 消耗冲刺惯性

	_perform_charge_attack(params[1], params[2], params[3], params[4])
	# 冲撞视觉：橙红色宽扇形
	_spawn_slash_visual(params[2], deg_to_rad(55.0), Color(1.0, 0.45, 0.15, 0.5))
	_combo.end_attack()


## 跳跃攻击启动：后跳蓄力 → 俯冲 → 落地 AOE
func _start_jump_attack() -> void:
	if _combo == null or not _combo.request_jump():
		return
	var params: Array = GameBalance.JUMP_ATTACK
	_combo.begin_attack()
	var aspd := GameManager.stat_value("aspd")
	_attack_timer = params[0] / maxf(aspd, 0.1)

	_jump_attack_dir = _facing
	_jump_phase = JumpPhase.BACKHOP
	_jump_phase_timer = GameBalance.JUMP_ATTACK_PHASES[0]
	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer, params[0])  # 复用冷却防连发


## 跳跃攻击阶段推进
## 已搬移至 states/jump_attack_state.gd；_jump_phase 的推进在那里进行


## 跳跃攻击落地：圆形 AOE 判定
func _perform_jump_landing() -> void:
	var params: Array = GameBalance.JUMP_ATTACK
	_perform_aoe_attack(params[1], params[4], params[5])
	# 落地视觉：青色全向扇形（360°）+ 强震屏
	_spawn_slash_visual(params[4], PI, Color(0.4, 0.9, 1.0, 0.5))
	_screen_shake(0.3)
	# 视觉反馈：落地消息
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.message.emit("落地斩！")


## 扇形近战判定（普攻/连段用）
func _perform_melee_attack(multiplier: float, reach: float, half_angle: float, knockback: float) -> void:
	var hit_any := _hit_enemies_in_cone(multiplier, reach, half_angle, knockback)
	if hit_any:
		_register_hit_combo()
	_finish_attack_feedback(hit_any)


## 冲撞判定（奔跑攻击）：面向矩形区域
func _perform_charge_attack(multiplier: float, length: float, width: float, knockback: float) -> void:
	var hit_any := false
	var width_sq := (width / 2.0) * (width / 2.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not _is_valid_enemy(enemy):
			continue
		var to_enemy: Vector3 = (enemy as Node3D).global_position - global_position
		# 矩形判定：沿面向投影在 [0, length]，侧向偏移 < width/2
		var forward_dist := to_enemy.dot(_facing)
		if forward_dist < 0.0 or forward_dist > length:
			continue
		var lateral := to_enemy - _facing * forward_dist
		if lateral.length_squared() > width_sq:
			continue
		_apply_hit(enemy as Node3D, multiplier, knockback)
		hit_any = true
	if hit_any:
		_register_hit_combo()
	_finish_attack_feedback(hit_any)


## 圆形 AOE 判定（跳跃攻击落地）
func _perform_aoe_attack(multiplier: float, radius: float, knockback: float) -> void:
	var hit_any := false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not _is_valid_enemy(enemy):
			continue
		var dist: float = (enemy as Node3D).global_position.distance_to(global_position)
		if dist > radius:
			continue
		_apply_hit(enemy as Node3D, multiplier, knockback)
		hit_any = true
	if hit_any:
		_register_hit_combo()
	_finish_attack_feedback(hit_any)


## 扇形内的敌人命中
func _hit_enemies_in_cone(multiplier: float, reach: float, half_angle: float, knockback: float) -> bool:
	var hit_any := false
	var cos_threshold := cos(half_angle)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not _is_valid_enemy(enemy):
			continue
		var to_enemy: Vector3 = (enemy as Node3D).global_position - global_position
		if to_enemy.length() > reach:
			continue
		if to_enemy.normalized().dot(_facing) < cos_threshold:
			continue
		_apply_hit(enemy as Node3D, multiplier, knockback)
		hit_any = true
	return hit_any


## 对单个敌人结算伤害与击退
func _apply_hit(enemy: Node3D, multiplier: float, knockback: float) -> void:
	var atk := GameManager.stat_value("atk")
	var crt := GameManager.stat_value("crt")
	var crd := GameManager.stat_value("crd")
	var fusion_bonus := GameManager.fusion_attack_bonus()
	# 连击数伤害加成（每击 +2%，上限 +30%）
	var combo_bonus: float = minf(
		_hit_combo_count * GameBalance.COMBO_DAMAGE_PER_HIT,
		GameBalance.COMBO_DAMAGE_CAP
	)
	var target_def: float = enemy.get("defense") if enemy.get("defense") != null else 0.0
	# 目标身上的词条影响：易伤（毒蚀等）与减伤（护盾/防御型）
	var vuln := 0.0
	var taken_down := 0.0
	var tgt_buffs = enemy.get("buffs")
	if tgt_buffs != null and tgt_buffs is BuffHolder:
		vuln = (tgt_buffs as BuffHolder).total_vulnerability()
		taken_down = (tgt_buffs as BuffHolder).total_damage_reduction()
	var result := DamagePipeline.elemental_attack(
		atk, multiplier, fusion_bonus + combo_bonus, target_def, attack_element,
		0.0, vuln, taken_down)
	# 元素亲和：元素伤害 +15%（分册 4.x 词条）
	if attack_element >= 0:
		result.damage = result.damage * (1.0 + _element_affinity_bonus())
	# 法术部分不可暴击（分册 2.3）——火/冰/雷/毒为纯法术，永不暴击；
	# 土/风的物理半可暴击，此处按「是否法术为主」简化：纯法术元素跳过暴击
	var can_crit := attack_element < 0 or ElementDefs.can_crit(attack_element)
	# 调试强制暴击**故意绕过 can_crit**：否则法术系元素永远看不到暴击顿帧，
	# 而观察暴击命中判定正是调试想要的。
	var crit := _force_crit or (can_crit and GameManager.rng.randf() < crt)
	var total := DamagePipeline.with_crit(result.damage, crit, crd)
	# 调试伤害倍率加在**出手侧**（面板上的"伤害倍率"惯例指"我打出去的伤害"）
	total *= _damage_multiplier

	# 击退向量（EnemyBase 硬直期间消费）
	var push: Vector3 = Vector3.ZERO
	if knockback > 0.0:
		push = (enemy.global_position - global_position)
		push.y = 0.0
		if push.length_squared() > 0.001:
			push = push.normalized() * knockback
		else:
			push = _facing * knockback
	enemy.call("take_damage", total, crit, push)
	# 元素攻击：给目标叠层，并把阈值事件转成控制词条（冰冻/麻痹）
	_apply_element_to(enemy)
	EventBus.damage_popup.emit(enemy.global_position, total, "crit" if crit else "normal")
	# 暴击/终结技 hitstop 顿帧。
	# 阈值必须是「罕见时刻」而非常规段位——旧值 1.5 把普攻4（1.8）、
	# 冲撞（1.5）、跳跃斩（1.7）全纳入，而这些是连段家常便饭，等于
	# 每击 0.06s 的 20 倍慢动作，连段手感变成「打一下卡一下」。
	# 收紧为暴击或终结技（第 4 段）才顿帧 + 震屏。
	if crit or _current_combo_stage == combo_stages_size():
		_hitstop(0.06)
		_screen_shake(0.1)


## 把本次攻击的元素叠到目标身上，并处理阈值触发（冰冻/雷暴）
## 攻击元素来源：已装备武器的 element 字段；未赋予则为纯物理，不叠层。
func _apply_element_to(enemy: Node3D) -> void:
	if attack_element < 0:
		return
	var tgt = enemy.get("buffs")
	if tgt == null:
		return
	var out: Dictionary = ElementDamage.attack(tgt, attack_element)
	for ev in out.get("events", []):
		var ctrl_id: String = ElementDamage.control_for_event(str(ev))
		if ctrl_id != "":
			tgt.apply(ctrl_id, "element")
			EventBus.message.emit("触发%s" % ElementDamage.event_name(str(ev)))


## 元素亲和：已装备物品提供的「所有元素伤害 +X%」总和（分册 4.x 词条）
## 词条挂在 EquipmentTemplate.element_affinity（0.15 = +15%），只取已装备的。
func _element_affinity_bonus() -> float:
	var total := 0.0
	if GameManager.equipment_manager == null:
		return total
	for inst in GameManager.equipment_manager.get_equipped().values():
		if inst == null:
			continue
		var tpl = inst.get_template()
		if tpl != null:
			total += float(tpl.element_affinity)
	return total


## 刷新攻击元素：取已装备武器里第一件带元素的。
## 武器才赋予攻击元素——护甲/饰品的元素只作为词条加成（元素亲和）。
func _refresh_attack_element() -> void:
	attack_element = -1
	# equipment_manager 在 start_new_run 里才创建；Player._ready 可能早于它
	# （直跑场景、测试实例化）——必须判空，否则这里会抛 Nil 错误
	if GameManager.equipment_manager == null:
		return
	var equipped: Dictionary = GameManager.equipment_manager.get_equipped()
	for slot in [EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Slot.WEAPON_2]:
		var inst = equipped.get(slot)
		if inst == null:
			continue
		var tpl = inst.get_template()
		if tpl != null and not str(tpl.element).is_empty():
			attack_element = ElementDamage.elem_from_key(str(tpl.element))
			if attack_element != -1:
				return


## 攻击收尾反馈。
## 普通命中**不震屏**：相机是正上方俯视 + rig.position 跟随 lerp，
## 水平向的震屏偏移会被俯视投影放大成整个画面大幅斜向抖动，且与
## 跟随逻辑每帧对抗（0.2s 内震荡）——体感是「屏幕被刷新一下」的假卡顿。
## 震屏保留给重时刻：落地斩已有 0.3；暴击/终结技在 _apply_hit 里震。
func _finish_attack_feedback(hit_any: bool) -> void:
	if hit_any:
		EventBus.player_attacked.emit(_facing, "")
		AudioManager.play("hit")


## Hitstop：短暂全局减速制造顿帧感
## 关键：必须保证 time_scale 一定被还原。原先用 await 等待定时器，
## 若玩家在顿帧期间死亡/场景切换（节点被 free），await 永不恢复 →
## time_scale 永久卡在 0.05，整个游戏变成慢动作（表现为"严重延迟/死机"）。
## 故改为：回调式还原 + 退出场景树时兜底还原。
##
## 与调试时间缩放共存：Engine.time_scale 有两个参与者——本处持有**瞬时值**，
## DebugManager 持有**倍率**。故这里用**保存/还原**而不是重算
## `HITSTOP * 倍率`：重算在「顿帧期间改倍率」或中途 _exit_tree 时会还原成过期值。
func _hitstop(duration: float) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	_pre_hitstop_scale = Engine.time_scale          # 保存，绝不重算
	Engine.time_scale = HITSTOP_TIME_SCALE * _debug_scale()
	var t := get_tree().create_timer(duration, true, false, true)
	t.timeout.connect(_end_hitstop)


## 还原全局时间缩放（幂等）。下限 0.001——Engine.time_scale = 0 会让引擎冻死且脚本无法恢复。
func _end_hitstop() -> void:
	if not _hitstop_active:
		return
	_hitstop_active = false
	Engine.time_scale = maxf(_pre_hitstop_scale, 0.001)


## 读取调试倍率（无 DebugManager 时按 1.0，测试场景友好）
func _debug_scale() -> float:
	var dm := get_node_or_null("/root/DebugManager")
	if dm != null and dm.has_method("get_debug_scale"):
		return float(dm.call("get_debug_scale"))
	return 1.0


# ============================================================
# 调试接口（实机测试模式；供 DebugManager 与测试调用）
# ============================================================

func set_god_mode(on: bool) -> void:
	_god_mode = on


func is_god_mode() -> bool:
	return _god_mode


func set_damage_multiplier(m: float) -> void:
	_damage_multiplier = maxf(m, 0.0)


func get_damage_multiplier() -> float:
	return _damage_multiplier


func set_force_crit(on: bool) -> void:
	_force_crit = on


## 重置全部战斗冷却（调试用，立刻可再出手）
func reset_cooldowns() -> void:
	_attack_timer = 0.0
	_current_attack_cooldown = 0.0
	_dodge_cooldown_timer = 0.0
	_sprint_attack_timer = 0.0
	_finisher_armor_timer = 0.0
	if _combo != null:
		_combo.reset()


## 离开场景树时兜底还原，避免顿帧中途换场景导致时间缩放泄漏
func _exit_tree() -> void:
	_end_hitstop()

var _hitstop_active := false
var _pre_hitstop_scale := 1.0    ## hitstop 前的时间缩放（保存/还原，见 _hitstop）

# —— 调试（实机测试模式；由 DebugManager 写入）——
var _god_mode := false           ## 无敌：跳过扣血，但保留受击反馈
var _damage_multiplier := 1.0    ## 出手伤害倍率
var _force_crit := false         ## 强制暴击（故意绕过 can_crit，便于观察法术暴击顿帧）


## 屏幕震动：给 rig 下的 Camera3D 一个短促位置脉冲，指数衰减回零。
## **偏移加在相机节点上而非 rig**：rig 的 position 由 CameraRig._process
## 每帧 lerp 向玩家——直接改 rig.position 会被跟随逻辑对抗（先被拉走一半、
## tween 又往回补，0.2s 内来回震荡，俯视投影下是大幅斜向抖动）。
## 相机是 rig 的子节点，改它的局部位置不影响跟随。
func _screen_shake(strength: float) -> void:
	var rig := get_node_or_null("../CameraRig")
	if rig == null:
		return
	var cam := rig.get_node_or_null("Camera3D") as Node3D
	if cam == null:
		return
	var offset := Vector3(
		rng_shake.randf_range(-strength, strength),
		0.0,
		rng_shake.randf_range(-strength, strength)
	)
	cam.position += offset
	var tween := create_tween()
	tween.tween_property(cam, "position", Vector3.ZERO, 0.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

var rng_shake := RandomNumberGenerator.new()


## 挥砍视觉：面前渐隐扇形 mesh（普攻/奔跑/跳跃攻击调用）
## 挥砍视觉：面前渐隐发光扇形。
##
## 性能设计（原先每次攻击都新建 ImmediateMesh + StandardMaterial3D）：
## 真实 GPU 上「新的 StandardMaterial3D」首次使用会同步编译着色器变体，
## 而本函数每次攻击都建新材质 → 攻击瞬间掉帧。故做三层复用：
##   1. 材质按颜色缓存（全场共用 5 种，不再新建）
##   2. 网格按 (reach, half_angle) 缓存（形状只由这两者决定）
##   3. 节点用池复用（避免每次 add_child/queue_free）
## 渐隐改为 tween 调制节点的 modulate.a，不再改材质 albedo——
## 否则调完 alpha 材质就废了，无法给下一个复用的节点用。
static var _slash_mat_cache := {}
static var _slash_mesh_cache := {}
var _slash_pool: Array[MeshInstance3D] = []
var _slash_free: Array[MeshInstance3D] = []


func _spawn_slash_visual(reach: float, half_angle: float, color: Color = Color(1, 1, 0.85, 0.5)) -> void:
	var node := _acquire_slash_node()
	node.mesh = _get_slash_mesh(reach, half_angle)
	# 每种颜色一个独立缓存的材质实例（渐隐会改它的 alpha，故不能与其他颜色共用）
	var mat := _get_slash_material(color)
	mat.albedo_color = color          # 复用前复位 alpha（上次渐隐可能改成了 0）
	node.material_override = mat
	node.visible = true

	var rot_y := atan2(_facing.x, _facing.z)
	node.position = global_position + Vector3(0, 1.0, 0)
	node.rotation.y = rot_y

	# 渐隐：调该颜色专属材质的 alpha，结束后归还池
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tween.tween_callback(func(): _release_slash_node(node))


## 取一个挥砍节点（池空则新建）
func _acquire_slash_node() -> MeshInstance3D:
	var node: MeshInstance3D
	if _slash_free.is_empty():
		node = MeshInstance3D.new()
		node.name = "SlashVisual"
		_slash_pool.append(node)
		get_parent().add_child(node)
	else:
		node = _slash_free.pop_back()
		node.visible = true
	return node


## 归还挥砍节点（隐藏而非销毁，供下次复用）
func _release_slash_node(node: MeshInstance3D) -> void:
	if not is_instance_valid(node):
		return
	node.visible = false
	if not _slash_free.has(node):
		_slash_free.append(node)


## 材质按颜色缓存（r/g/b 作键；alpha 由节点 modulate 控制，故键里不含 a）
static func _get_slash_material(color: Color) -> StandardMaterial3D:
	var key := "%.3f_%.3f_%.3f" % [color.r, color.g, color.b]
	if _slash_mat_cache.has(key):
		return _slash_mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_slash_mat_cache[key] = mat
	return mat


## 扇形网格按 (reach, half_angle) 缓存（形状只由这两个参数决定）
static func _get_slash_mesh(reach: float, half_angle: float) -> ArrayMesh:
	var key := "%.2f_%.3f" % [reach, half_angle]
	if _slash_mesh_cache.has(key):
		return _slash_mesh_cache[key]

	var steps := 12
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(steps):
		var a0 := -half_angle + (2.0 * half_angle * i / steps)
		var a1 := -half_angle + (2.0 * half_angle * (i + 1) / steps)
		var base := verts.size()
		verts.push_back(Vector3.ZERO)
		verts.push_back(Vector3(sin(a1) * reach, 0.0, cos(a1) * reach))
		verts.push_back(Vector3(sin(a0) * reach, 0.0, cos(a0) * reach))
		indices.push_back(base + 0)
		indices.push_back(base + 1)
		indices.push_back(base + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_slash_mesh_cache[key] = mesh
	return mesh


## 敌人有效性检查
func _is_valid_enemy(enemy: Node) -> bool:
	return is_instance_valid(enemy) and enemy is Node3D and enemy.has_method("take_damage")


## 连击计数（命中即计，2 秒无命中清零）
func _register_hit_combo() -> void:
	_hit_combo_count += 1
	_hit_combo_time = 2.0


## 当前连击数（HUD 用）
func get_hit_combo() -> int:
	return _hit_combo_count


func cast_skill(skill_id: String) -> Dictionary:
	var skill_data := GameBalance.skill_by_id(skill_id)
	if skill_data.is_empty():
		return {"ok": false, "reason": "未知技能"}

	var direction := InputManager.get_attack_direction_3d()
	if direction == Vector3.ZERO:
		direction = _facing

	EventBus.player_skill_cast.emit(skill_id, direction)
	return {"ok": true, "skill": skill_id, "direction": direction}


## 受击闪红：前 40% 全红，剩余时间线性退回本色（与敌人同款节奏）
func _update_flash() -> void:
	if _model == null or _model.material_override == null:
		return
	var mat := _model.material_override as StandardMaterial3D
	if mat == null:
		return
	if _flash_timer <= 0.0:
		mat.albedo_color = _base_color
		return
	var t := _flash_timer / HIT_FLASH_DURATION
	var blend := clampf(t / 0.4, 0.0, 1.0)
	mat.albedo_color = Color(1.0, 0.15, 0.15).lerp(_base_color, 1.0 - blend)


func take_damage(amount: float) -> void:
	# 翻滚/俯冲无敌帧
	if _is_dodging or _jump_phase == JumpPhase.DIVE:
		return
	# 终结技霸体：减伤 30%，不掉连段节奏（无硬直状态，攻击照常续接）
	var armor := _finisher_armor_timer > 0.0
	if armor:
		amount *= 0.7
	# 调试无敌：在无敌帧/霸体之后、真正扣血之前拦下。
	# 刻意保留下面的受击闪红与 player_hit 信号——「看得到打中」才是有意义的无敌，
	# 否则没法用它观察命中判定。
	if _god_mode:
		EventBus.player_hit.emit(0.0, global_position)
		_flash_timer = HIT_FLASH_DURATION
		_update_flash()
		return
	GameManager.attributes.take_damage(amount)
	EventBus.player_hit.emit(amount, global_position)
	EventBus.damage_popup.emit(global_position, amount, "player" if not armor else "armor")
	AudioManager.play("hit")
	# 受击闪红：玩家此前没有任何受击视觉，扣血了却看不出来
	_flash_timer = HIT_FLASH_DURATION
	_update_flash()
	# HUD 血量刷新：玩家受伤不发 stats_changed，HUD 数值不会变
	EventBus.stats_changed.emit()

	if GameManager.attributes.is_dead():
		die()


## 受击击退（石翼蝙蝠等怪物机制调用）
## 与敌人一样在短时间内把外力加进 velocity，由移动逻辑自然衰减。
func apply_knockback(force: Vector3) -> void:
	if _is_dodging:
		return
	velocity.x += force.x
	velocity.z += force.z


func die() -> void:
	if not is_inside_tree():
		return
	AudioManager.play("death")
	# 切到死亡状态：即便物理帧因故仍在跑，也不再有每帧行为
	if _state_machine:
		_state_machine.transition_to("DeadState")
	# finish_run 内部已发 run_finished（结算面板监听显示）
	GameManager.finish_run("defeated")
	set_physics_process(false)
	hide()


## 自动拾取：开启后走到掉落物上即自动捡起，无需按 E
## 由 _physics_process 每帧调用；关闭时立即返回（开销可忽略）
const AUTO_PICKUP_INTERVAL := 0.25   # 检测间隔（秒），避免每帧遍历
var _auto_pickup_timer := 0.0


func _update_auto_pickup(delta: float) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null or not bool(sm.get_setting("auto_pickup")):
		return
	_auto_pickup_timer -= delta
	if _auto_pickup_timer > 0.0:
		return
	_auto_pickup_timer = AUTO_PICKUP_INTERVAL
	var nearest := _nearest_pickup()
	if nearest == null:
		return
	if nearest.has_method("pick_up"):
		nearest.call("pick_up")   # 失败（背包满等）静默，等玩家腾出位置再来


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		EventBus.message.emit("背包")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		# 交互优先级：破墙（隐藏房）→ 特殊房 → 拾取
		if not _interact_hidden_wall() and not _interact_special_room():
			_pickup_nearby()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("devour"):
		_devour_nearby()
		get_viewport().set_input_as_handled()


## 切换拾取方式（按 E 手动 ↔ 自动拾取）。
## 仅由设置面板调用——不再绑定按键，避免与游戏内操作抢键。
func _toggle_auto_pickup() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		return
	var now: bool = not bool(sm.get_setting("auto_pickup"))
	sm.set_setting("auto_pickup", now)
	EventBus.message.emit("自动拾取：%s" % ("开" if now else "关"))

## 破墙进入隐藏房（策划 3.2：靠近出现裂缝 → 破开）。
## 返回 true 表示本次交互已被处理（破墙成功），调用方不再尝试其它交互。
func _interact_hidden_wall() -> bool:
	var walls := get_tree().get_nodes_in_group("hidden_walls")
	for w in walls:
		if not is_instance_valid(w):
			continue
		if w.has_method("can_interact_with") and bool(w.call("can_interact_with", self)):
			var ok: bool = bool(w.call("break_wall", self))
			if ok:
				AudioManager.play("hit")
				EventBus.message.emit("你破开了墙壁")
				return true
	return false


## 交互当前房间的商店、泉水或事件服务。
## 返回 false 表示"本房不是特殊房"，让位给 _pickup_nearby()——
## 注意每个房间都有控制器（activate 对所有房型都加组），
## 若无条件返回 true，拾取逻辑将永不执行。
func _interact_special_room() -> bool:
	var controller := get_tree().get_first_node_in_group("current_room_controller")
	if controller == null or not controller.has_method("is_special_room"):
		return false
	if not bool(controller.call("is_special_room")):
		return false

	# 打开交互面板；面板缺失时回退到旧的"按 E 直接结算"
	var ui := get_tree().get_first_node_in_group("special_room_ui")
	if ui != null and ui.has_method("open"):
		var ctx: Dictionary = controller.call("get_special_context")
		if ctx.get("ok", false):
			ui.call("open", ctx, controller)
			return true
		EventBus.message.emit(ctx.get("reason", "无法交互"))
		return true

	var result: Dictionary = controller.interact_special()
	if result.get("ok", false):
		EventBus.message.emit("特殊房交互完成")
	else:
		EventBus.message.emit(result.get("reason", "无法交互"))
	return true


## 查找最近的掉落物（拾取/吞噬共用）
## 有距离上限：超过则视为够不着（原先返回全场景最近的，隔着半张地图也能捡）
func _nearest_pickup() -> Node3D:
	var nearest: Node3D = null
	var nearest_d := PICKUP_RANGE
	for node in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(node):
			continue
		var d := (node as Node3D).global_position.distance_to(global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = node
	return nearest


## 拾取最近掉落物进背包
func _pickup_nearby() -> void:
	var nearest := _nearest_pickup()
	if nearest == null:
		EventBus.message.emit("附近没有可拾取的掉落物")
		return

	if nearest.has_method("pick_up"):
		var result: Dictionary = nearest.call("pick_up")
		if not result.get("ok", false):
			EventBus.message.emit(result.get("reason", "拾取失败"))


## 吞噬最近掉落物（本局永久成长）
func _devour_nearby() -> void:
	var nearest := _nearest_pickup()
	if nearest == null:
		EventBus.message.emit("附近没有可吞噬的掉落物")
		return

	if nearest.has_method("devour"):
		var result: Dictionary = nearest.call("devour")
		if result.get("ok", false):
			EventBus.message.emit("吞噬成功！")
			AudioManager.play("pickup")
		else:
			EventBus.message.emit(result.get("reason", "吞噬失败"))
