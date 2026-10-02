class_name Puffs
extends Node2D
## 砂ぼこり・煙（② 設計書3章）。kind: dust（衝突・着地・激突）・smoke（爆発）。
## ぼかした丸がふくらみながら上って消える。照明を受ける（暗い時間帯は暗く見える）

var kind: String = "dust"

var _puffs: Array = []  # [出る所, 横の流れ]
var _age: float = 0.0


func _ready() -> void:
	z_index = Tuning.Z_FX
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # 物理フレームの外で動かすため
	var spread: float = Tuning.PUFF_SPREAD[kind]
	for i: int in Quality.count(Tuning.PUFF_COUNT[kind]):  # 画質が中・低なら数を減らす
		_puffs.append([Vector2(randf_range(-spread, spread), randf_range(-spread, spread) * Tuning.PUFF_SPREAD_Y),
				randf_range(-Tuning.PUFF_DRIFT, Tuning.PUFF_DRIFT)])


func _process(delta: float) -> void:
	_age += delta
	if _age >= Tuning.PUFF_LIFE[kind]:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = _age / Tuning.PUFF_LIFE[kind]
	var r_range: Vector2 = Tuning.PUFF_R[kind]
	var r: float = lerpf(r_range.x, r_range.y, ease(t, Tuning.PUFF_EASE))
	var color: Color = Palette.FX_SMOKE if kind == "smoke" else Palette.FX_DUST
	var alpha: float = Tuning.PUFF_ALPHA[kind] * (1.0 - t)
	var rise: float = Tuning.PUFF_RISE[kind] * _age
	for p: Array in _puffs:
		var c: Vector2 = (p[0] as Vector2) + Vector2(float(p[1]) * rise, -rise)
		draw_texture_rect(DrawUtil.glow_texture(), Rect2(c - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, Color(color, alpha))
