extends Node
## 全局事件总线 —— HD-2D 重构版
## 所有游戏事件通过信号解耦，逻辑层与表现层互不依赖
##
## ## 契约（2026-09-21 实测审计）
##
## 每个信号标注 **发射者 → 订阅者** 与实测计数。计数来自
## `grep -rn "\.信号\.emit("` / `\.connect(`（排除 addons/ 与 房间参考/）。
##
## **`无订阅` 的信号不是缺陷，是预留扩展面**——EventBus 的职责就是广播，
## 发射者不该知道谁在听。但状态必须可见，故逐条标注：
##
## | 状态 | 含义 | 处置 |
## |---|---|---|
## | `N 发 M 收` | 正常接线 | 改签名时两边都要动 |
## | `N 发 0 收` | **有发无收**——留白，将来接统计/成就/音效/教学 | 可安全改签名（无订阅方） |
## | `0 发 0 收` | 完全空置 | 同上 |
##
## 启动时 `WiredCheck.audit_event_bus()` 会把有发无收的清单打到输出（debug 构建）。
##
## ## 使用方式
##   EventBus.enemy_died.emit(enemy_data, world_position)
##   EventBus.player_attacked.emit(direction, skill_data)

# ============================================================
# 玩家事件
# ============================================================
@warning_ignore("unused_signal")
## 2 发（move_state / dodge_state）· 0 收 —— 留白：将来接脚步声/移动教学
## 2 发（move_state / dodge_state）· 0 收 —— 留白：将来接脚步声/移动教学
signal player_moved(world_position: Vector3, direction: Vector3)
@warning_ignore("unused_signal")
## 2 发（player）· 0 收 —— 留白：将来接挥砍音效/连段统计
## 2 发（player）· 0 收 —— 留白：将来接挥砍音效/连段统计
signal player_attacked(direction: Vector3, skill_id: String)
@warning_ignore("unused_signal")
## 1 发（skill_facade）· 0 收 —— 留白：将来接技能音效/施法统计
## 1 发（skill_facade）· 0 收 —— 留白：将来接技能音效/施法统计
signal player_skill_cast(skill_id: String, direction: Vector3)
@warning_ignore("unused_signal")
## 4 发（player 受击/无敌帧/护盾挡）· 1 收（HUD 血条刷新）
## 4 发（player 受击/无敌帧/护盾挡）· 1 收（HUD 血条刷新）
signal player_hit(damage: float, source_position: Vector3)
@warning_ignore("unused_signal")
## 0 发 0 收 —— 完全空置（死亡实际走 GameManager.finish_run → run_finished）
## 0 发 0 收 —— 完全空置（死亡实际走 GameManager.finish_run → run_finished）
signal player_died(killer_name: String)

# ============================================================
# 战斗事件
# ============================================================
## 伤害发生（**语义尚未统一，接订阅者前先读这段**）。
##
## 现有两个发射点的参数语义**相反**：
##   · `enemy_base.gd` 的 `_perform_attack()`：`emit(self, _player, ...)`
##     —— source=敌人、target=玩家，即「**玩家承受**」
##   · `damage_pipeline.gd` 的 `emit_damage_result()`：`emit(null, target, ...)`
##     —— source=null、target=敌人，即「**玩家造成**」
##
## 而且第二条**在生产路径上不会执行**：它的唯一调用者是
## `CombatSystem`（`gameplay/combat/combat_system.gd`），那是个死类
## （生产与测试都零引用，player 的近战走自己的 `_hit_enemies_in_cone`）。
##
## 故实际只有「玩家承受」那一条会发。目前**零订阅者**，不影响任何可见行为。
## 将来接统计面板/成就时，**先决定要哪种语义**再统一（用户 2026-09-21 决策：
## 暂不动代码，仅记录）。
##
## 与之相对，`GameManager.total_damage` 的语义是明确的（玩家造成，见其声明）。
@warning_ignore("unused_signal")
signal damage_dealt(source: Node, target: Node, amount: float, element: String, is_crit: bool)
@warning_ignore("unused_signal")
## 3 发（room_controller / spawn_director）· 4 收（玩家统计/掉落/楼层机制）
## 3 发（room_controller / spawn_director）· 4 收（玩家统计/掉落/楼层机制）
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
## 3 发（projectile_manager 命中/爆炸）· 0 收 —— 留白：将来接弹丸音效/命中统计
## 3 发（projectile_manager 命中/爆炸）· 0 收 —— 留白：将来接弹丸音效/命中统计
signal projectile_hit(projectile: Node, target: Node, hit_position: Vector3)

# ============================================================
# 房间事件
# ============================================================
@warning_ignore("unused_signal")
## 1 发（room_controller.activate）· 1 收（小地图）
## 1 发（room_controller.activate）· 1 收（小地图）
signal room_entered(room_id: String)
@warning_ignore("unused_signal")
## 1 发（room_controller._on_cleared）· 0 收 —— 留白：将来接清房奖励/成就
## 1 发（room_controller._on_cleared）· 0 收 —— 留白：将来接清房奖励/成就
signal room_cleared(room_id: String)
@warning_ignore("unused_signal")
## 1 发（room_controller.deactivate）· 0 收 —— 留白：将来接离开音效/统计
## 1 发（room_controller.deactivate）· 0 收 —— 留白：将来接离开音效/统计
signal room_exited(room_id: String)
@warning_ignore("unused_signal")
## 1 发（room_controller._lock_doors）· 3 收（门触发器/HUD）
## 1 发（room_controller._lock_doors）· 3 收（门触发器/HUD）
signal door_opened(door_id: String, direction: String)
@warning_ignore("unused_signal")
## 1 发（room_controller._lock_doors）· 0 收 —— 留白：将来接锁门音效/提示
## 1 发（room_controller._lock_doors）· 0 收 —— 留白：将来接锁门音效/提示
signal door_locked(door_id: String)

# ============================================================
# 装备/物品事件
# ============================================================
## 宝箱被打开（第 6 层「硫磺毒气」减层挂钩：开宝箱 -1 层）。
## 原先开箱只发 gold_changed + message，外部无法感知"开了一个箱子"。
@warning_ignore("unused_signal")
## 1 发（chest）· 3 收（毒气层/统计/成就）
## 1 发（chest）· 3 收（毒气层/统计/成就）
signal chest_opened(gold: int, position: Vector3)
@warning_ignore("unused_signal")
## 2 发（pickup_item / shop_controller）· 0 收 —— 留白：将来接拾取音效/图鉴解锁
## 2 发（pickup_item / shop_controller）· 0 收 —— 留白：将来接拾取音效/图鉴解锁
signal item_picked_up(item_id: String, item_name: String)
@warning_ignore("unused_signal")
## 1 发（equipment_manager.devour）· 0 收 —— 留白：将来接吞噬特效/成长提示
## 1 发（equipment_manager.devour）· 0 收 —— 留白：将来接吞噬特效/成长提示
signal item_devoured(item_id: String, item_name: String)
@warning_ignore("unused_signal")
## 3 发（equipment_manager）· 2 收（玩家重算攻击元素 / HUD 装备栏）
## 3 发（equipment_manager）· 2 收（玩家重算攻击元素 / HUD 装备栏）
signal equipment_changed(slot: int, item_id: String)
@warning_ignore("unused_signal")
## 6 发（背包/装备管理器）· 1 收（背包 UI 刷新）
signal inventory_changed

# ============================================================
# 属性/UI 事件
# ============================================================
@warning_ignore("unused_signal")
## 17 发（属性变更各处）· 1 收（HUD 数值刷新）
signal stats_changed
@warning_ignore("unused_signal")
## 4 发（金币变更各处）· 4 收（HUD / 商店 / 结算）
## 4 发（金币变更各处）· 4 收（HUD / 商店 / 结算）
signal gold_changed(amount: int)
@warning_ignore("unused_signal")
## 27 发（伤害结算各处）· 3 收（飘字渲染）
## 27 发（伤害结算各处）· 3 收（飘字渲染）
signal damage_popup(world_position: Vector3, amount: float, kind: String)
@warning_ignore("unused_signal")
## 37 发（提示各处）· 1 收（HUD 消息条）
## 37 发（提示各处）· 1 收（HUD 消息条）
signal message(text: String)
@warning_ignore("unused_signal")
## 2 发（投射物爆炸 / 玩家落地斩）· 3 收（CameraRig 已接）
## 2 发（投射物爆炸 / 玩家落地斩）· 3 收（CameraRig 已接）
signal screen_shake(intensity: float, duration: float)

# ============================================================
# 游戏流程事件
# ============================================================
@warning_ignore("unused_signal")
## 1 发（GameManager.start_new_run）· 1 收（玩家重配职业/形态）
signal game_started
@warning_ignore("unused_signal")
## 1 发（GameManager.finish_run）· 1 收（结算面板）
## 1 发（GameManager.finish_run）· 1 收（结算面板）
signal run_finished(result: Dictionary)
@warning_ignore("unused_signal")
## 1 发（SpawnDirector._on_boss_died）· 1 收（HUD 隐藏 Boss 血条）
## 1 发（SpawnDirector._on_boss_died）· 1 收（HUD 隐藏 Boss 血条）
signal boss_state_changed(cleared: bool)

## Boss 血条：玩家进入 Boss 房时发 name/max_hp，HUD 据此显示顶部血条栏
@warning_ignore("unused_signal")
## 1 发（SpawnDirector._spawn_boss）· 1 收（HUD）
## 1 发（SpawnDirector._spawn_boss）· 1 收（HUD）
signal boss_engaged(boss_name: String, max_hp: float)
@warning_ignore("unused_signal")
## 1 发（GameRoot.next_floor）· 1 收（HUD/小地图）
## 1 发（GameRoot.next_floor）· 1 收（HUD/小地图）
signal floor_changed(floor_number: int)

## 钥匙碎片：获得一片时发（当前本局总数, 来源层）。HUD 据此提示与刷新进度
@warning_ignore("unused_signal")
## 1 发（GameManager.add_key_fragment）· 1 收（HUD）
## 1 发（GameManager.add_key_fragment）· 1 收（HUD）
signal key_fragment_gained(total: int, from_floor: int)
