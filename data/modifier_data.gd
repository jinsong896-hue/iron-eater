class_name ModifierData
extends Resource
## 通用属性修改器 —— 装备/吞噬/融合/形态/Buff 统一使用
## 文档：ai/框架相关.md 四、Modifier系统

enum Operation { ADD, MULTIPLY, OVERRIDE }

@export var target_stat: String = "atk"
@export var operation: Operation = Operation.ADD
@export var value: float = 0.0
@export var duration: float = 0.0  ## 0=永久


func apply(base: float) -> float:
	match operation:
		Operation.ADD:
			return base + value
		Operation.MULTIPLY:
			return base * (1.0 + value)
		Operation.OVERRIDE:
			return value
	return base


func description() -> String:
	var op_str := ""
	match operation:
		Operation.ADD: op_str = "+"
		Operation.MULTIPLY: op_str = "×"
		Operation.OVERRIDE: op_str = "="
	return "%s %s%.1f" % [target_stat, op_str, value]
