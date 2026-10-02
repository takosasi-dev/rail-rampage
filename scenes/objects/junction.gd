class_name Junction
extends Node2D
## 分岐（FR-5〜11）。選択先の保持と表示だけを持つ。どれがアクティブかは Game が決める。

var branches: Array[String] = []
var branch_curves: Array[Curve2D] = []
var selected: int = 0
var active: bool = false:
	set(value):
		active = value
		_pulse_time = 0.0
		if is_node_ready():
			visual.queue_redraw()
			_glow.visible = value and glow_strength > 0.0

var glow_strength: float = 0.0  ## 設計書4章: 時間帯のにじみの強さ（StageLoader.build が入れる）
var _glow: Glow = null
var _pulse_time: float = 0.0

@onready var visual: Node2D = $Visual


func _ready() -> void:
	visual.material = DrawUtil.unshaded  # 設計書4章: 光る物（暗い時間帯でも本来の明るさ）
	_glow = Glow.make(Tuning.JUNCTION_GLOW_RADIUS, Palette.HAZARD, glow_strength)
	add_child(_glow)
	move_child(_glow, 0)  # 円盤の絵（Visual）より先に描く
	_glow.visible = active and glow_strength > 0.0
	visual.draw.connect(_draw_visual)


func _process(delta: float) -> void:
	if active:
		_pulse_time += delta
		visual.queue_redraw()


func toggle() -> void:
	selected = 1 - selected
	visual.queue_redraw()


func _draw_visual() -> void:
	var curve: Curve2D = branch_curves[selected]
	var dir: Vector2 = (curve.sample_baked(Tuning.JUNCTION_DIR_SAMPLE) - position).normalized()
	if not active:
		visual.draw_circle(Vector2.ZERO, Tuning.JUNCTION_INACTIVE_RADIUS, Palette.PAPER)
		_draw_arrow(dir, Tuning.JUNCTION_SMALL_ARROW_BASE, Tuning.JUNCTION_SMALL_ARROW_TIP,
				Tuning.JUNCTION_SMALL_ARROW_HALF_W, Palette.PAPER, false)
		return

	# 選択中の出口の先頭に破線
	var d: float = 0.0
	while d < Tuning.JUNCTION_DASH_TOTAL:
		var e: float = minf(d + Tuning.JUNCTION_DASH_ON, Tuning.JUNCTION_DASH_TOTAL)
		visual.draw_line(curve.sample_baked(d) - position, curve.sample_baked(e) - position,
				Palette.HAZARD, Tuning.JUNCTION_DASH_WIDTH)
		d = e + Tuning.JUNCTION_DASH_OFF

	# 外周リング: 拡大率 1.0〜PULSE_SCALE を往復
	var phase: float = (1.0 - cos(TAU * _pulse_time / Tuning.JUNCTION_PULSE_PERIOD)) * 0.5
	var ring_r: float = Tuning.JUNCTION_RING_RADIUS * lerpf(1.0, Tuning.JUNCTION_PULSE_SCALE, phase)
	visual.draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, Tuning.JUNCTION_ARC_POINTS,
			Palette.HAZARD, Tuning.JUNCTION_RING_WIDTH)

	visual.draw_circle(Vector2.ZERO, Tuning.JUNCTION_ACTIVE_RADIUS, Palette.HAZARD)
	visual.draw_arc(Vector2.ZERO, Tuning.JUNCTION_ACTIVE_RADIUS, 0.0, TAU, Tuning.JUNCTION_ARC_POINTS,
			Palette.INK, Tuning.JUNCTION_OUTLINE)
	# 設計書3章: 円盤の金属の縁（左上の光）
	visual.draw_arc(Vector2.ZERO, Tuning.JUNCTION_ACTIVE_RADIUS - Tuning.JUNCTION_RIM_INSET, deg_to_rad(Tuning.JUNCTION_RIM_DEG.x),
			deg_to_rad(Tuning.JUNCTION_RIM_DEG.y), Tuning.SHORT_ARC_POINTS, Palette.RIM_LIGHT, Tuning.JUNCTION_RIM_W, true)
	# TODO(spec): 警告黄の矢印は方眼背景（BOARD）とのコントラストが低いため、16.4 に倣い墨の輪郭を付けた
	_draw_arrow(dir, Tuning.JUNCTION_ARROW_BASE, Tuning.JUNCTION_ARROW_TIP,
			Tuning.JUNCTION_ARROW_HALF_W, Palette.HAZARD, true)


func _draw_arrow(dir: Vector2, base_r: float, tip_r: float, half_w: float, color: Color, outlined: bool) -> void:
	var side: Vector2 = dir.orthogonal() * half_w
	var pts := PackedVector2Array([dir * tip_r, dir * base_r + side, dir * base_r - side])
	visual.draw_colored_polygon(pts, color)
	if outlined:
		pts.append(pts[0])
		visual.draw_polyline(pts, Palette.INK, Tuning.JUNCTION_ARROW_OUTLINE)
