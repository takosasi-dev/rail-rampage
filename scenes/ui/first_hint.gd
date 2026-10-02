class_name FirstHint
extends Node2D
## 初回操作ヒント（FR-36c）。「[SPACE] / クリックで切り替え」の札。墨地に、キーの部分だけ警告黄の札（デザイン案）。
## 原点は札の下辺の中央。Game がアクティブ分岐の上に置き、最初の切替が成功したら消す。

const KEY: String = "SPACE"
const REST: String = "/ クリックで切り替え"


func _ready() -> void:
	material = DrawUtil.unshaded  # 設計書4章: 光る物（暗い時間帯でも読める）
	z_index = Tuning.Z_SIGN
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # 分岐から分岐へ飛び移るので補間しない


func text() -> String:
	return "[%s] %s" % [KEY, REST]


func _draw() -> void:
	var key_size: Vector2 = Fonts.courier_bold.get_string_size(KEY, HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.HINT_KEY_FONT_SIZE) \
			+ Tuning.HINT_KEY_PAD * 2.0
	var rest_size: Vector2 = Fonts.BIZ.get_string_size(REST, HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.HINT_FONT_SIZE)
	var box := Vector2(key_size.x + Tuning.HINT_GAP + rest_size.x, maxf(key_size.y, rest_size.y)) + Tuning.HINT_PAD * 2.0
	var rect := Rect2(-box.x * 0.5, -box.y, box.x, box.y)
	draw_rect(rect, Palette.INK)
	var mid: float = rect.get_center().y
	var key_rect := Rect2(rect.position.x + Tuning.HINT_PAD.x, mid - key_size.y * 0.5, key_size.x, key_size.y)
	draw_rect(key_rect, Palette.HAZARD)
	_draw_middle(Fonts.courier_bold, key_rect.position.x + Tuning.HINT_KEY_PAD.x, mid, KEY, Tuning.HINT_KEY_FONT_SIZE, Palette.INK)
	_draw_middle(Fonts.BIZ, key_rect.end.x + Tuning.HINT_GAP, mid, REST, Tuning.HINT_FONT_SIZE, Palette.PAPER)


func _draw_middle(font: Font, x: float, mid: float, s: String, fs: int, color: Color) -> void:
	var baseline: float = mid + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
