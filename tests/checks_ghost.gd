extends SceneTree
## ゴーストの自動確認（設計書 docs/superpowers/specs/2026-09-28-replay-value-design.md の6章）。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_ghost.gd （失敗があれば終了コード1）
## 遊んでいる人の設定・記録・ゴーストを上書きしないよう、GameState の保存先を確認用のファイルに差し替え、最後に消す。

const DT: float = 1.0 / 60.0
const MAX_FRAMES: int = 10000
const GAME_SCENE: String = "res://scenes/game.tscn"
const SETTINGS_SCENE: String = "res://scenes/settings.tscn"
const EXAMPLE_STAGE: String = "res://tests/example_stage.json"  # id は stage_01
const TEST_SETTINGS: String = "user://checks_ghost_settings.cfg"
const TEST_SAVE: String = "user://checks_ghost_save.cfg"
const SPEED: float = 300.0  # 記録の確かめに使う、まっすぐ一定の速さ（px/s）
const NEAR: float = 5.0  # 同じ経路・同じ速さのゴーストとトロッコの位置の差の許し（px。線路の角では点の間の直線が内側を通る）

var _failed: int = 0
var _game_state: Node  # -s のスクリプトは autoload の名前では参照できない
var _audio: Node


func _initialize() -> void:
	_run.call_deferred()  # _initialize の時点では root がまだツリーに無く、_ready が走らない


func _run() -> void:
	_game_state = root.get_node("GameState")
	_audio = root.get_node("Audio")
	var real_settings: String = _game_state.settings_path
	var real_save: String = _game_state.save_path
	_game_state.settings_path = TEST_SETTINGS
	_game_state.save_path = TEST_SAVE
	_remove_test_files()
	_game_state.load_settings()
	_game_state.load_records()
	var checks: Array[Callable] = [_check_recorder, _check_thinning, _check_player, _check_player_bad_data, _check_settings_row,
			_check_game, _check_no_endless]
	for check: Callable in checks:
		# 各確認は最後に true を返す。スクリプトエラーで止まると null が返る
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
		paused = false
	_remove_test_files()
	_game_state.settings_path = real_settings
	_game_state.save_path = real_save
	_game_state.load_settings()
	_game_state.load_records()
	for p: Node in _audio.get_children():
		(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	for _i: int in 2:
		await process_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# 記録: 物理フレーム（60fps）ごとに受けて、GHOST_SAMPLE_DT ごとに1点。点 k はちょうど時刻 k × dt の値（フレームの間を補う）
func _check_recorder() -> bool:
	var rec := GhostRecorder.new()
	var frames: int = 180  # 3秒
	for f: int in range(1, frames + 1):
		var t: float = f * DT
		rec.sample(t, Vector2(SPEED * t, 600.0 - t), 0.1 * t)
	var d: Dictionary = rec.data()
	var pts: PackedVector3Array = d["points"]
	var dt: float = d["dt"]
	var want: int = floori(frames * DT / Tuning.GHOST_SAMPLE_DT) + 1
	_expect(is_equal_approx(dt, Tuning.GHOST_SAMPLE_DT) and pts.size() == want,
			"3秒の走行は %.2f 秒ごとに %d 点（%.3f 秒・%d 点）" % [Tuning.GHOST_SAMPLE_DT, want, dt, pts.size()])
	var off: Array[String] = []
	for k: int in range(1, pts.size()):  # 点 0 は最初のフレームの値
		var t: float = k * dt
		if pts[k].distance_to(Vector3(SPEED * t, 600.0 - t, 0.1 * t)) > 0.01:
			off.append("%d %s" % [k, pts[k]])
	_expect(off.is_empty(), "点 k は時刻 k × dt の位置と回転（ずれ: %s）" % [off.slice(0, 3)])
	_expect(d.keys().size() == 2 and d.has("dt") and d.has("points"), "data() は dt と points だけ（得点・車両・塗装はゲーム画面が足す）")
	# data() は写し（後から記録が進んでも、渡した辞書は変わらない）
	rec.sample((frames + 30) * DT, Vector2.ZERO, 0.0)
	_expect((d["points"] as PackedVector3Array).size() == want, "data() で渡した点は後の記録で変わらない")
	return true


# 長い走行: 点が GHOST_MAX_POINTS に届いたら1つおきに間引き、間隔を倍にする。走行の最後まで残り、点の時刻は合ったまま
func _check_thinning() -> bool:
	var rec := GhostRecorder.new()
	var seconds: float = Tuning.GHOST_MAX_POINTS * Tuning.GHOST_SAMPLE_DT * 2.5
	var frames: int = ceili(seconds / DT)
	for f: int in range(1, frames + 1):
		var t: float = f * DT
		rec.sample(t, Vector2(SPEED * t, 600.0), 0.0)
	var d: Dictionary = rec.data()
	var pts: PackedVector3Array = d["points"]
	var dt: float = d["dt"]
	_expect(pts.size() < Tuning.GHOST_MAX_POINTS and pts.size() > Tuning.GHOST_MAX_POINTS / 4,
			"%.0f 秒の走行でも点は %d 未満（%d 点）" % [seconds, Tuning.GHOST_MAX_POINTS, pts.size()])
	_expect(is_equal_approx(dt, Tuning.GHOST_SAMPLE_DT * 4.0), "間引くたびに間隔は倍（%.2f → %.2f 秒）" % [Tuning.GHOST_SAMPLE_DT, dt])
	var last_t: float = (pts.size() - 1) * dt
	_expect(last_t <= frames * DT and frames * DT - last_t < dt, "最後の点は走行の終わり（%.2f 秒 / %.2f 秒）" % [last_t, frames * DT])
	var off: int = 0
	for k: int in range(1, pts.size()):
		if absf(pts[k].x - SPEED * k * dt) > 0.01:
			off += 1
	_expect(off == 0, "間引いた後も点 k は時刻 k × dt の位置（ずれ %d 点）" % off)
	return true


# 再生: 点の間を線形に補って位置と回転を動かす。最後の点を過ぎたら GHOST_FADE_TIME 秒で薄くなって消える。
# 当たり判定・光・音は無い。車体は一度描いたら描き直さない
func _check_player() -> bool:
	var g := GhostPlayer.new()
	root.add_child(g)
	var pts := PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(10.0, 20.0, 0.4), Vector3(30.0, 20.0, 0.2)])
	g.setup({"score": 100, "trolley": "heavy", "paint": 0, "dt": 0.1, "points": pts})
	g.advance(0.05)
	_expect(g.position.is_equal_approx(Vector2(5.0, 10.0)) and is_equal_approx(g.rotation, 0.2),
			"時刻 0.05 は点0と点1の真ん中（%s %.2f）" % [g.position, g.rotation])
	g.advance(0.175)
	_expect(g.position.is_equal_approx(Vector2(25.0, 20.0)) and is_equal_approx(g.rotation, 0.25),
			"時刻 0.175 は点1と点2の 3/4（%s %.3f）" % [g.position, g.rotation])
	_expect(g.visible and is_equal_approx(g.modulate.a, Palette.GHOST_TINT.a) and g.modulate.r == Palette.GHOST_TINT.r,
			"走っている間は墨の薄い色（Palette.GHOST_TINT）で半透明（%s）" % g.modulate)
	g.advance(0.2 + Tuning.GHOST_FADE_TIME * 0.5)
	_expect(g.visible and g.position.is_equal_approx(Vector2(30.0, 20.0))
			and is_equal_approx(g.modulate.a, Palette.GHOST_TINT.a * 0.5), "最後の点を過ぎると止まって薄くなる（%.2f）" % g.modulate.a)
	g.advance(0.2 + Tuning.GHOST_FADE_TIME + 0.01)
	_expect(not g.visible, "GHOST_FADE_TIME 秒で消える")
	var extra: Array[String] = []
	for n: Node in _all(g):
		if n is CollisionObject2D or n is Light2D or n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is CPUParticles2D:
			extra.append(n.get_class())
	_expect(extra.is_empty() and g.get_node_or_null("Visual") != null, "当たり判定・光・音・火花は無く、Visual に車体を描く（%s）" % [extra])
	# 車体は Trolley.draw_body と同じ絵（選んだ車両で描く）。ゴーストの最初の描画が済んでから、1つずつ描いて比べる
	await process_frame
	await process_frame
	Trolley.probe_on = true
	Trolley.probe = []
	var want: Node2D = Node2D.new()
	want.draw.connect(func() -> void: Trolley.draw_body(want, "heavy", 0))
	root.add_child(want)
	await process_frame
	await process_frame
	var body: Array = Trolley.probe.duplicate()
	Trolley.probe = []
	g.advance(0.0)  # 消えた後なので出し直す（隠れていると描かない）
	(g.get_node("Visual") as CanvasItem).queue_redraw()
	await process_frame
	await process_frame
	Trolley.probe_on = false
	_expect(not body.is_empty() and Trolley.probe == body, "車体は Trolley.draw_body と同じ絵（重量型）")
	Trolley.probe = []
	want.free()
	g.free()
	return true


# 壊れたデータ・空のデータでも止まらず、何も出さない
func _check_player_bad_data() -> bool:
	var bad: Array[Dictionary] = [{}, {"dt": 0.0, "points": PackedVector3Array([Vector3.ZERO])}, {"dt": 0.05, "points": []},
			{"dt": "x", "points": PackedVector3Array([Vector3.ZERO]), "trolley": 3, "paint": "gold"}]
	var shown: int = 0
	for d: Dictionary in bad:
		var g := GhostPlayer.new()
		root.add_child(g)
		g.setup(d)
		g.advance(1.0)
		if g.visible:
			shown += 1
		g.free()
	_expect(shown == 0, "壊れたゴーストのデータは何も出さない（出た: %d）" % shown)
	# 点が1つだけでも止まらない
	var one := GhostPlayer.new()
	root.add_child(one)
	one.setup({"dt": 0.05, "points": PackedVector3Array([Vector3(7.0, 8.0, 0.0)])})
	one.advance(0.0)
	_expect(one.visible and one.position == Vector2(7.0, 8.0), "点が1つのゴーストはその位置に出る")
	one.free()
	return true


# 設定の「ゲーム」タブ: 「ゴースト 表示／非表示」。「時間帯」の下（↓ で届く）、押すとすぐ保存、選んだ側が墨地
func _check_settings_row() -> bool:
	_game_state.load_settings()
	var s: Control = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	root.add_child(s)
	await process_frame
	var on: Button = s.get_node("%GhostOn")
	var off: Button = s.get_node("%GhostOff")
	_expect(on.text == "表示" and off.text == "非表示" and on.is_visible_in_tree(), "「ゲーム」タブに「ゴースト 表示／非表示」")
	_expect(_game_state.show_ghost and (on.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == Palette.INK,
			"初期値は表示（「表示」が墨地）")
	(s.get_node("%TimeSequence") as Control).grab_focus()
	await _key(KEY_DOWN)
	_expect(on.has_focus() or off.has_focus(), "「時間帯」から ↓ で「ゴースト」へ")
	on.grab_focus()
	await _key(KEY_RIGHT)
	_expect(off.has_focus(), "「表示」から → で「非表示」へ")
	await _key(KEY_SPACE)
	_expect(not _game_state.show_ghost and _saved("show_ghost") == false
			and (off.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == Palette.INK,
			"「非表示」を決定するとすぐ保存し、「非表示」が墨地になる")
	await _key(KEY_DOWN)
	_expect((s.get_node("%Erase") as Control).has_focus(), "「ゴースト」から ↓ で「記録を消去する…」へ")
	await _click(on)
	_expect(_game_state.show_ghost and _saved("show_ghost") == true, "「表示」はクリックでも選べる")
	s.free()
	return true


# ゲーム画面: 合格するとゴーストが残り、2回目の走行に出て、同じ走りならトロッコと重なって動く。非表示なら出さない
func _check_game() -> bool:
	_game_state.erase_records()
	_game_state.set_show_ghost(true)
	var first: Node = _new_game()
	_expect(first._ghost == null, "ゴーストが無い最初の走行には出さない")
	_run_until(first, func() -> bool: return first._finished)
	var saved: Dictionary = _game_state.ghost(1)
	_expect(first._message.text == "GOAL" and saved.get("score") == first.score and saved.get("trolley") == first.trolley_id
			and (saved.get("points", PackedVector3Array()) as PackedVector3Array).size() > 10,
			"合格するとゴースト（得点・車両・点）が残る（%d 点）" % (saved.get("points", PackedVector3Array()) as PackedVector3Array).size())
	first.free()
	_game_state._ghosts = null  # ファイルから読み直しても同じ
	_expect(_game_state.ghost(1).get("points") == saved.get("points"), "ゴーストはファイルに残る")
	var second: Node = _new_game()
	var g: GhostPlayer = second._ghost
	_expect(g != null and g.is_inside_tree() and g.visible, "2回目の走行にゴーストが出る")
	if g == null:
		second.free()
		return true
	var worst: float = 0.0
	for _i: int in 120:
		second._physics_process(DT)
		if second._time >= Tuning.GHOST_SAMPLE_DT:  # 点 0 は最初のフレームの値（時刻 0 の値は受け取れない）。その後から比べる
			worst = maxf(worst, g.global_position.distance_to(second._trolley.global_position))
	_expect(worst < NEAR, "同じ走りのゴーストはトロッコと重なって動く（差 %.2f px。分岐の角は点の間の直線で少し内側を通る）" % worst)
	_run_until(second, func() -> bool: return second._finished)
	for _i: int in ceili(Tuning.GHOST_FADE_TIME / DT) + 2:
		second._physics_process(DT)
	_expect(not g.visible, "ゴーストは最後の点を過ぎると消える")
	second.free()
	_game_state.set_show_ghost(false)
	var third: Node = _new_game()
	_expect(third._ghost == null and _find_ghost(third) == null, "ゴースト「非表示」なら出さない")
	third.free()
	_game_state.set_show_ghost(true)
	return true


# 無限軌道（担当 E）がまだ無くても壊れない: 試験の番号 0 のゴーストは無く、残さない。ゴーストの無い試験でも走る
func _check_no_endless() -> bool:
	_expect(_game_state.ghost(0).is_empty(), "試験 0（無限軌道）のゴーストは無い")
	_expect(not _game_state.submit_ghost(0, {"score": 1, "dt": 0.05, "points": PackedVector3Array([Vector3.ZERO])}),
			"試験 0（無限軌道）のゴーストは残さない")
	_expect(_game_state.ghost(2).is_empty(), "走っていない試験のゴーストは無い")
	return true


# --- 補助 ---

func _new_game() -> Node:
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.stage_data = StageLoader.load_json(EXAMPLE_STAGE)
	game.auto_pause = false
	root.add_child(game)
	game._trolley.fixed_speed = Tuning.SPEED_MAX
	return game


## ゲームを物理フレームで進める（エンジンの物理フレームは待たない。checks.gd と同じ）
func _run_until(game: Node, done: Callable) -> void:
	for _i: int in MAX_FRAMES:
		if done.call():
			return
		game._physics_process(DT)


func _find_ghost(n: Node) -> GhostPlayer:
	for c: Node in _all(n):
		if c is GhostPlayer:
			return c
	return null


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c: Node in n.get_children():
		out.append(c)
		out.append_array(_all(c))
	return out


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)
	await process_frame


func _click(c: Control) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = c.get_global_rect().get_center()
		ev.global_position = ev.position
		root.push_input(ev, true)
	await process_frame


## 確認用の settings.cfg に保存されている値（読めなければ null）
func _saved(key: String) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(TEST_SETTINGS) != OK:
		return null
	return cfg.get_value(_game_state.SECTION, key, null)


func _remove_test_files() -> void:
	for path: String in [TEST_SETTINGS, TEST_SAVE, _game_state.ghosts_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
