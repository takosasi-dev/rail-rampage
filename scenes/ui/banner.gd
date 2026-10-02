class_name Banner
extends Control
## 試験開始バナー（FR-36b、16.6）。画面上部中央（上端から BANNER_TOP px）に「第N試験　試験開始」を
## BANNER_DURATION 秒出す。両端に警告黄×墨のストライプ、中央は PAPER 地に Courier Prime の試験番号と
## Dela Gothic One の「試験開始」。表示中もトロッコは走り、入力も受け付ける（クリックを止めない）。

const TITLE: String = "試験開始"

var number: int = 1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Tuning.BANNER_END_W * 2.0 + Tuning.BANNER_PAD_X * 2.0 + _number_w() + Tuning.BANNER_GAP + _title_w(),
			Tuning.BANNER_H)
	position = Vector2((get_viewport_rect().size.x - size.x) * 0.5, Tuning.BANNER_TOP)
	var tween := create_tween()
	tween.tween_interval(Tuning.BANNER_DURATION - Tuning.BANNER_FADE)
	tween.tween_property(self, "modulate:a", 0.0, Tuning.BANNER_FADE)
	tween.tween_callback(queue_free)


func number_text() -> String:
	return Display.stage_title(number)


func text() -> String:
	return "%s　%s" % [number_text(), TITLE]


func _number_w() -> float:
	return Fonts.courier_bold.get_string_size(number_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.BANNER_NUM_FONT_SIZE).x


func _title_w() -> float:
	return Fonts.DELA.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.BANNER_FONT_SIZE).x


func _draw() -> void:
	var end_w: float = Tuning.BANNER_END_W
	DrawUtil.stripes(self, Rect2(0.0, 0.0, end_w, size.y), Tuning.BANNER_STRIPE_W)
	DrawUtil.stripes(self, Rect2(size.x - end_w, 0.0, end_w, size.y), Tuning.BANNER_STRIPE_W)
	draw_rect(Rect2(end_w, 0.0, size.x - end_w * 2.0, size.y), Palette.PAPER)
	var x: float = end_w + Tuning.BANNER_PAD_X
	_draw_centered(Fonts.courier_bold, x, number_text(), Tuning.BANNER_NUM_FONT_SIZE)
	_draw_centered(Fonts.DELA, x + _number_w() + Tuning.BANNER_GAP, TITLE, Tuning.BANNER_FONT_SIZE)


## 縦を中央にそろえて x から書く
func _draw_centered(font: Font, x: float, s: String, fs: int) -> void:
	var baseline: float = (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.INK)
