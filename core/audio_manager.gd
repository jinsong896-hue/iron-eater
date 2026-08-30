extends Node
## 音频管理器 —— HD-2D 重构版
## 统一管理 BGM 和 SFX 播放

const SFX_BUS := "SFX"
const BGM_BUS := "BGM"

@export var bgm_volume_db := 0.0
@export var sfx_volume_db := 0.0

var _bgm_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_pool_size := 8

# 音频资源缓存
var _sound_cache := {}


func _ready() -> void:
	_setup_bgm()
	_setup_sfx_pool()


func _setup_bgm() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = BGM_BUS
	add_child(_bgm_player)


func _setup_sfx_pool() -> void:
	for i in _sfx_pool_size:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_sfx_players.append(player)


## 播放背景音乐
func play_bgm(stream_path: String) -> void:
	var stream := _load_audio(stream_path)
	if stream == null:
		return
	_bgm_player.stream = stream
	_bgm_player.play()


## 停止背景音乐
func stop_bgm() -> void:
	_bgm_player.stop()


## 播放音效
func play_sfx(stream_path: String) -> void:
	var stream := _load_audio(stream_path)
	if stream == null:
		return
	var player := _get_free_sfx_player()
	if player == null:
		return
	player.stream = stream
	player.play()


## 快捷方法：按名称播放预设音效
func play(_sfx_name: String) -> void:
	# TODO: 建立音效名称映射表
	match name:
		"hit":
			play_sfx("res://assets/audio/hit.wav")
		"pickup":
			play_sfx("res://assets/audio/pickup.wav")
		"death":
			play_sfx("res://assets/audio/death.wav")
		"menu_click":
			play_sfx("res://assets/audio/click.wav")


func _load_audio(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if _sound_cache.has(path):
		return _sound_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var stream := ResourceLoader.load(path, "AudioStream", ResourceLoader.CACHE_MODE_REUSE) as AudioStream
	if stream:
		_sound_cache[path] = stream
	return stream


func _get_free_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_players:
		if not player.playing:
			return player
	return _sfx_players[0]  # 都忙则复用第一个