#!/usr/bin/env python3
"""Build the launcher icon from the reference artwork.

The reference is a 1536x1536 render: a rounded-square icon on a white canvas
with a "豆包AI生成" watermark in the white margin BELOW the icon, so cropping
to the icon's blue bounds removes the watermark entirely (pixel-faithful).

The artwork is then inset into BOTH the legacy and the adaptive layers so the
launcher's icon mask cannot cut into the NPS, sitting on a background gradient
whose colours are sampled from the artwork's own border strips (so even if the
mask clips past the artwork edge, there is no visible seam).
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = "/Users/xubl/.workbuddy/clipboard-images/clipboard-2026-10-31T06-19-28-222Z-7db36180.jpg"
OUT = os.path.join(os.path.dirname(__file__), "out")
RES = "/Users/xubl/Haier/Test/Flutter/packet-sniffing/android/app/src/main/res"
os.makedirs(OUT, exist_ok=True)

INSET = 0.045      # trim the reference's own rim so it isn't an inner frame
SCALE = 0.57       # artwork size within the canvas (inside the safe zone)
RAMP = 0.10        # edge feather; must stay < the letters' own side margin


def main():
    im = Image.open(SRC).convert("RGB")
    a = np.asarray(im).astype(int)
    mask = (a[..., 2] - a[..., 0]) > 25          # blue icon, not white bg / gray watermark
    ys, xs = np.where(mask)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max(), ys.max()
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    crop = im.crop((x0 + int(cw * INSET), y0 + int(ch * INSET),
                    x0 + int(cw * (1 - INSET)), y0 + int(ch * (1 - INSET))))
    print("cropped:", crop.size)

    h, w = crop.size[1], crop.size[0]

    # blurred copy of the artwork = its smooth gradient field (letters removed).
    # Building the background by edge-extended inverse mapping of THIS field
    # guarantees it matches the artwork's own colours at the seam.
    blurred = crop.filter(ImageFilter.GaussianBlur(crop.size[0] * 0.06))
    bsrc = np.asarray(blurred).astype(np.uint8)

    def compose(size):
        gy, gx = np.mgrid[0:size, 0:size]
        # canvas -> artwork coords, inverse of the SCALE inset; outside is clamped
        mx = np.clip((((gx + 0.5) / size - 0.5) / SCALE + 0.5) * (w - 1), 0, w - 1).astype(int)
        my = np.clip((((gy + 0.5) / size - 0.5) / SCALE + 0.5) * (h - 1), 0, h - 1).astype(int)
        canvas = Image.fromarray(bsrc[my, mx]).convert("RGBA")

        s = int(size * SCALE)
        art = crop.resize((s, s), Image.LANCZOS).convert("RGBA")

        def feather(n):
            out = np.ones(n)
            r = int(n * RAMP)
            out[:r] = np.linspace(0, 1, r)
            out[-r:] = np.linspace(1, 0, r)
            return out

        fx, fy = feather(s), feather(s)
        art.putalpha(Image.fromarray((np.outer(fy, fx) * 255).astype(np.uint8)))
        canvas.alpha_composite(art, ((size - s) // 2, (size - s) // 2))
        return canvas

    base = compose(1024)
    base.save(os.path.join(OUT, "icon_master.png"))
    base.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icon_512.png"))
    print("master done", base.size)

    legacy = {"mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
              "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192}
    adaptive = {"mipmap-mdpi": 108, "mipmap-hdpi": 162, "mipmap-xhdpi": 216,
                "mipmap-xxhdpi": 324, "mipmap-xxxhdpi": 432}

    for folder, size in legacy.items():
        dst = os.path.join(RES, folder)
        os.makedirs(dst, exist_ok=True)
        p = base.resize((size, size), Image.LANCZOS)
        p.save(os.path.join(dst, "ic_launcher.png"))
        p.save(os.path.join(dst, "ic_launcher_round.png"))

    bg432 = Image.new("RGBA", (432, 432), tuple(int(c) for c in bsrc[4, 4]) + (255,))
    fg432 = compose(432)
    for folder, size in adaptive.items():
        dst = os.path.join(RES, folder)
        os.makedirs(dst, exist_ok=True)
        fg432.resize((size, size), Image.LANCZOS).save(os.path.join(dst, "ic_launcher_foreground.png"))
        bg432.resize((size, size), Image.LANCZOS).save(os.path.join(dst, "ic_launcher_background.png"))

    v26 = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(v26, exist_ok=True)
    with open(os.path.join(v26, "ic_launcher.xml"), "w") as f:
        f.write('<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')

    # previews simulating launcher masks, to confirm nothing important is cut
    for shape, box in (("circle", None), ("squircle", 0.22)):
        m = Image.new("L", (432, 432), 0)
        d = ImageDraw.Draw(m)
        if shape == "circle":
            d.ellipse([0, 0, 431, 431], fill=255)
        else:
            d.rounded_rectangle([0, 0, 431, 431], radius=int(432 * box), fill=255)
        prev = Image.new("RGBA", (432, 432), (255, 255, 255, 255))
        prev.paste(fg432, (0, 0), m)
        prev.save(os.path.join(OUT, "preview_%s.png" % shape))
    print("exports done")


if __name__ == "__main__":
    main()
