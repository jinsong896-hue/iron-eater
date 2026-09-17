class_name AffixDB
extends RefCounted
## 怪物词缀系统 —— 《噬铁者》怪物设计分册 第 7 章
##
## 分册只给了「效果示例」而非具体数值，故**数值是本项目自定的**（已在下方标注）。
## 分册明确的硬规则（照搬）：
##   阶段一(1-2层) 普通 0 / 精英 0，池：无（纯教学）
##   阶段二(3-4层) 普通 0~1 / 精英 1，池：快速、强壮、燃烧
##   阶段三(5-6层) 普通 1~2 / 精英 2，池：+冰冻、复仇
##   阶段四(7-8层) 普通 2~3 / 精英 3，池：+不朽、吸血
##   第 9 层      全精英 2~3，含专属：虚空、混沌
##
## 实现现状：**9 个词缀全部实装**。
## 数值型（快速/强壮）由 `apply()` 直接写怪物属性；
## 非数值型（燃烧/冰冻/复仇/不朽/吸血/虚空/混沌）的战斗钩子装配在
## `enemy_base._apply_affix()`，触发点见 `_perform_attack` / `take_damage` /
## `_apply_melee_mechanics` / `_tick_mech_timers`。

## 词缀定义表
## [id, 名称, 首次可用阶段, 是否纯数值,
##  速度倍率, 攻击倍率, 间隔倍率, 击退倍率,   ← 纯数值词缀用
##  效果说明]
const AFFIXES := [
	["fast",      "快速", 2, true,  1.25, 1.0, 0.80, 1.0, "移速与攻击频率提升"],
	["strong",    "强壮", 2, true,  1.0,  1.30, 1.0, 1.5, "攻击力与击退效果提升"],
	["burn",      "燃烧", 2, false, 1.0,  1.0,  1.0, 1.0, "攻击附加持续灼烧"],
	["freeze",    "冰冻", 3, false, 1.0,  1.0,  1.0, 1.0, "攻击附加减速/冻结"],
	["revenge",   "复仇", 3, false, 1.0,  1.0,  1.0, 1.0, "受击一定比例反伤"],
	["immortal",  "不朽", 4, false, 1.0,  1.0,  1.0, 1.0, "血量低于阈值时短暂免伤/回血"],
	["lifesteal", "吸血", 4, false, 1.0,  1.0,  1.0, 1.0, "造成伤害时回复自身"],
	["void",      "虚空", 5, false, 1.0,  1.0,  1.0, 1.0, "传送/空间干扰类效果（第 9 层专属）"],
	["chaos",     "混沌", 5, false, 1.0,  1.0,  1.0, 1.0, "混乱/随机化效果（第 9 层专属）"],
]

## 各阶段词缀数量 [普通最小, 普通最大, 精英数]
const COUNT_BY_PHASE := {
	1: [0, 0, 0],
	2: [0, 1, 1],
	3: [1, 2, 2],
	4: [2, 3, 3],
	5: [2, 3, 3],   # 第 9 层：全精英，取精英口径
}


## 指定阶段可用的词缀池（阶段 ≥ 首次可用阶段即解锁）
static func pool_for_phase(phase: int) -> Array:
	var out: Array = []
	for a in AFFIXES:
		if int(a[2]) <= phase:
			out.append(a)
	return out


## 按阶段与是否精英，随机抽词缀 id 列表
static func roll(phase: int, is_elite: bool, rng: RandomNumberGenerator) -> Array:
	var counts: Array = COUNT_BY_PHASE.get(clampi(phase, 1, 5), [0, 0, 0])
	var n: int
	if is_elite:
		n = int(counts[2])
	else:
		n = rng.randi_range(int(counts[0]), int(counts[1]))
	if n <= 0:
		return []

	var pool := pool_for_phase(phase)
	var picked: Array = []
	for _i in n:
		if pool.is_empty():
			break
		var idx := rng.randi_range(0, pool.size() - 1)
		var a: Array = pool[idx]
		# 不重复取同一词缀
		pool.remove_at(idx)
		picked.append(str(a[0]))
	return picked


## 词缀 id → 定义行
static func get_affix(id: String) -> Array:
	for a in AFFIXES:
		if str(a[0]) == id:
			return a
	return []


## 词缀显示名
static func affix_name(id: String) -> String:
	var a := get_affix(id)
	return str(a[1]) if not a.is_empty() else id


## 是否纯数值词缀（能被 apply 真正作用到属性上）
static func is_numeric(id: String) -> bool:
	var a := get_affix(id)
	return bool(a[3]) if not a.is_empty() else false


## 把词缀作用到怪物字典：数值型立刻改属性，
## 全部 id（含非数值型）记入 affixes 数组供后续系统消费。
## 返回应用了哪些纯数值词缀（便于 UI/调试显示）。
static func apply(monster: Dictionary, affix_ids: Array) -> Dictionary:
	var applied: Array = []
	monster["affixes"] = affix_ids.duplicate()
	for id in affix_ids:
		var a := get_affix(id)
		if a.is_empty() or not bool(a[3]):
			continue
		monster["speed_pct"] = float(monster.get("speed_pct", 100.0)) * float(a[4])
		monster["atk"] = int(float(monster.get("atk", 1.0)) * float(a[5]))
		monster["attack_interval"] = float(monster.get("attack_interval", 3.0)) * float(a[6])
		monster["knockback_mult"] = float(monster.get("knockback_mult", 1.0)) * float(a[7])
		applied.append(id)
	return {"applied_numeric": applied, "all": affix_ids}


## 需要后续系统实现的词缀（登记待办用）。
##
## **全部 9 个词缀现已实装**（7 个非数值词缀的战斗钩子在
## `enemy_base._apply_affix` / `_perform_attack` / `take_damage` 里）。
## 本函数保留为空实现——它是"只登记不实现"的守卫：
## 新增词缀但忘了接线时，这里会重新出现条目，测试随之变红。
static func pending_systems() -> Array:
	var out: Array = []
	for a in AFFIXES:
		if not bool(a[3]) and not (str(a[0]) in IMPLEMENTED_NON_NUMERIC):
			out.append({"id": a[0], "name": a[1], "effect": a[8]})
	return out


## 已接线战斗钩子的非数值词缀（与 enemy_base._apply_affix 的 match 分支一一对应）。
## 两边不同步时 pending_systems() 会非空，测试立刻失败。
const IMPLEMENTED_NON_NUMERIC := [
	"burn", "freeze", "revenge", "immortal", "lifesteal", "void", "chaos",
]
