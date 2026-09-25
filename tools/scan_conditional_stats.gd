extends SceneTree
## 条件型词条被压成常驻属性 —— 全量扫描
##
## ## 判据
##
## 文档里很多词条是**条件型**的：
##   「生命值低于30%时，吸血效果提升20%」
##   「击杀敌人后，移动速度增加20%，持续3秒」
##   「受到近战攻击时，对攻击者造成50%攻击力的伤害」
##
## 它们都含一个**触发从句**（「X 时，」「X 后，」）——而**常驻属性**
## 表达不了这个语义。若解析结果是一条裸属性（`[Stat.X, v, bool]` 或
## `[NNN, v, true]`），则触发条件被**静默丢弃**，词条变成无条件永久生效。
##
## ## 与「概率型」的区别
##
## 「概率型」（有 N% 概率）是本工具的一个子集：概率本身也是触发条件。
## 但**条件型更广**——「生命值低于30%时」没有概率，同样是条件。
##
## ## 用法
##
## ```bash
## "$GODOT" --headless --path . --script res://tools/scan_conditional_stats.gd
## ```

const TRACE := "res://tools/data/parse_trace.txt"

## 触发从句的正则：主句之前的条件部分
##
## 覆盖文档里的实际写法（实测归纳）：
##   「生命值低于30%时，…」「击杀敌人后，…」「受到伤害时，…」
##   「冰冻敌人时，…」「使用技能时，…」「出售装备时，…」
##   「召唤物存在时，…」「生命满时，…」「格挡时，…」「闪避时，…」
const TRIGGER_CLAUSE := [
	r"^[^，,]{2,20}(?:时|后)[，,]",
	r"^每(?:次|击杀|命中|受到|装备|持有)[^，,]{0,16}[，,]",
	r"^[^，,]{2,16}期间[，,]?",
	r"^[^，,]{2,16}存在时[，,]?",
]

## 「无条件陈述」的白名单：这些**本来就该**是常驻属性
##
## 不排掉会产生大量误报——它们描述的就是「永久/持续生效的加成」。
const UNCONDITIONAL_OK := [
	r"^[^，,]{0,12}(?:概率|几率)增加",
	r"^[^，,]{0,12}(?:概率|几率)提升",
	r"^[^，,]{0,12}获取量增加",
	r"^[^，,]{0,12}回复速度增加",
	r"^[^，,]{0,12}(?:上限|最大值)增加",
	r"^[^，,]{0,12}(?:获得|增加|提升)\s*\d+(?:\.\d+)?%?\s*(?:的)?(?:攻击力|防御|生命|移速|攻速|暴击|吸血|金币|经验|掉落)",
	r"^[^，,]{0,12}(?:附带|获得)\s*\d+(?:\.\d+)?%",
]

var _hits: Array[String] = []


func _init() -> void:
	var rows := _read_trace()
	print("读取 %d 条\n" % rows.size())

	var plain_total := 0
	for r in rows:
		var spec := str(r["spec"])
		if spec == "__MISS__" or spec == "__SKILL__":
			continue
		if not _is_plain_stat(spec):
			continue
		plain_total += 1
		var text := str(r["text"])
		if not _has_trigger_clause(text):
			continue
		if _is_unconditional_ok(text):
			continue
		_hits.append("%s\t%s\t%s\t%s" % [r["name"], r["col"], text, spec])

	print("裸属性（常驻）解析结果共 %d 条" % plain_total)
	print("=== 其中「原文带触发从句」的：%d 条 ===\n" % _hits.size())

	var by_item := {}
	for h in _hits:
		by_item[h.split("\t")[0]] = true
	print("影响装备（去重）：%d 件\n" % by_item.size())

	# 按从句类型分组展示
	var groups := {
		"生命/血量条件": [], "击杀条件": [], "受击/格挡/闪避": [],
		"施法/使用技能": [], "召唤物/存在期间": [], "其他": [],
	}
	for h in _hits:
		var t := h.split("\t")[2]
		if t.contains("生命值低于") or t.contains("生命低于") or t.contains("满血") or t.contains("生命满"):
			groups["生命/血量条件"].append(h)
		elif t.contains("击杀"):
			groups["击杀条件"].append(h)
		elif t.contains("受到") or t.contains("格挡") or t.contains("闪避"):
			groups["受击/格挡/闪避"].append(h)
		elif t.contains("使用技能") or t.contains("释放技能") or t.contains("施法"):
			groups["施法/使用技能"].append(h)
		elif t.contains("存在时") or t.contains("召唤物") or t.contains("期间"):
			groups["召唤物/存在期间"].append(h)
		else:
			groups["其他"].append(h)

	for g in groups:
		var arr: Array = groups[g]
		if arr.is_empty():
			continue
		print("--- %s（%d 条）---" % [g, arr.size()])
		for h in arr:
			var p: PackedStringArray = str(h).split("\t")
			print("  %s | %s" % [p[0], p[2]])
			print("      → %s" % p[3])
		print("")

	# 落盘
	var f := FileAccess.open("res://tools/data/conditional_stats.txt", FileAccess.WRITE)
	if f != null:
		for h in _hits:
			f.store_line(h)
		f.close()
		print("明细已写入 tools/data/conditional_stats.txt")

	quit(0)


## 解析结果是否为「裸属性」（无触发、无概率、无时长）
func _is_plain_stat(spec: String) -> bool:
	# [Stat.X, v, bool] 或 [NNN, v, true/false]
	var m := _re(r"^\[(?:Stat\.[A-Z]+|\d+),\s*-?[\d.]+,\s*(?:true|false)\]$").search(spec)
	return m != null


## 原文是否含触发从句
func _has_trigger_clause(text: String) -> bool:
	for p: String in TRIGGER_CLAUSE:
		if _re(p).search(text) != null:
			return true
	return false


## 是否属于「本来就该常驻」的白名单
func _is_unconditional_ok(text: String) -> bool:
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


func _re(p: String) -> RegEx:
	var r := RegEx.new()
	r.compile(p)
	return r
