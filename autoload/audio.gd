extends Node
## 効果音（FR-51, FR-52）。autoload。assets/sfx/<key>.wav（無ければ .ogg）を SE バスで鳴らす。

signal played(key: StringName)  # 鳴らそうとした（ファイルが無いキーでも出す。自動確認が数える）

const KEYS: Array[StringName] = [&"toggle", &"hit_small", &"hit_big", &"explosion", &"wall_break", &"derail",
		&"crash", &"goal", &"girigiri", &"stamp", &"ui_move", &"ui_select"]
const SFX_DIR: String = "res://assets/sfx/"
const BUS: StringName = &"SE"

var _players: Dictionary = {}  # key → AudioStreamPlayer（ファイルが無いキーは入らない）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # ポーズ中もメニューの音を鳴らす
	load_sounds(SFX_DIR)


## FR-52: キーごとに .wav → .ogg の順で探す。どちらも無いキーは鳴らさず、キーごとに1回だけ警告する
func load_sounds(dir: String) -> void:
	for p: Node in get_children():
		p.free()
	_players.clear()
	for key: StringName in KEYS:
		var stream: AudioStream = null
		for ext: String in ["wav", "ogg"]:
			var path: String = "%s%s.%s" % [dir, key, ext]
			if ResourceLoader.exists(path):
				stream = load(path)
				break
		if stream == null:
			push_warning("効果音 %s が無いので鳴らさない（%s に %s.wav か %s.ogg を置くと鳴る）" % [key, dir, key, key])
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = BUS
		player.max_polyphony = Tuning.SE_POLYPHONY
		add_child(player)
		_players[key] = player


func play(key: StringName) -> void:
	assert(key in KEYS, "未知の効果音 %s" % key)
	played.emit(key)
	var player: AudioStreamPlayer = _players.get(key)
	if player != null:
		player.play()


## FR-51: 音量 0〜100 を linear_to_db(音量 / 100) で SE バスに。0 はミュート（-inf dB を避ける、10章）
func set_volume(volume: int) -> void:
	var bus: int = AudioServer.get_bus_index(BUS)
	AudioServer.set_bus_mute(bus, volume <= 0)
	if volume > 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(volume / float(Tuning.SE_VOLUME_MAX)))
