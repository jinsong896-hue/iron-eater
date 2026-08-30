class_name ItemData
extends Resource
## 物品数据 —— HD-2D 重构版
## 通用物品定义（消耗品、材料等）

@export var id := ""
@export var display_name := ""
@export var description := ""
@export var icon: Texture2D

# 物品类型
enum ItemType {
	CONSUMABLE,   # 消耗品
	MATERIAL,     # 材料
	KEY,          # 钥匙
	SCROLL,       # 卷轴
}

@export var item_type := ItemType.CONSUMABLE

# 堆叠
@export var max_stack := 99
@export var stackable := true

# 效果（预留）
@export var effect_id := ""
@export var effect_value: float = 0.0