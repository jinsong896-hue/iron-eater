class_name DestroyableProp
extends StaticBody3D
## 可受击的场上物件基类 —— 通风口 / 符文熔炉 / 掩体
##
## **为什么需要它**：策划对第 3/5/8 层都要求"玩家能攻击的场上物件"
##（3 层通风口可破坏消除毒气、5 层熔炉可攻击改变状态、8 层掩体需躲），
## 而现有的 `chest.gd` / `special_prop.gd` 都是 `Node3D` + 纯展示，
## 既没有碰撞体也没有 `take_damage`，玩家根本打不到。
##
## **继承 StaticBody3D 而不是 Node3D**：投射物（Area3D）靠 `body_entered`
## 命中，没有碰撞体就永远打不中——这个坑在 `enemy_base._create_collision`
## 里刚踩过一次，不要再踩。
##
## **加入 `group("enemies")`**：玩家的攻击链路扫描的是该组
##（`player._is_valid_enemy` 的判据是 `is Node3D and has_method("take_damage")`），
## 进组即可被普攻/技能命中，无需改玩家代码。
## 已核实**不会干扰房间清空判定**——那里走的是 `RoomController._living_enemies`
##（`Array[EnemyBase]`），与敌人组无关。

## 被摧毁时发出（携带自身，供调用方做后续处理，如清除对应毒气区）
signal destroyed(prop: DestroyableProp)

## 物件类型："vent"（通风口）/ "furnace"（符文熔炉）/ "cover"（掩体）
var prop_kind := ""
## 当前/最大生命
var hp := 100.0
var max_hp := 100.0
## 不可摧毁（掩体用：只挡伤害，不该被打掉）
var indestructible := false

var _collision: CollisionShape3D = null
var _flash_timer := 0.0
var _materials: Array[StandardMaterial3D] = []

## 受击闪红时长（与敌人同节奏）
const HIT_FLASH_DURATION := 0.12


func _ready() -> void:
	add_to_group("enemies")
	_build_collision()
	_build_visual()


## 碰撞体：尺寸随子类覆写 `collision_size()` 变化
func _build_collision() -> void:
	if _collision != null:
		return
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	var box := BoxShape3D.new()
	box.size = collision_size()
	_collision.shape = box
	_collision.position = Vector3(0, box.size.y * 0.5, 0)
	add_child(_collision)
	# 占第 2 层（与敌人同层），mask 关掉——物件是静止障碍，
	# 不需要主动检测任何东西；投射物/玩家攻击靠各自的 mask 命中它。
	collision_layer = 2
	collision_mask = 0


## 子类覆写：碰撞盒尺寸（默认按 1 米立方）
func collision_size() -> Vector3:
	return Vector3(1.0, 1.0, 1.0)


## 子类覆写：构建视觉
func _build_visual() -> void:
	pass


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		_apply_flash()


## 受击。签名与 EnemyBase.take_damage 一致，这样玩家的命中链路无需分支。
func take_damage(amount: float, _crit: bool = false, _push: Vector3 = Vector3.ZERO) -> void:
	if indestructible:
		# 不可摧毁的物件仍给受击反馈，让玩家知道"打到了但打不坏"
		_flash_timer = HIT_FLASH_DURATION
		return
	hp -= maxf(amount, 0.0)
	_flash_timer = HIT_FLASH_DURATION
	if hp <= 0.0:
		_die()


## 是否还活着（供调用方判断，与敌人同一套语义）
func is_alive() -> bool:
	return hp > 0.0


## 血量比例（0~1）
func hp_ratio() -> float:
	return clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)


func _die() -> void:
	hp = 0.0
	destroyed.emit(self)
	# 视觉：下沉 + 淡出，然后销毁。用 tween 而非立即 free，
	# 让玩家看清"我打掉了它"。
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position", position + Vector3(0, -0.6, 0), 0.25)
	tw.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.25)
	tw.chain().tween_callback(queue_free)


## 受击闪红：把材质染红再还原。
## 与敌人同理——这里没有贴图，直接改 albedo_color 是安全的。
func _apply_flash() -> void:
	var t := _flash_timer / HIT_FLASH_DURATION
	var blend := clampf(t, 0.0, 1.0)
	for m in _materials:
		if m == null:
			continue
		m.albedo_color = m.albedo_color.lerp(Color(1.0, 0.35, 0.35), blend * 0.8)


# ============================================================
# 视觉构件（与 special_prop.gd 同款脚本画图元）
# ============================================================

func _add_box(pos: Vector3, size: Vector3, color: Color, emission: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	node.material_override = _make_material(color, emission)
	add_child(node)
	return node


func _add_cylinder(pos: Vector3, radius: float, height: float,
		color: Color, emission: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	node.mesh = mesh
	node.position = pos
	node.material_override = _make_material(color, emission)
	add_child(node)
	return node


func _add_sphere(pos: Vector3, radius: float, color: Color, emission: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	node.mesh = mesh
	node.position = pos
	node.material_override = _make_material(color, emission)
	add_child(node)
	return node


func _add_light(color: Color, energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 5.0
	light.position = Vector3(0, 1.0, 0)
	add_child(light)
	return light


## 建材质并**登记到 _materials**，供闪红时统一染色。
## 用每实例独占的材质（不复用静态材质），否则多只物件会互相串色。
func _make_material(color: Color, emission: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	_materials.append(mat)
	return mat
