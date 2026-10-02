extends SceneTree
## リザルト「試験報告書」の自動確認（17.7、FR-45, FR-46, FR-46a、10章、AC-23、AC-9 のリザルトの部分）。
## 書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_result.gd （失敗があれば終了コード1）
## キーは root に InputEventKey を送り、フォーカス移動・ボタンの決定・Esc を実際の経路で通す。
## リザルトが受けずに流したキーは、ゲーム画面の代わりに置いた Catcher が受ける（R はゲーム画面が受ける、FR-26）。

const RESULT_SCENE: String = "res://scenes/result.tscn"
# ★2・最高記録更新（デザイン案 ResultClear の値）
const CLEARED: Dictionary = {
	"stage": 3, "stage_name": "立ちはだかる壁", "cleared": true, "score": 3640, "smashed": 24, "total": 30,
	"max_combo": 12, "max_speed": 1085.0, "girigiri": 1, "stars": 2, "thresholds": [2500, 5500],
	"best_updated": true, "is_last": false, "fail_reason": "", "required_speed": 0.0, "reached_speed": 0.0,
}
# AC-23: 必要速度 700 の wall に 580 px/s で激突（デザイン案 ResultFail の値）
const FAILED: Dictionary = {
	"stage": 3, "stage_name": "立ちはだかる壁", "cleared": false, "score": 1850, "smashed": 9, "total": 30,
	"max_combo": 5, "max_speed": 640.0, "girigiri": 0, "stars": 0, "thresholds": [2500, 5500],
	"best_updated": false, "is_last": false, "fail_reason": "激突", "required_speed": 700.0, "reached_speed": 580.0,
}
# FR-46a の文（仕様書からそのまま写す。画面側の定数とは別に持つ）
const HINT_CRASH: String = "壁の手前で速度が足りませんでした。手前の分岐で標的の多いルートを選ぶと、勢いが溜まって速くなります。"
const HINT_DERAIL: String = "ジャンプ台で速度が足りませんでした。手前の分岐で標的の多いルートを選ぶと、勢いが溜まって速くなります。"
const FPS: float = 60.0  # --fixed-fps 60


## ゲーム画面の代わり。リザルトが受けずに流した retry・ui_cancel を数える
class Catcher extends Node:
	var seen: Array[StringName] = []

	func _unhandled_input(event: InputEvent) -> void:
		for action: StringName in [&"retry", &"ui_cancel"]:
			if event.is_action_pressed(action):
				seen.append(action)


var _failed: int = 0
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前（GameState など）では参照できない。
# 同じ理由で、autoload を使うスクリプト（result.gd・ui_button.gd など）の型名や preload もここでは使わない
var _game_state: Node
var _audio: Node
var _sounds: Array[StringName] = []  # 鳴らそうとした効果音
var _catcher: Catcher
var _emitted: Array[StringName] = []  # リザルトが出した合図


func _initialize() -> void:
	_run.call_deferred()  # _initialize の時点では root がまだツリーに無く、_ready が走らない


func _run() -> void:
	_game_state = root.get_node("GameState")
	_audio = root.get_node("Audio")
	var real_shake: bool = _game_state.screen_shake
	_game_state.screen_shake = true  # 遊んでいる人の設定に左右されないように。保存はしない
	_audio.played.connect(func(key: StringName) -> void: _sounds.append(key))
	_catcher = Catcher.new()
	root.add_child(_catcher)  # リザルトより先に置く = リザルトの後で _unhandled_input を受ける
	var checks: Array[Callable] = [_check_failed_crash, _check_failed_derail, _check_cleared, _check_stars_line,
			_check_last_stage, _check_keys_cleared, _check_keys_failed, _check_stamp, _check_shake]
	for check: Callable in checks:
		# 各確認は最後に true を返す。スクリプトエラーで止まると null が返る
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
	Engine.time_scale = 1.0
	_game_state.screen_shake = real_shake
	# 鳴っている効果音を止め、片付ける音声スレッドが回るまで少しだけ実時間で待つ（checks_ui.gd と同じ。
	# 再生中のまま終えると、終了時に「resources still in use」が出る）
	for p: Node in _audio.get_children():
		(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	for _i: int in 2:
		await process_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# AC-23, FR-46, FR-46a: 不合格の報告書。必要速度・到達速度（不足分）・中止理由・中止時の得点・激突のヒント。★は出さない
func _check_failed_crash() -> bool:
	var r: Control = await _open(FAILED)
	var rows: Dictionary = _rows(r)
	_expect("必要速度 " + rows.get("必要速度", "") == "必要速度 70 km/h", "AC-23 「必要速度 70 km/h」（%s）" % rows.get("必要速度"))
	_expect("到達速度 " + rows.get("到達速度", "") == "到達速度 58 km/h（12 不足）",
			"AC-23 「到達速度 58 km/h（12 不足）」（%s）" % rows.get("到達速度"))
	_expect(rows.get("中止理由") == "激突", "FR-46 中止理由「激突」（%s）" % rows.get("中止理由"))
	_expect(rows.get("中止時の得点") == "1,850記録には残りません", "FR-46 中止時の得点に「記録には残りません」を併記（%s）" % rows.get("中止時の得点"))
	_expect(rows.get("試験名") == "第3試験　立ちはだかる壁", "試験名「第3試験　立ちはだかる壁」（%s）" % rows.get("試験名"))
	var hint: Label = r.get_node("%HintText")
	_expect((r.get_node("%Hint") as Control).visible and hint.text == HINT_CRASH, "AC-23, FR-46a 激突のヒント文（%s）" % hint.text)
	_expect(not (r.get_node("%Rating") as Control).visible and not rows.has("得点"), "FR-46 不合格では★と得点の欄を出さない")
	_expect((r.get_node("%ReportNo") as Label).text == "TEST REPORT\nNo.003", "見出し「TEST REPORT No.003」")
	var retry: Button = r.get_node("Buttons/Retry")
	var select: Button = r.get_node("Buttons/Select")
	_expect(_visible_buttons(r) == ["リトライ", "ステージ選択へ"], "FR-46 ボタンは「リトライ」「ステージ選択へ」（%s）" % [_visible_buttons(r)])
	_expect(retry.has_focus() and retry.get("primary") == true and select.get("primary") == false,
			"FR-46, FR-47a 主ボタンの「リトライ」にフォーカスして開く")
	r.free()
	return true


# FR-46a: 脱線のヒント
func _check_failed_derail() -> bool:
	var data: Dictionary = FAILED.duplicate()
	data["fail_reason"] = "脱線"
	var r: Control = await _open(data)
	_expect(_rows(r).get("中止理由") == "脱線" and (r.get_node("%HintText") as Label).text == HINT_DERAIL,
			"FR-46a 脱線のヒント文（%s）" % (r.get_node("%HintText") as Label).text)
	r.free()
	return true


# FR-45: 合格の報告書の各欄。「最高記録更新」は更新したときだけ
func _check_cleared() -> bool:
	var r: Control = await _open(CLEARED)
	var rows: Dictionary = _rows(r)
	_expect(rows.get("得点") == "3,640最高記録更新", "FR-45 得点「3,640」と「最高記録更新」の札（%s）" % rows.get("得点"))
	_expect(rows.get("破壊数") == "24 / 30", "FR-45 破壊数／総標的数「24 / 30」（%s）" % rows.get("破壊数"))
	_expect(rows.get("最大コンボ") == "12", "FR-45 最大コンボ「12」（%s）" % rows.get("最大コンボ"))
	_expect(rows.get("最高速度") == "108 km/h", "FR-43, FR-45 最高速度 1085 px/s →「108 km/h」（%s）" % rows.get("最高速度"))
	_expect(rows.get("ギリギリ突破") == "1 回", "FR-45 ギリギリ突破「1 回」（%s）" % rows.get("ギリギリ突破"))
	_expect((r.get_node("%Rating") as Control).visible and not (r.get_node("%Hint") as Control).visible
			and not rows.has("中止理由"), "FR-45 合格では★の欄を出し、ヒント・中止理由は出さない")
	_expect(_visible_buttons(r) == ["次の試験へ", "リトライ", "ステージ選択へ"], "FR-45 ボタンは「次の試験へ」「リトライ」「ステージ選択へ」（%s）" % [_visible_buttons(r)])
	var next: Button = r.get_node("Buttons/Next")
	_expect(next.has_focus() and next.get("primary") == true, "FR-45, FR-47a 主ボタンの「次の試験へ」にフォーカスして開く")
	_expect(_sounds.is_empty(), "開いたときのフォーカスでは音を鳴らさない（%s）" % [_sounds])
	r.free()
	var data: Dictionary = CLEARED.duplicate()
	data["best_updated"] = false
	r = await _open(data)
	_expect(_rows(r).get("得点") == "3,640", "FR-45 最高記録を更新していなければ札を出さない（%s）" % _rows(r).get("得点"))
	r.free()
	return true


# FR-45, 10章: ★3 未獲得なら「★3 まで あと N 点」、★2 未獲得なら ★2 までの点数。★3 なら行を出さない
func _check_stars_line() -> bool:
	for c: Array in [[2, 3640, "★3 まで あと 1,860 点"], [1, 1200, "★2 まで あと 1,300 点"], [3, 6000, ""]]:
		var data: Dictionary = CLEARED.duplicate()
		data["stars"] = c[0]
		data["score"] = c[1]
		var r: Control = await _open(data)
		var remain: Control = r.get_node("%Remain")
		var text: String = ""
		for l: Node in remain.get_children():
			text += (l as Label).text
		if c[2] == "":
			_expect(not remain.visible, "10章 ★3 では「あと N 点」の行を出さない")
		else:
			_expect(remain.visible and text == c[2], "FR-45 ★%d・%d 点で「%s」（%s）" % [c[0], c[1], c[2], text])
		r.free()
	return true


# FR-45: 最終ステージでは「次の試験へ」を出さない。初期フォーカスは「ステージ選択へ」（TODO(spec)）
func _check_last_stage() -> bool:
	var data: Dictionary = CLEARED.duplicate()
	data["is_last"] = true
	data["stars"] = 3
	var r: Control = await _open(data)
	_expect(_visible_buttons(r) == ["リトライ", "ステージ選択へ"], "FR-45 最終ステージでは「次の試験へ」を出さない（%s）" % [_visible_buttons(r)])
	_expect((r.get_node("Buttons/Select") as Button).has_focus(), "最終ステージは「ステージ選択へ」にフォーカスして開く")
	await _key(KEY_UP)
	_expect((r.get_node("Buttons/Retry") as Button).has_focus(), "FR-47a ↑ で隠れた「次の試験へ」を飛ばして「リトライ」へ")
	r.free()
	return true


# FR-45, FR-47a, AC-9: 合格の各ボタンを ↓ と Enter / Space で決めると、それぞれの合図を出す。判子の前でも効く。
# Esc は select_requested を出して受け止める。R は受けずにゲーム画面へ流す
func _check_keys_cleared() -> bool:
	var r: Control = await _open(CLEARED)
	var stamp: Control = r.get_node("%Stamp")
	await _key(KEY_ENTER)
	_expect(_emitted == [&"next_requested"] and not stamp.visible, "FR-45 「次の試験へ」で next_requested（判子の前でも効く）（%s）" % [_emitted])
	_expect(_sounds == [&"ui_select"], "決定で ui_select を鳴らす（%s）" % [_sounds])
	_emitted.clear()
	await _key(KEY_DOWN)
	_expect((r.get_node("Buttons/Retry") as Button).has_focus() and _sounds.has(&"ui_move"), "FR-47a ↓ で「リトライ」へ移り ui_move を鳴らす")
	await _key(KEY_SPACE)
	_expect(_emitted == [&"retry_requested"], "FR-26 「リトライ」を Space で決めると retry_requested（%s）" % [_emitted])
	_emitted.clear()
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_expect(_emitted == [&"select_requested"], "FR-45 「ステージ選択へ」で select_requested（%s）" % [_emitted])
	_emitted.clear()
	_catcher.seen.clear()
	await _key(KEY_ESCAPE)
	_expect(_emitted == [&"select_requested"] and _catcher.seen.is_empty(), "FR-47a Esc で select_requested を出し、下の画面へは流さない（%s, %s）" % [_emitted, _catcher.seen])
	_emitted.clear()
	await _key(KEY_R)
	_expect(_emitted.is_empty() and _catcher.seen == [&"retry"], "AC-9 R はリザルトでは受けず、ゲーム画面へ流す（%s, %s）" % [_emitted, _catcher.seen])
	r.free()
	return true


# FR-46: 不合格は開いたまま Space で retry_requested。↓ Enter で select_requested
func _check_keys_failed() -> bool:
	var r: Control = await _open(FAILED)
	await _key(KEY_SPACE)
	_expect(_emitted == [&"retry_requested"], "FR-46 不合格で Space を押すと retry_requested（%s）" % [_emitted])
	_emitted.clear()
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_expect(_emitted == [&"select_requested"], "FR-46 「ステージ選択へ」で select_requested（%s）" % [_emitted])
	r.free()
	return true


# 17.7: 判子は開いてから0.4秒後に押す（time_scale が小さくても実時間で）。押すと stamp を鳴らし、拡大率 1.6→1.0。
# 合格は -14度の丸、不合格は -10度の角
func _check_stamp() -> bool:
	_sounds.clear()
	for cleared: bool in [true, false]:
		Engine.time_scale = 0.05  # スローモー・ヒットストップの途中で開いた場合
		var r: Control = _instance(CLEARED if cleared else FAILED)
		var stamp: Control = r.get_node("%Stamp")
		root.add_child(r)
		var frames: int = 0
		while not stamp.visible and frames < FPS:
			await process_frame
			frames += 1
		var t: float = frames / FPS
		_expect(absf(t - Tuning.RESULT_STAMP_DELAY) <= 2.0 / FPS, "17.7 判子は開いてから %.2f 秒後に押す（%.3f 秒、time_scale 0.05）" % [Tuning.RESULT_STAMP_DELAY, t])
		_expect(_sounds == [&"stamp"], "17.7 判子を押すと stamp を鳴らす（%s）" % [_sounds])
		_expect(stamp.scale.x > 1.0 + 0.1, "17.7 押した瞬間は拡大している（%.2f）" % stamp.scale.x)
		for _i: int in ceili(Tuning.RESULT_STAMP_POP_TIME * FPS) + 1:
			await process_frame
		var deg: float = Tuning.RESULT_PASS_STAMP_DEG if cleared else Tuning.RESULT_FAIL_STAMP_DEG
		var want_size: Vector2 = Tuning.RESULT_PASS_STAMP_SIZE if cleared else Tuning.RESULT_FAIL_STAMP_SIZE
		_expect(stamp.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(rad_to_deg(stamp.rotation), deg)
				and stamp.size == want_size, "17.7 %s の判子は %.0f度・%s で 1.0 に戻る" % ["合格" if cleared else "不合格", deg, want_size])
		Engine.time_scale = 1.0
		r.free()
		_sounds.clear()
	return true


# 17.7, FR-36: 判子で報告書を振幅6pxで0.15秒揺らし、元の位置に戻す。揺れの設定が OFF なら揺らさない
func _check_shake() -> bool:
	for shake_on: bool in [true, false]:
		_game_state.screen_shake = shake_on
		var r: Control = await _open(CLEARED)
		var report: Control = r.get_node("Report")
		var home: Vector2 = report.position
		var moved: float = 0.0
		for _i: int in ceili((Tuning.RESULT_STAMP_DELAY + Tuning.RESULT_SHAKE_TIME) * FPS) + 3:
			await process_frame
			moved = maxf(moved, report.position.distance_to(home))
		if shake_on:
			_expect(moved > 0.0 and moved <= Tuning.RESULT_SHAKE_AMP * sqrt(2.0), "17.7 判子で報告書が揺れる（最大 %.1f px）" % moved)
			_expect(report.position == home, "17.7 揺れた後は元の位置に戻る")
		else:
			_expect(moved == 0.0, "FR-36 揺れの設定が OFF なら揺らさない（最大 %.1f px）" % moved)
		r.free()
	_game_state.screen_shake = true
	return true


# --- 補助 ---

## setup(data) を済ませたリザルト（まだ木に入れていない）。出した合図は _emitted に入る
func _instance(data: Dictionary) -> Control:
	var r: Control = (load(RESULT_SCENE) as PackedScene).instantiate()
	r.setup(data)
	for sig: StringName in [&"retry_requested", &"next_requested", &"select_requested"]:
		r.connect(sig, func() -> void: _emitted.append(sig))
	return r


## リザルトを開く。コンテナの並べ替えは次のフレームなので、1フレーム待ってから返す
func _open(data: Dictionary) -> Control:
	_sounds.clear()
	_emitted.clear()
	var r: Control = _instance(data)
	root.add_child(r)
	await process_frame
	return r


## 報告書の欄。ラベル → 値（値の部品の文字をつないだもの）
func _rows(r: Control) -> Dictionary:
	var grid: GridContainer = r.get_node("%Grid")
	var out: Dictionary = {}
	for i: int in range(0, grid.get_child_count(), grid.columns):
		var value: String = ""
		for part: Node in grid.get_child(i + 1).get_children():
			value += (part as Label).text
		out[(grid.get_child(i) as Label).text] = value
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
