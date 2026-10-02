class_name Flash
extends PointLight2D
## 爆発の閃光（② 設計書3章）。まわりを一瞬照らし、FLASH_LIFE で消える。暗い時間帯ほど映える

var _age: float = 0.0


func _ready() -> void:
	texture = DrawUtil.glow_texture()
	texture_scale = Tuning.FLASH_SCALE
	color = Palette.FX_FIRE_CORE
	energy = Tuning.FLASH_ENERGY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # 物理フレームの外で動かすため


func _process(delta: float) -> void:
	_age += delta
	if _age >= Tuning.FLASH_LIFE:
		queue_free()
		return
	energy = Tuning.FLASH_ENERGY * (1.0 - _age / Tuning.FLASH_LIFE)
