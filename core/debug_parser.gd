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
