// =============================================================================
// TextAtlas — 海量文本 MultiMeshInstance2D 着色器 (每实例渲染一小段字符串, 单 draw call)
// =============================================================================
// 输入数据:
//   - text_atlas   字形图集 (烘焙, 均匀网格, 格号 = 字形索引)
//   - string_tex   每实例字符串的字形序列 (RGBA8, uint16 小端, 每 texel 2 字形)
//   - advance_tex  每字形墨迹宽度/左偏移 (格分数, 烘焙时测得)
//   - cum_tex      每字符「列右边界」累积列宽 (R32F float, 格分数)
// fragment 定位: 累积列宽单调递增 → 二分查找当前字符列 (O(log len) 次采样, 串长不限)。
// V 轴: 图集上传 GPU 时垂直翻转, 格内采样反向保持字形正立。
// 特效 (默认关闭, 开启不增加 CPU 负担): per_glyph_tint / anim / burst。
// =============================================================================

shader_type canvas_item;

const int MAX_TEXT_STYLES = 8;
uniform sampler2D text_atlas : filter_nearest;
uniform float atlas_grid = 64.0;      // 每行格数 (= 每列格数, 图集正方形网格)
uniform float atlas_cell_px = 80.0;   // 格边长 (px) — 采样用真实 texel 定位
uniform float atlas_size = 4096.0;    // 图集纹理宽高 (px)
uniform vec4 text_tints[MAX_TEXT_STYLES];
uniform sampler2D string_tex : filter_nearest;
uniform sampler2D cum_tex : filter_nearest;   // R32F: 每字符 1 texel 存累积列宽 (格分数)
uniform float string_tex_cols = 4096.0;      // 打包纹理宽
uniform float string_tex_rows = 98.0;        // 打包纹理高
uniform float max_string_len = 16.0;
uniform float cum_tex_cols = 4096.0;         // cum_tex 宽 (= string_tex_cols)
uniform float cum_tex_rows = 98.0;           // cum_tex 高 (每字符 1 texel)
uniform sampler2D advance_tex : filter_nearest;
uniform float advance_tex_cols = 4096.0;     // 图集格数

// —— 特效开关 (C# 侧 UI 控制, 默认 0 = 保持静态行为) ——
uniform float per_glyph_tint = 0.0;   // 1 = 每种字形独立取色 (tints[字形 % 8])
uniform float anim_enabled = 0.0;     // 1 = TIME 动态动画 (波浪位移 + 颜色流动)
uniform float anim_speed = 2.0;       // 动画速度系数
uniform float anim_strength = 0.06;   // 波浪位移强度
uniform float burst_enabled = 0.0;    // 1 = 喷发动画 (从原点随机初速喷出, 重力回落)
uniform float burst_speed = 0.0417;   // 每秒周期数 (1/24 → 周期 24s)
uniform float burst_vx = 125.0;       // 水平初速最大 (±均匀随机, 世界/秒)
uniform float burst_vy_min = 125.0;   // 垂直初速下限 (向上, 世界/秒)
uniform float burst_vy_max = 325.0;   // 垂直初速上限 (向上, 世界/秒)
uniform float burst_gravity = 36.75;  // 重力 (世界/秒²)
uniform float burst_spawn_radius = 2.0;  // 起点微散布
uniform float burst_quad_scale = 0.7;    // quad 缩放 (防瞬间重叠峰值)

varying vec4 instance_color;
varying float instance_id;
varying vec2 instance_uv;
varying float burst_t;                   // 喷发相位 (0..1)

// HSV ↔ RGB (用于动态色相流动)
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void vertex() {
	instance_color = COLOR;
	instance_id = float(INSTANCE_ID);
	instance_uv = UV;
	burst_t = 0.0;
	if (anim_enabled > 0.5) {
		float ph = fract(instance_id * 0.61803399);
		VERTEX.y += sin(TIME * anim_speed * 1.5 + ph * 6.28318) * anim_strength;
	}
	if (burst_enabled > 0.5) {
		// 喷发: 每实例从原点以随机初速喷出 (水平±vx, 垂直向上 vy), 重力下弧形回落
		VERTEX.xy *= burst_quad_scale;
		float ph = fract(instance_id * 0.61803399);
		float t = fract(TIME * burst_speed + ph);        // 周期相位 0..1 (周期 = 1/burst_speed 秒)
		burst_t = t;
		float tsec = t / burst_speed;                    // 实际飞行秒数
		// vx/vy 用两条独立随机流 (不同无理常数), 避免同源相关 → 斜向成团
		float rvx = fract(instance_id * 0.7548776662);
		float rvy = fract(instance_id * 0.5698402909);
		vec2 vel = vec2(
			(rvx - 0.5) * 2.0 * burst_vx,
			-(burst_vy_min + rvy * (burst_vy_max - burst_vy_min)));
		vec2 spawn = (vec2(fract(instance_id * 0.41342729), fract(instance_id * 0.9134577)) - 0.5) * 2.0 * burst_spawn_radius;
		vec2 d = spawn + vel * tsec + 0.5 * vec2(0.0, burst_gravity) * tsec * tsec; // v·t + ½g·t²
		mat2 M = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);    // 实例 2x2 缩放/旋转
		VERTEX.xy += inverse(M) * (d - MODEL_MATRIX[3].xy);       // 世界位移 → 局部
	}
}

// 读第 k 个字符的字形索引 (uint16 小端)
float glyph_of(int k) {
	// 与 C# 打包完全一致: pairIdx = instance_id*maxLen + k; texel = pairIdx/2, 通道按 pairIdx 奇偶
	// (串长可为奇数, 不能用 instance_id*(maxLen/2) 或 k%2 — 奇数串长会错位)
	int pairIdx = int(instance_id) * int(max_string_len) + k;
	int texel = pairIdx / 2;
	int tx = texel % int(string_tex_cols);
	int ty = texel / int(string_tex_cols);
	vec2 tc = vec2((float(tx) + 0.5) / string_tex_cols,
	               (float(ty) + 0.5) / string_tex_rows);
	vec4 tb = texture(string_tex, tc);
	float lo, hi;
	if ((pairIdx & 1) == 0) { lo = tb.r; hi = tb.g; }
	else                    { lo = tb.b; hi = tb.a; }
	return float(int(lo * 255.0 + 0.5) + (int(hi * 255.0 + 0.5) << 8));
}

// 读第 k 个字符的「列右边界」累积列宽 (格分数, R32F)
// 必须用浮点: uint16 只能表示 ≤1.0 格, 长串累积列宽会溢出回绕 → 定位错乱。
float cum_of(int k) {
	int texel = int(instance_id) * int(max_string_len) + k;   // 每字符 1 texel
	int tx = texel % int(cum_tex_cols);
	int ty = texel / int(cum_tex_cols);
	return texture(cum_tex, vec2((float(tx) + 0.5) / cum_tex_cols,
	                             (float(ty) + 0.5) / cum_tex_rows)).r;
}

// 字形度量: r=墨迹宽度/格, g=墨迹左偏移/格 (烘焙测得)
vec2 ao_of(float g) {
	return texture(advance_tex, vec2((g + 0.5) / advance_tex_cols, 0.5)).rg;
}

void fragment() {
	int len = int(instance_color.r * 255.0 + 0.5);
	if (len <= 0) { discard; }
	if (burst_enabled > 0.5 && burst_t > 0.94) { discard; }   // 周期末尾淡出 (落出屏幕后消失)
	int style = clamp(int(instance_color.b * 255.0 + 0.5), 0, MAX_TEXT_STYLES - 1);
	float total = max(cum_of(len - 1), 1e-4);                 // 总列宽 = 末字符累积值

	// 二分定位当前字符列: 找第一个 cum[k] > x (累积列宽单调递增 → O(log len) 次采样)
	float x = clamp(instance_uv.x * total, 0.0, max(total - 1e-4, 0.0));
	int lo = 0;
	int hi = len - 1;
	while (lo < hi) {
		int mid = (lo + hi) >> 1;
		if (cum_of(mid) > x) { hi = mid; } else { lo = mid + 1; }
	}
	int colK = lo;
	float prev = (colK > 0) ? cum_of(colK - 1) : 0.0;
	float p = x - prev;                       // 列内位置 [0, 列宽]

	float glyph = glyph_of(colK);
	vec2 ao = ao_of(glyph);
	float ink = max(ao.r, 0.25);
	if (p >= ink) { discard; }                // 间距区域 → 透明

	int col = int(glyph) % int(atlas_grid);
	int row = int(glyph) / int(atlas_grid);
	// 采样用真实格尺寸: 格 col 从 col×cell_px 开始, 墨迹偏移 (ao.g+p) 也是 cell_px 的分数
	vec2 uv = vec2(
		(float(col) * atlas_cell_px + (ao.g + p) * atlas_cell_px) / atlas_size,
		(float(row) * atlas_cell_px + (1.0 - instance_uv.y) * atlas_cell_px) / atlas_size);
	vec4 tex = texture(text_atlas, uv);

	// 取色: 每字染色 → 按字形索引取调色板色 (同字同色); 否则 → 实例样式色
	vec3 tint = per_glyph_tint > 0.5
		? text_tints[int(glyph) % MAX_TEXT_STYLES].rgb
		: text_tints[style].rgb;
	float alpha = tex.a;

	// 喷发: 起点短淡入 (防源头亮斑) + 周期末尾淡出
	if (burst_enabled > 0.5) {
		alpha *= smoothstep(0.0, 0.03, burst_t) * (1.0 - smoothstep(0.88, 0.94, burst_t));
	}

	// 动态: 色相缓慢流动 + 饱和度/亮度呼吸 (按字形错相)
	if (anim_enabled > 0.5) {
		float ph = fract(glyph * 0.61803399);
		vec3 hsv = rgb2hsv(tint);
		hsv.x = fract(hsv.x + TIME * anim_speed * 0.05 + ph * 0.25);
		hsv.y = clamp(hsv.y * (0.85 + 0.3 * sin(TIME * anim_speed * 0.8 + ph * 6.28318)), 0.0, 1.0);
		hsv.z = hsv.z * (0.75 + 0.35 * sin(TIME * anim_speed * 1.2 + ph * 6.28318));
		tint = hsv2rgb(hsv);
	}
	COLOR = vec4(tex.rgb * tint, alpha * instance_color.a);
}
