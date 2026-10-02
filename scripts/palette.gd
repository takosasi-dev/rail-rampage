class_name Palette
## 色（仕様書16.3）。他のファイルに色を直書きしない。

const INK: Color = Color("#1B1A17")
const HAZARD: Color = Color("#F2C230")
const HAZARD_DARK: Color = Color("#D9A81E")
const PAPER: Color = Color("#EFE8D8")
const PAPER_LIGHT: Color = Color("#F7F2E6")
const STAMP: Color = Color("#C0322B")
const BOARD: Color = Color("#D9D5CB")
const GRID_MINOR: Color = Color("#CDC8BC")
const GRID_MAJOR: Color = Color("#BCB6A9")
const GROUND: Color = Color("#625E57")
const STEEL: Color = Color("#3B3B3B")
const SLEEPER: Color = Color("#6B5B45")
const WOOD: Color = Color("#B07A3E")
const WOOD_DARK: Color = Color("#7A5128")
const BARREL: Color = Color("#8C5A2B")
const BRICK: Color = Color("#9C4A32")
const MORTAR: Color = Color("#D7C9B4")
const MUTED: Color = Color("#5A554B")
const MUTED_ON_INK: Color = Color("#A8A195")
const PAPER_DARK: Color = Color("#E3DBC8")
const STAMP_LIGHT: Color = Color("#F7E1DE")
const STAMP_TEXT: Color = Color("#A0241E")
const LOCKED: Color = Color("#8A857A")
const RAIL_ON_INK: Color = Color("#8A8D8F")
const SHADOW: Color = Color("#0E0D0B")
# TODO(spec): 16.4 と FR-19 は「白」を使うが、16.3 の表に白が無い。純白で置いた
const WHITE: Color = Color("#FFFFFF")
# TODO(spec): 破片パーティクル（FR-34）の色は仕様に無い。標的の主な色にした
const DEBRIS_COLORS: Dictionary = {"crate": WOOD, "barrel": BARREL, "dummy": HAZARD, "drum": STAMP, "wall": BRICK,
		"brick_piece": BRICK}
# TODO(spec): タイトルの挿絵の地面の色は 16.3 に無い。デザイン案の値
const GROUND_ON_INK: Color = Color("#2A2925")

# --- ① プレイ画面の絵（依頼者の判断で足した色。設計書 docs/superpowers/specs/2026-09-26-play-screen-art-design.md） ---
# 時間帯（設計書4章）。名前は TimeOfDay.NAMES
const TOD_AMBIENT: Dictionary = {  # 全体に掛ける色（CanvasModulate）
	"morning": Color("#FFF4E6"), "noon": Color("#FFFFFF"), "sunset": Color("#EDC39E"), "dusk": Color("#8D86A3"),
	"night": Color("#46454F")}
const TOD_SKY: Dictionary = {  # 窓の外の空 [上, 下]
	"morning": [Color("#9CC9EA"), Color("#F6E3B8")], "noon": [Color("#6FB2E6"), Color("#CFE8F7")],
	"sunset": [Color("#6A4A7E"), Color("#F08A4B")], "dusk": [Color("#1F2550"), Color("#6E5A86")],
	"night": [Color("#080A16"), Color("#1A1E36")]}
const TOD_SHAFT: Dictionary = {  # 窓から差し込む光の色（濃さは Tuning.TOD_SHAFT。0 の時間帯は使わない）
	"morning": Color("#FFE9B0"), "noon": Color("#FFFFFF"), "sunset": Color("#FF9A4A"), "dusk": Color("#FFFFFF"),
	"night": Color("#FFFFFF")}
# 描画の共通部品（設計書2章）
const SHADOW_TINT: Color = Color("#1B1A1752")  # 影の色（INK の 32%）。支柱の影など、ぼかさない影に使う
const NOISE_DARK: Color = Color("#1F1C17")  # むら・汚れ・粒（明るい地の上）
const NOISE_COLORS: Dictionary = {"blotch": NOISE_DARK, "grain": NOISE_DARK, "fleck": PAPER}  # fleck は墨地の上の粒
# 標的とトロッコの質感（設計書3章。光は左上から。ぼかしの区切りの位置は Tuning の *_STOP_AT）
const WOOD_LIGHT: Color = Color("#C58D4F")  # 木箱の上
const WOOD_SHADE: Color = Color("#9A6632")  # 木箱の下
const WOOD_SEAM: Color = Color("#6B4522")  # 板の継ぎ目
const WOOD_GRAIN: Color = Color("#7A512873")  # 木目（WOOD_DARK の 45%）
const WOOD_BRACE: Color = Color("#6E4822")  # 筋交い
const WOOD_BRACE_EDGE: Color = Color("#A7743F")  # 筋交いの上の光の縁
const BARREL_STOPS: Array = [Color("#5A3716"), Color("#A16A35"), Color("#B57E46"), Color("#7E4F24"), Color("#4A2D12")]
const BARREL_STAVE: Color = Color("#3E261066")  # 縦の板目（40%）
const HOOP_STOPS: Array = [Color("#2A2A2A"), Color("#8E8E8E"), Color("#262626")]  # 金属のたが
const PLASTIC_STOPS: Array = [Color("#FFE68F"), HAZARD, Color("#C08E10")]  # ダミー人形の艶
const GLOSS: Color = Color("#FFFFFFB3")  # 白い光の点（70%）
const DRUM_STOPS: Array = [Color("#7E1C17"), Color("#D2423A"), Color("#DC5A50"), Color("#A52822"), Color("#6C1713")]
const DRUM_BAND_STOPS: Array = [Color("#B98D12"), Color("#FFD85A"), HAZARD_DARK, Color("#A67D0E")]
const RIM_SHADE: Color = Color("#0000002E")  # 縁の段差（18%）
const GLINT: Color = Color("#FFFFFF47")  # 縦の光の筋（28%）
const MORTAR_DEEP: Color = Color("#C9BBA4")  # 引っ込んだ目地
const BRICK_TONES: Array = [Color("#9C4A32"), Color("#A5533A"), Color("#8F432D"), Color("#9A4630"), Color("#AE5A3E"),
	Color("#94452E")]  # レンガ1個ずつの色むら
const BRICK_EDGE_LIGHT: Color = Color("#D27A5A8C")  # 上の縁の光（55%）
const BRICK_EDGE_SHADE: Color = Color("#0000002E")  # 下の縁の影（18%）
const STEEL_LIGHT: Color = Color("#737373")  # 金属のぼかしの上
const STEEL_SHADE: Color = Color("#2A2A2A")  # 金属のぼかしの下
const RIVET: Color = Color("#A2A2A2")
const GLINT_SOFT: Color = Color("#FFFFFF17")  # トロッコの斜めの光の反射（9%）
const BAND_SHADE: Color = Color("#0000004D")  # ストライプ帯の上の影（30%）
const WHEEL_GLINT: Color = Color("#8C8C8C")  # 車輪の軸の光
# 線路・支柱・床（設計書2章）
const RAIL_TOP: Color = Color("#9A9A9A")  # レールの上面の光の筋
const SLEEPER_EDGE: Color = Color("#43382A")  # 枕木の下端の影
const TOWER: Color = Color("#55524C")  # 支柱の縦材と板
const TOWER_BRACE: Color = Color("#6E6A62")  # 筋交い
const TOWER_EDGE: Color = Color("#8C8880")  # 縦材の左の光の縁
const FLOOR_TOP: Color = Color("#716D65")  # 床の上（16.3 の GROUND の少し明るい側）
const FLOOR_BOTTOM: Color = Color("#4F4B45")
const SCALE_TICK: Color = Color("#6F695E")  # 距離の目盛りと数字
# 奥の壁（設計書2章）
const WALL_STOPS: Array = [Color("#DAD5CA"), Color("#D2CCC0"), Color("#B9B2A5")]  # 上→下（位置は Tuning.WALL_STOP_AT）
const WALL_SEAM: Color = Color("#B3AC9F")  # パネルの継ぎ目
const WALL_BOLT: Color = Color("#A59E90")
const WINDOW_FRAME: Color = Color("#8E887C")  # 窓枠と桟
const STAR: Color = Color("#FFFFFFCC")
# 照明（設計書4章）
const LAMP_BULB: Color = Color("#FFF6DA")  # 点いている電球
const LAMP_OFF: Color = Color("#B8B2A6")  # 消えている電球
const LAMP_LIGHT: Color = Color("#FFF1CF")  # 照明器具と前照灯の光
const RIM_LIGHT: Color = Color("#FFF1B0")  # 分岐の円盤の金属の縁の光

# --- ② 演出と手触り（依頼者の外出中に決めた。設計書 docs/superpowers/specs/2026-09-26-effects-design.md） ---
const FX_DUST: Color = Color("#B8AE9C")  # 砂ぼこり
const FX_SMOKE: Color = Color("#2E2B27")  # 爆発の煙
const FX_FIRE_CORE: Color = Color("#FFF6DA")  # 火の玉の芯・閃光
const FX_FIRE_EDGE: Color = Color("#E8622A")  # 火の玉の外側
const FX_SPARK: Color = Color("#FFE08A")  # 車輪の火花
const FX_SHARDS: Dictionary = {  # 破片の色（種類ごとに、ばらつかせる色）
	"plank": [WOOD, WOOD_DARK, Color("#C58D4F")], "stave": [BARREL, Color("#6E4420"), Color("#A16A35")],
	"metal": [STAMP, HAZARD, STEEL], "paper": [PAPER, PAPER_LIGHT, PAPER_DARK, HAZARD], "spark": [FX_SPARK, FX_FIRE_CORE]}
const FX_HOOP: Color = Color("#4A4A48")  # 樽のたがの輪
const GOAL_TAPE: Color = STAMP  # ゴールのテープ

# --- 車両の絵と車庫（依頼者の判断を待たずに決めた。trolleys-and-display-design.md 3章）。ぼかしは [上, 下] ---
const HEAVY_STEEL: Array = [Color("#72808D"), Color("#2A323A")]  # 重量型の青みの鋼板（明るさは標準型と同じくらい。夜も見える）
const HEAVY_LIP: Color = Color("#94A0AB")  # 上縁の厚い板
const HEAVY_SEAM: Color = Color("#121518")  # 板の継ぎ目
const HEAVY_RIVET: Color = Color("#BCC4CC")
const LIGHT_ALLOY: Array = [Color("#E6ECEF"), Color("#8D9BA6")]  # 軽量型の明るいアルミ
const LIGHT_STRIPE: Color = Color("#2E9CC0")  # 軽量型の青い細帯
const LIGHT_HOLE: Color = Color("#2A3239")  # 肉抜きの穴の奥
const BLAST_PAINT: Array = [Color("#E0503F"), Color("#781A13")]  # 発破型の赤い塗装（ドラム缶の色の仲間）
const BLAST_STICK: Color = Color("#E86A52")  # ダイナマイト
const PROTO_SHELL: Array = [Color("#FCFBF7"), Color("#B3AD9F")]  # 試作型の白い殻
const PROTO_VISOR: Color = Color("#22303B")  # 覗き窓
const PROTO_VISOR_GLINT: Color = Color("#8FB6CF")  # 覗き窓の光の筋
const GARAGE_LOCKED_FADE: Color = Color("#FFFFFF4D")  # 車庫の未解放の車両の絵（薄くする）

# --- やりこみ要素（依頼者の判断を待たずに決めた。docs/superpowers/specs/2026-09-28-replay-value-design.md）。担当ごとの節の下に足す ---
const GOLD_STAR: Color = Color("#E0B23A")  # 金★
# --- やりこみ A: 課題と金★ ---
# --- やりこみ B: 車庫（熟練度・強化・塗装） ---
## 塗装（設計書 5.3）: 車両 id → 塗装 0〜4 の色の組。0 は今までの色、4 は金。どれも夜・深夜に見える明るさ。
## body = 車体のぼかし [上, 下]。trim / detail は車両ごとに差し替える部品:
##   標準型 trim = 帯のストライプ・detail = 鋲 / 重量型 trim = 上縁の板・detail = リベット / 軽量型 trim = 細帯・detail = 肉抜きの穴 /
##   発破型 trim = 上縁のストライプ・detail = 危険表示 / 試作型 trim = 帯・detail = 覗き窓
## TODO(spec): 色は依頼者の判断を待たずに決めた（試遊の後に見直す）
const TROLLEY_PAINTS: Dictionary = {
	"standard": [
		{"body": [STEEL_LIGHT, STEEL_SHADE], "trim": HAZARD, "detail": RIVET},
		{"body": [Color("#C8553D"), Color("#5E2217")], "trim": HAZARD, "detail": Color("#E8A898")},
		{"body": [Color("#8DB255"), Color("#3C5420")], "trim": Color("#F5F0DC"), "detail": Color("#D9E8B8")},
		{"body": [Color("#5A7AB4"), Color("#1E2C4A")], "trim": Color("#E8E4D8"), "detail": Color("#A9BCE0")},
		{"body": [Color("#F0CF6A"), Color("#8A6414")], "trim": Color("#FFF1B8"), "detail": Color("#FFF1B8")},
	],
	"heavy": [
		{"body": HEAVY_STEEL, "trim": HEAVY_LIP, "detail": HEAVY_RIVET},
		{"body": [Color("#5E8C6A"), Color("#1F3527")], "trim": Color("#86B090"), "detail": Color("#D0E0D4")},
		{"body": [Color("#A0624A"), Color("#45241A")], "trim": Color("#C08468"), "detail": Color("#E6C8B8")},
		{"body": [Color("#7A6A9E"), Color("#2E2640")], "trim": Color("#9D8FC0"), "detail": Color("#D8D0EA")},
		{"body": [Color("#E8C35A"), Color("#7A5810")], "trim": Color("#F7DE8A"), "detail": Color("#FFF3C4")},
	],
	"light": [
		{"body": LIGHT_ALLOY, "trim": LIGHT_STRIPE, "detail": LIGHT_HOLE},
		{"body": [Color("#F4D9DE"), Color("#B08A92")], "trim": Color("#D0506A"), "detail": LIGHT_HOLE},
		{"body": [Color("#E4F0D0"), Color("#8FA878")], "trim": Color("#4E9A3A"), "detail": LIGHT_HOLE},
		{"body": [Color("#F8E6CC"), Color("#B89A74")], "trim": Color("#E07A1E"), "detail": LIGHT_HOLE},
		{"body": [Color("#FAE7A0"), Color("#B08A2A")], "trim": Color("#8A6414"), "detail": Color("#4A3608")},
	],
	"blast": [
		{"body": BLAST_PAINT, "trim": HAZARD, "detail": HAZARD},
		{"body": [Color("#E8892E"), Color("#7A3E0C")], "trim": Color("#F5E6C8"), "detail": HAZARD},
		{"body": [Color("#6E8C3A"), Color("#2C3A14")], "trim": HAZARD, "detail": HAZARD},
		{"body": [Color("#A85CAE"), Color("#401C44")], "trim": HAZARD, "detail": HAZARD},
		{"body": [Color("#F0CC5E"), Color("#85600F")], "trim": Color("#FFF3C4"), "detail": STAMP},
	],
	"prototype": [
		{"body": PROTO_SHELL, "trim": HAZARD, "detail": PROTO_VISOR},
		{"body": [Color("#DDEEF8"), Color("#8FA8BA")], "trim": Color("#2E9CC0"), "detail": PROTO_VISOR},
		{"body": [Color("#E6F2D6"), Color("#9AAE84")], "trim": Color("#4E9A3A"), "detail": PROTO_VISOR},
		{"body": [Color("#F2D0C4"), Color("#B07A68")], "trim": STAMP, "detail": PROTO_VISOR},
		{"body": [Color("#FBEBAE"), Color("#B89232")], "trim": Color("#8A6414"), "detail": Color("#3A2A08")},
	],
}
const GARAGE_UPGRADE_BAR: Color = Color("#3E9C5A")  # 性能の棒グラフの、強化で伸びた分
# --- やりこみ C: 裏試験 ---
# --- やりこみ D: ゴースト・試験記録の画面 ---
const GHOST_TINT: Color = Color("#6F7C8A73")  # ゴーストの車体を染める色（墨を薄めた青灰、不透明度 45%）
# --- やりこみ E: 無限軌道 ---
