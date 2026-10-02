class_name Target
extends RigidBody2D
## 標的（6.3, FR-12〜18）と、wall が割れた後のレンガ片。
## 被弾までは freeze で静止し（D-3）、launch() で物理に渡す。原点は下辺中央。

@export var kind: String = "crate"

var required_speed: float = 0.0  # wall だけ（FR-18）
var smashed: bool = false
var exploded: bool = false  # drum が爆発済みか（FR-17）
var unfrozen_at: float = 0.0  # freeze を解いたゲーム内時刻（NFR-2 の寿命）
var glow_strength: float = 0.0  # 設計書4章: 暗い時間帯のにじみの強さ（drum だけ。StageLoader.build が入れる）

@onready var visual: Node2D = $Visual


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = body_size()
	var col: CollisionShape2D = $CollisionShape2D
	col.shape = shape
	col.position = Vector2(0.0, -shape.size.y * 0.5)
	mass = Tuning.TARGET_MASS.get(kind, mass)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = Tuning.DEBRIS_BOUNCE
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true
	collision_layer = Tuning.LAYER_TARGET
	collision_mask = 0
	visual.draw.connect(_draw_visual)
	add_child(DropShadow.make(silhouette(kind)))  # 設計書2章
	if kind == "drum":  # 設計書4章: ドラム缶は光る物（本体は本来の明るさ、暗い時間帯は周りに赤いにじみ）
		visual.material = DrawUtil.unshaded
		var glow: Glow = Glow.make(Tuning.DRUM_GLOW_RADIUS, Palette.STAMP, glow_strength, Vector2(0.0, -body_size().y * 0.5))
		add_child(glow)
		move_child(glow, 0)  # 本体の絵より先に描く


func body_size() -> Vector2:
	return Tuning.TARGET_SIZE[kind]


## 見た目の中心（爆発の距離と得点ポップアップの位置に使う）
func center() -> Vector2:
	return to_global(Vector2(0.0, -body_size().y * 0.5))


## freeze を解いて飛ばす（FR-13 の「freeze解除 → 衝撃付与」、FR-14）。
## 衝撃に質量は掛けない（D-7）ので、重い物ほど飛ばない。
func launch(impulse: Vector2, spin: float, now: float) -> void:
	freeze = false
	# TODO(spec): 吹っ飛んだ物が何に当たるかは仕様に無い。地面と、吹っ飛んだ物どうしにだけ当てる
	#             （未破壊の標的に当てると、止まっている標的の上に積もるため）
	collision_layer = Tuning.LAYER_DEBRIS
	collision_mask = Tuning.LAYER_GROUND | Tuning.LAYER_DEBRIS
	apply_central_impulse(impulse)
	angular_velocity = spin
	unfrozen_at = now


func _draw_visual() -> void:
	draw_shape(visual, kind)


## 種別 kind の見た目を原点（下辺中央）に描く（タイトルの挿絵・ステージ選択のアイコンも同じ絵を使う）。
## 輪郭（16.4）はそのまま、内側に陰影と質感を足す（設計書3章。光は左上から）。
## 呼ぶ側が draw_set_transform で置いた位置・向き・大きさを崩さないよう、中で draw_set_transform を使わない
static func draw_shape(visual: CanvasItem, kind: String) -> void:
	var s: Vector2 = Tuning.TARGET_SIZE[kind]
	var rect := Rect2(-s.x * 0.5, -s.y, s.x, s.y)
	match kind:
		"crate":
			_draw_crate(visual, rect)
		"barrel":
			_draw_barrel(visual, rect)
		"dummy":
			_draw_dummy(visual)
		"drum":
			_draw_drum(visual, rect)
		"wall":
			_draw_wall(visual, rect)
		"brick_piece":
			_draw_brick(visual, rect, Palette.BRICK_TONES[0])
			visual.draw_rect(rect, Palette.INK, false, Tuning.OBJECT_OUTLINE)


## 影に使う形（下辺中央が原点の座標。DropShadow に渡す）
## ponytail: ダミー人形の部品は重なりを合わせない（腕と胴が 1px 重なる所だけ影が少し濃い）。目立つなら merge_polygons で合わせる
static func silhouette(kind: String) -> Array[PackedVector2Array]:
	var s: Vector2 = Tuning.TARGET_SIZE[kind]
	var rect := Rect2(-s.x * 0.5, -s.y, s.x, s.y)
	var out: Array[PackedVector2Array] = []
	match kind:
		"barrel":
			out.append(DrawUtil.rounded_rect(rect, Tuning.BARREL_RADIUS))
		"drum":
			out.append(DrawUtil.rounded_rect(rect, Tuning.DRUM_RADIUS))
		"dummy":
			for limb: Rect2 in Tuning.DUMMY_LIMBS:
				out.append(DrawUtil.rounded_rect(limb, Tuning.DUMMY_LIMB_RADIUS))
			out.append(DrawUtil.rounded_rect(Tuning.DUMMY_TORSO, Tuning.DUMMY_TORSO_RADIUS))
			out.append(DrawUtil.ellipse(Tuning.DUMMY_HEAD, Vector2.ONE * Tuning.DUMMY_HEAD_R))
		_:
			out.append(DrawUtil.rounded_rect(rect, 0.0))
	return out


## 木箱: 上が明るく下が暗いぼかし、板の継ぎ目、木目、光の縁の付いた筋交い、四隅の釘
static func _draw_crate(v: CanvasItem, rect: Rect2) -> void:
	var top := Vector2(rect.get_center().x, rect.position.y)
	DrawUtil.fill_gradient(v, DrawUtil.rounded_rect(rect, 0.0), top, Vector2(top.x, rect.end.y),
			[Palette.WOOD_LIGHT, Palette.WOOD_SHADE], [0.0, 1.0])
	for k: int in range(1, Tuning.CRATE_PLANKS):
		var y: float = rect.position.y + rect.size.y * k / Tuning.CRATE_PLANKS
		v.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Palette.WOOD_SEAM, Tuning.CRATE_SEAM_W)
	for grain: Array in Tuning.CRATE_GRAIN:
		var pts := PackedVector2Array()
		for p: Vector2 in grain:
			pts.append(rect.position + p)
		v.draw_polyline(pts, Palette.WOOD_GRAIN, Tuning.CRATE_GRAIN_W, true)
	var inset := Vector2.ONE * Tuning.CRATE_BRACE_INSET
	var ends: Array[Vector2] = [rect.position + inset, rect.end - inset,  # 左上→右下
			Vector2(rect.end.x - inset.x, rect.position.y + inset.y), Vector2(rect.position.x + inset.x, rect.end.y - inset.y)]
	for i: int in [0, 2]:
		v.draw_line(ends[i], ends[i + 1], Palette.WOOD_BRACE, Tuning.CRATE_BRACE_W)
		v.draw_line(ends[i] + Tuning.CRATE_BRACE_EDGE_SHIFT, ends[i + 1] + Tuning.CRATE_BRACE_EDGE_SHIFT,
				Palette.WOOD_BRACE_EDGE, Tuning.CRATE_BRACE_EDGE_W)
	for c: Vector2 in ends:
		v.draw_circle(c, Tuning.CRATE_NAIL_R, Palette.INK)
	v.draw_rect(rect, Palette.INK, false, Tuning.OBJECT_OUTLINE)


## 樽: 横のぼかしで丸み、縦の板目、金属のたが
static func _draw_barrel(v: CanvasItem, rect: Rect2) -> void:
	var mid: float = rect.get_center().y
	DrawUtil.fill_gradient(v, DrawUtil.rounded_rect(rect, Tuning.BARREL_RADIUS), Vector2(rect.position.x, mid),
			Vector2(rect.end.x, mid), Palette.BARREL_STOPS, Tuning.BARREL_STOP_AT)
	for k: int in range(1, Tuning.BARREL_STAVES):
		var x: float = rect.position.x + rect.size.x * k / Tuning.BARREL_STAVES
		v.draw_line(Vector2(x, rect.position.y + Tuning.BARREL_RADIUS), Vector2(x, rect.end.y - Tuning.BARREL_RADIUS),
				Palette.BARREL_STAVE, Tuning.BARREL_STAVE_W)
	for y: float in Tuning.BARREL_BAND_Y:  # 下端からの高さ
		var hoop := Rect2(rect.position.x, -y - Tuning.BARREL_HOOP_H * 0.5, rect.size.x, Tuning.BARREL_HOOP_H)
		var hy: float = hoop.get_center().y
		DrawUtil.fill_gradient(v, DrawUtil.rounded_rect(hoop, 0.0), Vector2(hoop.position.x, hy), Vector2(hoop.end.x, hy),
				Palette.HOOP_STOPS, Tuning.HOOP_STOP_AT)
	_outline(v, rect, Tuning.BARREL_RADIUS, Tuning.OBJECT_OUTLINE)


## ダミー人形: 部品ごとにプラスチックの艶（左上が明るい）、胴のベルト、試験用マーカー、白い光の点
static func _draw_dummy(v: CanvasItem) -> void:
	for limb: Rect2 in Tuning.DUMMY_LIMBS:
		_plastic(v, DrawUtil.rounded_rect(limb, Tuning.DUMMY_LIMB_RADIUS), limb)
		_outline(v, limb, Tuning.DUMMY_LIMB_RADIUS, Tuning.LIMB_OUTLINE)
	var torso: Rect2 = Tuning.DUMMY_TORSO
	_plastic(v, DrawUtil.rounded_rect(torso, Tuning.DUMMY_TORSO_RADIUS), torso)
	_outline(v, torso, Tuning.DUMMY_TORSO_RADIUS, Tuning.OBJECT_OUTLINE)
	v.draw_rect(Tuning.DUMMY_BELT, Palette.INK)
	var head_r := Vector2.ONE * Tuning.DUMMY_HEAD_R
	_plastic(v, DrawUtil.ellipse(Tuning.DUMMY_HEAD, head_r), Rect2(Tuning.DUMMY_HEAD - head_r, head_r * 2.0))
	v.draw_circle(Tuning.DUMMY_HEAD, Tuning.DUMMY_HEAD_R, Palette.INK, false, Tuning.OBJECT_OUTLINE, true)
	# 試験用マーカー: PAPER の円を4分割し、右上と左下を墨
	for m: Vector2 in Tuning.DUMMY_MARKERS:
		v.draw_circle(m, Tuning.DUMMY_MARKER_R, Palette.PAPER)
		_quarter(v, m, -PI * 0.5)
		_quarter(v, m, PI * 0.5)
	for g: Array in Tuning.DUMMY_GLOSS:
		v.draw_colored_polygon(DrawUtil.ellipse(g[0], g[1]), Palette.GLOSS)


## プラスチックの艶: 部品の外接矩形 box の左上から右下へのぼかし
static func _plastic(v: CanvasItem, shape: PackedVector2Array, box: Rect2) -> void:
	DrawUtil.fill_gradient(v, shape, box.position, box.end, Palette.PLASTIC_STOPS, Tuning.PLASTIC_STOP_AT)


## ドラム缶: 丸みの陰影、上下の縁の段差、丸みのある黄色の帯、縦の光の筋、警告三角
static func _draw_drum(v: CanvasItem, rect: Rect2) -> void:
	var mid: float = rect.get_center().y
	DrawUtil.fill_gradient(v, DrawUtil.rounded_rect(rect, Tuning.DRUM_RADIUS), Vector2(rect.position.x, mid),
			Vector2(rect.end.x, mid), Palette.DRUM_STOPS, Tuning.DRUM_STOP_AT)
	for y: float in Tuning.DRUM_RIM_Y:  # 下端からの高さ
		v.draw_line(Vector2(rect.position.x, -y), Vector2(rect.end.x, -y), Palette.RIM_SHADE, Tuning.DRUM_RIM_W)
	var band := Rect2(rect.position.x, -(rect.size.y + Tuning.DRUM_BAND_H) * 0.5, rect.size.x, Tuning.DRUM_BAND_H)
	var by: float = band.get_center().y
	DrawUtil.fill_gradient(v, DrawUtil.rounded_rect(band, 0.0), Vector2(band.position.x, by), Vector2(band.end.x, by),
			Palette.DRUM_BAND_STOPS, Tuning.DRUM_BAND_STOP_AT)
	v.draw_rect(band, Palette.INK, false, Tuning.DRUM_BAND_OUTLINE)
	v.draw_rect(Rect2(rect.position.x + Tuning.DRUM_GLINT_X, rect.position.y + Tuning.DRUM_RADIUS, Tuning.DRUM_GLINT_W,
			rect.size.y - Tuning.DRUM_RADIUS * 2.0), Palette.GLINT)
	var c: Vector2 = band.get_center()
	var hh: float = Tuning.DRUM_SIGN_H * 0.5
	var sign_pts := PackedVector2Array([c + Vector2(0.0, -hh), c + Vector2(Tuning.DRUM_SIGN_HALF_W, hh),
			c + Vector2(-Tuning.DRUM_SIGN_HALF_W, hh), c + Vector2(0.0, -hh)])
	v.draw_polyline(sign_pts, Palette.INK, Tuning.DRUM_SIGN_OUTLINE, true)
	_outline(v, rect, Tuning.DRUM_RADIUS, Tuning.OBJECT_OUTLINE)


## レンガ壁: 目地の地に、レンガ1個ずつ（決まった乱数の色むら）。縦目地は一番上の段から1段おき
static func _draw_wall(v: CanvasItem, rect: Rect2) -> void:
	v.draw_rect(rect, Palette.MORTAR_DEEP)
	var rng := RandomNumberGenerator.new()
	rng.seed = Tuning.BRICK_SEED
	var half: float = Tuning.MORTAR_W * 0.5
	for i: int in int(rect.size.y / Tuning.BRICK_ROW_H):
		var top: float = rect.position.y + Tuning.BRICK_ROW_H * i
		var xs: Array[float] = [rect.position.x, rect.end.x]
		if i % 2 == 0:
			xs.insert(1, rect.get_center().x)
		for k: int in xs.size() - 1:
			var brick := Rect2(xs[k] + half, top + half, xs[k + 1] - xs[k] - Tuning.MORTAR_W, Tuning.BRICK_ROW_H - Tuning.MORTAR_W)
			_draw_brick(v, brick, Palette.BRICK_TONES[rng.randi_range(0, Palette.BRICK_TONES.size() - 1)])
	v.draw_rect(rect, Palette.INK, false, Tuning.OBJECT_OUTLINE)


## レンガ1個: 地の色、上の縁に光、下の縁に影
static func _draw_brick(v: CanvasItem, r: Rect2, tone: Color) -> void:
	v.draw_rect(r, tone)
	v.draw_rect(Rect2(r.position, Vector2(r.size.x, Tuning.BRICK_EDGE_LIGHT_H)), Palette.BRICK_EDGE_LIGHT)
	v.draw_rect(Rect2(r.position.x, r.end.y - Tuning.BRICK_EDGE_SHADE_H, r.size.x, Tuning.BRICK_EDGE_SHADE_H),
			Palette.BRICK_EDGE_SHADE)


## 角丸の長方形に墨の輪郭だけを描く。輪郭は辺の上に中心を置く（デザイン案の SVG と同じ）
static func _outline(visual: CanvasItem, rect: Rect2, radius: int, outline: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = Palette.INK
	sb.set_border_width_all(int(outline))
	sb.set_corner_radius_all(radius)
	sb.set_expand_margin_all(outline * 0.5)
	sb.draw(visual.get_canvas_item(), rect)


## マーカーの円の、角度 from から90度ぶんを墨で塗る
static func _quarter(visual: CanvasItem, c: Vector2, from: float) -> void:
	var pts := PackedVector2Array([c])
	for i: int in Tuning.MARKER_ARC_STEPS + 1:
		var a: float = from + PI * 0.5 * i / Tuning.MARKER_ARC_STEPS
		pts.append(c + Vector2.from_angle(a) * Tuning.DUMMY_MARKER_R)
	visual.draw_colored_polygon(pts, Palette.INK)
