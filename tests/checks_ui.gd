extends SceneTree
## タイトル・設定画面の自動確認（17.2, 17.6, FR-40, FR-47a〜d, FR-50a, 10章, AC-20・AC-21 の設定画面の部分）。
## 書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_ui.gd （失敗があれば終了コード1）
## 遊んでいる人の設定・記録を上書きしないよう、GameState の保存先を確認用のファイルに差し替え、最後に消す。
## キーは root に InputEventKey を送り、フォーカス移動・ボタンの決定・Esc を実際の経路で通す。
## 壊れた settings.cfg を読む確認で、ConfigFile の parse error（ERROR）が1件出る。

const TITLE_SCENE: String = "res://scenes/title.tscn"
const SETTINGS_SCENE: String = "res://scenes/settings.tscn"
const TEST_SETTINGS: String = "user://checks_ui_settings.cfg"
const TEST_SAVE: String = "user://checks_ui_save.cfg"

var _failed: int = 0
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前（GameState など）では参照できない。
# 同じ理由で、autoload を使うスクリプト（ui_button.gd など）の型名や preload もここでは使わない
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
	_game_state.load_settings()  # 確認用のファイルが無い = 初期値から始める
	_audio.played.connect(func(key: StringName) -> void: _sounds.append(key))
	var checks: Array[Callable] = [_check_title, _check_settings_values, _check_erase, _check_fallback]
	for check: Callable in checks:
		# 各確認は最後に true を返す。スクリプトエラーで止まると null が返る
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
	_remove_test_files()
	_game_state.settings_path = real_settings
	_game_state.save_path = real_save
	_game_state.load_settings()
	# 鳴っている効果音を止め、片付ける音声スレッドが回るまで少しだけ実時間で待つ（checks.gd と同じ。
	# 再生中のまま終えると、終了時に「resources still in use」が出る）
	for p: Node in _audio.get_children():
		(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	for _i: int in 2:
		await process_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# FR-40, FR-47a, FR-47d: タイトルは「試験開始」にフォーカスして開く。↓↓ で「設定」（間に「試験記録」、設計書
# docs/superpowers/specs/2026-09-26-records-design.md の 3.1）、Enter で設定が重なって開き「戻る」にフォーカス。
# 開いている間はタイトルのボタンにフォーカスが行かない。Esc か「戻る」で閉じると「設定」に戻る
func _check_title() -> bool:
	var title: Control = await _add(TITLE_SCENE)
	var start: Button = title.get_node("Menu/Start")
	var records_button: Button = title.get_node("Menu/Records")
	var settings_button: Button = title.get_node("Menu/Row/Settings")
	var quit_button: Button = title.get_node("Menu/Row/Quit")
	_expect(start.has_focus() and _sounds.is_empty(), "FR-47a タイトルを開くと「試験開始」にフォーカス（音は鳴らさない）")
	_expect([start.text, records_button.text, settings_button.text, quit_button.text] == ["試験開始", "試験記録", "設定", "終了"]
			and quit_button.visible, "FR-40 「試験開始」「試験記録」「設定」「終了」が並ぶ（Web版でなければ「終了」を出す）")
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	_expect(settings_button.has_focus() and _sounds == [&"ui_move", &"ui_move"],
			"FR-47a ↓↓ で「試験記録」を通って「設定」へ移り、そのたびに ui_move を鳴らす（%s）" % [_sounds])
	if not settings_button.has_focus():
		title.free()  # このまま Enter を押すと「試験開始」でゲーム画面へ行ってしまう
		return true
	_sounds.clear()
	await _key(KEY_ENTER)
	var overlay: Control = _overlay(title)
	_expect(overlay != null and overlay.get_node("%Back").has_focus(), "FR-47a 「設定」を決定すると設定が開き「戻る」にフォーカス")
	_expect(_sounds == [&"ui_select"], "FR-47a 決定で ui_select を鳴らす（開いた画面のフォーカスでは鳴らさない）（%s）" % [_sounds])
	if overlay == null:
		title.free()
		return true
	for k: Key in [KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		await _key(k)
	_expect(overlay.is_ancestor_of(root.gui_get_focus_owner()), "設定を開いている間は、下に隠れたタイトルのボタンへフォーカスが行かない")
	var closed: Array[int] = [0]
	overlay.closed.connect(func() -> void: closed[0] += 1)
	await _key(KEY_ESCAPE)
	await process_frame
	_expect(closed[0] == 1 and not is_instance_valid(overlay), "FR-47d 設定で Esc を押すと closed を出して閉じる")
	_expect(settings_button.has_focus(), "FR-47d 閉じるとタイトルの「設定」にフォーカスが戻る")
	await _key(KEY_ENTER)
	overlay = _overlay(title)
	var reopened: bool = overlay != null and overlay.get_node("%Back").has_focus()
	await _key(KEY_ENTER)  # フォーカスは「戻る」
	_expect(reopened and not is_instance_valid(overlay) and settings_button.has_focus(),
			"FR-47d 「戻る」を決定しても閉じて、タイトルの「設定」に戻る")
	title.free()
	return true


# FR-47b, FR-50a, AC-20: 音量は ← → で10ずつ変わり、変えた瞬間に GameState とファイルに入り、読み直しても残る。
# 揺れ OFF も同じ。開き直すと保存した値で開く
func _check_settings_values() -> bool:
	var s: Control = await _add(SETTINGS_SCENE)
	var volume: HSlider = s.get_node("%Volume")
	var value_label: Label = s.get_node("%VolumeValue")
	_expect(volume.value == Tuning.SE_VOLUME_DEFAULT and value_label.text == str(Tuning.SE_VOLUME_DEFAULT),
			"FR-47b 設定ファイルが無ければ音量 %d で開く" % Tuning.SE_VOLUME_DEFAULT)
	volume.grab_focus()
	await _key(KEY_LEFT)
	await _key(KEY_LEFT)
	var want: int = Tuning.SE_VOLUME_DEFAULT - Tuning.SE_VOLUME_STEP * 2
	_expect(_game_state.se_volume == want and value_label.text == str(want), "FR-47b ← 2回で音量が %d になり、表示も変わる（%d）" % [want, _game_state.se_volume])
	_expect(_saved("se_volume") == want, "FR-47b 音量は変えた瞬間に settings.cfg に保存する")
	_game_state.load_settings()
	_expect(_game_state.se_volume == want, "FR-50a 読み直しても音量 %d" % want)
	for _i: int in 20:
		await _key(KEY_RIGHT)
	_expect(_game_state.se_volume == Tuning.SE_VOLUME_MAX, "FR-47b 音量は %d で止まる（%d）" % [Tuning.SE_VOLUME_MAX, _game_state.se_volume])
	while _game_state.se_volume > want:
		await _key(KEY_LEFT)
	var on: Button = s.get_node("%ShakeOn")
	var off: Button = s.get_node("%ShakeOff")
	await _key(KEY_DOWN)
	_expect(on.has_focus() or off.has_focus(), "FR-47a 音量から ↓ で「画面の揺れ」へ移る")
	on.grab_focus()
	await _key(KEY_RIGHT)
	_expect(off.has_focus(), "FR-47a ON から → で OFF へ移る")
	await _key(KEY_SPACE)
	_expect(not _game_state.screen_shake and _saved("screen_shake") == false, "FR-47b 揺れ OFF はすぐ保存する")
	_expect((off.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == Palette.INK, "選んだ OFF が墨地になる")
	_game_state.load_settings()
	_expect(not _game_state.screen_shake, "FR-50a 読み直しても揺れ OFF")
	s.free()
	s = await _add(SETTINGS_SCENE)
	var off_again: Button = s.get_node("%ShakeOff")
	_expect((s.get_node("%Volume") as HSlider).value == want and (off_again.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == Palette.INK,
			"AC-20 開き直すと音量 %d・揺れ OFF で開く" % want)
	s.free()
	return true


# FR-47c, 10章, AC-21: 「記録を消去する…」だけでは消えず、同じ場所に確認欄が出て「やめる」にフォーカス。
# Esc と「やめる」は確認欄を閉じるだけ。「消去する」で save.cfg が初期状態になり、設定は残る
func _check_erase() -> bool:
	var rec := ConfigFile.new()
	rec.set_value("stage_01", "cleared", true)
	rec.set_value("stage_01", "best_score", 1234)
	rec.save(TEST_SAVE)
	var before: String = FileAccess.get_file_as_string(TEST_SAVE)
	var volume: int = _game_state.se_volume
	var s: Control = await _add(SETTINGS_SCENE)
	var closed: Array[int] = [0]
	s.closed.connect(func() -> void: closed[0] += 1)
	var erase: Button = s.get_node("%Erase")
	var confirm: Control = s.get_node("%Confirm")
	erase.grab_focus()
	await _key(KEY_ENTER)
	_expect(FileAccess.get_file_as_string(TEST_SAVE) == before, "AC-21 「記録を消去する…」を押しただけでは記録は消えない")
	_expect(confirm.visible and not erase.visible and s.get_node("%Cancel").has_focus(),
			"FR-47c 同じ位置に確認欄が出て、フォーカスは「やめる」")
	_expect((s.get_node("%ConfirmText") as Label).text == "全ステージの記録と★を消去します。元に戻せません。", "FR-47c 確認欄の文")
	await _key(KEY_ESCAPE)
	_expect(not confirm.visible and erase.visible and erase.has_focus() and closed[0] == 0,
			"10章 確認中の Esc は確認欄を閉じるだけ（設定画面は閉じない）")
	_expect(FileAccess.get_file_as_string(TEST_SAVE) == before, "10章 確認中の Esc では消去しない")
	await _key(KEY_ENTER)  # もう一度開く
	await _key(KEY_ENTER)  # 「やめる」
	_expect(not confirm.visible and erase.has_focus() and FileAccess.get_file_as_string(TEST_SAVE) == before,
			"FR-47c 「やめる」は確認欄を閉じるだけで消去しない")
	await _key(KEY_ENTER)
	await _key(KEY_RIGHT)
	_expect(s.get_node("%EraseYes").has_focus(), "FR-47a 確認欄で → を押すと「消去する」へ移る")
	await _key(KEY_ENTER)
	var after := ConfigFile.new()
	_expect(after.load(TEST_SAVE) == OK and after.get_sections().is_empty(), "FR-47c 「消去する」で save.cfg が初期状態になる")
	_expect(not confirm.visible and erase.has_focus(), "「消去する」の後は確認欄を閉じる")
	_expect(_saved("se_volume") == volume and _saved("screen_shake") == false, "FR-47c 設定値（音量・揺れ）は消さない")
	await _key(KEY_ESCAPE)
	_expect(closed[0] == 1, "10章 もう一度 Esc で設定画面を閉じる")
	s.free()
	return true


# FR-50a, 10章: settings.cfg が壊れている・値が範囲外・型が違う場合は初期値（音量80、揺れON）
func _check_fallback() -> bool:
	var f: FileAccess = FileAccess.open(TEST_SETTINGS, FileAccess.WRITE)
	f.store_string("これは設定ファイルではない [[[\nse_volume = = 40\n")
	f.close()
	_game_state.se_volume = 30
	_game_state.screen_shake = false
	_game_state.load_settings()
	_expect(_game_state.se_volume == Tuning.SE_VOLUME_DEFAULT and _game_state.screen_shake,
			"10章 壊れた settings.cfg は初期値（%d, %s）" % [_game_state.se_volume, _game_state.screen_shake])
	var s: Control = await _add(SETTINGS_SCENE)
	_expect((s.get_node("%Volume") as HSlider).value == Tuning.SE_VOLUME_DEFAULT
			and (s.get_node("%ShakeOn").get_theme_stylebox("normal") as StyleBoxFlat).bg_color == Palette.INK,
			"10章 壊れた settings.cfg の後の設定画面は音量 %d・揺れ ON で開く" % Tuning.SE_VOLUME_DEFAULT)
	s.free()
	for bad: Array in [[Tuning.SE_VOLUME_MAX + 1, "yes"], [-1, 1], ["40", 0.5]]:
		var cfg := ConfigFile.new()
		cfg.set_value(_game_state.SECTION, "se_volume", bad[0])
		cfg.set_value(_game_state.SECTION, "screen_shake", bad[1])
		cfg.save(TEST_SETTINGS)
		_game_state.se_volume = 30
		_game_state.screen_shake = false
		_game_state.load_settings()
		_expect(_game_state.se_volume == Tuning.SE_VOLUME_DEFAULT and _game_state.screen_shake,
				"FR-50a 範囲外・型違い（音量 %s、揺れ %s）は初期値（%d, %s）" % [bad[0], bad[1], _game_state.se_volume, _game_state.screen_shake])
	return true


# --- 補助 ---

## 画面を開く。コンテナの並べ替えは次のフレームなので、1フレーム待ってから返す（位置が決まらないとフォーカス移動先が探せない）
func _add(path: String) -> Control:
	var node: Control = (load(path) as PackedScene).instantiate()
	root.add_child(node)
	await process_frame
	return node


## タイトルの上に重なっている設定画面
func _overlay(title: Node) -> Control:
	for c: Node in title.get_children():
		if c.has_signal("closed"):
			return c
	return null


## キーを押して離し、1フレーム進める（確認欄の表示などで並びが変わるのは次のフレーム）
func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)
	await process_frame


## 確認用の settings.cfg に保存されている値（読めなければ null）
func _saved(key: String) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(TEST_SETTINGS) != OK:
		return null
	return cfg.get_value(_game_state.SECTION, key, null)


func _remove_test_files() -> void:
	for path: String in [TEST_SETTINGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
