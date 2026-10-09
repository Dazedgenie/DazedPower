"""Dazed Power: seated pedalling animations (Bob_DazedPedal<Tier>), one per pedal generator tier.

Builds one crank turn procedurally on the vanilla Bob skeleton from the chair-sitting pose: hips on the saddle,
torso leaning to the bars, feet riding the pedals round a crank, hands on the grips. Writes the .X and its AnimSet
node into the mod. Runs in plain Python 3 with numpy, or inside Blender (4.2+/5.x) where it also sets up a preview.
    python3 tools/blender/dp_pedal.py
Optional globals: PZ_ANIMS (vanilla anims_X/Bob folder), MOD_MEDIA (mod's common/media folder).
"""
import os
import numpy as np

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__") or r"C:\Users\Shado\Zomboid\Workshop\DazedPower\tools\blender\x.py"))
PZ_ANIMS = globals().get("PZ_ANIMS") or os.environ.get("PZ_ANIMS") or r"D:\SteamSSD\steamapps\common\ProjectZomboid\media\anims_X\Bob"
MOD_MEDIA = globals().get("MOD_MEDIA") or os.path.normpath(os.path.join(_HERE, "..", "..", "Contents", "mods", "DazedPower", "common", "media"))

# The .X reader/writer, the pose rig and the Blender preview live in dp_pullstart.py; take them without running it.
_src = open(os.path.join(_HERE, "dp_pullstart.py"), encoding="utf-8").read().rsplit("\nrun()", 1)[0]
_lib = {"__file__": os.path.join(_HERE, "dp_pullstart.py"), "PZ_ANIMS": PZ_ANIMS, "MOD_MEDIA": MOD_MEDIA}
exec(_src, _lib)
XFile, Pose, write_x, rot, align = _lib["XFile"], _lib["Pose"], _lib["write_x"], _lib["rot"], _lib["align"]

FPS, TPS = 30, 4800
NFRAMES = 25                                   # 0..24 -> 0.8 s, one crank turn; the last frame closes the loop.

# Character space: +Y up, faces -Z, right side is -X; the game draws Bob GAME_SCALE times larger in tiles.
# RENDER_DROP is how much lower the rider draws than the pose says; both were fitted from in-game screenshots of all three bikes.
GAME_SCALE = 1.70
RENDER_DROP = 0.13
HIP_UP = 0.085                                 # hip joints above the saddle top, tiles
MAX_LEAN = 0.7                                 # torso pitch cap, radians; past it the shoulders swing forward instead
ANKLE_UP = 0.055                               # ankle bone above the pedal it stands on, Bob units
REACH = 0.97                                   # shoulder to grip as a share of the arm's full length

# Each bike as dz_render.build_pedal draws it, in model units (tiles): x across, y toward the back, z up.
# hip_back moves the hips along the saddle (negative = toward its nose), since the long bikes are a stretch to the bars.
BIKES = {
    "makeshift": dict(seat=(0, 0.07, 0.8025), hip_back=0.0, grip=(0.20, -0.37, 0.84), crank=(0, -0.02, 0.30), arm=0.125, pedal_x=0.09),
    "salvaged": dict(seat=(0, 0.24, 0.84), hip_back=-0.08, grip=(0.17, -0.41, 0.91), crank=(0, 0.05, 0.30), arm=0.128, pedal_x=0.10),
    "workshop": dict(seat=(0, 0.29, 0.82), hip_back=-0.12, grip=(0.18, -0.41, 0.84), crank=(0, -0.01, 0.32), arm=0.128, pedal_x=0.11),
}


def to_char(m, lift=0.0):
    """A bike model point (tiles) as a point in the rider's space; the rider stands on the square's centre facing the bike's front."""
    x, y, z = m
    return np.array([-x, z + RENDER_DROP + lift, y]) / GAME_SCALE


def rig(tier):
    """The tier's targets in the rider's space: hips, crank centre and radius, pedal spread, grip centre and spread."""
    b = BIKES[tier]
    hips = to_char((0, b["seat"][1] + b["hip_back"], b["seat"][2]), HIP_UP)
    g = b["grip"]
    return dict(hips=hips, crank=to_char(b["crank"]), arm=b["arm"] / GAME_SCALE, pedal_x=b["pedal_x"] / GAME_SCALE,
                bar=to_char((0, g[1], g[2])), grip_x=g[0] / GAME_SCALE)


def crank_foot(R, angle, side):
    """Ankle target for one foot: the pedal round the crank (angle 0 = top, turning forward), plus the ankle height."""
    a = angle + (0.0 if side == "L" else np.pi)
    p = R["crank"] + np.array([R["pedal_x"] if side == "L" else -R["pedal_x"], R["arm"] * np.cos(a), -R["arm"] * np.sin(a)])
    return p + np.array([0, ANKLE_UP, 0])


def seated_pose(template, sat):
    """A Pose on the template's skeleton holding the chair pose (bones the chair file lacks stay at rest)."""
    P = Pose(template, 0)
    loc = {b: (sat.sample_local(b, 0) if b in sat.frames else template.frames[b]) for b in template.order}
    P.W = template.world(loc)
    return P


def lean_for(R, template, sat):
    """Torso pitch that brings the shoulders within REACH of the grips."""
    best = None
    for lean in np.linspace(0.1, MAX_LEAN, 33):
        P = seated_pose(template, sat)
        P.translate("Bip01", R["hips"] - P.pos("Bip01_Pelvis"))
        P.rotate("Bip01_Spine", rot([1, 0, 0], -lean))
        arm = np.linalg.norm(P.pos("Bip01_L_Forearm") - P.pos("Bip01_L_UpperArm")) + np.linalg.norm(P.pos("Bip01_L_Hand") - P.pos("Bip01_L_Forearm"))
        d = np.linalg.norm(R["bar"] + np.array([R["grip_x"], 0, 0]) - P.pos("Bip01_L_UpperArm"))
        err = abs(d - REACH * arm)
        if best is None or err < best[0]: best = (err, lean)
    return best[1]


def arm_reach(P, side, target):
    """Shoulder-to-target distance as a share of the arm's full length."""
    u, e, h = (P.pos(f"Bip01_{side}_{b}") for b in ("UpperArm", "Forearm", "Hand"))
    return np.linalg.norm(target - u) / (np.linalg.norm(e - u) + np.linalg.norm(h - e))


def swing_shoulder(P, side, target):
    """Turn the clavicle toward the grip, up to 0.5 rad, until the hand can reach it."""
    c, u = P.pos(f"Bip01_{side}_Clavicle"), P.pos(f"Bip01_{side}_UpperArm")
    axis = np.cross(u - c, target - c)
    if np.linalg.norm(axis) < 1e-9: return
    step = rot(axis, 0.05)
    for _ in range(10):
        if arm_reach(P, side, target) <= REACH: break
        P.rotate(f"Bip01_{side}_Clavicle", step)


def build_frame(f, template, sat, R, lean):
    P = seated_pose(template, sat)
    angle = 2 * np.pi * f / (NFRAMES - 1)
    # Hips onto the saddle, then lean the torso to the bars.
    P.translate("Bip01", R["hips"] - P.pos("Bip01_Pelvis"))
    bob = 0.006 * np.sin(2 * angle)                                  # a slight sway with each pedal stroke
    P.rotate("Bip01_Spine", rot([1, 0, 0], -lean) @ rot([0, 0, 1], bob * 4))
    # Feet on the pedals: knees forward and a touch out, the foot kept level as it rides round.
    for side, pole in (("L", [0.35, 0.2, -1.0]), ("R", [-0.35, 0.2, -1.0])):
        foot = f"Bip01_{side}_Foot"
        keep = P.W[foot][:3, :3].copy()
        P.ik(f"Bip01_{side}_Thigh", f"Bip01_{side}_Calf", foot, crank_foot(R, angle, side), np.array(pole, float))
        a = angle + (0.0 if side == "L" else np.pi)
        toe = rot([1, 0, 0], 0.18 * np.sin(a))                       # ankle flexes a little through the stroke
        M4 = np.eye(4); M4[:3, :3] = keep
        cur = P.W[foot].copy(); cur[:3, :3] = (toe @ M4)[:3, :3]
        delta = cur @ np.linalg.inv(P.W[foot])
        for b in P.subtree(foot): P.W[b] = delta @ P.W[b]
    # Hands on the grips, elbows out and down.
    for side, sx, pole in (("L", 1, [1.0, -0.6, 0.3]), ("R", -1, [-1.0, -0.6, 0.3])):
        grip = R["bar"] + np.array([sx * R["grip_x"], 0, 0])
        swing_shoulder(P, side, grip)
        P.ik(f"Bip01_{side}_UpperArm", f"Bip01_{side}_Forearm", f"Bip01_{side}_Hand", grip, np.array(pole, float))
    # Head back up to look ahead over the bars.
    P.rotate("Bip01_Head", rot([1, 0, 0], -0.75 * lean))
    return P


ANIMSET_XML = """<?xml version="1.0" encoding="utf-8"?>
<animNode>
	<m_Name>DazedPedal{Tier}</m_Name>
	<m_AnimName>Bob_DazedPedal{Tier}</m_AnimName>
	<m_BlendTime>0.3</m_BlendTime>
	<m_SpeedScale>DazedPedalSpeed</m_SpeedScale>
	<m_SyncTrackingEnabled>false</m_SyncTrackingEnabled>
	<m_Conditions x_name="{uuid1}">
		<m_Name>PerformingAction</m_Name>
		<m_Type>STRING</m_Type>
		<m_Value>DazedPedal</m_Value>
	</m_Conditions>
	<m_Conditions x_name="{uuid2}">
		<m_Name>DazedPedalTier</m_Name>
		<m_Type>STRING</m_Type>
		<m_Value>{tier}</m_Value>
	</m_Conditions>
	<m_SubStateBoneWeights>
		<boneName>Dummy01</boneName>
	</m_SubStateBoneWeights>
	<m_SubStateBoneWeights>
		<boneName>Translation_Data</boneName>
	</m_SubStateBoneWeights>
</animNode>
"""
# Fixed ids so rebuilding doesn't churn the files; DazedPedal.xml keeps its old name so the 0.6.0 node is replaced.
XML_FILES = {"makeshift": ("DazedPedal.xml", "7c3f2e91-4a58-4d0b-b6e2-9d1f5a83c204", "1e6b0c47-93d2-4f1a-a8b5-0c2d7e9f3a11"),
             "salvaged": ("DazedPedalSalvaged.xml", "4b8e1d20-6c3a-4f97-9e52-7a1c0d3b8e42", "9d2f7a63-1b4e-4c08-b6a1-5e3c8f0d2b73"),
             "workshop": ("DazedPedalWorkshop.xml", "2a7c9e14-8d5b-4e36-a0f1-3b6d9c2e7f84", "6f1d3b85-0e9a-4c27-9b4e-8a2c5d7f1e95")}


def install(template, tier, keys):
    ax = os.path.join(MOD_MEDIA, "anims_X", "Bob")
    xml = os.path.join(MOD_MEDIA, "AnimSets", "player", "actions")
    os.makedirs(ax, exist_ok=True); os.makedirs(xml, exist_ok=True)
    Tier = tier.capitalize()
    out = os.path.join(ax, "Bob_DazedPedal%s.X" % Tier)
    write_x(template, out, "Bob_DazedPedal" + Tier, TPS, keys, (NFRAMES - 1) * TPS // FPS)
    name, u1, u2 = XML_FILES[tier]
    open(os.path.join(xml, name), "w", newline="\n").write(ANIMSET_XML.format(Tier=Tier, tier=tier, uuid1=u1, uuid2=u2))
    return out


def run():
    template = XFile(os.path.join(PZ_ANIMS, "Bob_SquatLoop.X"))
    sat = XFile(os.path.join(PZ_ANIMS, "Bob_SatChair.x"))
    all_poses = {}
    for tier in BIKES:
        R = rig(tier)
        lean = lean_for(R, template, sat)
        poses = [build_frame(f, template, sat, R, lean) for f in range(NFRAMES)]
        keys = {b: [] for b in template.order}
        for f, P in enumerate(poses):
            L = P.locals()
            for b in template.order:
                keys[b].append((f * TPS // FPS, L[b]))
        print("DazedPedal: wrote", install(template, tier, keys), "lean %.2f" % lean)
        all_poses[tier] = poses
    try:
        import bpy  # noqa: F401
    except ImportError:
        return all_poses
    _lib["BASE"] = template
    _lib["NFRAMES"] = NFRAMES
    _lib["GEN"] = (-0.05, 0.05, -0.30, 0.30, 0.02)      # a thin floor marker; the bike is judged in-game
    _lib["preview"](all_poses["salvaged"])
    return all_poses


if __name__ == "__main__" or "bpy" in globals() or globals().get("RUN", True):
    POSES = run()
