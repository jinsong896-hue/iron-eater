@tool
class_name AnimationSetData
extends Resource
## 角色动画集 —— 管理所有动作的动画路径
## 默认动作接口：idle/run/jump/attack1-4/run_attack/jump_attack

@export_category("Model")
@export var model_path: String = ""

@export_category("Movement")
@export var idle: String = ""
@export var run: String = ""
@export var jump: String = ""
@export var fall: String = ""
@export var land: String = ""

@export_category("Combat")
@export var attack_1: String = ""
@export var attack_2: String = ""
@export var attack_3: String = ""
@export var attack_4: String = ""
@export var run_attack: String = ""
@export var jump_attack: String = ""

@export_category("Hit & Death")
@export var hit: String = ""
@export var death: String = ""

@export_category("Skills")
@export var skill_anims: Dictionary = {}

func get_anim(action: String) -> String:
	match action:
		"idle": return idle
		"run": return run
		"jump": return jump
		"attack_1": return attack_1
		"attack_2": return attack_2
		"attack_3": return attack_3
		"attack_4": return attack_4
		"run_attack": return run_attack
		"jump_attack": return jump_attack
		"hit": return hit
		"death": return death
		_: return skill_anims.get(action, "")

func set_anim(action: String, name: String) -> void:
	match action:
		"idle": idle = name
		"run": run = name
		"jump": jump = name
		"attack_1": attack_1 = name
		"attack_2": attack_2 = name
		"attack_3": attack_3 = name
		"attack_4": attack_4 = name
		"run_attack": run_attack = name
		"jump_attack": jump_attack = name
		"hit": hit = name
		"death": death = name
		_: skill_anims[action] = name

func all_actions() -> Array[String]:
	return ["idle", "run", "jump", "fall", "land", "attack_1", "attack_2", "attack_3", "attack_4", "run_attack", "jump_attack", "hit", "death"]
