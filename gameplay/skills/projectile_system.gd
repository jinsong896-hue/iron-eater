class_name ProjectileSystem
extends RefCounted
## 投射物系统 —— 技能系统入口
##
## 本文件原先是「运行时 GDScript.new() + source_code 编译」的实现：
## 每次生成投射物都要编译一次脚本，且只硬编码打 enemies 组。
## 现已改为薄封装 —— 核心逻辑统一在 gameplay/skills/projectile.gd，
## 本文件只保留既有接口（skill_system.gd 依赖），避免重复实现。
##
## 需要弹射/弧线/延时/分裂等高级机制时，直接用 Projectile.spawn()。


## 创建投射物（向后兼容入口）
## parent 为挂载父节点；玩家技能射出的投射物打 enemies 组
static func spawn(projectile_data: Dictionary, parent: Node3D) -> Node3D:
	return Projectile.spawn(projectile_data, parent, Projectile.TARGET_ENEMY)


## 元素配色（保留旧接口）
static func element_color(element: String) -> Color:
	return Projectile.element_color(element)
