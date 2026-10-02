extends Control
## プレイ中の HUD（FR-42、17.4）。左上にスコア、上部中央にステージ札、右上に速度（km/h、FR-43）と勢いのゲージ、
## 右下にキー操作。コンボの札は ComboFx が combo_position() に出す。値は Game が毎フレーム show_values() で渡す。

const UiButton := preload("res://scenes/ui/ui_button.gd")
const KEYS_TEXT: String = "R リトライ　Esc ポーズ"

var _number: int = 1
var _stage_name: String = ""
var _score: int = 0
var _speed_kmh: int = 0
var _momentum_rate: float = 0.0  # 勢い / MOMENTUM_MAX
var _label_font: Font  # 「SCORE」「SPEED」（字間を空けた Courier Prime）


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_font = UiButton.spaced(Fonts.courier)


func setup(number: int, stage_name: String) -> void:
	_number = number
	_stage_name = stage_name
	queue_redraw()


func show_values(score: int, speed_px: float, momentum: float) -> void:
	var kmh: int = Display.to_display_speed(speed_px)
	var rate: float = clampf(momentum / Tuning.MOMENTUM_MAX, 0.0, 1.0)
	if score == _score and kmh == _speed_kmh and is_equal_approx(rate, _momentum_rate):
		return
	_score = score
	_speed_kmh = kmh
	_momentum_rate = rate
	queue_redraw()


func score_text() -> String:
	return Display.score_text(_score)


func speed_text() -> String:
	return "%d km/h" % _speed_kmh


func stage_text() -> String:
	return "%s %s" % [Display.stage_title(_number), _stage_name]


## コンボの札を置く位置（スコアの下）
func combo_position() -> Vector2:
	return Vector2(Tuning.HUD_MARGIN, Tuning.HUD_MARGIN + _score_panel_h() + Tuning.HUD_COMBO_GAP)


## 画面の上を覆う札（得点・試験名・速度）の範囲。判断材料が隠れないかの確認（L-3）にも使う
func panels() -> Array[Rect2]:
	return [_score_panel(), _stage_rect(), _speed_panel()]


func _draw() -> void:
	_draw_score()
	_draw_stage()
	_draw_speed()
	_draw_keys()


func _score_panel() -> Rect2:
	var m: float = Tuning.HUD_MARGIN
	var num_w: float = Fonts.DELA.get_string_size(Display.score_text(_score), HORIZONTAL_ALIGNMENT_LEFT, -1,
			Tuning.HUD_SCORE_FONT_SIZE).x
	return Rect2(m, m, maxf(Tuning.HUD_SCORE_MIN_W, num_w + Tuning.HUD_PANEL_PAD.x * 2.0), _score_panel_h())


func _stage_rect() -> Rect2:
	var r: Rect2 = Tuning.HUD_STAGE_RECT
	r.position.x = (size.x - r.size.x) * 0.5
	return r


func _speed_panel() -> Rect2:
	var h: float = Tuning.HUD_PANEL_PAD.y + Fonts.DELA.get_height(Tuning.HUD_SPEED_FONT_SIZE) + Tuning.HUD_ROW_GAP \
			+ Tuning.HUD_GAUGE_H + Tuning.HUD_SPEED_PAD_BOTTOM
	return Rect2(size.x - Tuning.HUD_MARGIN - Tuning.HUD_SPEED_W, Tuning.HUD_MARGIN, Tuning.HUD_SPEED_W, h)


## 左上: 墨の地に「SCORE」と得点（3桁区切り）
func _draw_score() -> void:
	var m: float = Tuning.HUD_MARGIN
	var pad: Vector2 = Tuning.HUD_PANEL_PAD
	var num: String = Display.score_text(_score)
	draw_rect(_score_panel(), Palette.INK)
	var y: float = m + pad.y + _label_font.get_ascent(Tuning.HUD_LABEL_FONT_SIZE)
	draw_string(_label_font, Vector2(m + pad.x, y), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.HUD_LABEL_FONT_SIZE, Palette.HAZARD)
	y += _label_font.get_descent(Tuning.HUD_LABEL_FONT_SIZE) + Fonts.DELA.get_ascent(Tuning.HUD_SCORE_FONT_SIZE)
	draw_string(Fonts.DELA, Vector2(m + pad.x, y), num, HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.HUD_SCORE_FONT_SIZE, Palette.PAPER)


func _score_panel_h() -> float:
	return Tuning.HUD_PANEL_PAD.y + _label_font.get_height(Tuning.HUD_LABEL_FONT_SIZE) \
			+ Fonts.DELA.get_height(Tuning.HUD_SCORE_FONT_SIZE) + Tuning.HUD_SCORE_PAD_BOTTOM


## 上部中央: 半透明の墨の札に「第N試験」とステージ名
func _draw_stage() -> void:
	var r: Rect2 = _stage_rect()
	draw_rect(r, Color(Palette.INK, Tuning.HUD_STAGE_ALPHA))
	var fs: int = Tuning.HUD_STAGE_FONT_SIZE
	var num: String = Display.stage_title(_number)
	var num_w: float = Fonts.courier.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var name_w: float = Fonts.BIZ_BOLD.get_string_size(_stage_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x: float = r.get_center().x - (num_w + Tuning.HUD_STAGE_GAP + name_w) * 0.5
	var mid: float = r.get_center().y
	draw_string(Fonts.courier, Vector2(x, _baseline(Fonts.courier, fs, mid)), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.HAZARD)
	draw_string(Fonts.BIZ_BOLD, Vector2(x + num_w + Tuning.HUD_STAGE_GAP, _baseline(Fonts.BIZ_BOLD, fs, mid)), _stage_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.PAPER)


## 右上: 「SPEED」と速度（km/h）、その下に勢いのゲージ（STEEL の溝に警告黄のストライプ）
func _draw_speed() -> void:
	var pad: Vector2 = Tuning.HUD_PANEL_PAD
	var fs: int = Tuning.HUD_SPEED_FONT_SIZE
	var gauge_h: float = Tuning.HUD_GAUGE_H
	var panel: Rect2 = _speed_panel()
	draw_rect(panel, Palette.INK)
	var left: float = panel.position.x + pad.x
	var right: float = panel.end.x - pad.x
	# 1行目: ベースラインをそろえる
	var baseline: float = panel.position.y + pad.y + Fonts.DELA.get_ascent(fs)
	draw_string(_label_font, Vector2(left, baseline), "SPEED", HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.HUD_LABEL_FONT_SIZE, Palette.HAZARD)
	var unit: String = " km/h"
	var unit_w: float = Fonts.courier.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.HUD_UNIT_FONT_SIZE).x
	var num: String = str(_speed_kmh)
	var num_w: float = Fonts.DELA.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(Fonts.DELA, Vector2(right - unit_w - num_w, baseline), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.PAPER)
	draw_string(Fonts.courier, Vector2(right - unit_w, baseline), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.HUD_UNIT_FONT_SIZE, Palette.PAPER)
	# 2行目: 「勢い」とゲージ
	var row_top: float = baseline + Fonts.DELA.get_descent(fs) + Tuning.HUD_ROW_GAP
	var mid: float = row_top + gauge_h * 0.5
	var lfs: int = Tuning.HUD_MOMENTUM_FONT_SIZE
	var label: String = "勢い"
	draw_string(Fonts.BIZ_BOLD, Vector2(left, _baseline(Fonts.BIZ_BOLD, lfs, mid)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Palette.MUTED_ON_INK)
	var gx: float = left + Fonts.BIZ_BOLD.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x + Tuning.HUD_GAUGE_LABEL_GAP
	var gauge := Rect2(gx, row_top, right - gx, gauge_h)
	draw_rect(gauge, Palette.STEEL)
	var b: float = Tuning.HUD_GAUGE_BORDER
	var inner: Rect2 = gauge.grow(-b)
	if _momentum_rate > 0.0:
		DrawUtil.stripes(self, Rect2(inner.position, Vector2(inner.size.x * _momentum_rate, inner.size.y)),
				Tuning.STRIPE_W, Palette.HAZARD, Palette.HAZARD_DARK)
	draw_rect(gauge.grow(-b * 0.5), Palette.MUTED, false, b)


## 右下: キー操作。TODO(spec): 地面が画面の下に外れると明るい背景に重なるので、墨の縁取りを付けた
func _draw_keys() -> void:
	var fs: int = Tuning.HUD_KEY_FONT_SIZE
	var w: float = Fonts.courier.get_string_size(KEYS_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(size.x - Tuning.HUD_MARGIN - w, size.y - Tuning.HUD_KEY_BOTTOM - Fonts.courier.get_descent(fs))
	draw_string_outline(Fonts.courier, pos, KEYS_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Tuning.HUD_KEY_OUTLINE, Palette.INK)
	draw_string(Fonts.courier, pos, KEYS_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.PAPER)


## 高さ mid の中央に文字をそろえるベースライン
static func _baseline(font: Font, fs: int, mid: float) -> float:
	return mid + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
