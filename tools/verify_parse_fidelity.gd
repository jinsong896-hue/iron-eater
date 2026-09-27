extends SceneTree
## 词条解析忠实度校验 —— 核对「解析结果是否忠实于文档原文」
##
## ## 为什么需要它
##
## 只统计「有没有解析出来」远远不够。**解析出来了但解错**同样错，
## 而且更隐蔽——报告全绿，数据是错的。实测发现的典型错误：
##
##   · 「该武器**所有数值**增加1%」   → 只解析成 `Stat.ATK`（丢了「所有」）
##   · 「每**击杀**一个敌人回复5%生命」→ 解析成 `ON_HIT`（命中，不是击杀）
##   · 「**全属性**增加10%，**持续5秒**，**可无限叠加**」
##                                    → 解析成**常驻** `Stat.ATK+10%`
##                                      （触发/时长/叠层全丢）
##
## ## 判据
##
## 从**文档原文**里抽特征词，检查**解析结果**里是否有对应的痕迹：
##   原文含「击杀」      → 结果里 trigger 必须是 ON_KILL(1)
##   原文含「受到伤害」  → trigger 必须是 ON_HURT(2)
##   原文含「持续N秒」   → 结果里必须有时长（duration>0 或触发型）
##   原文含「叠加N层」   → 结果里 stack_max 必须 = N
##   原文含「所有/全属性」→ 不能只落到单个 Stat.*
##   原文含「N%」        → 结果里的数值必须包含 N/100
##
## ## 用法
##
## ```bash
## "$GODOT" --headless --path . --script res://tools/verify_parse_fidelity.gd
## ```

const TRACE := "res://tools/data/parse_trace.txt"
## 完整问题明细（供重构前后 diff）
const ISSUES_PATH := "res://tools/data/fidelity_issues.txt"

## Trigger 枚举（与 AffixData.Trigger 一致）
const TRIG_ALWAYS := 0
const TRIG_ON_KILL := 1
const TRIG_ON_HURT := 2
const TRIG_ON_HIT := 3
const TRIG_AT_FULL := 5
const TRIG_ON_CRIT := 6

var _issues: Array[String] = []
var _checked := 0


func _init() -> void:
	var rows := _read_trace()
	print("读取解析追踪 %d 条\n" % rows.size())
	for r in rows:
		_check_one(r)

	_checked = rows.size()
	print("=== 忠实度问题：%d / %d 条 ===" % [_issues.size(), _checked])
	# 按问题类型聚合
	var by_kind := {}
	for s in _issues:
		var k := s.split(" | ")[0]
		by_kind[k] = int(by_kind.get(k, 0)) + 1
	var ks := by_kind.keys(); ks.sort()
	for k in ks:
		print("  %-34s %d" % [k, by_kind[k]])

	print("\n=== 明细（前 60 条）===")
	for i in mini(_issues.size(), 60):
		print("  " + _issues[i])

	# **完整明细落盘**——终端只打印 60 条，但做「重构前后对比」时
	# 截断会让 diff 失真：只在前 60 条里出现的差异被当成真差异，
	# 而实际是列表顺序变化导致的。实测踩过：误判 4 条既有问题为回归。
	#
	# 用 `sort` 保证跨次运行顺序稳定，diff 才有意义。
	var sorted := _issues.duplicate()
	sorted.sort()
	var f := FileAccess.open(ISSUES_PATH, FileAccess.WRITE)
	if f != null:
		for s in sorted:
			f.store_line(s)
		f.close()
		print("\n完整明细已写入 %s（%d 条）" % [ISSUES_PATH, sorted.size()])

	quit(0 if _issues.is_empty() else 1)


## 单条校验
func _check_one(r: Dictionary) -> void:
	var text := str(r["text"])
	var spec := str(r["spec"])
	var tag := "%s [%s] %s" % [r["name"], r["col"], text]

	if spec == "__MISS__":
		return                      # 未映射由另一个报告负责
	if spec == "__SKILL__":
		return

	var trig := _trigger_of(spec)
	var stack := _stack_of(spec)
	var nums := _numbers_of(spec)

	# —— 1. 触发条件 ——
	#
	# ## 只报「条件**整个丢了**」的情况
	#
	# 判据是 `trig == TRIG_ALWAYS`（解析成无条件常驻），而不是
	# 「不等于某个特定 trigger」。后者会大量误报：
	#   · 「护盾存在时，受到伤害减少10%」→ trigger=15(SHIELD_UP) **是对的**
	#     （条件就是「护盾存在」，不是「受到伤害」）
	#   · 「嘲讽期间…」→ 20(ON_TAUNT)、「反击姿态期间…」→ 24(ON_FRENZY) 同理
	#   · sentinel 类（`[2, "afterimage", ...]`）的 trigger 字段本就是
	#     从句切分推导的、对规则无意义
	# 那些都不该报。真错是「有条件却解析成常驻」——条件被静默丢弃。
	if trig == TRIG_ALWAYS and not spec.begins_with("[2,") \
			and not spec.begins_with("[4,") and not spec.begins_with("[8,"):
		var cond := ""
		if text.contains("击杀"):
			cond = "击杀"
		elif text.contains("受到伤害") or text.contains("受击"):
			cond = "受到伤害"
		elif text.contains("暴击时"):
			cond = "暴击"
		elif _re(r"(?:生命|血量|生命值)低于\s*\d+%").search(text) != null:
			cond = "低血"
		elif _re(r"^\S{2,10}(?:时|后)[，,]").search(text) != null:
			cond = "从句条件"
		# **条件内建通道要放过**：有些通道的语义**本身就是那个条件**，
		# 常驻形态是正确的，不是丢条件。判据是「原文条件 ↔ 通道语义」精确匹配：
		#   「对生命值低于N%的**敌人**」→ `execute_line`(105) 就是「对低血目标增伤」
		#   「被**冻结**敌人」           → `frozen_dmg`(141) 就是「对被冻结目标增伤」
		#   「**反弹**」                 → `reflect`(104) 就是「受伤时反伤」
		# 三者都只有在**条件与通道语义一致**时才放过——
		# 例如「每层目标受到伤害+5%」虽然也是 105，但它是**易伤**不是处决线，
		# 条件不同，仍要报。
		if not cond.is_empty() and _cond_is_intrinsic(text, cond, spec):
			cond = ""
		if not cond.is_empty():
			_issues.append("条件丢失 | %s\n      原文有「%s」条件，却解析成**无条件常驻** %s"
				% [tag, cond, spec])

	# —— 2. 叠层上限 ——
	# 「叠加N层」/「最多N层」→ stack_max 必须 = N
	var want_stack := _stack_from_text(text)
	if want_stack > 0 and stack != want_stack:
		_issues.append("叠层上限错 | %s\n      原文声明 %d 层，解析成 stack_max=%d"
			% [tag, want_stack, stack])

	# —— 3. 「所有/全属性」不能塌缩成单一属性 ——
	#
	# 多属性规格的形态是**嵌套数组**：`[[Stat.HP, v, t], [Stat.ATK, v, t], …]`
	# （`_make_affix_list` 逐条构建）。旧判据找的是 `;`（一个从未使用过的
	# 分隔符），于是任何展开后的结果都被当成「单属性」——**检查器假警报**。
	if text.contains("所有数值") or text.contains("全属性") \
			or text.contains("所有基础属性") or text.contains("所有属性"):
		if _re(r"^\s*\[\[\s*[A-Za-z_.0-9]+,").search(spec) == null:
			_issues.append("属性范围错 | %s\n      「所有/全属性」被塌缩成单属性（应为多属性规格）"
				% tag)

	# —— 4. 数值是否被提取 ——
	#
	# ## 只检查「效果量」数值，跳过「条件/结构」数值
	#
	# 原文里的 `N%` 不都是效果量：
	#   `有 N% 概率…`   —— 触发概率（不是效果，另有第 6 节专门查）
	#   `低于 N% 时`    —— 阈值
	#   `持续 N 秒`     —— 时长
	#   `最多 N 层`     —— 层数上限
	# 这些**本就不该出现在效果值里**，旧实现一刀切要求全部出现，
	# 于是 122 条里绝大多数是这类噪声，把真问题淹没了。
	var pcts := _effect_pcts_from_text(text)
	for p in pcts:
		if not _has_number(nums, p):
			_issues.append("数值丢失 | %s\n      原文的效果值 %s%% 未出现在解析结果里"
				% [tag, p])

	# —— 5. 「持续N秒」不能丢 ——
	#
	# 判据：原文写了时长，结果里就该有时长的痕迹。合法载体三种：
	#   `[2+..., chance, duration, ...]`      —— 第 4 槽是时长
	#   `[4, t, stat, v, stack_max, ...]`     —— 叠层类靠 `stack_max` 表达
	#   参数字典里带 `seconds` / `duration`    —— sentinel 类
	#
	# **旧判据是坏的**：`not spec.contains(".") and not spec.contains(",")`
	# 对任何数组字面量都恒假（spec 必然含逗号），于是这条**从未触发**。
	#
	# ## 只查「自身增益」的时长
	#
	# 原文里的「持续N秒」不都属于**词条本身**：
	# 「攻击施加"猎神标记"（最多8层，持续10秒）」的 10 秒是**标记**的时长、
	# 「坠落点留下星尘区域（每秒30%法强，持续3秒）」是**区域**的时长——
	# 这些词条的效果是「施加标记」「留下区域」，本身没有时长可言。
	# 故只在「…获得…持续N秒」这种**自身增益**写法上校验，
	# 与生成器侧 `_time_bound_wrap` 的口径一致。
	if _re(r"获得.{0,12}持续\s*\d+\s*秒").search(text) != null \
			and not text.contains("（") and not text.contains("("):
		if not _has_duration(spec):
			_issues.append("时长丢失 | %s\n      原文有「获得…持续N秒」但结果无时长（变成永久常驻）"
				% tag)

	# —— 6. **概率条件被当成效果量** ——
	#
	# 「格挡时有 3% 概率**完全免疫该次伤害**」——`3%` 是**触发概率**，
	# 「完全免疫该次伤害」才是效果。实测解析结果是 `[110, 0.03, true]`
	# = 「格挡率 +3%」：概率被当成了效果量，真正的效果整个丢失。
	# 这类比「未映射」隐蔽得多——数据看起来正常，报告也全绿。
	var pm := _re(r"有\s*(\d+(?:\.\d+)?)%\s*概率").search(text)
	if pm != null:
		var prob := pm.get_string(1)
		if _spec_is_unconditional(spec) and _has_number(nums, prob):
			_issues.append("概率当效果 | %s\n      原文的 %s%% 是**触发概率**，却成了效果值（真正的效果丢失）"
				% [tag, prob])

	# —— 7. **低血阈值丢失** ——
	#
	# 「生命低于30%时，吸血效果提升20%」——30% 与 20% **不是同一个数**。
	# 阈值在 `STACK_GAIN` 的第 6 槽；缺了它消费方只能按统一 0.5 判，
	# 于是 30% 那条会在 30%~50% 区间**提前生效**。
	var tm := _re(r"(?:生命|血量|生命值)低于\s*(\d+(?:\.\d+)?)%").search(text)
	if tm != null and trig == 11 and _threshold_of(spec) <= 0.0:
		_issues.append("阈值丢失 | %s\n      原文「低于 %s%%」未进第 6 槽（会退化成统一 0.5）"
			% [tag, tm.get_string(1)])


## 原文的条件是否**内建在通道语义里**（那就不算丢条件）
##
## 三条精确对应关系，都要求**条件与通道语义一致**：
##   「对生命值低于 N% 的**敌人**」→ `execute_line`(105) 是「对低血目标增伤」
##   「被**冻结**敌人」             → `frozen_dmg`(141) 是「对被冻结目标增伤」
##   「**反弹** N% 伤害」           → `reflect`(104) 是「受伤时反伤」
##
## **不能只按通道号放过**：同样是 105，「每层目标受到伤害+5%」是**易伤**
## 而不是处决线，条件不同，仍应报出来。
func _cond_is_intrinsic(text: String, cond: String, spec: String) -> bool:
	# 处决线：只有「对低于N%的敌人」才算内建
	if spec.contains("[105,"):
		return _re(r"对生命值?低于\s*\d+%\s*的敌人").search(text) != null
	# 冻结增伤：只有「被冻结敌人」才算内建
	if spec.contains("[141,"):
		return text.contains("冻结") and text.contains("敌人")
	# 反伤：只有「反弹」才算内建
	if spec.contains("[104,"):
		return text.contains("反弹")
	# 低血词条走 `[4, 11, ...]`——那已被 `_spec_is_unconditional` 排除，
	# 不在这里处理
	return false


## 结果是否是**无条件效果形态**（没有任何触发语义）
##
## 判据：不是触发型 `[2,...]`、不是叠层型 `[4,...]`、也不是技能修饰 `[8,...]`。
## 这些形态的效果值就写在字面量里，可以直接与原文的数字比对。
func _spec_is_unconditional(spec: String) -> bool:
	if spec.begins_with("[2,") or spec.begins_with("[4,") or spec.begins_with("[8,"):
		return false
	return _is_plain_spec(spec)


## 是否裸属性形态（`[Stat.X, v, bool]` / `[NNN, v, true]`）
func _is_plain_spec(spec: String) -> bool:
	return _re(r"^\[(?:[A-Za-z_.]+|\d+),\s*-?[\d.]+,\s*(?:true|false)\]$").search(spec) != null


## STACK_GAIN 形态的第 6 槽（条件阈值；无则 0）
func _threshold_of(spec: String) -> float:
	var m := _re(r"^\[4,\s*\d+,\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*([\d.]+)").search(spec)
	if m:
		return float(m.get_string(1))
	return 0.0


## 解析结果里是否带时长痕迹
func _has_duration(spec: String) -> bool:
	# 参数字典里的时长键（`seconds` 是生成器的写法，`_seconds` 是历史写法）
	if spec.contains("seconds") or spec.contains("duration"):
		return true
	# 触发型 `[2, "id", chance, dur]`——第 4 槽 > 0 即有时长
	var m := _re(r"^\[2,\s*\"[^\"]*\",\s*[\d.]+,\s*([\d.]+)").search(spec)
	if m != null:
		return float(m.get_string(1)) > 0.0
	# 叠层型 `[4, t, stat, v, stack_max]`——stack_max > 0 即有时长语义
	m = _re(r"^\[4,\s*\d+,\s*[^,]+,\s*[^,]+,\s*(\d+)").search(spec)
	if m != null:
		return int(m.get_string(1)) > 0
	return false


## 从原文抽「叠加 N 层」的**上限**
##
## ## 必须优先取「最多/可叠」
##
## 「受到伤害叠加1层"不朽"（最多15层）」里**两个数字都是层数**，
## 含义却相反：`1` 是**每次叠几层**，`15` 才是**上限**。
## 旧实现按出现顺序取第一个 → 拿到 1，于是 20 条词条被误报
## 「原文声明 1 层，解析成 stack_max=15」——**检查器本身的假警报**。
## 上限（`最多/可叠`）才是 `stack_max` 的语义。
func _stack_from_text(t: String) -> int:
	# 优先级 1：「最多/可叠 N 层」= 上限
	var m := _re(r"(?:最多|可叠|最多可叠)\s*(\d+)\s*层").search(t)
	if m:
		return int(m.get_string(1))
	# 优先级 2：「叠加 N 层」——没有「最多」时才当上限用
	m = _re(r"叠加\s*(\d+)\s*层").search(t)
	if m:
		return int(m.get_string(1))
	return 0


## 从原文抽所有百分比数值（字符串形式，保留原样）
func _pcts_from_text(t: String) -> Array:
	var out: Array = []
	for m in _re(r"(\d+(?:\.\d+)?)\s*%").search_all(t):
		out.append(m.get_string(1))
	return out


## 从原文抽**效果量**百分比——剔除条件/结构类数值
##
## 「有 30% 概率使目标移速 -50%」里的 `30%` 是**概率**、`50%` 才是效果。
## 先把非效果片段从文本里抹掉，剩下的百分比才要求出现在解析结果里。
func _effect_pcts_from_text(t: String) -> Array:
	var s := t
	for pat in [
		r"有\s*\d+(?:\.\d+)?%\s*概率",            # 触发概率
		r"(?:生命|血量|生命值)低?于?\s*\d+(?:\.\d+)?%",   # 低血阈值
		r"持续\s*\d+(?:\.\d+)?\s*秒",             # 时长
		r"(?:最多|可叠|叠加)\s*\d+\s*层",           # 层数
		r"\d+\s*层时",                            # 「N层时」
		r"\d+(?:\.\d+)?\s*~\s*\d+(?:\.\d+)?",     # 区间（10~50）
		r"\d+(?:\.\d+)?\s*米",                    # 距离
		r"冷却\s*\d+(?:\.\d+)?\s*秒",             # 冷却
	]:
		s = _re(pat).sub(s, " ", true)
	return _pcts_from_text(s)


## 解析结果里的所有数字（含小数归一）
func _numbers_of(spec: String) -> Array:
	var out: Array = []
	for m in _re(r"\d+(?:\.\d+)?").search_all(spec):
		out.append(m.get_string(0))
	return out


## 结果里是否包含「pct/100」（容差）
func _has_number(nums: Array, pct: String) -> bool:
	var want := float(pct) / 100.0
	for n in nums:
		if absf(float(n) - want) < 0.0005:
			return true
	# 「攻击力提高至60%」这类整体值也算（不按百分比累加）
	return false


## 从规格字面量里取 trigger（`[4, trigger, stat, value, stack_max]`）
##
## **多属性规格**（`[[4, 1, ...], [4, 1, ...]]`）取第一条即可——
## 展开出来的各条 trigger 必然相同。
func _trigger_of(spec: String) -> int:
	var s := spec
	var mm := _re(r"^\s*\[\[\s*4,\s*(\d+),").search(s)
	if mm:
		return int(mm.get_string(1))
	var m := _re(r"^\[4,\s*(\d+),").search(spec)
	if m:
		return int(m.get_string(1))
	# TRIGGER_BUFF 形态 `[2, "buff", chance, duration]`
	if spec.begins_with("[2,"):
		return TRIG_ON_HIT
	# 静态属性形态没有 trigger
	return TRIG_ALWAYS


## 从规格字面量里取 stack_max（STACK_GAIN 的第 5 项）
##
## **不能要求到行尾**：尾部还可能跟第 6 槽（条件阈值）与第 7 槽（参数字典）。
## 旧正则结尾是 `\]`，于是 `[4, 1, Stat.ATK, 0.03, 5, 0]` 匹配失败、
## 被当成 stack_max=0——**检查器自己的假警报**。
func _stack_of(spec: String) -> int:
	var m := _re(r"^\[4,\s*\d+,\s*[^,]+,\s*[^,]+,\s*(\d+)").search(spec)
	if m:
		return int(m.get_string(1))
	# 触发型可以在参数字典里覆盖层数上限（装备参考2：同一条词条
	# 「（最多5层）」vs「（最多8层）」——表定值不够用）
	m = _re(r"\"max_stacks\":\s*(\d+)").search(spec)
	if m:
		return int(m.get_string(1))
	return 0


func _read_trace() -> Array:
	var f := FileAccess.open(TRACE, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_line().replace("\r", "")
		if line.strip_edges().is_empty():
			continue
		var c := line.split("\t")
		if c.size() < 4:
			continue
		out.append({"name": c[0], "col": c[1], "text": c[2], "spec": c[3]})
	f.close()
	return out


func _re(p: String) -> RegEx:
	var r := RegEx.new()
	r.compile(p)
	return r
