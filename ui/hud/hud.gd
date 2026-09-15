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


## 每帧刷新连击数（轮询玩家，简单可靠）
func _process(_delta: float) -> void:
	_update_boss_bar()
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


## 更新技能冷却
func update_skill_cooldown(index: int, remaining: float, total: float) -> void:
	if index < 0 or index >= skill_buttons.size():
		return
	var btn := skill_buttons[index]
	# TODO: 实现冷却遮罩效果
	btn.disabled = remaining > 0.0