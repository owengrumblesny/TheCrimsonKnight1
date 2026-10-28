"""Crimson Knight: Earth-RED — the three signature vehicles (Blender 4.2+/5.x).

  CR-X1 Crimson Interceptor   assets/models/vehicles/crx1_interceptor.glb  (+ _lod1.glb)
  CR-B1 Crimson Batcycle      assets/models/vehicles/crb1_batcycle.glb     (+ _lod1.glb)
  CR-A1 Crimson Specter       assets/models/vehicles/cra1_specter.glb      (+ _lod1.glb)

Each model: lofted armoured body + separate moving parts on named pivot empties (wheels, steering,
suspension, doors/canopy, transformation panels, landing gear, control surfaces, VTOL nacelles),
anchor empties (seat_attach, entry/exit, camera, summon, sound), simplified *_COL collision boxes,
glTF clips (NLA tracks) for the moving parts, and a merged, decimated LOD1 file for distance.
Driving / flight physics are NOT implemented (asset-preparation phase).

Run from the project root:  blender -b --factory-startup --python tools/blender/ck_build_vehicles.py
Blender: Z up, vehicle front = -Y (exports to +Z forward, matching the hero).
"""
import json
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ck_lib as L  # noqa: E402

OUT = os.path.join(L.ROOT, "assets", "models", "vehicles")
REPORT = {}


def wheel(name, parent, loc, radius, width, rim_glow=True, spokes=6):
    """Wheel pivot at the hub: tyre with tread blocks, gunmetal rim + spokes, optional red rim ring."""
    piv = L.empty(name, loc, parent)
    ax = L.deg(0, 90, 0)  # cylinder axis along X
    L.cyl(name + "_tyre", radius, radius, width, (0, 0, 0), "Rubber", piv, ax, segs=36, bevel=0.04)
    for i in range(18):  # tread blocks
        a = 2 * 3.14159 * i / 18
        L.box(f"{name}_tread{i}", (width * 0.94, 0.09, 0.055), (0, radius * 0.99 * __import__("math").cos(a), radius * 0.99 * __import__("math").sin(a)),
              "Rubber", piv, bevel=0.008, rot=(a, 0, 0))
    L.cyl(name + "_rim", radius * 0.68, radius * 0.68, width * 1.02, (0, 0, 0), "Gunmetal", piv, ax, segs=32, bevel=0.015)
    L.cyl(name + "_hub", radius * 0.18, radius * 0.18, width * 1.08, (0, 0, 0), "Crimson", piv, ax, segs=16)
    import math
    for i in range(spokes):
        a = 2 * math.pi * i / spokes
        L.box(f"{name}_spoke{i}", (width * 0.2, 0.05, radius * 0.5), (width * 0.48, math.cos(a) * radius * 0.4, math.sin(a) * radius * 0.4),
              "Black", piv, bevel=0.01, rot=(a - math.pi / 2, 0, 0))
    if rim_glow:
        L.torus(name + "_glow", radius * 0.7, 0.012, (width * 0.52, 0, 0), "EmissiveRed", piv, L.deg(0, 90, 0))
        L.torus(name + "_glow2", radius * 0.7, 0.012, (-width * 0.52, 0, 0), "EmissiveRed", piv, L.deg(0, 90, 0))
    return piv


# ======================================================================================
# CR-X1 Crimson Interceptor (~6 m armoured pursuit car)
# ======================================================================================
def build_crx1():
    root = L.empty("CRX1_Interceptor", (0, 0, 0))
    body = L.empty("Body", (0, 0, 0), root)
    sections = [
        (-3.0, [(0, .32), (.72, .32), (.9, .44), (.82, .6), (.5, .64), (0, .64)]),
        (-2.3, [(0, .26), (1.0, .26), (1.16, .55), (1.06, .84), (.62, .9), (0, .92)]),
        (-1.1, [(0, .25), (1.05, .25), (1.22, .6), (1.12, .96), (.72, 1.08), (0, 1.1)]),
        (0.4, [(0, .25), (1.07, .25), (1.26, .62), (1.17, 1.0), (.76, 1.15), (0, 1.16)]),
        (1.6, [(0, .28), (1.12, .28), (1.32, .7), (1.22, 1.06), (.8, 1.2), (0, 1.2)]),
        (2.6, [(0, .36), (1.02, .36), (1.22, .76), (1.12, 1.1), (.7, 1.15), (0, 1.15)]),
        (3.0, [(0, .46), (.82, .46), (.96, .76), (.9, 1.0), (.6, 1.05), (0, 1.05)]),
    ]
    L.loft("X1_hull", sections, "Crimson", body, bevel=0.025)
    L.loft("X1_underbody", [(-2.6, [(0, .18), (.85, .18), (.95, .3), (0, .3)]), (2.7, [(0, .2), (.9, .2), (1.0, .34), (0, .34)])],
           "Black", body)
    # armour plates layered on the hull: hood, fenders, side skirts, rear deck
    L.box("X1_hood", (1.3, 1.4, 0.06), (0, -2.15, 0.83), "Crimson", body, bevel=0.03, rot=L.deg(-14, 0, 0))
    L.box("X1_hood_vent", (0.5, 0.6, 0.05), (0, -2.0, 0.88), "Black", body, bevel=0.02, rot=L.deg(-14, 0, 0))
    # faceted armour plates layered over the hull (angled, overlapping — the concept's plated look)
    for i, (y, w, z, tilt) in enumerate(((-1.5, 1.7, 0.98, -10), (-0.6, 1.9, 1.08, 4), (0.5, 2.0, 1.12, -4), (1.4, 2.1, 1.14, 6), (2.3, 1.8, 1.1, -8))):
        L.box(f"X1_plate{i}", (w, 0.75, 0.07), (0, y, z), "Crimson" if i % 2 else "CrimsonDark", body, bevel=0.025, rot=L.deg(tilt, 0, 0))
    for k in (1, -1):  # angular wheel-arch armour (side-profile outlines extruded across the wheel)
        L.extrude_outline(f"X1_arch_F{k}", [(-2.75, 0.55), (-2.55, 1.15), (-1.95, 1.32), (-1.2, 1.2), (-1.0, 0.75), (-1.35, 1.05), (-1.95, 1.15), (-2.45, 0.95)],
                          0.62, "Crimson", body, (k * 1.5, 0, 0), axis="X", bevel=0.03)
        L.extrude_outline(f"X1_arch_R{k}", [(0.75, 0.75), (1.05, 1.45), (1.85, 1.6), (2.75, 1.4), (2.95, 0.85), (2.6, 1.2), (1.85, 1.38), (1.15, 1.25)],
                          0.8, "Crimson", body, (k * 1.6, 0, 0), axis="X", bevel=0.03)
        L.box(f"X1_side_intake{k}", (0.12, 0.9, 0.28), (k * 1.08, 0.6, 0.6), "Black", body, bevel=0.03)
        for j in range(3):
            L.box(f"X1_intake_slat{k}{j}", (0.13, 0.85, 0.02), (k * 1.1, 0.6, 0.5 + j * 0.09), "Gunmetal", body, bevel=0)
    for k in (1, -1):
        L.box(f"X1_fender_F{k}", (0.5, 1.25, 0.16), (k * 1.18, -1.85, 0.98), "Crimson", body, bevel=0.05, rot=L.deg(0, 0, 0))
        L.box(f"X1_fender_R{k}", (0.68, 1.5, 0.2), (k * 1.22, 1.75, 1.15), "Crimson", body, bevel=0.06)
        L.box(f"X1_skirt{k}", (0.12, 2.6, 0.22), (k * 1.24, 0.0, 0.36), "Gunmetal", body, bevel=0.03)
        L.box(f"X1_underglow{k}", (0.03, 2.4, 0.03), (k * 1.2, 0.0, 0.22), "EmissiveRed", body, bevel=0)
        L.box(f"X1_headlight{k}", (0.42, 0.05, 0.05), (k * 0.6, -2.98, 0.55), "EmissiveWhite", body, bevel=0.01, rot=L.deg(0, 0, -k * 10))
        L.box(f"X1_taillight{k}", (0.5, 0.04, 0.05), (k * 0.6, 3.0, 0.82), "EmissiveRed", body, bevel=0.01)
        L.cyl(f"X1_thruster{k}", 0.17, 0.2, 0.35, (k * 0.45, 3.05, 0.55), "Gunmetal", body, L.deg(90, 0, 0))
        L.cyl(f"X1_thruster_core{k}", 0.12, 0.12, 0.05, (k * 0.45, 3.24, 0.55), "EmissiveRed", body, L.deg(90, 0, 0))
        L.extrude_outline(f"X1_fin{k}", [(0, 0), (0.9, 0), (0.85, 0.55), (0.3, 0.2)], 0.05, "Crimson", body,
                          (k * 0.75, 2.2, 1.18), L.deg(0, 0, 0), axis="X")
    for i in range(5):  # front grille with red slits
        L.box(f"X1_grille{i}", (1.1, 0.03, 0.025), (0, -3.0, 0.38 + i * 0.045), "EmissiveRed" if i % 2 else "Black", body, bevel=0)
    # cockpit interior: seat, dashboard with screens, steering yoke
    cab = L.empty("Cockpit", (0, -0.45, 0.6), body)
    L.box("X1_seat_base", (0.55, 0.6, 0.18), (0, 0.15, 0.0), "Black", cab, bevel=0.05)
    L.box("X1_seat_back", (0.55, 0.15, 0.7), (0, 0.48, 0.35), "Black", cab, bevel=0.05, rot=L.deg(-12, 0, 0))
    L.box("X1_dash", (1.3, 0.35, 0.22), (0, -0.75, 0.32), "Gunmetal", cab, bevel=0.04)
    L.box("X1_screen", (0.5, 0.02, 0.18), (0, -0.6, 0.48), "Screen", cab, bevel=0, rot=L.deg(-20, 0, 0))
    L.torus("X1_yoke", 0.16, 0.022, (0, -0.42, 0.45), "Black", cab, L.deg(70, 0, 0))
    # canopy (rear hinge) and gullwing doors (roof hinge): separate pivots
    canopy = L.empty("Canopy", (0, 0.55, 1.15), body)
    L.loft("X1_canopy_glass", [(-1.65, [(0, 0), (.62, 0), (.5, .2), (0, .26)]), (-0.55, [(0, 0), (.74, 0), (.6, .3), (0, .36)]),
                               (0.0, [(0, 0), (.74, 0), (.6, .28), (0, .32)])], "Glass", canopy, loc=(0, -0.55, -0.12))
    L.box("X1_canopy_frame", (0.08, 1.7, 0.06), (0, -1.1, 0.24), "Crimson", canopy, bevel=0.02, rot=L.deg(6, 0, 0))
    for k in (1, -1):
        door = L.empty(f"Door_{'L' if k > 0 else 'R'}", (k * 0.6, -0.5, 1.12), body)
        L.box(f"X1_door{k}", (0.08, 1.5, 0.62), (k * 0.66, 0, -0.38), "Crimson", door, bevel=0.03, rot=L.deg(0, -k * 18, 0))
        L.box(f"X1_door_strip{k}", (0.03, 1.2, 0.03), (k * 0.73, 0, -0.5), "EmissiveRed", door, bevel=0)
        # battle-mode armour flaps (hinged along the upper flank)
        flap = L.empty(f"BattlePanel_{'L' if k > 0 else 'R'}", (k * 1.15, 1.0, 1.05), body)
        L.box(f"X1_flap{k}", (0.06, 1.2, 0.4), (k * 0.06, 0, -0.18), "Crimson", flap, bevel=0.02)
    # turret pod (battle mode): hidden inside the rear deck, rises
    turret = L.empty("Turret", (0, 1.4, 0.95), body)
    L.box("X1_turret_base", (0.7, 0.8, 0.22), (0, 0, 0), "Gunmetal", turret, bevel=0.04)
    for k in (1, -1):
        L.cyl(f"X1_pod{k}", 0.07, 0.07, 0.6, (k * 0.2, -0.35, 0.12), "Black", turret, L.deg(90, 0, 0), segs=12)
    # wheels on suspension (+ steering for the front axle)
    wheels = {}
    for (n, y, r, w, x) in (("FL", -1.9, 0.6, 0.56, 1.5), ("FR", -1.9, 0.6, 0.56, -1.5), ("RL", 1.85, 0.76, 0.76, 1.6), ("RR", 1.85, 0.76, 0.76, -1.6)):
        susp = L.empty(f"Susp_{n}", (x, y, r), root)
        L.box(f"X1_arm_{n}", (abs(x) - 0.55, 0.12, 0.08), (-x / abs(x) * (abs(x) - 0.55) / 2, 0, 0.05), "Gunmetal", susp, bevel=0.02)
        holder = L.empty(f"Steer_{n}", (0, 0, 0), susp) if n.startswith("F") else susp
        wheels[n] = wheel(f"Wheel_{n}", holder, (0, 0, 0), r, w)
    # anchors for gameplay
    L.empty("seat_attach", (0, -0.3, 0.72), root)
    L.empty("entry_anchor_L", (1.9, -0.5, 0), root)
    L.empty("exit_anchor_L", (2.1, -0.2, 0), root)
    L.empty("summon_anchor", (0, 0, 0), root)
    L.empty("camera_chase", (0, 7.5, 2.6), root)
    L.empty("camera_cockpit", (0, -0.6, 1.25), root)
    L.empty("sound_engine", (0, 2.4, 0.6), root)
    L.collider("X1_body", (3.6, 6.1, 1.2), (0, 0, 0.8), root)
    # clips (frames at 30 fps)
    for side, k in (("L", 1), ("R", -1)):
        L.clip(bpy.data.objects[f"Door_{side}"], "CRX1_DoorsOpen", [(0, (0, 0, 0)), (20, L.deg(0, k * 70, 0))])
        L.clip(bpy.data.objects[f"BattlePanel_{side}"], "CRX1_BattleMode", [(0, (0, 0, 0)), (24, L.deg(0, -k * 55, 0))])
    L.clip(canopy, "CRX1_CanopyOpen", [(0, (0, 0, 0)), (24, L.deg(-48, 0, 0))])
    L.clip(turret, "CRX1_BattleMode", [(0, (0, 1.4, 0.95)), (24, (0, 1.4, 1.3))], path="location")
    for n, piv in wheels.items():
        L.clip(piv, "CRX1_WheelSpin", [(0, (0, 0, 0)), (30, L.deg(-360, 0, 0))])
    for n in ("FL", "FR"):
        L.clip(bpy.data.objects[f"Steer_{n}"], "CRX1_SteerLeft", [(0, (0, 0, 0)), (15, L.deg(0, 0, 28))])
    return root


# ======================================================================================
# CR-B1 Crimson Batcycle (~2.6 m)
# ======================================================================================
def build_crb1():
    root = L.empty("CRB1_Batcycle", (0, 0, 0))
    body = L.empty("Body", (0, 0, 0), root)
    L.loft("B1_frame", [
        (-0.7, [(0, .55), (.1, .55), (.13, .75), (.09, .95), (0, .97)]),
        (-0.2, [(0, .42), (.17, .42), (.22, .7), (.16, .98), (0, 1.02)]),
        (0.35, [(0, .45), (.16, .45), (.2, .7), (.14, .86), (0, .88)]),
        (0.95, [(0, .62), (.09, .62), (.12, .8), (.07, .9), (0, .9)]),
    ], "Crimson", body, bevel=0.012)
    L.loft("B1_engine", [(-0.35, [(0, .3), (.15, .3), (.17, .5), (0, .55)]), (0.3, [(0, .32), (.16, .32), (.18, .5), (0, .55)])], "Gunmetal", body)
    L.cyl("B1_turbine", 0.15, 0.15, 0.3, (0, 0.0, 0.42), "Gunmetal", body, L.deg(0, 90, 0), segs=24)
    L.torus("B1_turbine_glow", 0.15, 0.01, (0.16, 0, 0.42), "EmissiveRed", body, L.deg(0, 90, 0))
    L.box("B1_tank", (0.34, 0.5, 0.18), (0, -0.2, 1.02), "Crimson", body, bevel=0.06, taper_top=(0.8, 0.85))
    L.box("B1_seat", (0.28, 0.55, 0.08), (0, 0.32, 0.92), "Black", body, bevel=0.03)
    L.box("B1_tail", (0.18, 0.5, 0.1), (0, 0.85, 0.95), "Crimson", body, bevel=0.03, rot=L.deg(10, 0, 0))
    L.box("B1_taillight", (0.14, 0.03, 0.025), (0, 1.1, 0.98), "EmissiveRed", body, bevel=0)
    for k in (1, -1):
        L.extrude_outline(f"B1_fairing{k}", [(-0.95, 0.75), (-0.75, 1.08), (-0.2, 1.05), (0.25, 0.85), (0.2, 0.5), (-0.35, 0.38), (-0.8, 0.45)],
                          0.07, "Crimson", body, (k * 0.24, 0, 0), axis="X", bevel=0.015)
        L.extrude_outline(f"B1_fairing_low{k}", [(-0.6, 0.3), (0.3, 0.3), (0.45, 0.5), (-0.4, 0.55)], 0.06, "CrimsonDark", body, (k * 0.27, 0, 0), axis="X")
        L.box(f"B1_fairing_strip{k}", (0.02, 0.7, 0.02), (k * 0.225, -0.35, 0.62), "EmissiveRed", body, bevel=0)
        L.box(f"B1_compartment{k}", (0.12, 0.32, 0.2), (k * 0.2, 0.55, 0.62), "Gunmetal", body, bevel=0.03)
        L.box(f"B1_compartment_lid{k}", (0.13, 0.33, 0.02), (k * 0.2, 0.55, 0.73), "Crimson", body, bevel=0.01)
    L.box("B1_screen", (0.2, 0.02, 0.1), (0, -0.6, 1.08), "Screen", body, bevel=0, rot=L.deg(-35, 0, 0))
    L.box("B1_windscreen", (0.3, 0.02, 0.2), (0, -0.66, 1.16), "Glass", body, bevel=0.01, rot=L.deg(-30, 0, 0))
    # steering assembly: raked head tube pivot carrying fork, bars, front wheel
    steer = L.empty("Steer", (0, -0.68, 0.95), root, rot=L.deg(-25, 0, 0))
    for k in (1, -1):
        L.cyl(f"B1_fork{k}", 0.04, 0.04, 0.8, (k * 0.2, 0, -0.4), "Gunmetal", steer, segs=12)
    L.box("B1_bars", (0.7, 0.04, 0.04), (0, 0.05, 0.14), "Black", steer, bevel=0.01)
    for k in (1, -1):
        L.empty(f"grip_{'L' if k > 0 else 'R'}", (k * 0.33, 0.05, 0.14), steer)
    L.box("B1_headlight", (0.16, 0.04, 0.05), (0, -0.12, 0.0), "EmissiveWhite", steer, bevel=0.01)
    L.box("B1_cowl", (0.3, 0.3, 0.22), (0, -0.05, 0.02), "Crimson", steer, bevel=0.05, taper_top=(0.7, 0.7))
    front = L.empty("FrontWheel_mount", (0, -0.12, -0.74), steer, rot=L.deg(25, 0, 0))
    wheel("Wheel_F", front, (0, 0, 0), 0.43, 0.32, spokes=5)
    # rear swingarm suspension pivot
    swing = L.empty("Swingarm", (0, 0.3, 0.45), root)
    for k in (1, -1):
        L.box(f"B1_swingarm{k}", (0.05, 0.72, 0.08), (k * 0.25, 0.36, -0.02), "Gunmetal", swing, bevel=0.01, rot=L.deg(4, 0, 0))
    wheel("Wheel_R", swing, (0, 0.72, -0.02), 0.46, 0.44, spokes=5)
    stand = L.empty("Kickstand", (0.14, 0.05, 0.32), root)
    L.cyl("B1_stand", 0.015, 0.015, 0.34, (0, 0, -0.17), "Gunmetal", stand, segs=8)
    L.empty("seat_attach", (0, 0.3, 0.97), root)
    L.empty("entry_anchor_L", (0.8, 0.2, 0), root)
    L.empty("exit_anchor_L", (0.9, 0.3, 0), root)
    L.empty("summon_anchor", (0, 0, 0), root)
    L.empty("camera_chase", (0, 4.2, 1.6), root)
    L.empty("sound_engine", (0, 0.0, 0.42), root)
    L.collider("B1_body", (0.5, 2.5, 1.0), (0, 0, 0.6), root)
    L.clip(stand, "CRB1_StandDeploy", [(0, L.deg(0, 80, 0)), (15, L.deg(0, 0, 0))])
    L.clip(bpy.data.objects["Wheel_F"], "CRB1_WheelSpin", [(0, (0, 0, 0)), (30, L.deg(-360, 0, 0))])
    L.clip(bpy.data.objects["Wheel_R"], "CRB1_WheelSpin", [(0, (0, 0, 0)), (30, L.deg(-360, 0, 0))])
    L.clip(steer, "CRB1_SteerLeft", [(0, L.deg(-25, 0, 0)), (15, L.deg(-25, 0, 25))])
    L.clip(swing, "CRB1_SuspensionBob", [(0, (0, 0, 0)), (10, L.deg(4, 0, 0)), (20, (0, 0, 0))])
    for k, side in ((1, "L"), (-1, "R")):
        pass
    return root


# ======================================================================================
# CR-A1 Crimson Specter (18.4 m stealth wing, VTOL)
# ======================================================================================
def build_cra1():
    root = L.empty("CRA1_Specter", (0, 0, 0))
    body = L.empty("Body", (0, 0, 0), root)
    gear_h = 1.3
    L.loft("A1_fuselage", [
        (-9.2, [(0, gear_h + .9), (.05, gear_h + .9), (0, gear_h + .95)]),
        (-7.0, [(0, gear_h + .45), (.7, gear_h + .55), (.75, gear_h + 1.0), (.4, gear_h + 1.35), (0, gear_h + 1.4)]),
        (-3.0, [(0, gear_h + .2), (1.5, gear_h + .35), (1.7, gear_h + 1.0), (1.0, gear_h + 1.8), (0, gear_h + 1.95)]),
        (2.0, [(0, gear_h + .15), (1.9, gear_h + .3), (2.1, gear_h + .95), (1.3, gear_h + 1.65), (0, gear_h + 1.75)]),
        (7.0, [(0, gear_h + .35), (1.6, gear_h + .45), (1.8, gear_h + .95), (1.0, gear_h + 1.3), (0, gear_h + 1.35)]),
        (9.2, [(0, gear_h + .6), (1.0, gear_h + .65), (1.1, gear_h + .95), (0.6, gear_h + 1.05), (0, gear_h + 1.08)]),
    ], "Crimson", body, bevel=0.03)
    for k in (1, -1):
        s = "L" if k > 0 else "R"
        wing_pts = [(1.5 * k, -3.0), (14.3 * k, 6.2), (14.3 * k, 7.6), (9.0 * k, 6.4), (1.6 * k, 7.0)]
        if k < 0:
            wing_pts = wing_pts[::-1]
        L.extrude_outline(f"A1_wing_{s}", wing_pts, 0.55, "Crimson", body, (0, 0, gear_h + 0.75), bevel=0.08)
        top_pts = [(2.0 * k, -1.6), (11.5 * k, 5.6), (10.5 * k, 6.3), (2.0 * k, 4.5)]
        L.extrude_outline(f"A1_wing_top_{s}", top_pts if k > 0 else top_pts[::-1], 0.4, "CrimsonDark", body, (0, 0, gear_h + 1.05), bevel=0.06)
        L.extrude_outline(f"A1_spike_{s}", [(0, 0), (4.5, 0), (5.2, 3.2), (1.5, 1.0)], 0.25, "Crimson", body,
                          (k * 2.6, -0.5, gear_h + 1.0), L.deg(0, 0, 0), axis="X", bevel=0.04)
        L.box(f"A1_wing_light2_{s}", (0.04, 7.0, 0.04), (k * 6.5, 1.0, gear_h + 1.27), "EmissiveRed", body, bevel=0, rot=L.deg(0, 0, -k * 52))
        L.box(f"A1_fuse_light_{s}", (0.05, 6.0, 0.05), (k * 1.75, -1.5, gear_h + 0.75), "EmissiveRed", body, bevel=0)
        L.extrude_outline(f"A1_wing_trim_{s}", [(1.6 * k, -2.6), (13.8 * k, 6.3), (13.8 * k, 6.45), (1.6 * k, -2.35)][:: (1 if k > 0 else -1)],
                          0.34, "Gunmetal", body, (0, 0, gear_h + 0.75), bevel=0.01)
        L.box(f"A1_wing_light_{s}", (0.04, 9.5, 0.04), (k * 7.6, 1.6, gear_h + 0.92), "EmissiveRed", body, bevel=0, rot=L.deg(0, 0, -k * 54))
        L.extrude_outline(f"A1_tip_{s}", [(0, 0), (1.5, 0), (2.0, 1.6), (0.4, 0.4)], 0.12, "Crimson", body,
                          (k * 14.3, 6.2, gear_h + 0.75), L.deg(0, 0, 0), axis="X")
        L.box(f"A1_navlight_{s}", (0.12, 0.12, 0.12), (k * 14.35, 7.6, gear_h + 0.8), "EmissiveRed" if k > 0 else "EmissiveWhite", body, bevel=0.02)
        # control surfaces on hinge pivots at the wing trailing edge
        elevon = L.empty(f"Elevon_{s}", (k * 5.5, 6.65, gear_h + 0.75), body, rot=L.deg(0, 0, -k * 5))
        L.box(f"A1_elevon_{s}", (6.0, 0.7, 0.12), (k * 0.2, 0.35, 0), "Gunmetal", elevon, bevel=0.02)
        rudder = L.empty(f"Rudder_{s}", (k * 1.6, 7.6, gear_h + 1.5), body, rot=L.deg(0, -k * 18, 0))
        L.extrude_outline(f"A1_tail_{s}", [(0, 0), (1.6, 0), (2.2, 2.0), (1.0, 2.0)], 0.12, "Crimson", rudder, (0, -1.0, 0), axis="X")
        # engines with emissive exhaust
        L.cyl(f"A1_engine_{s}", 0.55, 0.62, 3.5, (k * 1.35, 7.6, gear_h + 0.95), "Gunmetal", body, L.deg(90, 0, 0), segs=24)
        L.cyl(f"A1_exhaust_{s}", 0.45, 0.45, 0.06, (k * 1.35, 9.38, gear_h + 0.95), "EmissiveRed", body, L.deg(90, 0, 0), segs=24)
        # VTOL nacelles that rotate from horizontal to vertical
        vtol = L.empty(f"VTOL_{s}", (k * 5.2, 2.2, gear_h + 0.9), body)
        L.cyl(f"A1_vtol_{s}", 0.65, 0.65, 0.5, (0, 0, 0), "Gunmetal", vtol, L.deg(90, 0, 0), segs=28)
        L.cyl(f"A1_vtol_fan_{s}", 0.55, 0.55, 0.06, (0, 0.2, 0), "EmissiveRed", vtol, L.deg(90, 0, 0), segs=28)
        # access panels
        L.box(f"A1_panel_{s}", (0.9, 1.4, 0.03), (k * 1.3, 0.5, gear_h + 1.62), "Gunmetal", body, bevel=0.01, rot=L.deg(0, -k * 35, 0))
    # canopy + cockpit
    canopy = L.empty("Canopy", (0, -6.6, gear_h + 1.38), body)
    L.loft("A1_canopy", [(0.0, [(0, 0), (.62, 0), (.45, .3), (0, .4)]), (2.6, [(0, 0), (.8, 0), (.6, .45), (0, .55)]),
                         (3.6, [(0, 0), (.7, 0), (.5, .3), (0, .35)])], "Glass", canopy, loc=(0, 0, 0))
    L.box("A1_seat", (0.6, 0.6, 0.9), (0, -4.6, gear_h + 1.3), "Black", body, bevel=0.06)
    L.box("A1_console", (1.2, 0.4, 0.3), (0, -5.6, gear_h + 1.35), "Gunmetal", body, bevel=0.04)
    L.box("A1_screens", (1.0, 0.02, 0.25), (0, -5.75, gear_h + 1.55), "Screen", body, bevel=0, rot=L.deg(-20, 0, 0))
    # landing gear on retract pivots
    gears = {}
    for name, loc, r in (("Gear_Nose", (0, -6.0, gear_h + 0.3), 0.3), ("Gear_L", (2.3, 2.5, gear_h + 0.25), 0.42), ("Gear_R", (-2.3, 2.5, gear_h + 0.25), 0.42)):
        g = L.empty(name, loc, root)
        L.cyl(name + "_strut", 0.08, 0.08, gear_h - 0.1, (0, 0, -(gear_h - r) / 2 - 0.1), "Gunmetal", g, segs=12)
        L.cyl(name + "_tyre", r, r, 0.3, (0, 0, -(gear_h - r) - 0.1), "Rubber", g, L.deg(0, 90, 0), segs=24)
        gears[name] = g
    L.empty("seat_attach", (0, -4.6, gear_h + 1.15), root)
    L.empty("entry_anchor_L", (2.5, -5.0, 0), root)
    L.empty("exit_anchor_L", (2.8, -4.5, 0), root)
    L.empty("summon_anchor", (0, 0, 0), root)
    L.empty("camera_chase", (0, 24, 7), root)
    L.empty("camera_cockpit", (0, -5.0, gear_h + 1.9), root)
    L.empty("sound_engine", (0, 8.5, gear_h + 1.0), root)
    L.collider("A1_fuselage", (4.0, 18.4, 2.0), (0, 0, gear_h + 1.0), root)
    L.collider("A1_wings", (28.7, 9.0, 0.4), (0, 3.0, gear_h + 0.75), root)
    L.clip(canopy, "CRA1_CanopyOpen", [(0, (0, 0, 0)), (30, L.deg(35, 0, 0))])
    for name, g in gears.items():
        L.clip(g, "CRA1_GearRetract", [(0, (0, 0, 0)), (40, L.deg(-95 if name == "Gear_Nose" else 0, 0, 0 if name == "Gear_Nose" else (95 if name == "Gear_L" else -95)))])
    for s in ("L", "R"):
        L.clip(bpy.data.objects[f"VTOL_{s}"], "CRA1_VTOLTransition", [(0, (0, 0, 0)), (45, L.deg(-90, 0, 0))])
        L.clip(bpy.data.objects[f"Elevon_{s}"], "CRA1_ElevonsUp", [(0, bpy.data.objects[f"Elevon_{s}"].rotation_euler[:]),
                                                                  (15, (L.deg(18, 0, 0)[0],) + tuple(bpy.data.objects[f"Elevon_{s}"].rotation_euler[1:]))])
        r = bpy.data.objects[f"Rudder_{s}"]
        L.clip(r, "CRA1_RudderLeft", [(0, r.rotation_euler[:]), (15, tuple(r.rotation_euler[:2]) + (L.deg(0, 0, 20)[2],))])
    return root


def finish(root, file_base):
    objs = L.descendants(root)
    tris = L.tri_count(objs)
    L.export(os.path.join(OUT, file_base + ".glb"), True, objs)
    lod = L.static_lod(objs, 0.25, file_base + "_LOD1")
    L.export(os.path.join(OUT, file_base + "_lod1.glb"), False, [lod])
    REPORT[file_base] = {"triangles_lod0": tris, "triangles_lod1": L.tri_count([lod]),
                         "pivots": sorted(o.name for o in objs if o.type == "EMPTY"),
                         "clips": sorted({t.name for o in objs if o.animation_data for t in o.animation_data.nla_tracks})}
    bpy.data.objects.remove(lod)
    print(f"[vehicles] {file_base}: {tris} tris, LOD1 {REPORT[file_base]['triangles_lod1']}")


def main():
    for build, base in ((build_crx1, "crx1_interceptor"), (build_crb1, "crb1_batcycle"), (build_cra1, "cra1_specter")):
        L.reset()
        root = build()
        bpy.context.view_layer.update()
        finish(root, base)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(L.ROOT, "assets", "source", "blender", base + ".blend"))
    cfg_path = os.path.join(L.ROOT, "config", "vehicle_assets.json")
    if os.path.exists(cfg_path):  # keep the per-mode map written by ck_build_vehicle_modes.py
        with open(cfg_path) as fh:
            old = json.load(fh)
        for key, rep in REPORT.items():
            if "modes" in old.get(key, {}):
                rep["modes"] = old[key]["modes"]
    with open(cfg_path, "w") as fh:
        json.dump(REPORT, fh, indent=2)
    print("[vehicles] OK")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
