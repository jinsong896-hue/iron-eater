class_name EnhancementRules
extends RefCounted
## 强化规则 —— HD-2D 重构版
## 装备强化的数值配置

# 每级强化加成
const BONUS_PER_LEVEL := 0.05

# 最大强化等级
const MAX_ENHANCEMENT_LEVEL := 20

# 强化消耗金币公式
const COST_BASE := 100
const COST_PER_LEVEL := 50


## 计算强化消耗
static func cost_for_level(current_level: int) -> int:
	return COST_BASE + COST_PER_LEVEL * current_level


## 是否可以继续强化
static func can_enhance(level: int) -> bool:
	return level < MAX_ENHANCEMENT_LEVEL


## 强化后的新等级
static func next_level(current: int) -> int:
	return clampi(current + 1, 0, MAX_ENHANCEMENT_LEVEL)