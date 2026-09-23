class_name BuffDefs
extends RefCounted
## 词条（Buff / Debuff）定义表 —— 《噬铁者》名词设计分册 第 3/4/5 章
##
## 分册口径：词条按功能分类，同类可叠层；同一攻击可同时触发多种词条，独立判定。
## 本文件只放**数据**；运行时的挂接/计时/叠层见 buff_holder.gd。
##
## 总计 81 种：负面 38（3.1~3.6）+ 增益 22（4.1~4.4）+ 通用池 21（第 5 章）
## 实现分层见每条 impl 字段：
##   "stat"     —— 纯属性型，Modifier 立刻可作用（本轮生效）
##   "dot"      —— 持续伤害/治疗，由 buff_holder 按 tick 结算（本轮生效）
##   "control"  —— 控制型（定身/眩晕/冰冻/麻痹…），需要目标状态机配合（登记）
##   "special"  —— 需要专属逻辑（护盾/反伤/传送/召唤…）（登记）

enum Kind { DOT, SLOW, CONTROL, VULN, WEAKEN, DISPLACE, SHIELD, ATTACK, MOBILITY, RESOURCE, GENERIC }

## 词条行格式：
## [id, 名称, 分类, 持续时间(0=永久), 叠层上限(0=不叠), 效果描述, 实现类型, 效果参数]
## 效果参数键约定（供运行时消费）：
##   stat / flat / pct     —— 属性修正
##   dot_pct               —— 每秒伤害 = 法强 × dot_pct（× 层数）
##   slow / aspd_down      —— 移速/攻速降低比例
##   vuln                  —— 受到伤害 +%
##   heal_down             —— 受到治疗 -%
##   dmg_down              —— 造成伤害 -%
const BUFFS := [
	# ---------- 3.1 持续伤害型（5） ----------
	["burn", "灼烧", Kind.DOT, 4.0, 50, "每秒造成法强×0.04 法术伤害", "dot", {"dot_pct": 0.04}],
	["poison_rot", "毒蚀", Kind.DOT, 0.0, 30, "每秒法强×0.03 法术伤害，全局易伤 +1%/层", "dot", {"dot_pct": 0.03, "vuln": 0.01}],
	["tear", "撕裂", Kind.DOT, 4.0, 0, "每秒造成攻击力×0.2 物理伤害", "dot", {"dot_atk": 0.2}],
	["bleed", "流血", Kind.DOT, 3.0, 3, "每秒造成攻击力×0.15 物理伤害", "dot", {"dot_atk": 0.15}],
	["curse_burn", "诅咒燃烧", Kind.DOT, 3.0, 0, "每秒法强×0.5 法术伤害，治疗效果 -30%", "dot", {"dot_pct": 0.5, "heal_down": 0.30}],

	# ---------- 3.2 减速 / 减速攻型（6） ----------
	["frost", "寒霜", Kind.SLOW, 3.0, 3, "移速 -25%/层，攻速 -20%/层", "stat", {"slow": 0.25, "aspd_down": 0.20}],
	["erosion", "侵蚀", Kind.SLOW, 0.0, 0, "移速 -20%（毒蚀 10 层解锁）", "stat", {"slow": 0.20}],
	["entangle", "缠绕", Kind.CONTROL, 1.5, 0, "定身 1.5 秒（不能移动，可攻击）", "control", {"root": true}],
	["thorn_slow", "荆棘地减速", Kind.SLOW, 0.0, 0, "移速 -50%（踏入期间）", "stat", {"slow": 0.50}],
	["dull", "迟钝", Kind.SLOW, 4.0, 0, "攻速 -25%，施法速度 -25%", "stat", {"aspd_down": 0.25}],
	["mire", "泥沼", Kind.SLOW, 3.0, 0, "移速 -40%，无法翻滚", "stat", {"slow": 0.40, "no_dodge": true}],
	# 第 4 层泥潭「越陷越深」的深层档位（策划：泥潭陷阱 = 减速 + 持续伤害）。
	# 策划未给分档数值，按"踩一下代价小、站桩被困住"的意图取 3 档递进。
	# 与上面的技能专用词条同性质：**不属于文档的 81 条**，见 SKILL_ONLY_IDS。
	["mire_deep", "深陷", Kind.SLOW, 3.0, 0, "移速 -50%，无法翻滚", "stat", {"slow": 0.50, "no_dodge": true}],
	["mire_deepest", "没顶", Kind.SLOW, 3.0, 0, "移速 -60%，无法翻滚", "stat", {"slow": 0.60, "no_dodge": true}],

	# ---------- 3.3 硬控型（8） ----------
	["freeze", "冰冻", Kind.CONTROL, 1.5, 0, "无法移动/攻击（冰裂可延长至 2.5 秒）", "control", {"stun": true}],
	["paralyze", "麻痹", Kind.CONTROL, 1.5, 0, "无法行动（雷暴触发）", "control", {"stun": true}],
	["stun", "眩晕", Kind.CONTROL, 1.0, 0, "无法行动", "control", {"stun": true}],
	["knockup", "击飞", Kind.DISPLACE, 0.0, 0, "面朝方向弹射 3 米", "control", {"knockup": 3.0}],
	["silence", "沉默", Kind.CONTROL, 3.0, 0, "无法施放技能", "control", {"no_skill": true}],
	["disarm", "缴械", Kind.CONTROL, 3.0, 0, "无法普攻", "control", {"no_attack": true}],
	["taunt", "嘲讽", Kind.CONTROL, 3.0, 0, "强制攻击施法者", "control", {"taunt": true}],
	["fear", "恐惧", Kind.CONTROL, 2.0, 0, "强制远离施法者", "control", {"fear": true}],

	# ---------- 3.4 易伤 / 破甲型（10） ----------
	["static_charge", "静电", Kind.VULN, 0.0, 10, "雷系增伤叠层；满 10 层触发雷暴", "special", {"element_stack": "static"}],
	["judgement", "审判印记", Kind.VULN, 8.0, 0, "受到伤害提升", "stat", {"vuln": 0.15}],
	["dark_erosion", "暗蚀", Kind.VULN, 5.0, 0, "受到暗影伤害提升", "stat", {"vuln": 0.12}],
	["brand", "烙印", Kind.VULN, 6.0, 0, "受到伤害提升", "stat", {"vuln": 0.10}],
	["mark", "标记", Kind.VULN, 6.0, 0, "被标记，受到伤害提升", "stat", {"vuln": 0.20}],
	["armor_down", "降甲", Kind.VULN, 4.0, 0, "护甲降低", "stat", {"def_down": 0.20}],
	["armor_break", "破甲", Kind.VULN, 4.0, 0, "护甲大幅降低", "stat", {"def_down": 0.35}],
	["frailty", "脆弱", Kind.VULN, 5.0, 0, "受到暴击伤害提升", "special", {"crit_vuln": 0.25}],
	["charm", "蛊惑", Kind.WEAKEN, 4.0, 0, "攻击有概率打空", "special", {"miss_chance": 0.30}],
	["expose", "暴露", Kind.VULN, 5.0, 0, "无法闪避，受到伤害提升", "stat", {"vuln": 0.10, "no_dodge": true}],

	# ---------- 3.5 减益 / 削弱型（5） ----------
	["enfeeble", "衰弱", Kind.WEAKEN, 5.0, 0, "造成伤害 -20%（毒蚀 20 层解锁）", "stat", {"dmg_down": 0.20}],
	["weakness", "虚弱", Kind.WEAKEN, 6.0, 0, "治疗效果 -50%（毒蚀 30 层解锁）", "stat", {"heal_down": 0.50}],
	["immolate", "焚身", Kind.DOT, 4.0, 0, "自身受到火焰伤害提升", "stat", {"vuln": 0.15}],
	["blind", "致盲", Kind.WEAKEN, 3.0, 0, "命中率大幅下降", "special", {"miss_chance": 0.50}],
	["fatigue", "疲软", Kind.WEAKEN, 4.0, 0, "攻击力降低", "stat", {"atk_down": 0.20}],

	# ---------- 3.6 击退 / 位移型（4） ----------
	["pull", "牵引", Kind.DISPLACE, 0.0, 0, "强制拉向风眼/施法者", "control", {"pull": true}],
	["knockback", "击退", Kind.DISPLACE, 0.0, 0, "被推开", "control", {"knockback": true}],
	["drag", "拉拽", Kind.DISPLACE, 0.0, 0, "被拖拽至目标位置", "control", {"drag": true}],
	["shadow_dash", "暗影突袭瞬移", Kind.MOBILITY, 0.0, 0, "瞬移至目标背后", "special", {"teleport_behind": true}],

	# ---------- 4.1 护盾 / 防御型（4） ----------
	["shield", "护盾", Kind.SHIELD, 8.0, 0, "吸收固定伤害", "special", {"absorb": 200.0}],
	["light_shield", "光盾", Kind.SHIELD, 8.0, 0, "吸收伤害并反射部分", "special", {"absorb": 150.0, "reflect": 0.20}],
	["iron_body", "铁身", Kind.SHIELD, 6.0, 0, "受到伤害降低", "stat", {"dmg_taken_down": 0.30}],
	["adamant", "金刚体", Kind.SHIELD, 5.0, 0, "免疫控制且受到伤害降低", "special", {"cc_immune": true, "dmg_taken_down": 0.20}],

	# ---------- 4.2 攻击 / 输出型（9） ----------
	["war_cry", "战吼", Kind.ATTACK, 6.0, 0, "攻击力提升", "stat", {"atk_up": 0.25}],
	["blood_rage", "血怒", Kind.ATTACK, 8.0, 0, "生命越低伤害越高", "special", {"low_hp_dmg": 0.50}],
	["spell_flame", "咒焰", Kind.ATTACK, 6.0, 0, "法术强度提升", "stat", {"ap_up": 0.30}],
	["focus", "聚力", Kind.ATTACK, 5.0, 0, "下次攻击伤害大幅提升", "special", {"charge_next": 1.5}],
	["supreme", "极意", Kind.ATTACK, 6.0, 0, "攻速与移速同时提升", "stat", {"aspd_up": 0.25, "spd_up": 0.15}],
	["break_limit", "破极状态", Kind.ATTACK, 5.0, 0, "全属性提升", "stat", {"atk_up": 0.20, "aspd_up": 0.20, "spd_up": 0.10}],
	["forest_wrath", "森林之怒", Kind.ATTACK, 6.0, 0, "攻击附带自然伤害", "special", {"bonus_element": "nature"}],
	["forest_bless", "森林祝福", Kind.ATTACK, 8.0, 0, "攻击与回复同时提升", "stat", {"atk_up": 0.15, "heal_up": 0.20}],
	["verdict", "裁决时刻", Kind.ATTACK, 5.0, 0, "对低血目标伤害提升", "special", {"execute_bonus": 0.40}],

	# ---------- 4.3 移动 / 机动型（4） ----------
	["shadow_trace", "影痕", Kind.MOBILITY, 4.0, 0, "留下残影，闪避提升", "stat", {"dodge_up": 0.20}],
	["shadow_form", "暗影形态", Kind.MOBILITY, 5.0, 0, "移速提升且可穿怪", "special", {"spd_up": 0.25, "phase": true}],
	["wind_step", "风之步", Kind.MOBILITY, 6.0, 0, "移速提升", "stat", {"spd_up": 0.30}],
	["gale", "疾风", Kind.MOBILITY, 5.0, 0, "移速与攻速提升", "stat", {"spd_up": 0.20, "aspd_up": 0.15}],

	# ---------- 4.4 资源 / 回复型（5） ----------
	["bloodbath", "浴血", Kind.RESOURCE, 6.0, 0, "造成伤害时回复生命", "special", {"lifesteal": 0.10}],
	["shadow_hunt", "暗影猎杀", Kind.RESOURCE, 5.0, 0, "击杀回复资源", "special", {"on_kill_resource": true}],
	["element_affinity", "元素亲和", Kind.RESOURCE, 8.0, 0, "元素伤害提升", "stat", {"elem_up": 0.25}],
	["arcane_echo", "奥术回响", Kind.RESOURCE, 6.0, 0, "技能有概率不消耗资源", "special", {"free_cast_chance": 0.30}],
	["execute", "处决", Kind.RESOURCE, 5.0, 0, "对低血目标直接斩杀", "special", {"execute_threshold": 0.15}],

	# ---------- 职业技能专用（挂在自己或敌人身上，来源为技能）
	# **不属于策划文档的 81 条词条体系**：这些是《角色设计分册》里各职业技能
	# 描述中明确点出的状态（如血怒的三项增益、拉拽的减速），文档只给了效果
	# 描述、没有独立词条定义，故在此补充。见 SKILL_ONLY_IDS。
	["rage_haste", "血怒·疾", Kind.ATTACK, 8.0, 0, "移速 +50%，攻速 +50%", "stat", {"spd_up": 0.50, "aspd_up": 0.50}],
	["rage_fury", "血怒·狂", Kind.ATTACK, 8.0, 0, "攻击力 +30%", "stat", {"atk_up": 0.30}],
	["rage_dance_aspd", "狂舞·疾", Kind.ATTACK, 6.0, 0, "攻速 +60%", "stat", {"aspd_up": 0.60}],
	["rage_dance_true", "狂舞·真", Kind.ATTACK, 6.0, 0, "攻击附带真实伤害", "special", {"true_dmg_pct": 0.30}],
	["chain_weak", "锁链缚", Kind.SLOW, 3.0, 0, "移速 -30%，攻速 -30%", "stat", {"slow": 0.30, "aspd_down": 0.30}],
	# 策划 4.4 咒焰使：每次施法 +1 层，每层 +8% 伤害、+5% 施法速度（最多 6 层）
	["flame_mark", "咒焰", Kind.ATTACK, 5.0, 6, "每层法强 +8%、攻速 +5%", "stat", {"ap_up": 0.08, "aspd_up": 0.05}],
	# 策划 4.6 虚空古神化身：目标受伤 +10%/层（最多 5 层）
	["void_stigma", "虚空印记", Kind.VULN, 8.0, 5, "每层受到伤害 +10%", "stat", {"vuln": 0.10}],
	# 策划 7.4 破极：每 25 连击触发 6 秒，攻击 +70%、攻速 +50%、防御归零
	["break_limit_state", "破极", Kind.ATTACK, 6.0, 0, "攻击 +70%、攻速 +50%、防御归零", "stat",
		{"atk_up": 0.70, "aspd_up": 0.50, "def_down": 1.0}],
	# 策划 6.5 森之选召：领域内猎人攻速 +40%、暴击 +30%
	["forest_domain_self", "森之领域·主", Kind.ATTACK, 6.0, 0, "领域内攻速 +40%、暴击 +30%", "stat",
		{"aspd_up": 0.40, "crit_up": 0.30}],
	# 策划 6.5 森之选召：领域内敌人移速 -40%、受伤 +25%
	["forest_domain_foe", "森之领域·敌", Kind.VULN, 6.0, 0, "移速 -40%、受伤 +25%", "stat",
		{"slow": 0.40, "vuln": 0.25}],
	# 策划 8.1 锁链判官：攻击挂审判印记，每层 +10% 法伤
	["judge_mark", "审判印记", Kind.VULN, 6.0, 5, "每层受到法术伤害 +10%", "stat", {"vuln": 0.10}],
	# 策划 8.5 光暗审裁：光层（治疗/护盾积累）
	["light_layer", "光层", Kind.RESOURCE, 10.0, 10, "光层累积", "special", {"light_layer": true}],
	# 策划 8.5 光暗审裁：暗层（施加负面积累）
	["dark_layer", "暗层", Kind.RESOURCE, 10.0, 10, "暗层累积", "special", {"dark_layer": true}],
	# 策划 8.5：光暗均 ≥5 时全伤害 +40%、移速 +30%
	["verdict_balance", "光暗平衡", Kind.ATTACK, 5.0, 0, "全伤害 +40%、移速 +30%", "stat",
		{"atk_up": 0.40, "ap_up": 0.40, "spd_up": 0.30}],

	# ---------- 第 5 章 通用词条池（21） ----------
	["gen_atk_up", "属性增益·攻击", Kind.GENERIC, 8.0, 0, "攻击力提升", "stat", {"atk_up": 0.12}],
	["gen_def_up", "属性增益·防御", Kind.GENERIC, 8.0, 0, "防御提升", "stat", {"def_up": 0.12}],
	["gen_hp_up", "属性增益·生命", Kind.GENERIC, 8.0, 0, "生命上限提升", "stat", {"hp_up": 0.12}],
	["gen_spd_up", "属性增益·移速", Kind.GENERIC, 8.0, 0, "移速提升", "stat", {"spd_up": 0.12}],
	["gen_aspd_up", "属性增益·攻速", Kind.GENERIC, 8.0, 0, "攻速提升", "stat", {"aspd_up": 0.12}],
	["gen_crit_up", "属性增益·暴击率", Kind.GENERIC, 8.0, 0, "暴击率提升", "stat", {"crit_up": 0.10}],
	["gen_crd_up", "属性增益·暴击伤害", Kind.GENERIC, 8.0, 0, "暴击伤害提升", "stat", {"crd_up": 0.20}],
	["gen_ap_up", "属性增益·法强", Kind.GENERIC, 8.0, 0, "法术强度提升", "stat", {"ap_up": 0.12}],
	["gen_cdr_up", "属性增益·冷却缩减", Kind.GENERIC, 8.0, 0, "冷却缩减提升", "stat", {"cdr_up": 0.10}],
	["gen_rng_up", "属性增益·射程", Kind.GENERIC, 8.0, 0, "射程提升", "stat", {"rng_up": 0.15}],
	["gen_control_1", "控制附加·减速", Kind.GENERIC, 3.0, 0, "命中时附加减速", "stat", {"slow": 0.25}],
	["gen_control_2", "控制附加·定身", Kind.GENERIC, 1.5, 0, "命中时附加定身", "control", {"root": true}],
	["gen_control_3", "控制附加·眩晕", Kind.GENERIC, 1.0, 0, "命中时附加眩晕", "control", {"stun": true}],
	["gen_control_4", "控制附加·击退", Kind.GENERIC, 0.0, 0, "命中时击退", "control", {"knockback": true}],
	["gen_fx_1", "特效附加·灼烧", Kind.GENERIC, 4.0, 10, "命中时附加灼烧层数", "dot", {"dot_pct": 0.04, "element_stack": "fire"}],
	["gen_fx_2", "特效附加·毒蚀", Kind.GENERIC, 0.0, 10, "命中时附加毒蚀层数", "dot", {"dot_pct": 0.03, "element_stack": "poison"}],
	["gen_fx_3", "特效附加·寒霜", Kind.GENERIC, 3.0, 3, "命中时附加寒霜层数", "stat", {"slow": 0.25, "element_stack": "frost"}],
	["gen_fx_4", "特效附加·静电", Kind.GENERIC, 0.0, 10, "命中时附加静电层数", "special", {"element_stack": "static"}],
	["gen_sustain_1", "续航·灭杀回复", Kind.GENERIC, 6.0, 0, "击杀时回复生命", "special", {"on_kill_heal": 0.05}],
	["gen_sustain_2", "续航·受击减伤", Kind.GENERIC, 6.0, 0, "受到伤害降低", "stat", {"dmg_taken_down": 0.15}],
	["gen_sustain_3", "续航·脱战回复", Kind.GENERIC, 10.0, 0, "脱战时持续回复", "special", {"regen": 0.02}],
	# ---------- 装备叠层型（装备参考2：逐层成长的词条） ----------
	#
	# 装备设计里大量出现「每层 +N%…（最多 N 层）」的成长型自有词条。
	# 这些**不需要新机制**：BuffHolder 早就支持叠层
	#（`stacks` / `max_stacks` / `stacks_of`），且 `_sync_modifier` 会把
	# 层数乘进属性（`params × stacks`）。第 5 列就是「最多 N 层」。
	["eq_atk_stack",    "攻击·叠层", Kind.ATTACK,   10.0, 10, "每层攻击力 +2%（最多 10 层）", "stat", {"atk_up": 0.02}],
	["eq_def_stack",    "防御·叠层", Kind.SHIELD,   10.0,  5, "每层防御 +1%（最多 5 层）", "stat", {"def_up": 0.01}],
	["eq_aspd_stack",   "攻速·叠层", Kind.ATTACK,    8.0,  5, "每层攻速 +2%（最多 5 层）", "stat", {"aspd_up": 0.02}],
	["eq_crit_stack",   "暴击·叠层", Kind.ATTACK,    8.0,  5, "每层暴击率 +3%（最多 5 层）", "stat", {"crit_up": 0.03}],
	["eq_crd_stack",    "暴伤·叠层", Kind.ATTACK,    8.0,  5, "每层暴击伤害 +3%（最多 5 层）", "stat", {"crd_up": 0.03}],
	["eq_spd_stack",    "移速·叠层", Kind.MOBILITY,  8.0,  3, "每层移速 +2%（最多 3 层）", "stat", {"spd_up": 0.02}],
	["eq_reduce_stack", "减伤·叠层", Kind.SHIELD,   10.0, 10, "每层减伤 +2%（最多 10 层）", "stat", {"dmg_taken_down": 0.02}],
	["eq_swift_stack",  "迅捷·叠层", Kind.MOBILITY,  8.0,  5, "每层攻速 +2%（迅捷）", "stat", {"aspd_up": 0.02}],
	["eq_soul_stack",   "噬魂·叠层", Kind.ATTACK,   12.0, 15, "每层攻击力 +2%（噬魂/灵魂）", "stat", {"atk_up": 0.02}],
	# 复用现成链路比新造一套更不容易出错。
	["ps_vitality",     "被动·坚韧体魄", Kind.SHIELD,   0.0, 0, "最大生命 +8%，护甲 +5%", "stat", {"hp_up": 0.08, "def_up": 0.05}],
	["ps_swift",        "被动·迅捷步伐", Kind.MOBILITY, 0.0, 0, "移速 +5%，冷却缩减 +10%", "stat", {"spd_up": 0.05, "cdr_up": 0.10}],
	["ps_fortune",      "被动·寻宝直觉", Kind.GENERIC,  0.0, 0, "金币获取 +10%，掉落率 +5%", "special", {"gold_gain": 0.10, "drop_rate": 0.05}],
	["ps_weapon_master","被动·武器专精", Kind.ATTACK,   0.0, 0, "攻击力 +5%", "stat", {"atk_up": 0.05}],
	["ps_armor_train",  "被动·护甲训练", Kind.SHIELD,   0.0, 0, "护甲 +8%", "stat", {"def_up": 0.08}],
	["ps_crit_train",   "被动·暴击训练", Kind.ATTACK,   0.0, 0, "暴击率 +5%", "stat", {"crit_up": 0.05}],
	["ps_cdr_train",    "被动·冷却缩减", Kind.GENERIC,  0.0, 0, "技能冷却 -5%", "stat", {"cdr_up": 0.05}],
	["ps_elem_resist",  "被动·元素抗性", Kind.SHIELD,   0.0, 0, "所有元素抗性 +5%", "stat", {"elem_resist": 0.05}],
	["ps_pickup",       "被动·拾取范围", Kind.GENERIC,  0.0, 0, "拾取范围 +20%", "special", {"pickup_range": 0.20}],
	["ps_exp",          "被动·经验获取", Kind.GENERIC,  0.0, 0, "经验获取 +8%", "special", {"exp_gain": 0.08}],
	# ---------- 装备技能的自身增益（装备参考2：buff 类技能的效果载体） ----------
	#
	# **为什么需要它们**：`SkillSystem._cast_buff` 是空实现——
	# buff 类技能的效果**完全靠 `self_buffs` 字段**承载（见 `_apply_self_buffs`）。
	# 装备技能表若只写 kind="buff" 而没有 self_buffs，放技能就"扣了冷却但没效果"。
	["shield_up",   "护盾·技能", Kind.SHIELD,  8.0, 0, "技能给予的护盾", "special", {"shield": 0.20}],
	["haste_self",  "急速·技能", Kind.ATTACK,  5.0, 0, "技能给予的攻速提升", "stat", {"aspd_up": 0.30}],
	["swift_self",  "疾行·技能", Kind.MOBILITY, 5.0, 0, "技能给予的移速提升", "stat", {"spd_up": 0.25}],
	["atk_up_self", "强化·技能", Kind.ATTACK,  6.0, 0, "技能给予的攻击提升", "stat", {"atk_up": 0.15}],
	["guard_self",  "守护·技能", Kind.SHIELD,  5.0, 0, "技能给予的减伤", "stat", {"dmg_taken_down": 0.20}],
	["heal_self",   "治愈·技能", Kind.RESOURCE, 0.0, 0, "技能给予的回复（实际量由技能 heal_pct 决定）", "special", {"regen": 0.0}],
	# ---------- 技能自身增益的**通用载体** ----------
	#
	# 上面 6 条把数值**写死在表里**（0.30 / 0.25 / 0.15），但装备技能是
	# **每件数值不同**的：「加速」移速 +25%、「时空加速」+30%、「疾风步」
	# +60%。若按数值造词条，133 条技能要造上百个近义词条。
	#
	# 故改用这一条**结构词条**：params 里列全所有可能的自身增益键
	#（全 0），实际数值由 `BuffHolder.apply` 的 `override_params` 传入
	#（见 `SkillSystem._apply_extra_self_buffs`）。
	# `duration` 写 1.0 只是占位——调用方必须传 `override_dur`。
	["eq_skill_buff", "技能增益", Kind.GENERIC, 1.0, 0, "装备技能提供的限时自身增益（数值由技能指定）", "stat",
		{"spd_up": 0.0, "aspd_up": 0.0, "atk_up": 0.0, "dmg_taken_down": 0.0,
		 "dodge_up": 0.0, "reflect_up": 0.0, "block_all": false}],
	# 血怒的「以血换攻」载体（策划 3.x）：
	# 每秒失去 `hp_drain_pct` × 最大生命，`atk_from_drain` 为真时
	# 把失去量**等量**加进攻击力（见 BuffHolder.tick 的 drain 分支）。
	["eq_blood_rage", "以血换攻", Kind.ATTACK, 1.0, 0, "每秒失去最大生命的一部分换等量攻击力", "drain",
		{"hp_drain_pct": 0.01, "atk_from_drain": true}],
]
## 单独列出是为了让「词条表 == 文档 81 条」这条不变量仍可被测试校验。
## 不属于策划文档 81 条的**扩展词条**（技能专用 + 装备叠层）。
##
## `doc_ids()` = 全部 − 本表。测试用「表 == 文档 81 条」做双向覆盖校验，
## 故任何新增的**非文档**词条都必须登记在这里，否则那条校验会失败
##（2026-09-22 加装备叠层词条时踩到）。
const SKILL_ONLY_IDS := ["rage_haste", "rage_fury", "rage_dance_aspd",
	"rage_dance_true", "chain_weak", "flame_mark", "void_stigma",
	"break_limit_state", "forest_domain_self", "forest_domain_foe",
	"judge_mark", "light_layer", "dark_layer", "verdict_balance",
	"mire_deep", "mire_deepest",
	# 装备叠层型（装备参考2 的成长类词条，见 BUFFS 表尾）
	"eq_atk_stack", "eq_def_stack", "eq_aspd_stack", "eq_crit_stack",
	"eq_crd_stack", "eq_spd_stack", "eq_reduce_stack", "eq_swift_stack",
	"eq_soul_stack",
	# 被动技能（装备参考2：常驻生效，不上技能槽）
	"ps_vitality", "ps_swift", "ps_fortune", "ps_weapon_master",
	"ps_armor_train", "ps_crit_train", "ps_cdr_train", "ps_elem_resist",
	"ps_pickup", "ps_exp",
	# 装备技能的自身增益（buff 类技能的效果载体，见 BUFFS 表尾）
	"shield_up", "haste_self", "swift_self", "atk_up_self", "guard_self", "heal_self",
	"eq_skill_buff", "eq_blood_rage"]

## 分册「文档章节」索引（第 3/4/5 章的小节分组，与上方 Kind 是**两个维度**）。
## Kind 是运行时语义（如「缠绕」归硬控，便于 is_controlled 判定），
## 此处是策划文档的分节（「缠绕」在 3.2 减速型）。二者不该混为一谈，
## 但数据必须能按文档分节核对，故单列此表。
## 合计 5+6+8+10+5+4 + 4+9+4+5 + 21 = 81
const DOC_SECTIONS := {
	"3.1 持续伤害型": ["burn", "poison_rot", "tear", "bleed", "curse_burn"],
	"3.2 减速/减速攻型": ["frost", "erosion", "entangle", "thorn_slow", "dull", "mire"],
	"3.3 硬控型": ["freeze", "paralyze", "stun", "knockup", "silence", "disarm", "taunt", "fear"],
	"3.4 易伤/破甲型": ["static_charge", "judgement", "dark_erosion", "brand", "mark", "armor_down", "armor_break", "frailty", "charm", "expose"],
	"3.5 减益/削弱型": ["enfeeble", "weakness", "immolate", "blind", "fatigue"],
	"3.6 击退/位移型": ["pull", "knockback", "drag", "shadow_dash"],
	"4.1 护盾/防御型": ["shield", "light_shield", "iron_body", "adamant"],
	"4.2 攻击/输出型": ["war_cry", "blood_rage", "spell_flame", "focus", "supreme", "break_limit", "forest_wrath", "forest_bless", "verdict"],
	"4.3 移动/机动型": ["shadow_trace", "shadow_form", "wind_step", "gale"],
	"4.4 资源/回复型": ["bloodbath", "shadow_hunt", "element_affinity", "arcane_echo", "execute"],
	"第5章 通用词条池": [
		"gen_atk_up", "gen_def_up", "gen_hp_up", "gen_spd_up", "gen_aspd_up",
		"gen_crit_up", "gen_crd_up", "gen_ap_up", "gen_cdr_up", "gen_rng_up",
		"gen_control_1", "gen_control_2", "gen_control_3", "gen_control_4",
		"gen_fx_1", "gen_fx_2", "gen_fx_3", "gen_fx_4",
		"gen_sustain_1", "gen_sustain_2", "gen_sustain_3",
	],
}

## 某文档分节包含的词条 id
static func section_ids(section: String) -> Array:
	return DOC_SECTIONS.get(section, [])


static func _index() -> Dictionary:
	var out := {}
	for row in BUFFS:
		out[str(row[0])] = row
	return out

static var _cached: Dictionary = {}

## **运行时注册的装备触发词条**（不进 BUFFS 常量表）。
##
## 为什么动态注册：装备触发词条的**数值来自装备数据**（如「每层防御 +1%」
## 的 1% 是每件装备各自的值），预置在表里就得为每个可能的值开一条。
## 故这里按需注册，与常量表共用同一套查询接口。
##
## 它们**不属于策划文档的 81 条**，故不计入 `doc_ids()`——
## 否则「表 == 文档」的双向覆盖校验会失败。
static var _dynamic: Dictionary = {}


## 注册一条装备触发的叠层词条（幂等：同 id 重复注册只更新数值）。
##
## 行格式与 BUFFS 一致：`[id, 名, Kind, 时长, 最大层数, 描述, impl, params]`，
## 这样 `get_buff` / `impl_of` / `params_of` / `_sync_modifier` 全部无需改动。
static func register_equipment_stack(id: String, stat: int, value: float,
		duration: float, max_stacks: int) -> void:
	if id.is_empty():
		return
	# stat → params 键（复用 _sync_modifier 认得的那些键名）
	var p := {}
	var key := EquipmentDB.special_out_key(stat)
	if key.is_empty():
		# 面板属性：按 AttributeSystem.Stat 反查键名
		for name in AttributeSystem.STAT_BY_NAME:
			if int(AttributeSystem.STAT_BY_NAME[name]) == stat:
				key = name + "_up"
				break
	else:
		# 扩展修饰量：_sync_modifier 不认这些键，故走 special 通道。
		# 但叠层词条的价值就在于「层数 × 数值」同步到面板——
		# 扩展量不在面板上，故这里退化为只记层数（由 special_modifiers 读）。
		pass
	if not key.is_empty():
		p[key] = value
	var row := [id, "装备·%s" % id, Kind.GENERIC, duration, max_stacks,
		"装备触发的叠层词条", "stat" if not p.is_empty() else "special", p]
	_dynamic[id] = row
	# 已缓存过则同步刷新，避免注册后查不到
	if not _cached.is_empty():
		_cached[id] = row


## 按 id 取定义行
static func get_buff(id: String) -> Array:
	if _cached.is_empty():
		_cached = _index()
	return _cached.get(id, _dynamic.get(id, []))

## 全部词条 id
static func all_ids() -> Array:
	if _cached.is_empty():
		_cached = _index()
	return _cached.keys()


## 全部词条 id（**排除技能专用**）——即策划文档的 81 条体系。
## 测试用它与 DOC_SECTIONS 做双向覆盖校验：技能词条不在文档里，
## 混在一起会让「表 == 文档」这条不变量失去意义。
static func doc_ids() -> Array:
	var out: Array = []
	for id in all_ids():
		if not (id in SKILL_ONLY_IDS):
			out.append(id)
	return out

## 按分类取词条
static func by_kind(kind: int) -> Array:
	var out: Array = []
	for row in BUFFS:
		if int(row[2]) == kind:
			out.append(row)
	return out

## 该词条的实现类型（stat/dot/control/special）
static func impl_of(id: String) -> String:
	var row := get_buff(id)
	return str(row[6]) if not row.is_empty() else ""

## 效果参数
static func params_of(id: String) -> Dictionary:
	var row := get_buff(id)
	return row[7] if row.size() > 7 else {}

## 本轮真正生效的实现类型（其余为登记）
static func implemented_types() -> Array:
	return ["stat", "dot"]
