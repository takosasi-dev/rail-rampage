"""仮の効果音 12 個を合成して assets/sfx/<key>.wav に書き出す（外部素材なし、Python 標準ライブラリだけ）。

モノラル・16bit・44100Hz。乱数の種はキーごとに固定なので、何度実行しても同じバイト列になる。
本番の効果音が決まったら、同じキー名の .wav / .ogg で置き換える（assets/sfx/CREDITS.txt）。
実行: python tools/make_sfx.py
"""
import math
import random
import sys
import wave
from array import array
from pathlib import Path

SR = 44100
PEAK = 10 ** (-3 / 20)  # 正規化後のピーク（-3 dBFS）
FADE_IN = 0.002  # 秒。頭のフェード（プチッを防ぐ）
FADE_OUT_RATIO = 0.08  # 尻のフェードは長さの 8%（最低 5ms）
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "sfx"
TAU = 2 * math.pi

# 加算合成の表: (周波数の倍率, 音量, 減衰の時定数の比)
BELL = [(1.0, 1.0, 1.0), (2.0, 0.45, 0.6), (3.0, 0.2, 0.4), (4.16, 0.1, 0.3)]  # ベル・チャイム
BAR = [(1.0, 1.0, 1.0), (2.76, 0.6, 0.6), (5.40, 0.35, 0.4), (8.93, 0.2, 0.25)]  # 金属棒（チャリン）
PLATE = [(1.0, 1.0, 1.0), (1.013, 0.5, 1.0), (2.32, 0.7, 0.7), (3.87, 0.5, 0.5),
         (5.13, 0.35, 0.35), (7.41, 0.2, 0.2)]  # 鉄板（ガーン）。1.013 は唸りを出すためのずらし


# ---- 基本 ------------------------------------------------------------------

def ns(sec: float) -> int:
    """秒 → サンプル数"""
    return int(round(sec * SR))


def at(v, t: float) -> float:
    """数値か「t（秒）→ 値」の関数を、時刻 t の値にする（スイープ用）"""
    return v(t) if callable(v) else v


def glide(f0: float, f1: float, tau: float):
    """f0 から f1 へ時定数 tau で指数的に近づくピッチ（t → Hz）"""
    return lambda t: f1 + (f0 - f1) * math.exp(-t / tau)


# ---- 音源 ------------------------------------------------------------------

def noise(rng: random.Random, sec: float) -> list[float]:
    """ホワイトノイズ"""
    return [rng.uniform(-1.0, 1.0) for _ in range(ns(sec))]


def sine(sec: float, freq) -> list[float]:
    """正弦波。freq は数値か t → Hz の関数（ピッチスイープ）"""
    out, ph = [], 0.0
    for i in range(ns(sec)):
        out.append(math.sin(ph))
        ph += TAU * at(freq, i / SR) / SR
    return out


def partials(sec: float, base: float, table) -> list[float]:
    """加算合成。table は (倍率, 音量, 減衰の時定数 秒) の並び。木・ベル・金属の鳴りに使う"""
    out = [0.0] * ns(sec)
    for ratio, amp, tau in table:
        w = TAU * base * ratio / SR
        for i in range(len(out)):
            out[i] += amp * math.exp(-i / SR / tau) * math.sin(w * i)
    return out


def ring(sec: float, base: float, tau: float, table=BELL) -> list[float]:
    """表（BELL / BAR / PLATE）の減衰の比に tau を掛けて鳴らす"""
    return partials(sec, base, [(r, a, k * tau) for r, a, k in table])


# ---- フィルタ・音量の形 ----------------------------------------------------

def lowpass(x: list[float], cutoff) -> list[float]:
    """1次ローパス。cutoff は数値か t → Hz の関数"""
    out, y = [], 0.0
    for i, s in enumerate(x):
        y += (1 - math.exp(-TAU * at(cutoff, i / SR) / SR)) * (s - y)
        out.append(y)
    return out


def highpass(x: list[float], cutoff: float) -> list[float]:
    """1次ハイパス（元の音 − ローパス）"""
    return [s - lo for s, lo in zip(x, lowpass(x, cutoff))]


def bandpass(x: list[float], freq, q: float) -> list[float]:
    """共振バンドパス（Chamberlin の状態変数フィルタ）。freq は数値か t → Hz の関数。
    q が大きいほど鋭く鳴る。中心周波数での利得がほぼ 1 になるよう 1/q を掛けている。
    ponytail: この形は SR/6（約 7.3kHz）より上で不安定になるので中心周波数をそこで止める。高い音が要るなら 2 倍オーバーサンプリングにする"""
    d = 1.0 / q
    low = band = 0.0
    out = []
    for i, s in enumerate(x):
        f = 2 * math.sin(math.pi * min(at(freq, i / SR), SR / 6) / SR)
        low += f * band
        band += f * (s - low - d * band)
        out.append(band * d)
    return out


def shape(x: list[float], attack: float, tau: float, hold: float = 0.0) -> list[float]:
    """音量の形: attack 秒で直線的に立ち上がり、hold 秒保ち、そのあと時定数 tau 秒で指数減衰"""
    out = []
    for i, s in enumerate(x):
        t = i / SR
        if t < attack:
            g = t / attack
        elif t < attack + hold:
            g = 1.0
        else:
            g = math.exp(-(t - attack - hold) / tau)
        out.append(s * g)
    return out


# ---- 組み立て用の部品 ------------------------------------------------------

def place(dst: list[float], src: list[float], start: float = 0.0, gain: float = 1.0) -> None:
    """src のピークを gain にそろえて、dst の start 秒の位置に足す（dst が短ければ伸ばす）"""
    peak = max((abs(s) for s in src), default=0.0)
    if peak == 0.0:
        return
    k, o = gain / peak, ns(start)
    if len(dst) < o + len(src):
        dst.extend([0.0] * (o + len(src) - len(dst)))
    for i, s in enumerate(src):
        dst[o + i] += s * k


def burst(rng: random.Random, sec: float, freq, q: float, attack: float, tau: float) -> list[float]:
    """ノイズを共振バンドパスに通して減衰させた短い音（打撃・破片・こすれの素）"""
    return shape(bandpass(noise(rng, sec), freq, q), attack, tau)


def click(rng: random.Random, sec: float, tau: float, cutoff: float = 2000) -> list[float]:
    """高域だけのノイズの一瞬（割れる瞬間・カチッの頭）"""
    return shape(highpass(noise(rng, sec), cutoff), 0.0002, tau)


def thud(sec: float, f0: float, f1: float, tau: float) -> list[float]:
    """ピッチが下がりながら消える低い正弦波（ドスッ）"""
    return shape(sine(sec, glide(f0, f1, tau / 2)), 0.001, tau)


def blip(sec: float, freq: float, tau: float) -> list[float]:
    """3倍音を少し混ぜた電子音（ピッ）"""
    return shape([a + 0.2 * b for a, b in zip(sine(sec, freq), sine(sec, 3 * freq))], 0.002, tau)


def scatter(rng: random.Random, dst: list[float], count: int, start: float, spread: float, gain: float,
            freqs: tuple[float, float], taus: tuple[float, float], q: float = 6.0, decay: float = 0.25,
            curve: float = 1.0) -> None:
    """破片のパラパラ: 短い burst を start から spread 秒の範囲にばらまく。
    後ろほど小さく（時定数 decay）、curve > 1 で前の方に寄る"""
    for _ in range(count):
        t = spread * rng.random() ** curve
        tau = rng.uniform(*taus)
        g = gain * math.exp(-t / decay) * rng.uniform(0.4, 1.0)
        place(dst, burst(rng, tau * 5, rng.uniform(*freqs), q, 0.0003, tau), start + t, g)


# ---- 効果音（1 つ 1 関数。rng はキーごとに種を固定した乱数） -------------

def toggle(rng: random.Random) -> list[float]:
    """ポイント切り替えレバーの「カチャッ」: 金属の小さな鳴り＋少し遅れて低めの当たり。よく鳴るので短く控えめに"""
    out: list[float] = []
    place(out, click(rng, 0.006, 0.0012, 3000), 0.0, 0.6)
    place(out, burst(rng, 0.03, 3200, 12, 0.0003, 0.006), 0.0, 0.5)
    place(out, burst(rng, 0.05, 1300, 5, 0.0005, 0.011), 0.026, 1.0)
    place(out, shape(sine(0.04, 430), 0.0005, 0.01), 0.026, 0.35)
    return out


def hit_small(rng: random.Random) -> list[float]:
    """木箱・樽の「コッ」: 短い割れ＋木の胴鳴り＋軽いドン"""
    out: list[float] = []
    place(out, click(rng, 0.01, 0.002), 0.0, 0.5)
    place(out, partials(0.15, 420, [(1.0, 1.0, 0.035), (2.4, 0.5, 0.02), (4.3, 0.3, 0.012)]), 0.0, 0.8)
    place(out, burst(rng, 0.1, 700, 3, 0.0005, 0.025), 0.0, 0.6)
    place(out, thud(0.12, 240, 120, 0.03), 0.0, 0.6)
    return out


def hit_big(rng: random.Random) -> list[float]:
    """人形・ドラム缶・壁の「ドゴッ」: 低いドスン＋中域のつぶれ＋細かいバキバキ"""
    out: list[float] = []
    place(out, thud(0.3, 150, 45, 0.09), 0.0, 1.0)
    place(out, shape(lowpass(lowpass(noise(rng, 0.25), 400), 400), 0.002, 0.07), 0.0, 0.6)
    place(out, burst(rng, 0.2, 900, 1.5, 0.001, 0.05), 0.0, 0.7)
    scatter(rng, out, 12, 0.0, 0.12, 0.35, (1200, 3500), (0.004, 0.009), q=4, decay=0.08)
    return out


def explosion(rng: random.Random) -> list[float]:
    """ドラム缶の「ドカーン」: 高域から閉じていく爆風ノイズ＋腹に来る一撃＋低い地鳴りの尾"""
    out: list[float] = []
    closing = lambda t: 180 + 4000 * math.exp(-t / 0.08)  # ローパスの閉じ方
    place(out, shape(lowpass(lowpass(noise(rng, 0.9), closing), closing), 0.002, 0.18), 0.0, 1.0)
    place(out, thud(0.9, 75, 35, 0.25), 0.0, 0.9)
    place(out, shape(lowpass(lowpass(noise(rng, 0.9), 90), 90), 0.01, 0.25), 0.0, 0.8)
    scatter(rng, out, 18, 0.02, 0.4, 0.3, (800, 3000), (0.004, 0.012), q=4, decay=0.15, curve=1.5)
    return out


def wall_break(rng: random.Random) -> list[float]:
    """レンガ壁の「バガーン」: 鋭い割れ＋ドスッ、そのあと破片がガラガラ散る"""
    out: list[float] = []
    place(out, click(rng, 0.03, 0.004, 1500), 0.0, 1.0)
    place(out, burst(rng, 0.08, 2500, 3, 0.0003, 0.015), 0.0, 0.7)
    place(out, thud(0.2, 120, 55, 0.06), 0.0, 0.7)
    place(out, burst(rng, 0.6, 600, 1.2, 0.002, 0.12), 0.0, 0.5)
    scatter(rng, out, 60, 0.03, 0.5, 0.55, (700, 4000), (0.004, 0.015), q=7, decay=0.3, curve=1.4)
    return out


def derail(rng: random.Random) -> list[float]:
    """脱線の「ギギギーッ、ガラガラ」: 車輪のきしみとこすれ → レールを外れてガコン → 金具が跳ねる"""
    out: list[float] = []
    pitch = lambda t: 2500 - 1000 * t + 70 * math.sin(TAU * 9 * t) + 30 * math.sin(TAU * 23 * t)  # 揺れながら下がる
    squeal = [a + 0.3 * b for a, b in zip(sine(0.6, pitch), sine(0.6, lambda t: 2.01 * pitch(t)))]
    place(out, shape(squeal, 0.03, 0.06, hold=0.33), 0.0, 0.55)
    place(out, shape(bandpass(noise(rng, 0.6), lambda t: 3500 - 2500 * t, 2), 0.02, 0.07, hold=0.33), 0.0, 0.6)
    place(out, ring(0.35, 220, 0.12, BAR), 0.38, 0.7)
    place(out, thud(0.25, 130, 60, 0.07), 0.38, 0.6)
    for _ in range(14):
        t = rng.uniform(0.42, 0.72)
        g = 0.45 * math.exp(-(t - 0.42) / 0.2) * rng.uniform(0.5, 1.0)
        place(out, ring(0.12, rng.uniform(600, 1500), rng.uniform(0.02, 0.05), BAR), t, g)
    return out


def crash(rng: random.Random) -> list[float]:
    """トロッコが壁に激突する「ガシャーン」: 重いドスン＋つぶれ＋鉄板の鳴り＋部品の跳ね"""
    out: list[float] = []
    place(out, thud(0.5, 110, 40, 0.12), 0.0, 1.0)
    place(out, click(rng, 0.03, 0.005, 1500), 0.0, 0.6)
    place(out, burst(rng, 0.3, 1100, 1.2, 0.001, 0.07), 0.0, 0.8)
    place(out, ring(0.7, 165, 0.25, PLATE), 0.0, 0.7)
    scatter(rng, out, 10, 0.0, 0.25, 0.35, (900, 3000), (0.005, 0.012), q=4, decay=0.12)
    for _ in range(5):
        t = rng.uniform(0.15, 0.5)
        place(out, ring(0.12, rng.uniform(700, 1400), rng.uniform(0.02, 0.04), BAR), t, 0.2 * rng.uniform(0.5, 1.0))
    return out


def goal(rng: random.Random) -> list[float]:
    """ゴールの「ピンポロリーン」: ド・ミ・ソと上がるベル。最後の音だけ長く、1オクターブ下を重ねて厚く"""
    out: list[float] = []
    for i, (freq, tau) in enumerate([(1046.5, 0.14), (1318.5, 0.14), (1568.0, 0.2)]):
        place(out, ring(0.8 - 0.11 * i, freq, tau), 0.11 * i, 0.8 + 0.1 * i)
    place(out, ring(0.58, 784.0, 0.2), 0.22, 0.3)
    return out


def girigiri(rng: random.Random) -> list[float]:
    """ギリギリ回避の「ヒュンッ、チーン」: 上がっていく風切り＋明るいベル（5度上を重ねてきらっと）"""
    out: list[float] = []
    rising = lambda t: 500 * 8 ** (t / 0.25)  # 0.25 秒で 3 オクターブ上がる
    place(out, shape(bandpass(noise(rng, 0.3), rising, 3), 0.22, 0.025), 0.0, 0.7)
    place(out, ring(0.18, 2093.0, 0.07), 0.22, 1.0)
    place(out, ring(0.18, 3136.0, 0.05), 0.22, 0.35)
    return out


def stamp(rng: random.Random) -> list[float]:
    """ハンコを紙に押す「ポン」: 低く鈍い短い当たり＋ごく小さな紙の音"""
    out: list[float] = []
    place(out, thud(0.15, 170, 75, 0.035), 0.0, 1.0)
    place(out, shape(lowpass(lowpass(noise(rng, 0.1), 500), 500), 0.001, 0.02), 0.0, 0.6)
    place(out, burst(rng, 0.03, 1800, 1.5, 0.0005, 0.005), 0.0, 0.2)
    return out


def ui_move(rng: random.Random) -> list[float]:
    """メニューのフォーカス移動「ポッ」: ごく短く柔らかい"""
    out: list[float] = []
    place(out, shape(sine(0.04, 1400), 0.001, 0.008), 0.0, 1.0)
    place(out, burst(rng, 0.01, 3000, 4, 0.0002, 0.002), 0.0, 0.15)
    return out


def ui_select(rng: random.Random) -> list[float]:
    """メニューの決定「ピコッ」: カチッ＋短く上がる2音"""
    out: list[float] = []
    place(out, click(rng, 0.005, 0.0015), 0.0, 0.25)
    place(out, blip(0.05, 880, 0.02), 0.0, 0.8)
    place(out, blip(0.065, 1320, 0.025), 0.035, 1.0)
    return out


# キー → (長さ 秒, 作る関数)。キーは autoload/audio.gd の KEYS と同じ
SOUNDS = {
    "toggle": (0.08, toggle),
    "hit_small": (0.15, hit_small),
    "hit_big": (0.3, hit_big),
    "explosion": (0.9, explosion),
    "wall_break": (0.6, wall_break),
    "derail": (0.8, derail),
    "crash": (0.7, crash),
    "goal": (0.8, goal),
    "girigiri": (0.4, girigiri),
    "stamp": (0.2, stamp),
    "ui_move": (0.04, ui_move),
    "ui_select": (0.1, ui_select),
}


# ---- 仕上げ・書き出し・確認 ------------------------------------------------

# 短い音はピークをそろえると衝突音より大きく聞こえる（RMS が高い）ので、ここに挙げた音だけ下げる（dB）。
# 切替は何度も鳴るので控えめにする
TRIM_DB = {"toggle": -3.0, "ui_move": -8.0, "ui_select": -6.0}


def finish(x: list[float], sec: float, trim_db: float = 0.0) -> list[float]:
    """長さをそろえ、直流を抜き、頭と尻にフェードをかけ、ピークを -3 dBFS（+ trim_db）にそろえる"""
    x = (x + [0.0] * ns(sec))[: ns(sec)]
    x = highpass(x, 20)
    n_in, n_out = ns(FADE_IN), max(ns(0.005), ns(sec * FADE_OUT_RATIO))
    for i in range(n_in):
        x[i] *= i / n_in
    for i in range(n_out):
        x[-1 - i] *= i / n_out
    peak = max(abs(s) for s in x)
    target = PEAK * 10 ** (trim_db / 20)
    return [s * target / peak for s in x]


def write_wav(path: Path, x: list[float]) -> None:
    pcm = array("h", (int(round(s * 32767)) for s in x))
    if sys.byteorder == "big":
        pcm.byteswap()  # WAV はリトルエンディアン
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def check() -> None:
    """書き出したファイルを読み戻し、形式とピークを確かめて一覧を出す（おかしければ止まる）"""
    total = 0
    for key, (sec, _) in SOUNDS.items():
        path = OUT_DIR / f"{key}.wav"
        with wave.open(str(path), "rb") as w:
            ch, width, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            pcm = array("h", w.readframes(frames))
        if sys.byteorder == "big":
            pcm.byteswap()
        peak_db = 20 * math.log10(max(abs(s) for s in pcm) / 32768)
        size = path.stat().st_size
        total += size
        assert (ch, width, rate, frames) == (1, 2, SR, ns(sec)), (key, ch, width, rate, frames)
        want_db = -3.0 + TRIM_DB.get(key, 0.0)
        assert abs(peak_db - want_db) < 0.5, (key, peak_db)
        print(f"{key:<10}  {frames / rate:5.3f}s  {rate}Hz  {ch}ch  peak {peak_db:6.2f} dBFS  {size / 1024:6.1f} KB")
    print(f"{len(SOUNDS)} 個、合計 {total / 1024:.1f} KB")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for key, (sec, make) in SOUNDS.items():
        rng = random.Random(f"rail-rampage/{key}")  # キーごとに種を固定（1 つ直しても他の音は変わらない）
        write_wav(OUT_DIR / f"{key}.wav", finish(make(rng), sec, TRIM_DB.get(key, 0.0)))
    check()


if __name__ == "__main__":
    main()
