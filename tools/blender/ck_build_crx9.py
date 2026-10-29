"""Crimson Knight: Earth-RED — CR-X9 hero builder (Blender 4.2+ / 5.x).

Builds the playable CR-X9 Crimson Knight from scratch, procedurally and reproducibly:
  * humanoid armature (skeleton contract from docs/BLENDER_RIGGING_AND_MULTIVIEW.md)
    + 5 cape strips x 4 control bones
  * skinned black undersuit (Skin modifier body, automatic bone-heat weights)
  * rigid hard-surface crimson armor plates, each weighted 100% to one bone
    (plates follow joints without deforming)
  * skinned cape weighted across the cape chains
  * PBR materials textured with the supplied assets/materials PNGs (embedded in the GLB)
  * 22 keyframed clips named CK_<Action>, authored with planted-foot leg IK solved in
    Python and baked to FK rotations (no IK constraints reach the GLB)

Outputs:
  assets/models/characters/crimson_knight_CRX9_rigged.glb   (Y-up, metres, faces +Z in Three.js)
  assets/source/blender/crimson_knight_CRX9_rigged.blend    (includes the original blockout as a reference)
  config/crx9_clips.json                                    (clip metadata used by the game)

Run from the project root:
  blender -b --factory-startup --python tools/blender/ck_build_crx9.py

The original blockout assets/models/characters/crimson_knight_CRX9.glb is only read, never modified.
Blender convention inside this script: Z up, character faces -Y, character's left side is +X.
"""
import json
import math
import os
import sys
from math import cos, pi, radians, sin

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FPS = 30
HEIGHT = 1.95
OUT_GLB = os.path.join(ROOT, "assets", "models", "characters", "crimson_knight_CRX9_rigged.glb")
OUT_BLEND = os.path.join(ROOT, "assets", "source", "blender", "crimson_knight_CRX9_rigged.blend")
OUT_CLIPS = os.path.join(ROOT, "config", "crx9_clips.json")
BLOCKOUT = os.path.join(ROOT, "assets", "models", "characters", "crimson_knight_CRX9.glb")

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))
FWD = Vector((0, -1, 0))
IDQ = Quaternion()
SIDES = (("L", 1.0), ("R", -1.0))


def Q(axis, deg):
    return Quaternion(axis, radians(deg))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# --------------------------------------------------------------------------------------
# Skeleton
# --------------------------------------------------------------------------------------
def joints():
    J = {
        "hips": Vector((0, 0, 0.98)), "spine": Vector((0, 0, 1.10)), "chest": Vector((0, 0, 1.26)),
        "chest_top": Vector((0, 0, 1.48)), "neck": Vector((0, 0, 1.50)), "head": Vector((0, -0.01, 1.62)),
        "head_top": Vector((0, -0.01, 1.84)),
    }
    for s, k in SIDES:
        d = Vector((k * sin(radians(45)), 0, -cos(radians(45))))  # A-pose, 45 deg from vertical
        J["arm_dir_" + s] = d
        J["clav_" + s] = Vector((k * 0.03, 0, 1.46))
        J["sh_" + s] = Vector((k * 0.19, 0.01, 1.47))
        J["el_" + s] = J["sh_" + s] + d * 0.30
        J["wr_" + s] = J["el_" + s] + d * 0.27
        J["hand_" + s] = J["wr_" + s] + d * 0.17
        J["hip_" + s] = Vector((k * 0.10, 0, 0.97))
        J["knee_" + s] = Vector((k * 0.105, -0.005, 0.53))
        J["ankle_" + s] = Vector((k * 0.105, 0.02, 0.10))
        J["ball_" + s] = Vector((k * 0.11, -0.11, 0.03))
        J["toe_" + s] = Vector((k * 0.11, -0.19, 0.03))
    return J


CAPE_STRIPS = 5
CAPE_SEGS = 4


def cape_point(u, t):
    """Cape surface point; u in [-1,1] across, t in [0,1] top->bottom."""
    half_w = 0.20 + 0.22 * t
    x = half_w * u
    y = 0.155 + 0.08 * t - 0.05 * u * u * (1 - t)
    z = 1.48 - 1.22 * t
    return Vector((x, y, z))


def bone_defs(J):
    B = [
        ("Hips", J["hips"], J["spine"], None),
        ("Spine", J["spine"], J["chest"], "Hips"),
        ("Chest", J["chest"], J["chest_top"], "Spine"),
        ("Neck", J["neck"], J["head"], "Chest"),
        ("Head", J["head"], J["head_top"], "Neck"),
    ]
    for s, _k in SIDES:
        B += [
            ("Shoulder_" + s, J["clav_" + s], J["sh_" + s], "Chest"),
            ("UpperArm_" + s, J["sh_" + s], J["el_" + s], "Shoulder_" + s),
            ("LowerArm_" + s, J["el_" + s], J["wr_" + s], "UpperArm_" + s),
            ("Hand_" + s, J["wr_" + s], J["hand_" + s], "LowerArm_" + s),
            ("UpperLeg_" + s, J["hip_" + s], J["knee_" + s], "Hips"),
            ("LowerLeg_" + s, J["knee_" + s], J["ankle_" + s], "UpperLeg_" + s),
            ("Foot_" + s, J["ankle_" + s], J["ball_" + s], "LowerLeg_" + s),
            ("Toes_" + s, J["ball_" + s], J["toe_" + s], "Foot_" + s),
        ]
    for i in range(CAPE_STRIPS):
        u = -1 + 2 * i / (CAPE_STRIPS - 1)
        parent = "Chest"
        for j in range(CAPE_SEGS):
            name = f"Cape_{i}_{j}"
            B.append((name, cape_point(u, j / CAPE_SEGS), cape_point(u, (j + 1) / CAPE_SEGS), parent))
            parent = name
    return B


def build_armature(J):
    data = bpy.data.armatures.new("CRX9_Armature")
    obj = bpy.data.objects.new("CRX9_Rig", data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in bone_defs(J):
        eb = data.edit_bones.new(name)
        eb.head, eb.tail = head, tail
        eb.roll = 0.0
        if parent:
            eb.parent = data.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in obj.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return obj


# --------------------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------------------
MATS = ["CK_CrimsonShell", "CK_Undersuit", "CK_Gunmetal", "CK_EmissiveRed", "CK_CapeCloth"]


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1.0]


TEX_DIR = os.path.join(ROOT, "assets", "materials")


def make_materials():
    """Hero materials use Owen's supplied PNGs in assets/materials as base-colour (and emission) maps."""
    spec = {
        "CK_CrimsonShell": dict(tex="crimson_metal.png", metallic=0.35, rough=0.48),
        "CK_Undersuit": dict(tex="black_rubber.png", metallic=0.0, rough=0.72),
        "CK_Gunmetal": dict(tex="gunmetal.png", metallic=0.85, rough=0.32),
        "CK_EmissiveRed": dict(tex="red_emissive.png", metallic=0.0, rough=0.4, emit=6.0),
        "CK_CapeCloth": dict(tex="crimson_metal.png", metallic=0.0, rough=0.86, double=True, darken=0.55),
    }
    out = {}
    for name in MATS:
        s = spec[name]
        m = bpy.data.materials.new(name)
        if bpy.app.version < (5, 0, 0):
            m.use_nodes = True  # always on (and deprecated) from Blender 5.0
        nodes, links = m.node_tree.nodes, m.node_tree.links
        bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(TEX_DIR, s["tex"]), check_existing=True)
        tex.interpolation = "Linear"
        color_out = tex.outputs["Color"]
        if "darken" in s:  # cape: same crimson PNG, multiplied darker for cloth
            mix = nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs["B"].default_value = (s["darken"],) * 3 + (1.0,)
            links.new(color_out, mix.inputs["A"])
            color_out = mix.outputs["Result"]
        links.new(color_out, bsdf.inputs["Base Color"])
        bsdf.inputs["Metallic"].default_value = s["metallic"]
        bsdf.inputs["Roughness"].default_value = s["rough"]
        if "emit" in s:
            links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = s["emit"]
        m.use_backface_culling = not s.get("double", False)
        px = tex.image.pixels[:4]
        m.diffuse_color = (px[0], px[1], px[2], 1.0)
        out[name] = m
    return out


# --------------------------------------------------------------------------------------
# Geometry helpers
# --------------------------------------------------------------------------------------
def frame(z_axis, x_hint=None):
    """Rotation matrix whose local Z points along z_axis (local X near x_hint)."""
    z = z_axis.normalized()
    if x_hint is None:
        return Z.rotation_difference(z).to_matrix()
    x = (x_hint - z * x_hint.dot(z)).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed()


def bevel_sharp(bm, offset, segs=2, angle=40):
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > radians(angle)]
    if edges and offset > 0:
        bmesh.ops.bevel(bm, geom=edges, offset=offset, offset_type="OFFSET", segments=segs,
                        profile=0.5, affect="EDGES", clamp_overlap=True)


def prim_box(dims, taper_top=(1, 1), taper_bot=(1, 1), bevel=0.01, segs=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        sx, sy = taper_top if v.co.z > 0 else taper_bot
        v.co.x *= dims[0] * sx
        v.co.y *= dims[1] * sy
        v.co.z *= dims[2]
    bevel_sharp(bm, min(bevel, min(dims) * 0.45), segs)
    return bm


def prim_cyl(r1, r2, depth, segs=20, bevel=0.006):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth)
    bevel_sharp(bm, bevel, 2, angle=50)
    return bm


def prim_sphere(scale, u=24, v=14):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    for vert in bm.verts:
        vert.co = Vector((vert.co.x * scale[0], vert.co.y * scale[1], vert.co.z * scale[2]))
    return bm


def prim_cone(r, depth, segs=4, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=segs, radius1=r, radius2=0.0, depth=depth)
    for vert in bm.verts:
        vert.co = Vector((vert.co.x * scale[0], vert.co.y * scale[1], vert.co.z * scale[2]))
    return bm


class PartBuilder:
    """Collects rigid parts into one mesh: every vertex weighted 1.0 to its part's bone."""

    def __init__(self):
        self.verts, self.faces, self.vbone, self.fmat = [], [], [], []

    def add(self, bm, bone, mat, at, rot=None):
        m = Matrix.Translation(at) @ (rot.to_4x4() if rot is not None else Matrix.Identity(4))
        bm.verts.index_update()
        base = len(self.verts)
        for v in bm.verts:
            self.verts.append(m @ v.co)
            self.vbone.append(bone)
        for f in bm.faces:
            self.faces.append([base + v.index for v in f.verts])
            self.fmat.append(MATS.index(mat))
        bm.free()

    def to_object(self, name, mats, rig):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        me.update()
        for m in MATS:
            me.materials.append(mats[m])
        me.polygons.foreach_set("material_index", self.fmat)
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        groups = {}
        for i, b in enumerate(self.vbone):
            groups.setdefault(b, []).append(i)
        for b, idx in groups.items():
            obj.vertex_groups.new(name=b).add(idx, 1.0, "REPLACE")
        attach(obj, rig)
        finish_mesh(me, 35)
        return obj


def attach(obj, rig):
    obj.parent = rig
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = rig


def finish_mesh(me, sharp_deg):
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    if hasattr(me, "set_sharp_from_angle"):
        me.set_sharp_from_angle(angle=radians(sharp_deg))
    box_project_uv(me)
    me.update()


def box_project_uv(me, scale=1.5):
    """Simple tri-planar box projection so every mesh carries valid UVs for later texturing."""
    uv = me.uv_layers.new(name="UVMap")
    co = [v.co for v in me.vertices]
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            p = co[me.loops[li].vertex_index]
            a, b = [(p.y, p.z), (p.x, p.z), (p.x, p.y)][ax]
            uv.data[li].uv = (a * scale, b * scale)


# --------------------------------------------------------------------------------------
# Undersuit (skinned body)
# --------------------------------------------------------------------------------------
def build_undersuit(J, mats, rig):
    pts, rad, edges = [], [], []

    def P(co, r):
        pts.append(Vector(co))
        rad.append(r if isinstance(r, tuple) else (r, r))
        return len(pts) - 1

    def chain(*ids):
        for a, b in zip(ids, ids[1:]):
            edges.append((a, b))

    pelvis = P((0, 0, 0.98), (0.13, 0.10))
    waist = P((0, 0, 1.12), (0.125, 0.092))
    chest = P((0, -0.005, 1.28), (0.17, 0.11))
    upper = P((0, 0, 1.42), (0.185, 0.105))
    nbase = P((0, 0, 1.51), 0.062)
    ntop = P((0, -0.005, 1.60), 0.056)
    head = P((0, -0.01, 1.70), (0.085, 0.095))
    htop = P((0, -0.01, 1.80), 0.06)
    chain(pelvis, waist, chest, upper, nbase, ntop, head, htop)
    for s, k in SIDES:
        d = J["arm_dir_" + s]
        clav = P(J["sh_" + s] - Vector((k * 0.07, 0.005, 0.02)), 0.065)
        sh = P(J["sh_" + s], 0.068)
        ua = P(J["sh_" + s] + d * 0.15, 0.064)
        el = P(J["el_" + s], 0.05)
        fa = P(J["el_" + s] + d * 0.12, 0.054)
        wr = P(J["wr_" + s], 0.036)
        hm = P(J["wr_" + s] + d * 0.08, 0.042)
        he = P(J["hand_" + s], 0.024)
        chain(upper, clav, sh, ua, el, fa, wr, hm, he)
        hip = P(J["hip_" + s] - Vector((k * 0.01, 0, 0.04)), 0.098)
        th = P(J["hip_" + s].lerp(J["knee_" + s], 0.5), 0.09)
        kn = P(J["knee_" + s], 0.062)
        sn = P(J["knee_" + s].lerp(J["ankle_" + s], 0.45), 0.062)
        an = P(J["ankle_" + s], 0.043)
        bl = P(J["ball_" + s] + Vector((0, 0, 0.005)), 0.04)
        tt = P(J["toe_" + s] + Vector((0, 0.01, 0)), 0.028)
        chain(pelvis, hip, th, kn, sn, an, bl, tt)

    me = bpy.data.meshes.new("CRX9_UndersuitSkin")
    me.from_pydata([tuple(p) for p in pts], edges, [])
    obj = bpy.data.objects.new("CRX9_UndersuitSkin", me)
    bpy.context.scene.collection.objects.link(obj)
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.branch_smoothing = 0.4
    for i, r in enumerate(rad):
        sv = me.skin_vertices[0].data[i]
        sv.radius = r
        sv.use_root = (i == pelvis)
    sub = obj.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = sub.render_levels = 2
    dg = bpy.context.evaluated_depsgraph_get()
    body = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj)
    body.name = "CRX9_Undersuit"
    body.materials.append(mats["CK_Undersuit"])
    out = bpy.data.objects.new("CRX9_Undersuit", body)
    bpy.context.scene.collection.objects.link(out)
    finish_mesh(body, 80)

    # automatic (bone-heat) weights on body bones only
    cape = [b for b in rig.data.bones if b.name.startswith("Cape_")]
    for b in cape:
        b.use_deform = False
    bpy.ops.object.select_all(action="DESELECT")
    out.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for b in cape:
        b.use_deform = True
    fill_missing_weights(out, rig)
    return out


def fill_missing_weights(obj, rig):
    """Bone heat can fail on a few vertices; give those nearest-bone weights instead."""
    segs = [(b.name, b.head_local, b.tail_local) for b in rig.data.bones if not b.name.startswith("Cape_")]
    fixed = 0
    for v in obj.data.vertices:
        if sum(g.weight for g in v.groups) > 1e-4:
            continue
        best = []
        for name, h, t in segs:
            ab = t - h
            tt = max(0.0, min(1.0, (v.co - h).dot(ab) / ab.length_squared))
            best.append(((v.co - (h + ab * tt)).length, name))
        best.sort()
        (d0, n0), (d1, n1) = best[0], best[1]
        w0 = 1 / max(d0, 1e-4) ** 4
        w1 = 1 / max(d1, 1e-4) ** 4
        for n, w in ((n0, w0 / (w0 + w1)), (n1, w1 / (w0 + w1))):
            vg = obj.vertex_groups.get(n) or obj.vertex_groups.new(name=n)
            vg.add([v.index], w, "REPLACE")
        fixed += 1
    print(f"[CRX9] undersuit: {len(obj.data.vertices)} verts, {fixed} filled by nearest-bone fallback")


# --------------------------------------------------------------------------------------
# Armor (rigid plates)
# --------------------------------------------------------------------------------------
def build_armor(J, mats, rig):
    A = PartBuilder()
    C, U, G, E = "CK_CrimsonShell", "CK_Undersuit", "CK_Gunmetal", "CK_EmissiveRed"

    # --- helmet (Head) ---
    A.add(prim_sphere((0.118, 0.13, 0.145), 28, 18), "Head", C, Vector((0, -0.012, 1.735)))
    A.add(prim_box((0.17, 0.09, 0.11), taper_bot=(0.62, 0.85), bevel=0.018, segs=3), "Head", C, Vector((0, -0.085, 1.672)))
    A.add(prim_box((0.10, 0.05, 0.04), bevel=0.012), "Head", G, Vector((0, -0.102, 1.613)))
    A.add(prim_box((0.20, 0.04, 0.03), taper_top=(0.82, 1), bevel=0.01), "Head", C, Vector((0, -0.132, 1.768)))
    A.add(prim_box((0.15, 0.02, 0.036), bevel=0.006), "Head", U, Vector((0, -0.137, 1.742)))
    for s, k in SIDES:
        A.add(prim_box((0.05, 0.012, 0.013), bevel=0.004), "Head", E, Vector((k * 0.041, -0.147, 1.743)),
              Q(Y, -k * 12).to_matrix())
        # long ears: tall thin pyramids, base sunk into the dome
        rot = (Q(Y, -k * 8) @ Q(X, -6)).to_matrix()
        A.add(prim_cone(0.036, 0.25, 4, (1.0, 0.45, 1.0)), "Head", C, Vector((k * 0.068, 0.012, 1.955)), rot)
        # cheek guards
        A.add(prim_box((0.02, 0.10, 0.08), bevel=0.008), "Head", C, Vector((k * 0.112, -0.03, 1.69)), Q(Z, k * 8).to_matrix())

    # --- neck / torso ---
    A.add(prim_cyl(0.078, 0.066, 0.07, 24), "Chest", C, Vector((0, 0.0, 1.525)))
    A.add(prim_box((0.42, 0.26, 0.24), taper_bot=(0.76, 0.9), bevel=0.035, segs=3), "Chest", C, Vector((0, -0.018, 1.36)))
    for s, k in SIDES:  # pectoral plates
        A.add(prim_box((0.17, 0.03, 0.12), taper_bot=(0.85, 1), bevel=0.012), "Chest", C, Vector((k * 0.095, -0.148, 1.405)), Q(Z, -k * 10).to_matrix())
    A.add(prim_box((0.34, 0.06, 0.22), taper_bot=(0.8, 1), bevel=0.02), "Chest", C, Vector((0, 0.11, 1.365)))
    A.add(prim_box((0.03, 0.03, 0.20), bevel=0.01), "Chest", G, Vector((0, 0.14, 1.36)))
    # Owen Enterprises chest emblem: black diamond with red emissive core
    face = frame(FWD, X)
    A.add(prim_cone(0.07, 0.02, 4, (0.85, 1.35, 1)), "Chest", U, Vector((0, -0.166, 1.37)), face @ Q(Z, 45).to_matrix())
    A.add(prim_cone(0.035, 0.012, 4, (0.85, 1.35, 1)), "Chest", E, Vector((0, -0.176, 1.37)), face @ Q(Z, 45).to_matrix())
    for i, z in enumerate((1.135, 1.185, 1.235)):
        w = 0.21 + 0.012 * i
        A.add(prim_box((w, 0.19, 0.042), taper_bot=(0.92, 0.95), bevel=0.012), "Spine", C, Vector((0, -0.012, z)))

    # --- belt / pelvis (Hips) ---
    A.add(prim_box((0.30, 0.215, 0.06), bevel=0.012), "Hips", G, Vector((0, 0, 1.035)))
    A.add(prim_box((0.075, 0.02, 0.05), bevel=0.008), "Hips", C, Vector((0, -0.112, 1.035)))
    A.add(prim_box((0.03, 0.006, 0.012), bevel=0.002), "Hips", E, Vector((0, -0.123, 1.035)))
    for s, k in SIDES:
        A.add(prim_box((0.045, 0.04, 0.055), bevel=0.008), "Hips", U, Vector((k * 0.105, -0.09, 1.03)))
        A.add(prim_box((0.04, 0.05, 0.055), bevel=0.008), "Hips", U, Vector((k * 0.155, 0.0, 1.03)))
        A.add(prim_box((0.045, 0.04, 0.055), bevel=0.008), "Hips", U, Vector((k * 0.10, 0.09, 1.03)))
    A.add(prim_box((0.26, 0.20, 0.08), taper_bot=(0.55, 0.85), bevel=0.015), "Hips", C, Vector((0, -0.028, 0.958)))

    # --- arms ---
    for s, k in SIDES:
        d = J["arm_dir_" + s]
        out = Vector((k * 0.7071, 0, 0.7071))  # outward normal of the A-posed arm
        sh, el, wr, hd = J["sh_" + s], J["el_" + s], J["wr_" + s], J["hand_" + s]
        # pauldron + layered rim
        A.add(prim_sphere((0.118, 0.12, 0.092)), "UpperArm_" + s, C, sh + Vector((k * 0.018, 0, 0.035)),
              Q(Y, -k * 22).to_matrix())
        A.add(prim_box((0.012, 0.13, 0.05), bevel=0.004), "UpperArm_" + s, G, sh + Vector((k * 0.07, 0, 0.09)),
              Q(Y, -k * 30).to_matrix())
        A.add(prim_cyl(0.07, 0.062, 0.15), "UpperArm_" + s, C, sh.lerp(el, 0.58), frame(d, out))
        A.add(prim_sphere((0.054, 0.054, 0.054), 16, 10), "LowerArm_" + s, G, el)
        A.add(prim_cyl(0.064, 0.054, 0.2), "LowerArm_" + s, C, el.lerp(wr, 0.55), frame(d, out))
        for t in (0.35, 0.55, 0.75):  # scalloped forearm fins, on the back of the forearm
            A.add(prim_box((0.008, 0.05, 0.032), taper_top=(1, 0.4), bevel=0.003), "LowerArm_" + s, G,
                  el.lerp(wr, t) + Vector((0, 0.068, 0)), frame(d, out) @ Q(X, 20).to_matrix())
        if s == "L":  # wrist module (summon / scanner)
            A.add(prim_box((0.05, 0.022, 0.06), bevel=0.006), "LowerArm_L", G, el.lerp(wr, 0.72) + Vector((0, -0.055, 0)),
                  frame(d, out))
            A.add(prim_box((0.022, 0.006, 0.022), bevel=0.002), "LowerArm_L", E, el.lerp(wr, 0.72) + Vector((0, -0.067, 0)),
                  frame(d, out))
        A.add(prim_box((0.022, 0.07, 0.075), bevel=0.008), "Hand_" + s, C, wr.lerp(hd, 0.42) + out * 0.02,
              frame(d, out))

    # --- legs ---
    for s, k in SIDES:
        hip, kn, an = J["hip_" + s], J["knee_" + s], J["ankle_" + s]
        legd = (kn - hip).normalized()
        shind = (an - kn).normalized()
        side = Vector((k, 0, 0))
        A.add(prim_cyl(0.104, 0.086, 0.30), "UpperLeg_" + s, C, hip.lerp(kn, 0.42), frame(legd, side))
        A.add(prim_box((0.03, 0.05, 0.16), bevel=0.01), "UpperLeg_" + s, G, hip.lerp(kn, 0.42) + Vector((k * 0.1, 0, 0)))
        A.add(prim_box((0.095, 0.045, 0.11), taper_top=(0.8, 1), bevel=0.016), "LowerLeg_" + s, C, kn + Vector((0, -0.072, 0.005)))
        A.add(prim_cyl(0.072, 0.056, 0.30), "LowerLeg_" + s, C, kn.lerp(an, 0.5), frame(shind, side))
        A.add(prim_box((0.03, 0.02, 0.25), bevel=0.008), "LowerLeg_" + s, G, kn.lerp(an, 0.5) + Vector((0, -0.068, 0)))
        A.add(prim_cyl(0.06, 0.058, 0.07, 20), "LowerLeg_" + s, G, an + Vector((0, 0, 0.045)))
        A.add(prim_box((0.105, 0.20, 0.10), taper_top=(0.9, 0.72), bevel=0.02), "Foot_" + s, U,
              Vector((k * 0.107, -0.04, 0.055)))
        A.add(prim_box((0.112, 0.21, 0.016), bevel=0.005), "Foot_" + s, U, Vector((k * 0.107, -0.045, 0.008)))
        A.add(prim_box((0.10, 0.075, 0.062), taper_top=(0.9, 0.6), bevel=0.016), "Toes_" + s, C,
              Vector((k * 0.11, -0.165, 0.034)))
    return A.to_object("CRX9_Armor", mats, rig)


# --------------------------------------------------------------------------------------
# Cape (skinned to cape chains)
# --------------------------------------------------------------------------------------
def build_cape(mats, rig):
    cols, rows = 12, 20
    verts, faces = [], []
    for r in range(rows + 1):
        for c in range(cols + 1):
            verts.append(cape_point(-1 + 2 * c / cols, r / rows))
    for r in range(rows):
        for c in range(cols):
            a = r * (cols + 1) + c
            faces.append([a, a + 1, a + cols + 2, a + cols + 1])
    me = bpy.data.meshes.new("CRX9_Cape")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.materials.append(mats["CK_CapeCloth"])
    obj = bpy.data.objects.new("CRX9_Cape", me)
    bpy.context.scene.collection.objects.link(obj)

    weights = {}
    for r in range(rows + 1):
        t = r / rows
        for c in range(cols + 1):
            vi = r * (cols + 1) + c
            fu = c / cols * (CAPE_STRIPS - 1)
            i0 = min(int(fu), CAPE_STRIPS - 2)
            wu = fu - i0
            ft = t * CAPE_SEGS
            if ft < 0.5:  # top hem blends into the chest so the cape stays attached
                segw = [("Chest", 1 - ft * 2), (0, ft * 2)]
            else:
                g = ft - 0.5
                j0 = min(int(g), CAPE_SEGS - 1)
                wj = g - j0
                j1 = min(j0 + 1, CAPE_SEGS - 1)
                segw = [(j0, 1 - wj), (j1, wj)]
            for seg, sw in segw:
                if sw <= 0:
                    continue
                if seg == "Chest":
                    weights.setdefault("Chest", []).append((vi, sw))
                    continue
                for strip, stw in ((i0, 1 - wu), (i0 + 1, wu)):
                    if stw > 0:
                        weights.setdefault(f"Cape_{strip}_{seg}", []).append((vi, sw * stw))
    for name, lst in weights.items():
        vg = obj.vertex_groups.new(name=name)
        acc = {}
        for vi, w in lst:
            acc[vi] = acc.get(vi, 0) + w
        for vi, w in acc.items():
            vg.add([vi], w, "REPLACE")
    attach(obj, rig)
    finish_mesh(me, 80)
    return obj


# --------------------------------------------------------------------------------------
# Animation: pose parameters -> world-space bone rotations -> FK basis keys
# --------------------------------------------------------------------------------------
DEFAULT = dict(
    hx=0.0, hy=0.0, hz=-0.015, hp=0.0, hyaw=0.0, hr=0.0,
    sp=0.0, syaw=0.0, sr=0.0, cp=0.0, cyaw=0.0, cr=0.0, np=0.0, hdp=0.0, hdyaw=0.0, hdr=0.0,
    capelift=4.0, capewave=0.0, capeph=0.0, capespread=0.0, legik=1.0,
)
for _s, _k in SIDES:
    DEFAULT.update({
        f"sw_{_s}": 0.0, f"ad_{_s}": 32.0, f"tw_{_s}": 0.0, f"elb_{_s}": 12.0, f"wr_{_s}": 0.0, f"shr_{_s}": 0.0,
        f"fx_{_s}": _k * 0.025, f"fy_{_s}": 0.0, f"fz_{_s}": 0.0, f"fp_{_s}": 0.0, f"tp_{_s}": 0.0, f"fyaw_{_s}": _k * 7.0,
        f"th_{_s}": 0.0, f"kn_{_s}": 0.0, f"thab_{_s}": 0.0, f"ank_{_s}": 0.0,
    })


def qe(pitch=0.0, yaw=0.0, roll=0.0):
    """pitch>0 tips the top of a bone forward (a hanging bone swings back); yaw about Z; roll about Y."""
    return Q(Z, yaw) @ Q(X, pitch) @ Q(Y, roll)


class Poser:
    def __init__(self, rig, J):
        self.rig, self.J = rig, J
        self.rest = {}
        self.order = []
        for b in rig.data.bones:
            self.rest[b.name] = (b.matrix_local.to_quaternion(), b.head_local.copy(), b.tail_local.copy(),
                                 b.parent.name if b.parent else None)
        # hierarchy order (parents before children)
        pending = [b.name for b in rig.data.bones]
        while pending:
            for n in list(pending):
                p = self.rest[n][3]
                if p is None or p in self.order:
                    self.order.append(n)
                    pending.remove(n)

    def rest_dir(self, name):
        _, h, t, _ = self.rest[name]
        return (t - h).normalized()

    def length(self, name):
        _, h, t, _ = self.rest[name]
        return (t - h).length

    def solve(self, P):
        J, G = self.J, {}
        off = Vector((P["hx"], P["hy"], P["hz"]))
        hips = qe(P["hp"], P["hyaw"], P["hr"])
        G["Hips"] = hips
        G["Spine"] = hips @ qe(P["sp"], P["syaw"], P["sr"])
        G["Chest"] = G["Spine"] @ qe(P["cp"], P["cyaw"], P["cr"])
        G["Neck"] = G["Chest"] @ qe(P["np"])
        G["Head"] = G["Neck"] @ qe(P["hdp"], P["hdyaw"], P["hdr"])
        hips_head = self.rest["Hips"][1]
        for s, k in SIDES:
            G["Shoulder_" + s] = G["Chest"] @ Q(Y, -k * P["shr_" + s])
            d = self.rest_dir("UpperArm_" + s)
            hinge = d.cross(FWD).normalized()
            G["UpperArm_" + s] = G["Shoulder_" + s] @ Q(X, -P["sw_" + s]) @ Q(Y, k * P["ad_" + s]) @ Q(d, k * P["tw_" + s])
            G["LowerArm_" + s] = G["UpperArm_" + s] @ Q(hinge, P["elb_" + s])
            G["Hand_" + s] = G["LowerArm_" + s] @ Q(hinge, P["wr_" + s])
            if P["legik"] >= 0.5:
                hip_pos = hips_head + off + hips @ (self.rest["UpperLeg_" + s][1] - hips_head)
                target = J["ankle_" + s] + Vector((P["fx_" + s], P["fy_" + s], P["fz_" + s]))
                pole = Q(Z, P["hyaw"] + P["fyaw_" + s] * 0.5) @ FWD
                th_dir, sh_dir = self.two_bone(hip_pos, target, self.length("UpperLeg_" + s),
                                               self.length("LowerLeg_" + s), pole)
                G["UpperLeg_" + s] = self.rest_dir("UpperLeg_" + s).rotation_difference(th_dir)
                G["LowerLeg_" + s] = self.rest_dir("LowerLeg_" + s).rotation_difference(sh_dir)
                G["Foot_" + s] = Q(Z, P["fyaw_" + s]) @ Q(X, P["fp_" + s])
                G["Toes_" + s] = Q(Z, P["fyaw_" + s]) @ Q(X, P["tp_" + s])
            else:
                G["UpperLeg_" + s] = hips @ Q(X, -P["th_" + s]) @ Q(Y, -k * P["thab_" + s])
                G["LowerLeg_" + s] = G["UpperLeg_" + s] @ Q(X, P["kn_" + s])
                G["Foot_" + s] = G["LowerLeg_" + s] @ Q(X, P["ank_" + s])
                G["Toes_" + s] = G["Foot_" + s]
        for i in range(CAPE_STRIPS):
            u = -1 + 2 * i / (CAPE_STRIPS - 1)
            acc = 0.0
            for j in range(CAPE_SEGS):
                acc += P["capelift"] / CAPE_SEGS + P["capewave"] * sin(P["capeph"] - j * 0.9 - i * 0.35)
                G[f"Cape_{i}_{j}"] = G["Chest"] @ Q(Y, -u * P["capespread"]) @ Q(X, acc)
        self.extra(G, P)
        basis = {}
        for n in self.order:
            R, _h, _t, par = self.rest[n]
            g = G[n] if n in G else (G[par] if par else IDQ)
            G[n] = g
            gp = G[par] if par else IDQ
            basis[n] = R.inverted() @ gp.inverted() @ g @ R
        loc = self.rest["Hips"][0].inverted() @ off
        return basis, loc

    def extra(self, G, P):
        """Hook for subclasses (v2 adds finger curl). Bones left out of G follow their parent."""

    @staticmethod
    def two_bone(hip, target, l1, l2, pole):
        d = target - hip
        dist = max(1e-3, min(d.length, l1 + l2 - 1e-4))
        u = d.normalized()
        a = math.acos(max(-1.0, min(1.0, (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist))))
        p = pole - u * pole.dot(u)
        p = p.normalized() if p.length > 1e-6 else FWD
        knee = hip + (u * cos(a) + p * sin(a)) * l1
        return (knee - hip).normalized(), (hip + u * dist - knee).normalized()


def P_(**kw):
    p = dict(DEFAULT)
    p.update(kw)
    return p


def lerp_params(a, b, t):
    return {k: a[k] + (b[k] - a[k]) * t for k in a}


def keyed(keys):
    """keys: [(frame, params)], eased pose-to-pose interpolation."""
    def f(frame):
        for (f0, a), (f1, b) in zip(keys, keys[1:]):
            if f0 <= frame <= f1:
                return lerp_params(a, b, smooth((frame - f0) / max(1, f1 - f0)))
        return dict(keys[-1][1])
    return f


def locomotion(T, ref_speed, beta, swing_h, hips_base, bob, lean, arm_amp, elbow, ad, cape_lift, cape_wave,
               strafe=0.0, crouch_lean=0.0, low_at_midstance=False, sway=0.02, kick=0.0, hip_yaw=5.0):
    S = ref_speed * beta * T / FPS  # body travel while one foot is planted

    def f(frame):
        phi = frame / T
        P = P_()
        for s, off in (("L", 0.0), ("R", 0.5)):
            k = 1 if s == "L" else -1
            p = (phi + off) % 1.0
            if p < beta:
                u = p / beta
                d = -S / 2 + S * u
                z = 0.0
                fp = -14 * (1 - smooth(u / 0.2)) + 34 * smooth((u - 0.62) / 0.38)
                tp = 0.0
            else:
                v = (p - beta) / (1 - beta)
                d = S / 2 - S * smooth(v) + kick * sin(pi * v) * (1 - v)
                z = swing_h * sin(pi * v) + kick * 0.6 * sin(pi * min(1.0, v * 1.6)) * (1 - v)
                fp = 34 * (1 - smooth(v / 0.6)) - 14 * smooth((v - 0.6) / 0.4)
                tp = fp * min(1.0, v / 0.2) * min(1.0, (1 - v) / 0.2)
            z += 0.115 * sin(radians(max(fp, 0.0)))
            if strafe:
                P["fx_" + s] = DEFAULT["fx_" + s] - strafe * d
                P["fy_" + s] = (0.07 if s == "L" else -0.07) * (z > 0.01) * strafe
            else:
                P["fy_" + s] = d
            P["fz_" + s], P["fp_" + s], P["tp_" + s] = z, fp, tp
        w = 2 * pi * phi
        low = w * 2 - (2 * pi * beta if low_at_midstance else 0.0)
        P["hz"] = hips_base - bob * cos(low)
        P["hx"] = sway * cos(w - pi * beta) if not strafe else 0.0
        P["hyaw"] = -hip_yaw * cos(w) if not strafe else 0.0
        P["hr"] = 2.0 * sin(w)
        P["sp"] = lean * 0.5 + crouch_lean
        P["cp"] = lean * 0.5
        P["cyaw"] = (hip_yaw * 1.8 * cos(w)) if not strafe else 0.0
        P["hdp"] = -(lean + crouch_lean) * 0.7
        P["hdyaw"] = -P["hyaw"] - P["cyaw"] * 0.7
        for s, sign in (("L", -1), ("R", 1)):
            swing = sign * arm_amp * cos(w)
            P["sw_" + s] = swing + lean * 0.3
            P["ad_" + s] = ad
            P["elb_" + s] = elbow + 0.5 * elbow * max(0.0, swing / max(arm_amp, 1e-3))
        P["capelift"] = cape_lift
        P["capewave"] = cape_wave
        P["capeph"] = 2 * w
        if strafe:
            P["sr"] = -strafe * 3
            P["capespread"] = 4 * strafe
        return P
    return f


def breathing(T, base, amp=1.0):
    def f(frame):
        w = 2 * pi * frame / T
        P = dict(base)
        P["cp"] += 1.4 * amp * sin(w)
        P["hz"] += -0.004 * amp * sin(w)
        P["hx"] += 0.008 * amp * sin(w / 1)
        P["shr_L"] += 1.2 * amp * sin(w)
        P["shr_R"] += 1.2 * amp * sin(w)
        P["hdyaw"] += 2.5 * amp * sin(w)
        P["capewave"] = 1.5
        P["capeph"] = w
        return P
    return f


def clip_table():
    idle = P_()
    crouch = P_(hz=-0.33, hy=0.06, sp=22, cp=10, hdp=-26, sw_L=18, sw_R=18, elb_L=45, elb_R=45, ad_L=28, ad_R=28,
                fx_L=0.06, fx_R=-0.06, fy_L=-0.10, fy_R=0.06, fp_R=10, fyaw_L=12, fyaw_R=-12, capelift=10)
    jump_crouch = P_(hz=-0.24, hy=0.04, sp=18, cp=8, hdp=-14, sw_L=-38, sw_R=-38, ad_L=26, ad_R=26, elb_L=18, elb_R=18)
    jump_push = P_(hz=0.06, sp=-3, cp=-4, hdp=-6, sw_L=110, sw_R=110, ad_L=30, ad_R=30, elb_L=28, elb_R=28,
                   fp_L=38, fp_R=38, fz_L=0.07, fz_R=0.07, capelift=-6)
    jump_off = P_(hz=0.11, sp=-4, cp=-5, hdp=-8, sw_L=140, sw_R=140, ad_L=30, ad_R=30, elb_L=30, elb_R=30,
                  fp_L=55, fp_R=55, fz_L=0.12, fz_R=0.12, capelift=-10)
    land_contact = P_(hz=-0.03, sw_L=28, sw_R=28, ad_L=5, ad_R=5, elb_L=30, elb_R=30, fp_L=-8, fp_R=-8, capelift=30)
    land_absorb = P_(hz=-0.26, hy=0.05, sp=16, cp=8, hdp=-14, sw_L=30, sw_R=30, ad_L=20, ad_R=20, elb_L=35, elb_R=35,
                     capelift=-4, capewave=3)
    hero_land = P_(hz=-0.55, hy=0.06, sp=30, cp=14, hdp=-34, hdyaw=-6,
                   fx_L=0.12, fy_L=-0.30, fyaw_L=12, fx_R=-0.06, fy_R=0.44, fz_R=0.035, fp_R=58, tp_R=0, fyaw_R=-4,
                   sw_R=28, ad_R=36, elb_R=6, wr_R=0, sw_L=-62, ad_L=-8, elb_L=24, capelift=-24, capespread=14)
    hero_hold = dict(hero_land, hz=-0.53, capelift=-18, capespread=8, hdp=-28)
    aim = P_(hz=-0.04, fy_L=-0.13, fy_R=0.12, fyaw_L=4, fyaw_R=-22, cyaw=12, syaw=4, sp=-2, hdp=-8, hdyaw=-10,
             sw_R=98, ad_R=40, elb_R=0, tw_R=0, sw_L=22, ad_L=28, elb_L=40)
    seated = P_(hz=-0.43, hy=0.10, sp=-8, cp=-4, hdp=10, fy_L=-0.40, fy_R=-0.40, fx_L=0.06, fx_R=-0.06, fp_L=-6, fp_R=-6,
                sw_L=48, sw_R=48, ad_L=40, ad_R=40, elb_L=58, elb_R=58, capelift=-2)
    step_in = P_(hz=-0.05, fy_L=-0.22, fz_L=0.22, hdp=8, sp=6, sw_L=-10, sw_R=25, elb_L=20, elb_R=25)
    sink = P_(hz=-0.38, hy=0.13, sp=14, cp=6, fy_L=-0.34, fy_R=-0.22, fz_L=0.03, sw_L=30, sw_R=30, elb_L=40, elb_R=40)
    belt = P_(sw_R=-8, ad_R=38, elb_R=72, tw_R=-20, hdp=12, hdyaw=-8, cyaw=-4)
    ready = P_(sw_R=58, ad_R=44, elb_R=78, tw_R=-10, hdp=4, cyaw=8, sw_L=12, elb_L=24)
    summon_a = P_(sw_L=58, ad_L=52, elb_L=118, tw_L=10, sw_R=30, ad_R=45, elb_R=60, hdp=16, hdyaw=10, cyaw=-6)
    summon_b = P_(sw_L=60, ad_L=54, elb_L=122, tw_L=10, sw_R=46, ad_R=56, elb_R=96, hdp=18, hdyaw=10, cyaw=-6)
    press = P_(sw_R=74, ad_R=40, elb_R=22, hdp=6, cyaw=10, fy_R=-0.08, hz=-0.03)

    def fk(**kw):
        return P_(legik=0.0, **kw)

    # combat poses (Godot port): guard high, short strikes with a step and a chest twist
    guard = P_(hz=-0.08, sp=6, cp=4, hdp=-4, fy_L=0.10, fy_R=-0.12, fyaw_L=-8, fyaw_R=14, cyaw=8,
               sw_L=62, ad_L=30, elb_L=112, sw_R=56, ad_R=34, elb_R=118, capelift=4)
    wind_r = dict(guard, cyaw=22, sw_R=34, elb_R=128, hz=-0.1)
    jab_r = dict(guard, cyaw=-26, syaw=-8, sw_R=92, ad_R=16, elb_R=4, fy_R=0.02, hz=-0.12, sp=10, capelift=14)
    wind_l = dict(guard, cyaw=-6, sw_L=40, elb_L=124)
    jab_l = dict(guard, cyaw=24, syaw=8, sw_L=88, ad_L=48, elb_L=36, fy_L=0.16, hz=-0.12, sp=10, capelift=12)
    heavy_wind = dict(guard, hz=-0.04, sp=-10, cp=-8, hdp=-10, sw_L=150, sw_R=150, ad_L=20, ad_R=20, elb_L=60, elb_R=60, cyaw=0)
    heavy_hit = dict(guard, hz=-0.34, sp=34, cp=16, hdp=8, sw_L=70, sw_R=70, ad_L=12, ad_R=12, elb_L=10, elb_R=10, cyaw=0,
                     fy_L=0.22, capelift=26, capewave=4)
    parry = dict(guard, cyaw=26, sw_L=104, ad_L=58, elb_L=96, tw_L=30, hdyaw=8)
    dodge_low = P_(hz=-0.42, hy=0.08, sp=30, cp=12, hdp=-20, syaw=18, fx_L=0.10, fx_R=-0.18, fy_L=0.06, fy_R=-0.16,
                   sw_L=40, ad_L=34, elb_L=100, sw_R=36, ad_R=34, elb_R=104, capelift=34, capespread=10)
    vault_plant = P_(hz=-0.12, sp=26, cp=12, hdp=-10, sw_L=78, sw_R=78, ad_L=16, ad_R=16, elb_L=8, elb_R=8, capelift=20)
    vault_over = fk(sp=34, cp=14, hdp=-14, th_L=86, kn_L=118, th_R=74, kn_R=104, ank_L=20, ank_R=20,
                    sw_L=70, sw_R=70, ad_L=18, ad_R=18, elb_L=4, elb_R=4, capelift=60, capewave=6)
    climb_pull = fk(sp=-4, cp=-2, hdp=-16, th_L=12, kn_L=28, th_R=4, kn_R=18, ank_L=14, ank_R=14,
                    sw_L=118, sw_R=118, ad_L=26, ad_R=26, elb_L=104, elb_R=104, capelift=8)
    climb_knee = fk(sp=30, cp=12, hdp=-8, th_L=96, kn_L=112, th_R=8, kn_R=24, ank_L=20, ank_R=10,
                    sw_L=56, sw_R=56, ad_L=24, ad_R=24, elb_L=22, elb_R=22, capelift=22)
    slide_low = fk(sp=-20, cp=-10, hdp=10, th_L=78, kn_L=20, th_R=40, kn_R=96, ank_L=10, ank_R=30,
                   sw_L=-20, ad_L=40, elb_L=20, sw_R=40, ad_R=30, elb_R=30, capelift=-8, capespread=6)

    def ledge_hang(frame):
        w = 2 * pi * frame / 40
        return fk(sp=-2, cp=-2, hdp=-12, th_L=8 + 3 * sin(w), kn_L=18, th_R=2 - 3 * sin(w), kn_R=12, ank_L=20, ank_R=24,
                  sw_L=168, sw_R=168, ad_L=18, ad_R=18, elb_L=16, elb_R=16, capelift=-2, capewave=2, capeph=w)

    def airborne(frame):
        w = 2 * pi * frame / 30
        return fk(th_L=36 + 4 * sin(w), kn_L=62, th_R=14 - 4 * sin(w), kn_R=48, ank_L=18, ank_R=24,
                  sw_L=22 + 6 * sin(w), sw_R=22 - 6 * sin(w), ad_L=2, ad_R=2, elb_L=32, elb_R=32,
                  hdp=-6, capelift=48, capewave=9, capeph=2 * w)

    def grapple_pull(frame):
        w = 2 * pi * frame / 24
        return fk(sp=-8, cp=-6, hdp=-18, th_L=-16 + 5 * sin(w), kn_L=34, th_R=-24 - 5 * sin(w), kn_R=50, ank_L=30, ank_R=34,
                  sw_R=162, ad_R=30, elb_R=14, sw_L=148, ad_L=34, elb_L=22, capelift=76, capewave=12, capeph=2 * w)

    def glide(frame):
        w = 2 * pi * frame / 40
        return fk(sp=4, cp=2, hdp=-30, th_L=-4, th_R=-4, kn_L=10 + 3 * sin(w), kn_R=10 - 3 * sin(w), ank_L=40, ank_R=40,
                  sw_L=8, sw_R=8, ad_L=-42 + 3 * sin(w), ad_R=-42 + 3 * sin(w), elb_L=12, elb_R=12, wr_L=-10, wr_R=-10,
                  capelift=82, capewave=5, capeph=2 * w, capespread=46)

    drive = breathing(60, seated, 0.6)
    # CR-B1: Batpod-style prone ride. Authored upright; the game pitches the hero ~72 deg forward on the seat,
    # so the head tilts back to keep the eyes on the road, arms reach forward to the low grips and the shins
    # fold back onto the rear pegs.
    ride_prone_base = fk(hz=-0.43, sp=6, cp=4, np=-20, hdp=-58, th_L=40, kn_L=100, th_R=40, kn_R=100, ank_L=-10, ank_R=-10,
                         sw_L=84, sw_R=84, ad_L=24, ad_R=24, elb_L=44, elb_R=44, wr_L=-12, wr_R=-12, tw_L=-8, tw_R=-8,
                         capelift=-10, capespread=4)
    ride_prone = breathing(60, ride_prone_base, 0.4)
    # CR-X1: reclined cockpit (driver lies back ~35 deg, legs out forward to the pedals, hands on the yoke).
    # The game pitches the hero back on the seat; the head tips forward to look through the canopy.
    drive_recline_base = fk(hz=-0.43, sp=-6, cp=-4, np=12, hdp=26, th_L=62, kn_L=26, th_R=62, kn_R=26, ank_L=12, ank_R=12,
                            sw_L=30, sw_R=30, ad_L=30, ad_R=30, elb_L=78, elb_R=78, capelift=-6)
    drive_recline = breathing(60, drive_recline_base, 0.5)

    # name, frames, loop, ref_speed (m/s, None = stationary), pose function, description
    return [
        ("CK_Idle", 60, True, None, breathing(60, idle), "breathing, weight shift, cape sway"),
        ("CK_Walk", 32, True, 1.6, locomotion(32, 1.6, 0.6, 0.09, -0.03, 0.012, 2, 22, 14, 34, 12, 4, hip_yaw=6),
         "planted-foot walk cycle"),
        ("CK_Run", 20, True, 5.0, locomotion(20, 5.0, 0.32, 0.22, -0.06, 0.03, 14, 48, 78, 40, 30, 5,
                                             low_at_midstance=True, sway=0.01, kick=0.18, hip_yaw=7),
         "run cycle with flight phase"),
        ("CK_Sprint", 16, True, 8.0, locomotion(16, 8.0, 0.26, 0.26, -0.08, 0.035, 24, 62, 88, 42, 46, 5,
                                                low_at_midstance=True, sway=0.006, kick=0.26, hip_yaw=8),
         "sprint, strong forward lean, cape streaming"),
        ("CK_StrafeLeft", 24, True, 1.0, locomotion(24, 1.0, 0.55, 0.08, -0.05, 0.008, 0, 6, 18, 32, 8, 3, strafe=1.0),
         "side-step toward character's left"),
        ("CK_StrafeRight", 24, True, 1.0, locomotion(24, 1.0, 0.55, 0.08, -0.05, 0.008, 0, 6, 18, 32, 8, 3, strafe=-1.0),
         "side-step toward character's right"),
        ("CK_CrouchIdle", 60, True, None, breathing(60, crouch, 0.8), "low ready crouch"),
        ("CK_CrouchWalk", 36, True, 1.0, locomotion(36, 1.0, 0.62, 0.07, -0.30, 0.01, 16, 14, 40, 28, 12, 3,
                                                    crouch_lean=10, sway=0.015, hip_yaw=4),
         "stealth crouch walk"),
        ("CK_JumpStart", 14, False, None, keyed([(0, idle), (5, jump_crouch), (10, jump_push), (14, jump_off)]),
         "anticipation + take-off; game applies the vertical impulse at frame 10"),
        ("CK_Airborne", 30, True, None, airborne, "in-air loop, cape lifting"),
        ("CK_LandSoft", 16, False, None, keyed([(0, land_contact), (5, land_absorb), (16, idle)]), "soft landing"),
        ("CK_LandHard", 34, False, None,
         keyed([(0, hero_land), (12, hero_hold), (24, P_(hz=-0.2, sp=10, hdp=-6, capelift=2)), (34, idle)]),
         "three-point hero landing then rise"),
        ("CK_GrappleAim", 30, True, None, breathing(30, aim, 0.5), "grapnel arm raised and aimed"),
        ("CK_GrapplePull", 24, True, None, grapple_pull, "being reeled toward the grapple point"),
        ("CK_Glide", 40, True, None, glide, "cape-wing glide; game pitches the root for flight"),
        ("CK_GadgetDraw", 18, False, None, keyed([(0, idle), (7, belt), (18, ready)]), "draw fictional gadget from belt"),
        ("CK_GadgetStow", 18, False, None, keyed([(0, ready), (10, belt), (18, idle)]), "return gadget to belt"),
        ("CK_Summon", 45, False, None,
         keyed([(0, idle), (10, summon_a), (16, summon_b), (22, summon_a), (28, summon_b), (36, summon_a), (45, idle)]),
         "wrist-module vehicle call"),
        ("CK_VehicleEnter", 40, False, None, keyed([(0, idle), (12, step_in), (26, sink), (40, seated)]),
         "generic step-in and sit; game blends root to the vehicle seat_attach"),
        ("CK_VehicleExit", 36, False, None, keyed([(0, seated), (12, sink), (24, step_in), (36, idle)]),
         "generic stand-up and step-out"),
        ("CK_Drive", 60, True, None, drive, "seated driving loop"),
        ("CK_RideProne", 60, True, None, ride_prone, "CR-B1 prone ride; game pitches the root forward on the seat"),
        ("CK_DriveRecline", 60, True, None, drive_recline, "CR-X1 reclined drive; game pitches the root back on the seat"),
        ("CK_Interact", 24, False, None, keyed([(0, idle), (9, press), (14, press), (24, idle)]), "reach and press"),
        # ---- melee (Godot port combat): fast strikes that start and end in the guard, so they chain ----
        ("CK_Guard", 30, True, None, breathing(30, guard, 0.6), "fighting guard, both fists up"),
        ("CK_PunchR", 14, False, None, keyed([(0, guard), (4, wind_r), (7, jab_r), (14, guard)]), "right straight, steps in"),
        ("CK_PunchL", 14, False, None, keyed([(0, guard), (4, wind_l), (7, jab_l), (14, guard)]), "left hook"),
        ("CK_HeavyStrike", 26, False, None, keyed([(0, guard), (9, heavy_wind), (14, heavy_hit), (18, heavy_hit), (26, guard)]),
         "two-handed hammer strike; impact at frame 14"),
        ("CK_Counter", 18, False, None, keyed([(0, guard), (4, parry), (9, jab_r), (18, guard)]),
         "parry with the left forearm, answer with the right"),
        ("CK_Dodge", 16, False, None, keyed([(0, guard), (5, dodge_low), (11, dodge_low), (16, guard)]),
         "low evasive duck; the game moves the root sideways"),
        # ---- traversal ----
        ("CK_Vault", 22, False, None, keyed([(0, idle), (5, vault_plant), (11, vault_over), (16, vault_plant), (22, idle)]),
         "hands on the obstacle, legs tucked over; the game carries the root across"),
        ("CK_LedgeHang", 40, True, None, ledge_hang, "hanging from a ledge by both hands"),
        ("CK_LedgeClimb", 30, False, None, keyed([(0, ledge_hang(0)), (10, climb_pull), (20, climb_knee), (30, idle)]),
         "pull up and step onto the ledge; the game lifts the root"),
        ("CK_Slide", 24, False, None, keyed([(0, idle), (5, slide_low), (18, slide_low), (24, idle)]), "low slide under obstacles"),
    ]


def bake_clips(rig, J, poser_cls=None):
    poser = (poser_cls or Poser)(rig, J)
    ad = rig.animation_data or rig.animation_data_create()
    meta = []
    for name, frames, loop, ref_speed, fn, desc in CLIP_TABLE():
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        ad.action = act
        prev = {}
        for f in range(frames + 1):
            basis, loc = poser.solve(fn(f if not loop else f % frames if f < frames else 0))
            for pb in rig.pose.bones:
                q = basis[pb.name]
                if pb.name in prev and prev[pb.name].dot(q) < 0:
                    q = -q
                prev[pb.name] = q
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.location = loc if pb.name == "Hips" else Vector()
                pb.keyframe_insert("location", frame=f)
        act.use_frame_range = True
        act.frame_start, act.frame_end = 0, frames
        if hasattr(act, "use_cyclic"):
            act.use_cyclic = loop
        track = ad.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        track.mute = True
        ad.action = None
        meta.append({"name": name, "frames": frames, "fps": FPS, "duration": round(frames / FPS, 4),
                     "loop": loop, "refSpeed": ref_speed, "description": desc})
        print(f"[CRX9] baked {name}: {frames} frames")
    for pb in rig.pose.bones:
        pb.rotation_quaternion = IDQ
        pb.location = Vector()
    return meta


# --------------------------------------------------------------------------------------
# Export / reference / main
# --------------------------------------------------------------------------------------
CLIP_TABLE = clip_table  # v2 wraps this to add per-clip finger grip


def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    opts = dict(
        filepath=path, export_format="GLB", use_selection=False, export_yup=True, export_apply=False,
        export_texcoord=True, export_normals=True, export_materials="EXPORT", export_image_format="AUTO",
        export_skins=True, export_all_influences=False, export_def_bones=False,
        export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
        export_optimize_animation_size=False, export_optimize_animation_keep_anim_armature=True,
        export_anim_single_armature=True, export_reset_pose_bones=True, export_anim_slide_to_zero=False,
        export_cameras=False, export_lights=False, export_extras=False,
    )
    valid = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    bpy.ops.export_scene.gltf(**{k: v for k, v in opts.items() if k in valid})


def add_blockout_reference():
    """Import the ChatGPT blockout, scaled to 1.95 m, beside the hero for comparison (.blend only)."""
    if not os.path.exists(BLOCKOUT):
        return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=BLOCKOUT)
    new = [o for o in bpy.data.objects if o not in before]
    coll = bpy.data.collections.new("REF_Blockout_CRX9_original")
    bpy.context.scene.collection.children.link(coll)
    holder = bpy.data.objects.new("REF_Blockout_Root", None)
    coll.objects.link(holder)
    for o in new:
        for c in o.users_collection:
            c.objects.unlink(o)
        coll.objects.link(o)
        if o.parent is None:
            o.parent = holder
    holder.scale = (HEIGHT / 4.26,) * 3  # blockout spans -0.47..3.79 m (helmet top)
    holder.location = (1.4, 0, 0.47 * HEIGHT / 4.26)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.unit_settings.system = "METRIC"
    J = joints()
    rig = build_armature(J)
    mats = make_materials()
    body = build_undersuit(J, mats, rig)
    armor = build_armor(J, mats, rig)
    cape = build_cape(mats, rig)
    meta = bake_clips(rig, J)
    scene.frame_start, scene.frame_end = 0, 60
    export_glb(OUT_GLB)
    add_blockout_reference()
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)

    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in (body, armor, cape))
    info = {
        "asset": "assets/models/characters/crimson_knight_CRX9_rigged.glb",
        "source": "tools/blender/ck_build_crx9.py",
        "height_m": HEIGHT,
        "forward": "+Z (Three.js)",
        "skeleton_bones": len(rig.data.bones),
        "triangles": tris,
        "clips": meta,
    }
    with open(OUT_CLIPS, "w") as fh:
        json.dump(info, fh, indent=2)
    print(f"[CRX9] OK bones={len(rig.data.bones)} tris={tris} clips={len(meta)} -> {OUT_GLB}")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
