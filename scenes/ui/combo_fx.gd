class_name ComboFx
extends Control
## コンボの表示と、コンボ専用の演出（依頼者の追加要望で、仕様に無い）。
## - コンボ数と倍率の札（FR-42、17.4: 警告黄の地に墨3pxの枠。コンボ2以上で、切れていないときだけ）
## - 倍率が上がった瞬間（5・10・15・20コンボ）に、画面上部へ「x2.0!」の札を判子のように押し、コンボ表示を弾ませる
## - 倍率 COMBO_EDGE_MULT 以上に上がったら、画面の上下の縁にストライプを光らせる
## - 最大倍率に届いたら maxed を出す（Game がスローモーと大きめの揺れを起こす）
## - COMBO_BREAK_MIN 以上のコンボが途切れたら「N COMBO」を出す

signal maxed

var _stamp: Label = null  # 表示中の倍率の札
var _bounce_tween: Tween = null
var _edge_tween: Tween = null

@onready var _label: Label = $ComboLabel
@onready var _edge: Control = $Edge


func _ready() -> void:
	var ls := LabelSettings.new()
	ls.font = Fonts.DELA
	ls.font_size = Tuning.HUD_COMBO_FONT_SIZE
	ls.font_color = Palette.INK
	_label.label_settings = ls
	# TODO(spec): デザイン案は倍率の部分だけ少し小さい（16px）。1つの札に同じ大きさで書いた
	_label.add_theme_stylebox_override("normal", _box(Palette.HAZARD, Tuning.HUD_COMBO_BORDER, Tuning.HUD_COMBO_PAD))
	_label.hide()
	_edge.modulate.a = 0.0
	_edge.draw.connect(_draw_edge)


## コンボの札の左上（HUD のスコアの下）
func place_tag(pos: Vector2) -> void:
	_label.position = pos


## smash でコンボが combo、倍率が mult になった。stepped: この smash で倍率が上がった
func on_smash(combo: int, mult: float, stepped: bool) -> void:
	_label.text = "%d COMBO x%.1f" % [combo, mult]
	_label.size = Vector2.ZERO  # 文字に合わせて札を縮める
	_label.visible = combo >= Tuning.COMBO_DISPLAY_MIN
	if not stepped:
		return
	_bounce()
	_press_stamp(mult)
	Audio.play(&"stamp")  # TODO(spec): コンボの札の音は仕様のキーに無いので、判子（stamp）を流用した
	if mult >= Tuning.COMBO_EDGE_MULT:
		_flash_edge()
	if mult >= Tuning.COMBO_MULT_MAX:
		maxed.emit()


## コンボが途切れた（最後の smash から COMBO_WINDOW 秒を超えた）
func on_expired(combo: int) -> void:
	_label.hide()
	if combo >= Tuning.COMBO_BREAK_MIN:
		_show_break(combo)


func combo_text() -> String:
	return _label.text if _label.visible else ""


## 墨の文字に PAPER の縁取り（地面や標的に重なっても読めるように）
func _text_settings(fs: int) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = Fonts.DELA
	ls.font_size = fs
	ls.font_color = Palette.INK
	ls.outline_color = Palette.PAPER
	ls.outline_size = Tuning.TEMP_HUD_OUTLINE
	return ls


## 地の色・墨の枠・余白の札
static func _box(fill: Color, border: int, pad: Vector2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = Palette.INK
	sb.set_border_width_all(border)
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_bottom = pad.y
	return sb


func _bounce() -> void:
	if _bounce_tween != null:
		_bounce_tween.kill()
	_label.pivot_offset = Vector2(0.0, _label.size.y * 0.5)  # 左端を支点に弾む
	_label.scale = Vector2.ONE * Tuning.COMBO_BOUNCE_SCALE
	_bounce_tween = _label.create_tween()
	_bounce_tween.tween_property(_label, "scale", Vector2.ONE, Tuning.COMBO_BOUNCE_TIME)


## 画面上部の中央に「x2.0!」の札（警告黄地・墨の枠と文字、傾き）を、拡大率 1.6→1.0 で押す
func _press_stamp(mult: float) -> void:
	if is_instance_valid(_stamp):
		_stamp.queue_free()
	var s := Label.new()
	s.text = ("x%.1f MAX!" if mult >= Tuning.COMBO_MULT_MAX else "x%.1f!") % mult
	var ls := LabelSettings.new()
	ls.font = Fonts.DELA
	ls.font_size = Tuning.COMBO_STAMP_FONT_SIZE
	ls.font_color = Palette.INK
	s.label_settings = ls
	s.add_theme_stylebox_override("normal", _box(Palette.HAZARD, Tuning.COMBO_STAMP_OUTLINE, Tuning.COMBO_STAMP_PAD))
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(s)
	s.size = s.get_combined_minimum_size()
	s.position = Vector2(size.x * 0.5, Tuning.COMBO_STAMP_Y) - s.size * 0.5
	s.pivot_offset = s.size * 0.5
	s.rotation = deg_to_rad(Tuning.COMBO_STAMP_ANGLE_DEG)
	s.scale = Vector2.ONE * Tuning.COMBO_STAMP_POP_SCALE
	var tween := s.create_tween()
	tween.tween_property(s, "scale", Vector2.ONE, Tuning.COMBO_STAMP_POP_TIME)
	tween.tween_interval(Tuning.COMBO_STAMP_HOLD)
	tween.tween_property(s, "modulate:a", 0.0, Tuning.COMBO_STAMP_FADE)
	tween.tween_callback(s.queue_free)
	_stamp = s


func _flash_edge() -> void:
	if _edge_tween != null:
		_edge_tween.kill()
	_edge.modulate.a = 1.0
	_edge_tween = _edge.create_tween()
	_edge_tween.tween_property(_edge, "modulate:a", 0.0, Tuning.COMBO_EDGE_TIME)


func _draw_edge() -> void:
	var w: float = _edge.size.x
	var h: float = Tuning.COMBO_EDGE_H
	DrawUtil.stripes(_edge, Rect2(0.0, 0.0, w, h), Tuning.COMBO_EDGE_STRIPE_W)
	DrawUtil.stripes(_edge, Rect2(0.0, _edge.size.y - h, w, h), Tuning.COMBO_EDGE_STRIPE_W)


## コンボ表示の位置に「N COMBO」を出し、少し下がりながら消す
func _show_break(combo: int) -> void:
	var b := Label.new()
	b.text = "%d COMBO" % combo
	b.label_settings = _text_settings(Tuning.COMBO_BREAK_FONT_SIZE)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.position = _label.position
	add_child(b)
	var tween := b.create_tween().set_parallel()
	tween.tween_property(b, "modulate:a", 0.0, Tuning.COMBO_BREAK_TIME)
	tween.tween_property(b, "position:y", b.position.y + Tuning.COMBO_BREAK_DROP, Tuning.COMBO_BREAK_TIME)
	tween.chain().tween_callback(b.queue_free)
