class_name ArtRegistry
extends RefCounted
## 美术资源注册表 —— 运行时的「用途 → 资源」查询入口
##
## ## 职责
##
## 持有当前生效的 `ArtProfile`，给消费方提供查询。消费方（装饰生成器、
## 敌人视觉、特效系统）**不直接读 profile**，而是走本类——
## 这样热切换只需改一处，且能在查询层统一做兜底。
##
## ## 核心不变量：**永远不返回空导致画面变黑**
##
## 查询失败（无 profile / 未配置该用途）时返回**空串**，语义是
## 「没配，你走原逻辑」——消费方据此回退到硬编码路径或占位体。
##
## 这样：
##   · 空 profile 的行为与接入前**完全一致**
##   · 接入可以分阶段进行（配一个用一个）
##   · 任何时候删掉配置都能一键回到原状
##
## 反面做法是「查询失败返回一个默认模型」——那会在素材缺失时
## 悄悄替换成别的东西，比报错更难排查。

## 当前生效的 profile（null = 未加载，所有查询返回空）
static var _profile: ArtProfile = null

## 默认 profile 路径（首次查询时惰性加载）
const DEFAULT_PROFILE_PATH := "res://data/art/default_profile.tres"


## 当前生效的 profile（null 表示未加载）
##
## **惰性加载默认配置**：首次调用时尝试加载 `default_profile.tres`。
## 加载失败（文件不存在/损坏）时返回 null 并保持 null——
## 不报错、不中断，消费方走原逻辑即可。
static func profile() -> ArtProfile:
	if _profile == null:
		_profile = _load_default()
	return _profile


## 热切换 profile（界面改完调这个）
##
## 传 null 表示「清空配置」——之后所有查询返回空，消费方走原逻辑。
static func set_profile(p: ArtProfile) -> void:
	_profile = p


## 重新从磁盘加载默认 profile（界面保存后调，让运行时看到新值）
static func reload() -> void:
	_profile = _load_default()


# ============================================================
# 装饰物查询
# ============================================================

## 某用途的装饰模型路径（空串 = 未配置，消费方走原逻辑）
##
## **必须用 `load()` 校验而不是只看路径非空**：`.import` 损坏的资源
## 路径是对的但加载不出来（项目已知陷阱，实测 castle-kit 76 个里 30 个）。
## 校验一次的开销可忽略（Godot 有资源缓存），但能避免
## 「配了模型却显示方块」这种最难查的问题。
static func prop_model(prop_type: String) -> String:
	var p := profile()
	if p == null:
		return ""
	var path := p.prop_model(prop_type)
	if path.is_empty():
		return ""
	# 路径配了但加载不出来 → 视同未配置，让消费方走占位
	if load(path) == null:
		push_warning("[ArtRegistry] 装饰 '%s' 的模型加载失败：%s（回退到占位）"
			% [prop_type, path])
		return ""
	return path


## 某用途的装饰变换参数（中性值 = 不缩放/不偏移/不旋转）
static func prop_transform(prop_type: String) -> Dictionary:
	var p := profile()
	if p == null:
		return {"scale": 1.0, "y_offset": 0.0, "y_rotation_deg": 0.0}
	return p.prop_transform(prop_type)


## 全部已配置且可用的装饰用途（供界面/调试显示）
static func configured_props() -> Array:
	var p := profile()
	return p.configured_props() if p != null else []


# ============================================================
# 其他类别（字段已留，消费方待素材到位后接入）
# ============================================================

## 某单位（敌人种类 / "player"）的模型路径（空串 = 未配置）
static func unit_model(kind: String) -> String:
	var p := profile()
	if p == null:
		return ""
	var v = p.units.get(kind, {})
	if not (v is Dictionary):
		return ""
	var path := str(v.get("model_path", ""))
	if path.is_empty() or load(path) == null:
		return ""
	return path


## 某装备模板的模型路径（空串 = 未配置）
static func equipment_model(template_id: String) -> String:
	var p := profile()
	if p == null:
		return ""
	var v = p.equipment.get(template_id, {})
	if not (v is Dictionary):
		return ""
	var path := str(v.get("model_path", ""))
	if path.is_empty() or load(path) == null:
		return ""
	return path


## 某特效的场景路径（空串 = 未配置）
static func effect_scene(effect_id: String) -> String:
	var p := profile()
	if p == null:
		return ""
	var v = p.effects.get(effect_id, {})
	if not (v is Dictionary):
		return ""
	var path := str(v.get("scene_path", ""))
	if path.is_empty() or load(path) == null:
		return ""
	return path


# ============================================================
# 内部
# ============================================================

static func _load_default() -> ArtProfile:
	if not ResourceLoader.exists(DEFAULT_PROFILE_PATH):
		return null
	var r = load(DEFAULT_PROFILE_PATH)
	return r as ArtProfile
