class_name FusionRules
extends RefCounted
## 融合规则

const MAX_FUSION := 25
const BASE_COST := 50


## 当前等级下是否允许融合
static func can_fuse(current_count: int) -> bool:
	return current_count < MAX_FUSION


## 融合后等级
static func next_fusion_count(current_count: int) -> int:
	return mini(current_count + 1, MAX_FUSION)


## 攻击加成
static func attack_bonus_at(count: int) -> float:
	if count <= 0:
		return 0.0
	if count < 5:
		return (count / 5.0) * 0.15
	if count < 10:
		return 0.15 + ((count - 5) / 5.0) * 0.15
	if count < 15:
		return 0.30 + ((count - 10) / 5.0) * 0.20
	if count < 20:
		return 0.50 + ((count - 15) / 5.0) * 0.25
	if count < 25:
		return 0.75 + ((count - 20) / 5.0) * 0.25
	return 1.0


## 融合金币消耗
static func fusion_cost(main: EquipmentInstance, material: EquipmentInstance, wallet: int = 0) -> int:
	if main == null or material == null:
		return 0
	var base := int(BASE_COST * (1.0 + main.fusion_count * 0.3))
	return base


## 品质阶段
static func tier_name(count: int) -> String:
	if count < 3:
		return "粗糙"
	elif count < 7:
		return "完整"
	elif count < 13:
		return "纯净"
	elif count < 21:
		return "不朽"
	return "神话"
