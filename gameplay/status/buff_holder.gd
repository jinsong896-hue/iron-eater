class_name BuffHolder
extends RefCounted
## 词条 + 元素叠层的运行时容器（挂在玩家/怪物上）
##
## 职责：
##   · 词条的施加/叠层/计时/过期
##   · 属性型词条（impl="stat"）通过 modifier 回调作用到目标
##   · DOT 型词条（impl="dot"）按 tick 结算伤害
##   · 元素叠层（火冰雷毒）与阈值触发（冰冻/雷暴）
##
## 纯逻辑、不依赖场景树，便于单测。
## 需要目标提供（可选，缺失则静默跳过对应能力）：
##   take_damage(amount)        —— DOT 结算
##   add_modifier(src, stat, flat, pct) / remove_modifiers(src)
##   eff_atk() / eff_ap()       —— DOT 的伤害基准

const MAX_TICK_HISTORY := 64

var _target            # 宿主对象
var _buffs := {}       # id -> {stacks, remaining, source, element}
var _elem_stacks := {} # elem_id -> 层数
var _frozen_until := 0.0
var _time := 0.0
## 元素阈值触发回调：func(elem_id, event_name, ctx: Dictionary)
var _on_element_event: Callable = Callable()


func _init(target = null) -> void:
	_target = target


## 设置元素事件回调（冰冻/雷暴等阈值触发交给外部处理控制效果）
func set_element_callback(cb: Callable) -> void:
	_on_element_event = cb


# ============================================================
# 词条
# ============================================================

## 施加词条。source 用于属性 modifier 的来源追踪。
## 已有同名词条则叠层（不超过上限）并刷新时长。
func apply(buff_id: String, source: String = "buff", stacks: int = 1) -> Dictionary:
	var row := BuffDefs.get_buff(buff_id)
	if row.is_empty():
		return {"ok": false, "reason": "未知词条 %s" % buff_id}
	var max_stacks := int(row[4])
	if not _buffs.has(buff_id):
		_buffs[buff_id] = {
			"stacks": 0, "remaining": float(row[3]),
			"source": source, "kind": int(row[2]), "impl": str(row[6]),
		}
	var e: Dictionary = _buffs[buff_id]
	# 叠层（max_stacks=0 表示不叠层，保持 1）
	if max_stacks > 0:
		e["stacks"] = mini(int(e["stacks"]) + stacks, max_stacks)
	else:
		e["stacks"] = maxi(int(e["stacks"]), 1)
	# 刷新时长（永久词条 duration=0 不设剩余时间）
	if float(row[3]) > 0.0:
		e["remaining"] = float(row[3])
	# 记录**最近一次**施加者：remove_from_source 靠它判断
	# 「这个词条现在还是我施加的吗」。区域陷阱每 tick 重刷，故施法者
	# 离开后若被别的来源接管，source 会随之更新，区域不会误删。
	e["source"] = source
	_sync_modifier(buff_id)
	return {"ok": true, "stacks": e["stacks"]}


## 移除词条
func remove(buff_id: String) -> void:
	if not _buffs.has(buff_id):
		return
	_clear_modifier(buff_id)
	_buffs.erase(buff_id)


## 按来源移除词条：仅当**当前记录的最后施加者**是 source 时才移除。
## 用于「区域内持续施加、离开区域撤销」的陷阱型词条（见 DamageZone）。
## 若期间被其它来源重新施加（source 已变），说明该词条另有出处，
## 不能由本来源撤销——否则会误删别人挂的效果。
## 返回是否真的移除了。
func remove_from_source(buff_id: String, source: String) -> bool:
	if not _buffs.has(buff_id):
		return false
	if str(_buffs[buff_id].get("source", "")) != source:
		return false
	remove(buff_id)
	return true


## 是否持有
func has(buff_id: String) -> bool:
	return _buffs.has(buff_id)


## 层数（无则 0）
func stacks_of(buff_id: String) -> int:
	return int((_buffs.get(buff_id, {}) as Dictionary).get("stacks", 0))


## 全部生效中的词条 id
func active_ids() -> Array:
	return _buffs.keys()


## 供 UI 渲染的完整状态快照。
## 返回 [{id, name, stacks, remaining, total, permanent, kind, is_debuff}, ...]
## `remaining/total` 用于画剩余时间进度条；duration=0 的永久词条
## remaining 恒为 0、permanent=true（UI 画成"∞"而不是空条）。
## 元素层数（毒/火…）不在 _buffs 里，但玩家最需要看到它们，
## 故一并输出为伪词条（id 形如 "elem:poison"）。
func ui_snapshot() -> Array:
	var out: Array = []
	for id in _buffs:
		var e: Dictionary = _buffs[id]
		var row := BuffDefs.get_buff(id)
		if row.is_empty():
			continue
		var total: float = float(row[3])
		out.append({
			"id": id,
			"name": str(row[1]),
			"stacks": int(e.get("stacks", 1)),
			"remaining": float(e.get("remaining", 0.0)),
			"total": total,
			"permanent": total <= 0.0,
			"kind": int(row[2]),
			"is_debuff": _is_debuff_kind(int(row[2])),
		})
	# 元素层数（不走 _buffs，单独补进来）
	for elem in _elem_stacks.keys():
		var n := int(_elem_stacks[elem])
		if n <= 0:
			continue
		var cfg := ElementDefs.get_element(elem)
		var dur := float(cfg.get("duration", 0.0))
		out.append({
			"id": "elem:%d" % elem,
			"name": str(cfg.get("stack_name", "元素")),
			"stacks": n,
			"remaining": 0.0,
			"total": dur,
			"permanent": dur <= 0.0,
			"kind": -1,
			"is_debuff": true,
		})
	return out


## 是否负面词条（UI 用它决定配色：负面红、正面绿）
func _is_debuff_kind(kind: int) -> bool:
	return kind in [BuffDefs.Kind.DOT, BuffDefs.Kind.SLOW, BuffDefs.Kind.CONTROL,
		BuffDefs.Kind.VULN, BuffDefs.Kind.WEAKEN, BuffDefs.Kind.DISPLACE]


## 累计「受到伤害提升%」（易伤类词条，按层数累加）
func total_vulnerability() -> float:
	var v := 0.0
	for id in _buffs:
		var e: Dictionary = _buffs[id]
		if str(e.get("impl", "")) not in ["stat", "dot"]:
			continue
		var p: Dictionary = BuffDefs.params_of(id)
		v += float(p.get("vuln", 0.0)) * int(e.get("stacks", 1))
	# 元素层数自带易伤：毒蚀每层 +1%（分册 4.x，与词条「毒蚀」同口径）。
	# 以元素层数为唯一真相——不再另挂一份 poison_rot 词条，避免两份状态漂移。
	var poison := int(_elem_stacks.get(ElementDefs.Elem.POISON, 0))
	if poison > 0:
		v += float(ElementDefs.get_element(ElementDefs.Elem.POISON).get("vuln_per_stack", 0.01)) * poison
	return v


## 累计「受到治疗降低%」
func total_heal_reduction() -> float:
	var v := 0.0
	for id in _buffs:
		var p: Dictionary = BuffDefs.params_of(id)
		v += float(p.get("heal_down", 0.0))
	return clampf(v, 0.0, 1.0)


## 累计「受到伤害降低%」（防御型）
func total_damage_reduction() -> float:
	var v := 0.0
	for id in _buffs:
		var p: Dictionary = BuffDefs.params_of(id)
		v += float(p.get("dmg_taken_down", 0.0))
	return clampf(v, 0.0, 0.9)


## 累计「移速降低比例」
func total_slow() -> float:
	var v := 0.0
	for id in _buffs:
		var e: Dictionary = _buffs[id]
		var p: Dictionary = BuffDefs.params_of(id)
		v += float(p.get("slow", 0.0)) * int(e.get("stacks", 1))
	# 寒霜层数自带减速：每层 -25%（分册 7.3）。
	# 寒霜层数存在 _elem_stacks 而非 _buffs，必须单独叠加。
	var frost := int(_elem_stacks.get(ElementDefs.Elem.FROST, 0))
	if frost > 0:
		v += float(ElementDefs.get_element(ElementDefs.Elem.FROST).get("slow_per_stack", 0.25)) * frost
	return clampf(v, 0.0, 0.9)


## 是否持有指定词条（冰冻判定用）
func _has_control_buff(buff_id: String) -> bool:
	return _buffs.has(buff_id)


## 是否处于硬控（定身/眩晕/冰冻/麻痹）
func is_controlled() -> bool:
	for id in _buffs:
		if int((_buffs[id] as Dictionary).get("kind", -1)) == BuffDefs.Kind.CONTROL:
			var p: Dictionary = BuffDefs.params_of(id)
			if bool(p.get("root", false)) or bool(p.get("stun", false)):
				return true
	return _time < _frozen_until


# ============================================================
# 元素叠层
# ============================================================

## 叠加元素层数，返回触发的事件（如 "freeze" / "thunderstorm"）
func add_element(elem: int, stacks: int = 1) -> Array:
	if not ElementDefs.stacks(elem):
		return []   # 土/风不叠层
	var cfg: Dictionary = ElementDefs.get_element(elem)
	var max_s := int(cfg.get("max_stacks", 0))
	var cur := int(_elem_stacks.get(elem, 0)) + stacks
	cur = mini(cur, max_s)
	_elem_stacks[elem] = cur

	var events: Array = []
	var th: Dictionary = cfg.get("thresholds", {})
	# 冰：叠满触发冰冻，冰冻结束后层数归零
	if elem == ElementDefs.Elem.FROST and cur >= int(th.get("freeze", 3)):
		_elem_stacks[elem] = 0
		_frozen_until = _time + float(cfg.get("freeze_duration", 1.5))
		events.append("freeze")
	# 雷：叠满触发雷暴，触发后归零
	if elem == ElementDefs.Elem.STATIC and cur >= int(th.get("thunderstorm", 10)):
		_elem_stacks[elem] = 0
		events.append("thunderstorm")

	# 毒：按层数解锁 侵蚀(-20%移速) / 衰弱(-20%伤害) / 虚弱(-50%治疗)
	# 分册 7.7；层数不衰减，故一旦解锁就持续有效，直到层数回落
	if elem == ElementDefs.Elem.POISON:
		if cur >= int(th.get("erosion", 10)) and not _buffs.has("erosion"):
			apply("erosion", "poison")
		if cur >= int(th.get("weakness", 20)) and not _buffs.has("weakness"):
			apply("weakness", "poison")
		if cur >= int(th.get("frailty", 30)) and not _buffs.has("frailty"):
			apply("frailty", "poison")

	for ev in events:
		if _on_element_event.is_valid():
			_on_element_event.call(elem, ev, element_context(elem))
	return events


## 元素层数
func elem_stacks(elem: int) -> int:
	return int(_elem_stacks.get(elem, 0))


## 元素上下文（供联动判定与伤害结算取用）
func element_context(elem: int) -> Dictionary:
	var cfg: Dictionary = ElementDefs.get_element(elem)
	return {
		"elem": elem,
		"stacks": elem_stacks(elem),
		"max_stacks": int(cfg.get("max_stacks", 0)),
		"dot_per_stack": float(cfg.get("dot_per_stack", 0.0)),
		"frozen": _time < _frozen_until,
	}


## 是否处于冰冻。
## 冰冻有两个入口，两者必须都算：① 寒霜叠满触发（_frozen_until）
## ② 直接施加 freeze 词条（怪物技能/装备）。只认①会导致
## 「用 freeze 词条冰冻后，冰系联动判不出来」。
func is_frozen() -> bool:
	return _time < _frozen_until or _has_control_buff("freeze")


# ============================================================
# 推进
# ============================================================

## 推进计时。返回本帧 DOT 应结算的总伤害（由调用方决定如何施加）。
func tick(delta: float) -> Dictionary:
	_time += delta
	var dot_total := 0.0
	var atk := _target_atk()
	var ap := _target_ap()
	var expired: Array = []

	for id in _buffs.keys():
		var e: Dictionary = _buffs[id]
		var row := BuffDefs.get_buff(id)
		if row.is_empty():
			expired.append(id)
			continue
		var p: Dictionary = params_of_cached(id)
		var n := int(e.get("stacks", 1))

		# DOT 结算（impl="dot"）
		if str(e.get("impl", "")) == "dot":
			if p.has("dot_pct"):
				dot_total += ap * float(p["dot_pct"]) * float(n) * delta
			if p.has("dot_atk"):
				dot_total += atk * float(p["dot_atk"]) * float(n) * delta

		# 时长推进（duration=0 表示永久）
		if float(row[3]) > 0.0:
			e["remaining"] = float(e["remaining"]) - delta
			if float(e["remaining"]) <= 0.0:
				expired.append(id)

	# 元素层数 DOT（分册 7.x：火=灼烧、毒=毒蚀，每层每秒 ×法强）
	# 注意与下面的「词条 DOT」是两条独立来源：元素层数不走 _buffs，
	# 故必须单独结算，否则火的灼烧只显示层数、不造成任何伤害。
	var elem_dot := 0.0
	for elem in _elem_stacks.keys():
		var ecfg: Dictionary = ElementDefs.get_element(elem)
		var per := float(ecfg.get("dot_per_stack", 0.0))
		if per > 0.0:
			elem_dot += ap * per * float(_elem_stacks[elem]) * delta

	# 元素衰减（火：停止攻击后每秒 -5 层；毒/雷不衰减）
	for elem in _elem_stacks.keys():
		var cfg: Dictionary = ElementDefs.get_element(elem)
		var decay := float(cfg.get("decay_per_sec", 0.0))
		if decay > 0.0:
			_elem_decay_accum[elem] = float(_elem_decay_accum.get(elem, 0.0)) + decay * delta
			var drop := int(_elem_decay_accum[elem])
			if drop > 0:
				_elem_decay_accum[elem] = float(_elem_decay_accum[elem]) - float(drop)
				_elem_stacks[elem] = maxi(int(_elem_stacks[elem]) - drop, 0)

	for id in expired:
		_clear_modifier(id)
		_buffs.erase(id)

	return {"dot": dot_total + elem_dot, "elem_dot": elem_dot, "expired": expired}


var _elem_decay_accum := {}
static var _param_cache := {}

static func params_of_cached(id: String) -> Dictionary:
	if _param_cache.is_empty():
		for bid in BuffDefs.all_ids():
			_param_cache[bid] = BuffDefs.params_of(bid)
	return _param_cache.get(id, {})


# ============================================================
# 属性同步（内部）
# ============================================================

## 把 stat 型词条的效果同步为 target 上的 modifier
func _sync_modifier(buff_id: String) -> void:
	if _target == null or not _target.has_method("add_modifier"):
		return
	var impl := BuffDefs.impl_of(buff_id)
	if impl != "stat":
		return
	var p := BuffDefs.params_of(buff_id)
	var src := "buff:%s" % buff_id
	_target.call("remove_modifiers", src)
	var n := float(stacks_of(buff_id))
	# 攻击/防御/移速等按层数放大
	_apply_stat(src, AttributeSystem.Stat.ATK, float(p.get("atk_up", 0.0)) * n, float(p.get("atk_down", 0.0)) * n)
	_apply_stat(src, AttributeSystem.Stat.DEF, float(p.get("def_up", 0.0)) * n, float(p.get("def_down", 0.0)) * n)
	_apply_stat(src, AttributeSystem.Stat.SPD, float(p.get("spd_up", 0.0)) * n, float(p.get("slow", 0.0)) * n)
	_apply_stat(src, AttributeSystem.Stat.ASPD, float(p.get("aspd_up", 0.0)) * n, float(p.get("aspd_down", 0.0)) * n)
	_apply_stat(src, AttributeSystem.Stat.AP, float(p.get("ap_up", 0.0)) * n, 0.0)
	_apply_stat(src, AttributeSystem.Stat.CRT, float(p.get("crit_up", 0.0)) * n, 0.0)
	_apply_stat(src, AttributeSystem.Stat.CRD, float(p.get("crd_up", 0.0)) * n, 0.0)
	_apply_stat(src, AttributeSystem.Stat.CDR, float(p.get("cdr_up", 0.0)) * n, 0.0)
	_apply_stat(src, AttributeSystem.Stat.RNG, float(p.get("rng_up", 0.0)) * n, 0.0)


## 正负系数合并成一次 modifier（add_modifier 接受 flat/percent 两个槽）
func _apply_stat(src: String, stat: int, up: float, down: float) -> void:
	var net := up - down
	if absf(net) < 0.0001:
		return
	_target.call("add_modifier", src, stat, 0.0, net)


func _clear_modifier(buff_id: String) -> void:
	if _target == null or not _target.has_method("remove_modifiers"):
		return
	_target.call("remove_modifiers", "buff:%s" % buff_id)


func _target_atk() -> float:
	if _target != null and _target.has_method("eff_atk"):
		return float(_target.call("eff_atk"))
	if _target != null and _target.has_method("stat_value"):
		return float(_target.call("stat_value", "atk"))
	return 0.0


func _target_ap() -> float:
	if _target != null and _target.has_method("eff_ap"):
		return float(_target.call("eff_ap"))
	if _target != null and _target.has_method("stat_value"):
		return float(_target.call("stat_value", "ap"))
	return 0.0


## 供测试：清空全部状态
func clear() -> void:
	for id in _buffs.keys():
		_clear_modifier(id)
	_buffs.clear()
	_elem_stacks.clear()
	_frozen_until = 0.0
