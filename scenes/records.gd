extends Control
## 試験記録（設計書 docs/superpowers/specs/2026-09-26-records-design.md の 3.1）。タイトルの「試験記録」から開く。
## 左に累計の記録（GameState.stats()）、右に検定印30個（8×4。最後の行は6個）と、フォーカスかマウスを乗せた印の説明欄。
## TODO(spec): 検定印が30個になった（replay-value-design.md 8章）。ページを分けず、判子を少し小さくして（半径 42 → 40、
##             名前の字 14 → 13）8列 × 4行に全部並べる。上の2行が今までの16個、下の2行が足した14個（Achievements.LIST の順）
## 「修了証書」は全試験に合格していれば押せ、修了証書をこの上に重ねて開く（閉じるのはこの画面）。「戻る」か Esc でタイトルへ。
## 依頼者の判断を待たずに決めた（配置・文言・大きさは試遊の後に見直す）
## TODO(spec): 開いたときのフォーカスは、修了証書を押せるときは「修了証書」（この画面でただ1つの警告黄のボタン。FR-47a の主ボタン）、
##             押せないときは最初の印（説明欄に最初から中身が出る）
## TODO(spec): ↑↓←→ は印の格子の中を動く。格子の左端の ← は「修了証書」（押せるときだけ）、下端の ↓ は「戻る」。
##             その先に何も無い向きは動かない。「戻る」の ↑ は「修了証書」（押せなければ左下の印）、→ は左下の印。
##             「修了証書」の ↓ は「戻る」、→ は左下の印
## TODO(spec): 印の上での Space / Enter は何もしない（説明はフォーカスで出る）。説明欄は、フォーカスがボタンに移っても
##             最後に出した印のままにする
## TODO(spec): ヘッダーの右端に、取った検定印の数「検定印 N / 30」を出す（ステージ選択の★合計に合わせた）

const UiButton := preload("res://scenes/ui/ui_button.gd")
const StageSelect := preload("res://scenes/stage_select.gd")
const TITLE_SCENE: String = "res://scenes/title.tscn"
const CERTIFICATE_SCENE: String = "res://scenes/certificate.tscn"
const COUNT_FORMAT: String = "%d / %d"
const TIMES_FORMAT: String = "%s 回"
const RESULTS_FORMAT: String = "%s / %s / %s"  # 合格／激突／脱線
const SPEED_FORMAT: String = "%d km/h"
const TOTAL_FORMAT: String = "合計 %s"
const NUMBER_FORMAT: String = "No.%02d"
const GOT_FORMAT: String = "取得日　%s"
const NOT_GOT: String = "未取得"
const LOCKED_MARK: String = "？"
# TODO(spec): 修了証書のボタンの横の文は仕様に無い。押せないときは条件、押せるときは修了日（completed_on）。
#             全試験に合格した後で検定印の記録が始まった保存データは修了日が空なので「―」
const CERT_LOCKED_FORMAT: String = "第1〜%d試験の合格で交付"
const CERT_DONE_FORMAT: String = "修了日　%s"
const NO_VALUE: String = "―"

## 説明欄に出している印（Achievements.LIST の添字）
var shown: int = 0

var _got: Dictionary = {}  # 取った検定印の id → 取った日（GameState.stamps()）
var _cells: Array[Control] = []  # 検定印のマス（Achievements.LIST の順）
var _certificate: Control = null  # 開いている修了証書

@onready var _header: Control = $Header
@onready var _stats: Control = $Stats
@onready var _table: GridContainer = %Table
@onready var _grid: GridContainer = %Stamps
@onready var _detail: Control = $Detail
@onready var _cert: UiButton = %Cert
@onready var _back: UiButton = %Back


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # 紙の粒（ステージ選択と同じ）
	_style()  # 複製するマス・標的の文字の書体は、複製する前に付ける
	_got = GameState.stamps()
	%Count.text = COUNT_FORMAT % [_got.size(), Achievements.LIST.size()]
	_fill_stats()
	_build_stamps()
	var can_open: bool = GameState.all_cleared()
	_cert.disabled = not can_open
	_cert.focus_mode = FOCUS_ALL if can_open else FOCUS_NONE
	if can_open:  # 主ボタンと同じ警告黄（生成り地の上の主ボタンの枠）
		_cert.paint(Palette.HAZARD, Palette.INK, Tuning.UI_PRIMARY_BORDER_ON_PAPER, Palette.INK)
		var done: String = GameState.stats()["completed_on"]
		%CertHint.text = CERT_DONE_FORMAT % (done if done != "" else NO_VALUE)
	else:  # 押せない: 未解放のカードと同じ地と色
		_cert.paint(Palette.BOARD, Palette.LOCKED, Tuning.UI_THIN_BORDER, Palette.MUTED)
		%CertHint.text = CERT_LOCKED_FORMAT % Tuning.STAGE_COUNT
	_link_focus()
	_stats.draw.connect(_draw_stats)
	_table.sort_children.connect(_stats.queue_redraw)  # 行の間の破線は、表が並んだ後の位置で描く
	_detail.draw.connect(_draw_detail)
	_cert.pressed.connect(open_certificate)
	_back.pressed.connect(_to_title)
	_show(0)
	UiButton.focus_quietly(_cert if can_open else _cells[0])


func _unhandled_input(event: InputEvent) -> void:
	if _certificate == null and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.play(&"ui_select")
		_to_title()


## 修了証書をこの上に重ねて開く。開いている間はこの画面のボタンと印にフォーカスが行かないようにする
func open_certificate() -> Control:
	_certificate = (load(CERTIFICATE_SCENE) as PackedScene).instantiate()
	_certificate.closed.connect(_on_certificate_closed.bind(_certificate))
	get_viewport().gui_release_focus()  # 「修了証書」にフォーカスが残ると、Enter でもう1枚開いてしまう
	_set_focusable(false)
	add_child(_certificate)
	return _certificate


func _on_certificate_closed(c: Control) -> void:
	c.queue_free()
	if c != _certificate:
		return
	_certificate = null
	_set_focusable(true)
	UiButton.focus_quietly(_cert)


func _set_focusable(on: bool) -> void:
	for c: Control in [_grid, _cert, _back]:
		c.focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED if on else FOCUS_BEHAVIOR_DISABLED


func _to_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


## 判子に入れる名前の行（取っていない印は「？」）。行の分け方は Tuning.RECORDS_STAMP_TAIL
func stamp_lines(i: int) -> PackedStringArray:
	if not _got.has(Achievements.LIST[i][0]):
		return PackedStringArray([LOCKED_MARK])
	var text: String = Achievements.LIST[i][1]
	var tail: int = Tuning.RECORDS_STAMP_TAIL
	if text.length() <= tail + 1:
		return PackedStringArray([text])
	return PackedStringArray([text.left(-tail), text.right(tail)])


## 累計の表（設計書 3.1）。最高速度は km/h（FR-43）、距離は m／km
func _fill_stats() -> void:
	var s: Dictionary = GameState.stats()
	%Runs.text = TIMES_FORMAT % Display.score_text(s["runs"])
	%Results.text = RESULTS_FORMAT % [Display.score_text(s["clears"]), Display.score_text(s["crashes"]),
			Display.score_text(s["derails"])]
	%Girigiri.text = TIMES_FORMAT % Display.score_text(s["girigiri"])
	%Speed.text = SPEED_FORMAT % Display.to_display_speed(s["best_speed"])
	%Combo.text = Display.score_text(s["best_combo"])
	%Distance.text = Display.distance_text(s["distance"])
	var row: Control = %Targets
	var template: Control = row.get_child(0)
	for _i: int in GameState.SMASH_KINDS.size() - 1:
		row.add_child(template.duplicate())
	var total: int = 0
	for k: int in GameState.SMASH_KINDS.size():
		var kind: String = GameState.SMASH_KINDS[k]
		var box: Control = row.get_child(k)
		var count: int = s["smashed"][kind]
		total += count
		(box.get_node("Count") as Label).text = Display.score_text(count)
		var icon: Control = box.get_node("Icon")
		icon.draw.connect(_draw_target.bind(icon, kind))
	%Smashed.text = TOTAL_FORMAT % Display.score_text(total)


## 検定印のマスを Achievements.LIST の数だけ並べる。フォーカス（キーボード・マウス）で説明欄を変える
func _build_stamps() -> void:
	var template: Control = _grid.get_child(0)
	for _i: int in Achievements.LIST.size() - 1:
		_grid.add_child(template.duplicate())
	for i: int in Achievements.LIST.size():
		var cell: Control = _grid.get_child(i)
		_cells.append(cell)
		cell.draw.connect(_draw_stamp.bind(i))  # フォーカスの枠（setup_focus）より先に描く
		UiButton.setup_focus(cell)
		cell.focus_entered.connect(_show.bind(i))


## フォーカスの行き先（クラスの TODO(spec) の決め方）。行き先の無い向きは自分を指して動かさない
func _link_focus() -> void:
	var cols: int = _grid.columns
	var n: int = _cells.size()
	var corner: Control = _cells[(ceili(n / float(cols)) - 1) * cols]  # 左下の印
	var cert: Control = _cert if _cert.focus_mode != FOCUS_NONE else null
	for i: int in n:
		var c: int = i % cols
		_link(_cells[i], SIDE_LEFT, _cells[i - 1] if c > 0 else cert)
		_link(_cells[i], SIDE_RIGHT, _cells[i + 1] if c < cols - 1 and i + 1 < n else null)
		_link(_cells[i], SIDE_TOP, _cells[i - cols] if i >= cols else null)
		_link(_cells[i], SIDE_BOTTOM, _cells[i + cols] if i + cols < n else _back)
	_link(_back, SIDE_TOP, cert if cert != null else corner)
	_link(_back, SIDE_RIGHT, corner)
	_link(_back, SIDE_LEFT, null)
	_link(_back, SIDE_BOTTOM, null)
	_link(_cert, SIDE_TOP, null)
	_link(_cert, SIDE_LEFT, null)
	_link(_cert, SIDE_RIGHT, corner)
	_link(_cert, SIDE_BOTTOM, _back)


static func _link(from: Control, side: Side, to: Control) -> void:
	from.set_focus_neighbor(side, from.get_path_to(to if to != null else from))


## 説明欄に印 i の名前・条件・取った日（まだなら「未取得」）を出す
func _show(i: int) -> void:
	shown = i
	var id: String = Achievements.LIST[i][0]
	%DetailNum.text = NUMBER_FORMAT % (i + 1)
	%DetailName.text = Achievements.name_of(id)
	%Condition.text = Achievements.describe(id)
	var date: Label = %Date
	date.text = GOT_FORMAT % _got[id] if _got.has(id) else NOT_GOT
	date.add_theme_color_override("font_color", Palette.HAZARD if _got.has(id) else Palette.MUTED_ON_INK)


func _style() -> void:
	var heading: Label = %Heading
	UiButton.style_label(heading, Fonts.DELA, Tuning.SELECT_HEAD_FONT_SIZE, Palette.PAPER)
	UiButton.style_label(%Sub, UiButton.spaced(Fonts.courier), Tuning.SELECT_SUB_FONT_SIZE, Palette.HAZARD)
	StageSelect._align_baseline(%Sub, heading)
	UiButton.style_label(%CountLabel, Fonts.DELA, Tuning.RECORDS_COUNT_LABEL_FONT_SIZE, Palette.HAZARD)
	UiButton.style_label(%Count, Fonts.DELA, Tuning.RECORDS_COUNT_FONT_SIZE, Palette.PAPER)

	for i: int in _table.get_child_count():  # 左の列がラベル、右の列が値。行ごとにベースラインを揃える
		var label: Label = _table.get_child(i)
		if i % _table.columns == 0:
			UiButton.style_label(label, Fonts.BIZ, Tuning.RECORDS_LABEL_FONT_SIZE, Palette.MUTED)
		else:
			UiButton.style_label(label, Fonts.courier_bold, Tuning.RECORDS_VALUE_FONT_SIZE, Palette.INK)
			StageSelect._align_baseline(_table.get_child(i - 1), label)
	UiButton.style_label($Stats/Body/Targets/Target/Count, Fonts.courier_bold, Tuning.RECORDS_TARGET_FONT_SIZE, Palette.INK)

	var detail_name: Label = %DetailName
	UiButton.style_label(%DetailNum, Fonts.courier, Tuning.RECORDS_DETAIL_NUM_FONT_SIZE, Palette.HAZARD)
	UiButton.style_label(detail_name, Fonts.DELA, Tuning.RECORDS_DETAIL_NAME_FONT_SIZE, Palette.PAPER)
	UiButton.style_label(%Date, Fonts.courier_bold, Tuning.RECORDS_DETAIL_TEXT_FONT_SIZE, Palette.HAZARD)
	for l: Label in [%DetailNum, %Date]:
		StageSelect._align_baseline(l, detail_name)
	UiButton.style_label(%ConditionLabel, Fonts.BIZ, Tuning.RECORDS_DETAIL_TEXT_FONT_SIZE, Palette.MUTED_ON_INK)
	UiButton.style_label(%Condition, Fonts.BIZ, Tuning.RECORDS_DETAIL_TEXT_FONT_SIZE, Palette.PAPER)
	UiButton.style_label(%CertHint, Fonts.BIZ, Tuning.RECORDS_CERT_HINT_FONT_SIZE, Palette.MUTED)
	UiButton.style_label(%Help, Fonts.courier, Tuning.SELECT_HELP_FONT_SIZE, Palette.MUTED)
	_cert.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cert.add_theme_color_override(&"font_disabled_color", Palette.MUTED)  # paint() は押せないときの文字色を決めない


## 地・横罫・ヘッダー・ストライプはステージ選択と同じ（17.1, 17.3）
func _draw() -> void:
	StageSelect.draw_page(self, _header.get_rect())


## 累計の表: 未選択のステージカードと同じ地と枠、行の間に破線
func _draw_stats() -> void:
	var r := Rect2(Vector2.ZERO, _stats.size)
	var b: float = Tuning.SELECT_CARD_BORDER
	_stats.draw_rect(r, Palette.PAPER_LIGHT)
	_stats.draw_rect(r.grow(-b * 0.5), Palette.INK, false, b)
	var sep: float = _table.get_theme_constant(&"v_separation")
	var left: float = _table.global_position.x - _stats.global_position.x
	for i: int in range(0, _table.get_child_count() - _table.columns, _table.columns):
		var label: Control = _table.get_child(i)
		var y: float = label.global_position.y - _stats.global_position.y + label.size.y + sep * 0.5
		_stats.draw_dashed_line(Vector2(left, y), Vector2(left + _table.size.x, y), Palette.GRID_MAJOR, Tuning.RECORDS_RULE_W,
				Tuning.RECORDS_RULE_DASH)


## 壊した標的の小さな絵（ゲーム画面と同じ絵を縮める。壁はステージ選択の短い壁）
func _draw_target(icon: Control, kind: String) -> void:
	var place: Array = Tuning.RECORDS_TARGET_ICON[kind]
	icon.draw_set_transform(place[0], 0.0, Vector2.ONE * place[1])
	if kind == "wall":
		StageSelect.draw_wall_icon(icon)
	else:
		Target.draw_shape(icon, kind)
	icon.draw_set_transform(Vector2.ZERO)


## 検定印（設計書 3.1）: 取った印は朱の丸判子に名前（印ごとに決まった角度で傾ける）、まだの印は LOCKED の破線の丸と「？」
func _draw_stamp(i: int) -> void:
	var cell: Control = _cells[i]
	var r: float = Tuning.RECORDS_STAMP_R
	if _got.has(Achievements.LIST[i][0]):
		var ink := Color(Palette.STAMP, Tuning.RECORDS_STAMP_ALPHA)
		var w: float = Tuning.RECORDS_STAMP_W
		var inner: float = r - w - Tuning.RECORDS_STAMP_INNER_GAP - Tuning.RECORDS_STAMP_INNER_W * 0.5
		cell.draw_set_transform(cell.size * 0.5, deg_to_rad(Tuning.RECORDS_STAMP_DEG[i]))
		cell.draw_arc(Vector2.ZERO, r - w * 0.5, 0.0, TAU, Tuning.RESULT_STAMP_ARC_POINTS, ink, w, true)
		cell.draw_arc(Vector2.ZERO, inner, 0.0, TAU, Tuning.RESULT_STAMP_ARC_POINTS, ink, Tuning.RECORDS_STAMP_INNER_W, true)
		_draw_lines(cell, stamp_lines(i), Fonts.BIZ_BOLD, Tuning.RECORDS_STAMP_FONT_SIZE, ink)
	else:
		var w: float = Tuning.RECORDS_LOCKED_W
		var step: float = TAU / Tuning.RECORDS_LOCKED_DASHES
		cell.draw_set_transform(cell.size * 0.5)
		for k: int in Tuning.RECORDS_LOCKED_DASHES:
			cell.draw_arc(Vector2.ZERO, r - w * 0.5, step * k, step * (k + Tuning.RECORDS_LOCKED_DASH_ON), Tuning.SHORT_ARC_POINTS,
					Palette.LOCKED, w, true)
		_draw_lines(cell, stamp_lines(i), Fonts.DELA, Tuning.RECORDS_LOCKED_FONT_SIZE, Palette.LOCKED)
	cell.draw_set_transform(Vector2.ZERO)


## 行を原点を中心に縦に積んで描く（各行は左右の中央揃え）
static func _draw_lines(ci: CanvasItem, lines: PackedStringArray, font: Font, fs: int, color: Color) -> void:
	var line_h: float = font.get_height(fs)
	var top: float = -line_h * lines.size() * 0.5 + font.get_ascent(fs)
	for k: int in lines.size():
		var w: float = font.get_string_size(lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(font, Vector2(-w * 0.5, top + line_h * k), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## 説明欄は墨地（ステージ選択の詳細パネルと同じ）
func _draw_detail() -> void:
	_detail.draw_rect(Rect2(Vector2.ZERO, _detail.size), Palette.INK)
