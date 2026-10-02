extends Control
## タイトル画面（17.2、FR-40）。「試験開始」「試験記録」「設定」「終了」。設定はこの上に重ねて開き、閉じるとここに戻る（FR-47d）。
## 試験記録は設計書 docs/superpowers/specs/2026-09-26-records-design.md の 3.1。
## TODO(spec): タイトルで Esc を押したときの戻り先は無い。何もしない
## TODO(spec): 17.2 のメニューは3つ。「試験記録」を足して縦に4つ並べると下端（y=680）の操作説明に届くので、
##             「設定」と「終了」を横に並べて3段にした（Web 版は「終了」を出さず「設定」が横いっぱい）。依頼者の判断を待たずに決めた

const UiButton := preload("res://scenes/ui/ui_button.gd")
const SETTINGS_SCENE: PackedScene = preload("res://scenes/settings.tscn")
const SELECT_SCENE: String = "res://scenes/stage_select.tscn"
const RECORDS_SCENE: String = "res://scenes/records.tscn"
const GAME_SCENE: String = "res://scenes/game.tscn"

@onready var _art: Control = $Art
@onready var _menu: Control = $Menu
@onready var _start: Button = $Menu/Start
@onready var _records: Button = $Menu/Records
@onready var _settings: Button = $Menu/Row/Settings
@onready var _quit: Button = $Menu/Row/Quit


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # 背景の粒（設計書5章）
	UiButton.style_label($Facility, UiButton.spaced(Fonts.courier), Tuning.TITLE_FACILITY_FONT_SIZE, Palette.HAZARD)
	# TODO(spec): 表示名は15章の未確定事項（デザイン案は旧仮称「トロッコ・カオス」）。プロダクト名を2行に分けて置いた
	UiButton.style_label($NameTop, Fonts.DELA, Tuning.TITLE_NAME_FONT_SIZE, Palette.PAPER)
	UiButton.style_label($NameBottom, Fonts.DELA, Tuning.TITLE_NAME_FONT_SIZE, Palette.HAZARD)
	for l: Label in [$Help, $Version]:
		UiButton.style_label(l, Fonts.courier, Tuning.TITLE_HELP_FONT_SIZE, Palette.MUTED_ON_INK)
	$Version.text = Tuning.GAME_VERSION
	_art.draw.connect(_draw_art)
	_quit.visible = not OS.has_feature("web")  # FR-40: Web版では「終了」を出さない
	_start.pressed.connect(get_tree().change_scene_to_file.bind(SELECT_SCENE))  # 17.3 ステージ選択へ
	_records.pressed.connect(get_tree().change_scene_to_file.bind(RECORDS_SCENE))
	_settings.pressed.connect(open_settings)
	_quit.pressed.connect(get_tree().quit)
	_setup_endless()
	UiButton.focus_quietly(_start)  # FR-47a: 開いた時点で主ボタンにフォーカス


## 無限軌道（replay-value-design.md 7章）: 検定印「基礎課程修了」で解放。それまでは押せず、条件を出す。解放後は最高記録。
## タイトルに戻ったら無限軌道を降りる（ステージ選択から始める試験を無限軌道にしない）
## TODO(spec): 置き場所は仕様に無い。メニューの4段目は下端の操作説明に届くので、挿絵の左上の空き（「試験開始」の右上）に
##             ボタンと小さな文字を置いた。「試験開始」から → で届く。依頼者の判断を待たずに決めた
func _setup_endless() -> void:
	GameState.endless = false
	var open: bool = GameState.stamps().has("basic")
	var button: Button = $Endless/Start
	var note: Label = $Endless/Note
	UiButton.style_label(note, Fonts.BIZ, Tuning.TITLE_ENDLESS_NOTE_FONT_SIZE, Palette.MUTED_ON_INK)
	button.disabled = not open
	button.focus_mode = Control.FOCUS_ALL if open else Control.FOCUS_NONE
	if open:
		var best: Dictionary = GameState.endless_record()
		note.text = "最高記録　%s 点　%s" % [Display.score_text(best["best_score"]), Display.distance_text(best["best_distance"])]
		button.pressed.connect(start_endless)
		_start.focus_neighbor_right = _start.get_path_to(button)
		button.focus_neighbor_left = button.get_path_to(_start)
		button.focus_neighbor_bottom = button.get_path_to(_start)
	else:
		note.text = "検定印「%s」で解放" % Achievements.name_of("basic")


## 無限軌道を始める（ゲーム画面が GameState.endless を読む）
func start_endless() -> void:
	GameState.endless = true
	get_tree().change_scene_to_file(GAME_SCENE)


## 設定をこの上に重ねて開く。開いている間はタイトルのボタンにフォーカスが行かないようにする
func open_settings() -> Control:
	var overlay: Control = SETTINGS_SCENE.instantiate()
	overlay.closed.connect(_on_settings_closed.bind(overlay))
	_menu.focus_behavior_recursive = FOCUS_BEHAVIOR_DISABLED
	$Endless.focus_behavior_recursive = FOCUS_BEHAVIOR_DISABLED
	add_child(overlay)
	return overlay


func _on_settings_closed(overlay: Control) -> void:
	overlay.queue_free()
	_menu.focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED
	$Endless.focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED
	UiButton.focus_quietly(_settings)


func _draw() -> void:
	var band_h: float = Tuning.UI_EDGE_BAND_H
	UiButton.draw_menu_bg(self, Rect2(Vector2.ZERO, size))
	DrawUtil.stripes(self, Rect2(0.0, 0.0, size.x, band_h), Tuning.UI_EDGE_STRIPE_W)
	DrawUtil.stripes(self, Rect2(0.0, size.y - band_h, size.x, band_h), Tuning.UI_EDGE_STRIPE_W)


## 右の挿絵（17.2）: トロッコがダミー人形と木箱を跳ね飛ばす静止画。部品は 16.5 のもの
func _draw_art() -> void:
	# 設計書5章: 挿絵にスポットライト（深夜の見た目とつながる）
	_art.draw_texture_rect(DrawUtil.glow_texture(), Tuning.TITLE_ART_SPOT, false, Color(Palette.LAMP_LIGHT, Tuning.TITLE_ART_SPOT_ALPHA))
	_art.draw_rect(Tuning.TITLE_ART_GROUND, Palette.GROUND_ON_INK)
	var routes: Array = Tuning.TITLE_ART_ROUTES
	for route: Array in routes:
		_sleepers(route)
	for i: int in routes.size():
		var alpha: float = 1.0 if i == 0 else Tuning.TITLE_ART_OTHER_ROUTE_ALPHA
		_art.draw_polyline(PackedVector2Array(routes[i]), Color(Palette.RAIL_ON_INK, alpha), Tuning.RAIL_WIDTH)
	# 分岐（FR-9 のアクティブ分岐の円）
	_art.draw_circle(Tuning.TITLE_ART_JUNCTION, Tuning.JUNCTION_ACTIVE_RADIUS, Palette.HAZARD)
	_art.draw_circle(Tuning.TITLE_ART_JUNCTION, Tuning.JUNCTION_ACTIVE_RADIUS, Palette.INK, false, Tuning.JUNCTION_OUTLINE, true)
	for l: Array in Tuning.TITLE_ART_SPEED_LINES:
		_art.draw_line(l[0], l[1], Color(Palette.PAPER, l[2]), Tuning.TITLE_ART_SPEED_LINE_W)
	_art.draw_set_transform(Tuning.TITLE_ART_TROLLEY)
	Trolley.draw_body(_art)
	_art.draw_set_transform(Vector2.ZERO)
	var impact := PackedVector2Array(Tuning.TITLE_ART_IMPACT)
	_art.draw_colored_polygon(impact, Palette.HAZARD)
	impact.append(impact[0])
	_art.draw_polyline(impact, Palette.INK, Tuning.OBJECT_OUTLINE, true)
	_art.draw_set_transform(Tuning.TITLE_ART_DUMMY_POS, deg_to_rad(Tuning.TITLE_ART_DUMMY_DEG),
			Vector2.ONE * Tuning.TITLE_ART_DUMMY_SCALE)
	Target.draw_shape(_art, "dummy")
	# 木箱は中心で回す（draw_shape の原点は下辺中央）
	var crate: Vector2 = Tuning.TARGET_SIZE["crate"]
	var crate_xf := Transform2D(deg_to_rad(Tuning.TITLE_ART_CRATE_DEG), Vector2.ONE * Tuning.TITLE_ART_CRATE_SIZE / crate.x,
			0.0, Tuning.TITLE_ART_CRATE_POS)
	_art.draw_set_transform_matrix(crate_xf * Transform2D(0.0, Vector2(0.0, crate.y * 0.5)))
	Target.draw_shape(_art, "crate")
	for chip: Array in Tuning.TITLE_ART_CHIPS:
		var r: Rect2 = chip[0]
		_art.draw_set_transform(r.get_center(), deg_to_rad(chip[1]))
		var local := Rect2(-r.size * 0.5, r.size)
		_art.draw_rect(local, Palette.DEBRIS_COLORS[chip[2]])
		_art.draw_rect(local, Palette.INK, false, Tuning.TITLE_ART_CHIP_OUTLINE)
	_art.draw_set_transform(Vector2.ZERO)


## 枕木（16.3: 12px幅の破線、6px描いて18px空ける）をレールの少し下に描く
func _sleepers(route: Array) -> void:
	var drop := Vector2(0.0, Tuning.TITLE_ART_SLEEPER_DROP)
	for i: int in route.size() - 1:
		var from: Vector2 = route[i] + drop
		var to: Vector2 = route[i + 1] + drop
		var dir: Vector2 = from.direction_to(to)
		var length: float = from.distance_to(to)
		var d: float = 0.0
		while d < length:
			_art.draw_line(from + dir * d, from + dir * minf(d + Tuning.TITLE_ART_SLEEPER_ON, length), Palette.SLEEPER,
					Tuning.TITLE_ART_SLEEPER_W)
			d += Tuning.TITLE_ART_SLEEPER_ON + Tuning.TITLE_ART_SLEEPER_OFF
