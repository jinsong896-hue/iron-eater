class_name FusionRules
extends RefCounted
## 融合规则：消耗公式、词条品质、校验状态
## 消耗金币 = 副装备基础消耗 × (1 + 主装备已融合次数 × 0.3) × 稀有度系数

enum FuseStatus {
	OK, NO_MAIN, NO_MATERIAL, SAME_ITEM, MAIN_NOT_OWNED, MAT_NOT_IN_BAG,
	MAT_LOCKED, WRONG_SLOT, NO_FUSION_AFFIX, NOT_ENOUGH_GOLD,
}

const BASE_COST := {
	EquipmentDefs.Rarity.WHITE: 50.0, EquipmentDefs.Rarity.GREEN: 150.0,
	EquipmentDefs.Rarity.BLUE: 400.0, EquipmentDefs.Rarity.PURPLE: 1000.0,
	EquipmentDefs.Rarity.ORANGE: 2500.0, EquipmentDefs.Rarity.RED: 6000.0,
}

const RARITY_MULT := {
	EquipmentDefs.Rarity.WHITE: 1.0, EquipmentDefs.Rarity.GREEN: 1.8,
	EquipmentDefs.Rarity.BLUE: 3.2, EquipmentDefs.Rarity.PURPLE: 5.5,
	EquipmentDefs.Rarity.ORANGE: 9.0, EquipmentDefs.Rarity.RED: 15.0,
}

## 融合攻击成长节点（武器分册）
const FUSION_GROWTH := {
	0: 0.0, 5: 0.15, 10: 0.30, 15: 0.50, 20: 0.75, 25: 1.00,
}

const TIERS := [
	{"min": 0, "name": "无"},
	{"min": 1, "name": "粗糙"},
	{"min": 4, "name": "完整"},
	{"min": 8, "name": "纯净"},
	{"min": 13, "name": "不朽"},
	{"min": 21, "name": "神话"},
]

const TIER_EFFECT := {
	"粗糙": 0.03, "完整": 0.08, "纯净": 0.15, "不朽": 0.25, "神话": 0.40,
}


static func cost(main_fusion_count: int, material_rarity: int) -> int:
	var base: float = BASE_COST.get(material_rarity, 50.0)
	var mult: float = RARITY_MULT.get(material_rarity, 1.0)
	return int(round(base * (1.0 + main_fusion_count * 0.3) * mult))


static func attack_bonus_at(fusion_count: int) -> float:
	var best := 0.0
	for count in FUSION_GROWTH:
		if fusion_count >= count:
			best = FUSION_GROWTH[count]
	return best


static func tier_name(fusion_count: int) -> String:
	var name := TIERS[0].name
	for t in TIERS:
		if fusion_count >= t.min:
			name = t.name
	return name


static func tier_effect(tier: String) -> float:
	return TIER_EFFECT.get(tier, 0.0)


## 返回 {status, reason, cost}
static func validate(
	main_item: EquipmentInstance, material: EquipmentInstance,
	gold: int, main_owned: bool, material_in_bag: bool
) -> Dictionary:
	if main_item == null:
		return {"status": FuseStatus.NO_MAIN, "reason": "请选择主装备", "cost": 0}
	if material == null:
		return {"status": FuseStatus.NO_MATERIAL, "reason": "请选择材料装备", "cost": 0}
	if main_item == material:
		return {"status": FuseStatus.SAME_ITEM, "reason": "主装备与材料不能是同一件", "cost": 0}
	if not main_owned:
		return {"status": FuseStatus.MAIN_NOT_OWNED, "reason": "主装备不在拥有列表", "cost": 0}
	if not material_in_bag:
		return {"status": FuseStatus.MAT_NOT_IN_BAG, "reason": "材料装备必须来自背包", "cost": 0}
	if material.is_locked:
		return {"status": FuseStatus.MAT_LOCKED, "reason": "材料装备已锁定，请先解锁", "cost": 0}
	var main_t: EquipmentTemplate = main_item.get_template()
	var mat_t: EquipmentTemplate = material.get_template()
	if main_t == null or mat_t == null:
		return {"status": FuseStatus.WRONG_SLOT, "reason": "模板缺失", "cost": 0}
	if main_t.slot_category != mat_t.slot_category:
		return {"status": FuseStatus.WRONG_SLOT, "reason": "材料与主装备不是同一槽位分类", "cost": 0}
	if mat_t.fusion_affix == null:
		return {"status": FuseStatus.NO_FUSION_AFFIX, "reason": "材料装备没有融合词条", "cost": 0}
	var c := cost(main_item.fusion_count, material.rarity)
	if gold < c:
		return {"status": FuseStatus.NOT_ENOUGH_GOLD, "reason": "金币不足，还差 %d" % (c - gold), "cost": c}
	return {"status": FuseStatus.OK, "reason": "", "cost": c}
