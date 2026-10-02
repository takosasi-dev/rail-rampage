extends Control
## ステージ選択（17.3、FR-41, FR-41a）。カードを横一列に並べ、下の詳細パネルに選んでいるステージを出す。
## 「試験開始」でゲーム画面へ、「戻る」か Esc でタイトルへ。
## TODO(spec): 17.3 はカード5枚。10ステージは SELECT_PAGE_SIZE 枚ずつのページに分け、選んでいるカードのページだけ見せる
##             （カードの見た目と位置は変えない）。ヘッダーのタブで今のページを示し、タブのクリックでそのページの最初の試験を選ぶ。
##             ←→ はページをまたいで選ぶ。ページの最初の試験が未解放なら、そのタブは押せない
##             （docs/superpowers/specs/2026-09-26-more-stages-design.md。依頼者の不在中に決めた。試遊の後に見直す）
## TODO(spec): FR-47a は ↑↓←→ をフォーカス移動とするが、この画面の ←→ はカードの選択にした（未解放は飛ばす）。
##             ←→ はどちらのボタンにフォーカスがあってもカードを動かし、フォーカスは動かさない。
##             ↑↓ は「試験開始」と「戻る」の間のフォーカス移動
## TODO(spec): マウスで選んでいるカードをもう一度クリックすると試験を始める（デザイン案の「SPACE / クリック 開始」。
##             ダブルクリックも「選ぶ → 始める」の順で始まる）。選んでいないカードのクリックは選ぶだけ
## 車両（trolleys-and-display-design.md 3章）: 詳細パネルの右の列の上に今の車両の絵・名前と「車両を選ぶ」を置き、
## 押すと車庫（garage.tscn）をこの上に重ねて開く（閉じるのはこの画面）。カード・詳細パネル・ヘッダーの★と最高スコア・
## 「済」の判子・★2・★3 の閾値は、選んでいる車両（GameState.trolley()）の記録と値
## TODO(spec): 「車両を選ぶ」は「試験開始」の上（↑ で届く）。車庫を閉じたら（決めても戻っても）「試験開始」にフォーカスを戻す

const UiButton := preload("res://scenes/ui/ui_button.gd")
const Result := preload("res://scenes/result.gd")  # 課題の丸印（draw_challenge_mark）
const GAME_SCENE: String = "res://scenes/game.tscn"
const TITLE_SCENE: String = "res://scenes/title.tscn"
const GARAGE_SCENE: String = "res://scenes/garage.tscn"
const STAR: String = "★"
const NO_RECORD: String = "記録なし"
## 8.1 の新要素（ステージ番号順）: [アイコン, 名前, 1行説明]。アイコンは Target.draw_shape の種類か "wall"・"jump"。
## 第6〜10試験は新要素が無いので、主役にする要素を「応用」として示す
## TODO(spec): 新要素の1行説明は仕様に無い。第3試験はデザイン案の文、ほかは 8.1 の「新要素」「狙い」から書いた。
##             第6〜10試験の分は more-stages-design.md の狙いから書いた
const NEW_ELEMENTS: Array = [
	["crate", "分岐・木箱", "Space かクリックで分岐を切り替え、標的の多い線路を選ぶ。"],
	["dummy", "ダミー人形・樽・勢い", "壊すほど勢いが溜まり、トロッコが速くなる。"],
	["wall", "レンガ壁", "必要速度に届いていれば突破、届かなければ激突。"],
	["drum", "爆発ドラム缶", "ぶつけると爆発し、周りの標的も巻き込む。"],
	["jump", "ジャンプ台", "必要速度に届いていれば飛び越え、届かなければ脱線。"],
	["drum", "ドラム缶と壁", "爆発に巻き込まれた壁は、速度が足りなくても崩れる。"],
	["jump", "ジャンプ台の連続", "着地の先にまた踏切台。跳ぶ前に勢いを溜め直す。"],
	["wall", "最高速の壁", "標的の多い道で勢いを溜め、最高速近くで壁を破る。"],
	["crate", "分岐の連続", "分岐が間を置かずに続く。一目で標的の多い道を選ぶ。"],
	["dummy", "全要素の総合", "壁・爆発・ジャンプを越えて、最高得点を狙う。"],
	# 裏試験1〜5（replay-value-design.md 4章。新要素は無く、本試験の要素の組み合わせ）
	# TODO(spec): 裏試験の要素の名前と1行説明は設計書に無い。各ステージの狙いから書いた
	["drum", "爆破と勢いの壁", "爆破で崩す壁と、勢いで破る壁が交互に4つ。"],
	["jump", "跳躍と壁", "ジャンプと壁が交互に5つ。勢いを落とさずに越える。"],
	["crate", "迷路の中の壁", "間を置かない分岐の中に壁。一目で道と速さを読む。"],
	["wall", "最高速の迷路", "最高速のまま壁が続く迷路と、最後の大ジャンプ。"],
	["dummy", "最終検定", "爆破・ジャンプ・迷路・壁のすべてを7つの分岐で。"]]
## ページ（SELECT_PAGE_SIZE 枚ずつ）: [タブの名前, 詳細パネルの要素の見出し]
const PAGES: Array = [["基礎課程", "新要素"], ["応用課程", "応用"], ["裏課程", "組合せ"]]
## 裏試験の解放の条件（「★10で解放」。カードと裏課程のタブ）
const EX_LOCK_TEXT: String = "%s%dで解放"
const EX_LOCK_NOW: String = "（今 %d）"  # 裏試験のカードの錠前の文に添える、全車両をまとめた★の合計
## TODO(spec): ステージファイルが無い・読めないときのカードは仕様に無い。名前を「データなし」、★の閾値を「―」にする。
##             試験は始められる（ゲーム画面が「ステージデータエラー」を出してここに戻る、6.4）
const NO_DATA_NAME: String = "データなし"
const NO_VALUE: String = "―"

## 選んでいるステージの番号（1〜STAGE_COUNT が本試験、EX_FIRST〜が裏試験）
var selected: int = 1

var _stages: Array[Dictionary] = []  # ステージ番号 - 1 → ステージ JSON（読めなければ空）
var _cards: Array[Control] = []
var _tabs: Array[Control] = []  # ページ番号（0 から）→ タブ
var _garage: Control = null  # 開いている車庫
var _detail_done: Array[bool] = []  # 詳細パネルの試験の課題の達成（丸印を描く）

@onready var _header: Control = $Header
@onready var _detail: Control = $Detail
@onready var _start: UiButton = %Start
@onready var _back: UiButton = %Back
@onready var _garage_button: UiButton = %Garage


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # 紙の粒（設計書5章）
	_style()  # 1枚目のカードに文字の書体を付けてから複製する
	var row: Control = $Cards
	var template: Control = row.get_child(0)
	for _i: int in _last() - 1:
		row.add_child(template.duplicate())
	for n: int in range(1, _last() + 1):
		var card: Control = row.get_child(n - 1)
		_cards.append(card)
		_stages.append(StageLoader.load_json(GameState.stage_path(n)))
		card.draw.connect(_draw_card.bind(n))
		card.get_node("Stamp").draw.connect(_draw_stamp.bind(n))
		var icon: Control = card.get_node("Body/IconBox/Icon")
		icon.draw.connect(_draw_icon.bind(n))
		if NEW_ELEMENTS[n - 1][0] == "jump":  # 踏切台はゲーム画面と同じノードを、レール（_draw_icon）の上面に置く
			var place: Array = Tuning.SELECT_ICON_PLACE["jump"]
			var ramp: Node2D = StageLoader._ramp(Vector2.ZERO)
			ramp.position = place[0] + Vector2(0.0, -Tuning.RAIL_WIDTH * 0.5 * place[1])
			ramp.scale = Vector2.ONE * place[1]
			icon.add_child(ramp)
		card.gui_input.connect(_on_card_input.bind(n))
	var tab_row: Control = $Header/Pages
	for _i: int in _page_count() - 1:
		tab_row.add_child(tab_row.get_child(0).duplicate())
	for p: int in _page_count():
		var tab: Control = tab_row.get_child(p)
		_tabs.append(tab)
		var first: int = p * Tuning.SELECT_PAGE_SIZE + 1
		var base: int = 0 if first <= Tuning.STAGE_COUNT else Tuning.STAGE_COUNT  # 裏課程は「裏課程 1〜5」
		(tab.get_node("Text") as Label).text = "%s %d〜%d" % [PAGES[p][0], first - base,
				mini(first + Tuning.SELECT_PAGE_SIZE - 1, Tuning.STAGE_COUNT if base == 0 else _last()) - base]
		tab.draw.connect(_draw_tab.bind(p))
		tab.gui_input.connect(_on_tab_input.bind(p))
	_detail.draw.connect(_draw_detail)
	(%TrolleyIcon as Control).draw.connect(_draw_trolley_icon)
	_start.pressed.connect(_start_stage)
	_back.pressed.connect(_to_title)
	_garage_button.pressed.connect(open_garage)
	# TODO(spec): 開いたときに選ぶカードは仕様に無い。前に遊んだステージ（GameState.current_stage）が解放済みならそれ、
	#             でなければ第1試験
	var n: int = GameState.current_stage
	selected = n if n >= 1 and n <= _last() and GameState.is_unlocked(n) else 1
	_refresh()
	UiButton.focus_quietly(_start)  # FR-47a: 開いた時点で主ボタンにフォーカス


## ←→ でカードを選ぶ（未解放は飛ばす）。フォーカス中のボタンに渡るとフォーカスが動くので、GUI より先に受け取る
func _input(event: InputEvent) -> void:
	if _garage != null:  # 車庫の ←→ は車庫が受ける
		return
	var step: int = 0
	if event.is_action_pressed("ui_left", true):
		step = -1
	elif event.is_action_pressed("ui_right", true):
		step = 1
	else:
		return
	get_viewport().set_input_as_handled()
	var n: int = selected + step
	while n >= 1 and n <= _last() and not GameState.is_unlocked(n):
		n += step
	if n >= 1 and n <= _last():
		_select(n)


func _unhandled_input(event: InputEvent) -> void:
	if _garage == null and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.play(&"ui_select")
		_to_title()


## 車庫をこの上に重ねて開く。開いている間はこの画面のボタンにフォーカスが行かないようにする
func open_garage() -> Control:
	_garage = (load(GARAGE_SCENE) as PackedScene).instantiate()
	_garage.closed.connect(_on_garage_closed.bind(_garage))
	get_viewport().gui_release_focus()  # 「車両を選ぶ」にフォーカスが残ると、Enter でもう1つ開いてしまう
	_set_focusable(false)
	add_child(_garage)
	return _garage


## 車庫を閉じた: 車両を替えていれば、カード・詳細パネル・ヘッダーをその車両の記録にする
func _on_garage_closed(g: Control) -> void:
	g.queue_free()
	if g != _garage:
		return
	_garage = null
	_set_focusable(true)
	_refresh()
	UiButton.focus_quietly(_start)


func _set_focusable(on: bool) -> void:
	for c: Control in [_detail, _back]:
		c.focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED if on else FOCUS_BEHAVIOR_DISABLED


## カードのクリック: 選んでいなければ選ぶ、選んでいれば始める。未解放は選べない（FR-41）
func _on_card_input(event: InputEvent, n: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if n == selected:
		_start.pressed.emit()  # 「試験開始」を押したのと同じ（ui_select も鳴る）
	elif GameState.is_unlocked(n):
		_select(n)
		UiButton.focus_quietly(_start)  # 続けて Space で始められるように


## タブのクリック: 別のページなら、そのページの最初の試験を選ぶ。最初の試験が未解放のページは選べない
func _on_tab_input(event: InputEvent, p: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if p != _page(selected) and _page_unlocked(p):
		_select(p * Tuning.SELECT_PAGE_SIZE + 1)
		UiButton.focus_quietly(_start)


func _select(n: int) -> void:
	if n == selected:
		return
	selected = n
	Audio.play(&"ui_move")
	_refresh()


func _start_stage() -> void:
	GameState.current_stage = selected
	get_tree().change_scene_to_file(GAME_SCENE)


func _to_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


## 記録と選択からヘッダー・カード・詳細パネルを作り直す（★・最高スコアは選んでいる車両の記録）
func _refresh() -> void:
	var trolley: String = GameState.trolley()
	%Total.text = "%d / %d" % [GameState.total_stars(trolley), Tuning.STAGE_COUNT * Tuning.STARS_MAX]
	%TrolleyName.text = Trolleys.name_of(trolley)
	(%TrolleyIcon as Control).queue_redraw()
	var page: int = _page(selected)
	for n: int in range(1, _last() + 1):
		_cards[n - 1].visible = _page(n) == page
		_fill_card(n)
	for p: int in _tabs.size():
		_fill_tab(p)
	var rec: Dictionary = GameState.record(selected, trolley)
	var element: Array = NEW_ELEMENTS[selected - 1]
	%DetailNum.text = _number_text(selected)
	%DetailName.text = _stage_name(selected)
	%ElementLabel.text = PAGES[page][1]
	%Element.text = element[1]
	%Explain.text = element[2]
	# TODO(spec): 未クリアのときの詳細パネルの最高スコアは仕様に無い。カードと同じ「記録なし」
	%BestValue.text = Display.score_text(rec["best_score"]) if rec["cleared"] else NO_RECORD
	%Star2Value.text = _threshold(selected, 0)
	%Star3Value.text = _threshold(selected, 1)
	var tod: String = _tod(selected)
	%TimeValue.text = "%s（%s）" % [TimeOfDay.CLOCKS[tod], TimeOfDay.LABELS[tod]]  # 設計書5章
	_fill_detail_challenges(selected)


## FR-41: 解放済みは試験番号・名前・アイコン・★・最高スコア、未解放は「？？？」・錠前・「第N試験の合格で解放」
func _fill_card(n: int) -> void:
	var card: Control = _cards[n - 1]
	var unlocked: bool = GameState.is_unlocked(n)
	var rec: Dictionary = GameState.record(n, GameState.trolley())
	var body: Control = card.get_node("Body")
	(body.get_node("Num") as Label).text = "%s・%s" % [_number_text(n), TimeOfDay.CLOCKS[_tod(n)]]  # 設計書5章: 試験時刻
	var name_label: Label = body.get_node("Name")
	name_label.text = _stage_name(n) if unlocked else "？？？"
	name_label.add_theme_color_override("font_color", Palette.INK if unlocked else Palette.MUTED)
	(body.get_node("Stars/Got") as Label).text = STAR.repeat(rec["stars"])
	(body.get_node("Stars/Rest") as Label).text = STAR.repeat(Tuning.STARS_MAX - rec["stars"])
	var best: Label = body.get_node("Best")
	best.text = "最高 " + Display.score_text(rec["best_score"]) if rec["cleared"] else NO_RECORD
	best.add_theme_color_override("font_color", Palette.INK if rec["cleared"] else Palette.MUTED)
	(body.get_node("LockHint") as Label).text = _lock_hint(n)
	for path: String in ["Stars", "Best"]:
		(body.get_node(path) as Control).visible = unlocked
	for path: String in ["Locked", "LockHint"]:
		(body.get_node(path) as Control).visible = not unlocked
	var icon: Control = body.get_node("IconBox/Icon")
	for c: Node in icon.get_children():  # 踏切台
		(c as CanvasItem).visible = unlocked
	card.mouse_default_cursor_shape = CURSOR_POINTING_HAND if unlocked else CURSOR_ARROW
	card.queue_redraw()
	icon.queue_redraw()
	(card.get_node("Stamp") as Control).queue_redraw()
	_fill_card_challenges(n)


## replay-value-design.md 3章: カードの★の行に、金★（取っていれば★3 の右に金色の★）と課題の達成数（「課題 2/3」）。
## 金★は選んでいる車両の記録、課題は車両をまとめた記録
## TODO(spec): カードの金★と課題の数の出し方は仕様に無い。★の行の右端に「課題 N/3」を置いた
func _fill_card_challenges(n: int) -> void:
	var stars: Control = _cards[n - 1].get_node("Body/Stars")
	var gold: Label = stars.get_node("Gold")
	var tasks: Label = stars.get_node("Tasks")
	UiButton.style_label(gold, (stars.get_node("Got") as Label).get_theme_font(&"font"), Tuning.SELECT_STARS_FONT_SIZE,
			Palette.GOLD_STAR)
	var list: Array = _challenge_list(n)
	var done: int = GameState.challenges(n).count(true)
	UiButton.style_label(tasks, Fonts.BIZ, Tuning.SELECT_TASKS_FONT_SIZE, Palette.INK if done == list.size() else Palette.MUTED)
	gold.visible = GameState.record(n, GameState.trolley())["gold"]
	tasks.visible = not list.is_empty()
	tasks.text = "課題 %d/%d" % [done, list.size()]


## replay-value-design.md 3章: 詳細パネルの金★の閾値（選んでいる車両の値）と、課題3つの文と達成の丸印
func _fill_detail_challenges(n: int) -> void:
	UiButton.style_label(%GoldLabel, Fonts.courier, Tuning.SELECT_DETAIL_TEXT_FONT_SIZE, Palette.GOLD_STAR)
	UiButton.style_label(%GoldValue, Fonts.courier_bold, Tuning.SELECT_DETAIL_TEXT_FONT_SIZE, Palette.PAPER)
	var t: Variant = _stages[n - 1].get("gold_threshold")
	%GoldValue.text = Display.score_text(Trolleys.thresholds(GameState.trolley(), [t])[0]) \
			if (t is int or t is float) and t > 0 else NO_VALUE
	var box: VBoxContainer = %Challenges
	box.add_theme_constant_override(&"separation", Tuning.SELECT_CHALLENGE_LINE_GAP)
	var m: float = Tuning.SELECT_CHALLENGE_MARK
	while box.get_child_count() < Tuning.CHALLENGE_COUNT:
		var i: int = box.get_child_count()
		var l := Label.new()
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = m + Tuning.RESULT_CHALLENGE_MARK_GAP
		l.add_theme_stylebox_override(&"normal", sb)
		var mark := Control.new()
		mark.mouse_filter = MOUSE_FILTER_IGNORE
		mark.anchor_top = 0.5
		mark.anchor_bottom = 0.5
		mark.offset_right = m
		mark.offset_top = -m * 0.5
		mark.offset_bottom = m * 0.5
		mark.draw.connect(func() -> void:
			Result.draw_challenge_mark(mark, Rect2(Vector2.ZERO, Vector2.ONE * m), i < _detail_done.size() and _detail_done[i],
					Palette.MUTED_ON_INK))
		l.add_child(mark)
		box.add_child(l)
	var list: Array = _challenge_list(n)
	_detail_done = GameState.challenges(n)
	box.visible = not list.is_empty()
	for i: int in box.get_child_count():
		var l: Label = box.get_child(i)
		l.visible = i < list.size()
		if l.visible:
			l.text = Challenges.describe(list[i])
			UiButton.style_label(l, Fonts.BIZ, Tuning.SELECT_CHALLENGE_FONT_SIZE, Palette.PAPER if _detail_done[i] else Palette.MUTED_ON_INK)
		(l.get_child(0) as Control).queue_redraw()


## 試験 n の課題（ステージ JSON の "challenges"。無い・読めなければ空）
func _challenge_list(n: int) -> Array:
	var list: Variant = _stages[n - 1].get("challenges")
	return list if list is Array else []


## タブの文字の色と、押せるときの指の形（地と枠は _draw_tab）
func _fill_tab(p: int) -> void:
	var tab: Control = _tabs[p]
	var current: bool = p == _page(selected)
	var color: Color = Palette.INK if current else (Palette.PAPER if _page_unlocked(p) else Palette.MUTED_ON_INK)
	(tab.get_node("Text") as Label).add_theme_color_override("font_color", color)
	_fill_ex_tab(p)
	tab.mouse_default_cursor_shape = CURSOR_POINTING_HAND if not current and _page_unlocked(p) else CURSOR_ARROW
	tab.queue_redraw()


## 第 n 試験のページ（0 から）
func _page(n: int) -> int:
	return floori((n - 1) / float(Tuning.SELECT_PAGE_SIZE))


func _page_count() -> int:
	return ceili(_last() / float(Tuning.SELECT_PAGE_SIZE))


## カードの最後の番号（裏試験の最後。本試験の後ろに続く）
func _last() -> int:
	return Tuning.EX_FIRST + Tuning.EX_COUNT - 1


## 未解放のカードの解放の条件。本試験は前の試験の合格、裏試験は本試験の★の合計（replay-value-design.md 4章）
func _lock_hint(n: int) -> String:
	if n >= Tuning.EX_FIRST:
		# 解放は全車両をまとめた★で決まる（ヘッダーは選んでいる車両の★）ので、今のまとめた★も添える
		return EX_LOCK_TEXT % [STAR, GameState.ex_unlock_stars(n)] + (EX_LOCK_NOW % GameState.total_stars() if n > Tuning.EX_FIRST else "")
	return "%sの合格で解放" % _number_text(n - 1)


## 裏課程のタブ: 解放前（最初の裏試験の★に届かない）は錠前と「★10で解放」、解放後は「裏課程 1〜5」。
## 錠前は文字の左に置く子（Lock）で、最初に呼ばれたときに作る
func _fill_ex_tab(p: int) -> void:
	var first: int = p * Tuning.SELECT_PAGE_SIZE + 1
	if first < Tuning.EX_FIRST:
		return
	var tab: Control = _tabs[p]
	var label: Label = tab.get_node("Text")
	var lock: Control = tab.get_node_or_null("Lock")
	if lock == null:
		label.set_meta(&"open_text", label.text)
		lock = Control.new()
		lock.name = "Lock"
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.draw.connect(func() -> void: draw_lock(lock))
		tab.add_child(lock)
		tab.resized.connect(_fill_ex_tab.bind(p))  # 開いた直後はタブの大きさがまだ決まっていない
	var locked: bool = not _page_unlocked(p)
	label.text = _lock_hint(first) if locked else str(label.get_meta(&"open_text"))
	lock.visible = locked
	if locked:  # 錠前と文字をまとめてタブの中央に
		var side: float = tab.size.y * Tuning.EX_TAB_LOCK
		var text_w: float = label.get_theme_font(&"font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				label.get_theme_font_size(&"font_size")).x
		lock.size = Vector2(side, side)
		lock.position = Vector2((tab.size.x - side - Tuning.EX_TAB_LOCK_GAP - text_w) * 0.5, (tab.size.y - side) * 0.5)
		label.offset_left = side + Tuning.EX_TAB_LOCK_GAP
	else:
		label.offset_left = 0.0
	lock.queue_redraw()


## ページの最初の試験が解放済みか（解放は番号順なので、1つでも解放済みなら最初も解放済み）
func _page_unlocked(p: int) -> bool:
	return GameState.is_unlocked(p * Tuning.SELECT_PAGE_SIZE + 1)


## 第 n 試験を遊ぶときの時間帯（設定の A／C に従う）
func _tod(n: int) -> String:
	return GameState.time_of_day(n, _stages[n - 1])


func _number_text(n: int) -> String:
	return Display.stage_title(n)


func _stage_name(n: int) -> String:
	return str(_stages[n - 1].get("name", NO_DATA_NAME))


## ★2（i = 0）・★3（i = 1）の閾値（ステージ JSON の star_thresholds を、選んでいる車両の値にしたもの）
func _threshold(n: int, i: int) -> String:
	var t: Variant = _stages[n - 1].get("star_thresholds")
	if t is Array and t.size() == Tuning.STARS_MAX - 1 and (t[i] is float or t[i] is int):
		return Display.score_text(Trolleys.thresholds(GameState.trolley(), t)[i])
	return NO_VALUE


func _style() -> void:
	var heading: Label = %Heading
	UiButton.style_label(heading, Fonts.DELA, Tuning.SELECT_HEAD_FONT_SIZE, Palette.PAPER)
	UiButton.style_label(%Sub, UiButton.spaced(Fonts.courier), Tuning.SELECT_SUB_FONT_SIZE, Palette.HAZARD)
	_align_baseline(%Sub, heading)
	UiButton.style_label(%TotalStar, Fonts.DELA, Tuning.SELECT_TOTAL_STAR_FONT_SIZE, Palette.HAZARD)
	UiButton.style_label(%Total, Fonts.DELA, Tuning.SELECT_TOTAL_FONT_SIZE, Palette.PAPER)
	UiButton.style_label($Header/Pages/Page/Text, Fonts.DELA, Tuning.SELECT_TAB_FONT_SIZE, Palette.PAPER)  # 複製する前に

	var body: Control = $Cards/Card/Body
	UiButton.style_label(body.get_node("Num"), Fonts.courier, Tuning.SELECT_NUM_FONT_SIZE, Palette.MUTED)
	UiButton.style_label(body.get_node("Name"), Fonts.DELA, Tuning.SELECT_NAME_FONT_SIZE, Palette.INK)
	var stars_font: Font = UiButton.spaced(Fonts.BIZ)
	UiButton.style_label(body.get_node("Stars/Got"), stars_font, Tuning.SELECT_STARS_FONT_SIZE, Palette.INK)
	UiButton.style_label(body.get_node("Stars/Rest"), stars_font, Tuning.SELECT_STARS_FONT_SIZE, Palette.GRID_MAJOR)
	UiButton.style_label(body.get_node("Best"), Fonts.courier, Tuning.SELECT_BEST_FONT_SIZE, Palette.INK)
	UiButton.style_label(body.get_node("Locked"), Fonts.DELA, Tuning.SELECT_LOCKED_FONT_SIZE, Palette.MUTED)
	UiButton.style_label(body.get_node("LockHint"), Fonts.BIZ, Tuning.SELECT_LOCK_HINT_FONT_SIZE, Palette.MUTED)

	var detail_name: Label = %DetailName
	UiButton.style_label(%DetailNum, Fonts.courier, Tuning.SELECT_DETAIL_NUM_FONT_SIZE, Palette.HAZARD)
	UiButton.style_label(detail_name, Fonts.DELA, Tuning.SELECT_DETAIL_NAME_FONT_SIZE, Palette.PAPER)
	_align_baseline(%DetailNum, detail_name)
	var fs: int = Tuning.SELECT_DETAIL_TEXT_FONT_SIZE
	UiButton.style_label(%ElementLabel, Fonts.BIZ, fs, Palette.PAPER)
	UiButton.style_label(%Element, Fonts.BIZ_BOLD, fs, Palette.HAZARD)
	UiButton.style_label(%Explain, Fonts.BIZ, fs, Palette.PAPER)
	for l: Label in [%BestLabel, %Star2Label, %Star3Label, %TimeLabel]:
		UiButton.style_label(l, Fonts.courier, fs, Palette.MUTED_ON_INK)
	for l: Label in [%BestValue, %Star2Value, %Star3Value, %TimeValue]:
		UiButton.style_label(l, Fonts.courier_bold, fs, Palette.PAPER)
	UiButton.style_label(%Help, Fonts.courier, Tuning.SELECT_HELP_FONT_SIZE, Palette.MUTED)
	UiButton.style_label(%TrolleyName, Fonts.DELA, Tuning.SELECT_TROLLEY_NAME_FONT_SIZE, Palette.PAPER)
	_start.alignment = HORIZONTAL_ALIGNMENT_CENTER  # デザイン案は文字とキー表示を中央に寄せる


## 同じ行の小さい文字のベースラインを大きい文字に揃える（デザイン案の align-items: baseline）。
## 両方とも行の下端に置く（size_flags_vertical = 下寄せ）前提で、小さい方を下の字の深さの差だけ持ち上げる
static func _align_baseline(small: Label, big: Label) -> void:
	var lift := StyleBoxEmpty.new()
	lift.content_margin_bottom = big.get_theme_font(&"font").get_descent(big.get_theme_font_size(&"font_size")) \
			- small.get_theme_font(&"font").get_descent(small.get_theme_font_size(&"font_size"))
	small.add_theme_stylebox_override(&"normal", lift)


func _draw() -> void:
	draw_page(self, _header.get_rect())


## 17.1, 17.3: 生成り地に横罫、上部に墨のヘッダー（header）とストライプ。試験記録の画面も同じ地を使う。
## ci は画面の root（texture_repeat は TEXTURE_REPEAT_ENABLED にしておく）
static func draw_page(ci: Control, header: Rect2) -> void:
	var page := Rect2(Vector2.ZERO, ci.size)
	ci.draw_rect(page, Palette.PAPER)
	DrawUtil.tile_noise(ci, page, "grain", Tuning.PAPER_GRAIN_ALPHA)
	var y: float = Tuning.SELECT_RULE_STEP
	while y < page.size.y:
		ci.draw_rect(Rect2(0.0, y - 1, page.size.x, 1), Palette.PAPER_DARK)
		y += Tuning.SELECT_RULE_STEP
	ci.draw_rect(header, Palette.INK)
	DrawUtil.stripes(ci, Rect2(header.position.x, header.end.y, header.size.x, Tuning.SELECT_BAND_H),
			Tuning.SELECT_STRIPE_W)


## カードの地と枠（17.3）。未解放は LOCKED の破線、選択中は白地・墨4px枠・警告黄4px外枠・8pxずらしの影
func _draw_card(n: int) -> void:
	var card: Control = _cards[n - 1]
	var r := Rect2(Vector2.ZERO, card.size)
	var b: float = Tuning.SELECT_CARD_BORDER
	if not GameState.is_unlocked(n):
		card.draw_rect(r, Palette.BOARD)
		_draw_dashed_rect(card, r.grow(-b * 0.5), Palette.LOCKED, b)
	elif n == selected:
		# 影の色は仕様に無い。デザイン案の墨
		card.draw_rect(Rect2(Tuning.SELECT_CARD_SHADOW, r.size), Palette.INK)
		card.draw_rect(r, Palette.WHITE)
		UiButton.draw_focus(card, r.grow(-Tuning.UI_FOCUS_W))  # 墨の枠はカードの内側、警告黄はその外
	else:
		card.draw_rect(r, Palette.PAPER_LIGHT)
		card.draw_rect(r.grow(-b * 0.5), Palette.INK, false, b)


## 破線の枠（未解放のカードとタブ）
static func _draw_dashed_rect(ci: CanvasItem, e: Rect2, color: Color, width: float) -> void:
	var corners: Array[Vector2] = [e.position, Vector2(e.end.x, e.position.y), e.end, Vector2(e.position.x, e.end.y)]
	for i: int in corners.size():
		ci.draw_dashed_line(corners[i], corners[(i + 1) % corners.size()], color, width, Tuning.SELECT_LOCKED_DASH)


## ページのタブ（墨のヘッダーの上）。今のページは警告黄の地（主ボタンと同じ色）、ほかは生成りの枠、
## 最初の試験が未解放のページは破線の枠
func _draw_tab(p: int) -> void:
	var tab: Control = _tabs[p]
	var r := Rect2(Vector2.ZERO, tab.size)
	var b: float = Tuning.SELECT_TAB_BORDER
	if p == _page(selected):
		tab.draw_rect(r, Palette.HAZARD)
	elif _page_unlocked(p):
		tab.draw_rect(r.grow(-b * 0.5), Palette.PAPER, false, b)
	else:
		_draw_dashed_rect(tab, r.grow(-b * 0.5), Palette.MUTED_ON_INK, b)


## クリア済みカードの右上に STAMP の丸判子「済」（FR-41, 17.3）。文字より手前に描く
func _draw_stamp(n: int) -> void:
	if not GameState.record(n, GameState.trolley())["cleared"]:
		return
	var stamp: Control = _cards[n - 1].get_node("Stamp")
	var w: float = Tuning.SELECT_STAMP_W
	var fs: int = Tuning.SELECT_STAMP_FONT_SIZE
	var text: String = "済"
	stamp.draw_set_transform(Vector2(stamp.size.x, 0.0) + Tuning.SELECT_STAMP_CENTER, deg_to_rad(_stamp_deg(n)))
	stamp.draw_arc(Vector2.ZERO, Tuning.SELECT_STAMP_R - w * 0.5, 0.0, TAU, Tuning.SELECT_ARC_POINTS, Palette.STAMP, w, true)
	var text_w: float = Fonts.DELA.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var baseline: float = (Fonts.DELA.get_ascent(fs) - Fonts.DELA.get_descent(fs)) * 0.5
	stamp.draw_string(Fonts.DELA, Vector2(-text_w * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.STAMP)
	stamp.draw_set_transform(Vector2.ZERO)


## 「済」の判子の傾き（裏試験は Tuning.EX_STAMP_DEG）
static func _stamp_deg(n: int) -> float:
	return Tuning.SELECT_STAMP_DEG[n - 1] if n <= Tuning.STAGE_COUNT else Tuning.EX_STAMP_DEG[n - Tuning.EX_FIRST]


## 新要素のアイコン（8.1）。標的はゲーム画面と同じ絵を縮めて描く。未解放は錠前
func _draw_icon(n: int) -> void:
	var icon: Control = _cards[n - 1].get_node("Body/IconBox/Icon")
	if not GameState.is_unlocked(n):
		draw_lock(icon)
		return
	var kind: String = NEW_ELEMENTS[n - 1][0]
	match kind:
		"wall":
			draw_wall_icon(icon)
		"jump":  # レールと、飛び出したトロッコ。踏切台は StageLoader._ramp のノード（_ready）
			var place: Array = Tuning.SELECT_ICON_PLACE["jump"]
			icon.draw_line(Vector2(0.0, place[0].y), Vector2(icon.size.x, place[0].y), Palette.STEEL,
					Tuning.RAIL_WIDTH * place[1])
			var trolley: Array = Tuning.SELECT_ICON_PLACE["trolley"]
			icon.draw_set_transform(trolley[0], deg_to_rad(Tuning.SELECT_JUMP_TROLLEY_DEG), Vector2.ONE * trolley[1])
			Trolley.draw_body(icon)
			icon.draw_set_transform(Vector2.ZERO)
		_:
			var place: Array = Tuning.SELECT_ICON_PLACE[kind]
			icon.draw_set_transform(place[0], 0.0, Vector2.ONE * place[1])
			Target.draw_shape(icon, kind)
			icon.draw_set_transform(Vector2.ZERO)


## レンガ壁のアイコン（64×64 の枠）。実寸（32×160）は枠に収まらないので、デザイン案と同じ短い壁を 16.5 の描き方で描く。
## 試験記録の画面も縮めて使う
static func draw_wall_icon(icon: CanvasItem) -> void:
	var r: Rect2 = Tuning.SELECT_WALL_ICON
	var row: float = Tuning.SELECT_WALL_ICON_ROW
	var cx: float = r.get_center().x
	var j: float = Tuning.SELECT_WALL_ICON_JOINT
	icon.draw_rect(r, Palette.BRICK)
	for i: int in int(r.size.y / row):
		var top: float = r.position.y + row * i
		if i > 0:
			icon.draw_line(Vector2(r.position.x, top), Vector2(r.end.x, top), Palette.MORTAR, Tuning.MORTAR_W)
		for x: float in ([cx] if i % 2 == 0 else [cx - j, cx + j]):  # 縦目地は段ごとに互い違い
			icon.draw_line(Vector2(x, top), Vector2(x, top + row), Palette.MORTAR, Tuning.MORTAR_W)
	icon.draw_rect(r, Palette.INK, false, Tuning.OBJECT_OUTLINE)


## 未解放の錠前（デザイン案の 24×24 の図を枠いっぱいに拡大）。車庫の未解放の車両も使う
static func draw_lock(icon: Control) -> void:
	var w: float = Tuning.SELECT_LOCK_LINE_W
	var body: Rect2 = Tuning.SELECT_LOCK_BODY
	var c: Vector2 = Tuning.SELECT_LOCK_SHACKLE_C
	var rad: float = Tuning.SELECT_LOCK_SHACKLE_R
	icon.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * icon.size.x / Tuning.SELECT_LOCK_VIEW)
	icon.draw_rect(body, Palette.MUTED, false, w)
	icon.draw_arc(c, rad, PI, TAU, Tuning.SELECT_ARC_POINTS, Palette.MUTED, w, true)  # つる（上半分の円）
	for x: float in [c.x - rad, c.x + rad]:
		icon.draw_line(Vector2(x, c.y), Vector2(x, body.position.y), Palette.MUTED, w)
	var key: Array = Tuning.SELECT_LOCK_KEYHOLE
	icon.draw_line(key[0], key[1], Palette.MUTED, w)
	icon.draw_set_transform(Vector2.ZERO)


## FR-41a: 詳細パネルは墨地
func _draw_detail() -> void:
	_detail.draw_rect(Rect2(Vector2.ZERO, _detail.size), Palette.INK)


## 詳細パネルの今の車両: 墨地の上のレール（タイトルの挿絵と同じ色）に、ゲーム画面と同じ絵を縮めて
func _draw_trolley_icon() -> void:
	var icon: Control = %TrolleyIcon
	var k: float = Tuning.SELECT_TROLLEY_SCALE
	var rail_y: float = (icon.size.y + Tuning.TROLLEY_H * k) * 0.5
	icon.draw_line(Vector2(0.0, rail_y), Vector2(icon.size.x, rail_y), Palette.RAIL_ON_INK, Tuning.RAIL_WIDTH * k)
	icon.draw_set_transform(Vector2(icon.size.x * 0.5, rail_y), 0.0, Vector2.ONE * k)
	Trolley.draw_body(icon, GameState.trolley(), GameState.garage(GameState.trolley())["paint"])
	icon.draw_set_transform(Vector2.ZERO)
