"""Google Play store graphics -> renders/play/.

1. raw shots (game, 1080x1920, HUD hidden):
   G --path . --resolution 1080x1920 -- --storeshots --lang en|ru --size 1080x1920   -> renders/game/s*.png
   (copy them to renders/play/raw/<lang>_<name>.png)
2. python tools/play_store.py
   {en,ru}_N.png             phone screenshots with captions
   feature_{en,ru}_1024x500.png
   icon_512.png
"""
import glob, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "renders", "play")
RAW = os.path.join(OUT, "raw")
TITLE = os.path.join(ROOT, "assets", "fonts", "Lobster.ttf")
BODY = os.path.join(ROOT, "assets", "fonts", "Nunito.ttf")

CAPTIONS = {
    "en": {"s1_title": "Slice juicy 3D fruit!", "s2_combo": "Chain huge combos", "s3_freeze": "Freeze time with frost berries",
           "s4_boss": "Defeat giant boss fruit", "s5_market": "6 painted worlds", "s6_frenzy": "Frenzy, double points & more",
           "s7_levels": "120 levels to master", "s8_blades": "Unlock 8 glowing blades"},
    "ru": {"s1_title": "Режь сочные 3D-фрукты!", "s2_combo": "Огромные комбо", "s3_freeze": "Замораживай время",
           "s4_boss": "Победи гигантских боссов", "s5_market": "6 живописных миров", "s6_frenzy": "Фруктопад и двойные очки",
           "s7_levels": "120 уровней", "s8_blades": "8 светящихся клинков"},
}
BOTTOM = {"s1_title", "s2_combo", "s3_freeze", "s4_boss", "s5_market", "s6_frenzy", "s7_levels", "s8_blades"}
ORDER = ["s2_combo", "s4_boss", "s3_freeze", "s5_market", "s6_frenzy", "s1_title", "s7_levels", "s8_blades"]


def body_font(size):
    f = ImageFont.truetype(BODY, size)
    try:
        f.set_variation_by_axes([850])
    except Exception:
        pass
    return f


def fit_font(text, path, size, max_w):
    while size > 30:
        f = ImageFont.truetype(path, size)
        if f.getlength(text) <= max_w:
            return f
        size -= 4
    return ImageFont.truetype(path, size)


def caption(lang, name):
    im = Image.open(os.path.join(RAW, f"{lang}_{name}.png")).convert("RGB")
    w, h = im.size
    band = 420
    top = name not in BOTTOM
    grad = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(grad)
    for y in range(band):
        a = int(215 * (1 - y / band) ** 1.3)
        yy = y if top else h - 1 - y
        d.line([(0, yy), (w, yy)], fill=a)
    im = Image.composite(Image.new("RGB", (w, h), (28, 8, 4)), im, grad)
    d = ImageDraw.Draw(im)
    text = CAPTIONS[lang][name]
    f = fit_font(text, TITLE, 118, w - 90)
    tw = f.getlength(text)
    y = 70 if top else h - 230
    d.text(((w - tw) / 2, y), text, font=f, fill=(255, 214, 90), stroke_width=9, stroke_fill=(70, 18, 6))
    return im


def feature(lang):
    w, h = 1024, 500
    bg = Image.open(os.path.join(ROOT, "concept", "worlds", "title_bg.png")).convert("RGB")
    s = bg.width / w
    bg = bg.resize((w, round(bg.height / s)), Image.LANCZOS)
    top = int(bg.height * 0.42) - h // 2
    bg = bg.crop((0, top, w, top + h))
    shade = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shade).rectangle((380, 0, w, h), fill=120)
    shade = shade.filter(ImageFilter.GaussianBlur(70))
    bg = Image.composite(Image.new("RGB", (w, h), (40, 10, 6)), bg, shade)
    ic = Image.open(os.path.join(ROOT, "concept", "ui", "icon_chatgpt.png")).convert("RGB").resize((330, 330), Image.LANCZOS)
    m = Image.new("L", ic.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, 329, 329), 66, fill=255)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle((40, 70, 400, 430), 80, fill=(255, 190, 70, 170))
    glow = glow.filter(ImageFilter.GaussianBlur(30))
    bg = bg.convert("RGBA")
    bg.alpha_composite(glow)
    bg = bg.convert("RGB")
    bg.paste(ic, (55, 85), m)
    d = ImageDraw.Draw(bg)
    title = ["Fruit Slice", "Master"] if lang == "en" else ["Мастер", "нарезки"]
    ft = ImageFont.truetype(TITLE, 100)
    y = 48
    for line in title:
        d.text((430, y), line, font=ft, fill=(255, 220, 100), stroke_width=7, stroke_fill=(80, 20, 6))
        y += 112
    sub = "Slice juicy 3D fruit!" if lang == "en" else "Режь сочные 3D-фрукты!"
    d.text((436, 292), sub, font=body_font(38), fill=(255, 246, 230), stroke_width=4, stroke_fill=(60, 14, 4))
    sub2 = "120 levels · 6 worlds · boss fruit" if lang == "en" else "120 уровней · 6 миров · боссы"
    d.text((436, 352), sub2, font=body_font(30), fill=(255, 200, 80), stroke_width=3, stroke_fill=(60, 14, 4))
    bg.save(os.path.join(OUT, f"feature_{lang}_1024x500.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    Image.open(os.path.join(ROOT, "assets", "ui", "icon_512.png")).convert("RGB").save(os.path.join(OUT, "icon_512.png"))
    for lang in ("en", "ru"):
        feature(lang)
        for i, name in enumerate(ORDER):
            if os.path.exists(os.path.join(RAW, f"{lang}_{name}.png")):
                caption(lang, name).save(os.path.join(OUT, f"{lang}_{i + 1}.png"))
    print("ok", sorted(os.path.basename(p) for p in glob.glob(os.path.join(OUT, "*.png"))))
