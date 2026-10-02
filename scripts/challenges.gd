class_name Challenges
## 試験ごとの課題（設計書 docs/superpowers/specs/2026-09-28-replay-value-design.md の 3.1）。判定・文・検証。
## GameState を参照しない（-s の確認スクリプトから型名で使えるように）。課題の中身はステージ JSON の "challenges"

const TYPES: Array[String] = ["score", "smash_all", "combo", "girigiri", "no_toggle", "toggles_max", "kind", "chain",
	"speed", "trolley"]
## value を使わない種類（0 を入れる）
const NO_VALUE: Array[String] = ["smash_all", "no_toggle", "trolley"]
const KIND_NAMES: Dictionary = {"crate": "木箱", "barrel": "樽", "dummy": "ダミー人形", "drum": "ドラム缶", "wall": "レンガ壁"}
const KIND_VERBS: Dictionary = {"crate": "壊し", "barrel": "壊し", "dummy": "飛ばし", "drum": "爆発させ", "wall": "崩し"}  # 「…て合格する」の形


## 課題 c をこの走行で達成したか。run は GameState.submit_run と同じ辞書に "trolley"・"total"（標的の総数）・"smashed_count"（壊した標的の数）を足したもの。
## 合格した走行だけ達成になる
static func achieved(c: Dictionary, run: Dictionary) -> bool:
	if run.get("outcome", "") != "clear":
		return false
	var v: float = float(c.get("value", 0))
	var smashed: Dictionary = run.get("smashed", {})
	match c.get("type", ""):
		"score":
			return run["score"] >= v
		"smash_all":
			var total: int = run.get("total", 0)
			return total > 0 and run.get("smashed_count", 0) >= total
		"combo":
			return run["max_combo"] >= v
		"girigiri":
			return run["girigiri"] >= v
		"no_toggle":
			return run["toggles"] == 0
		"toggles_max":
			return run["toggles"] <= v
		"kind":
			return smashed.get(c.get("kind", ""), 0) >= v
		"chain":
			return run["chained"] >= v
		"speed":
			return run["max_speed"] >= v
		"trolley":
			return run.get("trolley", "") == c.get("trolley", "")
	return false


## 課題の文（例「ドラム缶を8個以上爆発させる」）。知らない種類は ""
static func describe(c: Dictionary) -> String:
	var v: int = int(c.get("value", 0))
	match c.get("type", ""):
		"score":
			return "%s点以上で合格する" % Display.score_text(v)
		"smash_all":
			return "標的をすべて壊して合格する"
		"combo":
			return "%dコンボ以上つなげて合格する" % v
		"girigiri":
			return "ギリギリ突破を%d回以上して合格する" % v
		"no_toggle":
			return "一度も分岐を切り替えずに合格する"
		"toggles_max":
			return "分岐の切り替え%d回以下で合格する" % v
		"kind":
			var k: String = c.get("kind", "")
			return "%sを%d個以上%sて合格する" % [KIND_NAMES.get(k, k), v, KIND_VERBS.get(k, "壊し")]
		"chain":
			return "巻き込まれたドラム缶を%d個以上爆発させて合格する" % v
		"speed":
			return "%dkm/h 以上を出して合格する" % Display.to_display_speed(v)
		"trolley":
			return "%sで合格する" % Trolleys.name_of(c.get("trolley", ""))
	return ""


## ステージの "challenges" の検証（StageLoader.validate が使う）。違反の文の配列（無ければ空）。
## 無いステージ（null）は違反にしない
static func validate(list: Variant) -> Array[String]:
	var errors: Array[String] = []
	if list == null:
		return errors
	if not list is Array or (list as Array).size() != Tuning.CHALLENGE_COUNT:
		errors.append("challenges は %d 個の配列" % Tuning.CHALLENGE_COUNT)
		return errors
	for c: Variant in list:
		if not c is Dictionary:
			errors.append("challenges の要素が辞書でない")
			continue
		var type: Variant = (c as Dictionary).get("type")
		if not type is String or not TYPES.has(type):
			errors.append("challenges の種類が不正: %s" % str(type))
			continue
		var v: Variant = (c as Dictionary).get("value", 0)
		if not (v is int or v is float) or v < 0:
			errors.append("challenges の value が不正: %s" % str(v))
		if type == "kind" and not KIND_NAMES.has((c as Dictionary).get("kind", "")):
			errors.append("challenges の kind が不正")
		if type == "trolley" and not Trolleys.IDS.has((c as Dictionary).get("trolley", "")):
			errors.append("challenges の trolley が不正")
	return errors
