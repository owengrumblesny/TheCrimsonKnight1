@tool
extends EditorScenePostImport
## Project-wide GLB post-import (set in project.godot [importer_defaults]).
##  - Z-up placeholders (manifest up_axis "Z") are turned Y-up, like registry.instance() in the web build.
##  - *_COL meshes become hidden StaticBody3D + BoxShape3D collision proxies.
##  - Clip loop modes: CK_* from config/crx9_clips.json, NPC_* loop, Gear_Idle loops, other Gear_* play once.
##  - Gear roots keep their glTF "attach" extra as root metadata (fallback: config/gadget_assets.json).
##  - Placeholder vertex colours are re-skinned in Owen's material PNGs (render/materials.ts rules);
##    unmatched or rigged (NPC) vertex colours are shown via vertex_color_use_as_albedo.

const MAT_DIR := "res://godot/materials/png_%s.tres"
## Placeholder palette (raw COLOR_0 * 255) -> material PNG; "" = decided by asset (see _rule_tex).
const RULES := [
	[Color8(30, 33, 40), ""],
	[Color8(35, 80, 95), "glass"],
	[Color8(230, 40, 60), "red_emissive"],
	[Color8(255, 40, 60), "red_emissive"],
	[Color8(72, 77, 87), "gunmetal"],
	[Color8(52, 56, 65), "gunmetal"],
	[Color8(158, 18, 32), "crimson_metal"],
	[Color8(145, 13, 31), "crimson_metal"],
	[Color8(77, 5, 17), "crimson_metal"],
	[Color8(100, 99, 101), "concrete"],
	[Color8(17, 18, 25), "black_rubber"],
]

var _vc_cache := {}


func _post_import(scene: Node) -> Object:
	var rel := get_source_file().trim_prefix("res://")
	var id := rel.get_file().get_basename()
	var entry := CKData.asset_by_file(rel)
	var category: String = entry.get("category", rel.get_base_dir().get_file())
	scene.set_meta("asset_id", entry.get("id", id))
	if entry.get("up_axis", "Y") == "Z":
		for c in scene.get_children():
			if c is Node3D:
				c.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3.ZERO) * c.transform
	_colliders(scene)
	_loops(scene)
	_attach(scene, id)
	_materials(scene, id, category, bool(entry.get("rigged", false)) or id.begins_with("npc_"))
	return scene


func _all(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out


func _colliders(scene: Node) -> void:
	for n in _all(scene):
		if not (n is MeshInstance3D and String(n.name).to_upper().ends_with("_COL")):
			continue
		var mi := n as MeshInstance3D
		var aabb := mi.mesh.get_aabb() if mi.mesh else AABB()
		var s := mi.transform.basis.get_scale()
		var body := StaticBody3D.new()
		var col_name := mi.name
		mi.name = "_replaced"
		body.name = col_name
		body.transform = Transform3D(mi.transform.basis.orthonormalized(), mi.transform.origin)
		var shape := CollisionShape3D.new()
		shape.name = "Box"
		var box := BoxShape3D.new()
		box.size = (aabb.size * s).abs().max(Vector3.ONE * 0.02)
		shape.shape = box
		shape.position = aabb.get_center() * s
		body.add_child(shape)
		var parent := mi.get_parent()
		parent.add_child(body)
		parent.move_child(body, mi.get_index())
		for c in mi.get_children():
			c.reparent(body)
		parent.remove_child(mi)
		mi.free()
		body.owner = scene
		shape.owner = scene


func _loops(scene: Node) -> void:
	for n in _all(scene):
		if not n is AnimationPlayer:
			continue
		var ap := n as AnimationPlayer
		for clip in ap.get_animation_list():
			var a := ap.get_animation(clip)
			var name := String(clip).get_file()
			var loop := a.loop_mode != Animation.LOOP_NONE
			if name.begins_with("CK_"):
				loop = bool(CKData.hero_clip(name).get("loop", true))
			elif name.begins_with("NPC_") or name == "Gear_Idle":
				loop = true
			elif name.begins_with("Gear_"):
				loop = false
			a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE


func _attach(scene: Node, id: String) -> void:
	for n in _all(scene):
		if n.has_meta("extras"):
			var ex = n.get_meta("extras")
			if ex is Dictionary and ex.has("attach"):
				scene.set_meta("attach", ex["attach"])
				return
	var gear = CKData.json("gadget_assets")
	for g in gear["gear"] if gear else []:
		if g["id"] == id:
			scene.set_meta("attach", g["attach"])
			return


func _rule_tex(rule_tex: String, id: String, category: String) -> String:
	if rule_tex != "":
		return rule_tex
	if id.begins_with("road_tile"):
		return "wet_asphalt"
	return "concrete" if category == "architecture" else "gunmetal"


func _materials(scene: Node, id: String, category: String, keep_vertex_colour: bool) -> void:
	for n in _all(scene):
		if not (n is MeshInstance3D and n.mesh is ArrayMesh):
			continue
		var mesh := n.mesh as ArrayMesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var cols = arrays[Mesh.ARRAY_COLOR]
			if cols == null or cols.is_empty():
				continue
			var tex := ""
			if not keep_vertex_colour:
				var sum := Vector3.ZERO
				for c in cols:
					sum += Vector3(c.r, c.g, c.b)
				var mean: Vector3 = sum / cols.size()
				var best := ""
				var best_d := INF
				for r in RULES:
					var rc: Color = r[0]
					var d := (mean - Vector3(rc.r, rc.g, rc.b)).length() * 255.0
					if d < best_d:
						best_d = d
						best = _rule_tex(r[1], id, category)
				if best_d < 22.0:
					tex = best
			if tex != "":
				mesh.surface_set_material(s, load(MAT_DIR % tex))
			else:
				mesh.surface_set_material(s, _vertex_colour(mesh.surface_get_material(s)))


func _vertex_colour(src: Material) -> Material:
	if _vc_cache.has(src):
		return _vc_cache[src]
	var m: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = false
	_vc_cache[src] = m
	return m
