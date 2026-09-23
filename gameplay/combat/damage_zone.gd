class_name DamageZone
extends Area3D
## 持续伤害区域 —— 毒液区 / 火焰光环 / 岩浆轨迹 / 水波
##
## 取代原先散落在 EnemyBase 里的 `_spawn_death_poison`——那版用 await
## 定时器逐秒结算，节点被 free 时协程会悬挂（投射物系统踩过同一个坑）。
## 本类改用 _process 计时，无协程悬挂风险，且统一支持：
##   · 敌对伤害（打玩家或打敌人，按目标组）
##   · 友方增益（毒腺蛙的毒液区给区域内怪物回血）
##   · 跟随施法者移动（光环型）
##   · 随施法者死亡而消失

const TARGET_PLAYER := "player"
const TARGET_ENEMY := "enemies"

var radius := 2.0
var height := 2.0
var duration := 5.0            ## 总持续时间（秒）；<0 表示永久（跟随型光环）
var tick_interval := 1.0       ## 每秒结算几「跳」（1.0 = 每秒一次）
var damage_per_tick := 10.0
var heal_per_tick := 0.0       ## 区域内友方每跳回血（>0 时生效）
var target_group := TARGET_PLAYER
var friendly_group := ""       ## 回血作用的对象组（留空则不回血）
var slow_buff := ""            ## 区域内目标持续挂的减速词条 id（陷阱型）
var follow: Node3D = null      ## 跟随目标（光环型）；为空则固定原地
## 是否绑定了跟随目标。**不能用 `follow != null` 判断**——Godot 4 中
## 已释放的对象引用与 null 比较**相等**，那样写会让「施法者已死」的分支
## 永远进不去，光环变成孤儿持续伤害玩家（实测踩到）。
var _follows := false
var color := Color(0.3, 0.9, 0.2, 0.4)
var _elapsed := 0.0
var _tick_accum := 0.0
## 每跳结算回调 `func(zone: DamageZone, node: Node3D) -> bool`。
##
## **返回 true 表示本次已由回调处理**，本类不再走默认的 `take_damage`
## 裸伤害路径。装备技能的持续区域（毒雾 / 烈焰风暴 / 风暴之眼）需要
## **完整的伤害管线**——面板 ATK × 倍率、元素叠层、暴击、伤害飘字——
## 这些都在 `SkillSystem._deal_damage` 里，裸 `take_damage` 全都没有。
##
## 留空则保持旧行为（怪物陷阱用的裸伤害），两者互不影响。
var on_tick: Callable = Callable()


## 生成一个伤害区域
static func spawn(data: Dictionary, parent: Node3D) -> DamageZone:
	var z := DamageZone.new()
	z.radius = float(data.get("radius", 2.0))
	z.height = float(data.get("height", 2.0))
	z.duration = float(data.get("duration", 5.0))
	z.tick_interval = maxf(float(data.get("tick_interval", 1.0)), 0.05)
	z.damage_per_tick = float(data.get("damage", 10.0))
	z.heal_per_tick = float(data.get("heal", 0.0))
	z.target_group = str(data.get("target_group", TARGET_PLAYER))
	z.friendly_group = str(data.get("friendly_group", ""))
	z.slow_buff = str(data.get("slow_buff", ""))
	z.follow = data.get("follow", null)
	z._follows = z.follow != null
	z.color = data.get("color", z.color)
	z.position = data.get("position", Vector3.ZERO)
	z.on_tick = data.get("on_tick", Callable())
	parent.add_child(z)
	z._build()
	return z


func _build() -> void:
	add_to_group("damage_zones")
	collision_layer = 0
	monitoring = false   # 不依赖物理回调，主动轮询（更可控）

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	add_child(col)

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 1.5
	# **必须用抖动透明（HASH）而不是 ALPHA**：
	# 像素化管线（SubViewport + 后处理）下 `TRANSPARENCY_ALPHA` 的区域
	# **完全不渲染**——实机症状是"陷阱特效消失"。
	# 实测对比（同位置、同颜色，只换 transparency 模式）：
	#   ALPHA(1) 不可见 · DISABLED(0) 可见 · SCISSOR 可见 · HASH 可见
	# HASH 既保留半透明观感、又是硬边裁剪，与像素风格天然契合，故采用。
	#
	# 根因未完全定位（后处理只取 rgb 不碰 alpha），但四种模式的实测
	# 结果一致且可复现，HASH 是其中唯一兼顾"可见 + 半透明"的选项。
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	# 抖动阈值：alpha 越低露出的地面越多（观感越"淡"）
	mat.alpha_scissor_threshold = clampf(1.0 - color.a, 0.05, 0.95)
	mesh.material_override = mat
	add_child(mesh)


func _process(delta: float) -> void:
	# 跟随型（光环）：贴在施法者身上；施法者没了则一同消失。
	# 注意用 _follows 而非 `follow != null`——见该字段的注释。
	if _follows:
		if not is_instance_valid(follow):
			queue_free()
			return
		global_position = follow.global_position

	_elapsed += delta
	if duration >= 0.0 and _elapsed >= duration:
		queue_free()
		return

	_tick_accum += delta
	if _tick_accum < tick_interval:
		return
	_tick_accum -= tick_interval
	_apply_tick()


## 一次结算：对目标组造成伤害，对友方组回血
func _apply_tick() -> void:
	if target_group != "":
		for n in get_tree().get_nodes_in_group(target_group):
			if not (n is Node3D):
				continue
			if global_position.distance_to((n as Node3D).global_position) > radius:
				continue
			# 技能区域：交给回调走完整伤害管线（元素/暴击/飘字）
			if on_tick.is_valid():
				if bool(on_tick.call(self, n)):
					continue
			if damage_per_tick > 0.0 and n.has_method("take_damage"):
				n.call("take_damage", damage_per_tick)

	if heal_per_tick > 0.0 and friendly_group != "":
		for n in get_tree().get_nodes_in_group(friendly_group):
			if not (n is Node3D):
				continue
			if global_position.distance_to((n as Node3D).global_position) > radius:
				continue
			# 敌人回血：直接加血并刷新血条
			if n.get("_hp") != null:
				var max_hp := float(n.get("max_hp"))
				n.set("_hp", minf(float(n.get("_hp")) + heal_per_tick, max_hp))
				if n.has_method("_update_health_bar"):
					n.call("_update_health_bar")

	# 减速陷阱（骸骨猎犬 / 第 2 层坍方区）：区域内目标挂减速词条。
	#
	# **必须成对：进区施加、出区移除。** 原先只有施加没有移除，而这里用的
	# thorn_slow 是 duration=0 的永久词条（策划口径「移速 -50%（踏入期间）」，
	# 靠离开时撤掉）——于是玩家一旦踩进第 2 层的坍方区，-50% 移速就永久挂着，
	# 后续无论走到哪都脱不掉（实测踩到）。
	# 移除只针对**本区域施加的**（用本区域实例 id 作 source），
	# 避免误删同一词条的其它来源（怪物命中减速等）。
	if slow_buff != "":
		var my_source := "zone_%d" % get_instance_id()
		for n in get_tree().get_nodes_in_group(target_group):
			if not (n is Node3D):
				continue
			var tb = n.get("buffs")
			if tb == null:
				continue
			if global_position.distance_to((n as Node3D).global_position) <= radius:
				tb.apply(slow_buff, my_source)
			else:
				tb.remove_from_source(slow_buff, my_source)
