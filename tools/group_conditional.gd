extends SceneTree
## 条件型词条 —— 按「需要的 Trigger」归类
##
## 为「条件型解析重构」计划提供依据：109 条各自需要什么样的触发条件，
## 其中多少能复用现有 Trigger、多少需要新增、多少属特殊事件。
##
## ## 用法
##
## ```bash
## "$GODOT" --headless --path . --script res://tools/group_conditional.gd
## ```

const SRC := "res://tools/data/conditional_stats.txt"

## 归类规则：[组名, 关键词数组]
##
## 顺序有意义——先匹配到的先归类。宽泛词放后面。
const GROUPS := [
	["血线（LOW_HP 已有）", ["生命低于", "生命值低于", "血量低于", "生命低于50%"]],
	["满状态（需新增）", ["资源满时", "储存满时", "生命满时", "生命值满时"]],
	["存在期间（部分已有）", ["召唤物存在时", "护盾存在时", "影分身存在时", "图腾存在时"]],
	["满层（AT_FULL 已有）", ["满层", "叠满", "层时"]],
	["技能相关（ON_SKILL_CAST 已有）", ["使用技能", "施放技能", "技能命中", "释放技能"]],
	["受击/格挡/闪避（已有）", ["受到近战", "受到伤害", "受到元素", "格挡", "闪避"]],
	["击杀相关（已有）", ["击杀"]],
	["冲刺/疾跑（已有）", ["冲刺", "疾跑", "疾风步"]],
	["隐身相关（需新增）", ["隐身"]],
	["眩晕/麻痹目标（需新增）", ["眩晕目标", "麻痹目标", "冰冻目标", "冰冻敌人"]],
	["暴击相关（已有）", ["暴击"]],
	["距离条件（需新增）", ["距离目标", "米外", "米内"]],
	["其他特殊事件", []],
]


func _init() -> void:
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		push_error("读不到 %s" % SRC)
		quit(1)
		return

	var buckets := {}
	var order: Array = []
	for g in GROUPS:
		buckets[g[0]] = []
		order.append(g[0])

	while not f.eof_reached():
		var line := f.get_line().replace("\r", "")
		if line.strip_edges().is_empty():
			continue
		var c := line.split("\t")
		if c.size() < 3:
			continue
		var name := c[0]
		var text := c[2]
		var placed := false
		for g in GROUPS:
			var kws: Array = g[1]
			if kws.is_empty():
				continue
			for kw in kws:
				if text.contains(str(kw)):
					buckets[g[0]].append("%s | %s" % [name, text])
					placed = true
					break
			if placed:
				break
		if not placed:
			buckets["其他特殊事件"].append("%s | %s" % [name, text])
	f.close()

	var total := 0
	print("=== 条件型词条归类（共 109 条）===\n")
	for k in order:
		var arr: Array = buckets[k]
		if arr.is_empty():
			continue
		total += arr.size()
		print("【%s】%d 条" % [k, arr.size()])
		for a in arr:
			print("    " + str(a))
		print("")
	print("合计 %d 条" % total)

	quit(0)
