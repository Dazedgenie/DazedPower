"""Blender script: renders the analog charge board's parts (gauge face, needle, hub, battery case, toggles, number
wheel, isolator knob, lamps) top-down at 2x for media/ui/DazedPower/Board.
Run inside Blender (4.2+ / 5.x): BOARD_OUT = r"C:\\...\\board"; exec(open(path).read())
Optional globals: BOARD_OUT (default <this folder>/board), BOARD_SAMPLES (default 96), BOARD_ONLY (list of names).
"""
import bpy
import math
import os

OUT = globals().get("BOARD_OUT") or os.path.join(os.path.dirname(os.path.abspath(globals().get("__file__", "."))), "board")
SAMPLES = globals().get("BOARD_SAMPLES", 96)
ONLY = globals().get("BOARD_ONLY")
U = 0.1          # one base pixel in Blender units; renders come out at 2 px per base pixel


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


def mat(name, col, rough=0.5, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


def srgb(r, g, b):
    """sRGB 0-255 to the linear values Blender's colour inputs take."""
    def f(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b))


def put(obj, m):
    obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def cyl(r, depth, z, m, verts=96, x=0, y=0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r * U, depth=depth * U, location=(x * U, y * U, z * U))
    return put(bpy.context.object, m)


def box(w, h, d, z, m, x=0, y=0, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x * U, y * U, z * U))
    o = bpy.context.object
    o.scale = (w * U, h * U, d * U)
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel * U
        mod.segments = 4
    return put(o, m)


def torus(R, r, z, m, x=0, y=0):
    bpy.ops.mesh.primitive_torus_add(major_radius=R * U, minor_radius=r * U, major_segments=128, minor_segments=24,
                                     location=(x * U, y * U, z * U))
    return put(bpy.context.object, m)


def sphere(r, z, m, x=0, y=0, flat=1.0):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r * U, segments=48, ring_count=24, location=(x * U, y * U, z * U))
    o = bpy.context.object
    o.scale = (1, 1, flat)
    return put(o, m)


def setup(w, h):
    """Camera straight down over a w x h base-pixel part, a soft key from the upper left, transparent film."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = int(w * 2), int(h * 2)
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = max(w, h) * U
    co = bpy.data.objects.new("cam", cam)
    co.location = (0, 0, 100 * U)
    sc.collection.objects.link(co)
    sc.camera = co
    for name, loc, power, size in (("key", (-60, 80, 120), 9000, 80), ("fill", (70, -40, 90), 2500, 120)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = power * U * U
        ld.size = size * U
        lo = bpy.data.objects.new(name, ld)
        lo.location = tuple(v * U for v in loc)
        lo.rotation_euler = (0, 0, 0)
        d = lo.location
        lo.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        sc.collection.objects.link(lo)
    world = sc.world or bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.5, 0.5, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35


def shoot(name):
    os.makedirs(OUT, exist_ok=True)
    bpy.context.scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)


BLACK = lambda: mat("black", srgb(28, 28, 26), 0.35, 0.6)
CHROME = lambda: mat("chrome", srgb(200, 200, 196), 0.18, 1.0)


def gauge_face():
    setup(176, 176)
    torus(84, 4.5, 0, BLACK())
    cyl(82, 2, -2, mat("dial", srgb(238, 230, 208), 0.7))
    torus(79.5, 0.8, -0.6, mat("rim", srgb(150, 140, 120), 0.5, 0.3))


def needle():
    # Points right; the pivot is 14 px from the left edge, at mid height (see DP_BoardLayout's NEEDLE).
    setup(96, 16)
    red = mat("red", srgb(186, 38, 30), 0.35, 0.1)
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=3.2 * U, radius2=0.5 * U, depth=78 * U, location=(25 * U, 0, 0))
    o = bpy.context.object
    o.rotation_euler = (0, math.pi / 2, 0)
    o.scale = (0.5, 1, 1)
    put(o, red)
    box(14, 5, 2, 0, red, x=-37)


def hub():
    setup(20, 20)
    sphere(7.5, 0, BLACK(), flat=0.6)


def battery_case():
    setup(60, 170)
    box(58, 156, 10, 0, mat("case", srgb(38, 38, 36), 0.45, 0.2), y=-6, bevel=6)
    box(24, 10, 6, 0, BLACK(), y=77, bevel=2)
    box(46, 134, 4, 4, mat("window", srgb(24, 24, 23), 0.8), y=-6, bevel=2)


def toggle(up):
    setup(40, 56)
    box(36, 52, 4, 0, BLACK(), bevel=5)
    for y in (20, -20):
        cyl(2.6, 2, 2.4, CHROME(), verts=32, y=y)
    cyl(6, 3, 3, CHROME(), verts=48)
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=2.8 * U, depth=18 * U, location=(0, 0, 0))
    lever = put(bpy.context.object, CHROME())
    tilt = math.radians(55)
    lever.rotation_euler = (-tilt if up else tilt, 0, 0)
    lever.location = (0, (7 if up else -7) * U, 9 * U)
    sphere(3.6, 9 + 7 * math.cos(tilt), CHROME(), y=(7 + 7 * math.sin(tilt)) * (1 if up else -1))


def wheel():
    setup(22, 32)
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=20 * U, depth=20 * U, location=(0, 0, -12 * U))
    o = bpy.context.object
    o.rotation_euler = (0, math.pi / 2, 0)
    put(o, mat("drum", srgb(30, 30, 28), 0.55))


def isolator(on):
    setup(64, 64)
    cyl(30, 4, 0, mat("amber", srgb(226, 160, 52), 0.45))
    torus(30, 1.2, 1.5, mat("amberrim", srgb(180, 120, 36), 0.4))
    h = box(12, 56, 8, 6, mat("handle", srgb(192, 46, 36), 0.35), bevel=4)
    if not on:
        h.rotation_euler = (0, 0, math.pi / 2)


def lamp(kind):
    setup(24, 24)
    torus(10, 1.6, 0, CHROME())
    cols = {"green": srgb(92, 200, 84), "amber": srgb(240, 170, 50), "red": srgb(226, 60, 48)}
    if kind == "off":
        m = mat("glass", srgb(40, 38, 34), 0.25)
    else:
        m = mat("glass", cols[kind], 0.2, 0, emit=cols[kind], strength=1.2)
    sphere(9, 0, m, flat=0.55)


PARTS = {
    "gauge_face": gauge_face, "needle": needle, "hub": hub, "battery_case": battery_case,
    "toggle_up": lambda: toggle(True), "toggle_down": lambda: toggle(False), "wheel": wheel,
    "isolator_on": lambda: isolator(True), "isolator_off": lambda: isolator(False),
    "lamp_green": lambda: lamp("green"), "lamp_amber": lambda: lamp("amber"), "lamp_red": lambda: lamp("red"),
    "lamp_off": lambda: lamp("off"),
}

for name, build in PARTS.items():
    if ONLY and name not in ONLY:
        continue
    clear()
    build()
    shoot(name)
print("BOARD DONE", OUT)
