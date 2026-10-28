"""
Crimson Knight: Earth-RED -- NPC / enemy family builder (Blender 5.x, headless).

    blender -b --factory-startup --python tools/blender/ck_build_npcs.py

Every humanoid reuses the CR-X9 skeleton maths and poser from ck_build_crx9.py (minus the cape chain),
so all NPCs share one bone layout and one clip set: NPC_Idle, NPC_Walk, NPC_Alert, NPC_Cower.
Each NPC is ONE skinned mesh with ONE vertex-coloured material (one draw call per NPC on the laptop GPU).
The patrol drone is a rigid, non-skinned model with rotor pivots and a hover clip.

No AI is implemented here or in the game yet (directive: assets first) -- NPCs stand in the city idling.

Outputs: assets/models/npcs/npc_<type>.glb, config/npc_assets.json
"""
import json
import os
import sys
from math import radians

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ck_build_crx9 as v1  # noqa: E402  (skeleton, poser, clip maths)
import ck_lib as L  # noqa: E402  (rigid-asset helpers for the drone)

ROOT = os.path.dirname(os.path.dirname(HERE))
OUT_DIR = os.path.join(ROOT, "assets", "models", "npcs")
OUT_JSON = os.path.join(ROOT, "config", "npc_assets.json")
SIDES = v1.SIDES

# palette: name -> sRGB hex (baked into vertex colours)
PAL = {
    "skin_a": "#c89a7c", "skin_b": "#8d5e44", "skin_c": "#e1b99c", "hair_dark": "#1d1714", "hair_brown": "#4a3022",
    "hair_grey": "#8a8a8a", "denim": "#2f3f5c", "khaki": "#7b6e52", "black": "#151517", "charcoal": "#2d2f33",
    "grey": "#5d6168", "white": "#d9d9d6", "navy": "#1c2740", "police_blue": "#1f2f57", "hivis": "#e7a316",
    "hivis_yellow": "#cbd63a", "orange": "#c9581c", "red": "#8e1a1a", "crimson": "#b3122a", "green": "#3c4a32",
    "olive": "#4f5233", "tan": "#9a7e5c", "brown": "#4b3526", "steel": "#7c8590", "gunmetal": "#3a3f46",
    "visor": "#0d1b24", "glow_red": "#ff2a2a", "glow_cyan": "#39d4ff", "purple": "#3d2a52", "teal": "#1f4d4d",
    "shoe": "#1b1a19", "boot": "#2b2219", "silver": "#b6bcc4", "gold": "#b8922e",
}
PAL_NAMES = list(PAL)


def srgb_to_linear(h):
    return v1.srgb(h)[:3]


# --------------------------------------------------------------------------------------
# NPC catalogue
# --------------------------------------------------------------------------------------
# body: girth multiplier, belly, height scale applied in game (scale), skin tone
# clothes: shirt, pants, shoes, hair, sleeves ("long"/"short"), gloves
# acc: accessory ids built below
NPCS = {
    "civilian_a": dict(label="Civilian (jacket)", role="civilian", girth=1.0, belly=1.0, skin="skin_a", hair="hair_brown",
                       shirt="teal", pants="denim", shoes="shoe", sleeves="long", acc=["jacket_collar"]),
    "civilian_b": dict(label="Civilian (t-shirt)", role="civilian", girth=0.94, belly=0.95, skin="skin_b", hair="hair_dark",
                       shirt="crimson", pants="khaki", shoes="white", sleeves="short", acc=["long_hair"]),
    "office_worker": dict(label="Office worker", role="civilian", girth=0.98, belly=1.05, skin="skin_c", hair="hair_grey",
                          shirt="white", pants="charcoal", shoes="shoe", sleeves="long", acc=["tie", "suit_jacket", "briefcase"]),
    "construction_worker": dict(label="Construction worker", role="civilian", girth=1.1, belly=1.1, skin="skin_a",
                                hair="hair_brown", shirt="grey", pants="denim", shoes="boot", sleeves="short",
                                acc=["hard_hat", "hivis_vest", "tool_belt"]),
    "police_officer": dict(label="New Gotham PD officer", role="law", girth=1.05, belly=1.0, skin="skin_b", hair="hair_dark",
                           shirt="police_blue", pants="navy", shoes="shoe", sleeves="long",
                           acc=["police_cap", "duty_belt", "badge", "radio"]),
    "security_guard": dict(label="Owen Enterprises security", role="law", girth=1.08, belly=1.08, skin="skin_c",
                           hair="hair_brown", shirt="charcoal", pants="black", shoes="shoe", sleeves="long",
                           acc=["security_cap", "duty_belt", "oe_patch"]),
    "scientist": dict(label="Owen Enterprises scientist", role="civilian", girth=0.95, belly=1.0, skin="skin_c",
                      hair="hair_grey", shirt="grey", pants="charcoal", shoes="shoe", sleeves="long",
                      acc=["lab_coat", "glasses", "id_card"]),
    "mechanic": dict(label="Mechanic", role="civilian", girth=1.05, belly=1.05, skin="skin_b", hair="hair_dark",
                     shirt="navy", pants="navy", shoes="boot", sleeves="short", acc=["backwards_cap", "wrench_belt"]),
    "criminal_thug": dict(label="Street thug", role="enemy", girth=1.1, belly=1.0, skin="skin_a", hair="hair_dark",
                          shirt="purple", pants="black", shoes="shoe", sleeves="long", acc=["beanie", "bandana", "pipe"]),
    "mercenary": dict(label="Mercenary", role="enemy", girth=1.12, belly=1.0, skin="skin_b", hair="hair_dark",
                      shirt="olive", pants="olive", shoes="boot", sleeves="long", gloves="black",
                      acc=["tactical_helmet", "plate_carrier", "backpack", "knee_pads"]),
    "enforcer": dict(label="Heavy enforcer", role="enemy", girth=1.32, belly=1.15, skin="skin_a", hair="hair_dark",
                     shirt="gunmetal", pants="black", shoes="boot", sleeves="long", gloves="black", scale=1.12,
                     acc=["heavy_shoulders", "gas_mask", "plate_carrier", "knee_pads"]),
    "stealth_operative": dict(label="Stealth operative", role="enemy", girth=0.96, belly=0.95, skin="black", hair="black",
                              shirt="black", pants="black", shoes="black", sleeves="long", gloves="black",
                              acc=["stealth_hood", "visor_strip", "blade_sheath"]),
    "riot_trooper": dict(label="Riot trooper", role="enemy", girth=1.15, belly=1.0, skin="skin_c", hair="hair_dark",
                         shirt="charcoal", pants="charcoal", shoes="boot", sleeves="long", gloves="black",
                         acc=["riot_helmet", "plate_carrier", "heavy_shoulders", "riot_shield", "knee_pads"]),
    "security_robot": dict(label="Sentinel security robot", role="enemy", robot=True, scale=1.08, acc=[]),
}


# --------------------------------------------------------------------------------------
# NPC rig (CR-X9 skeleton minus the cape chain)
# --------------------------------------------------------------------------------------
_bone_defs = v1.bone_defs
v1.bone_defs = lambda J: [b for b in _bone_defs(J) if not b[0].startswith("Cape_")]


def make_palette_materials():
    mats = {}
    for n, h in PAL.items():
        m = bpy.data.materials.new(n)
        m.diffuse_color = tuple(srgb_to_linear(h)) + (1.0,)
        mats[n] = m
    return mats


def build_body(J, mats, rig, spec):
    """Skin-modifier body like the CR-X9 undersuit, with per-NPC girth and belly; auto-weighted."""
    g, belly = spec["girth"], spec["belly"]
    pts, rad, edges = [], [], []

    def P(co, r):
        pts.append(Vector(co))
        r = r if isinstance(r, tuple) else (r, r)
        rad.append(r)
        return len(pts) - 1

    def chain(*ids):
        edges.extend(zip(ids, ids[1:]))

    pelvis = P((0, 0, 0.98), (0.135 * g, 0.105 * g * belly))
    waist = P((0, -0.005 * (belly - 1) * 10, 1.12), (0.128 * g * belly, 0.1 * g * belly))
    chest = P((0, -0.005, 1.28), (0.165 * g, 0.108 * g))
    upper = P((0, 0, 1.42), (0.18 * g, 0.1 * g))
    nbase = P((0, 0, 1.51), 0.058 * g)
    ntop = P((0, -0.005, 1.6), 0.052)
    head = P((0, -0.01, 1.69), (0.098, 0.108))
    htop = P((0, -0.005, 1.79), 0.075)
    chain(pelvis, waist, chest, upper, nbase, ntop, head, htop)
    for s, k in SIDES:
        d = J["arm_dir_" + s]
        clav = P(J["sh_" + s] - Vector((k * 0.07, 0.005, 0.02)), 0.062 * g)
        sh = P(J["sh_" + s], 0.064 * g)
        ua = P(J["sh_" + s] + d * 0.15, 0.058 * g)
        el = P(J["el_" + s], 0.046 * g)
        fa = P(J["el_" + s] + d * 0.12, 0.048 * g)
        wr = P(J["wr_" + s], 0.034)
        hm = P(J["wr_" + s] + d * 0.08, 0.04)
        he = P(J["hand_" + s], 0.024)
        chain(upper, clav, sh, ua, el, fa, wr, hm, he)
        hip = P(J["hip_" + s] - Vector((k * 0.01, 0, 0.04)), 0.1 * g)
        th = P(J["hip_" + s].lerp(J["knee_" + s], 0.5), 0.085 * g)
        kn = P(J["knee_" + s], 0.058 * g)
        sn = P(J["knee_" + s].lerp(J["ankle_" + s], 0.45), 0.058 * g)
        an = P(J["ankle_" + s], 0.045)
        bl = P(J["ball_" + s] + Vector((0, 0, 0.005)), 0.045)
        tt = P(J["toe_" + s] + Vector((0, 0.01, 0)), 0.032)
        chain(pelvis, hip, th, kn, sn, an, bl, tt)

    me = bpy.data.meshes.new("NPC_Skin")
    me.from_pydata([tuple(p) for p in pts], edges, [])
    obj = bpy.data.objects.new("NPC_Skin", me)
    bpy.context.scene.collection.objects.link(obj)
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.branch_smoothing = 0.4
    for i, r in enumerate(rad):
        sv = me.skin_vertices[0].data[i]
        sv.radius = r
        sv.use_root = (i == pelvis)
    sub = obj.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = sub.render_levels = 1  # crowd budget (hero uses 2)
    dg = bpy.context.evaluated_depsgraph_get()
    body = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj)
    body.name = "NPC_Body"
    for n in PAL_NAMES:
        body.materials.append(mats[n])
    out = bpy.data.objects.new("NPC_Body", body)
    bpy.context.scene.collection.objects.link(out)
    colour_regions(out, J, spec)
    v1.finish_mesh(body, 80)
    bpy.ops.object.select_all(action="DESELECT")
    out.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    v1.fill_missing_weights(out, rig)
    return out


def colour_regions(obj, J, spec):
    """Clothing by region: head/neck skin + hair, torso shirt, sleeves, hands, trousers, shoes."""
    idx = {n: i for i, n in enumerate(PAL_NAMES)}
    hands = [J["hand_L"].lerp(J["wr_L"], 0.4), J["hand_R"].lerp(J["wr_R"], 0.4)]
    elbows = [J["el_L"], J["el_R"]]
    out = []
    for p in obj.data.polygons:
        c = p.center
        if c.z > 1.535:
            hair = c.z > 1.735 or (c.z > 1.6 and c.y > 0.02) or (c.z > 1.68 and abs(c.x) > 0.075)
            m = spec["hair"] if hair else spec["skin"]
        elif abs(c.x) > 0.22 and c.z > 0.9:  # arms
            if min((c - h).length for h in hands) < 0.1:
                m = spec.get("gloves", spec["skin"])
            elif spec["sleeves"] == "short" and min((c - e).length for e in elbows) < 0.13 or \
                    spec["sleeves"] == "short" and c.z < min(e.z for e in elbows):
                m = spec["skin"]
            else:
                m = spec["shirt"]
        elif c.z > 0.93:
            m = spec["shirt"]
        elif c.z > 0.115:
            m = spec["pants"]
        else:
            m = spec["shoes"]
        out.append(idx[m])
    obj.data.polygons.foreach_set("material_index", out)


# --------------------------------------------------------------------------------------
# Accessories (rigid parts weighted to one bone each)
# --------------------------------------------------------------------------------------
HEAD = Vector((0, -0.01, 1.70))


def accessories(pb, J, spec):
    """Each accessory: pb.add(bmesh, bone, palette colour, position, rotation)."""
    box, cyl, sph = v1.prim_box, v1.prim_cyl, v1.prim_sphere
    g = spec.get("girth", 1.0)
    for a in spec["acc"]:
        if a == "jacket_collar":
            pb.add(box((0.3 * g, 0.2 * g, 0.06), bevel=0.02), "Chest", spec["shirt"], Vector((0, 0.01, 1.47)))
            for s, k in SIDES:
                pb.add(box((0.05, 0.012, 0.32), bevel=0.004), "Chest", "charcoal", Vector((k * 0.06, -0.112 * g, 1.28)))
        elif a == "long_hair":
            pb.add(box((0.17, 0.06, 0.24), (1, 1), (0.9, 0.6), bevel=0.03), "Head", spec["hair"], Vector((0, 0.07, 1.6)))
        elif a == "tie":
            pb.add(box((0.05, 0.012, 0.3), (1, 1), (0.5, 1), bevel=0.003), "Chest", "red", Vector((0, -0.113 * g, 1.27)))
        elif a == "suit_jacket":
            pb.add(box((0.37 * g, 0.235 * g, 0.5), (1.02, 1), (0.92, 1), bevel=0.03), "Spine", "charcoal",
                   Vector((0, 0.012, 1.18)))
        elif a == "briefcase":
            pb.add(box((0.08, 0.36, 0.27), bevel=0.01), "Hand_R", "brown", J["hand_R"] + Vector((0, 0, -0.17)))
        elif a == "hard_hat":
            pb.add(sph((0.11, 0.12, 0.08), 16, 8), "Head", "hivis_yellow", HEAD + Vector((0, 0, 0.075)))
            pb.add(cyl(0.135, 0.135, 0.012, 20), "Head", "hivis_yellow", HEAD + Vector((0, -0.01, 0.06)))
        elif a == "hivis_vest":
            pb.add(box((0.35 * g, 0.235 * g, 0.42), bevel=0.03), "Chest", "hivis", Vector((0, 0.005, 1.25)))
            pb.add(box((0.355 * g, 0.24 * g, 0.03), bevel=0.0), "Chest", "silver", Vector((0, 0.005, 1.18)))
        elif a == "tool_belt":
            pb.add(box((0.31 * g, 0.24 * g, 0.06), bevel=0.01), "Hips", "brown", Vector((0, 0, 0.97)))
            pb.add(box((0.08, 0.08, 0.12), bevel=0.01), "Hips", "tan", Vector((0.17 * g, -0.03, 0.92)))
        elif a in ("police_cap", "security_cap"):
            col = "navy" if a == "police_cap" else "black"
            pb.add(cyl(0.1, 0.106, 0.075, 18), "Head", col, HEAD + Vector((0, 0, 0.09)))
            pb.add(box((0.17, 0.08, 0.012), bevel=0.004), "Head", "black", HEAD + Vector((0, -0.11, 0.06)))
            pb.add(box((0.04, 0.01, 0.03), bevel=0.002), "Head", "gold" if a == "police_cap" else "crimson",
                   HEAD + Vector((0, -0.106, 0.1)))
        elif a == "duty_belt":
            pb.add(box((0.31 * g, 0.24 * g, 0.055), bevel=0.01), "Hips", "black", Vector((0, 0, 0.97)))
            for k in (1, -1):
                pb.add(box((0.05, 0.07, 0.1), bevel=0.01), "Hips", "black", Vector((k * 0.165 * g, -0.02, 0.94)))
        elif a == "badge":
            pb.add(box((0.035, 0.01, 0.04), bevel=0.003), "Chest", "gold", Vector((0.07, -0.115 * g, 1.33)))
        elif a == "radio":
            pb.add(box((0.04, 0.03, 0.07), bevel=0.005), "Chest", "black", Vector((-0.08, -0.11 * g, 1.38)))
        elif a == "oe_patch":
            pb.add(box((0.05, 0.01, 0.05), bevel=0.003), "UpperArm_L", "crimson", J["sh_L"] + J["arm_dir_L"] * 0.1 +
                   Vector((0.035, -0.02, 0)))
        elif a == "lab_coat":
            pb.add(box((0.37 * g, 0.235 * g, 0.62), (1.02, 1), (1.08, 1.05), bevel=0.03), "Spine", "white",
                   Vector((0, 0.01, 1.12)))
            for s, k in SIDES:
                pb.add(box((0.15, 0.2, 0.38), (1, 1), (1.05, 1.05), bevel=0.02), "UpperLeg_" + s, "white",
                       J["hip_" + s].lerp(J["knee_" + s], 0.33) + Vector((k * 0.01, 0, 0)))
        elif a == "glasses":
            pb.add(box((0.15, 0.01, 0.035), bevel=0.003), "Head", "black", HEAD + Vector((0, -0.094, 0.015)))
        elif a == "id_card":
            pb.add(box((0.04, 0.006, 0.055), bevel=0.002), "Chest", "crimson", Vector((-0.07, -0.122, 1.3)))
        elif a == "backwards_cap":
            pb.add(sph((0.092, 0.1, 0.06), 14, 7), "Head", "crimson", HEAD + Vector((0, 0, 0.07)))
            pb.add(box((0.14, 0.07, 0.01), bevel=0.003), "Head", "crimson", HEAD + Vector((0, 0.11, 0.06)))
        elif a == "wrench_belt":
            pb.add(box((0.3 * g, 0.235 * g, 0.05), bevel=0.01), "Hips", "black", Vector((0, 0, 0.97)))
            pb.add(box((0.025, 0.02, 0.22), bevel=0.004), "Hips", "steel", Vector((0.17 * g, -0.05, 0.86)))
        elif a == "beanie":
            pb.add(sph((0.092, 0.102, 0.075), 14, 7), "Head", "black", HEAD + Vector((0, 0, 0.065)))
        elif a == "bandana":
            pb.add(box((0.17, 0.09, 0.07), (1, 1), (0.85, 1), bevel=0.02), "Head", "red", HEAD + Vector((0, -0.04, -0.04)))
        elif a == "pipe":
            pb.add(cyl(0.016, 0.016, 0.6, 10), "Hand_R", "steel", J["hand_R"] + Vector((0, 0, -0.22)))
        elif a == "tactical_helmet":
            pb.add(sph((0.108, 0.118, 0.085), 18, 9), "Head", spec["shirt"], HEAD + Vector((0, 0.005, 0.07)))
            pb.add(box((0.12, 0.03, 0.04), bevel=0.01), "Head", "black", HEAD + Vector((0, -0.105, 0.09)))
        elif a == "plate_carrier":
            pb.add(box((0.36 * g, 0.25 * g, 0.38), bevel=0.03), "Chest", "black", Vector((0, 0.005, 1.27)))
            for k in (-1, 0, 1):
                pb.add(box((0.07, 0.04, 0.09), bevel=0.01), "Chest", "gunmetal", Vector((k * 0.09, -0.14 * g, 1.17)))
        elif a == "backpack":
            pb.add(box((0.28, 0.13, 0.36), bevel=0.03), "Chest", spec["shirt"], Vector((0, 0.18 * g, 1.28)))
        elif a == "knee_pads":
            for s, k in SIDES:
                pb.add(box((0.1, 0.06, 0.12), bevel=0.02), "LowerLeg_" + s, "black", J["knee_" + s] + Vector((0, -0.055, 0)))
        elif a == "heavy_shoulders":
            for s, k in SIDES:
                pb.add(sph((0.11, 0.12, 0.08), 14, 7), "Shoulder_" + s, "gunmetal", J["sh_" + s] + Vector((k * 0.03, 0, 0.04)))
        elif a == "gas_mask":
            pb.add(box((0.15, 0.08, 0.12), (0.8, 1), (1, 1), bevel=0.03), "Head", "black", HEAD + Vector((0, -0.07, -0.02)))
            for k in (1, -1):
                pb.add(cyl(0.03, 0.03, 0.04, 12), "Head", "gunmetal", HEAD + Vector((k * 0.06, -0.12, -0.05)),
                       v1.frame(Vector((k * 0.5, -1, 0))))
            pb.add(box((0.13, 0.02, 0.035), bevel=0.005), "Head", "glow_red", HEAD + Vector((0, -0.1, 0.02)))
        elif a == "stealth_hood":
            pb.add(sph((0.1, 0.11, 0.105), 16, 8), "Head", "black", HEAD + Vector((0, 0.01, 0.01)))
        elif a == "visor_strip":
            pb.add(box((0.14, 0.02, 0.025), bevel=0.006), "Head", "glow_red", HEAD + Vector((0, -0.1, 0.02)))
        elif a == "blade_sheath":
            pb.add(box((0.04, 0.03, 0.5), bevel=0.008), "Chest", "gunmetal", Vector((0.06, 0.13, 1.25)),
                   v1.frame(Vector((0.5, 0, 1))))
        elif a == "riot_helmet":
            pb.add(sph((0.115, 0.125, 0.11), 18, 9), "Head", "charcoal", HEAD + Vector((0, 0.005, 0.03)))
            pb.add(box((0.2, 0.03, 0.12), (1, 1), (0.95, 1), bevel=0.02), "Head", "visor", HEAD + Vector((0, -0.12, 0.0)))
        elif a == "riot_shield":
            pb.add(box((0.03, 0.55, 0.85), bevel=0.02), "LowerArm_L", "visor", J["wr_L"] + Vector((0.07, -0.1, 0.05)))
            pb.add(box((0.035, 0.3, 0.06), bevel=0.01), "LowerArm_L", "silver", J["wr_L"] + Vector((0.075, -0.1, 0.25)))
        else:
            raise ValueError(f"unknown accessory {a}")


def build_robot(J, mats, rig):
    """Sentinel robot: rigid shells per bone (no skin body) -- reads mechanical, deforms nothing."""
    pb = v1.PartBuilder()
    box, cyl, sph = v1.prim_box, v1.prim_cyl, v1.prim_sphere

    def limb(bone, a, b, w, d, col):
        dirv = b - a
        pb.add(box((w, d, dirv.length * 0.92), bevel=0.015), bone, col, (a + b) / 2, v1.frame(dirv))

    pb.add(box((0.3, 0.2, 0.18), bevel=0.03), "Hips", "gunmetal", Vector((0, 0, 0.97)))
    pb.add(cyl(0.07, 0.09, 0.16, 12), "Spine", "steel", Vector((0, 0, 1.12)))
    pb.add(box((0.44, 0.26, 0.32), (1.1, 1), (0.8, 0.9), bevel=0.04), "Chest", "silver", Vector((0, 0, 1.33)))
    pb.add(box((0.2, 0.02, 0.1), bevel=0.01), "Chest", "crimson", Vector((0, -0.133, 1.36)))
    pb.add(cyl(0.03, 0.03, 0.08, 10), "Neck", "steel", Vector((0, 0, 1.54)))
    pb.add(box((0.17, 0.19, 0.17), bevel=0.04), "Head", "silver", HEAD + Vector((0, 0, 0.0)))
    pb.add(box((0.15, 0.02, 0.035), bevel=0.008), "Head", "glow_red", HEAD + Vector((0, -0.1, 0.015)))
    pb.add(cyl(0.004, 0.004, 0.12, 6), "Head", "steel", HEAD + Vector((0.06, 0.03, 0.14)))
    for s, k in SIDES:
        pb.add(sph((0.085, 0.085, 0.07), 12, 6), "Shoulder_" + s, "gunmetal", J["sh_" + s] + Vector((k * 0.02, 0, 0.02)))
        limb("UpperArm_" + s, J["sh_" + s], J["el_" + s], 0.08, 0.08, "steel")
        limb("LowerArm_" + s, J["el_" + s], J["wr_" + s], 0.095, 0.095, "silver")
        limb("Hand_" + s, J["wr_" + s], J["hand_" + s], 0.07, 0.05, "gunmetal")
        limb("UpperLeg_" + s, J["hip_" + s], J["knee_" + s], 0.11, 0.11, "steel")
        pb.add(sph((0.06, 0.06, 0.06), 10, 6), "LowerLeg_" + s, "gunmetal", J["knee_" + s])
        limb("LowerLeg_" + s, J["knee_" + s], J["ankle_" + s], 0.12, 0.13, "silver")
        pb.add(box((0.1, 0.22, 0.07), bevel=0.02), "Foot_" + s, "gunmetal", J["ankle_" + s] + Vector((0, -0.06, -0.06)))
    return pb.to_object("NPC_Body", mats, rig)


def bake_vertex_colours(obj):
    """Material slot colours -> one CORNER colour attribute; then a single vertex-colour material."""
    me = obj.data
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    cols = [tuple(me.materials[p.material_index].diffuse_color) for p in me.polygons]
    flat = []
    for p in me.polygons:
        c = cols[p.index]
        flat.extend(c * len(p.loop_indices))
    attr.data.foreach_set("color", flat)
    me.color_attributes.active_color = attr
    me.materials.clear()
    m = bpy.data.materials.new("NPC_Vertex")
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    vc = nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.72
    bsdf.inputs["Metallic"].default_value = 0.0
    me.materials.append(m)


# --------------------------------------------------------------------------------------
# Clips (shared by all humanoids)
# --------------------------------------------------------------------------------------
def npc_clips():
    P_, br, kd = v1.P_, v1.breathing, v1.keyed
    idle = P_(capelift=0)
    alert = P_(hz=-0.06, fy_L=-0.12, fy_R=0.1, fyaw_R=-18, cyaw=10, sp=6, hdp=-4, sw_L=40, sw_R=46, ad_L=30, ad_R=34,
               elb_L=70, elb_R=75, capelift=0)
    cower = P_(hz=-0.38, hy=0.08, sp=30, cp=16, hdp=20, sw_L=95, sw_R=95, ad_L=18, ad_R=18, elb_L=125, elb_R=125,
               fy_L=-0.12, fy_R=0.08, capelift=0)
    talk_a = P_(sw_R=30, ad_R=40, elb_R=60, tw_R=-20, hdyaw=8, capelift=0)
    talk_b = P_(sw_R=42, ad_R=46, elb_R=82, tw_R=-10, sw_L=12, elb_L=30, hdyaw=-6, hdp=4, capelift=0)
    return [
        ("NPC_Idle", 72, True, None, br(72, idle, 0.8), "breathing idle (random start phase per NPC)"),
        ("NPC_Walk", 32, True, 1.4, v1.locomotion(32, 1.4, 0.6, 0.085, -0.03, 0.012, 2, 20, 16, 34, 0, 0, hip_yaw=6),
         "relaxed walk cycle, 1.4 m/s"),
        ("NPC_Alert", 60, True, None, br(60, alert, 0.6), "guard / combat-ready stance (enemies)"),
        ("NPC_Cower", 48, True, None, br(48, cower, 1.4), "civilian crouch with arms over head"),
        ("NPC_Talk", 60, True, None, kd([(0, talk_a), (15, talk_b), (30, talk_a), (45, talk_b), (60, talk_a)]),
         "conversation gestures"),
    ]


def export_npc(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    opts = dict(
        filepath=path, export_format="GLB", use_selection=False, export_yup=True, export_apply=False,
        export_texcoord=False, export_normals=True, export_materials="EXPORT", export_vertex_color="ACTIVE",
        export_all_vertex_colors=False, export_skins=True, export_all_influences=False, export_def_bones=False,
        export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
        export_optimize_animation_size=False, export_anim_single_armature=True, export_reset_pose_bones=True,
        export_cameras=False, export_lights=False, export_extras=False,
    )
    valid = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    bpy.ops.export_scene.gltf(**{k: v for k, v in opts.items() if k in valid})


def build_humanoid(key, spec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = v1.FPS
    J = v1.joints()
    rig = v1.build_armature(J)
    rig.name = f"NPC_{key}_Rig"
    mats = make_palette_materials()
    v1.MATS = PAL_NAMES  # PartBuilder indexes materials through this list
    if spec.get("robot"):
        body = build_robot(J, mats, rig)
    else:
        body = build_body(J, mats, rig, spec)
        if spec["acc"]:
            pb = v1.PartBuilder()
            accessories(pb, J, spec)
            parts = pb.to_object("NPC_Parts", mats, rig)
            bpy.ops.object.select_all(action="DESELECT")
            parts.select_set(True)
            body.select_set(True)
            bpy.context.view_layer.objects.active = body
            bpy.ops.object.join()
    body.name = f"NPC_{key}"
    bake_vertex_colours(body)
    # sockets for later gameplay (weapons / held props), as bone names
    v1.CLIP_TABLE = npc_clips
    meta = v1.bake_clips(rig, J)
    path = os.path.join(OUT_DIR, f"npc_{key}.glb")
    export_npc(path)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print(f"[NPC] {key}: {tris} tris -> {path}")
    return dict(id=f"npc_{key}", file=os.path.relpath(path, ROOT).replace("\\", "/"), label=spec["label"], role=spec["role"],
                triangles=tris, bones=len(rig.data.bones), scale=spec.get("scale", 1.0), materials=1,
                clips=[m["name"] for m in meta], sockets={"hand_R": "Hand_R", "hand_L": "Hand_L", "head": "Head"})


def build_drone():
    """Patrol drone (rigid): body, four rotor pivots, camera eye, gimbal; clip NPC_DroneHover."""
    L.reset()
    root = L.empty("NPC_Drone", (0, 0, 0))
    body = L.box("Drone_Body", (0.5, 0.62, 0.16), (0, 0, 0), "Gunmetal", parent=root, bevel=0.04, taper_top=(0.8, 0.8))
    L.box("Drone_Stripe", (0.51, 0.1, 0.02), (0, -0.16, 0.07), "EmissiveRed", parent=body, bevel=0.005)
    gimbal = L.empty("Drone_Gimbal", (0, -0.24, -0.1), parent=body)
    L.cyl("Drone_Eye", 0.07, 0.07, 0.09, (0, 0, 0), "Black", parent=gimbal, rot=L.deg(90, 0, 0), segs=16)
    L.cyl("Drone_Lens", 0.04, 0.04, 0.01, (0, -0.05, 0), "EmissiveRed", parent=gimbal, rot=L.deg(90, 0, 0), segs=16)
    rotors = []
    for i, (x, y) in enumerate(((0.42, 0.42), (-0.42, 0.42), (0.42, -0.42), (-0.42, -0.42))):
        arm_len = (x * x + y * y) ** 0.5
        L.box(f"Drone_Arm{i}", (0.06, arm_len, 0.04), (x / 2, y / 2, 0.02), "Black", parent=body, bevel=0.01,
              rot=(0, 0, -__import__("math").atan2(x, y)))
        L.cyl(f"Drone_Motor{i}", 0.05, 0.05, 0.07, (x, y, 0.05), "Gunmetal", parent=body, segs=12)
        L.torus(f"Drone_Guard{i}", 0.2, 0.012, (x, y, 0.08), "Black", parent=body, seg=24, ring=6)
        piv = L.empty(f"Rotor_{i}", (x, y, 0.1), parent=body)
        L.box(f"Drone_Blade{i}", (0.36, 0.035, 0.008), (0, 0, 0), "Black", parent=piv, bevel=0.0)
        rotors.append(piv)
    for i, piv in enumerate(rotors):
        L.clip(piv, "NPC_DroneHover", [(0, (0, 0, 0)), (12, L.deg(0, 0, 360 * (1 if i % 2 else -1)))])
    L.clip(body, "NPC_DroneHover", [(0, (0, 0, 0)), (24, (0, 0, 0.06)), (48, (0, 0, 0))], path="location")
    L.clip(gimbal, "NPC_DroneScan", [(0, L.deg(0, 0, -35)), (40, L.deg(0, 0, 35)), (80, L.deg(0, 0, -35))])
    path = os.path.join(OUT_DIR, "npc_patrol_drone.glb")
    objs = L.descendants(root)
    L.export(path, animations=True)
    tris = L.tri_count(objs)
    print(f"[NPC] patrol_drone: {tris} tris")
    return dict(id="npc_patrol_drone", file=os.path.relpath(path, ROOT).replace("\\", "/"), label="Patrol drone",
                role="enemy", triangles=tris, rigged=False, clips=["NPC_DroneHover", "NPC_DroneScan"],
                pivots=[r.name for r in rotors] + ["Drone_Gimbal"], hover_height_m=3.5)


def main():
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = []
    for key, spec in NPCS.items():
        if only and key not in only:
            continue
        out.append(build_humanoid(key, spec))
    if not only or "patrol_drone" in only:
        out.append(build_drone())
    if not only:
        with open(OUT_JSON, "w", encoding="utf-8") as fh:
            json.dump({"source": "tools/blender/ck_build_npcs.py", "forward": "+Z (Three.js)", "height_m": 1.84,
                       "note": "No AI yet: placed idle in the district. One vertex-coloured material per NPC.",
                       "npcs": out}, fh, indent=2)
    print(f"[NPC] OK {len(out)} assets")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
