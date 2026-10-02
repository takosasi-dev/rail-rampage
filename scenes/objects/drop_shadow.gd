class_name DropShadow
extends Node2D
## 物の影（設計書2章）。親の形（shapes、親の座標）を、後ろの壁にぼかして落とす。
## ずらす向きは画面の右下のまま（親が回っても影のずれは回さない）。描く順は壁のすぐ手前（Z_SHADOW）なので、
## 床（Z_GROUND）より下に落ちた影は床に隠れる。
## 画質が低なら描かない（ぼかしの影は重い描き方。trolleys-and-display-design.md 4章）

var shapes: Array[PackedVector2Array] = []
var _last_rotation: float = NAN  # 前に合わせたときの親の向き（止まっている標的は毎フレーム入れ直さない）


static func make(shapes_: Array[PackedVector2Array]) -> DropShadow:
	var s := DropShadow.new()
	s.name = "Shadow"
	s.shapes = shapes_
	return s


func _ready() -> void:
	z_as_relative = false
	z_index = Tuning.Z_SHADOW
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # 物理フレームの外で動かすため
	if Quality.plain():
		hide()
		set_process(false)
		return
	_follow()


func _process(_delta: float) -> void:
	_follow()


## 親の座標で、画面の向きの SHADOW_OFFSET にあたる位置へ置く。親の向き・大きさが変わっていなければ何もしない
func _follow() -> void:
	var xf: Transform2D = (get_parent() as Node2D).global_transform
	var rot: float = xf.get_rotation()
	if rot == _last_rotation:
		return
	_last_rotation = rot
	position = xf.basis_xform_inv(Tuning.SHADOW_OFFSET)


func _draw() -> void:
	for shape: PackedVector2Array in shapes:
		DrawUtil.soft_shadow(self, shape)
