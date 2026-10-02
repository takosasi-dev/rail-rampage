extends SceneTree
## 課題と金★の自動確認（docs/superpowers/specs/2026-09-28-replay-value-design.md の 3章・10章）。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_challenges.gd （失敗があれば終了コード1）
## data/stages/ にある stage_*.json と ex_*.json のすべてについて、全経路を強化なしの標準型で実走し、課題3つが
## どれかの経路・切り替え方で達成できること、gold_threshold に届き ★3 の閾値より上であることを確かめる。
## 車両を名指しする課題（trolley）は、その車両（強化なし）で合格できる経路があることを確かめる。
## 番号を後ろに付けると（例: -- 3 7）そのステージだけ走らせ、経路ごとの結果と金★の目安（最高得点の97%）を出す。
## 「-- ui」ならリザルトとステージ選択の表示の確認だけ（走らせない）。
## 記録と設定は確認用のファイルに差し替え、終わったら消す（遊んでいる人の記録を上書きしない）。

const MAX_FRAMES: int = 20000
const GAME_SCENE: String = "res://scenes/game.tscn"
const RESULT_SCENE: String = "res://scenes/result.tscn"
const SELECT_SCENE: String = "res://scenes/stage_select.tscn"
const STAGE_DIR: String = "res://data/stages/"
const SETTINGS_PATH: String = "user://checks_challenges_settings.cfg"
const SAVE_PATH: String = "user://checks_challenges_save.cfg"
const GOLD_RATIO: float = 0.97  # 金★の目安（設計書 3.2）。表示の目安にだけ使う
const GOLD_STEP: int = 500
const SCENE_WAIT_FRAMES: int = 10

var _failed: int = 0
var _verbose: bool = false
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前では参照できない
var _game_state: Node
var _time_scale: Node


func _initialize() -> void:
	_run.call_deferred()  # _initialize の時点では root がまだツリーに無く、_ready が走らない


func _run() -> void:
	_game_state = root.get_node("GameState")
	_time_scale = root.get_node("TimeScale")
	_game_state.settings_path = SETTINGS_PATH
	_game_state.save_path = SAVE_PATH
	_remove_test_files()
	_game_state.load_settings()
	_game_state.load_records()
	var args: Array = Array(OS.get_cmdline_user_args())
	var ui_only: bool = args.has("ui")
	var only: Array = args.filter(func(a: String) -> bool: return a.is_valid_int()).map(func(a: String) -> int: return a.to_int())
	_verbose = not only.is_empty()
	if not _verbose:
		for check: Callable in [_check_validate, _check_result, _check_select]:
			if await check.call() != true:
				_expect(false, "%s が途中で止まった" % check.get_method())
	if not ui_only:
		_unlock_all_trolleys()
		for n: int in _stage_numbers():
			if _verbose and not only.has(n):
				continue
			if await _check_stage(n) != true:
				_expect(false, "ステージ%d の確認が途中で止まった" % n)
	await _finish()


## data/stages/ にあるステージの番号（stage_NN は NN、ex_NN は EX_FIRST + NN - 1）
func _stage_numbers() -> Array[int]:
	var out: Array[int] = []
	for n: int in range(1, Tuning.EX_FIRST + Tuning.EX_COUNT):
		if FileAccess.file_exists(_game_state.stage_path(n)):
			out.append(n)
	return out


## 全車両を解放する（確認用の記録に全試験の合格と、解放に要る検定印を書く）。強化は無いまま
func _unlock_all_trolleys() -> void:
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		_game_state.submit_clear(n, 1, 1, Trolleys.DEFAULT)
	for u: Dictionary in Tuning.TROLLEY_UNLOCK.values():
		if u.has("stamp"):
			_game_state._stamps[u["stamp"]] = "2026-09-28"


func _finish() -> void:
	if current_scene != null:
		unload_current_scene()
	for p: Node in root.get_node("Audio").get_children():
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	await physics_frame
	await physics_frame
	_remove_test_files()
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


func _remove_test_files() -> void:
	for path: String in [SETTINGS_PATH, SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- 検証（StageLoader.validate） ---

func _check_validate() -> bool:
	var base: Dictionary = StageLoader.load_json(_game_state.stage_path(1))
	_expect(StageLoader.validate(base).is_empty(), "第1試験は検証を通る")
	var cases: Array = [
		["challenges が2つ", "challenges", func(d: Dictionary) -> void: (d["challenges"] as Array).pop_back()],
		["知らない課題の種類", "challenges", func(d: Dictionary) -> void: d["challenges"][0] = {"type": "fly", "value": 1}],
		["gold_threshold が負", "gold_threshold", func(d: Dictionary) -> void: d["gold_threshold"] = -500],
		["gold_threshold が小数", "gold_threshold", func(d: Dictionary) -> void: d["gold_threshold"] = 1000.5],
		["gold_threshold が文字", "gold_threshold", func(d: Dictionary) -> void: d["gold_threshold"] = "abc"],
	]
	for c: Array in cases:
		var d: Dictionary = base.duplicate(true)
		(c[2] as Callable).call(d)
		var errors: Array[String] = StageLoader.validate(d)
		_expect(errors.any(func(e: String) -> bool: return e.contains(c[1])), "%s を違反として返す（%s）" % [c[0], errors])
	var bare: Dictionary = base.duplicate(true)
	bare.erase("challenges")
	bare.erase("gold_threshold")
	_expect(StageLoader.validate(bare).is_empty(), "challenges・gold_threshold が無いステージは検証を通る")
	return true


# --- ステージ ---

func _check_stage(n: int) -> bool:
	var data: Dictionary = StageLoader.load_json(_game_state.stage_path(n))
	var errors: Array[String] = StageLoader.validate(data)
	var title: String = Display.stage_title(n)
	_expect(errors.is_empty(), "%s は検証を通る（%s）" % [title, errors])
	var list: Variant = data.get("challenges")
	_expect(list is Array and (list as Array).size() == Tuning.CHALLENGE_COUNT, "%s に課題が %d つある" % [title, Tuning.CHALLENGE_COUNT])
	_expect(data.get("gold_threshold") is float or data.get("gold_threshold") is int, "%s に gold_threshold がある" % title)
	if not errors.is_empty():
		return true
	var routes: Array = _routes(data)
	var runs: Array = []  # 標準型で全経路を走らせた結果（run の辞書 + "route"）
	for route: Array in routes:
		var run: Dictionary = await _drive(data, route, Trolleys.DEFAULT)
		runs.append(run)
		if _verbose:
			print("    %s %s 得点 %d 切替 %d コンボ %d ギリギリ %d 誘爆 %d 最高 %dkm/h 破壊 %d/%d %s" % [run["route"],
					"合格" if run["outcome"] == "clear" else run["outcome"], run["score"], run["toggles"], run["max_combo"],
					run["girigiri"], run["chained"], Display.to_display_speed(run["max_speed"]), run["smashed_count"],
					run["total"], run["smashed"]])
	var top: int = 0
	for run: Dictionary in runs:
		if run["outcome"] == "clear":
			top = maxi(top, run["score"])
	if _verbose:
		print("    最高得点 %d → 金★の目安 %d（★3 %d）" % [top, floori(top * GOLD_RATIO / GOLD_STEP) * GOLD_STEP,
				data["star_thresholds"][1]])
	var gold: int = int(data.get("gold_threshold", 0))
	_expect(gold > int(data["star_thresholds"][1]), "%s の金★ %d は ★3 %d より上" % [title, gold, data["star_thresholds"][1]])
	_expect(top >= gold, "%s の金★ %d に強化なしの標準型で届く（最高得点 %d）" % [title, gold, top])
	for i: int in (list as Array).size() if list is Array else 0:
		var c: Dictionary = list[i]
		var by: Array = runs
		if c["type"] == "trolley":
			by = []
			for route: Array in routes:
				var run: Dictionary = await _drive(data, route, c["trolley"])
				by.append(run)
				if run["outcome"] == "clear":
					break
		var hit: Array = by.filter(func(run: Dictionary) -> bool: return Challenges.achieved(c, run))
		_expect(not hit.is_empty(), "%s の課題%d「%s」を%sで達成できる（%s）" % [title, i + 1, Challenges.describe(c),
				Trolleys.name_of(c.get("trolley", Trolleys.DEFAULT)), (hit[0] as Dictionary)["route"] if not hit.is_empty() else "どの経路でも無理"])
	return true


## route どおりに分岐を合わせて、車両 trolley（強化なし）で最後まで走らせる。戻り値は Challenges.achieved の run
## （toggles は、通る分岐のうち最初の選択先（JSON の default）と違う出口を選ぶ数 = 遊ぶ人が切り替える回数）と "route"
func _drive(data: Dictionary, route: Array, trolley: String) -> Dictionary:
	_game_state.set_trolley(trolley)
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.stage_data = data.duplicate(true)
	root.add_child(game)
	game.set_process_unhandled_input(false)
	var toggles: int = 0
	for i: int in route.size() - 1:
		var end: Dictionary = data["segments"][route[i]]["end"]
		if end["type"] == "junction":
			var junction: Junction = game._junctions[end["id"]]
			var before: int = junction.selected
			junction.selected = junction.branches.find(route[i + 1])
			if junction.selected != before:
				toggles += 1
	for _i: int in MAX_FRAMES:
		if game._finished:
			break
		await physics_frame
	var outcome: String = "clear" if game._finished and game.fail_reason == "" else "fail"
	var run: Dictionary = (game._run_record(outcome) as Dictionary).duplicate(true)
	run["toggles"] = toggles
	run["route"] = "-".join(route)
	if game.trolley_id != trolley:
		_expect(false, "%s を %s で走らせる（%s になった）" % [run["route"], trolley, game.trolley_id])
	game.free()
	_time_scale.clear()
	_game_state.set_trolley(Trolleys.DEFAULT)
	return run


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


# --- リザルト ---

## 合格の報告書の元（checks_result.gd の値に、やりこみ要素のキーを足したもの）
func _result_data(cleared: bool) -> Dictionary:
	return {
		"stage": 12, "stage_name": "裏の壁", "cleared": cleared, "score": 60000 if cleared else 1850, "smashed": 24,
		"total": 30, "max_combo": 12, "max_speed": 1085.0, "girigiri": 1, "stars": 3 if cleared else 0,
		"thresholds": [30000, 50000], "best_updated": true, "is_last": false, "fail_reason": "" if cleared else "激突",
		"required_speed": 0.0 if cleared else 700.0, "reached_speed": 0.0 if cleared else 580.0,
		"title": "裏試験2", "gold": cleared, "gold_threshold": 58000, "trolley": "heavy",
		"xp": {"gained": 1520, "level_before": 9, "level_after": 11},
		"challenges": [
			{"text": "巻き込まれたドラム缶を15個以上爆発させて合格する", "done": true, "new": true},
			{"text": "ギリギリ突破を1回以上して合格する", "done": true, "new": false},
			{"text": "分岐の切り替え1回以下で合格する", "done": false, "new": false}],
	}


func _check_result() -> bool:
	var r: Control = await _open_result(_result_data(true))
	var rows: Dictionary = _result_rows(r)
	_expect(rows.get("試験名") == "裏試験2　裏の壁", "リザルトの見出しは title（%s）" % rows.get("試験名"))
	_expect(rows.get("重量型の熟練度") == "+1,52011段に上がった強化のポイント +2",
			"熟練度の行: 車両の名前・「+N」・段が上がった札・強化のポイント（%s）" % rows.get("重量型の熟練度"))
	var lines: Array = (rows.get("課題", "") as String).split("\n")
	_expect(lines == ["巻き込まれたドラム缶を15個以上爆発させて合格する", "ギリギリ突破を1回以上して合格する", "分岐の切り替え1回以下で合格する"],
			"合格の報告書に課題3つの行（%s）" % [lines])
	var box: Control = r.find_child("Challenges", true, false)
	var fresh: Label = box.get_child(0)
	var marks: Array = box.get_children().map(func(l: Node) -> Control: return l.get_child(0))
	_expect(fresh.get_theme_stylebox(&"normal") is StyleBoxFlat and not ((box.get_child(1) as Label).get_theme_stylebox(&"normal") is StyleBoxFlat),
			"今回達成した課題だけ警告黄の地で目立たせる")
	_expect(marks[0].modulate.a == 0.0 and marks[1].modulate.a > 0.0, "今回達成した課題の丸印は判子の後に押す（開いた時点では透明）")
	var gold: Control = r.find_child("GoldStar", true, false)
	_expect(gold != null and not r.get("_gold_shown") and not (r.get_node("%Remain") as Control).visible,
			"金★を取った走行: ★3 の右に金★の枠。判子の前は塗らない。「あと N 点」は出さない")
	var stars: Control = r.get_node("%Stars")
	_expect(gold != null and gold.position.x >= stars.custom_minimum_size.x - Tuning.RESULT_STAR_SIZE - 0.5
			and gold.position.x > Tuning.STARS_MAX * Tuning.RESULT_STAR_SIZE, "金★は★3 の右（%s）" % [gold.position if gold else null])
	var wait: float = Tuning.RESULT_STAMP_DELAY + Tuning.RESULT_NEW_MARK_INTERVAL * 2.0 + Tuning.RESULT_STAMP_POP_TIME
	for _i: int in ceili(wait * 60.0) + 3:
		await process_frame
	_expect(r.get("_gold_shown") == true and marks[0].modulate.a > 0.0 and marks[0].scale.is_equal_approx(Vector2.ONE),
			"判子の後に金★を塗り、今回達成した課題の丸印を押す")
	_expect_report_fits(r, "合格・課題3つ・段が上がった")
	r.free()

	# ★3 で金★を取れなかったとき: 金★は枠だけで「金★まで あと N 点」
	var d: Dictionary = _result_data(true)
	d["gold"] = false
	d["score"] = 55000
	r = await _open_result(d)
	var remain: String = ""
	for l: Node in r.get_node("%Remain").get_children():
		remain += (l as Label).text
	_expect((r.get_node("%Remain") as Control).visible and remain == "金★まで あと 3,000 点", "★3 で金★に届かなければ「%s」" % remain)
	for _i: int in ceili(wait * 60.0) + 3:
		await process_frame
	_expect(r.get("_gold_shown") == false, "金★を取っていない走行では金★を塗らない")
	r.free()

	# 不合格: 熟練度は出す。課題・金★は出さない。段が上がらなければ札は無い
	d = _result_data(false)
	d["xp"] = {"gained": 18, "level_before": 3, "level_after": 3}
	r = await _open_result(d)
	rows = _result_rows(r)
	_expect(rows.get("重量型の熟練度") == "+18" and not rows.has("課題") and r.find_child("GoldStar", true, false) == null,
			"不合格の報告書: 熟練度の行（%s）は出し、課題と金★は出さない" % rows.get("重量型の熟練度"))
	_expect_report_fits(r, "不合格・熟練度")
	r.free()

	# 全ステージの課題の文が報告書の値の列に収まる（今回達成の地を付けた太字でも）
	for n: int in _stage_numbers():
		d = _result_data(true)
		var list: Array = StageLoader.load_json(_game_state.stage_path(n)).get("challenges", [])
		d["challenges"] = list.map(func(c: Dictionary) -> Dictionary: return {"text": Challenges.describe(c), "done": true, "new": true})
		r = await _open_result(d)
		_expect_report_fits(r, "%s の課題" % Display.stage_title(n))
		r.free()
	return true


## 報告書の中身は枠に収まり、報告書（影ごと）は画面の中で、右列のボタンに重ならない
func _expect_report_fits(r: Control, label: String) -> void:
	var body: Control = r.get_node("Report/Body")
	var report: Rect2 = (r.get_node("Report") as Control).get_global_rect()
	var with_shadow: Rect2 = report.merge(Rect2(report.position + Tuning.UI_PANEL_SHADOW, report.size))
	var min_size: Vector2 = body.get_combined_minimum_size()
	var buttons: Rect2 = (r.get_node("Buttons") as Control).get_global_rect()
	_expect(min_size.x <= body.size.x and min_size.y <= body.size.y and Rect2(Vector2.ZERO, r.size).encloses(with_shadow)
			and not with_shadow.intersects(buttons.grow(Tuning.UI_FOCUS_W * 2.0)),
			"%s: 報告書の中身（%s）は枠（%s）に収まり、報告書は画面の中でボタンに重ならない" % [label, min_size, body.size])


func _open_result(data: Dictionary) -> Control:
	var r: Control = (load(RESULT_SCENE) as PackedScene).instantiate()
	r.setup(data)
	root.add_child(r)
	await process_frame
	return r


## 報告書の欄。ラベル → 値（値の部品の文字をつないだもの。縦に並べた行は改行でつなぐ）
func _result_rows(r: Control) -> Dictionary:
	var grid: GridContainer = r.get_node("%Grid")
	var out: Dictionary = {}
	for i: int in range(0, grid.get_child_count(), grid.columns):
		var value: String = ""
		for part: Node in grid.get_child(i + 1).get_children():
			if part is Label:
				value += (part as Label).text
			else:
				value += "\n".join(part.get_children().map(func(l: Node) -> String: return (l as Label).text))
		out[(grid.get_child(i) as Label).text] = value
	return out


# --- ステージ選択 ---

func _check_select() -> bool:
	_game_state.load_records()
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		_game_state.submit_clear(n, 1, 1, Trolleys.DEFAULT, n == 1)
	var list1: Array = StageLoader.load_json(_game_state.stage_path(1))["challenges"]
	# 第1試験の課題1（分岐を切り替えない）だけを達成した走行
	var run: Dictionary = {"stage": 1, "outcome": "clear", "smashed": {}, "girigiri": 0, "max_combo": 0, "max_speed": 0.0,
			"distance": 0.0, "chained": 0, "toggles": 0, "score": 1, "trolley": Trolleys.DEFAULT, "total": 81, "smashed_count": 0}
	_expect(_game_state.submit_challenges(1, list1, run) == [0], "確認用の記録に第1試験の課題1の達成を書く")
	var s: Control = (load(SELECT_SCENE) as PackedScene).instantiate()
	root.add_child(s)
	await process_frame
	s.call("_select", 1)
	await process_frame
	var card1: Control = s.get_node("Cards").get_child(0)
	var card2: Control = s.get_node("Cards").get_child(1)
	_expect((card1.get_node("Body/Stars/Gold") as Control).visible and not (card2.get_node("Body/Stars/Gold") as Control).visible,
			"カード: 金★を取った試験だけ金色の★")
	_expect((card1.get_node("Body/Stars/Tasks") as Label).text == "課題 1/3" and (card2.get_node("Body/Stars/Tasks") as Label).text == "課題 0/3",
			"カード: 課題の達成数（%s, %s）" % [(card1.get_node("Body/Stars/Tasks") as Label).text, (card2.get_node("Body/Stars/Tasks") as Label).text])
	_expect((s.get_node("%GoldValue") as Label).text == "18,500", "詳細パネルに金★の閾値（%s）" % (s.get_node("%GoldValue") as Label).text)
	var box: Control = s.get_node("%Challenges")
	var texts: Array = box.get_children().map(func(l: Node) -> String: return (l as Label).text)
	_expect(texts == list1.map(func(c: Dictionary) -> String: return Challenges.describe(c)) and s.get("_detail_done") == [true, false, false],
			"詳細パネルに課題3つの文と達成の印（%s %s）" % [texts, s.get("_detail_done")])
	# 全試験で、カードの★の行と詳細パネルの中身が枠に収まり、詳細パネルはカード・「戻る」に重ならない
	var info: Control = s.get_node("Detail/Info")
	var detail: Rect2 = (s.get_node("Detail") as Control).get_global_rect()
	var cards: Rect2 = (s.get_node("Cards") as Control).get_global_rect()
	var back: Rect2 = (s.get_node("%Back") as Control).get_global_rect()
	var bad: Array[int] = []
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		s.call("_select", n)
		await process_frame
		var stars: Control = s.get_node("Cards").get_child(n - 1).get_node("Body/Stars")
		var min_size: Vector2 = info.get_combined_minimum_size()
		if min_size.x > info.size.x or min_size.y > info.size.y or stars.get_combined_minimum_size().x > stars.size.x \
				or not detail.encloses(info.get_global_rect()):
			bad.append(n)
	_expect(bad.is_empty(), "全試験でカードの★の行と詳細パネルの中身が枠に収まる（はみ出す試験 %s）" % [bad])
	_expect(not detail.intersects(cards.grow_individual(0, 0, Tuning.SELECT_CARD_SHADOW.x, Tuning.SELECT_CARD_SHADOW.y))
			and not detail.intersects(back.grow(Tuning.UI_FOCUS_W * 2.0)) and Rect2(Vector2.ZERO, s.size).encloses(detail),
			"詳細パネル（%s）はカードの影・「戻る」のフォーカスの枠に重ならず、画面の中" % [detail])
	s.free()
	return true


func _expect(ok: bool, label: String) -> void:
	if ok and _verbose and not label.contains("課題") and not label.contains("金★"):
		return
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
