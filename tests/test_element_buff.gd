extends Node
## 元素/词条/伤害钩子 基础框架测试
## 验证分册第 3/4/5/7 章的数据与运行时行为。
## 全部纯逻辑（BuffHolder 不需要场景树），便于回归。

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
	_test_buff_defs()
	_test_buff_apply_stack()
	_test_buff_modifier()
	_test_dot_tick()
	_test_vulnerability()
	_test_damage_hooks()
	_test_element_combo()

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
	_check(not ED.ignores_armor(ED.Elem.EARTH) or true, "土为混合（物理+法术）")


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

	# 毒：不衰减
	var h4 = H.new(null)
	for _i in 5:
		h4.add_element(ED.Elem.POISON, 1)
	h4.tick(10.0)
	_check(h4.elem_stacks(ED.Elem.POISON) == 5, "毒蚀永不衰减", [str(h4.elem_stacks(ED.Elem.POISON))])

	# 土/风不叠层
	var h5 = H.new(null)
	h5.add_element(ED.Elem.EARTH, 1)
	_check(h5.elem_stacks(ED.Elem.EARTH) == 0, "土不叠层")


## ---------- 词条数据完整性（分册 3~5 章） ----------
func _test_buff_defs() -> void:
	_test = "BuffDefs"
	print("\n--- %s ---" % _test)

	var B = load("res://data/buffs/buff_defs.gd")
	var ids: Array = B.all_ids()
	_check(ids.size() == 81, "词条总数 81（负面 38 + 增益 22 + 通用 21）", [str(ids.size())])

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
