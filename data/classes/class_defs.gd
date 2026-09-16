class_name ClassDefs
extends RefCounted
## 职业 / 形态 / 技能定义表 —— 《角色设计分册》
##
## **本文件是角色系统的唯一真相源**：5 职业 × 5 形态 × 每形态 2 技能。
## 表格风格与 BuffDefs / MonsterDB 一致（纯代码静态数据，不用 .tres）——
## 理由同那两处：策划数值还在迭代，代码表改起来比 .tres 快且能进版本对比。
##
## 解锁条件（策划 2 章统一口径）：
##   初始形态默认解锁；进阶 1 = 通关第 3 层；进阶 2 = 第 6 层；
##   进阶 3 = 第 8 层；终极形态 = 第 9 层。
##
## ⚠ 当前进度：**战士 5 形态全实装**，其余 4 职业留骨架（信息已录，
## 技能 kind 已归类，但数值与机制待逐轮填充）。见 _pending_classes()。

## 形态槽位：0 初始 / 1 进阶1 / 2 进阶2 / 3 进阶3 / 4 终极
const FORM_SLOTS := 5

## 各形态槽位对应的解锁层（0 = 默认解锁）
const UNLOCK_FLOOR := [0, 3, 6, 8, 9]

## 职业表：每项 { id, name, resource, desc, forms: [ {…} × 5 ] }
##
## 形态项字段：
##   name          形态名
##   gain          专属增益（说明文本 + mods 属性修正 + special 特殊字段）
##   mods          [{stat, flat, percent}] 直接进 AttributeSystem
##   special       需代码处理的特殊增益（如"远程伤害 -50%"）
##   skills        [ {…} × 2 ] 技能项，见下方技能字段
##   start_gear    初始装备（模板 id 列表；空 = 不更换）
##
## 技能项字段：
##   id / name / kind / cooldown / cost（资源消耗）
##   damage_mult   伤害倍率（相对面板 ATK）
##   reach / radius / range      几何参数（近战距离 / AOE 半径 / 投射距离）
##   dash_dist     位移距离（kind=dash）
##   knockback     击退力
##   element       附带元素（"" = 纯物理）
##   self_buffs    [{id, stacks}] 施放时给自身挂的词条
##   target_buffs  [{id, duration}] 命中时给目标挂的词条
##   duration      持续型技能的时长（如血怒）
##   desc          策划原文描述
const CLASSES := {
	"warrior": {
		"id": "warrior", "name": "战士 · 狂怒之刃",
		"resource": "warrior",
		"desc": "受击/造成伤害积攒怒气，强化技能。近战重装，正面硬刚。",
		"forms": [
			# ---------- 初始：狂战士 ----------
			{
				"name": "狂战士",
				"gain": "近战武器伤害 +20%",
				"mods": [],
				"special": {"melee_dmg_pct": 0.20},
				"start_gear": ["W01"],
				"skills": [],
			},
			# ---------- 进阶1：壁垒 ----------
			{
				"name": "壁垒",
				"gain": "远程伤害 -50%；近战伤害 -20%",
				"mods": [],
				"special": {"ranged_dmg_pct": -0.50, "melee_dmg_pct": -0.20},
				"start_gear": ["C01", "S01", "W01"],
				"skills": [
					{
						"id": "shield_charge", "name": "撞击", "kind": "dash",
						"cooldown": 2.0, "cost": 20.0,
						"damage_mult": 1.2, "dash_dist": 5.0,
						"reach": 1.6, "knockback": 3.0,
						"desc": "向前冲刺，对沿途所有敌人造成伤害并击退",
					},
					{
						"id": "elbow_strike", "name": "肘击", "kind": "cone",
						"cooldown": 3.0, "cost": 25.0,
						"damage_mult": 1.5, "reach": 3.0, "half_angle": 60.0,
						"knockback": 5.0, "knockup": true,
						"desc": "前方扇形伤害并击飞；击飞的敌人撞到其他敌人时双方再受一次伤害",
					},
				],
			},
			# ---------- 进阶2：狂怒 ----------
			{
				"name": "狂怒",
				"gain": "武器攻速在按武器攻击力增加的基础上额外 +2；越残越疯",
				"mods": [{"stat": "aspd", "flat": 2.0, "percent": 0.0}],
				"special": {},
				"start_gear": ["C02", "W06"],
				"skills": [
					{
						"id": "stomp", "name": "跺脚", "kind": "aoe",
						"cooldown": 4.0, "cost": 30.0,
						"damage_mult": 1.4, "radius": 4.0, "knockback": 4.0,
						"desc": "周围范围伤害并击退",
					},
					{
						"id": "blood_rage", "name": "血怒", "kind": "buff",
						"cooldown": 10.0, "cost": 35.0,
						"duration": 8.0,
						# 每秒失去 1% 最大生命、按失去量换等量攻击力；攻速/移速/攻击 +50%/30%
						"hp_drain_pct": 0.01, "atk_from_drain": true,
						"self_buffs": [
							{"id": "rage_haste", "stacks": 1},
							{"id": "rage_fury", "stacks": 1},
						],
						"desc": "每秒失去 1% 最大生命换等量攻击力；攻击 +30%、移速 +50%、攻速 +50%",
					},
				],
			},
			# ---------- 进阶3：锁链 ----------
			{
				"name": "锁链",
				"gain": "攻击改为投掷锁链武器：射程大增、攻击力 +60%、攻速 +30%、穿刺无视 50% 护甲",
				"mods": [
					{"stat": "atk", "flat": 0.0, "percent": 0.60},
					{"stat": "aspd", "flat": 0.0, "percent": 0.30},
					{"stat": "rng", "flat": 3.0, "percent": 0.0},
				],
				"special": {"armor_pierce": 0.50},
				"start_gear": ["C03", "W13"],
				"skills": [
					{
						"id": "chain_pull", "name": "拉拽", "kind": "pull",
						"cooldown": 3.0, "cost": 25.0,
						"damage_mult": 1.0, "range": 8.0,
						"target_buffs": [{"id": "chain_weak", "duration": 3.0}],
						"desc": "丢出锁链：伤害首个敌人、施加 -30% 攻速/移速，并把角色拉拽到其面前",
					},
					{
						"id": "whirlwind", "name": "旋风斩", "kind": "aoe",
						"cooldown": 6.0, "cost": 40.0,
						"damage_mult": 1.8, "radius": 5.0, "knockback": 2.0,
						"desc": "甩出链武器，对周围大范围敌人造成伤害",
					},
				],
			},
			# ---------- 终极：解放者 ----------
			{
				"name": "解放者",
				"gain": "所有攻击附带 50% 生命偷取；溢出治疗 60% 转护盾（上限 100% 生命）；双形态切换",
				"mods": [],
				"special": {"lifesteal": 0.50, "overflow_to_shield": 0.60},
				"start_gear": [],
				"skills": [
					{
						"id": "blood_sacrifice", "name": "鲜血献祭", "kind": "aoe",
						"cooldown": 12.0, "cost": 15.0,
						"hp_cost_pct": 0.15,
						"damage_mult": 2.0, "radius": 4.0,
						"heal_per_hit_pct": 0.05,
						"desc": "消耗 15% 当前生命，对 4 米敌人造成（攻击力×2.0）伤害，每命中 1 敌回复 5% 已损失生命",
					},
					{
						"id": "blood_dance", "name": "血刃狂舞", "kind": "buff",
						"cooldown": 18.0, "cost": 30.0,
						"duration": 6.0,
						"self_buffs": [
							{"id": "rage_dance_aspd", "stacks": 1},
							{"id": "rage_dance_true", "stacks": 1},
						],
						"desc": "进入鲜血狂乱 6 秒：攻速 +60%，每次攻击附带（攻击力×0.3）真实伤害",
					},
				],
			},
		],
	},
	# ---------- 其余 4 职业：骨架（信息已录，数值与 kind 待逐轮填充）----------
	"mage": {
		"id": "mage", "name": "法师 · 元素使",
		"resource": "mage",
		"desc": "自动回蓝。远程风筝，技能爆发。",
		"forms": [
			{"name": "元素使", "gain": "待实装", "mods": [], "special": {}, "start_gear": ["W11"], "skills": []},
			{"name": "咒术师", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "咒焰使", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "咒术共鸣", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "虚空古神化身", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
		],
	},
	"hunter": {
		"id": "hunter", "name": "猎人 · 暗影追猎者",
		"resource": "hunter",
		"desc": "连击/暴击积攒专注。走 A 拉扯，暴击压制。",
		"forms": [
			{"name": "追猎者", "gain": "待实装", "mods": [], "special": {}, "start_gear": ["W09"], "skills": []},
			{"name": "斥候", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "暗刃", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "鹰眼", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "森之选召", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
		],
	},
	"judge": {
		"id": "judge", "name": "判官 · 渡鸦",
		"resource": "judge",
		"desc": "攻击附加法术伤害；满裁决自动触发终局裁决。",
		"forms": [
			{"name": "渡鸦", "gain": "待实装", "mods": [], "special": {}, "start_gear": ["W01"], "skills": []},
			{"name": "锁链判官", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "影子判官", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "暗影主宰", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "光暗审裁", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
		],
	},
	"monk": {
		"id": "monk", "name": "武僧 · 破拳",
		"resource": "monk",
		"desc": "不装备武器，连击体系驱动。连击续航，极限爆发。",
		"forms": [
			{"name": "拳师", "gain": "待实装", "mods": [], "special": {"no_weapon": true}, "start_gear": [], "skills": []},
			{"name": "铁身", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "疾风", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "破极", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
			{"name": "无我极境", "gain": "待实装", "mods": [], "special": {}, "start_gear": [], "skills": []},
		],
	},
}


## 取职业定义（未知职业返回空字典，调用方需判空）
static func get_class_def(class_id: String) -> Dictionary:
	return CLASSES.get(class_id, {})


## 取形态定义（越界钳制；未知职业返回空）
static func get_form(class_id: String, form_slot: int) -> Dictionary:
	var c := get_class_def(class_id)
	if c.is_empty():
		return {}
	var forms: Array = c.get("forms", [])
	if forms.is_empty():
		return {}
	return forms[clampi(form_slot, 0, forms.size() - 1)]


## 形态解锁层（0 = 默认解锁）
static func unlock_floor_of(form_slot: int) -> int:
	return int(UNLOCK_FLOOR[clampi(form_slot, 0, UNLOCK_FLOOR.size() - 1)])


## 玩家当前层数下，可用的最高形态槽位。
## 策划 2 章：初始默认；进阶 1 通关 3 层；进阶 2 第 6 层；进阶 3 第 8 层；终极第 9 层。
## 「通关 N 层」= 层数 > N，故 cleared_floor=3（已通关第 3 层）时解锁槽位 1。
static func max_available_form(cleared_floor: int) -> int:
	var best := 0
	for slot in range(UNLOCK_FLOOR.size()):
		if cleared_floor >= int(UNLOCK_FLOOR[slot]):
			best = slot
	return best


## 全部可玩职业 id（供主菜单列出）
static func class_ids() -> Array:
	return CLASSES.keys()


## 职业显示名
static func class_name_of(class_id: String) -> String:
	return str(get_class_def(class_id).get("name", class_id))


## 尚未实装的职业（技能为空的都算；供测试与进度展示）
static func pending_classes() -> Array:
	var out: Array = []
	for cid in CLASSES:
		var c: Dictionary = CLASSES[cid]
		var has_skill := false
		for f in c.get("forms", []):
			if not (f.get("skills", []) as Array).is_empty():
				has_skill = true
				break
		if not has_skill:
			out.append(cid)
	return out


## 收集某形态的全部技能（供 HUD 技能条与 SkillSystem 查询）
static func skills_of(class_id: String, form_slot: int) -> Array:
	var f := get_form(class_id, form_slot)
	return f.get("skills", [])


## 全局技能检索：按 id 找 {skill, form_slot, class_id}（找不到返回空）
static func find_skill(skill_id: String) -> Dictionary:
	for cid in CLASSES:
		var forms: Array = CLASSES[cid].get("forms", [])
		for slot in range(forms.size()):
			for sk in forms[slot].get("skills", []):
				if str(sk.get("id", "")) == skill_id:
					return {"skill": sk, "form_slot": slot, "class_id": cid}
	return {}
