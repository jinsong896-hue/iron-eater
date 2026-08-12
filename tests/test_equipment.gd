extends SceneTree
## 装备系统逻辑测试：模板/实例分离、分类标签、槽位、融合、强化、吞噬、掉落、序列化

const ManagerScript := preload("res://scripts/equipment/equipment_manager.gd")
const TemplateScript := preload("res://scripts/equipment/equipment_template.gd")
const InstanceScript := preload("res://scripts/equipment/equipment_instance.gd")

var failed := 0


func _init() -> void:
	_check(EquipmentDB.all_templates().size() == 36, "36 件白装模板")
	_test_tags()
	_test_instance_separation()
	_test_loadout()
	_test_fusion()
	_test_enhance()
	_test_devour()
	_test_loot()
	_test_serialize()
	if failed == 0:
		print("ALL EQUIPMENT TESTS PASSED")
		quit(0)
	else:
		print("EQUIPMENT TESTS FAILED: %d" % failed)
		quit(1)


func _test_tags() -> void:
	var sword: EquipmentTemplate = EquipmentDB.get_template("W01")
	var spear: EquipmentTemplate = EquipmentDB.get_template("W08")
	var staff: EquipmentTemplate = EquipmentDB.get_template("W11")
	var shield: EquipmentTemplate = EquipmentDB.get_template("W05")
	var helm: EquipmentTemplate = EquipmentDB.get_template("A03")
	var ring: EquipmentTemplate = EquipmentDB.get_template("J01")
	_check("单手" in sword.all_tags() and "近战" in sword.all_tags() and "物理" in sword.all_tags(), "单手剑标签")
	_check("双手" in spear.all_tags() and "长杆" in spear.all_tags(), "长枪自动双手+长杆")
	_check("双手" in staff.all_tags() and "法术" in staff.all_tags(), "法杖双手+法术")
	_check("单手" in shield.all_tags() and "其他" in shield.all_tags(), "盾牌单手+其他")
	_check("重甲" in helm.all_tags() and "白色" in helm.all_tags(), "头盔重甲标签")
	_check(ring.all_tags() == ["白色"], "饰品仅稀有度标签")


func _test_instance_separation() -> void:
	var t: EquipmentTemplate = EquipmentDB.get_template("W01")
	var a := InstanceScript.create(t)
	var b := InstanceScript.create(t)
	a.fusion_count = 5
	_check(b.fusion_count == 0, "模板/实例分离：实例 A 融合不影响 B")
	_check(a.instance_id != b.instance_id, "实例 ID 唯一")


func _test_loadout() -> void:
	var m: EquipmentManager = ManagerScript.new()
	var sword := InstanceScript.create(EquipmentDB.get_template("W01"))
	var shield := InstanceScript.create(EquipmentDB.get_template("W05"))
	var greatsword := InstanceScript.create(EquipmentDB.get_template("W06"))
	m.add_item(sword)
	m.add_item(shield)
	m.add_item(greatsword)
	var r1 := m.equip(sword.instance_id)
	_check(r1.ok, "单手剑可装备")
	var r2 := m.equip(shield.instance_id)
	_check(r2.ok, "盾牌可装备武器2")
	_check(m.loadout.get_item(EquipmentDefs.SlotId.WEAPON_1) == sword, "武器1=单手剑")
	_check(m.loadout.get_item(EquipmentDefs.SlotId.WEAPON_2) == shield, "武器2=盾牌")
	var r3 := m.equip(greatsword.instance_id)
	_check(r3.ok, "双手剑可装备")
	_check(m.loadout.get_item(EquipmentDefs.SlotId.WEAPON_1) == greatsword, "双手剑占武器1")
	_check(m.loadout.get_item(EquipmentDefs.SlotId.WEAPON_2) == greatsword, "双手剑占武器2")
	_check(m.loadout.equipped_items().size() == 1, "双手剑属性只计一次")
	_check(m.inventory.has(sword) and m.inventory.has(shield), "被双手武器替换的单手装备回到背包")


func _test_fusion() -> void:
	var m: EquipmentManager = ManagerScript.new()
	var main := InstanceScript.create(EquipmentDB.get_template("W01"))
	var mat := InstanceScript.create(EquipmentDB.get_template("W01"))
	var wrong_slot := InstanceScript.create(EquipmentDB.get_template("A03"))
	m.add_item(main)
	m.add_item(mat)
	m.add_item(wrong_slot)
	var cost0 := FusionRules.cost(0, EquipmentDefs.Rarity.WHITE)
	_check(cost0 == 50, "融合费用 0 次=50")
	_check(FusionRules.cost(25, EquipmentDefs.Rarity.WHITE) == 425, "融合费用 25 次=425")
	var v1 := FusionRules.validate(main, wrong_slot, 99999, true, true)
	_check(v1.status == FusionRules.FuseStatus.WRONG_SLOT, "异槽位拒绝融合")
	var v2 := FusionRules.validate(main, mat, 10, true, true)
	_check(v2.status == FusionRules.FuseStatus.NOT_ENOUGH_GOLD, "金币不足拒绝")
	var result := m.fuse(main.instance_id, mat.instance_id, 99999)
	_check(result.ok, "同名融合成功")
	_check(main.fusion_count == 1, "融合次数 +1")
	_check(not m.inventory.has(mat), "材料消失")
	_check(main.gained_fusion_affixes.size() == 1 and main.gained_fusion_affixes[0].stack_count == 1, "首次同名融合新增 ×1")
	# 第二次同名融合：升级已有词条 → ×2
	var mat2 := InstanceScript.create(EquipmentDB.get_template("W01"))
	m.add_item(mat2)
	var result2 := m.fuse(main.instance_id, mat2.instance_id, 99999)
	_check(result2.ok and main.gained_fusion_affixes[0].stack_count == 2, "同名二次融合升级 ×2")
	_check(FusionRules.tier_name(8) == "纯净" and FusionRules.tier_name(21) == "神话", "品质阈值")
	var locked := InstanceScript.create(EquipmentDB.get_template("W01"))
	locked.is_locked = true
	m.add_item(locked)
	var v3 := FusionRules.validate(main, locked, 99999, true, true)
	_check(v3.status == FusionRules.FuseStatus.MAT_LOCKED, "锁定材料拒绝")


func _test_enhance() -> void:
	var m: EquipmentManager = ManagerScript.new()
	var item := InstanceScript.create(EquipmentDB.get_template("W01"))
	m.add_item(item)
	var cost := EnhancementRules.cost(0)
	_check(cost == 100, "强化 0 级费用 100")
	var r1 := m.enhance(item.instance_id, 500)
	_check(r1.ok and item.enhancement_level == 1, "强化成功 +1")
	var base: float = item.get_template().base_affix.value
	_check(absf(EnhancementRules.enhanced_value(base, 1) - base * 1.05) < 0.001, "强化 +5%")
	var r2 := m.enhance(item.instance_id, 10)
	_check(not r2.ok and item.enhancement_level == 1, "金币不足不强化")


func _test_devour() -> void:
	var m: EquipmentManager = ManagerScript.new()
	var a := InstanceScript.create(EquipmentDB.get_template("W01"))
	var b := InstanceScript.create(EquipmentDB.get_template("W02"))
	b.is_locked = true
	var c := InstanceScript.create(EquipmentDB.get_template("W06"))
	m.add_item(a)
	m.add_item(b)
	m.add_item(c)
	var result := m.devour_many([a.instance_id, b.instance_id, c.instance_id])
	_check(result.count == 2, "批量吞噬 2 件（锁定跳过）")
	_check(m.devour_totals.has("atk"), "吞噬累计攻击")
	_check(absf(m.devour_totals["atk"]["flat"] - 1.2) < 0.001, "吞噬累计数值 0.5+0.7=1.2")
	_check(m.inventory.has(b), "锁定装备保留")


func _test_loot() -> void:
	var m: EquipmentManager = ManagerScript.new()
	var ids := {}
	var valid := true
	for i in 100:
		var item := m.create_loot()
		if item == null or EquipmentDB.get_template(item.template_id) == null:
			valid = false
			break
		if ids.has(item.instance_id):
			valid = false
			break
		ids[item.instance_id] = true
	_check(valid, "掉落 100 件全部有效且实例唯一")


func _test_serialize() -> void:
	var m: EquipmentManager = ManagerScript.new()
	var sword := InstanceScript.create(EquipmentDB.get_template("W01"))
	sword.fusion_count = 5
	var helm := InstanceScript.create(EquipmentDB.get_template("A03"))
	m.add_item(sword)
	m.add_item(helm)
	m.equip(sword.instance_id)
	m.devour_many([helm.instance_id])
	var data := m.serialize()
	var m2: EquipmentManager = ManagerScript.new()
	m2.deserialize(data)
	_check(m2.inventory.size() == m.inventory.size(), "序列化背包数量一致")
	_check(m2.loadout.get_item(EquipmentDefs.SlotId.WEAPON_1) != null, "序列化装备栏恢复")
	_check(m2.devour_totals.has("def"), "序列化吞噬累计恢复")


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
