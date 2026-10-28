extends SceneTree
## Headless import check: godot --headless --path . --script res://godot/tools/verify_import.gd
## Loads every manifest model and checks the post-import rules (colliders, loops, attach, materials).
## Prints a summary and exits 1 on any failure.


func _init() -> void:
	var fails := []
	var stats := {"models": 0, "colliders": 0, "png_surfaces": 0, "vc_surfaces": 0, "plain_surfaces": 0, "clips": 0}
	var png_by_cat := {}
	for a in CKData.json("asset_manifest")["assets"]:
		var path := CKData.model_path(a["id"])
		var ps = load(path)
		if ps == null:
			fails.append("load failed: " + path)
			continue
		var root: Node = ps.instantiate()
		stats["models"] += 1
		for n in root.find_children("*", "", true, false):
			if String(n.name).to_upper().ends_with("_COL"):
				if n is StaticBody3D and n.get_child_count() > 0:
					stats["colliders"] += 1
				else:
					fails.append("%s: %s not converted (%s)" % [a["id"], n.name, n.get_class()])
			if n is MeshInstance3D and n.mesh:
				for s in n.mesh.get_surface_count():
					var m = n.mesh.surface_get_material(s)
					if m and String(m.resource_path).begins_with("res://godot/materials/"):
						stats["png_surfaces"] += 1
						png_by_cat[a["category"]] = png_by_cat.get(a["category"], 0) + 1
					elif m is BaseMaterial3D and m.vertex_color_use_as_albedo:
						stats["vc_surfaces"] += 1
					else:
						stats["plain_surfaces"] += 1
			if n is AnimationPlayer:
				for c in n.get_animation_list():
					stats["clips"] += 1
					var nm := String(c).get_file()
					var loop: bool = n.get_animation(c).loop_mode != Animation.LOOP_NONE
					var want = null
					if nm.begins_with("CK_"):
						want = CKData.hero_clip(nm).get("loop")
					elif nm.begins_with("NPC_") or nm == "Gear_Idle":
						want = true
					elif nm.begins_with("Gear_"):
						want = false
					if want != null and want != loop:
						fails.append("%s: clip %s loop=%s want %s" % [a["id"], nm, loop, want])
		if String(a["id"]).begins_with("gear_") and not root.has_meta("attach"):
			fails.append(a["id"] + ": no attach meta")
		root.free()
	print("verify_import: ", stats)
	print("png surfaces by category: ", png_by_cat)
	var hero: Node = load(CKData.model_path("crimson_knight_CRX9_rigged")).instantiate()
	var sk: Skeleton3D = hero.find_children("*", "Skeleton3D", true, false)[0]
	print("hero bones: ", sk.get_bone_count(), " sockets: ", ["Socket_Hand_R", "Socket_Hand_L", "Socket_Belt_R", "Socket_Belt_L",
		"Socket_Back", "Socket_Head"].map(func(b): return sk.find_bone(b) >= 0))
	print("hero LOD meshes: ", hero.find_children("*_LOD?", "MeshInstance3D", true, false).map(func(n): return String(n.name)))
	hero.free()
	for f in fails.slice(0, 40):
		printerr("FAIL ", f)
	print("verify_import: %d failures" % fails.size())
	quit(1 if fails.size() else 0)
