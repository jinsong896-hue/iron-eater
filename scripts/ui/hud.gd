extends CanvasLayer
## HUD（暗黑风底栏版）：底部战斗栏（红蓝资源球 + 6 技能槽 + 状态行）、顶部属性/调试面板、
## Boss 血条 API、伤害飘字、消息提示。全部代码构建，无外部场景依赖。
## 数值来源：GameBalance（ai/demo1 冻结数值）。
## 挂在 CanvasLayer 下，保证 UI 固定于屏幕、不随 Camera2D 漂移。

const BAR_COLOR := Color(0.07, 0.07, 0.10)
const PANEL_COLOR := Color(0.09, 0.09, 0.12, 0.94)

var _stats_label: Label
var _gold_label: Label
var _inventory_label: RichTextLabel
var _boss_hint: Label
var _message_label: Label
var _hp_orb: StatOrb
var _mp_orb: StatOrb
var _skill_slots: Array = []
var _run_time := 0.0
var _mp := 100.0
var _status_line: Label
var _run_label: Label
var _next_btn: Button
var _demo_boss_btn: Button

# Boss 血条（顶部居中）
var _boss_bar: PanelContainer
var _boss_name: Label
var _boss_hp: ProgressBar
var _boss_phase: Label
var _demo_boss_hp := 1500.0
var _demo_boss_phase := 1
var _demo_boss_active := false
var _demo_boss_timer := 0.0


func _ready() -> void:
	_build_ui()
	EventBus.stats_changed.connect(_on_stats_changed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.message.connect(_on_message)
	EventBus.layer_changed.connect(_on_layer_changed)
	EventBus.player_hit.connect(func(_amount): _refresh_orbs())
	EventBus.boss_state_changed.connect(_on_boss_state_changed)
	EventBus.damage_popup.connect(_on_damage_popup)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_on_run_timer)
	add_child(timer)
	timer.start()
	_on_stats_changed()
	_on_inventory_changed()
	_on_gold_changed()
	var mgr := _dungeon_manager()
	if mgr != null:
		var cfg: ChapterConfig = mgr.LAYER_CONFIGS[mgr.current_layer - 1]
		_on_layer_changed(mgr.current_layer, cfg.chapter_name)


func _build_ui() -> void:
	_build_bottom_bar()
	_build_top_panel()
	_build_boss_bar()
	_build_message_label()


# ---------------------------------------------------------------------------
# 底部战斗栏
# ---------------------------------------------------------------------------

func _build_bottom_bar() -> void:
	var bar := Panel.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -128.0
	bar.add_theme_stylebox_override("panel", _panel_style(BAR_COLOR, 2.0, 0.4))
	add_child(bar)

	# 红蓝资源球
	_hp_orb = StatOrb.new()
	_hp_orb.orb_color = Color(0.78, 0.16, 0.18)
	_hp_orb.orb_title = "生命"
	_hp_orb.position = Vector2(16, 16)
	_hp_orb.size = Vector2(96, 96)
	bar.add_child(_hp_orb)

	_mp_orb = StatOrb.new()
	_mp_orb.orb_color = Color(0.20, 0.42, 0.85)
	_mp_orb.orb_title = "法力"
	_mp_orb.position = Vector2(120, 16)
	_mp_orb.size = Vector2(96, 96)
	bar.add_child(_mp_orb)

	# 6 技能槽（Q/F/G 为演示技能，T/Y/H 为未解锁占位；E 保留给吞噬掉落物）
	var slot_size := 48.0
	var gap := 6.0
	var total := 6 * slot_size + 5 * gap
	var start_x := (get_viewport().get_visible_rect().size.x - total) * 0.5
	for i in 6:
		var slot := SkillSlot.new()
		slot.position = Vector2(start_x + i * (slot_size + gap), 24)
		slot.size = Vector2(slot_size, slot_size)
		if i < GameBalance.DEMO_SKILLS.size():
			var data: Dictionary = GameBalance.DEMO_SKILLS[i]
			slot.setup(data)
			slot.pressed.connect(_on_skill_pressed.bind(i))
		else:
			slot.setup({"name": "未解锁", "key": ["T", "Y", "H"][i - 3], "element": "", "cooldown": 0.0, "desc": "技能尚未开放"})
			slot.disabled = true
			slot.modulate = Color(1, 1, 1, 0.4)
		bar.add_child(slot)
		_skill_slots.append(slot)

	# 状态行（快捷键提示 / 当前房）
	_status_line = Label.new()
	_status_line.position = Vector2(start_x, 80)
	_status_line.size = Vector2(total, 22)
	_status_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_line.add_theme_font_size_override("font_size", 12)
	_status_line.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	_status_line.text = "左键普攻 · Q 火焰斩 · E 吞噬 · Tab 背包 · Esc 暂停"
	bar.add_child(_status_line)


# ---------------------------------------------------------------------------
# 顶部属性 / 调试面板
# ---------------------------------------------------------------------------

func _build_top_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL_COLOR, 2.0, 0.5))
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "状态"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	vbox.add_child(title)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_stats_label)

	_run_label = Label.new()
	_run_label.add_theme_font_size_override("font_size", 12)
	_run_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.84))
	vbox.add_child(_run_label)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 15)
	_gold_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	vbox.add_child(_gold_label)

	_boss_hint = Label.new()
	_boss_hint.add_theme_font_size_override("font_size", 11)
	_boss_hint.add_theme_color_override("font_color", Color(0.85, 0.7, 0.5))
	_boss_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_boss_hint.custom_minimum_size = Vector2(260, 0)
	vbox.add_child(_boss_hint)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 调试按钮（两行）
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	vbox.add_child(row1)
	row1.add_child(_make_btn("+100金币", func(): GameState.give_gold(100)))
	row1.add_child(_make_btn("生成装备", func(): GameState.spawn_item()))

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	vbox.add_child(row2)
	row2.add_child(_make_btn("重置单局", func(): GameState.reset_run()))
	row2.add_child(_make_btn("装备管理", _on_toggle_equipment_screen))

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 4)
	vbox.add_child(row3)
	row3.add_child(_make_btn("重生成(R)", func(): _dungeon_manager().regenerate()))
	_next_btn = _make_btn("下一层(N)", func(): _dungeon_manager().next_layer())
	row3.add_child(_next_btn)

	_demo_boss_btn = _make_btn("Boss血条演示", _toggle_demo_boss)
	row3.add_child(_demo_boss_btn)

	_inventory_label = RichTextLabel.new()
	_inventory_label.bbcode_enabled = true
	_inventory_label.fit_content = true
	_inventory_label.custom_minimum_size = Vector2(280, 120)
	_inventory_label.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(_inventory_label)


func _make_btn(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(handler)
	return b


func _panel_style(color: Color, radius: int, alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_color = Color(0.35, 0.35, 0.40, alpha)
	sb.set_border_width_all(1)
	return sb


# ---------------------------------------------------------------------------
# Boss 血条（顶部居中）
# ---------------------------------------------------------------------------

func _build_boss_bar() -> void:
	_boss_bar = PanelContainer.new()
	_boss_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_bar.position = Vector2(-280, 16)
	_boss_bar.custom_minimum_size = Vector2(560, 0)
	_boss_bar.add_theme_stylebox_override("panel", _panel_style(PANEL_COLOR, 3, 0.7))
	_boss_bar.visible = false
	add_child(_boss_bar)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_boss_bar.add_child(vbox)

	_boss_name = Label.new()
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_font_size_override("font_size", 15)
	_boss_name.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	vbox.add_child(_boss_name)

	_boss_hp = ProgressBar.new()
	_boss_hp.show_percentage = false
	_boss_hp.custom_minimum_size = Vector2(540, 14)
	_boss_hp.add_theme_stylebox_override("fill", _panel_style(Color(0.78, 0.22, 0.22), 2, 1.0))
	vbox.add_child(_boss_hp)

	_boss_phase = Label.new()
	_boss_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_phase.add_theme_font_size_override("font_size", 12)
	_boss_phase.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(_boss_phase)


func _build_message_label() -> void:
	_message_label = Label.new()
	_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_label.position = Vector2(-450, 96)
	_message_label.custom_minimum_size = Vector2(900, 30)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 14)
	_message_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_message_label.add_theme_constant_override("outline_size", 4)
	add_child(_message_label)


# ---------------------------------------------------------------------------
# 信号回调
# ---------------------------------------------------------------------------

func _on_stats_changed() -> void:
	var s := GameState.attributes
	_stats_label.text = (
		"攻击 %.0f　防御 %.0f\n" % [s.get_value(AttributeSystem.Stat.ATK), s.get_value(AttributeSystem.Stat.DEF)]
		+ "移速 %.0f　攻速 %.2f\n" % [s.get_value(AttributeSystem.Stat.SPD), s.get_value(AttributeSystem.Stat.ASPD)]
		+ "法强 %.0f　暴击 %.0f%%\n" % [s.get_value(AttributeSystem.Stat.AP), s.get_value(AttributeSystem.Stat.CRT) * 100.0]
		+ "击杀 %d　吞噬 %d" % [GameState.kills, GameState.devoured_count]
	)
	_refresh_orbs()


func _refresh_orbs() -> void:
	var s := GameState.attributes
	if _hp_orb:
		_hp_orb.set_stats(s.hp, s.max_hp)
	if _mp_orb:
		var max_mp := maxf(s.get_value(AttributeSystem.Stat.MP), 1.0)
		_mp = clampf(_mp, 0.0, max_mp)
		_mp_orb.set_stats(_mp, max_mp)


func _on_inventory_changed() -> void:
	var text := "【背包】\n"
	for i in GameState.equipment_manager.inventory.size():
		var item: EquipmentInstance = GameState.equipment_manager.inventory[i]
		var color: String = EquipmentDefs.rarity_hex(item.rarity)
		text += "[color=%s]%d. %s（%s）[/color] 融%d [%s] +%d\n" % [
			color, i, item.display_name(), item.rarity_name(), item.fusion_count, item.fusion_tier(), item.enhancement_level]
	_inventory_label.text = text


func _on_gold_changed() -> void:
	_gold_label.text = "金币：%d" % GameState.gold


func _on_message(text: String) -> void:
	_message_label.text = text


func _on_layer_changed(layer_id: int, layer_name: String) -> void:
	_on_boss_state_changed(false)
	_refresh_status_line(layer_id, layer_name)
	_refresh_run_label()


func _on_boss_state_changed(cleared: bool) -> void:
	if _next_btn:
		_next_btn.disabled = not cleared
	_boss_hint.text = "" if cleared else "击败本层 Boss 后可进入下一层（第 9 层需击败 3 个 Boss）"


func _refresh_status_line(layer_id: int, layer_name: String) -> void:
	if _status_line:
		_status_line.text = "第 %d 层 · %s　|　左键普攻 · Q 火焰斩 · E 吞噬 · Tab 背包" % [layer_id, layer_name]


func _refresh_run_label() -> void:
	if _run_label == null:
		return
	var cls := GameCatalog.class_info(str(GameState.run_info.get("character", "warrior")))
	var diff := GameCatalog.difficulty_info(str(GameState.run_info.get("difficulty", "normal")))
	_run_label.text = "%s · %s　难度：%s　本局 %s" % [cls.name, cls.title, diff.name, _format_time(_run_time)]


func _format_time(sec: float) -> String:
	var m := int(sec) / 60
	var s := int(sec) % 60
	return "%d:%02d" % [m, s]


func _on_run_timer() -> void:
	if get_tree().paused:
		return
	_run_time += 1.0
	_refresh_run_label()
	_update_demo_boss(1.0)


func _update_demo_boss(delta: float) -> void:
	if not _demo_boss_active:
		return
	_demo_boss_timer += delta
	if _demo_boss_timer >= 0.3:
		_demo_boss_timer = 0.0
		_demo_boss_hp = maxf(_demo_boss_hp - 35.0, 0.0)
		if _demo_boss_hp <= 0.0:
			_demo_boss_active = false
			hide_boss_bar()
			EventBus.message.emit("（演示）狱卒·卡恩 已被击败")
			return
		if _demo_boss_hp <= float(GameBalance.BOSS.hp) * 0.5 and _demo_boss_phase == 1:
			_demo_boss_phase = 2
			EventBus.message.emit("（演示）狱卒·卡恩 进入阶段 2！")
		update_boss_bar(_demo_boss_hp, _demo_boss_phase)


func _on_damage_popup(world_pos: Vector2, amount: float, kind: String) -> void:
	if not SettingsManager.get_value("game", "damage_numbers", true):
		return
	var popup := DamagePopup.new()
	add_child(popup)
	popup.setup(world_pos, amount, kind)


# ---------------------------------------------------------------------------
# 技能（演示）：无真实战斗效果，只走冷却 + 消息反馈；后续接入技能系统即可
# ---------------------------------------------------------------------------

func _on_skill_pressed(index: int) -> void:
	var slot := _skill_slots[index] as SkillSlot
	var data: Dictionary = GameBalance.DEMO_SKILLS[index]
	if slot.cooldown > 0.0:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not player.has_method("cast_skill"):
		return
	var result: Dictionary = player.cast_skill(str(data.get("id", "")))
	if result.get("ok", false):
		slot.start_cooldown(float(data.get("cooldown", 1.0)))


# ---------------------------------------------------------------------------
# Boss 血条 API + 演示
# ---------------------------------------------------------------------------

func show_boss_bar(boss_name: String, hp: float, max_hp: float, phase: int) -> void:
	_boss_name.text = boss_name
	_boss_hp.max_value = maxf(max_hp, 1.0)
	_boss_hp.value = clampf(hp, 0.0, max_hp)
	_boss_phase.text = "阶段 %d" % phase
	_boss_bar.visible = true


func update_boss_bar(hp: float, phase: int) -> void:
	_boss_hp.value = clampf(hp, 0.0, _boss_hp.max_value)
	_boss_phase.text = "阶段 %d" % phase


func hide_boss_bar() -> void:
	_boss_bar.visible = false


func _toggle_demo_boss() -> void:
	if _boss_bar.visible:
		hide_boss_bar()
		_demo_boss_active = false
		return
	_demo_boss_hp = float(GameBalance.BOSS.hp)
	_demo_boss_phase = 1
	_demo_boss_timer = 0.0
	_demo_boss_active = true
	show_boss_bar(GameBalance.BOSS.name, _demo_boss_hp, float(GameBalance.BOSS.hp), _demo_boss_phase)
	EventBus.message.emit("Boss 血条演示：自动掉血，半血进入阶段 2")


# ---------------------------------------------------------------------------
# 输入 / 工具
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# 演示技能快捷键 Q / F / G（E 保留给吞噬掉落物，见 player.gd）
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := -1
		match event.physical_keycode:
			KEY_Q: idx = 0
			KEY_F: idx = 1
			KEY_G: idx = 2
		if idx >= 0 and idx < GameBalance.DEMO_SKILLS.size():
			_on_skill_pressed(idx)
			get_viewport().set_input_as_handled()


func _dungeon_manager() -> DungeonManager:
	return get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager


func _on_toggle_equipment_screen() -> void:
	var screen = get_tree().get_first_node_in_group("equipment_screen")
	if screen:
		screen.visible = not screen.visible
		screen.refresh_all()
