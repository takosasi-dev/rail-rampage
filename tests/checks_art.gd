extends SceneTree
## ① プレイ画面の絵の自動確認（設計書 docs/superpowers/specs/2026-09-26-play-screen-art-design.md の7章）。
## 書き出しには含めない。
## 実行: godot --headless --path . --fixed-fps 60 -s tests/checks_art.gd （失敗があれば終了コード1）
## 描画の関数のエラーは終了コードに出ないので、出力に「SCRIPT ERROR」が無いことも見る（README）。
## 設定・記録は確認用のファイルに差し替え、最後に消す（遊んでいる人の設定・記録を上書きしない）。
## 壊れた settings.cfg を読む確認は無い（型の違う値だけ）ので、ConfigFile の parse error は出ない。

const GAME_SCENE: String = "res://scenes/game.tscn"
const TEST_SETTINGS: String = "user://checks_art_settings.cfg"
const TEST_SAVE: String = "user://checks_art_save.cfg"
## C「見どころに合わせる」の割り当て（設計書4章）。第1〜5試験と、第6〜10試験（more-stages-design.md）
const STAGE_TOD: Array[String] = ["noon", "morning", "sunset", "night", "dusk", "dusk", "morning", "sunset", "noon", "night"]

var _failed: int = 0
# autoload。-s で動かすスクリプトは autoload より先に読み込まれ、名前（GameState など）では参照できない
var _game_state: Node
var _games: Array = []  # この確認で作ったゲーム（最後に消す。解放済みも入る）


func _initialize() -> void:
	_run.call_deferred()  # _initialize の時点では root がまだツリーに無く、_ready が走らない


func _run() -> void:
	_game_state = root.get_node("GameState")
	var real_settings: String = _game_state.settings_path
	var real_save: String = _game_state.save_path
	_game_state.settings_path = TEST_SETTINGS
	_game_state.save_path = TEST_SAVE
	_remove_test_files()
	_game_state.load_settings()
	_game_state.load_records()
	var checks: Array[Callable] = [_check_tod_by_number, _check_tod_resolve, _check_tod_validate, _check_tod_settings,
			_check_tod_presets, _check_gradient, _check_shapes, _check_shadow_node, _check_glow, _check_textures,
			_check_object_shadows, _check_draw_all, _check_towers, _check_track_nodes, _check_backdrop, _check_backdrop_coverage,
			_check_lamp_spots, _check_game_lighting, _check_headlight_fail, _check_retry_lighting, _check_emissive,
			_check_settings_time, _check_select_clock, _check_menu_texture, _check_backdrop_layout, _check_lamp_signs]
	for check: Callable in checks:
		# 各確認は最後に true を返す。スクリプトエラーで止まると null が返る
		if await check.call() != true:
			_expect(false, "%s が途中で止まった" % check.get_method())
		for game: Variant in _games:  # 型を付けると、解放済みのゲームを受けたときに止まる
			if is_instance_valid(game):
				(game as Node).free()
		_games.clear()
		_game_state.time_of_day_mode = "sequence"  # 次の確認に持ち越さない（保存はしない）
	_remove_test_files()
	_game_state.settings_path = real_settings
	_game_state.save_path = real_save
	_game_state.load_settings()
	_game_state.load_records()
	# 鳴っている効果音を止め、片付ける音声スレッドが回るまで少しだけ実時間で待つ（checks.gd と同じ）
	for p: Node in root.get_node("Audio").get_children():
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).stop()
	OS.delay_msec(200)
	await physics_frame
	await physics_frame
	print("失敗 %d 件" % _failed)
	quit(1 if _failed > 0 else 0)


# --- 時間帯（設計書4章） ---

# A「順に進む」: 5試験なら第N試験が N 番目。ほかの数でも5つを順に均等に割り当て、範囲外の番号は端に寄せる
func _check_tod_by_number() -> bool:
	var five: Array[String] = []
	for n: int in range(1, 6):
		five.append(TimeOfDay.by_number(n, 5))
	_expect(five == TimeOfDay.NAMES, "A: 5試験なら 朝・昼・夕方・夜の入り・深夜 の順（%s）" % [five])
	var seven: Array[String] = []
	for n: int in range(1, 8):
		seven.append(TimeOfDay.by_number(n, 7))
	var want7: Array[String] = ["morning", "morning", "noon", "sunset", "sunset", "dusk", "night"]
	_expect(seven == want7, "A: 7試験なら5つを均等に割り当てる（%s）" % [seven])
	var ten: Array[String] = []
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		ten.append(TimeOfDay.by_number(n, Tuning.STAGE_COUNT))
	var want10: Array[String] = ["morning", "morning", "noon", "noon", "sunset", "sunset", "dusk", "dusk", "night", "night"]
	_expect(ten == want10, "A: 今の %d 試験なら2つずつ（%s）" % [Tuning.STAGE_COUNT, ten])
	_expect(TimeOfDay.by_number(1, 1) == "morning" and TimeOfDay.by_number(9, 5) == "night"
			and TimeOfDay.by_number(0, 5) == "morning", "A: 範囲外の番号は端に寄せる")
	return true


# C「見どころに合わせる」: JSON の time_of_day を使い、無い・知らない名前・文字列でないときは A の値
func _check_tod_resolve() -> bool:
	var seq: String = TimeOfDay.MODE_SEQUENCE
	var stg: String = TimeOfDay.MODE_STAGE
	_expect(TimeOfDay.resolve(seq, 4, 5, {"time_of_day": "noon"}) == "dusk", "A は JSON の time_of_day を見ない")
	_expect(TimeOfDay.resolve(stg, 4, 5, {"time_of_day": "noon"}) == "noon", "C は JSON の time_of_day を使う")
	_expect(TimeOfDay.resolve(stg, 4, 5, {}) == "dusk", "C で time_of_day が無ければ A の値")
	_expect(TimeOfDay.resolve(stg, 4, 5, {"time_of_day": "evening"}) == "dusk"
			and TimeOfDay.resolve(stg, 4, 5, {"time_of_day": 3}) == "dusk", "C で知らない名前・文字列でない値なら A の値")
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		var data: Dictionary = StageLoader.load_json(_game_state.stage_path(n))
		_expect(TimeOfDay.resolve(stg, n, Tuning.STAGE_COUNT, data) == STAGE_TOD[n - 1],
				"第%d試験の C は %s（ステージの JSON）" % [n, STAGE_TOD[n - 1]])
	return true


# 6.4 に足した検証: time_of_day は省略できる。書いてあれば5つの名前のどれか（違反は1つ）
func _check_tod_validate() -> bool:
	var base: Dictionary = StageLoader.load_json(_game_state.stage_path(1))
	var errors: Array[String] = StageLoader.validate(base)
	_expect(errors.is_empty(), "time_of_day を書いたステージ1は検証を通る（%s）" % [errors])
	var none: Dictionary = base.duplicate(true)
	none.erase("time_of_day")
	_expect(StageLoader.validate(none).is_empty(), "time_of_day が無くても検証を通る（省略できる）")
	for bad: Variant in ["evening", 3, ""]:
		var d: Dictionary = base.duplicate(true)
		d["time_of_day"] = bad
		var e: Array[String] = StageLoader.validate(d)
		_expect(e.size() == 1 and e[0].begins_with("time_of_day"), "time_of_day = %s は違反を1つ出す（%s）" % [bad, e])
	return true


# 設定「時間帯」: 無ければ A。変えた瞬間に保存し、読み直しても残る。型の違う値・知らない値は A
func _check_tod_settings() -> bool:
	_game_state.load_settings()
	_expect(_game_state.time_of_day_mode == TimeOfDay.MODE_SEQUENCE, "設定ファイルが無ければ時間帯は A「順に進む」")
	_game_state.set_time_of_day_mode(TimeOfDay.MODE_STAGE)
	_expect(_saved("time_of_day_mode") == TimeOfDay.MODE_STAGE, "C に変えるとすぐ settings.cfg に保存する")
	_game_state.time_of_day_mode = TimeOfDay.MODE_SEQUENCE
	_game_state.load_settings()
	_expect(_game_state.time_of_day_mode == TimeOfDay.MODE_STAGE, "読み直しても C")
	_expect(_game_state.time_of_day(4, StageLoader.load_json(_game_state.stage_path(4))) == "night",
			"C の第4試験は深夜（GameState.time_of_day）")
	for bad: Variant in ["xyz", 1, true]:
		var cfg := ConfigFile.new()
		cfg.set_value(_game_state.SECTION, "time_of_day_mode", bad)
		cfg.save(TEST_SETTINGS)
		_game_state.load_settings()
		_expect(_game_state.time_of_day_mode == TimeOfDay.MODE_SEQUENCE, "time_of_day_mode = %s は A に戻る" % [bad])
	_game_state.set_time_of_day_mode("xyz")
	_expect(_game_state.time_of_day_mode == TimeOfDay.MODE_SEQUENCE, "知らない値を入れようとしても A になる")
	return true


# 5つの時間帯すべてに色・強さ・表示・時刻がそろい、全体の明るさは下限以上
func _check_tod_presets() -> bool:
	for tod: String in TimeOfDay.NAMES:
		var tables: Array = [Palette.TOD_AMBIENT, Palette.TOD_SKY, Palette.TOD_SHAFT, Tuning.TOD_LAMP, Tuning.TOD_SHAFT,
				Tuning.TOD_STARS, Tuning.TOD_GLOW, Tuning.TOD_HEADLIGHT, TimeOfDay.LABELS, TimeOfDay.CLOCKS]
		_expect(tables.all(func(d: Dictionary) -> bool: return d.has(tod)), "%s の色・強さ・表示・時刻がそろっている" % tod)
		var luma: float = (Palette.TOD_AMBIENT[tod] as Color).get_luminance()
		_expect(luma >= Tuning.TOD_AMBIENT_MIN_LUMA, "%s の全体の明るさ %.2f が下限 %.2f 以上" % [tod, luma, Tuning.TOD_AMBIENT_MIN_LUMA])
	return true


# --- 描画の共通部品（設計書2章・3章） ---

# ぼかしの切れ端: 合わせると元の形と同じ面積。始まりは最初の色、終わりは最後の色、中間の区切りにはその色の頂点
func _check_gradient() -> bool:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var red := Color(1, 0, 0)
	var green := Color(0, 1, 0)
	var blue := Color(0, 0, 1)
	var pieces: Array = DrawUtil.gradient_pieces(square, Vector2(0, 5), Vector2(10, 5), [red, blue], [0.0, 1.0])
	var area: float = 0.0
	var ends_ok: bool = true
	for piece: Array in pieces:
		var pts: PackedVector2Array = piece[0]
		var cols: PackedColorArray = piece[1]
		area += _poly_area(pts)
		for i: int in pts.size():
			if is_zero_approx(pts[i].x):
				ends_ok = ends_ok and cols[i].is_equal_approx(red)
			elif is_equal_approx(pts[i].x, 10.0):
				ends_ok = ends_ok and cols[i].is_equal_approx(blue)
	_expect(is_equal_approx(area, 100.0), "ぼかしの切れ端を合わせると元の形と同じ面積（%.3f）" % area)
	_expect(ends_ok, "ぼかしの始まりは最初の色、終わりは最後の色")
	var mid_ok: bool = false
	for piece: Array in DrawUtil.gradient_pieces(square, Vector2(0, 5), Vector2(10, 5), [red, green, blue], [0.0, 0.5, 1.0]):
		for i: int in (piece[0] as PackedVector2Array).size():
			if is_equal_approx(piece[0][i].x, 5.0) and (piece[1][i] as Color).is_equal_approx(green):
				mid_ok = true
	_expect(mid_ok, "色の区切り（0.5）で切り分け、そこにその色の頂点がある")
	var c: Array = [red, blue]
	var o: Array = [0.2, 0.8]
	_expect(DrawUtil.gradient_color(c, o, 0.0).is_equal_approx(red) and DrawUtil.gradient_color(c, o, 1.0).is_equal_approx(blue)
			and DrawUtil.gradient_color(c, o, 0.5).is_equal_approx(Color(0.5, 0, 0.5)), "区切りの外は端の色、間は線形")
	return true


# 角丸と楕円の点
func _check_shapes() -> bool:
	var r := Rect2(0, 0, 40, 56)
	var rr: PackedVector2Array = DrawUtil.rounded_rect(r, 6.0)
	_expect(rr.size() == 4 * (Tuning.ROUND_STEPS + 1) and Array(rr).all(func(p: Vector2) -> bool: return r.grow(0.001).has_point(p)),
			"角丸の点は角ごとに %d 点で、長方形からはみ出さない（%d 点）" % [Tuning.ROUND_STEPS + 1, rr.size()])
	_expect(DrawUtil.rounded_rect(r, 0.0).size() == 4, "角丸 0 は4点の長方形")
	var e: PackedVector2Array = DrawUtil.ellipse(Vector2(5, 5), Vector2(3, 2))
	_expect(e.size() == Tuning.CIRCLE_STEPS and e[0].is_equal_approx(Vector2(8, 5)), "楕円は %d 点で右端から始まる" % Tuning.CIRCLE_STEPS)
	return true


# 設計書2章: 影は親が回っても画面の右下（SHADOW_OFFSET）にずれ、壁のすぐ手前（Z_SHADOW、親に関係なく）に描く
func _check_shadow_node() -> bool:
	var parent := Node2D.new()
	parent.position = Vector2(100, 200)
	parent.rotation = PI * 0.5
	root.add_child(parent)
	var shape: Array[PackedVector2Array] = [PackedVector2Array([Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)])]
	var shadow: DropShadow = DropShadow.make(shape)
	parent.add_child(shadow)
	await process_frame
	_expect((shadow.global_position - parent.global_position).is_equal_approx(Tuning.SHADOW_OFFSET),
			"影は親が90度回っても右下 %s にずれる（%s）" % [Tuning.SHADOW_OFFSET, shadow.global_position - parent.global_position])
	parent.rotation = PI
	await process_frame
	_expect((shadow.global_position - parent.global_position).is_equal_approx(Tuning.SHADOW_OFFSET), "親が回り続けても影のずれは同じ")
	_expect(shadow.z_index == Tuning.Z_SHADOW and not shadow.z_as_relative, "影は Z_SHADOW（親の z に関係なく）")
	parent.free()
	return true


# 設計書4章: にじみは強さ 0 なら出さない。足し算で重ね、照明の影響を受けない
func _check_glow() -> bool:
	var off: Glow = Glow.make(10.0, Palette.STAMP, 0.0)
	var on: Glow = Glow.make(10.0, Palette.STAMP, 0.5)
	root.add_child(off)
	root.add_child(on)
	_expect(not off.visible and on.visible, "にじみは強さ 0 なら出さず、0 より大きければ出す")
	_expect(on.material == DrawUtil.additive and DrawUtil.additive.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD
			and DrawUtil.additive.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED, "にじみは足し算で、照明の影響を受けない")
	_expect(DrawUtil.unshaded.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED
			and DrawUtil.unshaded.blend_mode == CanvasItemMaterial.BLEND_MODE_MIX, "光る物の材質は照明の影響を受けない普通の重ね方")
	off.free()
	on.free()
	return true


# 雑音の模様は継ぎ目なしで、作るのは1回。円錐の絵は頂点の近くの中央が明るく、縁と遠くは暗い
func _check_textures() -> bool:
	for kind: String in ["blotch", "grain", "fleck"]:
		var t: NoiseTexture2D = DrawUtil.noise(kind)
		_expect(t.seamless and t.width == Tuning.NOISE_SIZE and DrawUtil.noise(kind) == t, "雑音の模様 %s は継ぎ目なし・%dpx・作るのは1回" % [kind, Tuning.NOISE_SIZE])
	var img: Image = DrawUtil.cone_image()
	var size := Vector2i(img.get_width(), Tuning.CONE_TEXTURE_H)
	var near_center: float = img.get_pixel(size.x / 2, size.y / 8).a
	var near_edge: float = img.get_pixel(0, size.y / 8).a
	var far_center: float = img.get_pixel(size.x / 2, size.y - 2).a
	_expect(img.get_size() == size and near_center > 0.5 and near_edge < 0.05 and far_center < 0.1,
			"円錐の絵: 頂点の近くの中央 %.2f・縁 %.2f・遠く %.2f" % [near_center, near_edge, far_center])
	# 最終レビュー 1: 円錐が絵の左右の端で切れると、光が四角い柱になる。どの行でも端の列はほぼ透明
	var edge_max: float = 0.0
	for y: int in img.get_height():
		edge_max = maxf(edge_max, maxf(img.get_pixel(0, y).a, img.get_pixel(img.get_width() - 1, y).a))
	_expect(edge_max < 0.02, "円錐の絵は左右の端で切れない（端の列の濃さの最大 %.3f）" % edge_max)
	_expect(DrawUtil.cone_texture() == DrawUtil.cone_texture() and DrawUtil.glow_texture() == DrawUtil.glow_texture(),
			"円錐とにじみの絵は作るのは1回")
	return true


# --- 標的とトロッコ（設計書3章） ---

# 標的・レンガ片・トロッコ・残骸は影（DropShadow）を持つ。ドラム缶だけ、にじみ（Glow）を持つ（強さ 0 なら出さない）
func _check_object_shadows() -> bool:
	var scenes: Dictionary = StageLoader.TARGET_SCENES.duplicate()
	scenes["brick_piece"] = load("res://scenes/objects/brick_piece.tscn")
	for kind: String in scenes:
		var t: Target = (scenes[kind] as PackedScene).instantiate()
		t.position = Vector2(300, 300)
		t.rotation = 0.6
		root.add_child(t)
		await process_frame
		var shadow: Node = t.get_node_or_null("Shadow")
		_expect(shadow is DropShadow and not (shadow as DropShadow).shapes.is_empty()
				and ((shadow as Node2D).global_position - t.global_position).is_equal_approx(Tuning.SHADOW_OFFSET),
				"%s は影を持ち、回っていても右下にずれる" % kind)
		var glow: Node = t.get_node_or_null("Glow")
		_expect((glow is Glow) == (kind == "drum") and (glow == null or not (glow as Glow).visible),
				"%s のにじみ: ドラム缶だけが持ち、強さ 0 のうちは出さない" % kind)
		t.free()
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2(0, 600))
	path.curve.add_point(Vector2(1000, 600))
	root.add_child(path)
	var trolley: Trolley = (load("res://scenes/objects/trolley.tscn") as PackedScene).instantiate()
	path.add_child(trolley)
	var wreck: Node = (load("res://scenes/objects/trolley_wreck.tscn") as PackedScene).instantiate()
	root.add_child(wreck)
	await process_frame
	_expect(trolley.get_node_or_null("Shadow") is DropShadow and wreck.get_node_or_null("Shadow") is DropShadow,
			"トロッコと、失敗して転がる残骸も影を持つ")
	path.free()
	wreck.free()
	return true


# 全種類の標的とトロッコを描く（描画のエラーは出力の SCRIPT ERROR で見る）。影の形は物の大きさに収まる
func _check_draw_all() -> bool:
	var canvas := Node2D.new()
	canvas.draw.connect(func() -> void:
		for kind: String in Tuning.TARGET_SIZE:
			Target.draw_shape(canvas, kind)
		Trolley.draw_body(canvas))
	root.add_child(canvas)
	await process_frame
	await process_frame
	for kind: String in Tuning.TARGET_SIZE:
		var s: Vector2 = Tuning.TARGET_SIZE[kind]
		var box := Rect2(-s.x * 0.5, -s.y, s.x, s.y).grow(0.5)
		var inside: bool = Target.silhouette(kind).all(func(shape: PackedVector2Array) -> bool:
			return Array(shape).all(func(p: Vector2) -> bool: return box.has_point(p)))
		_expect(not Target.silhouette(kind).is_empty() and inside, "%s の影の形は物の大きさ %s に収まる" % [kind, s])
	_expect(Trolley.silhouette().size() == 3, "トロッコの影は車体と車輪2つ")
	canvas.free()
	return true


# --- 線路・支柱・床（設計書2章） ---

# 支柱: ジャンプのセグメントには立てない。頭から TOWER_SPACING の半分、その先 TOWER_SPACING おき。上端は線路の上
func _check_towers() -> bool:
	var data: Dictionary = StageLoader.load_json(_game_state.stage_path(5))
	var spots: Array[Dictionary] = StageLoader.tower_spots(data)
	var on_jump: Array = spots.filter(func(s: Dictionary) -> bool: return data["segments"][s["segment"]].has("jump"))
	_expect(not spots.is_empty() and on_jump.is_empty(), "第5試験: 支柱 %d 本、ジャンプのセグメントには立てない" % spots.size())
	var s0: Array = spots.filter(func(s: Dictionary) -> bool: return s["segment"] == "s0").map(func(s: Dictionary) -> Vector2: return s["top"])
	var half: float = Tuning.TOWER_SPACING * 0.5
	var want: Array = [Vector2(half, 600), Vector2(half + Tuning.TOWER_SPACING, 600), Vector2(half + Tuning.TOWER_SPACING * 2, 600),
			Vector2(half + Tuning.TOWER_SPACING * 3, 600)]
	var same: bool = s0.size() == want.size() and range(want.size()).all(func(i: int) -> bool:
			return (s0[i] as Vector2).is_equal_approx(want[i]))
	_expect(same, "s0（長さ1800）の支柱は %s（%s）" % [want, s0])
	# 坂の後: s1 は (1800,600)→(2000,500)（長さ 223.6）→ 水平。最初の支柱は水平の所の 16.4px 先
	var s1_first: Vector2 = spots.filter(func(s: Dictionary) -> bool: return s["segment"] == "s1")[0]["top"]
	_expect(s1_first.is_equal_approx(Vector2(2000.0 + half - Vector2(200, 100).length(), 500.0)),
			"坂を越えた先の支柱の位置も線路の上（%s）" % s1_first)
	return true


# ゲーム画面を組むと、支柱と影・各線路のレールと影・床の模様の敷き詰めが付く
func _check_track_nodes() -> bool:
	var game: Node = _new_game(StageLoader.load_json(_game_state.stage_path(5)))
	await process_frame
	var world: Node2D = game._world
	var towers: Node2D = world.get_node_or_null("Towers")
	var tower_shadows: Node2D = world.get_node_or_null("TowerShadows")
	_expect(towers != null and towers.z_index == Tuning.Z_TOWER and tower_shadows != null
			and tower_shadows.z_index == Tuning.Z_SHADOW and not tower_shadows.z_as_relative, "支柱（Z_TOWER）とその影（Z_SHADOW）")
	var rails_ok: bool = true
	for id: String in game.stage_data["segments"]:
		var rail: Node = world.get_node_or_null("%s/Rail" % id)
		var shadow: Node2D = world.get_node_or_null("%s/Rail/Shadow" % id)
		rails_ok = rails_ok and rail != null and shadow != null and shadow.z_index == Tuning.Z_SHADOW and not shadow.z_as_relative
	_expect(rails_ok, "どのセグメントにもレール（Rail）と、その影（Z_SHADOW）がある")
	# 最終レビュー 3: 床と支柱はステージ全体を1つに描かず、WORLD_CHUNK_W ごとの塊に分ける（画面の外の塊は描かない）
	var ground_chunks: Array[Node] = world.get_node("Ground/Visual").get_children()
	_expect(ground_chunks.size() > 1 and ground_chunks.all(func(c: Node) -> bool:
			return (c as CanvasItem).texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED),
			"床は %d 個の塊に分けて描き、どれも模様を敷き詰められる（texture_repeat）" % ground_chunks.size())
	_expect(towers.get_child_count() > 1 and tower_shadows.get_child_count() == towers.get_child_count(),
			"支柱と影も塊に分けて描く（%d 個）" % towers.get_child_count())
	var ranges: Array[Vector2] = StageLoader.chunk_ranges(-3000.0, 29800.0)
	var contiguous: bool = true
	for i: int in ranges.size():
		contiguous = contiguous and is_equal_approx(ranges[i].y - ranges[i].x, Tuning.WORLD_CHUNK_W) \
				and (i == 0 or is_equal_approx(ranges[i].x, ranges[i - 1].y))
	_expect(contiguous and ranges[0].x <= -3000.0 and ranges[-1].y >= 29800.0 and is_zero_approx(fmod(ranges[0].x, Tuning.WORLD_CHUNK_W)),
			"塊は %dpx ずつ、すき間なく左右の端まで覆う（%d 個）" % [Tuning.WORLD_CHUNK_W, ranges.size()])
	_expect(is_zero_approx(fmod(Tuning.WORLD_CHUNK_W, Tuning.NOISE_SIZE)) and is_zero_approx(fmod(Tuning.WORLD_CHUNK_W, Tuning.CURB_STRIPE_W * 2.0)),
			"塊の幅は雑音の模様と縁石の縞の倍数（塊の継ぎ目で模様がずれない）")
	_expect(is_equal_approx(Tuning.PX_PER_METER, Tuning.DISPLAY_SPEED_DIV * 3.6), "距離の目盛りは速度表示と同じ換算（36px = 1m）")
	# 最終レビュー 3: 重さを依頼者の PC で見られるよう、デバッグ表示（FR-54）に1フレームの描画命令の数も出す
	await process_frame
	var debug_text: String = (game._debug_label as Label).text
	_expect(debug_text.contains("FPS") and debug_text.contains("DRAW"), "デバッグ表示に FPS と描画命令の数（DRAW）が出る（%s）" % debug_text.replace("\n", " / "))
	return true


# --- 奥の壁（設計書2章） ---

# 線路の 0.85 倍で横に流れ、1枚を横に繰り返す。空と差し込む光は光る物。星は夜の入りと深夜だけ、差し込む光は朝・昼・夕方だけ
func _check_backdrop() -> bool:
	for tod: String in ["sunset", "night"]:
		var b := Backdrop.new()
		b.ground_y = 900.0
		b.tod = tod
		root.add_child(b)
		await process_frame
		_expect(is_equal_approx(b.scroll_scale.x, Tuning.BACKDROP_SCROLL) and is_equal_approx(b.scroll_scale.y, 1.0)
				and is_equal_approx(b.repeat_size.x, Tuning.BACKDROP_TILE_W) and b.z_index == Tuning.Z_BACKDROP,
				"%s: 壁は横 %.2f 倍・縦は線路と同じに流れ、%dpx ごとに繰り返す" % [tod, Tuning.BACKDROP_SCROLL, Tuning.BACKDROP_TILE_W])
		_expect((b.get_node("Sky") as CanvasItem).material == DrawUtil.unshaded
				and (b.get_node("Shafts") as CanvasItem).material == DrawUtil.additive, "%s: 窓の空は光る物、差し込む光は足し算" % tod)
		_expect((b.get_node("Shafts") as CanvasItem).visible == (Tuning.TOD_SHAFT[tod] > 0.0), "%s: 差し込む光は濃さが 0 なら出さない" % tod)
		_expect((b.get_node("Base") as CanvasItem).texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED, "%s: 壁は模様を敷き詰められる" % tod)
		var wins: Array[Rect2] = b.windows()
		_expect(not wins.is_empty() and wins.all(func(w: Rect2) -> bool:
				return is_equal_approx(w.end.y, 900.0 - Tuning.WINDOW_BOTTOM) and w.end.x <= Tuning.BACKDROP_TILE_W),
				"%s: 窓 %d 枚は床から %dpx の高さで、1枚の中に収まる" % [tod, wins.size(), Tuning.WINDOW_BOTTOM])
		b.free()
	_expect(fmod(Tuning.BACKDROP_TILE_W, 200.0) == 0.0 and fmod(Tuning.BACKDROP_TILE_W, Tuning.PANEL_W) == 0.0,
			"1枚の幅は方眼（200px）とパネルの幅の倍数（繰り返しの継ぎ目で方眼がずれない）")
	return true


# Review Focus: 一番引いたズーム（ZOOM_MIN。一番速い車両の最高速）でも、壁が画面の横を覆い、どのステージでも上にすき間が出ない
func _check_backdrop_coverage() -> bool:
	var view: Vector2 = Vector2(1280, 720) / Tuning.ZOOM_MIN
	_expect(Tuning.BACKDROP_TILE_W * Tuning.BACKDROP_REPEAT >= view.x + Tuning.BACKDROP_TILE_W,
			"繰り返し %d 枚で、最も広い画面の横 %.0fpx を覆う" % [Tuning.BACKDROP_REPEAT, view.x])
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		var data: Dictionary = StageLoader.load_json(_game_state.stage_path(n))
		var top_track: float = INF
		for seg: Dictionary in (data["segments"] as Dictionary).values():
			for p: Array in seg["points"]:
				top_track = minf(top_track, p[1])
		# カメラの縦はトロッコに付いてくる。一番高い線路にいるとき、画面の上端は線路から画面の高さ × CAMERA_TROLLEY_SCREEN_Y 上
		var need: float = data["ground_y"] - (top_track - view.y * Tuning.CAMERA_TROLLEY_SCREEN_Y)
		_expect(Tuning.BACKDROP_H >= need, "第%d試験: 壁の高さ %.0f は、一番高い線路での画面の上端まで %.0f 以上" % [n, Tuning.BACKDROP_H, need])
	return true


# --- 照明と時間帯（設計書4章） ---

# 照明器具は LAMP_FIRST_X から LAMP_SPACING おきに、前後 LAMP_REACH の一番高い線路より LAMP_CLEARANCE 上
func _check_lamp_spots() -> bool:
	var data: Dictionary = StageLoader.load_json(_game_state.stage_path(5))
	var spots: Array[Vector2] = StageLoader.lamp_spots(data)
	var spaced: bool = true
	for i: int in range(1, spots.size()):
		spaced = spaced and is_equal_approx(spots[i].x - spots[i - 1].x, Tuning.LAMP_SPACING)
	_expect(not spots.is_empty() and is_equal_approx(spots[0].x, Tuning.LAMP_FIRST_X) and spaced,
			"照明器具 %d 個は %dpx から %dpx おき" % [spots.size(), Tuning.LAMP_FIRST_X, Tuning.LAMP_SPACING])
	_expect(is_equal_approx(spots[0].y, 600.0 - Tuning.LAMP_CLEARANCE), "スタート近くは高さ 600 の線路の %dpx 上" % Tuning.LAMP_CLEARANCE)
	# 第5試験の1つ目のジャンプの頂点は (6850, 380)。その前後 LAMP_REACH にある照明器具は、頂点より上
	var near_jump: Array = spots.filter(func(p: Vector2) -> bool: return absf(p.x - 6850.0) <= Tuning.LAMP_REACH)
	_expect(not near_jump.is_empty() and near_jump.all(func(p: Vector2) -> bool: return p.y <= 380.0 - Tuning.LAMP_CLEARANCE + 0.01),
			"ジャンプの空中の軌道の近くでは、軌道の頂点より上に吊る（%s）" % [near_jump])
	return true


# A と C で時間帯が決まり、全体の色・壁・照明器具・前照灯・ドラム缶のにじみがその時間帯になる
func _check_game_lighting() -> bool:
	for c: Array in [[TimeOfDay.MODE_SEQUENCE, 7, "dusk"], [TimeOfDay.MODE_STAGE, 4, "night"], [TimeOfDay.MODE_SEQUENCE, 3, "noon"]]:
		_game_state.time_of_day_mode = c[0]
		var game: Node = _new_game(StageLoader.load_json(_game_state.stage_path(c[1])))
		await process_frame
		var tod: String = c[2]
		_expect(game.time_of_day == tod, "%s の第%d試験は %s（%s）" % [c[0], c[1], tod, game.time_of_day])
		var ambient: Node = game.get_node_or_null("Ambient")
		_expect(ambient is CanvasModulate and (ambient as CanvasModulate).color == Palette.TOD_AMBIENT[tod], "%s: 全体に掛ける色" % tod)
		_expect((game.get_node("Backdrop") as Backdrop).tod == tod, "%s: 壁の空も同じ時間帯" % tod)
		var head: PointLight2D = game._trolley.headlight
		var head_on: bool = Tuning.TOD_HEADLIGHT[tod] > 0.0
		_expect(head.enabled == head_on and is_equal_approx(head.energy, Tuning.TOD_HEADLIGHT[tod] * Tuning.HEADLIGHT_ENERGY),
				"%s: 前照灯は %s（強さ %.2f）" % [tod, "点く" if head_on else "消えている", head.energy])
		var lamps: Array[Node] = game.get_node("World/Lamps").get_children()
		var lamp_on: bool = Tuning.TOD_LAMP[tod] > 0.0
		_expect(lamps.size() == StageLoader.lamp_spots(game.stage_data).size()
				and lamps.all(func(l: Node) -> bool: return (l.get_node("Light") as PointLight2D).enabled == lamp_on),
				"%s: 照明器具 %d 個は%s" % [tod, lamps.size(), "点いている" if lamp_on else "消えている"])
		var drums: Array = game._targets.filter(func(t: Target) -> bool: return t.kind == "drum")
		_expect(drums.all(func(t: Target) -> bool:
				var g: Glow = t.get_node("Glow")
				return is_equal_approx(g.strength, Tuning.TOD_GLOW[tod]) and g.visible == (Tuning.TOD_GLOW[tod] > 0.0)),
				"%s: ドラム缶 %d 個のにじみの強さ" % [tod, drums.size()])
		game.free()
	return true


# 設計書4章: 失敗して転がるトロッコ（残骸）では前照灯が消える
func _check_headlight_fail() -> bool:
	_game_state.time_of_day_mode = TimeOfDay.MODE_STAGE
	var game: Node = _new_game(StageLoader.load_json(_game_state.stage_path(4)))  # 深夜
	await process_frame
	_expect(game._trolley.headlight.is_visible_in_tree(), "深夜は走っている間、前照灯が点いている")
	game._fail("激突", 700.0)
	await process_frame
	_expect(not game._trolley.headlight.is_visible_in_tree() and game._wreck.find_children("*", "PointLight2D", true, false).is_empty(),
			"失敗するとトロッコは隠れて前照灯も消え、残骸には前照灯が無い")
	return true


# Review Focus: リトライしても照明器具・影が増えない（新しい画面は組み直し、古い画面は消える）
func _check_retry_lighting() -> bool:
	_game_state.time_of_day_mode = TimeOfDay.MODE_STAGE
	var game: Node = _new_game(StageLoader.load_json(_game_state.stage_path(4)))
	await process_frame
	var lamps: int = game.get_node("World/Lamps").get_child_count()
	var fresh: Node = game
	for _i: int in 3:
		fresh._last_retry = -INF  # 連打よけ（RETRY_DEBOUNCE）に掛からないように
		fresh = fresh.retry()
		_games.append(fresh)
		await process_frame
		await process_frame
	var ambients: int = 0
	for n: Node in root.get_children():
		ambients += n.find_children("*", "CanvasModulate", true, false).size()
	_expect(is_instance_valid(fresh) and fresh.is_inside_tree() and fresh.get_node("World/Lamps").get_child_count() == lamps
			and ambients == 1, "リトライ3回の後も照明器具は %d 個、全体の色（CanvasModulate）は1つ（%d）" % [lamps, ambients])
	return true


# Review Focus: 暗い時間帯でも本来の明るさで見える物（光る物）は、照明の影響を受けない材質
func _check_emissive() -> bool:
	_game_state.time_of_day_mode = TimeOfDay.MODE_STAGE
	var game: Node = _new_game(StageLoader.load_json(_game_state.stage_path(3)))  # 夕方。壁と標識がある
	await process_frame
	var j: Junction = game._junctions.values()[0]
	_expect(j.visual.material == DrawUtil.unshaded, "分岐（円盤・矢印・選んだ線路の破線）は光る物")
	var signs: Array = game._world.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is SpeedSign)
	var signs_ok: bool = not signs.is_empty()
	for s: SpeedSign in signs:
		signs_ok = signs_ok and s.material == DrawUtil.unshaded \
				and is_equal_approx((s.get_node("Glow") as Glow).strength, Tuning.TOD_GLOW["sunset"])
	_expect(signs_ok, "必要速度の標識 %d 枚は光る物で、夕方のにじみを持つ" % signs.size())
	# 最終レビュー 2: 設計書4章の光る物にはドラム缶も入る（本体も本来の明るさ。周りに赤いにじみ）
	var drum: Target = (StageLoader.TARGET_SCENES["drum"] as PackedScene).instantiate()
	game._world.add_child(drum)
	var crate: Target = (StageLoader.TARGET_SCENES["crate"] as PackedScene).instantiate()
	game._world.add_child(crate)
	_expect(drum.visual.material == DrawUtil.unshaded and crate.visual.material == null,
			"ドラム缶の本体は光る物（ほかの標的は照明を受ける）")
	for path: String in ["res://scenes/ui/score_popup.tscn", "res://scenes/ui/girigiri.tscn", "res://scenes/ui/first_hint.tscn"]:
		var n: CanvasItem = (load(path) as PackedScene).instantiate()
		game._world.add_child(n)
		_expect(n.material == DrawUtil.unshaded, "%s は光る物（暗い時間帯でも読める）" % path.get_file())
	return true


# --- 設定の「時間帯」とステージ選択の試験時刻（設計書5章） ---

# 設定画面: 「順に進む」「見どころに合わせる」の2つ。選んでいる側が墨地になり、押した瞬間に保存する
func _check_settings_time() -> bool:
	_game_state.set_time_of_day_mode(TimeOfDay.MODE_SEQUENCE)
	var s: Control = (load("res://scenes/settings.tscn") as PackedScene).instantiate()
	root.add_child(s)
	await process_frame
	var seq: Button = s.get_node("%TimeSequence")
	var stg: Button = s.get_node("%TimeStage")
	_expect(seq.text == "順に進む" and stg.text == "見どころに合わせる", "設定の時間帯のボタン（%s／%s）" % [seq.text, stg.text])
	_expect(_bg(seq) == Palette.INK and _bg(stg) == Palette.PAPER, "A のときは「順に進む」が墨地")
	stg.pressed.emit()
	_expect(_game_state.time_of_day_mode == TimeOfDay.MODE_STAGE and _saved("time_of_day_mode") == TimeOfDay.MODE_STAGE
			and _bg(stg) == Palette.INK and _bg(seq) == Palette.PAPER, "「見どころに合わせる」を押すと C になり、すぐ保存し、墨地が移る")
	s.free()
	return true


# ステージ選択: カードの見出しに試験時刻、詳細パネルに「HH:MM（時間帯）」。設定の A／C に従う
func _check_select_clock() -> bool:
	for c: Array in [[TimeOfDay.MODE_SEQUENCE, "第5試験・17:30", "17:30（夕方）"], [TimeOfDay.MODE_STAGE, "第1試験・12:00", "12:00（昼）"]]:
		_game_state.time_of_day_mode = c[0]
		var s: Control = (load("res://scenes/stage_select.tscn") as PackedScene).instantiate()
		root.add_child(s)
		await process_frame
		var n: int = 5 if c[0] == TimeOfDay.MODE_SEQUENCE else 1
		var num: Label = s.get_node("Cards").get_child(n - 1).get_node("Body/Num")
		_expect(num.text == c[1], "%s: 第%d試験のカードの見出しは「%s」（%s）" % [c[0], n, c[1], num.text])
		var tod: String = _game_state.time_of_day(s.selected, s._stages[s.selected - 1])
		var want_detail: String = "%s（%s）" % [TimeOfDay.CLOCKS[tod], TimeOfDay.LABELS[tod]]
		_expect((s.get_node("%TimeValue") as Label).text == want_detail, "%s: 詳細パネルの試験時刻は「%s」" % [c[0], want_detail])
		s.free()
	return true


# --- メニューの質感（設計書5章） ---

# 粒の模様を敷き詰める画面・パネルは texture_repeat を有効にしている（無いと模様が引き伸ばされる）
func _check_menu_texture() -> bool:
	var cases: Array = [["res://scenes/title.tscn", "."], ["res://scenes/settings.tscn", "."], ["res://scenes/settings.tscn", "Panel"],
			["res://scenes/pause_menu.tscn", "Panel"], ["res://scenes/stage_select.tscn", "."]]
	for c: Array in cases:
		var s: Node = (load(c[0]) as PackedScene).instantiate()
		root.add_child(s)
		await process_frame
		_expect((s.get_node(c[1]) as CanvasItem).texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED,
				"%s の %s は粒の模様を敷き詰められる" % [c[0].get_file(), c[1]])
		s.free()
	var r: Control = (load("res://scenes/result.tscn") as PackedScene).instantiate()
	r.setup({"stage": 1, "stage_name": "check", "cleared": true, "score": 100, "smashed": 1, "total": 1, "max_combo": 1,
			"max_speed": 500.0, "girigiri": 0, "stars": 1, "thresholds": [1000, 2000], "best_updated": false, "is_last": false,
			"fail_reason": "", "required_speed": 0.0, "reached_speed": 0.0})
	root.add_child(r)
	await process_frame
	_expect(r.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED and r._report.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED,
			"リザルトの背景と報告書は粒の模様を敷き詰められる")
	r.free()
	return true


# --- ①の後回し分（最終レビューの Minor） ---

# 計測マーカーは窓（枠を含む）と重ならない（重なると後から描く空に隠れる）。方眼の縦線は1枚の右端に引かない
# （引くと次の1枚の左端の線と重なって、繰り返しの継ぎ目で線が二重になる）
func _check_backdrop_layout() -> bool:
	var b := Backdrop.new()
	b.ground_y = 900.0
	var hidden: Array = []
	for m: Vector2 in Tuning.BACKDROP_MARKERS:
		var c := Vector2(m.x, 900.0 - m.y)
		var box := Rect2(c - Vector2.ONE * Tuning.MARKER_R, Vector2.ONE * Tuning.MARKER_R * 2.0)
		for w: Rect2 in b.windows():
			if box.intersects(w.grow(Tuning.WINDOW_FRAME_W)):
				hidden.append(m)
	_expect(hidden.is_empty(), "計測マーカーは窓と重ならない（重なる: %s）" % [hidden])
	var xs: Array[float] = Backdrop.grid_xs(Tuning.BACKDROP_TILE_W)
	_expect(not xs.is_empty() and is_zero_approx(xs[0]) and xs.back() < Tuning.BACKDROP_TILE_W,
			"方眼の縦線は 0 から、1枚の右端（%d）の手前まで（最後 %.0f）" % [Tuning.BACKDROP_TILE_W, xs.back()])
	b.free()
	return true


# 照明器具は、近くの必要速度の標識（判断材料、L-3）より上に吊る。今の5ステージと、標識が照明器具の真下に来る仮のコース
func _check_lamp_signs() -> bool:
	var straight: Dictionary = {"segments": {"s0": {"points": [[0, 600.0], [4000, 600.0]], "end": {"type": "goal"}}},
			"objects": [{"type": "wall", "segment": "s0", "offset": Tuning.LAMP_FIRST_X, "required_speed": 700.0}]}
	var stages: Array[Dictionary] = [straight]
	for n: int in range(1, Tuning.STAGE_COUNT + 1):
		stages.append(StageLoader.load_json(_game_state.stage_path(n)))
	for data: Dictionary in stages:
		var bad: Array = []
		for top: Vector2 in _sign_tops(data):
			for lamp: Vector2 in StageLoader.lamp_spots(data):
				if absf(lamp.x - top.x) <= Tuning.LAMP_REACH and lamp.y > top.y - Tuning.LAMP_SIGN_GAP:
					bad.append([lamp, top])
		_expect(bad.is_empty(), "%s: 照明器具は近くの標識の上端より %dpx 以上上（重なる: %s）" % [
				data.get("id", "仮のコース"), Tuning.LAMP_SIGN_GAP, bad])
	return true


## ステージの必要速度の標識の上端（壁の上と、ジャンプの始まりの上）
func _sign_tops(data: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var wall_h: float = (Tuning.TARGET_SIZE["wall"] as Vector2).y
	for od: Dictionary in data.get("objects", []):
		if od["type"] == "wall":
			var at: Vector2 = StageLoader._point_at(data["segments"][od["segment"]]["points"], float(od["offset"]))
			out.append(at - Vector2(0.0, wall_h + Tuning.SIGN_WALL_GAP + Tuning.SIGN_SIZE.y))
	for seg: Dictionary in (data["segments"] as Dictionary).values():
		if seg.has("jump"):
			var start: Vector2 = StageLoader._point(seg["points"][0])
			out.append(start - Vector2(0.0, Tuning.SIGN_JUMP_HEIGHT + Tuning.SIGN_SIZE.y))
	return out


# --- 共通 ---

## ボタンの地の色（地なしなら透明）
func _bg(b: Button) -> Color:
	var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
	return sb.bg_color if sb != null and sb.draw_center else Color(0, 0, 0, 0)


func _poly_area(poly: PackedVector2Array) -> float:
	var twice: float = 0.0
	for i: int in poly.size():
		twice += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(twice) * 0.5


func _new_game(data: Dictionary) -> Node:
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.stage_data = data
	game.auto_pause = false  # 窓が無いのでフォーカスを失った扱いでポーズしないように
	root.add_child(game)
	_games.append(game)
	return game


## 確認用の settings.cfg に保存されている値（読めなければ null）
func _saved(key: String) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(TEST_SETTINGS) != OK:
		return null
	return cfg.get_value(_game_state.SECTION, key, null)


func _remove_test_files() -> void:
	for path: String in [TEST_SETTINGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(ok: bool, label: String) -> void:
	print(("OK  " if ok else "NG  ") + label)
	if not ok:
		_failed += 1
