class_name SkillLoadout
extends RefCounted
## 技能槽（Loadout）—— 玩家已装备技能的 6 个槽位。
##
## ## 为什么是独立类而不是塞进 Player
##
## 技能槽是**局内状态**，要跨房间存活（切房会重建 Player 节点），
## 又要随新开局重置。放在 GameManager 持有的独立对象里，两个条件同时满足；
## 挂在 Player 上会在切房时丢失。
##
## ## 与职业形态的关系
##
## 技能**池**来自当前职业/形态（`ClassDefs.skills_of`），但**装备哪些**
## 由玩家在技能管理页决定。这解决了一个实际问题：规格里每个形态有
## 0~3 个技能，而槽位有 6 个——不管理的话，切形态会丢掉已配好的组合。
##
## 槽位里的技能 id 允许来自**任意已解锁形态**（`ClassDefs.find_skill`
## 全局检索），这样玩家可以把不同形态的技能混搭进 6 个槽。

## 槽位数量（用户要求：角色最多只能装备 6 个技能）
const SLOT_COUNT := 6

## 槽位内容：下标 0~5，值为技能 id（空串 = 空槽）
var slots: Array[String] = ["", "", "", "", "", ""]


## 把技能装到指定槽位。
##
## 已装在别的槽 → 先清掉那个槽（同一技能不能占两格）。
## 返回 {ok, reason?}。
func equip(skill_id: String, slot: int) -> Dictionary:
	if slot < 0 or slot >= SLOT_COUNT:
		return {"ok": false, "reason": "槽位越界"}
	if skill_id.is_empty():
		return {"ok": false, "reason": "技能 id 为空"}
	if ClassDefs.find_skill(skill_id).is_empty():
		return {"ok": false, "reason": "未找到该技能"}
	# 同一技能不占两格
	var old := slots.find(skill_id)
	if old >= 0:
		slots[old] = ""
	slots[slot] = skill_id
	return {"ok": true, "moved_from": old}


## 清空指定槽位
func unequip(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	if slots[slot].is_empty():
		return false
	slots[slot] = ""
	return true


## 某槽位的技能数据（空槽返回空字典）
func skill_at(slot: int) -> Dictionary:
	if slot < 0 or slot >= SLOT_COUNT:
		return {}
	var sid := slots[slot]
	if sid.is_empty():
		return {}
	return ClassDefs.find_skill(sid).get("skill", {})


## 已装备的技能 id 列表（保持槽位顺序，含空串）
func ids() -> Array[String]:
	return slots.duplicate()


## 已装备的技能数据列表（跳过空槽）
func equipped_skills() -> Array:
	var out: Array = []
	for i in SLOT_COUNT:
		var sk := skill_at(i)
		if not sk.is_empty():
			out.append(sk)
	return out


## 已装备数量
func equipped_count() -> int:
	var n := 0
	for s in slots:
		if not s.is_empty():
			n += 1
	return n


## 是否已满
func is_full() -> bool:
	return equipped_count() >= SLOT_COUNT


## 新开局重置（清空所有槽）
func reset() -> void:
	for i in SLOT_COUNT:
		slots[i] = ""


## 按**当前职业/形态**自动填充（开局默认配置）。
##
## 用途：玩家没手动配过技能时，至少要有能用的技能——
## 否则「技能管理页」没打开过就永远空手（规格里每个形态 0~3 个技能）。
## 只在**槽位全空**时填充，不覆盖玩家已有的配置。
func autofill_if_empty(class_id: String, form_slot: int) -> void:
	if equipped_count() > 0:
		return
	var pool: Array = ClassDefs.skills_of(class_id, form_slot)
	for i in mini(pool.size(), SLOT_COUNT):
		slots[i] = str((pool[i] as Dictionary).get("id", ""))


## 序列化（存档用）
func to_dict() -> Dictionary:
	return {"slots": Array(slots)}


## 反序列化（读档用）。字段缺失时保持当前值（向后兼容旧存档）。
func from_dict(d: Dictionary) -> void:
	var arr: Array = d.get("slots", [])
	for i in mini(arr.size(), SLOT_COUNT):
		slots[i] = str(arr[i])
