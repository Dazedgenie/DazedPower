"""Stand-in windmill spin frames (windspin rows) drawn over the Blender 'turning' and 'broken' cells.

    python3 tools/wind_frames.py      # writes tools/art/<index>.png for every windspin row that has no art yet

The real frames come from tools/blender/dz2.py (job dp:windspin); this only fills the sheet until then. It uses the
same 2:1 iso camera as dz_render.py, so blades land where the renderer would put them.
"""
import math, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import dp_taxonomy as T  # noqa: E402

ART = HERE / "art"
FACING_DEG = {"E": 90, "S": 0, "W": 270, "N": 180}       # model front is -Y; degrees about Z (dz_render FACINGS)
# Rotor per tier, from dz_render.build_windmill: hub, blade count, length, root and tip chord, colour.
ROTOR = {
    "makeshift": dict(hub=(0, -0.12, 2.02), n=3, L=0.56, w0=0.10, w1=0.05, col=(179, 176, 164), hub_r=0.07, hub_col=(170, 140, 100)),
    "salvaged": dict(hub=(0, -0.15, 2.12), n=6, L=0.50, w0=0.11, w1=0.13, col=(64, 95, 124), hub_r=0.07, hub_col=(60, 62, 64)),
    "workshop": dict(hub=(0, -0.22, 2.04), n=3, L=0.55, w0=0.075, w1=0.03, col=(203, 203, 195), hub_r=0.04, hub_col=(203, 203, 195)),
}


def rot_x(a):
    c, s = math.cos(a), math.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(a):
    c, s = math.cos(a), math.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(a):
    c, s = math.cos(a), math.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


CAM = rot_z(math.radians(45)) @ rot_x(math.radians(60))   # Blender XYZ euler (60, 0, 45)
UP, RIGHT, FWD = CAM @ np.array([0, 1, 0]), CAM @ np.array([1, 0, 0]), CAM @ np.array([0, 0, -1])
CENTER = UP * (1.5 / math.sqrt(2))
ORTHO = 2 * math.sqrt(2)                                     # vertical extent of the 512 px render


def project(p):
    """Model point (after facing) to (x, y) in a 128x256 cell, and its depth (bigger = farther)."""
    d = np.asarray(p, float) - CENTER
    x = 64 + d @ RIGHT / (ORTHO / 2) * 128
    y = 128 - d @ UP / (ORTHO / 2) * 128
    return x, y, d @ FWD


def blade_polys(tier, facing, angle, grow=0.0):
    """The projected outline of each blade at `angle`, widened by `grow` squares for erasing."""
    r = ROTOR[tier]; Rz = rot_z(math.radians(FACING_DEG[facing])); hub = np.array(r["hub"], float)
    out = []
    for i in range(r["n"]):
        a = math.radians(angle + 360.0 * i / r["n"])
        along = np.array([math.sin(a), 0, math.cos(a)]); chord = np.array([math.cos(a), 0, -math.sin(a)])
        root, tip = hub + along * r["hub_r"] * 0.5, hub + along * (r["L"] + grow)
        w0, w1 = r["w0"] / 2 + grow, r["w1"] / 2 + grow
        pts = [root + chord * w0, tip + chord * w1, tip - chord * w1, root - chord * w0]
        out.append(([project(Rz @ p)[:2] for p in pts], a))
    return out


def unbladed(still, tier, facing):
    """The 'still' cell with its own blades taken out: pixels inside each blade's outline that are blade-coloured."""
    r = ROTOR[tier]; mask = Image.new("L", still.size, 0); d = ImageDraw.Draw(mask)
    for poly, _ in blade_polys(tier, facing, 0.0, grow=0.05):
        d.polygon(poly, fill=255)
    px = np.array(still).astype(int); m = np.array(mask) > 0
    col = np.array(r["col"]); diff = np.abs(px[..., :3] - col).sum(-1)
    lum = px[..., :3].mean(-1); blade_lum = col.mean()
    # Shading moves a blade's brightness a long way, so match on hue (colour minus its own grey) and a loose brightness.
    hue = np.abs((px[..., :3] - lum[..., None]) - (col - blade_lum)).sum(-1)
    hit = m & (px[..., 3] > 0) & (hue < 60) & (np.abs(lum - blade_lum) < 110)
    # The post under the hub is never a blade: keep a strip as wide as the post (tower radius ~0.08) below it.
    Rz = rot_z(math.radians(FACING_DEG[facing])); hub = np.array(r["hub"], float)
    hx, hy, _ = project(Rz @ hub); bx, by, _ = project(Rz @ np.array([0, 0, hub[2]]))
    half = 0.085 / (ORTHO / 2) * 128 + 1
    ys, xs = np.mgrid[0:still.size[1], 0:still.size[0]]
    hit &= ~((np.abs(xs - bx) <= half) & (ys > by + 2))
    px[hit] = 0
    return Image.fromarray(px.astype(np.uint8))


def frame(base, tier, facing, angle, behind_ok=True):
    r = ROTOR[tier]; Rz = rot_z(math.radians(FACING_DEG[facing])); hub = np.array(r["hub"], float)
    hx, hy, hz = project(Rz @ hub)
    _, _, post_z = project(Rz @ np.array([0, 0, hub[2]]))
    behind = hz > post_z                                       # the rotor is on the far side of the post
    # Drawn at 4x and scaled down, so blade edges are smooth like the renders.
    SS = 4
    big = Image.new("RGBA", (base.size[0] * SS, base.size[1] * SS), (0, 0, 0, 0)); d = ImageDraw.Draw(big)
    edge = tuple(int(v * 0.6) for v in r["col"]) + (255,)
    for poly, a in blade_polys(tier, facing, angle, grow=0.006):
        d.polygon([(x * SS, y * SS) for x, y in poly], fill=edge)
    for poly, a in blade_polys(tier, facing, angle):
        shade = 0.82 + 0.18 * math.cos(a)                      # a little light-to-dark round the turn
        c = tuple(min(255, int(v * shade)) for v in r["col"])
        d.polygon([(x * SS, y * SS) for x, y in poly], fill=c + (255,))
    hr = r["hub_r"] / (ORTHO / 2) * 128 * SS
    hx, hy = hx * SS, hy * SS
    d.ellipse((hx - hr, hy - hr * 0.9, hx + hr, hy + hr * 0.9), fill=r["hub_col"] + (255,), outline=(40, 40, 40, 255), width=SS)
    layer = big.resize(base.size, Image.LANCZOS)
    out = Image.new("RGBA", base.size, (0, 0, 0, 0))
    if behind:
        out.alpha_composite(layer); out.alpha_composite(base)
    else:
        out.alpha_composite(base); out.alpha_composite(layer)
    return out


def wobble(base, tier, facing, deg=9):
    """A broken rotor rocked a few degrees: the disc around the hub turned in the rotor's own plane."""
    r = ROTOR[tier]; Rz = rot_z(math.radians(FACING_DEG[facing])); hub = np.array(r["hub"], float)
    o = np.array(project(Rz @ hub)[:2]); ex = np.array(project(Rz @ (hub + [1, 0, 0]))[:2]) - o
    ez = np.array(project(Rz @ (hub + [0, 0, 1]))[:2]) - o
    A = np.column_stack([ex, ez]); Ai = np.linalg.inv(A); c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    M = A @ np.array([[c, s], [-s, c]]) @ Ai                   # rotate in the rotor plane, seen through the camera
    Mi = np.linalg.inv(M); src = np.asarray(base)
    out = np.array(base); R = r["L"] / (ORTHO / 2) * 128 * 1.05
    for y in range(base.size[1]):
        for x in range(base.size[0]):
            v = np.array([x, y]) - o
            if v @ v > R * R: continue
            sx, sy = (Mi @ v + o).round().astype(int)
            if 0 <= sx < base.size[0] and 0 <= sy < base.size[1] and src[sy, sx, 3] > 0 and out[y, x, 3] == 0:
                out[y, x] = src[sy, sx]
    return Image.fromarray(out)


def main(force=False):
    n = 0
    for tier in T.TIERS["windspin"]:
        step = 360.0 / ROTOR[tier]["n"] / 4
        for fi, facing in enumerate(T.FACINGS):
            still = Image.open(ART / ("%d.png" % T.sprite_index("windmill", "ground", tier, "still", facing))).convert("RGBA")
            bare = unbladed(still, tier, facing)
            broken = Image.open(ART / ("%d.png" % T.sprite_index("windmill", "ground", tier, "broken", facing))).convert("RGBA")
            for k, state in enumerate(T.STATES["windspin"]):
                idx = T.sprite_index("windspin", "ground", tier, state, facing)
                dest = ART / ("%d.png" % idx)
                if dest.exists() and not force: continue
                # Until dz2.py renders the rocked rotor, the wobble frame is the broken cell itself.
                im = broken.copy() if state == "wobble" else frame(bare, tier, facing, step * k)
                im.save(dest); n += 1
    print("wrote %d stand-in frames" % n)


if __name__ == "__main__":
    main("--force" in sys.argv[1:])
