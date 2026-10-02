class_name SpeedLines
extends Node2D
## トロッコの後ろのスピード線（② 設計書3章）。amount（0〜1。SPEED_BASE で 0、SPEED_MAX で 1）で長さと濃さが変わる。
## トロッコの子（トロッコと一緒に傾く）。画質が中・低なら本数を減らす（trolleys-and-display-design.md 4章）

var amount: float = 0.0:
	set(value):
		if not is_equal_approx(value, amount):
			amount = value
			queue_redraw()

var _lines: Array = []  # 描く線（Tuning.SPEED_LINES の頭から）


func _ready() -> void:
	_lines = Tuning.SPEED_LINES.slice(0, Quality.count(Tuning.SPEED_LINES.size()))


## 描く線の本数（自動確認用）
func line_count() -> int:
	return _lines.size()


func _draw() -> void:
	if amount <= 0.0:
		return
	var color := Color(Palette.INK, Tuning.SPEED_LINE_ALPHA * amount)
	for line: Array in _lines:
		var head: Vector2 = line[0]
		draw_line(head, head - Vector2(float(line[1]) * amount, 0.0), color, Tuning.SPEED_LINE_W)
