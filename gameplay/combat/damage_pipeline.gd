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


## **附加元素伤害**（装备参考2：「攻击附带 N% 火焰伤害」）。
##
## ## 与 `elemental_attack` 的区别
##
## `elemental_attack` 把**整段伤害**按元素规则结算（火/冰/雷/毒无视护甲）；
## 本函数算的是**额外多出的一段**——本体伤害照常结算，这一段另算后加上去。
##
## 规格原文的语义就是「附带」：烈焰法杖打人时，物理本体照打，
## **额外**再造成 50% 法强的火焰伤害。
##
## ## 参数
##   base    —— 计算基准（武器攻击力或法强）
##   ratio   —— 附带比例（0.5 = 50%）
##   element —— 元素 key（fire/frost/static/earth/wind/poison）
##   target_resist —— 目标对该元素的抗性（0~1）
##
## 返回附加伤害值（>= 0）。
static func bonus_element_damage(base: float, ratio: float,
		element: String, target_resist: float = 0.0) -> float:
	if base <= 0.0 or ratio <= 0.0:
		return 0.0
	if element.is_empty():
		return 0.0
	# 元素抗性减免（与 elemental 同口径：1 - 抗性）
	var r := clampf(target_resist, 0.0, 0.95)
	return maxf(base * ratio * (1.0 - r), 0.0)
