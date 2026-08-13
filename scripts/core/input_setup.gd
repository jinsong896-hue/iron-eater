extends Node
## 输入动作注册（原型阶段在代码里配置 InputMap，避免手写 project.godot 事件序列化）

func _enter_tree() -> void:
	_ensure_action("move_left", KEY_A)
	_ensure_action("move_right", KEY_D)
	_ensure_action("move_up", KEY_W)
	_ensure_action("move_down", KEY_S)
	_ensure_action("attack", KEY_J)
	_ensure_action("attack_up", KEY_UP)
	_ensure_action("attack_down", KEY_DOWN)
	_ensure_action("attack_left", KEY_LEFT)
	_ensure_action("attack_right", KEY_RIGHT)
	_ensure_action("toggle_inventory", KEY_TAB)
	_ensure_action("dungeon_regenerate", KEY_R)
	_ensure_action("dungeon_next_layer", KEY_N)

	# 鼠标左键同样触发攻击
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mouse)


func _ensure_action(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)
