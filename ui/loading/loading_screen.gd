extends CanvasLayer
class_name LoadingScreen
## 加载过渡 —— 两段式
##
## 【第一段 · 切入】(场景切换时，挂在 SceneManager 上，跨场景存活)
##   玩家从菜单进入游戏、或层与层之间：盖住整屏 → 隐藏生成过程 → 淡出。
##   **最低时长受 RoomLoader.MIN_DURATION 约束**（策划 11.8：单房间加载 < 1 秒），
##   生成更快也不会缩短，保证节奏稳定、不闪烁。
##
## 【第二段 · 房内】(玩家已站在初始房，由 GameRoot 驱动)
##   不遮挡视野，只在屏幕下方显示细进度条，把剩余房间的预建摊开。
##   玩家此时可以自由行动（进度条不拦输入）。
##
## 两段的时长都以 RoomLoader.MIN_DURATION 为准：整层生成绝不超过 1 秒，
## 也不再额外拖长等待。

const COLOR_BG := Color(0.035, 0.039, 0.043, 1.0)     # #090A0B
const COLOR_TEXT := Color(0.914, 0.898, 0.863)        # #E9E5DC
const COLOR_DIM := Color(0.545, 0.545, 0.529)         # #8B8B87
const COLOR_GOLD := Color(0.71, 0.592, 0.384)         # #B59762
const COLOR_RUST := Color(0.608, 0.376, 0.271)        # #9B6045

var _overlay: ColorRect = null
var _title: Label = null
var _hint: Label = null
var _panel: Control = null        ## 第二段的房内进度条容器
var _bar_bg: ColorRect = null
var _bar_fill: ColorRect = null
var _bar_label: Label = null

var _elapsed := 0.0
var _min_duration := 1.0
var _holding := false             ## 是否处于「等最低时长」阶段
var _in_game_progress := false    ## 是否显示房内进度条


func _ready() -> void:
	# 过渡必须在暂停时也能推进（结算/暂停状态下切场景也要能淡出）
	process_mode = PROCESS_MODE_ALWAYS
	layer = 100                   # 盖在所有 UI 之上
	_build()
	visible = false


func _build() -> void:
	# —— 第一段：全屏遮罩 ——
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = COLOR_BG
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	_title = Label.new()
	_title.text = "噬 铁 者"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", COLOR_TEXT)
	_title.add_theme_font_size_override("font_size", 34)
	box.add_child(_title)

	var rule := ColorRect.new()
	rule.color = COLOR_RUST
	rule.custom_minimum_size = Vector2(120, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rule)

	_hint = Label.new()
	_hint.text = "正在进入地下城…"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", COLOR_DIM)
	_hint.add_theme_font_size_override("font_size", 16)
	box.add_child(_hint)

	# —— 第二段：房内进度条（不遮挡视野）——
	_panel = Control.new()
	_panel.name = "InGameProgress"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var bar_box := VBoxContainer.new()
	bar_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar_box.position = Vector2(0, -90)
	bar_box.custom_minimum_size = Vector2(320, 0)
	bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(bar_box)

	_bar_label = Label.new()
	_bar_label.text = "场景构建中"
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.add_theme_color_override("font_color", COLOR_DIM)
	_bar_label.add_theme_font_size_override("font_size", 13)
	bar_box.add_child(_bar_label)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(1, 1, 1, 0.10)
	_bar_bg.custom_minimum_size = Vector2(320, 3)
	bar_box.add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = COLOR_GOLD
	_bar_fill.size = Vector2(0, 3)
	_bar_fill.position = Vector2.ZERO
	_bar_bg.add_child(_bar_fill)

	_panel.visible = false


func _process(delta: float) -> void:
	if _holding:
		_elapsed += delta


## ========== 第一段：切入 ==========
## 盖上并开始计时。await 完成后遮罩已全黑。
func begin(duration: float, title: String = "", hint: String = "") -> void:
	_min_duration = maxf(duration, 0.01)
	_elapsed = 0.0
	_holding = true
	_in_game_progress = false
	_panel.visible = false
	if title != "":
		_title.text = title
	if hint != "":
		_hint.text = hint

	_overlay.modulate.a = 0.0
	# 恢复输入拦截：上一轮 finish 时放开了它（见 finish 的说明），
	# 本轮要重新挡住输入，否则过渡期间玩家能点到下面的 UI。
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 1.0, 0.12)
	await tween.finished


## 等满最低时长后淡出。若生成超过最低时长，立即淡出（不额外等待）。
##
## **淡出前必须先放开鼠标拦截**：遮罩是 `MOUSE_FILTER_STOP` 的全屏 ColorRect，
## 只要它还拦截输入，下面的 UI 就完全点不动。而 `visible = false` 在
## `await tween.finished` 之后——tween 一旦被打断（节点释放、被新 tween
## 顶掉、切场景时正在 await），这行就永远不会执行，
## 留下一个 **alpha=0 却拦截一切点击的隐形遮罩**。
## 实机症状正是「回到主界面后 UI 无法再次触发」。
## 故不把"能否操作"绑在动画完成上：一进 finish 就放开输入。
func finish() -> void:
	if _overlay != null:
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wait := maxf(_min_duration - _elapsed, 0.0)
	if wait > 0.0:
		await get_tree().create_timer(wait, true, false, true).timeout
	_holding = false
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 0.0, 0.18)
	await tween.finished
	visible = false


## 立即隐藏并放开输入（不播淡出）。
## 给"切场景等不了 0.18 秒淡出"的路径用，避免淡出动画与场景切换竞争。
func hide_now() -> void:
	if _overlay != null:
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.modulate.a = 0.0
	_holding = false
	visible = false


## 生成耗时汇报（供日志/调试）
func report(gen_seconds: float) -> void:
	if gen_seconds > _min_duration:
		push_warning("房间生成 %.3fs 超过策划预算 %.1fs（总册 11.8）"
			% [gen_seconds, _min_duration])


## ========== 第二段：房内进度 ==========
## 玩家已在初始房内，显示细进度条推进剩余房间预建
func show_in_game_progress(show_it: bool) -> void:
	if _in_game_progress == show_it:
		return
	_in_game_progress = show_it
	_panel.visible = show_it
	if not show_it:
		visible = false


## 更新房内进度（0.0~1.0）
func set_progress(ratio: float) -> void:
	if _bar_fill == null:
		return
	_bar_fill.size = Vector2(320.0 * clampf(ratio, 0.0, 1.0), 3.0)
	if _bar_label != null:
		_bar_label.text = "场景构建中 %d%%" % int(clampf(ratio, 0.0, 1.0) * 100.0)
