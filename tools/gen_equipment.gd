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
## 未映射明细落盘路径（`装备名\t稀有度\t列\t词条原文`）
const UNMAPPED_PATH := "res://tools/data/unmapped_detail.txt"
## 逐条解析追踪落盘路径（`装备名\t列\t词条原文\t解析结果`）
const TRACE_PATH := "res://tools/data/parse_trace.txt"

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
	# 标枪（2026-09-26 用户决策）：改为**普通远程武器**的攻击方式。
	# 与 spear 分开是因为攻击方式不同——长矛近战突刺、标枪投掷（远程）。
	"javelin": "远程,单手,物理",
}
const WT_MULT := {
	"sword": 1.0, "greatsword": 1.6, "dagger": 0.75, "axe": 1.0,
	"greataxe": 1.6, "spear": 1.0, "scythe": 1.6, "bow": 1.0,
	"crossbow": 1.0, "heavy_crossbow": 1.6, "staff": 1.3, "shield": 1.0,
	"javelin": 1.0,
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
	# 2026-09-24：元素拆分 + 非元素维度（见 EquipmentDB.SPECIAL_STAT）
	"fire_dmg": 121, "frost_dmg": 122, "static_dmg": 123, "earth_dmg": 124,
	"wind_dmg": 125, "poison_dmg": 126, "shadow_dmg": 127,
	"fire_resist": 128, "frost_resist": 129, "static_resist": 130,
	"earth_resist": 131, "wind_resist": 132, "poison_resist": 133,
	"shadow_resist": 134,
	"ranged_dmg": 135, "aoe_dmg": 136, "trap_dmg": 137, "projectile_dmg": 138,
	"debuff_resist": 139, "shield_power": 140, "frozen_dmg": 141,
	# 2026-09-26：职业资源（装备参考2 的「获得 N 点怒气/魔力/…」）
	"res_gain": 142, "res_gain_pct": 143, "res_max": 144, "res_regen": 145,
}

## Operation / Trigger 枚举值（与 AffixData 一致）
const OP_BONUS_ELEMENT := 3
const OP_TRIGGER_BUFF := 2
const OP_STACK_GAIN := 4
const OP_GRANT_SKILL := 7
const TRIG_ON_KILL := 1
const TRIG_ON_HURT := 2
const TRIG_ON_HIT := 3
const TRIG_ON_DODGE := 4
const TRIG_ON_COMBO := 7
const TRIG_ON_BLOCK := 9
const TRIG_ON_CRIT := 6
# 2026-09-26 两段式重构补全（与 AffixData.Trigger 一一对应）
const TRIG_ALWAYS := 0
const TRIG_AT_FULL := 5
const TRIG_ON_DASH := 8
const TRIG_ON_ATTACK := 10
const TRIG_LOW_HP := 11
const TRIG_STATIONARY := 12
const TRIG_ON_ROOM_ENTER := 13
# 2026-09-24 补全：条件型词条实测需要（与 AffixData.Trigger 一致）
const TRIG_ON_SHIELD_BREAK := 14
const TRIG_SHIELD_UP := 15
const TRIG_ON_TRAP_TRIGGER := 16
const TRIG_ON_SUMMON_ALIVE := 17
const TRIG_ON_SKILL_CAST := 18
const TRIG_ON_SPRINT := 19
const TRIG_ON_TAUNT := 20
const TRIG_ON_BLOCK_STANCE := 21
const TRIG_ON_WHIRLWIND := 22
const TRIG_ON_TIME_SLOW := 23
const TRIG_ON_FRENZY := 24
# 2026-09-26 两段式重构补全（与 AffixData.Trigger 一一对应）
const TRIG_RESOURCE_FULL := 25
const TRIG_HP_FULL := 26
const TRIG_STEALTH_UP := 27
const TRIG_ON_TARGET_CONTROLLED := 28
const TRIG_DISTANCE_FAR := 29
const TRIG_GOLD_ABOVE := 30
const TRIG_ON_SELL := 31
const TRIG_ON_CHEST_OPEN := 32
const TRIG_ON_RECALL := 33
const TRIG_ON_CHEAT_DEATH := 34
const TRIG_ON_TARGET_DEATH := 35
const TRIG_ON_ELEMENT_PROC := 36
const TRIG_ON_HEAL := 37

## 数值型效果名 → 扩展通道 key（吞噬/融合列大量出现）
##
## ## 2026-09-24 修正：具体元素不再塌缩
##
## 旧表把「火焰伤害」「冰霜伤害」「雷电伤害」…**全部映射到同一个 `elem_dmg`**，
## 于是烈焰法杖与寒霜法杖的吞噬词条生成出来**一字不差**——元素区别在
## 数据层就消失了。而且「远程/范围/陷阱/投射物伤害」根本不是元素、
## 「异常状态抗性/护盾强度」不是元素抗性——它们被塞进了错误的通道。
##
## 现在：具体元素各归各的键；全局写法（「元素伤害」「元素抗性」）保留
## 全局通道；非元素维度走它们自己的新通道。
##
## **暗影不是六元素**（名词设计分册只定义火冰雷土风毒），故它只有
## 增伤/抗性键，不参与元素叠层。
const EXT_BY_NAME := {
	# —— 具体元素增伤：各归各的（不再塌缩）——
	#
	# **写法必须穷举**：规格里「疾风伤害」与「风元素伤害」是同一个元素的
	# 两种写法（`ELEM_KEY` 认「疾风」→ wind，所以自有/融合列一直是对的），
	# 但 `EXT_BY_NAME` 只列了「风元素伤害」，于是「获得 1% 疾风伤害提升」
	# 掉进下面的 `nm.contains("伤害")` 兜底 → 被当成全局元素增伤。
	# 六系法杖里**只有疾风法杖**踩到这个坑。
	"火焰伤害": "fire_dmg", "冰霜伤害": "frost_dmg", "雷电伤害": "static_dmg",
	"毒素伤害": "poison_dmg",
	"大地伤害": "earth_dmg", "土元素伤害": "earth_dmg", "岩裂伤害": "earth_dmg",
	"风元素伤害": "wind_dmg", "疾风伤害": "wind_dmg", "裂风伤害": "wind_dmg",
	"暗影伤害": "shadow_dmg",
	# 全局元素增伤（规格里确有「元素伤害增加 N%」这类全元素写法）
	"元素伤害": "elem_dmg",
	# —— 非元素维度：不是元素，走各自通道 ——
	"远程伤害": "ranged_dmg", "范围伤害": "aoe_dmg", "陷阱伤害": "trap_dmg",
	"投射物伤害": "projectile_dmg", "穿透后的投射物伤害": "projectile_dmg",
	"被冻结敌人受到伤害": "frozen_dmg",
	# —— 防御维度 ——
	"元素抗性": "elem_resist",
	"异常状态抗性": "debuff_resist",
	"护盾强度": "shield_power", "护盾获取量": "shield_power",
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
## 整行都是模板/示例文本、被跳过的占位行数（见 `_is_placeholder_row`）
var _placeholder_rows := 0

# —— 逐件解析状态（供 compare_spec_vs_code 消费）——
## 当前正在解析的装备名 / 稀有度 / 列名
var _cur_name := ""
var _cur_rar := ""
var _cur_col := ""
## 当前装备各列的解析计数：{col: {ok, total, miss}}
var _cur_counts := {}
## 带装备上下文的未映射记录（`装备名\t列\t词条原文`）
var _unmapped_ctx: Array[String] = []
## 逐条解析追踪：`装备名\t列\t词条原文\t解析结果`
##
## 用途：核对「解析结果是否忠实于原文」——只统计「有没有解析出来」
## 不够，数值提错、层数丢失、语义压错通道同样是错的，且更隐蔽。
var _trace: Array[String] = []


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

		# **跳过占位行**：规格表里有 3 行是策划文档的**模板/示例**，不是真装备：
		#   G018 守护护符   —— 三列全是「触发概率低，效果小…」「0.2%~0.5%」等示例文本
		#   G050 真实伤害护符 —— 三列全是「装备直接生效，通常是一个主动技能…」
		#   P064 伤害储存护符 —— 三列是「主动技能」「被动增益」「机制强化」模板标签
		#
		# G018 还与 B017 守护护符**同名**（B017 是完整的真装备），生成出来
		# 会在图鉴里出现两件同名装备、其中一件词条全空。
		#
		# **注意计数器的位置**：`by_rar` 必须在跳过之前自增，否则后面所有
		# 同稀有度装备的 id 会整体前移，与既有存档/引用对不上。
		if _is_placeholder_row(own, dev, fus):
			_placeholder_rows += 1
			continue

		var cat_e: String = str(CAT_ENUM.get(cat, "EquipmentDefs.Category.ACCESSORY"))
		var slot_e: String = "EquipmentDefs.Slot.WEAPON_1" if cat == "WEAPON" \
			else str(SLOT_ENUM.get(wtype, "EquipmentDefs.Slot.ACCESSORY_1"))
		var wt: String = wtype if cat == "WEAPON" else ""
		# **标枪走 javelin 类型**（2026-09-26 用户决策：改为普通远程武器）。
		#
		# 规格表里标枪的 weapon_type 是 `spear`（与长矛共用），但攻击方式
		# 完全不同——长矛近战突刺、标枪投掷。故按**名字含「标枪」**细分。
		# 实测 8 个 spear 里恰好 2 个是标枪（雷霆标枪 / 猎手标枪）。
		if wt == "spear" and name.contains("标枪"):
			wt = "javelin"
		var tags: String = str(WEAPON_TAGS.get(wt, "")) if cat == "WEAPON" else ""

		# 基础属性：武器给攻击/法强；**防御武器无攻击**（规格）；其余给防御
		var base := ""
		if cat == "WEAPON":
			var v: float = 35.0 * float(RAR_SCALE.get(rar, 1.6)) * float(WT_MULT.get(wt, 1.0))
			var bs := "Stat.AP" if wt == "staff" else ("Stat.DEF" if wt == "shield" else "Stat.ATK")
			base = "[[%s, %.1f, false]]" % [bs, v]
		else:
			base = "[[Stat.DEF, %.1f, false]]" % (12.0 * float(RAR_SCALE.get(rar, 1.6)) * 0.35)

		# —— 逐件解析状态：记录当前装备名/稀有度，供 report_item 输出 ——
		_cur_name = name
		_cur_rar = rar
		_cur_counts = {}

		_cur_col = "own"
		var own_a := _parse_affix_text(own)
		# **自有列的「主动技能」要留痕**（装备参考2：133 件装备的自有词条
		# 就是技能本身）。`_parse_affix_text` 把它识别成 `__SKILL__` 并跳过
		#（技能本体已单独进 `EquipmentSkills` 表），但**自有列不同于吞噬/融合列**：
		# 它是「这件装备提供什么」的展示位，留空会让图鉴显示不出技能来源
		#（实测 129 件 own_affixes 为空）。
		# 故这里额外补一条 GRANT_SKILL，承载「本装备提供主动技能 X」。
		# **追加到末尾，不能插在开头**：`EquipmentTemplate.own_affix`
		#（单数访问器）返回的是 `own_affixes[0]`，而多处消费者只读它——
		# 尤其 `equipment_effects._affixes_with` 用它派发**触发型词条**，
		# 插到开头会让那 133 件装备的「击杀叠层」等触发词条整个失效。
		# GRANT_SKILL 只是展示用元数据，放末尾不影响任何既有消费者。
		var grant := _grant_skill_spec(own, name)
		if not grant.is_empty():
			own_a = "[%s, %s]" % [own_a.substr(1, own_a.length() - 2), grant] \
				if own_a != "[]" else "[%s]" % grant
		_cur_col = "devour"
		var dev_a := _parse_affix_text(dev)
		_cur_col = "fusion"
		var fus_a := _parse_affix_text(fus)
		# 逐件报告解析状态（stderr）——让「哪件装备的哪条词条没解析」可见
		report_item()

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
	printerr("=== 占位行（整行是策划模板/示例，已跳过）：%d 行 ===" % _placeholder_rows)
	# 带装备上下文的未映射清单落盘（供 compare_spec_vs_code 消费）
	_dump_unmapped()
	quit(0)


## 解析一整条词条文本（可能含「；」分隔的复合效果）→ GDScript 数组字面量
## 判据：三列里**至少两列**是策划文档的设计模板文本（不是真词条）
##
## 为什么要「至少两列」而不是「任一列」：单列出现模板文本的情况可能是
## 真装备的某一列没写，但三列里两列以上都是模板 = 整行就是模板。
func _is_placeholder_row(own: String, dev: String, fus: String) -> bool:
	var hits := 0
	for col in [own, dev, fus]:
		var c := str(col).strip_edges()
		if _RE_PLACEHOLDER.search(c) != null:
			hits += 1
		# 模板标签形态（「主动技能」/「被动增益」/「机制强化」这类单词标签）
		elif c in ["主动技能", "被动增益", "机制强化", "核心机制"]:
			hits += 1
	return hits >= 2


## 自有列里若含「主动技能"X"」→ 生成一条 GRANT_SKILL 规格；否则空串
##
## 返回形如 `[7, "eq_元素调和法杖", "元素调和"]`（Operation.GRANT_SKILL = 7）。
##
## **技能 id 必须用「装备名」拼**，不是技能名——`EquipmentSkills._skill_id`
## 的规则是 `"eq_" + equip_name`（它按**装备显示名**索引整张技能表）。
## 用技能名会拼出 `eq_元素调和` 而表里是 `eq_元素调和法杖`，
## 引用落空（实测 55 条对不上）。显示名用技能名，更易读。
func _grant_skill_spec(own: String, equip_name: String) -> String:
	var m := _re(r"主动技能\s*[“”\"']([^“”\"']+)[“”\"']").search(own)
	if m == null:
		return ""
	var sname := m.get_string(1).strip_edges()
	if sname.is_empty():
		return ""
	return "[%d, \"eq_%s\", \"%s\"]" % [OP_GRANT_SKILL, equip_name, sname]


func _parse_affix_text(text: String) -> String:
	if text.strip_edges().is_empty():
		return "[]"
	var parts := text.split("；")
	var out: Array[String] = []
	for p in parts:
		# 也按半角分号拆（规格里两种都出现过）
		for q in p.split(";"):
			var s := q.strip_edges()
			if s.is_empty():
				continue
			# 计数（report_item 用）
			if not _cur_counts.has(_cur_col):
				_cur_counts[_cur_col] = {"ok": 0, "total": 0, "miss": 0}
			var c: Dictionary = _cur_counts[_cur_col]
			c["total"] = int(c["total"]) + 1

			var r := _parse_one(s)
			# **哨兵值必须一起判**：`_parse_main` 解不出来时返回
			# `"__UNMAPPED__"` 而不是空串（避免重复计数）。只判 `is_empty()`
			# 会让哨兵被当成词条字面量写进数据——
			# 实测产出 `[__UNMAPPED__]`，整个 equipment_db.gd 编译失败。
			if r.is_empty() or r == "__UNMAPPED__":
				# 记下**是哪件装备的哪条**——只报词条文本会丢失上下文，
				# 而同一词条文本可能出现在多件装备上，改起来无从下手。
				c["miss"] = int(c["miss"]) + 1
				_unmapped_ctx.append("%s\t%s\t%s" % [_cur_name, _cur_col, s])
				# 逐条追踪（供 compare 核对「解析结果是否忠实于原文」）
				_trace.append("%s\t%s\t%s\t%s" % [_cur_name, _cur_col, s, "__MISS__"])
				continue
			if r == "__SKILL__":
				_skill_notes += 1
				_trace.append("%s\t%s\t%s\t%s" % [_cur_name, _cur_col, s, "__SKILL__"])
			else:
				c["ok"] = int(c["ok"]) + 1
				_trace.append("%s\t%s\t%s\t%s" % [_cur_name, _cur_col, s, r])
				out.append(r)
	return "[%s]" % ", ".join(out)


## 逐件报告每条装备的三列解析状态（供 `compare_spec_vs_code` 消费）
##
## 输出到 stderr，格式：
##   ITEM <名字> <稀有度>
##   COL  <own|devour|fusion> <ok数>/<总条数> <未映射条数>
func report_item() -> void:
	printerr("ITEM %s %s" % [_cur_name, _cur_rar])
	for col in _cur_counts:
		var c: Dictionary = _cur_counts[col]
		printerr("COL  %s %d/%d %d" % [col, int(c["ok"]), int(c["total"]), int(c["miss"])])


## 把「哪件装备的哪条词条没解析」落盘
##
## 格式：`装备名\t稀有度\t列\t词条原文`
## **这是「需重做」的精确依据**——只报词条文本会丢失上下文，
## 而同一文本可能出现在多件装备上。
func _dump_unmapped() -> void:
	var f := FileAccess.open(UNMAPPED_PATH, FileAccess.WRITE)
	if f == null:
		return
	for line in _unmapped_ctx:
		f.store_line(line)
	f.close()
	printerr("=== 未映射明细已写入 %s（%d 条）===" % [UNMAPPED_PATH, _unmapped_ctx.size()])
	# 逐条解析追踪
	var g := FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	if g == null:
		return
	for line in _trace:
		g.store_line(line)
	g.close()
	printerr("=== 逐条解析追踪已写入 %s（%d 条）===" % [TRACE_PATH, _trace.size()])


## 解析**单条**效果。返回：
##   ""           —— 无法映射（已记入 _unmapped）
##   "__SKILL__"  —— 装备技能的修饰（不属于词条层级）
##   其他         —— 词条规格的 GDScript 字面量
##
## ## 从句**只作校验与修正**，不改解析路径（2026-09-26 重构）
##
## 起初试的是「切掉从句 → 主句走规则」，但实测**大面积失配**：
## 46 节规则里有相当一批是按「从句 + 主句」**整体**匹配的
##（如第 46 节 `s.contains("护盾存在时")`），切掉从句它们就再也匹配不到，
## 未映射从 8 条暴涨到 344 条。
##
## 现在的做法是**加法而非改路**：
##   ① 完整文本走原有规则（行为与重构前**完全一致**）
##   ② 从句识别出 Trigger 后，只做三件事：
##      · 结果已是触发型且 trigger 一致 → 不动
##      · 结果 trigger 不一致 → **以从句为准**覆盖
##      · 结果是**裸属性**（条件被吞）→ 包上从句的 trigger
##
## **不变量**：`原文含触发从句` ⟹ `结果必须带 trigger`。
## 从句识别不了时**报未映射**，绝不静默压成常驻。
func _parse_one(s: String) -> String:
	if s.is_empty():
		return ""
	# 装备技能整体跳过——**必须在从句处理之前**，
	# 否则技能描述里的「使用技能后…」会被误当成触发从句
	if s.begins_with("主动技能"):
		return "__SKILL__"
	if _RE_SKILL_NOTE.search(s) != null:
		return "__SKILL__"

	# ---- ① 完整文本走原有规则（一字未改）----
	var spec := _parse_main(s)

	# ---- ② 从句校验 / 修正 ----
	var parts := _split_clause(s)
	var clause: String = parts["clause"]
	if clause.is_empty():
		return spec   # 无触发从句 → 原样返回

	# **主句回退**：完整文本解不出来时，试主句部分。
	#
	# 两个方向都要试，因为规则表里两种写法都有：
	#   · 按**完整文本**匹配的（第 46 节 `s.contains("护盾存在时")`）
	#   · 按**主句**匹配的（第 9 节数值型，从句会干扰它）
	# 只试一边必然漏掉另一边。
	if spec.is_empty():
		spec = _parse_main(str(parts["main"]))

	var t := _trigger_of_clause(clause)
	var trig := int(t["trigger"])
	if trig == TRIG_ALWAYS:
		# 从句**识别不了**。两种可能：
		#   · 旧规则已把它处理成带触发语义的形态（如 `[2,"buff",…]`、
		#     `[4,5,…]`）——那是好的，**保留**
		#   · 结果仍是**裸属性**——说明条件被吞（正是本轮要修的 bug），
		#     此时报未映射
		#
		# 不能一律报未映射：实测那样会让 56 条旧规则本已处理的词条
		# 变成「未映射」（如「5层时…」「标记目标死亡时…」这类，
		# 我的从句映射表没穷举到，但旧规则认得）。
		if _trigger_of_spec(spec) >= 0:
			return spec
		_unmapped.append(s)
		return ""

	if spec.is_empty() or spec == "__UNMAPPED__" or spec == "__SKILL__":
		# 解不出来：把整条记未映射（不能只记主句，否则报告缺上下文）
		_unmapped.append(s)
		return spec if spec == "__SKILL__" else ""

	# 结果自带触发条件吗？
	var cur := _trigger_of_spec(spec)
	if cur >= 0:
		if cur == trig:
			return spec
		# 触发条件不一致时**不急着覆盖**——先看旧规则是不是解出了
		# 比「裸属性」更具体的东西。
		#
		# 实测：我新增的从句规则会盖掉更精确的旧解析。例：
		#   「飞斧命中后弹射至最近敌人（50%伤害）」
		#   旧规则 → `[117, 0.15, true]`（弹射伤害加成，合理）
		#   我覆盖 → `[4, 10, 117, 0.15, 0]`（变成「攻击时加元素伤害」）
		#
		# 故只在旧结果是**叠层型**（trigger 明确且本就是条件语义）时才覆盖；
		# 裸属性/其他形态交给下面的分支处理。
		if _is_stack_spec(spec):
			return _replace_trigger(spec, trig)
		return spec

	# **裸属性 = 条件被吞**（这正是本轮要修的 bug）→ 包上从句触发
	if _is_plain_spec(spec):
		return _wrap_with_trigger(spec, trig, float(t["param"]))

	# 其他形态（扩展通道、周期型等）：**保留旧解析**
	#
	# 这些形态的旧解析往往已表达完整语义（如 `[117, 0.15, true]` 是
	# 「弹射伤害 +15%」），硬包一层会把语义改掉。
	return spec


## 结果是否是**叠层型**（`[4, trigger, ...]`）
func _is_stack_spec(spec: String) -> bool:
	return _re(r"^\[4,\s*\d+,").search(spec) != null


## 结果是否是**裸属性**（`[Stat.X, v, bool]` / `[NNN, v, true]`）
func _is_plain_spec(spec: String) -> bool:
	return _re(r"^\[(?:[A-Za-z_.]+|\d+),\s*-?[\d.]+,\s*(?:true|false)\]$").search(spec) != null


## 从解析结果里取 trigger 槽位；**不带触发语义时返回 -1**
##
## 三种形态：
##   `[4, trigger, stat, v, stack_max]`  叠层型 → 第 2 位
##   `[2, "buff", chance, dur]`          触发型 → **自带触发语义**（返回 0，
##                                        表示「已经是触发型，不必再包」）
##   `[3, "elem", v]`                    附带元素 → 同上
##   `[Stat.X, v, bool]` / `[NNN, v, true]` 裸属性 → -1
func _trigger_of_spec(spec: String) -> int:
	var m := _re(r"^\[4,\s*(\d+),").search(spec)
	if m:
		return int(m.get_string(1))
	if spec.begins_with("[%d," % OP_TRIGGER_BUFF) \
			or spec.begins_with("[%d," % OP_BONUS_ELEMENT):
		return TRIG_ALWAYS   # 已是触发型，视为「不必再包」
	return -1


## 替换叠层型结果的 trigger 槽位（其余部分不动）
func _replace_trigger(spec: String, trig: int) -> String:
	var m := _re(r"^\[4,\s*\d+,\s*(.+)\]$").search(spec)
	if m:
		return "[%d, %d, %s]" % [OP_STACK_GAIN, trig, m.get_string(1)]
	return spec


## 主句解析 —— **原有 46 节规则全部在这里**，一字未改
##
## 拆出来只为让 `_parse_one` 能在它前后加从句处理。
## 改规则时仍然改这里。
func _parse_main(s: String) -> String:
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
		# **通道修正**：旧代码映射到 `exp_gain`（经验获取）——那是错的，
		# 词条说的是「回复 N 点**职业资源**」，与经验无关。
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, SP["res_gain"], _raw(m.get_string(1))]
	# ---------- 3b. 职业资源点（装备参考2：「获得 N 点怒气/魔力/…」） ----------
	#
	# 资源已统一为怒气/魔力/气劲三种（用户 2026-09-26 决策），
	# 故这些词条一律按「获得 N 点**职业资源**」处理——谁装备谁生效，
	# 不再绑死某个职业。规格里的「（战士）」「（猎人）」等括号是**说明**，
	# 不是限定条件。
	#
	# 触发时机按从句区分：击杀 / 受击 / 命中 / 暴击 / 连击。
	# **数值用 `_raw` 不除 100**：「获得 5 点」是绝对点数，不是百分比。
	m = _re(r"击杀敌人(?:时)?获得\s*(\d+)\s*点(?:怒气|魔力|专注|裁决|气劲|职业资源)").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, SP["res_gain"], _raw(m.get_string(1))]
	m = _re(r"击杀敌人回复\s*(\d+)\s*点(?:怒气|魔力|专注|裁决|气劲)").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, SP["res_gain"], _raw(m.get_string(1))]
	m = _re(r"受到伤害时获得\s*(\d+)\s*点(?:怒气|魔力|专注|裁决|气劲|职业资源)").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HURT, SP["res_gain"], _raw(m.get_string(1))]
	m = _re(r"攻击命中时获得\s*(\d+)\s*点(?:怒气|魔力|专注|裁决|气劲|职业资源)").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, SP["res_gain"], _raw(m.get_string(1))]
	m = _re(r"暴击时获得\s*(\d+)\s*点(?:怒气|魔力|专注|裁决|气劲|职业资源)").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_CRIT, SP["res_gain"], _raw(m.get_string(1))]
	m = _re(r"连击时获得\s*(\d+)\s*点(?:怒气|魔力|专注|裁决|气劲|职业资源)").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_COMBO, SP["res_gain"], _raw(m.get_string(1))]
	# 每秒回复 N 点魔力（法师）——**速率**，不是一次性获得。
	#
	# 走独立通道 `res_regen`：`res_gain` 是「某个事件发生时获得 N 点」，
	# 而这个是「持续每秒回 N 点」。语义不同，混用会让「每秒回 1 点」
	# 变成「永远只回 1 点」。
	m = _re(r"每秒回复\s*(\d+)\s*点(?:怒气|魔力|专注|裁决|气劲)").search(s)
	if m:
		return "[%d, %s, true]" % [SP["res_regen"], _raw(m.get_string(1))]
	# 「怒气获取量增加 0.5%」类——资源积攒量的百分比乘区
	m = _re(r"(?:怒气|魔力|专注|裁决|气劲|资源)获取量增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["res_gain_pct"], _f(m.get_string(1))]
	# 「魔力回复速度增加 0.5%」——同上（写法变体）
	m = _re(r"(?:怒气|魔力|专注|裁决|气劲|资源)回复速度增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["res_gain_pct"], _f(m.get_string(1))]
	# 「最大怒气/魔力/专注/裁决/气劲增加 3%」——资源上限乘区
	m = _re(r"最大(?:怒气|魔力|专注|裁决|气劲)(?:/[^\s]+)*增加\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["res_max"], _f(m.get_string(1))]
	# 「击杀敌人回复 2% 最大魔力」——按**百分比**回复资源
	#（与「获得 N 点」的绝对点数不同，故走同一个 flat 通道但值是百分比化的？
	#  不——语义不同：这是「回复上限的 2%」。用 res_gain_pct 会让它变成
	#  「积攒量 +2%」，也是错的。
	#  正确做法：折算成点数存进 res_gain（上限 100 的 2% = 2 点），
	#  因为资源上限统一是 100。见 ClassResource.DEFS 的 max 字段。）
	m = _re(r"击杀敌人回复\s*(\d+(?:\.\d+)?)%\s*最大(?:怒气|魔力|专注|裁决|气劲)").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, SP["res_gain"],
			_raw("%.1f" % float(m.get_string(1)))]
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
		# 同 663 行：通道修正 `exp_gain` → `res_gain`，且用 `_raw` 不除 100
		return "[%d, %d, %d, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, SP["res_gain"], _raw(m.get_string(1))]

	# ---------- 8c. 条件型补全（2026-09-26，B 类 15 条）----------
	#
	# 这些词条的**机制都已存在**（词条表、Trigger 枚举、消费点齐全），
	# 只是生成器缺规则。放在第 9 节通用兜底之前——否则会被
	# `nm.contains("伤害")` 之类吞掉（「N层时」那三条就是这么丢的）。

	# 圣光伤害有 N% 概率致盲敌人 M 秒 → 命中时挂 blind
	m = _re(r"圣光伤害有\s*(\d+)%\s*概率致盲敌人\s*(\d+(?:\.\d+)?)\s*秒").search(s)
	if m:
		return "[%d, \"blind\", %s, %s]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1)), _raw(m.get_string(2))]
	# 反击风暴期间免疫控制 / 荆棘爆发期间免疫控制 → 状态期间免疫
	if s.contains("反击风暴期间免疫控制"):
		return "[%d, \"control_immune\", 1.0, 0.0]" % OP_TRIGGER_BUFF
	# 守护期间免疫击退 → 复用 ctrl_resist 通道（击退属控制类）
	if s.contains("守护期间免疫击退"):
		return "[%d, 1.0, true]" % SP["ctrl_resist"]
	# 成功抵抗控制效果后，获得 N 秒霸体 → 受控抵抗 → 免疫控制
	if s.contains("成功抵抗控制效果后"):
		return "[%d, \"control_immune\", 1.0, 3.0]" % OP_TRIGGER_BUFF
	# 护盾存在时，攻击力提高 N%
	m = _re(r"护盾存在时[，,]?\s*攻击力提高\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [
			OP_STACK_GAIN, TRIG_SHIELD_UP, _f(m.get_string(1))]
	# 攻击有 N% 概率造成额外 M% 攻击力的真实伤害 → 命中时按概率加真伤
	m = _re(r"攻击有\s*(\d+)%\s*概率造成额外\s*(\d+)%\s*攻击力的真实伤害").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [
			OP_STACK_GAIN, TRIG_ON_HIT, SP["true_dmg"], _f(m.get_string(2))]
	# 真实伤害击杀敌人时，回复 N% 最大生命值 → 击杀回血
	m = _re(r"真实伤害击杀敌人时[，,]?回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [
			OP_STACK_GAIN, TRIG_ON_KILL, SP["lifesteal"], _f(m.get_string(1))]
	# 治疗自身时，对周围敌人造成治疗量 N% 的圣光伤害 → 治疗触发范围伤害
	m = _re(r"治疗自身时[，,]?对周围敌人造成治疗量\s*(\d+)%\s*的圣光伤害").search(s)
	if m:
		return "[%d, %d, Stat.AP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HEAL, _f(m.get_string(1))]
	# 使用技能时，有 N% 概率使该技能冷却立即减少 M%
	m = _re(r"使用技能时[，,]?有\s*(\d+)%\s*概率使该技能冷却立即减少\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, %d, %s, 0]" % [
			OP_STACK_GAIN, TRIG_ON_SKILL_CAST, SP["cd_refresh"], _f(m.get_string(2))]
	# 生命低于 N% 时，普通攻击变为范围攻击，造成 M% 伤害
	#
	# 「变为范围攻击」本身需要普攻形态切换（不在裸属性可表达范围），
	# 但**伤害倍率**可提取：M% 是相对基础的倍率，超出 100% 的部分
	# 记进 `aoe_dmg`（范围伤害增伤）。这样至少伤害提升生效。
	m = _re(r"生命(?:值)?低于\s*(\d+)%\s*时[，,]?普通攻击变为范围攻击[，,]?造成\s*(\d+)%\s*伤害").search(s)
	if m:
		var bonus := maxf(float(m.get_string(2)) / 100.0 - 1.0, 0.0)
		return "[%d, %.4f, true]" % [SP["aoe_dmg"], bonus]
	# 点燃目标死亡时，火焰扩散至周围 N 米 → 目标死亡触发
	if s.contains("点燃目标死亡时"):
		return "[%d, \"burn\", 1.0, 4.0]" % OP_TRIGGER_BUFF
	# 被点燃目标受到暴击时，火焰持续时间刷新 → 暴击触发
	if s.contains("被点燃目标受到暴击时"):
		return "[%d, \"burn\", 1.0, 4.0]" % OP_TRIGGER_BUFF
	# 击杀敌人后，暴击率增加 N%，持续 M 秒，可叠加 K 层
	m = _re(r"击杀敌人后[，,]?暴击率增加\s*(\d+)%[，,]?持续\s*(\d+(?:\.\d+)?)\s*秒[，,]?可叠加\s*(\d+)\s*层").search(s)
	if m:
		return "[%d, %d, Stat.CRT, %s, %s]" % [
			OP_STACK_GAIN, TRIG_ON_KILL, _f(m.get_string(1)), m.get_string(3)]
	# 额外投射物命中同一目标时，伤害递增 N% → 命中叠层
	m = _re(r"额外投射物命中同一目标时[，,]?伤害递增\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(1))]

	# ---------- 8b. 「N层时」精确规则（**必须早于第 9 节通用兜底**）----------
	#
	# 第 9 节的数值型兜底里有 `if nm.contains("伤害") → elem_dmg`，
	# 会把「N层时目标受到伤害+N%」整条吞掉（那是**目标易伤**，
	# 不是自己的元素增伤）。
	#
	# 同理「N层时…必定暴击」会掉进同一兜底（把暴击当元素增伤）。
	# 故这三条必须在第 9 节**之前**判——**更具体的规则要先于更宽泛的**。
	#
	# 第 10 节（915 行）里也有一份同样的规则，但那时已经太晚了：
	# 第 9 节在 853 行，先命中并 return 了。
	m = _re(r"\d+层时目标受到伤害\s*\+\s*(\d+)%").search(s)
	if m:
		# 目标易伤（不是自己的增伤）——复用已有的 `judgement` 词条
		#（Kind.VULN，「受到伤害提升」），值走参数覆盖。
		return "[%d, \"judgement\", 1.0, 0.0, {\"vuln\": %s}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1))]
	m = _re(r"\d+层时.*?必定暴击").search(s)
	if m:
		# 「必定暴击且暴击伤害+50%」——裸属性只能表达后半段。
		# 「必定暴击」是「下一次攻击」的标志，需要待发标记机制，
		# 不在裸属性可表达的范围内，故取 CRD（暴击伤害）。
		return "[Stat.CRD, 0.50, true]"
	m = _re(r"\d+层时.*?获得吸收\s*(\d+)%\s*最大生命").search(s)
	if m:
		# 「获得吸收 N% 最大生命的护盾」——旧代码走 `elem_resist`
		#（元素抗性），与「护盾」毫无关系。走 `grant_shield` sentinel。
		return "[%d, \"grant_shield\", 1.0, 0.0, {\"pct\": %s, \"cap\": 0.60}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1))]

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
	# 注：「N层时获得护盾 / 必定暴击 / 目标受到伤害+N%」三条已提到
	# 第 8b 节（第 9 节通用兜底之前）——放这里会被兜底先吞掉。
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
	# **灵魂召唤必须先于下面的兜底**：下面的规则把任何
	# 「含召唤 + 含持续 + 含秒」的词条一律压成 `summon_dmg` 数值加成——
	# 「击杀敌人召唤一个灵魂（继承30%攻击，持续10秒，最多3个）」
	# 正好命中它，于是**真的召唤动作被压成了一个攻击力百分比**。
	# 更具体的规则必须排在更宽泛的规则前面。
	if s.contains("召唤其灵魂"):
		return "[%d, \"summon_soul\", 0.10, 0.0]" % OP_TRIGGER_BUFF
	if s.contains("召唤一个灵魂"):
		return "[%d, \"summon_soul\", 1.0, 0.0]" % OP_TRIGGER_BUFF
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
		# 与 1654 行同一条机制：触发条件是 AT_FULL(5)，不是字面量 15。
		# 15 是笔误（落在 trigger 槽位上），且 2026-09-24 新增 SHIELD_UP=15
		# 后它会静默变成「护盾存在时触发」。
		return "[%d, 5, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, _f(m.get_string(1))]
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
		# 「层数不清空」修饰的是**满层爆发后的层数处理**，不是数值。
		#
		# 旧代码这里写的是字面量 `15`，落在了 **trigger 槽位**上
		#（形态是 `[4, trigger, stat, value, stack_max]`）——那是笔误，
		# 本意应是 `stack_max`。旧 Trigger 枚举只到 13，故 15 是**无效值**、
		# 该词条一直不触发；而 2026-09-24 新增 `SHIELD_UP=15` 后，
		# 它会静默变成「护盾存在时触发」。
		#
		# 现在改为返回 `soul_persist` 词条——由
		# `PlayerEquipmentEffects._consume_stacks` 在满层爆发时读取，
		# 从而真正实现「不清空」。**不要再返回一个假的 STACK_GAIN 数值**：
		# 那会凭空给玩家一个永久 +2% 攻击力，与规格语义无关。
		return "[%d, \"soul_persist\", 1.0, 0.0]" % OP_TRIGGER_BUFF
	# —— 灵魂叠层强化（装备参考2：「暗影波击杀敌人时，层数不清空」
	#    「终极技能消耗灵魂后，返还50%层数」）——
	#
	# 这两条修饰的是**满层爆发后的层数处理**，不是数值。用 buff 词条承载，
	# 由 `PlayerEquipmentEffects._consume_stacks` 在爆发时读。
	if s.contains("层数不清空"):
		return "[%d, \"soul_persist\", 1.0, 0.0]" % OP_TRIGGER_BUFF
	if s.contains("返还50%层数"):
		return "[%d, \"soul_refund\", 1.0, 0.0]" % OP_TRIGGER_BUFF
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
	# ---------- 32b. 受击概率减伤 / 低血护盾（2026-09-26 补） ----------
	#
	# 「受到伤害时，有 10% 概率减少 50% 伤害」——给**自己**挂一条限时减伤。
	# 形态 `[OP_TRIGGER_BUFF, buff_id, chance, duration, params]`，
	# 第 5 项是数值覆盖（同一条 `gen_sustain_2` 承载不同数值）。
	m = _re(r"受到伤害时[，,]?有\s*(\d+)%\s*概率减少\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, \"gen_sustain_2\", %s, 0.0, {\"dmg_taken_down\": %s}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1)), _f(m.get_string(2))]
	# 「生命值低于 20% 时，获得一个吸收 30% 最大生命值的护盾，持续 10 秒」
	#
	# **不用 `shield` 词条**：`BuffDefs` 里那条的 `absorb` 是固定值，
	# 且玩家侧**没有 absorb 的消费点**（只有敌人侧读）。走它也加不了护盾。
	# 改为 `grant_shield` sentinel —— `PlayerEquipmentEffects` 识别后调
	# `Player._add_shield()`（`shield_power_pct` 用的同一入口，已有消费点）。
	m = _re(r"生命值低于\s*(\d+)%\s*时[，,]?获得一个吸收\s*(\d+)%\s*最大生命值的护盾").search(s)
	if m:
		return "[%d, \"grant_shield\", 1.0, 0.0, {\"pct\": %s, \"cap\": 0.60}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(2))]
	# 「满血时回复转护盾（最多 15%）」
	m = _re(r"满血时回复转(?:化为)?护盾(?:（最多\s*(\d+)%）)?").search(s)
	if m:
		var cap: String = _f(m.get_string(1)) if not m.get_string(1).is_empty() else "0.1500"
		return "[%d, \"grant_shield\", 1.0, 0.0, {\"pct\": %s, \"cap\": %s}]" % [
			OP_TRIGGER_BUFF, cap, cap]
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
		# 「每层额外造成 N% 伤害」是**满层爆发的倍率**，触发条件是 AT_FULL(5)。
		# 旧代码写的字面量 `15` 落在 trigger 槽位上，是笔误（见上一条说明）。
		return "[%d, 5, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, _f(m.get_string(1))]
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

	# ---------- 46. 条件型词条（2026-09-24 补） ----------
	#
	# ## 为什么现在才补
	#
	# 这批共 50 条，此前被 `_RE_SKILL_NOTE` 正则**静默吃掉**——旧正则
	# `^(技能名).*(?:期间|同时|触发时|被击破时|存在时…)` 的第二个 `.*`
	# 会把整条吞下，判为「装备技能的修饰」并跳过。
	#
	# 正则收紧后它们暴露为「无法映射」——说明生成器**根本没有规则**
	# 处理它们，正则只是把它们藏起来、伪装成「已跳过」。这正是假绿灯：
	# 报告显示 0 条无法映射，实际有 50 条缺口。
	#
	# 归为两类：
	#   · **条件型词条**（本节）——「护盾被击破时…」「陷阱触发时…」
	#     与具体技能无关，走 OP_STACK_GAIN + 新 Trigger
	#   · **技能修饰**（上一节正则）——「战吼同时嘲讽敌人1秒」
	#     在修饰某个技能，不属于词条层级
	#
	# 数值一律**按规格原值**，不做平衡调整。

	# —— 护盾被击破时（11 条）——
	# 形态：「护盾被击破时[，]对周围造成 N% 攻击力[的]伤害」
	m = _re(r"护盾被击破时[，,]?\s*对周围造成\s*(\d+)%\s*攻击力(?:的)?伤害").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_SHIELD_BREAK,
			_f(m.get_string(1))]
	m = _re(r"护盾被击破时[，,]?\s*对攻击者造成\s*(\d+)%\s*攻击力伤害").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_SHIELD_BREAK,
			_f(m.get_string(1))]
	# 「对周围造成（反伤层数×10%）攻击力的伤害」——数值是**动态的**（随层数），
	# 不是固定百分比。规格给的是公式而非数值，这里只登记机制、数值留 0，
	# 由 PlayerEquipmentEffects 按当前层数结算（不臆造一个固定值）。
	if s.contains("护盾被击破时") and s.contains("反伤层数"):
		return "[%d, %d, Stat.ATK, 0.0, 0]" % [OP_STACK_GAIN, TRIG_ON_SHIELD_BREAK]
	# 「护盾被击破时冻结周围1秒」→ 施加冻结词条
	if s.contains("护盾被击破时") and s.contains("冻结周围"):
		return "[%d, \"freeze\", 1.0, 1.0]" % OP_TRIGGER_BUFF
	# 「护盾被击破时，回复10%最大生命」
	m = _re(r"护盾被击破时[，,]?\s*回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_SHIELD_BREAK,
			_f(m.get_string(1))]
	# 「元素护盾被击破时，对周围造成元素爆炸」——数值未给，只登记机制
	if s.contains("护盾被击破时") and s.contains("元素爆炸"):
		return "[%d, %d, Stat.AP, 0.0, 0]" % [OP_STACK_GAIN, TRIG_ON_SHIELD_BREAK]

	# —— 护盾存在期间（7 条）——
	m = _re(r"护盾存在时[，,]?\s*攻击\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_SHIELD_UP,
			_f(m.get_string(1))]
	m = _re(r"护盾存在时[，,]?\s*受到伤害减少\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.DEF, %s, 0]" % [OP_STACK_GAIN, TRIG_SHIELD_UP,
			_f(m.get_string(1))]
	m = _re(r"护盾存在时[，,]?\s*反弹\s*(\d+)%\s*近战伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["reflect"], _f(m.get_string(1))]
	m = _re(r"护盾存在时[，,]?\s*攻击附带\s*(\d+)%\s*额外伤害").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_SHIELD_UP,
			_f(m.get_string(1))]
	if s.contains("护盾存在时") and s.contains("免疫控制"):
		return "[%d, \"control_immune\", 1.0, 0.0]" % OP_TRIGGER_BUFF

	# —— 陷阱触发时（2 条）——
	m = _re(r"陷阱触发时对周围\s*(\d+(?:\.\d+)?)\s*米造成\s*(\d+)%\s*攻击力伤害").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_TRAP_TRIGGER,
			_f(m.get_string(2))]
	m = _re(r"陷阱触发时对周围造成\s*(\d+)%\s*攻击力伤害").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_TRAP_TRIGGER,
			_f(m.get_string(1))]

	# —— 召唤物/图腾在场（3 条）——
	m = _re(r"召唤物存在时[，,]?\s*自身(?:伤害增加|攻击力提高)\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_SUMMON_ALIVE,
			_f(m.get_string(1))]
	m = _re(r"图腾存在时自身获得\s*(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %d, Stat.DEF, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_SUMMON_ALIVE,
			_f(m.get_string(1))]
	if s.contains("召唤物死亡时留下减速区域"):
		return "[%d, \"slow\", 1.0, 3.0]" % OP_TRIGGER_BUFF

	# —— 施法/治疗同时（5 条）——
	#
	# 「净化/治疗同时清除负面状态」——`cleanse` 不是 buff 词条，而是一个
	# **即时动作**（移除目标身上的负面状态）。故用专门的 sentinel id，
	# 由 `Player._apply_trigger_affixes` 识别后调用 `BuffHolder` 的移除。
	# **不能**当成 buff 施加——那会变成「给敌人挂一个叫净化的状态」。
	if s.contains("净化同时") or s.contains("治疗之泉同时") or s.contains("治疗同时"):
		if s.contains("清除所有负面状态"):
			return "[%d, \"__cleanse_all__\", 1.0, 0.0]" % OP_TRIGGER_BUFF
		return "[%d, \"__cleanse_one__\", 1.0, 0.0]" % OP_TRIGGER_BUFF
	m = _re(r"净化同时回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, %d, Stat.HP, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_SKILL_CAST,
			_f(m.get_string(1))]
	m = _re(r"治疗区域同时提供\s*(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %d, Stat.DEF, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_SKILL_CAST,
			_f(m.get_string(1))]

	# —— 冲刺/疾跑期间（2 条）——
	m = _re(r"疾跑期间闪避\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.DODGE, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_SPRINT,
			_f(m.get_string(1))]
	m = _re(r"冲锋期间免疫控制").search(s)
	if m:
		return "[%d, \"control_immune\", 1.0, 0.0]" % OP_TRIGGER_BUFF

	# —— 嘲讽期间（1 条）——
	m = _re(r"嘲讽期间受到伤害减少\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.DEF, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_TAUNT,
			_f(m.get_string(1))]

	# —— 格挡/反击姿态期间（2 条）——
	m = _re(r"反击姿态期间受到伤害减少\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.DEF, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_BLOCK_STANCE,
			_f(m.get_string(1))]

	# —— 旋风斩期间（2 条）——
	m = _re(r"旋风斩期间移速\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.SPD, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_WHIRLWIND,
			_f(m.get_string(1))]

	# —— 时间减缓期间（2 条）——
	m = _re(r"时间减缓期间自身攻速\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.ASPD, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_TIME_SLOW,
			_f(m.get_string(1))]

	# —— 荆棘爆发期间（3 条）——
	m = _re(r"荆棘(?:爆发|护盾)期间受到伤害减少\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, Stat.DEF, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_FRENZY,
			_f(m.get_string(1))]
	if s.contains("荆棘爆发期间免疫控制"):
		return "[%d, \"control_immune\", 1.0, 0.0]" % OP_TRIGGER_BUFF

	# —— 其他条件型（3 条）——
	# 「元素状态持续时间翻倍」→ 元素叠层时长 +100%（走 debuff_dur 通道）
	if s.contains("元素状态持续时间翻倍"):
		return "[%d, 1.0, true]" % SP["debuff_dur"]
	# 「加速期间免疫减速」
	if s.contains("加速期间免疫减速"):
		return "[%d, \"slow_immune\", 1.0, 0.0]" % OP_TRIGGER_BUFF
	# 「加速期间击杀敌人延长2秒」→ 击杀延长增益（数值 2 秒，非百分比）
	if s.contains("加速期间击杀敌人延长"):
		return "[%d, %d, Stat.ATK, 0.0, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL]

	# ---------- 46b. 技能修饰：**保持未映射，不伪装** ----------
	#
	# 以下 8 条是「给某个主动技能附加效果」：
	#   战吼同时嘲讽敌人1秒 / 战吼同时降低敌人30%攻击力 /
	#   治愈术同时清除一个负面状态 / 疾风步期间留下火焰路径 /
	#   残影存在时再次冲刺可引爆所有残影
	#
	# **它们是真缺口，不是「技能修饰可跳过」**。判定依据：语义依赖
	# 「那个技能被放出来」这个前提——若当成通用触发词条（「命中时嘲讽」），
	# 玩家不按战吼也会嘲讽，机制就错了。
	#
	# 要真正实现需给 `EquipmentSkills` 表加一列「技能附加效果」
	#（如 `{"on_cast_buff": "taunt"}`），并让 `SkillSystem` 在施法后消费。
	# 那是**表结构变更**，不在本轮范围。
	#
	# 故这里**不写规则、不计数为技能修饰**——让它们留在「无法映射」清单里，
	# 报告如实显示 8 条缺口。**不静默丢弃、不伪装成正常跳过。**

	# ---------- 无法映射 ----------
	# **返回哨兵值而不是在这里记 `_unmapped`**：
	# `_parse_one` 会对同一条文本调用 `_parse_main` **两次**
	#（完整文本 + 主句），若在这里记录就会重复计数
	#（实测未映射数虚高：57 → 133）。由调用方统一记录。
	return "__UNMAPPED__"


## 数值字符串 → 百分比浮点（"50" → "0.5000"）
func _f(pct: String) -> String:
	return "%.4f" % (float(pct) / 100.0)


## 原始数值字符串 → 浮点字面量（**不除以 100**）
##
## 用于「获得 5 点怒气」这类**绝对点数**——`_f` 会把它变成 0.05，
## 那是百分比的转换，对点数不适用。
func _raw(v: String) -> String:
	return "%.4f" % float(v)


# ============================================================
# 两段式：从句剥离 / 从句 → Trigger / 包上触发
# ============================================================

## 把一条词条拆成「触发从句」+「主句」
##
## ## 为什么需要
##
## 文档里大量词条是「**条件**，**效果**」的形式：
##   「生命值低于30%时，吸血效果提升20%」
##   「击杀敌人后，移动速度增加20%，持续3秒」
##   「受到伤害时，有10%概率反弹50%伤害给攻击者」
##
## 单段式解析会拿整条去匹配规则，末尾的宽泛兜底把「伤害」类文本
## 一律压成常驻属性——**条件被静默丢弃**。
##
## ## 判据
##
## 从句必须**同时**满足：
##   · 出现在句首（或分号后的段首）
##   · 以「时，」「后，」「期间」「存在时」等**条件标记**结尾
##   · 长度合理（2~24 字）——太长的多半是主句的一部分
##
## 返回 `{clause, main}`。无从句时 `clause` 为空、`main` 为原文。
##
## **不切分「攻击有N%概率」**：那是「攻击时」的概率，不是独立条件，
## 且现有规则（第 2 节）已能正确处理。切了反而会把概率参数弄丢。
func _split_clause(s: String) -> Dictionary:
	var out := {"clause": "", "main": s}

	# 从句标记（按长度降序匹配，避免「时」先于「存在时」命中）
	var markers := ["存在时", "期间", "触发时", "被击破时", "满层时", "层时"]
	for mk in markers:
		var idx := s.find(mk)
		if idx > 0 and idx <= 24:
			# 「期间」等不带逗号，其后可能直接接主句
			var cut := idx + str(mk).length()
			if cut < s.length() and s[cut] in ["，", ","]:
				cut += 1
			out["clause"] = s.substr(0, idx + str(mk).length())
			out["main"] = s.substr(cut).strip_edges()
			if not str(out["main"]).is_empty():
				return out

	# 「X时，」「X后，」——要求逗号紧跟，避免切到「攻击时造成」这类
	var m := _re(r"^([^，,]{2,24}?(?:时|后))[，,](.+)$").search(s)
	if m:
		var main := m.get_string(2).strip_edges()
		if not main.is_empty():
			out["clause"] = m.get_string(1)
			out["main"] = main
	return out


## 从句 → `{trigger, param}`（识别不了返回 `{trigger: ALWAYS}`）
##
## `param` 承载阈值类从句的数值（「低于30%时」→ 0.30，
## 「金币超过500时」→ 500.0）。非阈值类为 0.0。
##
## **顺序即优先级**：更具体的写法排在前面。例如「生命满时」必须在
## 「生命低于」之前判（否则「满」会被「低于」的正则漏掉），
## 「护盾被击破时」必须在「护盾存在时」之前判。
func _trigger_of_clause(clause: String) -> Dictionary:
	var none := {"trigger": TRIG_ALWAYS, "param": 0.0}
	if clause.is_empty():
		return none
	var c := clause

	# ---- 护盾类（「被击破」必须先于「存在时」）----
	if c.contains("护盾被击破") or c.contains("破除护盾"):
		return {"trigger": TRIG_ON_SHIELD_BREAK, "param": 0.0}
	if c.contains("护盾存在"):
		return {"trigger": TRIG_SHIELD_UP, "param": 0.0}

	# ---- 击杀 + 目标低血（**必须先于纯生命阈值判**）----
	#
	# 「击杀生命值低于15%的敌人时，回复5%最大生命值」——这里「生命值低于15%」
	# 修饰的是**目标**（处决线），不是玩家自己。当成 `LOW_HP` 会让语义反转：
	# 变成「自己血低于15%时回血」。
	#
	# 实测这是本类规则引入的**真回归**（处决者之刃），故显式优先判。
	if c.contains("击杀") and (c.contains("生命") or c.contains("血量")):
		return {"trigger": TRIG_ON_KILL, "param": 0.0}

	# ---- 生命阈值 / 满血（「满」先于「低于」）----
	if c.contains("生命满") or c.contains("满血"):
		return {"trigger": TRIG_HP_FULL, "param": 0.0}
	var m := _re(r"生命(?:值)?低于\s*(\d+)%").search(c)
	if m:
		return {"trigger": TRIG_LOW_HP, "param": float(m.get_string(1)) / 100.0}
	if c.contains("生命低于") or c.contains("血量低于"):
		return {"trigger": TRIG_LOW_HP, "param": 0.5}

	# ---- 资源类 ----
	if c.contains("资源满") or c.contains("储存满") or c.contains("魔力满"):
		return {"trigger": TRIG_RESOURCE_FULL, "param": 0.0}

	# ---- 金币阈值 ----
	m = _re(r"金币(?:超过|大于|达到)\s*(\d+)").search(c)
	if m:
		return {"trigger": TRIG_GOLD_ABOVE, "param": float(m.get_string(1))}

	# ---- 状态期间 ----
	if c.contains("隐身"):
		return {"trigger": TRIG_STEALTH_UP, "param": 0.0}
	if c.contains("石肤") or c.contains("大地守护") or c.contains("钢铁之躯") \
			or c.contains("血海狂") or c.contains("不灭"):
		return {"trigger": TRIG_ON_BLOCK_STANCE, "param": 0.0}
	if c.contains("旋风斩"):
		return {"trigger": TRIG_ON_WHIRLWIND, "param": 0.0}
	if c.contains("时间减缓"):
		return {"trigger": TRIG_ON_TIME_SLOW, "param": 0.0}
	if c.contains("荆棘") or c.contains("反击姿态") or c.contains("狂暴"):
		return {"trigger": TRIG_ON_FRENZY, "param": 0.0}
	if c.contains("嘲讽"):
		return {"trigger": TRIG_ON_TAUNT, "param": 0.0}
	if c.contains("疾跑") or c.contains("冲刺"):
		return {"trigger": TRIG_ON_SPRINT, "param": 0.0}
	if c.contains("召唤物") or c.contains("影分身") or c.contains("图腾") \
			or c.contains("残影"):
		return {"trigger": TRIG_ON_SUMMON_ALIVE, "param": 0.0}

	# ---- 目标状态 ----
	if c.contains("冰冻") or c.contains("冻结") or c.contains("眩晕") \
			or c.contains("麻痹"):
		# 「冰冻目标死亡时」是目标死亡事件，不是「目标受控时」
		if c.contains("死亡"):
			return {"trigger": TRIG_ON_TARGET_DEATH, "param": 0.0}
		return {"trigger": TRIG_ON_TARGET_CONTROLLED, "param": 0.0}
	if c.contains("缠绕结束"):
		return {"trigger": TRIG_ON_TARGET_DEATH, "param": 0.0}

	# ---- 距离阈值 ----
	m = _re(r"(?:距离|超过)\s*(\d+(?:\.\d+)?)\s*米").search(c)
	if m and (c.contains("距离") or c.contains("远")):
		return {"trigger": TRIG_DISTANCE_FAR, "param": float(m.get_string(1))}

	# ---- 非战斗事件 ----
	if c.contains("出售"):
		return {"trigger": TRIG_ON_SELL, "param": 0.0}
	if c.contains("宝箱") or c.contains("开箱"):
		return {"trigger": TRIG_ON_CHEST_OPEN, "param": 0.0}
	if c.contains("回收标枪"):
		return {"trigger": TRIG_ON_RECALL, "param": 0.0}
	if c.contains("免死") or c.contains("致命伤害"):
		return {"trigger": TRIG_ON_CHEAT_DEATH, "param": 0.0}
	if c.contains("元素终焉") or c.contains("抗性触发") or c.contains("元素爆发"):
		return {"trigger": TRIG_ON_ELEMENT_PROC, "param": 0.0}

	# ---- 既有 Trigger（与旧规则一致的口径）----
	if c.contains("击杀"):
		return {"trigger": TRIG_ON_KILL, "param": 0.0}
	if c.contains("受到伤害") or c.contains("受到近战") or c.contains("受击") \
			or c.contains("受到元素"):
		return {"trigger": TRIG_ON_HURT, "param": 0.0}
	if c.contains("暴击"):
		return {"trigger": TRIG_ON_CRIT, "param": 0.0}
	if c.contains("闪避"):
		return {"trigger": TRIG_ON_DODGE, "param": 0.0}
	if c.contains("格挡"):
		return {"trigger": TRIG_ON_BLOCK, "param": 0.0}
	if c.contains("连击"):
		return {"trigger": TRIG_ON_COMBO, "param": 0.0}
	if c.contains("满层") or c.contains("叠满"):
		return {"trigger": TRIG_AT_FULL, "param": 0.0}
	# **带数字的层数阈值**（「5层时…」「3层时…」「8层时…」）
	#
	# 早期只认「满层」「叠满」两个词，于是「5层时消耗全部层数获得护盾」
	# 这类从句**识别不了** → 返回 ALWAYS → 主句解出裸属性 → 报未映射。
	# 实测 3 条卡在这里（预言者头盔 / 荆棘长鞭 / 格挡者壁垒）。
	#
	# 语义上它们同属 `AT_FULL`（层数达到阈值时触发），故归到同一枚举。
	if _re(r"\d+\s*层时").search(c) != null:
		return {"trigger": TRIG_AT_FULL, "param": 0.0}
	if c.contains("使用技能") or c.contains("施放技能") or c.contains("技能命中"):
		return {"trigger": TRIG_ON_SKILL_CAST, "param": 0.0}
	if c.contains("进入新房间") or c.contains("未探索房间"):
		return {"trigger": TRIG_ON_ROOM_ENTER, "param": 0.0}
	if c.contains("陷阱触发"):
		return {"trigger": TRIG_ON_TRAP_TRIGGER, "param": 0.0}
	if c.contains("静止"):
		return {"trigger": TRIG_STATIONARY, "param": 0.0}
	if c.contains("攻击时") or c.contains("攻击命中") or c.contains("攻击有"):
		return {"trigger": TRIG_ON_ATTACK, "param": 0.0}

	# 识别不了 —— 调用方据此报未映射（**不猜**）
	return none


## 把主句的解析结果**包上触发条件**
##
## ## 三种形态的处理
##
## | 主句结果形态 | 处理 |
## |---|---|
## | `[Stat.X, v, bool]` 面板属性 | 转成 `[OP_STACK_GAIN, trig, Stat.X, v, 0]` |
## | `[NNN, v, true]` 扩展通道 | 同上（`NNN` 直接作 stat） |
## | `[2, "buff", chance, dur]` 触发型 | 已是触发语义，**保留原样** |
## | `[3, "elem", v]` 附带元素 | 保留原样（附带是命中时的固有行为） |
##
## ## 为什么不给「触发型」再包一层
##
## `[2, "slow", 0.1, 2.0]` 本身表达「命中时按 10% 概率施加减速」——
## 再包一层 `[4, trig, ...]` 会变成「条件满足时施加一个 buff」，
## 语义重复且 `_make_one_affix` 解不出来。故原样保留。
func _wrap_with_trigger(spec: String, trig: int, param: float) -> String:
	# 触发型 / 附带元素型：原样保留（它们自带触发语义）
	if spec.begins_with("[%d," % OP_TRIGGER_BUFF) \
			or spec.begins_with("[%d," % OP_BONUS_ELEMENT):
		return spec

	# 已经是叠层型：把它的 trigger 换掉（主句解出的 trigger 可能不对）
	var m := _re(r"^\[4,\s*(\d+),\s*(.+)\]$").search(spec)
	if m:
		var rest := m.get_string(2)
		return "[%d, %d, %s]" % [OP_STACK_GAIN, trig, rest]

	# 面板属性 / 扩展通道 → 包成叠层型
	m = _re(r"^\[([A-Za-z_.]+|\d+),\s*([-\d.]+),\s*(true|false)\]$").search(spec)
	if m:
		var stat := m.get_string(1)
		var v := m.get_string(2)
		return "[%d, %d, %s, %s, 0]" % [OP_STACK_GAIN, trig, stat, v]

	# 其他形态（周期型等）：原样保留，不强行包装
	return spec


var _re_cache := {}
func _re(pattern: String) -> RegEx:
	if _re_cache.has(pattern):
		return _re_cache[pattern]
	var r := RegEx.new()
	r.compile(pattern)
	_re_cache[pattern] = r
	return r

## 装备技能修饰的识别（这些在修饰某个技能，不是独立词条）
##
## ## 2026-09-24 修正：旧正则把合法词条吃掉了
##
## 旧版：`^(技能名词表).*(?:期间|同时|触发时|被击破时|存在时|留下|释放|引爆|翻倍|清除|满层时)`
##
## 第二个 `.*` 会把**条件型词条整个吃掉**——「护盾**被击破时**…」
## 「陷阱**触发时**…」「旋风斩**期间**…」全部命中，于是被判为
## 「装备技能的修饰」并**静默丢弃**。
##
## 但实测发现：这 60 条**并非都是合法词条**。禁用正则后其中 **50 条
## 变成「无法映射」**——说明生成器**根本没有规则处理它们**，正则只是
## 把它们藏起来、伪装成「已跳过的技能修饰」。报告全绿，数据在丢。
##
## 现在改为**只匹配真正的技能修饰句式**：技能名 + 数值修饰特征
##（伤害/冷却/持续/层数/范围/概率），且**不含**独立的条件从句结构。
## 剩下的进入「无法映射」清单，逐条补规则——**不猜**。
var _RE_PLACEHOLDER: RegEx = _build_placeholder_re()
var _RE_SKILL_NOTE: RegEx = _build_skill_note_re()
func _build_skill_note_re() -> RegEx:
	var r := RegEx.new()
	# 只认「修饰某个已有技能」的写法：技能名开头 + 该技能的某个数值被改动。
	# 判据是**数值修饰词**（冷却/持续/伤害/范围/层数/概率/速度），
	# 而不是「期间/触发时」这类条件从句——条件从句是正常词条的常见写法。
	r.compile(r"^(?:治愈术|战吼|护盾术|陷阱|毒雾|疾风步|反击姿态|时间减缓|闪现|圣光|烈焰|冰霜|雷霆|旋风|冲锋|突刺|盾击|召唤|狼灵|分身|残影|图腾|领域|新星|箭雨|火球|地刺|落石|风刃|缠绕|净化|驱散|嘲讽|挑衅|锁链|击退|生命汲取|灵魂|暗影|星辰|时空|荆棘|无畏|加速|疾跑|治疗|资源|元素|号令|脉冲|光环)[^，。；]*(?:冷却|持续时长|作用范围|触发范围|层数|触发概率|释放范围)\s*(?:缩减|减少|降低|增加|提升|\+|-|延长)")
	return r


func _build_placeholder_re() -> RegEx:
	var r := RegEx.new()
	r.compile(r"触发概率低，效果小|装备直接生效，通常是一个主动技能|吞噬后永久加到角色本局面板|作为副材融合时给主装备的新词条|基础效果低，比如每击杀回复|完整核心机制，通常包含触发条件|比蓝色更完整的核心机制|带叠层/循环/触发体系")
	return r
