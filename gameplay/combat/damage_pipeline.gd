class_name DamagePipeline
extends RefCounted
## 伤害管线 —— HD-2D 重构版
## 物理伤害 = 攻击力 × 技能倍率 × (1 + 增伤%) × (1 - 护甲减伤%)
## 护甲减伤% = 防御 / (防御 + 100)

## 物理伤害计算
static func physical(attacker_atk: float, skill_multiplier: float, bonus: float, target_def: float) -> Dictionary:
	var raw := attacker_atk * skill_multiplier * (1.0 + bonus)
	var reduction := target_def / (target_def + 100.0)
	var final_damage := maxf(raw * (1.0 - reduction), 1.0)
	return {
		"damage": final_damage,
		"raw": raw,
		"reduction": reduction,
	}


## 暴击伤害 = 物理伤害 × (1.5 + 暴击伤害加成%)
static func with_crit(damage: float, crit: bool, crit_damage_bonus: float) -> float:
	if not crit:
		return damage
	return damage * (1.5 + crit_damage_bonus)


## 元素伤害计算（预留）
static func elemental(base_damage: float, element: String, target_resistance: float) -> Dictionary:
	var resistance_mult := 1.0 - target_resistance
	var final_damage := maxf(base_damage * resistance_mult, 0.0)
	return {
		"damage": final_damage,
		"element": element,
		"resistance": target_resistance,
	}


## 受击反馈（伤害弹出 + 消息）
## 注意：EventBus 是 Autoload，仅在完整游戏运行时可用
static func emit_damage_result(target: Node3D, amount: float, kind: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var eb := tree.root.get_node_or_null("EventBus")
	if eb:
		eb.damage_popup.emit(target.global_position, amount, kind)
		eb.damage_dealt.emit(null, target, amount, kind, kind == "crit")