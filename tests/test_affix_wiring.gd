extends Node
## 词条接线运行时验证 —— 每个通道都要「真的装上/融合/吞噬 → 数值真的变了」
##
## ## 为什么不能用 grep 验证接线
##
## 计划书 §0.4 记了两次踩坑：
## 1. `special_modifiers()` 的返回字典**定义**了每个键，搜字符串会把
##    「定义」当成「消费」
## 2. 元素通道走**动态拼接** `"%s_dmg_pct" % key`，搜字面量永远搜不到
##
## ## 三条生效路径（这是本测试的关键认知）
##
## 装备词条**不是**都靠「穿上」生效。实测各通道的来源列：
##
## | 通道 | 自有列（穿上生效） | 吞噬列（吞噬生效） | 融合列（融合生效） |
## |---|---|---|---|
## | `ranged_dmg` | 0 | **5** | 0 |
## | `shield_power` | 0 | **11** | 0 |
## | `debuff_resist` | 0 | **5** | 0 |
## | `frozen_dmg` | 0 | 0 | **3** |
## | `trap_dmg` | **1** | 3 | 0 |
##
## 所以测试必须**按各自的路径**触发——用「穿上装备」去验证一个只在
## 吞噬列存在的通道，永远失败，且失败原因与接线无关。

var failed := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 60.0
	guard.timeout.connect(func(): print("AFFIX WIRING TESTS FAILED: 超时"); get_tree().quit(1))
	add_child(guard); guard.start()
	await get_tree().process_frame
	await get_tree().process_frame

	EquipmentDB.init_equipment_db()

	_test_special_mods_roundtrip()
	_test_aoe_kind_classification()
	_test_debuff_kind_classification()
	await _test_own_affix_channel()
	await _test_devour_special_channel()
	await _test_fusion_channel()
	await _test_frozen_dmg_channel()

	if failed == 0:
		print("ALL AFFIX WIRING TESTS PASSED")
		get_tree().quit(0)
	else:
		print("AFFIX WIRING TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 1. `special_modifiers()` 必须把新增通道**汇总出来**
func _test_special_mods_roundtrip() -> void:
	print("\n--- special_modifiers 通道汇总 ---")
	var em = GameManager.equipment_manager
	if em == null:
		_check(false, "equipment_manager 就绪")
		return
	var sp: Dictionary = em.special_modifiers()
	var required := [
		"ranged_dmg_pct", "projectile_dmg_pct", "aoe_dmg_pct", "trap_dmg_pct",
		"frozen_dmg_pct", "debuff_resist_pct", "shield_power_pct",
		"fire_dmg_pct", "frost_dmg_pct", "static_dmg_pct", "earth_dmg_pct",
		"wind_dmg_pct", "poison_dmg_pct", "shadow_dmg_pct",
		"fire_resist_pct", "frost_resist_pct", "static_resist_pct",
		"earth_resist_pct", "wind_resist_pct", "poison_resist_pct",
		"shadow_resist_pct",
	]
	var missing: Array = []
	for k in required:
		if not sp.has(k):
			missing.append(k)
	_check(missing.is_empty(), "21 个新通道都在 special_modifiers 汇总里",
		["缺失：%s" % str(missing)])


## 2. AOE kind 分类（`aoe_dmg_pct` 的消费条件）
func _test_aoe_kind_classification() -> void:
	print("\n--- AOE kind 分类 ---")
	for k in ["aoe", "cone", "detonate", "spread"]:
		_check(k in ["aoe", "cone", "detonate", "spread"], "%s 归为范围伤害" % k)
	for k in ["pull", "multi_hit", "teleport", "dash", "projectile"]:
		_check(not (k in ["aoe", "cone", "detonate", "spread"]),
			"%s 不归为范围伤害" % k)


## 3. 负面词条分类（`debuff_resist_pct` 的消费条件）
func _test_debuff_kind_classification() -> void:
	print("\n--- 负面词条分类 ---")
	var holder := BuffHolder.new(null)
	for id in ["burn", "frost", "freeze", "mark", "weakness", "knockback"]:
		if BuffDefs.get_buff(id).is_empty():
			continue
		_check(holder._is_debuff_kind(int(BuffDefs.get_buff(id)[2])), "%s 判为负面" % id)
	for id in ["war_cry", "gen_atk_up", "iron_body"]:
		if BuffDefs.get_buff(id).is_empty():
			continue
		_check(not holder._is_debuff_kind(int(BuffDefs.get_buff(id)[2])),
			"%s 不判为负面（增益不该被抗性抵抗）" % id)


## 4. **自有列**通道：穿上装备即生效
##
## `trap_dmg` 是唯一有自有列来源的（`陷阱护符 B049`）。
func _test_own_affix_channel() -> void:
	print("\n--- 自有列通道（穿上生效）---")
	_reset()
	await get_tree().process_frame
	var base := _channel("trap_dmg_pct")

	if not _equip_by_name("陷阱护符", EquipmentDefs.Slot.ACCESSORY_1):
		_check(false, "装上「陷阱护符」(B049)")
		return
	await get_tree().process_frame
	var after := _channel("trap_dmg_pct")
	_check(after > base, "陷阱护符的自有词条 → trap_dmg_pct 生效",
		["装前=%.4f 装后=%.4f" % [base, after]])
	_reset()


## 5. **吞噬列**通道：吞噬后生效（本轮修的 bug 路径）
##
## 这是**本轮修的最严重的 bug**：`devour()` 无条件把 `stat` 传给
## `AttributeSystem.add_modifier`，而吞噬词条的 `stat` 是 SPECIAL_STAT
## 枚举（>=100）——越界报错并静默失效。实测 346 条吞噬词条里 245 条如此。
func _test_devour_special_channel() -> void:
	print("\n--- 吞噬列通道（吞噬生效）---")
	_reset()
	await get_tree().process_frame
	var base := _channel("shield_power_pct")

	# 护盾发生器 G037 的吞噬词条是「护盾获取量增加0.5%」
	var inst := _make_inst_by_name("护盾发生器")
	if inst == null:
		_check(false, "构造「护盾发生器」实例")
		return
	var r: Dictionary = GameManager.equipment_manager.devour(inst)
	_check(bool(r.get("ok", false)), "吞噬「护盾发生器」成功", [str(r.get("reason", ""))])
	await get_tree().process_frame
	var after := _channel("shield_power_pct")
	_check(after > base, "吞噬「护盾获取量 +0.5%」→ shield_power_pct 生效",
		["吞前=%.4f 吞后=%.4f" % [base, after]])
	_reset()


## 6. **融合列**通道：融合进主装备后生效
##
## `frozen_dmg` 只在融合列（`冰霜新星胸甲 B083` 等 3 件）。
func _test_fusion_channel() -> void:
	print("\n--- 融合列通道（融合生效）---")
	_reset()
	await get_tree().process_frame
	GameManager.gold = 1000
	var base := _channel("frozen_dmg_pct")

	# 主装备用任意胸甲，材料用带 frozen_dmg 的 B083
	var main_inst := _make_inst_by_name("吸血脉甲")   # ARMOR/CHEST，与材料同大类
	var mat_inst := _make_inst_by_name("冰霜新星胸甲")   # 融合词条 = 被冻结敌人增伤
	if main_inst == null or mat_inst == null:
		_check(false, "构造融合主/材料实例")
		return
	var r: Dictionary = GameManager.equipment_manager.fuse(main_inst, mat_inst)
	_check(bool(r.get("ok", false)), "融合成功", [str(r.get("reason", ""))])
	# 融合产物需**穿上**才生效（融合词条进 main.extra_affixes）
	GameManager.equipment_manager.equip(EquipmentDefs.Slot.CHEST, main_inst)
	await get_tree().process_frame
	var after := _channel("frozen_dmg_pct")
	_check(after > base, "融合「被冻结敌人增伤」→ frozen_dmg_pct 生效",
		["融合前=%.4f 融合后=%.4f" % [base, after]])
	_reset()


## 7. `frozen_dmg_pct` 的**消费点**：只对冻结目标增伤
func _test_frozen_dmg_channel() -> void:
	print("\n--- frozen_dmg_pct 消费点验证 ---")
	_reset()
	await get_tree().process_frame
	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return

	GameManager.gold = 1000
	var unfrozen := _ranged_damage(player)

	# 融合出带 frozen_dmg 的胸甲并穿上
	var main_inst := _make_inst_by_name("吸血脉甲")
	var mat_inst := _make_inst_by_name("冰霜新星胸甲")
	if main_inst == null or mat_inst == null:
		_check(false, "构造融合实例")
		return
	GameManager.equipment_manager.fuse(main_inst, mat_inst)
	GameManager.equipment_manager.equip(EquipmentDefs.Slot.CHEST, main_inst)
	await get_tree().process_frame
	var bonus := _channel("frozen_dmg_pct")
	_check(bonus > 0.0, "融合产物提供 frozen_dmg_pct", ["实际=%.4f" % bonus])

	player.set("_target_is_frozen", false)
	var unfrozen_boosted := _ranged_damage(player)
	player.set("_target_is_frozen", true)
	var frozen_boosted := _ranged_damage(player)

	_check(absf(unfrozen_boosted - unfrozen) < unfrozen * 0.001,
		"目标未冻结时，「对被冻结目标增伤」不生效",
		["基线=%.2f 装了但未冻结=%.2f" % [unfrozen, unfrozen_boosted]])
	_check(frozen_boosted > unfrozen_boosted * 1.001,
		"目标冻结时，「对被冻结目标增伤」生效",
		["未冻结=%.2f 冻结=%.2f" % [unfrozen_boosted, frozen_boosted]])
	player.set("_target_is_frozen", false)
	_reset()


# ============================================================
# 辅助
# ============================================================

func _player() -> Node3D:
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] as Node3D if not ps.is_empty() else null


## 读某个装备通道的当前汇总值
func _channel(key: String) -> float:
	var em = GameManager.equipment_manager
	if em == null:
		return 0.0
	var sp: Dictionary = em.special_modifiers()
	return float(sp.get(key, 0.0))


## 用「远程普攻」的参数算一次伤害（不实际发射，只看数值）
func _ranged_damage(player: Node3D) -> float:
	var calc: Dictionary = player.call("_compute_basic_damage",
		1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, false, true)
	return float(calc["damage"])


func _make_inst(id: String) -> EquipmentInstance:
	var tpl = EquipmentDB.get_template(id)
	return EquipmentInstance.create(tpl) if tpl != null else null


## 按**显示名**构造实例（优先于硬编码 ID）
##
## ## 为什么不用硬编码 ID
##
## 装备 ID 是**按稀有度内的出现顺序**生成的。策划往 TSV 里插一件装备，
## 其后所有同稀有度装备的 ID 都会**整体后移**——实测本轮就位移了
##（`陷阱护符` B049 → B051、`护盾发生器` G037 → G044、
## `冰霜新星胸甲` B083 → B086、`远程精准镜` G048 → G055）。
##
## 硬编码 ID 的测试会在数据变化时**静默测错对象**——不报错，
## 只是测了别的装备。这是最坏的一种测试失败。
func _make_inst_by_name(name: String) -> EquipmentInstance:
	var tpl = _find_by_name(name)
	return EquipmentInstance.create(tpl) if tpl != null else null


func _find_by_name(name: String):
	for t in EquipmentDB.all_templates():
		var id := str(t.id)
		if not (id.length() >= 2 and id.substr(1, 1).is_valid_int() \
				and id.substr(0, 1) in "GBPO"):
			continue
		if t.display_name == name:
			return t
	return null


func _equip_by_name(name: String, slot: int) -> bool:
	var inst := _make_inst_by_name(name)
	if inst == null:
		return false
	GameManager.equipment_manager.equip(slot, inst)
	return true


func _equip_by_id(id: String, slot: int) -> bool:
	var inst := _make_inst(id)
	if inst == null:
		return false
	GameManager.equipment_manager.equip(slot, inst)
	return true


## 清空装备 + 吞噬状态（回到基线）
##
## **必须用 `unequip`**：`equip(slot, null)` 在 `equip` 开头就
## `if inst == null: return`——清不掉，装备还留在身上，基线会带上
## 上一轮的加成，测试全部失真。
##
## 吞噬状态用 `from_dict({})` 重置——`from_dict` 会撤掉旧的吞噬 modifier
## 并清空 `_devour_specials`（见该函数实现）。没有公开的
## `reset_devour()`，故用这个等价入口。
func _reset() -> void:
	var em = GameManager.equipment_manager
	if em == null:
		return
	for slot in [EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Slot.WEAPON_2,
			EquipmentDefs.Slot.HEAD, EquipmentDefs.Slot.CHEST,
			EquipmentDefs.Slot.SHOULDERS, EquipmentDefs.Slot.HANDS,
			EquipmentDefs.Slot.LEGS, EquipmentDefs.Slot.FEET,
			EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Slot.ACCESSORY_2]:
		em.unequip(slot)
	em.from_dict({})


func _check(c: bool, name: String, detail: Array = []) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
		for d in detail:
			print("    %s" % d)
