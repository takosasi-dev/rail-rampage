extends SceneTree
## 画面遷移の自動確認（AC-22、FR-47a）。マウスを使わず、キーボードだけで
## タイトル → ステージ選択 → プレイ → ポーズ → 設定 → ポーズ → ステージ選択 → タイトル まで移動できる。
## 書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_flow.gd （失敗があれば終了コード1）
## キーは root に InputEventKey を送り、本物の入力の経路（フォーカス・ボタン・_unhandled_input）を通す。
## 遊んでいる人の設定・記録を上書きしないよう、GameState の保存先を確認用のファイルに差し替え、最後に消す。

const TITLE: String = "res://scenes/title.tscn"
const SELECT: String = "res://scenes/stage_select.tscn"
const GAME: String = "res://scenes/game.tscn"
const TEST_SETTINGS: String = "user://checks_flow_settings.cfg"
const TEST_SAVE: String = "user://checks_flow_save.cfg"
const MAX_FRAMES: int = 600

var _failed: int = 0
var _game_state: Node  # -s のスクリプトは autoload の名前では参照できない
var _audio: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_game_state = root.get_node("GameState")
	_audio = root.get_node("Audio")
	var real_settings: String = _game_state.settings_path
	var real_save: String = _game_state.save_path
	_game_state.settings_path = TEST_SETTINGS
	_game_state.save_path = TEST_SAVE
	_remove_test_files()
	_game_state.load_records()  # 記録なし = ステージ1だけ解放
	_game_state.current_stage = 1
	if await _walk() != true:
		_expect(false, "キーボードだけの画面遷移が途中で止まった")
	if await _walk_pages() != true:
		_expect(false, "キーボードだけで第10試験を始める確認が途中で止まった")
	paused = false
	if current_scene != null:
		current_scene.free()
	_remove_test_files()
	_game_state.settings_path = real_settings
	_game_state.save_path = real_save
	_game_state.load_settings()
	_game_state.load_records()
	# 鳴っている効果音を止め、片付ける音声スレッドが回るまで少しだけ実時間で待つ（checks.gd と同じ）
	for p: Node in _audio.get_children():
		(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	for _i: int in 2:
		await process_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


func _walk() -> bool:
	change_scene_to_file(TITLE)
	if not await _until_scene(TITLE, "起動するとタイトル"):
		return true
	await _key(KEY_ENTER)  # 「試験開始」（開いた時点でフォーカス、FR-47a）
	if not await _until_scene(SELECT, "タイトルの「試験開始」で Enter → ステージ選択"):
		return true
	await _key(KEY_ENTER)  # 「試験開始」（第1試験）
	if not await _until_scene(GAME, "ステージ選択で Enter → 第1試験が始まる"):
		return true
	var game: Node = current_scene
	game.auto_pause = false
	await _frames(10)
	_expect(game._trolley != null and game._trolley.total_distance > 0.0, "第1試験のトロッコが走る")
	await _key(KEY_ESCAPE)
	_expect(paused and game._pause != null, "プレイ中に Esc → ポーズ")
	if game._pause == null:
		return true
	var menu: Control = game._pause
	await _key(KEY_DOWN)  # 再開 → リトライ
	await _key(KEY_DOWN)  # → 設定
	_expect(menu.get_node("%Settings").has_focus(), "ポーズで ↓↓ → 「設定」")
	await _key(KEY_ENTER)
	_expect(menu.is_settings_open(), "「設定」で Enter → 設定が開く")
	await _key(KEY_ESCAPE)
	_expect(not menu.is_settings_open() and paused and menu.get_node("%Settings").has_focus(), "設定で Esc → ポーズに戻る")
	await _key(KEY_DOWN)  # → ステージ選択へ
	_expect(menu.get_node("%Select").has_focus(), "ポーズで ↓ → 「ステージ選択へ」")
	await _key(KEY_ENTER)
	if not await _until_scene(SELECT, "「ステージ選択へ」で Enter → ステージ選択"):
		return true
	_expect(not paused, "ステージ選択に戻るとポーズは解ける")
	await _key(KEY_ESCAPE)
	await _until_scene(TITLE, "ステージ選択で Esc → タイトル（AC-22 の最後）")
	return true


## FR-47a: 第9試験まで合格していれば、ステージ選択の → だけで5枚ずつのページをまたいで第10試験を選び、Enter で始められる
func _walk_pages() -> bool:
	paused = false
	for n: int in range(1, Tuning.STAGE_COUNT):
		_game_state.submit_clear(n, 1000, 1)
	_game_state.current_stage = 1
	change_scene_to_file(SELECT)
	if not await _until_scene(SELECT, "記録を足してステージ選択を開く"):
		return true
	for _i: int in Tuning.STAGE_COUNT - 1:
		await _key(KEY_RIGHT)
	var s: Control = current_scene
	_expect(s.selected == Tuning.STAGE_COUNT and s.get_node("Cards").get_child(Tuning.STAGE_COUNT - 1).visible,
			"→ を %d 回で第%d試験を選び、そのカードが見えている" % [Tuning.STAGE_COUNT - 1, Tuning.STAGE_COUNT])
	await _key(KEY_ENTER)
	if not await _until_scene(GAME, "第%d試験を Enter で始める" % Tuning.STAGE_COUNT):
		return true
	var game: Node = current_scene
	game.auto_pause = false
	_expect(game.stage_data.get("id", "") == "stage_%02d" % Tuning.STAGE_COUNT and game._trolley != null,
			"第%d試験のステージが検証を通って走り出す（%s）" % [Tuning.STAGE_COUNT, game.stage_data.get("id", "")])
	return true


## 今の画面が path になるまで待つ
func _until_scene(path: String, label: String) -> bool:
	for _i: int in MAX_FRAMES:
		if current_scene != null and current_scene.scene_file_path == path:
			await _frames(2)  # 画面の _ready とフォーカスが落ち着くまで
			_expect(true, label)
			return true
		await process_frame
	_expect(false, "%s（今の画面: %s）" % [label, current_scene.scene_file_path if current_scene != null else "なし"])
	return false


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)
	await _frames(2)


func _frames(n: int) -> void:
	for _i: int in n:
		await process_frame


func _remove_test_files() -> void:
	for path: String in [TEST_SETTINGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
