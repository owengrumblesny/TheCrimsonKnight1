"""Render any exported GLB for visual review: six orthographic views fitted to its bounds plus one
perspective hero shot, then a labelled contact sheet (Pillow from the system Python is not needed;
the sheet is assembled with Blender's own image API).

  blender -b --factory-startup --python tools/blender/ck_render_asset.py -- <glb> <out_dir> [clip_name frame]

*_COL collision proxies are hidden. With a clip name, that glTF animation is posed at `frame` first.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
GLB, OUT = os.path.abspath(args[0]), os.path.abspath(args[1])
CLIP = args[2] if len(args) > 2 else None
FRAME = int(args[3]) if len(args) > 3 else 0


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = 30
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.13, 0.135, 0.15, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.world = w
    return sc


def main():
    sc = setup()
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=GLB)
    objs = [o for o in bpy.data.objects if o not in before]
    for o in objs:
        if o.name.endswith("_COL"):
            o.hide_render = True
    if CLIP:
        for o in objs:
            ad = o.animation_data
            if not ad:
                continue
            for tr in ad.nla_tracks:
                tr.mute = tr.name != CLIP and not tr.name.startswith(CLIP)
        act = [a for a in bpy.data.actions if a.name.startswith(CLIP)]
        if act and not any(o.animation_data and len(o.animation_data.nla_tracks) for o in objs):
            for o in objs:
                if o.animation_data:
                    o.animation_data.action = act[0]
        sc.frame_set(FRAME)
    bpy.context.view_layer.update()
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in objs:
        if o.type != "MESH" or o.hide_render:
            continue
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    center, size = (lo + hi) / 2, hi - lo
    radius = max(size) * 0.5
    for name, loc, energy, s in (("key", (-1.2, -1.6, 1.4), 900, 2.5), ("fill", (1.6, -0.8, 0.6), 300, 3), ("rim", (0.3, 1.8, 1.2), 600, 2.5)):
        d = bpy.data.lights.new(name, "AREA")
        d.energy = energy * (radius / 1.5) ** 2
        d.size = s * radius
        o = bpy.data.objects.new(name, d)
        o.location = center + Vector(loc) * radius * 2.2
        o.rotation_euler = (center - o.location).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(o)
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    os.makedirs(OUT, exist_ok=True)
    shots = []
    sc.render.resolution_x, sc.render.resolution_y = 640, 480
    cd.type = "ORTHO"
    cd.ortho_scale = max(size.x, size.y, size.z) * 1.15
    cd.clip_end = radius * 20
    for name, ang, elev in (("front", 0, 0), ("front_left_45", -45, 0), ("left", -90, 0), ("rear", 180, 0), ("top", 0, 89), ("front_right_45", 45, 15)):
        t, e = math.radians(ang), math.radians(elev)
        cam.location = center + Vector((math.sin(t) * math.cos(e), -math.cos(t) * math.cos(e), math.sin(e))) * radius * 4
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(OUT, f"{name}.png")
        bpy.ops.render.render(write_still=True)
        shots.append(sc.render.filepath)
    cd.type = "PERSP"
    cd.lens = 40
    cam.location = center + Vector((-0.9, -1.3, 0.45)).normalized() * radius * 3.2
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.render.filepath = os.path.join(OUT, "hero_shot.png")
    bpy.ops.render.render(write_still=True)
    print(f"[render_asset] OK {len(shots) + 1} images -> {OUT}  size={tuple(round(v, 2) for v in size)}")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
