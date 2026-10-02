class_name Goal
extends Node2D
## ゴール地点の目印。到達判定はトロッコ側（goal セグメントの終端）で行う。
## ② 設計書3章: テープを張り、トロッコが着くと snap() でテープが切れて左右に落ちる。
## TODO(spec): 柱の上の「試験終了」の看板と、ゴール全体を光る物にする（暗い時間帯でもゴールが見える）のは設計書に無い。
## 依頼者の不在中に決めた

const SIGN_TEXT: String = "試験終了"

var tape_cut: bool = false  ## テープが切れた

@onready var visual: Node2D = $Visual


func _ready() -> void:
	visual.material = DrawUtil.unshaded
	visual.draw.connect(_draw_visual)


## テープを切る（Game がゴールに着いたときに呼ぶ）
func snap() -> void:
	tape_cut = true
	visual.queue_redraw()


func _draw_visual() -> void:
	var y: float = 0.0
	var i: int = 0
	while y < Tuning.GOAL_POLE_H:
		var color: Color = Palette.HAZARD if i % 2 == 0 else Palette.INK
		var h: float = minf(Tuning.GOAL_BLOCK_H, Tuning.GOAL_POLE_H - y)
		visual.draw_rect(Rect2(-Tuning.GOAL_POLE_W * 0.5, -y - h, Tuning.GOAL_POLE_W, h), color)
		y += Tuning.GOAL_BLOCK_H
		i += 1
	# 看板
	var sign_rect: Rect2 = Tuning.GOAL_SIGN
	visual.draw_rect(sign_rect, Palette.PAPER)
	visual.draw_rect(sign_rect.grow(-Tuning.GOAL_SIGN_BORDER * 0.5), Palette.INK, false, Tuning.GOAL_SIGN_BORDER)
	var font: Font = Fonts.DELA
	var fs: int = Tuning.GOAL_SIGN_FONT_SIZE
	var baseline: float = sign_rect.get_center().y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	visual.draw_string(font, Vector2(sign_rect.position.x, baseline), SIGN_TEXT, HORIZONTAL_ALIGNMENT_CENTER, sign_rect.size.x,
			fs, Palette.INK)
	# テープ（切れたら、上の端は左下へ垂れ、下の端は右へ、レールの上に落ちる）
	var x: float = Tuning.GOAL_TAPE_X
	var top := Vector2(x, -Tuning.GOAL_TAPE_H)
	var bottom := Vector2(x, -Tuning.GOAL_TAPE_W)
	if not tape_cut:
		visual.draw_line(top, bottom, Palette.GOAL_TAPE, Tuning.GOAL_TAPE_W)
		return
	var droop: Vector2 = Tuning.GOAL_TAPE_DROOP
	visual.draw_line(top, top + Vector2(-droop.x, droop.y), Palette.GOAL_TAPE, Tuning.GOAL_TAPE_W)
	visual.draw_line(bottom, bottom + Vector2(droop.y, 0.0), Palette.GOAL_TAPE, Tuning.GOAL_TAPE_W)
