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
@onready var minimap: Control = $Minimap

var skill_buttons: Array[Button] = []
var item_buttons: Array[Button] = []


func _ready() -> void:
	_collect_skill_buttons()
	_collect_item_buttons()
	_connect_signals()
	_update_display()
	set_process(true)


## 每帧刷新连击数（轮询玩家，简单可靠）
func _process(_delta: float) -> void:
	if combo_label == null:
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p = players[0]
	if p and p.has_method("get_hit_combo"):
		var count: int = p.get_hit_combo()
		combo_label.text = "连击 x%d" % count if count >= 2 else ""


func _collect_skill_buttons() -> void:
	var skill_bar := $BottomBar/SkillBar
	for child in skill_bar.get_children():
		if child is Button:
			skill_buttons.append(child as Button)


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
	# 初始层数显示
	var gm0 := get_node_or_null("/root/GameManager")
	if gm0 and floor_label:
		floor_label.text = "第 %d 层" % int(gm0.run_info.get("floor", 1))


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

	# 连击伤害加成（原 MP 球——技能系统未实装前展示真实数据）
	var combo_bonus := _combo_damage_bonus()
	if mana_orb:
		mana_orb.max_value = GameBalance.COMBO_DAMAGE_CAP * 100.0
		mana_orb.value = combo_bonus * 100.0
	if mana_label:
		mana_label.text = "+%d%%" % int(combo_bonus * 100.0)

	if gold_label:
		gold_label.text = "金币: %d" % gm.get("gold")


## 当前连击伤害加成（从玩家读连击数）
func _combo_damage_bonus() -> float:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return 0.0
	var p = players[0]
	if p and p.has_method("get_hit_combo"):
		var count: int = p.get_hit_combo()
		return minf(
			count * GameBalance.COMBO_DAMAGE_PER_HIT,
			GameBalance.COMBO_DAMAGE_CAP
		)
	return 0.0


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
	if health_orb:
		var tween := create_tween()
		tween.tween_property(health_orb, "modulate", Color.RED, 0.1)
		tween.tween_property(health_orb, "modulate", Color.WHITE, 0.2)


## 楼层变化回调
func _on_floor_changed(floor_num: int) -> void:
	set_floor(floor_num)


## 更新楼层显示
func set_floor(floor_num: int, floor_name: String = "") -> void:
	if floor_label:
		if floor_name.is_empty():
			floor_label.text = "第 %d 层" % floor_num
		else:
			floor_label.text = "第 %d 层 · %s" % [floor_num, floor_name]


## 更新技能冷却
func update_skill_cooldown(index: int, remaining: float, total: float) -> void:
	if index < 0 or index >= skill_buttons.size():
		return
	var btn := skill_buttons[index]
	# TODO: 实现冷却遮罩效果
	btn.disabled = remaining > 0.0