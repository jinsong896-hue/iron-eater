class_name EnhancementRules
extends RefCounted
## 强化规则（用户确认版）：只提升基础词条，固定百分比，无失败

const BONUS_PER_LEVEL := 0.05


static func cost(current_level: int) -> int:
	return int(round(100.0 * (1.0 + current_level * 0.5)))


static func enhanced_value(base: float, current_level: int) -> float:
	return base * (1.0 + current_level * BONUS_PER_LEVEL)
