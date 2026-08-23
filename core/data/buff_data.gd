class_name BuffData
extends Resource
## Buff/Debuff数据 —— 临时属性修改 + 持续时间
## 文档：ai/框架相关.md Phase 2 Buff系统

@export var buff_id: String = ""
@export var buff_name: String = ""
@export var is_debuff: bool = false
@export var duration: float = 5.0
@export var tick_interval: float = 0.0
@export var max_stacks: int = 1
@export var modifiers: Array[ModifierData] = []
@export var vfx_path: String = ""
@export var icon_path: String = ""


func description() -> String:
	var prefix := "Debuff" if is_debuff else "Buff"
	var parts: PackedStringArray = []
	for m in modifiers:
		parts.append(m.description())
	return "%s[%s] %.1fs %s" % [prefix, buff_name, duration, ", ".join(parts)]
