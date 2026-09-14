class_name DebugParser
extends RefCounted
## 调试命令解析器 —— 纯逻辑，无场景依赖，可单测
##
## 刻意不 import 任何游戏 class_name：registry（命令表）与 monster_ids
## 由调用方注入，故本文件可在 --script 测试模式下单独加载。
##
## 语法：COMMAND [ARG...]
##   · 空白分词（连续空格/制表符视作一个分隔）
##   · 双引号可包裹含空格的参数
##   · 命令名大小写不敏感；**怪物 id 保持大小写敏感**（id 是精确查找键）

## 分词结果：{ok, tokens: Array[String], error: String}
static func tokenize(line: String) -> Dictionary:
	var tokens: Array = []
	var cur := ""
	var in_quote := false
	var started := false   # 当前是否已开始一个 token（区分 "" 与空）
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			in_quote = not in_quote
			started = true
			continue
		var is_sep := ch == " " or ch == "\t"
		if is_sep and not in_quote:
			if started:
				tokens.append(cur)
				cur = ""
				started = false
			continue
		cur += ch
		started = true
	if in_quote:
		return {"ok": false, "tokens": [], "error": "引号未闭合"}
	if started:
		tokens.append(cur)
	return {"ok": true, "tokens": tokens, "error": ""}


## 校验并拆解成 {ok, name, args, error}
## registry: {命令名: {"min": int, "max": int, "usage": String, "desc": String}}
## 校验顺序：空→命令存在（否则给候选）→参数个数。逐参范围校验在 DebugManager
## 里做（那里才拿得到 dungeon_graph / 背包容量等运行时上下文）。
static func validate(tokens: Array, registry: Dictionary) -> Dictionary:
	if tokens.is_empty():
		return {"ok": false, "name": "", "args": [], "error": ""}   # 空行：静默忽略
	var name := str(tokens[0]).to_lower()
	if not registry.has(name):
		var near := suggest(name, registry.keys())
		var hint := ""
		if not near.is_empty():
			hint = "  最接近：%s" % ", ".join(near)
		return {"ok": false, "name": name, "args": [],
			"error": "未知命令：%s%s（用 help 查看全部）" % [tokens[0], hint]}
	var spec: Dictionary = registry[name]
	var args: Array = tokens.slice(1)
	var lo := int(spec.get("min", 0))
	var hi := int(spec.get("max", 99))
	if args.size() < lo or args.size() > hi:
		var want := "至少 %d 个" % lo if lo == hi else "%d~%d 个" % [lo, hi]
		return {"ok": false, "name": name, "args": args,
			"error": "参数个数不对：需要 %s，收到 %d 个\n  用法：%s" % [
				want, args.size(), spec.get("usage", name)]}
	return {"ok": true, "name": name, "args": args, "error": ""}


## 近似候选：编辑距离 ≤2，或前缀匹配。用于拼错时的提示。
static func suggest(name: String, candidates: Array) -> Array:
	var out: Array = []
	var low := name.to_lower()
	for c in candidates:
		var cs := str(c)
		if cs.to_lower() == low:
			continue
		if cs.to_lower().begins_with(low) or low.begins_with(cs.to_lower()):
			out.append(cs)
		elif _edit_distance(cs.to_lower(), low) <= 2:
			out.append(cs)
	out.sort()
	return out.slice(0, 5)


## 莱文斯坦距离（经典 DP，两行滚动数组）
static func _edit_distance(a: String, b: String) -> int:
	var n := a.length()
	var m := b.length()
	if n == 0:
		return m
	if m == 0:
		return n
	var prev := []
	var cur := []
	for j in m + 1:
		prev.append(j)
	for i in range(1, n + 1):
		cur = [i]
		for j in range(1, m + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			cur.append(mini(mini(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost))
		prev = cur.duplicate()
	return int(prev[m])


## 由 registry 生成帮助文本（不会与命令表漂移）
static func help_text(registry: Dictionary, topic: String = "") -> String:
	if topic != "":
		var key := topic.to_lower()
		if not registry.has(key):
			return "没有命令：%s" % topic
		var s: Dictionary = registry[key]
		return "%s\n  %s" % [s.get("usage", key), s.get("desc", "")]
	var keys: Array = registry.keys()
	keys.sort()
	var lines: Array = ["可用命令："]
	for k in keys:
		var s: Dictionary = registry[k]
		lines.append("  %-14s %s" % [s.get("usage", k), s.get("desc", "")])
	return "\n".join(lines)


## 每个命令的**参数候选**来源键。DebugParser 不认识怪物库/房间表，
## 故只声明「该去问谁」，实际候选由调用方通过 ctx 注入。
const ARG_SOURCE := {
	"testmode": "onoff",
	"god": "onoff",
	"crit": "onoff",
	"list": "listwhat",
	"item": "rarity",
	"spawn": "monster",
	"tp": "room",
	"floor": "floor",
	"timescale": "num_ts",
	"dmgmult": "num",
	"gold": "num",
	"potion": "num",
	"help": "command",
}


## 自动补全。返回 {candidates: Array[String], token: String, index: int}
##
## line 为整行文本；补全**最后一个以空白分隔的 token**。
##   index 0        → 命令名
##   index >= 1     → 按命令的 ARG_SOURCE 取候选（ctx 注入）
##
## ctx 可含：monster_ids / room_count / floors
static func complete(line: String, registry: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var idx := _token_index(line)
	var cut := line.length()
	if cut > 0 and (line[cut - 1] == " " or line[cut - 1] == "\t"):
		# 刚打完空格：正在开始一个新 token（补全它的空前缀 = 列全部候选）
		return {"candidates": _candidates_for("", idx, _first_word(line), registry, ctx),
			"token": "", "index": idx}
	var start := maxi(line.rfind(" "), line.rfind("\t")) + 1
	var token := line.substr(start, cut - start)
	var names := _candidates_for(token, idx, _first_word(line), registry, ctx)
	var stripped: Array = []
	for n in names:
		if str(n).to_lower().begins_with(token.to_lower()):
			stripped.append(str(n))
	return {"candidates": stripped, "token": token, "index": idx}


## 当前正在输入第几个 token（0 = 命令名）
## 数的是「已完成的 token 数」= 空格数。**不能先 strip_edges**——那会丢掉
## 尾随空格，使「testmode 」（正准备输参数）被误判成在输命令名。
static func _token_index(line: String) -> int:
	var n := 0
	for ch in line:
		if ch == " " or ch == "	":
			n += 1
	return n


static func _first_word(line: String) -> String:
	var t := line.strip_edges()
	var sp := t.find(" ")
	return t if sp < 0 else t.substr(0, sp)


static func _candidates_for(token: String, idx: int, cmd: String,
		registry: Dictionary, ctx: Dictionary) -> Array:
	if idx == 0:
		return registry.keys()
	var src := str(ARG_SOURCE.get(cmd.to_lower(), ""))
	match src:
		"onoff": return ["on", "off"]
		"listwhat": return ["monsters", "rooms", "entities"]
		"rarity": return ["white", "green", "blue", "purple", "orange"]
		"monster": return ctx.get("monster_ids", [])
		"room":
			var out: Array = []
			for i in int(ctx.get("room_count", 0)):
				out.append(str(i))
			return out
		"floor":
			var f: Array = []
			for i in range(1, 10):
				f.append(str(i))
			return f
		"command": return registry.keys()
		_: return []


## 最长公共前缀（多候选时先补到公共部分，再列出全部）
static func common_prefix(items: Array) -> String:
	if items.is_empty():
		return ""
	var p := str(items[0])
	for s in items:
		var t := str(s)
		var i := 0
		while i < p.length() and i < t.length() and p[i] == t[i]:
			i += 1
		p = p.substr(0, i)
		if p == "":
			break
	return p
