class_name GlyphAtlasBaker
extends Node
## 字形图集烘焙器 —— GDScript 移植自 MassiveText 的 GlyphAtlasBaker.cs
## 用 SubViewport + Label 把所有字形烘焙到 4096² 图集纹理，
## 同时测量每个字形的墨迹宽度(advance)和左偏移(offset)，输出 advance_tex。
##
## 必须是 Node 子类：烘焙需 await process_frame 等待 SubViewport 渲染。
##
## 输出：{ atlas: ImageTexture, advance_tex: ImageTexture,
##         glyph_to_index: Dictionary, grid: int, cell: int, used_cells: int,
##         advances: Array, offsets: Array }

const ATLAS_SIZE := 4096
const CELL_CANDIDATES := [80, 64, 48, 40, 32]
const FRAMES_PER_CHUNK := 3


## 烘焙入口：传入文本字符串集合、字体、字号，返回结果字典
func bake(
	text_samples: Array, font: Font, font_size_px: int
) -> Dictionary:
	# 1. 收集去重字形（grapheme 簇）
	var glyphs := _collect_unique_glyphs(text_samples)
	if glyphs.is_empty():
		return {}

	# 2. 选格边长
	var cell := _choose_cell(font_size_px, glyphs.size())
	var grid := ATLAS_SIZE / cell
	var used_cells := glyphs.size()

	# 3. 烘焙图集 + 测 advance/offset
	var atlas_image := Image.create_empty(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color(0, 0, 0, 0))
	var advances: Array = []
	var offsets: Array = []
	var glyph_to_index := {}
	for i in glyphs.size():
		glyph_to_index[glyphs[i]] = i

	await _bake_glyphs_to_atlas(
		atlas_image, glyphs, font, font_size_px, cell, grid, advances, offsets
	)

	# 4. 生成 advance_tex（1×cells 的 RGBA8，R=advance×255, G=offset×255）
	var advance_image := Image.create_empty(used_cells, 1, false, Image.FORMAT_RGBA8)
	for i in used_cells:
		var adv: float = advances[i] if i < advances.size() else 0.55
		var ofs: float = offsets[i] if i < offsets.size() else 0.0
		adv = clamp(adv, 0.0, 1.0)
		ofs = clamp(ofs, 0.0, 1.0)
		advance_image.set_pixel(i, 0, Color(adv, ofs, 0.0, 1.0))

	return {
		"atlas": ImageTexture.create_from_image(atlas_image),
		"advance_tex": ImageTexture.create_from_image(advance_image),
		"glyph_to_index": glyph_to_index,
		"grid": grid,
		"cell": cell,
		"used_cells": used_cells,
		"advances": advances,
		"offsets": offsets,
	}


## 收集去重字形（处理代理对 emoji，简单字符直接取）
func _collect_unique_glyphs(text_samples: Array) -> Array:
	var result: Array = []
	var seen := {}
	for sample in text_samples:
		var clusters := _split_graphemes(str(sample))
		for c in clusters:
			if not seen.has(c):
				seen[c] = true
				result.append(c)
	return result


## 按 Unicode 码点拆分字形簇（处理代理对）
func _split_graphemes(s: String) -> Array:
	var result: Array = []
	var i := 0
	while i < s.length():
		var code := s.unicode_at(i)
		# 代理对高位：D800-DBFF → 与下一码点合并
		if code >= 0xD800 and code <= 0xDBFF and i + 1 < s.length():
			result.append(s.substr(i, 2))
			i += 2
		else:
			result.append(s.substr(i, 1))
			i += 1
	return result


## 选格边长：从大到小试，选第一个容量够且 cell >= 字号*1.15 的
func _choose_cell(font_size_px: int, glyph_count: int) -> int:
	for cell in CELL_CANDIDATES:
		var grid: int = ATLAS_SIZE / cell
		if grid * grid >= glyph_count and cell >= font_size_px * 1.15:
			return cell
	# 兜底用最小格
	return CELL_CANDIDATES[-1]


## 用 SubViewport + Label 逐字形烘焙到图集，同时测 advance/offset
func _bake_glyphs_to_atlas(
	atlas_image: Image, glyphs: Array, font: Font, font_size_px: int,
	cell: int, grid: int, advances: Array, offsets: Array
) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(cell, cell)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	for i in glyphs.size():
		var col: int = i % grid
		var row: int = i / grid
		var captured := await _render_glyph_to_viewport(
			glyphs[i], font, font_size_px, cell, vp
		)
		if captured == null:
			advances.append(0.55)
			offsets.append(0.0)
			continue
		var dest := Rect2i(col * cell, row * cell, cell, cell)
		atlas_image.blit_rect(captured, Rect2i(0, 0, cell, cell), Vector2i(dest.position))
		var measured := _measure_advance(captured, cell)
		advances.append(measured.advance)
		offsets.append(measured.offset)

	vp.queue_free()


## 在 SubViewport 里渲染单个字形，返回捕获的 Image
func _render_glyph_to_viewport(
	glyph: String, font: Font, font_size_px: int, cell: int, vp: SubViewport
) -> Image:
	# 清空旧子节点
	for child in vp.get_children():
		child.queue_free()

	var label := Label.new()
	label.text = glyph
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override(
		"font_size", mini(font_size_px, int(float(cell) * 0.9))
	)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(cell, cell)
	vp.add_child(label)

	# 等待渲染完成（SubViewport UPDATE_ALWAYS 需要帧）
	await get_tree().process_frame
	await get_tree().process_frame
	return vp.get_texture().get_image()


## 逐像素扫描 alpha 通道，测墨迹宽度和左偏移
func _measure_advance(img: Image, cell: int) -> Dictionary:
	var data := img.get_data()
	var min_x := cell
	var max_x := -1
	# data 是 RGBA8 PackedByteArray，每像素 4 字节，alpha 在 idx*4+3
	for y in cell:
		for x in cell:
			var idx := (y * cell + x) * 4 + 3
			if data[idx] > 0:
				if x < min_x:
					min_x = x
				if x > max_x:
					max_x = x
	if max_x < min_x:
		# 空字形（空格等）
		return {"advance": 0.55, "offset": 0.0}
	var advance := float(max_x - min_x + 1) / float(cell)
	var offset := float(min_x) / float(cell)
	return {"advance": advance, "offset": offset}
