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
				"start_gear": ["A06", "W05", "W01"],
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
				"start_gear": ["A05", "W06"],
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
				"start_gear": ["A12", "W08"],
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
			# ---------- 初始：元素使 ----------
			{
				"name": "元素使",
				"gain": "技能范围 +15%",
				"mods": [],
				"special": {"skill_range_pct": 0.15},
				"start_gear": ["W11"],
				"skills": [],
			},
			# ---------- 进阶1：咒术师 ----------
			{
				"name": "咒术师",
				"gain": "每次施法后回蓝速度 +20%（可叠 3 层，最高 +60%）；施法命中返还 15% 消耗",
				"mods": [],
				"special": {"mana_regen_stack": 0.20, "cast_refund_pct": 0.15},
				"start_gear": ["A04", "W02"],
				"skills": [
					{
						"id": "arcane_siphon", "name": "奥术汲取", "kind": "projectile",
						"cooldown": 3.0, "cost": 20.0,
						"damage_mult": 0.8, "speed": 14.0, "lifetime": 1.6,
						"element": "fire", "restore_resource": 10.0,
						"desc": "造成（法强×0.8）伤害，恢复 10 点魔力，目标有负面状态额外 +5 点",
					},
					{
						"id": "mana_convert", "name": "灵能转换", "kind": "buff",
						"cooldown": 8.0, "cost": 0.0,
						"hp_cost_pct": 0.10, "restore_resource": 30.0,
						"duration": 3.0,
						"self_buffs": [{"id": "gen_aspd_up", "stacks": 1}],
						"desc": "消耗 10% 当前生命，立即恢复 30 点魔力，3 秒内施法速度 +25%",
					},
				],
			},
			# ---------- 进阶2：咒焰使 ----------
			{
				"name": "咒焰使",
				"gain": "每次施法 +1 层咒焰（每层 +8% 伤害、+5% 施法速度，最多 6 层，持续 5 秒）",
				"mods": [],
				"special": {"flame_stack_per_cast": true},
				"start_gear": ["A05", "W11"],
				"skills": [
					{
						"id": "flame_burst", "name": "咒焰冲击", "kind": "detonate",
						"cooldown": 6.0, "cost": 25.0,
						"range": 12.0, "detonate_buff": "flame_mark",
						"per_stack_mult": 1.2, "full_stack_mult": 2.4, "full_stack_count": 4,
						"stack_buff_per_cast": "flame_mark",
						"desc": "清空所有层数，造成（法强×1.2 + 层数×法强×0.4）伤害，层数≥4 时额外范围爆炸",
					},
					{
						"id": "flame_infuse", "name": "咒焰灌注", "kind": "buff",
						"cooldown": 10.0, "cost": 30.0,
						"duration": 6.0, "stack_buff_per_cast": "flame_mark",
						"self_buffs": [{"id": "gen_ap_up", "stacks": 1}],
						"desc": "消耗所有层数，使下一次法术伤害 ×（1.5 + 层数×0.1），最高 ×2.1",
					},
				],
			},
			# ---------- 进阶3：咒术共鸣 ----------
			{
				"name": "咒术共鸣",
				"gain": "法术范围 +30%；20% 概率触发法术共鸣（对周围 4 米敌人造成 50% 伤害副本）",
				"mods": [],
				"special": {"skill_range_pct": 0.30, "resonance_chance": 0.20},
				"start_gear": ["A07", "W11"],
				"skills": [
					{
						"id": "resonance_burst", "name": "共鸣引爆", "kind": "aoe",
						"cooldown": 8.0, "cost": 30.0,
						"damage_mult": 1.4, "radius": 4.5,
						"target_buffs": [{"id": "brand", "duration": 4.0}],
						"desc": "标记目标 4 秒，期间对其造成的所有法术伤害复制 40% 扩散至周围 3 米",
					},
					{
						"id": "range_overload", "name": "范围过载", "kind": "buff",
						"cooldown": 12.0, "cost": 0.0,
						"hp_cost_pct": 0.0, "duration": 6.0,
						"self_buffs": [{"id": "gen_rng_up", "stacks": 1},
							{"id": "gen_ap_up", "stacks": 1}],
						"desc": "消耗 30% 当前魔力，使下一次法术范围 ×2.0、伤害 ×1.3，命中≥3 敌时返还 50% 消耗",
					},
				],
			},
			# ---------- 终极：虚空古神化身 ----------
			{
				"name": "虚空古神化身",
				"gain": "每次施法给目标叠 1 层虚空印记（最多 5 层，受伤 +10%/层）；技能冷却 -30%、魔力回复 +150%",
				"mods": [{"stat": "cdr", "flat": 0.30, "percent": 0.0}],
				"special": {"void_stigma_per_cast": true, "mana_regen_up": 1.5},
				"start_gear": [],
				"skills": [
					{
						"id": "void_annihilate", "name": "虚空湮灭", "kind": "detonate",
						"cooldown": 15.0, "cost": 50.0,
						"range": 14.0, "detonate_buff": "void_stigma",
						"per_stack_mult": 3.5, "full_stack_mult": 3.5, "full_stack_count": 5,
						"target_buffs": [{"id": "silence", "duration": 4.0}],
						"stack_buff_per_cast": "void_stigma",
						"desc": "引爆所有裂隙，每道造成（法强×3.5）范围伤害，沉默 4 秒",
					},
					{
						"id": "abyss_whisper", "name": "深渊低语", "kind": "aoe",
						"cooldown": 9.0, "cost": 40.0,
						"damage_mult": 2.0, "radius": 4.5,
						"stack_buff_per_cast": "void_stigma",
						"desc": "以虚空之力冲击周围，施加印记并造成（法强×2.0）伤害",
					},
				],
			},
		],
	},
	"hunter": {
		"id": "hunter", "name": "猎人 · 暗影追猎者",
		"resource": "hunter",
		"desc": "连击/暴击积攒专注。走 A 拉扯，暴击压制。",
		"forms": [
			# ---------- 初始：追猎者 ----------
			{
				"name": "追猎者",
				"gain": "远近切换无冷却；切换后移速 +10%（持续 2 秒）",
				"mods": [],
				"special": {"free_weapon_swap": true},
				"start_gear": ["W09", "W02"],
				"skills": [],
			},
			# ---------- 进阶1：斥候 ----------
			{
				"name": "斥候",
				"gain": "移动射击移速惩罚取消；脱战 3 秒后移速 +30%；翻滚后免疫下一次攻击",
				"mods": [{"stat": "spd", "flat": 0.0, "percent": 0.30}],
				"special": {"out_of_combat_spd": 0.30, "dodge_immune_next": true},
				"start_gear": ["A01", "W09"],
				"skills": [
					{
						"id": "scout_dash", "name": "疾步", "kind": "dash",
						"cooldown": 4.0, "cost": 20.0,
						"damage_mult": 1.0, "dash_dist": 4.0, "reach": 1.8,
						"target_buffs": [{"id": "thorn_slow", "duration": 3.0}],
						"desc": "向前滑铲 4 米，无敌帧 0.25 秒，结束时扇形伤害 + 减速 50%（3 秒）",
					},
					{
						"id": "survival_instinct", "name": "生存本能", "kind": "buff",
						"cooldown": 12.0, "cost": 30.0,
						"duration": 4.0,
						"heal_pct_max": 0.20,
						"self_buffs": [{"id": "gale", "stacks": 1}],
						"desc": "立即恢复 20% 最大生命值 + 移速 40%（4 秒）；生命＜40% 时被动自动触发（每局限 1 次）",
					},
				],
			},
			# ---------- 进阶2：暗刃 ----------
			{
				"name": "暗刃",
				"gain": "所有攻速 +30%；背刺伤害 ×2.0；暴击额外 +2 专注",
				"mods": [{"stat": "aspd", "flat": 0.0, "percent": 0.30}],
				"special": {"backstab_mult": 2.0},
				"start_gear": ["A05", "W02"],
				"skills": [
					{
						"id": "shadow_assault_h", "name": "暗影突袭", "kind": "teleport",
						"cooldown": 4.0, "cost": 25.0,
						"range": 8.0, "behind_offset": 1.1, "damage_mult": 1.2,
						"target_buffs": [{"id": "tear", "duration": 4.0}],
						"desc": "突进 4 米，120% 伤害，从背后命中时伤害 ×2.5 并施加撕裂（15/秒，4 秒）",
					},
					{
						"id": "blade_storm", "name": "旋刃风暴", "kind": "multi_hit",
						"cooldown": 6.0, "cost": 35.0,
						"range": 3.0, "hit_count": 2, "damage_mult": 0.75,
						"desc": "旋转双匕，周围 3 米敌人受到 2 次伤害（每次普攻 75%），可移动",
					},
				],
			},
			# ---------- 进阶3：鹰眼 ----------
			{
				"name": "鹰眼",
				"gain": "所有武器射程 +60%；所有攻击附带范围穿透（身后 2 米直线 40% 伤害）",
				"mods": [{"stat": "rng", "flat": 0.0, "percent": 0.60}],
				"special": {"pierce_line": 0.40},
				"start_gear": ["A02", "W09"],
				"skills": [
					{
						"id": "heartseeker", "name": "穿心箭", "kind": "projectile",
						"cooldown": 5.0, "cost": 35.0,
						"damage_mult": 3.0, "speed": 24.0, "lifetime": 2.4,
						"pierce_count": 3, "windup": 0.8,
						"desc": "蓄力 0.8 秒，300% 伤害，无视 40% 护甲，穿透≥2 敌时冷却 -2 秒",
					},
					{
						"id": "eagle_vision", "name": "鹰眼视野", "kind": "buff",
						"cooldown": 10.0, "cost": 30.0,
						"duration": 8.0,
						"self_buffs": [{"id": "gen_rng_up", "stacks": 1},
							{"id": "focus", "stacks": 1}],
						"desc": "激活 8 秒，视野 +50%，全屏敌人标记（受伤 +20%，10 秒）",
					},
				],
			},
			# ---------- 终极：森之选召 ----------
			{
				"name": "森之选召",
				"gain": "命中生成森之领域（6 秒、4 米）：领域内敌人移速 -40%、受伤 +25%，猎人在领域内攻速 +40%、暴击 +30%",
				"mods": [],
				"special": {"forest_domain": true},
				"start_gear": [],
				"skills": [
					{
						"id": "forest_rush", "name": "万木奔袭", "kind": "aoe",
						"cooldown": 10.0, "cost": 45.0,
						"damage_mult": 2.0, "radius": 6.0,
						"target_buffs": [{"id": "entangle", "duration": 1.5}],
						"self_buffs": [{"id": "wind_step", "stacks": 1}],
						"desc": "引爆所有领域，每个对全屏造成（攻击力×2.0）伤害，施加 3 层缠绕，移速 +80% 持续 6 秒",
					},
					{
						"id": "thorn_ground", "name": "荆棘地", "kind": "aoe",
						"cooldown": 8.0, "cost": 35.0,
						"damage_mult": 1.2, "radius": 4.0,
						"target_buffs": [{"id": "thorn_slow", "duration": 8.0}],
						"desc": "生成荆棘地（8 秒）：踏入者每秒受攻击力×0.6 伤害、减速 50%",
					},
				],
			},
		],
	},
	"judge": {
		"id": "judge", "name": "判官 · 渡鸦",
		"resource": "judge",
		"desc": "攻击附加法术伤害；满裁决自动触发终局裁决。",
		"forms": [
			# ---------- 初始：渡鸦 ----------
			{
				"name": "渡鸦",
				"gain": "所有攻击额外附加（法强×0.2）法术伤害",
				"mods": [],
				"special": {"spell_on_hit_ap_pct": 0.20},
				"start_gear": ["W01"],
				"skills": [],
			},
			# ---------- 进阶1：锁链判官 ----------
			{
				"name": "锁链判官",
				"gain": "攻击距离 +2 米；攻击挂审判印记（每层 +10% 法伤）；印记连锁传导 30% 法术伤害",
				"mods": [{"stat": "rng", "flat": 2.0, "percent": 0.0}],
				"special": {"mark_per_hit": true, "chain_30pct": true},
				"start_gear": ["A04", "W12"],
				"skills": [
					{
						"id": "verdict_chain", "name": "裁决锁链", "kind": "spread",
						"cooldown": 5.0, "cost": 20.0,
						"damage_mult": 1.0, "range": 8.0, "radius": 3.0,
						"spread_buff": "judgement",
						"desc": "投掷锁链造成（法强×1.0）伤害，将印记复制到周围 3 米所有敌人",
					},
					{
						"id": "chain_detonate", "name": "连锁引爆", "kind": "detonate",
						"cooldown": 8.0, "cost": 35.0,
						"range": 8.0, "detonate_buff": "judgement",
						"per_stack_mult": 0.6, "full_stack_mult": 1.8, "full_stack_count": 3,
						"desc": "引爆所有印记，每层造成（法强×0.6）伤害，3 层时法强×1.8",
					},
				],
			},
			# ---------- 进阶2：影子判官 ----------
			{
				"name": "影子判官",
				"gain": "攻速 +40%；每 4 次攻击触发影子攻击（法强×0.5，无视护甲）；影子攻击叠影痕",
				"mods": [{"stat": "aspd", "flat": 0.0, "percent": 0.40}],
				"special": {"shadow_every_4": true},
				"start_gear": ["A05", "W02"],
				"skills": [
					{
						"id": "shadow_step", "name": "影步", "kind": "teleport",
						"cooldown": 3.0, "cost": 15.0,
						"range": 8.0, "dash_dist": 3.0, "behind_offset": 1.0,
						"self_buffs": [{"id": "gen_aspd_up", "stacks": 1}],
						"desc": "瞬移 3 米，后 1 秒内攻速 +40%",
					},
					{
						"id": "shadow_storm", "name": "影子风暴", "kind": "multi_hit",
						"cooldown": 8.0, "cost": 40.0,
						"range": 3.5, "hit_count": 5, "damage_mult": 0.5,
						"desc": "召唤影子连续攻击，周围 3 米敌人受到 5 次伤害（每次物理×0.5 + 法强×0.2）",
					},
				],
			},
			# ---------- 进阶3：暗影主宰 ----------
			{
				"name": "暗影主宰",
				"gain": "背刺伤害 ×2.5；击杀生成影子分身（30% 攻击，6 秒）；分身期间暴击率 +20%",
				"mods": [],
				"special": {"backstab_mult": 2.5},
				"start_gear": ["A15", "W02"],
				"skills": [
					{
						"id": "shadow_assault", "name": "暗影突袭", "kind": "teleport",
						"cooldown": 5.0, "cost": 25.0,
						"range": 8.0, "behind_offset": 1.1, "damage_mult": 2.0,
						"target_buffs": [{"id": "bleed", "duration": 4.0}],
						"desc": "瞬移至目标背后造成（物理×2.0 + 法强×1.0）伤害，目标生命＜40% 时 ×2.0",
					},
					{
						"id": "shadow_burst", "name": "暗影爆发", "kind": "aoe",
						"cooldown": 10.0, "cost": 45.0,
						"damage_mult": 1.0, "radius": 4.0,
						"target_buffs": [{"id": "dark_erosion", "duration": 5.0}],
						"desc": "引爆所有分身造成（法强×1.0）范围伤害 + 暗影标记（受伤 +15%，5 秒）",
					},
				],
			},
			# ---------- 终极：光暗审裁 ----------
			{
				"name": "光暗审裁",
				"gain": "光层（治疗/护盾积累）与暗层（施加负面积累）独立叠加；光≥暗附光系伤害并回血，暗＞光附暗蚀；均≥5 时全伤害 +40%、移速 +30%",
				"mods": [],
				"special": {"light_dark_layers": true, "verdict_at_5": 0.40},
				"start_gear": [],
				"skills": [
					{
						"id": "final_verdict", "name": "终末审判", "kind": "aoe",
						"cooldown": 18.0, "cost": 60.0,
						"damage_mult": 2.5, "radius": 6.0,
						"target_buffs": [{"id": "brand", "duration": 8.0}],
						"desc": "消耗所有层数，每层对全屏造成（法强×0.7）伤害，施加烙印（受伤 +35%，8 秒）",
					},
					{
						"id": "balance_shift", "name": "天平倾斜", "kind": "buff",
						"cooldown": 12.0, "cost": 20.0,
						"duration": 6.0,
						"self_buffs": [{"id": "gen_atk_up", "stacks": 1}],
						"desc": "立即获得 3 光层 + 3 暗层并强化自身，用于快速推到裁决时刻",
					},
				],
			},
		],
	},
	"monk": {
		"id": "monk", "name": "武僧 · 破拳",
		"resource": "monk",
		"desc": "不装备武器，连击体系驱动。连击续航，极限爆发。",
		"forms": [
			# ---------- 初始：拳师 ----------
			{
				"name": "拳师",
				"gain": "不可装备武器；空手攻击射程 +0.5 米、无视 5% 护甲；基础攻速 +30%；连击中断后保留 50% 连击数",
				"mods": [{"stat": "aspd", "flat": 0.0, "percent": 0.30}],
				"special": {"no_weapon": true, "fist_reach": 0.5, "fist_armor_pierce": 0.05},
				"start_gear": [],
				"skills": [],
			},
			# ---------- 进阶1：铁身 ----------
			{
				"name": "铁身",
				"gain": "生命 +40%；受伤自动反击（下次攻击 ×2.0）；连击≥10 时减伤 25% 且反击翻倍",
				"mods": [{"stat": "hp", "flat": 0.0, "percent": 0.40}],
				"special": {"no_weapon": true, "counter_on_hit": 2.0},
				"start_gear": [],
				"skills": [
					{
						"id": "adamant_body", "name": "金刚体", "kind": "aoe",
						"cooldown": 6.0, "cost": 25.0,
						"damage_mult": 0.8, "radius": 3.5,
						"target_buffs": [{"id": "taunt", "duration": 2.0}],
						"self_buffs": [{"id": "adamant", "stacks": 1}],
						"desc": "4 秒霸体 + 减伤 30%，移速 -30%，开启瞬间范围伤害（攻击×0.8）+ 嘲讽 2 秒",
					},
					{
						"id": "iron_counter", "name": "铁壁反击", "kind": "cone",
						"cooldown": 5.0, "cost": 20.0,
						"damage_mult": 2.5, "reach": 2.6, "half_angle": 70.0,
						"knockback": 4.0,
						"self_buffs": [{"id": "adamant", "stacks": 1}],
						"desc": "防御姿态 1.5 秒（不可移动/攻击），受击时反击（攻击×2.5）+ 击退，触发后重置冷却",
					},
				],
			},
			# ---------- 进阶2：疾风 ----------
			{
				"name": "疾风",
				"gain": "攻速 +30%；连击≥10 时每次攻击恢复 2% 已损生命；连击≥20 时攻速额外 +30%；断连每秒 -5",
				"mods": [{"stat": "aspd", "flat": 0.0, "percent": 0.60}],
				"special": {"no_weapon": true, "combo_heal": 0.02, "slow_combo_decay": true},
				"start_gear": [],
				"skills": [
					{
						"id": "gale_flurry", "name": "疾风连打", "kind": "multi_hit",
						"cooldown": 5.0, "cost": 25.0,
						"range": 2.5, "hit_count": 10, "damage_mult": 0.40,
						"combo_gain": 10,
						"desc": "1.5 秒内对单目标造成 10 次伤害（每次 40%），连击计数翻倍增长",
					},
					{
						"id": "wind_step_m", "name": "风之步", "kind": "teleport",
						"cooldown": 2.0, "cost": 15.0,
						"range": 6.0, "dash_dist": 2.5, "behind_offset": 1.0,
						"combo_gain": 3,
						"self_buffs": [{"id": "gen_aspd_up", "stacks": 1}],
						"desc": "瞬移 2.5 米，后 1 秒攻速 +50%，连击计数 +3",
					},
				],
			},
			# ---------- 进阶3：破极 ----------
			{
				"name": "破极",
				"gain": "可装备武器（突破限制）；连击无上限；每 25 连击触发破极状态 6 秒（攻击 +70%、攻速 +50%、真伤 ×0.15、防御归零）",
				"mods": [],
				"special": {"can_equip_weapon": true, "break_limit_at": 25},
				"start_gear": [],
				"skills": [
					{
						"id": "breaker_fist", "name": "破极拳", "kind": "cone",
						"cooldown": 4.0, "cost": 30.0,
						"damage_mult": 3.5, "reach": 3.0, "half_angle": 55.0,
						"knockback": 5.0, "combo_scaled": true,
						"desc": "蓄力 0.5~2 秒，造成（物理×1.5~3.5）伤害，破极状态下必暴且 ×1.5",
					},
					{
						"id": "last_stand", "name": "背水一战", "kind": "buff",
						"cooldown": 12.0, "cost": 40.0,
						"duration": 8.0,
						"heal_lost_pct": 0.20,
						"self_buffs": [{"id": "break_limit", "stacks": 1},
							{"id": "war_cry", "stacks": 1}],
						"desc": "立即进入破极状态 8 秒（即使连击不足 25），受击 +150%，开启瞬间恢复 20% 已损生命",
					},
				],
			},
			# ---------- 终极：无我极境 ----------
			{
				"name": "无我极境",
				"gain": "万象连击随连击数自动演进：连击>10 附范围冲击波；>25 发射 5 颗气功弹；>40 改为龙型气功波激光",
				"mods": [],
				"special": {"no_weapon": true, "myriad_combo": true},
				"start_gear": [],
				"skills": [
					{
						"id": "myriad_fist", "name": "万象连击", "kind": "multi_hit",
						"cooldown": 8.0, "cost": 40.0,
						"range": 3.0, "hit_count": 8, "damage_mult": 0.70,
						"combo_scaled": true, "combo_gain": 8,
						"desc": "连续不断的万象拳，随连击数提升段数与伤害",
					},
					{
						"id": "void_palm", "name": "虚空掌", "kind": "aoe",
						"cooldown": 10.0, "cost": 45.0,
						"damage_mult": 2.5, "radius": 5.0, "knockback": 3.0,
						"combo_scaled": true,
						"desc": "一掌震开周围敌人，伤害随连击数放大",
					},
				],
			},
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


# ============================================================
# 形态 special 字段的统一读取口
# ============================================================
# **为什么收口在这里**：`special` 是形态机制的唯一声明处（31 个字段），
# 消费方却横跨 player（普攻）/ skill_system（技能）/ class_resource（资源）
# 三处。此前 `skill_system._form_special_float` 是唯一实现，player 想读
# 同一个字段只能再抄一份——重复实现迟早分叉（改了一处忘另一处，
# 表现就是"同一个机制在普攻生效、在技能不生效"）。
# 故所有读取统一走下面三个静态方法。

## 某形态的 special 字典（取不到返回空字典）
static func special_of(class_id: String, form_slot: int) -> Dictionary:
	var f := get_form(class_id, form_slot)
	return f.get("special", {})


## 读形态 special 的数值项。缺项返回 fallback——
## 形态增益是"锦上添花"，某个形态没声明该字段不该让整条链路失效。
static func special_num(class_id: String, form_slot: int, key: String,
		fallback: float = 0.0) -> float:
	var sp := special_of(class_id, form_slot)
	if not sp.has(key):
		return fallback
	return float(sp[key])


## 读形态 special 的开关项（如 no_weapon / myriad_combo）。
## 注意 bool 型字段转 float 会得到 1.0/0.0，故开关项必须走这里，
## 不能靠 special_num 的返回值判断"是否有值"。
static func special_flag(class_id: String, form_slot: int, key: String) -> bool:
	var sp := special_of(class_id, form_slot)
	if not sp.has(key):
		return false
	return bool(sp[key])


## 该形态是否声明了某 special 字段（区分"声明为 0"与"没声明"）
static func has_special(class_id: String, form_slot: int, key: String) -> bool:
	return special_of(class_id, form_slot).has(key)


## 「每次命中叠印记」的 flag → 印记 buff id。
##
## **普攻与技能共用**：咒焰使的技能是 `kind=detonate`（读目标身上的层数来引爆），
## 它自己不产生层数——层数只能由**普攻**累积。若只在技能侧接，
## 该形态会陷入"要引爆先得有层数、要有层数却只能靠引爆"的死循环。
## 故普攻（player._apply_hit）与技能（skill_system._deal_damage）都要读这张表。
const FORM_MARK_PAIRS := [
	["flame_stack_per_cast", "flame_mark"],
	["void_stigma_per_cast", "void_stigma"],
]


## 当前形态声明的印记 buff id（无则空串）
static func form_mark_id(class_id: String, form_slot: int) -> String:
	for p in FORM_MARK_PAIRS:
		if special_flag(class_id, form_slot, str(p[0])):
			return str(p[1])
	return ""


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
