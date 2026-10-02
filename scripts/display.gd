class_name Display
## 画面に出す値の換算。


## FR-43: 速度 px/s を km/h の表示値にする（HUD と必要速度標識で共通）
static func to_display_speed(px_per_sec: float) -> int:
	return int(px_per_sec / Tuning.DISPLAY_SPEED_DIV)


## 得点を3桁区切りにする（例 1850 → "1,850"。デザイン案の表記）
static func score_text(n: int) -> String:
	var digits: String = str(absi(n))
	var out: String = ""
	while digits.length() > Tuning.DIGIT_GROUP:
		out = "," + digits.right(Tuning.DIGIT_GROUP) + out
		digits = digits.left(digits.length() - Tuning.DIGIT_GROUP)
	return ("-" if n < 0 else "") + digits + out


## FR-29: ★1 = クリア、★2 = スコア ≥ thresholds[0]、★3 = スコア ≥ thresholds[1]。クリアしていなければ0
static func stars_for(cleared: bool, score: int, thresholds: Array) -> int:
	if not cleared:
		return 0
	var stars: int = 1
	for t: Variant in thresholds:
		if score >= int(t):
			stars += 1
	return stars


## 金★（replay-value-design.md 3.2）: 合格して gold_threshold 以上。閾値が 0 以下（ステージに無い）なら取れない
static func gold_for(cleared: bool, score: int, gold_threshold: int) -> bool:
	return cleared and gold_threshold > 0 and score >= gold_threshold


## 試験の見出し（replay-value-design.md 1章）: 本試験は「第N試験」、裏試験（EX_FIRST 以降）は「裏試験N」
static func stage_title(n: int) -> String:
	if n >= Tuning.EX_FIRST:
		return "裏試験%d" % (n - Tuning.EX_FIRST + 1)
	return "第%d試験" % n


## 走った距離（px）を表示する。1000m 未満は「850 m」、以上は小数1桁の「2,743.5 km」（試験記録。整数部は3桁区切り）
static func distance_text(px: float) -> String:
	var m: float = px * Tuning.DISPLAY_METERS_PER_PX
	if roundi(m) < roundi(Tuning.METERS_PER_KM):
		return "%d m" % roundi(m)
	var km: PackedStringArray = ("%.1f" % (m / Tuning.METERS_PER_KM)).split(".")
	return "%s.%s km" % [score_text(km[0].to_int()), km[1]]
