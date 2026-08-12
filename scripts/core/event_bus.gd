extends Node
## 全局事件总线（原型阶段最小版）

signal stats_changed
signal inventory_changed
signal gold_changed
signal player_damage_dealt(total: float, crit: bool)
signal enemy_died
signal message(text: String)
signal layer_changed(layer_id: int, layer_name: String)
