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


## 品质阶段（策划 3.2：按**累计融合次数**分档，与装备稀有度无关）
##   1~3 次 → 粗糙 | 4~7 → 完整 | 8~12 → 纯净 | 13~20 → 不朽 | 21+ → 神话
## 注意 0 次（未融合）也归粗糙——它是"还没成长"的状态，与 1~3 同档。
static func tier_name(count: int) -> String:
	if count <= 3:
		return "粗糙"
	elif count <= 7:
		return "完整"
	elif count <= 12:
		return "纯净"
	elif count <= 20:
		return "不朽"
	return "神话"


## 品质档位序号（0=粗糙 … 4=神话），供数值表按档位取参
static func tier_index(count: int) -> int:
	if count <= 3:
		return 0
	elif count <= 7:
		return 1
	elif count <= 12:
		return 2
	elif count <= 20:
		return 3
	return 4


## 融合词条满级效果参考（策划 3.2「满级效果参考（攻击加成为例）」）。
## 下标与 tier_index 对应：粗糙 +3% / 完整 +8% / 纯净 +15% / 不朽 +25% / 神话 +40%
const TIER_AFFIX_ATTACK := [0.03, 0.08, 0.15, 0.25, 0.40]


## 按融合次数取该档位的词条攻击加成
static func tier_affix_attack(count: int) -> float:
	return float(TIER_AFFIX_ATTACK[tier_index(count)])
