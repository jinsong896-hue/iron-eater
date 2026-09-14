extends CanvasLayer
## 调试控制台 —— 实机测试模式的**总开关**入口
##
## 按 ` 开关。输入 `testmode on` 之前，除 testmode / help 外所有命令都被拒绝
## （闸门在 DebugManager.execute 里，不在这里——保证控制台与面板走同一条路径）。
##
## 敲字时必须让角色停手：LineEdit 只吞**事件**，而 InputManager 是每帧轮询，
## 故 InputManager 会问 DebugManager.is_text_input_active()，本控制台的 visible
## 就是那个判断依据。

@onready var _output: RichTextLabel = get_node_or_null("Root/Panel/VBox/Output")
@onready var _input_box: LineEdit = get_node_or_null("Root/Panel/VBox/Input")

const MAX_LINES := 200

var _history: Array[String] = []
var _hist_pos := -1


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	if _input_box:
		_input_box.text_submitted.connect(_on_submitted)
	var dm := _debug_manager()
	if dm and dm.has_method("register_console"):
		dm.call("register_console", self)
	_print_line("《噬铁者》调试控制台。输入 help 查看命令。")
	_print_line("首次使用需先执行：testmode on")


func _debug_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("DebugManager")
	return null


# ============================================================
# 开关
# ============================================================

## 用 _input 而非 _unhandled_input：Esc 要能关掉自己，
## 而 LineEdit 会把按键事件吞掉，_unhandled_input 收不到。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_console"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
		return
	if visible and event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		# 上下键翻历史（LineEdit 的默认光标行为在这里用处不大）
		if kc == KEY_UP:
			_recall(-1)
			get_viewport().set_input_as_handled()
		elif kc == KEY_DOWN:
			_recall(1)
			get_viewport().set_input_as_handled()
		elif kc == KEY_TAB:
			_complete()
			get_viewport().set_input_as_handled()


## Tab 自动补全：一个候选直接补全；多个候选补到公共前缀并列出全部。
func _complete() -> void:
	if _input_box == null:
		return
	var dm := _debug_manager()
	if dm == null or not dm.has_method("complete"):
		return
	var line := _input_box.text
	var r: Dictionary = dm.call("complete", line)
	var cands: Array = r.get("candidates", [])
	if cands.is_empty():
		return
	if cands.size() == 1:
		_apply_completion(line, str(r.get("token", "")), str(cands[0]))
		return
	# 多个候选：先补到公共前缀，再把候选列出来
	var DP = load("res://core/debug_parser.gd")
	var pre: String = DP.common_prefix(cands)
	if pre.length() > str(r.get("token", "")).length():
		_apply_completion(line, str(r.get("token", "")), pre)
	# 候选太多（如 64 个怪物）只显示数量与前若干个，避免刷屏
	var show: Array = cands.slice(0, 12)
	var more := "" if cands.size() <= 12 else "  …共 %d 个" % cands.size()
	_print_line("  候选：%s%s" % ["  ".join(show), more])


## 用 repl 替换行尾的那个 token（保留前面的内容）
## 用 repl 替换行尾的那个 token（保留前面的内容）。
## 若补出的 token 后面还没有空格，自动补一个 —— 补全后可以立刻接着输参数。
func _apply_completion(line: String, token: String, repl: String) -> void:
	var start := line.length() - token.length()
	var newline := line.substr(0, start) + repl
	if not newline.ends_with(" "):
		newline += " "
	_input_box.text = newline
	_input_box.caret_column = newline.length()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	_reconcile()
	if _input_box:
		_input_box.grab_focus()
		_input_box.clear()


func close() -> void:
	visible = false
	_reconcile()


func _reconcile() -> void:
	var dm := _debug_manager()
	if dm and dm.has_method("reconcile_modal"):
		dm.call("reconcile_modal")


# ============================================================
# 执行
# ============================================================

func _on_submitted(line: String) -> void:
	var text := line.strip_edges()
	if _input_box:
		_input_box.clear()
	if text == "":
		return
	_history.append(text)
	_hist_pos = -1
	_print_line("> %s" % text)

	var dm := _debug_manager()
	if dm == null or not dm.has_method("execute"):
		_print_line("[错误] DebugManager 不可用")
		return
	var r: Dictionary = dm.call("execute", text)
	if not r.get("ok", false):
		var e := str(r.get("error", ""))
		if e != "":                    # 空行静默
			_print_line("[错误] %s" % e)
		return
	var out := str(r.get("text", ""))
	if out != "":
		_print_line(out)


func _recall(dir: int) -> void:
	if _history.is_empty() or _input_box == null:
		return
	if _hist_pos == -1:
		_hist_pos = _history.size() - 1 if dir < 0 else _history.size()
	else:
		_hist_pos = clampi(_hist_pos + dir, 0, _history.size() - 1)
	_input_box.text = _history[_hist_pos]
	_input_box.caret_column = _input_box.text.length()


func _print_line(s: String) -> void:
	if _output == null:
		return
	_output.append_text(s + "\n")
	# 只保留最近 N 行，避免长时间使用后无限增长
	var lines := _output.get_parsed_text().split("\n")
	if lines.size() > MAX_LINES:
		_output.clear()
		_output.append_text("\n".join(lines.slice(lines.size() - MAX_LINES)) + "\n")


## 供测试读取回显内容
func output_text() -> String:
	return _output.get_parsed_text() if _output else ""
