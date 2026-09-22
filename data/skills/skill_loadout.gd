class_name SkillLoadout
extends RefCounted
## 技能配置 —— **主动技能上槽（最多 6 个）**，被动技能学会即生效。
##
## ## 主动 / 被动的区别（装备参考2 规格）
##
## | | 主动技能 | 被动技能 |
## |---|---|---|
## | 上槽位 | 是（6 个槽，玩家手动配） | **否** |
## | 生效方式 | 按键施放 | **常驻生效**（学会就有） |
## | 规格 kind | `aoe`/`cone`/`dash`/… | `passive` |
##
## 判定统一走 `SkillLoadout.is_passive(sk)`，不散落各处判 kind 字符串。
##
## ## 为什么被动不用单独一套生效机制
##
## 规格里被动的效果就是属性加成（「最大生命+8%」「移速+5%」「金币+10%」），
## 而 `BuffHolder` 已经能把**永不过期词条**（duration=0）同步进
## AttributeSystem。故被动 = 给玩家挂一条 permanent 词条，复用现成链路。
##
## ## 为什么是独立类而不是塞进 Player
##
## 技能配置是**局内状态**，要跨房间存活（切房会重建 Player 节点），
## 又要随新开局重置。放在 GameManager 持有的独立对象里，两个条件同时满足。

## 主动技能槽位数（用户要求：角色最多只能装备 6 个技能）
const SLOT_COUNT := 6

## 被动词条的 id 前缀（见 buff_defs.gd 的 ps_* 条目）
const PASSIVE_BUFF_PREFIX := "ps_"

## 主动技能槽：下标 0~5，值为技能 id（空串 = 空槽）
var slots: Array[String] = ["", "", "", "", "", ""]

## 已学会的被动技能 id 列表（**不占槽位**，学会即生效）
var passives: Array[String] = []


# ============================================================
# 主动 / 被动 判定
# ============================================================

## 该技能是否是被动（规格用 kind="passive" 标记）
static func is_passive(sk: Dictionary) -> bool:
	return str(sk.get("kind", "")) == "passive"


## 按技能 id 判定是否被动。
##
## **被动技能不需要进技能表**：规格里被动是常驻属性加成，其效果
## 由词条（`ps_*`，见 buff_defs.gd）承载。故这里先查技能表，
## 查不到再看它是不是一条被动词条——这样「只登记词条」的被动
## 也能被学会，不必在两处重复登记。
static func is_passive_id(skill_id: String) -> bool:
	if skill_id.begins_with(PASSIVE_BUFF_PREFIX):
		return true
	var found := ClassDefs.find_skill(skill_id)
	if found.is_empty():
		return false
	return is_passive(found.get("skill", {}))


## 技能 id 是否可被识别（技能表里有，或是一条被动词条）
static func _known(skill_id: String) -> bool:
	if skill_id.begins_with(PASSIVE_BUFF_PREFIX):
		return not BuffDefs.get_buff(skill_id).is_empty()
	return not ClassDefs.find_skill(skill_id).is_empty()


# ============================================================
# 主动技能：装备 / 卸下
# ============================================================

## 把**主动**技能装到指定槽位。
##
## 被动技能会被拒绝——它们不上槽（见文件头）。这是硬约束：
## 不拦的话被动会占掉 6 个主动槽之一，与规格矛盾。
## 返回 {ok, reason?}。
func equip(skill_id: String, slot: int) -> Dictionary:
	if slot < 0 or slot >= SLOT_COUNT:
		return {"ok": false, "reason": "槽位越界"}
	if skill_id.is_empty():
		return {"ok": false, "reason": "技能 id 为空"}
	var found := ClassDefs.find_skill(skill_id)
	if found.is_empty():
		return {"ok": false, "reason": "未找到该技能"}
	if is_passive(found.get("skill", {})):
		return {"ok": false, "reason": "被动技能不上槽位（学会即生效）"}
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


## 已装备的主动技能 id 列表（保持槽位顺序，含空串）
func ids() -> Array[String]:
	return slots.duplicate()


## 已装备的主动技能数据列表（跳过空槽）
func equipped_skills() -> Array:
	var out: Array = []
	for i in SLOT_COUNT:
		var sk := skill_at(i)
		if not sk.is_empty():
			out.append(sk)
	return out


## 已装备的主动技能数量
func equipped_count() -> int:
	var n := 0
	for s in slots:
		if not s.is_empty():
			n += 1
	return n


## 主动槽是否已满
func is_full() -> bool:
	return equipped_count() >= SLOT_COUNT


# ============================================================
# 被动技能：学会 / 遗忘
# ============================================================

## 学会一个被动技能（**不占槽位**）。返回 {ok, reason?}。
##
## 非被动技能会被拒绝——主动技能必须走 `equip` 上槽，
## 否则"学会"会变成绕过 6 槽上限的旁路。
func learn_passive(skill_id: String) -> Dictionary:
	if skill_id.is_empty():
		return {"ok": false, "reason": "技能 id 为空"}
	if not _known(skill_id):
		return {"ok": false, "reason": "未找到该技能"}
	if not is_passive_id(skill_id):
		return {"ok": false, "reason": "该技能不是被动（需上槽位）"}
	if passives.has(skill_id):
		return {"ok": false, "reason": "已学会该被动"}
	passives.append(skill_id)
	return {"ok": true}


## 遗忘一个被动
func forget_passive(skill_id: String) -> bool:
	var i := passives.find(skill_id)
	if i < 0:
		return false
	passives.remove_at(i)
	return true


## 已学会的被动数量
func passive_count() -> int:
	return passives.size()


## 已学会被动的数据列表
func learned_passives() -> Array:
	var out: Array = []
	for sid in passives:
		var sk: Dictionary = ClassDefs.find_skill(sid).get("skill", {})
		if not sk.is_empty():
			out.append(sk)
	return out


# ============================================================
# 重置 / 兜底 / 序列化
# ============================================================

## 新开局重置（清空槽位与已学被动）
func reset() -> void:
	for i in SLOT_COUNT:
		slots[i] = ""
	passives.clear()


## 按**当前职业/形态**自动填充（开局默认配置）。
##
## 主动技能填进槽位；被动技能自动"学会"（不上槽）。
## 只在**槽位与被动都为空**时填充，不覆盖玩家已有的配置。
func autofill_if_empty(class_id: String, form_slot: int) -> void:
	if equipped_count() > 0 or not passives.is_empty():
		return
	var pool: Array = ClassDefs.skills_of(class_id, form_slot)
	var slot_i := 0
	for sk in pool:
		var sid := str((sk as Dictionary).get("id", ""))
		if sid.is_empty():
			continue
		if is_passive(sk as Dictionary):
			passives.append(sid)          # 被动：学会即生效
		elif slot_i < SLOT_COUNT:
			slots[slot_i] = sid           # 主动：占一个槽
			slot_i += 1


## 序列化（存档用）
func to_dict() -> Dictionary:
	return {"slots": Array(slots), "passives": Array(passives)}


## 反序列化（读档用）。字段缺失时保持当前值（向后兼容旧存档）。
func from_dict(d: Dictionary) -> void:
	var arr: Array = d.get("slots", [])
	for i in mini(arr.size(), SLOT_COUNT):
		slots[i] = str(arr[i])
	passives.clear()
	for sid in d.get("passives", []):
		passives.append(str(sid))
