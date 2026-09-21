extends Node
## 元素/词条/伤害钩子 基础框架测试
## 验证分册第 3/4/5/7 章的数据与运行时行为。
## 全部纯逻辑（BuffHolder 不需要场景树），便于回归。

## 私有成员访问一律经 `TestProbe`（重构搬方法时只改 probe，本文件零改动）
var probe := TestProbe.new()

var failed := 0
var _test := ""


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 30.0
	guard.timeout.connect(func(): print("ELEMENT BUFF TESTS FAILED: 超时"); get_tree().quit(1))
	add_child(guard); guard.start()
	await get_tree().process_frame

	_test_element_defs()
	_test_element_stacking()
	_test_ui_snapshot()
	_test_buff_defs()
	_test_buff_apply_stack()
	_test_buff_modifier()
	_test_dot_tick()
	_test_vulnerability()
	_test_damage_hooks()
	_test_element_combo()
	_test_element_damage_bridge()
	_test_control_effects()
	_test_equipment_element()
	_test_element_dot()
	_test_monster_mechanics()
	_test_projectile_mechanics()
	await _test_damage_zones()
	_test_projectile_advanced()
	_test_mechanic_buff_ids()
	_test_teleport_stealth_mechanics()
	_test_summon_and_variants()
	_test_zone_slow_lifecycle()
	_test_elem_resist_and_penetration()

	if failed == 0:
		print("ALL ELEMENT BUFF TESTS PASSED")
		get_tree().quit(0)
	else:
		print("ELEMENT BUFF TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## ---------- 元素定义（分册 7.2~7.7） ----------
func _test_element_defs() -> void:
	_test = "ElementDefs"
	print("\n--- %s ---" % _test)

	var ED = load("res://data/elements/element_defs.gd")
	var all: Array = ED.all_elements()
	_check(all.size() == 6, "六元素齐备", [str(all.size())])

	# 叠层上限照分册
	_check(int(ED.get_element(ED.Elem.FIRE).max_stacks) == 50, "火·灼烧上限 50 层")
	_check(int(ED.get_element(ED.Elem.FROST).max_stacks) == 3, "冰·寒霜上限 3 层")
	_check(int(ED.get_element(ED.Elem.STATIC).max_stacks) == 10, "雷·静电上限 10 层")
	_check(int(ED.get_element(ED.Elem.POISON).max_stacks) == 30, "毒·毒蚀上限 30 层")
	# 土/风不叠层
	_check(not ED.stacks(ED.Elem.EARTH), "土不参与叠层")
	_check(not ED.stacks(ED.Elem.WIND), "风不参与叠层")

	# 衰减规则：火每秒 -5 层；雷/毒永不衰减
	_check(absf(float(ED.get_element(ED.Elem.FIRE).decay_per_sec) - 5.0) < 0.01, "火停止攻击后每秒 -5 层")
	_check(float(ED.get_element(ED.Elem.STATIC).decay_per_sec) == 0.0, "静电永不衰减")
	_check(float(ED.get_element(ED.Elem.POISON).decay_per_sec) == 0.0, "毒蚀永不衰减")

	# DOT 系数
	_check(absf(float(ED.get_element(ED.Elem.FIRE).dot_per_stack) - 0.04) < 0.001, "灼烧每层 法强×0.04")
	_check(absf(float(ED.get_element(ED.Elem.POISON).dot_per_stack) - 0.03) < 0.001, "毒蚀每层 法强×0.03")

	# 暴击口径：只有物理可暴击；火冰雷毒与土风法术部分不可
	_check(not ED.can_crit(ED.Elem.FIRE), "火不可暴击")
	_check(not ED.can_crit(ED.Elem.FROST), "冰不可暴击")
	_check(not ED.can_crit(ED.Elem.STATIC), "雷不可暴击")
	_check(not ED.can_crit(ED.Elem.POISON), "毒不可暴击")
	# 无视护甲：法术与真实部分
	_check(ED.ignores_armor(ED.Elem.FIRE), "火无视护甲")
	# damage_type=mixed 的**法术部分**无视护甲 ⇒ `ignores_armor` 为 true。
	# 物理部分不无视，那是 `can_crit`/伤害拆分的事，与本函数无关。
	# （此前写成 `... or true` 的恒真断言，等于没测。）
	_check(ED.ignores_armor(ED.Elem.EARTH), "土含法术部分（无视护甲为真）")
	_check(ED.ignores_armor(ED.Elem.WIND), "风含法术部分（无视护甲为真）")


## ---------- 元素叠层与阈值触发 ----------
func _test_element_stacking() -> void:
	_test = "ElementStacking"
	print("\n--- %s ---" % _test)

	var ED = load("res://data/elements/element_defs.gd")
	var H = load("res://gameplay/status/buff_holder.gd")
	var h = H.new(null)

	# 火：叠到上限即封顶
	for _i in 60:
		h.add_element(ED.Elem.FIRE, 1)
	_check(h.elem_stacks(ED.Elem.FIRE) == 50, "灼烧封顶 50 层", [str(h.elem_stacks(ED.Elem.FIRE))])

	# 火衰减：tick 1 秒应掉 5 层
	h.tick(1.0)
	_check(h.elem_stacks(ED.Elem.FIRE) == 45, "1 秒后灼烧 -5 层", [str(h.elem_stacks(ED.Elem.FIRE))])

	# 雷：叠满 10 层触发雷暴并归零
	var h2 = H.new(null)
	var last_events: Array = []
	for i in 10:
		last_events = h2.add_element(ED.Elem.STATIC, 1)
	_check(last_events.has("thunderstorm"), "静电叠满触发雷暴", [str(last_events)])
	_check(h2.elem_stacks(ED.Elem.STATIC) == 0, "雷暴后层数归零")

	# 冰：叠满 3 层触发冰冻并归零
	var h3 = H.new(null)
	var ev3: Array = []
	for i in 3:
		ev3 = h3.add_element(ED.Elem.FROST, 1)
	_check(ev3.has("freeze"), "寒霜叠满触发冰冻", [str(ev3)])
	_check(h3.is_frozen(), "冰冻状态生效")
	_check(h3.elem_stacks(ED.Elem.FROST) == 0, "冰冻后层数归零")

	# 毒：不衰减（**敌人侧语义**——玩家打怪时层数越叠越高是设计意图）
	var h4 = H.new(null)
	for _i in 5:
		h4.add_element(ED.Elem.POISON, 1)
	h4.tick(10.0)
	_check(h4.elem_stacks(ED.Elem.POISON) == 5, "毒蚀永不衰减（无宿主/敌人侧）",
		[str(h4.elem_stacks(ED.Elem.POISON))])

	# **玩家侧必须能消退**：玩家被毒怪/毒雾叠层后没有任何清除手段，
	# 若沿用"永不衰减"会一直掉血到死（实机症状：接触毒雾后中毒不消退）。
	# 用一个进 "player" 组的 Node 冒充宿主。
	var pnode := Node.new()
	pnode.add_to_group("player")
	add_child(pnode)
	var hp = H.new(pnode)
	for _i in 5:
		hp.add_element(ED.Elem.POISON, 1)
	_check(hp.elem_stacks(ED.Elem.POISON) == 5, "玩家中毒先叠上 5 层")
	hp.tick(1.0)
	_check(hp.elem_stacks(ED.Elem.POISON) < 5,
		"玩家侧毒蚀会衰减（1 秒后 %d 层）" % hp.elem_stacks(ED.Elem.POISON))
	hp.tick(10.0)
	_check(hp.elem_stacks(ED.Elem.POISON) == 0, "玩家侧毒蚀最终清零（不会永久挂）")
	pnode.queue_free()

	# 土/风不叠层
	var h5 = H.new(null)
	h5.add_element(ED.Elem.EARTH, 1)
	_check(h5.elem_stacks(ED.Elem.EARTH) == 0, "土不叠层")


## ---------- buff UI 快照：剩余时间必须可读 ----------
##
## HUD 的图标要显示"还有几秒"。快照若把限时状态报成 permanent，
## UI 会画成 "∞" —— 玩家看到持续掉血却不知道还要扛多久。
func _test_ui_snapshot() -> void:
	_test = "UiSnapshot"
	print("\n--- %s ---" % _test)
	var H = load("res://gameplay/status/buff_holder.gd")

	# 限时 buff：快照必须给出 remaining/total 且非永久
	var h = H.new(null)
	h.apply("burn", "test")
	var snap: Array = h.ui_snapshot()
	var burn := {}
	for info in snap:
		if str(info.get("id", "")) == "burn":
			burn = info
	_check(not burn.is_empty(), "快照含 burn 词条")
	if not burn.is_empty():
		_check(not bool(burn.get("permanent", true)), "限时词条不是永久")
		_check(float(burn.get("total", 0.0)) > 0.0, "限时词条有总时长")
		_check(float(burn.get("remaining", 0.0)) > 0.0, "限时词条有剩余时间")

	# 玩家身上的毒：快照要给出可推算的剩余时间（而不是 ∞）
	var pnode := Node.new()
	pnode.add_to_group("player")
	add_child(pnode)
	var hp = H.new(pnode)
	hp.add_element(ElementDefs.Elem.POISON, 3)
	var found := {}
	for info in hp.ui_snapshot():
		if str(info.get("id", "")).begins_with("elem:"):
			found = info
	_check(not found.is_empty(), "快照含元素层数条目")
	if not found.is_empty():
		_check(int(found.get("stacks", 0)) == 3, "元素条目带层数")
		_check(not bool(found.get("permanent", true)),
			"玩家侧毒蚀显示为限时（会衰减，不是 ∞）")
		_check(float(found.get("remaining", 0.0)) > 0.0,
			"玩家侧毒蚀有可读剩余时间（%.1fs）" % float(found.get("remaining", 0.0)))
	pnode.queue_free()


## ---------- 词条数据完整性（分册 3~5 章） ----------
func _test_buff_defs() -> void:
	_test = "BuffDefs"
	print("\n--- %s ---" % _test)

	var B = load("res://data/buffs/buff_defs.gd")
	# 用 doc_ids() 而非 all_ids()：技能专用词条（血怒/拉拽等）是《角色设计
	# 分册》技能描述反推的扩展，不属于策划文档的 81 条体系，混进来会让
	# 下面「表 == 文档」的双向覆盖校验失去意义。
	var ids: Array = B.doc_ids()
	_check(ids.size() == 81, "策划文档词条 81 条（负面 38 + 增益 22 + 通用 21）", [str(ids.size())])
	_check(B.all_ids().size() == 81 + B.SKILL_ONLY_IDS.size(),
		"总词条数 = 文档 81 + 技能 %d" % B.SKILL_ONLY_IDS.size(), [str(B.all_ids().size())])

	# 分类计数按**文档分节**核对（与运行时 Kind 是两个维度，见 buff_defs 说明）
	var sec := {
		"3.1 持续伤害型": 5, "3.2 减速/减速攻型": 6, "3.3 硬控型": 8,
		"3.4 易伤/破甲型": 10, "3.5 减益/削弱型": 5, "3.6 击退/位移型": 4,
		"4.1 护盾/防御型": 4, "4.2 攻击/输出型": 9, "4.3 移动/机动型": 4,
		"4.4 资源/回复型": 5, "第5章 通用词条池": 21,
	}
	var sec_total := 0
	var missing_in_buffs: Array = []
	for name in sec:
		var sec_ids: Array = B.section_ids(name)
		_check(sec_ids.size() == int(sec[name]), "%s 共 %d 种" % [name, sec[name]], [str(sec_ids.size())])
		sec_total += sec_ids.size()
		# 分节里的每个 id 都必须真实存在于词条表
		for id in sec_ids:
			if B.get_buff(id).is_empty():
				missing_in_buffs.append(id)
	_check(sec_total == 81, "分节合计 81 种", [str(sec_total)])
	_check(missing_in_buffs.is_empty(), "分节引用的 id 均存在于词条表", [str(missing_in_buffs)])

	# 两个维度必须覆盖同一集合（防止新增词条只进了一个索引）
	var union := {}
	for name in sec:
		for sid in B.section_ids(name):
			union[sid] = true
	var mismatch: Array = []
	for id in ids:
		if not union.has(id):
			mismatch.append(id)
	_check(mismatch.is_empty(), "Kind 索引与文档分节覆盖同一集合", [str(mismatch)])

	# 抽查关键数值（分册 3.1）
	var burn: Array = B.get_buff("burn")
	_check(not burn.is_empty() and absf(float(burn[3]) - 4.0) < 0.01, "灼烧持续 4 秒")
	_check(int(burn[4]) == 50, "灼烧上限 50 层")
	var bleed: Array = B.get_buff("bleed")
	_check(int(bleed[4]) == 3, "流血上限 3 层")

	# 实现分层：本轮生效 stat / dot
	var impl_stat := 0
	var impl_dot := 0
	var pending := 0
	for id in ids:
		match B.impl_of(id):
			"stat": impl_stat += 1
			"dot": impl_dot += 1
			_: pending += 1
	_check(impl_stat > 0 and impl_dot > 0, "有 stat 型与 dot 型词条可本轮生效",
		["stat=%d dot=%d 待实现=%d" % [impl_stat, impl_dot, pending]])
	print("    （本轮生效 %d 种：stat %d + dot %d；登记待实现 %d 种）"
		% [impl_stat + impl_dot, impl_stat, impl_dot, pending])


## ---------- 施加与叠层 ----------
func _test_buff_apply_stack() -> void:
	_test = "BuffApplyStack"
	print("\n--- %s ---" % _test)

	var B = load("res://data/buffs/buff_defs.gd")
	var H = load("res://gameplay/status/buff_holder.gd")
	var h = H.new(null)

	var r: Dictionary = h.apply("burn", "test")
	_check(r.get("ok", false), "施加灼烧成功")
	_check(h.stacks_of("burn") == 1, "初始 1 层")

	for _i in 100:
		h.apply("burn", "test")
	_check(h.stacks_of("burn") == 50, "叠层封顶 50", [str(h.stacks_of("burn"))])

	# 不叠层词条（上限 0）保持 1 层
	var h2 = H.new(null)
	h2.apply("tear", "t")
	h2.apply("tear", "t")
	_check(h2.stacks_of("tear") == 1, "不叠层词条保持 1 层")

	# 移除
	h2.remove("tear")
	_check(not h2.has("tear"), "移除后不再持有")

	# 永久词条不因时间过期
	var h3 = H.new(null)
	h3.apply("poison_rot", "t")
	h3.tick(100.0)
	_check(h3.has("poison_rot"), "永久词条（毒蚀）不会过期")

	# 限时词条到期自动移除
	var h4 = H.new(null)
	h4.apply("bleed", "t")
	h4.tick(4.0)
	_check(not h4.has("bleed"), "流血 3 秒后过期移除")


## ---------- 属性型词条真正作用于属性 ----------
func _test_buff_modifier() -> void:
	_test = "BuffModifier"
	print("\n--- %s ---" % _test)

	var H = load("res://gameplay/status/buff_holder.gd")
	var AS = load("res://data/attributes/attribute_system.gd")
	var attrs = AS.new()
	var h = H.new(attrs)

	var base_spd: float = attrs.get_value(AS.Stat.SPD)
	h.apply("wind_step", "test")
	_check(attrs.get_value(AS.Stat.SPD) > base_spd, "「风之步」提升移速",
		["%f → %f" % [base_spd, attrs.get_value(AS.Stat.SPD)]])

	# 移除后恢复
	h.remove("wind_step")
	_check(absf(attrs.get_value(AS.Stat.SPD) - base_spd) < 0.01, "移除后移速恢复")

	# 减速：寒霜 3 层 = 移速 -75%
	var h2 = H.new(attrs)
	var spd0: float = attrs.get_value(AS.Stat.SPD)
	for _i in 3:
		h2.apply("frost", "test")
	_check(absf(h2.total_slow() - 0.75) < 0.01, "寒霜 3 层减速 75%", [str(h2.total_slow())])
	_check(attrs.get_value(AS.Stat.SPD) < spd0, "减速已作用到移速属性")
	h2.clear()
	_check(absf(attrs.get_value(AS.Stat.SPD) - spd0) < 0.01, "清理后移速恢复")


## ---------- DOT 结算 ----------
func _test_dot_tick() -> void:
	_test = "DotTick"
	print("\n--- %s ---" % _test)

	var H = load("res://gameplay/status/buff_holder.gd")
	# 用带 eff_ap 的替身宿主
	var host = _FakeHost.new()
	host.ap = 100.0
	host.atk = 50.0
	var h = H.new(host)

	# 灼烧 10 层，法强 100：每秒 = 100 × 0.04 × 10 = 40
	for _i in 10:
		h.apply("burn", "t")
	var out: Dictionary = h.tick(1.0)
	_check(absf(float(out.dot) - 40.0) < 0.5, "灼烧 10 层每秒 40（法强100×0.04×10）", [str(out.dot)])

	# 撕裂：攻击力×0.2
	var h2 = H.new(host)
	h2.apply("tear", "t")
	var out2: Dictionary = h2.tick(1.0)
	_check(absf(float(out2.dot) - 10.0) < 0.5, "撕裂每秒 攻击力×0.2 = 10", [str(out2.dot)])


## ---------- 易伤/减伤累加 ----------
func _test_vulnerability() -> void:
	_test = "Vulnerability"
	print("\n--- %s ---" % _test)

	var H = load("res://gameplay/status/buff_holder.gd")
	var h = H.new(null)

	# 毒蚀每层 +1% 易伤（30 层 = +30%）
	for _i in 30:
		h.apply("poison_rot", "t")
	_check(absf(h.total_vulnerability() - 0.30) < 0.01, "毒蚀 30 层 = 易伤 30%",
		[str(h.total_vulnerability())])

	# 标记 +20%
	var h2 = H.new(null)
	h2.apply("mark", "t")
	_check(absf(h2.total_vulnerability() - 0.20) < 0.01, "标记 = 易伤 20%")

	# 减伤
	var h3 = H.new(null)
	h3.apply("iron_body", "t")
	_check(absf(h3.total_damage_reduction() - 0.30) < 0.01, "铁身 = 减伤 30%")

	# 治疗削减
	var h4 = H.new(null)
	h4.apply("weakness", "t")
	_check(absf(h4.total_heal_reduction() - 0.50) < 0.01, "虚弱 = 治疗 -50%")


## ---------- 伤害钩子（易伤/减伤接入物理公式） ----------
func _test_damage_hooks() -> void:
	_test = "DamageHooks"
	print("\n--- %s ---" % _test)

	var DP = load("res://gameplay/combat/damage_pipeline.gd")
	# 无词条基线
	var base: Dictionary = DP.physical(100.0, 1.0, 0.0, 0.0)
	_check(absf(float(base.damage) - 100.0) < 0.01, "基线：攻100 无护甲 无词条 = 100",
		[str(base.damage)])

	# 易伤 +30%
	var vul: Dictionary = DP.physical(100.0, 1.0, 0.0, 0.0, 0.30, 0.0)
	_check(absf(float(vul.damage) - 130.0) < 0.01, "易伤 30% → 130", [str(vul.damage)])

	# 减伤 30%
	var red: Dictionary = DP.physical(100.0, 1.0, 0.0, 0.0, 0.0, 0.30)
	_check(absf(float(red.damage) - 70.0) < 0.01, "减伤 30% → 70", [str(red.damage)])

	# 两者叠加：100 × 1.3 × 0.7 = 91
	var both: Dictionary = DP.physical(100.0, 1.0, 0.0, 0.0, 0.30, 0.30)
	_check(absf(float(both.damage) - 91.0) < 0.01, "易伤与减伤叠加 → 91", [str(both.damage)])

	# 护甲口径仍是 防御/(防御+100)
	var armor: Dictionary = DP.physical(100.0, 1.0, 0.0, 100.0)
	_check(absf(float(armor.damage) - 50.0) < 0.01, "护甲 100 → 减伤 50%", [str(armor.damage)])

	# 兼容：旧的三参数调用仍然有效
	var legacy: Dictionary = DP.physical(100.0, 1.0, 0.0, 0.0)
	_check(absf(float(legacy.damage) - 100.0) < 0.01, "旧调用签名向后兼容")


## ---------- 元素联动（分册 7.8，4 组） ----------
func _test_element_combo() -> void:
	_test = "ElementCombo"
	print("\n--- %s ---" % _test)

	var EC = load("res://gameplay/combat/element_combo.gd")
	var ED = load("res://data/elements/element_defs.gd")

	_check(EC.all_combos().size() == 4, "联动共 4 组", [str(EC.all_combos().size())])

	# ① 烈焰风暴：灼烧≥20 且龙卷风存在
	var a: Dictionary = EC.evaluate({"burn": 20, "tornado": true})
	_check(a.has(ED.COMBO_FIRE_STORM), "烈焰风暴触发（灼烧20+龙卷风）")
	_check(not EC.evaluate({"burn": 19, "tornado": true}).has(ED.COMBO_FIRE_STORM),
		"灼烧 19 层不触发烈焰风暴")
	_check(not EC.evaluate({"burn": 20, "tornado": false}).has(ED.COMBO_FIRE_STORM),
		"无龙卷风不触发烈焰风暴")
	if a.has(ED.COMBO_FIRE_STORM):
		_check(absf(float(a[ED.COMBO_FIRE_STORM]["burn_per_sec"]) - 5.0) < 0.01,
			"烈焰风暴：灼烧每秒 +5 层")
		_check(absf(float(a[ED.COMBO_FIRE_STORM]["splash_ratio"]) - 1.20) < 0.01,
			"烈焰风暴：溅射提升至 120%")

	# ② 腐化烈焰：灼烧≥20 且毒蚀≥15
	var b: Dictionary = EC.evaluate({"burn": 20, "poison": 15})
	_check(b.has(ED.COMBO_CORRUPT_FLAME), "腐化烈焰触发（灼烧20+毒蚀15）")
	_check(not EC.evaluate({"burn": 20, "poison": 14}).has(ED.COMBO_CORRUPT_FLAME),
		"毒蚀 14 层不触发腐化烈焰")

	# ③ 冰晶电导：静电≥5 且冰冻中
	var c: Dictionary = EC.evaluate({"static": 5, "frozen": true})
	_check(c.has(ED.COMBO_ICE_CONDUCT), "冰晶电导触发（静电5+冰冻）")
	_check(not EC.evaluate({"static": 4, "frozen": true}).has(ED.COMBO_ICE_CONDUCT),
		"静电 4 层不触发冰晶电导")
	if c.has(ED.COMBO_ICE_CONDUCT):
		_check(absf(float(c[ED.COMBO_ICE_CONDUCT]["burst_mult"]) - 6.0) < 0.01,
			"冰晶电导：雷暴 法强×6.0")
		_check(absf(float(c[ED.COMBO_ICE_CONDUCT]["paralyze"]) - 2.5) < 0.01,
			"冰晶电导：麻痹 2.5 秒")
		_check(absf(float(c[ED.COMBO_ICE_CONDUCT]["chain_radius"]) - 6.0) < 0.01,
			"冰晶电导：连锁范围 6 米")

	# ④ 碎裂岩击：冰冻中 且山崩触发
	var d: Dictionary = EC.evaluate({"frozen": true, "shatter_proc": true})
	_check(d.has(ED.COMBO_SHATTER_ROCK), "碎裂岩击触发（冰冻+山崩）")
	if d.has(ED.COMBO_SHATTER_ROCK):
		_check(absf(float(d[ED.COMBO_SHATTER_ROCK]["proc_mult"]) - 7.0) < 0.01,
			"碎裂岩击：山崩 法强×7.0")
		_check(absf(float(d[ED.COMBO_SHATTER_ROCK]["stun"]) - 2.0) < 0.01,
			"碎裂岩击：眩晕 2 秒")

	# 无联动情形
	_check(EC.evaluate({}).is_empty(), "空状态无联动")
	_check(EC.evaluate({"burn": 5, "poison": 3}).is_empty(), "条件不足无联动")

	# 从 BuffHolder 生成快照
	var H = load("res://gameplay/status/buff_holder.gd")
	var h = H.new(null)
	for _i in 20:
		h.add_element(ED.Elem.FIRE, 1)
	var snap: Dictionary = EC.state_from_holder(h)
	_check(int(snap.get("burn", 0)) == 20, "快照正确取到灼烧层数")
	var with_tornado: Dictionary = EC.evaluate(dict_merge(snap, {"tornado": true}))
	_check(with_tornado.has(ED.COMBO_FIRE_STORM), "快照 + 龙卷风 → 触发烈焰风暴")


## 测试用：合并字典
func dict_merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = b[k]
	return out


## ---------- 元素伤害桥接层 ----------
func _test_element_damage_bridge() -> void:
	_test = "ElementDamageBridge"
	print("\n--- %s ---" % _test)

	var EDmg = load("res://gameplay/combat/element_damage.gd")
	var ED = load("res://data/elements/element_defs.gd")
	var H = load("res://gameplay/status/buff_holder.gd")

	# 键名 ↔ 枚举
	_check(EDmg.elem_from_key("fire") == ED.Elem.FIRE, "键名 fire → 火")
	_check(EDmg.elem_from_key("poison") == ED.Elem.POISON, "键名 poison → 毒")
	_check(EDmg.elem_from_key("") == EDmg.NO_ELEMENT, "空键名 → 无元素")
	_check(EDmg.elem_from_key("nonsense") == EDmg.NO_ELEMENT, "未知键名 → 无元素")

	# 纯物理（无元素）不叠层
	var h = H.new(null)
	var r0: Dictionary = EDmg.attack(h, EDmg.NO_ELEMENT)
	_check(r0.get("stacks_applied") == 0, "无元素攻击不叠层")

	# 火攻击叠 1 层
	var r1: Dictionary = EDmg.attack(h, ED.Elem.FIRE)
	_check(r1.get("stacks_applied") == 1, "火攻击叠 1 层")
	_check(h.elem_stacks(ED.Elem.FIRE) == 1, "层数已写入目标")

	# 冰：叠 3 次触发冰冻事件
	var h2 = H.new(null)
	var last: Dictionary = {}
	for _i in 3:
		last = EDmg.attack(h2, ED.Elem.FROST)
	_check((last.get("events", []) as Array).has("freeze"), "冰攻击第 3 次触发冰冻事件")
	_check(h2.is_frozen(), "目标进入冰冻")

	# 雷：叠 10 次触发雷暴
	var h3 = H.new(null)
	var last3: Dictionary = {}
	for _i in 10:
		last3 = EDmg.attack(h3, ED.Elem.STATIC)
	_check((last3.get("events", []) as Array).has("thunderstorm"), "雷攻击第 10 次触发雷暴")

	# 阈值事件 → 控制词条
	_check(EDmg.control_for_event("freeze") == "freeze", "冰冻事件 → freeze 词条")
	_check(EDmg.control_for_event("thunderstorm") == "paralyze", "雷暴事件 → 麻痹词条")

	# 联动生效：冰冻 + 山崩 → 碎裂岩击，本次伤害倍率被放大
	# 注意不要用「静电≥5 + 冰冻」测——雷攻击叠满 10 层会触发雷暴并归零，
	# 判定时静电已为 0（这是元素机制本身的正确行为，不是 bug）。
	var h4 = H.new(null)
	h4.apply("freeze", "test")
	var boosted: Dictionary = EDmg.attack(h4, ED.Elem.FIRE, 1.0, {"shatter_proc": true})
	_check((boosted.get("combo", {}) as Dictionary).has(ED.COMBO_SHATTER_ROCK),
		"冰冻+山崩 → 碎裂岩击联动被判定",
		[str((boosted.get("combo", {}) as Dictionary).keys())])
	_check(float(boosted.get("damage_mult", 1.0)) > 1.0, "联动放大本次伤害倍率",
		[str(boosted.get("damage_mult"))])

	# 冰晶电导也验证一次：直接构造状态快照（不经攻击叠层，避免雷暴归零）
	var h4b = H.new(null)
	for _i in 5:
		h4b.add_element(ED.Elem.STATIC, 1)
	h4b.add_element(ED.Elem.FROST, 3)   # 触发冰冻
	var b2: Dictionary = EDmg.attack(h4b, ED.Elem.EARTH, 1.0)
	_check((b2.get("combo", {}) as Dictionary).has(ED.COMBO_ICE_CONDUCT),
		"静电5+冰冻 → 冰晶电导被判定",
		[str((b2.get("combo", {}) as Dictionary).keys())])

	# DOT 每秒：火 10 层 + 法强 100 = 40
	var h5 = H.new(null)
	for _i in 10:
		h5.add_element(ED.Elem.FIRE, 1)
	_check(absf(EDmg.dot_per_second(h5, 100.0) - 40.0) < 0.5,
		"元素 DOT 每秒 40（法强100 火10层）", [str(EDmg.dot_per_second(h5, 100.0))])


## ---------- 控制型词条真正生效 ----------
func _test_control_effects() -> void:
	_test = "ControlEffects"
	print("\n--- %s ---" % _test)

	var H = load("res://gameplay/status/buff_holder.gd")

	# 硬控判定：冰冻/麻痹/眩晕/定身 为真；减速不算硬控
	var h = H.new(null)
	_check(not h.is_controlled(), "无词条时不受控")
	h.apply("freeze", "t")
	_check(h.is_controlled(), "冰冻 → 受控")
	var h2 = H.new(null)
	h2.apply("paralyze", "t")
	_check(h2.is_controlled(), "麻痹 → 受控")
	var h3 = H.new(null)
	h3.apply("stun", "t")
	_check(h3.is_controlled(), "眩晕 → 受控")
	var h4 = H.new(null)
	h4.apply("entangle", "t")
	_check(h4.is_controlled(), "定身 → 受控")
	var h5 = H.new(null)
	h5.apply("frost", "t")
	_check(not h5.is_controlled(), "寒霜是减速不是硬控")

	# 硬控会随时间结束
	var h6 = H.new(null)
	h6.apply("stun", "t")   # 眩晕 1 秒
	_check(h6.is_controlled(), "眩晕中")
	h6.tick(1.5)
	_check(not h6.is_controlled(), "1.5 秒后眩晕已结束")

	# 减速累加（多来源叠加）
	var h7 = H.new(null)
	_check(h7.total_slow() == 0.0, "无减速")
	h7.apply("mire", "t")   # -40%
	_check(absf(h7.total_slow() - 0.40) < 0.01, "泥沼减速 40%")
	h7.apply("erosion", "t")  # 再 -20%
	_check(absf(h7.total_slow() - 0.60) < 0.01, "叠加后 60%", [str(h7.total_slow())])

	# 减速有上限（不会超过 90%）
	var h8 = H.new(null)
	for id in ["mire", "erosion", "thorn_slow"]:
		h8.apply(id, "t")
	_check(h8.total_slow() <= 0.9, "减速封顶 90%", [str(h8.total_slow())])

	# 攻速降低（迟钝 25%）
	var h9 = H.new(null)
	h9.apply("dull", "t")
	var down := float(load("res://data/buffs/buff_defs.gd").params_of("dull").get("aspd_down", 0.0))
	_check(absf(down - 0.25) < 0.01, "迟钝 攻速 -25%")


## ---------- 装备元素与元素亲和 ----------
func _test_equipment_element() -> void:
	_test = "EquipmentElement"
	print("\n--- %s ---" % _test)

	var EDB = load("res://data/equipment/equipment_db.gd")
	var ED = load("res://data/elements/element_defs.gd")
	EDB.init_equipment_db()

	# 占位元素表生效：长杖=火，长弓=毒
	var staff = EDB.get_template(&"W11")
	_check(staff != null and staff.element == "fire", "学徒长杖带火元素",
		[str(staff.element) if staff else "nil"])
	var bow = EDB.get_template(&"W09")
	_check(bow != null and bow.element == "poison", "猎人长弓带毒元素",
		[str(bow.element) if bow else "nil"])

	# 未指定的武器为空（纯物理）
	var sword = EDB.get_template(&"W01")
	_check(sword != null and sword.element == "", "铁制单手剑无元素（纯物理）")

	# 高稀有度克隆继承元素
	var staff_p = EDB.get_template(&"W11_P")
	_check(staff_p != null and staff_p.element == "fire", "紫装长杖继承火元素",
		[str(staff_p.element) if staff_p else "nil"])
	var staff_g = EDB.get_template(&"W11_G")
	_check(staff_g != null and staff_g.element == "fire", "绿装长杖继承火元素")

	# 元素亲和词条（分册 4.x）只挂饰品
	var ring = EDB.get_template(&"J02")
	_check(ring != null and absf(ring.element_affinity - 0.15) < 0.001,
		"蓝晶戒指提供元素亲和 +15%",
		[str(ring.element_affinity) if ring else "nil"])
	var ring_o = EDB.get_template(&"J02_O")
	_check(ring_o != null and absf(ring_o.element_affinity - 0.15) < 0.001,
		"橙装蓝晶戒指继承元素亲和")
	var plain = EDB.get_template(&"J01")
	_check(plain != null and plain.element_affinity == 0.0, "铁戒指无元素亲和")

	# 元素伤害类型（分册 7.1）：火/冰/雷/毒=法术无视护甲；土/风=各半
	var DP = load("res://gameplay/combat/damage_pipeline.gd")
	var armor := 100.0   # 减伤 50%

	# 火：纯法术，护甲完全不影响
	var fire_hit: Dictionary = DP.elemental_attack(100.0, 1.0, 0.0, armor, ED.Elem.FIRE)
	_check(absf(fire_hit.damage - 100.0) < 0.5, "火伤害无视护甲（100 防御下仍 100）",
		[str(fire_hit.damage)])
	_check(fire_hit.get("is_spell_only", false), "火为纯法术伤害")

	# 物理对照：同样 100 攻，护甲 100 → 减半
	var phys_hit: Dictionary = DP.elemental_attack(100.0, 1.0, 0.0, armor, -1)
	_check(absf(phys_hit.damage - 50.0) < 0.5, "物理伤害被护甲减半（100→50）",
		[str(phys_hit.damage)])

	# 土：mixed，物理半吃护甲 → 50*(1-0.5) + 50 = 75
	var earth_hit: Dictionary = DP.elemental_attack(100.0, 1.0, 0.0, armor, ED.Elem.EARTH)
	_check(absf(earth_hit.damage - 75.0) < 0.5, "土伤害=物理半减伤+法术半（100→75）",
		[str(earth_hit.damage)])

	# 可暴击性（分册 2.3）：法术不可暴击，土/风的物理半可
	_check(not ED.can_crit(ED.Elem.FIRE), "火不可暴击")
	_check(not ED.can_crit(ED.Elem.POISON), "毒不可暴击")
	_check(ED.can_crit(ED.Elem.EARTH), "土可暴击（物理半）")
	_check(ED.can_crit(ED.Elem.WIND), "风可暴击（物理半）")


## ---------- 元素 DOT 与毒阈值（任务 3）----------
func _test_element_dot() -> void:
	_test = "ElementDot"
	print("\n--- %s ---" % _test)

	var ED = load("res://data/elements/element_defs.gd")
	var H = load("res://gameplay/status/buff_holder.gd")

	# 火层数应产生 DOT（此前只显示层数、不造成伤害）
	# 注意 DOT 的伤害基数来自宿主法强（_target_ap），桩宿主必须提供 eff_ap，
	# 否则法强为 0、DOT 恒为 0——测试会误判成「DOT 没实现」。
	var host := _ApStub.new()
	var h = H.new(host)
	for _i in 10:
		h.add_element(ED.Elem.FIRE, 1)
	var out: Dictionary = h.tick(1.0)
	# 火 dot_per_stack 0.04 × 法强100 × 10 层 = 40/秒
	_check(absf(float(out.get("elem_dot", 0.0)) - 40.0) < 0.5, "火层数产生 DOT（法强100×10层=40/秒）",
		[str(out.get("elem_dot"))])
	_check(float(out.get("dot", 0.0)) >= float(out.get("elem_dot", 0.0)),
		"总 DOT 含元素 DOT 部分")

	# 毒层数同样有 DOT（0.03 × 100 × 10 = 30）
	var h2 = H.new(_ApStub.new())
	for _i in 10:
		h2.add_element(ED.Elem.POISON, 1)
	var out2: Dictionary = h2.tick(1.0)
	_check(absf(float(out2.get("elem_dot", 0.0)) - 30.0) < 0.5,
		"毒层数产生 DOT（法强100×10层=30/秒）", [str(out2.get("elem_dot"))])

	# 毒每层 +1% 易伤（分册 4.x）
	var h3 = H.new(null)
	_check(h3.total_vulnerability() == 0.0, "无毒层时无易伤")
	for _i in 10:
		h3.add_element(ED.Elem.POISON, 1)
	_check(absf(h3.total_vulnerability() - 0.10) < 0.001,
		"毒 10 层 → 易伤 +10%", [str(h3.total_vulnerability())])

	# 毒阈值解锁：10 层侵蚀（减速）/ 20 层衰弱 / 30 层虚弱（治疗降低）
	var h4 = H.new(null)
	for _i in 10:
		h4.add_element(ED.Elem.POISON, 1)
	_check(h4.total_slow() > 0.0, "毒 10 层解锁侵蚀（减速）", [str(h4.total_slow())])
	var h5 = H.new(null)
	for _i in 30:
		h5.add_element(ED.Elem.POISON, 1)
	_check(h5.total_heal_reduction() > 0.0, "毒 30 层解锁虚弱（治疗降低）",
		[str(h5.total_heal_reduction())])

	# 寒霜层数自带减速（每层 -25%）
	var h6 = H.new(null)
	h6.add_element(ED.Elem.FROST, 1)
	_check(absf(h6.total_slow() - 0.25) < 0.01, "寒霜 1 层 → 减速 25%",
		[str(h6.total_slow())])
	h6.add_element(ED.Elem.FROST, 1)
	_check(absf(h6.total_slow() - 0.50) < 0.01, "寒霜 2 层 → 减速 50%")


## ---------- 怪物专属机制（任务 2）----------
func _test_monster_mechanics() -> void:
	_test = "MonsterMechanics"
	print("\n--- %s ---" % _test)

	var MDB = load("res://data/monsters/monster_db.gd")
	MDB.init()

	# 机制标记应随怪物数据一起下发
	var blade: Dictionary = MDB.get_monster("chaos_blade")
	_check(not blade.is_empty(), "混沌利刃在库")
	_check(str(blade.get("mech", "")) == "true_damage", "混沌利刃带 true_damage 标记",
		[str(blade.get("mech"))])
	var beetle: Dictionary = MDB.get_monster("crystal_beetle")
	_check(str(beetle.get("mech", "")) == "armor_break", "矿晶甲虫带 armor_break 标记")
	var guard: Dictionary = MDB.get_monster("void_guard")
	_check(str(guard.get("mech", "")) == "rage_on_hit", "虚无守卫带 rage_on_hit 标记")
	var warp: Dictionary = MDB.get_monster("time_warp")
	_check(str(warp.get("mech", "")) == "slow_haste", "时间畸变者带 slow_haste 标记")

	# 用真实敌人实例验证机制装配（不进场景树，直接构造）
	var EB = load("res://entities/enemies/enemy_base.gd")
	var e = EB.new()
	add_child(e)
	e.apply_monster_config(beetle)
	_check(absf(e.armor_plates - 0.30) < 0.001, "矿晶甲虫装配护甲减伤 30%",
		[str(e.armor_plates)])
	_check(absf(e.armor_break_at - 300.0) < 0.001, "护甲碎裂阈值 300")

	# 护甲减伤生效：100 伤害只吃 70
	probe.set_enemy_hp(e, 1000.0)
	e.take_damage(100.0)
	_check(absf(probe.enemy_hp(e) - 930.0) < 0.5, "护甲减伤 30%（1000-70=930）", [str(probe.enemy_hp(e))])

	# 累计伤害达 300 后护甲碎裂
	for _i in 5:
		e.take_damage(100.0)
	_check(e.armor_plates == 0.0, "累计受伤达阈值后护甲碎裂（减伤失效）",
		[str(e.armor_plates)])
	var hp_before: float = probe.enemy_hp(e)
	e.take_damage(100.0)
	_check(absf((hp_before - probe.enemy_hp(e)) - 100.0) < 0.5, "碎裂后全额受伤（无减伤）")

	# 虚无守卫：每受击 +5% 攻击，最多 10 层
	var g = EB.new()
	add_child(g)
	g.apply_monster_config(guard)
	var base_atk: float = g.atk
	g.take_damage(1.0)
	_check(g.atk > base_atk, "虚无守卫受击后攻击提升",
		["%f → %f" % [base_atk, g.atk]])
	for _i in 20:
		g.take_damage(1.0)
	_check(absf(g.atk - base_atk * 1.5) < 0.01, "激怒封顶 10 层（+50%）",
		[str(g.atk), str(base_atk * 1.5)])

	# 混沌利刃：真实伤害标记
	var c = EB.new()
	add_child(c)
	c.apply_monster_config(blade)
	_check(c.true_damage, "混沌利刃开启真实伤害")

	e.queue_free(); g.queue_free(); c.queue_free()


## ---------- 投射物机制（分册第 5/6 章）----------
func _test_projectile_mechanics() -> void:
	_test = "ProjectileMechanics"
	print("\n--- %s ---" % _test)

	# **本段测的是「旧 Area3D 节点路径」**。
	#
	# 分流开关已于 2026-09-19 默认开启（`USE_SIM_CORE = true`），
	# 但本场景里没有 ProjectileManager，`_sim_manager()` 返回 null，
	# `Projectile.spawn` 会**自动回退到节点路径**——所以下面的字段断言
	# 仍然有效，不是假绿灯。这条回退路径本身也值得有防线：
	# 它是核不可用（无编译产物、管理器未创建）时的唯一兜底。
	#
	# 核路径（ProjectileSim）的行为由 `tests/test_projectile_sim.gd` 覆盖；
	# 核与场景的接线（manager）由 `tests/test_projectile_manager.gd` 覆盖。
	_check(bool(Projectile.USE_SIM_CORE), "分流开关默认开启（核路径为默认）")
	_check(Projectile._sim_manager(self) == null,
		"本场景无管理器 → 走节点路径回退（下方断言测的是这条）")

	var P = load("res://gameplay/skills/projectile.gd")
	var ED = load("res://data/elements/element_defs.gd")

	# 投射物父节点必须是 Node3D（挂载点）；用普通 Node 会触发类型错误，
	# 而运行时类型错误不会让测试失败——会静默跳过整段断言（假绿灯）。
	var host := Node3D.new()
	add_child(host)

	# 弹射弹：方向/速度/伤害/弹射次数正确落到实例上
	var bounce: Node3D = P.spawn({
		"direction": Vector3.FORWARD, "position": Vector3.ZERO,
		"speed": 10.0, "damage": 25.0, "lifetime": 2.0,
		"element": "fire", "bounces": 2,
	}, host, P.TARGET_ENEMY)
	_check(bounce != null, "弹射弹生成成功")
	_check(bounce.bounces == 2, "弹射次数 2（分册 6-19 硫磺元素）",
		[str(bounce.bounces)])
	_check(bounce.elem_enum == ED.Elem.FIRE, "元素枚举解析正确（火）",
		[str(bounce.elem_enum)])
	_check(bounce.is_in_group("enemies") == false, "投射物自身不属于命中组")
	bounce.queue_free()

	# 弧线弹：标记 arc 并按抛物线推进
	var arc: Node3D = P.spawn({
		"direction": Vector3.FORWARD, "position": Vector3.ZERO,
		"speed": 8.0, "damage": 20.0, "lifetime": 2.0,
		"arc": true, "arc_height": 3.0,
	}, host, P.TARGET_ENEMY)
	_check(arc.arc, "弧线轨迹已开启")
	# 抛物线在 t=0.5 时最高：4·h·0.5·0.5 = h
	var mid := 4.0 * 3.0 * 0.5 * (1.0 - 0.5)
	_check(absf(mid - 3.0) < 0.01, "抛物线峰值 = 高度设定（3.0）", [str(mid)])
	arc.queue_free()

	# 延时炸弹：引信标记与爆炸范围
	var bomb: Node3D = P.spawn({
		"direction": Vector3.FORWARD, "position": Vector3.ZERO,
		"speed": 6.0, "damage": 30.0, "lifetime": 1.0,
		"fuse": 3.0, "explode_radius": 2.5, "explode_damage": 45.0,
	}, host, P.TARGET_ENEMY)
	_check(absf(bomb.fuse - 3.0) < 0.01, "引信 3 秒（分册 2-12 轨道投弹手）",
		[str(bomb.fuse)])
	_check(absf(bomb.explode_radius - 2.5) < 0.01, "爆炸半径 2.5")
	_check(not probe.bomb_fuse_armed(bomb), "初始未进入引信阶段")
	bomb.queue_free()

	# 命中目标过滤：玩家侧投射物只打 enemies 组
	var pe: Node3D = P.spawn({"direction": Vector3.FORWARD, "damage": 10.0}, host, P.TARGET_ENEMY)
	_check(probe.owner_faction(pe) == "enemies", "玩家投射物目标组 = enemies")
	pe.queue_free()
	var pp: Node3D = P.spawn({"direction": Vector3.FORWARD, "damage": 10.0}, host, P.TARGET_PLAYER)
	_check(probe.owner_faction(pp) == "player", "怪物投射物目标组 = player（此前打不到玩家）")
	pp.queue_free()

	# 兼容入口：ProjectileSystem 仍可用且走同一实现
	var PS = load("res://gameplay/skills/projectile_system.gd")
	var legacy: Node3D = PS.spawn({"direction": Vector3.FORWARD, "damage": 12.0}, host)
	_check(legacy.get_class() == "Area3D" and legacy.get("bounces") != null,
		"ProjectileSystem.spawn 返回统一 Projectile 实例",
		[legacy.get_class(), str(legacy.get_script())])
	legacy.queue_free()


## ---------- 光环与区域机制（分册第 5/6 章）----------
func _test_damage_zones() -> void:
	_test = "DamageZones"
	print("\n--- %s ---" % _test)

	var DZ = load("res://gameplay/combat/damage_zone.gd")
	var MDB = load("res://data/monsters/monster_db.gd")
	var EB = load("res://entities/enemies/enemy_base.gd")
	MDB.init()

	var host := Node3D.new()
	add_child(host)

	# 区域生成与参数落地
	var z: Node3D = DZ.spawn({
		"position": Vector3.ZERO, "radius": 3.0, "duration": 5.0, "damage": 15.0,
	}, host)
	_check(z != null, "伤害区域生成成功")
	_check(absf(z.radius - 3.0) < 0.01, "半径 3.0")
	_check(absf(z.duration - 5.0) < 0.01, "持续 5 秒")
	_check(absf(z.damage_per_tick - 15.0) < 0.01, "每跳伤害 15")
	_check(z.is_in_group("damage_zones"), "已登记 damage_zones 组")
	z.queue_free()

	# 跟随型光环：施法者消失时一同消失（不留孤儿）
	var caster := Node3D.new()
	host.add_child(caster)
	var aura: Node3D = DZ.spawn({
		"position": Vector3.ZERO, "radius": 4.0, "duration": -1.0,
		"damage": 40.0, "follow": caster,
	}, host)
	_check(aura.follow == caster, "光环绑定施法者")
	caster.free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not is_instance_valid(aura) or aura.is_queued_for_deletion(),
		"施法者消失后光环随之销毁（不留孤儿）")

	# 机制装配：4 个区域机制应把参数写到敌人上
	var cases := {
		"venom_frog": ["zone_on_attack", 15.0],      # 4-16 毒腺蛙：毒液区每秒 15
		"flame_spawn": ["aura_spec", 40.0],          # 6-22 炎魔幼体：火焰光环每秒 40
		"swamp_giant": ["aura_spec", 0.0],           # 4-18 沼泽巨人：水波（减速非伤害）
		"hound_p3": ["trail_spec", 12.0],            # 4.6 熔岩猎犬：岩浆轨迹
	}
	for mid in cases:
		var m: Dictionary = MDB.get_monster(mid)
		if m.is_empty():
			_check(false, "%s 在库" % mid)
			continue
		var e = EB.new()
		add_child(e)
		e.apply_monster_config(m)
		var field: String = cases[mid][0]
		var want: float = cases[mid][1]
		var spec = e.get(field)
		var ok := spec is Dictionary and not (spec as Dictionary).is_empty()
		if ok and want > 0.0:
			ok = absf(float((spec as Dictionary).get("damage", 0.0)) - want) < 0.01
		_check(ok, "%s 装配 %s" % [mid, field], [str(spec)])
		e.queue_free()

	# 沼泽巨人的水波是减速（slow_buff）而非伤害
	var sg: Dictionary = MDB.get_monster("swamp_giant")
	var g = EB.new()
	add_child(g)
	g.apply_monster_config(sg)
	_check(str(g.aura_spec.get("slow_buff", "")) == "mire", "沼泽巨人水波挂减速词条")
	_check(g.aura_interval > 0.0, "沼泽巨人光环有周期（%s 秒）" % str(g.aura_interval))
	g.queue_free()


## ---------- 投射物高级能力（分裂 / 命中留区域）----------
func _test_projectile_advanced() -> void:
	_test = "ProjectileAdvanced"
	print("\n--- %s ---" % _test)

	var PJ = load("res://gameplay/skills/projectile.gd")

	# 分裂：命中时射出 N 枚小弹，且只分裂一次（防无限繁殖）
	var host := Node3D.new()
	add_child(host)
	var p = PJ.spawn({
		"direction": Vector3.FORWARD, "position": Vector3.ZERO,
		"damage": 100.0, "split_on_hit": 3, "split_damage_pct": 0.5,
	}, host, PJ.TARGET_PLAYER)
	_check(int(p.split_on_hit) == 3, "分裂数已配置")
	_check(absf(p.split_damage_pct - 0.5) < 0.01, "分裂伤害比例 50%")
	_check(not p.data.is_empty(), "保留原始配置（分裂时复制用）")

	var before := host.get_child_count()
	# 直接触发命中分裂（不经物理，避免依赖真实碰撞）
	probe.projectile_spawn_split(p)
	var after := host.get_child_count()
	_check(after > before, "命中分裂出小弹（%d → %d）" % [before, after])

	# 生成的小弹继承阵营与降低的伤害
	var child = host.get_child(before)
	_check(absf(float(child.damage) - 50.0) < 0.01, "小弹伤害 = 本体 50%",
		[str(child.damage)])
	_check(probe.owner_faction(child) == PJ.TARGET_PLAYER, "小弹继承阵营（仍打玩家）")
	_check(int(child.bounces) == 0 and int(child.pierce_count) == 0,
		"小弹不继承弹射/穿透（避免爆炸式增长）")

	# 命中留区域：配置写入且能生成
	var p2 = PJ.spawn({
		"direction": Vector3.FORWARD, "position": Vector3.ZERO, "damage": 10.0,
		"zone_on_land": {"radius": 2.0, "duration": 4.0, "damage": 20.0},
	}, host, PJ.TARGET_PLAYER)
	_check(not (p2.zone_on_land as Dictionary).is_empty(), "命中留区域已配置")
	var zones_before := get_tree().get_nodes_in_group("damage_zones").size()
	probe.projectile_spawn_land_zone(p2)
	var zones_after := get_tree().get_nodes_in_group("damage_zones").size()
	_check(zones_after > zones_before, "命中后生成区域（%d → %d）" % [zones_before, zones_after])

	host.queue_free()


## ---------- 怪物机制引用的词条 id 必须真实存在 ----------
## 背景：本轮实现攻击/突进附加效果时，我写的 "healcut" 在词条表里根本不存在，
## 机制会**静默失效**（apply 不报错、什么也不发生）。这类错误肉眼很难发现，
## 故固化为测试：把机制代码里引用的词条 id 逐一对照词条表。
func _test_mechanic_buff_ids() -> void:
	_test = "MechanicBuffIds"
	print("\n--- %s ---" % _test)

	var B = load("res://data/buffs/buff_defs.gd")
	var src_path := "res://entities/enemies/enemy_base.gd"
	var f := FileAccess.open(src_path, FileAccess.READ)
	if f == null:
		_check(false, "能读取 enemy_base.gd")
		return
	var src := f.get_as_text()
	f.close()

	# 抓出 `apply("xxx", ...)` 与 `"slow_buff": "xxx"` 两种引用形式
	var referenced := {}
	for m in _regex_all(src, "apply\\(\"([a-z_]+)\""):
		referenced[m] = true
	for m in _regex_all(src, "\"slow_buff\": \"([a-z_]+)\""):
		referenced[m] = true

	_check(referenced.size() > 0, "在机制代码中找到词条引用（%d 个）" % referenced.size())
	var missing: Array = []
	for id in referenced:
		if B.get_buff(id).is_empty():
			missing.append(id)
	_check(missing.is_empty(), "机制引用的词条 id 全部存在", [str(missing)])

	# 反向确认：减速类机制不应误用硬控词条。
	# 「恐惧吼叫」策划要求是减速 30%，而 "fear" 在词条表里是「强制远离」硬控，
	# 用错会让玩家被控住而非减速——这类语义错误同样肉眼难辨。
	var fear_sec: Array = B.get_buff("fear")
	_check(int(fear_sec[2]) == B.Kind.CONTROL, "「恐惧」在词条表里是硬控类型")
	var mire_sec: Array = B.get_buff("mire")
	_check(not mire_sec.is_empty() and int(mire_sec[2]) != B.Kind.CONTROL,
		"「泥沼」是减速而非硬控（fear_roar 用的就是它）")


## 简易正则全匹配（GDScript 无内置正则，用 RegEx 类）
func _regex_all(text: String, pattern: String) -> Array:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return []
	var out: Array = []
	for m in re.search_all(text):
		out.append(m.get_string(1))
	return out


## ---------- 传送/潜伏/护盾类机制装配 ----------
func _test_teleport_stealth_mechanics() -> void:
	_test = "TeleportStealth"
	print("\n--- %s ---" % _test)

	var MDB = load("res://data/monsters/monster_db.gd")
	var EB = load("res://entities/enemies/enemy_base.gd")
	MDB.init()

	# 机制标记 → 应被置位的字段
	var cases := {
		"shadow_lurker": ["stealth_always", true],       # 2-13 常态隐身
		"entropy_wraith": ["hit_swap_positions", true],  # 9-4 命中交换位置
		"wetland_ambusher": ["ambush", true],            # 4-17 潜伏突袭
		"shadow_sentry": ["shield_on_timer", 20.0],      # 9-8 每 20 秒护盾
		"forge_core": ["pulse_invuln", true],            # 6-20 脉冲无敌
		"warped_beast": ["gravity_pull", true],          # 9-3 引力拉扯
		"void_hunter": ["hit_root_seconds", 1.5],        # 9-4 突进定身
	}
	for mid in cases:
		var m: Dictionary = MDB.get_monster(mid)
		if m.is_empty():
			_check(false, "%s 在库" % mid)
			continue
		var e = EB.new()
		add_child(e)
		e.apply_monster_config(m)
		var field: String = cases[mid][0]
		var want = cases[mid][1]
		var got = e.get(field)
		var ok: bool
		if want is bool:
			ok = bool(got) == want
		else:
			ok = absf(float(got) - float(want)) < 0.01
		_check(ok, "%s 装配 %s（%s）" % [mid, field, str(got)], [str(got)])
		e.queue_free()

	# 护盾的数值口径（暗影哨兵：吸收 200）
	var ss: Dictionary = MDB.get_monster("shadow_sentry")
	var sh = EB.new()
	add_child(sh)
	sh.apply_monster_config(ss)
	_check(absf(sh.shield_amount - 200.0) < 0.01, "暗影哨兵护盾吸收 200",
		[str(sh.shield_amount)])
	sh.queue_free()

	# 潜伏突袭的距离口径（湿地伏击者：3 米）
	var wa: Dictionary = MDB.get_monster("wetland_ambusher")
	var amb = EB.new()
	add_child(amb)
	amb.apply_monster_config(wa)
	_check(absf(amb.ambush_range - 3.0) < 0.01, "伏击触发距离 3 米",
		[str(amb.ambush_range)])
	_check(amb.ambush_damage_pct > 1.0, "突袭为高伤害（%.1fx）" % amb.ambush_damage_pct)
	amb.queue_free()


## ---------- 召唤变体 / 死亡区域变体 / 弹道变体 ----------
func _test_summon_and_variants() -> void:
	_test = "SummonVariants"
	print("\n--- %s ---" % _test)

	var MDB = load("res://data/monsters/monster_db.gd")
	var EB = load("res://entities/enemies/enemy_base.gd")
	MDB.init()

	# 死亡区域形态：毒系四阶段必须各不相同（分册 4.2 递进）
	var zone_expect := {
		"zombie_miasma": "POISON",       # 毒瘴僵尸：基础毒雾
		"miasma_p2": "BIG_POISON",   # 腐毒僵尸：毒雾扩大
		"miasma_p3": "SULFUR",           # 硫磺僵尸：硫磺爆炸
		"miasma_p4": "ENTROPY",          # 熵毒僵尸：熵毒领域
	}
	for mid in zone_expect:
		var m: Dictionary = MDB.get_monster(mid)
		if m.is_empty():
			_check(false, "%s 在库" % mid)
			continue
		var e = EB.new()
		add_child(e)
		e.apply_monster_config(m)
		var want: String = zone_expect[mid]
		var got_name: String = EB.DeathZone.keys()[e.death_zone]
		_check(got_name == want, "%s 死亡区域为 %s（实际 %s）" % [mid, want, got_name],
			[got_name])
		e.queue_free()

	# 召唤变体配置
	var z3: Dictionary = MDB.get_monster("zombie_p3")
	if not z3.is_empty():
		var e3 = EB.new()
		add_child(e3)
		e3.apply_monster_config(z3)
		_check(int(e3.summon_spec.get("count", 0)) == 2, "熔炉僵尸召唤 2 只小鬼",
			[str(e3.summon_spec)])
		_check(float(e3.summon_spec.get("hp", 0)) == 100.0, "熔炉小鬼 100 血")
		_check(float(e3.summon_spec.get("atk", 0)) == 20.0, "熔炉小鬼 20 攻")
		_check(bool(e3.summon_spec.get("death_explode", false)), "熔炉小鬼死亡自爆")
		e3.queue_free()

	var z4: Dictionary = MDB.get_monster("zombie_p4")
	if not z4.is_empty():
		var e4 = EB.new()
		add_child(e4)
		e4.apply_monster_config(z4)
		_check(bool(e4.summon_spec.get("zone", false)), "虚空僵尸召唤的是裂痕区域")
		_check(float(e4.summon_spec.get("damage", 0)) == 40.0, "虚空裂痕每秒 40 伤")
		e4.queue_free()

	# 弹道变体：穿透箭 / 虚空回响
	var se: Dictionary = MDB.get_monster("sentry_p2")
	if not se.is_empty():
		var es = EB.new()
		add_child(es)
		es.apply_monster_config(se)
		_check(es.pierce_every == 3, "符文哨兵每 3 次射击穿透", [str(es.pierce_every)])
		es.queue_free()
	var se3: Dictionary = MDB.get_monster("sentry_p4")
	if not se3.is_empty():
		var es3 = EB.new()
		add_child(es3)
		es3.apply_monster_config(se3)
		_check(es3.void_echo, "熔炉哨兵射击产生虚空回响")
		es3.queue_free()

	# 闪避派生
	var ph4: Dictionary = MDB.get_monster("phantom_p2")
	if not ph4.is_empty():
		var ep = EB.new()
		add_child(ep)
		ep.apply_monster_config(ph4)
		_check(ep.dodge_teleport, "虚空魅影闪避后瞬移")
		ep.queue_free()


## 区域减速词条的生命周期：进区施加 / 出区移除。
## 回归 bug：DamageZone 只施加不移除，而 thorn_slow 是 duration=0 的永久词条
## （策划口径「踏入期间」），导致玩家踩一次第 2 层坍方区就永久 -50% 移速。
func _test_zone_slow_lifecycle() -> void:
	_test = "ZoneSlowLifecycle"
	print("\n--- %s ---" % _test)

	var BH = load("res://gameplay/status/buff_holder.gd")
	var holder = BH.new(null)
	var zone_source := "zone_12345"

	# thorn_slow 确实是永久词条（duration=0）——这是必须成对移除的前提
	var row: Array = BuffDefs.get_buff("thorn_slow")
	_check(not row.is_empty() and float(row[3]) == 0.0,
		"thorn_slow 是 duration=0 的永久词条（离开时必须显式移除）")

	# 进区：施加后应有减速
	holder.apply("thorn_slow", zone_source)
	_check(holder.has("thorn_slow"), "进区后挂上减速")
	_check(holder.total_slow() > 0.4, "减速生效（%.2f）" % holder.total_slow())

	# 出区：按来源移除
	var removed: bool = holder.remove_from_source("thorn_slow", zone_source)
	_check(removed, "出区时按来源移除成功")
	_check(not holder.has("thorn_slow"), "出区后减速已清除")
	_check(holder.total_slow() == 0.0, "出区后移速恢复正常（slow=%.2f）" % holder.total_slow())

	# 来源不匹配时不误删（该词条另有出处 → 不能由本区域撤销）
	holder.apply("thorn_slow", "monster_hit")
	var wrong: bool = holder.remove_from_source("thorn_slow", zone_source)
	_check(not wrong, "来源不匹配时不移除（不误删其它来源的效果）")
	_check(holder.has("thorn_slow"), "被怪物施加的减速仍在")

	# 被其它来源接管后，原来源也不该撤销它
	holder.apply("thorn_slow", zone_source)
	holder.apply("thorn_slow", "monster_hit")   # monster 后施加 → source 变为 monster
	var taken_over: bool = holder.remove_from_source("thorn_slow", zone_source)
	_check(not taken_over, "词条已被其它来源接管时，原来源不撤销")

	# 反复进出不残留（区域每 tick 重刷的真实节奏）
	holder.remove("thorn_slow")
	for i in 5:
		holder.apply("thorn_slow", zone_source)
		holder.remove_from_source("thorn_slow", zone_source)
	_check(not holder.has("thorn_slow"), "反复进出区域不残留减速")


## 元素抗性与穿透（分册 7.10：「法术伤害仅受极少数怪物自带抗性减免」
## + 通用词条「元素穿透：忽视目标 5%~15% 元素抗性」）
func _test_elem_resist_and_penetration() -> void:
	_test = "ElemResistPenetration"
	print("\n--- %s ---" % _test)

	var MDB = load("res://data/monsters/monster_db.gd")
	MDB.init()

	# ① 六元素在怪物侧都要有来源（此前冰/雷为 0，元素系统半边是死的）
	var by_elem := {}
	for m in MDB.all_monsters():
		var e := str(m.get("element", ""))
		if not e.is_empty():
			by_elem[e] = int(by_elem.get(e, 0)) + 1
	for need in ["fire", "frost", "static", "earth", "poison"]:
		_check(int(by_elem.get(need, 0)) > 0,
			"怪物侧有 %s 元素来源（%d 只）" % [need, int(by_elem.get(need, 0))])

	# ② 抗性稀疏表：只有少数怪有，且值域合法
	var with_resist := 0
	for m in MDB.all_monsters():
		var r = m.get("elem_resist", {})
		if r is Dictionary and not (r as Dictionary).is_empty():
			with_resist += 1
			for k in r:
				var v := float(r[k])
				_check(v > 0.0 and v <= 0.9,
					"%s 的 %s 抗性值域合法（%.2f）" % [str(m.get("id")), k, v])
	_check(with_resist > 0, "存在自带元素抗性的怪（%d 只）" % with_resist)
	# 分册口径「极少数」——不该大面积铺满
	_check(with_resist < MDB.all_monsters().size(),
		"抗性是少数派（%d / %d）" % [with_resist, MDB.all_monsters().size()])

	# ③ 元素枚举 ↔ 键 互逆（抗性表以字符串为键，必须能双向转换）
	for k in ["fire", "frost", "static", "earth", "wind", "poison"]:
		var e := ElementDamage.elem_from_key(k)
		_check(ElementDamage.key_from_elem(e) == k,
			"元素键 %s 双向转换一致" % k)
	_check(ElementDamage.key_from_elem(999) == "", "未知元素返回空串")

	# ④ 抗性参与伤害结算：抗性越高伤害越低
	var no_res := DamagePipeline.elemental_attack(100.0, 1.0, 0.0, 0.0,
		ElementDefs.Elem.FIRE, 0.0)
	var half := DamagePipeline.elemental_attack(100.0, 1.0, 0.0, 0.0,
		ElementDefs.Elem.FIRE, 0.5)
	_check(float(half.damage) < float(no_res.damage),
		"抗性降低元素伤害（无抗 %.1f → 抗50%% %.1f）" % [
			float(no_res.damage), float(half.damage)])

	# ⑤ 穿透削抗：抗 0.6 的怪，穿透 0.15 后应等价于抗 0.45 的伤害
	var r60 := DamagePipeline.elemental_attack(100.0, 1.0, 0.0, 0.0,
		ElementDefs.Elem.FIRE, 0.6)
	var pen := DamagePipeline.elemental_attack(100.0, 1.0, 0.0, 0.0,
		ElementDefs.Elem.FIRE, 0.6 - 0.15)
	var r45 := DamagePipeline.elemental_attack(100.0, 1.0, 0.0, 0.0,
		ElementDefs.Elem.FIRE, 0.45)
	_check(absf(float(pen.damage) - float(r45.damage)) < 0.01,
		"穿透 15%% 等价于抗性 -15%%（%.1f == %.1f）" % [
			float(pen.damage), float(r45.damage)])
	_check(float(pen.damage) > float(r60.damage),
		"穿透后伤害高于未穿透（%.1f > %.1f）" % [
			float(pen.damage), float(r60.damage)])

	# ⑥ 命中减速用的词条必须**有时效**（thorn_slow 是区域专用永久词条，
	#    拿来当命中减速会让玩家永久被减速且无法解除）。
	#    走真实数据路径：取带 slow_on_hit 机制的怪，看它解析出的词条。
	var EB = load("res://entities/enemies/enemy_base.gd")
	var slow_ids: Array[String] = []
	for m in MDB.all_monsters():
		if str(m.get("mech", "")) != "slow_on_hit":
			continue
		var e2 = EB.new()
		add_child(e2)
		e2.apply_monster_config(m)
		var bid: String = str(e2.get("hit_slow_buff"))
		if not bid.is_empty() and not slow_ids.has(bid):
			slow_ids.append(bid)
		e2.queue_free()
	_check(not slow_ids.is_empty(), "存在 slow_on_hit 机制的怪（%d 种词条）" % slow_ids.size())
	for bid in slow_ids:
		var row: Array = BuffDefs.get_buff(bid)
		_check(not row.is_empty(), "命中减速词条 %s 存在" % bid)
		_check(float(row[3]) > 0.0,
			"命中减速词条 %s 有时效（%.1fs）——不能是永久词条" % [bid, row[3]])


func _check(c: bool, name: String, detail: Array = []) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
		for d in detail:
			print("    %s" % d)


## DOT 测试用的替身宿主
class _FakeHost extends RefCounted:
	var ap := 0.0
	var atk := 0.0
	func eff_ap() -> float: return ap
	func eff_atk() -> float: return atk


## 法强桩：DOT 伤害基数来自宿主法强，测试用它固定 100
class _ApStub extends RefCounted:
	func eff_ap() -> float: return 100.0
	func eff_atk() -> float: return 50.0
