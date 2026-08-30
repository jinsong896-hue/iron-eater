class_name CombatCore
extends RefCounted
## 战斗核心 —— 游戏和数值模拟器共用
## 文档：ai/框架相关.md Balance Studio 二

## 基础伤害：ATK × 倍率 × (1 - 护甲减伤)，保底 10%
static func calc_damage(atk: float, mult: float, defense: float) -> float:
	var raw := atk * mult
	var mitigation := defense / (defense + 100.0)
	return maxf(raw * (1.0 - mitigation), raw * 0.1)


## 暴击掷骰
static func calc_crit_damage(damage: float, crt: float, crd: float) -> float:
	if randf() < crt:
		return damage * (1.0 + crd)
	return damage


## DPS 期望值
static func calc_dps(atk: float, aspd: float, crt: float, crd: float, target_def: float) -> float:
	var hits := 1.0 / maxf(aspd, 0.1)
	var base := calc_damage(atk, 1.0, target_def)
	var avg := base * (1.0 + crt * crd)
	return avg * hits


## 击杀时间（秒）
static func calc_ttk(dps: float, hp: float, defense: float) -> float:
	var mit := defense / (defense + 100.0)
	return hp / maxf(dps * (1.0 - mit), 1.0)


## 应用 Modifier 到属性数据
static func apply_modifiers(base: StatsData, mods: Array[ModifierData]) -> StatsData:
	return base.apply_modifiers(mods)
