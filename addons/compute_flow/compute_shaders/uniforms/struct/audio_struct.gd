@tool
extends Struct
class_name AudioStruct
## 音频结构体参数

func _init() -> void:
	struct_name = "AudioStruct"
	fields = "
float left;     // 左声道振幅 (-1.0 ~ 1.0)
float right;    // 右声道振幅 (-1.0 ~ 1.0)

float time_offset = 0.0 ;    // 时间偏移（秒）
float base_frequency= 440.0; // 基础频率
float amplitude=0.5;         // 振幅
"
