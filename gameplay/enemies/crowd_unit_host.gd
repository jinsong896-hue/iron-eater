class_name CrowdUnitHost
extends Node
## 群体单位的 buff 宿主 —— 让元素叠层 / 印记 / 触发词条能作用于 swarm 怪
##
## ## 为什么需要它
## `BuffHolder` 的宿主必须是一个 Node（它用 `_target.call(...)` 读写）。
## 群体单位住在 CrowdSim 的 SoA 数组里、**不是场景节点**，所以早期版本
## 群体路径整套跳过了"给敌人挂状态"的效果：元素叠层、审判印记、
## 咒焰/虚空印记、装备触发词条全部失效。
##
## ## 与敌人宿主（EnemyBase）的一致性
## 敌人也**没有 AttributeSystem**（属性系统是玩家专有），故它只提供
## `eff_atk`/`eff_ap` 两个「读」接口、不提供 `add_modifier`——
## `BuffHolder._sync_modifier` 会因此早退，与既有行为一致。
## 本类沿用同一套约定，保证"同一个词条挂到节点怪和 swarm 怪上行为相同"。
##
## ## 位置同步
## 宿主不主动跟随单位（那需要每帧回写，抵消了 CPU 零写入的收益）。
## 由 `CrowdManager` 在需要时（叠层/查询）调 `bind()` 更新坐标。

## 该宿主对应的 CrowdSim 实例 id（-1 = 未绑定）
var unit_id := -1
## 最近一次同步的世界坐标
var pos := Vector3.ZERO
## 单位的攻/法强（从 monster dict 取，供 DOT 结算）
var atk := 10.0
## 所属管理器（读实时坐标用）
var mgr: Node = null


func bind(p_id: int, p_pos: Vector3, p_atk: float, p_mgr: Node) -> void:
	unit_id = p_id
	pos = p_pos
	atk = p_atk
	mgr = p_mgr


## 实时坐标（宿主位置可能滞后于模拟核，故优先问管理器）
func world_position() -> Vector3:
	if mgr != null and is_instance_valid(mgr) and unit_id >= 0:
		if bool(mgr.call("is_alive", unit_id)):
			return mgr.call("unit_position", unit_id)
	return pos


## BuffHolder 结算 DOT 时读宿主攻击力（与 EnemyBase.eff_atk 同口径）
func eff_atk() -> float:
	return atk


## 敌人无独立法强字段，按攻击力折半近似（与 EnemyBase.eff_ap 同口径）
func eff_ap() -> float:
	return atk * 0.5


## **刻意不提供 `add_modifier`**：群体单位没有属性层，stat 型词条无处可挂。
## `BuffHolder._sync_modifier` 会因找不到该方法而早退——
## 这与敌人侧行为完全一致，是有意的，不是遗漏。
