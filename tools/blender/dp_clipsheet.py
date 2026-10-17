"""Dazed Power: contact sheets of player clips, drawn on the skinned Bob mesh without Blender.

Reads each clip back from its written .X (so the sheet also proves the file parses), skins the Body mesh the file
carries, and draws a side view and a three-quarter front view per sampled frame with a floor line and an optional
stand-in prop box. Plain Python 3 with numpy and Pillow.
    python3 tools/blender/dp_clipsheet.py <out.png> <clip.X>[:<label>] ... [--box x0,x1,z0,z1,h] [--frames N]
Character space as in dp_pullstart.py: +Y up, faces -Z, right side is -X; the floor is y = 0.
"""
import os
import sys
import numpy as np
from PIL import Image, ImageDraw

_HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(_HERE, "dp_pullstart.py"), encoding="utf-8").read().rsplit("\nrun()", 1)[0]
_lib = {"__file__": os.path.join(_HERE, "dp_pullstart.py")}
exec(_src, _lib)
XFile, mesh_data = _lib["XFile"], _lib["mesh_data"]

CELL = 220                     # pixels per view
SCALE = 190                    # pixels per Bob unit
UP = np.array([0.0, 1.0, 0.0])
LIGHT = np.array([0.4, 0.8, 0.45]); LIGHT /= np.linalg.norm(LIGHT)


def skinned(x, t, cache={}):
    """World-space vertices of the Body mesh at tick t, and its faces."""
    key = id(x)
    if key not in cache:
        cache[key] = mesh_data(x)
    verts, faces, skins = cache[key]
    W = x.world({b: x.sample_local(b, t) for b in x.order})
    vh = np.c_[verts, np.ones(len(verts))]
    out = np.zeros((len(verts), 3)); tot = np.zeros(len(verts))
    for b, (idx, w, off) in skins.items():
        M = W[b] @ off
        idx = np.array(idx, dtype=int); w = np.array(w, dtype=float)
        if not len(idx):
            continue
        np.add.at(out, idx, (vh[idx] @ M.T)[:, :3] * w[:, None])
        np.add.at(tot, idx, w)
    out /= np.maximum(tot, 1e-9)[:, None]
    return out, faces, W


def box_faces(box):
    x0, x1, z0, z1, h = box
    c = np.array([[x, y, z] for x in (x0, x1) for y in (0, h) for z in (z0, z1)], float)
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return c, quads


def draw_view(img, ox, oy, verts, faces, d, extra=(), skin=(205, 165, 135), centre=(0, 0.45, -0.1)):
    """Painter's-order flat shading looking along -d (d points from the subject to the camera)."""
    d = np.asarray(d, float); d /= np.linalg.norm(d)
    right = np.cross(-d, UP); right /= np.linalg.norm(right)
    up = np.cross(right, -d)
    cx, cy = ox + CELL / 2, oy + CELL / 2
    c = np.asarray(centre)

    def proj(p):
        q = p - c
        return np.c_[cx + q @ right * SCALE, cy - q @ up * SCALE], q @ d
    dr = ImageDraw.Draw(img)
    # Floor line through y = 0 under the subject.
    a, _ = proj(np.array([[-0.6 * right[0], 0, -0.6 * right[2]], [0.6 * right[0], 0, 0.6 * right[2]]]))
    dr.line([tuple(a[0]), tuple(a[1])], fill=(90, 90, 90), width=2)
    polys = []
    for verts_, faces_, colour in [(verts, faces, skin)] + list(extra):
        s, z = proj(verts_)
        for f in faces_:
            p = verts_[list(f)]
            n = np.cross(p[1] - p[0], p[2] - p[0])
            ln = np.linalg.norm(n)
            if ln < 1e-12:
                continue
            n /= ln
            if n @ d < 0:
                n = -n
            k = 0.45 + 0.55 * max(0.0, float(n @ LIGHT))
            polys.append((float(np.mean(z[list(f)])), [tuple(s[i]) for i in f], tuple(int(v * k) for v in colour)))
    polys.sort(key=lambda q: q[0])
    for _, pts, col in polys:
        dr.polygon(pts, fill=col)


def sheet(out, clips, box=None, frames=6, title=None):
    """clips: list of (path, label). One row per clip: frames x (side, three-quarter) views."""
    W_, H_ = frames * CELL * 2, len(clips) * (CELL + 22) + (26 if title else 0)
    img = Image.new("RGB", (W_, H_), (236, 233, 226))
    dr = ImageDraw.Draw(img)
    y0 = 0
    if title:
        dr.text((8, 6), title, fill=(30, 30, 30)); y0 = 26
    extra = []
    if box:
        bv, bq = box_faces(box)
        extra = [(bv, bq, (150, 60, 45))]
    for r, (path, label) in enumerate(clips):
        x = XFile(path)
        n = x.length()
        oy = y0 + r * (CELL + 22)
        dr.text((8, oy + 4), "%s  (%s, %d keys, %.2f s)" % (label, os.path.basename(path), len(x.anim), n / x.ticks), fill=(20, 20, 20))
        for k in range(frames):
            t = int(round(n * k / max(1, frames - 1))) if frames > 1 else 0
            verts, faces, W = skinned(x, t)
            for j, d in enumerate(([1, 0, 0], [0.75, 0.25, -0.65])):
                ox = (k * 2 + j) * CELL
                draw_view(img, ox, oy + 22, verts, faces, d, extra)
                if j == 0:
                    dr.text((ox + 6, oy + 24), "f%d" % round(t * 30 / x.ticks), fill=(60, 60, 60))
            # Props: the two prop bones as dots in the side view (green = Prop1/right, blue = Prop2/left).
            for b, col in (("Bip01_Prop1", (30, 150, 40)), ("Bip01_Prop2", (40, 70, 200))):
                p = W[b][:3, 3] - np.array([0, 0.45, -0.1])
                sx, sy = k * 2 * CELL + CELL / 2 + (-p[2]) * SCALE, oy + 22 + CELL / 2 - p[1] * SCALE
                dr.ellipse([sx - 3, sy - 3, sx + 3, sy + 3], fill=col)
    img.save(out)
    return out


if __name__ == "__main__":
    args = sys.argv[1:]
    box, frames, title = None, 6, None
    clips = []
    i = 1
    while i < len(args):
        a = args[i]
        if a == "--box":
            box = tuple(float(v) for v in args[i + 1].split(",")); i += 2; continue
        if a == "--frames":
            frames = int(args[i + 1]); i += 2; continue
        if a == "--big":
            CELL, SCALE = 400, 360; i += 1; continue
        if a == "--title":
            title = args[i + 1]; i += 2; continue
        p, _, lab = a.partition(":") if not os.path.exists(a) else (a, "", "")
        clips.append((p, lab or os.path.splitext(os.path.basename(p))[0]))
        i += 1
    print(sheet(args[0], clips, box, frames, title))
