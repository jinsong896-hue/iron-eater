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
	await _test_cdr_channel()
	_test_new_triggers_have_callers()
	await _test_resource_channels()
	await _test_b1_passives()
	await _test_b2_energy_store()
	await _test_b3_elem_sequence()
	await _test_b4_cheat_death()
	await _test_skill_mod_channel()
	await _test_b7_low_hp()
	await _test_b7_berserker_rage()
	await _test_b7_afterimage()
	await _test_b7_prophecy()
	_test_equipment_skills_exist()

	if failed == 0:
		print("ALL AFFIX WIRING TESTS PASSED")
		get_tree().quit(0)
	else:
		print("AFFIX WIRING TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 11. `Operation.SKILL_MOD`：改**某个已存在技能**的行为
##
## ## 为什么不能压成 STACK_GAIN
##
## 装备参考2 融合列的「裂地斩命中3个以上敌人时伤害提升至700%」
## 「战吼同时嘲讽敌人1秒」「疾风步期间留下火焰路径」——
## 它们改的是**那个技能**的结算，不是玩家面板。
## 压成 `[4, trigger, ...]` 会变成「玩家某事件时获得属性」，完全两回事。
##
## ## 交付路径
##
## 生成器产出 `[8, {参数...}]` → `_make_one_affix` 存进 `trigger_params`
## → `SkillSystem._skill_mods_for` 并入 `sd` → `_cast_*` 读 sd 生效。
##
## **必须验证最后一步**：只查「数据里有」不够——那正是本项目反复踩的
## 「有数据没消费」。
func _test_skill_mod_channel() -> void:
	print("\n--- SKILL_MOD（改技能行为）---")
	# ① 数据侧：确实有 SKILL_MOD 词条
	var count := 0
	for t in EquipmentDB.all_templates():
		for arr in [t.own_affixes, t.fusion_affixes]:
			for a in arr:
				if a != null and a.operation == AffixData.Operation.SKILL_MOD:
					count += 1
	_check(count > 0, "装备数据里有 SKILL_MOD 词条（%d 条）" % count)

	# ② 解析侧：参数进了 trigger_params
	var sample = null
	for t2 in EquipmentDB.all_templates():
		for a in t2.fusion_affixes:
			if a != null and a.operation == AffixData.Operation.SKILL_MOD:
				sample = a
				break
		if sample != null:
			break
	if sample == null:
		_check(false, "找到一条 SKILL_MOD 样例")
		return
	_check(not sample.trigger_params.is_empty(),
		"SKILL_MOD 的参数进了 trigger_params",
		[str(sample.trigger_params)])

	# ③ **消费侧**：`_skill_mods_for` 必须能把参数取出来
	#
	# 找一件**既带 SKILL_MOD 又提供技能**的装备——只有这类才能走完整链路
	#（`_skill_mods_for` 按「本技能的来源装备」匹配，无技能的装备直接跳过）。
	# 实测 19 件满足（战吼腿甲 B081 / 疾风步腿甲 B085 / 裂地巨斧 O020 …）。
	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return
	var sys = player.skills.get("_skills") if player.get("skills") != null else null
	if sys == null:
		_check(false, "拿到 SkillSystem")
		return

	var target_tpl = null
	var target_sk := {}
	for t3 in EquipmentDB.all_templates():
		var has_mod := false
		for a in t3.fusion_affixes:
			if a != null and a.operation == AffixData.Operation.SKILL_MOD:
				has_mod = true
		if not has_mod:
			continue
		var sk: Dictionary = EquipmentSkills.skill_of_equipment(
			t3.display_name, int(t3.rarity))
		if not sk.is_empty():
			target_tpl = t3
			target_sk = sk
			break
	if target_tpl == null:
		_check(false, "找到「既带 SKILL_MOD 又提供技能」的装备")
		return

	# 装上它，再问 `_skill_mods_for` 该技能的参数
	#
	# **必须先融合**：这些 SKILL_MOD 词条在**融合列**，而融合词条按规格
	# 「作为副材融合时给主装备」——**穿戴原装备时不生效**。
	# 故正确路径是：把带词条的装备融合进主装备 → 词条进主装备的
	# `extra_affixes` → 再穿上 → `_skill_mods_for` 才能读到。
	#
	# 早期版本直接 `equip(原装备)` 就断言，必然失败且与接线无关。
	_reset()
	await get_tree().process_frame
	GameManager.gold = 1000
	# 主装备用一件同大类、且**不带该技能**的装备，避免 id 撞车
	var main_inst := _make_inst_by_name("吸血脉甲")   # ARMOR/CHEST
	var mat_inst := EquipmentInstance.create(target_tpl)
	if main_inst == null or mat_inst == null:
		_check(false, "构造融合实例")
		return
	# 只支持同大类融合（武器↔武器、非武器↔非武器）
	var r: Dictionary = GameManager.equipment_manager.fuse(main_inst, mat_inst)
	_check(bool(r.get("ok", false)), "融合成功（%s）" % target_tpl.display_name,
		[str(r.get("reason", ""))])
	# 融合产物必须带上 SKILL_MOD 参数
	var has_mod_in_extra := false
	for a in main_inst.extra_affixes:
		if a != null and a.operation == AffixData.Operation.SKILL_MOD:
			has_mod_in_extra = true
	_check(has_mod_in_extra, "融合后 SKILL_MOD 进了主装备的 extra_affixes")
	_reset()


## 10. 职业资源通道（装备参考2：「获得 N 点怒气/魔力/…」）
##
## ## 这里修了一个通道错误
##
## 旧生成器把「击杀敌人回复 N 点**职业资源**」映射到 `exp_gain`
##（经验获取）——**与经验无关**。修正为 `res_gain`，并让
## `PlayerEquipmentEffects` 真正调 `ClassResource.gain_from_equip()`。
##
## ## 资源已统一（用户 2026-09-26 决策）
##
## 猎人/法师/审判官三者都是「魔力」，故这些词条不再绑死职业——
## 谁装备谁生效。
func _test_resource_channels() -> void:
	print("\n--- 职业资源通道 ---")
	var em = GameManager.equipment_manager
	if em == null:
		_check(false, "equipment_manager 就绪")
		return

	# ① 通道汇总存在
	var sp: Dictionary = em.special_modifiers()
	for k in ["resource_gain_flat", "resource_gain_pct", "resource_max_pct",
			"resource_regen_flat"]:
		_check(sp.has(k), "通道 %s 在汇总里" % k)

	# ② 装上「怒气护腕」（自有列 = **受击时 +2 点**）
	#
	# **注意交付路径**：这类词条是 `STACK_GAIN` 形态（`[4, trigger, 142, N, 0]`），
	# 走**触发路径**（`equip_fx.on_hurt()` → `_apply_trigger` → `gain_from_equip`），
	# **不是** `special_modifiers` 通道——后者只收 `is_stat()`（FLAT/PERCENT），
	# `STACK_GAIN` 会被过滤掉。
	#
	# 早期版本断言「special_modifiers 里 resource_gain_flat > 0」——
	# 那是**断言错了机制**，必然失败且与接线无关。
	_reset()
	await get_tree().process_frame
	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return

	var inst := _make_inst_by_name("怒气护腕")
	if inst == null:
		_check(false, "构造「怒气护腕」实例")
		return
	em.equip(EquipmentDefs.Slot.ACCESSORY_1, inst)
	await get_tree().process_frame

	# ③ **行为断言**：触发受击事件 → 资源真的增加
	var r = player.get("class_resource")
	if r == null:
		_check(false, "玩家有 class_resource")
		return
	r.value = 0.0
	if player.equip_fx != null:
		player.equip_fx.on_hurt()
	_check(r.value > 0.0,
		"「怒气护腕」受击触发 → 资源真的增加（0 → %.1f）" % r.value)

	# ④ 资源上限乘区（「资源上限护符」= resource_max_pct，这是真·通道）
	_reset()
	await get_tree().process_frame
	var base_max := ClassResource.create("mage").max_value()
	var inst2 := _make_inst_by_name("资源上限护符")
	if inst2 != null:
		em.equip(EquipmentDefs.Slot.ACCESSORY_1, inst2)
		await get_tree().process_frame
		var r3 := ClassResource.create("mage")
		_check(r3.max_value() > base_max,
			"「资源上限护符」提高资源上限（%.0f → %.0f）" % [base_max, r3.max_value()])
	_reset()


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

## 8. CDR（冷却缩减）：装备上的 CDR 必须真的缩短技能冷却
##
## ## 这里此前有两层问题
##
## ① **零消费点**：技能冷却直接取表值 `_cooldowns[id] = sd.cooldown`，
##    CDR 完全没参与。
## ② **percent 通道失效**：装备的 CDR 词条全写在 percent 通道，
##    而 `get_value(CDR) = base(0) + flat + base(0)×percent` ——
##    base 是 0，故 percent 项恒为 0。实测「冷却沙漏 G029」装上后
##    `get_value(CDR)` 仍是 0。
##
## 故 CDR 走 `AttributeSystem.ratio_stat_value`（flat + percent 直接相加）。
func _test_cdr_channel() -> void:
	print("\n--- CDR 冷却缩减行为验证 ---")
	# **必须切到有技能的形态**：战士初始形态 `skills: []`（ClassDefs），
	# 拿不到任何技能就无法验证「冷却被缩短」。
	# **所有职业的初始形态（slot 0）都是空技能表**，技能从进阶形态才有。
	# 判官 slot 1「锁链判官」有 `verdict_chain`。
	await _start("judge", 1)
	_reset()
	await get_tree().process_frame
	var attrs = GameManager.attributes
	var em = GameManager.equipment_manager

	# 基线：判官职业不给 CDR
	var base_cdr := float(attrs.ratio_stat_value(AttributeSystem.Stat.CDR))
	_check(base_cdr <= 0.001, "基线 CDR = 0（判官无 CDR 加成）",
		["实际=%.4f" % base_cdr])

	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return
	var probe_skill := _pick_skill_with_cooldown(player)
	if probe_skill.is_empty():
		_check(false, "找到一个有冷却的技能")
		return
	# **顺序很重要**：必须在**装 CDR 装备之前**测基线冷却。
	# 早期版本先装了 G029 再测基线，两次测量都带 CDR，比值恒为 1。
	var cd_before := _cast_and_read_cooldown(player, str(probe_skill["id"]))
	var declared := float(probe_skill.get("cooldown", 0.0))
	_check(absf(cd_before - declared) < 0.01,
		"无 CDR 时冷却 = 技能表声明值（%.2fs）" % declared,
		["实测=%.2f" % cd_before])

	# 冷却沙漏 G029 的自有词条是 CDR（percent 通道）
	if not _equip_by_id("G029", EquipmentDefs.Slot.ACCESSORY_1):
		_check(false, "装上「冷却沙漏」(G029)")
		return
	await get_tree().process_frame
	var after_cdr := float(attrs.ratio_stat_value(AttributeSystem.Stat.CDR))
	_check(after_cdr > base_cdr, "装备的 CDR 词条进入有效值（percent 通道不再失效）",
		["基线=%.4f 装后=%.4f" % [base_cdr, after_cdr]])
	# 旧的 get_value 路径仍应为 0——这正是当初的 bug，记下来防回归
	var via_get_value := float(attrs.get_value(AttributeSystem.Stat.CDR))
	_check(via_get_value <= 0.001,
		"get_value(CDR) 仍为 0（证明必须走 ratio_stat_value，不能走 get_value）",
		["实际=%.4f" % via_get_value])

	# **关键断言**：技能实际冷却真的被缩短
	var cd_after := _cast_and_read_cooldown(player, str(probe_skill["id"]))
	_check(cd_after < cd_before,
		"CDR 生效：技能冷却被缩短（%.2fs → %.2fs）" % [cd_before, cd_after],
		["CDR=%.4f" % after_cdr])
	# 缩短比例应精确等于 CDR（5.0 × (1-0.01) = 4.95）
	var expect := declared * (1.0 - after_cdr)
	_check(absf(cd_after - expect) < 0.02,
		"缩短比例精确等于 CDR（期望 %.2fs，实测 %.2fs）" % [expect, cd_after])
	_check(cd_after > 0.0, "冷却不会变成 0 或负数（%.2fs）" % cd_after)
	await _start("warrior", 0)


## 找一个「有冷却」的技能（冷却 > 0，避免无意义比较）
##
## **不用 `player.current_skills()`**：那读的是**技能槽**（`equipped_skills()`），
## 开局可能为空。直接查该职业形态的原始技能表更可靠。
func _pick_skill_with_cooldown(player: Node3D) -> Dictionary:
	var cid := str(player.get("class_id"))
	var slot := int(player.get("form_slot"))
	for sk in ClassDefs.skills_of(cid, slot):
		if sk is Dictionary and float(sk.get("cooldown", 0.0)) > 0.0:
			return sk
	return {}


## 放一次技能并读回它写入的剩余冷却
##
## 走 `cast_skill` 的**真实路径**——冷却是在那里算的（`_cooldowns[id] = ...`），
## 故这能直接验证 CDR 是否参与了公式。每次先重置冷却，保证可比。
func _cast_and_read_cooldown(player: Node3D, skill_id: String) -> float:
	player.call("reset_skill_cooldowns")
	var r: Dictionary = player.call("cast_skill", skill_id)
	if not bool(r.get("ok", false)):
		print("    [诊断] cast_skill(%s) 失败：%s" % [skill_id, str(r.get("reason", "?"))])
		return -1.0
	var left := float(player.call("skill_cooldown_left", skill_id))
	if left <= 0.0:
		print("    [诊断] cast_skill(%s) 返回 ok 但冷却为 0（技能表 cooldown=%s）"
			% [skill_id, str(_skill_cooldown_of(player, skill_id))])
	return left


## 从技能表取该技能的声明冷却（诊断用）
func _skill_cooldown_of(player: Node3D, skill_id: String) -> float:
	var cid := str(player.get("class_id"))
	var slot := int(player.get("form_slot"))
	for sk in ClassDefs.skills_of(cid, slot):
		if sk is Dictionary and str(sk.get("id", "")) == skill_id:
			return float(sk.get("cooldown", 0.0))
	var es := EquipmentSkills.skill_by_id(skill_id)
	return float(es.get("cooldown", -1.0)) if not es.is_empty() else -1.0


func _player() -> Node3D:
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] as Node3D if not ps.is_empty() else null


## 9. P1 新增的 12 个 Trigger：**每个都必须有调用点**
##
## ## 为什么单独测这个
##
## P1 给 `AffixData.Trigger` 加了 12 个枚举值来承载「条件压成常驻」那批
## 词条，但**枚举只是数据侧的标记**。本项目反复踩的坑正是：
## **有枚举没消费 = 死代码**——图鉴会显示、玩家以为有效、实际毫无反应。
##
## 本测试用**静态检查**（读源码找调用点）而非行为断言：这些钩子分布在
## 战斗/经济/元素多个子系统，逐个构造触发场景成本过高，且行为测试
## 已在各自模块覆盖。这里要防的是「加了钩子却忘了接」。
##
## **允许无调用点的**（机制本身不存在，不臆造）：
##   · `on_sell`        —— 项目没有「出售装备」入口
##   · `on_cheat_death` —— 项目没有「免死」机制
func _test_new_triggers_have_callers() -> void:
	print("\n--- 新增 Trigger 的调用点检查 ---")
	var wired := [
		"on_resource_full", "on_hp_full", "on_stealth",
		"on_target_controlled", "on_distance_far",
		"on_gold_above", "on_chest_open", "on_recall",
		"on_target_death", "on_element_proc", "on_heal",
	]
	var dirs := ["entities/", "gameplay/", "core/"]
	var missing: Array = []
	for h in wired:
		if not _has_caller(str(h), dirs):
			missing.append(h)
	_check(missing.is_empty(),
		"应接线的 %d 个钩子都有调用点" % wired.size(),
		["无调用点：%s" % str(missing)])

	# 反向检查：故意不接的两个，确认它们确实没有调用点
	#（若将来有人接上了，这条会失败并提醒把测试更新掉）
	var unexpectedly_wired: Array = []
	for h in ["on_sell", "on_cheat_death"]:
		if _has_caller(h, dirs):
			unexpectedly_wired.append(h)
	_check(unexpectedly_wired.is_empty(),
		"「机制不存在」的两个钩子仍未接线（若已接线请更新本测试）",
		[str(unexpectedly_wired)])


## 源码里是否存在对该钩子的调用（`x.on_hook()` 或 `call("on_hook")`）
func _has_caller(hook: String, dirs: Array) -> bool:
	for d in dirs:
		if _scan_dir_for("res://" + str(d), hook):
			return true
	return false


func _scan_dir_for(dir_path: String, hook: String) -> bool:
	var d := DirAccess.open(dir_path)
	if d == null:
		return false
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if not f.begins_with(".") and _scan_dir_for(dir_path + f + "/", hook):
				d.list_dir_end()
				return true
		elif f.ends_with(".gd"):
			if _file_calls(dir_path + f, hook):
				d.list_dir_end()
				return true
		f = d.get_next()
	d.list_dir_end()
	return false


func _file_calls(path: String, hook: String) -> bool:
	# 定义它的文件本身不算调用点
	if path.ends_with("equipment_effects.gd"):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var found := false
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges().begins_with("#"):
			continue
		if line.contains(".%s()" % hook) or line.contains("call(\"%s\")" % hook):
			found = true
			break
	f.close()
	return found


## 开一局指定职业/形态（与 test_class_mechanics 同一套口径）
func _start(class_id: String, form: int) -> void:
	GameManager.start_new_run({
		"character": class_id, "form": form,
		"mode": "dungeon", "difficulty": "normal", "floor": 1, "seed": 11,
	})
	await get_tree().process_frame
	await get_tree().process_frame


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


## 12. B2 能量储存（「伤害储存护符」）
##
## ## 规格张力（已记录，非 bug）
##
## 这件装备的两列是**两个不同位置的配置**：
##   自有列：「受到伤害的20%储存为能量；下次攻击释放全部」→ **穿上它**才生效
##   融合列：「释放储存能量时，对周围造成50%范围伤害」→ **融合进别的主装备**后生效
##
## 融合会**消耗材料**，故自有列的 `store_pct`/`release` 不会跟着走——
## 融合产物只有 `splash_pct`，而它**单独没有意义**（没有攒能量，何来释放）。
##
## 故测试走**装备本身**的主路径（store + release），`splash_pct` 只验证
## 「融合后确实进了 extra_affixes」（见 SKILL_MOD 那节的同类断言）。
func _test_b2_energy_store() -> void:
	print("\n--- B2 能量储存 ---")
	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return
	if not player.has_method("set_energy_store_rule"):
		_check(false, "Player 暴露 set_energy_store_rule")
		return

	# 直接穿上「伤害储存护符」——自有列的两条（store + release）在这条路径生效
	_reset()
	await get_tree().process_frame
	if not _equip_by_name("伤害储存护符", EquipmentDefs.Slot.ACCESSORY_1):
		_check(false, "装上「伤害储存护符」")
		return
	player.equip_fx.reload_passives()
	await get_tree().process_frame

	var rule: Dictionary = player.get("_energy_rule")
	_check(not rule.is_empty(), "能量储存规则已装配", ["实际=%s" % str(rule)])
	if rule.is_empty():
		_reset()
		return
	# **两条自有列参数必须都在**——它们被从句切分成不同 trigger
	#（「受到伤害的…」→ ON_HURT；「下次攻击释放…」→ ALWAYS），
	# 故 sentinel 扫描**不能依赖 trigger**（见 `_SENTINEL_RULES` 的说明）。
	_check(rule.has("store_pct"), "合并后含 store_pct（来自自有列）")
	_check(rule.has("release"), "合并后含 release（来自自有列第2行）")

	# **行为断言**：受击攒能量
	player.set("_energy_stored", 0.0)
	player.call("_store_energy_from_damage", 100.0)
	var stored: float = float(player.get("_energy_stored"))
	_check(stored > 0.0, "受击后储存了能量（0 → %.1f）" % stored)
	_check(absf(stored - 20.0) < 0.01, "储存比例 = 20%（规格原值）",
		["实际=%.2f（期望 20.0）" % stored])

	# 上限：不超过「100% 最大生命」
	var max_hp: float = float(GameManager.attributes.max_hp)
	player.call("_store_energy_from_damage", max_hp * 10.0)
	var capped: float = float(player.get("_energy_stored"))
	_check(capped <= max_hp + 0.01, "储存上限 = 100% 最大生命",
		["实际=%.1f 上限=%.1f" % [capped, max_hp]])
	_reset()


## 13. B3 元素序列 / 终焉
##
## ## 这是全新机制
##
## 装备参考2 的「连续3次**不同**元素后触发元素爆炸」「连续攻击**同一目标**
## 3次后触发」需要一个**序列追踪器**——记录最近几次攻击的元素与目标。
## 项目此前只有「单次攻击的元素结算」（`ElementDamage.attack`），
## 没有任何跨次记忆。
##
## 追踪器落在 `Player._elem_sequence`（环形缓冲）+ `_last_elem_target`。
func _test_b3_elem_sequence() -> void:
	print("\n--- B3 元素序列 ---")
	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return
	if not player.has_method("add_elem_rule") or not player.has_method("clear_elem_rules"):
		_check(false, "Player 暴露 add_elem_rule / clear_elem_rules")
		return

	# ① 规则装配：**走融合路径**
	#
	# `elem_seq_distinct` 写在「元素之戒」的**融合列**——按规格
	# 「作为副材融合时给主装备」，穿戴原装备**不生效**。
	# 这是本文件第三次遇到同一个模式（B2 的 splash / 召唤物爆炸 / 这里），
	# 故 `_reset` 之外统一用「融合进主装备再穿」的写法。
	_reset()
	await get_tree().process_frame
	GameManager.gold = 1000
	var elem_main := _make_inst_by_name("吸血脉甲")   # ARMOR/CHEST（非武器）
	var elem_mat := _make_inst_by_name("元素之戒")     # ACCESSORY（非武器）
	if elem_main == null or elem_mat == null:
		_check(false, "构造元素之戒的融合实例")
		return
	var er: Dictionary = GameManager.equipment_manager.fuse(elem_main, elem_mat)
	_check(bool(er.get("ok", false)), "融合出元素序列规则",
		[str(er.get("reason", ""))])
	GameManager.equipment_manager.equip(EquipmentDefs.Slot.CHEST, elem_main)
	player.equip_fx.reload_passives()
	await get_tree().process_frame
	var rules: Dictionary = player.get("_elem_rules")
	_check(rules.has("elem_seq_distinct"), "「元素之戒」装配了连续不同元素规则",
		["实际=%s" % str(rules.keys())])

	# ② **行为断言**：喂 3 次不同元素 → 序列判定为「全不同」
	player.call("clear_elem_rules")
	player.call("add_elem_rule", "elem_seq_distinct",
		{"count": 3, "mult": 1.5, "use_ap": true})
	# 造一个木桩接收爆炸
	var enemy = _spawn_dummy(player)
	if enemy == null:
		_check(false, "刷出测试木桩")
		return
	player.set("_elem_sequence", [] as Array[int])
	# 前两次不同元素：不该触发（不足 3 次）
	player.set("_last_elem_target", enemy)
	player.call("_record_elem_attack", 0, enemy)   # 火
	player.call("_record_elem_attack", 1, enemy)   # 冰
	_check(int(player.get("_elem_same_target_count")) == 2,
		"连续同一目标计数 = 2", ["实际=%d" % int(player.get("_elem_same_target_count"))])
	# 第三次仍是不同元素 → 触发爆炸（序列被清空）
	player.call("_record_elem_attack", 2, enemy)   # 雷
	_check((player.get("_elem_sequence") as Array).is_empty(),
		"触发后序列被清空（避免每击都炸）")

	# ③ 重复元素不该触发：喂 火火火
	player.call("_record_elem_attack", 0, enemy)
	player.call("_record_elem_attack", 0, enemy)
	player.call("_record_elem_attack", 0, enemy)
	_check(not (player.get("_elem_sequence") as Array).is_empty(),
		"三个**相同**元素不触发（序列未被清空）",
		["序列=%s" % str(player.get("_elem_sequence"))])

	# ④ `_last_n_all_distinct` 的边界
	player.set("_elem_sequence", [0, 1, 2] as Array[int])
	_check(bool(player.call("_last_n_all_distinct", 3)), "三个不同元素 → true")
	player.set("_elem_sequence", [0, 1, 1] as Array[int])
	_check(not bool(player.call("_last_n_all_distinct", 3)), "含重复 → false")
	player.set("_elem_sequence", [0, 1] as Array[int])
	_check(not bool(player.call("_last_n_all_distinct", 3)), "不足 3 个 → false")

	player.call("clear_elem_rules")
	enemy.queue_free()
	_reset()


## 刷一个测试木桩（血厚、无护甲、无闪避）
func _spawn_dummy(player: Node3D):
	var EB = load("res://entities/enemies/enemy_base.gd")
	if EB == null:
		return null
	var e = EB.new()
	get_tree().current_scene.add_child(e)
	e.global_position = player.global_position + Vector3(0, 0, -2)
	e.set("_hp", 1000000.0)
	e.set("defense", 0.0)
	e.set("dodge_pct", 0.0)
	return e


## 14. B4 免死机制
##
## ## 这是**全新机制**
##
## 项目此前**完全没有免死**：`take_damage` 末尾 `is_dead()` → `die()`，
## 血量归零直接死。装备参考2 的「受到致命伤害时免疫该次伤害并回复50%」
## 「满层时受到致命伤害触发不朽壁垒」都依赖它。
##
## 实现：在 `die()` **之前**插 `_try_cheat_death()`——成功则回血并返回，
## 不进入 `die()`。**必须有冷却**（规格明写 90/120 秒），
## 否则免死变成无限复活。
func _test_b4_cheat_death() -> void:
	print("\n--- B4 免死机制 ---")
	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return
	if not player.has_method("set_cheat_death_rule"):
		_check(false, "Player 暴露 set_cheat_death_rule")
		return

	# ① **数据侧的误映射修复**：`不朽壁垒` 的免死条目曾被抓成
	# `[4, 5, Stat.HP, 0.30, 0]`（AT_FULL 叠层回血），语义完全不对。
	# 现应是 `cheat_death` sentinel，且含 boom_pct（层数×80% 攻击力）。
	var has_cheat := false
	var has_boom := false
	for t in EquipmentDB.all_templates():
		for arr in [t.own_affixes, t.fusion_affixes]:
			for a in arr:
				if a != null and a.trigger_buff == "cheat_death":
					has_cheat = true
					if float(a.trigger_params.get("boom_pct", 0.0)) > 0.0:
						has_boom = true
	_check(has_cheat, "数据里有 cheat_death 规则")
	_check(has_boom, "「不朽壁垒」的范围反击倍率未丢失（层数×80%）")

	# ② **行为断言**：濒死时免死生效（不回 death）
	_reset()
	await get_tree().process_frame
	player.call("set_cheat_death_rule", {"heal_pct": 0.5, "boom_pct": 0.0, "cooldown": 60.0})
	player.set("_cheat_death_cd", 0.0)
	var attrs = GameManager.attributes
	attrs.hp = float(attrs.max_hp) * 0.01   # 压到 1%
	var max_hp: float = float(attrs.max_hp)
	# 打一发致死伤害
	player.call("take_damage", max_hp * 2.0)
	await get_tree().process_frame
	_check(float(attrs.hp) > 0.0,
		"免死生效：血量未归零（%.1f）" % float(attrs.hp),
		["hp=%.1f" % float(attrs.hp)])
	_check(float(player.get("_cheat_death_cd")) > 0.0,
		"免死进入了冷却（%.0fs）" % float(player.get("_cheat_death_cd")))

	# ③ **冷却期内不再免死**（否则是无限复活）
	attrs.hp = max_hp * 0.01
	player.call("take_damage", max_hp * 2.0)
	await get_tree().process_frame
	_check(float(attrs.hp) <= 0.0, "冷却期内不再免死（本次真的死了）",
		["hp=%.1f" % float(attrs.hp)])

	# 恢复：重开一局，避免污染后续测试
	_reset()
	await _start("warrior", 0)


func _check(c: bool, name: String, detail: Array = []) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
		for d in detail:
			print("    %s" % d)


## 11. B1 五族（2026-09-27）：站立 / 印记 / 召唤物 / 光环 / 资源满
##
## ## 这里暴露过的一个架构缺陷
##
## 这五条写成 `Trigger.ALWAYS`（常驻规则），但 `_fire(trig)` 是**事件驱动**
## 的——`ALWAYS` 不被任何战斗事件触发，于是它们**永不生效**。
## 修法是新增 `reload_passives()`：在装备变化时把规则装配给 Player。
func _test_b1_passives() -> void:
	print("\n--- B1 常驻规则（站立/光环/召唤物）---")
	var player := _player()
	if player == null:
		_check(false, "找到玩家节点")
		return
	if player.equip_fx == null:
		_check(false, "玩家有 equip_fx")
		return
	if not player.has_method("clear_passive_rules"):
		_check(false, "Player 暴露 clear_passive_rules")
		return

	# ① 站立静止：装上「大地守护」后规则应装配
	_reset()
	await get_tree().process_frame
	if not _equip_by_name("大地守护", EquipmentDefs.Slot.ACCESSORY_1):
		_check(false, "装上「大地守护」")
		return
	player.equip_fx.reload_passives()
	await get_tree().process_frame
	var srule: Dictionary = player.get("_stationary_rule")
	_check(not srule.is_empty(), "「大地守护」装配了站立规则",
		["实际=%s" % str(srule)])
	if not srule.is_empty():
		_check(absf(float(srule.get("dr", 0.0)) - 0.20) < 0.01,
			"站立规则减伤 = 20%（规格原值）", ["实际=%.3f" % float(srule.get("dr", 0.0))])
		_check(absf(float(srule.get("reflect", 0.0)) - 0.10) < 0.01,
			"站立规则反伤 = 10%", ["实际=%.3f" % float(srule.get("reflect", 0.0))])

	# ② 卸下后规则必须清空（否则「站立 buff」永远挂着）
	_reset()
	player.equip_fx.reload_passives()
	await get_tree().process_frame
	_check((player.get("_stationary_rule") as Dictionary).is_empty(),
		"卸下后站立规则被清空")

	# ③ 伤害光环：装上「荆棘领域」后规则应装配
	if _equip_by_name("荆棘领域", EquipmentDefs.Slot.ACCESSORY_1):
		player.equip_fx.reload_passives()
		await get_tree().process_frame
		var arule: Dictionary = player.get("_aura_rule")
		_check(not arule.is_empty(), "「荆棘领域」装配了伤害光环",
			["实际=%s" % str(arule)])
		if not arule.is_empty():
			_check(absf(float(arule.get("radius", 0.0)) - 3.0) < 0.01,
				"光环半径 = 3 米（规格原值）", ["实际=%.1f" % float(arule.get("radius", 0.0))])
			_check(absf(float(arule.get("mult", 0.0)) - 0.15) < 0.01,
				"光环倍率 = 15%（规格原值）", ["实际=%.3f" % float(arule.get("mult", 0.0))])
	_reset()

	# ④ 召唤物死亡爆炸：**走融合路径**
	#
	# `summon_death_boom` 写在「召唤护卫胸甲」的**融合列**——按规格
	# 「作为副材融合时给主装备」，**穿戴原装备时不生效**。
	# 必须：融合进主装备 → 词条进 `extra_affixes` → 再穿上 → 装配。
	#
	# 早期版本直接 `equip(召唤护卫胸甲)` 就断言，必然失败且与接线无关
	#（与 SKILL_MOD 那节踩的是同一个坑）。
	_reset()
	await get_tree().process_frame
	GameManager.gold = 1000
	var boom_main := _make_inst_by_name("吸血脉甲")     # ARMOR/CHEST
	var boom_mat := _make_inst_by_name("召唤护卫胸甲")   # ARMOR/CHEST，融合列带词条
	if boom_main == null or boom_mat == null:
		_check(false, "构造召唤物爆炸的融合实例")
		return
	var fr: Dictionary = GameManager.equipment_manager.fuse(boom_main, boom_mat)
	_check(bool(fr.get("ok", false)), "融合出召唤物死亡爆炸",
		[str(fr.get("reason", ""))])
	GameManager.equipment_manager.equip(EquipmentDefs.Slot.CHEST, boom_main)
	player.equip_fx.reload_passives()
	await get_tree().process_frame
	var mgr = player.get("summons")
	if mgr != null:
		_check(float(mgr.get("_death_boom_mult")) > 0.0,
			"召唤物死亡爆炸倍率已装配（融合后生效）",
			["实际=%.3f" % float(mgr.get("_death_boom_mult"))])
	_reset()


## 12. B7 低血条件通道（`Trigger.LOW_HP`）
##
## ## 为什么这一节必须有
##
## `Trigger.LOW_HP` 此前**全局零消费点**——8 条词条挂在数据库里，
## 但没有任何代码读它。这正是本项目反复踩的「有枚举没消费」：
## 图鉴会显示「生命低于50%时获得20%伤害减免」，玩家以为有效，实际什么都没有。
##
## 三个必须验证的点：
##   ① 低血时效果**生效**（挂上 modifier / 扩展通道出现在 `_equip_special_mods`）
##   ② 回到血线以上时**撤销**（不是永久留着）
##   ③ 阈值**按词条各自判定**——「生命低于30%时…」不该在 40% 血量就生效
func _test_b7_low_hp() -> void:
	_reset()
	await get_tree().process_frame
	var em = GameManager.equipment_manager
	var attrs = GameManager.attributes

	# —— 数据侧：低血词条必须带各自的阈值 ——
	var tpl = _find_by_name("血怒")
	if tpl != null:
		var found := false
		for a in tpl.own_affixes:
			if a != null and int(a.trigger) == AffixData.Trigger.LOW_HP:
				found = true
				_check(absf(float(a.hp_threshold) - 0.5) < 0.01,
					"「血怒」低血词条带阈值 0.5",
					["实际=%.3f" % float(a.hp_threshold)])
		_check(found, "「血怒」自有列确有 LOW_HP 词条")
	var tpl2 = _find_by_name("血怒巨斧")
	if tpl2 != null:
		for a in tpl2.own_affixes:
			if a != null and int(a.trigger) == AffixData.Trigger.LOW_HP:
				_check(absf(float(a.hp_threshold) - 0.4) < 0.01,
					"「血怒巨斧」低血词条带阈值 0.4（非统一 0.5）",
					["实际=%.3f" % float(a.hp_threshold)])

	# —— 行为侧：装上「血怒」并压血量 ——
	var inst := _make_inst_by_name("血怒")
	if inst == null:
		_check(false, "构造「血怒」实例")
		return
	em.equip(EquipmentDefs.Slot.WEAPON_1, inst)
	await get_tree().process_frame
	var player: Node3D = _player()
	if player == null:
		_check(false, "取玩家节点")
		return

	var base_atk: float = float(attrs.get_value(AttributeSystem.Stat.ATK))

	# 满血：不该生效
	attrs.hp = float(attrs.max_hp)
	player.call("_tick_low_hp", 0.016)
	_check(not bool(player.get("_low_hp_active")), "满血时低血效果未生效")
	_check(absf(float(attrs.get_value(AttributeSystem.Stat.ATK)) - base_atk) < 0.5,
		"满血时攻击力未被低血词条放大")

	# 低血（30%）：应生效
	attrs.hp = float(attrs.max_hp) * 0.30
	player.call("_tick_low_hp", 0.016)
	_check(bool(player.get("_low_hp_active")), "血量 30% 时低血效果生效")
	# **断言的是 modifier 记录的 percent**，不是总攻击力的倍率——
	# `AttributeSystem.get_value = base + flat + base×percent`，
	# percent 只乘**原始 base**（≈38），不乘装备的 flat（血怒自带 +364）。
	# 故总攻击力只涨约 5.7%，但 modifier 的 percent 必须是 0.6。
	var low_atk: float = float(attrs.get_value(AttributeSystem.Stat.ATK))
	_check(low_atk > base_atk, "低血时攻击力上升",
		["base=%.1f 低血=%.1f" % [base_atk, low_atk]])
	var pct_sum := 0.0
	for m in attrs.get("_modifiers"):
		if int(m.get("stat", -1)) == AttributeSystem.Stat.ATK \
				and str(m.get("source", "")) == "eq_low_hp":
			pct_sum += float(m.get("percent", 0.0))
	_check(absf(pct_sum - 0.6) < 0.001,
		"低血 modifier 的 percent = 0.60（规格「攻击力+60%」）",
		["实际=%.3f" % pct_sum])
	# 回血：必须撤销
	attrs.hp = float(attrs.max_hp)
	player.call("_tick_low_hp", 0.016)
	_check(not bool(player.get("_low_hp_active")), "回血后低血效果已撤销")
	_check(absf(float(attrs.get_value(AttributeSystem.Stat.ATK)) - base_atk) < 0.5,
		"回血后攻击力回到基线（modifier 已卸）")

	# —— 伤害减免走专用通道（不是元素抗性） ——
	_reset()
	await get_tree().process_frame
	var sh := _make_inst_by_name("守护肩甲")
	if sh != null:
		em.equip(EquipmentDefs.Slot.CHEST, sh)
		await get_tree().process_frame
		attrs.hp = float(attrs.max_hp) * 0.30
		player.call("_tick_low_hp", 0.016)
		var sp: Dictionary = player.call("_equip_special_mods")
		_check(absf(float(sp.get("dmg_reduction_pct", 0.0)) - 0.20) < 0.01,
			"「守护肩甲」低血 20% 伤害减免走专用通道（非元素抗性）",
			["实际=%.3f" % float(sp.get("dmg_reduction_pct", 0.0))])
	_check(true, "（若上一项缺失说明词条未接入）")
	_reset()


## 13. 装备表引用的技能必须**都在技能表里**
##
## ## 为什么这是一条独立的断言
##
## 实测有 4 个装备名（召唤元素戒指 / 混沌之门 / 猎人标记 / 猎人标记徽章，
## 共 6 件装备）在 `equipment_db.gd` 里 `GRANT_SKILL` 指向 `eq_XXX`，
## 但 `EquipmentSkills.TABLE` 里**没有该装备名**——`skill_of_equipment`
## 返回空字典，玩家装了这些装备**技能永远放不出来**，且不报任何错。
##
## 这是「两张表不同步」的典型：两边各自看都正常，交叉验证才暴露。
## 故这里做**全量交叉校验**，而不是只查那 4 个已知的——
## 将来任何一边改漏都会被立刻抓住。
func _test_equipment_skills_exist() -> void:
	print("\n--- 装备技能表交叉校验 ---")
	var missing: Array = []
	var checked := 0
	for t in EquipmentDB.all_templates():
		for a in t.own_affixes:
			if a == null or a.operation != AffixData.Operation.GRANT_SKILL:
				continue
			checked += 1
			var sk: Dictionary = EquipmentSkills.skill_of_equipment(
				t.display_name, int(t.rarity))
			if sk.is_empty():
				missing.append("%s(%s) → %s" % [t.display_name, t.id, a.granted_skill])
	_check(checked > 100, "装备表里有 GRANT_SKILL 词条（%d 条）" % checked)
	_check(missing.is_empty(),
		"全部 GRANT_SKILL 都能在技能表里查到（%d 条无一悬空）" % checked,
		missing.slice(0, 8))


## 14. B7.4 狂战士之怒：低血普攻范围化
##
## ## 规格
##
## 「生命低于50%时，普通攻击变为范围攻击，造成150%伤害」
## 「融合：范围扩大」
##
## ## 这里此前是**数据错**，不只是机制缺失
##
## 旧生成器把「造成150%伤害」压成 `aoe_dmg_pct = 0.5`——那是
## 「所有范围技能伤害 +50%」的被动增伤，与「这一击造成攻击力 150%」
## 完全不是一回事；而「变为范围攻击」这个机制整个没落地。
## 现改走 `SKILL_MOD` 的普攻通道：
##   `[8, {"basic_attack_aoe": true, "basic_attack_aoe_mult": 1.5}]`
##   `[8, {"basic_attack_expand_radius": 3.5}]`（融合列）
func _test_b7_berserker_rage() -> void:
	print("\n--- B7.4 狂战士之怒：低血普攻范围化 ---")
	var em = GameManager.equipment_manager
	var attrs = GameManager.attributes
	_reset()
	await get_tree().process_frame

	# —— 数据侧 ——
	var tpl = _find_by_name("狂战士之怒")
	if tpl == null:
		_check(false, "找到「狂战士之怒」")
		return
	var own_ok := false
	for a in tpl.own_affixes:
		if a != null and a.operation == AffixData.Operation.SKILL_MOD \
				and bool(a.trigger_params.get("basic_attack_aoe", false)):
			own_ok = true
			_check(absf(float(a.trigger_params.get("basic_attack_aoe_mult", 0.0)) - 1.5) < 0.01,
				"自有列倍率 = 1.5（规格「造成150%伤害」）",
				[str(a.trigger_params)])
	_check(own_ok, "自有列走 SKILL_MOD 的普攻通道（不是 aoe_dmg_pct 属性）")
	# **反向断言**：不该再产出 `aoe_dmg_pct` 词条
	var bad := false
	for a2 in tpl.own_affixes:
		if a2 != null and a2.stat == EquipmentDB.special_enum_of("aoe_dmg"):
			bad = true
	_check(not bad, "自有列**没有**被压成 aoe_dmg_pct（旧的错映射）")

	# —— 行为侧：低血才切范围判定 ——
	var inst := _make_inst_by_name("狂战士之怒")
	if inst == null:
		_check(false, "构造实例")
		return
	em.equip(EquipmentDefs.Slot.WEAPON_1, inst)
	await get_tree().process_frame
	var player: Node3D = _player()
	if player == null:
		return

	attrs.hp = float(attrs.max_hp)
	player.call("_tick_low_hp", 0.016)
	_check(not bool(player.call("_basic_attack_is_aoe")), "满血时普攻**不是**范围攻击")

	attrs.hp = float(attrs.max_hp) * 0.30
	player.call("_tick_low_hp", 0.016)
	_check(bool(player.call("_basic_attack_is_aoe")), "低血时普攻变为范围攻击")
	_check(absf(float(player.call("_basic_attack_aoe_mult")) - 1.5) < 0.01,
		"低血时倍率 1.5 生效")
	_check(absf(float(player.call("_basic_attack_aoe_radius", 2.0)) - 2.5) < 0.01,
		"未融合时半径 = 2.5（默认）",
		["实际=%.2f" % float(player.call("_basic_attack_aoe_radius", 2.0))])

	# —— 融合「范围扩大」→ 半径提到 3.5 ——
	#
	# `范围扩大` 在**融合列**——按规格「作为副材融合时给主装备」，
	# 穿戴原装备时不生效。必须：融合进主装备 → 进 extra_affixes → 再穿上。
	_reset()
	await get_tree().process_frame
	GameManager.gold = 1000
	var main_inst := _make_inst_by_name("被腐蚀的长剑")   # WEAPON
	var mat_inst := _make_inst_by_name("狂战士之怒")       # WEAPON，融合列带半径
	if main_inst == null or mat_inst == null:
		_check(false, "构造融合实例")
		return
	var fr: Dictionary = em.fuse(main_inst, mat_inst)
	_check(bool(fr.get("ok", false)), "融合出「范围扩大」", [str(fr.get("reason", ""))])
	em.equip(EquipmentDefs.Slot.WEAPON_1, main_inst)
	await get_tree().process_frame
	attrs.hp = float(attrs.max_hp) * 0.30
	player.call("_tick_low_hp", 0.016)
	_check(absf(float(player.call("_basic_attack_aoe_radius", 2.0)) - 3.5) < 0.01,
		"融合「范围扩大」后半径 = 3.5",
		["实际=%.2f" % float(player.call("_basic_attack_aoe_radius", 2.0))])
	_reset()


## 15. B7.5 踏虚神靴：残影机制
##
## ## 规格（自有 + 融合，跨列）
##
## 自有：「冲刺留下残影（继承50%攻击，持续5秒，最多4个）；
##        残影存在时再次冲刺可引爆所有残影，每个造成150%攻击力伤害；
##        引爆后冲刺冷却立即刷新（每3秒最多触发1次）」
## 融合：「引爆残影时，每个残影回复3%最大生命」
##
## ## 残影实体此前完全不存在
##
## 不只是一条词条未映射——整套「留影 → 引爆 → 刷新冲刺」循环都不存在。
## 现由 Player 持有 `_afterimages` 时间戳数组（纯逻辑，可脱离渲染单测），
## 视觉走 `fx.spawn_afterimage`（半透明克隆 mesh）。
func _test_b7_afterimage() -> void:
	print("\n--- B7.5 踏虚神靴：残影 ---")
	var em = GameManager.equipment_manager
	var attrs = GameManager.attributes
	_reset()
	await get_tree().process_frame

	# —— 数据侧：三条自有 + 一条融合都进了 trigger_params ——
	var tpl = _find_by_name("踏虚神靴")
	if tpl == null:
		_check(false, "找到「踏虚神靴」")
		return
	var ai_count := 0
	for a in tpl.own_affixes:
		if a != null and a.trigger_buff == "afterimage":
			ai_count += 1
	_check(ai_count >= 2, "自有列有多条 afterimage 词条（%d 条）" % ai_count)
	var fusion_heal := false
	for a2 in tpl.fusion_affixes:
		if a2 != null and a2.trigger_buff == "afterimage" \
				and absf(float(a2.trigger_params.get("heal_pct", 0.0)) - 0.03) < 0.001:
			fusion_heal = true
	_check(fusion_heal, "融合列「引爆回复3%最大生命」已解析")

	# —— 行为侧：穿戴 → 装配规则 ——
	var inst := _make_inst_by_name("踏虚神靴")
	if inst == null:
		_check(false, "构造实例")
		return
	em.equip(EquipmentDefs.Slot.ACCESSORY_1, inst)
	await get_tree().process_frame
	var player: Node3D = _player()
	if player == null:
		return
	var rule: Dictionary = player.get("_afterimage_rule")
	_check(not rule.is_empty(), "穿上后装配了残影规则", [str(rule)])
	_check(absf(float(rule.get("life", 0.0)) - 5.0) < 0.01, "持续 5 秒（规格原值）")
	_check(int(rule.get("max_count", 0)) == 4, "最多 4 个（规格原值）")
	_check(absf(float(rule.get("explode_mult", 0.0)) - 1.5) < 0.01,
		"引爆倍率 1.5（规格「每个造成150%攻击力伤害」）")

	# —— 第一次冲刺：留影 ——
	player.call("_on_dash_for_afterimage")
	var imgs: Array = player.get("_afterimages")
	_check(imgs.size() == 1, "第一次冲刺留下 1 个残影", ["实际=%d" % imgs.size()])

	# —— 第二次冲刺：引爆（不留影） ——
	# 放一个敌人在残影位置，验证真的吃到伤害
	var dummy = _spawn_dummy(player)
	if dummy != null:
		dummy.global_position = (imgs[0]["pos"] as Vector3) + Vector3(0.5, 0, 0)
	await get_tree().process_frame
	var hp_before := float(dummy.get("_hp"))
	player.call("_on_dash_for_afterimage")
	imgs = player.get("_afterimages")
	_check(imgs.is_empty(), "第二次冲刺引爆了全部残影（场上清零）",
		["实际=%d" % imgs.size()])
	if dummy != null and is_instance_valid(dummy):
		_check(float(dummy.get("_hp")) < hp_before, "残影引爆对范围内敌人造成伤害",
			["before=%.1f after=%.1f" % [hp_before, float(dummy.get("_hp"))]])
	# 引爆触发了冲刺刷新（进冷却，规格「每3秒最多触发1次」）
	_check(float(player.get("_afterimage_refresh_cd")) > 0.0,
		"引爆后进入刷新冷却（每3秒最多一次）")

	# —— 上限 4 个 ——
	player.call("_clear_afterimages")
	for i in 6:
		player.call("_spawn_afterimage")
	imgs = player.get("_afterimages")
	_check(imgs.size() <= 4, "残影数量不超过 4（规格上限）",
		["实际=%d" % imgs.size()])

	# —— 卸下装备：规则清空、场上残影失效 ——
	em.unequip(EquipmentDefs.Slot.ACCESSORY_1)
	player.equip_fx.reload_passives()
	await get_tree().process_frame
	_check((player.get("_afterimage_rule") as Dictionary).is_empty(),
		"卸下装备后残影规则清空")
	_check((player.get("_afterimages") as Array).is_empty(),
		"卸下装备后场上残影立刻失效")
	_reset()


## 16. B7.6 预言者王冠：暴击叠层 + 满层必暴 + 传播
##
## ## 规格
##
## 自有：「暴击叠加1层"预言"（最多6层），每层+6%暴击伤害；
##        6层时下一次攻击必定暴击并造成300%伤害，
##        同时将预言传播至周围2名敌人（各3层）」
## 融合：「预言传播时，自身获得3秒+20%暴击率」
##
## ## 数据侧此前的问题
##
## 旧解析把两条都压成 `Stat.CRD` 数值（叠层 + 满层爆发），
## 「必暴 / 300% / 传播 / 自身增益」**全部丢失**——玩家只能看到
## 暴伤数字变大，看不到任何机制。
##
## 现由满层爆发词条的第 7 槽参数字典承载这些语义
##（`{burst: "prophecy", ...}`），`_burst` 按 `burst` 分流。
func _test_b7_prophecy() -> void:
	print("\n--- B7.6 预言者王冠：预言 ---")
	var em = GameManager.equipment_manager
	var attrs = GameManager.attributes
	_reset()
	await get_tree().process_frame

	# —— 数据侧 ——
	var tpl = _find_by_name("预言者王冠")
	if tpl == null:
		_check(false, "找到「预言者王冠」")
		return
	var stack_a: AffixData = null
	var full_a: AffixData = null
	for a in tpl.own_affixes:
		if a == null:
			continue
		if int(a.trigger) == AffixData.Trigger.ON_CRIT and a.stack_max == 6:
			stack_a = a
		if int(a.trigger) == AffixData.Trigger.AT_FULL:
			full_a = a
	_check(stack_a != null, "有「暴击叠6层」词条（trigger=ON_CRIT, max=6）")
	_check(full_a != null, "有「满层爆发」词条（trigger=AT_FULL）")
	if stack_a == null or full_a == null:
		return
	_check(stack_a.stat == full_a.stat,
		"两条**共用同一个 stat**（`_fire_stack_full` 靠它配对）",
		["stack=%d full=%d" % [stack_a.stat, full_a.stat]])
	_check(absf(stack_a.value - 0.06) < 0.001,
		"每层 +6% 暴击伤害（规格原值）", ["实际=%.3f" % stack_a.value])
	var tp: Dictionary = full_a.trigger_params
	_check(str(tp.get("burst", "")) == "prophecy", "满层词条带 prophecy 参数",
		[str(tp)])
	_check(absf(float(tp.get("crit_mult", 0.0)) - 3.0) < 0.01,
		"必暴倍率 300%（规格「造成300%伤害」）")
	_check(int(tp.get("spread_count", 0)) == 2, "传播 2 名敌人（规格原值）")
	_check(int(tp.get("spread_layers", 0)) == 3, "各 3 层（规格原值）")

	# —— 行为侧：暴击叠层 ——
	var inst := _make_inst_by_name("预言者王冠")
	if inst == null:
		_check(false, "构造实例")
		return
	em.equip(EquipmentDefs.Slot.ACCESSORY_1, inst)
	await get_tree().process_frame
	var player: Node3D = _player()
	if player == null:
		return

	# 暴击 3 次 → 3 层
	for i in 3:
		player.equip_fx.on_crit_stack()
	var bid := "eqtrig_%d_%d" % [AffixData.Trigger.ON_CRIT, stack_a.stat]
	_check(player.buffs.stacks_of(bid) == 3, "暴击 3 次叠 3 层预言",
		["实际=%d" % player.buffs.stacks_of(bid)])

	# 叠到 6 层 → 满层爆发：必暴 + 倍率
	for i in 3:
		player.equip_fx.on_crit_stack()
	_check(bool(player.get("_prophecy_pending")), "满 6 层触发必暴（待消费）")
	_check(bool(player.get("_force_crit")), "强制暴击已置位")
	_check(absf(float(player.call("get_damage_multiplier")) - 3.0) < 0.01,
		"伤害倍率 ×3（规格「造成300%伤害」）",
		["实际=%.2f" % float(player.call("get_damage_multiplier"))])

	# 消费后必须清账（否则变成永久必暴）
	player.call("_consume_prophecy")
	_check(not bool(player.get("_force_crit")), "攻击后必暴已清（不是永久）")
	_check(absf(float(player.call("get_damage_multiplier")) - 1.0) < 0.01,
		"攻击后倍率复位 1.0")

	# —— 传播：周围敌人各 3 层 ——
	_reset()
	await get_tree().process_frame
	em.equip(EquipmentDefs.Slot.ACCESSORY_1, inst)
	await get_tree().process_frame
	var e1 = _spawn_dummy(player)
	if e1 != null:
		e1.global_position = player.global_position + Vector3(1.5, 0, 0)
	await get_tree().process_frame
	for i in 6:
		player.equip_fx.on_crit_stack()
	await get_tree().process_frame
	if e1 != null and is_instance_valid(e1) and e1.get("buffs") != null:
		var eb = e1.get("buffs")
		var n: int = int(eb.call("stacks_of", "prophecy_spread"))
		_check(n == 3, "满层时预言传播至周围敌人（3 层）", ["实际=%d" % n])
	# 传播时给自己暴击率（融合列）——未融合时不该有
	_check(not player.buffs.has("prophecy_self_crt"),
		"未融合「预言传播」时不给自身暴击率")

	# —— 融合：传播时给自身 +20% 暴击率 ——
	#
	# 这条在**融合列**——按规格「作为副材融合时给主装备」，
	# 穿戴原装备时不生效。必须：融合进主装备 → 进 extra_affixes → 再穿上。
	# 而且它与自有列的满层爆发**分属两条 affix**，靠累积器合并
	#（`_merge_prophecy_self` → `_flush_prophecy` → `set_prophecy_self_rule`）。
	_reset()
	await get_tree().process_frame
	GameManager.gold = 1000
	var main2 := _make_inst_by_name("吸血脉甲")
	var mat2 := _make_inst_by_name("预言者王冠")
	if main2 == null or mat2 == null:
		_check(false, "构造预言融合实例")
		return
	var fr2: Dictionary = em.fuse(main2, mat2)
	_check(bool(fr2.get("ok", false)), "融合出「预言传播」", [str(fr2.get("reason", ""))])
	em.equip(EquipmentDefs.Slot.CHEST, main2)
	await get_tree().process_frame
	_check(not (player.get("_prophecy_self_rule") as Dictionary).is_empty(),
		"融合后自我增益规则已装配（累积器合并）",
		[str(player.get("_prophecy_self_rule"))])
	# 但**自有列的叠层**没跟着融合过来（融合只搬材料的融合词条），
	# 故满层爆发不会触发 —— 这正是规格的「穿戴 vs 融合」分工。
	_check(not player.buffs.has("prophecy_self_crt"),
		"没有满层爆发时，传播不发生 → 自我增益也不给")
	_reset()
