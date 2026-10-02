class_name Glow
extends Node2D
## 光る物のにじみ（設計書4章）。親の後ろに、足し算で丸い光を重ねる。強さは時間帯（Tuning.TOD_GLOW）で決まる。
## 兄弟の絵（Visual など）より先に描くよう、足した側が move_child(glow, 0) で先頭に置く

var radius: float = 40.0
var color: Color = Palette.WHITE
var strength: float = 0.0  ## 0 なら出さない


static func make(radius_: float, color_: Color, strength_: float, at: Vector2 = Vector2.ZERO) -> Glow:
	var g := Glow.new()
	g.name = "Glow"
	g.radius = radius_
	g.color = color_
	g.strength = strength_
	g.position = at
	return g


func _ready() -> void:
	material = DrawUtil.additive
	show_behind_parent = true
	visible = strength > 0.0


func _draw() -> void:
	draw_texture_rect(DrawUtil.glow_texture(), Rect2(-Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false,
			Color(color, strength))
