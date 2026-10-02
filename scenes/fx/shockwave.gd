class_name Shockwave
extends Node2D
## 爆発の衝撃波の輪（② 設計書3章）。max_radius（FR-16 の EXPLOSION_RADIUS）まで広がって消える。
## 巻き込む範囲が目で分かる。光る物

var max_radius: float = Tuning.EXPLOSION_RADIUS
var radius: float = 0.0

var _age: float = 0.0


func _ready() -> void:
	material = DrawUtil.unshaded
	z_index = Tuning.Z_FX
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # 物理フレームの外で動かすため


func _process(delta: float) -> void:
	_age += delta
	if _age >= Tuning.SHOCKWAVE_LIFE:
		queue_free()
		return
	radius = max_radius * ease(_age / Tuning.SHOCKWAVE_LIFE, Tuning.SHOCKWAVE_EASE)
	queue_redraw()


func _draw() -> void:
	var t: float = _age / Tuning.SHOCKWAVE_LIFE
	if radius <= 0.0:
		return
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, Tuning.SHOCKWAVE_ARC_POINTS, Color(Palette.PAPER, 1.0 - t),
			Tuning.SHOCKWAVE_W * (1.0 - t) + Tuning.SHOCKWAVE_MIN_W, true)
