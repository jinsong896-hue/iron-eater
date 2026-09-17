class_name ClassBase
extends RefCounted
## 职业基础属性表 —— 《角色设计分册》
##
## **为什么需要这张表**：`AttributeSystem.DEFAULT_BASE` 是「所有角色共用一套起点」，
## 于是选战士和选法师开局完全一样（500 血 / 35 攻），职业选择只在
## `ClassDefs` 的形态 `mods` 上差几个百分点——选谁都是在玩同一个角色。
## 职业之间的差异必须在**起点**就建立，形态机制（`special`）是在起点之上做区分。
##
## ⚠ 数值来源：仓库内没有《角色设计分册》原文，只有 `ClassDefs` 里的转录
##（那部分转录只有形态与技能，没有职业基础值）。故下表是按各职业定位
## 推导的**暂定值**，集中在这一张表里便于按策划原文校准。
## 调平衡只改这里，不要散落到各处。

## 每职业一行，键与 AttributeSystem.STAT_BY_NAME 一致。
## 缺项自动回落到 DEFAULT_BASE（见 apply_to）。
const BASE := {
	# 战士：近战重装。血最厚、防御最高，代价是移速与攻速最慢。
	"warrior": {
		"hp": 620.0, "atk": 38.0, "def": 18.0, "spd": 92.0, "aspd": 0.95,
		"rng": 1.5, "ap": 6.0, "mp": 100.0, "cdr": 0.0, "crt": 0.05, "crd": 0.50,
	},
	# 法师：远程法术。血防最薄，法强与射程换取安全距离下的爆发。
	"mage": {
		"hp": 380.0, "atk": 28.0, "def": 6.0, "spd": 98.0, "aspd": 0.95,
		"rng": 1.8, "ap": 22.0, "mp": 120.0, "cdr": 0.0, "crt": 0.06, "crd": 0.55,
	},
	# 猎人：远程走A。移速与射程最高，暴击/暴伤偏高，靠走位拉扯。
	"hunter": {
		"hp": 440.0, "atk": 34.0, "def": 9.0, "spd": 118.0, "aspd": 1.00,
		"rng": 2.4, "ap": 8.0, "mp": 100.0, "cdr": 0.0, "crt": 0.10, "crd": 0.60,
	},
	# 判官：近战审判。各项居中的均衡型，法强略高于同档近战。
	"judge": {
		"hp": 500.0, "atk": 36.0, "def": 12.0, "spd": 100.0, "aspd": 1.00,
		"rng": 1.6, "ap": 16.0, "mp": 110.0, "cdr": 0.0, "crt": 0.06, "crd": 0.50,
	},
	# 武僧：近战内功。攻速最快、射程最短（贴脸拳），血防中等。
	## 射程 1.2 配合「徒手」形态的 fist_reach 加成，构成"打到人必须在脸上"的手感。
	"monk": {
		"hp": 470.0, "atk": 32.0, "def": 11.0, "spd": 106.0, "aspd": 1.35,
		"rng": 1.2, "ap": 10.0, "mp": 100.0, "cdr": 0.0, "crt": 0.08, "crd": 0.65,
	},
}

## 未知职业的兜底 id（仅用于文案等非数值场景）
const FALLBACK_ID := "warrior"


## 取某职业的基础属性覆盖字典 {AttributeSystem.Stat: float}。
## 未知职业返回空字典——**刻意不做回落**：调用方若拿不到就说明职业 id 有问题，
## 回落成某个职业的数值会把"打错字"伪装成"数值就是这样"。
## 需要"一定能拿到完整一套"的场景用 full_table()（它按 DEFAULT_BASE 补全）。
static func overrides(class_id: String) -> Dictionary:
	if not BASE.has(class_id):
		return {}
	var raw: Dictionary = BASE[class_id]
	var out := {}
	for key in raw:
		var stat_id: int = int(AttributeSystem.STAT_BY_NAME.get(key, -1))
		if stat_id >= 0:
			out[stat_id] = float(raw[key])
	return out


## 整份基础属性 {stat_id: value}。已列出的取本表，**未列出的回落
## AttributeSystem.DEFAULT_BASE**——调用方要"把整套基础值刷一遍"时用这个，
## 保证 11 项都有值而不是变成 0。
## 未知职业同样按 DEFAULT_BASE 全量返回（能让游戏跑起来，而非崩溃）。
static func full_table(class_id: String) -> Dictionary:
	var raw: Dictionary = BASE.get(class_id, {})
	var out := {}
	for key in AttributeSystem.STAT_BY_NAME:
		var stat_id: int = AttributeSystem.STAT_BY_NAME[key]
		if raw.has(key):
			out[stat_id] = float(raw[key])
		else:
			out[stat_id] = float(AttributeSystem.DEFAULT_BASE.get(stat_id, 0.0))
	return out


## 单职业单项基础值。已列出的取本表，未列出的回落 AttributeSystem.DEFAULT_BASE。
static func value_of(class_id: String, stat_key: String) -> float:
	var raw: Dictionary = BASE.get(class_id, {})
	if raw.has(stat_key):
		return float(raw[stat_key])
	var stat_id: int = int(AttributeSystem.STAT_BY_NAME.get(stat_key, -1))
	if stat_id >= 0:
		return float(AttributeSystem.DEFAULT_BASE.get(stat_id, 0.0))
	return 0.0


## 职业定位一句话（选人界面展示用）
static func tagline(class_id: String) -> String:
	return str(TAGLINES.get(class_id, ""))


## 各职业的定位描述（数值口径见上方 BASE 的注释）。
## 注意与 BASE 保持一致：这里的"最快/最厚"被测试断言过，
## 改数值就该同步改文案，否则界面说法会与手感对不上。
const TAGLINES := {
	"warrior": "近战重装 · 血最厚、防最高，靠怒气越战越勇",
	"mage": "远程法术 · 血最薄，用魔力与射程换爆发",
	"hunter": "远程走A · 移速最快、射程最远，靠走位与暴击",
	"judge": "近战审判 · 各项均衡，法强略高于同档近战",
	"monk": "近战内功 · 攻速最快、射程最短，贴脸快拳",
}
