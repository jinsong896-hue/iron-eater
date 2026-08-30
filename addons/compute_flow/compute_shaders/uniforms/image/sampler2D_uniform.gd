@icon("uid://ba1uh4mggvxy0")
@tool
extends ComputeUniform 
class_name Sampler2DUniform 
## 贴图变量

@export_custom(PROPERTY_HINT_NODE_TYPE, "TextureRect,Sprite2D,SubViewport")
var texture_node:Node

@export var image_size:=Vector2i.ZERO


enum SamplerType {
	NEAREST_CLAMP,      ## 最近邻 + 钳制
	LINEAR_CLAMP,       ## 线性 + 钳制  
	LINEAR_REPEAT,      ## 线性 + 重复
	LINEAR_MIPMAP,      ## 线性 + mipmap
	ANISOTROPIC         ## 各向异性
	}
## 采样器样式
@export var sampler_type = SamplerType.LINEAR_CLAMP


## 选择图片格式限定符
@export var format_qualifier: FormatQualifier = 0
@export_group("用途复选框")
## 可采样：纹理可以被着色器采样（texture()调用）。[br]大多数纹理都需要启用此项。
@export var enable_sampling: bool = true
## 可读写：纹理可以被计算着色器读写（imageLoad()/imageStore()）。[br]启用后性能可能下降，但允许GPU读写纹理数据。
@export var enable_storage: bool = false
## 渲染目标：纹理可以作为颜色渲染目标。[br]用于离屏渲染、后处理等需要将内容渲染到纹理的场景。
@export var enable_color_attachment: bool = false
## 深度模板：纹理可以作为深度/模板缓冲。[br]用于深度测试、阴影映射等需要深度信息的渲染。
@export var enable_depth_attachment: bool = false
## 可更新：纹理数据可以被更新。[br]允许在创建后修改纹理内容，禁用此项可提高性能。
@export var enable_can_update: bool = true
## 可从CPU读：纹理数据可以从GPU读回CPU。[br]用于屏幕截图、读取渲染结果等，有性能开销。
@export var enable_can_copy_from: bool = false
## 可写入CPU：CPU数据可以上传到纹理。[br]用于动态更新纹理内容，大部分情况与可更新重复。
@export var enable_can_copy_to: bool = false


## 获取rd_uniform
func get_rd_uniform() -> RDUniform:
	rid = RID()
	_set_uniform()
	rd_uniform = RDUniform.new()
	uniform_type =  rd.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	rd_uniform.uniform_type = uniform_type
	rd_uniform.binding = binding
	rd_uniform.add_id(_create_sampler_by_type())
	rd_uniform.add_id(rid)
	print("创建 Uniform - 类型: %d, 绑定: %d\n" % [uniform_type, binding])
	rd_change.emit()
	return rd_uniform

## 获取glsl文本
func get_declaration(set:int)->String:
	return "layout(set = %s, binding = %s) uniform %s %s;  %s\n" % [
			str(set),
			str(binding),
			"sampler2D",
			uniform_name,
			"// " + description if description else "" # 描述
			 ]

# <==============================私有方法==============================> #

func _set_uniform():
	## 创建纹理
	if texture_node is SubViewport :
		texture_node.render_target_clear_mode = 0
		texture_node.render_target_update_mode = 4
		texture_node.transparent_bg = true
		rid =  RenderingServer.texture_get_rd_texture( 
		RenderingServer.viewport_get_texture( # 获取子视口的rid
			texture_node.get_viewport_rid() ))
		return rid
		
	# 创建纹理
	var image:Image
	if texture_node.texture and texture_node.texture :
		if texture_node.texture is Texture2DRD:
			rid = texture_node.texture.texture_rd_rid
			return 

		elif texture_node.texture is NoiseTexture2D:
			image = texture_node.texture.noise.get_image(texture_node.texture.width
				,texture_node.texture.height)
			image.convert(Image.FORMAT_RGBA8)
		else:
			image = texture_node.texture.get_image()
			image.convert(Image.FORMAT_RGBA8)
	else :
		image = Image.create_empty(image_size.x,image_size.y,false,_get_rd_format())
	var texture_format = RDTextureFormat.new()
	texture_format.width = image.get_width()
	texture_format.height = image.get_height()
	texture_format.format = _get_rd_format_from_image_format(image.get_format())
	# 设置使用标志
	texture_format.usage_bits = _get_actual_usage_bits()
	# 创建纹理数据数组
	var image_data = image.get_data()
	var data_array = PackedByteArray()
	data_array.append_array(image_data)
	# 创建纹理
	rid = rd.texture_create(texture_format, view, [data_array])

## 创建采样器
func _create_sampler_by_type() -> RID:
	var state = RDSamplerState.new()
	
	match sampler_type:
		SamplerType.NEAREST_CLAMP:
			state.mag_filter = rd.SAMPLER_FILTER_NEAREST
			state.min_filter = rd.SAMPLER_FILTER_NEAREST
			state.repeat_u = rd.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
			state.repeat_v = rd.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
			
		SamplerType.LINEAR_CLAMP:
			state.mag_filter = rd.SAMPLER_FILTER_LINEAR
			state.min_filter = rd.SAMPLER_FILTER_LINEAR
			state.repeat_u = rd.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
			state.repeat_v = rd.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
			
		SamplerType.LINEAR_REPEAT:
			state.mag_filter = rd.SAMPLER_FILTER_LINEAR
			state.min_filter = rd.SAMPLER_FILTER_LINEAR
			state.repeat_u = rd.SAMPLER_REPEAT_MODE_REPEAT
			state.repeat_v = rd.SAMPLER_REPEAT_MODE_REPEAT
			
		SamplerType.LINEAR_MIPMAP:
			state.mag_filter = rd.SAMPLER_FILTER_LINEAR
			state.min_filter = rd.SAMPLER_FILTER_LINEAR_MIPMAP_LINEAR
			state.mip_filter = rd.SAMPLER_FILTER_LINEAR
			
		SamplerType.ANISOTROPIC:
			state.mag_filter = rd.SAMPLER_FILTER_LINEAR
			state.min_filter = rd.SAMPLER_FILTER_LINEAR_MIPMAP_LINEAR
			state.max_anisotropy = 16.0
	
	return rd.sampler_create(state)

## 获取用途
func _get_actual_usage_bits() -> int:
	# 使用复选框版本
	var usage = 0
	if enable_sampling:
		usage |= RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	if enable_storage:
		usage |= RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	if enable_color_attachment:
		usage |= RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
	if enable_depth_attachment:
		usage |= RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
	if enable_can_update:
		usage |= RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	if enable_can_copy_from:
		usage |= RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	if enable_can_copy_to:
		usage |= RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return usage

# 辅助函数：转换 Image 格式到 RD 格式
func _get_rd_format_from_image_format(image_format: int) -> int:
	match image_format:
		Image.FORMAT_RGBA8:
			return RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		Image.FORMAT_RGB8:
			return RenderingDevice.DATA_FORMAT_R8G8B8_UNORM
		Image.FORMAT_R8:
			return RenderingDevice.DATA_FORMAT_R8_UNORM
		Image.FORMAT_RGBAF:
			return RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		Image.FORMAT_RGF:
			return RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
		Image.FORMAT_RF:
			return RenderingDevice.DATA_FORMAT_R32_SFLOAT
		_:
			return RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM  # 默认
	
## 将枚举转换为纹理格式
func _get_rd_format() -> int:
	match format_qualifier:
		FormatQualifier.RGBA8:
			return Image.FORMAT_RGBA8
		FormatQualifier.RG8:
			return Image.FORMAT_RG8
		FormatQualifier.R8:
			return Image.FORMAT_R8
		FormatQualifier.RGBA16F:
			return Image.FORMAT_RGBAH
		FormatQualifier.RGBA32F:
			return Image.FORMAT_RGBAF
		FormatQualifier.R32F:
			return Image.FORMAT_RF
		FormatQualifier.RG16F:
			return Image.FORMAT_RGH
		FormatQualifier.RG32F:
			return Image.FORMAT_RGF
		_:
			return Image.FORMAT_RGBA8
