class_name EffectField
extends Node3D
## 战斗特效池 —— 消除「每次命中现建节点 + Tween」的开销
##
## ## 为什么需要
## 项目此前**零粒子系统**，战斗特效靠每次现建 `MeshInstance3D` + `create_tween()`：
##   · 节点创建/销毁是纯 CPU 开销
##   · 每个 Tween 每帧都要被调度推进
## 一次群战里 2000 只怪同时被 AOE 命中，按"每击 8 个球"算就是 16000 个节点
## + 16000 个 Tween 同帧创建——必然卡顿。
##
## ## 做法
## 两层池化，复用 `player.gd:_slash_pool` 已验证的模式：
##   1. **发射器池**：每种特效预建 N 个 `GPUParticles3D`，用完归还而不是销毁
##   2. **材质缓存**：按「类型 + 颜色」缓存 `ParticleProcessMaterial`，
##      不每次新建
##
## 粒子本身由 GPU 推进（GPUParticles3D 的固有特性），CPU 每帧零开销——
## 这正是"大量粒子不卡"的关键。
##
## ## 为什么用 GPUParticles3D 而不是自写实例缓冲
## 粒子数量在 GPU 侧是固定容量（`amount`），超出直接丢弃，不会拖垮帧率；
## 且重力/散射/颜色渐变这些都有现成参数，不必自己写着色器。
## 自写方案控制力更强但维护成本高——本项目没有那个必要。

## 每种特效的预建数量。取值依据：同屏同时播放的特效峰值，
## 超出后复用最旧的（视觉上只是"特效被顶掉"，不会漏伤害）。
const POOL_PER_KIND := 24

## 特效类型 → 粒子参数预设
##   amount        粒子数
##   lifetime      存活秒数
##   speed         初速范围
##   spread        散射角（度）
##   gravity       重力
##   size          粒子大小
##   one_shot      是否一次性爆发
const PRESETS := {
	# 命中火花：小、快、向上散开
	"hit": {
		"amount": 8, "lifetime": 0.35, "speed": Vector2(2.0, 5.0),
		"spread": 55.0, "gravity": Vector3(0, -6.0, 0), "size": 0.12,
	},
	# 死亡爆炸：大、慢、向外扩散
	"death": {
		"amount": 20, "lifetime": 0.6, "speed": Vector2(3.0, 8.0),
		"spread": 90.0, "gravity": Vector3(0, -4.0, 0), "size": 0.22,
	},
	# 元素附着：环绕式、轻、慢
	"element": {
		"amount": 12, "lifetime": 0.8, "speed": Vector2(0.8, 2.5),
		"spread": 180.0, "gravity": Vector3(0, -0.8, 0), "size": 0.16,
	},
	# 群体死亡：更轻量（可能同时几百个，粒子数要压住）
	"swarm_death": {
		"amount": 4, "lifetime": 0.4, "speed": Vector2(1.5, 3.5),
		"spread": 90.0, "gravity": Vector3(0, -5.0, 0), "size": 0.14,
	},
}

## 池：kind → 空闲发射器列表
var _free: Dictionary = {}
## 池：kind → 全部发射器（用于上限淘汰）
var _all: Dictionary = {}
## 材质缓存：kind_color → ParticleProcessMaterial
static var _mat_cache: Dictionary = {}
## 当前活跃的发射器（kind → 列表，用于"池满时顶掉最旧的"）
var _live: Dictionary = {}

## 播放计数（测试用）
var _play_count := 0


## 播放一次特效。返回是否成功（后端不可用时返回 false）。
##
## **不阻塞、不返回节点**——调用方只负责"这里该有个特效"，
## 生命周期完全由池管理。这样调用点不必持有引用、也不会漏 free。
func play(kind: String, world_pos: Vector3, color: Color = Color(1, 0.8, 0.3)) -> bool:
	var preset: Dictionary = PRESETS.get(kind, PRESETS["hit"])
	var em := _acquire(kind, color, preset)
	if em == null:
		return false
	em.global_position = world_pos
	# one_shot 的发射器：restart() 重新从头播一次
	em.restart()
	em.emitting = true
	_play_count += 1
	# 到期归还：**必须有兜底计时器**——`finished` 信号在粒子被
	# 提前顶掉/节点被暂停时不保证触发，只靠它会让发射器永久卡在活跃态。
	_schedule_release(kind, em, float(preset.get("lifetime", 0.5)) + 0.15)
	return true


## 取一个可用发射器（池空则新建；已达上限则顶掉最旧的）
func _acquire(kind: String, color: Color, preset: Dictionary) -> GPUParticles3D:
	if not _free.has(kind):
		_free[kind] = []
		_all[kind] = []
		_live[kind] = []
	var free_list: Array = _free[kind]
	if not free_list.is_empty():
		var em: GPUParticles3D = free_list.pop_back()
		em.emitting = false
		_apply_material(em, kind, color, preset)
		_live[kind].append(em)
		return em
	# 池空：未达上限就新建
	if _all[kind].size() < POOL_PER_KIND:
		var em := _make_emitter(kind, color, preset)
		_all[kind].append(em)
		_live[kind].append(em)
		add_child(em)
		return em
	# 已达上限：顶掉最旧的那个（复用它的节点，不新建）
	var live_list: Array = _live[kind]
	if live_list.is_empty():
		return null
	var oldest: GPUParticles3D = live_list.pop_front()
	oldest.emitting = false
	_apply_material(oldest, kind, color, preset)
	live_list.append(oldest)
	return oldest


## 到期归还（延迟 lifetime 后把发射器放回空闲池）
func _schedule_release(kind: String, em: GPUParticles3D, delay: float) -> void:
	var t := get_tree().create_timer(delay, true, false, true)
	t.timeout.connect(func(): _release(kind, em))


func _release(kind: String, em: GPUParticles3D) -> void:
	if em == null or not is_instance_valid(em):
		return
	em.emitting = false
	# 显式确保容器存在，而不是 `get(k, [])` 拿临时数组——
	# 那种写法在 kind 首次归还时会 append 进一个随即丢弃的临时数组，
	# 表现为"归还了但池里没有"。
	if not _live.has(kind):
		_live[kind] = []
	if not _free.has(kind):
		_free[kind] = []
	(_live[kind] as Array).erase(em)
	var free_list: Array = _free[kind]
	if not free_list.has(em):
		free_list.append(em)


## 建一个发射器（只在此 kind 首次需要时调用）
func _make_emitter(kind: String, color: Color, preset: Dictionary) -> GPUParticles3D:
	var em := GPUParticles3D.new()
	em.name = "FX_%s" % kind
	em.amount = int(preset.get("amount", 8))
	em.lifetime = float(preset.get("lifetime", 0.5))
	em.one_shot = true
	em.explosiveness = 1.0        # 一次性爆发（不是持续喷射）
	em.local_coords = false       # 粒子留在世界里，不跟着发射器走
	em.emitting = false
	# 粒子视觉：小方块（与项目像素风一致）
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * float(preset.get("size", 0.15))
	em.draw_pass_1 = mesh
	_apply_material(em, kind, color, preset)
	return em


## 应用/刷新粒子材质（按 kind+颜色 缓存，避免每次新建）
func _apply_material(em: GPUParticles3D, kind: String, color: Color, preset: Dictionary) -> void:
	var key := "%s_%.2f_%.2f_%.2f" % [kind, color.r, color.g, color.b]
	if not _mat_cache.has(key):
		var pm := ParticleProcessMaterial.new()
		var sp: Vector2 = preset.get("speed", Vector2(2.0, 5.0))
		pm.direction = Vector3(0, 1, 0)
		pm.spread = float(preset.get("spread", 60.0))
		pm.initial_velocity_min = sp.x
		pm.initial_velocity_max = sp.y
		pm.gravity = preset.get("gravity", Vector3(0, -6.0, 0))
		# 颜色渐变：从本色淡出到透明（避免粒子"啪"地消失）
		pm.color = color
		var ramp := Gradient.new()
		ramp.set_color(0, Color(color.r, color.g, color.b, 1.0))
		ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
		var tex := GradientTexture1D.new()
		tex.gradient = ramp
		pm.color_ramp = tex
		pm.scale_min = 0.7
		pm.scale_max = 1.3
		_mat_cache[key] = pm
	em.process_material = _mat_cache[key]


# ============================================================
# 测试 / 调试接口
# ============================================================

## 累计播放次数
func play_count() -> int:
	return _play_count


## 某类型的池状态 {total, free, live}
func pool_state(kind: String) -> Dictionary:
	return {
		"total": (_all.get(kind, []) as Array).size(),
		"free": (_free.get(kind, []) as Array).size(),
		"live": (_live.get(kind, []) as Array).size(),
	}


## 全部类型的发射器总数（验证"不无限增长"）
func total_emitters() -> int:
	var n := 0
	for kind in _all:
		n += (_all[kind] as Array).size()
	return n
