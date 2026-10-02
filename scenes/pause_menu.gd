extends Control
## ポーズ（FR-44、17.5）。プレイ画面に墨の幕を掛け、中央のパネルに「再開」「リトライ」「設定」「ステージ選択へ」。
## 木が止まっている間も動く（process_mode = ALWAYS）。設定はこの上に重ねて開き、閉じるとここに戻る（FR-47d）。
## どのボタンでどうするかは開いた側（Game）が決める。

signal resume_requested
signal retry_requested
signal select_requested

const UiButton := preload("res://scenes/ui/ui_button.gd")
const SETTINGS_SCENE: PackedScene = preload("res://scenes/settings.tscn")

var _settings_overlay: Control = null

@onready var _panel: Control = $Panel
@onready var _menu: Control = %Menu
@onready var _resume: Button = %Resume
@onready var _retry: Button = %Retry
@onready var _settings: Button = %Settings
@onready var _select: Button = %Select


func _ready() -> void:
	_panel.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # 紙の粒（設計書5章）
	UiButton.style_label(%Heading, Fonts.DELA, Tuning.PAUSE_HEAD_FONT_SIZE, Palette.INK)
	UiButton.style_label(%Sub, UiButton.spaced(Fonts.courier), Tuning.PAUSE_SUB_FONT_SIZE, Palette.MUTED)
	UiButton.style_label(%Help, Fonts.courier, Tuning.PAUSE_HELP_FONT_SIZE, Palette.MUTED)
	_resume.pressed.connect(resume_requested.emit)
	_retry.pressed.connect(retry_requested.emit)
	_settings.pressed.connect(open_settings)
	_select.pressed.connect(select_requested.emit)
	_panel.draw.connect(_draw_panel)
	UiButton.focus_quietly(_resume)  # FR-47a: 開いた時点で主ボタン


func _unhandled_input(event: InputEvent) -> void:
	if _settings_overlay != null:
		return  # 設定が開いている間は設定が受け取る（Esc は設定を閉じる）
	# TODO(spec): ポーズ中の Esc / P は仕様に無い。デザイン案の「再開 Esc」に合わせて再開する
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.play(&"ui_select")
		resume_requested.emit()
	elif event.is_action_pressed("retry"):  # FR-26: ポーズ中の R でもやり直す
		get_viewport().set_input_as_handled()
		retry_requested.emit()


## 設定をこの上に重ねて開く。開いている間はポーズのボタンにフォーカスが行かないようにする
func open_settings() -> Control:
	_settings_overlay = SETTINGS_SCENE.instantiate()
	_settings_overlay.closed.connect(_on_settings_closed)
	_menu.focus_behavior_recursive = FOCUS_BEHAVIOR_DISABLED
	add_child(_settings_overlay)
	return _settings_overlay


func _on_settings_closed() -> void:
	_settings_overlay.queue_free()
	_settings_overlay = null
	_menu.focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED
	UiButton.focus_quietly(_settings)


func is_settings_open() -> bool:
	return _settings_overlay != null


## 17.5: プレイ画面の上に墨 72% の幕
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK, Tuning.PAUSE_VEIL_ALPHA))


## 生成りのパネル。墨の枠、上端にストライプ、10pxずらしの影（16.4、設定画面と同じ）
func _draw_panel() -> void:
	var r := Rect2(Vector2.ZERO, _panel.size)
	var b: float = Tuning.UI_PANEL_BORDER
	_panel.draw_rect(Rect2(Tuning.UI_PANEL_SHADOW, r.size), Palette.SHADOW)
	_panel.draw_rect(r, Palette.PAPER)
	DrawUtil.tile_noise(_panel, r, "grain", Tuning.PAPER_GRAIN_ALPHA)
	DrawUtil.stripes(_panel, Rect2(b, b, r.size.x - b * 2.0, Tuning.UI_PANEL_BAND_H), Tuning.UI_PANEL_STRIPE_W)
	_panel.draw_rect(r.grow(-b * 0.5), Palette.INK, false, b)
