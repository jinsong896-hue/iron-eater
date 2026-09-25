extends SceneTree
## 逐件核对：每件装备的词条**是否真的忠实于文档**
##
## ## 为什么需要它
##
## 之前的「无需改动 253 件」是**减法算出来的**（390 − 137），不是逐条验证的。
## 这正是不该偷懒的地方——只有把每一件都过一遍，才能回答
## 「剩下的是否真的没问题」。
##
## ## 分类
##
## 对每件装备的三列词条，逐条判定解析结果属于哪一类：
##   PLAIN    裸属性（`[Stat.X,v,bool]` / `[NNN,v,true]`）—— **无条件**加成
##   TRIGGER  带触发条件的词条（`[4, trigger, ...]` / `[2, "buff", chance, dur]`）
##   MISS     未映射（生成器无规则）
##   SKILL    装备技能的承载（自有列写「主动技能X」）
##
## 然后回答三个问题：
##   ① 有多少件是**纯属性加成**（三列全是 PLAIN）？
##   ② 这些「纯属性」里，有多少件的原文**含触发从句**（= 被压成常驻）？
##   ③ 剩下的「纯属性」原文是否真的无条件？
##
## ## 用法
##
## ```bash
## "$GODOT" --headless --path . --script res://tools/audit_plain_items.gd
## ```

const TRACE := "res://tools/data/parse_trace.txt"
const TSV := "res://tools/data/equipment_spec.tsv"

## 触发从句（与 scan_conditional_stats 同一套判据）
const TRIGGER_CLAUSE := [
	r"^[^，,]{2,20}(?:时|后)[，,]",
	r"^每(?:次|击杀|命中|受到|装备|持有)[^，,]{0,16}[，,]",
	r"^[^，,]{2,16}期间[，,]?",
	r"^[^，,]{2,16}存在时[，,]?",
]

## 本来就该常驻的写法白名单
const UNCONDITIONAL_OK := [
	r"^[^，,]{0,14}(?:概率|几率)(?:增加|提升)",
	r"^[^，,]{0,14}(?:获取量|回复速度|上限|最大值)(?:增加|提升)",
	r"^[^，,]{0,14}(?:获得|增加|提升)\s*\d+(?:\.\d+)?%?\s*(?:的)?(?:攻击力|防御|生命|移速|攻速|暴击|吸血|金币|经验|掉落)",
	r"^[^，,]{0,14}(?:附带|获得)\s*\d+(?:\.\d+)?%",
]


func _init() -> void:
	var trace := _read_trace()
	var doc := _read_tsv()
	print("文档 %d 件，解析追踪 %d 条\n" % [doc.size(), trace.size()])

	# 按装备聚合
	var by_item := {}
	for r in trace:
		var n := str(r["name"])
		if not by_item.has(n):
			by_item[n] = []
		by_item[n].append(r)

	# 分类统计
	var pure_plain: Array = []       # 三列全是裸属性
	var has_trigger: Array = []      # 至少一条带触发
	var has_miss: Array = []         # 至少一条未映射
	var no_trace: Array = []         # 完全没有解析记录

	var pure_plain_but_conditional: Array = []   # 纯属性 且 原文含触发从句
	var pure_plain_ok: Array = []                # 纯属性 且 原文确实无条件

	for d in doc:
		var n := str(d["name"])
		if not by_item.has(n):
			no_trace.append(n)
			continue
		var rows: Array = by_item[n]
		var n_plain := 0
		var n_trig := 0
		var n_miss := 0
		var n_skill := 0
		var cond_texts: Array = []
		for r in rows:
			var spec := str(r["spec"])
			if spec == "__MISS__":
				n_miss += 1
			elif spec == "__SKILL__":
				n_skill += 1
			elif _is_plain(spec):
				n_plain += 1
				var t := str(r["text"])
				if _has_clause(t) and not _is_ok(t):
					cond_texts.append(t)
			else:
				n_trig += 1
		if n_miss > 0:
			has_miss.append(n)
		elif n_plain > 0 and n_trig == 0 and n_skill == 0:
			pure_plain.append(n)
			if cond_texts.is_empty():
				pure_plain_ok.append(n)
			else:
				pure_plain_but_conditional.append(n)
		elif n_trig > 0:
			has_trigger.append(n)

	print("=== 逐件分类 ===")
	print("  三列全是裸属性（纯属性加成）: %d 件" % pure_plain.size())
	print("    其中原文含触发从句（被压成常驻）: %d 件" % pure_plain_but_conditional.size())
	print("    其中原文确实无条件            : %d 件" % pure_plain_ok.size())
	print("  至少一条带触发条件            : %d 件" % has_trigger.size())
	print("  至少一条未映射                : %d 件" % has_miss.size())
	print("  完全没有解析记录              : %d 件" % no_trace.size())

	# —— 逐件审计：给每件一个最终判定 ——
	#
	# 只有把 390 件全部过一遍，才能回答「剩下的是否真的没问题」。
	# 「有触发词条」不等于「触发词条对」——「每击杀一个敌人回复5%生命」
	# 解析成 ON_HIT 就是错的，但它确实带触发。
	var verdict := {}          # name -> 问题类型
	for d in doc:
		var n := str(d["name"])
		if not by_item.has(n):
			verdict[n] = "无解析记录"
			continue
		var rows: Array = by_item[n]
		var problems: Array = []
		for r in rows:
			var spec := str(r["spec"])
			var text := str(r["text"])
			if spec == "__MISS__":
				problems.append("未映射")
				continue
			if spec == "__SKILL__":
				continue
			if _is_plain(spec):
				if _has_clause(text) and not _is_ok(text):
					problems.append("条件压成常驻")
			else:
				# 带触发的，核对触发条件是否与原文一致
				var bad := _trigger_mismatch(text, spec)
				if not bad.is_empty():
					problems.append(bad)
		if not problems.is_empty():
			verdict[n] = ", ".join(problems)

	print("\n=== 最终判定：有问题的装备 %d / %d 件 ===" % [verdict.size(), doc.size()])
	var by_kind := {}
	for n in verdict:
		var k := str(verdict[n])
		by_kind[k] = int(by_kind.get(k, 0)) + 1
	var ks := by_kind.keys(); ks.sort()
	for k in ks:
		print("  %-24s %d" % [k, by_kind[k]])

	print("\n=== 无需改动：%d 件 ===" % (doc.size() - verdict.size()))

	# —— 反向核对：触发词条的类型是否与原文语义一致 ——
	#
	# 上一步只查了「原文有触发词 → 结果是否对应」。这里反向查：
	# 「结果声明了某触发 → 原文是否真有那个条件」。
	# 防止生成器**凭空造出一个触发**（如把常驻加成写成 ON_KILL）。
	var invented: Array[String] = []
	for r in trace:
		var spec := str(r["spec"])
		if spec == "__MISS__" or spec == "__SKILL__":
			continue
		if _is_plain(spec):
			continue
		var trig := _trigger_of(spec)
		if trig < 0:
			continue
		var text := str(r["text"])
		var want := _expected_words(trig)
		if want.is_empty():
			continue
		var found := false
		for w in want:
			if text.contains(w):
				found = true
				break
		if not found:
			invented.append("%s | %s → trigger=%d（原文无对应条件）"
				% [r["name"], text, trig])
	print("\n=== 反向核对：触发条件「凭空出现」的 %d 条 ===" % invented.size())
	for i in mini(invented.size(), 25):
		print("  " + invented[i])

	# —— 最终并集 ——
	#
	# 逐件判定（verdict）+ 反向核对（invented）是**两个方向**的检查，
	# 一件装备可能只在其中一边出问题，故取并集才是最终「需重做」清单。
	for s in invented:
		var n := str(s).split(" | ")[0]
		if not verdict.has(n):
			verdict[n] = "触发条件凭空造"

	# **计数一律按文档条目**（不是按名字）：装备名不唯一，按名字去重
	# 会让各项加起来对不上 390。且必须在并集**之后**统计，
	# 否则反向核对新增的条目会被重复计入「无需改动」。
	var bad_entries := 0
	var clean_pure := 0        # 三列全是裸属性、且原文无条件
	var clean_triggered := 0   # 至少一条带触发（触发条件经双向核对一致）
	for d in doc:
		var n := str(d["name"])
		if verdict.has(n):
			bad_entries += 1
			continue
		var has_trig := false
		for r in by_item.get(n, []):
			var spec := str(r["spec"])
			if spec != "__MISS__" and spec != "__SKILL__" and not _is_plain(spec):
				has_trig = true
		if has_trig:
			clean_triggered += 1
		else:
			clean_pure += 1

	var f := FileAccess.open("res://tools/data/audit_final.txt", FileAccess.WRITE)
	if f != null:
		for n in verdict:
			f.store_line("%s\t%s" % [n, verdict[n]])
		f.close()
	print("\n=== 最终并集：%d / %d 件需重做（按文档条目）===" % [bad_entries, doc.size()])
	print("    无需改动：%d 件" % (doc.size() - bad_entries))
	print("      其中「三列纯属性加成」      : %d 件" % clean_pure)
	print("      其中「带触发条件（已核对）」: %d 件" % clean_triggered)
	print("    明细已写入 tools/data/audit_final.txt")

	quit(0)


## 某 trigger 值对应的原文应含的关键词
##
## **关键词必须覆盖文档的实际写法**——漏一个词就会把正确解析判成错。
## 实测踩到的：
##   「受到**一次**伤害」不含「受到伤害」子串 → 误报 ON_HURT 是凭空造的
##   「**连续**攻击同一目标」不含「连击」 → 误报 ON_COMBO
##   「治疗区域**同时**…」不含「使用技能」 → 误报 ON_SKILL_CAST
func _expected_words(trig: int) -> Array:
	match trig:
		1: return ["击杀", "死亡"]
		2: return ["受到伤害", "受到近战", "受到一次伤害", "受到", "受击"]
		3: return ["命中", "攻击"]
		4: return ["闪避"]
		6: return ["暴击"]
		7: return ["连击", "连续攻击"]
		9: return ["格挡"]
		14: return ["护盾被击破", "被击破"]
		15: return ["护盾存在"]
		16: return ["陷阱触发"]
		17: return ["召唤物存在", "图腾存在", "召唤物"]
		18: return ["使用技能", "施法", "治疗区域", "治疗时", "净化", "同时"]
		19: return ["疾跑", "冲刺"]
		20: return ["嘲讽"]
		21: return ["反击姿态", "格挡"]
		22: return ["旋风斩"]
		23: return ["时间减缓"]
		24: return ["荆棘爆发", "荆棘护盾"]
	return []


## 触发条件与原文是否矛盾（返回问题描述，空串 = 一致）
##
## ## 判据必须**保守**——只报「明确矛盾」，不报「用了更具体的触发」
##
## 初版写得太宽，把下列**正确**解析全判成错：
##   「反击姿态期间受到伤害减少30%」→ `[4, 21]`（ON_BLOCK_STANCE）✅
##   「护盾存在时，受到伤害减少10%」→ `[4, 15]`（SHIELD_UP）✅
##   「嘲讽期间受到伤害减少10%」    → `[4, 20]`（ON_TAUNT）✅
## 它们都含「受到伤害」，但触发条件是**更具体**的那一个，是对的。
##
## 故：原文若含「期间 / 存在时 / 嘲讽 / 格挡 / 姿态 / 隐身」这类
## **更具体的条件**，就不再按「受到伤害」判。
func _trigger_mismatch(text: String, spec: String) -> String:
	# 更具体的条件存在时，不按宽泛条件判
	var has_specific := false
	for w in ["期间", "存在时", "嘲讽", "格挡", "姿态", "隐身", "召唤物", "图腾"]:
		if text.contains(w):
			has_specific = true
			break

	var trig := _trigger_of(spec)

	# ① 原文说「击杀」→ 必须是 ON_KILL(1) 或 AT_FULL(5)
	#    解析成 ON_HIT(3) 是**明确矛盾**（命中即触发 vs 击杀才触发）
	if text.contains("击杀") and not text.contains("击杀时若"):
		if trig == 3:
			return "触发条件错(击杀→命中)"
	# ② 原文说「受到近战/受到伤害」且**无更具体条件** → 应为 ON_HURT(2)
	#    `[2, "buff", ...]` 形态（TRIGGER_BUFF）**没有 trigger 槽位**，
	#    实际按「命中时」施加——对「受到攻击时」的原文是错的。
	if not has_specific and (text.contains("受到近战") or text.contains("受到伤害")):
		if spec.begins_with("[2,"):
			return "触发条件错(受击→按命中施加)"
	# ③ 原文说「暴击时」→ 必须是 ON_CRIT(6)
	if text.contains("暴击时") and trig != 6 and trig != -1:
		return "触发条件错(暴击→%d)" % trig
	# ④ 原文说「闪避时」→ 必须是 ON_DODGE(4)
	if text.contains("闪避时") and trig != 4 and trig != -1:
		return "触发条件错(闪避→%d)" % trig
	return ""


## 取规格里的 trigger 槽位（非 STACK_GAIN 形态返回 -1）
func _trigger_of(spec: String) -> int:
	var m := _re(r"^\[4,\s*(\d+),").search(spec)
	if m:
		return int(m.get_string(1))
	return -1


## 解析结果是否为裸属性
func _is_plain(spec: String) -> bool:
	return _re(r"^\[(?:Stat\.[A-Z]+|\d+),\s*-?[\d.]+,\s*(?:true|false)\]$").search(spec) != null


func _has_clause(text: String) -> bool:
	for p: String in TRIGGER_CLAUSE:
		if _re(p).search(text) != null:
			return true
	return false


func _is_ok(text: String) -> bool:
	for p: String in UNCONDITIONAL_OK:
		if _re(p).search(text) != null:
			return true
	return false


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


func _read_tsv() -> Array:
	var f := FileAccess.open(TSV, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_line().replace("\r", "")
		if line.strip_edges().is_empty():
			continue
		var c := line.split("\t")
		if c.size() < 8 or c[0] != "PASS":
			continue
		out.append({"name": c[4], "rarity": c[1], "own": c[5], "devour": c[6], "fusion": c[7]})
	f.close()
	return out


func _re(p: String) -> RegEx:
	var r := RegEx.new()
	r.compile(p)
	return r
