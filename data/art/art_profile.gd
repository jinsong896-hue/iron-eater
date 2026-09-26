class_name ArtProfile
extends Resource
## 美术资源分配表 —— 「用途 → 资源」的可配置映射
##
## ## 为什么需要它
##
## 在此之前，「哪个用途用哪个美术资源」全是**硬编码 GDScript 常量表**：
##   · `decoration_builder.PROP_PATHS`  装饰类型 → .tscn 路径
##   · `enemy_visuals.build()`          按 AIBehavior 枚举 match 出颜色
##   · `AtlasDefs.FLOOR_TILES`          主题 → 图集格坐标
##
## 后果：换一个模型要改代码、重新跑；非程序员无法参与；而且**悬空路径
## 无人发现**——实测 `PROP_PATHS` 5 条里 3 条指向不存在的文件，
## 每次加载失败后静默回退到方块占位。
##
## 本资源把这份映射**外提为数据**，于是：
##   · 可视化界面（编辑器 / 游戏内）能读写
##   · 校验工具能提前发现悬空引用
##   · 运行时可热切换
##
## ## 设计原则
##
## **只存「差异」，不存「默认值」**。未配置的用途由消费方走原有逻辑，
## 因此空 profile 的行为与接入前**完全一致**——这让接入可以分阶段进行，
## 且任何时候出问题都能一键回到原状。
##
## ## 与设计文档的关系
##
## `ai/框架相关.md:3231` 起的「Asset Browser / Character Studio」愿景
## 比本类大得多（含骨骼、动画、技能图）。本类是其中**可立即落地**的
## 子集：先把「用途 → 资源」这条链路打通，其余类别按同一模式增量添加。

## 装饰物配置：`prop_type → {model_path, scale, y_offset, y_rotation_deg}`
##
## `prop_type` 是房间 JSON 里 `entities[].type` 的值（torch / chest /
## barrel / pillar / …）。
##
## `model_path` 空串表示「该用途未配置」——消费方走原有 `.tscn` 或占位逻辑。
@export var props: Dictionary = {}

## 单位配置：`unit_kind → {model_path, scale, y_offset, y_rotation_deg}`
##
## `unit_kind` 是敌人种类（见 `AIBehavior`）或 `"player"`。
##
## **当前为空**：项目还没有任何生物模型（castle-kit 全是建筑）。
## 字段先留着，等素材到位后直接填，消费方已按同一模式接好。
@export var units: Dictionary = {}

## 装备配置：`template_id → {model_path, socket}`
##
## **当前为空**：项目还没有武器/护甲模型。
## `EquipmentTemplate` 早有 `scene_path`/`icon_path` 字段但零读取，
## 本表是它的替代方案（按 id 集中管理，比散落在 300+ 个模板上更好维护）。
@export var equipment: Dictionary = {}

## 特效配置：`effect_id → {scene_path, color, scale}`
##
## **当前为空**：`特效素材/` 是空目录，特效目前全是代码生成的粒子。
@export var effects: Dictionary = {}


## 取某用途的装饰配置（未配置返回空字典）
func prop(prop_type: String) -> Dictionary:
	var v = props.get(prop_type, {})
	return v if v is Dictionary else {}


## 取某用途的装饰模型路径（未配置返回空串）
func prop_model(prop_type: String) -> String:
	return str(prop(prop_type).get("model_path", ""))


## 取某用途的变换参数（未配置时返回中性值：不缩放、不偏移、不旋转）
##
## **返回中性值而非报错**：调用方拿到后直接应用即可，
## 不必到处判空。`scale = 1.0` 是 castle-kit 的正确值——
## 实测其 AABB 是 1.00 单位宽，与项目 `CELL_SIZE = 1.0` 匹配。
func prop_transform(prop_type: String) -> Dictionary:
	var c := prop(prop_type)
	return {
		"scale": float(c.get("scale", 1.0)),
		"y_offset": float(c.get("y_offset", 0.0)),
		"y_rotation_deg": float(c.get("y_rotation_deg", 0.0)),
	}


## 全部已配置的装饰用途（供界面列列表）
func configured_props() -> Array:
	var out: Array = []
	for k in props:
		if props[k] is Dictionary and not str(props[k].get("model_path", "")).is_empty():
			out.append(str(k))
	out.sort()
	return out


## 设置某用途的装饰配置
func set_prop(prop_type: String, model_path: String, scale: float = 1.0,
		y_offset: float = 0.0, y_rotation_deg: float = 0.0) -> void:
	props[prop_type] = {
		"model_path": model_path,
		"scale": scale,
		"y_offset": y_offset,
		"y_rotation_deg": y_rotation_deg,
	}


## 移除某用途的配置（回到「未配置」，消费方走原逻辑）
func clear_prop(prop_type: String) -> void:
	props.erase(prop_type)


## 校验：所有已配置的 `model_path` 是否真的能加载
##
## **必须用 `load()` 而不是 `ResourceLoader.exists()`**——项目已知陷阱：
## `.import` 里 `valid=false` 的资源，`exists()` 仍返回 true 但 `load()`
## 返回 null（实测 castle-kit 76 个模型里 30 个如此）。
## 用 `exists()` 校验会报「全部正常」的假绿灯。
##
## 返回 `[{prop_type, model_path, reason}]`，空数组表示全部可用。
func validate() -> Array:
	var bad: Array = []
	for k in props:
		if not (props[k] is Dictionary):
			bad.append({"prop_type": str(k), "model_path": "", "reason": "配置格式错误"})
			continue
		var p := str(props[k].get("model_path", ""))
		if p.is_empty():
			continue
		if load(p) == null:
			bad.append({"prop_type": str(k), "model_path": p,
				"reason": "load() 返回 null（导入失败或文件缺失）"})
	return bad
