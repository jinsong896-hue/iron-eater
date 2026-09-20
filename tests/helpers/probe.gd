class_name TestProbe
extends RefCounted
## 测试访问集中层 —— **唯一允许触碰下划线私有成员的地方**。
##
## ## 为什么要有这个文件
##
## 重构前，23 套测试里有 **107 处** 直呼私有成员（`p._hitstop()`、
## `ui._selected`、`gr._transition_to_room()`…）。这等于把**实现细节钉死**：
## 每次搬动一个私有函数（哪怕行为一字不改），都要满世界改测试，
## 于是"重构"变成"重写测试"，而重写过的测试**失去了保护作用**
## （新写的断言是照着新实现写的，测不出行为漂移）。
##
## 收口后，重构搬走 `Player._hitstop` 时**只改本文件一行**，
## 测试语义零变化、断言一字不改。
##
## ## 用法
##
## ```gdscript
## var probe := TestProbe.new()
## probe.hitstop(player, 0.05)        # 代替 player._hitstop(0.05)
## var n: int = probe.hit_combo_count(player)
## ```
##
## ## 约定
##
## · 取字段走 `get()`，调方法走 `call()` —— 这样重构搬走成员时
##   本文件是**唯一**需要跟着改的地方。
## · **新增私有访问前先问**：能不能用公开 API 表达？能就别加到这里。
## · `assert_coverage()` 会核对本文件登记的名字在当前代码里真实存在，
##   重构搬空一个方法而忘了更新 probe 时，测试会**指名道姓地红**。

# ============================================================
# 通用取用（宿主类型无关）
# ============================================================

## 读任意私有字段（等价于 `obj._name`）
func field(obj: Object, name: String):
	return obj.get(name)


## 写任意私有字段（等价于 `obj._name = v`）
func set_field(obj: Object, name: String, value) -> void:
	obj.set(name, value)


## 调任意私有方法（等价于 `obj._name(...)`）
func invoke(obj: Object, name: String, args: Array = []):
	return obj.callv(name, args)


## 某私有成员是否存在于对象上（方法或属性）
func has(obj: Object, name: String) -> bool:
	if obj.has_method(name):
		return true
	return name in obj


# ============================================================
# Player —— 36 个（重构阶段 C1 的主要迁移对象）
# ============================================================

## 触发一次顿帧（hitstop）
func hitstop(p: Node, duration: float) -> void:
	p.call("_hitstop", duration)

## 当前是否处于冲刺（奔跑）态
func is_sprinting(p: Node) -> bool:
	return bool(p.get("_is_sprinting"))

## 置冲刺态
func set_sprinting(p: Node, on: bool) -> void:
	p.set("_is_sprinting", on)

## 当前是否处于翻滚态
func is_dodging(p: Node) -> bool:
	return bool(p.get("_is_dodging"))

## 攻击冷却计时器
func attack_timer(p: Node) -> float:
	return float(p.get("_attack_timer"))

## 置攻击冷却计时器
func set_attack_timer(p: Node, v: float) -> void:
	p.set("_attack_timer", v)

## 本次攻击的总冷却（取消窗口按比例算）
func current_attack_cooldown(p: Node) -> float:
	return float(p.get("_current_attack_cooldown"))

## 置本次攻击的总冷却
func set_current_attack_cooldown(p: Node, v: float) -> void:
	p.set("_current_attack_cooldown", v)

## 冲刺攻击计时器
func sprint_attack_timer(p: Node) -> float:
	return float(p.get("_sprint_attack_timer"))

## 是否处于可取消窗口内
func in_cancel_window(p: Node) -> bool:
	return bool(p.call("_in_cancel_window"))

## 取消当前攻击
func cancel_current_attack(p: Node) -> void:
	p.call("_cancel_current_attack")

## 起手一次普攻
func start_normal_attack(p: Node) -> void:
	p.call("_start_normal_attack")

## 终结技霸体剩余时间
func finisher_armor_timer(p: Node) -> float:
	return float(p.get("_finisher_armor_timer"))

## 当前朝向
func facing(p: Node) -> Vector3:
	return p.get("_facing")

## 连击计数
func hit_combo_count(p: Node) -> int:
	return int(p.get("_hit_combo_count"))

## 连击剩余时间
func hit_combo_time(p: Node) -> float:
	return float(p.get("_hit_combo_time"))

## 登记一次命中连击
func register_hit_combo(p: Node) -> void:
	p.call("_register_hit_combo")

## 连击回血结算
func apply_combo_heal(p: Node) -> void:
	p.call("_apply_combo_heal")

## 对单个敌人结算伤害与击退（普攻的唯一漏斗）
func apply_hit(p: Node, enemy: Node3D, multiplier: float, knockback: float) -> void:
	p.call("_apply_hit", enemy, multiplier, knockback)

## 普攻穿透值
func basic_attack_pierce(p: Node) -> float:
	return float(p.call("_basic_attack_pierce"))

## 拳师徒手额外触及
func fist_reach_bonus(p: Node) -> float:
	return float(p.call("_fist_reach_bonus"))

## 是否背刺（目标背对玩家）
func is_backstab(p: Node, enemy: Node3D) -> bool:
	return bool(p.call("_is_backstab", enemy))

## 执行一次近战攻击（含扇形判定）
func perform_melee_attack(p: Node, mult: float, reach: float,
		half_angle: float, knockback: float) -> void:
	p.call("_perform_melee_attack", mult, reach, half_angle, knockback)

## 玩家受击钩子（词条/护盾/连击打断）
func on_player_hurt(p: Node, amount: float) -> void:
	p.call("_on_player_hurt", amount)

## 普攻命中回调（连击、吸血、附魔等触发点）
func on_basic_attack_landed(p: Node, enemy: Node3D, damage: float) -> void:
	p.call("_on_basic_attack_landed", enemy, damage)

## 吸血结算
func lifesteal_heal(p: Node, amount: float) -> void:
	p.call("_lifesteal_heal", amount)

## 伤害反射（反伤词条）
func reflect_damage(p: Node, attacker: Node3D, amount: float) -> void:
	p.call("_reflect_damage", attacker, amount)

## 连锁法术伤害（雷系）
func chain_spell_damage(p: Node, origin: Node3D, amount: float) -> void:
	p.call("_chain_spell_damage", origin, amount)

## 光暗层数平衡刷新（增益/减益分界）
func refresh_light_dark_balance(p: Node) -> void:
	p.call("_refresh_light_dark_balance")

## 获得一层「光」
func gain_light_layer(p: Node) -> void:
	p.call("_gain_light_layer")

## 破限（阈值触发）检查
func maybe_trigger_break_limit(p: Node) -> void:
	p.call("_maybe_trigger_break_limit")

## 生成森林领域（形态机制）
func spawn_forest_domain(p: Node) -> void:
	p.call("_spawn_forest_domain")

## 生成挥砍视觉（扇形）
func spawn_slash_visual(p: Node, reach: float, half_angle: float) -> void:
	p.call("_spawn_slash_visual", reach, half_angle)

## 跳跃阶段
func jump_phase(p: Node) -> int:
	return int(p.get("_jump_phase"))

## 状态机实例（**StateMachine 是 RefCounted，不是 Node**）
##
## 返回类型必须写宽：写成 `Node` 时 Godot 对 RefCounted 返回值**静默返回 null**，
## 调用方随即报 "Nonexistent function in base 'Nil'"。
func state_machine(p: Node):
	return p.get("_state_machine")

## 模型节点
func model(p: Node) -> Node:
	return p.get("_model")

## 受击闪红剩余时间
func flash_timer(p: Node) -> float:
	return float(p.get("_flash_timer"))

## 拾取最近掉落物（E 键路径）
func pickup_nearby(p: Node) -> void:
	p.call("_pickup_nearby")


# ============================================================
# EnemyBase —— 7 个
# ============================================================

## 血量
func enemy_hp(e: Node) -> float:
	return float(e.get("_hp"))

## 置血量
func set_enemy_hp(e: Node, v: float) -> void:
	e.set("_hp", v)

## 受击闪红剩余时间
func enemy_flash_timer(e: Node) -> float:
	return float(e.get("_flash_timer"))

## 血条节点
func hp_bar(e: Node) -> Node:
	return e.get("_hp_bar")

## 血条背景 quad
func hp_bar_bg(e: Node) -> Node:
	return e.get("_hp_bar_bg")

## 血条填充 quad
func hp_bar_fill(e: Node) -> Node:
	return e.get("_hp_bar_fill")

## 装配单个词缀
func apply_affix(e: Node, id: String) -> void:
	e.call("_apply_affix", id)


# ============================================================
# RoomController —— 6 个
# ============================================================

## 房间的门节点列表
func ctrl_doors(ctrl: Node) -> Array:
	return ctrl.get("_doors")

## 本房是否为特殊房
func ctrl_is_special_room(ctrl: Node) -> bool:
	return bool(ctrl.get("_is_special_room"))

## 触发「房间已清空」流程
func ctrl_on_cleared(ctrl: Node) -> void:
	ctrl.call("_on_cleared")

## 刷怪点列表
func ctrl_spawn_points(ctrl: Node) -> Array:
	return ctrl.get("_spawn_points")

## 特殊房服务实例
func ctrl_special_service(ctrl: Node) -> Node:
	return ctrl.get("_special_service")

## 特殊房是否已使用（局内）
func ctrl_special_used(ctrl: Node) -> bool:
	return bool(ctrl.get("_special_used"))

## 特殊房是否已使用（从 room_state 读回）
func ctrl_special_was_used(ctrl: Node) -> bool:
	return bool(ctrl.call("_special_was_used"))

## 群体管理器
func ctrl_crowd(ctrl: Node) -> Node:
	return ctrl.call("_crowd")

## 是否应走群体路径
func ctrl_should_use_crowd(ctrl: Node, m: Dictionary, is_elite_room: bool) -> bool:
	return bool(ctrl.call("_should_use_crowd", m, is_elite_room))

## 在指定刷怪点生成一个群体单位
func ctrl_spawn_crowd_at(ctrl: Node, point: Node, m: Dictionary, diff: float) -> bool:
	return bool(ctrl.call("_spawn_crowd_at", point, m, diff))

## 在指定刷怪点生成一个节点式敌人
func ctrl_spawn_enemy_at(ctrl: Node, point: Node, diff: float, m: Dictionary = {}) -> Node:
	return ctrl.call("_spawn_enemy_at", point, diff, m)


# ============================================================
# GameRoot —— 8 个
# ============================================================

## 方向名 → 单位向量
func gr_dir_vector(gr: Node, dir: String) -> Vector3:
	return gr.call("_dir_vector", dir)

## 反向方向名
func gr_opposite_dir(gr: Node, dir: String) -> String:
	return str(gr.call("_opposite_dir", dir))

## 找指定方向的邻接房索引（-1 = 无）
func gr_find_room_in_direction(gr: Node, dir: String) -> int:
	return int(gr.call("_find_room_in_direction", dir))

## 门触发回调（穿门）
func gr_on_door_entered(gr: Node, dir: String, door_id: String) -> void:
	gr.call("_on_door_entered", dir, door_id)

## 切到指定房间
func gr_transition_to_room(gr: Node, idx: int, enter_dir: String = "") -> void:
	gr.call("_transition_to_room", idx, enter_dir)

## 房间缓存
func gr_room_cache(gr: Node) -> Dictionary:
	return gr.get("_room_cache")

## 当前层号
func gr_current_floor(gr: Node) -> int:
	return int(gr.call("_current_floor_num"))


# ============================================================
# LootSystem —— 6 个
# ============================================================

## 掷稀有度
func loot_roll_rarity(loot: Node, floor_num: int) -> int:
	return int(loot.call("_roll_rarity", floor_num))

## 掷装备模板
func loot_roll_template(loot: Node, rarity: int, floor_num: int) -> Dictionary:
	return loot.call("_roll_template", rarity, floor_num)

## 是否 Boss 掉落
func loot_is_boss(loot: Node, source_kind: String) -> bool:
	return bool(loot.call("_is_boss", source_kind))

## 是否精英掉落
func loot_is_elite(loot: Node, source_kind: String) -> bool:
	return bool(loot.call("_is_elite", source_kind))

## Boss 保底稀有度
func loot_boss_pity_rarity(loot: Node) -> int:
	return int(loot.get("_boss_pity_rarity"))

## 层数衰减概率
func loot_floor_decayed_chance(loot: Node) -> float:
	return float(loot.get("_floor_decayed_chance"))


# ============================================================
# 其余宿主 —— 逐个对应
# ============================================================

## 属性系统的修饰符表
func attrs_modifiers(attrs: Node) -> Array:
	return attrs.get("_modifiers")

## 投射物引信是否已武装
func bomb_fuse_armed(bomb: Node) -> bool:
	return bool(bomb.get("_fuse_armed"))

## 投射物所属阵营
func owner_faction(obj: Node) -> String:
	return str(obj.get("_owner_faction"))

## 投射物生成落地区域
func projectile_spawn_land_zone(p: Node) -> void:
	p.call("_spawn_land_zone")

## 投射物分裂
func projectile_spawn_split(p: Node) -> void:
	p.call("_spawn_split")

## 门触发器受击回调
func door_trigger_body_entered(trig: Node, body: Node3D) -> void:
	trig.call("_on_body_entered", body)

## 门触发器是否已置位
func door_trigger_triggered(trig: Node) -> bool:
	return bool(trig.get("_triggered"))

## 装备管理器的背包
func em_inventory(em: Node) -> Array:
	return em.get("_inventory")

## 局内统计重置
func gm_reset_run(gm: Node) -> void:
	gm.call("_reset_run")

## 地牢生成器的 BFS 距离表
func gen_bfs_distances(gen: Node) -> Dictionary:
	return gen.get("_bfs_distances")

## 特效池的每帧推进
func field_process(field: Node, delta: float) -> void:
	field.call("_process", delta)

## BuffHolder 的目标节点
func holder_target(holder: Node) -> Node:
	return holder.get("_target")

## HUD 玩家受击刷新
func hud_on_player_hit(hud: Node, amount: float, from: Vector3) -> void:
	hud.call("_on_player_hit", amount, from)

## HUD 毒气标签刷新
func hud_update_gas_label(hud: Node) -> void:
	hud.call("_update_gas_label")

## 主菜单返回上一级
func menu_go_back(menu: Node) -> void:
	menu.call("_go_back")

## 暂停菜单打开设置
func pause_menu_on_settings(pm: Node) -> void:
	pm.call("_on_settings")

## 结算面板继续
func settlement_on_continue(sp: Node) -> void:
	sp.call("_on_continue")

## 技能系统发射投射物
func skill_system_cast_projectile(ss: Node, data: Dictionary) -> void:
	ss.call("_cast_projectile", data)


# ============================================================
# 背包 UI —— 30 个（数量最多的宿主）
# ============================================================

## 当前选中项（EquipmentInstance，**不是 Node**）
##
## **返回类型必须写宽**：写成 `Node` 时 Godot 会对不符的返回值**静默返回 null**
## （不报错、不警告），调用方的断言就会莫名其妙地失败。
## 本项目已多次被这类"类型撒谎"咬到，故此处一律用无类型返回。
func ui_selected(ui: Node):
	return ui.get("_selected")

## 置当前选中项
func set_ui_selected(ui: Node, item) -> void:
	ui.set("_selected", item)

## 装备槽网格
func ui_slot_grid(ui: Node) -> Node:
	return ui.get("_slot_grid")

## 所有装备槽网格（**Dictionary**：slot_id → BackpackItem，不是 Array）
func ui_slot_grids(ui: Node) -> Dictionary:
	return ui.get("_slot_grids")

## 背包网格
func ui_grids(ui: Node) -> Array:
	return ui.get("_grids")

## 属性面板
func ui_stats(ui: Node) -> Node:
	return ui.get("_stats")

## 详情标题
func ui_detail_name(ui: Node) -> Node:
	return ui.get("_detail_name")

## 详情元信息
func ui_detail_meta(ui: Node) -> Node:
	return ui.get("_detail_meta")

## 详情词条
func ui_detail_affix(ui: Node) -> Node:
	return ui.get("_detail_affix")

## 装备页
func ui_equip_page(ui: Node) -> Node:
	return ui.get("_equip_page")

## 强化页
func ui_craft_page(ui: Node) -> Node:
	return ui.get("_craft_page")

## 融合材料来源（EquipmentInstance，**不是 Node**——类型写窄会静默返回 null）
func ui_fusion_source(ui: Node):
	return ui.get("_fusion_source")

## 多选状态（**Dictionary**：EquipmentInstance → true，不是 Array）
func ui_multi(ui: Node) -> Dictionary:
	return ui.get("_multi")

## 清空多选
func ui_clear_multi(ui: Node) -> void:
	ui.call("_clear_multi")

## 切换多选
func ui_toggle_multi(ui: Node, item) -> void:
	ui.call("_toggle_multi", item)

## 切页
func ui_switch_page(ui: Node, page) -> void:
	ui.call("_switch_page", page)

## 刷新详情面板
func ui_refresh_detail(ui: Node) -> void:
	ui.call("_refresh_detail")

## 按钮：装备
func ui_btn_equip(ui: Node) -> Node:
	return ui.get("_btn_equip")

## 按钮：吞噬
func ui_btn_devour(ui: Node) -> Node:
	return ui.get("_btn_devour")

## 按钮：强化
func ui_btn_enhance(ui: Node) -> Node:
	return ui.get("_btn_enhance")

## 按钮：融合
func ui_btn_fuse(ui: Node) -> Node:
	return ui.get("_btn_fuse")

## 回调：装备
func ui_on_btn_equip(ui: Node) -> void:
	ui.call("_on_btn_equip")

## 回调：吞噬
func ui_on_btn_devour(ui: Node) -> void:
	ui.call("_on_btn_devour")

## 回调：强化
func ui_on_btn_enhance(ui: Node) -> void:
	ui.call("_on_btn_enhance")

## 回调：融合
func ui_on_btn_fuse(ui: Node) -> void:
	ui.call("_on_btn_fuse")

## 回调：选材料
func ui_on_btn_pick(ui: Node) -> void:
	ui.call("_on_btn_pick")

## 回调：筛选·全部
func ui_on_filter_all(ui: Node) -> void:
	ui.call("_on_filter_all")

## 回调：筛选·武器
func ui_on_filter_weapon(ui: Node) -> void:
	ui.call("_on_filter_weapon")

## 回调：点选物品
func ui_on_item_clicked(ui: Node, index: int) -> void:
	ui.call("_on_item_clicked", index)

## 回调：点选装备槽
func ui_on_slot_clicked(ui: Node, index: int) -> void:
	ui.call("_on_slot_clicked", index)

## 回调：动作请求（统一入口）
func ui_on_action_requested(ui: Node, action: String, index: int) -> void:
	ui.call("_on_action_requested", action, index)


# ============================================================
# 覆盖率自检
# ============================================================

## 本文件登记的名字清单 —— **重构搬走成员时必须同步更新**。
##
## 结构：{ "宿主类别": [名字, ...] }。
## 前四组（player / enemy / roomctrl / gameroot）会被
## `assert_coverage()` 逐一核对是否真实存在于对应脚本上；
## 其余宿主类型杂、实例化成本高，只登记不自动核对。
const REGISTERED := {
	"player": [
		"_hitstop", "_is_sprinting", "_is_dodging", "_attack_timer",
		"_current_attack_cooldown", "_sprint_attack_timer", "_in_cancel_window",
		"_cancel_current_attack", "_start_normal_attack", "_finisher_armor_timer",
		"_facing", "_hit_combo_count", "_hit_combo_time", "_register_hit_combo",
		"_apply_combo_heal", "_apply_hit", "_basic_attack_pierce", "_fist_reach_bonus",
		"_is_backstab", "_perform_melee_attack", "_on_player_hurt",
		"_on_basic_attack_landed", "_lifesteal_heal", "_reflect_damage",
		"_chain_spell_damage", "_refresh_light_dark_balance", "_gain_light_layer",
		"_maybe_trigger_break_limit", "_spawn_forest_domain", "_spawn_slash_visual",
		"_jump_phase", "_state_machine", "_model", "_flash_timer", "_pickup_nearby",
	],
	"enemy": [
		"_hp", "_flash_timer", "_hp_bar", "_hp_bar_bg", "_hp_bar_fill", "_apply_affix",
	],
	"roomctrl": [
		"_doors", "_is_special_room", "_on_cleared", "_spawn_points",
		"_special_service", "_special_used", "_special_was_used", "_crowd",
		"_should_use_crowd", "_spawn_crowd_at", "_spawn_enemy_at",
	],
	"gameroot": [
		"_dir_vector", "_opposite_dir", "_find_room_in_direction",
		"_on_door_entered", "_transition_to_room", "_room_cache", "_current_floor_num",
	],
}


## 核对本文件登记的成员在对应脚本里真实存在。
##
## **这是重构的报警器**：某个私有方法被搬走 / 改名而忘了更新 probe 时，
## 这里会点名报出具体名字，而不是等到某个测试莫名其妙地红。
##
## 返回：[缺失项描述, ...]，空数组表示全部通过。
static func assert_coverage() -> Array:
	var missing: Array = []
	var scripts := {
		"player": "res://entities/player/player.gd",
		"enemy": "res://entities/enemies/enemy_base.gd",
		"roomctrl": "res://gameplay/dungeon/room_controller.gd",
		"gameroot": "res://scenes/game_root.gd",
	}
	for kind in REGISTERED:
		if not scripts.has(kind):
			continue
		var src: String = _read_source(scripts[kind])
		if src.is_empty():
			missing.append("%s: 脚本读取失败 %s" % [kind, scripts[kind]])
			continue
		for name in REGISTERED[kind]:
			if not _declares(src, name):
				missing.append("%s 缺少 %s" % [kind, name])
	return missing


## 源码里是否声明了该成员（`func _name(` 或 `var _name`）。
##
## 变量声明的四种形态都要认，否则会误报：
##   `var _x`（裸声明）· `var _x = 1` · `var _x: T` · `var _x: T = 1`
## 故判定「`var _name` 后面紧跟的字符不是标识符字符」——
## 这样 `var _x` 不会误配到 `var _xyz`。
##
## **必须认 `\r`**：本仓库部分文件是 CRLF 行尾（Git 检出时转换），
## 只认 `\n` 会把裸声明的行尾判成标识符字符而误报缺失。
static func _declares(src: String, name: String) -> bool:
	if src.contains("\nfunc %s(" % name):
		return true
	var needle := "\nvar %s" % name
	var idx := src.find(needle)
	while idx >= 0:
		var after := idx + needle.length()
		if after >= src.length():
			return true                      # 文件末尾的裸声明
		var c := src[after]
		if c == "\n" or c == "\r" or c == " " or c == "\t" \
				or c == ":" or c == "=":
			return true
		idx = src.find(needle, idx + 1)
	return false


## 读脚本源文件（走 FileAccess 而非 load，避免受类缓存影响）
static func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text
