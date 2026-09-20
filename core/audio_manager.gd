extends Node
## 音频管理器 —— HD-2D 重构版
## 统一管理 BGM 和 SFX 播放

const SFX_BUS := "SFX"
const BGM_BUS := "BGM"
## 音效素材目录（Kenney「RPG Audio」CC0，见 assets/rpg-audio/License.txt）
const SFX_DIR := "res://assets/rpg-audio/Audio/"

## 语义名 → 素材文件。
##
## ## 为什么必须有这张表
## 此前 `play()` 里的 `match name` 匹配的是**节点名**（本 autoload 叫
## "AudioManager"）而不是参数 `_sfx_name`，四个分支**永远进不去**；
## 且那些分支指向的 `res://assets/audio/*.wav` 全项目**不存在**。
## 结果是玩家受击/击杀/拾取/死亡四处调用**全部静默无声**——
## 不报错、不警告，看起来像"还没做音效"，实际是接错了变量名。
##
## 素材是 Kenney 的通用音效包，没有"受击/死亡"这类语义命名，
## 故这里按**听感用途**挑文件（金属撞击→受击、割裂→命中、金币→拾取、
## 低吟→死亡）。换素材只需改这张表的右半边。
const SFX_MAP := {
	"hit": "knifeSlice2.ogg",        # 金属割裂，玩家挥砍命中
	"pickup": "handleCoins.ogg",     # 金币哗啦，拾取掉落物
	"death": "creak3.ogg",           # 木构呻吟，玩家阵亡
	"menu_click": "metalClick.ogg",  # 金属轻点，UI 按钮
}

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


## 快捷方法：按语义名播放预设音效。
##
## 未登记的语义名**静默返回**（不是报错）——音效缺失不该打断游戏逻辑，
## 但要用 `has_sfx()` 在测试里守"表里的名字都有对应素材"。
func play(_sfx_name: String) -> void:
	var file: String = SFX_MAP.get(_sfx_name, "")
	if file.is_empty():
		return
	play_sfx(SFX_DIR + file)


## 语义名是否已登记且素材存在（测试/调试用）
func has_sfx(sfx_name: String) -> bool:
	var file: String = SFX_MAP.get(sfx_name, "")
	return not file.is_empty() and ResourceLoader.exists(SFX_DIR + file)


## 递归给一棵 UI 子树里的所有按钮接上点击音。
##
## **用递归而不是逐个手接**：菜单里的按钮是散落在各处的 @onready 字段，
## 逐个补意味着以后每加一个按钮就要记得再补一行——那正是这类"静默无声"
## 缺陷的成因。递归一次覆盖全部，新按钮自动带上。
##
## **幂等**：已连接过的按钮会跳过，故可以在按钮动态增删后再调一次。
## 用 `is_connected` 判断而不是自己记账——记账会和实际的连接状态脱节。
func connect_buttons(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root is Button and not (root as Button).pressed.is_connected(_on_ui_button_pressed):
		(root as Button).pressed.connect(_on_ui_button_pressed)
	for child in root.get_children():
		connect_buttons(child)


## 按钮点击音的统一回调（`connect_buttons` 用）
func _on_ui_button_pressed() -> void:
	play("menu_click")


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