extends SceneTree
## ステージデータの自動確認（M5: AC-14, AC-15, AC-17 と 8.2 のレベルデザイン規則）。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_stages.gd （失敗があれば終了コード1）
## 全ステージの全ルート（分岐の選び方すべて）を実際に走らせるので、数分かかる。
## ステージを絞るときは番号を後ろに付ける（例: ... -s tests/checks_stages.gd -- 7 9）。絞ったときは、ルートごとの
## 得点と wall・jump の到達速度も出す（必要速度と★の閾値を決めるのに使う）
## 車両を付けると（例: -- trolley=prototype）、その車両で全経路を走らせ、見え方の規則（L-3）とデータの規則だけを確かめる
## （必要速度・★の閾値・検定印は標準型で決めてあるので確かめない。車両ごとの合否と★は tests/checks_trolleys.gd）
## 裏試験（replay-value-design.md 4章）は -- ex で5つ、-- ex=2 で裏試験2だけ（-- trolley=<id> とも組み合わせられる）。
## 裏試験では L-1〜L-8 に加えて、5台どの車両でも L-5（その車両の必要速度）と★3 に届くこと、課題3つと金★を実走で確かめる
## （課題・金★は強化なしの標準型で。車両を名指しする課題はその車両の回で確かめる）。経路ごとの結果も出す
## 記録と設定は確認用のファイルに差し替え、終わったら消す（遊んでいる人の記録を上書きしない）。

const MAX_FRAMES: int = 20000
const GAME_SCENE: String = "res://scenes/game.tscn"
const EXAMPLE_STAGE: String = "res://tests/example_stage.json"  # 仕様書6.2の例（本物のステージ1とは別）
## 確認用の記録と設定（プロセスごとの名前。車両ごとに並べて走らせてもぶつからない）
var _settings_path: String = "user://checks_stages_%d_settings.cfg" % OS.get_process_id()
var _save_path: String = "user://checks_stages_%d_save.cfg" % OS.get_process_id()
## 8.1 の「新要素」（L-1）。分岐は junction、ジャンプは jump と書く（勢いはデータに現れないので省く）。
## 第6〜10試験は新要素なし（それまでの要素の応用。docs/superpowers/specs/2026-09-26-more-stages-design.md）
const NEW_ELEMENTS: Array = [["junction", "crate"], ["dummy", "barrel"], ["wall"], ["drum"], ["jump"], [], [], [], [], []]
const WALL_STAGE: int = 3  # L-7 の対象
const TROLLEY_ARG: String = "trolley="
const EX_ARG: String = "ex"  # 裏試験（-- ex で5つ、-- ex=N で裏試験N）
## 1回の走行で取る検定印（records-design.md 2.3）。全ステージを走らせたとき、どれもどこかの経路で取れる
const RUN_STAMPS: Array[String] = ["combo_max", "chain", "top_speed", "no_toggle", "big_score", "first_crash", "first_derail"]

var _failed: int = 0
var _verbose: bool = false  # ステージを絞ったときは、ルートごとの結果も出す
var _trolley: String = Trolleys.DEFAULT  # 走らせる車両（-- trolley=<id>）
var _stamps_seen: Dictionary = {}  # 1回の走行で取れた検定印の id → 取れたステージと経路
var _most_girigiri: Array = [0, ""]  # 1回の走行のギリギリ突破の最多 [回数, ステージと経路]（紙一重の条件を決めるため）
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前では参照できない
var _game_state: Node
var _time_scale: Node


func _initialize() -> void:
	_run.call_deferred()  # _initialize の時点では root がまだツリーに無く、_ready が走らない


func _run() -> void:
	_game_state = root.get_node("GameState")
	_time_scale = root.get_node("TimeScale")
	_game_state.settings_path = _settings_path
	_game_state.save_path = _save_path
	_game_state.load_records()
	for check: Callable in [_check_validate_accepts, _check_validate_rejects]:
		if check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
	var args: Array = Array(OS.get_cmdline_user_args())
	for a: String in args:
		if a.begins_with(TROLLEY_ARG):
			_trolley = a.trim_prefix(TROLLEY_ARG)
	var only: Array = args.filter(func(a: String) -> bool: return not a.begins_with(TROLLEY_ARG) and not a.begins_with(EX_ARG)).map(
			func(a: String) -> int: return a.to_int())
	var stages: Array = range(1, Tuning.STAGE_COUNT + 1)
	for a: String in args:
		if a == EX_ARG:
			stages = range(Tuning.EX_FIRST, Tuning.EX_FIRST + Tuning.EX_COUNT)
		elif a.begins_with(EX_ARG + "="):
			stages = [Tuning.EX_FIRST + a.trim_prefix(EX_ARG + "=").to_int() - 1]
	var ex: bool = stages[0] >= Tuning.EX_FIRST
	_verbose = not only.is_empty() or ex
	if _trolley != Trolleys.DEFAULT:
		_use_trolley()
	_expect(NEW_ELEMENTS.size() == Tuning.STAGE_COUNT, "L-1 の新要素の表はステージ %d 個分（%d）" % [Tuning.STAGE_COUNT, NEW_ELEMENTS.size()])
	for n: int in stages:
		if not ex and _verbose and not only.has(n):
			continue
		if await _check_stage(n) != true:
			_expect(false, "%s の確認が途中で止まった" % _label(n))
	if not _verbose and _trolley == Trolleys.DEFAULT:
		var missing: Array = RUN_STAMPS.filter(func(id: String) -> bool: return not _stamps_seen.has(id))
		_expect(missing.is_empty(), "1回の走行で取る検定印は、どれもどこかのステージの経路で取れる（取れない %s。取れた %s。ギリギリ突破の最多 %s）" % [
				missing, _stamps_seen, _most_girigiri])
	await _finish()


## 全車両を解放して（確認用の記録に全試験の合格と、解放に要る検定印を書く）、_trolley を選ぶ
func _use_trolley() -> void:
	_expect(Trolleys.IDS.has(_trolley), "車両 %s がある（%s）" % [_trolley, Trolleys.IDS])
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		_game_state.submit_clear(n, 1, 1, Trolleys.DEFAULT)
	for u: Dictionary in Tuning.TROLLEY_UNLOCK.values():
		if u.has("stamp"):
			_game_state._stamps[u["stamp"]] = "2026-09-27"
	_game_state.set_trolley(_trolley)
	_expect(_game_state.trolley() == _trolley, "車両 %s で走らせる" % _trolley)


## 鳴っている効果音を止め、確認用の記録・設定ファイルを消してから終える。--fixed-fps では実時間がほとんど進まず、
## 止めた音を片付ける前に終わってしまう（終了時に「resources still in use」が出る）ので、少しだけ実時間で待つ
func _finish() -> void:
	for p: Node in root.get_node("Audio").get_children():
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	await physics_frame
	await physics_frame
	for path: String in [_settings_path, _save_path, _game_state.ghosts_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# --- 6.4 の検証 ---

# 仕様書6.2の例と、tests/checks.gd が作る仮のステージ（直線・ジャンプ）は検証を通る
func _check_validate_accepts() -> bool:
	var errors: Array[String] = StageLoader.validate(StageLoader.load_json(EXAMPLE_STAGE))
	_expect(errors.is_empty(), "6.4 仕様書6.2の例は検証を通る（%s）" % [errors])
	var objects: Array = []
	for kind: String in ["crate", "barrel", "dummy", "drum"]:
		objects.append({"type": kind, "segment": "s0", "offset": 600.0})
	objects.append({"type": "wall", "segment": "s0", "offset": 3450.0, "required_speed": 700.0})
	var straight: Dictionary = {
		"id": "check", "name": "check", "ground_y": 900.0, "start_segment": "s0", "star_thresholds": [1, 2],
		"segments": {"s0": {"points": [[0, 600.0], [4000, 600.0]], "end": {"type": "goal"}}},
		"junctions": {}, "objects": objects}
	errors = StageLoader.validate(straight)
	_expect(errors.is_empty(), "6.4 tests/checks.gd の直線のコース（_straight）は検証を通る（%s）" % [errors])
	var jump: Dictionary = straight.duplicate(true)
	jump["objects"] = []
	jump["segments"] = {
		"s0": {"points": [[0, 600.0], [1000, 600.0]], "end": {"type": "next", "segment": "s1"}},
		"s1": {"points": [[1000, 600.0], [1200, 500.0], [1400, 600.0]], "jump": {"required_speed": 700.0},
				"end": {"type": "next", "segment": "s2"}},
		"s2": {"points": [[1400, 600.0], [3000, 600.0]], "end": {"type": "goal"}}}
	errors = StageLoader.validate(jump)
	_expect(errors.is_empty(), "6.4 tests/checks.gd のジャンプのコース（_jump_stage）は検証を通る（%s）" % [errors])
	return true


# AC-14, 6.4: 8項目それぞれの違反を見つけ、何が悪いかを返す。形の崩れたデータでも止まらない
func _check_validate_rejects() -> bool:
	var cases: Array = [
		["AC-14 存在しないセグメントIDを参照", "存在しないセグメント s9", func(d: Dictionary) -> void:
			d["segments"]["s1"]["end"]["segment"] = "s9"],
		["6.4-1 存在しない分岐IDを参照", "存在しない分岐 j9", func(d: Dictionary) -> void:
			d["segments"]["s0"]["end"]["id"] = "j9"],
		["6.4-1 標的が存在しないセグメントの上", "objects[0] の segment が存在しないセグメント s9", func(d: Dictionary) -> void:
			d["objects"][0]["segment"] = "s9"],
		["6.4-2 points が1点", "（2）", func(d: Dictionary) -> void:
			d["segments"]["s3"]["points"] = [[4000, 600]]],
		["6.4-3 出口の始点が分岐点から2pxずれる", "（3）", func(d: Dictionary) -> void:
			d["segments"]["s2"]["points"][0] = [1800, 602]],
		["6.4-4 branches が3本", "（4）", func(d: Dictionary) -> void:
			d["junctions"]["j0"]["branches"].append("s3")],
		["6.4-4 default が2", "（4）", func(d: Dictionary) -> void:
			d["junctions"]["j0"]["default"] = 2],
		["6.4-4 star_thresholds が降順", "star_thresholds", func(d: Dictionary) -> void:
			d["star_thresholds"] = [3000, 1500]],
		["6.4-5 offset がセグメント長より大きい", "（5）", func(d: Dictionary) -> void:
			d["objects"][0]["offset"] = 3000],
		["6.4-5 offset が負", "（5）", func(d: Dictionary) -> void:
			d["objects"][0]["offset"] = -1],
		["6.4-6 wall に required_speed が無い", "（6）", func(d: Dictionary) -> void:
			d["objects"][0]["type"] = "wall"],
		["6.4-7 循環していて goal に着かない", "（7）", func(d: Dictionary) -> void:
			d["segments"]["s3"]["end"] = {"type": "next", "segment": "s4"}
			d["segments"]["s4"] = {"points": [[6000, 600], [6000, 300], [0, 300], [0, 600]],
					"end": {"type": "next", "segment": "s0"}}],
		["6.4-8 分岐の間が MIN_JUNCTION_GAP より短い", "（8）", func(d: Dictionary) -> void:
			d["objects"] = []
			d["segments"]["s1"] = {"points": [[1800, 600], [2200, 450], [2400, 450]], "end": {"type": "junction", "id": "j1"}}
			d["segments"]["s4"] = {"points": [[2400, 450], [4000, 600]], "end": {"type": "next", "segment": "s3"}}
			d["segments"]["s5"] = {"points": [[2400, 450], [4000, 450], [4000, 600]], "end": {"type": "next", "segment": "s3"}}
			d["junctions"]["j1"] = {"branches": ["s4", "s5"], "default": 0}],
		["知らない標的の種類", "知らない標的の種類", func(d: Dictionary) -> void:
			d["objects"][0]["type"] = "rock"],
		["jump に required_speed が無い", "jump に数値の required_speed が無い", func(d: Dictionary) -> void:
			d["segments"]["s1"]["jump"] = {}],
		["キーが足りない", "star_thresholds", func(d: Dictionary) -> void:
			d.erase("star_thresholds")
			d.erase("ground_y")],
		["型が違う", "points", func(d: Dictionary) -> void:
			d["segments"]["s1"]["points"] = "abc"
			d["segments"]["s2"]["end"] = 5
			d["junctions"]["j0"]["branches"] = {"a": 1}
			d["objects"].append(7)],
	]
	for c: Array in cases:
		var d: Dictionary = StageLoader.load_json(EXAMPLE_STAGE)
		(c[2] as Callable).call(d)
		var errors: Array[String] = StageLoader.validate(d)
		var hit: bool = errors.any(func(e: String) -> bool: return e.contains(c[1]))
		_expect(hit, "%s を違反として返す（%s）" % [c[0], errors])
	for junk: Variant in [{}, {"segments": 1}, {"segments": {"s0": null}, "junctions": {}},
			{"segments": {"s0": {"points": [[0, 0], [9, 0]], "end": {"type": 3}}}, "junctions": {"j": []}, "objects": {}}]:
		_expect(not StageLoader.validate(junk).is_empty(), "形の崩れたデータ %s でも止まらずに違反を返す" % [junk])
	return true


# --- ステージ ---

func _check_stage(n: int) -> bool:
	var data: Dictionary = StageLoader.load_json(_game_state.stage_path(n))
	var errors: Array[String] = StageLoader.validate(data)
	_expect(errors.is_empty(), "AC-17 ステージ%d は検証（6.4、8 の MIN_JUNCTION_GAP を含む）を通る（%s）" % [n, errors])
	if not errors.is_empty():
		return true
	_expect(data["id"] == _game_state.stage_key(n), "ステージ%d の id は %s（%s）" % [n, _game_state.stage_key(n), data["id"]])
	var routes: Array = _routes(data)
	var fails: Array = _failure_elements(data)
	_check_elements(n, data)
	_check_detours(n, data, fails)
	_check_lengths(n, data, routes)
	if n == WALL_STAGE:
		_check_first_wall(data, routes)
	_check_branch_y(n, data)

	# 全ルートを走らせる
	var material: Dictionary = _decision_material(data)
	var drives: Dictionary = {}  # ルート（"s0-s1-..."）→ 走った結果
	var unseen: Array[String] = []
	for route: Array in routes:
		drives["-".join(route)] = await _drive(data, route, material, unseen)
		if _verbose:
			var r: Dictionary = drives["-".join(route)]
			print("    %s %s 得点 %d 到達速度 %s" % ["-".join(route), "ゴール" if r["cleared"] else "失敗", r["score"], r["arrivals"]])
			if n >= Tuning.EX_FIRST:  # 課題の値を決めるのに使う
				var run: Dictionary = r["run"]
				print("      コンボ %d 巻き込み %d 最高速 %.0f 切り替え %d ギリギリ %d 壊した %s" % [run["max_combo"], run["chained"],
						run["max_speed"], run["toggles"], run["girigiri"], run["smashed"]])
	_expect(unseen.is_empty(),
			"L-3 ステージ%d: どのルートでも、分岐の %.1f 秒前に各出口の最初の標的と wall・jump の標識が画面内で、HUD の札に隠れない（%s）" % [
				n, Tuning.DECISION_LEAD_TIME, unseen])

	var ex: bool = n >= Tuning.EX_FIRST
	if _trolley != Trolleys.DEFAULT and not ex:
		return true  # 必要速度と★の閾値は標準型で決めてある（車両ごとは checks_trolleys）
	# L-5: wall・jump に至る経路のうち標的が最も多い経路で、到達速度 ≥ required_speed + 50。遅い経路では失敗する。
	# 裏試験は車両ごとに、その車両の必要速度（壁・ジャンプへの強さを掛けた値、強化なし）で確かめる
	for f: Dictionary in fails:
		var best: Array = _richest_route_to(data, routes, f)
		var arrival: float = (drives["-".join(best)] as Dictionary)["arrivals"].get(f["key"], -1.0)
		var need: float = Trolleys.effective_required(_trolley, "jump" if data["segments"].has(f["key"]) else "wall", f["required"])
		_expect(arrival >= need + Tuning.REQUIRED_SPEED_MARGIN,
				"L-5 ステージ%d の %s（%s の必要 %d）: 標的の最も多い経路（%s）で到達速度 %.0f ≥ %d（-1 は届かなかった）" % [
					n, f["key"], _trolley, need, "-".join(best), arrival, need + Tuning.REQUIRED_SPEED_MARGIN])
		if _trolley != Trolleys.DEFAULT:
			continue
		var slowest: float = INF
		for r: Dictionary in drives.values():
			slowest = minf(slowest, r["arrivals"].get(f["key"], INF))
		_expect(slowest < f["required"], "ステージ%d の %s: 遅い経路で着くと失敗する（最も遅い到達速度 %.0f < %d）" % [
				n, f["key"], slowest, f["required"]])

	# ★: 最高得点で ★3 に届く（15章: 閾値は開発者が試遊で決める仮値）
	var top: int = 0
	var cleared: int = 0
	for r: Dictionary in drives.values():
		if r["cleared"]:
			cleared += 1
			top = maxi(top, r["score"])
	var three: int = Trolleys.thresholds(_trolley, data["star_thresholds"])[1]
	_expect(top >= three, "ステージ%d: %s の最高得点 %d で ★3（%d）に届く（ゴールできる経路 %d / %d）" % [
			n, _trolley, top, three, cleared, routes.size()])
	if ex:
		_check_ex_rewards(n, data, drives, top)
	if _trolley != Trolleys.DEFAULT:
		return true

	# AC-15: 標的の最も多い経路で全標的を壊しても、freeze 解除済みの物体は MAX_ACTIVE_BODIES 以下（本試験と裏試験の最後）
	if n == Tuning.STAGE_COUNT or n == Tuning.EX_FIRST + Tuning.EX_COUNT - 1:
		var heavy: Array = _richest_route_to(data, routes, {})
		var r: Dictionary = drives["-".join(heavy)]
		_expect(r["cleared"] and r["max_bodies"] <= Tuning.MAX_ACTIVE_BODIES,
				"AC-15 ステージ%d を標的の最も多い経路（%s）で走りきり、freeze 解除済みの物体は最大 %d 個（上限 %d）" % [
					n, "-".join(heavy), r["max_bodies"], Tuning.MAX_ACTIVE_BODIES])
	return true


## 裏試験の課題3つと金★（replay-value-design.md 3章）: 課題はどれも、強化なしの標準型（車両を名指しする課題はその車両）の
## どこかの経路で達成できる。金★の閾値は標準型の最高得点の約 EX_GOLD_RATIO（EX_GOLD_STEP 単位で切り捨て）で、★3 より上
func _check_ex_rewards(n: int, data: Dictionary, drives: Dictionary, top: int) -> void:
	var list: Variant = data.get("challenges")
	var errors: Array[String] = Challenges.validate(list)
	_expect(list is Array and errors.is_empty(), "%s の課題は %d つで正しい形（%s）" % [_label(n), Tuning.CHALLENGE_COUNT, errors])
	if not errors.is_empty() or list == null:
		return
	for c: Dictionary in list:
		var named: String = c.get("trolley", "") if c["type"] == "trolley" else Trolleys.DEFAULT
		if named != _trolley:
			if _trolley == Trolleys.DEFAULT:
				print("（参考）%s の課題「%s」は -- trolley=%s の回で確かめる" % [_label(n), Challenges.describe(c), named])
			continue
		var by: Array = drives.keys().filter(func(k: String) -> bool: return Challenges.achieved(c, drives[k]["run"]))
		_expect(not by.is_empty(), "%s の課題「%s」は %s で達成できる（達成した経路 %d 本 %s）" % [
				_label(n), Challenges.describe(c), Trolleys.name_of(_trolley), by.size(), by.slice(0, 3)])
	if _trolley != Trolleys.DEFAULT:
		return
	var gold: int = data.get("gold_threshold", 0)
	var ideal: int = floori(top * Tuning.EX_GOLD_RATIO / Tuning.EX_GOLD_STEP) * Tuning.EX_GOLD_STEP
	_expect(gold > data["star_thresholds"][1] and gold <= top and gold >= ideal - Tuning.EX_GOLD_STEP,
			"%s の金★ %d は標準型の最高得点 %d で取れ、その約 %d%%（%d）に近く、★3（%d）より上" % [
				_label(n), gold, top, roundi(Tuning.EX_GOLD_RATIO * 100.0), ideal, data["star_thresholds"][1]])


## 見出し（「第3試験」「裏試験2」）
func _label(n: int) -> String:
	return Display.stage_title(n)


# L-1: 新しく登場する要素は 8.1 の新要素だけ（前のステージの要素は使ってよい）。新要素は必ず出す。
# 裏試験は新要素なし（本試験の全要素を使ってよい）
func _check_elements(n: int, data: Dictionary) -> void:
	var present: Dictionary = {}
	for od: Dictionary in data["objects"]:
		present[od["type"]] = true
	if not (data["junctions"] as Dictionary).is_empty():
		present["junction"] = true
	for seg: Dictionary in data["segments"].values():
		if seg.has("jump"):
			present["jump"] = true
	var allowed: Array = []
	for i: int in mini(n, Tuning.STAGE_COUNT):
		allowed.append_array(NEW_ELEMENTS[i])
	var new: Array = NEW_ELEMENTS[n - 1] if n <= Tuning.STAGE_COUNT else []
	var extra: Array = present.keys().filter(func(e: String) -> bool: return not allowed.has(e))
	var missing: Array = new.filter(func(e: String) -> bool: return not present.has(e))
	_expect(extra.is_empty() and missing.is_empty(), "L-1 ステージ%d の要素 %s は 8.1 のここまでの要素だけで、新要素 %s を含む（余分 %s、不足 %s）" % [
			n, present.keys(), new, extra, missing])


# L-4: wall・jump は分岐の片方の出口にだけあり、もう片方の出口（合流まで）には失敗要素が無い
func _check_detours(n: int, data: Dictionary, fails: Array) -> void:
	var safe_side: Dictionary = {}  # 反対の出口に失敗要素が無い出口のセグメント
	for j: Dictionary in data["junctions"].values():
		var own: Array = [_own_part(data, j["branches"][0], j["branches"][1]), _own_part(data, j["branches"][1], j["branches"][0])]
		for i: int in 2:
			if not fails.any(func(f: Dictionary) -> bool: return own[1 - i].has(f["segment"])):
				for id: String in own[i]:
					safe_side[id] = true
	var bad: Array = fails.filter(func(f: Dictionary) -> bool: return not safe_side.has(f["segment"]))
	_expect(bad.is_empty(), "L-4 ステージ%d: wall・jump %d 個すべての手前の分岐に失敗要素の無い迂回がある（迂回が無い %s）" % [
			n, fails.size(), bad.map(func(f: Dictionary) -> String: return f["key"])])


# L-6: どの経路でもスタートからゴールまで STAGE_LENGTH_MIN〜STAGE_LENGTH_MAX px
func _check_lengths(n: int, data: Dictionary, routes: Array) -> void:
	var shortest: float = INF
	var longest: float = 0.0
	for route: Array in routes:
		var length: float = _distance(data, route, route.size())
		shortest = minf(shortest, length)
		longest = maxf(longest, length)
	_expect(shortest >= Tuning.STAGE_LENGTH_MIN and longest <= Tuning.STAGE_LENGTH_MAX,
			"L-6 ステージ%d の総延長は全 %d 経路で %.0f〜%.0f px（%d〜%d）" % [
				n, routes.size(), shortest, longest, Tuning.STAGE_LENGTH_MIN, Tuning.STAGE_LENGTH_MAX])


# L-7: ステージ3の最初の wall はスタートから FIRST_WALL_MAX px 以内
# TODO(spec): 「ステージ開始から5000px」は x 座標でなく、スタートから線路に沿った経路距離で測った
func _check_first_wall(data: Dictionary, routes: Array) -> void:
	var nearest: float = INF
	for route: Array in routes:
		for i: int in route.size():
			for od: Dictionary in data["objects"]:
				if od["type"] == "wall" and od["segment"] == route[i]:
					nearest = minf(nearest, _distance(data, route, i) + od["offset"])
	_expect(nearest <= Tuning.FIRST_WALL_MAX, "L-7 ステージ%d の最初の wall はスタートから %.0f px（%d 以内）" % [
			WALL_STAGE, nearest, Tuning.FIRST_WALL_MAX])


# L-8: 分岐点から経路距離 MIN_JUNCTION_GAP の範囲で、両方の出口の y が分岐点の y ± BRANCH_Y_RANGE
func _check_branch_y(n: int, data: Dictionary) -> void:
	var worst: float = 0.0
	for j: Dictionary in data["junctions"].values():
		var y0: float = data["segments"][j["branches"][0]]["points"][0][1]
		for b: String in j["branches"]:
			var pts := PackedVector2Array()
			for id: String in _section(data, b):
				for p: Array in data["segments"][id]["points"]:
					pts.append(Vector2(p[0], p[1]))
			# 点の間は直線なので、範囲内の点と、ちょうど MIN_JUNCTION_GAP の位置の y を見れば足りる
			var dist: float = 0.0
			for i: int in pts.size():
				if i > 0:
					var step: float = pts[i - 1].distance_to(pts[i])
					if step > 0.0 and dist + step >= Tuning.MIN_JUNCTION_GAP:
						var cut: Vector2 = pts[i - 1].lerp(pts[i], (Tuning.MIN_JUNCTION_GAP - dist) / step)
						worst = maxf(worst, absf(cut.y - y0))
						break
					dist += step
				worst = maxf(worst, absf(pts[i].y - y0))
	_expect(worst <= Tuning.BRANCH_Y_RANGE, "L-8 ステージ%d: 分岐から %d px の範囲で出口の y は分岐点から最大 %.0f px（± %d 以内）" % [
			n, Tuning.MIN_JUNCTION_GAP, worst, Tuning.BRANCH_Y_RANGE])


# --- 走らせる ---

## ルートどおりに分岐を合わせて最後まで走らせる。L-3 の見え方は unseen に足す。戻り値:
## { "cleared": ゴールした, "score": 得点, "arrivals": {wall・jump のキー: 到達速度}, "max_bodies": freeze 解除済み物体の最大数 }
func _drive(data: Dictionary, route: Array, material: Dictionary, unseen: Array[String]) -> Dictionary:
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.stage_data = data.duplicate(true)
	root.add_child(game)
	game.set_process_unhandled_input(false)
	var segs: Dictionary = data["segments"]
	var toggles: int = 0  # 遊ぶ人が切り替える回数（通る分岐のうち、最初の選択先（JSON の default）と違う出口を選ぶ数）
	for i: int in route.size() - 1:
		var end: Dictionary = segs[route[i]]["end"]
		if end["type"] == "junction":
			var junction: Junction = game._junctions[end["id"]]
			var before: int = junction.selected
			junction.selected = junction.branches.find(route[i + 1])
			if junction.selected != before:
				toggles += 1
	var trolley: Trolley = game._trolley
	var arrivals: Dictionary = {}
	var walls: Dictionary = {}  # まだ残っている wall の instance ID → キー（build() は objects の順に標的を作る）
	for i: int in data["objects"].size():
		if data["objects"][i]["type"] == "wall":
			walls[(game._targets[i] as Target).get_instance_id()] = "objects[%d]" % i
	var views: Array = []  # 物理フレームごとの [ゲーム内時刻, 画面に映っている範囲, HUD の札（画面の座標）]
	var last: Array[String] = [route[0]]  # 直前のセグメント（ラムダの中から書き換えるので配列に入れる）
	trolley.segment_entered.connect(func(id: String) -> void:
		var end: Dictionary = segs[last[0]]["end"]
		last[0] = id
		if segs[id].has("jump"):
			arrivals[id] = trolley.speed
		if end["type"] != "junction":
			return
		# L-3: 分岐に着く DECISION_LEAD_TIME 秒前の画面に、判断材料が映っていて、HUD の札に隠れていなかったか
		var at: float = game._time - Tuning.DECISION_LEAD_TIME
		var view: Variant = null
		var panels: Array = []
		for v: Array in views:
			if v[0] <= at:
				view = v[1]
				panels = v[2]
		for m: Array in material[end["id"]]:
			if view == null or not (view as Rect2).has_point(m[1]):
				unseen.append("%s の %s（%s、分岐での速度 %d、位置 %s、1秒前の画面 %s）" % [end["id"], m[0], "-".join(route),
						trolley.speed, m[1], view])
				continue
			var r: Rect2 = view
			var on_screen: Vector2 = ((m[1] as Vector2) - r.position) / r.size * game.get_viewport_rect().size
			if panels.any(func(p: Rect2) -> bool: return p.has_point(on_screen)):
				unseen.append("%s の %s が HUD の札に隠れる（%s、分岐での速度 %d、画面の位置 %s）" % [end["id"], m[0],
						"-".join(route), trolley.speed, on_screen]))
	var max_bodies: int = 0
	for _i: int in MAX_FRAMES:
		if game._finished:
			break
		await physics_frame
		var cam: Camera2D = game._camera
		var size: Vector2 = game.get_viewport_rect().size / cam.zoom
		views.append([game._time, Rect2(cam.position - size * 0.5, size), game._hud_view.panels()])
		max_bodies = maxi(max_bodies, game._active_bodies.size())
		var alive: Dictionary = {}
		for t: Target in game._targets:
			alive[t.get_instance_id()] = true
		for id: int in walls.keys():
			if not alive.has(id):  # 壊れた
				arrivals[walls[id]] = trolley.speed
				walls.erase(id)
		if game.fail_reason == "激突":  # 激突した wall = 残っている wall のうちトロッコに一番近いもの
			var nearest: int = 0
			for id: int in walls:
				var d: float = (instance_from_id(id) as Node2D).global_position.distance_to(trolley.global_position)
				if nearest == 0 or d < (instance_from_id(nearest) as Node2D).global_position.distance_to(trolley.global_position):
					nearest = id
			if nearest != 0:
				arrivals[walls[nearest]] = trolley.speed
	var result: Dictionary = {"cleared": game._finished and game.fail_reason == "", "score": game.score,
			"arrivals": arrivals, "max_bodies": max_bodies}
	var outcome: String = "clear" if result["cleared"] else ("crash" if game.fail_reason == "激突" else "derail")
	var n: int = game._number
	var run: Dictionary = {"stage": n, "outcome": outcome, "max_combo": game.max_combo, "chained": game.chained_count,
			"girigiri": game.girigiri_count, "max_speed": game.max_speed, "toggles": toggles, "score": game.score}
	# 課題の判定に使う走行の記録（ゲーム画面と同じ辞書。切り替えの回数はこの確認が合わせた分）
	result["run"] = (game._run_record(outcome) as Dictionary).duplicate(true)
	result["run"]["toggles"] = toggles
	# 合格の走行は、その試験の合格が記録されているとき（ゴールした経路なら記録される）
	var cleared: Array = []
	cleared.resize(Tuning.STAGE_COUNT)
	cleared.fill(false)
	if n <= Tuning.STAGE_COUNT:
		cleared[n - 1] = result["cleared"]
	if game.girigiri_count > _most_girigiri[0]:
		_most_girigiri = [game.girigiri_count, "%s %s" % [data["id"], "-".join(route)]]
	for id: String in RUN_STAMPS:
		if not _stamps_seen.has(id) and Achievements.earned(id, run, {"smashed": {}}, {"cleared": cleared, "stars": []}):
			_stamps_seen[id] = "%s %s" % [data["id"], "-".join(route)]
	game.free()
	_time_scale.clear()  # 消したゲームのヒットストップ・スローモーを次の走行に持ち越さない
	return result


## 分岐ごとの判断材料（L-3）: 各出口（合流まで）の最初の標的の中心と、wall・jump の必要速度標識の中心。
## { 分岐ID: [[説明, 位置], ...] }
## TODO(spec): 「画面内に見える」は、分岐に着くゲーム内時刻の1.0秒前のフレームで、カメラの表示範囲（揺れのずれは除く）に
##             中心が入っていることとした（半分以上見えている）
func _decision_material(data: Dictionary) -> Dictionary:
	var curves: Dictionary = {}
	for id: String in data["segments"]:
		var curve := Curve2D.new()
		for p: Array in data["segments"][id]["points"]:
			curve.add_point(Vector2(p[0], p[1]))
		curves[id] = curve
	var sign_half: float = Tuning.SIGN_SIZE.y * 0.5
	var out: Dictionary = {}
	for jid: String in data["junctions"]:
		var b: Array = data["junctions"][jid]["branches"]
		var items: Array = []
		for i: int in 2:
			var first_found: bool = false
			for id: String in _own_part(data, b[i], b[1 - i]):
				var curve: Curve2D = curves[id]
				if data["segments"][id].has("jump"):
					items.append(["jump %s の標識" % id, curve.get_point_position(0) + Vector2(0.0, -Tuning.SIGN_JUMP_HEIGHT - sign_half)])
				var here: Array = data["objects"].filter(func(od: Dictionary) -> bool: return od["segment"] == id)
				for od: Dictionary in here:
					if od["type"] == "wall":
						var top: float = (Tuning.TARGET_SIZE["wall"] as Vector2).y
						items.append(["%s の wall の標識" % id,
								curve.sample_baked(od["offset"]) + Vector2(0.0, -top - Tuning.SIGN_WALL_GAP - sign_half)])
				if not first_found and not here.is_empty():
					first_found = true
					here.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return a["offset"] < c["offset"])
					var h: float = (Tuning.TARGET_SIZE[here[0]["type"]] as Vector2).y
					items.append(["%s の最初の標的（%s）" % [id, here[0]["type"]],
							curve.sample_baked(here[0]["offset"]) + Vector2(0.0, -h * 0.5)])
		out[jid] = items
	return out


# --- 経路の計算（検証を通ったデータだけに使う） ---

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


## from から合流をたどり、次の分岐かゴールまでのセグメント
func _section(data: Dictionary, from: String) -> Array[String]:
	var ids: Array[String] = [from]
	while data["segments"][ids.back()]["end"]["type"] == "next":
		ids.append(data["segments"][ids.back()]["end"]["segment"])
	return ids


## 出口 from の、もう一方の出口 other と合流するまでの部分
func _own_part(data: Dictionary, from: String, other: String) -> Array[String]:
	var shared: Array[String] = _section(data, other)
	return _section(data, from).filter(func(id: String) -> bool: return not shared.has(id))


## wall と jump。{ "key": 表示名, "segment": ID, "offset": 位置, "required": 必要速度 }
func _failure_elements(data: Dictionary) -> Array:
	var out: Array = []
	for i: int in data["objects"].size():
		var od: Dictionary = data["objects"][i]
		if od["type"] == "wall":
			out.append({"key": "objects[%d]" % i, "segment": od["segment"], "offset": od["offset"], "required": od["required_speed"]})
	for id: String in data["segments"]:
		if data["segments"][id].has("jump"):
			out.append({"key": id, "segment": id, "offset": 0.0, "required": data["segments"][id]["jump"]["required_speed"]})
	return out


## f（失敗要素）に至る経路のうち、f より手前の標的が最も多い経路。f が空ならゴールまでの標的が最も多い経路
func _richest_route_to(data: Dictionary, routes: Array, f: Dictionary) -> Array:
	var best: Array = []
	var best_count: int = -1
	for route: Array in routes:
		if not f.is_empty() and not route.has(f["segment"]):
			continue
		var count: int = 0
		for od: Dictionary in data["objects"]:
			var i: int = route.find(od["segment"])
			var before: bool = f.is_empty() or i < route.find(f["segment"]) \
					or (od["segment"] == f["segment"] and od["offset"] < f["offset"])
			if i >= 0 and before:
				count += 1
		if count > best_count:
			best = route
			best_count = count
	return best


## route の先頭から count 個のセグメントの長さの合計
func _distance(data: Dictionary, route: Array, count: int) -> float:
	var total: float = 0.0
	for i: int in count:
		total += StageLoader._polyline_length(data["segments"][route[i]]["points"])
	return total


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
