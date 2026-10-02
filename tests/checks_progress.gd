extends SceneTree
## 車庫のやりこみ（熟練度・強化・塗装）の自動確認（docs/superpowers/specs/2026-09-28-replay-value-design.md の5章）。
## 塗装の絵、車庫のカードの熟練度、整備パネルの操作（強化・ポイント不足・最大・振り直し・塗装・錠前）、
## ステージ選択・ゲーム画面のトロッコ・激突後の車体に塗装が渡ること、強化がゲームに効くこと。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_progress.gd （失敗があれば終了コード1）
## 保存先は確認用のファイルに差し替え、最後に消す。キーとクリックは root に送る（checks_garage.gd と同じ）。
## 壁の必要速度・コンボの受付の強化は checks_save.gd が見るので、ここでは他の項目を見る。

const SELECT_SCENE: String = "res://scenes/stage_select.tscn"
const GAME_SCENE: String = "res://scenes/game.tscn"
const TEST_SETTINGS: String = "user://checks_progress_settings.cfg"
const TEST_SAVE: String = "user://checks_progress_save.cfg"
const SCENE_WAIT_FRAMES: int = 10
const SCREEN: Vector2 = Vector2(1280, 720)
const RAIL_Y: float = 600.0

var _failed: int = 0
var _gs: Node  # autoload（-s のスクリプトでは名前で参照できない）
var _audio: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_audio = root.get_node("Audio")
	var real_settings: String = _gs.settings_path
	var real_save: String = _gs.save_path
	_gs.settings_path = TEST_SETTINGS
	_gs.save_path = TEST_SAVE
	var checks: Array[Callable] = [_check_paint_art, _check_mastery_card, _check_workshop_keys, _check_upgrades,
			_check_reset, _check_paints, _check_locked_trolley, _check_workshop_layout, _check_paint_elsewhere,
			_check_game_paint, _check_game_upgrades]
	for check: Callable in checks:
		_reset()
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
		if current_scene != null:
			unload_current_scene()
		await process_frame
	_remove_test_files()
	_gs.settings_path = real_settings
	_gs.save_path = real_save
	_gs.load_settings()
	_gs.load_records()
	for p: Node in _audio.get_children():
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	for _i: int in 2:
		await process_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


func _reset() -> void:
	_remove_test_files()
	_gs.load_settings()
	_gs.load_records()
	_gs.current_stage = 1


# --- 塗装の絵 ---

# 5台 × 塗装5つ: 塗装ごとに車体の地の色が違い、絵は外接矩形から出ない。塗装0は今までの色。
# 車体の上の色は夜・深夜でも見える明るさ（標準型の既定の色の 9割以上）。名前と色の組は塗装の数だけある
func _check_paint_art() -> bool:
	var count: int = Tuning.PAINT_UNLOCK_LEVELS.size()
	var box := Rect2(-Tuning.TROLLEY_TOP_W * 0.5, -Tuning.TROLLEY_H, Tuning.TROLLEY_TOP_W, Tuning.TROLLEY_H).grow(Tuning.TROLLEY_ART_SLACK)
	var dark: Array[String] = []
	var same: Array[String] = []
	var outside: Array[String] = []
	var counts_ok: bool = true
	for id: String in Trolleys.IDS:
		counts_ok = counts_ok and (Palette.TROLLEY_PAINTS[id] as Array).size() == count and (Trolley.PAINT_NAMES[id] as Array).size() == count
		var grounds: Array[Color] = []
		for p: int in count:
			var parts: Array = await _probe_draw(func(ci: CanvasItem) -> void: Trolley.draw_body(ci, id, p))
			for part: Array in parts:
				for pt: Vector2 in part[1]:
					if not box.has_point(pt) and not outside.has("%s/%d" % [id, p]):
						outside.append("%s/%d" % [id, p])
			var ground: Color = _body_color(parts)
			if ground.get_luminance() < Palette.STEEL_LIGHT.get_luminance() * 0.9:
				dark.append("%s/%d %s" % [id, p, ground.to_html(false)])
			for g: Color in grounds:
				if g.is_equal_approx(ground):
					same.append("%s/%d" % [id, p])
			grounds.append(ground)
		_expect(grounds[0] == (Palette.TROLLEY_PAINTS[id][0]["body"] as Array)[0], "%s の塗装0は今までの色（%s）" % [id, grounds[0].to_html(false)])
	_expect(counts_ok, "5台とも塗装の色の組と名前が %d つ" % count)
	_expect(same.is_empty(), "塗装ごとに車体の地の色が違う（同じ色 %s）" % [same])
	_expect(outside.is_empty(), "どの塗装も絵は外接矩形から出ない（%s）" % [outside])
	_expect(dark.is_empty(), "車体の上の色は夜でも見える明るさ（暗い %s）" % [dark])
	_expect(Trolley.paint_name("standard", 4) == "金" and Trolley.paint_name("heavy", 0) == "既定" and Trolley.paint_name("nope", 99) == "金",
			"塗装の名前（最後は「金」、範囲外は端に寄せる）")
	var std: Array = await _probe_draw(func(ci: CanvasItem) -> void: Trolley.draw_body(ci))
	_expect(std[0][0] == Palette.STEEL_LIGHT, "引数なしの draw_body は標準型の既定の色")
	return true


## 車体 = 一番大きい多角形の色（同じ大きさなら先に塗った地）
static func _body_color(parts: Array) -> Color:
	var best: Array = parts[0]
	for part: Array in parts:
		if _area(part[1]) > _area(best[1]):
			best = part
	return best[0]


# --- 車庫のカード ---

# カードに「熟練 ◯段」。最大の段は「（最高）」。未解放の車両は出さない。棒グラフは強化込み（強化で伸びる）
func _check_mastery_card() -> bool:
	_unlock_heavy()
	_gs.add_xp("standard", _xp_for(6) + 10)
	_gs.add_xp("heavy", _xp_for(Tuning.LEVEL_MAX))
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var g: Control = await _open_garage(s)
	_expect(_card_text(g, 0, "Body/Mastery/Level") == "熟練 6段" and _card_text(g, 1, "Body/Mastery/Level") == "熟練 25段（最高）"
			and (_card(g, 0).get_node("Body/Mastery") as Control).visible,
			"カードに熟練度（%s / %s）" % [_card_text(g, 0, "Body/Mastery/Level"), _card_text(g, 1, "Body/Mastery/Level")])
	_expect(not (_card(g, 2).get_node("Body/Mastery") as Control).visible, "未解放の車両のカードに熟練度は出さない")
	var before: float = g.call("strength", "standard", "hit_power", false, {})
	var after: float = g.call("strength", "standard", "hit_power", false, {"hit_power": 3})
	_expect(after > before and is_equal_approx(after, before * 1.15), "棒グラフの強さは強化込み（%.2f → %.2f）" % [before, after])
	return true


# --- 整備パネル ---

# 「整備」は ↑↓ で回る（この車両にする → 戻る → 整備）。E か「整備」で開き、強化の1行目にフォーカス。
# 開いている間の ←→ は車両を替えない。E・Esc で閉じ、「整備」にフォーカス。もう一度 Esc で車庫を閉じる
func _check_workshop_keys() -> bool:
	_unlock_heavy()
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var g: Control = await _open_garage(s)
	var ws: Control = g.get_node("%Workshop")
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	_expect((g.get_node("%Maintain") as Button).has_focus(), "↓↓ で「この車両にする」→「戻る」→「整備」")
	await _key(KEY_ENTER)
	_expect(ws.visible and _up(g, "hit_power").has_focus() and _text(g, "%WsName") == "標準型",
			"「整備」で標準型の整備パネルを開き、強化の1行目にフォーカス")
	await _key(KEY_RIGHT)
	await _key(KEY_LEFT)
	_expect(g.get("selected") == 0 and ws.visible, "整備パネルの ←→ は車両を替えない")
	await _key(KEY_ESCAPE)
	_expect(not ws.visible and s.get("_garage") == g and (g.get_node("%Maintain") as Button).has_focus(),
			"Esc で整備パネルだけを閉じ、「整備」にフォーカス")
	await _key(KEY_RIGHT)
	await _key(KEY_E)
	_expect(ws.visible and _text(g, "%WsName") == "重量型", "→ で重量型を選び E で重量型の整備パネル")
	await _key(KEY_E)
	_expect(not ws.visible, "E でも閉じる")
	await _click(g.get_node("%Maintain"))
	_expect(ws.visible, "「整備」のクリックでも開く")
	await _click(g.get_node("%Close"))
	_expect(not ws.visible, "「戻る」のクリックで閉じる")
	await _key(KEY_ESCAPE)
	await process_frame
	_expect(s.get("_garage") == null, "整備パネルを閉じた後の Esc は車庫を閉じる")
	return true


# 強化: 押すと1段上がりポイントが減る。段・効き目の文・値段が変わる。最大の段とポイント不足は上がらず理由を出す
func _check_upgrades() -> bool:
	_unlock_heavy()
	_gs.add_xp("standard", _xp_for(6))  # 段6 = 5ポイント
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var g: Control = await _open_garage(s)
	await _key(KEY_E)
	_expect(_text(g, "%WsPoints") == "残り 5 ポイント" and _text(g, "%WsLevel") == "熟練 6段", "見出しに段と残りのポイント（%s）" % _text(g, "%WsPoints"))
	_expect(_row(g, "Steps", "hit_power") == "□□□" and _row(g, "Effect", "hit_power") == "吹っ飛ばす力 ±0% → +5%"
			and _row(g, "Cost", "hit_power") == "1 ポイント",
			"強化前の行（%s %s %s）" % [_row(g, "Steps", "hit_power"), _row(g, "Effect", "hit_power"), _row(g, "Cost", "hit_power")])
	await _key(KEY_ENTER)
	_expect(_gs.garage("standard")["upgrades"] == {"hit_power": 1} and _text(g, "%WsPoints") == "残り 4 ポイント"
			and _row(g, "Steps", "hit_power") == "■□□" and _row(g, "Effect", "hit_power") == "吹っ飛ばす力 +5% → +10%",
			"Enter で吹っ飛ばす力を1段（%s、%s）" % [_gs.garage("standard")["upgrades"], _row(g, "Effect", "hit_power")])
	for _i: int in 3:
		await _click(_up(g, "wall_factor"))
	_expect(_gs.garage("standard")["upgrades"].get("wall_factor") == 3 and _text(g, "%WsPoints") == "残り 0 ポイント"
			and _row(g, "Effect", "wall_factor") == "壁の必要速度 −9%" and _row(g, "Cost", "wall_factor") == "最大",
			"クリック3回で壁に強くを最大（1+1+2 ポイント。%s・%s）" % [_row(g, "Effect", "wall_factor"), _row(g, "Cost", "wall_factor")])
	await _click(_up(g, "wall_factor"))
	_expect(_gs.garage("standard")["upgrades"].get("wall_factor") == 3 and _text(g, "%Message").contains("最大"),
			"最大の段は上がらず「最大の段」（%s）" % _text(g, "%Message"))
	await _click(_up(g, "blast_radius"))
	_expect(not _gs.garage("standard")["upgrades"].has("blast_radius") and _text(g, "%Message").contains("ポイントが足りない")
			and _row(g, "Cost", "blast_radius") == "1 ポイント",
			"ポイント不足は上がらず「ポイントが足りない」（%s）" % _text(g, "%Message"))
	var eff: Array[String] = []
	for item: String in Progression.upgrade_ids():
		eff.append(g.call("effect_text", item, 2))
	_expect(eff == ["吹っ飛ばす力 +10%", "爆発の範囲 +10%", "コンボの受付時間 +10%", "ギリギリ突破の幅 +40%", "壁の必要速度 −6%",
			"ジャンプの必要速度 −6%"], "効き目の文（2段）%s" % [eff])
	_expect(not Progression.upgrade_ids().has("speed_max") and not Progression.upgrade_ids().has("speed_base")
			and not Progression.upgrade_ids().has("momentum_gain"), "速さに効く強化は無い（設計書 5.2）")
	return true


# 振り直し: 確認を出す（Esc・「やめる」は戻さない）。「振り直す」で全部戻りポイントが返る
func _check_reset() -> bool:
	_unlock_heavy()
	_gs.add_xp("standard", _xp_for(4))
	_gs.buy_upgrade("standard", "combo_window")
	_gs.buy_upgrade("standard", "jump_factor")
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var g: Control = await _open_garage(s)
	await _key(KEY_E)
	var confirm: Control = g.get_node("%Confirm")
	await _click(g.get_node("%Reset"))
	_expect(confirm.visible and (g.get_node("%ResetNo") as Button).has_focus() and not (g.get_node("%Reset") as Control).visible,
			"「振り直し」で確認を出し、「やめる」にフォーカス")
	await _key(KEY_ESCAPE)
	_expect(not confirm.visible and (g.get_node("%Workshop") as Control).visible and _gs.garage("standard")["upgrades"].size() == 2
			and (g.get_node("%Reset") as Button).has_focus(), "確認中の Esc は確認だけ閉じ、強化はそのまま")
	await _click(g.get_node("%Reset"))
	await _click(g.get_node("%ResetNo"))
	_expect(not confirm.visible and _gs.garage("standard")["upgrades"].size() == 2, "「やめる」は戻さない")
	await _click(g.get_node("%Reset"))
	await _click(g.get_node("%ResetYes"))
	_expect(not confirm.visible and _gs.garage("standard")["upgrades"].is_empty() and _text(g, "%WsPoints") == "残り 3 ポイント"
			and _row(g, "Steps", "combo_window") == "□□□", "「振り直す」で全部戻り、ポイントが返る（%s）" % _text(g, "%WsPoints"))
	return true


# 塗装: 使える塗装を押すと選ぶ（保存・カードの絵も変わる）。使えない塗装は錠前と「◯段で解放」で、押しても選ばない
func _check_paints() -> bool:
	_unlock_heavy()
	_gs.add_xp("standard", _xp_for(5))  # 段5 = 塗装2つ
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var g: Control = await _open_garage(s)
	await _key(KEY_E)
	var labels: Array[String] = []
	var locks: Array[bool] = []
	for p: int in Tuning.PAINT_UNLOCK_LEVELS.size():
		var b: Node = g.get_node("%PaintGrid").get_child(p)
		labels.append((b.get_node("Name") as Label).text)
		locks.append((b.get_node("Lock") as Control).visible)
	_expect(labels == ["既定", "朱", "10段で解放", "15段で解放", "25段で解放"] and locks == [false, false, true, true, true],
			"段5: 塗装は既定・朱が使え、残りは錠前と「◯段で解放」（%s）" % [labels])
	await _click(_paint(g, 1))
	_expect(_gs.garage("standard")["paint"] == 1, "朱を押すと選ぶ")
	var colors: Array = await _probe_colors(_card(g, 0).get_node("Body/Picture"))
	_expect(colors.has(Palette.TROLLEY_PAINTS["standard"][1]["body"][0]), "カードの絵が朱になる")
	await _click(_paint(g, 3))
	_expect(_gs.garage("standard")["paint"] == 1 and _text(g, "%Message").contains("15段で解放"),
			"使えない塗装は押しても選ばない（%s）" % _text(g, "%Message"))
	_gs.load_records()
	_expect(_gs.garage("standard")["paint"] == 1, "選んだ塗装は保存される")
	# キーボード: 塗装のボタンへ移って Space で選ぶ
	g.get_node("%PaintGrid").get_child(0).grab_focus()
	await _key(KEY_SPACE)
	_expect(_gs.garage("standard")["paint"] == 0, "Space でも塗装を選ぶ（既定に戻す）")
	return true


# 未解放の車両は整備できない（「整備」は押せず、E でも開かない）
func _check_locked_trolley() -> bool:
	_unlock_heavy()
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var g: Control = await _open_garage(s)
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	await _key(KEY_E)
	_expect(g.get("selected") == 2 and (g.get_node("%Maintain") as Button).disabled and not (g.get_node("%Workshop") as Control).visible,
			"未解放の軽量型は「整備」が押せず、E でも開かない")
	g.call("open_workshop")
	_expect(not (g.get_node("%Workshop") as Control).visible, "open_workshop も未解放では開かない")
	return true


# 整備パネルは画面の中で、中身がパネルに収まる。車庫の下のボタンは重ならない
func _check_workshop_layout() -> bool:
	_unlock_heavy()
	_gs.add_xp("standard", _xp_for(Tuning.LEVEL_MAX))
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var g: Control = await _open_garage(s)
	await _key(KEY_E)
	await process_frame
	var panel: Control = g.get_node("Workshop/Panel")
	var r: Rect2 = panel.get_global_rect()
	var body: Control = g.get_node("Workshop/Panel/Body")
	_expect(Rect2(Vector2.ZERO, SCREEN).encloses(r.merge(Rect2(r.position + Tuning.UI_PANEL_SHADOW, r.size))),
			"整備パネル %s は影ごと画面の中" % r)
	_expect(r.encloses(body.get_global_rect()), "中身 %s はパネルの中" % body.get_global_rect())
	var rows: Array[Rect2] = []
	for path: String in ["%Back", "%Help", "%Maintain", "%Decide"]:
		rows.append((g.get_node(path) as Control).get_global_rect())
	var overlap: bool = false
	for i: int in rows.size():
		for j: int in range(i + 1, rows.size()):
			overlap = overlap or rows[i].intersects(rows[j])
	_expect(not overlap, "車庫の下の「戻る」・操作説明・「整備」・「この車両にする」は重ならない（%s）" % [rows])
	var help: Label = g.get_node("%Help")
	var help_w: float = help.get_theme_font(&"font").get_string_size(help.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			help.get_theme_font_size(&"font_size")).x
	_expect(help_w <= help.size.x, "操作説明（%.0f px）は欄（%.0f px）に入る" % [help_w, help.size.x])
	return true


# --- 他の画面への塗装の受け渡し ---

# ステージ選択の詳細パネルの車両の絵は、選んでいる車両の塗装
func _check_paint_elsewhere() -> bool:
	_gs.add_xp("standard", _xp_for(10))
	_gs.set_paint("standard", 2)
	var s: Control = await _open(SELECT_SCENE)
	if s == null:
		return true
	var colors: Array = await _probe_colors(s.get_node("%TrolleyIcon"))
	_expect(colors.has(Palette.TROLLEY_PAINTS["standard"][2]["body"][0]), "ステージ選択の詳細パネルの車両は塗装の色")
	return true


# ゲーム画面のトロッコと、激突後の車体に塗装が渡る
func _check_game_paint() -> bool:
	_gs.add_xp("standard", _xp_for(Tuning.LEVEL_MAX))
	_gs.set_paint("standard", 4)
	var gold: Color = Palette.TROLLEY_PAINTS["standard"][4]["body"][0]
	var game: Node = _new_game(_straight([]))
	await _frames(2)
	var trolley: Trolley = game.get("_trolley")
	var colors: Array = await _probe_colors(trolley.visual)
	_expect(trolley.paint == 4 and colors.has(gold), "ゲーム画面のトロッコは金の塗装（%d）" % trolley.paint)
	game.call("_fail", "激突", 600.0)
	await _frames(2)
	var wreck: TrolleyWreck = game.get("_wreck")
	if _expect(wreck != null, "激突で車体が残る"):
		colors = await _probe_colors(wreck.visual)
		_expect(wreck.paint == 4 and colors.has(gold), "激突後の車体も金の塗装（%d）" % wreck.paint)
	game.free()
	return true


# 強化がゲームに効く（吹っ飛ばす力・爆発の範囲・ギリギリの幅・ジャンプの必要速度。壁とコンボは checks_save）
func _check_game_upgrades() -> bool:
	_unlock_heavy()  # 先に解放する（解放されていない車両の経験値は標準型に付く）
	_gs.add_xp("heavy", _xp_for(Tuning.LEVEL_MAX))
	for item: String in ["hit_power", "hit_power", "blast_radius", "girigiri_margin", "jump_factor", "jump_factor", "jump_factor"]:
		_gs.buy_upgrade("heavy", item)
	_gs.set_trolley("heavy")
	var game: Node = _new_game(_straight([]))
	await _frames(2)
	_expect(is_equal_approx(game.call("stat", "hit_power"), Trolleys.stat("heavy", "hit_power") * 1.1), "吹っ飛ばす力は2段で +10%")
	_expect(is_equal_approx(game.call("blast_radius"), Tuning.EXPLOSION_RADIUS * Trolleys.stat("heavy", "blast_radius") * 1.05),
			"爆発の範囲は1段で +5%")
	_expect(is_equal_approx(game.call("stat", "girigiri_margin"), 1.2), "ギリギリの幅は1段で +20%")
	var jump: float = game.call("required_for", "jump", 700.0)
	_expect(jump < Trolleys.effective_required("heavy", "jump", 700.0) and is_equal_approx(jump, snappedf(700.0 * Trolleys.stat("heavy", "jump_factor") * 0.91, Tuning.DISPLAY_SPEED_DIV)),
			"ジャンプの必要速度は3段で −9%%（%.0f）" % jump)
	_expect(is_equal_approx(game.call("stat", "speed_max"), Trolleys.stat("heavy", "speed_max")), "最高速は強化で変わらない")
	game.free()
	return true


# --- 補助 ---

## 段 level にするのに要る経験値の合計
static func _xp_for(level: int) -> int:
	var sum: int = 0
	for l: int in range(1, level):
		sum += Progression.xp_for_level(l)
	return sum


## 第3試験まで合格（重量型が解放）。標準型を選ぶ
func _unlock_heavy() -> void:
	for n: int in range(1, 4):
		_gs.submit_clear(n, 1000, 1)
	_gs.set_trolley("standard")
	_gs.current_stage = 1


func _new_game(data: Dictionary) -> Node:
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.stage_data = data.duplicate(true)
	game.auto_pause = false
	root.add_child(game)
	return game


func _straight(objects: Array) -> Dictionary:
	return {
		"id": "check", "name": "check", "ground_y": 900.0, "start_segment": "s0", "star_thresholds": [900000, 900001],
		"segments": {"s0": {"points": [[0, RAIL_Y], [4000, RAIL_Y]], "end": {"type": "goal"}}},
		"junctions": {}, "objects": objects}


func _frames(n: int) -> void:
	for _i: int in n:
		await physics_frame


## draw(ci) で描いた部品（Trolley.probe）を集める
func _probe_draw(draw: Callable) -> Array:
	var out: Array = []
	var canvas := Node2D.new()
	canvas.draw.connect(func() -> void:
		Trolley.probe_on = true
		Trolley.probe = []
		draw.call(canvas)
		out.append_array(Trolley.probe)
		Trolley.probe_on = false
		Trolley.probe = [])
	root.add_child(canvas)
	await process_frame
	await process_frame
	canvas.free()
	return out


## ci を描き直して、その間に draw_body が使った色
func _probe_colors(ci: CanvasItem) -> Array:
	Trolley.probe = []
	Trolley.probe_on = true
	ci.queue_redraw()
	await process_frame
	await process_frame
	Trolley.probe_on = false
	var out: Array = Trolley.probe.map(func(part: Array) -> Color: return part[0])
	Trolley.probe = []
	return out


static func _area(poly: PackedVector2Array) -> float:
	var twice: float = 0.0
	for i: int in poly.size():
		twice += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(twice) * 0.5 if poly.size() >= 3 else 0.0


func _open(path: String) -> Control:
	change_scene_to_file(path)
	for _i: int in SCENE_WAIT_FRAMES:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path:
			await process_frame
			return current_scene
	_expect(false, "%s が開かない" % path)
	return null


func _open_garage(s: Control) -> Control:
	s.call("open_garage")
	await process_frame
	await process_frame
	return s.get("_garage")


func _card(g: Control, i: int) -> Control:
	return g.get_node("Cards").get_child(i)


func _card_text(g: Control, i: int, path: String) -> String:
	return (_card(g, i).get_node(path) as Label).text


func _up(g: Control, item: String) -> Button:
	return g.get_node("%UpGrid").get_node("Up_" + item)


func _paint(g: Control, p: int) -> Button:
	return g.get_node("%PaintGrid").get_child(p)


func _row(g: Control, part: String, item: String) -> String:
	return (g.get_node("%UpGrid").get_node(part + "_" + item) as Label).text


func _text(from: Node, path: String) -> String:
	return (from.get_node(path) as Label).text


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)
	await process_frame


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
	for path: String in [TEST_SETTINGS, TEST_SAVE, _gs.ghosts_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(ok: bool, label: String) -> bool:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
	return ok
