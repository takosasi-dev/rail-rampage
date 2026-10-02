extends SceneTree
## 車両（トロッコの種類）と画面の設定のデータの自動確認
## （設計書 docs/superpowers/specs/2026-09-26-trolleys-and-display-design.md の1・2・4章）。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_options.gd （失敗があれば終了コード1）
## 設定・記録は確認用のファイルに差し替え、最後に消す。

const GAME_SCENE: String = "res://scenes/game.tscn"
const TEST_SETTINGS: String = "user://checks_options_settings.cfg"
const TEST_SAVE: String = "user://checks_options_save.cfg"
const RAIL_Y: float = 600.0
const MAX_FRAMES: int = 3000
const TROLLEY_COUNT: int = 5  # 設計書1章の車両の数
const STAT_KEYS: Array[String] = ["speed_base", "speed_max", "momentum_gain", "momentum_decay", "wall_factor", "jump_factor",
		"hit_power", "blast_radius", "combo_window", "star_scale"]
const WALL_REQUIRED: float = 700.0
const NO_STAR: int = 900000

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
	var checks: Array[Callable] = [_check_display_defaults, _check_display_save, _check_display_broken, _check_trolley_list,
			_check_unlock, _check_current_trolley, _check_records_per_trolley, _check_old_records, _check_game_stats,
			_check_game_required, _check_game_blast, _check_game_records, _check_game_new_trolleys, _check_star_scale,
			_check_locked_clear, _check_required_unscaled]
	for check: Callable in checks:
		_reset()
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
		for game: Variant in _games:  # 型を付けると、解放済みのゲームを受けたときに止まる
			if is_instance_valid(game):
				(game as Node).free()
		_games.clear()
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


# --- 画面の設定（設計書4章） ---

func _check_display_defaults() -> bool:
	_expect(_game_state.quality == "high" and _game_state.max_fps == 0 and _game_state.vsync == true
			and _game_state.show_fps == false, "設定が無いときは 画質 高・FPS 上限なし・垂直同期 ON・FPS 表示 OFF（今までと同じ動き）")
	_expect(Tuning.QUALITY_LEVELS == ["high", "medium", "low"] and Tuning.FPS_LIMITS.has(0) and Tuning.FPS_LIMITS.has(60),
			"画質は高・中・低、FPS 上限の選択肢に「上限なし（0）」と 60 がある（%s）" % [Tuning.FPS_LIMITS])
	return true


func _check_display_save() -> bool:
	var changed: Array[int] = [0]
	_game_state.display_changed.connect(func() -> void: changed[0] += 1)
	_game_state.set_quality("low")
	_game_state.set_max_fps(30)
	_game_state.set_vsync(false)
	_game_state.set_show_fps(true)
	_expect(changed[0] == 4, "画面の設定を変えるたびに display_changed を出す（%d 回）" % changed[0])
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	_expect(cfg.get_value("settings", "quality", "") == "low" and cfg.get_value("settings", "max_fps", -1) == 30
			and cfg.get_value("settings", "vsync", true) == false and cfg.get_value("settings", "show_fps", false) == true,
			"画面の設定は変えた瞬間に settings.cfg に保存する")
	_game_state.load_settings()
	_expect(_game_state.quality == "low" and _game_state.max_fps == 30 and _game_state.vsync == false and _game_state.show_fps,
			"読み直しても同じ")
	_game_state.set_quality("ultra")
	_game_state.set_max_fps(45)
	_expect(_game_state.quality == "high" and _game_state.max_fps == 0, "知らない画質・選択肢に無い FPS 上限は初期値（%s・%d）" % [
			_game_state.quality, _game_state.max_fps])
	for c: Dictionary in _game_state.display_changed.get_connections():
		_game_state.display_changed.disconnect(c["callable"])
	return true


func _check_display_broken() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "quality", 3)
	cfg.set_value("settings", "max_fps", "60")
	cfg.set_value("settings", "vsync", "no")
	cfg.set_value("settings", "show_fps", 1)
	cfg.save(TEST_SETTINGS)
	_game_state.load_settings()
	_expect(_game_state.quality == "high" and _game_state.max_fps == 0 and _game_state.vsync == true
			and _game_state.show_fps == false, "型が違う画面の設定は初期値")
	return true


# --- 車両のデータ（設計書1・2章） ---

func _check_trolley_list() -> bool:
	_expect(Trolleys.IDS.size() == TROLLEY_COUNT and Trolleys.IDS[0] == Trolleys.DEFAULT and Trolleys.DEFAULT == "standard",
			"車両は %d 種で、最初が標準型（%s）" % [TROLLEY_COUNT, Trolleys.IDS])
	var missing: Array = []
	for id: String in Trolleys.IDS:
		if Trolleys.name_of(id) == "":
			missing.append("%s の名前" % id)
		for key: String in STAT_KEYS:
			if not (Tuning.TROLLEY_STATS.get(id, {}) as Dictionary).has(key):
				missing.append("%s.%s" % [id, key])
		if id != Trolleys.DEFAULT and (Trolleys.pros_of(id) == "" or Trolleys.cons_of(id) == ""):
			missing.append("%s の長所と短所" % id)
	_expect(missing.is_empty(), "どの車両にも名前・性能の値がそろい、標準型以外は長所と短所がある（無い %s）" % [missing])
	var std: Dictionary = Tuning.TROLLEY_STATS[Trolleys.DEFAULT]
	var ones: bool = STAT_KEYS.filter(func(k: String) -> bool: return not k.begins_with("speed_")).all(
			func(k: String) -> bool: return std[k] == 1.0)
	_expect(std["speed_base"] == Tuning.SPEED_BASE and std["speed_max"] == Tuning.SPEED_MAX and ones,
			"標準型の性能は今までの値（倍率はすべて1）")
	# 目標速度は「初速＋勢い×SPEED_PER_MOMENTUM」で、勢いは MOMENTUM_MAX まで。それより大きい最高速は出ない
	var unreachable: Array = Trolleys.IDS.filter(func(id: String) -> bool:
		return Trolleys.stat(id, "speed_max") > Trolleys.stat(id, "speed_base") + Tuning.MOMENTUM_MAX * Tuning.SPEED_PER_MOMENTUM)
	_expect(unreachable.is_empty(), "どの車両も最高速は「初速＋勢いの上限×SPEED_PER_MOMENTUM」以下（出せない最高速 %s）" % [unreachable])
	return true


func _check_unlock() -> bool:
	_expect(_game_state.unlocked_trolleys() == [Trolleys.DEFAULT], "記録が無いときは標準型だけ（%s）" % [_game_state.unlocked_trolleys()])
	var heavy_stage: int = Tuning.TROLLEY_UNLOCK["heavy"]["stage"]
	for n: int in range(1, heavy_stage):
		_game_state.submit_clear(n, 100, 1)
	_expect(not _game_state.is_trolley_unlocked("heavy"), "第%d試験の前までの合格では重量型はまだ" % heavy_stage)
	_game_state.submit_clear(heavy_stage, 100, 1)
	_expect(_game_state.is_trolley_unlocked("heavy"), "第%d試験に合格すると重量型" % heavy_stage)
	_expect(Trolleys.unlock_text("heavy") == "第%d試験の合格で解放" % heavy_stage, "解放の条件の文（%s）" % Trolleys.unlock_text("heavy"))
	var stamp: String = Tuning.TROLLEY_UNLOCK["blast"]["stamp"]
	_expect(Trolleys.unlock_text("blast") == "検定印「%s」で解放" % Achievements.name_of(stamp), "検定印の条件の文（%s）" % Trolleys.unlock_text("blast"))
	_expect(not _game_state.is_trolley_unlocked("blast"), "検定印「%s」の前は発破型はまだ" % Achievements.name_of(stamp))
	_game_state.submit_run(_run_of("crash", {"chained": Tuning.ACH_CHAIN}))
	_expect(_game_state.stamps().has(stamp) and _game_state.is_trolley_unlocked("blast"), "検定印を取ると発破型")
	return true


func _check_current_trolley() -> bool:
	_expect(_game_state.trolley() == Trolleys.DEFAULT, "初めは標準型")
	_game_state.set_trolley("heavy")
	_expect(_game_state.trolley() == Trolleys.DEFAULT, "解放されていない車両は選べない")
	for n: int in range(1, Tuning.TROLLEY_UNLOCK["heavy"]["stage"] + 1):
		_game_state.submit_clear(n, 100, 1)
	_game_state.set_trolley("heavy")
	_expect(_game_state.trolley() == "heavy", "解放された車両は選べる")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	_expect(cfg.get_value("settings", "trolley", "") == "heavy", "選んだ車両は settings.cfg に保存する")
	_game_state.load_settings()
	_game_state.load_records()
	_expect(_game_state.trolley() == "heavy", "起動し直しても同じ車両")
	_game_state.erase_records()
	_expect(_game_state.trolley() == Trolleys.DEFAULT, "記録を消して解放されていない車両になったら標準型")
	for n: int in range(1, Tuning.TROLLEY_UNLOCK["heavy"]["stage"] + 1):
		_game_state.submit_clear(n, 100, 1, Trolleys.DEFAULT)
	_expect(_game_state.trolley() == Trolleys.DEFAULT, "消した後に解放し直しても、選び直すまで標準型のまま（レビューの指摘）")
	_game_state.set_trolley("nope")
	_expect(_game_state.trolley() == Trolleys.DEFAULT, "知らない車両は標準型")
	# save.cfg が無くなった（壊れた）ときも、設定に残った車両に黙って戻らない
	_game_state.set_trolley("heavy")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	_game_state.load_settings()
	_game_state.load_records()
	for n: int in range(1, Tuning.TROLLEY_UNLOCK["heavy"]["stage"] + 1):
		_game_state.submit_clear(n, 100, 1, Trolleys.DEFAULT)
	_expect(_game_state.trolley() == Trolleys.DEFAULT, "記録が読めずに解放が外れた車両は、読んだ時点で標準型に戻す")
	return true


# 走行中に記録を消して、選んでいた車両が解放されていない状態でゴールしたら、その記録は標準型に付ける（レビューの指摘）
func _check_locked_clear() -> bool:
	_game_state.submit_clear(1, 100, 1, "heavy")
	_expect(not _game_state.record(1, "heavy")["cleared"] and _game_state.record(1, Trolleys.DEFAULT)["cleared"],
			"解放されていない車両の合格は標準型の記録にする")
	return true


func _check_records_per_trolley() -> bool:
	# 重量型と軽量型を解放する（標準型で第1〜5試験に 0点・★0 で合格。★の合計に数えない）
	for n: int in range(1, Tuning.TROLLEY_UNLOCK["light"]["stage"] + 1):
		_game_state.submit_clear(n, 0, 0, Trolleys.DEFAULT)
	_game_state.submit_clear(1, 500, 2, "heavy")
	_game_state.submit_clear(1, 300, 3, "standard")
	var heavy: Dictionary = _game_state.record(1, "heavy")
	var std: Dictionary = _game_state.record(1, "standard")
	var merged: Dictionary = _game_state.record(1)
	_expect(heavy == {"cleared": true, "best_score": 500, "stars": 2, "gold": false} and std == {"cleared": true, "best_score": 300, "stars": 3, "gold": false},
			"試験の記録は車両ごと（%s・%s）" % [heavy, std])
	_expect(merged == {"cleared": true, "best_score": 500, "stars": 3, "gold": false}, "車両を指定しない記録は全車両をまとめた値（%s）" % merged)
	_expect(_game_state.record(1, "light")["cleared"] == false, "走っていない車両は未合格")
	_expect(_game_state.submit_clear(1, 400, 1, "heavy") == false and _game_state.submit_clear(1, 600, 1, "heavy") == true,
			"最高記録の更新は車両ごとに判定する")
	_game_state.submit_clear(2, 100, 1, "light")
	_expect(_game_state.is_unlocked(3), "試験の解放はどれかの車両の合格で決まる")
	_expect(_game_state.total_stars("heavy") == 2 and _game_state.total_stars("light") == 1 and _game_state.total_stars() == 4,
			"★の合計は車両ごと、指定しなければ試験ごとの最大の合計（%d・%d・%d）" % [_game_state.total_stars("heavy"),
				_game_state.total_stars("light"), _game_state.total_stars()])
	_game_state.load_records()
	_expect(_game_state.record(1, "heavy")["best_score"] == 600 and _game_state.record(2, "light")["cleared"],
			"車両ごとの記録は save.cfg に残る")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SAVE)
	_expect(cfg.has_section("stage_01") and cfg.has_section("stage_01/heavy") and cfg.has_section("stage_02/light"),
			"標準型は [stage_01]、ほかは [stage_01/heavy] のように保存する（%s）" % [cfg.get_sections()])
	return true


func _check_old_records() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("stage_01", "cleared", true)
	cfg.set_value("stage_01", "best_score", 700)
	cfg.set_value("stage_01", "stars", 2)
	cfg.set_value("stage_02/nope", "cleared", true)
	cfg.set_value("stage_02/nope", "best_score", 1)
	cfg.set_value("stage_02/nope", "stars", 1)
	cfg.save(TEST_SAVE)
	_game_state.load_records()
	_expect(_game_state.record(1, "standard") == {"cleared": true, "best_score": 700, "stars": 2, "gold": false},
			"今までの記録（[stage_01]）は標準型の記録として読む")
	_expect(not _game_state.record(2)["cleared"], "知らない車両の記録は読まない")
	return true


# --- ゲームが車両の性能を使う（設計書1章） ---

func _check_game_stats() -> bool:
	_unlock_all()
	for id: String in ["heavy", "light"]:
		_game_state.set_trolley(id)
		var s: Dictionary = Tuning.TROLLEY_STATS[id]
		var game: Node = _new_game(_straight([_obj("barrel", 900)]))
		_expect(is_equal_approx(game._trolley.speed, s["speed_base"]), "%s: 初速は speed_base（%.0f）" % [id, game._trolley.speed])
		await _frames(5)
		var target: float = minf(s["speed_base"] + game.momentum * Tuning.SPEED_PER_MOMENTUM, s["speed_max"])
		_expect(absf(game.target_speed() - target) < 0.01, "%s: 目標速度は speed_base ＋勢い×SPEED_PER_MOMENTUM（上限 speed_max）" % id)
		var barrel: Target = game._targets[0]
		await _frames_until(func() -> bool: return barrel.smashed)
		var gained: float = Tuning.TARGET_MOMENTUM["barrel"] * s["momentum_gain"]
		_expect(absf(game.momentum - gained) < Tuning.MOMENTUM_DECAY * s["momentum_decay"] / 30.0,
				"%s: 壊したときの勢いは種類の値×momentum_gain（%.2f / %.2f）" % [id, game.momentum, gained])
		var m0: float = game.momentum
		await _frames(30)
		_expect(absf((m0 - game.momentum) - Tuning.MOMENTUM_DECAY * s["momentum_decay"] * 0.5) < 0.5,
				"%s: 勢いは毎秒 MOMENTUM_DECAY×momentum_decay 減る（0.5秒で %.2f）" % [id, m0 - game.momentum])
		var hit: float = (Tuning.HIT_BASE + game._trolley.speed * Tuning.HIT_SPEED_FACTOR) * s["hit_power"]
		_expect(absf(game._hit_impulse(Vector2.ZERO).length() - hit) < 0.01, "%s: 吹っ飛ばす力は FR-14 の大きさ×hit_power" % id)
		_expect(absf(game.combo_window() - Tuning.COMBO_WINDOW * s["combo_window"]) < 0.001, "%s: コンボの受付は COMBO_WINDOW×combo_window" % id)
		game.free()
		_games.erase(game)
	return true


func _check_game_required() -> bool:
	_unlock_all()
	_game_state.set_trolley("heavy")
	var wall: Dictionary = _obj("wall", 1400)
	wall["required_speed"] = WALL_REQUIRED
	var data: Dictionary = _straight([wall])
	data["segments"] = {
		"s0": {"points": [[0, RAIL_Y], [1000, RAIL_Y]], "end": {"type": "next", "segment": "j"}},
		"j": {"points": [[1000, RAIL_Y], [1200, RAIL_Y - 100], [1400, RAIL_Y]], "end": {"type": "next", "segment": "s1"},
				"jump": {"required_speed": WALL_REQUIRED}},
		"s1": {"points": [[1400, RAIL_Y], [5000, RAIL_Y]], "end": {"type": "goal"}}}
	wall["segment"] = "s1"
	var game: Node = _new_game(data)
	var want_wall: float = Trolleys.effective_required("heavy", "wall", WALL_REQUIRED)
	var want_jump: float = Trolleys.effective_required("heavy", "jump", WALL_REQUIRED)
	var s: Dictionary = Tuning.TROLLEY_STATS["heavy"]
	_expect(is_equal_approx(want_wall, snappedf(WALL_REQUIRED * s["wall_factor"], Tuning.DISPLAY_SPEED_DIV))
			and is_equal_approx(want_jump, snappedf(WALL_REQUIRED * s["jump_factor"], Tuning.DISPLAY_SPEED_DIV)),
			"必要速度はステージの値×倍率を 1km/h 単位に丸めた値（壁 %.0f・ジャンプ %.0f）" % [want_wall, want_jump])
	var wall_t: Target = game._targets[0]
	_expect(is_equal_approx(wall_t.required_speed, want_wall), "重量型: 壁の必要速度は換算した値（%.0f）" % wall_t.required_speed)
	var signs: Array = _find_all(game, SpeedSign)
	var by_kind: Dictionary = {}
	for sg: SpeedSign in signs:
		by_kind[sg.kind] = sg.required_speed
	_expect(is_equal_approx(by_kind.get("wall", -1.0), want_wall) and is_equal_approx(by_kind.get("jump", -1.0), want_jump),
			"標識もその車両の必要速度を出す（%s）" % by_kind)
	# 換算した必要速度で判定する: ジャンプの必要速度ちょうどで通過、壁の必要速度の1つ下で激突
	game._trolley.fixed_speed = want_jump
	await _frames_until(func() -> bool: return game._last_segment == "s1" or game._finished)
	_expect(game.fail_reason == "", "重量型: 換算したジャンプの必要速度（%.0f）ちょうどなら通過" % want_jump)
	game._trolley.fixed_speed = want_wall - 1.0
	await _frames_until(func() -> bool: return game._finished)
	_expect(game.fail_reason == "激突" and is_equal_approx(game.result_data()["required_speed"], want_wall),
			"重量型: 換算した壁の必要速度の1つ下で激突し、リザルトの必要速度も換算した値（%s）" % game.result_data()["required_speed"])
	return true


func _check_game_blast() -> bool:
	_unlock_all()
	_game_state.set_trolley("blast")
	var game: Node = _new_game(_straight([]))
	var r: float = Tuning.EXPLOSION_RADIUS * Tuning.TROLLEY_STATS["blast"]["blast_radius"]
	_expect(is_equal_approx(game.blast_radius(), r), "発破型: 爆発の範囲は EXPLOSION_RADIUS×blast_radius（%.0f）" % game.blast_radius())
	var inside: Vector2 = Vector2(0.0, -(r - 1.0))
	_expect(game._explosion_impulse(Vector2.ZERO, inside).length() > 0.0
			and game._explosion_impulse(Vector2.ZERO, Vector2(0.0, -(r + 1.0))).length() == 0.0,
			"爆発の衝撃は換算した範囲の端で0になる")
	return true


func _check_game_records() -> bool:
	_unlock_all()
	_game_state.set_trolley("light")
	var game: Node = _new_game(_straight([_obj("crate", 600)]))
	await _frames_until(func() -> bool: return game._result != null)
	var data: Dictionary = game.result_data()
	_expect(data["trolley"] == "light" and _game_state.record(1, "light")["cleared"] and _game_state.record(1, "light")["best_score"] == game.score,
			"ゴールの記録は選んでいる車両の記録になり、リザルトのデータに車両が入る（%s）" % data["trolley"])
	return true


func _check_game_new_trolleys() -> bool:
	var heavy_stage: int = Tuning.TROLLEY_UNLOCK["heavy"]["stage"]
	for n: int in range(1, heavy_stage):
		_game_state.submit_clear(n, 100, 1)
	var data: Dictionary = _straight([])
	data["id"] = "stage_%02d" % heavy_stage
	var game: Node = _new_game(data)
	await _frames_until(func() -> bool: return game._result != null)
	_expect(game.result_data()["new_trolleys"] == ["heavy"], "第%d試験に初めて合格すると、リザルトのデータの new_trolleys に重量型（%s）" % [
			heavy_stage, game.result_data()["new_trolleys"]])
	return true


func _check_star_scale() -> bool:
	_expect(Trolleys.IDS.all(func(id: String) -> bool:
			var k: float = Tuning.TROLLEY_STATS[id]["star_scale"]
			return k > 0.0 and k <= 1.0), "star_scale は 0 より大きく 1 以下（閾値を下げる向きだけ）")
	var t: Array = Trolleys.thresholds("standard", [1000, 2000])
	_expect(t == [1000, 2000], "標準型の★の閾値はステージの値のまま（%s）" % [t])
	return true


# 倍率1（標準型）の必要速度は丸めない（ステージの値が 10 の倍数でなくても今までと同じ。レビューの指摘）
func _check_required_unscaled() -> bool:
	_expect(Trolleys.effective_required(Trolleys.DEFAULT, "wall", 703.0) == 703.0
			and Trolleys.effective_required(Trolleys.DEFAULT, "jump", 1037.0) == 1037.0, "標準型の必要速度はステージの値のまま")
	return true


# --- 道具 ---

func _unlock_all() -> void:
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		_game_state.submit_clear(n, 1, 1)
	for id: String in Trolleys.IDS:
		var u: Dictionary = Tuning.TROLLEY_UNLOCK.get(id, {})
		if u.has("stamp"):
			_game_state._stamps[u["stamp"]] = "2026-09-26"


func _run_of(outcome: String, extra: Dictionary) -> Dictionary:
	var r: Dictionary = {"stage": 1, "outcome": outcome, "smashed": {}, "girigiri": 0, "max_combo": 0, "max_speed": 0.0,
			"distance": 0.0, "chained": 0, "toggles": 0, "score": 0}
	r.merge(extra, true)
	return r


func _find_all(node: Node, type: Variant) -> Array:
	var out: Array = []
	for c: Node in node.get_children():
		if is_instance_of(c, type):
			out.append(c)
		out.append_array(_find_all(c, type))
	return out


func _straight(objects: Array) -> Dictionary:
	return {
		"id": "check", "name": "check", "ground_y": 900.0, "start_segment": "s0", "star_thresholds": [NO_STAR, NO_STAR + 1],
		"segments": {"s0": {"points": [[0, RAIL_Y], [4000, RAIL_Y]], "end": {"type": "goal"}}},
		"junctions": {}, "objects": objects}


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
