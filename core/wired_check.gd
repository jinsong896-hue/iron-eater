class_name WiredCheck
extends RefCounted
## 接线自检 —— 把"静默失效"变成"有声"。
##
## ## 为什么要有这个
##
## 本项目反复被同一类缺陷咬：**代码在跑、不报错、只是什么都不发生**。
## 已知的实例（全部是真实发生过并修掉的）：
##
##   · `AudioManager.play()` 里 `match name:` 匹配错了变量名 → 音效全程无声
##   · `EventBus.screen_shake` 有 2 处 emit、**零订阅者** → 爆炸没有画面反馈
##   · HUD 用 `current_scene` 取 GameRoot 恒为 null → 毒气层数永远不显示
##   · `_refs` 下标耦合、`force_position` 从不存在的守卫……
##
## 共同点：**没有任何一处会报错**。这类缺陷靠人肉 review 抓不住，
## 只能靠"启动时点名"。
##
## ## 本类做什么
##
## debug 构建启动时打印一份接线审计：每个 `EventBus` 信号的
## 「发射者数 / 订阅者数 / 状态」，把 **有发无收** 与 **两边全空** 的信号
## 明确列出来。**它不改任何行为、不报错、不影响门禁判据**——
## 只是让下一个人在一分钟内看到"这条线没人接"。
##
## ## 用法
##
## ```gdscript
## if OS.is_debug_build():
##     WiredCheck.audit_event_bus()
## ```


## 信号的接线状态表。
##
## 结构：{ 信号名: [发射者文件数, 订阅者文件数, 备注] }。
##
## **这张表是快照，会随代码演进过期**——它的价值不在于数字精确，
## 而在于**有发无收的信号被显式记录**：要么补上订阅者，要么在备注里
## 写清"预留扩展面"，不留"忘了接"这种模糊状态。
##
## 采集方式（2026-09-20）：
##   grep -rl "\.<信号>\.emit" --include=*.gd . | grep -v addons
##   grep -rl "\.<信号>\.connect" --include=*.gd . | grep -v addons
const SIGNAL_TABLE := {
	# —— 有发无收：发射了，但没人听 ——
	"player_moved":        [2, 0, "预留扩展面（脚步声/足迹/教学提示）"],
	"player_attacked":     [1, 0, "预留扩展面（连击统计/成就）"],
	"player_skill_cast":   [1, 0, "预留扩展面（技能统计/教学）"],
	"damage_dealt":        [2, 0, "预留扩展面（统计面板；**语义未统一**——两处发射点参数相反，见 EventBus 声明）"],
	"room_cleared":        [1, 0, "预留扩展面（成就/评分）"],
	"room_exited":         [1, 0, "预留扩展面"],
	"door_locked":         [1, 0, "预留扩展面（音效/UI 提示）"],
	"item_picked_up":      [2, 0, "预留扩展面（拾取提示/统计）"],
	"item_devoured":       [1, 0, "预留扩展面（吞噬统计）"],

	# —— 两边全空：零发射零订阅的遗留定义 ——
	"player_died":         [0, 0, "遗留定义：死亡走 GameManager.finish_run，删或留无行为差异"],
	"projectile_hit":      [0, 0, "遗留定义：命中走 ProjectileManager.projectile_hit（同名另一信号）"],

	# —— 正常接线 ——
	"player_hit":          [1, 1, ""],
	"enemy_died":          [2, 2, ""],
	"unit_died":           [1, 1, ""],
	"room_entered":        [1, 1, ""],
	"door_opened":         [1, 3, ""],
	"chest_opened":        [1, 1, ""],
	"equipment_changed":   [1, 2, ""],
	"inventory_changed":   [2, 1, ""],
	"stats_changed":       [5, 1, ""],
	"gold_changed":        [3, 4, ""],
	"damage_popup":        [8, 3, ""],
	"message":             [13, 1, ""],
	"screen_shake":        [2, 1, "2026-09-20 接上 CameraRig.shake（此前零订阅）"],
	"game_started":        [1, 1, ""],
	"run_finished":        [1, 1, ""],
	"boss_state_changed":  [1, 1, ""],
	"boss_engaged":        [1, 1, ""],
	"floor_changed":       [1, 1, ""],
	"key_fragment_gained": [1, 1, ""],
}


## 跑一次接线审计，结果打到 stdout。
##
## 返回 { "dead": [有发无收], "empty": [两边全空], "wired": 正常条数 }，
## 便于测试断言或将来接进 debug 面板。
static func audit_event_bus() -> Dictionary:
	var dead: Array = []
	var empty: Array = []
	var wired := 0
	for name in SIGNAL_TABLE:
		var row: Array = SIGNAL_TABLE[name]
		var emits: int = row[0]
		var subs: int = row[1]
		if emits > 0 and subs == 0:
			dead.append("%s（%d 处发射，0 订阅）— %s" % [name, emits, row[2]])
		elif emits == 0 and subs == 0:
			empty.append("%s — %s" % [name, row[2]])
		else:
			wired += 1
	print("[WiredCheck] EventBus 接线审计：共 %d 条信号，正常 %d 条"
		% [SIGNAL_TABLE.size(), wired])
	if not dead.is_empty():
		print("[WiredCheck]   有发无收 %d 条（发射了但没人听，功能静默失效）：" % dead.size())
		for d in dead:
			print("[WiredCheck]     · %s" % d)
	if not empty.is_empty():
		print("[WiredCheck]   两边全空 %d 条（零发射零订阅的遗留定义）：" % empty.size())
		for e in empty:
			print("[WiredCheck]     · %s" % e)
	return {"dead": dead, "empty": empty, "wired": wired}


## 校验信号表与实际 `event_bus.gd` 声明**一一对应**。
##
## 防止表过期：新增了信号却忘了登记（新信号最容易"有发无收"），
## 或删了信号但表里还留着。
##
## 返回缺失/多余的信号名清单，空数组表示完全一致。
static func verify_table() -> Array:
	var issues: Array = []
	var declared := _declared_signals()
	for name in declared:
		if not SIGNAL_TABLE.has(name):
			issues.append("event_bus.gd 声明了 %s，但 WiredCheck 表里没登记" % name)
	for name in SIGNAL_TABLE:
		if not declared.has(name):
			issues.append("WiredCheck 表里的 %s 在 event_bus.gd 里已不存在" % name)
	return issues


## 读 event_bus.gd 源文件，抽出全部 `signal <name>` 声明
static func _declared_signals() -> Array:
	var out: Array = []
	var f := FileAccess.open("res://core/event_bus.gd", FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("signal "):
			var rest := line.substr(7).strip_edges()
			var name := rest.split("(")[0].strip_edges()
			if not name.is_empty():
				out.append(name)
	f.close()
	return out
