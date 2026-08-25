shader_type canvas_item;
render_mode blend_mix;

uniform float pixel_size : hint_range(1.0, 16.0, 1.0) = 4.0;
uniform int color_count : hint_range(4, 256) = 32;
uniform float outline_threshold : hint_range(0.0, 1.0, 0.01) = 0.15;

void fragment() {
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 uv = UV;
	// 像素化
	uv = floor(uv * tex_size / pixel_size) * pixel_size / tex_size;
	vec4 col = texture(TEXTURE, uv);
	// 限制调色板
	col.rgb = floor(col.rgb * float(color_count)) / float(color_count);
	// 简单轮廓检测
	vec2 off = vec2(pixel_size / tex_size.x, 0.0);
	float edge = abs(texture(TEXTURE, uv + off).a - texture(TEXTURE, uv - off).a);
	edge += abs(texture(TEXTURE, uv + off.yx).a - texture(TEXTURE, uv - off.yx).a);
	if (edge > outline_threshold && col.a < 0.5) {
		col.rgb = vec3(0.0);
		col.a = 1.0;
	}
	COLOR = col;
}
