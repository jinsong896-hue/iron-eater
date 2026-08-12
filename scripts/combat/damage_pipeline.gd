class_name DamagePipeline
extends RefCounted
## 伤害管线（《名词设计分册》2.1/2.3）
## 物理伤害 = 攻击力 × 技能倍率 × (1 + 增伤%) × (1 - 护甲减伤%)；护甲减伤% = 防御 / (防御 + 100)

static func physical(attacker_atk: float, skill_multiplier: float, bonus: float, target_def: float) -> Dictionary:
	var raw := attacker_atk * skill_multiplier * (1.0 + bonus)
	var reduction := target_def / (target_def + 100.0)
	var final_damage := maxf(raw * (1.0 - reduction), 1.0)
	return {
		"damage": final_damage,
		"raw": raw,
		"reduction": reduction,
	}


## 暴击伤害 = 物理伤害 × (1.5 + 暴击伤害加成%)（名词分册 2.3）
static func with_crit(damage: float, crit: bool, crit_damage_bonus: float) -> float:
	if not crit:
		return damage
	return damage * (1.5 + crit_damage_bonus)
