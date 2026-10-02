extends Control
## リザルト「試験報告書」（17.7、FR-45, FR-46, FR-46a）。ゲーム画面が自分の上に重ねるオーバーレイ。
## add_child の前に setup(data) を呼んでもらう。ボタンと Esc は合図を出すだけで、画面の切り替えはゲーム側がする。
## R（retry）はゲーム側の _unhandled_input が受ける（FR-26）ので、ここでは受けない。
## 判子は開いてから RESULT_STAMP_DELAY 秒後に押す。それまでもボタンは効く（決定すれば合図を出すだけ）。
## 新しく取った検定印は右列の札に並べ、合否の判子の後に順に押す（設計書 3.2）。全試験の合格がそろった走行なら
## 「修了証書を受け取る」で修了証書をこの上に重ねて開く（3.3）。開いている間の R・Esc は修了証書が受け止める。
## 車両（trolleys-and-display-design.md 3章）: 報告書に「使用車両」の行（合格・不合格とも）。この走行で新しく解放された
## 車両は、検定印と同じ右列の札の上の段に小さな絵と名前で知らせる
## TODO(spec): 新しい車両と検定印が両方あるときは、1枚の札の上の段に車両、下の段に検定印を並べる。札が
##             ボタンの上の空きに収まらなければ、右列のボタンをその分だけ下げる（検定印だけのときの配置は今までどおり）

signal retry_requested
signal next_requested
signal select_requested

const UiButton := preload("res://scenes/ui/ui_button.gd")
const Stamp := preload("res://scenes/ui/stamp.gd")
const CERTIFICATE_SCENE: String = "res://scenes/certificate.tscn"
## FR-46a: 中止理由ごとの固定ヒント
const HINTS: Dictionary = {
	"激突": "壁の手前で速度が足りませんでした。手前の分岐で標的の多いルートを選ぶと、勢いが溜まって速くなります。",
	"脱線": "ジャンプ台で速度が足りませんでした。手前の分岐で標的の多いルートを選ぶと、勢いが溜まって速くなります。",
}

var _data: Dictionary = {}
var _stars: int = 0
var _marks: Array[Control] = []  # 新しい検定印の小さな判子（押す順）
var _challenge_marks: Array[Control] = []  # 今回達成した課題の丸印（押す順）
var _gold_star: Control = null  # 金★（ステージに gold_threshold があるときだけ）
var _gold_shown: bool = false  # 金★を塗った（取った走行で、判子の後）

@onready var _report: Control = $Report
@onready var _head: Control = %Head
@onready var _grid: GridContainer = %Grid
@onready var _rating: Control = %Rating
@onready var _stars_box: Control = %Stars
@onready var _hint: PanelContainer = %Hint
@onready var _hint_icon: Control = %HintIcon
@onready var _stamp: Stamp = %Stamp
@onready var _buttons: VBoxContainer = $Buttons
@onready var _new_stamps: Control = %NewStamps


## data のキーはゲーム側との取り決め（stage, stage_name, cleared, score, smashed, total, max_combo, max_speed,
## girigiri, stars, thresholds, best_updated, is_last, fail_reason, required_speed, reached_speed,
## new_stamps, certificate, trolley, new_trolleys）。new_stamps・certificate・new_trolleys は無ければ「無い」「false」、
## trolley は無ければ標準型として扱う
## やりこみ要素（replay-value-design.md 10章）: title（無ければ Display.stage_title）、gold・gold_threshold（金★）、
## challenges（課題の行 [{"text", "done", "new"}]）、xp（熟練度 {"gained", "level_before", "level_after"}）。無ければ出さない
func setup(data: Dictionary) -> void:
	_data = data


func _ready() -> void:
	var cleared: bool = _data["cleared"]
	_style()
	var stage: int = _data["stage"]
	var stage_name: String = _data["stage_name"]
	(%ReportNo as Label).text = "TEST REPORT\nNo.%s" % (("EX-%d" % (stage - Tuning.EX_FIRST + 1)) if stage >= Tuning.EX_FIRST else "%03d" % stage)
	var title: String = _data.get("title", Display.stage_title(stage))
	_row("試験名", [_text("%s　%s" % [title, stage_name], Fonts.BIZ_BOLD, Tuning.RESULT_NAME_FONT_SIZE)])
	# TODO(spec): 「使用車両」の行は試験名のすぐ下（合格・不合格とも）。名前だけで絵は出さない
	_row("使用車両", [_text(Trolleys.name_of(_data.get("trolley", Trolleys.DEFAULT)), Fonts.BIZ_BOLD,
			Tuning.RESULT_NAME_FONT_SIZE)])
	if cleared:
		_fill_cleared()
	else:
		_fill_failed()
	_fill_xp()  # 熟練度は合格・不合格とも
	if cleared:
		_fill_challenges()
	_rating.visible = cleared
	_hint.visible = not cleared
	_buttons.position.y = Tuning.RESULT_BUTTONS_Y_CLEARED if cleared else Tuning.RESULT_BUTTONS_Y_FAILED
	_fill_new_trolleys()
	_fill_new_stamps()
	if _new_stamps.visible:  # 札（影ごと）がボタンのフォーカスの枠に重なるなら、ボタンを下げる
		var slip_end: float = _new_stamps.position.y + _new_stamps.get_combined_minimum_size().y + Tuning.UI_PANEL_SHADOW.y
		_buttons.position.y = maxf(_buttons.position.y, slip_end + Tuning.UI_FOCUS_W * 2.0 + Tuning.RESULT_BUTTONS_SLIP_GAP)
	var first: Button
	if cleared:
		var cert: Button = null
		if _data.get("certificate", false):
			# 設計書 3.3: 全試験の合格がそろった走行（最終ステージ）の主ボタン
			cert = _button("Certificate", "修了証書を受け取る", "SPACE", true, open_certificate)
			cert.add_theme_font_size_override(&"font_size", Tuning.RESULT_CERT_FONT_SIZE)
		var next: Button = _button("Next", "次の試験へ", "SPACE", true, next_requested.emit)
		next.visible = not _data["is_last"] and cert == null
		_button("Retry", "リトライ", "R", false, retry_requested.emit)
		var select: Button = _button("Select", "ステージ選択へ", "Esc", false, select_requested.emit)
		# TODO(spec): 最終ステージでは「次の試験へ」が無く、主ボタン（FR-47a の初期フォーカス先）が無い。
		#             修了証書を受け取らない走行では、ステージを進める先の代わりとして「ステージ選択へ」にフォーカスを
		#             置いた（見た目は副ボタンのまま）
		if cert != null:
			first = cert
		else:
			first = select if _data["is_last"] else next
	else:
		first = _button("Retry", "リトライ", "R / SPACE", true, retry_requested.emit)
		_button("Select", "ステージ選択へ", "Esc", false, select_requested.emit)
	UiButton.focus_quietly(first)  # FR-45, FR-46, FR-47a
	_stamp.passed = cleared
	_stamp.position = Tuning.RESULT_PASS_STAMP_POS if cleared else Tuning.RESULT_FAIL_STAMP_POS
	# 17.7: 開いてから0.4秒後に判子。スローモーの途中で開いても遅れないよう time_scale を無視する
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_interval(Tuning.RESULT_STAMP_DELAY)
	tween.tween_callback(_press_stamp)
	# replay-value-design.md 3章: 合否の判子の後に、金★、今回達成した課題の丸印、新しい検定印の順に押す
	# TODO(spec): 金★と課題の丸印の演出は仕様に無い。検定印の小さな判子と同じ間合い・拡大率・音（stamp）にした
	if _gold_star != null and _data.get("gold", false):
		tween.tween_interval(Tuning.RESULT_NEW_MARK_INTERVAL)
		tween.tween_callback(_press_gold)
	for mark: Control in _challenge_marks:
		tween.tween_interval(Tuning.RESULT_NEW_MARK_INTERVAL)
		tween.tween_callback(_press_mark.bind(mark))
	for mark: Control in _marks:  # 設計書 3.2: 新しい検定印は合否の判子の後に順に押す
		tween.tween_interval(Tuning.RESULT_NEW_MARK_INTERVAL)
		tween.tween_callback(_press_mark.bind(mark))


## 設計書 3.3: 修了証書をこの上に重ねて開く。開いている間はリザルトのボタンにフォーカスが行かないようにする
func open_certificate() -> Control:
	var c: Control = (load(CERTIFICATE_SCENE) as PackedScene).instantiate()
	c.closed.connect(_on_certificate_closed.bind(c))
	_buttons.focus_behavior_recursive = FOCUS_BEHAVIOR_DISABLED
	add_child(c)
	return c


func _on_certificate_closed(c: Control) -> void:
	c.queue_free()
	_buttons.focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED
	UiButton.focus_quietly(_buttons.get_node("Certificate"))


## FR-47a: Esc で戻る（ステージ選択へ）
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.play(&"ui_select")
		select_requested.emit()


## FR-45: 得点（最高記録更新の札）、破壊数／総標的数、最大コンボ、最高速度、ギリギリ突破回数、★と「あと N 点」
func _fill_cleared() -> void:
	var score: int = _data["score"]
	var score_parts: Array[Control] = [_text(Display.score_text(score), Fonts.courier_bold, Tuning.RESULT_SCORE_FONT_SIZE)]
	if _data["best_updated"]:
		score_parts.append(_tag("最高記録更新"))
	_row("得点", score_parts, Tuning.RESULT_TAG_GAP)
	_row("破壊数", [_value("%d / %d" % [_data["smashed"], _data["total"]])])
	_row("最大コンボ", [_value(str(_data["max_combo"]))])
	_row("最高速度", [_value("%d km/h" % Display.to_display_speed(_data["max_speed"]))])
	_row("ギリギリ突破", [_value("%d 回" % _data["girigiri"])])
	_stars = _data["stars"]
	_stars_box.custom_minimum_size = Vector2(
			Tuning.RESULT_STAR_SIZE * Tuning.STARS_MAX + Tuning.RESULT_STAR_GAP * (Tuning.STARS_MAX - 1), Tuning.RESULT_STAR_SIZE)
	_stars_box.draw.connect(_draw_stars)
	var gold_threshold: int = _data.get("gold_threshold", 0)
	if gold_threshold > 0:  # replay-value-design.md 3.2: 金★は★3 の右に、少し離して置く
		_gold_star = Control.new()
		_gold_star.name = "GoldStar"
		_gold_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gold_star.size = Vector2.ONE * Tuning.RESULT_STAR_SIZE
		_gold_star.position.x = _stars_box.custom_minimum_size.x + Tuning.RESULT_GOLD_GAP
		_gold_star.pivot_offset = _gold_star.size * 0.5
		_gold_star.draw.connect(_draw_gold_star)
		_stars_box.add_child(_gold_star)
		_stars_box.custom_minimum_size.x += Tuning.RESULT_GOLD_GAP + Tuning.RESULT_STAR_SIZE
	# 10章: ★3 なら「あと N 点」の行を出さない。★2 未獲得なら ★2 までの点数
	# TODO(spec): ★3 で金★を取れなかったときは「金★まで あと N 点」を出す（仕様に無い。★の行と同じ形）
	var remain: Control = %Remain
	var to_gold: bool = _stars == Tuning.STARS_MAX and gold_threshold > 0 and not _data.get("gold", false)
	remain.visible = _stars < Tuning.STARS_MAX or to_gold
	if to_gold:
		(%RemainHead as Label).text = "金★まで あと "
		(%RemainPoints as Label).text = Display.score_text(gold_threshold - score)
	elif remain.visible:
		var thresholds: Array = _data["thresholds"]
		(%RemainHead as Label).text = "★%d まで あと " % (_stars + 1)
		(%RemainPoints as Label).text = Display.score_text(int(thresholds[_stars - 1]) - score)


## FR-46, FR-46a: 中止理由、必要速度、到達速度と不足分（km/h）、中止時の得点、中止理由ごとのヒント
func _fill_failed() -> void:
	var reason: String = _data["fail_reason"]
	var required: int = Display.to_display_speed(_data["required_speed"])
	var reached: int = Display.to_display_speed(_data["reached_speed"])
	_row("中止理由", [_text(reason, Fonts.DELA, Tuning.RESULT_REASON_FONT_SIZE, Palette.STAMP)])
	_row("必要速度", [_value("%d km/h" % required)])
	# AC-23: 「到達速度 58 km/h（12 不足）」。不足分は表示値どうしの差
	_row("到達速度", [_text("%d km/h" % reached, Fonts.courier_bold, Tuning.RESULT_VALUE_FONT_SIZE),
			_text("（%d 不足）" % (required - reached), Fonts.courier_bold, Tuning.RESULT_VALUE_FONT_SIZE, Palette.STAMP)],
			Tuning.RESULT_VALUE_GAP)
	_row("中止時の得点", [_value(Display.score_text(_data["score"])),
			_text("記録には残りません", Fonts.BIZ, Tuning.RESULT_NOTE_FONT_SIZE, Palette.MUTED)], Tuning.RESULT_VALUE_GAP)
	(%HintText as Label).text = HINTS.get(reason, "")


## replay-value-design.md 5.1: 熟練度の行。「+N」と、段が上がったら「◯段に上がった」の札と「強化のポイント +M」。
## ラベルに車両の名前を入れる（「標準型の熟練度」）
func _fill_xp() -> void:
	var xp: Dictionary = _data.get("xp", {})
	if xp.is_empty():
		return
	var parts: Array[Control] = [_value("+%s" % Display.score_text(xp.get("gained", 0)))]
	var up: int = int(xp.get("level_after", 1)) - int(xp.get("level_before", 1))
	if up > 0:
		parts.append(_tag("%d段に上がった" % xp["level_after"]))
		parts.append(_text("強化のポイント +%d" % up, Fonts.BIZ, Tuning.RESULT_LEVEL_NOTE_FONT_SIZE))
	_row("%sの熟練度" % Trolleys.name_of(_data.get("trolley", Trolleys.DEFAULT)), parts)


## replay-value-design.md 3.1: 課題3つの行（合格のときだけ）。達成済みは朱の丸印にレ点、未達成は薄い丸。
## 今回達成したものは警告黄の地にして、丸印は合否の判子の後に押す
func _fill_challenges() -> void:
	var list: Array = _data.get("challenges", [])
	if list.is_empty():
		return
	var lines := VBoxContainer.new()
	lines.name = "Challenges"
	lines.add_theme_constant_override(&"separation", Tuning.RESULT_CHALLENGE_LINE_GAP)
	for c: Dictionary in list:
		lines.add_child(_challenge_line(c))
	var head: Label = _row("課題", [lines])
	head.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# TODO(spec): 課題の3行が入るよう、報告書を下に伸ばし（result.tscn）、行の間を少し詰める
	_grid.add_theme_constant_override(&"v_separation", Tuning.RESULT_ROW_GAP_TIGHT)


func _challenge_line(c: Dictionary) -> Label:
	var done: bool = c.get("done", false)
	var fresh: bool = c.get("new", false)
	var l: Label = _text(c.get("text", ""), Fonts.BIZ_BOLD if fresh else Fonts.BIZ, Tuning.RESULT_CHALLENGE_FONT_SIZE,
			Palette.INK if done else Palette.MUTED)
	var m: float = Tuning.RESULT_CHALLENGE_MARK
	var sb: StyleBox = StyleBoxEmpty.new()
	var pad: Vector2 = Vector2.ZERO
	if fresh:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Palette.HAZARD
		pad = Tuning.RESULT_CHALLENGE_NEW_PAD
		flat.content_margin_right = pad.x
		flat.content_margin_top = pad.y
		flat.content_margin_bottom = pad.y
		sb = flat
	sb.content_margin_left = pad.x + m + Tuning.RESULT_CHALLENGE_MARK_GAP
	l.add_theme_stylebox_override(&"normal", sb)
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var mark := Control.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.anchor_top = 0.5
	mark.anchor_bottom = 0.5
	mark.offset_left = pad.x
	mark.offset_right = pad.x + m
	mark.offset_top = -m * 0.5
	mark.offset_bottom = m * 0.5
	mark.pivot_offset = Vector2.ONE * m * 0.5
	mark.draw.connect(func() -> void: draw_challenge_mark(mark, Rect2(Vector2.ZERO, Vector2.ONE * m), done, Palette.LOCKED))
	l.add_child(mark)
	if fresh:
		mark.modulate.a = 0.0  # 合否の判子の後に押す
		_challenge_marks.append(mark)
	return l


## 課題の丸印。達成は朱（STAMP）の丸にレ点、未達成は open_color の丸だけ（ステージ選択の詳細パネルも使う）
static func draw_challenge_mark(ci: CanvasItem, r: Rect2, done: bool, open_color: Color) -> void:
	var w: float = Tuning.RESULT_CHALLENGE_MARK_LINE
	var color: Color = Palette.STAMP if done else open_color
	ci.draw_arc(r.get_center(), (r.size.x - w) * 0.5, 0.0, TAU, Tuning.RESULT_STAMP_ARC_POINTS, color, w, true)
	if not done:
		return
	var pts := PackedVector2Array()
	for p: Vector2 in Tuning.CHALLENGE_CHECK:
		pts.append(r.position + p * r.size)
	ci.draw_polyline(pts, color, w, true)


## 設計書 3.2: 新しく取った検定印の札。RESULT_STAMPS_MAX 個まで小さな丸判子と名前を並べ、残りは「ほか N 個」。
## 判子は押すまで透明にしておく（隠すと名前の位置がずれる）
## TODO(spec): 小さな丸判子の中の字は仕様に無い。検定印の「検」にした。名前の横に条件は出さない（試験記録の画面で見る）
func _fill_new_stamps() -> void:
	var ids: Array = _data.get("new_stamps", [])
	_new_stamps.visible = not ids.is_empty() or not (_data.get("new_trolleys", []) as Array).is_empty()
	for c: Control in [%NewHead, %NewList]:
		c.visible = not ids.is_empty()
	var shown: int = mini(ids.size(), Tuning.RESULT_STAMPS_MAX)
	for i: int in shown:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", Tuning.RESULT_NEW_MARK_GAP)
		# コンテナは子の回転と拡大率を戻すので、判子はコンテナの外の子（holder の子）にする
		var holder := Control.new()
		holder.custom_minimum_size = Vector2.ONE * Tuning.RESULT_NEW_MARK_SIZE
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mark := Control.new()
		mark.size = holder.custom_minimum_size
		mark.pivot_offset = mark.size * 0.5
		mark.rotation = deg_to_rad(Tuning.RESULT_NEW_MARK_DEG)
		mark.modulate.a = 0.0
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.draw.connect(_draw_mark.bind(mark))
		holder.add_child(mark)
		row.add_child(holder)
		row.add_child(_text(Achievements.name_of(ids[i]), Fonts.BIZ_BOLD, Tuning.RESULT_NEW_NAME_FONT_SIZE))
		%NewList.add_child(row)
		_marks.append(mark)
	var more: Label = %NewMore
	more.visible = ids.size() > shown
	more.text = "ほか %d 個" % (ids.size() - shown)


## 新しく解放された車両（new_trolleys）: 札の上の段に、小さな絵（検定印の小さな判子と同じ枠）と名前、使い方の一言
func _fill_new_trolleys() -> void:
	var ids: Array = _data.get("new_trolleys", [])
	for c: Control in [%TrolleyHead, %TrolleyList, %TrolleyNote]:
		c.visible = not ids.is_empty()
	for id: String in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", Tuning.RESULT_NEW_MARK_GAP)
		var pic := Control.new()
		pic.custom_minimum_size = Vector2.ONE * Tuning.RESULT_NEW_MARK_SIZE
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.draw.connect(_draw_new_trolley.bind(pic, id))
		row.add_child(pic)
		row.add_child(_text(Trolleys.name_of(id), Fonts.BIZ_BOLD, Tuning.RESULT_NEW_NAME_FONT_SIZE))
		%TrolleyList.add_child(row)


## 新しい車両の小さな絵（ゲーム画面と同じ絵を縮めて、枠の真ん中に）
func _draw_new_trolley(pic: Control, id: String) -> void:
	var k: float = Tuning.RESULT_NEW_TROLLEY_SCALE
	pic.draw_set_transform(pic.size * 0.5 + Vector2(0.0, Tuning.TROLLEY_H * k * 0.5), 0.0, Vector2.ONE * k)
	Trolley.draw_body(pic, id, GameState.garage(id)["paint"])
	pic.draw_set_transform(Vector2.ZERO)


## 新しい検定印の判子を1つ押す（合否の判子と同じ拡大率で）
## TODO(spec): 小さな判子の音は仕様に無い。合否の判子と同じ stamp を鳴らす
func _press_mark(mark: Control) -> void:
	mark.modulate.a = Tuning.RESULT_STAMP_ALPHA
	mark.scale = Vector2.ONE * Tuning.RESULT_STAMP_POP_SCALE
	create_tween().set_ignore_time_scale(true).tween_property(mark, "scale", Vector2.ONE, Tuning.RESULT_STAMP_POP_TIME)
	Audio.play(&"stamp")


## 報告書の1行: 左にラベル列、右に値（parts を gap 空けて横に並べる）
func _row(label: String, parts: Array[Control], gap: float = Tuning.RESULT_TAG_GAP) -> Label:
	var head: Label = _text(label, Fonts.BIZ, Tuning.RESULT_LABEL_FONT_SIZE, Palette.MUTED)
	head.custom_minimum_size.x = Tuning.RESULT_LABEL_COL_W
	_grid.add_child(head)
	var value := HBoxContainer.new()
	value.add_theme_constant_override(&"separation", int(gap))
	for p: Control in parts:
		value.add_child(p)
	_grid.add_child(value)
	return head


func _text(s: String, font: Font, font_size: int, color: Color = Palette.INK) -> Label:
	var l := Label.new()
	l.text = s
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiButton.style_label(l, font, font_size, color)
	return l


## 報告書の数値（Courier Prime）
func _value(s: String) -> Label:
	return _text(s, Fonts.courier, Tuning.RESULT_VALUE_FONT_SIZE)


## 「最高記録更新」の札: 警告黄の地に墨の枠
func _tag(s: String) -> Label:
	# TODO(spec): 札の文字はデザイン案では Dela Gothic One 14px。16.2 の下限 18px に上げた
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


## 右列のボタン。寸法はデザイン案（主 64px・24px、副 54px。17.1 の範囲内）で、UiButton の _ready が入れた値を上書きする
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


## 17.7: 判子を押し、揺れの設定が ON なら振幅6pxで0.15秒揺らす（振幅は0へ線形に減らす、FR-33 と同じ）
func _press_stamp() -> void:
	_stamp.press()
	if not GameState.screen_shake:
		return
	# TODO(spec): 17.7 は「カメラを揺らす」だが、カメラは下に隠れたゲーム画面のもの。報告書（判子ごと）を揺らす
	var home: Vector2 = _report.position
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_method(_shake_report.bind(home), 1.0, 0.0, Tuning.RESULT_SHAKE_TIME)
	tween.tween_callback(func() -> void: _report.position = home)


## 揺れの1コマ。k は残りの割合（1→0）
func _shake_report(k: float, home: Vector2) -> void:
	_report.position = home + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * Tuning.RESULT_SHAKE_AMP * k


func _style() -> void:
	var t := Theme.new()  # 報告書の本文（BIZ UDPGothic、16.2）
	t.set_font(&"font", &"Label", Fonts.BIZ)
	t.set_font_size(&"font_size", &"Label", Tuning.RESULT_TEXT_FONT_SIZE)
	t.set_color(&"font_color", &"Label", Palette.INK)
	theme = t
	UiButton.style_label(%Heading, Fonts.DELA, Tuning.RESULT_HEAD_FONT_SIZE, Palette.INK)
	var no: Label = %ReportNo
	UiButton.style_label(no, Fonts.courier, Tuning.RESULT_NO_FONT_SIZE, Palette.MUTED)
	_line_height(no, Tuning.RESULT_NO_LINE_HEIGHT)
	UiButton.style_label(%RatingLabel, Fonts.BIZ, Tuning.RESULT_LABEL_FONT_SIZE, Palette.MUTED)
	UiButton.style_label(%RemainPoints, Fonts.courier_bold, Tuning.RESULT_VALUE_FONT_SIZE, Palette.INK)
	var hint_text: Label = %HintText
	hint_text.language = "ja@lb=strict"  # 行頭に「ー」や小書きの仮名を置かない（ICU の厳格な禁則）
	_line_height(hint_text, Tuning.RESULT_HINT_LINE_HEIGHT)
	var box := StyleBoxFlat.new()  # 16.3: 不合格リザルトのヒント欄は PAPER_DARK
	box.bg_color = Palette.PAPER_DARK
	# 行間の半分を上下にも足す（デザイン案の line-height は1行目の上と最終行の下にも余白を付ける）
	var half_leading: float = hint_text.get_theme_constant(&"line_spacing") * 0.5
	box.content_margin_left = Tuning.RESULT_HINT_PAD.x
	box.content_margin_right = Tuning.RESULT_HINT_PAD.x
	box.content_margin_top = Tuning.RESULT_HINT_PAD.y + half_leading
	box.content_margin_bottom = Tuning.RESULT_HINT_PAD.y + half_leading
	_hint.add_theme_stylebox_override(&"panel", box)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # 背景と紙の粒（設計書5章）
	_report.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_report.draw.connect(_draw_report)
	_head.draw.connect(_draw_head_rule.bind(_head))
	_rating.draw.connect(_draw_rating_rule)
	_hint_icon.draw.connect(_draw_hint_icon)
	# 設計書 3.2: 新しい検定印の札（報告書と同じ生成りの紙、上端にストライプ）
	UiButton.style_label(%NewHeading, Fonts.DELA, Tuning.RESULT_NEW_HEAD_FONT_SIZE, Palette.INK)
	UiButton.style_label(%NewMore, Fonts.BIZ, Tuning.RESULT_NEW_MORE_FONT_SIZE, Palette.MUTED)
	_new_stamps.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_new_stamps.draw.connect(_draw_slip)
	var new_head: Control = %NewHead
	new_head.draw.connect(_draw_head_rule.bind(new_head))
	UiButton.style_label(%TrolleyHeading, Fonts.DELA, Tuning.RESULT_NEW_HEAD_FONT_SIZE, Palette.INK)
	UiButton.style_label(%TrolleyNoteText, Fonts.BIZ, Tuning.RESULT_NEW_NOTE_FONT_SIZE, Palette.MUTED)
	var trolley_head: Control = %TrolleyHead
	trolley_head.draw.connect(_draw_head_rule.bind(trolley_head))


## 行の高さを文字の大きさの ratio 倍にする（デザイン案の line-height）
func _line_height(l: Label, ratio: float) -> void:
	var font: Font = l.get_theme_font(&"font")
	var fs: int = l.get_theme_font_size(&"font_size")
	l.add_theme_constant_override(&"line_spacing", roundi(fs * ratio - font.get_height(fs)))


func _draw() -> void:
	UiButton.draw_menu_bg(self, Rect2(Vector2.ZERO, size))


## 17.7: 生成りの報告書（10pxずらしの影、16.4）と上端中央のクリップ（STEEL、墨の枠）
func _draw_report() -> void:
	var r := Rect2(Vector2.ZERO, _report.size)
	_report.draw_rect(Rect2(Tuning.UI_PANEL_SHADOW, r.size), Palette.SHADOW)
	_report.draw_rect(r, Palette.PAPER)
	DrawUtil.tile_noise(_report, r, "grain", Tuning.PAPER_GRAIN_ALPHA)
	var clip := Rect2((r.size.x - Tuning.RESULT_CLIP_SIZE.x) * 0.5, -Tuning.RESULT_CLIP_RISE, Tuning.RESULT_CLIP_SIZE.x,
			Tuning.RESULT_CLIP_SIZE.y)
	# 設計書5章: クリップに金属の光沢（上が明るいぼかしと、上の光の筋）
	DrawUtil.fill_gradient(_report, DrawUtil.rounded_rect(clip, 0.0), clip.position, Vector2(clip.position.x, clip.end.y),
			[Palette.STEEL_LIGHT, Palette.STEEL_SHADE], [0.0, 1.0])
	_report.draw_line(clip.position + Vector2(0.0, Tuning.RESULT_CLIP_BORDER + 1.0),
			Vector2(clip.end.x, clip.position.y + Tuning.RESULT_CLIP_BORDER + 1.0), Palette.RAIL_TOP, Tuning.RESULT_CLIP_GLINT_W)
	_report.draw_rect(clip.grow(-Tuning.RESULT_CLIP_BORDER * 0.5), Palette.INK, false, Tuning.RESULT_CLIP_BORDER)


## 見出しの下の墨の線（デザイン案）。報告書と検定印の札の見出し
func _draw_head_rule(head: Control) -> void:
	var w: float = Tuning.RESULT_HEAD_RULE
	head.draw_rect(Rect2(0.0, head.size.y - w, head.size.x, w), Palette.INK)


## 設計書 3.2: 検定印の札。報告書と同じ生成りの紙と影に、上端のストライプ（新しく取った知らせ）
## TODO(spec): 札の見た目は仕様に無い。報告書の紙と設定のパネルの上端のストライプ（16.4）を借りた
func _draw_slip() -> void:
	var r := Rect2(Vector2.ZERO, _new_stamps.size)
	_new_stamps.draw_rect(Rect2(Tuning.UI_PANEL_SHADOW, r.size), Palette.SHADOW)
	_new_stamps.draw_rect(r, Palette.PAPER)
	DrawUtil.tile_noise(_new_stamps, r, "grain", Tuning.PAPER_GRAIN_ALPHA)
	DrawUtil.stripes(_new_stamps, Rect2(0.0, 0.0, r.size.x, Tuning.UI_PANEL_BAND_H), Tuning.UI_PANEL_STRIPE_W)


## 新しい検定印の小さな朱の丸判子（中に「検」）
func _draw_mark(mark: Control) -> void:
	var s: float = Tuning.RESULT_NEW_MARK_SIZE
	var w: float = Tuning.RESULT_NEW_MARK_LINE
	mark.draw_arc(Vector2.ONE * s * 0.5, (s - w) * 0.5, 0.0, TAU, Tuning.RESULT_STAMP_ARC_POINTS, Palette.STAMP, w, true)
	var fs: int = Tuning.RESULT_NEW_MARK_FONT_SIZE
	var baseline: float = (s + Fonts.DELA.get_ascent(fs) - Fonts.DELA.get_descent(fs)) * 0.5
	mark.draw_string(Fonts.DELA, Vector2(0.0, baseline), "検", HORIZONTAL_ALIGNMENT_CENTER, s, fs, Palette.STAMP)


## ★の欄の上の破線（デザイン案）
func _draw_rating_rule() -> void:
	var y: float = Tuning.RESULT_DASH_W * 0.5
	_rating.draw_dashed_line(Vector2(0.0, y), Vector2(_rating.size.x, y), Palette.MUTED_ON_INK, Tuning.RESULT_DASH_W,
			Tuning.RESULT_DASH)


## ★を STARS_MAX 個。獲得分は警告黄に墨の輪郭、未獲得は LOCKED の破線の輪郭（デザイン案の SVG）
func _draw_stars() -> void:
	var k: float = Tuning.RESULT_STAR_SIZE / Tuning.RESULT_ICON_BOX
	var w: float = Tuning.RESULT_STAR_OUTLINE * k
	for i: int in Tuning.STARS_MAX:
		var offset := Vector2(i * (Tuning.RESULT_STAR_SIZE + Tuning.RESULT_STAR_GAP), 0.0)
		var pts := PackedVector2Array()
		for p: Vector2 in Tuning.RESULT_STAR_POINTS:
			pts.append(offset + p * k)
		if i < _stars:
			_stars_box.draw_colored_polygon(pts, Palette.HAZARD)
			pts.append(pts[0])
			_stars_box.draw_polyline(pts, Palette.INK, w, true)
		else:
			pts.append(pts[0])
			for j: int in pts.size() - 1:
				_stars_box.draw_dashed_line(pts[j], pts[j + 1], Palette.LOCKED, w, Tuning.RESULT_STAR_DASH * k)


## replay-value-design.md 3.2: 金★。取るまでは金色の破線の輪郭、取った走行では判子の後に金色に塗る（墨の輪郭）
func _draw_gold_star() -> void:
	var k: float = Tuning.RESULT_STAR_SIZE / Tuning.RESULT_ICON_BOX
	var w: float = Tuning.RESULT_STAR_OUTLINE * k
	var pts := PackedVector2Array()
	for p: Vector2 in Tuning.RESULT_STAR_POINTS:
		pts.append(p * k)
	if _gold_shown:
		_gold_star.draw_colored_polygon(pts, Palette.GOLD_STAR)
		pts.append(pts[0])
		_gold_star.draw_polyline(pts, Palette.INK, w, true)
		return
	pts.append(pts[0])
	for j: int in pts.size() - 1:
		_gold_star.draw_dashed_line(pts[j], pts[j + 1], Palette.GOLD_STAR, w, Tuning.RESULT_STAR_DASH * k)


## 金★を塗り、検定印の小さな判子と同じく拡大率 1.6→1.0 で出す
func _press_gold() -> void:
	_gold_shown = true
	_gold_star.queue_redraw()
	_gold_star.scale = Vector2.ONE * Tuning.RESULT_STAMP_POP_SCALE
	create_tween().set_ignore_time_scale(true).tween_property(_gold_star, "scale", Vector2.ONE, Tuning.RESULT_STAMP_POP_TIME)
	Audio.play(&"stamp")


## ヒント欄の電球（デザイン案の SVG を線で描く）
func _draw_hint_icon() -> void:
	var k: float = Tuning.RESULT_HINT_ICON_SIZE / Tuning.RESULT_ICON_BOX
	var w: float = Tuning.RESULT_HINT_ICON_LINE
	var arc: Vector2 = Tuning.RESULT_HINT_BULB_ARC_DEG
	_hint_icon.draw_arc(Tuning.RESULT_HINT_BULB_CENTER * k, Tuning.RESULT_HINT_BULB_RADIUS * k, deg_to_rad(arc.x),
			deg_to_rad(arc.y), Tuning.RESULT_STAMP_ARC_POINTS, Palette.INK, w, true)
	for line: Array in Tuning.RESULT_HINT_BULB_LINES:
		var pts := PackedVector2Array()
		for p: Vector2 in line:
			pts.append(p * k)
		_hint_icon.draw_polyline(pts, Palette.INK, w, true)
