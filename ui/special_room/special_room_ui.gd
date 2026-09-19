extends CanvasLayer
class_name SpecialRoomUI
## 特殊房交互面板 —— 商店 / 泉水 / 事件房
##
## 一个场景按 kind 驱动三种布局（不拆三个场景）。
## 关键约定：**面板只负责展示与选择，所有业务校验（金币/容量/单次性）
## 都在 RoomController 与 SpecialRoomService 里**，面板不复制业务规则——
## 否则两边规则会漂移，且无法单测。
##
## 开关：open() 设 paused + 登记 modal_ui 组；close() 反之。
## modal_ui 组供 pause_menu 判断"是否有更高优先级面板"，避免 Esc 叠加打开。

const GROUP_MODAL := "modal_ui"
const GROUP_SELF := "special_room_ui"

const COLOR_BG := Color(0.035, 0.039, 0.043, 0.98)      # #090A0B
const COLOR_PANEL := Color(0.071, 0.078, 0.086, 0.8)    # #121416CC
const COLOR_TEXT := Color(0.914, 0.898, 0.863)          # #E9E5DC
const COLOR_DIM := Color(0.545, 0.545, 0.529)           # #8B8B87
const COLOR_GOLD := Color(0.71, 0.592, 0.384)           # #B59762 暗金
const COLOR_RUST := Color(0.608, 0.376, 0.271)          # #9B6045 铁锈
const COLOR_DANGER := Color(0.478, 0.161, 0.141)        # #7A2924

@onready var _title: Label = $Root/Center/Panel/VBox/Title
@onready var _body: Label = $Root/Center/Panel/VBox/Body
@onready var _choices: VBoxContainer = $Root/Center/Panel/VBox/Choices
@onready var _status: Label = $Root/Center/Panel/VBox/Status
@onready var _hint: Label = $Root/Center/Panel/VBox/Hint

var _controller = null          # RoomController
var _kind := ""                 # "shop" | "heal" | "event"
var _event_type := ""           # "memory_shard" | "gambler"
var _config: Dictionary = {}
var _choices_data: Array = []   # [{id, label}] 当前可选条目
var _selected := 0
var _used := false                # 控制器回报的"本房已结算"状态
var _gambler_started := false
var _gambler_resolved := false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	# 供 player 查找本面板（避免跨场景硬编码节点路径）
	if not is_in_group(GROUP_SELF):
		add_to_group(GROUP_SELF)
	# 金币变化时刷新状态行（控制器结算后会发这个信号）
	var bus = _event_bus()
	if bus and bus.has_signal("gold_changed"):
		bus.gold_changed.connect(func(_g): _refresh_status())


## 打开面板。ctx 来自 RoomController.get_special_context()
func open(ctx: Dictionary, controller) -> void:
	if not ctx.get("ok", false):
		return
	_controller = controller
	_kind = str(ctx.get("kind", ""))
	_event_type = str(ctx.get("event_type", ""))
	_config = ctx.get("config", {})
	_gambler_started = false
	_gambler_resolved = false
	_selected = 0

	_build_layout()
	refresh(ctx)
	add_to_group(GROUP_MODAL)
	visible = true
	get_tree().paused = true


## 关闭面板
func close() -> void:
	remove_from_group(GROUP_MODAL)
	visible = false
	get_tree().paused = false
	_controller = null
	_choices_data.clear()
	_gambler_started = false
	_gambler_resolved = false
	_used = false


## 是否有模态面板打开（供 pause_menu 判断）
static func is_modal_active() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	return not tree.get_nodes_in_group(GROUP_MODAL).is_empty()


## 按房间类型搭标题与文案
func _build_layout() -> void:
	match _kind:
		"shop":
			_title.text = "商 店"
			_body.text = str(_config.get("desc", "货架上摆着几件装备，也有些药水与门路可谈。"))
		"heal":
			_title.text = "泉 水"
			_body.text = str(_config.get("desc", "一泓清泉，饮下可恢复生命。"))
		"event":
			_title.text = "事 件"
			_body.text = str(_config.get("text", ""))
		_:
			_title.text = "?"
			_body.text = ""


## 根据控制器状态重建选项与状态行
func refresh(ctx: Dictionary = {}) -> void:
	if not ctx.is_empty():
		_config = ctx.get("config", _config)
		_used = bool(ctx.get("used", _used))
	_status.text = _status_line(ctx)
	_choices_data.clear()

	match _kind:
		"shop":
			_build_shop_choices()
		"heal":
			_build_heal_choices()
		"event":
			_build_event_choices()

	_render_choices()


func _build_shop_choices() -> void:
	var price := int(_config.get("price", 25))
	var heal := float(_config.get("heal", 80.0))
	_choices_data.append({
		"id": "buy_potion",
		"label": "购买生命药水（%d 金 · 恢复 %.0f 生命）" % [price, heal],
	})
	# —— 策划 总册 5.1「商店也出售装备」——
	# 装备摆在最前：玩家进商店的第一诉求是看货，其次才是消费模块。
	_build_shop_stock_choices()
	# —— 策划 总册 4.3.2 的消费模块「防溢出深坑」——
	var gm = _game_manager()
	if gm != null:
		# 属性灌注：无限购，价格随次数递增
		var icost: int = SpecialRoomService.infuse_cost(gm.infused_count)
		_choices_data.append({
			"id": "buy_infusion",
			"label": "属性灌注（%d 金 · 随机 +1~3 攻击 或 +3~8 生命，本局永久）" % icost,
		})
		# 融合折扣券
		if not gm.has_fusion_coupon:
			_choices_data.append({
				"id": "buy_coupon",
				"label": "融合折扣券（%d 金 · 下次融合费用减半）" % SpecialRoomService.FUSION_COUPON_PRICE,
			})
		# 商店升级券（三级）
		var up := SpecialRoomService.shop_upgrade(gm.shop_level)
		if up.get("ok", false):
			_choices_data.append({
				"id": "buy_upgrade",
				"label": "商店升级券（%d 金 · 升至 %d 级%s）" % [
					int(up.get("cost", 0)), int(up.get("level", 1)),
					"（解锁全店 9 折）" if int(up.get("level", 1)) >= SpecialRoomService.SHOP_MAX_LEVEL else ""],
			})
		# 装备附魔（策划 4.3.2：低级 800 / 中级 2,000 / 高级 5,000，单件限 3 次）
		# 与「属性灌注」的区别：灌注给玩家加固定属性；附魔把词条附加到装备上
		_choices_data.append({
			"id": "buy_enchant",
			"label": "装备附魔·中级（%d 金 · 随机附加一条词条到已穿戴装备，单件限 3 次）"
				% int(SpecialRoomService.ENCHANT_COSTS.get("mid", 2000)),
		})
		# 贷款：高风险博弈
		_choices_data.append({
			"id": "buy_loan",
			"label": "贷款（借 %d，通关结算时还 %d）" % [
				SpecialRoomService.LOAN_AMOUNT, SpecialRoomService.LOAN_REPAY],
		})
	_choices_data.append({"id": "leave", "label": "离开"})


## 商店装备货架（策划 总册 5.1）。已售出的条目仍列出但标「已售出」，
## 而不是整条抽掉——抽掉会让选项编号跳动，玩家刚看中的第 3 件
## 在买掉第 1 件后就变成了第 2 件，容易误购。
func _build_shop_stock_choices() -> void:
	if _controller == null or not _controller.has_method("get_shop_stock"):
		return
	var stock: Array = _controller.get_shop_stock()
	for i in range(stock.size()):
		var row: Dictionary = stock[i]
		var affix := str(row.get("affix_text", ""))
		var suffix := "" if affix.is_empty() else "（%s）" % affix
		if bool(row.get("sold", false)):
			_choices_data.append({
				"id": "buy_equip_%d" % i,
				"label": "%s · 已售出" % str(row.get("name", "")),
			})
			continue
		_choices_data.append({
			"id": "buy_equip_%d" % i,
			"label": "%s%s（%d 金）" % [
				str(row.get("name", "")), suffix, int(row.get("price", 0))],
		})


func _build_heal_choices() -> void:
	if _used:
		# 泉水每层限用一次；已用过就只给离开（控制器也会拒绝并给出原因）
		_choices_data.append({"id": "leave", "label": "这里已经用过了（离开）"})
		return
	_choices_data.append({"id": "heal", "label": "饮用泉水"})
	_choices_data.append({"id": "leave", "label": "离开"})


func _build_event_choices() -> void:
	var used: bool = _used
	match _event_type:
		"gambler":
			if used or _gambler_resolved:
				_choices_data.append({"id": "leave", "label": "赌局已结束（离开）"})
			elif not _gambler_started:
				_choices_data.append({
					"id": "start_gamble",
					"label": "付 %d 金，选一只箱子" % int(_config.get("cost", 100)),
				})
			else:
				for i in 3:
					_choices_data.append({"id": "box_%d" % i, "label": "第 %d 只箱子" % (i + 1)})
		"plague":
			# 瘟疫之泉：高风险高回报，文案要把代价说清楚
			if used:
				_choices_data.append({"id": "leave", "label": "泉水已饮尽（离开）"})
			else:
				_choices_data.append({"id": "drink_plague", "label": "饮下泉水（回满生命，但随机一项属性 -10%）"})
				_choices_data.append({"id": "leave", "label": "不喝，离开"})
		"forge":
			# 锻造炉：需要选一件背包装备
			if used:
				_choices_data.append({"id": "leave", "label": "锻造炉已冷却（离开）"})
			else:
				_append_bag_item_choices("forge_item_", "免费提升稀有度")
				_choices_data.append({"id": "leave", "label": "离开"})
		"altar":
			if used:
				_choices_data.append({"id": "leave", "label": "祭坛已沉寂（离开）"})
			else:
				_append_bag_item_choices("sacrifice_", "献祭换取更高稀有度")
				_choices_data.append({"id": "leave", "label": "离开"})
		"rift":
			if used:
				_choices_data.append({"id": "leave", "label": "裂隙已闭合（离开）"})
			else:
				_choices_data.append({"id": "enter_rift", "label": "踏入裂隙（传送至已探索房间，可再刷）"})
				_choices_data.append({"id": "leave", "label": "离开"})
		_:
			# 记忆碎片等自动事件：已领过则只剩离开
			if used:
				_choices_data.append({"id": "leave", "label": "记忆已取走（离开）"})
			else:
				_choices_data.append({"id": "claim", "label": "收下这段记忆"})
				_choices_data.append({"id": "leave", "label": "离开"})


## 把背包里的装备列成选项（锻造炉/祭坛要玩家指定一件）。
## prefix 是动作 id 前缀，后面接下标；物品名进 label 供玩家辨认。
func _append_bag_item_choices(prefix: String, verb: String) -> void:
	var gm = _game_manager()
	if gm == null or gm.equipment_manager == null:
		return
	var inv: Array = gm.equipment_manager.get_inventory()
	if inv.is_empty():
		_choices_data.append({"id": "leave", "label": "背包里没有装备"})
		return
	for i in inv.size():
		var inst = inv[i]
		var tpl = inst.get_template()
		var nm: String = tpl.display_name if tpl != null else "未知装备"
		_choices_data.append({
			"id": "%s%d" % [prefix, i],
			"label": "%s：%s（%s）" % [verb, nm, EquipmentDefs.rarity_name(inst.rarity)],
		})


## 绘制选项行（数字前缀；选中项用暗金高亮）
func _render_choices() -> void:
	for child in _choices.get_children():
		child.queue_free()
	for i in _choices_data.size():
		var row := Label.new()
		var idx := i + 1
		row.text = "  %d. %s" % [idx, _choices_data[i].get("label", "")]
		row.add_theme_color_override("font_color", COLOR_GOLD if i == _selected else COLOR_TEXT)
		row.add_theme_font_size_override("font_size", 20 if i == _selected else 18)
		_choices.add_child(row)
	_hint.text = "1-%d 选择 · Enter 确认 · Esc/E 关闭" % _choices_data.size()


## 状态行：金币与背包容量实时显示
func _status_line(ctx: Dictionary) -> String:
	var gm = _game_manager()
	if gm == null:
		return ""
	var gold := int(ctx.get("gold", gm.gold))
	var inv = gm.consumable_inventory
	var potions := int(ctx.get("potions", inv.count(inv.HEALTH_POTION_ID) if inv else 0))
	var capacity := int(ctx.get("capacity", inv.capacity if inv else 0))
	return "金币 %d　·　生命药水 %d/%d" % [gold, potions, capacity]


## 刷新状态行（金币变化时调用）
func _refresh_status() -> void:
	if not visible:
		return
	_status.text = _status_line({})


## 移动选择
func set_selected(index: int) -> void:
	if _choices_data.is_empty():
		return
	_selected = clampi(index, 0, _choices_data.size() - 1)
	_render_choices()


## 确认当前选择（Enter / 数字键 / 点击）
func confirm_selection() -> void:
	if _selected < 0 or _selected >= _choices_data.size():
		return
	_activate(str(_choices_data[_selected].get("id", "")))


## 购买货架上第 index 件装备（成功提示带名称与售价）
func _activate_equipment(index: int) -> void:
	var r: Dictionary = _controller.purchase_equipment(index)
	if r.get("ok", false):
		_notify(r, "购入 %s（%d 金）" % [str(r.get("name", "")), int(r.get("price", 0))])
	else:
		_notify(r, "")
	refresh(_controller.get_special_context())


## 按条目 id 执行（测试直接调这个，绕过输入层）
func _activate(id: String) -> void:
	if _controller == null:
		return
	# 装备货架条目带下标（buy_equip_0/1/2），match 只能精确匹配，
	# 故在进入 match 前先按前缀分流。
	if id.begins_with("buy_equip_"):
		_activate_equipment(int(id.trim_prefix("buy_equip_")))
		return
	match id:
		"leave":
			close()
			return
		"buy_potion":
			var r: Dictionary = _controller.purchase_health_potion()
			_notify(r, "购入生命药水")
			refresh(_controller.get_special_context())
		"buy_infusion":
			var r: Dictionary = _controller.purchase_infusion()
			if r.get("ok", false):
				var stat_name := "攻击力" if str(r.get("stat", "")) == "atk" else "生命值"
				_notify(r, "灌注成功：%s +%d" % [stat_name, int(r.get("amount", 0))])
			else:
				_notify(r, "")
			refresh(_controller.get_special_context())
		"buy_coupon":
			var r: Dictionary = _controller.purchase_fusion_coupon()
			_notify(r, "已获得融合折扣券")
			refresh(_controller.get_special_context())
		"buy_upgrade":
			var r: Dictionary = _controller.purchase_shop_upgrade()
			_notify(r, "商店升至 %d 级" % int(r.get("level", 0)))
			refresh(_controller.get_special_context())
		"buy_enchant":
			var r: Dictionary = _controller.purchase_enchant("mid")
			if r.get("ok", false):
				_notify(r, "%s → %s" % [str(r.get("item", "")), str(r.get("text", ""))])
			else:
				_notify(r, "")
			refresh(_controller.get_special_context())
		"buy_loan":
			var r: Dictionary = _controller.purchase_loan()
			_notify(r, "已到账 %d 金（欠款 %d）" % [
				int(r.get("amount", 0)), int(r.get("debt", 0))])
			refresh(_controller.get_special_context())
		"heal":
			var r: Dictionary = _controller.interact_special()
			_notify(r, "生命已恢复")
			refresh(_controller.get_special_context())
		"claim":
			var r: Dictionary = _controller.claim_memory_shard()
			_notify(r, "获得 %d 金币" % int(r.get("reward", 0)))
			refresh(_controller.get_special_context())
		"drink_plague":
			var r: Dictionary = _controller.interact_event()
			_notify(r, "生命已回满，但 %s 永久降低 10%%" % str(r.get("cursed_stat", "")))
			refresh(_controller.get_special_context())
		"enter_rift":
			# 传送后本房会切走，不必 refresh
			var r: Dictionary = _controller.interact_event()
			if not r.get("ok", false):
				_notify(r, "")
			close()
			return
		"start_gamble":
			var r: Dictionary = _controller.start_gambler_challenge()
			if r.get("ok", false):
				_gambler_started = true
			else:
				_notify(r, "")
			refresh(_controller.get_special_context())
		_:
			if id.begins_with("forge_item_"):
				# 锻造炉：把选中的背包装备提升 1 个稀有度
				var fi := int(id.substr("forge_item_".length()))
				var r: Dictionary = _controller.interact_event(fi)
				_notify(r, "装备已重铸为更高品质")
				refresh(_controller.get_special_context())
			elif id.begins_with("sacrifice_"):
				# 古代祭坛：献祭选中的装备换同部位更高稀有度
				var si := int(id.substr("sacrifice_".length()))
				var r: Dictionary = _controller.interact_event(si)
				_notify(r, "获得装备：%s" % str(r.get("item_name", "")))
				refresh(_controller.get_special_context())
			elif id.begins_with("box_"):
				var idx := int(id.substr(4))
				var r: Dictionary = _controller.resolve_gambler_choice(idx)
				if r.get("ok", false):
					_gambler_resolved = true
					_notify(r, _outcome_text(r))
				else:
					_notify(r, "")
				refresh(_controller.get_special_context())


## 把结算结果转成玩家可读文案
func _outcome_text(r: Dictionary) -> String:
	match str(r.get("outcome", "")):
		"gold":
			return "箱中是 %d 金币" % int(r.get("amount", 0))
		"equipment":
			return "获得装备：%s" % str(r.get("item_name", "一件装备"))
	return "箱子是空的"


## 反馈：成功走成功文案，失败走失败原因（HUD 会显示）
func _notify(result: Dictionary, ok_text: String) -> void:
	var bus = _event_bus()
	var ok: bool = result.get("ok", false)
	var text: String = ok_text if ok else str(result.get("reason", "无法交互"))
	if bus:
		bus.message.emit(text)


## 供测试断言的状态行
func status_text() -> String:
	return _status.text if _status else ""


## 供测试断言的当前选项 id 列表
func choice_ids() -> Array:
	var out: Array = []
	for c in _choices_data:
		out.append(str(c.get("id", "")))
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# 关闭：Esc 或 E
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()
		return

	# Enter 确认
	if event.is_action_pressed("ui_accept"):
		confirm_selection()
		get_viewport().set_input_as_handled()
		return

	# 数字键 1-9 直接选择并确认
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc >= KEY_1 and kc <= KEY_9:
			var idx := kc - KEY_1
			if idx < _choices_data.size():
				set_selected(idx)
				confirm_selection()
				get_viewport().set_input_as_handled()


func _game_manager():
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("GameManager")
	return null


func _event_bus():
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("EventBus")
	return null
