class_name Progression
## 車両の熟練度・強化・塗装（設計書 docs/superpowers/specs/2026-09-28-replay-value-design.md の5章）。
## GameState を参照しない（-s の確認スクリプトから型名で使えるように）。車両ごとの記録は引数で受け取る。
## 値は Tuning の XP_*・LEVEL_MAX・UPGRADES・UPGRADE_COSTS・PAINT_UNLOCK_LEVELS（依頼者の判断を待たずに決めた仮の値）


## 段 L から L+1 に要る経験値
static func xp_for_level(level: int) -> int:
	return Tuning.XP_LEVEL_BASE + Tuning.XP_LEVEL_STEP * (level - 1)


## 経験値の合計 → 段（1〜LEVEL_MAX）
static func level_for(xp: int) -> int:
	var level: int = 1
	while level < Tuning.LEVEL_MAX and xp >= xp_for_level(level):
		xp -= xp_for_level(level)
		level += 1
	return level


## [今の段の中で得た経験値, 次の段までに要る経験値]。最大の段は [0, 0]
static func xp_to_next(xp: int) -> Array:
	var level: int = 1
	while level < Tuning.LEVEL_MAX and xp >= xp_for_level(level):
		xp -= xp_for_level(level)
		level += 1
	if level >= Tuning.LEVEL_MAX:
		return [0, 0]
	return [xp, xp_for_level(level)]


## 段で得た強化のポイント（段 - 1）
static func points_total(xp: int) -> int:
	return level_for(xp) - 1


## 使ったポイント（upgrades: 項目 id → 段）
static func points_spent(upgrades: Dictionary) -> int:
	var sum: int = 0
	for item: String in upgrades:
		for s: int in clampi(int(upgrades[item]), 0, Tuning.UPGRADE_COSTS.size()):
			sum += Tuning.UPGRADE_COSTS[s]
	return sum


## 項目を段 step → step+1 にする値段。最大の段なら 0
static func cost_of_next(step: int) -> int:
	return Tuning.UPGRADE_COSTS[step] if step >= 0 and step < Tuning.UPGRADE_COSTS.size() else 0


## 強化の項目の id（Tuning.UPGRADES の順）
static func upgrade_ids() -> Array[String]:
	var out: Array[String] = []
	for u: Array in Tuning.UPGRADES:
		out.append(u[0])
	return out


static func upgrade_name(item: String) -> String:
	for u: Array in Tuning.UPGRADES:
		if u[0] == item:
			return u[1]
	return ""


## 強化の倍率（1 + 段 × 1段ごとの変化）。知らない項目は 1
static func upgrade_factor(item: String, upgrades: Dictionary) -> float:
	for u: Array in Tuning.UPGRADES:
		if u[0] == item:
			return 1.0 + clampi(int(upgrades.get(item, 0)), 0, Tuning.UPGRADE_COSTS.size()) * float(u[2])
	return 1.0


## 強化込みの性能。key は Tuning.TROLLEY_STATS のキーか "girigiri_margin"（ギリギリの幅の倍率。車両の値は 1）
static func stat(id: String, key: String, upgrades: Dictionary) -> float:
	var base: float = Trolleys.stat(id, key) if key != "girigiri_margin" else 1.0
	return base * upgrade_factor(key, upgrades)


## 強化込みの壁（kind = "wall"）・ジャンプ（"jump"）の必要速度。倍率が1なら丸めない（Trolleys.effective_required と同じ）
static func effective_required(id: String, kind: String, required: float, upgrades: Dictionary) -> float:
	var factor: float = stat(id, "wall_factor" if kind == "wall" else "jump_factor", upgrades)
	if factor == 1.0:
		return required
	return snappedf(required * factor, Tuning.DISPLAY_SPEED_DIV)


## 走行1回の経験値（run は GameState.submit_run の辞書）
static func xp_for_run(run: Dictionary) -> int:
	return int(run.get("score", 0)) / Tuning.XP_SCORE_DIV + (Tuning.XP_CLEAR_BONUS if run.get("outcome", "") == "clear" else 0)


## 段 level で使える塗装の数
static func paints_unlocked(level: int) -> int:
	var n: int = 0
	for l: int in Tuning.PAINT_UNLOCK_LEVELS:
		if level >= l:
			n += 1
	return n
