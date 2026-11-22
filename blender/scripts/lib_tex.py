"""numpy texture painting helpers for fruit skins (equirect u=angle, v=height) and cut sections (polar)."""
import numpy as np


def rng(seed):
    return np.random.default_rng(seed)


def _upscale(a, h, w):
    """bilinear upscale of a small grid to (h, w), wrapping in x (u is an angle)."""
    sh, sw = a.shape
    a = np.concatenate([a, a[:, :1]], axis=1)  # wrap u
    ys = np.linspace(0, sh - 1, h)
    xs = np.linspace(0, sw, w, endpoint=False)
    y0 = np.floor(ys).astype(int); y1 = np.minimum(y0 + 1, sh - 1); fy = (ys - y0)[:, None]
    x0 = np.floor(xs).astype(int); x1 = x0 + 1; fx = (xs - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    top = a[y0][:, x0] * (1 - fx) + a[y0][:, x1] * fx
    bot = a[y1][:, x0] * (1 - fx) + a[y1][:, x1] * fx
    return top * (1 - fy) + bot * fy


def fbm(h, w, seed=0, base=4, octaves=5, aspect=1.0):
    """value-noise fbm in [0,1], tileable in u."""
    r = rng(seed)
    out = np.zeros((h, w))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        gw = int(base * aspect * 2 ** o) + 1
        gh = int(base * 2 ** o) + 1
        out += amp * _upscale(r.random((gh, gw)), h, w)
        tot += amp
        amp *= 0.5
    out /= tot
    out = (out - out.min()) / max(1e-6, out.max() - out.min())
    return out


def col(c):
    return np.array(c, dtype=float).reshape(1, 1, 3)


def mix(a, b, t):
    t = np.clip(t, 0, 1)
    if t.ndim == 2:
        t = t[..., None]
    return a * (1 - t) + b * t


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def dots(h, w, n, radius, seed, jitter=1.0, aspect=2.0):
    """mask of n soft round dots (in pixels, radius in px), wrapping in u."""
    r = rng(seed)
    m = np.zeros((h, w))
    yy, xx = np.mgrid[0:h, 0:w]
    for _ in range(n):
        cy, cx = r.random() * h, r.random() * w
        rr = radius * (0.6 + 0.8 * r.random() * jitter)
        x0, x1 = int(cx - rr * 2), int(cx + rr * 2) + 1
        y0, y1 = max(0, int(cy - rr * 2)), min(h, int(cy + rr * 2) + 1)
        xs = np.arange(x0, x1) % w
        dy = (yy[y0:y1, 0][:, None] - cy)
        dx = (np.arange(x0, x1)[None, :] - cx)
        d = np.sqrt(dx * dx + dy * dy) / rr
        v = np.clip(1.2 - d, 0, 1)
        m[y0:y1][:, xs] = np.maximum(m[y0:y1][:, xs], v)
    return np.clip(m, 0, 1)


def polar(n):
    """r in [0,1] (1 = rim at the half-width), angle in [-pi,pi] for an n x n cap texture."""
    yy, xx = np.mgrid[0:n, 0:n]
    x = (xx + 0.5) / n * 2 - 1
    y = (yy + 0.5) / n * 2 - 1
    return np.sqrt(x * x + y * y), np.arctan2(y, x), x, y


def to_rgba8(img, alpha=None):
    img = np.clip(img, 0, 1)
    h, w, _ = img.shape
    a = np.ones((h, w, 1)) if alpha is None else np.clip(alpha, 0, 1)[..., None]
    return np.concatenate([img, a], axis=2)
