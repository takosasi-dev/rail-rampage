extends Control
## 無限軌道のリザルト（docs/superpowers/specs/2026-09-28-replay-value-design.md の7章）。試験報告書（scenes/result.gd）と
## 同じ紙・文字の小さな「走行記録」: 終了理由・得点（最高記録更新の札）・走行距離・この車両の最高記録・熟練度・
## 新しい検定印。右列に「もう一度」（主ボタン）と「タイトルへ」。ゲーム画面が自分の上に重ね、add_child の前に setup(data)。
## R（retry）はゲーム画面の _unhandled_input が受ける。Esc は「タイトルへ」
## TODO(spec): 見出しは「走行記録」、判子は押さない（無限軌道に合否は無い）。依頼者の判断を待たずに決めた

signal retry_requested
signal title_requested

const UiButton := preload("res://scenes/ui/ui_button.gd")

var _data: Dictionary = {}

@onready var _report: Control = $Report
@onready var _rows: VBoxContainer = %Rows
@onready var _buttons: VBoxContainer = $Buttons


## data: score, distance（px）, best_score, best_distance, best_updated, xp（{"gained", "level_before", "level_after"}）,
## new_stamps, new_trolleys, trolley, fail_reason
func setup(data: Dictionary) -> void:
	_data = data


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_report.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_report.position = Tuning.ENDLESS_RESULT_REPORT.position
	_report.size = Tuning.ENDLESS_RESULT_REPORT.size
	_report.draw.connect(_draw_report)
	var body: VBoxContainer = $Report/Body
	body.position = Tuning.ENDLESS_RESULT_PAD
	body.size = Tuning.ENDLESS_RESULT_REPORT.size - Tuning.ENDLESS_RESULT_PAD * 2.0
	_rows.add_theme_constant_override(&"separation", Tuning.ENDLESS_RESULT_ROW_GAP)
	UiButton.style_label(%Heading, Fonts.DELA, Tuning.RESULT_HEAD_FONT_SIZE, Palette.INK)
	UiButton.style_label(%ReportNo, Fonts.courier, Tuning.RESULT_NO_FONT_SIZE, Palette.MUTED)
	var head: Control = %Head
	head.draw.connect(func() -> void:
		head.draw_rect(Rect2(0.0, head.size.y - Tuning.RESULT_HEAD_RULE, head.size.x, Tuning.RESULT_HEAD_RULE), Palette.INK))
	_fill()
	_buttons.position = Tuning.ENDLESS_RESULT_BUTTONS.position
	_buttons.size.x = Tuning.ENDLESS_RESULT_BUTTONS.size.x
	var again: Button = _button("Again", "もう一度", "R / SPACE", true, retry_requested.emit)
	_button("Title", "タイトルへ", "Esc", false, title_requested.emit)
	UiButton.focus_quietly(again)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.play(&"ui_select")
		title_requested.emit()


func _fill() -> void:
	_row("試験名", [_text("無限軌道", Fonts.BIZ_BOLD, Tuning.RESULT_NAME_FONT_SIZE)])
	_row("使用車両", [_text(Trolleys.name_of(_data.get("trolley", Trolleys.DEFAULT)), Fonts.BIZ_BOLD, Tuning.RESULT_NAME_FONT_SIZE)])
	var reason: String = _data.get("fail_reason", "")
	if not reason.is_empty():
		_row("終了理由", [_text(reason, Fonts.DELA, Tuning.RESULT_REASON_FONT_SIZE, Palette.STAMP)])
	var score_parts: Array[Control] = [_text(Display.score_text(_data["score"]), Fonts.courier_bold, Tuning.RESULT_SCORE_FONT_SIZE)]
	if _data["best_updated"]:
		score_parts.append(_tag("最高記録更新"))
	_row("得点", score_parts)
	_row("走行距離", [_value(Display.distance_text(_data["distance"]))])
	_row("最高記録", [_value("%s 点 / %s" % [Display.score_text(_data["best_score"]), Display.distance_text(_data["best_distance"])])])
	var xp: Dictionary = _data.get("xp", {"gained": 0, "level_before": 1, "level_after": 1})
	var xp_text: String = "+%d" % xp["gained"]
	if xp["level_after"] > xp["level_before"]:
		xp_text += "　%d段 → %d段" % [xp["level_before"], xp["level_after"]]
	_row("熟練度", [_value(xp_text)])
	var stamps: Array = _data.get("new_stamps", [])
	if not stamps.is_empty():
		var names: Array = stamps.slice(0, Tuning.ENDLESS_RESULT_STAMPS_MAX).map(func(id: String) -> String: return Achievements.name_of(id))
		var text: String = "・".join(names)
		if stamps.size() > Tuning.ENDLESS_RESULT_STAMPS_MAX:
			text += "　ほか %d 個" % (stamps.size() - Tuning.ENDLESS_RESULT_STAMPS_MAX)
		_row("新しい検定印", [_text(text, Fonts.BIZ_BOLD, Tuning.RESULT_NAME_FONT_SIZE, Palette.STAMP)])
	var trolleys: Array = _data.get("new_trolleys", [])
	if not trolleys.is_empty():
		_row("新しい車両", [_text("・".join(trolleys.map(func(id: String) -> String: return Trolleys.name_of(id))),
				Fonts.BIZ_BOLD, Tuning.RESULT_NAME_FONT_SIZE, Palette.STAMP)])


## 報告書の1行: 左にラベル列、右に値
func _row(label: String, parts: Array[Control]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(Tuning.RESULT_TAG_GAP))
	var head: Label = _text(label, Fonts.BIZ, Tuning.RESULT_LABEL_FONT_SIZE, Palette.MUTED)
	head.custom_minimum_size.x = Tuning.RESULT_LABEL_COL_W
	row.add_child(head)
	for p: Control in parts:
		row.add_child(p)
	_rows.add_child(row)


func _text(s: String, font: Font, font_size: int, color: Color = Palette.INK) -> Label:
	var l := Label.new()
	l.text = s
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiButton.style_label(l, font, font_size, color)
	return l


func _value(s: String) -> Label:
	return _text(s, Fonts.courier, Tuning.RESULT_VALUE_FONT_SIZE)


## 「最高記録更新」の札（試験報告書と同じ: 警告黄の地に墨の枠）
func _tag(s: String) -> Label:
	var l: Label = _text(s, Fonts.DELA, Tuning.RESULT_TAG_FONT_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.HAZARD
	sb.border_color = Palette.INK
	sb.set_border_width_all(Tuning.RESULT_TAG_BORDER)
	sb.content_margin_left = Tuning.RESULT_TAG_PAD.x
	sb.content_margin_right = Tuning.RESULT_TAG_PAD.x
	sb.content_margin_top = Tuning.RESULT_TAG_PAD.y
	sb.content_margin_bottom = Tuning.RESULT_TAG_PAD.y
	l.add_theme_stylebox_override(&"normal", sb)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _button(node_name: String, text: String, key: String, primary: bool, on_press: Callable) -> Button:
	var b: UiButton = UiButton.new()
	b.name = node_name
	b.text = text
	b.key_hint = key
	b.primary = primary
	_buttons.add_child(b)
	b.custom_minimum_size.y = Tuning.RESULT_PRIMARY_H if primary else Tuning.RESULT_SECONDARY_H
	if primary:
		b.add_theme_font_size_override(&"font_size", Tuning.RESULT_PRIMARY_FONT_SIZE)
	b.pressed.connect(on_press)
	return b


func _draw() -> void:
	UiButton.draw_menu_bg(self, Rect2(Vector2.ZERO, size))


## 生成りの紙（10pxずらしの影）と上端中央のクリップ（試験報告書と同じ）
func _draw_report() -> void:
	var r := Rect2(Vector2.ZERO, _report.size)
	_report.draw_rect(Rect2(Tuning.UI_PANEL_SHADOW, r.size), Palette.SHADOW)
	_report.draw_rect(r, Palette.PAPER)
	DrawUtil.tile_noise(_report, r, "grain", Tuning.PAPER_GRAIN_ALPHA)
	var clip := Rect2((r.size.x - Tuning.RESULT_CLIP_SIZE.x) * 0.5, -Tuning.RESULT_CLIP_RISE, Tuning.RESULT_CLIP_SIZE.x,
			Tuning.RESULT_CLIP_SIZE.y)
	DrawUtil.fill_gradient(_report, DrawUtil.rounded_rect(clip, 0.0), clip.position, Vector2(clip.position.x, clip.end.y),
			[Palette.STEEL_LIGHT, Palette.STEEL_SHADE], [0.0, 1.0])
	_report.draw_rect(clip.grow(-Tuning.RESULT_CLIP_BORDER * 0.5), Palette.INK, false, Tuning.RESULT_CLIP_BORDER)
