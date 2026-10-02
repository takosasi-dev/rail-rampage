extends SceneTree
## 試験記録の画面とタイトルの「試験記録」の自動確認（設計書 docs/superpowers/specs/2026-09-26-records-design.md の 3.1、FR-47a）。
## 書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_records_screen.gd （失敗があれば終了コード1）
## 遊んでいる人の設定・記録を上書きしないよう、GameState の保存先を確認用のファイルに差し替え、最後に消す。
## 画面は change_scene_to_file で開き、キーとマウスは root に送って実際の経路で通す。

const TITLE_SCENE: String = "res://scenes/title.tscn"
const RECORDS_SCENE: String = "res://scenes/records.tscn"
const CERTIFICATE_SCENE: String = "res://scenes/certificate.tscn"
const TEST_SETTINGS: String = "user://checks_records_screen_settings.cfg"
const TEST_SAVE: String = "user://checks_records_screen_save.cfg"
const SCENE_WAIT_FRAMES: int = 10  # 画面の切り替えを待つ上限
const COLUMNS: int = 8  # 検定印の格子（8列 × 4行、最後の行は6個）
const ROWS: int = 4
const CORNER: int = COLUMNS * (ROWS - 1)  # 左下の印
const STAMP_TEXT_MARGIN: float = 3.0  # 判子の名前の字の箱と内側の輪の間に空ける（1px だと写しで輪に触れて見えた）
## 確かめに使う走行（設計書 2.2 のキー）。B で倍率上限・連鎖反応・最高速度・激突の記録、C で脱線の記録を取る
const RUNS: Array[Dictionary] = [
	{"stage": 1, "outcome": "clear", "smashed": {"crate": 12, "barrel": 3, "dummy": 2}, "girigiri": 1, "max_combo": 9,
		"max_speed": 812.0, "distance": 18000.0, "chained": 0, "toggles": 2, "score": 5000},
	{"stage": 2, "outcome": "crash", "smashed": {"crate": 5, "drum": 2, "wall": 1}, "girigiri": 0, "max_combo": 25,
		"max_speed": 1095.0, "distance": 9000.5, "chained": 2, "toggles": 1, "score": 3000},
	{"stage": 1, "outcome": "derail", "smashed": {"dummy": 4}, "girigiri": 1, "max_combo": 3,
		"max_speed": 640.0, "distance": 4000.0, "chained": 0, "toggles": 0, "score": 800}]
const RUN_STAMPS: Array[String] = ["combo_max", "chain", "top_speed", "first_crash", "first_derail"]

var _failed: int = 0
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前（GameState など）では参照できない
var _game_state: Node
var _audio: Node
var _sounds: Array[StringName] = []  # 鳴らそうとした効果音


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
	_game_state.load_records()  # 確認用のファイルが無い = 初期状態から始める
	_audio.played.connect(func(key: StringName) -> void: _sounds.append(key))
	var checks: Array[Callable] = [_check_title, _check_title_layout, _check_blank, _check_values, _check_stamps,
			_check_grid, _check_mouse, _check_certificate, _check_glyphs, _check_layout]
	for check: Callable in checks:
		# 各確認は最後に true を返す。スクリプトエラーで止まると null が返る
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
	if current_scene != null:
		unload_current_scene()
	_remove_test_files()
	_game_state.settings_path = real_settings
	_game_state.save_path = real_save
	_game_state.load_settings()
	_game_state.load_records()
	# 鳴っている効果音を止め、片付ける音声スレッドが回るまで少しだけ実時間で待つ（checks_ui.gd と同じ）
	for p: Node in _audio.get_children():
		(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	for _i: int in 2:
		await process_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# タイトルの「試験記録」: 「試験開始」の ↓ で届き、Enter で試験記録を開く。Esc と「戻る」でタイトルに戻る
func _check_title() -> bool:
	_game_state.erase_records()
	var t: Control = await _open(TITLE_SCENE)
	if t == null:
		return true
	var start: Button = t.get_node("Menu/Start")
	var records: Button = t.get_node("Menu/Records")
	var texts: Array[String] = []
	for path: String in ["Menu/Start", "Menu/Records", "Menu/Row/Settings", "Menu/Row/Quit"]:
		texts.append((t.get_node(path) as Button).text)
	_expect(texts == ["試験開始", "試験記録", "設定", "終了"] and (t.get_node("Menu/Row/Quit") as Button).visible,
			"タイトルのボタンは「試験開始」「試験記録」「設定」「終了」（%s）" % [texts])
	_expect((start as Object).get("primary") == true and (records as Object).get("primary") == false,
			"主ボタンは「試験開始」のまま、「試験記録」は副ボタン")
	_sounds.clear()
	await _key(KEY_DOWN)
	_expect(records.has_focus() and _sounds == [&"ui_move"], "↓ で「試験記録」へ移り ui_move を鳴らす（%s）" % [_sounds])
	await _key(KEY_DOWN)
	_expect((t.get_node("Menu/Row/Settings") as Button).has_focus(), "もう一度 ↓ で「設定」へ")
	await _key(KEY_UP)
	_sounds.clear()
	await _key(KEY_ENTER)
	var s: Control = await _current(RECORDS_SCENE, "「試験記録」で Enter → 試験記録の画面")
	if s == null:
		return true
	_expect(_sounds == [&"ui_select"], "開いた画面のフォーカスでは音を鳴らさない（決定の ui_select だけ。%s）" % [_sounds])
	_expect(s.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED, "試験記録の画面は紙の粒を敷き詰められる")
	_sounds.clear()
	await _key(KEY_ESCAPE)
	_expect(await _wait_scene(TITLE_SCENE) and _sounds == [&"ui_select"], "FR-47a Esc でタイトルへ戻る（%s）" % [_sounds])
	s = await _open(RECORDS_SCENE)
	var back: Button = s.get_node("%Back")
	for _i: int in ROWS:
		await _key(KEY_DOWN)
	_expect(back.has_focus(), "最初の印から ↓ %d 回で「戻る」" % ROWS)
	await _key(KEY_ENTER)
	_expect(await _wait_scene(TITLE_SCENE), "「戻る」を決定するとタイトルへ戻る")
	s = await _open(RECORDS_SCENE)
	await _click(s.get_node("%Back"))
	_expect(await _wait_scene(TITLE_SCENE), "「戻る」をクリックしてもタイトルへ戻る")
	return true


# タイトルのボタンが4つになっても、操作の案内・バージョン・挿絵と重ならない（フォーカスの枠も含めて）
func _check_title_layout() -> bool:
	var t: Control = await _open(TITLE_SCENE)
	if t == null:
		return true
	var ring: float = Tuning.UI_FOCUS_W * 2.0  # フォーカスの枠はボタンの外に墨と警告黄で 8px
	var overlaps: Array[String] = []
	for path: String in ["Menu/Start", "Menu/Records", "Menu/Row/Settings", "Menu/Row/Quit"]:
		var r: Rect2 = (t.get_node(path) as Control).get_global_rect().grow(ring)
		for other: String in ["Help", "Version", "Art"]:
			var o: Control = t.get_node(other)
			var text_rect: Rect2 = o.get_global_rect()
			if o is Label:  # 案内は下寄せ。字のある高さだけ見る
				var l: Label = o
				var h: float = l.get_theme_font(&"font").get_height(l.get_theme_font_size(&"font_size"))
				text_rect = Rect2(text_rect.position.x, text_rect.end.y - h, text_rect.size.x, h)
			if r.intersects(text_rect):
				overlaps.append("%s と %s" % [path.get_file(), other])
	_expect(overlaps.is_empty(), "タイトルのボタン（枠を含む）は操作の案内・バージョン・挿絵と重ならない（重なる: %s）" % [overlaps])
	var settings: Rect2 = (t.get_node("Menu/Row/Settings") as Control).get_global_rect()
	var quit_rect: Rect2 = (t.get_node("Menu/Row/Quit") as Control).get_global_rect()
	var menu: Rect2 = (t.get_node("Menu") as Control).get_global_rect()
	_expect(is_equal_approx(settings.position.y, quit_rect.position.y) and settings.end.x < quit_rect.position.x
			and menu.encloses(quit_rect), "「設定」と「終了」は横に並び、メニューの幅に収まる（%s %s）" % [settings, quit_rect])
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	_expect((t.get_node("Menu/Row/Quit") as Button).has_focus(), "「設定」から → で「終了」へ")
	await _key(KEY_UP)
	_expect((t.get_node("Menu/Records") as Button).has_focus(), "「終了」から ↑ で「試験記録」へ")
	return true


# 記録が無いとき: 表はすべて0、印はすべて「？」、修了証書は押せず、最初の印にフォーカス
func _check_blank() -> bool:
	_game_state.erase_records()
	var s: Control = await _open(RECORDS_SCENE)
	if s == null:
		return true
	var values: Array[String] = []
	for key: String in ["%Runs", "%Results", "%Girigiri", "%Speed", "%Combo", "%Distance", "%Smashed", "%Count"]:
		values.append(_text(s, key))
	_expect(values == ["0 回", "0 / 0 / 0", "0 回", "0 km/h", "0", "0 m", "合計 0", "0 / 30"],
			"記録が無ければ表は0、検定印は 0 / 30（%s）" % [values])
	var all_locked: bool = true
	for i: int in Achievements.LIST.size():
		all_locked = all_locked and s.stamp_lines(i) == PackedStringArray(["？"])
	_expect(all_locked, "記録が無ければ印はすべて「？」")
	var cert: Button = s.get_node("%Cert")
	_expect(cert.disabled and cert.focus_mode == Control.FOCUS_NONE and _text(s, "%CertHint") == "第1〜10試験の合格で交付",
			"全試験に合格していなければ「修了証書」は押せない（%s）" % _text(s, "%CertHint"))
	_expect(_cell(s, 0).has_focus() and s.shown == 0 and _text(s, "%DetailName") == "基礎課程修了" and _text(s, "%Date") == "未取得",
			"開くと最初の印にフォーカスし、説明欄はその印（%s %s）" % [_text(s, "%DetailName"), _text(s, "%Date")])
	var bg: Color = (cert.get_theme_stylebox("disabled") as StyleBoxFlat).bg_color
	_expect(bg == Palette.BOARD and cert.get_theme_color(&"font_disabled_color") == Palette.MUTED,
			"押せない「修了証書」は未解放のカードと同じ地・補助文字の色")
	await _click(cert)
	_expect(_overlay(s) == null and current_scene == s, "押せない「修了証書」をクリックしても開かない")
	return true


# 累計の値（submit_run で作る）が表に出る。最高速度は km/h、距離は Display.distance_text
func _check_values() -> bool:
	_game_state.erase_records()
	var today: String = Time.get_date_string_from_system()
	for run: Dictionary in RUNS:
		_game_state.submit_run(run)
	var st: Dictionary = _game_state.stats()
	var s: Control = await _open(RECORDS_SCENE)
	if s == null:
		return true
	var want: Dictionary = {"%Runs": "3 回", "%Results": "1 / 1 / 1", "%Girigiri": "2 回", "%Speed": "109 km/h",
			"%Combo": "25", "%Distance": Display.distance_text(31000.5), "%Smashed": "合計 29", "%Count": "5 / 30"}
	var got: Dictionary = {}
	for key: String in want:
		got[key] = _text(s, key)
	_expect(got == want, "累計の表（%s）" % [got])
	_expect(Display.distance_text(st["distance"]) == "861 m", "走った距離 31000.5px は 861 m（%s）" % Display.distance_text(st["distance"]))
	var counts: Array[String] = []
	for box: Node in s.get_node("%Targets").get_children():
		counts.append((box.get_node("Count") as Label).text)
	_expect(counts == ["17", "3", "6", "2", "1"], "壊した標的は種類（木箱・樽・人形・ドラム缶・壁）ごとの数（%s）" % [counts])
	_expect(s._got.keys().size() == RUN_STAMPS.size() and RUN_STAMPS.all(func(id: String) -> bool: return s._got.get(id) == today),
			"画面の検定印は GameState.stamps() と同じ（%s）" % [s._got])
	# 大きい数は3桁区切り、距離は km
	var big: Dictionary = {"stage": 3, "outcome": "abort", "smashed": {"crate": 12345}, "girigiri": 0, "max_combo": 0,
			"max_speed": 0.0, "distance": 36000.0 * 12.3, "chained": 0, "toggles": 1, "score": 0}
	_game_state.submit_run(big)
	s = await _open(RECORDS_SCENE)
	_expect(_text(s, "%Runs") == "4 回" and (s.get_node("%Targets").get_child(0).get_node("Count") as Label).text == "12,362"
			and _text(s, "%Smashed") == "合計 12,374" and _text(s, "%Distance") == Display.distance_text(31000.5 + 36000.0 * 12.3)
			and _text(s, "%Results") == "1 / 1 / 1",
			"途中でやめた走行も回数に入り、数は3桁区切り、距離は km（%s %s %s）" % [_text(s, "%Runs"), _text(s, "%Smashed"), _text(s, "%Distance")])
	return true


# 取った印と取っていない印の見分け（判子の中の字と説明欄）。説明欄はフォーカスした印の名前・条件・取った日
func _check_stamps() -> bool:
	_game_state.erase_records()
	for run: Dictionary in RUNS:
		_game_state.submit_run(run)
	var today: String = Time.get_date_string_from_system()
	var s: Control = await _open(RECORDS_SCENE)
	if s == null:
		return true
	var bad: Array[String] = []
	for i: int in Achievements.LIST.size():
		var id: String = Achievements.LIST[i][0]
		var lines: PackedStringArray = s.stamp_lines(i)
		var ok: bool = "".join(lines) == Achievements.name_of(id) if RUN_STAMPS.has(id) else lines == PackedStringArray(["？"])
		if not ok:
			bad.append("%s %s" % [id, lines])
	_expect(bad.is_empty(), "取った印は判子に名前、取っていない印は「？」（違う: %s）" % [bad])
	_expect(s.stamp_lines(4) == PackedStringArray(["倍率", "上限"]) and s.stamp_lines(10) == PackedStringArray(["激突の", "記録"]),
			"4字以上の名前は最後の2字を2行目にする（%s %s）" % [s.stamp_lines(4), s.stamp_lines(10)])
	_expect(Tuning.RECORDS_STAMP_DEG.size() == Achievements.LIST.size(), "判子の傾きは印 %d 個分（%d）" % [
			Achievements.LIST.size(), Tuning.RECORDS_STAMP_DEG.size()])
	# 判子の名前（全部取ったとき）の字の箱の角は、内側の輪の内縁より STAMP_TEXT_MARGIN 以上内にある（records.gd の _draw_lines と同じ並べ方）
	var real_got: Dictionary = s._got
	var all_got: Dictionary = {}
	for a: Array in Achievements.LIST:
		all_got[a[0]] = "x"
	s._got = all_got
	var font: Font = Fonts.BIZ_BOLD
	var fs: int = Tuning.RECORDS_STAMP_FONT_SIZE
	var line_h: float = font.get_height(fs)
	var edge: float = Tuning.RECORDS_STAMP_R - Tuning.RECORDS_STAMP_W - Tuning.RECORDS_STAMP_INNER_GAP - Tuning.RECORDS_STAMP_INNER_W \
			- STAMP_TEXT_MARGIN
	var outside: Array[String] = []
	for i: int in Achievements.LIST.size():
		var lines: PackedStringArray = s.stamp_lines(i)
		for k: int in lines.size():
			var half_w: float = font.get_string_size(lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
			var ys: Array[float] = [-line_h * lines.size() * 0.5 + line_h * k, -line_h * lines.size() * 0.5 + line_h * (k + 1)]
			for y: float in ys:
				if Vector2(half_w, y).length() > edge:
					outside.append("%s（%.1f > %.1f）" % [lines[k], Vector2(half_w, y).length(), edge])
	s._got = real_got
	_expect(outside.is_empty(), "判子の名前は内側の輪の中に収まる（はみ出す: %s）" % [outside])
	_sounds.clear()
	await _key(KEY_RIGHT)  # 全課程修了（取っていない）
	_expect(s.shown == 1 and _text(s, "%DetailName") == "全課程修了" and _text(s, "%Date") == "未取得"
			and _text(s, "%Condition") == Achievements.describe("all_clear") and _text(s, "%DetailNum") == "No.02"
			and _sounds == [&"ui_move"], "→ で説明欄が「全課程修了」に変わり ui_move を鳴らす（%s %s）" % [_text(s, "%Condition"), _sounds])
	await _key(KEY_DOWN)  # 大台（取っていない）
	_expect(s.shown == 9 and _text(s, "%DetailName") == "大台", "↓ で下の行の印へ（%d）" % s.shown)
	await _key(KEY_UP)
	for _i: int in 4:
		await _key(KEY_RIGHT)  # 連鎖反応（取った）
	var date: Label = s.get_node("%Date")
	_expect(s.shown == 5 and _text(s, "%DetailName") == "連鎖反応" and date.text == "取得日　" + today
			and date.get_theme_color(&"font_color") == Palette.HAZARD and _text(s, "%Condition") == Achievements.describe("chain"),
			"取った印は説明欄に取った日（%s %s）" % [_text(s, "%DetailName"), date.text])
	_expect(_text(s, "%Condition") == "1回の走行で、爆発に巻き込まれたドラム缶が2個以上爆発する", "条件の文は数値が入っている（%s）" % _text(s, "%Condition"))
	for _i: int in ROWS - 1:
		await _key(KEY_DOWN)  # 13・21・29
	await _key(KEY_DOWN)  # 「戻る」
	_expect(s.get_node("%Back").has_focus() and s.shown == 29, "ボタンにフォーカスが移っても説明欄は最後の印のまま（%d）" % s.shown)
	return true


# ←→↑↓ で格子の中を動き、端から先に何も無い向きは動かない。下端の ↓ は「戻る」、「戻る」の ↑ は左下の印
func _check_grid() -> bool:
	_game_state.erase_records()
	var s: Control = await _open(RECORDS_SCENE)
	if s == null:
		return true
	var path: Array[int] = []
	var steps: Array = [KEY_RIGHT, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT,
			KEY_DOWN, KEY_LEFT, KEY_DOWN, KEY_UP]
	for k: Key in steps:
		await _key(k)
		path.append(_focused_cell(s))
	_expect(path == [1, 2, 3, 4, 5, 6, 7, 7, 15, 14, 22, 14], "←→↑↓ で格子の中を動き、右端の → は動かない（%s）" % [path])
	# 最後の行（6個）の右に空きがある列（22・23）の ↓ は「戻る」
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	_expect(s.get_node("%Back").has_focus(), "下に印の無い列の ↓ は「戻る」")
	await _key(KEY_UP)
	_expect(_focused_cell(s) == CORNER, "「戻る」の ↑ は左下の印（%d）" % _focused_cell(s))
	for k: Key in [KEY_UP, KEY_UP, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT]:
		await _key(k)  # 14 へ戻す
	_sounds.clear()
	for k: Key in [KEY_UP, KEY_UP, KEY_UP]:
		await _key(k)
	_expect(_focused_cell(s) == 6 and _sounds == [&"ui_move"], "上端の ↑ は動かず、音も鳴らさない（%d %s）" % [_focused_cell(s), _sounds])
	for _i: int in COLUMNS:
		await _key(KEY_LEFT)
	_expect(_focused_cell(s) == 0, "左端の ← は、修了証書を押せないときは動かない（%d）" % _focused_cell(s))
	for _i: int in ROWS:
		await _key(KEY_DOWN)
	var back: Button = s.get_node("%Back")
	_expect(back.has_focus(), "下端の ↓ で「戻る」へ")
	for k: Key in [KEY_LEFT, KEY_DOWN]:
		await _key(k)
	_expect(back.has_focus(), "「戻る」の ← ↓ は動かない")
	await _key(KEY_UP)
	_expect(_focused_cell(s) == CORNER, "「戻る」の ↑ は左下の印（修了証書を押せないとき）（%d）" % _focused_cell(s))
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	_expect(_focused_cell(s) == CORNER, "「戻る」の → も左下の印")
	await _key(KEY_SPACE)
	_expect(current_scene == s and _overlay(s) == null and _focused_cell(s) == CORNER, "印の上の Space は何もしない")
	return true


# マウスを乗せた印の説明を出す（フォーカスも移る）
func _check_mouse() -> bool:
	_game_state.erase_records()
	for run: Dictionary in RUNS:
		_game_state.submit_run(run)
	var s: Control = await _open(RECORDS_SCENE)
	if s == null:
		return true
	_sounds.clear()
	await _hover(_cell(s, 10))
	_expect(s.shown == 10 and _cell(s, 10).has_focus() and _text(s, "%DetailName") == "激突の記録" and _text(s, "%Date") != "未取得"
			and _sounds == [&"ui_move"], "マウスを乗せた印（激突の記録）の説明を出し、フォーカスも移る（%s %s）" % [_text(s, "%DetailName"), _sounds])
	await _hover(_cell(s, 15))
	_expect(s.shown == 15 and _text(s, "%DetailName") == "千個破壊" and _text(s, "%Date") == "未取得", "別の印に乗せると説明が変わる")
	return true


# 修了証書: 全試験合格のときだけ押せ、開くと開いた時点でフォーカス、押すと certificate.tscn が重なって開く。
# 開いている間は下の画面にフォーカスが行かず、Esc はタイトルへ戻らない。closed で閉じて「修了証書」にフォーカスが戻る
func _check_certificate() -> bool:
	_game_state.erase_records()
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		_game_state.submit_clear(n, 1000 * n, 1)
	_game_state.submit_run({"stage": Tuning.STAGE_COUNT, "outcome": "clear", "smashed": {}, "girigiri": 0, "max_combo": 0,
			"max_speed": 0.0, "distance": 0.0, "chained": 0, "toggles": 1, "score": 1000})
	var today: String = Time.get_date_string_from_system()
	var s: Control = await _open(RECORDS_SCENE)
	if s == null:
		return true
	var cert: Button = s.get_node("%Cert")
	_expect(not cert.disabled and cert.has_focus() and _text(s, "%CertHint") == "修了日　" + today
			and (cert.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == Palette.HAZARD,
			"全試験に合格していれば「修了証書」は警告黄で押せ、開いた時点でフォーカス。横に修了日（%s）" % _text(s, "%CertHint"))
	_expect(s.stamp_lines(1) == PackedStringArray(["全課程", "修了"]), "全課程修了の印を取っている（%s）" % [s.stamp_lines(1)])
	_expect(_text(s, "%DetailName") == "基礎課程修了", "修了証書にフォーカスしていても説明欄は最初の印")
	# 格子と修了証書の間
	await _key(KEY_DOWN)
	_expect(s.get_node("%Back").has_focus(), "「修了証書」の ↓ は「戻る」")
	await _key(KEY_UP)
	_expect(cert.has_focus(), "「戻る」の ↑ は「修了証書」（押せるとき）")
	await _key(KEY_RIGHT)
	_expect(_focused_cell(s) == CORNER, "「修了証書」の → は左下の印（%d）" % _focused_cell(s))
	await _key(KEY_UP)
	await _key(KEY_LEFT)
	_expect(cert.has_focus(), "格子の左端の ← は「修了証書」（押せるとき）")
	_sounds.clear()
	await _key(KEY_ENTER)
	var overlay: Control = _overlay(s)
	_expect(overlay != null and overlay.scene_file_path == CERTIFICATE_SCENE and _sounds == [&"ui_select"],
			"「修了証書」を決定すると certificate.tscn がこの上に重なって開く（%s）" % [_sounds])
	if overlay == null:
		return true
	_expect(root.gui_get_focus_owner() == null or overlay.is_ancestor_of(root.gui_get_focus_owner()),
			"開いたとき、下の画面のボタンにフォーカスを残さない")
	# 矢印キーで確かめる（Enter は証書の「閉じる」を押して閉じるのが正しい動き。閉じるのは下の Esc で見る）
	for k: Key in [KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_UP]:
		await _key(k)
	var owner: Control = root.gui_get_focus_owner()
	_expect((owner == null or overlay.is_ancestor_of(owner)) and s.get_children().filter(_is_certificate).size() == 1,
			"修了証書を開いている間は、下の画面にフォーカスが行かず、もう1枚開かない")
	var closed: Array[int] = [0]
	overlay.closed.connect(func() -> void: closed[0] += 1)
	await _key(KEY_ESCAPE)
	await process_frame
	_expect(closed[0] == 1 and not is_instance_valid(overlay) and current_scene == s,
			"修了証書で Esc を押すと closed で閉じ、試験記録の画面に残る（タイトルへ戻らない）")
	_expect(cert.has_focus(), "閉じると「修了証書」にフォーカスが戻る")
	await _click(cert)
	overlay = _overlay(s)
	_expect(overlay != null, "「修了証書」はクリックでも開く")
	if overlay != null:
		overlay.closed.emit()
		await process_frame
		_expect(not is_instance_valid(overlay) and cert.has_focus(), "closed を出すと閉じてフォーカスが戻る")
	await _key(KEY_ESCAPE)
	_expect(await _wait_scene(TITLE_SCENE), "閉じた後の Esc はタイトルへ")
	return true


# 画面の文字はすべてその書体にある（判子の名前・「？」・ヘッダー・表・説明欄）
func _check_glyphs() -> bool:
	_game_state.erase_records()
	var s: Control = await _open(RECORDS_SCENE)
	if s == null:
		return true
	var missing: Array[String] = []
	for a: Array in Achievements.LIST:
		_missing(Fonts.BIZ_BOLD, a[1], missing)  # 判子の中
		_missing(Fonts.DELA, a[1], missing)  # 説明欄の名前
		_missing(Fonts.BIZ, Achievements.describe(a[0]), missing)
	_missing(Fonts.DELA, "？", missing)
	for l: Label in _labels(s):
		_missing(l.get_theme_font(&"font"), l.text, missing)
	_expect(missing.is_empty(), "試験記録の画面の文字はすべて書体にある（無い: %s）" % [missing])
	return true


# 検定印30個（replay-value-design.md 8章）が画面に収まる: 判子はマスに収まり、マスは説明欄・累計の表と重ならず、
# どの印の条件の文も説明欄の幅に1行で収まる
func _check_layout() -> bool:
	_game_state.erase_records()
	var s: Control = await _open(RECORDS_SCENE)
	if s == null:
		return true
	var screen := Rect2(Vector2.ZERO, Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height")))
	var detail: Rect2 = (s.get_node("Detail") as Control).get_global_rect()
	var stats: Rect2 = (s.get_node("Stats") as Control).get_global_rect()
	var bad: Array[String] = []
	var n: int = s.get_node("%Stamps").get_child_count()
	for i: int in n:
		var r: Rect2 = _cell(s, i).get_global_rect()
		if minf(r.size.x, r.size.y) < Tuning.RECORDS_STAMP_R * 2.0 or not screen.encloses(r) or r.intersects(detail) or r.intersects(stats):
			bad.append("%d %s" % [i, r])
	_expect(n == Achievements.LIST.size() and bad.is_empty(),
			"検定印 %d 個のマスは画面に収まり、判子が入り、説明欄・表と重ならない（悪い: %s）" % [n, bad])
	var condition: Label = s.get_node("%Condition")
	var room: float = (s.get_node("Detail/Info") as Control).size.x - condition.position.x
	var long: Array[String] = []
	for a: Array in Achievements.LIST:
		var w: float = condition.get_theme_font(&"font").get_string_size(Achievements.describe(a[0]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				condition.get_theme_font_size(&"font_size")).x
		if w > room:
			long.append("%s（%.0f > %.0f）" % [a[0], w, room])
	_expect(long.is_empty(), "どの印の条件の文も説明欄に収まる（はみ出す: %s）" % [long])
	return true


# --- 補助 ---

func _missing(font: Font, text: String, out: Array[String]) -> void:
	for c: String in text:
		if c != " " and c != "　" and not font.has_char(c.unicode_at(0)) and not out.has(c):
			out.append(c)


func _labels(n: Node) -> Array[Label]:
	var out: Array[Label] = []
	for c: Node in n.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_labels(c))
	return out


func _cell(s: Control, i: int) -> Control:
	return s.get_node("%Stamps").get_child(i)


## フォーカスのある印の添字（印でなければ -1）
func _focused_cell(s: Control) -> int:
	var owner: Control = root.gui_get_focus_owner()
	return owner.get_index() if owner != null and owner.get_parent() == s.get_node("%Stamps") else -1


func _is_certificate(n: Node) -> bool:
	return n.scene_file_path == CERTIFICATE_SCENE


## 試験記録の画面の上に重なっている修了証書
func _overlay(s: Node) -> Control:
	for c: Node in s.get_children():
		if _is_certificate(c):
			return c
	return null


func _text(from: Node, path: String) -> String:
	return (from.get_node(path) as Label).text


## 画面を開き、切り替わって並びが決まるまで待つ。開けなければ null
func _open(path: String) -> Control:
	change_scene_to_file(path)
	return await _current(path, "")


## 今の画面が path になるのを待つ（label が空でなければ OK/NG を出す）。並びが決まってから返す。なれなければ null
func _current(path: String, label: String) -> Control:
	var ok: bool = await _wait_scene(path)
	if label != "":
		_expect(ok, label)
	elif not ok:
		_expect(false, "%s が開かない" % path)
	if not ok:
		return null
	await process_frame  # コンテナの並べ替えは次のフレーム
	return current_scene


## current_scene が path になるまで数フレーム待つ（change_scene_to_file は次のフレームで切り替わる）
func _wait_scene(path: String) -> bool:
	for _i: int in SCENE_WAIT_FRAMES:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path:
			return true
	return false


## キーを押して離し、1フレーム進める
func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)
	await process_frame


## c の中央を左クリックして、1フレーム進める（座標は画面の座標）
func _click(c: Control) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = c.get_global_rect().get_center()
		ev.global_position = ev.position
		root.push_input(ev, true)
	await process_frame


## マウスを c の中央へ動かして、1フレーム進める
func _hover(c: Control) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = c.get_global_rect().get_center()
	ev.global_position = ev.position
	root.push_input(ev, true)
	await process_frame


func _remove_test_files() -> void:
	for path: String in [TEST_SETTINGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
