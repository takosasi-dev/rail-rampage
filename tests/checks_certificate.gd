extends SceneTree
## 修了証書とリザルトの「新しい検定印」の札の自動確認（設計書 docs/superpowers/specs/2026-09-26-records-design.md の
## 3.2, 3.3、FR-47a）。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_certificate.gd （失敗があれば終了コード1）
## 記録は確認用のファイルに差し替え、最後に消す。キーは root に InputEventKey を送り、実際の経路で通す。
## 画面が受けずに流したキーは、ゲーム画面の代わりに置いた Catcher が受ける（R はゲーム画面が受ける、FR-26）。

const RESULT_SCENE: String = "res://scenes/result.tscn"
const CERTIFICATE_SCENE: String = "res://scenes/certificate.tscn"
const TEST_SETTINGS: String = "user://checks_certificate_settings.cfg"
const TEST_SAVE: String = "user://checks_certificate_save.cfg"
const FPS: float = 60.0  # --fixed-fps 60
# 最終ステージの合格（検定印なし・修了証書なし）
const CLEARED: Dictionary = {
	"stage": 10, "stage_name": "最終試験", "cleared": true, "score": 40000, "smashed": 60, "total": 80,
	"max_combo": 30, "max_speed": 1090.0, "girigiri": 0, "stars": 2, "thresholds": [30000, 56000],
	"best_updated": true, "is_last": true, "fail_reason": "", "required_speed": 0.0, "reached_speed": 0.0,
	"new_stamps": [], "certificate": false,
}
const FAILED: Dictionary = {
	"stage": 3, "stage_name": "立ちはだかる壁", "cleared": false, "score": 1850, "smashed": 9, "total": 30,
	"max_combo": 5, "max_speed": 640.0, "girigiri": 0, "stars": 0, "thresholds": [2500, 5500],
	"best_updated": false, "is_last": false, "fail_reason": "激突", "required_speed": 700.0, "reached_speed": 580.0,
	"new_stamps": [], "certificate": false,
}
# 確認用の記録: ★の合計 28、最高得点の合計 55,000、修了日 2026-09-20
const STARS: Array[int] = [3, 3, 3, 3, 3, 3, 3, 3, 2, 2]
const SCORES: Array[int] = [1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000]
const COMPLETED_ON: String = "2026-09-20"
const MANY: Array[String] = ["basic", "all_clear", "combo_max", "top_speed", "big_score"]  # LIST の順


## ゲーム画面の代わり。画面が受けずに流した retry・ui_cancel・pause を数える
class Catcher extends Node:
	var seen: Array[StringName] = []

	func _unhandled_input(event: InputEvent) -> void:
		for action: StringName in [&"retry", &"ui_cancel", &"pause"]:
			if event.is_action_pressed(action):
				seen.append(action)


var _failed: int = 0
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前（GameState など）では参照できない。
# 同じ理由で、autoload を使うスクリプト（certificate.gd・result.gd など）の型名や preload もここでは使わない
var _game_state: Node
var _audio: Node
var _sounds: Array[StringName] = []  # 鳴らそうとした効果音
var _catcher: Catcher
var _emitted: Array[StringName] = []  # リザルトが出した合図と、修了証書の closed


func _initialize() -> void:
	_run.call_deferred()  # _initialize の時点では root がまだツリーに無く、_ready が走らない


func _run() -> void:
	_game_state = root.get_node("GameState")
	_audio = root.get_node("Audio")
	var real_settings: String = _game_state.settings_path
	var real_save: String = _game_state.save_path
	var real_shake: bool = _game_state.screen_shake
	_game_state.settings_path = TEST_SETTINGS
	_game_state.save_path = TEST_SAVE
	_game_state.screen_shake = true  # 遊んでいる人の設定に左右されないように。保存はしない
	_audio.played.connect(func(key: StringName) -> void: _sounds.append(key))
	_catcher = Catcher.new()
	root.add_child(_catcher)  # 画面より先に置く = 画面の後で _unhandled_input を受ける
	var checks: Array[Callable] = [_check_certificate_values, _check_certificate_blank, _check_certificate_keys,
			_check_certificate_stamp, _check_certificate_layout, _check_no_new_stamps, _check_few_new_stamps,
			_check_many_new_stamps, _check_new_stamps_order, _check_slip_layout, _check_certificate_button,
			_check_certificate_over_result]
	for check: Callable in checks:
		_write_records()
		# 各確認は最後に true を返す。スクリプトエラーで止まると null が返る
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
	Engine.time_scale = 1.0
	_remove_test_files()
	_game_state.settings_path = real_settings
	_game_state.save_path = real_save
	_game_state.screen_shake = real_shake
	_game_state.load_records()
	# 鳴っている効果音を止め、片付ける音声スレッドが回るまで少しだけ実時間で待つ（checks_result.gd と同じ）
	for p: Node in _audio.get_children():
		(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	for _i: int in 2:
		await process_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# --- 修了証書（設計書 3.3） ---

# 賞状の見出し・本文と、★の合計・最高得点の合計・修了日
func _check_certificate_values() -> bool:
	var c: Control = await _open_certificate()
	_expect((c.get_node("%Heading") as Label).text == "修了証書", "3.3 見出し「修了証書」")
	var text: String = (c.get_node("%Text") as Label).text
	_expect(text.replace("\n", "") == "あなたは RailRampage 衝突試験場の第1〜%d試験の全課程を修了したことをここに証します"
			% Tuning.STAGE_COUNT, "3.3 本文（%s）" % text)
	_expect((c.get_node("%Stars") as Label).text == "28 / %d" % (Tuning.STAGE_COUNT * Tuning.STARS_MAX),
			"3.3 ★の合計「28 / 30」（%s）" % (c.get_node("%Stars") as Label).text)
	_expect((c.get_node("%Score") as Label).text == "55,000 点", "3.3 最高得点の合計「55,000 点」（%s）" % (c.get_node("%Score") as Label).text)
	_expect((c.get_node("%Date") as Label).text == "2026年9月20日", "3.3 修了日「2026年9月20日」（%s）" % (c.get_node("%Date") as Label).text)
	c.free()
	return true


# 修了日が空（まだ修了していない）は「未修了」（TODO(spec)）。形の違う日付はそのまま出す
func _check_certificate_blank() -> bool:
	_remove_test_files()
	_game_state.load_records()
	var c: Control = await _open_certificate()
	_expect((c.get_node("%Date") as Label).text == "未修了" and (c.get_node("%Stars") as Label).text == "0 / 30"
			and (c.get_node("%Score") as Label).text == "0 点", "記録が無いときは「未修了」「0 / 30」「0 点」")
	_expect(c.date_text("2026-9-5") == "2026年9月5日" and c.date_text("いつか") == "いつか",
			"修了日の書き方（%s・%s）" % [c.date_text("2026-9-5"), c.date_text("いつか")])
	c.free()
	return true


# FR-47a: 「閉じる」（主ボタン）にフォーカスして開き、Enter・Space・Esc で closed。R・P・Esc は下の画面に流さない。
# 画面全体でマウスを受け止める（下のボタンを押させない）
func _check_certificate_keys() -> bool:
	var c: Control = await _open_certificate()
	var close: Button = c.get_node("%Close")
	_expect(close.has_focus() and close.get("primary") == true and close.text == "閉じる", "FR-47a 主ボタンの「閉じる」にフォーカスして開く")
	_expect(_sounds.is_empty(), "開いたときのフォーカスでは音を鳴らさない（%s）" % [_sounds])
	# headless の窓は小さいので、画面の大きさは content_scale_size（1280×720）で見る
	_expect(c.mouse_filter == Control.MOUSE_FILTER_STOP and c.size == Vector2(root.content_scale_size),
			"画面全体でマウスを受け止める（%s）" % c.size)
	for code: Key in [KEY_ENTER, KEY_SPACE]:
		_emitted.clear()
		_sounds.clear()
		await _key(code)
		_expect(_emitted == [&"closed"] and _sounds == [&"ui_select"], "FR-47a 「閉じる」を %s で決めると closed（%s, %s）"
				% [OS.get_keycode_string(code), _emitted, _sounds])
	_emitted.clear()
	_catcher.seen.clear()
	await _key(KEY_ESCAPE)
	_expect(_emitted == [&"closed"] and _catcher.seen.is_empty(), "FR-47a Esc で closed、下の画面へは流さない（%s, %s）" % [_emitted, _catcher.seen])
	_emitted.clear()
	await _key(KEY_R)
	await _key(KEY_P)
	_expect(_emitted.is_empty() and _catcher.seen.is_empty(), "R・P は受け止めて下の画面へ流さない（%s, %s）" % [_emitted, _catcher.seen])
	c.free()
	return true


# 「修了」の丸判子を、開いてから RESULT_STAMP_DELAY 秒後に（time_scale が小さくても実時間で）押す。紙を揺らして戻す
func _check_certificate_stamp() -> bool:
	_sounds.clear()
	Engine.time_scale = 0.05
	var c: Control = (load(CERTIFICATE_SCENE) as PackedScene).instantiate()
	root.add_child(c)
	var stamp: Control = c.get_node("%Stamp")
	var paper: Control = c.get_node("%Paper")
	var home: Vector2 = paper.position
	var frames: int = 0
	while not stamp.visible and frames < FPS:
		await process_frame
		frames += 1
	var t: float = frames / FPS
	_expect(absf(t - Tuning.RESULT_STAMP_DELAY) <= 2.0 / FPS, "判子は開いてから %.2f 秒後に押す（%.3f 秒、time_scale 0.05）" % [Tuning.RESULT_STAMP_DELAY, t])
	_expect(stamp.get("label") == "修了" and stamp.get("passed") == true and _sounds == [&"stamp"],
			"「修了」の丸判子を押して stamp を鳴らす（%s, %s）" % [stamp.get("label"), _sounds])
	var moved: float = 0.0
	for _i: int in ceili(Tuning.RESULT_SHAKE_TIME * FPS) + 3:
		await process_frame
		moved = maxf(moved, paper.position.distance_to(home))
	_expect(moved > 0.0 and paper.position == home, "判子で紙が揺れて元の位置に戻る（最大 %.1f px）" % moved)
	Engine.time_scale = 1.0
	c.free()
	return true


# 賞状の文字が紙の枠に収まり、判子が二重枠の内側にある。「閉じる」は画面の中
func _check_certificate_layout() -> bool:
	var c: Control = await _open_certificate()
	var paper: Control = c.get_node("%Paper")
	var body: Control = c.get_node("Paper/Body")
	_expect(body.get_combined_minimum_size().y <= body.size.y and body.size.x <= paper.size.x,
			"賞状の文字が紙に収まる（%s ≤ %s）" % [body.get_combined_minimum_size(), body.size])
	var inner := Rect2(Vector2.ZERO, paper.size).grow(-Tuning.CERT_FRAME_INSET - Tuning.CERT_FRAME_OUTER
			- Tuning.CERT_FRAME_GAP - Tuning.CERT_FRAME_INNER)
	var stamp := Rect2(Tuning.CERT_STAMP_POS, Tuning.RESULT_PASS_STAMP_SIZE)
	_expect(inner.encloses(stamp), "判子は二重枠の内側（%s）" % stamp)
	var rows: Control = c.get_node("%Rows")
	var rows_rect := Rect2(body.position + rows.position, rows.size)
	_expect(not rows_rect.intersects(stamp), "判子は★・得点・修了日の欄に重ならない（%s, %s）" % [rows_rect, stamp])
	var close: Control = c.get_node("%Close")
	_expect(Rect2(Vector2.ZERO, c.size).encloses(close.get_global_rect().grow(Tuning.UI_FOCUS_W * 2.0))
			and not paper.get_global_rect().grow(Tuning.UI_PANEL_SHADOW.y).intersects(close.get_global_rect()),
			"「閉じる」（フォーカスの枠ごと）は画面の中で、紙と影に重ならない")
	c.free()
	return true


# --- リザルトの「新しい検定印」の札（設計書 3.2） ---

# 新しい検定印が無ければ札を出さない（new_stamps が無いデータも同じ）
func _check_no_new_stamps() -> bool:
	for data: Dictionary in [CLEARED, FAILED]:
		var r: Control = await _open_result(data)
		_expect(not (r.get_node("%NewStamps") as Control).visible, "3.2 新しい検定印が無ければ札を出さない（%s）" % ("合格" if data["cleared"] else "不合格"))
		r.free()
	var old: Dictionary = CLEARED.duplicate()
	old.erase("new_stamps")
	old.erase("certificate")
	var r: Control = await _open_result(old)
	_expect(not (r.get_node("%NewStamps") as Control).visible and _visible_buttons(r) == ["リトライ", "ステージ選択へ"],
			"new_stamps・certificate の無いデータは、札も修了証書のボタンも出さない")
	r.free()
	return true


# 合格・不合格のどちらにも出す。RESULT_STAMPS_MAX 個以下なら全部並べ、「ほか」は出さない
func _check_few_new_stamps() -> bool:
	for data: Dictionary in [CLEARED, FAILED]:
		var d: Dictionary = data.duplicate()
		d["new_stamps"] = ["girigiri", "first_crash"]
		var r: Control = await _open_result(d)
		var slip: Control = r.get_node("%NewStamps")
		_expect(slip.visible and (r.get_node("%NewHeading") as Label).text == "新しい検定印"
				and _slip_names(r) == ["紙一重", "激突の記録"] and not (r.get_node("%NewMore") as Control).visible,
				"3.2 %s のリザルトに「新しい検定印」の札と名前を並べる（%s）" % ["合格" if data["cleared"] else "不合格", _slip_names(r)])
		r.free()
	return true


# 多いときは RESULT_STAMPS_MAX 個まで、残りは「ほか N 個」
func _check_many_new_stamps() -> bool:
	var d: Dictionary = CLEARED.duplicate()
	d["new_stamps"] = MANY
	var r: Control = await _open_result(d)
	var want: Array[String] = []
	for id: String in MANY.slice(0, Tuning.RESULT_STAMPS_MAX):
		want.append(Achievements.name_of(id))
	var more: Label = r.get_node("%NewMore")
	_expect(_slip_names(r) == want, "3.2 札には先頭の %d 個（%s）" % [Tuning.RESULT_STAMPS_MAX, _slip_names(r)])
	_expect(more.visible and more.text == "ほか %d 個" % (MANY.size() - Tuning.RESULT_STAMPS_MAX), "3.2 残りは「ほか N 個」（%s）" % more.text)
	r.free()
	return true


# 合否の判子の後に、RESULT_NEW_MARK_INTERVAL ごとに順に押す（time_scale が小さくても実時間で）。1つごとに stamp を鳴らす
func _check_new_stamps_order() -> bool:
	for data: Dictionary in [CLEARED, FAILED]:
		var d: Dictionary = data.duplicate()
		d["new_stamps"] = MANY
		_sounds.clear()
		Engine.time_scale = 0.05  # スローモーの途中で開いた場合
		var r: Control = _instance(d)
		root.add_child(r)
		var stamp: Control = r.get_node("%Stamp")
		var marks: Array[Control] = r.get("_marks")
		var at: Array[int] = [-1]  # 合否の判子と、小さな判子それぞれが見えたフレーム
		for _m: Control in marks:
			at.append(-1)
		var early: bool = false
		var frames: int = 0
		while at.has(-1) and frames < FPS * 3.0:
			await process_frame
			frames += 1
			if at[0] < 0 and stamp.visible:
				at[0] = frames
			for i: int in marks.size():
				if at[i + 1] < 0 and marks[i].modulate.a > 0.0:
					at[i + 1] = frames
					early = early or at[0] < 0
		var ok: bool = not at.has(-1) and not early
		for i: int in range(1, at.size()):
			ok = ok and absf((at[i] - at[i - 1]) / FPS - Tuning.RESULT_NEW_MARK_INTERVAL) <= 2.0 / FPS
		_expect(marks.size() == Tuning.RESULT_STAMPS_MAX and ok,
				"3.2 %s: 合否の判子の後に小さな判子を %.2f 秒ごとに順に押す（見えたフレーム %s）" % ["合格" if data["cleared"] else "不合格", Tuning.RESULT_NEW_MARK_INTERVAL, at])
		var want: Array[StringName] = []
		for _i: int in marks.size() + 1:
			want.append(&"stamp")
		_expect(_sounds == want, "判子を押すたびに stamp を鳴らす（%s）" % [_sounds])
		Engine.time_scale = 1.0
		r.free()
	return true


# 札は右列のボタンの上の空き: 報告書・ボタン（フォーカスの枠ごと）・画面の端に重ならない（多いときの大きさで）
func _check_slip_layout() -> bool:
	for data: Dictionary in [CLEARED, FAILED]:
		var d: Dictionary = data.duplicate()
		d["new_stamps"] = MANY
		d["certificate"] = data["cleared"]
		var r: Control = await _open_result(d)
		var slip: Rect2 = (r.get_node("%NewStamps") as Control).get_global_rect()
		var with_shadow: Rect2 = slip.merge(Rect2(slip.position + Tuning.UI_PANEL_SHADOW, slip.size))
		var buttons: Control = r.get_node("Buttons")
		var report: Rect2 = (r.get_node("Report") as Control).get_global_rect()
		var label: String = "合格" if data["cleared"] else "不合格"
		_expect(with_shadow.end.y <= buttons.global_position.y - Tuning.UI_FOCUS_W * 2.0,
				"3.2 %s: 札（影ごと）はボタンのフォーカスの枠より上（札の下端 %.0f、ボタンの上端 %.0f）" % [label, with_shadow.end.y, buttons.global_position.y])
		_expect(not with_shadow.intersects(report) and Rect2(Vector2.ZERO, r.size).encloses(with_shadow)
				and is_equal_approx(slip.size.x, buttons.size.x),
				"3.2 %s: 札は報告書に重ならず、画面の中で、ボタンと同じ幅（%s）" % [label, slip])
		r.free()
	return true


# --- 修了証書を受け取る（設計書 3.3） ---

# certificate が true なら、主ボタン「修了証書を受け取る」に初期フォーカス。文字はボタンの幅に収まる
func _check_certificate_button() -> bool:
	var d: Dictionary = CLEARED.duplicate()
	d["certificate"] = true
	d["new_stamps"] = ["all_clear"]
	var r: Control = await _open_result(d)
	var cert: Button = r.get_node("Buttons/Certificate")
	_expect(_visible_buttons(r) == ["修了証書を受け取る", "リトライ", "ステージ選択へ"],
			"3.3 ボタンは「修了証書を受け取る」「リトライ」「ステージ選択へ」（%s）" % [_visible_buttons(r)])
	_expect(cert.has_focus() and cert.get("primary") == true, "3.3, FR-47a 主ボタンの「修了証書を受け取る」にフォーカスして開く")
	var buttons: Control = r.get_node("Buttons")
	_expect(cert.get_combined_minimum_size().x <= buttons.size.x and is_equal_approx(cert.size.x, buttons.size.x),
			"「修了証書を受け取る」の文字とキー表示が右列の幅に収まる（%.0f ≤ %.0f）" % [cert.get_combined_minimum_size().x, buttons.size.x])
	r.free()
	return true


# 押すと修了証書をリザルトの上に重ねて開く。開いている間はリザルトのボタンにフォーカスが行かず、R・Esc は
# リザルトにもゲーム画面にも届かない（Esc は修了証書を閉じる）。閉じるとフォーカスが「修了証書を受け取る」に戻る
func _check_certificate_over_result() -> bool:
	var d: Dictionary = CLEARED.duplicate()
	d["certificate"] = true
	d["new_stamps"] = ["all_clear"]
	var r: Control = await _open_result(d)
	var cert: Button = r.get_node("Buttons/Certificate")
	await _key(KEY_ENTER)
	var c: Control = _certificate_in(r)
	_expect(c != null and _emitted.is_empty(), "3.3 「修了証書を受け取る」で修了証書をリザルトの上に開く（%s）" % [_emitted])
	if c == null:
		r.free()
		return true
	var close: Button = c.get_node("%Close")
	_expect(close.has_focus() and r.get_child(r.get_child_count() - 1) == c, "修了証書は一番上で、「閉じる」にフォーカス")
	for code: Key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		await _key(code)
	_expect(close.has_focus(), "修了証書を開いている間は、↑↓←→ でリザルトのボタンにフォーカスが行かない")
	_catcher.seen.clear()
	await _key(KEY_R)
	await _key(KEY_P)
	_expect(_emitted.is_empty() and _catcher.seen.is_empty() and is_instance_valid(c) and not c.is_queued_for_deletion(),
			"修了証書を開いている間の R・P は、リザルトにもゲーム画面にも届かない（%s, %s）" % [_emitted, _catcher.seen])
	await _key(KEY_ESCAPE)
	_expect(_emitted.is_empty() and _catcher.seen.is_empty(), "Esc は修了証書を閉じるだけで、リザルト・ゲーム画面には届かない（%s, %s）" % [_emitted, _catcher.seen])
	await process_frame
	_expect(not is_instance_valid(c) and cert.has_focus(), "閉じるとリザルトに戻り、フォーカスが「修了証書を受け取る」に戻る")
	await _key(KEY_DOWN)
	_expect((r.get_node("Buttons/Retry") as Button).has_focus(), "閉じた後はリザルトのボタンにまたフォーカスが行く")
	await _key(KEY_ESCAPE)
	_expect(_emitted == [&"select_requested"], "閉じた後の Esc はいつもどおり「ステージ選択へ」（%s）" % [_emitted])
	_emitted.clear()
	# マウスで押しても同じ（ボタンの pressed）。閉じるボタンで閉じる
	cert.pressed.emit()
	c = _certificate_in(r)
	await process_frame
	(c.get_node("%Close") as Button).pressed.emit()
	await process_frame
	_expect(not is_instance_valid(c) and cert.has_focus() and _emitted.is_empty(), "「閉じる」ボタンでも閉じてリザルトに戻る")
	r.free()
	return true


# --- 補助 ---

## 確認用の記録を書いて読み込む（第1〜10試験に合格、★と最高得点は STARS・SCORES、修了日 COMPLETED_ON）
func _write_records() -> void:
	var cfg := ConfigFile.new()
	for i: int in Tuning.STAGE_COUNT:
		var key: String = "stage_%02d" % (i + 1)
		cfg.set_value(key, "cleared", true)
		cfg.set_value(key, "best_score", SCORES[i])
		cfg.set_value(key, "stars", STARS[i])
	cfg.set_value("stats", "completed_on", COMPLETED_ON)
	cfg.save(TEST_SAVE)
	_game_state.load_records()


func _remove_test_files() -> void:
	for path: String in [TEST_SETTINGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 修了証書を開く。closed は _emitted に入る
func _open_certificate() -> Control:
	_sounds.clear()
	_emitted.clear()
	var c: Control = (load(CERTIFICATE_SCENE) as PackedScene).instantiate()
	c.connect(&"closed", func() -> void: _emitted.append(&"closed"))
	root.add_child(c)
	await process_frame
	return c


## setup(data) を済ませたリザルト（まだ木に入れていない）。出した合図は _emitted に入る
func _instance(data: Dictionary) -> Control:
	var r: Control = (load(RESULT_SCENE) as PackedScene).instantiate()
	r.setup(data)
	for sig: StringName in [&"retry_requested", &"next_requested", &"select_requested"]:
		r.connect(sig, func() -> void: _emitted.append(sig))
	return r


## リザルトを開く。コンテナの並べ替えは次のフレームなので、1フレーム待ってから返す
func _open_result(data: Dictionary) -> Control:
	_sounds.clear()
	_emitted.clear()
	var r: Control = _instance(data)
	root.add_child(r)
	await process_frame
	return r


## リザルトの上に開いている修了証書（無ければ null）
func _certificate_in(r: Control) -> Control:
	for n: Node in r.get_children():
		if n.scene_file_path == CERTIFICATE_SCENE and not n.is_queued_for_deletion():
			return n
	return null


## 札に並んだ検定印の名前
func _slip_names(r: Control) -> Array[String]:
	var out: Array[String] = []
	for row: Node in r.get_node("%NewList").get_children():
		out.append((row.get_child(1) as Label).text)
	return out


func _visible_buttons(r: Control) -> Array[String]:
	var out: Array[String] = []
	for b: Node in r.get_node("Buttons").get_children():
		if (b as Button).visible:
			out.append((b as Button).text)
	return out


## キーを押して離し、1フレーム進める
func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)
	await process_frame


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
