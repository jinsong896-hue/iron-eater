class_name GameBalance
extends RefCounted
## 数值基线：《ai/demo1》最终 Demo（V17 Gold Build）冻结数值 + 第一层怪物/技能配置
## 作为 HUD / 技能栏 / 未来的技能系统的单一数据来源，避免散落在各处。

# ---- Boss 基线（demo1 balance：狱卒·卡恩 HP 1500 两阶段）----
const BOSS := {
	"name": "狱卒·卡恩",
	"hp": 1500.0,
	"phase": 2,
	"half_summon": true,
}

# ---- 技能基线（demo1：火焰斩 / 雷击 / 毒刃，元素叠层；demo2：Q 火焰斩 / E 吞噬）----
# 键位说明：本项目 WASD 为移动（W 已占用），E 保留给“吞噬掉落物”（demo2），
# 故三个演示技能用 Q / F / G。
# kind：aoe 范围 / single 单体 / dot 持续伤害；mult 相对攻击力的倍率；range 单位 px。
const DEMO_SKILLS := [
	{"id": "fire_slash", "key": "Q", "name": "火焰斩", "element": "fire", "cooldown": 3.0,
	 "kind": "aoe", "mult": 1.6, "range": 180.0,
	 "desc": "近战范围火焰斩击（攻击力 ×1.6，范围 180px）"},
	{"id": "lightning", "key": "F", "name": "雷击", "element": "lightning", "cooldown": 4.0,
	 "kind": "single", "mult": 2.2, "range": 420.0,
	 "desc": "锁定最近敌人单体雷伤（攻击力 ×2.2）"},
	{"id": "poison_blade", "key": "G", "name": "毒刃", "element": "poison", "cooldown": 5.0,
	 "kind": "dot", "mult": 0.8, "range": 160.0, "dot_dps": 0.25, "dot_duration": 3.0,
	 "desc": "近战挥击并附加毒蚀（攻击力 ×0.8 + 每秒 0.25×攻击力，持续 3 秒）"},
]

# 元素层数上限（demo1：灼烧 50 / 静电 10 / 毒蚀 30）
const ELEMENT_MAX_STACKS := {"fire": 50, "lightning": 10, "poison": 30}
const ELEMENT_COLORS := {
	"fire": Color(0.96, 0.42, 0.22),
	"lightning": Color(0.55, 0.72, 1.0),
	"poison": Color(0.55, 0.85, 0.35),
}
const ELEMENT_NAMES := {"fire": "灼烧", "lightning": "静电", "poison": "毒蚀"}


static func skill_by_id(skill_id: String) -> Dictionary:
	for s in DEMO_SKILLS:
		if s.id == skill_id:
			return s
	return {}
