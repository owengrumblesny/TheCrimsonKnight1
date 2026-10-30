class_name CityExtender
extends Node3D
## Endless New Gotham: as the Knight nears the edge of the built city, more city blocks are generated around
## him, so the world keeps going. Each block (District.SPACING square, indexed like Places.PARKS) gets its
## ground slab, the avenues and sidewalks on its edges, street lamps and rows of kit buildings on its four faces,
## with the occasional park or enterable shop. Deterministic per block (same city every time). One block is
## built per frame (no hitch); blocks far behind are freed to keep memory flat.

const BUILD_RADIUS := 380.0
const FREE_RADIUS := 1100.0
const FOOT := {"kit_gothic_tower": [16, 16], "kit_office_tower": [17, 17], "kit_apartment": [14, 13],
	"kit_warehouse": [24, 20], "kit_shopfront": [10, 12]}
const KINDS := ["kit_apartment", "kit_shopfront", "kit_office_tower", "kit_apartment", "kit_warehouse", "kit_shopfront", "kit_gothic_tower"]

var district: District
var blocks := {} # Vector2i -> Node3D
var _edges := {} # "x|k|i" road segments already laid
var _queue: Array = []
var _check_t := 0.0


## Blocks the original district already covers.
static func core(b: Vector2i) -> bool:
	return b.x >= -District.GRID and b.x < District.GRID and b.y >= -District.GRID and b.y < District.GRID


func update(p: Vector3, dt: float) -> void:
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = 0.5
		var S := District.SPACING
		var c := Vector2i(floori(p.x / S), floori(p.z / S))
		var r := int(ceil(BUILD_RADIUS / S)) + 1
		for i in range(c.x - r, c.x + r + 1):
			for j in range(c.y - r, c.y + r + 1):
				var b := Vector2i(i, j)
				if core(b) or blocks.has(b) or b in _queue:
					continue
				var nearest := Vector2(clampf(p.x, i * S, (i + 1) * S), clampf(p.z, j * S, (j + 1) * S))
				if nearest.distance_to(Vector2(p.x, p.z)) < BUILD_RADIUS:
					_queue.append(b)
		# nearest first
		_queue.sort_custom(func(a, b2): return Vector2(a * S).distance_to(Vector2(p.x, p.z)) < Vector2(b2 * S).distance_to(Vector2(p.x, p.z)))
		for b in blocks.keys():
			var centre := Vector2((b.x + 0.5) * S, (b.y + 0.5) * S)
			if centre.distance_to(Vector2(p.x, p.z)) > FREE_RADIUS:
				blocks[b].queue_free()
				blocks.erase(b)
	if not _queue.is_empty():
		_build(_queue.pop_front())


func _build(b: Vector2i) -> void:
	var S := District.SPACING
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(b) ^ 0x5eed
	var root := Node3D.new()
	root.name = "Block_%d_%d" % [b.x, b.y]
	add_child(root)
	blocks[b] = root
	var x0 := b.x * S
	var z0 := b.y * S
	# ground slab (the district's own ground ends at ±650 m)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(S, S)
	pm.material = district.wet
	g.mesh = pm
	g.position = Vector3(x0 + S / 2.0, 0.0, z0 + S / 2.0)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(g)
	var body := StaticBody3D.new()
	root.add_child(body)
	district._box(body, Vector3(S, 2, S), Transform3D(Basis(), Vector3(x0 + S / 2.0, -1.0, z0 + S / 2.0)))
	# roads + sidewalks + lamps on the block's four edges (each edge laid once, shared with the neighbour)
	var road := []
	var walks := []
	var lamps := []
	for e in [["x", z0, x0], ["x", z0 + S, x0], ["z", x0, z0], ["z", x0 + S, z0]]:
		var key := "%s|%d|%d" % [e[0], e[1], e[2]]
		if _edges.has(key):
			continue
		_edges[key] = true
		var c: float = e[1]
		for t in range(0, int(S / 6.0)):
			var a: float = e[2] + t * 6.0 + 3.0
			for o in [-6, 0, 6]:
				road.append(district._p(a, c + o) if e[0] == "x" else district._p(c + o, a))
			if district._off_crossing(a, District.ROAD_HALF + 3.0):
				for o in [-District.WALK, District.WALK]:
					walks.append(district._p(a, c + o) if e[0] == "x" else district._p(c + o, a))
		for t in range(0, int(S / 12.0)):
			var a2: float = e[2] + t * 12.0 + 6.0
			if district._off_crossing(a2, 20.0):
				if e[0] == "x":
					lamps.append(district._p(a2, c - 10.2, -PI / 2))
				else:
					lamps.append(district._p(c + 10.2, a2, PI))
	var park := rng.randf() < 0.12
	var lots := {}
	if park and district.places:
		district.places.add_park(b)
	else:
		for face in [["x", z0, 1], ["x", z0 + S, -1], ["z", x0, 1], ["z", x0 + S, -1]]:
			var c2: float = face[1]
			var side: int = face[2]
			var cursor: float = (x0 if face[0] == "x" else z0) + District.FACADE + 1.0
			var stop: float = (x0 if face[0] == "x" else z0) + S - District.FACADE - 1.0
			while cursor < stop:
				var kind: String = KINDS[rng.randi() % KINDS.size()]
				var w: float = FOOT[kind][0]
				var d: float = FOOT[kind][1]
				if cursor + w > stop:
					break
				var along := cursor + w / 2.0
				var off := c2 + side * (District.FACADE + d / 2.0)
				var at := Vector2(along, off) if face[0] == "x" else Vector2(off, along)
				var rot: float = (PI if side > 0 else 0.0) if face[0] == "x" else (-PI / 2 if side > 0 else PI / 2)
				var front := Vector3(0, 0, -side) if face[0] == "x" else Vector3(-side, 0, 0)
				if kind == "kit_shopfront" and rng.randf() < 0.12 and district.places:
					district.places.add_place(["store", "diner", "pawn", "bank"][rng.randi() % 4], Vector3(at.x, 0, at.y), front, w, d, rng.randi() % 97)
				else:
					district._add(lots, kind, district._p(at.x, at.y, rot, 0.0, 1.0 + rng.randf() * 0.35 if kind in ["kit_office_tower", "kit_gothic_tower"] else 1.0))
				cursor += w + 1.5
	# build the instanced meshes under this block's root (so freeing the block frees them)
	var before := district.get_child_count()
	district.instanced("road_tile_v01", road, {"collide": false, "shadow": false})
	district.instanced("sidewalk_tile_v01", walks, {"collide": true, "shadow": false, "layer": 16})
	district.instanced("kit_streetlight", lamps, {"collide": true})
	for kind in lots:
		district.instanced(kind, lots[kind], {"collide": true, "map_kind": "building", "chunk": 40, "vis_end": District.LOD_DIST})
		district.instanced(kind + "_lod1", lots[kind], {"collide": false, "shadow": false, "chunk": 40, "vis_begin": District.LOD_DIST})
	var made: Array = []
	for i in range(before, district.get_child_count()):
		made.append(district.get_child(i))
	for n in made:
		n.reparent(root)
	for l in lamps:
		var head := Vector3(1.75, 6.55, 0).rotated(Vector3.UP, l["rot"])
		district.lamps.append({"pos": Vector3(l["x"], 0, l["z"]) + head, "off_until": 0.0})
	district.map_features.append({"kind": "road", "min": Vector2(x0 - District.ROAD_HALF, z0 - District.ROAD_HALF), "max": Vector2(x0 + S + District.ROAD_HALF, z0 + District.ROAD_HALF)})
	district.map_features.append({"kind": "road", "min": Vector2(x0 - District.ROAD_HALF, z0 - District.ROAD_HALF), "max": Vector2(x0 + District.ROAD_HALF, z0 + S + District.ROAD_HALF)})
