class_name Tuning
## 調整値（仕様書7章）。他のファイルに数値を直書きせず、ここに集める。

# --- 7章の調整値 ---
const SPEED_BASE: float = 500.0  # 7章の初期値は 400。M1 の試遊で「もう少し速く」となり上げた
const SPEED_MAX: float = 1100.0
const SPEED_PER_MOMENTUM: float = 5.0
const SPEED_LERP: float = 4.0
const MOMENTUM_MAX: float = 140.0
const MOMENTUM_DECAY: float = 4.0
const HIT_BASE: float = 300.0
const HIT_SPEED_FACTOR: float = 0.8
const HIT_ANGLE_JITTER_DEG: float = 15.0
const ANG_VEL_MAX: float = 10.0
const EXPLOSION_RADIUS: float = 180.0
const EXPLOSION_IMPULSE: float = 1200.0
const EXPLOSION_CHAIN_DELAY: float = 0.08
const COMBO_WINDOW: float = 1.0
const HITSTOP_MIN_POINTS: int = 300
const HITSTOP_SCALE: float = 0.05
const HITSTOP_DURATION: float = 0.06
const SLOWMO_SCALE: float = 0.3
const SLOWMO_DURATION: float = 0.35
const SHAKE_BASE: float = 4.0
const SHAKE_DIV: float = 50.0
const SHAKE_MAX: float = 20.0
const SHAKE_DECAY: float = 0.25
const ZOOM_AT_BASE: float = 1.0
const ZOOM_AT_MAX: float = 0.68  # TODO(spec): 7章の初期値は 0.7。車両ごとの速さの伸び方で、分岐の1秒前に標識が画面の右端から数px 出たので少し引いた（trolleys-and-display-design.md）
const ZOOM_MIN: float = 0.625  # SPEED_MAX より速い車両のズームの下限（試作型の最高速 1200 で約 0.627。FR-38 の傾きのまま引く）
const ZOOM_MIN_MARGIN: float = 0.01  # ZOOM_MIN は一番速い車両の最高速のズームからこの差以内（確認用）
const CAMERA_Y_SMOOTH: float = 5.0
const FAIL_DELAY: float = 1.5
const DEBRIS_LIFETIME: float = 4.0
const DEBRIS_BEHIND_LIMIT: float = 2000.0
const MAX_ACTIVE_BODIES: int = 120
const RETRY_DEBOUNCE: float = 0.3
const MIN_JUNCTION_GAP: float = 1100.0
const DEBUG_FIXED_SPEED: float = -1.0
const GIRIGIRI_MARGIN: float = 50.0
const GIRIGIRI_BONUS: int = 500
const BANNER_DURATION: float = 1.2
const JUNCTION_PULSE_PERIOD: float = 0.6
const SE_VOLUME_DEFAULT: int = 80

# --- ステージと記録（8.1、FR-29、FR-48） ---
# TODO(spec): 8.1 は5ステージ。依頼者の「ステージ数増やすでもええし」を受けて第6〜10試験を足した
#             （docs/superpowers/specs/2026-09-26-more-stages-design.md。依頼者の不在中に決めた。試遊の後に見直す）
const STAGE_COUNT: int = 10
const STARS_MAX: int = 3
const DIGIT_GROUP: int = 3  # 得点の3桁区切り

# --- カメラ（FR-37） ---
const CAMERA_TROLLEY_SCREEN_X: float = 0.25  # 画面左端からの割合
# TODO(spec): FR-39 は縦の位置を決めていない（今までは画面の中央）。上の出口の wall の標識が分岐の1秒前に右上の速度の札に
#             隠れていた（L-3）ので、トロッコを少し下に置いて上を空けた。依頼者の不在中に決めた。試遊の後に見直す
const CAMERA_TROLLEY_SCREEN_Y: float = 0.66  # 画面上端からの割合（車両ごとの速さでも標識が右上の札に隠れないように）

# --- 速度の表示（FR-43: km/h = int(px/s / 10)） ---
const DISPLAY_SPEED_DIV: float = 10.0

# --- 物理レイヤー（11章の 1=地面 2=未破壊の標的 3=破片・吹っ飛んだ物体。値はビット） ---
const LAYER_GROUND: int = 1
const LAYER_TARGET: int = 2
const LAYER_DEBRIS: int = 4

# --- 標的（6.3）。brick_piece は wall が割れた後のレンガ片 ---
const TARGET_POINTS: Dictionary = {"crate": 100, "barrel": 150, "dummy": 300, "drum": 500, "wall": 800}
const TARGET_MASS: Dictionary = {"crate": 1.0, "barrel": 1.5, "dummy": 2.0, "drum": 2.0, "brick_piece": 0.8}
const TARGET_SIZE: Dictionary = {
	"crate": Vector2(48, 48), "barrel": Vector2(40, 56), "dummy": Vector2(32, 80),
	"drum": Vector2(44, 60), "wall": Vector2(32, 160), "brick_piece": Vector2(20, 20)}
const TARGET_MOMENTUM: Dictionary = {"crate": 3.0, "barrel": 5.0, "dummy": 6.0, "drum": 10.0, "wall": 15.0}  # 勢い加算（FR-21）
const HIT_DIRECTION: Vector2 = Vector2(1.0, -0.7)  # FR-14 の衝撃の向き（正規化して使う）
const WALL_PIECES: int = 8  # FR-18
# TODO(spec): FR-20「跳ねて転がる」の跳ね返りの強さは仕様に無い。仮値
const DEBRIS_BOUNCE: float = 0.3

# --- コンボ倍率（FR-28 の式 min(1.0 + floor(combo / 5) × 0.5, 3.0) の定数） ---
const COMBO_STEP: int = 5
const COMBO_STEP_BONUS: float = 0.5
const COMBO_MULT_MAX: float = 3.0
const COMBO_DISPLAY_MIN: int = 2  # FR-42: コンボ数はこの値以上のときだけ出す

# --- 得点ポップアップ（FR-35、16.4、16.6） ---
const POPUP_RISE: float = 60.0
const POPUP_DURATION: float = 0.8
const POPUP_FONT_SIZE: int = 30
const POPUP_OUTLINE: int = 6

# --- 必要速度標識（FR-19, FR-24）。寸法はデザイン案の StyleGuide から ---
const SIGN_SIZE: Vector2 = Vector2(130, 38)
const SIGN_OUTLINE: float = 3.0  # 枠は標識の内側に描く（デザイン案は border-box）
const SIGN_FONT_SIZE: int = 18
const SIGN_WALL_GAP: float = 10.0  # 標識の下端から wall の上端まで
const SIGN_JUMP_HEIGHT: float = 80.0  # TODO(spec): FR-24「開始地点の上方80px」を標識の下端までの高さとした

# --- ジャンプ（6.2、16.5） ---
const JUMP_RAIL_PART: float = 0.15  # レールを描く先頭・末尾の割合
const RAMP_W: float = 80.0
const RAMP_H: float = 26.0
const RAMP_LINE_W: float = 3.0

# --- ギリギリ突破の表示（FR-36a、16.6） ---
const GIRIGIRI_SHOW_TIME: float = 1.0
const GIRIGIRI_FONT_SIZE: int = 36
const GIRIGIRI_ANGLE_DEG: float = -4.0
const GIRIGIRI_PADDING: Vector2 = Vector2(14, 2)  # 文字の周りの余白（デザイン案）

# --- 失敗（FR-25、16.6） ---
const FAIL_FONT_SIZE: int = 72
const FAIL_SHADOW_OFFSET: Vector2 = Vector2(3, 3)
const FAIL_POP_SCALE: float = 1.4
const FAIL_POP_TIME: float = 0.15

# --- 地面（FR-20、16.3） ---
const GROUND_LINE_W: float = 6.0
# TODO(spec): 地面を描く範囲は仕様に無い。線路の左右端からの余白と、地面の厚み（画面の下端より深く）
const GROUND_MARGIN: float = 3000.0
const GROUND_DEPTH: float = 2000.0

# --- 画面中央の知らせ（GOAL・ステージデータエラー）、デバッグ表示、途切れたコンボの文字 ---
const MESSAGE_FONT_SIZE: int = 48
const TEMP_HUD_OUTLINE: int = 4  # 生成りの縁取り（地面や標的に重なっても読めるように）

# --- 破片パーティクル（FR-34） ---
# TODO(spec): 個数・寿命以外（広がり・速さ・重力・大きさ）は仕様に無い。仮値。向きは衝撃の向き
const PARTICLE_AMOUNT: int = 16
const PARTICLE_LIFETIME: float = 0.6
const PARTICLE_SPREAD_DEG: float = 60.0
const PARTICLE_SPEED_MIN: float = 200.0
const PARTICLE_SPEED_MAX: float = 480.0
const PARTICLE_GRAVITY: Vector2 = Vector2(0, 1200)
const PARTICLE_SIZE_MIN: float = 4.0
const PARTICLE_SIZE_MAX: float = 10.0

# --- 試験開始バナー（FR-36b、16.6）。寸法はデザイン案から ---
const BANNER_TOP: float = 72.0  # 画面上端からバナーの上端まで
const BANNER_H: float = 44.0
const BANNER_END_W: float = 22.0  # 両端のストライプの幅
const BANNER_STRIPE_W: float = 8.0
const BANNER_PAD_X: float = 18.0
const BANNER_GAP: float = 14.0  # 試験番号と「試験開始」の間
const BANNER_NUM_FONT_SIZE: int = 15
const BANNER_FONT_SIZE: int = 20
const BANNER_FADE: float = 0.2  # TODO(spec): 消え方は仕様に無い。表示時間の最後のこの秒数で薄くなる

# --- 初回操作ヒント（FR-36c）。寸法はデザイン案から ---
const HINT_HEIGHT: float = 80.0  # TODO(spec): 「分岐の上方80px」を札の下端までの高さとした（FR-24 の標識と同じ）
const HINT_PAD: Vector2 = Vector2(14, 8)
const HINT_KEY_PAD: Vector2 = Vector2(8, 2)
const HINT_GAP: float = 10.0
const HINT_FONT_SIZE: int = 15
const HINT_KEY_FONT_SIZE: int = 14

# --- コンボの演出（依頼者の追加要望で、仕様に無い。値はすべて仮） ---
const COMBO_STAMP_Y: float = 150.0  # 倍率の札の中心の高さ（画面上端から。試験開始バナーの下）
const COMBO_STAMP_FONT_SIZE: int = 44
const COMBO_STAMP_PAD: Vector2 = Vector2(18, 2)
const COMBO_STAMP_OUTLINE: int = 4
const COMBO_STAMP_ANGLE_DEG: float = -8.0
const COMBO_STAMP_POP_SCALE: float = 1.6  # リザルトの判子（17.7）と同じ 1.6→1.0
const COMBO_STAMP_POP_TIME: float = 0.12
const COMBO_STAMP_HOLD: float = 0.5
const COMBO_STAMP_FADE: float = 0.3
const COMBO_BOUNCE_SCALE: float = 1.3  # 倍率が上がったときのコンボ表示の弾み
const COMBO_BOUNCE_TIME: float = 0.15
const COMBO_EDGE_MULT: float = 2.0  # この倍率以上に上がったら、画面の上下の縁にストライプを出す
const COMBO_EDGE_H: float = 20.0  # 17.2 の画面端の帯と同じ太さ
const COMBO_EDGE_STRIPE_W: float = 20.0
const COMBO_EDGE_TIME: float = 0.6
const COMBO_MAX_SLOWMO_SCALE: float = 0.3  # 最大倍率に届いた瞬間のスローモー
const COMBO_MAX_SLOWMO_DURATION: float = 0.5
const COMBO_MAX_SHAKE: float = 24.0
const COMBO_BREAK_MIN: int = 10  # このコンボ数以上で途切れたら「N COMBO」を出す
const COMBO_BREAK_FONT_SIZE: int = 28
const COMBO_BREAK_TIME: float = 0.8
const COMBO_BREAK_DROP: float = 16.0

# --- 効果音（FR-51） ---
const SE_VOLUME_MAX: int = 100
const SE_VOLUME_STEP: int = 10  # FR-47b: 設定画面は10刻み
const SE_POLYPHONY: int = 4  # TODO(spec): 同じ効果音を重ねて鳴らせる数は仕様に無い。仮値

# --- 描画順 ---
const Z_GROUND: int = -1
const Z_TROLLEY: int = 2  # 分岐・標的（z=0）より手前
const Z_SIGN: int = 3  # 標識はトロッコより手前
const Z_PARTICLES: int = 4
const Z_POPUP: int = 10

# --- 線路（FR-4） ---
const RAIL_WIDTH: float = 6.0

# --- 分岐（FR-9） ---
const JUNCTION_ACTIVE_RADIUS: float = 16.0
const JUNCTION_OUTLINE: float = 3.0
const JUNCTION_RING_RADIUS: float = 30.0
const JUNCTION_RING_WIDTH: float = 4.0
const JUNCTION_PULSE_SCALE: float = 1.15
const JUNCTION_DASH_TOTAL: float = 250.0
const JUNCTION_DASH_ON: float = 12.0
const JUNCTION_DASH_OFF: float = 8.0
const JUNCTION_DASH_WIDTH: float = 4.0
const JUNCTION_INACTIVE_RADIUS: float = 10.0
const JUNCTION_ARC_POINTS: int = 48
# TODO(spec): 矢印の大きさ・位置・向きを測る距離は仕様に無い。仮値。
const JUNCTION_DIR_SAMPLE: float = 40.0  # 出口の向きを測る、出口先頭からの距離
const JUNCTION_ARROW_BASE: float = 20.0
const JUNCTION_ARROW_TIP: float = 58.0
const JUNCTION_ARROW_HALF_W: float = 14.0
const JUNCTION_ARROW_OUTLINE: float = 3.0
const JUNCTION_SMALL_ARROW_BASE: float = 12.0
const JUNCTION_SMALL_ARROW_TIP: float = 28.0
const JUNCTION_SMALL_ARROW_HALF_W: float = 7.0

# --- トロッコの仮素材（16.5）。原点はレール上 ---
const TROLLEY_TOP_W: float = 96.0
const TROLLEY_BOTTOM_W: float = 80.0
const TROLLEY_H: float = 48.0
const TROLLEY_WHEEL_R: float = 9.0
const TROLLEY_HUB_R: float = 3.0
const TROLLEY_WHEEL_X: float = 26.0  # TODO(spec): 車輪の左右位置は仕様に無い。仮値
const TROLLEY_BAND_H: float = 12.0
const TROLLEY_OUTLINE: float = 3.0
const STRIPE_W: float = 6.0  # ストライプ1本の幅（黄と墨で同じ幅）

# --- 標的の仮素材（16.4、16.5）。原点は下辺中央、寸法はデザイン案の StyleGuide から ---
const OBJECT_OUTLINE: float = 3.0
const LIMB_OUTLINE: float = 2.0  # ダミー人形の手足
const CRATE_BRACE_W: float = 4.0
const BARREL_RADIUS: int = 6
const BARREL_BAND_Y: Array = [14.0, 42.0]  # 帯の高さ（下端から）
const DRUM_RADIUS: int = 4
const DRUM_BAND_H: float = 22.0
const DRUM_BAND_OUTLINE: float = 2.0
const DRUM_SIGN_HALF_W: float = 8.0
const DRUM_SIGN_H: float = 15.0
const DRUM_SIGN_OUTLINE: float = 2.5
const BRICK_ROW_H: float = 20.0
const MORTAR_W: float = 2.0
const DUMMY_HEAD: Vector2 = Vector2(0, -70)
const DUMMY_HEAD_R: float = 10.0
const DUMMY_TORSO: Rect2 = Rect2(-12, -57, 24, 30)
const DUMMY_TORSO_RADIUS: int = 4
# 腕2本・脚2本。デザイン案の腕は幅34pxにはみ出すので、6.3 の幅32pxに収めた
const DUMMY_LIMBS: Array = [Rect2(-16, -55, 5, 24), Rect2(11, -55, 5, 24), Rect2(-10, -22, 8, 22), Rect2(2, -22, 8, 22)]
const DUMMY_LIMB_RADIUS: int = 2
const DUMMY_BELT: Rect2 = Rect2(-11, -27, 22, 5)
const DUMMY_MARKERS: Array = [Vector2(0, -70), Vector2(0, -45)]  # 頭と胸
const DUMMY_MARKER_R: float = 5.0
const MARKER_ARC_STEPS: int = 8

# --- ゴールの仮素材 ---
# TODO(spec): ゴールの見た目は仕様に無い。警告黄×墨の縞の柱で仮置き
const GOAL_POLE_W: float = 16.0
const GOAL_POLE_H: float = 160.0
const GOAL_BLOCK_H: float = 20.0

# --- タイトル・設定画面（17.1, 17.2, 17.6） ---
# 共通（17.1、16.4）。縞の横幅はデザイン案（縞に直交する向きで帯の高さと同じ幅）を横方向に直した値
const UI_EDGE_BAND_H: float = 20.0  # 画面端のストライプ帯
const UI_EDGE_STRIPE_W: float = 28.0
const UI_PANEL_BAND_H: float = 14.0  # パネル上端のストライプ帯
const UI_PANEL_STRIPE_W: float = 20.0
const UI_GRID_STEP: float = 40.0  # メニュー画面の背景の方眼
const UI_GRID_ALPHA: float = 0.05
const UI_PANEL_BORDER: float = 4.0  # TODO(spec): パネルの枠（墨4px）はデザイン案の値。仕様に無い
const UI_PANEL_SHADOW: Vector2 = Vector2(10, 10)
const UI_FOCUS_W: float = 4.0  # FR-47a: 墨の枠と警告黄の外枠の太さ
const UI_THIN_BORDER: int = 2  # 副ボタンと確認欄の枠
const UI_PRIMARY_H: float = 60.0
const UI_PRIMARY_FONT_SIZE: int = 26
const UI_PRIMARY_SHADOW: Vector2 = Vector2(6, 6)
# TODO(spec): 生成り地の上の主ボタンの枠と影は仕様に無い（16.4 は墨地の影だけ）。デザイン案の墨3px枠と墨4pxずらしの影
const UI_PRIMARY_BORDER_ON_PAPER: int = 3
const UI_PRIMARY_SHADOW_ON_PAPER: Vector2 = Vector2(4, 4)
const UI_SECONDARY_H: float = 52.0
const UI_SECONDARY_FONT_SIZE: int = 19  # 17.1（デザイン案は 20px）
const UI_KEY_FONT_SIZE: int = 14  # ボタン右端のキー表示
const UI_BUTTON_PAD: float = 20.0  # ボタンの文字の左右の余白
const UI_KEY_GAP: float = 12.0  # ボタンの文字とキー表示の間
const UI_LETTER_SPACING: int = 2  # Courier Prime の英字ラベルの字間（デザイン案の 0.12em）

# タイトル（17.2）
const TITLE_FACILITY_FONT_SIZE: int = 18
const TITLE_NAME_FONT_SIZE: int = 124
const TITLE_HELP_FONT_SIZE: int = 15
# TODO(spec): バージョンの付け方は仕様に無い。デザイン案の表記。書き出し設定と揃えるなら project.godot の
#             application/config/version に移す
const GAME_VERSION: String = "v0.1"
# タイトルの挿絵（700×560）。座標は挿絵の左上から、デザイン案の SVG の値
const TITLE_ART_GROUND: Rect2 = Rect2(0, 500, 700, 60)
const TITLE_ART_ROUTES: Array = [  # 分岐の手前と選択中の出口（上）、選ばれていない出口（下）
	[Vector2(0, 420), Vector2(260, 420), Vector2(360, 340), Vector2(700, 340)],
	[Vector2(260, 420), Vector2(360, 480), Vector2(700, 480)]]
const TITLE_ART_OTHER_ROUTE_ALPHA: float = 0.5
const TITLE_ART_SLEEPER_DROP: float = 6.0  # 枕木はレールの中心より 6px 下
const TITLE_ART_SLEEPER_W: float = 12.0  # 16.3: 12px幅の破線、6px描いて18px空ける
const TITLE_ART_SLEEPER_ON: float = 6.0
const TITLE_ART_SLEEPER_OFF: float = 18.0
const TITLE_ART_JUNCTION: Vector2 = Vector2(260, 420)
const TITLE_ART_SPEED_LINES: Array = [  # [始点, 終点, 不透明度]
	[Vector2(230, 300), Vector2(300, 300), 0.35], [Vector2(250, 318), Vector2(320, 318), 0.25],
	[Vector2(210, 284), Vector2(290, 284), 0.2]]
const TITLE_ART_SPEED_LINE_W: float = 3.0
const TITLE_ART_TROLLEY: Vector2 = Vector2(428, 340)  # レール上の原点
const TITLE_ART_IMPACT: Array = [  # 衝突の星
	Vector2(492, 296), Vector2(506, 272), Vector2(514, 294), Vector2(540, 286), Vector2(522, 306), Vector2(544, 322),
	Vector2(516, 318), Vector2(508, 344), Vector2(498, 320), Vector2(472, 326), Vector2(490, 308), Vector2(470, 292)]
const TITLE_ART_DUMMY_POS: Vector2 = Vector2(580, 190)  # 足元
const TITLE_ART_DUMMY_DEG: float = -38.0
const TITLE_ART_DUMMY_SCALE: float = 2.2
const TITLE_ART_CRATE_POS: Vector2 = Vector2(640, 250)  # 中心
const TITLE_ART_CRATE_DEG: float = 22.0
const TITLE_ART_CRATE_SIZE: float = 68.0
const TITLE_ART_CHIPS: Array = [  # 破片 [矩形, 中心まわりの角度, 色を借りる標的]
	[Rect2(548, 120, 14, 10), 30.0, "crate"], [Rect2(600, 330, 12, 8), -20.0, "crate"],
	[Rect2(530, 230, 10, 10), 45.0, "dummy"]]
const TITLE_ART_CHIP_OUTLINE: float = 2.0

# 設定（17.6、FR-47b, FR-47c）
const SETTINGS_HEAD_FONT_SIZE: int = 34
const SETTINGS_SUB_FONT_SIZE: int = 15
const SETTINGS_LABEL_FONT_SIZE: int = 18
const SETTINGS_TEXT_FONT_SIZE: int = 16
const SETTINGS_VALUE_FONT_SIZE: int = 22
const SETTINGS_NOTE_FONT_SIZE: int = 14
const SETTINGS_TRACK_H: float = 12.0  # TODO(spec): 音量スライダーの見た目は仕様に無い（デザイン案はブラウザ標準）
const SETTINGS_GRABBER: Vector2i = Vector2i(14, 28)
const SETTINGS_CONFIRM_PAD: Vector2 = Vector2(16, 14)
const SETTINGS_FOOTER_DASH: float = 6.0  # 「戻る」の上の破線

# --- ステージ選択（17.3、FR-41, FR-41a） ---
# 文字の大きさ・線・アイコンはデザイン案（StageSelect）の値。並びの位置と大きさは stage_select.tscn
const SELECT_RULE_STEP: float = 32.0  # 17.1: 生成り地の横罫の間隔
const SELECT_BAND_H: float = 12.0  # ヘッダーの下のストライプ
const SELECT_STRIPE_W: float = 20.0  # デザイン案の 14px 幅の縞を横方向に直した値
const SELECT_HEAD_FONT_SIZE: int = 36
const SELECT_SUB_FONT_SIZE: int = 16
const SELECT_TOTAL_FONT_SIZE: int = 24
const SELECT_TOTAL_STAR_FONT_SIZE: int = 26
const SELECT_CARD_BORDER: float = 2.0
const SELECT_CARD_SHADOW: Vector2 = Vector2(8, 8)  # 選択中のカードの影
const SELECT_LOCKED_DASH: float = 6.0  # 未解放カードの破線
const SELECT_NUM_FONT_SIZE: int = 15
const SELECT_NAME_FONT_SIZE: int = 20
const SELECT_STARS_FONT_SIZE: int = 20
const SELECT_BEST_FONT_SIZE: int = 16
const SELECT_LOCKED_FONT_SIZE: int = 18
const SELECT_LOCK_HINT_FONT_SIZE: int = 14
# 「済」の丸判子: カードの右上の角から見た中心、外径の半径、線の太さ
const SELECT_STAMP_CENTER: Vector2 = Vector2(-32, 32)
const SELECT_STAMP_R: float = 20.0
const SELECT_STAMP_W: float = 3.0
const SELECT_STAMP_FONT_SIZE: int = 18
# TODO(spec): 判子の傾きは仕様に無い。デザイン案の第1〜3試験の -12・8・-6 度に、第4〜10試験の分を足した
const SELECT_STAMP_DEG: Array = [-12.0, 8.0, -6.0, 10.0, -8.0, 7.0, -10.0, 5.0, -7.0, 12.0]
const SELECT_ARC_POINTS: int = 32
# TODO(spec): 17.3 はカード5枚。10ステージは SELECT_PAGE_SIZE 枚ずつのページに分け、ヘッダーのタブで今のページを示す
#             （more-stages-design.md）。タブの並びの位置は stage_select.tscn
const SELECT_PAGE_SIZE: int = 5
const SELECT_TAB_FONT_SIZE: int = 17
const SELECT_TAB_BORDER: float = 2.0
# 新要素のアイコン（8.1）。64×64 の枠の中の [原点（標的は下辺中央、踏切台は左下の角、トロッコはレール上）, 拡大率]
const SELECT_ICON_PLACE: Dictionary = {
	"crate": [Vector2(32, 54), 0.92], "dummy": [Vector2(32, 61), 0.73], "drum": [Vector2(32, 60), 0.93],
	"jump": [Vector2(2, 58), 0.5], "trolley": [Vector2(42, 32), 0.4]}
# TODO(spec): 第5試験（jump）のアイコンはデザイン案に無い。レールの上の踏切台から、トロッコが傾いて飛び出す絵にした
const SELECT_JUMP_TROLLEY_DEG: float = -20.0
# レンガ壁のアイコン: デザイン案の短い壁（段の高さ14px、奇数段の縦目地は中心から±8px）
const SELECT_WALL_ICON: Rect2 = Rect2(16, 4, 32, 56)
const SELECT_WALL_ICON_ROW: float = 14.0
const SELECT_WALL_ICON_JOINT: float = 8.0
# 未解放の錠前: デザイン案の 24×24 の図の値。枠いっぱいに拡大して描く
const SELECT_LOCK_VIEW: float = 24.0
const SELECT_LOCK_BODY: Rect2 = Rect2(5, 11, 14, 10)
const SELECT_LOCK_SHACKLE_C: Vector2 = Vector2(12, 8)  # つるの半円の中心
const SELECT_LOCK_SHACKLE_R: float = 4.0
const SELECT_LOCK_KEYHOLE: Array = [Vector2(12, 15), Vector2(12, 17)]
const SELECT_LOCK_LINE_W: float = 1.8
# 詳細パネル（FR-41a）と下端
const SELECT_DETAIL_NUM_FONT_SIZE: int = 16
const SELECT_DETAIL_NAME_FONT_SIZE: int = 30
const SELECT_DETAIL_TEXT_FONT_SIZE: int = 17
const SELECT_HELP_FONT_SIZE: int = 15

# --- リザルト（17.7、FR-45, FR-46, FR-46a） ---
# 判子の演出（17.7）。時間はすべて実時間（Engine.time_scale を無視する）
const RESULT_STAMP_DELAY: float = 0.4  # 開いてから判子を押すまで
const RESULT_STAMP_POP_SCALE: float = 1.6
const RESULT_STAMP_POP_TIME: float = 0.12
const RESULT_SHAKE_AMP: float = 6.0
const RESULT_SHAKE_TIME: float = 0.15
# 判子の形（17.7）。位置は報告書の左上から、判子の外形の左上（デザイン案）
const RESULT_PASS_STAMP_SIZE: Vector2 = Vector2(150, 150)
const RESULT_FAIL_STAMP_SIZE: Vector2 = Vector2(176, 96)
const RESULT_PASS_STAMP_DEG: float = -14.0
const RESULT_FAIL_STAMP_DEG: float = -10.0
const RESULT_PASS_STAMP_POS: Vector2 = Vector2(454, 118)
const RESULT_FAIL_STAMP_POS: Vector2 = Vector2(434, 112)
const RESULT_STAMP_ALPHA: float = 0.92  # デザイン案の opacity
const RESULT_STAMP_LINE: float = 6.0  # 丸判子の線
const RESULT_STAMP_DOUBLE_LINE: float = 2.0  # 角判子の二重線の1本とすき間（合わせて 6px）
const RESULT_STAMP_ARC_POINTS: int = 64  # 円弧を描く点の数
const RESULT_PASS_STAMP_FONT_SIZE: int = 48
const RESULT_PASS_STAMP_SUB_FONT_SIZE: int = 13
const RESULT_PASS_STAMP_TEXT_Y: float = 66.0  # 「合格」の行の中心（判子の上端から）
const RESULT_PASS_STAMP_SUB_Y: float = 100.0  # 「衝突試験場」の行の中心
const RESULT_FAIL_STAMP_FONT_SIZE: int = 40
# 報告書（17.7、デザイン案）
const RESULT_CLIP_SIZE: Vector2 = Vector2(120, 30)  # 上端中央のクリップ（墨の枠を含む）
const RESULT_CLIP_RISE: float = 18.0  # クリップが報告書の上端からはみ出す高さ
const RESULT_CLIP_BORDER: float = 3.0
const RESULT_HEAD_FONT_SIZE: int = 36
const RESULT_HEAD_RULE: float = 3.0  # 見出しの下の線
const RESULT_NO_FONT_SIZE: int = 15  # 「TEST REPORT No.00N」
const RESULT_NO_LINE_HEIGHT: float = 1.4
const RESULT_LABEL_COL_W: float = 150.0  # 17.7: ラベル列
const RESULT_LABEL_FONT_SIZE: int = 16
const RESULT_TEXT_FONT_SIZE: int = 16
const RESULT_NAME_FONT_SIZE: int = 18  # 試験名
const RESULT_VALUE_FONT_SIZE: int = 20
const RESULT_SCORE_FONT_SIZE: int = 30
const RESULT_REASON_FONT_SIZE: int = 26  # 中止理由
const RESULT_NOTE_FONT_SIZE: int = 14  # 「記録には残りません」
const RESULT_VALUE_GAP: float = 20.0  # 到達速度と不足分、中止時の得点と注記の間（デザイン案の全角空白）
const RESULT_TAG_FONT_SIZE: int = 18  # 「最高記録更新」の札（デザイン案は 14px）
const RESULT_TAG_PAD: Vector2 = Vector2(10, 2)
const RESULT_TAG_BORDER: int = 2
const RESULT_TAG_GAP: float = 14.0
const RESULT_DASH_W: float = 2.0  # ★の欄の上の破線
const RESULT_DASH: float = 6.0
const RESULT_ICON_BOX: float = 24.0  # ★と電球の座標の枠（デザイン案の SVG の viewBox）
const RESULT_STAR_SIZE: float = 52.0
const RESULT_STAR_GAP: float = 10.0
const RESULT_STAR_OUTLINE: float = 1.5  # 枠 24 での太さ
const RESULT_STAR_DASH: float = 2.0  # 未獲得の★の破線（枠 24 での長さ）
const RESULT_STAR_POINTS: Array = [Vector2(12, 2), Vector2(15, 9), Vector2(22, 9.5), Vector2(16.5, 14), Vector2(18.5, 21),
		Vector2(12, 17), Vector2(5.5, 21), Vector2(7.5, 14), Vector2(2, 9.5), Vector2(9, 9)]
const RESULT_HINT_PAD: Vector2 = Vector2(18, 16)
const RESULT_HINT_LINE_HEIGHT: float = 1.7
const RESULT_HINT_ICON_SIZE: float = 28.0
const RESULT_HINT_ICON_LINE: float = 2.0
const RESULT_HINT_BULB_CENTER: Vector2 = Vector2(12, 9)  # 電球の丸（枠 24 の座標）
const RESULT_HINT_BULB_RADIUS: float = 6.0
const RESULT_HINT_BULB_ARC_DEG: Vector2 = Vector2(131.6, 408.4)  # 左下から上を回って右下まで
const RESULT_HINT_BULB_LINES: Array = [  # 電球の首と口金
	[Vector2(16, 13.5), Vector2(15.2, 14.3), Vector2(15, 16), Vector2(9, 16), Vector2(8.8, 14.3), Vector2(8, 13.5)],
	[Vector2(9, 18), Vector2(15, 18)], [Vector2(10, 21), Vector2(14, 21)]]
# 右列のボタン（x=880、幅300 は result.tscn）。デザイン案の寸法で、17.1 の範囲内
const RESULT_BUTTONS_Y_CLEARED: float = 330.0
const RESULT_BUTTONS_Y_FAILED: float = 380.0
const RESULT_PRIMARY_H: float = 64.0
const RESULT_PRIMARY_FONT_SIZE: int = 24
const RESULT_SECONDARY_H: float = 54.0

# --- HUD・ポーズ（17.4, 17.5、FR-42, FR-44） ---
# HUD。寸法はデザイン案から
const HUD_MARGIN: float = 24.0
const HUD_PANEL_PAD: Vector2 = Vector2(16, 8)  # パネルの左右・上の余白
const HUD_SCORE_PAD_BOTTOM: float = 10.0
const HUD_SPEED_PAD_BOTTOM: float = 14.0
const HUD_SCORE_MIN_W: float = 200.0
const HUD_LABEL_FONT_SIZE: int = 13  # 「SCORE」「SPEED」
const HUD_SCORE_FONT_SIZE: int = 40
const HUD_SPEED_FONT_SIZE: int = 44
const HUD_UNIT_FONT_SIZE: int = 16
const HUD_STAGE_RECT: Rect2 = Rect2(490, 24, 300, 34)  # x は画面の中央にそろえ直す
const HUD_STAGE_ALPHA: float = 0.85
const HUD_STAGE_FONT_SIZE: int = 15
const HUD_STAGE_GAP: float = 12.0
const HUD_SPEED_W: float = 280.0
const HUD_ROW_GAP: float = 6.0
const HUD_GAUGE_H: float = 14.0
const HUD_GAUGE_BORDER: float = 2.0
const HUD_GAUGE_LABEL_GAP: float = 10.0
const HUD_MOMENTUM_FONT_SIZE: int = 13
const HUD_KEY_FONT_SIZE: int = 14
const HUD_KEY_BOTTOM: float = 18.0
const HUD_KEY_OUTLINE: int = 4
const HUD_COMBO_GAP: float = 6.0  # スコアとコンボの札の間
const HUD_COMBO_FONT_SIZE: int = 20
const HUD_COMBO_PAD: Vector2 = Vector2(14, 4)
const HUD_COMBO_BORDER: int = 3
# ポーズ
const PAUSE_VEIL_ALPHA: float = 0.72
const PAUSE_HEAD_FONT_SIZE: int = 32
const PAUSE_SUB_FONT_SIZE: int = 15
const PAUSE_HELP_FONT_SIZE: int = 14
# リザルトへ移るまで（ゲーム内時刻）
# TODO(spec): ゴールからリザルトまでの間は仕様に無い（失敗は FAIL_DELAY）。ゴールに着いたのが見えるように少し待つ
const GOAL_RESULT_DELAY: float = 1.0
# TODO(spec): ステージデータエラーを出してからステージ選択に戻るまでの秒数は仕様に無い
const STAGE_ERROR_DELAY: float = 2.0

# --- ステージデータの検証（6.4）・レベルデザイン（8.2） ---
const JOINT_TOLERANCE: float = 1.0  # 6.4-3: 出口・合流先の始点と、元のセグメントの終点のずれの上限（px）
const DECISION_LEAD_TIME: float = 1.0  # L-3: 分岐の判断材料が画面に見えている、分岐に着く前の秒数
const REQUIRED_SPEED_MARGIN: float = 50.0  # L-5: required_speed は到達速度からこの値（px/s）を引いた値以下
const STAGE_LENGTH_MIN: float = 15000.0  # L-6: スタートからゴールまでの経路の長さ（px）
const STAGE_LENGTH_MAX: float = 30000.0
const FIRST_WALL_MAX: float = 5000.0  # L-7: ステージ3の最初の wall までの経路距離（px）
const BRANCH_Y_RANGE: float = 250.0  # L-8: 分岐から MIN_JUNCTION_GAP の範囲の出口の y は、分岐点の y ± この値

# --- ① プレイ画面の絵（依頼者の判断で足した。設計書 docs/superpowers/specs/2026-09-26-play-screen-art-design.md） ---
# 時間帯（設計書4章）。名前は TimeOfDay.NAMES、色は Palette.TOD_*
const TOD_LAMP: Dictionary = {"morning": 0.0, "noon": 0.0, "sunset": 0.35, "dusk": 0.75, "night": 1.0}  # 照明器具
const TOD_SHAFT: Dictionary = {"morning": 0.16, "noon": 0.10, "sunset": 0.30, "dusk": 0.0, "night": 0.0}  # 差し込む光
const TOD_STARS: Dictionary = {"morning": false, "noon": false, "sunset": false, "dusk": true, "night": true}
const TOD_GLOW: Dictionary = {"morning": 0.0, "noon": 0.0, "sunset": 0.4, "dusk": 0.8, "night": 1.0}  # 光る物のにじみ
const TOD_HEADLIGHT: Dictionary = {"morning": 0.0, "noon": 0.0, "sunset": 0.5, "dusk": 0.8, "night": 1.0}  # 前照灯
const TOD_AMBIENT_MIN_LUMA: float = 0.25  # 全体に掛ける色の明るさの下限（深夜でも標的が見分けられるように）
# 描画の共通部品（設計書2章・3章）
const ROUND_STEPS: int = 4  # 角丸1つを何本の線で近似するか
const CIRCLE_STEPS: int = 24
const NOISE_SIZE: int = 512  # 雑音の模様の一辺（256px だと繰り返しが目立った）
const NOISE_OCTAVES: int = 3
const NOISE_FREQUENCY: Dictionary = {"blotch": 0.006, "grain": 0.35, "fleck": 0.35}
const NOISE_SEED: Dictionary = {"blotch": 9, "grain": 2, "fleck": 3}
const NOISE_RAMP: Dictionary = {  # 雑音の値がこの範囲で、色の濃さ 0→1（下の端より小さい所は描かない）
	"blotch": Vector2(0.55, 1.0), "grain": Vector2(0.5, 1.0), "fleck": Vector2(0.6, 1.0)}
const GLOW_TEXTURE_SIZE: int = 128
const CONE_TEXTURE_H: int = 256  # 照明の円錐の絵の長さ。頂点は上端の中央。幅は円錐が収まるよう角度から決める
const CONE_HALF_ANGLE_DEG: float = 22.0  # 見本の絵の照明に合わせた
const CONE_EDGE_SOFT: float = 0.35  # 円錐の縁のぼかし（中心線からの角度の割合）
# 影（設計書2章）
const SHADOW_OFFSET: Vector2 = Vector2(8, 11)  # 画面の右下へ
const SHADOW_BLUR: float = 5.0
const SHADOW_STEPS: int = 3
const SHADOW_ALPHA: float = 0.32
# 描画順（設計書2章）: 奥の壁 < 影 < 支柱 < 照明器具 < 地面（Z_GROUND）< 線路・標的
const Z_BACKDROP: int = -10
const Z_SHADOW: int = -6
const Z_TOWER: int = -5
const Z_LAMP: int = -4
# 標的とトロッコの質感（設計書3章）。寸法は見本の絵（2026-09-26-play-screen-art-mock.html）から
const CRATE_PLANKS: int = 3  # 木箱の板の枚数（継ぎ目は枚数 - 1 本）
const CRATE_SEAM_W: float = 1.5
const CRATE_GRAIN: Array = [  # 木目の折れ線（木箱の左上の角から。見本の曲線を点でなぞった）
	[Vector2(2, 6), Vector2(14, 5), Vector2(26, 7.5), Vector2(46, 6)],
	[Vector2(4, 11), Vector2(16, 10), Vector2(22, 12.5), Vector2(30, 11)],
	[Vector2(2, 23), Vector2(18, 21.5), Vector2(30, 25), Vector2(46, 22)],
	[Vector2(18, 28), Vector2(26, 27), Vector2(34, 29.5), Vector2(44, 28)],
	[Vector2(2, 39), Vector2(12, 37.5), Vector2(30, 41), Vector2(46, 38)]]
const CRATE_GRAIN_W: float = 1.0
const CRATE_BRACE_INSET: float = 4.0  # 筋交いと釘の、角からの内側
const CRATE_BRACE_EDGE_SHIFT: Vector2 = Vector2(0, -1.5)
const CRATE_BRACE_EDGE_W: float = 1.2
const CRATE_NAIL_R: float = 1.6
const BARREL_STOP_AT: Array = [0.0, 0.3, 0.42, 0.75, 1.0]  # Palette.BARREL_STOPS の位置（左→右）
const BARREL_STAVES: int = 5  # 縦の板の枚数
const BARREL_STAVE_W: float = 1.3
const BARREL_HOOP_H: float = 6.0  # たがの高さ（BARREL_BAND_Y の位置を中心に）
const HOOP_STOP_AT: Array = [0.0, 0.35, 1.0]
const PLASTIC_STOP_AT: Array = [0.0, 0.5, 1.0]  # 部品の左上→右下
const DUMMY_GLOSS: Array = [[Vector2(-5, -75), Vector2(3, 2)], [Vector2(-7, -52), Vector2(2.5, 1.6)]]  # [中心, 半径]
const DRUM_STOP_AT: Array = [0.0, 0.3, 0.45, 0.8, 1.0]
const DRUM_BAND_STOP_AT: Array = [0.0, 0.35, 0.8, 1.0]
const DRUM_RIM_Y: Array = [5.0, 55.0]  # 縁の段差の高さ（下端から）
const DRUM_RIM_W: float = 2.0
const DRUM_GLINT_X: float = 9.0  # 縦の光の筋の、左端からの位置と幅
const DRUM_GLINT_W: float = 4.0
const DRUM_GLOW_RADIUS: float = 50.0  # 暗い時間帯の赤いにじみ（設計書4章）
const BRICK_SEED: int = 7  # レンガの色むらの乱数（どの壁も毎回同じ模様）
const BRICK_EDGE_LIGHT_H: float = 2.0
const BRICK_EDGE_SHADE_H: float = 3.0
const TROLLEY_GLINT: Array = [Vector2(-24, -48), Vector2(-6, -48), Vector2(-22, -12), Vector2(-40, -12)]  # 斜めの光の反射
const TROLLEY_RIVETS: Array = [Vector2(-41, -44), Vector2(41, -44), Vector2(-36, -16), Vector2(36, -16)]
const TROLLEY_RIVET_R: float = 2.0
const TROLLEY_BAND_SHADE_H: float = 2.0
const TROLLEY_AXLE_GLINT_DEG: Vector2 = Vector2(200, 290)  # 車輪の軸の光の円弧（左上）
const TROLLEY_AXLE_GLINT_INSET: float = 2.5
const TROLLEY_AXLE_GLINT_W: float = 1.5
# 線路・支柱・床（設計書2章）。枕木は 16.3（12px 幅、6px 描いて 18px 空ける）
const SLEEPER_DROP: float = 7.0  # 枕木の中心はレールの中心より下
const SLEEPER_W: float = 12.0
const SLEEPER_ON: float = 6.0
const SLEEPER_OFF: float = 18.0
const SLEEPER_EDGE_DROP: float = 4.0  # 枕木の下端の影の、枕木の中心からの下がり
const SLEEPER_EDGE_W: float = 4.0
const RAIL_TOP_SHIFT: float = 2.0  # レールの上面の光の筋の、レールの中心からの上がり
const RAIL_TOP_W: float = 1.5
const TOWER_SPACING: float = 480.0
const TOWER_W: float = 28.0  # 縦材の中心どうしの間
const TOWER_LEG_W: float = 6.0
# 床と支柱を分けて描く塊の幅（ステージ全体を1つに描くと、画面の外も毎フレーム描いてしまう）。
# 雑音の模様（NOISE_SIZE）と縁石の縞（CURB_STRIPE_W の2倍）の倍数にして、塊の継ぎ目で模様をずらさない
const WORLD_CHUNK_W: float = 2560.0
const TOWER_EDGE_W: float = 1.5
const TOWER_BRACE_W: float = 2.5
const TOWER_BAY: float = 36.0  # 筋交い1段の高さ
const TOWER_TOP_DROP: float = 14.0  # 支柱の上端はレールの中心の下（枕木の下）
const TOWER_CAP_H: float = 6.0
const TOWER_CAP_OUT: float = 8.0  # 上の板の、縦材からのはみ出し
const TOWER_FOOT_H: float = 8.0
const TOWER_FOOT_OUT: float = 10.0
const TOWER_MIN_H: float = 20.0  # これより低い支柱は立てない
const PX_PER_METER: float = DISPLAY_SPEED_DIV * 3.6  # FR-43 の換算（10px/s = 1km/h）で 1m = 36px
const SCALE_MAJOR_EVERY: int = 10  # 長い目盛りと数字の間隔（m）
const SCALE_MAJOR_H: float = 14.0
const SCALE_MINOR_H: float = 6.0
const SCALE_MAJOR_W: float = 2.0
const SCALE_MINOR_W: float = 1.5
const SCALE_FONT_SIZE: int = 13  # 16.2 の Courier Prime の下限
const SCALE_LABEL_GAP: float = 5.0
const SCALE_LABEL_LIFT: float = 5.0
const FLOOR_FADE_H: float = 60.0  # 床のぼかしの高さ（その下は FLOOR_BOTTOM）
const FLOOR_NOISE_H: float = 400.0
const FLOOR_NOISE_ALPHA: float = 0.35
const CURB_H: float = 10.0  # 墨の線の下の警告ストライプの縁石
const CURB_STRIPE_W: float = 10.0
const CURB_SHADE_H: float = 3.0
# 奥の壁（設計書2章）。1枚（BACKDROP_TILE_W）を横に繰り返す。高さは床（ground_y）から測る
const BACKDROP_SCROLL: float = 0.85  # 線路に対する横の流れの速さ
const BACKDROP_TILE_W: float = 1600.0  # 方眼（200px）とパネル（PANEL_W）の倍数
const BACKDROP_REPEAT: int = 3
const BACKDROP_H: float = 2400.0  # 床から壁の上端まで
const WALL_STOP_AT: Array = [0.0, 0.7, 1.0]
const PANEL_W: float = 320.0  # コンクリートのパネル
const PANEL_H: float = 240.0
const PANEL_SEAM_W: float = 3.0
const PANEL_BOLT_INSET: float = 14.0
const PANEL_BOLT_R: float = 3.0
const BACKDROP_GRID_MINOR_ALPHA: float = 0.8  # 方眼（16.3 の GRID_MINOR / GRID_MAJOR）の濃さ
const BACKDROP_GRID_MAJOR_ALPHA: float = 0.7
const BACKDROP_GRID_MINOR_W: float = 1.0  # 16.3
const BACKDROP_GRID_MAJOR_W: float = 2.0
const GRID_MINOR_STEP: float = 40.0  # 16.3
const GRID_MAJOR_STEP: float = 200.0
const WALL_BLOTCH_ALPHA: float = 0.25
const WALL_GRAIN_ALPHA: float = 0.35
const WINDOW_BOTTOM: float = 410.0  # 床から窓の下端まで
const WINDOW_H: float = 100.0
const WINDOW_W: float = 256.0  # パネル1枚に窓1つ
const WINDOW_MARGIN_X: float = 32.0  # パネルの左端から窓の左端まで
const WINDOW_FRAME_W: float = 8.0
const WINDOW_OUTLINE: float = 3.0
const MULLION_W: float = 5.0
const MULLION_COLS: int = 4  # 縦の桟で分ける数（横の桟は真ん中に1本）
const STAR_COUNT: int = 7  # 窓1つの星
const STAR_PAD: float = 12.0
const STAR_STEP: Vector2 = Vector2(37, 23)  # 星を散らす間隔（窓の中で折り返す）
const STAR_R_MIN: float = 1.2
const STAR_R_STEP: float = 0.5
const SHAFT_SLANT: float = 330.0  # 窓から差し込む光の、床までの横のずれ
const BACKDROP_MARKERS: Array = [Vector2(180, 570), Vector2(1100, 570)]  # 計測マーカー [1枚の左端からの x, 床からの高さ]。窓と重ねない
const MARKER_R: float = 18.0
const MARKER_OUTLINE: float = 3.0
# 照明（設計書4章）。円錐の光は DrawUtil.cone_texture() を texture_scale 倍して使う
const LAMP_SPACING: float = 1200.0  # 照明器具の間隔（同時に当たる照明は15個前後が上限。画面に入るのは2〜3個）
const LAMP_FIRST_X: float = 400.0
const LAMP_REACH: float = 500.0  # この範囲の一番高い線路より上に吊る
const LAMP_SAMPLE: float = 50.0  # 線路の高さを調べる間隔
const LAMP_CLEARANCE: float = 160.0
const LAMP_SIGN_GAP: float = 40.0  # 必要速度の標識（判断材料、L-3）の上端より、電球の下端をこれだけ上に
const LAMP_ROD_H: float = 1400.0  # 電球の下端から吊り棒の上端まで
const LAMP_ROD_W: float = 6.0
const LAMP_HOUSING_H: float = 14.0
const LAMP_HOUSING_TOP_W: float = 32.0
const LAMP_HOUSING_BOTTOM_W: float = 52.0
const LAMP_OUTLINE: float = 2.0
const LAMP_BULB_RECT: Rect2 = Rect2(-20, -3, 40, 3)
const LAMP_GLOW_RADIUS: float = 46.0
const LAMP_LIGHT_SCALE: float = 3.0
const LAMP_ENERGY: float = 0.8  # 強さ 1.0（深夜）のときの光の強さ
const HEADLIGHT_AT: Vector2 = Vector2(44, -26)  # トロッコの前（原点はレール上）
const HEADLIGHT_SCALE: float = 3.5
const HEADLIGHT_ENERGY: float = 0.7
const JUNCTION_GLOW_RADIUS: float = 56.0
const JUNCTION_RIM_INSET: float = 5.0  # 円盤の縁の光の、外周からの内側
const JUNCTION_RIM_W: float = 2.0
const JUNCTION_RIM_DEG: Vector2 = Vector2(190, 260)  # 左上
const SHORT_ARC_POINTS: int = 8  # 短い円弧（分岐の縁の光・車輪の軸の光・判子のかすれ）を描く点の数
const SIGN_GLOW_RADIUS: float = 80.0
const SIGN_DEPTH: float = 3.0  # 標識の板の厚み（右下にずらした墨）
const SIGN_BOLT_INSET: Vector2 = Vector2(8, 7)
const SIGN_BOLT_R: float = 2.0
# メニューの質感（設計書5章）
const MENU_FLECK_ALPHA: float = 0.2  # 墨地の上の明るい粒
const PAPER_GRAIN_ALPHA: float = 0.25  # 紙の粒
const TITLE_ART_SPOT: Rect2 = Rect2(40, -60, 620, 620)  # タイトルの挿絵に当てるスポットライト（挿絵の左上から）
const TITLE_ART_SPOT_ALPHA: float = 0.14
const RESULT_CLIP_GLINT_W: float = 1.5  # クリップの上の光の筋
# 判子のかすれ: 合格は丸の線の上の [始まりの角度, 長さ（度）, 線の中心からのずれ]、不合格は二重線の上の
# [横の位置（幅に対する割合）, 0 = 上の辺・1 = 下の辺]
const RESULT_STAMP_WEAR_PASS: Array = [[20.0, 14.0, 1.5], [75.0, 9.0, -1.5], [130.0, 18.0, 1.0], [200.0, 11.0, -1.0],
	[250.0, 7.0, 1.5], [310.0, 15.0, -1.5]]
const RESULT_STAMP_WEAR_FAIL: Array = [[0.15, 0], [0.4, 0], [0.7, 0], [0.25, 1], [0.6, 1], [0.85, 1]]
const RESULT_STAMP_WEAR_W: float = 1.6
const RESULT_STAMP_WEAR_LEN: float = 5.0

# --- ② 演出と手触り（依頼者の外出中に決めた仮の値。設計書 docs/superpowers/specs/2026-09-26-effects-design.md） ---
const MAX_EFFECTS: int = 60  # World/Effects の下に同時に置く演出の数の上限（古いものから消す）
const Z_FX: int = 5  # 破片パーティクル（Z_PARTICLES）より手前、得点ポップアップ（Z_POPUP）より奥
# 衝突の星（大きさは基本点で変える）
const IMPACT_LIFE: float = 0.16
const IMPACT_SPIKES: int = 7
const IMPACT_R_MIN: float = 18.0
const IMPACT_R_PER_POINT: float = 0.04
const IMPACT_R_MAX: float = 46.0
const IMPACT_INNER: float = 0.45  # 尖りの付け根の半径（外の半径に対する割合）
const IMPACT_OUTLINE: float = 3.0
const IMPACT_SCALE: Vector2 = Vector2(0.6, 1.3)  # 出たとき→消えるとき
const IMPACT_EASE: float = 0.4  # ふくらみ方（ease の曲線。1 未満は始めに速い）
const FAIL_IMPACT_POINTS: int = 800  # 激突・脱線の星の大きさ（基本点に置き換えて）
# 破片（物理ボディにしない。放物線で動かす）。種類: plank（板）・stave（樽板）・metal（金属）・paper（紙吹雪）・
# spark（激突・脱線の火花。光る物で、飛ぶ向きに伸びた線で描く）
const SHARD_COUNT: Dictionary = {"plank": 6, "stave": 6, "metal": 8, "paper": 28, "spark": 14}
const SHARD_SIZE: Dictionary = {"plank": Vector2(22, 6), "stave": Vector2(8, 24), "metal": Vector2(10, 7), "paper": Vector2(10, 14),
	"spark": Vector2(0, 3)}  # spark は y だけ使う（線の太さ）
const SHARD_SPEED: Dictionary = {"plank": Vector2(250, 650), "stave": Vector2(250, 600), "metal": Vector2(300, 800),
	"paper": Vector2(300, 700), "spark": Vector2(400, 950)}  # 速さの最小・最大（px/s）
const SHARD_GRAVITY: Dictionary = {"plank": 1400.0, "stave": 1400.0, "metal": 1200.0, "paper": 300.0, "spark": 1500.0}
const SHARD_DRAG: Dictionary = {"plank": 0.0, "stave": 0.0, "metal": 0.0, "paper": 2.4, "spark": 1.5}  # 空気の抵抗（1秒あたりの割合）
const SHARD_LIFE: Dictionary = {"plank": 1.0, "stave": 1.0, "metal": 1.1, "paper": 1.6, "spark": 0.45}
const SHARD_SPREAD_DEG: float = 70.0  # 飛ぶ向きのばらつき（片側）
const SHARD_SIZE_JITTER: Vector2 = Vector2(0.7, 1.2)  # 1つずつの大きさの倍率（最小・最大）
const SHARD_SPIN: float = 14.0  # 回る速さの最大（rad/s）
const SPARK_STREAK: float = 0.02  # 火花の線の長さ（速さ × この秒数）
# 樽のたがの輪（樽板の破片のうち、この数を輪にする。切れた輪を円弧で描く）
const SHARD_HOOPS: Dictionary = {"stave": 2}
const HOOP_R: float = 16.0
const HOOP_ARC_DEG: float = 250.0
const HOOP_W: float = 3.0
const SHARD_OUTLINE: float = 1.5
const SHARD_FADE: float = 0.3  # 寿命の最後のこの割合で薄くなる
const PAPER_SWAY: float = 70.0  # 紙吹雪の横揺れの速さ（px/s）
const PAPER_SWAY_FREQ: float = 6.0
# 砂ぼこり・煙。値は [始まり, 終わり] か種類ごと
const PUFF_COUNT: Dictionary = {"dust": 5, "smoke": 6}
const PUFF_LIFE: Dictionary = {"dust": 0.7, "smoke": 1.6}
const PUFF_R: Dictionary = {"dust": Vector2(14, 36), "smoke": Vector2(24, 64)}
const PUFF_SPREAD: Dictionary = {"dust": 40.0, "smoke": 60.0}  # 出る所のばらつき（px）
const PUFF_RISE: Dictionary = {"dust": 25.0, "smoke": 70.0}  # 上る速さ（px/s）
const PUFF_ALPHA: Dictionary = {"dust": 0.55, "smoke": 0.75}
const PUFF_SPREAD_Y: float = 0.5  # 出る所の縦のばらつき（横に対する割合）
const PUFF_DRIFT: float = 0.5  # 上りながら横へ流れる量の最大（上る量に対する割合）
const PUFF_EASE: float = 0.5  # ふくらみ方（ease の曲線）
# 爆発
const FIREBALL_LIFE: float = 0.35
const FIREBALL_R: Vector2 = Vector2(40, 170)  # 外側の半径（始まり→終わり）
const FIREBALL_EASE: float = 0.3  # ふくらみ方（ease の曲線）
const FIREBALL_CORE: float = 0.45  # 黄色い芯の半径（外側に対する割合）
const FIREBALL_CORE_SHRINK: float = 0.5  # 芯が消えるまでに縮む割合
const FIREBALL_WHITE: float = 0.6  # 白い芯の半径（黄色い芯に対する割合）
const SHOCKWAVE_LIFE: float = 0.3
const SHOCKWAVE_W: float = 6.0
const SHOCKWAVE_MIN_W: float = 1.0  # 消える直前の線の太さ
const SHOCKWAVE_EASE: float = 0.4  # 広がり方（ease の曲線）
const SHOCKWAVE_ARC_POINTS: int = 48
const FLASH_LIFE: float = 0.4
const FLASH_ENERGY: float = 1.6
const FLASH_SCALE: float = 7.0  # にじみの絵（GLOW_TEXTURE_SIZE）を何倍にして照らすか
# スピード線・車輪の火花（トロッコの原点はレール上）
const SPEED_LINES: Array = [[Vector2(-58, -40), 120.0], [Vector2(-52, -27), 160.0], [Vector2(-62, -14), 100.0]]  # [前の端, 長さ（最大）]
const SPEED_LINE_W: float = 3.0
const SPEED_LINE_ALPHA: float = 0.45
const SPARK_SPEED: float = 850.0  # これ以上の速さで車輪から火花
const SPARK_AMOUNT: int = 14
const SPARK_LIFETIME: float = 0.35
const SPARK_DIRECTION: Vector2 = Vector2(-1.0, -0.4)  # 後ろの少し上へ散る
const SPARK_VELOCITY: Vector2 = Vector2(140, 320)
const SPARK_SIZE: Vector2 = Vector2(2, 4)
const SPARK_GRAVITY: Vector2 = Vector2(0, 900)
# 着地・失敗の揺れ（FR-33 と同じ揺れ。設定の揺れ OFF なら揺らさない）
const LANDING_SHAKE: float = 6.0
const FAIL_SHAKE: float = 16.0
# ゴール: 切れるテープと看板
const GOAL_TAPE_X: float = TROLLEY_TOP_W * 0.5  # 柱から見たテープの位置（ゴールで止まったトロッコの前の端）
const GOAL_TAPE_H: float = 110.0
const GOAL_TAPE_W: float = 4.0
const GOAL_TAPE_DROOP: Vector2 = Vector2(14, 34)  # 切れた後、上の端は左下へ垂れ、下の端は右へ落ちる（付け根からのずれ）
const GOAL_SIGN: Rect2 = Rect2(-74, -196, 148, 36)  # 柱の上の「試験終了」の看板（柱の根元から）
const GOAL_SIGN_FONT_SIZE: int = 20
const GOAL_SIGN_BORDER: float = 3.0
const GOAL_MESSAGE_POP: float = 1.6  # 「GOAL」を判子のように押す（拡大率→1.0）
const GOAL_MESSAGE_POP_TIME: float = 0.15

# --- 試験記録と検定印（依頼者の判断を待たずに決めた仮の値。設計書 docs/superpowers/specs/2026-09-26-records-design.md） ---
const ACH_BASIC_LAST: int = 5  # 基礎課程修了: 第1〜この試験（ステージ選択の「基礎課程」のページ）
const ACH_COMBO: int = 20  # 倍率上限: コンボ倍率が COMBO_MULT_MAX に届く最小のコンボ（FR-28 の式）
const ACH_CHAIN: int = 2  # 連鎖反応: 1回の走行で、爆発に巻き込まれて爆発したドラム缶の数
const ACH_GIRIGIRI: int = 5  # 紙一重: ギリギリ突破の累計（1回の走行では、どのステージのどの経路でも最多1回）
const ACH_TOP_SPEED_SLACK: float = 10.0  # 最高速度: 速度は SPEED_MAX に漸近して届かないので、表示で1km/h 手前から取る
const ACH_BIG_SCORE: int = 50000  # 大台: 1回の走行の得点（合格したとき）
const ACH_DUMMY: int = 100  # 人形百体: ダミー人形の累計
const ACH_DRUM: int = 50  # 花火師: ドラム缶の累計
const ACH_WALL: int = 30  # 解体業者: レンガ壁の累計
const ACH_SMASH: int = 1000  # 千個破壊: 標的の累計
const DISPLAY_METERS_PER_PX: float = 1.0 / PX_PER_METER  # 走った距離の表示。速度の表示と同じ縮尺（1px/s = 0.1km/h）
const METERS_PER_KM: float = 1000.0

# --- 試験記録の画面（scenes/records.gd、タイトルのボタン） ---
# （この節の値はこの下に足す）
# 依頼者の判断を待たずに決めた仮の値（設計書 3.1）。地・横罫・ヘッダー・ストライプ・カードの枠・見出しの文字はステージ選択
# （SELECT_*）と同じ値を使う。並びの位置と大きさは records.tscn と title.tscn
const RECORDS_COUNT_LABEL_FONT_SIZE: int = 18  # ヘッダー右端の「検定印 N / 30」
const RECORDS_COUNT_FONT_SIZE: int = 24
const RECORDS_LABEL_FONT_SIZE: int = 17  # 累計の表のラベル列
const RECORDS_VALUE_FONT_SIZE: int = 20  # 累計の表の値の列
const RECORDS_TARGET_FONT_SIZE: int = 17  # 壊した標的の種類ごとの数
const RECORDS_RULE_W: float = 1.0  # 累計の表の行の間の破線
const RECORDS_RULE_DASH: float = 4.0
# 壊した標的の絵（40×40 の枠、records.tscn の Icon）: [原点, 拡大率]。標的の原点は下辺中央。
# wall はステージ選択の壁のアイコン（64×64 の枠、StageSelect.draw_wall_icon）を枠の左上から縮めて描く
const RECORDS_TARGET_ICON: Dictionary = {
	"crate": [Vector2(20, 38), 0.75], "barrel": [Vector2(20, 38), 0.64], "dummy": [Vector2(20, 38), 0.45],
	"drum": [Vector2(20, 38), 0.6], "wall": [Vector2(0, 0), 0.625]}
# 検定印（格子の1マスの中央）。取った印は朱の丸判子に名前、まだの印は破線の丸に「？」
const RECORDS_STAMP_R: float = 40.0  # 外径の半径（30個を 8×4 に並べる大きさ。やりこみ D で 42 → 40）
const RECORDS_STAMP_W: float = 3.0
const RECORDS_STAMP_INNER_GAP: float = 3.0  # 内側の細い輪の、外の輪からの間
const RECORDS_STAMP_INNER_W: float = 1.0
const RECORDS_STAMP_ALPHA: float = 0.92  # 朱肉のかすれ（リザルトの判子と同じ）
const RECORDS_STAMP_FONT_SIZE: int = 13  # 16.2 の本文の下限。判子が小さくなったので 14 → 13（「基礎課程」が内側の輪に収まる）
# TODO(spec): 判子の名前の行の分け方は仕様に無い。3字までは1行、4字以上は最後の2字を2行目にする
#             （「基礎課程／修了」「連鎖／反応」「激突の／記録」。今の16個の名前で切れ目が読みやすくなる決め方）
const RECORDS_STAMP_TAIL: int = 2
# TODO(spec): 判子の傾きは仕様に無い（設計書は「少し傾ける」）。印ごとに決まった値（Achievements.LIST の順）
const RECORDS_STAMP_DEG: Array = [-8.0, 6.0, -4.0, 9.0, -11.0, 5.0, -6.0, 10.0, -3.0, 7.0, -9.0, 4.0, -7.0, 11.0, -5.0, 8.0,
		6.0, -10.0, 3.0, -7.0, 9.0, -4.0, 11.0, -6.0, -5.0, 8.0, -9.0, 4.0, -3.0, 10.0]
const RECORDS_LOCKED_W: float = 2.0  # まだの印の破線の丸
const RECORDS_LOCKED_DASHES: int = 18  # 1周の破線の数
const RECORDS_LOCKED_DASH_ON: float = 0.55  # 破線1つの、描く部分の割合
const RECORDS_LOCKED_FONT_SIZE: int = 30  # 「？」
# 説明欄（墨地）と修了証書のボタンの横の文
const RECORDS_DETAIL_NUM_FONT_SIZE: int = 16
const RECORDS_DETAIL_NAME_FONT_SIZE: int = 26
const RECORDS_DETAIL_TEXT_FONT_SIZE: int = 17
const RECORDS_CERT_HINT_FONT_SIZE: int = 15

# --- 修了証書（scenes/certificate.gd）とリザルトの検定印（scenes/result.gd） ---
# （この節の値はこの下に足す）
# 依頼者の判断を待たずに決めた仮の値（設計書 3.2, 3.3）。紙と文字の並びの位置は certificate.tscn・result.tscn
# 修了証書。判子を押す間合いと揺れはリザルトの判子（RESULT_STAMP_*, RESULT_SHAKE_*）と同じ
const CERT_FRAME_INSET: float = 20.0  # 紙の端から墨の二重枠まで
const CERT_FRAME_OUTER: float = 6.0  # 二重枠の外側の線
const CERT_FRAME_GAP: float = 5.0  # 外側と内側の線の間
const CERT_FRAME_INNER: float = 2.0  # 二重枠の内側の線
const CERT_SUB_FONT_SIZE: int = 15  # 「CERTIFICATE OF COMPLETION」
const CERT_HEAD_FONT_SIZE: int = 64  # 「修了証書」
const CERT_HEAD_SPACING: int = 24  # 「修了証書」の字間
const CERT_TEXT_FONT_SIZE: int = 20  # 本文（16.2 の BIZ UDPGothic の上限）
const CERT_TEXT_LINE_HEIGHT: float = 1.8
const CERT_LABEL_FONT_SIZE: int = 16  # ★の合計・最高得点の合計・修了日
const CERT_VALUE_FONT_SIZE: int = 26
const CERT_STAMP_POS: Vector2 = Vector2(690, 360)  # 「修了」の判子の左上（紙の左上から）
# リザルトの「新しい検定印」の札（右列のボタンの上）
const RESULT_STAMPS_MAX: int = 3  # 札に並べる数。残りは「ほか N 個」（ボタンの上の空きに収まる数）
const RESULT_NEW_HEAD_FONT_SIZE: int = 20  # 「新しい検定印」
const RESULT_NEW_NAME_FONT_SIZE: int = 18  # 印の名前
const RESULT_NEW_MORE_FONT_SIZE: int = 16  # 「ほか N 個」
const RESULT_NEW_MARK_SIZE: float = 40.0  # 小さな丸判子の直径
const RESULT_NEW_MARK_LINE: float = 3.0
const RESULT_NEW_MARK_FONT_SIZE: int = 18  # 丸の中の「検」（ステージ選択の「済」と同じ）
const RESULT_NEW_MARK_DEG: float = -12.0
const RESULT_NEW_MARK_GAP: int = 14  # 小さな判子と名前の間
const RESULT_NEW_MARK_INTERVAL: float = 0.25  # 合否の判子の後、1つずつ押す間合い（実時間）
const RESULT_CERT_FONT_SIZE: int = 22  # 「修了証書を受け取る」（右列の幅 300 に収まるよう 17.1 の下限）

# --- 車両と画面の設定（依頼者の判断を待たずに決めた仮の値。設計書 docs/superpowers/specs/2026-09-26-trolleys-and-display-design.md） ---
const QUALITY_LEVELS: Array[String] = ["high", "medium", "low"]  # 画質（高・中・低）。最初が初期値
const FPS_LIMITS: Array[int] = [30, 60, 120, 0]  # FPS 上限の選択肢（0 は上限なし）
const FPS_LIMIT_DEFAULT: int = 0  # 今までと同じ（上限なし・垂直同期 ON）
## 車両の性能（設計書1章の表）。標準型は今までの値（倍率1）。値を変えたら Trolleys.TEXT の長所・短所の文も合わせる
const TROLLEY_STATS: Dictionary = {
	"standard": {"speed_base": SPEED_BASE, "speed_max": SPEED_MAX, "momentum_gain": 1.0, "momentum_decay": 1.0,
			"wall_factor": 1.0, "jump_factor": 1.0, "hit_power": 1.0, "blast_radius": 1.0, "combo_window": 1.0, "star_scale": 1.0},
	"heavy": {"speed_base": 470.0, "speed_max": SPEED_MAX, "momentum_gain": 0.95, "momentum_decay": 1.0,
			"wall_factor": 0.85, "jump_factor": 1.04, "hit_power": 1.35, "blast_radius": 1.0, "combo_window": 1.0, "star_scale": 1.0},
	"light": {"speed_base": 540.0, "speed_max": SPEED_MAX, "momentum_gain": 1.0, "momentum_decay": 1.4,
			"wall_factor": 1.05, "jump_factor": 0.92, "hit_power": 0.75, "blast_radius": 1.0, "combo_window": 1.0, "star_scale": 1.0},
	"blast": {"speed_base": 480.0, "speed_max": 1060.0, "momentum_gain": 1.0, "momentum_decay": 1.0,
			"wall_factor": 1.0, "jump_factor": 1.0, "hit_power": 1.0, "blast_radius": 1.25, "combo_window": 1.1, "star_scale": 1.0},
	"prototype": {"speed_base": SPEED_BASE, "speed_max": 1200.0, "momentum_gain": 1.1, "momentum_decay": 1.4,
			"wall_factor": 1.08, "jump_factor": 1.08, "hit_power": 1.0, "blast_radius": 1.0, "combo_window": 1.0, "star_scale": 1.0},
}
## 車両の解放の条件: {"stage": N}（どれかの車両で第N試験に合格）か {"stamp": 検定印の id}。無い車両は最初から
const TROLLEY_UNLOCK: Dictionary = {
	"heavy": {"stage": 3},  # 壁が出る試験
	"light": {"stage": 5},  # ジャンプが出る試験
	"blast": {"stamp": "chain"},
	"prototype": {"stamp": "all_clear"},
}

# --- 画面の設定の画面（scenes/settings.gd のタブ）・画質の適用・FPS 表示 ---
# （この節の値はこの下に足す）
# 依頼者の判断を待たずに決めた仮の値（設計書4章）。設定画面の並びの位置と大きさは settings.tscn
# 画質（scripts/quality.gd）。高は今のまま（倍率 1・上限 MAX_EFFECTS）
# TODO(spec): 中と低の演出の減らし方は設計書に割合が無い。どちらも粒の数を半分（1つ以上は残す）、同時の演出を半分にした
#             （低は「中に加えて」照明・暗さ・重い描き方を変えるので、粒の数は中と同じ）
const QUALITY_FX_SCALE: Dictionary = {"high": 1.0, "medium": 0.5, "low": 0.5}  # 破片・煙・火花・紙吹雪・パーティクル・スピード線の数
const QUALITY_MAX_EFFECTS: Dictionary = {"high": MAX_EFFECTS, "medium": 30, "low": 30}  # 同時に置く演出の数の上限
# TODO(spec): 低の「時間帯の暗さを弱める」の量は設計書に無い。全体に掛ける色を白へこの割合だけ寄せる（深夜でも標識・標的・線路が見える）
const QUALITY_LOW_AMBIENT_LIFT: float = 0.6
# 設定の「画面」タブ
const SETTINGS_QUALITY_NOTE_FONT_SIZE: int = 14  # 画質の下の「次に始める試験から…」（16.2 の本文の下限 13px 以上）
# FPS 表示（autoload/fps_counter.gd）
const FPS_LAYER: int = 100  # ゲーム画面の HUD（1）・ポーズとリザルト（2）より手前
const FPS_FONT_SIZE: int = 13  # 16.2 の Courier Prime の下限
const FPS_PAD: Vector2 = Vector2(6, 2)  # 墨の地の左右・上下の余白

# --- 車庫（車両を選ぶ画面）・車両の絵・ステージ選択とリザルトの車両の表示 ---
# （この節の値はこの下に足す）
const TROLLEY_THIN_LINE: float = 0.75  # 導火線・試験用マーカーの線の太さ（TROLLEY_DETAIL_W に掛ける）
const BLAST_SIGN_DOT_R: float = 0.6  # 発破型の「！」の点の半径（TROLLEY_DETAIL_W に掛ける）
# 依頼者の判断を待たずに決めた仮の値（trolleys-and-display-design.md 3章）。見本の絵は無い
# 車両の絵（Trolley.draw_body）。原点はレール上。どの車両も 16.5 の外接矩形（TROLLEY_TOP_W × TROLLEY_H）の中に描き、
# 車輪（TROLLEY_WHEEL_X・TROLLEY_WHEEL_R）と前照灯（HEADLIGHT_AT）の位置は標準型と同じ。色は Palette の車両の節
const TROLLEY_ART_SLACK: float = 4.0  # 絵が外接矩形からはみ出してよい幅（発破型の導火線の先。tests/checks_garage.gd が見る）
const TROLLEY_DETAIL_W: float = 2.0  # 部品の輪郭・継ぎ目の線（車体の輪郭 TROLLEY_OUTLINE より細い）
# 重量型: 上の角を落とした厚い鋼板の箱（ほぼ長方形）、上縁の厚い板、縦の継ぎ目、2列のリベット
const HEAVY_BODY: Array = [Vector2(-44, -48), Vector2(44, -48), Vector2(48, -44), Vector2(46, -12), Vector2(-46, -12),
	Vector2(-48, -44)]
const HEAVY_LIP_H: float = 9.0  # 上縁の板の高さ
const HEAVY_SEAM_X: Array = [-17.0, 17.0]  # 縦の継ぎ目
const HEAVY_RIVET_ROWS: Array = [-43.5, -18.0]  # リベットの列の高さ（上縁の板の中と、下の縁）
const HEAVY_RIVET_X: Array = [-39.0, -27.0, -7.0, 7.0, 27.0, 39.0]  # 継ぎ目を挟んで3枚の板に2個ずつ
const HEAVY_RIVET_R: float = 2.5
# 軽量型: 低く細いアルミの桶（上辺が車体の高さの 3/4）、上の手すり、青い細帯、肉抜きの穴
const LIGHT_BODY: Array = [Vector2(-46, -34), Vector2(46, -34), Vector2(40, -12), Vector2(-40, -12)]
const LIGHT_RAIL: Array = [Vector2(-42, -34), Vector2(-42, -46), Vector2(42, -46), Vector2(42, -34)]  # 手すり（両端の支柱と上の棒）
const LIGHT_POSTS: Array = [-14.0, 14.0]  # 中の支柱
const LIGHT_RAIL_W: float = 3.0
const LIGHT_STRIPE: Rect2 = Rect2(-48, -30, 96, 4)
const LIGHT_HOLES: Array = [Vector2(-22, -20), Vector2(0, -20), Vector2(22, -20)]
const LIGHT_HOLE_R: float = 4.5
# 発破型: 赤い桶（上辺を下げた台形）、上縁の警告のストライプ、ひし形の危険表示、桶の後ろから出たダイナマイト3本と導火線
const BLAST_BODY: Array = [Vector2(-48, -38), Vector2(48, -38), Vector2(40, -12), Vector2(-40, -12)]
const BLAST_BAND_H: float = 7.0
const BLAST_SIGN: Vector2 = Vector2(6, -22)  # 危険表示のひし形の中心
const BLAST_SIGN_R: float = 8.0  # 中心から角まで
const BLAST_SIGN_MARK: Vector2 = Vector2(-4.5, 1.0)  # 「！」の縦棒の上端と下端（中心からの y）
const BLAST_SIGN_DOT_Y: float = 3.8  # 「！」の点（中心からの y）
const BLAST_STICKS: Array = [Rect2(-33, -46, 7, 12), Rect2(-25, -48, 7, 14), Rect2(-17, -46, 7, 12)]
const BLAST_TIE: Rect2 = Rect2(-34, -42, 25, 3)  # ダイナマイトを束ねる帯
const BLAST_FUSE: Array = [Vector2(-21.5, -48), Vector2(-20, -49.5), Vector2(-17, -50)]  # 導火線（最後の点に火花）
const BLAST_SPARK_R: float = 1.8
# 試作型: 白い流線形（後ろは丸く、前は低く尖る）、前の上の覗き窓、警告黄の帯、試験用マーカー（ダミー人形と同じ半径）
const PROTO_BODY: Array = [Vector2(-38, -46), Vector2(6, -46), Vector2(24, -42), Vector2(40, -33), Vector2(48, -22),
	Vector2(45, -12), Vector2(-45, -12), Vector2(-48, -22), Vector2(-47, -36), Vector2(-43, -43)]
const PROTO_VISOR: Array = [Vector2(6, -43), Vector2(22, -39.5), Vector2(34, -32), Vector2(10, -32)]
const PROTO_VISOR_GLINT: Array = [Vector2(12, -40), Vector2(21, -38)]
const PROTO_STRIPE: Rect2 = Rect2(-48, -25, 96, 5)
const PROTO_MARKER: Vector2 = Vector2(-24, -33)
# 車庫（scenes/garage.gd）。地・横罫・ヘッダー・カードの枠・見出し・錠前はステージ選択（SELECT_*）と同じ値。
# 並びの位置と大きさは garage.tscn
const GARAGE_PICTURE_SCALE: float = 1.6  # カードの車両の絵
const GARAGE_PICTURE_RAIL_Y: float = 84.0  # 絵の枠の上端からレールの中心まで
const GARAGE_NAME_FONT_SIZE: int = 22
const GARAGE_TAG_FONT_SIZE: int = 18  # 「使用中」の札（リザルトの「最高記録更新」の札と同じ作り）
const GARAGE_TRAIT_FONT_SIZE: int = 14  # 長所・短所
const GARAGE_LOCK_HINT_FONT_SIZE: int = 14  # 解放の条件
const GARAGE_LEGEND_FONT_SIZE: int = 15  # ヘッダーの右端の凡例
const GARAGE_BAR_FONT_SIZE: int = 13  # 棒グラフの見出し
const GARAGE_BAR_ROW_H: float = 20.0
const GARAGE_BAR_H: float = 8.0
const GARAGE_BAR_LABEL_GAP: float = 8.0  # 見出しと棒の間
const GARAGE_BAR_GAIN: float = 1.25  # 標準型との比 r の棒の長さ（棒の幅に対する割合）: 0.5 + (r - 1) × この値（0〜1 に収める）
const GARAGE_BAR_TICK_W: float = 2.0  # 標準型の目盛り（棒の真ん中）
const GARAGE_BAR_BORDER: float = 1.0
# ステージ選択の詳細パネルの車両（右の列の上）
const SELECT_TROLLEY_SCALE: float = 0.5
const SELECT_TROLLEY_NAME_FONT_SIZE: int = 20
# リザルトの「新しい車両」（新しい検定印の札の上の段）
const RESULT_NEW_TROLLEY_SCALE: float = 0.4  # 小さな判子と同じ枠（RESULT_NEW_MARK_SIZE）に収める
const RESULT_NEW_NOTE_FONT_SIZE: int = 14  # 「「車両を選ぶ」から使えます」
const RESULT_BUTTONS_SLIP_GAP: float = 12.0  # 札が伸びてボタンを下げるときの、札の影・フォーカスの枠の下の空き

# --- やりこみ要素（依頼者の判断を待たずに決めた仮の値。設計書 docs/superpowers/specs/2026-09-28-replay-value-design.md） ---
# 裏試験（設計書1章・4章）。番号は本試験の後ろ（11〜15）
const EX_FIRST: int = STAGE_COUNT + 1
const EX_COUNT: int = 5
const EX_UNLOCK_STARS: Array[int] = [10, 14, 18, 22, 26]  # 裏試験 i の解放に要る本試験の★の合計
const CHALLENGE_COUNT: int = 3  # 試験ごとの課題の数
# 熟練度（設計書 5.1）
const XP_SCORE_DIV: int = 100  # 得点 ÷ この値が経験値
const XP_CLEAR_BONUS: int = 100  # 合格した走行に足す経験値
const LEVEL_MAX: int = 25
const XP_LEVEL_BASE: int = 300  # 段 L → L+1 に要る経験値 = BASE + STEP × (L - 1)
const XP_LEVEL_STEP: int = 150
# 強化（設計書 5.2）。[id, 名前, 1段ごとの倍率の変化]。倍率は 1 + 段 × 変化
const UPGRADES: Array = [
	["hit_power", "吹っ飛ばす力", 0.05],
	["blast_radius", "爆発の範囲", 0.05],
	["combo_window", "コンボの受付", 0.05],
	["girigiri_margin", "ギリギリの幅", 0.2],
	["wall_factor", "壁に強く", -0.03],
	["jump_factor", "ジャンプに強く", -0.03],
]
const UPGRADE_COSTS: Array[int] = [1, 1, 2]  # 段 0→1、1→2、2→3 の値段（ポイント）
# 塗装（設計書 5.3）。塗装 i が使えるようになる段
const PAINT_UNLOCK_LEVELS: Array[int] = [1, 5, 10, 15, 25]
# ゴースト（設計書6章）
const GHOST_SAMPLE_DT: float = 0.05  # 記録の間隔（ゲーム内時刻の秒）
# 検定印（設計書8章）
const ACH_LEVEL: int = 10  # 熟練工
const ACH_CHALLENGES: int = 10  # 課題提出
const ACH_ENDLESS_DISTANCE: float = 5.0 * METERS_PER_KM * PX_PER_METER  # 長距離運転: 無限軌道の1回の距離（px。5km）

# --- やりこみ A: 課題と金★ ---
# （この節の値はこの下に足す）
# リザルトの金★（★3 の右に、★どうしより広く空けて置く）・課題の行・熟練度の行
const RESULT_GOLD_GAP: float = 22.0
const RESULT_CHALLENGE_FONT_SIZE: int = 15  # 一番長い文（巻き込まれたドラム缶を…）が値の列に入る大きさ
const RESULT_CHALLENGE_LINE_GAP: int = 2  # 課題の行どうし
const RESULT_CHALLENGE_MARK: float = 14.0  # 行の頭の丸印の直径
const RESULT_CHALLENGE_MARK_LINE: float = 2.0
const RESULT_CHALLENGE_MARK_GAP: float = 6.0  # 丸印と文の間
const RESULT_CHALLENGE_NEW_PAD: Vector2 = Vector2(5, 1)  # 今回達成した行の警告黄の地の内側の余白
## 丸印の中のレ点（直径を 1 とした座標）
const CHALLENGE_CHECK: Array = [Vector2(0.27, 0.52), Vector2(0.45, 0.7), Vector2(0.75, 0.32)]
const RESULT_LEVEL_NOTE_FONT_SIZE: int = 16  # 「強化のポイント +1」
const RESULT_ROW_GAP_TIGHT: int = 9  # 課題の行があるときの報告書の行の間（ふだんは 12）
# ステージ選択のカードの金★と課題の数、詳細パネルの課題
const SELECT_TASKS_FONT_SIZE: int = 15  # 「課題 2/3」
const SELECT_CHALLENGE_FONT_SIZE: int = 16
const SELECT_CHALLENGE_MARK: float = 15.0
const SELECT_CHALLENGE_LINE_GAP: int = 1

# --- やりこみ B: 車庫（熟練度・強化・塗装） ---
# （この節の値はこの下に足す）
# 車庫のカードの熟練度の行（段と次の段までの棒）
const GARAGE_MASTERY_FONT_SIZE: int = 14
const GARAGE_XP_BAR_H: float = 8.0
# 整備パネル（強化と塗装）。見出しなどの文字の大きさは設定画面（SETTINGS_*）に揃える
const GARAGE_WS_ROW_H: float = 40.0  # 強化の行のボタンの高さ
const GARAGE_WS_EFFECT_FONT_SIZE: int = 15  # 効き目の文・値段
const GARAGE_WS_SMALL_FONT_SIZE: int = 14  # 塗装の名前・「◯段で解放」・操作説明
const GARAGE_WS_SWATCH: Vector2 = Vector2(132, 96)  # 塗装のボタン
const GARAGE_WS_SWATCH_NAME_H: float = 24.0  # 塗装のボタンの下の名前の欄
const GARAGE_WS_SWATCH_SCALE: float = 0.9  # 塗装のボタンの車両の絵
const GARAGE_WS_SWATCH_RAIL_Y: float = 60.0  # 塗装のボタンの上端からレールの中心まで
const GARAGE_WS_LOCK_SIZE: float = 32.0  # 使えない塗装の錠前

# --- やりこみ C: 裏試験 ---
# （この節の値はこの下に足す）
# 金★の閾値（設計書 3.2）: 強化なしの標準型の最高得点 × この割合を、この単位で切り捨てる（tests/checks_stages.gd -- ex が確かめる）
const EX_GOLD_RATIO: float = 0.97
const EX_GOLD_STEP: int = 500
# ステージ選択の「裏課程」のページ（scenes/stage_select.gd）。タブの並びの幅は stage_select.tscn（3つ入るように広げた）
const EX_STAMP_DEG: Array = [9.0, -11.0, 6.0, -5.0, 11.0]  # 裏試験1〜5 の「済」の判子の傾き（本試験は SELECT_STAMP_DEG）
const EX_TAB_LOCK: float = 0.55  # 解放前のタブの錠前の一辺（タブの高さに対する割合）
const EX_TAB_LOCK_GAP: float = 4.0  # 錠前と「★10で解放」の間

# --- やりこみ D: ゴースト・試験記録の画面 ---
# （この節の値はこの下に足す）
const GHOST_MAX_POINTS: int = 4000  # ゴーストの点の上限（届いたら1つおきに間引いて間隔を倍に。0.05秒なら 200秒分）
const GHOST_FADE_TIME: float = 0.6  # ゴーストが最後の点を過ぎてから消えるまで（秒）

# --- やりこみ E: 無限軌道 ---
# （この節の値はこの下に足す）
# 区間（data/endless/chunks.json）の型の座標は、入口のレールを (0, 0) にした相対の値。組むときに x を前の区間の出口に、
# y を ENDLESS_RAIL_Y にずらす（どの型も入口と出口のレールの高さは 0 でそろえる）
const ENDLESS_RAIL_Y: float = 600.0
const ENDLESS_GROUND_Y: float = 900.0
const ENDLESS_LEVEL_LENGTH: float = 12000.0  # 区間の始まりの x（px）がこの値ごとに難しさの段が1つ上がる（約333m）
const ENDLESS_LEVEL_MAX: int = 6
const ENDLESS_REQUIRED_STEP: float = 50.0  # 段が1つ上がるごとに、壁・ジャンプの必要速度に足す値（px/s）。届く値で頭打ち
const ENDLESS_PARTS_AHEAD: int = 2  # トロッコのいる区間の先に組んでおく区間の数
const ENDLESS_SIM_DT: float = 1.0 / 60.0  # 必要速度を決めるための速さの見積もりの刻み（秒。物理フレームと同じ）
# 無限軌道のリザルト（scenes/endless_result.gd）。試験報告書（リザルト）と同じ紙・文字で小さく。文字の大きさは RESULT_*
const ENDLESS_RESULT_REPORT: Rect2 = Rect2(180, 72, 620, 560)  # 報告書の紙
const ENDLESS_RESULT_PAD: Vector2 = Vector2(48, 40)  # 紙の内側の余白
const ENDLESS_RESULT_ROW_GAP: int = 14  # 行の間
const ENDLESS_RESULT_BUTTONS: Rect2 = Rect2(880, 420, 300, 0)  # 右列のボタン（高さは中身で決まる）
const ENDLESS_RESULT_STAMPS_MAX: int = 3  # 名前を並べる新しい検定印の数（残りは「ほか N 個」）
# タイトルの「無限軌道」（scenes/title.gd）
const TITLE_ENDLESS_NOTE_FONT_SIZE: int = 16  # 解放の条件・最高記録（16.2 の下限）
