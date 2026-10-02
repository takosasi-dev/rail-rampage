class_name TrolleyWreck
extends RigidBody2D
## 失敗したトロッコ（FR-25）。トロッコと同じ見た目の物理ボディで、失敗時点の速度で転がる。原点はレール上。
## TODO(spec): 質量と跳ね返りは仕様に無い。質量は既定の1。跳ね返らない（相手の跳ね返りを打ち消す）ので、
##             激突した wall から後ろへ跳ね戻らずその場に落ちる。地面・未破壊の標的・破片に当たる

var type_id: String = Trolleys.DEFAULT  # 車両（トロッコと同じ絵。Game が木に入れる前に入れる）
var paint: int = 0  # 塗装の番号（replay-value-design.md 5.3。Game が入れる。描き分けは担当 B）

@onready var visual: Node2D = $Visual


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(Tuning.TROLLEY_TOP_W, Tuning.TROLLEY_H)  # トロッコの HitArea と同じ外接矩形
	var col: CollisionShape2D = $CollisionShape2D
	col.shape = shape
	col.position = Vector2(0.0, -Tuning.TROLLEY_H * 0.5)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = Tuning.DEBRIS_BOUNCE  # 標的・破片の跳ね返りと同じ量を
	physics_material_override.absorbent = true  # 足すのではなく引く（Godot は2物体の跳ね返りを足し合わせる）
	z_index = Tuning.Z_TROLLEY
	collision_layer = Tuning.LAYER_DEBRIS
	collision_mask = Tuning.LAYER_GROUND | Tuning.LAYER_TARGET | Tuning.LAYER_DEBRIS
	visual.draw.connect(func() -> void: Trolley.draw_body(visual, type_id, paint))
	add_child(DropShadow.make(Trolley.silhouette()))  # 設計書2章
