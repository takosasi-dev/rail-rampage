class_name StageLoader
## ステージJSONの読み込み・検証（6.4）・構築（仕様書6章、D-2）。

const JUNCTION_SCENE: PackedScene = preload("res://scenes/objects/junction.tscn")
const GOAL_SCENE: PackedScene = preload("res://scenes/objects/goal.tscn")
const SPEED_SIGN_SCENE: PackedScene = preload("res://scenes/ui/speed_sign.tscn")
const TARGET_SCENES: Dictionary = {
	"crate": preload("res://scenes/objects/crate.tscn"),
	"barrel": preload("res://scenes/objects/barrel.tscn"),
	"dummy": preload("res://scenes/objects/dummy.tscn"),
	"drum": preload("res://scenes/objects/drum.tscn"),
	"wall": preload("res://scenes/objects/wall.tscn"),
}


## 6.4: 読み込み時の検証。違反ごとに説明を1つ返す（空なら合格）。ゲーム画面は違反を push_error で出し、
## 「ステージデータエラー」を表示してステージ選択に戻る。
## キーが無い・型が違うデータでも止まらずに違反として返す（build() が読むキーはすべてここで確かめる）。
## 説明の末尾の（1）〜（8）は 6.4 の項目番号
static func validate(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if data.is_empty():
		errors.append("ステージデータが空")
		return errors
	var segments: Variant = data.get("segments")
	var junctions: Variant = data.get("junctions")
	if not segments is Dictionary or (segments as Dictionary).is_empty():
		errors.append("segments が空でない辞書になっていない")
		return errors
	if not junctions is Dictionary:
		errors.append("junctions が辞書になっていない")
		return errors

	# --- 線路のつながり（1〜4） ---
	var lengths: Dictionary = {}  # 点の形が正しいセグメント → 長さ（点を直線で結んだ長さ）
	for id: Variant in segments:
		var seg: Variant = segments[id]
		if not id is String:
			errors.append("セグメントID %s が文字列になっていない" % [id])
		if not seg is Dictionary:
			errors.append("セグメント %s が辞書になっていない" % [id])
			continue
		var pts: Variant = seg.get("points")
		if not _is_points(pts):
			errors.append("セグメント %s の points が [x, y] の配列になっていない" % [id])
		elif (pts as Array).size() < 2:
			errors.append("セグメント %s の points が2点未満（2）" % [id])
		else:
			lengths[id] = _polyline_length(pts)
		var end: Variant = seg.get("end")
		# 型の違う値どうしを == で比べると止まるので、文字列にしてから比べる
		var end_type: String = str((end as Dictionary).get("type")) if end is Dictionary else ""
		if end_type == "junction":
			if not junctions.has(end.get("id")):
				errors.append("セグメント %s の end.id が存在しない分岐 %s を参照している（1）" % [id, end.get("id")])
		elif end_type == "next":
			if not segments.has(end.get("segment")):
				errors.append("セグメント %s の end.segment が存在しないセグメント %s を参照している（1）" % [id, end.get("segment")])
		elif end_type != "goal":
			errors.append("セグメント %s の end.type が junction・next・goal のどれでもない（%s）" % [id, end_type])
		if seg.has("jump"):
			var jump: Variant = seg["jump"]
			if not (jump is Dictionary and _is_number((jump as Dictionary).get("required_speed"))):
				errors.append("セグメント %s の jump に数値の required_speed が無い" % [id])
	for jid: Variant in junctions:
		var j: Variant = junctions[jid]
		if not jid is String:
			errors.append("分岐ID %s が文字列になっていない" % [jid])
		if not j is Dictionary:
			errors.append("分岐 %s が辞書になっていない" % [jid])
			continue
		var branches: Variant = j.get("branches")
		if not (branches is Array and (branches as Array).size() == 2):
			errors.append("分岐 %s の branches の要素数が2でない（4）" % [jid])
		else:
			for b: Variant in branches:
				if not segments.has(b):
					errors.append("分岐 %s の branches が存在しないセグメント %s を参照している（1）" % [jid, b])
		var def: Variant = j.get("default")
		if not (_is_number(def) and (def == 0 or def == 1)):
			errors.append("分岐 %s の default が 0 か 1 になっていない（4）" % [jid])
	var start: Variant = data.get("start_segment")
	if not segments.has(start):
		errors.append("start_segment が存在しないセグメント %s を参照している（1）" % [start])
	for id: Variant in lengths:
		var last: Vector2 = _point((segments[id]["points"] as Array).back())
		for n: String in _next_ids(segments[id], segments, junctions):
			if not lengths.has(n):
				continue
			var first: Vector2 = _point(segments[n]["points"][0])
			if last.distance_to(first) > Tuning.JOINT_TOLERANCE:
				errors.append("セグメント %s の終点 %s と、次のセグメント %s の始点 %s が %dpx より離れている（3）" % [
						id, last, n, first, Tuning.JOINT_TOLERANCE])
	# 7・8 は線路の形とつながりが正しいときだけ調べる（壊れた参照で同じ原因の違反を重ねて出さない）
	var track_ok: bool = errors.is_empty()

	# --- ステージ全体の値（4） ---
	for key: String in ["id", "name"]:
		if not data.get(key) is String:
			errors.append("%s が文字列になっていない" % key)
	if not _is_number(data.get("ground_y")):
		errors.append("ground_y が数値になっていない")
	var stars: Variant = data.get("star_thresholds")
	# TODO(spec): 「昇順」は同じ値が並ぶのも許すことにした（★2 と ★3 の閾値が同じでも遊べる）
	if not (stars is Array and (stars as Array).size() == 2 and _is_number(stars[0]) and _is_number(stars[1])
			and stars[0] <= stars[1]):
		errors.append("star_thresholds が要素数2の昇順の数値になっていない（4）")
	# 設計書4章: time_of_day は省略できる。書いてあれば5つの名前のどれか
	if data.has("time_of_day") and not (data["time_of_day"] is String and TimeOfDay.NAMES.has(data["time_of_day"])):
		errors.append("time_of_day が %s のどれでもない（%s）" % [", ".join(TimeOfDay.NAMES), data["time_of_day"]])
	# replay-value-design.md 3章: 課題と金★の閾値。どちらも省略できる
	errors.append_array(Challenges.validate(data.get("challenges")))
	var gold: Variant = data.get("gold_threshold", 0)
	if not (_is_number(gold) and gold >= 0 and gold == floorf(gold)):
		errors.append("gold_threshold が0以上の整数になっていない")

	# --- 標的（1, 5, 6） ---
	var objects: Variant = data.get("objects", [])
	if not objects is Array:
		errors.append("objects が配列になっていない")
		objects = []
	for i: int in (objects as Array).size():
		var od: Variant = objects[i]
		if not od is Dictionary:
			errors.append("objects[%d] が辞書になっていない" % i)
			continue
		var type: Variant = od.get("type")
		var sid: Variant = od.get("segment")
		var offset: Variant = od.get("offset")
		if not TARGET_SCENES.has(type):
			errors.append("objects[%d] の type %s は知らない標的の種類" % [i, type])
		if not segments.has(sid):
			errors.append("objects[%d] の segment が存在しないセグメント %s を参照している（1）" % [i, sid])
		if not _is_number(offset):
			errors.append("objects[%d] の offset が数値になっていない" % i)
		elif lengths.has(sid) and (offset < 0.0 or offset > lengths[sid]):
			errors.append("objects[%d] の offset %s がセグメント %s の長さ 0〜%.1f の外（5）" % [i, offset, sid, lengths[sid]])
		if str(type) == "wall" and not _is_number(od.get("required_speed")):
			errors.append("objects[%d] の wall に数値の required_speed が無い（6）" % i)

	# --- 経路（7, 8） ---
	if not track_ok:
		return errors
	var cycle: String = _find_cycle(start, segments, junctions, {})
	if not cycle.is_empty():
		errors.append("start_segment から進むとセグメント %s で循環し、goal に着かない経路がある（7）" % cycle)
		return errors
	for jid: String in junctions:
		for b: String in junctions[jid]["branches"]:
			# 次の分岐まで合流をたどる。7 は start から届く所しか見ないので、届かない分岐の先の循環で
			# 止まらないよう、たどる回数に上限を付ける（上限に届いたら循環）
			var id: String = b
			var dist: float = 0.0
			for step: int in segments.size() + 1:
				if step == segments.size():
					errors.append("分岐 %s の出口 %s から合流をたどると循環し、goal に着かない（7）" % [jid, b])
					break
				dist += lengths[id]
				var end: Dictionary = segments[id]["end"]
				if end["type"] == "junction":
					if dist < Tuning.MIN_JUNCTION_GAP:
						errors.append("分岐 %s から %s を通って分岐 %s まで %.0fpx で、MIN_JUNCTION_GAP（%dpx）より短い（8）" % [
								jid, b, end["id"], dist, Tuning.MIN_JUNCTION_GAP])
					break
				if end["type"] != "next":
					break
				id = end["segment"]
	return errors


## 7: from から進んで、探索中のセグメントに戻ったらそのIDを返す（循環が無ければ ""）。
## state: ID → 1（探索中）/ 2（調べ終えた）
static func _find_cycle(from: String, segments: Dictionary, junctions: Dictionary, state: Dictionary) -> String:
	state[from] = 1
	for n: String in _next_ids(segments[from], segments, junctions):
		if state.get(n, 0) == 1:
			return n
		if state.get(n, 0) == 0:
			var found: String = _find_cycle(n, segments, junctions, state)
			if not found.is_empty():
				return found
	state[from] = 2
	return ""


## セグメントの出口・合流先のうち、存在するセグメントのID（壊れた参照は validate() が別に違反として数える）
static func _next_ids(seg: Dictionary, segments: Dictionary, junctions: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var end: Variant = seg.get("end")
	if not end is Dictionary:
		return ids
	var to: Array = []
	var end_type: String = str(end.get("type"))
	if end_type == "next":
		to = [end.get("segment")]
	elif end_type == "junction":
		var j: Variant = junctions.get(end.get("id"))
		if j is Dictionary and j.get("branches") is Array:
			to = j["branches"]
	for n: Variant in to:
		if n is String and segments.has(n):
			ids.append(n)
	return ids


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


static func _is_points(v: Variant) -> bool:
	if not v is Array:
		return false
	for p: Variant in v:
		if not (p is Array and (p as Array).size() == 2 and _is_number(p[0]) and _is_number(p[1])):
			return false
	return true


static func _point(p: Array) -> Vector2:
	return Vector2(p[0], p[1])


## 点同士を直線で結んだ長さ（build() の Curve2D はハンドルなしで点を足すので、焼いた長さと同じ）
static func _polyline_length(points: Array) -> float:
	var total: float = 0.0
	for i: int in range(1, points.size()):
		total += _point(points[i - 1]).distance_to(_point(points[i]))
	return total


## 読めなければ空の Dictionary を返す。
static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ステージファイルがありません: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("ステージJSONを解析できません: %s" % path)
		return {}
	return parsed


## world の下に地面・線路・支柱・照明器具・分岐・ゴール・標的・必要速度標識を置く。tod は時間帯（設計書4章）で、
## 照明器具の点灯と、光る物（ドラム缶・分岐・標識）のにじみの強さを決める。
## 戻り値: { "paths": {id: Path2D}, "junctions": {id: Junction}, "targets": Array[Target],
##          "signs": Array[SpeedSign] }
static func build(data: Dictionary, world: Node2D, tod: String = "noon") -> Dictionary:
	_build_ground(data, world)
	return _build_contents(data, world, tod, Tuning.TOD_LAMP[tod])


## 無限軌道（replay-value-design.md 7章）: 区間1つ（Endless.add_part() の戻り値）を、まとめのノード "Part<番号>" の下に組む。
## 床の見た目は区間の "ground" の x の範囲だけ描き、当たり（StaticBody2D）は置かない（ゲーム画面が1つだけ置く）。
## 照明器具は区間の x の範囲にあるものだけ（隣の区間と二重にしない）。戻り値は build() と同じ形に "node" を足したもの
static func build_part(part: Dictionary, world: Node2D, ground_y: float, tod: String) -> Dictionary:
	var node := Node2D.new()
	node.name = "Part%d" % part["index"]
	world.add_child(node)
	var range_x: Vector2 = part["ground"]
	var floor_visual: Node2D = _ground_visual(range_x.x, range_x.y, true)
	floor_visual.position = Vector2(0.0, ground_y)
	floor_visual.z_index = Tuning.Z_GROUND
	node.add_child(floor_visual)
	var sub: Dictionary = {"ground_y": ground_y, "segments": part["segments"], "junctions": part["junctions"],
			"objects": part["objects"]}
	var built: Dictionary = _build_contents(sub, node, tod, -1.0, false)  # 出口が goal なのは次の区間を足すまでの間だけ
	var lamps := Node2D.new()
	lamps.name = "Lamps"
	node.add_child(lamps)
	for at: Vector2 in lamp_spots(sub):
		if at.x >= range_x.x and at.x < range_x.y:
			var lamp := Lamp.new()
			lamp.position = at
			lamp.strength = Tuning.TOD_LAMP[tod]
			lamps.add_child(lamp)
	built["node"] = node
	return built


## build() の床より後ろ: 線路・支柱・照明器具（lamp_strength が負なら置かない）・分岐・ゴール（goals が false なら置かない）・
## 標的・必要速度標識
static func _build_contents(data: Dictionary, world: Node2D, tod: String, lamp_strength: float, goals: bool = true) -> Dictionary:
	var glow: float = Tuning.TOD_GLOW[tod]
	var segments: Dictionary = data["segments"]
	var paths: Dictionary = {}
	var signs: Array[SpeedSign] = []
	for id: String in segments:
		var seg: Dictionary = segments[id]
		var path := Path2D.new()
		path.name = id
		path.curve = Curve2D.new()
		for p: Array in seg["points"]:
			path.curve.add_point(Vector2(p[0], p[1]))
		world.add_child(path)
		paths[id] = path
		if seg.has("jump"):
			# 6.2: points は空中の軌道。レールは先頭と末尾だけ描き、先頭に踏切台を置く。FR-24: 上方に必要速度標識
			var length: float = path.curve.get_baked_length()
			var part: float = length * Tuning.JUMP_RAIL_PART
			path.add_child(_rail(_curve_part(path.curve, 0.0, part)))
			path.add_child(_rail(_curve_part(path.curve, length - part, length)))
			var start: Vector2 = path.curve.get_point_position(0)
			world.add_child(_ramp(start))
			var sign: SpeedSign = SPEED_SIGN_SCENE.instantiate()
			sign.required_speed = float(seg["jump"]["required_speed"])
			sign.kind = "jump"
			sign.glow_strength = glow
			sign.position = start + Vector2(0.0, -Tuning.SIGN_JUMP_HEIGHT)
			world.add_child(sign)
			signs.append(sign)
		else:
			path.add_child(_rail(_curve_part(path.curve, 0.0, path.curve.get_baked_length())))
		if goals and seg["end"]["type"] == "goal":
			var goal: Node2D = GOAL_SCENE.instantiate()
			goal.position = path.curve.get_point_position(path.curve.point_count - 1)
			world.add_child(goal)

	_build_towers(data, world)  # 設計書2章
	if lamp_strength >= 0.0:
		_build_lamps(data, world, lamp_strength)
	var junctions: Dictionary = {}
	for id: String in data["junctions"]:
		var jd: Dictionary = data["junctions"][id]
		var j: Junction = JUNCTION_SCENE.instantiate()
		j.glow_strength = glow
		j.name = id
		j.branches.assign(jd["branches"])
		j.selected = int(jd["default"])
		for b: String in j.branches:
			j.branch_curves.append((paths[b] as Path2D).curve)
		j.position = j.branch_curves[0].get_point_position(0)
		world.add_child(j)
		junctions[id] = j

	var targets: Array[Target] = []
	for od: Dictionary in data.get("objects", []):
		var scene: PackedScene = TARGET_SCENES.get(od["type"])
		if scene == null:
			push_error("未知の標的の種類: %s" % od["type"])
			continue
		var t: Target = scene.instantiate()
		t.glow_strength = glow
		# 原点（下辺中央）を、その位置のレールの上面に接地させる
		# TODO(spec): 坂の上の標的の向きは仕様に無い。レールの傾きに合わせて回した
		var curve: Curve2D = (paths[od["segment"]] as Path2D).curve
		t.transform = curve.sample_baked_with_rotation(float(od["offset"])).translated_local(
				Vector2(0.0, -Tuning.RAIL_WIDTH * 0.5))
		world.add_child(t)
		targets.append(t)
		if t.kind == "wall":
			# FR-19: 標識の下端が wall の上端より SIGN_WALL_GAP 上。wall と一緒に消える
			t.required_speed = float(od.get("required_speed", 0.0))
			var sign: SpeedSign = SPEED_SIGN_SCENE.instantiate()
			sign.required_speed = t.required_speed
			sign.kind = "wall"
			sign.glow_strength = glow
			sign.position = Vector2(0.0, -t.body_size().y - Tuning.SIGN_WALL_GAP)
			t.add_child(sign)
			signs.append(sign)

	return {"paths": paths, "junctions": junctions, "targets": targets, "signs": signs}


## FR-4 と 16.3: 線路。STEEL 6px のレールと上面の光の筋、その下の枕木の破線と下端の影。
## 子の Shadow が、後ろの壁に落ちる影（設計書2章）を描く。画質が低なら影を置かない（ぼかしの影は重い描き方）
static func _rail(points: PackedVector2Array) -> Node2D:
	var rail := Node2D.new()
	rail.name = "Rail"
	rail.draw.connect(func() -> void:
		_dashes(rail, _shifted(points, Vector2(0.0, Tuning.SLEEPER_DROP)), Palette.SLEEPER, Tuning.SLEEPER_W)
		_dashes(rail, _shifted(points, Vector2(0.0, Tuning.SLEEPER_DROP + Tuning.SLEEPER_EDGE_DROP)), Palette.SLEEPER_EDGE,
				Tuning.SLEEPER_EDGE_W)
		rail.draw_polyline(points, Palette.STEEL, Tuning.RAIL_WIDTH)
		rail.draw_polyline(_shifted(points, Vector2(0.0, -Tuning.RAIL_TOP_SHIFT)), Palette.RAIL_TOP, Tuning.RAIL_TOP_W))
	if Quality.plain():
		return rail
	var shadow := Node2D.new()
	shadow.name = "Shadow"
	shadow.z_as_relative = false
	shadow.z_index = Tuning.Z_SHADOW
	shadow.draw.connect(func() -> void:
		DrawUtil.soft_shadow_line(shadow, _shifted(points, Tuning.SHADOW_OFFSET), Tuning.RAIL_WIDTH + Tuning.SLEEPER_W))
	rail.add_child(shadow)
	return rail


## points をすべて v だけずらした折れ線
static func _shifted(points: PackedVector2Array, v: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(p + v)
	return out


## 折れ線に沿って、16.3 の枕木の破線（SLEEPER_ON px 描いて SLEEPER_OFF px 空ける）を描く。区間ごとに頭からそろえる
static func _dashes(ci: CanvasItem, points: PackedVector2Array, color: Color, width: float) -> void:
	for i: int in points.size() - 1:
		var from: Vector2 = points[i]
		var dir: Vector2 = from.direction_to(points[i + 1])
		var length: float = from.distance_to(points[i + 1])
		var s: float = 0.0
		while s < length:
			ci.draw_line(from + dir * s, from + dir * minf(s + Tuning.SLEEPER_ON, length), color, width)
			s += Tuning.SLEEPER_ON + Tuning.SLEEPER_OFF


## 設計書2章: 支柱（鉄骨の塔）の上端の位置。ジャンプでないセグメントの線路の上に、頭から TOWER_SPACING の半分、
## その先 TOWER_SPACING おきに置く（ジャンプの空中の軌道の下には立てない）。戻り値は [{"segment": ID, "top": 線路上の点}]
static func tower_spots(data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in data["segments"]:
		var seg: Dictionary = data["segments"][id]
		if seg.has("jump"):
			continue
		var pts: Array = seg["points"]
		var length: float = _polyline_length(pts)
		var d: float = Tuning.TOWER_SPACING * 0.5
		while d < length:
			out.append({"segment": id, "top": _point_at(pts, d)})
			d += Tuning.TOWER_SPACING
	return out


## 折れ線 points（[x, y] の配列）の頭から距離 d の点
static func _point_at(points: Array, d: float) -> Vector2:
	var left: float = d
	for i: int in range(1, points.size()):
		var a: Vector2 = _point(points[i - 1])
		var b: Vector2 = _point(points[i])
		var l: float = a.distance_to(b)
		if left <= l:
			return a.lerp(b, left / l) if l > 0.0 else a
		left -= l
	return _point(points.back())


## 支柱を Towers の下に、影を TowerShadows の下に（ぼかさない SHADOW_TINT で）描く。
## WORLD_CHUNK_W ごとの塊に分ける（画面の外の塊は描かれない）
static func _build_towers(data: Dictionary, world: Node2D) -> void:
	var ground: float = data["ground_y"]
	var groups: Dictionary = {}  # 塊の番号 → その塊の支柱の上端
	for s: Dictionary in tower_spots(data):
		var top: Vector2 = (s["top"] as Vector2) + Vector2(0.0, Tuning.TOWER_TOP_DROP)
		var key: int = floori(top.x / Tuning.WORLD_CHUNK_W)
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(top)
	var shadows := Node2D.new()
	shadows.name = "TowerShadows"
	shadows.z_as_relative = false
	shadows.z_index = Tuning.Z_SHADOW
	world.add_child(shadows)
	var towers := Node2D.new()
	towers.name = "Towers"
	towers.z_index = Tuning.Z_TOWER
	world.add_child(towers)
	for key: int in groups:
		var tops: Array = groups[key]
		var shadow := Node2D.new()
		shadow.draw.connect(func() -> void:
			for top: Vector2 in tops:
				_draw_tower(shadow, top + Tuning.SHADOW_OFFSET, ground + Tuning.SHADOW_OFFSET.y, true))
		shadows.add_child(shadow)
		var chunk := Node2D.new()
		chunk.draw.connect(func() -> void:
			for top: Vector2 in tops:
				_draw_tower(chunk, top, ground, false))
		towers.add_child(chunk)


## left〜right を覆う、WORLD_CHUNK_W ずつの塊の範囲（x の始まり, 終わり）。始まりは WORLD_CHUNK_W の倍数にそろえる
static func chunk_ranges(left: float, right: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var x: float = floorf(left / Tuning.WORLD_CHUNK_W) * Tuning.WORLD_CHUNK_W
	while x < right:
		out.append(Vector2(x, x + Tuning.WORLD_CHUNK_W))
		x += Tuning.WORLD_CHUNK_W
	return out


## 設計書2章: 照明器具の位置（電球の下端の中央）。x は LAMP_FIRST_X から LAMP_SPACING おき、y は前後 LAMP_REACH の
## 一番高い線路（ジャンプの空中の軌道も含む）より LAMP_CLEARANCE 上
static func lamp_spots(data: Dictionary) -> Array[Vector2]:
	var samples: Array[Vector2] = []  # 線路の上の点（LAMP_SAMPLE おきと、折れ線の頂点。ジャンプの頂点を取りこぼさない）
	var right: float = -INF
	for seg: Dictionary in (data["segments"] as Dictionary).values():
		var pts: Array = seg["points"]
		var length: float = _polyline_length(pts)
		var d: float = 0.0
		while d < length:
			samples.append(_point_at(pts, d))
			d += Tuning.LAMP_SAMPLE
		for p: Array in pts:
			samples.append(_point(p))
			right = maxf(right, p[0])
	# 必要速度の標識（判断材料、L-3）の上端。照明器具は、その上に LAMP_SIGN_GAP 空けて吊る
	var sign_tops: Array[Vector2] = []
	var wall_h: float = (Tuning.TARGET_SIZE["wall"] as Vector2).y
	for od: Dictionary in data.get("objects", []):
		if od.get("type") == "wall":
			var at: Vector2 = _point_at(data["segments"][od["segment"]]["points"], float(od["offset"]))
			sign_tops.append(at - Vector2(0.0, wall_h + Tuning.SIGN_WALL_GAP + Tuning.SIGN_SIZE.y))
	for seg: Dictionary in (data["segments"] as Dictionary).values():
		if seg.has("jump"):
			sign_tops.append(_point(seg["points"][0]) - Vector2(0.0, Tuning.SIGN_JUMP_HEIGHT + Tuning.SIGN_SIZE.y))
	var out: Array[Vector2] = []
	var x: float = Tuning.LAMP_FIRST_X
	while x <= right:
		var y: float = INF
		for s: Vector2 in samples:
			if absf(s.x - x) <= Tuning.LAMP_REACH:
				y = minf(y, s.y - Tuning.LAMP_CLEARANCE)
		for t: Vector2 in sign_tops:
			if absf(t.x - x) <= Tuning.LAMP_REACH:
				y = minf(y, t.y - Tuning.LAMP_SIGN_GAP)
		if y < INF:
			out.append(Vector2(x, y))
		x += Tuning.LAMP_SPACING
	return out


## 照明器具をまとめる Lamps の下に置く。strength は時間帯の照明の強さ（0 なら消えている）
static func _build_lamps(data: Dictionary, world: Node2D, strength: float) -> void:
	var lamps := Node2D.new()
	lamps.name = "Lamps"
	world.add_child(lamps)
	for at: Vector2 in lamp_spots(data):
		var lamp := Lamp.new()
		lamp.position = at
		lamp.strength = strength
		lamps.add_child(lamp)


## 鉄骨の塔1本（縦材2本・X の筋交い・上下の板）。top は上端の中央、bottom は床の y。as_shadow なら影の色だけで塗る
static func _draw_tower(ci: CanvasItem, top: Vector2, bottom: float, as_shadow: bool) -> void:
	if bottom - top.y < Tuning.TOWER_MIN_H:
		return
	var main: Color = Palette.SHADOW_TINT if as_shadow else Palette.TOWER
	var brace: Color = Palette.SHADOW_TINT if as_shadow else Palette.TOWER_BRACE
	var hw: float = Tuning.TOWER_W * 0.5
	var foot: float = bottom - Tuning.TOWER_FOOT_H
	var y: float = top.y
	while y < foot:
		var y2: float = minf(y + Tuning.TOWER_BAY, foot)
		ci.draw_line(Vector2(top.x - hw, y), Vector2(top.x + hw, y2), brace, Tuning.TOWER_BRACE_W)
		ci.draw_line(Vector2(top.x + hw, y), Vector2(top.x - hw, y2), brace, Tuning.TOWER_BRACE_W)
		ci.draw_line(Vector2(top.x - hw, y2), Vector2(top.x + hw, y2), brace, Tuning.TOWER_BRACE_W)
		y = y2
	for dx: float in [-hw, hw]:
		var leg := Rect2(top.x + dx - Tuning.TOWER_LEG_W * 0.5, top.y, Tuning.TOWER_LEG_W, bottom - top.y)
		ci.draw_rect(leg, main)
		if not as_shadow:
			ci.draw_rect(Rect2(leg.position, Vector2(Tuning.TOWER_EDGE_W, leg.size.y)), Palette.TOWER_EDGE)
	ci.draw_rect(Rect2(top.x - hw - Tuning.TOWER_CAP_OUT, top.y - Tuning.TOWER_CAP_H,
			Tuning.TOWER_W + Tuning.TOWER_CAP_OUT * 2.0, Tuning.TOWER_CAP_H), main)
	ci.draw_rect(Rect2(top.x - hw - Tuning.TOWER_FOOT_OUT, foot, Tuning.TOWER_W + Tuning.TOWER_FOOT_OUT * 2.0,
			Tuning.TOWER_FOOT_H), main)


## curve の先頭からの距離 from〜to の区間の折れ線（点同士は直線なので、端と間の点だけで形が決まる）
static func _curve_part(curve: Curve2D, from: float, to: float) -> PackedVector2Array:
	var pts := PackedVector2Array([curve.sample_baked(from)])
	for i: int in range(1, curve.point_count - 1):
		var p: Vector2 = curve.get_point_position(i)
		var d: float = curve.get_closest_offset(p)
		if d > from and d < to:
			pts.append(p)
	pts.append(curve.sample_baked(to))
	return pts


## 16.5: 踏切台（幅 RAMP_W・高さ RAMP_H の直角三角形、GROUND 地に墨の輪郭、斜辺に HAZARD の線）
## TODO(spec): 置く位置は仕様に無い。ジャンプ区間の始点を左下の角にして、レールの上面に載せた
static func _ramp(start: Vector2) -> Node2D:
	var ramp := Node2D.new()
	ramp.name = "Ramp"
	ramp.position = start + Vector2(0.0, -Tuning.RAIL_WIDTH * 0.5)
	var visual := Node2D.new()
	visual.name = "Visual"
	var tri := PackedVector2Array([Vector2.ZERO, Vector2(Tuning.RAMP_W, 0.0), Vector2(Tuning.RAMP_W, -Tuning.RAMP_H)])
	var draw_ramp := func() -> void:
		DrawUtil.fill_gradient(visual, tri, Vector2(0.0, -Tuning.RAMP_H), Vector2.ZERO, [Palette.FLOOR_TOP, Palette.GROUND],
				[0.0, 1.0])
		visual.draw_polyline(tri + PackedVector2Array([tri[0]]), Palette.INK, Tuning.OBJECT_OUTLINE)
		visual.draw_line(tri[0], tri[2], Palette.HAZARD, Tuning.RAMP_LINE_W)
	visual.draw.connect(draw_ramp)
	ramp.add_child(visual)
	return ramp


## FR-20: ground_y に地面（上端に墨の線）。吹っ飛んだ物はここで跳ねて転がる
static func _build_ground(data: Dictionary, world: Node2D) -> void:
	var left: float = INF
	var right: float = -INF
	for seg: Dictionary in (data["segments"] as Dictionary).values():
		for p: Array in seg["points"]:
			left = minf(left, p[0])
			right = maxf(right, p[0])
	left -= Tuning.GROUND_MARGIN
	right += Tuning.GROUND_MARGIN

	var body := StaticBody2D.new()
	body.name = "Ground"
	body.position = Vector2(0.0, data["ground_y"])
	body.z_index = Tuning.Z_GROUND
	body.collision_layer = Tuning.LAYER_GROUND
	body.collision_mask = 0
	var col := CollisionShape2D.new()
	col.shape = WorldBoundaryShape2D.new()  # 既定は上向きの法線で、原点（ground_y）を通る
	body.add_child(col)
	body.add_child(_ground_visual(left, right))
	world.add_child(body)


## 床の見た目（x = left〜right、ground_y が 0）。WORLD_CHUNK_W ごとの塊に分けて描く（画面の外の塊は描かれない）。
## clip なら塊の両端を left・right で切る（無限軌道の区間どうしで二重に描かない）
static func _ground_visual(left: float, right: float, clip: bool = false) -> Node2D:
	var visual := Node2D.new()
	visual.name = "Visual"
	var noise: bool = not Quality.plain()  # 画質が低なら、むら（雑音の模様）を描かない
	for r: Vector2 in chunk_ranges(left, right):
		var chunk := Node2D.new()
		chunk.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # 模様を敷き詰める
		var from: float = maxf(r.x, left) if clip else r.x
		var to: float = minf(r.y, right) if clip else r.y
		chunk.draw.connect(func() -> void: _draw_ground(chunk, from, to, noise))
		visual.add_child(chunk)
	return visual


## 床の見た目の x = left〜right の部分（ground_y が 0）: コンクリートのぼかし・むら、上端に墨の線（16.3）と
## 警告ストライプの縁石。その上の壁に距離の目盛り（設計書2章。x = 0 がスタート、36px = 1m、1m ごとに短い目盛り、
## 10m ごとに長い目盛りと数字。目盛りは left 以上 right 未満のものだけ描き、隣の塊と二重にしない）。
## noise が false（画質が低）なら、むらを描かない
static func _draw_ground(ci: CanvasItem, left: float, right: float, noise: bool) -> void:
	var w: float = right - left
	ci.draw_rect(Rect2(left, 0.0, w, Tuning.GROUND_DEPTH), Palette.FLOOR_BOTTOM)
	DrawUtil.fill_gradient(ci, DrawUtil.rounded_rect(Rect2(left, 0.0, w, Tuning.FLOOR_FADE_H), 0.0), Vector2.ZERO,
			Vector2(0.0, Tuning.FLOOR_FADE_H), [Palette.FLOOR_TOP, Palette.FLOOR_BOTTOM], [0.0, 1.0])
	if noise:
		DrawUtil.tile_noise(ci, Rect2(left, 0.0, w, Tuning.FLOOR_NOISE_H), "blotch", Tuning.FLOOR_NOISE_ALPHA)
	ci.draw_rect(Rect2(left, 0.0, w, Tuning.GROUND_LINE_W), Palette.INK)
	DrawUtil.stripes(ci, Rect2(left, Tuning.GROUND_LINE_W, w, Tuning.CURB_H), Tuning.CURB_STRIPE_W)
	ci.draw_rect(Rect2(left, Tuning.GROUND_LINE_W + Tuning.CURB_H, w, Tuning.CURB_SHADE_H), Palette.BAND_SHADE)
	for m: int in range(maxi(ceili(left / Tuning.PX_PER_METER), 0), ceili(right / Tuning.PX_PER_METER)):
		var x: float = m * Tuning.PX_PER_METER
		var major: bool = m % Tuning.SCALE_MAJOR_EVERY == 0
		ci.draw_line(Vector2(x, -(Tuning.SCALE_MAJOR_H if major else Tuning.SCALE_MINOR_H)), Vector2(x, 0.0), Palette.SCALE_TICK,
				Tuning.SCALE_MAJOR_W if major else Tuning.SCALE_MINOR_W)
		if major:
			ci.draw_string(Fonts.courier, Vector2(x + Tuning.SCALE_LABEL_GAP, -Tuning.SCALE_LABEL_LIFT), "%dm" % m,
					HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.SCALE_FONT_SIZE, Palette.SCALE_TICK)
