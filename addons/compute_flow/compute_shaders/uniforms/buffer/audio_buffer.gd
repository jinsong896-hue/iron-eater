@icon("uid://0v0dr6x2knfj")
@tool
extends StorageBuffer
class_name AudioBuffer

@export_tool_button("add_audio_macro") var add_audio_macro = _add_audio_macro
@export_tool_button("add_audio_struct") var add_audio_struct = _add_audio_struct

@export_custom(PROPERTY_HINT_NODE_TYPE, "AudioStreamPlayer,AudioStreamPlayer2D,AudioStreamPlayer3D")
var audio_stream_player:Node
var audio_stream:AudioStreamGenerator
var playback:AudioStreamGeneratorPlayback

func _ready() -> void:
	if Engine.is_editor_hint():
		editor_description = "绑定音频buffer到播放器\n使用AudioStream:完成程序化音频"
		return
	
	audio_stream = AudioStreamGenerator.new()
	audio_stream.mix_rate = 44100
	if audio_stream_player:
		audio_stream_player.stream = audio_stream
	await rd_change
	black_board.compute_run.connect(get_audio_stream)

func get_audio_stream():
	var byte_data = get_byte_array()
	var audio_frames = byte_data.to_vector2_array()
	# 创建AudioStreamGenerator
	audio_stream.buffer_length = float(audio_frames.size()) / 44100.0
	audio_stream_player.play()
	# 获取播放器引用并填充
	playback = audio_stream_player.get_stream_playback()
	if playback:
		playback.push_buffer(audio_frames)
	
func _add_audio_macro():
	if black_board:
		black_board.macro += "
//音频常量
#define SAMPLE_RATE 44100.0          // 标准音频采样率
#define INV_SR      0.00002267573    // 采样率倒数

#define OSC_SINE(p)     (sin(p))                                             // 正弦波
#define OSC_SAW(p)      ((mod(p, TWO_PI) / PI) - 1.0)                        // 锯齿波
#define OSC_SQUARE(p)   (sin(p) >= 0.0 ? 1.0 : -1.0)                         // 方波
#define OSC_TRIANGLE(p) (abs(mod((p), TWO_PI) - PI) / HALF_PI - 1.0)         // 三角波
"
		
		black_board.is_dirty = true
		black_board.changed.emit()
func _add_audio_struct():
	var audio_struct:= AudioStruct.new()
	if black_board:
		black_board.structs.append(audio_struct)
		black_board.is_dirty = true
		black_board.changed.emit()
