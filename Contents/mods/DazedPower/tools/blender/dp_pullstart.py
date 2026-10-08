"""Dazed Power: generator pull-start animation (Bob_DazedPullStartGenerator).
Builds the pull procedurally on the vanilla Bob skeleton, writes the .X and its AnimSet node into the mod,
then (inside Blender 4.2+/5.x) sets up a skinned preview with a stand-in generator.
Run in Blender: open this file in the Text Editor and Run Script, or exec(open(path).read()).
Optional globals: PZ_ANIMS (vanilla anims_X/Bob folder), MOD_MEDIA (mod's common/media folder).
"""
import os
import re
import numpy as np

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__") or r"C:\Users\Shado\Zomboid\Workshop\DazedPower\Contents\mods\DazedPower\tools\blender\x.py"))
PZ_ANIMS = globals().get("PZ_ANIMS") or r"D:\SteamSSD\steamapps\common\ProjectZomboid\media\anims_X\Bob"
MOD_MEDIA = globals().get("MOD_MEDIA") or os.path.normpath(os.path.join(_HERE, "..", "..", "common", "media"))



def _tokens(text):
    # Strings, braces, and bare words/numbers; separators ; and , are dropped.
    return re.findall(r'"[^"]*"|[{}]|[^\s{};,"]+', text)


class Node:
    __slots__ = ("kind", "name", "items", "children")

    def __init__(self, kind, name):
        self.kind, self.name, self.items, self.children = kind, name, [], []


def _parse_block(toks, i):
    # toks[i] is the kind; returns (Node, next index).
    kind = toks[i]; i += 1
    name = None
    if toks[i] != "{":
        name = toks[i]; i += 1
    assert toks[i] == "{", (kind, name, toks[i])
    i += 1
    node = Node(kind, name)
    while toks[i] != "}":
        if toks[i] == "{":
            # Reference like { Bip01 }.
            node.items.append(("ref", toks[i + 1])); i += 3
        elif _isident(toks[i]) and (toks[i + 1] == "{" or (_isident(toks[i + 1]) and toks[i + 2] == "{")):
            child, i = _parse_block(toks, i)
            node.children.append(child)
        else:
            node.items.append(toks[i]); i += 1
    return node, i + 1


def _isident(t):
    return bool(re.match(r'^[A-Za-z_]', t))


def _isnum(t):
    return bool(re.match(r'^-?[0-9.]', t))


def mat_from16(vals):
    # .X stores row-major with translation in the last row (row-vector convention); return column-vector 4x4.
    return np.array(vals, dtype=float).reshape(4, 4).T


def mat_to16(m):
    return list(np.asarray(m).T.reshape(16))


def quat_to_mat(q):
    w, x, y, z = q
    n = np.sqrt(w * w + x * x + y * y + z * z); w, x, y, z = w / n, x / n, y / n, z / n
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)]])


def mat_to_quat(m):
    m = np.asarray(m)[:3, :3]
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        q = [0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s]
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s]
    q = np.array(q)
    return q / np.linalg.norm(q)


class XFile:
    def __init__(self, path):
        self.text = open(path, encoding="latin-1").read()
        cut = self.text.index("AnimTicksPerSecond  {") if "AnimTicksPerSecond  {" in self.text else self.text.index("AnimTicksPerSecond {")
        # Header = templates + frames + mesh, reused verbatim when writing.
        self.header = self.text[:cut]
        toks = _tokens(self.text[self.text.index("\nFrame "):])
        self.frames = {}      # name -> rest local matrix (column-vector)
        self.parent = {}
        self.order = []
        self.mesh = None
        self.anim = {}        # bone -> dict(S=[(t,v)], R=[(t,q)], T=[(t,v)])
        self.ticks = 4800
        i = 0
        while i < len(toks):
            if toks[i] == "Frame":
                node, i = _parse_block(toks, i)
                self._walk_frame(node, None)
            elif toks[i] == "AnimTicksPerSecond":
                self.ticks = int(toks[i + 2]); i += 4
            elif toks[i] == "AnimationSet":
                node, i = _parse_block(toks, i)
                self.anim_name = node.name
                self._read_anims(node)
            else:
                i += 1

    def _walk_frame(self, node, parent):
        m = np.eye(4)
        for c in node.children:
            if c.kind == "FrameTransformMatrix" and len(c.items) == 16:
                m = mat_from16([float(v) for v in c.items])
        self.frames[node.name] = m
        self.parent[node.name] = parent
        self.order.append(node.name)
        for c in node.children:
            if c.kind == "Frame":
                self._walk_frame(c, node.name)
            elif c.kind == "Mesh":
                self.mesh = c

    def _read_anims(self, node):
        for a in node.children:
            bone = [it[1] for it in a.items if isinstance(it, tuple)][0]
            d = {}
            for k in a.children:
                it = [float(v) for v in k.items]
                typ, n = int(it[0]), int(it[1])
                p = 2
                keys = []
                for _ in range(n):
                    t, cnt = it[p], int(it[p + 1])
                    keys.append((int(t), np.array(it[p + 2:p + 2 + cnt])))
                    p += 2 + cnt
                d[{0: "R", 1: "S", 2: "T"}[typ]] = keys
            self.anim[bone] = d

    def length(self):
        return max(k[-1][0] for d in self.anim.values() for k in d.values())

    def sample_local(self, bone, t):
        # Local matrix of a bone at tick t (linear/slerp between keys); falls back to rest.
        d = self.anim.get(bone)
        if not d:
            return self.frames[bone].copy()
        def lerp(keys, slerp=False):
            if t <= keys[0][0]:
                return keys[0][1]
            for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
                if t <= t1:
                    a = (t - t0) / max(1, t1 - t0)
                    if slerp:
                        if np.dot(v0, v1) < 0:
                            v1 = -v1
                        v = v0 * (1 - a) + v1 * a
                        return v / np.linalg.norm(v)
                    return v0 * (1 - a) + v1 * a
            return keys[-1][1]
        m = np.eye(4)
        r = lerp(d["R"], True) if "R" in d else mat_to_quat(self.frames[bone])
        s = lerp(d["S"]) if "S" in d else np.ones(3)
        tr = lerp(d["T"]) if "T" in d else self.frames[bone][:3, 3]
        # Keys store the conjugate rotation (D3D row-vector convention).
        rc = np.array([r[0], -r[1], -r[2], -r[3]]) if "R" in d else r
        m[:3, :3] = quat_to_mat(rc) @ np.diag(s)
        m[:3, 3] = tr
        return m

    def world(self, locals_):
        out = {}
        for b in self.order:
            p = self.parent[b]
            out[b] = (out[p] @ locals_[b]) if p else locals_[b]
        return out


def write_x(template: XFile, path, set_name, ticks, keys_by_bone, end_tick):
    """keys_by_bone: bone -> list of (tick, local 4x4). Writes S/R/T keys like vanilla files."""
    out = [template.header, "AnimTicksPerSecond  {\n %d;\n}\n\n" % ticks, "AnimationSet %s {\n \n" % set_name]
    for bone in template.order:
        keys = keys_by_bone.get(bone)
        if keys is None:
            m = template.frames[bone]
            keys = [(0, m), (end_tick, m)]
        out.append(" Animation {\n  \n  { %s }\n\n" % bone)
        def block(typ, rows):
            s = "  AnimationKey %s {\n   %d;\n   %d;\n" % ({0: "R", 1: "S", 2: "T"}[typ], typ, len(rows))
            s += ",\n".join("   %d;%d;%s;;" % (t, len(v), ",".join("%.6f" % x for x in v)) for t, v in rows) + ";\n  }\n\n"
            return s
        S, R, T = [], [], []
        prev = None
        for t, m in keys:
            sc = np.linalg.norm(m[:3, :3], axis=0)
            q = mat_to_quat(m[:3, :3] / sc) * np.array([1, -1, -1, -1])
            if prev is not None and np.dot(prev, q) < 0:
                q = -q
            prev = q
            S.append((t, sc)); R.append((t, q)); T.append((t, m[:3, 3]))
        out.append(block(1, S) + block(0, R) + block(2, T))
        out.append(" }\n\n")
    out.append("}\n")
    open(path, "w", encoding="latin-1", newline="\n").write("".join(out))

# ---------------------------------------------------------------- the pull

BASE = None                                   # Bob_SquatLoop.X: lower-body crouch source and file template.
BASE_T = 2400                                 # Half-squat moment in the squat loop.
GRIP_SRC = None                               # Bob_IdleChainsaw_Start.X: closed right-hand fingers from its cord pull.
GRIP_T = 2194
FPS, TPS = 30, 4800
NFRAMES = 49                                  # 0..48 -> 1.6 s, one full pull.
# Phase boundaries (frames): settle, slack, yank, hold, return.
K_SETTLE, K_SLACK, K_YANK, K_HOLD = 10, 14, 19, 24

# Character space: +Y up, faces -Z, right side is -X.
GRIP = np.array([-0.07, 0.27, -0.20])         # Cord handle on the generator.
PULL = np.array([-0.17, 0.43, 0.06])          # Hand at the end of the yank, beside the ribs.
GEN = (-0.12, 0.16, -0.39, -0.21, 0.32)     # Generator box for previews: x0, x1, z0, z1, height.
LHAND = np.array([0.07, 0.335, -0.24])         # Left hand braced on the generator frame.


def rot(axis, ang):
    axis = np.asarray(axis, float); axis /= np.linalg.norm(axis)
    x, y, z = axis; c, s = np.cos(ang), np.sin(ang); C = 1 - c
    R = np.eye(4)
    R[:3, :3] = [[c + x*x*C, x*y*C - z*s, x*z*C + y*s],
                 [y*x*C + z*s, c + y*y*C, y*z*C - x*s],
                 [z*x*C - y*s, z*y*C + x*s, c + z*z*C]]
    return R


def align(a, b):
    # Minimal rotation taking direction a onto direction b.
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); s = np.linalg.norm(v); c = np.dot(a, b)
    if s < 1e-9:
        return np.eye(4)
    return rot(v, np.arctan2(s, c))


class Pose:
    def __init__(self, x, t):
        self.x = x
        loc = {b: x.sample_local(b, t) for b in x.order}
        self.W = x.world(loc)
        self.kids = {b: [c for c in x.order if x.parent[c] == b] for b in x.order}

    def subtree(self, b):
        out = [b]
        for c in self.kids[b]:
            out += self.subtree(c)
        return out

    def pos(self, b):
        return self.W[b][:3, 3].copy()

    def rotate(self, b, R, pivot=None):
        # Rigidly rotate a bone and everything under it about pivot (world).
        p = self.pos(b) if pivot is None else pivot
        T = np.eye(4); T[:3, 3] = p
        Ti = np.eye(4); Ti[:3, 3] = -p
        M = T @ R @ Ti
        for c in self.subtree(b):
            self.W[c] = M @ self.W[c]

    def translate(self, b, d):
        M = np.eye(4); M[:3, 3] = d
        for c in self.subtree(b):
            self.W[c] = M @ self.W[c]

    def ik(self, upper, lower, end, target, pole):
        # Analytic two-bone IK with a pole direction for the middle joint.
        S, E, H = self.pos(upper), self.pos(lower), self.pos(end)
        l1, l2 = np.linalg.norm(E - S), np.linalg.norm(H - E)
        d = target - S; dist = np.clip(np.linalg.norm(d), 1e-6, (l1 + l2) * 0.999)
        dn = d / np.linalg.norm(d)
        cosA = np.clip((l1*l1 + dist*dist - l2*l2) / (2*l1*dist), -1, 1)
        pn = pole - np.dot(pole, dn) * dn; pn /= np.linalg.norm(pn)
        E2 = S + dn * l1 * cosA + pn * l1 * np.sqrt(1 - cosA*cosA)
        self.rotate(upper, align(E - S, E2 - S))
        E, H = self.pos(lower), self.pos(end)
        self.rotate(lower, align(H - E, S + dn * dist - E))

    def locals(self):
        out = {}
        for b in self.x.order:
            p = self.x.parent[b]
            out[b] = np.linalg.inv(self.W[p]) @ self.W[b] if p else self.W[b].copy()
        return out


def ease(a):
    a = np.clip(a, 0, 1); return a*a*(3 - 2*a)


def ease_out(a):
    a = np.clip(a, 0, 1); return 1 - (1 - a)**3


def channels(f):
    """Per-frame drive values: hand position, forward bend, twist, lean-back, pelvis lift, finger curl."""
    hand = GRIP.copy(); bend = 0.0; twist = 0.0; lift = 0.0
    # 0-6 settle on the handle, 6-9 small push for slack, 9-14 yank, 14-18 hold/recoil, 18-36 return.
    slack = GRIP + np.array([0.01, -0.025, -0.02])
    if f < K_SETTLE:
        a = f / K_SETTLE; hand = GRIP + np.array([0, 0.008*np.sin(a*np.pi), 0])
    elif f < K_SLACK:
        a = ease((f - K_SETTLE) / (K_SLACK - K_SETTLE)); hand = GRIP + (slack - GRIP) * a; bend = 0.06*a; lift = -0.012*a
    elif f < K_YANK:
        a = ease_out((f - K_SLACK) / (K_YANK - K_SLACK))
        hand = slack + (PULL - slack) * a
        bend = 0.06 - 0.22*a; twist = 0.42*a; lift = -0.012 + 0.04*a
    elif f < K_HOLD:
        a = (f - K_YANK) / (K_HOLD - K_YANK)
        hand = PULL + np.array([-0.012, 0.012, 0.012]) * np.sin(a*np.pi)
        bend = -0.16 + 0.03*np.sin(a*np.pi); twist = 0.42; lift = 0.028
    else:
        a = ease((f - K_HOLD) / (NFRAMES - 1 - K_HOLD))
        hand = PULL + (GRIP - PULL) * a
        bend = -0.16 * (1 - a); twist = 0.42*(1 - a); lift = 0.028*(1 - a)
    return hand, bend, twist, lift


def build_frame(f):
    P = Pose(BASE, BASE_T)
    feet = {b: P.W[b].copy() for b in ("Bip01_L_Foot", "Bip01_R_Foot") + tuple(P.subtree("Bip01_L_Foot")[1:]) + tuple(P.subtree("Bip01_R_Foot")[1:])}
    hand, bend, twist, lift = channels(f)
    # Lean the whole torso forward over the generator, then add the per-frame bend/twist.
    P.rotate("Bip01_Spine", rot([1, 0, 0], -(0.80 + bend)))
    P.rotate("Bip01_Spine1", rot([0, 1, 0], twist * 0.6))
    P.rotate("Bip01_Spine", rot([0, 1, 0], twist * 0.4))
    P.translate("Bip01_Pelvis", np.array([0, lift, 0.0]))
    # Legs stay planted: IK the knees back to the original feet.
    for side, pole in (("L", [0.3, 0, -1]), ("R", [-0.3, 0, -1])):
        P.ik(f"Bip01_{side}_Thigh", f"Bip01_{side}_Calf", f"Bip01_{side}_Foot", feet[f"Bip01_{side}_Foot"][:3, 3], np.array(pole, float))
    for b, m in feet.items():
        P.W[b] = m.copy()
    # Arms: left braced on the frame, right on the cord.
    P.ik("Bip01_L_UpperArm", "Bip01_L_Forearm", "Bip01_L_Hand", LHAND, np.array([1.0, -0.3, 0.6]))
    P.ik("Bip01_R_UpperArm", "Bip01_R_Forearm", "Bip01_R_Hand", hand, np.array([-0.6, 0.7, 1.0]))
    # Right fingers closed round the handle, taken from the chainsaw pull.
    for b in P.subtree("Bip01_R_Hand")[1:]:
        P.W[b] = P.W[BASE.parent[b]] @ GRIP_SRC.sample_local(b, GRIP_T)
    # Head looks down at the generator.
    P.rotate("Bip01_Head", rot([1, 0, 0], 0.25))
    return P


# ---------------------------------------------------------------- install + Blender preview

def mesh_data(x):
    """Vertices, faces and per-bone (indices, weights, offset) from the template's skinned Body mesh."""
    it = x.mesh.items
    nv = int(it[0]); verts = np.array([float(v) for v in it[1:1 + nv * 3]]).reshape(nv, 3)
    p = 1 + nv * 3; nf = int(it[p]); p += 1
    faces = []
    for _ in range(nf):
        n = int(it[p]); faces.append([int(v) for v in it[p + 1:p + 1 + n]]); p += 1 + n
    skins = {}
    for c in x.mesh.children:
        if c.kind == "SkinWeights":
            name = c.items[0].strip('"'); n = int(c.items[1])
            idx = [int(v) for v in c.items[2:2 + n]]
            w = [float(v) for v in c.items[2 + n:2 + 2 * n]]
            off = mat_from16([float(v) for v in c.items[2 + 2 * n:18 + 2 * n]])
            skins[name] = (idx, w, off)
    return verts, faces, skins


ANIMSET_XML = """<?xml version="1.0" encoding="utf-8"?>
<animNode>
	<m_Name>DazedPullStart</m_Name>
	<m_AnimName>Bob_DazedPullStartGenerator</m_AnimName>
	<m_BlendTime>0.25</m_BlendTime>
	<m_SyncTrackingEnabled>false</m_SyncTrackingEnabled>
	<m_Conditions x_name="b1d6a6e2-3f51-4c8e-9a43-5d2f7c0e9a17">
		<m_Name>PerformingAction</m_Name>
		<m_Type>STRING</m_Type>
		<m_Value>DazedPullStart</m_Value>
	</m_Conditions>
	<m_SubStateBoneWeights>
		<boneName>Dummy01</boneName>
	</m_SubStateBoneWeights>
	<m_SubStateBoneWeights>
		<boneName>Translation_Data</boneName>
	</m_SubStateBoneWeights>
</animNode>
"""


def install(mod_media, keys):
    """Writes the .X and its AnimSet node into the mod's media folder."""
    import os
    ax = os.path.join(mod_media, "anims_X", "Bob")
    xml = os.path.join(mod_media, "AnimSets", "player", "actions")
    os.makedirs(ax, exist_ok=True); os.makedirs(xml, exist_ok=True)
    out = os.path.join(ax, "Bob_DazedPullStartGenerator.X")
    write_x(BASE, out, "Bob_DazedPullStartGenerator", TPS, keys, (NFRAMES - 1) * TPS // FPS)
    open(os.path.join(xml, "DazedPullStart.xml"), "w", newline="\n").write(ANIMSET_XML)
    return out


def preview(poses):
    """Builds the skinned Bob mesh, keys the pull on an armature and adds a stand-in generator."""
    import bpy
    from mathutils import Matrix
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            coll.remove(d)
    # .X is Y-up facing -Z; Blender is Z-up, so rotate +90 deg about X (character faces +Y).
    C = np.array([[1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]], float)
    Ci = np.linalg.inv(C)
    verts, faces, skins = mesh_data(BASE)
    rest = BASE.world({b: BASE.frames[b] for b in BASE.order})
    bind = {b: (np.linalg.inv(skins[b][2]) if b in skins else rest[b]) for b in BASE.order if b != "Body"}
    bones = [b for b in BASE.order if b != "Body"]

    arm_data = bpy.data.armatures.new("BobRig")
    arm = bpy.data.objects.new("BobRig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for b in bones:
        eb = arm_data.edit_bones.new(b)
        M = C @ bind[b]
        R = M[:3, :3] / np.linalg.norm(M[:3, :3], axis=0)
        eb.head = M[:3, 3]; eb.tail = M[:3, 3] + R[:, 1] * 0.03
        kids = [c for c in bones if BASE.parent[c] == b]
        if kids:
            L = np.linalg.norm((C @ bind[kids[0]])[:3, 3] - M[:3, 3])
            if L > 0.005:
                eb.tail = M[:3, 3] + R[:, 1] * L
        m = Matrix([list(r) for r in np.vstack([np.column_stack([R, M[:3, 3]]), [0, 0, 0, 1]])])
        L = eb.length; eb.matrix = m; eb.length = L
    for b in bones:
        p = BASE.parent[b]
        if p and p in arm_data.edit_bones:
            arm_data.edit_bones[b].parent = arm_data.edit_bones[p]
    bpy.ops.object.mode_set(mode="OBJECT")

    me = bpy.data.meshes.new("Bob")
    me.from_pydata([tuple((C[:3, :3] @ v)) for v in verts], [], faces)
    body = bpy.data.objects.new("Bob", me)
    bpy.context.scene.collection.objects.link(body)
    for b, (idx, w, _) in skins.items():
        vg = body.vertex_groups.new(name=b)
        for i, wt in zip(idx, w):
            vg.add([i], wt, "ADD")
    mod = body.modifiers.new("Armature", "ARMATURE"); mod.object = arm
    body.parent = arm
    skin = bpy.data.materials.new("Skin"); skin.diffuse_color = (0.75, 0.6, 0.5, 1); me.materials.append(skin)
    for poly in me.polygons:
        poly.use_smooth = True

    # Pose keys: armature-space pose = C W bind^-1 C^-1 restLocal, then basis relative to the parent.
    scn = bpy.context.scene
    scn.render.fps = FPS; scn.frame_start = 0; scn.frame_end = NFRAMES - 1
    rl = {b: np.array(arm_data.bones[b].matrix_local) for b in bones}
    for f, P in enumerate(poses):
        posed = {b: C @ P.W[b] @ np.linalg.inv(bind[b]) @ Ci @ rl[b] for b in bones}
        for b in bones:
            p = BASE.parent[b]
            if p in posed:
                basis = np.linalg.inv(np.linalg.inv(rl[p]) @ rl[b]) @ np.linalg.inv(posed[p]) @ posed[b]
            else:
                basis = np.linalg.inv(rl[b]) @ posed[b]
            pb = arm.pose.bones[b]; pb.rotation_mode = "QUATERNION"
            loc, q, sc = Matrix([list(r) for r in basis]).decompose()
            pb.location, pb.rotation_quaternion, pb.scale = loc, q, sc
            pb.keyframe_insert("location", frame=f); pb.keyframe_insert("rotation_quaternion", frame=f); pb.keyframe_insert("scale", frame=f)

    # Stand-in generator box so contact points can be judged.
    x0, x1, z0, z1, h = GEN
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2, -(z0 + z1) / 2, h / 2))
    gen = bpy.context.active_object; gen.name = "Generator"; gen.scale = (x1 - x0, z1 - z0, h)
    gm = bpy.data.materials.new("GenRed"); gm.diffuse_color = (0.55, 0.12, 0.08, 1); gen.data.materials.append(gm)
    bpy.ops.mesh.primitive_plane_add(size=3, location=(0, 0, 0))
    fl = bpy.context.active_object; fl.name = "Floor"
    fm = bpy.data.materials.new("Floor"); fm.diffuse_color = (0.3, 0.3, 0.3, 1); fl.data.materials.append(fm)

    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scn.collection.objects.link(cam); scn.camera = cam
    cam.location = (1.15, 0.75, 0.55)
    tgt = bpy.data.objects.new("CamTarget", None); scn.collection.objects.link(tgt); tgt.location = (0, 0.05, 0.33)
    tc = cam.constraints.new("TRACK_TO"); tc.target = tgt; tc.track_axis = "TRACK_NEGATIVE_Z"; tc.up_axis = "UP_Y"
    cam.data.lens = 40
    scn.frame_set(0)
    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            sp = area.spaces[0]
            sp.shading.type = "SOLID"; sp.shading.color_type = "MATERIAL"
            sp.region_3d.view_perspective = "CAMERA"
            sp.overlay.show_bones = True


def run():
    global BASE, GRIP_SRC
    import os
    BASE = XFile(os.path.join(PZ_ANIMS, "Bob_SquatLoop.X"))
    GRIP_SRC = XFile(os.path.join(PZ_ANIMS, "Bob_IdleChainsaw_Start.X"))
    poses = [build_frame(f) for f in range(NFRAMES)]
    keys = {b: [] for b in BASE.order}
    for f, P in enumerate(poses):
        L = P.locals()
        for b in BASE.order:
            keys[b].append((f * TPS // FPS, L[b]))
    out = install(MOD_MEDIA, keys)
    print("DazedPullStart: wrote", out)
    try:
        import bpy  # noqa: F401
    except ImportError:
        return
    preview(poses)


run()
