"""Synthesizes the game's own sound effects (whoosh, squish, launch, fuse, freeze, miss, thump) as 16-bit WAV.
python tools/make_sfx.py  ->  assets/audio/*.wav   (CC0, made for this game)"""
import numpy as np, wave, os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(3)


def save(name, x, gain=0.9):
    x = x / max(1e-6, np.abs(x).max()) * gain
    d = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(d.tobytes())


def env(n, a, r, shape=2.0):
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(a, 1e-4)) * np.clip(1 - (t - a) / r, 0, 1) ** shape
    return e


def bandnoise(n, f0, f1, q=0.15):
    """noise through a time-varying band-pass (state variable filter), centre sweeping f0 -> f1."""
    x = rng.standard_normal(n)
    out = np.zeros(n)
    low = band = 0.0
    fc = np.geomspace(f0, f1, n)
    for i in range(n):
        f = 2 * np.sin(np.pi * fc[i] / SR)
        low += f * band
        high = x[i] - low - q * band
        band += f * high
        out[i] = band
    return out


def whoosh(seed, f0, f1, dur):
    global rng
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    x = bandnoise(n, f0, f1, 0.35)
    t = np.linspace(0, 1, n)
    e = np.sin(np.pi * t ** 0.6) ** 1.6
    return x * e


def squish(seed, dur=0.28):
    global rng
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    t = np.arange(n) / SR
    wet = bandnoise(n, 2500, 400, 0.6) * env(n, 0.004, dur, 3)
    blob = np.sin(2 * np.pi * (180 * t - 260 * t * t)) * env(n, 0.002, 0.12, 2) * 0.6
    drops = np.zeros(n)
    for k in range(5):
        s = int(SR * (0.03 + 0.04 * k + 0.02 * rng.random()))
        m = int(SR * 0.04)
        if s + m < n:
            tt = np.arange(m) / SR
            f = 900 + 900 * rng.random()
            drops[s:s + m] += np.sin(2 * np.pi * f * tt * (1 + 3 * tt)) * np.exp(-tt * 70) * 0.35
    return wet + blob + drops


def main():
    os.makedirs(OUT, exist_ok=True)
    save("whoosh_1.wav", whoosh(1, 600, 2800, 0.22), 0.5)
    save("whoosh_2.wav", whoosh(2, 500, 2200, 0.26), 0.5)
    save("whoosh_3.wav", whoosh(3, 800, 3500, 0.18), 0.5)
    for k in range(3):
        save(f"squish_{k + 1}.wav", squish(10 + k), 0.8)
    # launch: soft low "fwump"
    for k in range(2):
        n = int(SR * 0.3)
        t = np.arange(n) / SR
        x = bandnoise(n, 300 + 80 * k, 900, 0.5) * env(n, 0.01, 0.25, 2) + np.sin(2 * np.pi * (90 + 20 * k) * t * (1 + 2 * t)) * env(n, 0.005, 0.2, 2) * 0.5
        save(f"launch_{k + 1}.wav", x, 0.45)
    # fuse: crackling hiss, loopable 1 s
    n = SR
    x = bandnoise(n, 4000, 4000, 0.8) * 0.4
    crack = (rng.random(n) > 0.9985).astype(float) * rng.standard_normal(n) * 6
    x += np.convolve(crack, np.exp(-np.arange(200) / 30.0), "same")
    save("fuse.wav", x, 0.6)
    # freeze: icy shimmer of high partials
    n = int(SR * 1.2)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f in (1760, 2217, 2637, 3520, 4186, 5274):
        x += np.sin(2 * np.pi * f * t + rng.random() * 6) * np.exp(-t * (2 + rng.random() * 2)) * (0.5 + 0.5 * np.sin(2 * np.pi * (6 + rng.random() * 6) * t))
    x += bandnoise(n, 6000, 2000, 0.4) * env(n, 0.01, 0.8, 2) * 0.6
    save("freeze.wav", x, 0.6)
    # miss: low sad "bonk"
    n = int(SR * 0.45)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * (220 * t - 120 * t * t)) * np.exp(-t * 7) + 0.5 * np.sin(2 * np.pi * (330 * t - 200 * t * t)) * np.exp(-t * 9)
    save("miss.wav", x, 0.6)
    # thump: boss hit
    n = int(SR * 0.35)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * (110 * t - 60 * t * t)) * np.exp(-t * 12) + bandnoise(n, 1500, 300, 0.7) * env(n, 0.002, 0.15, 3) * 0.6
    save("thump.wav", x, 0.85)
    print("ok")


main()
