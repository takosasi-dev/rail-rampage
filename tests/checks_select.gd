extends SceneTree
## ステージ選択と記録の自動確認（17.3、FR-41, FR-41a, FR-47a, FR-48〜50、10章、AC-12・AC-21 の自動確認できる部分）と、
## 10ステージを5枚ずつのページに分けた見せ方（docs/superpowers/specs/2026-09-26-more-stages-design.md）。
## 書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_select.gd （失敗があれば終了コード1）
## 遊んでいる人の設定・記録を上書きしないよう、GameState の保存先を確認用のファイルに差し替え、最後に消す。
## 画面は change_scene_to_file で開き、キーとクリックは root に送って実際の経路で通す。
## 壊れた save.cfg を読む確認で、ConfigFile の parse error（ERROR）が1件出る。ステージ JSON が無いうちは
## 「ステージファイルがありません」も出る。

const SELECT_SCENE: String = "res://scenes/stage_select.tscn"
const TITLE_SCENE: String = "res://scenes/title.tscn"
const GAME_SCENE: String = "res://scenes/game.tscn"
const TEST_SETTINGS: String = "user://checks_select_settings.cfg"
const TEST_SAVE: String = "user://checks_select_save.cfg"
const SCENE_WAIT_FRAMES: int = 10  # 画面の切り替えを待つ上限

var _failed: int = 0
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前（GameState など）では参照できない。
# 同じ理由で、autoload を使うスクリプト（stage_select.gd など）の型名や preload もここでは使わない
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
	var checks: Array[Callable] = [_check_records, _check_fresh_screen, _check_navigation, _check_pages, _check_ex_page, _check_back,
			_check_start, _check_erase, _check_title]
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


# FR-41, FR-48〜50, AC-12: 記録（GameState）
func _check_records() -> bool:
	var gs: Node = _game_state
	_expect(gs.is_unlocked(1) and not gs.is_unlocked(2) and not gs.is_unlocked(5) and gs.total_stars() == 0,
			"FR-41 記録が無ければステージ1だけ解放")
	var first: bool = gs.submit_clear(1, 1500, 2)
	_expect(first and gs.is_unlocked(2) and not gs.is_unlocked(3), "FR-41 ステージ1のクリアでステージ2が解放される")
	gs.load_records()
	var r: Dictionary = gs.record(1)
	_expect(gs.is_unlocked(2) and r["cleared"] and r["best_score"] == 1500 and r["stars"] == 2,
			"AC-12 読み直してもステージ2の解放とベストスコアが残る（%s）" % [r])
	var updated: bool = gs.submit_clear(1, 1000, 1)
	r = gs.record(1)
	_expect(not updated and r["best_score"] == 1500 and r["stars"] == 2, "FR-49 低い得点・少ない★では下がらない（%s）" % [r])
	gs.submit_clear(1, 1200, 3)
	r = gs.record(1)
	_expect(r["best_score"] == 1500 and r["stars"] == 3, "FR-49 ★だけ上がり、得点は下がらない（%s）" % [r])
	updated = gs.submit_clear(1, 2000, 1)
	gs.load_records()
	r = gs.record(1)
	_expect(updated and r["best_score"] == 2000 and r["stars"] == 3, "FR-49 得点だけ上がり、★は下がらない（%s）" % [r])
	var f: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string("これはセーブではない [[[\nstage_01 = = true\n")
	f.close()
	gs.load_records()
	_expect(gs.is_unlocked(1) and not gs.is_unlocked(2) and gs.record(1) == {"cleared": false, "best_score": 0, "stars": 0, "gold": false},
			"FR-50, AC-12 壊れた save.cfg はクラッシュせず初期状態")
	var cfg := ConfigFile.new()
	cfg.set_value("stage_01", "cleared", true)
	cfg.set_value("stage_01", "best_score", 900)
	cfg.set_value("stage_01", "stars", Tuning.STARS_MAX + 1)
	cfg.save(TEST_SAVE)
	gs.load_records()
	_expect(not gs.is_unlocked(2), "FR-50 範囲外の★のステージは初期状態")
	gs.erase_records()
	return true


# FR-41, FR-47a, AC-21: 記録が無い状態の画面。ステージ1だけ解放、未解放は「？？？」で選べない
func _check_fresh_screen() -> bool:
	_game_state.erase_records()
	_game_state.current_stage = 1
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	_expect(s.selected == 1 and s.get_node("%Start").has_focus() and _sounds.is_empty(),
			"FR-47a 開くと第1試験を選び、「試験開始」にフォーカス（音は鳴らさない）")
	_expect_blank(s, "AC-21 記録が無ければ")
	var locked_ok: bool = true
	for n: int in range(2, Tuning.STAGE_COUNT + 1):
		var body: Node = _card(s, n).get_node("Body")
		locked_ok = locked_ok and _text(body, "Name") == "？？？" and body.get_node("Locked").visible \
				and not body.get_node("Stars").visible and _text(body, "LockHint") == "第%d試験の合格で解放" % (n - 1)
	_expect(locked_ok, "FR-41 未解放カードは「？？？」「未解放」「第N試験の合格で解放」")
	_expect(s.get_node("Cards").get_child_count() == Tuning.STAGE_COUNT + Tuning.EX_COUNT and Tuning.STAGE_COUNT == 10,
			"カードは本試験と裏試験の %d 枚（Tuning.STAGE_COUNT = %d）" % [s.get_node("Cards").get_child_count(), Tuning.STAGE_COUNT])
	_expect(Tuning.SELECT_STAMP_DEG.size() == Tuning.STAGE_COUNT, "「済」の判子の傾きはステージ %d 個分（%d）" % [
			Tuning.STAGE_COUNT, Tuning.SELECT_STAMP_DEG.size()])
	_expect(_shown(s) == [1, 2, 3, 4, 5] and _text(_tab(s, 1), "Text") == "基礎課程 1〜5" and _text(_tab(s, 2), "Text") == "応用課程 6〜10",
			"見えているのは第1〜5試験のページ（%s）。タブは「%s」「%s」" % [_shown(s), _text(_tab(s, 1), "Text"), _text(_tab(s, 2), "Text")])
	var missing: Array[String] = []
	for p: int in [1, 2, 3]:
		var label: Label = _tab(s, p).get_node("Text")
		for c: String in label.text:
			if not label.get_theme_font(&"font").has_char(c.unicode_at(0)):
				missing.append(c)
	_expect(missing.is_empty(), "タブの文字はすべてタブのフォントにある（無い: %s）" % [missing])
	await _click(_tab(s, 2))
	_expect(s.selected == 1 and _shown(s) == [1, 2, 3, 4, 5] and _sounds.is_empty(), "第6試験が未解放なら「応用課程」のタブを押しても変わらない")
	await _key(KEY_RIGHT)
	_expect(s.selected == 1 and _sounds.is_empty(), "FR-41 → を押しても未解放には移らない（音も鳴らさない）")
	await _click(_card(s, 2))
	_expect(s.selected == 1 and current_scene == s, "FR-41 未解放カードはクリックしても選べない")
	return true


# FR-41, FR-41a, FR-47a: ←→ で選び（未解放は飛ばす）、詳細パネルが変わる。↑↓ はボタンの間のフォーカス移動
func _check_navigation() -> bool:
	_game_state.erase_records()
	_game_state.submit_clear(1, 1850, 2)
	_game_state.submit_clear(2, 4120, 3)
	_game_state.current_stage = 2
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var start: Button = s.get_node("%Start")
	var back: Button = s.get_node("%Back")
	_expect(s.selected == 2 and _text(s, "%DetailNum") == "第2試験" and _text(s, "%BestValue") == "4,120",
			"開くと前に遊んだ第2試験を選ぶ（詳細パネル %s %s）" % [_text(s, "%DetailNum"), _text(s, "%BestValue")])
	_expect(_text(s, "%Total") == "5 / 30", "17.3 ヘッダーの★合計（%s）" % _text(s, "%Total"))
	var body: Node = _card(s, 1).get_node("Body")
	_expect(_text(body, "Stars/Got") == "★★" and _text(body, "Stars/Rest") == "★" and _text(body, "Best") == "最高 1,850",
			"FR-41 カードに★と最高スコア（%s%s %s）" % [_text(body, "Stars/Got"), _text(body, "Stars/Rest"), _text(body, "Best")])
	_expect(_text(_card(s, 3).get_node("Body"), "Name") != "？？？", "FR-41 ステージ2のクリアでステージ3が解放されている")
	_sounds.clear()
	await _key(KEY_RIGHT)
	_expect(s.selected == 3 and _sounds == [&"ui_move"] and start.has_focus(),
			"FR-47a → で第3試験を選び ui_move を鳴らす。フォーカスは「試験開始」のまま（%s）" % [_sounds])
	var data: Dictionary = _stage_json(3)
	var thresholds: Variant = data.get("star_thresholds")
	var want_star2: String = Display.score_text(int(thresholds[0])) if thresholds is Array else "―"
	_expect(_text(s, "%DetailNum") == "第3試験" and _text(s, "%DetailName") == str(data.get("name", "データなし"))
			and _text(s, "%Element") == "レンガ壁" and _text(s, "%Explain") == "必要速度に届いていれば突破、届かなければ激突。"
			and _text(s, "%BestValue") == "記録なし" and _text(s, "%Star2Value") == want_star2,
			"FR-41a 詳細パネルが第3試験に変わる（%s %s ★2 %s）" % [_text(s, "%DetailName"), _text(s, "%Element"), _text(s, "%Star2Value")])
	_sounds.clear()
	await _key(KEY_RIGHT)
	_expect(s.selected == 3 and _sounds.is_empty(), "FR-41 → の先が全部未解放なら動かない")
	await _key(KEY_LEFT)
	await _key(KEY_LEFT)
	await _key(KEY_LEFT)
	_expect(s.selected == 1, "← で第1試験まで戻り、それより左へは行かない")
	await _key(KEY_DOWN)
	_expect(back.has_focus(), "FR-47a ↓ で「戻る」へ")
	await _key(KEY_RIGHT)
	_expect(s.selected == 2 and back.has_focus(), "「戻る」にフォーカスがあっても → はカードを選ぶ（フォーカスは動かさない）")
	await _key(KEY_UP)
	_expect(start.has_focus(), "FR-47a ↑ で「試験開始」へ戻る")
	_sounds.clear()
	await _click(_card(s, 3))
	_expect(s.selected == 3 and _sounds == [&"ui_move"] and start.has_focus() and _text(s, "%DetailNum") == "第3試験",
			"クリックでカードを選び、「試験開始」にフォーカス（%s）" % [_sounds])
	_game_state.current_stage = 5
	s = await _open(SELECT_SCENE)
	_expect(s != null and s.selected == 1, "前に遊んだステージが未解放なら第1試験を選んで開く")
	return true


# 10ステージは5枚ずつのページ（基礎課程 1〜5／応用課程 6〜10）。←→ でページをまたぎ、タブのクリックでもページを変える。
# カードの見た目と位置はページが変わっても同じ。第6〜10試験の詳細パネルは「新要素」でなく「応用」
func _check_pages() -> bool:
	_game_state.erase_records()
	for n: int in range(1, 8):
		_game_state.submit_clear(n, 1000 * n, 1)  # 第8試験まで解放
	_game_state.current_stage = 5
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var start: Button = s.get_node("%Start")
	var first: Rect2 = _card(s, 1).get_global_rect()
	_expect(s.selected == 5 and _shown(s) == [1, 2, 3, 4, 5] and _text(s, "%ElementLabel") == "新要素" and _text(s, "%Total") == "7 / 30",
			"第5試験を選んで開くと第1〜5試験のページ（%s、%s、%s）" % [_shown(s), _text(s, "%ElementLabel"), _text(s, "%Total")])
	var head_end: float = (s.get_node("%Sub") as Control).get_global_rect().end.x
	var total_start: float = (s.get_node("%TotalStar") as Control).get_global_rect().position.x
	var tabs: Rect2 = _tab(s, 1).get_global_rect().merge(_tab(s, 2).get_global_rect())
	_expect(tabs.position.x > head_end and tabs.end.x < total_start and s.get_node("Header").get_global_rect().encloses(tabs),
			"タブはヘッダーの中の、見出しと★合計の間（%s、見出しの右端 %.0f、★の左端 %.0f）" % [tabs, head_end, total_start])
	_sounds.clear()
	await _key(KEY_RIGHT)
	await process_frame  # コンテナの並べ替えは次のフレーム
	_expect(s.selected == 6 and _shown(s) == [6, 7, 8, 9, 10] and _sounds == [&"ui_move"] and start.has_focus(),
			"→ で第5試験から第6試験に移るとページが変わる（%s、%s）。フォーカスは「試験開始」のまま" % [_shown(s), _sounds])
	_expect(_card(s, 6).get_global_rect() == first, "ページが変わってもカードの位置と大きさは同じ（%s）" % _card(s, 6).get_global_rect())
	_expect(_text(s, "%DetailNum") == "第6試験" and _text(s, "%DetailName") == str(_stage_json(6).get("name", "データなし"))
			and _text(s, "%ElementLabel") == "応用" and _text(s, "%Element") == "ドラム缶と壁"
			and _text(s, "%Explain") == "爆発に巻き込まれた壁は、速度が足りなくても崩れる。",
			"第6試験の詳細パネル（%s %s %s %s）" % [_text(s, "%DetailName"), _text(s, "%ElementLabel"), _text(s, "%Element"), _text(s, "%Explain")])
	var body6: Node = _card(s, 6).get_node("Body")
	_expect(_text(body6, "Num").begins_with("第6試験・") and _text(body6, "Best") == "最高 6,000"
			and _text(_card(s, 9).get_node("Body"), "Name") == "？？？" and _text(_card(s, 9).get_node("Body"), "LockHint") == "第8試験の合格で解放",
			"第6試験のカードに記録、第9試験は未解放（%s %s）" % [_text(body6, "Num"), _text(body6, "Best")])
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	_sounds.clear()
	await _key(KEY_RIGHT)
	_expect(s.selected == 8 and _sounds.is_empty(), "第8試験から → の先は未解放なので動かない")
	for _i: int in 3:
		await _key(KEY_LEFT)
	await process_frame
	_expect(s.selected == 5 and _shown(s) == [1, 2, 3, 4, 5] and _text(s, "%ElementLabel") == "新要素",
			"← で第5試験に戻ると第1〜5試験のページ（%s）" % [_shown(s)])
	await _key(KEY_DOWN)
	_sounds.clear()
	await _click(_tab(s, 2))
	await process_frame
	_expect(s.selected == 6 and _shown(s) == [6, 7, 8, 9, 10] and _sounds == [&"ui_move"] and start.has_focus(),
			"「応用課程」のタブのクリックで第6試験を選び、「試験開始」にフォーカス（%s、%s）" % [_shown(s), _sounds])
	_sounds.clear()
	await _click(_tab(s, 2))
	_expect(s.selected == 6 and _sounds.is_empty(), "今のページのタブを押しても変わらない")
	await _click(_tab(s, 1))
	await process_frame
	_expect(s.selected == 1 and _shown(s) == [1, 2, 3, 4, 5], "「基礎課程」のタブのクリックで第1試験を選ぶ")
	_game_state.current_stage = 7
	s = await _open(SELECT_SCENE)
	_expect(s != null and s.selected == 7 and _shown(s) == [6, 7, 8, 9, 10], "前に遊んだ第7試験を選んで、第6〜10試験のページで開く")
	_game_state.erase_records()
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		_game_state.submit_clear(n, 1000, Tuning.STARS_MAX)
	s = await _open(SELECT_SCENE)
	_expect(s != null and _text(s, "%Total") == "30 / 30", "全部 ★3 なら ★ 30 / 30（%s）" % (_text(s, "%Total") if s != null else ""))
	return true


# 裏課程（replay-value-design.md 4章）: 3つ目のタブ。本試験の★の合計が ex_unlock_stars(11) に届くまでは錠前と「★10で解放」で
# 押せない。届けばタブのクリックと ←→ で裏試験を選べる。裏試験のカードは解放に要る★を出す
func _check_ex_page() -> bool:
	var gs: Node = _game_state
	gs.erase_records()
	for n: int in range(1, 4):
		gs.submit_clear(n, 1000, Tuning.STARS_MAX)  # ★9
	gs.current_stage = 1
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var tab: Control = _tab(s, 3)
	var need: int = gs.ex_unlock_stars(Tuning.EX_FIRST)
	var lock: Control = tab.get_node_or_null("Lock")
	_expect(_text(tab, "Text") == "★%dで解放" % need and lock != null and lock.visible and lock.size.x > 0.0,
			"★9 では裏課程のタブは錠前と「★%dで解放」（%s）" % [need, _text(tab, "Text")])
	var tabs: Rect2 = _tab(s, 1).get_global_rect().merge(tab.get_global_rect())
	var head_end: float = (s.get_node("%Sub") as Control).get_global_rect().end.x
	var total_start: float = (s.get_node("%TotalStar") as Control).get_global_rect().position.x
	_expect(tabs.position.x > head_end and tabs.end.x < total_start, "3つのタブは見出しと★合計の間（%s、%.0f〜%.0f）" % [
			tabs, head_end, total_start])
	_sounds.clear()
	await _click(tab)
	_expect(s.selected == 1 and _sounds.is_empty(), "解放前の裏課程のタブは押せない")
	var hint: String = _text(_card(s, Tuning.EX_FIRST).get_node("Body"), "LockHint")
	_expect(hint == "★%dで解放" % need, "裏試験1 のカードは「★%dで解放」（%s）" % [need, hint])
	gs.submit_clear(4, 1000, 1)  # ★10
	s = await _open(SELECT_SCENE)
	tab = _tab(s, 3)
	_expect(_text(tab, "Text") == "裏課程 1〜5" and not (tab.get_node("Lock") as Control).visible,
			"★10 で裏課程のタブが開く（%s）" % _text(tab, "Text"))
	await _click(tab)
	await process_frame
	var ex_cards: Array[int] = []
	for i: int in Tuning.EX_COUNT:
		ex_cards.append(Tuning.EX_FIRST + i)
	_expect(s.selected == Tuning.EX_FIRST and _shown(s) == ex_cards and _text(s, "%DetailNum") == "裏試験1"
			and _text(_card(s, Tuning.EX_FIRST).get_node("Body"), "Num").begins_with("裏試験1・"),
			"タブのクリックで裏試験1 を選ぶ（%s、%s）" % [_shown(s), _text(s, "%DetailNum")])
	var body2: Node = _card(s, Tuning.EX_FIRST + 1).get_node("Body")
	_expect(_text(body2, "Name") == "？？？" and _text(body2, "LockHint") == "★%dで解放（今 %d）" % [gs.ex_unlock_stars(Tuning.EX_FIRST + 1), gs.total_stars()],
			"裏試験2 は未解放で「★%dで解放」と今のまとめた★（%s）" % [gs.ex_unlock_stars(Tuning.EX_FIRST + 1), _text(body2, "LockHint")])
	await _key(KEY_RIGHT)
	_expect(s.selected == Tuning.EX_FIRST, "裏試験1 から → の先は未解放なので動かない")
	await _key(KEY_LEFT)
	await process_frame
	_expect(s.selected == 5 and _shown(s) == [1, 2, 3, 4, 5], "← で未解放の第6〜10試験を飛ばして第5試験へ（%d）" % s.selected)
	gs.current_stage = Tuning.EX_FIRST
	s = await _open(SELECT_SCENE)
	_expect(s != null and s.selected == Tuning.EX_FIRST and _shown(s) == ex_cards, "前に遊んだ裏試験1 を選んで裏課程のページで開く")
	gs.erase_records()
	return true


# FR-47a: Esc と「戻る」でタイトルへ
func _check_back() -> bool:
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	_sounds.clear()
	await _key(KEY_ESCAPE)
	_expect(await _wait_scene(TITLE_SCENE) and _sounds == [&"ui_select"], "FR-47a Esc でタイトルへ戻る（%s）" % [_sounds])
	s = await _open(SELECT_SCENE)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_expect(await _wait_scene(TITLE_SCENE), "「戻る」を決定するとタイトルへ戻る")
	return true


# FR-41a: 「試験開始」で current_stage を決めてゲーム画面へ。選んでいるカードのクリックでも始まる
func _check_start() -> bool:
	_game_state.erase_records()
	_game_state.submit_clear(1, 1850, 2)
	_game_state.current_stage = 1
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	_expect(_game_state.current_stage == 2 and await _wait_scene(GAME_SCENE),
			"FR-41a → で第2試験を選び Enter で current_stage = 2 にしてゲーム画面へ（%d）" % _game_state.current_stage)
	s = await _open(SELECT_SCENE)  # current_stage = 2 なので第2試験を選んで開く
	await _click(_card(s, 1))
	_expect(s.selected == 1 and current_scene == s, "選んでいないカードのクリックは選ぶだけ")
	await _click(_card(s, 1))
	_expect(_game_state.current_stage == 1 and await _wait_scene(GAME_SCENE), "選んでいるカードをもう一度クリックすると始める")
	s = await _open(SELECT_SCENE)
	await _key(KEY_SPACE)
	_expect(_game_state.current_stage == 1 and await _wait_scene(GAME_SCENE), "FR-47a Space でも始める")
	return true


# AC-21, 10章: 記録を消去した後のステージ選択はステージ1のみ解放、★・最高記録は空
func _check_erase() -> bool:
	_game_state.erase_records()
	for n: int in range(1, 4):
		_game_state.submit_clear(n, 3000 + n, n)
	_game_state.current_stage = 3
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	_expect(_text(_card(s, 4).get_node("Body"), "Name") != "？？？" and _text(s, "%Total") == "6 / 30",
			"消去の前は第4試験まで解放、★ 6 / 30")
	_game_state.erase_records()
	s = await _open(SELECT_SCENE)
	_expect(s.selected == 1, "AC-21 消去の後は第1試験を選んで開く")
	_expect_blank(s, "AC-21 消去の後は")
	return true


# タイトルの「試験開始」はステージ選択へ
func _check_title() -> bool:
	var t: Control = await _open(TITLE_SCENE)
	if t == null:
		return true
	_expect(t.get_node("Menu/Start").has_focus(), "タイトルは「試験開始」にフォーカス")
	await _key(KEY_ENTER)
	_expect(await _wait_scene(SELECT_SCENE), "タイトルの「試験開始」でステージ選択へ")
	return true


# --- 補助 ---

## 記録が空の画面: ステージ1だけ解放、★は全部空、最高スコアは「記録なし」、ヘッダーは 0 / 30
func _expect_blank(s: Control, label: String) -> void:
	var body: Node = _card(s, 1).get_node("Body")
	var locked: int = 0
	for n: int in range(2, Tuning.STAGE_COUNT + 1):
		if _text(_card(s, n).get_node("Body"), "Name") == "？？？":
			locked += 1
	_expect(_text(body, "Name") != "？？？" and locked == Tuning.STAGE_COUNT - 1, "%s ステージ1だけ解放" % label)
	_expect(_text(body, "Stars/Got") == "" and _text(body, "Stars/Rest") == "★★★" and _text(body, "Best") == "記録なし"
			and _text(s, "%BestValue") == "記録なし" and _text(s, "%Total") == "0 / 30",
			"%s ★・最高記録は空（%s / %s / %s）" % [label, _text(body, "Stars/Rest"), _text(body, "Best"), _text(s, "%Total")])


## 画面を開き、切り替わって並びが決まるまで待つ。開けなければ null
func _open(path: String) -> Control:
	change_scene_to_file(path)
	if not await _wait_scene(path):
		_expect(false, "%s が開かない" % path)
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


func _card(s: Control, n: int) -> Control:
	return s.get_node("Cards").get_child(n - 1)


## ページのタブ（p = 1 から）
func _tab(s: Control, p: int) -> Control:
	return s.get_node("Header/Pages").get_child(p - 1)


## 見えているカードの試験番号
func _shown(s: Control) -> Array[int]:
	var out: Array[int] = []
	for n: int in range(1, s.get_node("Cards").get_child_count() + 1):
		if _card(s, n).visible:
			out.append(n)
	return out


func _text(from: Node, path: String) -> String:
	return (from.get_node(path) as Label).text


func _stage_json(n: int) -> Dictionary:
	var path: String = "res://data/stages/stage_%02d.json" % n
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


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


func _remove_test_files() -> void:
	for path: String in [TEST_SETTINGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
