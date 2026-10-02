extends SceneTree
## 無限軌道（docs/superpowers/specs/2026-09-28-replay-value-design.md の7章）の自動確認。書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_endless.gd （失敗があれば終了コード1）
## 1. 区間の型（data/endless/chunks.json）: つなげられる形（入口と出口のレールの高さ）、壁・ジャンプは選ぶ出口にだけあり
##    もう一方は迂回（L-4）、判断材料は分岐の直後（L-3、5台の速さで）、爆破で崩れる壁の手前のドラム缶
## 2. 生成を多くの乱数の種と5台で回す: 検証（6.4）を通る、つなぎ目の L-3、壁・ジャンプは見積もった道の上（L-5）、
##    進むほど標的が増え必要速度が上がる、走るたびに違う
## 3. ゲーム画面で自動操縦（選ぶ出口を選ぶ）して数十区間を走る: 区間が足され・消され、ノードの数が増え続けない、
##    激突しない（L-5 の到達速度）、分岐の1秒前の画面に判断材料（L-3）。5台で
## 4. 激突でリザルトが出て記録が残る、「もう一度」「タイトルへ」。タイトルの錠前
## 記録と設定は確認用のファイルに差し替え、終わったら消す。

const GAME_SCENE: String = "res://scenes/game.tscn"
const NODE_GROWTH_MAX: float = 1.6  # 後半のノードの数の最大 ÷ 前半の最大の上限（増え続けていないかの目安）
const TITLE_SCENE: String = "res://scenes/title.tscn"
const SETTINGS_PATH: String = "user://checks_endless_settings.cfg"
const SAVE_PATH: String = "user://checks_endless_save.cfg"
const MIN_TYPES: int = 10  # 型の数（始まりの型を除く）
const SEEDS: int = 60  # 生成を回す乱数の種の数（車両ごと）
const GEN_PARTS: int = 40  # 1つの種で作る区間の数
const LEAD_SLACK: float = 40.0  # L-3 の見積もりの余裕（px）。本当の見え方はゲーム画面で確かめる
const BLAST_SLACK: float = 10.0  # 爆破で崩れる壁: ドラム缶の中心から壁の中心までが爆発の範囲よりこれだけ内側
const DRIVE_PARTS: Dictionary = {"standard": 30, "heavy": 12, "light": 12, "blast": 12, "prototype": 12}  # 自動操縦で通り過ぎる区間の数
const MAX_FRAMES: int = 60000

var _failed: int = 0
var _game_state: Node
var _time_scale: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_game_state = root.get_node("GameState")
	_time_scale = root.get_node("TimeScale")
	_game_state.settings_path = SETTINGS_PATH
	_game_state.save_path = SAVE_PATH
	_game_state.erase_records()
	_check_types()
	_check_generation()
	for id: String in Trolleys.IDS:
		if await _drive(id) != true:
			_expect(false, "%s の自動操縦が途中で止まった" % id)
	await _finish()


func _finish() -> void:
	_game_state.endless = false
	paused = false
	for p: Node in root.get_node("Audio").get_children():
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	await physics_frame
	await physics_frame
	for path: String in [SETTINGS_PATH, SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# --- 1. 区間の型 ---

func _check_types() -> void:
	var types: Array = Endless.types()
	var ids: Array = types.map(func(t: Dictionary) -> String: return t["id"])
	var starts: int = types.filter(func(t: Dictionary) -> bool: return t.get("start", false)).size()
	_expect(starts == 1 and types.size() - starts >= MIN_TYPES, "区間の型は始まり1つと、乱数で選ぶ型 %d 種類以上（%d 種類 %s）" % [
			MIN_TYPES, types.size() - starts, ids])
	for t: Dictionary in types:
		_check_type(t)


func _check_type(t: Dictionary) -> void:
	var name: String = t["id"]
	var segs: Dictionary = t["segments"]
	var exits: Array = segs.keys().filter(func(id: String) -> bool: return segs[id]["end"]["type"] == "exit")
	var entry_pt: Array = segs[t["entry"]]["points"][0]
	var exit_pt: Array = segs[exits[0]]["points"].back() if exits.size() == 1 else [0, 1]
	_expect(exits.size() == 1 and entry_pt[0] == 0.0 and entry_pt[1] == 0.0 and exit_pt[1] == 0.0,
			"型 %s: 入口は (0, 0)、出口は1つでレールの高さ 0（出口 %s、入口 %s、出口の端 %s）" % [name, exits, entry_pt, exit_pt])
	# 検証（6.4）: 1つだけ置いた区間（全段の標的）がそのまま通る
	var gen := Endless.new(Trolleys.DEFAULT, 1)
	var part: Dictionary = gen._instantiate(_all_levels(t))
	gen.data["start_segment"] = part["entry"]
	var errors: Array[String] = StageLoader.validate(gen.data)
	_expect(errors.is_empty(), "型 %s: 1つだけ組んだ区間は検証（6.4）を通る（%s）" % [name, errors])
	if not errors.is_empty():
		return
	var route: Array[String] = Endless.pick_route(part)
	# L-4: 壁・ジャンプは選ぶ出口の道にだけあり、分岐のもう一方の出口（合流まで）には失敗要素が無い
	var fails: Array = _fail_segments(part)
	_expect(fails.all(func(id: String) -> bool: return route.has(id)),
			"型 %s: 壁・ジャンプ（%s）はすべて選ぶ出口の道 %s の上（もう一方は迂回、L-4）" % [name, fails, route])
	# L-2: 分岐の2つの出口の中身は違う
	for jid: String in part["junctions"]:
		var b: Array = part["junctions"][jid]["branches"]
		var own: Array = [_own_part(part, b[0], b[1]), _own_part(part, b[1], b[0])]
		var sums: Array = [_points_on(part, own[0]), _points_on(part, own[1])]
		_expect(sums[0] != sums[1] or fails.any(func(id: String) -> bool: return own[0].has(id) or own[1].has(id)),
				"型 %s の %s: 2つの出口は得点量かリスクが違う（L-2。得点 %s）" % [name, jid, sums])
	# 爆破で崩れる壁: 手前の同じセグメントのドラム缶の中心から、壁の中心まで爆発の範囲の内側（5台のうち一番狭い範囲で）
	var radius: float = INF
	for id: String in Trolleys.IDS:
		radius = minf(radius, Tuning.EXPLOSION_RADIUS * Progression.stat(id, "blast_radius", {}))
	for od: Dictionary in part["objects"]:
		if not od.get("blast", false):
			continue
		var wall_c: Vector2 = _center(part, od)
		var near: float = INF
		for dr: Dictionary in part["objects"]:
			if dr["type"] == "drum" and dr["segment"] == od["segment"] and dr["offset"] < od["offset"]:
				near = minf(near, _center(part, dr).distance_to(wall_c))
		_expect(near <= radius - BLAST_SLACK, "型 %s: 爆破で崩れる壁は手前のドラム缶の爆発で崩れる（中心の距離 %.0f ≤ %.0f）" % [
				name, near, radius - BLAST_SLACK])
	# L-3: 判断材料は分岐の直後（5台の速さで、1秒前の画面の右端より左）
	var late: Array[String] = _late_material(gen.data)
	_expect(late.is_empty(), "型 %s: 分岐の %.1f 秒前の画面（5台の速さ）に判断材料が入る（L-3。入らない %s）" % [
			name, Tuning.DECISION_LEAD_TIME, late])


## 型の標的をすべての段で置く（level を消した写し）
func _all_levels(t: Dictionary) -> Dictionary:
	var copy: Dictionary = t.duplicate(true)
	for od: Dictionary in copy["objects"]:
		od.erase("level")
	return copy


## 壁（爆破で崩れる壁を含む）とジャンプのあるセグメント
func _fail_segments(part: Dictionary) -> Array:
	var out: Array = []
	for od: Dictionary in part["objects"]:
		if od["type"] == "wall":
			out.append(od["segment"])
	for id: String in part["segments"]:
		if part["segments"][id].has("jump"):
			out.append(id)
	return out


## 出口 from の、もう一方の出口 other と合流するまでの部分（区間の中）
func _own_part(part: Dictionary, from: String, other: String) -> Array:
	var shared: Array = _section(part["segments"], other)
	return _section(part["segments"], from).filter(func(id: String) -> bool: return not shared.has(id))


func _section(segs: Dictionary, from: String) -> Array:
	var ids: Array = [from]
	while segs[ids.back()]["end"]["type"] == "next" and segs.has(segs[ids.back()]["end"]["segment"]):
		ids.append(segs[ids.back()]["end"]["segment"])
	return ids


func _points_on(part: Dictionary, ids: Array) -> int:
	var sum: int = 0
	for od: Dictionary in part["objects"]:
		if ids.has(od["segment"]):
			sum += Tuning.TARGET_POINTS[od["type"]]
	return sum


## 標的の中心（build() と同じ置き方: 下辺中央をレールの上面に、レールの傾きに合わせて回す）
func _center(part: Dictionary, od: Dictionary) -> Vector2:
	var curve: Curve2D = _curve(part["segments"][od["segment"]]["points"])
	var xf: Transform2D = curve.sample_baked_with_rotation(float(od["offset"])).translated_local(
			Vector2(0.0, -Tuning.RAIL_WIDTH * 0.5))
	return xf * Vector2(0.0, -(Tuning.TARGET_SIZE[od["type"]] as Vector2).y * 0.5)


func _curve(points: Array) -> Curve2D:
	var curve := Curve2D.new()
	for p: Array in points:
		curve.add_point(Vector2(p[0], p[1]))
	return curve


## 分岐ごとの判断材料（tests/checks_stages.gd の _decision_material と同じ: 各出口の最初の標的の中心と、
## 壁・ジャンプの標識の中心）。{ 分岐 id: [[説明, 位置], ...] }
func _material(data: Dictionary) -> Dictionary:
	var sign_half: float = Tuning.SIGN_SIZE.y * 0.5
	var out: Dictionary = {}
	var part: Dictionary = {"segments": data["segments"]}
	for jid: String in data["junctions"]:
		var b: Array = data["junctions"][jid]["branches"]
		var items: Array = []
		for i: int in 2:
			var first_found: bool = false
			for id: String in _own_part(part, b[i], b[1 - i]):
				var curve: Curve2D = _curve(data["segments"][id]["points"])
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


## L-3 の見積もり: 分岐に速さ v で着く1秒前、トロッコは分岐の v px 手前（線路の長さ ≥ x の差なので控えめ）。
## カメラはトロッコを画面の左から CAMERA_TROLLEY_SCREEN_X に置くので、画面の右端は トロッコ + 表示幅 × (1 − その割合)。
## 5台の初速〜最高速で、判断材料の x がそこより LEAD_SLACK 以上左、y が画面の上端より下
func _late_material(data: Dictionary) -> Array[String]:
	var late: Array[String] = []
	var material: Dictionary = _material(data)
	var view: Vector2 = root.get_visible_rect().size
	for jid: String in material:
		var at: Vector2 = _curve(data["segments"][data["junctions"][jid]["branches"][0]]["points"]).get_point_position(0)
		for id: String in Trolleys.IDS:
			var v: float = Progression.stat(id, "speed_base", {})
			var vmax: float = Progression.stat(id, "speed_max", {})
			while v <= vmax:
				var t: float = maxf(inverse_lerp(Tuning.SPEED_BASE, Tuning.SPEED_MAX, v), 0.0)
				var zoom: float = maxf(lerpf(Tuning.ZOOM_AT_BASE, Tuning.ZOOM_AT_MAX, t), Tuning.ZOOM_MIN)
				var right: float = at.x - v * Tuning.DECISION_LEAD_TIME + view.x / zoom * (1.0 - Tuning.CAMERA_TROLLEY_SCREEN_X)
				var top: float = at.y - view.y / zoom * Tuning.CAMERA_TROLLEY_SCREEN_Y
				for m: Array in material[jid]:
					var p: Vector2 = m[1]
					if p.x > right - LEAD_SLACK or p.y < top:
						late.append("%s の %s（%s %d px/s、右端 %.0f）" % [jid, m[0], id, v, right])
				v += 50.0
	return late


# --- 2. 生成 ---

func _check_generation() -> void:
	var invalid: Array[String] = []
	var late: Array[String] = []
	var off_route: Array[String] = []
	var too_high: Array[String] = []
	var targets_by_level: Dictionary = {}  # 段 → [区間の数, 標的の数]
	var required_by_level: Dictionary = {}  # 段 → 壁の必要速度（px/s、強化なし・車両の強さを掛ける前）の最大
	var firsts: Dictionary = {}  # 2つ目の区間の型（走るたびに違う）
	for id: String in Trolleys.IDS:
		for s: int in SEEDS:
			var gen := Endless.new(id, s * 7919 + 13)
			var route: Array[String] = []
			for _i: int in GEN_PARTS:
				var part: Dictionary = gen.add_part()
				route.append_array(Endless.pick_route(part))
				var lv: int = part["level"]
				var tl: Array = targets_by_level.get(lv, [0, 0])
				targets_by_level[lv] = [tl[0] + 1, tl[1] + part["objects"].size()]
				for od: Dictionary in part["objects"]:
					if od["type"] == "wall" and not od.get("blast", false):
						required_by_level[lv] = maxf(required_by_level.get(lv, 0.0), od["required_speed"])
				_check_required(part, too_high)
			if id == Trolleys.DEFAULT:
				firsts[gen.parts[1]["type"]] = true
			var errors: Array[String] = StageLoader.validate(gen.data)
			if not errors.is_empty():
				invalid.append("%s 種%d: %s" % [id, s, errors.slice(0, 3)])
			if s < 5:  # L-3 のつなぎ目の見積もりは重いので一部の種だけ（型ごとは _check_type で全部見ている）
				late.append_array(_late_material(gen.data))
			for f: String in _fail_segments({"segments": gen.data["segments"], "objects": gen.data["objects"]}):
				if not route.has(f):
					off_route.append("%s 種%d の %s" % [id, s, f])
	_expect(invalid.is_empty(), "5台 × %d 種 × %d 区間: 組んだ線路はどれも検証（6.4、つなぎ目の MIN_JUNCTION_GAP を含む）を通る（%s）" % [
			SEEDS, GEN_PARTS, invalid.slice(0, 5)])
	_expect(late.is_empty(), "つなぎ目を含め、分岐の %.1f 秒前の画面に判断材料が入る（L-3、5台の速さ。%s）" % [
			Tuning.DECISION_LEAD_TIME, late.slice(0, 5)])
	_expect(off_route.is_empty(), "壁・ジャンプはどれも、速さを見積もった道（選ぶ出口をたどる道）の上にある（L-5。%s）" % [off_route.slice(0, 5)])
	_expect(too_high.is_empty(), "必要速度は段の値以下で、壁・ジャンプとも速度の表示の単位で正の値（%s）" % [too_high.slice(0, 5)])
	var levels: Array = targets_by_level.keys()
	levels.sort()
	var density: Array = levels.map(func(l: int) -> float: return float(targets_by_level[l][1]) / targets_by_level[l][0])
	_expect(levels.size() >= 3 and density.back() > density.front() * 1.1,
			"進むほど標的が増える（段ごとの1区間の標的の平均 %s、段 %s）" % [density.map(func(x: float) -> String: return "%.1f" % x), levels])
	var req_levels: Array = required_by_level.keys()
	req_levels.sort()
	_expect(req_levels.size() >= 3 and required_by_level[req_levels.back()] > required_by_level[req_levels.front()],
			"進むほど壁の必要速度が上がる（段ごとの最大 %s）" % [required_by_level])
	_expect(firsts.size() >= 4, "乱数の種ごとに違う型が選ばれる（2つ目の区間の型 %s）" % [firsts.keys()])


## 壁・ジャンプの必要速度: 段の値（型の値 + 段 × ENDLESS_REQUIRED_STEP）以下、正、表示の単位の倍数
func _check_required(part: Dictionary, bad: Array[String]) -> void:
	var t: Dictionary = {}
	for tt: Dictionary in Endless.types():
		if tt["id"] == part["type"]:
			t = tt
	var step: float = Tuning.ENDLESS_REQUIRED_STEP * part["level"]
	var prefix: String = "c%d_" % part["index"]
	for od: Dictionary in part["objects"]:
		if od["type"] != "wall" or od.get("blast", false):
			continue
		var base: float = 0.0
		for o: Dictionary in t["objects"]:
			if prefix + str(o["segment"]) == od["segment"] and o["offset"] == od["offset"]:
				base = o["required_speed"]
		var r: float = od["required_speed"]
		if r > base + step or r <= 0.0 or fmod(r, Tuning.DISPLAY_SPEED_DIV) != 0.0:
			bad.append("%s の壁 %.0f（段の値 %.0f）" % [part["type"], r, base + step])
	for id: String in part["segments"]:
		if part["segments"][id].has("jump"):
			var local: String = id.trim_prefix(prefix)
			var base: float = t["segments"][local]["jump"]["required_speed"]
			var r: float = part["segments"][id]["jump"]["required_speed"]
			if r > base + step or r <= 0.0 or fmod(r, Tuning.DISPLAY_SPEED_DIV) != 0.0:
				bad.append("%s のジャンプ %.0f（段の値 %.0f）" % [part["type"], r, base + step])


# --- 3. ゲーム画面 ---

## 車両 id で無限軌道を始め、選ぶ出口（pick）を選び続けて DRIVE_PARTS[id] 区間を通り過ぎる。標準型は最後に激突させて
## リザルト・記録・「もう一度」・Esc を確かめる
func _drive(id: String) -> bool:
	_unlock_all()
	_game_state.set_trolley(id)
	_expect(_game_state.trolley() == id, "車両 %s で走らせる" % id)
	_game_state.endless = true
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	root.add_child(game)
	game.set_process_unhandled_input(false)
	game.auto_pause = false
	var gen: Endless = game._endless
	_expect(gen != null and game._number == 0 and game._ghost == null and game._hint == null,
			"%s: GameState.endless でゲーム画面は無限軌道（試験の番号 0、ゴースト・初回ヒント無し）" % id)
	if gen == null:
		game.free()
		return true
	var trolley: Trolley = game._trolley
	var segs: Dictionary = gen.data["segments"]
	var views: Array = []  # [ゲーム内時刻, 画面の範囲, HUD の札]
	var unseen: Array[String] = []
	var low: Array[String] = []  # 必要速度 + 余裕に届かなかった壁・ジャンプ
	var checked: Array[int] = [0]  # 到達速度を確かめた壁・ジャンプの数
	var walls: Dictionary = {}  # 見張っている壁（爆破で崩れる壁を除く）の instance id → [必要速度, 型]
	var watched_parts: Array[int] = [0]  # 壁を見張りに足した区間の数（ゲーム画面の _endless_nodes との対応）
	var last: Array[String] = [trolley.segment_id]
	trolley.segment_entered.connect(func(sid: String) -> void:
		var end: Dictionary = segs.get(last[0], {"end": {"type": ""}})["end"]
		last[0] = sid
		if segs[sid].has("jump"):
			var req: float = game.required_for("jump", segs[sid]["jump"]["required_speed"])
			checked[0] += 1
			if trolley.speed < req + Tuning.REQUIRED_SPEED_MARGIN:
				low.append("%s のジャンプ %s（必要 %.0f、到達 %.0f）" % [id, sid, req, trolley.speed])
		if end["type"] != "junction":
			return
		var at: float = game._time - Tuning.DECISION_LEAD_TIME
		var view: Variant = null
		var panels: Array = []
		for v: Array in views:
			if v[0] <= at:
				view = v[1]
				panels = v[2]
		for m: Array in _material(gen.data).get(end["id"], []):
			if view == null or not (view as Rect2).has_point(m[1]):
				unseen.append("%s の %s の %s（速度 %d、位置 %s、1秒前の画面 %s）" % [id, end["id"], m[0], trolley.speed, m[1], view])
				continue
			var r: Rect2 = view
			var on_screen: Vector2 = ((m[1] as Vector2) - r.position) / r.size * game.get_viewport_rect().size
			if panels.any(func(p: Rect2) -> bool: return p.has_point(on_screen)):
				unseen.append("%s の %s の %s が HUD の札に隠れる" % [id, end["id"], m[0]]))
	var target_parts: int = DRIVE_PARTS[id]
	var max_parts: int = 0
	var nodes_at: Dictionary = {}  # 通り過ぎて消した区間の数 → その時のノードの数
	var passed: int = 0
	for _i: int in MAX_FRAMES:
		for p: Dictionary in gen.parts:  # 自動操縦: 選ぶ出口
			for jid: String in p["pick"]:
				if game._junctions.has(jid):
					(game._junctions[jid] as Junction).selected = p["pick"][jid]
		while watched_parts[0] < game._endless_nodes.size() + passed:
			_watch_walls(gen, game, watched_parts[0] - passed, walls)
			watched_parts[0] += 1
		await physics_frame
		if game._finished:
			break
		var cam: Camera2D = game._camera
		var size: Vector2 = game.get_viewport_rect().size / cam.zoom
		views.append([game._time, Rect2(cam.position - size * 0.5, size), game._hud_view.panels()])
		if views.size() > 200:
			views.pop_front()
		passed = gen.parts[0]["index"]
		max_parts = maxi(max_parts, gen.parts.size())
		if not nodes_at.has(passed):
			nodes_at[passed] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var alive: Dictionary = {}
		for t: Target in game._targets:
			alive[t.get_instance_id()] = true
		for wid: int in walls.keys():
			if not alive.has(wid):
				checked[0] += 1
				if trolley.speed < walls[wid][0] + Tuning.REQUIRED_SPEED_MARGIN:
					low.append("%s の壁（%s、必要 %.0f、到達 %.0f）" % [id, walls[wid][1], walls[wid][0], trolley.speed])
				walls.erase(wid)
		if passed >= target_parts:
			break
	_expect(not game._finished and passed >= target_parts,
			"%s: 自動操縦（選ぶ出口）で %d 区間を通り過ぎても激突・脱線しない（通り過ぎた %d、%s、距離 %s）" % [
				id, target_parts, passed, game.fail_reason, Display.distance_text(game.distance)])
	_expect(low.is_empty() and checked[0] >= 3,
			"%s: L-5 壁・ジャンプ %d 個に必要速度 + %d 以上で着く（届かない %s）" % [id, checked[0], Tuning.REQUIRED_SPEED_MARGIN, low])
	_expect(unseen.is_empty(), "%s: L-3 分岐の %.1f 秒前の画面に判断材料が入り、HUD の札に隠れない（%s）" % [
			id, Tuning.DECISION_LEAD_TIME, unseen.slice(0, 5)])
	_expect(max_parts <= Tuning.ENDLESS_PARTS_AHEAD + 3 and game._endless_nodes.size() == gen.parts.size()
			and game._world.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Part")).size() <= Tuning.ENDLESS_PARTS_AHEAD + 3,
			"%s: 区間は足されて消され、同時に組んでいるのは最大 %d 個（上限 %d）" % [id, max_parts, Tuning.ENDLESS_PARTS_AHEAD + 3])
	var keys: Array = nodes_at.keys()
	keys.sort()
	if keys.size() >= 6:
		var early: int = 0
		var late: int = 0
		for k: int in keys.slice(1, keys.size() / 2):
			early = maxi(early, nodes_at[k])
		for k: int in keys.slice(keys.size() / 2):
			late = maxi(late, nodes_at[k])
		# 線路は走るたびに乱数で変わり、区間の型で標的の数が違う（1.3 倍では型の偏りでたまに落ちた）
		_expect(late <= early * NODE_GROWTH_MAX, "%s: 長く走ってもノードの数が増え続けない（前半の最大 %d、後半の最大 %d）" % [id, early, late])
	var goals: Array = game._world.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is Goal)
	_expect(goals.is_empty(), "%s: 区間の境目にゴールを置かない（%d 個）" % [id, goals.size()])
	var hud_text: String = game.endless_title_text()
	_expect(hud_text.begins_with("無限軌道") and hud_text.ends_with("m"), "%s: HUD の見出しは「無限軌道」と距離（%s）" % [id, hud_text])
	if id == Trolleys.DEFAULT:
		await _check_result(game)
	else:
		game.free()
		_time_scale.clear()
	return true


## 区間 k（ゲーム画面の _endless_nodes の位置）の壁（爆破で崩れる壁を除く）を見張りに足す。標的は objects の順に組まれる
func _watch_walls(gen: Endless, game: Node, k: int, walls: Dictionary) -> void:
	var part: Dictionary = gen.parts[k]
	var targets: Array = game._endless_nodes[k]["targets"]
	for i: int in part["objects"].size():
		var od: Dictionary = part["objects"][i]
		if od["type"] == "wall" and not od.get("blast", false) and is_instance_valid(targets[i]):
			walls[(targets[i] as Target).get_instance_id()] = [(targets[i] as Target).required_speed, part["type"]]


## 激突 → リザルト（得点・距離・最高記録・熟練度）、記録が残る。R で別の線路でやり直し、Esc でタイトルへ
func _check_result(game: Node) -> void:
	var runs_before: int = _game_state._stats["runs"]
	game._fail("激突", game._trolley.speed + 100.0)
	for _i: int in 200:
		await physics_frame
		if game._result != null:
			break
	var result: Control = game._result
	_expect(result != null and result.has_signal(&"title_requested"), "激突すると無限軌道のリザルトが出る")
	var rec: Dictionary = _game_state.endless_record(Trolleys.DEFAULT)
	_expect(rec["best_score"] == game.score and is_equal_approx(rec["best_distance"], game.distance) and game._endless_best,
			"記録が残る（得点 %d・距離 %.0f → 記録 %s）" % [game.score, game.distance, rec])
	_expect(_game_state._stats["runs"] == runs_before + 1 and not (_game_state._stats["attempts"] as Dictionary).has(0),
			"試験記録の累計に1回入り、試験ごとの回数（0）には入らない")
	_expect(int(game.result_data()["xp"]["gained"]) > 0, "熟練度が入る（%s）" % [game.result_data()["xp"]])
	if result == null:
		game.free()
		return
	var texts: Array = result.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	_expect(texts.has(Display.distance_text(game.distance)) and texts.has(Display.score_text(game.score)) and texts.has("最高記録更新"),
			"リザルトに距離・得点・最高記録更新（%s）" % [texts])
	var again: Button = result.get_node("Buttons/Again")
	_expect(again.has_focus() and (result.get_node("Buttons/Title") as Button).text == "タイトルへ",
			"「もう一度」にフォーカス、「タイトルへ」がある")
	var old_seed: int = game._endless._rng.seed
	var fresh: Node = game.retry()
	await process_frame
	await physics_frame
	_expect(fresh != game and fresh._endless != null and fresh._endless._rng.seed != old_seed and fresh.score == 0,
			"R（もう一度）で別の線路の無限軌道をやり直す")
	fresh.auto_pause = false
	fresh.set_process_unhandled_input(false)
	fresh._fail("脱線", 900.0)
	for _i: int in 200:
		await physics_frame
		if fresh._result != null:
			break
	if fresh._result == null:
		_expect(false, "やり直した走行でもリザルトが出る")
		fresh.free()
		return
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	for _i: int in 10:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == TITLE_SCENE:
			break
	_expect(current_scene != null and current_scene.scene_file_path == TITLE_SCENE and not _game_state.endless,
			"Esc でタイトルへ戻り、無限軌道を降りる")
	if is_instance_valid(fresh):
		fresh.free()
	_time_scale.clear()
	await _check_title()


## タイトルの錠前: 「基礎課程修了」が無ければ押せず条件を出す。あれば押せて、最高記録を出し、押すと無限軌道が始まる
func _check_title() -> void:
	var stamps: Dictionary = _game_state._stamps
	var saved: Dictionary = stamps.duplicate()
	stamps.erase("basic")
	change_scene_to_file(TITLE_SCENE)
	await process_frame
	await process_frame
	var t: Node = current_scene
	var b: Button = t.get_node("Endless/Start")
	var note: String = (t.get_node("Endless/Note") as Label).text
	_expect(b.disabled and b.focus_mode == Control.FOCUS_NONE and note.contains(Achievements.name_of("basic")),
			"「基礎課程修了」が無ければ「無限軌道」は押せず、条件を出す（%s）" % note)
	stamps["basic"] = "2026-09-28"
	change_scene_to_file(TITLE_SCENE)
	await process_frame
	await process_frame
	t = current_scene
	b = t.get_node("Endless/Start")
	note = (t.get_node("Endless/Note") as Label).text
	var best: Dictionary = _game_state.endless_record()
	_expect(not b.disabled and note.contains(Display.distance_text(best["best_distance"])),
			"「基礎課程修了」があれば押せて、最高記録を出す（%s）" % note)
	var start: Button = t.get_node("Menu/Start")
	start.grab_focus()
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.physical_keycode = KEY_RIGHT
	right.pressed = true
	root.push_input(right)
	await process_frame
	_expect(b.has_focus(), "「試験開始」から → で「無限軌道」へ")
	b.pressed.emit()
	for _i: int in 10:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == GAME_SCENE:
			break
	_expect(current_scene != null and current_scene.scene_file_path == GAME_SCENE and current_scene._endless != null,
			"「無限軌道」を押すと無限軌道が始まる")
	_game_state._stamps = saved
	_game_state.endless = false
	change_scene_to_file(TITLE_SCENE)
	await process_frame
	await process_frame


## 全車両を解放する（確認用の記録に全試験の合格と、解放に要る検定印を書く）
func _unlock_all() -> void:
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		_game_state.submit_clear(n, 1, 1, Trolleys.DEFAULT)
	for u: Dictionary in Tuning.TROLLEY_UNLOCK.values():
		if u.has("stamp"):
			_game_state._stamps[u["stamp"]] = "2026-09-28"


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
