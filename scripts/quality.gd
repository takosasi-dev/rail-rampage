class_name Quality
## 画質（docs/superpowers/specs/2026-09-26-trolleys-and-display-design.md 4章）の中身。
## ゲーム画面を作るときに GameState.quality を level に写し、画面の中の物（照明・影・演出）はここを見る。
## ポーズの設定で画質を変えても今の試験は変わらず、次に始めた試験（リトライを含む）から効く。
## 高: 今のまま。中: 演出の数と粒の量を減らす（照明は残す）。
## 低: 中に加えて、照明（PointLight2D の照明器具・前照灯・爆発の閃光）を切り、時間帯の暗さを弱め、
##     ぼかしの影と雑音の模様を省く
## TODO(spec): 低で省くものは設計書の例（ぼかしの影・雑音の模様）だけにした。照明器具の電球と光る物のにじみ
##             （足し算の丸）、ぼかさない支柱の影、メニュー画面の紙の粒は残す（軽い。暗い時間帯の目印にもなる）
## TODO(spec): 中で減らす演出は粒の数（破片・煙・紙吹雪・車輪の火花・スピード線・FR-34 のパーティクル）と同時の数だけ。
##             衝突の星・火の玉・衝撃波の輪・得点ポップアップは1つずつなので減らさない
## ponytail: 今のゲーム画面の値を1つだけ持つ（ゲーム画面は同時に1つ）。ゲームの外の画面は、最後に遊んだ画質のまま

const HIGH: String = "high"  # Tuning.QUALITY_LEVELS の名前
const LOW: String = "low"

static var level: String = HIGH


## 演出の粒の数（破片・煙・火花・紙吹雪・パーティクル・スピード線）。高は n のまま。n が 1 以上なら 1 つは残す
static func count(n: int) -> int:
	return maxi(ceili(n * float(Tuning.QUALITY_FX_SCALE[level])), mini(n, 1))


## 同時に置く演出の数の上限（Fx.add）
static func max_effects() -> int:
	return Tuning.QUALITY_MAX_EFFECTS[level]


## 照明（PointLight2D）を点けるか
static func lights() -> bool:
	return level != LOW


## 重い描き方（ぼかしの影・雑音の模様）を省くか
static func plain() -> bool:
	return level == LOW


## 時間帯 tod の全体に掛ける色（CanvasModulate）。低は白へ寄せて暗さを弱める
static func ambient(tod: String) -> Color:
	var c: Color = Palette.TOD_AMBIENT[tod]
	return c.lerp(Palette.WHITE, Tuning.QUALITY_LOW_AMBIENT_LIFT) if plain() else c
