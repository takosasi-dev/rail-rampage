class_name Backdrop
extends Parallax2D
## 奥の壁（設計書2章）。コンクリートのパネル・方眼・むらと汚れ・高窓（中は時間帯の空）・計測マーカーを1枚分
## （BACKDROP_TILE_W）描き、横に繰り返す。線路の BACKDROP_SCROLL 倍で横に流して奥行きを出す（縦は線路と同じ）。
## 窓の中の空と差し込む光は光る物（全体に掛ける色の影響を受けない）。ground_y と tod を入れてから木に足す。
## 画質が低なら、むらと粒（雑音の模様）を描かない（重い描き方。trolleys-and-display-design.md 4章）

var ground_y: float = 900.0
var tod: String = "noon"
var noise: bool = true  ## むらと粒を描くか（木に足したときの画質で決まる）


func _ready() -> void:
	name = "Backdrop"
	noise = not Quality.plain()
	scroll_scale = Vector2(Tuning.BACKDROP_SCROLL, 1.0)
	repeat_size = Vector2(Tuning.BACKDROP_TILE_W, 0.0)
	repeat_times = Tuning.BACKDROP_REPEAT
	z_index = Tuning.Z_BACKDROP
	var base := _layer("Base", null)
	base.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # 模様を敷き詰める
	base.draw.connect(_draw_base.bind(base))
	var sky := _layer("Sky", DrawUtil.unshaded)
	sky.draw.connect(_draw_sky.bind(sky))
	var mullions := _layer("Mullions", null)
	mullions.draw.connect(_draw_mullions.bind(mullions))
	var shafts := _layer("Shafts", DrawUtil.additive)
	shafts.visible = Tuning.TOD_SHAFT[tod] > 0.0
	shafts.draw.connect(_draw_shafts.bind(shafts))


func _layer(layer_name: String, mat: Material) -> Node2D:
	var n := Node2D.new()
	n.name = layer_name
	n.material = mat
	add_child(n)
	return n


## 1枚の中の窓（パネル1枚に1つ）
func windows() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var y: float = ground_y - Tuning.WINDOW_BOTTOM - Tuning.WINDOW_H
	var x: float = Tuning.WINDOW_MARGIN_X
	while x + Tuning.WINDOW_W <= Tuning.BACKDROP_TILE_W:
		out.append(Rect2(x, y, Tuning.WINDOW_W, Tuning.WINDOW_H))
		x += Tuning.PANEL_W
	return out


## コンクリートの地（上から下へ少し暗く）・パネルの継ぎ目とボルト・方眼・むらと粒・窓枠・計測マーカー
func _draw_base(ci: Node2D) -> void:
	var w: float = Tuning.BACKDROP_TILE_W
	var top: float = ground_y - Tuning.BACKDROP_H
	var rect := Rect2(0.0, top, w, Tuning.BACKDROP_H)
	DrawUtil.fill_gradient(ci, DrawUtil.rounded_rect(rect, 0.0), Vector2(0.0, top), Vector2(0.0, ground_y), Palette.WALL_STOPS,
			Tuning.WALL_STOP_AT)
	var x: float = 0.0
	while x < w:
		ci.draw_line(Vector2(x, top), Vector2(x, ground_y), Palette.WALL_SEAM, Tuning.PANEL_SEAM_W)
		var y: float = ground_y
		while y > top:
			ci.draw_line(Vector2(x, y), Vector2(x + Tuning.PANEL_W, y), Palette.WALL_SEAM, Tuning.PANEL_SEAM_W)
			for corner: Vector2 in [Vector2(Tuning.PANEL_BOLT_INSET, -Tuning.PANEL_BOLT_INSET),
					Vector2(Tuning.PANEL_W - Tuning.PANEL_BOLT_INSET, -Tuning.PANEL_BOLT_INSET)]:
				# 小さいので四角で描く（円は1つが1回の描画命令になり、壁全体で数百になる）
				var bolt := Vector2.ONE * Tuning.PANEL_BOLT_R
				ci.draw_rect(Rect2(Vector2(x, y) + corner - bolt, bolt * 2.0), Palette.WALL_BOLT)
			y -= Tuning.PANEL_H
		x += Tuning.PANEL_W
	_draw_grid(ci, rect)
	if noise:
		DrawUtil.tile_noise(ci, rect, "blotch", Tuning.WALL_BLOTCH_ALPHA)
		DrawUtil.tile_noise(ci, rect, "grain", Tuning.WALL_GRAIN_ALPHA)
	for win: Rect2 in windows():
		var frame: Rect2 = win.grow(Tuning.WINDOW_FRAME_W)
		ci.draw_rect(frame, Palette.WINDOW_FRAME)
		ci.draw_rect(frame, Palette.INK, false, Tuning.WINDOW_OUTLINE)
	for m: Vector2 in Tuning.BACKDROP_MARKERS:
		_marker(ci, Vector2(m.x, ground_y - m.y))


## 16.3 の方眼（40px 間隔 1px の GRID_MINOR、200px 間隔 2px の GRID_MAJOR）。床の高さを基準にそろえる
func _draw_grid(ci: Node2D, rect: Rect2) -> void:
	var minor := Color(Palette.GRID_MINOR, Tuning.BACKDROP_GRID_MINOR_ALPHA)
	var major := Color(Palette.GRID_MAJOR, Tuning.BACKDROP_GRID_MAJOR_ALPHA)
	for x: float in grid_xs(rect.end.x):
		var is_major: bool = is_zero_approx(fmod(x, Tuning.GRID_MAJOR_STEP))
		ci.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), major if is_major else minor,
				Tuning.BACKDROP_GRID_MAJOR_W if is_major else Tuning.BACKDROP_GRID_MINOR_W)
	var k: int = 0
	var y: float = rect.end.y
	while y >= rect.position.y:
		var is_major: bool = k % int(Tuning.GRID_MAJOR_STEP / Tuning.GRID_MINOR_STEP) == 0
		ci.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), major if is_major else minor,
				Tuning.BACKDROP_GRID_MAJOR_W if is_major else Tuning.BACKDROP_GRID_MINOR_W)
		y -= Tuning.GRID_MINOR_STEP
		k += 1


## 1枚の中の方眼の縦線の x。右端（width）には引かない（次の1枚の左端の線と重なって二重になるため）
static func grid_xs(width: float) -> Array[float]:
	var out: Array[float] = []
	var x: float = 0.0
	while x < width:
		out.append(x)
		x += Tuning.GRID_MINOR_STEP
	return out


## 窓の中の空（時間帯の2色のぼかし）と、夜の入り・深夜の星
func _draw_sky(ci: Node2D) -> void:
	var colors: Array = Palette.TOD_SKY[tod]
	for win: Rect2 in windows():
		DrawUtil.fill_gradient(ci, DrawUtil.rounded_rect(win, 0.0), win.position, Vector2(win.position.x, win.end.y), colors, [0.0, 1.0])
		if not Tuning.TOD_STARS[tod]:
			continue
		var room: Vector2 = win.size - Vector2.ONE * Tuning.STAR_PAD * 2.0
		for k: int in Tuning.STAR_COUNT:
			var p: Vector2 = win.position + Vector2.ONE * Tuning.STAR_PAD \
					+ Vector2(fposmod(k * Tuning.STAR_STEP.x, room.x), fposmod(k * Tuning.STAR_STEP.y, room.y))
			var r: float = Tuning.STAR_R_MIN + (k % 3) * Tuning.STAR_R_STEP  # 小さいので四角で描く（描画命令を減らす）
			ci.draw_rect(Rect2(p - Vector2.ONE * r, Vector2.ONE * r * 2.0), Palette.STAR)


## 窓の桟（縦 MULLION_COLS - 1 本、横は真ん中に1本）。照明を受ける（暗い時間帯は暗くなる）
func _draw_mullions(ci: Node2D) -> void:
	for win: Rect2 in windows():
		for k: int in range(1, Tuning.MULLION_COLS):
			var x: float = win.position.x + win.size.x * k / Tuning.MULLION_COLS
			ci.draw_line(Vector2(x, win.position.y), Vector2(x, win.end.y), Palette.WINDOW_FRAME, Tuning.MULLION_W)
		var y: float = win.get_center().y
		ci.draw_line(Vector2(win.position.x, y), Vector2(win.end.x, y), Palette.WINDOW_FRAME, Tuning.MULLION_W)


## 窓から床へ差し込む光の筋（見た目だけで、物は照らさない）
func _draw_shafts(ci: Node2D) -> void:
	var color: Color = Palette.TOD_SHAFT[tod]
	var alpha: float = Tuning.TOD_SHAFT[tod]
	for win: Rect2 in windows():
		var shaft := PackedVector2Array([Vector2(win.position.x, win.end.y), Vector2(win.end.x, win.end.y),
				Vector2(win.end.x + Tuning.SHAFT_SLANT, ground_y), Vector2(win.position.x + Tuning.SHAFT_SLANT, ground_y)])
		DrawUtil.fill_gradient(ci, shaft, Vector2(0.0, win.end.y), Vector2(0.0, ground_y), [Color(color, alpha), Color(color, 0.0)],
				[0.0, 1.0])


## 衝突試験の計測マーカー（4分割の円。右上と左下を墨）
func _marker(ci: Node2D, c: Vector2) -> void:
	var r: float = Tuning.MARKER_R
	ci.draw_circle(c, r, Palette.PAPER)
	for from: float in [-PI * 0.5, PI * 0.5]:
		var pts := PackedVector2Array([c])
		for i: int in Tuning.MARKER_ARC_STEPS + 1:
			pts.append(c + Vector2.from_angle(from + PI * 0.5 * i / Tuning.MARKER_ARC_STEPS) * r)
		ci.draw_colored_polygon(pts, Palette.INK)
	ci.draw_arc(c, r, 0.0, TAU, Tuning.CIRCLE_STEPS, Palette.INK, Tuning.MARKER_OUTLINE, true)
