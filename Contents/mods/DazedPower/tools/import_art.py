"""Bring Blender renders (tools/blender/dp_render.py) into the mod: world cells into tools/art/<index>.png, icons
into tools/art/icons/<Item>.png, then rebuild the sheet with tools/build_sheet.py.

    python3 tools/import_art.py <dp_out folder>
A 2x render (256x512) is shrunk with premultiplied alpha and sharpened; a 2x2 piece is cut to its own square
by its <index>_m.png mask. Icons are trimmed and fitted to 32x32.
"""
import subprocess, sys
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter

HERE = Path(__file__).resolve().parent
ART = HERE / "art"
CW, CH = 128, 256


def shrink(im):
    """Halve a 2x render with premultiplied alpha (no dark fringes), then sharpen lightly."""
    small = im.convert("RGBa").resize((CW, CH), Image.LANCZOS)
    small = small.filter(ImageFilter.UnsharpMask(radius=0.8, percent=70, threshold=1))
    return small.convert("RGBA")


def cell(p):
    """A cell, cut to its own square by its mask when it has one, then shrunk to 128x256."""
    im = Image.open(p).convert("RGBA")
    m = p.with_name(p.stem + "_m.png")
    if m.exists():
        keep = Image.open(m).convert("RGBA").getchannel("R")
        im.putalpha(ImageChops.multiply(im.getchannel("A"), keep))
    if im.size != (CW, CH):
        im = shrink(im) if im.size == (CW * 2, CH * 2) else im.resize((CW, CH), Image.LANCZOS)
    return im


def icon(im):
    """Trim, shrink with premultiplied alpha to fit 30x30, sharpen a touch and centre on 32x32."""
    im = im.crop(im.getbbox()).convert("RGBa")
    im.thumbnail((30, 30), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=1)).convert("RGBA")
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    out.alpha_composite(im, ((32 - im.width) // 2, (32 - im.height) // 2))
    return out


def main(src):
    src = Path(src)
    ART.mkdir(exist_ok=True)
    (ART / "icons").mkdir(exist_ok=True)
    cells = icons = 0
    for fam in sorted(p for p in src.iterdir() if p.is_dir() and p.name not in ("preview",)):
        for p in sorted(fam.glob("*.png")):
            if p.stem.endswith("_m"):
                continue
            if fam.name == "icons":
                icon(Image.open(p).convert("RGBA")).save(ART / "icons" / p.name)
                icons += 1
            elif p.stem.isdigit():
                cell(p).save(ART / p.name)
                cells += 1
    print("%d cells, %d icons imported" % (cells, icons))
    subprocess.run([sys.executable, str(HERE / "build_sheet.py")], check=True)


if __name__ == "__main__":
    main(sys.argv[1])
