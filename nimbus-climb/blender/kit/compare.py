"""Side-by-side sheets (system python3 + Pillow): today's Part build (tools/render_model.py) next to the Blender kit.

    python3 compare.py OUT.png "label A" a.png "label B" b.png [...]
"""
import sys

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main():
    out = sys.argv[1]
    items = list(zip(sys.argv[2::2], sys.argv[3::2]))
    H = 620
    ims = []
    for label, path in items:
        im = Image.open(path).convert("RGB")
        im = im.resize((int(im.width * H / im.height), H), Image.LANCZOS)
        ims.append((label, im))
    W = sum(im.width for _, im in ims) + 12 * (len(ims) + 1)
    sheet = Image.new("RGB", (W, H + 56), (236, 240, 248))
    d = ImageDraw.Draw(sheet)
    x = 12
    for label, im in ims:
        sheet.paste(im, (x, 48))
        d.text((x + 4, 12), label, fill=(40, 52, 78), font=font(22))
        x += im.width + 12
    sheet.save(out)
    print("wrote", out, sheet.size)


if __name__ == "__main__":
    main()
