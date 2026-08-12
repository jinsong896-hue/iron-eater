extends SceneTree
## 框架逻辑自测：属性叠加、伤害公式、装备数据、吞噬/融合
## 运行：godot --headless --path <项目> --script res://tests/test_framework.gd

const AttrScript := preload("res://scripts/core/attribute_system.gd")
const DmgScript := preload("res://scripts/combat/damage_pipeline.gd")


func _init() -> void:
	var failed := 0

	# 1. 属性系统：基础值 + Modifier 叠加
	var attr = AttrScript.new()
	failed = _check(attr.get_value(AttrScript.Stat.ATK) == 35.0, "战士初始攻击 35", failed)
	attr.add_modifier("test", AttrScript.Stat.ATK, 5.0, 0.1)
	failed = _check(absf(attr.get_value(AttrScript.Stat.ATK) - 43.5) < 0.001, "Modifier 固定+百分比叠加", failed)
	attr.remove_modifiers("test")
	failed = _check(absf(attr.get_value(AttrScript.Stat.ATK) - 35.0) < 0.001, "Modifier 移除", failed)

	# 2. 伤害公式：35 攻击打 10 防御 ≈ 31.8
	var r = DmgScript.physical(35.0, 1.0, 0.0, 10.0)
	failed = _check(r.damage > 31.0 and r.damage < 32.0, "物理伤害公式（含护甲减伤）", failed)
	var crit_dmg = DmgScript.with_crit(100.0, true, 0.5)
	failed = _check(absf(crit_dmg - 200.0) < 0.001, "暴击 150%+50% 加成 = 200%", failed)

	# 3. 装备模板与实例（36 件白装数据库）
	var sword = EquipmentDB.get_template("W01")
	failed = _check(sword != null and sword.rarity_name() == "白" and sword.base_affix.value == 35.0, "白装模板（铁制单手剑）", failed)
	var inst = EquipmentInstance.create(sword)
	failed = _check(inst != null and inst.get_template() == sword, "模板创建实例", failed)

	# 4. 融合词条品质
	var item = EquipmentInstance.create(sword)
	failed = _check(item.fusion_tier() == "无", "融合 0 次 = 无", failed)
	item.fusion_count = 8
	failed = _check(item.fusion_tier() == "纯净", "融合 8 次 = 纯净", failed)
	item.fusion_count = 25
	failed = _check(item.fusion_tier() == "神话", "融合 25 次 = 神话", failed)

	if failed == 0:
		print("ALL FRAMEWORK TESTS PASSED")
		quit(0)
	else:
		print("TESTS FAILED: %d" % failed)
		quit(1)


func _check(cond: bool, name: String, failed: int) -> int:
	if cond:
		print("  [OK] %s" % name)
		return failed
	else:
		print("  [FAIL] %s" % name)
		return failed + 1
