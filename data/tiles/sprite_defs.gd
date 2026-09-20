class_name SpriteDefs
extends RefCounted
## 角色/怪物精灵表定义 —— 单位视觉的唯一真相源
##
## **本文件是精灵系统的唯一真相源**：哪一格是哪种单位、按什么规则挑格。
## 与 `AtlasDefs`（地砖/墙砖）同构，但那是场景贴图、这是**单位贴图**，故分开。
##
## ## 素材来源与烘焙
## 源：`assets/tiny-dungeon/Tilemap/tilemap_packed.png`（Kenney Tiny Dungeon 1.0，
## **CC0**，License 见 `assets/tiny-dungeon/License.txt`）。
##
## 该图集底部四行是角色/怪物/道具，**每行前 5 格**是单位：
##
##   y=112  法师 / 村民 / 僧侣 / 灰狼 / 橙衣人
##   y=128  银甲骑士 / 头盔卫兵 / 剑士 / 粉衣少女 / 灰发老人
##   y=144  绿史莱姆 / 浅棕猿 / 红蟹 / 棕熊 / 绿头带人
##   y=160  棕蝠 / 灰幽灵 / 棕蜘蛛 / 棕鼠 / 灰巨蛛
##
## ## 烘焙（`assets/sprites/units_16x16.png`，80×64、5 列 × 4 行）
##
## **源图自带正确的透明通道，烘焙只是裁格，不是抠图。**
## 这一点踩过坑，写下来免得后人重犯：
##
## 源图是**索引色 PNG**（colorType=3），`tRNS` 只有 1 项 ⇒ **只有调色板索引 0
## 是透明的**，角色外的空白格用的正是索引 0。所以直接把索引→RGBA 展开就得到
## 干净的 alpha，不需要任何颜色阈值判断。
##
## 当时误以为"背景是实色 RGB(118,59,54)"并按颜色距离抠图，**抠反了**：
## RGB(118,59,54) 是调色板**索引 24**，那是角色的**深栗色描边**，不是背景。
## 按颜色距离抠图的结果是把描边抠成透明、把真正的背景（索引 0，黑）留成不透明，
## 于是每只怪都顶着一块黑方块——且因为黑方块在深色场景里不显眼，很晚才被发现。
##
## **改了源图或换了格子，必须重跑烘焙**，否则本表的坐标会指向空图。
##
## ## 与 roguelike 图集的关键差异
## `AtlasDefs` 那张图**格间有 1px 间隔**（STEP_PX = 17），本表**无间隔**
## （stride = 16）。**别把 AtlasDefs 的换算套过来**——会整体偏移。

## 烘焙产物路径
const SHEET_PATH := "res://assets/sprites/units_16x16.png"
## 单格像素尺寸（与源图集一致）
const TILE_PX := 16
## 本表**无格间隔**（源图集是紧密排列的）
const GAP_PX := 0
## 每格步进
const STEP_PX := TILE_PX + GAP_PX
## 表尺寸
const SHEET_W := 80
const SHEET_H := 64
## 列数/行数
const COLS := 5
const ROWS := 4

## 单位类型名 → 格坐标（col, row）。**这是全项目引用单位精灵的唯一入口**。
##
## 命名按"外形"而不是按怪物名：同一个外形会被多个怪物复用
## （如 `humanoid_grunt` 给村民/橙衣人这类杂兵共用），
## 这样换美术时只需改这一张表的映射，不必动 58 个怪物条目。
const CELLS := {
	# ── 人形（第 0 行）──
	"humanoid_mage":    Vector2i(0, 0),   # 紫袍法师
	"humanoid_villager": Vector2i(1, 0),  # 棕发村民
	"humanoid_monk":    Vector2i(2, 0),   # 光头僧侣
	"humanoid_brute":   Vector2i(4, 0),   # 橙衣人（体型感偏壮）
	# ── 人形（第 1 行）──
	"humanoid_knight":  Vector2i(0, 1),   # 银甲骑士
	"humanoid_guard":   Vector2i(1, 1),   # 头盔卫兵
	"humanoid_swordsman": Vector2i(2, 1), # 棕发剑士
	"humanoid_archer":  Vector2i(3, 1),   # 粉衣少女（远程体型）
	"humanoid_elder":   Vector2i(4, 1),   # 灰发老人
	# ── 兽类（第 2 行）──
	"beast_wolf":       Vector2i(3, 0),   # 灰狼（猎犬家族用这个）
	"beast_slime":      Vector2i(0, 2),   # 绿史莱姆
	"beast_ape":        Vector2i(1, 2),   # 浅棕猿
	"beast_crab":       Vector2i(2, 2),   # 红蟹
	"beast_bear":       Vector2i(3, 2),   # 棕熊
	"beast_bandit":     Vector2i(4, 2),   # 绿头带人
	# ── 虫/亡灵（第 3 行）──
	"beast_bat":        Vector2i(0, 3),   # 棕蝠
	"undead_ghost":     Vector2i(1, 3),   # 灰幽灵
	"beast_spider":     Vector2i(2, 3),   # 棕蜘蛛
	"beast_rat":        Vector2i(3, 3),   # 棕鼠
	"beast_spider_big": Vector2i(4, 3),   # 灰巨蛛
}

## 兜底格：表里查不到的类型用它，保证"永远画得出东西"
const FALLBACK_CELL := Vector2i(1, 0)

## 怪物原型 key（`MonsterDB` 条目的 `base_key` 字段）→ 精灵类型。
##
## **只映射真正走群体模拟的那三支**（`MonsterDB.SWARM_BASE_KEYS`）。
## 其余原型一律回退兜底格——它们目前根本不会进 `CrowdManager`
## （路由判据见 `room_controller._should_use_crowd`），提前给它们编映射
## 属于凭空猜测，等真要搬进核里时再按当时的策划稿定。
##
## 调试开关 `RoomController.CROWD_FORCE_SWARM` 会把所有基础怪强行送进核里，
## 那时它们会全部显示兜底格——这是可接受的：调试模式看的是数量与寻路，
## 不是长相。
const MONSTER_KIND := {
	"zombie":    "humanoid_villager",   # 缓慢近身杂兵
	"berserker": "humanoid_brute",      # 普通速度近身
	"hound":     "beast_wolf",          # 突进近战
}


## 取某类型的格坐标（查不到回退兜底格）
static func cell_of(kind: String) -> Vector2i:
	return CELLS.get(kind, FALLBACK_CELL)


## 怪物配置字典 → 精灵格坐标。
##
## 认的是 `base_key`（`MonsterDB` 写入的原型 key，如 "zombie"）。
## 拿不到 `base_key`（空 dict、老存档、调试造的假数据）时回退兜底格，
## **不报错**——视觉兜底不该打断战斗逻辑。
static func cell_for_monster(monster: Dictionary) -> Vector2i:
	var key := str(monster.get("base_key", ""))
	var kind := str(MONSTER_KIND.get(key, ""))
	if kind.is_empty():
		return FALLBACK_CELL
	return cell_of(kind)


## 怪物配置字典 → 归一化 UV 矩形（Vector4: u0, v0, u1, v1）
static func uv_rect_for_monster(monster: Dictionary) -> Vector4:
	return tile_uv_rect(cell_for_monster(monster))


## 格坐标 → 归一化 UV 矩形（Vector4: u0, v0, u1, v1）
##
## **内缩半像素**：与 AtlasDefs 同理，浮点采样会跨格边界。
## 本表虽然无格间隔，但格与格**紧邻**，不内缩会在边界处采到隔壁格的颜色
## （表现为角色边缘闪出相邻角色的颜色）。
##
## **不要在这里翻 V 轴**。烘焙产物是**顶行朝上**（直接照抄源图的行序，
## 第 0 行在 PNG 顶部），而 QuadMesh 的 UV.y 也是顶部为 1、底部为 0——
## 两者同向，直接映射即可。此前的烘焙把行序倒过来存，导致不加翻转就上下颠倒，
## 是烘焙的问题，已修；在这里补一次翻转只会把修好的又翻回去。
static func tile_uv_rect(cell: Vector2i) -> Vector4:
	const INSET := 0.5
	var x0 := float(cell.x * STEP_PX)
	var y0 := float(cell.y * STEP_PX)
	var u0 := (x0 + INSET) / float(SHEET_W)
	var v0 := (y0 + INSET) / float(SHEET_H)
	var u1 := (x0 + float(TILE_PX) - INSET) / float(SHEET_W)
	var v1 := (y0 + float(TILE_PX) - INSET) / float(SHEET_H)
	return Vector4(u0, v0, u1, v1)


## 表内所有格坐标（供测试校验不越界）
static func all_cells() -> Array:
	var out: Array = []
	for k in CELLS:
		out.append(CELLS[k])
	return out


## 加载精灵表贴图（取不到时返回 null，调用方需兜底）
static func sheet() -> Texture2D:
	if not ResourceLoader.exists(SHEET_PATH):
		return null
	return ResourceLoader.load(SHEET_PATH, "Texture2D",
		ResourceLoader.CACHE_MODE_REUSE) as Texture2D
