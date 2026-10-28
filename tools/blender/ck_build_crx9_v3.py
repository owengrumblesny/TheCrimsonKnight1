"""Crimson Knight: Earth-RED — CR-X9 War Suit, version 3: realistic (Arkham-style) pass. Blender 5.x.

What changes vs v2 (tools/blender/ck_build_crx9_v2.py, kept):
  * ANATOMY FIRST: the body is sculpted from ~70 muscle volumes (pecs, lats, traps, deltoids, biceps,
    triceps, forearm flexors, quads, hamstrings, calves, glutes, obliques...) unioned by a voxel remesh
    and relaxed, instead of skin-modifier tubes
  * ARMOR FROM ANATOMY: every plate is cut from that body surface (region masks), offset, given real
    thickness, its outline relaxed and its edges bevelled, so plates hug the musculature with panel gaps
  * sculpted cowl (brow ridge, cheekbones, carved eye sockets, short swept ears) and armoured jaw
  * HIGH-TO-LOW BAKE: Cycles bakes a procedural paint/wear shader (edge wear via the Bevel node, cavity
    grime via AO, scuffs, micro bump) into 2K base colour / metallic-roughness / normal maps
  * heavy cape with folds, thickness and a fabric sheen
  * the same skeleton (v2: fingers + sockets), the same 22 CK_* clips, LOD0/1/2 (LOD1 is the laptop LOD)

Run from the project root:
  blender -b --factory-startup --python tools/blender/ck_build_crx9_v3.py [-- --preview OUT.png] [-- --tex 1024]
"""
import json
import os
import shutil
import sys
import time
from math import cos, pi, radians, sin

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ck_build_crx9 as v1  # noqa: E402
import ck_build_crx9_v2 as v2  # noqa: E402

ROOT = v1.ROOT
OUT_GLB = v1.OUT_GLB
OUT_V2 = OUT_GLB.replace("_rigged.glb", "_rigged_v2.glb")
OUT_BLEND = os.path.join(ROOT, "assets", "source", "blender", "crimson_knight_CRX9_v3.blend")
TEX_OUT = os.path.join(ROOT, "assets", "source", "textures", "crx9_v3")
X, Y, Z, FWD, SIDES = v1.X, v1.Y, v1.Z, v1.FWD, v1.SIDES

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return ARGS[ARGS.index(name) + 1] if name in ARGS else default


TEX = int(arg("--tex", 2048))
# paint ids (face attribute "paint", read by the bake shader)
CRIMSON, GUNMETAL, RUBBER, TRIM = 0, 1, 2, 3


def log(*a):
    print("[CRX9v3]", *a, flush=True)


# ======================================================================================
# Anatomy: ellipsoid muscle volumes -> voxel remesh -> relax
# ======================================================================================
def limb_frame(a, b, k):
    ax = (b - a).normalized()
    f = (FWD - ax * FWD.dot(ax)).normalized()
    sv = Vector((k, 0, 0))
    s = (sv - ax * sv.dot(ax) - f * sv.dot(f)).normalized()
    return ax, f, s, (b - a).length


class Volumes:
    def __init__(self):
        self.items = []  # (centre, radii(x,y,z), rotation matrix 3x3)

    def T(self, c, r, rot=(0, 0, 0)):
        self.items.append((Vector(c), r, Euler([radians(x) for x in rot]).to_matrix()))

    def M(self, a, b, k, t, of, os_, rl, rf, rs, tilt=0.0):
        """Muscle on limb a->b: at t along it, offset `of` forward / `os_` outward; radii along/fwd/side."""
        ax, f, s, L = limb_frame(a, b, k)
        if tilt:
            ax = (ax + f * tilt).normalized()
            f = (f - ax * f.dot(ax)).normalized()
        c = a + ax * (t * L) + f * of + s * os_
        self.items.append((c, (rf, rs, rl), Matrix((f, s, ax)).transposed()))

    def mesh(self, name, seg=(24, 14)):
        bm = bmesh.new()
        for c, r, rot in self.items:
            tmp = bmesh.new()
            bmesh.ops.create_uvsphere(tmp, u_segments=seg[0], v_segments=seg[1], radius=1.0)
            for v in tmp.verts:
                v.co = c + rot @ Vector((v.co.x * r[0], v.co.y * r[1], v.co.z * r[2]))
            me = bpy.data.meshes.new("tmp")
            tmp.to_mesh(me)
            tmp.free()
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def remesh(obj, voxel, smooth_iters=0, smooth_factor=0.5, close=0.0):
    """Voxel-union the volumes; `close` > 0 runs a morphological closing (offset out, re-union, offset back)
    which fillets every crease between volumes like a sculptor's smooth brush; then a light Laplacian relax."""
    def vox():
        m = obj.modifiers.new("Remesh", "REMESH")
        m.mode, m.voxel_size, m.use_smooth_shade = "VOXEL", voxel, True
        apply_all(obj)

    def offset(r):
        m = obj.modifiers.new("Offset", "DISPLACE")
        m.mid_level, m.strength, m.direction = 0.0, r, "NORMAL"
        apply_all(obj)

    vox()
    if close:
        offset(close)
        vox()
        offset(-close)
        vox()
    if smooth_iters:
        s = obj.modifiers.new("Smooth", "LAPLACIANSMOOTH")
        s.iterations, s.lambda_factor, s.lambda_border = smooth_iters, smooth_factor, 0.0
        s.use_volume_preserve = True
        s.use_normalized = True
    apply_all(obj)
    return obj


def apply_all(obj):
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj], selected_editable_objects=[obj]):
        for m in list(obj.modifiers):
            if m.type != "ARMATURE":
                bpy.ops.object.modifier_apply(modifier=m.name)


def anatomy(J):
    V = Volumes()
    T, M = V.T, V.M
    # ---- torso ----
    T((0, 0.012, 1.315), (0.162, 0.112, 0.19))            # ribcage
    T((0, 0.0, 1.13), (0.122, 0.09, 0.12))                # waist core
    T((0, -0.048, 1.15), (0.098, 0.058, 0.135))           # rectus abdominis
    for row, z in enumerate((1.225, 1.16, 1.095)):        # ab blocks (6-pack bumps)
        for k in (1, -1):
            T((k * 0.038, -0.083 + row * 0.004, z), (0.036, 0.024, 0.03))
    T((0, 0.0, 0.98), (0.136, 0.1, 0.1))                  # pelvis
    for s, k in SIDES:
        T((k * 0.078, -0.064, 1.372), (0.106, 0.046, 0.07), (6, -k * 3, -k * 10))   # pectoral (broad, flat)
        T((k * 0.125, -0.06, 1.405), (0.06, 0.045, 0.045), (0, 0, -k * 30))       # pec -> deltoid insertion
        T((k * 0.124, 0.018, 1.3), (0.046, 0.09, 0.15), (0, -k * 16, 0))          # latissimus (V taper)
        T((k * 0.078, 0.035, 1.468), (0.088, 0.058, 0.052), (0, k * 24, 0))       # trapezius slope
        T((k * 0.032, 0.065, 1.4), (0.05, 0.04, 0.09))                            # upper trap / rhomboid
        T((k * 0.096, -0.012, 1.135), (0.046, 0.074, 0.095), (0, k * 10, 0))      # oblique
        T((k * 0.118, -0.03, 1.215), (0.04, 0.05, 0.06))                          # serratus
        T((k * 0.032, 0.078, 1.19), (0.028, 0.026, 0.17))                         # spinal erector
        T((k * 0.064, 0.05, 0.94), (0.075, 0.062, 0.08), (0, -k * 8, 0))         # glute
    # ---- neck + head (covered by the cowl, needed for skin weights and the cowl's base) ----
    T((0, 0.008, 1.548), (0.07, 0.068, 0.085))
    for k in (1, -1):
        T((k * 0.03, -0.018, 1.545), (0.022, 0.022, 0.075), (-22, k * 18, 0))     # sternocleidomastoid
    T((0, 0.0, 1.725), (0.083, 0.098, 0.102))             # cranium
    T((0, -0.04, 1.65), (0.064, 0.066, 0.052))            # jaw
    # ---- arms ----
    for s, k in SIDES:
        sh, el, wr = J["sh_" + s], J["el_" + s], J["wr_" + s]
        d = J["arm_dir_" + s]
        out = Vector((k, 0, 0))
        T(sh + out * 0.012 + Z * 0.012, (0.078, 0.082, 0.07))                     # shoulder cap mass
        M(sh, el, k, 0.08, 0.028, 0.026, 0.105, 0.05, 0.058)                      # anterior deltoid
        M(sh, el, k, 0.1, -0.004, 0.04, 0.12, 0.06, 0.05)                         # lateral deltoid
        M(sh, el, k, 0.1, -0.035, 0.022, 0.105, 0.052, 0.052)                     # posterior deltoid
        M(sh, el, k, 0.5, 0.0, 0.0, 0.17, 0.047, 0.046)                           # humerus core
        M(sh, el, k, 0.56, 0.026, -0.004, 0.11, 0.046, 0.043)                     # biceps
        M(sh, el, k, 0.45, -0.03, 0.006, 0.13, 0.046, 0.046)                      # triceps long head
        M(sh, el, k, 0.42, -0.018, 0.03, 0.1, 0.036, 0.034)                       # triceps lateral head
        M(sh, el, k, 0.98, 0.0, 0.0, 0.04, 0.042, 0.044)                          # elbow
        M(el, wr, k, 0.26, 0.004, 0.02, 0.12, 0.05, 0.052)                        # brachioradialis / extensors
        M(el, wr, k, 0.3, 0.012, -0.018, 0.11, 0.042, 0.04)                       # flexors
        M(el, wr, k, 0.62, 0.0, 0.0, 0.17, 0.034, 0.038)                          # forearm taper
        M(el, wr, k, 1.0, 0.0, 0.0, 0.022, 0.026, 0.034)                          # wrist
        pn = J["palm_n_" + s]
        hc = wr + d * 0.05
        V.items.append((hc, (0.024, 0.046, 0.055), Matrix((pn, d.cross(pn).normalized(), d)).transposed()))  # palm
    # ---- legs ----
    for s, k in SIDES:
        hip, kn, an = J["hip_" + s], J["knee_" + s], J["ankle_" + s]
        T(hip + Vector((-k * 0.004, 0.0, -0.05)), (0.084, 0.088, 0.1))            # upper thigh mass
        M(hip, kn, k, 0.45, 0.032, 0.006, 0.22, 0.066, 0.064)                     # rectus femoris
        M(hip, kn, k, 0.5, 0.012, 0.042, 0.22, 0.06, 0.05)                        # vastus lateralis
        M(hip, kn, k, 0.76, 0.024, -0.03, 0.1, 0.046, 0.044)                      # vastus medialis (teardrop)
        M(hip, kn, k, 0.42, -0.03, 0.0, 0.22, 0.064, 0.07)                        # hamstrings
        M(hip, kn, k, 0.3, -0.006, -0.045, 0.16, 0.05, 0.048)                     # adductors
        M(hip, kn, k, 0.98, 0.006, 0.0, 0.05, 0.052, 0.054)                       # knee
        M(kn, an, k, 0.3, -0.03, 0.008, 0.16, 0.056, 0.05)                        # gastrocnemius
        M(kn, an, k, 0.24, -0.022, -0.022, 0.12, 0.046, 0.042)                    # gastrocnemius medial
        M(kn, an, k, 0.4, 0.02, 0.012, 0.2, 0.03, 0.03)                           # tibialis
        M(kn, an, k, 0.62, 0.0, 0.0, 0.2, 0.042, 0.042)                           # shin taper
        M(kn, an, k, 1.0, 0.0, 0.0, 0.035, 0.034, 0.038)                          # ankle
        T((an.x, an.y + 0.012, 0.048), (0.042, 0.052, 0.048))                         # heel
        T((an.x + k * 0.003, (an.y + J["ball_" + s].y) / 2, 0.05), (0.046, 0.08, 0.042))  # midfoot
        T((J["ball_" + s].x, J["ball_" + s].y - 0.03, 0.032), (0.045, 0.055, 0.03))     # toes
    return V


def build_body(J, voxel=0.006):
    t0 = time.time()
    obj = anatomy(J).mesh("CRX9_BodyHigh")
    remesh(obj, voxel, smooth_iters=4, smooth_factor=0.5, close=0.016)
    log(f"body high: {len(obj.data.polygons)} faces in {time.time() - t0:.1f}s")
    return obj


# ======================================================================================
# Preview render (proportion / look review without the full bake)
# ======================================================================================
def preview(objs, path, views=("front", "side", "back", "q"), res=900, focus=None, ortho=1.15):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = int(res * 0.62), res
    sc.view_settings.view_transform = "AgX"
    w = bpy.data.worlds.new("pw")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.055, 0.065, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.35
    sc.world = w
    for name, energy, loc in (("key", 900, (2.2, -3.0, 3.2)), ("rim", 1200, (-2.6, 2.6, 2.8)), ("fill", 220, (-3, -2, 1.2))):
        L = bpy.data.lights.new(name, "AREA")
        L.energy, L.size = energy, 2.0
        o = bpy.data.objects.new(name, L)
        o.location = loc
        o.rotation_euler = (Vector((0, 0, 1.1)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(o)
    cam_d = bpy.data.cameras.new("pc")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = ortho * 2
    cam = bpy.data.objects.new("pc", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    centre = Vector(focus) if focus else Vector((0, 0, 1.0))
    for o in sc.objects:
        if o.type == "MESH":
            o.hide_render = o not in objs
    files = []
    dirs = {"front": (0, -1, 0), "side": (1, 0, 0), "back": (0, 1, 0), "q": (0.7, -0.7, 0.12)}
    for v in views:
        dv = Vector(dirs[v]).normalized()
        cam.location = centre + dv * 6
        cam.rotation_euler = (-dv).to_track_quat("-Z", "Y").to_euler()
        f = path.replace(".png", f"_{v}.png")
        sc.render.filepath = f
        bpy.ops.render.render(write_still=True)
        files.append(f)
    log("preview:", files)
    return files


# ======================================================================================
# Plate source: decimated body + per-face nearest bone / limb coordinates
# ======================================================================================
def deform_bones(rig):
    skip = ("Cape_", "Socket_", "Root", "Index", "Middle", "Ring", "Pinky", "Thumb")
    return [b for b in rig.data.bones if not b.name.startswith(skip) and not any(x in b.name for x in skip[3:])]


def decimated_copy(obj, tris, name):
    c = obj.copy()
    c.data = obj.data.copy()
    c.name = c.data.name = name
    bpy.context.scene.collection.objects.link(c)
    n = sum(len(p.vertices) - 2 for p in c.data.polygons)
    if n > tris:
        d = c.modifiers.new("Dec", "DECIMATE")
        d.ratio = tris / n
        apply_all(c)
    return c


class Src:
    """Decimated anatomy used to cut armour plates (region masks over face centres)."""

    def __init__(self, body, rig, tris=34000):
        self.obj = decimated_copy(body, tris, "CRX9_PlateSource")
        self.bm = bmesh.new()
        self.bm.from_mesh(self.obj.data)
        self.bm.normal_update()
        self.bm.faces.ensure_lookup_table()
        self.bm.verts.ensure_lookup_table()
        self.faces = list(self.bm.faces)
        self.C = np.array([tuple(f.calc_center_median()) for f in self.faces])
        self.N = np.array([tuple(f.normal) for f in self.faces])
        bones = deform_bones(rig)
        H = np.array([tuple(b.head_local) for b in bones])
        Tl = np.array([tuple(b.tail_local) for b in bones])
        ab = Tl - H
        best = np.full(len(self.C), 1e9)
        idx = np.zeros(len(self.C), int)
        for i in range(len(bones)):
            t = np.clip(((self.C - H[i]) @ ab[i]) / (ab[i] @ ab[i]), 0, 1)
            d = np.linalg.norm(self.C - (H[i] + t[:, None] * ab[i]), axis=1)
            closer = d < best
            best[closer], idx[closer] = d[closer], i
        self.B = np.array([bones[i].name for i in idx])
        self.bvh = BVHTree.FromBMesh(self.bm)
        bpy.data.objects.remove(self.obj)

    def on(self, *names):
        return np.isin(self.B, names)

    def limbc(self, a, b, k):
        ax, f, s, L = limb_frame(a, b, k)
        ax, f, s = (np.array(tuple(v)) for v in (ax, f, s))
        d = self.C - np.array(tuple(a))
        along = d @ ax
        r = d - np.outer(along, ax)
        return along / L, np.arctan2(r @ s, r @ f)

    def dist(self, p):
        return np.linalg.norm(self.C - np.array(tuple(p)), axis=1)


def angin(a, lo, hi):
    return np.mod(a - lo, 2 * pi) <= (hi - lo)


def components(faces):
    faces = set(faces)
    out = []
    while faces:
        seed = faces.pop()
        comp, stack = [seed], [seed]
        while stack:
            f = stack.pop()
            for e in f.edges:
                for g in e.link_faces:
                    if g in faces:
                        faces.discard(g)
                        comp.append(g)
                        stack.append(g)
        out.append(comp)
    return out


def shell(bm, normals, thick, bevel, relax=8):
    """bm: open surface patch; normals: {vert: outward normal}. Relax the outline, then give it thickness
    (outer = +normal) with side walls, and bevel the outer rim. Returns bm (closed, consistent normals)."""
    for _ in range(relax):
        nb = {}
        for e in bm.edges:
            if e.is_boundary:
                a, b = e.verts
                nb.setdefault(a, []).append(b)
                nb.setdefault(b, []).append(a)
        moved = {v: v.co * 0.5 + (ns[0].co + ns[1].co) * 0.25 for v, ns in nb.items() if len(ns) == 2}
        for v, co in moved.items():
            v.co = co
    inner_faces = list(bm.faces)
    bnd = [e for e in bm.edges if e.is_boundary]
    outer = {v: bm.verts.new(v.co + normals[v] * thick) for v in list(bm.verts)}
    for f in inner_faces:
        bm.faces.new([outer[v] for v in f.verts])
    rim = []
    for e in bnd:
        a, b = e.verts
        try:
            bm.faces.new((a, b, outer[b], outer[a]))
        except ValueError:
            continue
        rim.append((outer[a], outer[b]))
    bmesh.ops.reverse_faces(bm, faces=inner_faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    rim_edges = [bm.edges.get(p) for p in rim]
    rim_edges = [e for e in rim_edges if e is not None]
    if bevel > 0 and rim_edges:
        bmesh.ops.bevel(bm, geom=rim_edges, offset=bevel, offset_type="OFFSET", segments=2, profile=0.6,
                        affect="EDGES", clamp_overlap=True)
    return bm


class Assembly:
    """Parts -> one skinned mesh. bone=None means 'transfer weights from the skinned body'."""

    def __init__(self):
        self.parts = []

    def add(self, bm, paint, bone, mat=0):
        self.parts.append((bm, paint, bone, mat))

    def to_object(self, name, mats, rig, body=None):
        verts, faces, fpaint, fmat, vgrp = [], [], [], [], []
        for bm, paint, bone, mat in self.parts:
            bm.verts.index_update()
            base = len(verts)
            verts += [tuple(v.co) for v in bm.verts]
            vgrp += [bone or "__transfer"] * len(bm.verts)
            for f in bm.faces:
                faces.append([base + v.index for v in f.verts])
                fpaint.append(paint)
                fmat.append(mat)
            bm.free()
        me = bpy.data.meshes.new(name)
        me.from_pydata(verts, [], faces)
        me.update()
        for m in mats:
            me.materials.append(m)
        me.polygons.foreach_set("material_index", fmat)
        at = me.attributes.new("paint", "INT", "FACE")
        at.data.foreach_set("value", fpaint)
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        groups = {}
        for i, b in enumerate(vgrp):
            groups.setdefault(b, []).append(i)
        for b, idx in groups.items():
            obj.vertex_groups.new(name=b).add(idx, 1.0, "REPLACE")
        if "__transfer" in groups and body is not None:
            transfer_weights(obj, body, "__transfer")
        v1.attach(obj, rig)
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
        if hasattr(me, "set_sharp_from_angle"):
            me.set_sharp_from_angle(angle=radians(48))
        return obj


def transfer_weights(obj, body, mask_group):
    for vg in body.vertex_groups:
        if vg.name not in obj.vertex_groups:
            obj.vertex_groups.new(name=vg.name)
    dt = obj.modifiers.new("DT", "DATA_TRANSFER")
    dt.object = body
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    dt.vertex_group = mask_group
    apply_all(obj)
    obj.vertex_groups.remove(obj.vertex_groups[mask_group])


# ======================================================================================
# Armour design (all plates cut from the anatomy)
# ======================================================================================
def plate(A, S, mask, off, thick, paint, bone="auto", bevel=0.0024, lift=None, relax=8, min_faces=10, mat=0):
    idx = np.nonzero(mask)[0]
    if len(idx) == 0:
        log("WARN empty plate mask", paint, bone)
        return
    sel = [S.faces[i] for i in idx]
    if bone == "auto":
        names, counts = np.unique(S.B[idx], return_counts=True)
        bone = str(names[np.argmax(counts)])
    for comp in components(sel):
        if len(comp) < min_faces:
            continue
        bm = bmesh.new()
        vmap, normals = {}, {}
        for f in comp:
            for v in f.verts:
                if v.index not in vmap:
                    o = off + (lift(v.co) if lift else 0.0)
                    nv = bm.verts.new(v.co + v.normal * o)
                    vmap[v.index] = nv
                    normals[nv] = v.normal.copy()
            try:
                bm.faces.new([vmap[v.index] for v in f.verts])
            except ValueError:
                pass
        A.add(shell(bm, normals, thick, bevel, relax), paint, bone, mat)


def shape(A, bm, paint, bone, at, rot=None, mat=0):
    m = Matrix.Translation(at) @ (rot.to_4x4() if rot is not None else Matrix.Identity(4))
    bm.transform(m)
    A.add(bm, paint, bone, mat)


def surf(S, origin, direction):
    """First hit on the anatomy from `origin` along `direction` -> (point, normal) or (None, None)."""
    hit, n, _i, _d = S.bvh.ray_cast(Vector(origin), Vector(direction).normalized())
    return hit, n


def decal(A, poly, target_bm, paint, bone, off, thick, step=0.004, mat=0, bevel=0.0012):
    """2D outline in the XZ plane projected (+Y) onto target_bm's front surface -> raised inlay."""
    bvh = BVHTree.FromBMesh(target_bm)
    xs, zs = [p[0] for p in poly], [p[1] for p in poly]

    def inside(x, z):
        c = False
        j = len(poly) - 1
        for i in range(len(poly)):
            xi, zi = poly[i]
            xj, zj = poly[j]
            if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi:
                c = not c
            j = i
        return c

    bm = bmesh.new()
    grid = {}
    nx = int((max(xs) - min(xs)) / step) + 2
    nz = int((max(zs) - min(zs)) / step) + 2
    for i in range(nx):
        for j in range(nz):
            x, z = min(xs) + i * step, min(zs) + j * step
            if inside(x + step / 2, z + step / 2):
                for a, b in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)):
                    if (a, b) not in grid:
                        grid[(a, b)] = bm.verts.new((min(xs) + a * step, -0.5, min(zs) + b * step))
                bm.faces.new([grid[(i, j)], grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)]])
    # relax the stair-stepped outline in 2D first, then project
    for _ in range(10):
        nb = {}
        for e in bm.edges:
            if e.is_boundary:
                a, b = e.verts
                nb.setdefault(a, []).append(b)
                nb.setdefault(b, []).append(a)
        for v, ns in nb.items():
            if len(ns) == 2:
                v.co = v.co * 0.5 + (ns[0].co + ns[1].co) * 0.25
    normals = {}
    for v in list(bm.verts):
        hit, n, _i, _d = bvh.ray_cast(Vector((v.co.x, -0.5, v.co.z)), Vector((0, 1, 0)))
        if hit is None:
            hit, n = Vector((v.co.x, -0.1, v.co.z)), Vector((0, -1, 0))
        v.co = hit + n * off
        normals[v] = n.copy()
    A.add(shell(bm, normals, thick, bevel, relax=0), paint, bone, mat)


def box(dims, bevel=0.004, segs=2):
    return v1.prim_box(dims, bevel=bevel, segs=segs)


def capsule(r, length, seg=12):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=8, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * r, v.co.y * r * 0.9, v.co.z * length / 2))
    return bm


def wedge(length, width, thick, taper=0.12):
    bm = v2.wedge(length, width, thick, taper)
    v1.bevel_sharp(bm, min(thick * 0.3, 0.003), 2, angle=30)
    return bm


def build_armor(J, S, body_bm_for_cowl, rig, mats, body):
    A = Assembly()
    C, N = S.C, S.N
    torso = S.on("Chest", "Spine", "Hips")
    upper = torso | S.on("Shoulder_L", "Shoulder_R", "Neck")  # clavicle bones run across the upper chest
    ax = np.abs(C[:, 0])
    zin = lambda a, b: (C[:, 2] >= a) & (C[:, 2] <= b)  # noqa: E731

    # ---------------- torso ----------------
    chest_mask = upper & zin(1.275, 1.47) & (C[:, 1] < -0.012) & (ax < 0.19)
    plate(A, S, chest_mask, 0.011, 0.015, CRIMSON, "Chest", bevel=0.003)
    chest_bm = bmesh.new()  # emblem projection target: chest plate outer surface
    idx = np.nonzero(chest_mask)[0]
    for i in idx:
        f = S.faces[i]
        chest_bm.faces.new([chest_bm.verts.new(v.co + v.normal * 0.026) for v in f.verts])
    plate(A, S, upper & zin(1.474, 1.53) & (np.hypot(C[:, 0], C[:, 1] - 0.008) > 0.082) & (ax < 0.2),
          0.008, 0.011, GUNMETAL, "Chest")                                                          # collar
    for k in (1, -1):
        side = (C[:, 0] * k > 0.012)
        plate(A, S, upper & side & (C[:, 1] > 0.018) & zin(1.27, 1.468) & (ax < 0.17), 0.009, 0.013, CRIMSON, "Chest")  # upper back
        plate(A, S, torso & side & (C[:, 1] > 0.03) & zin(1.08, 1.255) & (ax < 0.115), 0.007, 0.009, GUNMETAL, "Spine")  # lower back
        plate(A, S, torso & (C[:, 0] * k > 0.086) & zin(1.07, 1.262) & (np.abs(C[:, 1]) < 0.05), 0.007, 0.009, GUNMETAL, "Spine")  # obliques
        for r, (a, b) in enumerate(((1.068, 1.127), (1.134, 1.19), (1.197, 1.258))):
            plate(A, S, torso & (C[:, 1] < -0.03) & (C[:, 0] * k > 0.009) & (ax < 0.098) & zin(a, b),
                  0.009 + r * 0.001, 0.011, CRIMSON, "Spine")                                         # abdomen rows
    plate(A, S, torso & (C[:, 1] > 0.035) & (ax < 0.018) & zin(1.1, 1.46), 0.016, 0.01, GUNMETAL, "Chest", relax=3)  # spine ridge
    belt_mask = torso & zin(0.986, 1.05)
    plate(A, S, belt_mask, 0.008, 0.014, GUNMETAL, "Hips", relax=12)
    # belt hardware: pouches round the back/sides, buckle with a status light
    for k in (1, -1):
        for ang in (0.85, 1.3, 1.8, 2.35):
            o = Vector((sin(ang) * k, -cos(ang), 0))
            hit, n = surf(S, Vector((0, 0, 1.018)) + o * 0.5, -o)
            if hit is None:
                continue
            n = Vector((n.x, n.y, 0)).normalized()
            rot = v1.frame(Z, Vector((n.y, -n.x, 0)))
            shape(A, box((0.05, 0.036, 0.062), 0.008, 3), RUBBER, "Hips", hit + n * 0.042, rot)
            shape(A, box((0.052, 0.008, 0.02), 0.002), GUNMETAL, "Hips", hit + n * 0.062 + Z * 0.022, rot)
    hit, n = surf(S, (0, -0.5, 1.018), (0, 1, 0))
    if hit is not None:
        shape(A, box((0.09, 0.022, 0.052), 0.008, 3), TRIM, "Hips", hit + n * 0.03)
        shape(A, box((0.04, 0.006, 0.012), 0.002), RUBBER, "Hips", hit + n * 0.044, mat=1)

    # ---------------- arms ----------------
    for s, k in SIDES:
        sh, el, wr, hd = J["sh_" + s], J["el_" + s], J["wr_" + s], J["hand_" + s]
        d, pn = J["arm_dir_" + s], J["palm_n_" + s]
        UA, LA, H = "UpperArm_" + s, "LowerArm_" + s, "Hand_" + s
        cap_c = sh + Vector((k * 0.022, 0, 0.018))
        cap_dir = np.array(tuple(Vector((k * 0.75, 0, 0.66)).normalized()))
        rel = C - np.array(tuple(cap_c))
        cosang = (rel @ cap_dir) / np.maximum(np.linalg.norm(rel, axis=1), 1e-6)
        dist = np.linalg.norm(rel, axis=1)
        notorso = C[:, 0] * k > 0.15
        plate(A, S, notorso & (dist < 0.13) & (cosang > -0.15), 0.006, 0.009, GUNMETAL, UA, relax=10)   # under-pauldron
        plate(A, S, notorso & (dist < 0.118) & (cosang > 0.12), 0.019, 0.013, CRIMSON, UA, bevel=0.0035, relax=10)  # pauldron
        plate(A, S, notorso & (dist < 0.09) & (cosang > 0.45), 0.034, 0.01, CRIMSON, UA, bevel=0.003, relax=10)     # pauldron crown
        t, ang = S.limbc(sh, el, k)
        plate(A, S, S.on(UA) & (t > 0.3) & (t < 0.86) & angin(ang, -0.35, 2.7), 0.009, 0.011, CRIMSON, UA)      # bicep/tricep shell
        plate(A, S, S.on(UA, LA) & (S.dist(el) < 0.062) & angin(ang, 1.9, 3.9), 0.012, 0.012, GUNMETAL, LA)     # elbow cop
        t, ang = S.limbc(el, wr, k)
        plate(A, S, S.on(LA) & (t > 0.1) & (t < 0.92) & angin(ang, -0.7, 3.0), 0.01, 0.013, CRIMSON, LA, bevel=0.003)  # gauntlet
        plate(A, S, S.on(LA) & (t > 0.12) & (t < 0.9) & angin(ang, 3.15, 5.5), 0.006, 0.008, GUNMETAL, LA)            # inner bracer
        plate(A, S, S.on(LA, H) & (t > 0.93) & (t < 1.04), 0.012, 0.011, GUNMETAL, LA, relax=4)                        # wrist cuff
        plate(A, S, S.on(H) & ((N @ -np.array(tuple(pn))) > 0.35), 0.007, 0.008, CRIMSON, H, relax=4)                # back of hand
        # gauntlet blades: three swept fins on the outer-back edge
        ax_, f_, s_, L = limb_frame(el, wr, k)
        for i, tt in enumerate((0.34, 0.52, 0.7)):
            o = (s_ * 0.6 - f_ * 0.8).normalized()
            hit, n = surf(S, el + ax_ * (tt * L) + o * 0.3, -o)
            if hit is None:
                continue
            rot = v1.frame(n, ax_) @ Matrix.Rotation(radians(-28), 3, "Y")
            shape(A, wedge(0.07 - i * 0.008, 0.055, 0.007), GUNMETAL, LA, hit + n * 0.018, rot)
        # glove fingers (rubber capsules) with armoured knuckle plates, one rigid piece per finger bone
        for fname, off, l1, l2 in v2.FINGERS:
            base = hd + Vector((0, -off, 0))
            for seg, (Lf, bone) in enumerate(((l1, f"{fname}1_{s}"), (l2, f"{fname}2_{s}"))):
                c = base + d * (Lf / 2 + (l1 if seg else 0))
                shape(A, capsule(0.0105, Lf * 1.08), RUBBER, bone, c, v1.frame(d, pn))
                shape(A, box((0.006, 0.016, Lf * 0.72), 0.0025), CRIMSON, bone, c - pn * 0.0105, v1.frame(d, pn))
        tb = wr + d * 0.03 + Vector((0, -0.032, 0)) + pn * 0.012
        td = (d * 0.55 + FWD * 0.85).normalized()
        shape(A, capsule(0.012, 0.045), RUBBER, f"Thumb1_{s}", tb + td * 0.02, v1.frame(td, pn))
        shape(A, capsule(0.011, 0.04), RUBBER, f"Thumb2_{s}", tb + td * 0.058, v1.frame(td, pn))
        shape(A, box((0.018, 0.08, 0.012), 0.004), GUNMETAL, H, hd - pn * 0.016 + d * 0.004, v1.frame(d, pn))  # knuckle bar

    # ---------------- legs ----------------
    for s, k in SIDES:
        hip, kn, an = J["hip_" + s], J["knee_" + s], J["ankle_" + s]
        UL, LL, F, T_ = "UpperLeg_" + s, "LowerLeg_" + s, "Foot_" + s, "Toes_" + s
        t, ang = S.limbc(hip, kn, k)
        plate(A, S, S.on(UL) & (t > 0.13) & (t < 0.8) & angin(ang, -1.15, 1.1), 0.01, 0.013, CRIMSON, UL)        # thigh
        plate(A, S, S.on(UL) & (t > 0.06) & (t < 0.68) & angin(ang, 1.25, 2.15), 0.008, 0.009, GUNMETAL, UL)     # thigh outer
        plate(A, S, S.on(UL) & (t > 0.2) & (t < 0.72) & angin(ang, 2.6, 3.7), 0.006, 0.008, GUNMETAL, UL)        # hamstring guard
        plate(A, S, S.on(UL, LL) & (S.dist(kn + FWD * 0.012) < 0.072) & ((N @ np.array(tuple(FWD))) > 0.1),
              0.02, 0.014, CRIMSON, LL, bevel=0.0035)                                                           # knee
        for side in (1, -1):
            shape(A, v1.prim_cyl(0.034, 0.03, 0.026, 20, 0.004), GUNMETAL, LL, kn + Vector((side * 0.066, 0.006, 0)),
                  v1.frame(Vector((1, 0, 0))))
        t, ang = S.limbc(kn, an, k)
        plate(A, S, S.on(LL) & (t > 0.14) & (t < 0.84) & angin(ang, -1.25, 1.25), 0.01, 0.013, CRIMSON, LL, bevel=0.003,
              lift=lambda p, kn=kn, an=an, k=k: 0.005 * max(0.0, 1 - abs(p.x - kn.x - (an.x - kn.x) * 0.5) / 0.02))  # shin with ridge
        plate(A, S, S.on(LL) & (t > 0.1) & (t < 0.62) & angin(ang, 2.3, 4.0), 0.007, 0.009, GUNMETAL, LL)       # calf
        boot = S.on(F, T_) | (S.on(LL) & (t > 0.8))
        plate(A, S, boot, 0.008, 0.011, GUNMETAL, None, relax=6)                                               # boot shell
        plate(A, S, S.on(T_, F) & (C[:, 1] < J["ball_" + s].y + 0.01) & (C[:, 2] > 0.014) & ((N @ np.array(tuple(FWD))) > -0.1),
              0.016, 0.01, GUNMETAL, T_, relax=6)                                                               # toe cap
        plate(A, S, S.on(LL, F) & (t > 0.86) & (C[:, 1] > an.y + 0.01), 0.018, 0.01, GUNMETAL, F, relax=4)    # heel guard
        shape(A, box((0.104, 0.15, 0.022), 0.005), RUBBER, F, Vector((an.x, an.y - 0.045, 0.011)))           # sole
        shape(A, box((0.1, 0.085, 0.02), 0.005), RUBBER, T_, Vector((J["ball_" + s].x, J["ball_" + s].y - 0.05, 0.01)))
        for i in range(6):
            shape(A, box((0.1, 0.01, 0.006), 0.0015), GUNMETAL, F if i < 4 else T_,
                  Vector((an.x, an.y + 0.02 - i * 0.03, 0.0)))

    # ---------------- cowl ----------------
    cowl = build_cowl()
    A.add(cowl, CRIMSON, None)  # per-face paint fixed below (jaw plate)
    # ---------------- chest emblem (original winged design) + core light ----------------
    wing = [(0.0, 0.62), (0.07, 0.48), (0.2, 0.62), (0.42, 0.66), (0.62, 0.55), (0.5, 0.48), (0.55, 0.38), (0.36, 0.43),
            (0.24, 0.30), (0.12, 0.36), (0.0, 0.10)]
    pts = [(u * 0.95, v) for u, v in wing] + [(-u * 0.95, v) for u, v in reversed(wing[1:-1])]
    poly = [(sin(u) * 0.205, 1.335 + sin(v) * 0.2) for u, v in pts]
    decal(A, poly, chest_bm, RUBBER, "Chest", 0.0, 0.006)
    core = [(0.0, 1.43), (0.012, 1.405), (0.0, 1.36), (-0.012, 1.405)]
    decal(A, core, chest_bm, RUBBER, "Chest", 0.0065, 0.002, step=0.002, mat=1)
    chest_bm.free()
    obj = A.to_object("CRX9_Armor", [mats["armor"], mats["emissive"]], rig, body)
    # jaw / faceplate in gunmetal, lenses emissive (faces of the cowl part recognised by position)
    me = obj.data
    paint = [0] * len(me.polygons)
    me.attributes["paint"].data.foreach_get("value", paint)
    mi = [0] * len(me.polygons)
    me.polygons.foreach_get("material_index", mi)
    for p in me.polygons:
        c = p.center
        if c.z > 1.585 and c.z < 1.675 and c.y < -0.035 and abs(c.x) < 0.085 and paint[p.index] == CRIMSON:
            paint[p.index] = GUNMETAL
    me.attributes["paint"].data.foreach_set("value", paint)
    return obj


def build_cowl():
    """Sculpted cowl: skull, brow ridge, cheekbones, armoured jaw, hood flaring onto the traps, swept ears;
    eye sockets carved by boolean with lenses set inside."""
    V = Volumes()
    T = V.T
    T((0, 0.006, 1.738), (0.094, 0.11, 0.112))          # skull
    T((0, 0.032, 1.71), (0.088, 0.092, 0.1))            # occipital
    T((0, -0.084, 1.748), (0.08, 0.032, 0.028), (-12, 0, 0))  # brow ridge
    for k in (1, -1):
        T((k * 0.044, -0.088, 1.752), (0.046, 0.026, 0.018), (0, k * 14, 0))  # angry brow wings
        T((k * 0.056, -0.07, 1.69), (0.034, 0.034, 0.03))                    # cheekbone
        T((k * 0.066, -0.035, 1.645), (0.03, 0.05, 0.04))                    # jaw hinge
        # swept blade ears: tapering stack leaning back/out
        # swept blade fins (knight-helm style, raked back) rather than upright ears
        base, tip = Vector((k * 0.058, 0.012, 1.8)), Vector((k * 0.084, 0.105, 1.915))
        for i in range(10):
            u = i / 9
            T(base.lerp(tip, u), (0.012 * (1 - u) + 0.003, 0.03 * (1 - u) + 0.004, 0.022), (-48, -k * 10, 0))
    for i in range(7):  # central crest ridge, brow to nape
        a = -0.4 + i * 0.32
        T((0, 0.006 + 0.112 * sin(a) * 1.0, 1.738 + 0.118 * cos(a)), (0.012, 0.03, 0.016), (-a * 57.3, 0, 0))
    T((0, -0.098, 1.705), (0.028, 0.02, 0.048))         # nose bridge
    T((0, -0.05, 1.635), (0.074, 0.07, 0.056))          # jaw
    T((0, -0.09, 1.612), (0.042, 0.032, 0.03))          # chin
    T((0, 0.008, 1.585), (0.08, 0.08, 0.07))            # neck hood
    T((0, 0.012, 1.545), (0.115, 0.1, 0.045))           # hood widening
    T((0, 0.018, 1.512), (0.172, 0.12, 0.042))          # hood flare onto the traps
    obj = V.mesh("CRX9_Cowl")
    remesh(obj, 0.0035, smooth_iters=3, smooth_factor=0.4, close=0.008)
    # carve eye sockets + a breathing slot
    cutters = []
    for k in (1, -1):
        e = Volumes()
        e.T((k * 0.038, -0.104, 1.718), (0.031, 0.03, 0.0125), (0, k * 15, 0))
        cutters.append(e.mesh("cut"))
    slot = Volumes()
    slot.T((0, -0.118, 1.646), (0.026, 0.03, 0.0035))
    cutters.append(slot.mesh("cut"))
    for c in cutters:
        b = obj.modifiers.new("Bool", "BOOLEAN")
        b.operation, b.solver, b.object = "DIFFERENCE", "EXACT", c
        apply_all(obj)
        bpy.data.objects.remove(c)
    dec = obj.modifiers.new("Dec", "DECIMATE")
    dec.ratio = min(1.0, 16000 / max(1, len(obj.data.polygons) * 2))
    apply_all(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bpy.data.objects.remove(obj)
    return bm


def build_lenses(A):
    for k in (1, -1):
        lens = capsule(0.011, 0.05, 16)
        rot = (Euler((0, radians(k * 15), 0)).to_matrix() @ Matrix.Rotation(radians(90), 3, "Y"))
        for v in lens.verts:
            v.co.y *= 0.45
        shape(A, lens, RUBBER, "Head", Vector((k * 0.038, -0.092, 1.718)), rot, mat=1)


# ======================================================================================
# Cape: heavy cloth, folds, thickness, rolled hem (weights as v1: 5 strips x 4 segments)
# ======================================================================================
def build_cape(mat, rig):
    cols, rows = 30, 52
    verts, faces = [], []
    for r in range(rows + 1):
        for c in range(cols + 1):
            u, t = -1 + 2 * c / cols, r / rows
            p = v1.cape_point(u, t)
            p.y += 0.026 * sin(u * pi * 4.5 + 0.6) * t ** 1.1 + 0.01 * sin(u * pi * 9) * t ** 2  # folds
            p.z += 0.01 * sin(u * pi * 4.5 + 0.6) * t * t                                        # uneven hem
            top = max(0.0, 1 - t / 0.16) ** 2                                                  # wrap round the shoulders
            p.x *= 1 + 0.25 * top
            p.y -= 0.075 * u * u * top
            p.z += 0.025 * (1 - u * u) * top
            verts.append(p)
    for r in range(rows):
        for c in range(cols):
            a = r * (cols + 1) + c
            faces.append([a, a + 1, a + cols + 2, a + cols + 1])
    me = bpy.data.meshes.new("CRX9_Cape")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.materials.append(mat)
    obj = bpy.data.objects.new("CRX9_Cape", me)
    bpy.context.scene.collection.objects.link(obj)
    weights = {}
    for r in range(rows + 1):
        t = r / rows
        for c in range(cols + 1):
            vi = r * (cols + 1) + c
            fu = c / cols * (v1.CAPE_STRIPS - 1)
            i0 = min(int(fu), v1.CAPE_STRIPS - 2)
            wu = fu - i0
            ft = t * v1.CAPE_SEGS
            if ft < 0.5:
                segw = [("Chest", 1 - ft * 2), (0, ft * 2)]
            else:
                g = ft - 0.5
                j0 = min(int(g), v1.CAPE_SEGS - 1)
                segw = [(j0, 1 - (g - j0)), (min(j0 + 1, v1.CAPE_SEGS - 1), g - j0)]
            for seg, sw in segw:
                if sw <= 0:
                    continue
                if seg == "Chest":
                    weights.setdefault("Chest", {}).setdefault(vi, 0)
                    weights["Chest"][vi] += sw
                    continue
                for strip, stw in ((i0, 1 - wu), (i0 + 1, wu)):
                    if stw > 0:
                        g_ = weights.setdefault(f"Cape_{strip}_{seg}", {})
                        g_[vi] = g_.get(vi, 0) + sw * stw
    for name, acc in weights.items():
        vg = obj.vertex_groups.new(name=name)
        for vi, w in acc.items():
            vg.add([vi], w, "REPLACE")
    sol = obj.modifiers.new("Solidify", "SOLIDIFY")
    sol.thickness, sol.offset, sol.use_rim = 0.007, 1.0, True
    apply_all(obj)
    v1.attach(obj, rig)
    v1.finish_mesh(me, 80)
    retile(me, 7.0)
    return obj


def retile(me, scale):
    for d in me.uv_layers.active.data:
        d.uv = (d.uv[0] / 1.5 * scale, d.uv[1] / 1.5 * scale)


# ======================================================================================
# Texturing: smart UVs + Cycles bake of a procedural paint/wear shader -> PBR maps (numpy combine)
# ======================================================================================
def smart_uv(obj, margin=0.0025):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    while obj.data.uv_layers:
        obj.data.uv_layers.remove(obj.data.uv_layers[0])
    obj.data.uv_layers.new(name="UVMap")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=radians(62), island_margin=margin, area_weight=0.0, correct_aspect=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def node(nt, kind, **inputs):
    n = nt.nodes.new(kind)
    for k, v in inputs.items():
        if k.startswith("_"):
            setattr(n, k[1:], v)
        else:
            n.inputs[k].default_value = v
    return n


def bake_material(kind):
    m = bpy.data.materials.new("bake_" + kind)
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = node(nt, "ShaderNodeOutputMaterial")
    L = nt.links.new
    tc = node(nt, "ShaderNodeTexCoord")
    attr = node(nt, "ShaderNodeAttribute", _attribute_type="GEOMETRY", _attribute_name="paint")
    if kind == "mask":
        ao = node(nt, "ShaderNodeAmbientOcclusion", Distance=0.05, _samples=16)
        bev = node(nt, "ShaderNodeBevel", Radius=0.0045, _samples=8)
        geo = node(nt, "ShaderNodeNewGeometry")
        dot = node(nt, "ShaderNodeVectorMath", _operation="DOT_PRODUCT")
        L(bev.outputs["Normal"], dot.inputs[0])
        L(geo.outputs["Normal"], dot.inputs[1])
        edge = node(nt, "ShaderNodeMapRange", **{"From Min": 1.0, "From Max": 0.9, "To Min": 0.0, "To Max": 1.0})
        L(dot.outputs["Value"], edge.inputs["Value"])
        p4 = node(nt, "ShaderNodeMath", _operation="DIVIDE")
        p4.inputs[1].default_value = 4.0
        L(attr.outputs["Fac"], p4.inputs[0])
        comb = node(nt, "ShaderNodeCombineColor")
        L(ao.outputs["AO"], comb.inputs[0])
        L(edge.outputs["Result"], comb.inputs[1])
        L(p4.outputs["Value"], comb.inputs[2])
        em = node(nt, "ShaderNodeEmission")
        L(comb.outputs["Color"], em.inputs["Color"])
        L(em.outputs["Emission"], out.inputs["Surface"])
    elif kind == "noise":
        grime = node(nt, "ShaderNodeTexNoise", Scale=4.0, Detail=8.0, Roughness=0.62)
        var = node(nt, "ShaderNodeTexNoise", Scale=1.3, Detail=3.0)
        scr, _ = scratches(nt, tc)
        for n in (grime, var):
            L(tc.outputs["Object"], n.inputs["Vector"])
        comb = node(nt, "ShaderNodeCombineColor")
        L(grime.outputs["Fac"], comb.inputs[0])
        L(scr, comb.inputs[1])
        L(var.outputs["Fac"], comb.inputs[2])
        em = node(nt, "ShaderNodeEmission")
        L(comb.outputs["Color"], em.inputs["Color"])
        L(em.outputs["Emission"], out.inputs["Surface"])
    else:  # normal: bevelled edges + scratches/orange peel on hard parts, padded kevlar weave on rubber
        scr, _ = scratches(nt, tc)
        peel = node(nt, "ShaderNodeTexNoise", Scale=900.0, Detail=2.0)
        L(tc.outputs["Object"], peel.inputs["Vector"])
        hard = node(nt, "ShaderNodeMath", _operation="MULTIPLY_ADD")  # peel*0.15 - scr
        L(peel.outputs["Fac"], hard.inputs[0])
        hard.inputs[1].default_value = 0.15
        neg = node(nt, "ShaderNodeMath", _operation="MULTIPLY")
        L(scr, neg.inputs[0])
        neg.inputs[1].default_value = -1.0
        L(neg.outputs["Value"], hard.inputs[2])
        weave = weave_height(nt, tc)
        is_rub = node(nt, "ShaderNodeMath", _operation="COMPARE")
        L(attr.outputs["Fac"], is_rub.inputs[0])
        is_rub.inputs[1].default_value = float(RUBBER)
        is_rub.inputs[2].default_value = 0.5
        bev = node(nt, "ShaderNodeBevel", Radius=0.0028, _samples=8)
        b_hard = node(nt, "ShaderNodeBump", Strength=0.35, Distance=0.0006)
        b_soft = node(nt, "ShaderNodeBump", Strength=0.9, Distance=0.0012)
        for b, h in ((b_hard, hard.outputs["Value"]), (b_soft, weave)):
            L(h, b.inputs["Height"])
            L(bev.outputs["Normal"], b.inputs["Normal"])
        mix = node(nt, "ShaderNodeMix", _data_type="VECTOR")
        L(is_rub.outputs["Value"], mix.inputs["Factor"])
        L(b_hard.outputs["Normal"], mix.inputs[4])
        L(b_soft.outputs["Normal"], mix.inputs[5])
        bsdf = node(nt, "ShaderNodeBsdfPrincipled")
        L(mix.outputs[1], bsdf.inputs["Normal"])
        L(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


def scratches(nt, tc):
    L = nt.links.new
    vor = node(nt, "ShaderNodeTexVoronoi", Scale=26.0, _feature="DISTANCE_TO_EDGE")
    L(tc.outputs["Object"], vor.inputs["Vector"])
    line = node(nt, "ShaderNodeMapRange", **{"From Min": 0.006, "From Max": 0.0, "To Min": 0.0, "To Max": 1.0})
    L(vor.outputs["Distance"], line.inputs["Value"])
    msk = node(nt, "ShaderNodeTexNoise", Scale=3.5, Detail=4.0)
    L(tc.outputs["Object"], msk.inputs["Vector"])
    mr = node(nt, "ShaderNodeMapRange", **{"From Min": 0.6, "From Max": 0.72, "To Min": 0.0, "To Max": 1.0})
    L(msk.outputs["Fac"], mr.inputs["Value"])
    mul = node(nt, "ShaderNodeMath", _operation="MULTIPLY")
    L(line.outputs["Result"], mul.inputs[0])
    L(mr.outputs["Result"], mul.inputs[1])
    return mul.outputs["Value"], vor


def weave_height(nt, tc):
    """Padded hex panels (Voronoi cells) + fine twill weave: the tactical undersuit look."""
    L = nt.links.new
    cell = node(nt, "ShaderNodeTexVoronoi", Scale=19.0, _feature="DISTANCE_TO_EDGE")
    L(tc.outputs["Object"], cell.inputs["Vector"])
    pad = node(nt, "ShaderNodeMapRange", **{"From Min": 0.0, "From Max": 0.07, "To Min": 0.0, "To Max": 1.0}, _interpolation_type="SMOOTHSTEP")
    L(cell.outputs["Distance"], pad.inputs["Value"])
    wx = node(nt, "ShaderNodeTexWave", Scale=60.0, _wave_type="BANDS", _bands_direction="X", _wave_profile="SIN")
    wz = node(nt, "ShaderNodeTexWave", Scale=60.0, _wave_type="BANDS", _bands_direction="Z", _wave_profile="SIN")
    for w in (wx, wz):
        L(tc.outputs["Object"], w.inputs["Vector"])
    tw = node(nt, "ShaderNodeMath", _operation="MULTIPLY")
    L(wx.outputs["Fac"], tw.inputs[0])
    L(wz.outputs["Fac"], tw.inputs[1])
    h = node(nt, "ShaderNodeMath", _operation="MULTIPLY_ADD")
    L(pad.outputs["Result"], h.inputs[0])
    h.inputs[1].default_value = 0.7
    sc = node(nt, "ShaderNodeMath", _operation="MULTIPLY")
    L(tw.outputs["Value"], sc.inputs[0])
    sc.inputs[1].default_value = 0.3
    L(sc.outputs["Value"], h.inputs[2])
    return h.outputs["Value"]


def bake(obj, kind, samples, size):
    sc = bpy.context.scene
    img = bpy.data.images.new(f"{obj.name}_{kind}", size, size, alpha=False, float_buffer=True)
    mat = bake_material(kind)
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    mat.node_tree.nodes.active = tex
    saved = [s.material for s in obj.material_slots]
    for s in obj.material_slots:
        s.material = mat
    sc.cycles.samples = samples
    for o in sc.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    t0 = time.time()
    bpy.ops.object.bake(type="NORMAL" if kind == "normal" else "EMIT", margin=12, use_clear=True,
                        normal_space="TANGENT", use_selected_to_active=False)
    for s, m in zip(obj.material_slots, saved):
        s.material = m
    log(f"baked {obj.name} {kind} {size}px x{samples} in {time.time() - t0:.0f}s")
    a = np.empty(size * size * 4, np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(size, size, 4)[..., :3]


# per paint id: base colour (linear), roughness, metallic, edge-wear amount, scratch amount
PAL = np.array([
    # r      g      b      rough  metal  wear  scratch
    [0.072, 0.0065, 0.0085, 0.45, 0.10, 1.00, 0.5],  # CRIMSON oxblood paint (deep, satin)
    [0.026, 0.027, 0.03, 0.42, 0.85, 0.55, 0.4],    # GUNMETAL
    [0.013, 0.013, 0.015, 0.62, 0.00, 0.00, 0.2],   # RUBBER / kevlar
    [0.300, 0.270, 0.230, 0.30, 1.00, 0.40, 0.5],   # TRIM brushed alloy
])
BARE = np.array([0.33, 0.32, 0.31])


def combine_maps(mask, noise, suit=False):
    ao, edge, pid = mask[..., 0], mask[..., 1], np.clip(np.rint(mask[..., 2] * 4), 0, 3).astype(int)
    grime, scr, var = noise[..., 0], noise[..., 1], noise[..., 2]
    if suit:
        pid[:] = RUBBER
    P = PAL[pid]
    base = P[..., :3] * (0.86 + 0.28 * var[..., None])
    convex = np.clip((ao - 0.72) / 0.2, 0, 1)
    breakup = np.clip((grime - 0.38) * 3.0, 0, 1)
    wear = np.clip(edge * 1.6, 0, 1) * convex * breakup * P[..., 5]
    s = scr * P[..., 6]
    base = base * (1 - wear[..., None]) + BARE * wear[..., None]
    base = base * (1 - 0.6 * s[..., None]) + (BARE * 0.8) * 0.6 * s[..., None]
    cavity = 0.35 + 0.65 * ao
    dirt = np.clip((grime - 0.45) * 2.2, 0, 1) * (1 - ao) * 1.4
    base = base * cavity[..., None]
    base = base * (1 - np.clip(dirt, 0, 0.7)[..., None]) + np.array([0.012, 0.010, 0.008]) * np.clip(dirt, 0, 0.7)[..., None]
    rough = np.clip(P[..., 3] + (1 - ao) * 0.18 + (grime - 0.5) * 0.12 - wear * 0.12 - s * 0.1 + dirt * 0.15, 0.08, 1)
    metal = np.clip(P[..., 4] + wear * (1 - P[..., 4]), 0, 1)
    srgb = np.where(base <= 0.0031308, base * 12.92, 1.055 * np.power(np.clip(base, 0, None), 1 / 2.4) - 0.055)
    mr = np.stack([np.ones_like(rough), rough, metal], -1)
    return np.clip(srgb, 0, 1), mr


def save_png(name, rgb, non_color):
    h, w = rgb.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    rgba = np.concatenate([rgb, np.ones((h, w, 1))], -1).astype(np.float32)
    img.pixels.foreach_set(rgba.ravel())
    os.makedirs(TEX_OUT, exist_ok=True)
    img.filepath_raw = os.path.join(TEX_OUT, name + ".png")
    img.file_format = "PNG"
    img.save()
    img.pack()
    return img


def pbr_material(name, base, mr, nrm, coat=0.0):
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    L = nt.links.new
    tb = nt.nodes.new("ShaderNodeTexImage")
    tb.image = base
    L(tb.outputs["Color"], bsdf.inputs["Base Color"])
    tm = nt.nodes.new("ShaderNodeTexImage")
    tm.image = mr
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    L(tm.outputs["Color"], sep.inputs["Color"])
    L(sep.outputs["Green"], bsdf.inputs["Roughness"])
    L(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = nrm
    nm = nt.nodes.new("ShaderNodeNormalMap")
    L(tn.outputs["Color"], nm.inputs["Color"])
    L(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if coat:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.25
    return m


def texture(obj, prefix, size, suit=False):
    mask = bake(obj, "mask", 24, size)
    noise = bake(obj, "noise", 4, size)
    nrm = bake(obj, "normal", 10, size)
    base, mr = combine_maps(mask, noise, suit)
    return (save_png(f"{prefix}_basecolor", base, False), save_png(f"{prefix}_mr", mr, True),
            save_png(f"{prefix}_normal", nrm, True))


def simple_materials():
    em = bpy.data.materials.new("CK_EmissiveRed")
    b = next(n for n in em.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (0.9, 0.03, 0.02, 1)
    b.inputs["Emission Color"].default_value = (1.0, 0.04, 0.02, 1)
    b.inputs["Emission Strength"].default_value = 6.0
    b.inputs["Roughness"].default_value = 0.2
    # cape: dark oxblood heavy weave with sheen; tileable weave normal generated here
    n = 512
    yy, xx = np.mgrid[0:n, 0:n] / n * 32
    h = (np.sin(xx * 2 * pi) * np.sin(yy * 2 * pi) * 0.5 + 0.5) ** 1.3 + v2.tile_noise(n, 60, 7) * 0.25
    nrm = v2.height_to_normal(h, 2.4)
    os.makedirs(TEX_OUT, exist_ok=True)
    nimg = save_png("crx9_cape_normal", nrm, True)
    cape = bpy.data.materials.new("CK_CapeCloth")
    nt = cape.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (0.03, 0.0035, 0.0045, 1)
    b.inputs["Roughness"].default_value = 0.82
    b.inputs["Sheen Weight"].default_value = 0.25
    b.inputs["Sheen Tint"].default_value = (0.3, 0.05, 0.05, 1)
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = nimg
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.inputs["Strength"].default_value = 0.7
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    cape.use_backface_culling = False
    return em, cape


# ======================================================================================
# Body skinning, LODs, export
# ======================================================================================
def skin_body(body, rig):
    no = [b for b in rig.data.bones if b.name.startswith("Cape_") or any(x in b.name for x in ("Index", "Middle", "Ring", "Pinky", "Thumb"))]
    for b in no:
        b.use_deform = False
    for o in bpy.context.scene.objects:
        o.select_set(False)
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for b in no:
        b.use_deform = True
    v1.fill_missing_weights(body, rig)


def make_lods(spec):
    out = []
    for o, ratios in spec:
        for lvl, ratio in enumerate(ratios, start=1):
            c = o.copy()
            c.data = o.data.copy()
            c.name = c.data.name = f"{o.name}_LOD{lvl}"
            bpy.context.scene.collection.objects.link(c)
            dec = c.modifiers.new("Decimate", "DECIMATE")
            dec.ratio = ratio
            c.modifiers.move(len(c.modifiers) - 1, 0)
            with bpy.context.temp_override(object=c, active_object=c, selected_objects=[c], selected_editable_objects=[c]):
                bpy.ops.object.modifier_apply(modifier=dec.name)
            out.append(c)
        o.name = o.name + "_LOD0"
    return out


def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    opts = dict(
        filepath=path, export_format="GLB", use_selection=False, export_yup=True, export_apply=False,
        export_texcoord=True, export_normals=True, export_tangents=True, export_materials="EXPORT",
        export_image_format="AUTO", export_skins=True, export_all_influences=False, export_def_bones=False,
        export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
        export_optimize_animation_size=False, export_optimize_animation_keep_anim_armature=True,
        export_anim_single_armature=True, export_reset_pose_bones=True, export_anim_slide_to_zero=False,
        export_cameras=False, export_lights=False, export_extras=False, export_attributes=False,
    )
    valid = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    bpy.ops.export_scene.gltf(**{k: v for k, v in opts.items() if k in valid})


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


# ======================================================================================
def main():
    t_start = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = v1.FPS
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    J = v2.joints()
    rig = v2.build_armature(J)
    high = build_body(J)
    if arg("--preview-body"):
        preview([high], arg("--preview-body"))
        return
    em, cape_mat = simple_materials()
    ph_armor = bpy.data.materials.new("CK_Armor")
    ph_suit = bpy.data.materials.new("CK_Undersuit")
    # undersuit LOD0 (skinned)
    body = decimated_copy(high, 26000, "CRX9_Undersuit")
    body.data.materials.clear()
    body.data.materials.append(ph_suit)
    body.data.polygons.foreach_set("use_smooth", [True] * len(body.data.polygons))
    skin_body(body, rig)
    S = Src(high, rig)
    armor = build_armor(J, S, None, rig, {"armor": ph_armor, "emissive": em}, body)
    lensA = Assembly()
    build_lenses(lensA)
    lenses = lensA.to_object("CRX9_Lenses", [em], rig)
    # merge lenses into the armour (material slot 1 = emissive)
    for o in sc.objects:
        o.select_set(False)
    armor.select_set(True)
    lenses.select_set(True)
    bpy.context.view_layer.objects.active = armor
    bpy.ops.object.join()
    bpy.data.objects.remove(high)
    cape = build_cape(cape_mat, rig)
    log(f"geometry: undersuit {tris(body)} armour {tris(armor)} cape {tris(cape)} tris ({time.time() - t_start:.0f}s)")
    if arg("--preview-geo"):
        preview([body, armor, cape], arg("--preview-geo"))
        return
    # ---- texture bake ----
    smart_uv(armor)
    smart_uv(body)
    ab, amr, an = texture(armor, "crx9_armor", TEX)
    sb, smr, sn = texture(body, "crx9_suit", TEX, suit=True)
    armor_mat = pbr_material("CK_Armor", ab, amr, an)
    suit_mat = pbr_material("CK_Undersuit", sb, smr, sn)
    armor.material_slots[0].material = armor_mat
    body.material_slots[0].material = suit_mat
    for m in (ph_armor, ph_suit):
        bpy.data.materials.remove(m)
    # ---- animation, LODs, export ----
    v1.CLIP_TABLE = v2.clip_table_v2
    meta = v1.bake_clips(rig, J, v2.PoserV2)
    make_lods([(body, (0.4, 0.13)), (armor, (0.34, 0.1)), (cape, (0.45, 0.15))])
    sc.frame_start, sc.frame_end = 0, 60
    if os.path.exists(OUT_GLB) and not os.path.exists(OUT_V2):
        shutil.copyfile(OUT_GLB, OUT_V2)  # keep v2 alongside
    export_glb(OUT_GLB)
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    lod_tris = {f"LOD{l}": sum(tris(o) for o in sc.objects if o.type == "MESH" and o.name.endswith(f"_LOD{l}")) for l in (0, 1, 2)}
    info = {
        "asset": "assets/models/characters/crimson_knight_CRX9_rigged.glb", "version": 3,
        "source": "tools/blender/ck_build_crx9_v3.py", "height_m": v1.HEIGHT, "forward": "+Z (Three.js)",
        "skeleton_bones": len(rig.data.bones), "triangles": lod_tris, "lod_distances_m": [0, 9, 26],
        "laptop_lod": 1, "textures": {"armor": f"{TEX}px base/mr/normal", "undersuit": f"{TEX}px base/mr/normal"},
        "sockets": [b.name for b in rig.data.bones if b.name.startswith("Socket_")], "clips": meta,
    }
    with open(v1.OUT_CLIPS, "w") as fh:
        json.dump(info, fh, indent=2)
    log(f"OK tris={lod_tris} clips={len(meta)} total {time.time() - t_start:.0f}s")
    if arg("--preview"):
        for o in sc.objects:
            if o.type == "MESH":
                o.hide_render = not o.name.endswith("_LOD0")
        preview([o for o in sc.objects if o.name.endswith("_LOD0")], arg("--preview"))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
