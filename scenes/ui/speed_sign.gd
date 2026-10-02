class_name SpeedSign
extends Node2D
## 必要速度標識（FR-19, FR-24）。原点は下辺の中央。毎フレーム現在速度と比べ、
## 足りれば「○ 70km/h」（白地・墨文字）、足りなければ「× 70km/h」（朱地・白文字）にする。書体は Dela Gothic One

var required_speed: float = 0.0
var kind: String = "wall"  # "wall" か "jump"（車両の倍率を掛けるときに使う。StageLoader.build が入れる）
var speed_of: Callable  # 現在速度（px/s）を返す
var ok: bool = false
var glow_strength: float = 0.0  ## 設計書4章: 時間帯のにじみの強さ（StageLoader.build が入れる）
var _glow: Glow = null


func _ready() -> void:
	z_index = Tuning.Z_SIGN
	global_rotation = 0.0  # 坂の上の wall に付いても傾けない
	material = DrawUtil.unshaded  # 設計書4章: 光る物
	_glow = Glow.make(Tuning.SIGN_GLOW_RADIUS, Palette.STAMP, glow_strength, Vector2(0.0, -Tuning.SIGN_SIZE.y * 0.5))
	add_child(_glow)
	_update()
	_glow.color = Palette.WHITE if ok else Palette.STAMP


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var now_ok: bool = speed_of.is_valid() and speed_of.call() >= required_speed
	if now_ok != ok:
		ok = now_ok
		queue_redraw()
		if _glow != null:
			_glow.color = Palette.WHITE if ok else Palette.STAMP
			_glow.queue_redraw()


func text() -> String:
	return "%s %dkm/h" % ["○" if ok else "×", Display.to_display_speed(required_speed)]


func _draw() -> void:
	var s: Vector2 = Tuning.SIGN_SIZE
	var rect := Rect2(-s.x * 0.5, -s.y, s.x, s.y)
	draw_rect(Rect2(rect.position + Vector2.ONE * Tuning.SIGN_DEPTH, rect.size), Palette.INK)  # 設計書3章: 板の厚み
	draw_rect(rect, Palette.WHITE if ok else Palette.STAMP)
	draw_rect(rect.grow(-Tuning.SIGN_OUTLINE * 0.5), Palette.INK, false, Tuning.SIGN_OUTLINE)
	for sx: float in [-1.0, 1.0]:  # 四隅のボルト
		for sy: float in [0.0, 1.0]:
			var at := Vector2(sx * (s.x * 0.5 - Tuning.SIGN_BOLT_INSET.x),
					-s.y + Tuning.SIGN_BOLT_INSET.y + sy * (s.y - Tuning.SIGN_BOLT_INSET.y * 2.0))
			draw_circle(at, Tuning.SIGN_BOLT_R, Palette.INK)
	var font: Font = Fonts.DELA
	var fs: int = Tuning.SIGN_FONT_SIZE
	var w: float = font.get_string_size(text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var baseline: float = rect.get_center().y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(-w * 0.5, baseline), text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Palette.INK if ok else Palette.WHITE)
