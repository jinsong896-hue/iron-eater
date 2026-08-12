class_name GameCatalog
extends RefCounted
## 新游戏配置数据目录：《开始页面相关.md》——五职业/模式/难度/形态解锁

const CLASSES := [
	{"id": "warrior", "name": "战士", "title": "狂怒之刃", "resource": "怒气", "desc": "近战重装，正面硬刚，通过攻击与受击积累怒气。", "unlocked": true, "difficulty": 2, "tags": "近战 / 生存 / 爆发", "recommended": true},
	{"id": "mage", "name": "法师", "title": "元素使", "resource": "魔力", "desc": "远程法系，技能爆发，高消耗高爆发。", "unlocked": true, "difficulty": 3, "tags": "远程 / 法术 / 爆发", "recommended": false},
	{"id": "hunter", "name": "猎人", "title": "暗影追猎者", "resource": "专注", "desc": "远程敏捷，走位拉扯，连续命中提升暴击。", "unlocked": true, "difficulty": 3, "tags": "远程 / 敏捷 / 走位", "recommended": false},
	{"id": "judge", "name": "判官", "title": "渡鸦", "resource": "裁决", "desc": "近战法附，攻击附加法术伤害，满裁决触发终局裁决。", "unlocked": true, "difficulty": 4, "tags": "近战 / 法附 / 裁决", "recommended": false},
	{"id": "monk", "name": "武僧", "title": "破拳", "resource": "气劲", "desc": "拳脚连击，不装备武器，连击体系驱动。", "unlocked": true, "difficulty": 3, "tags": "近战 / 连击 / 无武器", "recommended": false},
]

const DIFFICULTIES := [
	{"id": "easy", "name": "简单", "desc": "怪物伤害降低，适合熟悉职业与装备系统。", "mult": 0.8, "detail": "敌人生命 −20%\n敌人伤害 −20%\n适合熟悉职业与装备系统。"},
	{"id": "normal", "name": "普通", "desc": "推荐难度，按照标准数值体验游戏。", "mult": 1.0, "detail": "敌人生命 / 伤害 标准值\n推荐难度，按照标准数值体验游戏。"},
	{"id": "hard", "name": "困难", "desc": "怪物伤害、生命和精英出现率提高。", "mult": 1.3, "detail": "敌人生命 +30%\n敌人伤害 +30%\n精英出现率提高，资源压力上升。"},
]

const MODES := [
	{"id": "dungeon", "name": "地牢模式", "desc": "肉鸽短平快，单局独立，当前优先开发。", "locked": false, "locked_reason": ""},
	{"id": "story", "name": "剧情模式", "desc": "20 小时以上线性剧情体验。", "locked": true, "locked_reason": "剧情模式将在后续版本开放"},
]

const FORMS := {
	"warrior": ["狂战士", "壁垒", "狂怒", "锁链", "解放者"],
	"mage": ["元素使", "咒术师", "咒焰使", "咒术共鸣", "虚空古神化身"],
	"hunter": ["追猎者", "斥候", "暗刃", "鹰眼", "森之选召"],
	"judge": ["渡鸦", "锁链判官", "影子判官", "暗影主宰", "光暗审裁"],
	"monk": ["拳师", "铁身", "疾风", "破极", "无我极境"],
}


static func class_info(class_id: String) -> Dictionary:
	for c in CLASSES:
		if c.id == class_id:
			return c
	return CLASSES[0]


static func difficulty_info(difficulty_id: String) -> Dictionary:
	for d in DIFFICULTIES:
		if d.id == difficulty_id:
			return d
	return DIFFICULTIES[1]


static func mode_info(mode_id: String) -> Dictionary:
	for m in MODES:
		if m.id == mode_id:
			return m
	return MODES[0]
