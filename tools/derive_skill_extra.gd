extends SceneTree
## 装备技能表重建器 —— 从描述文本派生 `kind` 与 `extra`
##
## ## 为什么需要这个脚本
##
## `EquipmentSkills.TABLE` 的 133 条装备技能有两层问题：
##
## **1. `extra` 基本是空的**——只有召唤/隐身两类填了内容，其余 122 条是 `{}`。
##    执行端（`SkillSystem`）要读的 `radius` / `element` / `heal_pct` /
##    `shield_pct` / `self_buffs` 等键**在整张表里出现次数为 0**。于是
##    「护盾术」「冰封领域」「圣光审判」按下去什么都不发生。
##
## **2. `kind` 是猜的**——按关键词粗分，与描述不符：
##    · 11 条反伤类（「3秒内反弹100%伤害」）被标成 `projectile`，
##      但反伤是**自身状态**，不是投射物
##    · 50 条 `aoe` 里混着目标区域型（「在目标区域召唤地刺」）——
##      用「以自身为圆心」结算会**打错位置**
##    · 4 条自增益（石肤/钢铁之躯/疾风步/大地守护）也被标成 `aoe`
##
## ## 设计原则：只从描述文本派生，描述没写的不编造
##
## 每条技能的 kind/extra **全部**从描述推导：
##   · 描述写「冻结周围 4 米」→ radius = 4.0
##   · 描述只写「对周围敌人」→ **不给 radius**（用执行端默认值）。
##     策划没给数字，编一个出来就是又一次「臆断生成」。
##
## ## 用法
##
## ```bash
## "$GODOT" --headless --path . --script res://tools/derive_skill_extra.gd
## ```
##
## 输出三段：
##   `=== TABLE ===`  完整的新表条目（含修正后的 kind），可直接粘回源文件
##   `=== VERIFY ===` 校验：描述里的关键词是否都有对应字段
##   `=== SUMMARY ===` 统计

const TABLE_PATH := "res://data/equipment/equipment_skills.gd"

## 元素关键词 → ElementDefs 的元素名
##
## **只映射 `ElementDefs.Elem` 真实存在的 6 种**（火/冰/雷/土/风/毒）。
## 「圣光」「暗影」「灵魂」在项目里**不是元素**——`ElementDefs.Elem`
## 没有这两项，`ElementDamage.attack()` 拿到非法值会静默走不到任何
## 元素分支。规格把它们当伤害**类型名**（文案），不是元素归属，
## 故这些技能不写 element（伤害照常结算，只是不带元素叠层）。
##
## 若将来策划确认要加圣光/暗影元素，应先在 `ElementDefs` 里定义，
## 再把这里的两行加回来——顺序反了会造出「引用了不存在的元素」的数据。
const ELEM_WORDS := {
	"冰霜": "frost", "冰锥": "frost", "冰冻": "frost", "冻结": "frost", "冰封": "frost",
	"火焰": "fire", "火球": "fire", "燃烧": "fire", "烈焰": "fire", "流星": "fire",
	"毒素": "poison", "毒雾": "poison",
	"雷电": "static", "雷霆": "static", "麻痹": "static",
	"土元素": "earth", "地刺": "earth", "地裂": "earth", "落石": "earth", "藤蔓": "earth",
	"风元素": "wind", "风刃": "wind", "风之箭": "wind",
}

## 控制类型关键词 → 控制类别
const CONTROL_WORDS := [
	["冻结", "freeze"], ["冰冻", "freeze"], ["冰封", "freeze"],
	["束缚", "root"], ["藤蔓", "root"], ["囚笼", "root"],
	["麻痹", "paralyze"], ["雷电", "paralyze"],
	["嘲讽", "taunt"],
	["恐惧", "fear"],
	["眩晕", "stun"],
]

## 中文数字
const CN_NUM := {"一": 1, "两": 2, "二": 2, "三": 3, "四": 4, "五": 5}


func _init() -> void:
	var rows := _read_table()
	if rows.is_empty():
		push_error("[derive] 读不到技能表：%s" % TABLE_PATH)
		quit(1)
		return

	var out: Array = []
	for r in rows:
		out.append(_rebuild(r))

	_print_table(out)
	var issues := _verify(out)
	_print_verify(issues, rows.size())
	_print_defaults(_needs_default(out))
	_print_summary(out)

	# `--write` 才真的落盘（默认 dry-run）。命令形如：
	#   godot --headless --path . --script res://tools/derive_skill_extra.gd -- --write
	if "--write" in OS.get_cmdline_user_args():
		if not issues.is_empty():
			push_error("[derive] 校验未通过，拒绝写盘（先修问题）")
			quit(1)
			return
		var err := _write_table(out)
		print("\n=== WRITE ===\n%s" % ("已写回 " + TABLE_PATH if err == OK else "写盘失败：%s" % err))

	quit(0 if issues.is_empty() else 1)


## 把重建后的表写回源文件
##
## 只替换 `const TABLE := [` 到配对的 `]` 之间的内容，**其余部分
##（文件头注释、_build、查询函数）原样保留**——那些是解释「为什么」
## 的文档，重生成时丢掉就再也找不回来了。
func _write_table(out: Array) -> int:
	var f := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if f == null:
		return FAILED
	var lines: Array = []
	while not f.eof_reached():
		lines.append(f.get_line().replace("\r", ""))
	f.close()

	var start := -1
	var end := -1
	for i in lines.size():
		var s := str(lines[i]).strip_edges()
		if start < 0 and s.begins_with("const TABLE := ["):
			start = i
			continue
		# 结束：TABLE 之后第一个只有 `]` 的行
		if start >= 0 and s == "]":
			end = i
			break
	if start < 0 or end < 0:
		push_error("[derive] 找不到 TABLE 边界（start=%s end=%s）" % [start, end])
		return FAILED

	var merged: Array = []
	merged.append_array(lines.slice(0, start + 1))
	for r in out:
		merged.append(_row_literal(r))
	merged.append_array(lines.slice(end))

	var w := FileAccess.open(TABLE_PATH, FileAccess.WRITE)
	if w == null:
		return FAILED
	w.store_string("\n".join(merged) + "\n")
	w.close()
	return OK


## 一条技能 → 源文件里的行字面量
func _row_literal(r: Dictionary) -> String:
	# 描述里若有 ASCII 双引号必须转义，否则破坏 GDScript 字符串字面量。
	# 当前 133 条用的都是中文引号 `“”`，但描述是人工维护的，防一手。
	var desc := str(r["desc"]).replace("\\", "\\\\").replace("\"", "\\\"")
	# 第 5 列（旧 reach）**写 0.0**：它原本是 damage_mult 的副本，
	# 会让 cone 类的扇形半径等于伤害倍率（裂空斩 1.8 米）。真正的射程
	# 一律走 extra 的 range/radius，执行端对缺失值有默认兜底。
	return "  [\"%s\", \"%s\", \"%s\", %s, %s, 0.0, %s, \"%s\", %s]," % [
		r["name"], r["sname"], r["kind"], _n(r["cd"]), _n(r["dmg"]),
		_n(r["dur"]), desc, _fmt(r["extra"])]


# ============================================================
# 读表
# ============================================================

## 读技能表原始行 → [{name, sname, kind, cd, dmg, reach_col, dur, desc}]
func _read_table() -> Array:
	var f := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		# **必须先去掉 `\r`**：表里曾混着 133 个 `\r`（每条技能一个，
		# 都在描述末尾、收尾引号之前）。Godot 的 `get_line()` 把 `\r`
		# 也当行终止符，于是每行读到描述就被截断，后面的 `, {}]` 永远
		# 读不到——表现为「133 条全匹配、0 条解析成功」且不报任何错。
		var line := f.get_line().replace("\r", "").strip_edges()
		if not line.begins_with("[\""):
			continue
		var m := _parse_row(line)
		if not m.is_empty():
			out.append(m)
	f.close()
	return out


## 解析一行表条目
##
## 行格式：["装备名", "技能名", "kind", cd, dmg, reach, dur, "描述", {...}],
func _parse_row(line: String) -> Dictionary:
	var i := line.find("[\"")
	if i < 0:
		return {}
	i += 2
	var fields: Array = []
	var cur := ""
	# **初始必须在字符串内**：上面已消费开引号 `["`，若写 false，
	# 第一个 `"`（字段0收尾）会把状态翻成 true，之后所有逗号都成了
	# 字符串内容——整行解析成 1 个字段并静默失败。
	var in_str := true
	while i < line.length():
		var c := line[i]
		if c == "\"":
			in_str = not in_str
			i += 1
			continue
		if not in_str and c == ",":
			fields.append(cur.strip_edges())
			cur = ""
			i += 1
			continue
		if not in_str and c == "]":
			fields.append(cur.strip_edges())
			break
		cur += c
		i += 1
	if fields.size() < 8:
		return {}
	return {
		"name": str(fields[0]), "sname": str(fields[1]), "kind": str(fields[2]),
		"cd": float(fields[3]), "dmg": float(fields[4]),
		"reach_col": float(fields[5]), "dur": float(fields[6]), "desc": str(fields[7]),
	}


# ============================================================
# 派生
# ============================================================

## 从描述重建一条技能（修正 kind + 补齐 extra）
func _rebuild(r: Dictionary) -> Dictionary:
	var desc := str(r["desc"])
	# 剥掉 `主动技能"XXX"` 这截**技能名**——否则「反击风暴」的「风暴」
	# 会被元素规则误判成风元素、「暗影刺杀」的「暗影」会污染上下文。
	var body := _strip_skill_name(desc)
	var e := _derive_extra(r, body)
	var kind := _derive_kind(r, body, e)
	# **kind 定下来之后才能补的字段**——例如召唤物的 lifetime 只在
	# kind=="summon" 时才要。早期版本在 _derive_extra 里读 `r["kind"]`，
	# 那时拿到的还是**旧表的 kind**（唤灵短杖旧标 aoe），于是
	# 「唤灵」和「暗影分身」两条的 lifetime 被静默丢掉。
	_finalize_kind_dependent(r, body, kind, e)
	return {
		"name": r["name"], "sname": r["sname"], "kind": kind,
		"cd": r["cd"], "dmg": r["dmg"], "dur": r["dur"],
		"desc": desc, "extra": e,
	}


## 补 kind 相关的字段
func _finalize_kind_dependent(r: Dictionary, body: String, kind: String, e: Dictionary) -> void:
	# 召唤物存活时长（描述都写「持续 N 秒」）
	if kind == "summon":
		var m := _re(r"持续\s*(\d+(?:\.\d+)?)\s*秒").search(body)
		if m:
			e["lifetime"] = float(m.get_string(1))
	# 隐身类：破隐一击的加成取自描述，不是写死 1.0
	if kind == "stealth":
		e.erase("atk_pct")  # 「下次攻击+80%」不是常驻攻击加成
		var m2 := _re(r"下一次普攻伤害翻倍").search(body)
		if m2:
			e["next_hit_bonus"] = 1.0
		else:
			m2 = _re(r"下次攻击\s*\+\s*(\d+(?:\.\d+)?)%").search(body)
			if m2:
				e["next_hit_bonus"] = float(m2.get_string(1)) / 100.0


## 剥掉描述里的 `主动技能"XXX"` 与紧随的破折号
##
## 描述两种形态：
##   `主动技能"名字"——效果…`
##   `被动效果；主动技能"名字"——效果…`
## 两种都统一取「——」之后的正文；没有「——」时取原文。
func _strip_skill_name(desc: String) -> String:
	# 先砍掉被动前缀（第一个「；」之前），它不属于主动技能的效果
	var segs := desc.split("；")
	var active := desc
	for s in segs:
		if s.contains("主动技能"):
			active = s
			break
	var k := active.find("——")
	if k >= 0:
		return active.substr(k + 2)
	return active


## 从描述正文派生 extra
func _derive_extra(r: Dictionary, body: String) -> Dictionary:
	var e: Dictionary = {}

	# ---- 1. 半径：只在描述给了米数时才写 ----
	var m := _re(r"(?:周围|区域|半径)\s*(\d+(?:\.\d+)?)\s*米").search(body)
	if m == null:
		m = _re(r"(\d+(?:\.\d+)?)\s*米\s*(?:区域|范围内)").search(body)
	if m:
		e["radius"] = float(m.get_string(1))

	# ---- 2. 射程：位移/拉拽距离 ----
	m = _re(r"(?:瞬移|闪现|冲锋|冲刺|突进|拉至|拖拽|冲向|向前)[^，。；]*?(\d+(?:\.\d+)?)\s*米").search(body)
	if m == null:
		m = _re(r"前方\s*(\d+(?:\.\d+)?)\s*米内").search(body)
	if m:
		e["range"] = float(m.get_string(1))

	# ---- 3. 元素 ----
	#
	# 「随机元素」是另一种机制（释放时 roll），不在这里定死；
	# 用 random_element 标记，执行端自行随机。
	if body.contains("随机元素"):
		e["random_element"] = true
	else:
		for w in ELEM_WORDS:
			if body.contains(w):
				e["element"] = ELEM_WORDS[w]
				break

	# ---- 4. 目标区域型（伤害中心不是自身，是准心方向 range 米处）----
	if body.contains("目标区域") or body.contains("目标地点") \
			or body.contains("目标点") or _re(r"在\s*\d+(?:\.\d+)?\s*米区域").search(body):
		e["at_aim"] = true

	# ---- 5. 治疗 ----
	#
	# 三种语义分开，**互斥**（早期版本三个正则各写各的，
	# 导致「每命中一个敌人回复5%」同时命中 heal_pct 与 heal_per_hit_pct）：
	#   「回复造成伤害的 N%」  → lifesteal_pct
	#   「每命中一个敌人回复 N%」→ heal_per_hit_pct
	#   「每秒回复 N%」        → heal_tick_pct（周期性）
	#   「回复/治疗 N% 最大生命」→ heal_pct（一次性）
	m = _re(r"回复造成伤害的\s*(\d+(?:\.\d+)?)%").search(body)
	if m:
		e["lifesteal_pct"] = float(m.get_string(1)) / 100.0
	else:
		m = _re(r"每命中[^，。；]*?回复\s*(\d+(?:\.\d+)?)%").search(body)
		if m:
			e["heal_per_hit_pct"] = float(m.get_string(1)) / 100.0
		else:
			m = _re(r"每秒(?:回复|治疗)[^，。；]*?(\d+(?:\.\d+)?)%").search(body)
			if m:
				e["heal_tick_pct"] = float(m.get_string(1)) / 100.0
				e["tick_interval"] = 1.0
			else:
				m = _re(r"(?:回复|治疗)[^，。；]*?(\d+(?:\.\d+)?)%\s*(?:最大生命|生命)").search(body)
				if m:
					e["heal_pct"] = float(m.get_string(1)) / 100.0

	# ---- 6. 护盾 ----
	m = _re(r"吸收\s*(\d+(?:\.\d+)?)%\s*最大生命").search(body)
	if m:
		e["shield_pct"] = float(m.get_string(1)) / 100.0

	# ---- 7. 自身增益 ----
	m = _re(r"(\d+(?:\.\d+)?)%\s*减伤").search(body)
	if m:
		e["dr_pct"] = float(m.get_string(1)) / 100.0
	m = _re(r"闪避\s*\+?\s*(\d+(?:\.\d+)?)%").search(body)
	if m:
		e["dodge_pct"] = float(m.get_string(1)) / 100.0
	m = _re(r"移速\s*\+?\s*(\d+(?:\.\d+)?)%").search(body)
	if m:
		e["spd_pct"] = float(m.get_string(1)) / 100.0
	m = _re(r"攻速\s*\+?\s*(\d+(?:\.\d+)?)%").search(body)
	if m:
		e["aspd_pct"] = float(m.get_string(1)) / 100.0
	m = _re(r"攻击\s*\+\s*(\d+(?:\.\d+)?)%").search(body)
	if m:
		e["atk_pct"] = float(m.get_string(1)) / 100.0

	# ---- 8. 对目标的减益 ----
	m = _re(r"移速\s*-\s*(\d+(?:\.\d+)?)%").search(body)
	if m:
		e["target_spd_pct"] = -float(m.get_string(1)) / 100.0
	m = _re(r"攻速\s*-\s*(\d+(?:\.\d+)?)%").search(body)
	if m:
		e["target_aspd_pct"] = -float(m.get_string(1)) / 100.0
	m = _re(r"攻击力\s*(?:-\s*|降低\s*)(\d+(?:\.\d+)?)%").search(body)
	if m:
		e["target_atk_pct"] = -float(m.get_string(1)) / 100.0

	# ---- 9. 控制 ----
	#
	# 类型与时长分开：类型供执行端选 buff 词条，时长写进 control_seconds。
	# 「沉默」的文案是「使目标无法使用技能 2 秒」——没有「沉默」二字，
	# 需单独匹配。
	for pair in CONTROL_WORDS:
		if body.contains(str(pair[0])):
			e["control"] = str(pair[1])
			break
	if body.contains("无法使用技能"):
		e["control"] = "silence"
	if e.has("control"):
		m = _re(r"(\d+(?:\.\d+)?)\s*秒").search(body)
		if m:
			e["control_seconds"] = float(m.get_string(1))

	# ---- 9b. 隐身时长 ----
	#
	# 「进入隐身 3 秒」「隐身 2 秒」——时长写在「隐身」后面。
	# 早期版本漏了这条，导致烟雾弹头盔/护手（描述是「自身进入隐身3秒」）
	# 的 extra 是空的，隐身技能拿不到时长。
	if body.contains("隐身"):
		m = _re(r"隐身[^，。；]*?(\d+(?:\.\d+)?)\s*秒").search(body)
		if m == null:
			m = _re(r"持续\s*(\d+(?:\.\d+)?)\s*秒").search(body)
		if m:
			e["stealth_seconds"] = float(m.get_string(1))
		if body.contains("免疫"):
			e["invuln"] = true
		m = _re(r"下一次普攻伤害翻倍|下次攻击\+(\d+(?:\.\d+)?)%").search(body)
		if m:
			e["next_hit_bonus"] = 1.0

	# ---- 9c. 净化 / 驱散 ----
	if body.contains("负面状态"):
		e["dispel"] = 1
		if body.contains("所有负面状态"):
			e["dispel"] = 99

	# ---- 9d. 友方链接（分担伤害）----
	if body.contains("链接一名友方") or body.contains("链接"):
		e["link_ally"] = true
		m = _re(r"分担其\s*(\d+(?:\.\d+)?)%\s*伤害").search(body)
		if m:
			e["link_share_pct"] = float(m.get_string(1)) / 100.0
		if body.contains("持续治疗"):
			e["link_heal"] = true

	# ---- 10. 位移控制：击飞 / 击退 ----
	if body.contains("击飞") or body.contains("撞飞"):
		e["knockup"] = true
	elif body.contains("击退"):
		e["knockback"] = 4.0

	# ---- 11. 拉拽 ----
	#
	# 键名用 `pull_target` 而不是 `pull`：`pull` 在 `_fmt` 输出的字典
	# 字面量里是裸标识符位置，且与 kind 名 "pull" 混淆，容易误读。
	if body.contains("拉至身前") or body.contains("拉扯") or body.contains("牵引"):
		e["pull_target"] = true

	# ---- 12. 反伤 / 格挡 ----
	m = _re(r"反弹\s*(\d+(?:\.\d+)?)%\s*伤害").search(body)
	if m:
		e["reflect_pct"] = float(m.get_string(1)) / 100.0
	elif body.contains("受到反弹伤害"):
		# 描述没给百分比（「3秒内周围敌人受到反弹伤害」）——
		# **不编数值**，标记出来交给执行端用默认值。
		e["reflect_aura"] = true
	if body.contains("格挡所有攻击") or body.contains("免疫一切伤害") \
			or body.contains("免疫所有伤害") or body.contains("免疫伤害"):
		e["block_all"] = true
	elif body.contains("格挡所有远程"):
		e["block_ranged"] = true
	elif body.contains("格挡正面"):
		e["block_front"] = true

	# ---- 13. 数量：多发 / 多只 ----
	m = _re(r"发射\s*(\d+)\s*枚").search(body)
	if m:
		e["count"] = int(m.get_string(1))
	m = _re(r"召唤\s*(\d+|[一两二三四五])\s*(?:只|个)").search(body)
	if m:
		var s := m.get_string(1)
		e["count"] = int(s) if s.is_valid_int() else int(CN_NUM.get(s, 1))

	# ---- 13b. 召唤继承比例 ----
	#
	# 描述写「继承 50% 法强」「继承 60% 生命，40% 攻击」「继承 100% 最大生命、
	# 60% 攻击力」。**原表把这几个值一刀切写成 0.4**——是臆断，
	# 与描述的数字不符（召唤守护者描述是 100%，表里是 0.4）。
	# 这里一律按描述派生。
	if body.contains("继承"):
		m = _re(r"继承\s*(\d+(?:\.\d+)?)%\s*(?:最大生命|生命)").search(body)
		if m:
			e["hp_ratio"] = float(m.get_string(1)) / 100.0
		m = _re(r"继承[^，。；]*?(\d+(?:\.\d+)?)%\s*(?:攻击力|攻击)").search(body)
		if m:
			e["atk_ratio"] = float(m.get_string(1)) / 100.0
		m = _re(r"继承\s*(\d+(?:\.\d+)?)%\s*法强").search(body)
		if m:
			e["ap_ratio"] = float(m.get_string(1)) / 100.0
	# 召唤物存活时长已移到 _finalize_kind_dependent（需先定 kind）

	# ---- 14. 穿透 ----
	#
	# 「穿透所有敌人」「对路径所有敌人」「对路径敌人」都表示打穿一条线。
	if body.contains("穿透所有") or body.contains("路径所有敌人") \
			or body.contains("路径敌人"):
		e["pierce_count"] = 99
	else:
		m = _re(r"穿透\s*[≥>]?\s*(\d+)\s*敌").search(body)
		if m:
			e["pierce_count"] = int(m.get_string(1))

	# ---- 15. 护甲穿透 ----
	m = _re(r"无视\s*(\d+(?:\.\d+)?)%\s*护甲").search(body)
	if m:
		e["armor_pierce"] = float(m.get_string(1)) / 100.0

	# ---- 16. 消耗 ----
	m = _re(r"消耗\s*(\d+(?:\.\d+)?)%\s*当前生命").search(body)
	if m:
		e["hp_cost_pct"] = float(m.get_string(1)) / 100.0

	# ---- 17. 持续型（周期性结算）----
	if body.contains("每秒造成") or body.contains("每0.5秒造成") \
			or body.contains("每 0.5 秒造成"):
		e["tick_interval"] = 0.5 if body.contains("0.5") else 1.0

	# ---- 18. 暴击 / 蓄力 / 资源 / 引爆 ----
	if body.contains("必定暴击"):
		e["guaranteed_crit"] = true
	m = _re(r"蓄力\s*(\d+(?:\.\d+)?)\s*秒").search(body)
	if m:
		e["windup"] = float(m.get_string(1))
	m = _re(r"回复\s*(\d+(?:\.\d+)?)%\s*职业资源").search(body)
	if m:
		e["restore_resource_pct"] = float(m.get_string(1)) / 100.0
	if body.contains("引爆") or body.contains("消耗所有"):
		e["detonate"] = true

	# ---- 19. 状态持续时长 ----
	#
	# 第 6 列 `duration` 只覆盖了「持续 N 秒」的写法；「3 秒内反弹 100% 伤害」
	# 这类**限时状态**没被捕获（第 6 列是 0.0）。若不补，反伤/格挡 buff
	# 会按 `BuffDefs` 的默认时长走（或永久），与描述不符。
	if not e.has("duration_seconds"):
		m = _re(r"(\d+(?:\.\d+)?)\s*秒内").search(body)
		if m == null:
			m = _re(r"持续\s*(\d+(?:\.\d+)?)\s*秒").search(body)
		if m:
			e["duration_seconds"] = float(m.get_string(1))

	return e


## 从描述派生正确的 kind
##
## 判据顺序**很重要**：先判「不造成伤害的自身状态」，再判位移，
## 最后才按形状分。顺序反了会把「3秒内反弹100%伤害」（无伤害的自身
## 状态）判成 projectile——这正是旧表 11 条反伤技能的错误来源。
func _derive_kind(r: Dictionary, body: String, e: Dictionary) -> String:
	var dmg := float(r["dmg"])

	# 1. 隐身（优先级最高：隐身技能的描述里也可能含「瞬移」等词）
	if body.contains("隐身"):
		return "stealth"
	# 2. 召唤
	if body.contains("召唤") and _re(r"召唤\s*(\d+|[一两二三四五])\s*(?:只|个)").search(body):
		return "summon"
	# 3. 位移
	#
	# **必须排在「纯自身状态」之前**：传送/闪现的描述是「瞬移至 8 米内
	# 指定位置」——既不造成伤害、也不含「敌人/目标」字样，会被下面
	# 的 buff 判据吃掉（实测 5 条传送/闪现被误标成 buff）。
	if body.contains("瞬移") or body.contains("闪现") or body.contains("冲锋") \
			or body.contains("冲刺") or body.contains("突进"):
		return "dash"
	# 4. 纯自身状态：不造成伤害，且不作用于敌人
	#
	# 「不作用于敌人」的判据是描述里没有「敌人/目标」——战吼虽然
	# damage_mult=0，但它作用于「周围敌人」，必须留在 aoe。
	var affects_enemy := body.contains("敌人") or body.contains("目标")
	if dmg <= 0.0 and not affects_enemy:
		return "buff"
	# 5. 拉拽
	if e.has("pull_target"):
		return "pull"
	# 6. 投射物：有「发射/射出/投掷」且不是范围爆炸
	if (body.contains("发射") or body.contains("射出") or body.contains("投掷")) \
			and not e.has("at_aim") and not e.has("tick_interval"):
		return "projectile"
	# 7. 扇形：明确写「向前方」且是近战劈砍
	if body.contains("向前方") and (body.contains("劈砍") or body.contains("扇形") \
			or body.contains("吐息") or body.contains("剑气") or body.contains("喷射")):
		return "cone"
	# 8. 兜底：范围
	return "aoe"


# ============================================================
# 校验
# ============================================================

## 校验：描述里的关键词是否都有对应字段
##
## 这是本脚本**最重要的部分**——133 条无法靠肉眼保证不漏。
func _verify(out: Array) -> Array:
	var issues: Array = []
	for i in out.size():
		var r: Dictionary = out[i]
		var e: Dictionary = r["extra"]
		var body := _strip_skill_name(str(r["desc"]))
		var tag := "%d %s/%s" % [i + 1, r["name"], r["sname"]]

		if _re(r"\d+(?:\.\d+)?\s*米").search(body) \
				and not e.has("radius") and not e.has("range"):
			issues.append("%s：描述有米数但无 radius/range" % tag)
		if not e.has("element") and not e.has("random_element"):
			for w in ELEM_WORDS:
				if body.contains(w):
					issues.append("%s：描述含「%s」但无 element" % [tag, w])
					break
		if body.contains("吸收") and body.contains("最大生命") and not e.has("shield_pct"):
			issues.append("%s：描述含护盾但无 shield_pct" % tag)
		if body.contains("反弹") and not e.has("reflect_pct") and not e.has("reflect_aura"):
			issues.append("%s：描述含反弹但无 reflect_pct" % tag)
		if (body.contains("击飞") or body.contains("撞飞")) and not e.has("knockup"):
			issues.append("%s：描述含击飞但无 knockup" % tag)
		if body.contains("每秒造成") and not e.has("tick_interval"):
			issues.append("%s：描述含持续伤害但无 tick_interval" % tag)
		if body.contains("目标区域") and not e.has("at_aim"):
			issues.append("%s：描述含目标区域但无 at_aim" % tag)
	return issues


## 描述未给射程的 cone 类——**不是数据缺陷**，是执行端需要默认值
##
## 旧表的 reach 列是 damage_mult 的副本（裂空斩 1.8 米、裂地斩 5.0 米），
## 清零后这些技能的 reach 变成 0.0。执行端若写 `sd.get("reach", 3.0)`，
## 拿到的是 0.0 而不是 3.0——**扇形会退化成零射程，技能看似没反应**。
## 故必须由 `SkillSystem` 显式兜底（见 `_cast_cone` 的 `maxf(reach, ...)`）。
func _needs_default(out: Array) -> Array:
	var names: Array = []
	for r in out:
		if r["kind"] == "cone" and not r["extra"].has("radius") \
				and not r["extra"].has("range"):
			names.append("%s/%s" % [r["name"], r["sname"]])
	return names


# ============================================================
# 输出
# ============================================================

func _print_table(out: Array) -> void:
	print("=== TABLE ===")
	for r in out:
		print("  [\"%s\", \"%s\", \"%s\", %s, %s, %s, %s, \"%s\", %s]," % [
			r["name"], r["sname"], r["kind"], _n(r["cd"]), _n(r["dmg"]),
			_n(0.0), _n(r["dur"]), r["desc"], _fmt(r["extra"])])


func _print_verify(issues: Array, total: int) -> void:
	print("\n=== VERIFY ===")
	if issues.is_empty():
		print("全部通过：%d 条" % total)
	else:
		print("发现 %d 条问题：" % issues.size())
		for s in issues:
			print("  " + s)


func _print_defaults(names: Array) -> void:
	print("\n=== NEEDS DEFAULT (非缺陷) ===")
	if names.is_empty():
		print("无")
		return
	print("%d 条 cone 类描述未给射程，执行端必须兜底默认值：" % names.size())
	for n in names:
		print("  " + str(n))


func _print_summary(out: Array) -> void:
	var kinds := {}
	var keys := {}
	for r in out:
		var k := str(r["kind"])
		kinds[k] = int(kinds.get(k, 0)) + 1
		for key in r["extra"]:
			keys[key] = int(keys.get(key, 0)) + 1
	print("\n=== SUMMARY ===")
	print("kind 分布：")
	var ks := kinds.keys(); ks.sort()
	for k in ks:
		print("  %-12s %d" % [k, kinds[k]])
	print("extra 字段覆盖：")
	var xs := keys.keys(); xs.sort()
	for k in xs:
		print("  %-20s %d" % [k, keys[k]])
	var empty := 0
	for r in out:
		if r["extra"].is_empty():
			empty += 1
	print("extra 仍为空：%d 条" % empty)


## float → 保留一位小数的字面量
func _n(v) -> String:
	return "%.1f" % float(v)


## 字典 → GDScript 字面量
##
## 必须按类型分别处理：字符串值不加引号会输出 `element: frost`
##（`frost` 被当成标识符），GDScript 解析直接失败。
func _fmt(d: Dictionary) -> String:
	if d.is_empty():
		return "{}"
	var keys := d.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		var v = d[k]
		if v is bool:
			parts.append("\"%s\": %s" % [k, "true" if v else "false"])
		elif v is String:
			parts.append("\"%s\": \"%s\"" % [k, v])
		else:
			parts.append("\"%s\": %s" % [k, v])
	return "{" + ", ".join(parts) + "}"


## 正则封装
func _re(pattern: String) -> RegEx:
	var rx := RegEx.new()
	rx.compile(pattern)
	return rx
