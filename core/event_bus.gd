extends Node
## 全局事件总线 —— HD-2D 重构版
## 所有游戏事件通过信号解耦，逻辑层与表现层互不依赖
##
## 使用方式：
##   EventBus.enemy_died.emit(enemy_data, world_position)
##   EventBus.player_attacked.emit(direction, skill_data)

# ============================================================
# 玩家事件
# ============================================================
@warning_ignore("unused_signal")
signal player_moved(world_position: Vector3, direction: Vector3)
@warning_ignore("unused_signal")
signal player_attacked(direction: Vector3, skill_id: String)
@warning_ignore("unused_signal")
signal player_skill_cast(skill_id: String, direction: Vector3)
@warning_ignore("unused_signal")
signal player_hit(damage: float, source_position: Vector3)
@warning_ignore("unused_signal")
signal player_died(killer_name: String)

# ============================================================
# 战斗事件
# ============================================================
@warning_ignore("unused_signal")
signal damage_dealt(source: Node, target: Node, amount: float, element: String, is_crit: bool)
@warning_ignore("unused_signal")
signal enemy_died(enemy: Node, world_position: Vector3, loot_table: Array)
## 有单位死亡（**含敌人被敌人打死**），供「击杀成长」类机制感知。
##
## 为什么不能复用 `enemy_died`：那条信号的接收方（玩家击杀统计、掉落、
## 楼层机制）语义都是「玩家击杀」，把「怪物A 打死 怪物B」也发进去会污染
## 击杀计数与掉落。而分册 9-5 虚空吞噬者明确要求「每击杀一个单位
## （**包括其他怪物**）」，故单开一条。
##
## 性能：**只在场上有吞噬者时才发**（`EnemyBase._broadcast_death` 标记）——
## 否则每只怪死亡都要做一次全组查找，白付代价。
@warning_ignore("unused_signal")
signal unit_died(victim: Node, killer: Node, world_position: Vector3)
@warning_ignore("unused_signal")
signal projectile_hit(projectile: Node, target: Node, hit_position: Vector3)

# ============================================================
# 房间事件
# ============================================================
@warning_ignore("unused_signal")
signal room_entered(room_id: String)
@warning_ignore("unused_signal")
signal room_cleared(room_id: String)
@warning_ignore("unused_signal")
signal room_exited(room_id: String)
@warning_ignore("unused_signal")
signal door_opened(door_id: String, direction: String)
@warning_ignore("unused_signal")
signal door_locked(door_id: String)

# ============================================================
# 装备/物品事件
# ============================================================
## 宝箱被打开（第 6 层「硫磺毒气」减层挂钩：开宝箱 -1 层）。
## 原先开箱只发 gold_changed + message，外部无法感知"开了一个箱子"。
@warning_ignore("unused_signal")
signal chest_opened(gold: int, position: Vector3)
@warning_ignore("unused_signal")
signal item_picked_up(item_id: String, item_name: String)
@warning_ignore("unused_signal")
signal item_devoured(item_id: String, item_name: String)
@warning_ignore("unused_signal")
signal equipment_changed(slot: int, item_id: String)
@warning_ignore("unused_signal")
signal inventory_changed

# ============================================================
# 属性/UI 事件
# ============================================================
@warning_ignore("unused_signal")
signal stats_changed
@warning_ignore("unused_signal")
signal gold_changed(amount: int)
@warning_ignore("unused_signal")
signal damage_popup(world_position: Vector3, amount: float, kind: String)
@warning_ignore("unused_signal")
signal message(text: String)
@warning_ignore("unused_signal")
signal screen_shake(intensity: float, duration: float)

# ============================================================
# 游戏流程事件
# ============================================================
@warning_ignore("unused_signal")
signal game_started
@warning_ignore("unused_signal")
signal run_finished(result: Dictionary)
@warning_ignore("unused_signal")
signal boss_state_changed(cleared: bool)

## Boss 血条：玩家进入 Boss 房时发 name/max_hp，HUD 据此显示顶部血条栏
@warning_ignore("unused_signal")
signal boss_engaged(boss_name: String, max_hp: float)
@warning_ignore("unused_signal")
signal floor_changed(floor_number: int)

## 钥匙碎片：获得一片时发（当前本局总数, 来源层）。HUD 据此提示与刷新进度
@warning_ignore("unused_signal")
signal key_fragment_gained(total: int, from_floor: int)