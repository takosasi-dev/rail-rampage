extends Node2D
## ゲーム画面。ステージを組み立て、トロッコを走らせ、アクティブ分岐・標的の破壊・得点・勢い・失敗・リトライと、
## 演出（ヒットストップ・スローモー・揺れ・破片・ズーム・試験開始バナー・初回ヒント・効果音）、HUD、ポーズ、
## リザルトへの移動を管理する。

signal exploded(drum: Target)  # drum が爆発した（自動確認 AC-6 が数える）

const STAGE_SELECT_SCENE: String = "res://scenes/stage_select.tscn"
const RESULT_SCENE: String = "res://scenes/result.tscn"
const PAUSE_SCENE: PackedScene = preload("res://scenes/pause_menu.tscn")
const TROLLEY_SCENE: PackedScene = preload("res://scenes/objects/trolley.tscn")
const WRECK_SCENE: PackedScene = preload("res://scenes/objects/trolley_wreck.tscn")
const BRICK_PIECE_SCENE: PackedScene = preload("res://scenes/objects/brick_piece.tscn")
const SCORE_POPUP_SCENE: PackedScene = preload("res://scenes/ui/score_popup.tscn")
const GIRIGIRI_SCENE: PackedScene = preload("res://scenes/ui/girigiri.tscn")
const BANNER_SCENE: PackedScene = preload("res://scenes/ui/banner.tscn")
const FIRST_HINT_SCENE: PackedScene = preload("res://scenes/ui/first_hint.tscn")
const TITLE_SCENE: String = "res://scenes/title.tscn"
const ENDLESS_RESULT_SCENE: String = "res://scenes/endless_result.tscn"

## 空なら GameState.current_stage のステージを読む（自動確認はここにステージを直接入れる）
var stage_data: Dictionary = {}
var score: int = 0
var combo: int = 0
var momentum: float = 0.0  # FR-21
var girigiri_count: int = 0  # ギリギリ突破の回数
var fail_reason: String = ""  # 失敗したら「激突」か「脱線」
var auto_pause: bool = true  # FR-47。画面を撮る確認用のスクリプトは切る（窓がフォーカスを失っても止めない）
# リザルト（FR-45, FR-46）に出す記録
var smashed_count: int = 0  # 壊した標的の数（wall は1個、レンガ片は数えない）
var total_targets: int = 0
var max_combo: int = 0
var max_speed: float = 0.0  # px/s
# 試験記録（設計書 docs/superpowers/specs/2026-09-26-records-design.md の 2.2）に出す記録
var smashed_by_kind: Dictionary = {}  # 種類 → 壊した数
var chained_count: int = 0  # 爆発に巻き込まれて爆発したドラム缶の数
var toggle_count: int = 0  # 分岐を切り替えた回数
var distance: float = 0.0  # 走った距離（px）
## 車両（trolleys-and-display-design.md 1章）。ステージを組む前に GameState.trolley() から決める
var trolley_id: String = Trolleys.DEFAULT

var _segments: Dictionary = {}
var _junctions: Dictionary = {}
var _active: Junction = null
var _trolley: Trolley = null
var _wreck: TrolleyWreck = null  # 失敗後に転がるトロッコ（FR-25）
var _finished: bool = false  # トロッコが止まった（ゴール・失敗・ステージデータエラー）
var _last_retry: float = -INF  # 実時間（秒）。リトライ後のゲーム画面にも引き継ぐ（FR-26 の連打よけ）
var _targets: Array[Target] = []  # 未破壊の標的
var _active_bodies: Array[Target] = []  # freeze 解除済みの物体（破片を含む）。古い順（NFR-2）
var _time: float = 0.0  # ゲーム内時刻（コンボ・連鎖・物体の寿命に使う）
var _last_smash_time: float = -INF
var _combo_alive: bool = false  # 最後の smash から COMBO_WINDOW 秒以内
var _chain: Array = []  # 連鎖待ちの [drum: Target, 爆発する時刻: float]（FR-17）
var _shake_amp: float = 0.0  # 揺れ始めの振幅（FR-33）
var _shake_left: float = 0.0  # 揺れの残りの実時間（秒）
var _shake_tween: Tween = null
var _hint: FirstHint = null  # 初回操作ヒント（FR-36c）。最初の切替が成功したら消す
var _number: int = 1  # 試験番号
var _fail_required: float = 0.0  # 失敗した壁・ジャンプの必要速度（px/s）
var _fail_speed: float = 0.0  # 失敗した瞬間の速度（px/s）
var _best_updated: bool = false
var _result_at: float = INF  # リザルトを出すゲーム内時刻
var _result: Control = null
var _pause: Control = null
var time_of_day: String = "noon"  # 設計書4章。ステージを組む前に、設定の A／C とステージから決める
var _fx: Node2D = null  # ② 演出の置き場（World/Effects）
var _goal: Goal = null
var _last_segment: String = ""  # ② ジャンプの着地を見分けるため、1つ前のセグメント
var _run_sent: bool = false  # 走行1回分の記録を GameState に出した
var _new_stamps: Array[String] = []  # この走行で新しく取った検定印
var _unlocked_before: Array[String] = []  # 走り出したときに解放されていた車両
var _new_trolleys: Array[String] = []  # この走行で新しく解放された車両
# やりこみ要素（設計書 docs/superpowers/specs/2026-09-28-replay-value-design.md）
var _upgrades: Dictionary = {}  # この走行の車両の強化（走り出したときの写し）
var _gold: bool = false  # この走行で金★を取った
var _new_challenges: Array[int] = []  # この走行で新しく達成した課題の番号
var _xp: Dictionary = {"gained": 0, "level_before": 1, "level_after": 1}  # この走行の熟練度
var _ghost_rec: GhostRecorder = null
var _ghost: GhostPlayer = null
# 無限軌道（replay-value-design.md 7章。GameState.endless のときだけ使う）
var _endless: Endless = null  # 線路を先へ足していく生成
var _endless_nodes: Array[Dictionary] = []  # 組んだ区間（古い順）: {"node": まとめのノード, "targets": その区間の標的}
var _endless_best: bool = false  # この走行で最高記録（得点か距離）を更新した
var _endless_title: Control = null  # HUD の見出し「無限軌道」と距離
var _endless_shown_m: int = -1  # 見出しに出している距離（m）

@onready var _world: Node2D = $World
@onready var _camera: Camera2D = $Camera2D
@onready var _hud: CanvasLayer = $Hud
@onready var _hud_view: Control = $Hud/HudView
@onready var _message: Label = $Hud/Message
@onready var _fail_text: Label = $Hud/FailText
@onready var _combo_fx: ComboFx = $Hud/ComboFx
@onready var _debug_label: Label = $Hud/DebugLabel
@onready var _overlay: CanvasLayer = $Overlay  # ポーズとリザルト（HUD・バナー・コンボの札より手前）


func _ready() -> void:
	RenderingServer.set_default_clear_color(Palette.BOARD)
	for label: Label in [_message, _debug_label]:
		label.add_theme_color_override("font_color", Palette.INK)
		label.add_theme_color_override("font_outline_color", Palette.PAPER)
		label.add_theme_constant_override("outline_size", Tuning.TEMP_HUD_OUTLINE)
	_message.add_theme_font_override("font", Fonts.DELA)
	_message.add_theme_font_size_override("font_size", Tuning.MESSAGE_FONT_SIZE)
	_debug_label.visible = OS.is_debug_build()
	# 16.6: 激突！／脱線！ は Dela Gothic One の STAMP の文字に PAPER の3pxずらし影
	var fail_settings := LabelSettings.new()
	fail_settings.font = Fonts.DELA
	fail_settings.font_size = Tuning.FAIL_FONT_SIZE
	fail_settings.font_color = Palette.STAMP
	fail_settings.shadow_color = Palette.PAPER
	fail_settings.shadow_offset = Tuning.FAIL_SHADOW_OFFSET
	fail_settings.shadow_size = 0
	_fail_text.label_settings = fail_settings
	if GameState.endless:
		_endless_ready()
		return
	if stage_data.is_empty():
		stage_data = StageLoader.load_json(GameState.stage_path(GameState.current_stage))
	# 6.4: 検証に通らなければ、違反を出して「ステージデータエラー」を表示し、ステージ選択に戻る（AC-14）
	var errors: Array[String] = StageLoader.validate(stage_data)
	if not errors.is_empty():
		for e: String in errors:
			push_error("ステージデータエラー: %s" % e)
		_show_message("ステージデータエラー")
		_hud_view.hide()
		_finished = true
		get_tree().create_timer(Tuning.STAGE_ERROR_DELAY).timeout.connect(_to_stage_select)
		return
	_segments = stage_data["segments"]
	trolley_id = GameState.trolley()
	_upgrades = GameState.garage(trolley_id)["upgrades"]
	_unlocked_before = GameState.unlocked_trolleys()
	_number = stage_number(stage_data.get("id", ""))
	time_of_day = GameState.time_of_day(_number, stage_data)
	Quality.level = GameState.quality  # 画質はゲーム画面を作るときに読む（trolleys-and-display-design.md 4章）
	_dress_stage()
	var built: Dictionary = StageLoader.build(stage_data, _world, time_of_day)
	_junctions = built["junctions"]
	_targets.assign(built["targets"])
	total_targets = _targets.size()
	# 車両の壁・ジャンプへの強さ: 壁と標識の必要速度をその車両の値にする（ジャンプは進入したときに換算する）
	for t: Target in _targets:
		if t.kind == "wall":
			t.required_speed = required_for("wall", t.required_speed)
	for s: SpeedSign in built["signs"]:
		s.required_speed = required_for(s.kind, s.required_speed)
	# ② 設計書4章: 演出は World/Effects の下にまとめる（World の直下の数を今の確認のまま保つ）
	_fx = Node2D.new()
	_fx.name = "Effects"
	_world.add_child(_fx)
	for n: Node in _world.get_children():
		if n is Goal:
			_goal = n
	_last_segment = stage_data["start_segment"]

	_trolley = TROLLEY_SCENE.instantiate()
	_trolley.paths = built["paths"]
	_trolley.resolve_next = _resolve_next
	_trolley.type_id = trolley_id
	_trolley.paint = GameState.garage(trolley_id)["paint"]
	_trolley.speed = stat("speed_base")
	_trolley.segment_id = stage_data["start_segment"]
	(built["paths"][_trolley.segment_id] as Path2D).add_child(_trolley)
	_trolley.segment_entered.connect(_on_segment_entered)
	_trolley.goal_reached.connect(_on_goal_reached)
	_trolley.set_headlight(Tuning.TOD_HEADLIGHT[time_of_day])  # 設計書4章
	for s: SpeedSign in built["signs"]:
		s.speed_of = func() -> float: return _trolley.speed
	_combo_fx.maxed.connect(_on_combo_maxed)
	_hud_view.setup(_number, stage_data.get("name", ""))
	_combo_fx.place_tag(_hud_view.combo_position())
	# FR-36b: 試験開始バナー
	var banner: Banner = BANNER_SCENE.instantiate()
	banner.number = _number
	_hud.add_child(banner)
	# FR-36c: 第1試験だけ、最初の切替が成功するまでアクティブ分岐の上にヒントを出す（リトライで出し直す）
	if _number == 1:
		_hint = FIRST_HINT_SCENE.instantiate()
		_world.add_child(_hint)
	# ゴースト（設計書6章）: 記録はいつも、再生は設定が表示でゴーストがあるときだけ
	_ghost_rec = GhostRecorder.new()
	var ghost_data: Dictionary = GameState.ghost(_number)
	if GameState.show_ghost and not ghost_data.is_empty():
		_ghost = GhostPlayer.new()
		_ghost.z_index = Tuning.Z_TROLLEY - 1
		_world.add_child(_ghost)
		_ghost.setup(ghost_data)
	_update_active_junction()
	_update_zoom()
	_camera.position = Vector2(_camera_x(), _camera_y())
	_camera.reset_physics_interpolation()  # 最初の1フレームが原点からの補間で何も映らないのを防ぐ


## 設計書2章・4章: 奥の壁（World より奥）と、時間帯の全体の色（CanvasModulate。HUD・ポーズ・リザルトは
## CanvasLayer にあるので掛からない）。画質が低なら暗さを弱める
func _dress_stage() -> void:
	var backdrop := Backdrop.new()
	backdrop.ground_y = stage_data["ground_y"]
	backdrop.tod = time_of_day
	add_child(backdrop)
	move_child(backdrop, 0)
	var ambient := CanvasModulate.new()
	ambient.name = "Ambient"
	ambient.color = Quality.ambient(time_of_day)
	add_child(ambient)


## ステージの試験番号（バナー・HUD・リザルトの「第N試験」、初回ヒントの判定、記録の保存先）。id の数字（stage_03 → 3）
## TODO(spec): 数字が無い id（自動確認が作るステージなど）は第1試験として扱う
## 裏試験（"ex_01"）は EX_FIRST から（replay-value-design.md 1章）
static func stage_number(id: String) -> int:
	if id.begins_with("ex_"):
		return Tuning.EX_FIRST + maxi(id.to_int(), 1) - 1
	return maxi(id.to_int(), 1)


## 本試験・裏試験の最後の番号（「次の試験へ」の行き止まり）
func _last_number() -> int:
	return Tuning.STAGE_COUNT if _number < Tuning.EX_FIRST else Tuning.EX_FIRST + Tuning.EX_COUNT - 1


## この走行の車両の強化込みの性能（replay-value-design.md 5.2）
func stat(key: String) -> float:
	return Progression.stat(trolley_id, key, _upgrades)


## この走行の車両の強化込みの壁（"wall"）・ジャンプ（"jump"）の必要速度
func required_for(kind: String, required: float) -> float:
	return Progression.effective_required(trolley_id, kind, required, _upgrades)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("retry"):
		retry()  # FR-26: プレイ中・失敗演出中・リザルト中（ポーズ中はポーズ画面が受ける）
	# FR-11: アクティブ分岐がなければ何もしない
	elif event.is_action_pressed("toggle_switch") and _active != null and not _finished:
		_active.toggle()
		toggle_count += 1
		Audio.play(&"toggle")  # FR-10
		if _hint != null:  # FR-36c: 最初の切替が成功したら消す
			_hint.queue_free()
			_hint = null
	elif event.is_action_pressed("pause"):
		pause()


func _notification(what: int) -> void:
	# FR-47: ウィンドウがフォーカスを失ったら自動でポーズする
	# TODO(spec): 走っている間だけにした（失敗演出中・ゴール後はリザルトへ進ませる）
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and auto_pause and not _finished:
		pause()


## FR-44: ポーズ。木を止め、TimeScale の要求を全部捨てて time_scale を 1.0 にする（再開後も 1.0）
## TODO(spec): リザルトを出した後はポーズしない（リザルトの Esc は「ステージ選択へ」）
func pause() -> void:
	# リトライで差し替えを待っている古い画面（process_mode が DISABLED）はポーズしない（新しい画面が止まった木で始まる）
	if _pause != null or _result != null or _trolley == null or process_mode == Node.PROCESS_MODE_DISABLED:
		return
	TimeScale.clear()
	_pause = PAUSE_SCENE.instantiate()
	_pause.resume_requested.connect(resume)
	_pause.retry_requested.connect(retry)
	_pause.select_requested.connect(_to_stage_select)
	_overlay.add_child(_pause)
	if _endless != null:
		(_pause.get_node("%Select") as Button).text = "タイトルへ"  # 無限軌道はタイトルから来る
	get_tree().paused = true


func resume() -> void:
	if _pause == null:
		return
	_pause.queue_free()
	_pause = null
	get_tree().paused = false


func is_paused() -> bool:
	return _pause != null


func _to_stage_select() -> void:
	_submit_run("abort")  # 走っている途中でやめた（ポーズの「ステージ選択へ」。無限軌道は「タイトルへ」）
	get_tree().paused = false
	TimeScale.clear()
	get_tree().change_scene_to_file(TITLE_SCENE if _endless != null else STAGE_SELECT_SCENE)


## リザルトの「次の試験へ」
func _to_next_stage() -> void:
	TimeScale.clear()
	GameState.current_stage = mini(_number + 1, _last_number())
	get_tree().change_scene_to_file(scene_file_path)


## FR-26: ステージを最初からやり直す。新しいゲーム画面に差し替えるので、スコア・勢い・コンボ・標的はすべて
## 初期状態に戻る。RETRY_DEBOUNCE 秒以内の2回目以降は無視する。差し替え先を返す（無視したときは自分）
func retry() -> Node:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_retry < Tuning.RETRY_DEBOUNCE:
		return self
	_last_retry = now
	_submit_run("abort")  # 走っている途中のリトライ（走行が終わった後なら、もう出している）
	# 差し替えまでの間に古い画面が物理を1フレーム進めて smash すると、演出と効果音が新しい画面に持ち越されるので止める
	process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false  # ポーズ中からのリトライ
	TimeScale.clear()  # ヒットストップ・スローモーを持ち越さない
	var fresh: Node = (load(scene_file_path) as PackedScene).instantiate()
	fresh.stage_data = stage_data
	fresh._last_retry = now
	_replace_with.call_deferred(fresh)  # 入力の処理中に自分を木から外さない
	return fresh


func _replace_with(fresh: Node) -> void:
	var tree: SceneTree = get_tree()
	var parent: Node = get_parent()
	var was_current: bool = tree.current_scene == self
	parent.remove_child(self)
	parent.add_child(fresh)
	if was_current:
		tree.current_scene = fresh
	queue_free()


func _physics_process(delta: float) -> void:
	if _trolley == null:
		return  # ステージデータエラー
	_time += delta
	if _combo_alive and _time - _last_smash_time > combo_window():
		_combo_alive = false
		_combo_fx.on_expired(combo)
	if not _finished:
		# FR-21: 勢いは毎秒 MOMENTUM_DECAY 減る。FR-22: 目標速度 = SPEED_BASE + 勢い × SPEED_PER_MOMENTUM
		momentum = maxf(momentum - Tuning.MOMENTUM_DECAY * stat("momentum_decay") * delta, 0.0)
		_trolley.advance(delta, target_speed())
		max_speed = maxf(max_speed, _trolley.speed)
		distance += _trolley.speed * delta
		_ghost_rec.sample(_time, _trolley.global_position, _trolley.global_rotation)
		if not _finished:  # 進む途中でゴールに着いたり脱線したりしたら、当たりは見ない
			_check_hits()
	if _endless != null:
		_endless_update()
	if _ghost != null:
		_ghost.advance(_time)
	if _time >= _result_at:
		_show_result()
	_run_chain()
	_expire_bodies()
	_update_zoom()
	# FR-37, FR-39: 横はトロッコを画面左25%に固定、縦だけ平滑化して追従
	# TODO(spec): position_smoothing は縦横両方に効き、高速時にトロッコが25%の位置からずれるため、
	#             縦だけ同じ式（lerp × CAMERA_Y_SMOOTH）を手で適用した
	var y: float = lerpf(_camera.position.y, _camera_y(), minf(Tuning.CAMERA_Y_SMOOTH * delta, 1.0))
	_camera.position = Vector2(_camera_x(), y)


func _process(_delta: float) -> void:
	if _trolley != null:
		_hud_view.show_values(score, _trolley.speed, momentum)  # FR-42（コンボは ComboFx が出す）
	# FR-33: 揺れ（残り時間は shake() の Tween が減らす）
	var a: float = shake_amplitude()
	_camera.offset = Vector2(randf_range(-a, a), randf_range(-a, a))
	if _debug_label.visible and _trolley != null:
		# FR-54: FPS（Engine の値は1秒平均）と freeze 解除済み物体の数
		# TODO(spec): L-5 の到達速度の実測用に、速度（px/s）と勢いも出した。①プレイ画面の絵の重さを見るため、
		#             1フレームの描画命令の数（DRAW）も出した
		_debug_label.text = "FPS %d\nDRAW %d\nBODIES %d\nSPEED %d px/s\nMOMENTUM %d" % [
				Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				_active_bodies.size(), _trolley.speed, momentum]


## FR-22 の目標速度。車両の初速（SPEED_BASE の代わり）＋勢い × SPEED_PER_MOMENTUM、上限は車両の最高速
func target_speed() -> float:
	return minf(stat("speed_base") + momentum * Tuning.SPEED_PER_MOMENTUM,
			stat("speed_max"))


## FR-28 のコンボの受付時間（車両の倍率を掛けた COMBO_WINDOW）
func combo_window() -> float:
	return Tuning.COMBO_WINDOW * stat("combo_window")


## FR-16 の爆発の範囲（車両の倍率を掛けた EXPLOSION_RADIUS）
func blast_radius() -> float:
	return Tuning.EXPLOSION_RADIUS * stat("blast_radius")


## その車両の★2・★3 の閾値
func _thresholds() -> Array:
	return Trolleys.thresholds(trolley_id, stage_data.get("star_thresholds", []))


## その車両の金★の閾値（replay-value-design.md 3.2。ステージに無ければ 0 = 取れない）
func _gold_threshold() -> int:
	var t: Variant = stage_data.get("gold_threshold", 0)
	return roundi(float(t) * Trolleys.stat(trolley_id, "star_scale")) if (t is int or t is float) else 0


## FR-28: 倍率 = min(1.0 + floor(combo / 5) × 0.5, 3.0)
static func combo_multiplier(c: int) -> float:
	return minf(1.0 + floorf(float(c) / Tuning.COMBO_STEP) * Tuning.COMBO_STEP_BONUS, Tuning.COMBO_MULT_MAX)


## FR-33: 振幅 amp で揺らし、SHAKE_DECAY 秒で0へ線形に減らす。揺れ中なら大きい方で上書きする。
## FR-36: 設定の「画面の揺れ」が OFF なら揺らさない
func shake(amp: float) -> void:
	if not GameState.screen_shake or amp < shake_amplitude():
		return
	_shake_amp = amp
	_shake_left = Tuning.SHAKE_DECAY
	# TODO(spec): 減衰を数える時間は仕様に無い。実時間で数える（ヒットストップ中も揺れが止まらないように）。
	# time_scale を無視する Tween で減らす（ヒットストップを始めたフレームは delta と time_scale が食い違うので、
	# delta / time_scale で数えると、その場で揺れが0になる）
	if _shake_tween != null:
		_shake_tween.kill()
	_shake_tween = create_tween().set_ignore_time_scale(true)
	_shake_tween.tween_property(self, "_shake_left", 0.0, Tuning.SHAKE_DECAY)


func shake_amplitude() -> float:
	return _shake_amp * _shake_left / Tuning.SHAKE_DECAY


## FR-38: 速度 SPEED_BASE で ZOOM_AT_BASE、SPEED_MAX で ZOOM_AT_MAX。その間は線形
## TODO(spec): SPEED_MAX より速い車両（試作型）では、同じ傾きのまま引き、ZOOM_MIN で止める（FR-38 は SPEED_MAX までしか
##             決めていない。引かないと、分岐の1秒前に判断材料が画面に入らない〔L-3〕。trolleys-and-display-design.md）
func _update_zoom() -> void:
	var t: float = maxf(inverse_lerp(Tuning.SPEED_BASE, Tuning.SPEED_MAX, _trolley.speed), 0.0)
	_camera.zoom = Vector2.ONE * maxf(lerpf(Tuning.ZOOM_AT_BASE, Tuning.ZOOM_AT_MAX, t), Tuning.ZOOM_MIN)


func _camera_x() -> float:
	var view_w: float = get_viewport_rect().size.x / _camera.zoom.x
	return _focus().x + view_w * (0.5 - Tuning.CAMERA_TROLLEY_SCREEN_X)


## 縦はトロッコを画面上端から CAMERA_TROLLEY_SCREEN_Y の高さに置く
func _camera_y() -> float:
	var view_h: float = get_viewport_rect().size.y / _camera.zoom.y
	return _focus().y + view_h * (0.5 - Tuning.CAMERA_TROLLEY_SCREEN_Y)


## カメラが追う位置。TODO(spec): 失敗後は転がるトロッコ（FR-25）を追うことにした
func _focus() -> Vector2:
	return _wreck.global_position if _wreck != null else _trolley.global_position


## 分岐の選択先はトロッコが到達したこの瞬間の状態で確定する（FR-8）
func _resolve_next(id: String) -> String:
	var end: Dictionary = _segments[id]["end"]
	match end["type"]:
		"junction":
			var j: Junction = _junctions[end["id"]]
			return j.branches[j.selected]
		"next":
			return end["segment"]
	return ""


func _on_segment_entered(id: String) -> void:
	_update_active_junction()
	# ② 設計書3章: ジャンプから着地した（1つ前がジャンプの区間）。砂ぼこりと小さな揺れ
	if (_segments.get(_last_segment, {}) as Dictionary).has("jump") and not _finished:
		Fx.puffs(_fx, _trolley.global_position, "dust")
		shake(Tuning.LANDING_SHAKE)
	_last_segment = id
	var jump: Dictionary = _segments[id].get("jump", {})
	_trolley.airborne = not jump.is_empty()
	if jump.is_empty():
		return
	# FR-23: 進入した瞬間の速度が必要速度以上なら通過、未満なら脱線
	var required: float = required_for("jump", jump["required_speed"])
	if _trolley.speed < required:
		_fail("脱線", required)
	else:
		var start: Vector2 = (_trolley.paths[id] as Path2D).curve.get_point_position(0)
		_check_girigiri(_trolley.speed - required, start + Vector2(0.0, -Tuning.SIGN_JUMP_HEIGHT))


## FR-6: 現在のセグメントから合流をたどって最初に着く分岐をアクティブにする
func _update_active_junction() -> void:
	var found: Junction = null
	var id: String = _trolley.segment_id
	for _i: int in _segments.size():  # 循環は検証（6.4）で弾くが、念のため上限を付ける
		var end: Dictionary = _segments[id]["end"]
		if end["type"] == "junction":
			found = _junctions[end["id"]]
			break
		if end["type"] != "next":
			break
		id = end["segment"]
	if found == _active:
		return
	if _active != null:
		_active.active = false
	_active = found
	if _active != null:
		_active.active = true
	if _hint != null:
		_hint.visible = _active != null
		if _active != null:
			_hint.position = _active.global_position + Vector2(0.0, -Tuning.HINT_HEIGHT)  # World は原点


## FR-13: HitArea に触れている未破壊の標的を1個ずつ smash する（1フレームに複数でも個別に、10章）。
## 接触の通知（body_entered）の中では物理の状態を変えられないので、毎物理フレーム重なりを調べる
func _check_hits() -> void:
	for body: Node2D in _trolley.hit_area.get_overlapping_bodies():
		if _finished:
			return  # 激突した
		if body is Target:
			_smash(body, _hit_impulse)


## FR-13 の順に処理する: freeze解除 → 衝撃付与 → smashed = true → 得点加算 → 勢い加算。
## impulse_at は物体の中心を受け取り、その物体に与える衝撃を返す。
## chained: drum の爆発に巻き込まれた（トロッコは触れていない。drum なら少し遅れて爆発する、FR-17）
func _smash(t: Target, impulse_at: Callable, chained: bool = false) -> void:
	if t.smashed:
		return  # FR-15
	# FR-18: トロッコが必要速度未満で wall に触れたら激突
	# TODO(spec): 爆発に巻き込まれた wall の扱いは仕様に無い。FR-16「範囲内の未破壊標的は smash 扱い」に従い、
	#             速度を問わず壊す（ギリギリ突破の判定もしない）
	var speed: float = _trolley.speed
	var by_trolley_wall: bool = t.kind == "wall" and not chained
	if by_trolley_wall and speed < t.required_speed:
		_fail("激突", t.required_speed)
		return
	var at: Vector2 = t.center()
	var sign_at: Vector2 = t.to_global(Vector2(0.0, -t.body_size().y - Tuning.SIGN_WALL_GAP))
	_targets.erase(t)
	if t.kind == "wall":
		# FR-18: レンガ片に置き換えて飛ばす
		var piece_h: float = (Tuning.TARGET_SIZE["brick_piece"] as Vector2).y
		for i: int in Tuning.WALL_PIECES:
			var piece: Target = BRICK_PIECE_SCENE.instantiate()
			piece.transform = t.global_transform.translated_local(Vector2(0.0, -piece_h * i))
			_world.add_child(piece)
			piece.reset_physics_interpolation()
			_launch(piece, impulse_at)
		t.queue_free()
	else:
		_launch(t, impulse_at)
	t.smashed = true
	smashed_count += 1
	smashed_by_kind[t.kind] = smashed_by_kind.get(t.kind, 0) + 1
	if chained and t.kind == "drum":
		chained_count += 1
	var base: int = Tuning.TARGET_POINTS[t.kind]
	_add_score(base, at)
	momentum = minf(momentum + Tuning.TARGET_MOMENTUM[t.kind] * stat("momentum_gain"),
			Tuning.MOMENTUM_MAX)  # FR-21
	_smash_effects(t.kind, base, at, impulse_at.call(at))
	if by_trolley_wall:
		_check_girigiri(speed - t.required_speed, sign_at)
	if t.kind != "drum":
		return
	if chained:
		_chain.append([t, _time + Tuning.EXPLOSION_CHAIN_DELAY])
	else:
		_explode(t)


## smash の演出: ヒットストップ（FR-30）、揺れ（FR-33）、破片（FR-34）、効果音（FR-51）。push は物体に与えた衝撃の向き
func _smash_effects(kind: String, base: int, at: Vector2, push: Vector2) -> void:
	if base >= Tuning.HITSTOP_MIN_POINTS:
		TimeScale.request(Tuning.HITSTOP_SCALE, Tuning.HITSTOP_DURATION)
		Audio.play(&"hit_big")
	else:
		Audio.play(&"hit_small")
	if kind == "wall":
		Audio.play(&"wall_break")
	shake(minf(Tuning.SHAKE_BASE + base / Tuning.SHAKE_DIV, Tuning.SHAKE_MAX))
	var dir: Vector2 = push.normalized() if push != Vector2.ZERO else Tuning.HIT_DIRECTION.normalized()
	_burst(at, dir, kind)
	# ② 設計書3章: 衝突の星と、種類ごとの壊れ方（ダミー人形は形を保つので破片を出さない、2.3）
	Fx.impact(_fx, at, base)
	match kind:
		"crate":
			Fx.shards(_fx, at, "plank", dir)
		"barrel":
			Fx.shards(_fx, at, "stave", dir)
		"wall", "dummy":
			Fx.puffs(_fx, at, "dust")


## FR-34: smash 位置に破片のパーティクル（PARTICLE_AMOUNT 個、寿命 PARTICLE_LIFETIME 秒、one_shot）。
## 衝撃の向きに飛ばし、色は標的の主な色
## TODO(spec): FR-34 の個数は16個。画質が中・低なら減らす（trolleys-and-display-design.md 4章の「パーティクル」）
func _burst(at: Vector2, dir: Vector2, kind: String) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.z_index = Tuning.Z_PARTICLES
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = Quality.count(Tuning.PARTICLE_AMOUNT)
	p.lifetime = Tuning.PARTICLE_LIFETIME
	p.direction = dir
	p.spread = Tuning.PARTICLE_SPREAD_DEG
	p.initial_velocity_min = Tuning.PARTICLE_SPEED_MIN
	p.initial_velocity_max = Tuning.PARTICLE_SPEED_MAX
	p.gravity = Tuning.PARTICLE_GRAVITY
	p.scale_amount_min = Tuning.PARTICLE_SIZE_MIN
	p.scale_amount_max = Tuning.PARTICLE_SIZE_MAX
	p.color = Palette.DEBRIS_COLORS[kind]
	p.finished.connect(p.queue_free)
	_world.add_child(p)
	p.emitting = true


## FR-17: 予定の時刻になった連鎖待ちの drum を爆発させる。ゲーム内時刻で数えるので、
## ポーズ中は止まり、スローモー中は遅くなり、連鎖の何段目でも間隔がそろう
func _run_chain() -> void:
	var due: Array[Target] = []
	var waiting: Array = []
	for e: Array in _chain:
		if not is_instance_valid(e[0]):
			continue  # 待っている間に上限（NFR-2）で消された
		if _time >= e[1]:
			due.append(e[0])
		else:
			waiting.append(e)
	_chain = waiting
	for d: Target in due:
		_explode(d)


func _launch(b: Target, impulse_at: Callable) -> void:
	b.launch(impulse_at.call(b.center()), randf_range(-Tuning.ANG_VEL_MAX, Tuning.ANG_VEL_MAX), _time)
	_active_bodies.append(b)
	# NFR-2: 上限を超えたら最も古いものから消す
	while _active_bodies.size() > Tuning.MAX_ACTIVE_BODIES:
		_active_bodies.pop_front().queue_free()


## FR-14: 右上向きを ±HIT_ANGLE_JITTER_DEG 度回し、大きさは HIT_BASE + 速度 × HIT_SPEED_FACTOR
func _hit_impulse(_at: Vector2) -> Vector2:
	var jitter: float = deg_to_rad(randf_range(-Tuning.HIT_ANGLE_JITTER_DEG, Tuning.HIT_ANGLE_JITTER_DEG))
	return Tuning.HIT_DIRECTION.normalized().rotated(jitter) * (Tuning.HIT_BASE + _trolley.speed * Tuning.HIT_SPEED_FACTOR) \
			* stat("hit_power")


## FR-16: 半径内の物体を、中心からの距離で線形に弱まる衝撃で飛ばす。未破壊の標的は smash 扱い
## TODO(spec): 「半径内」は物体の中心までの距離で判定。巻き込まれた標的の回転は FR-14 と同じ乱数にした
func _explode(drum: Target) -> void:
	if drum.exploded:
		return  # FR-17: 1つの drum が爆発するのは1回だけ
	drum.exploded = true
	var origin: Vector2 = drum.center()
	var impulse_at := func(at: Vector2) -> Vector2: return _explosion_impulse(origin, at)
	# 先に対象を決める（この爆発で飛ばし始めた物に二重に衝撃を与えないため）
	# TODO(spec): 爆発した drum 自身は向きが決まらないので、自分の爆発の衝撃を受けない
	var flying: Array[Target] = []
	for b: Target in _active_bodies:
		if b != drum and b.center().distance_to(origin) <= blast_radius():
			flying.append(b)
	var caught: Array[Target] = []
	for t: Target in _targets:
		if t.center().distance_to(origin) <= blast_radius():
			caught.append(t)
	exploded.emit(drum)
	TimeScale.request(Tuning.SLOWMO_SCALE, Tuning.SLOWMO_DURATION)  # FR-31
	Audio.play(&"explosion")
	Fx.explosion(_fx, origin, blast_radius())  # ② 設計書3章: 火の玉・衝撃波の輪・煙・金属の破片・閃光
	for b: Target in flying:
		b.apply_central_impulse(impulse_at.call(b.center()))
	if _wreck != null:  # 失敗後に転がっているトロッコも「すべての RigidBody2D」に入る
		var wc: Vector2 = _wreck.to_global(Vector2(0.0, -Tuning.TROLLEY_H * 0.5))
		if wc.distance_to(origin) <= blast_radius():
			_wreck.apply_central_impulse(impulse_at.call(wc))
	for t: Target in caught:
		_smash(t, impulse_at, true)


func _explosion_impulse(origin: Vector2, at: Vector2) -> Vector2:
	var d: Vector2 = at - origin
	var strength: float = Tuning.EXPLOSION_IMPULSE * maxf(1.0 - d.length() / blast_radius(), 0.0)
	return (d.normalized() if d != Vector2.ZERO else Vector2.UP) * strength


## FR-27, FR-28: 得点 = 基本点 × コンボ倍率（切り捨て）。前回から COMBO_WINDOW 秒以内ならコンボ+1、超えたら1
func _add_score(base: int, at: Vector2) -> void:
	combo = combo + 1 if _time - _last_smash_time <= combo_window() else 1
	max_combo = maxi(max_combo, combo)
	_last_smash_time = _time
	var mult: float = combo_multiplier(combo)
	var points: int = int(floorf(base * mult))
	score += points
	# FR-35: 得点ポップアップ
	var popup: ScorePopup = SCORE_POPUP_SCENE.instantiate()
	popup.position = at
	popup.points_text = "+%d" % points
	popup.mult_text = "x%.1f" % mult if mult > 1.0 else ""
	_world.add_child(popup)
	_combo_alive = true
	_combo_fx.on_smash(combo, mult, mult > combo_multiplier(combo - 1))


## コンボの倍率が最大に届いた（依頼者の追加要望。仕様に無いので、スローモーと揺れの値は仮）
func _on_combo_maxed() -> void:
	TimeScale.request(Tuning.COMBO_MAX_SLOWMO_SCALE, Tuning.COMBO_MAX_SLOWMO_DURATION)
	shake(Tuning.COMBO_MAX_SHAKE)


## FR-36a: wall の突破・jump の通過で、速度の余裕（速度 − 必要速度）が GIRIGIRI_MARGIN 未満なら
## GIRIGIRI_BONUS を足す（倍率は掛けない）。sign_at は必要速度標識の下端
## TODO(spec): 「その位置」は必要速度標識の位置とした（wall の中心では得点ポップアップと重なる）
func _check_girigiri(margin: float, sign_at: Vector2) -> void:
	if margin >= Tuning.GIRIGIRI_MARGIN * stat("girigiri_margin"):
		return
	score += Tuning.GIRIGIRI_BONUS
	girigiri_count += 1
	Audio.play(&"girigiri")
	var label: Girigiri = GIRIGIRI_SCENE.instantiate()
	label.position = sign_at + Vector2(0.0, -Tuning.SIGN_SIZE.y * 0.5)
	_world.add_child(label)


## FR-25: トロッコを同じ見た目の物理ボディに置き換えて失敗時点の速度で転がし、画面中央に「激突！」「脱線！」を出し、
## FAIL_DELAY 秒（ゲーム内時刻。ポーズ中は進まない）後に失敗版リザルトを出す。required は壁・ジャンプの必要速度
func _fail(reason: String, required: float) -> void:
	if _finished:
		return
	_finished = true
	fail_reason = reason
	_fail_required = required
	_fail_speed = _trolley.speed
	_submit_run("crash" if reason == "激突" else "derail")
	_result_at = _time + Tuning.FAIL_DELAY
	_wreck = WRECK_SCENE.instantiate()
	_wreck.type_id = trolley_id
	_wreck.paint = _trolley.paint
	_wreck.transform = _trolley.global_transform  # World は原点・無回転
	_world.add_child(_wreck)
	_wreck.reset_physics_interpolation()
	_wreck.linear_velocity = Vector2.RIGHT.rotated(_trolley.global_rotation) * _trolley.speed
	_trolley.hide()
	Audio.play(&"crash" if reason == "激突" else &"derail")
	# ② 設計書3章: 車体の前に大きめの衝突の星・火花（光る）・砂ぼこり、カメラの揺れ（揺れ OFF なら揺らさない）
	var front: Vector2 = _trolley.to_global(Vector2(Tuning.TROLLEY_TOP_W * 0.5, -Tuning.TROLLEY_H * 0.5))
	Fx.impact(_fx, front, Tuning.FAIL_IMPACT_POINTS)
	Fx.shards(_fx, front, "spark", Vector2.UP.rotated(_trolley.global_rotation))
	Fx.puffs(_fx, front, "dust")
	shake(Tuning.FAIL_SHAKE)
	# 16.6: 拡大率 FAIL_POP_SCALE → 1.0 で出る
	_fail_text.text = reason + "！"
	_fail_text.pivot_offset = _fail_text.size * 0.5
	_fail_text.scale = Vector2.ONE * Tuning.FAIL_POP_SCALE
	_fail_text.show()
	create_tween().tween_property(_fail_text, "scale", Vector2.ONE, Tuning.FAIL_POP_TIME)


## NFR-2: freeze 解除から DEBRIS_LIFETIME 秒たった物と、カメラ左端より DEBRIS_BEHIND_LIMIT px 以上後ろの物を消す
func _expire_bodies() -> void:
	var left: float = _camera.position.x - get_viewport_rect().size.x / _camera.zoom.x * 0.5 - Tuning.DEBRIS_BEHIND_LIMIT
	for b: Target in _active_bodies.duplicate():
		if _time - b.unfrozen_at >= Tuning.DEBRIS_LIFETIME or b.global_position.x < left:
			_active_bodies.erase(b)
			b.queue_free()


func _on_goal_reached() -> void:
	if _finished:
		return  # 10章: 失敗が優先（同じフレームで脱線した後にゴールへ着いても、クリアにしない）
	_finished = true
	Audio.play(&"goal")
	# FR-29, FR-49: クリアの記録はゴールに着いた時点で保存する（リザルトを待たずにリトライしても残る）
	var stars: int = Display.stars_for(true, score, _thresholds())
	_gold = Display.gold_for(true, score, _gold_threshold())
	_best_updated = GameState.submit_clear(_number, score, stars, trolley_id, _gold)
	# 課題（設計書 3.1）と ゴースト（6章）。検定印（課題の数）が見られるよう _submit_run の前
	_new_challenges = GameState.submit_challenges(_number, stage_data.get("challenges", []), _run_record("clear"))
	var ghost: Dictionary = _ghost_rec.data()
	ghost.merge({"score": score, "trolley": trolley_id, "paint": _trolley.paint}, true)
	GameState.submit_ghost(_number, ghost)
	_submit_run("clear")  # 検定印の「合格」系が今の合格を見られるよう、submit_clear の後
	# TODO(spec): ゴールに着いたときの表示は仕様に無い。「GOAL」を出し、GOAL_RESULT_DELAY 秒後にリザルトへ
	_show_message("GOAL")
	_result_at = _time + Tuning.GOAL_RESULT_DELAY
	# ② 設計書3章: テープが切れて、試験報告書の紙吹雪。「GOAL」は判子のように押す
	_trolley.stop_fx()
	if _goal != null:
		_goal.snap()
		Fx.shards(_fx, _goal.global_position + Vector2(0.0, Tuning.GOAL_SIGN.position.y), "paper", Vector2.UP)
	_message.pivot_offset = _message.size * 0.5
	_message.scale = Vector2.ONE * Tuning.GOAL_MESSAGE_POP
	create_tween().set_ignore_time_scale(true).tween_property(_message, "scale", Vector2.ONE, Tuning.GOAL_MESSAGE_POP_TIME)


## リザルト（FR-45, FR-46）を重ねて出す。ゲーム画面は後ろに残り、R（retry）はこのまま受ける
func _show_result() -> void:
	if _endless != null:
		_endless_show_result()
		return
	_result_at = INF
	_result = (load(RESULT_SCENE) as PackedScene).instantiate()
	_result.setup(result_data())
	_result.retry_requested.connect(retry)
	_result.next_requested.connect(_to_next_stage)
	_result.select_requested.connect(_to_stage_select)
	_overlay.add_child(_result)


## リザルトに渡す記録（キーはリザルト画面との約束事）
func result_data() -> Dictionary:
	var cleared: bool = fail_reason.is_empty()
	var thresholds: Array = _thresholds()
	return {
		"stage": _number,
		"stage_name": stage_data.get("name", ""),
		"cleared": cleared,
		"score": score,
		"smashed": smashed_count,
		"total": total_targets,
		"max_combo": max_combo,
		"max_speed": max_speed,
		"girigiri": girigiri_count,
		"stars": Display.stars_for(cleared, score, thresholds),
		"thresholds": thresholds,
		"title": Display.stage_title(_number),
		"gold": _gold,
		"gold_threshold": _gold_threshold(),
		"challenges": _challenge_rows(),  # [{"text", "done", "new"}] × CHALLENGE_COUNT（設計書 3.1）
		"xp": _xp,  # この走行の熟練度（設計書 5.1）
		"best_updated": _best_updated,
		# 「次の試験へ」を出さない: 最終ステージか、次が解放されていない（プレイ中に記録を消した）とき
		"is_last": _number >= _last_number() or not GameState.is_unlocked(_number + 1),
		"fail_reason": fail_reason,
		"required_speed": _fail_required,
		"reached_speed": _fail_speed,
		"new_stamps": _new_stamps,  # この走行で新しく取った検定印の id（設計書 3.2）
		"certificate": _new_stamps.has("all_clear"),  # この走行で全試験の合格がそろった（修了証書、設計書 3.3）
		"trolley": trolley_id,  # 使った車両（trolleys-and-display-design.md 3章）
		"new_trolleys": _new_trolleys,  # この走行で新しく解放された車両（Trolleys.IDS の順）
	}


## 設計書 2.2: 走行1回分の記録を GameState に出す。ゴール・失敗・途中でやめたときの、最初の1回だけ
## （ステージデータエラーで走っていないときは出さない）
func _submit_run(outcome: String) -> void:
	if _run_sent or _trolley == null:
		return
	_run_sent = true
	var run: Dictionary = _run_record(outcome)
	if _endless != null:  # 検定印（長距離運転）が今の距離を見られるよう、submit_run の前
		_endless_best = GameState.submit_endless(score, distance, trolley_id)
	_xp = GameState.add_xp(trolley_id, Progression.xp_for_run(run))  # 熟練度（設計書 5.1）。検定印の段より前
	_new_stamps = GameState.submit_run(run)
	var now: Array[String] = GameState.unlocked_trolleys()
	_new_trolleys.assign(now.filter(func(id: String) -> bool: return not _unlocked_before.has(id)))


## 走行1回分の記録（records-design.md 2.2 に、課題の判定に要る "trolley"・"total"・"smashed_count" を足したもの）
func _run_record(outcome: String) -> Dictionary:
	return {
		"stage": _number,
		"outcome": outcome,
		"smashed": smashed_by_kind,
		"girigiri": girigiri_count,
		"max_combo": max_combo,
		"max_speed": max_speed,
		"distance": distance,
		"chained": chained_count,
		"toggles": toggle_count,
		"score": score,
		"trolley": trolley_id,
		"total": total_targets,
		"smashed_count": smashed_count,
	}


## リザルトの課題の行（ステージに課題が無ければ空）
func _challenge_rows() -> Array:
	var rows: Array = []
	var list: Array = stage_data.get("challenges", [])
	var done: Array[bool] = GameState.challenges(_number)
	for i: int in mini(list.size(), Tuning.CHALLENGE_COUNT):
		rows.append({"text": Challenges.describe(list[i]), "done": done[i], "new": _new_challenges.has(i)})
	return rows


func _show_message(text: String) -> void:
	_message.text = text
	_message.show()


# --- 無限軌道（replay-value-design.md 7章）。GameState.endless のとき _ready の代わりに組む ---
# 試験の番号は 0（試験記録の累計には入る。試験ごとの回数・ゴースト・初回ヒント・課題・金★は無し）。ゴールは無く、
# 激突・脱線で終わる。区間（Endless）をトロッコの先に ENDLESS_PARTS_AHEAD 個組んでおき、通り過ぎた区間は消す

## 車両・強化・塗装は選んでいるもの。走るたびに乱数の種を変える（リトライでも別の線路）
## TODO(spec): 時間帯は設定の決め方のまま（試験の番号 0 なので「順に進む」なら朝。JSON の time_of_day は無い）
func _endless_ready() -> void:
	trolley_id = GameState.trolley()
	_upgrades = GameState.garage(trolley_id)["upgrades"]
	_unlocked_before = GameState.unlocked_trolleys()
	_number = 0
	_endless = Endless.new(trolley_id, randi())
	stage_data = _endless.data
	_segments = stage_data["segments"]
	time_of_day = GameState.time_of_day(_number, stage_data)
	Quality.level = GameState.quality
	_dress_stage()
	# 地面の当たりは1つ（WorldBoundaryShape2D は横に果てしない）。見た目は区間ごと（StageLoader.build_part）
	var ground := StaticBody2D.new()
	ground.name = "Ground"
	ground.position = Vector2(0.0, stage_data["ground_y"])
	ground.collision_layer = Tuning.LAYER_GROUND
	ground.collision_mask = 0
	var col := CollisionShape2D.new()
	col.shape = WorldBoundaryShape2D.new()
	ground.add_child(col)
	_world.add_child(ground)
	_fx = Node2D.new()
	_fx.name = "Effects"
	_world.add_child(_fx)
	_trolley = TROLLEY_SCENE.instantiate()
	_trolley.resolve_next = _resolve_next
	_trolley.type_id = trolley_id
	_trolley.paint = GameState.garage(trolley_id)["paint"]
	_trolley.speed = stat("speed_base")
	for _i: int in Tuning.ENDLESS_PARTS_AHEAD + 1:
		_endless_add_part()
	_trolley.segment_id = stage_data["start_segment"]
	_last_segment = _trolley.segment_id
	(_trolley.paths[_trolley.segment_id] as Path2D).add_child(_trolley)
	_trolley.segment_entered.connect(_on_segment_entered)
	_trolley.goal_reached.connect(_on_goal_reached)  # 先に区間を足しておくので着かない
	_trolley.set_headlight(Tuning.TOD_HEADLIGHT[time_of_day])
	_combo_fx.maxed.connect(_on_combo_maxed)
	_hud_view.setup(_number, "")
	_combo_fx.place_tag(_hud_view.combo_position())
	# HUD の見出し: 試験の札の場所に「無限軌道」と距離（HUD の絵は担当 C の持ち物なので、上に重ねて描く）
	# TODO(spec): 下の「第0試験」を隠すため、札の地は半透明でなく墨で塗りつぶした
	_endless_title = Control.new()
	_endless_title.name = "EndlessTitle"
	_endless_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_endless_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_endless_title.draw.connect(_endless_draw_title)
	_hud_view.add_child(_endless_title)
	_ghost_rec = GhostRecorder.new()  # 記録はするが残さない（ゴーストは出さない）
	_update_active_junction()
	_update_zoom()
	_camera.position = Vector2(_camera_x(), _camera_y())
	_camera.reset_physics_interpolation()


## 次の区間を組んで、トロッコの行き先・分岐・標的・標識に足す
func _endless_add_part() -> void:
	var part: Dictionary = _endless.add_part()
	var built: Dictionary = StageLoader.build_part(part, _world, stage_data["ground_y"], time_of_day)
	_trolley.paths.merge(built["paths"])
	_junctions.merge(built["junctions"])
	var targets: Array[Target] = []
	targets.assign(built["targets"])
	for t: Target in targets:
		if t.kind == "wall":
			t.required_speed = required_for("wall", t.required_speed)
	for s: SpeedSign in built["signs"]:
		s.required_speed = required_for(s.kind, s.required_speed)
		s.speed_of = func() -> float: return _trolley.speed
	_targets.append_array(targets)
	total_targets += targets.size()
	_endless_nodes.append({"node": built["node"], "targets": targets})
	_world.move_child(_fx, -1)  # 演出は後から足した区間より手前


## 一番古い区間を消す（残っている標的・吹っ飛んでいる標的も一緒に。レンガ片は World の下で寿命で消える）
func _endless_remove_part() -> void:
	var part: Dictionary = _endless.remove_part()
	var e: Dictionary = _endless_nodes.pop_front()
	for t: Variant in e["targets"]:  # 壊れた壁・寿命で消えた物は解放済み
		if is_instance_valid(t):
			_targets.erase(t)
			_active_bodies.erase(t)
	for id: String in part["segments"]:
		_trolley.paths.erase(id)
	for id: String in part["junctions"]:
		_junctions.erase(id)
	(e["node"] as Node).queue_free()


## 毎物理フレーム: 先の区間を足し、カメラの左端より DEBRIS_BEHIND_LIMIT 以上後ろに抜けた区間を消し、見出しの距離を直す
func _endless_update() -> void:
	var here: int = _endless.part_of(_trolley.segment_id)
	while int(_endless.parts.back()["index"]) - here < Tuning.ENDLESS_PARTS_AHEAD:
		_endless_add_part()
	var left: float = _camera.position.x - get_viewport_rect().size.x / _camera.zoom.x * 0.5 - Tuning.DEBRIS_BEHIND_LIMIT
	while int(_endless.parts[0]["index"]) < here and (_endless.parts[0]["ground"] as Vector2).y < left:
		_endless_remove_part()
	var m: int = roundi(distance * Tuning.DISPLAY_METERS_PER_PX)
	if m != _endless_shown_m:
		_endless_shown_m = m
		_endless_title.queue_redraw()


## HUD の見出し: 試験の札と同じ場所・同じ字で「無限軌道」（警告黄）と走った距離（生成り）
func _endless_draw_title() -> void:
	var c: Control = _endless_title
	var r: Rect2 = Tuning.HUD_STAGE_RECT
	r.position.x = (c.size.x - r.size.x) * 0.5
	c.draw_rect(r, Palette.INK)
	var fs: int = Tuning.HUD_STAGE_FONT_SIZE
	var head: String = "無限軌道"
	var dist: String = Display.distance_text(distance)
	var head_w: float = Fonts.BIZ_BOLD.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var dist_w: float = Fonts.courier.get_string_size(dist, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x: float = r.get_center().x - (head_w + Tuning.HUD_STAGE_GAP + dist_w) * 0.5
	var mid: float = r.get_center().y
	for part: Array in [[Fonts.BIZ_BOLD, head, x, Palette.HAZARD], [Fonts.courier, dist, x + head_w + Tuning.HUD_STAGE_GAP, Palette.PAPER]]:
		var font: Font = part[0]
		var baseline: float = mid + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
		c.draw_string(font, Vector2(part[2], baseline), part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, part[3])


func endless_title_text() -> String:
	return "無限軌道 " + Display.distance_text(distance)


## 無限軌道のリザルト（scenes/endless_result.tscn）を重ねる。R はこのまま retry、「タイトルへ」・Esc はタイトルへ
func _endless_show_result() -> void:
	_result_at = INF
	var r: Dictionary = result_data()
	var best: Dictionary = GameState.endless_record(trolley_id)
	_result = (load(ENDLESS_RESULT_SCENE) as PackedScene).instantiate()
	_result.setup({"score": score, "distance": distance, "best_score": best["best_score"], "best_distance": best["best_distance"],
			"best_updated": _endless_best, "xp": r["xp"], "new_stamps": r["new_stamps"], "new_trolleys": r["new_trolleys"],
			"trolley": trolley_id, "fail_reason": fail_reason})
	_result.retry_requested.connect(retry)
	_result.title_requested.connect(_endless_to_title)
	_overlay.add_child(_result)


func _endless_to_title() -> void:
	get_tree().paused = false
	TimeScale.clear()
	get_tree().change_scene_to_file(TITLE_SCENE)
