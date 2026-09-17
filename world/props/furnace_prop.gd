class_name FurnaceProp
extends DestroyableProp
## 符文熔炉 —— 第 5 层「符文熔炉」
##
## 策划 6.6：「房间四角/四边分布 4 个符文熔炉，周期性喷发火焰
##（范围提示 3 秒后爆发，30 火焰伤害）。玩家与 Boss 都会被烧；
## Boss 部分技能会激活熔炉（改变喷发节奏/增大范围/追踪玩家），
## 玩家也可攻击熔炉改变状态（提前引爆/关闭/定向喷射）。机关是双刃剑。」
##
## 本类只负责**物件本身**（血量/受击/视觉/状态）。喷发节奏由
## FloorEnvironment 的 `_tick_furnaces` 统一驱动——4 个熔炉共享一个计时器，
## 这样"提前引爆"只影响该熔炉自己，而整体节奏仍然协调。

## 该熔炉的位置编号（0~3，对应房间四角）
var corner_index := -1
## 提前引爆请求：FloorEnvironment 消费后清零
var force_ignite := false
## 关闭剩余轮数：>0 时跳过本熔炉的喷发
var skip_rounds := 0


func _init() -> void:
	prop_kind = "furnace"
	max_hp = 140.0
	hp = 140.0


func collision_size() -> Vector3:
	return Vector3(1.0, 1.4, 1.0)


func _build_visual() -> void:
	# 石质炉体 + 顶部符文环 + 炉口橙红火光
	_add_box(Vector3(0, 0.5, 0), Vector3(0.9, 1.0, 0.9), Color(0.32, 0.20, 0.16), 0.0)
	_add_cylinder(Vector3(0, 1.05, 0), 0.42, 0.14, Color(0.42, 0.26, 0.18), 0.0)
	_add_sphere(Vector3(0, 1.20, 0), 0.26, Color(1.0, 0.45, 0.12), 1.2)
	_add_light(Color(1.0, 0.55, 0.20), 1.6)


## 被玩家攻击时的"改变状态"入口（策划：提前引爆 / 关闭）。
## 由 FloorEnvironment 在 `destroyed` 之外单独判定——本函数只记录意图，
## 具体效果由驱动方执行（它才知道计时器状态）。
func request_ignite() -> void:
	force_ignite = true


func request_skip() -> void:
	skip_rounds = maxi(skip_rounds, 1)
