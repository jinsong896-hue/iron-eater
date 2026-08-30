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
