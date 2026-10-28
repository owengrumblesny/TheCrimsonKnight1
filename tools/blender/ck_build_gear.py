"""
Crimson Knight: Earth-RED -- gadget & fictional-weapon models (Blender 5.x, headless).

    blender -b --factory-startup --python tools/blender/ck_build_gear.py [-- id ...]

One GLB per inventory item (gear_<itemId>.glb), real-world scale, Owen's material PNGs via ck_lib.
Conventions (match the CR-X9 v2 sockets):
  * origin = the grip point; it attaches to the socket named in the root's "attach" extra
    (Socket_Hand_R / Socket_Hand_L / Socket_Belt_R / Socket_Back / ground)
  * front = -Y in Blender (+Z in three.js); muzzles / emitters are empties named Muzzle / Emitter
  * moving parts are pivots with clips: Gear_Deploy (open / unfold / ignite), Gear_Fire (recoil / pulse), Gear_Idle (loops)
All weapons are fictional energy devices (no real-world firearm replicas).

Outputs: assets/models/gear/gear_<id>.glb, config/gadget_assets.json
"""
import json
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ck_lib as L  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
OUT_DIR = os.path.join(ROOT, "assets", "models", "gear")
OUT_JSON = os.path.join(ROOT, "config", "gadget_assets.json")
D = L.deg


def ring_y(name, r1, r2, depth, y, mat, parent, z=0.0, x=0.0, segs=20):
    """Cylinder along the Y (front/back) axis."""
    return L.cyl(name, r1, r2, depth, (x, y, z), mat, parent=parent, rot=D(90, 0, 0), segs=segs)


# --------------------------------------------------------------------------------------
# gadgets
# --------------------------------------------------------------------------------------
def batarang(R):
    hub = L.box("Batarang_Hub", (0.07, 0.06, 0.016), (0, 0, 0), "Gunmetal", parent=R, bevel=0.006)
    L.box("Batarang_Core", (0.03, 0.03, 0.02), (0, -0.005, 0), "EmissiveRed", parent=hub, bevel=0.004)
    for side, k in (("L", 1), ("R", -1)):
        piv = L.empty(f"Wing_{side}", (k * 0.03, 0, 0), parent=R)
        pts = [(0, 0.03), (k * 0.06, 0.05), (k * 0.13, 0.035), (k * 0.17, 0.06), (k * 0.155, -0.005), (k * 0.11, -0.02),
               (k * 0.08, -0.045), (k * 0.045, -0.03), (0, -0.03)]
        if k < 0:
            pts = pts[::-1]
        L.extrude_outline(f"Wing_{side}_Blade", pts, 0.008, "Crimson", parent=piv, bevel=0.002)
        L.clip(piv, "Gear_Deploy", [(0, D(0, 0, -k * 150)), (8, D(0, 0, 0))])
    L.clip(R, "Gear_Idle", [(0, D(0, 0, 0)), (10, D(0, 0, 360))])  # in-flight spin
    return dict(attach="Socket_Belt_R", anchors=[], note="wings fold into the hub on the belt; Gear_Deploy snaps them open")


def grapple(R):
    body = L.box("Grapnel_Body", (0.06, 0.24, 0.08), (0, -0.07, 0.07), "Gunmetal", parent=R, bevel=0.012)
    L.box("Grapnel_Grip", (0.04, 0.05, 0.12), (0, 0.01, 0.0), "Rubber", parent=R, bevel=0.01, rot=D(-12, 0, 0))
    L.box("Grapnel_Trigger", (0.012, 0.02, 0.03), (0, -0.035, 0.02), "Black", parent=R, bevel=0.003)
    L.box("Grapnel_Stripe", (0.062, 0.18, 0.012), (0, -0.07, 0.112), "Crimson", parent=R, bevel=0.003)
    ring_y("Grapnel_Barrel", 0.024, 0.024, 0.12, -0.24, "Gunmetal", R, z=0.075)
    ring_y("Grapnel_Spool", 0.04, 0.04, 0.05, -0.02, "Black", R, z=0.075)
    head = L.empty("Grapnel_Head", (0, -0.31, 0.075), parent=R)
    L.cyl("Grapnel_Tip", 0.018, 0.004, 0.06, (0, -0.02, 0), "Crimson", parent=head, rot=D(90, 0, 0), segs=12)
    for i in range(3):
        a = i * 120
        claw = L.empty(f"Claw_{i}", (0, 0, 0), parent=head, rot=D(0, a, 0))
        L.box(f"Claw_{i}_Blade", (0.01, 0.05, 0.012), (0, 0.01, 0.028), "Gunmetal", parent=claw, bevel=0.003)
        L.clip(claw, "Gear_Fire", [(0, D(0, a, 0)), (6, D(-55, a, 0)), (20, D(-55, a, 0))])
    L.empty("Muzzle", (0, -0.34, 0.075), parent=R)
    L.empty("Cable_Origin", (0, -0.3, 0.075), parent=R)
    return dict(attach="Socket_Hand_R", anchors=["Muzzle", "Cable_Origin"], note="claws spread on Gear_Fire")


def scanner(R):
    L.box("Scanner_Body", (0.09, 0.03, 0.15), (0, 0, 0.07), "Gunmetal", parent=R, bevel=0.01)
    L.box("Scanner_Screen", (0.075, 0.004, 0.1), (0, -0.016, 0.08), "Screen", parent=R, bevel=0.002)
    L.box("Scanner_Trim", (0.092, 0.032, 0.012), (0, 0, 0.0), "Crimson", parent=R, bevel=0.004)
    ant = L.empty("Antenna", (0.035, 0.0, 0.145), parent=R)
    L.cyl("Antenna_Rod", 0.004, 0.003, 0.08, (0, 0, 0.04), "Black", parent=ant, segs=8)
    L.box("Antenna_Tip", (0.01, 0.01, 0.01), (0, 0, 0.082), "EmissiveRed", parent=ant, bevel=0.002)
    L.clip(ant, "Gear_Deploy", [(0, D(0, -90, 0)), (10, D(0, 0, 0))])
    L.empty("Emitter", (0, -0.02, 0.15), parent=R)
    return dict(attach="Socket_Hand_L", anchors=["Emitter"], note="screen uses the Screen material; antenna flips up")


def drone(R):
    body = L.box("Recon_Body", (0.14, 0.18, 0.05), (0, 0, 0), "Gunmetal", parent=R, bevel=0.015, taper_top=(0.8, 0.8))
    L.box("Recon_Stripe", (0.141, 0.03, 0.006), (0, -0.05, 0.024), "Crimson", parent=body, bevel=0.002)
    L.cyl("Recon_Eye", 0.02, 0.02, 0.02, (0, -0.09, -0.01), "EmissiveRed", parent=body, rot=D(90, 0, 0), segs=12)
    for i, (x, y) in enumerate(((0.13, 0.13), (-0.13, 0.13), (0.13, -0.13), (-0.13, -0.13))):
        L.box(f"Recon_Arm{i}", (0.02, 0.17, 0.012), (x / 2, y / 2, 0.0), "Black", parent=body, bevel=0.003,
              rot=(0, 0, -math.atan2(x, y)))
        L.torus(f"Recon_Guard{i}", 0.065, 0.005, (x, y, 0.01), "Black", parent=body, seg=20, ring=5)
        piv = L.empty(f"Rotor_{i}", (x, y, 0.02), parent=body)
        L.box(f"Recon_Blade{i}", (0.11, 0.012, 0.003), (0, 0, 0), "Black", parent=piv, bevel=0.0)
        L.clip(piv, "Gear_Idle", [(0, (0, 0, 0)), (6, D(0, 0, 360 * (1 if i % 2 else -1)))])
    L.empty("Emitter", (0, -0.1, -0.02), parent=R)
    return dict(attach="ground", anchors=["Emitter"], origin="centre", note="Gear_Idle spins the rotors; game flies the root")


def smoke(R):
    L.cyl("Pellet_Body", 0.025, 0.025, 0.045, (0, 0, 0.0225), "Gunmetal", parent=R, segs=16)
    L.cyl("Pellet_Band", 0.0262, 0.0262, 0.01, (0, 0, 0.02), "Crimson", parent=R, segs=16)
    L.cyl("Pellet_Vents", 0.02, 0.012, 0.012, (0, 0, 0.05), "Black", parent=R, segs=16)
    pin = L.empty("Pin", (0.0, 0.0, 0.056), parent=R)
    L.torus("Pin_Ring", 0.012, 0.0025, (0.015, 0, 0), "Gunmetal", parent=pin, rot=D(90, 0, 0), seg=16, ring=5)
    L.clip(pin, "Gear_Deploy", [(0, (0, 0, 0.056)), (6, (0.03, 0, 0.07))], path="location")
    L.empty("Emitter", (0, 0, 0.058), parent=R)
    return dict(attach="Socket_Belt_L", anchors=["Emitter"], note="pin pulls on Gear_Deploy")


def shield(R):
    L.cyl("Shield_Emitter", 0.04, 0.04, 0.12, (0, 0, 0), "Gunmetal", parent=R, rot=D(90, 0, 0), segs=16)
    L.cyl("Shield_Core", 0.025, 0.025, 0.122, (0, 0, 0.0), "EmissiveRed", parent=R, rot=D(90, 0, 0), segs=6)
    field = L.empty("Shield_Field", (-0.06, 0, 0), parent=R)
    L.cyl("Shield_Hex", 0.42, 0.42, 0.01, (0, 0, 0), "Hologram", parent=field, rot=D(0, 90, 0), segs=6)
    L.torus("Shield_Rim", 0.42, 0.012, (0, 0, 0), "EmissiveRed", parent=field, rot=D(0, 90, 0), seg=6, ring=4)
    L.clip(field, "Gear_Deploy", [(0, (0.01, 0.01, 0.01)), (8, (1.1, 1.1, 1.1)), (12, (1, 1, 1))], path="scale")
    return dict(attach="Socket_Hand_L", anchors=[], note="forearm emitter; hexagonal hard-light field scales in")


def cloak(R):
    L.box("Cloak_Module", (0.1, 0.05, 0.07), (0, 0, 0), "Gunmetal", parent=R, bevel=0.01)
    L.box("Cloak_Lens", (0.06, 0.006, 0.03), (0, -0.026, 0.005), "Hologram", parent=R, bevel=0.003)
    fins = L.empty("Cloak_Fins", (0, 0, 0.035), parent=R)
    for i in range(3):
        L.box(f"Cloak_Fin{i}", (0.008, 0.04, 0.03), ((i - 1) * 0.03, 0, 0.012), "EmissiveRed", parent=fins, bevel=0.002)
    L.clip(fins, "Gear_Deploy", [(0, (1, 1, 0.1)), (10, (1, 1, 1))], path="scale")
    return dict(attach="Socket_Belt_R", anchors=[], note="belt module; game drives the refraction shader on the hero")


def beacon(R):
    L.cyl("Beacon_Spike", 0.008, 0.002, 0.12, (0, 0, 0.06), "Gunmetal", parent=R, segs=8, rot=D(180, 0, 0))
    L.cyl("Beacon_Body", 0.03, 0.03, 0.08, (0, 0, 0.14), "Gunmetal", parent=R, segs=12)
    L.cyl("Beacon_Light", 0.022, 0.018, 0.03, (0, 0, 0.195), "EmissiveRed", parent=R, segs=12)
    L.cyl("Beacon_Band", 0.031, 0.031, 0.012, (0, 0, 0.12), "Crimson", parent=R, segs=12)
    for i in range(3):
        a = i * 120
        leg = L.empty(f"Leg_{i}", (0, 0, 0.11), parent=R, rot=D(0, 0, a))
        L.box(f"Leg_{i}_Strut", (0.008, 0.008, 0.1), (0, 0.0, -0.05), "Black", parent=leg, bevel=0.002)
        L.clip(leg, "Gear_Deploy", [(0, D(0, 0, a)), (10, D(35, 0, a))])
    L.empty("Emitter", (0, 0, 0.21), parent=R)
    return dict(attach="ground", anchors=["Emitter"], origin="ground", note="legs splay on Gear_Deploy")


def emp(R):
    L.cyl("EMP_Body", 0.035, 0.035, 0.08, (0, 0, 0.04), "Gunmetal", parent=R, segs=16)
    for i, z in enumerate((0.02, 0.04, 0.06)):
        L.torus(f"EMP_Coil{i}", 0.037, 0.004, (0, 0, z), "Neon", parent=R, seg=20, ring=5)
    cap = L.empty("EMP_Cap", (0, 0, 0.08), parent=R)
    L.cyl("EMP_CapMesh", 0.03, 0.022, 0.02, (0, 0, 0.01), "Crimson", parent=cap, segs=6)
    L.clip(cap, "Gear_Deploy", [(0, (0, 0, 0)), (8, D(0, 0, 90))])
    L.clip(cap, "Gear_Idle", [(0, (0, 0, 0)), (20, D(0, 0, 360))])
    L.empty("Emitter", (0, 0, 0.1), parent=R)
    return dict(attach="Socket_Belt_L", anchors=["Emitter"], note="twist-arm cap; coils use the Neon material")


def sonic(R):
    L.box("Sonic_Grip", (0.035, 0.04, 0.11), (0, 0.01, 0.0), "Rubber", parent=R, bevel=0.008)
    L.box("Sonic_Body", (0.05, 0.12, 0.06), (0, -0.04, 0.07), "Gunmetal", parent=R, bevel=0.01)
    dish = L.empty("Sonic_Dish", (0, -0.1, 0.07), parent=R)
    L.cyl("Sonic_Cone", 0.02, 0.06, 0.05, (0, -0.025, 0), "Gunmetal", parent=dish, rot=D(90, 0, 0), segs=20)
    for i, r in enumerate((0.05, 0.035, 0.02)):
        L.torus(f"Sonic_Ring{i}", r, 0.003, (0, -0.05 + i * 0.008, 0), "EmissiveRed", parent=dish, rot=D(90, 0, 0), seg=20, ring=4)
    L.clip(dish, "Gear_Fire", [(0, (0, -0.1, 0.07)), (3, (0, -0.115, 0.07)), (10, (0, -0.1, 0.07))], path="location")
    L.empty("Muzzle", (0, -0.16, 0.07), parent=R)
    return dict(attach="Socket_Hand_R", anchors=["Muzzle"], note="dish pulses forward on Gear_Fire")


def decoy(R):
    L.cyl("Decoy_Puck", 0.05, 0.05, 0.025, (0, 0, 0.0125), "Gunmetal", parent=R, segs=20)
    L.cyl("Decoy_Lens", 0.02, 0.02, 0.006, (0, 0, 0.027), "Hologram", parent=R, segs=16)
    L.torus("Decoy_Rim", 0.05, 0.004, (0, 0, 0.02), "Crimson", parent=R, seg=20, ring=4)
    holo = L.empty("Decoy_Hologram", (0, 0, 0.03), parent=R)
    L.box("Decoy_Holo_Body", (0.36, 0.2, 0.85), (0, 0, 1.05), "Hologram", parent=holo, bevel=0.06, taper_top=(1.15, 1.0))
    L.box("Decoy_Holo_Legs", (0.3, 0.16, 0.8), (0, 0, 0.4), "Hologram", parent=holo, bevel=0.04)
    L.cyl("Decoy_Holo_Head", 0.1, 0.11, 0.24, (0, 0, 1.62), "Hologram", parent=holo, segs=12)
    L.clip(holo, "Gear_Deploy", [(0, (0.6, 0.6, 0.01)), (12, (1, 1, 1))], path="scale")
    return dict(attach="ground", anchors=[], origin="ground", note="projects a full-size hologram silhouette of the CR-X9")


def holoprojector(R):
    L.box("Holo_Base", (0.12, 0.08, 0.025), (0, 0, 0.0125), "Gunmetal", parent=R, bevel=0.008)
    L.box("Holo_Emitter", (0.1, 0.012, 0.01), (0, -0.02, 0.03), "EmissiveRed", parent=R, bevel=0.002)
    panel = L.empty("Holo_Panel", (0, -0.02, 0.035), parent=R)
    L.box("Holo_Screen", (0.3, 0.004, 0.18), (0, 0, 0.11), "Hologram", parent=panel, bevel=0.0)
    L.box("Holo_Map", (0.24, 0.005, 0.12), (0, -0.002, 0.11), "Screen", parent=panel, bevel=0.0)
    L.clip(panel, "Gear_Deploy", [(0, (1, 1, 0.01)), (10, (1, 1, 1))], path="scale")
    return dict(attach="Socket_Hand_L", anchors=[], note="unfolds a city-map hologram panel")


def gauntlet(R):
    L.cyl("Gauntlet_Bracer", 0.048, 0.042, 0.2, (0, 0.1, 0), "Crimson", parent=R, rot=D(90, 0, 0), segs=16)
    L.box("Gauntlet_Plate", (0.06, 0.15, 0.02), (0, 0.1, 0.047), "CrimsonDark", parent=R, bevel=0.006)
    L.box("Gauntlet_Screen", (0.04, 0.06, 0.004), (0, 0.08, 0.058), "Screen", parent=R, bevel=0.0)
    lid = L.empty("Gauntlet_Lid", (0, 0.11, 0.058), parent=R)
    L.box("Gauntlet_LidMesh", (0.05, 0.07, 0.008), (0, -0.035, 0.004), "Gunmetal", parent=lid, bevel=0.002)
    L.clip(lid, "Gear_Deploy", [(0, (0, 0, 0)), (8, D(-110, 0, 0))])
    for i in range(3):
        L.box(f"Gauntlet_Fin{i}", (0.012, 0.03, 0.02), (0.05, 0.05 + i * 0.045, 0.01), "Gunmetal", parent=R, bevel=0.003)
    L.empty("Emitter", (0, -0.005, 0.03), parent=R)
    return dict(attach="Socket_Hand_L", origin="wrist", anchors=["Emitter"], note="forearm module; lid flips to show screen")


# --------------------------------------------------------------------------------------
# fictional energy weapons (deliberately non-realistic: no real firearm replicas)
# --------------------------------------------------------------------------------------
def phantom_sidearm(R):
    L.box("Sidearm_Grip", (0.032, 0.045, 0.11), (0, 0.012, 0.0), "Rubber", parent=R, bevel=0.01, rot=D(-14, 0, 0))
    L.box("Sidearm_Frame", (0.034, 0.17, 0.035), (0, -0.05, 0.065), "Gunmetal", parent=R, bevel=0.008)
    slide = L.empty("Slide", (0, 0, 0.0), parent=R)
    L.box("Sidearm_Shroud", (0.038, 0.18, 0.03), (0, -0.055, 0.097), "Crimson", parent=slide, bevel=0.008, taper_top=(0.8, 1))
    for i in range(3):
        L.box(f"Sidearm_Vent{i}", (0.039, 0.012, 0.012), (0, -0.09 + i * 0.03, 0.097), "EmissiveRed", parent=slide, bevel=0.002)
    ring_y("Sidearm_Emitter", 0.012, 0.016, 0.03, -0.155, "Gunmetal", R, z=0.08)
    L.cyl("Sidearm_Cell", 0.01, 0.01, 0.05, (0, 0.02, -0.03), "EmissiveRed", parent=R, segs=8, rot=D(-14, 0, 0))
    L.clip(slide, "Gear_Fire", [(0, (0, 0, 0)), (2, (0, 0.02, 0)), (6, (0, 0, 0))], path="location")
    L.empty("Muzzle", (0, -0.175, 0.08), parent=R)
    return dict(attach="Socket_Hand_R", anchors=["Muzzle"], note="energy shroud recoils on Gear_Fire")


def crimson_carbine(R):
    L.box("Carbine_Grip", (0.032, 0.045, 0.11), (0, 0.012, 0.0), "Rubber", parent=R, bevel=0.01, rot=D(-14, 0, 0))
    L.box("Carbine_Receiver", (0.05, 0.32, 0.07), (0, -0.07, 0.075), "Gunmetal", parent=R, bevel=0.012)
    L.box("Carbine_Shell", (0.054, 0.22, 0.03), (0, -0.12, 0.115), "Crimson", parent=R, bevel=0.01, taper_top=(0.7, 1))
    L.box("Carbine_Stock", (0.04, 0.2, 0.06), (0, 0.17, 0.06), "CrimsonDark", parent=R, bevel=0.012, taper_top=(1, 0.8))
    L.box("Carbine_Fore", (0.04, 0.08, 0.04), (0, -0.2, 0.03), "Rubber", parent=R, bevel=0.008)
    ring_y("Carbine_Barrel", 0.016, 0.016, 0.18, -0.31, "Gunmetal", R, z=0.08)
    for i in range(3):
        L.torus(f"Carbine_Coil{i}", 0.021, 0.004, (0, -0.26 - i * 0.04, 0.08), "EmissiveRed", parent=R, rot=D(90, 0, 0), seg=16, ring=4)
    sight = L.empty("Carbine_Sight", (0, -0.04, 0.11), parent=R)
    L.box("Carbine_SightMesh", (0.03, 0.08, 0.035), (0, 0, 0.02), "Black", parent=sight, bevel=0.006)
    L.box("Carbine_SightLens", (0.022, 0.004, 0.022), (0, -0.041, 0.022), "Glass", parent=sight, bevel=0.0)
    L.clip(sight, "Gear_Deploy", [(0, D(0, 0, 0)), (1, D(-90, 0, 0)), (8, D(0, 0, 0))])
    cell = L.empty("Cell", (0, -0.06, 0.03), parent=R)
    L.box("Carbine_Cell", (0.03, 0.05, 0.08), (0, 0, -0.04), "EmissiveRed", parent=cell, bevel=0.006)
    L.clip(cell, "Gear_Fire", [(0, (0, -0.06, 0.03)), (2, (0, -0.055, 0.035)), (6, (0, -0.06, 0.03))], path="location")
    L.empty("Muzzle", (0, -0.4, 0.08), parent=R)
    L.empty("OffHand", (0, -0.2, 0.03), parent=R)
    return dict(attach="Socket_Hand_R", anchors=["Muzzle", "OffHand"], note="two-handed; OffHand = left-hand IK target")


def energy_launcher(R):
    L.box("Launcher_Grip", (0.032, 0.045, 0.11), (0, 0.012, 0.0), "Rubber", parent=R, bevel=0.01, rot=D(-10, 0, 0))
    ring_y("Launcher_Tube", 0.075, 0.075, 0.7, -0.1, "Gunmetal", R, z=0.14, segs=24)
    ring_y("Launcher_Bell", 0.09, 0.08, 0.06, -0.47, "Crimson", R, z=0.14, segs=24)
    ring_y("Launcher_Rear", 0.08, 0.085, 0.05, 0.26, "CrimsonDark", R, z=0.14, segs=24)
    for i in range(4):
        L.torus(f"Launcher_Ring{i}", 0.077, 0.006, (0, -0.32 + i * 0.12, 0.14), "EmissiveRed", parent=R, rot=D(90, 0, 0), seg=24, ring=4)
    flap = L.empty("Launcher_Sight", (-0.08, -0.15, 0.17), parent=R)
    L.box("Launcher_SightMesh", (0.008, 0.06, 0.06), (-0.004, 0, 0.03), "Black", parent=flap, bevel=0.003)
    L.clip(flap, "Gear_Deploy", [(0, D(0, -90, 0)), (8, D(0, 0, 0))])
    L.empty("Muzzle", (0, -0.5, 0.14), parent=R)
    L.empty("OffHand", (0, -0.25, 0.06), parent=R)
    return dict(attach="Socket_Hand_R", anchors=["Muzzle", "OffHand"], note="shoulder-carried energy tube; sight flips out")


def energy_cannon(R):
    L.box("Cannon_Grip", (0.032, 0.045, 0.11), (0, 0.012, 0.0), "Rubber", parent=R, bevel=0.01, rot=D(-10, 0, 0))
    L.box("Cannon_Housing", (0.14, 0.42, 0.14), (0, -0.08, 0.12), "Crimson", parent=R, bevel=0.03, taper_top=(0.85, 1))
    L.box("Cannon_Core", (0.145, 0.12, 0.05), (0, -0.05, 0.12), "EmissiveRed", parent=R, bevel=0.01)
    L.box("Cannon_Battery", (0.1, 0.12, 0.12), (0, 0.18, 0.12), "Gunmetal", parent=R, bevel=0.02)
    barrel = L.empty("Cannon_Barrels", (0, -0.29, 0.12), parent=R)
    for i in range(3):
        a = math.radians(i * 120)
        ring_y(f"Cannon_Barrel{i}", 0.018, 0.018, 0.3, -0.15, "Gunmetal", barrel, x=math.cos(a) * 0.035, z=math.sin(a) * 0.035, segs=12)
    L.torus("Cannon_Clamp", 0.06, 0.008, (0, -0.25, 0), "Black", parent=barrel, rot=D(90, 0, 0), seg=20, ring=4)
    L.clip(barrel, "Gear_Fire", [(0, (0, 0, 0)), (12, D(0, 360, 0))])
    L.empty("Muzzle", (0, -0.6, 0.12), parent=R)
    L.empty("OffHand", (0, -0.2, 0.04), parent=R)
    return dict(attach="Socket_Hand_R", anchors=["Muzzle", "OffHand"], note="rotary emitter spins on Gear_Fire")


def energy_blade(R):
    L.cyl("Blade_Hilt", 0.016, 0.017, 0.16, (0, 0, 0.0), "Gunmetal", parent=R, segs=16)
    L.cyl("Blade_Wrap", 0.018, 0.018, 0.09, (0, 0, -0.01), "Rubber", parent=R, segs=16)
    L.box("Blade_Guard", (0.09, 0.03, 0.02), (0, 0, 0.09), "Crimson", parent=R, bevel=0.006, taper_top=(0.7, 1))
    L.cyl("Blade_Pommel", 0.02, 0.014, 0.02, (0, 0, -0.09), "Crimson", parent=R, segs=8)
    edge = L.empty("Blade_Edge", (0, 0, 0.1), parent=R)
    L.box("Blade_Energy", (0.035, 0.008, 0.7), (0, 0, 0.35), "EmissiveRed", parent=edge, bevel=0.003, taper_top=(0.2, 1))
    L.clip(edge, "Gear_Deploy", [(0, (1, 1, 0.01)), (6, (1, 1, 1.05)), (9, (1, 1, 1))], path="scale")
    L.empty("Tip", (0, 0, 0.8), parent=R)
    return dict(attach="Socket_Hand_R", anchors=["Tip"], note="hard-light blade extends on Gear_Deploy; blade along +Z (up)")


GEAR = {
    "batarang": ("Crimson Batarang", "gadget", batarang),
    "grapple": ("Grapnel Gun", "gadget", grapple),
    "scanner": ("Tactical Scanner", "gadget", scanner),
    "drone": ("Recon Drone", "gadget", drone),
    "smoke": ("Smoke Pellet", "gadget", smoke),
    "shield": ("Energy Shield", "gadget", shield),
    "cloak": ("Optical Cloak", "gadget", cloak),
    "beacon": ("Tracking Beacon", "gadget", beacon),
    "emp": ("EMP Device", "gadget", emp),
    "sonic": ("Sonic Emitter", "gadget", sonic),
    "decoy": ("Hologram Decoy", "gadget", decoy),
    "holoprojector": ("Holoprojector", "gadget", holoprojector),
    "gauntlet": ("Wrist Gauntlet", "gadget", gauntlet),
    "phantom_sidearm": ("Phantom Sidearm", "fictional_weapon", phantom_sidearm),
    "crimson_carbine": ("Crimson Carbine", "fictional_weapon", crimson_carbine),
    "energy_launcher": ("Energy Launcher", "fictional_weapon", energy_launcher),
    "energy_cannon": ("Energy Cannon", "fictional_weapon", energy_cannon),
    "energy_blade": ("Energy Blade", "fictional_weapon", energy_blade),
}


def build(key):
    label, cat, fn = GEAR[key]
    L.reset()
    root = L.empty(f"Gear_{key}", (0, 0, 0))
    info = fn(root)
    root["attach"] = info["attach"]
    root["inventory_id"] = key
    path = os.path.join(OUT_DIR, f"gear_{key}.glb")
    L.export(path, animations=True)
    objs = L.descendants(root)
    clips = sorted({t.name for o in objs if o.animation_data for t in o.animation_data.nla_tracks})
    pivots = [o.name for o in objs if o.type == "EMPTY" and o.animation_data and o is not root]
    tris = L.tri_count(objs)
    print(f"[GEAR] {key}: {tris} tris, clips={clips}")
    return dict(id=f"gear_{key}", inventory_id=key, label=label, category=cat, file=os.path.relpath(path, ROOT).replace("\\", "/"),
                triangles=tris, rigged=False, attach=info["attach"], origin=info.get("origin", "grip"), anchors=info["anchors"],
                pivots=pivots, clips=clips, note=info["note"])


def main():
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = [build(k) for k in GEAR if not only or k in only]
    if not only:
        with open(OUT_JSON, "w", encoding="utf-8") as fh:
            json.dump({"source": "tools/blender/ck_build_gear.py", "forward": "+Z (Three.js)",
                       "conventions": "origin = grip; attach = CR-X9 v2 socket; Muzzle/Emitter/OffHand/Tip anchors; Gear_* clips",
                       "gear": out}, fh, indent=2)
    print(f"[GEAR] OK {len(out)} models")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
