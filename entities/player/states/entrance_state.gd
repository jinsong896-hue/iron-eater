extends PlayerState
## 入场状态 —— 玩家进入初始房间时原地播放一段特殊动作
##
## 由 GameRoot 在加载完初始房后调用 player.play_entrance()。
## 期间：
##   · 速度归零（原地不动，不受输入影响）
##   · 不接受攻击/翻滚/技能（整体锁输入）
##   · 播完自动回到 MoveState
##
## **视觉留给美术**：当前只有"呼吸/起身"式的程序化表现（轻微起伏 + 面向镜头）。
## 真正的主角入场动画TODO：把 _play_visual() 换成 AnimationPlayer.play("entrance")
## 即可，状态本身不用改。

## 入场时长（秒）。玩家入场动画做好后，改为读动画长度。
const ENTRANCE_DURATION := 1.2

var _elapsed := 0.0
var _duration := ENTRANCE_DURATION
var _tween: Tween = null


func setup(p_player: Player) -> void:
	super.setup(p_player)


## 允许外部指定时长（GameRoot 可传动画长度）
func enter(_previous: String, data: Dictionary = {}) -> void:
	_elapsed = 0.0
	_duration = maxf(float(data.get("duration", ENTRANCE_DURATION)), 0.05)
	var p := player
	if p == null:
		return
	# 原地站定
	p.velocity = Vector3.ZERO
	_play_visual()


func physics_update(delta: float) -> void:
	var p := player
	if p == null:
		return
	# 锁死位移：即使有输入也不动（入场表演期间玩家不该乱跑）
	p.velocity.x = 0.0
	p.velocity.z = 0.0
	p.move_and_slide()

	_elapsed += delta
	if _elapsed >= _duration:
		finished.emit("MoveState", {})


func exit() -> void:
	_stop_visual()


## 入场表现。**替换点**：接真正的动画时改这里
func _play_visual() -> void:
	var p := player
	if p == null:
		return
	var model := p.get_node_or_null("Model") as Node3D
	if model == null:
		return
	# 程序化占位：轻微「起身」——先下压再回正，带一点放大
	_stop_visual()
	var base_y := model.position.y
	var base_scale := model.scale
	_tween = p.create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(model, "position:y", base_y - 0.25, 0.18)
	_tween.parallel().tween_property(model, "scale", base_scale * 1.06, 0.18)
	_tween.tween_property(model, "position:y", base_y, _duration - 0.18)
	_tween.parallel().tween_property(model, "scale", base_scale, _duration - 0.18)


func _stop_visual() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	var p := player
	if p == null:
		return
	var model := p.get_node_or_null("Model") as Node3D
	if model != null:
		model.position.y = 0.0
		model.scale = Vector3.ONE
