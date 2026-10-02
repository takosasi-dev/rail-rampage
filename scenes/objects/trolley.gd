class_name Trolley
extends PathFollow2D
## トロッコ（D-1, FR-1〜3）。物理ボディにせず PathFollow2D でレール上を確定的に動かす。
## 移動は Game が毎物理フレーム advance() を呼んで進める。

signal segment_entered(id: String)
signal goal_reached

## 現在のセグメントの次に進むセグメントIDを返す。ゴールなら ""。
var resolve_next: Callable
var paths: Dictionary = {}  # id -> Path2D
var segment_id: String = ""
var speed: float = Tuning.SPEED_BASE
## FR-55: 0 以上なら速度をこの値に固定する（デバッグビルドのみ）。自動確認はここを書き換える
var fixed_speed: float = Tuning.DEBUG_FIXED_SPEED if OS.is_debug_build() else -1.0
var total_distance: float = 0.0  # AC-4 の確認用
var headlight: PointLight2D  # 設計書4章: 前方を照らす円錐の光。set_headlight で点ける
var type_id: String = Trolleys.DEFAULT  # 車両（絵を描き分ける。Game が入れる）
var paint: int = 0  # 塗装の番号（replay-value-design.md 5.3。Game が入れる。描き分けは担当 B）
var airborne: bool = false  # ② ジャンプの区間にいる（Game が決める）。空中では車輪の火花を出さない
var _speed_lines: SpeedLines  # ② 設計書3章: 速いほど長く濃いスピード線
var _sparks: CPUParticles2D  # ② 設計書3章: SPARK_SPEED 以上で車輪から火花

@onready var visual: Node2D = $Visual
@onready var hit_area: Area2D = $HitArea  # FR-13。未破壊の標的（レイヤー2）だけを見る


func _ready() -> void:
	z_index = Tuning.Z_TROLLEY
	visual.draw.connect(_draw_visual)
	add_child(DropShadow.make(silhouette()))  # 設計書2章
	headlight = PointLight2D.new()
	headlight.name = "Headlight"
	headlight.texture = DrawUtil.cone_texture()
	headlight.texture_scale = Tuning.HEADLIGHT_SCALE
	headlight.rotation = -PI * 0.5  # 円錐の絵は下向き。前（+x）へ向ける
	headlight.position = Tuning.HEADLIGHT_AT
	# 円錐の頂点（絵の上端の中央）をトロッコの前に合わせる。offset は texture_scale を掛けた後の px
	headlight.offset = Vector2(0.0, headlight.texture.get_height() * Tuning.HEADLIGHT_SCALE * 0.5)
	headlight.color = Palette.LAMP_LIGHT
	headlight.enabled = false
	add_child(headlight)
	_speed_lines = SpeedLines.new()
	_speed_lines.name = "SpeedLines"
	add_child(_speed_lines)
	_sparks = _make_sparks()
	add_child(_sparks)
	# 当たり判定は車体の外接矩形（上辺の幅 × 高さ）
	var shape := RectangleShape2D.new()
	shape.size = Vector2(Tuning.TROLLEY_TOP_W, Tuning.TROLLEY_H)
	var col: CollisionShape2D = $HitArea/CollisionShape2D
	col.shape = shape
	col.position = Vector2(0.0, -Tuning.TROLLEY_H * 0.5)
	# monitorable は既定（true）のままにする。false の Area2D は物理エンジンで静止物扱いになり、
	# freeze（静止）中の標的との重なりを検出しなくなる
	hit_area.collision_layer = 0
	hit_area.collision_mask = Tuning.LAYER_TARGET


## 設計書4章: 前照灯の強さ（時間帯の Tuning.TOD_HEADLIGHT）。0 なら消す。失敗でトロッコを隠すと一緒に消える。
## 画質が低なら点けない（trolleys-and-display-design.md 4章）
func set_headlight(strength: float) -> void:
	headlight.energy = strength * Tuning.HEADLIGHT_ENERGY
	headlight.enabled = strength > 0.0 and Quality.lights()


## ② 設計書3章: 後ろの車輪から後ろへ散る火花（光る物）。トロッコが進んでも火花はその場に残る（local_coords = false）
func _make_sparks() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "WheelSparks"
	p.material = DrawUtil.unshaded
	p.position = Vector2(-Tuning.TROLLEY_WHEEL_X, 0.0)
	p.local_coords = false
	p.emitting = false
	p.amount = Quality.count(Tuning.SPARK_AMOUNT)  # 画質が中・低なら減らす
	p.lifetime = Tuning.SPARK_LIFETIME
	p.direction = Tuning.SPARK_DIRECTION
	p.spread = Tuning.PARTICLE_SPREAD_DEG * 0.5
	p.initial_velocity_min = Tuning.SPARK_VELOCITY.x
	p.initial_velocity_max = Tuning.SPARK_VELOCITY.y
	p.gravity = Tuning.SPARK_GRAVITY
	p.scale_amount_min = Tuning.SPARK_SIZE.x
	p.scale_amount_max = Tuning.SPARK_SIZE.y
	p.color = Palette.FX_SPARK
	return p


## ② ゴールで止まったら、スピード線と火花を消す（止まった後は advance() が呼ばれない）
func stop_fx() -> void:
	_speed_lines.amount = 0.0
	_sparks.emitting = false


## FR-22: 実速度を目標速度へ追従させてから進む
func advance(delta: float, target_speed: float) -> void:
	if fixed_speed >= 0.0:
		speed = fixed_speed  # FR-55: 勢いは計算するが速度に反映しない
	else:
		speed = lerpf(speed, target_speed, Tuning.SPEED_LERP * delta)
	# ② 設計書3章: スピード感（見た目だけ）
	_speed_lines.amount = clampf(inverse_lerp(Tuning.SPEED_BASE, Tuning.SPEED_MAX, speed), 0.0, 1.0)
	_sparks.emitting = speed >= Tuning.SPARK_SPEED and not airborne
	var remaining: float = speed * delta
	total_distance += remaining
	# FR-2: 終端を越えた分は次のセグメントへ持ち越す
	while true:
		var length: float = (get_parent() as Path2D).curve.get_baked_length()
		var left: float = length - progress
		if remaining < left:
			progress += remaining
			return
		remaining -= left
		var next_id: String = resolve_next.call(segment_id)
		if next_id.is_empty():
			progress = length
			goal_reached.emit()
			return
		reparent(paths[next_id], false)
		progress = 0.0
		segment_id = next_id
		segment_entered.emit(next_id)


func _draw_visual() -> void:
	draw_body(visual, type_id, paint)


## 確認用（tests/checks_garage.gd）: probe_on の間、draw_body が描いた部品の [色, 点] を probe に足す。
## headless では描いた結果を読めないので、車両ごとの絵の違いと外接矩形からのはみ出しをこれで見る
static var probe_on: bool = false
static var probe: Array = []


## 車体を描く（失敗時の TrolleyWreck・タイトルの挿絵・ステージ選択のアイコンも同じ見た目で描く、FR-25）。
## id: 車両（trolleys-and-display-design.md 3章）。形と色で描き分ける。どの車両も 16.5 の外接矩形の中に描き、
## 車輪と前照灯（Tuning.HEADLIGHT_AT）の位置は同じ。影の形（silhouette）と当たり判定も全車両同じ
## TODO(spec): 車両ごとの絵は仕様に無い（16.5 はトロッコ1台だけ）。重量型は角ばった厚い鋼板とリベット、軽量型は低く細い
##             アルミの桶と手すり、発破型は赤い桶に危険表示とダイナマイト、試作型は白い流線形に覗き窓と試験用マーカー
## paint: 塗装の番号（replay-value-design.md 5.3。0 は既定の色）。色は Palette.TROLLEY_PAINTS
static func draw_body(visual: CanvasItem, id: String = Trolleys.DEFAULT, paint: int = 0) -> void:
	var p: Dictionary = paint_colors(id, paint)
	match id:
		"heavy":
			_draw_heavy(visual, p)
		"light":
			_draw_light(visual, p)
		"blast":
			_draw_blast(visual, p)
		"prototype":
			_draw_prototype(visual, p)
		_:
			_draw_standard(visual, p)
	var glint_from: float = deg_to_rad(Tuning.TROLLEY_AXLE_GLINT_DEG.x)
	var glint_to: float = deg_to_rad(Tuning.TROLLEY_AXLE_GLINT_DEG.y)
	for wx: float in [-Tuning.TROLLEY_WHEEL_X, Tuning.TROLLEY_WHEEL_X]:
		var c := Vector2(wx, _wheel_y())
		_dot(visual, c, Tuning.TROLLEY_WHEEL_R, Palette.INK)
		_dot(visual, c, Tuning.TROLLEY_HUB_R, Palette.PAPER)
		visual.draw_arc(c, Tuning.TROLLEY_WHEEL_R - Tuning.TROLLEY_AXLE_GLINT_INSET, glint_from, glint_to, Tuning.SHORT_ARC_POINTS,
				Palette.WHEEL_GLINT, Tuning.TROLLEY_AXLE_GLINT_W, true)


## 塗装の色の組（Palette.TROLLEY_PAINTS）。知らない車両は標準型、範囲外の番号は端に寄せる
static func paint_colors(id: String, paint: int) -> Dictionary:
	var list: Array = Palette.TROLLEY_PAINTS.get(id, Palette.TROLLEY_PAINTS[Trolleys.DEFAULT])
	return list[clampi(paint, 0, list.size() - 1)]


## 塗装の名前（車両ごと。Tuning.PAINT_UNLOCK_LEVELS と同じ数）
## TODO(spec): 名前は依頼者の判断を待たずに決めた。0 は「既定」、最後は「金」
const PAINT_NAMES: Dictionary = {
	"standard": ["既定", "朱", "若草", "藍", "金"],
	"heavy": ["既定", "深緑", "煉瓦", "紫紺", "金"],
	"light": ["既定", "桜", "若草", "橙", "金"],
	"blast": ["既定", "橙", "深緑", "紫", "金"],
	"prototype": ["既定", "空色", "若草", "朱", "金"],
}


static func paint_name(id: String, paint: int) -> String:
	var names: Array = PAINT_NAMES.get(id, PAINT_NAMES[Trolleys.DEFAULT])
	return names[clampi(paint, 0, names.size() - 1)]


## 標準型（16.5）: 台形の鋼板に金属のぼかし・斜めの光の反射・鋲、側面中央のストライプ帯（設計書3章）
static func _draw_standard(v: CanvasItem, p: Dictionary) -> void:
	var body: PackedVector2Array = _body_points()
	_metal(v, body, p["body"])
	for r: Vector2 in Tuning.TROLLEY_RIVETS:
		_dot(v, r, Tuning.TROLLEY_RIVET_R, p["detail"])
	# 側面中央のストライプ帯（45度、警告黄と墨を同じ幅で交互）と、その上の影
	var half_bottom: float = Tuning.TROLLEY_BOTTOM_W * 0.5
	var band_y: float = (-Tuning.TROLLEY_H + _wheel_y() - Tuning.TROLLEY_BAND_H) * 0.5
	_stripes(v, Rect2(-half_bottom, band_y, Tuning.TROLLEY_BOTTOM_W, Tuning.TROLLEY_BAND_H), p["trim"])
	_fill(v, _rect_points(Rect2(-half_bottom, band_y, Tuning.TROLLEY_BOTTOM_W, Tuning.TROLLEY_BAND_SHADE_H)), Palette.BAND_SHADE)
	_ring(v, body, Palette.INK, Tuning.TROLLEY_OUTLINE)


## 重量型: 上の角を落とした厚い鋼板の箱、上縁の厚い板、縦の継ぎ目、2列のリベット
static func _draw_heavy(v: CanvasItem, p: Dictionary) -> void:
	var body := PackedVector2Array(Tuning.HEAVY_BODY)
	_metal(v, body, p["body"])
	var lip := Rect2(-Tuning.TROLLEY_TOP_W * 0.5, -Tuning.TROLLEY_H, Tuning.TROLLEY_TOP_W, Tuning.HEAVY_LIP_H)
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(_rect_points(lip), body):
		_fill(v, piece, p["trim"])
	_line(v, PackedVector2Array([Vector2(lip.position.x, lip.end.y), lip.end]), Palette.HEAVY_SEAM, Tuning.TROLLEY_DETAIL_W)
	for x: float in Tuning.HEAVY_SEAM_X:
		_line(v, PackedVector2Array([Vector2(x, lip.end.y), Vector2(x, _wheel_y())]), Palette.HEAVY_SEAM, Tuning.TROLLEY_DETAIL_W)
	for y: float in Tuning.HEAVY_RIVET_ROWS:
		for x: float in Tuning.HEAVY_RIVET_X:
			_dot(v, Vector2(x, y), Tuning.HEAVY_RIVET_R, p["detail"])
	_ring(v, body, Palette.INK, Tuning.TROLLEY_OUTLINE)


## 軽量型: 低く細いアルミの桶、上の手すり、青い細帯、肉抜きの穴
static func _draw_light(v: CanvasItem, p: Dictionary) -> void:
	var rail := PackedVector2Array(Tuning.LIGHT_RAIL)
	_line(v, rail, Palette.INK, Tuning.LIGHT_RAIL_W)
	var rail_top: float = rail[1].y
	for x: float in Tuning.LIGHT_POSTS:
		_line(v, PackedVector2Array([Vector2(x, rail_top), Vector2(x, rail[0].y)]), Palette.INK, Tuning.LIGHT_RAIL_W)
	var body := PackedVector2Array(Tuning.LIGHT_BODY)
	_metal(v, body, p["body"])
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(_rect_points(Tuning.LIGHT_STRIPE), body):
		_fill(v, piece, p["trim"])
	for c: Vector2 in Tuning.LIGHT_HOLES:
		_dot(v, c, Tuning.LIGHT_HOLE_R, p["detail"])
		v.draw_circle(c, Tuning.LIGHT_HOLE_R, Palette.INK, false, Tuning.TROLLEY_DETAIL_W * 0.5, true)
	_ring(v, body, Palette.INK, Tuning.TROLLEY_OUTLINE)


## 発破型: 赤い桶、上縁の警告のストライプ、ひし形の危険表示、桶から出たダイナマイト3本と導火線
static func _draw_blast(v: CanvasItem, p: Dictionary) -> void:
	for stick: Rect2 in Tuning.BLAST_STICKS:  # 桶の後ろから出ている
		_fill(v, _rect_points(stick), Palette.BLAST_STICK)
		_ring(v, _rect_points(stick), Palette.INK, Tuning.TROLLEY_DETAIL_W)
	_fill(v, _rect_points(Tuning.BLAST_TIE), Palette.HAZARD)
	_line(v, PackedVector2Array(Tuning.BLAST_FUSE), Palette.INK, Tuning.TROLLEY_DETAIL_W * Tuning.TROLLEY_THIN_LINE)
	_dot(v, Tuning.BLAST_FUSE[Tuning.BLAST_FUSE.size() - 1], Tuning.BLAST_SPARK_R, Palette.FX_SPARK)
	var body := PackedVector2Array(Tuning.BLAST_BODY)
	_metal(v, body, p["body"])
	# 上縁の帯は、桶の側面の傾きの分だけ内側に寄せる（下の角が輪郭の外に出ないように）
	var inset: float = (body[1].x - body[2].x) * Tuning.BLAST_BAND_H / (body[2].y - body[1].y)
	_stripes(v, Rect2(body[0].x + inset, body[0].y, body[1].x - body[0].x - inset * 2.0, Tuning.BLAST_BAND_H), p["trim"])
	var c: Vector2 = Tuning.BLAST_SIGN
	var r: float = Tuning.BLAST_SIGN_R
	var sign := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	_fill(v, sign, p["detail"])
	_ring(v, sign, Palette.INK, Tuning.TROLLEY_DETAIL_W)
	var mark: Vector2 = Tuning.BLAST_SIGN_MARK  # 「！」の縦棒の上端と下端（中心から）
	_line(v, PackedVector2Array([c + Vector2(0, mark.x), c + Vector2(0, mark.y)]), Palette.INK, Tuning.TROLLEY_DETAIL_W)
	_dot(v, c + Vector2(0, Tuning.BLAST_SIGN_DOT_Y), Tuning.TROLLEY_DETAIL_W * Tuning.BLAST_SIGN_DOT_R, Palette.INK)
	_ring(v, body, Palette.INK, Tuning.TROLLEY_OUTLINE)


## 試作型: 白い流線形、前の上の覗き窓、警告黄の帯、試験用マーカー（ダミー人形と同じ4分割の円）
static func _draw_prototype(v: CanvasItem, p: Dictionary) -> void:
	var body := PackedVector2Array(Tuning.PROTO_BODY)
	_metal(v, body, p["body"])
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(_rect_points(Tuning.PROTO_STRIPE), body):
		_fill(v, piece, p["trim"])
	var visor := PackedVector2Array(Tuning.PROTO_VISOR)
	_fill(v, visor, p["detail"])
	_line(v, PackedVector2Array(Tuning.PROTO_VISOR_GLINT), Palette.PROTO_VISOR_GLINT, Tuning.TROLLEY_DETAIL_W)
	_ring(v, visor, Palette.INK, Tuning.TROLLEY_DETAIL_W)
	var m: Vector2 = Tuning.PROTO_MARKER
	_dot(v, m, Tuning.DUMMY_MARKER_R, Palette.PAPER)
	Target._quarter(v, m, -PI * 0.5)
	Target._quarter(v, m, PI * 0.5)
	v.draw_circle(m, Tuning.DUMMY_MARKER_R, Palette.INK, false, Tuning.TROLLEY_DETAIL_W * Tuning.TROLLEY_THIN_LINE, true)
	_ring(v, body, Palette.INK, Tuning.TROLLEY_OUTLINE)


## 金属の地: 上が明るいぼかし（設計書3章）と、斜めの光の反射
static func _metal(v: CanvasItem, body: PackedVector2Array, colors: Array) -> void:
	var top: float = Array(body).map(func(p: Vector2) -> float: return p.y).min()
	DrawUtil.fill_gradient(v, body, Vector2(0.0, top), Vector2(0.0, _wheel_y()), colors, [0.0, 1.0])
	_note(colors[0], body)
	for glint: PackedVector2Array in Geometry2D.intersect_polygons(PackedVector2Array(Tuning.TROLLEY_GLINT), body):
		_fill(v, glint, Palette.GLINT_SOFT)


static func _fill(v: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	v.draw_colored_polygon(pts, color)
	_note(color, pts)


## 閉じた輪郭
static func _ring(v: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	var line := pts.duplicate()
	line.append(pts[0])
	_line(v, line, color, width)


static func _line(v: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	v.draw_polyline(pts, color, width)
	_note(color, pts)


static func _dot(v: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	v.draw_circle(c, r, color)
	_note(color, PackedVector2Array([c - Vector2.ONE * r, c + Vector2.ONE * r]))


## 45度のストライプ（既定の塗装は警告黄と墨、16.4。塗装で明るい方の色を替える）
static func _stripes(v: CanvasItem, rect: Rect2, color: Color = Palette.HAZARD) -> void:
	DrawUtil.stripes(v, rect, Tuning.STRIPE_W, color)
	_note(color, _rect_points(rect))


static func _rect_points(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _note(color: Color, pts: PackedVector2Array) -> void:
	if probe_on:
		probe.append([color, pts])


## 影に使う形（車体と車輪2つ。原点はレール上）
static func silhouette() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = [_body_points()]
	for wx: float in [-Tuning.TROLLEY_WHEEL_X, Tuning.TROLLEY_WHEEL_X]:
		out.append(DrawUtil.ellipse(Vector2(wx, _wheel_y()), Vector2.ONE * Tuning.TROLLEY_WHEEL_R))
	return out


## 車体の台形（上辺 TOP_W・下辺 BOTTOM_W）。下辺は車輪の中心の高さ
static func _body_points() -> PackedVector2Array:
	var half_top: float = Tuning.TROLLEY_TOP_W * 0.5
	var half_bottom: float = Tuning.TROLLEY_BOTTOM_W * 0.5
	return PackedVector2Array([Vector2(-half_top, -Tuning.TROLLEY_H), Vector2(half_top, -Tuning.TROLLEY_H),
			Vector2(half_bottom, _wheel_y()), Vector2(-half_bottom, _wheel_y())])


## 車輪の中心の高さ（車輪の下端がレールの上面）
static func _wheel_y() -> float:
	return -(Tuning.TROLLEY_WHEEL_R + Tuning.RAIL_WIDTH * 0.5)
