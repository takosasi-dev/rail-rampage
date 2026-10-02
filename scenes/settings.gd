extends Control
## 設定画面（17.6、FR-47b〜d）。開いた画面（タイトル、M5 からはポーズ）の上に重ねるオーバーレイ。
## 「ゲーム」「画面」の2つのタブ（trolleys-and-display-design.md 4章）。ゲームは音量・揺れ・時間帯・ゴースト・操作・記録、
## 画面は画質・FPS 上限・垂直同期・表示（窓・全画面）・FPS 表示。
## どの値も変えた瞬間に GameState で反映・保存する。「戻る」か Esc で closed を出し、閉じるのは開いた側。
## TODO(spec): 17.6 にタブは無い。見出しの行の右に置いた（パネルを高くしない。タブの行を足すと、確認欄を開いたときに
##             画面の高さ 720 に収まらない）。今のタブは警告黄の地（ステージ選択のページのタブと同じ）
## TODO(spec): タブのキーボードでの切り替えは仕様に無い。タブもボタンにして、↑↓←→ でタブへ移り Space / Enter で
##             切り替える（FR-47a のままの操作。フォーカスが乗っただけでは切り替えない。マウスを乗せるとフォーカスが移るため）
## TODO(spec): 「ゴースト 表示／非表示」（replay-value-design.md 6章）は「時間帯」の下。行が増えても確認欄を開いたパネルが
##             画面の高さ 720 に収まるよう、行の間を 20 → 12px に詰めた（「画面」のタブも同じ間）
## TODO(spec): 開いたときのタブは仕様に無い。いつも「ゲーム」で開く（フォーカスは今までどおり「戻る」）

signal closed

const UiButton := preload("res://scenes/ui/ui_button.gd")
## Web 版で出さない「画面」の行（FPS 上限・垂直同期・表示はブラウザに任せる、設計書4章）
const WEB_HIDDEN_DISPLAY: Array[String] = ["FpsLabel", "FpsRow", "VsyncLabel", "VsyncRow", "WindowLabel", "WindowRow"]
## Web 版で出さない操作の行（F11 の全画面は Windows 版だけ、records-design.md 4章）
const WEB_HIDDEN_KEYS: Array[String] = ["Key4", "Desc4"]

var page: int = 0  ## 開いているタブ（0 = ゲーム、1 = 画面）
## 「画面」の選ぶボタン: [ボタン, GameState の変数（set_<変数> で変える）, 値]
var _display_choices: Array = []

@onready var _panel: Control = $Panel
@onready var _tabs: Array[UiButton] = [%TabGame, %TabDisplay]
@onready var _pages: Array[Control] = [%Grid, %DisplayGrid]
@onready var _grid: GridContainer = %Grid
@onready var _display_grid: GridContainer = %DisplayGrid
@onready var _keys: GridContainer = %Keys
@onready var _volume: HSlider = %Volume
@onready var _volume_value: Label = %VolumeValue
@onready var _shake_on: UiButton = %ShakeOn
@onready var _shake_off: UiButton = %ShakeOff
@onready var _time_sequence: UiButton = %TimeSequence
@onready var _time_stage: UiButton = %TimeStage
@onready var _ghost_on: UiButton = %GhostOn
@onready var _ghost_off: UiButton = %GhostOff
@onready var _erase: UiButton = %Erase
@onready var _confirm: PanelContainer = %Confirm
@onready var _cancel: UiButton = %Cancel
@onready var _erase_yes: UiButton = %EraseYes
@onready var _footer: Control = %Footer
@onready var _back: UiButton = %Back


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # 背景と紙の粒（設計書5章）
	_panel.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_style()
	_volume.max_value = Tuning.SE_VOLUME_MAX
	_volume.step = Tuning.SE_VOLUME_STEP
	_volume.value = GameState.se_volume  # 保存しないように、つなぐ前に入れる
	_volume_value.text = str(GameState.se_volume)
	_volume.value_changed.connect(_on_volume_changed)
	UiButton.setup_focus(_volume)
	_show_shake()
	_shake_on.pressed.connect(_set_shake.bind(true))
	_shake_off.pressed.connect(_set_shake.bind(false))
	_show_time()
	_time_sequence.pressed.connect(_set_time.bind(TimeOfDay.MODE_SEQUENCE))
	_time_stage.pressed.connect(_set_time.bind(TimeOfDay.MODE_STAGE))
	_show_ghost()
	_ghost_on.pressed.connect(_set_ghost.bind(true))
	_ghost_off.pressed.connect(_set_ghost.bind(false))
	_erase.pressed.connect(_open_confirm)
	_cancel.pressed.connect(close_confirm)
	_erase_yes.pressed.connect(_erase_records)
	# 「画面」の行ごとの選択肢（ボタンは左からこの順）
	for row: Array in [[%QualityRow, "quality", Tuning.QUALITY_LEVELS], [%FpsRow, "max_fps", Tuning.FPS_LIMITS],
			[%VsyncRow, "vsync", [true, false]], [%WindowRow, "fullscreen", [false, true]], [%ShowFpsRow, "show_fps", [true, false]]]:
		var buttons: Array[Node] = (row[0] as Node).get_children()
		for i: int in buttons.size():
			_display_choices.append([buttons[i], row[1], row[2][i]])
			(buttons[i] as UiButton).pressed.connect(_set_display.bind(row[1], row[2][i]))
	GameState.display_changed.connect(_show_display)  # F11 で全画面を切り替えたときも表示を合わせる
	_show_display()
	for i: int in _tabs.size():
		_tabs[i].pressed.connect(show_page.bind(i))
	# ページの一番上の行から ↑ でそのページのタブへ（タブは右上に離れていて、自動では見つからない所がある）。
	# タブの外側の ←→ ではどこへも移らない（下の項目へ飛ばない）
	_volume.focus_neighbor_top = _volume.get_path_to(_tabs[0])
	for b: Control in (%QualityRow as Node).get_children():
		b.focus_neighbor_top = b.get_path_to(_tabs[1])
	_tabs[0].focus_neighbor_left = ^"."
	_tabs[_tabs.size() - 1].focus_neighbor_right = ^"."
	show_page(0)
	apply_platform(OS.has_feature("web"))
	_back.pressed.connect(closed.emit)
	_panel.draw.connect(_draw_panel)
	_footer.draw.connect(_draw_footer)
	UiButton.focus_quietly(_back)  # FR-47a: 開いた時点で主ボタンにフォーカス


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	Audio.play(&"ui_select")
	if _confirm.visible:
		close_confirm()  # 10章: 確認中の Esc は確認欄を閉じるだけ（消去しない）
	else:
		closed.emit()  # FR-47d


## タブ p（0 = ゲーム、1 = 画面）を開く。記録の消去の確認欄は閉じる（隠れたまま Esc で閉じることにならないように）
func show_page(p: int) -> void:
	page = p
	if _confirm.visible:
		_confirm.hide()
		_erase.show()
	var first: Control = _volume if p == 0 else %QualityHigh  # タブから ↓ で移る、ページの一番上の項目
	for i: int in _pages.size():
		_pages[i].visible = i == p
		_tabs[i].focus_neighbor_bottom = _tabs[i].get_path_to(first)
		if i == p:
			_tabs[i].paint(Palette.HAZARD, Palette.INK, Tuning.UI_THIN_BORDER, Palette.INK)
		else:
			_tabs[i].paint(null, Palette.INK, Tuning.UI_THIN_BORDER, Palette.INK)


## Web 版（web）では FPS 上限・垂直同期・表示の行と F11 の操作を出さない。
## タブを切り替えてもパネルの高さが変わらない（上下に動かない）よう、ページの高さを高い方にそろえる
## TODO(spec): パネルの高さをそろえるのは仕様に無い。Web 版の「画面」は2行なので下が空くが、タブが動かない方を選んだ
func apply_platform(web: bool) -> void:
	for n: String in WEB_HIDDEN_DISPLAY:
		(_display_grid.get_node(n) as CanvasItem).visible = not web
	for n: String in WEB_HIDDEN_KEYS:
		(_keys.get_node(n) as CanvasItem).visible = not web
	var pages: Control = %Pages
	pages.custom_minimum_size.y = 0.0
	pages.custom_minimum_size.y = maxf(_grid.get_combined_minimum_size().y, _display_grid.get_combined_minimum_size().y)


func _on_volume_changed(value: float) -> void:
	GameState.set_se_volume(int(value))
	_volume_value.text = str(GameState.se_volume)
	# TODO(spec): 音量を変えたときの音は仕様に無い。変えた後の大きさが分かるように ui_move を鳴らす
	Audio.play(&"ui_move")


func _set_shake(on: bool) -> void:
	GameState.set_screen_shake(on)
	_show_shake()


## 選んでいる側を墨地・警告黄の文字、もう片方を生成り地・補助文字にする（デザイン案）
func _show_shake() -> void:
	for b: UiButton in [_shake_on, _shake_off]:
		_paint_choice(b, (b == _shake_on) == GameState.screen_shake)


## 設計書4章: 設定「時間帯」。変えた瞬間に保存する（次に遊ぶ試験から効く）
func _set_time(mode: String) -> void:
	GameState.set_time_of_day_mode(mode)
	_show_time()


func _show_time() -> void:
	for b: UiButton in [_time_sequence, _time_stage]:
		_paint_choice(b, (b == _time_stage) == (GameState.time_of_day_mode == TimeOfDay.MODE_STAGE))


## 設計書6章: 設定「ゴースト」。変えた瞬間に保存する（次に遊ぶ走行から効く）
func _set_ghost(on: bool) -> void:
	GameState.set_show_ghost(on)
	_show_ghost()


func _show_ghost() -> void:
	for b: UiButton in [_ghost_on, _ghost_off]:
		_paint_choice(b, (b == _ghost_on) == GameState.show_ghost)


## 「画面」の値を変える（GameState が保存し、FPS 上限・垂直同期・全画面はその場で効かせ、display_changed を出す）
func _set_display(key: String, value: Variant) -> void:
	GameState.call("set_" + key, value)


## 「画面」の選んでいるボタンを墨地にする（GameState の今の値に合わせる）
func _show_display() -> void:
	for c: Array in _display_choices:
		_paint_choice(c[0], GameState.get(c[1]) == c[2])


## 2つ以上から選ぶボタン: 選んでいる側を墨地・警告黄の文字、ほかを生成り地・補助文字にする（デザイン案）
func _paint_choice(b: UiButton, selected: bool) -> void:
	b.paint(Palette.INK if selected else Palette.PAPER, Palette.INK, Tuning.UI_THIN_BORDER,
			Palette.HAZARD if selected else Palette.MUTED)


## FR-47c: 「記録を消去する…」と同じ位置に確認欄を出す。初期フォーカスは「やめる」
func _open_confirm() -> void:
	_erase.hide()
	_confirm.show()
	UiButton.focus_quietly(_cancel)


func close_confirm() -> void:
	_confirm.hide()
	_erase.show()
	UiButton.focus_quietly(_erase)


## FR-47c: 記録（save.cfg）だけを初期状態にする。設定は消さない
func _erase_records() -> void:
	GameState.erase_records()
	# TODO(spec): 消去した後の知らせ（「消去しました」など）は仕様に無い。確認欄を閉じるだけにした
	close_confirm()


func _style() -> void:
	var t := Theme.new()  # 生成り地の上の文字は墨（本文は BIZ UDPGothic、16.2）
	t.set_color(&"font_color", &"Label", Palette.INK)
	t.set_font_size(&"font_size", &"Label", Tuning.SETTINGS_TEXT_FONT_SIZE)
	theme = t
	UiButton.style_label(%Heading, Fonts.DELA, Tuning.SETTINGS_HEAD_FONT_SIZE, Palette.INK)
	var sub: Label = %Sub
	UiButton.style_label(sub, UiButton.spaced(Fonts.courier), Tuning.SETTINGS_SUB_FONT_SIZE, Palette.MUTED)
	var lift := StyleBoxEmpty.new()  # 「SETTINGS」のベースラインを見出しに揃える（デザイン案）
	lift.content_margin_bottom = Fonts.DELA.get_descent(Tuning.SETTINGS_HEAD_FONT_SIZE) \
			- sub.get_theme_font(&"font").get_descent(Tuning.SETTINGS_SUB_FONT_SIZE)
	sub.add_theme_stylebox_override(&"normal", lift)
	for grid: GridContainer in [_grid, _display_grid]:
		for i: int in range(0, grid.get_child_count(), grid.columns):  # 左の列（ラベル列）
			UiButton.style_label(grid.get_child(i), Fonts.BIZ_BOLD, Tuning.SETTINGS_LABEL_FONT_SIZE, Palette.INK)
	for i: int in range(0, _keys.get_child_count(), _keys.columns):  # キーの列
		UiButton.style_label(_keys.get_child(i), Fonts.courier_bold, Tuning.SETTINGS_TEXT_FONT_SIZE, Palette.INK)
	UiButton.style_label(_volume_value, Fonts.courier_bold, Tuning.SETTINGS_VALUE_FONT_SIZE, Palette.INK)
	UiButton.style_label(%ConfirmText, Fonts.BIZ_BOLD, Tuning.SETTINGS_TEXT_FONT_SIZE, Palette.INK)
	UiButton.style_label(%Note, Fonts.courier, Tuning.SETTINGS_NOTE_FONT_SIZE, Palette.MUTED)
	UiButton.style_label(%QualityNote, Fonts.BIZ, Tuning.SETTINGS_QUALITY_NOTE_FONT_SIZE, Palette.MUTED)
	# 画質のラベルは、下に注記がある右の列の上端の行（ボタンの高さ）の中央にそろえる
	(%QualityLabel as Control).custom_minimum_size.y = Tuning.UI_SECONDARY_H

	# TODO(spec): 設定画面の小さいボタン（ON/OFF・記録の消去・確認欄）の寸法は、デザイン案（高さ44〜46px、
	#             文字15〜17px）が 16.2 の Dela Gothic One の下限18pxと 17.1 の副ボタンを下回るので、副ボタンの寸法にした
	for b: UiButton in [_shake_on, _shake_off, _time_sequence, _time_stage, _ghost_on, _ghost_off, %TabGame, %TabDisplay]:
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	for row: Node in [%QualityRow, %FpsRow, %VsyncRow, %WindowRow, %ShowFpsRow]:
		for b: UiButton in row.get_children():
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 16.3: 「記録を消去する…」の文字は STAMP_TEXT、確認欄の地は STAMP_LIGHT
	_erase.paint(Palette.PAPER, Palette.STAMP, Tuning.UI_THIN_BORDER, Palette.STAMP_TEXT)
	_cancel.paint(Palette.PAPER, Palette.INK, Tuning.UI_THIN_BORDER, Palette.INK)
	_erase_yes.paint(Palette.STAMP, Palette.INK, Tuning.UI_THIN_BORDER, Palette.WHITE)
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.STAMP_LIGHT
	box.border_color = Palette.STAMP
	box.set_border_width_all(Tuning.UI_THIN_BORDER)
	box.content_margin_left = Tuning.SETTINGS_CONFIRM_PAD.x
	box.content_margin_right = Tuning.SETTINGS_CONFIRM_PAD.x
	box.content_margin_top = Tuning.SETTINGS_CONFIRM_PAD.y
	box.content_margin_bottom = Tuning.SETTINGS_CONFIRM_PAD.y
	_confirm.add_theme_stylebox_override(&"panel", box)

	# 音量のスライダー: 墨の枠の溝、つまみまでは墨で塗る、つまみは角の無い墨の長方形（16.4）
	var track := StyleBoxFlat.new()
	track.bg_color = Palette.PAPER_DARK
	track.border_color = Palette.INK
	track.set_border_width_all(Tuning.UI_THIN_BORDER)
	track.content_margin_top = Tuning.SETTINGS_TRACK_H * 0.5
	track.content_margin_bottom = Tuning.SETTINGS_TRACK_H * 0.5
	var filled: StyleBoxFlat = track.duplicate()
	filled.bg_color = Palette.INK
	_volume.add_theme_stylebox_override(&"slider", track)
	_volume.add_theme_stylebox_override(&"grabber_area", filled)
	_volume.add_theme_stylebox_override(&"grabber_area_highlight", filled)
	var img := Image.create_empty(Tuning.SETTINGS_GRABBER.x, Tuning.SETTINGS_GRABBER.y, false, Image.FORMAT_RGBA8)
	img.fill(Palette.INK)
	var grabber := ImageTexture.create_from_image(img)
	_volume.add_theme_icon_override(&"grabber", grabber)
	_volume.add_theme_icon_override(&"grabber_highlight", grabber)


func _draw() -> void:
	UiButton.draw_menu_bg(self, Rect2(Vector2.ZERO, size))


## 17.6: 生成りのパネル。墨の枠、上端にストライプ、10pxずらしの影（16.4）
func _draw_panel() -> void:
	var r := Rect2(Vector2.ZERO, _panel.size)
	var b: float = Tuning.UI_PANEL_BORDER
	_panel.draw_rect(Rect2(Tuning.UI_PANEL_SHADOW, r.size), Palette.SHADOW)
	_panel.draw_rect(r, Palette.PAPER)
	DrawUtil.tile_noise(_panel, r, "grain", Tuning.PAPER_GRAIN_ALPHA)
	DrawUtil.stripes(_panel, Rect2(b, b, r.size.x - b * 2.0, Tuning.UI_PANEL_BAND_H), Tuning.UI_PANEL_STRIPE_W)
	_panel.draw_rect(r.grow(-b * 0.5), Palette.INK, false, b)


## 「戻る」の上の破線（デザイン案）
func _draw_footer() -> void:
	var y: float = Tuning.UI_THIN_BORDER * 0.5
	_footer.draw_dashed_line(Vector2(0.0, y), Vector2(_footer.size.x, y), Palette.MUTED_ON_INK, Tuning.UI_THIN_BORDER,
			Tuning.SETTINGS_FOOTER_DASH)
