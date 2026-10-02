extends SceneTree
## 受け入れ基準の自動確認（M1: AC-1〜AC-4、M2: AC-5, AC-6, AC-10、M3: AC-7〜AC-9, AC-18, AC-19、
## M4: AC-11, AC-13 ほか）。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks.gd （失敗があれば終了コード1）
## M2 以降の確認は物理エンジンを実際のフレームで進める。--fixed-fps 60 を付けると待たずに進む。
## DEBUG_FIXED_SPEED を使う AC は、トロッコの fixed_speed（その初期値）を書き換えて確かめる。
## ヒットストップ・スローモー（M4）で1フレームのゲーム内時間が変わるので、時間はゲーム内時刻（Game._time）で見る。
## AC-13 の確認は効果音を読まない状態にするので、12キーぶんの警告（WARNING）が出る。

const DT: float = 1.0 / 60.0
const MAX_FRAMES: int = 10000
const GAME_SCENE: String = "res://scenes/game.tscn"
const EXAMPLE_STAGE: String = "res://tests/example_stage.json"  # 仕様書6.2の例（id は stage_01。本物のステージ1とは別）
const GROUND_Y: float = 900.0
const RAIL_Y: float = 600.0
const TEST_SETTINGS: String = "user://checks_settings.cfg"
const TEST_SAVE: String = "user://checks_save.cfg"

var _failed: int = 0
var _games: Array = []  # この確認で作ったゲーム（解放済みも入る）
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前（GameState など）では参照できない
var _game_state: Node
var _time_scale: Node
var _audio: Node


func _initialize() -> void:
	_run.call_deferred()  # _initialize の時点では root がまだツリーに無く、_ready が走らない


func _run() -> void:
	var checks: Array[Callable] = [
		_check_toggle_before_junction, _check_toggle_after_junction, _check_carry_over,
		_check_crate, _check_drum_chain, _check_chain_interval, _check_combo, _check_all_kinds,
		_check_body_cap, _check_behind_limit,
		_check_momentum, _check_wall, _check_girigiri, _check_jump, _check_sign, _check_retry_playing,
		_check_retry_failed,
		_check_time_scale, _check_shake, _check_particles, _check_zoom, _check_banner, _check_hint, _check_se,
		_check_missing_sfx, _check_combo_fx,
		_check_hud, _check_pause, _check_pause_settings, _check_auto_pause, _check_result_fail, _check_result_clear,
		_check_stage_error, _check_settings_persist, _check_review_fixes]
	_game_state = root.get_node("GameState")
	_time_scale = root.get_node("TimeScale")
	_audio = root.get_node("Audio")
	# ゴールすると記録を保存するので、遊んでいる人の設定・記録を上書きしないよう確認用のファイルに差し替える
	var real_settings: String = _game_state.settings_path
	var real_save: String = _game_state.save_path
	_game_state.settings_path = TEST_SETTINGS
	_game_state.save_path = TEST_SAVE
	_remove_test_files()
	_game_state.load_records()
	_game_state.screen_shake = true  # 遊んでいる人の設定（揺れ OFF かもしれない）に左右されないように。保存はしない
	for check: Callable in checks:
		# 各確認は最後に true を返す。スクリプトエラーで止まると null が返る
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
		# 途中で止まった確認のゲームが残ると、そのトロッコが次の確認の標的を壊すので消す
		for game: Variant in _games:  # 型を付けると、解放済みのゲームを受けたときに止まる
			if is_instance_valid(game):
				(game as Node).free()
		_games.clear()
		_time_scale.clear()  # 消したゲームのヒットストップ・スローモーを次の確認に持ち越さない
		_game_state.screen_shake = true
		paused = false
	_remove_test_files()
	_game_state.settings_path = real_settings
	_game_state.save_path = real_save
	_game_state.load_settings()
	_game_state.load_records()
	# 鳴っている効果音を止めてから終える。--fixed-fps では実時間がほとんど進まず、止めた音を片付ける音声スレッドが
	# 回る前に終わってしまう（終了時に「resources still in use」が出る）ので、少しだけ実時間で待つ
	for p: Node in _audio.get_children():
		(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	await _frames(2)
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# --- M1（物理を使わないので _physics_process を手で呼んで進める） ---

# AC-1: 分岐の手前で切り替えると、矢印が反対を指し、反対側の出口へ進む
func _check_toggle_before_junction() -> bool:
	var game: Node = _new_game(StageLoader.load_json(EXAMPLE_STAGE))
	var j: Junction = game._junctions["j0"]
	_expect(j.active, "AC-1 開始時に j0 がアクティブ")
	var before: int = j.selected
	_press_toggle(game)
	_expect(j.selected == 1 - before, "AC-1 切替で j0 の選択が反転する")
	_run_until(game, func() -> bool: return game._trolley.segment_id != "s0")
	_expect(game._trolley.segment_id == j.branches[1 - before], "AC-1 反転した側の出口へ進む")
	game.free()
	return true


# AC-2, AC-3: 通過済みの分岐は変わらない。アクティブ分岐がなければ何も起きない
func _check_toggle_after_junction() -> bool:
	var game: Node = _new_game(StageLoader.load_json(EXAMPLE_STAGE))
	var j: Junction = game._junctions["j0"]
	_run_until(game, func() -> bool: return game._trolley.segment_id != "s0")
	var selected: int = j.selected
	_expect(not j.active and game._active == null, "AC-2 通過後の j0 はアクティブでない（例データは分岐1つ）")
	_press_toggle(game)
	_expect(j.selected == selected, "AC-2/AC-3 通過後・分岐なしの区間では切替が効かない")
	game.free()
	return true


# AC-4, FR-2: 最高速でも経路上の移動距離が毎フレーム速度×時間だけ増え、境目で止まらない
func _check_carry_over() -> bool:
	var game: Node = _new_game(StageLoader.load_json(EXAMPLE_STAGE))
	var t: Trolley = game._trolley
	t.fixed_speed = Tuning.SPEED_MAX  # AC-4 の DEBUG_FIXED_SPEED = 1100.0
	var step: float = Tuning.SPEED_MAX * DT
	var route: Array[String] = [t.segment_id]
	t.segment_entered.connect(func(id: String) -> void: route.append(id))
	var last: float = 0.0
	var bad_frames: int = 0
	var frames: int = 0
	while not game._finished and frames < MAX_FRAMES:
		game._physics_process(DT)
		frames += 1
		var dist: float = t.progress
		for i: int in route.size() - 1:
			dist += (t.paths[route[i]] as Path2D).curve.get_baked_length()
		var moved: float = dist - last
		last = dist
		if moved <= 0.0 or (not game._finished and absf(moved - step) > 0.01):
			bad_frames += 1
	_expect(route.size() == 3, "AC-4 分岐と合流を通って3区間を走る（%s）" % [route])
	_expect(bad_frames == 0, "AC-4 毎フレーム %.2fpx ずつ進む（ずれたフレーム %d）" % [step, bad_frames])
	_expect(game._finished and game._message.text == "GOAL", "ゴールで止まり GOAL を出す")
	game.free()
	return true


# --- M2（物理エンジンを実フレームで進める） ---

# AC-5, FR-15, FR-20: crate に当たると右上へ飛び +100。飛んだ crate に重なっても得点は増えない。
# 地面で止まり、寿命（DEBRIS_LIFETIME）で消える
func _check_crate() -> bool:
	# 衝撃の向きと回転は乱数（FR-14）。飛び方しだいで寿命の前に止まりきらないことがあったので、種を決めて毎回同じにする
	seed(CRATE_SEED)
	var game: Node = _new_game(_straight([_obj("crate", 600)]))
	var crate: Target = game._targets[0]
	await _frames_until(func() -> bool: return crate.smashed)
	_expect(crate.smashed and game.score == 100, "AC-5 crate に当たるとスコアが100増える（%d）" % game.score)
	await _frames(2)
	var v: Vector2 = crate.linear_velocity
	_expect(v.x > 0.0 and v.y < 0.0, "AC-5 crate が右上へ飛ぶ（速度 %s）" % v)
	crate.global_position = game._trolley.global_position
	await _frames(3)
	game._smash(crate, game._hit_impulse)
	_expect(game.score == 100, "AC-5/FR-15 飛んだ crate にもう一度触れてもスコアは増えない（%d）" % game.score)
	# FR-20: 地面で止まる（寿命の少し前まで待つ）
	var expires: float = crate.unfrozen_at + Tuning.DEBRIS_LIFETIME
	await _frames_until(func() -> bool:
		return (crate.linear_velocity.length() < 5.0 and absf(crate.angular_velocity) < 0.05) \
				or game._time >= expires - 0.5)
	var bottom: float = _bottom_y(crate)
	_expect(absf(bottom - GROUND_Y) <= 2.0 and crate.linear_velocity.length() < 5.0,
			"FR-20 飛んだ crate は地面（y=%d）の上で止まる（下端 %.1f、速さ %.1f）" % [GROUND_Y, bottom, crate.linear_velocity.length()])
	# NFR-2: 寿命の少し前はまだ残り、DEBRIS_LIFETIME 秒で消える。トロッコはこの間 crate より
	# DEBRIS_BEHIND_LIMIT 以上は先に進まないので、後方の削除とは区別できる
	var crate_id: int = crate.get_instance_id()
	await _frames_until(func() -> bool: return game._time >= expires - DT * 2)
	_expect(is_instance_id_valid(crate_id), "NFR-2 DEBRIS_LIFETIME 秒たつ前は消えない")
	await _frames(3)
	_expect(not is_instance_id_valid(crate_id) and game._active_bodies.is_empty(),
			"NFR-2 freeze 解除から DEBRIS_LIFETIME 秒で消える")
	game.free()
	return true


# NFR-2: カメラ左端より DEBRIS_BEHIND_LIMIT px 以上後ろに出た物は、寿命の前でも消える
func _check_behind_limit() -> bool:
	var game: Node = _new_game(_straight([]))
	var cam_left: float = game._camera.position.x - game.get_viewport_rect().size.x / game._camera.zoom.x * 0.5
	var ids: Array[int] = []
	for dx: float in [-Tuning.DEBRIS_BEHIND_LIMIT - 100.0, -Tuning.DEBRIS_BEHIND_LIMIT + 100.0]:
		var p: Target = (load("res://scenes/objects/brick_piece.tscn") as PackedScene).instantiate()
		p.position = Vector2(cam_left + dx, RAIL_Y)
		game._world.add_child(p)
		game._launch(p, func(_at: Vector2) -> Vector2: return Vector2.ZERO)
		ids.append(p.get_instance_id())
	await _frames(2)
	_expect(not is_instance_id_valid(ids[0]) and is_instance_id_valid(ids[1]),
			"NFR-2 カメラ左端から DEBRIS_BEHIND_LIMIT 以上後ろの物だけ消える")
	game.free()
	return true


# AC-6, FR-16, FR-17: 半径内に並べた2個の drum の片方に当たると、両方が1回ずつ爆発する
func _check_drum_chain() -> bool:
	var game: Node = _new_game(_straight([_obj("drum", 600), _obj("drum", 700)]))
	var a: Target = game._targets[0]
	var b: Target = game._targets[1]
	var log: Array[Target] = []
	game.exploded.connect(func(d: Target) -> void: log.append(d))
	await _frames_until(func() -> bool: return a.smashed)
	await _frames(2)
	_expect(b.linear_velocity.x > 0.0, "FR-16 巻き込まれた drum は爆心から離れる向きに飛ぶ（%s）" % b.linear_velocity)
	await _frames(60)
	_expect(log.size() == 2 and log.count(a) == 1 and log.count(b) == 1,
			"AC-6 両方の drum が爆発し、各 drum の爆発は1回だけ（%d 回）" % log.size())
	_expect(log.size() == 2 and log[0] == a, "FR-17 当たった drum が先に爆発し、巻き込まれた drum が後から爆発する")
	_expect(b.smashed and game.score == 1000, "FR-16 巻き込まれた drum も smash 扱いで得点が入る（%d）" % game.score)
	game.free()
	return true


# FR-17: 連鎖の何段目でも、ゲーム内時刻で EXPLOSION_CHAIN_DELAY 秒（を超える最初の物理フレーム）ずつ遅れて爆発する
func _check_chain_interval() -> bool:
	var game: Node = _new_game(_straight([_obj("drum", 600), _obj("drum", 700), _obj("drum", 800)]))
	var times: Array[float] = []
	game.exploded.connect(func(_d: Target) -> void: times.append(game._time))
	await _frames_until(func() -> bool: return times.size() == 3 or game._finished)
	var ok: bool = times.size() == 3
	var gaps: Array[String] = []
	for i: int in times.size() - 1:
		var gap: float = times[i + 1] - times[i]
		gaps.append("%.4f" % gap)
		ok = ok and gap >= Tuning.EXPLOSION_CHAIN_DELAY - 1e-6 and gap < Tuning.EXPLOSION_CHAIN_DELAY + DT
	_expect(ok, "FR-17 3個の連鎖がゲーム内時刻で %.2f 秒ずつ遅れて爆発する（%s）" % [Tuning.EXPLOSION_CHAIN_DELAY, gaps])
	game.free()
	return true


# AC-10, FR-28: COMBO_WINDOW 秒以内に5回続けて smash すると、5回目のポップアップに「x1.5」が出る。
# 間があくとコンボが1に戻る
func _check_combo() -> bool:
	var gap: float = Tuning.SPEED_BASE * 0.4  # 0.4秒おき
	var objects: Array = []
	for i: int in 5:
		objects.append(_obj("crate", 600 + gap * i))
	objects.append(_obj("crate", 600 + gap * 4 + Tuning.SPEED_BASE * 1.6))  # 1.6秒あける
	var game: Node = _new_game(_straight(objects))
	game._trolley.fixed_speed = Tuning.SPEED_BASE  # 勢いで速くなると間隔がずれるので固定する
	var popups: Array[String] = []  # 出た瞬間の表示（ポップアップは POPUP_DURATION 秒で消えるので文字だけ残す）
	game._world.child_entered_tree.connect(func(n: Node) -> void:
		if n is ScorePopup:
			popups.append(("%s %s" % [n.points_text, n.mult_text]).strip_edges()))
	var last: Target = game._targets[5]
	await _frames_until(func() -> bool: return last.smashed)
	_expect(popups == ["+100", "+100", "+100", "+100", "+150 x1.5", "+100"],
			"AC-10 5回目のポップアップだけに x1.5、間があくとコンボが1に戻る（%s）" % [popups])
	_expect(game.combo == 1, "FR-28 COMBO_WINDOW を超えるとコンボが1に戻る（コンボ %d）" % game.combo)
	_expect(game.score == 650, "FR-27 得点 = 基本点 × 倍率（%d）" % game.score)
	game.free()
	return true


# 標的5種の破壊（M2）: 1.2秒ずつあけた5種がそれぞれの基本点で壊れ、wall は8個のレンガ片になる
func _check_all_kinds() -> bool:
	var gap: float = Tuning.SPEED_BASE * 1.2
	var kinds: Array[String] = ["crate", "barrel", "dummy", "drum", "wall"]
	var objects: Array = []
	for i: int in kinds.size():
		objects.append(_obj(kinds[i], 600 + gap * i))
	# 速度を固定し、wall はギリギリ突破にならない余裕で突破させる（突破と失敗は _check_wall で確かめる）
	objects[4]["required_speed"] = Tuning.SPEED_BASE - Tuning.GIRIGIRI_MARGIN * 2.0
	var game: Node = _new_game(_straight(objects))
	game._trolley.fixed_speed = Tuning.SPEED_BASE
	# wall は smash されたフレームの終わりに消えるので、参照ではなく ID で消えたことを待つ
	var wall_id: int = (game._targets[4] as Target).get_instance_id()
	await _frames_until(func() -> bool: return not is_instance_id_valid(wall_id))
	var pieces: int = 0
	for b: Target in game._active_bodies:
		if b.kind == "brick_piece":
			pieces += 1
	_expect(pieces == Tuning.WALL_PIECES, "FR-18 wall は %d 個のレンガ片になる（%d）" % [Tuning.WALL_PIECES, pieces])
	_expect(game.score == 1850, "6.3 5種の基本点の合計 100+150+300+500+800（%d）" % game.score)
	_expect(not game._finished and game._targets.is_empty(), "FR-18 必要速度以上なら wall は消え、走行が続く")
	game.free()
	return true


# NFR-2: freeze 解除済みの物体が MAX_ACTIVE_BODIES を超えたら、最も古いものから消す
func _check_body_cap() -> bool:
	var game: Node = _new_game(_straight([]))
	var scene: PackedScene = load("res://scenes/objects/brick_piece.tscn")
	var extra: int = 5
	var oldest: Array[Target] = []
	for i: int in Tuning.MAX_ACTIVE_BODIES + extra:
		var p: Target = scene.instantiate()
		game._world.add_child(p)
		game._launch(p, game._hit_impulse)
		if i < extra:
			oldest.append(p)
	var all_old_gone: bool = oldest.all(func(p: Target) -> bool: return p.is_queued_for_deletion())
	_expect(game._active_bodies.size() == Tuning.MAX_ACTIVE_BODIES and all_old_gone,
			"NFR-2 上限 %d 個を超えた分は古い順に消える（%d 個）" % [Tuning.MAX_ACTIVE_BODIES, game._active_bodies.size()])
	game.free()
	return true


# --- M3 ---

const CRATE_SEED: int = 20260926  # _check_crate の乱数の種
const WALL_SPEED: float = 700.0  # AC-7, AC-18, AC-19 の wall と AC-8 の jump の required_speed


# FR-21, FR-22: smash で勢いが種別の値だけ増え、毎秒 MOMENTUM_DECAY 減る。速度は目標速度へ lerp で追従する
# （1フレームの式を確かめるので、ヒットストップの起きない barrel を使う）
func _check_momentum() -> bool:
	var game: Node = _new_game(_straight([_obj("barrel", 600), _obj("crate", 1500)]))
	var barrel: Target = game._targets[0]
	var crate: Target = game._targets[1]
	await _frames_until(func() -> bool: return barrel.smashed)
	var m: float = game.momentum
	_expect(is_equal_approx(m, Tuning.TARGET_MOMENTUM["barrel"]), "FR-21 barrel を壊すと勢いが %d 増える（%.2f）" % [Tuning.TARGET_MOMENTUM["barrel"], m])
	var v0: float = game._trolley.speed
	await _frames(1)
	var m1: float = m - Tuning.MOMENTUM_DECAY * DT
	var want: float = lerpf(v0, minf(Tuning.SPEED_BASE + m1 * Tuning.SPEED_PER_MOMENTUM, Tuning.SPEED_MAX), Tuning.SPEED_LERP * DT)
	_expect(is_equal_approx(game.momentum, m1) and is_equal_approx(game._trolley.speed, want) and want > v0,
			"FR-21/22 1フレームで勢いが減り、速度が目標速度へ近づく（勢い %.3f / %.3f、速度 %.2f / %.2f）" % [game.momentum, m1, game._trolley.speed, want])
	var frames: int = 0
	while game.momentum > 0.0 and frames < MAX_FRAMES:
		await _frames(1)
		frames += 1
	var expect_frames: int = roundi(m1 / Tuning.MOMENTUM_DECAY / DT)
	_expect(absi(frames - expect_frames) <= 1, "FR-21 勢いは毎秒 %d ずつ減って0で止まる（%d フレーム、予想 %d）" % [Tuning.MOMENTUM_DECAY, frames, expect_frames])
	game.momentum = Tuning.MOMENTUM_MAX
	await _frames_until(func() -> bool: return crate.smashed)
	_expect(game.momentum <= Tuning.MOMENTUM_MAX, "FR-21 勢いは MOMENTUM_MAX を超えない（%.2f）" % game.momentum)
	game.free()
	return true


# AC-7: required_speed 700 の wall に 699 で触れると「激突！」で失敗、700 なら8片に割れて走行が続く
func _check_wall() -> bool:
	var game: Node = await _run_to_wall(WALL_SPEED - 1.0)
	var wall: Target = game._targets[0]
	_expect(game.fail_reason == "激突" and not wall.smashed and game.score == 0,
			"AC-7 699 で wall に触れると激突で失敗し、wall は壊れない（%s、スコア %d）" % [game.fail_reason, game.score])
	_expect(game._fail_text.visible and game._fail_text.text == "激突！", "FR-25 画面中央に「激突！」を出す")
	_expect(game._wreck != null and not game._trolley.visible, "FR-25 トロッコを物理ボディに置き換える")
	if game._wreck != null:
		await _frames(60)
		var back: float = wall.global_position.x - game._wreck.global_position.x
		_expect(back < Tuning.TROLLEY_TOP_W * 2.0, "激突したトロッコは wall から跳ね戻らない（1秒後に wall の %.0f px 手前）" % back)
	game.free()

	game = await _run_to_wall(WALL_SPEED)
	var pieces: int = game._active_bodies.filter(func(b: Target) -> bool: return b.kind == "brick_piece").size()
	_expect(game.fail_reason == "" and pieces == Tuning.WALL_PIECES, "AC-7 700 なら wall は %d 片に割れる（%d 片）" % [Tuning.WALL_PIECES, pieces])
	await _frames(30)
	_expect(not game._finished and game._trolley.visible, "AC-7 突破後も走行が続く")
	game.free()

	# TODO(spec) の決め事: drum の爆発に巻き込まれた wall は、トロッコが遅くても壊れる
	game = _new_game(_straight([_obj("drum", 600), _wall(700)]))
	var wall_id: int = (game._targets[1] as Target).get_instance_id()
	await _frames_until(func() -> bool: return game._finished or not is_instance_id_valid(wall_id))
	_expect(not is_instance_id_valid(wall_id) and game.fail_reason == "" and game._trolley.speed < WALL_SPEED,
			"爆発に巻き込まれた wall は速度 %d でも壊れ、激突にならない" % game._trolley.speed)
	game.free()
	return true


# AC-19, FR-36a: 速度720で突破すると「壁の基本点×倍率＋500」増えて「ギリギリ！」が出る。760 ならどちらも無い
func _check_girigiri() -> bool:
	for speed: float in [WALL_SPEED + 20.0, WALL_SPEED + 60.0]:
		var game: Node = await _run_to_wall(speed)
		var bonus: bool = speed - WALL_SPEED < Tuning.GIRIGIRI_MARGIN
		var want: int = Tuning.TARGET_POINTS["wall"] + (Tuning.GIRIGIRI_BONUS if bonus else 0)
		var labels: Array = game._world.get_children().filter(func(n: Node) -> bool: return n is Girigiri)
		_expect(game.score == want and game.girigiri_count == (1 if bonus else 0) and labels.size() == (1 if bonus else 0),
				"AC-19 速度 %d で突破: スコア %d（%d）、ギリギリ表示 %d 個" % [speed, want, game.score, labels.size()])
		if bonus and labels.size() == 1:
			_expect((labels[0] as Girigiri).text() == "ギリギリ！ +%d" % Tuning.GIRIGIRI_BONUS, "FR-36a 表示は「ギリギリ！ +500」")
			var id: int = (labels[0] as Node).get_instance_id()
			var until: float = game._time + Tuning.GIRIGIRI_SHOW_TIME + DT * 2.0
			await _frames_until(func() -> bool: return game._time >= until)
			_expect(not is_instance_id_valid(id), "FR-36a ギリギリの表示は %.1f 秒で消える" % Tuning.GIRIGIRI_SHOW_TIME)
		game.free()
	return true


# AC-8, FR-23, FR-36a: required_speed 700 の jump に 699 で入ると「脱線！」、700 なら通過する（差0なのでギリギリ突破）
func _check_jump() -> bool:
	var data: Dictionary = _jump_stage()
	var game: Node = _new_game(data.duplicate(true))
	game._trolley.fixed_speed = WALL_SPEED - 1.0
	# FR-24: jump の開始地点の上方に必要速度標識
	var signs: Array = game._world.get_children().filter(func(n: Node) -> bool: return n is SpeedSign)
	var sign: SpeedSign = signs[0] if signs.size() == 1 else null
	await _frames(2)
	_expect(sign != null and sign.position == Vector2(1000, RAIL_Y - Tuning.SIGN_JUMP_HEIGHT) and sign.text() == "× 70km/h",
			"FR-24 jump の開始地点の上方 %d px に標識があり、699 では「× 70km/h」" % Tuning.SIGN_JUMP_HEIGHT)
	await _frames_until(func() -> bool: return game._finished)
	var v: float = game._wreck.linear_velocity.length() if game._wreck != null else 0.0
	_expect(game.fail_reason == "脱線" and game._fail_text.text == "脱線！", "AC-8 699 で jump に入ると「脱線！」で失敗（%s）" % game.fail_reason)
	_expect(absf(v - (WALL_SPEED - 1.0)) < 30.0, "FR-25 失敗時点の速度で転がり始める（%.1f）" % v)
	game.free()

	game = _new_game(data.duplicate(true))
	game._trolley.fixed_speed = WALL_SPEED
	await _frames_until(func() -> bool: return game._trolley.segment_id == "s2" or game._finished)
	_expect(game._trolley.segment_id == "s2" and not game._finished, "AC-8 700 なら jump を通過する")
	_expect(game.score == Tuning.GIRIGIRI_BONUS and game.girigiri_count == 1, "FR-36a jump を差0で通過するとギリギリ突破（%d）" % game.score)
	game.free()
	return true


# AC-18, FR-19: 標識は wall の上端より10px上にあり、速度 699 では「× 70km/h」、700 にすると「○ 70km/h」になる
func _check_sign() -> bool:
	var game: Node = _new_game(_straight([_wall(1500)]))
	var wall: Target = game._targets[0]
	var sign: SpeedSign = wall.get_node("SpeedSign")
	var wall_top: float = wall.to_global(Vector2(0.0, -wall.body_size().y)).y
	_expect(is_equal_approx(sign.global_position.y, wall_top - Tuning.SIGN_WALL_GAP), "FR-19 標識の下端が wall の上端より %d px 上" % Tuning.SIGN_WALL_GAP)
	game._trolley.fixed_speed = WALL_SPEED - 1.0
	await _frames(2)
	_expect(not sign.ok and sign.text() == "× 70km/h", "AC-18 699 のとき「× 70km/h」（%s）" % sign.text())
	game._trolley.fixed_speed = WALL_SPEED
	await _frames(2)
	_expect(sign.ok and sign.text() == "○ 70km/h", "AC-18 700 にすると「○ 70km/h」（%s）" % sign.text())
	game.free()
	return true


# AC-9, FR-26: プレイ中に R を押すと、0.5秒以内にスコア0・勢い0・全標的復活で再開する。すぐ2回目を押しても無視する
func _check_retry_playing() -> bool:
	var game: Node = _new_game(_straight([_obj("crate", 600), _obj("crate", 800)]))
	var last: Target = game._targets[1]
	await _frames_until(func() -> bool: return last.smashed)
	_expect(game.score > 0 and game.momentum > 0.0, "AC-9 前提: 2個壊してスコアと勢いがある")
	var started: int = Time.get_ticks_msec()
	var fresh: Node = await _press_retry(game)
	var ms: int = Time.get_ticks_msec() - started
	_expect_restarted(fresh, 2, "プレイ中")
	_expect(ms < 500, "AC-9 0.5秒以内に再開する（%d ms）" % ms)
	await _frames(10)
	var moved: float = fresh._trolley.total_distance
	var again: Node = await _press_retry(fresh)
	_expect(again == fresh and fresh._trolley.total_distance > moved,
			"FR-26 RETRY_DEBOUNCE 秒以内の2回目のリトライは無視する")
	return true


# AC-9, FR-26: 失敗演出中に R を押しても、最初からやり直せる
func _check_retry_failed() -> bool:
	var game: Node = await _run_to_wall(WALL_SPEED - 1.0)
	_expect(game.fail_reason == "激突", "AC-9 前提: 激突で失敗している")
	var fresh: Node = await _press_retry(game)
	_expect_restarted(fresh, 1, "失敗演出中")
	_expect(fresh.fail_reason == "" and not fresh._fail_text.visible and fresh._wreck == null, "AC-9 失敗の表示も消える")
	return true


func _expect_restarted(fresh: Node, targets: int, when: String) -> void:
	var all_back: bool = fresh._targets.size() == targets and fresh._targets.all(func(t: Target) -> bool: return not t.smashed)
	_expect(fresh.score == 0 and fresh.momentum == 0.0 and fresh.combo == 0 and all_back and not fresh._finished,
			"AC-9 %s に R: スコア0・勢い0・全標的復活で再開（スコア %d、勢い %.1f、標的 %d）" % [when, fresh.score, fresh.momentum, fresh._targets.size()])
	_expect(fresh._trolley.segment_id == "s0" and fresh._trolley.total_distance <= Tuning.SPEED_MAX * DT * 2.0,
			"AC-9 %s に R: トロッコはスタート地点から走り直す" % when)


## R（retry）を押し、差し替え後のゲーム画面を返す（押しても差し替わらなければ元のゲーム画面）
func _press_retry(game: Node) -> Node:
	var before: int = root.get_child_count()
	_press(game, &"retry")
	await _frames(1)
	var last: Node = root.get_child(root.get_child_count() - 1)
	if last == game or root.get_child_count() != before:
		return game
	_games.append(last)
	return last


## required_speed 700 の wall（offset 600）に向かって速度 speed で走り、激突するか wall が消えるまで進めたゲームを返す
func _run_to_wall(speed: float) -> Node:
	var game: Node = _new_game(_straight([_wall(600)]))
	game._trolley.fixed_speed = speed
	var wall_id: int = (game._targets[0] as Target).get_instance_id()
	await _frames_until(func() -> bool: return game._finished or not is_instance_id_valid(wall_id))
	return game


# --- M4 ---

# AC-11, FR-30〜32, 10章: ヒットストップ中に爆発すると、小さい倍率（HITSTOP_SCALE）が先に効き、切れたらスローモー
# （SLOWMO_SCALE）の残りが続き、全部切れたら 1.0 に戻る。要求を全部捨てると（ポーズ FR-44 が使う）すぐ 1.0 になり、
# 後で古い要求の時間が切れても 1.0 のまま
# TODO(spec): ポーズ画面は M5。ここではポーズが呼ぶ TimeScale.clear() を直接確かめる
func _check_time_scale() -> bool:
	# dummy（300点）と drum を同じ位置に置き、同じフレームに smash する
	var game: Node = _new_game(_straight([_obj("dummy", 600), _obj("drum", 600)]))
	var dummy: Target = game._targets[0]
	await _frames_until(func() -> bool: return dummy.smashed)
	var scales: Array[float] = []
	for _i: int in MAX_FRAMES:
		scales.append(Engine.time_scale)
		if Engine.time_scale == 1.0:
			break
		await _frames(1)
	var stop: int = scales.count(Tuning.HITSTOP_SCALE)
	var slow: int = scales.count(Tuning.SLOWMO_SCALE)
	var expected: Array[float] = _repeat(Tuning.HITSTOP_SCALE, stop)
	expected.append_array(_repeat(Tuning.SLOWMO_SCALE, slow))
	expected.append(1.0)
	var in_order: bool = scales == expected
	var stop_frames: int = roundi(Tuning.HITSTOP_DURATION / DT)
	var all_frames: int = roundi(Tuning.SLOWMO_DURATION / DT)
	_expect(in_order and absi(stop - stop_frames) <= 1 and absi(stop + slow - all_frames) <= 1,
			"AC-11 ヒットストップ中に爆発: %.2f が %d フレーム → %.2f が %d フレーム → 1.0（実時間で約 %d / %d フレーム）" % [
				Tuning.HITSTOP_SCALE, stop, Tuning.SLOWMO_SCALE, slow, stop_frames, all_frames])
	await _frames(30)
	_expect(Engine.time_scale == 1.0, "AC-11 すべての演出が終わった後は 1.0 のまま")
	game.free()

	_time_scale.request(Tuning.SLOWMO_SCALE, Tuning.SLOWMO_DURATION)
	_time_scale.request(Tuning.HITSTOP_SCALE, Tuning.HITSTOP_DURATION)
	_time_scale.clear()
	_expect(Engine.time_scale == 1.0, "AC-11/FR-44 演出中に要求を全部捨てると 1.0 になる")
	await _frames(roundi(Tuning.SLOWMO_DURATION / DT) + 5)
	_expect(Engine.time_scale == 1.0, "AC-11 捨てた要求の時間が切れても 1.0 のまま")
	_time_scale.request(Tuning.SLOWMO_SCALE, Tuning.HITSTOP_DURATION)
	_expect(Engine.time_scale == Tuning.SLOWMO_SCALE, "FR-32 捨てた後の新しい要求は効く")
	await _frames(roundi(Tuning.HITSTOP_DURATION / DT) + 3)
	_expect(Engine.time_scale == 1.0, "FR-32 新しい要求が切れたら 1.0 に戻る")

	# FR-30: 基本点 HITSTOP_MIN_POINTS 未満（crate 100点）ではヒットストップしない
	game = _new_game(_straight([_obj("crate", 600)]))
	var crate: Target = game._targets[0]
	await _frames_until(func() -> bool: return crate.smashed)
	_expect(Engine.time_scale == 1.0, "FR-30 基本点 %d 未満の smash ではヒットストップしない" % Tuning.HITSTOP_MIN_POINTS)
	game.free()
	return true


# FR-33, FR-36: smash で振幅 min(SHAKE_BASE + 基本点 / SHAKE_DIV, SHAKE_MAX) px の揺れ、SHAKE_DECAY 秒（実時間）で0。
# 揺れ中は大きい方で上書き。設定の「画面の揺れ」が OFF なら揺らさない（ヒットストップ・パーティクルは行う）
func _check_shake() -> bool:
	var game: Node = _new_game(_straight([_obj("crate", 600)]))
	var crate: Target = game._targets[0]
	await _frames_until(func() -> bool: return crate.smashed)
	var want: float = minf(Tuning.SHAKE_BASE + Tuning.TARGET_POINTS["crate"] / Tuning.SHAKE_DIV, Tuning.SHAKE_MAX)
	await _frames(1)
	var off: Vector2 = game._camera.offset
	_expect(is_equal_approx(game._shake_amp, want) and off != Vector2.ZERO and absf(off.x) <= want and absf(off.y) <= want,
			"FR-33 crate の smash で振幅 %.0f px の揺れ（カメラのずれ %s）" % [want, off])
	game.shake(want * 0.5)
	_expect(is_equal_approx(game._shake_amp, want), "FR-33 揺れ中に小さい揺れが来ても、大きい方のまま")
	game.shake(Tuning.SHAKE_MAX)
	_expect(is_equal_approx(game._shake_amp, Tuning.SHAKE_MAX), "FR-33 揺れ中に大きい揺れが来たら上書きする")
	await _frames(roundi(Tuning.SHAKE_DECAY / DT) + 2)
	_expect(game.shake_amplitude() == 0.0 and game._camera.offset == Vector2.ZERO, "FR-33 SHAKE_DECAY 秒で揺れが0になる")
	game.free()

	# ヒットストップが起きる smash（dummy）でも揺れる（time_scale を変えたフレームで揺れが消えない）
	game = _new_game(_straight([_obj("dummy", 600)]))
	var hit: Target = game._targets[0]
	await _frames_until(func() -> bool: return hit.smashed)
	await _frames(2)
	_expect(Engine.time_scale == Tuning.HITSTOP_SCALE and game.shake_amplitude() > 0.0 and game._camera.offset != Vector2.ZERO,
			"FR-33 ヒットストップ中も揺れる（振幅 %.1f）" % game.shake_amplitude())
	game.free()
	_time_scale.clear()

	_game_state.screen_shake = false
	game = _new_game(_straight([_obj("dummy", 600)]))
	var parts: Array[Node] = []
	game._world.child_entered_tree.connect(func(n: Node) -> void:
		if n is CPUParticles2D:
			parts.append(n))
	var dummy: Target = game._targets[0]
	await _frames_until(func() -> bool: return dummy.smashed)
	var stopped: bool = Engine.time_scale == Tuning.HITSTOP_SCALE
	await _frames(1)
	_expect(game.shake_amplitude() == 0.0 and game._camera.offset == Vector2.ZERO and stopped and parts.size() == 1,
			"FR-36 揺れ OFF ならカメラは揺れず、ヒットストップとパーティクルは行う")
	game.free()
	return true


# FR-34: smash 位置に破片のパーティクル（16個、寿命0.6秒、one_shot）が出て、終われば消える
func _check_particles() -> bool:
	var game: Node = _new_game(_straight([_obj("barrel", 600)]))
	var parts: Array[CPUParticles2D] = []
	game._world.child_entered_tree.connect(func(n: Node) -> void:
		if n is CPUParticles2D:
			parts.append(n))
	var barrel: Target = game._targets[0]
	var at: Vector2 = barrel.center()
	await _frames_until(func() -> bool: return barrel.smashed)
	var p: CPUParticles2D = parts[0] if parts.size() == 1 else null
	_expect(p != null and p.amount == Tuning.PARTICLE_AMOUNT and is_equal_approx(p.lifetime, Tuning.PARTICLE_LIFETIME)
			and p.one_shot and p.emitting and p.position == at,
			"FR-34 smash 位置に %d 個・寿命 %.1f 秒・one_shot のパーティクル" % [Tuning.PARTICLE_AMOUNT, Tuning.PARTICLE_LIFETIME])
	if p != null:
		var id: int = p.get_instance_id()
		await _frames(roundi(Tuning.PARTICLE_LIFETIME / DT) * 2)
		_expect(not is_instance_id_valid(id), "FR-34 パーティクルは出し終わったら消える")
	game.free()
	return true


# FR-37, FR-38: ズームは速度 SPEED_BASE で ZOOM_AT_BASE、SPEED_MAX で ZOOM_AT_MAX、その間は線形。
# SPEED_MAX より速い車両（試作型）では同じ傾きでさらに引き、ZOOM_MIN で止める（L-3 の見え方を保つため）。
# どのズームでもトロッコは画面の左から25%の位置
func _check_zoom() -> bool:
	var game: Node = _new_game(_straight([]))
	var t: Trolley = game._trolley
	var mid_speed: float = (Tuning.SPEED_BASE + Tuning.SPEED_MAX) * 0.5
	var mid_zoom: float = (Tuning.ZOOM_AT_BASE + Tuning.ZOOM_AT_MAX) * 0.5
	var over: float = 0.1  # SPEED_MAX から、SPEED_BASE〜SPEED_MAX の幅の1割だけ速い
	var over_speed: float = Tuning.SPEED_MAX + (Tuning.SPEED_MAX - Tuning.SPEED_BASE) * over
	var over_zoom: float = Tuning.ZOOM_AT_MAX - (Tuning.ZOOM_AT_BASE - Tuning.ZOOM_AT_MAX) * over
	for c: Array in [[Tuning.SPEED_BASE, Tuning.ZOOM_AT_BASE], [mid_speed, mid_zoom], [Tuning.SPEED_MAX, Tuning.ZOOM_AT_MAX],
			[over_speed, over_zoom], [Tuning.SPEED_MAX * 3.0, Tuning.ZOOM_MIN]]:
		t.fixed_speed = c[0]
		await _frames(2)
		var zoom: float = game._camera.zoom.x
		var view_w: float = game.get_viewport_rect().size.x / zoom
		var ratio: float = (t.global_position.x - (game._camera.position.x - view_w * 0.5)) / view_w
		_expect(is_equal_approx(zoom, c[1]) and absf(ratio - Tuning.CAMERA_TROLLEY_SCREEN_X) < 0.001,
				"FR-38 速度 %d でズーム %.2f（%.3f）、トロッコは画面左から %.1f%%" % [c[0], c[1], zoom, ratio * 100.0])
	game.free()
	var fastest: float = 0.0
	for s: Dictionary in Tuning.TROLLEY_STATS.values():
		fastest = maxf(fastest, s["speed_max"])
	var natural: float = Tuning.ZOOM_AT_MAX - (Tuning.ZOOM_AT_BASE - Tuning.ZOOM_AT_MAX) * (fastest - Tuning.SPEED_MAX) / (
			Tuning.SPEED_MAX - Tuning.SPEED_BASE)
	_expect(Tuning.ZOOM_MIN <= natural + 0.001 and natural - Tuning.ZOOM_MIN < Tuning.ZOOM_MIN_MARGIN,
			"ZOOM_MIN（%.3f）は一番速い車両の最高速 %d のズーム（%.3f）以下で、それに近い" % [
			Tuning.ZOOM_MIN, fastest, natural])
	return true


# FR-36b: ステージ開始時、画面上部中央（上端から72px）に「第N試験　試験開始」を BANNER_DURATION 秒出す。表示中も走る
func _check_banner() -> bool:
	var data: Dictionary = _straight([])
	data["id"] = "stage_03"
	var game: Node = _new_game(data)
	var banners: Array = game._hud.get_children().filter(func(n: Node) -> bool: return n is Banner)
	var b: Banner = banners[0] if banners.size() == 1 else null
	var center_x: float = game.get_viewport_rect().size.x * 0.5
	_expect(b != null and b.text() == "第3試験　試験開始" and b.position.y == Tuning.BANNER_TOP
			and absf(b.position.x + b.size.x * 0.5 - center_x) < 0.5,
			"FR-36b 画面上部中央（上端から %d px）に「第3試験　試験開始」" % Tuning.BANNER_TOP)
	await _frames(10)
	_expect(game._trolley.total_distance > 0.0, "FR-36b バナーの表示中もトロッコは走る")
	if b != null:
		var id: int = b.get_instance_id()
		await _frames(roundi(Tuning.BANNER_DURATION / DT) + 5)
		_expect(not is_instance_id_valid(id), "FR-36b バナーは %.1f 秒で消える" % Tuning.BANNER_DURATION)
	game.free()
	return true


# FR-36c: 第1試験だけ、最初に切替が成功するまでアクティブ分岐の上方80pxにヒントを出す。
# 分岐を通り過ぎてアクティブ分岐が無くなったら隠す。リトライで出し直す
func _check_hint() -> bool:
	var game: Node = _new_game(StageLoader.load_json(EXAMPLE_STAGE))  # id は stage_01
	var hint: FirstHint = game._hint
	var j: Junction = game._junctions["j0"]
	_expect(hint != null and hint.visible and hint.position == j.global_position + Vector2(0.0, -Tuning.HINT_HEIGHT)
			and hint.text() == "[SPACE] / クリックで切り替え",
			"FR-36c 第1試験ではアクティブ分岐の上方 %d px に「[SPACE] / クリックで切り替え」" % Tuning.HINT_HEIGHT)
	_press_toggle(game)
	_expect(game._hint == null and hint.is_queued_for_deletion(), "FR-36c 切替が成功したらヒントを消す")
	var fresh: Node = await _press_retry(game)
	_expect(fresh != game and fresh._hint != null and fresh._hint.visible, "FR-36c リトライするとヒントを出し直す")
	if fresh != game:
		_run_until(fresh, func() -> bool: return fresh._trolley.segment_id != "s0")
		_expect(fresh._hint != null and not fresh._hint.visible, "FR-36c 切り替えずに分岐を過ぎ、アクティブ分岐が無くなったら隠す")

	var data: Dictionary = StageLoader.load_json(EXAMPLE_STAGE)
	data["id"] = "stage_02"
	var other: Node = _new_game(data)
	_expect(other._hint == null, "FR-36c 第2試験以降はヒントを出さない")
	return true


# FR-10, FR-11, FR-51: 出来事ごとに効果音を鳴らす。基本点 HITSTOP_MIN_POINTS 以上の smash は hit_big、未満は hit_small
func _check_se() -> bool:
	var played: Array[StringName] = []
	var record := func(key: StringName) -> void: played.append(key)
	_audio.played.connect(record)
	var game: Node = _new_game(StageLoader.load_json(EXAMPLE_STAGE))
	_press_toggle(game)
	_expect(played == [&"toggle"], "FR-10 切替で toggle（%s）" % [played])
	_run_until(game, func() -> bool: return game._trolley.segment_id != "s0")
	played.clear()
	_press_toggle(game)
	_expect(played.is_empty(), "FR-11 アクティブ分岐が無いときの切替では鳴らさない")
	game.free()

	# crate → hit_small、wall（速度720でギリギリ突破）→ hit_big・wall_break・girigiri、drum → hit_big・explosion、ゴール → goal
	played.clear()
	game = _new_game(_straight([_obj("crate", 600), _wall(1400), _obj("drum", 2600)]))
	game._trolley.fixed_speed = WALL_SPEED + 20.0
	await _frames_until(func() -> bool: return game._finished)
	var want: Array[StringName] = [&"hit_small", &"hit_big", &"wall_break", &"girigiri", &"hit_big", &"explosion", &"goal"]
	_expect(played == want, "FR-51 smash・壁の破壊・ギリギリ・爆発・ゴールで鳴らす（%s）" % [played])
	game.free()

	played.clear()
	game = await _run_to_wall(WALL_SPEED - 1.0)
	_expect(played == [&"crash"], "FR-51 激突で crash（%s）" % [played])
	game.free()
	played.clear()
	game = _new_game(_jump_stage())
	game._trolley.fixed_speed = WALL_SPEED - 1.0
	await _frames_until(func() -> bool: return game._finished)
	_expect(played == [&"derail"], "FR-51 脱線で derail（%s）" % [played])
	game.free()
	_audio.played.disconnect(record)
	return true


# AC-13, FR-52: 効果音のファイルが無くても、鳴らないだけでステージをクリアできる
# （1つ消す代わりに、12キーすべてのファイルが無い状態で確かめる）
func _check_missing_sfx() -> bool:
	_audio.load_sounds("res://tests/no_such_sfx/")
	var game: Node = _new_game(_straight([_obj("crate", 600), _obj("dummy", 900), _obj("drum", 1400)]))
	await _frames_until(func() -> bool: return game._finished)
	_expect(game._message.text == "GOAL" and game.score > 0, "AC-13 効果音のファイルが無くても、壊してゴールできる")
	game.free()
	_audio.load_sounds(_audio.SFX_DIR)
	_expect(_audio._players.size() == _audio.KEYS.size(), "FR-52 assets/sfx に %d キーすべての効果音がある" % _audio.KEYS.size())
	return true


# コンボ専用の演出（依頼者の追加要望。仕様に無い）: 倍率が上がる 5・10・15・20 コンボで札を押す。倍率2.0以上で画面の縁、
# 最大倍率でスローモーと大きめの揺れ。10コンボ以上が途切れたら「N COMBO」を出す
func _check_combo_fx() -> bool:
	var gap: float = Tuning.SPEED_BASE * 0.3  # 0.3秒おき
	var objects: Array = []
	for i: int in 20:
		objects.append(_obj("crate", 600 + gap * i))
	var game: Node = _new_game(_straight(objects))
	game._trolley.fixed_speed = Tuning.SPEED_BASE
	var fx: Control = game._combo_fx  # ComboFx は autoload（Audio）を使うので、型名で書くとこのスクリプトが読めなくなる
	var texts: Array[String] = []
	fx.child_entered_tree.connect(func(n: Node) -> void:
		if n is Label:
			texts.append((n as Label).text))
	var tenth: Target = game._targets[9]
	var last: Target = game._targets[19]
	await _frames_until(func() -> bool: return tenth.smashed)
	_expect(fx._edge.modulate.a > 0.5, "コンボ演出: 倍率2.0に上がると画面の上下の縁が光る")
	await _frames_until(func() -> bool: return last.smashed)
	_expect(Engine.time_scale == Tuning.COMBO_MAX_SLOWMO_SCALE and is_equal_approx(game._shake_amp, Tuning.COMBO_MAX_SHAKE)
			and fx.combo_text() == "20 COMBO x3.0",
			"コンボ演出: 最大倍率でスローモー（%.2f）と大きめの揺れ（%.0f）" % [Engine.time_scale, game._shake_amp])
	await _frames_until(func() -> bool: return not game._combo_alive)
	_expect(texts == ["x1.5!", "x2.0!", "x2.5!", "x3.0 MAX!", "20 COMBO"] and fx.combo_text() == "",
			"コンボ演出: 倍率が上がるたびに札、途切れたら「20 COMBO」（%s）" % [texts])
	game.free()
	return true


# --- M5 ---

# FR-42, FR-43: HUD に得点（3桁区切り）、速度（km/h）、「第N試験」とステージ名。コンボの札はスコアの下
func _check_hud() -> bool:
	var data: Dictionary = _straight([_obj("crate", 600), _obj("crate", 700)])
	data["id"] = "stage_02"
	data["name"] = "ダミー大行進"
	var game: Node = _new_game(data)
	game._trolley.fixed_speed = 580.0
	var second: Target = game._targets[1]
	await _frames_until(func() -> bool: return second.smashed)
	game.score = 12345
	await _frames(2)
	var hud: Control = game._hud_view
	_expect(hud.score_text() == "12,345" and hud.speed_text() == "58 km/h" and hud.stage_text() == "第2試験 ダミー大行進",
			"FR-42/43 HUD: 得点 %s、速度 %s、%s" % [hud.score_text(), hud.speed_text(), hud.stage_text()])
	var tag: Label = game._combo_fx._label
	_expect(tag.visible and tag.text == "2 COMBO x1.0" and tag.position == hud.combo_position(),
			"FR-42 コンボ2以上でスコアの下にコンボの札（%s）" % tag.text)
	game.free()
	return true


# FR-44, AC-11, AC-9: ポーズで木が止まり、演出中でも time_scale は 1.0。再開しても 1.0。ポーズ中の R でやり直す
func _check_pause() -> bool:
	var game: Node = _new_game(_straight([_obj("drum", 600)]))
	var drum: Target = game._targets[0]
	await _frames_until(func() -> bool: return drum.smashed)
	_expect(Engine.time_scale < 1.0, "前提: 爆発でスローモー中")
	_press(game, &"pause")
	var menu: Control = game._pause
	_expect(paused and Engine.time_scale == 1.0 and menu != null, "FR-44 pause で木が止まり、TimeScale の要求を捨てて 1.0")
	if menu == null:
		return true
	await _frames(1)
	_expect(menu.get_node("%Resume").has_focus(), "FR-47a ポーズは「再開」にフォーカスして開く")
	var moved: float = game._trolley.total_distance
	await _frames(10)
	_expect(game._trolley.total_distance == moved, "FR-44 ポーズ中はトロッコが止まっている")
	_push_action(&"pause")  # Esc / P で再開
	await _frames(2)
	_expect(not paused and game._pause == null and Engine.time_scale == 1.0, "AC-11 ポーズから再開しても time_scale は 1.0")
	await _frames(5)
	_expect(game._trolley.total_distance > moved, "FR-44 再開すると走り出す")

	_press(game, &"pause")
	var started: int = Time.get_ticks_msec()
	_push_action(&"retry")
	await _frames(1)
	var fresh: Node = root.get_child(root.get_child_count() - 1)
	var ms: int = Time.get_ticks_msec() - started
	if fresh != game:
		_games.append(fresh)
		_expect_restarted(fresh, 1, "ポーズ中")
	_expect(fresh != game and not paused and ms < 500, "AC-9 ポーズ中に R で 0.5秒以内にやり直す（%d ms）" % ms)
	return true


# FR-44, FR-47d: ポーズから設定を開き、Esc で閉じるとポーズに戻る（「設定」にフォーカス）。もう一度 Esc で再開
func _check_pause_settings() -> bool:
	var game: Node = _new_game(_straight([]))
	_press(game, &"pause")
	var menu: Control = game._pause
	var overlay: Control = menu.open_settings()
	await _frames(1)
	_expect(overlay.get_node("%Back").has_focus() and menu.is_settings_open(), "FR-44 ポーズから設定を開く（「戻る」にフォーカス）")
	_push_key(KEY_ESCAPE)
	await _frames(2)
	_expect(not menu.is_settings_open() and paused and menu.get_node("%Settings").has_focus(),
			"FR-47d 設定の Esc でポーズに戻り、「設定」にフォーカス（ポーズは続く）")
	_push_key(KEY_ESCAPE)
	await _frames(2)
	_expect(not paused and game._pause == null, "ポーズで Esc を押すと再開する")
	game.free()
	return true


# FR-47: ウィンドウがフォーカスを失ったら自動でポーズする
func _check_auto_pause() -> bool:
	var game: Node = _new_game(_straight([]))
	await _frames(2)
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_expect(paused and game._pause != null, "FR-47 フォーカスを失うと自動でポーズする")
	game.resume()
	game.free()
	return true


# FR-25, FR-46, AC-23, AC-9: 580 で必要速度 700 の壁に激突すると、FAIL_DELAY 秒後に失敗版リザルトが出る。
# 渡す記録は必要速度 700・到達速度 580。リザルト中に R でやり直す
func _check_result_fail() -> bool:
	_game_state.erase_records()  # 前の確認がゴールして残した記録（id に数字が無いステージは第1試験として記録される）を消す
	var game: Node = _new_game(_straight([_obj("crate", 300), _wall(600)]))
	game._trolley.fixed_speed = 580.0
	await _frames_until(func() -> bool: return game._finished)
	var failed_at: float = game._time
	await _frames_until(func() -> bool: return game._time >= failed_at + Tuning.FAIL_DELAY - DT * 2)
	_expect(game._result == null, "FR-25 FAIL_DELAY 秒たつまではリザルトを出さない")
	await _frames_until(func() -> bool: return game._result != null or game._time >= failed_at + Tuning.FAIL_DELAY + 1.0)
	var d: Dictionary = game.result_data()
	_expect(game._result != null and not d["cleared"] and d["fail_reason"] == "激突" and d["required_speed"] == WALL_SPEED
			and d["reached_speed"] == 580.0 and d["score"] == 100 and d["stars"] == 0 and not d["best_updated"],
			"FR-46/AC-23 失敗版リザルトに 激突・必要 %d・到達 580・得点 100（%s）" % [WALL_SPEED, d])
	if game._result != null:
		var texts: String = _all_text(game._result)
		_expect("70 km/h" in texts and "58 km/h" in texts and "12 不足" in texts
				and "壁の手前で速度が足りませんでした。" in texts, "AC-23 リザルトに 70 km/h・58 km/h（12 不足）・激突のヒント")
	_expect(not _game_state.record(1)["cleared"], "FR-46 失敗は記録しない")
	var fresh: Node = await _press_retry(game)
	_expect(fresh != game, "AC-9 リザルト中に R でやり直す")
	if fresh != game:
		_expect_restarted(fresh, 2, "リザルト中")
	return true


# FR-29, FR-45, FR-49, AC-12: ゴールでクリアを記録し（次のステージが解放される）、GOAL_RESULT_DELAY 秒後に合格のリザルト。
# 最高得点と★は大きいときだけ上がる
func _check_result_clear() -> bool:
	var data: Dictionary = _straight([_obj("crate", 600), _obj("dummy", 1000)])
	data["id"] = "stage_01"
	data["star_thresholds"] = [300, 1000]
	_game_state.erase_records()
	var game: Node = _new_game(data.duplicate(true))
	await _frames_until(func() -> bool: return game._finished)
	var r: Dictionary = _game_state.record(1)
	_expect(r["cleared"] and r["best_score"] == 400 and r["stars"] == 2 and _game_state.is_unlocked(2),
			"FR-29/48 ゴールでクリアを記録（最高 %d、★%d）し、第2試験が解放される" % [r["best_score"], r["stars"]])
	var goal_at: float = game._time
	await _frames_until(func() -> bool: return game._result != null or game._time >= goal_at + Tuning.GOAL_RESULT_DELAY + 1.0)
	var d: Dictionary = game.result_data()
	_expect(game._result != null and d["cleared"] and d["smashed"] == 2 and d["total"] == 2 and d["stars"] == 2
			and d["best_updated"] and not d["is_last"], "FR-45 合格のリザルト（破壊 2/2、★2、最高記録更新）")
	game.free()

	data["objects"] = [_obj("crate", 600)]  # 100点（前回の 400 より低い）
	game = _new_game(data.duplicate(true))
	await _frames_until(func() -> bool: return game._finished)
	r = _game_state.record(1)
	_expect(r["best_score"] == 400 and r["stars"] == 2 and not game.result_data()["best_updated"],
			"FR-49 低い得点では最高得点・★は下がらず、「最高記録更新」も出ない")
	game.free()
	_game_state.erase_records()
	return true


# 6.4, AC-14: 存在しないセグメントを参照するステージは「ステージデータエラー」を出し、STAGE_ERROR_DELAY 秒後にステージ選択へ戻る
func _check_stage_error() -> bool:
	var data: Dictionary = _straight([])
	data["segments"]["s0"]["end"] = {"type": "next", "segment": "no_such_segment"}
	var game: Node = _new_game(data)
	_expect(game._message.visible and game._message.text == "ステージデータエラー" and game._trolley == null,
			"AC-14 検証に通らないステージは「ステージデータエラー」を出して走らない")
	await create_timer(Tuning.STAGE_ERROR_DELAY + 0.1).timeout
	await _frames(2)
	var scene: Node = current_scene
	_expect(scene != null and scene.scene_file_path == "res://scenes/stage_select.tscn", "AC-14 その後ステージ選択に戻る")
	if scene != null:
		scene.free()
	return true


# FR-47b, FR-50a, AC-20: 音量40・揺れ OFF を保存して読み直すと、その値になり、SE バスの音量も 40% になる
func _check_settings_persist() -> bool:
	_game_state.set_se_volume(40)
	_game_state.set_screen_shake(false)
	_game_state.se_volume = Tuning.SE_VOLUME_DEFAULT
	_game_state.screen_shake = true
	_game_state.load_settings()
	var bus: int = AudioServer.get_bus_index(&"SE")
	_expect(_game_state.se_volume == 40 and not _game_state.screen_shake
			and is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.4)),
			"AC-20 音量40・揺れ OFF が保存され、読み直しても残る（SE バス %.1f dB）" % AudioServer.get_bus_volume_db(bus))
	_game_state.set_se_volume(Tuning.SE_VOLUME_DEFAULT)
	_game_state.set_screen_shake(true)
	return true


# M5 のレビューで直した3件
func _check_review_fixes() -> bool:
	# 1. start から届かない分岐の出口が合流で循環していても、検証が止まらずに違反を返す
	var data: Dictionary = _straight([])
	data["segments"]["a"] = {"points": [[0, 0], [2000, 0], [2000, 400], [0, 0]], "end": {"type": "next", "segment": "a"}}
	data["segments"]["b"] = {"points": [[0, 0], [2000, 0]], "end": {"type": "goal"}}
	data["junctions"]["j9"] = {"branches": ["a", "b"], "default": 0}
	var errors: Array[String] = StageLoader.validate(data)
	_expect(errors.any(func(e: String) -> bool: return e.ends_with("（7）")), "6.4 届かない分岐の先の循環も、止まらずに違反（7）を返す（%s）" % [errors])

	# 2. 解放されていないステージのクリアは記録せず、リザルトに「次の試験へ」を出さない
	_game_state.erase_records()
	_expect(not _game_state.submit_clear(3, 1000, 2) and not _game_state.record(3)["cleared"] and not _game_state.is_unlocked(4),
			"FR-41 未解放のステージ（第3試験）のクリアは記録しない")
	var stage: Dictionary = _straight([])
	stage["id"] = "stage_01"
	var game: Node = _new_game(stage)
	_game_state.erase_records()
	_game_state.submit_clear(1, 100, 1)
	_game_state.erase_records()  # プレイ中に記録を消した
	_expect(game.result_data()["is_last"], "記録を消した後のリザルトには「次の試験へ」を出さない（次が解放されていない）")
	game.free()

	# 3. リトライで差し替えを待っている古い画面は、フォーカスを失ってもポーズしない
	game = _new_game(_straight([]))
	await _frames(2)
	var fresh: Node = game.retry()
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_expect(not paused and game._pause == null, "リトライの差し替え待ちにフォーカスを失ってもポーズしない")
	await _frames(1)
	if fresh != game:
		_games.append(fresh)
	return true


# --- 補助 ---

## 本物の入力の経路（root → ポーズ画面など）で操作を送る
func _push_action(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		root.push_input(ev)


func _push_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)


## node の下にある Label・Button の文字をつなげる
func _all_text(node: Node) -> String:
	var out: String = ""
	for n: Node in node.find_children("*", "", true, false):
		if n is Label:
			out += (n as Label).text + "\n"
		elif n is Button:
			out += (n as Button).text + "\n"
	return out


func _remove_test_files() -> void:
	for path: String in [TEST_SETTINGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _repeat(v: float, n: int) -> Array[float]:
	var a: Array[float] = []
	for _i: int in n:
		a.append(v)
	return a


## s1 が required_speed 700 のジャンプ区間の直線コース
func _jump_stage() -> Dictionary:
	return {
		"id": "check", "name": "check", "ground_y": GROUND_Y, "start_segment": "s0", "star_thresholds": [1, 2],
		"segments": {
			"s0": {"points": [[0, RAIL_Y], [1000, RAIL_Y]], "end": {"type": "next", "segment": "s1"}},
			"s1": {"points": [[1000, RAIL_Y], [1200, RAIL_Y - 100], [1400, RAIL_Y]], "jump": {"required_speed": WALL_SPEED},
					"end": {"type": "next", "segment": "s2"}},
			"s2": {"points": [[1400, RAIL_Y], [3000, RAIL_Y]], "end": {"type": "goal"}},
		},
		"junctions": {},
		"objects": [],
	}


func _wall(offset: float) -> Dictionary:
	var od: Dictionary = _obj("wall", offset)
	od["required_speed"] = WALL_SPEED
	return od


func _straight(objects: Array) -> Dictionary:
	return {
		"id": "check", "name": "check", "ground_y": GROUND_Y, "start_segment": "s0", "star_thresholds": [1, 2],
		"segments": {"s0": {"points": [[0, RAIL_Y], [4000, RAIL_Y]], "end": {"type": "goal"}}},
		"junctions": {},
		"objects": objects,
	}


func _obj(type: String, offset: float) -> Dictionary:
	return {"type": type, "segment": "s0", "offset": offset}


## 回転した標的の四隅のうち一番下の y
func _bottom_y(t: Target) -> float:
	var s: Vector2 = t.body_size()
	var lowest: float = -INF
	for corner: Vector2 in [Vector2(-s.x * 0.5, 0.0), Vector2(s.x * 0.5, 0.0), Vector2(-s.x * 0.5, -s.y), Vector2(s.x * 0.5, -s.y)]:
		lowest = maxf(lowest, t.to_global(corner).y)
	return lowest


func _new_game(data: Dictionary) -> Node:
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.stage_data = data
	root.add_child(game)
	_games.append(game)
	return game


func _press_toggle(game: Node) -> void:
	_press(game, &"toggle_switch")


func _press(game: Node, action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	game._unhandled_input(ev)


func _run_until(game: Node, done: Callable) -> void:
	for _i: int in MAX_FRAMES:
		if done.call():
			return
		game._physics_process(DT)


func _frames(n: int) -> void:
	for _i: int in n:
		await physics_frame


func _frames_until(done: Callable) -> void:
	for _i: int in MAX_FRAMES:
		if done.call():
			return
		await physics_frame


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
