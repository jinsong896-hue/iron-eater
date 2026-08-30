class_name SkillRuntime
extends Node
## 技能运行时 —— 执行技能效果列表
## 文档：ai/框架相关.md Skill Studio

var skills: Array[SkillData] = []
var cooldowns: Dictionary = {}


## 载入技能列表并清空冷却
func load_skills(list: Array[SkillData]) -> void:
	skills = list
	cooldowns.clear()


## 是否可施放（冷却/HP/MP 检查）
func can_cast(skill: SkillData, hp: float, mp: float) -> bool:
	if cooldowns.get(skill.skill_id, 0.0) > 0:
		return false
	if hp < skill.hp_cost:
		return false
	if mp < skill.mp_cost:
		return false
	return true


## 施放技能（执行效果并进入冷却）
func cast(skill: SkillData, target: Node) -> Dictionary:
	if not can_cast(skill, 9999.0, 9999.0):
		return {"ok": false, "reason": "cannot cast"}
	skill.execute(target)
	cooldowns[skill.skill_id] = skill.cooldown
	return {"ok": true, "skill": skill.skill_name}


## 每帧冷却递减
func update_cooldowns(delta: float) -> void:
	for key in cooldowns:
		cooldowns[key] = maxf(cooldowns[key] - delta, 0.0)
