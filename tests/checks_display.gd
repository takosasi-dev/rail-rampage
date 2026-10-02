extends SceneTree
## 画面の設定の自動確認（docs/superpowers/specs/2026-09-26-trolleys-and-display-design.md の4章）。
## 設定画面の「ゲーム」「画面」のタブ（マウスとキーボード、FR-47a）、「画面」の各項目の保存、F11、Web 版で隠す行、
## 画質ごとのゲーム画面（照明・影・雑音の模様・時間帯の暗さ・演出の数）、FPS 表示。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_display.gd （失敗があれば終了コード1）
## 描画のエラーは終了コードに出ないので、出力に「SCRIPT ERROR」が無いことも見る。
## 遊んでいる人の設定・記録を上書きしないよう、GameState の保存先を確認用のファイルに差し替え、最後に消す。

const SETTINGS_SCENE: String = "res://scenes/settings.tscn"
const TITLE_SCENE: String = "res://scenes/title.tscn"
const GAME_SCENE: String = "res://scenes/game.tscn"
const TEST_SETTINGS: String = "user://checks_display_settings.cfg"
const TEST_SAVE: String = "user://checks_display_save.cfg"
const SCREEN: Rect2 = Rect2(0, 0, 1280, 720)
const RAIL_Y: float = 600.0
const MAX_FRAMES: int = 2000

var _failed: int = 0
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前（GameState など）では参照できない
var _game_state: Node
var _fps: Node
var _games: Array = []  # この確認で作ったゲーム（最後に消す。解放済みも入る）


func _initialize() -> void:
	_run.call_deferred()  # _initialize の時点では root がまだツリーに無く、_ready が走らない


func _run() -> void:
	_game_state = root.get_node("GameState")
	_fps = root.get_node("FpsCounter")
	var real_settings: String = _game_state.settings_path
	var real_save: String = _game_state.save_path
	_game_state.settings_path = TEST_SETTINGS
	_game_state.save_path = TEST_SAVE
	_remove_test_files()
	_game_state.load_settings()  # 確認用のファイルが無い = 初期値から始める
	_game_state.load_records()
	var checks: Array[Callable] = [_check_tabs_mouse, _check_tabs_keyboard, _check_display_values, _check_f11,
			_check_web_rows, _check_pause_settings, _check_quality_scale, _check_quality_world, _check_quality_fx,
			_check_quality_next_run, _check_fps_counter]
	for check: Callable in checks:
		# 各確認は最後に true を返す。スクリプトエラーで止まると null が返る
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
		for game: Variant in _games:  # 型を付けると、解放済みのゲームを受けたときに止まる
			if is_instance_valid(game):
				(game as Node).free()
		_games.clear()
		paused = false
		root.get_node("TimeScale").clear()
		_game_state.quality = "high"  # 次の確認に持ち越さない（保存はしない）
		_game_state.show_fps = false
		_game_state.fullscreen = false
		Quality.level = "high"
	_remove_test_files()
	_game_state.settings_path = real_settings
	_game_state.save_path = real_save
	_game_state.load_settings()
	_game_state.load_records()
	# 鳴っている効果音を止め、片付ける音声スレッドが回るまで少しだけ実時間で待つ（checks.gd と同じ）
	for p: Node in root.get_node("Audio").get_children():
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	await physics_frame
	await physics_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# --- 設定画面のタブ ---

# 開くと「ゲーム」のタブで「戻る」にフォーカス。タブをクリックするとページが替わり、今のタブが警告黄になる。
# 確認欄を開いたままタブを替えると確認欄は閉じる。パネルはタブを替えても同じ大きさで、画面に収まる
func _check_tabs_mouse() -> bool:
	var s: Control = await _add(SETTINGS_SCENE)
	var game_tab: Button = s.get_node("%TabGame")
	var display_tab: Button = s.get_node("%TabDisplay")
	var grid: Control = s.get_node("%Grid")
	var display: Control = s.get_node("%DisplayGrid")
	var panel: Control = s.get_node("Panel")
	_expect(game_tab.text == "ゲーム" and display_tab.text == "画面", "タブは「ゲーム」「画面」（%s／%s）" % [game_tab.text, display_tab.text])
	_expect(s.page == 0 and grid.is_visible_in_tree() and not display.is_visible_in_tree() and s.get_node("%Back").has_focus(),
			"開くと「ゲーム」のタブで、フォーカスは今までどおり「戻る」")
	_expect(_bg(game_tab) == Palette.HAZARD and _bg(display_tab) == Color(0, 0, 0, 0), "今のタブは警告黄の地、ほかは地なし")
	var rect_game: Rect2 = panel.get_global_rect()
	await _click(display_tab)
	_expect(s.page == 1 and display.is_visible_in_tree() and not grid.is_visible_in_tree(), "「画面」をクリックすると画面のページになる")
	_expect(_bg(display_tab) == Palette.HAZARD and _bg(game_tab) == Color(0, 0, 0, 0), "警告黄の地が「画面」に移る")
	_expect(panel.get_global_rect() == rect_game and SCREEN.encloses(panel.get_global_rect().grow_individual(0, 0,
			Tuning.UI_PANEL_SHADOW.x, Tuning.UI_PANEL_SHADOW.y)),
			"タブを替えてもパネルは同じ位置と大きさで、影まで画面に収まる（%s）" % [panel.get_global_rect()])
	var labels: Array = display.get_children().filter(func(n: Node) -> bool: return n is Label).map(func(l: Label) -> String: return l.text)
	_expect(labels == ["画質", "FPS 上限", "垂直同期", "表示", "FPS 表示"], "画面のページの項目（%s）" % [labels])
	_expect(s.get_node("%QualityNote").is_visible_in_tree() and (s.get_node("%QualityNote") as Label).text.contains("次に始める試験"),
			"画質の下に、次に始める試験から変わることを書く")
	await _click(game_tab)
	_expect(s.page == 0 and grid.is_visible_in_tree(), "「ゲーム」をクリックするとゲームのページに戻る")
	var erase: Button = s.get_node("%Erase")
	var confirm: Control = s.get_node("%Confirm")
	erase.pressed.emit()
	await process_frame
	_expect(confirm.visible and SCREEN.encloses(panel.get_global_rect()), "確認欄を開いてもパネルは画面に収まる（%s）" % [panel.get_global_rect()])
	await _click(display_tab)
	await _click(game_tab)
	_expect(not confirm.visible and erase.visible, "確認欄を開いたままタブを替えると、確認欄は閉じる")
	var closed: Array[int] = [0]
	s.closed.connect(func() -> void: closed[0] += 1)
	await _click(display_tab)
	await _key(KEY_ESCAPE)
	_expect(closed[0] == 1, "FR-47d 「画面」のタブでも Esc で閉じる")
	s.free()
	return true


# FR-47a: ↑ でタブへ移り、←→ でタブを選び、Enter / Space で切り替える。タブから ↓ でそのページの項目へ移る
func _check_tabs_keyboard() -> bool:
	var s: Control = await _add(SETTINGS_SCENE)
	var tabs: Array = [s.get_node("%TabGame"), s.get_node("%TabDisplay")]  # 型を付けると、ボタン以外で has を呼べない
	var ups: int = 0
	while not tabs.has(root.gui_get_focus_owner()) and ups < 10:
		await _key(KEY_UP)
		ups += 1
	_expect(tabs[0].has_focus(), "「戻る」から ↑ を %d 回で今のタブ（ゲーム）へ移る" % ups)
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	_expect(tabs[1].has_focus() and s.page == 0, "→ で「画面」のタブへ移り、その先へは行かない（フォーカスが乗っただけでは切り替えない）")
	await _key(KEY_ENTER)
	_expect(s.page == 1 and tabs[1].has_focus(), "Enter で「画面」のページになり、フォーカスはタブに残る")
	await _key(KEY_DOWN)
	var focus: Control = root.gui_get_focus_owner()
	_expect(focus != null and s.get_node("%DisplayGrid").is_ancestor_of(focus), "↓ で画面のページの項目へ移る（%s）" % [focus.name if focus else null])
	for _i: int in 10:
		await _key(KEY_DOWN)
	_expect(s.get_node("%Back").has_focus(), "↓ を続けると「戻る」へ着く")
	for _i: int in 10:
		await _key(KEY_UP)
	_expect(tabs[1].has_focus(), "↑ を続けると今のタブ（画面）へ着く")
	await _key(KEY_LEFT)
	await _key(KEY_LEFT)
	_expect(tabs[0].has_focus(), "← で「ゲーム」のタブへ移り、その先へは行かない")
	await _key(KEY_SPACE)
	_expect(s.page == 0 and s.get_node("%Grid").is_visible_in_tree(), "Space で「ゲーム」のページに戻る")
	await _key(KEY_DOWN)
	focus = root.gui_get_focus_owner()
	_expect(focus != null and s.get_node("%Grid").is_ancestor_of(focus), "↓ でゲームのページの項目へ移る（%s）" % [focus.name if focus else null])
	s.free()
	return true


# 「画面」の各ボタンを押すと GameState の値が変わり、settings.cfg に保存され、押したボタンが墨地になる
func _check_display_values() -> bool:
	var s: Control = await _add(SETTINGS_SCENE)
	s.show_page(1)
	await process_frame
	_expect(_bg(s.get_node("%QualityHigh")) == Palette.INK and _bg(s.get_node("%FpsNone")) == Palette.INK
			and _bg(s.get_node("%VsyncOn")) == Palette.INK and _bg(s.get_node("%Windowed")) == Palette.INK
			and _bg(s.get_node("%ShowFpsOff")) == Palette.INK, "初期値（高・上限なし・ON・窓・OFF）が墨地で開く")
	var cases: Array = [["%QualityMedium", "quality", "medium"], ["%QualityLow", "quality", "low"], ["%QualityHigh", "quality", "high"],
			["%Fps30", "max_fps", 30], ["%Fps60", "max_fps", 60], ["%Fps120", "max_fps", 120], ["%FpsNone", "max_fps", 0],
			["%VsyncOff", "vsync", false], ["%VsyncOn", "vsync", true], ["%Fullscreen", "fullscreen", true],
			["%Windowed", "fullscreen", false], ["%ShowFpsOn", "show_fps", true], ["%ShowFpsOff", "show_fps", false]]
	for c: Array in cases:
		var b: Button = s.get_node(c[0])
		b.grab_focus()
		await _key(KEY_ENTER)
		var others: Array = b.get_parent().get_children().filter(func(n: Node) -> bool: return n != b)
		_expect(_game_state.get(c[1]) == c[2] and _saved(c[1]) == c[2] and _bg(b) == Palette.INK
				and others.all(func(o: Button) -> bool: return _bg(o) == Palette.PAPER),
				"「%s」で %s = %s になり、保存し、そのボタンだけ墨地（%s）" % [b.text, c[1], c[2], _game_state.get(c[1])])
	_expect((s.get_node("%Fps120") as Button).text == str(Tuning.FPS_LIMITS[2]) and Tuning.FPS_LIMITS[3] == 0,
			"FPS 上限のボタンの並びは Tuning.FPS_LIMITS の順")
	s.free()
	# 開き直すと保存した値で開く
	_game_state.set_quality("low")
	_game_state.set_max_fps(60)
	s = await _add(SETTINGS_SCENE)
	_expect(_bg(s.get_node("%QualityLow")) == Palette.INK and _bg(s.get_node("%Fps60")) == Palette.INK, "開き直すと保存した値（低・60）で開く")
	s.free()
	_game_state.set_quality("high")
	_game_state.set_max_fps(0)
	return true


# F11（GameState が受ける）で全画面を切り替えると、設定画面の「表示」の行もその場で変わる
func _check_f11() -> bool:
	var s: Control = await _add(SETTINGS_SCENE)
	s.show_page(1)
	await process_frame
	await _key(KEY_F11)
	_expect(_game_state.fullscreen and _bg(s.get_node("%Fullscreen")) == Palette.INK and _bg(s.get_node("%Windowed")) == Palette.PAPER,
			"設定を開いたまま F11 で全画面になり、「全画面」が墨地になる")
	await _key(KEY_F11)
	_expect(not _game_state.fullscreen and _bg(s.get_node("%Windowed")) == Palette.INK, "もう一度 F11 で窓に戻り、「窓」が墨地になる")
	_expect(s.is_inside_tree() and s.page == 1, "F11 では設定画面は閉じず、タブもそのまま")
	s.free()
	return true


# Web 版では FPS 上限・垂直同期・表示の行と F11 の操作を出さない（OS.has_feature は変えられないので apply_platform で確かめる）
func _check_web_rows() -> bool:
	var s: Control = await _add(SETTINGS_SCENE)
	var display: Control = s.get_node("%DisplayGrid")
	var keys: Control = s.get_node("%Keys")
	var panel: Control = s.get_node("Panel")
	var shown := func() -> Array:
		return display.get_children().filter(func(n: Node) -> bool: return n is Label and (n as CanvasItem).visible) \
				.map(func(l: Label) -> String: return l.text)
	_expect(shown.call() == ["画質", "FPS 上限", "垂直同期", "表示", "FPS 表示"] and (keys.get_node("Key4") as CanvasItem).visible,
			"Windows 版（今の確認）はすべての行と F11 を出す（%s）" % [shown.call()])
	s.apply_platform(true)
	await process_frame
	_expect(shown.call() == ["画質", "FPS 表示"] and not (s.get_node("%FpsRow") as CanvasItem).visible
			and not (s.get_node("%VsyncRow") as CanvasItem).visible and not (s.get_node("%WindowRow") as CanvasItem).visible,
			"Web 版は画質と FPS 表示の行だけ（%s）" % [shown.call()])
	_expect(not (keys.get_node("Key4") as CanvasItem).visible and not (keys.get_node("Desc4") as CanvasItem).visible,
			"Web 版は操作の一覧に F11 を出さない")
	var web_rect: Rect2 = panel.get_global_rect()
	s.show_page(1)
	await process_frame
	await process_frame
	_expect(panel.get_global_rect() == web_rect and SCREEN.encloses(web_rect), "Web 版でもタブを替えてパネルが動かない（%s）" % [web_rect])
	s.apply_platform(false)
	await process_frame
	_expect(shown.call().size() == 5 and (keys.get_node("Key4") as CanvasItem).visible, "Windows 版に戻すと行が戻る")
	s.free()
	return true


# ポーズから開く設定も同じ画面（タブがある）
func _check_pause_settings() -> bool:
	var game: Node = _new_game(_straight([]))
	await process_frame
	game.pause()
	await process_frame
	var overlay: Control = game._pause.open_settings()
	await process_frame
	_expect(overlay.scene_file_path == SETTINGS_SCENE and overlay.get_node("%TabDisplay") is Button and overlay.get_node("%Back").has_focus(),
			"ポーズから開く設定も同じ画面で、タブがあり「戻る」にフォーカス")
	await _click(overlay.get_node("%TabDisplay"))
	_expect(overlay.page == 1, "ポーズ中の設定でもタブを切り替えられる（木が止まっていても動く）")
	game.resume()
	return true


# --- 画質 ---

# 粒の数: 高はそのまま、中・低は減らす（1つ以上は残す）。演出の数の上限も
func _check_quality_scale() -> bool:
	Quality.level = "high"
	var same: bool = Tuning.SHARD_COUNT.values().all(func(n: int) -> bool: return Quality.count(n) == n) \
			and Quality.count(Tuning.PARTICLE_AMOUNT) == Tuning.PARTICLE_AMOUNT and Quality.max_effects() == Tuning.MAX_EFFECTS
	_expect(same and Quality.lights() and not Quality.plain(), "高は今のまま（粒の数・演出の上限・照明・重い描き方）")
	for level: String in ["medium", "low"]:
		Quality.level = level
		var fewer: bool = Tuning.SHARD_COUNT.values().all(func(n: int) -> bool: return Quality.count(n) < n and Quality.count(n) >= 1) \
				and Quality.count(1) == 1 and Quality.count(0) == 0 and Quality.max_effects() < Tuning.MAX_EFFECTS
		_expect(fewer, "%s は粒の数と演出の上限が高より少ない（1つ以上は残す）" % level)
	Quality.level = "medium"
	_expect(Quality.lights() and not Quality.plain(), "中は照明を残し、重い描き方も残す")
	Quality.level = "low"
	_expect(not Quality.lights() and Quality.plain(), "低は照明を切り、重い描き方を省く")
	return true


# 第4試験（C で深夜）: 画質ごとの照明・影・雑音の模様・全体の暗さ・車輪の火花とスピード線
func _check_quality_world() -> bool:
	_game_state.time_of_day_mode = TimeOfDay.MODE_STAGE
	var high_luma: float = 0.0
	for level: String in Tuning.QUALITY_LEVELS:
		_game_state.quality = level
		var game: Node = _new_game(StageLoader.load_json(_game_state.stage_path(4)))
		await process_frame
		_expect(game.time_of_day == "night" and Quality.level == level, "%s: 第4試験は深夜で、画質 %s で作る" % [level, Quality.level])
		var lights: Array[Node] = game.find_children("*", "PointLight2D", true, false)
		var on: int = lights.filter(func(l: PointLight2D) -> bool: return l.enabled).size()
		var lamps: int = game.get_node("World/Lamps").get_child_count()
		if level == "low":
			_expect(on == 0 and not game._trolley.headlight.enabled, "low: 照明（PointLight2D %d 個）はすべて切れている" % lights.size())
		else:
			_expect(on == lamps + 1 and game._trolley.headlight.enabled, "%s: 照明器具 %d 個と前照灯が点いている（%d）" % [level, lamps, on])
		var ambient: Color = (game.get_node("Ambient") as CanvasModulate).color
		if level == "high":
			high_luma = ambient.get_luminance()
		if level == "low":
			_expect(ambient.get_luminance() > high_luma + 0.3, "low: 深夜の暗さを弱める（明るさ %.2f、高は %.2f）" % [ambient.get_luminance(), high_luma])
		else:
			_expect(ambient == Palette.TOD_AMBIENT["night"], "%s: 全体の色は今のまま" % level)
		var rail_shadows: int = game._world.find_children("Shadow", "Node2D", true, false) \
				.filter(func(n: Node) -> bool: return n.get_parent().name == "Rail").size()
		var shadows: Array = game._targets.map(func(t: Target) -> Node: return t.get_node("Shadow"))
		var plain: bool = level == "low"
		_expect((rail_shadows == 0) == plain and shadows.all(func(d: DropShadow) -> bool: return d.visible != plain)
				and (game._trolley.get_node("Shadow") as CanvasItem).visible != plain,
				"%s: ぼかしの影（線路 %d 本・標的 %d 個・トロッコ）は%s" % [level, rail_shadows, shadows.size(), "省く" if plain else "描く"])
		_expect((game.get_node("Backdrop") as Backdrop).noise != plain, "%s: 奥の壁のむらと粒は%s" % [level, "省く" if plain else "描く"])
		var sparks: CPUParticles2D = game._trolley.get_node("WheelSparks")
		var lines: SpeedLines = game._trolley.get_node("SpeedLines")
		var want_sparks: int = Tuning.SPARK_AMOUNT if level == "high" else Quality.count(Tuning.SPARK_AMOUNT)
		var want_lines: int = Tuning.SPEED_LINES.size() if level == "high" else Quality.count(Tuning.SPEED_LINES.size())
		_expect(sparks.amount == want_sparks and lines.line_count() == want_lines and (level == "high" or want_lines < Tuning.SPEED_LINES.size()),
				"%s: 車輪の火花 %d 粒・スピード線 %d 本" % [level, sparks.amount, lines.line_count()])
		game.free()
	return true


# ドラム缶の爆発: 画質ごとの煙・金属の破片・閃光（PointLight2D）・破片のパーティクルの数。高は今と同じ
func _check_quality_fx() -> bool:
	for level: String in Tuning.QUALITY_LEVELS:
		_game_state.quality = level
		var game: Node = _new_game(_straight([_obj("drum", 600)]))
		var drum: Target = game._targets[0]
		await _frames_until(func() -> bool: return drum.exploded)
		await physics_frame
		var fx: Node2D = game.get_node("World/Effects")
		var metal: Array = _of(fx, Shards).filter(func(n: Shards) -> bool: return n.kind == "metal")
		var smoke: Array = _of(fx, Puffs).filter(func(n: Puffs) -> bool: return n.kind == "smoke")
		var burst: Array = _of(game._world, CPUParticles2D)
		var pieces: int = (metal[0] as Shards)._pieces.size() if metal.size() == 1 else -1
		var puffs: int = (smoke[0] as Puffs)._puffs.size() if smoke.size() == 1 else -1
		var amount: int = (burst[0] as CPUParticles2D).amount if burst.size() == 1 else -1
		if level == "high":
			_expect(pieces == Tuning.SHARD_COUNT["metal"] and puffs == Tuning.PUFF_COUNT["smoke"] and amount == Tuning.PARTICLE_AMOUNT,
					"high: 金属の破片 %d・煙 %d・パーティクル %d は今と同じ" % [pieces, puffs, amount])
		else:
			_expect(pieces == Quality.count(Tuning.SHARD_COUNT["metal"]) and pieces < Tuning.SHARD_COUNT["metal"]
					and puffs < Tuning.PUFF_COUNT["smoke"] and amount < Tuning.PARTICLE_AMOUNT and pieces > 0 and puffs > 0 and amount > 0,
					"%s: 金属の破片 %d・煙 %d・パーティクル %d に減る" % [level, pieces, puffs, amount])
		var flashes: Array = _of(fx, Flash)
		_expect((flashes.size() == 1) == (level != "low"), "%s: 爆発の閃光（PointLight2D）は%s" % [level, "出さない" if level == "low" else "出す"])
		_expect(_of(fx, Fireball).size() == 1 and _of(fx, Shockwave).size() == 1, "%s: 火の玉と衝撃波の輪は残す" % level)
		for i: int in Tuning.MAX_EFFECTS + 20:
			Fx.impact(fx, Vector2(i, 0), 100)
		_expect(fx.get_child_count() == Tuning.QUALITY_MAX_EFFECTS[level], "%s: 同時の演出は %d まで（%d）" % [
				level, Tuning.QUALITY_MAX_EFFECTS[level], fx.get_child_count()])
		game.free()
	return true


# 画質はゲーム画面を作るときに読む: プレイ中に変えても今の試験は変わらず、リトライした画面から効く
func _check_quality_next_run() -> bool:
	_game_state.time_of_day_mode = TimeOfDay.MODE_STAGE
	_game_state.quality = "high"
	var game: Node = _new_game(StageLoader.load_json(_game_state.stage_path(4)))
	await process_frame
	game.pause()
	_game_state.set_quality("low")  # ポーズの設定で変えた
	game.resume()
	await process_frame
	_expect(game._trolley.headlight.enabled and Quality.level == "high", "プレイ中に低にしても、今の試験は照明が点いたまま")
	game._last_retry = -INF
	var fresh: Node = game.retry()
	_games.append(fresh)
	await process_frame
	await process_frame
	_expect(is_instance_valid(fresh) and fresh.is_inside_tree() and Quality.level == "low" and not fresh._trolley.headlight.enabled,
			"リトライした画面から低になる（前照灯が消える）")
	_game_state.set_quality("high")
	return true


# --- FPS 表示 ---

# ON ならどの画面でも左上の隅に今の FPS。HUD の札・デバッグ版の右下の表示・タイトルのボタンと重ならない。OFF なら出さない
func _check_fps_counter() -> bool:
	await process_frame
	_expect(_fps.text() == "" and (_fps as CanvasLayer).layer > 2, "FPS 表示は初期値 OFF で出さない。層はポーズ・リザルトより手前")
	_game_state.set_show_fps(true)
	await process_frame
	var label: Label = _fps.get_node("Fps")
	var digits := RegEx.create_from_string("^\\d+ FPS$")
	_expect(label.visible and digits.search(_fps.text()) != null, "ON にすると「N FPS」を出す（%s）" % _fps.text())
	var r: Rect2 = label.get_global_rect()
	_expect(SCREEN.encloses(r) and r.position.x <= Tuning.FPS_PAD.x and r.position.y <= Tuning.FPS_PAD.y, "左上の隅に出す（%s）" % [r])
	var game: Node = _new_game(_straight([]))
	await process_frame
	var hud: Array[Rect2] = game._hud_view.panels()
	var debug: Label = game._debug_label
	_expect(hud.all(func(p: Rect2) -> bool: return not p.intersects(r)) and not debug.get_global_rect().intersects(r),
			"HUD の札（%d 枚）とデバッグ版の右下の表示に重ならない" % hud.size())
	game.pause()
	await process_frame
	_expect(label.is_visible_in_tree() and not game._pause.get_node("Panel").get_global_rect().intersects(r), "ポーズ中も出し、ポーズのパネルに重ならない")
	game.resume()
	game.free()
	var title: Control = await _add(TITLE_SCENE)
	var buttons: Array = title.find_children("*", "Button", true, false)
	_expect(buttons.size() >= 3 and buttons.all(func(b: Button) -> bool: return not b.get_global_rect().intersects(r)),
			"タイトルのボタン %d 個に重ならない" % buttons.size())
	var s: Control = await _add(SETTINGS_SCENE)
	_expect(not s.get_node("Panel").get_global_rect().intersects(r), "設定のパネルに重ならない")
	s.free()
	title.free()
	_game_state.set_show_fps(false)
	await process_frame
	_expect(not label.visible and _fps.text() == "", "OFF にすると消える")
	return true


# --- 補助 ---

## 画面を開く。コンテナの並べ替えは次のフレームなので、1フレーム待ってから返す
func _add(path: String) -> Control:
	var node: Control = (load(path) as PackedScene).instantiate()
	root.add_child(node)
	await process_frame
	return node


func _new_game(data: Dictionary) -> Node:
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.stage_data = data
	game.auto_pause = false  # 窓が無いのでフォーカスを失った扱いでポーズしないように
	root.add_child(game)
	_games.append(game)
	return game


func _straight(objects: Array) -> Dictionary:
	return {
		"id": "check", "name": "check", "ground_y": 900.0, "start_segment": "s0", "star_thresholds": [1, 2],
		"segments": {"s0": {"points": [[0, RAIL_Y], [4000, RAIL_Y]], "end": {"type": "goal"}}},
		"junctions": {}, "objects": objects}


func _obj(type: String, offset: float) -> Dictionary:
	return {"type": type, "segment": "s0", "offset": offset}


## node の直下にある type の子
func _of(node: Node, type: Variant) -> Array:
	return node.get_children().filter(func(n: Node) -> bool: return is_instance_of(n, type))


func _frames_until(done: Callable) -> void:
	for _i: int in MAX_FRAMES:
		if done.call():
			return
		await physics_frame


## キーを押して離し、1フレーム進める
func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)
	await process_frame


## c の真ん中をマウスでクリックする
func _click(c: Control) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = c.get_global_rect().get_center()
		ev.global_position = ev.position
		root.push_input(ev, true)
	await process_frame


## ボタンの地の色（地なしなら透明）
func _bg(b: Button) -> Color:
	var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
	return sb.bg_color if sb != null and sb.draw_center else Color(0, 0, 0, 0)


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
