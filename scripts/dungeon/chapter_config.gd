class_name ChapterConfig
extends Resource
## 章节（层）配置：《关卡设计分册》1.2 每层参数 + 主题配色

@export var layer_id := 1
@export var chapter_name := ""
@export var map_size := 14          # 母网格可用范围（14/16/.../30）
@export var min_rooms := 12
@export var max_rooms := 16
@export var elite_rate := 0.25      # 精英房占战斗房比例（文档 20%～30%）
@export_color_no_alpha var floor_color := Color(0.25, 0.27, 0.32)
@export_color_no_alpha var wall_color := Color(0.12, 0.13, 0.16)
@export_color_no_alpha var corridor_color := Color(0.18, 0.19, 0.22)
