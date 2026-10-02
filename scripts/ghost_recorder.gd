class_name GhostRecorder
extends RefCounted
## ゴーストの記録（設計書 docs/superpowers/specs/2026-09-28-replay-value-design.md の6章）。
## ゲーム画面が物理フレームごとに sample() を呼び、合格したら data() を GameState.submit_ghost に渡す。
## 点 k はゲーム内時刻 k × dt のトロッコの位置と回転（前後のフレームの間を線形に補って、ちょうどその時刻の値にする）。
## 点 0 だけは最初のフレーム（時刻 1/60 秒）の値（時刻 0 の値は受け取らない。出だしの1フレーム分だけ前にずれる）。
## TODO(spec): 長い走行の大きさの上限は仕様に無い。点が Tuning.GHOST_MAX_POINTS に届いたら1つおきに間引いて dt を倍にする
##             （走行の全部を残したまま、点の数は上限を超えない。粗くなるのは上限を超えるほど長い走行だけ）

var _dt: float = Tuning.GHOST_SAMPLE_DT
var _points := PackedVector3Array()
var _has_prev: bool = false
var _prev_time: float = 0.0
var _prev := Vector3.ZERO  # 前のフレームの (x, y, 回転)


## ゲーム内時刻 time のトロッコの位置と回転
func sample(time: float, pos: Vector2, rot: float) -> void:
	var now := Vector3(pos.x, pos.y, rot)
	while _points.size() * _dt <= time:
		var t: float = _points.size() * _dt
		if not _has_prev or time <= _prev_time:
			_points.append(now)  # 最初の点（時刻 0 の後の最初のフレーム）はそのフレームの値
		else:
			var w: float = clampf((t - _prev_time) / (time - _prev_time), 0.0, 1.0)
			_points.append(Vector3(lerpf(_prev.x, now.x, w), lerpf(_prev.y, now.y, w), lerp_angle(_prev.z, now.z, w)))
		if _points.size() >= Tuning.GHOST_MAX_POINTS:
			_halve()
	_has_prev = true
	_prev_time = time
	_prev = now


## {"dt": 記録の間隔, "points": PackedVector3Array（x, y, 回転）}。得点・車両・塗装はゲーム画面が足す
func data() -> Dictionary:
	return {"dt": _dt, "points": _points.duplicate()}


## 1つおきに残す（点 2k が新しい点 k。時刻は 2k × 古い dt = k × 新しい dt で合う）
func _halve() -> void:
	var kept := PackedVector3Array()
	for i: int in range(0, _points.size(), 2):
		kept.append(_points[i])
	_points = kept
	_dt *= 2.0
