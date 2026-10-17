"""Dazed Power: work clips at machines (Bob_DazedTinker, Bob_DazedPress, Bob_DazedRunCable, Bob_DazedReadSky).

Built procedurally on the vanilla Bob skeleton like the pull-start and pedal clips, then written as .X files with
their AnimSet nodes into the mod:
  Bob_DazedTinker    crouched at a machine: left hand braced on it, right hand turning a screwdriver at two spots.
  Bob_DazedPress     crouched at a machine's switch or button: reach, press, hold, let go.
  Bob_DazedRunCable  squatting low, feeding a cable along the ground hand over hand.
  Bob_DazedReadSky   standing, head up, right hand shading the eyes, a slow look across the sky.
All four loop (the last frame is the first). Props: Bip01_Prop1/Prop2 follow the right/left hand with the hand-to-prop
offset the vanilla standing pose has, so an item set with setOverrideHandModels sits in the hand.

Plain Python 3 with numpy (no Blender needed):
    python3 tools/blender/dp_work.py
Skeleton and mesh: Bob_SquatLoop.X from PZ_ANIMS when that folder exists; otherwise the mod's own
Bob_DazedPullStartGenerator.X, whose header IS Bob_SquatLoop's (dp_pullstart.write_x copies it verbatim), so the
skeleton, rest frames and skinned mesh are the same. The crouch is the pull-start clip's first frame (settled at
the generator), which dp_pullstart built from Bob_SquatLoop's half squat.
Check the result with tools/blender/dp_clipsheet.py (contact sheet of the written files).
"""
import os
import numpy as np

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__") or r"C:\Users\Shado\Zomboid\Workshop\DazedPower\tools\blender\x.py"))
PZ_ANIMS = globals().get("PZ_ANIMS") or os.environ.get("PZ_ANIMS") or r"D:\SteamSSD\steamapps\common\ProjectZomboid\media\anims_X\Bob"
MOD_MEDIA = globals().get("MOD_MEDIA") or os.path.normpath(os.path.join(_HERE, "..", "..", "Contents", "mods", "DazedPower", "common", "media"))

_src = open(os.path.join(_HERE, "dp_pullstart.py"), encoding="utf-8").read().rsplit("\nrun()", 1)[0]
_lib = {"__file__": os.path.join(_HERE, "dp_pullstart.py"), "PZ_ANIMS": PZ_ANIMS, "MOD_MEDIA": MOD_MEDIA}
exec(_src, _lib)
XFile, Pose, write_x, rot, align = _lib["XFile"], _lib["Pose"], _lib["write_x"], _lib["rot"], _lib["align"]

FPS, TPS = 30, 4800
FEET = ("Bip01_L_Foot", "Bip01_R_Foot")
# Character space: +Y up, faces -Z, right side is -X; floor at y = 0. The stand-in machine of the pull-start
# (front face at z = -0.21, top at 0.32) is the work surface here too.
MACHINE = (-0.14, 0.16, -0.40, -0.21, 0.32)


def ease(a):
    a = np.clip(a, 0, 1); return a * a * (3 - 2 * a)


def smooth_step(f, keys):
    """Piecewise eased interpolation of vectors over frames: keys = [(frame, value), ...], held outside."""
    if f <= keys[0][0]: return np.asarray(keys[0][1], float)
    for (f0, v0), (f1, v1) in zip(keys, keys[1:]):
        if f <= f1:
            a = ease((f - f0) / max(1e-9, f1 - f0))
            return np.asarray(v0, float) * (1 - a) + np.asarray(v1, float) * a
    return np.asarray(keys[-1][1], float)


class Rig:
    """The template skeleton plus the two source poses: the vanilla standing rest and the pull-start crouch."""

    def __init__(self):
        squat = os.path.join(PZ_ANIMS, "Bob_SquatLoop.X")
        own = os.path.join(MOD_MEDIA, "anims_X", "Bob", "Bob_DazedPullStartGenerator.X")
        self.template = XFile(squat if os.path.exists(squat) else own)
        self.pull = XFile(own)
        x = self.template
        rest = x.world({b: x.frames[b] for b in x.order})
        # The prop bones' place in each hand, from the standing rest pose (where they sit in the hands).
        self.prop_off = {"Bip01_Prop1": np.linalg.inv(rest["Bip01_R_Hand"]) @ rest["Bip01_Prop1"],
                         "Bip01_Prop2": np.linalg.inv(rest["Bip01_L_Hand"]) @ rest["Bip01_Prop2"]}
        # Right fingers closed (the pull-start's cord grip) and open (the rest pose).
        P0 = Pose(self.pull, 0)
        L0 = P0.locals()
        kids = P0.subtree("Bip01_R_Hand")[1:]
        self.grip_R = {b: L0[b] for b in kids}
        self.open_R = {b: x.frames[b] for b in kids}
        self.grip_L = {b: L0[b] for b in P0.subtree("Bip01_L_Hand")[1:]}

    def crouch(self):
        """A fresh copy of the pull-start crouch (frame 0) on the template's skeleton."""
        P = Pose(self.template, 0)
        P.W = {b: m.copy() for b, m in Pose(self.pull, 0).W.items()}
        return P

    def stand(self):
        x = self.template
        P = Pose(x, 0)
        P.W = x.world({b: x.frames[b] for b in x.order})
        return P

    def props(self, P):
        P.W["Bip01_Prop1"] = P.W["Bip01_R_Hand"] @ self.prop_off["Bip01_Prop1"]
        P.W["Bip01_Prop2"] = P.W["Bip01_L_Hand"] @ self.prop_off["Bip01_Prop2"]

    def fingers(self, P, side, locals_):
        for b, m in locals_.items():
            P.W[b] = P.W[self.template.parent[b]] @ m


def plant(P, drop=0.0, lean=0.0, sway=0.0, twist=0.0):
    """Moves the hips down by drop and the torso forward by lean (radians) while the feet stay where they were."""
    feet = {b: P.W[b].copy() for f in FEET for b in P.subtree(f)}
    if drop:
        P.translate("Bip01_Pelvis", np.array([0, -drop, 0]))
    if lean or sway:
        P.rotate("Bip01_Spine", rot([1, 0, 0], -lean) @ rot([0, 0, 1], sway))
    if twist:
        P.rotate("Bip01_Spine1", rot([0, 1, 0], twist))
    for side, pole in (("L", [0.3, 0, -1]), ("R", [-0.3, 0, -1])):
        P.ik(f"Bip01_{side}_Thigh", f"Bip01_{side}_Calf", f"Bip01_{side}_Foot", feet[f"Bip01_{side}_Foot"][:3, 3], np.array(pole, float))
    for b, m in feet.items():
        P.W[b] = m.copy()


def twist_hand(P, side, angle):
    """Rolls the hand about the forearm, half of it in the forearm, half at the wrist (no candy-wrap)."""
    e, h = P.pos(f"Bip01_{side}_Forearm"), P.pos(f"Bip01_{side}_Hand")
    axis = h - e
    P.rotate(f"Bip01_{side}_Forearm", rot(axis, angle * 0.5))
    P.rotate(f"Bip01_{side}_Hand", rot(axis, angle * 0.5))


def flex_hand(P, side, angle, axis=(1, 0, 0)):
    P.rotate(f"Bip01_{side}_Hand", rot(axis, angle))


def look(P, pitch=0.0, yaw=0.0):
    """Head turn: pitch > 0 tips the head back (looks up), yaw > 0 turns it to the character's left."""
    P.rotate("Bip01_Neck", rot([0, 1, 0], yaw * 0.4) @ rot([1, 0, 0], pitch * 0.4))
    P.rotate("Bip01_Head", rot([0, 1, 0], yaw * 0.6) @ rot([1, 0, 0], pitch * 0.6))


def arm(P, side, target, pole):
    P.ik(f"Bip01_{side}_UpperArm", f"Bip01_{side}_Forearm", f"Bip01_{side}_Hand", np.asarray(target, float), np.asarray(pole, float))


# ---------------------------------------------------------------- the clips

def tinker(rig, f, n):
    """2 s: three screwdriver turns at one spot, shift along the panel, three at the next, back."""
    P = rig.crouch()
    spotA = np.array([-0.06, 0.255, -0.225]); spotB = np.array([0.01, 0.225, -0.225])
    hand = smooth_step(f, [(0, spotA), (22, spotA), (30, spotB), (52, spotB), (60, spotA)])
    moving = 1.0 - max(0.0, min(1.0, min(abs(f - 26), abs(f - 56)) / 5.0))
    settled = 1.0 - moving
    # Three turns in each 22-frame hold: the wrist rolls through the turn and back.
    ph = (f % 30) / 22.0
    turn = 0.55 * np.sin(np.clip(ph, 0, 1) * 3 * 2 * np.pi) * settled
    push = 0.008 * np.sin(np.clip(ph, 0, 1) * 6 * 2 * np.pi) * settled
    sway = 0.03 * np.sin(2 * np.pi * f / n)
    plant(P, drop=0.0, lean=-0.10, sway=sway, twist=0.08 * (hand[0] - spotA[0]) / (spotB[0] - spotA[0]))
    arm(P, "L", [0.085 + sway * 0.3, 0.325, -0.255], [1.0, -0.3, 0.6])
    arm(P, "R", hand + np.array([0, 0, -push]), [-0.7, 0.4, 0.8])
    rig.fingers(P, "R", rig.grip_R)
    # Screwdriver held into the panel: hand bent to point the tool forward, then the turn.
    twist_hand(P, "R", turn)
    look(P, pitch=-0.05 + 0.04 * np.sin(2 * np.pi * f / n), yaw=-0.15 + 0.12 * (hand[0] - spotA[0]) / (spotB[0] - spotA[0]))
    rig.props(P)
    return P


def press(rig, f, n):
    """1.5 s: hand comes up to the switch, presses (or flips) it, holds a moment, eases back to the ready spot."""
    P = rig.crouch()
    ready = np.array([-0.06, 0.30, -0.18]); at = np.array([-0.035, 0.335, -0.235]); pushed = at + np.array([0, -0.012, -0.022])
    hand = smooth_step(f, [(0, ready), (12, at), (17, pushed), (25, pushed), (30, at), (45, ready)])
    flick = smooth_step(f, [(0, [0.0]), (14, [0.0]), (18, [0.35]), (26, [0.35]), (31, [0.0])])[0]
    plant(P, drop=-0.03, lean=-0.18, sway=0.0)
    knee = P.pos("Bip01_L_Calf")
    arm(P, "L", knee + np.array([-0.01, 0.045, -0.02]), [1.0, 0.2, 0.3])
    arm(P, "R", hand, [-0.8, -0.2, 0.6])
    rig.fingers(P, "R", rig.open_R)
    flex_hand(P, "R", -flick)
    look(P, pitch=0.05)
    rig.props(P)
    return P


def run_cable(rig, f, n):
    """2 s: squatting, hand over hand: each hand reaches forward low, grips, draws the cable back past the knee."""
    P = rig.crouch()
    lean_b = 0.10 + 0.04 * np.sin(4 * np.pi * f / n)
    plant(P, drop=0.07, lean=lean_b, sway=0.025 * np.sin(2 * np.pi * f / n))
    # Squatting this low the skirt bones' hem would sink ~2 cm into the floor: hold it up off the ground.
    P.translate("Bip01_DressBack02", np.array([0, 0.03, 0]))
    P.translate("Bip01_DressFront02", np.array([0, 0.02, 0]))

    def hand_path(phase, x):
        # phase 0..1: 0-0.5 draws back along the ground, 0.5-1 lifts and reaches forward again.
        front = np.array([x, 0.11, -0.34]); back = np.array([x * 1.6, 0.13, -0.14])
        if phase < 0.5:
            a = ease(phase / 0.5)
            return front * (1 - a) + back * a
        a = ease((phase - 0.5) / 0.5)
        p = back * (1 - a) + front * a
        p[1] += 0.06 * np.sin(a * np.pi)
        return p
    ph = f / n
    arm(P, "R", hand_path(ph % 1.0, -0.055), [-0.8, 0.3, 0.6])
    arm(P, "L", hand_path((ph + 0.5) % 1.0, 0.055), [0.8, 0.3, 0.6])
    rig.fingers(P, "R", rig.grip_R)
    look(P, pitch=-0.25, yaw=0.0)
    rig.props(P)
    return P


def read_sky(rig, f, n):
    """3 s: standing, head back, right hand shading the eyes, a slow look from one side to the other."""
    P = rig.stand()
    breathe = 0.01 * np.sin(4 * np.pi * f / n)
    P.rotate("Bip01_Spine", rot([1, 0, 0], 0.06 + breathe))
    yaw = 0.35 * np.sin(2 * np.pi * f / n)
    P.rotate("Bip01_Spine1", rot([0, 1, 0], yaw * 0.25))
    look(P, pitch=0.6, yaw=yaw * 0.75)
    # Hand flat over the brow: just in front of and above the eyes (the head bone sits at the jaw hinge).
    head, nub = P.pos("Bip01_Head"), P.pos("Bip01_HeadNub")
    upv = (nub - head) / np.linalg.norm(nub - head)
    fwd = np.cross(upv, [1.0, 0, 0]); fwd /= np.linalg.norm(fwd)
    if fwd[2] > 0: fwd = -fwd
    target = head + upv * 0.085 + fwd * 0.085 + np.array([-0.015, 0, 0])
    arm(P, "R", target, [-1.0, 0.2, 0.3])
    rig.fingers(P, "R", rig.open_R)
    rig.props(P)
    return P


CLIPS = {
    # name: (builder, frames incl. the closing one, AnimSet node, condition GUID, blend)
    "Tinker": (tinker, 61, "DazedTinker", "5e2b8c41-7d93-4a06-b1f8-2c6e9a4d7b13", 0.25),
    "Press": (press, 46, "DazedPress", "a3c71f58-2e4b-4d90-8b6c-7f1e0d92c5a4", 0.2),
    "RunCable": (run_cable, 61, "DazedRunCable", "c84f2a17-5b3e-4e61-9d0a-6b2f8e13a7c9", 0.3),
    "ReadSky": (read_sky, 91, "DazedReadSky", "1f9d6e32-8a47-4c15-a2b3-e5c07d4f9b68", 0.3),
}

ANIMSET_XML = """<?xml version="1.0" encoding="utf-8"?>
<animNode>
	<m_Name>{node}</m_Name>
	<m_AnimName>Bob_{node}</m_AnimName>
	<m_BlendTime>{blend}</m_BlendTime>
	<m_SyncTrackingEnabled>false</m_SyncTrackingEnabled>
	<m_Conditions x_name="{uuid}">
		<m_Name>PerformingAction</m_Name>
		<m_Type>STRING</m_Type>
		<m_Value>{node}</m_Value>
	</m_Conditions>
	<m_SubStateBoneWeights>
		<boneName>Dummy01</boneName>
	</m_SubStateBoneWeights>
	<m_SubStateBoneWeights>
		<boneName>Translation_Data</boneName>
	</m_SubStateBoneWeights>
</animNode>
"""


def build(rig, name):
    fn, nframes, node, uuid, blend = CLIPS[name]
    n = nframes - 1
    poses = [fn(rig, f, n) for f in range(nframes)]
    keys = {b: [] for b in rig.template.order}
    for f, P in enumerate(poses):
        L = P.locals()
        for b in rig.template.order:
            keys[b].append((f * TPS // FPS, L[b]))
    ax = os.path.join(MOD_MEDIA, "anims_X", "Bob")
    xml = os.path.join(MOD_MEDIA, "AnimSets", "player", "actions")
    os.makedirs(ax, exist_ok=True); os.makedirs(xml, exist_ok=True)
    out = os.path.join(ax, "Bob_%s.X" % node)
    write_x(rig.template, out, "Bob_" + node, TPS, keys, n * TPS // FPS)
    open(os.path.join(xml, node + ".xml"), "w", newline="\n").write(ANIMSET_XML.format(node=node, uuid=uuid, blend=blend))
    return out, poses


def run(names=None):
    rig = Rig()
    out = {}
    for name in names or CLIPS:
        path, poses = build(rig, name)
        print("DazedWork: wrote", path)
        out[name] = poses
    return out


if __name__ == "__main__" or globals().get("RUN", True):
    POSES = run()
