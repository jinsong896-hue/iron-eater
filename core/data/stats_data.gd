class_name StatsData
extends Resource
## 角色属性数据 —— 11项基础属性，对应名词分册

@export var hp: float = 100.0
@export var atk: float = 10.0
@export var defense: float = 5.0
@export var spd: float = 100.0
@export var aspd: float = 1.0
@export var rng: float = 1.5
@export var ap: float = 0.0
@export var mp: float = 0.0
@export var cdr: float = 0.0
@export var crt: float = 0.05
@export var crd: float = 0.5


func clone() -> StatsData:
	var s := StatsData.new()
	s.hp = hp; s.atk = atk; s.defense = defense
	s.spd = spd; s.aspd = aspd; s.rng = rng
	s.ap = ap; s.mp = mp; s.cdr = cdr
	s.crt = crt; s.crd = crd
	return s


func apply_modifiers(modifiers: Array) -> StatsData:
	var result := clone()
	for mod in modifiers:
		if mod is ModifierData:
			match mod.target_stat:
				"hp": result.hp = mod.apply(result.hp)
				"atk": result.atk = mod.apply(result.atk)
				"defense": result.defense = mod.apply(result.defense)
				"spd": result.spd = mod.apply(result.spd)
				"aspd": result.aspd = mod.apply(result.aspd)
				"rng": result.rng = mod.apply(result.rng)
				"crt": result.crt = mod.apply(result.crt)
				"crd": result.crd = mod.apply(result.crd)
	return result
