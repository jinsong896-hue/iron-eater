class_name MonsterData
extends Resource
## 怪物数据 —— 模板化怪物配置
## 文档：ai/框架相关.md Monster Studio

@export var monster_name: String = ""
@export var ai_type: String = "melee_chase"
@export var hp: int = 100
@export var atk: int = 10
@export var defense: int = 5
@export var speed: int = 80
@export var floor_min: int = 1
@export var floor_max: int = 8
@export var hp_scale: float = 3.5
@export var sprite_path: String = ""
@export var loot_table: String = ""
@export var drop_rate: float = 0.3
