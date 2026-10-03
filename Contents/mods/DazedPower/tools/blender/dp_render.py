"""Dazed Utilities: Power -- render the solar, battery, controller, transformer and lamp sprites in Blender
with the pz-sprite-forge rig, in the style of Dazed Power and Plumbing.

Run inside Blender (4.2+ / 5.x) from the Python console:
    ART = r"C:\\Users\\<you>\\Zomboid\\ogm_art"; FAMILIES = ["preview"]; exec(open(ART + r"\\dp_render.py").read())
or headless:  blender -b -P dp_render.py -- <ART folder> [family ...]
ART must hold pz_sprite_forge.py. Families: preview, arrays, trackers, xl, banks, walls, controllers,
transformer, lamps, icons (or "all"). Cells go to ART/dp_out/<family>/<sprite index>.png (2x, 256x512),
named by their index on dazedpower_01; a 2x2 piece also writes <index>_m.png, the mask of its own square.
The power sources (pedal, wind, steam, gas, instruments) keep Dazed Power's renders.
"""
import bpy
import bmesh
import math
import os
import random
import sys
import time
from mathutils import Vector, Euler

if "ART" not in globals():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ART = argv[0] if argv else os.path.dirname(os.path.abspath(__file__))
    FAMILIES = argv[1:] or ["preview"]
else:
    FAMILIES = globals().get("FAMILIES", ["preview"])
SAMPLES = globals().get("SAMPLES", 256)
# "mp" is the Dazed Power / Plumbing look; "pz" leans into vanilla Project Zomboid: a muted, warm palette, matte
# paint with grime in the corners, and a soft dark outline. Its renders go to dp_out_pz so the two can be compared.
STYLE = globals().get("STYLE", "mp")
OUT = os.path.join(ART, "dp_out" if STYLE == "mp" else "dp_out_" + STYLE)
sys.path.insert(0, ART)
import pz_sprite_forge as F  # noqa: E402

try:
    F.register()
except (ValueError, RuntimeError):
    pass                                                        # already registered this session

# ------------------------------------------------------------------ the sheet's layout
# Must match tools/dp_taxonomy.py and DP_Parts.lua: rows in this order, four facings per row (E, S, W, N).
KINDS = ["array", "bank", "controller", "transformer", "lamp", "pedal", "windmill", "steam", "windsock", "vane",
         "propane", "petrol", "gauge"]
MOUNTS = {"array": ["ground", "tracker", "xl"], "bank": ["ground", "wall"], "controller": ["ground"],
          "transformer": ["ground"], "lamp": ["garden", "street"], "pedal": ["ground"], "windmill": ["ground"],
          "steam": ["ground"], "windsock": ["ground"], "vane": ["ground"], "propane": ["ground"], "petrol": ["ground"],
          "gauge": ["wall"]}
THREE = ["makeshift", "salvaged", "workshop"]
TIERS = {"array": THREE, "bank": THREE, "controller": ["makeshift", "workshop"], "transformer": ["standard"],
         "lamp": ["makeshift", "workshop"], "pedal": THREE, "windmill": THREE, "steam": THREE,
         "windsock": ["basic"], "vane": ["basic"], "propane": THREE, "petrol": THREE,
         "gauge": ["standard"]}
STATES = {"array": ["clear", "snow", "cracked"], "controller": ["off", "on"], "transformer": ["off", "on"],
          "lamp": ["off", "on"], "pedal": ["off", "on"], "windmill": ["still", "turning", "furled", "broken"],
          "steam": ["cold", "warming", "running", "broken"], "windsock": ["limp", "half", "full"], "vane": ["set"],
          "propane": ["off", "running", "broken"], "petrol": ["off", "running", "broken"],
          "gauge": ["off", "low", "mid", "full"]}
BANK_CELLS = {"ground": {"makeshift": 3, "salvaged": 6, "workshop": 8}, "wall": {"makeshift": 2, "salvaged": 3, "workshop": 4}}
PIECE_OFFSET = {1: (0, 0), 2: (1, 0), 3: (0, 1), 4: (1, 1)}          # PZ squares from the master (NW)


def states_for(kind, mount, tier):
    if kind != "bank":
        return STATES[kind]
    return ["c%d" % i for i in range(BANK_CELLS[mount][tier] + 1)]


ROWS = []
for _k in KINDS:
    for _m in MOUNTS[_k]:
        for _t in TIERS[_k]:
            for _s in states_for(_k, _m, _t):
                for _p in range(1, (4 if (_k == "array" and _m == "xl") else 1) + 1):
                    ROWS.append((_k, _m, _t, _s, _p))
ROW_OF = {r: i for i, r in enumerate(ROWS)}
FACINGS = {"E": (0, 90), "S": (1, 0), "W": (2, 270), "N": (3, 180)}   # column, degrees about Z


def index_of(kind, mount, tier, state, facing, piece=1):
    return ROW_OF[(kind, mount, tier, state, piece)] * 4 + FACINGS[facing][0]


# ------------------------------------------------------------------ scene
scene = bpy.data.scenes.get("DP_Render") or bpy.data.scenes.new("DP_Render")
if bpy.context.window is not None:
    bpy.context.window.scene = scene
scene.render.engine = "CYCLES"
props = scene.pz_forge
props.scale_2x, props.show_guide, props.ground_occlusion = True, False, True
F.build_rig(bpy.context)
# Crisper than the rig's defaults: twice the cell size, no denoiser; tools/import_art.py shrinks and sharpens.
scene.render.resolution_percentage = 200
scene.render.filter_size = 0.7
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = False
SUBJECT = bpy.data.objects[F.SUBJECT_NAME]


def outline(on):
    """Vanilla tiles read by a soft dark edge: Freestyle draws silhouettes and borders at about 1 px of the final cell."""
    scene.render.use_freestyle = on
    if not on:
        return
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = 2.2                  # at 200%; the import's halving leaves about one pixel
    vl = scene.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("pz_outline")
    ls.select_by_visibility, ls.select_by_edge_types = True, True
    ls.select_silhouette, ls.select_border, ls.select_crease = True, True, True
    ls.select_external_contour = True
    style = ls.linestyle
    style.color = (0.11, 0.085, 0.065)
    style.alpha = 0.6
    style.thickness = 2.2


outline(STYLE == "pz")
MODEL = bpy.data.collections.get("DP_Model") or bpy.data.collections.new("DP_Model")
if MODEL.name not in scene.collection.children:
    scene.collection.children.link(MODEL)


def clear_model():
    for o in list(MODEL.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


# ------------------------------------------------------------------ materials (as Dazed Power's)
def lin(hexcol):
    """An sRGB hex colour as linear RGB (what Base Color expects)."""
    h = hexcol.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


_mats = {}

PZ_DESAT = 0.32           # share of saturation the vanilla look takes away
PZ_WARM = (1.03, 1.0, 0.94)
PZ_RANGE = (0.07, 0.86)   # vanilla paint rarely reaches pure black or white


def pz_colour(hexcol):
    """A colour pulled toward vanilla PZ's palette: less saturated, slightly warm, kept off the extremes."""
    h = hexcol.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    grey = 0.3 * r + 0.59 * g + 0.11 * b
    out = []
    for c, w in zip((r, g, b), PZ_WARM):
        c = (c + (grey - c) * PZ_DESAT) * w
        out.append(PZ_RANGE[0] + (PZ_RANGE[1] - PZ_RANGE[0]) * max(0.0, min(1.0, c)))
    return "#%02x%02x%02x" % tuple(int(round(c * 255)) for c in out)


def mat(hexcol, rough=0.6, wear=0.0, emit=0.0, alpha=1.0, rust=0.0, spec=0.12):
    """Painted, essentially diffuse material (vanilla art is painted, not metallic), with optional wear and rust."""
    if STYLE == "pz" and emit <= 0:
        # Matte, grimier paint; lamps and LEDs keep their colour so they still read at a glance.
        hexcol = pz_colour(hexcol)
        rough, spec, wear = max(rough, 0.82), min(spec, 0.05), max(wear, 0.14)
    key = (hexcol, rough, wear, emit, alpha, rust, spec)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("dp_%s_%d" % (hexcol.strip("#"), len(_mats)))
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    base = lin(hexcol)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = spec
    b.inputs["Alpha"].default_value = alpha
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*base, 1)
        b.inputs["Emission Strength"].default_value = emit
    colour = None
    if wear > 0:                                                    # soft, broad paint wear
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 6.0
        noise.inputs["Detail"].default_value = 3.0
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.30
        ramp.color_ramp.elements[1].position = 0.75
        ramp.color_ramp.elements[0].color = (*(c * (1 - wear) for c in base), 1)
        ramp.color_ramp.elements[1].color = (*(min(1.0, c * (1 + wear * 0.3)) for c in base), 1)
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        colour = ramp.outputs["Color"]
    if rust > 0:                                                    # rust in patches, not speckle
        mask = nt.nodes.new("ShaderNodeTexNoise")
        mask.inputs["Scale"].default_value = 3.0
        mask.inputs["Detail"].default_value = 6.0
        mramp = nt.nodes.new("ShaderNodeValToRGB")
        mramp.color_ramp.elements[0].position = 0.50
        mramp.color_ramp.elements[1].position = 0.62
        mramp.color_ramp.elements[1].color = (rust, rust, rust, 1)
        nt.links.new(mask.outputs["Fac"], mramp.inputs["Fac"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        fac = [i for i in mix.inputs if i.name == "Factor" and i.type == "VALUE"][0]
        a = [i for i in mix.inputs if i.name == "A" and i.type == "RGBA"][0]
        bb = [i for i in mix.inputs if i.name == "B" and i.type == "RGBA"][0]
        out = [o for o in mix.outputs if o.type == "RGBA"][0]
        nt.links.new(mramp.outputs["Color"], fac)
        if colour is not None:
            nt.links.new(colour, a)
        else:
            a.default_value = (*base, 1)
        bb.default_value = (*lin("#6e3a22"), 1)
        colour = out
    if STYLE == "pz" and emit <= 0:
        # Dirt gathers where surfaces meet: ambient occlusion darkens the base colour in corners and seams.
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.inputs["Distance"].default_value = 0.08
        if colour is not None:
            nt.links.new(colour, ao.inputs["Color"])
        else:
            ao.inputs["Color"].default_value = (*base, 1)
        aoramp = nt.nodes.new("ShaderNodeValToRGB")
        aoramp.color_ramp.elements[0].color = (0.55, 0.50, 0.45, 1)
        aoramp.color_ramp.elements[1].color = (1, 1, 1, 1)
        nt.links.new(ao.outputs["AO"], aoramp.inputs["Fac"])
        dirt = nt.nodes.new("ShaderNodeMix")
        dirt.data_type = "RGBA"
        dirt.blend_type = "MULTIPLY"
        fac = [i for i in dirt.inputs if i.name == "Factor" and i.type == "VALUE"][0]
        a = [i for i in dirt.inputs if i.name == "A" and i.type == "RGBA"][0]
        bb = [i for i in dirt.inputs if i.name == "B" and i.type == "RGBA"][0]
        fac.default_value = 1.0
        nt.links.new(ao.outputs["Color"], a)
        nt.links.new(aoramp.outputs["Color"], bb)
        colour = [o for o in dirt.outputs if o.type == "RGBA"][0]
    if colour is not None:
        nt.links.new(colour, b.inputs["Base Color"])
    else:
        b.inputs["Base Color"].default_value = (*base, 1)
    _mats[key] = m
    return m


# ------------------------------------------------------------------ geometry helpers (as Dazed Power's)
def _obj(name, bm, material, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    MODEL.objects.link(o)
    o.location, o.rotation_euler = loc, Euler(rot, "XYZ")
    me.materials.append(material)
    o.parent = current_parent()
    if bevel > 0:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width, mod.segments, mod.limit_method = bevel, 2, "ANGLE"
    return o


_PARENTS = []


def current_parent():
    """What new parts hang from: the innermost `group`, else the turning subject."""
    return _PARENTS[-1][0] if _PARENTS else SUBJECT


class group:
    """Build parts in a local frame at `loc` with rotation `rot`."""
    def __init__(self, loc=(0, 0, 0), rot=(0, 0, 0)):
        e = bpy.data.objects.new("pivot", None)
        MODEL.objects.link(e)
        e.parent = current_parent()
        e.location, e.rotation_euler = loc, Euler(rot, "XYZ")
        self.empty = e

    def __enter__(self):
        _PARENTS.append((self.empty,))
        return self.empty

    def __exit__(self, *a):
        _PARENTS.pop()


def box(size, center, material, rot=(0, 0, 0), bevel=0.012):
    """A box `size` (x, y, z) centred at `center`."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    return _obj("box", bm, material, center, rot, bevel)


def cyl(radius, depth, center, material, axis="Z", radius2=None, segs=28, rot=None):
    """A cylinder (or cone with radius2) along an axis, centred at `center`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=depth)
    for f in bm.faces:
        f.smooth = abs(f.normal.z) < 0.7
    r = rot or {"Z": (0, 0, 0), "X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0)}[axis]
    return _obj("cyl", bm, material, center, r)


def ball(radius, center, material, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=radius)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    for f in bm.faces:
        f.smooth = True
    return _obj("ball", bm, material, center)


def tube(a, b, radius, material, segs=12):
    """A round bar from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    q = d.normalized().to_track_quat("Z", "Y")
    o = cyl(radius, d.length, (a + b) / 2, material, segs=segs)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = q
    return o


def light(center, on, colour="#3ee06a", size=(0.022, 0.012, 0.022)):
    box(size, center, mat(colour if on else "#2a2f2a", 0.3, emit=6.0 if on else 0.0), bevel=0.003)


# ------------------------------------------------------------------ palette
WOOD = "#7a5232"
PLANK = "#93673f"
STEEL = "#8e9398"
GALV = "#a3a8ad"
DARK = "#34373c"
BLACK = "#1c1d20"
CONCRETE = "#8b8983"
TAPE = "#9a9da0"
SNOW = "#f1f3f6"
COPPER = "#c08a3a"


def tier_rust(tier, state):
    return 0.6 if state == "cracked" else (0.25 if tier == "makeshift" else 0.0)


# ------------------------------------------------------------------ solar modules
# A module is drawn in its panel group's local frame: it lies in local XY, face up (+Z), its long side along
# local Y; the group is tipped about X so the face looks toward -Y (the part's front) and up.
CELL_LOOK = {
    "makeshift": (["#2b4a86", "#22305a", "#3c5a8e", "#1d2a4c"], "#8fa3b8", "#b9bec4"),   # mismatched poly cells
    "salvaged": (["#2b4a86"], "#9fb3c8", "#b9bec4"),                                     # polycrystalline blue
    "workshop": (["#141826"], "#38414f", "#c9cdd2"),                                     # monocrystalline black
}


def module(cx, cy, w, l, tier, state, rng, cols=4, rows=8, cracked=False):
    """One PV module centred at (cx, cy) in the panel frame: frame, cells, busbar grid; snow or cracks on top."""
    colours, line, frame_c = CELL_LOOK[tier]
    frame = mat(frame_c, 0.45, wear=0.1 if tier != "workshop" else 0.03)
    glass_rough = 0.22 if not cracked else 0.45
    t = 0.022
    box((w, l, 0.03), (cx, cy, -0.012), mat("#d8d8d2", 0.7), bevel=0.004)                 # backsheet and depth
    box((w, 0.024, t), (cx, cy - l / 2 + 0.012, 0.008), frame, bevel=0.003)               # frame rails
    box((w, 0.024, t), (cx, cy + l / 2 - 0.012, 0.008), frame, bevel=0.003)
    box((0.024, l, t), (cx - w / 2 + 0.012, cy, 0.008), frame, bevel=0.003)
    box((0.024, l, t), (cx + w / 2 - 0.012, cy, 0.008), frame, bevel=0.003)
    iw, il = w - 0.05, l - 0.05
    if len(colours) == 1:
        box((iw, il, 0.012), (cx, cy, 0.006), mat(colours[0], glass_rough, spec=0.35), bevel=0)
    else:                                                                                # patchwork of scavenged cells
        cw, ch = iw / cols, il / rows
        for i in range(cols):
            for j in range(rows):
                c = colours[rng.randrange(len(colours))]
                box((cw * 0.96, ch * 0.96, 0.012), (cx - iw / 2 + cw * (i + 0.5), cy - il / 2 + ch * (j + 0.5), 0.006),
                    mat(c, glass_rough, spec=0.35), bevel=0)
    lm = mat(line, 0.4)
    for i in range(1, cols):                                                             # busbars and cell gaps
        box((0.004, il, 0.003), (cx - iw / 2 + iw * i / cols, cy, 0.0135), lm, bevel=0)
    for j in range(1, rows):
        box((iw, 0.004, 0.003), (cx, cy - il / 2 + il * j / rows, 0.0135), lm, bevel=0)
    if tier == "makeshift":                                                              # duct tape where it was mended
        tm = mat(TAPE, 0.8, wear=0.2)
        box((w * 0.9, 0.035, 0.004), (cx, cy + rng.uniform(-0.2, 0.2) * l, 0.016), tm, rot=(0, 0, rng.uniform(-0.3, 0.3)), bevel=0)
    if state == "snow":
        sn = mat(SNOW, 0.9)
        box((w * 0.96, l * 0.78, 0.03), (cx, cy - l * 0.09, 0.03), sn, bevel=0.012)       # the top edge shows through
        for k in range(3):
            ball(0.04 + rng.uniform(0, 0.02), (cx - w / 2 + w * (k + 0.5) / 3, cy + l * 0.30, 0.03), sn, scale=(1.4, 0.7, 0.35))
        for k in range(5):                                                               # a lumpy lower edge where it slid
            ball(0.05 + rng.uniform(0, 0.03), (cx - w / 2 + w * (k + 0.5) / 5, cy - l / 2 + 0.03, 0.03), sn, scale=(1.2, 0.8, 0.45))
    if cracked:
        cm = mat("#d8e2ea", 0.3, emit=0.0)
        ox, oy = cx + rng.uniform(-0.25, 0.25) * w, cy + rng.uniform(-0.25, 0.25) * l
        box((0.08, 0.06, 0.006), (ox, oy, 0.016), mat("#0b0c10", 0.9), bevel=0)           # the impact, glass gone
        for k in range(7):
            a = rng.uniform(0, 2 * math.pi)
            ln = rng.uniform(0.12, 0.30)
            box((0.005, ln, 0.004), (ox + math.sin(a) * ln / 2, oy + math.cos(a) * ln / 2, 0.017), cm, rot=(0, 0, -a), bevel=0)


def panel_bank(n, w, l, tier, state, rng, gap=0.025, cols=4, rows=8, crack_one=True):
    """`n` modules side by side along local X; returns the span."""
    span = n * w + (n - 1) * gap
    for i in range(n):
        cx = -span / 2 + w / 2 + i * (w + gap)
        module(cx, 0, w, l, tier, state, rng, cols, rows, cracked=(state == "cracked" and (i == 0 or not crack_one)))
    return span


def junction_box(x, y, z, tier):
    box((0.10, 0.07, 0.035), (x, y, z), mat("#2a2c30", 0.6), bevel=0.006)
    tube((x - 0.03, y, z - 0.02), (x - 0.03, y + 0.02, 0.02), 0.008, mat(BLACK, 0.7))


# ------------------------------------------------------------------ static arrays
ARRAY = {  # modules, module width, length, tilt (deg)
    "makeshift": (2, 0.40, 0.80, 32),
    "salvaged": (2, 0.42, 0.84, 32),
    "workshop": (3, 0.28, 0.88, 32),
}


def static_array(tier, state):
    """A ground frame tilted toward the front (-Y), its modules side by side."""
    rng = random.Random(hash(("array", tier)) & 0xffff)
    n, w, l, tilt = ARRAY[tier]
    a = math.radians(tilt)
    run, rise = l * math.cos(a), l * math.sin(a)
    y0, z0 = -run / 2, 0.10                                         # front (low) edge
    rust = tier_rust(tier, state)
    if tier == "makeshift":
        wood = mat(WOOD, 0.85, wear=0.25)
        box((0.86, 0.10, 0.05), (0, y0, 0.025), mat(PLANK, 0.85, wear=0.25), bevel=0.006)          # front sleeper
        box((0.86, 0.10, 0.05), (0, -y0, 0.025), mat(PLANK, 0.85, wear=0.25), bevel=0.006)         # back sleeper
        for sx in (-0.36, 0.36):
            tube((sx, y0, 0.05), (sx, y0, z0), 0.025, wood)                                          # short front legs
            box((0.05, 0.05, z0 + rise - 0.02), (sx, -y0 - 0.02, (z0 + rise) / 2), wood, bevel=0.005)  # tall back legs
            tube((sx, y0, 0.06), (sx, -y0 - 0.02, z0 + rise - 0.06), 0.018, wood)                    # diagonal brace
        tube((-0.36, -y0 - 0.02, 0.30), (0.36, -y0 - 0.02, 0.30), 0.018, wood)
    else:
        frame = mat(STEEL if tier == "salvaged" else GALV, 0.45, wear=0.12 if tier == "salvaged" else 0.04, rust=rust)
        if tier == "workshop":
            box((0.90, 0.20, 0.06), (0, y0 + 0.02, 0.03), mat(CONCRETE, 0.9, wear=0.2), bevel=0.008)   # ballast blocks
            box((0.90, 0.20, 0.06), (0, -y0 - 0.04, 0.03), mat(CONCRETE, 0.9, wear=0.2), bevel=0.008)
        for sx in ((-0.38, 0.38) if tier == "salvaged" else (-0.40, 0.0, 0.40)):
            box((0.035, run + 0.04, 0.035), (sx, 0, 0.05), frame, bevel=0.004)                       # foot rail
            tube((sx, y0, 0.06), (sx, y0, z0), 0.017, frame)
            tube((sx, -y0 - 0.02, 0.06), (sx, -y0 - 0.02, z0 + rise - 0.04), 0.017, frame)           # back post
            tube((sx, y0 + 0.05, 0.07), (sx, -y0 - 0.06, z0 + rise * 0.7), 0.012, frame)             # brace
    with group((0, y0 + run / 2, z0 + rise / 2 + 0.03), (a, 0, 0)):
        if tier != "makeshift":
            fr = mat(STEEL if tier == "salvaged" else GALV, 0.45, rust=rust)
            for yy in (-l * 0.3, l * 0.3):
                box((n * w + 0.06, 0.03, 0.025), (0, yy, -0.04), fr, bevel=0.004)                    # purlins
        else:
            for yy in (-l * 0.3, l * 0.3):
                box((n * w + 0.06, 0.05, 0.03), (0, yy, -0.045), mat(WOOD, 0.85, wear=0.25), bevel=0.004)
        panel_bank(n, w, l, tier, state, rng)
        junction_box(0, l * 0.25, -0.06, tier)
    if tier == "makeshift":                                                                         # the lead, taped down
        tube((0.30, -y0 - 0.02, 0.25), (0.42, -y0 + 0.08, 0.02), 0.008, mat(BLACK, 0.7))


# ------------------------------------------------------------------ tracking arrays
TRACK = {  # modules, module width, length
    "makeshift": (2, 0.38, 0.74),
    "salvaged": (2, 0.40, 0.80),
    "workshop": (3, 0.27, 0.84),
}


def tracker(tier, state):
    """A post-mounted frame on a drive head: the frame tips toward the front (-Y); the facing is where the sun is."""
    rng = random.Random(hash(("tracker", tier)) & 0xffff)
    n, w, l = TRACK[tier]
    rust = tier_rust(tier, state)
    H = 0.78
    if tier == "makeshift":
        box((0.36, 0.36, 0.05), (0, 0.06, 0.025), mat(PLANK, 0.85, wear=0.25), bevel=0.006)        # plank foot
        box((0.09, 0.09, H), (0, 0.06, H / 2), mat(WOOD, 0.85, wear=0.25), bevel=0.006)            # timber post
        for sx in (-1, 1):
            tube((sx * 0.16, 0.06 + sx * 0.04, 0.05), (0, 0.06, H * 0.55), 0.015, mat(WOOD, 0.85))  # braces
        box((0.14, 0.10, 0.10), (0, 0.06, H + 0.04), mat("#3b4a3e", 0.6, wear=0.3), bevel=0.01)    # wiper-motor box
        cyl(0.05, 0.02, (0.08, 0.06, H + 0.04), mat(BLACK, 0.6), axis="X")                         # bike sprocket
        tube((0.09, 0.03, H + 0.02), (0.09, 0.03, H + 0.20), 0.004, mat("#202124", 0.6))            # chain
    else:
        pad = mat(CONCRETE, 0.9, wear=0.2)
        steel = mat(STEEL if tier == "salvaged" else GALV, 0.45, wear=0.1, rust=rust)
        box((0.40, 0.40, 0.08) if tier == "workshop" else (0.30, 0.30, 0.12), (0, 0.06, 0.04 if tier == "workshop" else 0.06), pad, bevel=0.01)
        cyl(0.055 if tier == "workshop" else 0.045, H, (0, 0.06, H / 2 + 0.04), steel, segs=20)     # post
        cyl(0.08, 0.10, (0, 0.06, H + 0.06), mat("#3b3e43", 0.5, rust=rust), segs=24)              # slewing drive
        box((0.10, 0.08, 0.08), (0.10, 0.06, H + 0.04), mat("#3b3e43", 0.5, rust=rust), bevel=0.01)  # motor
        if tier == "workshop":
            box((0.08, 0.05, 0.10), (0, 0.10, 0.36), mat("#d6d8db", 0.5), bevel=0.008)            # control box on the post
            light((0, 0.073, 0.38), True, "#3ee06a")
    with group((0, 0.06, H + 0.12), (math.radians(36), 0, 0)):
        tube((-n * w / 2 - 0.02, 0, -0.04), (n * w / 2 + 0.02, 0, -0.04), 0.02,
             mat(STEEL if tier != "makeshift" else WOOD, 0.5, rust=rust))                          # torque tube
        for yy in (-l * 0.32, l * 0.32):
            box((n * w + 0.04, 0.03, 0.025), (0, yy, -0.03), mat(STEEL if tier != "makeshift" else WOOD, 0.5, rust=rust), bevel=0.004)
        panel_bank(n, w, l, tier, state, rng)
        if tier == "workshop":                                                                     # sun sensor on the frame
            box((0.04, 0.04, 0.05), (n * w / 2 - 0.02, l / 2 + 0.03, 0.02), mat("#202225", 0.4), bevel=0.004)
            cyl(0.012, 0.012, (n * w / 2 - 0.02, l / 2 + 0.03, 0.05), mat("#9fd8ff", 0.2, emit=0.6))


# ------------------------------------------------------------------ the 2x2 array
XL = {  # columns of modules, rows up the slope, module width, length
    "makeshift": (4, 2, 0.40, 0.80),
    "salvaged": (4, 2, 0.42, 0.82),
    "workshop": (6, 2, 0.28, 0.86),
}


def xl_array(tier, state):
    """Four frames' worth of modules on one long welded rack, across a 2x2 footprint, tilted toward the front."""
    rng = random.Random(hash(("xl", tier)) & 0xffff)
    cols, rws, w, l = XL[tier]
    a = math.radians(30)
    L = rws * l + 0.03
    run, rise = L * math.cos(a), L * math.sin(a)
    y0, z0 = -run / 2, 0.14
    rust = tier_rust(tier, state)
    span = cols * w + (cols - 1) * 0.025
    if tier == "makeshift":
        wood = mat(WOOD, 0.85, wear=0.25)
        for sx in (-0.82, -0.27, 0.27, 0.82):
            box((0.12, run + 0.10, 0.05), (sx, 0, 0.025), mat(PLANK, 0.85, wear=0.25), bevel=0.006)   # sleepers
            box((0.05, 0.05, z0), (sx, y0, z0 / 2), wood, bevel=0.005)
            box((0.06, 0.06, z0 + rise), (sx, -y0, (z0 + rise) / 2), wood, bevel=0.005)
            tube((sx, y0 + 0.04, 0.06), (sx, -y0 - 0.04, z0 + rise * 0.8), 0.02, wood)
        tube((-0.82, -y0, 0.35), (0.82, -y0, 0.35), 0.02, wood)
        tube((-0.82, -y0, 0.06), (0.82, -y0 + 0.0, z0 + rise * 0.7), 0.014, wood)                    # cross brace
    else:
        steel = mat(STEEL if tier == "salvaged" else GALV, 0.45, wear=0.12 if tier == "salvaged" else 0.04, rust=rust)
        pad = mat(CONCRETE, 0.9, wear=0.2)
        for sx in (-0.80, -0.27, 0.27, 0.80):
            box((0.14, 0.14, 0.06), (sx, y0 + 0.02, 0.03), pad, bevel=0.008)                          # footings
            box((0.14, 0.14, 0.06), (sx, -y0 - 0.02, 0.03), pad, bevel=0.008)
            tube((sx, y0 + 0.02, 0.06), (sx, y0 + 0.02, z0), 0.022, steel)
            tube((sx, -y0 - 0.02, 0.06), (sx, -y0 - 0.02, z0 + rise - 0.02), 0.024, steel)
            tube((sx, y0 + 0.06, 0.07), (sx, -y0 - 0.06, z0 + rise * 0.65), 0.014, steel)
        tube((-0.80, -y0 - 0.02, 0.40), (0.80, -y0 - 0.02, 0.40), 0.016, steel)                      # back rail
        tube((-0.80, -y0 - 0.02, 0.12), (0.27, -y0 - 0.02, z0 + rise * 0.8), 0.010, steel)            # X bracing
        tube((0.80, -y0 - 0.02, 0.12), (-0.27, -y0 - 0.02, z0 + rise * 0.8), 0.010, steel)
    with group((0, 0, z0 + rise / 2 + 0.03), (a, 0, 0)):
        fr = mat(WOOD if tier == "makeshift" else (STEEL if tier == "salvaged" else GALV), 0.5, rust=rust)
        for yy in (-L * 0.38, -L * 0.12, L * 0.12, L * 0.38):
            box((span + 0.08, 0.035, 0.03), (0, yy, -0.045), fr, bevel=0.004)                         # purlins
        for r in range(rws):
            with group((0, -L / 2 + l / 2 + r * (l + 0.03), 0)):
                panel_bank(cols, w, l, tier, state if (state != "cracked" or r == 0) else "clear", rng)
        junction_box(span / 2 - 0.1, 0, -0.07, tier)


# ------------------------------------------------------------------ batteries and banks
def car_battery(x, y, z, rot=0.0, scale=1.0):
    """A car battery standing at (x, y) on height z: black case, label, two terminals."""
    w, d, h = 0.24 * scale, 0.16 * scale, 0.17 * scale
    with group((x, y, z), (0, 0, rot)):
        box((w, d, h), (0, 0, h / 2), mat("#1e1f22", 0.55), bevel=0.008)
        box((w * 0.98, d * 0.98, 0.012), (0, 0, h + 0.004), mat("#2a2c30", 0.5), bevel=0.003)         # lid
        box((w * 0.6, 0.003, h * 0.45), (0, -d / 2 - 0.001, h * 0.5), mat("#d8d6cf", 0.6), bevel=0)   # label
        box((w * 0.18, 0.004, h * 0.12), (-w * 0.16, -d / 2 - 0.002, h * 0.6), mat("#c8302a", 0.5), bevel=0)
        cyl(0.014 * scale, 0.025, (-w * 0.32, 0, h + 0.02), mat("#c8302a", 0.4), segs=12)              # + terminal
        cyl(0.014 * scale, 0.025, (w * 0.32, 0, h + 0.02), mat(BLACK, 0.4), segs=12)                   # - terminal


def jumper(a, b, red=True):
    tube(a, b, 0.008, mat("#b02a2a" if red else "#202124", 0.6))


def ground_bank(tier, n):
    """A floor bank holding `n` cells: Makeshift crate (3), Salvaged rack (6), Workshop cabinet (8, LEDs show them)."""
    if tier == "makeshift":
        plank = mat(PLANK, 0.85, wear=0.3)
        wood = mat(WOOD, 0.85, wear=0.25)
        for yy in (-0.22, 0.0, 0.22):
            box((0.10, 0.52, 0.06), (0, 0, 0.03), wood, bevel=0.004) if yy == 0 else None
        for xx in (-0.36, 0.0, 0.36):
            box((0.08, 0.56, 0.06), (xx, 0, 0.03), wood, bevel=0.004)                               # pallet runners
        for i in range(5):
            box((0.84, 0.09, 0.025), (0, -0.22 + i * 0.11, 0.075), plank, bevel=0.003)              # deck boards
        box((0.84, 0.025, 0.16), (0, 0.27, 0.165), plank, bevel=0.003)                              # back board
        for sx in (-1, 1):
            box((0.025, 0.56, 0.12), (sx * 0.41, 0, 0.145), plank, bevel=0.003)                     # side boards
        pos = [(-0.26, 0.04), (0.0, 0.04), (0.26, 0.04)]
        for i in range(n):
            car_battery(pos[i][0], pos[i][1], 0.088)
        for i in range(n - 1):
            jumper((pos[i][0] + 0.077, pos[i][1], 0.29), (pos[i + 1][0] - 0.077, pos[i + 1][1], 0.29), red=i % 2 == 0)
        box((0.10, 0.04, 0.06), (0.32, 0.27, 0.30), mat("#3b4a3e", 0.6, wear=0.3), bevel=0.006)    # a fuse box nailed on
    elif tier == "salvaged":
        steel = mat(STEEL, 0.45, wear=0.15)
        shelf = mat("#6f7378", 0.5, wear=0.15)
        for sx in (-0.40, 0.40):
            for sy in (-0.20, 0.20):
                box((0.035, 0.035, 0.74), (sx, sy, 0.37), steel, bevel=0.004)                        # uprights
        for z in (0.06, 0.40):
            box((0.84, 0.44, 0.025), (0, 0, z), shelf, bevel=0.004)                                  # shelves
            box((0.84, 0.02, 0.04), (0, -0.22, z + 0.02), steel, bevel=0.003)                        # lips
        box((0.84, 0.44, 0.02), (0, 0, 0.74), shelf, bevel=0.004)                                    # top
        pos = [(-0.26, 0.0, 0.073), (0.0, 0.0, 0.073), (0.26, 0.0, 0.073),
               (-0.26, 0.0, 0.413), (0.0, 0.0, 0.413), (0.26, 0.0, 0.413)]
        for i in range(n):
            car_battery(*pos[i])
        for i in range(n - 1):
            if pos[i][2] == pos[i + 1][2]:
                jumper((pos[i][0] + 0.077, 0, pos[i][2] + 0.2), (pos[i + 1][0] - 0.077, 0, pos[i][2] + 0.2), red=i % 2 == 0)
        bus = mat(COPPER, 0.35)
        box((0.03, 0.02, 0.60), (0.41, 0.21, 0.42), bus, bevel=0.003)                                # bus bars down the side
        box((0.03, 0.02, 0.60), (0.37, 0.21, 0.42), mat("#202124", 0.6), bevel=0.003)
    else:
        grey = mat("#b9bdc2", 0.5, wear=0.06)
        dark = mat("#2e3133", 0.6)
        box((0.86, 0.50, 0.06), (0, 0, 0.03), mat(CONCRETE, 0.9, wear=0.2), bevel=0.006)             # plinth
        box((0.80, 0.44, 0.80), (0, 0, 0.46), grey, bevel=0.014)                                     # cabinet
        box((0.82, 0.46, 0.03), (0, 0, 0.875), mat("#a6aaaf", 0.5), bevel=0.008)                     # lid
        box((0.36, 0.012, 0.66), (-0.19, -0.222, 0.46), mat("#c3c7cc", 0.5, wear=0.05), bevel=0.004)  # doors
        box((0.36, 0.012, 0.66), (0.19, -0.222, 0.46), mat("#c3c7cc", 0.5, wear=0.05), bevel=0.004)
        box((0.012, 0.01, 0.08), (-0.02, -0.232, 0.46), dark, bevel=0.003)                           # handles
        box((0.012, 0.01, 0.08), (0.02, -0.232, 0.46), dark, bevel=0.003)
        for i in range(6):                                                                            # side louvres
            box((0.012, 0.30, 0.02), (0.405, 0, 0.24 + i * 0.05), dark, rot=(0, -0.6, 0), bevel=0.002)
        box((0.30, 0.008, 0.07), (-0.19, -0.231, 0.74), mat("#202225", 0.4), bevel=0.003)            # cell gauge window
        for i in range(8):
            on = i < n
            light((-0.31 + i * 0.034, -0.236, 0.74), on, "#3ee06a" if on else "#2a2f2a", size=(0.022, 0.008, 0.045))
        box((0.10, 0.006, 0.07), (0.25, -0.231, 0.74), mat("#e5c22a", 0.5), bevel=0.002)             # warning label
        cyl(0.02, 0.06, (0.30, 0.0, 0.92), dark, segs=12)                                             # vent cap


def wall_bank(tier, n):
    """A wall bank holding `n` cells, its back against the wall behind it (+Y)."""
    back = 0.5
    if tier == "makeshift":
        wood = mat(WOOD, 0.85, wear=0.25)
        plank = mat(PLANK, 0.85, wear=0.3)
        z = 0.52
        box((0.70, 0.30, 0.03), (0, back - 0.16, z), plank, bevel=0.004)                             # shelf board
        box((0.70, 0.03, 0.10), (0, back - 0.015, z + 0.02), wood, bevel=0.004)                      # batten
        for sx in (-0.28, 0.28):                                                                       # brackets
            box((0.03, 0.03, 0.22), (sx, back - 0.015, z - 0.12), wood, bevel=0.003)
            tube((sx, back - 0.03, z - 0.20), (sx, back - 0.26, z - 0.02), 0.012, wood)
        pos = [(-0.15, back - 0.17), (0.15, back - 0.17)]
        for i in range(n):
            car_battery(pos[i][0], pos[i][1], z + 0.015)
        if n == 2:
            jumper((-0.073, back - 0.17, z + 0.215), (0.073, back - 0.17, z + 0.215))
        tube((0.30, back - 0.03, z + 0.05), (0.30, back - 0.03, 0.05), 0.008, mat(BLACK, 0.7))       # lead down the wall
    elif tier == "salvaged":
        steel = mat(STEEL, 0.45, wear=0.15)
        z = 0.48
        box((0.82, 0.30, 0.025), (0, back - 0.16, z), steel, bevel=0.004)                            # tray
        box((0.82, 0.02, 0.06), (0, back - 0.30, z + 0.03), steel, bevel=0.003)                      # front lip
        for sx in (-0.41, 0.41):
            box((0.02, 0.30, 0.10), (sx, back - 0.16, z + 0.05), steel, bevel=0.003)
            tube((sx * 0.95, back - 0.02, z - 0.22), (sx * 0.95, back - 0.28, z - 0.01), 0.012, steel)  # struts
        box((0.82, 0.02, 0.30), (0, back - 0.01, z + 0.15), mat("#6f7378", 0.5, wear=0.15), bevel=0.004)  # back plate
        for i in range(n):
            car_battery(-0.26 + i * 0.26, back - 0.16, z + 0.013)
        for i in range(n - 1):
            jumper((-0.26 + i * 0.26 + 0.077, back - 0.16, z + 0.21), (-0.26 + (i + 1) * 0.26 - 0.077, back - 0.16, z + 0.21), i % 2 == 0)
        box((0.025, 0.015, 0.45), (0.36, back - 0.025, 0.25), mat(COPPER, 0.35), bevel=0.003)          # bus down
    else:
        grey = mat("#b9bdc2", 0.5, wear=0.06)
        dark = mat("#2e3133", 0.6)
        z = 0.38
        box((0.78, 0.26, 0.48), (0, back - 0.14, z + 0.24), grey, bevel=0.012)                       # wall cabinet
        box((0.80, 0.27, 0.025), (0, back - 0.14, z + 0.49), mat("#a6aaaf", 0.5), bevel=0.006)
        box((0.72, 0.012, 0.40), (0, back - 0.273, z + 0.24), mat("#c3c7cc", 0.5, wear=0.05), bevel=0.004)
        box((0.012, 0.01, 0.07), (0.30, back - 0.282, z + 0.24), dark, bevel=0.003)
        box((0.20, 0.008, 0.06), (-0.18, back - 0.281, z + 0.38), mat("#202225", 0.4), bevel=0.003)
        for i in range(4):
            on = i < n
            light((-0.255 + i * 0.05, back - 0.286, z + 0.38), on, "#3ee06a" if on else "#2a2f2a", size=(0.03, 0.008, 0.04))
        for i in range(5):
            box((0.40, 0.012, 0.016), (0.04, back - 0.282, z + 0.10 + i * 0.03), dark, rot=(0.6, 0, 0), bevel=0.002)
        tube((0.30, back - 0.03, z), (0.30, back - 0.03, 0.05), 0.012, mat("#606468", 0.5))           # conduit down


# ------------------------------------------------------------------ the wall power gauge
GAUGE_LED = {"off": None, "low": "#e0402a", "mid": "#eaa62a", "full": "#3ee06a"}
GAUGE_NEEDLE = {"off": -1.1, "low": -0.75, "mid": 0.0, "full": 0.75}       # radians from straight up


def gauge(state):
    """A small steel panel with a round dial, its needle and a lamp showing the charge band, back against the wall (+Y)."""
    back = 0.5
    z = 0.62
    steel = mat("#8d9196", 0.45, wear=0.08)
    face = mat("#e4e7dc", 0.6)
    dark = mat("#26292b", 0.6)
    box((0.30, 0.04, 0.24), (0, back - 0.02, z), steel, bevel=0.008)                                 # back plate
    cyl(0.085, 0.02, (0, back - 0.05, z + 0.02), steel, axis="Y")                                    # dial bezel
    cyl(0.075, 0.006, (0, back - 0.061, z + 0.02), face, axis="Y")                                   # dial face
    ang = GAUGE_NEEDLE[state]
    tip = (math.sin(ang) * 0.06, back - 0.066, z + 0.02 + math.cos(ang) * 0.06)
    tube((0, back - 0.066, z + 0.02), tip, 0.004, mat("#b3261e", 0.4))                              # needle
    box((0.18, 0.008, 0.035), (0, back - 0.044, z - 0.085), dark, bevel=0.003)                       # readout strip
    col = GAUGE_LED[state]
    light((0.11, back - 0.046, z + 0.08), col is not None, col or "#2a2f2a", size=(0.025, 0.01, 0.025))
    tube((0.12, back - 0.02, z - 0.12), (0.12, back - 0.02, 0.05), 0.008, mat(BLACK, 0.7))           # lead down the wall


# ------------------------------------------------------------------ charge controllers
def controller(tier, state):
    """The charge controller, front (-Y): Makeshift is a board of scavenged gear on legs, Workshop a steel cabinet."""
    on = state == "on"
    if tier == "makeshift":
        wood = mat(WOOD, 0.85, wear=0.25)
        board = mat("#a07a4e", 0.8, wear=0.25)
        for sx in (-0.22, 0.22):
            box((0.05, 0.05, 0.86), (sx, 0.06, 0.43), wood, bevel=0.005)                             # legs
            box((0.05, 0.24, 0.04), (sx, 0.06, 0.02), wood, bevel=0.004)                             # feet
        box((0.56, 0.03, 0.56), (0, 0.03, 0.58), board, bevel=0.006)                                 # plywood board
        box((0.22, 0.12, 0.16), (-0.12, -0.04, 0.70), mat("#c84a1e", 0.5, wear=0.2), bevel=0.012)   # the old battery charger
        box((0.10, 0.006, 0.05), (-0.12, -0.103, 0.74), mat("#9fd8a0" if on else "#2c3a2e", 0.3, emit=3.5 if on else 0), bevel=0)  # its meter, lit
        box((0.16, 0.06, 0.10), (0.13, -0.01, 0.75), mat("#2a2c30", 0.6), bevel=0.008)              # salvaged LCD box
        box((0.12, 0.006, 0.05), (0.13, -0.043, 0.76), mat("#7de08e" if on else "#24302a", 0.3, emit=4.0 if on else 0), bevel=0)
        box((0.18, 0.05, 0.08), (0.08, -0.01, 0.48), mat("#3a3c40", 0.6), bevel=0.006)              # fuse block
        for i in range(4):
            cyl(0.012, 0.03, (0.01 + i * 0.045, -0.04, 0.48), mat("#d9a42a" if i % 2 else "#c8302a", 0.4), axis="Y", segs=10)
        with group((-0.15, -0.02, 0.46), (0, 0, 0)):                                                 # knife switch
            box((0.10, 0.03, 0.04), (0, 0, 0), mat("#2a2c30", 0.6), bevel=0.004)
            box((0.012, 0.012, 0.10), (0, -0.02, 0.05 if on else 0.02), mat(COPPER, 0.35), rot=(0 if on else 1.2, 0, 0), bevel=0)
        for k in range(3):                                                                             # cables down
            tube((-0.20 + k * 0.05, 0.02, 0.32), (-0.24 + k * 0.08, 0.12, 0.02), 0.009, mat("#b02a2a" if k == 0 else BLACK, 0.6))
        light((0.22, -0.02, 0.84), on)
    else:
        grey = mat("#d2d5d9", 0.5, wear=0.04)
        dark = mat("#2b2d31", 0.5)
        box((0.50, 0.30, 0.06), (0, 0.04, 0.03), mat(CONCRETE, 0.9, wear=0.2), bevel=0.006)
        for sx in (-0.18, 0.18):
            box((0.04, 0.04, 0.30), (sx, 0.04, 0.21), dark, bevel=0.004)                             # stand
        box((0.48, 0.26, 0.56), (0, 0.04, 0.64), grey, bevel=0.014)                                  # cabinet
        box((0.50, 0.28, 0.025), (0, 0.04, 0.93), mat("#b8bbc0", 0.5), bevel=0.006)
        box((0.24, 0.008, 0.13), (-0.08, -0.094, 0.79), mat("#101215", 0.3), bevel=0.004)            # the big screen
        box((0.22, 0.004, 0.11), (-0.08, -0.099, 0.79), mat("#5ad0ff" if on else "#151a20", 0.25, emit=4.5 if on else 0), bevel=0)
        if on:
            for i in range(4):                                                                         # bars on the screen
                box((0.02, 0.003, 0.02 + 0.015 * i), (-0.16 + i * 0.035, -0.102, 0.75 + 0.0075 * i), mat("#e8fbff", 0.3, emit=5.0), bevel=0)
        for i in range(5):                                                                             # breaker row
            box((0.03, 0.03, 0.06), (-0.16 + i * 0.05, -0.098, 0.58), mat("#2a2c30", 0.5), bevel=0.003)
            box((0.012, 0.01, 0.02), (-0.16 + i * 0.05, -0.115, 0.59 if on else 0.57), mat("#e6e7e8", 0.4), bevel=0)
        box((0.12, 0.006, 0.05), (0.15, -0.096, 0.83), mat("#e5c22a", 0.5), bevel=0.002)             # label
        light((0.15, -0.10, 0.76), on)
        light((0.19, -0.10, 0.76), on, "#ffb02a")
        for i in range(7):                                                                             # heat-sink fins on the side
            box((0.03, 0.20, 0.008), (0.255, 0.04, 0.44 + i * 0.05), mat("#9ea2a6", 0.4), bevel=0)
        tube((0.12, 0.10, 0.36), (0.12, 0.10, 0.06), 0.02, mat("#606468", 0.5))                      # conduit
        tube((-0.12, 0.10, 0.36), (-0.12, 0.10, 0.06), 0.02, mat("#606468", 0.5))


# ------------------------------------------------------------------ transformer
def transformer(state):
    """A pad-mount transformer: green steel box on a concrete pad, cooling fins on the sides, a lamp that shows it live."""
    on = state == "on"
    green = mat("#3f6b4a", 0.55, wear=0.12)
    box((0.92, 0.80, 0.08), (0, 0, 0.04), mat(CONCRETE, 0.9, wear=0.2), bevel=0.008)
    box((0.66, 0.54, 0.62), (0, 0.02, 0.39), green, bevel=0.016)
    box((0.68, 0.56, 0.03), (0, 0.02, 0.715), mat("#36603f", 0.55, wear=0.12), bevel=0.01)
    for sx in (-1, 1):
        for i in range(6):
            box((0.10, 0.012, 0.46), (sx * 0.38, -0.18 + i * 0.07, 0.36), mat("#3a6344", 0.55, wear=0.12), bevel=0.003)  # fins
    box((0.50, 0.012, 0.46), (0, -0.252, 0.38), mat("#46745a", 0.55, wear=0.1), bevel=0.004)          # door
    box((0.012, 0.01, 0.08), (0.20, -0.262, 0.40), mat(BLACK, 0.5), bevel=0.003)
    bm = bmesh.new()                                                                                 # warning triangle
    v = [bm.verts.new(p) for p in ((-0.08, -0.26, 0.46), (0.08, -0.26, 0.46), (0.0, -0.26, 0.60))]
    bm.faces.new(v)
    _obj("warn", bm, mat("#e5c22a", 0.5))
    box((0.012, 0.004, 0.07), (0.0, -0.262, 0.51), mat(BLACK, 0.5), rot=(0, 0.35, 0), bevel=0)        # the bolt
    for x in (-0.18, 0.0, 0.18):                                                                     # bushings on top
        cyl(0.03, 0.08, (x, 0.12, 0.77), mat("#6e4a2e", 0.4), segs=14)
        cyl(0.038, 0.012, (x, 0.12, 0.76), mat("#6e4a2e", 0.4), segs=14)
    light((-0.22, -0.262, 0.62), on, "#ffb02a", size=(0.035, 0.012, 0.035))


# ------------------------------------------------------------------ solar lamps
def lamp(mount, tier, state):
    """Solar lamps: the panel faces the front (-Y); a street lamp's head reaches forward over it."""
    on = state == "on"
    glow = mat("#ffe2b0", 0.3, emit=9.0) if on else mat("#d9d6cc", 0.3)
    if mount == "garden":
        if tier == "makeshift":
            box((0.03, 0.03, 0.42), (0, 0, 0.21), mat(WOOD, 0.85, wear=0.25), bevel=0.003)          # stake
            cyl(0.07, 0.14, (0, 0, 0.48), mat("#cfe4e8", 0.15, alpha=0.55 if not on else 0.9), segs=20)  # a glass jar
            cyl(0.03, 0.06, (0, 0, 0.47), glow, segs=12)                                                # the bulb in it
            cyl(0.075, 0.02, (0, 0, 0.56), mat("#b9bec4", 0.5, wear=0.2), segs=20)                     # the lid
            with group((0, 0, 0.575), (math.radians(20), 0, 0)):
                box((0.11, 0.11, 0.008), (0, 0, 0), mat("#2b4a86", 0.25, spec=0.35), bevel=0)          # its tiny panel
            box((0.02, 0.10, 0.004), (0, 0, 0.55), mat(TAPE, 0.8), bevel=0)                             # tape
        else:
            black = mat("#26282c", 0.45, wear=0.05)
            box((0.14, 0.14, 0.02), (0, 0, 0.01), mat(CONCRETE, 0.9), bevel=0.004)
            cyl(0.045, 0.40, (0, 0, 0.21), black, segs=20)                                              # bollard
            cyl(0.058, 0.10, (0, 0, 0.45), mat("#f4f1ea", 0.2, emit=8.0) if on else mat("#d9dde0", 0.2, alpha=0.8), segs=24)  # lens
            cyl(0.065, 0.025, (0, 0, 0.51), black, segs=24)
            with group((0, 0, 0.53), (math.radians(15), 0, 0)):
                box((0.13, 0.13, 0.012), (0, 0, 0), mat("#141826", 0.2, spec=0.4), bevel=0.002)       # mono panel
                box((0.135, 0.135, 0.008), (0, 0, -0.008), mat("#c9cdd2", 0.4), bevel=0.002)
    else:
        H = 2.25
        if tier == "makeshift":
            wood = mat(WOOD, 0.85, wear=0.25)
            box((0.34, 0.34, 0.06), (0, 0.04, 0.03), mat(CONCRETE, 0.9, wear=0.3), bevel=0.01)       # a cinder block foot
            box((0.10, 0.10, H), (0, 0.04, H / 2), wood, bevel=0.006)                                  # timber pole
            box((0.18, 0.12, 0.16), (0, -0.04, 0.95), mat("#2a2c30", 0.6, wear=0.2), bevel=0.01)      # battery box, strapped
            box((0.19, 0.13, 0.015), (0, -0.04, 0.98), mat(TAPE, 0.8, wear=0.2), bevel=0)
            box((0.19, 0.13, 0.015), (0, -0.04, 0.90), mat(TAPE, 0.8, wear=0.2), bevel=0)
            with group((0, 0.10, H + 0.02), (math.radians(35), 0, 0)):
                module(0, 0, 0.40, 0.46, "makeshift", "clear", random.Random(7), cols=4, rows=4)
            tube((0, 0.0, H - 0.20), (0, -0.30, H - 0.08), 0.015, mat(STEEL, 0.5, wear=0.2))         # bent pipe arm
            cyl(0.10, 0.08, (0, -0.33, H - 0.15), mat("#3d5874", 0.5, wear=0.25), radius2=0.04, segs=20)  # bucket shade
            ball(0.04, (0, -0.33, H - 0.20), glow)
        else:
            steel = mat("#5d6166", 0.45, wear=0.05)
            box((0.26, 0.26, 0.03), (0, 0.04, 0.015), mat(CONCRETE, 0.9), bevel=0.006)
            box((0.18, 0.18, 0.02), (0, 0.04, 0.04), steel, bevel=0.004)                               # base plate
            cyl(0.045, H, (0, 0.04, H / 2), steel, radius2=0.032, segs=20)                            # tapered pole
            box((0.14, 0.09, 0.22), (0, -0.015, 1.05), mat("#c9ccd0", 0.5, wear=0.04), bevel=0.01)    # battery cabinet
            light((0.03, -0.062, 1.12), True, "#3ee06a")
            with group((0, 0.12, H + 0.04), (math.radians(30), 0, 0)):
                module(0, 0, 0.52, 0.62, "workshop", "clear", random.Random(9), cols=4, rows=6)
            tube((0, 0.04, H - 0.12), (0, -0.38, H - 0.04), 0.022, steel)                              # arm
            box((0.30, 0.13, 0.045), (0, -0.50, H - 0.05), steel, bevel=0.012)                        # LED head
            box((0.26, 0.10, 0.008), (0, -0.50, H - 0.077), glow, bevel=0)


# ------------------------------------------------------------------ inventory-only items
def handbook(colour, emblem):
    """A thick manual lying flat: cover, page block and a solar or gear emblem."""
    box((0.56, 0.74, 0.05), (0, 0, 0.03), mat("#ecebe4", 0.8), bevel=0.006)                         # pages
    box((0.58, 0.76, 0.012), (0, 0, 0.062), mat(colour, 0.6, wear=0.1), bevel=0.004)                # cover
    box((0.04, 0.76, 0.07), (-0.29, 0, 0.03), mat(colour, 0.6, wear=0.1), bevel=0.006)              # spine
    if emblem == "sun":
        cyl(0.10, 0.006, (0.0, 0.10, 0.07), mat("#f2c23a", 0.4), segs=24)
        for k in range(8):
            a = k * math.pi / 4
            box((0.02, 0.07, 0.006), (math.sin(a) * 0.15, 0.10 + math.cos(a) * 0.15, 0.07), mat("#f2c23a", 0.4), rot=(0, 0, -a), bevel=0)
        box((0.28, 0.12, 0.006), (0.0, -0.18, 0.07), mat("#2b4a86", 0.3), bevel=0)
    else:
        cyl(0.13, 0.006, (0.0, 0.05, 0.07), mat("#d6d8db", 0.4), segs=24)
        for k in range(10):
            a = k * math.pi / 5
            box((0.04, 0.05, 0.006), (math.sin(a) * 0.15, 0.05 + math.cos(a) * 0.15, 0.07), mat("#d6d8db", 0.4), rot=(0, 0, -a), bevel=0)
        cyl(0.045, 0.008, (0.0, 0.05, 0.072), mat(colour, 0.6), segs=16)
        box((0.30, 0.06, 0.006), (0.0, -0.24, 0.07), mat("#e5c22a", 0.5), bevel=0)


def icon_list():
    out = []
    for tier in THREE:
        T = tier.capitalize()
        out.append(("DazedArray" + T, lambda t=tier: static_array(t, "clear"), 1.15))
        out.append(("DazedTracker" + T, lambda t=tier: tracker(t, "clear"), 1.1))
        out.append(("DazedArrayXL" + T, lambda t=tier: xl_array(t, "clear"), 0.62))
        out.append(("DazedBank" + T, lambda t=tier: ground_bank(t, BANK_CELLS["ground"][t]), 1.2))
        out.append(("DazedWallBank" + T, lambda t=tier: wall_bank(t, BANK_CELLS["wall"][t]), 1.3))
    for tier in ("makeshift", "workshop"):
        T = tier.capitalize()
        out.append(("DazedController" + T, lambda t=tier: controller(t, "on"), 1.3))
        out.append(("DazedGardenLamp" + T, lambda t=tier: lamp("garden", t, "off"), 2.2))
        out.append(("DazedStreetLamp" + T, lambda t=tier: lamp("street", t, "off"), 0.6))
    out.append(("DazedTransformer", lambda: transformer("off"), 1.1))
    out.append(("DazedPowerGauge", lambda: gauge("full"), 2.6))
    out.append(("DazedPowerManual", lambda: handbook("#2f5aa0", "sun"), 1.6))
    out.append(("DazedPowerManualAdv", lambda: handbook("#3a3c40", "gear"), 1.6))
    return out


# ------------------------------------------------------------------ rendering
_mask = None


def mask_material():
    """White where a surface stands over the square under the camera, black elsewhere (world position)."""
    global _mask
    if _mask:
        return _mask
    m = bpy.data.materials.new("dp_mask")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    tests = []
    for axis in ("X", "Y"):
        ab = nt.nodes.new("ShaderNodeMath"); ab.operation = "ABSOLUTE"
        nt.links.new(sep.outputs[axis], ab.inputs[0])
        lt = nt.nodes.new("ShaderNodeMath"); lt.operation = "LESS_THAN"; lt.inputs[1].default_value = 0.5
        nt.links.new(ab.outputs[0], lt.inputs[0])
        tests.append(lt)
    both = nt.nodes.new("ShaderNodeMath"); both.operation = "MULTIPLY"
    nt.links.new(tests[0].outputs[0], both.inputs[0]); nt.links.new(tests[1].outputs[0], both.inputs[1])
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(both.outputs[0], em.inputs["Strength"])
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    _mask = m
    return m


_count = [0, time.time()]


def shoot(path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    _count[0] += 1
    if _count[0] % 10 == 0:
        print("DP render: %d images, %.0f s" % (_count[0], time.time() - _count[1]))


def shoot_mask(path):
    vl = bpy.context.view_layer
    keep = scene.cycles.samples
    vl.material_override = mask_material()
    scene.cycles.samples = 16
    try:
        shoot(path)
    finally:
        vl.material_override = None
        scene.cycles.samples = keep


def pose(facing, offset=(0.0, 0.0)):
    SUBJECT.location = (offset[0], offset[1], 0)
    SUBJECT.rotation_euler = Euler((0, 0, math.radians(FACINGS[facing][1])), "XYZ")


def build(kind, mount, tier, state):
    if kind == "array":
        {"ground": static_array, "tracker": tracker, "xl": xl_array}[mount](tier, state)
    elif kind == "bank":
        (ground_bank if mount == "ground" else wall_bank)(tier, int(state[1:]))
    elif kind == "controller":
        controller(tier, state)
    elif kind == "transformer":
        transformer(state)
    elif kind == "lamp":
        lamp(mount, tier, state)
    elif kind == "gauge":
        gauge(state)


FAMILY_OF = {("array", "ground"): "arrays", ("array", "tracker"): "trackers", ("array", "xl"): "xl",
             ("bank", "ground"): "banks", ("bank", "wall"): "walls", ("controller", "ground"): "controllers",
             ("transformer", "ground"): "transformer", ("lamp", "garden"): "lamps", ("lamp", "street"): "lamps",
             ("gauge", "wall"): "gauges"}


def render_family(fam, facings=("E", "S", "W", "N"), out_dir=None):
    """Every row of one family, all facings (and all four pieces of a 2x2)."""
    done = 0
    seen = set()
    for (kind, mount, tier, state, piece) in ROWS:
        if FAMILY_OF.get((kind, mount)) != fam or (kind, mount, tier, state) in seen:
            continue
        seen.add((kind, mount, tier, state))
        clear_model()
        build(kind, mount, tier, state)
        out = out_dir or os.path.join(OUT, fam)
        os.makedirs(out, exist_ok=True)
        pieces = 4 if mount == "xl" else 1
        for facing in facings:
            for p in range(1, pieces + 1):
                dx, dy = PIECE_OFFSET[p]
                pose(facing, (0.5 - dx, dy - 0.5) if pieces > 1 else (0.0, 0.0))
                idx = index_of(kind, mount, tier, state, facing, p)
                shoot(os.path.join(out, "%d.png" % idx))
                if pieces > 1:
                    shoot_mask(os.path.join(out, "%d_m.png" % idx))
                done += 1
    pose("S")
    return done


def render_preview():
    """One S-facing look at each model and state (whole 2x2 framed), at low samples, for checking the style."""
    out = os.path.join(OUT, "preview")
    os.makedirs(out, exist_ok=True)
    keep = scene.cycles.samples
    scene.cycles.samples = min(keep, 64)
    picks = []
    for t in THREE:
        picks += [("array", "ground", t, s) for s in ("clear", "snow", "cracked")]
        picks += [("array", "tracker", t, "clear"), ("array", "xl", t, "clear")]
        picks += [("bank", "ground", t, "c%d" % BANK_CELLS["ground"][t]), ("bank", "wall", t, "c%d" % BANK_CELLS["wall"][t])]
    picks += [("bank", "ground", "salvaged", "c2"), ("controller", "ground", "makeshift", "on"), ("controller", "ground", "workshop", "on"),
              ("controller", "ground", "workshop", "off"), ("transformer", "ground", "standard", "on")]
    for m in ("garden", "street"):
        for t in ("makeshift", "workshop"):
            picks += [("lamp", m, t, "on")]
    for (kind, mount, tier, state) in picks:
        clear_model()
        build(kind, mount, tier, state)
        if mount == "xl":
            SUBJECT.scale = (0.5, 0.5, 0.5)
        pose("S")
        shoot(os.path.join(out, "%s_%s_%s_%s.png" % (kind, mount, tier, state)))
        SUBJECT.scale = (1, 1, 1)
    scene.cycles.samples = keep
    return len(picks)


def render_icons(names=None):
    out = os.path.join(OUT, "icons")
    os.makedirs(out, exist_ok=True)
    n = 0
    for name, fn, scale in icon_list():
        if names and name not in names:
            continue
        clear_model(); fn()
        SUBJECT.location = (0, 0, 0)
        SUBJECT.rotation_euler = Euler((0, 0, math.radians(15)), "XYZ")
        SUBJECT.scale = (scale, scale, scale)
        shoot(os.path.join(out, name + ".png"))
        n += 1
    SUBJECT.scale = (1, 1, 1)
    pose("S")
    return n


ALL = ["arrays", "trackers", "xl", "banks", "walls", "controllers", "transformer", "lamps", "gauges", "icons"]
fams = ALL if "all" in FAMILIES else FAMILIES
total = 0
for fam in fams:
    if fam == "preview":
        total += render_preview()
    elif fam == "icons" or fam.startswith("icons:"):
        total += render_icons(fam.split(":", 1)[1].split(",") if ":" in fam else None)
    else:
        total += render_family(fam)
print("DP render: done, %d images for %s -> %s in %.0f s" % (total, ", ".join(fams), OUT, time.time() - _count[1]))
with open(os.path.join(OUT, "DONE_%s.txt" % "_".join(f.replace(":", "-") for f in fams)), "w") as fh:
    fh.write("%d images\n" % total)
