"""Write common/media/depthmaps/DEPTH_dazedpower_0N.png so Build 42 knows how deep each Dazed Power tile is.

    python3 tools/make_depth.py          # after build_sheet.py; reads the packed sheet

Without a depth map the game treats every pixel of a modded tile as the front face of a solid block filling its
square, so a player on or behind the square vanishes behind it -- a rider on a pedal generator most of all.
Wall parts get a slab on the wall they hang on; a pedal generator sits a little behind its rider so the rider draws
in front; everything else gets a box as wide as the sprite's base. Depth sheets are 8 tiles wide (the game reads
them that way whatever the tile sheet's own width).
"""
import io, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent.parent / "DazedCore/tools/pzformat"))
import dp_taxonomy as T  # noqa: E402
import pzdepth as Z  # noqa: E402
from packfile import TexturePack  # noqa: E402

MEDIA = HERE.parent / "common/media"
CW, CH = 128, 256
EDGE = {"S": "N", "E": "W", "N": "S", "W": "E"}     # a wall part facing S hangs on the north edge, and so on
WALL_STANDOFF = {"bank": 0.30, "gauge": 0.10, "cooler": 0.25}
# Pedal generators: the bike's pixels sit this far behind the square's centre, toward the far corner, so the
# rider (standing at the centre) is always drawn over it.
PEDAL_BACK = 0.18

# Every pixel's camera ray, once: origin and direction arrays over the 128x256 cell.
_ys, _xs = np.mgrid[0:CH, 0:CW]
_nx = (_xs + 0.5) / CW * 2 - 1
_ny = 1 - (_ys + 0.5) / CH * 2
_a = np.einsum("ij,jhw->ihw", Z.MINV, np.stack([_nx, _ny, -np.ones_like(_nx), np.ones_like(_nx)]))
_b = np.einsum("ij,jhw->ihw", Z.MINV, np.stack([_nx, _ny, np.ones_like(_nx), np.ones_like(_nx)]))
O, D = _a[:3], _b[:3] - _a[:3]


def normalized(p):
    """Depth of scene points (3, h, w) as the game stores it, 0.5 near to 1.0 far."""
    q = np.einsum("ij,jhw->ihw", Z.M[:3, :3], p) + Z.M[:3, 3:4, None]
    return q[2] * (0.25 / Z._REF) + 0.75


def box_depth(lo, hi):
    """Depth where each ray first meets the box lo..hi, NaN where it misses."""
    t0 = np.full((CH, CW), -1e9); t1 = np.full((CH, CW), 1e9)
    for i in range(3):
        d = D[i]; safe = np.where(np.abs(d) < 1e-12, 1e-12, d)
        a, b = (lo[i] - O[i]) / safe, (hi[i] - O[i]) / safe
        t0 = np.maximum(t0, np.minimum(a, b)); t1 = np.minimum(t1, np.maximum(a, b))
    hit = t0 <= t1
    dep = normalized(O + D * t0)
    return np.where(hit, dep, np.nan)


def plane_depth(axis, value):
    t = (value - O[axis]) / np.where(np.abs(D[axis]) < 1e-12, 1e-12, D[axis])
    return normalized(O + D * t)


def slab(edge, t):
    lo, hi = [-0.5, 0.0, -0.5], [0.5, Z.LEVEL, 0.5]
    axis = 2 if edge in ("N", "S") else 0
    if edge in ("N", "W"): hi[axis] = -0.5 + t
    else: lo[axis] = 0.5 - t
    return lo, hi, axis, hi[axis] if edge in ("N", "W") else lo[axis]


def tile_depth(frame, kind, mount, facing):
    alpha = np.array(frame.split()[3].point(lambda a: 255 if a > 0 else 0).filter(ImageFilter.MaxFilter(3))) > 0
    if mount == "wall":
        lo, hi, axis, face = slab(EDGE[facing], WALL_STANDOFF.get(kind, 0.25))
        dep = box_depth(lo, hi)
        dep = np.where(np.isnan(dep), plane_depth(axis, face), dep)
    elif kind == "pedal":
        # A thin upright card through the square, pushed back toward the far corner (scene -x, -z is away).
        c = -PEDAL_BACK / np.sqrt(2)
        dep = box_depth([c - 0.3, 0.0, c - 0.3], [c + 0.3, Z.LEVEL, c + 0.3])
        dep = np.where(np.isnan(dep), plane_depth(2, c + 0.3), dep)
    else:
        bb = frame.getbbox()
        h = min(0.5, max(0.15, (bb[3] - 224) / 64)) if bb else 0.5
        dep = box_depth([-h, 0.0, -h], [h, Z.LEVEL, h])
        dep = np.where(np.isnan(dep), plane_depth(2, h), dep)
    v = np.clip(np.round(dep * 255), 0, 255).astype(np.uint8)
    out = np.zeros((CH, CW, 4), np.uint8)
    out[..., 0] = out[..., 1] = out[..., 2] = v
    out[..., 3] = np.where(alpha, 255, 0)
    out[~alpha, :3] = 0
    return Image.fromarray(out)


def main():
    pk = TexturePack.read(MEDIA / "texturepacks/dazedpower.pack")
    cells = {}
    for pg in pk.pages:
        sheet = Image.open(io.BytesIO(pg.png)).convert("RGBA")
        for e in pg.entries:
            c = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
            c.paste(sheet.crop((e.x, e.y, e.x + e.w, e.y + e.h)), (e.ox, e.oy))
            cells[e.name] = c
    total = len(T.ROWS) * T.COLS
    out_dir = MEDIA / "depthmaps"; out_dir.mkdir(exist_ok=True)
    for s in range((total + T.SHEET_TILES - 1) // T.SHEET_TILES):
        first, last = s * T.SHEET_TILES, min(total, (s + 1) * T.SHEET_TILES)
        n = last - first
        sheet = Image.new("RGBA", (8 * CW, ((n + 7) // 8) * CH))
        for idx in range(first, last):
            kind, mount, tier, state, piece = T.ROWS[idx // T.COLS]
            facing = T.FACINGS[idx % T.COLS]
            frame = cells.get(T.sprite_name(idx))
            if frame is None: continue
            k = idx - first
            sheet.paste(tile_depth(frame, T.ALIAS.get(kind, kind), mount, facing), ((k % 8) * CW, (k // 8) * CH))
        name = "DEPTH_%s.png" % T.TILESETS[s]
        sheet.save(out_dir / name, optimize=True)
        print("wrote %s (%d tiles)" % (name, n))


if __name__ == "__main__":
    main()
