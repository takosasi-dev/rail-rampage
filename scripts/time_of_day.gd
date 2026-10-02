class_name TimeOfDay
## 時間帯（① プレイ画面の絵、設計書4章）。名前・表示・時刻と、遊ぶステージの時間帯の決め方。
## 決め方は2通り（設定 time_of_day_mode）: A「順に進む」は第N試験の番号から、C「見どころに合わせる」はステージの
## JSON の time_of_day から。色は Palette.TOD_*、強さは Tuning.TOD_*

const NAMES: Array[String] = ["morning", "noon", "sunset", "dusk", "night"]
const LABELS: Dictionary = {"morning": "朝", "noon": "昼", "sunset": "夕方", "dusk": "夜の入り", "night": "深夜"}
## 試験の時刻（ステージ選択に出す飾り。遊び方には関係しない）
const CLOCKS: Dictionary = {"morning": "07:00", "noon": "12:00", "sunset": "17:30", "dusk": "19:30", "night": "23:30"}
const MODE_SEQUENCE: String = "sequence"  # A「順に進む」
const MODE_STAGE: String = "stage"  # C「見どころに合わせる」
const MODES: Array[String] = [MODE_SEQUENCE, MODE_STAGE]


## A: 全 count 試験のうち第 number 試験の時間帯。5つを順に均等に割り当てる（count = 5 なら第N試験が N 番目）。
## 範囲外の番号は端に寄せる
static func by_number(number: int, count: int) -> String:
	var total: int = maxi(count, 1)
	var n: int = clampi(number, 1, total)
	return NAMES[mini(int(float(n - 1) * NAMES.size() / total), NAMES.size() - 1)]


## 遊ぶときの時間帯。mode が C でも、JSON に time_of_day が無い・知らない名前なら A の値。
## 裏試験（number が count より大きい）は A でもステージの time_of_day（replay-value-design.md 4章）
static func resolve(mode: String, number: int, count: int, stage_data: Dictionary) -> String:
	var fallback: String = by_number(number, count)
	if mode != MODE_STAGE and number <= count:
		return fallback
	var v: Variant = stage_data.get("time_of_day")
	return v if v is String and NAMES.has(v) else fallback
