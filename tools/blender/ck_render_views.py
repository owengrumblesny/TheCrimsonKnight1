"""Crimson Knight: Earth-RED — true multi-view + animation-frame renders of an exported GLB.

Imports the *exported* GLB into an empty scene (so the renders also verify the file),
then renders:
  * six orthographic reference views of the bind pose from fixed cameras around the same mesh
    (front, front_left_45, left, rear, right, front_right_45) — extends tools/blender_camera_reference_template.py
  * N frames of every animation clip from a three-quarter camera, over a ground plane
    so foot contact can be judged
and writes a JSON manifest of every rendered frame.

Run from the project root:
  blender -b --factory-startup --python tools/blender/ck_render_views.py -- [glb] [out_dir] [clip_filter]
Defaults: the rigged CR-X9 GLB, references/renders/crx9/, all clips.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
GLB = os.path.abspath(args[0]) if len(args) > 0 else os.path.join(ROOT, "assets", "models", "characters", "crimson_knight_CRX9_rigged.glb")
OUT = os.path.abspath(args[1]) if len(args) > 1 else os.path.join(ROOT, "references", "renders", "crx9")
CLIP_FILTER = args[2] if len(args) > 2 else ""
FRAMES_PER_CLIP = 4


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30  # import clips at their authored rate
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    if scene.render.engine == "CYCLES":
        scene.cycles.samples = 32
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    world = bpy.data.worlds.new("CK_World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.16, 0.165, 0.18, 1)
    bg.inputs[1].default_value = 0.6
    scene.world = world

    def light(name, kind, loc, energy, color=(1, 1, 1), size=1.0):
        d = bpy.data.lights.new(name, kind)
        d.energy = energy
        d.color = color
        if kind == "AREA":
            d.size = size
        o = bpy.data.objects.new(name, d)
        o.location = loc
        direction = Vector((0, 0, 1.0)) - Vector(loc)
        o.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(o)

    light("Key", "AREA", (-2.5, -3.0, 3.2), 520, (1.0, 0.96, 0.92), 2.0)
    light("Fill", "AREA", (3.0, -2.0, 1.8), 160, (0.85, 0.9, 1.0), 3.0)
    light("Rim", "AREA", (0.5, 3.5, 3.0), 450, (1.0, 0.75, 0.75), 2.0)
    return scene


def import_glb():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=GLB)
    objs = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in objs if o.type == "ARMATURE")
    return rig, objs


def camera(scene, ortho):
    cd = bpy.data.cameras.new("CK_Cam")
    cam = bpy.data.objects.new("CK_Cam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = 2.45
    else:
        cd.lens = 50
    return cam


def aim(cam, angle_deg, dist, height, target):
    t = math.radians(angle_deg)
    cam.location = (math.sin(t) * dist, -math.cos(t) * dist, height)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()


def set_action(rig, clip):
    act = next((a for a in bpy.data.actions if a.name == clip), None) or \
        next((a for a in bpy.data.actions if a.name.startswith(clip)), None)
    if act is None:
        return None
    ad = rig.animation_data or rig.animation_data_create()
    for tr in ad.nla_tracks:
        tr.mute = True
    ad.action = act
    if hasattr(ad, "action_slot") and getattr(act, "slots", None) and ad.action_slot is None:
        ad.action_slot = act.slots[0]
    return act


def clear_action(rig):
    ad = rig.animation_data
    if ad:
        ad.action = None
        for tr in ad.nla_tracks:
            tr.mute = True
    for pb in rig.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)


def main():
    os.makedirs(OUT, exist_ok=True)
    scene = setup_scene()
    rig, objs = import_glb()
    report = {"glb": os.path.relpath(GLB, ROOT).replace("\\", "/"), "views": [], "clips": {}}

    # ---- six true orthographic views of the bind pose ----
    clear_action(rig)
    scene.frame_set(0)
    scene.render.resolution_x, scene.render.resolution_y = 768, 896
    cam = camera(scene, ortho=True)
    for name, ang in [("front", 0), ("front_left_45", -45), ("left", -90), ("rear", 180), ("right", 90), ("front_right_45", 45)]:
        # character faces -Y in Blender; its left side is +X, so a camera at -90 deg sees its left profile
        aim(cam, ang, 6.0, 1.04, (0, 0, 1.04))
        path = os.path.join(OUT, f"view_{name}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        report["views"].append(os.path.relpath(path, ROOT).replace("\\", "/"))

    # ---- animation frames over a ground plane ----
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("Ground")
    gm.diffuse_color = (0.25, 0.25, 0.27, 1)
    try:
        gm.use_nodes = True
    except Exception:
        pass
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.22, 0.22, 0.24, 1)
    ground.data.materials.append(gm)
    pcam = camera(scene, ortho=False)
    aim(pcam, -55, 5.2, 1.5, (0, 0, 0.85))
    scene.render.resolution_x, scene.render.resolution_y = 360, 420
    clip_names = sorted({a.name for a in bpy.data.actions})
    for clip in clip_names:
        if CLIP_FILTER and CLIP_FILTER not in clip:
            continue
        act = set_action(rig, clip)
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        frames = [round(f0 + (f1 - f0) * i / FRAMES_PER_CLIP) for i in range(FRAMES_PER_CLIP)]
        report["clips"][clip] = []
        for f in frames:
            scene.frame_set(f)
            path = os.path.join(OUT, "clips", f"{clip}_{f:03d}.png")
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            report["clips"][clip].append(os.path.relpath(path, ROOT).replace("\\", "/"))
        print(f"[render] {clip}: frames {frames}")

    with open(os.path.join(OUT, "render_manifest.json"), "w") as fh:
        json.dump(report, fh, indent=2)
    print(f"[render] OK views={len(report['views'])} clips={len(report['clips'])} -> {OUT}")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
