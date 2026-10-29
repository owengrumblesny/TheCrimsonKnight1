class_name Places
extends Node3D
## Enterable places and parks in New Gotham (Godot port).
##  - Places replace some shopfront / warehouse lots with a procedural building whose ground floor is a real
##    room: store, bank, diner, pawn shop or gym. Each has a glass storefront with a doorway, a lit main room,
##    a back room behind a partition, and furniture. Glass, partitions and furniture are Smashable: the
##    CR-X1 Interceptor ploughs straight through them (Vehicle._smash_ahead), and they rebuild later.
##    Bank and store robberies spawn inside them (Director.start_crime), so fights happen indoors.
##  - Parks fill whole blocks (no buildings): lawns, crossing paths, a fountain, trees, benches and lamps.

const TYPES := {
	"store": {"names": ["QUIK-STOP MART", "GOTHAM GROCER", "24/7 CORNER STORE"], "light": Color("#e8f4ff")},
	"bank": {"names": ["FIRST NEW GOTHAM BANK", "CRIMSON TRUST & SAVINGS", "HARBOR CITY BANK"], "light": Color("#fff2d8")},
	"diner": {"names": ["MIDNIGHT DINER", "RIVERSIDE GRILL", "THE COFFEE CUP"], "light": Color("#ffd9a8")},
	"pawn": {"names": ["LUCKY PAWN", "GOLD & LOAN", "SECOND CHANCE PAWN"], "light": Color("#ffe6c4")},
	"gym": {"names": ["IRONWORKS GYM", "SOUTHSIDE BOXING CLUB"], "light": Color("#dfe8ff")},
}
## blocks (Vector2i block index, block spans [i*S, (i+1)*S]) that are parks instead of buildings
const PARKS := [Vector2i(-1, 0), Vector2i(1, 1), Vector2i(-2, -2), Vector2i(2, -1)]
const FLOOR_H := 4.5

var district: District
var list: Array = [] # {type, name, center: Vector3, front: Vector3, w, d, room: Node3D}
var parks: Array = [] # {min: Vector2, max: Vector2}
var _mats := {}


static func is_park_block(at: Vector2) -> bool:
	var S := District.SPACING
	return Vector2i(floori(at.x / S), floori(at.y / S)) in PARKS


func _mat(key: String, color: Color, emit := 0.0, alpha := 1.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = 0.6
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.4
		m.roughness = 0.08
	_mats[key] = m
	return m


## Visual box (no collision) in `parent`'s space.
func _vis(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, range_end := 160.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	mi.visibility_range_end = range_end
	parent.add_child(mi)
	return mi


## Solid box (collision layer 1) with a mesh.
func _solid(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	_vis(sb, size, Vector3.ZERO, mat)
	parent.add_child(sb)
	return sb


func _smash(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, glass := false) -> Smashable:
	var s := Smashable.new()
	s.position = pos
	s.setup(size, mat, glass)
	parent.add_child(s)
	return s


## Build one place. at = lot centre (ground), front = unit vector toward the street, w along the street, d deep.
func add_place(type: String, at: Vector3, front: Vector3, w: float, d: float, seed_i: int) -> void:
	var root := Node3D.new()
	root.name = "Place_%s_%d" % [type, list.size()]
	var x_axis := Vector3.UP.cross(front)
	root.transform = Transform3D(Basis(x_axis, Vector3.UP, front), at)
	add_child(root)
	var t: Dictionary = TYPES[type]
	var nm: String = t["names"][seed_i % t["names"].size()]
	var wall := _mat("wall_%d" % (seed_i % 3), [Color("#2a2228"), Color("#30282a"), Color("#262a30")][seed_i % 3])
	var inner := _mat("inner_" + type, {"store": Color("#d8d4cc"), "bank": Color("#c9bfae"), "diner": Color("#8a3a3a"),
		"pawn": Color("#5a4a3a"), "gym": Color("#5c6066")}[type])
	var floor_m := _mat("floor_" + type, {"store": Color("#b8b4ae"), "bank": Color("#d9d2c4"), "diner": Color("#2b2626"),
		"pawn": Color("#4a3c30"), "gym": Color("#2a2c30")}[type])
	var glass := _mat("glass", Color("#9fc4e0"), 0.15, 0.28)
	var hw := w / 2.0
	var hd := d / 2.0
	var floors := 2 + seed_i % 3
	var top := FLOOR_H + floors * 4.0
	# shell: back + sides solid, upper floors one solid block with lit windows on the front
	_solid(root, Vector3(w, FLOOR_H, 0.3), Vector3(0, FLOOR_H / 2, -hd + 0.15), wall)
	_solid(root, Vector3(0.3, FLOOR_H, d), Vector3(-hw + 0.15, FLOOR_H / 2, 0), wall)
	_solid(root, Vector3(0.3, FLOOR_H, d), Vector3(hw - 0.15, FLOOR_H / 2, 0), wall)
	_solid(root, Vector3(w, top - FLOOR_H, d), Vector3(0, FLOOR_H + (top - FLOOR_H) / 2, 0), wall)
	var win := _mat("win", Color("#ffe3b0"), 1.6)
	for f in floors:
		for i in int(w / 3.0):
			if (i + f + seed_i) % 3 != 0:
				_vis(root, Vector3(1.4, 1.6, 0.06), Vector3(-hw + 1.5 + i * 3.0, FLOOR_H + 1.6 + f * 4.0, hd + 0.03), win, 260.0)
	_vis(root, Vector3(w, 0.06, d), Vector3(0, 0.03, 0), floor_m)
	_vis(root, Vector3(w - 0.6, 0.05, d - 0.6), Vector3(0, FLOOR_H - 0.03, 0), inner) # ceiling
	# storefront: header over glass panes (smashable), door gap at the left end
	_solid(root, Vector3(w, 1.1, 0.3), Vector3(0, FLOOR_H - 0.55, hd - 0.15), wall)
	var door_w := 2.0
	var x := -hw + 0.3 + door_w
	while x < hw - 0.35:
		var pw := minf(2.4, hw - 0.3 - x)
		if pw > 0.4:
			_smash(root, Vector3(pw - 0.05, FLOOR_H - 1.1, 0.12), Vector3(x + pw / 2, (FLOOR_H - 1.1) / 2, hd - 0.15), glass, true)
		x += pw
	# sign over the door / header
	var sign := Label3D.new()
	sign.text = nm
	sign.font_size = 96
	sign.pixel_size = 0.012
	sign.modulate = Color("#ff4d64") if type != "bank" else Color("#ffd27a")
	sign.outline_size = 0
	sign.shaded = false
	sign.position = Vector3(0, FLOOR_H - 0.55, hd + 0.02)
	sign.visibility_range_end = 220.0
	root.add_child(sign)
	# back room partition (smashable) with a doorway
	var pz := -hd + d * 0.34
	var gap := 1.6
	var lw := (w - gap) * 0.65
	_smash(root, Vector3(lw, FLOOR_H - 0.2, 0.2), Vector3(-hw + lw / 2, (FLOOR_H - 0.2) / 2, pz), inner)
	var rw := w - gap - lw
	if rw > 0.3:
		_smash(root, Vector3(rw, FLOOR_H - 0.2, 0.2), Vector3(hw - rw / 2, (FLOOR_H - 0.2) / 2, pz), inner)
	# light: one warm/cool fill that fades out with distance (cheap on the laptop)
	var l := OmniLight3D.new()
	l.light_color = t["light"]
	l.light_energy = 1.6
	l.omni_range = maxf(w, d) * 0.9
	l.position = Vector3(0, FLOOR_H - 0.8, hd * 0.25)
	l.distance_fade_enabled = true
	l.distance_fade_begin = 40.0
	l.distance_fade_length = 20.0
	root.add_child(l)
	_vis(root, Vector3(w * 0.5, 0.04, 1.0), Vector3(0, FLOOR_H - 0.06, hd * 0.25), _mat("panel", t["light"], 2.5))
	_furnish(root, type, w, d, pz, seed_i)
	list.append({"type": type, "name": nm, "center": root.global_transform * Vector3(0, 0.1, hd * 0.25),
		"back": root.global_transform * Vector3(0, 0.1, (-hd + pz) / 2.0), "front": front, "w": w, "d": d, "room": root})
	district.map_features.append({"kind": "place", "min": Vector2(at.x - maxf(w, d) / 2, at.z - maxf(w, d) / 2),
		"max": Vector2(at.x + maxf(w, d) / 2, at.z + maxf(w, d) / 2)})


func _furnish(root: Node3D, type: String, w: float, d: float, pz: float, _seed_i: int) -> void:
	var hw := w / 2.0
	var hd := d / 2.0
	var front_room := hd - pz # depth of the main room
	var mid := (hd + pz) / 2.0
	var wood := _mat("wood", Color("#5a3a26"))
	var metal := _mat("metal", Color("#6a6e76"))
	match type:
		"store":
			for i in 3:
				var sx := -hw + w * (0.3 + i * 0.22)
				_smash(root, Vector3(0.7, 1.7, front_room * 0.55), Vector3(sx, 0.85, mid - 0.4), metal)
			_smash(root, Vector3(2.4, 1.0, 0.8), Vector3(hw - 2.0, 0.5, hd - 2.2), wood) # checkout
			_vis(root, Vector3(0.4, 1.9, front_room * 0.7), Vector3(hw - 0.6, 0.95, mid), _mat("fridge", Color("#a8d8ff"), 0.9))
		"bank":
			_smash(root, Vector3(w * 0.7, 1.15, 0.7), Vector3(0, 0.58, pz + 1.6), _mat("marble", Color("#d8d0c4")))
			for i in 2:
				_solid(root, Vector3(0.6, FLOOR_H, 0.6), Vector3((-1 if i == 0 else 1) * hw * 0.45, FLOOR_H / 2, mid + 1.0), _mat("marble", Color("#d8d0c4")))
			# vault door in the back room
			var vault := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 1.2
			cyl.bottom_radius = 1.2
			cyl.height = 0.3
			cyl.material = metal
			vault.mesh = cyl
			vault.rotation.x = PI / 2
			vault.position = Vector3(0, 1.4, -hd + 0.35)
			root.add_child(vault)
		"diner":
			for i in int((w - 3.0) / 2.6):
				var bx := -hw + 2.2 + i * 2.6
				_smash(root, Vector3(1.2, 0.75, 0.8), Vector3(bx, 0.38, hd - 1.6), _mat("table", Color("#d9d4cc")))
				_smash(root, Vector3(1.4, 1.0, 0.45), Vector3(bx, 0.5, hd - 2.4), _mat("booth", Color("#9c1f2e")))
			_smash(root, Vector3(w * 0.6, 1.1, 0.7), Vector3(0, 0.55, pz + 1.3), wood)
		"pawn":
			for i in 3:
				_smash(root, Vector3(1.8, 1.0, 0.7), Vector3(-hw + 2.0 + i * 2.6, 0.5, mid), _mat("case", Color("#c8e8ff"), 0.6, 0.6))
			_vis(root, Vector3(0.1, 2.2, front_room * 0.8), Vector3(-hw + 0.4, 1.6, mid), wood)
		"gym":
			for i in 4:
				var bag := MeshInstance3D.new()
				var c := CylinderMesh.new()
				c.top_radius = 0.3
				c.bottom_radius = 0.3
				c.height = 1.2
				c.material = _mat("bag", Color("#8a1a24"))
				bag.mesh = c
				bag.position = Vector3(-hw + 2.5 + i * (w - 5.0) / 3.0, 2.0, mid + 1.5)
				root.add_child(bag)
			_vis(root, Vector3(w * 0.5, 0.08, front_room * 0.4), Vector3(0, 0.07, mid - 1.0), _mat("mat", Color("#203a6a")))
			_smash(root, Vector3(3.0, 0.9, 1.0), Vector3(hw - 2.5, 0.45, mid - 2.0), metal) # weight rack


## A whole-block park: lawn, crossing paths, fountain, trees, benches, lamps.
func add_park(block: Vector2i) -> void:
	var S := District.SPACING
	var inset := District.WALK + 2.0
	var mn := Vector2(block.x * S + inset, block.y * S + inset)
	var mx := Vector2((block.x + 1) * S - inset, (block.y + 1) * S - inset)
	var c := (mn + mx) / 2
	var size := mx - mn
	var root := Node3D.new()
	root.name = "Park_%d_%d" % [block.x, block.y]
	add_child(root)
	_vis(root, Vector3(size.x, 0.05, size.y), Vector3(c.x, 0.02, c.y), _mat("lawn", Color("#1d3a1f")), 400.0)
	var path := _mat("path", Color("#6e6a64"))
	_vis(root, Vector3(size.x, 0.07, 4.0), Vector3(c.x, 0.035, c.y), path, 400.0)
	_vis(root, Vector3(4.0, 0.07, size.y), Vector3(c.x, 0.035, c.y), path, 400.0)
	# fountain
	var basin := StaticBody3D.new()
	basin.position = Vector3(c.x, 0.4, c.y)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 5.0
	sh.height = 0.8
	cs.shape = sh
	basin.add_child(cs)
	var bm := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 5.0
	cy.bottom_radius = 5.2
	cy.height = 0.8
	cy.material = _mat("stone", Color("#5c5a58"))
	bm.mesh = cy
	basin.add_child(bm)
	var water := MeshInstance3D.new()
	var wc := CylinderMesh.new()
	wc.top_radius = 4.6
	wc.bottom_radius = 4.6
	wc.height = 0.05
	wc.material = _mat("water", Color("#2a5a7a"), 0.25, 0.75)
	water.mesh = wc
	water.position.y = 0.38
	basin.add_child(water)
	var spout := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.5
	sc.bottom_radius = 0.8
	sc.height = 2.6
	sc.material = cy.material
	spout.mesh = sc
	spout.position.y = 1.1
	basin.add_child(spout)
	root.add_child(basin)
	var trees := []
	var benches := []
	var lamps := []
	var bushes := []
	var rng := RandomNumberGenerator.new()
	rng.seed = block.x * 7919 + block.y * 104729
	for i in 26:
		var p := Vector2(rng.randf_range(mn.x + 3, mx.x - 3), rng.randf_range(mn.y + 3, mx.y - 3))
		if absf(p.x - c.x) < 5 or absf(p.y - c.y) < 5 or p.distance_to(c) < 9:
			continue
		trees.append({"x": p.x, "z": p.y, "rot": rng.randf() * TAU, "y": 0.0, "scale": rng.randf_range(1.1, 1.6)})
	for i in 12:
		var p2 := Vector2(rng.randf_range(mn.x + 3, mx.x - 3), rng.randf_range(mn.y + 3, mx.y - 3))
		if absf(p2.x - c.x) > 5 and absf(p2.y - c.y) > 5:
			bushes.append({"x": p2.x, "z": p2.y, "rot": rng.randf() * TAU, "y": 0.0, "scale": 1.0})
	for s in [-1, 1]:
		for k in [12.0, 26.0]:
			benches.append({"x": c.x + s * k, "z": c.y + 3.2, "rot": PI, "y": 0.0, "scale": 1.0})
			benches.append({"x": c.x - 3.2, "z": c.y + s * k, "rot": PI / 2, "y": 0.0, "scale": 1.0})
			lamps.append({"x": c.x + s * (k + 6), "z": c.y - 3.0, "rot": PI / 2, "y": 0.0, "scale": 1.0})
			lamps.append({"x": c.x + 3.0, "z": c.y + s * (k + 6), "rot": PI, "y": 0.0, "scale": 1.0})
	district.instanced("kit_street_tree", trees, {"collide": true})
	district.instanced("kit_bench", benches, {"collide": true})
	district.instanced("kit_bush", bushes, {"collide": false})
	district.instanced("kit_streetlight", lamps, {"collide": true})
	for l in lamps:
		district.lamps.append({"pos": Vector3(l["x"], 6.55, l["z"]), "off_until": 0.0})
	parks.append({"min": mn, "max": mx, "center": Vector3(c.x, 0, c.y)})
	district.map_features.append({"kind": "park", "min": mn, "max": mx})


## True when p is inside a place's ground floor (no rain indoors).
func inside(p: Vector3) -> bool:
	for pl in list:
		var l: Vector3 = pl["room"].global_transform.affine_inverse() * p
		if absf(l.x) < pl["w"] / 2.0 and absf(l.z) < pl["d"] / 2.0 and l.y < FLOOR_H:
			return true
	return false


## Nearest place of `type` ("" = any) to `from`, or {}.
func nearest(from: Vector3, type := "", max_d := 1e9) -> Dictionary:
	var best := {}
	var bd := max_d
	for p in list:
		if type != "" and p["type"] != type:
			continue
		var d: float = from.distance_to(p["center"])
		if d < bd:
			bd = d
			best = p
	return best


## A place of `type` between min_d and max_d from `from` (random among those), or {}.
func pick(from: Vector3, types: Array, min_d: float, max_d: float) -> Dictionary:
	var c := list.filter(func(p): return p["type"] in types and from.distance_to(p["center"]) > min_d and from.distance_to(p["center"]) < max_d)
	return c[randi() % c.size()] if not c.is_empty() else {}
