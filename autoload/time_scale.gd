extends Node
## Engine.time_scale を変えるのはここだけ（FR-32）。autoload。
## 演出は「倍率と実時間」を要求として登録し、有効な要求のうち最小の倍率を使う。全部切れたら 1.0 に戻す。

var _requests: Dictionary = {}  # 要求の番号 → 倍率
var _next_id: int = 0


## scale 倍を実時間 seconds 秒だけ要求する（time_scale とポーズに左右されずに数える）
func request(scale: float, seconds: float) -> void:
	_next_id += 1
	var id: int = _next_id
	_requests[id] = scale
	_apply()
	get_tree().create_timer(seconds, true, false, true).timeout.connect(func() -> void:
		_requests.erase(id)  # clear() の後なら何もしない
		_apply())


## すべての要求を捨てて 1.0 に戻す（ポーズ FR-44・リトライ・画面の移動）
func clear() -> void:
	_requests.clear()
	_apply()


func _apply() -> void:
	var s: float = 1.0
	for v: float in _requests.values():
		s = minf(s, v)
	Engine.time_scale = s
