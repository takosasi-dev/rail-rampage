class_name Fireball
extends Node2D
## 爆発の火の玉（② 設計書3章）。橙の外側がふくらみ、白い芯が縮んで消える。足し算で重ねる光る物

var _age: float = 0.0


func _ready() -> void:
	material = DrawUtil.additive
	z_index = Tuning.Z_FX
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # 物理フレームの外で動かすため


func _process(delta: float) -> void:
	_age += delta
	if _age >= Tuning.FIREBALL_LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = _age / Tuning.FIREBALL_LIFE
	var r: float = lerpf(Tuning.FIREBALL_R.x, Tuning.FIREBALL_R.y, ease(t, Tuning.FIREBALL_EASE))
	var fade: float = 1.0 - t
	var tex: Texture2D = DrawUtil.glow_texture()
	draw_texture_rect(tex, Rect2(-Vector2.ONE * r, Vector2.ONE * r * 2.0), false, Color(Palette.FX_FIRE_EDGE, fade))
	var core: float = r * Tuning.FIREBALL_CORE * (1.0 - t * Tuning.FIREBALL_CORE_SHRINK)
	draw_texture_rect(tex, Rect2(-Vector2.ONE * core, Vector2.ONE * core * 2.0), false, Color(Palette.HAZARD, fade))
	var white: float = core * Tuning.FIREBALL_WHITE
	draw_texture_rect(tex, Rect2(-Vector2.ONE * white, Vector2.ONE * white * 2.0), false, Color(Palette.FX_FIRE_CORE, fade))
