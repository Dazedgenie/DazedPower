"""Dazed Power: sanity checks for player clip .X files against a reference clip.
    python3 tools/blender/dp_xcheck.py <reference.X> <clip.X> ...
Each clip must: carry the reference's header byte for byte (templates, skeleton, skinned mesh), animate exactly
the reference's bones in the same order, have well-formed key blocks (declared counts match, ticks rising, unit
quaternions, finite numbers, scale ~1), balanced braces, the AnimationSet named after the file, and, as a loop,
end on the pose it starts with. Exit status 1 on any failure.
"""
import os
import re
import sys
import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(_HERE, "dp_pullstart.py"), encoding="utf-8").read().rsplit("\nrun()", 1)[0]
_lib = {"__file__": os.path.join(_HERE, "dp_pullstart.py")}
exec(_src, _lib)
XFile = _lib["XFile"]


def header(text):
    return text[:text.index("AnimTicksPerSecond  {")]


def check(ref_path, path, loop=True):
    errs = []
    ref = XFile(ref_path)
    text = open(path, encoding="latin-1").read()
    if not text.startswith("xof 0303txt 0032"):
        errs.append("not a text .X 0303")
    if text.count("{") != text.count("}"):
        errs.append("unbalanced braces")
    if header(text) != header(ref.text):
        errs.append("header differs from the reference (skeleton/mesh)")
    x = XFile(path)
    name = os.path.splitext(os.path.basename(path))[0]
    if getattr(x, "anim_name", None) != name:
        errs.append("AnimationSet is %r, file is %r" % (getattr(x, "anim_name", None), name))
    order = re.findall(r"Animation \{\s*\{ (\S+) \}", text)
    ref_order = re.findall(r"Animation \{\s*\{ (\S+) \}", ref.text)
    if order != ref_order:
        errs.append("animated bones differ from the reference: %d vs %d" % (len(order), len(ref_order)))
    if x.order != ref.order:
        errs.append("frame hierarchy differs")
    # Declared key counts against what is there.
    for m in re.finditer(r"AnimationKey [RST] \{\s*(\d);\s*(\d+);\s*(.*?);\s*\}", text, re.S):
        typ, n, body = int(m.group(1)), int(m.group(2)), m.group(3)
        rows = [r for r in body.split(";;") if r.strip(" ,\n;")]
        if len(rows) != n:
            errs.append("a key block declares %d keys and has %d" % (n, len(rows)))
            break
    end = x.length()
    for b, d in x.anim.items():
        for k, keys in d.items():
            ts = [t for t, _ in keys]
            if ts != sorted(ts) or len(set(ts)) != len(ts):
                errs.append("%s %s: ticks not rising" % (b, k)); continue
            vals = np.array([v for _, v in keys])
            if not np.all(np.isfinite(vals)):
                errs.append("%s %s: non-finite value" % (b, k))
            if k == "R" and np.max(np.abs(np.linalg.norm(vals, axis=1) - 1)) > 1e-3:
                errs.append("%s: quaternion not unit" % b)
            if k == "S" and np.max(np.abs(vals - 1)) > 1e-3:
                errs.append("%s: scale is not 1" % b)
            if loop:
                a, z = keys[0][1], keys[-1][1]
                same = abs(abs(float(np.dot(a, z))) - 1) < 1e-4 if k == "R" else np.allclose(a, z, atol=1e-4)
                if not same:
                    errs.append("%s %s: last key differs from the first (not a clean loop)" % (b, k))
    return errs, len(order), end / x.ticks


def main(argv):
    ref = argv[0]
    bad = 0
    for p in argv[1:]:
        errs, n, secs = check(ref, p)
        print("%s: %s (%d bones, %.2f s)" % (os.path.basename(p), "OK" if not errs else "FAIL", n, secs))
        for e in errs[:12]:
            print("   ", e)
        bad += bool(errs)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
