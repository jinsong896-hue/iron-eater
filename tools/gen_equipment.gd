extends SceneTree
## 装备数据生成器 —— 严格按《装备参考2》规格
##
## ## 为什么用 GDScript 而不是 perl
##
## 初版用 perl 写，但 perl 的双引号字符串会**隐式插值**——`"[$1/100.0]"`
## 里的 `$1` 被当变量、`/100.0` 被当字面量，产出 `[10/100.0]` 这种
## **不是数字的字符串**。反复踩了三次同类坑。
##
## GDScript 没有这个陷阱，且它本就是项目语言——将来改规则的人
## 不需要会 perl。用项目自带的 Godot 二进制即可运行：
##
##   "$GODOT" --headless --path . --script res://tools/gen_equipment.gd
##
## ## 原则
##
## **按机制族逐条写死规则，不做通用猜测。**
## 匹配不到 → 报告给人看，**不猜**（旧生成器的"猜"正是问题根源）。
##
## ## 输入 / 输出
##
##   输入：tools/data/equipment_spec.tsv（制表符分隔的规格表）
##   输出：stdout —— CURATED_TABLE 的 GDScript 数组字面量
##   报告：stderr —— 无法自动映射的词条清单

const SPEC_PATH := "res://tools/data/equipment_spec.tsv"

const RAR_ID := {"GREEN": "G", "BLUE": "B", "PURPLE": "P", "ORANGE": "O"}
const RAR_SCALE := {"GREEN": 1.6, "BLUE": 2.5, "PURPLE": 4.0, "ORANGE": 6.5}

const CAT_ENUM := {
	"WEAPON": "EquipmentDefs.Category.WEAPON",
	"ARMOR": "EquipmentDefs.Category.ARMOR",
	"ACCESSORY": "EquipmentDefs.Category.ACCESSORY",
}
const SLOT_ENUM := {
	"HEAD": "EquipmentDefs.Slot.HEAD", "CHEST": "EquipmentDefs.Slot.CHEST",
	"SHOULDERS": "EquipmentDefs.Slot.SHOULDERS", "HANDS": "EquipmentDefs.Slot.HANDS",
	"LEGS": "EquipmentDefs.Slot.LEGS", "FEET": "EquipmentDefs.Slot.FEET",
	"ACCESSORY_1": "EquipmentDefs.Slot.ACCESSORY_1",
}

## 武器类型 → 标签（规格：近战/远程/防御/魔法 × 单手/双手 × 长杆）
const WEAPON_TAGS := {
	"sword": "近战,单手,物理", "greatsword": "近战,双手,物理",
	"dagger": "近战,单手,物理", "axe": "近战,单手,物理",
	"greataxe": "近战,双手,物理", "spear": "近战,双手,长杆,物理",
	"scythe": "近战,双手,长杆,物理", "bow": "远程,双手,物理",
	"crossbow": "远程,单手,物理", "heavy_crossbow": "远程,双手,物理",
	"staff": "魔法,双手,长杆,法术", "shield": "防御",
}
const WT_MULT := {
	"sword": 1.0, "greatsword": 1.6, "dagger": 0.75, "axe": 1.0,
	"greataxe": 1.6, "spear": 1.0, "scythe": 1.6, "bow": 1.0,
	"crossbow": 1.0, "heavy_crossbow": 1.6, "staff": 1.3, "shield": 1.0,
}

## 元素中文名 → ElementDefs 的 key
const ELEM_KEY := {
	"火焰": "fire", "冰霜": "frost", "雷电": "static",
	"毒素": "poison", "大地": "earth", "疾风": "wind",
}

## 属性名 → Stat 枚举名（生成时直接写字面量）
const STAT_ENUM := {
	"攻击力": "Stat.ATK", "物理伤害": "Stat.ATK",
	"法术强度": "Stat.AP", "法强": "Stat.AP", "魔法伤害": "Stat.AP",
	"生命": "Stat.HP", "最大生命": "Stat.HP", "生命值": "Stat.HP",
	"防御": "Stat.DEF", "护甲": "Stat.DEF", "防御力": "Stat.DEF",
	"移动速度": "Stat.SPD", "移速": "Stat.SPD",
	"攻击速度": "Stat.ASPD", "攻速": "Stat.ASPD",
	"暴击率": "Stat.CRT", "暴击伤害": "Stat.CRD",
	"冷却缩减": "Stat.CDR", "冷却": "Stat.CDR", "射程": "Stat.RNG",
}

## 扩展通道 → 枚举值（与 EquipmentDB.SPECIAL_STAT 一致）
const SP := {
	"lifesteal": 100, "knockback": 101, "debuff_dur": 102, "elem_pen": 103,
	"reflect": 104, "execute_line": 105, "elem_resist": 106, "gold_gain": 107,
	"sell_price": 108, "key_drop": 109, "block": 110, "dodge": 111,
	"ctrl_resist": 112, "cd_refresh": 113, "drop_rate": 114, "pickup_range": 115,
	"summon_dmg": 116, "elem_dmg": 117, "true_dmg": 118, "exp_gain": 119,
	"summon_limit": 120,
}

## Operation / Trigger 枚举值（与 AffixData 一致）
const OP_BONUS_ELEMENT := 3
const OP_TRIGGER_BUFF := 2
const OP_STACK_GAIN := 4
const TRIG_ON_KILL := 1
const TRIG_ON_HURT := 2
const TRIG_ON_HIT := 3
const TRIG_ON_COMBO := 7
const TRIG_ON_BLOCK := 9
const TRIG_ON_CRIT := 6

## 数值型效果名 → 扩展通道 key（吞噬/融合列大量出现）
const EXT_BY_NAME := {
	"元素伤害": "elem_dmg", "火焰伤害": "elem_dmg", "冰霜伤害": "elem_dmg",
	"雷电伤害": "elem_dmg", "毒素伤害": "elem_dmg", "大地伤害": "elem_dmg",
	"土元素伤害": "elem_dmg", "风元素伤害": "elem_dmg", "暗影伤害": "elem_dmg",
	"远程伤害": "elem_dmg", "范围伤害": "elem_dmg", "陷阱伤害": "elem_dmg",
	"投射物伤害": "elem_dmg", "被冻结敌人受到伤害": "elem_dmg",
	"元素抗性": "elem_resist", "异常状态抗性": "elem_resist", "护盾强度": "elem_resist",
	"生命偷取": "lifesteal", "吸血": "lifesteal", "治疗效果": "lifesteal",
	"生命回复": "lifesteal", "反伤效果": "reflect", "反弹伤害": "reflect",
	"格挡率": "block", "闪避率": "dodge", "护甲穿透": "elem_pen",
	"处决线": "execute_line", "对精英/Boss伤害": "execute_line",
	"背刺伤害": "execute_line", "标记增伤": "execute_line", "真实伤害": "true_dmg",
	"金币获取": "gold_gain", "钥匙碎片掉落": "key_drop",
	"钥匙碎片掉落概率": "key_drop", "掉落率": "drop_rate",
	"装备掉落率": "drop_rate", "经验获取": "exp_gain", "资源上限": "exp_gain",
	"拾取范围": "pickup_range", "召唤物伤害": "summon_dmg", "召唤物生命": "summon_dmg",
}

## 命中施加词条：中文名 → BuffDefs id
const BUFF_OF := {
	"冰冻": "freeze", "麻痹": "paralyze", "眩晕": "stun", "缠绕": "entangle",
	"减速": "slow", "中毒": "poison_rot", "燃烧": "burn", "点燃": "burn",
	"标记": "mark", "沉默": "silence", "缴械": "disarm",
	"恐惧": "fear", "嘲讽": "taunt",
}

## 未映射词条收集（最后统一报告）
var _unmapped: Array[String] = []
## 装备技能修饰（不属于词条，单独统计）
var _skill_notes := 0


func _initialize() -> void:
	var f := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if f == null:
		push_error("打不开规格表：%s" % SPEC_PATH)
		quit(1)
		return
	var rows: Array[String] = []
	var by_rar := {}
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty():
			continue
		# **必须清掉 \r**：规格表是从对话记录里提取的，字段间混了
		# `\r\t`（CR + TAB）——`split("\t")` 后 cols[0] 会带上 `\r`，
		# 于是 `cols[0] != "PASS"` 恒成立，**一行都读不到**（实测踩到）。
		line = line.replace("\r", "").strip_edges()
		if line.is_empty():
			continue
		var cols := line.split("\t")
		if cols.size() < 8 or cols[0] != "PASS":
			continue
		var rar := cols[1]
		var cat := cols[2]
		var wtype := cols[3]
		var name := cols[4]
		var own := cols[5]
		var dev := cols[6]
		var fus := cols[7]

		var n: int = int(by_rar.get(rar, 0))
		by_rar[rar] = n + 1
		var id := "%s%03d" % [RAR_ID.get(rar, "X"), n]

		var cat_e: String = str(CAT_ENUM.get(cat, "EquipmentDefs.Category.ACCESSORY"))
		var slot_e: String = "EquipmentDefs.Slot.WEAPON_1" if cat == "WEAPON" \
			else str(SLOT_ENUM.get(wtype, "EquipmentDefs.Slot.ACCESSORY_1"))
		var wt: String = wtype if cat == "WEAPON" else ""
		var tags: String = str(WEAPON_TAGS.get(wt, "")) if cat == "WEAPON" else ""

		# 基础属性：武器给攻击/法强；**防御武器无攻击**（规格）；其余给防御
		var base := ""
		if cat == "WEAPON":
			var v: float = 35.0 * float(RAR_SCALE.get(rar, 1.6)) * float(WT_MULT.get(wt, 1.0))
			var bs := "Stat.AP" if wt == "staff" else ("Stat.DEF" if wt == "shield" else "Stat.ATK")
			base = "[[%s, %.1f, false]]" % [bs, v]
		else:
			base = "[[Stat.DEF, %.1f, false]]" % (12.0 * float(RAR_SCALE.get(rar, 1.6)) * 0.35)

		var own_a := _parse_affix_text(own)
		var dev_a := _parse_affix_text(dev)
		var fus_a := _parse_affix_text(fus)

		var tag_s := "[]"
		if not tags.is_empty():
			var parts := tags.split(",")
			var quoted: Array[String] = []
			for p in parts:
				quoted.append("\"%s\"" % p)
			tag_s = "[%s]" % ", ".join(quoted)
		var wt_s := "\"%s\"" % wt if not wt.is_empty() else "\"\""

		rows.append("  [\"%s\", \"%s\", %s, %s, %s, %s, %s, %s, %s, %s]," % [
			id, name, wt_s, tag_s, slot_e, cat_e, base, own_a, dev_a, fus_a])

	for r in rows:
		print(r)

	# —— 报告（stderr，不污染 stdout 的数据）——
	print_rich_unmapped()


func print_rich_unmapped() -> void:
	var counts := {}
	for u in _unmapped:
		counts[u] = int(counts.get(u, 0)) + 1
	printerr("\n=== 无法自动映射的词条：%d 条去重 ===" % counts.size())
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	for k in keys:
		printerr("  [%d] %s" % [counts[k], k])
	printerr("=== 装备技能修饰（已跳过，不属于词条）：%d 条 ===" % _skill_notes)
	quit(0)


## 解析一整条词条文本（可能含「；」分隔的复合效果）→ GDScript 数组字面量
func _parse_affix_text(text: String) -> String:
	if text.strip_edges().is_empty():
		return "[]"
	var parts := text.split("；")
	var out: Array[String] = []
	for p in parts:
		# 也按半角分号拆（规格里两种都出现过）
		for q in p.split(";"):
			var r := _parse_one(q.strip_edges())
			if r.is_empty():
				continue
			if r == "__SKILL__":
				_skill_notes += 1
			else:
				out.append(r)
	return "[%s]" % ", ".join(out)


## 解析**单条**效果。返回：
##   ""           —— 无法映射（已记入 _unmapped）
##   "__SKILL__"  —— 装备技能的修饰（不属于词条层级）
##   其他         —— 词条规格的 GDScript 字面量
func _parse_one(s: String) -> String:
	if s.is_empty():
		return ""
	# ---------- 0. 装备技能的修饰（**不是词条**） ----------
	if s.begins_with("主动技能"):
		return "__SKILL__"
	if _RE_SKILL_NOTE.search(s) != null:
		return "__SKILL__"

	# ---------- 1. 攻击附带元素伤害（规格 #4） ----------
	var m := _re(r"攻击附带\s*(\d+)%\s*(火焰|冰霜|雷电|毒素|大地|疾风)伤害").search(s)
	if m:
		var ek: String = str(ELEM_KEY.get(m.get_string(2), "fire"))
		return "[%d, \"%s\", %s]" % [OP_BONUS_ELEMENT, ek, _f(m.get_string(1))]
	m = _re(r"攻击附带\s*(\d+)%\s*吸血").search(s)
	if m:
		return "[%d, %s, true]" % [SP["lifesteal"], _f(m.get_string(1))]
	m = _re(r"攻击附带\s*(\d+)%\s*减速").search(s)
	if m:
		return "[%d, \"slow\", 1.0, 2.0]" % OP_TRIGGER_BUFF
	m = _re(r"攻击附带穿透效果.*无视.*?(\d+)%\s*护甲").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_pen"], _f(m.get_string(1))]

	# ---------- 2. 攻击概率触发（规格 #2） ----------
	# 「攻击必定施加中毒（每秒20%攻击力毒素伤害，持续5秒，最多5层）」
	m = _re(r"攻击必定施加(中毒|流血|燃烧)").search(s)
	if m:
		var dur := 0.0
		var md0 := _re(r"持续\s*(\d+(?:\.\d+)?)\s*秒").search(s)
		if md0:
			dur = float(md0.get_string(1))
		return "[%d, \"%s\", 1.0, %.1f]" % [
			OP_TRIGGER_BUFF, str(BUFF_OF.get(m.get_string(1), "poison_rot")), dur]
	m = _re(r"攻击有\s*(\d+)%\s*概率\s*(冰冻|麻痹|眩晕|缠绕|减速|中毒|燃烧|点燃|标记|沉默|缴械|恐惧|嘲讽)").search(s)
	if m:
		var dur := 0.0
		var md := _re(r"(\d+(?:\.\d+)?)\s*秒").search(s)
		if md:
			dur = float(md.get_string(1))
		return "[%d, \"%s\", %s, %.1f]" % [
			OP_TRIGGER_BUFF, str(BUFF_OF.get(m.get_string(2), "slow")),
			_f(m.get_string(1)), dur]

	# ---------- 3. 击杀叠层（规格 #3） ----------
	m = _re(r"击杀敌人获得\s*\d+\s*层.*?最多\s*(\d+)\s*层.*?每层\s*\+?(\d+)%\s*(?:攻击力|伤害|资源回复|背刺伤害)").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, %s]" % [
			OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(2)), m.get_string(1)]
	m = _re(r"击杀敌人回复\s*(\d+)\s*点职业资源").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, SP["exp_gain"], _f(m.get_string(1))]
	m = _re(r"击杀敌人回复\s*(\d+(?:\.\d+)?)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	if _re(r"击杀敌人后立即重置冲刺冷却").search(s):
		return "[%d, 1.0, true]" % SP["cd_refresh"]
	m = _re(r"击杀敌人有\s*(\d+)%\s*概率额外掉落\s*\d+\s*枚金币").search(s)
	if m:
		return "[%d, \"bonus_gold\", %s, 0.0]" % [OP_TRIGGER_BUFF, _f(m.get_string(1))]

	# ---------- 4. 受击触发（规格 #8） ----------
	m = _re(r"每受到一次伤害.*?(防御力|攻击力|护甲)\s*增加\s*(\d+)%.*?叠加\s*(\d+)\s*层").search(s)
	if m:
		var stat: String = str(STAT_ENUM.get(m.get_string(1), "Stat.DEF"))
		return "[%d, %d, %s, %s, %s]" % [
			OP_STACK_GAIN, TRIG_ON_HURT, stat, _f(m.get_string(2)), m.get_string(3)]
	m = _re(r"受到伤害时获得\s*\d+\s*层.*?最多\s*(\d+)\s*层.*?每层\s*\+?(\d+)%\s*(?:攻击力|背刺伤害)").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, %s]" % [
			OP_STACK_GAIN, TRIG_ON_HURT, _f(m.get_string(2)), m.get_string(1)]
	m = _re(r"受到伤害后.*?对周围造成.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HURT, _f(m.get_string(1))]
	m = _re(r"受到(火焰|冰霜|雷电|毒素|大地|疾风)伤害减少\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(2))]
	m = _re(r"受到的控制效果持续时间减少\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["ctrl_resist"], _f(m.get_string(1))]
	m = _re(r"受到近战攻击时.*?反弹\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	m = _re(r"^反弹\s*(\d+)%\s*(?:近战|所有)?\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	m = _re(r"受到致命伤害时.*?免疫.*?恢复?\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HURT, _f(m.get_string(1))]

	# ---------- 5. 低血 / 处决（规格 #13） ----------
	m = _re(r"生命低于\s*\d+%\s*时.*?(\d+)%\s*伤害减免").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"对生命值?低于\s*\d+%\s*的敌人.*?额外\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f(m.get_string(1))]
	m = _re(r"对满血敌人造成额外\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f(m.get_string(1))]

	# ---------- 6. 格挡 / 闪避 / 冲刺 ----------
	m = _re(r"格挡成功.*?最多\s*(\d+)\s*层.*?每层\s*\+?(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %d, %d, %s, %s]" % [
			OP_STACK_GAIN, TRIG_ON_BLOCK, SP["elem_resist"], _f(m.get_string(2)), m.get_string(1)]
	m = _re(r"格挡率?\s*(?:增加|\+)?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["block"], _f(m.get_string(1))]
	m = _re(r"闪避时有\s*(\d+)%\s*概率立即刷新冲刺冷却").search(s)
	if m:
		return "[%d, %s, true]" % [SP["cd_refresh"], _f(m.get_string(1))]
	m = _re(r"闪避率?\s*(?:增加|\+)?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["dodge"], _f(m.get_string(1))]
	m = _re(r"冲刺冷却减少\s*(\d+)%").search(s)
	if m:
		return "[Stat.CDR, %s, true]" % _f(m.get_string(1))
	m = _re(r"冲刺后获得\s*(\d+)%\s*移速").search(s)
	if m:
		return "[Stat.SPD, %s, true]" % _f(m.get_string(1))

	# ---------- 7. 元素 / 吸血 / 连击 / 暴击 ----------
	m = _re(r"所有元素伤害\s*(?:增加|\+)?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"所有元素抗性\s*(?:增加|\+)?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"攻击无视(?:目标)?\s*(\d+)%\s*元素抗性").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_pen"], _f(m.get_string(1))]
	m = _re(r"对应元素伤害增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"获得\s*(\d+(?:\.\d+)?)%\s*生命偷取").search(s)
	if m:
		return "[%d, %s, true]" % [SP["lifesteal"], _f(m.get_string(1))]
	m = _re(r"生命偷取\s*(?:增加|\+)?\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["lifesteal"], _f(m.get_string(1))]
	m = _re(r"连击伤害增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_COMBO, _f(m.get_string(1))]
	m = _re(r"连续攻击同一目标时.*?每次.*?\+?(\d+)%.*?最多\s*(\d+)\s*层").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, %s]" % [
			OP_STACK_GAIN, TRIG_ON_COMBO, _f(m.get_string(1)), m.get_string(2)]
	m = _re(r"暴击叠加\s*\d+\s*层.*?最多\s*(\d+)\s*层.*?每层\s*\+?(\d+)%\s*暴击伤害").search(s)
	if m:
		return "[%d, %d, Stat.CRD, %s, %s]" % [
			OP_STACK_GAIN, TRIG_ON_CRIT, _f(m.get_string(2)), m.get_string(1)]
	m = _re(r"从背后攻击造成额外\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[Stat.CRD, %s, true]" % _f(m.get_string(1))

	# ---------- 8. 经济 / 召唤 / 命中回复 ----------
	m = _re(r"金币获取(?:量)?\s*(?:增加|\+)?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["gold_gain"], _f(m.get_string(1))]
	m = _re(r"出售装备价格增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["sell_price"], _f(m.get_string(1))]
	m = _re(r"钥匙碎片掉落(?:概率|\+)?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["key_drop"], _f(m.get_string(1))]
	m = _re(r"召唤物上限\s*\+?\s*(\d+)").search(s)
	if m:
		return "[%d, %s, false]" % [SP["summon_limit"], m.get_string(1)]
	m = _re(r"召唤物伤害\s*(?:增加|\+)?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["summon_dmg"], _f(m.get_string(1))]
	m = _re(r"(?:攻击命中|每击杀一个敌人|击杀敌人)回复\s*(\d+(?:\.\d+)?)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(1))]
	m = _re(r"攻击命中回复\s*(\d+)\s*点职业资源").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, SP["exp_gain"], _f(m.get_string(1))]

	# ---------- 9. 数值型（统一查找：面板属性优先，再扩展通道） ----------
	#
	# 覆盖三种写法（规格的吞噬/融合列大量使用后两种）：
	#   「攻击力增加3%」/「攻击力+5%」   —— 名称在前
	#   「获得0.5%吸血」                 —— 数值在前（前缀「获得」）
	#   「获得1%火焰伤害提升」           —— 数值在前 + 后缀「提升」
	var nm := ""
	var v := 0.0
	m = _re(r"^(.+?)\s*(?:增加|提升|\+)\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		nm = m.get_string(1)
		v = float(m.get_string(2)) / 100.0
	else:
		m = _re(r"^获得\s*(\d+(?:\.\d+)?)%\s*(.+?)(?:提升|增加)?$").search(s)
		if m:
			nm = m.get_string(2)
			v = float(m.get_string(1)) / 100.0
	if not nm.is_empty():
		# ① 面板属性（含「最大生命值」这类带后缀的）
		var stat_name := nm.trim_suffix("值")
		if STAT_ENUM.has(stat_name):
			return "[%s, %.4f, true]" % [STAT_ENUM[stat_name], v]
		# ② 扩展通道
		if EXT_BY_NAME.has(nm):
			return "[%d, %.4f, true]" % [SP[EXT_BY_NAME[nm]], v]
		# ③ 全属性（规格只说"全属性"，不擅自拆多条）
		if nm.contains("全属性") or nm.contains("所有基础属性"):
			return "[Stat.ATK, %.4f, true]" % v
		# ④ 职业资源 / 资源回复
		if nm.contains("职业资源") or nm.contains("资源回复"):
			return "[%d, %.4f, true]" % [SP["exp_gain"], v]
		# ⑤ 时长类
		if nm.contains("增益效果持续时间"):
			return "[%d, %.4f, true]" % [SP["debuff_dur"], v]
		if nm.contains("技能冷却缩减"):
			return "[Stat.CDR, %.4f, true]" % v
		# ⑥ 减伤 / 增伤
		if nm.contains("减伤"):
			return "[%d, %.4f, true]" % [SP["elem_resist"], v]
		if nm.contains("增伤") or nm.contains("伤害"):
			return "[%d, %.4f, true]" % [SP["elem_dmg"], v]
		# ⑦ 「XX效果」这类（强化效果/标记效果…）→ 归到攻击力（最通用的增伤口径）
		if nm.ends_with("效果"):
			return "[Stat.ATK, %.4f, true]" % v

	# ---------- 10. 收尾：少量明确的一次性效果 ----------
	# 「命中3个以上敌人时回复量翻倍」→ 命中回复（规格明确给了触发条件）
	if s.contains("命中3个以上敌人时回复量翻倍"):
		return "[%d, %d, Stat.HP, 0.05, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT]
	# 「结算时额外获得N%记忆残渣」→ 经验获取（同类成长资源）
	m = _re(r"结算时额外获得\s*(\d+)%\s*记忆残渣").search(s)
	if m:
		return "[%d, %s, true]" % [SP["exp_gain"], _f(m.get_string(1))]
	# 「每层Boss额外掉落1片钥匙碎片的概率+N%」
	m = _re(r"额外掉落\s*\d+\s*片钥匙碎片的概率\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["key_drop"], _f(m.get_string(1))]
	# 「毒雾内敌人移速-N%」
	m = _re(r"敌人移速\s*-\s*(\d+)%").search(s)
	if m:
		return "[%d, \"slow\", 1.0, 3.0]" % OP_TRIGGER_BUFF

	# ---------- 无法映射 ----------
	_unmapped.append(s)
	return ""


## 数值字符串 → 百分比浮点（"50" → "0.5000"）
func _f(pct: String) -> String:
	return "%.4f" % (float(pct) / 100.0)


var _re_cache := {}
func _re(pattern: String) -> RegEx:
	if _re_cache.has(pattern):
		return _re_cache[pattern]
	var r := RegEx.new()
	r.compile(pattern)
	_re_cache[pattern] = r
	return r

## 装备技能修饰的识别（这些在修饰某个技能，不是独立词条）
var _RE_SKILL_NOTE: RegEx = _build_skill_note_re()
func _build_skill_note_re() -> RegEx:
	var r := RegEx.new()
	r.compile(r"^(?:治愈术|战吼|护盾|陷阱|毒雾|疾风步|反击姿态|时间减缓|强化效果|闪现|圣光|烈焰|冰霜|雷霆|旋风|冲锋|突刺|盾击|召唤|狼灵|分身|残影|图腾|领域|新星|爆发|箭雨|火球|地刺|落石|风刃|缠绕|净化|驱散|嘲讽|挑衅|锁链|击退|生命汲取|灵魂|暗影|星辰|时空|荆棘|无畏|加速|疾跑|护盾术|治愈|治疗|资源|元素|号令|脉冲|光环).*(?:期间|同时|触发时|被击破时|存在时|留下|释放|引爆|翻倍|清除|满层时)")
	return r
