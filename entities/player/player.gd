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

# 视觉反馈（受击闪红 / 挥砍扇形特效）已拆到 FxComponent，见 entities/player/fx_component.gd

const ATTACK_REACH := 2.0

## 顿帧时的时间缩放（配合 _hitstop，必须保证还原）
const HITSTOP_TIME_SCALE := 0.05

## 拾取/交互组件（E 键交互、自动拾取、就近查找）。
## 在 `_ready()` 里经 `_setup_pickup()` 装配。
## 作用距离常量住在组件里（`PickupComponent.PICKUP_RANGE`）。
var pickup: PickupComponent = null

## 视觉反馈组件（受击闪红 / 挥砍扇形特效）。
## 在 `_ready()` 里经 `_setup_fx()` 装配；它同时接管模型材质。
var fx: PlayerFx = null

## 屏幕震动组件。在 `_ready()` 里经 `_setup_fx()` 装配。
var cam_fx: PlayerCameraFx = null

## 职业/形态/技能组件。在 `_ready()` 里经 `_setup_skills()` 装配。
var skills: PlayerSkills = null

## 装备触发条件结算器（击杀/受击/命中/闪避时生效的自有词条）。
var equip_fx: PlayerEquipmentEffects = null

## 召唤物管理器。在 `_ready()` 里经 `_setup_summons()` 装配。
var summons: SummonManager = null

# —— 隐身状态（装备参考2：暗影步/烟雾弹/暗影刺杀）——
## 隐身剩余时长（秒）。>0 时模型半透明、敌人不再以你为目标。
var _stealth_timer := 0.0
## 隐身期间移速加成
var _stealth_speed_pct := 0.0
## 隐身期间是否免疫伤害
var _stealth_invuln := false
## 破隐一击的伤害加成（下次攻击消费一次）
var _stealth_next_hit_bonus := 0.0


func _ready() -> void:
	add_to_group("player")
	_combo = AttackCombo.new()
	# 词条/元素容器：敌人的元素攻击会往这里叠层，控制/易伤也从这里读
	if buffs == null:
		buffs = BuffHolder.new(self)
	# 技能组件必须在 _setup_class 之前装配——后者要经它转发
	_setup_skills()
	_setup_equip_fx()
	_setup_class()
	_setup_state_machine()
	_setup_fx()
	# 召唤物管理器（装备技能「召唤狼灵/护卫」用）
	_setup_summons()
	# 拾取/交互组件（E 键交互、自动拾取、就近查找）
	_setup_pickup()
	# 击杀回血（监听全局敌死信号）
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("enemy_died"):
		bus.enemy_died.connect(_on_enemy_killed)
	# 装备变更 → 重算攻击元素（武器决定元素，护甲/饰品只给元素亲和）
	if bus and bus.has_signal("equipment_changed"):
		bus.equipment_changed.connect(func(_s, _i): _refresh_attack_element())
	_refresh_attack_element()
	# 开局重配：**必须在 start_new_run 之后**才能拿到玩家选的职业/形态。
	#
	# 时序陷阱：main.tscn 实例化时玩家节点的 _ready 先跑，此时
	# GameManager.run_info 还是上一局/默认值；`start_new_run()` 是随后
	# 由主菜单调用的。只靠 _ready 里的 _setup_class() 会导致
	# **玩家选的职业/形态从未生效过**（选法师开局仍是战士的数值）。
	# 故订阅 game_started，在真正的开局信息写进去之后再配一次。
	if bus and bus.has_signal("game_started"):
		bus.game_started.connect(_on_game_started)
	# 治疗监听：光层靠"治疗/护盾积累"（策划 8.5）。
	# 治疗入口散落在泉水/药水/击杀回血/吸血等多处，故收口在
	# AttributeSystem.heal_listeners 一处，避免逐个挂漏掉。
	_bind_heal_listener()


## 把光层监听挂到当前 AttributeSystem。
## 每次开局 AttributeSystem 会被重建（GameManager._reset_run），
## 故 _on_game_started 里也要重新挂——否则第二局起光层不再积累。
func _bind_heal_listener() -> void:
	var attrs = GameManager.attributes
	if attrs == null or not ("heal_listeners" in attrs):
		return
	var cb := Callable(self, "_on_healed")
	if not attrs.heal_listeners.has(cb):
		attrs.heal_listeners.append(cb)


## 新一局开始：按 run_info 重新装配职业/形态/资源。
func _on_game_started() -> void:
	class_resource = null   # 换职业要换资源容器，不能沿用上一个职业的
	_setup_class()
	_refresh_attack_element()
	# AttributeSystem 每次开局都会被重建，监听要重新挂
	_bind_heal_listener()
	EventBus.stats_changed.emit()


# ============================================================
# 职业 / 形态 / 技能（策划《角色设计分册》）
# ============================================================

## 职业资源容器（怒气/魔力/专注/裁决/气劲）。
## **留在 Player 上**：45 处战斗逻辑直接读它，且它是实体身份的一部分。
var class_resource: ClassResource = null
## 当前职业 id（来自 GameManager.run_info["character"]）
var class_id := ""
## 当前形态槽位（0 初始 / 1~3 进阶 / 4 终极）
var form_slot := 0
## 护盾：在 hp 之前被消耗的临时生命（形态「溢出转护盾」等机制的载体）
var temp_shield := 0.0
## DOT 小数累积器：DOT 单帧只有零点几点，攒够 1 点才结算一次
##（见 _physics_process 里的说明——每帧结算会冒出 "0" 伤害数字）
var _dot_accum := 0.0
## 反击待发次数（策划 7.2 铁身「受伤自动反击」）：
## 每次受伤 +1，下次普攻消费 1 次并吃 counter_on_hit 倍率。
var _counter_charges := 0
## 普攻命中计数（策划 8.3 影子判官「每 4 次攻击触发影子攻击」）
var _attack_count := 0
## 脱战计时（策划 6.2 斥候「脱战 3 秒后移速 +30%」）：有输出/受击即清零
var _out_of_combat_time := 0.0
## 翻滚后免疫下一次攻击的待发标记（策划 6.2 斥候）
var _dodge_immune_ready := false
## 破极状态是否已触发（策划 7.4：每 25 连击触发一次，同一次连击段内不重复触发）
var _break_triggered := false
## 森之领域节点（策划 6.5；同一时刻只保留一个）
var _forest_domain: Node3D = null
## 光层 / 暗层计数（策划 8.5 光暗审裁）
var _light_layers := 0
var _dark_layers := 0




## 装配职业与初始形态（实现已拆到 PlayerSkills）。
func _setup_class() -> void:
	skills.setup_class()


## 装配技能组件。**必须在 _setup_class 之前**——后者的转发要经 skills。
func _setup_skills() -> void:
	skills = PlayerSkills.new()
	skills.name = "SkillsComponent"
	add_child(skills)
	skills.setup(self)


## 装配装备触发条件结算器（击杀/受击/命中/闪避时生效的自有词条）。
func _setup_equip_fx() -> void:
	equip_fx = PlayerEquipmentEffects.new()
	equip_fx.name = "EquipmentFxComponent"
	add_child(equip_fx)
	equip_fx.setup(self)


## 把当前形态的专属增益挂到属性系统上（转发到 PlayerSkills）。
## **保留公开名**：形态切换与开局装配都走它。
func _apply_form_modifiers() -> void:
	skills.apply_form_modifiers()


## 当前形态的技能范围乘区（转发；SkillSystem 经 has_method 调用它）
func skill_range_mult() -> float:
	return skills.skill_range_mult()


## 切换形态（转发）
func switch_form(slot: int) -> bool:
	return skills.switch_form(slot)


## 当前形态的技能列表（转发；HUD 技能条经 has_method 调用它）
func current_skills() -> Array:
	return skills.current_skills()


## 释放技能（转发；HUD / 测试 / 技能系统经 has_method 调用它）
func cast_skill(skill_id: String, direction: Vector3 = Vector3.ZERO) -> Dictionary:
	return skills.cast_skill(skill_id, direction)


## 按槽位放技能（转发）
func cast_skill_slot(slot: int) -> Dictionary:
	return skills.cast_skill_slot(slot)


## 技能剩余冷却（转发）
func skill_cooldown_left(skill_id: String) -> float:
	return skills.skill_cooldown_left(skill_id)


## 冲刺类技能的位移执行（转发；SkillSystem 经 has_method 回调它）
func apply_skill_dash(dir: Vector3, dist: float) -> void:
	skills.apply_skill_dash(dir, dist)


## 技能输入轮询（转发；打字时不调，见 _physics_process）
func _poll_skill_input() -> void:
	skills.poll_input()
## 装配受击闪红用的模型引用。
## 复制一份材质再挂到模型上——直接改 scene 里的共享材质会让
## 同场景的多个玩家实例（或复用的资源）互相影响。
## 装配模型与受击闪红用的材质。
##
## **模型从胶囊换成 billboard 四边形 + 职业贴图**：HD-2D 的做法是 2D 像素图
## 贴在朝相机的平面上（与敌人同一套方案，见 enemy_base._create_visual）。
## 这里在运行时重建 mesh 而不改 .tscn——逻辑集中在一处，且贴图格依赖
## class_id（_setup_class 已先跑，见 _ready 顺序）。
# ============================================================
# 属性接口（BuffHolder 消费）—— 转发到 GameManager.attributes
# ============================================================
## **为什么必须加这几个转发**：BuffHolder 通过 `_target.call("add_modifier", …)`
## 给宿主挂属性修正，通过 `_target.call("stat_value"/"eff_atk"/"eff_ap")` 读宿主
## 的攻击/法强来结算 DOT。但这两个方法只存在于 AttributeSystem，
## 而 BuffHolder 的 target 是 **Player 节点**——方法查找失败后
## `_sync_modifier` 静默早退，于是**所有 stat 型词条（攻击+25%、生命+12%…）
## 与元素/词条 DOT 从未生效过**（实测：挂 war_cry 后 ATK 35→35）。
##
## 这几个方法把调用转发到真正持有属性的 AttributeSystem。

func add_modifier(source: String, stat: int, flat: float = 0.0, percent: float = 0.0) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.attributes != null:
		gm.attributes.add_modifier(source, stat, flat, percent)


func remove_modifiers(source: String) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.attributes != null:
		gm.attributes.remove_modifiers(source)


## 按属性名读最终值（BuffHolder 的 DOT 结算用）
func stat_value(stat_name: String) -> float:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("stat_value"):
		return float(gm.call("stat_value", stat_name))
	return 0.0


## 有效攻击力（DOT 用 dot_atk 系数乘它）
func eff_atk() -> float:
	return stat_value("atk")


## 有效法术强度（DOT 用 dot_pct 系数乘它）
func eff_ap() -> float:
	return stat_value("ap")


## 装配视觉反馈组件（受击闪红 / 挥砍扇形特效 / 屏幕震动）。
## FxComponent 的 setup 会接管模型材质——闪红可控的前提。
func _setup_fx() -> void:
	fx = PlayerFx.new()
	fx.name = "FxComponent"
	add_child(fx)
	fx.setup(self)
	cam_fx = PlayerCameraFx.new()
	cam_fx.name = "CameraFxComponent"
	add_child(cam_fx)
	cam_fx.setup(self)


## 装配拾取/交互组件（E 键交互、自动拾取、就近查找）。
## **必须在 add_child 之后 setup**：组件要在场景树里才能 get_tree()。
func _setup_pickup() -> void:
	pickup = PickupComponent.new()
	pickup.name = "PickupComponent"
	add_child(pickup)
	pickup.setup(self)


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
	# 职业资源：击杀积攒（策划 6.1 判官「击杀 +20」）。
	# 与命中积攒同属"打怪回资源"链路，此前同样从未被调用。
	skills.on_kill()
	# 装备触发条件（装备参考2：「每击杀一个敌人…」类自有词条）
	if equip_fx != null:
		equip_fx.on_kill()
	# 装备词条·击杀刷新冷却（`cd_refresh_pct` 通道）。
	#
	# 规格里有多件装备带「击杀目标后刷新所有技能冷却」/「闪避时 N% 概率
	# 立即刷新冲刺冷却」。这个通道此前**零消费者**——装备加了也没效果。
	# 按概率判定：概率 = 通道值（多件叠加由 special_modifiers 累加）。
	var cd_pct: float = float(_equip_special_mods().get("cd_refresh_pct", 0.0))
	if cd_pct > 0.0 and GameManager.rng.randf() < cd_pct:
		reset_cooldowns()
		if skills != null:
			skills.reset_skill_cooldowns()
		EventBus.message.emit("击杀刷新冷却！")
	if GameBalance.KILL_HEAL <= 0.0:
		return
	if GameManager.attributes and not GameManager.attributes.is_dead():
		var healed: float = GameManager.attributes.heal(GameBalance.KILL_HEAL)
		# 绿色回血飘字
		var bus := get_node_or_null("/root/EventBus")
		if bus and healed > 0.0:
			bus.damage_popup.emit(global_position, healed, "heal")




## 控制台是否正在接收文本（打字时不该触发放技能）
func _typing_input() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var m := tree.root.get_node_or_null("DebugManager")
	if m != null and m.has_method("is_text_input_active"):
		return bool(m.call("is_text_input_active"))
	return false


func _physics_process(delta: float) -> void:
	# 定时器无条件递减（在任何状态里都要走，移入状态会改变语义）
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)
	_sprint_attack_timer = maxf(_sprint_attack_timer - delta, 0.0)
	_finisher_armor_timer = maxf(_finisher_armor_timer - delta, 0.0)
	# 受击闪红衰减（视觉反馈已拆到 FxComponent）
	fx.tick(delta)
	# 隐身计时（装备参考2：暗影步/烟雾弹）
	_tick_stealth(delta)
	# 自动拾取（设置开启时生效）与 E 键交互已拆到 PickupComponent
	pickup.update(delta)

	# 职业资源与技能（策划《角色设计分册》）
	# 资源自然回复（法师回蓝）+ 技能冷却推进，都在这里无条件走
	skills.tick(delta)
	# 技能输入：控制台打字时不响应（与其它输入一致）
	if not _typing_input():
		_poll_skill_input()

	# 连击窗口推进 + 连击数计时
	if _combo:
		_combo.tick(delta)
	if _hit_combo_time > 0.0:
		_hit_combo_time = maxf(_hit_combo_time - delta, 0.0)
		if _hit_combo_time == 0.0:
			# 形态·断连保留（策划 7.1 拳师「连击中断后保留 50% 连击数」）。
			# 只对声明了该机制的形态生效：其余形态断连归零，
			# 否则"连击断了"这件事对所有职业都失去惩罚。
			if ClassDefs.special_flag(class_id, form_slot, "slow_combo_decay"):
				_hit_combo_count = int(_hit_combo_count * 0.5)
			else:
				_hit_combo_count = 0
			_break_triggered = false   # 断连后允许下次连击段再触发破极

	# 脱战计时（策划 6.2 斥候）：有输出/受击时被 _on_basic_attack_landed
	# 与 _on_player_hurt 清零，此处只负责推进
	_out_of_combat_time += delta

	# 词条/元素推进：DOT 结算 + 元素衰减 + 控制判定
	if buffs != null:
		var tick_out: Dictionary = buffs.tick(delta)
		var dot: float = float(tick_out.get("dot", 0.0))
		# **DOT 按「跳」结算，不是每帧结算**。
		#
		# DOT 公式是 `法强 × 系数 × 层数 × delta`，单帧只有 ~0.017 点
		#（60fps 下）。原先每帧直接 take_damage(0.017)，而伤害飘字格式化成
		# `"%.0f"` —— 于是每帧在玩家身上冒一个 **"0"**，既刷屏又看不出在掉血
		#（实机症状：「不停冒出 0 点伤害数字」）。
		# 改为累积到 1 点再结算：飘字变成有意义的整数，且每帧的受击开销消失。
		if dot > 0.0:
			_dot_accum += dot
			if _dot_accum >= 1.0:
				var whole := floorf(_dot_accum)
				_dot_accum -= whole
				take_damage(whole)
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
	# **远近切换**：主手武器带「远程」标签时，普攻改为发射投射物。
	# 段位参数取自 RANGED_COMBO_STAGES（第 3/4 列语义与近战不同，见该表注释）。
	var ranged := _main_weapon_is_ranged()
	var params: Array = (_combo_ranged_get().stage_params(stage) if ranged
		else _combo.stage_params(stage))
	_combo.begin_attack()
	var aspd := GameManager.stat_value("aspd")
	_attack_timer = params[0] / maxf(aspd, 0.1)
	_current_attack_cooldown = _attack_timer
	_current_combo_stage = stage
	# 终结技（第 4 段）霸体
	if stage == combo_stages_size() and GameBalance.FINISHER_SUPERARMOR:
		_finisher_armor_timer = _attack_timer
		_spawn_armor_visual()
	if ranged:
		_perform_ranged_attack(params[1], params[2], int(params[3]), params[4])
	else:
		# 普攻射程 = 连段表的基础射程 + 形态加成（策划 7.1 拳师「空手射程 +0.5 米」）
		var reach: float = float(params[2]) + _fist_reach_bonus()
		_perform_melee_attack(params[1], reach, deg_to_rad(params[3]), params[4])
		# 挥砍视觉：终结技（第 4 段）金色大扇形，其余白
		if stage == combo_stages_size():
			fx.spawn_slash(reach, deg_to_rad(params[3]), Color(1.0, 0.8, 0.2, 0.55))
		else:
			fx.spawn_slash(reach, deg_to_rad(params[3]))
	_combo.end_attack()


## 主手武器是否带「远程」标签（决定普攻走投射物还是扇形）
##
## 标签由 `EquipmentDefs.weapon_tags_of` 从「武器类型 + 中文标签」推出，
## 弓/弩/带「远程」标签的法杖都会返回 `ranged`。
## **近战武器槽为空时返回 false**——空手（武僧 `no_weapon` 形态）走近战。
func _main_weapon_is_ranged() -> bool:
	var em = GameManager.equipment_manager
	if em == null:
		return false
	var inst = em.get_equipped().get(EquipmentDefs.Slot.WEAPON_1, null)
	if inst == null:
		return false
	var tpl = inst.get_template()
	if tpl == null:
		return false
	return "ranged" in EquipmentDefs.weapon_tags_of(tpl.weapon_type, tpl.tags)


## 远程连段器（懒建，与近战 `_combo` 分开）
##
## **必须分开**：近战连段的 `_stage` / 窗口状态若被远程共用，
## 玩家换武器后连段进度会串（近战打到第 3 段，换弓后直接从远程第 3 段开始）。
## 两张表段数相同，但语义与冷却都不同，各自维护最清晰。
var _combo_ranged: AttackCombo = null

func _combo_ranged_get() -> AttackCombo:
	if _combo_ranged == null:
		_combo_ranged = AttackCombo.new(GameBalance.RANGED_COMBO_STAGES)
	return _combo_ranged


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
		_armor_mat = MaterialLibrary.create_translucent_material(Color(1.0, 0.8, 0.3, 0.25), 1.2)
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
	fx.spawn_slash(params[2], deg_to_rad(55.0), Color(1.0, 0.45, 0.15, 0.5))
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
	fx.spawn_slash(params[4], PI, Color(0.4, 0.9, 1.0, 0.5))
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


## 远程普攻：沿面朝方向发射一枚投射物
##
## ## 结算走 `_apply_hit`，不走投射物的默认路径
##
## 投射物默认的 `_deal_damage` 只做「元素管线 + 裸 take_damage」，
## 而普攻有一整套效果（连击计数、生命偷取、装备触发词条、形态印记、
## 职业资源积攒、背刺判定、暴击顿帧）全在 `_apply_hit` 里。
## 故通过投射物的 `on_hit` 回调把结算**接回本类**——
## 远程与近战共用同一漏斗，手感与收益口径一致。
##
## `multiplier` 是段位伤害倍率，作为 `on_hit` 的闭包捕获传入。
func _perform_ranged_attack(multiplier: float, speed: float,
		pierce: int, knockback: float) -> void:
	var parent := _projectile_parent()
	if parent == null:
		return
	var dir := CombatGeometry.flat_normalized(_facing)
	if dir.length_squared() < 0.001:
		dir = Vector3.FORWARD
	var kb := knockback
	# 命中回调：接管结算。投射物只负责飞与判定，伤害口径交回 `_apply_hit`。
	var cb := func(target: Node3D, _dmg: float) -> void:
		if not is_instance_valid(target):
			return
		_apply_hit(target, multiplier, kb)
		_register_hit_combo()
		_finish_attack_feedback(true)
	ProjectileSystem.spawn({
		"direction": dir,
		"speed": speed,
		"damage": 0.0,      # 伤害由 on_hit 接管，不用投射物自带的数值
		"lifetime": GameBalance.RANGED_PROJECTILE_LIFETIME,
		"element": ElementDamage.key_from_elem(attack_element) if attack_element >= 0 else "",
		"pierce_count": pierce,
		"position": global_position + dir * 0.6,
		"on_hit": cb,
		# **强制节点路径**：模拟核不带目标引用、Callable 也跨不过 C++ 边界，
		# 走核会让 on_hit 永不触发 → 伤害为 0 且普攻效果全丢。见 Projectile.spawn。
		"force_node": true,
	}, parent)


## 玩家投射物的挂载父节点
##
## 与 `SkillSystem._projectile_parent` 同一策略：从自身向上找最近的 Node3D。
## 3D 世界在 SubViewport 下时，直接父节点可能是 `Viewport`（非 Node3D），
## 传给 `ProjectileSystem.spawn` 会抛类型错误并静默不出弹。
func _projectile_parent() -> Node3D:
	var n := get_parent()
	while n != null:
		if n is Node3D:
			return n as Node3D
		n = n.get_parent()
	return null


## 冲撞判定（奔跑攻击）：面向矩形区域
func _perform_charge_attack(multiplier: float, length: float, width: float, knockback: float) -> void:
	var hit_any := false
	# 形态·徒手射程（策划 7.1 拳师）对突进距离同样生效
	length += _fist_reach_bonus()
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
	# 形态·徒手射程（策划 7.1 拳师）对落地 AOE 半径同样生效
	radius += _fist_reach_bonus()
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
	# 群体单位（CrowdSim）不在场景树里，走查询而不是遍历组。
	# 扇形判据与上面完全一致，保证两条路径的命中范围相同。
	var mgr = _crowd_manager()
	if mgr != null and int(mgr.get("active")) > 0:
		var dir2 := Vector2(_facing.x, _facing.z)
		if dir2.length_squared() > 0.0001:
			dir2 = dir2.normalized()
			var ids = mgr.call("query_cone", global_position.x, global_position.z,
				dir2.x, dir2.y, half_angle, reach)
			for id in ids:
				_apply_hit_crowd(mgr, int(id), multiplier, knockback)
				hit_any = true
	return hit_any


## 攻击是否属于「背刺」：攻击者位于目标**背后**。
##
## 敌人没有 facing 字段，朝向由 `-global_transform.basis.z` 给出
##（enemy_base 在 CHASE 态 look_at 目标，故这个前向是可信的）。
## 判定用「目标→攻击者」与「目标前向」的点积：大于阈值说明攻击者在正面，
## 小于负阈值说明确实绕到了背后。
func _is_backstab(enemy: Node3D) -> bool:
	if ClassDefs.special_num(class_id, form_slot, "backstab_mult", 1.0) <= 1.0:
		return false
	if enemy == null or not is_instance_valid(enemy):
		return false
	# 几何判据走 CombatGeometry（纯函数，可单测）
	return CombatGeometry.is_behind(
		enemy.global_position, -enemy.global_transform.basis.z, global_position)




## 形态·远近切换无冷却（策划 6.1 追猎者「远近切换无冷却；切换后移速 +10%」）。
##
## 玩家没有真正的"切换武器"动作（攻击由连段表驱动），故这里把它落成
## **连续攻击之间不额外惩罚**：声明该机制时，攻击后的移速惩罚取消，
## 并在攻击间隔内给一点移速补偿，对应策划的"切换后移速 +10%"手感。
func weapon_swap_free() -> bool:
	return ClassDefs.special_flag(class_id, form_slot, "free_weapon_swap")


## 普攻射程的形态加成（策划 7.1 拳师「空手攻击射程 +0.5 米」）。
##
## 注意：基础射程来自**连段表**（AttackCombo.stage_params），
## 不是本文件的 ATTACK_REACH 常量——后者是历史遗留、无人读取。
## 形态加成是"在连段表之上再加一截"，故单独返回增量而不是绝对值。
func _fist_reach_bonus() -> float:
	return ClassDefs.special_num(class_id, form_slot, "fist_reach", 0.0)


## 当前形态的普攻护甲穿透。
## `armor_pierce`（形态主动机制）与 `fist_armor_pierce`（徒手特性）是两条
## 独立来源，可叠加，故一并返回。
func _basic_attack_pierce() -> float:
	var p := ClassDefs.special_num(class_id, form_slot, "armor_pierce", 0.0)
	p += ClassDefs.special_num(class_id, form_slot, "fist_armor_pierce", 0.0)
	return clampf(p, 0.0, 1.0)


## 受伤时的形态反应（在扣血前调用，amount 是护盾吸收后的实际伤害）。
func _on_player_hurt(amount: float) -> void:
	if amount <= 0.0:
		return
	# 装备触发条件（装备参考2：「每受到一次伤害，防御力增加1%…」类）
	if equip_fx != null:
		equip_fx.on_hurt()
	# 脱战计时被打断（策划 6.2：脱战 3 秒后才给移速加成）
	_out_of_combat_time = 0.0
	# 受伤反击（策划 7.2 铁身）：置位一次待发反击；
	# 连击≥10 时策划要求「反击翻倍」——这里再置一位，即两次 ×2.0
	if ClassDefs.has_special(class_id, form_slot, "counter_on_hit"):
		_counter_charges += 1
		if _hit_combo_count >= COUNTER_DOUBLE_COMBO:
			_counter_charges += 1
	# 暗层积累（策划 8.5：施加负面积累）——受伤本身就是"负面"的一种
	if ClassDefs.special_flag(class_id, form_slot, "light_dark_layers"):
		_gain_dark_layer()
	# 职业资源：战士怒气等（原本就在 take_damage 里调，这里保持同口径）
	skills.on_damage_taken(amount)


## 连击≥10 时铁身的反击翻倍（策划 7.2）
const COUNTER_DOUBLE_COMBO := 10
## 连击≥10 时铁身的减伤比例（策划 7.2）
const COUNTER_COMBO_DR := 0.25
## 翻滚开始（由 DodgeState.enter 调用）
func on_dodge_started() -> void:
	_out_of_combat_time = 0.0
	if ClassDefs.special_flag(class_id, form_slot, "dodge_immune_next"):
		_dodge_immune_ready = true
	# 装备词条·闪避刷新冲刺冷却（规格「闪避之靴：闪避时有5%概率立即刷新冲刺冷却」）。
	# 同一个 `cd_refresh_pct` 通道，两种触发源（击杀 / 闪避）——
	# 按规格文本归类时，凡「闪避时…刷新」的走这里，其余走击杀。
	var cd_pct: float = float(_equip_special_mods().get("cd_refresh_pct", 0.0))
	if cd_pct > 0.0 and GameManager.rng.randf() < cd_pct:
		_dodge_cooldown_timer = 0.0
		EventBus.message.emit("闪避刷新冲刺冷却！")
	# 装备触发条件（装备参考2：「闪避时…」类自有词条）
	if equip_fx != null:
		equip_fx.on_dodge()


## 6.2 斥候「脱战 3 秒后移速 +30%」：返回当前应额外乘的移速系数。
## 由 move_state 每帧读取——挂在属性系统上会需要额外的计时器管理，
## 而"脱战"是玩家侧的瞬时状态，就地算更直接。
func out_of_combat_speed_mult() -> float:
	# 隐身移速（装备参考2：暗影步「隐身期间移速 +30%」）优先于脱战加成——
	# 两者同时生效会让隐身期间移速叠到很高，且隐身是短时爆发、脱战是长时状态，
	# 取隐身那个更符合"隐身时跑得快"的设计意图。
	if _stealth_timer > 0.0 and _stealth_speed_pct > 0.0:
		return 1.0 + _stealth_speed_pct
	var bonus := ClassDefs.special_num(class_id, form_slot, "out_of_combat_spd", 0.0)
	if bonus <= 0.0 or _out_of_combat_time < OUT_OF_COMBAT_DELAY:
		return 1.0
	return 1.0 + bonus


## 脱战判定时长（策划 6.2：3 秒）
const OUT_OF_COMBAT_DELAY := 3.0


## 连击数是否无上限（策划 7.4 破极「连击无上限」）。
## 其余形态沿用 GameBalance 的连击加成上限，避免数值失控。
func combo_cap() -> float:
	if ClassDefs.special_flag(class_id, form_slot, "myriad_combo") \
			or ClassDefs.has_special(class_id, form_slot, "break_limit_at"):
		return INF
	return GameBalance.COMBO_DAMAGE_CAP


## 当前形态是否禁用武器（策划 7.1/7.2/7.3/7.5 武僧前四形态「不可装备武器」；
## 7.4 破极「可装备武器（突破限制）」用 can_equip_weapon 显式解锁）。
func weapon_forbidden() -> bool:
	if ClassDefs.special_flag(class_id, form_slot, "can_equip_weapon"):
		return false
	return ClassDefs.special_flag(class_id, form_slot, "no_weapon")


## 治疗/护盾时积累光层（策划 8.5 光暗审裁）。
## 订阅在 _ready 里挂到 AttributeSystem.heal_listeners——治疗入口有
## 泉水/药水/击杀回血/吸血等多处，收口在那里才能全覆盖。
func _on_healed(amount: float) -> void:
	if amount > 0.0:
		_gain_light_layer()


## 普攻命中后的形态附加效果（策划 6/7/8 章）。
## 集中在一处：这些都要"打中了才算"，放在 _apply_hit 的命中分支里。
func _on_basic_attack_landed(enemy: Node3D, damage: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_out_of_combat_time = 0.0   # 有输出即视为交战
	_attack_count += 1

	# 8.1 渡鸦「所有攻击额外附加（法强×0.2）法术伤害」
	var spell_pct := ClassDefs.special_num(class_id, form_slot, "spell_on_hit_ap_pct", 0.0)
	if spell_pct > 0.0:
		var ap := GameManager.stat_value("ap")
		if ap > 0.0:
			_deal_bonus_damage(enemy, ap * spell_pct, "spell")

	# 8.2 锁链判官「攻击挂审判印记（每层 +10% 法伤）」+「连锁传导 30%」
	if ClassDefs.special_flag(class_id, form_slot, "mark_per_hit"):
		_apply_buff_to(enemy, "judge_mark")
		var chain := ClassDefs.special_num(class_id, form_slot, "chain_30pct", 0.0)
		if chain > 0.0:
			_chain_spell_damage(enemy, damage * chain)

	# 8.3 影子判官「每 4 次攻击触发影子攻击（法强×0.5，无视护甲）」
	if ClassDefs.special_flag(class_id, form_slot, "shadow_every_4") \
			and _attack_count % SHADOW_ATTACK_EVERY == 0:
		var ap2 := GameManager.stat_value("ap")
		_deal_bonus_damage(enemy, ap2 * 0.5, "shadow", true)

	# 6.5 森之选召「命中生成森之领域」
	if ClassDefs.special_flag(class_id, form_slot, "forest_domain"):
		_spawn_forest_domain()

	# 8.5 光层：造成伤害本身不算光层（光层来自治疗/护盾），故这里只处理
	# 「施加负面 → 暗层」——锁链判官挂印记属于施加负面
	if ClassDefs.special_flag(class_id, form_slot, "light_dark_layers") \
			and ClassDefs.special_flag(class_id, form_slot, "mark_per_hit"):
		_gain_dark_layer()

	# 7.4 破极「每 25 连击触发破极状态 6 秒」
	_maybe_trigger_break_limit()

	# 场上物件的"被攻击改变状态"（策划 6.6：玩家攻击熔炉可提前引爆）。
	# 用 has_method 而非类型判断——玩家不该依赖 world/props 的具体类。
	if enemy.has_method("request_ignite"):
		enemy.call("request_ignite")


## 影子攻击的触发间隔（策划 8.3：每 4 次攻击）
const SHADOW_ATTACK_EVERY := 4


## 6.4 鹰眼：命中后沿攻击方向在目标**身后**再打一条直线，
## 对线上其余敌人造成本次伤害的一部分。
##
## 与 `armor_pierce`（削护甲）是两回事：这个是"打穿一条线"，
## 名字都带 pierce 但机制不同，故分开实现。
func _apply_pierce_line(origin: Node3D, damage: float) -> void:
	var pct := ClassDefs.special_num(class_id, form_slot, "pierce_line", 0.0)
	if pct <= 0.0 or damage <= 0.0:
		return
	var dir := CombatGeometry.flat_normalized(_facing)
	if dir == Vector3.ZERO:
		return
	var line_start: Vector3 = origin.global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == origin or not _is_valid_enemy(e):
			continue
		# 判据走 CombatGeometry —— 与群体路径**同一份实现**（见该文件头）
		if not CombatGeometry.is_on_pierce_line(line_start, dir, (e as Node3D).global_position):
			continue
		_deal_bonus_damage(e as Node3D, damage * pct, "pierce")



## 对目标结算一笔"附加伤害"（不走普攻的连击/暴击链路，独立结算）。
## `ignore_armor` 用于影子攻击（策划明写"无视护甲"）。
func _deal_bonus_damage(enemy: Node3D, amount: float, kind: String,
		ignore_armor: bool = false) -> void:
	if amount <= 0.0 or not _is_valid_enemy(enemy):
		return
	var def_v: float = 0.0
	if not ignore_armor:
		def_v = float(enemy.get("defense")) if enemy.get("defense") != null else 0.0
	var result := DamagePipeline.physical(amount, 1.0, 0.0, def_v)
	enemy.call("take_damage", float(result.damage), false, Vector3.ZERO, self)
	EventBus.damage_popup.emit(enemy.global_position, float(result.damage), kind)


## 给单个目标挂 buff（形态印记等）
func _apply_buff_to(enemy: Node3D, buff_id: String) -> void:
	if not _is_valid_enemy(enemy):
		return
	var eb = enemy.get("buffs")
	if eb != null and eb.has_method("apply"):
		eb.call("apply", buff_id, "form")


## 8.2 连锁传导：把本次伤害的一部分扩散给目标周围的敌人
func _chain_spell_damage(origin: Node3D, amount: float) -> void:
	if amount <= 0.0:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == origin or not _is_valid_enemy(e):
			continue
		if (e as Node3D).global_position.distance_to(origin.global_position) > CHAIN_RADIUS:
			continue
		_deal_bonus_damage(e as Node3D, amount, "spell")


## 连锁传导半径（策划 8.2：周围 3 米）
const CHAIN_RADIUS := 3.0


## 7.4 破极：连击数跨过 25 的整数倍时触发破极状态 6 秒。
## 用 `_break_triggered` 保证"同一次连击段内只触发一次"——
## 否则连击停在 25 附近来回时会反复刷新，等于常驻。
func _maybe_trigger_break_limit() -> void:
	var at := int(ClassDefs.special_num(class_id, form_slot, "break_limit_at", 0.0))
	if at <= 0 or buffs == null:
		return
	if _hit_combo_count < at:
		return
	if _break_triggered:
		return
	_break_triggered = true
	buffs.apply("break_limit_state", "form")
	EventBus.message.emit("破极！")


## 6.5 森之选召：在脚下生成森之领域（6 秒、4 米）。
## 同一时刻只保留一个——重复命中不该叠出一地领域。
##
## 复用 DamageZone 的「区域内挂/撤词条」能力（damage=0：领域只上 debuff 不造成伤害）。
## 它自带进区施加、出区移除的成对逻辑，比另写一套范围检测可靠。
func _spawn_forest_domain() -> void:
	if _forest_domain != null and is_instance_valid(_forest_domain):
		return
	var parent := get_parent()
	if parent == null:
		return
	_forest_domain = DamageZone.spawn({
		"radius": FOREST_DOMAIN_RADIUS,
		"duration": FOREST_DOMAIN_DURATION,
		"damage": 0.0,
		"target_group": DamageZone.TARGET_ENEMY,
		"slow_buff": "forest_domain_foe",
		"color": Color(0.25, 0.75, 0.35, 0.25),
		"position": global_position,
	}, parent)
	# 领域内猎人自身：攻速 +40%、暴击 +30%（策划 6.5）。
	# 自身增益用 buff 计时器管，领域消失后自然到期。
	if buffs != null:
		buffs.apply("forest_domain_self", "form")


const FOREST_DOMAIN_RADIUS := 4.0
const FOREST_DOMAIN_DURATION := 6.0


## 形态·连击减伤（策划 7.2 铁身「连击≥10 时减伤 25%」）。
## 只对声明了 counter_on_hit 的形态生效——否则会给所有职业白送减伤。
func _combo_damage_reduction() -> float:
	if not ClassDefs.has_special(class_id, form_slot, "counter_on_hit"):
		return 0.0
	if _hit_combo_count < COUNTER_DOUBLE_COMBO:
		return 0.0
	return COUNTER_COMBO_DR


## 光层 / 暗层积累与平衡判定（策划 8.5 光暗审裁）。
## 光层来自治疗/护盾，暗层来自施加负面；均 ≥5 时挂 verdict_balance。
func _gain_light_layer() -> void:
	if not ClassDefs.special_flag(class_id, form_slot, "light_dark_layers"):
		return
	_light_layers = mini(_light_layers + 1, LIGHT_DARK_CAP)
	_refresh_light_dark_balance()


func _gain_dark_layer() -> void:
	if not ClassDefs.special_flag(class_id, form_slot, "light_dark_layers"):
		return
	_dark_layers = mini(_dark_layers + 1, LIGHT_DARK_CAP)
	_refresh_light_dark_balance()


## 光暗均 ≥5 时挂 verdict_balance（策划 8.5：全伤害 +40%、移速 +30%）
const LIGHT_DARK_CAP := 10
const LIGHT_DARK_BALANCE_AT := 5


func _refresh_light_dark_balance() -> void:
	if buffs == null:
		return
	if _light_layers >= LIGHT_DARK_BALANCE_AT and _dark_layers >= LIGHT_DARK_BALANCE_AT:
		if not buffs.has("verdict_balance"):
			buffs.apply("verdict_balance", "form")
	else:
		if buffs.has("verdict_balance"):
			buffs.remove("verdict_balance")


## 普攻伤害结算的**共用计算段** —— 节点怪与群体单位走同一套数值。
##
## 抽出来的理由：命中链路里"找目标"有两条（场景树 group / CrowdSim 查询），
## 但**伤害公式只能有一套**。若各写一份，迟早出现"同样的攻击打节点怪和
## 打 swarm 怪伤害不一样"——那种 bug 极难察觉，玩家只会觉得"某些怪特别硬"。
##
## 参数：
##   enemy      目标（节点路径传入 EnemyBase；群体路径传 null）
##   target_def 目标防御（群体路径从 monster dict 取）
##   hp_ratio   目标血量比例（-1 = 不可知，跳过处决线判定）
##   is_backstab 是否背刺（群体单位没有朝向，恒 false）
## 返回 {damage, crit, push} —— 调用方据此扣血/击退/飘字。
func _compute_basic_damage(multiplier: float, knockback: float,
		target_def: float, elem_resist: float, vuln: float, taken_down: float,
		hp_ratio: float, is_backstab: bool) -> Dictionary:
	var atk := GameManager.stat_value("atk")
	var crt := GameManager.stat_value("crt")
	var crd := GameManager.stat_value("crd")
	var fusion_bonus := GameManager.fusion_attack_bonus()
	# 形态·近战伤害倍率（策划 3.2 狂战士「近战武器伤害 +20%」、
	# 壁垒「近战 -20%」）。普攻全是近战，直接乘在倍率上。
	multiplier *= 1.0 + ClassDefs.special_num(class_id, form_slot, "melee_dmg_pct", 0.0)
	# 形态·反击加成（策划 7.2 铁身「受伤自动反击，下次攻击 ×2.0」）。
	# 计数器在 take_damage 里置位，这里消费一次后清掉——
	# 策划写的是「下次攻击」，不是"永久翻倍"。
	if _counter_charges > 0:
		multiplier *= ClassDefs.special_num(class_id, form_slot, "counter_on_hit", 1.0)
		_counter_charges -= 1
	# 形态·背刺（策划 6.3 暗刃 ×2.0 / 8.4 暗影主宰 ×2.5）
	if is_backstab:
		multiplier *= ClassDefs.special_num(class_id, form_slot, "backstab_mult", 1.0)
	# 连击数伤害加成（每击 +2%，上限由形态决定——策划 7.4 破极「连击无上限」）
	var combo_bonus: float = minf(
		_hit_combo_count * GameBalance.COMBO_DAMAGE_PER_HIT,
		combo_cap()
	)
	# 形态·护甲穿透（策划 3.5 锁链「穿刺无视 50% 护甲」、
	# 7.1 拳师「徒手无视 5% 护甲」）。
	target_def *= 1.0 - _basic_attack_pierce()
	# 装备扩展修饰量（此处提前取：元素/真实伤害加成要用，见下）
	var sp: Dictionary = _equip_special_mods()
	var result := DamagePipeline.elemental_attack(
		atk, multiplier, fusion_bonus + combo_bonus, target_def, attack_element,
		elem_resist, vuln, taken_down)
	# 元素亲和：元素伤害 +15%（分册 4.x 词条）
	if attack_element >= 0:
		result.damage = result.damage * (1.0 + _element_affinity_bonus())
		# 装备词条·元素伤害 +N%（`elem_dmg_pct` 通道）。
		# 该通道此前零消费者——「元素伤害 +8%」这类装备加了没效果。
		# 只在**元素攻击**上生效（纯物理攻击不吃）。
		result.damage = result.damage * (1.0 + float(sp.get("elem_dmg_pct", 0.0)))
	# 装备词条·真实伤害 +N%（`true_dmg_pct` 通道）。
	# 同样此前零消费者；按「附加真实伤害」处理：无视防御，直接加在总伤上。
	var true_pct := float(sp.get("true_dmg_pct", 0.0))
	if true_pct > 0.0:
		result.damage += atk * multiplier * true_pct
	# **装备词条·攻击附带元素伤害**（装备参考2：`BONUS_ELEMENT`）。
	#
	# 规格里 11+ 件装备带这类词条（「攻击附带 50% 火焰伤害」）。
	# 旧实现把它压成了 `[Stat.ATK, 0.5]`——六把元素法杖数据一字不差，
	# 元素区别整个消失。这里按规格语义结算：**额外多出的一段元素伤害**，
	# 本体伤害照常（不替代）。
	#
	# 基准取 `atk`（武器攻击力）：规格的「攻击附带 N%」都是以攻击力为基准。
	# 目标的元素抗性由 `elem_resist` 参数传入（与本体同口径）。
	result.damage += _bonus_element_total(atk, elem_resist)
	# 法术部分不可暴击（分册 2.3）
	var can_crit := attack_element < 0 or ElementDefs.can_crit(attack_element)
	var crit := _force_crit or (can_crit and GameManager.rng.randf() < crt)
	var total := DamagePipeline.with_crit(result.damage, crit, crd)
	total *= _damage_multiplier

	# 处决线：对生命低于阈值的敌人伤害 +30%（分册「处决线」）。
	#
	# **键名必须是 `execute_bonus`**：`special_modifiers()` 的输出键由
	# `EquipmentDB.SPECIAL_STAT` 的 `out` 字段决定（"execute_line" 是**输入键**，
	# 输出键是 "execute_bonus"）。此前这里读的是 `execute_line`——
	# 那个键在输出字典里**根本不存在**，`get` 静默返回 0.0，
	# 于是**所有处决线装备一直无效**且不报错。
	var exec_line: float = float(sp.get("execute_bonus", 0.0))
	if exec_line > 0.0 and hp_ratio >= 0.0 and hp_ratio <= exec_line:
		total *= 1.3
	# 击退距离 +N%
	var kb_pct: float = float(sp.get("knockback_pct", 0.0))
	# 破隐一击（装备参考2：暗影步「下次攻击 +N% 伤害」）。
	# **消费一次即失效**：这是"蓄势一击"不是"永久加成"，
	# 不消费会让隐身变成纯增伤 buff（规格明写"下一次攻击"）。
	if _stealth_next_hit_bonus > 0.0:
		total *= 1.0 + _stealth_next_hit_bonus
		_stealth_next_hit_bonus = 0.0
		exit_stealth()
	return {"damage": total, "crit": crit, "knockback": knockback * (1.0 + kb_pct)}


## 对**群体单位**（CrowdSim）结算一次普攻命中。
##
## 与 `_apply_hit` 共用 `_compute_basic_damage`，故伤害公式完全一致。
## 形态附加效果（渡鸦法强/影子攻击/穿透线/森之领域/光暗层/破极）
## 与节点路径**同样生效**——它们要么是纯伤害、要么作用于自身，不依赖目标节点。
##
## **仍缺失的**（需目标身上有状态，见批次 6 待办）：
## 元素叠层、审判印记、咒焰/虚空印记、装备触发词条——
## 模拟核没有 buff 槽，这些要等给核加状态存储。
func _apply_hit_crowd(mgr, id: int, multiplier: float, knockback: float) -> void:
	var pos: Vector3 = mgr.call("unit_position", id)
	var monster: Dictionary = mgr.call("monster_of", id)
	# 先判存活：`damage_unit` 对已死单位返回 0，那会让下面的 kills 判定失效
	var alive_before := bool(mgr.call("is_alive", id))
	var target_def := float(monster.get("defense", 0.0))
	var hp: float = float(mgr.call("unit_hp", id))
	var max_hp := maxf(float(monster.get("hp", hp)), 1.0)
	var calc := _compute_basic_damage(multiplier, knockback, target_def,
		0.0, 0.0, 0.0, clampf(hp / max_hp, 0.0, 1.0), false)
	var total: float = calc["damage"]
	var crit: bool = calc["crit"]
	# 走 CrowdManager.damage_unit 而不是直接 apply_damage：
	# 词缀·复仇（反伤）与不朽（致命伤免伤+回血）必须在扣血之前介入，
	# 直接扣血会让这两种词缀在群体路径上静默失效。
	mgr.call("damage_unit", id, total, self, pos)
	var kills: int = 1 if (alive_before and not bool(mgr.call("is_alive", id))) else 0
	# 生命偷取（不依赖目标节点）
	var ls: float = float(_equip_special_mods().get("life_steal", 0.0))
	if ls > 0.0:
		_lifesteal_heal(total * ls)
	skills.on_hit(crit)
	if kills > 0:
		_register_hit_combo()
	EventBus.damage_popup.emit(pos, total, "crit" if crit else "normal")
	# —— 形态附加效果（与节点路径同一套，见 _on_basic_attack_landed）——
	_apply_form_extras_at(pos, total)
	# —— 给目标挂状态的效果（元素叠层 / 印记 / 触发词条）——
	# 群体单位不是场景节点，BuffHolder 需要宿主才能工作；
	# CrowdManager.buffs_of 按需建一个（见 crowd_unit_host.gd）。
	var tgt_holder: BuffHolder = mgr.call("buffs_of", id)
	if tgt_holder != null:
		_apply_element_to_holder(tgt_holder)
		_apply_form_mark_to(tgt_holder)
		_apply_trigger_affixes_holder(tgt_holder, total)
	if crit or _current_combo_stage == combo_stages_size():
		_hitstop(0.06)
		_screen_shake(0.1)


## 形态附加效果 —— **按位置**版本，两条命中路径共用。
##
## 节点路径的 `_on_basic_attack_landed(enemy, dmg)` 需要一个 EnemyBase 引用，
## 但群体单位不是节点。这里改用世界坐标：需要找周围敌人时走群体查询，
## 不需要找敌人的效果（森之领域/光暗层/破极）则与路径无关。
func _apply_form_extras_at(pos: Vector3, damage: float) -> void:
	_attack_count += 1
	# 8.1 渡鸦「所有攻击额外附加（法强×0.2）法术伤害」——
	# 附加给**被命中的那个**（按位置找最近的那个群体单位）
	var spell_pct := ClassDefs.special_num(class_id, form_slot, "spell_on_hit_ap_pct", 0.0)
	if spell_pct > 0.0:
		var ap := GameManager.stat_value("ap")
		if ap > 0.0:
			_deal_bonus_damage_crowd(pos, ap * spell_pct, "spell")
	# 8.3 影子判官「每 4 次攻击触发影子攻击（法强×0.5，无视护甲）」
	if ClassDefs.special_flag(class_id, form_slot, "shadow_every_4") \
			and _attack_count % SHADOW_ATTACK_EVERY == 0:
		var ap2 := GameManager.stat_value("ap")
		_deal_bonus_damage_crowd(pos, ap2 * 0.5, "shadow", true)
	# 6.4 鹰眼「所有攻击附带范围穿透：身后 2 米直线 40% 伤害」
	if ClassDefs.special_num(class_id, form_slot, "pierce_line", 0.0) > 0.0:
		_apply_pierce_line_at(pos, damage)
	# 6.5 森之选召「命中生成森之领域」——作用于自身，与目标类型无关
	if ClassDefs.special_flag(class_id, form_slot, "forest_domain"):
		_spawn_forest_domain()
	# 8.5 光层/暗层：施加负面 → 暗层。群体路径没有 buff 槽，
	# 但"命中本身算施加负面"的语义在锁链判官形态下成立，故照样计
	if ClassDefs.special_flag(class_id, form_slot, "light_dark_layers") \
			and ClassDefs.special_flag(class_id, form_slot, "mark_per_hit"):
		_gain_dark_layer()
	# 7.4 破极「每 25 连击触发破极状态 6 秒」——作用于自身
	_maybe_trigger_break_limit()


## 对**最近的群体单位**结算一笔附加伤害（按位置找目标）。
## 找不到群体单位时退化为对最近的节点敌人结算——保证附加伤害不凭空消失。
func _deal_bonus_damage_crowd(pos: Vector3, amount: float, kind: String,
		ignore_armor: bool = false) -> void:
	if amount <= 0.0:
		return
	var mgr = _crowd_manager()
	if mgr == null or int(mgr.get("active")) <= 0:
		return
	# 取最近的一个群体单位（半径给足，附加伤害本就跟随本次命中）
	var ids = mgr.call("query_circle", pos.x, pos.z, BONUS_TARGET_RADIUS)
	if ids.is_empty():
		return
	var best_id := int(ids[0])
	var best_d := INF
	for id in ids:
		var up: Vector3 = mgr.call("unit_position", int(id))
		var d := up.distance_to(pos)
		if d < best_d:
			best_d = d
			best_id = int(id)
	var def_v := 0.0
	if not ignore_armor:
		def_v = float(mgr.call("monster_of", best_id).get("defense", 0.0))
	var result := DamagePipeline.physical(amount, 1.0, 0.0, def_v)
	mgr.call("apply_damage", PackedInt32Array([best_id]), float(result.damage))
	EventBus.damage_popup.emit(mgr.call("unit_position", best_id), float(result.damage), kind)


## 附加伤害的搜敌半径（米）。给得比普攻范围大一点——
## 附加伤害是"这次命中的衍生效果"，不该因为目标恰好站在范围边缘就丢掉。
const BONUS_TARGET_RADIUS := 4.0


## 直线穿透（按位置版）：沿攻击方向在目标身后打一条线，只作用于群体单位。
func _apply_pierce_line_at(origin: Vector3, damage: float) -> void:
	var pct := ClassDefs.special_num(class_id, form_slot, "pierce_line", 0.0)
	if pct <= 0.0 or damage <= 0.0:
		return
	var dir := CombatGeometry.flat_normalized(_facing)
	if dir == Vector3.ZERO:
		return
	var mgr = _crowd_manager()
	if mgr == null or int(mgr.get("active")) <= 0:
		return
	# 用锥形查询取沿线候选，再按侧向偏移过滤（与节点版**同一份判据**）
	var ids = mgr.call("query_cone", origin.x, origin.z, dir.x, dir.z,
		deg_to_rad(30.0), CombatGeometry.PIERCE_LINE_LENGTH)
	for id in ids:
		var up: Vector3 = mgr.call("unit_position", int(id))
		if not CombatGeometry.is_on_pierce_line(origin, dir, up):
			continue
		var result := DamagePipeline.physical(damage * pct, 1.0, 0.0, 0.0)
		mgr.call("apply_damage", PackedInt32Array([int(id)]), float(result.damage))
		EventBus.damage_popup.emit(up, float(result.damage), "pierce")


## 本房间的群体管理器（没有则返回 null）
##
## 查找逻辑统一在 `GameRef.crowd_manager()`（跨层引用的唯一入口）。
## 房间未启用群体路径时返回 null 是正常状态，见该函数注释。
func _crowd_manager():
	return GameRef.crowd_manager()


## 对单个敌人结算伤害与击退
##
## **这是普攻的唯一漏斗**：扇形横扫、冲撞、落地 AOE 三条路径全部汇入这里，
## 所以「近战伤害 +N%」这类形态机制只需在这一处生效。
func _apply_hit(enemy: Node3D, multiplier: float, knockback: float) -> void:
	var target_def: float = enemy.get("defense") if enemy.get("defense") != null else 0.0
	# 目标身上的词条影响：易伤（毒蚀等）与减伤（护盾/防御型）
	var vuln := 0.0
	var taken_down := 0.0
	var tgt_buffs = enemy.get("buffs")
	if tgt_buffs != null and tgt_buffs is BuffHolder:
		vuln = (tgt_buffs as BuffHolder).total_vulnerability()
		taken_down = (tgt_buffs as BuffHolder).total_damage_reduction()
	var hp_ratio: float = float(enemy.call("hp_ratio")) if enemy.has_method("hp_ratio") else -1.0
	var calc := _compute_basic_damage(multiplier, knockback, target_def,
		_target_elem_resist(enemy), vuln, taken_down, hp_ratio, _is_backstab(enemy))
	var total: float = calc["damage"]
	var crit: bool = calc["crit"]
	var kb: float = calc["knockback"]
	var sp: Dictionary = _equip_special_mods()

	# 击退向量（EnemyBase 硬直期间消费）
	var push: Vector3 = Vector3.ZERO
	if kb > 0.0:
		push = (enemy.global_position - global_position)
		push.y = 0.0
		if push.length_squared() > 0.001:
			push = push.normalized() * kb
		else:
			push = _facing * kb
	enemy.call("take_damage", total, crit, push, self)
	# 形态印记：普攻也要叠（见 _apply_form_mark_to 的说明）
	_apply_form_mark_to(enemy.get("buffs"))
	# 形态·普攻附加效果（命中后结算）
	_on_basic_attack_landed(enemy, total)
	# 职业资源：**普攻命中也要积攒**。
	#
	# 此前 on_hit() 只在 SkillSystem._deal_damage 里调过——普攻命中从不积攒。
	# 于是除法师/武僧（有自然回复）外，战士/猎人/判官**只能靠挨打或放技能**
	# 攒资源，而放技能本身又要资源：死循环。实机表现就是"蓝量不能恢复"。
	skills.on_hit(crit)
	# 形态·直线穿透（策划 6.4 鹰眼「所有攻击附带范围穿透：
	# 身后 2 米直线 40% 伤害」）——沿攻击方向在目标身后再打一条线
	_apply_pierce_line(enemy, total)
	# 生命偷取：造成伤害的 N% 转回血
	var ls: float = float(sp.get("life_steal", 0.0))
	if ls > 0.0:
		_lifesteal_heal(total * ls)
	# 元素攻击：给目标叠层，并把阈值事件转成控制词条（冰冻/麻痹）
	_apply_element_to(enemy)
	# 装备触发型词条：按概率给目标施加状态（眩晕/破甲/致盲/缴械/范围伤害）
	_apply_trigger_affixes(enemy, total)
	EventBus.damage_popup.emit(enemy.global_position, total, "crit" if crit else "normal")
	# 暴击/终结技 hitstop 顿帧。
	# 阈值必须是「罕见时刻」而非常规段位——旧值 1.5 把普攻4（1.8）、
	# 冲撞（1.5）、跳跃斩（1.7）全纳入，而这些是连段家常便饭，等于
	# 每击 0.06s 的 20 倍慢动作，连段手感变成「打一下卡一下」。
	# 收紧为暴击或终结技（第 4 段）才顿帧 + 震屏。
	if crit or _current_combo_stage == combo_stages_size():
		_hitstop(0.06)
		_screen_shake(0.1)


## 目标对本元素的**实际抗性** = 怪物自带抗性 − 玩家的元素穿透。
## 分册 7.10：「法术伤害仅受极少数怪物自带抗性减免」，
## 而通用词条「元素穿透：忽视目标 5%~15% 元素抗性」正是拿来削它的。
## 结果钳到 [0, 0.9]——穿透可以完全抵掉抗性，但不该变成负抗性（反而增伤）。
func _target_elem_resist(enemy: Node3D) -> float:
	if attack_element < 0:
		return 0.0
	var raw = enemy.get("elem_resist")
	if raw == null or not (raw is Dictionary):
		return 0.0
	var key := ElementDamage.key_from_elem(attack_element)
	if key.is_empty():
		return 0.0
	var base_resist: float = float((raw as Dictionary).get(key, 0.0))
	if base_resist <= 0.0:
		return 0.0
	var pen: float = float(_equip_special_mods().get("elem_pen_pct", 0.0))
	return clampf(base_resist - pen, 0.0, 0.9)


## 取已装备的特殊修饰量汇总（生命偷取/击退加成/负效时长/元素穿透/
## 反弹/处决线）。装备管理器不可用时返回全 0，调用方无需判空。
func _equip_special_mods() -> Dictionary:
	var em = GameManager.equipment_manager
	if em == null or not em.has_method("special_modifiers"):
		return {}
	return em.special_modifiers()


## 当前生效的**技能增益**词条提供的修饰量（装备参考2 的 buff 类技能）。
##
## **为什么需要单独一条通道**：装备技能的自身增益（减伤/闪避/格挡/反伤）
## 走的是 `BuffHolder`，而不是装备的 `special_modifiers`（那是**穿戴**装备
## 的常驻加成，与**施放**技能得到的限时状态是两回事）。
## 例：「大地守护」施放后 5 秒内减伤 30%——只在 buff 生效期间算，
## 不能写进装备的常驻修饰量。
##
## 返回 `{dr, dodge, block, reflect}`（缺省 0.0）。
func _skill_buff_mods() -> Dictionary:
	var out := {"dr": 0.0, "dodge": 0.0, "block": 0.0, "reflect": 0.0}
	if buffs == null:
		return out
	if buffs.has_method("total_damage_reduction"):
		out["dr"] = float(buffs.call("total_damage_reduction"))
	for id in buffs.call("active_ids"):
		var p: Dictionary = buffs.call("params_of_active", str(id))
		out["dodge"] = float(out["dodge"]) + float(p.get("dodge_up", 0.0))
		if bool(p.get("block_all", false)):
			out["block"] = 1.0
		out["reflect"] = float(out["reflect"]) + float(p.get("reflect_up", 0.0))
	return out


## 生命偷取回血（分册第 5 章通用词条）。治疗量受「受到治疗 -%」影响。
func _lifesteal_heal(amount: float) -> void:
	if amount <= 0.0:
		return
	if GameManager.attributes == null or GameManager.attributes.is_dead():
		return
	var heal_down: float = 0.0
	if buffs != null:
		heal_down = buffs.total_heal_reduction()
	var healed: float = GameManager.attributes.heal(amount * (1.0 - clampf(heal_down, 0.0, 1.0)))
	if healed > 0.0:
		EventBus.damage_popup.emit(global_position, healed, "heal")
	# 形态·溢出转护盾（策划 3.6 解放者「溢出的治疗量转化为护盾，上限 60% 最大生命」）。
	# 满血时吸血本应完全浪费，这个形态把浪费掉的那部分变成有效生命。
	var overflow := (amount * (1.0 - clampf(heal_down, 0.0, 1.0))) - healed
	var shield_pct := ClassDefs.special_num(class_id, form_slot, "overflow_to_shield", 0.0)
	if overflow > 0.0 and shield_pct > 0.0:
		_add_shield(overflow, shield_pct)


## 护盾吸收伤害，返回未被吸收完、仍需扣血的剩余量。
## 护盾是"临时生命"，在 hp 之前消耗。
func _absorb_with_shield(amount: float) -> float:
	if temp_shield <= 0.0:
		return amount
	var used: float = minf(temp_shield, amount)
	temp_shield -= used
	if temp_shield <= 0.0:
		temp_shield = 0.0
	return amount - used


## 加护盾，上限为 max_hp 的 cap_pct（防止无限叠成无敌）。
func _add_shield(amount: float, cap_pct: float) -> void:
	var cap: float = GameManager.attributes.max_hp * clampf(cap_pct, 0.0, 1.0)
	temp_shield = minf(temp_shield + amount, cap)
	EventBus.damage_popup.emit(global_position, amount, "armor")
	EventBus.stats_changed.emit()


## 装备触发型词条：命中时按概率给目标施加状态（名词分册第 5 章）。
##
## 与元素控制的关系：元素走「叠层到阈值」（冰冻/麻痹），
## 这里是装备直接的概率触发，两条链路独立判定、可叠加。
## 概率在 EquipmentManager 侧已按同名词条累加（两件 5% = 10%）。
func _apply_trigger_affixes(enemy: Node3D, damage: float) -> void:
	# 装备触发条件（装备参考2：「命中时…」类自有词条）
	if equip_fx != null:
		equip_fx.on_hit()
	var em = GameManager.equipment_manager
	if em == null or not em.has_method("equipped_trigger_affixes"):
		return
	var triggers: Array = em.equipped_trigger_affixes()
	if triggers.is_empty():
		return
	var tgt_buffs = enemy.get("buffs")
	if tgt_buffs == null:
		return
	# 负效时长 +N%（分册通用词条）放大本次施加的持续时间
	var dur_bonus: float = float(_equip_special_mods().get("debuff_dur_pct", 0.0))

	for t in triggers:
		if randf() > float(t.get("chance", 0.0)):
			continue
		var bid: String = str(t.get("buff", ""))
		if bid.is_empty():
			continue
		# 范围伤害是特殊项：不是施加词条，而是对周围造成溅射
		if bid == "splash":
			_apply_splash_damage(enemy, damage)
			continue
		# 时长：词条自带时长 ×(1+负效加成)；<=0 表示用表定值
		var dur: float = float(t.get("duration", 0.0))
		tgt_buffs.apply(bid, "equip")
		# 施加后按加成延长（BuffHolder 记录的是表定 remaining，这里补差）
		if dur_bonus > 0.0:
			_extend_buff_duration(tgt_buffs, bid, dur_bonus)
		EventBus.message.emit("触发【%s】" % _buff_name(bid))


## 延长目标身上某词条的剩余时长（负效时长 +N%）。
func _extend_buff_duration(tgt_buffs, buff_id: String, bonus: float) -> void:
	if tgt_buffs == null or not tgt_buffs.has(buff_id):
		return
	var e = tgt_buffs.get("_buffs")
	if e is Dictionary and (e as Dictionary).has(buff_id):
		var rec: Dictionary = (e as Dictionary)[buff_id]
		var cur: float = float(rec.get("remaining", 0.0))
		if cur > 0.0:
			rec["remaining"] = cur * (1.0 + bonus)


## 词条显示名（取不到时回退 id）
func _buff_name(buff_id: String) -> String:
	var row: Array = BuffDefs.get_buff(buff_id)
	if row.is_empty():
		return buff_id
	return str(row[1])


## 范围伤害（分册通用词条「攻击附带 攻击力×0.1 范围伤害（2 米内）」）。
## 只伤害目标周围**其它**敌人——主目标已经在本次命中里结算过了。
func _apply_splash_damage(center: Node3D, _base_damage: float) -> void:
	var atk: float = GameManager.stat_value("atk")
	var splash: float = atk * EquipmentDB.SPLASH_ATK_RATIO
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == center or not _is_valid_enemy(e):
			continue
		var d: float = (e as Node3D).global_position.distance_to(center.global_position)
		if d > EquipmentDB.SPLASH_RADIUS:
			continue
		(e as Node3D).call("take_damage", splash, false, Vector3.ZERO)
		EventBus.damage_popup.emit((e as Node3D).global_position, splash, "aoe")


## 把本次攻击的元素叠到目标身上，并处理阈值触发（冰冻/雷暴）## 攻击元素来源：已装备武器的 element 字段；未赋予则为纯物理，不叠层。
func _apply_element_to(enemy: Node3D) -> void:
	_apply_element_to_holder(enemy.get("buffs"))


## 给目标挂元素层数（按 holder 版本）。
##
## 抽出来是为了让**节点路径与群体路径共用同一套逻辑**——
## 群体单位不是节点，但它同样能拿到一个 BuffHolder 宿主
##（见 gameplay/enemies/crowd_unit_host.gd）。
## 两处各写一份的话，迟早出现"元素在节点怪上生效、在 swarm 怪上不生效"。
func _apply_element_to_holder(tgt) -> void:
	if attack_element < 0 or tgt == null:
		return
	var out: Dictionary = ElementDamage.attack(tgt, attack_element)
	for ev in out.get("events", []):
		var ctrl_id: String = ElementDamage.control_for_event(str(ev))
		if ctrl_id != "":
			tgt.apply(ctrl_id, "element")
			EventBus.message.emit("触发%s" % ElementDamage.event_name(str(ev)))


## 形态印记（咒焰/虚空印记）挂到目标身上（按 holder 版本）。
##
## **为什么普攻也要叠**：咒焰使的两个技能一个是 detonate（引爆目标身上
## 已有的 flame_mark 层数）、一个是 buff，没有任何一个技能能产生层数。
## 只在技能侧接的话，该形态会陷入"要引爆先得有层数、要有层数却只能引爆"
## 的死循环——实测症状正是"放完技能敌人身上 0 层"。
func _apply_form_mark_to(tgt) -> void:
	var mark := ClassDefs.form_mark_id(class_id, form_slot)
	if mark.is_empty() or tgt == null:
		return
	if tgt.has_method("apply"):
		tgt.call("apply", mark, "form")


## 装备触发型词条（按 holder 版本）。
## 与节点版 `_apply_trigger_affixes(enemy, dmg)` 同源，只是目标换成 holder。
func _apply_trigger_affixes_holder(tgt, damage: float) -> void:
	if tgt == null or damage <= 0.0:
		return
	var em = GameManager.equipment_manager
	if em == null or not em.has_method("equipped_trigger_affixes"):
		return
	var triggers: Array = em.equipped_trigger_affixes()
	if triggers.is_empty():
		return
	for t in triggers:
		var d: Dictionary = t
		var chance := float(d.get("chance", 0.0))
		if chance <= 0.0 or GameManager.rng.randf() > chance:
			continue
		var bid := str(d.get("buff", ""))
		if bid.is_empty():
			continue
		if tgt.has_method("apply"):
			tgt.call("apply", bid, "equip")


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
		PlayerSfx.on_hit_landed()


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


## 屏幕震动转发（实现已拆到 CameraFx）。
##
## **偏移加在相机节点上而非 rig** 的原因见 entities/player/camera_fx.gd 文件头。
func _screen_shake(strength: float) -> void:
	cam_fx.shake(strength)


## 挥砍视觉转发（实现已拆到 FxComponent）。
##
## 性能设计（材质按色缓存 / 网格按形状缓存 / 节点池复用）见
## entities/player/fx_component.gd 的文件头。
func _spawn_slash_visual(reach: float, half_angle: float,
		color: Color = Color(1, 1, 0.85, 0.5)) -> void:
	fx.spawn_slash(reach, half_angle, color)

## 敌人有效性检查
func _is_valid_enemy(enemy: Node) -> bool:
	return is_instance_valid(enemy) and enemy is Node3D and enemy.has_method("take_damage")


## 连击计数（命中即计，2 秒无命中清零）
func _register_hit_combo() -> void:
	_hit_combo_count += 1
	_hit_combo_time = 2.0
	# 形态·连击回复（策划 7.3 疾风「连击≥10 时每次攻击恢复 2% 已损生命」）
	_apply_combo_heal()


## 形态·连击达标时按比例回复**已损生命**（不是最大生命的百分比——
## 策划写的是「已损生命」，残血时回复量才够看，满血时为 0）。
func _apply_combo_heal() -> void:
	var pct := ClassDefs.special_num(class_id, form_slot, "combo_heal", 0.0)
	if pct <= 0.0 or _hit_combo_count < COMBO_HEAL_THRESHOLD:
		return
	var attrs = GameManager.attributes
	if attrs == null or attrs.is_dead():
		return
	var lost: float = maxf(attrs.max_hp - attrs.hp, 0.0)
	if lost > 0.0:
		_lifesteal_heal(lost * pct)


## 连击回复的触发门槛（策划 7.3：连击≥10）
const COMBO_HEAL_THRESHOLD := 10


## 当前连击数（HUD 用）
func get_hit_combo() -> int:
	return _hit_combo_count


## 主动加连击数（武僧技能用：疾风连打「连击翻倍」/ 风之步「+3」）。
## 同时刷新连击计时窗口，否则加完立刻因超时清零。
func add_hit_combo(n: int) -> void:
	if n <= 0:
		return
	_hit_combo_count += n
	_hit_combo_time = 2.0


## from：攻击者（可选）。仅用于**伤害反弹**词条（分册限定「受到近战伤害时」），
## 传 null 表示无来源（区域伤害/DOT 等），不触发反弹。
## 保持默认值以兼容既有调用（敌人 AI、DamageZone、测试）。
## 真实伤害 —— 无视护甲、减伤、霸体与护盾，**只受无敌帧保护**。
##
## 用途：第 6 层「硫磺毒气」每层每秒 ×1.5 的真实伤害（策划 6.7 明写
## "真实伤害"）。走这个入口而不是 `take_damage`，否则玩家堆防御就能
## 把毒气完全免疫，机制失去意义。
##
## 仍保留无敌帧判定与受击反馈——"翻滚能躲"是合理的操作空间，
## 但"堆减伤能免疫"不是。
func take_true_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	if _is_dodging or _jump_phase == JumpPhase.DIVE:
		return
	if _god_mode:
		return
	var attrs = GameManager.attributes
	if attrs == null or attrs.is_dead():
		return
	attrs.take_damage(amount)
	EventBus.player_hit.emit(amount, global_position)
	EventBus.damage_popup.emit(global_position, amount, "true")
	fx.flash()
	EventBus.stats_changed.emit()
	if attrs.is_dead():
		die()


## 装备·格挡/闪避的免伤判定（装备参考2 扩充通道）。
##
## 两者的语义差别：**格挡**是举盾硬挡（有盾牌/格挡词条时），
## **闪避**是侧身躲开。机制上都是「按概率完全免伤」，故合并成一次判定——
## 概率相加后取一次随机，避免连续判两次导致实际免伤率被放大
##（1-(1-a)(1-b) ≠ a+b，分开判会让「格挡10%+闪避10%」变成 19% 而不是 20%）。
##
## 上限 75%：全免伤会让游戏失去威胁（策划也未给超过这个量级的数值）。
## 返回 true 表示本次伤害被完全免除。
func _roll_avoidance() -> bool:
	var sp: Dictionary = _equip_special_mods()
	var chance: float = float(sp.get("block_pct", 0.0)) + float(sp.get("dodge_pct", 0.0))
	# 技能增益也能给闪避/格挡（装备参考2：疾风步「闪避+30%」、
	# 反击姿态「3 秒内格挡所有攻击」）。与装备通道**相加**——
	# 两者来源不同（穿戴 vs 施法），同时存在时理应都算。
	var sb: Dictionary = _skill_buff_mods()
	chance += float(sb["dodge"]) + float(sb["block"])
	if chance <= 0.0:
		return false
	chance = clampf(chance, 0.0, 0.75)
	if GameManager.rng.randf() >= chance:
		return false
	EventBus.message.emit("格挡！免疫本次伤害")
	return true


## 玩家受击的**扩展签名**：带元素与「是否元素伤害」标记。
##
## 为什么要有这个重载：原 `take_damage(amount, from)` 不带元素信息，
## 于是「受到火焰伤害 -3%」这类词条**无法按元素细分**。
## 攻击方（敌人/投射物）是知道自己的元素的，故加一条带元素的路径，
## 由它们主动调用；老的 `take_damage(amount, from)` 保留为纯物理入口
##（不传元素 = 物理，与既有行为一致）。
func take_elemental_damage(amount: float, elem: int, from: Node3D = null) -> void:
	# 装备·元素减伤（装备参考2 扩充通道）：elem >= 0 才算元素伤害。
	# **只对元素伤害生效**——物理伤害不该被「元素抗性」减免。
	if elem >= 0:
		var er: float = float(_equip_special_mods().get("elem_resist_pct", 0.0))
		if er > 0.0:
			amount *= 1.0 - clampf(er, 0.0, 0.8)
	take_damage(amount, from)


func take_damage(amount: float, from: Node3D = null) -> void:
	# 翻滚/俯冲无敌帧
	if _is_dodging or _jump_phase == JumpPhase.DIVE:
		return
	# 装备·格挡 / 闪避（装备参考2 扩充通道）：
	# 两者都是「按概率完全免伤」，差别只在来源语义（格挡=举盾挡下、闪避=躲开）。
	# 放在最前面判——免伤就该在一切结算之前发生，否则护盾/减伤先扣一遍
	# 再免伤会让玩家白掉资源。
	if _roll_avoidance():
		EventBus.player_hit.emit(0.0, global_position)
		fx.flash()
		return
	# 形态·翻滚后免疫一次（策划 6.2 斥候「翻滚后免疫下一次攻击」）。
	# 与无敌帧是两回事：无敌帧只在翻滚**过程中**生效，这个是在翻滚
	# **结束后**仍能挡下一次。消费一次后失效。
	if _dodge_immune_ready:
		_dodge_immune_ready = false
		EventBus.player_hit.emit(0.0, global_position)
		fx.flash()
		EventBus.message.emit("闪避！免疫本次伤害")
		return
	# 终结技霸体：减伤 30%，不掉连段节奏（无硬直状态，攻击照常续接）
	var armor := _finisher_armor_timer > 0.0
	if armor:
		amount *= 0.7
	# 隐身免疫（装备参考2：暗影刺杀「隐身期间免疫所有伤害」）
	if _stealth_invuln and _stealth_timer > 0.0:
		EventBus.player_hit.emit(0.0, global_position)
		fx.flash()
		return
	# 调试无敌：在无敌帧/霸体之后、真正扣血之前拦下。
	# 刻意保留下面的受击闪红与 player_hit 信号——「看得到打中」才是有意义的无敌，
	# 否则没法用它观察命中判定。
	if _god_mode:
		EventBus.player_hit.emit(0.0, global_position)
		fx.flash()
		return
	# 护盾先吃伤害（形态「溢出转护盾」产生）。全被护盾吸收时不掉血，
	# 但仍照常走受击反馈——玩家要看得出"护盾挡了一下"。
	var to_hp := _absorb_with_shield(amount)
	amount = maxf(to_hp, 0.0)
	# 形态·受伤触发（在真正扣血前记录，用**护盾吸收后**的实际伤害）：
	#   7.2 铁身「受伤自动反击，下次攻击 ×2.0」；连击≥10 时反击翻倍
	#   6.2 斥候「脱战计时」被打断
	#   8.5 光暗审裁「暗层（施加负面积累）」受伤也算一次暗层
	_on_player_hurt(amount)
	# 形态·连击减伤（策划 7.2 铁身「连击≥10 时减伤 25%」）
	var combo_dr := _combo_damage_reduction()
	if combo_dr > 0.0:
		amount *= 1.0 - combo_dr
	# 技能增益·减伤（装备参考2：大地守护「获得 30% 减伤」、
	# 石肤「20% 减伤」、钢铁之躯「50% 减伤」）。
	#
	# **此前玩家侧完全没有这条**：`total_damage_reduction()` 只在
	# `_apply_hit` 里对**敌人**用过（玩家打敌人时读敌人的减伤），
	# 玩家自己身上的减伤词条零消费——技能挂了 buff 却不减伤。
	var skill_dr: float = float(_skill_buff_mods()["dr"])
	if skill_dr > 0.0:
		amount *= 1.0 - skill_dr
	GameManager.attributes.take_damage(amount)
	EventBus.player_hit.emit(amount, global_position)
	EventBus.damage_popup.emit(global_position, amount, "player" if not armor else "armor")
	PlayerSfx.on_hurt()
	# 受击闪红：玩家此前没有任何受击视觉，扣血了却看不出来
	fx.flash()
	# HUD 血量刷新：玩家受伤不发 stats_changed，HUD 数值不会变
	EventBus.stats_changed.emit()
	# 伤害反弹（分册第 5 章通用词条「受到近战伤害时反弹 5%~15%」）。
	# 只在**近战来源**下触发——分册明确限定近战；远程/区域伤害不反弹。
	if from != null and is_instance_valid(from) and amount > 0.0:
		_reflect_damage(from, amount)

	if GameManager.attributes.is_dead():
		die()


## 伤害反弹：把本次受到伤害的 N% 打回攻击者。
## 用 take_damage 回流，故对方的护甲/减伤照常参与结算——反弹是「以对方的
## 规则打对方」，不是真实伤害。
##
## **两个来源相加**：
##   · 装备常驻 `reflect_pct`（SPECIAL_STAT 104，穿戴即生效）
##   · 技能限时 buff 的 `reflect_up`（装备参考2「3 秒内反弹 100% 伤害」）
func _reflect_damage(attacker: Node3D, amount: float) -> void:
	var pct: float = float(_equip_special_mods().get("reflect_pct", 0.0))
	pct += float(_skill_buff_mods()["reflect"])
	if pct <= 0.0:
		return
	var back: float = amount * pct
	if back <= 0.0:
		return
	if attacker.has_method("take_damage"):
		attacker.call("take_damage", back, false, Vector3.ZERO)
		EventBus.damage_popup.emit(attacker.global_position, back, "aoe")


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
	PlayerSfx.on_death()
	# 切到死亡状态：即便物理帧因故仍在跑，也不再有每帧行为
	if _state_machine:
		_state_machine.transition_to("DeadState")
	# finish_run 内部已发 run_finished（结算面板监听显示）
	GameManager.finish_run("defeated")
	set_physics_process(false)

# ============================================================
# 拾取 / 交互（转发到 PickupComponent）
# ============================================================
#
# 实现已搬到 `entities/player/pickup_component.gd`。
# 这里保留**同名同签名的转发**，外部调用点（`_unhandled_input` 的键位分发、
# 测试的 `probe.pickup_nearby`）零改动。

## E 键等输入分发。拾取相关的三条分支转发到组件。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		EventBus.message.emit("背包")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		# 交互优先级：破墙（隐藏房）→ 特殊房 → 拾取（顺序见组件注释）
		pickup.try_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("devour"):
		pickup.try_devour()
		get_viewport().set_input_as_handled()


## 切换拾取方式（按 E 手动 ↔ 自动拾取）。仅由设置面板调用。
func _toggle_auto_pickup() -> void:
	pickup.toggle_auto_pickup()


## 破墙进入隐藏房。返回 true 表示本次交互已被处理。
func _interact_hidden_wall() -> bool:
	return pickup.interact_hidden_wall()


## 交互当前房间的商店/泉水/事件服务。
## 返回 false 表示"本房不是特殊房"，让位给拾取。
func _interact_special_room() -> bool:
	return pickup.interact_special_room()


## 查找最近的掉落物（拾取/吞噬共用）
func _nearest_pickup() -> Node3D:
	return pickup.nearest_pickup()


## 当前房间的掉落物管理器（没有则返回 null，**null 是正常状态**）
func _pickup_field() -> PickupField:
	return pickup.pickup_field()


## 拾取最近掉落物进背包
func _pickup_nearby() -> void:
	pickup.pickup_nearby()


## 吞噬最近掉落物（本局永久成长）
func _devour_nearby() -> void:
	pickup.devour_nearby()


## 受击闪红剩余时间（转发到 FxComponent；测试与 HUD 读它判断反馈是否在跑）
func flash_timer() -> float:
	return fx.flash_timer() if fx != null else 0.0


## 装配召唤物管理器（装备技能「召唤狼灵/护卫/元素灵」用）
func _setup_summons() -> void:
	summons = SummonManager.new()
	summons.name = "SummonManager"
	add_child(summons)
	summons.setup(self)


## 进入隐身（装备参考2：暗影步/烟雾弹/暗影刺杀）。
##
## 隐身期间：
##   · 模型半透明（视觉上"看不见了"）
##   · 敌人不再以你为目标（见 enemy_base._find_player 的 stealth 判断）
##   · 移速加成（规格里常配 +30%）
##   · 可选免疫伤害（暗影刺杀）
## 破隐：下一次攻击吃 `next_hit_bonus` 加成，然后隐身结束。
func enter_stealth(seconds: float, speed_pct: float,
		next_hit_bonus: float, invuln: bool) -> void:
	_stealth_timer = maxf(seconds, 0.1)
	_stealth_speed_pct = speed_pct
	_stealth_next_hit_bonus = next_hit_bonus
	_stealth_invuln = invuln
	_apply_stealth_visual(true)
	EventBus.message.emit("进入隐身")


## 当前是否处于隐身
func is_stealthed() -> bool:
	return _stealth_timer > 0.0


## 退出隐身（破隐/超时）
func exit_stealth() -> void:
	if _stealth_timer <= 0.0:
		return
	_stealth_timer = 0.0
	_stealth_speed_pct = 0.0
	_stealth_invuln = false
	_apply_stealth_visual(false)


## 隐身视觉：模型半透明。
##
## 用 `_model.transparency`（MeshInstance3D 的几何透明度属性）而不是改材质——
## 改材质会与闪红（ToonMaterial 的 set_color）抢同一个槽位，
## 隐身时受击闪红会失效，反之亦然。
func _apply_stealth_visual(on: bool) -> void:
	if fx == null:
		return
	var m := fx.model()
	if m != null:
		m.transparency = 0.75 if on else 0.0


## 隐身每帧推进（由 _physics_process 调用）
func _tick_stealth(delta: float) -> void:
	if _stealth_timer <= 0.0:
		return
	_stealth_timer = maxf(_stealth_timer - delta, 0.0)
	if _stealth_timer <= 0.0:
		exit_stealth()


## 已装备装备提供的「攻击附带元素伤害」总和（装备参考2：BONUS_ELEMENT）。
##
## **遍历复数表而不是首项**：一件装备可能有多条自有词条
##（规格里约 100 件是复合的），只读 `own_affix` 会漏掉后半条。
func _bonus_element_total(base: float, target_resist: float) -> float:
	var em = GameManager.equipment_manager
	if em == null:
		return 0.0
	var total := 0.0
	for inst in em.get_equipped().values():
		if inst == null:
			continue
		var tpl = inst.get_template()
		if tpl == null:
			continue
		for a: AffixData in tpl.own_affixes:
			if a == null or a.operation != AffixData.Operation.BONUS_ELEMENT:
				continue
			# 数值随「同件融合升级」成长（与其它自有词条同口径）
			var ratio: float = float(a.value) * (1.0 + float(inst.same_fuse_level(tpl.id)) * 0.25)
			total += DamagePipeline.bonus_element_damage(
				base, ratio, str(a.element_key), target_resist)
	return total
