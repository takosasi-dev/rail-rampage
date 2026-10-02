class_name Lamp
extends Node2D
## 天井から吊った照明器具（設計書2章・4章）。原点は電球の下端の中央。吊り棒は上へ LAMP_ROD_H 伸ばす。
## strength が 0 より大きければ点いて、下へ円錐の光（PointLight2D）を落とし、電球を光る物として描く。
## 画質が低なら円錐の光は落とさない（電球は点いて見える。trolleys-and-display-design.md 4章）

var strength: float = 0.0


func _ready() -> void:
	z_index = Tuning.Z_LAMP
	var housing := Node2D.new()
	housing.name = "Housing"
	housing.draw.connect(_draw_housing.bind(housing))
	add_child(housing)
	var on: bool = strength > 0.0
	var bulb := Node2D.new()
	bulb.name = "Bulb"
	if on:
		bulb.material = DrawUtil.unshaded
		bulb.add_child(Glow.make(Tuning.LAMP_GLOW_RADIUS, Palette.LAMP_BULB, strength))
	bulb.draw.connect(func() -> void: bulb.draw_rect(Tuning.LAMP_BULB_RECT, Palette.LAMP_BULB if on else Palette.LAMP_OFF))
	add_child(bulb)
	var light := PointLight2D.new()
	light.name = "Light"
	light.texture = DrawUtil.cone_texture()
	light.texture_scale = Tuning.LAMP_LIGHT_SCALE
	# 円錐の頂点（絵の上端の中央）を電球に合わせる。offset は texture_scale を掛けた後の px
	light.offset = Vector2(0.0, light.texture.get_height() * Tuning.LAMP_LIGHT_SCALE * 0.5)
	light.color = Palette.LAMP_LIGHT
	light.energy = strength * Tuning.LAMP_ENERGY
	light.enabled = on and Quality.lights()
	add_child(light)


## 吊り棒と、台形の笠（STEEL、墨の輪郭）
func _draw_housing(ci: Node2D) -> void:
	ci.draw_rect(Rect2(-Tuning.LAMP_ROD_W * 0.5, -Tuning.LAMP_ROD_H, Tuning.LAMP_ROD_W, Tuning.LAMP_ROD_H - Tuning.LAMP_HOUSING_H),
			Palette.STEEL)
	var top: float = -Tuning.LAMP_HOUSING_H
	var pts := PackedVector2Array([Vector2(-Tuning.LAMP_HOUSING_TOP_W * 0.5, top), Vector2(Tuning.LAMP_HOUSING_TOP_W * 0.5, top),
			Vector2(Tuning.LAMP_HOUSING_BOTTOM_W * 0.5, 0.0), Vector2(-Tuning.LAMP_HOUSING_BOTTOM_W * 0.5, 0.0)])
	ci.draw_colored_polygon(pts, Palette.STEEL)
	pts.append(pts[0])
	ci.draw_polyline(pts, Palette.INK, Tuning.LAMP_OUTLINE)
