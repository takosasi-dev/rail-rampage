class_name Achievements
## 検定印（設計書 docs/superpowers/specs/2026-09-26-records-design.md の 2.3）。名前と条件、取ったかの判定。
## GameState を参照しない（-s の確認スクリプトから型名で使えるように）。判定に要るものは引数で受け取る。
## 依頼者の判断を待たずに決めた（名前・条件・数値は試遊の後に見直す）

## 走行が無くても、試験の合格と★だけで決まる印（検定印が入る前の記録を読んだときにも付ける）
const PROGRESS: Array[String] = ["basic", "all_clear", "full_marks", "all_stars", "license_standard", "license_heavy",
	"license_light", "license_blast", "license_prototype", "ex_first", "ex_all", "gold_first", "gold_all", "challenge10",
	"challenge_all", "level10", "level_max", "endless_5km"]
## [id, 名前, 条件]。この順に並べて見せる。条件の {…} は describe() が数値を入れる
const LIST: Array = [
	["basic", "基礎課程修了", "第1〜{basic_last}試験にすべて合格する"],
	["all_clear", "全課程修了", "第1〜{stages}試験にすべて合格する"],
	["full_marks", "満点答案", "どれかの試験で★{stars_max}を取る"],
	["all_stars", "全★制覇", "★を{stars_all}個すべて集める"],
	["combo_max", "倍率上限", "1回の走行でコンボ倍率が{combo_mult}に届く"],
	["chain", "連鎖反応", "1回の走行で、爆発に巻き込まれたドラム缶が{chain}個以上爆発する"],
	["girigiri", "紙一重", "ギリギリ突破を累計{girigiri}回する"],
	["top_speed", "最高速度", "最高速度（{top_speed}km/h）に届く"],
	["no_toggle", "初志貫徹", "一度も分岐を切り替えずに合格する"],
	["big_score", "大台", "1回の走行で{big_score}点を取って合格する"],
	["first_crash", "激突の記録", "壁に激突する"],
	["first_derail", "脱線の記録", "ジャンプ台で脱線する"],
	["dummy100", "人形百体", "ダミー人形を累計{dummy}体飛ばす"],
	["drum50", "花火師", "ドラム缶を累計{drum}個爆発させる"],
	["wall30", "解体業者", "レンガ壁を累計{wall}枚崩す"],
	["smash1000", "千個破壊", "標的を累計{smash}個壊す"],
	# やりこみ要素（設計書 docs/superpowers/specs/2026-09-28-replay-value-design.md の8章）
	["license_standard", "標準型免許", "標準型で第1〜{stages}試験にすべて合格する"],
	["license_heavy", "重量型免許", "重量型で第1〜{stages}試験にすべて合格する"],
	["license_light", "軽量型免許", "軽量型で第1〜{stages}試験にすべて合格する"],
	["license_blast", "発破型免許", "発破型で第1〜{stages}試験にすべて合格する"],
	["license_prototype", "試作型免許", "試作型で第1〜{stages}試験にすべて合格する"],
	["ex_first", "裏口", "裏試験のどれかに合格する"],
	["ex_all", "裏課程修了", "裏試験{ex}つすべてに合格する"],
	["gold_first", "金賞", "金★を取る"],
	["gold_all", "金字塔", "第1〜{stages}試験のすべてで金★を取る"],
	["challenge10", "課題提出", "課題を累計{challenges}個達成する"],
	["challenge_all", "皆勤", "課題を{challenges_all}個すべて達成する"],
	["level10", "熟練工", "どれかの車両の熟練度を{level}段にする"],
	["level_max", "名工", "どれかの車両の熟練度を{level_max}段（最大）にする"],
	["endless_5km", "長距離運転", "無限軌道で1回に{endless}走る"],
]


## have（取った印の id → 日）に無く、今の状態で条件を満たす印の id を LIST の順に返す。
## run: この走行の記録（設計書 2.2）。stats: この走行を足した後の累計（2.1）。
## progress: {"cleared": 試験ごとの合格（試験番号 - 1 の順）, "stars": 試験ごとの★}
static func newly_earned(have: Dictionary, run: Dictionary, stats: Dictionary, progress: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for a: Array in LIST:
		if not have.has(a[0]) and earned(a[0], run, stats, progress):
			out.append(a[0])
	return out


static func earned(id: String, run: Dictionary, stats: Dictionary, progress: Dictionary) -> bool:
	var cleared: Array = progress["cleared"]
	var stars: Array = progress["stars"]
	# 合格の走行は、その試験の合格が記録されているときだけ数える（走行中に記録を消し、まだ解放されていない試験に
	# ゴールしたときは記録されない）
	var stage: int = run.get("stage", 0)
	var passed: bool = run.get("passed", run["outcome"] == "clear" and stage >= 1 and stage <= cleared.size() and cleared[stage - 1])
	var smashed: Dictionary = stats["smashed"]
	match id:
		"basic":
			return cleared.slice(0, Tuning.ACH_BASIC_LAST).all(func(c: bool) -> bool: return c)
		"all_clear":
			return cleared.all(func(c: bool) -> bool: return c)
		"full_marks":
			return stars.any(func(s: int) -> bool: return s >= Tuning.STARS_MAX)
		"all_stars":
			return stars.all(func(s: int) -> bool: return s >= Tuning.STARS_MAX)
		"combo_max":
			return run["max_combo"] >= Tuning.ACH_COMBO
		"chain":
			return run["chained"] >= Tuning.ACH_CHAIN
		"girigiri":
			return stats["girigiri"] >= Tuning.ACH_GIRIGIRI
		"top_speed":
			return run["max_speed"] >= Tuning.SPEED_MAX - Tuning.ACH_TOP_SPEED_SLACK
		"no_toggle":
			return passed and run["toggles"] == 0
		"big_score":
			return passed and run["score"] >= Tuning.ACH_BIG_SCORE
		"first_crash":
			return run["outcome"] == "crash"
		"first_derail":
			return run["outcome"] == "derail"
		"dummy100":
			return smashed["dummy"] >= Tuning.ACH_DUMMY
		"drum50":
			return smashed["drum"] >= Tuning.ACH_DRUM
		"wall30":
			return smashed["wall"] >= Tuning.ACH_WALL
		"smash1000":
			return (smashed.values() as Array).reduce(func(sum: int, c: int) -> int: return sum + c, 0) >= Tuning.ACH_SMASH
		"ex_first":
			return (progress.get("ex_cleared", []) as Array).has(true)
		"ex_all":
			var ex: Array = progress.get("ex_cleared", [])
			return not ex.is_empty() and not ex.has(false)
		"gold_first":
			return (progress.get("gold", []) as Array).has(true) or _any_ex_gold(progress)
		"gold_all":
			var gold: Array = progress.get("gold", [])
			return not gold.is_empty() and not gold.has(false)
		"challenge10":
			return progress.get("challenges", 0) >= Tuning.ACH_CHALLENGES
		"challenge_all":
			return progress.get("challenges", 0) >= progress.get("challenges_total", INF)
		"level10":
			return progress.get("max_level", 1) >= Tuning.ACH_LEVEL
		"level_max":
			return progress.get("max_level", 1) >= Tuning.LEVEL_MAX
		"endless_5km":
			return progress.get("endless_distance", 0.0) >= Tuning.ACH_ENDLESS_DISTANCE \
					or (stage == 0 and run.get("distance", 0.0) >= Tuning.ACH_ENDLESS_DISTANCE)
	if id.begins_with("license_"):
		return (progress.get("licenses", {}) as Dictionary).get(id.trim_prefix("license_"), false)
	return false


## 裏試験の金★（progress の "ex_gold"。無ければ false）
static func _any_ex_gold(progress: Dictionary) -> bool:
	return (progress.get("ex_gold", []) as Array).has(true)


## 印の名前（知らない id は ""）
static func name_of(id: String) -> String:
	var a: Array = _entry(id)
	return a[1] if not a.is_empty() else ""


## 印の条件の文（数値を入れたもの。知らない id は ""）
static func describe(id: String) -> String:
	var a: Array = _entry(id)
	if a.is_empty():
		return ""
	return (a[2] as String).format({
		"basic_last": Tuning.ACH_BASIC_LAST,
		"stages": Tuning.STAGE_COUNT,
		"stars_max": Tuning.STARS_MAX,
		"stars_all": Tuning.STAGE_COUNT * Tuning.STARS_MAX,
		"combo_mult": "x%.1f" % Tuning.COMBO_MULT_MAX,
		"chain": Tuning.ACH_CHAIN,
		"girigiri": Tuning.ACH_GIRIGIRI,
		"top_speed": Display.to_display_speed(Tuning.SPEED_MAX),
		"big_score": Display.score_text(Tuning.ACH_BIG_SCORE),
		"dummy": Tuning.ACH_DUMMY,
		"drum": Tuning.ACH_DRUM,
		"wall": Tuning.ACH_WALL,
		"smash": Display.score_text(Tuning.ACH_SMASH),
		"ex": Tuning.EX_COUNT,
		"challenges": Tuning.ACH_CHALLENGES,
		"challenges_all": (Tuning.STAGE_COUNT + Tuning.EX_COUNT) * Tuning.CHALLENGE_COUNT,
		"level": Tuning.ACH_LEVEL,
		"level_max": Tuning.LEVEL_MAX,
		"endless": Display.distance_text(Tuning.ACH_ENDLESS_DISTANCE),
	})


static func has(id: String) -> bool:
	return not _entry(id).is_empty()


static func _entry(id: String) -> Array:
	for a: Array in LIST:
		if a[0] == id:
			return a
	return []
