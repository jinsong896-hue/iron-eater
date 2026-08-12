class_name RoomCamera
extends Camera2D
## 房间相机：《关卡设计分册》五、摄像机与视口配置
## 房间边界 → Camera2D Limit，切换时平滑过渡（推镜头）

const VIEWPORT := Vector2(1280, 720)

var _tween: Tween


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0
	make_current()


func switch_to_room(room_rect: Rect2) -> void:
	var l := room_rect.position.x
	var t := room_rect.position.y
	var r := room_rect.end.x
	var b := room_rect.end.y
	# 房间小于视口时居中（Godot 小 Limit 会自动居中，这里显式扩展）
	if r - l < VIEWPORT.x:
		var cx := (l + r) * 0.5
		l = cx - VIEWPORT.x * 0.5
		r = cx + VIEWPORT.x * 0.5
	if b - t < VIEWPORT.y:
		var cy := (t + b) * 0.5
		t = cy - VIEWPORT.y * 0.5
		b = cy + VIEWPORT.y * 0.5
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "limit_left", l, 0.4)
	_tween.tween_property(self, "limit_top", t, 0.4)
	_tween.tween_property(self, "limit_right", r, 0.4)
	_tween.tween_property(self, "limit_bottom", b, 0.4)
