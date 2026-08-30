class_name AttributeSystem
extends RefCounted
## 属性系统 —— HD-2D 重构版
## 11 项基础属性 + Modifier 叠加框架
## 口径：HP/ATK/DEF/SPD/ASPD/RNG/AP/MP/CDR/CRT/CRD

enum Stat { HP, ATK, DEF, SPD, ASPD, RNG, AP, MP, CDR, CRT, CRD }

const STAT_BY_NAME := {
	"hp": Stat.HP, "atk": Stat.ATK, "def": Stat.DEF, "spd": Stat.SPD, "aspd": Stat.ASPD,
	"rng": Stat.RNG, "ap": Stat.AP, "mp": Stat.MP, "cdr": Stat.CDR, "crt": Stat.CRT, "crd": Stat.CRD,
}

const STAT_NAMES := {
	Stat.HP: "生命值", Stat.ATK: "攻击力", Stat.DEF: "防御", Stat.SPD: "移动速度",
	Stat.ASPD: "攻击速度", Stat.RNG: "射程", Stat.AP: "法术强度", Stat.MP: "法力值",
	Stat.CDR: "冷却缩减", Stat.CRT: "暴击率", Stat.CRD: "暴击伤害加成",
}

const DEFAULT_BASE := {
	Stat.HP: 500.0, Stat.ATK: 35.0, Stat.DEF: 10.0, Stat.SPD: 100.0, Stat.ASPD: 1.0,
	Stat.RNG: 1.5, Stat.AP: 10.0, Stat.MP: 100.0, Stat.CDR: 0.0, Stat.CRT: 0.05, Stat.CRD: 0.5,
}

var _base := {}
var _modifiers: Array[Dictionary] = []
var max_hp := 500.0
var hp := 500.0


func _init(overrides: Dictionary = {}) -> void:
	_base = DEFAULT_BASE.duplicate()
	for k in overrides:
		_base[k] = overrides[k]
	_recalc_hp()


func set_base(stat: int, value: float) -> void:
	_base[stat] = value
	_recalc_hp()


func get_base(stat: int) -> float:
	return _base.get(stat, 0.0)


## 最终值 = 基础值 + 固定值 + 基础值 × 百分比
func get_value(stat: int) -> float:
	var flat := 0.0
	var percent := 0.0
	for m in _modifiers:
		if m.stat == stat:
			flat += m.flat
			percent += m.percent
	return _base[stat] + flat + _base[stat] * percent


func add_modifier(source: String, stat: int, flat: float = 0.0, percent: float = 0.0) -> void:
	_modifiers.append({"source": source, "stat": stat, "flat": flat, "percent": percent})
	_recalc_hp()


func remove_modifiers(source: String) -> void:
	_modifiers = _modifiers.filter(func(m: Dictionary) -> bool: return m.source != source)
	_recalc_hp()


func take_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)


func is_dead() -> bool:
	return hp <= 0.0


func _recalc_hp() -> void:
	max_hp = get_value(Stat.HP)
	if hp > max_hp:
		hp = max_hp