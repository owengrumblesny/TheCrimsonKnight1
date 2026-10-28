"""Crimson Knight: Earth-RED — New Gotham city kit: buildings, street infrastructure, props (Blender 4.2+/5.x).

Writes one GLB per asset to assets/models/kit/<id>.glb (buildings also <id>_lod1.glb) and
config/citykit.json (triangle counts, footprint, notes). Every asset: ground-centred origin, metres,
Owen's material PNGs + generated detail maps, simplified *_COL boxes. Buildings have flat, reachable
roofs. The dumpster's lid is a hinged pivot with a DumpsterLidOpen clip.

Run from the project root:  blender -b --factory-startup --python tools/blender/ck_build_citykit.py
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ck_lib as L  # noqa: E402

OUT = os.path.join(L.ROOT, "assets", "models", "kit")
REPORT = {}
random.seed(4)


def windows(root, prefix, face_center, width_axis, normal, w, h, cols, rows, z0, floor_h, win_w, win_h, lit=0.35, arched=False):
    """Grid of inset windows with frames on one facade. Lit ones glow warm (a few red)."""
    n = Vector(normal)
    a = Vector(width_axis)
    for r_ in range(rows):
        for c in range(cols):
            u = (c + 0.5) / cols - 0.5
            p = Vector(face_center) + a * (u * w) + Vector((0, 0, z0 + r_ * floor_h + floor_h * 0.55))
            roll = random.random()
            mat = "WindowLit" if roll < lit else ("WindowRed" if roll < lit + 0.05 else "Glass")
            rot = (0, 0, math.atan2(n.y, n.x) - math.pi / 2)
            L.box(f"{prefix}_win{r_}_{c}", (win_w, 0.08, win_h), tuple(p + n * 0.02), mat, root, bevel=0, rot=rot)
            L.box(f"{prefix}_sill{r_}_{c}", (win_w + 0.2, 0.18, 0.08), tuple(p + n * 0.08 - Vector((0, 0, win_h / 2 + 0.04))), "Concrete", root, bevel=0.01, rot=rot)
            if arched:
                L.extrude_outline(f"{prefix}_arch{r_}_{c}", [(-win_w / 2, 0), (win_w / 2, 0), (0, win_h * 0.35)], 0.1, "Concrete", root,
                                  tuple(p + n * 0.06 + Vector((0, 0, win_h / 2))), rot=(math.pi / 2, 0, rot[2]), axis="Z", bevel=0)


def building_shell(root, prefix, w, d, h, mat, roof_mat="Concrete", parapet=0.8):
    L.box(f"{prefix}_shell", (w, d, h), (0, 0, h / 2), mat, root, bevel=0.05)
    L.box(f"{prefix}_roof", (w - 0.2, d - 0.2, 0.25), (0, 0, h + 0.12), roof_mat, root, bevel=0.02)
    for k, (dims, loc) in enumerate((((w, 0.35, parapet), (0, d / 2 - 0.17, h + parapet / 2)), ((w, 0.35, parapet), (0, -d / 2 + 0.17, h + parapet / 2)),
                                     ((0.35, d, parapet), (w / 2 - 0.17, 0, h + parapet / 2)), ((0.35, d, parapet), (-w / 2 + 0.17, 0, h + parapet / 2)))):
        L.box(f"{prefix}_parapet{k}", dims, loc, mat, root, bevel=0.02)
    L.collider(prefix, (w, d, h), (0, 0, h / 2), root)


def rooftop_machinery(root, prefix, w, d, h):
    for i in range(3):
        x, y = random.uniform(-w / 3, w / 3), random.uniform(-d / 3, d / 3)
        L.box(f"{prefix}_ac{i}", (2.2, 1.4, 1.2), (x, y, h + 0.85), "Gunmetal", root, bevel=0.05)
        L.cyl(f"{prefix}_fan{i}", 0.5, 0.5, 0.1, (x, y, h + 1.5), "Black", root, segs=16)
    L.cyl(f"{prefix}_vent", 0.35, 0.35, 1.6, (w / 3, -d / 3, h + 1.0), "Gunmetal", root, segs=12)
    L.box(f"{prefix}_access", (2.5, 2.5, 2.8), (-w / 3, d / 3, h + 1.6), "Concrete", root, bevel=0.03)
    L.box(f"{prefix}_access_door", (1.0, 0.08, 2.1), (-w / 3, d / 3 - 1.27, h + 1.25), "Gunmetal", root, bevel=0.01)


# ======================================================================================
# buildings
# ======================================================================================
def gothic_tower():
    root = L.empty("gothic_tower")
    w = 14
    tiers = ((14, 0, 24), (11, 24, 16), (8, 40, 12))
    for i, (s, z0, hh) in enumerate(tiers):
        L.box(f"gt_tier{i}", (s, s, hh), (0, 0, z0 + hh / 2), "Brick", root, bevel=0.08)
        L.box(f"gt_cornice{i}", (s + 0.6, s + 0.6, 0.6), (0, 0, z0 + hh), "Concrete", root, bevel=0.06)
        for side in range(4):
            ang = side * math.pi / 2
            n = Vector((math.cos(ang), math.sin(ang), 0))
            a = Vector((-math.sin(ang), math.cos(ang), 0))
            windows(root, f"gt{i}_{side}", tuple(n * (s / 2)), tuple(a), tuple(n), s, hh, max(2, int(s / 3)), int(hh / 4), z0, 4, 1.2, 2.2, 0.3, arched=True)
        for cx in (-1, 1):  # corner buttresses
            for cy in (-1, 1):
                L.box(f"gt_butt{i}{cx}{cy}", (1.4, 1.4, hh), (cx * (s / 2 + 0.3), cy * (s / 2 + 0.3), z0 + hh / 2), "Concrete", root, bevel=0.06, taper_top=(0.7, 0.7))
                L.cyl(f"gt_pinnacle{i}{cx}{cy}", 0.6, 0.0, 3.2, (cx * (s / 2 + 0.3), cy * (s / 2 + 0.3), z0 + hh + 1.6), "Concrete", root, segs=4, bevel=0)
    L.cyl("gt_spire", 4.5, 0.05, 18, (0, 0, 52 + 9), "Gunmetal", root, segs=4, rot=(0, 0, math.pi / 4), bevel=0.02)
    L.box("gt_spire_light", (0.4, 0.4, 0.4), (0, 0, 70.2), "EmissiveRed", root, bevel=0.05)
    L.box("gt_door", (3.5, 0.5, 5), (0, -7.1, 2.5), "Black", root, bevel=0.05)
    L.box("gt_roof", (7.6, 7.6, 0.3), (0, 0, 52.15), "Concrete", root, bevel=0.02)
    for (s, z0, hh) in tiers:
        L.collider(f"gt_tier{z0}", (s, s, hh), (0, 0, z0 + hh / 2), root)
    return root, (w + 2, w + 2, 70)


def office_tower():
    root = L.empty("office_tower")
    w, d, h = 16, 16, 45
    L.box("ot_core", (w, d, h), (0, 0, h / 2), "Glass", root, bevel=0.05)
    for side in range(4):
        ang = side * math.pi / 2
        n = Vector((math.cos(ang), math.sin(ang), 0))
        a = Vector((-math.sin(ang), math.cos(ang), 0))
        for i in range(9):  # vertical mullions
            p = n * (w / 2 + 0.12) + a * ((i - 4) * (w / 8))
            L.box(f"ot_mull{side}_{i}", (0.25, 0.25, h), (p.x, p.y, h / 2), "Gunmetal", root, bevel=0.01, rot=(0, 0, ang))
        for j in range(12):  # floor bands, a few lit floors
            z = 3.6 * (j + 1)
            p = n * (w / 2 + 0.1)
            L.box(f"ot_band{side}_{j}", (w + 0.3, 0.3, 0.45), (p.x, p.y, z), "Concrete", root, bevel=0.01, rot=(0, 0, ang + math.pi / 2))
            if random.random() < 0.3:
                L.box(f"ot_lit{side}_{j}", (w * 0.9, 0.05, 2.4), (p.x * 1.0, p.y * 1.0, z - 1.6), "WindowLit", root, bevel=0, rot=(0, 0, ang + math.pi / 2))
    L.box("ot_lobby", (w + 0.6, d + 0.6, 4.5), (0, 0, 2.25), "Black", root, bevel=0.05)
    L.box("ot_lobby_glow", (6, 0.1, 3), (0, -d / 2 - 0.32, 2.0), "WindowLit", root, bevel=0)
    L.box("ot_roof", (w, d, 0.4), (0, 0, h + 0.2), "Concrete", root, bevel=0.02)
    rooftop_machinery(root, "ot", w, d, h + 0.4)
    L.cyl("ot_antenna", 0.12, 0.05, 12, (3, 3, h + 6.4), "Gunmetal", root, segs=8)
    L.box("ot_beacon", (0.3, 0.3, 0.3), (3, 3, h + 12.5), "EmissiveRed", root, bevel=0.02)
    L.collider("ot", (w + 0.6, d + 0.6, h + 0.4), (0, 0, (h + 0.4) / 2), root)
    return root, (w + 1, d + 1, h + 12)


def apartment():
    root = L.empty("apartment")
    w, d, h = 12, 10, 22
    building_shell(root, "ap", w, d, h, "Brick")
    for side, (n, a, ww) in enumerate((((0, -1, 0), (1, 0, 0), w), ((0, 1, 0), (1, 0, 0), w), ((1, 0, 0), (0, 1, 0), d), ((-1, 0, 0), (0, 1, 0), d))):
        windows(root, f"ap{side}", tuple(Vector(n) * ((d if abs(n[1]) else w) / 2)), a, n, ww, h, int(ww / 2.6), 6, 1.5, 3.4, 1.2, 1.7, 0.35)
    for f in range(1, 6):  # zig-zag fire escape on the front facade
        z = 1.5 + f * 3.4
        L.box(f"ap_fe_plat{f}", (5.0, 1.3, 0.08), (2.5, -d / 2 - 0.7, z), "Grate", root, bevel=0)
        L.box(f"ap_fe_rail{f}", (5.0, 0.05, 0.05), (2.5, -d / 2 - 1.33, z + 1.0), "Black", root, bevel=0)
        for px in (0.1, 2.5, 4.9):
            L.box(f"ap_fe_post{f}_{px}", (0.05, 0.05, 1.0), (px, -d / 2 - 1.33, z + 0.5), "Black", root, bevel=0)
        ang = 0.6 if f % 2 else -0.6
        L.box(f"ap_fe_stair{f}", (2.6, 0.7, 0.06), (2.5, -d / 2 - 0.9, z - 1.7), "Grate", root, bevel=0, rot=(0, ang, 0))
    for f in range(1, 6):  # balconies on the side
        L.box(f"ap_balc{f}", (0.9, 3.0, 0.15), (w / 2 + 0.45, 0, 1.5 + f * 3.4), "Concrete", root, bevel=0.02)
        L.box(f"ap_balc_rail{f}", (0.05, 3.0, 0.9), (w / 2 + 0.88, 0, 1.95 + f * 3.4), "Black", root, bevel=0)
    L.box("ap_awning", (4, 1.6, 0.15), (-2.5, -d / 2 - 0.8, 3.2), "CrimsonDark", root, bevel=0.03, rot=(0.15, 0, 0))
    L.box("ap_door", (1.6, 0.2, 2.5), (-2.5, -d / 2 - 0.05, 1.25), "Gunmetal", root, bevel=0.02)
    for i in range(4):  # rooftop water tower
        L.cyl(f"ap_wt_leg{i}", 0.1, 0.1, 3, (2 + (i % 2) * 2, 1 + (i // 2) * 2, h + 1.5), "Gunmetal", root, segs=6)
    L.cyl("ap_wt_tank", 1.6, 1.6, 3, (3, 2, h + 4.5), "Wood", root, segs=16)
    L.cyl("ap_wt_roof", 1.7, 0.1, 1.2, (3, 2, h + 6.6), "Gunmetal", root, segs=16)
    return root, (w + 2, d + 3, h + 7)


def warehouse():
    root = L.empty("warehouse")
    w, d, h = 24, 16, 9
    building_shell(root, "wh", w, d, h, "Gunmetal", parapet=0.4)
    for i in range(25):  # corrugation ribs
        x = -w / 2 + i * (w / 24)
        for y in (-d / 2 - 0.06, d / 2 + 0.06):
            L.box(f"wh_rib{i}_{y}", (0.12, 0.1, h), (x, y, h / 2), "Gunmetal", root, bevel=0)
    for i in range(3):  # roll-up doors + loading dock
        x = -7 + i * 7
        L.box(f"wh_door{i}", (4.5, 0.15, 5), (x, -d / 2 - 0.12, 2.5), "Concrete", root, bevel=0.02)
        for j in range(10):
            L.box(f"wh_door_slat{i}_{j}", (4.5, 0.17, 0.05), (x, -d / 2 - 0.12, 0.3 + j * 0.5), "Gunmetal", root, bevel=0)
        L.box(f"wh_door_light{i}", (0.6, 0.2, 0.15), (x, -d / 2 - 0.3, 5.6), "WindowLit", root, bevel=0)
    L.box("wh_dock", (w - 2, 2.5, 1.2), (0, -d / 2 - 1.3, 0.6), "Concrete", root, bevel=0.03)
    L.collider("wh_dock", (w - 2, 2.5, 1.2), (0, -d / 2 - 1.3, 0.6), root)
    for i in range(4):
        L.box(f"wh_skylight{i}", (3, 2, 0.4), (-9 + i * 6, 0, h + 0.4), "Glass", root, bevel=0.05)
        L.cyl(f"wh_vent{i}", 0.5, 0.4, 1.4, (-9 + i * 6, 4, h + 0.9), "Gunmetal", root, segs=10)
    L.text_mesh("wh_sign", "OWEN ENTERPRISES LOGISTICS", 0.9, (0, -d / 2 - 0.2, 7.4), "Neon", root, rot=L.deg(90, 0, 0))
    return root, (w, d + 4, h + 2)


def shopfront():
    root = L.empty("shopfront")
    w, d, h = 10, 10, 8
    building_shell(root, "sh", w, d, h, "Brick")
    L.box("sh_window", (7, 0.1, 3), (0, -d / 2 - 0.06, 2.2), "WindowLit", root, bevel=0)
    L.box("sh_window_frame", (7.3, 0.2, 0.15), (0, -d / 2 - 0.1, 3.75), "Black", root, bevel=0)
    L.box("sh_awning", (8, 1.8, 0.12), (0, -d / 2 - 0.9, 4.2), "Crimson", root, bevel=0.03, rot=(0.25, 0, 0))
    L.text_mesh("sh_neon", "NIGHT OWL DINER", 0.7, (0, -d / 2 - 0.15, 5.6), "Neon", root, rot=L.deg(90, 0, 0))
    windows(root, "sh_up", (0, -d / 2, 0), (1, 0, 0), (0, -1, 0), w, h, 3, 1, 4.2, 3.4, 1.4, 1.6, 0.5)
    return root, (w, d + 2, h + 1)


# ======================================================================================
# street infrastructure
# ======================================================================================
def traffic_light():
    root = L.empty("traffic_light")
    L.cyl("tl_pole", 0.12, 0.1, 5.5, (0, 0, 2.75), "Gunmetal", root, segs=12)
    L.box("tl_arm", (4.5, 0.15, 0.15), (2.2, 0, 5.3), "Gunmetal", root, bevel=0.02)
    for x in (2.5, 4.2):
        L.box(f"tl_head{x}", (0.35, 0.3, 1.0), (x, 0, 4.7), "Black", root, bevel=0.04)
        for i, mat in enumerate(("EmissiveRed", "Black", "Black")):
            L.cyl(f"tl_lamp{x}{i}", 0.1, 0.1, 0.05, (x, -0.17, 5.0 - i * 0.3), mat, root, L.deg(90, 0, 0), segs=12)
    L.box("tl_sign", (0.8, 0.04, 0.25), (1.0, 0, 4.9), "Paint", root, bevel=0.01)
    L.collider("tl", (0.3, 0.3, 5.5), (0, 0, 2.75), root)
    return root, (5, 0.5, 5.6)


def streetlight():
    root = L.empty("streetlight")
    L.cyl("sl_base", 0.25, 0.18, 0.6, (0, 0, 0.3), "Gunmetal", root, segs=12)
    L.cyl("sl_pole", 0.09, 0.07, 6.5, (0, 0, 3.6), "Gunmetal", root, segs=10)
    L.box("sl_arm", (1.8, 0.1, 0.1), (0.85, 0, 6.85), "Gunmetal", root, bevel=0.02, rot=(0, -0.12, 0))
    L.box("sl_head", (0.8, 0.35, 0.18), (1.75, 0, 6.75), "Black", root, bevel=0.04)
    L.box("sl_lamp", (0.65, 0.28, 0.03), (1.75, 0, 6.65), "WindowLit", root, bevel=0)
    L.collider("sl", (0.4, 0.4, 7), (0, 0, 3.5), root)
    return root, (2.2, 0.5, 7)


def crosswalk():
    root = L.empty("crosswalk")
    for i in range(8):
        L.box(f"cw_stripe{i}", (0.5, 3.6, 0.02), (-3.5 + i, 0, 0.16), "Paint", root, bevel=0)
    return root, (8, 3.6, 0.2)


def street_sign():
    root = L.empty("street_sign")
    L.cyl("ss_pole", 0.05, 0.05, 3, (0, 0, 1.5), "Gunmetal", root, segs=8)
    L.box("ss_plate", (1.1, 0.03, 0.28), (0.4, 0, 2.85), "Plant", root, bevel=0.01)
    L.text_mesh("ss_text", "CRIMSON AVE", 0.12, (0.4, -0.02, 2.85), "Paint", root, rot=L.deg(90, 0, 0), extrude=0.003)
    L.box("ss_stop", (0.6, 0.03, 0.6), (0, 0, 2.3), "Crimson", root, bevel=0.15)
    return root, (1.2, 0.3, 3)


def bus_shelter():
    root = L.empty("bus_shelter")
    L.box("bs_roof", (4.2, 1.8, 0.12), (0, 0, 2.5), "Gunmetal", root, bevel=0.03)
    for x in (-2, 2):
        L.box(f"bs_post{x}", (0.1, 0.1, 2.5), (x, 0.8, 1.25), "Gunmetal", root, bevel=0.01)
    L.box("bs_back", (4.0, 0.05, 1.9), (0, 0.85, 1.35), "Glass", root, bevel=0)
    L.box("bs_ad", (1.2, 0.08, 1.8), (2.05, 0.2, 1.35), "WindowRed", root, bevel=0.01)
    L.box("bs_bench", (3.0, 0.45, 0.08), (-0.3, 0.55, 0.45), "Wood", root, bevel=0.01)
    L.collider("bs", (4.2, 1.8, 2.5), (0, 0, 1.25), root)
    return root, (4.3, 1.9, 2.6)


def manhole():
    root = L.empty("manhole")
    L.cyl("mh_cover", 0.4, 0.4, 0.04, (0, 0, 0.02), "Gunmetal", root, segs=24)
    for i in range(4):
        L.box(f"mh_ridge{i}", (0.7, 0.03, 0.02), (0, -0.2 + i * 0.13, 0.045), "Black", root, bevel=0)
    return root, (0.8, 0.8, 0.05)


def drain():
    root = L.empty("drain")
    L.box("dr_frame", (0.9, 0.5, 0.06), (0, 0, 0.03), "Gunmetal", root, bevel=0.01)
    for i in range(8):
        L.box(f"dr_bar{i}", (0.04, 0.42, 0.04), (-0.38 + i * 0.11, 0, 0.06), "Black", root, bevel=0)
    return root, (0.9, 0.5, 0.07)


# ======================================================================================
# props
# ======================================================================================
def dumpster():
    root = L.empty("dumpster")
    W, D, H, t = 1.9, 1.15, 1.25, 0.05
    L.box("dp_floor", (W, D, t), (0, 0, 0.22), "Plant", root, bevel=0.01)
    for name, dims, loc in (("front", (W, t, H), (0, -D / 2, 0.2 + H / 2)), ("back", (W, t, H * 1.08), (0, D / 2, 0.2 + H * 0.54)),
                            ("left", (t, D, H), (-W / 2, 0, 0.2 + H / 2)), ("right", (t, D, H), (W / 2, 0, 0.2 + H / 2))):
        L.box(f"dp_wall_{name}", dims, loc, "Plant", root, bevel=0.01)  # real wall thickness, open cavity
    L.box("dp_rim", (W + 0.08, D + 0.08, 0.06), (0, 0, 0.2 + H), "Gunmetal", root, bevel=0.01)
    L.box("dp_rim_inner", (W - 0.1, D - 0.1, 0.07), (0, 0, 0.2 + H), "Black", root, bevel=0)  # visual inner lip
    for k in (-1, 1):
        L.cyl(f"dp_hinge{k}", 0.035, 0.035, 0.18, (k * 0.6, D / 2 + 0.04, 0.2 + H * 1.08), "Gunmetal", root, L.deg(0, 90, 0), segs=10)
        L.box(f"dp_handle{k}", (0.06, 0.12, 0.05), (k * (W / 2 + 0.06), 0, 0.2 + H * 0.7), "Gunmetal", root, bevel=0.01)
        L.box(f"dp_pocket{k}", (0.3, 0.12, 0.15), (k * 0.55, -D / 2 - 0.06, 0.45), "Gunmetal", root, bevel=0.01)  # fork pockets
        for y in (-1, 1):
            L.cyl(f"dp_wheel{k}{y}", 0.1, 0.1, 0.06, (k * 0.8, y * 0.4, 0.1), "Rubber", root, L.deg(0, 90, 0), segs=12)
    lid = L.empty("Lid", (0, D / 2 + 0.04, 0.2 + H * 1.08), root)  # hinge line at the back
    L.box("dp_lid", (W + 0.04, D + 0.06, 0.05), (0, -(D + 0.06) / 2, 0.0), "Black", lid, bevel=0.02, rot=(-0.08, 0, 0))
    for i in range(3):
        L.box(f"dp_rust{i}", (random.uniform(0.2, 0.5), 0.005, random.uniform(0.1, 0.3)), (random.uniform(-0.7, 0.7), -D / 2 - t / 2 - 0.003, random.uniform(0.4, 1.2)),
              "Bark", root, bevel=0)  # weathering patches
    L.clip(lid, "DumpsterLidOpen", [(0, (0, 0, 0)), (20, L.deg(105, 0, 0))])
    L.collider("dp", (W, D, H + 0.2), (0, 0, (H + 0.2) / 2), root)
    return root, (W + 0.2, D + 0.2, 1.6)


def trash_can():
    root = L.empty("trash_can")
    L.cyl("tc_body", 0.28, 0.25, 0.85, (0, 0, 0.43), "Gunmetal", root, segs=20, cap=True)
    for i in range(10):
        a = 2 * math.pi * i / 10
        L.box(f"tc_rib{i}", (0.03, 0.03, 0.8), (math.cos(a) * 0.27, math.sin(a) * 0.27, 0.43), "Black", root, bevel=0)
    L.cyl("tc_lid", 0.31, 0.22, 0.12, (0, 0, 0.92), "Black", root, segs=20)
    L.collider("tc", (0.56, 0.56, 0.98), (0, 0, 0.49), root)
    return root, (0.6, 0.6, 1.0)


def recycling_bin():
    root = L.empty("recycling_bin")
    L.box("rb_body", (0.6, 0.7, 0.95), (0, 0, 0.48), "Plant", root, bevel=0.04, taper_top=(1.05, 1.05))
    L.box("rb_lid", (0.66, 0.76, 0.06), (0, 0, 0.98), "Gunmetal", root, bevel=0.02)
    L.box("rb_label", (0.35, 0.01, 0.2), (0, -0.36, 0.65), "Paint", root, bevel=0)
    for k in (-1, 1):
        L.cyl(f"rb_wheel{k}", 0.08, 0.08, 0.05, (k * 0.25, 0.3, 0.08), "Rubber", root, L.deg(0, 90, 0), segs=12)
    L.collider("rb", (0.62, 0.72, 1.0), (0, 0, 0.5), root)
    return root, (0.7, 0.8, 1.0)


def garbage_bag():
    root = L.empty("garbage_bag")
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=0.35)
    for v in bm.verts:
        p = v.co.copy()
        v.co = Vector((p.x, p.y * 0.9, max(p.z, -0.15) * 1.1)) * (1 + noise.noise(p * 6) * 0.12)
    L.obj_from_bm("gb_bag", bm, "Black", root, (0, 0, 0.32))
    L.cyl("gb_tie", 0.05, 0.02, 0.15, (0, 0, 0.72), "Black", root, segs=8)
    return root, (0.7, 0.65, 0.8)


def cardboard_box():
    root = L.empty("cardboard_box")
    L.box("cb_body", (0.6, 0.45, 0.4), (0, 0, 0.2), "Cardboard", root, bevel=0.01)
    L.box("cb_tape", (0.62, 0.08, 0.005), (0, 0, 0.402), "Fabric", root, bevel=0)
    for k in (-1, 1):
        L.box(f"cb_flap{k}", (0.6, 0.22, 0.01), (0, k * 0.22, 0.43), "Cardboard", root, bevel=0, rot=(-k * 0.5, 0, 0))
    L.collider("cb", (0.6, 0.45, 0.4), (0, 0, 0.2), root)
    return root, (0.6, 0.6, 0.5)


def bench():
    root = L.empty("bench")
    for k in (-1, 1):
        L.extrude_outline(f"bn_frame{k}", [(-0.3, 0), (-0.2, 0), (-0.15, 0.42), (0.25, 0.42), (0.25, 0.47), (0.3, 0.9), (0.24, 0.9), (0.18, 0.5), (-0.25, 0.5)],
                          0.06, "Black", root, (k * 0.85, 0, 0), axis="X", bevel=0.005)
    for i in range(4):
        L.box(f"bn_seat{i}", (1.9, 0.09, 0.04), (0, -0.14 + i * 0.1, 0.48), "Wood", root, bevel=0.01)
    for i in range(3):
        L.box(f"bn_back{i}", (1.9, 0.04, 0.09), (0, 0.24 + i * 0.015, 0.6 + i * 0.12), "Wood", root, bevel=0.01, rot=(0.25, 0, 0))
    L.collider("bn", (1.9, 0.6, 0.9), (0, 0, 0.45), root)
    return root, (2, 0.7, 0.95)


def mailbox():
    root = L.empty("mailbox")
    L.box("mb_body", (0.5, 0.55, 0.7), (0, 0, 0.75), "CrimsonDark", root, bevel=0.04)
    L.cyl("mb_top", 0.25, 0.25, 0.55, (0, 0, 1.1), "CrimsonDark", root, L.deg(90, 0, 0), segs=20)
    L.box("mb_slot", (0.3, 0.02, 0.04), (0, -0.28, 1.0), "Black", root, bevel=0)
    for kx in (-1, 1):
        for ky in (-1, 1):
            L.box(f"mb_leg{kx}{ky}", (0.05, 0.05, 0.4), (kx * 0.2, ky * 0.22, 0.2), "Gunmetal", root, bevel=0.005)
    L.collider("mb", (0.5, 0.55, 1.35), (0, 0, 0.67), root)
    return root, (0.55, 0.6, 1.4)


def hydrant():
    root = L.empty("hydrant")
    L.cyl("hy_base", 0.2, 0.2, 0.1, (0, 0, 0.05), "Crimson", root, segs=16)
    L.cyl("hy_body", 0.14, 0.15, 0.55, (0, 0, 0.37), "Crimson", root, segs=16)
    L.cyl("hy_cap", 0.15, 0.05, 0.18, (0, 0, 0.73), "Crimson", root, segs=16)
    for k in (-1, 1):
        L.cyl(f"hy_nozzle{k}", 0.06, 0.06, 0.12, (k * 0.18, 0, 0.45), "Gunmetal", root, L.deg(0, 90, 0), segs=12)
    L.cyl("hy_front", 0.08, 0.08, 0.12, (0, -0.18, 0.4), "Gunmetal", root, L.deg(90, 0, 0), segs=12)
    L.collider("hy", (0.35, 0.35, 0.8), (0, 0, 0.4), root)
    return root, (0.45, 0.4, 0.85)


def vending_machine():
    root = L.empty("vending_machine")
    L.box("vm_body", (0.9, 0.8, 1.9), (0, 0, 0.95), "Crimson", root, bevel=0.03)
    L.box("vm_glass", (0.55, 0.02, 1.2), (-0.12, -0.41, 1.15), "Glass", root, bevel=0)
    for i in range(5):
        L.box(f"vm_row{i}", (0.5, 0.02, 0.03), (-0.12, -0.39, 0.65 + i * 0.25), "WindowLit", root, bevel=0)
    L.box("vm_panel", (0.2, 0.02, 0.5), (0.3, -0.41, 1.3), "Screen", root, bevel=0)
    L.box("vm_tray", (0.5, 0.05, 0.15), (-0.12, -0.42, 0.3), "Black", root, bevel=0.01)
    L.collider("vm", (0.9, 0.8, 1.9), (0, 0, 0.95), root)
    return root, (0.95, 0.85, 1.95)


def utility_cabinet():
    root = L.empty("utility_cabinet")
    L.box("uc_body", (1.0, 0.5, 1.4), (0, 0, 0.75), "Gunmetal", root, bevel=0.02)
    L.box("uc_plinth", (1.05, 0.55, 0.1), (0, 0, 0.05), "Concrete", root, bevel=0.01)
    L.box("uc_seam", (0.02, 0.52, 1.3), (0, 0, 0.75), "Black", root, bevel=0)
    for k in (-1, 1):
        L.box(f"uc_vent{k}", (0.3, 0.52, 0.12), (k * 0.25, 0, 1.3), "Black", root, bevel=0)
    L.box("uc_warning", (0.2, 0.01, 0.15), (0.25, -0.26, 1.0), "Paint", root, bevel=0)
    L.collider("uc", (1.0, 0.5, 1.45), (0, 0, 0.72), root)
    return root, (1.1, 0.6, 1.5)


def traffic_cone():
    root = L.empty("traffic_cone")
    L.box("cn_base", (0.4, 0.4, 0.04), (0, 0, 0.02), "Black", root, bevel=0.02)
    L.cyl("cn_body", 0.15, 0.025, 0.7, (0, 0, 0.39), "Crimson", root, segs=16)
    L.cyl("cn_band", 0.11, 0.08, 0.12, (0, 0, 0.42), "Paint", root, segs=16)
    L.collider("cn", (0.35, 0.35, 0.75), (0, 0, 0.37), root)
    return root, (0.4, 0.4, 0.75)


def jersey_barrier():
    root = L.empty("jersey_barrier")
    L.extrude_outline("jb_body", [(-0.3, 0), (0.3, 0), (0.25, 0.08), (0.1, 0.3), (0.08, 0.8), (-0.08, 0.8), (-0.1, 0.3), (-0.25, 0.08)],
                      3.0, "Concrete", root, (0, 0, 0), axis="Y", bevel=0.01)
    L.box("jb_stripe", (3.0, 0.01, 0.12), (0, -0.095, 0.6), "Crimson", root, bevel=0)
    L.collider("jb", (3.0, 0.6, 0.8), (0, 0, 0.4), root)
    return root, (3.0, 0.6, 0.8)


def fence():
    root = L.empty("fence")
    for i in range(4):
        L.cyl(f"fn_post{i}", 0.04, 0.04, 2.2, (-3 + i * 2, 0, 1.1), "Gunmetal", root, segs=8)
    for z in (0.1, 2.1):
        L.cyl(f"fn_rail{z}", 0.025, 0.025, 6, (0, 0, z), "Gunmetal", root, L.deg(0, 90, 0), segs=8)
    L.box("fn_mesh", (6, 0.01, 2.0), (0, 0, 1.1), "Grate", root, bevel=0)
    L.collider("fn", (6, 0.1, 2.2), (0, 0, 1.1), root)
    return root, (6, 0.2, 2.2)


def pallet():
    root = L.empty("pallet")
    for i in range(7):
        L.box(f"pl_top{i}", (1.2, 0.1, 0.022), (0, -0.45 + i * 0.15, 0.133), "Wood", root, bevel=0.003)
    for i in range(3):
        L.box(f"pl_strut{i}", (1.2, 0.1, 0.1), (0, -0.45 + i * 0.45, 0.07), "Wood", root, bevel=0.005)
    for i in range(3):
        L.box(f"pl_bot{i}", (1.2, 0.1, 0.02), (0, -0.45 + i * 0.45, 0.01), "Wood", root, bevel=0.003)
    L.collider("pl", (1.2, 1.0, 0.145), (0, 0, 0.072), root)
    return root, (1.2, 1.0, 0.15)


def shipping_container():
    root = L.empty("shipping_container")
    w, d, h = 6.06, 2.44, 2.59
    L.box("sc_body", (w, d, h), (0, 0, h / 2), "CrimsonDark", root, bevel=0.03)
    for i in range(30):
        x = -w / 2 + 0.15 + i * (w - 0.3) / 29
        for y in (-d / 2 - 0.02, d / 2 + 0.02):
            L.box(f"sc_rib{i}_{y}", (0.06, 0.04, h - 0.2), (x, y, h / 2), "CrimsonDark", root, bevel=0)
    for k in (-1, 1):
        L.box(f"sc_door{k}", (0.05, d / 2 - 0.05, h - 0.2), (w / 2 + 0.02, k * d / 4, h / 2), "Crimson", root, bevel=0.01)
        for j in (-1, 1):
            L.cyl(f"sc_bar{k}{j}", 0.025, 0.025, h - 0.3, (w / 2 + 0.06, k * d / 4 + j * 0.2, h / 2), "Gunmetal", root, segs=8)
    L.text_mesh("sc_logo", "OWEN ENTERPRISES", 0.32, (0, -d / 2 - 0.05, h * 0.62), "Paint", root, rot=L.deg(90, 0, 0), extrude=0.005)
    L.collider("sc", (w, d, h), (0, 0, h / 2), root)
    return root, (w, d, h)


def toolbox():
    root = L.empty("toolbox")
    L.box("tb_body", (0.5, 0.22, 0.22), (0, 0, 0.11), "Crimson", root, bevel=0.02)
    L.box("tb_lid", (0.5, 0.22, 0.05), (0, 0, 0.245), "CrimsonDark", root, bevel=0.015)
    L.box("tb_handle", (0.28, 0.03, 0.06), (0, 0, 0.3), "Black", root, bevel=0.01)
    for k in (-1, 1):
        L.box(f"tb_latch{k}", (0.04, 0.01, 0.05), (k * 0.17, -0.115, 0.2), "Gunmetal", root, bevel=0)
    return root, (0.5, 0.25, 0.33)


def generator():
    root = L.empty("generator")
    L.box("gn_skid", (2.4, 1.2, 0.15), (0, 0, 0.075), "Gunmetal", root, bevel=0.02)
    L.box("gn_body", (1.8, 1.0, 1.1), (-0.15, 0, 0.7), "Plant", root, bevel=0.05)
    L.cyl("gn_tank", 0.35, 0.35, 0.9, (0.85, 0, 0.55), "Gunmetal", root, L.deg(90, 0, 0), segs=16)
    L.cyl("gn_exhaust", 0.07, 0.07, 0.6, (-0.6, 0.3, 1.5), "Black", root, segs=8)
    for i in range(6):
        L.box(f"gn_louvre{i}", (0.02, 0.9, 0.05), (-1.06, 0, 0.4 + i * 0.12), "Black", root, bevel=0)
    L.box("gn_panel", (0.3, 0.02, 0.25), (0.3, -0.51, 0.95), "Screen", root, bevel=0)
    L.collider("gn", (2.4, 1.2, 1.3), (0, 0, 0.65), root)
    return root, (2.4, 1.2, 1.6)


def terminal():
    root = L.empty("terminal")
    L.box("tm_base", (0.6, 0.5, 1.0), (0, 0, 0.5), "Gunmetal", root, bevel=0.03, taper_top=(0.9, 0.8))
    L.box("tm_head", (0.65, 0.2, 0.55), (0, -0.05, 1.3), "Black", root, bevel=0.03, rot=(-0.25, 0, 0))
    L.box("tm_screen", (0.5, 0.02, 0.38), (0, -0.16, 1.32), "Screen", root, bevel=0, rot=(-0.25, 0, 0))
    L.box("tm_keys", (0.5, 0.25, 0.03), (0, -0.25, 0.98), "Black", root, bevel=0.01, rot=(0.3, 0, 0))
    L.collider("tm", (0.65, 0.5, 1.6), (0, 0, 0.8), root)
    return root, (0.7, 0.55, 1.6)


def office_desk():
    root = L.empty("office_desk")
    L.box("od_top", (1.6, 0.8, 0.04), (0, 0, 0.75), "Wood", root, bevel=0.01)
    for kx in (-1, 1):
        L.box(f"od_leg{kx}", (0.05, 0.7, 0.73), (kx * 0.75, 0, 0.365), "Gunmetal", root, bevel=0.005)
    L.box("od_drawers", (0.45, 0.65, 0.6), (0.5, 0, 0.42), "Gunmetal", root, bevel=0.01)
    L.box("od_monitor", (0.6, 0.03, 0.38), (0, 0.25, 1.0), "Screen", root, bevel=0.01)
    L.box("od_chair_seat", (0.5, 0.5, 0.08), (0, -0.65, 0.48), "Black", root, bevel=0.03)
    L.box("od_chair_back", (0.48, 0.06, 0.55), (0, -0.88, 0.8), "Black", root, bevel=0.03)
    L.cyl("od_chair_post", 0.03, 0.03, 0.4, (0, -0.65, 0.24), "Gunmetal", root, segs=8)
    L.collider("od", (1.6, 0.8, 0.78), (0, 0, 0.39), root)
    return root, (1.6, 1.6, 1.3)


def sofa():
    root = L.empty("sofa")
    L.box("sf_base", (2.0, 0.85, 0.42), (0, 0, 0.21), "Fabric", root, bevel=0.06)
    L.box("sf_back", (2.0, 0.22, 0.5), (0, 0.33, 0.6), "Fabric", root, bevel=0.07)
    for k in (-1, 1):
        L.box(f"sf_arm{k}", (0.2, 0.85, 0.3), (k * 0.92, 0, 0.55), "Fabric", root, bevel=0.06)
        L.box(f"sf_cushion{k}", (0.85, 0.65, 0.12), (k * 0.43, -0.05, 0.48), "Fabric", root, bevel=0.05)
    L.collider("sf", (2.0, 0.85, 0.85), (0, 0, 0.42), root)
    return root, (2.0, 0.9, 0.9)


def street_tree():
    root = L.empty("street_tree")
    L.cyl("tr_trunk", 0.18, 0.12, 3.2, (0, 0, 1.6), "Bark", root, segs=10)
    for i in range(5):
        a = i * 1.3
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
        for v in bm.verts:
            v.co *= 1 + noise.noise(v.co * 3 + Vector((i, i, i))) * 0.25
        L.obj_from_bm(f"tr_canopy{i}", bm, "Plant", root, (math.cos(a) * 0.7, math.sin(a) * 0.7, 3.4 + (i % 2) * 0.6)).scale = (1.3, 1.3, 1.0)
    L.cyl("tr_grate", 0.7, 0.7, 0.04, (0, 0, 0.02), "Gunmetal", root, segs=16)
    L.collider("tr", (0.4, 0.4, 3.0), (0, 0, 1.5), root)
    return root, (3.2, 3.2, 5)


def bush():
    root = L.empty("bush")
    for i in range(3):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.5)
        for v in bm.verts:
            v.co *= 1 + noise.noise(v.co * 4 + Vector((i, 0, 0))) * 0.2
        L.obj_from_bm(f"bu_{i}", bm, "Plant", root, (-0.4 + i * 0.4, (i % 2) * 0.2, 0.4))
    return root, (1.4, 0.9, 0.9)


def rock(seed=0, name="rock", scale=(1.6, 1.2, 1.0)):
    root = L.empty(name)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    for v in bm.verts:
        p = v.co.copy()
        d = 1 + noise.fractal(p * 1.8 + Vector((seed, seed, seed)), 0.6, 2.0, 4) * 0.3
        v.co = Vector((p.x * scale[0], p.y * scale[1], max(p.z, -0.2) * scale[2])) * d
    L.obj_from_bm(name + "_mesh", bm, "Stone", root, (0, 0, 0.2 * scale[2]))
    L.collider(name, (scale[0] * 1.6, scale[1] * 1.6, scale[2] * 1.2), (0, 0, scale[2] * 0.6), root)
    return root, (scale[0] * 2, scale[1] * 2, scale[2] * 1.4)


def cave_formation():
    root = L.empty("cave_formation")
    for i in range(6):
        h = random.uniform(1.2, 4)
        L.cyl(f"cf_stalag{i}", random.uniform(0.3, 0.7), 0.03, h, (random.uniform(-1.5, 1.5), random.uniform(-1.5, 1.5), h / 2), "Stone", root, segs=7, bevel=0)
    return root, (3.5, 3.5, 4)


ASSETS = [
    ("gothic_tower", gothic_tower, True), ("office_tower", office_tower, True), ("apartment", apartment, True),
    ("warehouse", warehouse, True), ("shopfront", shopfront, True),
    ("traffic_light", traffic_light, False), ("streetlight", streetlight, False), ("crosswalk", crosswalk, False),
    ("street_sign", street_sign, False), ("bus_shelter", bus_shelter, False), ("manhole", manhole, False), ("drain", drain, False),
    ("dumpster", dumpster, False), ("trash_can", trash_can, False), ("recycling_bin", recycling_bin, False),
    ("garbage_bag", garbage_bag, False), ("cardboard_box", cardboard_box, False), ("bench", bench, False),
    ("mailbox", mailbox, False), ("hydrant", hydrant, False), ("vending_machine", vending_machine, False),
    ("utility_cabinet", utility_cabinet, False), ("traffic_cone", traffic_cone, False), ("jersey_barrier", jersey_barrier, False),
    ("fence", fence, False), ("pallet", pallet, False), ("shipping_container", shipping_container, False),
    ("toolbox", toolbox, False), ("generator", generator, False), ("terminal", terminal, False),
    ("office_desk", office_desk, False), ("sofa", sofa, False), ("street_tree", street_tree, False), ("bush", bush, False),
    ("rock", lambda: rock(), False), ("cave_formation", cave_formation, False),
]


def main():
    for name, fn, lod in ASSETS:
        L.reset()
        root, size = fn()
        bpy.context.view_layer.update()
        objs = L.descendants(root)
        anim = any(o.animation_data and len(o.animation_data.nla_tracks) for o in objs)
        L.export(os.path.join(OUT, f"kit_{name}.glb"), anim, objs)
        info = {"file": f"assets/models/kit/kit_{name}.glb", "triangles": L.tri_count(objs), "size_m": [round(v, 2) for v in size]}
        if lod:
            lo = L.static_lod(objs, 0.3, f"{name}_LOD1")
            L.export(os.path.join(OUT, f"kit_{name}_lod1.glb"), False, [lo])
            info["triangles_lod1"] = L.tri_count([lo])
        REPORT[name] = info
        print(f"[citykit] {name}: {info['triangles']} tris")
    with open(os.path.join(L.ROOT, "config", "citykit.json"), "w") as fh:
        json.dump(REPORT, fh, indent=2)
    print(f"[citykit] OK {len(REPORT)} assets")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
