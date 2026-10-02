extends Control
## 修了証書（設計書 docs/superpowers/specs/2026-09-26-records-design.md の 3.3）。開いた画面（リザルト・試験記録）の上に
## 重ねるオーバーレイ。「閉じる」か Esc で closed を出す。閉じるのは開いた側。
## 開いている間は R（リトライ）と Esc（ポーズ）を下の画面（リザルトの下のゲーム画面など）に流さない。
## 依頼者の判断を待たずに作った（体裁・文言は試遊の後に見直す）

signal closed

const UiButton := preload("res://scenes/ui/ui_button.gd")
const Stamp := preload("res://scenes/ui/stamp.gd")

@onready var _paper: Control = %Paper
@onready var _stamp: Stamp = %Stamp
@onready var _close: Button = %Close


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # 背景と紙の粒（設計書5章）
	_paper.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_style()
	# 設計書 3.3 の本文。自動の折り返しは「RailRampage」の後で切れて左右の長さがそろわないので、切る所を決めておく
	(%Text as Label).text = "あなたは RailRampage 衝突試験場の第1〜%d試験の\n全課程を修了したことをここに証します" % Tuning.STAGE_COUNT
	(%Stars as Label).text = "%d / %d" % [GameState.total_stars(), Tuning.STAGE_COUNT * Tuning.STARS_MAX]
	var best: int = 0
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		best += GameState.record(n)["best_score"]
	(%Score as Label).text = Display.score_text(best) + " 点"
	(%Date as Label).text = date_text(GameState.stats()["completed_on"])
	_paper.draw.connect(_draw_paper)
	_close.pressed.connect(closed.emit)
	UiButton.focus_quietly(_close)  # FR-47a: 開いた時点で主ボタンにフォーカス
	# リザルトの判子と同じ流儀: 開いてから少し後に押す。スローモーの途中で開いても遅れないよう time_scale を無視する
	_stamp.label = "修了"
	_stamp.position = Tuning.CERT_STAMP_POS
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_interval(Tuning.RESULT_STAMP_DELAY)
	tween.tween_callback(_press_stamp)


## FR-47a: Esc で閉じる。R と Esc・P（ポーズ）は下の画面に流さない（リザルトの下のゲーム画面がリトライしないように）
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.play(&"ui_select")
		closed.emit()
	elif event.is_action("retry") or event.is_action("pause"):
		get_viewport().set_input_as_handled()


## 修了日（"2026-09-26"）を「2026年9月26日」にする。形が違えばそのまま
## TODO(spec): 修了日が空（まだ全試験に合格していない）ときは「未修了」と出す。普通は開けない（開く側が全試験の合格を確かめる）
static func date_text(on: String) -> String:
	if on.is_empty():
		return "未修了"
	var p: PackedStringArray = on.split("-")
	if p.size() != 3 or not (p[0].is_valid_int() and p[1].is_valid_int() and p[2].is_valid_int()):
		return on
	return "%d年%d月%d日" % [p[0].to_int(), p[1].to_int(), p[2].to_int()]


## 判子を押し、揺れの設定が ON なら紙を揺らす（リザルトの判子と同じ振幅・時間）
func _press_stamp() -> void:
	_stamp.press()
	if not GameState.screen_shake:
		return
	var home: Vector2 = _paper.position
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_method(_shake_paper.bind(home), 1.0, 0.0, Tuning.RESULT_SHAKE_TIME)
	tween.tween_callback(func() -> void: _paper.position = home)


## 揺れの1コマ。k は残りの割合（1→0）
func _shake_paper(k: float, home: Vector2) -> void:
	_paper.position = home + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * Tuning.RESULT_SHAKE_AMP * k


func _style() -> void:
	# TODO(spec): 賞状の文字の書体・大きさは仕様に無い。見出しは Dela Gothic One、本文と欄の名前は BIZ UDPGothic、
	#             数値は Courier Prime（報告書と同じ文法）
	var head := FontVariation.new()
	head.base_font = Fonts.DELA
	head.spacing_glyph = Tuning.CERT_HEAD_SPACING
	UiButton.style_label(%Heading, head, Tuning.CERT_HEAD_FONT_SIZE, Palette.INK)
	UiButton.style_label(%Sub, UiButton.spaced(Fonts.courier), Tuning.CERT_SUB_FONT_SIZE, Palette.MUTED)
	var text: Label = %Text
	UiButton.style_label(text, Fonts.BIZ, Tuning.CERT_TEXT_FONT_SIZE, Palette.INK)
	text.language = "ja@lb=strict"  # 行頭に「ー」や小書きの仮名を置かない
	text.add_theme_constant_override(&"line_spacing", roundi(Tuning.CERT_TEXT_FONT_SIZE * Tuning.CERT_TEXT_LINE_HEIGHT
			- Fonts.BIZ.get_height(Tuning.CERT_TEXT_FONT_SIZE)))
	var rows: GridContainer = %Rows
	for i: int in rows.get_child_count():
		var l: Label = rows.get_child(i)
		if i % rows.columns == 0:
			UiButton.style_label(l, Fonts.BIZ_BOLD, Tuning.CERT_LABEL_FONT_SIZE, Palette.MUTED)
		else:
			UiButton.style_label(l, Fonts.courier_bold, Tuning.CERT_VALUE_FONT_SIZE, Palette.INK)


func _draw() -> void:
	UiButton.draw_menu_bg(self, Rect2(Vector2.ZERO, size))


## 生成りの紙（10pxずらしの影、16.4）に墨の二重枠（外は太く、内は細く）
func _draw_paper() -> void:
	var r := Rect2(Vector2.ZERO, _paper.size)
	_paper.draw_rect(Rect2(Tuning.UI_PANEL_SHADOW, r.size), Palette.SHADOW)
	_paper.draw_rect(r, Palette.PAPER)
	DrawUtil.tile_noise(_paper, r, "grain", Tuning.PAPER_GRAIN_ALPHA)
	var inset: float = Tuning.CERT_FRAME_INSET
	_paper.draw_rect(r.grow(-inset - Tuning.CERT_FRAME_OUTER * 0.5), Palette.INK, false, Tuning.CERT_FRAME_OUTER)
	inset += Tuning.CERT_FRAME_OUTER + Tuning.CERT_FRAME_GAP
	_paper.draw_rect(r.grow(-inset - Tuning.CERT_FRAME_INNER * 0.5), Palette.INK, false, Tuning.CERT_FRAME_INNER)
