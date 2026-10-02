extends SceneTree
## 車両の調整の約束（docs/superpowers/specs/2026-09-26-trolleys-and-display-design.md の1章・6章）の自動確認。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_trolleys.gd （失敗があれば終了コード1）
## 全車両 × 全ステージ × 全経路を実際に走らせるので、20分ほどかかる。
## 絞るときは車両の id とステージ番号を後ろに付ける（例: ... -s tests/checks_trolleys.gd -- heavy 3 5）。絞ったときは
## 経路ごとの結果（合否・得点・wall と jump の到達速度とその車両の必要速度）も出す。standard も付ければ標準型と比べた結果も出す
## （絞ったときの長所・短所の比べは参考。NG にするのは絞らないときだけ）。
## 記録と設定は確認用のファイル（プロセスごとの名前。並べて走らせてもぶつからない）に差し替え、終わったら消す。

const MAX_FRAMES: int = 20000
const GAME_SCENE: String = "res://scenes/game.tscn"
## 約束5: 性能のキー → [長所・短所の文に出す言葉, 値が大きいほど良いか]。標準型より良ければ長所に、悪ければ短所にその言葉が出て、
## 同じならどちらにも出ない（star_scale は性能ではなく★の閾値なので文にしない）
const TEXT_WORDS: Dictionary = {
	"speed_base": ["初速", true], "speed_max": ["最高速", true], "momentum_gain": ["勢いが溜まり", true],
	"momentum_decay": ["勢いが減り", false], "wall_factor": ["壁", false], "jump_factor": ["ジャンプ", false],
	"hit_power": ["吹っ飛ばす", true], "blast_radius": ["爆発", true], "combo_window": ["コンボ", true]}

var _failed: int = 0
var _settings_path: String = "user://checks_trolleys_%d_settings.cfg" % OS.get_process_id()
var _save_path: String = "user://checks_trolleys_%d_save.cfg" % OS.get_process_id()
## 車両 id → {ステージ番号 → {経路（"s0-s1-..."）→ 走った結果}}
var _results: Dictionary = {}
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前では参照できない
var _game_state: Node
var _time_scale: Node


func _initialize() -> void:
	_run.call_deferred()  # _initialize の時点では root がまだツリーに無く、_ready が走らない


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	_game_state = root.get_node("GameState")
	_time_scale = root.get_node("TimeScale")
	_game_state.settings_path = _settings_path
	_game_state.save_path = _save_path
	_unlock_all()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var ids: Array = Array(args).filter(func(a: String) -> bool: return Trolleys.IDS.has(a))
	var stages: Array = Array(args).filter(func(a: String) -> bool: return a.is_valid_int()).map(func(a: String) -> int: return a.to_int())
	var verbose: bool = not args.is_empty()
	if ids.is_empty():
		ids = Trolleys.IDS.duplicate()
	if stages.is_empty():
		stages = range(1, Tuning.STAGE_COUNT + 1)
	_check_text()
	for id: String in ids:
		_game_state.set_trolley(id)
		_expect(_game_state.trolley() == id, "%s を選べる（確認用の記録で解放してある）" % id)
		_results[id] = {}
		for n: int in stages:
			_results[id][n] = await _drive_stage(id, n, verbose)
			_check_stage(id, n)
	_check_pros_cons(not verbose)
	_print_table(stages)
	print("所要時間 %.1f 分" % ((Time.get_ticks_msec() - started) / 60000.0))
	await _finish()


## 全車両を解放する記録を確認用の save に作る（全試験に標準型で合格＝検定印「全課程修了」、検定印の条件の車両はその印）
func _unlock_all() -> void:
	var cfg := ConfigFile.new()
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		for field: String in ["cleared", "best_score", "stars"]:
			cfg.set_value(_game_state.STAGE_KEY_FORMAT % n, field, {"cleared": true, "best_score": 1, "stars": 1}[field])
	for id: String in Trolleys.IDS:
		var u: Dictionary = Tuning.TROLLEY_UNLOCK.get(id, {})
		if u.has("stamp"):
			cfg.set_value(_game_state.STAMPS_SECTION, u["stamp"], Time.get_date_string_from_system())
	cfg.save(_save_path)
	_game_state.load_records()
	_game_state.load_settings()


## 鳴っている効果音を止め、確認用の記録・設定ファイルを消してから終える（tests/checks_stages.gd と同じ）
func _finish() -> void:
	for p: Node in root.get_node("Audio").get_children():
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	await physics_frame
	await physics_frame
	for path: String in [_settings_path, _save_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# --- 約束 ---

## 約束5: 長所・短所の文が値と合っている
func _check_text() -> void:
	var std: Dictionary = Tuning.TROLLEY_STATS[Trolleys.DEFAULT]
	for id: String in Trolleys.IDS:
		if id == Trolleys.DEFAULT:
			continue
		var wrong: Array = []
		for key: String in TEXT_WORDS:
			var word: String = TEXT_WORDS[key][0]
			var diff: float = float(Tuning.TROLLEY_STATS[id][key]) - float(std[key])
			var better: bool = diff > 0.0 if TEXT_WORDS[key][1] else diff < 0.0
			var worse: bool = diff != 0.0 and not better
			if Trolleys.pros_of(id).contains(word) != better or Trolleys.cons_of(id).contains(word) != worse:
				wrong.append("%s（%s）" % [key, "良い" if better else ("悪い" if worse else "同じ")])
		_expect(wrong.is_empty(), "約束5 %s: 長所「%s」・短所「%s」は性能の値と合う（合わない %s）" % [
				Trolleys.name_of(id), Trolleys.pros_of(id), Trolleys.cons_of(id), wrong])


## 約束1・2: その車両で合格できる経路があり、★3（その車両の閾値）に届く
func _check_stage(id: String, n: int) -> void:
	var runs: Dictionary = _results[id][n]
	var three: int = _star3(id, n)
	var top: int = _top(id, n)
	var cleared: int = runs.values().filter(func(r: Dictionary) -> bool: return r["cleared"]).size()
	_expect(cleared > 0, "約束1 %s ステージ%d: 合格できる経路がある（%d / %d）" % [id, n, cleared, runs.size()])
	_expect(top >= three, "約束2 %s ステージ%d: 最高得点 %d で ★3（%d）に届く" % [id, n, top, three])


## 約束3・4: 標準型と比べた長所と短所。strict でなければ（絞ったとき）参考として出すだけ
func _check_pros_cons(strict: bool) -> void:
	if not _results.has(Trolleys.DEFAULT):
		return
	var std: Dictionary = _results[Trolleys.DEFAULT]
	for id: String in _results:
		if id == Trolleys.DEFAULT:
			continue
		var won: Array = []  # 標準型は失敗、この車両は合格した経路
		var lost: Array = []  # 標準型は合格、この車両は失敗した経路
		var higher: Array = []  # 最高得点が標準型より高いステージ
		var lower: Array = []
		for n: int in _results[id]:
			if not std.has(n):
				continue
			for key: String in _results[id][n]:
				var mine: bool = _results[id][n][key]["cleared"]
				var theirs: bool = std[n][key]["cleared"]
				if mine and not theirs:
					won.append("%d:%s" % [n, key])
				elif theirs and not mine:
					lost.append("%d:%s" % [n, key])
			var diff: int = _top(id, n) - _top(Trolleys.DEFAULT, n)
			if diff > 0:
				higher.append(n)
			elif diff < 0:
				lower.append(n)
		# 壁かジャンプに強い車両は「標準型が失敗する経路を越えられる」で確かめる。どちらにも強くなければ最高得点でもよい
		var tough: bool = Trolleys.stat(id, "wall_factor") < 1.0 or Trolleys.stat(id, "jump_factor") < 1.0
		var pros_ok: bool = not won.is_empty() or (not tough and not higher.is_empty())
		var cons_ok: bool = not lost.is_empty() or not lower.is_empty()
		var pros_label: String = "約束3 %s: 長所が効く（標準型が失敗して合格する経路 %d 本 %s、最高得点が上のステージ %s）" % [
				id, won.size(), won, higher]
		var cons_label: String = "約束4 %s: 短所が効く（標準型が合格して失敗する経路 %d 本 %s、最高得点が下のステージ %s）" % [
				id, lost.size(), lost, lower]
		if strict:
			_expect(pros_ok, pros_label)
			_expect(cons_ok, cons_label)
		else:
			print("（参考）" + pros_label)
			print("（参考）" + cons_label)


## 車両ごと・ステージごとの、合格できる経路の数と最高得点（標準型との比）の表
func _print_table(stages: Array) -> void:
	print("--- 合格できる経路 / 全経路、最高得点（★3 の閾値、標準型との差） ---")
	for id: String in _results:
		var cells: Array = []
		for n: int in stages:
			var runs: Dictionary = _results[id][n]
			var cleared: int = runs.values().filter(func(r: Dictionary) -> bool: return r["cleared"]).size()
			var vs: String = ""
			if id != Trolleys.DEFAULT and _results.has(Trolleys.DEFAULT) and _results[Trolleys.DEFAULT].has(n):
				var s: int = _top(Trolleys.DEFAULT, n)
				vs = " %+d%%" % roundi(100.0 * (_top(id, n) - s) / maxf(s, 1.0))
			cells.append("%d: %d/%d %d(%d%s)" % [n, cleared, runs.size(), _top(id, n), _star3(id, n), vs])
		print("%-10s %s" % [id, "  ".join(cells)])


func _top(id: String, n: int) -> int:
	var top: int = 0
	for r: Dictionary in (_results[id][n] as Dictionary).values():
		if r["cleared"]:
			top = maxi(top, r["score"])
	return top


func _star3(id: String, n: int) -> int:
	var data: Dictionary = StageLoader.load_json(_game_state.stage_path(n))
	return Trolleys.thresholds(id, data["star_thresholds"])[1]


# --- 走らせる（tests/checks_stages.gd の _routes・_drive から、L-3 の見え方を除いたもの） ---

## 選んでいる車両で、ステージ n の全経路を走らせる。{経路 → 結果}
func _drive_stage(id: String, n: int, verbose: bool) -> Dictionary:
	var data: Dictionary = StageLoader.load_json(_game_state.stage_path(n))
	var out: Dictionary = {}
	for route: Array in _routes(data):
		var key: String = "-".join(route)
		out[key] = await _drive(data, route)
		if verbose:
			var r: Dictionary = out[key]
			var speeds: Array = []
			for k: String in r["arrivals"]:
				speeds.append("%s %.0f/%.0f" % [k, r["arrivals"][k], _required(id, data, k)])
			print("    %s ステージ%d %s %s 得点 %d 到達/必要 %s" % [id, n, key, "合格" if r["cleared"] else r["reason"], r["score"],
					", ".join(speeds)])
	return out


## その車両にとっての wall（"objects[i]"）・jump（セグメント ID）の必要速度
func _required(id: String, data: Dictionary, key: String) -> float:
	if key.begins_with("objects["):
		var od: Dictionary = data["objects"][key.trim_prefix("objects[").trim_suffix("]").to_int()]
		return Trolleys.effective_required(id, "wall", od["required_speed"])
	return Trolleys.effective_required(id, "jump", data["segments"][key]["jump"]["required_speed"])


## ルートどおりに分岐を合わせて最後まで走らせる。戻り値:
## { "cleared": ゴールした, "reason": 失敗の理由, "score": 得点, "arrivals": {wall・jump のキー: 到達速度} }
func _drive(data: Dictionary, route: Array) -> Dictionary:
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.stage_data = data.duplicate(true)
	root.add_child(game)
	game.set_process_unhandled_input(false)
	var segs: Dictionary = data["segments"]
	for i: int in route.size() - 1:
		var end: Dictionary = segs[route[i]]["end"]
		if end["type"] == "junction":
			var junction: Junction = game._junctions[end["id"]]
			junction.selected = junction.branches.find(route[i + 1])
	var trolley: Trolley = game._trolley
	var arrivals: Dictionary = {}
	var walls: Dictionary = {}  # まだ残っている wall の instance ID → キー（build() は objects の順に標的を作る）
	for i: int in data["objects"].size():
		if data["objects"][i]["type"] == "wall":
			walls[(game._targets[i] as Target).get_instance_id()] = "objects[%d]" % i
	trolley.segment_entered.connect(func(id: String) -> void:
		if segs[id].has("jump"):
			arrivals[id] = trolley.speed)
	for _i: int in MAX_FRAMES:
		if game._finished:
			break
		await physics_frame
		var alive: Dictionary = {}
		for t: Target in game._targets:
			alive[t.get_instance_id()] = true
		for wid: int in walls.keys():
			if not alive.has(wid):  # 壊れた
				arrivals[walls[wid]] = trolley.speed
				walls.erase(wid)
		if game.fail_reason == "激突":  # 激突した wall = 残っている wall のうちトロッコに一番近いもの
			var nearest: int = 0
			for wid: int in walls:
				var d: float = (instance_from_id(wid) as Node2D).global_position.distance_to(trolley.global_position)
				if nearest == 0 or d < (instance_from_id(nearest) as Node2D).global_position.distance_to(trolley.global_position):
					nearest = wid
			if nearest != 0:
				arrivals[walls[nearest]] = trolley.speed
	var result: Dictionary = {"cleared": game._finished and game.fail_reason == "", "reason": game.fail_reason,
			"score": game.score, "arrivals": arrivals}
	if not game._finished:
		result["reason"] = "時間切れ"
	game.free()
	_time_scale.clear()  # 消したゲームのヒットストップ・スローモーを次の走行に持ち越さない
	return result


## start_segment からゴールまでの全経路（セグメントIDの配列）
func _routes(data: Dictionary) -> Array:
	var out: Array = []
	var stack: Array = [[data["start_segment"]]]
	while not stack.is_empty():
		var route: Array = stack.pop_back()
		var nexts: Array[String] = StageLoader._next_ids(data["segments"][route.back()], data["segments"], data["junctions"])
		if nexts.is_empty():
			out.append(route)
		for next: String in nexts:
			stack.append(route + [next])
	return out


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
