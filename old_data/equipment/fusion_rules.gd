class_name FusionRules
extends RefCounted
## 融合规则 —— HD-2D 重构版
## 吞噬融合的数值配置

# 融合等级对应的攻击加成
const FUSION_BONUS_TABLE := {
	0: 0.0,
	1: 0.15,
	2: 0.30,
	3: 0.50,
	4: 0.75,
	5: 1.00,
}

# 融合等级名称
const TIER_NAMES := {
	0: "未融合",
	1: "融合 I",
	2: "融合 II",
	3: "融合 III",
	4: "融合 IV",
	5: "融合 MAX",
}

# 最大融合等级
const MAX_FUSION_COUNT := 5


## 获取指定融合等级的攻击加成
static func attack_bonus_at(count: int) -> float:
	return FUSION_BONUS_TABLE.get(clampi(count, 0, MAX_FUSION_COUNT), 0.0)


## 获取融合等级名称
static func tier_name(count: int) -> String:
	return TIER_NAMES.get(clampi(count, 0, MAX_FUSION_COUNT), "未知")


## 是否可以继续融合
static func can_fuse(count: int) -> bool:
	return count < MAX_FUSION_COUNT


## 融合后的新等级
static func next_fusion_count(current: int) -> int:
	return clampi(current + 1, 0, MAX_FUSION_COUNT)