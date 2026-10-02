extends Button
## メニュー画面のボタン（17.1、FR-47a）。主ボタン（警告黄の地）と副ボタン（地なし・2pxの枠）。
## フォーカス中は墨4pxの枠＋警告黄4pxの外枠。フォーカスが移ると ui_move、押すと ui_select を鳴らす。
## メニュー画面の共通部品（背景・文字・フォーカス）も静的関数で持つ。使う側は preload して呼ぶ（M5 の画面も使う）。

@export var primary: bool = false
@export var on_ink: bool = true  ## 墨地の上に置くか（false なら生成り地）
@export var key_hint: String = ""  ## 右端のキー表示（Courier Prime Bold）

static var _quiet: bool = false  # focus_quietly() の間は ui_move を鳴らさない

var _text_color: Color = Palette.INK


func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_font_override("font", Fonts.DELA)
	if primary:
		add_theme_font_size_override("font_size", Tuning.UI_PRIMARY_FONT_SIZE)
		custom_minimum_size.y = Tuning.UI_PRIMARY_H
		if on_ink:
			paint(Palette.HAZARD, Palette.HAZARD, 0, Palette.INK)
			_add_shadow(Palette.SLEEPER, Tuning.UI_PRIMARY_SHADOW)
		else:
			paint(Palette.HAZARD, Palette.INK, Tuning.UI_PRIMARY_BORDER_ON_PAPER, Palette.INK)
			_add_shadow(Palette.INK, Tuning.UI_PRIMARY_SHADOW_ON_PAPER)
	else:
		add_theme_font_size_override("font_size", Tuning.UI_SECONDARY_FONT_SIZE)
		custom_minimum_size.y = Tuning.UI_SECONDARY_H
		var fg: Color = Palette.PAPER if on_ink else Palette.INK
		paint(null, fg, Tuning.UI_THIN_BORDER, fg)
	pressed.connect(Audio.play.bind(&"ui_select"))
	setup_focus(self)


## 地（null なら地なし）・枠・文字の色を決める。マウスを乗せても押しても見た目は変えない（状態はフォーカスの枠で示す）
func paint(fill: Variant, border: Color, border_w: int, text_color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = fill is Color
	if fill is Color:
		sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.content_margin_left = Tuning.UI_BUTTON_PAD
	sb.content_margin_right = Tuning.UI_BUTTON_PAD
	if not key_hint.is_empty():
		sb.content_margin_right += _key_width() + Tuning.UI_KEY_GAP
	for s: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		add_theme_stylebox_override(s, sb)
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color",
			&"font_focus_color"]:
		add_theme_color_override(c, text_color)
	_text_color = text_color
	queue_redraw()


func _draw() -> void:
	if key_hint.is_empty():
		return
	var font: Font = Fonts.courier_bold
	var fs: int = Tuning.UI_KEY_FONT_SIZE
	var baseline: float = (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(size.x - Tuning.UI_BUTTON_PAD - _key_width(), baseline), key_hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _text_color)


func _key_width() -> float:
	return Fonts.courier_bold.get_string_size(key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.UI_KEY_FONT_SIZE).x


## ずらした影（16.4、ぼかしなし）。ボタンの後ろに描く
func _add_shadow(color: Color, offset: Vector2) -> void:
	var shadow := ColorRect.new()
	shadow.color = color
	shadow.show_behind_parent = true
	shadow.mouse_filter = MOUSE_FILTER_IGNORE
	shadow.set_anchors_preset(PRESET_FULL_RECT)
	shadow.offset_left = offset.x
	shadow.offset_right = offset.x
	shadow.offset_top = offset.y
	shadow.offset_bottom = offset.y
	add_child(shadow, false, INTERNAL_MODE_FRONT)


## c をメニューの操作に合わせる（FR-47a）: フォーカス中は二重の枠を描き、フォーカスが移ったら ui_move を鳴らし、
## マウスを乗せたらフォーカスを移す。ボタン以外（音量のスライダーなど）にも使う
static func setup_focus(c: Control) -> void:
	c.focus_entered.connect(func() -> void:
		c.z_index = 1  # 枠を隣のボタンより手前に描く
		c.queue_redraw()
		if not _quiet:
			Audio.play(&"ui_move"))
	c.focus_exited.connect(func() -> void:
		c.z_index = 0
		c.queue_redraw())
	# TODO(spec): マウスを乗せたときの動きは仕様に無い。乗せた物にフォーカスを移す（枠がマウスに付いてくる）
	c.mouse_entered.connect(func() -> void:
		if c.focus_mode != Control.FOCUS_NONE and not c.has_focus():
			c.grab_focus())
	c.draw.connect(func() -> void:
		if c.has_focus():
			draw_focus(c, Rect2(Vector2.ZERO, c.size)))


## FR-47a: 墨4pxの枠＋その外に警告黄4pxの外枠
static func draw_focus(ci: CanvasItem, rect: Rect2) -> void:
	var w: float = Tuning.UI_FOCUS_W
	ci.draw_rect(rect.grow(w * 0.5), Palette.INK, false, w)
	ci.draw_rect(rect.grow(w + w * 0.5), Palette.HAZARD, false, w)


## 効果音を鳴らさずにフォーカスを置く（画面を開いた時など、プレイヤーが動かしたのではない移動）
static func focus_quietly(c: Control) -> void:
	_quiet = true
	c.grab_focus()
	_quiet = false


## メニュー画面の背景（17.1）: 墨地に生成り5%の方眼と、明るい粒（設計書5章）。
## ci の texture_repeat は TEXTURE_REPEAT_ENABLED にしておく（粒を敷き詰めるため）
static func draw_menu_bg(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, Palette.INK)
	var line := Color(Palette.PAPER, Tuning.UI_GRID_ALPHA)
	var x: float = rect.position.x
	while x < rect.end.x:
		ci.draw_rect(Rect2(x, rect.position.y, 1, rect.size.y), line)
		x += Tuning.UI_GRID_STEP
	var y: float = rect.position.y
	while y < rect.end.y:
		ci.draw_rect(Rect2(rect.position.x, y, rect.size.x, 1), line)
		y += Tuning.UI_GRID_STEP
	DrawUtil.tile_noise(ci, rect, "fleck", Tuning.MENU_FLECK_ALPHA)


static func style_label(l: Label, font: Font, font_size: int, color: Color) -> void:
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)


## 字間を空けた英字ラベルの書体（デザイン案の letter-spacing）
static func spaced(font: Font) -> Font:
	var f := FontVariation.new()
	f.base_font = font
	f.spacing_glyph = Tuning.UI_LETTER_SPACING
	return f
