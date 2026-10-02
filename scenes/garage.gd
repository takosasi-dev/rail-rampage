extends Control
## 車庫（車両を選ぶ画面。docs/superpowers/specs/2026-09-26-trolleys-and-display-design.md の3章）。
## ステージ選択の上に重ねるオーバーレイ。5台のカード（絵・名前・長所と短所・性能の棒グラフ）を横に並べ、
## ←→ で選び、「この車両にする」（Space / Enter）で GameState.set_trolley してから closed を出す。
## 「戻る」か Esc は何も変えずに closed を出す。閉じるのは開いた側。
## 依頼者の判断を待たずに決めた（配置・文言・棒グラフの見せ方は試遊の後に見直す）
## TODO(spec): 開いたときは今の車両のカードを選び、「この車両にする」（この画面の主ボタン）にフォーカスを置く。
##             ↑↓ は「この車両にする」と「戻る」の間のフォーカス移動（ステージ選択と同じ）
## TODO(spec): ←→ は未解放の車両にも止まる（解放の条件を読めるように）。端では止まる。
##             未解放の車両を選んでいる間は「この車両にする」を「未解放」にして押せなくする
## TODO(spec): マウスは、選んでいないカードのクリックで選び、選んでいるカードのクリックで決める（ステージ選択と同じ）
## TODO(spec): 未解放の車両のカードは、絵を薄くして錠前を重ね、名前と解放の条件だけ出す（長所・短所・棒グラフは出さない）
## TODO(spec): 標準型の長所・短所は「―」。棒グラフの真ん中の縦線が標準型の値で、ヘッダーの右端に凡例を出す
##
## やりこみ（replay-value-design.md 5章）: カードに熟練度（「熟練 ◯段」と次の段までの棒）。「整備」ボタンか E で
## 選んでいる車両の整備パネル（強化6項目・振り直し・塗装5つ）を開く。性能の棒グラフは強化込みの値で、伸びた分は緑
## TODO(spec): 整備のキーは E（他の画面で使っていないキー）。↑↓ は「この車両にする」→「戻る」→「整備」の順に回る
## TODO(spec): 整備パネルは車庫の上に重ねる。E か Esc で閉じる（振り直しの確認中の Esc は確認を閉じるだけ）。
##             ポイントが足りない・最大の段の項目も押せる（押すと理由を出す）。使えない塗装も押せる（解放の段を出す）
## TODO(spec): 効き目の文は今の段の効き目と次の段の効き目（「爆発の範囲 +5% → +10%」、最大なら今の段だけ）

signal closed

const UiButton := preload("res://scenes/ui/ui_button.gd")
const StageSelect := preload("res://scenes/stage_select.gd")
const DECIDE_TEXT: String = "この車両にする"
const LOCKED_TEXT: String = "未解放"
const NO_TRAIT: String = "―"
## 強化の効き目の文の主語（Tuning.UPGRADES の id → 何が変わるか）
const UPGRADE_EFFECTS: Dictionary = {
	"hit_power": "吹っ飛ばす力", "blast_radius": "爆発の範囲", "combo_window": "コンボの受付時間",
	"girigiri_margin": "ギリギリ突破の幅", "wall_factor": "壁の必要速度", "jump_factor": "ジャンプの必要速度",
}
## 性能の棒グラフ（設計書3章）: [見出し, Trolleys.stat のキー, 値が小さいほど強いか]
## TODO(spec): 「勢い」は溜まりやすさ（momentum_gain）の棒。減りやすさ（momentum_decay）は棒に出さず短所の文で示す
const BARS: Array = [["初速", "speed_base", false], ["最高速", "speed_max", false], ["勢い", "momentum_gain", false],
	["壁", "wall_factor", true], ["ジャンプ", "jump_factor", true], ["吹っ飛ばす力", "hit_power", false]]

## 選んでいる車両（Trolleys.IDS の添字）
var selected: int = 0

var _cards: Array[Control] = []
var _up_buttons: Array[UiButton] = []  # 強化の行のボタン（Tuning.UPGRADES の順）
var _paint_buttons: Array[UiButton] = []  # 塗装のボタン（0〜）

@onready var _header: Control = $Header
@onready var _decide: UiButton = %Decide
@onready var _back: UiButton = %Back
@onready var _maintain: UiButton = %Maintain
@onready var _workshop: Control = %Workshop
@onready var _ws_panel: Control = $Workshop/Panel
@onready var _reset: UiButton = %Reset
@onready var _confirm: PanelContainer = %Confirm
@onready var _reset_no: UiButton = %ResetNo
@onready var _reset_yes: UiButton = %ResetYes
@onready var _message: Label = %Message


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # 紙の粒（ステージ選択と同じ地）
	_style()  # 1枚目のカードに文字の書体を付けてから複製する
	var row: Control = $Cards
	var template: Control = row.get_child(0)
	for _i: int in Trolleys.IDS.size() - 1:
		row.add_child(template.duplicate())
	for i: int in Trolleys.IDS.size():
		var card: Control = row.get_child(i)
		_cards.append(card)
		card.draw.connect(_draw_card.bind(i))
		(card.get_node("Body/Picture") as Control).draw.connect(_draw_picture.bind(i))
		var lock: Control = card.get_node("Body/Picture/Lock")
		lock.draw.connect(func() -> void: StageSelect.draw_lock(lock))  # 未解放の錠前（ステージ選択と同じ絵）
		(card.get_node("Body/Bars") as Control).draw.connect(_draw_bars.bind(i))
		(card.get_node("Body/Mastery/XpBar") as Control).draw.connect(_draw_xp_bar.bind(i))
		card.gui_input.connect(_on_card_input.bind(i))
		_fill_card(i)
	_decide.pressed.connect(_decide_selected)
	_back.pressed.connect(closed.emit)
	_maintain.pressed.connect(open_workshop)
	_build_workshop()
	selected = maxi(Trolleys.IDS.find(GameState.trolley()), 0)
	_refresh()
	UiButton.focus_quietly(_decide)  # FR-47a: 開いた時点で主ボタンにフォーカス


## ←→ で車両を選ぶ。フォーカス中のボタンに渡るとフォーカスが動くので、GUI より先に受け取る。
## 整備パネルを開いている間は、←→ はパネルの中のフォーカス移動（GUI に任せる）
func _input(event: InputEvent) -> void:
	if _workshop.visible:
		return
	var step: int = 0
	if event.is_action_pressed("ui_left", true):
		step = -1
	elif event.is_action_pressed("ui_right", true):
		step = 1
	else:
		return
	get_viewport().set_input_as_handled()
	_select(clampi(selected + step, 0, Trolleys.IDS.size() - 1))


## FR-47a: Esc で戻る（何も変えない）。整備パネルを開いていればパネルを閉じる（振り直しの確認中は確認を閉じる）。
## E で整備パネルを開く・閉じる
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_E:
		get_viewport().set_input_as_handled()
		if _workshop.visible:
			Audio.play(&"ui_select")
			close_workshop()
		elif not _maintain.disabled:
			_maintain.pressed.emit()  # 「整備」を押したのと同じ（ui_select も鳴る）
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.play(&"ui_select")
		if _confirm.visible:
			_close_confirm()
		elif _workshop.visible:
			close_workshop()
		else:
			closed.emit()


## カードのクリック: 選んでいなければ選ぶ、選んでいれば決める（未解放は決められない）
func _on_card_input(event: InputEvent, i: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if i != selected:
		_select(i)
		UiButton.focus_quietly(_decide)  # 続けて Space で決められるように
	elif not _decide.disabled:
		_decide.pressed.emit()  # 「この車両にする」を押したのと同じ（ui_select も鳴る）


func _select(i: int) -> void:
	if i == selected:
		return
	selected = i
	Audio.play(&"ui_move")
	_refresh()


func _decide_selected() -> void:
	GameState.set_trolley(Trolleys.IDS[selected])
	closed.emit()


## 選んでいるカードの枠と、「この車両にする」（未解放なら押せない「未解放」）
func _refresh() -> void:
	for card: Control in _cards:
		card.queue_redraw()
	var ok: bool = GameState.is_trolley_unlocked(Trolleys.IDS[selected])
	_decide.disabled = not ok
	_decide.text = DECIDE_TEXT if ok else LOCKED_TEXT
	_maintain.disabled = not ok  # 未解放の車両は整備できない
	if ok:  # 生成り地の上の主ボタン（UiButton と同じ）
		_decide.paint(Palette.HAZARD, Palette.INK, Tuning.UI_PRIMARY_BORDER_ON_PAPER, Palette.INK)
		_maintain.paint(null, Palette.INK, Tuning.UI_THIN_BORDER, Palette.INK)
	else:  # 押せない: 未解放のカードと同じ地と色（試験記録の「修了証書」と同じ）
		_decide.paint(Palette.BOARD, Palette.LOCKED, Tuning.UI_THIN_BORDER, Palette.MUTED)
		_maintain.paint(Palette.BOARD, Palette.LOCKED, Tuning.UI_THIN_BORDER, Palette.MUTED)


## カードの文字。解放済みは名前・「使用中」・長所と短所・棒グラフ、未解放は薄い絵と錠前・名前・解放の条件
func _fill_card(i: int) -> void:
	var id: String = Trolleys.IDS[i]
	var unlocked: bool = GameState.is_trolley_unlocked(id)
	var card: Control = _cards[i]
	var body: Control = card.get_node("Body")
	var name_label: Label = body.get_node("NameRow/Name")
	name_label.text = Trolleys.name_of(id)
	name_label.add_theme_color_override("font_color", Palette.INK if unlocked else Palette.MUTED)
	(body.get_node("NameRow/InUse") as Control).visible = id == GameState.trolley()
	(body.get_node("Traits/Pros") as Label).text = _lines(Trolleys.pros_of(id))
	(body.get_node("Traits/Cons") as Label).text = _lines(Trolleys.cons_of(id))
	(body.get_node("LockHint") as Label).text = Trolleys.unlock_text(id)
	(body.get_node("Mastery/Level") as Label).text = mastery_text(GameState.garage(id))
	for path: String in ["Traits", "Bars", "Mastery"]:
		(body.get_node(path) as Control).visible = unlocked
	for path: String in ["LockHint", "Picture/Lock"]:
		(body.get_node(path) as Control).visible = not unlocked
	(body.get_node("Picture") as CanvasItem).self_modulate = Palette.WHITE if unlocked else Palette.GARAGE_LOCKED_FADE
	card.mouse_default_cursor_shape = CURSOR_POINTING_HAND


## 長所・短所の文（「・」区切り）を1行に1つずつ。空なら「―」
static func _lines(text: String) -> String:
	return NO_TRAIT if text.is_empty() else text.replace("・", "\n")


## 「熟練 3段」（最大の段は「熟練 25段（最高）」）。g は GameState.garage の辞書
static func mastery_text(g: Dictionary) -> String:
	return "熟練 %d段%s" % [g["level"], "（最高）" if g["level"] >= Tuning.LEVEL_MAX else ""]


## 性能の強さ: 標準型との比（標準型は 1。壁・ジャンプの倍率は小さいほど強いので逆数）。
## upgrades を渡すと強化込み（Progression.stat）
static func strength(id: String, key: String, smaller_is_stronger: bool, upgrades: Dictionary = {}) -> float:
	var r: float = Progression.stat(id, key, upgrades) / Trolleys.stat(Trolleys.DEFAULT, key)
	return 1.0 / r if smaller_is_stronger else r


## 強化の効き目の文。step 段の効き目（「爆発の範囲 +10%」「壁の必要速度 −6%」）
static func effect_text(item: String, step: int) -> String:
	return "%s %s" % [UPGRADE_EFFECTS.get(item, ""), _percent(_change(item) * step)]


## 倍率の変化を「+10%」「−6%」に（0 は「±0%」）
static func _percent(f: float) -> String:
	var n: int = roundi(f * 100.0)
	if n == 0:
		return "±0%"
	return ("+%d%%" if n > 0 else "−%d%%") % absi(n)


## 棒の長さ（棒の幅に対する割合）。標準型は真ん中
static func bar_fraction(r: float) -> float:
	return clampf(0.5 + (r - 1.0) * Tuning.GARAGE_BAR_GAIN, 0.0, 1.0)


func _style() -> void:
	var heading: Label = %Heading
	UiButton.style_label(heading, Fonts.DELA, Tuning.SELECT_HEAD_FONT_SIZE, Palette.PAPER)
	UiButton.style_label(%Sub, UiButton.spaced(Fonts.courier), Tuning.SELECT_SUB_FONT_SIZE, Palette.HAZARD)
	StageSelect._align_baseline(%Sub, heading)
	UiButton.style_label(%Legend, Fonts.BIZ, Tuning.GARAGE_LEGEND_FONT_SIZE, Palette.MUTED_ON_INK)
	var body: Control = $Cards/Card/Body
	UiButton.style_label(body.get_node("NameRow/Name"), Fonts.DELA, Tuning.GARAGE_NAME_FONT_SIZE, Palette.INK)
	var tag: Label = body.get_node("NameRow/InUse")
	UiButton.style_label(tag, Fonts.DELA, Tuning.GARAGE_TAG_FONT_SIZE, Palette.INK)
	var sb := StyleBoxFlat.new()  # リザルトの「最高記録更新」の札と同じ: 警告黄の地に墨の枠
	sb.bg_color = Palette.HAZARD
	sb.border_color = Palette.INK
	sb.set_border_width_all(Tuning.RESULT_TAG_BORDER)
	sb.content_margin_left = Tuning.RESULT_TAG_PAD.x
	sb.content_margin_right = Tuning.RESULT_TAG_PAD.x
	sb.content_margin_top = Tuning.RESULT_TAG_PAD.y
	sb.content_margin_bottom = Tuning.RESULT_TAG_PAD.y
	tag.add_theme_stylebox_override(&"normal", sb)
	var fs: int = Tuning.GARAGE_TRAIT_FONT_SIZE
	UiButton.style_label(body.get_node("Traits/ProsLabel"), Fonts.BIZ_BOLD, fs, Palette.INK)
	UiButton.style_label(body.get_node("Traits/ConsLabel"), Fonts.BIZ_BOLD, fs, Palette.STAMP_TEXT)
	for path: String in ["Traits/Pros", "Traits/Cons"]:
		UiButton.style_label(body.get_node(path), Fonts.BIZ, fs, Palette.INK)
		(body.get_node(path) as Label).language = "ja@lb=strict"  # 行頭に「ー」や小書きの仮名を置かない
	UiButton.style_label(body.get_node("LockHint"), Fonts.BIZ, Tuning.GARAGE_LOCK_HINT_FONT_SIZE, Palette.MUTED)
	UiButton.style_label(body.get_node("Mastery/Level"), Fonts.BIZ_BOLD, Tuning.GARAGE_MASTERY_FONT_SIZE, Palette.INK)
	UiButton.style_label(%Help, Fonts.courier, Tuning.SELECT_HELP_FONT_SIZE, Palette.MUTED)
	_decide.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_maintain.alignment = HORIZONTAL_ALIGNMENT_CENTER
	for b: UiButton in [_decide, _maintain]:
		b.add_theme_color_override(&"font_disabled_color", Palette.MUTED)  # paint() は押せないときの文字色を決めない
	# 整備パネル（設定画面と同じ文字の大きさ）
	UiButton.style_label(%WsHeading, Fonts.DELA, Tuning.SETTINGS_HEAD_FONT_SIZE, Palette.INK)
	UiButton.style_label(%WsName, Fonts.DELA, Tuning.SETTINGS_LABEL_FONT_SIZE, Palette.INK)
	for path: String in ["%WsLevel", "%WsPoints", "%UpTitle", "%PaintTitle"]:
		UiButton.style_label(get_node(path), Fonts.BIZ_BOLD, Tuning.SETTINGS_LABEL_FONT_SIZE, Palette.INK)
	UiButton.style_label(%ConfirmText, Fonts.BIZ_BOLD, Tuning.SETTINGS_TEXT_FONT_SIZE, Palette.INK)
	UiButton.style_label(_message, Fonts.BIZ_BOLD, Tuning.GARAGE_WS_EFFECT_FONT_SIZE, Palette.STAMP_TEXT)
	UiButton.style_label(%WsHelp, Fonts.courier, Tuning.GARAGE_WS_SMALL_FONT_SIZE, Palette.MUTED)
	# 振り直しは記録の消去と同じ色（設定画面 16.3）
	_reset.paint(Palette.PAPER, Palette.STAMP, Tuning.UI_THIN_BORDER, Palette.STAMP_TEXT)
	_reset_no.paint(Palette.PAPER, Palette.INK, Tuning.UI_THIN_BORDER, Palette.INK)
	_reset_yes.paint(Palette.STAMP, Palette.INK, Tuning.UI_THIN_BORDER, Palette.WHITE)
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.STAMP_LIGHT
	box.border_color = Palette.STAMP
	box.set_border_width_all(Tuning.UI_THIN_BORDER)
	box.content_margin_left = Tuning.SETTINGS_CONFIRM_PAD.x
	box.content_margin_right = Tuning.SETTINGS_CONFIRM_PAD.x
	box.content_margin_top = Tuning.SETTINGS_CONFIRM_PAD.y * 0.5
	box.content_margin_bottom = Tuning.SETTINGS_CONFIRM_PAD.y * 0.5
	_confirm.add_theme_stylebox_override(&"panel", box)


## 地・横罫・ヘッダー・ストライプはステージ選択と同じ（17.1, 17.3）
func _draw() -> void:
	StageSelect.draw_page(self, _header.get_rect())


## カードの地と枠（ステージ選択のカードと同じ）。選んでいるカードは白地（未解放は BOARD）・墨の枠・警告黄の外枠・影
func _draw_card(i: int) -> void:
	var card: Control = _cards[i]
	var r := Rect2(Vector2.ZERO, card.size)
	var b: float = Tuning.SELECT_CARD_BORDER
	var unlocked: bool = GameState.is_trolley_unlocked(Trolleys.IDS[i])
	if i == selected:
		card.draw_rect(Rect2(Tuning.SELECT_CARD_SHADOW, r.size), Palette.INK)
		card.draw_rect(r, Palette.WHITE if unlocked else Palette.BOARD)
		UiButton.draw_focus(card, r.grow(-Tuning.UI_FOCUS_W))
	elif unlocked:
		card.draw_rect(r, Palette.PAPER_LIGHT)
		card.draw_rect(r.grow(-b * 0.5), Palette.INK, false, b)
	else:
		card.draw_rect(r, Palette.BOARD)
		StageSelect._draw_dashed_rect(card, r.grow(-b * 0.5), Palette.LOCKED, b)


## 車両の絵をレールの上に（ゲーム画面と同じ Trolley.draw_body を拡大して）
func _draw_picture(i: int) -> void:
	var pic: Control = _cards[i].get_node("Body/Picture")
	var k: float = Tuning.GARAGE_PICTURE_SCALE
	var rail_y: float = Tuning.GARAGE_PICTURE_RAIL_Y
	pic.draw_line(Vector2(0.0, rail_y), Vector2(pic.size.x, rail_y), Palette.STEEL, Tuning.RAIL_WIDTH * k)
	pic.draw_set_transform(Vector2(pic.size.x * 0.5, rail_y), 0.0, Vector2.ONE * k)
	Trolley.draw_body(pic, Trolleys.IDS[i], GameState.garage(Trolleys.IDS[i])["paint"])
	pic.draw_set_transform(Vector2.ZERO)


## 次の段までの棒（溝・墨の枠・得た分は墨）。最大の段は警告黄で満たす
func _draw_xp_bar(i: int) -> void:
	var bar: Control = _cards[i].get_node("Body/Mastery/XpBar")
	var h: float = Tuning.GARAGE_XP_BAR_H
	var track := Rect2(0.0, (bar.size.y - h) * 0.5, bar.size.x, h)
	var got: Array = Progression.xp_to_next(GameState.garage(Trolleys.IDS[i])["xp"])
	bar.draw_rect(track, Palette.PAPER_DARK)
	if got[1] == 0:
		bar.draw_rect(track, Palette.HAZARD)
	else:
		bar.draw_rect(Rect2(track.position, Vector2(track.size.x * float(got[0]) / float(got[1]), h)), Palette.INK)
	bar.draw_rect(track.grow(Tuning.GARAGE_BAR_BORDER * 0.5), Palette.INK, false, Tuning.GARAGE_BAR_BORDER)


## 性能の棒グラフ: 見出し・溝・棒。標準型の値（真ん中）までは墨、それより強い分は警告黄、弱い分は朱の薄い地に朱の枠。
## 真ん中に標準型の目盛り。強化で伸びた分（強化なしの値から強化込みの値まで）は緑
func _draw_bars(i: int) -> void:
	var bars: Control = _cards[i].get_node("Body/Bars")
	var id: String = Trolleys.IDS[i]
	var upgrades: Dictionary = GameState.garage(id)["upgrades"]
	var fs: int = Tuning.GARAGE_BAR_FONT_SIZE
	var label_w: float = 0.0
	for row: Array in BARS:
		label_w = maxf(label_w, Fonts.BIZ.get_string_size(row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var left: float = label_w + Tuning.GARAGE_BAR_LABEL_GAP
	var w: float = bars.size.x - left
	var h: float = Tuning.GARAGE_BAR_H
	var row_h: float = Tuning.GARAGE_BAR_ROW_H
	for k: int in BARS.size():
		var mid: float = row_h * (k + 0.5)
		var baseline: float = mid + (Fonts.BIZ.get_ascent(fs) - Fonts.BIZ.get_descent(fs)) * 0.5
		bars.draw_string(Fonts.BIZ, Vector2(0.0, baseline), BARS[k][0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.MUTED)
		var track := Rect2(left, mid - h * 0.5, w, h)
		bars.draw_rect(track, Palette.PAPER_DARK)
		var base_x: float = left + w * 0.5
		var x: float = left + w * bar_fraction(strength(id, BARS[k][1], BARS[k][2]))
		bars.draw_rect(Rect2(left, track.position.y, minf(x, base_x) - left, h), Palette.INK)
		if x > base_x:
			bars.draw_rect(Rect2(base_x, track.position.y, x - base_x, h), Palette.HAZARD)
		elif x < base_x:
			var loss := Rect2(x, track.position.y, base_x - x, h)
			bars.draw_rect(loss, Palette.STAMP_LIGHT)
			bars.draw_rect(loss.grow(-Tuning.GARAGE_BAR_BORDER * 0.5), Palette.STAMP, false, Tuning.GARAGE_BAR_BORDER)
		var up_x: float = left + w * bar_fraction(strength(id, BARS[k][1], BARS[k][2], upgrades))
		if up_x > x:
			bars.draw_rect(Rect2(x, track.position.y, up_x - x, h), Palette.GARAGE_UPGRADE_BAR)
		bars.draw_rect(track.grow(Tuning.GARAGE_BAR_BORDER * 0.5), Palette.INK, false, Tuning.GARAGE_BAR_BORDER)
		bars.draw_line(Vector2(base_x, mid - row_h * 0.5 + Tuning.GARAGE_BAR_BORDER),
				Vector2(base_x, mid + row_h * 0.5 - Tuning.GARAGE_BAR_BORDER), Palette.INK, Tuning.GARAGE_BAR_TICK_W)


# --- 整備パネル（replay-value-design.md 5.2〜5.4） ---

## 整備パネルの部品を作る: 強化の行（ボタン・段・効き目・値段）× 6 と、塗装のボタン × 5
func _build_workshop() -> void:
	_ws_panel.draw.connect(_draw_ws_panel)
	_ws_panel.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_workshop.draw.connect(func() -> void:
		_workshop.draw_rect(Rect2(Vector2.ZERO, _workshop.size), Color(Palette.INK, Tuning.PAUSE_VEIL_ALPHA)))
	var grid: GridContainer = %UpGrid
	for item: String in Progression.upgrade_ids():
		var b := UiButton.new()
		b.name = "Up_" + item
		b.on_ink = false
		b.text = Progression.upgrade_name(item)
		grid.add_child(b)
		b.custom_minimum_size.y = Tuning.GARAGE_WS_ROW_H  # UiButton._ready の高さより低く（6行を収める）
		b.pressed.connect(_buy.bind(item))
		_up_buttons.append(b)
		for part: String in ["Steps", "Effect", "Cost"]:
			var l := Label.new()
			l.name = part + "_" + item
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			UiButton.style_label(l, Fonts.BIZ_BOLD if part != "Effect" else Fonts.BIZ, Tuning.GARAGE_WS_EFFECT_FONT_SIZE, Palette.INK)
			grid.add_child(l)
	for p: int in Tuning.PAINT_UNLOCK_LEVELS.size():
		var b := UiButton.new()
		b.name = "Paint%d" % p
		b.on_ink = false
		%PaintGrid.add_child(b)
		b.custom_minimum_size = Tuning.GARAGE_WS_SWATCH
		var art := Control.new()
		art.name = "Art"
		art.mouse_filter = MOUSE_FILTER_IGNORE
		art.set_anchors_preset(PRESET_FULL_RECT)
		art.offset_bottom = -Tuning.GARAGE_WS_SWATCH_NAME_H
		art.draw.connect(_draw_swatch.bind(art, p))
		b.add_child(art)
		var lock := Control.new()
		lock.name = "Lock"
		lock.mouse_filter = MOUSE_FILTER_IGNORE
		lock.size = Vector2.ONE * Tuning.GARAGE_WS_LOCK_SIZE
		lock.position = (Tuning.GARAGE_WS_SWATCH - lock.size) * 0.5 - Vector2(0.0, Tuning.GARAGE_WS_SWATCH_NAME_H * 0.5)
		lock.draw.connect(func() -> void: StageSelect.draw_lock(lock))
		b.add_child(lock)
		var l := Label.new()
		l.name = "Name"
		l.mouse_filter = MOUSE_FILTER_IGNORE
		l.set_anchors_preset(PRESET_BOTTOM_WIDE)
		l.offset_top = -Tuning.GARAGE_WS_SWATCH_NAME_H
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UiButton.style_label(l, Fonts.BIZ_BOLD, Tuning.GARAGE_WS_SMALL_FONT_SIZE, Palette.INK)
		b.add_child(l)
		b.pressed.connect(_choose_paint.bind(p))
		_paint_buttons.append(b)
	_reset.pressed.connect(_open_confirm)
	_reset_no.pressed.connect(_close_confirm)
	_reset_yes.pressed.connect(_reset_upgrades)
	(%Close as UiButton).pressed.connect(close_workshop)


## 選んでいる車両の整備パネルを開く（未解放の車両は開かない）。フォーカスは強化の1行目
func open_workshop() -> void:
	if not GameState.is_trolley_unlocked(Trolleys.IDS[selected]):
		return
	_confirm.hide()
	_reset.show()
	_message.text = ""
	_fill_workshop()
	_workshop.show()
	UiButton.focus_quietly(_up_buttons[0])


func close_workshop() -> void:
	_workshop.hide()
	UiButton.focus_quietly(_maintain)


## 整備している車両の id
func workshop_id() -> String:
	return Trolleys.IDS[selected]


## 整備パネルの中身を今の熟練度・強化・塗装にする。カードの絵・棒グラフも描き直す
func _fill_workshop() -> void:
	var id: String = workshop_id()
	var g: Dictionary = GameState.garage(id)
	(%WsName as Label).text = Trolleys.name_of(id)
	(%WsLevel as Label).text = mastery_text(g)
	(%WsPoints as Label).text = "残り %d ポイント" % g["points_left"]
	var grid: GridContainer = %UpGrid
	for item: String in Progression.upgrade_ids():
		var step: int = g["upgrades"].get(item, 0)
		var cost: int = Progression.cost_of_next(step)
		var ok: bool = cost > 0 and cost <= g["points_left"]
		var steps: Label = grid.get_node("Steps_" + item)
		steps.text = "■".repeat(step) + "□".repeat(Tuning.UPGRADE_COSTS.size() - step)
		var effect: Label = grid.get_node("Effect_" + item)
		effect.text = effect_text(item, step) if cost == 0 else "%s → %s" % [effect_text(item, step), _percent(_change(item) * (step + 1))]
		var cost_label: Label = grid.get_node("Cost_" + item)
		cost_label.text = "最大" if cost == 0 else "%d ポイント" % cost
		cost_label.add_theme_color_override("font_color", Palette.MUTED if cost == 0 else (Palette.INK if ok else Palette.STAMP_TEXT))
		var b: UiButton = grid.get_node("Up_" + item)
		if ok:
			b.paint(null, Palette.INK, Tuning.UI_THIN_BORDER, Palette.INK)
		else:  # 押せるが強化できない（押すと理由を出す）: 未解放と同じ地と色
			b.paint(Palette.BOARD, Palette.LOCKED, Tuning.UI_THIN_BORDER, Palette.MUTED)
	var usable: int = Progression.paints_unlocked(g["level"])
	for p: int in _paint_buttons.size():
		var b: UiButton = _paint_buttons[p]
		var open: bool = p < usable
		(b.get_node("Lock") as Control).visible = not open
		(b.get_node("Art") as CanvasItem).self_modulate = Palette.WHITE if open else Palette.GARAGE_LOCKED_FADE
		var l: Label = b.get_node("Name")
		l.text = Trolley.paint_name(id, p) if open else "%d段で解放" % Tuning.PAINT_UNLOCK_LEVELS[p]
		l.add_theme_color_override("font_color", Palette.INK if open else Palette.MUTED)
		if p == g["paint"]:  # 使っている塗装（設定画面のタブと同じ警告黄の地）
			b.paint(Palette.HAZARD, Palette.INK, Tuning.UI_THIN_BORDER, Palette.INK)
		elif open:
			b.paint(Palette.PAPER_LIGHT, Palette.INK, Tuning.UI_THIN_BORDER, Palette.INK)
		else:
			b.paint(Palette.BOARD, Palette.LOCKED, Tuning.UI_THIN_BORDER, Palette.MUTED)
		(b.get_node("Art") as Control).queue_redraw()
	_fill_card(selected)
	_cards[selected].get_node("Body/Picture").queue_redraw()
	_cards[selected].get_node("Body/Bars").queue_redraw()
	_cards[selected].get_node("Body/Mastery/XpBar").queue_redraw()


static func _change(item: String) -> float:
	for u: Array in Tuning.UPGRADES:
		if u[0] == item:
			return u[2]
	return 0.0


## 強化の行を押した: 1段上げる。上げられなければ理由を出す
func _buy(item: String) -> void:
	var id: String = workshop_id()
	var g: Dictionary = GameState.garage(id)
	var cost: int = Progression.cost_of_next(g["upgrades"].get(item, 0))
	if GameState.buy_upgrade(id, item):
		_message.text = ""
	elif cost == 0:
		_message.text = "「%s」は最大の段" % Progression.upgrade_name(item)
	else:
		_message.text = "ポイントが足りない（%d ポイント要る）" % cost
	_fill_workshop()


## 塗装のボタンを押した: 使える塗装なら選ぶ。使えなければ解放の段を出す
func _choose_paint(p: int) -> void:
	var id: String = workshop_id()
	if p < Progression.paints_unlocked(GameState.garage(id)["level"]):
		GameState.set_paint(id, p)
		_message.text = ""
	else:
		_message.text = "塗装「%s」は熟練 %d段で解放" % [Trolley.paint_name(id, p), Tuning.PAINT_UNLOCK_LEVELS[p]]
	_fill_workshop()


func _open_confirm() -> void:
	_reset.hide()
	_confirm.show()
	UiButton.focus_quietly(_reset_no)


func _close_confirm() -> void:
	_confirm.hide()
	_reset.show()
	UiButton.focus_quietly(_reset)


func _reset_upgrades() -> void:
	GameState.reset_upgrades(workshop_id())
	_message.text = ""
	_close_confirm()
	_fill_workshop()


## 塗装のボタンの車両の絵（その塗装で）
func _draw_swatch(art: Control, p: int) -> void:
	var k: float = Tuning.GARAGE_WS_SWATCH_SCALE
	var rail_y: float = Tuning.GARAGE_WS_SWATCH_RAIL_Y
	art.draw_line(Vector2(0.0, rail_y), Vector2(art.size.x, rail_y), Palette.STEEL, Tuning.RAIL_WIDTH * k)
	art.draw_set_transform(Vector2(art.size.x * 0.5, rail_y), 0.0, Vector2.ONE * k)
	Trolley.draw_body(art, workshop_id(), p)
	art.draw_set_transform(Vector2.ZERO)


## 設定画面と同じ生成りのパネル: 墨の枠、上端にストライプ、ずらしの影（16.4）
func _draw_ws_panel() -> void:
	var r := Rect2(Vector2.ZERO, _ws_panel.size)
	var b: float = Tuning.UI_PANEL_BORDER
	_ws_panel.draw_rect(Rect2(Tuning.UI_PANEL_SHADOW, r.size), Palette.SHADOW)
	_ws_panel.draw_rect(r, Palette.PAPER)
	DrawUtil.tile_noise(_ws_panel, r, "grain", Tuning.PAPER_GRAIN_ALPHA)
	DrawUtil.stripes(_ws_panel, Rect2(b, b, r.size.x - b * 2.0, Tuning.UI_PANEL_BAND_H), Tuning.UI_PANEL_STRIPE_W)
	_ws_panel.draw_rect(r.grow(-b * 0.5), Palette.INK, false, b)
