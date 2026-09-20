class_name DamagePipeline
extends RefCounted
## 伤害管线 —— HD-2D 重构版
## 物理伤害 = 攻击力 × 技能倍率 × (1 + 增伤%) × (1 - 护甲减伤%)
## 护甲减伤% = 防御 / (防御 + 100)

## 物理伤害计算
## bonus  = 增伤（连击/融合等）
## vuln   = 目标易伤（词条累加，如毒蚀每层 +1%）
## taken_down = 目标受到伤害降低（护盾/防御型词条）
static func physical(attacker_atk: float, skill_multiplier: float, bonus: float, target_def: float, vuln: float = 0.0, taken_down: float = 0.0) -> Dictionary:
	var raw := attacker_atk * skill_multiplier * (1.0 + bonus)
	var reduction := target_def / (target_def + 100.0)
	var final_damage := raw * (1.0 - reduction) * (1.0 + vuln) * (1.0 - clampf(taken_down, 0.0, 0.9))
	final_damage = maxf(final_damage, 1.0)
	return {
		"damage": final_damage,
		"raw": raw,
		"reduction": reduction,
		"vuln": vuln,
		"taken_down": taken_down,
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


## 带元素的攻击结算（分册 7.1 伤害类型总览）
##
## 分册规则：
##   火/冰/雷/毒 = **法术伤害**：无视护甲、不可暴击
##   土/风       = **各占 50%**：物理半受护甲影响且可暴击，法术半无视护甲
##   无元素      = 纯物理
##
## 注意 target_def 传防御值（不是减伤率），内部按 防御/(防御+100) 折算。
## 返回 {damage, phys, spell, reduction, is_spell_only}
static func elemental_attack(atk: float, skill_multiplier: float, bonus: float,
		target_def: float, element: int, resistance: float = 0.0,
		vuln: float = 0.0, taken_down: float = 0.0) -> Dictionary:
	if element < 0:
		var p := physical(atk, skill_multiplier, bonus, target_def, vuln, taken_down)
		p["phys"] = p["damage"]
		p["spell"] = 0.0
		p["is_spell_only"] = false
		return p

	# 用 element_defs 的 damage_type 元数据判定，不硬编码元素名——
	# 后续新增/调整元素时只改数据表，这里自动跟随
	var dtype := str(ElementDefs.get_element(element).get("damage_type", "magic"))

	var raw := atk * skill_multiplier * (1.0 + bonus)
	var reduction := target_def / (target_def + 100.0)
	var common := (1.0 + vuln) * (1.0 - clampf(taken_down, 0.0, 0.9)) * (1.0 - resistance)

	var phys_part := 0.0
	var spell_part := 0.0
	match dtype:
		"physical":
			phys_part = raw * (1.0 - reduction) * common
		"mixed":
			# 土/风：物理法术各半，只有物理半吃护甲
			phys_part = raw * 0.5 * (1.0 - reduction) * common
			spell_part = raw * 0.5 * common
		_:
			# 火/冰/雷/毒：法术伤害，全然无视护甲
			spell_part = raw * common

	var total := maxf(phys_part + spell_part, 1.0)
	return {
		"damage": total,
		"raw": raw,
		"phys": phys_part,
		"spell": spell_part,
		"reduction": reduction,
		"is_spell_only": dtype == "magic",
		"damage_type": dtype,
		"element": element,
	}
