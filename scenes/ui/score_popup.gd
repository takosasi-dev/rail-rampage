class_name ScorePopup
extends Node2D
## 得点ポップアップ（FR-35、16.6）。smash 位置から POPUP_DURATION 秒で POPUP_RISE px 上がりながら消える。書体は Dela Gothic One

var points_text: String = ""  # 例 "+450"
var mult_text: String = ""  # 倍率 > 1.0 のときだけ。例 "x1.5"


func _ready() -> void:
	material = DrawUtil.unshaded  # 設計書4章: 光る物（暗い時間帯でも読める）
	z_index = Tuning.Z_POPUP
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # 物理フレームの外（tween）で動かすため
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y - Tuning.POPUP_RISE, Tuning.POPUP_DURATION)
	tween.tween_property(self, "modulate:a", 0.0, Tuning.POPUP_DURATION)
	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	var font: Font = Fonts.DELA
	var fs: int = Tuning.POPUP_FONT_SIZE
	var head: String = points_text if mult_text.is_empty() else points_text + " "
	var head_w: float = font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var mult_w: float = font.get_string_size(mult_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(-(head_w + mult_w) * 0.5, 0.0)  # 左右中央。y はベースライン
	var mult_pos: Vector2 = pos + Vector2(head_w, 0.0)
	# 白文字＋墨の縁取り、倍率の部分は警告黄（16.4, 16.6）
	draw_string_outline(font, pos, head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Tuning.POPUP_OUTLINE, Palette.INK)
	draw_string_outline(font, mult_pos, mult_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Tuning.POPUP_OUTLINE, Palette.INK)
	draw_string(font, pos, head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.WHITE)
	draw_string(font, mult_pos, mult_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.HAZARD)
