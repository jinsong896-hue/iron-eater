shader_type spatial;
// 模型轮廓描边（反壳法 / inverted hull）
//
// 思路：把网格沿顶点法线向外推，只画**背面**（cull_front），得到一圈包住
// 模型的纯色外壳。挂在 toon 材质的 `next_pass` 上，几何体只多画一遍，
// 不需要额外节点，也不依赖屏幕空间缓冲。
//
// 与另两条描边通道的分工（三条各管一段，别互相顶替）：
//   - 本文件          → 角色 / 怪物 / 场景物件的**模型外轮廓**（实心黑边）
//   - pixel_post_process.gdshader → 墙 / 地板之间的**接缝线**（屏幕空间深度+法线）
//   - toon.gdshader 的 use_borders → 模型**自身明暗色块之间**的分界暗线
//
// **顶点外推而非屏幕空间膨胀**：屏幕空间描边需要读邻域深度，在 SubViewport
// 低分辨率下会随像素化一起变成台阶；反壳描边是世界空间的，与分辨率无关。
//
// `grow_amount` 在**视空间**加偏移：直接改 VERTEX 的话，模型若被父节点缩放，
// 描边宽度会跟着缩放（敌人有 body_scale，吞噬者还会长大），近处粗远处细。
// 视空间偏移让描边在任何缩放下都是固定像素宽度。
//
// **没有 INV_MODELVIEW_MATRIX 这个内置量**（Godot 4 的 spatial 着色器只给
// MODELVIEW_MATRIX / INV_VIEW_MATRIX / INV_PROJECTION_MATRIX 等）。这里走
// 「视空间算完再乘回模型空间」的等价写法：视图矩阵是正交的，转置即逆。

render_mode unshaded, cull_front, shadows_disabled, blend_mix;

// 视空间外扩量。0.01 在 640×360 的 SubViewport 下约合 1 个像素
uniform float grow_amount : hint_range(0.0, 0.1) = 0.012;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// 描边整体不透明度。**必须显式写 ALPHA 并开混合**：
//
// 反壳描边挂在 next_pass 上，而 `GeometryInstance3D.transparency`
// （隐身怪用的那条路，见 rendering/materials/toon_material.gd）
// **只作用于主 pass，不会传导到 next_pass**。不在这里补一个 alpha，
// 隐身怪就会变成「本体几乎透明、外圈一圈实心黑边」——比不隐身还显眼。
//
// 显式写 ALPHA 会让这支 pass 掉进透明队列（不写深度），这对 next_pass
// 没有副作用：它本来就只画外壳、不参与任何后续读取。
uniform float outline_alpha : hint_range(0.0, 1.0) = 1.0;


void vertex() {
	// 法线转到视空间（w=0 只取旋转部分），避免模型缩放污染描边宽度
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// 再转回模型空间：视图矩阵正交，其逆等于转置
	vec3 model_normal = normalize((vec4(view_normal, 0.0) * MODELVIEW_MATRIX).xyz);
	VERTEX += model_normal * grow_amount;
}


void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a * outline_alpha;
}
