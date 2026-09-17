extends CanvasLayer
## HUD 主控制器 —— HD-2D 重构版
## 暗黑风格：血球 / 蓝球 / 6技能槽 / 4道具槽 / Buff栏 / 小地图

@onready var health_orb: TextureProgressBar = $BottomBar/HealthOrb
@onready var health_label: Label = $BottomBar/HealthOrb/HealthLabel
@onready var mana_orb: TextureProgressBar = $BottomBar/ManaOrb
@onready var mana_label: Label = $BottomBar/ManaOrb/ManaLabel

@onready var gold_label: Label = $TopLeft/GoldLabel
@onready var floor_label: Label = $TopLeft/FloorLabel
@onready var combo_label: Label = $TopLeft/ComboLabel
@onready var message_label: Label = $TopLeft/MessageLabel
@onready var buff_bar: HBoxContainer = $BuffBar
@onready var minimap: MinimapView = $Minimap
@onready var boss_bar: Control = $BossBar
@onready var boss_name_label: Label = $BossBar/BossName
@onready var boss_bar_bg: ColorRect = $BossBar/BossBarBg
@onready var boss_bar_fill: ColorRect = $BossBar/BossBarFill

var skill_buttons: Array[Button] = []
var item_buttons: Array[Button] = []

# Boss 血条栏状态
var _boss_entity: Node = null
var _boss_max_hp := 1.0


func _ready() -> void:
	_collect_skill_buttons()
	_collect_item_buttons()
	_connect_signals()
	_update_display()
	set_process(true)


## 每帧刷新连击数（轮询玩家，简单可靠）+ 状态图标条
func _process(_delta: float) -> void:
	_update_boss_bar()
	_update_buff_icons()
	_update_skill_bar()
	# 资源球（魔力/怒气/…）必须每帧刷新：它是**连续变化**的
	#（法师每秒回蓝），而 _update_display 此前只在 stats_changed /
	# player_hit 等事件时被调——回蓝过程球根本不动，
	# 玩家看到的就是"蓝量不恢复"。
	_update_display()
	if combo_label == null:
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p = players[0]
	if p and p.has_method("get_hit_combo"):
		var count: int = p.get_hit_combo()
		combo_label.text = "连击 x%d" % count if count >= 2 else ""


# ============================================================
# 状态图标条（BuffBar）
# ============================================================
## 每个图标节点复用的缓存：id -> {"root": Control, "label": Label, "bar": ColorRect, ...}
##
## **为什么每帧重建不可取**：状态会持续若干秒，每帧 new/free 节点会造成
## 持续的 GC 压力与布局抖动。这里按 id 复用，只在状态增删时改节点数。
var _buff_icons: Dictionary = {}
## 图标尺寸（像素）。16×16 一屏能放下 20+ 个，不挡视野。
const BUFF_ICON_SIZE := 30
const BUFF_ICON_GAP := 4


## 按玩家当前状态刷新图标条
func _update_buff_icons() -> void:
	if buff_bar == null:
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p = players[0]
	var pb = p.get("buffs")
	if pb == null or not pb.has_method("ui_snapshot"):
		return
	var snap: Array = pb.call("ui_snapshot")

	# 收集本次出现的 id，用于回收消失的图标
	var alive := {}
	for info in snap:
		var bid := str(info.get("id", ""))
		if bid.is_empty():
			continue
		alive[bid] = true
		var icon: Control = _buff_icons.get(bid)
		if icon == null:
			icon = _make_buff_icon()
			_buff_icons[bid] = icon
			buff_bar.add_child(icon)
		_paint_buff_icon(icon, info)

	# 回收：本次没出现的一律移除
	for bid in _buff_icons.keys():
		if alive.has(bid):
			continue
		var ic: Control = _buff_icons[bid]
		if is_instance_valid(ic):
			ic.queue_free()
		_buff_icons.erase(bid)


## 创建一个状态图标（方块底 + 名字首字 + 底部时间条）。
## 纯程序化绘制——项目没有 buff 图标美术资源，用「首字 + 颜色」表达类型，
## 与背包格子的做法一致（见 backpack_item.gd）。
func _make_buff_icon() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(BUFF_ICON_SIZE, BUFF_ICON_SIZE)

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var txt := Label.new()
	txt.name = "Glyph"
	txt.set_anchors_preset(Control.PRESET_FULL_RECT)
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.add_theme_font_size_override("font_size", 16)
	root.add_child(txt)

	# 剩余时间条：贴在图标底部（永久状态不显示）
	var bar := ColorRect.new()
	bar.name = "TimeBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.color = Color(1, 1, 1, 0.85)
	root.add_child(bar)

	# 层数角标（右下角，仅叠层 > 1 时显示）
	var stack := Label.new()
	stack.name = "Stacks"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	stack.add_theme_font_size_override("font_size", 12)
	stack.add_theme_color_override("font_color", Color(1, 1, 0.6))
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(stack)

	# 悬停说明（把鼠标放在图标上能看到完整名称与剩余时间）
	root.tooltip_text = ""
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	return root


## 把一份状态快照画到图标上
func _paint_buff_icon(icon: Control, info: Dictionary) -> void:
	var name_s := str(info.get("name", "?"))
	var stacks := int(info.get("stacks", 1))
	var permanent := bool(info.get("permanent", false))
	var is_debuff := bool(info.get("is_debuff", true))
	var remaining := float(info.get("remaining", 0.0))
	var total := float(info.get("total", 0.0))

	# 底色：负面红 / 正面绿（首字用名称第一个字，中文一格足矣）
	var bg := icon.get_node_or_null("Bg") as ColorRect
	if bg != null:
		bg.color = (Color(0.55, 0.15, 0.15, 0.9) if is_debuff
			else Color(0.15, 0.45, 0.20, 0.9))

	var glyph := icon.get_node_or_null("Glyph") as Label
	if glyph != null:
		glyph.text = name_s.substr(0, 1)

	# 底部时间条：永久状态画满条（表示"∞"），限时状态按剩余比例收缩
	var bar := icon.get_node_or_null("TimeBar") as ColorRect
	if bar != null:
		var ratio := 1.0
		if not permanent and total > 0.0:
			ratio = clampf(remaining / total, 0.0, 1.0)
		bar.size = Vector2(float(BUFF_ICON_SIZE) * ratio, 3.0)
		bar.position = Vector2(0.0, float(BUFF_ICON_SIZE) - 3.0)
		bar.color = (Color(0.6, 0.6, 0.6, 0.8) if permanent
			else Color(1.0, 1.0, 1.0, 0.85))

	var stk := icon.get_node_or_null("Stacks") as Label
	if stk != null:
		stk.text = ("x%d" % stacks) if stacks > 1 else ""

	# 悬停提示：名称 + 层数 + 剩余时间
	var tip := name_s
	if stacks > 1:
		tip += " ×%d" % stacks
	if permanent:
		tip += "（持续）"
	elif total > 0.0:
		tip += "（%.1fs）" % maxf(remaining, 0.0)
	icon.tooltip_text = tip


func _collect_skill_buttons() -> void:
	var skill_bar := $BottomBar/SkillBar
	var idx := 0
	for child in skill_bar.get_children():
		if child is Button:
			var btn := child as Button
			skill_buttons.append(btn)
			# 点击也能施放（鼠标玩家 / 触屏），与键盘 1~6 等价
			btn.pressed.connect(_on_skill_button_pressed.bind(idx))
			idx += 1


## 点击技能槽 → 交给玩家施放
func _on_skill_button_pressed(slot: int) -> void:
	var p := _local_player()
	if p != null and p.has_method("cast_skill_slot"):
		p.call("cast_skill_slot", slot)


## 刷新技能条：当前形态的技能名 + 冷却遮罩 + 无技能槽灰显。
## 每帧调（冷却要连续衰减），但只在内容变化时改文字，避免每帧重排版。
func _update_skill_bar() -> void:
	if skill_buttons.is_empty():
		return
	var p := _local_player()
	if p == null or not p.has_method("current_skills"):
		for b in skill_buttons:
			b.disabled = true
		return
	var list: Array = p.call("current_skills")
	for i in range(skill_buttons.size()):
		var btn := skill_buttons[i]
		if i >= list.size():
			# 该形态没有这么多技能：灰显 + 只留键位号
			btn.disabled = true
			btn.text = "%d" % (i + 1)
			continue
		var sd: Dictionary = list[i]
		var sname := str(sd.get("name", ""))
		var cd_left := float(p.call("skill_cooldown_left", str(sd.get("id", ""))))
		btn.disabled = false
		# 冷却中显示剩余秒数，否则显示「键位·技能名」
		var label := "%d·%s" % [i + 1, sname]
		if cd_left > 0.0:
			label = "%s\n%.1fs" % [sname, cd_left]
		if btn.text != label:
			btn.text = label
		# 冷却中调暗（TODO「冷却遮罩」的最简实现：整按钮 modulate）
		btn.modulate = Color(0.55, 0.55, 0.6) if cd_left > 0.0 else Color.WHITE


## 本场景的玩家（HUD 通常在 main.tscn 里与 Player 同级）
func _local_player() -> Node:
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] if not ps.is_empty() else null


func _collect_item_buttons() -> void:
	var item_bar := $BottomBar/ItemBar
	for child in item_bar.get_children():
		if child is Button:
			item_buttons.append(child as Button)


func _connect_signals() -> void:
	var eb := get_node_or_null("/root/EventBus")
	if eb == null:
		return
	if eb.has_signal("stats_changed"):
		eb.stats_changed.connect(_update_display)
	if eb.has_signal("gold_changed"):
		eb.gold_changed.connect(_on_gold_changed)
	if eb.has_signal("message"):
		eb.message.connect(_on_message)
	if eb.has_signal("player_hit"):
		eb.player_hit.connect(_on_player_hit)
	if eb.has_signal("floor_changed"):
		eb.floor_changed.connect(_on_floor_changed)
	if eb.has_signal("room_entered"):
		eb.room_entered.connect(_on_room_entered)
	if eb.has_signal("boss_engaged"):
		eb.boss_engaged.connect(_on_boss_engaged)
	if eb.has_signal("boss_state_changed"):
		eb.boss_state_changed.connect(_on_boss_state_changed)
	if eb.has_signal("key_fragment_gained"):
		eb.key_fragment_gained.connect(_on_key_fragment_gained)
	if boss_bar:
		boss_bar.visible = false
	# 初始层数显示（含本层主题名与碎片进度）
	_refresh_floor_text()
	# 小地图初始刷新
	if minimap:
		minimap.notify_room_changed()


## Boss 出现：显示顶部血条栏
func _on_boss_engaged(boss_name: String, max_hp: float) -> void:
	if boss_bar == null:
		return
	_boss_entity = _find_boss_entity()
	_boss_max_hp = maxf(max_hp, 1.0)
	if boss_name_label:
		boss_name_label.text = boss_name
	boss_bar.visible = true
	_update_boss_bar()


## Boss 结束（死亡/房间清空）：隐藏血条栏
func _on_boss_state_changed(_cleared: bool) -> void:
	_boss_entity = null
	if boss_bar:
		boss_bar.visible = false


## 每帧刷新 Boss 血量（Boss 是场上唯一带 boss_loot 标记的敌人）
func _update_boss_bar() -> void:
	if boss_bar == null or not boss_bar.visible:
		return
	if _boss_entity == null or not is_instance_valid(_boss_entity):
		_boss_entity = _find_boss_entity()
		if _boss_entity == null:
			return
	var ratio: float = float(_boss_entity.call("hp_ratio")) if _boss_entity.has_method("hp_ratio") else 1.0
	if boss_bar_fill:
		boss_bar_fill.size.x = boss_bar_bg.size.x * clampf(ratio, 0.0, 1.0)


## 找当前 Boss 实体（带 boss_loot meta 的敌人）
func _find_boss_entity() -> Node:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_meta("boss_loot"):
			return e
	return null
func _on_room_entered(_room_id: String) -> void:
	if minimap:
		minimap.notify_room_changed()


func _update_display() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("stat_value"):
		return

	var attrs = gm.get("attributes")
	if attrs == null:
		return

	var max_hp: float = attrs.get("max_hp")
	var hp: float = attrs.get("hp")
	if health_orb:
		health_orb.max_value = max_hp
		health_orb.value = hp
	if health_label:
		health_label.text = "%d" % int(hp)

	# 职业资源球（怒气/魔力/专注/裁决/气劲）
	# 此前这里显示的是「连击伤害加成」——那是技能系统未实装时的临时占位
	# （见旧注释「原 MP 球」）。技能与资源已实装，改回真实数据。
	var p := _local_player()
	var res = p.get("class_resource") if p != null else null
	if mana_orb:
		if res != null:
			mana_orb.max_value = float(res.max_value())
			mana_orb.value = float(res.value)
		else:
			mana_orb.value = 0.0
	if mana_label:
		if res != null:
			mana_label.text = "%d" % int(res.value)
		else:
			mana_label.text = ""

	if gold_label:
		gold_label.text = "金币: %d" % gm.get("gold")


func _on_gold_changed(amount: int) -> void:
	if gold_label:
		gold_label.text = "金币: %d" % amount


func _on_message(text: String) -> void:
	if message_label:
		message_label.text = text
		var timer := get_tree().create_timer(2.5)
		timer.timeout.connect(func():
			if message_label:
				message_label.text = ""
		)


func _on_player_hit(_damage: float, _pos: Vector3) -> void:
	# 刷新血量：玩家受伤**不发** stats_changed，原先只闪血球不更新数值，
	# 导致血量看起来"没变化"，玩家以为没受伤
	_update_display()
	if health_orb:
		var tween := create_tween()
		tween.tween_property(health_orb, "modulate", Color.RED, 0.1)
		tween.tween_property(health_orb, "modulate", Color.WHITE, 0.2)


## 楼层变化回调
func _on_floor_changed(floor_num: int) -> void:
	set_floor(floor_num)


## 更新楼层显示。
## 楼层名由调用方传入；不传时按 FloorDefs 自动取（每层主题名不同）。
## 附带显示钥匙碎片进度（集齐 8 片解锁隐藏层）。
func set_floor(floor_num: int, floor_name: String = "") -> void:
	if floor_label == null:
		return
	var name_part := floor_name
	if name_part.is_empty():
		# FloorDefs 的 9 层主题名（监牢入口/废弃矿道/…）
		if floor_num >= 1 and floor_num <= FloorDefs.FLOORS.size():
			name_part = FloorDefs.theme_name(floor_num)
	var txt := "第 %d 层" % floor_num
	if not name_part.is_empty():
		txt += " · %s" % name_part
	var frag := _fragment_suffix()
	if not frag.is_empty():
		txt += "\n" + frag
	floor_label.text = txt


## 碎片进度后缀（"钥匙碎片 3/8"；一片都没有时不显示）
func _fragment_suffix() -> String:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null or not ("run_key_fragments" in gm):
		return ""
	var have: int = int(gm.run_key_fragments)
	if have <= 0:
		return ""
	var need: int = FloorDefs.KEY_FRAGMENTS_REQUIRED
	if have >= need:
		return "钥匙碎片 %d/%d（可进隐藏层）" % [have, need]
	return "钥匙碎片 %d/%d" % [have, need]


## 钥匙碎片获得回调：刷新显示 + 飘字提示
func _on_key_fragment_gained(total: int, _from_floor: int) -> void:
	_refresh_floor_text()
	var need: int = FloorDefs.KEY_FRAGMENTS_REQUIRED
	if total >= need:
		EventBus.message.emit("钥匙碎片集齐！击败本层 Boss 后可进入混沌裂隙")


## 重刷楼层文本（不改层数，只更新碎片后缀）
func _refresh_floor_text() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return
	set_floor(int(gm.run_info.get("floor", 1)))


## 技能冷却由 _update_skill_bar 每帧统一刷新（含剩余秒数与调暗）。
## 此处曾有一个 update_skill_cooldown(index, remaining, total) 接口，
## 全项目零调用者且只做 btn.disabled = remaining > 0，已被取代删除。