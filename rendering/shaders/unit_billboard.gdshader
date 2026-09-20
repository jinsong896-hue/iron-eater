shader_type spatial;
// 单位 billboard —— 群体单位（`CrowdManager`）与投射物（`ProjectileManager`）
// 共用的 MultiMesh 实例着色器
//
// ## 两个管理器共用一支，靠 `use_instance_color` 分流
// 两者的 billboard 数学**逐字相同**（都从实例矩阵取缩放、绕 Y 轴朝相机、
// 顶点存单位尺寸），差别只有两处：
//   · 群体单位：从 `INSTANCE_CUSTOM` 取精灵格，贴角色图集
//   · 投射物：不采样图集，纯色；颜色走 `use_colors` 的 `COLOR`
// 复制成两支着色器会让这段 billboard 数学有两份真相，改一处漏一处——
// 而两边的缓冲布局本来就一样（都开一个实例通道 ⇒ stride 16）。
//
// ## 为什么不用 `toon.gdshader`
//   1. toon 是**受光**的（light() 里做色阶量化），而 billboard 只能绕 Y 轴转，
//      法线是算出来的假值、不随光照变化。走 toon 的话整批单位会被"点亮"，
//      在俯视相机下大面积顶到纯白——与 `toon.gdshader` 文件头警告的 rim 问题同源。
//      单位在画面里只占几个像素，本来就不指望它们参与光照分层，故这里 unshaded。
//   2. toon 的 `albedo_texture` 是**整张表**采样，本表要按实例取不同格。
//   3. 反壳描边（`model_outline.gdshader`）是往外扩一圈几何，对 billboard 平面
//      会扩出一整块实心方块，**不能挂**。单位的可读性靠脚下的接触阴影
//      （见 `contact_shadow`）和色阶对比，不靠描边。
//
// ## 不写 ALPHA
// 写了 ALPHA 会让整支着色器掉进透明队列（不写深度、排序开销），
// 而这里所有像素非全透即全实。抠图用 `discard`，等价于 alpha-scissor，
// 且保持不透明队列。与 `toon.gdshader` 文件头同一条纪律。
//
// ## 布局依赖（改动前先看这里）
// 本着色器**依赖实例缓冲是 stride 16 的布局**（12 个变换 float + 4 个通道 float）。
// 两边管理器都必须让 MultiMesh 恰好开**一个**实例通道：
//   · CrowdManager  → `use_custom_data = true`
//   · ProjectileManager → `use_colors = true`
// 开两个（或都不开）会让 stride 变成 20 或 12，`INSTANCE_CUSTOM` / `COLOR`
// 读到的是错位数据，表现为"精灵格全乱"或"子弹全黑"。
// Godot 不允许在已有实例时切换这两个开关，所以赋值顺序必须是
// 先开开关、再设 `instance_count`。

render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest;
// true = 贴图集（群体单位）；false = 纯色（投射物）
uniform bool use_instance_color = false;
// 贴图模式下的整体亮度——**本着色器不受光**，明暗全靠这个系数。
// 0.85 的来历：与 `toon_material.gd` 里 diffuse_strength=0.25 的标定同口径，
// 但单位只占几个像素，压太暗会糊成一团，故给到接近 1。
// 注意本项目的 WorldEnvironment 开了 ACES tonemap，亮度不是线性函数，
// 要调请实测取样，别按比例算（同 toon.gdshader 的告诫）。
uniform float brightness : hint_range(0.0, 2.0) = 0.85;
// 受击白闪 / 元素染色。按需改；默认黑 = 不发光。
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
// 接触阴影：精灵自身下半部压暗的强度与高度占比。
// 做进精灵里而不是另开一个阴影实例，是因为 MultiMesh 每实例只有一条
// transform + 一条通道，加阴影要么翻倍实例数、要么每帧在 GDScript 里
// 重算一份 buffer（2048 单位下光这份开销就吃掉帧预算）。
uniform float contact_shadow : hint_range(0.0, 1.0) = 0.35;
uniform float contact_shadow_height : hint_range(0.0, 0.5) = 0.22;

varying vec4 v_uv_rect;
varying vec4 v_color;

void vertex() {
	// ① 从实例矩阵取缩放。MultiMesh 只写对角（m[0]/m[5]/m[10]）与末列位置，
	//    不写旋转，故列向量长度即缩放。长度恒为正——**原地旋转 180° 的实例
	//    在此被翻正**，这正是我们要的（精灵不该倒着画）。
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	// 死单位：核把三轴缩放全写 0（`crowd_sim.cpp` / `projectile_core.cpp`
	// 的未存活分支）。提前把顶点塌掉，避免出现一个"位于世界原点的退化三角形"。
	if (sx <= 0.0001) {
		POSITION = vec4(0.0);
		v_uv_rect = vec4(0.0);
		v_color = vec4(0.0);
	} else {
		// ② 绕 Y 轴朝向相机。取视图矩阵的右向量并抹掉 y 分量，
		//    这样单位永远正面朝屏幕，但不会跟着相机俯仰角翻倒。
		vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
		vec3 up = vec3(0.0, 1.0, 0.0);
		// 顶点存的是**单位** QuadMesh（1×1），尺寸全由实例缩放决定——
		// 与核写进渲染缓冲的 `scale_of(i)` / `base_scale` 是同一份数据，
		// 别在这里再乘一次。
		vec3 pos = right * (VERTEX.x * sx) + up * (VERTEX.y * sy);
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz + pos, 1.0);

		// ③ 每实例的通道数据。两种模式取不同的量，但都落在缓冲末尾 4 个 float。
		v_uv_rect = INSTANCE_CUSTOM;
		v_color = COLOR;
		if (v_uv_rect.z - v_uv_rect.x <= 0.0 || v_uv_rect.w - v_uv_rect.y <= 0.0) {
			// 没写精灵格（非 MultiMesh 场景、或纯色模式）：回退整张表，
			// 至少能看出"有东西画出来了"而不是一片空白。
			v_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
		}
	}
}

void fragment() {
	if (use_instance_color) {
		// 纯色模式（投射物）：不做抠图，整个四边形都画。
		// 圆润感靠四边形本身够小 + 像素化后处理，不值得为它单独烤一张贴图。
		ALBEDO = v_color.rgb * brightness;
	} else {
		vec2 uv = mix(v_uv_rect.xy, v_uv_rect.zw, UV);
		vec4 tex = texture(albedo_texture, uv);
		// 抠图残留的半透明边：直接丢弃，否则会画出精灵外的毛边
		if (tex.a <= 0.5) {
			discard;
		}
		// 接触阴影：越靠精灵底部越暗，给俯视相机一个"站在地上"的锚点
		float shade = 1.0 - contact_shadow * smoothstep(1.0 - contact_shadow_height, 1.0, UV.y);
		ALBEDO = tex.rgb * brightness * shade;
	}
	EMISSION = emission_color.rgb * emission_energy;
}
