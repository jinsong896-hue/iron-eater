@icon("uid://c87bx2sxf5nwj")
@tool
extends ComputeUniform 
class_name ImageUniform 
## 贴图节点
@export_custom(PROPERTY_HINT_NODE_TYPE, "TextureRect,Sprite2D,Viewport")
var texture_node:Node
@export var image_size:=Vector2i.ONE:
	set(value):
		image_size = Vector2i(max(1,value.x),max(1,value.y))
## 是否为输出纹理,可以替换贴图节点纹理[br]
## 写入需要开启允许存储用途
@export var output_image:=false
## 选择图片格式限定符
@export var format_qualifier: FormatQualifier = 0
## 图片格式限定符枚举
@export_group("限定符")
## 只读限定符：纹理只能读取，不能写入。优化缓存性能
@export var is_readonly: bool = false:
	set(v):
		is_readonly = v
		if is_writeonly and v:
			is_writeonly = false
			print("只读 只写互斥")
## 只写限定符：纹理只能写入，不能读取。减少读取开销
@export var is_writeonly: bool = false:
	set(v):
		is_writeonly = v
		if is_readonly and v:
			is_readonly = false
			print("只读 只写互斥")
## 限制别名：确保纹理没有其他别名，允许编译器更多优化
@export var is_restrict: bool = false
## 一致性：保证内存操作在所有着色器调用间可见，用于原子操作
@export var is_coherent: bool = false
## 易变性：禁止编译器优化内存访问，用于硬件寄存器
@export var is_volatile: bool = false
@export_group("", "")
# 或使用复选框版本
@export_group("用途复选框")
## 可采样：纹理可以被着色器采样（texture()调用）。[br]大多数纹理都需要启用此项。
@export var enable_sampling: bool = true
## 可读写：纹理可以被计算着色器读写（imageLoad()/imageStore()）。[br]启用后性能可能下降，但允许GPU读写纹理数据。
@export var enable_storage: bool = true
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
## 根据计算着色器数据生成的Texture2DRD
var compute_texture:Texture2DRD
## 纹理格式
var image_format:int

## 获取rd_uniform
func get_rd_uniform() -> RDUniform:
	_set_uniform()
	rd_uniform = RDUniform.new()
	rd_uniform.uniform_type = uniform_type
	rd_uniform.binding = binding
	rd_uniform.add_id(rid)
	#print("创建 Uniform - 类型: %d, 绑定: %d\n" % [uniform_type, binding])
	rd_change.emit()
	return rd_uniform

func get_declaration(set:int)->String:
	return "layout(set = %s, binding = %s, %s) %suniform %s %s;  %s\n" % [
			str(set),
			str(binding),
			str(_get_format_qualifier()),
			_get_qualifiers(),
			"image2D",
			uniform_name,
			"// " + description if description else "" # 描述
			 ]

func update_from_rd()->PackedByteArray:
	return rd.texture_get_data(rid, 0)

func updata_image() -> Image:
	var new_data := update_from_rd()
	var new_image:=Image.create_from_data(
		compute_texture.get_width(),
		compute_texture.get_height(),
		false,
		image_format,
		new_data
		)
	return new_image
#<=============================私有方法=============================>#

## 更新uniform绑定
func _set_uniform()-> RID:
	uniform_type =  RenderingDevice.UNIFORM_TYPE_IMAGE
	image_format = _get_rd_format()
	
	if texture_node is SubViewport :
		rid =  RenderingServer.texture_get_rd_texture( # 将子视口rid转成渲染服务器rid
		RenderingServer.viewport_get_texture( # 获取子视口的rid
			texture_node.get_viewport_rid() 
			))
		return rid
		
	## 创建纹理
	var image:Image
	if texture_node and texture_node.texture and texture_node.texture is not Texture2D:
		image = texture_node.texture.get_image()
	else :
		image = Image.create_empty(image_size.x,image_size.y,false,image_format)
	rid = _create_texture_from_image(image)
	compute_texture = Texture2DRD.new()
	compute_texture.texture_rd_rid = rid
	if texture_node and output_image:
		texture_node.texture = compute_texture
	return rid

## 获取格式限定符字符串
func _get_format_qualifier() -> String:
	match format_qualifier:
		FormatQualifier.RGBA8: return "rgba8"
		FormatQualifier.RG8: return "rg8"
		FormatQualifier.R8: return "r8"
		FormatQualifier.RGBA16F: return "rgba16f"
		FormatQualifier.RGBA32F: return "rgba32f"
		FormatQualifier.R32F: return "r32f"
		FormatQualifier.RG16F: return "rg16f"
		FormatQualifier.RG32F: return "rg32f"
		_: return "rgba8"

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

## 获取限定符字符串
func _get_qualifiers() -> String:
	var qualifiers = []	
	if is_readonly:
		qualifiers.append("readonly")
	elif is_writeonly:
		qualifiers.append("writeonly")
	if is_restrict:
		qualifiers.append("restrict")
	if is_coherent:
		qualifiers.append("coherent")
	if is_volatile:
		qualifiers.append("volatile")
	return " ".join(qualifiers)+" "

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

## 从图片创建 纹理RID （rd）
func _create_texture_from_image(image: Image) -> RID:
	# 1. 获取图片信息
	var texture_size = image.get_size()
	
	# 2. 定义图片数据
	var image_data = []
	image_data.resize(1)  
	image_data[0] = image.get_data()  # 获取原始字节数据
	
	# 3. 获取合适的RD纹理格式
	var rd_texture_format = _get_rd_texture_format_for_image(image)
	
	# 4. 创建纹理RID
	var texture_rid = rd.texture_create(
		rd_texture_format, 
		view, 
		image_data
	)
	
	return texture_rid

func _get_rd_texture_format_for_image(image: Image) -> RDTextureFormat:
	# 创建RDTextureFormat对象
	var texture_format = RDTextureFormat.new()
	
	# 设置基本属性
	texture_format.width = image.get_width()
	texture_format.height = image.get_height()
	texture_format.depth = 1
	texture_format.array_layers = 1
	texture_format.mipmaps = 1
	texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	
	# 根据Image格式设置RD格式
	var rd_data_format = _map_image_format_to_rd_format(image.get_format())
	texture_format.format = rd_data_format
	
	# 设置使用标志
	texture_format.usage_bits = _get_actual_usage_bits()
	
	return texture_format

func _map_image_format_to_rd_format(image_format: Image.Format) -> int:
	match image_format:
		Image.FORMAT_RGBA8:
			return RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		Image.FORMAT_RGB8:
			return RenderingDevice.DATA_FORMAT_R8G8B8_UNORM
		Image.FORMAT_RG8:
			return RenderingDevice.DATA_FORMAT_R8G8_UNORM
		Image.FORMAT_R8:
			return RenderingDevice.DATA_FORMAT_R8_UNORM
		Image.FORMAT_RGBAF:
			return RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		Image.FORMAT_RGBF:
			return RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
		Image.FORMAT_RGF:
			return RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
		Image.FORMAT_RF:
			return RenderingDevice.DATA_FORMAT_R32_SFLOAT
		Image.FORMAT_RGBAH:
			return RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		Image.FORMAT_DXT1:
			return RenderingDevice.DATA_FORMAT_BC1_RGB_UNORM_BLOCK
		Image.FORMAT_DXT3:
			return RenderingDevice.DATA_FORMAT_BC2_UNORM_BLOCK
		Image.FORMAT_DXT5:
			return RenderingDevice.DATA_FORMAT_BC3_UNORM_BLOCK
		Image.FORMAT_ETC2_RGB8:
			return RenderingDevice.DATA_FORMAT_ETC2_R8G8B8_UNORM_BLOCK
		# ... 其他格式映射
		_:
			# 默认回退到RGBA8
			push_warning("Unsupported image format, falling back to RGBA8")
			return RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
