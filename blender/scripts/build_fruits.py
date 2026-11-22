"""Builds every fruit (whole + two halves with a painted cut face), the bomb and special fruits.

blender -b --factory-startup -P blender/scripts/build_fruits.py -- [--only apple,orange] [--no-render]

Output:
  assets/models/fruits/<name>.glb   nodes: whole, top, bot   (bomb: whole only)
  assets/models/fruits.json        per fruit: radius, half offsets, juice/flesh colours
  assets/ui/fruits/<name>.png      256 px icons (Cycles, transparent)
  renders/fruits_sheet.png         contact sheet of all fruits, whole and cut
Conventions: Blender Z up -> Godot Y up. Fruit axis = Z. The cut plane is z = 0 (normal +Z), so in Godot
the halves separate along local +Y / -Y. Each half's origin is its own centre; its offset from the fruit
centre is in fruits.json (Godot coordinates).
"""
import bpy, bmesh, sys, os, json, math
import numpy as np
from mathutils import Vector, Matrix

sys.path.append(os.path.dirname(__file__))
from lib_tex import *  # noqa

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_M = os.path.join(ROOT, "assets", "models", "fruits")
OUT_I = os.path.join(ROOT, "assets", "ui", "fruits")
OUT_R = os.path.join(ROOT, "renders")
TEX_TMP = os.path.join(ROOT, "blender", "tex")
for d in (OUT_M, OUT_I, OUT_R, TEX_TMP):
    os.makedirs(d, exist_ok=True)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = None
if "--only" in argv:
    ONLY = argv[argv.index("--only") + 1].split(",")
NO_RENDER = "--no-render" in argv

SW, SH = 1024, 512   # skin texture
CN = 512             # cut texture
TAU = math.tau


# ------------------------------------------------------------------ geometry

def param_body(bm, nu, nv, fn):
    """Closed surface of revolution-like param mesh. fn(theta, t) -> (x, y, z); t: 0 bottom pole .. 1 top pole.
    Returns list of faces. UV: u = theta / tau, v = t."""
    uv = bm.loops.layers.uv.verify()
    rings = []
    for j in range(1, nv):
        t = j / nv
        rings.append([bm.verts.new(fn(TAU * i / nu, t)) for i in range(nu)])
    bot = bm.verts.new(fn(0.0, 0.0))
    top = bm.verts.new(fn(0.0, 1.0))
    faces = []
    for j in range(len(rings) - 1):
        a, b = rings[j], rings[j + 1]
        for i in range(nu):
            i2 = (i + 1) % nu
            f = bm.faces.new((a[i], a[i2], b[i2], b[i]))
            u0, u1 = i / nu, (i + 1) / nu
            v0, v1 = (j + 1) / nv, (j + 2) / nv
            for l, (u, v) in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
                l[uv].uv = (u, v)
            faces.append(f)
    for i in range(nu):
        i2 = (i + 1) % nu
        f = bm.faces.new((rings[0][i2], rings[0][i], bot))
        for l, (u, v) in zip(f.loops, (((i + 1) / nu, 1 / nv), (i / nu, 1 / nv), ((i + 0.5) / nu, 0.0))):
            l[uv].uv = (u, v)
        faces.append(f)
        f = bm.faces.new((rings[-1][i], rings[-1][i2], top))
        for l, (u, v) in zip(f.loops, ((i / nu, (nv - 1) / nv), ((i + 1) / nu, (nv - 1) / nv), ((i + 0.5) / nu, 1.0))):
            l[uv].uv = (u, v)
        faces.append(f)
    for f in faces:
        f.smooth = True
    return faces


def revolve(R, H, prof, mod=None, nu=56, nv=40, bend=0.0):
    """prof(t) -> (r_factor, z_factor in [-1,1]); mod(theta, t) -> radius multiplier."""
    def fn(th, t):
        rf, zf = prof(t)
        m = mod(th, t) if mod else 1.0
        r = R * rf * m
        z = H * zf
        x = r * math.cos(th) + bend * z * z
        return (x, r * math.sin(th), z)
    return fn, nu, nv


def mesh_obj(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def leaf_bm(bm, length, width, bend, base, direction, up, mat_index, nseg=8, twist=0.0):
    """A curved leaf strip from base point along direction (unit), bending toward 'up'."""
    uv = bm.loops.layers.uv.verify()
    d = Vector(direction).normalized()
    u = Vector(up).normalized()
    side = d.cross(u).normalized()
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    rows = []
    for k in range(nseg + 1):
        s = k / nseg
        w = width * math.sin(math.pi * min(1.0, s * 1.05)) ** 0.8 * (1 - 0.15 * s)
        c = Vector(base) + d * (length * s) + u * (bend * length * s * s)
        tw = side * math.cos(twist * s) + u * math.sin(twist * s)
        lift = u * (w * 0.25)
        rows.append((c - tw * w * 0.5 + lift * 0.0, c + lift, c + tw * w * 0.5))
    faces = []
    for k in range(nseg):
        a = [bm.verts.new(p) for p in rows[k]] if k == 0 else prev
        b = [bm.verts.new(p) for p in rows[k + 1]]
        for i in range(2):
            f = bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
            f.material_index = mat_index
            f.smooth = True
            for l, (uu, vv) in zip(f.loops, ((i / 2, k / nseg), ((i + 1) / 2, k / nseg), ((i + 1) / 2, (k + 1) / nseg), (i / 2, (k + 1) / nseg))):
                l[uv].uv = (uu, vv)
            faces.append(f)
        prev = b
    return faces


def cyl_bm(bm, p0, p1, r0, r1, mat_index, n=10):
    uv = bm.loops.layers.uv.verify()
    p0, p1 = Vector(p0), Vector(p1)
    ax = (p1 - p0).normalized()
    a = ax.orthogonal().normalized()
    b = ax.cross(a)
    ring0 = [bm.verts.new(p0 + (a * math.cos(TAU * i / n) + b * math.sin(TAU * i / n)) * r0) for i in range(n)]
    ring1 = [bm.verts.new(p1 + (a * math.cos(TAU * i / n) + b * math.sin(TAU * i / n)) * r1) for i in range(n)]
    for i in range(n):
        f = bm.faces.new((ring0[i], ring0[(i + 1) % n], ring1[(i + 1) % n], ring1[i]))
        f.material_index = mat_index
        f.smooth = True
        for l in f.loops:
            l[uv].uv = (0.5, 0.5)
    f = bm.faces.new(list(reversed(ring0)))
    f.material_index = mat_index
    f = bm.faces.new(ring1)
    f.material_index = mat_index


# ------------------------------------------------------------------ materials

def save_img(name, arr):
    h, w, _ = arr.shape
    img = bpy.data.images.get(name) or bpy.data.images.new(name, w, h, alpha=True)
    img.scale(w, h)
    img.pixels.foreach_set(np.flipud(arr).astype(np.float32).ravel())
    path = os.path.join(TEX_TMP, name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def material(name, img=None, color=(1, 1, 1), rough=0.4, metal=0.0, emit=None, emit_str=0.0, coat=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    if img is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        nt.links.new(tn.outputs[0], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if coat > 0 and "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1)
        bsdf.inputs["Emission Strength"].default_value = emit_str
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
    return m


# ------------------------------------------------------------------ painted skins (h=512 rows = t from top(0) to bottom)
# image row 0 is the TOP of the texture = v=1 = top pole (we flip on save so v matches rows reversed)

def grid_uv():
    v = np.linspace(1, 0, SH)[:, None] * np.ones((1, SW))       # t: 1 at top row
    u = np.ones((SH, 1)) * np.linspace(0, 1, SW, endpoint=False)[None, :]
    return u, v


def skin_apple(seed=1, base=(0.78, 0.05, 0.06), blush=(0.95, 0.75, 0.2)):
    u, v = grid_uv()
    n = fbm(SH, SW, seed, base=3, octaves=4, aspect=2)
    streak = fbm(SH, SW, seed + 7, base=2, octaves=4, aspect=24)
    img = mix(col(base), col(blush), smooth(0.55, 0.95, n * 0.7 + 0.45 * np.cos(u * TAU) * 0.5 + 0.2))
    img = mix(img, col(base) * 0.6, smooth(0.5, 0.9, streak) * 0.6)
    img = mix(img, col((0.55, 0.6, 0.15)), smooth(0.93, 1.0, v) * 0.8)
    img = mix(img, col((1, 0.95, 0.7)), dots(SH, SW, 220, 1.6, seed + 3) * 0.55)
    return img


def skin_citrus(rgb, seed, deep):
    u, v = grid_uv()
    pores = fbm(SH, SW, seed, base=24, octaves=3, aspect=2)
    n = fbm(SH, SW, seed + 1, base=3, octaves=4, aspect=2)
    img = col(rgb) * (0.86 + 0.18 * n[..., None])
    img = mix(img, col(deep), smooth(0.55, 0.9, pores) * 0.45)
    img = mix(img, col(rgb) * 0.55, smooth(0.96, 1.0, v) + smooth(0.04, 0.0, v))
    return img


def skin_watermelon(seed=4):
    u, v = grid_uv()
    wob = fbm(SH, SW, seed, base=3, octaves=5, aspect=1) - 0.5
    stripe = 0.5 + 0.5 * np.cos((u * 16 + wob * 0.9) * TAU)
    img = mix(col((0.05, 0.22, 0.06)), col((0.42, 0.66, 0.2)), smooth(0.55, 0.75, stripe))
    img = img * (0.85 + 0.25 * fbm(SH, SW, seed + 3, base=8, octaves=4, aspect=2)[..., None])
    img = mix(img, col((0.6, 0.6, 0.25)), smooth(0.93, 1.0, v) * 0.6)
    return img


def skin_pineapple(seed=5):
    u, v = grid_uv()
    a = u * 14 + v * 9
    b = u * 14 - v * 9
    fa, fb = a - np.floor(a), b - np.floor(b)
    edge = np.minimum(np.minimum(fa, 1 - fa), np.minimum(fb, 1 - fb))
    cell = smooth(0.0, 0.25, edge)
    centre = smooth(0.32, 0.5, edge)
    n = fbm(SH, SW, seed, base=6, octaves=4, aspect=2)
    img = mix(col((0.38, 0.2, 0.05)), col((0.92, 0.62, 0.12)), cell)
    img = mix(img, col((0.55, 0.62, 0.15)), centre * (0.5 + 0.5 * n) * 0.7)
    img = img * (0.85 + 0.2 * n[..., None])
    return img


def skin_banana(seed=6):
    u, v = grid_uv()
    n = fbm(SH, SW, seed, base=3, octaves=5, aspect=2)
    ridge = np.abs(np.cos(u * 5 * math.pi))
    img = col((0.98, 0.82, 0.18)) * (0.9 + 0.12 * n[..., None]) * (0.9 + 0.1 * ridge[..., None])
    img = mix(img, col((0.55, 0.65, 0.15)), smooth(0.85, 0.97, v) * 0.6 + smooth(0.12, 0.03, v) * 0.5)
    img = mix(img, col((0.25, 0.15, 0.05)), smooth(0.97, 1.0, v) + smooth(0.025, 0.0, v))
    img = mix(img, col((0.45, 0.28, 0.08)), dots(SH, SW, 40, 3, seed + 2) * 0.6)
    return img


def skin_pear(seed=7):
    u, v = grid_uv()
    n = fbm(SH, SW, seed, base=3, octaves=4, aspect=2)
    img = mix(col((0.62, 0.75, 0.15)), col((0.92, 0.82, 0.25)), n)
    img = mix(img, col((0.85, 0.35, 0.12)), smooth(0.6, 1.0, 0.5 + 0.5 * np.cos(u * TAU)) * smooth(0.3, 0.7, n) * 0.6)
    img = mix(img, col((0.5, 0.35, 0.12)), dots(SH, SW, 500, 1.5, seed + 1) * 0.6)
    return img


def skin_kiwi(seed=8):
    u, v = grid_uv()
    fuzz = fbm(SH, SW, seed, base=48, octaves=2, aspect=2)
    n = fbm(SH, SW, seed + 1, base=3, octaves=4, aspect=2)
    img = col((0.42, 0.28, 0.13)) * (0.75 + 0.35 * fuzz[..., None]) * (0.85 + 0.2 * n[..., None])
    return img


def skin_peach(seed=9):
    u, v = grid_uv()
    n = fbm(SH, SW, seed, base=3, octaves=4, aspect=2)
    img = mix(col((1.0, 0.72, 0.3)), col((0.9, 0.22, 0.2)), smooth(0.35, 0.9, n * 0.6 + v * 0.6))
    img = img * (0.92 + 0.1 * fbm(SH, SW, seed + 2, base=40, octaves=2, aspect=2)[..., None])
    return img


def skin_coconut(seed=10):
    u, v = grid_uv()
    fib = fbm(SH, SW, seed, base=2, octaves=6, aspect=40)
    n = fbm(SH, SW, seed + 1, base=4, octaves=4, aspect=2)
    img = mix(col((0.22, 0.12, 0.05)), col((0.55, 0.36, 0.18)), fib * 0.8 + n * 0.3)
    return img


def skin_strawberry(seed=11):
    u, v = grid_uv()
    n = fbm(SH, SW, seed, base=3, octaves=4, aspect=2)
    img = mix(col((0.85, 0.04, 0.08)), col((0.62, 0.0, 0.05)), n)
    img = mix(img, col((1.0, 0.75, 0.55)), smooth(0.9, 1.0, v) * 0.5)
    # seeds: staggered grid
    rows, cols = 14, 22
    yy, xx = np.mgrid[0:SH, 0:SW]
    gy = yy / SH * rows
    gx = xx / SW * cols + 0.5 * (np.floor(gy) % 2)
    dy = gy - np.floor(gy) - 0.5
    dx = gx - np.floor(gx) - 0.5
    d = np.sqrt((dx * 1.0) ** 2 + (dy * 1.6) ** 2)
    img = mix(img, col((0.35, 0.0, 0.02)), smooth(0.24, 0.16, d) * 0.8)
    img = mix(img, col((1.0, 0.85, 0.25)), smooth(0.12, 0.06, d))
    return img


def skin_plum(seed=12):
    u, v = grid_uv()
    n = fbm(SH, SW, seed, base=3, octaves=4, aspect=2)
    img = mix(col((0.32, 0.05, 0.3)), col((0.55, 0.12, 0.45)), n)
    img = mix(img, col((0.75, 0.68, 0.85)), fbm(SH, SW, seed + 5, base=12, octaves=3, aspect=2) * 0.28)
    return img


def skin_mango(seed=13):
    u, v = grid_uv()
    n = fbm(SH, SW, seed, base=3, octaves=4, aspect=2)
    g = 0.5 + 0.5 * np.cos(u * TAU)
    img = mix(col((0.35, 0.6, 0.12)), col((1.0, 0.7, 0.1)), smooth(0.2, 0.7, g * 0.7 + n * 0.4))
    img = mix(img, col((0.95, 0.25, 0.12)), smooth(0.7, 1.0, g * 0.6 + v * 0.5) * 0.85)
    img = mix(img, col((0.9, 0.9, 0.5)), dots(SH, SW, 300, 1.2, seed) * 0.4)
    return img


def skin_dragon(seed=14):
    u, v = grid_uv()
    n = fbm(SH, SW, seed, base=3, octaves=4, aspect=2)
    img = mix(col((0.88, 0.08, 0.45)), col((1.0, 0.3, 0.6)), n)
    return img


def skin_star(seed=15):
    u, v = grid_uv()
    n = fbm(SH, SW, seed, base=3, octaves=4, aspect=2)
    rib = np.abs(np.cos(u * 5 * math.pi))
    img = mix(col((1.0, 0.78, 0.1)), col((0.6, 0.85, 0.15)), (1 - rib) * 0.5 + n * 0.2)
    img = mix(img, col((0.55, 0.4, 0.05)), smooth(0.97, 0.995, rib) * 0.6)
    return img


def skin_pomegranate(seed=16):
    u, v = grid_uv()
    n = fbm(SH, SW, seed, base=3, octaves=4, aspect=2)
    img = mix(col((0.62, 0.05, 0.08)), col((0.95, 0.35, 0.18)), n * 0.8)
    img = mix(img, col((1.0, 0.82, 0.3)), smooth(0.6, 0.95, fbm(SH, SW, seed + 4, base=5, octaves=3, aspect=2)) * 0.35)
    return img


def skin_flat(rgb, seed, var=0.12):
    n = fbm(SH, SW, seed, base=4, octaves=4, aspect=2)
    return col(rgb) * (1 - var + 2 * var * n[..., None])


# ------------------------------------------------------------------ cut faces (polar)

def cut_citrus(peel, pith, flesh, seg=10, seed=1):
    r, a, x, y = polar(CN)
    n = fbm(CN, CN, seed, base=10, octaves=4)
    wedge = np.abs(((a / TAU * seg) % 1.0) - 0.5) * 2         # 1 at membrane
    mem = smooth(0.86, 0.97, wedge) * smooth(0.12, 0.2, r)
    img = col(flesh) * (0.8 + 0.35 * n[..., None])
    vesicle = fbm(CN, CN, seed + 2, base=40, octaves=2)
    img = mix(img, col(flesh) * 1.25, smooth(0.6, 0.9, vesicle) * 0.5)
    img = mix(img, col((1, 0.97, 0.9)), mem * 0.85)
    img = mix(img, col((1, 0.97, 0.9)), smooth(0.14, 0.06, r))
    img = mix(img, col(pith), smooth(0.84, 0.87, r))
    img = mix(img, col(peel), smooth(0.93, 0.95, r))
    return img


def cut_simple(flesh, rind, rind_w=0.05, core=None, seeds=None, seed=1, center_col=None):
    r, a, x, y = polar(CN)
    n = fbm(CN, CN, seed, base=6, octaves=4)
    img = col(flesh) * (0.88 + 0.22 * n[..., None])
    img = mix(img, col(flesh) * 1.15, smooth(0.5, 0.0, r) * 0.4)
    if center_col is not None:
        img = mix(img, col(center_col), smooth(0.28, 0.12, r))
    img = mix(img, col(rind), smooth(1 - rind_w - 0.02, 1 - rind_w, r))
    if core is not None:
        kind, ccol, cr = core
        if kind == "pit":
            d = np.sqrt((x / 0.75) ** 2 + (y / 1.0) ** 2)
            img = mix(img, col(ccol) * (0.8 + 0.3 * fbm(CN, CN, seed + 9, base=16, octaves=2)[..., None]), smooth(cr, cr - 0.03, d))
        elif kind == "star":   # apple / pear core: star of 5 seed chambers
            star = cr * (0.7 + 0.3 * np.cos(5 * a))
            img = mix(img, col(ccol), smooth(star + 0.03, star, r) * 0.7)
    if seeds is not None:
        sc, ring, count, size = seeds
        for k in range(count):
            ang = TAU * k / count + 0.3
            cx, cy = math.cos(ang) * ring, math.sin(ang) * ring
            dx, dy = x - cx, y - cy
            # teardrop pointing to centre
            along = (dx * math.cos(ang) + dy * math.sin(ang))
            across = (-dx * math.sin(ang) + dy * math.cos(ang))
            d = np.sqrt((along / (size * 1.6)) ** 2 + (across / size) ** 2)
            img = mix(img, col(sc), smooth(1.0, 0.8, d))
    return img


def cut_watermelon(seed=4):
    r, a, x, y = polar(CN)
    n = fbm(CN, CN, seed, base=8, octaves=4)
    img = col((0.95, 0.12, 0.2)) * (0.85 + 0.25 * n[..., None])
    img = mix(img, col((1.0, 0.45, 0.45)), smooth(0.25, 0.0, r) * 0.4)
    rr = rng(seed)
    for k in range(26):
        ang = rr.random() * TAU
        ring = 0.35 + rr.random() * 0.35
        cx, cy = math.cos(ang) * ring, math.sin(ang) * ring
        along = ((x - cx) * math.cos(ang) + (y - cy) * math.sin(ang))
        across = (-(x - cx) * math.sin(ang) + (y - cy) * math.cos(ang))
        d = np.sqrt((along / 0.05) ** 2 + (across / 0.028) ** 2)
        img = mix(img, col((0.05, 0.03, 0.03)), smooth(1.0, 0.8, d))
        img = mix(img, col((0.5, 0.45, 0.4)), smooth(0.5, 0.2, np.sqrt(((along + 0.015) / 0.02) ** 2 + ((across + 0.008) / 0.01) ** 2)) * 0.6)
    img = mix(img, col((0.95, 0.95, 0.8)), smooth(0.85, 0.88, r))
    img = mix(img, col((0.45, 0.75, 0.3)), smooth(0.9, 0.92, r))
    img = mix(img, col((0.06, 0.25, 0.06)), smooth(0.95, 0.97, r))
    return img


def cut_kiwi(seed=8):
    r, a, x, y = polar(CN)
    n = fbm(CN, CN, seed, base=8, octaves=4)
    streak = 0.5 + 0.5 * np.cos(a * 60 + n * 6)
    img = mix(col((0.35, 0.68, 0.08)), col((0.55, 0.85, 0.2)), streak * 0.4 + smooth(0.9, 0.4, r) * 0.4)
    img = mix(img, col((0.95, 0.95, 0.75)), smooth(0.3, 0.2, r * (1 + 0.15 * np.cos(a * 14))))
    rr = rng(seed)
    for k in range(70):
        ang = rr.random() * TAU
        ring = 0.32 + rr.random() * 0.08
        cx, cy = math.cos(ang) * ring, math.sin(ang) * ring
        d = np.sqrt(((x - cx) / 0.022) ** 2 + ((y - cy) / 0.014) ** 2)
        img = mix(img, col((0.05, 0.04, 0.02)), smooth(1.0, 0.7, d))
    img = mix(img, col((0.4, 0.28, 0.12)), smooth(0.95, 0.97, r))
    return img


def cut_pineapple(seed=5):
    r, a, x, y = polar(CN)
    n = fbm(CN, CN, seed, base=8, octaves=4)
    fib = 0.5 + 0.5 * np.cos(a * 50 + n * 4)
    img = mix(col((1.0, 0.82, 0.25)), col((1.0, 0.9, 0.45)), fib * 0.5)
    img = mix(img, col((1.0, 0.95, 0.7)), smooth(0.25, 0.15, r))
    img = mix(img, col((0.6, 0.4, 0.1)), smooth(0.92, 0.95, r))
    return img


def cut_pomegranate(seed=16):
    r, a, x, y = polar(CN)
    img = col((1.0, 0.9, 0.7)).repeat(CN, 0).repeat(CN, 1)
    rr = rng(seed)
    for k in range(160):
        cx, cy = (rr.random() * 2 - 1) * 0.85, (rr.random() * 2 - 1) * 0.85
        if cx * cx + cy * cy > 0.72:
            continue
        s = 0.06 + rr.random() * 0.03
        d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / s
        g = smooth(1.0, 0.0, d)
        img = mix(img, col((0.8, 0.02, 0.12)) * (0.8 + 0.5 * g[..., None]), smooth(1.0, 0.85, d))
        img = mix(img, col((1.0, 0.7, 0.75)), smooth(0.35, 0.1, np.sqrt((x - cx + s * 0.3) ** 2 + (y - cy + s * 0.3) ** 2) / s) * 0.8)
    img = mix(img, col((0.7, 0.12, 0.1)), smooth(0.9, 0.93, r))
    return img


def cut_ice(seed=17):
    r, a, x, y = polar(CN)
    n = fbm(CN, CN, seed, base=5, octaves=5)
    facet = np.abs(np.cos(a * 7 + n * 3))
    img = mix(col((0.55, 0.85, 1.0)), col((0.95, 1.0, 1.0)), facet * 0.5 + smooth(0.6, 0.0, r) * 0.5)
    img = mix(img, col((0.3, 0.6, 1.0)), smooth(0.9, 0.95, r))
    return img


def cut_coconut(seed=10):
    r, a, x, y = polar(CN)
    n = fbm(CN, CN, seed, base=8, octaves=4)
    img = mix(col((0.88, 0.92, 0.95)), col((0.75, 0.82, 0.9)), n)
    img = mix(img, col((1.0, 0.99, 0.96)), smooth(0.55, 0.6, r))
    img = mix(img, col((0.32, 0.2, 0.1)), smooth(0.84, 0.86, r))
    img = mix(img, col((0.55, 0.38, 0.22)) * (0.8 + 0.3 * n[..., None]), smooth(0.9, 0.92, r))
    return img


def cut_dragon(seed=14):
    r, a, x, y = polar(CN)
    n = fbm(CN, CN, seed, base=8, octaves=4)
    img = col((0.98, 0.97, 0.95)) * (0.92 + 0.1 * n[..., None])
    img = mix(img, col((0.05, 0.03, 0.03)), dots(CN, CN, 260, 3.2, seed) * smooth(0.85, 0.8, r))
    img = mix(img, col((0.92, 0.1, 0.5)), smooth(0.9, 0.93, r))
    return img


def cut_star(seed=15):
    r, a, x, y = polar(CN)
    n = fbm(CN, CN, seed, base=8, octaves=4)
    img = col((1.0, 0.88, 0.3)) * (0.9 + 0.2 * n[..., None])
    img = mix(img, col((1.0, 0.97, 0.75)), smooth(0.25, 0.1, r))
    for k in range(5):
        ang = TAU * k / 5 + math.pi / 2
        cx, cy = math.cos(ang) * 0.3, math.sin(ang) * 0.3
        d = np.sqrt(((x - cx) / 0.06) ** 2 + ((y - cy) / 0.06) ** 2)
        img = mix(img, col((0.55, 0.4, 0.1)), smooth(1.0, 0.7, d))
    img = mix(img, col((0.85, 0.7, 0.1)), smooth(0.9, 0.95, r))
    return img


# ------------------------------------------------------------------ fruit definitions

def ellip(p=1.0):
    return lambda t: (math.sin(math.pi * t) ** p, -math.cos(math.pi * t))


def dimpled(p=0.85, top=0.18, bot=0.12, widen=0.12):
    def f(t):
        s = math.sin(math.pi * t) ** p
        z = -math.cos(math.pi * t)
        z -= top * math.exp(-((1 - t) / 0.1) ** 2)
        z += bot * math.exp(-(t / 0.08) ** 2)
        return s * (1 + widen * (t - 0.5)), z
    return f


def wrap(th):
    return (th + math.pi) % TAU - math.pi


FRUITS = {}


def fruit(name, **kw):
    FRUITS[name] = kw


# radius R / half-height H in metres (apple ~0.3)
fruit("apple", R=0.3, H=0.27, prof=dimpled(), mod=lambda th, t: 1 + 0.035 * math.cos(5 * th) * (1 - t),
      skin=lambda: skin_apple(), rough=0.28, cut=lambda: cut_simple((1.0, 0.96, 0.78), (0.75, 0.05, 0.06), 0.03, ("star", (0.85, 0.75, 0.5), 0.28), ((0.25, 0.12, 0.05), 0.17, 5, 0.045)),
      juice=(1.0, 0.95, 0.75), acc="apple", points=10)
fruit("orange", R=0.32, H=0.3, prof=dimpled(1.0, 0.05, 0.03, 0.0), skin=lambda: skin_citrus((1.0, 0.5, 0.04), 21, (0.85, 0.35, 0.0)), rough=0.5,
      cut=lambda: cut_citrus((1.0, 0.5, 0.05), (1.0, 0.9, 0.7), (1.0, 0.55, 0.08), 11, 21), juice=(1.0, 0.6, 0.05), acc="nub", points=10)
fruit("lemon", R=0.24, H=0.34, prof=lambda t: (math.sin(math.pi * t) ** 1.15, -math.cos(math.pi * t) * (1 + 0.12 * math.exp(-(math.sin(math.pi * t) / 0.25) ** 2))),
      skin=lambda: skin_citrus((1.0, 0.86, 0.1), 22, (0.85, 0.7, 0.0)), rough=0.45,
      cut=lambda: cut_citrus((1.0, 0.85, 0.1), (1.0, 0.98, 0.8), (1.0, 0.93, 0.4), 9, 22), juice=(1.0, 0.95, 0.35), acc=None, points=10)
fruit("lime", R=0.23, H=0.26, prof=lambda t: (math.sin(math.pi * t) ** 1.05, -math.cos(math.pi * t) * (1 + 0.06 * math.exp(-(math.sin(math.pi * t) / 0.25) ** 2))),
      skin=lambda: skin_citrus((0.35, 0.75, 0.08), 23, (0.15, 0.45, 0.02)), rough=0.45,
      cut=lambda: cut_citrus((0.3, 0.65, 0.05), (0.92, 1.0, 0.8), (0.65, 0.92, 0.3), 10, 23), juice=(0.7, 1.0, 0.35), acc=None, points=10)
fruit("watermelon", R=0.52, H=0.62, prof=ellip(0.95), skin=lambda: skin_watermelon(), rough=0.35,
      cut=lambda: cut_watermelon(), juice=(1.0, 0.15, 0.25), acc="nub", points=15, nu=64, nv=44)
fruit("pineapple", R=0.33, H=0.45, prof=lambda t: ((1 - abs(2 * t - 1) ** 3.5) ** 0.5, 2 * t - 1),
      mod=lambda th, t: 1 + 0.035 * (abs(math.sin(7 * th + 4.5 * math.pi * t)) + abs(math.sin(7 * th - 4.5 * math.pi * t))),
      skin=lambda: skin_pineapple(), rough=0.55, cut=lambda: cut_pineapple(), juice=(1.0, 0.88, 0.2), acc="crown", points=15, nu=84, nv=56)
fruit("banana", R=0.13, H=0.44, prof=lambda t: (math.sin(math.pi * t) ** 0.45 * (1 - 0.25 * abs(2 * t - 1) ** 2), 2 * t - 1),
      mod=lambda th, t: 1 + 0.07 * abs(math.cos(2.5 * th)), bend=0.85,
      skin=lambda: skin_banana(), rough=0.45, cut=lambda: cut_simple((1.0, 0.96, 0.8), (0.98, 0.85, 0.25), 0.07, None, ((0.6, 0.5, 0.35), 0.12, 3, 0.04), 6),
      juice=(1.0, 0.97, 0.8), acc=None, points=10)
fruit("pear", R=0.29, H=0.38, prof=lambda t: (math.sin(math.pi * t) ** 0.7 * (1 - 0.48 * smooth(0.35, 0.85, t)), -math.cos(math.pi * t) - 0.1 * math.exp(-(t / 0.07) ** 2) * -1),
      skin=lambda: skin_pear(), rough=0.4, cut=lambda: cut_simple((1.0, 0.98, 0.85), (0.7, 0.75, 0.2), 0.03, ("star", (0.9, 0.85, 0.65), 0.25), ((0.3, 0.15, 0.05), 0.15, 5, 0.04), 7),
      juice=(1.0, 1.0, 0.85), acc="pear", points=10)
fruit("kiwi", R=0.21, H=0.27, prof=ellip(0.9), skin=lambda: skin_kiwi(), rough=0.85, cut=lambda: cut_kiwi(), juice=(0.6, 0.95, 0.2), acc=None, points=10)
fruit("peach", R=0.31, H=0.29, prof=lambda t: (math.sin(math.pi * t) ** 0.85, -math.cos(math.pi * t) + 0.12 * math.exp(-((1 - t) / 0.08) ** 2)),
      mod=lambda th, t: 1 - 0.06 * math.exp(-(wrap(th) / 0.22) ** 2),
      skin=lambda: skin_peach(), rough=0.7, cut=lambda: cut_simple((1.0, 0.7, 0.25), (0.95, 0.35, 0.2), 0.03, ("pit", (0.5, 0.22, 0.1), 0.3), None, 9),
      juice=(1.0, 0.7, 0.3), acc="leaf", points=10)
fruit("coconut", R=0.36, H=0.4, prof=ellip(0.9), mod=lambda th, t: 1 + 0.05 * math.cos(3 * th),
      skin=lambda: skin_coconut(), rough=0.9, cut=lambda: cut_coconut(), juice=(0.95, 0.97, 1.0), acc=None, points=15)
fruit("strawberry", R=0.22, H=0.24, prof=lambda t: (math.sin(math.pi * min(t, 0.999)) ** 0.5 * (0.3 + 0.7 * t ** 0.8), -math.cos(math.pi * t)),
      skin=lambda: skin_strawberry(), rough=0.3, cut=lambda: cut_simple((1.0, 0.55, 0.55), (0.88, 0.05, 0.1), 0.1, None, None, 11, (1.0, 0.85, 0.85)),
      juice=(1.0, 0.1, 0.2), acc="calyx", points=10)
fruit("plum", R=0.25, H=0.26, prof=dimpled(0.9, 0.06, 0.02, 0.0), mod=lambda th, t: 1 - 0.04 * math.exp(-(wrap(th) / 0.2) ** 2),
      skin=lambda: skin_plum(), rough=0.45, cut=lambda: cut_simple((1.0, 0.8, 0.2), (0.4, 0.05, 0.35), 0.035, ("pit", (0.55, 0.35, 0.15), 0.3), None, 12),
      juice=(0.75, 0.1, 0.5), acc="nub", points=10)
fruit("mango", R=0.27, H=0.38, prof=ellip(0.85), mod=lambda th, t: 1 + 0.14 * math.cos(th) * math.sin(math.pi * t) - 0.05 * math.cos(2 * th),
      skin=lambda: skin_mango(), rough=0.35, cut=lambda: cut_simple((1.0, 0.72, 0.08), (0.6, 0.6, 0.1), 0.03, ("pit", (0.95, 0.9, 0.7), 0.32), None, 13),
      juice=(1.0, 0.7, 0.05), acc="nub", points=10)
fruit("dragonfruit", R=0.28, H=0.36, prof=ellip(0.85), skin=lambda: skin_dragon(), rough=0.35, cut=lambda: cut_dragon(),
      juice=(1.0, 0.95, 0.95), acc="scales", points=15)
fruit("grapefruit", R=0.37, H=0.34, prof=dimpled(1.0, 0.04, 0.03, 0.0), skin=lambda: skin_citrus((1.0, 0.62, 0.3), 24, (0.9, 0.35, 0.2)), rough=0.5,
      cut=lambda: cut_citrus((1.0, 0.55, 0.25), (1.0, 0.9, 0.8), (1.0, 0.35, 0.35), 12, 24), juice=(1.0, 0.4, 0.4), acc=None, points=15)
# specials
fruit("starfruit", R=0.27, H=0.34, prof=ellip(0.8), mod=lambda th, t: 0.55 + 0.45 * abs(math.cos(2.5 * th)) ** 0.7,
      skin=lambda: skin_star(), rough=0.25, cut=lambda: cut_star(), juice=(1.0, 0.9, 0.3), acc=None, points=30, special="frenzy")
fruit("pomegranate", R=0.38, H=0.36, prof=dimpled(0.9, -0.02, 0.05, 0.0), mod=lambda th, t: 1 + 0.03 * math.cos(6 * th),
      skin=lambda: skin_pomegranate(), rough=0.3, cut=lambda: cut_pomegranate(), juice=(0.9, 0.05, 0.15), acc="crown_p", points=5, special="multi")
fruit("frostberry", R=0.28, H=0.27, prof=dimpled(0.9, 0.1, 0.06, 0.0), mod=lambda th, t: 1 + 0.06 * abs(math.cos(4 * th + 3 * t)),
      skin=lambda: skin_flat((0.45, 0.8, 1.0), 31), rough=0.08, cut=lambda: cut_ice(), juice=(0.7, 0.95, 1.0), acc="leaf_ice", points=20, special="freeze", emit=(0.2, 0.55, 1.0))
fruit("goldapple", R=0.3, H=0.27, prof=dimpled(), skin=lambda: skin_flat((1.0, 0.75, 0.2), 32, 0.08), rough=0.18, metal=0.9,
      cut=lambda: cut_simple((1.0, 0.92, 0.55), (1.0, 0.75, 0.2), 0.04, ("star", (1.0, 0.8, 0.3), 0.28), ((0.7, 0.45, 0.1), 0.17, 5, 0.045), 33),
      juice=(1.0, 0.85, 0.3), acc="apple", points=50, special="double", emit=(0.6, 0.4, 0.05))
fruit("bomb", R=0.3, H=0.3, prof=ellip(1.0), skin=lambda: skin_flat((0.06, 0.06, 0.08), 40, 0.25), rough=0.25, metal=0.3,
      cut=None, juice=(0.2, 0.2, 0.2), acc="bomb", points=0, special="bomb")


# ------------------------------------------------------------------ accessories

def add_acc(bm, kind, R, H):
    """mat indices: 2 = leaf, 3 = stem/dark. Returns nothing; adds to bm."""
    top = H
    if kind == "apple":
        cyl_bm(bm, (0, 0, top - 0.06), (0.03, 0.0, top + 0.1), 0.018, 0.012, 3)
        leaf_bm(bm, 0.2, 0.09, 0.25, (0.02, 0, top + 0.06), (1, 0.3, 0.25), (0, 0, 1), 2, twist=0.4)
    elif kind == "pear":
        cyl_bm(bm, (0, 0, top - 0.04), (0.04, 0.02, top + 0.14), 0.016, 0.01, 3)
    elif kind == "leaf":
        cyl_bm(bm, (0, 0, top - 0.04), (0.0, 0.0, top + 0.04), 0.015, 0.012, 3)
        leaf_bm(bm, 0.22, 0.1, 0.2, (0, 0, top + 0.02), (-1, 0.2, 0.35), (0, 0, 1), 2, twist=-0.3)
    elif kind == "leaf_ice":
        leaf_bm(bm, 0.2, 0.09, 0.3, (0, 0, top - 0.02), (1, 0.2, 0.4), (0, 0, 1), 2, twist=0.3)
        leaf_bm(bm, 0.16, 0.08, 0.3, (0, 0, top - 0.02), (-1, -0.3, 0.4), (0, 0, 1), 2, twist=-0.3)
    elif kind == "nub":
        cyl_bm(bm, (0, 0, top - 0.03), (0, 0, top + 0.025), 0.02, 0.012, 3)
    elif kind == "crown":
        for k in range(18):
            ang = TAU * k / 18 + (0.17 if k % 2 else 0)
            tilt = 0.35 + 0.5 * ((k * 7) % 5) / 5
            ln = 0.28 + 0.14 * ((k * 3) % 4) / 3
            d = (math.cos(ang) * tilt, math.sin(ang) * tilt, 1.0)
            leaf_bm(bm, ln, 0.07, -0.25, (math.cos(ang) * 0.04, math.sin(ang) * 0.04, top - 0.04), d, (math.cos(ang), math.sin(ang), 0.2), 2, nseg=6)
    elif kind == "calyx":
        for k in range(8):
            ang = TAU * k / 8
            leaf_bm(bm, 0.12, 0.07, 0.15, (0, 0, top - 0.02), (math.cos(ang), math.sin(ang), -0.15), (0, 0, 1), 2, nseg=5)
        cyl_bm(bm, (0, 0, top - 0.02), (0, 0, top + 0.07), 0.015, 0.01, 2)
    elif kind == "crown_p":
        for k in range(6):
            ang = TAU * k / 6
            leaf_bm(bm, 0.11, 0.06, -0.1, (math.cos(ang) * 0.05, math.sin(ang) * 0.05, top - 0.04), (math.cos(ang) * 0.4, math.sin(ang) * 0.4, 1), (math.cos(ang), math.sin(ang), 0), 3, nseg=4)
    elif kind == "scales":
        for row in range(3):
            for k in range(6):
                ang = TAU * k / 6 + row * 0.5
                t = 0.3 + 0.22 * row
                zz = -math.cos(math.pi * t) * H
                rr = R * math.sin(math.pi * t) ** 0.85
                base = (math.cos(ang) * rr * 0.97, math.sin(ang) * rr * 0.97, zz)
                d = (math.cos(ang) * 0.35, math.sin(ang) * 0.35, 1)
                leaf_bm(bm, 0.16, 0.08, 0.6, base, d, (math.cos(ang), math.sin(ang), 0), 2, nseg=5)
    elif kind == "bomb":
        cyl_bm(bm, (0, 0, top - 0.06), (0, 0, top + 0.06), 0.11, 0.11, 3, 16)
        cyl_bm(bm, (0, 0, top + 0.05), (0, 0, top + 0.08), 0.08, 0.06, 3, 16)
        pts = [(0, 0, top + 0.06), (0.03, 0, top + 0.14), (0.08, 0.01, top + 0.2), (0.15, 0.02, top + 0.22)]
        for a, b in zip(pts, pts[1:]):
            cyl_bm(bm, a, b, 0.018, 0.018, 2, 8)


def acc_mats(name, kind, emit):
    if kind == "bomb":
        leafm = material(name + "_fuse", color=(0.55, 0.42, 0.25), rough=0.9)
        stem = material(name + "_metal", color=(0.35, 0.35, 0.38), rough=0.3, metal=1.0)
    elif kind == "leaf_ice":
        leafm = material(name + "_leaf", color=(0.6, 0.9, 1.0), rough=0.1, emit=(0.3, 0.7, 1.0), emit_str=0.6)
        stem = material(name + "_stem", color=(0.3, 0.2, 0.1), rough=0.7)
    elif kind == "scales":
        leafm = material(name + "_leaf", color=(0.35, 0.75, 0.2), rough=0.4)
        stem = material(name + "_stem", color=(0.3, 0.2, 0.1), rough=0.7)
    elif kind == "crown_p":
        leafm = material(name + "_leaf", color=(0.3, 0.6, 0.15), rough=0.5)
        stem = material(name + "_stem", color=(0.65, 0.2, 0.1), rough=0.5)
    elif name == "goldapple":
        leafm = material(name + "_leaf", color=(1.0, 0.8, 0.3), rough=0.2, metal=1.0)
        stem = material(name + "_stem", color=(0.8, 0.55, 0.15), rough=0.3, metal=1.0)
    else:
        leafm = material(name + "_leaf", color=(0.18, 0.55, 0.1), rough=0.45)
        stem = material(name + "_stem", color=(0.3, 0.18, 0.07), rough=0.75)
    return leafm, stem


# ------------------------------------------------------------------ build

def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.cameras, bpy.data.lights):
        for b in list(coll):
            coll.remove(b)


def build_fruit(name, d):
    R, H = d["R"], d["H"]
    fn, nu, nv = revolve(R, H, d["prof"], d.get("mod"), d.get("nu", 56), d.get("nv", 40), d.get("bend", 0.0))
    skin_img = save_img(name + "_skin", to_rgba8(d["skin"]()))
    emit = d.get("emit")
    skin = material(name + "_skin", skin_img, rough=d["rough"], metal=d.get("metal", 0.0),
                    emit=emit, emit_str=0.35 if emit else 0.0, coat=0.5)
    flesh = None
    if d["cut"] is not None:
        flesh_img = save_img(name + "_cut", to_rgba8(d["cut"]()))
        flesh = material(name + "_cut", flesh_img, rough=0.22, emit=emit, emit_str=0.2 if emit else 0.0)
    leafm, stem = acc_mats(name, d.get("acc"), emit)
    mats = [skin, flesh or skin, leafm, stem]

    def body_bm():
        bm = bmesh.new()
        param_body(bm, nu, nv, fn)
        return bm

    # whole
    bm = body_bm()
    if d.get("acc"):
        add_acc(bm, d["acc"], R, H)
    whole = mesh_obj(name + "_whole", bm, mats)
    out = {"whole": whole}
    info = {"radius": round(max(R * 1.05, H if d.get("bend", 0) == 0 else H * 0.75), 3), "R": R, "H": H,
            "juice": d["juice"], "points": d["points"], "special": d.get("special", "")}
    if d["cut"] is not None:
        offsets = {}
        for side in ("top", "bot"):
            bm = body_bm()
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, 0), plane_no=(0, 0, 1),
                                         clear_inner=(side == "top"), clear_outer=(side == "bot"))
            cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
            filled = bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)
            caps = filled["faces"]
            poked = bmesh.ops.poke(bm, faces=caps)
            cap_faces = poked["faces"]
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            uv = bm.loops.layers.uv.verify()
            rmax = max((v.co.xy.length for f in cap_faces for v in f.verts), default=R) * 1.0
            for f in cap_faces:
                f.material_index = 1
                f.smooth = False
                for l in f.loops:
                    l[uv].uv = (0.5 + l.vert.co.x / (2 * rmax), 0.5 + l.vert.co.y / (2 * rmax))
            if d.get("acc"):
                acc = bmesh.new()
                add_acc(acc, d["acc"], R, H)
                me_tmp = bpy.data.meshes.new("tmp")
                acc.to_mesh(me_tmp)
                acc.free()
                # keep only accessory islands on this side
                tmpbm = bmesh.new()
                tmpbm.from_mesh(me_tmp)
                islands = []
                seen = set()
                for f in tmpbm.faces:
                    if f.index in seen:
                        continue
                    stack, isl = [f], []
                    seen.add(f.index)
                    while stack:
                        g = stack.pop()
                        isl.append(g)
                        for e in g.edges:
                            for h in e.link_faces:
                                if h.index not in seen:
                                    seen.add(h.index)
                                    stack.append(h)
                    islands.append(isl)
                kill = []
                for isl in islands:
                    cz = sum(v.co.z for f in isl for v in f.verts) / sum(len(f.verts) for f in isl)
                    if (cz > 0) != (side == "top"):
                        kill.extend(isl)
                bmesh.ops.delete(tmpbm, geom=list(set(kill)), context="FACES")
                tmpbm.to_mesh(me_tmp)
                tmpbm.free()
                bm.from_mesh(me_tmp)
                bpy.data.meshes.remove(me_tmp)
            # recentre on body centroid
            vs = [v.co.copy() for v in bm.verts]
            c = sum(vs, Vector()) / len(vs)
            for v in bm.verts:
                v.co -= c
            ob = mesh_obj(name + "_" + side, bm, mats)
            out[side] = ob
            offsets[side] = [round(c.x, 4), round(c.z, 4), round(-c.y, 4)]  # Godot coords
        info["offsets"] = offsets
    return out, info


def export(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for k, ob in objs.items():
        ob.name = k
        ob.data.name = name + "_" + k
        ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_M, name + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_materials="EXPORT", export_image_format="AUTO")
    for k, ob in objs.items():
        ob.name = name + "_" + k


# ------------------------------------------------------------------ render

def setup_render(size=256):
    sc = bpy.context.scene
    try:
        sc.render.engine = "CYCLES"
    except TypeError:
        pass
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.render.resolution_x = size
    sc.render.resolution_y = size
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    world = bpy.data.worlds.new("w") if not sc.world else sc.world
    sc.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.55, 0.6, 0.75, 1)
    bg.inputs[1].default_value = 0.7
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
    key.data.energy = 220
    key.data.size = 1.5
    key.location = (1.6, -1.8, 2.2)
    key.rotation_euler = (math.radians(50), 0, math.radians(40))
    sc.collection.objects.link(key)
    rim = bpy.data.objects.new("rim", bpy.data.lights.new("rim", "AREA"))
    rim.data.energy = 160
    rim.data.size = 1.0
    rim.location = (-1.5, 1.8, 1.5)
    rim.rotation_euler = (math.radians(-55), 0, math.radians(-140))
    sc.collection.objects.link(rim)
    return cam


def frame(cam, objs, dist_scale=2.8):
    pts = []
    for ob in objs:
        pts += [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = (mn + mx) / 2
    r = (mx - mn).length / 2
    cam.data.lens = 50
    d = r * dist_scale
    direc = Vector((0.0, -1.0, 0.45)).normalized()
    cam.location = c + direc * d
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    names = [n for n in FRUITS if ONLY is None or n in ONLY]
    meta_path = os.path.join(ROOT, "assets", "models", "fruits.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) and ONLY else {}
    sheet = []
    for name in names:
        clear_scene()
        objs, info = build_fruit(name, FRUITS[name])
        meta[name] = info
        export(name, objs)
        print("built", name)
        if not NO_RENDER:
            cam = setup_render(256)
            for k, ob in objs.items():
                ob.hide_render = k != "whole"
            objs["whole"].rotation_euler = (math.radians(12), math.radians(-8), math.radians(25))
            frame(cam, [objs["whole"]], 2.9)
            icon = os.path.join(OUT_I, name + ".png")
            render(icon)
            sheet.append(icon)
            if "top" in objs:
                objs["whole"].hide_render = True
                objs["top"].hide_render = False
                objs["bot"].hide_render = False
                objs["top"].location = (0, 0, 0.18)
                objs["top"].rotation_euler = (math.radians(-35), 0, 0)
                objs["bot"].location = (0, 0, -0.1)
                objs["bot"].rotation_euler = (math.radians(30), 0, 0)
                frame(cam, [objs["top"], objs["bot"]], 2.3)
                p = os.path.join(OUT_R, "fruits", name + "_cut.png")
                os.makedirs(os.path.dirname(p), exist_ok=True)
                render(p)
                sheet.append(p)
    json.dump(meta, open(meta_path, "w"), indent=1)
    print("DONE", len(names))


main()
