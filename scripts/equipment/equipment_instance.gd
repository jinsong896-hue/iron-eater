class_name EquipmentInstance
extends RefCounted
## 装备实例：实际掉落/持有的装备，与模板严格分离
## 实例字段：instance_id / fusion_count / enhancement_level / 已获得融合词条 / 锁定 / 生成时间

var instance_id := ""
var template_id := ""
var rarity := EquipmentDefs.Rarity.WHITE
var fusion_count := 0
var enhancement_level := 0
var gained_fusion_affixes: Array[AffixInstance] = []
var is_locked := false
var created_at_usec := 0

## 进程内实例序号（保证 ID 唯一，不依赖全局随机，避免污染本局可复现性）
static var _seq := 0


static func create(template: EquipmentTemplate) -> EquipmentInstance:
	var inst := EquipmentInstance.new()
	_seq += 1
	inst.instance_id = "%s_%d_%d" % [template.id, Time.get_ticks_usec(), _seq]
	inst.template_id = template.id
	inst.rarity = template.rarity
	inst.created_at_usec = Time.get_ticks_usec()
	return inst


func get_template() -> EquipmentTemplate:
	return EquipmentDB.get_template(template_id)


## 融合攻击成长（策划表：0/5/10/15/20/25 → 0/15/30/50/75/100%）
func fusion_bonus() -> float:
	return FusionRules.attack_bonus_at(fusion_count)


## 强化只提升基础词条（固定 +5%/级）
func enhancement_mult() -> float:
	return 1.0 + enhancement_level * EnhancementRules.BONUS_PER_LEVEL


## 基础词条的有效值（含强化）：固定与百分比词条统一按强化倍率缩放
func base_affix_value() -> float:
	var t := get_template()
	if t == null or t.base_affix == null:
		return 0.0
	return t.base_affix.value * enhancement_mult()


func fusion_tier() -> String:
	return FusionRules.tier_name(fusion_count)


func display_name() -> String:
	var t := get_template()
	return t.display_name if t != null else template_id


func rarity_name() -> String:
	return EquipmentDefs.rarity_name(rarity)


func to_dict() -> Dictionary:
	var affixes: Array = []
	for a in gained_fusion_affixes:
		affixes.append(a.to_dict())
	return {
		"instance_id": instance_id, "template_id": template_id, "rarity": rarity,
		"fusion_count": fusion_count, "enhancement_level": enhancement_level,
		"is_locked": is_locked, "created_at_usec": created_at_usec,
		"gained_fusion_affixes": affixes,
	}


static func from_dict(d: Dictionary) -> EquipmentInstance:
	var inst := EquipmentInstance.new()
	inst.instance_id = d.get("instance_id", "")
	inst.template_id = d.get("template_id", "")
	inst.rarity = d.get("rarity", EquipmentDefs.Rarity.WHITE)
	inst.fusion_count = d.get("fusion_count", 0)
	inst.enhancement_level = d.get("enhancement_level", 0)
	inst.is_locked = d.get("is_locked", false)
	inst.created_at_usec = d.get("created_at_usec", 0)
	inst.gained_fusion_affixes.clear()
	for a in d.get("gained_fusion_affixes", []):
		inst.gained_fusion_affixes.append(AffixInstance.from_dict(a))
	return inst
