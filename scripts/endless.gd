class_name Endless
extends RefCounted
## 無限軌道（docs/superpowers/specs/2026-09-28-replay-value-design.md の7章）の線路を作る。
## 手で作った区間の型（data/endless/chunks.json）を乱数で選んで先へ先へとつなぎ、ステージの辞書（仕様書6章の形の
## segments・junctions・objects）を区間ごとに足す。通り過ぎた区間は remove_part() で辞書から消す。
## 進んだ距離（区間の始まりの x）で難しさの段が上がり、段の標的（型の "level"）が増え、壁・ジャンプの必要速度が上がる。
## 必要速度は、型の「選ぶ出口」（pick）をたどって走ったときの速さを見積もり、そこから届く値で頭打ちにする（L-5）。
## 壁・ジャンプは pick の道にだけあり、もう一方の出口は失敗要素の無い迂回（L-4）なので、どちらを選んでも詰むことは無い。

const CHUNKS_PATH: String = "res://data/endless/chunks.json"

## ステージの辞書（6章の形）。区間を足すと segments・junctions・objects が増え、消すと減る。
## 最後の区間の出口は、次の区間を足すまで goal にしておく（検証 StageLoader.validate がそのまま通る）
var data: Dictionary = {}
## 今ある区間（古い順）。{"index", "type", "level", "entry", "exit", "segments": {id: 辞書}（data と同じ辞書）,
## "junctions", "objects", "pick": {分岐 id: 選ぶ出口の番号}, "ground": Vector2(左端の x, 右端の x)}
var parts: Array[Dictionary] = []
var trolley_id: String = Trolleys.DEFAULT
var _rng := RandomNumberGenerator.new()
var _count: int = 0  # 作った区間の数（ID の頭に使う）
var _x: float = 0.0  # 次の区間の入口の x
var _last_type: String = ""
# 必要速度の見積もり（pick をたどって走ったときの、最後の区間の出口での状態）
var _speed: float = 0.0
var _momentum: float = 0.0
var _carry: float = 0.0  # 最後の刻みで出口を越えた距離（次の区間へ持ち越す）
static var _types: Array = []


## id: 走らせる車両（強化なしの性能で必要速度を決める。強化は壁・ジャンプを楽にする向きにしか効かない）
func _init(id: String, seed_value: int) -> void:
	trolley_id = id
	_rng.seed = seed_value
	_speed = Progression.stat(id, "speed_base", {})
	# star_thresholds は検証（6.4）を通すための形だけの値（無限軌道に★は無い）
	data = {"id": "endless", "name": "無限軌道", "ground_y": Tuning.ENDLESS_GROUND_Y, "start_segment": "",
			"star_thresholds": [0, 0], "segments": {}, "junctions": {}, "objects": []}


## 区間の型（読むのは1回だけ）
static func types() -> Array:
	if _types.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHUNKS_PATH))
		if parsed is Dictionary and (parsed as Dictionary).get("chunks") is Array:
			_types = parsed["chunks"]
		else:
			push_error("区間の型を読めません: %s" % CHUNKS_PATH)
	return _types


## x（区間の始まり）での難しさの段
static func level_at(x: float) -> int:
	return clampi(int(x / Tuning.ENDLESS_LEVEL_LENGTH), 0, Tuning.ENDLESS_LEVEL_MAX)


## 次の区間を選んで組み、data に足して返す。最初の区間は "start" の型
func add_part() -> Dictionary:
	var t: Dictionary = _pick_type()
	var part: Dictionary = _instantiate(t)
	if parts.is_empty():
		data["start_segment"] = part["entry"]
		part["ground"] = part["ground"] - Vector2(Tuning.GROUND_MARGIN, 0.0)  # 走り出す前の画面の左にも床を敷く
	else:
		data["segments"][parts.back()["exit"]]["end"] = {"type": "next", "segment": part["entry"]}
	parts.append(part)
	_settle(part)
	return part


## 一番古い区間を data から消して返す（ノードを消すのはゲーム画面）
func remove_part() -> Dictionary:
	var part: Dictionary = parts.pop_front()
	for id: String in part["segments"]:
		data["segments"].erase(id)
	for id: String in part["junctions"]:
		data["junctions"].erase(id)
	data["objects"] = (data["objects"] as Array).filter(func(od: Dictionary) -> bool: return data["segments"].has(od["segment"]))
	return part


## 区間を持つセグメント id → 区間の番号（parts の中の位置ではなく "index"）。無ければ -1
func part_of(segment_id: String) -> int:
	for p: Dictionary in parts:
		if (p["segments"] as Dictionary).has(segment_id):
			return p["index"]
	return -1


func _pick_type() -> Dictionary:
	var all: Array = types()
	if _count == 0:
		for t: Dictionary in all:
			if t.get("start", false):
				return t
	var level: int = level_at(_x)
	var candidates: Array = all.filter(func(t: Dictionary) -> bool:
		return not t.get("start", false) and int(t["min_level"]) <= level and t["id"] != _last_type)
	var total: float = 0.0
	for t: Dictionary in candidates:
		total += float(t["weight"])
	var r: float = _rng.randf() * total
	for t: Dictionary in candidates:
		r -= float(t["weight"])
		if r < 0.0:
			return t
	return candidates.back()


## 型を x = _x、レールの高さ ENDLESS_RAIL_Y に置いた区間。ID の頭に "c<番号>_" を付ける
func _instantiate(t: Dictionary) -> Dictionary:
	var prefix: String = "c%d_" % _count
	var level: int = level_at(_x)
	var part: Dictionary = {"index": _count, "type": t["id"], "level": level, "entry": prefix + str(t["entry"]),
			"exit": "", "segments": {}, "junctions": {}, "objects": [], "pick": {}}
	var right: float = _x
	for local: String in t["segments"]:
		var s: Dictionary = t["segments"][local]
		var pts: Array = []
		for p: Array in s["points"]:
			pts.append([float(p[0]) + _x, float(p[1]) + Tuning.ENDLESS_RAIL_Y])
			right = maxf(right, float(p[0]) + _x)
		var seg: Dictionary = {"points": pts}
		var end: Dictionary = s["end"]
		match str(end["type"]):
			"next":
				seg["end"] = {"type": "next", "segment": prefix + str(end["segment"])}
			"junction":
				seg["end"] = {"type": "junction", "id": prefix + str(end["id"])}
			_:  # exit: 次の区間を足すまで goal
				seg["end"] = {"type": "goal"}
				part["exit"] = prefix + local
		if s.has("jump"):
			seg["jump"] = {"required_speed": float(s["jump"]["required_speed"])}
		part["segments"][prefix + local] = seg
		data["segments"][prefix + local] = seg
	for local: String in t["junctions"]:
		var j: Dictionary = t["junctions"][local]
		var jd: Dictionary = {"branches": [prefix + str(j["branches"][0]), prefix + str(j["branches"][1])],
				"default": int(j["default"])}
		part["junctions"][prefix + local] = jd
		data["junctions"][prefix + local] = jd
		part["pick"][prefix + local] = int(j["pick"])
	for od: Dictionary in t["objects"]:
		if int(od.get("level", 0)) > level:
			continue
		var o: Dictionary = od.duplicate()
		o.erase("level")
		o["segment"] = prefix + str(od["segment"])
		part["objects"].append(o)
		data["objects"].append(o)
	part["ground"] = Vector2(_x, right)
	_x = right
	_last_type = t["id"]
	_count += 1
	return part


## 区間の中の、pick をたどる道（セグメント id の順）
static func pick_route(part: Dictionary) -> Array[String]:
	var route: Array[String] = [part["entry"]]
	while true:
		var end: Dictionary = part["segments"][route.back()]["end"]
		if end["type"] == "next" and (part["segments"] as Dictionary).has(end["segment"]):
			route.append(end["segment"])
		elif end["type"] == "junction":
			var j: Dictionary = part["junctions"][end["id"]]
			route.append(j["branches"][part["pick"][end["id"]]])
		else:
			break
	return route


## pick の道を強化なしの車両で走ったときの速さを見積もり（ゲーム画面と同じ式を同じ順に: 勢いが減る → 速度が目標へ
## 近づく → 進む → 触れた標的の勢いを足す）、壁・ジャンプの必要速度を「段の値」と「着く速さ − 余裕」の小さい方にする。
## 見積もりは控えめ: 爆発に巻き込まれて壊れる標的の勢いは数えず、標的には車体の前の端が触れた所で当たる
## （実際はもっと速く着く。ゲーム画面で自動操縦して確かめる、tests/checks_endless.gd）
func _settle(part: Dictionary) -> void:
	var events: Array = []  # [道の頭からの距離, 標的の辞書かジャンプのセグメント]
	var base: float = 0.0
	var reach: float = Tuning.TROLLEY_TOP_W * 0.5
	for id: String in pick_route(part):
		var seg: Dictionary = part["segments"][id]
		if seg.has("jump"):
			events.append([base, seg])
		for od: Dictionary in part["objects"]:
			if od["segment"] == id:
				var half: float = (Tuning.TARGET_SIZE[od["type"]] as Vector2).x * 0.5
				events.append([base + float(od["offset"]) - reach - half, od])
		base += StageLoader._polyline_length(seg["points"])
	events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var gain: float = Progression.stat(trolley_id, "momentum_gain", {})
	var decay: float = Tuning.MOMENTUM_DECAY * Progression.stat(trolley_id, "momentum_decay", {})
	var speed_base: float = Progression.stat(trolley_id, "speed_base", {})
	var speed_max: float = Progression.stat(trolley_id, "speed_max", {})
	var dt: float = Tuning.ENDLESS_SIM_DT
	var d: float = _carry
	var i: int = 0
	while true:
		while i < events.size() and events[i][0] <= d:
			var e: Dictionary = events[i][1]
			if e.has("jump"):
				e["jump"]["required_speed"] = _required(e["jump"]["required_speed"], "jump_factor", part["level"])
			else:
				if e["type"] == "wall" and not e.get("blast", false):
					e["required_speed"] = _required(e["required_speed"], "wall_factor", part["level"])
				_momentum = minf(_momentum + Tuning.TARGET_MOMENTUM[e["type"]] * gain, Tuning.MOMENTUM_MAX)
			i += 1
		if d >= base:
			break
		_momentum = maxf(_momentum - decay * dt, 0.0)
		_speed = lerpf(_speed, minf(speed_base + _momentum * Tuning.SPEED_PER_MOMENTUM, speed_max), Tuning.SPEED_LERP * dt)
		d += _speed * dt
	_carry = d - base


## 段 level の必要速度（型の値 + 段 × ENDLESS_REQUIRED_STEP）を、今の見積もりの速さ（_speed）で届く値で頭打ちにする。
## 車両の壁・ジャンプへの強さ（factor_key）を掛けて表示の単位に丸めた値が「速さ − REQUIRED_SPEED_MARGIN」以下になるように
func _required(base_value: float, factor_key: String, level: int) -> float:
	var want: float = base_value + Tuning.ENDLESS_REQUIRED_STEP * level
	var factor: float = Progression.stat(trolley_id, factor_key, {})
	var div: float = Tuning.DISPLAY_SPEED_DIV
	var cap: float = floorf((_speed - Tuning.REQUIRED_SPEED_MARGIN - div * 0.5) / factor / div) * div
	return minf(want, cap)
