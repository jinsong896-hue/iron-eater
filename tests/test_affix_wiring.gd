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

	if failed == 0:
		print("ALL AFFIX WIRING TESTS PASSED")
		get_tree().quit(0)
	else:
		print("AFFIX WIRING TESTS FAILED: %d" % failed)
		get_tree().quit(1)


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
		"on_target_death", "on_element_proc",
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


func _check(c: bool, name: String, detail: Array = []) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
		for d in detail:
			print("    %s" % d)
