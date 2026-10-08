"""Dazed Power: seated pedalling animation (Bob_DazedPedalGenerator) for the pedal generators.

Builds one crank turn procedurally on the vanilla Bob skeleton from the chair-sitting pose: hips on the saddle,
torso leaning to the bars, feet riding the pedals round a crank, hands on the grips. Writes the .X and its AnimSet
node into the mod. Runs in plain Python 3 with numpy, or inside Blender (4.2+/5.x) where it also sets up a preview.
    python3 tools/blender/dp_pedal.py
Optional globals: PZ_ANIMS (vanilla anims_X/Bob folder), MOD_MEDIA (mod's common/media folder).
"""
import os
import numpy as np

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__") or r"C:\Users\Shado\Zomboid\Workshop\DazedPower\Contents\mods\DazedPower\tools\blender\x.py"))
PZ_ANIMS = globals().get("PZ_ANIMS") or os.environ.get("PZ_ANIMS") or r"D:\SteamSSD\steamapps\common\ProjectZomboid\media\anims_X\Bob"
MOD_MEDIA = globals().get("MOD_MEDIA") or os.path.normpath(os.path.join(_HERE, "..", "..", "common", "media"))

# The .X reader/writer, the pose rig and the Blender preview live in dp_pullstart.py; take them without running it.
_src = open(os.path.join(_HERE, "dp_pullstart.py"), encoding="utf-8").read().rsplit("\nrun()", 1)[0]
_lib = {"__file__": os.path.join(_HERE, "dp_pullstart.py"), "PZ_ANIMS": PZ_ANIMS, "MOD_MEDIA": MOD_MEDIA}
exec(_src, _lib)
XFile, Pose, write_x, rot, align = _lib["XFile"], _lib["Pose"], _lib["write_x"], _lib["rot"], _lib["align"]

FPS, TPS = 30, 4800
NFRAMES = 25                                   # 0..24 -> 0.8 s, one crank turn; the last frame closes the loop.

# Character space: +Y up, faces -Z, right side is -X. Sizes are the bikes' (dz_render.build_pedal) scaled to Bob:
# saddle ~0.78 tile units high sits at Bob's hip height, so one tile unit is ~0.66 here.
SEAT_Y = 0.52                                  # pelvis on the saddle
CRANK = np.array([0.0, 0.205, -0.05])          # bottom bracket: below and a little ahead of the saddle
CRANK_R = 0.075                                # crank arm
PEDAL_X = 0.075                                # pedals sit this far out each side
ANKLE_UP = 0.055                               # ankle bone above the pedal it stands on
BAR = np.array([0.0, 0.565, -0.265])           # handlebar centre
GRIP_X = 0.115
LEAN = 0.42                                    # torso pitch toward the bars, radians


def crank_foot(angle, side):
    """Ankle target for one foot: the pedal round the crank (angle 0 = top, turning forward), plus the ankle height."""
    a = angle + (0.0 if side == "L" else np.pi)
    p = CRANK + np.array([PEDAL_X if side == "L" else -PEDAL_X, CRANK_R * np.cos(a), -CRANK_R * np.sin(a)])
    return p + np.array([0, ANKLE_UP, 0])


def seated_pose(template, sat):
    """A Pose on the template's skeleton holding the chair pose (bones the chair file lacks stay at rest)."""
    P = Pose(template, 0)
    loc = {b: (sat.sample_local(b, 0) if b in sat.frames else template.frames[b]) for b in template.order}
    P.W = template.world(loc)
    return P


def build_frame(f, template, sat):
    P = seated_pose(template, sat)
    angle = 2 * np.pi * f / (NFRAMES - 1)
    # Lift the hips from the chair onto the saddle, then lean the torso forward to the bars.
    P.translate("Bip01", np.array([0, SEAT_Y - P.pos("Bip01_Pelvis")[1], 0.02]))
    bob = 0.006 * np.sin(2 * angle)                                  # a slight sway with each pedal stroke
    P.rotate("Bip01_Spine", rot([1, 0, 0], -LEAN) @ rot([0, 0, 1], bob * 4))
    # Feet on the pedals: knees forward and a touch out, the foot kept level as it rides round.
    for side, pole in (("L", [0.35, 0.2, -1.0]), ("R", [-0.35, 0.2, -1.0])):
        foot = f"Bip01_{side}_Foot"
        keep = P.W[foot][:3, :3].copy()
        P.ik(f"Bip01_{side}_Thigh", f"Bip01_{side}_Calf", foot, crank_foot(angle, side), np.array(pole, float))
        a = angle + (0.0 if side == "L" else np.pi)
        toe = rot([1, 0, 0], 0.18 * np.sin(a))                       # ankle flexes a little through the stroke
        R = np.eye(4); R[:3, :3] = keep
        cur = P.W[foot].copy(); cur[:3, :3] = (toe @ R)[:3, :3]
        delta = cur @ np.linalg.inv(P.W[foot])
        for b in P.subtree(foot): P.W[b] = delta @ P.W[b]
    # Hands on the grips, elbows out and down.
    P.ik("Bip01_L_UpperArm", "Bip01_L_Forearm", "Bip01_L_Hand", BAR + np.array([GRIP_X, 0, 0]), np.array([1.0, -0.6, 0.3]))
    P.ik("Bip01_R_UpperArm", "Bip01_R_Forearm", "Bip01_R_Hand", BAR + np.array([-GRIP_X, 0, 0]), np.array([-1.0, -0.6, 0.3]))
    # Head back up to look ahead over the bars.
    P.rotate("Bip01_Head", rot([1, 0, 0], -0.3))
    return P


ANIMSET_XML = """<?xml version="1.0" encoding="utf-8"?>
<animNode>
	<m_Name>DazedPedal</m_Name>
	<m_AnimName>Bob_DazedPedalGenerator</m_AnimName>
	<m_BlendTime>0.3</m_BlendTime>
	<m_SpeedScale>DazedPedalSpeed</m_SpeedScale>
	<m_SyncTrackingEnabled>false</m_SyncTrackingEnabled>
	<m_Conditions x_name="7c3f2e91-4a58-4d0b-b6e2-9d1f5a83c204">
		<m_Name>PerformingAction</m_Name>
		<m_Type>STRING</m_Type>
		<m_Value>DazedPedal</m_Value>
	</m_Conditions>
	<m_SubStateBoneWeights>
		<boneName>Dummy01</boneName>
	</m_SubStateBoneWeights>
	<m_SubStateBoneWeights>
		<boneName>Translation_Data</boneName>
	</m_SubStateBoneWeights>
</animNode>
"""


def install(template, keys):
    ax = os.path.join(MOD_MEDIA, "anims_X", "Bob")
    xml = os.path.join(MOD_MEDIA, "AnimSets", "player", "actions")
    os.makedirs(ax, exist_ok=True); os.makedirs(xml, exist_ok=True)
    out = os.path.join(ax, "Bob_DazedPedalGenerator.X")
    write_x(template, out, "Bob_DazedPedalGenerator", TPS, keys, (NFRAMES - 1) * TPS // FPS)
    open(os.path.join(xml, "DazedPedal.xml"), "w", newline="\n").write(ANIMSET_XML)
    return out


def run():
    template = XFile(os.path.join(PZ_ANIMS, "Bob_SquatLoop.X"))
    sat = XFile(os.path.join(PZ_ANIMS, "Bob_SatChair.x"))
    poses = [build_frame(f, template, sat) for f in range(NFRAMES)]
    keys = {b: [] for b in template.order}
    for f, P in enumerate(poses):
        L = P.locals()
        for b in template.order:
            keys[b].append((f * TPS // FPS, L[b]))
    out = install(template, keys)
    print("DazedPedal: wrote", out)
    try:
        import bpy  # noqa: F401
    except ImportError:
        return poses
    _lib["BASE"] = template
    _lib["NFRAMES"] = NFRAMES
    _lib["GEN"] = (-0.05, 0.05, -0.30, 0.30, 0.02)      # a thin floor marker; the bike is judged in-game
    _lib["preview"](poses)
    return poses


if __name__ == "__main__" or "bpy" in globals() or globals().get("RUN", True):
    POSES = run()
