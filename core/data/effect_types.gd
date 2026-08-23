class_name DamageEffect
extends EffectData
## 伤害效果

@export var multiplier: float = 1.0
@export var element: String = "physical"

func execute(target: Node) -> void:
	if target.has_method("take_damage"):
		target.take_damage(multiplier * 10.0, false)
		print("[Effect] Damage x%.1f %s" % [multiplier, element])

func description() -> String:
	return "伤害 x%.1f (%s)" % [multiplier, element]
