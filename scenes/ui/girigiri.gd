class_name Girigiri
extends Node2D
## 「ギリギリ！ +500」の札（FR-36a、16.6）。警告黄地に Dela Gothic One の墨文字、-4度傾けて GIRIGIRI_SHOW_TIME 秒出す。


func _ready() -> void:
	material = DrawUtil.unshaded  # 設計書4章: 光る物（暗い時間帯でも読める）
	z_index = Tuning.Z_POPUP
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # 動かさないので補間しない
	rotation = deg_to_rad(Tuning.GIRIGIRI_ANGLE_DEG)
	create_tween().tween_callback(queue_free).set_delay(Tuning.GIRIGIRI_SHOW_TIME)


func text() -> String:
	return "ギリギリ！ +%d" % Tuning.GIRIGIRI_BONUS


func _draw() -> void:
	var font: Font = Fonts.DELA
	var fs: int = Tuning.GIRIGIRI_FONT_SIZE
	var size: Vector2 = font.get_string_size(text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var box: Vector2 = size + Tuning.GIRIGIRI_PADDING * 2.0
	draw_rect(Rect2(-box * 0.5, box), Palette.HAZARD)
	var baseline: float = (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(-size.x * 0.5, baseline), text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.INK)
