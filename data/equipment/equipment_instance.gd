class_name EquipmentInstance
extends RefCounted
## 装备实例 —— 运行时数据，记录成长状态

var instance_id: String = ""
var template_id: StringName = &""
var rarity: int = 0
var fusion_count: int = 0
var enhancement_level: int = 0
var is_locked: bool = false
var created_at_usec: int = 0


func _init() -> void:
	created_at_usec = Time.get_ticks_usec()
	instance_id = _generate_uuid()


## 获取模板
func get_template() -> EquipmentTemplate:
	return EquipmentDB.get_template(template_id)


## 显示名
func display_name() -> String:
	var t := get_template()
	if t == null:
		return "未知装备"
	return t.display_name


## 融合等级文本
func fusion_tier() -> String:
	if fusion_count < 3:
		return "粗糙"
	elif fusion_count < 7:
		return "完整"
	elif fusion_count < 13:
		return "纯净"
	elif fusion_count < 21:
		return "不朽"
	return "神话"


## 基础词条有效值（含强化）
func base_affix_value() -> float:
	var t := get_template()
	if t == null or t.base_affix == null:
		return 0.0
	return t.base_affix.value * (1.0 + enhancement_level * 0.05)


## 融合攻击加成（临时简化版）
func fusion_bonus() -> float:
	return fusion_count * 0.02


## 强化倍率
func enhancement_mult() -> float:
	return 1.0 + enhancement_level * 0.05


## 序列化
func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"template_id": str(template_id),
		"rarity": rarity,
		"fusion_count": fusion_count,
		"enhancement_level": enhancement_level,
		"is_locked": is_locked,
		"created_at_usec": created_at_usec,
	}


## 反序列化
func from_dict(d: Dictionary) -> EquipmentInstance:
	instance_id = d.get("instance_id", _generate_uuid())
	template_id = StringName(d.get("template_id", ""))
	rarity = d.get("rarity", 0)
	fusion_count = d.get("fusion_count", 0)
	enhancement_level = d.get("enhancement_level", 0)
	is_locked = d.get("is_locked", false)
	created_at_usec = d.get("created_at_usec", 0)
	return self


## 静态工厂
static func create(template: EquipmentTemplate) -> EquipmentInstance:
	var inst := EquipmentInstance.new()
	if template == null:
		return inst
	inst.template_id = template.id
	inst.rarity = template.rarity
	return inst


## 生成简单 UUID
func _generate_uuid() -> String:
	var chars := "0123456789abcdef"
	var s := ""
	for i in range(8):
		s += chars[randi() % chars.length()]
	s += "-"
	for i in range(4):
		s += chars[randi() % chars.length()]
	s += "-4"
	for i in range(3):
		s += chars[randi() % chars.length()]
	s += "-"
	for i in range(4):
		s += chars[(randi() % 4 + 8)]
	s += "-"
	for i in range(12):
		s += chars[randi() % chars.length()]
	return s
