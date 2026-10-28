class_name District
extends Node3D
## New Gotham test block (port of world/district.ts): two crossing avenues, kit buildings facade-to-facade
## 11 m from the road centre (LOD1 beyond 64 m), a skyline ring, street lights whose real light pool follows
## the nearest working lamp heads, and street props. Repeated assets are drawn as MultiMeshInstance3D in
## ~40 m chunks so frustum culling works; static colliders come from each asset's *_COL boxes.

## every street-lamp head: {pos, off_until}
var lamps: Array = []
## loose physics props: RigidBody3D list
var dynamic: Array = []
## building footprints + road strips for the map screen: {kind, min: Vector2, max: Vector2}
var map_features: Array = []
var _light_pool: Array = []
var _pool_timer := 0.0
var _rand_state := 0
var _proto_cache := {}
## Shared wet-street material: the ground and every surface that used png_wet_asphalt (road tiles).
var wet: ShaderMaterial


func _rand() -> float:
	_rand_state = (_rand_state * 1664525 + 1013904223) & 0xFFFFFFFF
	return float(_rand_state) / 4294967296.0


func build() -> void:
	name = "Sector_Downtown"
	wet = _wet_material()
	_rand_state = int(CKData.json("world")["seed"])
	_ground()

	var road_tiles := []
	var walks := []
	for i in range(-10, 11):
		road_tiles.append_array([_p(i * 6, 0), _p(0, i * 6)])
		if i != 0:
			for o in [-6, 6]:
				walks.append_array([_p(i * 6, o), _p(o, i * 6)])
	instanced("road_tile_v01", road_tiles, {"collide": false, "shadow": false})
	instanced("sidewalk_tile_v01", walks, {"collide": true, "shadow": false})

	# ---- building rows (footprints from config/citykit.json) ----
	var foot := {"kit_gothic_tower": [16, 16], "kit_office_tower": [17, 17], "kit_apartment": [14, 13],
		"kit_warehouse": [24, 20], "kit_shopfront": [10, 12]}
	var kinds := ["kit_apartment", "kit_shopfront", "kit_office_tower", "kit_apartment", "kit_warehouse", "kit_shopfront", "kit_gothic_tower"]
	var lots := {}
	for axis in ["x", "z"]:
		for side in [-1, 1]:
			for dir in [-1, 1]:
				var cursor := 12.0
				while cursor < 116:
					var kind: String = kinds[int(_rand() * kinds.size())]
					var w: float = foot[kind][0]
					var d: float = foot[kind][1]
					if cursor + w > 120:
						break
					var along: float = dir * (cursor + w / 2)
					var off: float = side * (11 + d / 2)
					# near the intersection: full detail; further out: the merged LOD1 version
					var id := kind if absf(along) < 64 else kind + "_lod1"
					if axis == "x":
						_add(lots, id, _p(along, off, PI if side > 0 else 0.0))
					else:
						_add(lots, id, _p(off, along, -PI / 2 if side > 0 else PI / 2))
					cursor += w + 1.5
	# far LOD1 lots sit outside every preset's shadow range (<= 45 m), so they don't cast
	for id in lots:
		instanced(id, lots[id], {"collide": true, "map_kind": "building", "chunk": 40, "shadow": not id.ends_with("_lod1")})
	# simplified distant skyline (LOD1 only, no collision)
	var sky := {}
	for i in 48:
		var a := (i / 48.0) * TAU + _rand() * 0.05
		var r := 150 + _rand() * 70
		var kind: String = ["kit_office_tower", "kit_gothic_tower", "kit_apartment"][i % 3]
		_add(sky, kind, _p(cos(a) * r, sin(a) * r, -a - PI / 2, 0.0, 1 + _rand() * 0.9))
	for kind in sky:
		instanced(kind + "_lod1", sky[kind], {"collide": false, "shadow": false, "chunk": 150})
	map_features.append({"kind": "road", "min": Vector2(-63, -3), "max": Vector2(63, 3)})
	map_features.append({"kind": "road", "min": Vector2(-3, -63), "max": Vector2(3, 63)})

	# ---- street lights (arm over the road) ----
	var lamp_list := []
	for i in range(-9, 10, 2):
		if absi(i) < 2:
			continue
		lamp_list.append_array([_p(i * 6, -3.7, -PI / 2), _p(i * 6 + 6, 3.7, PI / 2), _p(3.7, i * 6, PI), _p(-3.7, i * 6 + 6, 0)])
	instanced("kit_streetlight", lamp_list, {"collide": true})
	for l in lamp_list:
		var head := Vector3(1.75, 6.55, 0).rotated(Vector3.UP, l["rot"])
		lamps.append({"pos": Vector3(l["x"], 0, l["z"]) + head, "off_until": 0.0})

	# ---- intersection furniture ----
	instanced("kit_traffic_light", [_p(4.4, 4.4, PI), _p(-4.4, -4.4, 0), _p(-4.4, 4.4, PI / 2), _p(4.4, -4.4, -PI / 2)], {"collide": true})
	instanced("kit_crosswalk", [_p(7.5, 0), _p(-7.5, 0), _p(0, 7.5, PI / 2), _p(0, -7.5, PI / 2)], {"collide": false, "shadow": false})
	instanced("kit_street_sign", [_p(5.5, -5.5, 0.3), _p(-5.5, 5.5, PI + 0.3)], {"collide": true})
	var covers := []
	var drains := []
	var trees := []
	for i in range(-8, 9):
		if absi(i) < 2:
			continue
		var odd := i % 2 != 0
		covers.append_array([_p(i * 7.3, 0.9 if odd else -0.9), _p(-0.9 if odd else 0.9, i * 7.3)])
		drains.append_array([_p(i * 6.5 + 2, 2.75), _p(2.75, i * 6.5 + 2, PI / 2)])
		trees.append_array([_p(i * 7 + 3, 8.2, i), _p(i * 7 + 3, -8.2, i * 2), _p(8.2, i * 7 + 3, i * 3), _p(-8.2, i * 7 + 3, i)])
	instanced("kit_manhole", covers, {"collide": false, "shadow": false})
	instanced("kit_drain", drains, {"collide": false, "shadow": false})
	instanced("kit_street_tree", trees, {"collide": true})

	# ---- sidewalk props ----
	var props := _scatter(["kit_trash_can", "kit_hydrant", "kit_bench", "kit_mailbox", "kit_recycling_bin", "kit_vending_machine",
		"kit_utility_cabinet", "kit_garbage_bag", "kit_bus_shelter", "kit_dumpster", "kit_bush"], 80, 60)
	for id in props:
		instanced(id, props[id], {"collide": id != "kit_garbage_bag" and id != "kit_bush"})
	instanced("kit_dumpster", [_p(-40, 9.4, PI), _p(-37.5, 9.4, PI)], {"collide": true})
	instanced("kit_shipping_container", [_p(92, -7), _p(92, -7, 0, 2.6), _p(99, 7, 0.2)], {"collide": true})
	instanced("kit_generator", [_p(84, 6.5)], {"collide": true})
	instanced("kit_fence", [_p(88, 10.2), _p(94, 10.2)], {"collide": true})
	instanced("kit_jersey_barrier", [_p(-30, -1.6), _p(-26.8, -1.6), _p(30, 1.6)], {"collide": true})
	var cars := []
	for i in 10:
		var along := (_rand() - 0.5) * 100
		if absf(along) < 12:
			continue
		var lane := -1.6 if _rand() < 0.5 else 1.6
		cars.append(_p(along, lane) if i % 2 else _p(lane, along, PI / 2))
	instanced("car_prop_v01", cars, {"collide": true})

	# ---- physics playthings ----
	var loose := _scatter(["kit_cardboard_box", "barrel_v01", "kit_traffic_cone", "kit_pallet", "kit_toolbox"], 30, 34)
	for id in loose:
		for p in loose[id]:
			_dynamic_prop(id, p)

	_billboards()
	_citadel_portal()


func _ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(400, 400)
	mesh.material = wet
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# a finite slab, not a WorldBoundaryShape3D: that is a half-space and would push the Citadel (y -120) up
	var body := StaticBody3D.new()
	body.name = "Ground_static"
	add_child(body)
	_box(body, Vector3(400, 2, 400), Transform3D(Basis(), Vector3(0, -1, 0)))


func _wet_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://godot/shaders/wet_asphalt.gdshader")
	m.set_shader_parameter("albedo_tex", load(CKData.texture_path("wet_asphalt")))
	var puddles := FastNoiseLite.new()
	puddles.seed = 7
	puddles.frequency = 0.02
	puddles.fractal_octaves = 3
	var pt := NoiseTexture2D.new()
	pt.noise = puddles
	pt.seamless = true
	pt.width = 512
	pt.height = 512
	pt.generate_mipmaps = true
	m.set_shader_parameter("puddle_noise", pt)
	var ripple := FastNoiseLite.new()
	ripple.seed = 11
	ripple.frequency = 0.08
	var rt := NoiseTexture2D.new()
	rt.noise = ripple
	rt.seamless = true
	rt.as_normal_map = true
	rt.bump_strength = 4.0
	rt.width = 256
	rt.height = 256
	rt.generate_mipmaps = true
	m.set_shader_parameter("ripple_normal", rt)
	return m


func _p(x: float, z: float, rot := 0.0, y := 0.0, scale := 1.0) -> Dictionary:
	return {"x": x, "z": z, "rot": rot, "y": y, "scale": scale}


func _add(map: Dictionary, id: String, p: Dictionary) -> void:
	if not map.has(id):
		map[id] = []
	map[id].append(p)


func _xf(p: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, p["rot"]).scaled(Vector3.ONE * p["scale"]), Vector3(p["x"], p["y"], p["z"]))


func _scatter(ids: Array, n: int, r: float) -> Dictionary:
	var out := {}
	for i in n:
		var along := (_rand() - 0.5) * 2 * r
		var side := -1.0 if _rand() < 0.5 else 1.0
		var off := side * (4.9 + _rand() * 2.0)
		var p := _p(along, off) if _rand() < 0.5 else _p(off, along)
		if Vector2(p["x"], p["z"]).length() < 9:
			continue
		p["rot"] = _rand() * TAU
		_add(out, ids[i % ids.size()], p)
	return out


## Imported asset scene, analysed once: visible meshes (root-relative), collider boxes, local bounds.
func proto(id: String) -> Dictionary:
	if _proto_cache.has(id):
		return _proto_cache[id]
	var scene: Node3D = load(CKData.model_path(id)).instantiate()
	add_child(scene) # in-tree for global transforms; removed below
	var meshes := []
	var cols := []
	var bounds := AABB()
	var first := true
	var inv := scene.global_transform.affine_inverse()
	for n in scene.find_children("*", "", true, false):
		if n is MeshInstance3D and n.is_visible_in_tree() and n.mesh:
			var xf: Transform3D = inv * n.global_transform
			meshes.append({"mesh": _wet_surfaces(n.mesh), "xf": xf, "skin": n.skin != null})
			var b: AABB = xf * n.mesh.get_aabb()
			bounds = b if first else bounds.merge(b)
			first = false
		elif n is CollisionShape3D and n.shape is BoxShape3D:
			cols.append({"size": n.shape.size, "xf": inv * n.global_transform})
	remove_child(scene)
	scene.queue_free()
	var info := {"meshes": meshes, "cols": cols, "bounds": bounds}
	_proto_cache[id] = info
	return info


## Copy of a mesh with its png_wet_asphalt surfaces switched to the wet-street shader (others untouched).
func _wet_surfaces(mesh: Mesh) -> Mesh:
	var hit := false
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m and m.resource_path.ends_with("png_wet_asphalt.tres"):
			hit = true
	if not hit or wet == null:
		return mesh
	var copy: Mesh = mesh.duplicate()
	for i in copy.get_surface_count():
		var m := copy.surface_get_material(i)
		if m and m.resource_path.ends_with("png_wet_asphalt.tres"):
			copy.surface_set_material(i, wet)
	return copy


## Chunked MultiMeshInstance3D per sub-mesh; static colliders from *_COL boxes (else bounds).
## opts: collide, shadow (default true), map_kind, chunk (m)
func instanced(id: String, list: Array, opts: Dictionary) -> void:
	if list.is_empty() or CKData.model_path(id) == "":
		push_warning("district: missing asset " + id)
		return
	var info := proto(id)
	var chunk: float = opts.get("chunk", 0.0)
	var chunks := {}
	for p in list:
		var key := Vector2i(floori(p["x"] / chunk), floori(p["z"] / chunk)) if chunk > 0 else Vector2i.ZERO
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(p)
	var shadow: bool = opts.get("shadow", true)
	for key in chunks:
		var group: Array = chunks[key]
		for m in info["meshes"]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = m["mesh"]
			mm.instance_count = group.size()
			for i in group.size():
				mm.set_instance_transform(i, _xf(group[i]) * m["xf"])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d" % [id, key.x, key.y]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
	var body: StaticBody3D = null
	if opts.get("collide", false):
		body = StaticBody3D.new()
		body.name = id + "_static"
		add_child(body)
	var bounds: AABB = info["bounds"]
	for p in list:
		var xf := _xf(p)
		if body:
			if info["cols"].is_empty():
				_box(body, bounds.size * p["scale"], xf * Transform3D(Basis(), bounds.get_center()))
			else:
				for c in info["cols"]:
					_box(body, c["size"], xf * c["xf"])
		if opts.has("map_kind"):
			var b: AABB = xf * bounds
			map_features.append({"kind": opts["map_kind"], "min": Vector2(b.position.x, b.position.z), "max": Vector2(b.end.x, b.end.z)})


func _box(body: StaticBody3D, size: Vector3, xf: Transform3D) -> void:
	var s := xf.basis.get_scale()
	var shape := BoxShape3D.new()
	shape.size = (size * s).abs()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	body.add_child(cs)


func _dynamic_prop(id: String, p: Dictionary) -> void:
	var info := proto(id)
	var bounds: AABB = info["bounds"]
	var rb := RigidBody3D.new()
	rb.name = id
	rb.mass = 3.0 if id.contains("traffic_cone") else 25.0
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	rb.add_child(cs)
	# re-centre the visual on the body origin; the body starts axis-aligned with its visual
	for m in info["meshes"]:
		var mi := MeshInstance3D.new()
		mi.mesh = m["mesh"]
		mi.transform = Transform3D(Basis(), -bounds.get_center()) * m["xf"]
		rb.add_child(mi)
	rb.position = Vector3(p["x"], p["y"], p["z"]) + bounds.get_center()
	rb.sleeping = true
	add_child(rb)
	dynamic.append(rb)


## Owen Enterprises billboards showing images cut from the concept boards.
func _billboards() -> void:
	var art := ["vehicles/x1_crx1_showcase", "vehicles/b1_crb1_showcase", "vehicles/a1_cra1_showcase", "world/c_downtown_wide",
		"vehicles/x1_crx1_pursuit", "world/c_citadel_main_hangar_wide", "vehicles/a1_cra1_flight", "world/c_rooftops_wide"]
	var spots := [[-21, -10.4, 0], [21, 10.4, PI], [10.4, -27, -PI / 2], [-10.4, 27, PI / 2],
		[-45, 10.4, PI], [45, -10.4, 0], [-10.4, -45, PI / 2], [10.4, 45, -PI / 2]]
	var frame_mat: Material = load("res://godot/materials/png_gunmetal.tres")
	var trim_mat: Material = load("res://godot/materials/png_red_emissive.tres")
	for i in spots.size():
		var tex: Texture2D = load(CKData.board_image_path(art[i % art.size()]))
		if tex == null:
			continue
		var w := 9.0
		var h := minf(6.5, w * tex.get_height() / tex.get_width())
		var board := Node3D.new()
		board.position = Vector3(spots[i][0], 0, spots[i][1])
		board.rotation.y = spots[i][2]
		add_child(board)
		var face_mat := StandardMaterial3D.new()
		face_mat.albedo_texture = tex
		face_mat.emission_enabled = true
		face_mat.emission_texture = tex
		face_mat.emission_energy_multiplier = 0.75
		face_mat.roughness = 0.6
		var face := QuadMesh.new()
		face.size = Vector2(w, h)
		face.material = face_mat
		_part(board, face, Vector3(0, 7 + h / 2, 0.16), false)
		_part(board, _boxmesh(Vector3(w + 0.5, h + 0.5, 0.25), frame_mat), Vector3(0, 7 + h / 2, 0), true)
		_part(board, _boxmesh(Vector3(w + 0.6, 0.12, 0.3), trim_mat), Vector3(0, 6.8, 0.02), false)
		_part(board, _boxmesh(Vector3(0.4, 7, 0.4), frame_mat), Vector3(0, 3.5, -0.2), true)
		var body := StaticBody3D.new()
		board.add_child(body)
		_box(body, Vector3(0.4, 7, 0.4), Transform3D(Basis(), Vector3(0, 3.5, -0.2)))


func _boxmesh(size: Vector3, mat: Material) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	return b


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, shadow: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Red Citadel entrance at config/world.json redCitadelPortal.
func _citadel_portal() -> void:
	var at: Array = CKData.json("world")["redCitadelPortal"]
	var x: float = at[0]
	var z: float = at[2]
	var pad := _p(x, z, 0, 0, 2)
	instanced("landing_pad_v01", [pad], {"collide": true, "map_kind": "portal"})
	var ring := TorusMesh.new()
	ring.inner_radius = 3.88
	ring.outer_radius = 4.12
	ring.rings = 64
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("#330000")
	rm.emission_enabled = true
	rm.emission = Color("#ff2020")
	rm.emission_energy_multiplier = 3
	ring.material = rm
	var rmi := MeshInstance3D.new()
	rmi.mesh = ring
	rmi.position = Vector3(x, 4.5, z)
	rmi.rotation.x = PI / 2
	add_child(rmi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1, 0.125, 0.125)
	glow.light_energy = 4
	glow.omni_range = 30
	glow.position = Vector3(x, 4, z)
	add_child(glow)
	for pair in [["world/c_citadel_entrance_wide", -1], ["world/c_citadel_command_center_wide", 1]]:
		var tex: Texture2D = load(CKData.board_image_path(pair[0]))
		if tex == null:
			continue
		var w := 6.0
		var h := w * tex.get_height() / tex.get_width()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 0.85)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var q := QuadMesh.new()
		q.size = Vector2(w, h)
		q.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.position = Vector3(x + pair[1] * 7.5, 3 + h / 2, z + 1)
		mi.rotation.y = -pair[1] * 0.35
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Resize the street-light pool (graphics preset).
func set_light_pool(n: int, shadows := false) -> void:
	for l in _light_pool:
		l.queue_free()
	_light_pool.clear()
	for i in n:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.69, 0.44)
		l.light_energy = 3.0
		l.omni_range = 22
		l.omni_attenuation = 1.6
		l.shadow_enabled = shadows and i < 2
		add_child(l)
		_light_pool.append(l)
	_pool_timer = 0.0


## Move pooled lights to the nearest working lamps (throttled).
func update_lights(center: Vector3, now: float, dt: float) -> void:
	_pool_timer -= dt
	if _pool_timer > 0:
		return
	_pool_timer = 0.25
	var live := lamps.filter(func(l): return l["off_until"] <= now)
	live.sort_custom(func(a, b): return a["pos"].distance_squared_to(center) < b["pos"].distance_squared_to(center))
	for i in _light_pool.size():
		var light: OmniLight3D = _light_pool[i]
		light.visible = i < live.size()
		if i < live.size():
			light.position = live[i]["pos"]
