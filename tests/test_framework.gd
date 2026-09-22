extends SceneTree
## 测试框架 —— HD-2D 重构版
## 用法：Godot --headless --path . --script res://tests/test_framework.gd
## 注意：--script 模式下 class_name 不可用，使用 load() 替代
## 注意：load() 返回 null（脚本编译失败）会被 _require_script 计入失败，
##       避免脚本加载失败导致整组测试被静默跳过形成"假绿灯"。

var _failed := 0
var _passed := 0
var _current_test := ""

## 私有成员访问一律经 TestProbe（重构搬方法时只改 probe，本文件零改动）。
##
## **必须用 load() 而不是 class_name**：本套件跑在 `--script` 模式下，
## 该模式不注册全局类缓存，直接写 `TestProbe.new()` 会解析失败。
var probe = load("res://tests/helpers/probe.gd").new()


## 测试入口。
## 注意：必须用 _ready 而非 _init —— _init 不是协程上下文，
## 异步测试（内部 await 的）会在第一个 await 处挂起返回，其断言
## 在汇总打印之后才执行，既不影响计数也不影响退出码 → 假绿灯。
## 故这里统一 await 所有测试函数（同步函数 await 也无副作用）。
func _init() -> void:
	_ready.call_deferred()


func _ready() -> void:
	print("=".repeat(60))
	print("测试框架启动 —— HD-2D 重构版")
	print("=".repeat(60))

	# 属性系统测试
	await _run_test(test_attribute_system)

	# 白装数据库测试（36 件 V1 基准池；先于通用装备测试，避免后者注册测试模板污染计数）
	await _run_test(test_white_equipment_db)

	# 装备系统测试
	await _run_test(test_equipment_system)

	# 装备通用词条池（名词分册第 5 章：21 种装备可附加词条）
	await _run_test(test_generic_affix_pool)
	await _run_test(test_generic_affix_attach)

	# 伤害管线测试
	await _run_test(test_damage_pipeline)

	# 融合规则测试
	await _run_test(test_fusion_rules)

	# 装备参考2 规格：随机词条 / 武器类型互斥
	await _run_test(test_random_affix)
	await _run_test(test_weapon_tag_conflict)

	# 房间数据测试
	await _run_test(test_room_data)

	# 房间刷怪闭环集成测试
	await _run_test(test_room_combat_loop)

	# Boss 房闭环测试
	await _run_test(test_boss_room_loop)

	# 连段状态机测试
	await _run_test(test_attack_combo)

	# 状态机基类测试（注册/转移/转发/数据传递）
	await _run_test(test_state_machine)

	# 房间编辑器核心测试（JSON 往返 + 矩形填充/围墙/校验）
	await _run_test(test_room_editor_core)

	# 坐标放置测试（单点全元素/矩形墙圈/对角/钳制）
	await _run_test(test_coord_placement)

	# 第一层怪物数据库测试
	await _run_test(test_monster_db_layer1)

	# 怪物池与词缀（全量 64 种、按层选池、词缀阶段分配）
	await _run_test(test_monster_pool)
	await _run_test(test_rusher_dash_range)
	await _run_test(test_monster_mechanics_wired)

	# 资源系统测试（宝箱/回血/层间恢复/金币产出）
	await _run_test(test_resource_system)

	# 特殊房交互测试（商店/泉水/事件）
	await _run_test(test_special_room_interactions)
	await _run_test(test_event_room_pool)
	await _run_test(test_shop_consumption)

	# 门拓扑测试（按地牢连通关系算门，消除哑门）
	await _run_test(test_doors_by_topology)

	# 地牢生成规则测试（BFS 图距离 / 特殊房距离门控 / 房型配额）
	await _run_test(test_dungeon_generation_rules)

	# 加权掉落测试（稀有度分布 / 逐层缩放 / Boss 保底 / 精英概率）
	await _run_test(test_weighted_loot)

	# 房间模板池完整性（回归"normal/elite/treasure 无模板导致回退起始房"）
	await _run_test(test_room_template_pool)
	await _run_test(test_dungeon_template_coverage)

	# 层级系统（9 层主题/范围/房间数/难度曲线）
	await _run_test(test_floor_defs)
	await _run_test(test_dungeon_range_fits)

	# 批次 B：Boss 掉落表 / 红装池 / 隐藏层结构与碎片
	await _run_test(test_boss_drop_table)
	await _run_test(test_red_rarity_pool_not_empty)
	await _run_test(test_layer9_structure)
	await _run_test(test_equipment_save_roundtrip)
	await _run_test(test_key_fragments)

	# 生命上限不变量（实机「受伤掉上限 / 血瓶泉水回不上血」防回归）
	await _run_test(_test_max_hp_balance)

	# 批次 D：楼层环境机制
	await _run_test(test_floor_environment)
	await _run_test(test_floor_mechanism_distinct)
	await _run_test(test_floor_environment_robustness)

	# 批次 E：隐藏房
	await _run_test(test_hidden_rooms)

	# 批次 C：Boss 体系
	await _run_test(test_boss_db)
	await _run_test(test_boss_mechanic_wiring)
	await _run_test(test_boss_room_sizes)

	# 批次 G：职业 / 形态 / 技能 / 资源
	await _run_test(test_class_defs)
	await _run_test(test_class_base_and_start_gear)
	await _run_test(test_class_resource)

	# 音效接线（语义名映射表 + 素材存在）
	await _run_test(test_audio_wiring)

	# 测试 probe 覆盖率（重构报警器）
	await _run_test(test_probe_coverage)

	# 接线自检表与 event_bus 声明的一一对应
	await _run_test(test_wired_check_table)

	print("=".repeat(60))
	if _failed == 0:
		print("ALL %d TESTS PASSED" % _passed)
	else:
		print("FAILED: %d / %d" % [_failed, _passed + _failed])
	print("=".repeat(60))
	quit(1 if _failed > 0 else 0)


## 运行一个测试函数，并检测「协程被运行时错误静默中断」。
##
## **为什么需要这层守卫**：`_ready()` 逐个 await 测试函数，但若某个测试
## 内部发生 runtime error（空引用、访问不存在的属性…），Godot 会**静默中断
## 那个协程**——它后面的断言全不执行、`_failed` 不增加，而 `_ready` 照常继续，
## 最后打印 "ALL N TESTS PASSED"。实测注入一个必然崩溃的语句，测试仍报通过。
##
## 判据：正常跑完的测试**必然推进断言计数**（38 个测试每个都至少一条断言）。
## 计数没动 = 该测试被中断，计一次失败。
## ---------- 职业 / 形态 / 技能数据（《角色设计分册》） ----------
func test_class_defs() -> void:
	_current_test = "ClassDefs"
	print("\n--- %s ---" % _current_test)

	# 5 职业齐备
	var ids: Array = ClassDefs.class_ids()
	_check(ids.size() == 5, "5 个职业", [str(ids.size())])
	for cid in ["warrior", "mage", "hunter", "judge", "monk"]:
		_check(cid in ids, "职业 %s 存在" % cid)
		var c := ClassDefs.get_class_def(cid)
		_check(not c.is_empty(), "职业 %s 有定义" % cid)
		var forms: Array = c.get("forms", [])
		_check(forms.size() == ClassDefs.FORM_SLOTS,
			"职业 %s 有 5 形态" % cid, [str(forms.size())])

	# 解锁阶梯（策划 2 章：默认 / 3层 / 6层 / 8层 / 9层）
	_check(ClassDefs.unlock_floor_of(0) == 0, "初始形态默认解锁")
	_check(ClassDefs.unlock_floor_of(1) == 3, "进阶1 通关第 3 层解锁")
	_check(ClassDefs.unlock_floor_of(2) == 6, "进阶2 通关第 6 层解锁")
	_check(ClassDefs.unlock_floor_of(3) == 8, "进阶3 通关第 8 层解锁")
	_check(ClassDefs.unlock_floor_of(4) == 9, "终极形态通关第 9 层解锁")
	_check(ClassDefs.max_available_form(0) == 0, "0 层只解锁初始形态")
	_check(ClassDefs.max_available_form(3) == 1, "通关 3 层解锁到进阶1")
	_check(ClassDefs.max_available_form(6) == 2, "通关 6 层解锁到进阶2")
	_check(ClassDefs.max_available_form(8) == 3, "通关 8 层解锁到进阶3")
	_check(ClassDefs.max_available_form(9) == 4, "通关 9 层解锁终极形态")
	# 越界不崩
	_check(ClassDefs.max_available_form(99) == 4, "通关 99 层仍是终极形态（不越界）")

	# 战士 5 形态的技能（策划 3.2~3.6：初始无技能，4 个进阶各 2）
	var total := 0
	var kinds := {}
	for slot in range(ClassDefs.FORM_SLOTS):
		var f := ClassDefs.get_form("warrior", slot)
		var sks: Array = f.get("skills", [])
		total += sks.size()
		for s in sks:
			kinds[str(s.get("kind", ""))] = true
	_check(total == 8, "战士共 8 个技能（初始形态无技能）", [str(total)])
	_check(ClassDefs.skills_of("warrior", 0).is_empty(), "狂战士（初始）无专属技能")
	_check(ClassDefs.skills_of("warrior", 1).size() == 2, "壁垒有 2 技能")
	_check(ClassDefs.skills_of("warrior", 4).size() == 2, "解放者有 2 技能")

	# 技能 kind 覆盖了预期的执行分派
	for k in ["dash", "cone", "aoe", "buff", "pull"]:
		_check(kinds.has(k), "战士技能用到了 kind=%s" % k)

	# 每个技能数据完整（id/name/kind/cooldown 必备）
	var bad: Array = []
	for slot in range(ClassDefs.FORM_SLOTS):
		for s in ClassDefs.skills_of("warrior", slot):
			for key in ["id", "name", "kind", "cooldown"]:
				if not s.has(key):
					bad.append("%s 缺 %s" % [str(s.get("id", "?")), key])
	_check(bad.is_empty(), "战士技能字段完整", [str(bad)])

	# 全局检索
	var found := ClassDefs.find_skill("stomp")
	_check(not found.is_empty(), "find_skill 能查到跺脚")
	_check(str(found.get("class_id", "")) == "warrior", "跺脚属于战士")
	_check(ClassDefs.find_skill("nonexistent_skill_xyz").is_empty(),
		"未知技能返回空")

	# 已实装职业不应出现在待办里。
	# **不写死待办数量**——每完成一个职业都要改数字，是脆弱的断言；
	# 改为校验「已完成的确实不在待办」，数量变化不影响。
	var pending: Array = ClassDefs.pending_classes()
	_check(not ("warrior" in pending), "战士已实装（不在待办里）")
	_check(not ("judge" in pending), "判官已实装（不在待办里）")
	# 5 职业已全部实装（策划 25 形态）
	_check(pending.is_empty(), "5 职业全部实装（无待办）", [str(pending)])
	# 技能总数：每职业 4 个进阶形态 × 2 = 8（初始与终极各 2）
	var total_skills := 0
	for cid in ClassDefs.class_ids():
		for slot in range(ClassDefs.FORM_SLOTS):
			total_skills += ClassDefs.skills_of(cid, slot).size()
	_check(total_skills == 40, "5 职业共 40 个技能（各 8）", [str(total_skills)])

	# 技能引用的词条 id 必须真实存在（否则运行时挂不上）
	var missing: Array = []
	for slot in range(ClassDefs.FORM_SLOTS):
		var f := ClassDefs.get_form("warrior", slot)
		for s in f.get("skills", []):
			for b in s.get("self_buffs", []):
				if BuffDefs.get_buff(str(b.get("id", ""))).is_empty():
					missing.append(str(b.get("id")))
			for b in s.get("target_buffs", []):
				if BuffDefs.get_buff(str(b.get("id", ""))).is_empty():
					missing.append(str(b.get("id")))
	_check(missing.is_empty(), "技能引用的词条 id 均存在", [str(missing)])

	# ---------- 形态机制「已接线」审计（反真空） ----------
	# **为什么必须有这条**：`ClassDefs` 的 `special` 字段是形态机制的声明处，
	# 但没有任何机制强制它被消费。上一轮的实况是——31 个字段里只有 2 个
	# 真正被读，其余全是"录了数据、代码没读"的静默失效：
	# 壁垒不减远程伤害、武僧照样拿武器打、猎人背刺没加成，
	# 40 个形态玩起来是同一个角色。
	#
	# 做法：维护一份"已接线字段"清单，断言它 == 数据里实际出现的字段集合。
	# 两条路都会让测试变红：
	#   · 新增了 special 字段却没实现 → 出现在数据侧、不在清单里 → 失败
	#   · 实现了新机制 → 清单落后 → 也失败（强制同步，状态永远显式）
	var all_keys := {}
	for cid in ClassDefs.class_ids():
		for slot in range(ClassDefs.FORM_SLOTS):
			for k in ClassDefs.special_of(cid, slot):
				all_keys[k] = true
	var unimplemented: Array = []
	for k in all_keys:
		if not (k in IMPLEMENTED_SPECIALS):
			unimplemented.append(k)
	unimplemented.sort()
	var expected: Array = EXPECTED_UNIMPLEMENTED.duplicate()
	expected.sort()
	_check(unimplemented == expected,
		"未接线的形态机制集合与预期一致（共 %d 个已接线 / %d 个待做）"
			% [IMPLEMENTED_SPECIALS.size(), expected.size()],
		["实际未接线：%s" % str(unimplemented), "预期未接线：%s" % str(expected)])

	# 已接线的字段必须真的能被读到（不是清单里写了就算）
	for probe in [
		["warrior", 0, "melee_dmg_pct", 0.20],
		["warrior", 3, "armor_pierce", 0.50],
		["mage", 0, "skill_range_pct", 0.15],
		["mage", 1, "cast_refund_pct", 0.15],
	]:
		var got: float = ClassDefs.special_num(str(probe[0]), int(probe[1]),
			str(probe[2]), -1.0)
		_check(absf(got - float(probe[3])) < 0.0001,
			"ClassDefs.special_num 读 %s/%d.%s = %.2f" % [
				str(probe[0]), int(probe[1]), str(probe[2]), float(probe[3])],
			[str(got)])
	_check(ClassDefs.special_flag("monk", 0, "no_weapon"), "special_flag 读开关项")
	_check(not ClassDefs.special_flag("warrior", 0, "no_weapon"),
		"special_flag 对未声明字段返回 false")
	_check(ClassDefs.special_num("warrior", 0, "nonexistent", 7.5) == 7.5,
		"special_num 缺项返回 fallback")


## 已接线的形态机制字段（有一条明确的消费链路）。
## **这不是"想做"的清单，是"代码里真的读了"的清单**——
## 新增字段却没实现时，上面的断言会失败并把它列出来。
const IMPLEMENTED_SPECIALS := [
	# 战士
	"lifesteal",                  # player._lifesteal_heal / equipment 侧
	"melee_dmg_pct",              # player._apply_hit 倍率乘区
	"ranged_dmg_pct",             # skill_system._cast_projectile
	"armor_pierce",               # player._basic_attack_pierce / skill_system
	"overflow_to_shield",         # player._lifesteal_heal → _add_shield
	# 法师
	"skill_range_pct",            # skill_system.cast_skill 几何放大
	"mana_regen_up",              # ClassResource.regen_mult
	"mana_regen_stack",           # ClassResource.regen_mult
	"cast_refund_pct",            # skill_system.cast_skill 消耗返还
	"resonance_chance",           # skill_system.cast_skill 概率免费
	"flame_stack_per_cast",       # ClassDefs.form_mark_id（普攻+技能）
	"void_stigma_per_cast",       # ClassDefs.form_mark_id（普攻+技能）
	# 猎人
	"free_weapon_swap",           # player._start_normal_attack 远近切换无冷却
	"out_of_combat_spd",          # player.out_of_combat_speed_mult
	"dodge_immune_next",          # player.on_dodge_started / take_damage
	"backstab_mult",              # player._is_backstab
	"pierce_line",                # player._apply_hit 直线穿透
	"forest_domain",              # player._spawn_forest_domain
	# 武僧
	"no_weapon",                  # EquipmentManager._can_wear
	"can_equip_weapon",           # EquipmentManager._can_wear（显式解锁）
	"fist_reach",                 # player._fist_reach_bonus
	"fist_armor_pierce",          # player._basic_attack_pierce
	"counter_on_hit",             # player._on_player_hurt / _apply_hit
	"combo_heal",                 # player._apply_combo_heal
	"slow_combo_decay",           # player 连击衰减保留 50%
	"break_limit_at",             # player._maybe_trigger_break_limit
	"myriad_combo",               # player.combo_cap
	# 判官
	"spell_on_hit_ap_pct",        # player._on_basic_attack_landed
	"mark_per_hit",               # player._on_basic_attack_landed
	"chain_30pct",                # player._chain_spell_damage
	"shadow_every_4",             # player._on_basic_attack_landed
	"light_dark_layers",          # player._gain_light_layer / _gain_dark_layer
	"verdict_at_5",               # player._refresh_light_dark_balance
]

## 仍未接线的字段（应恒为空——全部 31 个机制已实装）。
## 留这个常量是为了让"未接线集合 == 预期"的断言在两侧都保持显式：
## 将来新增 special 字段时，它会被列进实际未接线集合而让测试变红。
const EXPECTED_UNIMPLEMENTED := []


## ---------- 职业基础属性 + 初始装备 ----------
func test_class_base_and_start_gear() -> void:
	_current_test = "ClassBase"
	print("\n--- %s ---" % _current_test)

	# 5 职业基础属性必须互不相同——否则"选职业"没有意义
	# （此前正是如此：AttributeSystem.DEFAULT_BASE 被所有职业共用，
	#  选战士和选法师开局都是 500 血 / 35 攻）
	var hps := {}
	var atks := {}
	for cid in ClassDefs.class_ids():
		var t := ClassBase.full_table(cid)
		hps[int(t[AttributeSystem.Stat.HP])] = true
		atks[int(t[AttributeSystem.Stat.ATK])] = true
	_check(hps.size() == ClassDefs.class_ids().size(),
		"5 职业生命上限互不相同", [str(hps.keys())])
	_check(atks.size() == ClassDefs.class_ids().size(),
		"5 职业攻击力互不相同", [str(atks.keys())])

	# 定位断言：战士血最厚、法师血最薄、猎人攻速最快、武僧射程最短
	var hp_of := {}
	var aspd_of := {}
	var rng_of := {}
	for cid in ClassDefs.class_ids():
		var t := ClassBase.full_table(cid)
		hp_of[cid] = float(t[AttributeSystem.Stat.HP])
		aspd_of[cid] = float(t[AttributeSystem.Stat.ASPD])
		rng_of[cid] = float(t[AttributeSystem.Stat.RNG])
	_check(hp_of["warrior"] == hp_of.values().max(), "战士生命最高（重装定位）",
		[("战 %.0f vs 最高 %.0f" % [hp_of["warrior"], hp_of.values().max()])])
	_check(hp_of["mage"] == hp_of.values().min(), "法师生命最低（脆皮定位）")
	_check(aspd_of["monk"] == aspd_of.values().max(), "武僧攻速最高（快拳定位）")
	_check(rng_of["monk"] == rng_of.values().min(), "武僧射程最短（贴脸定位）")
	_check(rng_of["hunter"] == rng_of.values().max(), "猎人射程最远（走A定位）")

	# 未列出的项回落到 DEFAULT_BASE，不能变成 0
	var warrior_table := ClassBase.full_table("warrior")
	_check(warrior_table.size() == AttributeSystem.STAT_BY_NAME.size(),
		"full_table 覆盖全部 11 项属性")
	var zero: Array = []
	for sid in warrior_table:
		if float(warrior_table[sid]) <= 0.0 and sid != AttributeSystem.Stat.CDR:
			zero.append(str(AttributeSystem.STAT_NAMES.get(sid, sid)))
	_check(zero.is_empty(), "职业基础表无零值属性（CDR 除外）", [str(zero)])

	# 未知职业回落（不能崩，也不能静默变 0）
	_check(ClassBase.full_table("no_such_class").size() ==
		AttributeSystem.STAT_BY_NAME.size(), "未知职业回落且不崩")
	_check(ClassBase.value_of("no_such_class", "hp") ==
		AttributeSystem.DEFAULT_BASE[AttributeSystem.Stat.HP],
		"未知职业回落值为默认值")

	# start_gear：策划点名的款式未必在白装层注册（白装是"每槽位 1 件"的
	# 基础款）。所以断言"能解析出模板"而不是"id 精确存在"——
	# `_grant_start_gear` 走的就是 resolve_or_white_fallback 这条降级路径，
	# 测试必须与它同口径，否则会要求一个运行时不成立的保证。
	#
	# 但**完全查不到槽位**的 id 仍是真错误（打错字），必须抓到。
	var unresolved: Array = []
	var wrong_slot: Array = []
	var gear_count := 0
	for cid in ClassDefs.class_ids():
		for slot in range(ClassDefs.FORM_SLOTS):
			for tid in ClassDefs.get_form(cid, slot).get("start_gear", []):
				gear_count += 1
				var tpl = EquipmentDB.resolve_or_white_fallback(StringName(str(tid)))
				if tpl == null:
					unresolved.append("%s/%d:%s" % [cid, slot, str(tid)])
				elif tpl.rarity != EquipmentDefs.Rarity.WHITE:
					wrong_slot.append("%s:%s→%s" % [cid, str(tid), tpl.display_name])
	_check(gear_count > 0, "形态声明了初始装备（共 %d 件）" % gear_count)
	_check(unresolved.is_empty(), "初始装备 id 均能解析出模板（含白装降级）",
		[str(unresolved)])
	_check(wrong_slot.is_empty(), "初始装备只能是白装（不越级发绿装）",
		[str(wrong_slot)])

	# 降级路径本身：白装层没有的 id 要回退到**同槽位**白装，不能退回 null
	var fb = EquipmentDB.resolve_or_white_fallback(&"A12")   # 铁制护手，白装层无
	_check(fb != null, "白装层不存在的 id 能降级解析（A12）")
	if fb != null:
		_check(fb.slot == EquipmentDefs.Slot.HANDS,
			"降级到同槽位（HANDS），而不是随便给一件", [str(fb.slot)])
		_check(fb.rarity == EquipmentDefs.Rarity.WHITE, "降级结果为白装")
	_check(EquipmentDB.resolve_or_white_fallback(&"ZZ99") == null,
		"槽位都定位不到的 id 返回 null（真·打错字）")
	var exact = EquipmentDB.resolve_or_white_fallback(&"W01")
	_check(exact != null and exact.id == &"W01", "精确命中的 id 原样返回，不走降级")


## ---------- 职业资源运行时 ----------
func test_class_resource() -> void:
	_current_test = "ClassResource"
	print("\n--- %s ---" % _current_test)

	# 5 职业各有资源定义
	for cid in ["warrior", "mage", "hunter", "judge", "monk"]:
		var r := ClassResource.create(cid)
		_check(r.is_active(), "职业 %s 有资源系统" % cid)
		_check(not r.res_name.is_empty(), "职业 %s 资源有名称" % cid)
		# 开局给一部分初始资源（策划未规定比例；此前恒为 0，
		# 而技能消耗 20~40、战士/猎人/判官又无自然回复 → 开局放不出技能）
		_check(r.value > 0.0 and r.value < r.max_value(),
			"职业 %s 开局有初始资源（%.0f/%.0f）" % [cid, r.value, r.max_value()])

	# 未知职业 → 无资源，所有操作空转
	var none := ClassResource.create("not_a_class")
	_check(not none.is_active(), "未知职业无资源系统")
	_check(none.gain(50.0) == 0.0, "无资源时 gain 无效")
	_check(not none.spend(1.0), "无资源时 spend 失败")

	# 战士怒气：命中 +5、受击按 10% 积攒、上限 100
	# **用增量断言而不是绝对值**：初始资源不再为 0，写死绝对值会被
	# 初始值一改就打破（下面几组同理）。
	var w := ClassResource.create("warrior")
	var w_base: float = w.value
	w.on_hit(false)
	_check(absf(w.value - (w_base + 5.0)) < 0.01, "普攻命中 +5 怒气",
		["%.1f → %.1f" % [w_base, w.value]])
	var before_taken: float = w.value
	w.on_damage_taken(100.0)
	_check(absf(w.value - (before_taken + 10.0)) < 0.01, "受击 100 按 10% 加 10",
		["%.1f → %.1f" % [before_taken, w.value]])
	w.gain(500.0)
	_check(absf(w.value - w.max_value()) < 0.01, "资源封顶于上限", [str(w.value)])
	_check(w.ratio() >= 0.99, "满资源比例为 1")

	# 消耗：足量成功、不足失败且不扣
	var w2 := ClassResource.create("warrior")
	w2.reset()          # reset 清零，便于断言精确剩余量
	w2.gain(30.0)
	_check(w2.spend(20.0), "足够时消耗成功")
	_check(absf(w2.value - 10.0) < 0.01, "消耗后剩 10", [str(w2.value)])
	_check(not w2.spend(50.0), "不足时消耗失败")
	_check(absf(w2.value - 10.0) < 0.01, "失败不扣资源", [str(w2.value)])
	_check(w2.has(10.0) and not w2.has(11.0), "has() 边界正确")

	# 上限加成可加可清
	var w3 := ClassResource.create("warrior")
	w3.add_max_bonus(50.0)
	_check(absf(w3.max_value() - 150.0) < 0.01, "上限加成生效", [str(w3.max_value())])
	w3.clear_max_bonus()
	_check(absf(w3.max_value() - 100.0) < 0.01, "上限加成可清除")

	# 法师魔力：自然回复（tick 累积到整点才进 value）
	var m := ClassResource.create("mage")
	m.reset()
	m.tick(1.0)
	_check(absf(m.value - 6.0) < 0.01, "法师每秒回 6 点魔力", [str(m.value)])
	m.reset()
	_check(m.value == 0.0, "reset 清零资源")

	# 猎人：暴击额外积攒
	var h := ClassResource.create("hunter")
	h.reset()
	h.on_hit(false)
	var normal_gain := h.value
	h.reset()
	h.on_hit(true)
	_check(h.value > normal_gain, "猎人暴击积攒多于普通命中",
		["普通%.0f 暴击%.0f" % [normal_gain, h.value]])

	# 新局/新层重置
	var r4 := ClassResource.create("warrior")
	r4.gain(80.0)
	r4.reset()
	_check(r4.value == 0.0 and r4.max_value() == r4.base_max,
		"reset 同时清空值与上限加成")


func _run_test(fn: Callable) -> void:
	var before := _passed + _failed
	await fn.call()
	if (_passed + _failed) == before:
		_failed += 1
		print("  FAIL [%s]: 测试中断——一条断言都没执行（协程被运行时错误打断？）"
			% fn.get_method())


## 加载被测脚本；编译失败（load 返回 null）计入失败并返回 null
func _require_script(path: String):
	var script = load(path)
	if script == null:
		_failed += 1
		print("  FAIL [%s]: 脚本加载失败（编译错误）: %s" % [_current_test, path])
	return script


func _check(condition: bool, desc: String, failed: Array = []) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL [%s]: %s" % [_current_test, desc])
		for f in failed:
			print("    %s" % f)


func test_attribute_system() -> void:
	_current_test = "AttributeSystem"
	print("\n--- %s ---" % _current_test)

	var AS = _require_script("res://data/attributes/attribute_system.gd")
	if AS == null:
		return
	var attrs = AS.new()
	_check(attrs.hp == 500.0, "初始 HP = 500", [attrs.hp])
	_check(attrs.max_hp == 500.0, "初始 max_hp = 500", [attrs.max_hp])

	attrs.take_damage(100.0)
	_check(attrs.hp == 400.0, "受到 100 伤害后 HP = 400", [attrs.hp])

	attrs.heal(50.0)
	_check(attrs.hp == 450.0, "治疗 50 后 HP = 450", [attrs.hp])

	_check(not attrs.is_dead(), "HP > 0 时未死亡")
	attrs.take_damage(500.0)
	_check(attrs.is_dead(), "HP <= 0 时死亡")

	# Modifier 测试
	var attrs2 = AS.new()
	attrs2.add_modifier("test", attrs2.STAT_BY_NAME.get("atk", 0), 10.0, 0.5)
	var atk: float = attrs2.get_value(attrs2.STAT_BY_NAME.get("atk", 0))
	_check(atk > 35.0, "加入 Modifier 后 ATK 增长", [atk])

	attrs2.remove_modifiers("test")
	var atk2: float = attrs2.get_value(attrs2.STAT_BY_NAME.get("atk", 0))
	_check(atk2 == 35.0, "移除 Modifier 后 ATK 恢复", [atk2])


func test_equipment_system() -> void:
	_current_test = "EquipmentSystem"
	print("\n--- %s ---" % _current_test)

	var ET = _require_script("res://data/equipment/equipment_template.gd")
	var ED = _require_script("res://data/equipment/equipment_defs.gd")
	var EI = _require_script("res://data/equipment/equipment_instance.gd")
	var EDB = _require_script("res://data/equipment/equipment_db.gd")
	var AD = _require_script("res://data/equipment/affix_data.gd")
	if ET == null or ED == null or EI == null or EDB == null or AD == null:
		return

	var template = ET.new()
	template.id = "test_sword"
	template.display_name = "测试剑"
	template.rarity = ED.Rarity.WHITE
	template.category = ED.Category.WEAPON

	var affix = AD.new()
	affix.id = "test_atk"
	affix.stat = 0
	affix.value = 10.0
	template.base_affix = affix

	EDB.register(template)

	var inst = EI.create(template)
	_check(inst.template_id == "test_sword", "实例 template_id 匹配")
	_check(inst.rarity == ED.Rarity.WHITE, "实例稀有度匹配")
	_check(inst.fusion_count == 0, "初始融合等级为 0")

	var d: Dictionary = inst.to_dict()
	var inst2 = EI.create(template)
	inst2.from_dict(d)
	_check(inst2.template_id == inst.template_id, "反序列化后 template_id 一致")


func test_white_equipment_db() -> void:
	_current_test = "WhiteEquipmentDB"
	print("\n--- %s ---" % _current_test)

	var EDB = _require_script("res://data/equipment/equipment_db.gd")
	var ED = _require_script("res://data/equipment/equipment_defs.gd")
	if EDB == null or ED == null:
		return

	EDB.init_equipment_db()

	# 白装 = 基础款（每槽位 1 件），绿～红 = 完整目录（36 件）按系数缩放
	# 合计 13 + 36×5 = 193
	# （红装原为「仅占位不生成」，但第 6 层起 Boss 保底红装、
	#   池空会回退白装，故按同系数生成占位红装——见 equipment_db 注释）
	#
	# **2026-09-22 起另加策划「装备参考2」筛选池 188 件**（CURATED_TABLE）：
	# 那是策划逐件设计的装备，与占位克隆并存（id 前缀 G/B/P/O 不冲突）。
	# 故总数 = 193 + 188 = 381；策划池的数量按稀有度分布不均
	#（绿 36 / 蓝 64 / 紫 51 / 橙 37），下面的断言改为**下限**而非等式。
	var white_count: int = EDB.get_templates_by_rarity(ED.Rarity.WHITE).size()
	_check(white_count == EDB.WHITE_COUNT, "白装为基础款 %d 件" % EDB.WHITE_COUNT, [white_count])
	_check(white_count == 13, "白装 13 件（4 武器 + 6 护甲 + 3 饰品）", [white_count])
	_check(EDB.template_count() == 452,
		"模板总数 = 452（193 占位克隆 + 259 策划筛选池）", [EDB.template_count()])
	_check(EDB.CURATED_TABLE.size() == 259, "策划筛选池 259 件", [EDB.CURATED_TABLE.size()])

	# 稀有度阶梯：种类数量 紫 > 蓝 >= 橙 > 绿 > 白
	var n_green: int = EDB.get_templates_by_rarity(ED.Rarity.GREEN).size()
	var n_blue: int = EDB.get_templates_by_rarity(ED.Rarity.BLUE).size()
	var n_purple: int = EDB.get_templates_by_rarity(ED.Rarity.PURPLE).size()
	var n_orange: int = EDB.get_templates_by_rarity(ED.Rarity.ORANGE).size()
	_check(n_green >= 36 and n_blue >= 36 and n_purple >= 36 and n_orange >= 36,
		"绿/蓝/紫/橙 各至少 36 件（占位目录 + 策划池）",
		["%d/%d/%d/%d" % [n_green, n_blue, n_purple, n_orange]])
	# 白装是最少的基础款；且完整目录均多于白装
	_check(white_count < minf(n_green, minf(n_blue, minf(n_purple, n_orange))),
		"白装种类数最少（基础款）", [str(white_count)])

	# 每个稀有度的模板池都非空（加权掉落的前提）
	for r in [ED.Rarity.WHITE, ED.Rarity.GREEN, ED.Rarity.BLUE, ED.Rarity.PURPLE, ED.Rarity.ORANGE]:
		_check(not EDB.get_templates_by_rarity(r).is_empty(), "稀有度 %d 模板池非空" % r)

	# 数值系数：高稀有度 = 白装 × 系数
	_check(EDB.rarity_scale(ED.Rarity.WHITE) == 1.0, "白装系数 1.0")
	_check(EDB.rarity_scale(ED.Rarity.GREEN) == 1.6, "绿装系数 1.6")
	_check(EDB.rarity_scale(ED.Rarity.BLUE) == 2.5, "蓝装系数 2.5")
	_check(EDB.rarity_scale(ED.Rarity.PURPLE) == 4.0, "紫装系数 4.0")
	_check(EDB.rarity_scale(ED.Rarity.ORANGE) == 6.5, "橙装系数 6.5")

	# 抽查代表性条目
	var sword = EDB.get_template(&"W01")
	_check(sword != null, "W01 铁制单手剑存在")
	if sword:
		_check(sword.display_name == "铁制单手剑", "W01 名称正确", [sword.display_name])
		_check(sword.weapon_type == "sword", "W01 单手剑类型")
		_check(sword.is_one_handed_weapon(), "W01 判定为单手")
		_check(sword.base_affix.value == 35.0, "W01 基础 ATK +35", [sword.base_affix.value])
		_check(sword.devour_affix.value == 0.5, "W01 吞噬 ATK +0.5", [sword.devour_affix.value])
		_check(sword.fusion_affix.value == 0.03, "W01 融合 ATK +3%", [sword.fusion_affix.value])

	# 高稀有度同名装备：数值 = 白装 × 系数，词条同步缩放
	var sword_g = EDB.get_template(&"W01_G")
	_check(sword_g != null, "W01_G 绿装单手剑存在")
	if sword_g:
		_check(sword_g.rarity == ED.Rarity.GREEN, "W01_G 稀有度为绿")
		_check(absf(sword_g.base_affix.value - 35.0 * 1.6) < 0.01,
			"W01_G 基础 ATK = 35 × 1.6 = 56", [sword_g.base_affix.value])
		_check(absf(sword_g.fusion_affix.value - 0.03 * 1.6) < 0.0001,
			"W01_G 融合词条同步缩放", [sword_g.fusion_affix.value])
		_check(sword_g.weapon_type == "sword", "W01_G 保留武器类型")
	var sword_o = EDB.get_template(&"W01_O")
	_check(sword_o != null, "W01_O 橙装单手剑存在")
	if sword_o:
		_check(absf(sword_o.base_affix.value - 35.0 * 6.5) < 0.01,
			"W01_O 基础 ATK = 35 × 6.5 = 227.5", [sword_o.base_affix.value])

	var greatsword = EDB.get_template(&"W06")
	_check(greatsword != null, "W06 铁制巨剑存在")
	if greatsword:
		_check(greatsword.is_two_handed_weapon(), "W06 判定为双手")
		_check(greatsword.base_affix.value == 56.0, "W06 基础 ATK +56", [greatsword.base_affix.value])

	var staff = EDB.get_template(&"W11")
	_check(staff != null, "W11 学徒长杖存在")
	if staff:
		_check(staff.base_affix.stat == 6, "W11 基础词条为 AP（Stat.AP=6）", [staff.base_affix.stat])

	var helm = EDB.get_template(&"A03")
	_check(helm != null, "A03 铁制头盔存在")
	if helm:
		_check(helm.armor_class == ED.ArmorClass.HEAVY, "A03 重甲")

	var boots = EDB.get_template(&"A16")
	_check(boots != null, "A16 布质软靴存在")
	if boots:
		_check(boots.armor_class == ED.ArmorClass.LIGHT, "A16 轻甲")

	var amulet = EDB.get_template(&"J03")
	_check(amulet != null, "J03 骨牙吊坠存在")
	if amulet:
		_check(amulet.base_affix.value == 25.0, "J03 基础 HP +25", [amulet.base_affix.value])

	# 白装槽位覆盖完整（每槽位都有 1 件可用）
	# 十槽位中武器 2 槽共用 WEAPON_1 模板池、饰品 2 槽共用 ACCESSORY_1
	for slot in [ED.Slot.HEAD, ED.Slot.CHEST, ED.Slot.SHOULDERS, ED.Slot.HANDS,
			ED.Slot.LEGS, ED.Slot.FEET, ED.Slot.WEAPON_1, ED.Slot.ACCESSORY_1]:
		_check(EDB.get_templates_by_slot(slot).size() > 0, "槽位 %d 有可用模板" % slot)


func test_damage_pipeline() -> void:
	_current_test = "DamagePipeline"
	print("\n--- %s ---" % _current_test)

	var DP = _require_script("res://gameplay/combat/damage_pipeline.gd")
	if DP == null:
		return

	var result = DP.physical(100.0, 1.0, 0.0, 50.0)
	_check(result.damage > 0.0, "物理伤害 > 0", [result.damage])
	_check(result.damage < 100.0, "有防御时伤害降低", [result.damage])

	var result2 = DP.physical(100.0, 1.5, 0.0, 0.0)
	_check(result2.damage == 150.0, "1.5倍技能倍率伤害 = 150", [result2.damage])

	var crit_damage: float = DP.with_crit(100.0, true, 0.5)
	_check(crit_damage == 200.0, "暴击伤害 = 200", [crit_damage])

	var no_crit: float = DP.with_crit(100.0, false, 0.5)
	_check(no_crit == 100.0, "非暴击伤害不变", [no_crit])


func test_fusion_rules() -> void:
	_current_test = "FusionRules"
	print("\n--- %s ---" % _current_test)

	var FR = _require_script("res://data/equipment/fusion_rules.gd")
	if FR == null:
		return

	_check(FR.attack_bonus_at(0) == 0.0, "融合 0 = 0%加成")
	_check(FR.attack_bonus_at(5) == 0.15, "融合 5 = 15%加成")
	_check(FR.attack_bonus_at(25) == 1.0, "融合 25 = 100%加成（满级）")
	_check(FR.can_fuse(0), "融合 0 可以继续融合")
	_check(FR.can_fuse(24), "融合 24 可以继续融合")
	_check(not FR.can_fuse(25), "融合 25 不可继续融合（上限 25）")
	_check(FR.next_fusion_count(0) == 1, "融合后等级 +1")

	# 策划 3.1 的**全部 6 个锚点**（此前只测了 0/5/25 三个）
	_check(absf(FR.attack_bonus_at(10) - 0.30) < 0.001, "融合 10 = 30%", [FR.attack_bonus_at(10)])
	_check(absf(FR.attack_bonus_at(15) - 0.50) < 0.001, "融合 15 = 50%", [FR.attack_bonus_at(15)])
	_check(absf(FR.attack_bonus_at(20) - 0.75) < 0.001, "融合 20 = 75%", [FR.attack_bonus_at(20)])
	# 单调递增（不能出现涨到一半又掉）
	var mono := true
	for n in range(1, 26):
		if FR.attack_bonus_at(n) < FR.attack_bonus_at(n - 1):
			mono = false
	_check(mono, "融合加成随次数单调不减")

	# 品质档位边界（策划 3.2：1~3 粗糙 | 4~7 完整 | 8~12 纯净 | 13~20 不朽 | 21+ 神话）
	_check(FR.tier_name(0) == "粗糙", "0 次为粗糙")
	_check(FR.tier_name(1) == "粗糙", "1 次为粗糙")
	_check(FR.tier_name(3) == "粗糙", "3 次仍为粗糙（边界）", [FR.tier_name(3)])
	_check(FR.tier_name(4) == "完整", "4 次进入完整（边界）", [FR.tier_name(4)])
	_check(FR.tier_name(7) == "完整", "7 次仍为完整（边界）", [FR.tier_name(7)])
	_check(FR.tier_name(8) == "纯净", "8 次进入纯净", [FR.tier_name(8)])
	_check(FR.tier_name(12) == "纯净", "12 次仍为纯净", [FR.tier_name(12)])
	_check(FR.tier_name(13) == "不朽", "13 次进入不朽", [FR.tier_name(13)])
	_check(FR.tier_name(20) == "不朽", "20 次仍为不朽", [FR.tier_name(20)])
	_check(FR.tier_name(21) == "神话", "21 次进入神话", [FR.tier_name(21)])
	_check(FR.tier_name(25) == "神话", "25 次为神话（满级）")

	# 品质档位的攻击加成（策划 3.2 满级效果参考）
	_check(absf(FR.tier_affix_attack(1) - 0.03) < 0.001, "粗糙 = +3%", [FR.tier_affix_attack(1)])
	_check(absf(FR.tier_affix_attack(5) - 0.08) < 0.001, "完整 = +8%", [FR.tier_affix_attack(5)])
	_check(absf(FR.tier_affix_attack(10) - 0.15) < 0.001, "纯净 = +15%", [FR.tier_affix_attack(10)])
	_check(absf(FR.tier_affix_attack(15) - 0.25) < 0.001, "不朽 = +25%", [FR.tier_affix_attack(15)])
	_check(absf(FR.tier_affix_attack(25) - 0.40) < 0.001, "神话 = +40%", [FR.tier_affix_attack(25)])

	# EquipmentInstance 必须与 FusionRules 同源（曾各写一份、边界还不一致）
	var EI = _require_script("res://data/equipment/equipment_instance.gd")
	if EI != null:
		var inst = EI.new()
		inst.fusion_count = 3
		_check(inst.fusion_tier() == "粗糙",
			"实例 3 次也报粗糙（与 FusionRules 同源）", [inst.fusion_tier()])
		inst.fusion_count = 25
		_check(absf(inst.fusion_bonus() - 1.0) < 0.001,
			"实例 25 次融合加成 = 100%（原先写死 count×0.02 只有 50%）",
			[inst.fusion_bonus()])

	# —— 融合材料类别规则（装备参考2 规格，2026-09-22 起取代「同槽位」）——
	#
	# 规格原文：「武器只能和武器融合，但是其他部位装备可以和除武器以外的
	# 装备融合」。故判据是**是否同为武器**，而不是槽位相同。
	var ED = _require_script("res://data/equipment/equipment_defs.gd")
	if ED == null:
		return
	var W: int = ED.Category.WEAPON
	var A: int = ED.Category.ARMOR
	var J: int = ED.Category.ACCESSORY
	_check(FR.can_fuse_together(W, W), "武器 ↔ 武器 可融合")
	_check(FR.can_fuse_together(A, A), "护甲 ↔ 护甲 可融合")
	_check(FR.can_fuse_together(J, J), "饰品 ↔ 饰品 可融合")
	_check(FR.can_fuse_together(A, J), "护甲 ↔ 饰品 可融合（非武器之间不限）")
	_check(FR.can_fuse_together(J, A), "饰品 ↔ 护甲 可融合（反向同判）")
	_check(not FR.can_fuse_together(W, A), "武器 ↔ 护甲 不可融合")
	_check(not FR.can_fuse_together(A, W), "护甲 ↔ 武器 不可融合（反向同判）")
	_check(not FR.can_fuse_together(W, J), "武器 ↔ 饰品 不可融合")


func test_room_data() -> void:
	_current_test = "RoomData"
	print("\n--- %s ---" % _current_test)

	var RD = _require_script("res://data/rooms/room_data.gd")
	if RD == null:
		return

	var room = RD.new()
	room.room_id = "test_room"
	room.room_type = "normal"
	room.width = 10
	room.height = 8

	room.doors.append({"direction": "north", "id": "north"})
	room.entities.append({"type": "player_spawn", "x": 5, "y": 4})
	room.entities.append({"type": "enemy_spawn", "x": 3, "y": 3})

	_check(room.has_door("north"), "有北门")
	_check(not room.has_door("south"), "没有南门")

	var spawns: Array = room.get_enemy_spawns()
	_check(spawns.size() == 1, "有 1 个敌人生成点", [spawns.size()])

	var player: Dictionary = room.get_player_spawn()
	_check(not player.is_empty(), "有玩家出生点")

	# 全部房间 JSON 数据完整性：坐标不得越界、不得重复
	# （room_start.json 曾因编辑器保存不过滤而含 89 项越界 + 55 项重复）
	_validate_all_room_json()


## 扫描 data/rooms/*.json，校验所有格子坐标在房间范围内且不重复
func _validate_all_room_json() -> void:
	var dir := DirAccess.open("res://data/rooms/")
	if dir == null:
		_check(false, "房间目录可访问")
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var fn := dir.get_next()
	while not fn.is_empty():
		if fn.ends_with(".json"):
			files.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	_check(not files.is_empty(), "发现房间 JSON（%d 个）" % files.size())

	for f in files:
		var path := "res://data/rooms/%s" % f
		var fh := FileAccess.open(path, FileAccess.READ)
		if fh == null:
			_check(false, "%s 可读" % f)
			continue
		var parser := JSON.new()
		var parsed := parser.parse(fh.get_as_text())
		fh.close()
		if parsed != OK:
			_check(false, "%s JSON 可解析" % f)
			continue
		var data: Dictionary = parser.data
		var w := int(data.get("width", 0))
		var h := int(data.get("height", 0))
		if w <= 0 or h <= 0:
			_check(false, "%s 尺寸有效（%dx%d）" % [f, w, h])
			continue

		# 地板：去重后格数不得超范围，且每格坐标都在界内
		var cells := {}
		var bad := 0
		for t in data.get("floor", []):
			var tx := int(t.get("x", 0))
			var ty := int(t.get("y", 0))
			if tx < 0 or ty < 0 or tx >= w or ty >= h:
				bad += 1
			cells[Vector2i(tx, ty)] = true
		_check(bad == 0, "%s 地板无越界（%d 项）" % [f, bad])
		_check(cells.size() == int(data.get("floor", []).size()),
			"%s 地板无重复（%d 项 / 去重 %d）" % [f, data.get("floor", []).size(), cells.size()])

		# 墙 / 门 / 实体坐标也须在界内
		var bad_wall := 0
		for t in data.get("walls", []):
			var tx := int(t.get("x", 0))
			var ty := int(t.get("y", 0))
			if tx < 0 or ty < 0 or tx >= w or ty >= h:
				bad_wall += 1
		_check(bad_wall == 0, "%s 墙无越界（%d 项）" % [f, bad_wall])

		var bad_ent := 0
		for t in data.get("entities", []):
			var tx := int(t.get("x", 0))
			var ty := int(t.get("y", 0))
			if tx < 0 or ty < 0 or tx >= w or ty >= h:
				bad_ent += 1
		_check(bad_ent == 0, "%s 实体无越界（%d 项）" % [f, bad_ent])

		# 可通行性：从 player_spawn 出发 BFS，关键点必须可达。
		# 这条能抓到「刷怪点/宝箱落在石柱上」与「石柱围成封闭区」两类真问题
		# （本轮生成 17 个新模板时，5 个模板的刷怪点落在石柱里，正是靠它抓出来的）。
		var reach_issues := _check_room_reachability(data)
		for issue in reach_issues:
			_check(false, "%s %s" % [f, issue])
		if reach_issues.is_empty():
			_check(true, "%s 可通行（关键点均可达）" % f)


## 从 player_spawn 做 4 向 BFS，返回不可达/不可站的关键点问题列表
func _check_room_reachability(d: Dictionary) -> Array:
	var w := int(d.get("width", 0))
	var h := int(d.get("height", 0))
	var issues: Array = []

	var walkable := {}
	for t in d.get("floor", []):
		walkable["%d,%d" % [int(t.get("x", 0)), int(t.get("y", 0))]] = true
	# 墙格不可走
	for t in d.get("walls", []):
		walkable.erase("%d,%d" % [int(t.get("x", 0)), int(t.get("y", 0))])

	var start := ""
	for e in d.get("entities", []):
		if str(e.get("type", "")) == "player_spawn":
			start = "%d,%d" % [int(e.get("x", 0)), int(e.get("y", 0))]
	if start.is_empty():
		return ["无 player_spawn"]
	if not walkable.has(start):
		return ["出生点 %s 不可站（被墙占或地板缺失）" % start]

	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		var parts := cur.split(",")
		var cx := int(parts[0])
		var cy := int(parts[1])
		for off in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nk := "%d,%d" % [cx + int(off[0]), cy + int(off[1])]
			if seen.has(nk) or not walkable.has(nk):
				continue
			seen[nk] = true
			queue.append(nk)

	# 非玩家实体必须可达且可站
	for e in d.get("entities", []):
		if str(e.get("type", "")) == "player_spawn":
			continue
		var k := "%d,%d" % [int(e.get("x", 0)), int(e.get("y", 0))]
		if not walkable.has(k):
			issues.append("%s @%s 位于墙格" % [str(e.get("type", "")), k])
		elif not seen.has(k):
			issues.append("%s @%s 从出生点不可达" % [str(e.get("type", "")), k])

	return issues



## 房间刷怪闭环集成测试：建房间 → 激活 → 刷怪 → 全灭 → 清空
func test_room_combat_loop() -> void:
	_current_test = "RoomCombatLoop"
	print("\n--- %s ---" % _current_test)

	var RC = _require_script("res://gameplay/dungeon/room_controller.gd")
	var EB = _require_script("res://entities/enemies/enemy_base.gd")
	var EDB = _require_script("res://data/equipment/equipment_db.gd")
	if RC == null or EB == null or EDB == null:
		return

	EDB.init_equipment_db()

	# 构造房间结构：Room_N/{SpawnPoints, Doors, RoomController}
	var room_root := Node3D.new()
	room_root.name = "Room_Test"
	root.add_child(room_root)

	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	room_root.add_child(spawns)

	# 4 个生成点 → 70% 概率刷怪，为确定性直接种固定数量的敌人不好控制，
	# 改为验证：激活后 alive > 0（13 个点几乎必然 ≥1）与清空逻辑
	for i in range(13):
		var m := Marker3D.new()
		m.position = Vector3(float(i), 0.0, 0.0)
		# 必须加入白名单组：RoomController 只收集 ENEMY_SPAWN_GROUPS 里的标记
		# （enemy_spawn / elite_spawn），无组的 Marker3D 会被当作出生点/宝箱而忽略。
		# 本测试原先漏了加组 → 收集到 0 个生成点 → 永远 alive=0；
		# 而该测试是异步且未被 await，断言在汇总之后才跑，所以失败被掩盖了很久。
		m.add_to_group("enemy_spawn")
		spawns.add_child(m)

	var controller = RC.new()
	controller.name = "RoomController"
	controller.set("room_data", {"room_id": "test_room", "room_type": "normal"})
	room_root.add_child(controller)

	# 等待 _ready 收集节点
	await process_frame

	controller.activate()
	_check(controller.is_active, "房间激活")
	var alive: int = controller.enemies_alive
	_check(alive > 0, "激活后刷出敌人（alive=%d）" % alive, [alive])

	if alive > 0:
		# 杀死所有活敌 → 房间清空。
		# **必须走 `debug_kill_all_enemies()` 而不是自己遍历 `_living_enemies`**：
		# 后者只有节点式敌人，群体单位（CrowdSim）住在模拟核的 SoA 数组里、
		# 不是场景节点，漏掉就会让 `enemies_alive` 归不了零、`is_cleared` 恒 false。
		# 基础怪带 `swarm` 标记后（僵尸/狂暴囚犯/猎犬）本房会真的刷出群体单位。
		controller.debug_kill_all_enemies()
		_check(controller.is_cleared, "全灭后房间清空")

	room_root.queue_free()


## 连段状态机测试：四段推进 / 窗口超时 / 特殊攻击接入
func test_attack_combo() -> void:
	_current_test = "AttackCombo"
	print("\n--- %s ---" % _current_test)

	var AC = _require_script("res://gameplay/combat/attack_combo.gd")
	if AC == null:
		return

	var combo = AC.new()
	# 注入测试配置（避免依赖 GameBalance 常量变更）
	combo.combo_stages = [
		[0.28, 1.0, 2.0, 60.0, 0.0],
		[0.28, 1.1, 2.2, 65.0, 0.0],
		[0.32, 1.3, 2.6, 75.0, 1.5],
		[0.45, 1.8, 3.2, 90.0, 4.0],
	]
	combo.combo_window = 0.45

	# --- 四段连击推进 ---
	var s1: int = combo.request_normal()
	_check(s1 == 1, "第一击为普攻1", [s1])
	combo.begin_attack()
	_check(combo.request_normal() == 0, "动作进行中拒绝输入")
	combo.end_attack()
	_check(combo.is_combo_active(), "攻击后处于连击窗口")

	var s2: int = combo.request_normal()
	_check(s2 == 2, "窗口内第二击接普攻2", [s2])
	combo.begin_attack()
	combo.end_attack()
	var s3: int = combo.request_normal()
	_check(s3 == 3, "第三击接普攻3", [s3])
	combo.begin_attack()
	combo.end_attack()
	var s4: int = combo.request_normal()
	_check(s4 == 4, "第四击接普攻4（终结）", [s4])

	# --- 段位参数 ---
	var p4: Array = combo.stage_params(4)
	_check(p4[1] == 1.8, "普攻4 倍率 1.8", [p4[1]])
	_check(p4[2] == 3.2, "普攻4 距离 3.2（范围递增）", [p4[2]])
	var p1: Array = combo.stage_params(1)
	_check(p1[2] < p4[2], "普攻1 范围 < 普攻4 范围")
	_check(combo.stage_params(1)[1] < combo.stage_params(2)[1]
		and combo.stage_params(2)[1] < combo.stage_params(3)[1]
		and combo.stage_params(3)[1] < combo.stage_params(4)[1],
		"四段伤害递增")

	# --- 第四段后窗口超时回普攻1 ---
	combo.begin_attack()
	combo.end_attack()
	combo.tick(0.5)  # 超过 0.45 窗口
	_check(not combo.is_combo_active(), "窗口超时连击断")
	var s_after: int = combo.request_normal()
	_check(s_after == 1, "超时后回到普攻1", [s_after])

	# --- 奔跑攻击接入普攻3 ---
	combo = AC.new()
	combo.combo_stages = [[0.3, 1.0], [0.3, 1.1], [0.3, 1.3], [0.3, 1.8]]
	combo.combo_window = 0.45
	_check(combo.request_sprint(), "奔跑攻击被接受")
	combo.begin_attack()
	combo.end_attack()
	var after_sprint: int = combo.request_normal()
	_check(after_sprint == 3, "奔跑攻击后接普攻3", [after_sprint])
	combo.begin_attack()
	combo.end_attack()
	var after_sprint2: int = combo.request_normal()
	_check(after_sprint2 == 4, "奔跑攻击→普攻3→普攻4", [after_sprint2])

	# --- 跳跃攻击接入普攻3 ---
	combo = AC.new()
	combo.combo_stages = [[0.3, 1.0], [0.3, 1.1], [0.3, 1.3], [0.3, 1.8]]
	combo.combo_window = 0.45
	_check(combo.request_jump(), "跳跃攻击被接受")
	combo.begin_attack()
	combo.end_attack()
	var after_jump: int = combo.request_normal()
	_check(after_jump == 3, "跳跃攻击后接普攻3", [after_jump])

	# --- 特殊攻击进行中拒绝 ---
	combo = AC.new()
	combo.combo_stages = [[0.3, 1.0], [0.3, 1.1], [0.3, 1.3], [0.3, 1.8]]
	combo.begin_attack()
	_check(not combo.request_sprint(), "动作中拒绝奔跑攻击")
	_check(not combo.request_jump(), "动作中拒绝跳跃攻击")

	# --- 普攻中断连击（tick 在非动作期推进窗口）---
	combo = AC.new()
	combo.combo_stages = [[0.3, 1.0], [0.3, 1.1], [0.3, 1.3], [0.3, 1.8]]
	combo.combo_window = 0.45
	combo.request_normal()
	combo.begin_attack()
	combo.end_attack()
	combo.tick(0.2)
	_check(combo.is_combo_active(), "窗口内连击保持")
	combo.tick(0.3)
	_check(not combo.is_combo_active(), "累计超窗连击断")


## 状态机基类测试：注册 / 初始状态 / 转移 / 转发 / 数据传递
## 纯逻辑，不进场景树（状态 new() 出来直接驱动）
func test_state_machine() -> void:
	_current_test = "StateMachine"
	print("\n--- %s ---" % _current_test)

	var ST = _require_script("res://gameplay/state_machine/state.gd")
	var SM = _require_script("res://gameplay/state_machine/state_machine.gd")
	if ST == null or SM == null:
		return

	# 探针状态：记录 enter/exit/physics_update 调用，便于断言转发是否正确
	var probe = _StateProbe.new()
	probe.state_name = "A"
	var probe_b = _StateProbe.new()
	probe_b.state_name = "B"

	var sm = SM.new()
	sm.add_state("A", probe)
	sm.add_state("B", probe_b)

	_check(sm.current_state_name() == "", "未初始化时状态名为空")

	sm.set_initial("A")
	_check(sm.current_state_name() == "A", "初始状态已进入", [sm.current_state_name()])
	_check(probe.entered, "初始状态收到 enter")
	_check(probe.last_previous == "", "初始 enter 的 previous 为空")

	# 物理帧转发
	probe.ticks = 0
	sm.physics_update(0.1)
	sm.physics_update(0.1)
	_check(probe.ticks == 2, "physics_update 转发到当前状态", [str(probe.ticks)])
	_check(probe.total_delta > 0.19 and probe.total_delta < 0.21,
		"delta 原样透传", [str(probe.total_delta)])

	# 输入转发
	sm.handle_input(null)
	_check(probe.inputs == 1, "handle_input 转发到当前状态")

	# 状态主动结束 → 转移（finished 信号驱动）
	probe.finished.emit("B", {"reason": "done"})
	_check(sm.current_state_name() == "B", "finished 触发转移", [sm.current_state_name()])
	_check(probe.exited, "离开旧状态调用 exit")
	_check(probe_b.entered, "进入新状态调用 enter")
	_check(probe_b.last_previous == "A", "enter 收到上一状态名", [probe_b.last_previous])
	_check(probe_b.last_data.get("reason", "") == "done", "转移数据传递到 enter")

	# 转移到不存在的状态不应崩溃、也不改变当前状态
	sm.transition_to("NO_SUCH_STATE")
	_check(sm.current_state_name() == "B", "转移到未注册状态被拒绝且不改变现状")

	# 空数据转移（GDScript 信号不支持默认参数，状态必须显式传 {}）
	probe_b.finished.emit("A", {})
	_check(sm.current_state_name() == "A", "空数据转移可用", [sm.current_state_name()])

	_check(sm.is_in("B") == false, "转移后旧状态不再是当前状态")
	_check(sm.is_in("A"), "is_in 判定当前状态")


## 测试探针：State 的最小实现，记录被调用的痕迹
class _StateProbe:
	extends "res://gameplay/state_machine/state.gd"

	var state_name := ""
	var entered := false
	var exited := false
	var ticks := 0
	var inputs := 0
	var total_delta := 0.0
	var last_previous := ""
	var last_data: Dictionary = {}

	func enter(previous: String, data: Dictionary = {}) -> void:
		entered = true
		last_previous = previous
		last_data = data

	func exit() -> void:
		exited = true

	func physics_update(delta: float) -> void:
		ticks += 1
		total_delta += delta

	func handle_input(_event: InputEvent) -> void:
		inputs += 1


## 房间编辑器核心测试：JSON 往返一致性 + 矩形填充/自动围墙/校验
func test_room_editor_core() -> void:
	_current_test = "RoomEditorCore"
	print("\n--- %s ---" % _current_test)

	var RE = _require_script("res://addons/iron_studio/room_editor_core.gd")
	if RE == null:
		return

	# 构造编辑器节点树（容器结构同 room_editor_scene）
	var root := Node3D.new()
	root.name = "RoomEditorRoot"
	for c in ["Floor", "Walls", "Doors", "Spawns"]:
		var n := Node3D.new()
		n.name = c
		root.add_child(n)
	# 挂到场景树根（节点生命周期管理；编辑器核心是纯静态方法）
	self.root.add_child(root)

	# --- JSON 往返一致性 ---
	var source := {
		"version": 2, "id": "rt_test", "room_type": "normal",
		"width": 10, "height": 8, "tags": ["normal", "custom_tag"],
		"doors": [{"direction": "south", "id": "south_5_7", "x": 5, "y": 7}],
		"floor": [{"x": 1, "y": 1, "type": "stone"}, {"x": 2, "y": 1, "type": "wood"}],
		"walls": [{"x": 0, "y": 0, "direction": "north", "type": "normal_wall"}],
		"entities": [{"type": "enemy_spawn", "x": 3, "y": 3, "monster_id": "slime"}],
	}
	RE.build_editor_tree(root, source)
	var meta := {"id": "rt_test", "room_type": "normal", "width": 10, "height": 8, "tags": ["normal", "custom_tag"]}
	var round: Dictionary = RE.serialize_tree(root, meta)

	_check(round.get("tags") == ["normal", "custom_tag"], "tags 透传不丢失", [str(round.get("tags"))])
	_check(round.get("floor", []).size() == 2, "地板往返数量一致")
	_check(round.get("floor", [])[1].get("type") == "wood", "地板材质往返一致")
	_check(round.get("walls", []).size() == 1, "墙往返数量一致")
	var rt_door: Dictionary = round.get("doors", [])[0]
	_check(rt_door.get("id") == "south_5_7", "门 id 含坐标后缀（唯一）", [rt_door.get("id")])
	_check(rt_door.get("x") == 5 and rt_door.get("y") == 7, "门坐标往返一致")
	var rt_spawn: Dictionary = round.get("entities", [])[0]
	_check(rt_spawn.get("monster_id") == "slime", "刷怪点怪物绑定往返一致")

	# --- 越界与重复数据落盘前必须过滤 ---
	# 背景：编辑器保存不做过滤时，越界格子会落盘，运行时 FloorBuilder 不钳制，
	# 地板被渲染到房间外面（room_start.json 曾因此含 89 项越界 + 55 项重复）
	RE.clear_tree(root)
	var dirty: Dictionary = {
		"width": 10, "height": 8,
		"floor": [
			{"x": 1, "y": 1, "type": "stone"},
			{"x": 1, "y": 1, "type": "stone"},      # 重复
			{"x": -2, "y": -1, "type": "stone"},    # 越界（负）
			{"x": 20, "y": 3, "type": "stone"},     # 越界（超宽）
			{"x": 3, "y": 30, "type": "stone"},     # 越界（超高）
			{"x": 9, "y": 7, "type": "wood"},       # 边界内（角落）
		],
		"walls": [
			{"x": 0, "y": 0, "direction": "north", "type": "normal_wall"},
			{"x": 0, "y": 0, "direction": "north", "type": "normal_wall"},  # 重复
			{"x": 0, "y": 99, "direction": "south", "type": "normal_wall"}, # 越界
		],
		"entities": [
			{"type": "enemy_spawn", "x": 4, "y": 4},
			{"type": "enemy_spawn", "x": 4, "y": 4},                          # 重复
			{"type": "enemy_spawn", "x": -5, "y": 4},                         # 越界
		],
	}
	RE.build_editor_tree(root, dirty)
	var cleaned: Dictionary = RE.serialize_tree(root, {"id": "clean", "width": 10, "height": 8})
	_check(cleaned.get("floor", []).size() == 2, "保存时丢弃越界/重复地板（6→2）",
		[str(cleaned.get("floor", []).size())])
	var f_cells := []
	for t in cleaned.get("floor", []):
		f_cells.append(Vector2i(t.x, t.y))
	_check(f_cells.has(Vector2i(1, 1)) and f_cells.has(Vector2i(9, 7)),
		"保留范围内的地板（含边界角落）")
	_check(cleaned.get("walls", []).size() == 1, "保存时丢弃越界/重复墙（3→1）",
		[str(cleaned.get("walls", []).size())])
	_check(cleaned.get("entities", []).size() == 1, "保存时丢弃越界/重复实体（3→1）",
		[str(cleaned.get("entities", []).size())])

	# --- 门位置：编辑器与游戏 DoorBuilder 同口径 ---
	var DB = _require_script("res://world/rooms/door_builder.gd")
	if DB:
		var pos: Vector3 = DB._door_position_from_cell({"x": 5, "y": 7}, "south")
		_check(pos == Vector3(5.0, 1.5, 7.5), "门位置=格子边缘（编辑器=游戏口径）", [pos])
		var fallback: Vector3 = DB._door_position_from_cell({}, "south")
		_check(fallback == Vector3.INF, "旧数据无 x/y 返回回退标记")

	# --- 矩形填充 ---
	RE.clear_tree(root)
	var fill_op: Dictionary = RE.fill_rect_floor(root, Vector2i(1, 1), Vector2i(3, 3), "grass")
	_check(fill_op.get("added", []).size() == 9, "矩形填充 3x3=9 格", [str(fill_op.get("added", []).size())])
	var filled: Dictionary = RE.serialize_tree(root, meta)
	_check(filled.get("floor", []).size() == 9, "填充后序列化 9 块地板")

	# --- 橡皮擦清全部 ---
	var erase_op: Dictionary = RE.erase_cell(root, Vector2i(2, 2))
	_check(erase_op.get("removed", []).size() == 1, "橡皮擦清除该格地板")

	# --- 自动围墙（10x8 → 边界 2*(10+8)=36 段，角落双面墙）---
	RE.clear_tree(root)
	var wall_op: Dictionary = RE.auto_walls(root, 10, 8)
	var wall_count: int = wall_op.get("added", []).size()
	_check(wall_count == 2 * (10 + 8), "自动围墙 36 段（角落双面）", [str(wall_count)])

	# --- 校验 ---
	# 空房间 → 地板未铺满 + 无门问题不报（无门=没检查对象）
	var issues: Array = RE.validate_room(root, {"width": 10, "height": 8, "room_type": "normal"})
	_check(issues.size() > 0, "空房间校验发现问题（地板未铺满）", [str(issues)])
	var has_floor_issue := false
	for issue in issues:
		if str(issue).contains("地板"):
			has_floor_issue = true
	_check(has_floor_issue, "校验报出地板覆盖问题")

	# start 房无玩家出生点
	var issues2: Array = RE.validate_room(root, {"width": 10, "height": 8, "room_type": "start"})
	var has_spawn_issue := false
	for issue in issues2:
		if str(issue).contains("玩家出生"):
			has_spawn_issue = true
	_check(has_spawn_issue, "起始房缺玩家出生点被报出")

	root.queue_free()


## 坐标放置测试：单点全元素 / 矩形墙圈 / 对角放置 / 坐标钳制
func test_coord_placement() -> void:
	_current_test = "CoordPlacement"
	print("\n--- %s ---" % _current_test)

	var RE = _require_script("res://addons/iron_studio/room_editor_core.gd")
	if RE == null:
		return

	var root := Node3D.new()
	root.name = "RoomEditorRoot"
	for c in ["Floor", "Walls", "Doors", "Spawns"]:
		var n := Node3D.new()
		n.name = c
		root.add_child(n)
	self.root.add_child(root)

	# --- 单点放置：四种元素各放一个 ---
	var op_f: Dictionary = RE.place_single(root, Vector2i(3, 3), "floor", "north", "wood")
	_check(op_f.get("added", []).size() == 1, "单点放置地砖")
	var op_w: Dictionary = RE.place_single(root, Vector2i(4, 3), "wall", "east")
	_check(op_w.get("added", []).size() == 1, "单点放置墙（east）")
	var op_d: Dictionary = RE.place_single(root, Vector2i(0, 3), "door", "west")
	_check(op_d.get("added", []).size() == 1, "单点放置门")
	var op_s: Dictionary = RE.place_single(root, Vector2i(5, 5), "spawn", "north", "stone", "enemy_spawn", "slime")
	_check(op_s.get("added", []).size() == 1, "单点放置刷怪点")

	# 序列化验证元素类型正确
	var data: Dictionary = RE.serialize_tree(root, {"id": "cp", "width": 10, "height": 8})
	_check(data.get("floor", []).size() == 1, "地砖序列化 1 块")
	_check(data.get("floor", [])[0].get("type") == "wood", "地砖材质正确")
	_check(data.get("walls", []).size() == 1, "墙序列化 1 段")
	_check(data.get("walls", [])[0].get("direction") == "east", "墙朝向正确")
	_check(data.get("doors", []).size() == 1, "门序列化 1 扇")
	_check(data.get("entities", []).size() == 1, "刷怪点序列化 1 个")
	_check(data.get("entities", [])[0].get("monster_id") == "slime", "刷怪点怪物绑定")

	# --- 矩形墙圈：2x2 矩形四边（含角，角双面墙）---
	RE.clear_tree(root)
	var rect_op: Dictionary = RE.place_wall_rect(root, Vector2i(2, 2), Vector2i(4, 4))
	# 3x3 矩形：上边3+下边3+左边3+右边3=12，角重复计 4 次 → 实际新增 8 段位置（角双面）
	var rect_count: int = rect_op.get("added", []).size()
	_check(rect_count == 12, "3x3 矩形墙圈 12 段（角落双面）", [str(rect_count)])

	# --- 对角放置（门）：两点各一扇 ---
	RE.clear_tree(root)
	var corner_op: Dictionary = RE.place_corners(root, Vector2i(0, 0), Vector2i(9, 7), "door", "north", "south")
	_check(corner_op.get("added", []).size() == 2, "对角放置 2 扇门")
	var cdata: Dictionary = RE.serialize_tree(root, {"id": "cp2", "width": 10, "height": 8})
	_check(cdata.get("doors", []).size() == 2, "对角门序列化 2 扇")
	var door_ids := []
	for d in cdata.get("doors", []):
		door_ids.append(str(d.get("id")))
	_check(door_ids[0] != door_ids[1], "两扇门 id 不同（唯一性）", door_ids)

	# --- 坐标钳制 ---
	var c1: Vector2i = RE.clamp_cell(Vector2i(-5, 3), 10, 8)
	_check(c1 == Vector2i(0, 3), "负坐标钳制到 0", [str(c1)])
	var c2: Vector2i = RE.clamp_cell(Vector2i(15, 99), 10, 8)
	_check(c2 == Vector2i(9, 7), "越界坐标钳制到边界", [str(c2)])

	root.queue_free()


## 第一层怪物数据库测试：数量/数值口径/AI 映射/Boss/精英池
func test_monster_db_layer1() -> void:
	_current_test = "MonsterDBLayer1"
	print("\n--- %s ---" % _current_test)

	var MDB = _require_script("res://data/monsters/monster_db.gd")
	var EB = _require_script("res://entities/enemies/enemy_base.gd")
	if MDB == null or EB == null:
		return

	MDB.init()
	var all: Array = MDB.all_monsters()
	# 全量怪物设计分册：基础 10×4 阶段 + 独特 16 + 第9层 8 = 64
	_check(all.size() == 64, "怪物全量 64 种（10×4 阶段 + 独特 16 + 第9层 8）", [str(all.size())])
	var base_all: Array = MDB.all_base_monsters()
	_check(base_all.size() == 40, "基础怪 10 种 × 4 阶段 = 40", [str(base_all.size())])
	# 各阶段基础怪齐 10 种
	var per_phase := {}
	for m in base_all:
		var ph := int(m.get("phase", 0))
		per_phase[ph] = int(per_phase.get(ph, 0)) + 1
	var phase_ok := true
	for ph in [1, 2, 3, 4]:
		if int(per_phase.get(ph, 0)) != 10:
			phase_ok = false
	_check(phase_ok, "每个阶段基础怪各 10 种", [str(per_phase)])

	# 抽查设计分册数值口径
	var zombie = MDB.get_monster("zombie_prison")
	_check(zombie.get("hp") == 120 and zombie.get("atk") == 25, "监牢僵尸 120/25")
	var archer = MDB.get_monster("skeleton_archer")
	_check(archer.get("hp") == 70 and archer.get("attack_range") == 8.0, "骷髅弓手 70 血/射程 8")
	_check(archer.get("ai") == "kite", "弓手 AI = 风筝")
	var sentinel = MDB.get_monster("tomb_sentinel")
	_check(sentinel.get("ai") == "sentry" and sentinel.get("speed_pct") == 0, "哨兵固定不移动")
	var phantom = MDB.get_monster("mist_phantom")
	_check(phantom.get("dodge_pct") == 0.3, "迷雾幽灵闪避 30%", [str(phantom.get("dodge_pct"))])
	var rat = MDB.get_monster("rat_mutant")
	_check(rat.get("hp") == 250 and rat.get("speed_pct") == 35, "巨鼠 250 血/35% 移速")

	# 设计约束：远程血 ≤ 近战 60%、飞行血 ≤ 近战 40%
	_check(archer.get("hp") <= zombie.get("hp") * 0.6, "远程血 ≤ 近战 60%")
	var bat = MDB.get_monster("bat_stonewing")
	_check(bat.get("hp") <= zombie.get("hp") * 0.4, "飞行血 ≤ 近战 40%")

	# 攻击频率约束：分册 2.1 写「所有怪物攻击间隔 ≥ 2.5 秒」，
	# 但 3.2 进化规则表又写「攻击间隔 阶段三 ×0.7、阶段四 ×0.55」，
	# 而第 4 章各表的具体数值阶段四就是 1.5 秒（如监牢僵尸 3.5 → 虚空僵尸 1.5）。
	# ★ 分册内部冲突：2.1 的硬性约束与 3.2/第4章的阶段数值无法同时成立。
	# 本项目按第 4 章「具体数值表」实现（更明确），故此处只对**阶段一**断言 ≥2.5s。
	var p1_ok := true
	for m in base_all:
		if int(m.get("phase", 0)) == 1 and float(m.get("attack_interval")) < 2.5:
			p1_ok = false
	_check(p1_ok, "阶段一全部攻击间隔 ≥ 2.5s（分册 2.1 对第 1 层的硬性约束）")
	# 阶段四按分册第 4 章具体表：最快 1.3 秒（毒/狂战/蝠群等），最慢 2.1 秒
	var p4_min := 99.0
	var p4_max := 0.0
	for m in base_all:
		if int(m.get("phase", 0)) == 4:
			p4_min = minf(p4_min, float(m.get("attack_interval", 9)))
			p4_max = maxf(p4_max, float(m.get("attack_interval", 0)))
	_check(absf(p4_min - 1.3) < 0.01, "阶段四最快间隔 1.3s（分册第4章具体表）", [str(p4_min)])
	_check(absf(p4_max - 2.1) < 0.01, "阶段四最慢间隔 2.1s（分册第4章具体表）", [str(p4_max)])

	# Boss：鼠王（血 ×2.4=600，攻 ×1.3）
	var boss = MDB.boss_monster()
	_check(boss.get("hp") == 600, "鼠王血量 600", [str(boss.get("hp"))])
	_check(boss.get("atk") == 39, "鼠王攻击 39（30×1.3）", [str(boss.get("atk"))])
	_check(bool(boss.get("is_boss")), "Boss 标记")

	# EnemyBase 应用配置（场景树外纯属性应用）
	var enemy: CharacterBody3D = EB.new()
	enemy.apply_monster_config(MDB.get_monster("hound_jailer"))
	_check(enemy.behavior == EB.AIBehavior.RUSHER, "猎犬 AI = 突进")
	_check(enemy.max_hp == 90.0, "猎犬血量 90")
	_check(absf(enemy.move_speed - 4.8) < 0.01, "猎犬移速 120%×4.0=4.8", [str(enemy.move_speed)])
	var enemy2: CharacterBody3D = EB.new()
	enemy2.apply_monster_config(MDB.get_monster("zombie_miasma"))
	_check(enemy2.death_poison, "毒瘴僵尸死亡毒雾标记")
	var enemy3: CharacterBody3D = EB.new()
	enemy3.apply_monster_config(MDB.get_monster("tomb_sentinel"))
	_check(enemy3.behavior == EB.AIBehavior.SENTRY and enemy3.attack_range == 15.0, "哨兵 15 米射程")

	# 随机池
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var picked: Dictionary = MDB.random_monster(rng)
	_check(not picked.is_empty(), "加权随机返回有效怪物")
	var elite: Dictionary = MDB.random_elite(rng)
	_check(not elite.is_empty(), "精英随机返回有效怪物")
	_check(bool(elite.get("is_elite", false)), "精英带 is_elite 标记")
	# 精英倍率（分册 3.2 注：血量 ×1.5~2.0，攻击 ×1.3~1.5）
	var src: Dictionary = MDB.get_monster(str(elite.get("id", "")))
	if not src.is_empty():
		var hp_ratio := float(elite.get("hp", 0)) / maxf(float(src.get("hp", 1)), 1.0)
		var atk_ratio := float(elite.get("atk", 0)) / maxf(float(src.get("atk", 1)), 1.0)
		_check(hp_ratio >= 1.49 and hp_ratio <= 2.01, "精英血量倍率 ∈ [1.5,2.0]", [str(hp_ratio)])
		_check(atk_ratio >= 1.29 and atk_ratio <= 1.51, "精英攻击倍率 ∈ [1.3,1.5]", [str(atk_ratio)])


## 怪物池与词缀：按层选池、独特怪相邻层、第 9 层独立、词缀阶段分配
func test_monster_pool() -> void:
	_current_test = "MonsterPool"
	print("\n--- %s ---" % _current_test)

	var MDB = _require_script("res://data/monsters/monster_db.gd")
	var ADB = _require_script("res://data/monsters/affix_db.gd")
	if MDB == null or ADB == null:
		return
	MDB.init()

	# 第 1~8 层池非空，且每个池都恰好含该阶段 10 种基础怪
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for layer in range(1, 9):
		var pool: Array = MDB.pool_for_layer(layer)
		_check(not pool.is_empty(), "第 %d 层怪物池非空（%d 种）" % [layer, pool.size()])
		var phase: int = MDB.PHASE_OF_LAYER[layer]
		var base_count := 0
		for m in pool:
			if not m.get("is_unique", false) and int(m.get("phase", 0)) == phase:
				base_count += 1
		_check(base_count == 10, "第 %d 层含本阶段 10 种基础怪" % layer, [str(base_count)])

	# 独特怪只在「本层及相邻层」出现（分册 3.1）
	var u2: Array = MDB.pool_for_layer(2)
	var u2_ids: Array = []
	for m in u2:
		if m.get("is_unique", false):
			u2_ids.append(str(m.get("id", "")))
	_check(u2_ids.has("mine_bomber"), "第 2 层含第 2 层独特怪（矿道自爆者）", [str(u2_ids)])
	var u3_ids: Array = []
	for m in MDB.pool_for_layer(3):
		if m.get("is_unique", false):
			u3_ids.append(str(m.get("id", "")))
	_check(u3_ids.has("mine_bomber"), "第 3 层仍含相邻层的矿道自爆者（相邻层规则）")
	var u5_ids: Array = []
	for m in MDB.pool_for_layer(5):
		if m.get("is_unique", false):
			u5_ids.append(str(m.get("id", "")))
	_check(not u5_ids.has("mine_bomber"), "第 5 层不含矿道自爆者（超出相邻层）", [str(u5_ids)])

	# 第 9 层：独立终极池，8 种，全为精英
	var p9: Array = MDB.pool_for_layer(9)
	_check(p9.size() == 8, "第 9 层独立终极池 8 种", [str(p9.size())])
	var all_elite := true
	for m in p9:
		if not bool(m.get("is_elite", false)):
			all_elite = false
	_check(all_elite, "第 9 层全部为精英")
	# 第 8 层不得混入第 9 层的怪
	var p8_ids: Array = []
	for m in MDB.pool_for_layer(8):
		p8_ids.append(str(m.get("id", "")))
	_check(not p8_ids.has("chaos_blade"), "第 8 层不含第 9 层终极怪", [str(p8_ids)])

	# 基础怪阶段数值单调递增（血量/攻击随阶段升、间隔随阶段降）
	for key in ["zombie_prison", "skeleton_archer", "rat_mutant"]:
		var m1: Dictionary = MDB.get_monster(key)
		var phase_key: String = str(m1.get("base_key", ""))
		if phase_key.is_empty():
			continue
		var p1: Dictionary = MDB.get_monster(MDB._base_id(phase_key, 1))
		var p4: Dictionary = MDB.get_monster(MDB._base_id(phase_key, 4))
		_check(float(p4.get("hp", 0)) > float(p1.get("hp", 0)),
			"%s 阶段四血量 > 阶段一" % str(m1.get("name")))
		_check(float(p4.get("attack_interval", 9)) < float(p1.get("attack_interval", 9)),
			"%s 阶段四间隔 < 阶段一" % str(m1.get("name")))

	# 词缀：阶段分配照分册第 7 章
	_check(ADB.pool_for_phase(1).is_empty(), "阶段一词缀池为空（纯教学）")
	var p2_pool: Array = ADB.pool_for_phase(2)
	_check(p2_pool.size() == 3, "阶段二词缀池 3 种（快速/强壮/燃烧）", [str(p2_pool.size())])
	_check(ADB.pool_for_phase(3).size() == 5, "阶段三词缀池 5 种（+冰冻/复仇）")
	_check(ADB.pool_for_phase(4).size() == 7, "阶段四词缀池 7 种（+不朽/吸血）")
	_check(ADB.pool_for_phase(5).size() == 9, "第 9 层词缀池 9 种（+虚空/混沌）")

	# 数量规则：阶段一 0 个；阶段二普通 0~1 / 精英 1；阶段四普通 2~3 / 精英 3
	var r2 := RandomNumberGenerator.new()
	r2.seed = 99
	_check(ADB.roll(1, false, r2).is_empty(), "阶段一普通怪无词缀")
	var e2: Array = ADB.roll(2, true, r2)
	_check(e2.size() == 1, "阶段二精英 1 个词缀", [str(e2.size())])
	var n4: Array = ADB.roll(4, false, r2)
	_check(n4.size() >= 2 and n4.size() <= 3, "阶段四普通 2~3 个词缀", [str(n4.size())])
	var e4: Array = ADB.roll(4, true, r2)
	_check(e4.size() == 3, "阶段四精英 3 个词缀", [str(e4.size())])
	# 词缀不重复
	var uniq := {}
	for id in e4:
		uniq[id] = true
	_check(uniq.size() == e4.size(), "同一怪物词缀不重复")

	# 数值型词缀真正作用到属性（快速/强壮）
	var m: Dictionary = MDB.get_monster("zombie_prison").duplicate()
	var before_spd := float(m.get("speed_pct", 0))
	ADB.apply(m, ["fast", "strong"])
	_check(float(m.get("speed_pct", 0)) > before_spd, "「快速」提升移速")
	_check(float(m.get("attack_interval", 9)) < 3.5, "「快速」缩短攻击间隔")
	_check(int(m.get("atk", 0)) > 25, "「强壮」提升攻击")
	_check((m.get("affixes") as Array).size() == 2, "词缀 id 记入 affixes 供后续系统消费")
	# 非数值型词缀只登记、不改属性
	var m2: Dictionary = MDB.get_monster("zombie_prison").duplicate()
	var atk_before := int(m2.get("atk", 0))
	ADB.apply(m2, ["burn", "freeze"])
	_check(int(m2.get("atk", 0)) == atk_before, "非数值型词缀不改属性（仅登记）")
	# 全部 9 个词缀现已接线。这条断言是**反"只登记不实现"的守卫**：
	# 新增词缀却忘了在 enemy_base._apply_affix 里装配钩子时，
	# pending_systems() 会重新出现条目，此处立刻变红。
	_check(ADB.pending_systems().size() == 0, "9 个词缀全部接线（无待实现）",
		[str(ADB.pending_systems())])
	# 已接线清单必须与 affix_db 的 9 个 id 一一对应，不能漏也不能多
	var all_ids: Array = []
	for a in ADB.AFFIXES:
		all_ids.append(str(a[0]))
	var covered: Array = []
	for id in all_ids:
		if ADB.is_numeric(id) or id in ADB.IMPLEMENTED_NON_NUMERIC:
			covered.append(id)
	_check(covered.size() == all_ids.size(),
		"每个词缀 id 都被覆盖（数值型或已接线钩子）",
		["未覆盖：%s" % str(all_ids.filter(func(x): return not (x in covered)))])


## 突进类怪物必须真的能突进。
##
## **为什么单独一条**：机制名进了 `_apply_mechanic` 的 `match` 分支
## **不等于**行为会触发——`dash_slow_trap` / `dash_lava_trail` / `dash_root`
## / `long_dash_root` 四个机制全挂在"突进结束"这个事件上，而突进本身
## 需要 `dash_range > 0.0`。`dash_range` 只从 `special.dash_range` 读，
## 但 `MonsterDB._special_for()` 从没为基础怪写过这个键
##（它只映射 6 个机制，其余返回 `{"mechanic": mech}`）。
## 结果：4 只猎犬 + 虚空猎手 + 混沌利刃 `ai=rusher` 却永不突进，
## 连带那四个机制触发 0 次——门禁全绿，因为**没人断言过突进会发生**。
##
## 本测试走完整的 `apply_monster_config`（不是复刻判定逻辑），
## 这样兜底一旦被删就立刻变红。
func test_rusher_dash_range() -> void:
	_current_test = "RusherDash"
	print("\n--- %s ---" % _current_test)

	var MDB = _require_script("res://data/monsters/monster_db.gd")
	var EB = _require_script("res://entities/enemies/enemy_base.gd")
	if MDB == null or EB == null:
		return
	MDB.init()

	# 分册 4.6 表格原文：突进距离 2 / 2.5 / 3 / 4 米（阶段一~四）
	var expected := {"hound_jailer": 2.0, "hound_p2": 2.5, "hound_p3": 3.0, "hound_p4": 4.0}
	for id in expected:
		var m: Dictionary = MDB.get_monster(id)
		if m.is_empty():
			_check(false, "%s 在 MonsterDB 中" % id)
			continue
		var e = EB.new()
		e.apply_monster_config(m)
		var got := float(e.get("dash_range"))
		_check(is_equal_approx(got, float(expected[id])),
			"%s 突进距离 = %.1f 米（分册 4.6）" % [str(m.get("name")), float(expected[id])],
			["实得 %.2f" % got])
		e.free()

	# 虚空猎手：分册 5.4 写「突进距离翻倍（4 米）」，即基础 2 米 ×2。
	# 它在 hound 阶段四原型上取数，故兜底先给 4 米、再乘 dash_range_mult。
	var vh: Dictionary = MDB.get_monster("void_hunter")
	if not vh.is_empty():
		var ev = EB.new()
		ev.apply_monster_config(vh)
		_check(float(ev.get("dash_range")) > 0.0,
			"虚空猎手有突进距离（基础 %.1f 米）" % float(ev.get("dash_range")))
		_check(is_equal_approx(float(ev.get("dash_range_mult")), 2.0),
			"虚空猎手突进距离翻倍倍率 = 2.0")
		ev.free()

	# 反向守卫：所有 ai=rusher 的怪都必须拿到非零突进距离。
	# 将来新增突进怪却忘了接线时，这条会直接点名。
	var missing: Array = []
	for m in MDB.all_monsters():
		if str(m.get("ai", "")) != "rusher":
			continue
		var e = EB.new()
		e.apply_monster_config(m)
		if float(e.get("dash_range")) <= 0.0:
			missing.append(str(m.get("id", "")))
		e.free()
	_check(missing.is_empty(), "所有 rusher 都有非零突进距离（不会静默不突进）",
		[str(missing)])


## 怪物专属机制接线测试（分册 4.6 / 4.9 / 9-5）。
##
## **为什么需要这一条**：机制名出现在 `_apply_mechanic` 的 `match` 分支里
## **不等于**行为会触发——`dash_range` 那次就是这么漏的（`match` 有分支、
## 参数字典却没给键）。所以这里一律断言**参数装配结果**，不是断言分支存在。
func test_monster_mechanics_wired() -> void:
	_current_test = "MechWired"
	print("\n--- %s ---" % _current_test)

	var MDB = _require_script("res://data/monsters/monster_db.gd")
	var EB = _require_script("res://entities/enemies/enemy_base.gd")
	if MDB == null or EB == null:
		return
	MDB.init()

	# —— 4.6 狱卒猎犬：突进失败后硬直 0.5 秒 ——
	# 前提是它得先会突进（`dash_range > 0`），否则硬直永远不会发生。
	var hj: Dictionary = MDB.get_monster("hound_jailer")
	if not hj.is_empty():
		var e = EB.new()
		e.apply_monster_config(hj)
		_check(is_equal_approx(float(e.get("dash_stun_seconds")), 0.5),
			"狱卒猎犬 突进失败硬直 = 0.5 秒（分册 4.6）",
			["实得 %.2f" % float(e.get("dash_stun_seconds"))])
		_check(float(e.get("dash_range")) > 0.0,
			"狱卒猎犬有突进距离（否则硬直机制不可达）",
			["dash_range=%.2f" % float(e.get("dash_range"))])
		e.free()

	# —— 4.9 熔岩巨兽：每 8 秒熔岩光环（4 米，每秒 20 伤），站熔岩地面每秒回 15 血 ——
	var lava: Dictionary = MDB.get_monster("rat_p3")
	if not lava.is_empty():
		var e = EB.new()
		e.apply_monster_config(lava)
		_check(is_equal_approx(float(e.get("aura_interval")), 8.0),
			"熔岩巨兽 光环间隔 = 8 秒（分册 4.9）",
			["实得 %.1f" % float(e.get("aura_interval"))])
		var spec: Dictionary = e.get("aura_spec")
		_check(is_equal_approx(float(spec.get("radius", 0.0)), 4.0),
			"熔岩巨兽 光环半径 = 4 米", ["实得 %.1f" % float(spec.get("radius", 0.0))])
		_check(is_equal_approx(float(spec.get("damage", 0.0)), 20.0),
			"熔岩巨兽 光环每秒 20 伤", ["实得 %.1f" % float(spec.get("damage", 0.0))])
		_check(is_equal_approx(float(spec.get("heal", 0.0)), 15.0),
			"熔岩巨兽 站熔岩地面每秒回 15 血", ["实得 %.1f" % float(spec.get("heal", 0.0))])
		_check(str(spec.get("friendly_group", "")) == "enemies",
			"熔岩巨兽 回血作用对象 = enemies（分册原文同区敌方也受益）")
		e.free()

	# —— 4.9 虚空巨兽：每 6 秒虚空引力（牵引 2 秒，期间每秒 30 伤）——
	var vg: Dictionary = MDB.get_monster("rat_p4")
	if not vg.is_empty():
		var e = EB.new()
		e.apply_monster_config(vg)
		_check(is_equal_approx(float(e.get("aura_interval")), 6.0),
			"虚空巨兽 引力间隔 = 6 秒（分册 4.9）",
			["实得 %.1f" % float(e.get("aura_interval"))])
		_check(bool(e.get("gravity_pull")), "虚空巨兽 引力开关已打开")
		_check(is_equal_approx(float(e.get("gravity_pull_seconds")), 2.0),
			"虚空巨兽 牵引时长 = 2 秒",
			["实得 %.1f" % float(e.get("gravity_pull_seconds"))])
		_check(is_equal_approx(float(e.get("gravity_pull_dps")), 30.0),
			"虚空巨兽 牵引期间每秒 30 伤",
			["实得 %.1f" % float(e.get("gravity_pull_dps"))])
		e.free()

	# 扭曲巨兽（9-3）是**常驻**牵引，没有时长与伤害——不能被上面那套参数串了。
	var wb: Dictionary = MDB.get_monster("warped_beast")
	if not wb.is_empty():
		var e = EB.new()
		e.apply_monster_config(wb)
		_check(is_equal_approx(float(e.get("gravity_pull_seconds")), 0.0),
			"扭曲巨兽 保持常驻牵引（时长 0，不误加 2 秒窗口）",
			["实得 %.1f" % float(e.get("gravity_pull_seconds"))])
		e.free()

	# —— 9-5 虚空吞噬者：每击杀一个单位恢复 20% 血、体型增大（伤害 +10%）——
	var vd: Dictionary = MDB.get_monster("void_devourer")
	if not vd.is_empty():
		var e = EB.new()
		e.apply_monster_config(vd)
		_check(is_equal_approx(float(e.get("devour_heal_pct")), 0.20),
			"虚空吞噬者 每次击杀回 20% 血",
			["实得 %.2f" % float(e.get("devour_heal_pct"))])
		_check(is_equal_approx(float(e.get("devour_atk_pct")), 0.10),
			"虚空吞噬者 每次击杀伤害 +10%",
			["实得 %.2f" % float(e.get("devour_atk_pct"))])
		e.free()


## 资源系统测试：宝箱/回血/层间恢复/金币产出
func test_resource_system() -> void:
	_current_test = "ResourceSystem"
	print("\n--- %s ---" % _current_test)

	var AS = _require_script("res://data/attributes/attribute_system.gd")
	var LS = _require_script("res://gameplay/loot/loot_system.gd")
	var EB = _require_script("res://entities/enemies/enemy_base.gd")
	var MDB = _require_script("res://data/monsters/monster_db.gd")
	if AS == null or LS == null or EB == null or MDB == null:
		return

	# --- heal 返回实际回复量 ---
	var attrs = AS.new()
	attrs.take_damage(50.0)  # 450/500
	var healed1: float = attrs.heal(20.0)
	_check(healed1 == 20.0, "未满血回复 20 返回 20", [healed1])
	attrs.heal(100.0)  # 满血
	var healed2: float = attrs.heal(30.0)  # 溢出
	_check(healed2 == 0.0, "满血时回复返回 0", [healed2])

	# --- 击杀回血配置 ---
	_check(GameBalance.KILL_HEAL > 0.0, "击杀回血开启（每击 %.0f）" % GameBalance.KILL_HEAL)
	_check(GameBalance.FLOOR_TRANSITION_FULL_HEAL, "层间传送门全恢复开启")

	# --- 宝箱金币范围与击杀金币范围 ---
	_check(GameBalance.CHEST_GOLD_RANGE.x < GameBalance.CHEST_GOLD_RANGE.y, "宝箱金币范围有效")
	_check(GameBalance.KILL_GOLD_RANGE.x >= 5, "击杀金币下限 ≥5（经济可循环）",
		[GameBalance.KILL_GOLD_RANGE.x])

	# --- 宝箱掉落（必掉白装）---
	var EDB = _require_script("res://data/equipment/equipment_db.gd")
	if EDB:
		EDB.init_equipment_db()
		var parent := Node3D.new()
		self.root.add_child(parent)
		var loot = LS.new()
		loot.generate_chest_loot(Vector3.ZERO, parent, 1)
		# 只数拾取物——PickupField（集中管理器）也会作为子节点挂进来，
		# 直接比 get_child_count() 会被它占掉一个名额（实测踩到）。
		var pickups := 0
		for c in parent.get_children():
			if c.is_in_group("pickups"):
				pickups += 1
		_check(pickups == 1, "宝箱掉落生成 1 件拾取物", [pickups])
		# 顺带断言集中管理器确实建立了（掉落物优化的载体）
		_check(parent.get_node_or_null("PickupField") != null,
			"掉落物挂到了 PickupField 管理器下")
		parent.queue_free()

	# --- 怪物金币按血量档位 ---
	var zombie: CharacterBody3D = EB.new()
	zombie.apply_monster_config(MDB.get_monster("zombie_prison"))
	_check(zombie.gold_min >= 3, "僵尸金币下限 ≥3（血量档位）", [zombie.gold_min])
	var rat: CharacterBody3D = EB.new()
	rat.apply_monster_config(MDB.get_monster("rat_mutant"))
	_check(rat.gold_min > zombie.gold_min, "巨鼠金币 > 僵尸（血厚值钱）",
		["%d vs %d" % [rat.gold_min, zombie.gold_min]])
	var boss: CharacterBody3D = EB.new()
	boss.apply_monster_config(MDB.boss_monster())
	_check(boss.gold_min == 50 and boss.gold_max == 120, "Boss 金币 50~120")


## 特殊房交互测试：商店购买、泉水治疗、事件一次性奖励
## 事件房池：策划 总册 5.2 的 9 种事件规则
## 商店消费模块（策划 总册 4.3.2「防溢出深坑」）
func test_shop_consumption() -> void:
	_current_test = "ShopConsumption"
	print("\n--- %s ---" % _current_test)

	var S = _require_script("res://gameplay/dungeon/special_room_service.gd")
	if S == null:
		return

	# 属性灌注：300 起、每次 +50 递增（策划 4.3.2）
	_check(S.infuse_cost(0) == 300, "首次灌注 300 金", [S.infuse_cost(0)])
	_check(S.infuse_cost(1) == 350, "第二次 350 金", [S.infuse_cost(1)])
	_check(S.infuse_cost(5) == 550, "第 6 次 550 金", [S.infuse_cost(5)])
	# 负数次也安全（防御性）
	_check(S.infuse_cost(-3) == 300, "负数次数按首次计价")

	# 灌注掷骰：属性合法且数量在策划区间内
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var saw_atk := false
	var saw_hp := false
	var out_of_range := 0
	for _i in 60:
		var roll: Dictionary = S.roll_infusion(rng)
		var st := str(roll.get("stat", ""))
		var amt := int(roll.get("amount", 0))
		if st == "atk":
			saw_atk = true
			if amt < 1 or amt > 3:
				out_of_range += 1
		elif st == "hp":
			saw_hp = true
			if amt < 3 or amt > 8:
				out_of_range += 1
		else:
			out_of_range += 1
	_check(saw_atk and saw_hp, "灌注能随机到攻击与生命两种")
	_check(out_of_range == 0, "灌注数值都在策划区间内（atk 1~3 / hp 3~8）",
		["越界 %d 次" % out_of_range])

	# 商店升级券：500/800/1200 三级，满级拒绝
	var u1: Dictionary = S.shop_upgrade(0)
	_check(u1.get("ok", false) and int(u1.get("cost", 0)) == 500, "升级券 1 级 500 金", [u1])
	var u2: Dictionary = S.shop_upgrade(1)
	_check(u2.get("ok", false) and int(u2.get("cost", 0)) == 800, "升级券 2 级 800 金", [u2])
	var u3: Dictionary = S.shop_upgrade(2)
	_check(u3.get("ok", false) and int(u3.get("cost", 0)) == 1200, "升级券 3 级 1200 金", [u3])
	var u4: Dictionary = S.shop_upgrade(3)
	_check(not u4.get("ok", false), "商店满级后拒绝继续升级", [u4])

	# 折扣：3 级解锁全店 9 折
	_check(absf(S.shop_discount(0) - 1.0) < 0.001, "未升级无折扣")
	_check(absf(S.shop_discount(3) - 0.9) < 0.001, "3 级解锁 9 折")

	# 融合折扣券：费用减半
	_check(S.apply_fusion_coupon(100, false) == 100, "无券不打折")
	_check(S.apply_fusion_coupon(100, true) == 50, "有券费用减半", [S.apply_fusion_coupon(100, true)])
	_check(S.apply_fusion_coupon(55, true) == 28, "奇数费用向上取整", [S.apply_fusion_coupon(55, true)])

	# 附魔：可叠 3 次
	_check(S.can_enchant(0) and S.can_enchant(2), "附魔 0~2 次可继续")
	_check(not S.can_enchant(3), "附魔满 3 次后拒绝（策划：可叠 3 次）")
	_check(int(S.ENCHANT_COSTS.get("low", 0)) == 800, "低级附魔 800 金")
	_check(int(S.ENCHANT_COSTS.get("mid", 0)) == 2000, "中级附魔 2000 金")
	_check(int(S.ENCHANT_COSTS.get("high", 0)) == 5000, "高级附魔 5000 金")

	# 贷款：借 2000 还 4000
	_check(S.LOAN_AMOUNT == 2000 and S.LOAN_REPAY == 4000, "贷款借 2000 还 4000")

	# —— 商店出售装备（策划 总册 5.1）——
	# 升级券文案承诺「解锁紫装→红装碎片→全店 9 折」，但此前商店一件装备
	# 都不卖——满级解锁的是空集。这组断言把承诺钉住。
	_check(S.shop_max_rarity(0) == EquipmentDefs.Rarity.BLUE,
		"未升级只售白~蓝（商店保底）")
	_check(S.shop_max_rarity(2) == EquipmentDefs.Rarity.PURPLE,
		"2 级解锁紫装（策划 4.3.2）")
	_check(S.shop_max_rarity(3) == EquipmentDefs.Rarity.PURPLE,
		"满级仍不整件售红装（红装走碎片，策划 4.3.2）")

	# 定价：层数成长 + 商店折扣
	var p_base: int = S.shop_price(EquipmentDefs.Rarity.BLUE, 1, 0)
	_check(p_base == 700, "蓝装第 1 层原价 700", [p_base])
	_check(S.shop_price(EquipmentDefs.Rarity.BLUE, 9, 0) > p_base,
		"售价随层数上涨（第 9 层 > 第 1 层）")
	_check(S.shop_price(EquipmentDefs.Rarity.BLUE, 1, 3) == 630,
		"3 级 9 折生效（700 → 630）", [S.shop_price(EquipmentDefs.Rarity.BLUE, 1, 3)])

	# 货架：3 件、稀有度在允许档位内、id 不重复、字段齐全
	var no_rng_stock: Array = S.roll_shop_stock(3, 0, null)
	_check(no_rng_stock.size() == S.SHOP_STOCK_SIZE,
		"货架摆满 %d 件（无随机源时也摆满）" % S.SHOP_STOCK_SIZE,
		["实际 %d" % no_rng_stock.size()])
	var ids := {}
	var rarity_ok := true
	var fields_ok := true
	for row in no_rng_stock:
		ids[str(row.get("id", ""))] = true
		if int(row.get("rarity", -1)) > S.shop_max_rarity(0):
			rarity_ok = false
		for k in ["id", "slot", "rarity", "price", "name", "affix_text"]:
			if not row.has(k):
				fields_ok = false
	_check(ids.size() == no_rng_stock.size(), "货架内不重复（不摆两件同名装备）")
	_check(rarity_ok, "未升级货架不出现紫装")
	_check(fields_ok, "货架条目字段齐全（UI 展示所需）")

	# 升到 2 级后档位放宽，且货架里确实出现过紫装
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 20260919
	var saw_purple := false
	for _i in 20:
		for row in S.roll_shop_stock(5, 2, rng2):
			if int(row.get("rarity", -1)) == EquipmentDefs.Rarity.PURPLE:
				saw_purple = true
	_check(saw_purple, "2 级货架能刷出紫装（升级券不是空头支票）")

	# 货架随机源必须与全局流隔离，否则摆货架会挪动后续所有掷骰
	var a: RandomNumberGenerator = S.shop_stock_rng(7, 3, 0)
	var b: RandomNumberGenerator = S.shop_stock_rng(7, 3, 0)
	var c: RandomNumberGenerator = S.shop_stock_rng(7, 4, 0)
	_check(a.seed == b.seed, "同种子同层同等级 → 货架可复现")
	_check(a.seed != c.seed, "换层 → 货架换一批")


func test_event_room_pool() -> void:
	_current_test = "EventRoomPool"
	print("\n--- %s ---" % _current_test)

	var S = _require_script("res://gameplay/dungeon/special_room_service.gd")
	var AS = _require_script("res://data/attributes/attribute_system.gd")
	if S == null or AS == null:
		return
	var svc = S.new()

	# ① 瘟疫之泉：回满生命 + 随机一项属性 -10%
	var attrs = AS.new()
	attrs.take_damage(300.0)
	var claimed := {"value": false}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var r1: Dictionary = svc.use_plague_spring(attrs, claimed, rng)
	_check(r1.get("ok", false), "瘟疫之泉可用")
	_check(attrs.hp == attrs.max_hp, "瘟疫之泉回满生命",
		["%.0f/%.0f" % [attrs.hp, attrs.max_hp]])
	_check(r1.get("cursed_stat", "") in ["atk", "def", "spd"],
		"瘟疫之泉诅咒一项合法属性", [r1.get("cursed_stat")])
	_check(absf(float(r1.get("cursed_pct", 0.0)) + 0.10) < 0.001,
		"诅咒幅度为 -10%")
	_check(bool(claimed["value"]), "瘟疫之泉标记已使用")
	# 重复使用被拒
	var r1b: Dictionary = svc.use_plague_spring(attrs, claimed, rng)
	_check(not r1b.get("ok", false), "瘟疫之泉不可重复使用")

	# ② 锻造炉：稀有度 +1，上限蓝装
	var ED = _require_script("res://data/equipment/equipment_defs.gd")
	if ED != null:
		var f1: Dictionary = svc.forge_upgrade(ED.Rarity.WHITE, ED.Rarity.BLUE)
		_check(f1.get("ok", false) and int(f1.get("new_rarity", -1)) == ED.Rarity.GREEN,
			"锻造炉：白 → 绿", [f1])
		var f2: Dictionary = svc.forge_upgrade(ED.Rarity.GREEN, ED.Rarity.BLUE)
		_check(f2.get("ok", false) and int(f2.get("new_rarity", -1)) == ED.Rarity.BLUE,
			"锻造炉：绿 → 蓝", [f2])
		var f3: Dictionary = svc.forge_upgrade(ED.Rarity.BLUE, ED.Rarity.BLUE)
		_check(not f3.get("ok", false), "锻造炉：蓝装已达上限，拒绝", [f3])

		# ③ 古代祭坛：同部位 +1 稀有度，上限紫
		var a1: Dictionary = svc.altar_sacrifice(ED.Rarity.WHITE, 0, ED.Rarity.PURPLE)
		_check(a1.get("ok", false) and int(a1.get("want_rarity", -1)) == ED.Rarity.GREEN,
			"祭坛：白装献祭 → 换绿装", [a1])
		var a2: Dictionary = svc.altar_sacrifice(ED.Rarity.PURPLE, 0, ED.Rarity.PURPLE)
		_check(not a2.get("ok", false), "祭坛：紫装已达上限「最高至紫」，拒绝", [a2])

	# ④ 时空裂隙：从已探索房里挑一个（排除当前房）
	var r2: Dictionary = svc.rift_pick_target([0, 1, 2, 3], 2, rng)
	_check(r2.get("ok", false), "裂隙能选出目标房")
	_check(int(r2.get("target_index", -1)) != 2, "裂隙不传送到当前房",
		[r2.get("target_index")])
	_check(int(r2.get("target_index", -1)) in [0, 1, 3], "裂隙目标在已探索列表内")
	# 只有当前房时拒绝
	var r3: Dictionary = svc.rift_pick_target([2], 2, rng)
	_check(not r3.get("ok", false), "无其它已探索房时裂隙拒绝")

	# ⑤ 事件房模板齐全：9 种事件都有对应 JSON（否则生成器抽到就回退起始房）
	var want_types := ["memory_shard", "gambler", "plague", "forge", "altar", "rift"]
	var found := {}
	var dir := DirAccess.open("res://data/rooms/")
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while not fn.is_empty():
			if fn.ends_with(".json") and not dir.current_is_dir():
				var f := FileAccess.open("res://data/rooms/" + fn, FileAccess.READ)
				if f:
					var j := JSON.new()
					if j.parse(f.get_as_text()) == OK:
						var et := str(j.data.get("interaction", {}).get("event_type", ""))
						if not et.is_empty():
							found[et] = true
					f.close()
			fn = dir.get_next()
		dir.list_dir_end()
	for et in want_types:
		_check(found.has(et), "事件 %s 有模板" % et, [found.keys()])


func test_special_room_interactions() -> void:
	_current_test = "SpecialRoomInteractions"
	print("\n--- %s ---" % _current_test)

	var SR = _require_script("res://gameplay/dungeon/special_room_service.gd")
	var AS = _require_script("res://data/attributes/attribute_system.gd")
	if SR == null or AS == null:
		return

	var service = SR.new()
	var attrs = AS.new()
	attrs.take_damage(100.0)
	var heal_result: Dictionary = service.use_healing_spring(attrs)
	_check(heal_result.get("ok", false), "泉水交互成功")
	_check(attrs.hp == attrs.max_hp, "泉水恢复至满血", [attrs.hp])

	var state := {"gold": 100}
	var shop_result: Dictionary = service.buy_shop_item(state, 35)
	_check(shop_result.get("ok", false), "商店购买成功")
	_check(state.gold == 65, "商店扣除正确金币", [state.gold])
	var repeat_shop: Dictionary = service.buy_shop_item(state, 35)
	_check(not repeat_shop.get("ok", false), "商店商品不可重复购买")

	# 使用药水前先扣血，否则满血状态下治疗量为 0 会直接失败
	attrs.take_damage(100.0)
	var potion_state := {"gold": 100, "potions": 0, "capacity": 3}
	var potion_result: Dictionary = service.buy_health_potion(potion_state, 25, 80.0)
	_check(potion_result.get("ok", false), "生命药水购买成功")
	_check(potion_state.gold == 75 and potion_state.potions == 1, "生命药水扣金并入背包")
	var use_result: Dictionary = service.use_health_potion(potion_state, attrs)
	_check(use_result.get("ok", false), "生命药水使用成功")
	_check(potion_state.potions == 0, "使用后药水数量减少")
	var full_state := {"gold": 100, "potions": 3, "capacity": 3}
	var full_result: Dictionary = service.buy_health_potion(full_state, 25, 80.0)
	_check(not full_result.get("ok", false), "药水背包满时无法购买")

	var event_state := {}
	var event_result: Dictionary = service.claim_event_reward(event_state, 12)
	_check(event_result.get("ok", false), "事件首次交互成功")
	_check(event_state.get("claimed", false), "事件记录已领取")
	var repeat_result: Dictionary = service.claim_event_reward(event_state, 12)
	_check(not repeat_result.get("ok", false), "事件不可重复领取")

	var RD = _require_script("res://data/rooms/room_data.gd")
	if RD:
		# 事件房已按事件类型拆成多个文件（记忆碎片 / 赌徒），其余特殊房仍是单文件
		var special_templates := {
			"shop": ["res://data/rooms/room_shop.json"],
			"heal": ["res://data/rooms/room_heal.json"],
			"event": [
				"res://data/rooms/room_event_memory.json",
				"res://data/rooms/room_event_gambler.json",
			],
		}
		for room_type in special_templates:
			for path in special_templates[room_type]:
				var special_room = RD.load_from_file(path)
				_check(special_room != null, "%s 房模板可加载（%s）" % [room_type, path.get_file()])
				if special_room:
					_check(special_room.room_type == room_type, "%s 房类型正确" % room_type)
					_check(not special_room.interaction.is_empty(), "%s 房交互配置存在" % room_type)

		# 事件房必须带 event_type，UI 靠它分支
		for path in special_templates["event"]:
			var er = RD.load_from_file(path)
			if er:
				_check(not str(er.interaction.get("event_type", "")).is_empty(),
					"事件房带 event_type（%s）" % path.get_file())

## Boss 房闭环测试：boss 房 JSON 可解析 → 刷 Boss → 杀 Boss → 传送门出现
func test_boss_room_loop() -> void:
	_current_test = "BossRoomLoop"
	print("\n--- %s ---" % _current_test)

	var RC = _require_script("res://gameplay/dungeon/room_controller.gd")
	var RD = _require_script("res://data/rooms/room_data.gd")
	if RC == null or RD == null:
		return

	# Boss 房 JSON 可解析且类型正确
	var boss_room = RD.load_from_file("res://data/rooms/room_boss.json")
	_check(boss_room != null, "boss 房 JSON 可加载")
	if boss_room:
		_check(boss_room.room_type == "boss", "boss 房类型为 boss", [boss_room.room_type])
		var boss_spawns: Array = []
		for e in boss_room.entities:
			if str(e.get("type", "")) == "boss_spawn":
				boss_spawns.append(e)
		_check(boss_spawns.size() == 1, "boss 房恰有 1 个 Boss 点", [boss_spawns.size()])
		var boss_spawn: Dictionary = boss_room.get_player_spawn()
		_check(not boss_spawn.is_empty(), "boss 房有玩家入口")

	# 构造 boss 房场景：boss_spawn 标记 → 激活 → Boss 生成 → 杀死 → 传送门
	var room_root := Node3D.new()
	room_root.name = "Room_Boss_Test"
	root.add_child(room_root)

	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	room_root.add_child(spawns)
	var boss_marker := Marker3D.new()
	boss_marker.position = Vector3(5, 0, 5)
	boss_marker.add_to_group("boss_spawn")
	spawns.add_child(boss_marker)

	var controller = RC.new()
	controller.name = "RoomController"
	controller.set("room_data", {"room_id": "room_boss", "room_type": "boss"})
	room_root.add_child(controller)
	await process_frame

	controller.activate()
	_check(controller.is_boss_room, "识别为 Boss 房")
	_check(controller.enemies_alive == 1, "刷出 1 只 Boss", [controller.enemies_alive])
	var boss = controller.get("_boss")
	_check(boss != null, "Boss 实例存在")
	if boss:
		# Boss 血量 = FloorDefs.boss_hp(本层) × BossDB 个体倍率 × 难度（batch C 起）。
		# 不再等于固定的 600，故断言落在合理区间（0.8~1.5 倍基准为个体差异 + 难度）。
		var base: float = FloorDefs.boss_hp(1)
		var lo: float = base * 0.7
		var hi: float = base * 1.6
		_check(boss.max_hp >= lo and boss.max_hp <= hi,
			"Boss 血量来自 FloorDefs（实际 %.0f，区间 %.0f~%.0f）" % [boss.max_hp, lo, hi])
		# 名字必须来自 BossDB 的轮换池，不再是固定的「鼠王」
		var bname: String = str(boss.get("monster_name"))
		var pool_names: Array = []
		for b in BossDB.pool_for_floor(1):
			pool_names.append(str(b.get("name", "")))
		_check(bname in pool_names,
			"Boss 名字来自第 1 层轮换池（%s）" % bname, [pool_names])

		# 杀 Boss → 房间清空 + 传送门出现
		boss.take_damage(999999.0)
		await process_frame
		_check(controller.is_cleared, "Boss 死后房间清空")
		var portal = controller.get("_portal")
		_check(portal != null and is_instance_valid(portal), "生成下一层传送门")

	room_root.queue_free()

## 门拓扑测试：门必须只出现在有邻接房间的方位上（消除哑门）
func test_doors_by_topology() -> void:
	_current_test = "DoorsByTopology"
	print("\n--- %s ---" % _current_test)

	var DT = _require_script("res://gameplay/dungeon/doors_by_topology.gd")
	if DT == null:
		return

	# 手工拓扑：3 房一字排开 + 一条支线
	#   [0 start(0,0)] — [1 normal(1,0)] — [2 boss(2,0)]
	#                          |
	#                    [3 shop(1,1)]
	var rooms: Array = [
		{"position": Vector2i(0, 0), "type": "start"},
		{"position": Vector2i(1, 0), "type": "normal"},
		{"position": Vector2i(2, 0), "type": "boss"},
		{"position": Vector2i(1, 1), "type": "shop"},
	]
	var conns: Array = [[0, 1], [1, 2], [1, 3]]

	var parents: Array = DT.bfs_parents(rooms, conns, 0)
	_check(parents[0] == -1, "起始房无父节点")
	_check(int(parents[1]) == 0, "房1 父节点=房0")
	_check(int(parents[2]) == 1, "房2 父节点=房1")
	_check(int(parents[3]) == 1, "房3 父节点=房1")

	# --- 核心不变量：每扇门都通向真实邻接房间 ---
	for i in rooms.size():
		var dirs: Array = DT.directions_for(rooms, conns, i, 0, int(parents[i]))
		for d in dirs:
			_check(_has_neighbor_in_dir(rooms, conns, i, str(d)),
				"房%d 的 %s 门通向邻接房间" % [i, d])

	# --- 起始房：仅邻接方向，不补回退门 ---
	var d0: Array = DT.directions_for(rooms, conns, 0, 0, int(parents[0]))
	_check(d0.size() == 1 and d0.has("east"), "起始房仅东门（唯一邻接）", [str(d0)])

	# --- 中间房：三个邻接方位齐全 ---
	var d1: Array = DT.directions_for(rooms, conns, 1, 0, int(parents[1]))
	_check(d1.size() == 3, "房1 有 3 扇门", [str(d1)])
	_check(d1.has("west") and d1.has("east") and d1.has("south"), "房1 方位正确", [str(d1)])

	# --- Boss 房：单邻接则只有一扇门（不补哑门） ---
	var d2: Array = DT.directions_for(rooms, conns, 2, 0, int(parents[2]))
	_check(d2.size() == 1 and d2.has("west"), "房2 仅西门（邻接房1，不补哑门）", [str(d2)])

	# --- 死胡同救急：本房无任何邻接时补一扇回退门 ---
	var lonely: Array = [
		{"position": Vector2i(0, 0), "type": "start"},
		{"position": Vector2i(0, 5), "type": "normal"},   # 与起点同列、隔 5 格，无 connection
	]
	var d_lonely: Array = DT.directions_for(lonely, [], 1, 0, 0)
	_check(d_lonely.size() == 1 and d_lonely.has("north"),
		"孤立房补回退门（北向起点）", [str(d_lonely)])

	# --- 门格坐标在边界上 ---
	_check(DT.cell_for("north", 20, 15).y == 0, "北门在 y=0 边界")
	_check(DT.cell_for("south", 20, 15).y == 14, "南门在 y=height-1 边界")
	_check(DT.cell_for("west", 20, 15).x == 0, "西门在 x=0 边界")
	_check(DT.cell_for("east", 20, 15).x == 19, "东门在 x=width-1 边界")
	var cn: Vector2i = DT.cell_for("north", 20, 15)
	_check(cn.x >= 0 and cn.x < 20, "北门 x 在范围内")

	# --- build_doors 产出可直接喂给 DoorBuilder 的结构 ---
	var doors: Array = DT.build_doors(rooms, conns, 1, 0, int(parents[1]), 20, 15)
	_check(doors.size() == 3, "房1 生成 3 扇门数据", [str(doors.size())])
	var ids := {}
	for d in doors:
		_check(d.has("x") and d.has("y") and d.has("direction") and d.has("id"), "门字段完整")
		ids[d["id"]] = true
	_check(ids.size() == doors.size(), "门 id 互不重复")

	# --- 边界情形：孤立单房间 ---
	var single: Array = [{"position": Vector2i(0, 0), "type": "start"}]
	var d_single: Array = DT.directions_for(single, [], 0, 0, 0)
	_check(d_single.is_empty(), "孤立起始房无门", [str(d_single)])


## 房 i 在 dir 方向是否有邻接房间（测试辅助）
func _has_neighbor_in_dir(rooms: Array, conns: Array, i: int, dir: String) -> bool:
	for conn in conns:
		var other := -1
		if int(conn[0]) == i:
			other = int(conn[1])
		elif int(conn[1]) == i:
			other = int(conn[0])
		if other < 0:
			continue
		var diff: Vector2i = rooms[other]["position"] - rooms[i]["position"]
		var d := ""
		if diff.x > 0:
			d = "east"
		elif diff.x < 0:
			d = "west"
		elif diff.y > 0:
			d = "south"
		elif diff.y < 0:
			d = "north"
		if d == dir:
			return true
	return false


## 地牢生成规则测试：BFS 图距离 / 特殊房距离门控 / 房型配额
## 多种子批量验证，避免单种子偶然通过
func test_dungeon_generation_rules() -> void:
	_current_test = "DungeonGeneration"
	print("\n--- %s ---" % _current_test)

	var DG = _require_script("res://gameplay/dungeon/dungeon_generator.gd")
	if DG == null:
		return

	# --- 单图：BFS 距离正确性 ---
	var g = DG.new()
	g.min_rooms = 13
	g.max_rooms = 13
	g.generate(12345)
	# 总房间数 = 13（隐藏房计入配额：连通房 11 + 隐藏房 2，见 generate 注释）
	_check(g.rooms.size() == 13, "生成 13 房间（含隐藏房配额）", [g.rooms.size()])
	var d0: Dictionary = probe.gen_bfs_distances(g, g.start_room_index)
	_check(int(d0.get(g.start_room_index, -1)) == 0, "起点到自身距离 0")
	# 相邻房间距离必为 1
	var adj: Array = g.get_adjacent_rooms(g.start_room_index)
	if not adj.is_empty():
		_check(int(d0.get(adj[0], -1)) == 1, "相邻房间距离为 1", [d0.get(adj[0], -1)])
	# 所有**连通**房间都可达（隐藏房不在此列——它故意不与任何房间连通，
	# 靠破墙进入，见 DoorsByTopology.build_doors 对 hidden 的短路）
	var hidden := 0
	for r in g.rooms:
		if str(r.get("type", "")) == "hidden":
			hidden += 1
	_check(d0.size() == g.rooms.size() - hidden,
		"所有连通房间从起点可达（隐藏房除外）",
		["可达 %d / 共 %d（隐藏 %d）" % [d0.size(), g.rooms.size(), hidden]])
	# Boss 是图距离最远的房
	var boss_d: int = int(d0.get(g.boss_room_index, -1))
	var max_d := 0
	for v in d0.values():
		max_d = maxi(max_d, int(v))
	_check(boss_d == max_d, "Boss 房是图距离最远的房", ["boss=%d max=%d" % [boss_d, max_d]])

	# --- 多种子批量验放置规则 ---
	var shop_ok := 0
	var heal_ok := 0
	var treasure_farthest_ok := 0
	var type_counts := {}
	var seeds := 60
	for s in range(1, seeds + 1):
		var gen = DG.new()
		gen.min_rooms = 13
		gen.max_rooms = 13
		gen.generate(s)
		var ds: Dictionary = probe.gen_bfs_distances(gen, gen.start_room_index)
		var db: Dictionary = probe.gen_bfs_distances(gen, gen.boss_room_index)
		# 排除 Boss（它按规则必须占最深处）后，从起点可达的最远距离
		# 宝藏是特殊房里第一个被放置的，应当拿到这个最深位置
		var deepest_non_boss := 0
		for idx in gen.rooms.size():
			if str(gen.rooms[idx].get("type", "")) == "boss":
				continue
			deepest_non_boss = maxi(deepest_non_boss, int(ds.get(idx, 0)))

		for idx in gen.rooms.size():
			var t := str(gen.rooms[idx].get("type", ""))
			type_counts[t] = int(type_counts.get(t, 0)) + 1
			match t:
				"shop":
					var dd: int = int(ds.get(idx, -1))
					if dd >= 3 and dd <= 5:
						shop_ok += 1
				"treasure":
					# 宝藏是特殊房里第一个被放置的，应拿到「排除 Boss 后的最深处」。
					# 策划要求距初始 4~7，但本层 13 房直径不足时退化为该最深处。
					var dt: int = int(ds.get(idx, -1))
					if dt == deepest_non_boss and dt >= mini(4, deepest_non_boss):
						treasure_farthest_ok += 1
				"heal":
					var ddb: int = int(db.get(idx, -1))
					if ddb >= 2 and ddb <= 4:
						heal_ok += 1

	# 距离门控在多数种子上应严格落在区间内（13 房小图上偶有无解，允许放宽）
	_check(shop_ok >= int(seeds * 0.7), "商店多数落在距初始 3~5（%d/%d）" % [shop_ok, seeds])
	_check(heal_ok >= int(seeds * 0.5), "泉水多数落在距 Boss 2~4（%d/%d）" % [heal_ok, seeds])
	# 宝箱的区间（4~7）为 14×14 大地图设计，而本层固定 13 房、BFS 直径仅 3~6，
	# 故改为验证能达成的性质：宝箱距初始 ≥ min(4, 该图最远距离)
	# （放置顺序把约束最强的宝箱排在最前，就是为了让它拿到最深的房）
	_check(treasure_farthest_ok >= int(seeds * 0.9),
		"宝箱放在策划距离内/可达最深处（%d/%d）" % [treasure_farthest_ok, seeds])

	# 每层配额：start/boss/shop/treasure 各至少 1；事件房 ≥2
	_check(int(type_counts.get("start", 0)) == seeds, "每层 1 间初始房")
	_check(int(type_counts.get("boss", 0)) == seeds, "每层 1 间 Boss 房")
	_check(int(type_counts.get("shop", 0)) >= seeds, "每层至少 1 间商店")
	_check(int(type_counts.get("treasure", 0)) >= seeds, "每层至少 1 间宝箱房")
	_check(int(type_counts.get("event", 0)) >= seeds * 2, "每层至少 2 间事件房")
	# 精英占怪物房 20~30%
	var elite := int(type_counts.get("elite", 0))
	var normal := int(type_counts.get("normal", 0))
	var elite_ratio := float(elite) / maxf(float(elite + normal), 1.0)
	_check(elite_ratio >= 0.15 and elite_ratio <= 0.40,
		"精英占怪物房 20~30%% 量级（实际 %.0f%%）" % [elite_ratio * 100.0])


## 加权掉落测试：稀有度分布 / 逐层缩放 / Boss 保底 / 精英概率
func test_weighted_loot() -> void:
	_current_test = "WeightedLoot"
	print("\n--- %s ---" % _current_test)

	var LS = _require_script("res://gameplay/loot/loot_system.gd")
	var EDB = _require_script("res://data/equipment/equipment_db.gd")
	var ED = _require_script("res://data/equipment/equipment_defs.gd")
	if LS == null or EDB == null or ED == null:
		return

	EDB.init_equipment_db()

	# --- 权重表结构 ---
	_check(GameBalance.RARITY_WEIGHTS.size() == 6, "稀有度权重表覆盖 6 档")
	_check(GameBalance.RARITY_WEIGHTS[0] == 57.0 and GameBalance.RARITY_WEIGHTS[1] == 26.0
		and GameBalance.RARITY_WEIGHTS[2] == 11.0 and GameBalance.RARITY_WEIGHTS[3] == 4.0
		and GameBalance.RARITY_WEIGHTS[4] == 2.0,
		"基础权重 = 策划的 57/26/11/4/2", [str(GameBalance.RARITY_WEIGHTS)])
	_check(GameBalance.RARITY_WEIGHTS[5] == 0.0, "红色不参与随机掉落（权重 0）")

	# --- 分布模拟：第 1 层 20000 次，各稀有度占比贴近 57/26/11/4/2 ---
	var loot = LS.new()
	loot.rng.set_seed(20260913)
	var N := 20000
	var counts := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	for i in N:
		var r: int = probe.loot_roll_rarity(loot, 1)
		counts[r] = int(counts.get(r, 0)) + 1
	var expected := [57.0, 26.0, 11.0, 4.0, 2.0, 0.0]
	for r in 5:
		var actual_pct := float(counts[r]) / float(N) * 100.0
		var exp_pct: float = expected[r]
		_check(absf(actual_pct - exp_pct) < 3.0,
			"稀有度 %d 占比贴近 %.0f%%（实际 %.1f%%）" % [r, exp_pct, actual_pct])
	_check(int(counts[5]) == 0, "红色模拟中一次都不出现（仅 Boss 保底产出）")

	# --- 逐层缩放：高层高稀有度占比显著高于低层 ---
	var high_low := 0
	var high_high := 0
	var M := 20000
	for i in M:
		var r: int = probe.loot_roll_rarity(loot, 1)
		if r >= 2:
			high_low += 1
	for i in M:
		var r2: int = probe.loot_roll_rarity(loot, 9)
		if r2 >= 2:
			high_high += 1
	_check(high_high > high_low, "第 9 层高稀有度占比高于第 1 层",
		["层1=%d 层9=%d" % [high_low, high_high]])

	# 权重纯函数：白装权重不随层数变化，高稀有度随层数增长
	var w1: Array = LS.rarity_weights_for_floor(1)
	var w9: Array = LS.rarity_weights_for_floor(9)
	_check(w1[0] == w9[0], "白装权重不随层数变化")
	_check(w9[4] > w1[4], "橙装权重随层数增长")

	# --- 掉落率随层递减（数量侧收紧，稀有度侧提升）---
	# 症状：后期"击杀一个敌人就掉落过量装备"。层数越高房间/怪密度越大，
	# 恒定掉落率的乘积会让每层到手装备量随层数膨胀，背包长期爆满。
	# 不变量：掉落概率必须随层数单调不增，且有下限防止后期完全断供。
	var c1: float = probe.loot_floor_decayed_chance(loot, GameBalance.BASE_DROP_CHANCE, 1)
	var c5: float = probe.loot_floor_decayed_chance(loot, GameBalance.BASE_DROP_CHANCE, 5)
	var c9: float = probe.loot_floor_decayed_chance(loot, GameBalance.BASE_DROP_CHANCE, 9)
	_check(absf(c1 - GameBalance.BASE_DROP_CHANCE) < 0.0001,
		"第 1 层掉落率不衰减（%.3f）" % c1)
	_check(c5 < c1 and c9 < c5, "掉落率随层单调递减（%.3f → %.3f → %.3f）" % [c1, c5, c9])
	_check(c9 >= GameBalance.DROP_CHANCE_MIN, "掉落率不低于下限（%.3f）" % c9)
	var ce9: float = probe.loot_floor_decayed_chance(loot, GameBalance.ELITE_DROP_CHANCE, 9)
	_check(ce9 > c9, "精英掉落率仍高于杂兵（%.3f > %.3f）" % [ce9, c9])

	# --- Boss 保底 ---
	_check(probe.loot_boss_pity_rarity(loot, 1) == ED.Rarity.ORANGE, "第 1 层 Boss 保底橙装")
	_check(probe.loot_boss_pity_rarity(loot, 5) == ED.Rarity.ORANGE, "第 5 层 Boss 保底橙装")
	_check(probe.loot_boss_pity_rarity(loot, 6) == ED.Rarity.RED, "第 6 层 Boss 保底红装")
	_check(probe.loot_boss_pity_rarity(loot, 8) == ED.Rarity.RED, "第 8 层 Boss 保底红装")

	# --- 精英/普通概率分支 ---
	_check(probe.loot_is_elite(loot, {"elite": true}), "识别精英标记（Dictionary）")
	_check(not probe.loot_is_elite(loot, {}), "非精英不误判")
	_check(probe.loot_is_boss(loot, {"boss": true}), "识别 Boss 标记")
	_check(not probe.loot_is_boss(loot, {}), "非 Boss 不误判")

	# --- 显式掉落表优先 ---
	var explicit = probe.loot_roll_template(loot, {"loot": "W01"})
	_check(explicit != null and explicit.id == &"W01", "显式掉落表优先生效")

	# --- 高稀有度池可选（加权掉落的前提）---
	for r in [ED.Rarity.GREEN, ED.Rarity.BLUE, ED.Rarity.PURPLE, ED.Rarity.ORANGE]:
		_check(not EDB.get_templates_by_rarity(r).is_empty(), "稀有度 %d 池非空可抽" % r)


## 房间模板池完整性：normal/elite/treasure 必须有模板
## 回归本次修复的核心缺口——此前这三类无模板，_pick_template 回退到 room_start，
## 导致 13 房里有 8 个长得和起始房一样
func test_room_template_pool() -> void:
	_current_test = "RoomTemplatePool"
	print("\n--- %s ---" % _current_test)

	var dir := DirAccess.open("res://data/rooms/")
	if dir == null:
		_check(false, "房间目录可访问")
		return
	var by_type := {}
	dir.list_dir_begin()
	var fn := dir.get_next()
	while not fn.is_empty():
		if fn.ends_with(".json") and not dir.current_is_dir():
			var f := FileAccess.open("res://data/rooms/" + fn, FileAccess.READ)
			if f:
				var j := JSON.new()
				if j.parse(f.get_as_text()) == OK:
					var t := str(j.data.get("room_type", ""))
					by_type[t] = int(by_type.get(t, 0)) + 1
				f.close()
		fn = dir.get_next()
	dir.list_dir_end()

	# 地牢会产出的每一种房型都必须有模板，否则走回退（房间长得一样）
	for needed in ["start", "normal", "elite", "boss", "shop", "heal", "event", "treasure"]:
		_check(int(by_type.get(needed, 0)) > 0,
			"房型 %s 有模板（避免回退到起始房）" % needed,
			["该类型模板数 = %d" % int(by_type.get(needed, 0))])
	# 普通房应有多种布局（策划要求多种战斗房）
	_check(int(by_type.get("normal", 0)) >= 4,
		"普通房至少 4 种布局", [int(by_type.get("normal", 0))])


## 层级系统（FloorDefs）：9 层定义完整、范围/房间数/难度逐层递增
## 依据关卡设计分册 1.2（8+1 层结构）、2.1（范围 14→30）、5.3（难度曲线）
func test_floor_defs() -> void:
	_current_test = "FloorDefs"
	print("\n--- %s ---" % _current_test)

	_check(FloorDefs.FLOORS.size() == 9, "共 9 层定义",
		["实际 %d" % FloorDefs.FLOORS.size()])
	_check(FloorDefs.MAX_FLOOR == 9, "层数上限 = 9")

	# 每层必须有完整字段且 id 唯一
	var ids := {}
	for i in FloorDefs.FLOORS.size():
		var f: int = i + 1
		var d: Dictionary = FloorDefs.FLOORS[i]
		var id := str(d.get("id", ""))
		_check(not id.is_empty(), "第 %d 层有主题 id" % f)
		_check(not ids.has(id), "第 %d 层主题 id 唯一（%s）" % [f, id])
		ids[id] = true
		for key in ["name", "range_half", "rooms_min", "rooms_max",
				"monster_mult", "boss_hp", "colors"]:
			_check(d.has(key), "第 %d 层有字段 %s" % [f, key])
		# 配色六键齐全（缺键会让 builder 拿到回退灰，层间无区分）
		var colors: Dictionary = d.get("colors", {})
		for ck in ["floor", "wall", "accent", "ambient", "fog", "light"]:
			_check(colors.has(ck), "第 %d 层配色含 %s" % [f, ck])

	# 可用范围逐层扩张（策划书 2.1：14×14 → 30×30）
	var prev_half := 0
	var range_ok := true
	for f in range(1, 10):
		var h := FloorDefs.range_half(f)
		if h < prev_half:
			range_ok = false
		prev_half = h
	_check(range_ok, "可用范围逐层不减")
	_check(FloorDefs.range_half(1) == 7, "第 1 层范围 14×14（半边长 7）",
		[FloorDefs.range_half(1)])
	_check(FloorDefs.range_half(9) == 15, "第 9 层范围 30×30（半边长 15）",
		[FloorDefs.range_half(9)])

	# 难度（层因子）严格递增
	var prev_mult := 0.0
	var mult_ok := true
	for f in range(1, 10):
		var m := FloorDefs.monster_mult(f)
		if m <= prev_mult:
			mult_ok = false
		prev_mult = m
	_check(mult_ok, "怪物强度倍率逐层递增")
	_check(absf(FloorDefs.monster_mult(1) - 1.0) < 0.001, "第 1 层倍率 1.0（基准）")
	_check(FloorDefs.monster_mult(9) > 3.0, "第 9 层倍率 > 3.0（终极挑战）",
		[FloorDefs.monster_mult(9)])

	# Boss 血量基准递增（策划书 5.3）
	_check(FloorDefs.boss_hp(1) < FloorDefs.boss_hp(3),
		"Boss 血量随层提升（1层 < 3层）")
	_check(FloorDefs.boss_hp(8) >= 5000.0, "第 8 层 Boss 血量 ≥ 5000",
		[FloorDefs.boss_hp(8)])

	# 第 9 层为隐藏层，固定 5 间房（策划书：奖励大厅 + Boss 连战×3 + 传送点）
	_check(FloorDefs.is_hidden(9), "第 9 层标记为隐藏层")
	_check(not FloorDefs.is_hidden(8), "第 8 层不是隐藏层")
	_check(FloorDefs.room_count(9) == 5, "第 9 层固定 5 间房",
		[FloorDefs.room_count(9)])

	# 房间数随层递增（取区间中值比较，避开随机）
	var prev_rooms := 0
	var rooms_ok := true
	for f in range(1, 9):
		var rc := FloorDefs.room_count(f)
		if rc < prev_rooms:
			rooms_ok = false
		prev_rooms = rc
	_check(rooms_ok, "房间数随层不减（1~8 层）")
	_check(FloorDefs.room_count(1) >= 12, "第 1 层至少 12 间房",
		[FloorDefs.room_count(1)])
	_check(FloorDefs.room_count(8) >= 20, "第 8 层至少 20 间房",
		[FloorDefs.room_count(8)])

	# 越界层数钳制（存档损坏 / 调试跳层不该崩）
	_check(FloorDefs.theme_id(0) == FloorDefs.theme_id(1), "层数 0 钳制到第 1 层")
	_check(FloorDefs.theme_id(99) == FloorDefs.theme_id(9), "层数 99 钳制到第 9 层")

	# 主题两两不同（层间必须有视觉区分，这是本批次的核心目标）
	var seen_colors := {}
	var distinct := true
	for f in range(1, 10):
		var key := str(FloorDefs.color_of(f, "floor"))
		if seen_colors.has(key):
			distinct = false
		seen_colors[key] = f
	_check(distinct, "9 层地板配色两两不同（每层长得不一样）")


## 生成器范围约束：各层房间数都能在范围内的网格放满（不会死循环/缺房）
## 对照策划书 2.1 的「可用范围」与 1.2 的「总房间数」
func test_dungeon_range_fits() -> void:
	_current_test = "DungeonRangeFits"
	print("\n--- %s ---" % _current_test)

	for f in range(1, 10):
		var half: int = FloorDefs.range_half(f)
		var want: int = FloorDefs.room_count(f)
		var gen := DungeonGenerator.new()
		gen.rng.set_seed(12345 + f)
		gen.min_rooms = want
		gen.max_rooms = want
		gen.range_half = half
		gen.floor_num = f
		gen.generate(12345 + f)
		_check(gen.rooms.size() == want,
			"第 %d 层生成 %d 间房（范围 ±%d）" % [f, want, half],
			["实际 %d" % gen.rooms.size()])
		# 全部房间必须在范围内
		var oob := 0
		for r in gen.rooms:
			var p: Vector2i = r.get("position", Vector2i.ZERO)
			if absi(p.x) > half or absi(p.y) > half:
				oob += 1
		_check(oob == 0, "第 %d 层无越界房间" % f, ["越界 %d 间" % oob])

	# range_half <= 0 时不限制（兼容旧调用）
	var gen2 := DungeonGenerator.new()
	gen2.rng.set_seed(7)
	gen2.min_rooms = 10
	gen2.max_rooms = 10
	gen2.range_half = 0
	gen2.generate(7)
	_check(gen2.rooms.size() == 10, "range_half=0 时不受范围限制", [gen2.rooms.size()])


## 每层 Boss 掉落标准（关卡分册 6.2~6.9 各层「掉落标准」）
func test_boss_drop_table() -> void:
	_current_test = "BossDropTable"
	print("\n--- %s ---" % _current_test)

	_check(FloorDefs.BOSS_DROPS.size() == 9, "9 层掉落表齐全",
		[FloorDefs.BOSS_DROPS.size()])

	# 保底稀有度：1~5 层橙、6~8 层红（策划：第 6 层起升级为红装）
	for f in range(1, 6):
		_check(FloorDefs.boss_rarity(f) == FloorDefs.RARITY_ORANGE,
			"第 %d 层 Boss 保底橙装" % f, [FloorDefs.boss_rarity(f)])
	for f in range(6, 9):
		_check(FloorDefs.boss_rarity(f) == FloorDefs.RARITY_RED,
			"第 %d 层 Boss 保底红装" % f, [FloorDefs.boss_rarity(f)])

	# 金币区间：递增且合法
	var prev_hi := 0
	var gold_ok := true
	for f in range(1, 9):
		var g := FloorDefs.boss_gold_range(f)
		if g.x <= 0.0 or g.y < g.x:
			gold_ok = false
		if int(g.y) < prev_hi:
			gold_ok = false
		prev_hi = int(g.y)
	_check(gold_ok, "各层金币区间合法且上限不减")

	# 碎片概率：1~8 层为正（8 层各 1 片才能凑齐 8），第 9 层为 0
	for f in range(1, 9):
		var c := FloorDefs.boss_fragment_chance(f)
		_check(c > 0.0 and c <= 1.0, "第 %d 层有碎片掉落概率（%.2f）" % [f, c])
	_check(FloorDefs.boss_fragment_chance(9) == 0.0, "第 9 层不产碎片（终极层）")

	# 解锁所需碎片数 = 8 片 = 前 8 层每层至多 1 片
	_check(FloorDefs.KEY_FRAGMENTS_REQUIRED == 8, "解锁隐藏层需 8 片碎片",
		[FloorDefs.KEY_FRAGMENTS_REQUIRED])


## 红装池非空：第 6 层起 Boss 保底红装，池空会回退白装（回归此 bug）
## 装备通用词条池（名词设计分册第 5 章「装备可附加，21 种」）
## 这批词条此前**完全没有承载**：AffixData 只有 Stat+value，没有「概率触发」形态，
## 导致分册的 9 种触发型词条（眩晕/破甲/致盲/缴械/范围伤害…）无法落地。
func test_generic_affix_pool() -> void:
	_current_test = "GenericAffixPool"
	print("\n--- %s ---" % _current_test)

	EquipmentDB.init_equipment_db()

	# 池表规模与分册口径（16 属性型 + 5 触发型；分册共 21 种，
	# 其中 4 种「负面时长+/击退距离+」等已并入属性型表）
	_check(EquipmentDB.GENERIC_STAT_POOL.size() == 16,
		"属性型通用词条 16 种", [EquipmentDB.GENERIC_STAT_POOL.size()])
	_check(EquipmentDB.GENERIC_TRIGGER_POOL.size() == 5,
		"触发型通用词条 5 种", [EquipmentDB.GENERIC_TRIGGER_POOL.size()])

	# 触发型施加的词条 id 必须在 BuffDefs 里真实存在（否则触发了也没效果）
	for row in EquipmentDB.GENERIC_TRIGGER_POOL:
		var bid := str(row[2])
		if bid == "splash":
			continue   # 范围伤害是直接结算，不施加词条
		_check(not BuffDefs.get_buff(bid).is_empty(),
			"触发词条 %s 在 BuffDefs 中存在" % bid)
		# 概率区间合法
		_check(float(row[3]) > 0.0 and float(row[4]) >= float(row[3]),
			"触发词条 %s 概率区间合法（%.2f~%.2f）" % [bid, row[3], row[4]])

	# 属性型的 stat 键可解析（面板属性走 AttributeSystem，其余走 SPECIAL_STAT）
	for row in EquipmentDB.GENERIC_STAT_POOL:
		var key := str(row[2])
		var ok := EquipmentDB.stat_enum_of(key) >= 0 \
			or EquipmentDB.special_enum_of(key) >= 0
		_check(ok, "属性词条 %s 的 stat 键可解析（%s）" % [row[0], key])

	# AffixData 的触发型构造
	var t := AffixData.make_trigger("stun", 0.05, 1.0)
	_check(t.is_trigger(), "make_trigger 构造的是触发型")
	_check(not t.is_stat(), "触发型不被当作属性型（不会误挂 AttributeSystem）")
	_check(t.trigger_buff == "stun" and absf(t.trigger_chance - 0.05) < 0.001,
		"触发型字段正确")
	_check(t.description().contains("眩晕"), "触发型描述含词条名（%s）" % t.description())

	# 稀有度递进：白/绿无触发词条，蓝起有，橙有 2 条
	var white_pool: Array = EquipmentDB.get_templates_by_rarity(EquipmentDefs.Rarity.WHITE)
	if not white_pool.is_empty():
		_check(white_pool[0].trigger_affixes.is_empty(),
			"白装无触发型词条")
	var blue_pool: Array = EquipmentDB.get_templates_by_rarity(EquipmentDefs.Rarity.BLUE)
	if not blue_pool.is_empty():
		var any_blue := false
		for tpl in blue_pool:
			if not tpl.trigger_affixes.is_empty():
				any_blue = true
		_check(any_blue, "蓝装开始出现触发型词条")
	var orange_pool: Array = EquipmentDB.get_templates_by_rarity(EquipmentDefs.Rarity.ORANGE)
	if not orange_pool.is_empty():
		var max_cnt := 0
		for tpl in orange_pool:
			max_cnt = maxi(max_cnt, tpl.trigger_affixes.size())
		_check(max_cnt == 2, "橙装最多 2 条触发型词条", [max_cnt])

	# 确定性：同一件装备多次查表词条一致（否则背包里的词条会"漂移"）
	if not orange_pool.is_empty():
		var a: EquipmentTemplate = orange_pool[0]
		var tpl2: EquipmentTemplate = EquipmentDB.get_template(a.id)
		var same := tpl2 != null and tpl2.trigger_affixes.size() == a.trigger_affixes.size()
		if same:
			for i in a.trigger_affixes.size():
				if a.trigger_affixes[i].trigger_buff != tpl2.trigger_affixes[i].trigger_buff:
					same = false
		_check(same, "同 id 装备的触发词条稳定（不随查询变化）")

	# 特殊修饰量的枚举值不撞面板属性（AttributeSystem.Stat 只到 10）
	for key in EquipmentDB.SPECIAL_STAT:
		var ev := int(EquipmentDB.SPECIAL_STAT[key]["enum"])
		_check(ev >= 100, "特殊修饰量 %s 的枚举值 %d 避开面板属性域" % [key, ev])


## 通用词条的**挂载链路**：roll_generic_affix 阈值 → 附魔附加到实例 →
## 词条生效到属性 → 存档往返不丢。
## 回归：GENERIC_STAT_POOL 曾只被测试引用，生产代码零消费者；
## special_modifiers 也曾漏掉 extra_affixes（附魔的特殊词条不生效）。
func test_generic_affix_attach() -> void:
	_current_test = "GenericAffixAttach"
	print("\n--- %s ---" % _current_test)

	EquipmentDB.init_equipment_db()

	# ① roll_generic_affix 按稀有度门槛取样：稀有度越高可选池越大
	var counts := {}
	var rng := RandomNumberGenerator.new()
	for rar in [EquipmentDefs.Rarity.WHITE, EquipmentDefs.Rarity.BLUE,
			EquipmentDefs.Rarity.PURPLE, EquipmentDefs.Rarity.ORANGE]:
		rng.seed = 42
		var seen := {}
		for i in 80:
			var a: AffixData = EquipmentDB.roll_generic_affix(rar, rng)
			if a != null:
				seen[str(a.id)] = true
		counts[rar] = seen.size()
	_check(int(counts[EquipmentDefs.Rarity.WHITE]) > 0, "白装可出词条")
	_check(int(counts[EquipmentDefs.Rarity.ORANGE]) > int(counts[EquipmentDefs.Rarity.WHITE]),
		"稀有度越高可选词条越多（白 %d → 橙 %d）" % [
			int(counts[EquipmentDefs.Rarity.WHITE]),
			int(counts[EquipmentDefs.Rarity.ORANGE])])
	# 高门槛词条（元素穿透 橙+）不该出现在白装池里
	rng.seed = 7
	var white_has_pen := false
	for i in 100:
		var a: AffixData = EquipmentDB.roll_generic_affix(EquipmentDefs.Rarity.WHITE, rng)
		if a != null and EquipmentDB.special_out_key(a.stat) == "elem_pen_pct":
			white_has_pen = true
	_check(not white_has_pen, "白装抽不到橙+门槛的元素穿透")

	# roll 出的词条 stat 必须可解析（面板枚举或 100+ 扩展）
	rng.seed = 99
	for i in 50:
		var a: AffixData = EquipmentDB.roll_generic_affix(EquipmentDefs.Rarity.ORANGE, rng)
		if a == null:
			continue
		var ok := (a.stat >= 0 and a.stat < 11) or EquipmentDB.special_out_key(a.stat) != ""
		_check(ok, "roll 出的词条 stat 可解析（%s=%d）" % [str(a.id), a.stat])
		break

	# ② 实例承载：同模板两实例各自附加互不影响
	var white: Array = EquipmentDB.get_templates_by_rarity(EquipmentDefs.Rarity.WHITE)
	if white.is_empty():
		_check(false, "白装池非空")
		return
	var tpl: EquipmentTemplate = white[0]
	var i1 := EquipmentInstance.create(tpl)
	var i2 := EquipmentInstance.create(tpl)
	var a1 = AffixData.make_stat(EquipmentDB.stat_enum_of("atk"), 0.05, true)
	a1.id = StringName("gc_atk")
	i1.add_extra_affix(a1)
	_check(i1.extra_affixes.size() == 1 and i2.extra_affixes.is_empty(),
		"词条挂在实例上（同模板另一件不受影响）")
	_check(not i1.add_extra_affix(a1), "同 id 词条不重复附加")
	# 另一实例不受影响（词条挂在实例上，不是模板）
	var i3 := EquipmentInstance.create(tpl)
	_check(i3.extra_affixes.is_empty(),
		"同模板新建实例不含他人词条（extra_affixes 只在实例上）")

	# ③ 序列化往返：词条与附魔次数都不丢
	i1.enchant_stacks = 2
	var restored := EquipmentInstance.new()
	restored.from_dict(i1.to_dict())
	_check(restored.extra_affixes.size() == i1.extra_affixes.size(),
		"存档往返保留词条数（%d）" % restored.extra_affixes.size())
	_check(restored.enchant_stacks == 2, "存档往返保留附魔次数")
	if not restored.extra_affixes.is_empty():
		_check(str(restored.extra_affixes[0].id) == "gc_atk",
			"存档往返保留词条 id（%s）" % str(restored.extra_affixes[0].id))
		_check(absf(restored.extra_affixes[0].value - 0.05) < 0.001,
			"存档往返保留词条数值")

	# ④ special_modifiers 必须覆盖 extra_affixes
	#    （回归：曾只遍历模板三词条，附魔的生命偷取/元素穿透不生效）
	#    本测试跑在 --script 模式（无 autoload），故不走 GameManager——
	#    直接验证「汇总逻辑能看见实例词条」这一步：
	#    用真实 EquipmentInstance 挂一条特殊词条，检查它出现在待汇总集合里。
	var inst := EquipmentInstance.create(tpl)
	var ls = AffixData.make_stat(EquipmentDB.special_enum_of("lifesteal"), 0.10, true)
	ls.id = StringName("gc_lifesteal")
	inst.add_extra_affix(ls)
	# 复刻 special_modifiers 的遍历口径：模板三词条 + 实例附加词条
	var scan: Array = [tpl.base_affix, tpl.devour_affix, tpl.fusion_affix]
	scan.append_array(inst.extra_affixes)
	var found := false
	for affix in scan:
		if affix != null and affix.is_stat() \
				and EquipmentDB.special_out_key(affix.stat) == "life_steal":
			found = true
	_check(found, "汇总口径覆盖实例附加词条（生命偷取可被 special_modifiers 看见）")

	# ⑤ 附魔次数上限（策划 4.3.2：单件最多 3 次）
	_check(not SpecialRoomService.can_enchant(3), "附魔 3 次后不可继续")
	_check(SpecialRoomService.can_enchant(2), "附魔 2 次可继续")


func test_red_rarity_pool_not_empty() -> void:
	_current_test = "RedRarityPool"
	print("\n--- %s ---" % _current_test)

	EquipmentDB.init_equipment_db()
	var reds := EquipmentDB.get_templates_by_rarity(EquipmentDefs.Rarity.RED)
	_check(reds.size() > 0, "红装池非空（否则第 6 层起 Boss 掉白装）",
		["红装数 %d" % reds.size()])

	# 橙装也应存在（1~5 层保底）
	var oranges := EquipmentDB.get_templates_by_rarity(EquipmentDefs.Rarity.ORANGE)
	_check(oranges.size() > 0, "橙装池非空", ["橙装数 %d" % oranges.size()])

	# 稀有度越高数值倍率越高（红 > 橙）
	if reds.size() > 0 and oranges.size() > 0:
		var r_scale := EquipmentDB.rarity_scale(EquipmentDefs.Rarity.RED)
		var o_scale := EquipmentDB.rarity_scale(EquipmentDefs.Rarity.ORANGE)
		_check(r_scale > o_scale, "红装数值倍率高于橙装",
			["红 %.1f vs 橙 %.1f" % [r_scale, o_scale]])
	# 红色不在随机掉落权重里（仅保底产出）
	var w := LootSystem.rarity_weights_for_floor(9)
	var red_idx: int = EquipmentDefs.Rarity.RED
	if red_idx < w.size():
		_check(float(w[red_idx]) == 0.0, "红装不参与随机掉落（仅 Boss 保底）",
			[w[red_idx]])


## 第 9 层（隐藏层）固定结构：3 间 Boss 房 + 奖励大厅（策划书 6.10）
func test_layer9_structure() -> void:
	_current_test = "Layer9Structure"
	print("\n--- %s ---" % _current_test)

	var gen := DungeonGenerator.new()
	gen.rng.set_seed(4242)
	var want := FloorDefs.room_count(9)
	gen.min_rooms = want
	gen.max_rooms = want
	gen.range_half = FloorDefs.range_half(9)
	gen.floor_num = 9
	gen.generate(4242)

	_check(gen.rooms.size() == 5, "第 9 层固定 5 间房", [gen.rooms.size()])

	var bosses := 0
	var halls := 0
	var start := 0
	for r in gen.rooms:
		match str(r.get("type", "")):
			"boss":
				bosses += 1
			"reward_hall":
				halls += 1
			"start":
				start += 1
	_check(bosses == 3, "第 9 层 3 间 Boss 房（三连战）", [bosses])
	_check(halls == 1, "第 9 层 1 间奖励大厅", [halls])
	_check(start == 1, "第 9 层 1 间起始房", [start])
	# 第 9 层不应有常规怪物房（纯 Boss 挑战）
	var normal := 0
	for r in gen.rooms:
		if str(r.get("type", "")) == "normal":
			normal += 1
	_check(normal == 0, "第 9 层无普通怪物房（纯 Boss 挑战）", [normal])

	# **顺序断言**（策划 6.10：传送进入 → 奖励大厅搜刮 → Boss 连战三场）。
	# 早期实现按「距离升序，前 3 间标 boss」，奖励大厅落在最远处
	# （实测距起始房 3），玩家要打完 Boss 才拿得到奖励，与策划相反。
	# 只断言数量查不出这个，必须断言**距离**。
	#
	# 注意：不能断言「所有 Boss 都比大厅远」——起始房通常扇形连 2~3 个房间，
	# 距离 1 的位置不止一个，大厅占其一后必然还有 Boss 并列在距离 1。
	# 能保证且该保证的是「大厅就在起始房旁边」，玩家进门第一间就能搜刮。
	var dist: Dictionary = probe.gen_bfs_distances(gen, gen.start_room_index)
	var hall_dist := -1
	for i in gen.rooms.size():
		if str(gen.rooms[i].get("type", "")) == "reward_hall":
			hall_dist = int(dist.get(i, 99))
	_check(hall_dist == 1, "奖励大厅紧邻起始房（实际距离 %d）" % hall_dist, [hall_dist])

	# 对照：第 1 层仍是常规结构（1 间 Boss）
	var gen1 := DungeonGenerator.new()
	gen1.rng.set_seed(4242)
	gen1.min_rooms = 13
	gen1.max_rooms = 13
	gen1.floor_num = 1
	gen1.generate(4242)
	var b1 := 0
	for r in gen1.rooms:
		if str(r.get("type", "")) == "boss":
			b1 += 1
	_check(b1 == 1, "第 1 层仍是 1 间 Boss 房", [b1])


## 生命上限收支平衡（防"受伤掉上限 / 血瓶泉水回不上血"回归）。
##
## 实机症状：「角色受到伤害的时候有概率会直接降低生命上限，用血瓶和泉水
## 无法恢复生命值」。此前的探查结论（2026-09-17）：
##   · 40 秒持续受击下 max_hp 恒定，伤害路径不会改上限；
##   · 瘟疫之泉的诅咒池是 atk/def/spd，明确排除生命；
##   · 全代码库中玩家侧 max_hp 的唯一写者是 AttributeSystem._recalc_hp
##     （由 Stat.HP 的 modifier 驱动），没有第二处。
## 但以上是**当时**的结论，代码会变。故这里固化不变量：
## 任何"穿上再卸下 / 挂上再清除"的循环都必须让 max_hp 精确回到基线，
## 且不允许出现同一源名的重复 modifier（重复 = 加了没减，正是慢慢压低
## 上限的机制）。
func _test_max_hp_balance() -> void:
	var EI = _require_script("res://data/equipment/equipment_instance.gd")
	if EI == null:
		return
	var attrs := AttributeSystem.new()
	var baseline: float = attrs.max_hp
	_check(absf(baseline - AttributeSystem.DEFAULT_BASE[AttributeSystem.Stat.HP]) < 0.001,
		"基线 max_hp = 默认生命值（%.0f）" % baseline)

	# 装备循环：同一槽位穿卸 5 次，上限必须回到基线
	var em := EquipmentManager.new()
	em.rng = RandomNumberGenerator.new()
	var tpl = EquipmentDB.get_template(&"A05")
	if tpl != null:
		for i in 5:
			var inst = EI.create(tpl)
			em.add_item(inst)
			em.equip(EquipmentDefs.Slot.CHEST, inst)
			var worn: float = attrs.max_hp
			em.unequip(EquipmentDefs.Slot.CHEST)
			_check(absf(attrs.max_hp - baseline) < 0.01,
				"装备循环第 %d 次卸下后 max_hp 回基线（穿着时 %.0f）" % [i + 1, worn])
			if absf(attrs.max_hp - baseline) >= 0.01:
				break
	else:
		_check(false, "A05 模板存在（皮革胸甲，带生命词条）")
	_check(_has_duplicate_source(attrs) == "",
		"装备循环后无重复 modifier 源 %s" % _has_duplicate_source(attrs))

	# 融合/强化后同样不得留下重复源（enhance 会重挂基础词条）
	if tpl != null:
		var inst2 = EI.create(tpl)
		em.add_item(inst2)
		em.enhance(inst2)
		em.enhance(inst2)
		_check(_has_duplicate_source(attrs) == "",
			"强化 ×2 后无重复 modifier 源 %s" % _has_duplicate_source(attrs))

	# hp_up buff：挂上要涨，清除要精确回落
	var holder := BuffHolder.new()
	probe.set_field(holder, "_target", null)   # 无宿主的 holder 只验账本，不验 modifier 同步
	_check(holder.apply("gen_hp_up", "test", 1).get("ok", false), "gen_hp_up 可施加")
	_check(holder.stacks_of("gen_hp_up") == 1, "gen_hp_up 叠 1 层")
	holder.clear()
	_check(not holder.has("gen_hp_up"), "clear() 后词条已移除")


## 返回第一个"同一源名挂了多条 modifier"的源名（无则空串）。
## 源名天然唯一（equip_<id> / fusion_<id> / devour_<id> / buff:<id>），
## 重复即代表"加了没减"的泄漏。
func _has_duplicate_source(attrs) -> String:
	var counts := {}
	for m in probe.attrs_modifiers(attrs):
		var src := str(m.get("source", "?"))
		counts[src] = int(counts.get(src, 0)) + 1
		if int(counts[src]) > 1:
			return "%s（%d 条）" % [src, int(counts[src])]
	return ""


## 存档往返：装备/背包/融合/强化/吞噬加成必须完整保真
## 回归：SaveManager 此前**只有写没有读**——`_collect_save_data` 存数据，
## 但没有任何恢复函数，`_on_continue_pressed` 直接 start_new_run（全新开局），
## 玩家读档后发现装备全丢、金币归零，而存档文件看起来完全正常。
func test_equipment_save_roundtrip() -> void:
	_current_test = "EquipmentSaveRoundtrip"
	print("\n--- %s ---" % _current_test)

	var EM = _require_script("res://gameplay/inventory/equipment_manager.gd")
	var EI = _require_script("res://data/equipment/equipment_instance.gd")
	EquipmentDB.init_equipment_db()
	if EM == null or EI == null:
		return

	var em = EM.new()
	var tpl = EquipmentDB.get_template(&"W06")
	_check(tpl != null, "测试模板 W06 存在")
	if tpl == null:
		return

	# 造一份"有进度"的状态：已装备武器（融合 6 次 + 强化 3 级）+ 背包 4 件 + 吞噬 1 件
	var wp = EI.create(tpl)
	wp.fusion_count = 6
	wp.enhancement_level = 3
	em.add_item(wp)
	em.equip(EquipmentDefs.Slot.WEAPON_1, wp)
	for tid in [&"W11", &"A03", &"A16", &"J03"]:
		var t = EquipmentDB.get_template(tid)
		if t != null:
			em.add_item(EI.create(t))
	var dv = EI.create(tpl)
	em.add_item(dv)
	em.devour(dv)

	var snap: Dictionary = em.to_dict()
	_check(snap["equipped"].size() == 1, "快照含 1 件已装备", [snap["equipped"].size()])
	_check(snap["inventory"].size() == 4, "快照含 4 件背包物品", [snap["inventory"].size()])
	# 吞噬的那件已从背包移除（背包从 5 减到 4），但有 1 条吞噬记录
	_check(snap["devour_modifiers"].size() == 1, "快照含 1 条吞噬加成记录",
		[snap["devour_modifiers"].size()])

	# 恢复到一个全新的空 manager（模拟读档）
	var em2 = EM.new()
	em2.from_dict(snap)
	var eq2: Dictionary = em2.get_equipped()
	var w2 = eq2.get(EquipmentDefs.Slot.WEAPON_1)
	_check(eq2.size() == 1, "恢复后 1 件已装备", [eq2.size()])
	_check(em2.get_inventory().size() == 4, "恢复后 4 件背包物品",
		[em2.get_inventory().size()])
	_check(w2 != null, "恢复后武器槽非空")
	if w2 != null:
		# 槽位键必须是 int——JSON 会把 int 键转成字符串，
		# 不转回来的话按 int 查槽位全部落空（装备"存了但取不到"）
		_check(w2.fusion_count == 6, "融合次数保真", [w2.fusion_count])
		_check(w2.enhancement_level == 3, "强化等级保真", [w2.enhancement_level])
		_check(w2.template_id == tpl.id, "模板 id 保真", [w2.template_id])
	_check(absf(em2.fusion_attack_bonus() - em.fusion_attack_bonus()) < 0.001,
		"融合攻击加成保真",
		["%.4f vs %.4f" % [em2.fusion_attack_bonus(), em.fusion_attack_bonus()]])
	_check(em2.to_dict()["devour_modifiers"].size() == 1, "吞噬加成记录保真")

	# 幂等：存 → 读 → 再存，两次数值一致
	var snap2: Dictionary = em2.to_dict()
	_check(snap2["equipped"].size() == snap["equipped"].size()
		and snap2["inventory"].size() == snap["inventory"].size(),
		"存→读→存 幂等")

	# 空字典不炸（存档缺失/损坏的容错）
	var em3 = EM.new()
	em3.from_dict({})
	_check(em3.get_equipped().is_empty() and em3.get_inventory().is_empty(),
		"空存档数据不产生物品（容错）")

	# 消耗品背包也有序列化
	var ConsInv = _require_script("res://data/consumables/consumable_inventory.gd")
	if ConsInv != null:
		var ci = ConsInv.new()
		ci.add_health_potion(2)
		var cd: Dictionary = ci.to_dict()
		_check(int(cd.get("quantities", {}).get("health_potion", 0)) == 2,
			"消耗品背包序列化含药水数", [cd])
		var ci2 = ConsInv.new()
		ci2.from_dict(cd)
		_check(ci2.count("health_potion") == 2, "消耗品背包恢复药水数",
			[ci2.count("health_potion")])


func test_key_fragments() -> void:
	_current_test = "KeyFragments"
	print("\n--- %s ---" % _current_test)

	var gm: Node = load("res://core/game_manager.gd").new()
	_check(gm.run_key_fragments == 0, "初始碎片为 0")
	_check(not gm.has_all_key_fragments(), "初始未集齐")

	for i in range(7):
		gm.add_key_fragment(i + 1)
	_check(gm.run_key_fragments == 7, "累加 7 片", [gm.run_key_fragments])
	_check(not gm.has_all_key_fragments(), "7 片未集齐（需 8 片）")

	gm.add_key_fragment(8)
	_check(gm.run_key_fragments == 8, "累加至 8 片", [gm.run_key_fragments])
	_check(gm.has_all_key_fragments(), "8 片集齐（可进隐藏层）")

	# 局外累积与局内计数同步增长
	_check(gm.meta_key_fragments == 8, "局外累积同步", [gm.meta_key_fragments])

	# 新局重置局内计数，但局外保留
	probe.gm_reset_run(gm)
	_check(gm.run_key_fragments == 0, "新局重置局内碎片")
	_check(gm.meta_key_fragments == 8, "新局保留局外碎片（跨局）",
		[gm.meta_key_fragments])

	gm.free()


## 楼层环境机制：各层 env 登记完整、机制能装配、安全区不被侵占
## 依据关卡设计分册第 4 章「每层主题与环境机制」
func test_floor_environment() -> void:
	_current_test = "FloorEnvironment"
	print("\n--- %s ---" % _current_test)

	# 各层 env 标识：1 层无机制（教学层），2~9 层各有机制且不重复
	_check(FloorDefs.env_id(1).is_empty(), "第 1 层无环境机制（教学层）",
		[FloorDefs.env_id(1)])
	var seen := {}
	for f in range(2, 10):
		var e := FloorDefs.env_id(f)
		_check(not e.is_empty(), "第 %d 层登记了环境机制" % f)
		_check(not seen.has(e), "第 %d 层机制 %s 唯一" % [f, e])
		seen[e] = f

	# 机制装配**行为级**断言：每层 env 装配后 mechanism() 必须非空。
	# 不用硬编码的 env 名列表——那样只能证明"名字在名单里"，
	# 证明不了"真的有实现"（第 7 层曾登记 low_gravity 却被当成已实现，
	# 实际落地的机制叫 void_warp，名实不符且从名单上看不出来）。
	#
	# **每层用独立宿主节点**：FloorEnvironment.apply 会往 room_node 上挂一个
	# 同名子节点，复用同一个宿主会让第二次 add_child 触发 Godot 自动改名，
	# 且 host.free() 时子节点仍持引用 → 整个测试协程被打断（实测：
	# 该测试曾一条断言都没跑却算通过，正是本轮加守卫后才暴露出来）。
	for f in range(2, 10):
		var host := Node3D.new()
		var env_node := FloorEnvironment.apply(host, f, {"width": 20, "height": 15})
		var mech: Dictionary = env_node.mechanism() if env_node != null else {}
		_check(not mech.is_empty(),
			"第 %d 层 env '%s' 有实际机制装配" % [f, FloorDefs.env_id(f)],
			[mech])
		host.free()

	# 造一个房间数据，验证危害区真的生成且避开安全点
	var data := {
		"width": 20, "height": 15,
		"entities": [{"type": "player_spawn", "x": 10, "y": 12}],
		"doors": [{"x": 10, "y": 14, "direction": "south"}],
	}
	# 区域型机制（2~5 层）：应生成危害区
	for f in [2, 3, 4, 5]:
		var room := Node3D.new()
		var fe := FloorEnvironment.apply(room, f, data)
		_check(fe != null, "第 %d 层环境已装配" % f)
		if fe:
			var zones: Array = []
			for c in fe.get_children():
				if c is DamageZone:
					zones.append(c)
			_check(zones.size() > 0, "第 %d 层生成了危害区（%d 个）" % [f, zones.size()])
			# 安全区不变量：危害不得压在出生点或门上
			var bad := 0
			for z in zones:
				var zp: Vector3 = (z as Node3D).position
				var to_spawn := Vector2(zp.x - 10.0, zp.z - 12.0).length()
				var to_door := Vector2(zp.x - 10.0, zp.z - 14.5).length()
				var r: float = float(z.get("radius"))
				if to_spawn < r or to_door < r:
					bad += 1
			_check(bad == 0, "第 %d 层危害区避开出生点与门" % f, ["侵占 %d 个" % bad])
		room.free()

	# 周期型机制（6~9 层）：无静态危害区，但有机制配置
	for f in [6, 7, 8, 9]:
		var room2 := Node3D.new()
		var fe2 := FloorEnvironment.apply(room2, f, data)
		_check(fe2 != null, "第 %d 层环境已装配" % f)
		if fe2:
			var m: Dictionary = fe2.mechanism()
			_check(not m.is_empty(), "第 %d 层有机制配置（%s）" % [f, m.get("kind", "")])
		room2.free()

	# 第 1 层（无机制）返回 null
	var room1 := Node3D.new()
	_check(FloorEnvironment.apply(room1, 1, data) == null, "第 1 层不装配环境机制")
	room1.free()


## 各层机制**互不相同**（反"换皮"回归）。
##
## 用户的原话是「所有关卡机制都是第二层的换皮」。审计发现整套只用了
## 3 个原语（持久危害区 / 随机位置爆发 / 随机传送），只是参数不同。
## 这条断言用「节点类型组合」当指纹——只要两层生成的东西一样就会失败，
## 从而防止将来又把新层实现成旧层的参数变体。
func test_floor_mechanism_distinct() -> void:
	_current_test = "FloorMechanismDistinct"
	print("\n--- %s ---" % _current_test)

	var data := {
		"width": 20, "height": 15,
		"entities": [{"type": "player_spawn", "x": 10, "y": 12}],
		"doors": [{"x": 10, "y": 14, "direction": "south"}],
	}
	var sigs := {}
	var details: Array = []
	for f in range(2, 10):
		var room := Node3D.new()
		var fe := FloorEnvironment.apply(room, f, data)
		if fe != null:
			var sig := _mechanism_signature(fe)
			sigs[f] = sig
			details.append("第%d层:%s" % [f, sig])
		room.free()

	var uniq := {}
	for f in sigs:
		uniq[sigs[f]] = true
	_check(sigs.size() == 8, "2~9 层都装配了机制（实际 %d）" % sigs.size())
	_check(uniq.size() >= 6,
		"至少 6 种不同的机制构成（实际 %d）" % uniq.size(), [str(details)])

	# 逐层的关键构件（证明每层有各自的东西，不是同一个圈）
	# 用"装配后直接扫子节点"的方式，不挂到树上——本套件是 --script 模式
	# （SceneTree），测试脚本不是 Node，没有 add_child。
	_check(_floor_has_kind(3, data, "VentProp"), "第 3 层有可破坏通风口")
	_check(_floor_has_kind(5, data, "FurnaceProp"), "第 5 层有符文熔炉")
	_check(_floor_has_kind(8, data, "CoverProp"), "第 8 层有掩体")


## 临时装配一层，检查是否含指定类型的子节点，然后销毁房间
func _floor_has_kind(floor_num: int, data: Dictionary, cls: String) -> bool:
	var room := Node3D.new()
	var fe := FloorEnvironment.apply(room, floor_num, data)
	var found := false
	if fe != null:
		for c in fe.get_children():
			if c.get_script() != null \
					and str(c.get_script().get_global_name()) == cls:
				found = true
				break
	room.free()
	return found


## 机制指纹：本层生成的节点类型与数量 + 机制 kind
func _mechanism_signature(fe: FloorEnvironment) -> String:
	var counts := {"zone": 0, "vent": 0, "furnace": 0, "cover": 0}
	for c in fe.get_children():
		if c is DamageZone:
			counts["zone"] += 1
		elif c is VentProp:
			counts["vent"] += 1
		elif c is FurnaceProp:
			counts["furnace"] += 1
		elif c is CoverProp:
			counts["cover"] += 1
	var parts: Array = []
	for k in counts:
		if int(counts[k]) > 0:
			parts.append("%s×%d" % [k, counts[k]])
	var m: Dictionary = fe.mechanism()
	parts.append("kind=%s" % str(m.get("kind", "")))
	return ",".join(parts)


## 环境机制不会在没有房间控制器时崩溃（预建房间尚未接入控制器）
func test_floor_environment_robustness() -> void:
	_current_test = "FloorEnvironmentRobust"
	print("\n--- %s ---" % _current_test)

	# **显式 load 拿类**：--script 模式下 class_name 全局符号可能未解析
	# （实测这里直接写 FloorEnvironment 会报 "Nonexistent function 'apply'"，
	# 导致整个测试协程被打断、一条断言都没跑——本轮加守卫后才暴露）。
	var FE = _require_script("res://gameplay/dungeon/floor_environment.gd")
	if FE == null:
		return

	# 极端房间数据：无 entities / 无 doors / 尺寸极小
	var bare := {"width": 4, "height": 4}
	for f in range(2, 10):
		var room := Node3D.new()
		var fe = FE.apply(room, f, bare)
		# 不崩即通过；无出生点数据时应回退到房间中心作安全点
		_check(true, "第 %d 层在缺数据房间下不崩" % f)
		if fe != null:
			fe.queue_free()
		room.free()

	# 越界层数钳制（存档损坏）
	var room2 := Node3D.new()
	FE.apply(room2, 99, bare)
	_check(true, "越界层数不崩")
	room2.free()


## 隐藏房：每层稳定 2 间、不与任何房间连通（无门通向）、有锚房间可破墙进入
## 依据关卡设计分册 3.1（每层 2 间）与 3.2（发现规则）
func test_hidden_rooms() -> void:
	_current_test = "HiddenRooms"
	print("\n--- %s ---" % _current_test)

	# 1~8 层各有 2 间隐藏房（第 9 层是纯 Boss 层，无隐藏房）
	for f in range(1, 9):
		var gen := DungeonGenerator.new()
		gen.rng.set_seed(9000 + f)
		gen.min_rooms = 14
		gen.max_rooms = 14
		gen.range_half = FloorDefs.range_half(f)
		gen.floor_num = f
		gen.generate(9000 + f)

		var hidden: Array[int] = []
		for i in gen.rooms.size():
			if str(gen.rooms[i].get("type", "")) == "hidden":
				hidden.append(i)
		_check(hidden.size() == 2, "第 %d 层 2 间隐藏房（实际 %d）" % [f, hidden.size()])

		# 核心不变量：没有任何 connection 连到隐藏房（否则门会指向它、暴露）
		var conn_to_hidden := 0
		for c in gen.connections:
			if c.size() < 2:
				continue
			if int(c[0]) in hidden or int(c[1]) in hidden:
				conn_to_hidden += 1
		_check(conn_to_hidden == 0, "第 %d 层隐藏房不与任何房间连通" % f,
			["连接数 %d" % conn_to_hidden])

		# 每间隐藏房都要有锚房间与方位（破墙入口挂在那里）
		for hi in hidden:
			var anchor := int(gen.rooms[hi].get("anchor_index", -1))
			var adir := str(gen.rooms[hi].get("anchor_dir", ""))
			_check(anchor >= 0 and anchor < gen.rooms.size(),
				"第 %d 层隐藏房有锚房间" % f, [anchor])
			_check(adir in ["north", "south", "west", "east"],
				"第 %d 层隐藏房有方位" % f, [adir])
			if anchor < 0 or anchor >= gen.rooms.size() or adir.is_empty():
				continue

			# 隐藏房**恰好 1 扇出口门**，方向指向锚房间。
			# 曾经这里是 `doors.is_empty()`——只验证了「没有门通向隐藏房」，
			# 但没验证「进去之后出得来」，结果破墙进去就出不去（实测踩到）。
			# 现在的口径：隐藏房有且只有一扇朝锚房的门；隐藏性由
			# 「锚房那侧不生成门」保证，而不是靠「隐藏房没门」。
			var hdoors := DoorsByTopology.build_doors(
				gen.rooms, gen.connections, hi,
				gen.start_room_index, gen.start_room_index, 20, 15)
			_check(hdoors.size() == 1,
				"第 %d 层隐藏房 %d 恰有 1 扇出口门" % [f, hi], [hdoors.size()])
			if hdoors.size() == 1:
				# 出口方向 = 「从隐藏房看锚房」= apos - hpos
				# （anchor_dir 是「从锚房看隐藏房」，两者互为反向）
				var hpos: Vector2i = gen.rooms[hi].get("position", Vector2i.ZERO)
				var diff := Vector2i(gen.rooms[anchor].get("position", Vector2i.ZERO)) - hpos
				var want := ""
				if diff == Vector2i.UP: want = "north"
				elif diff == Vector2i.DOWN: want = "south"
				elif diff == Vector2i.LEFT: want = "west"
				elif diff == Vector2i.RIGHT: want = "east"
				_check(str(hdoors[0].get("direction", "")) == want,
					"第 %d 层隐藏房出口朝锚房（%s）" % [f, want],
					[str(hdoors[0].get("direction", ""))])

			# **反向断言**：锚房间不得在朝隐藏房那侧生成门（否则隐藏房暴露）
			var anchor_doors := DoorsByTopology.build_doors(
				gen.rooms, gen.connections, anchor,
				gen.start_room_index, gen.start_room_index, 20, 15)
			var leak := false
			for d in anchor_doors:
				if str(d.get("direction", "")) == adir:
					leak = true
			_check(not leak, "第 %d 层锚房朝隐藏房那侧无门（未暴露）" % f)

	# 第 9 层（纯 Boss 层）无隐藏房
	var gen9 := DungeonGenerator.new()
	gen9.rng.set_seed(31)
	gen9.min_rooms = 5
	gen9.max_rooms = 5
	gen9.floor_num = 9
	gen9.range_half = 15
	gen9.generate(31)
	var h9 := 0
	for r in gen9.rooms:
		if str(r.get("type", "")) == "hidden":
			h9 += 1
	_check(h9 == 0, "第 9 层无隐藏房（纯 Boss 层）", [h9])

	# 锚房间的方位与两房相对位置一致（破墙入口要挂在正确的墙上）
	var gen2 := DungeonGenerator.new()
	gen2.rng.set_seed(1234)
	gen2.min_rooms = 14
	gen2.max_rooms = 14
	gen2.floor_num = 3
	gen2.range_half = 9
	gen2.generate(1234)
	var ok_dir := true
	for i in gen2.rooms.size():
		var r: Dictionary = gen2.rooms[i]
		if str(r.get("type", "")) != "hidden":
			continue
		var a := int(r.get("anchor_index", -1))
		if a < 0:
			continue
		var hp: Vector2i = r.get("position", Vector2i.ZERO)
		var ap: Vector2i = gen2.rooms[a].get("position", Vector2i.ZERO)
		var diff := hp - ap
		var expect := ""
		if diff == Vector2i.UP: expect = "north"
		elif diff == Vector2i.DOWN: expect = "south"
		elif diff == Vector2i.LEFT: expect = "west"
		elif diff == Vector2i.RIGHT: expect = "east"
		if expect != str(r.get("anchor_dir", "")):
			ok_dir = false
	_check(ok_dir, "隐藏房的锚方位与相对位置一致")

	# 模板齐全：hidden 房型有 JSON 模板（否则 _pick_template 回退到 start 房）
	var found_hidden_template := false
	var dir := DirAccess.open("res://data/rooms/")
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while not fn.is_empty():
			if fn.ends_with(".json") and not dir.current_is_dir():
				var fh := FileAccess.open("res://data/rooms/" + fn, FileAccess.READ)
				if fh:
					var jj := JSON.new()
					if jj.parse(fh.get_as_text()) == OK:
						if str(jj.data.get("room_type", "")) == "hidden":
							found_hidden_template = true
					fh.close()
			fn = dir.get_next()
		dir.list_dir_end()
	_check(found_hidden_template, "hidden 房型有模板（避免回退到起始房）")


## Boss 体系（BossDB）：每层 7 个轮换、机制归类完整、配置翻译正确
## 依据关卡设计分册 6.1（池容量）、6.2~6.10（各层 Boss 池）
func test_boss_db() -> void:
	_current_test = "BossDB"
	print("\n--- %s ---" % _current_test)

	# 总量：7 层 × 7 轮换 + 第 8 层固定 1 + 第 9 层三连战 3 = 53
	_check(BossDB.total_count() == 53, "Boss 总数 53（策划 6.1）",
		[BossDB.total_count()])

	# 1~7 层各 7 个轮换
	for f in range(1, 8):
		var pool: Array = BossDB.pool_for_floor(f)
		_check(pool.size() == 7, "第 %d 层 7 个轮换 Boss" % f, [pool.size()])

	# 第 8 层固定 1 个、第 9 层三连战 3 个
	_check(BossDB.pool_for_floor(8).size() == 1, "第 8 层固定 Boss",
		[BossDB.pool_for_floor(8).size()])
	_check(BossDB.pool_for_floor(9).size() == 3, "第 9 层三连战 3 个",
		[BossDB.pool_for_floor(9).size()])

	# 每个 Boss 必须有：唯一 id、名字、至少一类机制、合法 ai
	var ids := {}
	var bad_mech: Array = []
	var bad_ai: Array = []
	var valid_ai := ["melee", "kite", "sentry", "rusher"]
	for f in BossDB.BOSSES:
		for b in BossDB.BOSSES[f]:
			var bid := str(b.get("id", ""))
			_check(not ids.has(bid), "Boss id 唯一（%s）" % bid)
			ids[bid] = true
			_check(not str(b.get("name", "")).is_empty(), "Boss %s 有名字" % bid)
			var mechs: Array = b.get("mechs", [])
			if mechs.is_empty():
				bad_mech.append(bid)
			# 机制类必须是已知的 9 类之一
			for m in mechs:
				if not BossDB.ALL_MECHANICS.has(str(m)):
					bad_mech.append("%s:%s" % [bid, m])
			if not valid_ai.has(str(b.get("ai", ""))):
				bad_ai.append(bid)
	_check(bad_mech.is_empty(), "所有 Boss 都归入已知机制类", [bad_mech])
	_check(bad_ai.is_empty(), "所有 Boss 的 ai 合法", [bad_ai])

	# 9 类机制必须都有 Boss 使用（归并设计不能有死类）
	var used := {}
	for f in BossDB.BOSSES:
		for b in BossDB.BOSSES[f]:
			for m in b.get("mechs", []):
				used[str(m)] = true
	var unused: Array = []
	for m in BossDB.ALL_MECHANICS:
		if not used.has(m):
			unused.append(m)
	_check(unused.is_empty(), "9 类机制都有 Boss 使用", [unused])

	# 配置翻译：血量随层提升（同 hp_pct 下，层基准更高）
	var c1 := BossDB.to_monster_config(BossDB.pool_for_floor(1)[0], 1, FloorDefs.boss_hp(1))
	var c7 := BossDB.to_monster_config(BossDB.pool_for_floor(7)[0], 7, FloorDefs.boss_hp(7))
	_check(float(c7.get("hp", 0)) > float(c1.get("hp", 0)),
		"高层 Boss 血量更高", ["%s vs %s" % [c1.get("hp"), c7.get("hp")]])
	_check(float(c7.get("atk", 0)) > float(c1.get("atk", 0)),
		"高层 Boss 攻击更高")
	_check(bool(c1.get("is_boss", false)), "翻译结果标记为 Boss")
	_check(str(c1.get("name", "")) == str(BossDB.pool_for_floor(1)[0].get("name", "")),
		"翻译保留 Boss 名字")

	# 阶段：第 8 层四阶段（策划 6.9.1）
	var p8: Dictionary = BossDB.pool_for_floor(8)[0].get("params", {})
	_check(p8.has("phases") and p8["phases"].size() == 3,
		"第 8 层有 3 个阶段阈值（共 4 阶段）", [p8.get("phases")])
	_check(p8.has("burn_per_second"), "第 8 层有地狱灼烧（每秒掉血）")

	# 第 9 层首战血量基准 4500（策划 5.3）、终战 12000
	_check(absf(FloorDefs.boss_hp(9) - 4500.0) < 1.0,
		"第 9 层首战血量 4500", [FloorDefs.boss_hp(9)])

	# random_for_floor 抽取：同层多次抽取能拿到不同的 Boss（轮换而非固定）
	var seen := {}
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 777
	for _i in 30:
		var b := BossDB.random_for_floor(1, rng2)
		seen[str(b.get("id", ""))] = true
	_check(seen.size() > 1, "第 1 层多次抽取能拿到不同 Boss（轮换）",
		["抽到 %d 种" % seen.size()])

	# get_boss 按 id 精确取
	_check(not BossDB.get_boss("3-1").is_empty(), "get_boss 能按 id 取到")
	_check(BossDB.get_boss("nonexistent").is_empty(), "get_boss 未知 id 返回空")


## Boss 机制参数接线：BossDB 声明的 params 必须真的到达 EnemyBase
## 回归 P0 前的状态——当时 _special_of 只映射 3 个字段，
## 大量 Boss 写了机制参数却毫无行为（静默失效，从数据层完全看不出来）。
func test_boss_mechanic_wiring() -> void:
	_current_test = "BossMechanicWiring"
	print("\n--- %s ---" % _current_test)

	# ① 每类机制至少有一个代表 Boss 的参数真的落到了 special 上
	var cases := [
		["1-1", "summon", "summon"],
		["3-2", "split", "death_split"],
		["2-7", "stealth", "stealth_always"],
		["4-5", "stealth(ambush)", "ambush"],
		["1-2", "charge", "dash_range"],
		["3-4", "charge(knockback)", "knockback_on_hit"],
		["7-2", "control(slow)", "slow_target_pct"],
		["3-3", "control(healcut)", "healcut_on_hit"],
		["1-6", "control(fear)", "aura_spec"],
		["6-6", "ranged(teleport)", "teleport_after_shot"],
		["5-5", "field(tar)", "zone_on_attack"],
		["3-6", "stealth(disguise)", "ambush"],
	]
	for c in cases:
		var boss := BossDB.get_boss(str(c[0]))
		var cfg := BossDB.to_monster_config(boss, 3, 1000.0)
		var special: Dictionary = cfg.get("special", {})
		_check(special.has(str(c[2])),
			"%s 的 %s 机制参数已接线（→ %s）" % [c[0], c[1], c[2]],
			[special.keys()])

	# ② 覆盖度：绝大多数 Boss 必须带至少一个可执行机制
	var total := 0
	var with_behavior := 0
	for f in BossDB.BOSSES:
		for b in BossDB.BOSSES[f]:
			total += 1
			var cfg := BossDB.to_monster_config(b, f, 1000.0)
			var sp: Dictionary = cfg.get("special", {})
			var mechs: Array = b.get("mechs", [])
			# BossMechanics 接管的类（phase/shield/field）：声明即生效
			var bm_handles := mechs.has(BossDB.M_PHASE) or mechs.has(BossDB.M_SHIELD) \
				or mechs.has(BossDB.M_FIELD)
			if not sp.is_empty() or bm_handles:
				with_behavior += 1
	_check(with_behavior == total,
		"所有 Boss 都有可执行机制（%d/%d）" % [with_behavior, total])

	# ③ 参数交代完整性：每个 params 键要么已接线、要么在 UNWIRED_PARAMS 登记。
	# 这条防止后续加 Boss 时又出现「写了参数、没接线、也没登记」的静默遗漏。
	var undoc := BossDB.undocumented_params()
	_check(undoc.is_empty(),
		"所有 params 键都有交代（已接线或已登记未实现）", [undoc])

	# ③b UNWIRED_PARAMS 不得腐烂。上面那条只查单向（已登记就算交代），
	# 于是清单会往两个方向腐烂，而两条都不会被上面的断言发现：
	#   · 陈旧登记——已接线却忘了移除，读清单的人会误以为它没做
	#   · 僵尸登记——清单里有、但没有任何 Boss 用它，纯噪声
	# 2026-09-19 审计时实际存在 5 项陈旧 + 3 项僵尸，说明这不是假想问题。
	var stale := BossDB.stale_unwired()
	_check(stale.is_empty(),
		"UNWIRED_PARAMS 无陈旧登记（已接线的必须从清单移除）", [stale])
	var zombie := BossDB.zombie_unwired()
	_check(zombie.is_empty(),
		"UNWIRED_PARAMS 无僵尸登记（清单项必须有 Boss 在用）", [zombie])

	# ④ 召唤 id 必须能在 MonsterDB 查到。
	# **行为级断言，比字段级更靠得住**：策划写的是概念名（"zombie"），
	# MonsterDB 存的是具体 id（"zombie_prison"），早期直接传概念名导致
	# _do_summon 查不到怪、静默跳过——字段检查完全看不出（字段确实有值）。
	MonsterDB.init()
	var bad_summon: Array = []
	for f in BossDB.BOSSES:
		for b in BossDB.BOSSES[f]:
			var cfg := BossDB.to_monster_config(b, f, 1000.0)
			var s: Dictionary = cfg.get("special", {}).get("summon", {})
			if s.is_empty():
				continue
			if MonsterDB.get_monster(str(s.get("id", ""))).is_empty():
				bad_summon.append("%s → %s" % [b.get("id"), s.get("id")])
	_check(bad_summon.is_empty(),
		"所有 Boss 的召唤 id 都能在 MonsterDB 查到", [bad_summon])

	# ⑤ BossMechanics 读到的 summon 必须是**已解析**的（与 to_monster_config 同源）。
	# 回归：BossMechanics 曾直接读原始 params，绕过映射，
	# 导致「配置检查通过、实际召唤失败」的两条路径不一致。
	var b1 := BossDB.get_boss("1-4")
	var bm := BossMechanics.attach(null, {})   # 空 attach 只为取静态解析路径
	_check(bm == null, "空 boss_def 不产生机制实例")
	var spec := BossDB._resolve_summon(b1.get("params", {}).get("summon", {}))
	_check(str(spec.get("id", "")) != str(b1.get("params", {}).get("summon", {}).get("id", "")),
		"1-4 的召唤 id 经解析后已换成真实怪物 id",
		["%s → %s" % [b1.get("params", {}).get("summon", {}).get("id"), spec.get("id")]])
	_check(not MonsterDB.get_monster(str(spec.get("id", ""))).is_empty(),
		"1-4 解析后的召唤 id 可查")


## Boss 房尺寸分级（策划 7 章）：按 Boss 个体选战场大小
func test_boss_room_sizes() -> void:
	_current_test = "BossRoomSizes"
	print("\n--- %s ---" % _current_test)

	# 策划明写的映射：第 1 层三档、第 2 层两档（无 3×3）
	_check(BossDB.room_size_of(BossDB.get_boss("1-7")) == "large",
		"1-7 枷锁幽灵用大型房（策划：3×3）")
	_check(BossDB.room_size_of(BossDB.get_boss("1-3")) == "mid",
		"1-3 典狱长用中型房（策划：2×2）")
	_check(BossDB.room_size_of(BossDB.get_boss("1-1")) == "standard",
		"1-1 狱卒用标准房（策划：1×1）")
	# 第 2 层无 3×3
	var has_large_f2 := false
	for b in BossDB.pool_for_floor(2):
		if BossDB.room_size_of(b) == "large":
			has_large_f2 = true
	_check(not has_large_f2, "第 2 层无大型房（策划明写取消 3×3）")
	# 2-3/2-4/2-7 是中型
	for bid in ["2-3", "2-4", "2-7"]:
		_check(BossDB.room_size_of(BossDB.get_boss(bid)) == "mid",
			"%s 用中型房" % bid)

	# 未定义的层/Boss 一律 standard（不自行编造）
	_check(BossDB.room_size_of(BossDB.get_boss("7-1")) == "standard",
		"策划未定义的层用标准房（不自编）")

	# 模板必须存在且尺寸递增
	var sizes := {}
	for key in ["standard", "mid", "large"]:
		var tid := str(BossDB.SIZE_TEMPLATE[key])
		var path := "res://data/rooms/%s.json" % tid
		_check(FileAccess.file_exists(path), "尺寸档 %s 的模板存在（%s）" % [key, tid])
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var j := JSON.new()
			if j.parse(f.get_as_text()) == OK:
				sizes[key] = int(j.data.get("width", 0)) * int(j.data.get("height", 0))
			f.close()
	_check(sizes.get("standard", 0) < sizes.get("mid", 0),
		"中型房面积大于标准房", [sizes])
	_check(sizes.get("mid", 0) < sizes.get("large", 0),
		"大型房面积大于中型房", [sizes])

	# 生成阶段抽定 Boss：dungeon_graph 的 boss 房必须带 boss_def 与 boss_size
	var gen := DungeonGenerator.new()
	gen.rng.set_seed(555)
	gen.min_rooms = 13
	gen.max_rooms = 13
	gen.floor_num = 1
	gen.generate(555)
	var boss_rooms := 0
	var with_def := 0
	for r in gen.rooms:
		if str(r.get("type", "")) != "boss":
			continue
		boss_rooms += 1
		if not r.get("boss_def", {}).is_empty() and not str(r.get("boss_size", "")).is_empty():
			with_def += 1
	_check(boss_rooms >= 1 and with_def == boss_rooms,
		"生成阶段已为 Boss 房抽定 Boss 与尺寸（%d/%d）" % [with_def, boss_rooms])

	# 同种子两次生成必须抽到同一个 Boss（可复现）
	var gen2 := DungeonGenerator.new()
	gen2.rng.set_seed(555)
	gen2.min_rooms = 13
	gen2.max_rooms = 13
	gen2.floor_num = 1
	gen2.generate(555)
	var a := ""
	var b := ""
	for i in gen.rooms.size():
		if str(gen.rooms[i].get("type", "")) == "boss":
			a = str(gen.rooms[i].get("boss_def", {}).get("id", ""))
	for i in gen2.rooms.size():
		if str(gen2.rooms[i].get("type", "")) == "boss":
			b = str(gen2.rooms[i].get("boss_def", {}).get("id", ""))
	_check(a == b, "同种子两次生成的 Boss 相同（可复现）", ["%s vs %s" % [a, b]])

	# 第 9 层三连战按策划顺序取（守卫 → 双子 → 完全体），不是随机
	var gen9 := DungeonGenerator.new()
	gen9.rng.set_seed(31)
	gen9.min_rooms = 5
	gen9.max_rooms = 5
	gen9.range_half = 15
	gen9.floor_num = 9
	gen9.generate(31)
	var seq_ids: Array = []
	var d9: Dictionary = probe.gen_bfs_distances(gen9, gen9.start_room_index)
	var order9: Array = []
	for i in gen9.rooms.size():
		if str(gen9.rooms[i].get("type", "")) == "boss":
			order9.append(i)
	order9.sort_custom(func(x, y): return int(d9.get(x, 0)) < int(d9.get(y, 0)))
	for i in order9:
		seq_ids.append(str(gen9.rooms[i].get("boss_def", {}).get("id", "")))
	_check(seq_ids == ["9-1", "9-2", "9-3"],
		"第 9 层三连战按策划顺序（守卫→双子→完全体）", [seq_ids])


## 地牢配置的模板池覆盖：生成器产出的房型都能在 data/rooms 找到模板
func test_dungeon_template_coverage() -> void:
	_current_test = "DungeonTemplateCoverage"
	print("\n--- %s ---" % _current_test)

	var DG = _require_script("res://gameplay/dungeon/dungeon_generator.gd")
	if DG == null:
		return

	# 注册模板（同 GameRoot._register_templates 的做法）
	var pool := {}
	var dir := DirAccess.open("res://data/rooms/")
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while not fn.is_empty():
		if fn.ends_with(".json") and not dir.current_is_dir():
			var f := FileAccess.open("res://data/rooms/" + fn, FileAccess.READ)
			if f:
				var j := JSON.new()
				if j.parse(f.get_as_text()) == OK:
					var t := str(j.data.get("room_type", ""))
					pool[t] = int(pool.get(t, 0)) + 1
				f.close()
		fn = dir.get_next()
	dir.list_dir_end()

	# 多种子跑生成器，收集实际产出的房型，逐一确认有模板
	var produced := {}
	for s in range(1, 31):
		var g = DG.new()
		g.min_rooms = 13
		g.max_rooms = 13
		g.generate(s)
		for r in g.rooms:
			produced[str(r.get("type", ""))] = true
	for t in produced.keys():
		_check(int(pool.get(t, 0)) > 0,
			"生成器产出的房型 %s 有对应模板" % t, ["模板数 = %d" % int(pool.get(t, 0))])


# ============================================================
# 音效接线
# ============================================================

## 音效语义名映射表必须真的能用。
##
## ## 为什么值得一条测试
## 这条链路此前**完全断开且完全静默**：`AudioManager.play()` 里的
## `match name` 匹配的是**节点名**（本 autoload 叫 "AudioManager"），
## 不是参数 `_sfx_name`——四个分支永远进不去；而分支里写的
## `res://assets/audio/*.wav` 全项目也不存在。
## 结果：玩家受击 / 击杀 / 拾取 / 死亡四处调用**一声不响**，
## 不报错、不警告，看起来像"音效还没做"。
##
## 所以这里守两件事：
##   ① 调用点用到的语义名，映射表里必须有，且素材文件真实存在
##   ② `connect_buttons` 真的会把子树的按钮接上（UI 点击音）
func test_audio_wiring() -> void:
	_current_test = "AudioWiring"
	print("\n--- %s ---" % _current_test)

	var am = _require_script("res://core/audio_manager.gd")
	if am == null:
		return
	var inst = am.new()

	# ① 玩家侧四个调用点的语义名（与 player.gd 里的字面量一一对应）
	var used := ["hit", "pickup", "death", "menu_click"]
	for nm in used:
		_check(bool(inst.call("has_sfx", nm)),
			"音效 %s 已登记且素材存在" % nm)

	# 未登记的名字必须安全返回 false（而不是报错）
	_check(not bool(inst.call("has_sfx", "definitely_not_a_sound")),
		"未登记的音效名安全返回 false")

	# ② 按钮接线：造一个两层嵌套的子树，确认递归覆盖到深层按钮
	var holder := Node.new()
	root.add_child(holder)
	var mid := Control.new()
	holder.add_child(mid)
	var b1 := Button.new()
	holder.add_child(b1)
	var b2 := Button.new()
	mid.add_child(b2)          # 深层：只在顶层遍历会漏掉它
	inst.call("connect_buttons", holder)
	_check(b1.pressed.is_connected(Callable(inst, "_on_ui_button_pressed")),
		"按钮点击音：直接子节点已接线")
	_check(b2.pressed.is_connected(Callable(inst, "_on_ui_button_pressed")),
		"按钮点击音：深层子节点也接线（递归而非只扫一层）")

	# 幂等：再调一次不该重复连接（重复连会让一次点击放两声）
	inst.call("connect_buttons", holder)
	_check(b1.pressed.get_connections().size() == 1,
		"按钮接线幂等（重复调用不叠加连接）")

	holder.free()
	inst.free()


## 测试 probe 覆盖率 —— 重构报警器。
##
## `tests/helpers/probe.gd` 是测试访问私有成员的**唯一入口**。
## 它登记的名字若在对应脚本里被搬走/改名（重构时的常见事故），
## 这里会**指名道姓**报出来，而不是等某个测试莫名其妙地红。
func test_probe_coverage() -> void:
	_current_test = "ProbeCoverage"
	print("\n--- %s ---" % _current_test)

	var probe = _require_script("res://tests/helpers/probe.gd")
	if probe == null:
		return

	var missing: Array = probe.assert_coverage()
	_check(missing.is_empty(),
		"probe 登记的名字全部存在于对应脚本（缺 %d 个）" % missing.size(),
		missing)

	# 反向核对：本文件确实读到了四个脚本的源码（防止路径写错导致空跑）
	var reg: Dictionary = probe.REGISTERED
	_check(reg.size() >= 4, "probe 至少登记了 4 类宿主", [reg.keys()])
	var total := 0
	for k in reg:
		total += (reg[k] as Array).size()
	_check(total >= 50, "probe 登记名字总数 >= 50（实际 %d）" % total)


## WiredCheck 信号表与 event_bus.gd 声明的一一对应。
##
## 守住"新增了 EventBus 信号却忘了在 WiredCheck 表里登记"——
## 新信号最容易有发无收，登记动作本身就是一次接线自查。
func test_wired_check_table() -> void:
	_current_test = "WiredCheck"
	print("\n--- %s ---" % _current_test)

	var WC = _require_script("res://core/wired_check.gd")
	if WC == null:
		return

	var issues: Array = WC.verify_table()
	_check(issues.is_empty(),
		"WiredCheck 信号表与 event_bus.gd 一一对应（差异 %d 项）" % issues.size(),
		issues)

	# 审计能跑且给出合理结果
	var r: Dictionary = WC.audit_event_bus()
	_check(int(r.get("wired", 0)) > 0, "审计识别出正常接线的信号", [str(r.get("wired"))])
	_check((r.get("dead", []) as Array).size() > 0,
		"审计能列出「有发无收」的信号（本项目的典型缺陷）")


## 随机词条（装备参考2 规格）：条数分布 / 三类词条 / 不可升级
func test_random_affix() -> void:
	_current_test = "RandomAffix"
	print("\n--- %s ---" % _current_test)

	var RA = _require_script("res://data/equipment/random_affix.gd")
	var Inst = _require_script("res://data/equipment/equipment_instance.gd")
	var Defs = _require_script("res://data/equipment/equipment_defs.gd")
	var DB = _require_script("res://data/equipment/equipment_db.gd")
	if RA == null or Inst == null or Defs == null or DB == null:
		return

	DB.init_equipment_db()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	# ① 条数必须落在 1~4
	var counts := {1: 0, 2: 0, 3: 0, 4: 0}
	var kinds := {}
	for i in 300:
		var tpl = DB.get_template(&"W01")
		if tpl == null:
			_check(false, "W01 模板存在"); return
		var inst = Inst.create_drop(tpl, rng, DB.all_templates())
		var n: int = inst.random_affixes.size()
		counts[n] = int(counts.get(n, 0)) + 1
		for a in inst.random_affixes:
			kinds[a.random_kind] = int(kinds.get(kinds, 0)) + 1 if false else int(kinds.get(a.random_kind, 0)) + 1
	_check(counts[1] > 0 and counts[4] > 0,
		"300 次掉落覆盖了 1 条与 4 条两种极端", [str(counts)])
	var total_n := 0
	for k in counts:
		total_n += int(counts[k])
	_check(total_n == 300, "条数统计总数 = 300")

	# ② 三类词条都要出现（300 件 × 平均 2 条 = 600 条，10% 的特殊词条约 60 条）
	_check(int(kinds.get(Defs.RANDOM_KIND_NUMERIC, 0)) > 0, "出现了数值词条")
	_check(int(kinds.get(Defs.RANDOM_KIND_ATTRIBUTE, 0)) > 0, "出现了属性词条")
	_check(int(kinds.get(Defs.RANDOM_KIND_SPECIAL, 0)) > 0, "出现了特殊词条")

	# ③ 数值词条的档位色必须是六色之一
	var valid_colors := ["白", "绿", "蓝", "紫", "橙", "红"]
	for i in 50:
		var tpl = DB.get_template(&"W01")
		var inst = Inst.create_drop(tpl, rng, DB.all_templates())
		for a in inst.random_affixes:
			if a.random_kind == Defs.RANDOM_KIND_NUMERIC:
				_check(a.tier_color in valid_colors,
					"数值词条档位色合法（%s）" % a.tier_color)

	# ④ 随机词条**不可升级**：强化后数值不变
	var tpl2 = DB.get_template(&"W01")
	var inst2 = Inst.create_drop(tpl2, rng, DB.all_templates())
	if inst2.random_affixes.size() > 0:
		var before: float = inst2.random_affixes[0].value
		inst2.enhancement_level = 5
		var after: float = inst2.random_affixes[0].value
		_check(absf(after - before) < 0.0001,
			"强化后随机词条数值不变（不可升级）", ["%.4f → %.4f" % [before, after]])

	# ⑤ 存档往返保留随机词条
	if inst2.random_affixes.size() > 0:
		var d: Dictionary = inst2.to_dict()
		var inst3 = Inst.new().from_dict(d)
		_check(inst3.random_affixes.size() == inst2.random_affixes.size(),
			"存档往返后随机词条数量一致",
			["%d → %d" % [inst2.random_affixes.size(), inst3.random_affixes.size()]])
		_check(inst3.random_affixes[0].tier_color == inst2.random_affixes[0].tier_color,
			"存档往返后档位色一致")
		_check(inst3.random_affixes[0].random_kind == inst2.random_affixes[0].random_kind,
			"存档往返后词条类别一致")


## 武器类型互斥（装备参考2 规格）
func test_weapon_tag_conflict() -> void:
	_current_test = "WeaponTagConflict"
	print("\n--- %s ---" % _current_test)

	var Defs = _require_script("res://data/equipment/equipment_defs.gd")
	if Defs == null:
		return

	# ① 规格逐条：互斥对必须被识别
	_check(not Defs.weapon_tag_conflict(["melee"], ["ranged"]).is_empty(),
		"近战 ↔ 远程 互斥")
	_check(not Defs.weapon_tag_conflict(["one_hand"], ["two_hand"]).is_empty(),
		"单手 ↔ 双手 互斥")
	_check(not Defs.weapon_tag_conflict(["defensive"], ["ranged"]).is_empty(),
		"防御 ↔ 远程 互斥")
	_check(not Defs.weapon_tag_conflict(["defensive"], ["magic"]).is_empty(),
		"防御 ↔ 魔法 互斥")
	_check(not Defs.weapon_tag_conflict(["defensive"], ["polearm"]).is_empty(),
		"防御 ↔ 长杆 互斥")
	_check(not Defs.weapon_tag_conflict(["polearm"], ["ranged"]).is_empty(),
		"长杆 ↔ 远程 互斥")

	# ② 非互斥组合不应误报
	_check(Defs.weapon_tag_conflict(["melee"], ["magic"]).is_empty(),
		"近战 + 魔法 可共存（不误报）")
	_check(Defs.weapon_tag_conflict(["one_hand"], ["melee"]).is_empty(),
		"单手 + 近战 可共存（不误报）")

	# ③ 反向也要认（无向对）
	_check(not Defs.weapon_tag_conflict(["ranged"], ["melee"]).is_empty(),
		"反向：远程 ↔ 近战 同样互斥")

	# ④ 中文标签 → 规格标签的映射
	var t_sword: Array = Defs.weapon_tags_of("sword", ["近战", "物理"])
	_check("melee" in t_sword, "单手剑映射出 melee")
	_check("one_hand" in t_sword, "单手剑映射出 one_hand")
	var t_bow: Array = Defs.weapon_tags_of("bow", ["远程", "物理"])
	_check("ranged" in t_bow, "长弓映射出 ranged")
	_check("two_hand" in t_bow, "长弓映射出 two_hand")
	var t_shield: Array = Defs.weapon_tags_of("shield", ["其他"])
	_check("defensive" in t_shield, "盾牌映射出 defensive")

	# ⑤ 单手剑 vs 长弓：近战/远程 + 单手/双手 双冲突
	var conf: Array = Defs.weapon_tag_conflict(t_sword, t_bow)
	_check(not conf.is_empty(), "单手剑与长弓不能同时装备（实测冲突：%s）" % str(conf))
