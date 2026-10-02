extends SceneTree
## やりこみ要素の土台の自動確認（設計書 docs/superpowers/specs/2026-09-28-replay-value-design.md の2章・3章・5章・8章・10章）。
## 保存・課題・熟練度・強化・塗装・無限軌道・ゴーストの記録と、検定印、ゲーム画面のつなぎ。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_save.gd （失敗があれば終了コード1）

const GAME_SCENE: String = "res://scenes/game.tscn"
const TEST_SETTINGS: String = "user://checks_save_settings.cfg"
const TEST_SAVE: String = "user://checks_save_save.cfg"
const RAIL_Y: float = 600.0
const MAX_FRAMES: int = 3000

var _failed: int = 0
var _gs: Node  # autoload（-s のスクリプトでは名前で参照できない）
var _games: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	var real_settings: String = _gs.settings_path
	var real_save: String = _gs.save_path
	_gs.settings_path = TEST_SETTINGS
	_gs.save_path = TEST_SAVE
	var checks: Array[Callable] = [_check_numbers, _check_ex_unlock, _check_gold_record, _check_challenges,
			_check_challenge_texts, _check_progression, _check_garage, _check_broken_garage, _check_endless, _check_ghost, _check_locked_trolley_records,
			_check_erase, _check_new_stamps, _check_game_hooks, _check_game_upgrades]
	for check: Callable in checks:
		_reset()
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
		for game: Variant in _games:
			if is_instance_valid(game):
				(game as Node).free()
		_games.clear()
		root.get_node("TimeScale").clear()
	_remove_test_files()
	_gs.settings_path = real_settings
	_gs.save_path = real_save
	_gs.load_settings()
	_gs.load_records()
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
	_gs.load_settings()
	_gs.load_records()
	_gs.current_stage = 1


# --- 番号と見出し（1章） ---

func _check_numbers() -> bool:
	_expect(Display.stage_title(3) == "第3試験" and Display.stage_title(Tuning.EX_FIRST + 1) == "裏試験2",
			"見出し（%s・%s）" % [Display.stage_title(3), Display.stage_title(Tuning.EX_FIRST + 1)])
	var game_script: GDScript = load("res://scenes/game.gd")
	_expect(game_script.stage_number("ex_02") == Tuning.EX_FIRST + 1 and game_script.stage_number("stage_07") == 7,
			"ステージの id から番号（ex_02 → %d）" % game_script.stage_number("ex_02"))
	_expect(_gs.stage_path(Tuning.EX_FIRST) == "res://data/stages/ex_01.json" and _gs.stage_path(2) == "res://data/stages/stage_02.json",
			"ステージのファイル（%s）" % _gs.stage_path(Tuning.EX_FIRST))
	_expect(_gs.stage_key(Tuning.EX_FIRST + 4) == "ex_05", "保存のキー（%s）" % _gs.stage_key(Tuning.EX_FIRST + 4))
	return true


# --- 裏試験の解放（4章） ---

func _check_ex_unlock() -> bool:
	_expect(not _gs.is_unlocked(Tuning.EX_FIRST), "★0 では裏試験1は閉じている")
	for n: int in range(1, 5):  # ★3 × 4 = 12
		_gs.submit_clear(n, 100, 3, Trolleys.DEFAULT)
	_expect(_gs.is_unlocked(Tuning.EX_FIRST) and not _gs.is_unlocked(Tuning.EX_FIRST + 1),
			"★12 で裏試験1だけ開く（閾値 %s）" % [Tuning.EX_UNLOCK_STARS])
	_gs.submit_clear(Tuning.EX_FIRST, 500, 3, Trolleys.DEFAULT)
	_expect(_gs.total_stars() == 12, "裏試験の★は本試験の★の合計に入れない（%d）" % _gs.total_stars())
	_gs.load_records()
	_expect(_gs.record(Tuning.EX_FIRST)["best_score"] == 500, "裏試験の記録を保存して読める")
	_expect(not _gs.is_unlocked(Tuning.EX_FIRST + Tuning.EX_COUNT), "裏試験の後ろの番号は開かない")
	return true


# --- 金★（3.2） ---

func _check_gold_record() -> bool:
	_expect(not Display.gold_for(true, 100, 0) and Display.gold_for(true, 100, 100) and not Display.gold_for(false, 100, 1),
			"金★の判定（閾値 0 は取れない・失敗は取れない）")
	for n: int in range(1, 4):  # 重量型を解放する
		_gs.submit_clear(n, 50, 1, Trolleys.DEFAULT)
	_gs.submit_clear(1, 100, 3, "heavy", true)
	_gs.submit_clear(1, 200, 3, Trolleys.DEFAULT, false)
	_expect(_gs.record(1, "heavy")["gold"] and not _gs.record(1, Trolleys.DEFAULT)["gold"] and _gs.record(1)["gold"],
			"金★は車両ごと、まとめた記録はどれか")
	_gs.submit_clear(1, 300, 3, "heavy", false)
	_expect(_gs.record(1, "heavy")["gold"], "金★は取った後に消えない")
	_gs.load_records()
	_expect(_gs.record(1, "heavy")["gold"], "金★を保存して読める")
	return true


# --- 課題（3.1） ---

func _check_challenges() -> bool:
	var list: Array = [{"type": "score", "value": 1000}, {"type": "kind", "kind": "drum", "value": 2}, {"type": "no_toggle", "value": 0}]
	_expect(Challenges.validate(list).is_empty() and Challenges.validate(null).is_empty(), "課題の検証が通る（無いステージも）")
	_expect(not Challenges.validate([list[0]]).is_empty() and not Challenges.validate([{"type": "x"}, list[1], list[2]]).is_empty()
			and not Challenges.validate([{"type": "kind", "kind": "cat", "value": 1}, list[1], list[2]]).is_empty(),
			"数・種類・標的の種類の違反を見つける")
	var run: Dictionary = _run_of("clear", {"score": 1500, "smashed": {"drum": 1}, "toggles": 2})
	_expect(_gs.submit_challenges(1, list, run) == [0], "得点の課題だけ達成（%s）" % [_gs.challenges(1)])
	run = _run_of("crash", {"score": 1500, "smashed": {"drum": 5}, "toggles": 0})
	_expect(_gs.submit_challenges(1, list, run).is_empty(), "失敗した走行では達成しない")
	run = _run_of("clear", {"score": 0, "smashed": {"drum": 3}, "toggles": 0})
	_expect(_gs.submit_challenges(1, list, run) == [1, 2], "残りの2つ（新しく達成した番号だけ返す）")
	_gs.load_records()
	_expect(_gs.challenges(1) == [true, true, true] and _gs.challenges(2) == [false, false, false], "課題の達成を保存して読める")
	_expect(_gs.submit_challenges(Tuning.EX_FIRST, list, run).is_empty(), "開いていない試験の課題は記録しない")
	var all: Dictionary = {"type": "smash_all", "value": 0}
	_expect(Challenges.achieved(all, _run_of("clear", {"total": 3, "smashed_count": 3}))
			and not Challenges.achieved(all, _run_of("clear", {"total": 3, "smashed_count": 2})), "標的をすべて壊す")
	_expect(Challenges.achieved({"type": "trolley", "trolley": "heavy", "value": 0}, _run_of("clear", {"trolley": "heavy"})),
			"車両の課題")
	return true


func _check_challenge_texts() -> bool:
	var bad: Array[String] = []
	for t: String in Challenges.TYPES:
		var c: Dictionary = {"type": t, "value": 3, "kind": "drum", "trolley": "light"}
		if Challenges.describe(c) == "":
			bad.append(t)
	_expect(bad.is_empty(), "どの種類にも文がある（無い: %s）" % [bad])
	_expect(Challenges.describe({"type": "kind", "kind": "drum", "value": 8}) == "ドラム缶を8個以上爆発させて合格する",
			"文の例（%s）" % Challenges.describe({"type": "kind", "kind": "drum", "value": 8}))
	return true


# --- 熟練度・強化・塗装（5章） ---

func _check_progression() -> bool:
	_expect(Progression.level_for(0) == 1 and Progression.level_for(Tuning.XP_LEVEL_BASE) == 2
			and Progression.level_for(Tuning.XP_LEVEL_BASE - 1) == 1, "段の境目")
	_expect(Progression.level_for(100000000) == Tuning.LEVEL_MAX and Progression.xp_to_next(100000000) == [0, 0], "段の上限")
	_expect(Progression.xp_to_next(Tuning.XP_LEVEL_BASE + 10) == [10, Tuning.XP_LEVEL_BASE + Tuning.XP_LEVEL_STEP],
			"次の段までの経験値（%s）" % [Progression.xp_to_next(Tuning.XP_LEVEL_BASE + 10)])
	var full: Dictionary = {}
	for id: String in Progression.upgrade_ids():
		full[id] = Tuning.UPGRADE_COSTS.size()
	_expect(Progression.points_spent(full) == Tuning.LEVEL_MAX - 1, "最大の段のポイントで全部の強化ができる（%d）" % Progression.points_spent(full))
	_expect(is_equal_approx(Progression.stat("heavy", "hit_power", {"hit_power": 2}), Trolleys.stat("heavy", "hit_power") * 1.1),
			"強化は車両の値に掛ける")
	_expect(is_equal_approx(Progression.stat(Trolleys.DEFAULT, "girigiri_margin", {"girigiri_margin": 1}), 1.2), "ギリギリの幅")
	_expect(Progression.effective_required(Trolleys.DEFAULT, "wall", 1000.0, {}) == 1000.0
			and Progression.effective_required(Trolleys.DEFAULT, "wall", 1000.0, {"wall_factor": 1}) == 970.0
			and Progression.effective_required("heavy", "jump", 700.0, {"jump_factor": 3}) < Trolleys.effective_required("heavy", "jump", 700.0),
			"壁・ジャンプの強化は必要速度を下げる")
	_expect(Progression.xp_for_run({"score": 12345, "outcome": "clear"}) == 123 + Tuning.XP_CLEAR_BONUS
			and Progression.xp_for_run({"score": 999, "outcome": "crash"}) == 9, "走行の経験値")
	_expect(Progression.paints_unlocked(1) == 1 and Progression.paints_unlocked(Tuning.LEVEL_MAX) == Tuning.PAINT_UNLOCK_LEVELS.size(),
			"塗装の数")
	return true


func _check_garage() -> bool:
	for n: int in range(1, 6):  # 軽量型を解放する（解放されていない車両の経験値は標準型に付く）
		_gs.submit_clear(n, 50, 1, Trolleys.DEFAULT)
	var g: Dictionary = _gs.garage("light")
	_expect(g["xp"] == 0 and g["level"] == 1 and g["points_left"] == 0 and g["paint"] == 0, "最初は段1・ポイント0")
	_expect(not _gs.buy_upgrade("light", "hit_power"), "ポイントが無いと強化できない")
	var xp: Dictionary = _gs.add_xp("light", Tuning.XP_LEVEL_BASE + Tuning.XP_LEVEL_BASE + Tuning.XP_LEVEL_STEP)
	_expect(xp == {"gained": 2 * Tuning.XP_LEVEL_BASE + Tuning.XP_LEVEL_STEP, "level_before": 1, "level_after": 3},
			"経験値で段が上がる（%s）" % [xp])
	_expect(_gs.buy_upgrade("light", "wall_factor") and _gs.buy_upgrade("light", "wall_factor"), "2ポイントで2段")
	_expect(not _gs.buy_upgrade("light", "wall_factor") and not _gs.buy_upgrade("light", "speed_max"),
			"足りない・知らない項目は強化しない")
	_expect(is_equal_approx(_gs.stat("light", "wall_factor"), Trolleys.stat("light", "wall_factor") * 0.94), "強化込みの性能")
	_expect(_gs.garage(Trolleys.DEFAULT)["upgrades"].is_empty(), "強化は車両ごと")
	_gs.set_paint("light", 1)
	_expect(_gs.garage("light")["paint"] == 0, "段が足りない塗装は選べない")
	_gs.load_records()
	_expect(_gs.garage("light")["upgrades"] == {"wall_factor": 2} and _gs.garage("light")["level"] == 3, "熟練度と強化を保存して読める")
	_gs.reset_upgrades("light")
	_expect(_gs.garage("light")["points_left"] == 2 and _gs.garage("light")["upgrades"].is_empty(), "振り直しでポイントが戻る")
	return true


func _check_broken_garage() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("garage/heavy", "xp", 10)
	cfg.set_value("garage/heavy", "upgrades", {"hit_power": 3, "nope": 1})
	cfg.set_value("garage/heavy", "paint", 4)
	cfg.set_value("garage/light", "xp", "x")
	cfg.set_value("challenges", "stage_01", [true, 3, false])
	cfg.set_value("challenges", "stage_02", [true, false, true])
	cfg.set_value("endless/blast", "best_score", -5)
	cfg.set_value("stage_01", "cleared", true)
	cfg.set_value("stage_01", "best_score", 10)
	cfg.set_value("stage_01", "stars", 1)
	cfg.save(TEST_SAVE)
	_gs.load_records()
	var g: Dictionary = _gs.garage("heavy")
	_expect(g["upgrades"].is_empty() and g["paint"] == 0 and g["xp"] == 10, "ポイントを超える強化・使えない塗装は戻す（%s）" % [g])
	_expect(_gs.garage("light")["xp"] == 0, "型の違う経験値は0")
	_expect(_gs.challenges(1) == [false, false, false] and _gs.challenges(2) == [true, false, true], "型の違う課題の記録は捨てる")
	_expect(_gs.endless_record("blast")["best_score"] == 0, "負の無限軌道の記録は捨てる")
	_expect(_gs.record(1)["cleared"] and not _gs.record(1)["gold"], "gold の無い古い記録も読める")
	return true


func _check_endless() -> bool:
	for n: int in range(1, 4):  # 重量型を解放する
		_gs.submit_clear(n, 50, 1, Trolleys.DEFAULT)
	_expect(_gs.submit_endless(1000, 5000.0, "heavy"), "最初の無限軌道の記録は更新")
	_expect(not _gs.submit_endless(900, 4000.0, "heavy"), "下回れば更新しない")
	_expect(_gs.submit_endless(800, 9000.0, Trolleys.DEFAULT), "車両ごと・距離だけの更新も更新")
	_gs.load_records()
	_expect(_gs.endless_record("heavy") == {"best_score": 1000, "best_distance": 5000.0}
			and _gs.endless_record() == {"best_score": 1000, "best_distance": 9000.0}, "保存して読め、まとめた記録は最大（%s）" % [_gs.endless_record()])
	return true


func _check_ghost() -> bool:
	var pts := PackedVector3Array([Vector3(0, 600, 0), Vector3(10, 600, 0.1)])
	_expect(_gs.ghost(1).is_empty(), "最初はゴーストが無い")
	_gs.submit_clear(1, 100, 1, Trolleys.DEFAULT)  # 記録のファイルを作る（無いとゴーストのファイルを読まない）
	_expect(_gs.submit_ghost(1, {"score": 100, "trolley": "heavy", "paint": 0, "dt": 0.05, "points": pts}), "ゴーストを残す")
	_expect(not _gs.submit_ghost(1, {"score": 100, "points": pts}), "得点が同じか低ければ残さない")
	_expect(not _gs.submit_ghost(Tuning.EX_FIRST, {"score": 100, "points": pts}), "開いていない試験は残さない")
	_gs.load_records()
	var g: Dictionary = _gs.ghost(1)
	_expect(g.get("score") == 100 and g.get("points") == pts and g.get("trolley") == "heavy", "ゴーストを保存して読める")
	_expect(_gs.ghosts_path() == "user://checks_save_save" + _gs.GHOSTS_SUFFIX, "ゴーストのファイルは記録の隣（%s）" % _gs.ghosts_path())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))  # 記録のファイルだけ消した
	_gs.load_records()
	_expect(_gs.ghost(1).is_empty(), "記録のファイルが無ければ、残っているゴーストのファイルは読まない")
	return true


func _check_locked_trolley_records() -> bool:
	_gs.add_xp("heavy", 500)
	_gs.submit_endless(100, 10.0, "heavy")
	_expect(_gs.garage("heavy")["xp"] == 0 and _gs.endless_record("heavy")["best_score"] == 0
			and _gs.garage(Trolleys.DEFAULT)["xp"] == 500 and _gs.endless_record(Trolleys.DEFAULT)["best_score"] == 100,
			"解放されていない車両の熟練度・無限軌道の記録は標準型に付ける（走行中に記録を消したとき）")
	var cfg := ConfigFile.new()
	cfg.set_value("garage/standard", "xp", 10)
	cfg.set_value("garage/standard", "upgrades", {3: 1, "hit_power": 0})
	cfg.save(TEST_SAVE)
	_gs.load_records()
	_expect(_gs.garage(Trolleys.DEFAULT)["upgrades"] == {"hit_power": 0}, "文字でない強化のキーは捨てる")
	return true


func _check_erase() -> bool:
	_gs.submit_clear(1, 100, 1, Trolleys.DEFAULT, true)
	_gs.submit_challenges(1, [{"type": "score", "value": 0}, {"type": "score", "value": 0}, {"type": "score", "value": 0}],
			_run_of("clear", {}))
	_gs.add_xp("heavy", 5000)
	_gs.submit_endless(1, 1.0, "heavy")
	_gs.submit_ghost(1, {"score": 1, "points": PackedVector3Array()})
	_gs.erase_records()
	_expect(not _gs.record(1)["gold"] and _gs.challenges(1) == [false, false, false] and _gs.garage("heavy")["xp"] == 0
			and _gs.endless_record()["best_score"] == 0 and _gs.ghost(1).is_empty()
			and not FileAccess.file_exists(_gs.ghosts_path()), "記録の消去はやりこみの記録とゴーストも消す")
	return true


# --- 検定印（8章） ---

func _check_new_stamps() -> bool:
	_expect(Achievements.LIST.size() == 30, "検定印は30個（%d）" % Achievements.LIST.size())
	var bad: Array[String] = []
	for a: Array in Achievements.LIST:
		if Achievements.describe(a[0]).contains("{"):
			bad.append(a[0])
	_expect(bad.is_empty(), "条件の文に数値が入る（%s）" % [bad])
	for n: int in range(1, 6):  # 軽量型を解放する
		_gs.submit_clear(n, 50, 1, Trolleys.DEFAULT)
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		_gs.submit_clear(n, 100, 3, "light", n == 1)
	_gs.add_xp("light", 100000000)
	var got: Array[String] = _gs.submit_run(_run_of("abort", {"stage": 1}))
	for id: String in ["license_light", "gold_first", "level10", "level_max"]:
		_expect(got.has(id), "%s を取る（%s）" % [id, got])
	_expect(not got.has("license_heavy") and not got.has("gold_all") and not got.has("ex_first"), "条件を満たさない印は取らない")
	_gs.submit_endless(0, Tuning.ACH_ENDLESS_DISTANCE, "light")
	got = _gs.submit_run(_run_of("crash", {"stage": 0, "distance": Tuning.ACH_ENDLESS_DISTANCE}))
	_expect(got.has("endless_5km") and _gs.stats()["attempts"].get(0) == null, "無限軌道の5km・試験ごとの回数に入れない（%s）" % [got])
	for n: int in range(Tuning.EX_FIRST, Tuning.EX_FIRST + Tuning.EX_COUNT):
		_gs.submit_clear(n, 100, 1, "light")
	var ten: Array = [{"type": "score", "value": 0}, {"type": "score", "value": 0}, {"type": "score", "value": 0}]
	for n: int in range(1, 5):
		_gs.submit_challenges(n, ten, _run_of("clear", {"stage": n}))
	got = _gs.submit_run(_run_of("abort", {"stage": 1}))
	_expect(got.has("ex_first") and got.has("ex_all") and got.has("challenge10") and not got.has("challenge_all"),
			"裏試験・課題の印（%s）" % [got])
	var clear_ex: Dictionary = _run_of("clear", {"stage": Tuning.EX_FIRST, "score": Tuning.ACH_BIG_SCORE})
	got = _gs.submit_run(clear_ex)
	_expect(got.has("big_score"), "裏試験の合格でも「大台」を取る（%s）" % [got])
	return true


# --- ゲーム画面のつなぎ（10章） ---

func _check_game_hooks() -> bool:
	var data: Dictionary = _straight([_obj("crate", 600), _obj("crate", 900)])
	data["gold_threshold"] = 1
	data["challenges"] = [{"type": "score", "value": 1}, {"type": "no_toggle", "value": 0}, {"type": "score", "value": 900000}]
	var game: Node = _new_game(data)
	await _frames_until(func() -> bool: return game._result != null)
	var r: Dictionary = game.result_data()
	_expect(r.get("gold") == true and r.get("title") == "第1試験", "リザルトに金★と見出し（%s・%s）" % [r.get("gold"), r.get("title")])
	var rows: Array = r.get("challenges", [])
	_expect(rows.size() == 3 and rows[0]["done"] and rows[0]["new"] and rows[1]["new"] and not rows[2]["done"]
			and rows[2]["text"] != "", "リザルトの課題の行（%s）" % [rows])
	_expect(_gs.record(1)["gold"] and _gs.challenges(1) == [true, true, false], "金★と課題を記録する")
	var xp: Dictionary = r.get("xp", {})
	_expect(xp.get("gained", 0) == game.score / Tuning.XP_SCORE_DIV + Tuning.XP_CLEAR_BONUS
			and _gs.garage(Trolleys.DEFAULT)["xp"] == xp["gained"], "熟練度が入る（%s）" % [xp])
	var ghost: Dictionary = _gs.ghost(1)
	_expect(ghost.get("score") == game.score and ghost.get("trolley") == Trolleys.DEFAULT, "合格でゴーストを残す（%s）" % [ghost.get("score")])
	# 2回目はゴーストを出す
	var game2: Node = _new_game(data)
	await _frames(2)
	_expect(game2._ghost != null, "ゴーストがあれば重ねる")
	_gs.set_show_ghost(false)
	var game3: Node = _new_game(data)
	await _frames(2)
	_expect(game3._ghost == null, "設定が非表示なら出さない")
	_gs.load_settings()
	_expect(not _gs.show_ghost, "ゴーストの設定を保存して読める")
	return true


func _check_game_upgrades() -> bool:
	_gs.add_xp(Trolleys.DEFAULT, 100000000)
	for i: int in 3:
		_gs.buy_upgrade(Trolleys.DEFAULT, "wall_factor")
		_gs.buy_upgrade(Trolleys.DEFAULT, "combo_window")
	var data: Dictionary = _straight([{"type": "wall", "segment": "s0", "offset": 2000, "required_speed": 600.0}])
	var game: Node = _new_game(data)
	await _frames(2)
	var wall: Target = null
	for t: Target in game._targets:
		if t.kind == "wall":
			wall = t
	_expect(wall != null and is_equal_approx(wall.required_speed, 550.0), "壁の必要速度は強化込み（%s）" % [wall.required_speed if wall else -1])
	_expect(is_equal_approx(game.combo_window(), Tuning.COMBO_WINDOW * 1.15), "コンボの受付は強化込み（%.3f）" % game.combo_window())
	return true


# --- 道具 ---

func _run_of(outcome: String, extra: Dictionary) -> Dictionary:
	var r: Dictionary = {"stage": 1, "outcome": outcome, "smashed": {}, "girigiri": 0, "max_combo": 0, "max_speed": 0.0,
			"distance": 0.0, "chained": 0, "toggles": 0, "score": 0, "trolley": Trolleys.DEFAULT, "total": 0, "smashed_count": 0}
	r.merge(extra, true)
	return r


func _straight(objects: Array) -> Dictionary:
	return {
		"id": "check", "name": "check", "ground_y": 900.0, "start_segment": "s0", "star_thresholds": [900000, 900001],
		"segments": {"s0": {"points": [[0, RAIL_Y], [4000, RAIL_Y]], "end": {"type": "goal"}}},
		"junctions": {}, "objects": objects}


func _obj(type: String, offset: float) -> Dictionary:
	return {"type": type, "segment": "s0", "offset": offset}


func _new_game(data: Dictionary) -> Node:
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.stage_data = data.duplicate(true)
	game.auto_pause = false
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
	for path: String in [TEST_SETTINGS, TEST_SAVE, _gs.ghosts_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
