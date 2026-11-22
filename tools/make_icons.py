"""App icons from concept/ui/icon_chatgpt.png -> assets/ui/icon*.png, icon.ico, Android adaptive layers."""
from PIL import Image, ImageDraw
src = Image.open("concept/ui/icon_chatgpt.png").convert("RGB")
w, h = src.size
s = min(w, h)
src = src.crop(((w - s) // 2, (h - s) // 2, (w + s) // 2, (h + s) // 2))


def rounded(img, r):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.size[0] - 1, img.size[1] - 1), r, fill=255)
    out = img.convert("RGBA")
    out.putalpha(m)
    return out


for n in (512, 256, 192):
    im = src.resize((n, n), Image.LANCZOS)
    (rounded(im, n // 5) if n != 192 else im).save(f"assets/ui/icon{'' if n == 256 else '_' + str(n)}.png")
rounded(src.resize((256, 256), Image.LANCZOS), 50).save("assets/ui/icon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
# adaptive: foreground = full art scaled into the 66% safe zone over a matching background
bg = src.resize((432, 432), Image.LANCZOS).crop((0, 0, 432, 432))
bg = bg.resize((8, 8), Image.BILINEAR).resize((432, 432), Image.BICUBIC)
bg.save("assets/ui/adaptive_bg_432.png")
fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
art = rounded(src.resize((300, 300), Image.LANCZOS), 60)
fg.paste(art, (66, 66), art)
fg.save("assets/ui/adaptive_fg_432.png")
# splash
sp = rounded(src.resize((300, 300), Image.LANCZOS), 60)
sp.save("assets/ui/splash.png")
print("ok")
