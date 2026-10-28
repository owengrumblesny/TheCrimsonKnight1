"""Crimson Knight: Earth-RED — the Red Citadel, explorable underground headquarters (Blender 4.2+/5.x).

Output: assets/models/citadel/red_citadel.glb (+ .blend). Layout (metres, Blender Z up, +Y = north):
  * Hub cavern (ellipse ~100 x 84 m, 30 m high): displaced rock shell, stalactites, waterfall, vents,
    support girders, elevated walkway ring + bridge, and the 9.1 m (30 ft) CR-X9 statue on its pedestal
  * Command center (east, raised 5 m): curved monitor wall, central computer, consoles, servers, holo table
  * Armor workshop (west): CR-X9 display chamber, maintenance arms, cabinets, tool racks, spare plates
  * Armory (north-west, enclosed): cabinets, lockers, workbench with the armored gadget briefcase
  * Hangar hall (north): CR-X1 bay, CR-B1 bay, maintenance garage; CR-A1 hangar + 90 m runway tunnel
  * South corridor with 13 rooms: research lab, forensic lab, medical bay, training, drone workshop,
    server room, security room, trophy vault, living quarters, storage, power facility, arrival elevator,
    emergency tunnel
Structure for the game:
  Room_<Name>      empty grouping each room's static meshes (room-based visibility)
  Door_<Name>      sliding door pivots (separate moving meshes), Elevator_Platform (moving platform)
  *_COL            collision boxes          Light_<Room>_<n>  light points (extras: color, intensity, range)
  Anchor_*         arrival point, exit, vehicle parking spots for CR-X1 / CR-B1 / CR-A1
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

OUT = os.path.join(L.ROOT, "assets", "models", "citadel", "red_citadel.glb")
HERO = os.path.join(L.ROOT, "assets", "models", "characters", "crimson_knight_CRX9_rigged.glb")
random.seed(27052010)
ROOMS = {}


def room_root(name):
    r = L.empty("Room_" + name, (0, 0, 0))
    ROOMS[name] = r
    return r


def light(room, idx, loc, color=(1.0, 0.25, 0.22), intensity=40.0, rng=18.0):
    e = L.empty(f"Light_{room.name[5:]}_{idx}", loc, room)
    e["color"] = list(color)
    e["intensity"] = intensity
    e["range"] = rng
    return e


def strip_light(room, name, loc, length, axis="x"):
    dims = (length, 0.12, 0.06) if axis == "x" else (0.12, length, 0.06)
    L.box(name, dims, loc, "EmissiveRed", room, bevel=0)


def stairs(room, name, start, direction, steps, rise, run, width, mat="Grate"):
    d = Vector(direction).normalized()
    for i in range(steps):
        c = Vector(start) + d * (run * (i + 0.5)) + Vector((0, 0, rise * (i + 0.5)))
        dims = (width, run, rise * (i + 1)) if abs(d.y) > 0.5 else (run, width, rise * (i + 1))
        L.box(f"{name}_{i}", dims, (c.x, c.y, rise * (i + 1) / 2), mat, room, bevel=0.01)
    L.collider(name, (width if abs(d.y) > 0.5 else run * steps, run * steps if abs(d.y) > 0.5 else width, rise * steps * 0.6),
               tuple(Vector(start) + d * run * steps / 2 + Vector((0, 0, rise * steps * 0.3))), room)


def railing(room, name, a, b, h=1.1):
    a, b = Vector(a), Vector(b)
    n = max(2, int((b - a).length / 2.5) + 1)
    for i in range(n):
        p = a.lerp(b, i / (n - 1))
        L.box(f"{name}_post{i}", (0.06, 0.06, h), (p.x, p.y, p.z + h / 2), "Gunmetal", room, bevel=0.01)
    mid = (a + b) / 2
    ang = math.atan2(b.y - a.y, b.x - a.x)
    L.box(f"{name}_rail", ((b - a).length, 0.06, 0.06), (mid.x, mid.y, mid.z + h), "Crimson", room, bevel=0.01, rot=(0, 0, ang))


# --------------------------------------------------------------------------------------
# small furniture / equipment kit for rooms
# --------------------------------------------------------------------------------------
def desk(r, n, x, y, z=0, rot=0):
    L.box(n + "_top", (1.8, 0.8, 0.06), (x, y, z + 0.76), "Gunmetal", r, bevel=0.015, rot=(0, 0, rot))
    L.box(n + "_body", (1.7, 0.6, 0.7), (x, y, z + 0.38), "Black", r, bevel=0.02, rot=(0, 0, rot))
    L.box(n + "_mon", (0.9, 0.04, 0.5), (x, y + 0.2, z + 1.1), "Screen", r, bevel=0.01, rot=(0, 0, rot))
    L.box(n + "_chair", (0.55, 0.55, 0.5), (x, y - 0.75, z + 0.25), "Black", r, bevel=0.06, rot=(0, 0, rot))


def server_rack(r, n, x, y, z=0):
    L.box(n, (0.65, 1.0, 2.2), (x, y, z + 1.1), "Gunmetal", r, bevel=0.02)
    for i in range(6):
        L.box(f"{n}_led{i}", (0.5, 0.02, 0.03), (x, y - 0.51, z + 0.4 + i * 0.3), "EmissiveRed" if i % 2 else "Screen", r, bevel=0)


def cabinet(r, n, x, y, z=0, h=2.0, mat="Gunmetal"):
    L.box(n, (1.0, 0.6, h), (x, y, z + h / 2), mat, r, bevel=0.02)
    L.box(n + "_seam", (0.02, 0.62, h * 0.9), (x, y, z + h / 2), "Black", r, bevel=0)


def crate(r, n, x, y, z=0, s=1.0):
    L.box(n, (s, s, s), (x, y, z + s / 2), "Gunmetal", r, bevel=0.03)
    L.box(n + "_band", (s * 1.02, s * 1.02, 0.08), (x, y, z + s / 2), "Crimson", r, bevel=0.01)


def bed(r, n, x, y):
    L.box(n, (1.0, 2.1, 0.45), (x, y, 0.22), "Gunmetal", r, bevel=0.03)
    L.box(n + "_mat", (0.95, 2.0, 0.15), (x, y, 0.52), "Fabric", r, bevel=0.05)


def generator(r, n, x, y):
    L.cyl(n, 1.3, 1.3, 3.0, (x, y, 1.5), "Gunmetal", r, segs=24)
    L.torus(n + "_ring", 1.32, 0.06, (x, y, 2.2), "EmissiveRed", r)
    L.torus(n + "_ring2", 1.32, 0.06, (x, y, 0.8), "EmissiveRed", r)
    L.cyl(n + "_pipe", 0.2, 0.2, 4.0, (x + 1.6, y, 2.0), "Crimson", r, segs=12)


def holo_table(r, n, x, y, z=0, rad=1.4):
    L.cyl(n, rad, rad * 1.1, 0.9, (x, y, z + 0.45), "Gunmetal", r, segs=32)
    L.cyl(n + "_disc", rad * 0.9, rad * 0.9, 0.02, (x, y, z + 0.91), "Hologram", r, segs=32)
    L.cyl(n + "_holo", rad * 0.75, rad * 0.2, 1.2, (x, y, z + 1.55), "Hologram", r, segs=24, cap=False)


# --------------------------------------------------------------------------------------
# enclosed room with a sliding door + sign
# --------------------------------------------------------------------------------------
def enclosed_room(name, label, cx, cy, w, d, door_side, props, h=4.5):
    """door_side: 'N' or 'S' (wall with a 3 m sliding door)."""
    r = room_root(name)
    L.box(f"{name}_floor", (w, d, 0.2), (cx, cy, -0.1), "Grate", r, bevel=0.01)
    L.box(f"{name}_ceiling", (w, d, 0.3), (cx, cy, h + 0.15), "Gunmetal", r, bevel=0.01)
    t = 0.3
    for side, (x, y, dims) in {"W": (cx - w / 2, cy, (t, d, h)), "E": (cx + w / 2, cy, (t, d, h))}.items():
        L.box(f"{name}_wall{side}", dims, (x, y, h / 2), "Concrete", r, bevel=0.02)
        L.collider(f"{name}_wall{side}", dims, (x, y, h / 2), r)
    for side, y in (("N", cy + d / 2), ("S", cy - d / 2)):
        if side == door_side:
            seg = (w - 3) / 2
            for k in (-1, 1):
                L.box(f"{name}_wall{side}{k}", (seg, t, h), (cx + k * (1.5 + seg / 2), y, h / 2), "Concrete", r, bevel=0.02)
                L.collider(f"{name}_wall{side}{k}", (seg, t, h), (cx + k * (1.5 + seg / 2), y, h / 2), r)
            L.box(f"{name}_lintel", (3.2, t, h - 3.1), (cx, y, 3.1 + (h - 3.1) / 2), "Concrete", r, bevel=0.02)
            L.box(f"{name}_frame", (3.3, t + 0.1, 0.12), (cx, y, 3.05), "Crimson", r, bevel=0.01)
            door = L.empty(f"Door_{name}", (cx, y, 0), None)
            L.box(f"{name}_door", (3.0, 0.15, 3.0), (0, 0, 1.5), "Gunmetal", door, bevel=0.03)
            L.box(f"{name}_door_strip", (2.6, 0.17, 0.05), (0, 0, 1.6), "EmissiveRed", door, bevel=0)
            sy = y + (0.2 if side == "N" else -0.2)
            L.text_mesh(f"{name}_sign", label, 0.32, (cx, sy, 3.6), "EmissiveRed", r, rot=L.deg(90, 0, 0 if side == "S" else 180))
        else:
            L.box(f"{name}_wall{side}", (w, t, h), (cx, y, h / 2), "Concrete", r, bevel=0.02)
            L.collider(f"{name}_wall{side}", (w, t, h), (cx, y, h / 2), r)
    L.collider(f"{name}_floor", (w, d, 0.4), (cx, cy, -0.2), r)
    strip_light(r, f"{name}_lightstrip", (cx, cy, h - 0.05), w * 0.7)
    light(r, 0, (cx, cy, h - 0.6), (1.0, 0.82, 0.75), 30, max(w, d))
    props(r, cx, cy, w, d)
    return r


def south_rooms():
    def research(r, cx, cy, w, d):
        for i in range(3):
            desk(r, f"res_desk{i}", cx - 5 + i * 5, cy + 2)
        holo_table(r, "res_holo", cx, cy - 2.5)
        for i in range(4):
            cabinet(r, f"res_cab{i}", cx - w / 2 + 0.8, cy - 4 + i * 1.6, mat="Gunmetal")

    def forensic(r, cx, cy, w, d):
        L.box("for_table", (2.4, 1.2, 0.95), (cx, cy, 0.48), "Gunmetal", r, bevel=0.03)
        L.box("for_glass", (2.0, 1.0, 0.02), (cx, cy, 0.97), "Glass", r, bevel=0)
        for i in range(2):
            desk(r, f"for_desk{i}", cx - 4 + i * 8, cy + 3)
        L.box("for_wall_screen", (5, 0.05, 2.0), (cx, cy + d / 2 - 0.25, 2.3), "Screen", r, bevel=0)

    def medical(r, cx, cy, w, d):
        for i in range(3):
            bed(r, f"med_bed{i}", cx - 5 + i * 5, cy + 1)
            L.torus(f"med_scan{i}", 0.7, 0.07, (cx - 5 + i * 5, cy + 1, 1.2), "Hologram", r, L.deg(90, 0, 0))
        cabinet(r, "med_cab", cx + w / 2 - 0.8, cy - 3, mat="Concrete")

    def training(r, cx, cy, w, d):
        L.box("trn_mat", (w - 4, d - 4, 0.06), (cx, cy, 0.03), "Black", r, bevel=0.01)
        for i in range(5):
            x = cx - 8 + i * 4
            L.cyl(f"trn_dummy{i}", 0.3, 0.35, 1.8, (x, cy + 2, 0.9), "Gunmetal", r, segs=12)
            L.box(f"trn_target{i}", (0.6, 0.05, 0.6), (x, cy - d / 2 + 0.4, 1.7), "Crimson", r, bevel=0.01)
        for i in range(3):
            L.box(f"trn_box{i}", (2, 2, 1.0 + i * 0.6), (cx + 8, cy - 4 + i * 3, 0.5 + i * 0.3), "Concrete", r, bevel=0.03)

    def drones(r, cx, cy, w, d):
        L.box("drn_bench", (5, 1.4, 0.95), (cx, cy, 0.48), "Gunmetal", r, bevel=0.03)
        for i in range(4):
            x = cx - 1.8 + i * 1.2
            L.box(f"drn_body{i}", (0.4, 0.4, 0.12), (x, cy, 1.02), "Crimson", r, bevel=0.03)
            for a in range(4):
                ang = a * math.pi / 2 + math.pi / 4
                L.cyl(f"drn_rotor{i}{a}", 0.13, 0.13, 0.02, (x + math.cos(ang) * 0.28, cy + math.sin(ang) * 0.28, 1.1), "Black", r, segs=12)
        for i in range(4):
            L.box(f"drn_shelf{i}", (4, 0.5, 0.05), (cx, cy + d / 2 - 0.5, 0.8 + i * 0.6), "Gunmetal", r, bevel=0.01)

    def servers(r, cx, cy, w, d):
        for row in range(2):
            for i in range(6):
                server_rack(r, f"srv{row}_{i}", cx - 5 + i * 2, cy - 2 + row * 4)

    def security(r, cx, cy, w, d):
        L.box("sec_console", (6, 1.2, 1.0), (cx, cy - 1, 0.5), "Gunmetal", r, bevel=0.04)
        for i in range(6):
            L.box(f"sec_screen{i}", (1.6, 0.05, 0.9), (cx - 4.2 + (i % 3) * 4.2 / 1.5 + 1.2, cy + d / 2 - 0.3, 1.4 + (i // 3) * 1.0), "Screen", r, bevel=0)
        L.box("sec_chair", (0.6, 0.6, 0.5), (cx, cy - 2.2, 0.25), "Black", r, bevel=0.06)

    def vault(r, cx, cy, w, d):
        for i in range(6):
            x = cx - 6 + (i % 3) * 6
            y = cy - 2 + (i // 3) * 4
            L.box(f"vlt_plinth{i}", (1.2, 1.2, 1.0), (x, y, 0.5), "Black", r, bevel=0.03)
            L.box(f"vlt_case{i}", (1.1, 1.1, 1.0), (x, y, 1.5), "Glass", r, bevel=0.01)
            L.box(f"vlt_item{i}", (0.4, 0.3, 0.3), (x, y, 1.25), "Crimson" if i % 2 else "Gunmetal", r, bevel=0.05, rot=(0, 0, i))

    def quarters(r, cx, cy, w, d):
        bed(r, "liv_bed", cx - 5, cy + 2)
        L.box("liv_sofa", (2.6, 0.9, 0.5), (cx + 3, cy - 2, 0.25), "Fabric", r, bevel=0.08)
        L.box("liv_sofa_back", (2.6, 0.25, 0.6), (cx + 3, cy - 2.45, 0.7), "Fabric", r, bevel=0.06)
        L.box("liv_table", (1.2, 0.7, 0.45), (cx + 3, cy - 0.6, 0.23), "Wood", r, bevel=0.02)
        L.box("liv_tv", (2.2, 0.06, 1.2), (cx + 3, cy + d / 2 - 0.3, 1.6), "Screen", r, bevel=0)
        L.box("liv_kitchen", (4, 0.7, 0.95), (cx - 3, cy - d / 2 + 0.6, 0.48), "Concrete", r, bevel=0.02)

    def storage(r, cx, cy, w, d):
        for i in range(12):
            crate(r, f"sto_crate{i}", cx - 6 + (i % 6) * 2.3, cy - 3 + (i // 6) * 4, 0, 1.2)
        for i in range(3):
            crate(r, f"sto_stack{i}", cx - 6 + i * 2.3, cy - 3, 1.2, 1.0)

    def power(r, cx, cy, w, d):
        generator(r, "pwr_gen0", cx - 4, cy)
        generator(r, "pwr_gen1", cx + 4, cy)
        for i in range(6):
            cabinet(r, f"pwr_panel{i}", cx - 6 + i * 2.4, cy + d / 2 - 0.5, h=2.2)

    specs = [
        ("ResearchLab", "RESEARCH LAB", -60, -63, research), ("ForensicLab", "FORENSIC LAB", -40, -63, forensic),
        ("MedicalBay", "MEDICAL BAY", -20, -63, medical), ("Training", "TRAINING", 0, -65, training),
        ("DroneWorkshop", "DRONE WORKSHOP", 20, -63, drones), ("ServerRoom", "SERVER ROOM", 40, -63, servers),
        ("SecurityRoom", "SECURITY", 60, -63, security),
    ]
    for name, label, x, y, fn in specs:
        dims = (24, 18) if name == "Training" else (18, 14)
        enclosed_room(name, label, x, y, dims[0], dims[1], "N", fn)
    for name, label, x, y, fn in (("TrophyVault", "TROPHY VAULT", -60, -41, vault), ("LivingQuarters", "LIVING QUARTERS", -40, -41, quarters),
                                  ("Storage", "STORAGE", 40, -41, storage), ("PowerFacility", "POWER FACILITY", 60, -41, power)):
        enclosed_room(name, label, x, y, 18, 14, "S", fn)


def corridor():
    r = room_root("Corridor")
    L.box("cor_floor", (146, 8, 0.2), (0, -52, -0.1), "Grate", r, bevel=0.01)
    L.collider("cor_floor", (146, 8, 0.4), (0, -52, -0.2), r)
    L.box("cor_ceiling", (146, 8, 0.3), (0, -52, 4.65), "Gunmetal", r, bevel=0.01)
    for i in range(15):
        x = -70 + i * 10
        L.box(f"cor_rib{i}", (0.4, 8.2, 0.4), (x, -52, 4.4), "Crimson", r, bevel=0.02)
        strip_light(r, f"cor_light{i}", (x + 5, -52, 4.45), 3.0)
    for i in range(5):
        light(r, i, (-56 + i * 28, -52, 3.8), (1.0, 0.3, 0.25), 25, 22)
    # arrival elevator (north side of the corridor, opening into the hub tunnel)
    el = room_root("Elevator")
    L.box("elv_shaft_back", (6, 0.3, 12), (12, -47.5, 6), "Concrete", el, bevel=0.02)
    for k in (-1, 1):
        L.box(f"elv_shaft_side{k}", (0.3, 5, 12), (12 + k * 3, -50, 6), "Concrete", el, bevel=0.02)
    platform = L.empty("Elevator_Platform", (12, -50, 0), None)
    L.box("elv_platform", (5.4, 4.4, 0.25), (0, 0, 0.12), "Grate", platform, bevel=0.02)
    L.box("elv_rail", (5.4, 0.08, 0.08), (0, -2.1, 1.1), "Crimson", platform, bevel=0.01)
    L.text_mesh("elv_sign", "ELEVATOR - NEW GOTHAM", 0.3, (12, -47.7, 3.7), "EmissiveRed", el, rot=L.deg(90, 0, 0))
    L.empty("Anchor_Arrival", (12, -51, 0.3), None)
    L.empty("Anchor_Exit", (12, -50, 0.3), None)
    # hub access tunnel
    tun = room_root("HubTunnel")
    L.box("tun_floor", (10, 10, 0.2), (0, -43, -0.1), "Grate", tun, bevel=0.01)
    L.collider("tun_floor", (10, 10, 0.4), (0, -43, -0.2), tun)
    for k in (-1, 1):
        L.box(f"tun_wall{k}", (0.6, 10, 6), (k * 5.3, -43, 3), "Concrete", tun, bevel=0.03)
        L.collider(f"tun_wall{k}", (0.6, 10, 6), (k * 5.3, -43, 3), tun)
    L.box("tun_arch", (11, 10, 0.6), (0, -43, 6.2), "Gunmetal", tun, bevel=0.03)
    # emergency tunnel at the west end
    em = room_root("EmergencyTunnel")
    L.box("em_floor", (40, 5, 0.2), (-93, -52, -0.1), "Concrete", em, bevel=0.01)
    L.collider("em_floor", (40, 5, 0.4), (-93, -52, -0.2), em)
    for i in range(8):
        L.torus(f"em_ring{i}", 3.0, 0.15, (-76 - i * 5, -52, 1.6), "Gunmetal", em, L.deg(0, 90, 0), seg=24, ring=6)
        L.box(f"em_light{i}", (0.6, 0.1, 0.1), (-76 - i * 5, -49.6, 2.5), "EmissiveRed", em, bevel=0)
    L.text_mesh("em_sign", "EMERGENCY EXIT", 0.35, (-73, -52, 3.6), "EmissiveRed", em, rot=L.deg(90, 0, 90))
    light(em, 0, (-90, -52, 3), (1.0, 0.1, 0.1), 20, 20)


# --------------------------------------------------------------------------------------
# hub cavern, statue, command center, workshop, armory
# --------------------------------------------------------------------------------------
def cavern():
    r = room_root("Hub")
    rx, ry, rz = 52, 44, 30
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=1.0)
    for v in bm.verts:
        p = v.co.copy()
        n = noise.fractal(p * 2.4, 0.6, 2.0, 4) * 0.12 + noise.noise(p * 7.0) * 0.03
        v.co = Vector((p.x * rx * (1 + n), p.y * ry * (1 + n), max(-0.3, p.z) * rz * (1 + n)))
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])  # we live inside it
    L.obj_from_bm("hub_rock", bm, "Stone", r)
    L.box("hub_floor", (96, 80, 0.4), (0, 0, -0.2), "Concrete", r, bevel=0.02)
    L.collider("hub_floor", (104, 88, 0.6), (0, 0, -0.3), r)
    for i in range(16):  # rock wall collision ring
        if i in (4, 12):  # tunnel mouths (hangar tunnel / hub access tunnel) stay open
            continue
        a = 2 * math.pi * i / 16
        L.collider(f"hub_wall{i}", (14, 3, 12), (math.cos(a) * (rx - 4), math.sin(a) * (ry - 4), 6), r).rotation_euler = (0, 0, a + math.pi / 2)
    # grate panels set into the floor + painted lanes
    for i in range(-4, 5):
        L.box(f"hub_grate{i}", (4, 70, 0.03), (i * 9, 0, 0.01), "Grate", r, bevel=0)
    for i in range(40):  # stalactites
        a = random.uniform(0, 2 * math.pi)
        d = random.uniform(0.2, 0.85)
        x, y = math.cos(a) * rx * d, math.sin(a) * ry * d
        z = rz * math.sqrt(max(0.05, 1 - d * d)) - 0.5
        ln = random.uniform(2, 7)
        L.cyl(f"hub_stal{i}", random.uniform(0.4, 1.1), 0.02, ln, (x, y, z - ln / 2), "Stone", r, segs=7, bevel=0)
    # waterfall down the west wall into a pool
    L.box("hub_waterfall", (0.4, 10, 26), (-48, -16, 13), "Water", r, bevel=0)
    L.box("hub_pool", (8, 14, 0.3), (-44, -16, 0.15), "Water", r, bevel=0.05)
    # support structure: girder pillars + overhead trusses
    for i in range(8):
        a = 2 * math.pi * (i + 0.5) / 8
        x, y = math.cos(a) * 34, math.sin(a) * 28
        L.box(f"hub_pillar{i}", (1.4, 1.4, 22), (x, y, 11), "Gunmetal", r, bevel=0.04)
        L.box(f"hub_pillar_band{i}", (1.5, 1.5, 0.3), (x, y, 7.8), "Crimson", r, bevel=0.02)
        L.collider(f"hub_pillar{i}", (1.4, 1.4, 22), (x, y, 11), r)
        strip_light(r, f"hub_pillar_light{i}", (x, y, 21.5), 1.2)
    for i in range(4):
        L.box(f"hub_truss{i}", (70, 0.8, 0.8), (0, -24 + i * 16, 22.5), "Gunmetal", r, bevel=0.03)
    # ventilation drums
    for i, (x, y) in enumerate(((44, -18), (-40, 24), (38, 26))):
        L.cyl(f"hub_vent{i}", 2.4, 2.4, 1.2, (x, y, 14), "Gunmetal", r, L.deg(0, 90, 0), segs=24)
        L.cyl(f"hub_vent_fan{i}", 2.0, 2.0, 0.2, (x, y, 14), "Black", r, L.deg(0, 90, 0), segs=24)
    # elevated walkway (z 8) along the south wall + bridge crossing north of the statue (z 14)
    L.box("hub_walk_south", (60, 3, 0.3), (0, -36, 8), "Grate", r, bevel=0.01)
    L.collider("hub_walk_south", (60, 3, 0.5), (0, -36, 7.9), r)
    railing(r, "hub_walk_rail", (-30, -34.6, 8.15), (30, -34.6, 8.15))
    stairs(r, "hub_walk_stairs", (-34, -36, 0), (1, 0, 0), 20, 0.4, 0.5, 3)
    L.box("hub_bridge", (64, 3, 0.4), (0, 18, 14), "Grate", r, bevel=0.01)
    L.collider("hub_bridge", (64, 3, 0.6), (0, 18, 13.9), r)
    railing(r, "hub_bridge_rail_n", (-32, 19.4, 14.2), (32, 19.4, 14.2))
    railing(r, "hub_bridge_rail_s", (-32, 16.6, 14.2), (32, 16.6, 14.2))
    for k in (-1, 1):
        L.box(f"hub_bridge_cable{k}", (0.08, 0.08, 8), (k * 14, 18, 18.5), "Gunmetal", r, bevel=0)
    for i in range(6):
        light(r, i, (math.cos(i) * 30, math.sin(i) * 24, 18), (1.0, 0.2, 0.18), 120, 40)
    light(r, 6, (0, -8, 16), (1.0, 0.85, 0.8), 160, 30)  # statue key light
    return r


def statue(r):
    """The 30 ft CR-X9 statue: the real v2 armor, posed (CK_Idle frame 0), scaled ×4.4, on a black pedestal."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=HERO)
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == "ARMATURE")
    act = bpy.data.actions.get("CK_Idle") or next(a for a in bpy.data.actions if a.name.startswith("CK_Idle"))
    ad = rig.animation_data or rig.animation_data_create()
    for tr in ad.nla_tracks:
        tr.mute = True
    ad.action = act
    if hasattr(ad, "action_slot") and getattr(act, "slots", None):
        ad.action_slot = act.slots[0]
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    scale = 9.1 / 2.08
    parts = []
    for o in new:
        if o.type == "MESH" and o.name.endswith("_LOD1"):
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
            me.transform(o.matrix_world)
            s = bpy.data.objects.new("statue_" + o.name.replace("_LOD1", ""), me)
            bpy.context.scene.collection.objects.link(s)
            s.scale = (scale,) * 3
            s.location = (0, 0, 2.6)
            s.parent = r
            parts.append(s)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    L.box("statue_pedestal", (7, 7, 2.6), (0, 0, 1.3), "Black", r, bevel=0.08)
    L.box("statue_pedestal_trim", (7.2, 7.2, 0.25), (0, 0, 2.5), "Crimson", r, bevel=0.03)
    L.collider("statue", (7, 7, 11.5), (0, 0, 5.75), r)
    for i, (line, size) in enumerate((("OWEN GRUMBLES", 0.55), ("THE CRIMSON KNIGHT", 0.42), ("FOUNDER — OWEN ENTERPRISES", 0.3))):
        L.text_mesh(f"statue_inscription{i}", line, size, (0, -3.53, 1.9 - i * 0.62), "Gunmetal", r, rot=L.deg(90, 0, 0), extrude=0.02)
    return parts


def command_center():
    r = room_root("Command")
    L.box("cmd_platform", (22, 18, 0.6), (36, 2, 4.7), "Grate", r, bevel=0.03)
    L.collider("cmd_platform", (22, 18, 1.0), (36, 2, 4.5), r)
    for i in range(6):
        L.box(f"cmd_leg{i}", (0.8, 0.8, 4.6), (27 + (i % 3) * 9, -5 + (i // 3) * 14, 2.3), "Gunmetal", r, bevel=0.03)
    stairs(r, "cmd_stairs", (25.0, -4, 0), (1, 0, 0), 10, 0.5, 0.6, 3)
    railing(r, "cmd_rail", (25, 11, 5.0), (47, 11, 5.0))
    # massive central computer: curved wall of screens around a core
    for i in range(9):
        a = math.radians(-60 + i * 15)
        x, y = 36 + math.sin(a) * 9, 4 + math.cos(a) * 9
        for row in range(3):
            L.box(f"cmd_screen{i}_{row}", (2.3, 0.08, 1.3), (x, y, 6.4 + row * 1.4), "Screen", r, bevel=0.01, rot=(0, 0, -a))
        L.box(f"cmd_frame{i}", (2.4, 0.3, 4.6), (x + math.sin(a) * 0.2, y + math.cos(a) * 0.2, 7.7), "Gunmetal", r, bevel=0.02, rot=(0, 0, -a))
    L.cyl("cmd_core", 1.2, 1.4, 6, (36, 13.5, 8), "Gunmetal", r, segs=24)
    L.torus("cmd_core_ring", 1.45, 0.08, (36, 13.5, 9.5), "EmissiveRed", r)
    L.text_mesh("cmd_title", "O.E. TACTICAL NETWORK", 0.5, (36, 12.1, 11.6), "EmissiveRed", r, rot=L.deg(90, 0, 0))
    for i in range(3):  # curved tactical consoles
        a = math.radians(-30 + i * 30)
        L.box(f"cmd_console{i}", (3.2, 1.0, 1.0), (36 + math.sin(a) * 5, 4 + math.cos(a) * 5, 5.5), "Gunmetal", r, bevel=0.04, rot=(0, 0, -a))
        L.box(f"cmd_console_top{i}", (3.0, 0.9, 0.04), (36 + math.sin(a) * 5, 4 + math.cos(a) * 5, 6.02), "Screen", r, bevel=0, rot=(-0.2, 0, -a))
    L.box("cmd_chair", (0.8, 0.8, 1.2), (36, 1.5, 5.6), "Black", r, bevel=0.1)
    holo_table(r, "cmd_holo", 36, -3.5, 5.0, 1.8)
    for i in range(4):
        server_rack(r, f"cmd_rack{i}", 45.5, -5 + i * 1.2, 5.0)
    for i in range(2):  # communications stations
        desk(r, f"cmd_comms{i}", 28, -3 + i * 5, 5.0, rot=math.pi / 2)
    strip_light(r, "cmd_edge", (36, -7, 5.05), 22)
    light(r, 0, (36, 4, 10), (1.0, 0.2, 0.2), 80, 20)
    light(r, 1, (36, -3.5, 8), (1.0, 0.3, 0.3), 40, 12)
    return r


def workshop():
    r = room_root("Workshop")
    L.box("wks_floor", (16, 18, 0.2), (-36, 2, 0.1), "Grate", r, bevel=0.01)
    # CR-X9 armor display chamber: glass cylinder, base ring, lights
    L.cyl("wks_chamber_base", 1.8, 1.9, 0.5, (-40, 6, 0.45), "Gunmetal", r, segs=32)
    L.cyl("wks_chamber_glass", 1.6, 1.6, 3.2, (-40, 6, 2.3), "Glass", r, segs=32, cap=False)
    L.cyl("wks_chamber_cap", 1.8, 1.7, 0.4, (-40, 6, 4.1), "Gunmetal", r, segs=32)
    L.torus("wks_chamber_ring", 1.82, 0.05, (-40, 6, 0.75), "EmissiveRed", r)
    L.empty("Anchor_ArmorDisplay", (-40, 6, 0.7), r)
    # maintenance arms (base, segments) and platforms
    for k, (x, y) in enumerate(((-36.5, 8.5), (-43.5, 3.5))):
        L.cyl(f"wks_arm_base{k}", 0.4, 0.5, 0.6, (x, y, 0.3), "Gunmetal", r, segs=16)
        L.box(f"wks_arm_a{k}", (0.25, 0.25, 2.2), (x, y, 1.6), "Crimson", r, bevel=0.03, rot=L.deg(0, 20 - 40 * k, 0))
        L.box(f"wks_arm_b{k}", (0.2, 0.2, 1.6), (x + (0.6 if k == 0 else -0.6), y, 3.0), "Gunmetal", r, bevel=0.03, rot=L.deg(0, -60 + 120 * k, 0))
    L.box("wks_platform", (5, 3, 1.0), (-33, 0, 0.5), "Grate", r, bevel=0.02)
    L.collider("wks_platform", (5, 3, 1.0), (-33, 0, 0.5), r)
    for i in range(4):
        cabinet(r, f"wks_cab{i}", -43.5, -4 + i * 1.2)
    L.box("wks_rack", (0.15, 2.8, 1.8), (-43.9, 10.0, 1.4), "Gunmetal", r, bevel=0.01)  # tool rack
    for i in range(6):
        L.box(f"wks_tool{i}", (0.1, 0.08, 0.6), (-43.7, 9.0 + i * 0.4, 1.5), "Crimson" if i % 2 else "Black", r, bevel=0.01)
    for i in range(3):  # diagnostic screens
        L.box(f"wks_diag{i}", (1.8, 0.06, 1.1), (-38 + i * 2.2, 10.8, 2.2), "Screen", r, bevel=0.01)
    L.box("wks_bench", (1.0, 2.4, 0.9), (-34, -4.4, 0.45), "Gunmetal", r, bevel=0.02)
    for i in range(5):  # spare armour components on the bench
        L.box(f"wks_spare{i}", (0.45, 0.3, 0.12 + 0.05 * i), (-34, -5.2 + i * 0.4, 0.98), "Crimson", r, bevel=0.04, rot=(0.2, 0, i))
    strip_light(r, "wks_light", (-36, 2, 6), 10)
    light(r, 0, (-38, 5, 6), (1.0, 0.85, 0.8), 60, 16)
    light(r, 1, (-40, 6, 4.2), (1.0, 0.15, 0.15), 25, 6)
    return r


def armory():
    def props(r, cx, cy, w, d):
        for i in range(8):  # reinforced lockers
            L.box(f"arm_locker{i}", (0.9, 0.7, 2.2), (cx - w / 2 + 0.7, cy - 5 + i * 1.3, 1.1), "Gunmetal", r, bevel=0.02)
            L.box(f"arm_locker_vent{i}", (0.02, 0.4, 0.3), (cx - w / 2 + 1.16, cy - 5 + i * 1.3, 1.8), "Black", r, bevel=0)
        for i in range(3):  # gadget display cases
            L.box(f"arm_case{i}", (1.2, 0.8, 1.0), (cx + w / 2 - 1.2, cy - 3 + i * 2.4, 0.5), "Black", r, bevel=0.02)
            L.box(f"arm_case_glass{i}", (1.1, 0.7, 0.7), (cx + w / 2 - 1.2, cy - 3 + i * 2.4, 1.35), "Glass", r, bevel=0.01)
            L.box(f"arm_case_item{i}", (0.4, 0.25, 0.1), (cx + w / 2 - 1.2, cy - 3 + i * 2.4, 1.1), "Crimson", r, bevel=0.03, rot=(0, 0, 0.6))
        # workbench with the armored briefcase: open lid, black foam insert, fitted gadget compartments
        L.box("arm_bench", (3.0, 1.3, 0.92), (cx, cy + 1, 0.46), "Gunmetal", r, bevel=0.03)
        L.box("arm_case_shell", (1.2, 0.85, 0.16), (cx, cy + 1, 1.0), "Crimson", r, bevel=0.03)
        L.box("arm_case_foam", (1.1, 0.75, 0.04), (cx, cy + 1, 1.09), "Foam", r, bevel=0.01)
        lid = L.box("arm_case_lid", (1.2, 0.85, 0.12), (cx, cy + 1.5, 1.45), "Crimson", r, bevel=0.03, rot=L.deg(-75, 0, 0))
        for j, (dx, dy, sx, sy) in enumerate(((-0.35, 0.15, 0.3, 0.18), (0.05, 0.15, 0.35, 0.12), (0.4, 0.15, 0.15, 0.25),
                                               (-0.35, -0.18, 0.25, 0.2), (0.05, -0.18, 0.3, 0.2), (0.4, -0.18, 0.15, 0.15))):
            L.box(f"arm_slot{j}", (sx, sy, 0.02), (cx + dx, cy + 1 + dy, 1.11), "Black", r, bevel=0)
            L.box(f"arm_gadget{j}", (sx * 0.85, sy * 0.8, 0.05), (cx + dx, cy + 1 + dy, 1.13), "Gunmetal" if j % 2 else "Crimson", r, bevel=0.01)
        L.box("arm_terminal", (0.9, 0.06, 0.6), (cx + 1.0, cy + 1.6, 1.4), "Screen", r, bevel=0.01, rot=(-0.3, 0, 0))
        _ = lid
    enclosed_room("Armory", "ARMORY", -33, 26, 16, 12, "S", props)


def hangars():
    r = room_root("HangarHall")
    L.box("hng_floor", (64, 26, 0.3), (0, 60, -0.15), "Concrete", r, bevel=0.01)
    L.collider("hng_floor", (64, 26, 0.6), (0, 60, -0.3), r)
    L.box("hng_ceiling", (64, 26, 0.4), (0, 60, 9.2), "Gunmetal", r, bevel=0.01)
    for k in (-1, 1):
        L.box(f"hng_wall{k}", (0.6, 26, 9), (k * 32, 60, 4.5), "Concrete", r, bevel=0.02)
        L.collider(f"hng_wall{k}", (0.6, 26, 9), (k * 32, 60, 4.5), r)
    L.box("hng_tunnel_floor", (12, 8, 0.3), (0, 44, -0.15), "Concrete", r, bevel=0.01)
    L.collider("hng_tunnel_floor", (12, 8, 0.6), (0, 44, -0.3), r)
    L.box("hng_road", (5, 34, 0.04), (0, 57, 0.02), "Asphalt", r, bevel=0)
    for i in range(8):
        L.box(f"hng_lane{i}", (0.2, 1.6, 0.02), (0, 42 + i * 4, 0.05), "EmissiveRed", r, bevel=0)
    for name, x, label in (("CRX1", -18, "CR-X1 INTERCEPTOR"), ("CRB1", 18, "CR-B1 BATCYCLE"), ("Garage", 0, "MAINTENANCE")):
        if name != "Garage":
            L.box(f"hng_pad_{name}", (10, 12, 0.12), (x, 62, 0.06), "Grate", r, bevel=0.02)
            L.torus(f"hng_pad_ring_{name}", 4.2, 0.06, (x, 62, 0.14), "EmissiveRed", r, seg=48, ring=6)
            L.empty(f"Anchor_{name}", (x, 62, 0.15), r)
            for k in (-1, 1):  # maintenance platforms each side
                L.box(f"hng_maint_{name}{k}", (1.6, 8, 1.4), (x + k * 6, 62, 0.7), "Gunmetal", r, bevel=0.03)
                L.collider(f"hng_maint_{name}{k}", (1.6, 8, 1.4), (x + k * 6, 62, 0.7), r)
                L.box(f"hng_diag_{name}{k}", (0.06, 2.0, 1.1), (x + k * 6.9, 60, 2.4), "Screen", r, bevel=0.01)
            light(r, 0 if name == "CRX1" else 1, (x, 62, 8), (1.0, 0.85, 0.8), 70, 18)
        L.text_mesh(f"hng_sign_{name}", label, 0.45, (x, 72.6, 6.5), "EmissiveRed", r, rot=L.deg(90, 0, 0))
        # industrial door at the back of each bay (vertical lift)
        door = L.empty(f"Door_Hangar{name}", (x, 72.9, 0), None)
        L.box(f"hng_door_{name}", (9, 0.3, 6), (0, 0, 3), "Gunmetal", door, bevel=0.04)
        for j in range(5):
            L.box(f"hng_door_rib_{name}{j}", (9.05, 0.32, 0.1), (0, 0, 0.8 + j * 1.1), "Crimson", door, bevel=0)
    for i in range(6):
        crate(r, f"hng_crate{i}", 26 + (i % 2) * 1.6, 50 + i * 1.5, 0, 1.2)
    L.box("hng_lift", (6, 6, 0.4), (0, 62, 0.2), "Grate", r, bevel=0.02)  # garage vehicle lift
    for k in (-1, 1):
        L.box(f"hng_lift_post{k}", (0.4, 0.4, 3.5), (k * 3.2, 62, 1.75), "Crimson", r, bevel=0.02)
    # CR-A1 Specter hangar + runway tunnel
    a1 = room_root("SpecterHangar")
    L.box("a1h_floor", (44, 34, 0.3), (0, 90, -0.15), "Concrete", a1, bevel=0.01)
    L.collider("a1h_floor", (44, 34, 0.6), (0, 90, -0.3), a1)
    L.box("a1h_ceiling", (44, 34, 0.5), (0, 90, 14.2), "Gunmetal", a1, bevel=0.01)
    for k in (-1, 1):
        L.box(f"a1h_wall{k}", (0.8, 34, 14), (k * 22, 90, 7), "Concrete", a1, bevel=0.02)
        L.collider(f"a1h_wall{k}", (0.8, 34, 14), (k * 22, 90, 7), a1)
        L.box(f"a1h_gantry{k}", (2.5, 26, 6), (k * 18.5, 90, 3), "Gunmetal", a1, bevel=0.04)
        L.collider(f"a1h_gantry{k}", (2.5, 26, 6), (k * 18.5, 90, 3), a1)
        L.box(f"a1h_screen{k}", (0.08, 4, 2), (k * 17.2, 86, 4.5), "Screen", a1, bevel=0.01)
    L.box("a1h_divider", (44, 0.6, 3), (0, 73.2, 10.5), "Concrete", a1, bevel=0.02)
    L.text_mesh("a1h_sign", "CR-A1 CRIMSON SPECTER", 0.6, (0, 106.5, 11), "EmissiveRed", a1, rot=L.deg(90, 0, 0))
    L.empty("Anchor_CRA1", (0, 90, 0.15), a1)
    for i in range(4):
        light(a1, i, (-12 + i * 8, 90, 13), (1.0, 0.85, 0.8), 90, 22)
    rw = room_root("Runway")
    L.box("rw_floor", (14, 92, 0.3), (0, 153, -0.15), "Asphalt", rw, bevel=0.01)
    L.collider("rw_floor", (14, 92, 0.6), (0, 153, -0.3), rw)
    for i in range(23):
        for k in (-1, 1):
            L.box(f"rw_edge{i}{k}", (0.25, 0.25, 0.12), (k * 6.5, 109 + i * 4, 0.06), "EmissiveRed", rw, bevel=0)
        L.box(f"rw_rib{i}", (16, 0.6, 0.6), (0, 109 + i * 4, 12), "Gunmetal", rw, bevel=0.02)
    for k in (-1, 1):
        L.box(f"rw_wall{k}", (1, 92, 12), (k * 7.5, 153, 6), "Stone", rw, bevel=0.05)
        L.collider(f"rw_wall{k}", (1, 92, 12), (k * 7.5, 153, 6), rw)
    blast = L.empty("Door_Runway", (0, 199, 0), None)
    L.box("rw_blast_door", (14, 1.0, 12), (0, 0, 6), "Gunmetal", blast, bevel=0.05)
    L.box("rw_blast_stripe", (14.05, 1.02, 0.4), (0, 0, 6), "Crimson", blast, bevel=0)
    light(rw, 0, (0, 150, 10), (1.0, 0.15, 0.12), 60, 40)


def main():
    L.reset()
    cav = cavern()
    statue(cav)
    command_center()
    workshop()
    armory()
    hangars()
    corridor()
    south_rooms()
    bpy.context.view_layer.update()
    objs = list(bpy.data.objects)
    tris = L.tri_count(objs)
    L.export(OUT, False, None)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(L.ROOT, "assets", "source", "blender", "red_citadel.blend"))
    rooms = {n: L.tri_count(L.descendants(r)) for n, r in ROOMS.items()}
    with open(os.path.join(L.ROOT, "config", "citadel_layout.json"), "w") as fh:
        json.dump({"asset": "assets/models/citadel/red_citadel.glb", "triangles": tris, "rooms": rooms,
                   "doors": sorted(o.name for o in objs if o.name.startswith("Door_")),
                   "anchors": sorted(o.name for o in objs if o.name.startswith("Anchor_")),
                   "lights": len([o for o in objs if o.name.startswith("Light_")])}, fh, indent=2)
    print(f"[citadel] OK {tris} tris, {len(ROOMS)} rooms")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
