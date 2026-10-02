class_name Impact
extends Node2D
## 衝突の星（② 設計書3章）。警告黄の尖った星に墨の輪郭。一瞬ふくらんで消える。光る物（暗い時間帯でも明るい）

var radius: float = Tuning.IMPACT_R_MIN

var _age: float = 0.0
var _star := PackedVector2Array()


func _ready() -> void:
	material = DrawUtil.unshaded
	z_index = Tuning.Z_FX
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # 物理フレームの外で動かすため
	rotation = randf() * TAU
	for i: int in Tuning.IMPACT_SPIKES * 2:
		var r: float = radius if i % 2 == 0 else radius * Tuning.IMPACT_INNER
		_star.append(Vector2.from_angle(TAU * i / (Tuning.IMPACT_SPIKES * 2)) * r)
	_apply(0.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= Tuning.IMPACT_LIFE:
		queue_free()
		return
	_apply(_age / Tuning.IMPACT_LIFE)


## t（0〜1）の大きさと濃さ
func _apply(t: float) -> void:
	scale = Vector2.ONE * lerpf(Tuning.IMPACT_SCALE.x, Tuning.IMPACT_SCALE.y, ease(t, Tuning.IMPACT_EASE))
	modulate.a = 1.0 - t * t


func _draw() -> void:
	draw_colored_polygon(_star, Palette.HAZARD)
	var outline := _star.duplicate()
	outline.append(_star[0])
	draw_polyline(outline, Palette.INK, Tuning.IMPACT_OUTLINE, true)
