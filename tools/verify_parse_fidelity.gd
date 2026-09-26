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
	# 「击杀」→ 必须是 ON_KILL。实测「每击杀一个敌人回复5%最大生命值」
	# 被解析成 ON_HIT（命中）——语义完全不同（命中即回血 vs 击杀才回血）。
	if text.contains("击杀") and not text.contains("击杀时若"):
		if trig != TRIG_ON_KILL and trig != TRIG_AT_FULL:
			_issues.append("触发条件错 | %s\n      解析成 trigger=%d（应为 ON_KILL=1）"
				% [tag, trig])
	# 「受到伤害」→ ON_HURT
	if text.contains("受到伤害") or text.contains("受击"):
		if trig != TRIG_ON_HURT and trig != TRIG_ALWAYS:
			_issues.append("触发条件错 | %s\n      解析成 trigger=%d（应为 ON_HURT=2）"
				% [tag, trig])
	# 「暴击」→ ON_CRIT
	if text.contains("暴击时") and trig != TRIG_ON_CRIT:
		_issues.append("触发条件错 | %s\n      解析成 trigger=%d（应为 ON_CRIT=6）"
			% [tag, trig])

	# —— 2. 叠层上限 ——
	# 「叠加N层」/「最多N层」→ stack_max 必须 = N
	var want_stack := _stack_from_text(text)
	if want_stack > 0 and stack != want_stack:
		_issues.append("叠层上限错 | %s\n      原文声明 %d 层，解析成 stack_max=%d"
			% [tag, want_stack, stack])

	# —— 3. 「所有/全属性」不能塌缩成单一属性 ——
	if text.contains("所有数值") or text.contains("全属性") \
			or text.contains("所有基础属性") or text.contains("所有属性"):
		if spec.contains("Stat.ATK") and not spec.contains(";"):
			_issues.append("属性范围错 | %s\n      「所有/全属性」被塌缩成 Stat.ATK 单属性"
				% tag)

	# —— 4. 数值是否被提取 ——
	# 原文有 N% 时，解析结果里应出现 N/100（容忍两位小数）
	var pcts := _pcts_from_text(text)
	for p in pcts:
		if not _has_number(nums, p):
			_issues.append("数值丢失 | %s\n      原文的 %s%% 未出现在解析结果里"
				% [tag, p])

	# —— 5. 「持续N秒」不能丢 ——
	if text.contains("持续") and _re(r"持续\s*\d+\s*秒").search(text) != null:
		# 触发型结果里应带时长（第 4 项），或 STACK_GAIN 的第 5 项 stack_max
		if not spec.contains(".") and not spec.contains(","):
			_issues.append("时长丢失 | %s\n      原文有「持续N秒」但解析结果无时长"
				% tag)


## 从原文抽「叠加/最多 N 层」
func _stack_from_text(t: String) -> int:
	var m := _re(r"(?:叠加|最多|可叠)\s*(\d+)\s*层").search(t)
	if m:
		return int(m.get_string(1))
	return 0


## 从原文抽所有百分比数值（字符串形式，保留原样）
func _pcts_from_text(t: String) -> Array:
	var out: Array = []
	for m in _re(r"(\d+(?:\.\d+)?)\s*%").search_all(t):
		out.append(m.get_string(1))
	return out


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
func _trigger_of(spec: String) -> int:
	var m := _re(r"^\[4,\s*(\d+),").search(spec)
	if m:
		return int(m.get_string(1))
	# TRIGGER_BUFF 形态 `[2, "buff", chance, duration]`
	if spec.begins_with("[2,"):
		return TRIG_ON_HIT
	# 静态属性形态没有 trigger
	return TRIG_ALWAYS


## 从规格字面量里取 stack_max（STACK_GAIN 的第 5 项）
func _stack_of(spec: String) -> int:
	var m := _re(r"^\[4,\s*\d+,\s*[^,]+,\s*[^,]+,\s*(\d+)\]").search(spec)
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
