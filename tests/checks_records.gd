extends SceneTree
## 試験記録・検定印・修了証書のデータの自動確認（設計書 docs/superpowers/specs/2026-09-26-records-design.md の2章・5章）。
## 書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_records.gd （失敗があれば終了コード1）
## 設定・記録は確認用のファイルに差し替え、最後に消す。

const GAME_SCENE: String = "res://scenes/game.tscn"
const TEST_SETTINGS: String = "user://checks_records_settings.cfg"
const TEST_SAVE: String = "user://checks_records_save.cfg"
const RAIL_Y: float = 600.0
const MAX_FRAMES: int = 3000
const KINDS: Array[String] = ["crate", "barrel", "dummy", "drum", "wall"]
const STAMP_COUNT: int = 30  # 設計書 2.3 の検定印の数（やりこみ要素で14個足した。replay-value-design.md 8章）
const NO_STAR: int = 900000  # 確かめるステージの★2の閾値（★3 にならず、満点答案を取らない）

var _failed: int = 0
var _game_state: Node  # autoload（-s のスクリプトでは名前で参照できない）
var _time_scale: Node
var _games: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_game_state = root.get_node("GameState")
	_time_scale = root.get_node("TimeScale")
	var real_settings: String = _game_state.settings_path
	var real_save: String = _game_state.save_path
	_game_state.settings_path = TEST_SETTINGS
	_game_state.save_path = TEST_SAVE
	var checks: Array[Callable] = [_check_blank, _check_totals, _check_run_stamps, _check_total_stamps,
			_check_progress_stamps, _check_stamp_once, _check_save_load, _check_broken_values, _check_erase,
			_check_list, _check_game_goal, _check_game_crash, _check_game_derail, _check_game_retry,
			_check_game_select, _check_game_toggles, _check_game_chain, _check_game_certificate, _check_fullscreen_setting,
			_check_fullscreen_key, _check_old_save, _check_unrecorded_clear]
	for check: Callable in checks:
		_reset()
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
		for game: Variant in _games:  # 型を付けると、解放済みのゲームを受けたときに止まる
			if is_instance_valid(game):
				(game as Node).free()
		_games.clear()
		if current_scene != null:
			current_scene.free()
		_time_scale.clear()
		paused = false
	_remove_test_files()
	_game_state.settings_path = real_settings
	_game_state.save_path = real_save
	_game_state.load_settings()
	_game_state.load_records()
	for p: Node in root.get_node("Audio").get_children():
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	await physics_frame
	await physics_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


func _reset() -> void:
	_remove_test_files()
	_game_state.load_settings()
	_game_state.load_records()
	_game_state.current_stage = 1


# --- 累計（設計書 2.1, 2.2） ---

func _check_blank() -> bool:
	var s: Dictionary = _game_state.stats()
	var zero_kinds: bool = KINDS.all(func(k: String) -> bool: return s["smashed"][k] == 0)
	_expect(s["runs"] == 0 and s["clears"] == 0 and s["crashes"] == 0 and s["derails"] == 0 and zero_kinds
			and s["girigiri"] == 0 and s["best_speed"] == 0.0 and s["best_combo"] == 0 and s["distance"] == 0.0
			and (s["attempts"] as Dictionary).is_empty() and s["completed_on"] == "",
			"記録が無いときの累計はすべて0（%s）" % s)
	_expect((_game_state.stamps() as Dictionary).is_empty(), "記録が無いときは検定印が無い")
	_expect(not _game_state.all_cleared(), "記録が無いときは全試験に合格していない")
	return true


func _check_totals() -> bool:
	_game_state.submit_run(_run_of("clear", {"stage": 2, "smashed": {"crate": 3, "dummy": 2}, "girigiri": 1, "max_combo": 7,
			"max_speed": 700.0, "distance": 5000.0, "score": 1200}))
	_game_state.submit_run(_run_of("crash", {"stage": 2, "smashed": {"crate": 1, "wall": 1}, "girigiri": 2, "max_combo": 4,
			"max_speed": 900.0, "distance": 3000.0}))
	_game_state.submit_run(_run_of("derail", {"stage": 5, "max_combo": 9, "max_speed": 600.0, "distance": 1000.0}))
	_game_state.submit_run(_run_of("abort", {"stage": 5, "smashed": {"barrel": 4}, "distance": 500.0}))
	var s: Dictionary = _game_state.stats()
	_expect(s["runs"] == 4 and s["clears"] == 1 and s["crashes"] == 1 and s["derails"] == 1,
			"走った回数は結果を問わず数え、合格・激突・脱線は別に数える（%d・%d・%d・%d）" % [s["runs"], s["clears"], s["crashes"], s["derails"]])
	_expect(s["smashed"] == {"crate": 4, "barrel": 4, "dummy": 2, "drum": 0, "wall": 1}, "壊した数を種類ごとに足す（%s）" % s["smashed"])
	_expect(s["girigiri"] == 3 and is_equal_approx(s["distance"], 9500.0), "ギリギリ突破と距離は足す（%d・%.0f）" % [s["girigiri"], s["distance"]])
	_expect(s["best_speed"] == 900.0 and s["best_combo"] == 9, "最高速度と最大コンボは大きい方（%.0f・%d）" % [s["best_speed"], s["best_combo"]])
	_expect(s["attempts"] == {2: 2, 5: 2}, "試験ごとに走った回数を数える（%s）" % s["attempts"])
	return true


# --- 検定印（設計書 2.3） ---

func _check_run_stamps() -> bool:
	var need: int = Tuning.ACH_COMBO
	var game_script: GDScript = load("res://scenes/game.gd")
	_expect(game_script.combo_multiplier(need) >= Tuning.COMBO_MULT_MAX and game_script.combo_multiplier(need - 1) < Tuning.COMBO_MULT_MAX,
			"倍率上限の条件 ACH_COMBO（%d）はコンボ倍率が x%.1f に届く最小のコンボ" % [need, Tuning.COMBO_MULT_MAX])
	var top: float = Tuning.SPEED_MAX - Tuning.ACH_TOP_SPEED_SLACK
	_expect(Display.to_display_speed(top) == Display.to_display_speed(Tuning.SPEED_MAX) - 1,
			"最高速度の検定印は表示で1km/h 手前から取れる（%d km/h）" % Display.to_display_speed(top))
	var cases: Array = [
		["combo_max", _run_of("clear", {"max_combo": need - 1}), _run_of("abort", {"max_combo": need})],
		["chain", _run_of("clear", {"chained": Tuning.ACH_CHAIN - 1}), _run_of("crash", {"chained": Tuning.ACH_CHAIN})],
		["top_speed", _run_of("clear", {"max_speed": top - 1.0}), _run_of("derail", {"max_speed": top})],
		["no_toggle", _run_of("crash", {"toggles": 0}), _run_of("clear", {"toggles": 0})],
		["no_toggle", _run_of("clear", {"toggles": 1}), _run_of("clear", {"toggles": 0})],
		["big_score", _run_of("clear", {"score": Tuning.ACH_BIG_SCORE - 1}), _run_of("clear", {"score": Tuning.ACH_BIG_SCORE})],
		["big_score", _run_of("crash", {"score": Tuning.ACH_BIG_SCORE}), _run_of("clear", {"score": Tuning.ACH_BIG_SCORE})],
		["first_crash", _run_of("derail", {}), _run_of("crash", {})],
		["first_derail", _run_of("abort", {}), _run_of("derail", {})],
	]
	for c: Array in cases:
		_reset()
		_game_state.submit_clear(1, 0, 1)  # 合格の走行は、その試験の合格が記録されているときだけ「合格」として数える
		var before: Array = _game_state.submit_run(c[1])
		var after: Array = _game_state.submit_run(c[2])
		_expect(not before.has(c[0]) and after.has(c[0]) and (_game_state.stamps() as Dictionary).has(c[0]),
				"%s: %s では取れず、%s で取れる（%s → %s）" % [c[0], _brief(c[1]), _brief(c[2]), before, after])
	return true


func _check_total_stamps() -> bool:
	var cases: Array = [["dummy100", {"dummy": Tuning.ACH_DUMMY}], ["drum50", {"drum": Tuning.ACH_DRUM}],
			["wall30", {"wall": Tuning.ACH_WALL}], ["smash1000", {"crate": Tuning.ACH_SMASH - 3, "barrel": 3}]]
	for c: Array in cases:
		_reset()
		var less: Dictionary = (c[1] as Dictionary).duplicate()
		var key: String = less.keys()[0]
		less[key] -= 1
		var first: Array = _game_state.submit_run(_run_of("abort", {"smashed": less}))
		var second: Array = _game_state.submit_run(_run_of("abort", {"smashed": {key: 1}}))
		_expect(not first.has(c[0]) and second.has(c[0]), "%s: 累計が条件の1つ手前では取れず、届いた走行で取れる（%s → %s）" % [c[0], first, second])
	_reset()
	var got: Array = []
	for i: int in Tuning.ACH_GIRIGIRI:
		got = _game_state.submit_run(_run_of("clear", {"girigiri": 1, "toggles": 1}))
		_expect(got.has("girigiri") == (i == Tuning.ACH_GIRIGIRI - 1), "girigiri: ギリギリ突破の累計 %d 回目で取る（%s）" % [i + 1, got])
	return true


func _check_progress_stamps() -> bool:
	for n: int in range(1, 5):
		_game_state.submit_clear(n, 100, 1)
	var got: Array = _game_state.submit_run(_run_of("clear", {"stage": 4}))
	_expect(not got.has("basic"), "第1〜4試験の合格では基礎課程修了にならない（%s）" % [got])
	_game_state.submit_clear(5, 100, 1)
	got = _game_state.submit_run(_run_of("clear", {"stage": 5}))
	_expect(got.has("basic") and not got.has("full_marks"), "第5試験に合格すると基礎課程修了（★3 はまだ）（%s）" % [got])
	_game_state.submit_clear(3, 100, Tuning.STARS_MAX)
	got = _game_state.submit_run(_run_of("clear", {"stage": 3}))
	_expect(got.has("full_marks") and not got.has("all_stars"), "★3 を1つ取ると満点答案（%s）" % [got])
	for n: int in range(6, Tuning.STAGE_COUNT + 1):
		_game_state.submit_clear(n, 100, 1)
	_expect(_game_state.all_cleared() and _game_state.stats()["completed_on"] == "", "全試験に合格した後、走行を出すまで修了日はまだ無い")
	got = _game_state.submit_run(_run_of("clear", {"stage": Tuning.STAGE_COUNT}))
	var on: String = _game_state.stats()["completed_on"]
	_expect(got.has("all_clear") and on == Time.get_date_string_from_system(), "全試験に合格すると全課程修了と修了日（%s・%s）" % [got, on])
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		_game_state.submit_clear(n, 100, Tuning.STARS_MAX)
	got = _game_state.submit_run(_run_of("clear", {"stage": 1}))
	_expect(got == ["all_stars"], "★を全部集めると全★制覇（ほかはもう取っている）（%s）" % [got])
	_expect(_game_state.stats()["completed_on"] == on, "修了日は最初に修了した日のまま")
	return true


func _check_stamp_once() -> bool:
	var first: Array = _game_state.submit_run(_run_of("crash", {"girigiri": Tuning.ACH_GIRIGIRI}))
	var second: Array = _game_state.submit_run(_run_of("crash", {"girigiri": Tuning.ACH_GIRIGIRI}))
	_expect(first == ["girigiri", "first_crash"], "新しく取った検定印は Achievements.LIST の順（%s）" % [first])
	_expect(second.is_empty(), "取った検定印は2回目には新しくならない（%s）" % [second])
	var stamps: Dictionary = _game_state.stamps()
	_expect(stamps.get("first_crash", "") == Time.get_date_string_from_system(), "検定印には取った日が残る（%s）" % stamps)
	return true


func _check_save_load() -> bool:
	_game_state.submit_clear(1, 500, 2)
	_game_state.submit_run(_run_of("clear", {"stage": 1, "smashed": {"crate": 5}, "girigiri": 3, "max_combo": 6,
			"max_speed": 812.5, "distance": 4321.5}))
	var s: Dictionary = _game_state.stats()
	var st: Dictionary = _game_state.stamps()
	_game_state.load_records()
	_expect(_game_state.stats() == s and _game_state.stamps() == st, "累計と検定印は save.cfg に残り、読み直しても同じ（%s・%s）" % [
			_game_state.stats(), _game_state.stamps()])
	_expect(_game_state.record(1)["best_score"] == 500, "ステージの記録も残る")
	return true


func _check_broken_values() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "runs", "abc")
	cfg.set_value("stats", "clears", 3)
	cfg.set_value("stats", "crashes", -2)
	cfg.set_value("stats", "smashed", {"crate": 4, "barrel": "x", "dummy": -1, "bogus": 9})
	cfg.set_value("stats", "best_speed", 750)  # int でも数として読む
	cfg.set_value("stats", "distance", -5.0)
	cfg.set_value("stats", "attempts", {1: 3, "2": 4, 3: -1})
	cfg.set_value("stats", "completed_on", 20260926)
	cfg.set_value("stamps", "chain", "2026-09-20")
	cfg.set_value("stamps", "unknown_id", "2026-09-20")
	cfg.set_value("stamps", "basic", 5)
	cfg.save(TEST_SAVE)
	_game_state.load_records()
	var s: Dictionary = _game_state.stats()
	_expect(s["runs"] == 0 and s["clears"] == 3 and s["crashes"] == 0, "型が違う・負の回数はそのキーだけ0（%d・%d・%d）" % [s["runs"], s["clears"], s["crashes"]])
	_expect(s["smashed"] == {"crate": 4, "barrel": 0, "dummy": 0, "drum": 0, "wall": 0}, "壊した数も種類ごとに確かめる（%s）" % s["smashed"])
	_expect(s["best_speed"] == 750.0 and s["distance"] == 0.0, "速度は整数でも読み、負の距離は0（%s・%s）" % [s["best_speed"], s["distance"]])
	_expect(s["attempts"] == {1: 3}, "試験ごとの回数は番号が1〜STAGE_COUNT の整数で回数が0以上のものだけ（%s）" % s["attempts"])
	_expect(s["completed_on"] == "", "修了日が文字でなければ無し")
	_expect(_game_state.stamps() == {"chain": "2026-09-20"}, "知らない id・日付が文字でない検定印は捨てる（%s）" % _game_state.stamps())
	var inf := ConfigFile.new()
	inf.set_value("stats", "best_speed", INF)
	inf.set_value("stats", "distance", INF)
	inf.save(TEST_SAVE)
	_game_state.load_records()
	_expect(_game_state.stats()["best_speed"] == 0.0 and _game_state.stats()["distance"] == 0.0, "無限大の速度・距離は0")
	return true


func _check_erase() -> bool:
	_game_state.submit_clear(1, 500, 2)
	_game_state.submit_run(_run_of("crash", {"smashed": {"dummy": 2}}))
	_game_state.erase_records()
	_expect(_game_state.stats() == _blank_stats() and (_game_state.stamps() as Dictionary).is_empty(),
			"FR-47c 記録を消去すると累計と検定印も消える")
	var cfg := ConfigFile.new()
	_expect(cfg.load(TEST_SAVE) == OK and cfg.get_sections().is_empty(), "消去した後の save.cfg は空（%s）" % [cfg.get_sections()])
	_game_state.load_records()
	_expect(_game_state.stats() == _blank_stats(), "消去した後に読み直しても累計は0")
	return true


func _check_list() -> bool:
	var ids: Array = Achievements.LIST.map(func(a: Array) -> String: return a[0])
	_expect(ids.size() == STAMP_COUNT and ids.size() == _unique(ids).size(), "検定印は %d 個で id が重ならない（%d）" % [STAMP_COUNT, ids.size()])
	var named: bool = Achievements.LIST.all(func(a: Array) -> bool: return a.size() == 3 and (a[1] as String) != "" and (a[2] as String) != "")
	_expect(named, "検定印はどれも [id, 名前, 条件] を持つ")
	_expect(ids.has("all_clear"), "全課程修了（修了証書）の検定印がある")
	var unfilled: Array = ids.filter(func(id: String) -> bool: return Achievements.describe(id).contains("{"))
	_expect(unfilled.is_empty(), "条件の文の {…} はすべて数値が入る（%s）" % [unfilled])
	_expect(Achievements.describe("top_speed") == "最高速度（%dkm/h）に届く" % Display.to_display_speed(Tuning.SPEED_MAX)
			and Achievements.name_of("chain") == "連鎖反応" and Achievements.name_of("nope") == "",
			"名前と条件の文を id で引ける（%s）" % Achievements.describe("top_speed"))
	var per_km: float = Tuning.METERS_PER_KM / Tuning.DISPLAY_METERS_PER_PX  # 1km の px
	_expect(Display.distance_text(0.0) == "0 m" and Display.distance_text(per_km * 0.999) == "999 m"
			and Display.distance_text(per_km) == "1.0 km" and Display.distance_text(per_km * 12.34) == "12.3 km"
			and Display.distance_text(per_km * 2743.5) == "2,743.5 km",
			"走った距離は1000m 未満は m、以上は小数1桁の km で3桁区切り（%s・%s・%s）" % [Display.distance_text(per_km * 0.999),
				Display.distance_text(per_km * 12.34), Display.distance_text(per_km * 2743.5)])
	return true


# --- ゲーム画面から（設計書 2.2） ---

func _check_game_goal() -> bool:
	var game: Node = _new_game(_straight([_obj("crate", 600), _obj("crate", 900), _obj("dummy", 1400)]))
	await _frames_until(func() -> bool: return game._result != null)
	var s: Dictionary = _game_state.stats()
	_expect(s["runs"] == 1 and s["clears"] == 1 and s["smashed"]["crate"] == 2 and s["smashed"]["dummy"] == 1,
			"ゴールで1回分の走行を出す（%d 回・合格 %d・%s）" % [s["runs"], s["clears"], s["smashed"]])
	_expect(absf(s["distance"] - 4000.0) < 40.0, "走った距離はゴールまでの長さ（%.0f / 4000）" % s["distance"])
	_expect(s["attempts"] == {1: 1} and s["best_combo"] == game.max_combo and is_equal_approx(s["best_speed"], game.max_speed),
			"試験番号・最大コンボ・最高速度も出す（%s・%d・%.0f）" % [s["attempts"], s["best_combo"], s["best_speed"]])
	var data: Dictionary = game.result_data()
	_expect(data.get("new_stamps") is Array and data.get("certificate") == false,
			"リザルトのデータに new_stamps と certificate がある（%s・%s）" % [data.get("new_stamps"), data.get("certificate")])
	_expect(data["new_stamps"] == ["no_toggle"], "切り替えずに合格すると初志貫徹（%s）" % [data["new_stamps"]])
	_games.append(game.retry())  # リザルトの後のリトライは走行を出さない（作り直した画面も後で消す）
	await _frames(3)
	_expect(_game_state.stats()["runs"] == 1, "走行が終わった後のリトライでは、もう出さない（%d）" % _game_state.stats()["runs"])
	return true


func _check_game_crash() -> bool:
	var wall: Dictionary = _obj("wall", 900)
	wall["required_speed"] = Tuning.SPEED_MAX
	var game: Node = _new_game(_straight([wall]))
	await _frames_until(func() -> bool: return game._result != null)
	var s: Dictionary = _game_state.stats()
	_expect(s["runs"] == 1 and s["crashes"] == 1 and s["clears"] == 0, "激突で1回分の走行を出す（%d・%d）" % [s["runs"], s["crashes"]])
	_expect(game.result_data()["new_stamps"] == ["first_crash"], "激突すると激突の記録（%s）" % [game.result_data()["new_stamps"]])
	return true


func _check_game_derail() -> bool:
	var data: Dictionary = _straight([])
	data["segments"] = {
		"s0": {"points": [[0, RAIL_Y], [1200, RAIL_Y]], "end": {"type": "next", "segment": "s1"}},
		"s1": {"points": [[1200, RAIL_Y], [1600, RAIL_Y]], "end": {"type": "next", "segment": "s2"},
				"jump": {"required_speed": Tuning.SPEED_MAX}},
		"s2": {"points": [[1600, RAIL_Y], [4000, RAIL_Y]], "end": {"type": "goal"}}}
	var game: Node = _new_game(data)
	await _frames_until(func() -> bool: return game._result != null)
	var s: Dictionary = _game_state.stats()
	_expect(s["runs"] == 1 and s["derails"] == 1, "脱線で1回分の走行を出す（%d・%d）" % [s["runs"], s["derails"]])
	_expect(game.result_data()["new_stamps"] == ["first_derail"], "脱線すると脱線の記録（%s）" % [game.result_data()["new_stamps"]])
	return true


func _check_game_retry() -> bool:
	var game: Node = _new_game(_straight([_obj("crate", 600)]))
	await _frames_until(func() -> bool: return game.smashed_count > 0)
	var fresh: Node = game.retry()
	_games.append(fresh)
	await _frames(2)
	var s: Dictionary = _game_state.stats()
	_expect(s["runs"] == 1 and s["clears"] == 0 and s["smashed"]["crate"] == 1 and s["attempts"] == {1: 1},
			"走っている途中のリトライは「途中でやめた」1回（%d・%d・%s）" % [s["runs"], s["clears"], s["smashed"]])
	fresh.auto_pause = false
	await _frames_until(func() -> bool: return fresh._result != null)
	_expect(_game_state.stats()["runs"] == 2 and _game_state.stats()["clears"] == 1, "やり直した走行のゴールでもう1回（%d）" % _game_state.stats()["runs"])
	return true


func _check_game_select() -> bool:
	var game: Node = _new_game(_straight([]))
	await _frames(10)
	game.pause()
	game._to_stage_select()
	await _frames(2)
	_expect(_game_state.stats()["runs"] == 1, "ポーズの「ステージ選択へ」は「途中でやめた」1回（%d）" % _game_state.stats()["runs"])
	return true


func _check_game_toggles() -> bool:
	var game: Node = _new_game(_forked())
	await _frames(5)
	var ev := InputEventAction.new()
	ev.action = &"toggle_switch"
	ev.pressed = true
	game._unhandled_input(ev)
	await _frames_until(func() -> bool: return game._result != null)
	_expect(not (game.result_data()["new_stamps"] as Array).has("no_toggle"), "切り替えた走行では初志貫徹にならない（%s）" % [game.result_data()["new_stamps"]])
	return true


func _check_game_chain() -> bool:
	var game: Node = _new_game(_straight([_obj("drum", 700), _obj("drum", 760), _obj("drum", 820)]))
	await _frames_until(func() -> bool: return game._result != null)
	var got: Array = game.result_data()["new_stamps"]
	_expect(got.has("chain"), "1つ目の爆発に巻き込まれた2個が爆発すると連鎖反応（%s）" % [got])
	return true


func _check_game_certificate() -> bool:
	for n: int in range(1, Tuning.STAGE_COUNT):
		_game_state.submit_clear(n, 100, 1)
	var data: Dictionary = _straight([])
	data["id"] = "stage_%02d" % Tuning.STAGE_COUNT
	var game: Node = _new_game(data)
	await _frames_until(func() -> bool: return game._result != null)
	var r: Dictionary = game.result_data()
	_expect(r["certificate"] == true and (r["new_stamps"] as Array).has("all_clear"),
			"最後の1つに合格して全試験がそろうと、リザルトのデータの certificate が true（%s）" % [r["new_stamps"]])
	return true


# --- 全画面（設計書4章） ---

func _check_fullscreen_setting() -> bool:
	_expect(_game_state.fullscreen == false, "設定が無いときは窓で開く")
	_game_state.set_fullscreen(true)
	var cfg := ConfigFile.new()
	_expect(cfg.load(TEST_SETTINGS) == OK and cfg.get_value("settings", "fullscreen", false) == true, "全画面に変えるとすぐ settings.cfg に保存する")
	_game_state.fullscreen = false
	_game_state.load_settings()
	_expect(_game_state.fullscreen == true, "次に起動したとき（設定を読み直したとき）全画面に戻す")
	cfg.set_value("settings", "fullscreen", "yes")
	cfg.save(TEST_SETTINGS)
	_game_state.load_settings()
	_expect(_game_state.fullscreen == false, "型が違えば窓（初期値）")
	return true


func _check_fullscreen_key() -> bool:
	var keys: Array = InputMap.action_get_events(&"toggle_fullscreen").map(func(e: InputEvent) -> int:
		return (e as InputEventKey).physical_keycode if e is InputEventKey else -1)
	_expect(keys == [KEY_F11], "入力 toggle_fullscreen は F11（%s）" % [keys])
	_expect(_game_state.process_mode == Node.PROCESS_MODE_ALWAYS, "ポーズ中も F11 を受ける（GameState は木が止まっても動く）")
	var ev := InputEventAction.new()
	ev.action = &"toggle_fullscreen"
	ev.pressed = true
	_game_state._unhandled_input(ev)
	_expect(_game_state.fullscreen == true, "F11 で全画面になる")
	_game_state._unhandled_input(ev)
	_expect(_game_state.fullscreen == false, "もう一度 F11 で窓に戻る")
	var settings: Control = (load("res://scenes/settings.tscn") as PackedScene).instantiate()
	root.add_child(settings)
	var texts: Array = settings.get_node("%Keys").get_children().filter(func(n: Node) -> bool: return (n as CanvasItem).visible) 			.map(func(l: Label) -> String: return l.text)
	_expect(texts.has("F11") and texts.has("全画面の切り替え"), "設定の操作の一覧に F11 がある（%s）" % [texts])
	settings.free()
	return true


# --- 検定印が入る前の記録（レビューの指摘） ---

# 検定印の無い古い save.cfg: 進み具合で決まる印（基礎課程修了・全課程修了・満点答案・全★制覇）は読み込んだ時点で付け、
# 修了日もその日にする。次の走行（激突）では、その走行で取った印だけが新しい
func _check_old_save() -> bool:
	var cfg := ConfigFile.new()
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		var key: String = "stage_%02d" % n
		cfg.set_value(key, "cleared", true)
		cfg.set_value(key, "best_score", 1000)
		cfg.set_value(key, "stars", Tuning.STARS_MAX)
	cfg.save(TEST_SAVE)
	_game_state.load_records()
	var today: String = Time.get_date_string_from_system()
	var stamps: Dictionary = _game_state.stamps()
	_expect(stamps == {"basic": today, "all_clear": today, "full_marks": today, "all_stars": today, "license_standard": today},
			"古い記録を読むと、進み具合で決まる印をその場で付ける（%s）" % stamps)
	_expect(_game_state.stats()["completed_on"] == today, "全試験に合格している古い記録の修了日は読んだ日")
	var got: Array = _game_state.submit_run(_run_of("crash", {"stage": 3}))
	_expect(got == ["first_crash"], "次の激突では激突の記録だけが新しい（%s）" % [got])
	_reset()
	var half := ConfigFile.new()
	for n: int in range(1, Tuning.ACH_BASIC_LAST + 1):
		half.set_value("stage_%02d" % n, "cleared", true)
		half.set_value("stage_%02d" % n, "best_score", 1000)
		half.set_value("stage_%02d" % n, "stars", 1)
	half.save(TEST_SAVE)
	_game_state.load_records()
	_expect(_game_state.stamps().keys() == ["basic"] and _game_state.stats()["completed_on"] == "",
			"第1〜%d試験だけ合格の古い記録では基礎課程修了だけ（%s）" % [Tuning.ACH_BASIC_LAST, _game_state.stamps()])
	return true


# 記録されなかった合格（走行中に記録を消してから、まだ解放されていない試験でゴール）は、初志貫徹・大台に数えない
func _check_unrecorded_clear() -> bool:
	_expect(_game_state.submit_clear(2, Tuning.ACH_BIG_SCORE, 1) == false, "解放されていない第2試験の合格は記録しない")
	var got: Array = _game_state.submit_run(_run_of("clear", {"stage": 2, "score": Tuning.ACH_BIG_SCORE}))
	_expect(not got.has("no_toggle") and not got.has("big_score"), "記録されなかった合格では初志貫徹・大台を取らない（%s）" % [got])
	return true


# --- 道具 ---

## 1回の走行の記録（設計書 2.2）。extra で上書きする
func _run_of(outcome: String, extra: Dictionary) -> Dictionary:
	var r: Dictionary = {"stage": 1, "outcome": outcome, "smashed": {}, "girigiri": 0, "max_combo": 0, "max_speed": 0.0,
			"distance": 0.0, "chained": 0, "toggles": 0, "score": 0}
	r.merge(extra, true)
	return r


func _brief(r: Dictionary) -> String:
	var parts: Array[String] = [r["outcome"]]
	for k: String in ["max_combo", "chained", "girigiri", "max_speed", "toggles", "score"]:
		if r[k] != 0:
			parts.append("%s=%s" % [k, r[k]])
	return " ".join(parts)


func _blank_stats() -> Dictionary:
	return {"runs": 0, "clears": 0, "crashes": 0, "derails": 0,
			"smashed": {"crate": 0, "barrel": 0, "dummy": 0, "drum": 0, "wall": 0},
			"girigiri": 0, "best_speed": 0.0, "best_combo": 0, "distance": 0.0, "attempts": {}, "completed_on": ""}


func _unique(a: Array) -> Array:
	var seen: Dictionary = {}
	for v: Variant in a:
		seen[v] = true
	return seen.keys()


func _straight(objects: Array) -> Dictionary:
	return {
		"id": "check", "name": "check", "ground_y": 900.0, "start_segment": "s0", "star_thresholds": [NO_STAR, NO_STAR + 1],
		"segments": {"s0": {"points": [[0, RAIL_Y], [4000, RAIL_Y]], "end": {"type": "goal"}}},
		"junctions": {}, "objects": objects}


## 分岐が1つ（上下の出口は同じ長さで、どちらもゴール）
func _forked() -> Dictionary:
	return {
		"id": "check", "name": "check", "ground_y": 1200.0, "start_segment": "s0", "star_thresholds": [1, 2],
		"segments": {
			"s0": {"points": [[0, RAIL_Y], [1600, RAIL_Y]], "end": {"type": "junction", "id": "j0"}},
			"a": {"points": [[1600, RAIL_Y], [2000, RAIL_Y - 150], [4400, RAIL_Y - 150]], "end": {"type": "goal"}},
			"b": {"points": [[1600, RAIL_Y], [2000, RAIL_Y + 150], [4400, RAIL_Y + 150]], "end": {"type": "goal"}}},
		"junctions": {"j0": {"branches": ["a", "b"], "default": 0}}, "objects": []}


func _obj(type: String, offset: float) -> Dictionary:
	return {"type": type, "segment": "s0", "offset": offset}


func _new_game(data: Dictionary) -> Node:
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.stage_data = data
	game.auto_pause = false  # 窓が無いのでフォーカスを失った扱いでポーズしないように
	root.add_child(game)
	_games.append(game)
	return game


func _frames(n: int) -> void:
	for _i: int in n:
		await physics_frame


func _frames_until(done: Callable) -> void:
	for _i: int in MAX_FRAMES:
		if done.call():
			return
		await physics_frame


func _remove_test_files() -> void:
	for path: String in [TEST_SETTINGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
