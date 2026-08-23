extends Node
## 全局事件总线（原型阶段最小版）
## 信号通过 connect() 在其他脚本中使用，静态分析器不会追踪

@warning_ignore("unused_signal")
signal stats_changed
@warning_ignore("unused_signal")
signal inventory_changed
@warning_ignore("unused_signal")
signal gold_changed
@warning_ignore("unused_signal")
signal enemy_died
@warning_ignore("unused_signal")
signal message(text: String)
@warning_ignore("unused_signal")
signal layer_changed(layer_id: int, layer_name: String)
@warning_ignore("unused_signal")
signal player_hit(amount: float)
@warning_ignore("unused_signal")
signal run_finished(result: Dictionary)
@warning_ignore("unused_signal")
signal boss_state_changed(cleared: bool)
@warning_ignore("unused_signal")
signal damage_popup(world_pos: Vector2, amount: float, kind: String)
