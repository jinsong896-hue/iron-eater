class_name EnemyVisuals
extends Node
## 敌人的视觉表现组件 —— 模型 / 精英光环 / 词缀标签 / 血条 / 受击闪红。
##
## ## 为什么独立成组件
##
## 这些函数是**纯表现**：只读敌人状态（血量/行为类型/词缀/体型），
## 产出场景节点与材质。它们不参与任何战斗判定，却是 enemy_base 里
## 一大块（约 190 行）。抽出来后"改视觉"与"改战斗 AI"不再互相牵连。
##
## ## 血条的三个陷阱（都写在方法注释里，别改回去）
##
## 1. **收缩与左对齐一律在 mesh 顶点数据里做**（`size` + `center_offset`），
##    不用节点 scale / position —— billboard 渲染忽略节点 scale（实测改了
##    屏幕像素宽纹丝不动），节点 position 在俯视透视下投影成斜向位移
##    （表现为「血条往上跑」）。
## 2. **`center_offset.x` 必须随 `size.x` 同步更新**，否则左缘不钉死，
##    表现为「60% 血量看起来只有 30%」（血量越低偏移越明显）。
## 3. **填充必须显式指定更高 `render_priority`**：背景与填充是同一位置的
##    两个半透明 quad，俯视下 z=0.01 的深度差不足以裁决先后，Godot 会退回
##    按场景树顺序排——而该顺序在 mesh 重建（改 size）后会翻转，表现为
##    「受击后整条血条变暗且不再复原」。
##
## ## 字段归属
##
## 视觉字段（`_model` / `_hp_bar` / `_elite_ring` / `_affix_label` /
## `_flash_timer` / `_visual_color`）**留在 EnemyBase 上**——测试直接读它们
## （test_gameplay_fixes 断言 `e._hp_bar_fill.mesh.size.x` 与
## `center_offset.x`）。故本组件按鸭子类型写 `owner_enemy.xxx`，
## 字段归属不变、player 与测试零改动。

## 敌人本体（构造时注入）
var owner_enemy: Node3D = null

## 血条宽度（与 EnemyBase.BAR_WIDTH 同值；这里另存一份避免跨类常量引用）
const BAR_WIDTH := 1.1
## 血条高度
const BAR_HEIGHT := 0.14
## 受击闪红时长（秒）
const HIT_FLASH_DURATION := 0.18


## 装配：注入敌人节点
func setup(enemy: Node3D) -> void:
	owner_enemy = enemy


## 建模型 / 血条 / 精英标识（原 _create_visual）。
##
## **物理碰撞仍归 EnemyBase**：`_create_collision()` 是物理层职责，
## 这里只回调它一次，不把碰撞逻辑搬进来。
func build() -> void:
	owner_enemy._create_collision()
	var model := MeshInstance3D.new()
	model.name = "Model"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4 * owner_enemy.body_scale
	capsule.height = 1.8 * owner_enemy.body_scale
	model.mesh = capsule
	model.position = Vector3(0, 0.9 * owner_enemy.body_scale, 0)
	var color := Color(0.5, 0.3, 0.7)  # 紫色特殊（默认）
	match owner_enemy.behavior:
		EnemyBase.AIBehavior.MELEE_CHASE:
			color = Color(0.8, 0.2, 0.2)  # 红色近战
		EnemyBase.AIBehavior.RANGED_KITE:
			color = Color(0.2, 0.2, 0.8)  # 蓝色远程
		EnemyBase.AIBehavior.SENTRY:
			color = Color(0.2, 0.6, 0.6)  # 青色哨兵
		EnemyBase.AIBehavior.RUSHER:
			color = Color(0.85, 0.5, 0.1)  # 橙色突进
	# 卡通材质 + 反壳描边（毒怪带绿色自发光提示）
	var mat := ToonMaterial.create(color, null, Color.WHITE,
		Color(0.2, 0.8, 0.2) if owner_enemy.death_poison else Color.BLACK,
		0.4 if owner_enemy.death_poison else 0.0)
	model.material_override = mat

	owner_enemy.add_child(model)
	owner_enemy._model = model
	owner_enemy._visual_color = color  # 记录本色，闪红后还原用
	create_health_bar()
	create_elite_marker()


## 精英标识（策划 7.2：词缀的用意是「威胁特征」，玩家识别不出来就达不到设计目的）。
##
## 做法：脚下一圈金色光环（billboard 贴地，与血条同一套纯脚本图元方案）。
## **不动模型材质**——那会与受击闪红、毒怪发光等已有逻辑打架。
func create_elite_marker() -> void:
	if not owner_enemy.is_elite:
		return
	var ring := MeshInstance3D.new()
	ring.name = "EliteRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55 * owner_enemy.body_scale
	torus.outer_radius = 0.72 * owner_enemy.body_scale
	ring.mesh = torus
	# 平铺在地上（TorusMesh 默认竖立）
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	ring.position = Vector3(0, 0.05, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat

	owner_enemy.add_child(ring)
	owner_enemy._elite_ring = ring
	create_affix_label()


## 词缀名标签（策划 7.2 的「威胁特征」要让玩家看得见）。
##
## 用 `Label3D` + billboard——项目里已有先例（`damage_popup.gd`），
## 不需要自建字形图集或屏幕空间投影。
## 挂在血条上方，只对精英显示（普通怪没有词缀，第 1~2 层连精英也没有）。
func create_affix_label() -> void:
	if not owner_enemy.is_elite:
		return
	var names: Array[String] = []
	for id in owner_enemy.affixes:
		names.append(AffixDB.affix_name(str(id)))
	if names.is_empty():
		return
	var lb := Label3D.new()
	lb.name = "AffixLabel"
	lb.text = " · ".join(names)
	lb.font_size = 48
	lb.modulate = Color(1.0, 0.88, 0.45)
	lb.outline_size = 8
	lb.outline_modulate = Color.BLACK
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true          # 不被墙挡住，玩家始终看得到威胁信息
	lb.pixel_size = 0.006            # 世界单位下的字高（约 0.3 米）
	lb.position = Vector3(0, 2.75 * owner_enemy.body_scale, 0)

	owner_enemy.add_child(lb)
	owner_enemy._affix_label = lb


## 敌人头顶血条（billboard 四边形，纯脚本图元，无贴图依赖）
## 受伤后才显示；满血时隐藏，避免满屏血条
func create_health_bar() -> void:
	owner_enemy._hp_bar = Node3D.new()
	owner_enemy._hp_bar.name = "HealthBar"
	owner_enemy._hp_bar.position = Vector3(0, 2.15 * owner_enemy.body_scale, 0)

	# 底：深色背景 + 细黑边（优先级 0，排在填充之后画）
	owner_enemy._hp_bar_bg = _make_bar_quad(Vector3(BAR_WIDTH, BAR_HEIGHT, 0), Color(0.05, 0.05, 0.07, 0.9), 0)
	# 填充：红色（受击反馈里也用这个色系）；优先级 1 → 一定画在背景之上
	owner_enemy._hp_bar_fill = _make_bar_quad(Vector3(BAR_WIDTH, BAR_HEIGHT, 0), Color(0.85, 0.2, 0.2, 1.0), 1)
	# 填充略微前移，避免与底 z-fighting
	owner_enemy._hp_bar_fill.position.z = 0.01

	owner_enemy._hp_bar.add_child(owner_enemy._hp_bar_bg)
	owner_enemy._hp_bar.add_child(owner_enemy._hp_bar_fill)

	owner_enemy.add_child(owner_enemy._hp_bar)
	# 满血也显示（见 _update_health_bar 注释：懒显示是首击跳变误会的根源）
	owner_enemy._hp_bar.visible = true
	update_health_bar()


## 生成一个 billboard 四边形（始终面向相机）。
## **收缩与左对齐一律在 mesh 顶点数据里做**（size + center_offset），
## 不用节点 scale / position：
##   · 节点 scale —— billboard 渲染时被忽略（实测改了屏幕像素宽纹丝不动）
##   · 节点 position —— 世界空间偏移在俯视透视下投影成斜向位移（「血条往上跑」）
## center_offset 的取值见 _update_health_bar（必须随 size 同步更新）。
##
## priority 显式指定透明渲染顺序：背景与填充是**同一位置的两个半透明 quad**，
## 俯视相机下 z=0.01 的深度差小到不足以裁决先后，Godot 会退回按
## 场景树顺序/实例 id 排——而这个顺序在 mesh 被重建（改 size）后会翻转，
## 表现为「受击后整条血条变暗（暗色背景盖住了红色填充）」且不再复原。
## 给填充更高优先级把顺序钉死，不再依赖深度平局裁决。
func _make_bar_quad(quad_size: Vector3, col: Color, priority: int = 0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(quad_size.x, quad_size.y)
	mi.mesh = q
	var mat := MaterialLibrary.create_translucent_material(col)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true  # 不被墙体遮挡
	mat.render_priority = priority  # 显式排序，见上方注释
	mi.material_override = mat
	return mi


## 按当前血量刷新血条长度（从左向右收缩）与可见性。
##
## 两个量必须**同时**改，缺一不可：
##   size.x         = BAR_WIDTH × ratio        —— 可见长度
##   center_offset.x = (size.x - BAR_WIDTH) / 2 —— 把左缘钉死在 -BAR_WIDTH/2
##
## **左对齐公式推导**（这是曾经的核心 bug）：
##   顶点左缘 = center_offset.x - size.x / 2
##   要求左缘恒等于 -BAR_WIDTH / 2 →
##   center_offset.x = size.x / 2 - BAR_WIDTH / 2 = (size.x - BAR_WIDTH) / 2
## 满血时该值为 0（与背景条天然重合）；只设 size 不设 offset 的话，
## 填充会整体左移出背景条，玩家在暗条内只看到约一半长度——
## 表现为「60% 血量看起来只有 30%」，且血量越低偏移越明显。
##
## 满血也显示（旧版「受伤后才显示」让血条在已失血状态下凭空出现，
## 玩家看不到从 100% 掉下来的过程）。仅死亡隐藏。
func update_health_bar() -> void:
	if owner_enemy._hp_bar == null or owner_enemy._hp_bar_fill == null:
		return
	var maxv: float = maxf(owner_enemy.max_hp, 0.001)
	var ratio := clampf(owner_enemy._hp / maxv, 0.0, 1.0)
	owner_enemy._hp_bar.visible = owner_enemy._hp > 0.0
	var q := owner_enemy._hp_bar_fill.mesh as QuadMesh
	if q == null:
		return
	var w: float = maxf(BAR_WIDTH * ratio, 0.001)
	q.size = Vector2(w, BAR_HEIGHT)
	q.center_offset = Vector3((w - BAR_WIDTH) * 0.5, 0.0, 0.0)


## 每帧推进闪红衰减（由 EnemyBase._physics_process 转发）。
##
## 衰减与"是否真的在闪"是两件事：计时器归零后仍要调一次 `_update_flash`
## 把颜色还原成本色，否则模型会永远停在红色。
func tick_flash(delta: float) -> void:
	if owner_enemy._flash_timer <= 0.0:
		return
	owner_enemy._flash_timer = maxf(owner_enemy._flash_timer - delta, 0.0)
	_update_flash()


## 触发一次受击闪红
func flash_hit() -> void:
	if owner_enemy._model == null:
		return
	owner_enemy._flash_timer = HIT_FLASH_DURATION
	_update_flash()


func _update_flash() -> void:
	if owner_enemy._model == null or owner_enemy._model.material_override == null:
		return
	var mat := owner_enemy._model.material_override as ShaderMaterial
	if mat == null:
		return
	if owner_enemy._flash_timer <= 0.0:
		ToonMaterial.set_color(mat, owner_enemy._visual_color)
		return
	# 前 40% 全红，剩余时间线性退回本色
	var t: float = float(owner_enemy._flash_timer) / HIT_FLASH_DURATION
	var blend := clampf(t / 0.4, 0.0, 1.0)
	ToonMaterial.set_color(mat, Color(1.0, 0.15, 0.15).lerp(owner_enemy._visual_color, 1.0 - blend))

