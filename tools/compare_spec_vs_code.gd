extends SceneTree
## 装备设定表 ↔ 游戏实际代码 对比
##
## ## 三方对照
##
##   ① `tools/data/equipment_spec.tsv` —— **文档设定表**（权威）
##   ② `tools/_gen_out.gd` —— 生成器对文档的**解析结果**（文档文本 → 词条规格）
##   ③ `data/equipment/equipment_db.gd` 的 CURATED_TABLE —— **游戏实际数据**
##
## ## 为什么不能只用「名字」配对
##
## 装备名**不唯一**：实测有 58 组重名，其中一部分是**同名同稀有度**
##（如「猎人标记徽章」蓝色出现两次）。用名字做键会互相覆盖，
## 导致「两边都有 361 件」却只有 346 件代码这种自相矛盾的结论。
##
## 故按 **(名字, 稀有度, 该组合内的出现序号)** 三元组配对。
##
## ## 用法
##
## ```bash
## "$GODOT" --headless --path . --script res://tools/compare_spec_vs_code.gd
## ```

const TSV := "res://tools/data/equipment_spec.tsv"
const GEN_OUT := "res://tools/_gen_out.gd"


func _init() -> void:
	var doc := _read_tsv()
	var gen := _read_gen_out()
	EquipmentDB.init_equipment_db()
	var code := _read_code()

	print("① 文档设定表   : %d 件" % doc.size())
	print("② 生成器解析结果: %d 件" % gen.size())
	print("③ 游戏实际代码  : %d 件\n" % code.size())

	# ---- 文档 → 生成器：解析覆盖率 ----
	_cmp_layers(doc, gen, "① 文档", "② 生成器解析")

	# ---- 生成器 → 代码：是否已应用 ----
	_cmp_layers(gen, code, "② 生成器解析", "③ 游戏代码")

	quit(0)


## 两层对比：左层有、右层没有的，以及两边都有但内容不同的
func _cmp_layers(left: Array, right: Array, lname: String, rname: String) -> void:
	var lk := _index(left)
	var rk := _index(right)

	var only_left: Array = []
	var diff: Array = []
	var same := 0
	for key in lk:
		if not rk.has(key):
			only_left.append(lk[key])
			continue
		var a: Dictionary = lk[key]
		var b: Dictionary = rk[key]
		if _affixes_equal(a, b):
			same += 1
		else:
			diff.append({"left": a, "right": b})

	var only_right: Array = []
	for key in rk:
		if not lk.has(key):
			only_right.append(rk[key])

	print("=== %s → %s ===" % [lname, rname])
	print("  内容一致      : %d" % same)
	print("  词条不一致    : %d  ← 需重做" % diff.size())
	print("  %s 独有      : %d" % [lname, only_left.size()])
	print("  %s 独有      : %d" % [rname, only_right.size()])

	if not only_left.is_empty():
		print("\n  -- 只在 %s 里（缺失）--" % lname)
		for it in only_left:
			print("    [%s] %s" % [it.get("rarity", "?"), it.get("name", "?")])

	if not diff.is_empty():
		print("\n  -- 词条不一致（前 20 条）--")
		for i in mini(diff.size(), 20):
			var d: Dictionary = diff[i]
			print("    [%s] %s" % [d["left"].get("rarity", "?"), d["left"].get("name", "?")])
			print("        文档: %s" % _brief(d["left"]))
			print("        代码: %s" % _brief(d["right"]))

	if not only_right.is_empty():
		print("\n  -- 只在 %s 里（残留）--" % rname)
		for it in only_right:
			print("    [%s] %s" % [it.get("rarity", "?"), it.get("name", "?")])
	print("")


## 建索引：(名字, 稀有度, 该组合内出现序号) → 条目
func _index(items: Array) -> Dictionary:
	var seen := {}
	var out := {}
	for it in items:
		var base := "%s|%s" % [str(it.get("name", "")), str(it.get("rarity", ""))]
		var n: int = int(seen.get(base, 0))
		seen[base] = n + 1
		out["%s#%d" % [base, n]] = it
	return out


## 三列词条是否等价
##
## 文档层是**原文文本**，代码层是**词条规格字面量**，两者形态不同，
## 无法直接比字符串。故用「规范化签名」：
##   · 文档层：把原文里的数字抽出来（这是词条的数值）
##   · 代码层：把规格里的数字抽出来
## 数值集合一致即视为等价（**这是粗比对**，用于统计规模；
## 精确到语义的核对要靠生成器的「无法映射」报告）。
func _affixes_equal(a: Dictionary, b: Dictionary) -> bool:
	return _sig(a) == _sig(b)


func _sig(it: Dictionary) -> String:
	var nums: Array = []
	for col in ["own", "devour", "fusion"]:
		var txt := str(it.get(col, ""))
		var rx := _re(r"(\d+(?:\.\d+)?)\s*%?")
		var all := rx.search_all(txt)
		for m in all:
			nums.append(m.get_string(1))
	nums.sort()
	return ",".join(nums)


func _brief(it: Dictionary) -> String:
	var parts: Array = []
	for col in ["own", "devour", "fusion"]:
		var t := str(it.get(col, ""))
		parts.append(t.substr(0, 40))
	return " | ".join(parts)


## 读新 TSV
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
		out.append({
			"name": c[4], "rarity": c[1], "cat": c[2], "wtype": c[3],
			"own": c[5], "devour": c[6], "fusion": c[7],
		})
	f.close()
	return out


## 读生成器产出：从 `["G000", "名字", ..., [[...]], [[...]], [[...]]],` 行里
## 抽出名字 + 最后三列词条
##
## **不用整行正则**：行里有嵌套的 `[[...]]`（基础属性、标签数组），
## 正则容易切错。改为从行尾往前扫，找最后三个 `[[` 的起点——
## 它们必然是 own / devour / fusion 三列（生成器的列序固定）。
func _read_gen_out() -> Array:
	var f := FileAccess.open(GEN_OUT, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_line().replace("\r", "").strip_edges()
		if not line.begins_with("[\""):
			continue
		var nm := _re(r'^\["[A-Z]\d+",\s*"([^"]+)"').search(line)
		if nm == null:
			continue
		# 从行尾往前找三个 `[[`
		var idx: Array = []
		var pos := line.length()
		while idx.size() < 3:
			pos = line.rfind("[[", pos - 1)
			if pos < 0:
				break
			idx.append(pos)
		if idx.size() < 3:
			continue
		idx.reverse()                       # 现在是 [own, devour, fusion] 的起点
		var cols: Array = []
		for i in idx.size():
			var endp: int = idx[i + 1] if i + 1 < idx.size() else line.length()
			cols.append(line.substr(idx[i], endp - idx[i]).strip_edges().trim_suffix(","))
		var idm := _re(r'^\["([A-Z])\d+"').search(line)
		var prefix := idm.get_string(1) if idm != null else "?"
		var rar: String = str({"G": "GREEN", "B": "BLUE", "P": "PURPLE",
			"O": "ORANGE"}.get(prefix, "?"))
		out.append({
			"name": nm.get_string(1), "rarity": rar,
			"own": cols[0], "devour": cols[1], "fusion": cols[2],
		})
	f.close()
	return out


## 读游戏实际代码（CURATED_TABLE → EquipmentDB 解析后的对象）
func _read_code() -> Array:
	var out: Array = []
	for t in EquipmentDB.all_templates():
		var id := str(t.id)
		if not (id.length() >= 2 and id.substr(1, 1).is_valid_int()
				and id.substr(0, 1) in "GBPO"):
			continue
		out.append({
			"name": t.display_name, "rarity": _rarity_key(int(t.rarity)),
			"own": _affix_text(t.own_affixes),
			"devour": _affix_text(t.devour_affixes),
			"fusion": _affix_text(t.fusion_affixes),
		})
	return out


## 词条数组 → 文本（把 stat 枚举值还原成数字，便于与文档数值比对）
##
## **只抽数值**：`[4, 1, Stat.ATK, 0.0100, 10]` → "1 0.01 10"
func _affix_text(arr: Array) -> String:
	var parts: Array = []
	for a in arr:
		if a == null:
			continue
		parts.append("%s %s %s" % [a.stat, a.value, a.stack_max])
	return " ; ".join(parts)


func _rarity_key(r: int) -> String:
	match r:
		EquipmentDefs.Rarity.GREEN: return "GREEN"
		EquipmentDefs.Rarity.BLUE: return "BLUE"
		EquipmentDefs.Rarity.PURPLE: return "PURPLE"
		EquipmentDefs.Rarity.ORANGE: return "ORANGE"
	return "?"


func _re(p: String) -> RegEx:
	var r := RegEx.new()
	r.compile(p)
	return r
