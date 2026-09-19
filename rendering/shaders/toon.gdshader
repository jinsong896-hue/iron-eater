shader_type spatial;
// 卡通渲染（cel / toon）——《噬铁者》角色 / 怪物 / 场景的统一材质
//
// 血统：`房间参考/着色器/FlexibleToonShaderGD-main/addons/flexible_toon_shader/
// flexible_toon.shader`（MIT，作者 Simon Trichereau）。相对原版有四处适配：
//   1. 原版靠「未赋值的 sampler2D 返回白色」来支持无贴图场景；Godot 4 不保证
//      这个行为，故加 `use_albedo_texture` 显式开关，关闭时完全跳过采样
//   2. 原版 `use_borders` 画的是**色块之间的分界暗线**，不是模型外轮廓。
//      模型轮廓由 next_pass 上的反壳描边负责（model_outline.gdshader）；
//      墙 / 地板的接缝暗线由屏幕空间后处理负责（pixel_post_process.gdshader）。
//      三条通道各管一段，别互相顶替
//   3. 加 `emission_color` / `emission_energy`：受击白闪、毒怪绿光、宝箱微光
//      原先用 StandardMaterial3D.emission，换到这支着色器后需要等价出口
//   4. 去掉原版的 `specular_map` / `ramp` 贴图采样（本项目无对应贴图），
//      改为纯参数控制，行为等价
//
// **不要在这里写 `unshaded`**：那会让 light() 永不执行，整套卡通分层失效。
//
// 半透明**不在这里做**：写 ALPHA 会让整支着色器掉进透明队列（不写深度），
// 既拖慢场景几何，又会破坏屏幕空间描边读的深度缓冲。隐身怪改用
// `GeometryInstance3D.transparency`，见 rendering/materials/toon_material.gd。

// **不要自己定义 PI**：Godot 的 spatial 着色器已经内置了 PI，重定义会报
// `Redefinition of 'PI'` 并让整支着色器编译失败（材质静默回退成默认灰白）。

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_albedo_texture = false;
// filter_nearest：像素风必需，双线性会把图集格子糊成一团
uniform sampler2D albedo_texture : source_color, filter_nearest;
// true = 多光源下取最亮的一支（原版行为），false = 累加
uniform bool clamp_diffuse_to_max = false;

// 色阶数：把连续的 NdotL 量化成几档，是「卡通感」的主开关
uniform int cuts : hint_range(1, 8) = 3;
// 明暗分界的平移量，负值让暗部更宽
uniform float wrap : hint_range(-2.0, 2.0) = 0.0;
// 分层陡峭度：越大分界越硬
uniform float steepness : hint_range(1.0, 8.0) = 1.0;

uniform bool use_attenuation = true;

// 漫反射整体强度——**本项目的亮度标定旋钮**，默认值由实测反推，别随手改。
//
// 为什么必须有这个系数：卡通分层把 diffuse_amount **向色阶上界吸附**
// （见下方 diffuse_stepped），不是四舍五入，所以它的均值天然高于朗伯；
// 叠上本项目的灯光配置（太阳 energy=2.0 + AmbientLight 0.3，两支方向光
// 在 DIFFUSE_LIGHT 里累加），地板在 albedo 0.39 时就直接顶到纯白，
// 整片场景发白、看不到色阶。
//
// 0.25 的来历：同色地板（albedo 0.3875）在 SubViewport (320,260) 处取样，
// 内置 StandardMaterial3D 读回 (0.6275, 0.60, 0.5529)。扫描本系数后
// 0.25 读回 (0.6235, 0.5961, 0.5451)，差 1~2/255，即两种材质肉眼一致。
//
// 注意该值**不可线性外推**：本项目的 WorldEnvironment 开了 ACES tonemap
// （tonemap_mode=3），输出经过 S 形曲线，亮度不是系数的线性函数——
// 0.25→0.62 只让读数从 0.62 涨到 0.91，再往上到 1.0 就整体削顶发白。
// 要重新标定请照着上面的取样法实测，别按比例算。
uniform float diffuse_strength : hint_range(0.0, 1.5) = 0.25;

uniform bool use_specular = false;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.4;
uniform float specular_shininess : hint_range(0.0, 32.0) = 8.0;

// **默认关闭边缘光**。参考实现里 `rim_color` 是 alpha=1 的白、LIGHT_COLOR 归一化
// 到 1 左右，rim 只是给个描边似的亮边。本项目 LIGHT_COLOR 带真实光强
// （太阳 energy=2.0），rim 项会额外加约 +0.5 亮度，把地板和角色一起冲成纯白
// ——大面积平面在俯视相机下几乎处处是掠射角，正好是 rim 最强的地方。
uniform bool use_rim = false;
uniform float rim_width : hint_range(0.0, 16.0) = 6.0;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 0.15);

// 相邻色阶之间的分界暗线（**不是**模型轮廓，见文件头第 2 条）
uniform bool use_borders = false;
uniform float border_width : hint_range(0.0, 0.1) = 0.01;

uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;


// 把高光量化成「有 / 无」两档——卡通渲染里高光是一块色，不是渐变
float split_specular(float specular) {
	return step(0.5, specular);
}


void fragment() {
	vec3 base = albedo.rgb;
	if (use_albedo_texture) {
		base *= texture(albedo_texture, UV).rgb;
	}
	ALBEDO = base;
	EMISSION = emission_color.rgb * emission_energy;
}


void light() {
	// 衰减：方向光恒为 1，点光 / 聚光按距离衰减
	// **Godot 4 里 ATTENUATION 是 float**（原版参考实现写作 ATTENUATION.x，
	// 那是 Godot 3 的 vec3 语义，直接搬过来会编译失败）
	float attenuation = 1.0;
	if (use_attenuation) {
		attenuation = ATTENUATION;
	}

	// ---- 漫反射分层 ----
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = NdotL + (attenuation - 1.0) + wrap;
	diffuse_amount *= steepness;
	float cuts_inv = 1.0 / float(cuts);
	// 把 diffuse_amount 吸附到最近的色阶上界
	float diffuse_stepped = clamp(diffuse_amount + mod(1.0 - diffuse_amount, cuts_inv), 0.0, 1.0);

	// ---- 色块分界暗线（原版 use_borders）----
	// 注意这**不是**模型轮廓，只是相邻色阶之间的描边
	float border = 0.0;
	if (use_borders) {
		float corr_border_width = length(cross(NORMAL, LIGHT)) * border_width * steepness;
		border = step(diffuse_stepped - corr_border_width, diffuse_amount)
				- step(1.0 - corr_border_width, diffuse_amount);
	}

	// **这里既不乘 ALBEDO 也不除 PI**，两处都是 Godot 3 的语义，照抄会出事：
	//   - 乘 ALBEDO → Godot 4 在光循环结束后会再乘一遍，变成 ALBEDO 平方，
	//     深色地面（0.25 灰）被平方成 0.06，整片场景塌成黑色
	//   - 除 PI     → Godot 4 的内置材质并不除，本项目的灯光强度（太阳 2.0）
	//     是按内置口径调的，除 PI 会让所有受该材质的表面暗到约 1/3，
	//     与仍用内置材质的物件（投射物、区域特效）明显脱节
	vec3 diffuse = LIGHT_COLOR;
	diffuse *= diffuse_stepped * (1.0 - border) * diffuse_strength;

	if (clamp_diffuse_to_max) {
		DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
	} else {
		DIFFUSE_LIGHT += diffuse;
	}

	// ---- 高光（Blinn-Phong，量化成硬边）----
	if (use_specular) {
		vec3 H = normalize(LIGHT + VIEW);
		float NdotH = dot(NORMAL, H);
		float specular_amount = max(pow(NdotH, specular_shininess * specular_shininess), 0.0)
				* attenuation;
		specular_amount = split_specular(specular_amount);
		SPECULAR_LIGHT += specular_strength * specular_amount * LIGHT_COLOR;
	}

	// ---- 边缘光 ----
	// 同样不乘 ALBEDO、不除 PI（见上方说明）
	if (use_rim) {
		float NdotV = dot(NORMAL, VIEW);
		float rim_light = pow(1.0 - NdotV, rim_width);
		DIFFUSE_LIGHT += rim_light * rim_color.rgb * rim_color.a * LIGHT_COLOR;
	}
}
