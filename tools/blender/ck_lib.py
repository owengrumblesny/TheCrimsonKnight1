"""Crimson Knight: Earth-RED — shared Blender hard-surface library for non-character assets.

Materials: Owen's assets/materials PNGs as base colour + generated roughness/metal and detail-normal
maps (from assets/source/textures, created by ck_build_crx9_v2.py). Geometry: lofted bodies, bevelled
boxes/cylinders, extruded outlines, wedges. Rigging for machines: named EMPTY pivots with child meshes,
NLA-track clips (one glTF animation per track name), collision proxies (*_COL), static LOD export.
"""
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PNG = os.path.join(ROOT, "assets", "materials")
DETAIL = os.path.join(ROOT, "assets", "source", "textures")


def reset(fps=30):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = fps
    _MATS.clear()  # materials die with the old file


# --------------------------------------------------------------------------------------
# materials
# --------------------------------------------------------------------------------------
_MATS = {}


def _img(path, non_color=False):
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def material(name):
    """Shared PBR materials. Base colours are Owen's PNGs; detail maps are the generated CR-X9 set."""
    if name in _MATS:
        return _MATS[name]
    spec = {
        "Crimson": dict(png="crimson_metal.png", mr="crx9_crimson_mr.png", n="crx9_armor_normal.png", coat=0.6),
        "CrimsonDark": dict(png="crimson_metal.png", mr="crx9_crimson_mr.png", n="crx9_armor_normal.png", tint=0.45),
        "Gunmetal": dict(png="gunmetal.png", mr="crx9_gunmetal_mr.png", n="crx9_armor_normal.png"),
        "Black": dict(png="black_rubber.png", mr="crx9_suit_mr.png", n="crx9_armor_normal.png"),
        "Rubber": dict(png="black_rubber.png", rough=0.9),
        "Glass": dict(png="glass.png", rough=0.05, metal=0.3, coat=1.0),
        "Concrete": dict(png="concrete.png", rough=0.85, n="crx9_armor_normal.png"),
        "Asphalt": dict(png="wet_asphalt.png", rough=0.3, n="crx9_armor_normal.png"),
        "Stone": dict(png="cavern_stone.png", rough=0.92, n="crx9_suit_normal.png"),
        "EmissiveRed": dict(png="red_emissive.png", emit=(1, 0.08, 0.1), strength=5),
        "EmissiveWhite": dict(png="glass.png", emit=(1, 0.95, 0.88), strength=12),
        "Screen": dict(png="glass.png", emit=(0.9, 0.12, 0.15), strength=0.8),
        "Hologram": dict(png="glass.png", emit=(1, 0.2, 0.25), strength=1.2),
        "Water": dict(png="glass.png", emit=(0.35, 0.55, 0.75), strength=0.6, rough=0.05),
        "Grate": dict(png="gunmetal.png", mr="crx9_gunmetal_mr.png", n="crx9_suit_normal.png"),
        "Wood": dict(png="concrete.png", tint=(1.5, 1.05, 0.65), rough=0.8),
        "Brick": dict(png="crimson_metal.png", tint=0.32, rough=0.9, n="crx9_suit_normal.png"),
        "Foam": dict(png="black_rubber.png", rough=1.0),
        "Fabric": dict(png="gunmetal.png", tint=0.7, rough=0.95),
        "Skin": dict(png="concrete.png", tint=(2.6, 1.85, 1.45), rough=0.6),
        "Plant": dict(png="cavern_stone.png", tint=(0.45, 1.25, 0.5), rough=0.9),
        "WindowLit": dict(png="glass.png", emit=(1.0, 0.72, 0.42), strength=1.6),
        "WindowRed": dict(png="glass.png", emit=(1.0, 0.18, 0.15), strength=1.4),
        "Paint": dict(png="concrete.png", tint=(2.6, 2.6, 2.5), rough=0.6),
        "Cardboard": dict(png="concrete.png", tint=(1.75, 1.3, 0.85), rough=0.9),
        "Bark": dict(png="cavern_stone.png", tint=(0.9, 0.7, 0.55), rough=0.95),
        "Neon": dict(png="red_emissive.png", emit=(1, 0.1, 0.2), strength=6),
    }[name]
    m = bpy.data.materials.new(name)
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = next(nd for nd in nodes if nd.type == "BSDF_PRINCIPLED")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = _img(os.path.join(PNG, spec["png"]))
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
    if "mr" in spec and os.path.exists(os.path.join(DETAIL, spec["mr"])):
        mr = nodes.new("ShaderNodeTexImage")
        mr.image = _img(os.path.join(DETAIL, spec["mr"]), True)
        sep = nodes.new("ShaderNodeSeparateColor")
        links.new(mr.outputs["Color"], sep.inputs["Color"])
        links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    else:
        bsdf.inputs["Roughness"].default_value = spec.get("rough", 0.5)
        bsdf.inputs["Metallic"].default_value = spec.get("metal", 0.0)
    if "n" in spec and os.path.exists(os.path.join(DETAIL, spec["n"])):
        nt = nodes.new("ShaderNodeTexImage")
        nt.image = _img(os.path.join(DETAIL, spec["n"]), True)
        nm = nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = 0.5
        links.new(nt.outputs["Color"], nm.inputs["Color"])
        links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if spec.get("coat"):
        bsdf.inputs["Coat Weight"].default_value = spec["coat"]
        bsdf.inputs["Coat Roughness"].default_value = 0.12
    if "emit" in spec:
        bsdf.inputs["Emission Color"].default_value = spec["emit"] + (1,)
        bsdf.inputs["Emission Strength"].default_value = spec["strength"]
    _MATS[name] = m
    return m


# --------------------------------------------------------------------------------------
# geometry → objects
# --------------------------------------------------------------------------------------
def bevel_sharp(bm, offset, segs=1, angle=40):
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(angle)]
    if edges and offset > 0:
        bmesh.ops.bevel(bm, geom=edges, offset=offset, offset_type="OFFSET", segments=segs, profile=0.5,
                        affect="EDGES", clamp_overlap=True)


def _finish(me, smooth_angle=35, uv_scale=0.5):
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    if hasattr(me, "set_sharp_from_angle"):
        me.set_sharp_from_angle(angle=math.radians(smooth_angle))
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            a, b = [(p.y, p.z), (p.x, p.z), (p.x, p.y)][ax]
            uv.data[li].uv = (a * uv_scale * 4, b * uv_scale * 4)
    me.update()


def obj_from_bm(name, bm, mat, parent=None, loc=(0, 0, 0), rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material(mat))
    _finish(me)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = rot
    if parent:
        o.parent = parent
    return o


def box(name, dims, loc, mat, parent=None, bevel=0.02, rot=(0, 0, 0), taper_top=(1, 1), segs=1):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        sx, sy = taper_top if v.co.z > 0 else (1, 1)
        v.co = Vector((v.co.x * dims[0] * sx, v.co.y * dims[1] * sy, v.co.z * dims[2]))
    bevel_sharp(bm, min(bevel, min(dims) * 0.45), segs)
    return obj_from_bm(name, bm, mat, parent, loc, rot)


def cyl(name, r1, r2, depth, loc, mat, parent=None, rot=(0, 0, 0), segs=24, bevel=0.01, cap=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth)
    bevel_sharp(bm, bevel, 1, 50)
    return obj_from_bm(name, bm, mat, parent, loc, rot)


def torus(name, major, minor, loc, mat, parent=None, rot=(0, 0, 0), seg=32, ring=10):
    bm = bmesh.new()
    verts = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        row = []
        for j in range(ring):
            b = 2 * math.pi * j / ring
            r = major + minor * math.cos(b)
            row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
        verts.append(row)
    for i in range(seg):
        for j in range(ring):
            bm.faces.new((verts[i][j], verts[(i + 1) % seg][j], verts[(i + 1) % seg][(j + 1) % ring], verts[i][(j + 1) % ring]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(name, bm, mat, parent, loc, rot)


def loft(name, sections, mat, parent=None, loc=(0, 0, 0), mirror=True, bevel=0.0):
    """sections: [(y, [(x,z), ...] right half from bottom-centre (x=0) round to top-centre (x=0))].
    Mirrored to the left. Rings are bridged into quads and both ends capped."""
    bm = bmesh.new()
    rings = []
    for y, half in sections:
        pts = list(half)
        if mirror:
            pts = pts + [(-x, z) for x, z in reversed(half[1:-1])]
        rings.append([bm.verts.new((x, y, z)) for x, z in pts])
    for a, b in zip(rings, rings[1:]):
        n = len(a)
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bevel_sharp(bm, bevel, 1, 30)
    return obj_from_bm(name, bm, mat, parent, loc)


def extrude_outline(name, pts, thickness, mat, parent=None, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.01, axis="Z"):
    """Flat outline [(a,b)] extruded along axis (Z: outline in XY; X: outline in YZ; Y: outline in XZ)."""
    bm = bmesh.new()
    def P(a, b, h):
        return {"Z": (a, b, h), "X": (h, a, b), "Y": (a, h, b)}[axis]
    bot = [bm.verts.new(P(a, b, -thickness / 2)) for a, b in pts]
    top = [bm.verts.new(P(a, b, thickness / 2)) for a, b in pts]
    bm.faces.new(bot[::-1])
    bm.faces.new(top)
    n = len(pts)
    for i in range(n):
        bm.faces.new((bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bevel_sharp(bm, bevel, 1, 40)
    return obj_from_bm(name, bm, mat, parent, loc, rot)


def empty(name, loc=(0, 0, 0), parent=None, rot=(0, 0, 0), size=0.2):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    bpy.context.scene.collection.objects.link(e)
    e.location = loc
    e.rotation_euler = rot
    if parent:
        e.parent = parent
    return e


def text_mesh(name, text, size, loc, mat, parent=None, rot=(0, 0, 0), extrude=0.01, align="CENTER"):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = text
    cu.size = size
    cu.extrude = extrude
    cu.align_x = align
    cu.align_y = "CENTER"
    tmp = bpy.data.objects.new(name + "_tmp", cu)
    bpy.context.scene.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    me.materials.append(material(mat))
    _finish(me)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.location, o.rotation_euler = loc, rot
    if parent:
        o.parent = parent
    return o


def collider(name, dims, loc, parent=None):
    """Simplified collision proxy (box). Exported with the *_COL suffix; the game hides it and uses it for physics."""
    o = box(name + "_COL", dims, loc, "Black", parent, bevel=0)
    o.display_type = "WIRE"
    return o


# --------------------------------------------------------------------------------------
# animation: NLA track per clip, so one glTF animation can drive several pivots
# --------------------------------------------------------------------------------------
def clip(obj, name, keys, path="rotation_euler"):
    """keys: [(frame, value tuple)]. Adds an NLA track called `name` to obj."""
    ad = obj.animation_data or obj.animation_data_create()
    act = bpy.data.actions.new(f"{name}__{obj.name}")
    ad.action = act
    for f, v in keys:
        setattr(obj, path, v)
        obj.keyframe_insert(path, frame=f)
    ad.action = None
    tr = ad.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, int(keys[0][0]), act)
    tr.mute = True
    # restore rest value
    setattr(obj, path, keys[0][1])


def export(path, animations=True, selection=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if selection is not None:
        bpy.ops.object.select_all(action="DESELECT")
        for o in selection:
            o.select_set(True)
    opts = dict(filepath=path, export_format="GLB", use_selection=selection is not None, export_yup=True, export_apply=True,
                export_texcoord=True, export_normals=True, export_materials="EXPORT", export_animations=animations,
                export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_cameras=False, export_lights=False,
                export_extras=True, export_optimize_animation_size=False)
    valid = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    bpy.ops.export_scene.gltf(**{k: v for k, v in opts.items() if k in valid})


def static_lod(objs, ratio, name):
    """Merged, decimated static copy of all visible meshes (for distant LOD). Returns the new object."""
    copies = []
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        if o.type != "MESH" or o.name.endswith("_COL"):
            continue
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        me.transform(o.matrix_world)
        c = bpy.data.objects.new(o.name + "_lodtmp", me)
        bpy.context.scene.collection.objects.link(c)
        copies.append(c)
    bpy.ops.object.select_all(action="DESELECT")
    for c in copies:
        c.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    with bpy.context.temp_override(active_object=copies[0], selected_editable_objects=copies, object=copies[0]):
        bpy.ops.object.join()
    lod = copies[0]
    lod.name = name
    dec = lod.modifiers.new("Decimate", "DECIMATE")
    dec.ratio = ratio
    with bpy.context.temp_override(object=lod, active_object=lod):
        bpy.ops.object.modifier_apply(modifier=dec.name)
    return lod


def tri_count(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o.type == "MESH" and not o.name.endswith("_COL"))


def descendants(root):
    out = [root]
    for c in root.children:
        out += descendants(c)
    return out


def deg(*a):
    return tuple(math.radians(x) for x in a)


def frame_to(z_axis):
    """Euler rotation turning local +Z toward z_axis."""
    return Vector((0, 0, 1)).rotation_difference(Vector(z_axis).normalized()).to_euler()


_ = (Euler, Matrix)
