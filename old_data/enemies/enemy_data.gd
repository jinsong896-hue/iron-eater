class_name EnemyData
extends Resource
## 敌人数据 —— HD-2D 重构版
## 定义敌人的各项参数，与表现层解耦

@export var id := ""
@export var display_name := ""

# 基础属性
@export var max_hp: float = 100.0
@export var atk: float = 10.0
@export var defense: float = 5.0
@export var speed: float = 2.0

# AI 参数
enum AIBehavior {
	MELEE_CHASE,    # 近战追踪
	RANGED_KITE,    # 远程风筝
	PATROL,         # 巡逻
	STATIONARY,     # 定点
	BOSS,           # Boss AI
}

@export var behavior := AIBehavior.MELEE_CHASE
@export var detect_range: float = 10.0
@export var attack_range: float = 2.0
@export var attack_interval: float = 1.0
@export var flee_health_percent: float = 0.0  # 低于此血量逃跑（0=不逃跑）

# 掉落
@export var loot_table: Array[String] = []     # 可能掉落的装备模板 ID 列表
@export var gold_min: int = 0
@export var gold_max: int = 10
@export var exp_value: int = 10

# 视觉
@export var model_scene: String                # 3D 模型场景路径
@export var death_effect: String               # 死亡特效路径


func get_random_gold(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(gold_min, gold_max)


func get_random_loot(rng: RandomNumberGenerator) -> String:
	if loot_table.is_empty():
		return ""
	return loot_table[rng.randi() % loot_table.size()]