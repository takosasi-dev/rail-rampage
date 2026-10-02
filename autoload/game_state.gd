extends Node
## 設定（FR-47b, FR-50a）、選んでいるステージ、ステージごとの記録（FR-48〜50）。autoload。
## 車両ごとの記録・選んでいる車両・画面の設定（trolleys-and-display-design.md）もここ

signal display_changed  # 画面の設定（画質・FPS 上限・垂直同期・全画面・FPS 表示）が変わった

const SETTINGS_PATH: String = "user://settings.cfg"
const SAVE_PATH: String = "user://save.cfg"
const SECTION: String = "settings"
const STAGE_PATH_FORMAT: String = "res://data/stages/stage_%02d.json"
const STAGE_KEY_FORMAT: String = "stage_%02d"  # save.cfg のセクション名。ステージ JSON の id と同じ
## やりこみ要素（設計書 docs/superpowers/specs/2026-09-28-replay-value-design.md の2章）
const EX_PATH_FORMAT: String = "res://data/stages/ex_%02d.json"
const EX_KEY_FORMAT: String = "ex_%02d"  # 裏試験の記録のセクション名。ステージ JSON の id と同じ
const CHALLENGES_SECTION: String = "challenges"
const GARAGE_KEY_FORMAT: String = "garage/%s"
const ENDLESS_SECTION: String = "endless"
const GHOSTS_SUFFIX: String = "_ghosts.cfg"  # ゴーストのファイル: 記録のファイルの名前 + これ（user://save_ghosts.cfg）
const GHOST_KEY: String = "data"
const TROLLEY_KEY_FORMAT: String = "%s/%s"  # 標準型以外の車両の記録のセクション名（"stage_01/heavy"）
## 試験記録（累計）と検定印の save.cfg のセクション（設計書 docs/superpowers/specs/2026-09-26-records-design.md の 2.1）
const STATS_SECTION: String = "stats"
const STAMPS_SECTION: String = "stamps"
const STAT_COUNTS: Array[String] = ["runs", "clears", "crashes", "derails", "girigiri", "best_combo"]  # 0以上の整数
const STAT_AMOUNTS: Array[String] = ["best_speed", "distance"]  # 0以上の数
const SMASH_KINDS: Array[String] = ["crate", "barrel", "dummy", "drum", "wall"]  # 累計で数える標的（レンガ片は数えない）
## 走行の結果（設計書 2.2 の outcome）→ 数える累計のキー
const OUTCOME_COUNTS: Dictionary = {"clear": "clears", "crash": "crashes", "derail": "derails"}

## 自動確認は別のファイルに差し替える（遊んでいる人の設定・記録を上書きしない）
var settings_path: String = SETTINGS_PATH
var save_path: String = SAVE_PATH
var se_volume: int = Tuning.SE_VOLUME_DEFAULT  # 0〜100
var screen_shake: bool = true
var time_of_day_mode: String = TimeOfDay.MODE_SEQUENCE  # 設計書4章: A「順に進む」か C「見どころに合わせる」
## 全画面（records-design.md 4章。F11 で切り替え、次に起動したときも戻す）。Web 版では使わない（ブラウザの F11 に任せる）
var fullscreen: bool = false
## 画面の設定（trolleys-and-display-design.md 4章）
var quality: String = Tuning.QUALITY_LEVELS[0]  # 画質（ゲーム画面を作るときに読む）
var max_fps: int = Tuning.FPS_LIMIT_DEFAULT  # 0 は上限なし
var vsync: bool = true
var show_fps: bool = false
var show_ghost: bool = true  # ゴーストを出す（replay-value-design.md 6章。settings.cfg）
## 選んでいる車両（settings.cfg に保存）。解放されていなければ trolley() は標準型を返す
var current_trolley: String = Trolleys.DEFAULT
## 遊ぶステージの番号（1〜STAGE_COUNT）。ステージ選択・リザルトの「次の試験へ」が決め、ゲーム画面が読む。保存しない
var current_stage: int = 1
var endless: bool = false  # 無限軌道を遊ぶ（replay-value-design.md 7章。タイトルが true にしてゲーム画面が読み、タイトルに戻ると false。保存しない）

var _records: Dictionary = {}  # 車両 id → {ステージ番号 → {"cleared": bool, "best_score": int, "stars": int}}
var _stats: Dictionary = _blank_stats()  # 試験記録の累計（設計書 2.1）
var _stamps: Dictionary = {}  # 検定印の id → 取った日（"2026-09-26"）
var _challenges: Dictionary = {}  # 試験番号 → 課題の達成（bool × CHALLENGE_COUNT）
var _garage: Dictionary = {}  # 車両 id → {"xp": int, "upgrades": {項目 id: 段}, "paint": int}
var _endless: Dictionary = {}  # 車両 id → {"best_score": int, "best_distance": float}
var _ghosts: Variant = null  # 試験番号 → ゴーストの辞書。null はまだ読んでいない（大きいので必要になったときに読む）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # ポーズ中も F11 を受ける
	load_settings()
	load_records()


## F11: 今の窓が全画面かどうかから切り替える（最大化などほかの手段で窓が変わっていても1回で効く）。Web 版は何もしない
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen") and not OS.has_feature("web"):
		get_viewport().set_input_as_handled()
		set_fullscreen(not _window_is_fullscreen())


## 窓が全画面か。窓の無い headless（自動確認）では設定の値
func _window_is_fullscreen() -> bool:
	if DisplayServer.get_name() == "headless":
		return fullscreen
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## FR-50a: 読めない・型が違う・範囲外の値は初期値（音量 SE_VOLUME_DEFAULT、揺れ ON、時間帯 A）にする
func load_settings() -> void:
	se_volume = Tuning.SE_VOLUME_DEFAULT
	screen_shake = true
	time_of_day_mode = TimeOfDay.MODE_SEQUENCE
	fullscreen = false
	quality = Tuning.QUALITY_LEVELS[0]
	max_fps = Tuning.FPS_LIMIT_DEFAULT
	vsync = true
	show_fps = false
	show_ghost = true
	current_trolley = Trolleys.DEFAULT
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		# 既定値に null を渡すと、キーが無いときに Godot がエラーを出す（null は「既定値なし」の意味）
		var v: Variant = cfg.get_value(SECTION, "se_volume", se_volume)
		if v is int and v >= 0 and v <= Tuning.SE_VOLUME_MAX:
			se_volume = v
		var s: Variant = cfg.get_value(SECTION, "screen_shake", screen_shake)
		if s is bool:
			screen_shake = s
		var m: Variant = cfg.get_value(SECTION, "time_of_day_mode", time_of_day_mode)
		if m is String and TimeOfDay.MODES.has(m):
			time_of_day_mode = m
		var f: Variant = cfg.get_value(SECTION, "fullscreen", fullscreen)
		if f is bool:
			fullscreen = f
		var q: Variant = cfg.get_value(SECTION, "quality", quality)
		if q is String and Tuning.QUALITY_LEVELS.has(q):
			quality = q
		var fps: Variant = cfg.get_value(SECTION, "max_fps", max_fps)
		if fps is int and Tuning.FPS_LIMITS.has(fps):
			max_fps = fps
		var vs: Variant = cfg.get_value(SECTION, "vsync", vsync)
		if vs is bool:
			vsync = vs
		var sf: Variant = cfg.get_value(SECTION, "show_fps", show_fps)
		if sf is bool:
			show_fps = sf
		var sg: Variant = cfg.get_value(SECTION, "show_ghost", show_ghost)
		if sg is bool:
			show_ghost = sg
		var t: Variant = cfg.get_value(SECTION, "trolley", current_trolley)
		if t is String and Trolleys.IDS.has(t):
			current_trolley = t
	Audio.set_volume(se_volume)
	_apply_fullscreen()
	_apply_display()
	display_changed.emit()


## FR-47b: 変えた瞬間に反映して保存する
func set_se_volume(volume: int) -> void:
	se_volume = clampi(volume, 0, Tuning.SE_VOLUME_MAX)
	Audio.set_volume(se_volume)
	save_settings()


func set_screen_shake(on: bool) -> void:
	screen_shake = on
	save_settings()


## 設計書4章: 設定「時間帯」。知らない値は A にする。変えた瞬間に保存する
func set_time_of_day_mode(mode: String) -> void:
	time_of_day_mode = mode if TimeOfDay.MODES.has(mode) else TimeOfDay.MODE_SEQUENCE
	save_settings()


## records-design.md 4章: 変えた瞬間に反映して保存する
func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_fullscreen()
	save_settings()
	display_changed.emit()


## trolleys-and-display-design.md 4章: 画質。知らない値は高。ゲーム画面を作るときに読む（今のゲーム画面は変えない）
func set_quality(level: String) -> void:
	quality = level if Tuning.QUALITY_LEVELS.has(level) else Tuning.QUALITY_LEVELS[0]
	save_settings()
	display_changed.emit()


## FPS 上限（0 は上限なし）。選択肢に無い値は初期値。変えた瞬間に効く
func set_max_fps(fps: int) -> void:
	max_fps = fps if Tuning.FPS_LIMITS.has(fps) else Tuning.FPS_LIMIT_DEFAULT
	_apply_display()
	save_settings()
	display_changed.emit()


func set_vsync(on: bool) -> void:
	vsync = on
	_apply_display()
	save_settings()
	display_changed.emit()


func set_show_fps(on: bool) -> void:
	show_fps = on
	save_settings()
	display_changed.emit()


func set_show_ghost(on: bool) -> void:
	show_ghost = on
	save_settings()


## 選んでいる車両（解放されていなければ標準型）
func trolley() -> String:
	return current_trolley if is_trolley_unlocked(current_trolley) else Trolleys.DEFAULT


## 車両を選ぶ。知らない・解放されていない車両は選べない（何もしない）
func set_trolley(id: String) -> void:
	if not is_trolley_unlocked(id):
		return
	current_trolley = id
	save_settings()


func is_trolley_unlocked(id: String) -> bool:
	return Trolleys.is_unlocked(id, _progress()["cleared"], _stamps)


## 解放されている車両（Trolleys.IDS の順）
func unlocked_trolleys() -> Array[String]:
	var out: Array[String] = []
	for id: String in Trolleys.IDS:
		if is_trolley_unlocked(id):
			out.append(id)
	return out


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "se_volume", se_volume)
	cfg.set_value(SECTION, "screen_shake", screen_shake)
	cfg.set_value(SECTION, "time_of_day_mode", time_of_day_mode)
	cfg.set_value(SECTION, "fullscreen", fullscreen)
	cfg.set_value(SECTION, "quality", quality)
	cfg.set_value(SECTION, "max_fps", max_fps)
	cfg.set_value(SECTION, "vsync", vsync)
	cfg.set_value(SECTION, "show_fps", show_fps)
	cfg.set_value(SECTION, "show_ghost", show_ghost)
	cfg.set_value(SECTION, "trolley", current_trolley)
	cfg.save(settings_path)


## 窓の全画面・窓を今の設定に合わせる。Web 版はブラウザに任せ、窓の無い headless（自動確認）では何もしない
func _apply_fullscreen() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


## FPS 上限と垂直同期を効かせる。窓の無い headless（自動確認）では何もしない（上限で確認が遅くならないように）。
## 垂直同期は Web 版ではブラウザに任せる
func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Engine.max_fps = max_fps
	if not OS.has_feature("web"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## n は 1〜STAGE_COUNT（本試験）か EX_FIRST〜（裏試験）
static func stage_path(n: int) -> String:
	if n >= Tuning.EX_FIRST:
		return EX_PATH_FORMAT % (n - Tuning.EX_FIRST + 1)
	return STAGE_PATH_FORMAT % n


## 記録のある試験の番号（本試験と裏試験）
static func all_stages() -> Array[int]:
	var out: Array[int] = []
	for n: int in range(1, Tuning.EX_FIRST + Tuning.EX_COUNT):
		out.append(n)
	return out


## 試験の保存のキー（"stage_01"・"ex_01"）
static func stage_key(n: int) -> String:
	return EX_KEY_FORMAT % (n - Tuning.EX_FIRST + 1) if n >= Tuning.EX_FIRST else STAGE_KEY_FORMAT % n


## 第 n 試験（stage_data はその JSON）を遊ぶときの時間帯。設定の A／C に従う（設計書4章）
func time_of_day(n: int, stage_data: Dictionary) -> String:
	return TimeOfDay.resolve(time_of_day_mode, n, Tuning.STAGE_COUNT, stage_data)


## ステージ n の記録の写し。記録が無ければ初期状態（未クリア・0点・★0）。
## trolley_id を指定すればその車両の記録、"" なら全車両をまとめた値（合格はどれか、最高得点と★は最大）
func record(n: int, trolley_id: String = "") -> Dictionary:
	if trolley_id != "":
		return ((_records.get(trolley_id, {}) as Dictionary).get(n, _blank()) as Dictionary).duplicate()
	var merged: Dictionary = _blank()
	for id: String in _records:
		var r: Dictionary = (_records[id] as Dictionary).get(n, _blank())
		merged["cleared"] = merged["cleared"] or r["cleared"]
		merged["best_score"] = maxi(merged["best_score"], r["best_score"])
		merged["stars"] = maxi(merged["stars"], r["stars"])
		merged["gold"] = merged["gold"] or r["gold"]
	return merged


## FR-41: ステージ1は最初から、ステージ N は N-1 のクリア（どれかの車両で）で解放
## 裏試験（EX_FIRST〜）は本試験の★の合計が ex_unlock_stars(n) 以上（replay-value-design.md 4章）
func is_unlocked(n: int) -> bool:
	if n >= Tuning.EX_FIRST:
		return n < Tuning.EX_FIRST + Tuning.EX_COUNT and total_stars() >= ex_unlock_stars(n)
	return n == 1 or record(n - 1)["cleared"]


## 裏試験 n（EX_FIRST〜）の解放に要る本試験の★の合計
static func ex_unlock_stars(n: int) -> int:
	return Tuning.EX_UNLOCK_STARS[clampi(n - Tuning.EX_FIRST, 0, Tuning.EX_COUNT - 1)]


## 全ステージの★の合計。trolley_id を指定すればその車両の分、"" なら試験ごとの最大の合計
func total_stars(trolley_id: String = "") -> int:
	var total: int = 0
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		total += record(n, trolley_id)["stars"]
	return total


## ステージ n をクリアした。FR-49: 最高得点と★はそれぞれ既存値より大きいときだけ上げる。
## 最高記録を更新したら true（FR-45 の「最高記録更新」）
## TODO(spec): 初めてのクリアは「既存の最高記録」が無いので、0点より上なら更新として扱う
## まだ解放されていないステージのクリアは記録しない（プレイ中に記録を消してからゴールしたとき。
## 記録すると、手前のステージを飛ばして次が解放される）
## trolley_id を省けば選んでいる車両の記録（車両ごと、trolleys-and-display-design.md 2章）
func submit_clear(n: int, score: int, stars: int, trolley_id: String = "", gold: bool = false) -> bool:
	if not is_unlocked(n):
		return false
	if trolley_id == "":
		trolley_id = trolley()
	if not is_trolley_unlocked(trolley_id):
		trolley_id = Trolleys.DEFAULT  # 走行中に記録を消して、選んでいた車両が解放されていない状態でゴールした
	var r: Dictionary = record(n, trolley_id)
	var updated: bool = score > r["best_score"]
	r["cleared"] = true
	r["best_score"] = maxi(r["best_score"], score)
	r["stars"] = maxi(r["stars"], stars)
	r["gold"] = r["gold"] or gold
	if not _records.has(trolley_id):
		_records[trolley_id] = {}
	_records[trolley_id][n] = r
	save_records()
	return updated


## FR-48, FR-50: 読めなければ初期状態（全未クリア、ステージ1のみ解放）。次に保存するときに上書きする
## TODO(spec): ファイルは読めたが値の型・範囲がおかしいステージは、そのステージだけ初期状態にする
func load_records() -> void:
	_records.clear()
	_stats = _blank_stats()
	_stamps.clear()
	_challenges.clear()
	_garage.clear()
	_endless.clear()
	_ghosts = null
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		_ghosts = {}  # 記録が無い（読めない）なら、隣に残ったゴーストのファイルも読まない
		_reset_locked_trolley()
		return
	_load_stats(cfg)
	for id: String in Trolleys.IDS:
		for n: int in all_stages():
			var key: String = _record_key(n, id)
			if not cfg.has_section(key):
				continue
			var cleared: Variant = cfg.get_value(key, "cleared", false)
			var best: Variant = cfg.get_value(key, "best_score", 0)
			var stars: Variant = cfg.get_value(key, "stars", 0)
			var gold: Variant = cfg.get_value(key, "gold", false)
			if cleared is bool and best is int and best >= 0 and stars is int and stars >= 0 and stars <= Tuning.STARS_MAX:
				if not _records.has(id):
					_records[id] = {}
				_records[id][n] = {"cleared": cleared, "best_score": best, "stars": stars, "gold": gold is bool and gold}
	_load_extras(cfg)
	_grant_progress_stamps()
	_reset_locked_trolley()


## save.cfg の記録のセクション名。標準型は今までどおり "stage_01"（古い記録は標準型の記録）、ほかは "stage_01/heavy"
static func _record_key(n: int, trolley_id: String) -> String:
	var key: String = stage_key(n)
	return key if trolley_id == Trolleys.DEFAULT else TROLLEY_KEY_FORMAT % [key, trolley_id]


func save_records() -> void:
	var cfg := ConfigFile.new()
	for id: String in _records:
		for n: int in _records[id]:
			var key: String = _record_key(n, id)
			for field: String in _records[id][n]:
				cfg.set_value(key, field, _records[id][n][field])
	if _stats != _blank_stats():  # 何も走っていなければセクションを作らない（FR-47c の消去の後は空のファイル）
		for field: String in _stats:
			cfg.set_value(STATS_SECTION, field, _stats[field])
	for id: String in _stamps:
		cfg.set_value(STAMPS_SECTION, id, _stamps[id])
	for n: int in _challenges:
		cfg.set_value(CHALLENGES_SECTION, stage_key(n), _challenges[n])
	for id: String in _garage:
		for field: String in _garage[id]:
			cfg.set_value(GARAGE_KEY_FORMAT % id, field, _garage[id][field])
	for id: String in _endless:
		var key: String = ENDLESS_SECTION if id == Trolleys.DEFAULT else TROLLEY_KEY_FORMAT % [ENDLESS_SECTION, id]
		for field: String in _endless[id]:
			cfg.set_value(key, field, _endless[id][field])
	cfg.save(save_path)


## FR-47c: 記録を初期状態にする（save.cfg も空にする）。設定は消さない。試験記録の累計と検定印も記録なので消す
func erase_records() -> void:
	_records.clear()
	_stats = _blank_stats()
	_stamps.clear()
	_challenges.clear()
	_garage.clear()
	_endless.clear()
	_ghosts = {}
	DirAccess.remove_absolute(ghosts_path())
	save_records()
	_reset_locked_trolley()


## 選んでいる車両が解放されていなければ標準型に戻して保存する（記録を消した・読めなかった後、同じ車両が解放し直されたとき
## に、選び直していないのにその車両へ黙って戻らないように）
func _reset_locked_trolley() -> void:
	if current_trolley != Trolleys.DEFAULT and not is_trolley_unlocked(current_trolley):
		current_trolley = Trolleys.DEFAULT
		save_settings()


## 試験記録の累計の写し（設計書 2.1 のキー）
func stats() -> Dictionary:
	return _stats.duplicate(true)


## 取った検定印の写し（id → 取った日）
func stamps() -> Dictionary:
	return _stamps.duplicate()


## 全試験に合格している（修了証書）
func all_cleared() -> bool:
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		if not record(n)["cleared"]:
			return false
	return true


## 走行1回分を累計に足し、新しく取った検定印の id を Achievements.LIST の順に返す（設計書 2.2）。
## ゲーム画面が、ゴール（submit_clear の後）・失敗・途中でやめたときに1回だけ呼ぶ
func submit_run(run: Dictionary) -> Array[String]:
	run = run.duplicate()
	var stage: int = run.get("stage", 0)
	run["passed"] = run["outcome"] == "clear" and stage >= 1 and record(stage)["cleared"]
	_stats["runs"] += 1
	if OUTCOME_COUNTS.has(run["outcome"]):
		_stats[OUTCOME_COUNTS[run["outcome"]]] += 1
	var smashed: Dictionary = run["smashed"]
	for kind: String in smashed:
		if SMASH_KINDS.has(kind):
			_stats["smashed"][kind] += smashed[kind]
	_stats["girigiri"] += run["girigiri"]
	_stats["best_speed"] = maxf(_stats["best_speed"], run["max_speed"])
	_stats["best_combo"] = maxi(_stats["best_combo"], run["max_combo"])
	_stats["distance"] += run["distance"]
	if stage >= 1:  # 無限軌道（0）は試験ごとの回数に入れない
		_stats["attempts"][stage] = _stats["attempts"].get(stage, 0) + 1
	var got: Array[String] = Achievements.newly_earned(_stamps, run, _stats, _progress())
	_grant(got)
	save_records()
	return got


## 試験ごとの合格と★（Achievements の progress）
## やりこみ要素（replay-value-design.md 8章）: "gold"（本試験ごとの金★）、"ex_cleared"・"ex_gold"（裏試験ごとの合格・金★）、
## "licenses"（車両 id → 第1〜STAGE_COUNT 試験にすべて合格したか）、"challenges"（達成した課題の数）、
## "challenges_total"（課題の総数）、"max_level"（車両の熟練度の最大）、"endless_distance"（無限軌道の1回の最長距離）
func _progress() -> Dictionary:
	var progress: Dictionary = {"cleared": [], "stars": [], "gold": [], "ex_cleared": [], "ex_gold": [], "licenses": {},
			"challenges": 0, "challenges_total": (Tuning.STAGE_COUNT + Tuning.EX_COUNT) * Tuning.CHALLENGE_COUNT,
			"max_level": 1, "endless_distance": 0.0}
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		var r: Dictionary = record(n)
		progress["cleared"].append(r["cleared"])
		progress["stars"].append(r["stars"])
		progress["gold"].append(r["gold"])
	for n: int in range(Tuning.EX_FIRST, Tuning.EX_FIRST + Tuning.EX_COUNT):
		progress["ex_cleared"].append(record(n)["cleared"])
		progress["ex_gold"].append(record(n)["gold"])
	for id: String in Trolleys.IDS:
		var all: bool = true
		for n: int in range(1, Tuning.STAGE_COUNT + 1):
			all = all and record(n, id)["cleared"]
		progress["licenses"][id] = all
		progress["max_level"] = maxi(progress["max_level"], Progression.level_for(garage(id)["xp"]))
		progress["endless_distance"] = maxf(progress["endless_distance"], endless_record(id)["best_distance"])
	for n: int in _challenges:
		progress["challenges"] += (_challenges[n] as Array).count(true)
	return progress


## 検定印を今日の日付で付ける。全課程修了なら修了日も（まだ無ければ）
func _grant(ids: Array[String]) -> void:
	var today: String = Time.get_date_string_from_system()
	for id: String in ids:
		_stamps[id] = today
	if ids.has("all_clear") and _stats["completed_on"] == "":
		_stats["completed_on"] = today


## 検定印が入る前の記録（合格と★はあるが、進み具合の印が無い）を読んだとき、進み具合だけで決まる印を付けて保存する
func _grant_progress_stamps() -> void:
	var blank_run: Dictionary = {"stage": 0, "outcome": "abort"}
	var progress: Dictionary = _progress()
	var got: Array[String] = []
	for id: String in Achievements.PROGRESS:
		if not _stamps.has(id) and Achievements.earned(id, blank_run, _stats, progress):
			got.append(id)
	if got.is_empty():
		return
	_grant(got)
	save_records()


## 設計書 2.1: 型が違う・負の値のキーはそのキーだけ初期値。知らない検定印・日付が文字でない検定印は捨てる
func _load_stats(cfg: ConfigFile) -> void:
	for key: String in STAT_COUNTS:
		var v: Variant = cfg.get_value(STATS_SECTION, key, 0)
		if v is int and v >= 0:
			_stats[key] = v
	for key: String in STAT_AMOUNTS:
		var v: Variant = cfg.get_value(STATS_SECTION, key, 0.0)
		if (v is float or v is int) and v >= 0 and is_finite(v):
			_stats[key] = float(v)
	var smashed: Variant = cfg.get_value(STATS_SECTION, "smashed", {})
	if smashed is Dictionary:
		for kind: String in SMASH_KINDS:
			var c: Variant = (smashed as Dictionary).get(kind, 0)
			if c is int and c >= 0:
				_stats["smashed"][kind] = c
	var attempts: Variant = cfg.get_value(STATS_SECTION, "attempts", {})
	if attempts is Dictionary:
		for n: Variant in attempts:
			var c: Variant = attempts[n]
			if n is int and n >= 1 and n < Tuning.EX_FIRST + Tuning.EX_COUNT and c is int and c >= 0:
				_stats["attempts"][n] = c
	var on: Variant = cfg.get_value(STATS_SECTION, "completed_on", "")
	if on is String:
		_stats["completed_on"] = on
	if cfg.has_section(STAMPS_SECTION):
		for id: String in cfg.get_section_keys(STAMPS_SECTION):
			var day: Variant = cfg.get_value(STAMPS_SECTION, id)
			if Achievements.has(id) and day is String:
				_stamps[id] = day


static func _blank() -> Dictionary:
	return {"cleared": false, "best_score": 0, "stars": 0, "gold": false}


# --- やりこみ要素（replay-value-design.md）: 課題・熟練度・強化・塗装・無限軌道・ゴースト ---

## 試験 n の課題の達成（CHALLENGE_COUNT 個の bool）
func challenges(n: int) -> Array[bool]:
	var out: Array[bool] = []
	var have: Array = _challenges.get(n, [])
	for i: int in Tuning.CHALLENGE_COUNT:
		out.append(i < have.size() and have[i])
	return out


## 合格した走行で試験 n の課題を判定し、今回新しく達成した課題の番号（0〜）を返す。list はステージの "challenges"、
## run は Challenges.achieved の辞書。まだ解放されていない試験（走行中に記録を消した）は記録しない
func submit_challenges(n: int, list: Array, run: Dictionary) -> Array[int]:
	var got: Array[int] = []
	if not is_unlocked(n):
		return got
	var done: Array[bool] = challenges(n)
	for i: int in mini(list.size(), Tuning.CHALLENGE_COUNT):
		if not done[i] and list[i] is Dictionary and Challenges.achieved(list[i], run):
			done[i] = true
			got.append(i)
	if not got.is_empty():
		_challenges[n] = done
		save_records()
	return got


## 車両 id の熟練度・強化・塗装の写し: {"xp", "level", "upgrades", "paint", "points_left"}
func garage(id: String) -> Dictionary:
	var g: Dictionary = _garage.get(id, {"xp": 0, "upgrades": {}, "paint": 0})
	var level: int = Progression.level_for(g["xp"])
	return {"xp": g["xp"], "level": level, "upgrades": (g["upgrades"] as Dictionary).duplicate(), "paint": g["paint"],
			"points_left": Progression.points_total(g["xp"]) - Progression.points_spent(g["upgrades"])}


func _garage_entry(id: String) -> Dictionary:
	if not _garage.has(id):
		_garage[id] = {"xp": 0, "upgrades": {}, "paint": 0}
	return _garage[id]


## 経験値を足して保存する。{"gained", "level_before", "level_after"}
## 解放されていない車両（走行中に記録を消した）の分は標準型に付ける（submit_clear と同じ）
func add_xp(id: String, amount: int) -> Dictionary:
	id = id if is_trolley_unlocked(id) else Trolleys.DEFAULT
	var g: Dictionary = _garage_entry(id)
	var before: int = Progression.level_for(g["xp"])
	g["xp"] += maxi(amount, 0)
	save_records()
	return {"gained": maxi(amount, 0), "level_before": before, "level_after": Progression.level_for(g["xp"])}


## 項目を1段上げる。ポイントが足りない・最大の段・知らない項目なら false
func buy_upgrade(id: String, item: String) -> bool:
	if not Progression.upgrade_ids().has(item):
		return false
	var info: Dictionary = garage(id)
	var step: int = info["upgrades"].get(item, 0)
	var cost: int = Progression.cost_of_next(step)
	if cost == 0 or cost > info["points_left"]:
		return false
	_garage_entry(id)["upgrades"][item] = step + 1
	save_records()
	return true


## 強化を全部戻す（ポイントは返る）
func reset_upgrades(id: String) -> void:
	_garage_entry(id)["upgrades"] = {}
	save_records()


## 塗装を選ぶ（0〜）。段で使えない塗装は選べない（何もしない）
func set_paint(id: String, paint: int) -> void:
	if paint < 0 or paint >= Progression.paints_unlocked(garage(id)["level"]):
		return
	_garage_entry(id)["paint"] = paint
	save_records()


## 強化込みの性能（Progression.stat）
func stat(id: String, key: String) -> float:
	return Progression.stat(id, key, garage(id)["upgrades"])


## 強化込みの壁・ジャンプの必要速度
func effective_required(id: String, kind: String, required: float) -> float:
	return Progression.effective_required(id, kind, required, garage(id)["upgrades"])


## 無限軌道の最高記録。trolley_id が "" なら全車両の最大
func endless_record(trolley_id: String = "") -> Dictionary:
	if trolley_id != "":
		return (_endless.get(trolley_id, {"best_score": 0, "best_distance": 0.0}) as Dictionary).duplicate()
	var merged: Dictionary = {"best_score": 0, "best_distance": 0.0}
	for id: String in _endless:
		merged["best_score"] = maxi(merged["best_score"], _endless[id]["best_score"])
		merged["best_distance"] = maxf(merged["best_distance"], _endless[id]["best_distance"])
	return merged


## 無限軌道の走行を記録する。得点か距離の最高記録を更新したら true
func submit_endless(score: int, distance: float, trolley_id: String) -> bool:
	trolley_id = trolley_id if is_trolley_unlocked(trolley_id) else Trolleys.DEFAULT
	var r: Dictionary = endless_record(trolley_id)
	var updated: bool = score > r["best_score"] or distance > r["best_distance"]
	r["best_score"] = maxi(r["best_score"], score)
	r["best_distance"] = maxf(r["best_distance"], distance)
	_endless[trolley_id] = r
	save_records()
	return updated


## 試験 n のゴースト（無ければ {}）
func ghost(n: int) -> Dictionary:
	_load_ghosts()
	return ((_ghosts as Dictionary).get(n, {}) as Dictionary).duplicate()


## 試験 n のゴーストを、今のものより得点が高ければ残す。残したら true。まだ解放されていない試験は残さない
func submit_ghost(n: int, data: Dictionary) -> bool:
	if not is_unlocked(n) or not data.get("score", -1) is int:
		return false
	_load_ghosts()
	if data["score"] <= ((_ghosts as Dictionary).get(n, {}) as Dictionary).get("score", -1):
		return false
	_ghosts[n] = data.duplicate()
	var cfg := ConfigFile.new()
	for k: int in _ghosts:
		cfg.set_value(stage_key(k), GHOST_KEY, _ghosts[k])
	cfg.save(ghosts_path())
	return true


## ゴーストのファイル。記録のファイル（save_path）の隣に置く（自動確認が記録の場所を差し替えると、ゴーストも差し替わる）
func ghosts_path() -> String:
	return save_path.get_basename() + GHOSTS_SUFFIX


func _load_ghosts() -> void:
	if _ghosts != null:
		return
	_ghosts = {}
	var cfg := ConfigFile.new()
	if cfg.load(ghosts_path()) != OK:
		return
	for n: int in all_stages():
		var d: Variant = cfg.get_value(stage_key(n), GHOST_KEY, {})
		if d is Dictionary and (d as Dictionary).get("score") is int and (d as Dictionary).get("points") is PackedVector3Array:
			_ghosts[n] = d


## 課題・熟練度・無限軌道を読む。型の違う値はそのキーだけ捨てる
func _load_extras(cfg: ConfigFile) -> void:
	for n: int in all_stages():
		var c: Variant = cfg.get_value(CHALLENGES_SECTION, stage_key(n), [])
		if c is Array and (c as Array).size() == Tuning.CHALLENGE_COUNT and (c as Array).all(func(b: Variant) -> bool: return b is bool):
			_challenges[n] = c
	var ids: Array[String] = Progression.upgrade_ids()
	for id: String in Trolleys.IDS:
		var key: String = GARAGE_KEY_FORMAT % id
		if cfg.has_section(key):
			var g: Dictionary = {"xp": 0, "upgrades": {}, "paint": 0}
			var xp: Variant = cfg.get_value(key, "xp", 0)
			if xp is int and xp >= 0:
				g["xp"] = xp
			var ups: Variant = cfg.get_value(key, "upgrades", {})
			if ups is Dictionary:
				for item: Variant in ups:
					var st: Variant = ups[item]
					if item is String and ids.has(item) and st is int and st >= 0 and st <= Tuning.UPGRADE_COSTS.size():
						g["upgrades"][item] = st
			if Progression.points_spent(g["upgrades"]) > Progression.points_total(g["xp"]):
				g["upgrades"] = {}  # ポイントより多く使っている（手で書き換えた）なら戻す
			var paint: Variant = cfg.get_value(key, "paint", 0)
			if paint is int and paint >= 0 and paint < Progression.paints_unlocked(Progression.level_for(g["xp"])):
				g["paint"] = paint
			_garage[id] = g
		var ekey: String = ENDLESS_SECTION if id == Trolleys.DEFAULT else TROLLEY_KEY_FORMAT % [ENDLESS_SECTION, id]
		if cfg.has_section(ekey):
			var bs: Variant = cfg.get_value(ekey, "best_score", 0)
			var bd: Variant = cfg.get_value(ekey, "best_distance", 0.0)
			if bs is int and bs >= 0 and (bd is float or bd is int) and bd >= 0 and is_finite(bd):
				_endless[id] = {"best_score": bs, "best_distance": float(bd)}


static func _blank_stats() -> Dictionary:
	var smashed: Dictionary = {}
	for kind: String in SMASH_KINDS:
		smashed[kind] = 0
	return {"runs": 0, "clears": 0, "crashes": 0, "derails": 0, "smashed": smashed, "girigiri": 0, "best_speed": 0.0,
			"best_combo": 0, "distance": 0.0, "attempts": {}, "completed_on": ""}
