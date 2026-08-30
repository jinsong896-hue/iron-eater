class_name BuffEffect
extends EffectData
## 增益效果 —— 给目标添加属性修改器

@export var stat: String = "atk"
@export var add_value: float = 0.0
@export var mult_value: float = 0.0
@export var duration: float = 5.0

func execute(target: Node) -> void:
	var mod := ModifierData.new()
	mod.target_stat = stat
	if add_value != 0:
		mod.operation = ModifierData.Operation.ADD
		mod.value = add_value
	else:
		mod.operation = ModifierData.Operation.MULTIPLY
		mod.value = mult_value
	mod.duration = duration
	if target.has_method("add_modifier"):
		target.add_modifier(mod)
	print("[Effect] Buff %s: %+.1f for %.1fs" % [stat, add_value if add_value != 0 else mult_value, duration])

func description() -> String:
	var v := add_value if add_value != 0 else mult_value
	return "%s %+.1f (%.1fs)" % [stat, v, duration]
