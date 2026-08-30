class_name StatusEffect
extends RefCounted
## 状态效果系统 —— HD-2D 重构版
## 管理 Buff/Debuff 的施加、计时、移除

enum EffectType {
	BUFF,
	DEBUFF,
	DOT,       # 持续伤害
	HOT,       # 持续治疗
	STUN,      # 眩晕
	SLOW,      # 减速
}

var id := ""
var effect_type := EffectType.BUFF
var duration := 0.0
var tick_interval := 1.0
var value: float = 0.0
var stat_affected := AttributeSystem.Stat.ATK
var _elapsed := 0.0
var _tick_timer := 0.0


func _init(p_id: String, p_type: int, p_duration: float, p_value: float) -> void:
	id = p_id
	effect_type = p_type
	duration = p_duration
	value = p_value


## 更新状态效果，返回是否已过期
func update(delta: float) -> bool:
	_elapsed += delta
	if _elapsed >= duration:
		return true  # 已过期

	if tick_interval > 0.0:
		_tick_timer += delta
		if _tick_timer >= tick_interval:
			_tick_timer -= tick_interval
			return false  # 触发 tick

	return false


func is_expired() -> bool:
	return _elapsed >= duration


func get_remaining() -> float:
	return maxf(duration - _elapsed, 0.0)