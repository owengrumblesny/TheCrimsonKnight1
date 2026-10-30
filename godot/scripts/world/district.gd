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
## street grid: avenues at k * SPACING (k = -GRID..GRID) along both axes
const GRID := 3
const SPACING := 140.0
## kit buildings switch to their merged *_lod1 versions beyond this distance (per 40 m chunk)
const LOD_DIST := 110.0
## Citadel Square: open plaza around the portal (and the CR-A1 landing pad)
const SQUARE := Vector2(0, -135)
const SQUARE_RADIUS := 42.0
## street cross-section (metres from an avenue's centre line): 4 lanes of road out to ROAD_HALF, a sidewalk
## centred on WALK, building facades from FACADE. Two lanes each way at LANES (inner, outer).
const ROAD_HALF := 9.0
const WALK := 12.0
const FACADE := 15.0
const LANES := [2.2, 6.6]
## CityExtender keeps generating blocks past the grid edge
const ENDLESS := true
## open lots kept free of kit buildings: [centre, radius] (Citadel Square, the gang alley, the merc yard)
const CLEAR := [[Vector2(0, -135), 42.0], [Vector2(-40, -26), 15.0], [Vector2(95, 31), 24.0]]


static func clear_lot(at: Vector2) -> bool:
	for z in CLEAR:
		if at.distance_to(z[0]) < z[1]:
			return true
	return false
## Shared wet-street material: the ground and every surface that used png_wet_asphalt (road tiles).
var wet: ShaderMaterial
## enterable places (stores, banks, diners...) and parks, built during build()
var places: Places


func _rand() -> float:
	_rand_state = (_rand_state * 1664525 + 1013904223) & 0xFFFFFFFF
	return float(_rand_state) / 4294967296.0


func build() -> void:
	name = "Sector_Downtown"
	wet = _wet_material()
	_rand_state = int(CKData.json("world")["seed"])
	_ground()

	# ---- street grid: avenues at k * SPACING (k = -GRID..GRID) along both axes ----
	var half := GRID * SPACING
	var road_tiles := []
	var walks := []
	for k in range(-GRID, GRID + 1):
		var c := k * SPACING
		for t in range(-int(half / 6), int(half / 6) + 1):
			var a := t * 6.0
			for o in [-6, 0, 6]:
				road_tiles.append_array([_p(a, c + o), _p(c + o, a)])
			if _off_crossing(a, ROAD_HALF + 3.0):
				for o in [-WALK, WALK]:
					walks.append_array([_p(a, c + o), _p(c + o, a)])
	instanced("road_tile_v01", road_tiles, {"collide": false, "shadow": false})
	instanced("sidewalk_tile_v01", walks, {"collide": true, "shadow": false, "layer": 16}) # not layer 1: vehicles ignore the curb
	for k in range(-GRID, GRID + 1):
		map_features.append({"kind": "road", "min": Vector2(-half, k * SPACING - ROAD_HALF), "max": Vector2(half, k * SPACING + ROAD_HALF)})
		map_features.append({"kind": "road", "min": Vector2(k * SPACING - ROAD_HALF, -half), "max": Vector2(k * SPACING + ROAD_HALF, half)})

	# ---- building rows: kit buildings facade-to-facade along every block face (config/citykit.json
	# footprints), facades 11 m from the street centre; Citadel Square around the portal stays open ----
	var foot := {"kit_gothic_tower": [16, 16], "kit_office_tower": [17, 17], "kit_apartment": [14, 13],
		"kit_warehouse": [24, 20], "kit_shopfront": [10, 12]}
	var kinds := ["kit_apartment", "kit_shopfront", "kit_office_tower", "kit_apartment", "kit_warehouse", "kit_shopfront", "kit_gothic_tower"]
	var lots := {}
	places = Places.new()
	places.name = "Places"
	places.district = self
	add_child(places)
	var place_types := ["store", "diner", "pawn", "store", "bank", "diner"]
	var n_places := 0
	for axis in ["x", "z"]:
		for k in range(-GRID, GRID + 1):
			var c := k * SPACING
			for side in [-1, 1]:
				for blk in range(-GRID, GRID):
					var cursor := blk * SPACING + FACADE + 1.0
					var stop := (blk + 1) * SPACING - FACADE - 1.0
					while cursor < stop:
						var kind: String = kinds[int(_rand() * kinds.size())]
						var w: float = foot[kind][0]
						var d: float = foot[kind][1]
						if cursor + w > stop:
							break
						var along := cursor + w / 2
						var off: float = c + side * (FACADE + d / 2)
						var at := Vector2(along, off) if axis == "x" else Vector2(off, along)
						if not clear_lot(at) and not Places.is_park_block(at):
							var rot: float = (PI if side > 0 else 0.0) if axis == "x" else (-PI / 2 if side > 0 else PI / 2)
							var front := Vector3(0, 0, -side) if axis == "x" else Vector3(-side, 0, 0)
							if kind == "kit_shopfront" and n_places < 36 and _rand() < 0.22:
								places.add_place(place_types[n_places % place_types.size()], Vector3(at.x, 0, at.y), front, w, d, n_places)
								n_places += 1
							elif kind == "kit_warehouse" and n_places < 36 and _rand() < 0.2:
								places.add_place("bank" if n_places % 2 == 0 else "gym", Vector3(at.x, 0, at.y), front, w, d, n_places)
								n_places += 1
							else:
								_add(lots, kind, _p(at.x, at.y, rot))
						cursor += w + 1.5
	for kind in lots:
		instanced(kind, lots[kind], {"collide": true, "map_kind": "building", "chunk": 40, "vis_end": LOD_DIST})
		instanced(kind + "_lod1", lots[kind], {"collide": false, "shadow": false, "chunk": 40, "vis_begin": LOD_DIST})
	# simplified distant skyline beyond the grid (LOD1 only, no collision); off now that CityExtender builds
	# real blocks out to the horizon
	var sky := {}
	for i in (0 if ENDLESS else 72):
		var a := (i / 72.0) * TAU + _rand() * 0.04
		var r := half + 140 + _rand() * 120
		var kind: String = ["kit_office_tower", "kit_gothic_tower", "kit_apartment"][i % 3]
		_add(sky, kind, _p(cos(a) * r, sin(a) * r, -a - PI / 2, 0.0, 1.4 + _rand() * 1.2))
	for kind in sky:
		instanced(kind + "_lod1", sky[kind], {"collide": false, "shadow": false, "chunk": 200})

	# ---- per street: lamps (arm over the road), trees, manholes, drains, parked cars; per crossing: lights ----
	var lamp_list := []
	var trees := []
	var covers := []
	var drains := []
	var cars := []
	for k in range(-GRID, GRID + 1):
		var c := k * SPACING
		for t in range(-int(half / 12), int(half / 12)):
			var a := t * 12.0 + 6.0
			if not _off_crossing(a, 20.0):
				continue # keep crossings clear
			if t % 2 == 0:
				lamp_list.append_array([_p(a, c - 10.2, -PI / 2), _p(c + 10.2, a, PI)])
			else:
				lamp_list.append_array([_p(a, c + 10.2, PI / 2), _p(c - 10.2, a, 0)])
			if posmod(t, 3) == 0:
				trees.append_array([_p(a + 3, c + 13.6, t), _p(c - 13.6, a + 3, t * 2)])
			if posmod(t, 3) == 1:
				covers.append_array([_p(a, c + 4.4), _p(c - 4.4, a)])
				drains.append_array([_p(a + 2, c + 8.7), _p(c + 8.7, a + 2, PI / 2)])
			if _rand() < 0.1 and Vector2(a, c).distance_to(SQUARE) > SQUARE_RADIUS and Vector2(c, a).distance_to(SQUARE) > SQUARE_RADIUS:
				var lane := -7.6 if _rand() < 0.5 else 7.6 # parked against the kerb, clear of both traffic lanes
				cars.append(_p(a, c + lane) if _rand() < 0.5 else _p(c + lane, a, PI / 2))
	var lights := []
	var crossings := []
	var signs := []
	for kx in range(-GRID, GRID + 1):
		for kz in range(-GRID, GRID + 1):
			var x := kx * SPACING
			var z := kz * SPACING
			var r := ROAD_HALF + 1.0
			lights.append_array([_p(x + r, z + r, PI), _p(x - r, z - r, 0), _p(x - r, z + r, PI / 2), _p(x + r, z - r, -PI / 2)])
			for o in [-6, 0, 6]: # three crosswalk tiles span the 18 m road
				crossings.append_array([_p(x + 12.5, z + o), _p(x - 12.5, z + o), _p(x + o, z + 12.5, PI / 2), _p(x + o, z - 12.5, PI / 2)])
			if posmod(kx + kz, 2) == 0:
				signs.append_array([_p(x + 11.5, z - 11.5, 0.3), _p(x - 11.5, z + 11.5, PI + 0.3)])
	instanced("kit_streetlight", lamp_list, {"collide": true})
	for l in lamp_list:
		var head := Vector3(1.75, 6.55, 0).rotated(Vector3.UP, l["rot"])
		lamps.append({"pos": Vector3(l["x"], 0, l["z"]) + head, "off_until": 0.0})
	instanced("kit_traffic_light", lights, {"collide": true})
	instanced("kit_crosswalk", crossings, {"collide": false, "shadow": false})
	instanced("kit_street_sign", signs, {"collide": true})
	instanced("kit_manhole", covers, {"collide": false, "shadow": false})
	instanced("kit_drain", drains, {"collide": false, "shadow": false})
	instanced("kit_street_tree", trees, {"collide": true})
	instanced("car_prop_v01", cars, {"collide": true})

	# ---- sidewalk props along every street ----
	var props := _scatter_grid(["kit_trash_can", "kit_hydrant", "kit_bench", "kit_mailbox", "kit_recycling_bin", "kit_vending_machine",
		"kit_utility_cabinet", "kit_garbage_bag", "kit_bus_shelter", "kit_dumpster", "kit_bush"], 5)
	for id in props:
		instanced(id, props[id], {"collide": id != "kit_garbage_bag" and id != "kit_bush"})
	# dumpster alley + an industrial yard near the start (enemy hideouts)
	# (each in its own cleared lot beside the x avenue: see CLEAR)
	instanced("kit_dumpster", [_p(-44, -28, 0), _p(-41.4, -28, 0), _p(-35, -31, 0.4)], {"collide": true})
	instanced("kit_shipping_container", [_p(92, 30), _p(92, 30, 0, 2.6), _p(101, 37, 0.2), _p(84, 40, PI / 2)], {"collide": true})
	instanced("kit_generator", [_p(84, 26)], {"collide": true})
	instanced("kit_fence", [_p(88, 48), _p(94, 48), _p(100, 48)], {"collide": true})
	instanced("kit_jersey_barrier", [_p(86, 17), _p(89.2, 17), _p(-46, -19)], {"collide": true})

	# ---- physics playthings near the start ----
	var loose := _scatter(["kit_cardboard_box", "barrel_v01", "kit_traffic_cone", "kit_pallet", "kit_toolbox"], 30, 34)
	for id in loose:
		for p in loose[id]:
			_dynamic_prop(id, p)

	for b in Places.PARKS:
		places.add_park(b)
	_billboards()
	_citadel_portal()


## True when `a` (a coordinate along a street) is more than `margin` from the nearest crossing.
func _off_crossing(a: float, margin := 6.5) -> bool:
	return absf(a - roundf(a / SPACING) * SPACING) > margin


## Sidewalk props along every street: `per_block` per block face, both sides.
func _scatter_grid(ids: Array, per_block: int) -> Dictionary:
	var out := {}
	var n := 0
	for axis in ["x", "z"]:
		for k in range(-GRID, GRID + 1):
			for blk in range(-GRID, GRID):
				for i in per_block:
					var along := blk * SPACING + 14 + _rand() * (SPACING - 28)
					var off := k * SPACING + (-1.0 if _rand() < 0.5 else 1.0) * (10.6 + _rand() * 2.6)
					var p := _p(along, off) if axis == "x" else _p(off, along)
					p["rot"] = _rand() * TAU
					_add(out, ids[n % ids.size()], p)
					n += 1
	return out


func _ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1300, 1300)
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
	_box(body, Vector3(1300, 2, 1300), Transform3D(Basis(), Vector3(0, -1, 0)))


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
		var off := side * (10.6 + _rand() * 2.4)
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
	# one mesh per asset with one surface per material (like mergeByMaterial in the web build): a kit
	# building has 200+ parts, and drawing each as its own MultiMesh made the city draw-call bound
	if meshes.size() > 1:
		meshes = [{"mesh": _merge(meshes), "xf": Transform3D(), "skin": false}]
	var info := {"meshes": meshes, "cols": cols, "bounds": bounds}
	_proto_cache[id] = info
	return info


func _merge(parts: Array) -> Mesh:
	var groups := {} # key -> {mat, arrays: [verts, normals, tangents, colors, uvs, indices]}
	for part in parts:
		var mesh: Mesh = part["mesh"]
		var xf: Transform3D = part["xf"]
		var nb := xf.basis.inverse().transposed()
		for si in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var a := mesh.surface_get_arrays(si)
			var mat := mesh.surface_get_material(si)
			var has_c: bool = a[Mesh.ARRAY_COLOR] != null and a[Mesh.ARRAY_COLOR].size() > 0
			var has_uv: bool = a[Mesh.ARRAY_TEX_UV] != null and a[Mesh.ARRAY_TEX_UV].size() > 0
			var key := "%d|%s|%s" % [mat.get_instance_id() if mat else 0, has_c, has_uv]
			if not groups.has(key):
				groups[key] = {"mat": mat, "v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
					"uv": PackedVector2Array(), "i": PackedInt32Array(), "has_c": has_c, "has_uv": has_uv}
			var g: Dictionary = groups[key]
			var base: int = g["v"].size()
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var norms = a[Mesh.ARRAY_NORMAL]
			for k in verts.size():
				g["v"].append(xf * verts[k])
				g["n"].append((nb * norms[k]).normalized() if norms and norms.size() > k else Vector3.UP)
			if has_c:
				g["c"].append_array(a[Mesh.ARRAY_COLOR])
			if has_uv:
				g["uv"].append_array(a[Mesh.ARRAY_TEX_UV])
			var idx = a[Mesh.ARRAY_INDEX]
			if idx and idx.size() > 0:
				for k in idx:
					g["i"].append(base + k)
			else:
				for k in verts.size():
					g["i"].append(base + k)
	var im := ImporterMesh.new()
	for key in groups:
		var g: Dictionary = groups[key]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g["v"]
		arr[Mesh.ARRAY_NORMAL] = g["n"]
		if g["has_c"]:
			arr[Mesh.ARRAY_COLOR] = g["c"]
		if g["has_uv"]:
			arr[Mesh.ARRAY_TEX_UV] = g["uv"]
		arr[Mesh.ARRAY_INDEX] = g["i"]
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, g["mat"])
	im.generate_lods(25.0, 60.0, []) # automatic distance LODs, as the importer made for the parts
	return im.get_mesh()


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
	# every repeated asset is chunked (48 m by default) so off-screen groups are culled in both the main and
	# shadow passes; a district-wide MultiMesh is never culled
	var chunk: float = opts.get("chunk", 48.0)
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
			# distance LOD per chunk: full-detail kit up close, the merged *_lod1 version further out
			mmi.visibility_range_begin = opts.get("vis_begin", 0.0)
			mmi.visibility_range_end = opts.get("vis_end", 0.0)
			add_child(mmi)
	var body: StaticBody3D = null
	if opts.get("collide", false):
		body = StaticBody3D.new()
		body.collision_layer = opts.get("layer", 1)
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
	var spots := [[-21, -14.2, 0], [21, 14.2, PI], [14.2, -27, -PI / 2], [-14.2, 27, PI / 2],
		[-60, 14.2, PI], [60, -14.2, 0], [-14.2, -60, PI / 2], [14.2, 60, -PI / 2]]
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
