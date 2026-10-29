"""Crimson Knight: Earth-RED — CR-X9 War Suit, version 2 (Blender 4.2+ / 5.x).

Upgrades the v1 procedural hero (tools/blender/ck_build_crx9.py, kept unchanged) toward the concept boards:
  * armor built from SURFACE-CONFORMING PANELS: each plate is cut from a body-shaped surface (torso
    ellipsoid, tapered limb surfaces, helmet shell), given real thickness and bevelled edges, so plates
    layer with genuine panel gaps and the black undersuit shows between them
  * winged chest emblem conformed to the chest, layered pauldrons, mechanical knee hubs + pistons,
    finned gauntlets, segmented abdomen, heavy boots with treads, long blade ears, narrow lens eyes
  * skeleton: Root bone, finger bones (thumb + 4 fingers, 2 segments), non-deforming attachment sockets
    (hands, back, belt, head)
  * generated detail textures (armor micro-scratch normal + roughness variation, undersuit technical
    weave normal) with Owen's assets/materials PNGs kept as base colours; clearcoat paint
  * LOD0/LOD1/LOD2 meshes in one GLB (game switches by camera distance)
  * the same 22 CK_* clips (v1 poser + clip table) plus per-clip finger grip

Run from the project root:
  blender -b --factory-startup --python tools/blender/ck_build_crx9_v2.py
Writes assets/models/characters/crimson_knight_CRX9_rigged.glb (v1 remains in git history and as
assets/models/characters/crimson_knight_CRX9_rigged_v1.glb), the .blend, config/crx9_clips.json and
textures in assets/source/textures/.
"""
import json
import math
import os
import shutil
import sys
from math import cos, pi, radians, sin

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ck_build_crx9 as v1  # noqa: E402  (skeleton maths, poser, clip table, export)

ROOT = v1.ROOT
OUT_GLB = v1.OUT_GLB
OUT_V1 = OUT_GLB.replace("_rigged.glb", "_rigged_v1.glb")
OUT_BLEND = os.path.join(ROOT, "assets", "source", "blender", "crimson_knight_CRX9_v2.blend")
TEX_OUT = os.path.join(ROOT, "assets", "source", "textures")
X, Y, Z, FWD, Q, SIDES = v1.X, v1.Y, v1.Z, v1.FWD, v1.Q, v1.SIDES
C, U, G, E, K = "CK_CrimsonShell", "CK_Undersuit", "CK_Gunmetal", "CK_EmissiveRed", "CK_CapeCloth"
FINGERS = [("Index", 0.030, 0.046, 0.038), ("Middle", 0.010, 0.050, 0.040), ("Ring", -0.010, 0.047, 0.037), ("Pinky", -0.028, 0.038, 0.030)]


# ======================================================================================
# Skeleton v2: Root, shorter palm, fingers, sockets
# ======================================================================================
def joints():
    J = v1.joints()
    for s, k in SIDES:
        d = J["arm_dir_" + s]
        J["hand_" + s] = J["wr_" + s] + d * 0.085  # palm ends at the knuckles; fingers continue
        J["palm_n_" + s] = Vector((-k * 0.7071, 0, -0.7071))  # palm faces the body in the A-pose
    return J


def bone_defs(J):
    B = [("Root", Vector((0, 0, 0)), Vector((0, 0.25, 0)), None)]
    for name, h, t, parent in v1.bone_defs(J):
        B.append((name, h, t, parent or "Root"))
    for s, k in SIDES:
        d = J["arm_dir_" + s]
        kn = J["hand_" + s]
        for fname, off, l1, l2 in FINGERS:
            base = kn + Vector((0, -off, 0))  # spread along -Y: index finger forward
            m = base + d * l1
            B.append((f"{fname}1_{s}", base, m, "Hand_" + s))
            B.append((f"{fname}2_{s}", m, m + d * l2, f"{fname}1_{s}"))
        tb = J["wr_" + s] + d * 0.03 + Vector((0, -0.032, 0)) + J["palm_n_" + s] * 0.012
        td = (d * 0.55 + FWD * 0.85).normalized()
        B.append((f"Thumb1_{s}", tb, tb + td * 0.04, "Hand_" + s))
        B.append((f"Thumb2_{s}", tb + td * 0.04, tb + td * 0.075, f"Thumb1_{s}"))
        B.append((f"Socket_Hand_{s}", J["wr_" + s] + d * 0.06 + J["palm_n_" + s] * 0.035, J["wr_" + s] + d * 0.12 + J["palm_n_" + s] * 0.035, "Hand_" + s))
    B += [
        ("Socket_Back", Vector((0, 0.16, 1.38)), Vector((0, 0.16, 1.5)), "Chest"),
        ("Socket_Belt_R", Vector((-0.17, -0.02, 1.0)), Vector((-0.17, -0.02, 0.92)), "Hips"),
        ("Socket_Belt_L", Vector((0.17, -0.02, 1.0)), Vector((0.17, -0.02, 0.92)), "Hips"),
        ("Socket_Head", Vector((0, -0.02, 1.86)), Vector((0, -0.12, 1.86)), "Head"),
    ]
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
    bpy.ops.object.mode_set(mode="OBJECT")
    for b in data.bones:
        if b.name.startswith("Socket_") or b.name == "Root":
            b.use_deform = False
    for pb in obj.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return obj


# ======================================================================================
# Procedural detail textures (numpy) — tileable, saved as PNG and packed into the GLB
# ======================================================================================
def tile_noise(n, scale, seed):
    rng = np.random.default_rng(seed)
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    r = np.sqrt(fx * fx + fy * fy) + 1e-6
    spec = (rng.normal(size=(n, n)) + 1j * rng.normal(size=(n, n))) * np.exp(-(r * scale) ** 2) / r ** 0.6
    out = np.real(np.fft.ifft2(spec))
    return (out - out.min()) / (out.max() - out.min())


def scratches(n, count, seed):
    rng = np.random.default_rng(seed)
    h = np.zeros((n, n))
    for _ in range(count):
        x0, y0 = rng.uniform(0, n, 2)
        ang = rng.uniform(0, pi)
        length = rng.uniform(n * 0.02, n * 0.12)
        steps = int(length)
        xs = (x0 + np.cos(ang) * np.arange(steps)).astype(int) % n
        ys = (y0 + np.sin(ang) * np.arange(steps)).astype(int) % n
        h[ys, xs] += rng.uniform(0.4, 1.0)
    return np.clip(h, 0, 1)


def height_to_normal(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = 1 / np.sqrt(dx * dx + dy * dy + 1)
    return np.stack([-dx * nz * 0.5 + 0.5, dy * nz * 0.5 + 0.5, nz * 0.5 + 0.5], -1)


def save_image(name, rgb, non_color):
    n = rgb.shape[0]
    img = bpy.data.images.new(name, n, n, alpha=False)
    rgba = np.concatenate([rgb, np.ones((n, n, 1))], -1).astype(np.float32)
    img.pixels.foreach_set(rgba.ravel())
    os.makedirs(TEX_OUT, exist_ok=True)
    img.filepath_raw = os.path.join(TEX_OUT, name + ".png")
    img.file_format = "PNG"
    img.save()
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    img.pack()
    return img


def make_textures():
    n = 512
    T = {}
    # armor: low-frequency roughness variation + fine scratches (glossier where scratched)
    low = tile_noise(n, 18, 1)
    scr = scratches(n, 260, 2)
    for key, rough0, rough_amp, metal in (("crimson", 0.36, 0.14, 0.4), ("gunmetal", 0.30, 0.16, 0.9), ("suit", 0.62, 0.12, 0.0)):
        r = np.clip(rough0 + (low - 0.5) * rough_amp - scr * 0.12, 0.05, 1)
        T[key + "_mr"] = save_image(f"crx9_{key}_mr", np.stack([np.ones_like(r), r, np.full_like(r, metal)], -1), True)
    T["armor_n"] = save_image("crx9_armor_normal", height_to_normal(scr * 0.6 + tile_noise(n, 80, 3) * 0.15, 2.2), True)
    # undersuit: hexagonal technical weave
    yy, xx = np.mgrid[0:n, 0:n] / n * 24
    a = np.cos(xx * 2 * pi) + np.cos((xx * 0.5 + yy * 0.866) * 2 * pi) + np.cos((-xx * 0.5 + yy * 0.866) * 2 * pi)
    weave = (a - a.min()) / (a.max() - a.min())
    T["suit_n"] = save_image("crx9_suit_normal", height_to_normal(weave ** 1.5, 3.0), True)
    return T


# ======================================================================================
# Materials (Owen's PNGs as base colour + generated detail)
# ======================================================================================
def make_materials(T):
    spec = {
        C: dict(tex="crimson_metal.png", mr="crimson_mr", n="armor_n", coat=0.55),
        U: dict(tex="black_rubber.png", mr="suit_mr", n="suit_n"),
        G: dict(tex="gunmetal.png", mr="gunmetal_mr", n="armor_n"),
        E: dict(tex="red_emissive.png", emit=10.0, rough=0.35),
        K: dict(tex="crimson_metal.png", rough=0.85, double=True, darken=0.5),
    }
    out = {}
    for name in v1.MATS:
        s = spec[name]
        m = bpy.data.materials.new(name)
        nodes, links = m.node_tree.nodes, m.node_tree.links
        bsdf = next(nd for nd in nodes if nd.type == "BSDF_PRINCIPLED")
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(v1.TEX_DIR, s["tex"]), check_existing=True)
        col = tex.outputs["Color"]
        if "darken" in s:
            mix = nodes.new("ShaderNodeMix")
            mix.data_type, mix.blend_type = "RGBA", "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs["B"].default_value = (s["darken"],) * 3 + (1.0,)
            links.new(col, mix.inputs["A"])
            col = mix.outputs["Result"]
        links.new(col, bsdf.inputs["Base Color"])
        if "mr" in s:  # glTF metallicRoughness: G = roughness, B = metallic
            mr = nodes.new("ShaderNodeTexImage")
            mr.image = T[s["mr"]]
            sep = nodes.new("ShaderNodeSeparateColor")
            links.new(mr.outputs["Color"], sep.inputs["Color"])
            links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
            links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
        else:
            bsdf.inputs["Roughness"].default_value = s.get("rough", 0.5)
            bsdf.inputs["Metallic"].default_value = 0.0
        if "n" in s:
            nt = nodes.new("ShaderNodeTexImage")
            nt.image = T[s["n"]]
            nm = nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = 0.6
            links.new(nt.outputs["Color"], nm.inputs["Color"])
            links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        if s.get("coat"):
            bsdf.inputs["Coat Weight"].default_value = s["coat"]
            bsdf.inputs["Coat Roughness"].default_value = 0.18
        if "emit" in s:
            links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = s["emit"]
        m.use_backface_culling = not s.get("double", False)
        out[name] = m
    return out


# ======================================================================================
# Surface-conforming panels
# ======================================================================================
def ellipsoid(c, r):
    """u: azimuth (0 = front/-Y, +pi/2 = character's left/+X), v: elevation. Returns (point, normal)."""
    def f(u, v):
        d = Vector((sin(u) * cos(v), -cos(u) * cos(v), sin(v)))
        p = Vector((c[0] + r[0] * d.x, c[1] + r[1] * d.y, c[2] + r[2] * d.z))
        n = Vector((d.x / r[0], d.y / r[1], d.z / r[2])).normalized()
        return p, n
    return f


def limb(a, b, ra, rb, k=1.0, oval=1.0, bulge=0.0):
    """Tapered cylinder from a to b. u: angle (0 = front, +pi/2 = outer side for side k), v: 0..1 along."""
    a, b = Vector(a), Vector(b)
    ax = (b - a).normalized()
    f = (FWD - ax * FWD.dot(ax)).normalized()
    sv = Vector((k, 0, 0))
    s = (sv - ax * sv.dot(ax) - f * sv.dot(f)).normalized()
    L = (b - a).length

    def fn(u, v):
        r = ra + (rb - ra) * v + bulge * sin(pi * v)
        n = (f * cos(u) * oval + s * sin(u)).normalized()
        p = a + ax * (v * L) + f * (cos(u) * r * oval) + s * (sin(u) * r)
        return p, n
    return fn


class Builder:
    """Collects rigid parts; every vertex weighted 1.0 to its bone; per-face material."""

    def __init__(self):
        self.verts, self.faces, self.vbone, self.fmat = [], [], [], []

    def add_bm(self, bm, bone, mat, xf=None):
        bm.verts.index_update()
        base = len(self.verts)
        for v in bm.verts:
            self.verts.append((xf @ v.co) if xf else v.co.copy())
            self.vbone.append(bone)
        for f in bm.faces:
            self.faces.append([base + v.index for v in f.verts])
            self.fmat.append(v1.MATS.index(mat))
        bm.free()

    def panel(self, surf, bone, mat, v0, v1_, ulo, uhi, nu=10, nv=8, offset=0.004, thick=0.007, bevel=0.0022, lift=None):
        """Plate cut from surf over v in [v0,v1] and u in [ulo(v), uhi(v)] (callables or numbers)."""
        lo = ulo if callable(ulo) else (lambda v, x=ulo: x)
        hi = uhi if callable(uhi) else (lambda v, x=uhi: x)
        bm = bmesh.new()
        grid = []
        for j in range(nv + 1):
            v = v0 + (v1_ - v0) * j / nv
            row = []
            for i in range(nu + 1):
                u = lo(v) + (hi(v) - lo(v)) * i / nu
                p, n = surf(u, v)
                off = offset + (lift(u, v) if lift else 0.0)
                row.append(bm.verts.new(p + n * off))
            grid.append(row)
        for j in range(nv):
            for i in range(nu):
                bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        # make the plate face outward (away from the surface centre) before giving it thickness
        p_mid, n_mid = surf((lo((v0 + v1_) / 2) + hi((v0 + v1_) / 2)) / 2, (v0 + v1_) / 2)
        f0 = min(bm.faces, key=lambda f: (f.calc_center_median() - p_mid).length)
        if f0.normal.dot(n_mid) < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        v1.bevel_sharp(bm, bevel, 1, angle=50)
        self.add_bm(bm, bone, mat)

    def shape(self, bm, bone, mat, at, rot=None):
        m = Matrix.Translation(at) @ (rot.to_4x4() if rot is not None else Matrix.Identity(4))
        self.add_bm(bm, bone, mat, m)

    def polygon_on(self, surf, pts_uv, bone, mat, offset, thick):
        """Extrude a 2D outline (list of (u,v)) conformed onto surf — used for the chest emblem."""
        bm = bmesh.new()
        vs = []
        for u, v in pts_uv:
            p, n = surf(u, v)
            vs.append(bm.verts.new(p + n * offset))
        face = bm.faces.new(vs)
        bmesh.ops.triangulate(bm, faces=[face])
        p_mid, n_mid = surf(sum(u for u, _ in pts_uv) / len(pts_uv), sum(v for _, v in pts_uv) / len(pts_uv))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        if bm.faces[0].normal.dot(n_mid) < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
        self.add_bm(bm, bone, mat)

    def to_object(self, name, mats, rig):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        me.update()
        for m in v1.MATS:
            me.materials.append(mats[m])
        me.polygons.foreach_set("material_index", self.fmat)
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        groups = {}
        for i, b in enumerate(self.vbone):
            groups.setdefault(b, []).append(i)
        for b, idx in groups.items():
            obj.vertex_groups.new(name=b).add(idx, 1.0, "REPLACE")
        v1.attach(obj, rig)
        v1.finish_mesh(me, 40)
        retile_uv(me, 3.0)
        return obj


def retile_uv(me, scale):
    uv = me.uv_layers.active
    for d in uv.data:
        d.uv = (d.uv[0] / 1.5 * scale, d.uv[1] / 1.5 * scale)


def wedge(length, width, thick, taper=0.15):
    """Blade fin / ear: a thin tapered prism pointing +Z."""
    bm = bmesh.new()
    pts = [(-width / 2, 0), (width / 2, 0), (width * taper / 2, length), (-width * taper / 2, length)]
    top = [bm.verts.new((x, thick / 2, z)) for x, z in pts]
    bot = [bm.verts.new((x, -thick / 2, z)) for x, z in pts]
    bm.faces.new(top)
    bm.faces.new(bot[::-1])
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((top[i], bot[i], bot[j], top[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


# ======================================================================================
# CR-X9 armor v2
# ======================================================================================
def build_armor(J, mats, rig):
    A = Builder()
    d2r = radians

    # ---------------- helmet (Head): narrow cowl, black eye sockets, ears grown from the cowl ----------------
    hc = (0, -0.014, 1.728)
    shell = ellipsoid(hc, (0.106, 0.126, 0.152))
    A.panel(shell, "Head", C, -0.75, 1.5, -pi, pi, nu=30, nv=16, offset=0.0, thick=0.008, bevel=0.0)  # base cowl
    for k in (1, -1):
        # angled black eye socket (outer end higher) with a narrow emissive lens inside
        A.panel(shell, "Head", U, 0.02, 0.27, (lambda v: 0.07 + v * 0.5) if k > 0 else (lambda v: -(0.66 + v * 0.7)),
                (lambda v: 0.66 + v * 0.7) if k > 0 else (lambda v: -(0.07 + v * 0.5)), nu=8, nv=3, offset=0.006, thick=0.004)
        A.panel(shell, "Head", E, 0.11, 0.17, (lambda v: 0.16 + v * 0.5) if k > 0 else (lambda v: -(0.56 + v * 0.9)),
                (lambda v: 0.56 + v * 0.9) if k > 0 else (lambda v: -(0.16 + v * 0.5)), nu=6, nv=2, offset=0.0105, thick=0.003, bevel=0.0)
        # cheek plates sweeping back toward the ears
        A.panel(shell, "Head", C, -0.7, 0.05, (lambda v: 0.55) if k > 0 else (lambda v: -1.75), (lambda v: 1.75) if k > 0 else (lambda v: -0.55),
                nu=10, nv=7, offset=0.011, thick=0.009)
        # ear root fairing on the crown, then the long blade ear rising out of it
        A.panel(shell, "Head", C, 0.85, 1.42, (lambda v: 0.55) if k > 0 else (lambda v: -2.05), (lambda v: 2.05) if k > 0 else (lambda v: -0.55),
                nu=8, nv=5, offset=0.006, thick=0.012)
        rot = (Q(Y, -k * 7) @ Q(X, -4)).to_matrix()
        A.shape(wedge(0.27, 0.105, 0.03, 0.05), "Head", C, Vector((k * 0.058, 0.004, 1.815)), rot)
        A.shape(wedge(0.2, 0.04, 0.034, 0.08), "Head", G, Vector((k * 0.058, 0.008, 1.83)), rot)
    A.panel(shell, "Head", C, 0.30, 0.52, -0.78, 0.78, nu=14, nv=3, offset=0.016, thick=0.011)  # heavy brow
    A.panel(shell, "Head", C, -0.35, 0.36, -0.09, 0.09, nu=2, nv=6, offset=0.012, thick=0.008)  # nose ridge
    A.panel(shell, "Head", C, 0.55, 1.3, -0.22, 0.22, nu=4, nv=6, offset=0.009, thick=0.006)  # crest
    A.panel(shell, "Head", C, -1.05, -0.3, -1.15, 1.15, nu=14, nv=5, offset=0.014, thick=0.01)  # armoured jaw
    A.panel(shell, "Head", G, -1.25, -0.95, -0.45, 0.45, nu=8, nv=2, offset=0.015, thick=0.008)  # chin
    A.panel(shell, "Head", U, -0.42, -0.3, -0.35, 0.35, nu=6, nv=1, offset=0.017, thick=0.003)  # mouth slit
    # neck: gorget rings
    for i, (z, r) in enumerate(((1.505, 0.078), (1.545, 0.070))):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=False, segments=24, radius1=r + 0.006, radius2=r, depth=0.04)
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.006)
        A.shape(bm, "Chest" if i == 0 else "Neck", G, Vector((0, 0.0, z)))

    # ---------------- torso (Chest / Spine / Hips) ----------------
    chest = ellipsoid((0, 0.008, 1.335), (0.212, 0.135, 0.205))
    for k in (1, -1):
        sg = lambda a, k=k: k * a
        lo = (lambda v: 0.07) if k > 0 else (lambda v: -(1.08 - 0.22 * v))
        hi = (lambda v: 1.08 - 0.22 * v) if k > 0 else (lambda v: -0.07)
        A.panel(chest, "Chest", C, 0.02, 0.92, lo, hi, nu=12, nv=10, offset=0.01, thick=0.012,
                lift=lambda u, v: 0.006 * sin(min(1, max(0, (v - 0.02) / 0.9)) * pi))  # pectoral plates
        A.panel(chest, "Chest", C, -0.58, -0.04, (lambda v: 0.08) if k > 0 else (lambda v: -0.95), (lambda v: 0.95) if k > 0 else (lambda v: -0.08),
                nu=10, nv=6, offset=0.009, thick=0.01)  # lower chest / ribs
        A.panel(chest, "Chest", C, -0.45, 0.75, sg(1.15) if k > 0 else sg(1.95), sg(1.95) if k > 0 else sg(1.15), nu=7, nv=9, offset=0.008, thick=0.009)  # flank
        A.panel(chest, "Chest", C, 0.02, 0.9, sg(2.15) if k > 0 else sg(3.08), sg(3.08) if k > 0 else sg(2.15), nu=8, nv=8, offset=0.008, thick=0.01)  # upper back
        A.panel(chest, "Chest", C, -0.6, -0.04, sg(2.2) if k > 0 else sg(3.08), sg(3.08) if k > 0 else sg(2.2), nu=8, nv=5, offset=0.008, thick=0.009)  # lower back
    A.panel(chest, "Chest", G, -0.5, 0.82, -0.05, 0.05, nu=2, nv=10, offset=0.014, thick=0.008)  # sternum keel
    for k in (1, -1):  # trapezius / collar plates that bury the neck base
        A.panel(chest, "Chest", C, 0.9, 1.38, (lambda v: 0.12) if k > 0 else (lambda v: -2.9), (lambda v: 2.9) if k > 0 else (lambda v: -0.12),
                nu=14, nv=5, offset=0.012, thick=0.014)
    A.panel(chest, "Chest", G, -0.6, 0.85, pi - 0.05, pi + 0.05, nu=2, nv=10, offset=0.013, thick=0.012)  # spine ridge
    # winged emblem (original Owen Enterprises design): span ~0.25 m conformed to the chest
    wing = [(0.0, 0.62), (0.07, 0.48), (0.2, 0.62), (0.42, 0.66), (0.62, 0.55), (0.5, 0.48), (0.55, 0.38), (0.36, 0.43),
            (0.24, 0.30), (0.12, 0.36), (0.0, 0.10)]
    pts = [(u * 0.95, v) for u, v in wing] + [(-u * 0.95, v) for u, v in reversed(wing[1:-1])]
    A.polygon_on(chest, pts, "Chest", U, 0.032, 0.006)
    A.polygon_on(chest, [(0.0, 0.52), (0.05, 0.42), (0.0, 0.2), (-0.05, 0.42)], "Chest", E, 0.039, 0.002)
    # abdomen: 3 rows x 2 sides, plus side plates
    ab = limb((0, 0.004, 1.06), (0, 0.004, 1.235), 0.142, 0.15, 1, oval=0.78)
    for r, (a0, a1) in enumerate(((0.02, 0.31), (0.36, 0.64), (0.69, 0.98))):
        for k in (1, -1):
            A.panel(ab, "Spine", C, a0, a1, 0.06 if k > 0 else -0.95, 0.95 if k > 0 else -0.06, nu=8, nv=2, offset=0.008 + r * 0.002, thick=0.01)
        for k in (1, -1):
            A.panel(ab, "Spine", G, a0, a1, 1.05 if k > 0 else -1.75, 1.75 if k > 0 else -1.05, nu=5, nv=2, offset=0.006, thick=0.007)
    # belt band, buckle, pouches, faulds
    belt = limb((0, 0, 0.99), (0, 0, 1.05), 0.168, 0.164, 1, oval=0.74)
    A.panel(belt, "Hips", G, 0.0, 1.0, -pi, pi, nu=32, nv=2, offset=0.006, thick=0.012)
    A.shape(v1.prim_box((0.085, 0.02, 0.05), bevel=0.008), "Hips", C, Vector((0, -0.14, 1.02)))
    A.shape(v1.prim_box((0.036, 0.006, 0.014), bevel=0.002), "Hips", E, Vector((0, -0.152, 1.02)))
    for k in (1, -1):
        for ang in (0.75, 1.2, 1.75, 2.3):
            p, n = belt(k * ang, 0.5)
            A.shape(v1.prim_box((0.048, 0.034, 0.058), bevel=0.007), "Hips", U, p + n * 0.03, v1.frame(Z, Vector((n.y, -n.x, 0))))
            A.shape(v1.prim_box((0.05, 0.006, 0.018), bevel=0.002), "Hips", G, p + n * 0.048 + Vector((0, 0, 0.022)), v1.frame(Z, Vector((n.y, -n.x, 0))))
    pelvis = ellipsoid((0, 0.0, 0.985), (0.16, 0.115, 0.11))
    A.panel(pelvis, "Hips", C, -0.95, -0.15, -0.55, 0.55, nu=8, nv=5, offset=0.01, thick=0.01)  # front guard
    A.panel(pelvis, "Hips", C, -0.85, -0.12, pi - 0.7, pi + 0.7, nu=8, nv=5, offset=0.01, thick=0.01)  # rear guard

    # ---------------- arms ----------------
    for s, k in SIDES:
        d = J["arm_dir_" + s]
        sh, el, wr, hd = J["sh_" + s], J["el_" + s], J["wr_" + s], J["hand_" + s]
        outer = k * pi / 2
        # layered pauldron (three overlapping bands around the outer side)
        pc = sh + Vector((k * 0.03, 0.0, 0.012))
        for i, (a0, a1, sc) in enumerate(((0.7, 1.5, 1.0), (0.22, 0.75, 1.07), (-0.35, 0.28, 1.14))):
            pa = ellipsoid(pc, (0.128 * sc, 0.132 * sc, 0.115 * sc))
            A.panel(pa, "UpperArm_" + s, C, a0, a1, outer - 2.15, outer + 2.15, nu=16, nv=4, offset=0.0, thick=0.011, bevel=0.003)
        hub = v1.prim_cyl(0.05, 0.05, 0.05, 20, 0.004)
        A.shape(hub, "UpperArm_" + s, G, sh + Vector((k * 0.02, 0, 0)), v1.frame(Vector((k, 0, 0))))
        A.shape(v1.prim_box((0.016, 0.14, 0.05), taper_top=(1, 0.5), bevel=0.005), "UpperArm_" + s, G, pc + Vector((k * 0.09, 0.0, 0.07)),
                Q(Y, -k * 32).to_matrix())
        ua = limb(sh, el, 0.074, 0.064, k, bulge=0.006)
        A.panel(ua, "UpperArm_" + s, C, 0.3, 0.92, outer - 1.95, outer + 1.95, nu=14, nv=6, offset=0.006, thick=0.01)
        A.panel(ua, "UpperArm_" + s, G, 0.3, 0.92, outer + 2.05, outer + 4.23, nu=8, nv=6, offset=0.004, thick=0.006)
        # elbow hub + cop
        A.shape(v1.prim_sphere((0.056, 0.056, 0.056), 18, 10), "LowerArm_" + s, G, el)
        el_s = ellipsoid(el + Vector((0, 0.02, 0)), (0.07, 0.07, 0.07))
        A.panel(el_s, "LowerArm_" + s, C, -0.5, 0.6, pi - 0.9, pi + 0.9, nu=8, nv=6, offset=0.004, thick=0.009)
        # gauntlet
        fa = limb(el, wr, 0.07, 0.054, k)
        A.panel(fa, "LowerArm_" + s, C, 0.08, 0.92, outer - 2.1, outer + 1.05, nu=14, nv=7, offset=0.006, thick=0.012)
        A.panel(fa, "LowerArm_" + s, G, 0.12, 0.9, outer + 1.15, outer + 2.6, nu=6, nv=6, offset=0.004, thick=0.007)
        A.panel(fa, "LowerArm_" + s, G, 0.92, 1.0, -pi, pi, nu=20, nv=1, offset=0.008, thick=0.012)  # wrist cuff
        for t in (0.32, 0.52, 0.72):  # scalloped fins along the back-outer edge
            p, n = fa(pi * 0.75 * k, t)
            A.shape(wedge(0.06, 0.05, 0.008, 0.2), "LowerArm_" + s, G, p + n * 0.012, v1.frame(n, d))
        if s == "L":  # wrist computer
            p, n = fa(-0.2, 0.7)
            A.shape(v1.prim_box((0.05, 0.065, 0.02), bevel=0.005), "LowerArm_L", G, p + n * 0.02, v1.frame(n, d))
            A.shape(v1.prim_box((0.034, 0.04, 0.004), bevel=0.001), "LowerArm_L", E, p + n * 0.031, v1.frame(n, d))
        # hand: palm block (glove) + back-of-hand plate + knuckle guard
        pn = J["palm_n_" + s]
        A.shape(v1.prim_box((0.035, 0.085, 0.09), bevel=0.012), "Hand_" + s, U, wr.lerp(hd, 0.55), v1.frame(d, pn))
        A.shape(v1.prim_box((0.012, 0.08, 0.07), bevel=0.004), "Hand_" + s, C, wr.lerp(hd, 0.55) - pn * 0.022, v1.frame(d, pn))
        A.shape(v1.prim_box((0.016, 0.082, 0.02), bevel=0.004), "Hand_" + s, G, hd - pn * 0.018, v1.frame(d, pn))
        # fingers: glove segment + armored top plate per bone
        for fname, off, l1, l2 in FINGERS:
            base = hd + Vector((0, -off, 0))
            for seg, (L, bone) in enumerate(((l1, f"{fname}1_{s}"), (l2, f"{fname}2_{s}"))):
                c = base + d * (L / 2 + (l1 if seg else 0))
                A.shape(v1.prim_box((0.02, 0.018, L * 0.96), bevel=0.006), bone, U, c, v1.frame(d, pn))
                A.shape(v1.prim_box((0.006, 0.016, L * 0.8), bevel=0.002), bone, C, c - pn * 0.011, v1.frame(d, pn))
        tb = J["wr_" + s] + d * 0.03 + Vector((0, -0.032, 0)) + pn * 0.012
        td = (d * 0.55 + FWD * 0.85).normalized()
        A.shape(v1.prim_box((0.022, 0.02, 0.04), bevel=0.006), f"Thumb1_{s}", U, tb + td * 0.02, v1.frame(td, pn))
        A.shape(v1.prim_box((0.02, 0.018, 0.035), bevel=0.006), f"Thumb2_{s}", U, tb + td * 0.058, v1.frame(td, pn))
        A.shape(v1.prim_box((0.006, 0.016, 0.03), bevel=0.002), f"Thumb2_{s}", C, tb + td * 0.058 - pn * 0.011, v1.frame(td, pn))

    # ---------------- legs ----------------
    for s, k in SIDES:
        hip, kn, an = J["hip_" + s], J["knee_" + s], J["ankle_" + s]
        outer = k * pi / 2
        th = limb(hip, kn, 0.108, 0.082, k, bulge=0.008)
        A.panel(th, "UpperLeg_" + s, C, 0.12, 0.86, -0.8, 0.8, nu=10, nv=8, offset=0.007, thick=0.012)  # front
        A.panel(th, "UpperLeg_" + s, C, 0.08, 0.8, outer - 0.6, outer + 0.6, nu=6, nv=7, offset=0.006, thick=0.011)  # outer
        A.panel(th, "UpperLeg_" + s, G, 0.2, 0.75, k * 0.86 - 0.06, k * 0.86 + 0.06, nu=2, nv=6, offset=0.012, thick=0.01)  # seam rail
        # knee: hubs on both sides, piston housing (thigh) + rod (shin), knee cap
        for side in (1, -1):
            A.shape(v1.prim_cyl(0.042, 0.042, 0.03, 18, 0.004), "LowerLeg_" + s, G, kn + Vector((side * 0.075, 0.005, 0)), v1.frame(Vector((1, 0, 0))))
        p_top = th(k * pi * 0.7, 0.55)[0]  # back-outer of the thigh
        housing_dir = (kn - p_top).normalized()
        A.shape(v1.prim_cyl(0.016, 0.016, 0.16, 12, 0.002), "UpperLeg_" + s, G, p_top + housing_dir * 0.08, v1.frame(housing_dir))
        sh_ = limb(kn, an, 0.08, 0.062, k)
        p_rod = sh_(pi * 0.7 if k > 0 else -pi * 0.7, 0.25)[0]
        A.shape(v1.prim_cyl(0.009, 0.009, 0.2, 10, 0.0), "LowerLeg_" + s, G, (p_rod + p_top) / 2, v1.frame((p_top - p_rod).normalized()))
        kc = ellipsoid(kn + Vector((0, -0.02, 0)), (0.075, 0.07, 0.08))
        A.panel(kc, "LowerLeg_" + s, C, -0.7, 0.75, -0.95, 0.95, nu=10, nv=7, offset=0.012, thick=0.012)
        A.panel(sh_, "LowerLeg_" + s, C, 0.1, 0.88, -1.15, 1.15, nu=12, nv=8, offset=0.006, thick=0.012,
                lift=lambda u, v: 0.008 * max(0.0, 1 - abs(u) / 0.35))  # shin guard with ridge
        A.panel(sh_, "LowerLeg_" + s, C, 0.12, 0.62, pi - 1.0, pi + 1.0, nu=8, nv=5, offset=0.005, thick=0.01)  # calf
        A.panel(sh_, "LowerLeg_" + s, G, 0.86, 1.0, -pi, pi, nu=20, nv=1, offset=0.012, thick=0.014)  # ankle ring
        # boot: shell, toe cap, heel plate, sole with treads
        A.shape(v1.prim_box((0.112, 0.22, 0.105), taper_top=(0.9, 0.7), bevel=0.022, segs=3), "Foot_" + s, U, Vector((k * 0.107, -0.045, 0.06)))
        boot = ellipsoid((k * 0.108, -0.06, 0.055), (0.066, 0.135, 0.07))
        A.panel(boot, "Foot_" + s, C, -0.1, 1.0, -0.85, 0.85, nu=10, nv=6, offset=0.004, thick=0.01)
        A.panel(boot, "Foot_" + s, G, -0.2, 0.7, pi - 0.8, pi + 0.8, nu=8, nv=5, offset=0.004, thick=0.01)  # heel
        toe = ellipsoid((k * 0.11, -0.165, 0.038), (0.058, 0.06, 0.045))
        A.panel(toe, "Toes_" + s, C, -0.15, 1.1, -1.3, 1.3, nu=10, nv=6, offset=0.002, thick=0.01)
        A.shape(v1.prim_box((0.118, 0.215, 0.02), bevel=0.006), "Foot_" + s, U, Vector((k * 0.107, -0.05, 0.01)))
        A.shape(v1.prim_box((0.112, 0.08, 0.02), bevel=0.006), "Toes_" + s, U, Vector((k * 0.11, -0.17, 0.01)))
        for i in range(5):  # tread ridges
            A.shape(v1.prim_box((0.112, 0.012, 0.008), bevel=0.002), "Foot_" + s, G, Vector((k * 0.107, 0.04 - i * 0.035, 0.002)))
    return A.to_object("CRX9_Armor", mats, rig)


# ======================================================================================
# Cape v2: folds, thickness
# ======================================================================================
def build_cape(mats, rig):
    obj = v1.build_cape(mats, rig)
    me = obj.data
    for v in me.vertices:
        t = min(1.0, max(0.0, (1.48 - v.co.z) / 1.22))
        u = v.co.x / (0.2 + 0.22 * t)
        v.co.y += 0.022 * sin(u * pi * 3.5) * t ** 1.2  # hanging folds, deeper toward the hem
    me.update()
    mod = obj.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = 0.006
    mod.offset = 1
    obj.modifiers.move(len(obj.modifiers) - 1, 0)  # solidify before the armature
    dg = bpy.context.evaluated_depsgraph_get()
    # bake solidify only (armature at rest pose is identity)
    arm = obj.modifiers["Armature"]
    arm.show_viewport = False
    new = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    arm.show_viewport = True
    obj.modifiers.remove(mod)
    old = obj.data
    obj.data = new
    new.name = "CRX9_Cape"
    bpy.data.meshes.remove(old)
    v1.finish_mesh(new, 80)
    return obj


# ======================================================================================
# LODs
# ======================================================================================
def make_lods(objs):
    out = []
    for o in objs:
        for lvl, ratio in ((1, 0.42), (2, 0.14)):
            c = o.copy()
            c.data = o.data.copy()
            c.name = f"{o.name}_LOD{lvl}"
            c.data.name = c.name
            bpy.context.scene.collection.objects.link(c)
            dec = c.modifiers.new("Decimate", "DECIMATE")
            dec.ratio = ratio
            c.modifiers.move(len(c.modifiers) - 1, 0)  # decimate before the armature
            with bpy.context.temp_override(object=c, active_object=c, selected_objects=[c], selected_editable_objects=[c]):
                bpy.ops.object.modifier_apply(modifier=dec.name)
            out.append(c)
        o.name = o.name + "_LOD0"
    return out


# ======================================================================================
# Animation: v1 poser + finger grip
# ======================================================================================
class PoserV2(v1.Poser):
    def extra(self, G, P):
        for s, k in SIDES:
            hand = "Hand_" + s
            gh = G.get(hand)
            if gh is None:
                continue
            grip = P.get("grip_" + s, 0.3)
            pn = Vector((-k * 0.7071, 0, -0.7071))
            for fname, *_ in FINGERS:
                b1, b2 = f"{fname}1_{s}", f"{fname}2_{s}"
                axis = self.rest_dir(b1).cross(pn).normalized()
                G[b1] = gh @ Q(axis, 75 * grip)
                G[b2] = G[b1] @ Q(axis, 85 * grip)
            t1, t2 = f"Thumb1_{s}", f"Thumb2_{s}"
            axis = self.rest_dir(t1).cross(pn).normalized()
            G[t1] = gh @ Q(axis, 35 * grip)
            G[t2] = G[t1] @ Q(axis, 40 * grip)


GRIP = {
    "CK_Run": (0.85, 0.85), "CK_Sprint": (0.95, 0.95), "CK_GrappleAim": (0.6, 1.0), "CK_GrapplePull": (1.0, 1.0),
    "CK_LandHard": (0.4, 1.0), "CK_Glide": (0.05, 0.05), "CK_Interact": (0.3, 0.15), "CK_Drive": (0.85, 0.85),
    "CK_GadgetDraw": (0.3, 0.9), "CK_GadgetStow": (0.3, 0.9), "CK_Summon": (0.6, 0.2), "CK_Airborne": (0.55, 0.55),
    "CK_Guard": (1.0, 1.0), "CK_PunchR": (1.0, 1.0), "CK_PunchL": (1.0, 1.0), "CK_HeavyStrike": (1.0, 1.0),
    "CK_Counter": (1.0, 1.0), "CK_Dodge": (0.9, 0.9), "CK_Vault": (0.4, 0.4), "CK_LedgeHang": (1.0, 1.0),
    "CK_LedgeClimb": (0.9, 0.9), "CK_Slide": (0.3, 0.3),
}


def clip_table_v2():
    rows = []
    for name, frames, loop, ref, fn, desc in v1.clip_table():
        gl, gr = GRIP.get(name, (0.3, 0.3))

        def wrapped(f, fn=fn, gl=gl, gr=gr):
            p = fn(f)
            p["grip_L"], p["grip_R"] = gl, gr
            return p
        rows.append((name, frames, loop, ref, wrapped, desc))
    return rows


# ======================================================================================
def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = v1.FPS
    J = joints()
    rig = build_armature(J)
    T = make_textures()
    mats = make_materials(T)
    # undersuit (v1 skin body; palm now ends at the knuckles) — fingers/sockets excluded from auto weights
    no_deform = [b for b in rig.data.bones if any(x in b.name for x in ("Index", "Middle", "Ring", "Pinky", "Thumb"))]
    for b in no_deform:
        b.use_deform = False
    body = v1.build_undersuit(J, mats, rig)
    for b in no_deform:
        b.use_deform = True
    retile_uv(body.data, 6.0)
    armor = build_armor(J, mats, rig)
    cape = build_cape(mats, rig)
    v1.CLIP_TABLE = clip_table_v2
    meta = v1.bake_clips(rig, J, PoserV2)
    lods = make_lods([body, armor, cape])
    scene.frame_start, scene.frame_end = 0, 60
    if os.path.exists(OUT_GLB) and not os.path.exists(OUT_V1):
        shutil.copyfile(OUT_GLB, OUT_V1)  # keep v1 alongside
    v1.export_glb(OUT_GLB)
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)

    def tris(o):
        return sum(len(p.vertices) - 2 for p in o.data.polygons)
    lod_tris = {f"LOD{l}": sum(tris(o) for o in bpy.data.objects if o.type == "MESH" and o.name.endswith(f"_LOD{l}")) for l in (0, 1, 2)}
    info = {
        "asset": "assets/models/characters/crimson_knight_CRX9_rigged.glb",
        "version": 2,
        "source": "tools/blender/ck_build_crx9_v2.py",
        "height_m": v1.HEIGHT,
        "forward": "+Z (Three.js)",
        "skeleton_bones": len(rig.data.bones),
        "triangles": lod_tris,
        "lod_distances_m": [0, 9, 26],
        "sockets": [b.name for b in rig.data.bones if b.name.startswith("Socket_")],
        "clips": meta,
    }
    with open(v1.OUT_CLIPS, "w") as fh:
        json.dump(info, fh, indent=2)
    print(f"[CRX9v2] OK bones={len(rig.data.bones)} tris={lod_tris} clips={len(meta)}")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
