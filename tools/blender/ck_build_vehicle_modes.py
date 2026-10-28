"""Crimson Knight: Earth-RED — per-mode variants + first-person cockpits for the three vehicles.

Builds on ck_build_vehicles.py: each variant starts from the same base build (same pivots, anchors and
clips), gets a first-person cockpit, then the mode's changes:

  CR-X1 Interceptor  pursuit | battle | stealth
  CR-B1 Batcycle     pursuit | battle | stealth
  CR-A1 Specter      flight  | vtol   | stealth

  stealth  matte radar-absorbent materials, emissives dimmed to a faint red, faceted panels, tucked aero,
           lights/antennas retracted
  battle   armour plates, weapon pods, turret / battle panels posed deployed at rest
  pursuit  the baseline, polished (splitter, antenna, strobes, mirrors)
  vtol     VTOL nacelles posed rotated down at rest

Pivots whose rest pose differs from the base (BattlePanel_*, Turret, VTOL_*) keep their clips unchanged:
the clip still runs base -> deployed, so the game plays it for the transition and then swaps the model.
The cockpit is cut into the hull (exact boolean) under a transparent canopy so camera_cockpit sees
an interior; interior meshes are named IN_* and left out of LOD1. The bike gains a camera_cockpit empty.

Writes assets/models/vehicles/<Base>_<mode>.glb (+ _lod1.glb), the `modes` map in
config/vehicle_assets.json, and review renders in docs/renders/vehicle_modes/.

  blender -b --factory-startup --python tools/blender/ck_build_vehicle_modes.py [-- --no-render] [-- crx1|crb1|cra1 ...]
"""
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ck_lib as L  # noqa: E402
import ck_build_vehicles as V  # noqa: E402
import ck_vehicle_kit as K  # noqa: E402
from ck_vehicle_kit import adopt  # noqa: E402

OUT = os.path.join(L.ROOT, "assets", "models", "vehicles")
RENDERS = os.path.join(L.ROOT, "docs", "renders", "vehicle_modes")
CFG = os.path.join(L.ROOT, "config", "vehicle_assets.json")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER = "--no-render" not in ARGS
BAKE = "--no-bake" not in ARGS
TEX = int(ARGS[ARGS.index("--tex") + 1]) if "--tex" in ARGS else 2048
deg = L.deg
SKY_STRENGTH = float(ARGS[ARGS.index("--sky") + 1]) if "--sky" in ARGS else 0.3


# ======================================================================================
# materials (mode sets)
# ======================================================================================
MODE_MATS = {
    # stealth: radar-absorbent matte, near-black with a crimson undertone
    "Stealth_Skin": dict(png="gunmetal.png", tint=(0.2, 0.13, 0.14), rough=0.88, metal=0.1),
    "Stealth_Facet": dict(png="gunmetal.png", tint=(0.11, 0.1, 0.11), rough=0.93, metal=0.05),
    "Stealth_Gunmetal": dict(png="gunmetal.png", tint=0.28, rough=0.8, metal=0.3),
    "Stealth_Glow": dict(png="red_emissive.png", tint=0.08, emit=(0.8, 0.02, 0.04), strength=0.35),
    "Stealth_Glass": dict(png="glass.png", tint=(0.12, 0.1, 0.1), rough=0.12, metal=0.4, alpha=0.45),
    # shared by every variant
    "CanopyGlass": dict(png="glass.png", rough=0.04, metal=0.2, alpha=0.22, coat=1.0),
    "Cockpit_Screen": dict(png="glass.png", tint=0.05, rough=0.9, emit=(1.0, 0.0, 0.02), strength=0.5),
    "Cockpit_ScreenDim": dict(png="glass.png", tint=0.05, rough=0.9, emit=(1.0, 0.0, 0.02), strength=0.2),
    "Cockpit_Gauge": dict(png="red_emissive.png", emit=(1, 0.25, 0.2), strength=4),
    "Cockpit_HUD": dict(png="glass.png", tint=0.1, emit=(0.8, 0.1, 0.15), strength=0.25, alpha=0.15),
    "Cockpit_Trim": dict(png="black_rubber.png", tint=0.8, rough=0.5, metal=0.4),
    "Cockpit_Seat": dict(png="black_rubber.png", tint=(0.5, 0.18, 0.2), rough=0.85),
    "Cockpit_Tub": dict(png="gunmetal.png", tint=0.35, rough=0.7, metal=0.3),
    "Battle_Glow": dict(png="red_emissive.png", emit=(1, 0.1, 0.06), strength=9),
}

STEALTH_SWAP = {"Crimson": "Stealth_Skin", "CrimsonDark": "Stealth_Facet", "Gunmetal": "Stealth_Gunmetal",
                "EmissiveRed": "Stealth_Glow", "EmissiveWhite": "Stealth_Glow", "Battle_Glow": "Stealth_Glow",
                "Glass": "Stealth_Glass", "CanopyGlass": "Stealth_Glass", "Cockpit_Screen": "Cockpit_ScreenDim",
                "Screen": "Cockpit_ScreenDim", "LampWhite": "Stealth_Glow", "LensRed": "Stealth_Glow", "HotCore": "Stealth_Glow",
                "LensClear": "Stealth_Glass", "Chrome": "Stealth_Gunmetal"}


def make_mat(name, spec):
    m = bpy.data.materials.new(name)
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = next(nd for nd in nodes if nd.type == "BSDF_PRINCIPLED")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = L._img(os.path.join(L.PNG, spec["png"]))
    col = tex.outputs["Color"]
    if "tint" in spec:
        mix = nodes.new("ShaderNodeMix")
        mix.data_type, mix.blend_type = "RGBA", "MULTIPLY"
        mix.inputs["Factor"].default_value = 1
        t = spec["tint"]
        mix.inputs["B"].default_value = (tuple(t) if isinstance(t, tuple) else (t,) * 3) + (1,)
        links.new(col, mix.inputs["A"])
        col = mix.outputs["Result"]
    links.new(col, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = spec.get("rough", 0.5)
    bsdf.inputs["Metallic"].default_value = spec.get("metal", 0.0)
    if "n" in spec and os.path.exists(os.path.join(L.DETAIL, spec["n"])):
        nt = nodes.new("ShaderNodeTexImage")
        nt.image = L._img(os.path.join(L.DETAIL, spec["n"]), True)
        nm = nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = 0.6
        links.new(nt.outputs["Color"], nm.inputs["Color"])
        links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if spec.get("coat"):
        bsdf.inputs["Coat Weight"].default_value = spec["coat"]
        bsdf.inputs["Coat Roughness"].default_value = 0.05
    if "emit" in spec:
        bsdf.inputs["Emission Color"].default_value = spec["emit"] + (1,)
        bsdf.inputs["Emission Strength"].default_value = spec["strength"]
    if spec.get("alpha", 1) < 1:
        bsdf.inputs["Alpha"].default_value = spec["alpha"]
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND"), ("use_transparent_shadow", True)):
            if hasattr(m, attr):
                try:
                    setattr(m, attr, val)
                except (TypeError, AttributeError):
                    pass
    L._MATS[name] = m
    return m


def ensure_mats():
    for name, spec in MODE_MATS.items():
        if name not in L._MATS:
            make_mat(name, spec)
    K.register_materials()
    for n in ("Cockpit_Screen", "Cockpit_ScreenDim"):
        K.ui_texture(L._MATS[n])


def base_mat(m):
    return m.name.split(".")[0]


def swap_materials(objs, table):
    for o in objs:
        if o.type != "MESH":
            continue
        for i, m in enumerate(o.data.materials):
            if m and base_mat(m) in table:
                o.data.materials[i] = L.material(table[base_mat(m)])


# ======================================================================================
# geometry helpers (all coordinates in WORLD space; adopt() parents without moving)
# ======================================================================================
def ob(name):
    return bpy.data.objects[name]


def box(name, dims, loc, mat, parent, **kw):
    return adopt(L.box(name, dims, loc, mat, None, **kw), parent)


def cyl(name, r1, r2, depth, loc, mat, parent, rot=(0, 0, 0), segs=12, **kw):
    return adopt(L.cyl(name, r1, r2, depth, loc, mat, None, rot, segs=segs, **kw), parent)


def torus(name, major, minor, loc, mat, parent, rot=(0, 0, 0), seg=24, ring=6):
    return adopt(L.torus(name, major, minor, loc, mat, None, rot, seg=seg, ring=ring), parent)


def strut(name, p0, p1, t, mat, parent, w=None):
    """Box beam from p0 to p1 (t thick, w wide)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    o = L.box(name, (w or t, t, d.length), (0, 0, 0), mat, None, bevel=min(t, w or t) * 0.3)
    o.matrix_world = Matrix.Translation((p0 + p1) / 2) @ Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    o.location, o.rotation_euler = o.matrix_world.to_translation(), o.matrix_world.to_euler()
    return adopt(o, parent)


def polyline(name, pts, t, mat, parent, w=None):
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        strut(f"{name}_{i}", a, b, t, mat, parent, w)


def facet(name, pts, t, mat, parent, bevel=0.008):
    """Flat armour/RAM panel through 3-4 world points, `t` thick (extruded behind the point face)."""
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
    L.bevel_sharp(bm, bevel, 1, 30)
    return adopt(L.obj_from_bm(name, bm, mat), parent)


def mirror_x(pts):
    return [(-x, y, z) for x, y, z in reversed(pts)]


def facet_pair(name, pts, t, mat, parent, **kw):
    facet(name + "_L", pts, t, mat, parent, **kw)
    facet(name + "_R", mirror_x(pts), t, mat, parent, **kw)


def remove(*names):
    for n in names:
        o = bpy.data.objects.get(n)
        if o:
            for c in list(o.children):
                bpy.data.objects.remove(c, do_unlink=True)
            bpy.data.objects.remove(o, do_unlink=True)


def subtree(name):
    return set(L.descendants(ob(name)))


def cut_cockpit(scope, dims, loc, keep_out=()):
    """Exact-boolean a cockpit tub out of every mesh under `scope` that the cutter box touches.
    The new cavity walls take the Cockpit_Tub material."""
    cutter = L.box("_cockpit_cutter", dims, loc, "Cockpit_Tub", None, bevel=0.06, segs=2)
    bpy.context.view_layer.update()
    lo = Vector(loc) - Vector(dims) / 2
    hi = Vector(loc) + Vector(dims) / 2
    skip = set()
    for n in keep_out:
        skip |= subtree(n)
    for o in L.descendants(scope):
        if o.type != "MESH" or o in skip or o.name.endswith("_COL") or o.name.startswith("IN_"):
            continue
        pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
        omin = Vector(map(min, *pts))
        omax = Vector(map(max, *pts))
        if any(omax[i] < lo[i] or omin[i] > hi[i] for i in range(3)):
            continue
        mod = o.modifiers.new("cockpit_cut", "BOOLEAN")
        mod.operation, mod.object = "DIFFERENCE", cutter
        for attr, val in (("solver", "EXACT"), ("material_mode", "TRANSFER")):
            try:
                setattr(mod, attr, val)
            except (TypeError, AttributeError):
                pass
        with bpy.context.temp_override(object=o, active_object=o):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def open_bottom(o):
    """Drop the canopy's flat underside so the glass doesn't veil the cockpit from inside."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z < -0.9], context="FACES")
    bm.to_mesh(o.data)
    bm.free()


def gauge(name, centre, normal_rot, r, parent):
    """Ring gauge: emissive ring, dark face, needle."""
    torus(name + "_ring", r, r * 0.07, centre, "Cockpit_Gauge", parent, normal_rot, seg=20, ring=4)
    cyl(name + "_face", r * 0.95, r * 0.95, 0.004, centre, "Cockpit_Trim", parent, normal_rot, segs=16, bevel=0)


# ======================================================================================
# cockpits
# ======================================================================================
def cockpit_crx1():
    body, cab, canopy = ob("Body"), ob("Cockpit"), ob("Canopy")
    remove("X1_seat_base", "X1_seat_back", "X1_dash", "X1_screen", "X1_yoke")
    cut_cockpit(body, (1.12, 1.6, 0.9), (0, -0.82, 1.17), keep_out=("Canopy", "Door_L", "Door_R", "Cockpit"))
    for o in L.descendants(canopy):
        if o.type == "MESH":
            swap_materials([o], {"Glass": "CanopyGlass"})
    # tub floor, seat (rider hips at seat_attach 0,-0.3,0.72; eye at camera_cockpit 0,-0.6,1.25)
    box("IN_X1_floor", (1.0, 1.55, 0.04), (0, -0.82, 0.74), "Cockpit_Tub", cab, bevel=0.01)
    box("IN_X1_seat_base", (0.52, 0.5, 0.12), (0, -0.28, 0.8), "Cockpit_Seat", cab, bevel=0.04)
    box("IN_X1_seat_back", (0.52, 0.12, 0.62), (0, 0.0, 1.1), "Cockpit_Seat", cab, bevel=0.04, rot=deg(-16, 0, 0))
    for k in (1, -1):
        box(f"IN_X1_seat_bolster{k}", (0.08, 0.45, 0.14), (k * 0.27, -0.28, 0.86), "Cockpit_Seat", cab, bevel=0.03)
        box(f"IN_X1_seat_wing{k}", (0.08, 0.12, 0.5), (k * 0.27, 0.0, 1.12), "Cockpit_Trim", cab, bevel=0.02, rot=deg(-16, 0, 0))
    # dashboard: dash top under the canopy's front edge, binnacle with the cluster, centre stack
    box("IN_X1_dash", (1.08, 0.42, 0.3), (0, -1.42, 0.92), "Cockpit_Trim", cab, bevel=0.05)
    box("IN_X1_dash_top", (1.1, 0.4, 0.04), (0, -1.42, 1.06), "Cockpit_Tub", cab, bevel=0.015, rot=deg(4, 0, 0))
    box("IN_X1_binnacle", (0.5, 0.22, 0.12), (0, -1.24, 1.07), "Cockpit_Trim", cab, bevel=0.03)
    box("IN_X1_binnacle_hood", (0.54, 0.16, 0.025), (0, -1.2, 1.135), "Cockpit_Trim", cab, bevel=0.01, rot=deg(-8, 0, 0))
    box("IN_X1_cluster", (0.44, 0.008, 0.1), (0, -1.125, 1.06), "Cockpit_Screen", cab, bevel=0, rot=deg(14, 0, 0))
    for i, x in enumerate((-0.13, 0.13)):
        gauge(f"IN_X1_gauge{i}", (x, -1.118, 1.06), deg(-76, 0, 0), 0.04, cab)
    box("IN_X1_needle0", (0.004, 0.004, 0.034), (-0.13, -1.115, 1.072), "EmissiveWhite", cab, bevel=0, rot=deg(14, 30, 0))
    box("IN_X1_needle1", (0.004, 0.004, 0.034), (0.13, -1.115, 1.072), "EmissiveWhite", cab, bevel=0, rot=deg(14, -50, 0))
    box("IN_X1_stack", (0.22, 0.4, 0.3), (0, -1.05, 0.82), "Cockpit_Trim", cab, bevel=0.03, rot=deg(-25, 0, 0))
    box("IN_X1_stack_screen", (0.17, 0.008, 0.13), (0, -0.9, 0.9), "Cockpit_Screen", cab, bevel=0, rot=deg(40, 0, 0))
    box("IN_X1_console", (0.18, 0.6, 0.14), (0, -0.62, 0.8), "Cockpit_Trim", cab, bevel=0.03)
    for i in range(4):
        box(f"IN_X1_switch{i}", (0.03, 0.03, 0.012), (-0.045 + (i % 2) * 0.09, -0.75 + (i // 2) * 0.08, 0.875), "Cockpit_Gauge", cab, bevel=0.004)
    box("IN_X1_gear_lever", (0.03, 0.03, 0.14), (0, -0.5, 0.93), "Gunmetal", cab, bevel=0.01, rot=deg(-12, 0, 0))
    # HUD combiner on the dash
    box("IN_X1_hud", (0.22, 0.006, 0.09), (0, -1.36, 1.15), "Cockpit_HUD", cab, bevel=0, rot=deg(-14, 0, 0))
    torus("IN_X1_hud_reticle", 0.02, 0.0025, (0, -1.355, 1.155), "Cockpit_Gauge", cab, deg(-104, 0, 0), seg=16, ring=4)
    # steering wheel (faces the eye), column, paddles
    wc, wrot = Vector((0, -1.0, 0.9)), deg(-56, 0, 0)
    torus("IN_X1_wheel_rim", 0.14, 0.017, wc, "Cockpit_Trim", cab, wrot, seg=28, ring=6)
    cyl("IN_X1_wheel_hub", 0.045, 0.05, 0.05, wc, "Cockpit_Trim", cab, wrot, segs=12)
    rm = Euler(wrot).to_matrix()
    for i, a in enumerate((90, 0, 270)):
        r = math.radians(a)
        tip = wc + rm @ Vector((math.sin(r) * 0.14, math.cos(r) * 0.14, 0))
        strut(f"IN_X1_wheel_spoke{i}", wc, tip, 0.016, "Cockpit_Trim", cab, w=0.045)
    box("IN_X1_wheel_top", (0.04, 0.012, 0.02), wc + rm @ Vector((0, -0.14, 0.012)), "Cockpit_Gauge", cab, bevel=0, rot=wrot)
    strut("IN_X1_column", wc + rm @ Vector((0, 0, -0.03)), (0, -1.28, 0.86), 0.05, "Cockpit_Trim", cab)
    # canopy frame: A-pillars along the canopy shoulders, windscreen header and base bar (ride with the canopy)
    for k in (1, -1):
        polyline(f"IN_X1_apillar{k}", [(k * 0.6, -1.64, 1.04), (k * 0.53, -1.5, 1.21), (k * 0.6, -0.55, 1.32)], 0.025, "Cockpit_Trim", canopy, w=0.035)
        box(f"IN_X1_sill{k}", (0.1, 1.5, 0.08), (k * 0.6, -0.85, 1.03), "Cockpit_Tub", cab, bevel=0.02)
        box(f"IN_X1_door_card{k}", (0.03, 0.9, 0.22), (k * 0.54, -0.6, 0.9), "Cockpit_Seat", cab, bevel=0.01)
        box(f"IN_X1_door_strip{k}", (0.01, 0.8, 0.012), (k * 0.525, -0.6, 0.98), "Cockpit_Gauge", cab, bevel=0)
    remove("X1_canopy_frame")
    open_bottom(ob("X1_canopy_glass"))
    box("IN_X1_screen_base", (1.2, 0.06, 0.04), (0, -1.64, 1.04), "Cockpit_Trim", canopy, bevel=0.01)


def cockpit_crb1():
    body, steer, root = ob("Body"), ob("Steer"), ob("CRB1_Batcycle")
    remove("B1_screen", "B1_windscreen")
    L.empty("camera_cockpit", (0, -0.12, 1.52), root)  # rider head height, tucked over the tank
    facet("IN_B1_windscreen", [(0.21, -0.76, 1.14), (0.13, -0.58, 1.43), (-0.13, -0.58, 1.43), (-0.21, -0.76, 1.14)], 0.01, "CanopyGlass", body, bevel=0.003)
    for k in (1, -1):
        strut(f"IN_B1_screen_rail{k}", (k * 0.21, -0.765, 1.14), (k * 0.13, -0.585, 1.43), 0.014, "Cockpit_Trim", body, w=0.018)
    # handlebar cluster (turns with the bars): TFT + binnacle + warning lamps
    box("IN_B1_binnacle", (0.28, 0.1, 0.13), (0, -0.62, 1.17), "Cockpit_Trim", steer, bevel=0.03, rot=deg(34, 0, 0))
    box("IN_B1_tft", (0.22, 0.006, 0.1), (0, -0.575, 1.188), "Cockpit_Screen", steer, bevel=0, rot=deg(34, 0, 0))
    gauge("IN_B1_rev", (0.055, -0.572, 1.192), deg(-56, 0, 0), 0.035, steer)
    for i, x in enumerate((-0.11, -0.07, -0.03)):
        box(f"IN_B1_lamp{i}", (0.018, 0.01, 0.012), (x, -0.567, 1.15), "Cockpit_Gauge", steer, bevel=0, rot=deg(34, 0, 0))
    bpy.context.view_layer.update()
    for side, k in (("L", 1), ("R", -1)):
        g = ob(f"grip_{side}").matrix_world.to_translation()
        cyl(f"IN_B1_grip{k}", 0.024, 0.024, 0.13, g + Vector((k * 0.02, 0, 0)), "Rubber", steer, deg(0, 90, 0), segs=12)
        cyl(f"IN_B1_barend{k}", 0.026, 0.02, 0.03, g + Vector((k * 0.1, 0, 0)), "Gunmetal", steer, deg(0, 90, 0), segs=10)
        box(f"IN_B1_switchpod{k}", (0.06, 0.06, 0.05), g + Vector((-k * 0.08, 0, 0.005)), "Cockpit_Trim", steer, bevel=0.012)
        box(f"IN_B1_switch{k}", (0.03, 0.012, 0.012), g + Vector((-k * 0.08, 0.03, 0.02)), "Cockpit_Gauge", steer, bevel=0)
        strut(f"IN_B1_lever{k}", g + Vector((-k * 0.06, -0.04, 0.01)), g + Vector((k * 0.05, -0.08, -0.005)), 0.012, "Gunmetal", steer, w=0.02)
        strut(f"IN_B1_mirror_stalk{k}", g + Vector((-k * 0.1, -0.02, 0.02)), g + Vector((k * 0.0, -0.06, 0.16)), 0.012, "Cockpit_Trim", steer)
        box(f"IN_B1_mirror{k}", (0.1, 0.03, 0.05), g + Vector((k * 0.02, -0.065, 0.18)), "Cockpit_Trim", steer, bevel=0.015)
        box(f"IN_B1_mirror_glass{k}", (0.085, 0.004, 0.038), g + Vector((k * 0.02, -0.048, 0.18)), "Glass", steer, bevel=0)
        cyl(f"IN_B1_reservoir{k}", 0.022, 0.022, 0.03, g + Vector((-k * 0.13, 0.0, 0.035)), "Gunmetal", steer, segs=10)
    box("IN_B1_triple_clamp", (0.46, 0.12, 0.03), (0, -0.66, 1.07), "Gunmetal", steer, bevel=0.01, rot=deg(-25, 0, 0))
    # tank-top nav strip and tank pad the rider looks down onto
    box("IN_B1_tank_nav", (0.12, 0.2, 0.006), (0, -0.28, 1.115), "Cockpit_Screen", body, bevel=0, rot=deg(-6, 0, 0))
    box("IN_B1_tank_pad", (0.24, 0.22, 0.02), (0, -0.02, 1.08), "Cockpit_Seat", body, bevel=0.01, rot=deg(-10, 0, 0))


def cockpit_cra1():
    gear_h = 1.3
    body, canopy = ob("Body"), ob("Canopy")
    remove("A1_seat", "A1_console", "A1_screens", "A1_canopy")
    cut_cockpit(body, (1.24, 2.9, 1.7), (0, -4.95, 3.1), keep_out=("Canopy",))
    # taller bubble so the eye (camera_cockpit 0,-5,3.2) sits inside it; hinge pivot unchanged
    c0 = canopy.matrix_world.to_translation()
    secs = [(0.0, [(0, -.05), (.55, -.05), (.45, .24), (.25, .31), (0, .33)]),
            (1.2, [(0, -.05), (.66, -.05), (.6, .45), (.35, .74), (0, .8)]),
            (2.4, [(0, -.05), (.7, -.05), (.63, .48), (.36, .8), (0, .86)]),
            (3.6, [(0, -.05), (.6, -.05), (.5, .3), (.25, .44), (0, .48)])]
    open_bottom(adopt(L.loft("A1_canopy", secs, "CanopyGlass", None, loc=tuple(c0)), canopy))
    for s, ring in ((0.02, secs[0][1]), (1.2, secs[1][1]), (2.4, secs[2][1])):
        half = [(x, c0.y + s, c0.z + z) for x, z in ring[1:]]
        pts = half[:-1] + [(0, half[-1][1], half[-1][2])] + [(-x, y, z) for x, y, z in reversed(half[:-1])]
        polyline(f"IN_A1_canopy_bow{int(s * 10)}", pts, 0.03, "Cockpit_Trim", canopy, w=0.04)
    for k in (1, -1):
        box(f"IN_A1_canopy_rail{k}", (0.06, 3.6, 0.06), (k * 0.66, c0.y + 1.8, c0.z - 0.04), "Cockpit_Trim", canopy, bevel=0.015)
    # tub: floor, ejection seat, side consoles with throttle, instrument panel + glare shield, HUD, yoke
    box("IN_A1_floor", (1.1, 2.7, 0.05), (0, -4.95, 2.3), "Cockpit_Tub", body, bevel=0.01)
    box("IN_A1_seat_pan", (0.55, 0.55, 0.14), (0, -4.6, 2.45), "Cockpit_Seat", body, bevel=0.04)
    box("IN_A1_seat_back", (0.55, 0.14, 0.85), (0, -4.3, 2.9), "Cockpit_Seat", body, bevel=0.04, rot=deg(-12, 0, 0))
    box("IN_A1_headbox", (0.4, 0.22, 0.28), (0, -4.18, 3.42), "Cockpit_Trim", body, bevel=0.04, rot=deg(-12, 0, 0))
    for k in (1, -1):
        box(f"IN_A1_seat_rail{k}", (0.06, 0.2, 1.1), (k * 0.31, -4.25, 2.85), "Gunmetal", body, bevel=0.015, rot=deg(-12, 0, 0))
        box(f"IN_A1_console{k}", (0.22, 1.5, 0.3), (k * 0.48, -4.95, 2.48), "Cockpit_Trim", body, bevel=0.03)
        box(f"IN_A1_console_screen{k}", (0.16, 0.5, 0.006), (k * 0.48, -5.2, 2.635), "Cockpit_ScreenDim", body, bevel=0)
        for i in range(3):
            box(f"IN_A1_console_sw{k}{i}", (0.04, 0.04, 0.015), (k * 0.48, -4.7 + i * 0.12, 2.64), "Cockpit_Gauge", body, bevel=0.005)
    box("IN_A1_throttle_base", (0.1, 0.25, 0.06), (0.48, -5.05, 2.66), "Gunmetal", body, bevel=0.015)
    strut("IN_A1_throttle", (0.48, -5.05, 2.68), (0.48, -5.15, 2.86), 0.035, "Cockpit_Trim", body)
    box("IN_A1_throttle_grip", (0.06, 0.1, 0.06), (0.48, -5.16, 2.88), "Rubber", body, bevel=0.02)
    box("IN_A1_panel", (1.06, 0.25, 0.45), (0, -6.02, 2.72), "Cockpit_Trim", body, bevel=0.04)
    box("IN_A1_glare", (1.1, 0.42, 0.06), (0, -5.95, 2.97), "Cockpit_Tub", body, bevel=0.02)
    for i, x in enumerate((-0.33, 0.0, 0.33)):
        box(f"IN_A1_mfd{i}", (0.26, 0.04, 0.24), (x, -5.88, 2.74), "Cockpit_Trim", body, bevel=0.012, rot=deg(12, 0, 0))
        box(f"IN_A1_mfd_screen{i}", (0.21, 0.006, 0.19), (x, -5.855, 2.745), "Cockpit_Screen", body, bevel=0, rot=deg(12, 0, 0))
        for j in range(4):
            box(f"IN_A1_mfd_btn{i}{j}", (0.025, 0.01, 0.012), (x - 0.075 + j * 0.05, -5.85, 2.62), "Cockpit_Gauge", body, bevel=0)
    gauge("IN_A1_standby", (0.0, -5.86, 2.93), deg(-78, 0, 0), 0.035, body)
    box("IN_A1_hud_glass", (0.3, 0.006, 0.22), (0, -6.0, 3.11), "Cockpit_HUD", body, bevel=0, rot=deg(-20, 0, 0))
    strut("IN_A1_hud_post_L", (0.14, -5.98, 3.0), (0.14, -6.03, 3.2), 0.015, "Cockpit_Trim", body)
    strut("IN_A1_hud_post_R", (-0.14, -5.98, 3.0), (-0.14, -6.03, 3.2), 0.015, "Cockpit_Trim", body)
    torus("IN_A1_hud_reticle", 0.035, 0.003, (0, -5.995, 3.12), "Cockpit_Gauge", body, deg(-110, 0, 0), seg=16, ring=4)
    box("IN_A1_hud_ladder", (0.002, 0.004, 0.012), (0, -5.995, 3.12), "Cockpit_Gauge", body, bevel=0)
    # yoke
    strut("IN_A1_yoke_column", (0, -5.55, 2.33), (0, -5.42, 2.66), 0.06, "Cockpit_Trim", body)
    box("IN_A1_yoke_bar", (0.34, 0.05, 0.05), (0, -5.42, 2.68), "Cockpit_Trim", body, bevel=0.015)
    for k in (1, -1):
        strut(f"IN_A1_yoke_horn{k}", (k * 0.16, -5.42, 2.68), (k * 0.18, -5.38, 2.84), 0.045, "Rubber", body)
        box(f"IN_A1_yoke_btn{k}", (0.02, 0.02, 0.012), (k * 0.18, -5.38, 2.86), "Cockpit_Gauge", body, bevel=0)
    _ = gear_h


# ======================================================================================
# mode builders
# ======================================================================================
def crx1_pursuit():
    body = ob("Body")
    box("X1_splitter", (2.0, 0.28, 0.035), (0, -3.02, 0.22), "Gunmetal", body, bevel=0.01)
    for i, x in enumerate((-0.6, -0.2, 0.2, 0.6)):
        box(f"X1_diffuser{i}", (0.03, 0.4, 0.16), (x, 2.95, 0.3), "Black", body, bevel=0.005)
    for k in (1, -1):
        box(f"X1_strobe{k}", (0.16, 0.03, 0.035), (k * 0.25, -3.03, 0.62), "EmissiveWhite" if k > 0 else "EmissiveRed", body, bevel=0.005)
    cyl("X1_antenna", 0.008, 0.004, 0.5, (0.55, 2.55, 1.42), "Gunmetal", body, segs=6, bevel=0)
    cyl("X1_antenna_tip", 0.014, 0.014, 0.02, (0.55, 2.55, 1.68), "EmissiveRed", body, segs=6, bevel=0)


def crx1_battle():
    body, turret = ob("Body"), ob("Turret")
    # front ram (V-plough) and bumper horns
    facet_pair("X1_ram", [(0.0, -3.32, 0.2), (0.0, -3.22, 0.62), (1.0, -2.98, 0.58), (1.05, -3.06, 0.2)], 0.05, "Gunmetal", body)
    for k in (1, -1):
        box(f"X1_ram_horn{k}", (0.12, 0.3, 0.14), (k * 0.75, -3.15, 0.42), "CrimsonDark", body, bevel=0.03)
        box(f"X1_ram_glow{k}", (0.5, 0.012, 0.02), (k * 0.45, -3.25, 0.55), "Battle_Glow", body, bevel=0)
    # thick add-on armour: hood slab, doors-lower skirts with bolts, rear-deck plates
    box("X1_hood_armor", (1.2, 1.0, 0.06), (0, -2.3, 0.94), "Gunmetal", body, bevel=0.02, rot=deg(-14, 0, 0))
    for i, x in enumerate((-0.45, 0.45)):
        for j, y in enumerate((-2.65, -1.95)):
            cyl(f"X1_bolt_h{i}{j}", 0.03, 0.03, 0.03, (x, y, 0.98 + (y + 2.3) * -0.25), "Black", body, segs=6, bevel=0)
    for k in (1, -1):
        facet(f"X1_skirt_armor{k}", [(k * 1.36, -1.05, 0.6), (k * 1.36, 1.0, 0.6), (k * 1.4, 1.0, 0.24), (k * 1.4, -1.05, 0.24)][:: k], 0.05, "CrimsonDark", body)
        for i in range(4):
            cyl(f"X1_bolt_s{k}{i}", 0.025, 0.025, 0.03, (k * 1.41, -0.8 + i * 0.5, 0.52), "Gunmetal", body, deg(0, 90, 0), segs=6, bevel=0)
        box(f"X1_skirt_glow{k}", (0.012, 1.9, 0.02), (k * 1.41, 0.0, 0.3), "Battle_Glow", body, bevel=0)
        # weapon pods on the battle panels (swing out with BattlePanel_*)
        flap = ob(f"BattlePanel_{'L' if k > 0 else 'R'}")
        box(f"X1_pod_case{k}", (0.2, 0.75, 0.26), (k * 1.34, 1.0, 0.86), "Gunmetal", flap, bevel=0.03)
        for r in range(2):
            for c in range(3):
                cyl(f"X1_pod_tube{k}{r}{c}", 0.035, 0.035, 0.04, (k * (1.28 + r * 0.11), 0.62, 0.78 + c * 0.08), "Battle_Glow", flap, deg(90, 0, 0), segs=8, bevel=0)
        # hub armour discs (spin with the wheel)
        for n in (("FL", "RL") if k > 0 else ("FR", "RR")):
            w = ob(f"Wheel_{n}")
            p = w.matrix_world.to_translation()
            wd = 0.56 if n[0] == "F" else 0.76
            cyl(f"X1_hub_armor_{n}", 0.3, 0.22, 0.06, p + Vector((k * (wd / 2 + 0.04), 0, 0)), "CrimsonDark", w, deg(0, 90, 0), segs=12)
    # turret upgrade: twin cannon with shroud, muzzle brakes, ammo drum, sensor
    t = turret.matrix_world.to_translation()
    box("X1_turret_shield", (0.8, 0.12, 0.3), t + Vector((0, -0.42, 0.14)), "CrimsonDark", turret, bevel=0.03, rot=deg(-20, 0, 0))
    for k in (1, -1):
        cyl(f"X1_barrel{k}", 0.045, 0.045, 1.0, t + Vector((k * 0.2, -0.75, 0.12)), "Gunmetal", turret, deg(90, 0, 0), segs=10)
        cyl(f"X1_muzzle{k}", 0.07, 0.07, 0.12, t + Vector((k * 0.2, -1.25, 0.12)), "Black", turret, deg(90, 0, 0), segs=10)
        cyl(f"X1_muzzle_glow{k}", 0.04, 0.04, 0.01, t + Vector((k * 0.2, -1.315, 0.12)), "Battle_Glow", turret, deg(90, 0, 0), segs=10, bevel=0)
    cyl("X1_ammo_drum", 0.18, 0.18, 0.25, t + Vector((0, 0.3, 0.18)), "Gunmetal", turret, deg(0, 90, 0), segs=14)
    box("X1_turret_sensor", (0.18, 0.1, 0.08), t + Vector((0, -0.25, 0.32)), "Black", turret, bevel=0.02)
    box("X1_turret_eye", (0.12, 0.01, 0.025), t + Vector((0, -0.305, 0.32)), "Battle_Glow", turret, bevel=0)
    cyl("X1_antenna", 0.008, 0.004, 0.5, (0.55, 2.55, 1.42), "Gunmetal", body, segs=6, bevel=0)
    # rest pose = deployed (CRX1_BattleMode still keys stowed -> deployed)
    for side, k in (("L", 1), ("R", -1)):
        ob(f"BattlePanel_{side}").rotation_euler = deg(0, -k * 55, 0)
    turret.location = (0, 1.4, 1.3)


def crx1_stealth():
    body = ob("Body")
    remove("X1_headlight1", "X1_headlight-1")
    # faceted nose and headlight shutters
    facet_pair("X1_nose_facet", [(0.0, -3.1, 0.5), (0.0, -2.3, 0.97), (0.95, -2.25, 0.85), (0.98, -3.0, 0.46)], 0.04, "Stealth_Facet", body)
    for k in (1, -1):
        box(f"X1_shutter{k}", (0.44, 0.03, 0.06), (k * 0.6, -3.0, 0.55), "Stealth_Facet", body, bevel=0.005, rot=deg(0, 0, -k * 10))
        box(f"X1_shutter_slit{k}", (0.4, 0.035, 0.008), (k * 0.6, -3.0, 0.55), "Stealth_Glow", body, bevel=0, rot=deg(0, 0, -k * 10))
        # flank chines, faceted low skirts (tucked down toward the road), rear-deck facets
        facet(f"X1_chine{k}", [(k * 1.2, -1.15, 1.02), (k * 1.34, -1.0, 0.72), (k * 1.36, 0.7, 0.74), (k * 1.24, 0.8, 1.06)][:: k], 0.035, "Stealth_Facet", body)
        facet(f"X1_low_skirt{k}", [(k * 1.32, -1.1, 0.42), (k * 1.32, 1.05, 0.42), (k * 1.22, 1.05, 0.12), (k * 1.22, -1.1, 0.12)][:: k], 0.035, "Stealth_Facet", body)
        facet(f"X1_deck_facet{k}", [(0, 2.0, 1.27), (0, 2.95, 1.12), (k * 1.0, 2.9, 1.0), (k * 1.1, 2.0, 1.12)][:: k], 0.035, "Stealth_Facet", body)
        # thruster baffles: louvered caps over the exhaust
        p = ob(f"X1_thruster{k}").matrix_world.to_translation()
        cyl(f"X1_baffle{k}", 0.21, 0.21, 0.06, p + Vector((0, 0.2, 0)), "Stealth_Facet", body, deg(90, 0, 0), segs=12)
        for j in range(3):
            box(f"X1_baffle_slat{k}{j}", (0.34, 0.02, 0.025), p + Vector((0, 0.235, -0.1 + j * 0.1)), "Stealth_Gunmetal", body, bevel=0)
        # fins retracted into the deck (tucked aero): flush slot covers instead
        remove(f"X1_fin{k}")
        box(f"X1_fin_slot{k}", (0.07, 0.9, 0.02), (k * 0.75, 2.65, 1.2), "Stealth_Facet", body, bevel=0.005)
    # underglow off, grille closed
    remove("X1_underglow1", "X1_underglow-1")
    swap_materials(L.descendants(ob("CRX1_Interceptor")), STEALTH_SWAP)


def crb1_pursuit():
    body = ob("Body")
    cyl("B1_antenna", 0.006, 0.003, 0.45, (0.1, 1.0, 1.25), "Gunmetal", body, deg(10, 0, 0), segs=6, bevel=0)
    cyl("B1_antenna_tip", 0.012, 0.012, 0.015, (0.1, 1.04, 1.47), "EmissiveRed", body, segs=6, bevel=0)
    for k in (1, -1):
        box(f"B1_strobe{k}", (0.03, 0.08, 0.025), (k * 0.29, -0.75, 0.78), "EmissiveWhite" if k > 0 else "EmissiveRed", body, bevel=0.005)


def crb1_battle():
    body, steer, swing = ob("Body"), ob("Steer"), ob("Swingarm")
    for k in (1, -1):
        facet(f"B1_fairing_armor{k}", [(k * 0.31, -0.9, 0.95), (k * 0.31, -0.25, 0.98), (k * 0.33, -0.2, 0.55), (k * 0.33, -0.75, 0.5)][:: k], 0.03, "Gunmetal", body)
        for i in range(3):
            cyl(f"B1_bolt{k}{i}", 0.015, 0.015, 0.02, (k * 0.335, -0.75 + i * 0.22, 0.88), "Black", body, deg(0, 90, 0), segs=6, bevel=0)
        # forward guns under the fairing
        box(f"B1_gun_body{k}", (0.07, 0.35, 0.08), (k * 0.33, -0.45, 0.42), "Gunmetal", body, bevel=0.015)
        cyl(f"B1_gun_barrel{k}", 0.018, 0.018, 0.45, (k * 0.33, -0.85, 0.42), "Black", body, deg(90, 0, 0), segs=8)
        cyl(f"B1_gun_glow{k}", 0.012, 0.012, 0.01, (k * 0.33, -1.08, 0.42), "Battle_Glow", body, deg(90, 0, 0), segs=8, bevel=0)
        # missile pods over the rear compartments
        box(f"B1_pod{k}", (0.12, 0.36, 0.14), (k * 0.31, 0.55, 0.8), "Gunmetal", body, bevel=0.02)
        for r in range(2):
            for c in range(2):
                cyl(f"B1_pod_tube{k}{r}{c}", 0.022, 0.022, 0.02, (k * (0.28 + r * 0.06), 0.365, 0.77 + c * 0.06), "Battle_Glow", body, deg(90, 0, 0), segs=8, bevel=0)
        # rear wheel armour (on the swingarm)
        p = ob("Wheel_R").matrix_world.to_translation()
        facet(f"B1_wheel_guard{k}", [(k * 0.27, p.y - 0.3, p.z + 0.34), (k * 0.27, p.y + 0.3, p.z + 0.34), (k * 0.27, p.y + 0.38, p.z + 0.02), (k * 0.27, p.y - 0.38, p.z + 0.02)][:: k], 0.025, "CrimsonDark", swing)
        box(f"B1_battle_strip{k}", (0.012, 0.5, 0.015), (k * 0.345, -0.55, 0.62), "Battle_Glow", body, bevel=0)
    # ram blade on the cowl (steers)
    facet_pair("B1_ram", [(0.0, -1.02, 0.85), (0.0, -0.92, 1.05), (0.16, -0.8, 1.0), (0.16, -0.86, 0.8)], 0.025, "Gunmetal", steer)
    crb1_pursuit()


def crb1_stealth():
    body, steer = ob("Body"), ob("Steer")
    remove("B1_headlight")
    box("B1_shutter", (0.17, 0.04, 0.06), (0, -0.8, 1.0), "Stealth_Facet", steer, bevel=0.005, rot=deg(-25, 0, 0))
    box("B1_shutter_slit", (0.15, 0.045, 0.006), (0, -0.8, 1.0), "Stealth_Glow", steer, bevel=0, rot=deg(-25, 0, 0))
    facet_pair("B1_cowl_facet", [(0.0, -0.98, 0.85), (0.0, -0.88, 1.12), (0.18, -0.74, 1.06), (0.18, -0.82, 0.82)], 0.02, "Stealth_Facet", steer)
    for k in (1, -1):
        facet(f"B1_side_facet{k}", [(k * 0.3, -0.85, 0.9), (k * 0.3, 0.2, 0.9), (k * 0.34, 0.25, 0.55), (k * 0.33, -0.7, 0.5)][:: k], 0.02, "Stealth_Facet", body)
        facet(f"B1_low_skirt{k}", [(k * 0.31, -0.6, 0.42), (k * 0.31, 0.35, 0.42), (k * 0.26, 0.35, 0.2), (k * 0.26, -0.55, 0.2)][:: k], 0.02, "Stealth_Facet", body)
        cyl(f"B1_baffle{k}", 0.155, 0.155, 0.02, (k * 0.17, 0, 0.42), "Stealth_Facet", body, deg(0, 90, 0), segs=16)
    swap_materials(L.descendants(ob("CRB1_Batcycle")), STEALTH_SWAP)


def cra1_flight():
    body = ob("Body")
    cyl("A1_pitot", 0.02, 0.01, 1.0, (0, -9.6, 2.22), "Gunmetal", body, deg(90, 0, 0), segs=6, bevel=0)
    box("A1_antenna_blade", (0.03, 0.35, 0.22), (0, -1.5, 3.1), "Gunmetal", body, bevel=0.005, rot=deg(20, 0, 0))
    for k in (1, -1):
        box(f"A1_formation{k}", (0.04, 1.2, 0.03), (k * 1.9, 0.5, 2.25), "EmissiveRed", body, bevel=0)


def cra1_vtol():
    cra1_flight()
    body = ob("Body")
    for side, k in (("L", 1), ("R", -1)):
        v = ob(f"VTOL_{side}")
        p = v.matrix_world.to_translation()
        # intake doors on the wing top swing open over each nacelle
        # big intake doors stand open above each lift fan (clamshell), vanes + exhaust glow below
        for j, dx in enumerate((-0.8, 0.8)):
            hinge = p + Vector((dx, 0, 0.3))
            facet(f"A1_vtol_door_{side}{j}", [hinge + Vector((0, -1.0, 0)), hinge + Vector((0, 1.0, 0)),
                                             hinge + Vector((dx * 0.35, 0.9, 1.0)), hinge + Vector((dx * 0.35, -0.9, 1.0))][:: (1 if dx > 0 else -1)], 0.05, "CrimsonDark", body)
            strut(f"A1_vtol_door_strut_{side}{j}", hinge + Vector((0, 0, -0.02)), hinge + Vector((dx * 0.2, 0, 0.6)), 0.06, "Gunmetal", body)
        for j in range(4):
            box(f"A1_vtol_vane_{side}{j}", (1.3, 0.06, 0.35), p + Vector((0, -0.45 + j * 0.3, -0.55)), "Gunmetal", body, bevel=0.01, rot=deg(-15, 0, 0))
        cyl(f"A1_vtol_glow_{side}", 0.6, 0.6, 0.02, p + Vector((0, 0, -0.42)), "Battle_Glow", body, segs=20, bevel=0)
        v.rotation_euler = deg(-90, 0, 0)  # rest = rotated down (CRA1_VTOLTransition keys 0 -> -90)


def cra1_stealth():
    body = ob("Body")
    gear_h = 1.3
    remove("A1_navlight_L", "A1_navlight_R")
    for side, k in (("L", 1), ("R", -1)):
        # sawtooth spikes folded down flat (tucked aero)
        sp = ob(f"A1_spike_{side}")
        sp.rotation_euler = deg(0, -k * 65, 0)
        # flattened, serrated exhaust shroud over each engine
        p = ob(f"A1_engine_{side}").matrix_world.to_translation()
        box(f"A1_shroud_{side}", (1.6, 1.6, 0.7), p + Vector((0, 1.3, 0)), "Stealth_Facet", body, bevel=0.03, taper_top=(0.9, 0.95))
        for j in range(4):
            x = p.x - 0.6 + j * 0.4
            facet(f"A1_serration_{side}{j}", [(x - 0.2, p.y + 2.1, p.z + 0.12), (x + 0.2, p.y + 2.1, p.z + 0.12), (x, p.y + 2.45, p.z + 0.12)], 0.08, "Stealth_Facet", body)
        box(f"A1_exhaust_slit_{side}", (1.2, 0.03, 0.06), p + Vector((0, 2.11, -0.05)), "Stealth_Glow", body, bevel=0)
        # fuselage chines
        facet(f"A1_chine_{side}", [(k * 1.6, -6.0, gear_h + 0.8), (k * 2.1, -1.0, gear_h + 0.95), (k * 1.9, 3.5, gear_h + 1.55), (k * 1.0, -4.0, gear_h + 1.2)][:: k], 0.06, "Stealth_Facet", body)
        # flush covers over the VTOL fans (ride with the nacelle)
        v = ob(f"VTOL_{side}")
        q = v.matrix_world.to_translation()
        cyl(f"A1_vtol_cover_{side}", 0.67, 0.67, 0.04, q + Vector((0, 0.27, 0)), "Stealth_Facet", v, deg(90, 0, 0), segs=12)
        cyl(f"A1_vtol_cover_b_{side}", 0.67, 0.67, 0.04, q + Vector((0, -0.27, 0)), "Stealth_Facet", v, deg(90, 0, 0), segs=12)
    swap_materials(L.descendants(ob("CRA1_Specter")), STEALTH_SWAP)


# ======================================================================================
# realism pass: additive mechanical detail on the existing models (ck_vehicle_kit)
# ======================================================================================
def wheel_detail(n, x, w, r):
    """Lug nuts, centre cap, sidewall ribs and a valve on an existing wheel (spins with Wheel_<n>)."""
    wp = ob(f"Wheel_{n}")
    c = wp.matrix_world.to_translation()
    side = 1 if x > 0 else -1
    face = side * w * 0.54
    K.lathe(f"{n}_cap", [(0, side * 0.03), (r * 0.1, side * 0.026), (r * 0.15, side * 0.01), (r * 0.15, 0)], "Accent", wp, c + Vector((face, 0, 0)), segs=20, axis="X")
    for i in range(6):
        a = 2 * math.pi * i / 6
        p = c + Vector((face, math.cos(a) * r * 0.25, math.sin(a) * r * 0.25))
        K.lathe(f"{n}_lug{i}", [(0, side * 0.025), (0.016, side * 0.025), (0.019, side * 0.012), (0.019, 0)], "Iron", wp, p, segs=6, axis="X", smooth_angle=20)
    tyre_ribs(n, wp, c, r, w)
    K.lathe(f"{n}_valve", [(0, side * 0.03), (0.006, side * 0.03), (0.008, 0)], "Alloy", wp, c + Vector((side * w * 0.5, 0, r * 0.7)), segs=6, axis="X")


def tyre_ribs(n, wp, c, r, w):
    for s in (1, -1):
        K.lathe(f"{n}_rib{s}", [(r * 0.84, s * w * 0.5), (r * 0.86, s * (w * 0.5 + 0.006)), (r * 0.9, s * (w * 0.5 + 0.006)), (r * 0.92, s * w * 0.5)],
                "Rubber", wp, c, segs=40, axis="X")


def detail_crx1(mode):
    body = ob("Body")
    for n, x, r, w in (("FL", 1.5, 0.6, 0.56), ("FR", -1.5, 0.6, 0.56), ("RL", 1.6, 0.76, 0.76), ("RR", -1.6, 0.76, 0.76)):
        wheel_detail(n, x, w, r)
    for k in (1, -1):
        if mode != "stealth":  # projector headlamps in a recessed housing (stealth shutters them)
            K.rbox(f"X1_lamp_housing{k}", (0.5, 0.05, 0.15), (k * 0.6, -2.985, 0.49), "Carbon", body, r=0.02)
            for j, dx in enumerate((0.45, 0.6, 0.75)):
                K.lamp_projector(f"X1_proj{k}{j}", body, (k * dx, -3.0, 0.48), 0.042)
        K.rbox(f"X1_tail_housing{k}", (0.56, 0.04, 0.1), (k * 0.6, 3.0, 0.82), "Carbon", body, r=0.015)
        K.rbox(f"X1_tail_lens{k}", (0.54, 0.02, 0.08), (k * 0.6, 3.035, 0.82), "LensRed", body, r=0.01)
        # thruster: nozzle petals, liner and flame-holder
        c = Vector((k * 0.45, 3.05, 0.55))
        for i in range(12):
            a = 2 * math.pi * (i + 0.5) / 12
            K.strut(f"X1_petal{k}{i}", c + Vector((math.cos(a) * 0.178, 0.16, math.sin(a) * 0.178)),
                    c + Vector((math.cos(a) * 0.158, 0.31, math.sin(a) * 0.158)), 0.085, 0.01, "Iron", body)
        K.lathe(f"X1_liner{k}", [(0.168, 0.15), (0.168, 0.2), (0.13, 0.205)], "Iron", body, c, segs=24, axis="Y")
        K.tube(f"X1_flameholder{k}", [c + Vector((math.cos(a) * 0.08, 0.205, math.sin(a) * 0.08)) for a in np.linspace(0, 2 * math.pi, 17)], 0.008, "Iron", body, segs=5, cap=False)
        for i in range(6):
            a = 2 * math.pi * i / 6
            K.strut(f"X1_holder_spoke{k}{i}", c + Vector((0, 0.205, 0)), c + Vector((math.cos(a) * 0.15, 0.205, math.sin(a) * 0.15)), 0.012, 0.01, "Iron", body)
        # bolts round the wheel-arch armour (outer faces)
        for j, (yy, zz) in enumerate(((-2.5, 1.05), (-2.25, 1.18), (-1.95, 1.23), (-1.6, 1.18), (-1.3, 1.1))):
            K.bolts(f"X1_archbolt_F{k}{j}", [(k * 1.815, yy, zz)], deg(0, k * 90, 0), 0.018, "Alloy", body)
        for j, (yy, zz) in enumerate(((1.0, 1.2), (1.4, 1.42), (1.85, 1.49), (2.3, 1.44), (2.7, 1.3))):
            K.bolts(f"X1_archbolt_R{k}{j}", [(k * 2.005, yy, zz)], deg(0, k * 90, 0), 0.02, "Alloy", body)
        K.rbox(f"X1_rail{k}", (0.1, 3.4, 0.08), (k * 0.65, 0.0, 0.15), "Carbon", body, r=0.015)
        K.lathe(f"X1_towhook{k}", [(0.03, -0.012), (0.042, -0.012), (0.042, 0.012), (0.03, 0.012)], "Accent", body, (k * 0.35, -3.06, 0.32), (0, 0, 0), segs=16, axis="X")
        d = ob(f"Door_{'L' if k > 0 else 'R'}")
        M = d.matrix_world @ Matrix.Translation((k * 0.66, 0, -0.38)) @ Euler(deg(0, -k * 18, 0)).to_matrix().to_4x4()
        K.rbox(f"X1_door_handle{k}", (0.02, 0.2, 0.04), M @ Vector((k * 0.045, -0.35, 0.12)), "Carbon", d, r=0.008, rot=deg(0, -k * 18, 0))
    # armour plate fasteners
    for i, (yy, wd, zz, tilt) in enumerate(((-1.5, 1.7, 0.98, -10), (-0.6, 1.9, 1.08, 4), (0.5, 2.0, 1.12, -4), (1.4, 2.1, 1.14, 6), (2.3, 1.8, 1.1, -8))):
        M = Matrix.Translation((0, yy, zz)) @ Euler(deg(tilt, 0, 0)).to_matrix().to_4x4()
        pts = [M @ Vector((sx * (wd / 2 - 0.07), sy * 0.3, 0.036)) for sx in (1, -1) for sy in (1, -1)]
        K.bolts(f"X1_platebolt{i}", pts, deg(tilt, 0, 0), 0.016, "Alloy", body, h=0.01)
    # hood vent louvres
    M = Matrix.Translation((0, -2.0, 0.88)) @ Euler(deg(-14, 0, 0)).to_matrix().to_4x4()
    for i in range(7):
        K.rbox(f"X1_louvre{i}", (0.46, 0.022, 0.03), M @ Vector((0, -0.26 + i * 0.087, 0.02)), "Carbon", body, r=0.004, segs=1, rot=deg(-14 + 35, 0, 0))
    L.text_mesh("X1_badge", "CR-X1", 0.06, (0, 3.04, 0.95), "Alloy", body, deg(90, 0, 180), extrude=0.004)


def detail_crb1(mode):
    body, steer, swing, mount = ob("Body"), ob("Steer"), ob("Swingarm"), ob("FrontWheel_mount")
    bpy.context.view_layer.update()
    wf, wr = ob("Wheel_F"), ob("Wheel_R")
    cf, cr = wf.matrix_world.to_translation(), wr.matrix_world.to_translation()
    tyre_ribs("B1_F", wf, cf, 0.43, 0.32)
    tyre_ribs("B1_R", wr, cr, 0.46, 0.44)
    # brakes: twin front discs between hub and fork legs, radial calipers on the legs; single rear disc
    for s in (1, -1):
        dc = cf + Vector((s * 0.175, 0, 0))
        K.lathe(f"B1_disc_F{s}", [(0.11, -0.004), (0.2, -0.004), (0.2, 0.004), (0.11, 0.004)], "Iron", wf, dc, segs=36, axis="X")
        K.lathe(f"B1_carrier_F{s}", [(0.05, -0.006), (0.11, -0.003), (0.11, 0.003), (0.05, 0.006)], "Alloy", wf, dc, segs=12, axis="X")
        cp = cf + Vector((s * 0.19, 0.13, 0.1))
        K.rbox(f"B1_caliper_F{s}", (0.05, 0.08, 0.14), cp, "Accent", mount, r=0.015, rot=deg(-40, 0, 0))
        M = steer.matrix_world
        K.tube(f"B1_hose_F{s}", K.bent(M @ Vector((s * 0.12, 0.05, 0.12)), M @ Vector((s * 0.25, -0.1, -0.2)), cp + Vector((0, 0.02, 0.07)), 10),
               0.006, "Carbon", steer, segs=5)
        # fork: lower legs, dust seals, top caps (in the steer frame)
        K.tube(f"B1_fork_lower{s}", [M @ Vector((s * 0.2, 0, -0.45)), M @ Vector((s * 0.2, 0, -0.8))], 0.052, "Carbon", steer, segs=12)
        K.tube(f"B1_fork_seal{s}", [M @ Vector((s * 0.2, 0, -0.43)), M @ Vector((s * 0.2, 0, -0.46))], 0.056, "Rubber", steer, segs=12)
        K.tube(f"B1_fork_cap{s}", [M @ Vector((s * 0.2, 0, 0.0)), M @ Vector((s * 0.2, 0, 0.03))], 0.045, "Alloy", steer, segs=10)
    dr = cr + Vector((-0.235, 0, 0))
    K.lathe("B1_disc_R", [(0.1, -0.004), (0.17, -0.004), (0.17, 0.004), (0.1, 0.004)], "Iron", wr, dr, segs=32, axis="X")
    K.rbox("B1_caliper_R", (0.05, 0.13, 0.07), dr + Vector((-0.02, 0.05, -0.15)), "Accent", swing, r=0.015)
    # belt final drive (left side) and pulleys
    pf = Vector((0.2, 0.12, 0.42))
    pr = cr + Vector((0.245, 0, 0))
    K.lathe("B1_pulley_F", [(0, -0.02), (0.065, -0.02), (0.065, 0.02), (0, 0.02)], "Alloy", body, pf, segs=20, axis="X")
    K.lathe("B1_pulley_R", [(0.06, -0.018), (0.15, -0.018), (0.15, 0.018), (0.06, 0.018)], "Alloy", wr, pr, segs=32, axis="X")
    K.strut("B1_belt_top", pf + Vector((0.005, 0, 0.065)), pr + Vector((0, 0, 0.15)), 0.035, 0.012, "Carbon", swing)
    K.strut("B1_belt_bot", pf + Vector((0.005, 0, -0.065)), pr + Vector((0, 0, -0.15)), 0.035, 0.012, "Carbon", swing)
    # rear mono-shock (coil-over) under the seat
    a, b = Vector((0, 0.62, 0.52)), Vector((0, 0.38, 0.84))
    K.helix("B1_spring", a + (b - a) * 0.12, a + (b - a) * 0.8, 0.045, 0.009, 7, "Accent", body)
    K.tube("B1_damper", [a, b], 0.022, "Alloy", body, segs=10)
    K.tube("B1_reservoir", [b + Vector((0.06, 0.02, -0.02)), b + Vector((0.06, 0.12, -0.12))], 0.02, "Alloy", body, segs=10)
    # exhausts (one each side) ending under the tail
    for s in (1, -1):
        pts = K.bent((s * 0.12, -0.12, 0.3), (s * 0.24, 0.45, 0.34), (s * 0.17, 0.96, 0.74), 12)
        K.tube(f"B1_header{s}", pts, 0.032, "Iron", body, segs=10, cap=False)
        K.lathe(f"B1_tip{s}", [(0.025, 0.0), (0.045, 0.0), (0.05, 0.1), (0.04, 0.1)], "Alloy", body, pts[-1], deg(-35, 0, 0), segs=16, axis="Y")
        # rider pegs + levers
        K.strut(f"B1_peg{s}", (s * 0.2, 0.3, 0.46), (s * 0.31, 0.3, 0.46), 0.03, 0.03, "Alloy", body)
        K.rbox(f"B1_peg_pad{s}", (0.08, 0.04, 0.02), (s * 0.29, 0.3, 0.485), "Rubber", body, r=0.006)
        K.strut(f"B1_lever{s}", (s * 0.27, 0.32, 0.47), (s * 0.27, 0.08, 0.5), 0.012, 0.02, "Alloy", body)
        K.bolts(f"B1_fairbolt{s}", [(s * 0.278, yy, 0.9) for yy in (-0.7, -0.3, 0.1)], deg(0, s * 90, 0), 0.012, "Alloy", body, h=0.008)
    # radiator behind the front wheel
    K.rbox("B1_radiator", (0.28, 0.05, 0.24), (0, -0.48, 0.58), "Carbon", body, r=0.01)
    for i in range(8):
        K.rbox(f"B1_rad_fin{i}", (0.26, 0.012, 0.006), (0, -0.508, 0.48 + i * 0.028), "Alloy", body, r=0.0, segs=1)
    K.rbox("B1_tail_lens", (0.16, 0.02, 0.04), (0, 1.12, 0.98), "LensRed", body, r=0.008)
    if mode != "stealth":
        M = steer.matrix_world
        face = (M.to_3x3() @ Vector((0, -1, 0))).normalized()
        for s in (1, -1):
            K.lamp_projector(f"B1_proj{s}", steer, M @ Vector((s * 0.055, -0.16, -0.06)), 0.032, tuple(face))
    # rear hugger over the tyre (moves with the swingarm)
    K.lathe("B1_hugger", [(0.52, -0.11), (0.52, 0.11), (0.535, 0.11), (0.535, -0.11)], "Carbon", swing, cr, segs=16, axis="X",
            arc=(math.radians(95), math.radians(165)))


def detail_cra1(mode):
    body = ob("Body")
    gear_h = 1.3
    for name, r in (("Gear_Nose", 0.3), ("Gear_L", 0.42), ("Gear_R", 0.42)):
        g = ob(name)
        p = g.matrix_world.to_translation()
        axle = p + Vector((0, 0, -(gear_h - r) - 0.1))
        K.tube(f"{name}_oleo", [axle + Vector((0, 0, 0.05)), axle + Vector((0, 0, 0.55))], 0.055, "Chrome", g, segs=12)
        K.tube(f"{name}_collar", [axle + Vector((0, 0, 0.55)), axle + Vector((0, 0, 0.62))], 0.09, "Alloy", g, segs=12)
        K.strut(f"{name}_torque_a", axle + Vector((0, -0.05, 0.08)), axle + Vector((0, -0.2, 0.32)), 0.04, 0.03, "Alloy", g)
        K.strut(f"{name}_torque_b", axle + Vector((0, -0.2, 0.32)), axle + Vector((0, -0.05, 0.6)), 0.04, 0.03, "Alloy", g)
        for s in (1, -1):
            K.lathe(f"{name}_hub{s}", [(0, s * 0.17), (r * 0.35, s * 0.165), (r * 0.6, s * 0.15), (r * 0.62, s * 0.13)], "Alloy", g, axle, segs=20, axis="X")
            # gear-well doors hang open beside the bay (retract with the leg)
            K.rbox(f"{name}_door{s}", (0.02, 0.9 if name != "Gear_Nose" else 0.6, 0.45), p + Vector((s * 0.32, 0, -0.25)), "Crimson", g, r=0.008)
        K.rbox(f"{name}_well", (0.5, 1.0 if name != "Gear_Nose" else 0.7, 0.03), p, "Carbon", body, r=0.01)
        if mode != "stealth" and name == "Gear_Nose":
            K.lamp_projector("A1_taxi_lamp", g, axle + Vector((0, -0.12, 0.7)), 0.05)
    for k, side in ((1, "L"), (-1, "R")):
        if mode != "stealth":  # nozzle petals + flame-holder (stealth shrouds the nozzles)
            c = Vector((k * 1.35, 7.6, gear_h + 0.95))
            for i in range(16):
                a = 2 * math.pi * (i + 0.5) / 16
                K.strut(f"A1_petal_{side}{i}", c + Vector((math.cos(a) * 0.56, 1.7, math.sin(a) * 0.56)),
                        c + Vector((math.cos(a) * 0.5, 2.25, math.sin(a) * 0.5)), 0.22, 0.02, "Iron", body)
            K.lathe(f"A1_liner_{side}", [(0.54, 1.7), (0.54, 1.85), (0.42, 1.86)], "Iron", body, c, segs=28, axis="Y")
            K.tube(f"A1_holder_{side}", [c + Vector((math.cos(a) * 0.25, 1.85, math.sin(a) * 0.25)) for a in np.linspace(0, 2 * math.pi, 19)], 0.02, "Iron", body, segs=5, cap=False)
            K.lathe(f"A1_nav_dome_{side}", [(0.0, 0.1), (0.07, 0.07), (0.1, 0.0)], "LensClear", body, (k * 14.35, 7.6, gear_h + 0.8), deg(0, 0, -90 * k), segs=12, axis="Y")
        # access panels, fuel caps and vortex generators on the wing top (aligned with the sweep)
        sweep = math.radians(-k * 36)
        for j, (x, y, wd, ln) in enumerate(((4.0, 2.0, 1.1, 0.7), (6.6, 3.8, 0.9, 0.6), (3.4, 0.6, 0.6, 0.5), (8.8, 5.1, 0.7, 0.4))):
            M = Matrix.Translation((k * x, y, gear_h + 1.255)) @ Euler((0, 0, sweep)).to_matrix().to_4x4()
            quad = [M @ Vector(v) for v in ((-wd / 2, -ln / 2, 0), (wd / 2, -ln / 2, 0), (wd / 2, ln / 2, 0), (-wd / 2, ln / 2, 0))]
            K.slab(f"A1_access_{side}{j}", quad, 0.006, "CrimsonDark", body, r=0.003, segs=1)
            K.bolts(f"A1_panelbolt_{side}{j}", [M @ Vector((sx * (wd / 2 - 0.05), sy * (ln / 2 - 0.05), 0.002)) for sx in (1, -1) for sy in (1, -1)], (0, 0, 0), 0.012, "Alloy", body, h=0.006)
        K.lathe(f"A1_fuelcap_{side}", [(0, 0.012), (0.08, 0.01), (0.1, 0)], "Alloy", body, (k * 5.3, 1.5, gear_h + 1.252), segs=16, axis="Z")
        for j in range(6):
            x = 3.0 + j * 1.25
            y = -1.6 + (x - 2.0) * (7.2 / 9.5) + 0.35
            K.slab(f"A1_vg_{side}{j}", [(k * x, y, gear_h + 1.25), (k * x, y + 0.22, gear_h + 1.25), (k * x, y + 0.22, gear_h + 1.32)], 0.01, "Alloy", body, r=0.002, segs=1)
        # hinge-actuator fairings under the trailing edge
        for j, x in enumerate((3.5, 6.5, 9.5)):
            K.rbox(f"A1_canoe_{side}{j}", (0.22, 1.2, 0.16), (k * x, 6.4 - (x - 3.5) * 0.03, gear_h + 0.42), "CrimsonDark", body, r=0.06, taper=(0.7, 1.0))
    # weapons-bay doors and blade antennas under the fuselage
    for s in (1, -1):
        quad = [(0.0, -1.0, gear_h + 0.14), (s * 0.75, -1.0, gear_h + 0.16), (s * 0.75, 3.0, gear_h + 0.14), (0.0, 3.0, gear_h + 0.13)]
        K.slab(f"A1_bay_door{s}", quad[::s], 0.012, "CrimsonDark", body, r=0.004, segs=1)
    for j, y in enumerate((-3.5, 4.0)):
        K.slab(f"A1_blade_ant{j}", [(0, y, gear_h + 0.2), (0, y + 0.35, gear_h + 0.2), (0, y + 0.3, gear_h - 0.05), (0, y + 0.18, gear_h - 0.05)], 0.02, "Gunmetal", body, r=0.004, segs=1)


# ======================================================================================
# CR-X1 bike launch bay: the nose splits into two clamshell petals (cut from the existing nose
# pieces), a lit open-top bay with a launch sled, and the CRX1_BikeEject clip. The game parents the
# CR-B1 to bike_launch_anchor (on the sled) during the clip and releases it at bike_launch_exit.
# ======================================================================================
BAY_LO, BAY_HI = Vector((-0.9, -3.45, 0.22)), Vector((0.9, -1.66, 1.25))
EJECT_CLIP = "CRX1_BikeEject"


def _to_world_mesh(o):
    o.data.transform(o.matrix_world)
    o.parent = None
    o.matrix_world = Matrix.Identity(4)


def _bisect(o, keep_positive):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, 0), plane_no=(1, 0, 0), clear_inner=keep_positive, clear_outer=not keep_positive)
    boundary = [e for e in bm.edges if e.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
    bm.to_mesh(o.data)
    bm.free()


def _bool(o, cutter, op):
    m = o.modifiers.new("bay", "BOOLEAN")
    m.operation, m.object = op, cutter
    for attr, val in (("solver", "EXACT"), ("material_mode", "TRANSFER")):
        try:
            setattr(m, attr, val)
        except (TypeError, AttributeError):
            pass
    K.apply_mods(o)


def bike_bay_crx1(mode):
    root, body = ob("CRX1_Interceptor"), ob("Body")
    doors = {1: L.empty("BayDoor_L", (0.9, -2.55, 1.0), body), -1: L.empty("BayDoor_R", (-0.9, -2.55, 1.0), body)}
    bpy.context.view_layer.update()
    skip = set()
    for n in ("Canopy", "Door_L", "Door_R", "Cockpit", "BattlePanel_L", "BattlePanel_R", "Turret", "BayDoor_L", "BayDoor_R"):
        skip |= subtree(n)
    dims = BAY_HI - BAY_LO
    cutter = L.box("_bay_cutter", tuple(dims), tuple((BAY_LO + BAY_HI) / 2), "Black", None, bevel=0)
    bpy.context.view_layer.update()
    eps = 0.002
    for o in list(L.descendants(body)):
        if o.type != "MESH" or o in skip or o.name.startswith("IN_") or o.name.endswith("_COL") or o is cutter:
            continue
        pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
        lo, hi = Vector(map(min, *pts)), Vector(map(max, *pts))
        if any(hi[i] < BAY_LO[i] or lo[i] > BAY_HI[i] for i in range(3)):
            continue
        inside = all(lo[i] >= BAY_LO[i] - eps and hi[i] <= BAY_HI[i] + eps for i in range(3))
        if inside:
            part = o
        else:
            part = o.copy()
            part.data = o.data.copy()
            part.name = o.name + "_bay"
            bpy.context.scene.collection.objects.link(part)
            _bool(part, cutter, "INTERSECT")
            _bool(o, cutter, "DIFFERENCE")
            if not part.data.polygons:
                bpy.data.objects.remove(part, do_unlink=True)
                continue
        _to_world_mesh(part)
        xs = [v.co.x for v in part.data.vertices]
        if min(xs) >= -0.005:
            adopt(part, doors[1])
        elif max(xs) <= 0.005:
            adopt(part, doors[-1])
        else:
            other = part.copy()
            other.data = part.data.copy()
            other.name = part.name + "_R"
            bpy.context.scene.collection.objects.link(other)
            _bisect(part, True)
            _bisect(other, False)
            adopt(part, doors[1])
            adopt(other, doors[-1])
    bpy.data.objects.remove(cutter, do_unlink=True)
    # bay furniture: rails, guide lights, catapult block, launch sled + anchors
    for s in (1, -1):
        K.rbox(f"X1_bay_rail{s}", (0.05, 1.2, 0.035), (s * 0.2, -2.35, 0.24), "Alloy", body, r=0.008)
        K.rbox(f"X1_bay_light{s}", (0.015, 1.2, 0.012), (s * 0.84, -2.35, 0.235), "EmissiveRed", body, r=0.0, segs=1)
        K.tube(f"X1_bay_ram{s}", [(s * 0.14, -1.7, 0.45), (s * 0.14, -2.05, 0.45)], 0.03, "Alloy", body, segs=10)
    K.rbox("X1_bay_catapult", (0.42, 0.12, 0.34), (0, -1.73, 0.42), "Gunmetal", body, r=0.02)
    sled = L.empty("BikeSled", (0, -2.4, 0.24), body)
    bpy.context.view_layer.update()
    K.rbox("X1_sled_deck", (0.34, 1.25, 0.04), (0, -2.35, 0.275), "Gunmetal", sled, r=0.01)
    K.rbox("X1_sled_chock", (0.2, 0.12, 0.12), (0, -2.9, 0.33), "Alloy", sled, r=0.02, rot=deg(-30, 0, 0))
    for s in (1, -1):
        K.strut(f"X1_sled_clamp{s}", (s * 0.15, -1.6, 0.3), (s * 0.08, -1.55, 0.6), 0.03, 0.03, "Alloy", sled)
        K.rbox(f"X1_sled_glow{s}", (0.012, 1.2, 0.01), (s * 0.165, -2.35, 0.297), "EmissiveRed", sled, r=0.0, segs=1)
    L.empty("bike_launch_anchor", (0, -2.4, 0.3), sled)
    L.empty("bike_launch_exit", (0, -5.4, 0.0), root)
    # clip: petals open (0-18), sled holds, then runs out and drops onto the road (18-46)
    for k, d in doors.items():
        L.clip(d, EJECT_CLIP, [(0, (0, 0, 0)), (18, deg(0, k * 125, 0)), (46, deg(0, k * 125, 0))])
    L.clip(sled, EJECT_CLIP, [(0, (0, -2.4, 0.24)), (18, (0, -2.4, 0.24)), (34, (0, -3.7, 0.24)), (46, (0, -4.9, 0.0))], path="location")
    if mode == "stealth":
        swap_materials(L.descendants(root), STEALTH_SWAP)


def pose_eject(sled_y=-2.4):
    """Render-only pose: petals open, sled at sled_y."""
    for k, n in ((1, "BayDoor_L"), (-1, "BayDoor_R")):
        ob(n).rotation_euler = deg(0, k * 125, 0)
    ob("BikeSled").location = (0, sled_y, 0.24)


VEHICLES = {
    "crx1": dict(key="crx1_interceptor", file="CRX1_interceptor", build=V.build_crx1, cockpit=cockpit_crx1, detail=detail_crx1, extra=bike_bay_crx1, root="CRX1_Interceptor",
                 modes={"pursuit": crx1_pursuit, "battle": crx1_battle, "stealth": crx1_stealth}, pitch=-5),
    "crb1": dict(key="crb1_batcycle", file="CRB1_batcycle", build=V.build_crb1, cockpit=cockpit_crb1, detail=detail_crb1, extra=None, root="CRB1_Batcycle",
                 modes={"pursuit": crb1_pursuit, "battle": crb1_battle, "stealth": crb1_stealth}, pitch=-20),
    "cra1": dict(key="cra1_specter", file="CRA1_specter", build=V.build_cra1, cockpit=cockpit_cra1, detail=detail_cra1, extra=None, root="CRA1_Specter",
                 modes={"flight": cra1_flight, "vtol": cra1_vtol, "stealth": cra1_stealth}, pitch=-14),
}

PALETTE = {"battle": "battle", "stealth": "stealth"}  # every other mode: standard
MODE_NOTES = {
    "pursuit": "baseline look, polished: splitter/diffuser or antenna, strobes; cockpit",
    "battle": "armour plates, weapon pods; battle pivots posed deployed at rest; clip names unchanged",
    "stealth": "matte radar-absorbent materials (Stealth_*), emissives faint red, faceted panels, tucked aero, lights/antennas retracted",
    "flight": "baseline look, polished: pitot, antenna blade, formation lights; cockpit",
    "vtol": "VTOL_L/R posed rotated down at rest (-90 deg X), intake doors open, fan rings lit",
}
REST_POSE = {
    ("crx1", "battle"): {"BattlePanel_L": "rotation_euler (0,-55,0) deg", "BattlePanel_R": "rotation_euler (0,55,0) deg", "Turret": "location z 1.3 (Blender Z-up)"},
    ("cra1", "vtol"): {"VTOL_L": "rotation_euler (-90,0,0) deg", "VTOL_R": "rotation_euler (-90,0,0) deg"},
}


# ======================================================================================
# build / export / render
# ======================================================================================
def build_variant(vid, mode):
    v = VEHICLES[vid]
    L.reset()
    ensure_mats()
    root = v["build"]()
    bpy.context.view_layer.update()
    v["cockpit"]()
    bpy.context.view_layer.update()
    v["detail"](mode)
    bpy.context.view_layer.update()
    v["modes"][mode]()
    bpy.context.view_layer.update()
    if v["extra"]:
        v["extra"](mode)
    for o in L.descendants(root):
        if o.type == "MESH" and o.data.materials and base_mat(o.data.materials[0]).startswith("Cockpit_Screen"):
            K.fit_uv(o)
    root["ck_vehicle"] = v["key"]
    root["ck_mode"] = mode
    bpy.context.view_layer.update()
    if BAKE:
        K.bake_vehicle(root, f"{v['file']}_{mode}", PALETTE.get(mode, "standard"), TEX, log=lambda *a: print("[modes]", *a, flush=True))
    return root


def export_variant(vid, mode, root, baseline):
    v = VEHICLES[vid]
    objs = L.descendants(root)
    pivots = sorted(o.name for o in objs if o.type == "EMPTY")
    clips = sorted({t.name for o in objs if o.animation_data for t in o.animation_data.nla_tracks})
    missing = [p for p in baseline["pivots"] if p not in pivots]
    assert not missing, f"{vid}/{mode} lost pivots {missing}"
    assert set(baseline["clips"]) <= set(clips), f"{vid}/{mode} lost clips {set(baseline['clips']) - set(clips)}"
    base = f"{v['file']}_{mode}"
    K.export(os.path.join(OUT, base + ".glb"), objs, True)
    lod = L.static_lod([o for o in objs if not o.name.startswith("IN_")], 0.25, base + "_LOD1")
    for i, m in enumerate(lod.data.materials):
        if m and m.name.startswith(base):
            lod.data.materials[i] = K.downscaled(m, TEX // 2, "_lod1")
    K.export(os.path.join(OUT, base + "_lod1.glb"), [lod], False)
    entry = {
        "file": f"assets/models/vehicles/{base}.glb",
        "lod1": f"assets/models/vehicles/{base}_lod1.glb",
        "triangles_lod0": L.tri_count(objs),
        "triangles_lod1": L.tri_count([lod]),
        "triangles_interior": L.tri_count([o for o in objs if o.name.startswith("IN_")]),
        "materials": sorted({base_mat(m) for o in objs if o.type == "MESH" and not o.name.endswith("_COL") for m in o.data.materials if m}),
        "notes": MODE_NOTES[mode],
    }
    if (vid, mode) in REST_POSE:
        entry["rest_pose"] = REST_POSE[(vid, mode)]
    extra = [p for p in pivots if p not in baseline["pivots"]]
    if extra:
        entry["added_pivots"] = extra
    extra_clips = [c for c in clips if c not in baseline["clips"]]
    if extra_clips:
        entry["added_clips"] = extra_clips
    if vid == "crx1":
        entry["bike_eject"] = {
            "clip": EJECT_CLIP, "frames": [0, 46], "fps": 30,
            "pivots": ["BayDoor_L", "BayDoor_R", "BikeSled"],
            "anchor": "bike_launch_anchor (child of BikeSled): parent the CR-B1 root here, same forward axis",
            "exit": "bike_launch_exit (on the root, on the road ahead of the nose)",
            "timeline": "0-18 nose petals open; 18-34 sled runs forward; 34-46 sled drops to the road, then release the bike",
        }
    if BAKE:
        entry["textures"] = f"{TEX}px baked base/MR/normal (JPEG in GLB); LOD1 {TEX // 2}px"
    bpy.data.objects.remove(lod)
    print(f"[modes] {base}: {entry['triangles_lod0']} tris (interior {entry['triangles_interior']}), LOD1 {entry['triangles_lod1']}")
    return entry


def render_variant(vid, mode, root):
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    if hasattr(sc, "eevee"):
        sc.eevee.taa_render_samples = 48
        if hasattr(sc.eevee, "use_raytracing"):
            sc.eevee.use_raytracing = True
    w = bpy.data.worlds.new("w")
    if hasattr(w, "use_nodes"):
        w.use_nodes = True
    sc.world = w
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.42, 0.46, 0.55, 1)
    bg.inputs[1].default_value = 0.7
    try:  # physical sky for believable outdoor light
        sky = w.node_tree.nodes.new("ShaderNodeTexSky")
        for t in ("MULTIPLE_SCATTERING", "NISHITA", "HOSEK_WILKIE"):
            try:
                sky.sky_type = t
                break
            except TypeError:
                pass
        if hasattr(sky, "sun_elevation"):
            sky.sun_elevation, sky.sun_rotation = math.radians(28), math.radians(140)
        w.node_tree.links.new(sky.outputs["Color"], bg.inputs[0])
        bg.inputs[1].default_value = SKY_STRENGTH
    except Exception as e:
        print("[modes] sky failed", e)
    objs = L.descendants(root)
    for o in objs:
        if o.name.endswith("_COL"):
            o.hide_render = True
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in objs:
        if o.type == "MESH" and not o.hide_render:
            for c in o.bound_box:
                p = o.matrix_world @ Vector(c)
                lo, hi = Vector(map(min, lo, p)), Vector(map(max, hi, p))
    center, radius = (lo + hi) / 2, max(hi - lo) / 2
    gm = bpy.data.materials.new("ground")
    gb = gm.node_tree.nodes["Principled BSDF"]
    gt = gm.node_tree.nodes.new("ShaderNodeTexImage")
    gt.image = L._img(os.path.join(L.PNG, "wet_asphalt.png"))
    gm.node_tree.links.new(gt.outputs["Color"], gb.inputs["Base Color"])
    gb.inputs["Roughness"].default_value = 0.4
    me = bpy.data.meshes.new("ground")
    me.from_pydata([(-500, -500, 0), (500, -500, 0), (500, 500, 0), (-500, 500, 0)], [], [(0, 1, 2, 3)])
    me.uv_layers.new(name="UVMap")
    for i, uv in enumerate(((-150, -150), (150, -150), (150, 150), (-150, 150))):
        me.uv_layers[0].data[i].uv = uv
    me.materials.append(gm)
    g = bpy.data.objects.new("ground", me)
    sc.collection.objects.link(g)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy, sun.data.angle = 3.0, math.radians(3)
    sun.rotation_euler = deg(40, 0, 150)
    sc.collection.objects.link(sun)
    for name, loc, energy, s in (("key", (1.3, -1.5, 1.3), 700, 2.5), ("rim", (-0.6, 1.8, 1.2), 600, 2.5)):
        d = bpy.data.lights.new(name, "AREA")
        d.energy, d.size = energy * (radius / 1.5) ** 2, s * radius
        o = bpy.data.objects.new(name, d)
        o.location = center + Vector(loc) * radius * 2.2
        o.rotation_euler = (center - o.location).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(o)
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cd.clip_end = radius * 60
    sc.render.resolution_x, sc.render.resolution_y = 960, 540
    os.makedirs(RENDERS, exist_ok=True)
    base = f"{VEHICLES[vid]['file']}_{mode}"
    shots = []
    for tag, d, lens in (("front", (1.0, -1.35, 0.5), 45), ("rear", (-1.1, 1.25, 0.6), 45)):
        cd.lens, cd.clip_start = lens, 0.1
        cam.location = center + Vector(d).normalized() * radius * 2.9
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(RENDERS, f"{base}_{tag}.png")
        bpy.ops.render.render(write_still=True)
        shots.append(sc.render.filepath)
    if vid == "crx1":  # bike launch: petals open, sled run out with the CR-B1 riding it
        pose_eject(-3.3)
        bike = os.path.join(OUT, f"CRB1_batcycle_{'stealth' if mode == 'stealth' else 'pursuit'}.glb")
        before = set(bpy.data.objects)
        if os.path.exists(bike):
            bpy.ops.import_scene.gltf(filepath=bike)
            bpy.context.view_layer.update()
            anchor = ob("bike_launch_anchor").matrix_world.copy()
            for o in set(bpy.data.objects) - before:
                if o.name.endswith("_COL"):
                    o.hide_render = True
                if o.parent is None:
                    o.matrix_world = anchor @ o.matrix_world
        cd.lens, cd.clip_start = 35, 0.1
        cam.location = Vector((3.2, -9.0, 2.3))
        cam.rotation_euler = (Vector((0, -2.8, 0.6)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(RENDERS, f"{base}_eject.png")
        bpy.ops.render.render(write_still=True)
        for o in set(bpy.data.objects) - before:
            o.hide_render = True
        pose_eject(-2.4)
        ob("BayDoor_L").rotation_euler = (0, 0, 0)
        ob("BayDoor_R").rotation_euler = (0, 0, 0)
    cc = bpy.data.objects.get("camera_cockpit")
    if cc:
        cd.lens, cd.clip_start = 16, 0.02
        cam.location = cc.matrix_world.to_translation()
        cam.rotation_euler = deg(90 + VEHICLES[vid]["pitch"], 0, 180)
        sc.render.filepath = os.path.join(RENDERS, f"{base}_cockpit.png")
        bpy.ops.render.render(write_still=True)
        shots.append(sc.render.filepath)
    return shots


def contact_sheet(vid, rows):
    """rows: [[png, ...] per mode] -> one sheet per vehicle, 480x270 tiles."""
    import numpy as np
    tw, th = 480, 270
    nr, nc = len(rows), max(len(r) for r in rows)
    sheet = np.zeros((nr * th, nc * tw, 4), dtype=np.float32)
    sheet[..., 3] = 1
    for r, files in enumerate(rows):
        for c, f in enumerate(files):
            img = bpy.data.images.load(f)
            img.scale(tw, th)
            px = np.array(img.pixels[:], dtype=np.float32).reshape(th, tw, 4)
            y0 = (nr - 1 - r) * th
            sheet[y0:y0 + th, c * tw:(c + 1) * tw] = px
            bpy.data.images.remove(img)
    out = bpy.data.images.new("sheet", nc * tw, nr * th, alpha=False)
    out.pixels = sheet.ravel()
    out.filepath_raw = os.path.join(RENDERS, f"{VEHICLES[vid]['file']}_modes_sheet.png")
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)


def update_manifest(vid, modes):
    path = os.path.join(L.ROOT, "config", "asset_manifest.json")
    with open(path, encoding="utf-8") as fh:
        man = json.load(fh)
    by_id = {a["id"]: i for i, a in enumerate(man["assets"])}
    v = VEHICLES[vid]
    for mode, m in modes.items():
        for lod in (0, 1):
            f = m["file"] if lod == 0 else m["lod1"]
            entry = {
                "id": os.path.splitext(os.path.basename(f))[0], "category": "vehicles", "file": f, "format": "glb",
                "stage": "prototype" if lod == 0 else "prototype_lod", "rigged": False,
                "animation_clips": len(cfg_clips(v)) if lod == 0 else 0,
                "collision": "*_COL boxes in file" if lod == 0 else "none (visual)", "units": "meters",
                "origin": "ground_center", "up_axis": "Y", "forward": "+Z", "source": "tools/blender/ck_build_vehicle_modes.py",
                "triangles": m["triangles_lod0"] if lod == 0 else m["triangles_lod1"],
                "vehicle": v["key"], "mode": mode,
            }
            if entry["id"] in by_id:
                man["assets"][by_id[entry["id"]]] = entry
            else:
                by_id[entry["id"]] = len(man["assets"])
                man["assets"].append(entry)
    man["asset_count"] = len(man["assets"])
    note = "1.8 (Claude): per-mode vehicle variants (pursuit/battle/stealth, flight/vtol/stealth) with first-person cockpits."
    if note not in man["changelog"]:
        man["changelog"].append(note)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(man, fh, indent=2, ensure_ascii=False)


def cfg_clips(v):
    with open(CFG) as fh:
        return json.load(fh)[v["key"]]["clips"]


def main():
    with open(CFG) as fh:
        cfg = json.load(fh)
    pick = [a for a in ARGS if a in VEHICLES] or ["crb1", "crx1", "cra1"]  # bike first: the car's eject render uses it
    for vid in pick:
        v = VEHICLES[vid]
        baseline = cfg[v["key"]]
        modes, rows = {}, []
        for mode in v["modes"]:
            root = build_variant(vid, mode)
            modes[mode] = export_variant(vid, mode, root, baseline)
            if RENDER:
                rows.append(render_variant(vid, mode, root))
        cfg[v["key"]]["modes"] = modes
        if RENDER:
            contact_sheet(vid, rows)
        with open(CFG, "w") as fh:
            json.dump(cfg, fh, indent=2)
        update_manifest(vid, modes)
    print("[modes] OK")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
