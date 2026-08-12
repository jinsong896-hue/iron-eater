extends Node
## 音效管理：《AGENTS.md 素材规则》——使用 Kenney rpg-audio（CC0）免费素材
## 启动时创建 Music/SFX 总线，设置面板的音量滑条即可直接生效

const SFX_PATHS := {
	"hit": "res://assets/rpg-audio/Audio/knifeSlice.ogg",
	"pickup": "res://assets/rpg-audio/Audio/handleCoins.ogg",
	"death": "res://assets/rpg-audio/Audio/creak3.ogg",
	"ui": "res://assets/rpg-audio/Audio/metalClick.ogg",
	"door_open": "res://assets/rpg-audio/Audio/doorOpen_1.ogg",
	"door_close": "res://assets/rpg-audio/Audio/doorClose_1.ogg",
}

var _pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)


func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, name)


func play(sfx_name: String) -> void:
	if not SFX_PATHS.has(sfx_name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = load(SFX_PATHS[sfx_name])
			p.play()
			return


func play_ui() -> void:
	play("ui")
