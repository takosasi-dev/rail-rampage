extends SceneTree
## ② 演出と手触りの自動確認（設計書 docs/superpowers/specs/2026-09-26-effects-design.md の5章）。
## 書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_fx.gd （失敗があれば終了コード1）
## 物理を実フレームで進める（--fixed-fps 60 を付けると待たずに進む）。描画のエラーは終了コードに出ないので、
## 出力に「SCRIPT ERROR」が無いことも見る。設定・記録は確認用のファイルに差し替え、最後に消す。

const GAME_SCENE: String = "res://scenes/game.tscn"
const TEST_SETTINGS: String = "user://checks_fx_settings.cfg"
const TEST_SAVE: String = "user://checks_fx_save.cfg"
const RAIL_Y: float = 600.0
const MAX_FRAMES: int = 2000

var _failed: int = 0
var _game_state: Node  # autoload（-s のスクリプトでは名前で参照できない）
var _time_scale: Node
var _games: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_game_state = root.get_node("GameState")
	_time_scale = root.get_node("TimeScale")
	var real_settings: String = _game_state.settings_path
	var real_save: String = _game_state.save_path
	_game_state.settings_path = TEST_SETTINGS
	_game_state.save_path = TEST_SAVE
	_remove_test_files()
	_game_state.load_settings()
	_game_state.load_records()
	var checks: Array[Callable] = [_check_crate_fx, _check_barrel_fx, _check_wall_fx, _check_dummy_fx, _check_explosion_fx,
			_check_fx_materials, _check_speed_fx, _check_fail_fx, _check_landing_fx, _check_goal_fx, _check_fx_cap]
	for check: Callable in checks:
		_game_state.screen_shake = true
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
		for game: Variant in _games:  # 型を付けると、解放済みのゲームを受けたときに止まる
			if is_instance_valid(game):
				(game as Node).free()
		_games.clear()
		_time_scale.clear()
		paused = false
	_remove_test_files()
	_game_state.settings_path = real_settings
	_game_state.save_path = real_save
	_game_state.load_settings()
	_game_state.load_records()
	for p: Node in root.get_node("Audio").get_children():
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	await physics_frame
	await physics_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# --- 壊れ方（設計書3章） ---

# 木箱: 衝突の星と板の切れ端。どちらも時間が経つと消える
func _check_crate_fx() -> bool:
	var game: Node = _new_game(_straight([_obj("crate", 600)]))
	var crate: Target = game._targets[0]
	await _frames_until(func() -> bool: return crate.smashed)
	await physics_frame
	var fx: Node2D = game.get_node("World/Effects")
	var impacts: Array = _of(fx, Impact)
	var shards: Array = _of(fx, Shards)
	_expect(impacts.size() == 1 and shards.size() == 1 and (shards[0] as Shards).kind == "plank",
			"木箱を壊すと衝突の星と板の切れ端が出る（星 %d・破片 %s）" % [impacts.size(), shards.map(func(s: Shards) -> String: return s.kind)])
	await _frames(ceili(_fx_max_life() * 60.0) + 5)
	_expect(_of(fx, Impact).is_empty() and _of(fx, Shards).is_empty(), "演出は時間が経つと消える")
	return true


# 樽: 樽板の破片と、たがの輪
func _check_barrel_fx() -> bool:
	var game: Node = _new_game(_straight([_obj("barrel", 600)]))
	var barrel: Target = game._targets[0]
	await _frames_until(func() -> bool: return barrel.smashed)
	await physics_frame
	var shards: Array = _of(game.get_node("World/Effects"), Shards)
	_expect(shards.size() == 1 and (shards[0] as Shards).kind == "stave", "樽を壊すと樽板の破片が出る")
	_expect(shards.size() == 1 and (shards[0] as Shards).hoop_count() > 0, "樽の破片に、たがの輪が混ざる")
	return true


# レンガ壁: 砂ぼこり（レンガ片は今までどおり物理で飛ぶ）
func _check_wall_fx() -> bool:
	var wall: Dictionary = _obj("wall", 600)
	wall["required_speed"] = 100.0
	var game: Node = _new_game(_straight([wall]))
	await _frames_until(func() -> bool: return game.smashed_count > 0)  # 壁は壊れるとレンガ片に置き換わって消える
	await physics_frame
	var puffs: Array = _of(game.get_node("World/Effects"), Puffs)
	_expect(puffs.any(func(p: Puffs) -> bool: return p.kind == "dust"), "レンガ壁を壊すと砂ぼこりが出る")
	return true


# ダミー人形: 衝突の星と砂ぼこりだけ（2.3: 形は保つので破片は出さない）
func _check_dummy_fx() -> bool:
	var game: Node = _new_game(_straight([_obj("dummy", 600)]))
	var d: Target = game._targets[0]
	await _frames_until(func() -> bool: return d.smashed)
	await physics_frame
	var fx: Node2D = game.get_node("World/Effects")
	_expect(_of(fx, Impact).size() == 1 and _of(fx, Shards).is_empty() and _of(fx, Puffs).size() == 1,
			"ダミー人形は衝突の星と砂ぼこりだけ（破片なし）")
	return true


# 爆発: 火の玉・衝撃波の輪（最大の半径は EXPLOSION_RADIUS）・煙・金属の破片・閃光。閃光は消える
func _check_explosion_fx() -> bool:
	var game: Node = _new_game(_straight([_obj("drum", 600)]))
	var drum: Target = game._targets[0]
	await _frames_until(func() -> bool: return drum.exploded)
	await physics_frame
	var fx: Node2D = game.get_node("World/Effects")
	var waves: Array = _of(fx, Shockwave)
	_expect(_of(fx, Fireball).size() == 1 and waves.size() == 1
			and is_equal_approx((waves[0] as Shockwave).max_radius, Tuning.EXPLOSION_RADIUS),
			"爆発で火の玉と、半径 %d まで広がる衝撃波の輪が出る" % Tuning.EXPLOSION_RADIUS)
	_expect(_of(fx, Puffs).any(func(p: Puffs) -> bool: return p.kind == "smoke")
			and _of(fx, Shards).any(func(s: Shards) -> bool: return s.kind == "metal"), "爆発で煙と金属の破片が出る")
	var flashes: Array = _of(fx, Flash)
	_expect(flashes.size() == 1 and (flashes[0] as Flash).energy > 0.0, "爆発の閃光（PointLight2D）が点く")
	var wave: Shockwave = waves[0] if waves.size() == 1 else null
	var widest: float = 0.0
	for _i: int in ceili(_fx_max_life() * 60.0 / Tuning.SLOWMO_SCALE) + 5:
		if is_instance_valid(wave):
			widest = maxf(widest, wave.radius)
		await physics_frame
	_expect(widest >= Tuning.EXPLOSION_RADIUS * 0.95, "衝撃波の輪は半径 %d まで広がる（%.0f）" % [Tuning.EXPLOSION_RADIUS, widest])
	_expect(fx.get_child_count() == 0, "爆発の演出は全部消える（残り %d）" % fx.get_child_count())
	return true


# 光る物: 衝突の星・火の玉・火花は照明の影響を受けない。煙・破片は照明を受ける
func _check_fx_materials() -> bool:
	var game: Node = _new_game(_straight([_obj("drum", 600)]))
	var drum: Target = game._targets[0]
	await _frames_until(func() -> bool: return drum.exploded)
	await physics_frame
	var fx: Node2D = game.get_node("World/Effects")
	var lit_ok: bool = _of(fx, Impact).all(func(n: CanvasItem) -> bool: return n.material == DrawUtil.unshaded) \
			and _of(fx, Fireball).all(func(n: CanvasItem) -> bool: return n.material == DrawUtil.additive)
	var shaded_ok: bool = _of(fx, Puffs).all(func(n: CanvasItem) -> bool: return n.material == null) \
			and _of(fx, Shards).all(func(n: CanvasItem) -> bool: return n.material == null)
	var sparks: CPUParticles2D = game._trolley.get_node("WheelSparks")
	_expect(lit_ok and sparks.material == DrawUtil.unshaded, "衝突の星・火の玉・火花は光る物")
	_expect(shaded_ok, "煙と破片は照明を受ける")
	return true


# スピード線: SPEED_BASE で見えず、SPEED_MAX でいちばん濃い。火花は SPARK_SPEED 以上のときだけ
func _check_speed_fx() -> bool:
	var game: Node = _new_game(_straight([]))
	var t: Trolley = game._trolley
	var lines: SpeedLines = t.get_node("SpeedLines")
	var sparks: CPUParticles2D = t.get_node("WheelSparks")
	t.fixed_speed = Tuning.SPEED_BASE
	await _frames(3)
	_expect(is_zero_approx(lines.amount) and not sparks.emitting, "速さ SPEED_BASE ではスピード線も火花も出ない（%.2f）" % lines.amount)
	t.fixed_speed = Tuning.SPARK_SPEED
	await _frames(3)
	_expect(sparks.emitting, "速さ SPARK_SPEED 以上で車輪から火花")
	t.fixed_speed = Tuning.SPEED_MAX
	await _frames(3)
	_expect(is_equal_approx(lines.amount, 1.0), "速さ SPEED_MAX でスピード線がいちばん濃い（%.2f）" % lines.amount)
	return true


# 激突: 大きめの衝突の星と揺れ。揺れ OFF（FR-36）なら揺らさない
func _check_fail_fx() -> bool:
	for shake_on: bool in [true, false]:
		_game_state.screen_shake = shake_on
		var wall: Dictionary = _obj("wall", 600)
		wall["required_speed"] = 5000.0  # 必ず激突する
		var game: Node = _new_game(_straight([wall]))
		await _frames_until(func() -> bool: return game._finished)
		var amp: float = game.shake_amplitude()
		_expect((amp > 0.0) == shake_on, "激突で揺れる（揺れ %s: 振幅 %.1f）" % ["ON" if shake_on else "OFF", amp])
		var fx: Node2D = game.get_node("World/Effects")
		_expect(not _of(fx, Impact).is_empty(), "激突で衝突の星が出る")
		var sparks: Array = _of(fx, Shards).filter(func(s: Shards) -> bool: return s.kind == "spark")
		_expect(sparks.size() == 1 and (sparks[0] as Shards).material == DrawUtil.unshaded, "激突で光る火花が散る")
		game.free()
	return true


# ジャンプ: 空中では車輪の火花が出ない。着地で砂ぼこりと小さな揺れ（揺れ OFF なら揺らさない）。踏み切りでは出さない
func _check_landing_fx() -> bool:
	for shake_on: bool in [true, false]:
		_game_state.screen_shake = shake_on
		var data: Dictionary = _straight([])
		data["segments"] = {
			"s0": {"points": [[0, RAIL_Y], [1000, RAIL_Y]], "end": {"type": "next", "segment": "s1"}},
			"s1": {"points": [[1000, RAIL_Y], [1200, RAIL_Y - 100.0], [1400, RAIL_Y]], "jump": {"required_speed": 100.0},
					"end": {"type": "next", "segment": "s2"}},
			"s2": {"points": [[1400, RAIL_Y], [3000, RAIL_Y]], "end": {"type": "goal"}}}
		var game: Node = _new_game(data)
		var t: Trolley = game._trolley
		t.fixed_speed = Tuning.SPEED_MAX
		var sparks: CPUParticles2D = t.get_node("WheelSparks")
		var fx: Node2D = game.get_node("World/Effects")
		await _frames_until(func() -> bool: return t.segment_id == "s1")
		await _frames(2)
		_expect(_of(fx, Puffs).is_empty() and is_zero_approx(game.shake_amplitude()), "踏み切りでは砂ぼこりも揺れも出ない")
		_expect(not sparks.emitting, "ジャンプの空中では車輪の火花が出ない")
		await _frames_until(func() -> bool: return t.segment_id == "s2")
		await physics_frame
		var dust: Array = _of(fx, Puffs).filter(func(p: Puffs) -> bool: return p.kind == "dust")
		_expect(dust.size() == 1 and absf((dust[0] as Puffs).position.x - 1400.0) < 60.0, "ジャンプの着地で砂ぼこりが出る")
		var amp: float = game.shake_amplitude()
		_expect((amp > 0.0) == shake_on, "着地で小さく揺れる（揺れ %s: 振幅 %.1f）" % ["ON" if shake_on else "OFF", amp])
		await _frames(2)
		_expect(sparks.emitting, "着地したらまた火花が出る")
		game.free()
	return true


# ゴール: テープが切れて紙吹雪。「GOAL」を判子のように押す。止まったトロッコの火花とスピード線は消える
func _check_goal_fx() -> bool:
	var game: Node = _new_game(_straight([]))
	var t: Trolley = game._trolley
	t.fixed_speed = Tuning.SPEED_MAX
	var goals: Array = game._world.get_children().filter(func(n: Node) -> bool: return n is Goal)
	_expect(goals.size() == 1 and not (goals[0] as Goal).tape_cut, "ゴールにはテープが張ってある")
	_expect(Tuning.GOAL_TAPE_X >= Tuning.TROLLEY_TOP_W * 0.5,
			"テープは止まったトロッコの前の端より先にある（切れる前に車体がテープを通り抜けない）")
	await _frames_until(func() -> bool: return game._finished)
	_expect(game._message.scale.x > 1.0, "GOAL は大きく出てから等倍に押す（%.2f）" % game._message.scale.x)
	await physics_frame
	var paper: Array = _of(game.get_node("World/Effects"), Shards).filter(func(s: Shards) -> bool: return s.kind == "paper")
	_expect(goals.size() == 1 and (goals[0] as Goal).tape_cut and paper.size() == 1 and game._message.text == "GOAL",
			"ゴールに着くとテープが切れて紙吹雪が舞い、GOAL を出す")
	await _frames(3)
	var lines: SpeedLines = t.get_node("SpeedLines")
	_expect(not (t.get_node("WheelSparks") as CPUParticles2D).emitting and is_zero_approx(lines.amount),
			"ゴールで止まったら火花とスピード線は消える（線 %.2f）" % lines.amount)
	return true


# 演出をたくさん起こしても Effects の数は MAX_EFFECTS を超えない（古いものから消す）
func _check_fx_cap() -> bool:
	var game: Node = _new_game(_straight([]))
	var fx: Node2D = game.get_node("World/Effects")
	for i: int in Tuning.MAX_EFFECTS + 20:
		Fx.impact(fx, Vector2(i, 0), 100)
	await process_frame
	_expect(fx.get_child_count() <= Tuning.MAX_EFFECTS, "演出の数は %d まで（%d）" % [Tuning.MAX_EFFECTS, fx.get_child_count()])
	return true


# --- 共通 ---

## いちばん長い演出の寿命
func _fx_max_life() -> float:
	var lives: Array = [Tuning.IMPACT_LIFE, Tuning.FIREBALL_LIFE, Tuning.SHOCKWAVE_LIFE, Tuning.FLASH_LIFE]
	lives.append_array(Tuning.SHARD_LIFE.values())
	lives.append_array(Tuning.PUFF_LIFE.values())
	return lives.max()


func _straight(objects: Array) -> Dictionary:
	return {
		"id": "check", "name": "check", "ground_y": 900.0, "start_segment": "s0", "star_thresholds": [1, 2],
		"segments": {"s0": {"points": [[0, RAIL_Y], [4000, RAIL_Y]], "end": {"type": "goal"}}},
		"junctions": {}, "objects": objects}


func _obj(type: String, offset: float) -> Dictionary:
	return {"type": type, "segment": "s0", "offset": offset}


func _new_game(data: Dictionary) -> Node:
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.stage_data = data
	game.auto_pause = false  # 窓が無いのでフォーカスを失った扱いでポーズしないように
	root.add_child(game)
	_games.append(game)
	return game


## node の直下にある type の子
func _of(node: Node, type: Variant) -> Array:
	return node.get_children().filter(func(n: Node) -> bool: return is_instance_of(n, type))


func _frames(n: int) -> void:
	for _i: int in n:
		await physics_frame


func _frames_until(done: Callable) -> void:
	for _i: int in MAX_FRAMES:
		if done.call():
			return
		await physics_frame


func _remove_test_files() -> void:
	for path: String in [TEST_SETTINGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
