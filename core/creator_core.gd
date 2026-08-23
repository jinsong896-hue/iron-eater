class_name IronEaterCreator
extends RefCounted
## IronEater Creator 核心管理器 —— 三层架构的中枢
## 文档：ai/框架相关.md 一、Creator Core 总体架构
##
## 三层模型：
##   Editor Layer → Data Layer → Runtime Layer
##
## 数据流：
##   编辑器操作 → .tres 文件 → 运行时读取 → 游戏运行

# 数据目录
const CHAR_DIR := "res://data/characters"
const WEAPON_DIR := "res://data/weapons"
const SKILL_DIR := "res://data/skills"
const MONSTER_DIR := "res://data/monsters"
const FORM_DIR := "res://data/forms"

# 已加载的资源缓存
var characters: Dictionary = {}
var weapons: Dictionary = {}
var skills: Dictionary = {}
var monsters: Dictionary = {}


## 加载角色
func load_character(id: String) -> CharacterData:
	if characters.has(id):
		return characters[id]
	var path := CHAR_DIR + "/" + id + ".tres"
	if not FileAccess.file_exists(path):
		print("[CreatorCore] 角色文件不存在: %s" % path)
		return null
	var data: CharacterData = load(path) as CharacterData
	if data:
		characters[id] = data
	return data


## 加载武器
func load_weapon(id: String) -> WeaponData:
	if weapons.has(id):
		return weapons[id]
	var data: WeaponData = load(WEAPON_DIR + "/" + id + ".tres")
	if data:
		weapons[id] = data
	return data


## 加载技能
func load_skill(id: String) -> SkillData:
	if skills.has(id):
		return skills[id]
	var data: SkillData = load(SKILL_DIR + "/" + id + ".tres")
	if data:
		skills[id] = data
	return data


## 加载怪物
func load_monster(id: String) -> MonsterData:
	if monsters.has(id):
		return monsters[id]
	var data: MonsterData = load(MONSTER_DIR + "/" + id + ".tres")
	if data:
		monsters[id] = data
	return data


## 创建完整角色
func create_character(char_id: String, weapon_id: String = "", form_idx: int = 0) -> CharacterRuntime:
	var runtime := CharacterRuntime.new()
	var char := load_character(char_id)
	if char == null:
		return runtime
	runtime.setup(char, form_idx)
	if weapon_id != "":
		var equip := EquipmentRuntime.new()
		equip.equip(load_weapon(weapon_id))
		runtime.add_child(equip)
	return runtime


## 列出所有角色
func list_characters() -> Array[String]:
	return _list_dir(CHAR_DIR)


## 列出所有武器
func list_weapons() -> Array[String]:
	return _list_dir(WEAPON_DIR)


## 列出所有技能
func list_skills() -> Array[String]:
	return _list_dir(SKILL_DIR)


## 列出所有怪物
func list_monsters() -> Array[String]:
	return _list_dir(MONSTER_DIR)


func _list_dir(path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			result.append(f.trim_suffix(".tres"))
		f = dir.get_next()
	dir.list_dir_end()
	return result


func clear_cache() -> void:
	characters.clear()
	weapons.clear()
	skills.clear()
	monsters.clear()
