extends SceneTree
## 装备设定表提取器 —— 从 `ai/装备参考.txt` 完整提取所有装备条目
##
## ## 为什么重写
##
## 现有的 `tools/data/equipment_spec.tsv` **只覆盖了文档的一部分**：
## 文档装备区有 400 条，TSV 只有 349 条——**51 条从未进入流水线**，
## 所以「实机和文档不一样」的根因之一就是数据源本身不全。
##
## 本脚本直接读文档原文，按条目块解析，**不做任何筛选或猜测**：
## 文档里写了什么就提取什么，字段缺失就留空（由后续步骤报告）。
##
## ## 文档结构
##
## ```
## 1. 被腐蚀的长剑（精良）
## 类型：单手剑
##
## 自有词条：每击杀一个敌人，该武器所有数值增加1%
## 吞噬词条：角色所有基础属性增加0.5%
## 融合词条：获得被动——每击杀一个敌人，全属性增加10%
## ```
##
## 字段名有**变体**（实测统计）：
##   · 自有词条(393) / **核心机制(40)** —— 同一个字段的两种写法
##   · 吞噬词条(436)、融合词条(435)
##   · 类型(223)、体系方向(121)、核心流派(30)、说明(100)
##
## ## 用法
##
## ```bash
## "$GODOT" --headless --path . --script res://tools/extract_equipment_spec.gd
## ```
##
## 输出到 stdout：制表符分隔的 TSV（8 列，与现有 spec 同格式）
## 输出到 stderr：统计与异常报告

const SRC := "res://ai/装备参考.txt"
const OUT_PATH := "res://tools/data/equipment_spec.tsv"
## 人可读的设定表（Markdown），供策划核对
const OUT_MD := "res://ai/装备设定表.md"

## 装备区范围（行号，含端点）
##
## 文档前半是装备（512-6878），后半是技能（6879 起，标题形如
## 「一、主动技能（7个）」）。**必须按行号切**——两区的条目编号都从 1 重启，
## 光看编号无法区分。
const EQUIP_START := 512
const EQUIP_END := 6878

## **草稿剔除规则**：每个小节标题声明了件数（「一、武器类（10件）」），
## **只保留该小节的前 N 条**——超出的都是文档作者的草稿。
##
## ## 为什么这是可靠的
##
## 实测 49 个小节里 **47 个的条目数与声明完全吻合**，只有两处超量：
##   · 「三、饰品类（4件）」(658) —— 实际 24 条（含 823-1045 的草稿块 20 条）
##   · 「三、饰品类（10件）」(3148) —— 实际 20 条（含 3354-3470 的草稿块 10 条）
##
## 两个草稿块都能被「文档自己的声明」精确定位，无需靠内容启发式猜测。
## 草稿块的标志是文档里的思考过程文字（「实际上，让我重新考虑…」
## 「让我来设计10件紫色装备」），且与后面的正式块**同名同数量**。
##
## 保留草稿会生成 30 件重复装备（文档共 58 组重名，其余 28 组是
## 设计上就存在的跨稀有度同名，如「守护护符」精良与稀有各一件）。

## 字段名 → 归一化名（处理文档里的多种写法）
const FIELD_ALIAS := {
	"自有词条": "own", "核心机制": "own",
	"吞噬词条": "devour", "融合词条": "fusion",
	"类型": "type", "体系方向": "system", "核心流派": "system", "体系": "system",
}

## 稀有度中文 → TSV 的英文标识
##
## 文档有两种写法：`（精良）` 与 `（紫色单手剑）`——后者把稀有度和类型
## 挤在同一对括号里（「紫色」是**稀有度**，后面的才是类型）。
## 故用 `begins_with` 匹配前缀，而不是全等。
const RARITY_EN := {
	"精良": "GREEN", "稀有": "BLUE", "史诗": "PURPLE", "传奇": "ORANGE",
	"紫色": "PURPLE", "红色": "ORANGE",
}

## 类型 → (类别, 武器类型) 映射
##
## 类别：WEAPON / ARMOR / ACCESSORY
## 武器类型：EquipmentDefs 的 weapon_type 值（非武器留空）
const TYPE_MAP := {
	"单手剑": ["WEAPON", "sword"], "双手剑": ["WEAPON", "greatsword"],
	"匕首": ["WEAPON", "dagger"], "单手锤": ["WEAPON", "axe"],
	"单手斧": ["WEAPON", "axe"], "双手斧": ["WEAPON", "greataxe"],
	"长矛": ["WEAPON", "spear"], "长枪": ["WEAPON", "spear"],
	"法杖": ["WEAPON", "staff"], "法器": ["WEAPON", "staff"],
	"弓": ["WEAPON", "bow"], "长弓": ["WEAPON", "bow"],
	"弩": ["WEAPON", "crossbow"], "重弩": ["WEAPON", "heavy_crossbow"],
	"盾牌": ["WEAPON", "shield"], "盾": ["WEAPON", "shield"],
	"战镰": ["WEAPON", "scythe"], "镰刀": ["WEAPON", "scythe"],
	"双持斧": ["WEAPON", "greataxe"], "链刃": ["WEAPON", "sword"],
	"长剑": ["WEAPON", "sword"], "巨斧": ["WEAPON", "greataxe"],
	"双手锤": ["WEAPON", "greataxe"], "巨锤": ["WEAPON", "greataxe"],
}

## 防具/饰品类型 → 槽位
const SLOT_MAP := {
	"头盔": "HEAD", "胸甲": "CHEST", "肩甲": "SHOULDERS",
	"护手": "HANDS", "腿甲": "LEGS", "鞋子": "FEET", "战靴": "FEET",
	"戒指": "ACCESSORY_1", "项链": "ACCESSORY_1", "护符": "ACCESSORY_1",
	"徽章": "ACCESSORY_1", "饰品": "ACCESSORY_1", "法环": "ACCESSORY_1",
}

var _stats := {}
var _problems: Array[String] = []
## 被「声明件数」规则剔除的草稿条数
var _dropped := 0


func _init() -> void:
	var lines := _read_lines()
	if lines.is_empty():
		push_error("读不到文档：%s" % SRC)
		quit(1)
		return
	print("文档共 %d 行" % lines.size())

	var items := _parse_items(lines)
	print("解析出 %d 条装备\n" % items.size())

	_write_tsv(items)
	_write_markdown(items)
	_report(items)
	quit(0 if _problems.is_empty() else 1)


## 读全部行（**必须去 `\r`**：文档混了 CRLF，`get_line()` 把 `\r`
## 也当行终止符，会让每行末尾多一个不可见字符，字段值带上 `\r`）
func _read_lines() -> Array[String]:
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		return []
	var out: Array[String] = []
	while not f.eof_reached():
		out.append(f.get_line().replace("\r", ""))
	f.close()
	return out


## 按小节 + 条目块解析
##
## 先切小节（标题行 `一、武器类（10件）`），再在小节内切条目，
## 最后**只保留声明件数以内的条目**（见 `EQUIP_START` 上方的说明）。
func _parse_items(lines: Array[String]) -> Array:
	var sections := _split_sections(lines)
	var items: Array = []
	var dropped := 0
	for sec in sections:
		var starts := _item_starts(lines, int(sec["start"]), int(sec["end"]))
		# 只取前 `declared` 条——超出的都是草稿
		var declared: int = int(sec["declared"])
		if declared > 0 and starts.size() > declared:
			dropped += starts.size() - declared
			starts = starts.slice(0, declared)
		for idx in starts.size():
			var s: Dictionary = starts[idx]
			var end_line: int = int(starts[idx + 1]["line"]) if idx + 1 < starts.size() \
				else int(sec["end"]) + 1
			var fields := _collect_fields(lines, int(s["line"]), end_line)
			var it := _to_item(s, fields)
			it["section"] = str(sec["title"])
			items.append(it)
	_dropped = dropped
	return items


## 切分小节：返回 [{title, declared, start, end}]
##
## 小节起点 = 形如 `一、武器类（10件）` 的行；`declared` 从括号里的
## 「N件」提取。`start` 是该标题的下一行。
func _split_sections(lines: Array[String]) -> Array:
	var out: Array = []
	var cur := {}
	for i in lines.size():
		var ln := i + 1
		if ln < EQUIP_START or ln > EQUIP_END:
			continue
		var m := _re(r"^[一二三四五六七八九十]+、\S.*（\s*(\d+)\s*件\s*）").search(lines[i])
		if m == null:
			continue
		if not cur.is_empty():
			cur["end"] = ln - 1
			out.append(cur)
		cur = {
			"title": lines[i].strip_edges(),
			"declared": int(m.get_string(1)),
			"start": ln + 1,
		}
	if not cur.is_empty():
		cur["end"] = EQUIP_END
		out.append(cur)
	return out


## 取区间内的条目起点
func _item_starts(lines: Array[String], start: int, end: int) -> Array:
	var out: Array = []
	for ln in range(start, mini(end, lines.size()) + 1):
		var m := _re(r"^(\d+)\.\s*(.+?)（([^）]+)）").search(lines[ln - 1])
		if m:
			out.append({
				"line": ln, "num": int(m.get_string(1)),
				"name": m.get_string(2).strip_edges(),
				"rarity_raw": m.get_string(3).strip_edges(),
			})
	return out


## 收集一个块内的字段（到下一个条目起点为止）
func _collect_fields(lines: Array[String], start: int, end: int) -> Dictionary:
	var out := {}
	for ln in range(start, mini(end, lines.size() + 1)):
		var line: String = lines[ln - 1]
		var m := _re(r"^([^：:]{2,12})[：:]\s*(.*)$").search(line)
		if m == null:
			continue
		var key := str(m.get_string(1)).strip_edges()
		if not FIELD_ALIAS.has(key):
			continue
		var norm: String = FIELD_ALIAS[key]
		var val := str(m.get_string(2)).strip_edges()
		# 同名字段重复出现时保留第一条（文档里偶有重复行）
		if not out.has(norm):
			out[norm] = val
	return out


## 归一化成一条装备记录
func _to_item(start: Dictionary, f: Dictionary) -> Dictionary:
	var name := str(start["name"])
	var rar_raw := str(start["rarity_raw"])
	# 稀有度可能带后缀（「史诗·法杖」「紫色单手剑」），取前缀匹配
	var rar := ""
	for k in RARITY_EN:
		if rar_raw.begins_with(k):
			rar = RARITY_EN[k]
			break
	if rar.is_empty():
		_problems.append("%s：稀有度无法识别（原文「%s」）" % [name, rar_raw])

	# 类型 → 类别 + 武器类型/槽位
	#
	# **类型有两个来源**（实测：390 条里 190 条没有 `类型：` 字段）：
	#   ① 块内的 `类型：单手剑`
	#   ② 条目标题的稀有度括号，形如 `（史诗·双手剑）`——「·」后面就是类型
	# 只查 ① 会让 190 条落到「类型无法识别」并被误判成饰品。
	var t_raw := str(f.get("type", ""))
	if t_raw.is_empty():
		var dot := rar_raw.find("·")
		if dot >= 0:
			t_raw = rar_raw.substr(dot + 1).strip_edges()
	var cat := ""
	var wtype := ""
	var slot := ""
	for k in TYPE_MAP:
		if t_raw.contains(k):
			cat = TYPE_MAP[k][0]
			wtype = TYPE_MAP[k][1]
			break
	if cat.is_empty():
		for k in SLOT_MAP:
			if t_raw.contains(k):
				cat = "ACCESSORY" if SLOT_MAP[k].begins_with("ACCESSORY") else "ARMOR"
				slot = SLOT_MAP[k]
				break
	if cat.is_empty():
		_problems.append("%s：类型无法识别（原文「%s」）" % [name, t_raw])
		cat = "ACCESSORY"
		slot = "ACCESSORY_1"

	return {
		"name": name, "rarity": rar, "cat": cat,
		"wtype": wtype, "slot": slot,
		"own": str(f.get("own", "")),
		"devour": str(f.get("devour", "")),
		"fusion": str(f.get("fusion", "")),
		"type_raw": t_raw,
		"system": str(f.get("system", "")),
	}


## 写 TSV（8 列，与现有 spec 同格式，供 gen_equipment.gd 消费）
func _write_tsv(items: Array) -> void:
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("写不了输出文件：%s" % OUT_PATH)
		return
	for it in items:
		var cols: Array = [
			"PASS", it["rarity"], it["cat"], it["wtype"], it["name"],
			it["own"], it["devour"], it["fusion"],
		]
		# 字段里若含制表符/换行会破坏 TSV，替换成空格
		var clean: Array = []
		for c in cols:
			clean.append(str(c).replace("\t", " ").replace("\n", " "))
		f.store_line("\t".join(clean))
	f.close()
	print("已写入 %s（%d 行）" % [OUT_PATH, items.size()])


## 写人可读的设定表（Markdown）
##
## 按「小节 → 条目」组织，每条列出类型、体系方向与三列词条原文。
## 用途是**让策划能一眼核对「代码里的装备是否就是文档写的」**——
## TSV 是给生成器吃的，这个才是给人看的。
func _write_markdown(items: Array) -> void:
	var f := FileAccess.open(OUT_MD, FileAccess.WRITE)
	if f == null:
		push_error("写不了输出文件：%s" % OUT_MD)
		return
	f.store_line("# 装备设定表")
	f.store_line("")
	f.store_line("> 由 `tools/extract_equipment_spec.gd` 从 `ai/装备参考.txt` 自动提取。")
	f.store_line("> **请勿手工编辑**——改文档后重跑脚本即可。")
	f.store_line(">")
	f.store_line("> 共 %d 件。已剔除文档中的 %d 条草稿（每个小节的声明件数之外的部分）。"
		% [items.size(), _dropped])
	f.store_line("")

	# 按小节分组（保持文档顺序）
	var by_sec := {}
	var order: Array = []
	for it in items:
		var s := str(it.get("section", ""))
		if not by_sec.has(s):
			by_sec[s] = []
			order.append(s)
		by_sec[s].append(it)

	for s in order:
		f.store_line("## %s" % s)
		f.store_line("")
		for it in by_sec[s]:
			f.store_line("### %s（%s）" % [it["name"], _rarity_cn(str(it["rarity"]))])
			f.store_line("")
			f.store_line("- **类型**：%s" % (str(it["type_raw"]) if not str(it["type_raw"]).is_empty() else "—"))
			if not str(it["system"]).is_empty():
				f.store_line("- **体系方向**：%s" % it["system"])
			f.store_line("- **自有词条**：%s" % it["own"])
			f.store_line("- **吞噬词条**：%s" % it["devour"])
			f.store_line("- **融合词条**：%s" % it["fusion"])
			f.store_line("")
	f.close()
	print("已写入 %s" % OUT_MD)


## 英文稀有度 → 中文（Markdown 显示用）
func _rarity_cn(r: String) -> String:
	for k in RARITY_EN:
		if RARITY_EN[k] == r and k.length() <= 2:
			return k
	return r


## 统计报告
func _report(items: Array) -> void:
	var by_rar := {}
	var by_cat := {}
	var empty_own := 0
	var empty_dev := 0
	var empty_fus := 0
	for it in items:
		var r := str(it["rarity"])
		by_rar[r] = int(by_rar.get(r, 0)) + 1
		var c := str(it["cat"])
		by_cat[c] = int(by_cat.get(c, 0)) + 1
		if str(it["own"]).is_empty():
			empty_own += 1
		if str(it["devour"]).is_empty():
			empty_dev += 1
		if str(it["fusion"]).is_empty():
			empty_fus += 1

	printerr("\n=== 稀有度分布 ===")
	var ks := by_rar.keys(); ks.sort()
	for k in ks:
		printerr("  %-8s %d" % [k, by_rar[k]])
	printerr("=== 类别分布 ===")
	var cs := by_cat.keys(); cs.sort()
	for k in cs:
		printerr("  %-10s %d" % [k, by_cat[k]])
	printerr("=== 空字段 ===")
	printerr("  自有词条为空 %d" % empty_own)
	printerr("  吞噬词条为空 %d" % empty_dev)
	printerr("  融合词条为空 %d" % empty_fus)
	printerr("=== 无法识别（%d）===" % _problems.size())
	for p in _problems:
		printerr("  " + p)
	printerr("=== 小节清单（声明件数）===")
	var secs := _split_sections(_read_lines())
	var sum := 0
	for s in secs:
		printerr("  %-36s %d" % [str(s["title"]), int(s["declared"])])
		sum += int(s["declared"])
	printerr("  小节数 %d，声明合计 %d，实际提取 %d，剔除草稿 %d" % [
		secs.size(), sum, items.size(), _dropped])


func _re(pattern: String) -> RegEx:
	var r := RegEx.new()
	r.compile(pattern)
	return r
