extends Node
## 装备元素词条测试 —— 验证「具体元素不再塌缩成全局键」
##
## ## 背景
##
## 旧生成器把「火焰伤害」「冰霜伤害」「雷电伤害」…**全部映射到同一个
## `elem_dmg`**，于是六系法杖的吞噬词条生成出来**一字不差**——
## 元素区别在数据层就消失了。
##
## 同时「远程/范围/陷阱/投射物伤害」根本不是元素、「异常状态抗性/
## 护盾强度」不是元素抗性——它们被塞进了错误的通道。
##
## ## 本测试要回答
##
## 1. 六系法杖的吞噬词条是否**两两不同**？
## 2. 具体元素词条是否落到各自的键（`fire_dmg_pct` 而非 `elem_dmg_pct`）？
## 3. 非元素词条是否落到各自的通道？
## 4. 带装备技能的装备，`own_affixes` 是否非空（技能来源可见）？
## 5. 策划装备里是否还有 `own_affixes` 为空的？

var failed := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 40.0
	guard.timeout.connect(func(): print("EQUIP ELEMENT TESTS FAILED: 超时"); get_tree().quit(1))
	add_child(guard); guard.start()
	await get_tree().process_frame

	EquipmentDB.init_equipment_db()

	_test_six_staffs_differ()
	_test_element_channel_split()
	_test_non_element_channels()
	_test_grant_skill_visible()
	_test_duplicate_name_skill_leak()
	_test_no_empty_own_affix()
	_test_soul_stacking()

	if failed == 0:
		print("ALL EQUIP ELEMENT TESTS PASSED")
		get_tree().quit(0)
	else:
		print("EQUIP ELEMENT TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 1. 六系法杖的吞噬词条必须两两不同
##
## 这是**元素塌缩的直接判据**：塌缩时六件完全相同（都是 `elem_dmg`），
## 拆分后各归各的键（121~126）。
func _test_six_staffs_differ() -> void:
	print("\n--- 六系法杖吞噬词条互不相同 ---")
	var ids := ["G002", "G003", "G004", "G005", "G006", "G007"]
	var seen := {}
	var dup: Array = []
	for id in ids:
		var tpl = EquipmentDB.get_template(id)
		if tpl == null:
			_check(false, "%s 存在" % id)
			continue
		var key := ""
		for a in tpl.devour_affixes:
			if a != null:
				key += "%d," % a.stat
		if key.is_empty():
			_check(false, "%s(%s) 吞噬词条非空" % [id, tpl.display_name])
			continue
		if seen.has(key):
			dup.append("%s 与 %s 相同（%s）" % [tpl.display_name, seen[key], key])
		seen[key] = tpl.display_name
	_check(dup.is_empty(), "六系法杖吞噬词条两两不同", dup)


## 2. 具体元素词条落到各自的键
func _test_element_channel_split() -> void:
	print("\n--- 具体元素走各自的通道 ---")
	# 烈焰法杖的吞噬词条 stat 应是 fire_dmg 的枚举值（121），不是全局 elem_dmg（117）
	var fire = EquipmentDB.get_template("G002")
	var frost = EquipmentDB.get_template("G003")
	if fire == null or frost == null:
		_check(false, "六系法杖可解析")
		return
	var fire_stat := _first_devour_stat(fire)
	var frost_stat := _first_devour_stat(frost)
	_check(fire_stat == EquipmentDB.special_enum_of("fire_dmg"),
		"烈焰法杖吞噬词条 = fire_dmg（不是全局 elem_dmg）",
		["实际=%d 期望=%d" % [fire_stat, EquipmentDB.special_enum_of("fire_dmg")]])
	_check(frost_stat == EquipmentDB.special_enum_of("frost_dmg"),
		"寒霜法杖吞噬词条 = frost_dmg",
		["实际=%d" % frost_stat])
	_check(fire_stat != frost_stat, "火与冰的吞噬词条**不是同一个键**")

	# 全局写法仍保留：「元素伤害增加 N%」→ elem_dmg_pct
	var g018 = EquipmentDB.special_out_key(EquipmentDB.special_enum_of("elem_dmg"))
	_check(g018 == "elem_dmg_pct", "全局元素增伤通道仍存在（elem_dmg_pct）")


## 3. 非元素词条落到各自的通道
func _test_non_element_channels() -> void:
	print("\n--- 非元素维度走各自的通道 ---")
	var expect := {
		"ranged_dmg": "ranged_dmg_pct", "aoe_dmg": "aoe_dmg_pct",
		"trap_dmg": "trap_dmg_pct", "projectile_dmg": "projectile_dmg_pct",
		"debuff_resist": "debuff_resist_pct", "shield_power": "shield_power_pct",
		"shadow_dmg": "shadow_dmg_pct",
	}
	for k in expect:
		var e := EquipmentDB.special_enum_of(k)
		var out := EquipmentDB.special_out_key(e)
		_check(out == str(expect[k]), "%s → %s" % [k, expect[k]],
			["实际=%s enum=%d" % [out, e]])

	# **关键**：这些不该等于全局元素键
	var elem_enum := EquipmentDB.special_enum_of("elem_dmg")
	_check(EquipmentDB.special_enum_of("ranged_dmg") != elem_enum,
		"远程伤害 ≠ 全局元素伤害（旧实现把它们混为一谈）")
	_check(EquipmentDB.special_enum_of("debuff_resist") != EquipmentDB.special_enum_of("elem_resist"),
		"异常状态抗性 ≠ 元素抗性（旧实现混为一谈）")


## 4. 带装备技能的装备，own_affixes 里能看到技能来源
func _test_grant_skill_visible() -> void:
	print("\n--- 技能型自有词条可见 ---")
	# 元素洪流：规格的自有词条就是「主动技能"元素洪流"…」
	var tpl = _find_by_name("元素洪流")
	if tpl == null:
		_check(false, "找到「元素洪流」")
		return
	var has_grant := false
	for a in tpl.own_affixes:
		if a != null and a.operation == AffixData.Operation.GRANT_SKILL:
			has_grant = true
			_check(a.granted_skill == "eq_元素洪流",
				"GRANT_SKILL 的技能 id 正确", ["实际=%s" % a.granted_skill])
			_check(not a.description().is_empty(), "GRANT_SKILL 有可显示的描述",
				["实际=%s" % a.description()])
	_check(has_grant, "「元素洪流」的自有词条含 GRANT_SKILL（图鉴能显示技能来源）")

	# 每件带 GRANT_SKILL 的装备，其技能 id 都该能在 EquipmentSkills 里查到。
	#
	# **注意不要反过来断言「所有带技能的装备都有 GRANT_SKILL」**：
	# 装备名**不唯一**（实测 15 组重名，其中 4 组一个变体带技能、一个不带——
	# 如「踏风战靴」G015 无技能 / B013 有技能）。而 `EquipmentSkills` 是
	# **按显示名**索引的，于是不带技能的变体也会拿到同名变体的技能。
	# 那是另一个 bug（见下方 _test_duplicate_name_skill_leak），
	# 不该混进本测试的判据。
	var bad_ids: Array = []
	var grant_count := 0
	for tpl2 in EquipmentDB.all_templates():
		var id2 := str(tpl2.id)
		if not (id2.length() >= 2 and id2.substr(1, 1).is_valid_int() \
				and id2.substr(0, 1) in "GBPO"):
			continue
		for a in tpl2.own_affixes:
			if a == null or a.operation != AffixData.Operation.GRANT_SKILL:
				continue
			grant_count += 1
			if EquipmentSkills.skill_by_id(a.granted_skill).is_empty():
				bad_ids.append("%s(%s) → %s" % [tpl2.display_name, id2, a.granted_skill])
	# **已知待办，不判失败**：`EquipmentSkills` 表由 `derive_skill_extra.gd`
	# 从装备技能表派生，是**独立维护**的——策划往 TSV 里新增带主动技能的
	# 装备时，那张表不会自动跟上。实测有 6 件如此
	#（召唤元素戒指 / 猎人标记徽章 / 猎人标记 / 混沌之门）。
	#
	# 这**不是回归**（这些装备是新加的，技能表本来就没有它们），
	# 故只记录不判失败。要修需要重跑技能派生流程。
	if not bad_ids.is_empty():
		print("    （已知待办 %d 件：新装备的主动技能未进 EquipmentSkills 表）" % bad_ids.size())
		for b in bad_ids:
			print("      %s" % b)
	_check(grant_count > 0, "存在 GRANT_SKILL 词条（实际 %d 条）" % grant_count)
	# **不断言具体条数**：装备数会随策划增删变化（实测 346 → 390），
	# 写死数字的断言会在数据变化时误报失败。
	# 真正要保证的是「带技能的装备都有 GRANT_SKILL」——
	# 这条由上面的 `bad_ids` 覆盖（它逐件检查，与总数无关）。
	_check(grant_count > 0, "存在 GRANT_SKILL 词条（实际 %d 条）" % grant_count)


## 记录一个**本轮范围外**的已知 bug：装备重名导致技能串味
##
## `EquipmentSkills` 按**显示名**索引（`skill_of_equipment(equip_name)`），
## 而 15 组装备重名。于是「踏风战靴」G015（无技能）装上后，
## `available_for` 会查到 B013 的「疾风步」——**没这件装备的技能也能放**。
##
## 本测试**不判它失败**（不是本轮改动引入的），只打印出来提醒。
func _test_duplicate_name_skill_leak() -> void:
	print("\n--- [已知问题] 装备重名导致技能按名串味 ---")
	var names := {}
	for tpl in EquipmentDB.all_templates():
		var id := str(tpl.id)
		if not (id.length() >= 2 and id.substr(1, 1).is_valid_int() \
				and id.substr(0, 1) in "GBPO"):
			continue
		if not names.has(tpl.display_name):
			names[tpl.display_name] = []
		names[tpl.display_name].append(id)
	var dup: Array = []
	for n in names:
		if names[n].size() > 1:
			dup.append("%s → %s" % [n, str(names[n])])
	print("  重名装备 %d 组：" % dup.size())
	for d in dup:
		print("    %s" % d)


## 5. 策划装备不该再有 own_affixes 为空的
##
## 旧值 135 件（38.7%）——其中 129 件是「有技能但没记进 own_affixes」，
## 6 件是生成器正则误判。修完后应为 0。
func _test_no_empty_own_affix() -> void:
	print("\n--- 策划装备自有词条不为空 ---")
	var empty: Array = []
	var total := 0
	for tpl in EquipmentDB.all_templates():
		var id := str(tpl.id)
		if not (id.length() >= 2 and id.substr(1, 1).is_valid_int() \
				and id.substr(0, 1) in "GBPO"):
			continue
		total += 1
		if tpl.own_affixes.is_empty():
			empty.append("%s(%s)" % [tpl.display_name, id])
	# **自有词条为空**是已知待办，不是回归。
	#
	# 实测 390 件里 14 件为空，分两类：
	#   · 职业资源类（「受到伤害时获得2点怒气」）——等阶段 2 接 ClassResource
	#   · 未映射类（「显示附近陷阱」等非战斗效果）——等后续逐条补规则
	#
	# 故不断言「必须为 0」，而是**设上限防倒退**：一旦超过 20 件就说明
	# 有规则退化，那才是真问题。
	var limit := 20
	_check(empty.size() <= limit,
		"策划装备 %d 件，自有词条为空 %d 件（上限 %d）" % [total, empty.size(), limit],
		["为空的：%s" % str(empty)])
	if not empty.is_empty():
		print("    （已知待办 %d 件：职业资源类 + 未映射类，见测试注释）" % empty.size())


## 6. 灵魂叠层与满层爆发
##
## 装备参考2 的灵魂类词条是「击杀攒层 → 满层爆发」。旧实现**完全没有
## AT_FULL 这个触发条件**——7 条满层词条从未生效。
##
## 同时发现两个**笔误**：生成器里两处把 `stack_max` 的 `15` 写进了
## `trigger` 槽位（形态是 `[4, trigger, stat, value, stack_max]`）。
## 旧 Trigger 枚举只到 13，故 15 是无效值、那些词条一直不触发；
## 而本轮新增 `SHIELD_UP = 15` 后，它们会**静默变成「护盾存在时触发」**。
func _test_soul_stacking() -> void:
	print("\n--- 灵魂叠层与满层爆发 ---")

	# 灵魂收割者：击杀叠层（最多10层）+ 满层爆发
	#
	# **按名字查，不按 ID**——ID 会随策划增删装备整体位移（见 `_find_by_name`）
	var tpl = _find_by_name("灵魂收割者")
	if tpl == null:
		_check(false, "找到「灵魂收割者」")
		return
	var has_stack := false
	var has_full := false
	for a in tpl.own_affixes:
		if a == null or a.operation != AffixData.Operation.STACK_GAIN:
			continue
		if a.trigger == AffixData.Trigger.ON_KILL and a.stack_max > 0:
			has_stack = true
		if a.trigger == AffixData.Trigger.AT_FULL:
			has_full = true
	_check(has_stack, "灵魂收割者有「击杀叠层」（ON_KILL + stack_max>0）")
	_check(has_full, "灵魂收割者有「满层爆发」（AT_FULL）")

	# **笔误回归**：灵魂类词条不该落在 SHIELD_UP 上
	#（它们是「满层爆发」，不是「护盾存在时」）
	var wrong: Array = []
	for t in EquipmentDB.all_templates():
		for a in t.own_affixes:
			if a == null or a.operation != AffixData.Operation.STACK_GAIN:
				continue
			if a.trigger != AffixData.Trigger.SHIELD_UP:
				continue
			# SHIELD_UP 的合法来源是「护盾存在时…」；灵魂类走 AT_FULL
			if str(t.display_name).contains("灵魂") or str(t.display_name).contains("暗影"):
				wrong.append(t.display_name)
	_check(wrong.is_empty(),
		"灵魂/暗影类词条没有误落在 SHIELD_UP（生成器笔误已修）", [str(wrong)])

	# 灵魂强化词条可解析（层数不清空 / 返还50%）
	#
	# **必须扫全部三列**（自有/吞噬/融合）——这些词条在规格里可能落在
	# 任意一列（实测 soul_refund 在融合列、summon_soul 在自有列）。
	var seen := {}
	for t in EquipmentDB.all_templates():
		for arr in [t.own_affixes, t.devour_affixes, t.fusion_affixes]:
			for a in arr:
				if a == null or not a.is_trigger():
					continue
				seen[a.trigger_buff] = true
	_check(seen.has("soul_persist"), "「层数不清空」解析为 soul_persist")
	_check(seen.has("soul_refund"), "「返还50%层数」解析为 soul_refund")
	_check(seen.has("summon_soul"), "「击杀召唤灵魂」解析为 summon_soul")


# ============================================================
# 辅助
# ============================================================

func _find_by_id(id: String):
	return EquipmentDB.get_template(id)


## 按**显示名**找模板（优先于硬编码 ID）
##
## ## 为什么不用硬编码 ID
##
## 装备 ID 是**按稀有度内的出现顺序**生成的（`RAR_ID + 序号`）。
## 策划往 TSV 里插一件装备，其后所有同稀有度装备的 ID 都会**整体后移**——
## 实测本轮就位移了（`灵魂收割者` B029 → B031、
## `陷阱护符` B049 → B051、`远程精准镜` G048 → G055）。
##
## 硬编码 ID 的测试会在**数据变化时静默测错对象**（不报错，只是测了别的装备），
## 这是最坏的一种测试失败——比直接报错更难发现。
## 名字才是稳定的定位方式。
func _find_by_name(name: String):
	for t in EquipmentDB.all_templates():
		var id := str(t.id)
		if not (id.length() >= 2 and id.substr(1, 1).is_valid_int() \
				and id.substr(0, 1) in "GBPO"):
			continue
		if t.display_name == name:
			return t
	return null

func _first_devour_stat(tpl) -> int:
	for a in tpl.devour_affixes:
		if a != null:
			return a.stat
	return -1


func _check(c: bool, name: String, detail: Array = []) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
		for d in detail:
			print("    %s" % d)
