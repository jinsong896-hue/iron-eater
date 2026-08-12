extends Control
## HUD：属性面板、金币、背包、调试按钮、消息（原型阶段全部代码构建）

const RARITY_COLORS := {
	0: "#FFFFFF", 1: "#7BC96F", 2: "#5B8DEF", 3: "#B06CE8", 4: "#F09A3E", 5: "#E5484D",
}

var stats_label: Label
var gold_label: Label
var layer_label: Label
var inventory_label: RichTextLabel
var message_label: Label
var hp_bar: ProgressBar
var run_label: Label
var boss_hint: Label
var _next_btn: Button
var _run_time := 0.0


func _ready() -> void:
	_build_ui()
	EventBus.stats_changed.connect(_on_stats_changed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.message.connect(_on_message)
	EventBus.layer_changed.connect(_on_layer_changed)
	EventBus.player_hit.connect(func(_amount): _refresh_hp())
	EventBus.boss_state_changed.connect(_on_boss_state_changed)
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
	stats_label = Label.new()
	stats_label.position = Vector2(16, 16)
	stats_label.add_theme_font_size_override("font_size", 15)
	add_child(stats_label)

	layer_label = Label.new()
	layer_label.position = Vector2(16, 250)
	layer_label.add_theme_font_size_override("font_size", 18)
	layer_label.modulate = Color(1.0, 0.85, 0.5)
	add_child(layer_label)

	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(16, 220)
	hp_bar.size = Vector2(240, 20)
	hp_bar.show_percentage = false
	hp_bar.modulate = Color(1, 0.55, 0.5)
	add_child(hp_bar)

	run_label = Label.new()
	run_label.position = Vector2(16, 276)
	run_label.add_theme_font_size_override("font_size", 14)
	run_label.modulate = Color(0.85, 0.85, 0.9)
	add_child(run_label)

	gold_label = Label.new()
	gold_label.position = Vector2(16, 300)
	gold_label.add_theme_font_size_override("font_size", 18)
	add_child(gold_label)

	inventory_label = RichTextLabel.new()
	inventory_label.position = Vector2(16, 336)
	inventory_label.size = Vector2(480, 220)
	inventory_label.bbcode_enabled = true
	inventory_label.fit_content = true
	add_child(inventory_label)

	var btn_gold := Button.new()
	btn_gold.text = "+100 金币"
	btn_gold.position = Vector2(16, 520)
	btn_gold.pressed.connect(func(): GameState.give_gold(100))
	add_child(btn_gold)

	var btn_item := Button.new()
	btn_item.text = "生成装备"
	btn_item.position = Vector2(120, 520)
	btn_item.pressed.connect(func(): GameState.spawn_item())
	add_child(btn_item)

	var btn_reset := Button.new()
	btn_reset.text = "重置单局"
	btn_reset.position = Vector2(230, 520)
	btn_reset.pressed.connect(func(): GameState.reset_run())
	add_child(btn_reset)

	var btn_equipment := Button.new()
	btn_equipment.text = "装备管理"
	btn_equipment.position = Vector2(330, 520)
	btn_equipment.pressed.connect(_on_toggle_equipment_screen)
	add_child(btn_equipment)

	var btn_regenerate := Button.new()
	btn_regenerate.text = "重新生成本层 (R)"
	btn_regenerate.position = Vector2(600, 520)
	btn_regenerate.pressed.connect(func(): _dungeon_manager().regenerate())
	add_child(btn_regenerate)

	var btn_next := Button.new()
	btn_next.text = "下一层 (N)"
	btn_next.position = Vector2(790, 520)
	btn_next.pressed.connect(func(): _dungeon_manager().next_layer())
	add_child(btn_next)
	_next_btn = btn_next

	boss_hint = Label.new()
	boss_hint.position = Vector2(600, 560)
	boss_hint.add_theme_font_size_override("font_size", 13)
	boss_hint.modulate = Color(0.9, 0.75, 0.5)
	add_child(boss_hint)

	message_label = Label.new()
	message_label.position = Vector2(16, 560)
	message_label.size = Vector2(900, 100)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", 14)
	add_child(message_label)

	var hint := Label.new()
	hint.text = "WASD 移动 · 鼠标左键 / J 攻击 · 击杀木桩掉落装备 · 吞噬/融合提升属性"
	hint.position = Vector2(16, 680)
	hint.modulate = Color(0.7, 0.7, 0.7)
	add_child(hint)


func _on_stats_changed() -> void:
	var s := GameState.attributes
	stats_label.text = (
		"攻击 %.0f    防御 %.0f\n" % [s.get_value(AttributeSystem.Stat.ATK), s.get_value(AttributeSystem.Stat.DEF)]
		+ "移速 %.0f    攻速 %.2f    射程 %.1f\n" % [s.get_value(AttributeSystem.Stat.SPD), s.get_value(AttributeSystem.Stat.ASPD), s.get_value(AttributeSystem.Stat.RNG)]
		+ "法强 %.0f    法力 %d    冷却缩减 %.0f%%\n" % [s.get_value(AttributeSystem.Stat.AP), int(s.get_value(AttributeSystem.Stat.MP)), s.get_value(AttributeSystem.Stat.CDR) * 100.0]
		+ "暴击率 %.0f%%    暴击伤害 %.0f%%    击杀 %d    总伤害 %d"
		% [s.get_value(AttributeSystem.Stat.CRT) * 100.0, s.get_value(AttributeSystem.Stat.CRD) * 100.0, GameState.kills, int(GameState.total_damage)]
	)
	_refresh_hp()


func _refresh_hp() -> void:
	var s := GameState.attributes
	hp_bar.max_value = maxf(s.max_hp, 1.0)
	hp_bar.value = clampf(s.hp, 0.0, s.max_hp)


func _on_inventory_changed() -> void:
	var text := "【背包】\n"
	for i in GameState.equipment_manager.inventory.size():
		var item: EquipmentInstance = GameState.equipment_manager.inventory[i]
		var color: String = RARITY_COLORS.get(item.rarity, "#FFFFFF")
		var line := "[color=%s]%d. %s（%s）[/color] 融合 %d 次 [%s] 强化 +%d" % [
			color, i, item.display_name(), item.rarity_name(), item.fusion_count, item.fusion_tier(), item.enhancement_level]
		text += line + "\n"
	inventory_label.text = text


func _on_gold_changed() -> void:
	gold_label.text = "金币：%d" % GameState.gold


func _on_message(text: String) -> void:
	message_label.text = text


func _on_layer_changed(layer_id: int, layer_name: String) -> void:
	layer_label.text = "第 %d 层 · %s" % [layer_id, layer_name]
	_on_boss_state_changed(false)
	_refresh_run_label()


func _on_boss_state_changed(cleared: bool) -> void:
	if _next_btn:
		_next_btn.disabled = not cleared
	boss_hint.text = "" if cleared else "击败本层 Boss 后可进入下一层（第 9 层需击败 3 个 Boss）"


func _refresh_run_label() -> void:
	var cls := GameCatalog.class_info(str(GameState.run_info.get("character", "warrior")))
	var diff := GameCatalog.difficulty_info(str(GameState.run_info.get("difficulty", "normal")))
	run_label.text = "%s · %s　难度：%s　本局 %s" % [cls.name, cls.title, diff.name, _format_time(_run_time)]


func _on_run_timer() -> void:
	if get_tree().paused:
		return
	_run_time += 1.0
	_refresh_run_label()


func _format_time(sec: float) -> String:
	var m := int(sec) / 60
	var s := int(sec) % 60
	return "%d:%02d" % [m, s]


func _dungeon_manager() -> DungeonManager:
	return get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager


func _on_toggle_equipment_screen() -> void:
	var screen = get_tree().get_first_node_in_group("equipment_screen")
	if screen:
		screen.visible = not screen.visible
		screen.refresh_all()
