class_name GameBalance
extends RefCounted
## 数值平衡配置 —— HD-2D 重构版
## 游戏全局的数值参数配置

# ============================================================
# 玩家基础
# ============================================================
const PLAYER_BASE_SPEED := 4.0
const PLAYER_ACCELERATION := 20.0
const PLAYER_DECELERATION := 25.0
const PLAYER_BASE_ATTACK_INTERVAL := 0.6
const PLAYER_ATTACK_REACH := 2.0    # 近战攻击范围（3D 米）

# ============================================================
# 连段系统（四段普攻 + 奔跑/跳跃特殊攻击，均接普攻3）
# ============================================================
## 四段普攻参数：[冷却秒, 伤害倍率, 攻击距离(米), 扇形半角(度), 击退力]
const COMBO_STAGES := [
	[0.28, 1.00, 2.0, 60.0, 0.0],   # 普攻1：起手快
	[0.28, 1.10, 2.2, 65.0, 0.0],   # 普攻2
	[0.32, 1.30, 2.6, 75.0, 1.5],   # 普攻3：范围开始扩大，小击退
	[0.45, 1.80, 3.2, 90.0, 4.0],   # 普攻4：终结技，大击退
]
## 连击窗口（窗口内按下一击接段，超时回普攻1）
const COMBO_WINDOW := 0.45
## 连击窗口随 ASPD 缩放（攻速越快窗口越短）
const COMBO_WINDOW_SCALE_WITH_ASPD := true
## 攻击输入缓存时长（冷却中按下不丢，冷却结束立即触发）
const ATTACK_INPUT_BUFFER := 0.2
## 奔跑攻击参数：[冷却, 伤害倍率, 冲撞距离, 冲撞宽度, 击退力]
const SPRINT_ATTACK := [0.5, 1.50, 3.0, 1.8, 5.0]
## 跳跃攻击参数（方案C 后跳蓄力→俯冲砸地）：[冷却, 伤害倍率, 后跳距离, 俯冲距离, 落地AOE半径, 击退力]
const JUMP_ATTACK := [0.7, 1.70, 1.5, 4.0, 3.0, 6.0]
## 跳跃攻击阶段时长：[后跳蓄力, 俯冲, 落地恢复]
const JUMP_ATTACK_PHASES := [0.15, 0.2, 0.15]
## 攻击动作期间移动减速比例（0.5 = 减半）
const ATTACK_MOVE_SLOWDOWN := 0.5

# ============================================================
# 技能预设（内联数据，后续可迁移到 Resource）
# ============================================================
static var _skills := {}


## 注册技能
static func register_skill(id: String, data: Dictionary) -> void:
	_skills[id] = data


## 按 ID 查询技能
static func skill_by_id(id: String) -> Dictionary:
	return _skills.get(id, {})


# ============================================================
# 房间生成
# ============================================================
const ROOM_SIZE := 20.0               # 房间世界尺寸（米）
const WALL_HEIGHT := 3.0              # 墙壁高度
const WALL_THICKNESS := 0.2           # 墙壁厚度
const DOOR_WIDTH := 2.0               # 门宽度

# ============================================================
# 地下城生成
# ============================================================
const MIN_ROOMS := 8
const MAX_ROOMS := 15
const BOSS_DISTANCE_MIN := 4          # Boss 房距离起点最小房间数

# ============================================================
# 掉落
# ============================================================
const BASE_DROP_CHANCE := 0.3
const ELITE_DROP_CHANCE := 0.6
const BOSS_DROP_CHANCE := 1.0
const GOLD_DROP_RANGE := Vector2(5, 25)

# ============================================================
# 相机
# ============================================================
const CAMERA_ANGLE_X := -45.0         # 俯视角度
const CAMERA_ANGLE_Y := 45.0          # 旋转角度
const CAMERA_DISTANCE := 15.0         # 相机距离
const CAMERA_FOLLOW_SPEED := 6.0      # 跟随速度
const CAMERA_FOV := 40.0              # 视场角（HD-2D 用长焦）

# ============================================================
# 渲染
# ============================================================
const INTERNAL_3D_RESOLUTION := 0.5   # 3D 渲染分辨率缩放（0.5 = 960x540 @ 1080p）
const PIXEL_FILTER := "nearest"       # 像素过滤模式
