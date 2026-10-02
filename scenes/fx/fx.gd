class_name Fx
## ② 演出の置き場と作り方（設計書 docs/superpowers/specs/2026-09-26-effects-design.md）。
## 演出はゲーム画面の World/Effects の下に置き、決まった時間で自分で消える。数は MAX_EFFECTS まで（古いものから消す）。
## 演出は Engine.time_scale に従って動く（スローモー中はゆっくり、ヒットストップ中は止まる）。
## 画質が中・低なら数の上限と粒を減らし、低なら閃光（照明）を出さない（trolleys-and-display-design.md 4章、Quality）


## parent（World/Effects）の下に fx を置く。数が上限（高は MAX_EFFECTS）を超えたら古いものから消す
static func add(parent: Node2D, fx: Node2D) -> Node2D:
	parent.add_child(fx)
	while parent.get_child_count() > Quality.max_effects():
		var old: Node = parent.get_child(0)
		parent.remove_child(old)
		old.queue_free()
	return fx


## 衝突の星。大きさは基本点 points で決める
static func impact(parent: Node2D, at: Vector2, points: int) -> Impact:
	var n := Impact.new()
	n.position = at
	n.radius = clampf(Tuning.IMPACT_R_MIN + points * Tuning.IMPACT_R_PER_POINT, Tuning.IMPACT_R_MIN, Tuning.IMPACT_R_MAX)
	add(parent, n)
	return n


## 破片（kind: plank・stave・metal・paper）。direction の向きへ飛ばす
static func shards(parent: Node2D, at: Vector2, kind: String, direction: Vector2) -> Shards:
	var n := Shards.new()
	n.position = at
	n.kind = kind
	n.direction = direction.normalized() if direction != Vector2.ZERO else Vector2.UP
	add(parent, n)
	return n


## 砂ぼこり・煙（kind: dust・smoke）
static func puffs(parent: Node2D, at: Vector2, kind: String) -> Puffs:
	var n := Puffs.new()
	n.position = at
	n.kind = kind
	add(parent, n)
	return n


## 爆発（FR-16 の半径が見える衝撃波の輪・火の玉・煙・金属の破片・まわりを照らす閃光）。閃光は画質が低なら出さない
static func explosion(parent: Node2D, at: Vector2, radius: float = Tuning.EXPLOSION_RADIUS) -> void:
	puffs(parent, at, "smoke")
	shards(parent, at, "metal", Vector2.UP)
	var wave := Shockwave.new()
	wave.position = at
	wave.max_radius = radius
	add(parent, wave)
	var ball := Fireball.new()
	ball.position = at
	add(parent, ball)
	if not Quality.lights():
		return
	var flash := Flash.new()
	flash.position = at
	add(parent, flash)
