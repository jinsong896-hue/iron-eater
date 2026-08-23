class_name BalanceCalculator
extends RefCounted
## 数值平衡计算器 —— 不运行游戏，模拟战斗结果
## 文档：ai/框架相关.md Balance Studio

## 计算角色最终属性
static func calc_final_stats(base: StatsData, modifiers: Array[ModifierData]) -> Dictionary:
	var result := {
		"hp": base.hp, "atk": base.atk, "defense": base.defense,
		"spd": base.spd, "aspd": base.aspd, "rng": base.rng,
		"crt": base.crt, "crd": base.crd,
	}
	for mod in modifiers:
		if mod.target_stat in result:
			result[mod.target_stat] = mod.apply(result[mod.target_stat])
	return result


## 计算DPS
static func calc_dps(atk: float, aspd: float, crt: float, crd: float, defense: float, target_def: float) -> float:
	return CombatCore.calc_dps(atk, aspd, crt, crd, target_def)


## 计算生存时间（秒）
static func calc_survival(hp: float, defense: float, enemy_dps: float) -> float:
	var mitigation := defense / (defense + 100.0)
	var effective_dps := enemy_dps * (1.0 - mitigation)
	return hp / maxf(effective_dps, 1.0)


## 模拟Boss击杀时间
static func calc_ttk(player_dps: float, boss_hp: float, boss_def: float) -> float:
	return CombatCore.calc_ttk(player_dps, boss_hp, boss_def)


## 综合模拟报告
static func simulate(character: CharacterData, weapon: WeaponData, form_idx: int, floor: int) -> Dictionary:
	var base := character.base_stats if character.base_stats else StatsData.new()
	var all_mods: Array[ModifierData] = []

	# 形态加成
	if form_idx >= 0 and form_idx < character.forms.size():
		all_mods.append_array(character.forms[form_idx].modifiers)

	# 武器属性
	if weapon:
		var atk_mod := ModifierData.new()
		atk_mod.target_stat = "atk"
		atk_mod.operation = ModifierData.Operation.ADD
		atk_mod.value = weapon.current_atk() - weapon.base_atk
		all_mods.append(atk_mod)
		all_mods.append_array(weapon.modifiers)

	# 楼层倍率
	var floor_mult := 1.0 + (floor - 1) * 0.15

	var final := calc_final_stats(base, all_mods)
	var enemy_hp := 100.0 * floor_mult * (1.0 + (floor - 1) * 0.5)
	var enemy_atk := 15.0 * floor_mult
	var enemy_def := 5.0 * floor_mult

	var dps := calc_dps(final["atk"], final["aspd"], final["crt"], final["crd"], final["defense"], enemy_def)
	var survival := calc_survival(final["hp"], final["defense"], enemy_atk)
	var ttk := calc_ttk(dps, enemy_hp, enemy_def)

	return {
		"final_stats": final,
		"dps": dps,
		"survival_seconds": survival,
		"ttk_seconds": ttk,
		"enemy_hp": enemy_hp,
		"enemy_atk": enemy_atk,
		"floor": floor,
	}
