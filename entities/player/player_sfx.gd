class_name PlayerSfx
extends RefCounted
## 玩家音效的**语义接口层** —— 把"播哪个音频文件"与"什么时候播"分开。
##
## ## 为什么要有这一层
##
## 音效此前是 `player.gd` 里散落的 `AudioManager.play("hit")` 字面量。
## 这有两个问题：
##
## 1. **语义丢失**：调用点只写得出"播 hit"，写不出"这是受击音"还是
##    "这是命中敌人的音"——同一个 `hit` 目前被两种意图共用（见下）。
## 2. **换素材要改逻辑**：策划想换受击音，得去 `player.gd` 里找字面量。
##
## 收口到本类后，`player.gd` 只表达**意图**（`PlayerSfx.on_hurt()`），
## 具体映射到哪个素材由本类决定。
##
## ## 范围：只暴露**已接线**的音效
##
## 本类**只包含当前真实在播的音效**。不预置"将来可能会有"的钩子——
## 那会在代码里留死条目（本项目有过先例：`SFX_MAP` 里 `door`/`chest`
## 两条无调用点，后来删掉了）。要加新音效时，先有调用点、再进本类。
##
## ## 待用户决策
##
## `hit` 目前被两种语义共用：**玩家受击** 与 **玩家命中敌人**。
## 两者的素材是同一个（`knifeSlice2.ogg`），故听感上无差别。
## 是否拆分由策划/审美决定——本类已把两个意图分成了两个方法
##（`on_hurt()` / `on_hit_landed()`），拆分时只需改各自的映射，调用点不动。

## 玩家受击（扣血时）
static func on_hurt() -> void:
	AudioManager.play("hit")


## 玩家攻击命中敌人
static func on_hit_landed() -> void:
	AudioManager.play("hit")


## 玩家阵亡
static func on_death() -> void:
	AudioManager.play("death")


## 破开隐藏墙（策划 3.2 隐藏房入口）
static func on_break_wall() -> void:
	AudioManager.play("hit")


## 吞噬装备成功（本局永久成长）
static func on_devour() -> void:
	AudioManager.play("pickup")
