"""DazedPower interface art in the new style: monitor parts, white menu glyphs, the almanac sidebar and radial icons.

    python3 ui_art.py <out dir> [almanac book render]
Everything is drawn at 8x and shrunk, so edges come out soft like the game's own UI.
"""
import math, sys, random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont

OUT = Path(sys.argv[1]); BOOK = Path(sys.argv[2]) if len(sys.argv) > 2 else None
UI = OUT / "ui/DazedPower"; MENU = UI / "Menu"; SIDE = UI / "Sidebar"
SS = 8


def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def down(im, w, h):
    return im.resize((w, h), Image.LANCZOS)


def rgba(hexcol, a=255):
    h = hexcol.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def vgrad(w, h, top, bot):
    """A vertical gradient strip from colour `top` to `bot`."""
    g = Image.new("RGBA", (w, h))
    t, b = rgba(top), rgba(bot)
    for y in range(h):
        k = y / max(1, h - 1)
        ImageDraw.Draw(g).line([(0, y), (w, y)], fill=tuple(int(t[i] * (1 - k) + b[i] * k) for i in range(4)))
    return g


def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), r, fill=255); return m


def noise_layer(w, h, amt, seed=1):
    """Fine grain, so flat paint reads as a real surface."""
    r = random.Random(seed); im = Image.new("L", (w, h), 128); px = im.load()
    for y in range(h):
        for x in range(w): px[x, y] = 128 + r.randint(-amt, amt)
    return im.filter(ImageFilter.GaussianBlur(0.6))


def grain(im, amt=10, seed=1):
    n = noise_layer(im.width, im.height, amt, seed)
    rgb = Image.merge("RGB", [ImageChops.add(c, n, 1, -128) for c in im.convert("RGB").split()])
    out = rgb.convert("RGBA"); out.putalpha(im.getchannel("A")); return out


# ------------------------------------------------------------------ monitor parts
def key(lit):
    w, h = 84, 30; W, H = w * SS, h * SS
    base = vgrad(W, H, "#34373d" if not lit else "#3d4a3f", "#1c1e22" if not lit else "#25302a")
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); im.paste(base, (0, 0), rounded_mask(W, H, 5 * SS))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((SS, SS, W - SS, H - SS), 4 * SS, outline=rgba("#4b4f57" if not lit else "#5d7a5d", 200), width=SS)
    d.line([(6 * SS, 2 * SS), (W - 6 * SS, 2 * SS)], fill=rgba("#6a6f78" if not lit else "#86b07c", 150), width=SS)
    if lit:
        glow = Image.new("L", (W, H), 0); ImageDraw.Draw(glow).rounded_rectangle((6 * SS, H - 7 * SS, W - 6 * SS, H - 4 * SS), 2 * SS, fill=170)
        im.alpha_composite(Image.merge("RGBA", (Image.new("L", (W, H), 150), Image.new("L", (W, H), 230), Image.new("L", (W, H), 120),
                                                  glow.filter(ImageFilter.GaussianBlur(3 * SS)))))
    return grain(down(im, w, h), 5, 3 if lit else 2)


def led(col):
    s = 21; S = s * SS; im = canvas(s, s); d = ImageDraw.Draw(im)
    d.ellipse((0, 0, S - 1, S - 1), fill=rgba("#121316"))
    d.ellipse((SS, SS, S - SS, S - SS), fill=rgba("#3a3d43"))
    d.ellipse((3 * SS, 3 * SS, S - 3 * SS, S - 3 * SS), fill=rgba("#0d0e10"))
    lens = {"g": ("#7ef07a", "#1f7a2c"), "a": ("#ffcf5a", "#a8631a"), "r": ("#ff6a5a", "#8e1d17"), "off": ("#3c4440", "#141816")}[col]
    core = Image.new("RGBA", (S, S), (0, 0, 0, 0)); cd = ImageDraw.Draw(core)
    for k in range(40):
        t = k / 39; r0 = (S / 2 - 4 * SS) * (1 - t)
        c0, c1 = rgba(lens[1]), rgba(lens[0])
        if r0 < 2: break
        cd.ellipse((S / 2 - r0 + t * SS * 0.5, S / 2 - r0 + t * SS * 0.5, S / 2 + r0, S / 2 + r0), fill=tuple(int(c0[i] * (1 - t) + c1[i] * t) for i in range(4)))
    im.alpha_composite(core)
    ImageDraw.Draw(im).ellipse((6 * SS, 5 * SS, 10 * SS, 8 * SS), fill=(255, 255, 255, 120 if col != "off" else 50))
    if col != "off":
        halo = Image.new("L", (S, S), 0); ImageDraw.Draw(halo).ellipse((2 * SS, 2 * SS, S - 2 * SS, S - 2 * SS), fill=90)
        c = rgba(lens[0])
        im.alpha_composite(Image.merge("RGBA", [Image.new("L", (S, S), c[i]) for i in range(3)] + [halo.filter(ImageFilter.GaussianBlur(2 * SS))]))
    return down(im, s, s)


SEG = {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg"}


def digit(ch):
    """A white seven-segment figure, slightly slanted; the window tints it."""
    w, h = 26, 44; W, H = w * SS, h * SS; im = Image.new("L", (W, H), 0); d = ImageDraw.Draw(im)
    t = 4.2 * SS; L, R, T, B, Mid = 4 * SS, W - 4 * SS, 3 * SS, H - 3 * SS, H / 2
    g = 0.8 * SS

    def hseg(y):
        d.polygon([(L + g + t / 2, y), (L + g + t, y - t / 2), (R - g - t, y - t / 2), (R - g - t / 2, y), (R - g - t, y + t / 2), (L + g + t, y + t / 2)], fill=255)

    def vseg(x, y0, y1):
        d.polygon([(x, y0 + g + t / 2), (x + t / 2, y0 + g + t), (x + t / 2, y1 - g - t), (x, y1 - g - t / 2), (x - t / 2, y1 - g - t), (x - t / 2, y0 + g + t)], fill=255)
    segs = {"a": lambda: hseg(T + t / 2), "g": lambda: hseg(Mid), "d": lambda: hseg(B - t / 2),
            "f": lambda: vseg(L + t / 2, T, Mid), "b": lambda: vseg(R - t / 2, T, Mid),
            "e": lambda: vseg(L + t / 2, Mid, B), "c": lambda: vseg(R - t / 2, Mid, B)}
    for s in SEG[ch]: segs[s]()
    im = im.transform(im.size, Image.AFFINE, (1, 0.12, -0.12 * H / 2, 0, 1, 0), Image.BICUBIC)
    out = Image.new("RGBA", (W, H), (255, 255, 255, 0)); out.putalpha(im)
    return down(out, w, h)


def lcd_overlay():
    """Glass over the screen: a soft inner shadow, a diagonal glare and faint pixel lines."""
    w, h = 372, 252; im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh = Image.new("L", (w, h), 0); ImageDraw.Draw(sh).rectangle((0, 0, w - 1, h - 1), outline=170, width=10)
    im.alpha_composite(Image.merge("RGBA", (Image.new("L", (w, h), 0),) * 3 + (sh.filter(ImageFilter.GaussianBlur(8)),)))
    gl = Image.new("L", (w, h), 0); ImageDraw.Draw(gl).polygon([(0, 0), (w * 0.55, 0), (w * 0.25, h * 0.55), (0, h * 0.75)], fill=26)
    im.alpha_composite(Image.merge("RGBA", (Image.new("L", (w, h), 230),) * 3 + (gl.filter(ImageFilter.GaussianBlur(14)),)))
    lines = Image.new("L", (w, h), 0); ld = ImageDraw.Draw(lines)
    for y in range(0, h, 3): ld.line([(0, y), (w, y)], fill=10)
    im.alpha_composite(Image.merge("RGBA", (Image.new("L", (w, h), 0),) * 3 + (lines,)))
    return im


def screw():
    s = 14; S = s * SS; im = canvas(s, s); d = ImageDraw.Draw(im)
    d.ellipse((0, 0, S - 1, S - 1), fill=rgba("#16171a"))
    for k in range(30):
        t = k / 29; r = (S / 2 - SS) * (1 - t * 0.85); c0, c1 = rgba("#5d6168"), rgba("#b9bdc3")
        d.ellipse((S / 2 - r - t * SS * 0.5, S / 2 - r - t * SS * 0.5, S / 2 + r - t * SS * 0.5, S / 2 + r - t * SS * 0.5), fill=tuple(int(c0[i] * (1 - t) + c1[i] * t) for i in range(4)))
    for a in (35, 125):
        x, y = math.cos(math.radians(a)) * S * 0.3, math.sin(math.radians(a)) * S * 0.3
        d.line([(S / 2 - x, S / 2 - y), (S / 2 + x, S / 2 + y)], fill=rgba("#2a2c30"), width=int(1.6 * SS))
    return down(im, s, s)


def sticker():
    w, h = 116, 34; W, H = w * SS, h * SS; im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh = Image.new("L", (W, H), 0); ImageDraw.Draw(sh).rectangle((2 * SS, 2 * SS, W - SS, H - SS), fill=120)
    im.alpha_composite(Image.merge("RGBA", (Image.new("L", (W, H), 0),) * 3 + (sh.filter(ImageFilter.GaussianBlur(2 * SS)),)))
    paper = vgrad(W - 3 * SS, H - 3 * SS, "#e9e2cc", "#d8cfb4")
    m = Image.new("L", paper.size, 255); md = ImageDraw.Draw(m)
    md.polygon([(paper.width - 6 * SS, 0), (paper.width, 0), (paper.width, 6 * SS)], fill=0)
    im.paste(paper, (SS, SS), m)
    d = ImageDraw.Draw(im)
    d.polygon([(W - 2 * SS - 6 * SS, SS), (W - 2 * SS, SS + 6 * SS), (W - 2 * SS - 6 * SS, SS + 6 * SS)], fill=rgba("#b9ae90"))
    d.rectangle((SS, H - 5 * SS, W - 3 * SS, H - 2 * SS), fill=rgba("#d1a83a"))
    return grain(down(im, w, h), 8, 7)


def plate(on):
    """The pale isolator plate with a red rotary handle on a yellow collar: across for off, upright for on."""
    w, h = 116, 112; W, H = w * SS, h * SS; im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    body = vgrad(W, H, "#d9d4c4", "#bfb9a7"); im.paste(body, (0, 0), rounded_mask(W, H, 6 * SS))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((SS, SS, W - SS, H - SS), 6 * SS, outline=rgba("#8f8a7b"), width=SS)
    for x, y in ((8, 8), (w - 8, 8), (8, h - 8), (w - 8, h - 8)):
        sc = screw().resize((9 * SS, 9 * SS), Image.LANCZOS); im.alpha_composite(sc, (int(x * SS - 4.5 * SS), int(y * SS - 4.5 * SS)))
    cx, cy = W / 2, H * 0.52
    d.ellipse((cx - 34 * SS, cy - 34 * SS, cx + 34 * SS, cy + 34 * SS), fill=rgba("#d6a92c"), outline=rgba("#8a6a1a"), width=SS)
    d.ellipse((cx - 22 * SS, cy - 22 * SS, cx + 22 * SS, cy + 22 * SS), fill=rgba("#2a2b2e"))
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 9 * SS)
    d.text((cx - 41 * SS, cy - 5 * SS), "0", font=f, fill=rgba("#2a2b2e")); d.text((cx - 3 * SS, cy - 46 * SS), "I", font=f, fill=rgba("#2a2b2e"))
    handle = Image.new("RGBA", (W, H), (0, 0, 0, 0)); hd = ImageDraw.Draw(handle)
    hd.rounded_rectangle((cx - 30 * SS, cy - 7 * SS, cx + 30 * SS, cy + 7 * SS), 6 * SS, fill=rgba("#b8302a"))
    hd.rounded_rectangle((cx - 28 * SS, cy - 6 * SS, cx + 28 * SS, cy - 1 * SS), 5 * SS, fill=rgba("#d4483a"))
    hd.ellipse((cx - 9 * SS, cy - 9 * SS, cx + 9 * SS, cy + 9 * SS), fill=rgba("#9c2620"))
    if on: handle = handle.rotate(90, center=(cx, cy), resample=Image.BICUBIC)
    shadow = Image.merge("RGBA", (Image.new("L", (W, H), 0),) * 3 + (handle.getchannel("A").point(lambda v: v * 0.5),)).filter(ImageFilter.GaussianBlur(2 * SS))
    im.alpha_composite(shadow, (2 * SS, 3 * SS)); im.alpha_composite(handle)
    return grain(down(im, w, h), 6, 11 if on else 12)


def toggle(on):
    s = 44; S = s * SS; im = canvas(s, s); d = ImageDraw.Draw(im)
    d.rounded_rectangle((6 * SS, 2 * SS, S - 6 * SS, S - 2 * SS), 5 * SS, fill=rgba("#2a2c30"), outline=rgba("#4b4f57"), width=SS)
    d.rounded_rectangle((14 * SS, 7 * SS, S - 14 * SS, S - 7 * SS), 3 * SS, fill=rgba("#121316"))
    y0 = 9 * SS if on else S / 2 + 1 * SS
    d.rounded_rectangle((15 * SS, y0, S - 15 * SS, y0 + 12 * SS), 3 * SS, fill=rgba("#c9ccd0"))
    d.line([(16 * SS, y0 + 2 * SS), (S - 16 * SS, y0 + 2 * SS)], fill=rgba("#f0f2f4"), width=SS)
    return down(im, s, s)


# ------------------------------------------------------------------ white menu glyphs (24-unit grid)
class G:
    """Draws on a 24-unit grid at high resolution with round-capped strokes."""

    def __init__(self, n=24, px=384, sw=2.3):
        self.u = px / n; self.im = Image.new("L", (px, px), 0); self.d = ImageDraw.Draw(self.im); self.sw = sw

    def P(self, x, y): return (x * self.u, y * self.u)

    def line(self, *pts, w=None, fill=255):
        w = (w or self.sw) * self.u; ps = [self.P(*p) for p in pts]
        self.d.line(ps, fill=fill, width=int(w), joint="curve")
        for p in (ps[0], ps[-1]): self.d.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=fill)

    def poly(self, *pts, fill=255): self.d.polygon([self.P(*p) for p in pts], fill=fill)

    def rect(self, x0, y0, x1, y1, r=1.5, fill=None, w=None, outline=255):
        b = (*self.P(x0, y0), *self.P(x1, y1))
        if fill is not None: self.d.rounded_rectangle(b, r * self.u, fill=fill)
        else: self.d.rounded_rectangle(b, r * self.u, outline=outline, width=int((w or self.sw) * self.u))

    def circle(self, cx, cy, r, fill=None, w=None, outline=255):
        b = (*self.P(cx - r, cy - r), *self.P(cx + r, cy + r))
        if fill is not None: self.d.ellipse(b, fill=fill)
        else: self.d.ellipse(b, outline=outline, width=int((w or self.sw) * self.u))

    def arc(self, cx, cy, r, a0, a1, w=None, fill=255):
        b = (*self.P(cx - r, cy - r), *self.P(cx + r, cy + r)); self.d.arc(b, a0, a1, fill=fill, width=int((w or self.sw) * self.u))

    def slash(self):
        self.line((3, 3), (21, 21), w=self.sw + 2.6, fill=0); self.line((3, 3), (21, 21))

    def out(self):
        a = self.im; im = Image.new("RGBA", a.size, (255, 255, 255, 0)); im.putalpha(a); return im


def bolt(g, x, y, s=1.0, fill=255):
    pts = [(1.5, 0), (-2.2, 5), (0, 5), (-1.4, 10), (2.6, 4), (0.4, 4), (1.6, 0)]
    g.poly(*[(x + px * s, y + py * s) for px, py in pts], fill=fill)


def house(g):
    g.line((3.5, 11.5), (12, 4), (20.5, 11.5)); g.line((6, 10), (6, 20), (18, 20), (18, 10))


def battery_h(g):
    g.rect(3, 7.5, 19, 16.5, r=2); g.rect(19, 10, 21.5, 14, r=0.8, fill=255)


def plug_body(g, x=0, y=0):
    g.line((9 + x, 3 + y), (9 + x, 7 + y)); g.line((15 + x, 3 + y), (15 + x, 7 + y))
    g.rect(6 + x, 7 + y, 18 + x, 12 + y, r=1.5, fill=255); g.poly((7 + x, 12 + y), (17 + x, 12 + y), (14 + x, 16 + y), (10 + x, 16 + y))
    g.line((12 + x, 16 + y), (12 + x, 21 + y))


GLYPHS = {}


def glyph(name):
    def reg(fn): GLYPHS[name] = fn; return fn
    return reg


@glyph("solar-panel")
def _(g):
    g.poly((5, 4), (21, 4), (19, 15), (3, 15), fill=255)
    for x in (9.3, 13.7): g.line((x + 0.9, 4.6), (x - 1.1, 14.4), w=1.1, fill=0)
    g.line((4.3, 9.5), (20.1, 9.5), w=1.1, fill=0)
    g.line((11, 15), (11, 20)); g.line((7, 20.5), (15, 20.5))


@glyph("info-circle")
def _(g):
    g.circle(12, 12, 9); g.line((12, 11), (12, 16.5)); g.circle(12, 7.6, 1.4, fill=255)


@glyph("device-desktop-analytics")
def _(g):
    g.rect(3, 4, 21, 16, r=1.8); g.line((9, 20.5), (15, 20.5)); g.line((12, 16), (12, 20.5))
    g.line((8, 12.5), (8, 10.5)); g.line((12, 12.5), (12, 8)); g.line((16, 12.5), (16, 9.5))


@glyph("book-2")
def _(g):
    g.rect(5, 3, 19.5, 21, r=1.5); g.line((8.5, 3.5), (8.5, 20.5)); g.line((11.5, 8), (16.5, 8)); g.circle(14, 14, 2.2, fill=255)


@glyph("cloud")
def _(g):
    g.circle(9, 13, 4.6, fill=255); g.circle(14.5, 10.5, 5.6, fill=255); g.circle(18.5, 14.5, 3.4, fill=255)
    g.rect(6, 13, 20, 18, r=2.5, fill=255)
    g.circle(9, 13, 2.5, fill=0); g.circle(14.5, 10.5, 3.4, fill=0); g.circle(18.5, 14.5, 1.3, fill=0); g.rect(8.3, 12.5, 18.6, 15.8, r=1.2, fill=0)


@glyph("radar-2")
def _(g):
    g.circle(12, 12, 1.8, fill=255); g.arc(12, 12, 5.5, 200, 520); g.arc(12, 12, 9.2, 220, 500); g.line((12, 12), (19, 5))


@glyph("radar-off")
def _(g):
    GLYPHS["radar-2"](g); g.slash()


@glyph("home-bolt")
def _(g):
    house(g); bolt(g, 11.6, 10.3, 0.85)


@glyph("building-community")
def _(g):
    g.line((3, 20.5), (21, 20.5)); g.rect(4.5, 9, 11.5, 20.5, r=0.8); g.rect(12.5, 4, 19.5, 20.5, r=0.8)
    for y in (12, 15.5): g.line((7.5, y), (8.5, y), w=1.6)
    for y in (8, 11.5, 15): g.line((15.5, y), (16.5, y), w=1.6)


@glyph("home-off")
def _(g):
    house(g); g.slash()


@glyph("power")
def _(g):
    g.arc(12, 13, 8, 300, 600); g.line((12, 3), (12, 11))


@glyph("refresh")
def _(g):
    g.arc(12, 12, 7.5, 200, 340); g.arc(12, 12, 7.5, 20, 160)
    g.poly((19.8, 6), (20.8, 11.5), (15.4, 10.4)); g.poly((4.2, 18), (3.2, 12.5), (8.6, 13.6))


@glyph("battery-automotive")
def _(g):
    g.rect(3, 7, 21, 19.5, r=1.6); g.rect(5.5, 4.5, 9, 7, r=0.6, fill=255); g.rect(15, 4.5, 18.5, 7, r=0.6, fill=255)
    g.line((6, 12.5), (9, 12.5), w=1.8); g.line((15, 12.5), (18, 12.5), w=1.8); g.line((16.5, 11), (16.5, 14), w=1.8)


@glyph("battery-charging-2")
def _(g):
    battery_h(g); bolt(g, 10.8, 7.2, 0.95)


@glyph("battery-off")
def _(g):
    battery_h(g); g.slash()


@glyph("plug")
def _(g):
    plug_body(g)


@glyph("plug-connected")
def _(g):
    plug_body(g, 0, -1.2); g.rect(5, 18.5, 19, 22, r=1, fill=255)


@glyph("plug-x")
def _(g):
    plug_body(g, -2.5, 0); g.line((15.5, 15), (20.5, 20), w=2.0); g.line((20.5, 15), (15.5, 20), w=2.0)


@glyph("scissors")
def _(g):
    g.circle(6.5, 17.5, 3); g.circle(17.5, 17.5, 3); g.line((8.5, 15.3), (17.5, 3.5)); g.line((15.5, 15.3), (6.5, 3.5))


@glyph("snowflake")
def _(g):
    for a in (90, 30, 150):
        dx, dy = math.cos(math.radians(a)) * 9, math.sin(math.radians(a)) * 9
        g.line((12 - dx, 12 - dy), (12 + dx, 12 + dy), w=2.0)
        for s in (1, -1):
            bx, by = 12 + s * dx * 0.62, 12 + s * dy * 0.62
            for t in (35, -35):
                b = math.radians(a + (0 if s > 0 else 180) + 180 + t)
                g.line((bx, by), (bx - math.cos(b) * -3, by - math.sin(b) * -3), w=1.7)


@glyph("tool")
def _(g):
    g.line((6, 18), (14, 10), w=3.2); g.circle(16, 8, 4.4, fill=255); g.poly((16, 8), (22, 5.5), (19, 2.5), fill=0)
    g.circle(16, 8, 1.4, fill=0); g.circle(5.5, 18.5, 1.0, fill=0)


@glyph("droplet")
def _(g):
    g.poly((12, 3), (18.2, 12.5), (5.8, 12.5), fill=255); g.circle(12, 14.5, 6.3, fill=255)
    g.poly((12, 6.6), (15.7, 12.4), (8.3, 12.4), fill=0); g.circle(12, 14.5, 4.0, fill=0)
    g.arc(12, 14.5, 2.6, 100, 170, w=1.4)


@glyph("hand-grab")
def _(g):
    for x, top in ((7.5, 6.5), (10.5, 5), (13.5, 5), (16.5, 6.5)): g.rect(x - 1.25, top, x + 1.25, 13, r=1.25, fill=255)
    g.rect(6.2, 10.5, 18.6, 19.5, r=3.5, fill=255); g.line((6, 14), (3.8, 10.8), w=2.6)
    for x in (9, 12, 15): g.line((x, 11), (x, 12.6), w=0.9, fill=0)


def glyph_image(name, size):
    g = G(); GLYPHS[name](g); im = g.out().resize((size, size), Image.LANCZOS)
    if size <= 20:
        a = im.getchannel("A").filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=0)); im.putalpha(a)
    return im


def almanac_glyph(w, h, colour=(236, 233, 224)):
    """The sidebar's almanac: a book with a sun on its cover, off-white with a dark rim like the base game's buttons."""
    g = G(n=24, px=480, sw=2.0); d = g.d
    g.rect(4.5, 4, 19.5, 20.5, r=1.6, fill=255); g.rect(5.7, 5.2, 18.3, 19.3, r=1.0, fill=0)
    g.rect(4.5, 4, 8.3, 20.5, r=1.4, fill=255)
    g.circle(13.8, 11.5, 2.4, fill=255)
    for k in range(8):
        a = k * math.pi / 4; g.line((13.8 + math.cos(a) * 3.6, 11.5 + math.sin(a) * 3.6), (13.8 + math.cos(a) * 4.8, 11.5 + math.sin(a) * 4.8), w=1.1)
    g.line((10.5, 17.3), (17, 17.3), w=1.3)
    a = g.im
    rim = a.filter(ImageFilter.MaxFilter(13))
    out = Image.new("RGBA", a.size, (0, 0, 0, 0))
    out.paste((20, 20, 22, 170), (0, 0), rim); out.paste(colour + (255,), (0, 0), a)
    sq = out.resize((h, h), Image.LANCZOS)
    full = Image.new("RGBA", (w, h), (0, 0, 0, 0)); full.alpha_composite(sq, ((w - h) // 2, 0))
    return full


def main():
    UI.mkdir(parents=True, exist_ok=True)
    key(False).save(UI / "key_norm.png"); key(True).save(UI / "key_lit.png")
    for c in ("g", "a", "r", "off"): led(c).save(UI / ("led_%s.png" % c))
    for ch in "0123456789": digit(ch).save(UI / ("num_%s.png" % ch))
    lcd_overlay().save(UI / "lcd_overlay.png"); screw().save(UI / "screw.png"); sticker().save(UI / "sticker.png")
    plate(False).save(UI / "plate_off.png"); plate(True).save(UI / "plate_on.png")
    toggle(False).save(UI / "switch_off.png"); toggle(True).save(UI / "switch_on.png")
    for size in (16, 20, 24, 32, 48):
        (MENU / str(size)).mkdir(parents=True, exist_ok=True)
        for name in GLYPHS: glyph_image(name, size).save(MENU / str(size) / (name + ".png"))
    for w in (48, 64, 80, 96, 128):
        h = w * 3 // 4; (SIDE / str(w)).mkdir(parents=True, exist_ok=True)
        almanac_glyph(w, h).save(SIDE / str(w) / ("Almanac_%d.png" % w))
    almanac_glyph(64, 64, (255, 255, 255)).save(UI / "almanac.png")
    print("ui done:", len(GLYPHS), "glyphs")


if __name__ == "__main__":
    main()
