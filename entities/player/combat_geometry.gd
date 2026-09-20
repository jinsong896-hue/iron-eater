class_name CombatGeometry
extends RefCounted
## 战斗命中几何的**纯判据**集合 —— 无副作用、无状态、可单测。
##
## ## 为什么只有"判据"而没有"结算"
##
## 命中结算（`_apply_hit` / `_apply_hit_crowd` / `_compute_basic_damage`）
## 深度依赖 Player 的十来个字段（攻击元素、连击数、形态机制、装备词条、
## 暴击判定、hitstop…）。把它们搬出来需要传十几个回调，只是把复杂度
## 从"一个大文件"换成"一张大参数表"——**纯增间接层，没有收益**。
##
## 而**判据**是纯函数：给定坐标与朝向，算出"在不在扇形里""在不在线上"。
## 这部分既可单测、又恰好是重复代码的重灾区——见下。
##
## ## 消除的重复（本次拆分的实际收益）
##
## 「这个点是否落在穿透直线上」这段判据原本写了**两遍**：
##   · `player._apply_pierce_line`（节点路径，遍历 enemies 组）
##   · `player._apply_pierce_line_at`（群体路径，走 CrowdManager 锥形查询）
## 两份的 along / 侧向偏移阈值完全一致，但分别维护——改一处必漏另一处。
## 现在两边都调 `is_on_pierce_line`，成为唯一真相源。

## 背刺判定的点积阈值：要求"确实绕到身后"，而不是"在侧面"也算。
const BACKSTAB_DOT_THRESHOLD := 0.3

## 穿透直线的半宽（策划只给了长度 2 米，宽度按"一条线"取 0.6 米）
const PIERCE_LINE_HALF_WIDTH := 0.6

## 穿透直线长度（米）
const PIERCE_LINE_LENGTH := 2.0


## 目标点是否落在以 `origin` 为顶点、`facing` 为轴的扇形内。
##
## 判据与群体路径的 `query_cone` **语义一致**（那边由核内空间哈希实现），
## 故两条路径的命中范围相同。
static func in_cone(origin: Vector3, facing: Vector3, target: Vector3,
		reach: float, half_angle: float) -> bool:
	var to_target := target - origin
	to_target.y = 0.0
	if to_target.length() > reach:
		return false
	if to_target.length_squared() < 0.000001:
		return true          # 与顶点重合：算命中（避免 normalize 出 NaN）
	var flat_facing := facing
	flat_facing.y = 0.0
	if flat_facing.length_squared() < 0.000001:
		return false
	return to_target.normalized().dot(flat_facing.normalized()) >= cos(half_angle)


## 目标点是否落在以 `origin` 为起点、`dir` 为方向的穿透直线上。
##
## **两条穿透路径共用的唯一判据**（见文件头「消除的重复」）。
## `dir` 必须是已归一化的水平向量（调用方负责归一化——归一化失败时
## 调用方已提前 return，避免这里再判一次）。
static func is_on_pierce_line(origin: Vector3, dir: Vector3, target: Vector3) -> bool:
	var to_target := target - origin
	to_target.y = 0.0
	var along := to_target.dot(dir)
	# 必须落在**前方**且不超过线长
	if along <= 0.0 or along > PIERCE_LINE_LENGTH:
		return false
	# 侧向偏移要够小才算"在这条线上"
	return (to_target - dir * along).length() <= PIERCE_LINE_HALF_WIDTH


## 攻击者是否位于目标**背后**（背刺判定）。
##
## 敌人没有 facing 字段，朝向由 `-global_transform.basis.z` 给出
##（enemy_base 在 CHASE 态 look_at 目标，故这个前向是可信的）。
## 判定用「目标→攻击者」与「目标前向」的点积：小于负阈值说明确实绕到了背后。
##
## 注意：调用方需先确认**形态确实有背刺机制**（`backstab_mult > 1.0`）——
## 那是形态数据查询，不属于几何，故不在本函数里。
static func is_behind(target_pos: Vector3, target_forward: Vector3,
		attacker_pos: Vector3) -> bool:
	var to_attacker := attacker_pos - target_pos
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.0001:
		return false
	var forward := target_forward
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return false
	return to_attacker.normalized().dot(forward.normalized()) < -BACKSTAB_DOT_THRESHOLD


## 归一化水平方向；退化（零向量）时返回 ZERO 由调用方判断。
static func flat_normalized(v: Vector3) -> Vector3:
	var f := v
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return Vector3.ZERO
	return f.normalized()
