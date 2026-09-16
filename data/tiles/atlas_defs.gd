class_name AtlasDefs
extends RefCounted
## 贴图图集定义 —— Kenney roguelike 图集的可用图块索引
##
## **本文件是贴图系统的唯一真相源**：哪些图集格可用作地砖/墙砖，
## 以及 9 层主题各用哪一块。
##
## 素材：`assets/roguelike-rpg-pack/Spritesheet/roguelikeSheet_transparent.png`
## 规格（见同目录 spritesheetInfo.txt）：**每格 16×16 像素，格间 1 像素间隔**。
##
## ⚠ **格间 1px 间隔是最大的坑**：UV 若按格边界直接采样，会渗到相邻格
## （纹理渗色——地板边缘出现隔壁图块的颜色）。换算时必须**向内缩半个像素**。
## 见 tilesheet_uv() 与 tile_uv_rect()。
##
## 图块索引的可靠性：本表里的格都是**程序化筛出来的无缝格**
## （左右边缘像素列相同、上下边缘像素列相同、且 100% 不透明）。
## 凭肉眼看图挑格不可靠——Kenney 图集里同一材质的九宫格里
## 只有中间那格能无缝平铺，四边/四角格都有描边装饰。

## 图集文件
const SHEET_PATH := "res://assets/roguelike-rpg-pack/Spritesheet/roguelikeSheet_transparent.png"
## 单格像素尺寸
const TILE_PX := 16
## 格间间隔（像素）
const GAP_PX := 1
## 每格实际步进 = 尺寸 + 间隔
const STEP_PX := TILE_PX + GAP_PX
## 图集整图尺寸（用于 UV 归一化）
const SHEET_W := 968
const SHEET_H := 526

## 9 层主题 → 地砖/墙砖格坐标（col, row）
##
## 选取原则：图集**只有明亮自然色**（草/石/沙/木/砖），没有暗色/紫/红材质。
## 故主题的色调差异仍由 FloorDefs 的 albedo_color 染色提供，
## 贴图只负责**纹理**。这样两层都拿到了：纹理来自图集，配色来自主题表。
## 若将来找到暗色主题图集，替换本表的 col/row 即可，代码不用动。
const FLOOR_TILES := {
	# 监牢入口：灰石砖
	"prison": Vector2i(25, 15),
	# 废弃矿道：土黄砖
	"mine": Vector2i(14, 13),
	# 古老墓穴：浅青灰砖
	"tomb": Vector2i(32, 15),
	# 地下沼泽：草绿
	"swamp": Vector2i(3, 16),
	# 符文熔炉：橙红
	"forge": Vector2i(11, 14),
	# 硫磺深渊：深橙
	"sulfur": Vector2i(3, 19),
	# 虚空回廊：蓝灰
	"void": Vector2i(28, 13),
	# 地狱王座：棕木
	"throne": Vector2i(36, 13),
	# 混沌裂隙：纯灰
	"rift": Vector2i(21, 13),
}

## 各主题的墙砖格（目前复用同材质的砖面格；与地砖区分开避免墙地同纹）
const WALL_TILES := {
	"prison": Vector2i(21, 13),
	"mine": Vector2i(18, 15),
	"tomb": Vector2i(25, 15),
	"swamp": Vector2i(11, 17),
	"forge": Vector2i(11, 20),
	"sulfur": Vector2i(20, 16),
	"void": Vector2i(29, 13),
	"throne": Vector2i(39, 15),
	"rift": Vector2i(22, 16),
}


## 取某层主题的地砖格
static func floor_tile(theme_id: String) -> Vector2i:
	return FLOOR_TILES.get(theme_id, Vector2i(25, 15))


## 取某层主题的墙砖格
static func wall_tile(theme_id: String) -> Vector2i:
	return WALL_TILES.get(theme_id, Vector2i(21, 13))


## 格坐标 → 该格在整图里的**归一化 UV 矩形**（Vector4: u0, v0, u1, v1）。
##
## **内缩半像素**：格间有 1px 间隔，且浮点采样会跨格边界。
## 只内缩半个像素就够——缩太多会让相邻地板格之间出现缝隙。
static func tile_uv_rect(cell: Vector2i) -> Vector4:
	var x0 := float(cell.x * STEP_PX)
	var y0 := float(cell.y * STEP_PX)
	# 内缩半像素（采样安全边）
	const INSET := 0.5
	var u0 := (x0 + INSET) / float(SHEET_W)
	var v0 := (y0 + INSET) / float(SHEET_H)
	var u1 := (x0 + float(TILE_PX) - INSET) / float(SHEET_W)
	var v1 := (y0 + float(TILE_PX) - INSET) / float(SHEET_H)
	return Vector4(u0, v0, u1, v1)


## 图块大小在世界坐标里的比例：一张 16px 图块铺满一个 CELL_SIZE 格。
## FloorBuilder 的 UV 是「每格 0→1」，所以这里只要给出格在整图里的 UV 范围，
## 由 builder 把 0→1 线性映射过去。
static func tile_uv_scale() -> float:
	return 1.0


## 某格的**平均亮度**（0~1），带缓存。
##
## **为什么需要它**：Godot 的最终颜色 = albedo_color × albedo_texture。
## 贴图格自身有亮度（灰砖 0.8、暗木 0.48…），若直接把主题色当 albedo_color，
## 结果会被贴图再乘一次 → 亮度失控（实测第 1 层地板从 0.30 涨到 0.95，
## 整个画面洗白）。
## 正确做法：albedo_color = 主题色 / 贴图亮度，让「主题色 × 贴图纹理变化」
## 的结果亮度回到主题色水平。
##
## 运行时从贴图算而非写死常量——换了 FLOOR_TILES 里的格，这里自动跟随，
## 不会出现「改了表忘了改常量」的过期数据。
static var _lum_cache := {}

static func tile_luminance(cell: Vector2i) -> float:
	var key := "%d_%d" % [cell.x, cell.y]
	if _lum_cache.has(key):
		return _lum_cache[key]
	var lum := 0.8   # 取不到贴图时的兜底（Kenney 图集的常见灰砖亮度）
	if ResourceLoader.exists(SHEET_PATH):
		var tex := ResourceLoader.load(SHEET_PATH, "Texture2D",
			ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if tex != null:
			lum = _sample_luminance(tex, cell)
	_lum_cache[key] = lum
	return lum


## 从贴图里量某格的平均亮度（只读 16×16 像素，开销可忽略且结果被缓存）
static func _sample_luminance(tex: Texture2D, cell: Vector2i) -> float:
	var img := tex.get_image()
	if img == null:
		return 0.8
	var x0 := cell.x * STEP_PX
	var y0 := cell.y * STEP_PX
	var sum := 0.0
	var n := 0
	for y in range(TILE_PX):
		for x in range(TILE_PX):
			var px := x0 + x
			var py := y0 + y
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			var c := img.get_pixel(px, py)
			if c.a < 0.5:
				continue
			sum += (c.r + c.g + c.b) / 3.0
			n += 1
	return (sum / float(n)) if n > 0 else 0.8


## 计算「让贴图乘完后回到主题色亮度」的 albedo_color。
## 供 FloorBuilder / WallBuilder 共用，避免两处各写一份公式再次跑偏。
static func tint_for(theme_color: Color, cell: Vector2i) -> Color:
	if theme_color.a <= 0.0:
		return Color.WHITE   # 无主题：贴图本色
	var target := (theme_color.r + theme_color.g + theme_color.b) / 3.0
	var tex_lum := maxf(tile_luminance(cell), 0.05)
	var f := clampf(target / tex_lum, 0.08, 2.0)
	return Color(f, f, f)


## 校验：本表里所有格坐标都在图集范围内（供测试）
static func all_cells() -> Array:
	var out: Array = []
	for k in FLOOR_TILES:
		out.append(FLOOR_TILES[k])
	for k in WALL_TILES:
		out.append(WALL_TILES[k])
	return out


## 图集列数/行数（供测试核对坐标不越界）
static func cols() -> int:
	return int((SHEET_W + GAP_PX) / float(STEP_PX))


static func rows() -> int:
	return int((SHEET_H + GAP_PX) / float(STEP_PX))
