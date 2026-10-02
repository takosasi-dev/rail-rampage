extends CanvasLayer
## FPS 表示（docs/superpowers/specs/2026-09-26-trolleys-and-display-design.md 4章）。autoload。
## 設定の「FPS 表示」が ON なら、どの画面でも（リリース版でも）左上の隅に今の FPS を小さく出す。
## TODO(spec): 出す場所は設計書に無い。左上の隅（高さ20pxほど）にした。どの画面でもここは飾り（タイトルの縞の帯）か
##             空いている所で、HUD の札（上端から 24px 下）・デバッグ版の右下の表示・各画面のボタンと重ならない。
##             縞や絵の上でも読めるよう、墨の地に生成りの文字にした

var _label: Label


func _ready() -> void:
	layer = Tuning.FPS_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS  # ポーズ中も出す
	_label = Label.new()
	_label.name = "Fps"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override(&"font", Fonts.courier_bold)
	_label.add_theme_font_size_override(&"font_size", Tuning.FPS_FONT_SIZE)
	_label.add_theme_color_override(&"font_color", Palette.PAPER)
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.INK
	box.content_margin_left = Tuning.FPS_PAD.x
	box.content_margin_right = Tuning.FPS_PAD.x
	box.content_margin_top = Tuning.FPS_PAD.y
	box.content_margin_bottom = Tuning.FPS_PAD.y
	_label.add_theme_stylebox_override(&"normal", box)
	add_child(_label)
	_process(0.0)


## 設定は毎フレーム見る（display_changed を待たない。設定の変更も F11 もすぐ映る）
func _process(_delta: float) -> void:
	_label.visible = GameState.show_fps
	if _label.visible:
		_label.text = "%d FPS" % Engine.get_frames_per_second()  # 同じ文字なら Label は描き直さない


## 出している文字（自動確認用。出していなければ ""）
func text() -> String:
	return _label.text if _label.visible else ""
