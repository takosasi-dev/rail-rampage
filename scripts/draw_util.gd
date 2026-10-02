class_name DrawUtil
## 描画の共通部品。


## rect を45度のストライプ（警告黄と墨を同じ幅 w で交互、16.4）で塗る。縞は「/」の向き。
## 色を変えるときは a（地）と b（縞）を渡す（勢いゲージは警告黄と HAZARD_DARK）
static func stripes(ci: CanvasItem, rect: Rect2, w: float, a: Color = Palette.HAZARD, b: Color = Palette.INK) -> void:
	ci.draw_rect(rect, a)
	var area := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
			rect.end, Vector2(rect.position.x, rect.end.y)])
	var h: float = rect.size.y
	var x: float = rect.position.x
	while x < rect.end.x + h:
		var stripe := PackedVector2Array([
			Vector2(x, rect.position.y), Vector2(x + w, rect.position.y),
			Vector2(x + w - h, rect.end.y), Vector2(x - h, rect.end.y)])
		for clipped: PackedVector2Array in Geometry2D.intersect_polygons(stripe, area):
			if _area(clipped) >= 1.0:  # 端で切れた面積0の欠片は描けない（三角形に分けられずエラーになる）
				ci.draw_colored_polygon(clipped, b)
		x += w * 2.0


## 多角形の面積（px²）
static func _area(poly: PackedVector2Array) -> float:
	var twice: float = 0.0
	for i: int in poly.size():
		twice += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(twice) * 0.5


## 光る物（設計書4章）: 照明と、全体に掛ける色（CanvasModulate）の影響を受けない。暗い時間帯でも本来の明るさで出る
static var unshaded: CanvasItemMaterial = _material(CanvasItemMaterial.BLEND_MODE_MIX)
## 光のにじみ: 足し算で重ねる（照明の影響も受けない）
static var additive: CanvasItemMaterial = _material(CanvasItemMaterial.BLEND_MODE_ADD)

static var _noise: Dictionary = {}  # 種類 → NoiseTexture2D（作るのは1回）
static var _glow: Texture2D = null
static var _cone_image: Image = null
static var _cone: Texture2D = null


static func _material(blend: CanvasItemMaterial.BlendMode) -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	m.blend_mode = blend
	return m


## offsets（0〜1、昇順）の位置 t の色。区切りの間は線形、外は端の色
static func gradient_color(colors: Array, offsets: Array, t: float) -> Color:
	if t <= offsets[0]:
		return colors[0]
	for i: int in range(1, offsets.size()):
		if t <= offsets[i]:
			var span: float = maxf(float(offsets[i]) - float(offsets[i - 1]), 0.0001)
			return (colors[i - 1] as Color).lerp(colors[i], (t - float(offsets[i - 1])) / span)
	return colors[colors.size() - 1]


## 点 p の、from→to の直線上での位置（from で 0、to で 1）
static func _along(p: Vector2, from: Vector2, axis: Vector2) -> float:
	return (p - from).dot(axis) / axis.length_squared()


## 多角形 poly を from→to の直線のぼかしで塗るための切れ端（設計書3章）。色の区切りごとの帯で poly を切り、
## 各頂点に色を付ける（帯の中は頂点の色の線形補間なので、区切りの間はきっちり直線のぼかしになる）。
## 戻り値は [頂点 PackedVector2Array, 頂点の色 PackedColorArray] の配列（fill_gradient が描く。確かめやすいよう分けた）
static func gradient_pieces(poly: PackedVector2Array, from: Vector2, to: Vector2, colors: Array, offsets: Array) -> Array:
	var axis: Vector2 = to - from
	var lo: float = INF
	var hi: float = -INF
	var reach: float = 0.0  # 帯の横幅の半分（poly がはみ出さない長さ）
	for p: Vector2 in poly:
		var t: float = _along(p, from, axis)
		lo = minf(lo, t)
		hi = maxf(hi, t)
		reach = maxf(reach, p.distance_to(from))
	var cuts: Array[float] = [minf(lo, offsets[0]) - 1.0]  # 範囲の外も端の色で塗るため、最初と最後の帯を伸ばす
	for o: Variant in offsets:
		cuts.append(float(o))
	cuts.append(maxf(hi, offsets[offsets.size() - 1]) + 1.0)
	var side: Vector2 = axis.normalized().orthogonal() * (reach * 2.0 + 1.0)
	var out: Array = []
	for i: int in cuts.size() - 1:
		var a: Vector2 = from + axis * cuts[i]
		var b: Vector2 = from + axis * cuts[i + 1]
		var band := PackedVector2Array([a + side, b + side, b - side, a - side])
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(poly, band):
			if _area(piece) < 0.01:
				continue
			var cols := PackedColorArray()
			for p: Vector2 in piece:
				cols.append(gradient_color(colors, offsets, _along(p, from, axis)))
			out.append([piece, cols])
	return out


## 多角形 poly を from→to の直線のぼかしで塗る。colors[i] は offsets[i] の位置の色
## ponytail: 描くたびに多角形を切る。止まっている物は1回しか描かないので足りる。毎フレーム描く物に使うなら切れ端を覚えておく
static func fill_gradient(ci: CanvasItem, poly: PackedVector2Array, from: Vector2, to: Vector2, colors: Array,
		offsets: Array) -> void:
	for piece: Array in gradient_pieces(poly, from, to, colors, offsets):
		ci.draw_polygon(piece[0], piece[1])


## 角丸の長方形の輪郭の点（時計回り、角1つを ROUND_STEPS 本の線で）。radius が 0 以下なら4点
static func rounded_rect(rect: Rect2, radius: float) -> PackedVector2Array:
	var r: float = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	if r <= 0.0:
		return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
				Vector2(rect.position.x, rect.end.y)])
	var centers: Array[Vector2] = [rect.position + Vector2(r, r), Vector2(rect.end.x - r, rect.position.y + r),
			rect.end - Vector2(r, r), Vector2(rect.position.x + r, rect.end.y - r)]
	var pts := PackedVector2Array()
	for k: int in 4:
		var start: float = PI + PI * 0.5 * k  # 左上の角は 180°（左）から 270°（上）へ
		for s: int in Tuning.ROUND_STEPS + 1:
			pts.append(centers[k] + Vector2.from_angle(start + PI * 0.5 * s / Tuning.ROUND_STEPS) * r)
	return pts


## 楕円の輪郭の点（右端から時計回り）
static func ellipse(center: Vector2, radius: Vector2, steps: int = Tuning.CIRCLE_STEPS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in steps:
		pts.append(center + Vector2.from_angle(TAU * i / steps) * radius)
	return pts


## 形 poly のぼかした影（設計書2章）。形を少しずつ広げながら薄く重ねる。ずらしは呼ぶ側が決める
static func soft_shadow(ci: CanvasItem, poly: PackedVector2Array) -> void:
	var color := Color(Palette.INK, Tuning.SHADOW_ALPHA / Tuning.SHADOW_STEPS)
	for i: int in Tuning.SHADOW_STEPS:
		var grow: float = Tuning.SHADOW_BLUR * float(Tuning.SHADOW_STEPS - i) / Tuning.SHADOW_STEPS
		for p: PackedVector2Array in Geometry2D.offset_polygon(poly, grow, Geometry2D.JOIN_ROUND):
			if _area(p) >= 1.0:
				ci.draw_colored_polygon(p, color)


## 折れ線のぼかした影（線路など）。太さ width の線を広げながら薄く重ねる
static func soft_shadow_line(ci: CanvasItem, points: PackedVector2Array, width: float) -> void:
	var color := Color(Palette.INK, Tuning.SHADOW_ALPHA / Tuning.SHADOW_STEPS)
	for i: int in Tuning.SHADOW_STEPS:
		var grow: float = Tuning.SHADOW_BLUR * float(Tuning.SHADOW_STEPS - i) / Tuning.SHADOW_STEPS
		ci.draw_polyline(points, color, width + grow * 2.0)


## 雑音の模様（設計書2章）。"blotch" は粗いむらと汚れ、"grain" は細かい粒、"fleck" は墨地の上の明るい粒。
## 継ぎ目なしで敷き詰められる。色は Palette.NOISE_COLORS、濃さは雑音の値が Tuning.NOISE_RAMP の範囲で 0→1
static func noise(kind: String) -> NoiseTexture2D:
	if not _noise.has(kind):
		var n := FastNoiseLite.new()
		n.seed = Tuning.NOISE_SEED[kind]
		n.frequency = Tuning.NOISE_FREQUENCY[kind]
		n.fractal_octaves = Tuning.NOISE_OCTAVES
		var color: Color = Palette.NOISE_COLORS[kind]
		var ramp_range: Vector2 = Tuning.NOISE_RAMP[kind]
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([ramp_range.x, ramp_range.y])
		ramp.colors = PackedColorArray([Color(color, 0.0), color])
		var tex := NoiseTexture2D.new()
		tex.width = Tuning.NOISE_SIZE
		tex.height = Tuning.NOISE_SIZE
		tex.seamless = true
		tex.noise = n
		tex.color_ramp = ramp
		_noise[kind] = tex
	return _noise[kind]


## rect を雑音の模様で薄く覆う。ci の texture_repeat は TEXTURE_REPEAT_ENABLED にしておく（敷き詰めるため）
static func tile_noise(ci: CanvasItem, rect: Rect2, kind: String, alpha: float) -> void:
	ci.draw_texture_rect(noise(kind), rect, true, Color(1.0, 1.0, 1.0, alpha))


## 光のにじみの絵（中心が白く、外へ透明になる丸）
static func glow_texture() -> Texture2D:
	if _glow == null:
		var g := GradientTexture2D.new()
		g.width = Tuning.GLOW_TEXTURE_SIZE
		g.height = Tuning.GLOW_TEXTURE_SIZE
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Palette.WHITE, Color(Palette.WHITE, 0.0)])
		g.gradient = grad
		_glow = g
	return _glow


## 照明の円錐の絵の元（上端の中央が頂点で、下へ広がりながら弱まる白。濃さは透明度）。
## 幅は、円錐が絵の左右の端で切れない（切れると光が四角い柱になる）ように角度から決める
static func cone_image() -> Image:
	if _cone_image == null:
		var half: float = deg_to_rad(Tuning.CONE_HALF_ANGLE_DEG)
		var size := Vector2i(ceili(2.0 * Tuning.CONE_TEXTURE_H * tan(half)) + 2, Tuning.CONE_TEXTURE_H)
		var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		var apex := Vector2(size.x * 0.5, 0.0)
		for y: int in size.y:
			for x: int in size.x:
				var d: Vector2 = Vector2(x + 0.5, y + 0.5) - apex
				var edge: float = clampf(1.0 - absf(d.angle_to(Vector2.DOWN)) / half, 0.0, 1.0)  # 円錐の縁で 0
				var fall: float = clampf(1.0 - d.length() / size.y, 0.0, 1.0)  # 遠いほど弱い
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, smoothstep(0.0, Tuning.CONE_EDGE_SOFT, edge) * fall))
		_cone_image = img
	return _cone_image


## 照明の円錐の絵（PointLight2D に使う。頂点が絵の上端の中央）
static func cone_texture() -> Texture2D:
	if _cone == null:
		_cone = ImageTexture.create_from_image(cone_image())
	return _cone
