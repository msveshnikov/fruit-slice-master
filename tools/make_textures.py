"""Effect textures (white + alpha, tinted in Godot): juice splats, droplets, slash streak, sparkles, petals,
snowflakes, smoke, frost vignette.   python tools/make_textures.py -> assets/textures/fx/*.png"""
import numpy as np, os, math
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures", "fx")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(5)


def grid(n, m=None):
    m = m or n
    yy, xx = np.mgrid[0:m, 0:n]
    return (xx + 0.5) / n * 2 - 1, (yy + 0.5) / m * 2 - 1


def sm(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def save(name, a, rgb=None):
    a = np.clip(a, 0, 1)
    h, w = a.shape
    img = np.zeros((h, w, 4), np.uint8)
    if rgb is None:
        img[..., :3] = 255
    else:
        img[..., :3] = (np.clip(rgb, 0, 1) * 255).astype(np.uint8)
    img[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, name))


def noise(n, base, seed):
    r = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp = 1
    for o in range(5):
        g = r.random((base * 2 ** o + 1, base * 2 ** o + 1))
        img = np.array(Image.fromarray((g * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
        out += img * amp
        amp *= 0.5
    return (out - out.min()) / (out.max() - out.min())


# soft dot
x, y = grid(64)
r = np.sqrt(x * x + y * y)
save("dot.png", sm(1.0, 0.0, r) ** 1.5)
# hard droplet (juice drop with highlight, white)
save("drop.png", sm(0.95, 0.75, r))

# splats
for k in range(4):
    n = 256
    x, y = grid(n)
    ang = np.arctan2(y, x)
    nz = noise(n, 4, 20 + k)
    r = np.sqrt(x * x + y * y)
    edge = 0.42 + 0.12 * np.sin(ang * (5 + k) + k) + 0.18 * (nz - 0.5)
    a = sm(edge + 0.02, edge - 0.02, r)
    # spikes / streaks
    for s in range(9 + k * 2):
        th = rng.random() * math.tau
        ln = 0.55 + rng.random() * 0.4
        w = 0.025 + rng.random() * 0.04
        px, py = math.cos(th), math.sin(th)
        along = x * px + y * py
        across = np.abs(-x * py + y * px)
        wid = w * (1 - np.clip(along / ln, 0, 1)) + 0.004
        a = np.maximum(a, sm(wid + 0.01, wid, across) * (along > 0) * (along < ln))
        # droplet at the tip
        cx, cy = px * (ln + 0.05), py * (ln + 0.05)
        d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
        a = np.maximum(a, sm(w * 1.2 + 0.01, w * 1.2, d))
    for s in range(14):
        th = rng.random() * math.tau
        rr = 0.5 + rng.random() * 0.45
        cx, cy = math.cos(th) * rr, math.sin(th) * rr
        d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
        s_ = 0.01 + rng.random() * 0.035
        a = np.maximum(a, sm(s_ + 0.01, s_, d))
    a *= 0.75 + 0.25 * nz
    save(f"splat_{k + 1}.png", a)

# slash streak (horizontal)
w, h = 256, 64
x, y = grid(w, h)
a = sm(1.0, 0.0, np.abs(y) / (1 - np.abs(x) ** 2 + 1e-3)) * (1 - np.abs(x) ** 1.5)
save("streak.png", a)

# ring
x, y = grid(128)
r = np.sqrt(x * x + y * y)
save("ring.png", sm(0.1, 0.0, np.abs(r - 0.8)) * 0.9 + sm(0.25, 0.0, np.abs(r - 0.78)) * 0.4)

# sparkle star
x, y = grid(64)
r = np.sqrt(x * x + y * y)
a = np.maximum(sm(0.12, 0.0, np.abs(x)) * sm(1.0, 0.0, np.abs(y)), sm(0.12, 0.0, np.abs(y)) * sm(1.0, 0.0, np.abs(x)))
a = np.maximum(a, sm(0.4, 0.0, r))
save("spark.png", a)

# petal
x, y = grid(64)
a = sm(1.0, 0.92, (x / 0.55) ** 2 + ((y + 0.1 * x * x) / 0.9) ** 2) * (1 - sm(0.0, 0.15, -y - 0.75 + np.abs(x) * 2) * 0.0)
notch = sm(0.08, 0.0, np.sqrt(x * x + (y + 0.9) ** 2) - 0.12)
a = np.clip(a - notch, 0, 1)
rgb = np.ones((64, 64, 3))
rgb[..., 1] = 0.75 + 0.25 * (y + 1) / 2
rgb[..., 2] = 0.85 + 0.15 * (y + 1) / 2
save("petal.png", a, rgb)

# snowflake
x, y = grid(64)
r = np.sqrt(x * x + y * y)
ang = np.arctan2(y, x)
arm = np.abs(((ang / (math.tau / 6)) % 1.0) - 0.5) * 2  # 1 on arm
a = sm(0.85, 0.97, arm) * sm(0.95, 0.7, r)
a = np.maximum(a, sm(0.3, 0.1, r))
save("flake.png", a)

# smoke puff
n = 128
x, y = grid(n)
r = np.sqrt(x * x + y * y)
nz = noise(n, 3, 77)
save("smoke.png", sm(1.0, 0.3, r + (nz - 0.5) * 0.5) * (0.6 + 0.4 * nz))

# frost vignette (portrait-ish square, stretched in game)
n = 512
x, y = grid(n)
nz = noise(n, 6, 88)
edge = np.maximum(np.abs(x), np.abs(y))
a = sm(0.55, 1.0, edge + (nz - 0.5) * 0.35)
cr = noise(n, 24, 89)
a = np.clip(a * (0.7 + 0.5 * cr), 0, 1)
rgb = np.ones((n, n, 3))
rgb[..., 0] = 0.75
rgb[..., 1] = 0.92
save("frost.png", a, rgb)

# glow (big soft)
x, y = grid(128)
r = np.sqrt(x * x + y * y)
save("glow.png", np.exp(-r * r * 4) * sm(1.0, 0.8, r))
print("ok")
