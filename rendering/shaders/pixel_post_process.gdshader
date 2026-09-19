shader_type spatial;
// 屏幕空间描边后处理 —— HD-2D
//
// 血统：Kody King 的 three.js 像素后处理（normal + depth 边缘检测），
// 经 `房间参考/着色器/` 里两份 MIT 实现转写：
//   - 3DPixelArt_Tutorial/Shaders/edge_detection.gdshader（Eduardo Schildt）
//   - Godot-3d-pixelart-demo-master/pixelart_stylizer.gdshader（Leo Peltola）
//
// **它只画描边，不负责像素化。** 颗粒感来自 3D 世界按 1/pixel_scale 渲染
// 再最近邻放大，见 rendering/effects/pixel_renderer.gd。不要把
// `floor(SCREEN_UV * n)` 那套全屏 pixel shader 塞进来——`ai/hd2d.md`
// 第二十五条明确不推荐：会连带糊掉 UI、文字、景深、辉光与粒子。
//
// 全屏 quad 由 pixel_renderer.gd 挂在相机下。顶点着色器把 POSITION 直接
// 写成 NDC 常量（模型矩阵不参与），故网格**必须**开 flip_faces，否则背面
// 剔除会把整个 quad 剔掉——这正是它此前「开关都看不出区别」的原因。
//
// 注意此处**不能**写 `unshaded`：那会让 light() 永不执行，
// 使 useLighting 这个开关变成摆设。
//
// **必须关掉深度测试**（depth_test_disabled）。顶点着色器把 POSITION 钉在
// NDC 的 z=1.0（远平面），若还参与深度测试，这个 quad 只在「场景没画过东西」
// 的像素上存活——也就是纯背景。地板、墙、角色这些真正需要描边的地方
// 深度更近，quad 整片被裁掉，描边自然一条都画不出来。同理需要 blend_mix
// 让它走透明队列、排在不透明几何之后，否则读到的 SCREEN_TEXTURE 还是空的。
render_mode blend_mix, depth_test_disabled, depth_draw_never, specular_disabled, ambient_light_disabled, shadows_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;
uniform sampler2D NORMAL_TEXTURE : hint_normal_roughness_texture, filter_nearest;

uniform float lightIntensity : hint_range(0.0, 3.0) = 1.25;
uniform float lineAlpha : hint_range(0.0, 1.0) = 0.7;
uniform float lineHighlight : hint_range(0.0, 1.0) = 0.2;
uniform float lineShadow : hint_range(0.0, 1.0) = 0.55;
// true  = 用场景法线缓冲重新打光（参考项目里的平面着色）
// false = 原样透传画面，只压边；场景自身的 WorldEnvironment 光照/雾/辉光全保留
uniform bool useLighting = false;

varying vec2 screenUV;
varying float lineMask;


// 由深度缓冲反推视空间线性深度。
// 源码是「advanced postprocessing」文档里的标准写法。
float GetLinearDepth(vec2 sUV, sampler2D depthTexture, mat4 invProjectionMat, float mask){
	float depth = texture(depthTexture, sUV).x * mask;
	vec3 ndc = vec3(sUV * 2.0 - 1.0, depth);
	vec4 view = invProjectionMat * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}

// 取法线缓冲的法线。
//
// **用 vec3 乘法而不是 step/if 分支**：原实现写作
// `normal * 2.0 - 1.0 * mask`，对 mask=0 会得到 `2n` 而不是中性值，
// 在「逐像素编译分支」的驱动上还会让整个 loop 走两条路径。
// 这里显式做 mix，mask=0 时得到 (0,0,1)——法线比较的中性结果，
// 正是 GetLinearDepth 里 `depth * mask` 想要的语义。
vec3 GetNormal(vec2 uv, sampler2D normalTexture, float mask){
	vec3 n = texture(normalTexture, uv).rgb * 2.0 - 1.0;
	return mix(vec3(0.0, 0.0, 1.0), n, mask);
}

float NormalEdgeIndicator(vec3 normalEdgeBias, vec3 normal, vec3 neighborNormal, float depthDifference){
	float normalDifference = dot(normal - neighborNormal, normalEdgeBias);
	float normalIndicator = clamp(smoothstep(-.01, .01, normalDifference), 0.0, 1.0);
	float depthIndicator = clamp(sign(depthDifference * .25 + .0025), 0.0, 1.0);
	return (1.0 - dot(normal, neighborNormal)) * depthIndicator * normalIndicator;
}

void vertex(){
	// 直接吐 NDC：quad 永远铺满视口，与相机位置/朝向无关
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 texelSize = 1.0 / VIEWPORT_SIZE.xy;
	screenUV = SCREEN_UV;

	// 用 alpha 通道（屏幕粗糙度）屏蔽不需要描边的物体：
	// 粗糙度恰为 0 的物件不参与描边
	float outlineMask = texture(NORMAL_TEXTURE, SCREEN_UV).a;
	outlineMask = ceil(outlineMask);

	// ---- 深度边 ----
	// **必须写开四个邻居的常量索引**：原先那个
	// `for (int i = 0; i < UVOffsets.length(); i++)` 里，`UVOffsets` 是
	// 函数内局部数组、`length()` 在 GLES3/GLSL 下不保证常量折叠，
	// 整个循环连同里面的深度反投影会退化成逐像素分支。
	float depthDifference = 0.0;
	float invDepthDifference = 0.5;
	float depth = GetLinearDepth(SCREEN_UV, DEPTH_TEXTURE, INV_PROJECTION_MATRIX, outlineMask);

	float dUp    = GetLinearDepth(SCREEN_UV + vec2(0.0, -1.0) * texelSize, DEPTH_TEXTURE, INV_PROJECTION_MATRIX, outlineMask);
	float dDown  = GetLinearDepth(SCREEN_UV + vec2(0.0,  1.0) * texelSize, DEPTH_TEXTURE, INV_PROJECTION_MATRIX, outlineMask);
	float dRight = GetLinearDepth(SCREEN_UV + vec2(1.0,  0.0) * texelSize, DEPTH_TEXTURE, INV_PROJECTION_MATRIX, outlineMask);
	float dLeft  = GetLinearDepth(SCREEN_UV + vec2(-1.0, 0.0) * texelSize, DEPTH_TEXTURE, INV_PROJECTION_MATRIX, outlineMask);

	depthDifference += clamp(dUp - depth, 0.0, 1.0);
	depthDifference += clamp(dDown - depth, 0.0, 1.0);
	depthDifference += clamp(dRight - depth, 0.0, 1.0);
	depthDifference += clamp(dLeft - depth, 0.0, 1.0);
	invDepthDifference += (depth - dUp) + (depth - dDown) + (depth - dRight) + (depth - dLeft);
	invDepthDifference = clamp(invDepthDifference, 0.0, 1.0);
	invDepthDifference = clamp(smoothstep(0.9, 0.9, invDepthDifference) * 10.0, 0.0, 1.0);
	depthDifference = smoothstep(0.25, 0.3, depthDifference);

	// ---- 法线边 ----
	float normalDifference = 0.0;
	vec3 normalEdgeBias = vec3(1.0, 1.0, 1.0);
	vec3 normal = GetNormal(SCREEN_UV, NORMAL_TEXTURE, outlineMask);

	normalDifference += NormalEdgeIndicator(normalEdgeBias, normal,
		GetNormal(SCREEN_UV + vec2(0.0, -1.0) * texelSize, NORMAL_TEXTURE, outlineMask), depthDifference);
	normalDifference += NormalEdgeIndicator(normalEdgeBias, normal,
		GetNormal(SCREEN_UV + vec2(0.0,  1.0) * texelSize, NORMAL_TEXTURE, outlineMask), depthDifference);
	normalDifference += NormalEdgeIndicator(normalEdgeBias, normal,
		GetNormal(SCREEN_UV + vec2(1.0,  0.0) * texelSize, NORMAL_TEXTURE, outlineMask), depthDifference);
	normalDifference += NormalEdgeIndicator(normalEdgeBias, normal,
		GetNormal(SCREEN_UV + vec2(-1.0, 0.0) * texelSize, NORMAL_TEXTURE, outlineMask), depthDifference);

	normalDifference = smoothstep(0.2, 0.2, normalDifference);
	normalDifference = clamp(normalDifference - invDepthDifference, 0.0, 1.0);

	// 画面本身原样透传——场景光照/雾/辉光都在 SCREEN_TEXTURE 里
	ALBEDO = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	lineMask = clamp(0.1, lineAlpha, (depthDifference + normalDifference * 5.0));

	if (!useLighting){
		// 不重打光时，用亮度调制代替描边色：法线边提亮、深度边压暗
		ALBEDO += clamp((normalDifference - depthDifference), 0.0, 1.0) * lineHighlight;
		ALBEDO -= ALBEDO * depthDifference * lineShadow;
	}
}

void light(){
	if (useLighting){
		vec4 normal = texture(NORMAL_TEXTURE, screenUV);
		normal = normal * 2.0 - 1.0;

		float dotNL = dot(normal.rgb, LIGHT);
		dotNL = pow(dotNL, 2.5);
		dotNL = clamp(dotNL, 0.0, 1.0);

		if(LIGHT_IS_DIRECTIONAL)
			DIFFUSE_LIGHT += mix(vec3(1.0), dotNL * LIGHT_COLOR * lightIntensity, lineMask);
	}
	else
		DIFFUSE_LIGHT = vec3(1.0);
}
