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
	# 2026-09-27：全局伤害减免。**必须单独开一条**——旧版把「获得 N% 伤害减免」
	# 错映射成 `elem_resist`（106，元素抗性），语义完全不同：
	# 元素抗性只挡元素伤害，伤害减免该挡全部来源。
	"dmg_reduction": 146, "dmg_to_shield": 151, "delay_dmg": 152,
	"dmg_to_shield_cap": 153, "execute_threshold": 154,
	# 冷却刷新按**触发源**分键（击杀走 113）；闪避/暴击各自独立，
	# 否则三件装备的触发时机全错（详见 equipment_db 的 SPECIAL_STAT 注释）
	"cd_refresh_dodge": 147, "cd_refresh_crit": 148,
}

## Operation / Trigger 枚举值（与 AffixData 一致）
const OP_BONUS_ELEMENT := 3
const OP_TRIGGER_BUFF := 2
const OP_STACK_GAIN := 4
const OP_GRANT_SKILL := 7
const OP_SKILL_MOD := 8
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
const TRIG_ON_SUMMON_DEATH := 38
const TRIG_ON_STATIONARY := 39
const TRIG_ON_REFLECT := 40

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
	# 写法①（主流）：「主动技能"XXX"——效果」
	var m := _re(r"主动技能\s*[“”\"']([^“”\"']+)[“”\"']").search(own)
	# 写法②（**无引号**）：「主动投掷标枪（120%攻击力）…」
	#
	# 实测只有「猎手标枪」一件这样写，而它**因此拿不到 GRANT_SKILL**——
	# 技能表里就算有定义也放不出来（装备与技能之间少了一环注册）。
	# 技能名取「主动」与首个括号/逗号之间的部分。
	if m == null:
		m = _re(r"^主动(?:技能)?([^（(，,。；]{2,8})[（(]").search(own.strip_edges())
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
	# 时长兜底（见 `_time_bound_wrap` 的说明）
	spec = _time_bound_wrap(spec, s)

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
		#
		# **哨兵值要先判**：`__SKILL__` / `__UNMAPPED__` 不是「解不出来」，
		# 而是规则给出的**明确分类**（技能修饰 / 占位符）。
		# `_trigger_of_spec` 对它们返回 -1，若不先判就会被误报未映射——
		# 实测「不朽壁垒触发后，10秒内减伤+30%且免疫控制」卡在这里
		#（规则已正确匹配并返回 `__SKILL__`，却被这个分支吃掉）。
		if spec == "__SKILL__" or spec == "__UNMAPPED__":
			return spec
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
	#
	# **时长也要带上**：原文「击杀后获得3秒暴击率+15%」的 `3秒`
	# 与条件同样重要——不带的话落地成**永久** +15% 暴击率，
	# 强度完全不是一个量级。规格里这类写法很常见（击杀后/冲刺后/拖拽后）。
	# 时长从**整条原文**取（主句里通常没有），失败则 0（= 永久，与旧行为一致）。
	var dur := _duration_from_text(s)
	if _is_plain_spec(spec):
		return _wrap_with_trigger(spec, trig, float(t["param"]), dur,
			_stack_max_from_text(s), s)

	# 其他形态（扩展通道、周期型等）：**保留旧解析**
	#
	# 这些形态的旧解析往往已表达完整语义（如 `[117, 0.15, true]` 是
	# 「弹射伤害 +15%」），硬包一层会把语义改掉。
	return spec


## 结果是否是**叠层型**（`[4, trigger, ...]`）
func _is_stack_spec(spec: String) -> bool:
	# 多属性形态 `[[4, 1, …], [4, 1, …]]` 也算（展开后的叠层）
	if _re(r"^\s*\[\[\s*4,\s*\d+,").search(spec) != null:
		return true
	return _re(r"^\[4,\s*\d+,").search(spec) != null


## 结果是否是**裸属性**（`[Stat.X, v, bool]` / `[NNN, v, true]`）
func _is_plain_spec(spec: String) -> bool:
	return _re(r"^\[(?:[A-Za-z_.]+|\d+),\s*-?[\d.]+,\s*(?:true|false)\]$").search(spec) != null


## 结果是否是**多属性形态**（`[[…], […]]`，由 `_all_stats_spec` 展开）
func _is_multi_spec(spec: String) -> bool:
	return _re(r"^\s*\[\s*\[").search(spec) != null


## 遍历多属性形态里的每一条子规格（非多属性时返回单元素数组）
##
## **按括号配平切**，不能用 `split("], [")`——那样会把分隔符里的
## 括号一并吃掉，子规格变成残缺的 `Stat.HP, 0.1, true`。
func _sub_specs(spec: String) -> Array:
	if not _is_multi_spec(spec):
		return [spec]
	var out: Array = []
	var depth := 0
	var start := -1
	for i in spec.length():
		var ch := spec[i]
		if ch == "[":
			depth += 1
			if depth == 2:
				start = i
		elif ch == "]":
			if depth == 2 and start >= 0:
				out.append(spec.substr(start, i - start + 1))
				start = -1
			depth -= 1
	return out

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
	# **自足形态**：这些结果不携带触发条件，也**不该**被包 trigger——
	# 它们改的是「某个技能」或「提供某个技能」，不是「玩家某事件时获得属性」。
	#
	# 不加这条会让它们被误判为未映射：`_parse_one` 的从句校验逻辑是
	# 「从句识别不了 + 结果不是触发型 → 报未映射」，而
	# 「疾风步**期间**留下火焰路径」的从句「疾风步期间」不在映射表里
	#（它修饰的是技能，不是玩家状态），于是 `[8, {...}]` 被丢弃。
	if spec.begins_with("[%d," % OP_SKILL_MOD) \
			or spec.begins_with("[%d," % OP_GRANT_SKILL):
		return TRIG_ALWAYS
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
	# ---------- 0. 多属性并列（**必须最前**）----------
	#
	# 「暴击率+25%、暴击伤害+50%」「每层+4%攻速、+3%暴击率」
	# 「生命低于50%时…攻击+40%、攻速+30%、吸血+25%」
	#
	# 这类**用顿号/逗号并列多个属性**的写法，旧规则只认第一个
	#（实测 14 条：「暴击率+25%、暴击伤害+50%」只解析出暴击率，
	# 暴击伤害整个丢失）。故必须先于一切单属性规则。
	var multi := _parse_stat_list(s)
	if not multi.is_empty():
		return multi
	# ---------- 0a. 免死后效果（**必须最前**）----------
	#
	# 「不朽壁垒触发后，10秒内减伤+30%且免疫控制」「触发免死后，获得5秒无敌」
	# —— 这两条是**免死机制的后续保护窗口**，效果已由
	# `Player._try_cheat_death` 自动挂（见那里的 `eq_cheat_death_guard`），
	# 故这里**只需识别并跳过**，不产出词条。
	#
	# **必须在最前**：否则「减伤+30%」会被更早的低血/减伤规则截胡成
	# `[106, 0.3, true]`（元素抗性）——语义完全不对（实测踩到）。
	if (s.contains("壁垒触发后") or s.contains("触发免死后")) \
			and (s.contains("减伤") or s.contains("无敌")):
		_skill_notes += 1
		return "__SKILL__"
	# ---------- 0b. 状态期间免疫（**必须在 0a 之后、第 1 节之前**）----------
	#
	# 「守护期间免疫击退」「石肤期间免疫击退」等——「状态名 + 期间 + 免疫X」。
	#
	# 走 `ON_BLOCK_STANCE`（状态期间触发）**复用已有链路**——那是
	# 「石肤/大地守护/钢铁之躯期间」的既有 Trigger，语义相符。
	#
	# **必须在最前**：否则「免疫击退」会被更早的规则看成裸属性或
	# `ctrl_resist`（实测「守护期间免疫击退」被解成 `[112, 1.0, true]`）。
	#
	# 用局部变量 `im` 而不是 `m`——`m` 在 `_parse_main` 的后面才声明，
	# 这里用它会报 `Identifier "m" not declared`。
	var im := _re(r"^(.{2,8})期间免疫(击退|击飞|控制|减速|伤害)").search(s)
	if im:
		return "[%d, %d, Stat.DEF, 0.0, 0]" % [OP_STACK_GAIN, TRIG_ON_BLOCK_STANCE]
	# 「攻击力提高至60%」——**语义有歧义，按上下文推断**
	#
	# 字面是「把攻击力**设为** 60%」（不合理）。它是「护盾强化」的**融合列**，
	# 而该装备自有列是「护盾存在时，攻击力提高40%」——
	# 融合词条的语义应是**强化自有**：把 40% 提到 60%。
	#
	# 故按「护盾存在时攻击力 +60%」落地（`SHIELD_UP` 触发）。
	# **这是推断，已在清单标注**——若策划原意不同需回头改。
	im = _re(r"^攻击力提高至\s*(\d+(?:\.\d+)?)%").search(s)
	if im:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_SHIELD_UP,
			_f(im.get_string(1))]

	# ---------- 0. 装备技能的修饰（**不是词条**） ----------
	if s.begins_with("主动技能"):
		return "__SKILL__"
	if _RE_SKILL_NOTE.search(s) != null:
		return "__SKILL__"

	# 生命低于 N% 时进入「血海狂暴」——攻击+40%、攻速+30%、吸血+25%
	#
	# 与上面「生命低于50%时，攻击力+60%…」是**同一机制的不同写法**
	#（「攻击+」而非「攻击力+」，且带一个状态名）。旧版把这条整条压成
	# `[Stat.ATK, 0.40]`——**触发条件、攻速、吸血全丢**，
	# 而且 0.40 其实是**攻速**的数值（攻击是 40%，恰好也是 40 才没露馅）。
	var bs := _re(r"生命(?:值)?低于\s*(\d+)%\s*时进入.*?攻击\s*\+?\s*(\d+)%\s*[、，,]\s*攻速\s*\+?\s*(\d+)%\s*[、，,]\s*吸血\s*\+?\s*(\d+)%").search(s)
	if bs:
		var bth := _f(bs.get_string(1))
		var b1 := "[%d, %d, Stat.ATK, %s, 0, %s]" % [OP_STACK_GAIN, TRIG_LOW_HP, _f(bs.get_string(2)), bth]
		var b2 := "[%d, %d, Stat.ASPD, %s, 0, %s]" % [OP_STACK_GAIN, TRIG_LOW_HP, _f(bs.get_string(3)), bth]
		var b3 := "[%d, %d, %d, %s, 0, %s]" % [OP_STACK_GAIN, TRIG_LOW_HP, SP["lifesteal"], _f(bs.get_string(4)), bth]
		return "[%s, %s, %s]" % [b1, b2, b3]

	# 低血多属性（血怒 / 血海狂潮另一写法）
	#
	# 「生命低于50%时，攻击力+60%、**攻速+40%、吸血+30%**」——
	# 旧规则只认出第一项（且血海狂潮连触发条件都丢了，
	# 把「攻速+40%」的 40% 当成了攻击力）。
	# 现展开成多条：面板属性走 `STACK_GAIN`+`LOW_HP`，
	# 吸血走 `lifesteal` 通道（那是扩展通道，不是面板属性）。
	#
	# **必须放在单属性的「生命低于N%时，攻击力+X%」之前**。
	var lhm := _re(r"生命(?:值)?低于\s*(\d+)%\s*时[，,]?攻击力\s*\+?\s*(\d+)%\s*[、，,]\s*攻速\s*\+?\s*(\d+)%\s*[、，,]\s*吸血\s*\+?\s*(\d+)%").search(s)
	if lhm:
		var th := _f(lhm.get_string(1))
		var ap_ := "[%d, %d, Stat.ATK, %s, 0, %s]" % [OP_STACK_GAIN, TRIG_LOW_HP, _f(lhm.get_string(2)), th]
		var as_ := "[%d, %d, Stat.ASPD, %s, 0, %s]" % [OP_STACK_GAIN, TRIG_LOW_HP, _f(lhm.get_string(3)), th]
		var ls_ := "[%d, %d, %d, %s, 0, %s]" % [OP_STACK_GAIN, TRIG_LOW_HP, SP["lifesteal"], _f(lhm.get_string(4)), th]
		return "[%s, %s, %s]" % [ap_, as_, ls_]

	# 攻击附带元素伤害（规格 #4） ----------
	var m := _re(r"攻击附带\s*(\d+)%\s*(火焰|冰霜|雷电|毒素|大地|疾风)伤害").search(s)
	if m:
		var ek: String = str(ELEM_KEY.get(m.get_string(2), "fire"))
		return "[%d, \"%s\", %s]" % [OP_BONUS_ELEMENT, ek, _f(m.get_string(1))]
	m = _re(r"攻击附带\s*(\d+)%\s*吸血").search(s)
	if m:
		return "[%d, %s, true]" % [SP["lifesteal"], _f(m.get_string(1))]
	# 「攻击附带 N% 减速效果，持续 D 秒」——**N% 是减速量，此前整个丢掉**，
	# 落成 `[2,"slow",1.0,2.0]`（表定 25% + 写死 2 秒）。
	m = _re(r"攻击附带\s*(\d+(?:\.\d+)?)%\s*减速效果?\s*[，,]?\s*持续\s*(\d+(?:\.\d+)?)\s*秒").search(s)
	if m:
		return "[%d, \"slow\", 1.0, %s, {\"slow\": %s}]" % [
			OP_TRIGGER_BUFF, m.get_string(2), _f(m.get_string(1))]
	m = _re(r"攻击附带\s*(\d+)%\s*减速").search(s)
	if m:
		return "[%d, \"slow\", 1.0, 2.0]" % OP_TRIGGER_BUFF
	m = _re(r"攻击附带穿透效果.*无视.*?(\d+)%\s*护甲").search(s)
	if m:
		return "[%d, %s, true]" % [SP["elem_pen"], _f(m.get_string(1))]

	# ---------- 2. 攻击概率触发（规格 #2） ----------
	# 「攻击必定施加中毒（每秒20%攻击力毒素伤害，持续5秒，最多5层）」
	#
	# **「流血」必须走 `bleed` 而不是 `poison_rot`**：两者的 DOT 口径不同
	#（流血吃**攻击力** `dot_atk`、毒蚀吃**法强** `dot_pct`）。
	# 实测荆棘长鞭的「攻击必定施加流血」被挂成了毒蚀。
	m = _re(r"攻击必定施加(中毒|流血|燃烧)").search(s)
	if m:
		var dur := 0.0
		var md0 := _re(r"持续\s*(\d+(?:\.\d+)?)\s*秒").search(s)
		if md0:
			dur = float(md0.get_string(1))
		var eff1 := m.get_string(1)
		var bid1 := "bleed" if eff1 == "流血" \
			else str(BUFF_OF.get(eff1, "poison_rot"))
		# 参数合并：**不能只传 max_stacks**（`params_of_active` 是整体替换，
		# 只传层数会把 DOT 参数一起抹掉 → 中毒变成 0 伤害）。
		# 先把原文的「每秒 N% 攻击力/法强伤害」并进来，再带上层数上限。
		var prms := PackedStringArray()
		var mdmg := _re(r"每秒\s*(\d+(?:\.\d+)?)%\s*(攻击力|法强|法术强度)").search(s)
		if mdmg:
			var key1 := "dot_atk" if mdmg.get_string(2) == "攻击力" else "dot_pct"
			prms.append("\"%s\": %s" % [key1, _f(mdmg.get_string(1))])
		# 毒蚀的全局易伤是该词条的核心，覆盖时必须带上
		if bid1 == "poison_rot":
			prms.append("\"vuln\": 0.0100")
		# 「（…最多N层）」的层数上限：`poison_rot` 表定 30 层，
		# 而这条装备说的是 5 层——不带就被表定值盖掉。
		var ms := _stack_max_from_text(s)
		if ms > 0:
			prms.append("\"max_stacks\": %d" % ms)
		var extra := "" if prms.is_empty() else ", {%s}" % ", ".join(prms)
		return "[%d, \"%s\", 1.0, %.1f%s]" % [OP_TRIGGER_BUFF, bid1, dur, extra]
	# 形态：「攻击有P%概率点燃目标（每秒N%攻击力火焰伤害，持续D秒）」
	#
	# 与「概率使目标燃烧」是同义写法，但用「点燃」+「火焰伤害」+**全角括号**。
	# **必须放在下面那条泛化的状态规则之前**——那条只认效果名紧跟数值，
	# 匹配到「点燃目标（每秒30%…」时会给出错误的时长/缺失的量级。
	m = _re(r"攻击有\s*(\d+)%\s*概率点燃目标\s*[（(]\s*每秒\s*(\d+(?:\.\d+)?)%\s*攻击力\s*火焰伤害\s*[，,]?\s*持续\s*(\d+(?:\.\d+)?)\s*秒").search(s)
	if m:
		return "[%d, \"burn\", %s, %s, {\"dot_atk\": %s}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1)), m.get_string(3), _f(m.get_string(2))]
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
	#
	# **「伤害减免」必须走专用通道 `dmg_reduction`（146）**，不能塞元素抗性：
	# 元素抗性只挡元素伤害，而「获得 N% 伤害减免」该挡全部来源。
	# 旧版这里返回 `SP["elem_resist"]`——实测「守护肩甲：生命值低于50%时，
	# 获得20%伤害减免」在数据库里就是 `[4, 11, 106, 0.2, 0]`，
	# 玩家低血时只多了 20% 元素抗性。
	m = _re(r"生命低于\s*\d+%\s*时.*?(\d+)%\s*伤害减免").search(s)
	if m:
		return "[%d, %s, true]" % [SP["dmg_reduction"], _f(m.get_string(1))]
	m = _re(r"对生命值?低于\s*(\d+)%\s*的敌人.*?额外\s*(\d+)%\s*伤害").search(s)
	if m:
		# **阈值必须带上**：`value` 是增伤比例，阈值是另一个数
		#（「低于50%…加10%」→ 值 0.10、阈值 0.50）。旧版只带增伤、
		# 阈值丢失，而消费端把增伤当阈值用——两处都错。
		return "[[%d, %s, true], [%d, %s, true]]" % [SP["execute_line"],
			_f(m.get_string(2)), SP["execute_threshold"], _f(m.get_string(1))]
	# 「对生命值低于 N% 的**敌人**伤害+M%」——同一条语义的另一种写法。
	#
	# **注意「的敌人」这个限定**：没有它的话会误伤「每层目标受到伤害+4%」
	# 这类**易伤**词条（那是对目标的 debuff，不是自己的处决线）。
	m = _re(r"对生命值?低于\s*(\d+)%\s*的敌人\s*伤害\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[[%d, %s, true], [%d, %s, true]]" % [SP["execute_line"],
			_f(m.get_string(2)), SP["execute_threshold"], _f(m.get_string(1))]
	m = _re(r"对满血敌人造成额外\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[[%d, %s, true], [%d, 100.00, true]]" % [SP["execute_line"],
			_f(m.get_string(1)), SP["execute_threshold"]]

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
		# **按触发源分键**：这条是「闪避时」，不能落进 `cd_refresh`
		#（那是击杀路径）——否则击杀时白触发、闪避时反而不触发。
		return "[%d, %s, true]" % [SP["cd_refresh_dodge"], _f(m.get_string(1))]
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
	# 范围扩大（狂战士之怒的融合列）
	#
	# 规格原文只有这三个字，**没有任何数值**，也没说扩大多少米。
	# 它是「生命低于50%时，普攻变为范围攻击」的**强化**——故落地为
	# 「把该普攻的范围半径提到 3.5 米」（自有列的默认 2.5 米）。
	#
	# 用 `SKILL_MOD` 而不是压成属性：它改的是**普攻的形态**，
	# 压成 `aoe_dmg_pct` 会让狂暴期间只多 50% 伤害、半径纹丝不动。
	# 走 `basic_attack_expand_radius` 前缀，**不需要技能名**——
	# `_skill_mods_for` 是按「哪个技能的来源装备」匹配的，
	# 而普攻不属于任何装备技能，故必须单独取。
	if s == "范围扩大":
		return "[%d, {\"basic_attack_expand_radius\": 3.5000}]" % OP_SKILL_MOD

	# ---------- 预言（预言者王冠「暴击·预言连锁流」） ----------
	#
	# 规格三行：
	#   自有：「暴击叠加1层"预言"（最多6层），每层+6%暴击伤害；
	#          6层时下一次攻击必定暴击并造成300%伤害，
	#          同时将预言传播至周围2名敌人（各3层）」
	#   融合：「预言传播时，自身获得3秒+20%暴击率」
	#
	# 落在**两条** `STACK_GAIN` 上，靠**共用的 `stat`** 配对
	#（与「击杀叠层 + 满层爆发」同一套机制，见 `_fire_stack_full`）：
	#   ① 叠层：`[4, 6, Stat.CRD, 0.06, 6]`（暴击时 +1 层，每层 +6% 暴伤）
	#      触发用 `ON_CRIT`（6）——玩家侧由 `_apply_trigger_affixes` 挂钩
	#   ② 满层：`[4, 5, Stat.CRD, 1.0, 0, 0, {burst: "prophecy", ...}]`
	#      `Stat.CRD` 两处相同 → `_fire_stack_full` 能配上
	#
	# 第 7 槽的参数字典承载「必暴倍率 / 传播人数与层数 / 传播时的自身增益」——
	# 这些规格复杂到单个 `a.value` 表达不了。
	#
	# **两行必须分别解析**：`_parse_one` 只接受**一个** spec，
	# 故不能让第一行的规则一次吐两条。
	if s.contains("暴击叠加1层") and s.contains("预言"):
		m = _re(r"暴击叠加\s*(\d+)\s*层[“\"]?预言[”\"]?[（(]最多\s*(\d+)\s*层[）)][，,]?每层\s*\+?(\d+)%\s*暴击伤害").search(s)
		if m:
			return "[%d, %d, Stat.CRD, %s, %s]" % [
				OP_STACK_GAIN, TRIG_ON_CRIT, _f(m.get_string(3)), m.get_string(2)]
	# 满层：「6层时下一次攻击必定暴击并造成300%伤害，同时将预言传播至周围2名敌人（各3层）」
	if s.contains("必定暴击") and s.contains("传播"):
		m = _re(r"造成\s*(\d+)%\s*伤害.*?传播至周围\s*(\d+)\s*名敌人[（(]各\s*(\d+)\s*层").search(s)
		if m:
			var extra := "{\"burst\": \"prophecy\", \"crit_mult\": %.4f, \"spread_count\": %s, \"spread_layers\": %s, \"spread_radius\": 5.0, \"spread_stat\": %d, \"spread_value\": 0.06, \"spread_duration\": 8.0, \"spread_max\": 6}" % [
				float(m.get_string(1)) / 100.0, m.get_string(2), m.get_string(3),
				AttributeSystem.Stat.CRD]
			return "[%d, %d, Stat.CRD, 1.0, 0, 0, %s]" % [
				OP_STACK_GAIN, TRIG_AT_FULL, extra]
	# 融合：「预言传播时，自身获得 N 秒 +M% 暴击率」
	#
	# 它是**满层爆发的一部分**（只在「真的传播了」之后生效），不是独立词条。
	# 但它在**融合列**、与自有列的核心规则分属两条 affix，故走
	# **跨条累积器**（与能量储存 / 残影同一套模式）：产出 sentinel
	# `prophecy_self`，由 `_merge_prophecy_self` 合并进规则后再交给 Player。
	if s.contains("预言传播时") and s.contains("暴击率"):
		m = _re(r"自身获得\s*(\d+)\s*秒\s*\+?(\d+)%\s*暴击率").search(s)
		if m:
			return "[%d, \"prophecy_self\", 1.0, 0.0, {\"self_crt\": %.4f, \"self_crt_seconds\": %s}]" % [
				OP_TRIGGER_BUFF, float(m.get_string(2)) / 100.0, m.get_string(1)]

	# —— 反弹伤害时给攻击者挂状态（反伤徽章 / 荆棘系列，5 条）——
	#
	# ## 这里同时修了一个**数值错**，不只是「概率当效果」
	#
	# 原文「反弹伤害有10%概率眩晕攻击者1秒」里 `10%` 是**概率**。
	# 旧规则把它当成了 `reflect_pct` 的数值 → 反伤徽章的反弹量变成
	# 10%(自有) + 10%(格挡翻倍) + 10%(融合) + 10%(眩晕) = **40%**，
	# 而「眩晕」整个不存在。修好后反弹量回到 30%，并真的会眩晕。
	#
	# 形态：「反弹伤害有 N% 概率眩晕攻击者 M 秒」
	m = _re(r"反弹伤害有\s*(\d+)%\s*概率眩晕攻击者\s*(\d+)\s*秒").search(s)
	if m:
		return "[%d, \"stun\", %.4f, %s.0, {\"trigger\": %d}]" % [OP_TRIGGER_BUFF,
			float(m.get_string(1)) / 100.0, m.get_string(2), TRIG_ON_REFLECT]
	# 形态：「反弹伤害有 N% 概率(使攻击者)?流血 M 秒」（荆棘之环少一个「使」字）
	m = _re(r"反弹伤害有\s*(\d+)%\s*概率(?:使攻击者)?流血\s*(\d+)\s*秒").search(s)
	if m:
		return "[%d, \"bleed\", %.4f, %s.0, {\"trigger\": %d}]" % [OP_TRIGGER_BUFF,
			float(m.get_string(1)) / 100.0, m.get_string(2), TRIG_ON_REFLECT]

	# —— 击杀概率掉金（经济肩甲 / 贪婪之眼）——
	#
	# ## 与「金币获取量 +N%」是**两条不同的词条**
	#
	# 后者是乘区（走 `LootSystem._gold_mult`），每次都多一点；
	# 本条是**独立的额外掉落**，偶尔多一笔。期望值恰好接近，
	# 但分布完全不同——规格把它们分开写，故实现也分开。
	#
	# 旧版把概率当成了 `gold_gain_pct` 的数值（「5%」→ 金币获取 +0.05），
	# 概率与「额外掉落」都丢了。
	#
	# **必须先于「金币获取量」规则**，否则会被它吃掉。
	# 数值可能写成 `（10~50）`（**全角括号**，与前半句的逗号写法不同）——
	# 实测贪婪之眼就是这一种，不放宽会漏。
	m = _re(r"击杀(精英/Boss)?敌人有\s*(\d+)%\s*概率(?:额外)?掉落\s*(?:[（(]\s*)?(\d+)(?:\s*~\s*(\d+))?\s*(?:[）)])?\s*金币").search(s)
	if m:
		var elite := "true" if not m.get_string(1).is_empty() else "false"
		var lo := m.get_string(3)
		var hi := m.get_string(4)
		var amt := ("\"amount_min\": %s, \"amount_max\": %s" % [lo, hi]) \
			if not hi.is_empty() else ("\"amount\": %s" % lo)
		return "[%d, \"kill_gold\", 1.0, 0.0, {\"kill_gold\": {\"chance\": %.4f, \"elite_only\": %s, %s}}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(2)) / 100.0, elite, amt]
	# 语序变体：「击杀敌人有 N% 概率**掉落额外金币**（M~K）」
	#
	# 与上面的区别是「额外」在「掉落」**之后**、数字在「金币」**之后**
	#（「掉落额外金币（10~50）」）。实测贪婪之眼是这一种，
	# 用上面那条（要求「额外掉落」紧邻）匹配不到。
	m = _re(r"击杀敌人有\s*(\d+)%\s*概率掉落额外金币\s*[（(]\s*(\d+)\s*~\s*(\d+)\s*[）)]").search(s)
	if m:
		return "[%d, \"kill_gold\", 1.0, 0.0, {\"kill_gold\": {\"chance\": %.4f, \"elite_only\": false, \"amount_min\": %s, \"amount_max\": %s}}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0,
			m.get_string(2), m.get_string(3)]

	# 「击杀精英/Boss额外掉落 M~K 金币」——**没有概率**（必定掉落）
	m = _re(r"击杀精英/Boss额外掉落\s*(\d+)~(\d+)\s*金币").search(s)
	if m:
		return "[%d, \"kill_gold\", 1.0, 0.0, {\"kill_gold\": {\"chance\": 1.0, \"elite_only\": true, \"amount_min\": %s, \"amount_max\": %s}}]" % [
			OP_TRIGGER_BUFF, m.get_string(1), m.get_string(2)]

	# ---------- E 组：概率攻击效果（2026-09-28） ----------
	#
	# 这批词条此前被压成**静态属性**（`[117, 0.2]` = 元素伤害 +20%），
	# 概率与真实效果整个丢失。现统一产出 sentinel `attack_bonus`，
	# 参数字典携带规则，由 `PlayerEquipmentEffects` 累积后交给 Player。
	#
	# **必须放在「攻击有 N% 概率…」的通用规则之前**，否则会被吃掉。

	# 「攻击有 N% 概率追加 M 次 K% 伤害的攻击」（双重打击）
	m = _re(r"攻击有\s*(\d+)%\s*概率追加一次\s*(\d+)%\s*伤害的攻击").search(s)
	if m:
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"extra_hits\": {\"chance\": %.4f, \"hits\": 1, \"mult\": %.4f}}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0,
			float(m.get_string(2)) / 100.0]
	# 融合「追加攻击概率提升至40%」——**覆盖**同一条规则的概率
	m = _re(r"追加攻击概率提升至\s*(\d+)%").search(s)
	if m:
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"extra_hits\": {\"chance\": %.4f, \"hits\": 1, \"mult\": 0.5000}}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0]
	# 「攻击有 N% 概率分裂为 M 枚额外弩箭（各 K% 伤害）」（分裂弩）
	m = _re(r"攻击有\s*(\d+)%\s*概率分裂为\s*(\d+)\s*枚额外弩箭[（(]各\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"extra_hits\": {\"chance\": %.4f, \"hits\": %s, \"mult\": %.4f}}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0, m.get_string(2),
			float(m.get_string(3)) / 100.0]
	# 「远程/投射物攻击有 N% 概率额外发射 M 枚投射物（K% 伤害）」
	#（分裂箭袋 / 多重射击徽章）
	m = _re(r"(?:远程|投射物)攻击有\s*(\d+)%\s*概率额外发射\s*(\d+)\s*枚投射物[（(](\d+)%\s*伤害").search(s)
	if m:
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"extra_hits\": {\"chance\": %.4f, \"hits\": %s, \"mult\": %.4f}}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0, m.get_string(2),
			float(m.get_string(3)) / 100.0]
	# 「攻击有 N% 概率造成双倍伤害」（幸运之刃）+ 融合「概率提升至 M%」
	m = _re(r"攻击有\s*(\d+)%\s*概率造成双倍伤害").search(s)
	if m:
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"double_chance\": %.4f}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0]
	m = _re(r"概率提升至\s*(\d+)%").search(s)
	if m:
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"double_chance\": %.4f}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0]
	# 「每次攻击命中，有 N% 概率使下次攻击速度翻倍」（迅捷护手）
	m = _re(r"每次攻击命中[，,]?有\s*(\d+)%\s*概率使下次攻击速度翻倍").search(s)
	if m:
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"quick_chance\": %.4f}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0]
	# 「攻击有 N% 概率触发"影袭"——…造成 K% 攻击力伤害，冷却 S 秒」（暗影短刃）
	m = _re(r"攻击有\s*(\d+)%\s*概率触发[“\"]?影袭[”\"]?.*?造成\s*(\d+)%\s*攻击力伤害.*?冷却\s*(\d+)\s*秒").search(s)
	if m:
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"shadow_chance\": %.4f, \"shadow_mult\": %.4f, \"shadow_cd\": %s}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0,
			float(m.get_string(2)) / 100.0, m.get_string(3)]

	# 「投射物有 N% 概率穿透 M 个额外目标」（穿透弹头）
	m = _re(r"投射物有\s*(\d+)%\s*概率穿透\s*(\d+)\s*个额外目标").search(s)
	if m:
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"proj_pierce_chance\": %.4f, \"proj_pierce_count\": %s}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0, m.get_string(2)]
	# 吞噬「投射物穿透概率增加 N%」——叠加到同一条规则的**概率**上
	m = _re(r"投射物穿透概率增加\s*([\d.]+)%").search(s)
	if m:
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"proj_pierce_chance\": %.4f, \"proj_pierce_count\": 1}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0]
	# 「投射物命中时有 N% 概率弹射至最近敌人」（分裂箭袋融合）
	#
	# **概率交给投射物自己掷**（飞行中命中那一刻），故只传概率，
	# 不预先决定「这根子弹会不会弹」。
	m = _re(r"投射物命中时有\s*(\d+)%\s*概率弹射至最近敌人").search(s)
	if m:
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"proj_bounce_chance\": %.4f}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0]

	# ---------- 区域减速（装备参考2：毒雾/领域类，2026-09-28） ----------
	#
	# ## 统一产出中性 sentinel，由**装备侧**决定落到哪里
	#
	# 生成器逐行解析，拿不到「这件装备还有没有别的词条」——
	# 而两类来源（装备自带光环 vs 技能开区域）的落地方式不同：
	#   ① 有 `aura_damage` 的装备（荆棘领域）→ 挂到**同一个光环规则**上
	#   ② 靠技能开区域的装备（毒雾弹 / 暗影领域）→ 挂到**那个区域**上
	# 故这里只产出 `zone_slow` + 量级，路由交给
	# `PlayerEquipmentEffects._merge_zone_slow`（它拿得到 inst）。
	#
	# 形态：「<领域>内敌人移速 -N%」
	#
	# **不锚定行首、也不要前缀分组**：实测文本就是「领域内敌人移速-20%」
	#（没有「荆棘」之类的领域名前缀），锚 `^` 会一律匹配失败。
	# 「内敌人移速」这个特征本身已足够特异，不会误伤。
	m = _re(r"(?:领域|毒雾)内敌人移速\s*[-−]\s*(\d+)%").search(s)
	if m:
		return "[%d, \"zone_slow\", 1.0, 0.0, {\"slow_pct\": %s}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1))]
	# 形态：「护盾存在时，周围敌人移速 -N%」（冰霜之心）
	#
	# 「护盾存在时」是**真的条件**（不是常驻），故标记 `require_shield`，
	# 由 `Player._tick_aura` 判 `shield > 0` 后才施加——
	# 否则这条会退化成「无条件光环减速」。
	m = _re(r"护盾存在时[，,]?周围敌人移速\s*[-−]\s*(\d+)%").search(s)
	if m:
		return "[%d, \"zone_slow\", 1.0, 0.0, {\"slow_pct\": %s, \"require_shield\": true}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1))]

	# ---------- 残影（踏虚神靴「位移·残影歼灭流」） ----------
	#
	# 规格三行，跨自有/融合两列：
	#   自有：「冲刺留下残影（继承50%攻击，持续5秒，最多4个）；
	#          残影存在时再次冲刺可引爆所有残影，每个造成150%攻击力伤害；
	#          引爆后冲刺冷却立即刷新（每3秒最多触发1次）」
	#   融合：「引爆残影时，每个残影回复3%最大生命」
	#
	# **必须带齐自有列的两条**——只带「留影」会让残影永远炸不掉
	#（那才是这件装备的核心循环）。故第一条正则同时认「留下残影」。
	#
	# 「继承50%攻击」是**紫色版**残影自己攻击的设定；橙色版只在引爆时
	# 造成 150% 攻击力伤害，故 50% 在该装备上无消费点（见 Player 的注释）。
	m = _re(r"冲刺留下残影[（(]继承\s*(\d+)%攻击[，,]?持续\s*(\d+)\s*秒[，,]?最多\s*(\d+)\s*个").search(s)
	if m:
		return "[%d, \"afterimage\", 1.0, 0.0, {\"life\": %s, \"max_count\": %s, \"explode_mult\": 1.5000, \"refresh_cd\": 3.0, \"heal_pct\": 0.0}]" % [
			OP_TRIGGER_BUFF, m.get_string(2), m.get_string(3)]
	# 单条「残影存在时再次冲刺可引爆…每个造成 N% 攻击力伤害」
	m = _re(r"残影存在时再次冲刺可引爆所有残影[，,]?每个造成\s*(\d+)%\s*攻击力伤害").search(s)
	if m:
		return "[%d, \"afterimage\", 1.0, 0.0, {\"explode_mult\": %s}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1))]
	# 融合：「引爆残影时，每个残影回复 N% 最大生命」
	m = _re(r"引爆残影时[，,]?每个残影回复\s*(\d+)%\s*最大生命").search(s)
	if m:
		return "[%d, \"afterimage\", 1.0, 0.0, {\"heal_pct\": %s}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1))]
	# 「引爆后冲刺冷却立即刷新（每3秒最多触发1次）」
	#
	# **必须在这里拦住**：不放行的话会被泛化的 `cd_refresh` 规则吃成
	# `[113, 1.0, true]` = 「**击杀时** 100% 刷新所有冷却」——
	# 触发源完全不同（规格是「引爆后」），等于白送一个击杀刷新。
	#
	# 实际的刷新由 `_afterimage_rule.refresh_cd` 在引爆时执行。
	# 这里返回一个**不带参数**的 afterimage 哨兵：既标记该行已处理，
	# 又不会覆盖其它条目累积的参数（`_merge_afterimage` 只合并出现的键）。
	if s.contains("引爆后") and s.contains("冲刺冷却立即刷新"):
		return "[%d, \"afterimage\", 1.0, 0.0]" % OP_TRIGGER_BUFF

	# 生命低于 N% 时，普通攻击变为范围攻击，造成 M% 伤害
	#
	# ## 这里此前是错的（用户 2026-09-27 指出）
	#
	# 旧版把 M% 压成 `aoe_dmg_pct` 属性（`M/100 - 1`）——**语义完全不对**：
	# 「造成 150% 伤害」指的是**这一击**造成攻击力 150%，而
	# `aoe_dmg_pct` 是「所有范围技能伤害 +N%」的被动增伤。
	# 更要紧的是「**变为范围攻击**」这个机制整个没落地。
	#
	# 现改为走 `SKILL_MOD` 的普攻通道，由玩家在低血时切换普攻判定形态。
	m = _re(r"生命(?:值)?低于\s*(\d+)%\s*时[，,]?普通攻击变为范围攻击[，,]?造成\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, {\"basic_attack_aoe\": true, \"basic_attack_aoe_mult\": %.4f, \"basic_attack_aoe_threshold\": %.4f}]" % [
			OP_SKILL_MOD, float(m.get_string(2)) / 100.0,
			float(m.get_string(1)) / 100.0]
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
	# **「目标/敌人受到伤害 +N%」的通用写法**（2026-09-27）
	#
	# 判据是「**目标/敌人** + 受到伤害」这个组合——它明确说的是**对方**
	# 挨打更疼（易伤），而第 9 节兜底的 `nm.contains("受到伤害")` 会把它
	# 当成「玩家自己减伤」（`dmg_reduction`），**方向反了**。
	#
	# 实测 7 条落错：猎杀者长弓 / 风暴之眼 / 荆棘囚笼 / 荆棘链刃 /
	# 腐蚀之刃 / 锁链拖拽链刃 / 霜噬巨剑。
	# 必须放在第 9 节**之前**。
	#
	# **排除「被冻结/被冰冻敌人」**：那条有自己的通道 `frozen_dmg`(141)
	#（有专门的消费点），走通用易伤会把它覆盖掉——实测测试立刻抓到。
	if not s.contains("冻结") and not s.contains("冰冻"):
		m = _re(r"(?:目标|敌人)[^。]{0,14}?受到(?:冰霜|火焰|雷电|毒素|暗影)?伤害\s*\+?\s*(\d+)%").search(s)
		if m:
			# 「（最多8层，持续6秒），每层使目标…」——层数上限与时长一并带上
			var ms3 := _stack_max_from_text(s)
			var p3: String = "\"vuln\": %s" % _f(m.get_string(1))
			if ms3 > 0:
				p3 += ", \"max_stacks\": %d" % ms3
			var d3 := _duration_from_text(s)
			if d3 > 0.0:
				p3 += ", \"seconds\": %.4f" % d3
			return "[%d, \"judgement\", 1.0, 0.0, {%s}]" % [OP_TRIGGER_BUFF, p3]
	m = _re(r"(\d+)层时.*?必定暴击并造成\s*(\d+)%\s*伤害").search(s)
	if m:
		# 「N层时下一次攻击必定暴击并造成 M% 伤害」——**必暴与倍率都要带上**。
		# 旧版只出 `[Stat.CRD, 0.50]`（把「必定暴击」硬编码成暴伤 +50%）：
		# 既丢了「必暴」语义，也和规格的 200%/300% 倍率不符。
		#
		# 走与预言者王冠**同一套** `AT_FULL` 配对（靠共用的 `stat` 与叠层词条
		# 配对，`_fire_stack_full` → `_burst` → `_trigger_prophecy`）。
		# `stat` 用 `Stat.ATK`——格挡叠层的 stat 也是 ATK。
		return "[%d, %d, Stat.ATK, 1.0000, 0, 0, {\"burst\": \"prophecy\", \"crit_mult\": %.4f, \"spread_count\": 0, \"spread_layers\": 0}]" % [
			OP_STACK_GAIN, TRIG_AT_FULL, float(m.get_string(2)) / 100.0]
	m = _re(r"\d+层时.*?必定暴击").search(s)
	if m:
		# 没写倍率的写法——按 150% 落地
		return "[%d, %d, Stat.ATK, 1.0000, 0, 0, {\"burst\": \"prophecy\", \"crit_mult\": 1.5, \"spread_count\": 0, \"spread_layers\": 0}]" % [
			OP_STACK_GAIN, TRIG_AT_FULL]
	m = _re(r"\d+层时.*?获得吸收\s*(\d+)%\s*最大生命").search(s)
	if m:
		# 「获得吸收 N% 最大生命的护盾」——旧代码走 `elem_resist`
		#（元素抗性），与「护盾」毫无关系。走 `grant_shield` sentinel。
		return "[%d, \"grant_shield\", 1.0, 0.0, {\"pct\": %s, \"cap\": 0.60}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1))]

	# ---------- 8d. 命中 N 敌触发（2026-09-26，6 条）----------
	#
	# 形态：「<技能名>命中 N 个以上敌人时，伤害提升至 M%」。
	#
	# ## 为什么降级为「额外伤害」
	#
	# 计划书 §2 已决策：「条件变倍率」需要**回溯重算已结算的伤害**
	#（技能是逐个敌人独立结算的），代价高且手感突兀。
	# 改为「命中 ≥N 敌时追加一次范围伤害」——语义等价（都是"打中多个
	# 时伤害更高"），但实现干净。
	#
	# `multi_hit_bonus` 取超出 100% 的部分：规格的「提升至 700%」是
	# **倍率终值**，而追加伤害的倍率应是「额外多打多少」。
	#
	# **不能用 `M/100 - 1`**：M 可能**小于** 100（爆炸符文是「提升至50%」），
	# 那会算出负数并被 `maxf(...,0)` 夹成 0，效果整个消失。
	# 追加伤害直接取 `M/100`——语义是「额外再打 M% 攻击力」，
	# 与「提升至」的差值在数值上不等价，但**方向正确且不会归零**。
	# 这是计划书 §2「降级为额外伤害」决策的固有代价，已在文档标注。
	m = _re(r"命中\s*(\d+)\s*个以上敌人时[，,]?伤害提升至\s*(\d+)%").search(s)
	if m:
		var extra := maxf(float(m.get_string(2)) / 100.0, 0.0)
		return "[%d, {\"multi_hit_at\": %s, \"multi_hit_bonus\": %.4f}]" % [
			OP_SKILL_MOD, m.get_string(1), extra]
	# 「牵引 N 个以上敌人时，触发风爆（M% 攻击力风元素伤害）」
	m = _re(r"牵引\s*(\d+)\s*个以上敌人时[，,]?触发.*?(\d+)%\s*攻击力").search(s)
	if m:
		var extra2 := maxf(float(m.get_string(2)) / 100.0, 0.0)
		return "[%d, {\"multi_hit_at\": %s, \"multi_hit_bonus\": %.4f}]" % [
			OP_SKILL_MOD, m.get_string(1), extra2]

	# ---------- 8e. 技能附加效果（2026-09-26）----------
	#
	# 形态：「<技能名>同时 <效果>」——给某个**已有技能**附加额外效果。
	#
	# 这些是融合列词条，改的是**那个技能**的行为，不是给玩家加属性。
	# 走 `Operation.SKILL_MOD`，参数进 `trigger_params`——
	# **不能压成 `[4, trigger, ...]`**：那会变成「玩家某事件时获得属性」，
	# 与「改那个技能」完全是两回事。
	#
	# 判据：主串含「同时」+ 被修饰的技能名，且能做具体映射。
	if s.contains("战吼同时嘲讽敌人"):
		m = _re(r"嘲讽敌人\s*(\d+(?:\.\d+)?)\s*秒").search(s)
		var sec: String = m.get_string(1) if m else "1"
		return "[%d, {\"on_cast_buff\": \"taunt\", \"on_cast_seconds\": %s}]" % [OP_SKILL_MOD, sec]
	if s.contains("治愈术同时清除一个负面状态"):
		return "[%d, {\"on_cast_dispel\": 1}]" % OP_SKILL_MOD
	if s.contains("战吼同时降低敌人") :
		# 「战吼同时降低敌人 N% 攻击力，持续 M 秒」——数值与时长都要带上。
		#
		# **旧版有两个错**：
		#   ① id 写成 `atk_down`，而它**不是词条 id**（表里的降攻词条是
		#      `fatigue`）→ `BuffDefs.get_buff` 返回空 → `apply` 静默失败，
		#      **整条词条无效**
		#   ② 只取时长、没取数值 → 用表定的 20%，与规格的 30% 不符
		m = _re(r"战吼同时降低敌人\s*(\d+)%\s*攻击力[，,]?\s*持续\s*(\d+)\s*秒").search(s)
		if m:
			return "[%d, {\"on_cast_buff\": \"fatigue\", \"on_cast_seconds\": %s, \"on_cast_params\": {\"atk_down\": %.4f}}]" % [
				OP_SKILL_MOD, m.get_string(2), float(m.get_string(1)) / 100.0]
		m = _re(r"攻击力[，,]?持续\s*(\d+(?:\.\d+)?)\s*秒").search(s)
		if m:
			return "[%d, {\"on_cast_buff\": \"fatigue\", \"on_cast_seconds\": %s}]" % [OP_SKILL_MOD, m.get_string(1)]

	# ---------- 8f. 火焰路径 / 燃烧地面（2026-09-26）----------
	#
	# 「疾风步期间留下火焰路径」——冲刺/疾风步期间移动时周期性留下
	# 火焰区域。「留下燃烧地面」是同类（火系技能命中后原地留区域）。
	#
	# **数值一律从原文取，不硬编码**。实测规格里的写法：
	#   疾风步期间留下火焰路径                      → 无伤害
	#   疾风步期间留下火焰路径（每秒40%攻击力）      → 0.40
	#   疾风步期间留下火焰路径，对经过敌人造成30%攻击力伤害 → 0.30
	#   火焰吐息留下燃烧地面（每秒40%法强，持续3秒） → 0.40 / 3s
	#   火焰喷射留下燃烧地面（每秒20%法强，持续2秒） → 0.20 / 2s
	#   流星火雨留下燃烧地面（每秒80%法强，持续5秒） → 0.80 / 5s
	#
	# 早期版本把后三条硬编码成 3.0/0.30——**那是臆断**，三条不同数值的
	# 词条会变成一字不差。故这里逐项抽数值。
	if s.contains("留下火焰路径") or s.contains("留下燃烧地面"):
		# 百分比：优先「每秒N%」，其次任意「N%」
		var fp_mult := "0.0"
		m = _re(r"每秒\s*(\d+(?:\.\d+)?)%").search(s)
		if m == null:
			m = _re(r"(\d+(?:\.\d+)?)%").search(s)
		if m:
			fp_mult = "%.4f" % (float(m.get_string(1)) / 100.0)
		# 持续秒数：原文给了就用，没给取 3.0（区域默认时长）
		var fp_sec := "3.0"
		m = _re(r"持续\s*(\d+(?:\.\d+)?)\s*秒").search(s)
		if m:
			fp_sec = m.get_string(1)
		return "[%d, {\"fire_path_seconds\": %s, \"fire_path_mult\": %s}]" % [
			OP_SKILL_MOD, fp_sec, fp_mult]

	# ---------- 8g. 低难度杂项族（2026-09-27，5 条）----------
	#
	# 这五条各自独立，但都属于「机制基础设施已有、只差接线」。
	# 逐条从原文抽数值，不硬编码。

	# ① 站立静止（「站立不动1秒后获得"大地守护"（+20%减伤，+10%反伤），移动后失效」）
	#
	# **走 `OP_TRIGGER_BUFF` 而不是 `SKILL_MOD`**：这是**玩家状态**
	#（站够时间给自己挂 buff），不是「改某个技能」。早期版本误用了
	# SKILL_MOD——那需要「来源装备提供技能」才生效，而大地守护这件
	# 装备本身不带技能，会永远取不到。
	#
	# `Trigger.STATIONARY`(12) 早就存在但**零消费**，这里是它的第一个真实用途。
	if s.contains("站立不动") and s.contains("获得"):
		var dr := "0.0"
		var refl := "0.0"
		m = _re(r"\+?(\d+(?:\.\d+)?)%\s*减伤").search(s)
		if m:
			dr = _f(m.get_string(1))
		m = _re(r"\+?(\d+(?:\.\d+)?)%\s*反伤").search(s)
		if m:
			refl = _f(m.get_string(1))
		var secs := "1.0"
		m = _re(r"站立不动\s*(\d+(?:\.\d+)?)\s*秒").search(s)
		if m:
			secs = m.get_string(1)
		# 「获得一个吸收 N% 最大生命的**护盾**」——此前只取减伤/反伤两个槽，
		# 护盾量整个丢失（不动堡垒「站立2秒得30%最大生命护盾」）
		var sh := "0.0"
		m = _re(r"吸收\s*(\d+(?:\.\d+)?)%\s*最大生命的?护盾").search(s)
		if m:
			sh = _f(m.get_string(1))
		return "[%d, \"stationary_buff\", 1.0, 0.0, {\"stationary_seconds\": %s, \"dr_pct\": %s, \"reflect_pct\": %s, \"shield_pct\": %s}]" % [
			OP_TRIGGER_BUFF, secs, dr, refl, sh]

	# ② 印记扩散（「印记目标死亡时，印记扩散至周围2名敌人」）
	if s.contains("印记目标死亡时") and s.contains("扩散"):
		m = _re(r"扩散至周围\s*(\d+)\s*名敌人").search(s)
		var cnt: String = m.get_string(1) if m else "2"
		return "[%d, \"spread_mark\", 1.0, 0.0, {\"count\": %s}]" % [OP_TRIGGER_BUFF, cnt]

	# ③ 召唤物死亡爆炸（「护卫死亡时爆炸，造成50%法强伤害」）
	#
	# ## 两处此前不对
	#
	# ① 正则要求「造成」二字，而「守卫死亡时爆炸（80%法强）」是**括号写法**
	#    ——匹配不到就一律回落成 0.5，实测 6 条里 2 条倍率错。
	# ② **没区分法强/攻击力**：规格里两者都有
	#    （守卫「80%法强」vs 分身「60%攻击力」），旧版全按法强算。
	#    用户 2026-09-28 决策「按原文区分」，故把 `by` 一并存下来。
	if s.contains("死亡时爆炸"):
		m = _re(r"(\d+(?:\.\d+)?)%\s*(法强|法术强度|攻击力)").search(s)
		var mult: String = _f(m.get_string(1)) if m else "0.5"
		var by: String = "atk" if (m and m.get_string(2) == "攻击力") else "ap"
		return "[%d, \"summon_death_boom\", 1.0, 0.0, {\"mult\": %s, \"by\": \"%s\"}]" % [
			OP_TRIGGER_BUFF, mult, by]

	# ④ 周期伤害光环（「周围3米敌人每秒受到15%攻击力伤害」）
	#
	# **同样不是技能**——它是**常驻光环**（装备穿着即生效），
	# 由 `PlayerEquipmentEffects.tick` 每帧推进。故走 TRIGGER_BUFF sentinel，
	# 不走 SKILL_MOD（后者需要「本装备提供技能」才生效）。
	if s.contains("每秒受到") and s.contains("攻击力伤害"):
		m = _re(r"周围\s*(\d+(?:\.\d+)?)\s*米").search(s)
		var rad: String = m.get_string(1) if m else "3.0"
		m = _re(r"每秒受到\s*(\d+(?:\.\d+)?)%\s*攻击力").search(s)
		var am: String = _f(m.get_string(1)) if m else "0.15"
		return "[%d, \"aura_damage\", 1.0, 0.0, {\"aura_radius\": %s, \"aura_mult\": %s, \"aura_interval\": 1.0}]" % [
			OP_TRIGGER_BUFF, rad, am]

	# ⑤ 资源满时下次攻击释放冲击波（「资源满时，下次攻击释放资源冲击波（100%攻击力）」）
	if s.contains("资源满时") and s.contains("下次攻击"):
		m = _re(r"释放.*?(\d+(?:\.\d+)?)%\s*攻击力").search(s)
		var sw: String = _f(m.get_string(1)) if m else "1.0"
		return "[%d, \"res_shockwave\", 1.0, 0.0, {\"mult\": %s}]" % [OP_TRIGGER_BUFF, sw]

	# ---------- 8h. 能量储存（2026-09-27，3 条 / 1 件装备）----------
	#
	# 「伤害储存护符」的**跨列单一机制**：
	#   自有列：受到伤害的20%储存为"能量"（最多储存100%最大生命）；下次攻击释放全部
	#   融合列：释放储存能量时，对周围造成50%范围伤害
	#
	# 三行各自是**同一机制的一个参数**，故三个分支都产出**同一条** sentinel，
	# 由 `PlayerEquipmentEffects` 用 `merge` 语义合并（后者覆盖前者，
	# 但都来自同一件装备，不会互相覆盖参数）。
	#
	# ## 为什么走 sentinel 而不是 SKILL_MOD
	#
	# 它是**玩家侧状态**（受击攒能量、下次攻击释放），不是「改某个技能」。
	# 走 SKILL_MOD 需要「本装备提供技能」才生效，而伤害储存护符没有技能。
	if s.contains("储存为") and s.contains("能量"):
		m = _re(r"受到伤害的\s*(\d+(?:\.\d+)?)%\s*储存").search(s)
		var store_pct: String = _f(m.get_string(1)) if m else "0.20"
		# 上限：「最多储存100%最大生命」
		var cap: String = "1.0"
		m = _re(r"最多储存\s*(\d+(?:\.\d+)?)%").search(s)
		if m:
			cap = _f(m.get_string(1))
		return "[%d, \"energy_store\", 1.0, 0.0, {\"store_pct\": %s, \"cap_pct\": %s}]" % [
			OP_TRIGGER_BUFF, store_pct, cap]
	if s.contains("下次攻击释放全部储存能量"):
		# 参数由上面那条提供，这里只标记「释放」行为存在
		return "[%d, \"energy_store\", 1.0, 0.0, {\"release\": true}]" % OP_TRIGGER_BUFF
	if s.contains("释放储存能量") and s.contains("范围伤害"):
		m = _re(r"对周围造成\s*(\d+(?:\.\d+)?)%\s*范围伤害").search(s)
		var splash: String = _f(m.get_string(1)) if m else "0.50"
		return "[%d, \"energy_store\", 1.0, 0.0, {\"splash_pct\": %s}]" % [
			OP_TRIGGER_BUFF, splash]

	# ---------- 8i. 元素序列 / 终焉（2026-09-27，6 条）----------
	#
	# 这一族需要一个**元素序列追踪器**：记录最近几次攻击用的元素与目标，
	# 才能判定「连续3次**不同**元素」「连续攻击**同一目标**3次」。
	#
	# 追踪器落在 `Player._elem_sequence`（环形缓冲）+ `_last_hit_target`。
	# 三条词条各自声明判定条件，由 `_check_elem_sequence` 结算。

	# ① 连续 N 次不同元素 → 元素爆炸（「连续3次不同元素后，触发元素爆炸（150%法强）」）
	if s.contains("不同元素") and s.contains("元素爆炸"):
		m = _re(r"连续\s*(\d+)\s*次不同元素").search(s)
		var n1: String = m.get_string(1) if m else "3"
		m = _re(r"元素爆炸[（(]\s*(\d+(?:\.\d+)?)%\s*法强").search(s)
		var m1: String = _f(m.get_string(1)) if m else "1.5"
		return "[%d, \"elem_seq_distinct\", 1.0, 0.0, {\"count\": %s, \"mult\": %s, \"use_ap\": true}]" % [
			OP_TRIGGER_BUFF, n1, m1]
	# ② 连续攻击同一目标 N 次 → 元素爆炸（「连续攻击同一目标3次后，触发元素爆炸（150%攻击力）」）
	if s.contains("同一目标") and s.contains("元素爆炸"):
		m = _re(r"连续攻击同一目标\s*(\d+)\s*次").search(s)
		var n2: String = m.get_string(1) if m else "3"
		m = _re(r"元素爆炸[（(]\s*(\d+(?:\.\d+)?)%\s*攻击力").search(s)
		var m2: String = _f(m.get_string(1)) if m else "1.5"
		return "[%d, \"elem_seq_same_target\", 1.0, 0.0, {\"count\": %s, \"mult\": %s}]" % [
			OP_TRIGGER_BUFF, n2, m2]
	# ③ 使用不同元素技能 → 下一技能增伤（「使用不同元素技能时，下一个技能伤害+25%并附带对应元素状态」）
	if s.contains("使用不同元素技能时"):
		m = _re(r"下一个技能伤害\s*\+\s*(\d+(?:\.\d+)?)%").search(s)
		var p3: String = _f(m.get_string(1)) if m else "0.25"
		return "[%d, \"elem_next_skill\", 1.0, 0.0, {\"bonus_pct\": %s}]" % [OP_TRIGGER_BUFF, p3]
	# ④ 六种状态同时存在 → 元素终焉（「造成600%法强全元素伤害并清空所有状态」）
	if s.contains("六种状态同时存在时"):
		m = _re(r"造成\s*(\d+(?:\.\d+)?)%\s*法强").search(s)
		var m4: String = _f(m.get_string(1)) if m else "6.0"
		return "[%d, \"elem_finale\", 1.0, 0.0, {\"mult\": %s, \"clear\": true}]" % [OP_TRIGGER_BUFF, m4]
	# ⑤ 终焉触发后重新施加（「元素终焉触发后，六种状态重新施加且持续时间刷新」）
	if s.contains("元素终焉触发后"):
		return "[%d, \"elem_finale_refresh\", 1.0, 0.0, {\"refresh\": true}]" % OP_TRIGGER_BUFF
	# ⑥ 技能自动轮转六元素（「技能自动轮转六元素；每种元素对敌人施加独立状态」）
	if s.contains("自动轮转六元素"):
		return "[%d, \"elem_rotate\", 1.0, 0.0, {\"rotate\": true}]" % OP_TRIGGER_BUFF

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
		# ③ 全属性（**展开成各主属性**，见 `_all_stats_spec`）
		if nm.contains("全属性") or nm.contains("所有基础属性"):
			return _all_stats_spec(v)
		# ④ 职业资源 / 资源回复
		if nm.contains("职业资源") or nm.contains("资源回复"):
			return "[%d, %.4f, true]" % [SP["exp_gain"], v]
		# ⑤ 时长类
		if nm.contains("增益效果持续时间"):
			return "[%d, %.4f, true]" % [SP["debuff_dur"], v]
		if nm.contains("技能冷却缩减"):
			return "[Stat.CDR, %.4f, true]" % v
		# ⑥ 减伤 / 增伤
		#
		# **必须先判「受到伤害」**：`nm.contains("伤害")` 会把它一起吞掉，
		# 于是「受到伤害叠加1层…每层+3%减伤」里的「受到伤害」被当成增伤
		# 关键词，整条落到 `elem_dmg`（**玩家自己的伤害 +3%**）。
		# 那是**方向完全反了**：原文说的是「每层减伤 3%」。
		#
		# 实测 3 条同类：不朽壁垒 / 不灭壁垒 / 减伤叠层胸甲。
		if nm.contains("受到伤害") or nm.contains("承受伤害") or nm.contains("受到的元素伤害"):
			return "[%d, %.4f, true]" % [SP["dmg_reduction"], v]
		if nm.contains("反伤") or nm.contains("反弹"):
			return "[%d, %.4f, true]" % [SP["reflect"], v]
		if nm.contains("减伤"):
			return "[%d, %.4f, true]" % [SP["dmg_reduction"], v]
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

	# ---------- 9b. 免死机制（2026-09-27，2 条）----------
	#
	# **必须在第 10 节（满层触发）之前**：否则「满层时受到致命伤害触发
	# 不朽壁垒…并回复30%最大生命」会被第 10 节的 `满层时.*?\d+%最大生命`
	# 抢先匹配成 `[4, AT_FULL, Stat.HP, 0.30]`——那是「叠满时回血」，
	# 与「免死」完全两回事，且「层数×80%攻击力范围伤害」整个丢失。
	#
	# 判据必须含「致命伤害」——只说「满层时回复」的不是免死。
	if s.contains("致命伤害"):
		# 回血比例
		var cd_heal := "0.5"
		m = _re(r"回复\s*(\d+(?:\.\d+)?)%\s*最大生命").search(s)
		if m:
			cd_heal = _f(m.get_string(1))
		# 范围反击：不朽壁垒的「（层数×80%）攻击力」
		#
		# 原文用**中文全角括号**包裹：「对周围造成（层数×80%）攻击力伤害」。
		# 正则要容忍括号与百分号的各种位置，故用宽松的 `.*?` 连接。
		var cd_boom := "0.0"
		m = _re(r"层数\s*[×xX*]\s*(\d+(?:\.\d+)?)\s*%").search(s)
		if m:
			cd_boom = _f(m.get_string(1))
		# 冷却
		var cd_cd := "120.0"
		m = _re(r"冷却\s*(\d+(?:\.\d+)?)\s*秒").search(s)
		if m:
			cd_cd = m.get_string(1)
		return "[%d, \"cheat_death\", 1.0, 0.0, {\"heal_pct\": %s, \"boom_pct\": %s, \"cooldown\": %s}]" % [
			OP_TRIGGER_BUFF, cd_heal, cd_boom, cd_cd]
	# **免死后效果已在第 0a 节统一处理**（那里必须最前，否则会被减伤规则截胡）

	# 「释放终极技能时消耗所有灵魂，每层额外造成20%伤害」——
	# 这是**技能修饰**（改终极技能=形态4技能的行为），不是玩家属性。
	# 走 `SKILL_MOD`，参数由 `SkillSystem._skill_mods_for` 并入 `sd`。
	#
	# **必须排除「返还层数」**：「终极技能消耗灵魂后，返还50%层数」也含
	# 「终极技能」+「灵魂」，但它修饰的是**层数处理**（已有 `soul_refund`
	# sentinel 承载），不是伤害倍率。不加这条排除会把它抢走——
	# 实测导致 `soul_refund` 从数据里消失（既有测试立刻抓到）。
	if s.contains("终极技能") and s.contains("灵魂") and s.contains("每层"):
		m = _re(r"每层额外造成\s*(\d+(?:\.\d+)?)%\s*伤害").search(s)
		if m == null:
			m = _re(r"每层\s*\+?\s*(\d+(?:\.\d+)?)%\s*伤害").search(s)
		var per: String = _f(m.get_string(1)) if m else "0.20"
		return "[%d, {\"ultimate_soul_per_stack\": %s}]" % [OP_SKILL_MOD, per]

	# ---------- 9c. B5 三族（2026-09-27，7 条）----------
	#
	# ## 友方链接（3 条）
	#
	# 规格：「链接期间**自身**获得 N% 减伤」——注意是**自身**。
	# 故这是「链接技能给自己加减伤」，走 `SKILL_MOD` 的 `dr_pct`，
	# 由已有的 `_apply_extra_self_buffs`（`skill_system.gd:493` 读 `dr_pct`）
	# 消费——**零代码改动**，只需要把数值接上。
	#
	# 技能本身已在 `EquipmentSkills` 里声明了 `link_ally`/`link_share_pct`
	#（但引擎零消费，本作单人无队友）——那部分不在本轮范围。
	m = _re(r"链接期间自身获得\s*(\d+(?:\.\d+)?)%\s*减伤").search(s)
	if m:
		return "[%d, {\"dr_pct\": %s}]" % [OP_SKILL_MOD, _f(m.get_string(1))]

	# ## 陷阱（3 条）
	#
	# 项目**没有玩家侧陷阱系统**（`DamageZone` 有「陷阱型」注释，
	# 但只有 1 条陷阱技能：冰霜陷阱长弓）。故这三条做成**数据通道**——
	# `trap_resist_pct` / `trap_immune_pct` 挂上，等陷阱机制实现时直接生效。
	# 「显示附近陷阱（小地图）」是 UI 功能，不做（标注为 UI 项）。
	m = _re(r"陷阱伤害减少\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["trap_dmg"], _f(m.get_string(1))]
	# **注意两段式切分**：「触发陷阱时，有20%概率免疫伤害」的从句
	#（「触发陷阱时，」）被 `_split_clause` 切走，主句只剩「有20%概率免疫伤害」。
	#
	# 但两段式的「主句回退」路径实测**没有走到**（主句单独调 `_parse_main`
	# 成功、完整句的回退却返回空）。故这里直接**容忍前置从句**——
	# 正则从任意「，」之后开始匹配，第 ① 步（完整文本）就能命中，
	# 不依赖回退路径是否生效。
	m = _re(r"(?:^|[，,])\s*有\s*(\d+(?:\.\d+)?)%\s*概率免疫伤害").search(s)
	if m:
		return "[%d, %s, true]" % [SP["dodge"], _f(m.get_string(1))]
	if s.contains("显示附近陷阱"):
		_skill_notes += 1   # UI 功能，不属于词条层级
		return "__SKILL__"

	# ## 束缚箭（1 条）
	#
	# 「束缚箭命中后，目标防御降低20%，持续5秒」——这是**技能修饰**：
	# 巨兽猎手的自有列「攻击有6%概率发射束缚箭，使目标无法移动1.5秒」
	# 已经产出了 entangle 触发；本条是给**被束缚的目标**再降防。
	# 走 `SKILL_MOD` 的 `on_hit_debuff`，由 `_skill_mods_for` 并入该技能。
	if s.contains("束缚箭命中后") and s.contains("防御降低"):
		m = _re(r"防御降低\s*(\d+(?:\.\d+)?)%[，,]?\s*持续\s*(\d+(?:\.\d+)?)\s*秒").search(s)
		var ar := "0.20"
		var ad := "5.0"
		if m:
			ar = _f(m.get_string(1))
			ad = m.get_string(2)
		return "[%d, {\"armor_reduce\": %s, \"armor_reduce_seconds\": %s}]" % [OP_SKILL_MOD, ar, ad]

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
	# 混沌之门融合列：「混沌之门触发时，额外释放一次随机效果（50%效果）」
	#
	# 这是**改混沌之门这个技能**（多放一次、效果打折），不是给玩家挂属性，
	# 故必须走 `SKILL_MOD`。压成 `[4, trigger, ...]` 会变成
	# 「玩家某事件时获得属性」，语义完全不对。
	#
	# 折扣数值从文本取（「（50%效果）」→ 0.5），缺省 0.5。
	m = _re(r"额外释放一次随机效果[（(]\s*(\d+)%\s*效果").search(s)
	if m:
		return "[%d, {\"chaos_times\": 2, \"chaos_scale\": %.4f}]" % [
			OP_SKILL_MOD, float(m.get_string(1)) / 100.0]
	if s.contains("额外释放一次随机效果"):
		return "[%d, {\"chaos_times\": 2, \"chaos_scale\": 0.5000}]" % OP_SKILL_MOD

	# ---------- 12. 资源型（记忆残渣 / 钥匙碎片 / 金币持有量） ----------
	m = _re(r"每点记忆残渣.*?攻击力提高\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"每点记忆残渣\s*\+?(\d+(?:\.\d+)?)%\s*全属性").search(s)
	if m:
		return _all_stats_spec(float(m.get_string(1)) / 100.0)
	m = _re(r"每持有?一片钥匙碎片.*?全属性提高\s*(\d+)%").search(s)
	if m:
		return _all_stats_spec(float(m.get_string(1)) / 100.0)
	m = _re(r"每持有?一片钥匙碎片，\s*\+?(\d+)%\s*全属性").search(s)
	if m:
		return _all_stats_spec(float(m.get_string(1)) / 100.0)
	m = _re(r"每(?:持有)?\s*100\s*金币.*?攻击力提高\s*(\d+(?:\.\d+)?)%").search(s)
	if m:
		return "[Stat.ATK, %s, true]" % _f(m.get_string(1))
	m = _re(r"每持有\s*100\s*金币，\s*\+?(\d+)%\s*攻击力").search(s)
	if m:
		# 「每持有 100 金币，+N% 攻击力（最多 +M%）」——按档位缩放，
		# 旧版产出永久 \`[Stat.ATK, v]\`，满血/无金币也拿全额。
		var cap2 := _cap_from_text(s)
		return "[%d, \"state_scaled\", 1.0, 0.0, {\"per_gold\": 100.0, \"gold_atk\": %.4f, \"gold_max_pct\": %.4f}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0, cap2]
	m = _re(r"每装备一件(?:传奇|红色)装备.*?全属性提高\s*(\d+)%").search(s)
	if m:
		return _all_stats_spec(float(m.get_string(1)) / 100.0)
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
		# 「召唤物存在时，自身攻击力提高 N%」——这是**自身攻击**，
		# 不是「召唤物伤害」。旧版错走 `elem_resist`（元素抗性），
		# 与描述毫不相干；且数值硬编码 0.05，与原文的 25% 差 5 倍。
		#
		# 正确的规则在第 40 节（`召唤物存在时…自身攻击力提高`），这里
		# **不再兜底**——兜底会让它先被这一条吃掉。
		pass

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
		# 「减伤」= 全局减伤（不是元素抗性），同第 5 节的口径
		return "[%d, %s, true]" % [SP["dmg_reduction"], _f(m.get_string(1))]
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
	m = _re(r"每损失\s*([1-9]\d*)%\s*生命，?攻击力提高\s*(\d+)%").search(s)
	if m:
		# 「每损失 X% 生命，攻击力提高 N%」——**每 X% 加一档**。
		# 「每…，…」在中文里就是「for every …」，且这件装备的
		# 体系方向是「生命消耗·吸血循环流」：越受伤越强才有意义。
		# 旧版产出永久 `[Stat.ATK, v]`——满血也拿全额，分档整个丢失。
		return "[%d, \"state_scaled\", 1.0, 0.0, {\"per_hp_loss_pct\": %s, \"per_hp_atk\": %.4f}]" % [
			OP_TRIGGER_BUFF, m.get_string(1), float(m.get_string(2)) / 100.0]
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
		# 「攻击施加"猎杀标记"（最多5层），每层+3%暴击率」——
		# 机制是**给目标挂标记**，玩家自己拿的是标记带来的**对自己**增益
		# （暴击率）。层数上限必须带上，否则退化成 `BuffDefs` 表定值。
		var ms := _stack_max_from_text(s)
		var ex := "" if ms <= 0 else ", {\"max_stacks\": %d}" % ms
		return "[%d, \"mark\", 1.0, 0.0%s]" % [OP_TRIGGER_BUFF, ex]
	# 「攻击施加"猎神标记"…每层+5%受到伤害」——这是给**目标**的易伤，
	# 不是自己的处决线。见下方 `target_vuln` 规则的说明。
	m = _re(r"攻击施加.*?每层\s*\+?(\d+)%\s*受到伤害").search(s)
	if m:
		var ms2 := _stack_max_from_text(s)
		var ms_slot := "" if ms2 <= 0 else ", \"max_stacks\": %d" % ms2
		return "[%d, \"target_vuln\", 1.0, 0.0, {\"pct\": %s, \"per_stack\": true%s}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1)), ms_slot]
	m = _re(r"暴击时减少所有技能冷却\s*(\d+)\s*秒").search(s)
	if m:
		# 「暴击时减少所有技能冷却 N 秒」——旧版硬编码成 `[Stat.CDR, 0.20]`，
		# 那是「冷却缩减 +20%」的**被动**属性，与「暴击时立刻各减 N 秒」
		# 完全两回事（触发时机、数值量纲都不同）。
		# 现走 `SKILL_MOD` 的普攻/暴击通道，由 `_apply_trigger_affixes`
		# 在暴击分支里调 `SkillSystem.reduce_cooldowns(N)`。
		return "[%d, {\"crit_reduce_cooldown_seconds\": %s}]" % [
			OP_SKILL_MOD, m.get_string(1)]
	m = _re(r"护盾值\s*\+?\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["shield_power"], _f(m.get_string(1))]
	m = _re(r"吸血提高至\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["lifesteal"], _f(m.get_string(1))]
	m = _re(r"处决阈值提升至\s*(\d+)%").search(s)
	if m:
		# **这是「阈值」不是「增伤」**：旧版写进 `execute_line`（增伤通道），
		# 于是「处决阈值提升至40%」变成「增伤 +40%」——完全不搭边。
		return "[%d, %s, true]" % [SP["execute_threshold"], _f(m.get_string(1))]
	m = _re(r"对满血敌人伤害提升至\s*(\d+)%").search(s)
	if m:
		return "[[%d, %s, true], [%d, 100.00, true]]" % [SP["execute_line"],
			_f(m.get_string(1)), SP["execute_threshold"]]
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
		return "[%d, %s, true]" % [SP["cd_refresh_crit"], _f(m.get_string(1))]

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
	if s.contains("自身生命低于50%时效果翻倍"):
		return "[%d, %s, true]" % [SP["lifesteal"], _f("10")]
	# 「生命满时，回复(量)转化为护盾（最多 N% 最大生命）」——生命之树
	#
	# 旧版映射成 `elem_resist +10%`（元素抗性！）——**通道完全错**，
	# 且「最多 N% 最大生命」这个上限也丢了。现走 `grant_shield`，
	# `pct` 是护盾量、`cap` 是上限（`PlayerEquipmentEffects._grant_shield` 消费）。
	if s.contains("生命满时") and s.contains("转化为护盾"):
		var cap := "0.20"
		m = _re(r"最多\s*(\d+)%\s*最大生命").search(s)
		if m:
			cap = _f(m.get_string(1))
		# 「回复转化」的语义是「**这次治疗量**转成护盾」，
		# 但 `HP_FULL` 触发时治已经结算完、拿不到那个量。
		# 故按「满血时给一份等于上限的护盾」落地——与规格的观感一致
		#（满血时每次治疗都补一层盾，上限封顶）。
		return "[%d, \"grant_shield\", 1.0, 0.0, {\"pct\": %s, \"cap\": %s}]" % [
			OP_TRIGGER_BUFF, cap, cap]
	m = _re(r"治疗时额外获得治疗量\s*(\d+)%\s*的护盾").search(s)
	if m:
		# 「治疗时给予治疗量 N% 的护盾（最多 M% 最大生命）」——圣光护符。
		# 同样**旧版错挂成 `elem_resist`**。治疗量在 `on_heal` 时拿不到
		#（回调只通知"治疗发生"，不带数值），故按上限给一份。
		var cap2 := "0.15"
		var mc := _re(r"最多\s*(\d+)%\s*最大生命").search(s)
		if mc:
			cap2 = _f(mc.get_string(1))
		var ratio := _f(m.get_string(1))
		return "[%d, \"grant_shield\", 1.0, 0.0, {\"pct\": %s, \"cap\": %s, \"of_heal_ratio\": %s}]" % [
			OP_TRIGGER_BUFF, cap2, cap2, ratio]
	m = _re(r"受到伤害的\s*(\d+)%\s*延迟").search(s)
	if m:
		# 「受到伤害的 N% 延迟至5秒内逐渐结算」——旧版错映射成
		# `elem_resist`（元素抗性），与「延迟结算」毫无关系。
		return "[%d, %s, true]" % [SP["delay_dmg"], _f(m.get_string(1))]
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
		return "[%d, 1.0, true]" % SP["cd_refresh_dodge"]
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
	m = _re(r"隐身期间移速\s*\+?\s*(\d+)%").search(s)
	if m:
		# 旧版硬编码 0.20：「隐身期间移速+15%」拿到 20%（与规格不符）
		return "[Stat.SPD, %s, true]" % _f(m.get_string(1))
	m = _re(r"闪现后下次攻击\s*\+?\s*(\d+)%\s*伤害").search(s)
	if m:
		return "[%d, %d, Stat.ATK, %s, 0]" % [OP_STACK_GAIN, TRIG_ON_HIT, _f(m.get_string(1))]
	m = _re(r"冲锋后获得\s*\d*\s*秒?\s*(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %s, true]" % [SP["dmg_reduction"], _f(m.get_string(1))]
	m = _re(r"驱散成功后获得\s*\d+\s*秒\s*(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %s, true]" % [SP["dmg_reduction"], _f(m.get_string(1))]
	if s.contains("净化后获得3秒霸体"):
		return "[%d, %s, true]" % [SP["ctrl_resist"], _f("50")]
	m = _re(r"沉默箭命中后目标移速\s*-\s*(\d+)%").search(s)
	if m:
		# **量级必须带上**：`slow` 词条表定只有 0.25，
		# 不带覆盖的话「-20%」和「-30%」拿到的是同一个值。
		return "[%d, \"slow\", 1.0, 3.0, {\"slow\": %s}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1))]
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
		# **「范围扩大」改的是技能几何，不是属性**。旧版写死
		# `elem_dmg +10%` —— 把范围类词条全变成元素增伤（数值也丢了）。
		# 走 `SKILL_MOD` 的 `radius_mult`，由 `SkillSystem` 并入 sd 时放大 radius。
		return "[%d, {\"radius_mult\": %.4f}]" % [OP_SKILL_MOD,
			1.0 + float(m.get_string(1)) / 100.0]
	if s.contains("复仇满层时，背刺必定暴击") or s.contains("背刺消耗所有层数"):
		return "[Stat.CRD, 0.30, true]"
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
	# 「生命低于50%时进入"血海狂暴"——攻击+40%、攻速+30%、吸血+25%…」
	# 已在 `_parse_main` 开头的**低血多属性**规则里展开成 3 条，
	# 走到这里说明写法不同——保留旧行为避免整条丢失。
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
		# **`N%` 是概率，不是召唤物增伤**——旧版产出 `summon_dmg +0.10`，
		# 等于把「10% 概率多打一下」变成了「召唤物伤害永久 +10%」，
		# 语义完全不对（前者爆发、后者稳定）。
		#
		# 走玩家身上的**同一份概率攻击规则**（`attack_bonus`）——
		# 召唤物攻击时从 `owner_player._attack_bonus_rule` 读，
		# 这样「作用于玩家全部召唤物」天然成立（用户 2026-09-27 决策）。
		return "[%d, \"attack_bonus\", 1.0, 0.0, {\"summon_extra_chance\": %.4f}]" % [
			OP_TRIGGER_BUFF, float(m.get_string(1)) / 100.0]
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
	#
	# ## 这里此前丢了**三个**东西（用户 2026-09-28 决策后修）
	#
	# 原文「攻击有8%概率使目标中毒，每秒造成5%攻击力伤害，持续3秒」，
	# 旧规则产出 `[2, "poison_rot", 0.08, 3.0]`：
	#   · 时长写死 3.0（「持续2秒」的冻结之息也落成 3.0）
	#   · **伤害量 5% 整个丢失**（DOT 退化成 `poison_rot` 表定的法强×0.03）
	#   · **倍率口径丢失**（规格说「攻击力」，表定是「法强」）
	#
	# ## 为什么要合并基础参数
	#
	# `BuffHolder.params_of_active` 的覆盖是**整体替换**，不是逐键合并。
	# 故给 `poison_rot` 只传 `{dot_atk: …}` 会把它的 `vuln: 0.01` 一起抹掉
	#（毒蚀的全局易伤是该词条的核心之一）。故这里**显式带上**基础键。
	#
	# 形态：「攻击有P%概率使目标<效果>，每秒造成N%<攻击力|法强>伤害，持续D秒」
	m = _re(r"攻击有\s*(\d+)%\s*概率使目标(中毒|减速|燃烧)\s*[，,]?\s*每秒造成\s*(\d+(?:\.\d+)?)%\s*(攻击力|法强)伤害\s*[，,]?\s*持续\s*(\d+(?:\.\d+)?)\s*秒").search(s)
	if m:
		var eff := m.get_string(2)
		var bid := "poison_rot" if eff == "中毒" else ("slow" if eff == "减速" else "burn")
		var amt := _f(m.get_string(3))
		var byt := m.get_string(4)
		var dur := m.get_string(5)
		var dmg_key := "dot_atk" if byt == "攻击力" else "dot_pct"
		# 毒蚀的全局易伤要显式带上（见上面的说明）
		var base := ", \"vuln\": 0.0100" if bid == "poison_rot" else ""
		return "[%d, \"%s\", %s, %s, {\"%s\": %s%s}]" % [
			OP_TRIGGER_BUFF, bid, _f(m.get_string(1)), dur, dmg_key, amt, base]
	# 形态：「攻击有P%概率使目标减速N%，持续D秒」（只有量、没有 DOT）
	m = _re(r"攻击有\s*(\d+)%\s*概率使目标减速\s*(\d+(?:\.\d+)?)%\s*[，,]?\s*持续\s*(\d+(?:\.\d+)?)\s*秒").search(s)
	if m:
		return "[%d, \"slow\", %s, %s, {\"slow\": %s}]" % [
			OP_TRIGGER_BUFF, _f(m.get_string(1)), m.get_string(3), _f(m.get_string(2))]
	# 兜底（原文没给量级/时长时保持旧行为，避免把没写全的条目弄丢）
	m = _re(r"攻击有\s*(\d+)%\s*概率使目标(中毒|减速|燃烧|攻击力降低)").search(s)
	if m:
		var eff2 := m.get_string(2)
		var bid2 := "poison_rot" if eff2 == "中毒" else ("slow" if eff2 == "减速" else ("burn" if eff2 == "燃烧" else "fatigue"))
		var md0 := _re(r"持续\s*(\d+(?:\.\d+)?)\s*秒").search(s)
		var d0 := "3.0" if md0 == null else md0.get_string(1)
		return "[%d, \"%s\", %s, %s]" % [OP_TRIGGER_BUFF, bid2, _f(m.get_string(1)), d0]
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
		return "[%d, %s, true]" % [SP["cd_refresh_crit"], _f(m.get_string(1))]
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
		return "[%d, %s, true]" % [SP["dmg_reduction"], _f(m.get_string(1))]
	m = _re(r"生命值?低于\s*\d+%\s*时，额外获得\s*(\d+)%\s*减伤").search(s)
	if m:
		return "[%d, %s, true]" % [SP["dmg_reduction"], _f(m.get_string(1))]
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
	#
	# **`触发免死后` 已从本条移除**：免死由第 9b 节专门处理（那里产出
	# `cheat_death` sentinel）。留在这里会被误映射成 `dodge +50%`——
	# 「免死后获得无敌」与「闪避率 +50%」是两回事。
	#
	# 剩下的是「获得 N 秒无敌」类——那种确实该给高闪避（无敌的近似）。
	if s.contains("击杀敌人后获得") and s.contains("秒无敌") \
			or s.contains("触发后获得") and s.contains("秒无敌") \
			or s.contains("守护满层时") and s.contains("无敌"):
		return "[%d, %s, true]" % [SP["dodge"], _f("50")]

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
		# 规格有两个数：**转化比例 50%** + **吸收上限 30% 最大生命**。
		# 拆成两条——旧版把上限当成转化比例、还错走 `elem_resist`。
		return "[[%d, 0.5000, true], [%d, 0.3000, true]]" % [
			SP["dmg_to_shield"], SP["dmg_to_shield_cap"]]
	if s.contains("转化比例提升至"):
		return "[[%d, 0.7000, true], [%d, 0.3000, true]]" % [
			SP["dmg_to_shield"], SP["dmg_to_shield_cap"]]
	m = _re(r"每击杀\s*(\d+)\s*个敌人，获得一个随机增益").search(s)
	if m:
		return "[%d, %d, Stat.ATK, 0.15, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL]
	if s.contains("传奇共鸣触发时"):
		return _all_stats_spec(0.10)
	m = _re(r"每片钥匙碎片全属性提高\s*(\d+)%").search(s)
	if m:
		return _all_stats_spec(float(m.get_string(1)) / 100.0)
	m = _re(r"每件传奇装备全属性提高\s*(\d+)%").search(s)
	if m:
		return _all_stats_spec(float(m.get_string(1)) / 100.0)
	m = _re(r"每击杀一个敌人，金币掉落增加\s*(\d+)%").search(s)
	if m:
		return "[%d, %d, %d, %s, 5]" % [OP_STACK_GAIN, TRIG_ON_KILL, SP["gold_gain"], _f(m.get_string(1))]
	# 「每击杀一个敌人，该武器**所有数值**增加1%（本局内永久叠加）」——
	# 「所有数值」与「全属性」同义，同样要展开成各主属性。
	# 展开后是**多条叠层**（每条各自记层数），走嵌套数组形态。
	if s.contains("每击杀一个敌人，该武器所有数值增加1%") \
			or s.contains("每击杀一个敌人，全属性增加"):
		var parts: Array = []
		for st in ALL_STATS:
			parts.append("[%d, %d, %s, 0.01, 0]" % [OP_STACK_GAIN, TRIG_ON_KILL, st])
		return "[" + ", ".join(parts) + "]"

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
		# 旧版错映射成 `elem_resist`（元素抗性）——玩家多了 30% 元素抗性，
		# 与「受伤转盾」毫无关系。现走专用通道 `dmg_to_shield_pct`。
		return "[%d, %s, true]" % [SP["dmg_to_shield"], _f("30")]
	if s.contains("站立不动2秒后获得"):
		return "[%d, %s, true]" % [SP["elem_resist"], _f("30")]
	if s.contains("使用技能时，有10%概率使增益效果延长"):
		return "[%d, 0.10, true]" % SP["debuff_dur"]
	if s.contains("追击") or s.contains("追加攻击概率提升至"):
		return "[%d, %s, true]" % [SP["true_dmg"], _f("25")]
	# —— 「提升至 N%」的**各版本必须分开** ——
	#
	# 旧版用一个 `contains` 把 8 类语义完全不同的词条**全压成
	# `elem_dmg +20%`** —— 数值和通道都是错的：
	#   「处决阈值提升至40%」→ 应为**阈值** 0.40（不是增伤 0.20）
	#   「附加比例提升至8%」→ 应为**附加伤害**比例 0.08
	#   「伤害提升至500%（护盾爆裂）」→ 应为**满层爆发倍率** 5.0
	#   「爆炸/新星范围扩大20%」→ 应为**技能范围**（走 SKILL_MOD）
	# 逐个显式匹配，**不再留通用兜底**——兜底会让新写法静默走错通道。
	m = _re(r"阈值提升至\s*(\d+)%").search(s)
	if m:
		return "[%d, %s, true]" % [SP["execute_threshold"], _f(m.get_string(1))]
	m = _re(r"附加比例提升至\s*(\d+)%").search(s)
	if m:
		# 「攻击附加当前生命值5%的额外伤害」的强化版 → 真伤通道口径
		return "[%d, %s, true]" % [SP["true_dmg"], _f(m.get_string(1))]
	m = _re(r"伤害提升至\s*(\d+)%").search(s)
	if m:
		# 「护盾被击破时对周围造成300%攻击力伤害」的融合强化 → 满层爆发倍率
		return "[%d, %d, Stat.ATK, %.4f, 0]" % [OP_STACK_GAIN, TRIG_ON_SHIELD_BREAK,
			float(m.get_string(1)) / 100.0]
	m = _re(r"(?:爆炸|新星|火焰)范围扩大\s*(\d+)%").search(s)
	if m:
		# 「爆炸范围扩大20%」——改的是**技能几何**，不是属性。
		# 走 SKILL_MOD 的 `radius_mult`，由 `SkillSystem` 并入 sd 时放大 radius。
		return "[%d, {\"radius_mult\": %.4f}]" % [OP_SKILL_MOD,
			1.0 + float(m.get_string(1)) / 100.0]
	# **无参数**的「范围扩大」（规格只写了三个字，没给数值）——
	# 取 +20% 作默认（与有数值的那几条约同一量级）。
	# **必须放在带数值的规则之后**，否则会先吃掉「爆炸范围扩大20%」。
	if s.contains("范围扩大"):
		return "[%d, {\"radius_mult\": 1.2000}]" % OP_SKILL_MOD
	if s.contains("轨迹持续时间翻倍") or s.contains("附魔持续时间翻倍"):
		return "[%d, {\"duration_mult\": 2.0}]" % OP_SKILL_MOD
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
		# 「召唤物死亡时留下减速区域（3秒，-30%移速）」——量级 30% 要带上，
		# 否则用 `slow` 表定的 25%（与规格不符）。
		var mzs := _re(r"减速区域[（(]\s*(\d+)\s*秒[，,]\s*-?\s*(\d+)%\s*移速").search(s)
		if mzs:
			return "[%d, \"slow\", 1.0, %s, {\"slow\": %s}]" % [OP_TRIGGER_BUFF,
				mzs.get_string(1), _f(mzs.get_string(2))]
		return "[%d, \"slow\", 1.0, 3.0]" % OP_TRIGGER_BUFF

	# —— 施法/治疗同时（5 条）——
	#
	# 「净化/治疗同时清除负面状态」——`cleanse` 不是 buff 词条，而是一个
	# **即时动作**（移除目标身上的负面状态）。故用专门的 sentinel id，
	# 由 `Player._apply_trigger_affixes` 识别后调用 `BuffHolder` 的移除。
	# **不能**当成 buff 施加——那会变成「给敌人挂一个叫净化的状态」。
	if s.contains("净化同时") or s.contains("治疗之泉同时") or s.contains("治疗同时"):
		# **先判「回复最大生命」**：「净化同时**回复5%最大生命**」与
		# 「净化同时**清除一个负面状态**」是两种不同效果。
		# 顺序反了会让回复那条被清负面的规则吃掉（实测：净化法环
		# 只清了负面、5% 回血整个丢失）。
		var mh := _re(r"[，,]?\s*回复\s*(\d+)%\s*最大生命").search(s)
		if mh:
			return "[%d, %s, true]" % [SP["lifesteal"], _f(mh.get_string(1))]
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
	if c.contains("陷阱") and c.contains("时"):
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
func _wrap_with_trigger(spec: String, trig: int, param: float,
		duration: float = 0.0, stack_max: int = 0, text: String = "") -> String:
	# 触发型 / 附带元素型：原样保留（它们自带触发语义）
	#
	# **但「反弹伤害时」是个例外**：`TRIGGER_BUFF` 的既有消费
	#（`_apply_self_trigger_buff`）把状态挂到**自己**身上，
	# 而「反弹时眩晕攻击者」的目标是**打你的人**。故这里把 trigger
	# 标成 `ON_REFLECT`，由 `PlayerEquipmentEffects.on_reflect` 单独处理。
	if spec.begins_with("[%d," % OP_TRIGGER_BUFF):
		if _is_reflect_target_buff(text):
			var mm := _re(r"^\[2,\s*(\"[^\"]*\"),\s*([\d.]+),\s*([\d.]+)").search(spec)
			if mm != null:
				return "[%d, \"%s\", %s, %s, {\"trigger\": %d}]" % [OP_TRIGGER_BUFF,
					mm.get_string(1).replace("\"", ""), mm.get_string(2),
					mm.get_string(3), TRIG_ON_REFLECT]
		return spec
	if spec.begins_with("[%d," % OP_BONUS_ELEMENT):
		return spec

	# 已经是叠层型：把它的 trigger 换掉（主句解出的 trigger 可能不对）
	var m := _re(r"^\[4,\s*(\d+),\s*(.+)\]$").search(spec)
	if m:
		var rest := m.get_string(2)
		return "[%d, %d, %s]" % [OP_STACK_GAIN, trig, rest]

	# 面板属性 / 扩展通道 → 包成叠层型
	#
	# **多属性形态**由**调用方**（`_time_bound_wrap`）展开——
	# 那里能拿到 duration/want_stack 两个额外参数。
	# 这里**不能再展开一次**，否则套两层括号（三层嵌套），
	# `_make_affix_list` 拿到的是数组而非规格，整条静默变 0 条。

	m = _re(r"^\[([A-Za-z_.]+|\d+),\s*([-\d.]+),\s*(true|false)\]$").search(spec)
	if m:
		var stat := m.get_string(1)
		var v := m.get_string(2)
		# **低血阈值必须带上**（第 6 槽）：`hp_threshold` 是**按词条**的——
		# 「生命低于30%时…」与「生命低于50%时…」是两条独立词条，
		# 若都退化成 0.5，低血 30% 那条会在 30%~50% 区间**提前生效**。
		if trig == TRIG_LOW_HP and param > 0.0:
			return "[%d, %d, %s, %s, %d, %.4f]" % [OP_STACK_GAIN, trig, stat, v,
				stack_max, param]
		# **层数上限（第 5 槽）**：「每次冲刺叠加1层"踏虚"（最多3层）」少了它
		# 就**永不叠层**——「最多3层」形同虚设。此前被硬编码成 0。
		if duration > 0.0:
			return "[%d, %d, %s, %s, %d, 0, {\"seconds\": %.4f}]" % [
				OP_STACK_GAIN, trig, stat, v, stack_max, duration]
		return "[%d, %d, %s, %s, %d]" % [OP_STACK_GAIN, trig, stat, v, stack_max]

	# 其他形态（周期型等）：原样保留，不强行包装
	return spec


## 「全属性」展开成的主属性集合
##
## **不含 RNG / CDR / MP**：这三者的 base 是 0 或极小（`DEFAULT_BASE` 里
## RNG=1.5、CDR=0、MP=100），百分比加成在 `get_value = base + flat + base×pct`
## 下几乎无效果——写进去等于没写。其余 8 项是玩家实际在追的属性。
const ALL_STATS := ["Stat.HP", "Stat.ATK", "Stat.DEF", "Stat.SPD",
	"Stat.ASPD", "Stat.AP", "Stat.CRT", "Stat.CRD"]


## 多属性并列 → 多属性规格（非多属性时返回空串）
##
## ## 为什么需要
##
## 规格里大量「属性A +N%、属性B +M%」的并列写法，旧规则只认第一个：
##   · 「暴击率+25%、暴击伤害+50%」→ 只出 `Stat.CRT`（暴伤丢了）
##   · 「每层+4%攻速、+3%暴击率」  → 只出 `Stat.ASPD`
##   · 「攻击+40%、攻速+30%、吸血+25%」→ 只出攻击
##
## ## 叠层形态
##
## 片段来自「每层+X」时，结果是**叠层词条**（`[4, trig, stat, v, max]`）
## 而不是常驻属性——每条子规格都要带上同一个层数上限，
## 否则「最多 N 层」在该属性上失效（层数记不住）。
func _parse_stat_list(s: String) -> String:
	var parts := _split_stat_segments(s)
	if parts.size() < 2:
		return ""
	var is_stack := s.contains("每层")
	var stack_max := _stack_max_from_text(s)
	var trig := TRIG_ON_KILL if s.contains("击杀") else \
		(TRIG_ON_HURT if s.contains("受到伤害") or s.contains("受击") else TRIG_ALWAYS)
	if s.contains("背刺"):
		trig = TRIG_ON_HIT
	var specs: Array = []
	for p in parts:
		var spec := _one_stat_segment(str(p))
		if spec.is_empty():
			return ""   # 有一个片段不认得 → 整条交给原有规则
		if is_stack:
			# `[Stat.X, v, true]` / `[NNN, v, true]` → 叠层形态
			var m := _re(r"^\[([A-Za-z_.0-9]+),\s*([\d.]+),\s*true\]$").search(spec)
			if m == null:
				return ""
			spec = "[%d, %d, %s, %s, %d]" % [OP_STACK_GAIN, trig,
				m.get_string(1), m.get_string(2), stack_max]
		specs.append(spec)
	return "[" + ", ".join(specs) + "]"


## 按 `、` `，` `。` 切出片段；**全部片段都必须是属性片段**才返回，
## 否则返回空数组（交给原有规则）。
func _split_stat_segments(s: String) -> Array:
	var t := s.strip_edges()
	# **先剥下标**（「（最多5层）」「（持续5秒）」）——它们是该词条的
	# 条件/时长，由外层另行取用（`_stack_max_from_text` / `_duration_from_text`），
	# 这里只求不挡住属性片段的匹配。
	# **必须在找「每层」之前剥**：否则「…（最多5层），每层+4%攻速」
	# 的前缀从句里那串下标会干扰。
	t = _re(r"[（(][^）)]*[）)]").sub(t, "", true)
	# 「每次背刺成功叠加1层"影舞"，每层+4%攻速、+3%暴击率」——
	# 真正的属性列表在「每层」之后，前面是叠层条件的描述。
	# 取**最后一个**「每层」之后的文本（前面那句「叠加1层」不含「每层」）。
	var idx := t.rfind("每层")
	if idx >= 0:
		t = t.substr(idx + 2)
	else:
		var m0 := _re(r"^每层[:：]?\s*").search(t)
		if m0:
			t = t.substr(m0.get_end())
	t = t.replace("；", "、").replace(";", "、")
	var raw: Array = []
	for piece in t.split("。"):
		if str(piece).strip_edges().is_empty():
			continue
		for sub in str(piece).split("，"):
			if str(sub).strip_edges().is_empty():
				continue
			for sub2 in str(sub).split("、"):
				# 片段开头的 `+` 与「每层」残留都要去掉
				var seg := str(sub2).strip_edges().trim_prefix("+").strip_edges()
				if not seg.is_empty():
					raw.append(seg)
	return raw if raw.size() >= 2 else []


## 单个「属性+N%」片段 → 规格（不是属性片段时返回空串）
func _one_stat_segment(seg: String) -> String:
	# 形态 A：`(前缀)?属性名(+|提高|增加|提升)?N%`
	# 前缀容忍「冲刺后获得3秒」「攻击有20%概率」等修饰——只取属性部分。
	var m := _re(r"^(?:获得|自身)?[^一-龥]*([一-龥]{1,6}?)\s*(?:\+?|提高|增加|提升)\s*(\d+(?:\.\d+)?)\s*%$").search(seg)
	if m == null:
		# 形态 B：`N%属性名`
		m = _re(r"^[^一-龥]*(\d+(?:\.\d+)?)\s*%\s*([一-龥]{1,6})$").search(seg)
		if m == null:
			return ""
		return _stat_spec_of(str(m.get_string(2)), float(m.get_string(1)) / 100.0)
	var nm := str(m.get_string(1))
	# 剥掉「属性」前缀残留（「自身攻击」→「攻击」）
	for pre in ["自身", "角色", "周围", "获得的"]:
		if nm.begins_with(pre):
			nm = nm.substr(pre.length())
	return _stat_spec_of(nm, float(m.get_string(2)) / 100.0)


## 多属性片段里的**短名别名**（只在 `_stat_spec_of` 生效）
##
## 并列写法里属性名往往被压缩成两三个字（「受伤」「反伤」「资源回复」），
## 而 `STAT_ENUM` / `EXT_BY_NAME` 收的是完整说法（「受到伤害」）。
## **不动那两个全局表**——它们是别处的匹配依据，加短名会误伤。
const STAT_ALIAS_MULTI := {
	"减伤": "dmg_reduction", "受伤": "dmg_reduction",
	"反伤": "reflect", "反弹": "reflect",
	"资源回复": "res_regen", "回蓝": "res_regen",
	"移速": "Stat.SPD", "攻速": "Stat.ASPD", "暴击率": "Stat.CRT",
	"暴击伤害": "Stat.CRD", "攻击": "Stat.ATK", "攻击力": "Stat.ATK",
	"生命": "Stat.HP", "生命值": "Stat.HP", "最大生命": "Stat.HP",
	"防御": "Stat.DEF", "护甲": "Stat.DEF", "闪避": "dodge",
	"吸血": "lifesteal", "法强": "Stat.AP", "法术强度": "Stat.AP",
	"伤害": "Stat.ATK", "输出": "Stat.ATK", "资源": "res_regen",
}


## 属性名 + 比例 → 规格字面量（认不出返回空串）
func _stat_spec_of(nm: String, v: float) -> String:
	var name := nm.strip_edges().trim_suffix("值")
	if name.is_empty():
		return ""
	# ① 短名别名（并列写法专用）
	if STAT_ALIAS_MULTI.has(name):
		var al: String = STAT_ALIAS_MULTI[name]
		if al.begins_with("Stat."):
			return "[%s, %.4f, true]" % [al, v]
		return "[%d, %.4f, true]" % [SP[al], v]
	# ② 全名表
	if STAT_ENUM.has(name):
		return "[%s, %.4f, true]" % [STAT_ENUM[name], v]
	if EXT_BY_NAME.has(name):
		return "[%d, %.4f, true]" % [SP[EXT_BY_NAME[name]], v]
	if name.contains("全属性") or name.contains("所有基础属性"):
		return _all_stats_spec(v)
	return ""


## 产出「全属性 +N%」的**多属性规格**
##
## ## 为什么要展开
##
## 规格写「全属性+3%」，旧生成器只产出 `[Stat.ATK, 0.03, true]`——
## 玩家拿到的是「攻击力 +3%」，其余 7 项一点没有。实测 12 条如此。
##
## `_make_affix_list` **已支持嵌套数组**（`spec[0] is Array` 时逐条构建），
## 故这里直接产出 `[[A, v, true], [B, v, true], …]`，无需改数据层。
func _all_stats_spec(v: float, is_percent: bool = true) -> String:
	var t := "true" if is_percent else "false"
	var vs := "%.4f" % v
	var parts: Array = []
	for s in ALL_STATS:
		parts.append("[%s, %s, %s]" % [s, vs, t])
	return "[" + ", ".join(parts) + "]"
##
## 该词条的效果目标是**攻击者**（而非自己）吗？
##
## 判据：「反弹伤害有 N% 概率<给攻击者挂状态>」。这类词条的宿主是
## **打你的人**，故不能走 `_apply_self_trigger_buff`（那条挂自己）。
func _is_reflect_target_buff(t: String) -> bool:
	return t.contains("反弹伤害有") and t.contains("概率") \
		and (t.contains("眩晕攻击者") or t.contains("流血"))


## 必须优先取「最多/可叠」：「受到伤害叠加1层"不朽"（最多15层）」里
## 两个数字**都是层数**但含义相反——`1` 是每次叠几层，`15` 才是上限。
func _stack_max_from_text(t: String) -> int:
	var m := _re(r"(?:最多|可叠加?|最多可叠)\s*(\d+)\s*层").search(t)
	if m:
		return int(m.get_string(1))
	m = _re(r"叠加\s*(\d+)\s*层").search(t)
	if m:
		return int(m.get_string(1))
	return 0


## 从原文抽「持续 N 秒」（无则 0）
##
## 支持三种写法：`持续N秒` / `获得N秒` / `N秒内`——规格里混用。
func _duration_from_text(s: String) -> float:
	for pat in [
		r"持续\s*(\d+(?:\.\d+)?)\s*秒",
		r"获得\s*(\d+(?:\.\d+)?)\s*秒",
		r"(\d+(?:\.\d+)?)\s*秒内",
	]:
		var m := _re(pat).search(s)
		if m:
			return float(m.get_string(1))
	return 0.0


## **时长兜底**：原文带「N秒」而结果没带时，把时长补进去
##
## ## 为什么需要
##
## 「击杀后获得3秒暴击率+15%」「冲刺后获得5%移速，持续2秒」这类写法，
## `_split_clause` **不切分**（从句标记「X时，/X后，」要带逗号，而这两条
## 是「击杀后获得」「冲刺后获得」，无逗号），于是直接命中第 42 节的规则
## ——那些规则只产出裸属性，**时长全丢**，落地成**永久**加成。
## 一条条改规则既漏又散，故在 `_parse_one` 里统一补。
##
## ## **只在安全形态下补**（这条限制很重要）
##
## 原文里的「持续N秒」不都属于**词条本身**：
##   · 「攻击施加"猎神标记"（最多8层，持续10秒），每层+5%受到伤害」
##     —— 10 秒是**标记**的时长（子效果），不是这条词条的时长
##   · 「坠落点留下星尘区域（每秒30%法强，持续3秒）」—— 是**区域**的时长
## 给这些补时长会张冠李戴。故限定：
##   ① 时长出现在**括号之外**（`（…）` 里的属子效果，一律跳过）
##   ② 结果形如「…获得 N% X，持续 M 秒」——`获得` 与 `持续` 同属一个分句
func _time_bound_wrap(spec: String, text: String) -> String:
	if spec.is_empty() or spec.begins_with("__"):
		return spec
	# 括号内的时长属于子效果（标记/区域/分身），不补。
	# **但层数上限恰恰常写在括号里**（「（最多15层）」），故单独取。
	var has_dur := not (text.contains("（") or text.contains("("))
	var dur := _duration_from_text(text) if (has_dur and text.contains("获得")) else 0.0
	var want_stack := _stack_max_from_text(text)
	if dur <= 0.0 and want_stack <= 0:
		return spec
	# **多属性形态**：逐条独立包装（每条都是独立词条）
	#
	# 注意**只包一层**：`_sub_specs` 已经拆到叶子规格，
	# 每条再包一次即可。若在这里整体再包一层就会变成三层嵌套
	#（`[[[…],[…]]]`）——`_make_affix_list` 此前只认一层，
	# 整条词条会静默变成 0 条。
	if _is_multi_spec(spec):
		var wrapped: Array = []
		for sub in _sub_specs(spec):
			wrapped.append(_wrap_with_trigger(sub, _infer_trigger_from_text(text),
				0.0, dur, want_stack, text))
		return "[" + ", ".join(wrapped) + "]"
	# 叠层型：**已有触发条件、只缺时长/层数** → 补第 5 槽与第 7 槽
	if _is_stack_spec(spec):
		# 已带参数字典时**只补层数**（时长/其它参数已有，重建会破坏）
		if spec.contains("{"):
			if want_stack <= 0:
				return spec
			var mm := _re(r"^\[4,\s*(\d+),\s*([^,]+),\s*([^,]+),\s*(\d+),\s*(.+)\]$").search(spec)
			if mm == null or int(mm.get_string(4)) != 0:
				return spec
			return "[%d, %s, %s, %s, %d, %s]" % [OP_STACK_GAIN,
				mm.get_string(1), mm.get_string(2), mm.get_string(3),
				want_stack, mm.get_string(5)]
		var m := _re(r"^\[4,\s*(\d+),\s*(.+)\]$").search(spec)
		if m == null:
			return spec
		var trig := m.get_string(1)
		var slots: Array = m.get_string(2).split(",")
		# 归一化成 `[stat, value, stack_max, threshold]` 四槽
		while slots.size() < 4:
			slots.append(" 0")
		# **层数上限要从原文补**：`每次冲刺叠加1层"踏虚"（最多3层），每层+5%闪避`
		# 少了 stack_max 就**永不叠层**——「最多3层」形同虚设。
		if want_stack > 0 and int(str(slots[2]).strip_edges()) == 0:
			slots[2] = " %d" % want_stack
		if dur > 0.0:
			return "[%d, %s, %s, {\"seconds\": %.4f}]" % [
				OP_STACK_GAIN, trig, ", ".join(slots), dur]
		return "[%d, %s, %s]" % [OP_STACK_GAIN, trig, ", ".join(slots)]
	# 裸属性：条件也没了（无逗号的「X后获得…」）→ 一并补上 trigger 与时长
	if _is_plain_spec(spec):
		var trig := _infer_trigger_from_text(text)
		if trig == TRIG_ALWAYS:
			return spec
		return _wrap_with_trigger(spec, trig, 0.0, dur, want_stack, text)
	return spec


## 从**整条原文**推断触发条件（`_trigger_of_clause` 的宽松版）
##
## `_trigger_of_clause` 只接受「从句片段」，而这里拿到的是整条文本——
## 无逗号的写法（「冲锋后获得5%减伤」「冲刺后获得5%移速」）切不出从句，
## 故按**关键词**兜底推断。顺序即优先级（更具体的在前）。
func _infer_trigger_from_text(t: String) -> int:
	if t.contains("击杀"):
		return TRIG_ON_KILL
	if t.contains("受到伤害") or t.contains("受击"):
		return TRIG_ON_HURT
	if t.contains("暴击"):
		return TRIG_ON_CRIT
	if t.contains("格挡"):
		return TRIG_ON_BLOCK
	if t.contains("闪避"):
		return TRIG_ON_DODGE
	if t.contains("冲刺") or t.contains("冲锋") or t.contains("疾跑"):
		return TRIG_ON_SPRINT
	if t.contains("受到元素伤害") or t.contains("元素抗性触发"):
		return TRIG_ON_ELEMENT_PROC
	if t.contains("召唤"):
		return TRIG_ON_SUMMON_ALIVE
	if t.contains("陷阱"):
		return TRIG_ON_TRAP_TRIGGER
	if t.contains("技能") and (t.contains("释放") or t.contains("使用")):
		return TRIG_ON_SKILL_CAST
	return TRIG_ALWAYS


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


## 从原文抽「最多 +N%」的上限（无则 1.0 = 无上限）
##
## 「每持有 100 金币，+1% 攻击力（**最多 +20%**）」——上限必须带上，
## 不带的话金币越多加成越离谱（无上限）。
func _cap_from_text(t: String) -> float:
	var m := _re(r"最多\s*\+?\s*(\d+)%").search(t)
	if m:
		return float(m.get_string(1)) / 100.0
	return 1.0
