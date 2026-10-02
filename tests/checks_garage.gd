extends SceneTree
## 車庫（車両を選ぶ画面）・車両の絵・ステージ選択とリザルトの車両の表示の自動確認
## （docs/superpowers/specs/2026-09-26-trolleys-and-display-design.md の3章）。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_garage.gd （失敗があれば終了コード1）
## 遊んでいる人の設定・記録を上書きしないよう、GameState の保存先を確認用のファイルに差し替え、最後に消す。
## 画面は change_scene_to_file で開き、キーとクリックは root に送って実際の経路で通す（checks_select.gd と同じ）。
## 車両の絵は headless では描いた結果を読めないので、Trolley.probe（描いた部品の色と点）で見る。

const SELECT_SCENE: String = "res://scenes/stage_select.tscn"
const RESULT_SCENE: String = "res://scenes/result.tscn"
const TEST_SETTINGS: String = "user://checks_garage_settings.cfg"
const TEST_SAVE: String = "user://checks_garage_save.cfg"
const SCENE_WAIT_FRAMES: int = 10  # 画面の切り替えを待つ上限
const SCREEN: Vector2 = Vector2(1280, 720)
const CLEARED: Dictionary = {
	"stage": 3, "stage_name": "立ちはだかる壁", "cleared": true, "score": 3640, "smashed": 24, "total": 30,
	"max_combo": 12, "max_speed": 1085.0, "girigiri": 1, "stars": 2, "thresholds": [2500, 5500],
	"best_updated": true, "is_last": false, "fail_reason": "", "required_speed": 0.0, "reached_speed": 0.0,
	"new_stamps": [], "certificate": false, "trolley": "heavy", "new_trolleys": [],
}
const FAILED: Dictionary = {
	"stage": 3, "stage_name": "立ちはだかる壁", "cleared": false, "score": 1850, "smashed": 9, "total": 30,
	"max_combo": 5, "max_speed": 640.0, "girigiri": 0, "stars": 0, "thresholds": [2500, 5500],
	"best_updated": false, "is_last": false, "fail_reason": "激突", "required_speed": 700.0, "reached_speed": 580.0,
	"new_stamps": [], "certificate": false, "trolley": "light", "new_trolleys": [],
}
const MANY_STAMPS: Array[String] = ["basic", "all_clear", "combo_max", "top_speed", "big_score"]

var _failed: int = 0
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前（GameState など）では参照できない。
# 同じ理由で、autoload を使うスクリプト（stage_select.gd・garage.gd など）の型名や preload もここでは使わない
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
	_game_state.load_settings()
	_game_state.load_records()  # 確認用のファイルが無い = 初期状態から始める
	_audio.played.connect(func(key: StringName) -> void: _sounds.append(key))
	var checks: Array[Callable] = [_check_art, _check_open_close, _check_choose, _check_locked, _check_all_unlocked,
			_check_mouse, _check_select_per_trolley, _check_select_layout, _check_garage_layout, _check_result_row,
			_check_result_new_trolleys]
	for check: Callable in checks:
		# 各確認は最後に true を返す。スクリプトエラーで止まると null が返る
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
	if current_scene != null:
		unload_current_scene()
	_remove_test_files()
	_game_state.settings_path = real_settings
	_game_state.save_path = real_save
	_game_state.load_settings()
	_game_state.load_records()
	# 鳴っている効果音を止め、片付ける音声スレッドが回るまで少しだけ実時間で待つ（checks_ui.gd と同じ）
	for p: Node in _audio.get_children():
		(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	for _i: int in 2:
		await process_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# --- 車両の絵（Trolley.draw_body） ---

# 5台の絵が違う（車体の地の色と、使う色の組み合わせ）。どの絵も外接矩形（TROLLEY_TOP_W × TROLLEY_H）から
# TROLLEY_ART_SLACK より外に出ない。前照灯（HEADLIGHT_AT）は車体の上か、そのすぐ近く。標準型は今までと同じ部品
func _check_art() -> bool:
	var drawn: Dictionary = {}  # id → Trolley.probe の写し
	var canvas := Node2D.new()
	canvas.draw.connect(func() -> void:
		Trolley.probe_on = true
		for id: String in Trolleys.IDS:
			Trolley.probe = []
			Trolley.draw_body(canvas, id)
			drawn[id] = Trolley.probe.duplicate()
		Trolley.probe_on = false
		Trolley.probe = [])
	root.add_child(canvas)
	await process_frame
	await process_frame
	canvas.free()
	if not _expect(drawn.size() == Trolleys.IDS.size(), "5台とも描けた（%d 台）" % drawn.size()):
		return true
	var box := Rect2(-Tuning.TROLLEY_TOP_W * 0.5, -Tuning.TROLLEY_H, Tuning.TROLLEY_TOP_W, Tuning.TROLLEY_H).grow(Tuning.TROLLEY_ART_SLACK)
	var grounds: Array[Color] = []
	var palettes: Array = []
	for id: String in Trolleys.IDS:
		var parts: Array = drawn[id]
		var body_part: Array = parts[0]  # 車体 = 一番大きい多角形（同じ大きさなら先に塗った地。輪郭は後）
		var colors: Array[String] = []
		var outside: Array[Vector2] = []
		for part: Array in parts:
			if _area(part[1]) > _area(body_part[1]):
				body_part = part
			if not colors.has((part[0] as Color).to_html()):
				colors.append((part[0] as Color).to_html())
			for p: Vector2 in part[1]:
				if not box.has_point(p) and not outside.has(p):
					outside.append(p)
		colors.sort()
		palettes.append(colors)
		grounds.append(body_part[0])
		_expect(outside.is_empty(), "%s の絵は外接矩形 %s から出ない（外の点 %s）" % [id, box, outside])
		var body: PackedVector2Array = body_part[1]
		var head: Vector2 = Tuning.HEADLIGHT_AT
		var near: float = 0.0 if Geometry2D.is_point_in_polygon(head, body) else _distance_to_outline(head, body)
		_expect(near <= Tuning.TROLLEY_OUTLINE, "%s の前照灯 %s は車体の上（輪郭から %.1f px）" % [id, head, near])
		print("    %s: 部品 %d 個、色 %d 種" % [id, parts.size(), colors.size()])
	var distinct_ground: bool = true
	var distinct_palette: bool = true
	for i: int in grounds.size():
		for j: int in range(i + 1, grounds.size()):
			distinct_ground = distinct_ground and not grounds[i].is_equal_approx(grounds[j])
			distinct_palette = distinct_palette and palettes[i] != palettes[j]
	_expect(distinct_ground, "5台の車体の地の色はどれも違う（%s）" % [grounds.map(func(c: Color) -> String: return c.to_html(false))])
	_expect(distinct_palette, "5台の絵は使う色の組み合わせがどれも違う")
	var std: Array = drawn[Trolleys.DEFAULT]
	_expect(std[0][0] == Palette.STEEL_LIGHT and std[0][1] == Trolley._body_points(),
			"標準型は今までどおり 16.5 の台形（STEEL のぼかし）")
	_expect(Trolley.silhouette().size() == 3, "影の形（silhouette）は全車両で同じ、車体と車輪2つ")
	return true


## 多角形の面積（点が2つ以下なら 0）
static func _area(poly: PackedVector2Array) -> float:
	var twice: float = 0.0
	for i: int in poly.size():
		twice += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(twice) * 0.5 if poly.size() >= 3 else 0.0


static func _distance_to_outline(p: Vector2, poly: PackedVector2Array) -> float:
	var best: float = INF
	for i: int in poly.size():
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


# --- 車庫の開閉（FR-47a） ---

# ステージ選択の ↑ で「車両を選ぶ」、Enter で車庫を開く。開くと今の車両を選び「この車両にする」にフォーカス。
# Esc と「戻る」で閉じ、車両は変わらない。閉じると「試験開始」にフォーカス
func _check_open_close() -> bool:
	_unlock_heavy()
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var start: Button = s.get_node("%Start")
	var garage_button: Button = s.get_node("%Garage")
	_expect(start.has_focus() and _text(s, "%TrolleyName") == "標準型", "ステージ選択は「試験開始」にフォーカス、詳細パネルに今の車両「%s」" % _text(s, "%TrolleyName"))
	await _key(KEY_UP)
	_expect(garage_button.has_focus(), "↑ で「車両を選ぶ」へ")
	_sounds.clear()
	await _key(KEY_ENTER)
	var g: Control = s.get("_garage")
	if not _expect(g != null and g.get_parent() == s and g.is_visible_in_tree(), "Enter で車庫をステージ選択の上に開く"):
		return true
	_expect(_sounds == [&"ui_select"] and g.get("selected") == 0 and (g.get_node("%Decide") as Button).has_focus(),
			"開くと今の車両（標準型）を選び、「この車両にする」にフォーカス（%s）" % [_sounds])
	_expect((g.get_node("Cards") as Control).get_child_count() == Trolleys.IDS.size(), "カードは %d 枚" % Trolleys.IDS.size())
	_expect(not start.has_focus() and not garage_button.has_focus(), "車庫を開いている間、ステージ選択のボタンにフォーカスは無い")
	await _key(KEY_DOWN)
	_expect((g.get_node("%Back") as Button).has_focus(), "↓ で「戻る」へ")
	await _key(KEY_UP)
	_expect((g.get_node("%Decide") as Button).has_focus(), "↑ で「この車両にする」へ戻る")
	_sounds.clear()
	await _key(KEY_ESCAPE)
	await process_frame
	_expect(s.get("_garage") == null and not is_instance_valid(g) and current_scene == s and _sounds == [&"ui_select"],
			"Esc で車庫だけを閉じ、ステージ選択に戻る（%s）" % [_sounds])
	_expect(_game_state.trolley() == "standard" and start.has_focus(), "閉じても車両は変わらず、「試験開始」にフォーカス")
	await _key(KEY_ESCAPE)
	_expect(await _wait_scene("res://scenes/title.tscn"), "車庫を閉じた後の Esc はタイトルへ（ステージ選択の Esc が効く）")
	s = await _open(SELECT_SCENE)
	await _click(s.get_node("%Garage"))
	g = s.get("_garage")
	_expect(g != null, "「車両を選ぶ」のクリックでも開く")
	if g != null:
		await _click(g.get_node("%Back"))
		await process_frame
		_expect(s.get("_garage") == null and not is_instance_valid(g) and _game_state.trolley() == "standard", "「戻る」のクリックで閉じる")
	return true


# →（解放済み）と Enter で決めると GameState.trolley() が変わって保存され、車庫を閉じる。ステージ選択の表示もその車両になる
func _check_choose() -> bool:
	_unlock_heavy()
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var stage_before: int = s.get("selected")
	var g: Control = await _open_garage(s)
	_sounds.clear()
	await _key(KEY_LEFT)
	_expect(g.get("selected") == 0 and _sounds.is_empty(), "← の端では動かない（音も鳴らさない）")
	await _key(KEY_RIGHT)
	_expect(g.get("selected") == 1 and _sounds == [&"ui_move"] and (g.get_node("%Decide") as Button).has_focus(),
			"→ で重量型を選び ui_move を鳴らす。フォーカスは「この車両にする」のまま（%s）" % [_sounds])
	_sounds.clear()
	await _key(KEY_ENTER)
	await process_frame
	_expect(_game_state.trolley() == "heavy" and s.get("_garage") == null and _sounds == [&"ui_select"],
			"Enter で重量型に決め、車庫を閉じる（%s、%s）" % [_game_state.trolley(), _sounds])
	_expect(s.get("selected") == stage_before, "車庫の ←→ はステージ選択のカードを動かさない")
	_expect(_text(s, "%TrolleyName") == "重量型" and (s.get_node("%Start") as Button).has_focus(),
			"ステージ選択の詳細パネルが重量型になり、「試験開始」にフォーカス（%s）" % _text(s, "%TrolleyName"))
	_game_state.load_settings()
	_expect(_game_state.trolley() == "heavy", "選んだ車両は settings.cfg に残る")
	g = await _open_garage(s)
	_expect(g.get("selected") == 1 and _in_use(g) == [1], "開き直すと重量型を選んでいて、「使用中」の札は重量型だけ（%s）" % [_in_use(g)])
	await _key(KEY_LEFT)
	await _key(KEY_SPACE)
	await process_frame
	_expect(_game_state.trolley() == "standard" and s.get("_garage") == null, "Space でも決める（標準型に戻す）")
	return true


# 未解放の車両: 錠前と解放の条件の文。長所・短所・棒グラフは出さない。選べるが「この車両にする」は「未解放」で押せない
func _check_locked() -> bool:
	_unlock_heavy()
	_game_state.set_trolley("heavy")
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var g: Control = await _open_garage(s)
	var locked_ok: bool = true
	var open_ok: bool = true
	for i: int in Trolleys.IDS.size():
		var id: String = Trolleys.IDS[i]
		var body: Node = _card(g, i).get_node("Body")
		var unlocked: bool = _game_state.is_trolley_unlocked(id)
		if unlocked:
			var pros: String = _text(body, "Traits/Pros")
			var want: String = Trolleys.pros_of(id).replace("・", "\n") if Trolleys.pros_of(id) != "" else "―"
			open_ok = open_ok and pros == want and body.get_node("Traits").visible and body.get_node("Bars").visible \
					and not body.get_node("Picture/Lock").visible and not body.get_node("LockHint").visible
		else:
			locked_ok = locked_ok and body.get_node("Picture/Lock").visible and body.get_node("LockHint").visible \
					and _text(body, "LockHint") == Trolleys.unlock_text(id) and not body.get_node("Traits").visible \
					and not body.get_node("Bars").visible and _text(body, "NameRow/Name") == Trolleys.name_of(id)
	_expect(_game_state.unlocked_trolleys() == ["standard", "heavy"], "第3試験の合格で標準型と重量型が解放（%s）" % [_game_state.unlocked_trolleys()])
	_expect(open_ok, "解放済みのカードは長所・短所（1行に1つ）と棒グラフ、錠前なし")
	_expect(locked_ok, "未解放のカードは錠前・名前・解放の条件（「%s」など）で、長所・短所・棒グラフは出さない" % Trolleys.unlock_text("light"))
	var decide: Button = g.get_node("%Decide")
	_expect(g.get("selected") == 1 and not decide.disabled, "重量型を使っていれば、重量型を選んで開く")
	_sounds.clear()
	await _key(KEY_RIGHT)
	_expect(g.get("selected") == 2 and decide.disabled and decide.text == "未解放" and decide.has_focus() and _sounds == [&"ui_move"],
			"→ で未解放の軽量型にも止まり、「この車両にする」は押せない「未解放」になる（%s、選択 %d、フォーカス %s、%s）" % [
				decide.text, g.get("selected"), decide.has_focus(), _sounds])
	_sounds.clear()
	await _key(KEY_ENTER)
	await _key(KEY_SPACE)
	await process_frame
	_expect(s.get("_garage") == g and _game_state.trolley() == "heavy" and _sounds.is_empty(),
			"未解放を選んでいる間の Enter / Space は何もしない（%s）" % [_sounds])
	await _click(_card(g, 2))
	_expect(s.get("_garage") == g and _game_state.trolley() == "heavy", "未解放の選んでいるカードをクリックしても決まらない")
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	_expect(g.get("selected") == Trolleys.IDS.size() - 1, "→ の端（試作型）で止まる")
	await _key(KEY_LEFT)
	await _key(KEY_LEFT)
	await _key(KEY_LEFT)
	_expect(g.get("selected") == 1 and not decide.disabled and decide.text == "この車両にする", "解放済みに戻ると「この車両にする」が押せる")
	_game_state.set_trolley("light")
	_expect(_game_state.trolley() == "heavy", "未解放の車両は GameState からも選べない")
	return true


# 全部解放（検定印「連鎖反応」「全課程修了」）: 錠前は無く、どの車両も選べる
func _check_all_unlocked() -> bool:
	_unlock_all()
	_expect(_game_state.unlocked_trolleys() == Trolleys.IDS, "全試験の合格と検定印で5台とも解放（%s）" % [_game_state.unlocked_trolleys()])
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	for i: int in Trolleys.IDS.size():
		var g: Control = await _open_garage(s)
		var locks: int = 0
		for k: int in Trolleys.IDS.size():
			if _card(g, k).get_node("Body/Picture/Lock").visible:
				locks += 1
		while g.get("selected") != i:
			await _key(KEY_RIGHT if g.get("selected") < i else KEY_LEFT)
		await _key(KEY_ENTER)
		await process_frame
		_expect(locks == 0 and _game_state.trolley() == Trolleys.IDS[i] and _text(s, "%TrolleyName") == Trolleys.name_of(Trolleys.IDS[i]),
				"%s を選べる（錠前 %d 個）" % [Trolleys.name_of(Trolleys.IDS[i]), locks])
	return true


# マウス: 選んでいないカードのクリックで選び、選んでいるカードのクリックで決める
func _check_mouse() -> bool:
	_unlock_all()
	_game_state.set_trolley("standard")
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var g: Control = await _open_garage(s)
	_sounds.clear()
	await _click(_card(g, 3))
	_expect(g.get("selected") == 3 and _sounds == [&"ui_move"] and s.get("_garage") == g and (g.get_node("%Decide") as Button).has_focus(),
			"選んでいないカード（発破型）のクリックは選ぶだけ（%s）" % [_sounds])
	_sounds.clear()
	await _click(_card(g, 3))
	await process_frame
	_expect(_game_state.trolley() == "blast" and s.get("_garage") == null and _sounds == [&"ui_select"],
			"選んでいるカードをもう一度クリックすると決める（%s）" % [_sounds])
	g = await _open_garage(s)
	await _click(g.get_node("%Decide"))
	await process_frame
	_expect(_game_state.trolley() == "blast" and s.get("_garage") == null, "「この車両にする」のクリックで決める")
	return true


# ステージ選択のカード・詳細パネル・ヘッダーの★と最高スコア・閾値は、選んでいる車両の記録と値。替えたらすぐ変わる
func _check_select_per_trolley() -> bool:
	_game_state.erase_records()
	for n: int in range(1, 4):
		_game_state.submit_clear(n, 1000 * n, 1, "standard")  # 第4試験まで解放・重量型も解放
	_game_state.submit_clear(1, 5200, 3, "heavy")
	_game_state.set_trolley("standard")
	_game_state.current_stage = 1
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var body1: Node = _card(s, 1).get_node("Body")
	var t: Array = _stage_json(1).get("star_thresholds", [])
	_expect(_text(body1, "Stars/Got") == "★" and _text(body1, "Best") == "最高 1,000" and _text(s, "%BestValue") == "1,000"
			and _text(s, "%Total") == "3 / 30",
			"標準型: 第1試験 ★1・1,000、ヘッダー 3 / 30（%s %s %s）" % [_text(body1, "Stars/Got"), _text(body1, "Best"), _text(s, "%Total")])
	var g: Control = await _open_garage(s)
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	await process_frame
	body1 = _card(s, 1).get_node("Body")
	var body2: Node = _card(s, 2).get_node("Body")
	var want2: String = Display.score_text(Trolleys.thresholds("heavy", t)[0]) if t.size() == 2 else "―"
	var want3: String = Display.score_text(Trolleys.thresholds("heavy", t)[1]) if t.size() == 2 else "―"
	_expect(_game_state.trolley() == "heavy" and _text(body1, "Stars/Got") == "★★★" and _text(body1, "Best") == "最高 5,200"
			and _text(s, "%BestValue") == "5,200" and _text(s, "%Total") == "3 / 30",
			"重量型に替えると、第1試験 ★3・5,200、ヘッダーは重量型の★（%s %s %s）" % [_text(body1, "Stars/Got"), _text(body1, "Best"), _text(s, "%Total")])
	_expect(_text(body2, "Best") == "記録なし" and _text(body2, "Stars/Got") == "" and _text(body2, "Name") != "？？？",
			"重量型でまだ走っていない第2試験は「記録なし」（解放はどれかの車両の合格なので、解放のまま）")
	_expect(_text(s, "%Star2Value") == want2 and _text(s, "%Star3Value") == want3,
			"詳細パネルの ★2・★3 は重量型の閾値（%s / %s）" % [_text(s, "%Star2Value"), _text(s, "%Star3Value")])
	_expect(_text(_card(s, 4).get_node("Body"), "Name") != "？？？" and _text(_card(s, 5).get_node("Body"), "Name") == "？？？",
			"試験の解放は車両を替えても同じ（第4試験まで）")
	_game_state.set_trolley("standard")
	s = await _open(SELECT_SCENE)
	_expect(_text(s, "%TrolleyName") == "標準型" and _text(_card(s, 1).get_node("Body"), "Best") == "最高 1,000", "開き直すと標準型の記録")
	return true


# ステージ選択の詳細パネル: 右の列（車両の行と「試験開始」）はパネルの中。説明の列は全試験で文字が入り切る
func _check_select_layout() -> bool:
	_unlock_all()
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var detail: Rect2 = (s.get_node("Detail") as Control).get_global_rect()
	var row: Rect2 = (s.get_node("Detail/TrolleyRow") as Control).get_global_rect()
	var start: Rect2 = (s.get_node("%Start") as Control).get_global_rect()
	var info: Control = s.get_node("Detail/Info")
	var focus_w: float = Tuning.UI_FOCUS_W * 2.0
	_expect(detail.encloses(row.grow(focus_w)) and detail.encloses(start.grow(focus_w)) and not row.grow(focus_w).intersects(start)
			and info.get_global_rect().end.x < row.position.x - focus_w,
			"車両の行（%s）と「試験開始」（%s）はフォーカスの枠ごと詳細パネルの中で、重ならない" % [row, start])
	var too_wide: Array[int] = []
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		s.call("_select", n)
		if info.get_combined_minimum_size().x > info.size.x:
			too_wide.append(n)
	_expect(too_wide.is_empty(), "説明の列（幅 %.0f）に全試験の文字が入る（はみ出す試験 %s）" % [info.size.x, too_wide])
	var name_label: Label = s.get_node("%TrolleyName")
	var widest: float = 0.0
	for id: String in Trolleys.IDS:
		widest = maxf(widest, name_label.get_theme_font(&"font").get_string_size(Trolleys.name_of(id), HORIZONTAL_ALIGNMENT_LEFT, -1,
				name_label.get_theme_font_size(&"font_size")).x)
	_expect(widest <= name_label.size.x, "車両の名前（一番長い %.0f px）は名前の欄（%.0f px）に入る" % [widest, name_label.size.x])
	return true


# 車庫の並び: カードは画面の中で下のボタンに重ならない（選んでいる枠と影ごと）。中身はカードに収まる。絵は絵の枠の中
func _check_garage_layout() -> bool:
	for setup: Callable in [_unlock_heavy, _unlock_all]:
		setup.call()
		var s: Control = await _open(SELECT_SCENE)
		if s == null:
			return true
		var g: Control = await _open_garage(s)
		var screen := Rect2(Vector2.ZERO, SCREEN)
		var bottom: Array[Rect2] = []
		for path: String in ["%Back", "%Decide", "%Help"]:
			bottom.append((g.get_node(path) as Control).get_global_rect().grow(Tuning.UI_FOCUS_W * 2.0))
		var bad: Array[String] = []
		for i: int in Trolleys.IDS.size():
			var card: Control = _card(g, i)
			var r: Rect2 = card.get_global_rect()
			var framed: Rect2 = r.grow(Tuning.UI_FOCUS_W * 2.0).merge(Rect2(r.position + Tuning.SELECT_CARD_SHADOW, r.size))
			var body: Control = card.get_node("Body")
			var pic: Control = card.get_node("Body/Picture")
			var art_w: float = (Tuning.TROLLEY_TOP_W + Tuning.TROLLEY_ART_SLACK * 2.0) * Tuning.GARAGE_PICTURE_SCALE
			var art_top: float = Tuning.GARAGE_PICTURE_RAIL_Y - (Tuning.TROLLEY_H + Tuning.TROLLEY_ART_SLACK) * Tuning.GARAGE_PICTURE_SCALE
			if not screen.encloses(framed) or bottom.any(func(b: Rect2) -> bool: return b.intersects(framed)):
				bad.append("%s の枠 %s" % [Trolleys.IDS[i], framed])
			if body.get_combined_minimum_size().y > body.size.y:
				bad.append("%s の中身の高さ %.0f > %.0f" % [Trolleys.IDS[i], body.get_combined_minimum_size().y, body.size.y])
			if art_w > pic.size.x or art_top < 0.0 or Tuning.GARAGE_PICTURE_RAIL_Y + Tuning.RAIL_WIDTH * Tuning.GARAGE_PICTURE_SCALE * 0.5 > pic.size.y:
				bad.append("%s の絵 %.0f×%.0f の枠" % [Trolleys.IDS[i], pic.size.x, pic.size.y])
		var ids: String = ",".join(_game_state.unlocked_trolleys())
		_expect(bad.is_empty(), "車庫（解放 %s）: カードは画面の中でボタンに重ならず、中身と絵はカードに収まる %s" % [ids, bad])
		var rows: Array[Rect2] = []
		for path: String in ["%Back", "%Decide", "%Help"]:
			rows.append((g.get_node(path) as Control).get_global_rect())
		_expect(not rows[0].intersects(rows[2]) and not rows[1].intersects(rows[2]) and screen.encloses(rows[1].grow(Tuning.UI_FOCUS_W * 2.0)),
				"下の「戻る」・操作説明・「この車両にする」は重ならず、画面の中（%s）" % [rows])
		var head: Rect2 = (g.get_node("Header/Head") as Control).get_global_rect()
		var legend: Label = g.get_node("%Legend")
		var legend_w: float = legend.get_theme_font(&"font").get_string_size(legend.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				legend.get_theme_font_size(&"font_size")).x
		_expect(legend.get_global_rect().end.x - legend_w > head.end.x, "ヘッダーの凡例は見出しに重ならない")
	return true


# リザルト: 試験報告書に「使用車両」の行（合格・不合格とも）。報告書の枠からはみ出さない
func _check_result_row() -> bool:
	for data: Dictionary in [CLEARED, FAILED]:
		var r: Control = await _open_result(data)
		var rows: Dictionary = _rows(r)
		var body: Control = r.get_node("Report/Body")
		var label: String = "合格" if data["cleared"] else "不合格"
		_expect(rows.get("使用車両") == Trolleys.name_of(data["trolley"]) and _row_index(r, "使用車両") == 1,
				"%s の報告書の、試験名のすぐ下に「使用車両 %s」（%s）" % [label, Trolleys.name_of(data["trolley"]), rows.get("使用車両")])
		_expect(body.get_combined_minimum_size().y <= body.size.y,
				"%s の報告書の中身（高さ %.0f）は枠（%.0f）に収まる" % [label, body.get_combined_minimum_size().y, body.size.y])
		r.free()
	var old: Dictionary = CLEARED.duplicate()
	old.erase("trolley")
	old.erase("new_trolleys")
	var r: Control = await _open_result(old)
	_expect(_rows(r).get("使用車両") == "標準型" and not (r.get_node("%NewStamps") as Control).visible,
			"trolley の無いデータは標準型、new_trolleys が無ければ札を出さない")
	r.free()
	return true


# リザルト: 新しく解放された車両を右列の札に知らせる（検定印と一緒なら上の段に車両）。札はボタンに重ならず、ボタンは画面の中
func _check_result_new_trolleys() -> bool:
	for data: Dictionary in [CLEARED, FAILED]:
		var label: String = "合格" if data["cleared"] else "不合格"
		var d: Dictionary = data.duplicate()
		d["new_trolleys"] = ["heavy"]
		var r: Control = await _open_result(d)
		_expect((r.get_node("%NewStamps") as Control).visible and (r.get_node("%TrolleyHead") as Control).visible
				and _trolley_names(r) == ["重量型"] and not (r.get_node("%NewHead") as Control).visible
				and is_equal_approx((r.get_node("Buttons") as Control).position.y, Tuning.RESULT_BUTTONS_Y_CLEARED if data["cleared"] else Tuning.RESULT_BUTTONS_Y_FAILED),
				"%s: 新しい車両だけなら札に「新しい車両 重量型」、検定印の段は出さず、ボタンの位置は今までどおり（%s）" % [label, _trolley_names(r)])
		_expect_slip_fits(r, "%s・車両1台" % label)
		r.free()
		for many: bool in [false, true]:
			d = data.duplicate()
			d["new_trolleys"] = ["light", "blast"]
			d["new_stamps"] = MANY_STAMPS if many else ["chain"]
			d["certificate"] = many and data["cleared"]
			r = await _open_result(d)
			var order: Array[String] = []
			for n: Node in r.get_node("NewStamps/NewBody").get_children():
				if (n as Control).visible:
					order.append(n.name)
			_expect(_trolley_names(r) == ["軽量型", "発破型"] and (r.get_node("%NewHead") as Control).visible
					and order.find("TrolleyList") < order.find("NewHead"),
					"%s: 車両2台と検定印 %d 個は、上の段に車両、下の段に検定印（%s）" % [label, (d["new_stamps"] as Array).size(), order])
			_expect_slip_fits(r, "%s・車両2台と検定印 %d 個" % [label, (d["new_stamps"] as Array).size()])
			r.free()
	return true


## 札（影ごと）は報告書・ボタンのフォーカスの枠に重ならず、ボタン（フォーカスの枠ごと）は画面の中
func _expect_slip_fits(r: Control, label: String) -> void:
	var slip: Rect2 = (r.get_node("%NewStamps") as Control).get_global_rect()
	var with_shadow: Rect2 = slip.merge(Rect2(slip.position + Tuning.UI_PANEL_SHADOW, slip.size))
	var buttons: Control = r.get_node("Buttons")
	var last: Rect2 = Rect2()
	for b: Node in buttons.get_children():
		if (b as Control).visible:
			last = (b as Control).get_global_rect()
	var report: Rect2 = (r.get_node("Report") as Control).get_global_rect()
	_expect(with_shadow.end.y <= buttons.global_position.y - Tuning.UI_FOCUS_W * 2.0 and not with_shadow.intersects(report)
			and Rect2(Vector2.ZERO, SCREEN).encloses(last.grow(Tuning.UI_FOCUS_W * 2.0)),
			"%s: 札（下端 %.0f）はボタン（上端 %.0f）の上、ボタンの下端 %.0f は画面の中" % [label, with_shadow.end.y, buttons.global_position.y, last.end.y])


# --- 補助 ---

## 第3試験まで合格（重量型が解放）。標準型を選ぶ
func _unlock_heavy() -> void:
	_game_state.erase_records()
	for n: int in range(1, 4):
		_game_state.submit_clear(n, 1000, 1)
	_game_state.set_trolley("standard")
	_game_state.current_stage = 1


## 全試験に合格し、検定印「連鎖反応」「全課程修了」を持つ（5台とも解放）
func _unlock_all() -> void:
	var cfg := ConfigFile.new()
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		cfg.set_value("stage_%02d" % n, "cleared", true)
		cfg.set_value("stage_%02d" % n, "best_score", 1000)
		cfg.set_value("stage_%02d" % n, "stars", 1)
	for stamp: String in ["chain", "all_clear"]:
		cfg.set_value("stamps", stamp, "2026-09-26")
	cfg.save(TEST_SAVE)
	_game_state.load_records()
	_game_state.set_trolley("standard")
	_game_state.current_stage = 1


## 車庫を開いて、並びが決まるまで待つ
func _open_garage(s: Control) -> Control:
	s.call("open_garage")
	await process_frame
	await process_frame
	return s.get("_garage")


## 「使用中」の札が出ているカード（Trolleys.IDS の添字）
func _in_use(g: Control) -> Array[int]:
	var out: Array[int] = []
	for i: int in Trolleys.IDS.size():
		if _card(g, i).get_node("Body/NameRow/InUse").visible:
			out.append(i)
	return out


## 画面を開き、切り替わって並びが決まるまで待つ。開けなければ null
func _open(path: String) -> Control:
	change_scene_to_file(path)
	if not await _wait_scene(path):
		_expect(false, "%s が開かない" % path)
		return null
	await process_frame  # コンテナの並べ替えは次のフレーム
	return current_scene


## current_scene が path になるまで数フレーム待つ（change_scene_to_file は次のフレームで切り替わる）
func _wait_scene(path: String) -> bool:
	for _i: int in SCENE_WAIT_FRAMES:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path:
			return true
	return false


## リザルトを開く（ゲーム画面の代わりに root に置く）。コンテナの並べ替えは次のフレーム
func _open_result(data: Dictionary) -> Control:
	if current_scene != null:
		unload_current_scene()
	var r: Control = (load(RESULT_SCENE) as PackedScene).instantiate()
	r.setup(data)
	root.add_child(r)
	await process_frame
	await process_frame
	return r


## 報告書の欄。ラベル → 値（値の部品の文字をつないだもの）
func _rows(r: Control) -> Dictionary:
	var grid: GridContainer = r.get_node("%Grid")
	var out: Dictionary = {}
	for i: int in range(0, grid.get_child_count(), grid.columns):
		var value: String = ""
		for part: Node in grid.get_child(i + 1).get_children():
			value += (part as Label).text
		out[(grid.get_child(i) as Label).text] = value
	return out


## 報告書の欄の何行目か（0 から）
func _row_index(r: Control, label: String) -> int:
	var grid: GridContainer = r.get_node("%Grid")
	for i: int in range(0, grid.get_child_count(), grid.columns):
		if (grid.get_child(i) as Label).text == label:
			return i / grid.columns
	return -1


## 札に並んだ新しい車両の名前
func _trolley_names(r: Control) -> Array[String]:
	var out: Array[String] = []
	for row: Node in r.get_node("%TrolleyList").get_children():
		out.append((row.get_child(1) as Label).text)
	return out


func _card(screen: Control, n: int) -> Control:
	# ステージ選択は試験番号（1 から）、車庫は Trolleys.IDS の添字（0 から）
	return screen.get_node("Cards").get_child(n - 1 if screen.scene_file_path == SELECT_SCENE else n)


func _text(from: Node, path: String) -> String:
	return (from.get_node(path) as Label).text


func _stage_json(n: int) -> Dictionary:
	var path: String = "res://data/stages/stage_%02d.json" % n
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## キーを押して離し、1フレーム進める
func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)
	await process_frame


## c の中央を左クリックして、1フレーム進める（座標は画面の座標）
func _click(c: Control) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = c.get_global_rect().get_center()
		ev.global_position = ev.position
		root.push_input(ev, true)
	await process_frame


func _remove_test_files() -> void:
	for path: String in [TEST_SETTINGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(ok: bool, label: String) -> bool:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
	return ok
