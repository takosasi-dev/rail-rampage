class_name Shards
extends Node2D
## 破片（② 設計書3章・4章）。kind: plank（木箱の板）・stave（樽板とたがの輪）・metal（ドラム缶の金属）・
## paper（ゴールの紙吹雪）・spark（激突・脱線の火花）。
## 物理ボディにせず、自前の放物線で動かす（NFR-2 の物体の数に数えない）。spark だけ光る物、ほかは照明を受ける

var kind: String = "plank"
var direction: Vector2 = Vector2(1.0, -0.7)  # 飛ぶ向き（正規化済み）

var _pieces: Array = []  # [位置, 速度, 角度, 回る速さ, 大きさ, 色, 揺れの位相, たがの輪か]
var _age: float = 0.0
var _life: float = 1.0


func _ready() -> void:
	z_index = Tuning.Z_FX
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # 物理フレームの外で動かすため
	if kind == "spark":
		material = DrawUtil.unshaded
	_life = Tuning.SHARD_LIFE[kind]
	var colors: Array = Palette.FX_SHARDS[kind]
	var speed: Vector2 = Tuning.SHARD_SPEED[kind]
	var size: Vector2 = Tuning.SHARD_SIZE[kind]
	var spread: float = deg_to_rad(Tuning.SHARD_SPREAD_DEG)
	var hoops: int = Quality.count(Tuning.SHARD_HOOPS.get(kind, 0))  # 画質が中・低なら数を減らす
	for i: int in Quality.count(Tuning.SHARD_COUNT[kind]):
		var dir: Vector2 = direction.rotated(randf_range(-spread, spread))
		_pieces.append([Vector2.ZERO, dir * randf_range(speed.x, speed.y), randf() * TAU,
				randf_range(-Tuning.SHARD_SPIN, Tuning.SHARD_SPIN),
				size * randf_range(Tuning.SHARD_SIZE_JITTER.x, Tuning.SHARD_SIZE_JITTER.y), colors[i % colors.size()],
				randf() * TAU, i < hoops])


## 樽のたがの輪の数（自動確認用）
func hoop_count() -> int:
	return _pieces.filter(func(p: Array) -> bool: return p[7]).size()


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	var gravity: float = Tuning.SHARD_GRAVITY[kind]
	var drag: float = clampf(1.0 - Tuning.SHARD_DRAG[kind] * delta, 0.0, 1.0)
	for p: Array in _pieces:
		var vel: Vector2 = p[1]
		vel.y += gravity * delta
		vel *= drag
		p[1] = vel
		var pos: Vector2 = p[0] + vel * delta
		if kind == "paper":  # 紙吹雪はひらひら横に揺れる
			pos.x += sin(_age * Tuning.PAPER_SWAY_FREQ + p[6]) * Tuning.PAPER_SWAY * delta
		p[0] = pos
		p[2] = float(p[2]) + float(p[3]) * delta
	queue_redraw()


func _draw() -> void:
	var fade: float = clampf((_life - _age) / (_life * Tuning.SHARD_FADE), 0.0, 1.0)
	for p: Array in _pieces:
		if kind == "spark":  # 飛ぶ向きに伸びた光る線
			draw_line(p[0], p[0] - (p[1] as Vector2) * Tuning.SPARK_STREAK, Color(p[5], fade), (p[4] as Vector2).y)
			continue
		if p[7]:  # 切れたたがの輪（墨の縁の上に鉄の色）
			var from: float = p[2]
			var to: float = from + deg_to_rad(Tuning.HOOP_ARC_DEG)
			draw_arc(p[0], Tuning.HOOP_R, from, to, Tuning.SHORT_ARC_POINTS, Color(Palette.INK, fade),
					Tuning.HOOP_W + Tuning.SHARD_OUTLINE * 2.0)
			draw_arc(p[0], Tuning.HOOP_R, from, to, Tuning.SHORT_ARC_POINTS, Color(Palette.FX_HOOP, fade), Tuning.HOOP_W)
			continue
		var half: Vector2 = (p[4] as Vector2) * 0.5
		var xf := Transform2D(float(p[2]), p[0])
		var pts := PackedVector2Array([xf * Vector2(-half.x, -half.y), xf * Vector2(half.x, -half.y),
				xf * Vector2(half.x, half.y), xf * Vector2(-half.x, half.y)])
		draw_colored_polygon(pts, Color(p[5], fade))
		pts.append(pts[0])
		draw_polyline(pts, Color(Palette.INK, fade), Tuning.SHARD_OUTLINE)
