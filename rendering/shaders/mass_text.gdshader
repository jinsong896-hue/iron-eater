// =============================================================================
// MassText — 海量文本渲染着色器（每个字形一个实例，单 draw call）
// =============================================================================
//
// ## 与旧 TextAtlas.gdshader 的关键区别
//
// 旧方案为了支持"任意长度字符串"，用了 string_tex（字形序列）+
// cum_tex（累积列宽）+ 片元里二分查找定位字符列 + advance_tex（墨迹测量）
// ——四层间接，任何一环错都不出字，且 headless 读不到像素无法定位。
// 它的历史是"逐环节静态检查全部正确，实机就是不出字"。
//
// 新方案把复杂度从 GPU 挪到 CPU：
//   · **每个字形 = 一个实例**（不是一个字符串一个实例）
//   · 字形索引、出生时间、横向偏移、字号缩放全部预计算好塞进 INSTANCE_CUSTOM
//   · 着色器只做三件事：按 AGE 上浮、按 UV 采样图集、按 AGE 淡出
//
// 代价是实例数 = 文本数 × 平均字数（4000 字文本 ≈ 16000 实例），
// 但 MultiMesh 单 draw call 扛得住，且**没有跨实例依赖**——
// 每个实例自包含，不会出现"某处索引算错导致整片不出字"。
//
// ## INSTANCE_CUSTOM 编码
//   x = 图集格号（字形索引）
//   y = 出生时间（秒，取自 TIME 基准）
//   z = 横向偏移（像素，CPU 预算的累积 advance）
//   w = 字号缩放（相对烘焙字号的倍数）
//
// ## 上浮动画完全在 GPU
// CPU 只在**生成时**写一次实例数据，之后每帧零写入——
// 上浮位移由 `-age * rise_speed` 在 vertex 里算。
// 这是"几千个文本"能跑起来的关键：CPU 每帧不碰任何实例。

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D atlas : filter_nearest;
uniform vec2 atlas_grid = vec2(10.0, 10.0);   // 图集网格（列, 行）
uniform float lifetime = 1.0;                  // 存活时长（秒）
uniform float rise_speed = 60.0;               // 上浮速度（像素/秒）
uniform float fade_start = 0.65;               // 开始淡出的时间比例
// 当前时间（秒）——**由 GDScript 每帧写入，不要用 TIME**。
//
// 踩过的坑：内置 `TIME` 与 GDScript 的 `Time.get_ticks_msec()` **不是同一个
// 时钟**（实测同时刻分别为 ~1.0s 与 ~3.9s）。用它算 age 会得到负数，
// 片元全部 discard —— 表现为"一切数据都对但就是不出字"，
// 正是旧 TextAtlas 方案当初查不出的那种症状。
// 每帧写一个 uniform 的成本可忽略（不是每实例写）。
uniform float now_time = 0.0;

varying vec4 inst_custom;
varying vec4 inst_color;

void vertex() {
	inst_custom = INSTANCE_CUSTOM;
	inst_color = COLOR;
	float age = now_time - inst_custom.y;
	// **过期实例在顶点阶段就塌缩成退化三角形**（面积 0），
	// 光栅化器会直接跳过它，完全不产生片元。
	//
	// 只在 fragment 里 discard 是不够的：四边形仍会被光栅化，
	// 只是每个片元跑完 shader 才丢弃——8000 个 64×64 的四边形
	// 就是 3200 万片元的无效填充。
	//
	// 注意：GLSL 的 vertex 里**不能 return**（编译报错），必须用 if/else。
	if (age < 0.0 || age > lifetime) {
		VERTEX = vec2(0.0);
	} else {
		// 局部空间：四边形按字号缩放，再叠加"字符横向偏移 + 上浮位移"。
		// 实例变换本身只做平移（锚点），缩放放在这里，避免二者互相干扰。
		VERTEX = VERTEX * inst_custom.w + vec2(inst_custom.z, -age * rise_speed);
	}
}

void fragment() {
	float age = now_time - inst_custom.y;
	// 超出存活期直接丢弃（CPU 无需回收，实例槽位靠"过期后复用"）
	if (age < 0.0 || age > lifetime) {
		discard;
	}
	int gi = int(inst_custom.x + 0.5);
	if (gi < 0) {
		discard;
	}
	int cols = int(atlas_grid.x);
	int col = gi % cols;
	int row = gi / cols;
	// **V 轴要翻转**：canvas_item 的 UV.y 在四边形底部为 0、顶部为 1
	//（与"图集里 V=0 在顶部"相反）。不翻转的话字形会上下倒立——
	// 实测把渲染结果打成 ASCII 才看出来（"7" 的横杠跑到了下方）。
	vec2 uv = (vec2(float(col), float(row)) + vec2(UV.x, 1.0 - UV.y)) / atlas_grid;
	vec4 t = texture(atlas, uv);
	if (t.a < 0.02) {
		discard;   // 空格/字形外区域
	}
	float fade = 1.0 - smoothstep(fade_start, 1.0, age / lifetime);
	COLOR = vec4(t.rgb * inst_color.rgb, t.a * inst_color.a * fade);
}
