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
const TRIG_ON_DODGE := 4
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
## 规格占位符计数（设计说明，不是词条）
var _placeholders := 0


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

	# ---------- 10. 满层/层时触发（融合列为主，规格：机制补全） ----------
	#
	# 形态：「满层时…」「5层时…」「叠满3层时…」。
	# 这些是**叠层机制的结算**——按规格映射为「叠层 + 结算效果」。
	m = _re(r"满层时下次攻击释放.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, 5, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, _f(m.get_string(1))]
	m = _re(r"满层时下次攻击额外攻击\s*(\d+)\s*次").search(s)
	if m:
		return "[%d, 5, Stat.ATK, 0.40, 0]" % OP_STACK_GAIN
	m = _re(r"满层时释放.*?(\d+)%\s*(?:攻击力|法强|雷电)").search(s)
	if m:
		return "[%d, 5, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, _f(m.get_string(1))]
	m = _re(r"(\d+)层时.*?获得吸收\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(2))]
	m = _re(r"(\d+)层时.*?必定暴击").search(s)
	if m:
		return "[%d, %d, Stat.CRT, 0.50, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT]
	if s.contains("满层时免疫下一次控制") or s.contains("满层时免疫控制"):
		return "[%d, 0.30, true]" % SP["ctrl_resist"]
	if s.contains("满层时受到致命伤害"):
		return "[%d, %d, Stat.HP, 0.30, 0]" % [OP_STACK_GAIN, TRIG_ON_HURT]
	if s.contains("满层时技能消耗减半"):
		return "[%d, 0.50, true]" % SP["exp_gain"]
	if s.contains("叠满后下次技能不消耗资源") or s.contains("叠满3层时，下次技能不消耗资源"):
		return "[%d, 1.0, true]" % SP["exp_gain"]
	m = _re(r"叠满\s*\d+\s*层时.*?释放.*?(\d+)%\s*法强").search(s)
	if m:
		return "[%d, 5, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, _f(m.get_string(1))]

	# ---------- 11. 技能增强类（「使用技能后…」「下次技能…」） ----------
	m = _re(r"使用技能后，下次攻击伤害提高\s*(\d+)%").search(s)
	if m:
		return "[%d, \"atk_up_self\", 1.0, 0.0]" % OP_TRIGGER_BUFF
	m = _re(r"使用技能后，下次技能冷却-?(\d+)%").search(s)
	if m:
		return "[Stat.CDR, %s, true]" % _f(m.get_string(1))
	m = _re(r"技能冷却缩减\s*(\d+)%").search(s)
	if m:
		return "[Stat.CDR, %s, true]" % _f(m.get_string(1))
	m = _re(r"减少冷却提升至\s*(\d+)\s*秒").search(s)
	if m:
		return "[Stat.CDR, 0.20, true]"
	if s.contains("触发时额外释放一次该技能") or s.contains("下次技能额外释放一次"):
		return "[%d, \"atk_up_self\", 1.0, 0.0]" % OP_TRIGGER_BUFF

	# ---------- 12. 资源型（记忆残渣 / 钥匙碎片 / 金币持有量） ----------
	m = _re(r"每点记忆残渣.*?攻击力提高\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"每点记忆残渣\s*\+?(\d+(?:\.\d+)?)%\s*全属性").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"每持有?一片钥匙碎片.*?全属性提高\s*(\d+)%").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"每持有?一片钥匙碎片，\s*\+?(\d+)%\s*全属性").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"每(?:持有)?\s*100\s*金币.*?攻击力提高\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"每持有\s*100\s*金币，\s*\+?(\d+)%\s*攻击力").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"每装备一件(?:传奇|红色)装备.*?全属性提高\s*(\d+)%").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"每装备一件红色装备额外\s*\+?(\d+)%\s*暴击伤害").search(s)
	if m:
		return "[Stat.CRD, %s, true]" % _f(m.get_string(1))
	m = _re(r"记忆残渣获取\s*(?:增加|\+)?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["exp_gain"], _f(m.get_string(1))]
	m = _re(r"击杀精英(?:敌人)?获得\s*(\d+)\s*点记忆残渣").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, SP["exp_gain"], _f(m.get_string(1))]
	m = _re(r"击杀精英(?:敌人)?获得\s*\d+\s*点记忆残渣").search(s)
	if m:
		return "[%d, %d, %d, 0.01, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, SP["exp_gain"]]
	m = _re(r"金币超过\s*\d+\s*时，暴击率\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[Stat.CRT, %s, true]" % _f(m.get_string(1))

	# ---------- 13. 召唤物类 ----------
	m = _re(r"每个召唤物\s*\+?(\d+)%\s*召唤物伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["summon_dmg"], _f(m.get_string(1))]
	if s.contains("召唤物数量+1"):
		return "[%d, 1, false]" % SP["summon_limit"]
	if s.contains("召唤物死亡时爆炸") or s.contains("守卫死亡时爆炸") \
			or s.contains("图腾死亡时爆炸") or s.contains("分身死亡时爆炸") \
			or s.contains("灵魂死亡时爆炸"):
		return "[%d, 0.10, true]" % SP["summon_dmg"]
	if s.contains("召唤物存在时") or s.contains("链接期间") or s.contains("守护期间"):
		return "[%d, 0.05, true]" % SP["elem_resist"]

	# ---------- 14. 击杀/闪避/格挡的后续效果 ----------
	m = _re(r"击杀精英后，回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	m = _re(r"击杀低血量敌人时，回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	m = _re(r"击杀精英后，下次攻击\s*\+?(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	if s.contains("击杀低血量敌人时，重置一个技能冷却") or s.contains("击杀目标后刷新冷却"):
		return "[%d, 1.0, true]" % SP["cd_refresh"]
	m = _re(r"闪避成功后获得\s*\d+\s*秒\s*\+?(\d+)%\s*闪避").search(s)
	if m:
		return "[%d, %s, true]" % [SP["dodge"], _f(m.get_string(1))]
	m = _re(r"闪避成功后，下次攻击伤害提高\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_DODGE, _f(m.get_string(1))]
	m = _re(r"闪避成功时，对攻击者造成\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	m = _re(r"格挡成功后.*?对攻击者造成\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	m = _re(r"格挡成功后，反弹\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	m = _re(r"格挡成功叠加\s*\d+\s*层.*?每层\s*\+?(\d+)%\s*下次攻击伤害").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 5]" % [OP_STACK_GAIN, TRIG_ON_BLOCK, _f(m.get_string(1))]

	# ---------- 15. 消耗 / 代价类 ----------
	m = _re(r"攻击消耗\s*\d+%\s*生命，但吸血提高\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["lifesteal"], _f(m.get_string(1))]
	m = _re(r"击杀敌人回复消耗生命的\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	if s.contains("消耗金币代替生命"):
		return "[%d, 0.10, true]" % SP["gold_gain"]

	# ---------- 16. 数值型补充 ----------
	m = _re(r"每秒回复\s*(\d+(?:\.\d+)?)%\s*最大生命").search(s)
	if m:
		return "[%d, %s, true]" % [SP["lifesteal"], _f(m.get_string(1))]
	m = _re(r"生命值低于\s*\d+%\s*时，额外获得\s*(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"生命低于\s*\d+%\s*时，攻击力\s*\+?(\d+)%").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"周围敌人护甲\s*-\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_pen"], _f(m.get_string(1))]
	m = _re(r"周围敌人每秒受到\s*(\d+)%\s*攻击力伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"箭雨内敌人受到暴击率\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f(m.get_string(1))]
	m = _re(r"(?:控制|麻痹|无敌)时间(?:延长|提升)至\s*(\d+(?:\.\d+)?)\s*秒").search(s)
	if m:
		return "[%d, 0.30, true]" % SP["debuff_dur"]
	m = _re(r"增益持续时间增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["debuff_dur"], _f(m.get_string(1))]
	m = _re(r"控制持续时间增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["debuff_dur"], _f(m.get_string(1))]
	m = _re(r"冰霜抗性增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"反弹伤害有\s*(\d+)%\s*概率").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	m = _re(r"攻击附加当前生命值\s*(\d+)%\s*的额外伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["true_dmg"], _f(m.get_string(1))]
	m = _re(r"每损失\s*10%\s*生命，?攻击力提高\s*(\d+)%").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"攻击有\s*(\d+)%\s*概率造成双倍伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["true_dmg"], _f(m.get_string(1))]
	m = _re(r"攻击有\s*(\d+)%\s*概率追加一次").search(s)
	if m:
		return "[%d, %s, true]" % [SP["true_dmg"], _f(m.get_string(1))]
	m = _re(r"远程攻击有\s*(\d+)%\s*概率额外发射").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"额外投射物命中同一目标时，伤害递增\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"攻击施加.*?每层\s*\+?(\d+)%\s*暴击率").search(s)
	if m:
		return "[Stat.CRT, %s, true]" % _f(m.get_string(1))
	m = _re(r"攻击施加.*?每层\s*\+?(\d+)%\s*受到伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f(m.get_string(1))]
	m = _re(r"暴击时减少所有技能冷却\s*(\d+)\s*秒").search(s)
	if m:
		return "[Stat.CDR, 0.20, true]"
	m = _re(r"护盾值\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"吸血提高至\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["lifesteal"], _f(m.get_string(1))]
	m = _re(r"处决阈值提升至\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f(m.get_string(1))]
	m = _re(r"对满血敌人伤害提升至\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f(m.get_string(1))]
	m = _re(r"处决成功后回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]

	# ---------- 17. 元素附魔 / 状态类 ----------
	if s.contains("附加对应元素状态") or s.contains("触发元素爆发") \
			or s.contains("施加随机异常状态"):
		return "[%d, \"burn\", 0.15, 3.0]" % OP_TRIGGER_BUFF
	m = _re(r"受到元素伤害后，武器获得该元素附魔").search(s)
	if m:
		return "[%d, \"fire\", 0.50]" % OP_BONUS_ELEMENT
	m = _re(r"每次攻击切换元素.*?下次攻击\s*\+?(\d+)%\s*对应元素伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"每\s*10\s*秒获得随机元素抗性\s*\+?(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]

	# ---------- 18. 隐身类 ----------
	if s.contains("隐身期间免疫控制") or s.contains("隐身期间免疫"):
		return "[%d, 0.30, true]" % SP["ctrl_resist"]
	m = _re(r"隐身期间暴击率\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[Stat.CRT, %s, true]" % _f(m.get_string(1))
	if s.contains("隐身期间击杀敌人，刷新隐身") or s.contains("进入战斗后每5秒获得1秒隐身"):
		return "[%d, 0.30, true]" % SP["dodge"]
	if s.contains("隐身期间下次攻击必定暴击"):
		return "[Stat.CRT, 0.30, true]"

	# ---------- 19. 叠层保留 / 移动叠层 ----------
	m = _re(r"满层攻击后，?移速加成保留\s*(\d+)\s*秒").search(s)
	if m:
		return "[Stat.SPD, 0.10, true]"
	m = _re(r"满层攻击后攻速加成保留\s*(\d+)\s*秒").search(s)
	if m:
		return "[Stat.ASPD, 0.10, true]"
	m = _re(r"移动时叠加.*?每层\s*\+?(\d+)%\s*移速").search(s)
	if m:
		return "[%d, 10, Stat.SPD, %s, 0]" % [OP_STACK_GAIN, _f(m.get_string(1))]
	m = _re(r"每次冲刺叠加\s*\d+\s*层.*?每层\s*\+?(\d+)%\s*闪避").search(s)
	if m:
		return "[%d, %s, true]" % [SP["dodge"], _f(m.get_string(1))]
	m = _re(r"(\d+)层时.*?消耗所有层数获得吸收\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(2))]

	# ---------- 20. 标记 / 引爆类 ----------
	if s.contains("对5层标记目标攻击必定暴击") or s.contains("歼灭射击对5层以上标记目标必定暴击"):
		return "[Stat.CRT, 0.30, true]"
	m = _re(r"(\d+)层时下一次攻击引爆所有毒层.*?每层\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, %s]" % [
			OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(2)), m.get_string(1)]
	m = _re(r"(\d+)层时触发冰爆.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, %s]" % [
			OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(2)), m.get_string(1)]
	if s.contains("暴击时标记扩散") or s.contains("标记转移至周围敌人"):
		return "[%d, %s, true]" % [SP["execute_line"], _f("5")]
	m = _re(r"暴击时\s*(\d+)%\s*概率立即刷新一个技能冷却").search(s)
	if m:
		return "[%d, %s, true]" % [SP["cd_refresh"], _f(m.get_string(1))]

	# ---------- 21. 召唤 / 分身 / 图腾 ----------
	if s.contains("冲刺后留下分身") or s.contains("冲刺后留下残影") \
			or s.contains("召唤") and s.contains("持续") and s.contains("秒"):
		return "[%d, 0.10, true]" % SP["summon_dmg"]
	m = _re(r"(?:分身|残影|守卫|图腾|灵魂|元素灵体)攻击造成\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["summon_dmg"], _f(m.get_string(1))]
	if s.contains("主动放置图腾") or s.contains("主动放置陷阱") or s.contains("主动投掷标枪"):
		return "[%d, 0.10, true]" % SP["summon_dmg"]

	# ---------- 22. 震击 / 冲击波 / 范围 ----------
	m = _re(r"攻击造成范围震击.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"震击有\s*(\d+)%\s*概率眩晕").search(s)
	if m:
		return "[%d, \"stun\", %s, 1.0]" % [OP_TRIGGER_BUFF, _f(m.get_string(1))]
	m = _re(r"储存满时，攻击附带范围震击").search(s)
	if m:
		return "[%d, 0.50, true]" % SP["elem_dmg"]
	m = _re(r"每移动\s*\d+\s*米，释放一次冲击波.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"剑气命中\s*\d+\s*个以上敌人时，伤害提升至\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]

	# ---------- 23. 投射物 / 弹射 / 分裂 ----------
	m = _re(r"分裂箭弹射次数\s*\+?\s*(\d+)").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("10")]
	m = _re(r"分裂箭命中后弹射至最近敌人.*?(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"攻击有\s*(\d+)%\s*概率分裂为\s*\d+\s*枚额外弩箭").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	if s.contains("额外投射物可触发弹射"):
		return "[%d, 0.10, true]" % SP["elem_dmg"]
	m = _re(r"跳跃次数\s*\+?\s*(\d+)").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("15")]
	m = _re(r"麻痹目标受到雷电伤害时，雷电跳跃至最近\s*\d+\s*名敌人.*?(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]

	# ---------- 24. 低血 / 生命相关 ----------
	if s.contains("自身生命低于50%时效果翻倍") or s.contains("生命满时，回复量转化为护盾"):
		return "[%d, %s, true]" % [SP["lifesteal"], _f("10")]
	m = _re(r"治疗时额外获得治疗量\s*(\d+)%\s*的护盾").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"受到伤害的\s*(\d+)%\s*延迟").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	if s.contains("取消延迟伤害时") or s.contains("期间若击杀敌人，则取消延迟伤害"):
		return "[%d, %d, Stat.ATK, 0.10, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL]

	# ---------- 25. 其它数值型 ----------
	m = _re(r"强化效果提升至\s*(\d+)%").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"元素抗性超过\s*\d+%\s*时，攻击附带对应元素伤害.*?(\d+)%").search(s)
	if m:
		return "[%d, \"fire\", %s]" % [OP_BONUS_ELEMENT, _f(m.get_string(1))]
	m = _re(r"抗性触发时，对周围造成对应元素伤害.*?(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"击杀敌人后，光环范围\s*\+?\s*(\d+)\s*米").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("5")]
	m = _re(r"光环内敌人死亡时，回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	m = _re(r"窃取增益时，对周围敌人造成\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"击杀敌人有\s*(\d+)%\s*概率窃取其增益效果").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	m = _re(r"释放终极技能消耗所有灵魂，每层\s*\+?(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, 15, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, _f(m.get_string(1))]
	m = _re(r"复仇波命中敌人回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(1))]
	m = _re(r"连续\s*(\d+)\s*次不同元素后，触发元素爆炸.*?(\d+)%\s*法强").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(2))]
	m = _re(r"同元素连用则伤害\s*-\s*(\d+)%").search(s)
	if m:
		return "[Stat.ATK, -%s, true]" % _f(m.get_string(1))
	m = _re(r"流血目标死亡时，流血扩散至周围\s*(\d+)\s*米").search(s)
	if m:
		return "[%d, \"bleed\", 0.30, 3.0]" % OP_TRIGGER_BUFF
	m = _re(r"闪避成功时立即刷新冲刺冷却").search(s)
	if m:
		return "[%d, 1.0, true]" % SP["cd_refresh"]
	if s.contains("机制强化") or s.contains("被动增益"):
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("10")]

	# ---------- 26. 技能附加效果（融合列为主：给技能加料） ----------
	#
	# 形态：「<技能>命中后…」「<技能>造成眩晕N秒」「<技能>留下…区域」。
	# 这些是**给装备技能加的效果**——但规格把它们写在词条列里，
	# 故按「该效果的等价常驻加成」映射（保守：取最接近的通道）。
	m = _re(r"(?:地裂|地刺|震击|雷霆一击)造成眩晕\s*(\d+(?:\.\d+)?)\s*秒").search(s)
	if m:
		return "[%d, \"stun\", 1.0, %s]" % [OP_TRIGGER_BUFF, m.get_string(1)]
	m = _re(r"(?:燃烧|爆炸|火焰吐息|火球|坠落点|星尘).*?每秒\s*(\d+)%\s*法强").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"(?:陷阱|护卫|藤蔓|飞斧).*?对周围\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"(?:飞斧|风之箭|标枪)命中后.*?(?:弹射|牵引)").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("15")]
	m = _re(r"(?:星辰碎片|剑气|火球|爆炸)命中\s*\d+\s*个以上敌人时，?伤害提升至\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"牵引\s*\d+\s*个以上敌人时，触发风爆.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"连续\s*\d+\s*次不同元素后触发混沌爆炸.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"圣光新星对亡灵额外造成\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f(m.get_string(1))]
	m = _re(r"狼灵攻击有\s*(\d+)%\s*概率造成流血").search(s)
	if m:
		return "[%d, \"bleed\", %s, 3.0]" % [OP_TRIGGER_BUFF, _f(m.get_string(1))]
	m = _re(r"影闪后\s*\d+\s*秒内暴击率\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[Stat.CRT, %s, true]" % _f(m.get_string(1))
	if s.contains("隐身期间移速"):
		return "[Stat.SPD, 0.20, true]"
	m = _re(r"闪现后下次攻击\s*\+?\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(1))]
	m = _re(r"冲锋后获得\s*\d*\s*秒?\s*(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"驱散成功后获得\s*\d+\s*秒\s*(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	if s.contains("净化后获得3秒霸体"):
		return "[%d, %s, true]" % [SP["ctrl_resist"], _f("50")]
	m = _re(r"沉默箭命中后目标移速\s*-\s*(\d+)%").search(s)
	if m:
		return "[%d, \"slow\", 1.0, 3.0]" % OP_TRIGGER_BUFF
	m = _re(r"命中时牵引目标\s*(\d+)\s*米").search(s)
	if m:
		return "[%d, \"pull\", 1.0, 0.0]" % OP_TRIGGER_BUFF

	# ---------- 27. 元素附带（变体写法） ----------
	m = _re(r"攻击附带风元素（(\d+)%攻击力）").search(s)
	if m:
		return "[%d, \"wind\", %s]" % [OP_BONUS_ELEMENT, _f(m.get_string(1))]
	m = _re(r"每次攻击随机附带一种元素伤害（(\d+)%攻击力）").search(s)
	if m:
		return "[%d, \"fire\", %s]" % [OP_BONUS_ELEMENT, _f(m.get_string(1))]
	if s.contains("混沌爆炸附加随机元素状态") or s.contains("元素灵体攻击附带元素状态"):
		return "[%d, \"burn\", 0.30, 3.0]" % OP_TRIGGER_BUFF
	if s.contains("满层时下次攻击附带风元素"):
		return "[%d, \"wind\", 1.0]" % OP_BONUS_ELEMENT
	m = _re(r"获得冰霜护盾（吸收\s*(\d+)%最大生命").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]

	# ---------- 28. 护甲穿透 / 无视护甲 ----------
	m = _re(r"攻击无视\s*(\d+)%\s*护甲").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_pen"], _f(m.get_string(1))]
	m = _re(r"击杀敌人后，下次攻击无视\s*(\d+)%\s*护甲").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_pen"], _f(m.get_string(1))]
	m = _re(r"攻击有\s*(\d+)%\s*概率破除目标隐身/护盾，并造成\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_pen"], _f(m.get_string(2))]
	m = _re(r"破除护盾时，对周围造成\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]

	# ---------- 29. 蓄力 / 储存 ----------
	if s.contains("静止不动时每秒储存"):
		return "[%d, Stat.ATK, 0.15, 1.50]" % 6   # OP_CHARGE
	if s.contains("下次攻击释放全部储存伤害"):
		return "[%d, Stat.ATK, 0.15, 1.50]" % 6

	# ---------- 30. 其它 ----------
	m = _re(r"出售装备有\s*(\d+)%\s*概率获得双倍金币").search(s)
	if m:
		return "[%d, %s, true]" % [SP["gold_gain"], _f(m.get_string(1))]
	m = _re(r"灵魂获取增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["exp_gain"], _f(m.get_string(1))]
	if s.contains("暗影波击杀敌人时，层数不清空") or s.contains("雷电新星触发后，充能层数不清空"):
		return "[%d, 15, Stat.ATK, 0.02, 0]" % OP_STACK_GAIN
	if s.contains("受到伤害时获得1层“充能”"):
		return "[%d, %d, Stat.ATK, 0.02, 5]" % [OP_STACK_GAIN, TRIG_ON_HURT]
	m = _re(r"(?:燃烧|爆炸)范围(?:扩大|\+)\s*(\d+)\s*米?").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("10")]
	if s.contains("复仇满层时，背刺必定暴击") or s.contains("背刺消耗所有层数"):
		return "[Stat.CRD, 0.30, true]"
	if s.contains("生命满时，回复转化为护盾") or s.contains("生命满时，回复量转化为护盾"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("10")]
	m = _re(r"受到近战攻击时，对攻击者施加燃烧").search(s)
	if m:
		return "[%d, \"burn\", 1.0, 3.0]" % OP_TRIGGER_BUFF
	m = _re(r"使用技能后，下次技能冷却-?(\d+)\s*秒").search(s)
	if m:
		return "[Stat.CDR, 0.20, true]"

	# ---------- 31. 兜底：技能附加的伤害/控制（第三批） ----------
	#
	# 形态：「<技能>造成眩晕N秒」「<技能>对路径/周围敌人造成N%伤害」。
	# 这些都在给某个装备技能加效果——映射为等价常驻加成（保守）。
	m = _re(r"(?:落石|风刃|标枪|飞斧|藤蔓|护卫|陷阱|冰爆).*?造成眩晕\s*(\d+(?:\.\d+)?)\s*秒").search(s)
	if m:
		return "[%d, \"stun\", 1.0, %s]" % [OP_TRIGGER_BUFF, m.get_string(1)]
	m = _re(r"(?:风刃|标枪|飞斧|回收标枪).*?(?:牵引|路径敌人)").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("15")]
	m = _re(r"(?:标枪落点|陷阱触发后|护卫死亡|藤蔓消失|冰锥).*?对(?:周围|路径|同一目标).*?(\d+)%\s*(?:攻击力|法强)").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"冰爆冻结目标\s*(\d+(?:\.\d+)?)\s*秒").search(s)
	if m:
		return "[%d, \"freeze\", 1.0, %s]" % [OP_TRIGGER_BUFF, m.get_string(1)]
	m = _re(r"(?:暗影箭|灵魂爆发)击杀敌人时，?回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	m = _re(r"引爆残影时，每个残影回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	m = _re(r"召唤物死亡时回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	m = _re(r"标记目标死亡时，?回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]

	# ---------- 32. 护盾 / 免疫 ----------
	m = _re(r"进入新房间时获得\s*(\d+)%\s*最大生命护盾").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"生命低于\s*\d+%\s*时，获得\s*(\d+)%\s*最大生命护盾").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"受到元素伤害时获得对应元素护盾（吸收\s*(\d+)%最大生命").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"护盾获取量增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"触发陷阱时有\s*(\d+)%\s*概率免疫伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["dodge"], _f(m.get_string(1))]
	if s.contains("石肤期间免疫击退") or s.contains("血海狂暴期间免疫控制"):
		return "[%d, 0.30, true]" % SP["ctrl_resist"]
	m = _re(r"净化后获得\s*\d+\s*秒\s*(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]

	# ---------- 33. 背刺 / 影舞 ----------
	m = _re(r"每次背刺成功叠加.*?每层\s*\+?(\d+)%\s*攻速").search(s)
	if m:
		return "[Stat.ASPD, %s, true]" % _f(m.get_string(1))
	if s.contains("影舞满层时") or s.contains("影分身攻击视为背刺") or s.contains("背刺击杀敌人时刷新"):
		return "[Stat.CRD, 0.30, true]"
	if s.contains("生命低于50%时进入“血海狂暴”"):
		return "[Stat.ATK, 0.40, true]"
	m = _re(r"血海狂暴期间.*?每秒自动消耗\s*\d+%\s*生命转化为\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))

	# ---------- 34. 消耗生命类 ----------
	m = _re(r"攻击消耗\s*\d+%\s*当前生命，额外造成消耗生命\s*(\d+)%\s*的伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["true_dmg"], _f(m.get_string(1))]

	# ---------- 35. 冲刺 / 资源 / 经济（补充写法） ----------
	m = _re(r"冲刺后获得\s*(\d+)%\s*闪避").search(s)
	if m:
		return "[%d, %s, true]" % [SP["dodge"], _f(m.get_string(1))]
	m = _re(r"冲刺路径留下火焰，对敌人造成\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"冲刺后下次攻击附带\s*(\d+)%\s*额外伤害").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(1))]
	m = _re(r"冲刺冷却\s*-\s*(\d+)%").search(s)
	if m:
		return "[Stat.CDR, %s, true]" % _f(m.get_string(1))
	m = _re(r"资源满时，移速\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[Stat.SPD, %s, true]" % _f(m.get_string(1))
	m = _re(r"召唤物移速(?:增加|\+)?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["summon_dmg"], _f(m.get_string(1))]
	m = _re(r"召唤物攻击有\s*(\d+)%\s*概率触发额外攻击").search(s)
	if m:
		return "[%d, %s, true]" % [SP["summon_dmg"], _f(m.get_string(1))]
	m = _re(r"陷阱触发范围\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"击杀敌人有\s*(\d+)%\s*概率额外掉落\s*\d+\s*金币").search(s)
	if m:
		return "[%d, %s, true]" % [SP["gold_gain"], _f(m.get_string(1))]
	m = _re(r"击杀精英/Boss额外掉落\s*\d+~\d+\s*金币").search(s)
	if m:
		return "[%d, %s, true]" % [SP["gold_gain"], _f("20")]
	m = _re(r"出售价格\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["sell_price"], _f(m.get_string(1))]
	m = _re(r"记忆残渣获取量增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["exp_gain"], _f(m.get_string(1))]
	m = _re(r"击退撞墙敌人受到额外\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["knockback"], _f(m.get_string(1))]
	m = _re(r"受到伤害时反弹\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	m = _re(r"生命低于\s*\d+%\s*时反弹效果翻倍").search(s)
	if m:
		return "[%d, 0.20, true]" % SP["reflect"]
	m = _re(r"格挡时反弹效果翻倍").search(s)
	if m:
		return "[%d, 0.20, true]" % SP["reflect"]
	m = _re(r"攻击有\s*(\d+)%\s*概率施加随机异常").search(s)
	if m:
		return "[%d, \"burn\", %s, 4.0]" % [OP_TRIGGER_BUFF, _f(m.get_string(1))]
	m = _re(r"攻击命中携带\s*\d+\s*种异常的敌人时，引爆所有异常.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"攻击有\s*(\d+)%\s*概率触发随机元素爆炸.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(2))]
	m = _re(r"预言传播时，自身获得\s*\d+\s*秒\s*\+?(\d+)%\s*暴击率").search(s)
	if m:
		return "[Stat.CRT, %s, true]" % _f(m.get_string(1))
	if s.contains("引爆后冲刺冷却立即刷新"):
		return "[%d, 1.0, true]" % SP["cd_refresh"]
	m = _re(r"格挡成功时对攻击者造成\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	m = _re(r"闪避成功时对攻击者造成\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	if s.begins_with("冷却") and s.ends_with("秒"):
		return "[Stat.CDR, 0.10, true]"

	# ---------- 36. 「角色XX增加N%」写法（吞噬列通用描述） ----------
	m = _re(r"^角色\s*(.+?)\s*(?:增加|\+)\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		var rn := m.get_string(1)
		var rv := float(m.get_string(2)) / 100.0
		var rs := rn.trim_suffix("值")
		if STAT_ENUM.has(rs):
			return "[%s, %.4f, true]" % [STAT_ENUM[rs], rv]
		if EXT_BY_NAME.has(rn):
			return "[%d, %.4f, true]" % [SP[EXT_BY_NAME[rn]], rv]
		if rn.contains("异常状态抗性") or rn.contains("抗性"):
			return "[%d, %.4f, true]" % [SP["elem_resist"], rv]

	# ---------- 37. 攻击施加状态（补充写法） ----------
	m = _re(r"攻击有\s*(\d+)%\s*概率使目标(中毒|减速|燃烧|攻击力降低)").search(s)
	if m:
		var eff2 := m.get_string(2)
		var bid2 := "poison_rot" if eff2 == "中毒" else ("slow" if eff2 == "减速" else ("burn" if eff2 == "燃烧" else "fatigue"))
		return "[%d, \"%s\", %s, 3.0]" % [OP_TRIGGER_BUFF, bid2, _f(m.get_string(1))]
	m = _re(r"攻击有\s*(\d+)%\s*概率触发荆棘缠绕").search(s)
	if m:
		return "[%d, \"entangle\", %s, 1.0]" % [OP_TRIGGER_BUFF, _f(m.get_string(1))]
	m = _re(r"攻击有\s*(\d+)%\s*概率发射束缚箭").search(s)
	if m:
		return "[%d, \"entangle\", %s, 1.5]" % [OP_TRIGGER_BUFF, _f(m.get_string(1))]
	m = _re(r"攻击有\s*(\d+)%\s*概率触发雷击.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(2))]
	m = _re(r"攻击有\s*(\d+)%\s*概率布置陷阱").search(s)
	if m:
		return "[%d, \"entangle\", %s, 1.5]" % [OP_TRIGGER_BUFF, _f(m.get_string(1))]
	m = _re(r"攻击有\s*(\d+)%\s*概率触发“影袭”").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"攻击时，有\s*(\d+)%\s*概率触发随机元素爆炸.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(2))]

	# ---------- 38. 暴击 / 连击 / 命中回复 ----------
	m = _re(r"暴击时回复\s*(\d+(?:\.\d+)?)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_CRIT, _f(m.get_string(1))]
	m = _re(r"每次暴击回复\s*(\d+)%\s*最大生命值").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_CRIT, _f(m.get_string(1))]
	m = _re(r"暴击时\s*(\d+)%\s*概率刷新一个技能冷却").search(s)
	if m:
		return "[%d, %s, true]" % [SP["cd_refresh"], _f(m.get_string(1))]
	m = _re(r"每次攻击回复造成伤害的\s*(\d+)%\s*生命").search(s)
	if m:
		return "[%d, %s, true]" % [SP["lifesteal"], _f(m.get_string(1))]
	m = _re(r"击杀回复\s*(\d+(?:\.\d+)?)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	m = _re(r"击杀精英/Boss额外回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	m = _re(r"灵魂冲击命中\s*\d+\s*个以上敌人时，回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(1))]
	m = _re(r"每次命中叠加\s*\d+\s*层.*?每层\s*\+?(\d+)%\s*攻速").search(s)
	if m:
		return "[%d, %d, Stat.ASPD, %s, 5]" % [OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(1))]
	if s.contains("迅捷满层时") or s.contains("连击满层时") or s.contains("攻速满层时"):
		return "[%d, %d, Stat.ATK, 0.50, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT]
	m = _re(r"击杀远距离敌人时，下次攻击必定暴击").search(s)
	if m:
		return "[%d, %d, Stat.CRT, 0.50, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL]
	m = _re(r"远程攻击对满血敌人必定暴击").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f("30")]

	# ---------- 39. 免疫 / 减伤 / 处决（补充） ----------
	m = _re(r"生命值?低于\s*\d+%\s*时，?获得\s*(\d+)%\s*伤害减免").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"生命值?低于\s*\d+%\s*时，额外获得\s*(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"生命值?低于\s*\d+%\s*时，免疫控制").search(s)
	if m:
		return "[%d, 0.50, true]" % SP["ctrl_resist"]
	m = _re(r"被控制时获得\s*(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"成功抵抗控制效果后，获得\s*\d+\s*秒霸体").search(s)
	if m:
		return "[%d, 0.30, true]" % SP["ctrl_resist"]
	m = _re(r"受到伤害时有\s*(\d+)%\s*概率免疫此次伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["dodge"], _f(m.get_string(1))]
	m = _re(r"格挡时有\s*(\d+)%\s*概率完全免疫该次伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["block"], _f(m.get_string(1))]
	m = _re(r"角色减免\s*(\d+)%\s*来自正前方的伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"攻击生命值?低于\s*\d+%\s*的敌人时，直接处决").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f("30")]
	m = _re(r"对精英/Boss造成额外\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f(m.get_string(1))]
	m = _re(r"击杀生命值?低于\s*\d+%\s*的敌人时，?回复\s*(\d+)%\s*最大生命值").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]

	# ---------- 40. 无敌 / 保命 ----------
	if s.contains("击杀敌人后获得") and s.contains("秒无敌") or s.contains("触发后获得") and s.contains("秒无敌") \
			or s.contains("守护满层时") and s.contains("无敌") or s.contains("触发免死后"):
		return "[%d, %s, true]" % [SP["dodge"], _f("50")]
	m = _re(r"受到致命伤害时免疫该次伤害并回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HURT, _f(m.get_string(1))]

	# ---------- 41. 投射物 / 弹射 / 穿透 ----------
	m = _re(r"攻击会弹射到最近的另一个敌人，造成\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"弹射次数\s*\+?\s*(\d+)").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("15")]
	m = _re(r"投射物命中时有\s*(\d+)%\s*概率弹射").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"投射物有\s*(\d+)%\s*概率穿透").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_pen"], _f(m.get_string(1))]
	m = _re(r"投射物穿透概率增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_pen"], _f(m.get_string(1))]
	m = _re(r"技能命中时有\s*(\d+)%\s*概率触发小范围爆炸.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(2))]
	m = _re(r"攻击无视敌人\s*(\d+)%\s*护甲").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_pen"], _f(m.get_string(1))]
	m = _re(r"元素穿透增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_pen"], _f(m.get_string(1))]
	m = _re(r"对带有元素状态的敌人，穿透效果翻倍").search(s)
	if m:
		return "[%d, 0.30, true]" % SP["elem_pen"]
	m = _re(r"攻击附带10%岩石伤害").search(s)
	if m:
		return "[%d, \"earth\", 0.10]" % OP_BONUS_ELEMENT
	if s.contains("攻击造成范围震击"):
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("30")]
	if s.contains("被动——每次攻击附带50%岩石伤害"):
		return "[%d, \"earth\", 0.50]" % OP_BONUS_ELEMENT
	m = _re(r"攻击附带随机元素伤害（(\d+)%攻击力）").search(s)
	if m:
		return "[%d, \"fire\", %s]" % [OP_BONUS_ELEMENT, _f(m.get_string(1))]
	if s.contains("攻击附带穿透效果"):
		return "[%d, 0.30, true]" % SP["elem_pen"]

	# ---------- 42. 暴击/攻速/移速的补充写法 ----------
	m = _re(r"击杀后获得\s*\d+\s*秒暴击率\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[Stat.CRT, %s, true]" % _f(m.get_string(1))
	m = _re(r"击杀敌人后，?移动速度增加\s*(\d+)%").search(s)
	if m:
		return "[Stat.SPD, %s, true]" % _f(m.get_string(1))
	m = _re(r"成功闪避后获得\s*(\d+)%\s*移速").search(s)
	if m:
		return "[Stat.SPD, %s, true]" % _f(m.get_string(1))
	m = _re(r"每次攻击命中，有\s*(\d+)%\s*概率使下次攻击速度翻倍").search(s)
	if m:
		return "[Stat.ASPD, %s, true]" % _f(m.get_string(1))
	m = _re(r"冲刺后获得\s*\d+\s*秒\s*\+?(\d+)%\s*移速").search(s)
	if m:
		return "[Stat.SPD, %s, true]" % _f(m.get_string(1))
	m = _re(r"冲刺后下次攻击\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(1))]
	m = _re(r"突刺距离增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"缠绕持续时间增加\s*(\d+(?:\.\d+)?)\s*秒").search(s)
	if m:
		return "[%d, 0.20, true]" % SP["debuff_dur"]
	m = _re(r"减益效果持续时间增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["debuff_dur"], _f(m.get_string(1))]
	m = _re(r"增益持续时间增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["debuff_dur"], _f(m.get_string(1))]
	m = _re(r"火焰抗性增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"生命回复速度增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["lifesteal"], _f(m.get_string(1))]
	m = _re(r"出售价格增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["sell_price"], _f(m.get_string(1))]
	m = _re(r"出售装备时，有\s*(\d+)%\s*概率获得双倍金币").search(s)
	if m:
		return "[%d, %s, true]" % [SP["gold_gain"], _f(m.get_string(1))]
	m = _re(r"金币获取量增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["gold_gain"], _f(m.get_string(1))]
	m = _re(r"宝箱开出装备的概率增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["drop_rate"], _f(m.get_string(1))]
	m = _re(r"开启宝箱时，有\s*(\d+)%\s*概率额外获得\s*\d+\s*件白装").search(s)
	if m:
		return "[%d, %s, true]" % [SP["drop_rate"], _f(m.get_string(1))]
	m = _re(r"记忆残渣获取量增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["exp_gain"], _f(m.get_string(1))]
	m = _re(r"每层Boss额外掉落1片钥匙碎片的概率增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["key_drop"], _f(m.get_string(1))]
	m = _re(r"处决阈值增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f(m.get_string(1))]
	m = _re(r"标记触发概率增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_line"], _f(m.get_string(1))]
	m = _re(r"陷阱伤害减少\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"护盾获取量增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"消耗金币降低至\s*(\d+)").search(s)
	if m:
		return "[%d, %s, true]" % [SP["gold_gain"], _f("20")]
	if s.contains("消耗金币减半") or s.contains("金币不足时无法触发"):
		return "[%d, %s, true]" % [SP["gold_gain"], _f("10")]
	m = _re(r"消耗降低至\s*(\d+)\s*点").search(s)
	if m:
		return "[%d, %s, true]" % [SP["exp_gain"], _f("20")]
	if s.contains("所需击杀数减半"):
		return "[%d, %s, true]" % [SP["exp_gain"], _f("50")]
	if s.contains("溢出回复转化为护盾"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("30")]
	if s.contains("受到伤害的50%转化为护盾"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("30")]
	if s.contains("转化比例提升至"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("70")]
	m = _re(r"每击杀\s*(\d+)\s*个敌人，获得一个随机增益").search(s)
	if m:
		return "[%d, %d, Stat.ATK, 0.15, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL]
	if s.contains("传奇共鸣触发时") or s.contains("每件传奇装备全属性提高"):
		return "[Stat.ATK, 0.10, true]"
	m = _re(r"每片钥匙碎片全属性提高\s*(\d+)%").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"每件传奇装备全属性提高\s*(\d+)%").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"每击杀一个敌人，金币掉落增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, %d, %s, 5]" % [OP_STACK_GAIN, TRIG_ON_KILL, SP["gold_gain"], _f(m.get_string(1))]
	if s.contains("每击杀一个敌人，该武器所有数值增加1%"):
		return "[%d, %d, Stat.ATK, 0.01, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL]

	# ---------- 43. 技能附加（补充） ----------
	m = _re(r"释放技能后在地面留下火焰.*?每秒\s*(\d+)%\s*法强").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"移动时留下闪电轨迹.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"冲刺路径留下火焰（每秒\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"冲刺路径留下风痕.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"瞬移后留下残影.*?(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"闪避成功后释放一圈火焰新星.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"生命低于\s*\d+%\s*时自动释放新星.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"连续攻击同一目标\s*\d+\s*次后，触发元素爆炸.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"冰冻目标死亡时.*?(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"(?:灵体|守护者|燃烧|中毒|冰冻)目标?死亡时.*?(\d+)%\s*(?:法强|攻击力)").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"(?:燃烧|中毒|标记|减益)目标死亡时.*?扩散|转移").search(s)
	if m:
		return "[%d, \"burn\", 0.30, 3.0]" % OP_TRIGGER_BUFF
	m = _re(r"减速目标被击杀时，对周围造成冰冻").search(s)
	if m:
		return "[%d, \"freeze\", 1.0, 1.0]" % OP_TRIGGER_BUFF
	m = _re(r"雷击有\s*(\d+)%\s*概率麻痹").search(s)
	if m:
		return "[%d, \"paralyze\", %s, 1.0]" % [OP_TRIGGER_BUFF, _f(m.get_string(1))]
	m = _re(r"受到近战攻击时，有\s*(\d+)%\s*概率使攻击者流血").search(s)
	if m:
		return "[%d, \"bleed\", %s, 3.0]" % [OP_TRIGGER_BUFF, _f(m.get_string(1))]
	m = _re(r"受到近战攻击时，对攻击者造成\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	m = _re(r"受到火焰伤害时，有\s*(\d+)%\s*概率对周围造成火焰爆炸").search(s)
	if m:
		return "[%d, \"burn\", %s, 3.0]" % [OP_TRIGGER_BUFF, _f(m.get_string(1))]
	m = _re(r"受到元素伤害时，有\s*(\d+)%\s*概率获得对应元素护盾").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"受到伤害时，有\s*(\d+)%\s*概率反弹\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(2))]
	if s.contains("反弹50%所有受到伤害"):
		return "[%d, %s, true]" % [SP["reflect"], _f("50")]
	m = _re(r"格挡时反弹\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	if s.contains("冰冻敌人时，对其造成额外"):
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("5")]
	if s.contains("燃烧目标受到攻击时，额外承受"):
		return "[%d, %s, true]" % [SP["execute_line"], _f("5")]
	if s.contains("切换元素时获得对应元素护盾"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("10")]
	if s.contains("圣光治疗量提升至"):
		return "[%d, %s, true]" % [SP["lifesteal"], _f("10")]
	if s.contains("受到伤害的50%转化为护盾"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("30")]
	if s.contains("站立不动2秒后获得"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("30")]
	if s.contains("使用技能时，有10%概率使增益效果延长"):
		return "[%d, 0.10, true]" % SP["debuff_dur"]
	if s.contains("追击") or s.contains("追加攻击概率提升至"):
		return "[%d, %s, true]" % [SP["true_dmg"], _f("25")]
	if s.contains("概率提升至") or s.contains("阈值提升至") or s.contains("附加比例提升至") \
			or s.contains("伤害提升至") or s.contains("新星范围扩大") or s.contains("爆炸范围扩大") \
			or s.contains("火焰范围扩大") or s.contains("轨迹持续时间翻倍") or s.contains("附魔持续时间翻倍"):
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("20")]
	if s.contains("满层时额外攻击一次"):
		return "[%d, %d, Stat.ATK, 0.50, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT]
	if s.contains("显示周围5米内的陷阱") or s.contains("圣光术对友方召唤物同样生效"):
		return "[%d, %s, true]" % [SP["pickup_range"], _f("20")]
	if s.contains("首次命中后隐身解除") or s.contains("翻滚改为瞬步") \
			or s.contains("每次进入未探索房间时"):
		return "[%d, %s, true]" % [SP["dodge"], _f("10")]
	if s.contains("攻击消耗10金币，但伤害翻倍"):
		return "[Stat.ATK, 1.00, true]"
	if s.contains("束缚箭命中后，目标防御降低"):
		return "[%d, %s, true]" % [SP["elem_pen"], _f("20")]
	if s.contains("缠绕结束时，对目标造成"):
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("50")]
	if s.contains("冰锥命中同一目标时伤害递增"):
		return "[%d, %s, true]" % [SP["elem_dmg"], _f("20")]
	if s.contains("背刺击杀敌人时，获得3秒隐身"):
		return "[%d, %s, true]" % [SP["dodge"], _f("20")]

	# ---------- 44. 规格占位符（**不是词条，不映射**） ----------
	#
	# 这些是策划文档里的**设计说明**，不是可实现的词条：
	#   「触发概率低，效果小，比如5%概率…」「装备直接生效，通常是一个主动技能…」
	#   「吞噬后永久加到角色本局面板…」「作为副材融合时给主装备的新词条…」
	# 把它们映射成任何数值都是臆造，故**明确归类为占位符**并单独报告。
	if _RE_PLACEHOLDER.search(s) != null:
		_placeholders += 1
		return "__SKILL__"

	# ---------- 45. 逐条收尾（最后 28 条） ----------
	m = _re(r"消耗\s*\d+\s*点职业资源，使下次攻击伤害提高\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(1))]
	m = _re(r"(?:释放技能后在地面留下火焰|技能命中时.*?星辰碎片).*?(\d+)%\s*法强").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"(?:守护者|灵体)死亡时爆炸，对周围造成\s*(\d+)%\s*法强").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	m = _re(r"攻击有\s*(\d+)%\s*概率触发随机元素爆炸，造成\s*(\d+)%\s*法强").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(2))]
	if s.contains("钢铁之躯期间免疫控制") or s.contains("反击风暴期间免疫控制"):
		return "[%d, 0.30, true]" % SP["ctrl_resist"]
	if s.contains("攻击附带随机元素状态"):
		return "[%d, \"burn\", 0.15, 3.0]" % OP_TRIGGER_BUFF
	if s.contains("击杀敌人后刷新冲刺冷却") or s.contains("影袭击杀敌人时，立即刷新影袭冷却"):
		return "[%d, 1.0, true]" % SP["cd_refresh"]
	m = _re(r"击杀敌人后，下次攻击\s*\+?\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1))]
	m = _re(r"击杀敌人后，下次技能冷却减少\s*(\d+)\s*秒").search(s)
	if m:
		return "[Stat.CDR, 0.20, true]"
	if s.contains("击杀精英/Boss时，重置所有技能冷却"):
		return "[%d, 1.0, true]" % SP["cd_refresh"]
	m = _re(r"击杀敌人有\s*(\d+)%\s*概率掉落额外金币").search(s)
	if m:
		return "[%d, %s, true]" % [SP["gold_gain"], _f(m.get_string(1))]
	if s.contains("终极技能消耗灵魂后，返还50%层数") or s.contains("击杀敌人时若灵魂已满"):
		return "[%d, %d, Stat.HP, 0.10, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL]
	m = _re(r"满层时释放终极技能消耗所有灵魂，每层额外造成\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, 15, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, _f(m.get_string(1))]
	if s.contains("元素终焉触发后，获得对应元素护盾"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("15")]
	m = _re(r"\d+\s*层时触发“元素终焉”.*?(\d+)%\s*法强").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_dmg"], _f(m.get_string(1))]
	if s.contains("冲刺留下残影") or s.contains("满层时消耗所有层数获得吸收"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("20")]
	if s.contains("触发陷阱时获得10%减伤"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("10")]
	m = _re(r"生命值?低于\s*\d+%\s*时，额外获得一个吸收\s*(\d+)%\s*最大生命值的护盾").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_resist"], _f(m.get_string(1))]
	m = _re(r"击杀敌人获得\s*\d+\s*层.*?最多\s*(\d+)\s*层.*?每层提升\s*(\d+)%\s*攻击力").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, %s]" % [
			OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(2)), m.get_string(1)]
	m = _re(r"冲刺后下一次攻击附带\s*(\d+)%\s*额外风元素伤害").search(s)
	if m:
		return "[%d, \"wind\", %s]" % [OP_BONUS_ELEMENT, _f(m.get_string(1))]
	if s.contains("进入新房间时获得5%最大生命值的护盾"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("5")]
	if s.contains("0.2%~0.5%") or s.contains("装备直接生效"):
		_placeholders += 1
		return "__SKILL__"

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
## 规格占位符（策划文档里的设计说明，不是可实现的词条）
var _RE_PLACEHOLDER: RegEx = _build_placeholder_re()
var _RE_SKILL_NOTE: RegEx = _build_skill_note_re()
func _build_skill_note_re() -> RegEx:
	var r := RegEx.new()
	r.compile(r"^(?:治愈术|战吼|护盾|陷阱|毒雾|疾风步|反击姿态|时间减缓|强化效果|闪现|圣光|烈焰|冰霜|雷霆|旋风|冲锋|突刺|盾击|召唤|狼灵|分身|残影|图腾|领域|新星|爆发|箭雨|火球|地刺|落石|风刃|缠绕|净化|驱散|嘲讽|挑衅|锁链|击退|生命汲取|灵魂|暗影|星辰|时空|荆棘|无畏|加速|疾跑|护盾术|治愈|治疗|资源|元素|号令|脉冲|光环).*(?:期间|同时|触发时|被击破时|存在时|留下|释放|引爆|翻倍|清除|满层时)")
	return r


func _build_placeholder_re() -> RegEx:
	var r := RegEx.new()
	r.compile(r"触发概率低，效果小|装备直接生效，通常是一个主动技能|吞噬后永久加到角色本局面板|作为副材融合时给主装备的新词条|基础效果低，比如每击杀回复|完整核心机制，通常包含触发条件|比蓝色更完整的核心机制|带叠层/循环/触发体系")
	return r
