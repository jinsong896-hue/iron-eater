class_name EquipmentTemplate
extends Resource
## 装备模板 —— 纯数据，运行时不可修改

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var rarity: int = 0
@export var category: int = 0
@export var slot: int = 0
@export var weapon_type: String = ""
@export var armor_class: int = -1
@export var tags: Array[String] = []

## **基础属性**（规格第 1 条）：装备自带的面板加成（武器攻击力这类）。
## 复数形式：规格里基础属性只有一条，但保持与其它三条同构便于统一处理。
@export var base_affixes: Array[AffixData] = []

## **自有词条**（规格第 2 条）：装备独有的额外加成，
## **只有装备在角色身上才会生效**；融合同一件装备时会升级。
##
## **为什么是复数**：规格里约 100 件装备的自有词条是**复合的**
##（用「；」分隔两条效果），例如：
##   「突刺距离增加20%；冲刺后下一次攻击附带30%额外风元素伤害」
## 单条字段装不下——这正是旧实现把复合词条**只取前半句**的原因。
@export var own_affixes: Array[AffixData] = []

## **融合词条**（规格第 3 条）：这件装备**作为素材**融合到其他装备上时
## 产生的额外加成；融合同一件装备时会升级。
@export var fusion_affixes: Array[AffixData] = []

## **吞噬词条**（规格第 4 条）：这件装备**作为素材**被角色吞噬时
## 产生的额外加成；吞噬同一件装备时会升级。
@export var devour_affixes: Array[AffixData] = []

## 触发型词条（名词分册第 5 章「通用词条池（装备可附加）」的 9 种触发型）。
## 与上面三条数值型词条并列：那些改面板属性，这些在**命中时按概率施加词条**
## （眩晕/破甲/致盲/缴械/范围伤害）。数量与概率档位由稀有度决定
## （见 EquipmentDB.TRIGGER_POOL_BY_RARITY），白装没有、橙装才有 2 条。
@export var trigger_affixes: Array[AffixData] = []

@export var icon_path: String = ""
@export var scene_path: String = ""

## 攻击元素（分册 7.1）：仅武器使用。空 = 纯物理。
## 取值 "fire"/"frost"/"static"/"earth"/"wind"/"poison"（ElementDefs）
@export var element: String = ""
## 元素亲和：该件提供的「所有元素伤害 +X%」（分册 4.x 词条），0 = 无
@export var element_affinity: float = 0.0


func _init() -> void:
	resource_name = "EquipmentTemplate"


## 稀有度颜色
func rarity_color() -> Color:
	return EquipmentDefs.RARITY_COLORS.get(rarity, Color.WHITE)


## 是否是单手武器
func is_one_handed_weapon() -> bool:
	if category != EquipmentDefs.Category.WEAPON:
		return false
	return weapon_type in EquipmentDefs.SINGLE_HAND_WEAPONS


## 是否是双手武器
func is_two_handed_weapon() -> bool:
	if category != EquipmentDefs.Category.WEAPON:
		return false
	return not is_one_handed_weapon()


## 能否装备到指定槽位
func can_equip_in(slot_id: int) -> bool:
	return slot == slot_id


# ============================================================
# 兼容访问器（旧单数名 → 新复数表的首项）
# ============================================================
#
# 规格里绝大多数装备每条词条只有**一项**，只有约 100 件是复合的。
# 旧代码全部按「单条」写（`tpl.base_affix`），若一次性改成复数遍历，
# 39 处引用点全要改——改动面大且容易漏。
#
# 故保留单数名作为**派生访问器**：取复数表的首项。
# **消费方若需要完整效果，必须改用复数表**（`own_affixes` 等）；
# 单数访问器只适合"只关心第一条"的场景（如图鉴的简略显示）。

## 基础属性（首项；无则 null）
var base_affix: AffixData:
	get: return base_affixes[0] if base_affixes.size() > 0 else null

## 自有词条（首项；无则 null）
var own_affix: AffixData:
	get: return own_affixes[0] if own_affixes.size() > 0 else null

## 融合词条（首项；无则 null）
var fusion_affix: AffixData:
	get: return fusion_affixes[0] if fusion_affixes.size() > 0 else null

## 吞噬词条（首项；无则 null）
var devour_affix: AffixData:
	get: return devour_affixes[0] if devour_affixes.size() > 0 else null
