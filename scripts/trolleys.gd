class_name Trolleys
## 車両（トロッコの種類。設計書 docs/superpowers/specs/2026-09-26-trolleys-and-display-design.md の1章）。
## 名前と長所・短所の文、性能の値の引き方、解放の判定。性能の値は Tuning.TROLLEY_STATS、解放の条件は Tuning.TROLLEY_UNLOCK。
## GameState を参照しない（-s の確認スクリプトから型名で使えるように）。判定に要るものは引数で受け取る。
## 車両の数・名前・性能・解放の条件は、依頼者の判断を待たずに決めた（試遊の後に見直す）

## 並べる順（車庫・ステージ選択）。最初が最初から使える標準型
const IDS: Array[String] = ["standard", "heavy", "light", "blast", "prototype"]
const DEFAULT: String = "standard"
## id → [名前, 長所, 短所]（性能の値を変えたら、ここの文も合わせる）
const TEXT: Dictionary = {
	"standard": ["標準型", "", ""],
	"heavy": ["重量型", "壁に強い・吹っ飛ばす力が強い", "初速が遅い・勢いが溜まりにくい・ジャンプに弱い"],
	"light": ["軽量型", "初速が速い・ジャンプに強い", "壁に弱い・勢いが減りやすい・吹っ飛ばす力が弱い"],
	"blast": ["発破型", "爆発の範囲が広い・コンボの受付が長い", "最高速が低い・初速がやや遅い"],
	"prototype": ["試作型", "最高速が高い・勢いが溜まりやすい", "壁にもジャンプにも弱い・勢いが減りやすい"],
}


static func name_of(id: String) -> String:
	return (TEXT.get(id, ["", "", ""]) as Array)[0]


static func pros_of(id: String) -> String:
	return (TEXT.get(id, ["", "", ""]) as Array)[1]


static func cons_of(id: String) -> String:
	return (TEXT.get(id, ["", "", ""]) as Array)[2]


## 性能の値（知らない id は標準型）。キーは設計書1章の表
static func stat(id: String, key: String) -> float:
	return (Tuning.TROLLEY_STATS.get(id, Tuning.TROLLEY_STATS[DEFAULT]) as Dictionary)[key]


## その車両にとっての壁（kind = "wall"）・ジャンプ（"jump"）の必要速度: ステージの値 × 倍率を 1km/h 単位に丸める。
## 倍率が1なら丸めない（標準型はステージの値のまま）
static func effective_required(id: String, kind: String, required: float) -> float:
	var factor: float = stat(id, "wall_factor" if kind == "wall" else "jump_factor")
	if factor == 1.0:
		return required
	return snappedf(required * factor, Tuning.DISPLAY_SPEED_DIV)


## その車両の★2・★3 の閾値（ステージの star_thresholds × star_scale を整数に丸める）
static func thresholds(id: String, stage_thresholds: Array) -> Array:
	var k: float = stat(id, "star_scale")
	return stage_thresholds.map(func(t: Variant) -> int: return roundi(float(t) * k))


## 解放されているか。cleared: 試験ごとの合格（試験番号 - 1 の順。全車両をまとめたもの）、stamps: 取った検定印
static func is_unlocked(id: String, cleared: Array, stamps: Dictionary) -> bool:
	if not IDS.has(id):
		return false
	var u: Dictionary = Tuning.TROLLEY_UNLOCK.get(id, {})
	if u.has("stage"):
		var n: int = u["stage"]
		return n >= 1 and n <= cleared.size() and cleared[n - 1]
	if u.has("stamp"):
		return stamps.has(u["stamp"])
	return true


## 解放の条件の文（最初から使える車両は ""）
static func unlock_text(id: String) -> String:
	var u: Dictionary = Tuning.TROLLEY_UNLOCK.get(id, {})
	if u.has("stage"):
		return "第%d試験の合格で解放" % u["stage"]
	if u.has("stamp"):
		return "検定印「%s」で解放" % Achievements.name_of(u["stamp"])
	return ""
