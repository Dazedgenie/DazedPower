"""Flat stand-ins for the charge board's Blender parts, same names and sizes (2x), so the board can be built and previewed
before the renders exist. python3 board_art_stub.py <media/ui/DazedPower/Board>"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
SS = 8   # drawn at 8x the 2x size, then shrunk


def part(name, w, h, draw):
    im = Image.new("RGBA", (w * 2 * SS, h * 2 * SS), (0, 0, 0, 0))
    draw(ImageDraw.Draw(im), 2 * SS)
    im.resize((w * 2, h * 2), Image.LANCZOS).save(OUT / (name + ".png"))


def ell(d, s, cx, cy, r, **kw): d.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s], **kw)
def rr(d, s, x0, y0, x1, y1, r, **kw): d.rounded_rectangle([x0 * s, y0 * s, x1 * s, y1 * s], r * s, **kw)


part("gauge_face", 176, 176, lambda d, s: (ell(d, s, 88, 88, 88, fill=(30, 30, 28)), ell(d, s, 88, 88, 82, fill=(238, 230, 208)),
                                          ell(d, s, 88, 88, 80, outline=(160, 150, 130), width=s)))
part("needle", 96, 16, lambda d, s: (d.polygon([(14 * s, 4.5 * s), (94 * s, 7.6 * s), (94 * s, 8.4 * s), (14 * s, 11.5 * s)], fill=(186, 38, 30)),
                                     rr(d, s, 2, 5, 16, 11, 2, fill=(186, 38, 30))))
part("hub", 20, 20, lambda d, s: (ell(d, s, 10, 10, 7.5, fill=(28, 28, 26)), ell(d, s, 8, 8, 2.5, fill=(90, 90, 86))))
part("battery_case", 60, 170, lambda d, s: (rr(d, s, 18, 0, 42, 12, 2, fill=(28, 28, 26)), rr(d, s, 1, 8, 59, 169, 6, fill=(38, 38, 36)),
                                            rr(d, s, 7, 16, 53, 161, 2, fill=(24, 24, 23))))
for up in (True, False):
    def tog(d, s, up=up):
        rr(d, s, 2, 2, 38, 54, 5, fill=(28, 28, 26))
        for y in (8, 48): ell(d, s, 20, y, 2.6, fill=(170, 170, 166))
        ell(d, s, 20, 28, 6, fill=(150, 150, 146))
        ty = 12 if up else 44
        d.line([(20 * s, 28 * s), (20 * s, ty * s)], fill=(210, 210, 206), width=5 * s)
        ell(d, s, 20, ty, 3.8, fill=(230, 230, 226))
    part("toggle_up" if up else "toggle_down", 40, 56, tog)
part("wheel", 22, 32, lambda d, s: (rr(d, s, 0, 0, 22, 32, 2, fill=(30, 30, 28)), d.rectangle([0, 15.5 * s, 22 * s, 16.5 * s], fill=(52, 52, 50))))
for on in (True, False):
    def iso(d, s, on=on):
        rr(d, s, 1, 1, 37, 51, 5, fill=(70, 72, 74))
        for y in (6, 46): ell(d, s, 19, y, 2.4, fill=(170, 170, 166))
        rr(d, s, 10, 19, 28, 33, 3, fill=(28, 28, 26))
        ty = 8 if on else 44
        d.line([(19 * s, 26 * s), (19 * s, ty * s)], fill=(192, 46, 36), width=7 * s)
        ell(d, s, 19, ty, 5.2, fill=(210, 60, 46))
    part("isolator_on" if on else "isolator_off", 38, 52, iso)
for kind, col in (("green", (92, 200, 84)), ("amber", (240, 170, 50)), ("red", (226, 60, 48)), ("off", (44, 42, 38))):
    part("lamp_" + kind, 24, 24, lambda d, s, col=col: (ell(d, s, 12, 12, 11.5, fill=(180, 180, 176)), ell(d, s, 12, 12, 9.5, fill=col)))
print("stubs in", OUT)
