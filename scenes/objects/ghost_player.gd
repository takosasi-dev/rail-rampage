class_name GhostPlayer
extends Node2D
## ゴーストの再生の見た目（設計書 docs/superpowers/specs/2026-09-28-replay-value-design.md の6章）。当たり判定は無い。
## ゲーム画面が World に置き、物理フレームごとに advance(ゲーム内時刻) を呼ぶ。
## 車体は Trolley.draw_body と同じ絵を一度だけ描き（描き直さない）、動かすのは位置と回転だけ（画質「低」でも軽い）。
## 音・光・影・火花は出さない。
## TODO(spec): ゴーストの色は仕様に無い。車体全体を墨の薄い色（Palette.GHOST_TINT）に染めて半透明にする。
##             最後の点を過ぎたら Tuning.GHOST_FADE_TIME 秒で消える

var _dt: float = 0.0
var _points := PackedVector3Array()
var _visual: Node2D


## data は GameState.ghost(n) の辞書
func setup(data: Dictionary) -> void:
	var dt: Variant = data.get("dt")
	var points: Variant = data.get("points")
	if (dt is float or dt is int) and float(dt) > 0.0 and points is PackedVector3Array and not (points as PackedVector3Array).is_empty():
		_dt = float(dt)
		_points = points
	modulate = Palette.GHOST_TINT
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var trolley: String = data.get("trolley", Trolleys.DEFAULT) if data.get("trolley") is String else Trolleys.DEFAULT
	var paint: int = data.get("paint", 0) if data.get("paint") is int else 0
	_visual.draw.connect(func() -> void: Trolley.draw_body(_visual, trolley, paint))
	advance(0.0)


## ゲーム内時刻 time の位置へ（点の間は線形に補う）。最後の点を過ぎたら薄くなって消える
func advance(time: float) -> void:
	if _points.is_empty():
		visible = false
		return
	var last: int = _points.size() - 1
	var f: float = clampf(time / _dt, 0.0, last)
	var i: int = mini(floori(f), maxi(last - 1, 0))
	var a: Vector3 = _points[i]
	var b: Vector3 = _points[mini(i + 1, last)]
	var w: float = f - i
	position = Vector2(lerpf(a.x, b.x, w), lerpf(a.y, b.y, w))
	rotation = lerp_angle(a.z, b.z, w)
	var fade: float = 1.0 - clampf((time - last * _dt) / Tuning.GHOST_FADE_TIME, 0.0, 1.0)
	modulate.a = Palette.GHOST_TINT.a * fade
	visible = fade > 0.0


## 最後の点の時刻（確認用）
func end_time() -> float:
	return (_points.size() - 1) * _dt
