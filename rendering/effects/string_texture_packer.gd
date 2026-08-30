class_name StringTexturePacker
extends RefCounted
## 字符串打包器 —— 把多段字符串打包成 MassiveText shader 用的辅助纹理
## string_tex: RGBA8, 每 texel 存 2 个字形索引（uint16 小端），R/G 存偶数, B/A 存奇数
## cum_tex: R32F, 每字符 1 texel, 存该字符列右边界累积值（格分数）
##
## 与 GlyphAtlasBaker 配套使用

const STRING_TEX_WIDTH := 4096


## 打包入口：传入字符串数组、glyph_to_index 映射、advances/offsets、max_string_len
## 返回 { string_tex: ImageTexture, cum_tex: ImageTexture }
static func pack(
	strings: Array, glyph_to_index: Dictionary, advances: Array,
	max_string_len: int
) -> Dictionary:
	var count := strings.size()
	if count == 0 or max_string_len <= 0:
		return {}

	# 1. 把每个字符串转成字形索引数组
	var all_glyph_indices: Array = []
	for s in strings:
		var indices := _string_to_indices(str(s), glyph_to_index, max_string_len)
		all_glyph_indices.append(indices)

	# 2. 生成 string_tex（RGBA8，每 texel 2 字形小端）
	var texels_per_instance := maxi(1, int(ceil(float(max_string_len) / 2.0)))
	var total_texels := count * texels_per_instance
	var rows := maxi(1, int(ceil(float(total_texels) / float(STRING_TEX_WIDTH))))
	var string_data := PackedByteArray()
	string_data.resize(STRING_TEX_WIDTH * rows * 4)
	string_data.fill(0)

	for i in count:
		var indices: Array = all_glyph_indices[i]
		for k in max_string_len:
			if k >= indices.size():
				break
			var glyph_idx: int = indices[k]
			var pair_idx := i * max_string_len + k
			var texel := pair_idx / 2
			var tx := texel % STRING_TEX_WIDTH
			var ty := texel / STRING_TEX_WIDTH
			var base := (ty * STRING_TEX_WIDTH + tx) * 4
			var lo := glyph_idx & 0xFF
			var hi := (glyph_idx >> 8) & 0xFF
			if (pair_idx & 1) == 0:
				# 偶数：R=lo, G=hi
				string_data[base + 0] = lo
				string_data[base + 1] = hi
			else:
				# 奇数：B=lo, A=hi
				string_data[base + 2] = lo
				string_data[base + 3] = hi

	var string_image := Image.create_from_data(
		STRING_TEX_WIDTH, rows, false, Image.FORMAT_RGBA8, string_data
	)

	# 3. 生成 cum_tex（R32F，每字符 1 texel，累积列宽）
	var cum_total := count * max_string_len
	var cum_rows := maxi(1, int(ceil(float(cum_total) / float(STRING_TEX_WIDTH))))
	var cum_data := PackedByteArray()
	cum_data.resize(STRING_TEX_WIDTH * cum_rows * 4)

	for i in count:
		var indices: Array = all_glyph_indices[i]
		var cum := 0.0
		for k in max_string_len:
			var adv := 0.55  # 默认空字形
			if k < indices.size():
				var gidx: int = indices[k]
				if gidx < advances.size():
					var raw: float = advances[gidx]
					# 量化与 shader 一致
					adv = max(max(round(raw * 255.0) / 255.0, 0.25), 0.05)
			cum += adv
			var texel := i * max_string_len + k
			var tx := texel % STRING_TEX_WIDTH
			var ty := texel / STRING_TEX_WIDTH
			var base := (ty * STRING_TEX_WIDTH + tx) * 4
			# 写 float 小端
			cum_data.encode_float(base, cum)

	var cum_image := Image.create_from_data(
		STRING_TEX_WIDTH, cum_rows, false, Image.FORMAT_RF, cum_data
	)

	return {
		"string_tex": ImageTexture.create_from_image(string_image),
		"cum_tex": ImageTexture.create_from_image(cum_image),
		"rows": rows,
		"cum_rows": cum_rows,
	}


## 字符串 → 字形索引数组（截断到 max_len）
static func _string_to_indices(
	s: String, glyph_to_index: Dictionary, max_len: int
) -> Array:
	var result: Array = []
	var i := 0
	while i < s.length() and result.size() < max_len:
		var code := s.unicode_at(i)
		var glyph: String
		if code >= 0xD800 and code <= 0xDBFF and i + 1 < s.length():
			glyph = s.substr(i, 2)
			i += 2
		else:
			glyph = s.substr(i, 1)
			i += 1
		if glyph_to_index.has(glyph):
			result.append(int(glyph_to_index[glyph]))
		else:
			result.append(0)  # 未知字符用第 0 个字形兜底
	return result
