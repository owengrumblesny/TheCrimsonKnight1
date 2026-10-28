"""
Line-up review render: imports several GLBs side by side (rigs shown in a clip pose) and renders one sheet.

    blender -b --factory-startup --python tools/blender/ck_render_lineup.py -- OUT.png SPACING CLIP a.glb b.glb ...

CLIP may be "-" for rest pose.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
OUT, SPACING, CLIP, FILES = os.path.abspath(args[0]), float(args[1]), args[2], args[3:]


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
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.13, 0.135, 0.15, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.world = w
    return sc


def main():
    sc = setup()
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for i, f in enumerate(FILES):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.abspath(f))
        objs = [o for o in bpy.data.objects if o not in before]
        x = (i - (len(FILES) - 1) / 2) * SPACING
        for o in objs:
            if o.name.endswith("_COL"):
                o.hide_render = True
            if o.parent is None:
                o.location.x += x
            if o.type == "ARMATURE" and CLIP != "-":
                act = bpy.data.actions.get(CLIP) or next((a for a in bpy.data.actions if a.name.startswith(CLIP)), None)
                if act:
                    o.animation_data_create().action = act
        bpy.context.view_layer.update()
        for o in objs:
            if o.type == "MESH" and not o.hide_render:
                for c in o.bound_box:
                    p = o.matrix_world @ Vector(c)
                    lo = Vector(map(min, lo, p))
                    hi = Vector(map(max, hi, p))
    sc.frame_set(10)
    center, size = (lo + hi) / 2, hi - lo
    for name, loc, energy in (("key", (-0.4, -1.0, 0.7), 2500), ("fill", (0.6, -0.8, 0.3), 900), ("rim", (0.2, 1.0, 0.8), 1500)):
        d = bpy.data.lights.new(name, "AREA")
        d.energy = energy * (size.x / 6) ** 2
        d.size = size.x
        o = bpy.data.objects.new(name, d)
        o.location = center + Vector(loc) * size.x
        o.rotation_euler = (center - o.location).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(o)
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cd.type = "ORTHO"
    cd.ortho_scale = max(size.x, size.z * 2.2) * 1.06
    sc.render.resolution_x, sc.render.resolution_y = 2200, 1000
    t = math.radians(-20)
    cam.location = center + Vector((math.sin(t), -math.cos(t), 0.12)) * 40
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    cd.clip_end = 200
    sc.render.filepath = OUT
    bpy.ops.render.render(write_still=True)
    print("[LINEUP]", OUT)


main()
