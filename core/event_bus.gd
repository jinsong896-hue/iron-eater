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