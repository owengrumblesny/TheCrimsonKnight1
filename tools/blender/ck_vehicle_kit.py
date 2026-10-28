"""Crimson Knight: Earth-RED — realism kit for the existing vehicles (Blender 5.x). Additive only:
the vehicles keep their geometry; this adds mechanical detail (lathed lamps, brakes, nozzle petals,
springs, hoses, bolts) and a texture pass.

Texture pass: every opaque part's material maps to a paint id (Crimson -> Paint, Gunmetal -> Armor, ...).
bake_vehicle() packs one UV atlas for the whole vehicle and Cycles bakes AO / edge / grime / scratch /
normal detail, combined in numpy with a per-mode palette into base colour, metallic-roughness and normal
maps (the CR-X9 v3 approach). Glass, lamps and screens keep their own materials.
"""
import math
import os
import time
from collections import defaultdict

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

import ck_lib as L

TEX_DIR = os.path.join(L.ROOT, "assets", "source", "textures", "vehicles")

# --------------------------------------------------------------------------------------
# materials
# --------------------------------------------------------------------------------------
PAINT_ID = {"Paint": 0, "Armor": 1, "Rubber": 2, "Alloy": 3, "Carbon": 4, "Iron": 5, "Leather": 6, "Accent": 7, "PaintDark": 8}
# existing vehicle / mode materials -> paint id name (anything not listed is left as-is: glass, lamps, screens)
ALIAS = {"Crimson": "Paint", "CrimsonDark": "PaintDark", "Gunmetal": "Armor", "Black": "Carbon", "Rubber": "Rubber",
         "Stealth_Skin": "Paint", "Stealth_Facet": "PaintDark", "Stealth_Gunmetal": "Armor",
         "Cockpit_Trim": "Carbon", "Cockpit_Seat": "Leather", "Cockpit_Tub": "Armor", **{k: k for k in PAINT_ID}}
DETAIL_MATS = ("Alloy", "Iron", "Accent", "Carbon", "Leather")

# palette rows: linear base r g b, roughness, metallic, edge-wear, scratch, coat
PALETTES = {
    "standard": {
        "Paint": (0.20, 0.006, 0.012, 0.32, 0.35, 0.55, 0.35, 1.0),     # deep candy crimson, metallic, clear-coated
        "Armor": (0.030, 0.031, 0.034, 0.48, 0.70, 0.90, 0.50, 0.0),    # gunmetal ceramic-composite armour
        "Rubber": (0.016, 0.016, 0.017, 0.86, 0.00, 0.00, 0.10, 0.0),
        "Alloy": (0.50, 0.50, 0.52, 0.28, 1.00, 0.10, 0.30, 0.0),       # machined aluminium / titanium
        "Carbon": (0.014, 0.014, 0.016, 0.36, 0.20, 0.40, 0.20, 0.6),   # carbon composite (weave in the normal map)
        "Iron": (0.22, 0.21, 0.20, 0.55, 1.00, 0.20, 0.50, 0.0),        # brake discs, bare steel
        "Leather": (0.035, 0.012, 0.013, 0.80, 0.00, 0.00, 0.05, 0.0),
        "Accent": (0.30, 0.012, 0.02, 0.40, 0.20, 0.50, 0.30, 0.3),     # painted calipers / springs
        "PaintDark": (0.055, 0.004, 0.006, 0.36, 0.30, 0.60, 0.35, 0.8),  # oxblood second tone
    },
    "battle": {},   # filled below: standard, heavier wear and dirt
    "stealth": {
        "Paint": (0.022, 0.017, 0.018, 0.88, 0.05, 0.15, 0.15, 0.0),    # radar-absorbent matte coating, crimson undertone
        "Armor": (0.014, 0.014, 0.015, 0.92, 0.05, 0.10, 0.10, 0.0),
        "Rubber": (0.014, 0.014, 0.015, 0.90, 0.00, 0.00, 0.05, 0.0),
        "Alloy": (0.06, 0.06, 0.065, 0.55, 0.80, 0.05, 0.10, 0.0),      # blackened metal
        "Carbon": (0.012, 0.012, 0.013, 0.70, 0.10, 0.10, 0.10, 0.0),
        "Iron": (0.10, 0.10, 0.10, 0.65, 0.90, 0.10, 0.20, 0.0),
        "Leather": (0.025, 0.012, 0.013, 0.85, 0.00, 0.00, 0.05, 0.0),
        "Accent": (0.06, 0.008, 0.01, 0.75, 0.10, 0.10, 0.10, 0.0),
        "PaintDark": (0.013, 0.012, 0.013, 0.93, 0.03, 0.10, 0.10, 0.0),
    },
}
PALETTES["battle"] = dict(PALETTES["standard"])
WEAR = {"standard": (1.0, 1.0), "battle": (1.8, 1.7), "stealth": (0.4, 0.6)}  # (edge wear, dirt) multipliers

# non-baked materials: name -> spec (base rgb linear, rough, metal, emit rgb, strength, alpha, transmission-ish)
SPECIAL = {
    "LensClear": dict(base=(0.6, 0.6, 0.62), rough=0.02, metal=0.0, alpha=0.18, coat=1.0),
    "Chrome": dict(base=(0.85, 0.85, 0.86), rough=0.06, metal=1.0),
    "LampWhite": dict(base=(0.9, 0.9, 0.9), rough=0.2, emit=(1.0, 0.96, 0.9), strength=18),
    "LensRed": dict(base=(0.25, 0.005, 0.008), rough=0.05, emit=(0.6, 0.01, 0.02), strength=0.6, alpha=0.75, coat=1.0),
    "HotCore": dict(base=(0.3, 0.05, 0.02), rough=0.4, emit=(1.0, 0.25, 0.08), strength=12),
}


def ui_images():
    """Procedural instrument-cluster / nav-map textures for the screens (numpy, 1024x512)."""
    os.makedirs(TEX_DIR, exist_ok=True)
    out = {}
    h, w = 512, 1024
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    red, dim = np.array([1.0, 0.07, 0.06]), np.array([0.35, 0.03, 0.03])
    # cluster: two dials with tick rings + arcs, centre bar graph, text-like blocks
    img = np.zeros((h, w, 3), np.float32) + np.array([0.012, 0.004, 0.005])
    for cx, val in ((260, 0.62), (764, 0.38)):
        r = np.hypot(xx - cx, yy - 256)
        ang = (np.arctan2(yy - 256, xx - cx) + np.pi) / (2 * np.pi)
        ring = (np.abs(r - 200) < 3) & ((ang < 0.62) | (ang > 0.88))
        ticks = (np.abs(r - 182) < 14) & (np.mod(ang * 40, 1.0) < 0.08) & ((ang < 0.62) | (ang > 0.88))
        sweep = ((ang + 0.12) % 1.0)
        arc = (np.abs(r - 160) < 9) & (sweep < 0.12 + val * 0.62) & (sweep > 0.0) & ((ang < 0.62) | (ang > 0.88))
        img[ring | ticks] = dim * 2
        img[arc] = red
        digits = (np.abs(yy - 256) < 26) & (np.abs(xx - cx) < 60) & (np.mod(xx - cx + 60, 30) < 22) & (np.mod(yy, 13) < 9)
        img[digits] = red * 0.9
    bars = (np.abs(xx - 512) < 90) & (yy > 120) & (yy < 400) & (np.mod(yy, 28) < 16)
    lvl = (xx - 422) / 180 < (0.3 + 0.6 * np.abs(np.sin(yy / 47)))
    img[bars & lvl] = red * 0.8
    img[bars & ~lvl] = dim
    out["ui_cluster"] = img
    # nav map: grid of streets, route line, position chevron
    m = np.zeros((h, w, 3), np.float32) + np.array([0.01, 0.004, 0.005])
    streets = (np.mod(xx + 0.3 * yy, 96) < 4) | (np.mod(yy - 0.15 * xx, 80) < 4)
    m[streets] = dim * 1.3
    route = np.abs(yy - (256 + 120 * np.sin(xx / 210))) < 6
    m[route] = red
    chev = (np.abs(xx - 512) < (40 - (yy - 230))) & (yy > 230) & (yy < 290)
    m[chev] = np.array([1, 0.9, 0.85])
    out["ui_map"] = m
    imgs = {}
    for name, a in out.items():
        im = bpy.data.images.new(name, w, h, alpha=False)
        rgba = np.concatenate([a[::-1], np.ones((h, w, 1))], -1).astype(np.float32)
        im.pixels.foreach_set(rgba.ravel())
        im.filepath_raw = os.path.join(TEX_DIR, name + ".png")
        im.file_format = "PNG"
        im.save()
        im.pack()
        imgs[name] = im
    return imgs


_UI = {}


def special_material(name):
    spec = SPECIAL[name]
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = spec["base"] + (1,)
    bsdf.inputs["Roughness"].default_value = spec.get("rough", 0.5)
    bsdf.inputs["Metallic"].default_value = spec.get("metal", 0.0)
    if spec.get("coat"):
        bsdf.inputs["Coat Weight"].default_value = spec["coat"]
        bsdf.inputs["Coat Roughness"].default_value = 0.03
    if "emit" in spec:
        bsdf.inputs["Emission Color"].default_value = spec["emit"] + (1,)
        bsdf.inputs["Emission Strength"].default_value = spec["strength"]
        if "image" in spec:
            if not _UI:
                _UI.update(ui_images())
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = _UI[spec["image"]]
            nt.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
    if spec.get("alpha", 1) < 1:
        bsdf.inputs["Alpha"].default_value = spec["alpha"]
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND"), ("use_transparent_shadow", True)):
            try:
                setattr(m, attr, val)
            except (TypeError, AttributeError):
                pass
    return m


def preview_material(name, palette="standard"):
    r, g, b, rough, metal, _w, _s, coat = PALETTES[palette][name]
    m = bpy.data.materials.new(name)
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (r, g, b, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if coat:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.05
    return m


def register_materials(palette="standard"):
    """Add the detail + lamp materials to ck_lib's registry (never shadows its own names). Call after L.reset()."""
    _UI.clear()
    for n in DETAIL_MATS:
        L._MATS[n] = preview_material(n, palette)
    for n in SPECIAL:
        L._MATS[n] = special_material(n)


def ui_texture(mat, image="ui_cluster"):
    """Drive a screen material's emission from the procedural UI image."""
    if not _UI:
        _UI.update(ui_images())
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = _UI[image]
    nt.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Base Color"].default_value = (0.01, 0.01, 0.012, 1)


def fit_uv(o):
    """Stretch the UVs of a flat screen box over 0..1 on its two largest local axes."""
    me = o.data
    co = [v.co for v in me.vertices]
    lo = [min(c[i] for c in co) for i in range(3)]
    hi = [max(c[i] for c in co) for i in range(3)]
    ax = sorted(range(3), key=lambda i: hi[i] - lo[i], reverse=True)[:2]
    a, b = (ax[0], ax[1]) if ax[0] < ax[1] else (ax[1], ax[0])
    uv = me.uv_layers[0]
    for li, loop in enumerate(me.loops):
        p = me.vertices[loop.vertex_index].co
        uv.data[li].uv = ((p[a] - lo[a]) / max(hi[a] - lo[a], 1e-6), (p[b] - lo[b]) / max(hi[b] - lo[b], 1e-6))


# --------------------------------------------------------------------------------------
# helpers: objects in world space, adopt into pivots without moving
# --------------------------------------------------------------------------------------
def adopt(o, parent):
    if parent is not None:
        bpy.context.view_layer.update()
        o.parent = parent
        o.matrix_parent_inverse = parent.matrix_world.inverted()
    return o


def new_obj(name, bm, mat, parent=None, smooth_angle=32):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(L.material(mat))
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    if hasattr(me, "set_sharp_from_angle"):
        me.set_sharp_from_angle(angle=math.radians(smooth_angle))
    me.uv_layers.new(name="UVMap")
    _planar_uv(me)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return adopt(o, parent)


def _planar_uv(me, scale=2.0):
    uv = me.uv_layers[0]
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            a, b = [(p.y, p.z), (p.x, p.z), (p.x, p.y)][ax]
            uv.data[li].uv = (a * scale, b * scale)


def xform(bm, loc=(0, 0, 0), rot=(0, 0, 0), scale=None):
    M = Matrix.Translation(loc) @ Euler(rot).to_matrix().to_4x4()
    if scale:
        M = M @ Matrix.Diagonal(Vector(scale)).to_4x4()
    bm.transform(M)


def apply_mods(o):
    bpy.context.view_layer.update()
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o], selected_editable_objects=[o]):
        for m in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)


def finish_smooth(o, angle=32):
    me = o.data
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    if hasattr(me, "set_sharp_from_angle"):
        me.set_sharp_from_angle(angle=math.radians(angle))


def remove(*names):
    for n in names:
        o = bpy.data.objects.get(n)
        if o:
            for c in list(o.children_recursive):
                bpy.data.objects.remove(c, do_unlink=True)
            bpy.data.objects.remove(o, do_unlink=True)


# --------------------------------------------------------------------------------------
# primitives (world space)
# --------------------------------------------------------------------------------------
def rbox(name, dims, loc, mat, parent=None, r=0.01, segs=3, rot=(0, 0, 0), taper=(1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        sx, sy = taper if v.co.z > 0 else (1, 1)
        v.co = Vector((v.co.x * dims[0] * sx, v.co.y * dims[1] * sy, v.co.z * dims[2]))
    r = min(r, min(dims) * 0.45)
    if r > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=r, offset_type="OFFSET", segments=segs, profile=0.5, affect="EDGES", clamp_overlap=True)
    xform(bm, loc, rot)
    return new_obj(name, bm, mat, parent)


def lathe(name, prof, mat, parent=None, loc=(0, 0, 0), rot=(0, 0, 0), segs=32, axis="Y", arc=None, smooth_angle=40):
    """prof: [(radius, axial)] ; revolved about local `axis`. arc=(a0, a1) radians for a partial sweep."""
    bm = bmesh.new()
    a0, a1 = arc if arc else (0.0, 2 * math.pi)
    full = arc is None
    n = segs if full else segs + 1
    rings = []
    for r, h in prof:
        ring = []
        for i in range(n):
            a = a0 + (a1 - a0) * i / segs
            c, s = math.cos(a) * r, math.sin(a) * r
            p = {"Y": (c, h, s), "X": (h, c, s), "Z": (c, s, h)}[axis]
            ring.append(bm.verts.new(p))
        rings.append(ring)
    for ra, rb in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % n
            try:
                bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
            except ValueError:
                pass
    if full:
        for ring, r in ((rings[0], prof[0][0]), (rings[-1], prof[-1][0])):
            if r > 1e-4:
                try:
                    bm.faces.new(ring)
                except ValueError:
                    pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    xform(bm, loc, rot)
    return new_obj(name, bm, mat, parent, smooth_angle)


def tube(name, pts, r, mat, parent=None, segs=10, cap=True, radii=None):
    """Sweep a circle along a polyline (parallel-transport frames). radii: optional per-point radius."""
    P = [Vector(p) for p in pts]
    bm = bmesh.new()
    T = [(P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized() for i in range(len(P))]
    up = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
    N = T[0].cross(up).normalized()
    rings = []
    for i, p in enumerate(P):
        if i:
            N = (N - T[i] * N.dot(T[i])).normalized()
        B = T[i].cross(N)
        rr = radii[i] if radii else r
        rings.append([bm.verts.new(p + (N * math.cos(2 * math.pi * k / segs) + B * math.sin(2 * math.pi * k / segs)) * rr) for k in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    if cap:
        bm.faces.new(rings[0][::-1])
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return new_obj(name, bm, mat, parent, 50)


def bent(p0, p1, p2, n=8):
    """Quadratic Bezier polyline through control points (hoses, curved frame tubes)."""
    p0, p1, p2 = Vector(p0), Vector(p1), Vector(p2)
    return [(1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2 for t in (i / n for i in range(n + 1))]


def helix(name, a, b, r_coil, r_wire, turns, mat, parent=None):
    a, b = Vector(a), Vector(b)
    ax = (b - a)
    Ln = ax.length
    q = Vector((0, 0, 1)).rotation_difference(ax.normalized())
    pts = []
    steps = int(turns * 14)
    for i in range(steps + 1):
        t = i / steps
        ang = t * turns * 2 * math.pi
        pts.append(a + q @ Vector((math.cos(ang) * r_coil, math.sin(ang) * r_coil, t * Ln)))
    return tube(name, pts, r_wire, mat, parent, segs=6)


def strut(name, p0, p1, w, t, mat, parent=None, r=None):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    o = rbox(name, (w, t, d.length), (0, 0, 0), mat, None, r=r if r is not None else min(w, t) * 0.3, segs=1)
    o.matrix_world = Matrix.Translation((p0 + p1) / 2) @ Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    return adopt(o, parent)


def slab(name, pts, t, mat, parent=None, r=0.006, segs=2):
    """Flat plate through 3+ world points (coplanar-ish), t thick behind, rounded edges."""
    bm = bmesh.new()
    P = [Vector(p) for p in pts]
    n = (P[1] - P[0]).cross(P[2] - P[0]).normalized()
    top = [bm.verts.new(p) for p in P]
    bot = [bm.verts.new(p - n * t) for p in P]
    bm.faces.new(top)
    bm.faces.new(bot[::-1])
    k = len(P)
    for i in range(k):
        bm.faces.new((top[i], bot[i], bot[(i + 1) % k], top[(i + 1) % k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if r:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(r, t * 0.45), offset_type="OFFSET", segments=segs, profile=0.5, affect="EDGES", clamp_overlap=True)
    return new_obj(name, bm, mat, parent)


def mirror_x(pts):
    return [(-x, y, z) for x, y, z in reversed(pts)]


def arc_pts(c, r, a0, a1, n):
    return [(c[0] + math.cos(math.radians(a0 + (a1 - a0) * i / n)) * r, c[1] + math.sin(math.radians(a0 + (a1 - a0) * i / n)) * r) for i in range(n + 1)]


def bolts(name, pts, normal_rot, r, mat, parent=None, h=0.012):
    for i, p in enumerate(pts):
        lathe(f"{name}{i}", [(0, h), (r * 0.8, h), (r, h * 0.6), (r, 0)], mat, parent, p, normal_rot, segs=6, axis="Z", smooth_angle=20)


def brake(name, spin_parent, fixed_parent, c, disc_r, side, w):
    cx = Vector(c) + Vector((side * w * 0.15, 0, 0))
    lathe(name + "_disc", [(disc_r * 0.55, -0.018), (disc_r, -0.018), (disc_r, 0.018), (disc_r * 0.55, 0.018)], "Iron", spin_parent, cx, segs=40, axis="X")
    lathe(name + "_bell", [(disc_r * 0.3, 0.05 * side), (disc_r * 0.56, 0.02 * side), (disc_r * 0.56, -0.02 * side), (disc_r * 0.3, -0.02 * side)],
          "Alloy", spin_parent, cx, segs=24, axis="X")
    # caliper: hugs the disc edge at the trailing top
    a0 = math.radians(25)
    for s in (-1, 1):
        pts = [cx + Vector((s * 0.035, math.cos(a0 + t) * (disc_r - 0.03), math.sin(a0 + t) * (disc_r - 0.03))) for t in np.linspace(-0.45, 0.45, 6)]
        tube(f"{name}_caliper{s}", pts, 0.035, "Accent", fixed_parent, segs=8)
    p = cx + Vector((0, math.cos(a0) * (disc_r + 0.01), math.sin(a0) * (disc_r + 0.01)))
    rbox(name + "_bridge", (0.11, 0.06, 0.05), p, "Accent", fixed_parent, r=0.015, rot=(a0 - math.pi / 2, 0, 0))


def lamp_projector(name, parent, c, r, facing=(0, -1, 0), mat_lens="LensClear", mat_core="LampWhite"):
    """Projector headlamp: chrome reflector bowl, emitter, clear lens, facing `facing`."""
    rot = Vector((0, 1, 0)).rotation_difference(Vector(facing).normalized()).to_euler()
    lathe(name + "_bowl", [(r * 0.25, 0.0), (r * 0.7, 0.03), (r, 0.07), (r * 1.08, 0.075)], "Chrome", parent, c, rot, segs=20, axis="Y")
    lathe(name + "_core", [(0, 0.035), (r * 0.25, 0.035), (r * 0.25, 0.0)], mat_core, parent, c, rot, segs=12, axis="Y")
    lathe(name + "_lens", [(0, 0.1), (r * 0.6, 0.095), (r * 0.95, 0.078)], mat_lens, parent, c, rot, segs=20, axis="Y")


def vent(name, parent, c, w, l, slats, mat_frame="Carbon", rot=(0, 0, 0), depth=0.03):
    """Recessed vent: frame + angled slats (local X across, local Y along)."""
    M = Matrix.Translation(c) @ Euler(rot).to_matrix().to_4x4()
    rbox(name + "_well", (w, l, depth), M @ Vector((0, 0, -depth / 2)), "Carbon", parent, r=0.006, rot=rot)
    for i in range(slats):
        y = -l / 2 + l * (i + 0.5) / slats
        rbox(f"{name}_slat{i}", (w * 0.96, 0.012, depth * 0.9), M @ Vector((0, y, -depth * 0.25)), mat_frame if mat_frame != "Carbon" else "Armor", parent,
             r=0.003, segs=1, rot=(Euler(rot).to_matrix() @ Euler((math.radians(35), 0, 0)).to_matrix()).to_euler())


# --------------------------------------------------------------------------------------
# UV atlas + bake
# --------------------------------------------------------------------------------------
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
    Ln = nt.links.new
    attr = node(nt, "ShaderNodeAttribute", _attribute_type="GEOMETRY", _attribute_name="paint")
    geo = node(nt, "ShaderNodeNewGeometry")
    if kind == "mask":
        ao = node(nt, "ShaderNodeAmbientOcclusion", Distance=0.12, _samples=16)
        bev = node(nt, "ShaderNodeBevel", Radius=0.008, _samples=8)
        dot = node(nt, "ShaderNodeVectorMath", _operation="DOT_PRODUCT")
        Ln(bev.outputs["Normal"], dot.inputs[0])
        Ln(geo.outputs["Normal"], dot.inputs[1])
        edge = node(nt, "ShaderNodeMapRange", **{"From Min": 1.0, "From Max": 0.9, "To Min": 0.0, "To Max": 1.0})
        Ln(dot.outputs["Value"], edge.inputs["Value"])
        p8 = node(nt, "ShaderNodeMath", _operation="DIVIDE")
        p8.inputs[1].default_value = 16.0
        Ln(attr.outputs["Fac"], p8.inputs[0])
        comb = node(nt, "ShaderNodeCombineColor")
        Ln(ao.outputs["AO"], comb.inputs[0])
        Ln(edge.outputs["Result"], comb.inputs[1])
        Ln(p8.outputs["Value"], comb.inputs[2])
        em = node(nt, "ShaderNodeEmission")
        Ln(comb.outputs["Color"], em.inputs["Color"])
        Ln(em.outputs["Emission"], out.inputs["Surface"])
    elif kind == "noise":
        grime = node(nt, "ShaderNodeTexNoise", Scale=2.2, Detail=8.0, Roughness=0.62)
        var = node(nt, "ShaderNodeTexNoise", Scale=0.7, Detail=3.0)
        Ln(geo.outputs["Position"], grime.inputs["Vector"])
        Ln(geo.outputs["Position"], var.inputs["Vector"])
        scr = scratches(nt, geo)
        # road dust climbs from the ground: grime + (1 - z/0.9)
        sep = node(nt, "ShaderNodeSeparateXYZ")
        Ln(geo.outputs["Position"], sep.inputs["Vector"])
        dust = node(nt, "ShaderNodeMapRange", **{"From Min": 0.9, "From Max": 0.1, "To Min": 0.0, "To Max": 0.45})
        Ln(sep.outputs["Z"], dust.inputs["Value"])
        add = node(nt, "ShaderNodeMath", _operation="ADD")
        Ln(grime.outputs["Fac"], add.inputs[0])
        Ln(dust.outputs["Result"], add.inputs[1])
        comb = node(nt, "ShaderNodeCombineColor")
        Ln(add.outputs["Value"], comb.inputs[0])
        Ln(scr, comb.inputs[1])
        Ln(var.outputs["Fac"], comb.inputs[2])
        em = node(nt, "ShaderNodeEmission")
        Ln(comb.outputs["Color"], em.inputs["Color"])
        Ln(em.outputs["Emission"], out.inputs["Surface"])
    else:  # normal: rounded edges + orange peel/scratches on hard parts, carbon weave, leather grain
        scr = scratches(nt, geo)
        peel = node(nt, "ShaderNodeTexNoise", Scale=700.0, Detail=2.0)
        Ln(geo.outputs["Position"], peel.inputs["Vector"])
        hard = node(nt, "ShaderNodeMath", _operation="MULTIPLY_ADD")
        Ln(peel.outputs["Fac"], hard.inputs[0])
        hard.inputs[1].default_value = 0.12
        neg = node(nt, "ShaderNodeMath", _operation="MULTIPLY")
        Ln(scr, neg.inputs[0])
        neg.inputs[1].default_value = -1.0
        Ln(neg.outputs["Value"], hard.inputs[2])
        wx = node(nt, "ShaderNodeTexWave", Scale=180.0, _wave_type="BANDS", _bands_direction="DIAGONAL", _wave_profile="SAW")
        Ln(geo.outputs["Position"], wx.inputs["Vector"])
        is_c = node(nt, "ShaderNodeMath", _operation="COMPARE")
        Ln(attr.outputs["Fac"], is_c.inputs[0])
        is_c.inputs[1].default_value = float(PAINT_ID["Carbon"])
        is_c.inputs[2].default_value = 0.5
        is_r = node(nt, "ShaderNodeMath", _operation="COMPARE")
        Ln(attr.outputs["Fac"], is_r.inputs[0])
        is_r.inputs[1].default_value = float(PAINT_ID["Rubber"])
        is_r.inputs[2].default_value = 0.5
        weave = node(nt, "ShaderNodeMath", _operation="MULTIPLY")
        Ln(wx.outputs["Fac"], weave.inputs[0])
        Ln(is_c.outputs["Value"], weave.inputs[1])
        grain = node(nt, "ShaderNodeTexNoise", Scale=260.0, Detail=1.0)
        Ln(geo.outputs["Position"], grain.inputs["Vector"])
        rub = node(nt, "ShaderNodeMath", _operation="MULTIPLY")
        Ln(grain.outputs["Fac"], rub.inputs[0])
        Ln(is_r.outputs["Value"], rub.inputs[1])
        h1 = node(nt, "ShaderNodeMath", _operation="ADD")
        Ln(hard.outputs["Value"], h1.inputs[0])
        Ln(weave.outputs["Value"], h1.inputs[1])
        h2 = node(nt, "ShaderNodeMath", _operation="ADD")
        Ln(h1.outputs["Value"], h2.inputs[0])
        Ln(rub.outputs["Value"], h2.inputs[1])
        bev = node(nt, "ShaderNodeBevel", Radius=0.006, _samples=8)
        bump = node(nt, "ShaderNodeBump", Strength=0.3, Distance=0.0008)
        Ln(h2.outputs["Value"], bump.inputs["Height"])
        Ln(bev.outputs["Normal"], bump.inputs["Normal"])
        bsdf = node(nt, "ShaderNodeBsdfPrincipled")
        Ln(bump.outputs["Normal"], bsdf.inputs["Normal"])
        Ln(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


def scratches(nt, geo):
    Ln = nt.links.new
    vor = node(nt, "ShaderNodeTexVoronoi", Scale=14.0, _feature="DISTANCE_TO_EDGE")
    Ln(geo.outputs["Position"], vor.inputs["Vector"])
    line = node(nt, "ShaderNodeMapRange", **{"From Min": 0.005, "From Max": 0.0, "To Min": 0.0, "To Max": 1.0})
    Ln(vor.outputs["Distance"], line.inputs["Value"])
    msk = node(nt, "ShaderNodeTexNoise", Scale=1.8, Detail=4.0)
    Ln(geo.outputs["Position"], msk.inputs["Vector"])
    mr = node(nt, "ShaderNodeMapRange", **{"From Min": 0.58, "From Max": 0.7, "To Min": 0.0, "To Max": 1.0})
    Ln(msk.outputs["Fac"], mr.inputs["Value"])
    mul = node(nt, "ShaderNodeMath", _operation="MULTIPLY")
    Ln(line.outputs["Result"], mul.inputs[0])
    Ln(mr.outputs["Result"], mul.inputs[1])
    return mul.outputs["Value"]


def baked_objects(root):
    out = []
    for o in root.children_recursive:
        if o.type == "MESH" and not o.name.endswith("_COL") and o.data.materials and o.data.materials[0]:
            if o.data.materials[0].name.split(".")[0] in ALIAS:
                out.append(o)
    return out


def atlas_uv(objs, margin=0.0015):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        me = o.data
        while me.uv_layers:
            me.uv_layers.remove(me.uv_layers[0])
        me.uv_layers.new(name="UVMap")
        # paint id per face from its material
        a = me.attributes.get("paint") or me.attributes.new("paint", "FLOAT", "FACE")
        ids = [float(PAINT_ID[ALIAS.get(me.materials[p.material_index].name.split(".")[0], "Armor")]) for p in me.polygons]
        a.data.foreach_set("value", ids)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=margin, area_weight=0.0, correct_aspect=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_pass(objs, kind, samples, size, log):
    sc = bpy.context.scene
    img = bpy.data.images.new(f"_bake_{kind}", size, size, alpha=False, float_buffer=True)
    mat = bake_material(kind)
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    mat.node_tree.nodes.active = tex
    saved = {o: [s.material for s in o.material_slots] for o in objs}
    for o in objs:
        for s in o.material_slots:
            s.material = mat
    sc.cycles.samples = samples
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    t0 = time.time()
    bpy.ops.object.bake(type="NORMAL" if kind == "normal" else "EMIT", margin=6, use_clear=True, normal_space="TANGENT", use_selected_to_active=False)
    for o, ms in saved.items():
        for s, m in zip(o.material_slots, ms):
            s.material = m
    log(f"baked {kind} {size}px x{samples} on {len(objs)} objects in {time.time() - t0:.0f}s")
    a = np.empty(size * size * 4, np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    bpy.data.materials.remove(mat)
    return a.reshape(size, size, 4)[..., :3]


def combine(mask, noise, palette):
    keys = sorted(PAINT_ID, key=PAINT_ID.get)
    P = np.array([PALETTES[palette][k] for k in keys], np.float32)
    ew, dm = WEAR[palette]
    ao, edge = mask[..., 0], mask[..., 1]
    pid = np.clip(np.rint(mask[..., 2] * 16), 0, len(keys) - 1).astype(int)
    grime, scr, var = noise[..., 0], noise[..., 1], noise[..., 2]
    Q = P[pid]
    base = Q[..., :3] * (0.88 + 0.24 * var[..., None])
    convex = np.clip((ao - 0.7) / 0.2, 0, 1)
    breakup = np.clip((grime - 0.4) * 3.0, 0, 1)
    wear = np.clip(edge * 1.5 * ew, 0, 1) * convex * breakup * Q[..., 5]
    s = scr * Q[..., 6]
    bare = np.array([0.30, 0.29, 0.28], np.float32)
    primer = np.array([0.05, 0.05, 0.055], np.float32)
    # chipped paint shows dark primer first, bare metal at the very edge
    base = base * (1 - wear[..., None]) + (primer * 0.6 + bare * 0.4) * wear[..., None]
    base = base * (1 - 0.5 * s[..., None]) + bare * 0.5 * s[..., None]
    cavity = 0.4 + 0.6 * ao
    dirt = np.clip((grime - 0.5) * 2.0 * dm, 0, 0.85) * (0.35 + 0.65 * (1 - ao))
    dust = np.array([0.075, 0.064, 0.052], np.float32)
    base = base * cavity[..., None]
    base = base * (1 - dirt[..., None]) + dust * dirt[..., None]
    rough = np.clip(Q[..., 3] + (1 - ao) * 0.15 + dirt * 0.45 - wear * 0.1 + s * 0.15, 0.06, 1)
    metal = np.clip(Q[..., 4] * (1 - dirt) + wear * 0.6, 0, 1)
    srgb = np.where(base <= 0.0031308, base * 12.92, 1.055 * np.power(np.clip(base, 0, None), 1 / 2.4) - 0.055)
    mr = np.stack([np.ones_like(rough), rough, metal], -1)
    coat = Q[..., 7] * (1 - dirt)
    return np.clip(srgb, 0, 1), mr, float(np.median(coat[pid == 0])) if np.any(pid == 0) else 0.0


def downscaled(mat, size, suffix):
    """Copy of a baked material with its images resized (LOD files)."""
    m = mat.copy()
    m.name = mat.name + suffix
    for n in m.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image:
            img = n.image.copy()
            img.name = n.image.name + suffix
            img.scale(size, size)
            img.pack()
            n.image = img
    return m


def export(path, objs, animations=True, jpeg=95):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    opts = dict(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                export_texcoord=True, export_normals=True, export_tangents=True, export_materials="EXPORT",
                export_image_format="JPEG" if jpeg else "AUTO", export_jpeg_quality=jpeg or 90,
                export_animations=animations, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                export_cameras=False, export_lights=False, export_extras=True, export_optimize_animation_size=False)
    valid = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    bpy.ops.export_scene.gltf(**{k: v for k, v in opts.items() if k in valid})


def to_image(name, rgb, non_color, save_dir=None):
    h, w = rgb.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    img.pixels.foreach_set(np.concatenate([rgb, np.ones((h, w, 1), np.float32)], -1).astype(np.float32).ravel())
    if save_dir:
        os.makedirs(save_dir, exist_ok=True)
        img.filepath_raw = os.path.join(save_dir, name + ".png")
        img.file_format = "PNG"
        img.save()
    img.pack()
    return img


def pbr_material(name, base, mr, nrm, coat):
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    Ln = nt.links.new
    tb = nt.nodes.new("ShaderNodeTexImage")
    tb.image = base
    Ln(tb.outputs["Color"], bsdf.inputs["Base Color"])
    tm = nt.nodes.new("ShaderNodeTexImage")
    tm.image = mr
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    Ln(tm.outputs["Color"], sep.inputs["Color"])
    Ln(sep.outputs["Green"], bsdf.inputs["Roughness"])
    Ln(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = nrm
    nm = nt.nodes.new("ShaderNodeNormalMap")
    Ln(tn.outputs["Color"], nm.inputs["Color"])
    Ln(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if coat > 0.05:
        bsdf.inputs["Coat Weight"].default_value = coat * 0.8
        bsdf.inputs["Coat Roughness"].default_value = 0.06
    return m


def bake_vehicle(root, name, palette, size=2048, log=print, save_dir=None):
    """Atlas-UV every opaque part of `root`, bake, and swap their materials for one PBR material."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    objs = baked_objects(root)
    t0 = time.time()
    atlas_uv(objs)
    log(f"atlas UV on {len(objs)} objects in {time.time() - t0:.0f}s")
    mask = bake_pass(objs, "mask", 12, size, log)
    noise = bake_pass(objs, "noise", 1, size, log)
    nrm = bake_pass(objs, "normal", 6, size, log)
    base, mr, coat = combine(mask, noise, palette)
    imgs = (to_image(f"{name}_basecolor", base, False, save_dir), to_image(f"{name}_mr", mr, True, save_dir),
            to_image(f"{name}_normal", nrm, True, save_dir))
    mat = pbr_material(name, *imgs, coat)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
        if o.data.attributes.get("paint"):
            o.data.attributes.remove(o.data.attributes["paint"])
    return mat


def tris(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o.type == "MESH" and not o.name.endswith("_COL"))
