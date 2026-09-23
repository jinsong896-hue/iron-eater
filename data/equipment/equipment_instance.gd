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

## **同件累计计数**（装备参考2 规格）。
##
## 规格原文：自有/融合/吞噬三条词条都是「融合同一件装备时会升级」
## /「吞噬同一件装备时会升级」。故升级的判据不是「总共融了几次」，
## 而是「**这件（这个 id）** 累计了多少次」。
##
## 以 template_id 为键：同一件装备可能有多份实例，但只要 id 相同就算同件。
## 计数从 1 开始（第一次融合/吞噬即 1 级），上限见 EQUIP_AFFIX_MAX_LEVEL。
var same_fuse_counts: Dictionary = {}    ## template_id -> 累计融合次数
var same_devour_counts: Dictionary = {}  ## template_id -> 累计吞噬次数

## 同件词条的最高等级（超过后不再增长，避免无限叠）
const EQUIP_AFFIX_MAX_LEVEL := 10

## 通用词条（名词分册第 5 章：装备可附加的 16 种属性型词条）。
## **挂在实例而非模板**：同一模板的两件装备可以各自附魔不同词条，
## 挂模板上会让全世界的「铁制单手剑」共享同一套附加词条。
## 由融合/附魔/商店附加（见 EquipmentManager.attach_generic_affix）。
var extra_affixes: Array[AffixData] = []

## 附魔次数（策划 4.3.2：单件装备最多附魔 3 次，见
## SpecialRoomService.ENCHANT_MAX_STACKS / can_enchant）。
## 与 extra_affixes 分开记：融合附加的词条不计入附魔次数上限。
var enchant_stacks: int = 0

## 随机词条（装备参考2 规格：掉落时生成 1~4 条）。
##
## **与 extra_affixes 分开存**，因为生命周期完全不同：
##   · extra_affixes —— 融合/附魔产生，随装备成长（吃强化倍率）
##   · random_affixes —— 掉落时定死，**无法升级、无法转移、
##     不通过融合或吞噬继承**（规格原文）
## 分开存还让「随机词条不可升级」这条规则**在数据结构上就成立**——
## 升级路径只读 extra_affixes，随机词条天然进不去。
var random_affixes: Array[AffixData] = []


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


# ============================================================
# 同件累计升级（装备参考2 规格）
# ============================================================

## 某个装备 id 的累计融合次数（**用于「融合同一件升级」**）
func same_fuse_level(tid: StringName) -> int:
	return int(same_fuse_counts.get(str(tid), 0))


## 某个装备 id 的累计吞噬次数（**用于「吞噬同一件升级」**）
func same_devour_level(tid: StringName) -> int:
	return int(same_devour_counts.get(str(tid), 0))


## 记一次「融合了某件装备」。返回累计次数（已封顶）。
func note_same_fuse(tid: StringName) -> int:
	var k := str(tid)
	var n := mini(int(same_fuse_counts.get(k, 0)) + 1, EQUIP_AFFIX_MAX_LEVEL)
	same_fuse_counts[k] = n
	return n


## 记一次「吞噬了某件装备」。返回累计次数（已封顶）。
func note_same_devour(tid: StringName) -> int:
	var k := str(tid)
	var n := mini(int(same_devour_counts.get(k, 0)) + 1, EQUIP_AFFIX_MAX_LEVEL)
	same_devour_counts[k] = n
	return n


## 自有词条的有效值（含同件融合升级）。
##
## 规格：「自有词条…融合同一件装备时会升级」。
## 每融一件同名 +25%（0 次 = 原始值，1 次 = ×1.25，2 次 = ×1.5…），
## 上限 EQUIP_AFFIX_MAX_LEVEL 次。
func own_affix_value() -> float:
	var t := get_template()
	if t == null or t.own_affix == null:
		return 0.0
	var lv := same_fuse_level(template_id)
	return t.own_affix.value * (1.0 + float(lv) * 0.25) * enhancement_mult()


## 吞噬词条的有效值（含同件吞噬升级）。
##
## **吞噬词条是「这件装备被吞噬时给角色的加成」**，故升级看的是
## 「玩家累计吞噬过几件同名」——那个计数存在 GameManager 侧（跨实例），
## 由调用方传入。这里只负责按次数缩放模板值。
static func devour_value_at(t: EquipmentTemplate, times: int) -> float:
	if t == null or t.devour_affix == null:
		return 0.0
	var lv := clampi(times - 1, 0, EQUIP_AFFIX_MAX_LEVEL)
	return t.devour_affix.value * (1.0 + float(lv) * 0.25)


## 融合词条的有效值（含同件融合升级）。
##
## 融合词条是「这件装备作为素材时给主装备的加成」，
## 升级看的是「主装备累计融合过几件同名素材」——由主装备的
## same_fuse_counts 提供（调用方传入）。
static func fusion_value_at(t: EquipmentTemplate, times: int) -> float:
	if t == null or t.fusion_affix == null:
		return 0.0
	var lv := clampi(times - 1, 0, EQUIP_AFFIX_MAX_LEVEL)
	return t.fusion_affix.value * (1.0 + float(lv) * 0.25)


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
	var rnd: Array = []
	for a in random_affixes:
		if a != null:
			rnd.append(_affix_to_dict(a))
	return {
		"instance_id": instance_id,
		"template_id": str(template_id),
		"rarity": rarity,
		"fusion_count": fusion_count,
		"enhancement_level": enhancement_level,
		"is_locked": is_locked,
		"created_at_usec": created_at_usec,
		"extra_affixes": affixes,
		"random_affixes": rnd,
		"enchant_stacks": enchant_stacks,
		"same_fuse_counts": same_fuse_counts.duplicate(),
		"same_devour_counts": same_devour_counts.duplicate(),
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
		"random_kind": a.random_kind,
		"tier_color": a.tier_color,
		"attribute_kind": a.attribute_kind,
		"element_key": a.element_key,
		"is_borrowed": a.is_borrowed,
		"source_rarity": a.source_rarity,
	}


## 纯字典 → 通用词条（读档用）
func _affix_from_dict(d: Dictionary) -> AffixData:
	var a := AffixData.new(int(d.get("stat", 0)), float(d.get("value", 0.0)),
		int(d.get("operation", AffixData.Operation.FLAT)))
	a.id = StringName(d.get("id", ""))
	a.trigger_buff = str(d.get("trigger_buff", ""))
	a.trigger_chance = float(d.get("trigger_chance", 0.0))
	a.trigger_duration = float(d.get("trigger_duration", 0.0))
	a.random_kind = str(d.get("random_kind", ""))
	a.tier_color = str(d.get("tier_color", ""))
	a.attribute_kind = str(d.get("attribute_kind", ""))
	a.element_key = str(d.get("element_key", ""))
	a.is_borrowed = bool(d.get("is_borrowed", false))
	a.source_rarity = int(d.get("source_rarity", -1))
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
	random_affixes.clear()
	for ad in d.get("random_affixes", []):
		if ad is Dictionary:
			random_affixes.append(_affix_from_dict(ad))
	same_fuse_counts = (d.get("same_fuse_counts", {}) as Dictionary).duplicate()
	same_devour_counts = (d.get("same_devour_counts", {}) as Dictionary).duplicate()
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


## 静态工厂：创建**掉落物**实例（含随机词条）。
##
## **掉落走这里，商店/起始装备走 `create`** —— 规格原文：
## 「每个装备**掉落时**都会随机生成 1-4 个随机词条」。
## 商店卖的是定制品、起始装备是职业配置，都不该带随机词条。
##
## `rng` 由调用方传入（可复现）；`templates` 是特殊词条的借用候选池。
static func create_drop(template: EquipmentTemplate, rng: RandomNumberGenerator,
		templates: Array = []) -> EquipmentInstance:
	var inst := create(template)
	if inst.template_id == &"":
		return inst
	RandomAffix.roll_for(inst, rng, templates)
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
