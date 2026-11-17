import sys
from PIL import Image, ImageDraw, ImageFont
font_path, out_dir = sys.argv[1], sys.argv[2]
S = 1024
def tile(size):
    big = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.28), fill=(0x16, 0xA3, 0x4A, 255))
    f = ImageFont.truetype(font_path, int(S * 0.62))
    ch = chr(0xF055A)
    l, t, r, b = d.textbbox((0, 0), ch, font=f)
    d.text(((S - (r - l)) / 2 - l, (S - (b - t)) / 2 - t), ch, font=f, fill=(255, 255, 255, 255))
    return big.resize((size, size), Image.LANCZOS)
sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
imgs = [tile(s) for s in sizes]
imgs[-1].save(out_dir + '/app_icon.ico', sizes=[(s, s) for s in sizes], append_images=imgs[:-1])
tile(512).save(out_dir + '/icon_preview.png')
print('ok', tile(64).getbbox())
