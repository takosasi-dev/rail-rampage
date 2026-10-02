extends Control
## リザルトと修了証書の判子（17.7）。合格は直径150の丸、不合格は 176×96 の二重線の角。どちらも STAMP 色。
## 位置（左上）は置く側が決める。press() で出し、中心まわりに傾けて拡大率 1.6→1.0 で押す。

const UiButton := preload("res://scenes/ui/ui_button.gd")

var passed: bool = true  ## true で「合格」の丸、false で「不合格」の角
var label: String = "合格"  ## 丸判子の文字（修了証書は「修了」）

var _sub_font: Font = UiButton.spaced(Fonts.BIZ_BOLD)  # 「衝突試験場」（デザイン案は字間 0.1em）


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	hide()


## 判子を押す。Engine.time_scale に関係なく実時間で縮む（スローモーの途中でリザルトを開いても遅くならない）
func press() -> void:
	size = Tuning.RESULT_PASS_STAMP_SIZE if passed else Tuning.RESULT_FAIL_STAMP_SIZE
	pivot_offset = size * 0.5
	rotation = deg_to_rad(Tuning.RESULT_PASS_STAMP_DEG if passed else Tuning.RESULT_FAIL_STAMP_DEG)
	modulate.a = Tuning.RESULT_STAMP_ALPHA
	scale = Vector2.ONE * Tuning.RESULT_STAMP_POP_SCALE
	show()
	create_tween().set_ignore_time_scale(true).tween_property(self, "scale", Vector2.ONE, Tuning.RESULT_STAMP_POP_TIME)
	Audio.play(&"stamp")


func _draw() -> void:
	if passed:
		var w: float = Tuning.RESULT_STAMP_LINE
		draw_arc(size * 0.5, size.x * 0.5 - w * 0.5, 0.0, TAU, Tuning.RESULT_STAMP_ARC_POINTS, Palette.STAMP, w, true)
		_text(label, Fonts.DELA, Tuning.RESULT_PASS_STAMP_FONT_SIZE, Tuning.RESULT_PASS_STAMP_TEXT_Y)
		# TODO(spec): 丸判子の「衝突試験場」はデザイン案にあって仕様に無い。デザイン案の 12px は 16.2 の下限 13px に上げた
		_text("衝突試験場", _sub_font, Tuning.RESULT_PASS_STAMP_SUB_FONT_SIZE, Tuning.RESULT_PASS_STAMP_SUB_Y)
	else:
		# 二重線: 線・すき間・線を同じ太さで（デザイン案の CSS の double）
		var w: float = Tuning.RESULT_STAMP_DOUBLE_LINE
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(-w * 0.5), Palette.STAMP, false, w)
		draw_rect(r.grow(-w * 2.5), Palette.STAMP, false, w)
		_text("不合格", Fonts.DELA, Tuning.RESULT_FAIL_STAMP_FONT_SIZE, size.y * 0.5)
	_draw_wear()


## 設計書5章: インクのかすれ。線の上に紙の色の短い切れ目を入れる（判子の外の文字は消さないよう、線の上だけ）
func _draw_wear() -> void:
	var w: float = Tuning.RESULT_STAMP_WEAR_W
	if passed:
		var mid: float = size.x * 0.5 - Tuning.RESULT_STAMP_LINE * 0.5
		for m: Array in Tuning.RESULT_STAMP_WEAR_PASS:
			var from: float = deg_to_rad(m[0])
			draw_arc(size * 0.5, mid + float(m[2]), from, from + deg_to_rad(m[1]), Tuning.SHORT_ARC_POINTS, Palette.PAPER, w, true)
	else:
		var depth: float = Tuning.RESULT_STAMP_DOUBLE_LINE * 3.0  # 二重線の外側から内側まで
		for m: Array in Tuning.RESULT_STAMP_WEAR_FAIL:
			var y: float = 0.0 if m[1] == 0 else size.y - depth
			draw_rect(Rect2(size.x * float(m[0]), y, Tuning.RESULT_STAMP_WEAR_LEN, depth), Palette.PAPER)


## 1行を左右中央、行の中心の高さ center_y に描く
func _text(s: String, font: Font, font_size: int, center_y: float) -> void:
	var baseline: float = center_y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(0.0, baseline), s, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Palette.STAMP)
