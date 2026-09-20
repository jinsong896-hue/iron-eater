class_name WorldEnvironmentManager
extends Node
## 世界环境管理器 —— 楼层主题（雾色 / 环境光）的**唯一归属处**。
##
## ## 为什么需要它
##
## 楼层视觉主题（每层的雾色、环境光色与强度）原先写在
## `GameRoot._apply_floor_environment()` 里。独立出来是为了让
## "环境长什么样"与"地牢怎么生成"分开——改配色不必翻 1100 行的 GameRoot。
##
## ## 装配方式：注入 WorldEnvironment
##
## 由 `GameRoot._setup_environment()` 创建并把场景里的 `WorldEnvironment`
## **注入**进来。不让本类自己找：`WorldEnvironment` 挂在 SubViewport 子树下，
## 而本类是 GameRoot 的子节点——`find_children` 只搜自己的后代，
## 找不到兄弟分支里的节点。
##
## ## 关于 `PostProcess.apply_hd2d_settings`（**本类不再调用**）
##
## 旧实现在 `_ready()` 里调它来"应用 HD-2D 默认设置"。核对后**移除**：
## `main.tscn` 的 `Environment` sub-resource 才是当前真正在跑的那份值，
## 而 `apply_hd2d_settings` 有几处与它**不一致**，调用会改变视觉：
##
## | 字段 | main.tscn（在跑） | apply_hd2d_settings |
## |---|---|---|
## | `ambient_light_source` | **COLOR(2)** | SKY(3) ← 环境光来源变了 |
## | `glow_levels` | 未设（全 0） | lv1=1.0 / lv4=0.4 |
## | `glow_strength` / `hdr_bleed_*` | 未设（默认） | 显式设值 |
## | `ssao_power/detail/horizon/sharpness` | 未设（默认） | 显式设值 |
##
## 即 `main.tscn` 是一份**独立演化的**环境配置，两边已经分叉。
## 启动时调用它等于把在跑的那份覆盖掉——属视觉变化，不做。
## 若将来要统一，应先决定以哪份为准，再让两边收敛到一处。

## 目标 WorldEnvironment（由 `setup()` 注入）
@export var world_environment: WorldEnvironment

var _environment: Environment


## 装配：注入场景里的 WorldEnvironment。
##
## 场景里没有时自建一个（兜底，保证 `apply_floor` 不会因缺节点而静默失效）。
## **必须在 `add_child` 之后调用**——兜底分支要 `get_parent()`。
func setup(we: WorldEnvironment) -> void:
	world_environment = we
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		world_environment.name = "WorldEnvironment"
		get_parent().add_child(world_environment)
	_environment = world_environment.environment
	if _environment == null:
		_environment = Environment.new()
		world_environment.environment = _environment


## 获取 Environment 资源
func get_environment() -> Environment:
	return _environment


## 设置雾的颜色
func set_fog_color(color: Color) -> void:
	if _environment:
		_environment.fog_light_color = color


## 设置雾的密度
func set_fog_density(density: float) -> void:
	if _environment:
		_environment.fog_density = density


## 启用/禁用 SSAO
func set_ssao(enabled: bool) -> void:
	if _environment:
		_environment.ssao_enabled = enabled


## 设置泛光强度
func set_glow_intensity(intensity: float) -> void:
	if _environment:
		_environment.glow_intensity = intensity


## 应用主题环境（按 ThemeLibrary 的 4 套通用主题）。
##
## **与 `apply_floor` 是两套并行的配色来源**（遗留问题，未处理）：
## 楼层系统走 `FloorDefs` 的 9 层主题，本方法走 `ThemeLibrary` 的 4 套通用主题，
## 两者互不知晓。目前无调用者——保留给"非楼层场景（编辑器预览等）"。
func apply_theme(theme_id: String) -> void:
	ThemeLibrary.set_theme(theme_id)
	var theme := ThemeLibrary.get_current()
	if theme.is_empty():
		return

	if _environment:
		_environment.fog_light_color = theme.get("fog_color", Color.WHITE)
		_environment.ambient_light_color = theme.get("ambient_color", Color.WHITE)


## 按**楼层**应用主题环境（FloorDefs 的 9 层配色）。
## 由 GameRoot 在生成地牢时调用——每层雾色/环境光各不相同，
## 配合房间地板墙配色一起构成该层的视觉主题。
##
## **环境光强度系数取 1.6**（用户决策）：这是 `GameRoot` 原先在跑的值，
## 沿用可保证视觉零变化。旧代码写的 1.2 从未执行过（本类此前零引用）。
func apply_floor(floor_num: int) -> void:
	if _environment == null:
		return
	_environment.fog_light_color = FloorDefs.color_of(floor_num, "fog")
	_environment.ambient_light_color = FloorDefs.color_of(floor_num, "ambient")
	# 环境光强度随主题明度走：偏暗的层（虚空/裂隙）压暗，明亮层（熔炉/王座）提亮
	var amb := FloorDefs.color_of(floor_num, "ambient")
	var lum := (amb.r + amb.g + amb.b) / 3.0
	_environment.ambient_light_energy = clampf(0.4 + lum * 1.6, 0.3, 0.9)
