class_name WeaponData
extends Resource
## 武器数据 —— 融合成长 + 吞噬 + 词条
## 文档：ai/框架相关.md Equipment Studio

@export_category("Identity")
@export var weapon_id: String = ""
@export var weapon_name: String = ""
@export_enum("White:白", "Green:绿", "Blue:蓝", "Red:红", "Mythic:神话")
var rarity: String = "White"

@export_category("Stats")
@export var base_atk: int = 10
@export var modifiers: Array[ModifierData] = []

@export_category("Growth")
@export var fusion_level: int = 0
@export var max_fusion: int = 25
@export var fusion_atk_growth: float = 5.0
@export var devour_effects: Array[ModifierData] = []

@export_category("Visual")
@export var sprite_path: String = ""
@export var fusion_sprites: Array[String] = []


func current_atk() -> int:
	return base_atk + int(fusion_level * fusion_atk_growth)


func can_fuse() -> bool:
	return fusion_level < max_fusion


func fuse() -> void:
	if can_fuse():
		fusion_level += 1


func description() -> String:
	return "%s [%s] ATK:%d 融合:%d/%d" % [weapon_name, rarity, current_atk(), fusion_level, max_fusion]
