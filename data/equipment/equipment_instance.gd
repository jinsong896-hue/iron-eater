class_name EquipmentInstance
extends RefCounted
## 装备实例 —— 运行时数据，记录成长状态

var instance_id: String = ""
var template_id: StringName = &""
var rarity: int = 0
var fusion_count: int = 0
var enhancement_level: int = 0
var is_locked: bool = false
var created_at_usec: int = 0

## 通用词条（名词分册第 5 章：装备可附加的 16 种属性型词条）。
## **挂在实例而非模板**：同一模板的两件装备可以各自附魔不同词条，
## 挂模板上会让全世界的「铁制单手剑」共享同一套附加词条。
## 由融合/附魔/商店附加（见 EquipmentManager.attach_generic_affix）。
var extra_affixes: Array[AffixData] = []

## 附魔次数（策划 4.3.2：单件装备最多附魔 3 次，见
## SpecialRoomService.ENCHANT_MAX_STACKS / can_enchant）。
## 与 extra_affixes 分开记：融合附加的词条不计入附魔次数上限。
var enchant_stacks: int = 0


func _init() -> void:
	created_at_usec = Time.get_ticks_usec()
	instance_id = _generate_uuid()


## 获取模板
func get_template() -> EquipmentTemplate:
	return EquipmentDB.get_template(template_id)


## 显示名
func display_name() -> String:
	var t := get_template()
	if t == null:
		return "未知装备"
	return t.display_name


## 融合等级文本。
## **委托给 FusionRules.tier_name**，不在此重复判定边界——
## 原先这里和 FusionRules 各写了一份，边界还不一致（3 次/7 次错位），
## 两处会各自漂移。品质规则只该有一个真相源。
func fusion_tier() -> String:
	return FusionRules.tier_name(fusion_count)


## 基础词条有效值（含强化）
func base_affix_value() -> float:
	var t := get_template()
	if t == null or t.base_affix == null:
		return 0.0
	return t.base_affix.value * (1.0 + enhancement_level * 0.05)


## 融合带来的攻击加成。
## **委托给 FusionRules.attack_bonus_at**（策划 3.1 的分段公式：
## 0→+0%，5→+15%，10→+30%，15→+50%，20→+75%，25→+100%）。
## 原先这里是 `fusion_count * 0.02`（25 次只有 +50%），
## 与 FusionRules 里的正确公式并存却各算各的，实际生效的是这个错的。
func fusion_bonus() -> float:
	return FusionRules.attack_bonus_at(fusion_count)


## 强化倍率
func enhancement_mult() -> float:
	return 1.0 + enhancement_level * 0.05


## 序列化
func to_dict() -> Dictionary:
	var affixes: Array = []
	for a in extra_affixes:
		if a != null:
			affixes.append(_affix_to_dict(a))
	return {
		"instance_id": instance_id,
		"template_id": str(template_id),
		"rarity": rarity,
		"fusion_count": fusion_count,
		"enhancement_level": enhancement_level,
		"is_locked": is_locked,
		"created_at_usec": created_at_usec,
		"extra_affixes": affixes,
		"enchant_stacks": enchant_stacks,
	}


## 通用词条 → 纯字典（存档用）。
## AffixData 是 Resource，直接塞进存档会写出资源路径；这里拍平成普通字典，
## 读档时用 _affix_from_dict 还原。
func _affix_to_dict(a: AffixData) -> Dictionary:
	return {
		"id": str(a.id),
		"stat": a.stat,
		"operation": a.operation,
		"value": a.value,
		"trigger_buff": a.trigger_buff,
		"trigger_chance": a.trigger_chance,
		"trigger_duration": a.trigger_duration,
	}


## 纯字典 → 通用词条（读档用）
func _affix_from_dict(d: Dictionary) -> AffixData:
	var a := AffixData.new(int(d.get("stat", 0)), float(d.get("value", 0.0)),
		int(d.get("operation", AffixData.Operation.FLAT)))
	a.id = StringName(d.get("id", ""))
	a.trigger_buff = str(d.get("trigger_buff", ""))
	a.trigger_chance = float(d.get("trigger_chance", 0.0))
	a.trigger_duration = float(d.get("trigger_duration", 0.0))
	return a


## 反序列化（实例方法：填充自身）
func from_dict(d: Dictionary) -> EquipmentInstance:
	instance_id = d.get("instance_id", _generate_uuid())
	template_id = StringName(d.get("template_id", ""))
	rarity = d.get("rarity", 0)
	fusion_count = d.get("fusion_count", 0)
	enhancement_level = d.get("enhancement_level", 0)
	is_locked = d.get("is_locked", false)
	created_at_usec = d.get("created_at_usec", 0)
	enchant_stacks = int(d.get("enchant_stacks", 0))
	extra_affixes.clear()
	for ad in d.get("extra_affixes", []):
		if ad is Dictionary:
			extra_affixes.append(_affix_from_dict(ad))
	return self


## 附加一条通用词条（同 id 不重复附加，避免叠加刷属性）
## 返回是否真的加上了。
func add_extra_affix(a: AffixData) -> bool:
	if a == null:
		return false
	for e in extra_affixes:
		if e != null and e.id == a.id and not str(a.id).is_empty():
			return false
	extra_affixes.append(a)
	return true


## 静态工厂：从模板创建实例
static func create(template: EquipmentTemplate) -> EquipmentInstance:
	var inst := EquipmentInstance.new()
	if template == null:
		return inst
	inst.template_id = template.id
	inst.rarity = template.rarity
	return inst


func _generate_uuid() -> String:
	var chars := "0123456789abcdef"
	var s := ""
	for i in range(8):
		s += chars[randi() % chars.length()]
	s += "-"
	for i in range(4):
		s += chars[randi() % chars.length()]
	s += "-4"
	for i in range(3):
		s += chars[randi() % chars.length()]
	s += "-"
	for i in range(4):
		s += chars[(randi() % 4 + 8)]
	s += "-"
	for i in range(12):
		s += chars[randi() % chars.length()]
	return s
