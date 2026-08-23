class_name DataValidator
extends RefCounted
## 数据验证器 —— 检查 .tres 文件完整性
## 文档：ai/框架相关.md P2 数据验证

## 验证角色数据
static func validate_character(data: CharacterData) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if data.char_id.is_empty():
		errors.append("缺少角色ID")
	if data.char_name.is_empty():
		errors.append("缺少角色名称")
	if data.base_stats == null:
		errors.append("缺少基础属性")
	if data.forms.is_empty():
		warnings.append("没有配置形态")
	for f in data.forms:
		if f.skills.is_empty():
			warnings.append("形态 '%s' 没有技能" % f.form_name)
		if f.modifiers.is_empty():
			warnings.append("形态 '%s' 没有属性修改器" % f.form_name)

	return {"errors": errors, "warnings": warnings, "valid": errors.is_empty()}


## 验证武器数据
static func validate_weapon(data: WeaponData) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if data.weapon_id.is_empty():
		errors.append("缺少武器ID")
	if data.weapon_name.is_empty():
		errors.append("缺少武器名称")
	if data.base_atk <= 0:
		warnings.append("基础攻击力为0")
	if data.max_fusion <= 0:
		warnings.append("最大融合等级为0")

	return {"errors": errors, "warnings": warnings, "valid": errors.is_empty()}


## 验证技能数据
static func validate_skill(data: SkillData) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if data.skill_id.is_empty():
		errors.append("缺少技能ID")
	if data.skill_name.is_empty():
		errors.append("缺少技能名称")
	if data.effects.is_empty():
		warnings.append("没有配置效果")
	if data.cooldown < 0:
		errors.append("冷却时间为负")

	return {"errors": errors, "warnings": warnings, "valid": errors.is_empty()}


## 批量验证目录
static func validate_directory(dir_path: String, type: String) -> Dictionary:
	var results: Array[Dictionary] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return {"results": [], "total": 0, "passed": 0}

	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var data: Resource = load(dir_path + "/" + f)
			var result: Dictionary
			match type:
				"character":
					result = validate_character(data as CharacterData)
				"weapon":
					result = validate_weapon(data as WeaponData)
				"skill":
					result = validate_skill(data as SkillData)
				_:
					result = {"valid": true, "errors": [], "warnings": []}
			result["file"] = f
			results.append(result)
		f = dir.get_next()
	dir.list_dir_end()

	var passed := 0
	for r in results:
		if r["valid"]: passed += 1

	return {"results": results, "total": results.size(), "passed": passed}
