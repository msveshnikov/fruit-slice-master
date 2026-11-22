"""contact sheet: python tools/sheet.py out.png cols cell img1 img2 ..."""
import sys
from PIL import Image
out, cols, cell = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
files = sys.argv[4:]
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cell, rows * cell), (70, 75, 95))
for i, f in enumerate(files):
    im = Image.open(f).convert("RGBA")
    im.thumbnail((cell, cell))
    sheet.paste(im, ((i % cols) * cell, (i // cols) * cell), im)
sheet.save(out)
