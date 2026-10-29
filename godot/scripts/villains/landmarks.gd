class_name Landmarks
extends Node3D
## New Gotham's 20 named locations (godot/data/locations.json). 19 are built here, procedurally, in the open
## belt around the downtown grid; the Red Citadel already exists under Citadel Square and is only registered.
## Each site: a recognisable silhouette, at least one enterable interior (a real room with a doorway, lights
## and furniture; "underground" places are halls under a raised plinth reached by stairs up and then down),
## an accent light colour, a synthesized ambience loop (positional) and a few NPCs standing inside.
## Built from boxes, cylinders and the existing city kit: blockout quality, not finished art.
## Site space: origin at the site centre, +Z faces the city centre (every main door is on the +Z side).

const AMB_RATE := 22050

var district: District
var sites := {} # id -> {def, root: Node3D, center: Vector3, spot: Vector3 (world), heading, npcs: [], amb}
var _mats := {}
var _npcs: Array = [] # {root, anim, pending}
var _rng := RandomNumberGenerator.new()


func build(d: District) -> void:
	name = "Landmarks"
	district = d
	_rng.seed = 7077
	_water()
	_boundary()
	for def in CKData.data("locations")["locations"]:
		var p := Vector3(def["pos"][0], 0, def["pos"][1])
		var heading := atan2(-p.x, -p.z) # +Z toward the city centre
		var site := {"def": def, "center": p, "heading": heading, "npcs": [], "spot": p}
		sites[def["id"]] = site
		if def["style"] == "citadel":
			continue
		var root := Node3D.new()
		root.name = "Site_" + str(def["id"])
		root.position = p
		root.rotation.y = heading
		add_child(root)
		site["root"] = root
		var out: Dictionary = call("_build_" + str(def["style"]), root, def)
		site["spot"] = root.global_transform * (out.get("spot", Vector3.ZERO) as Vector3)
		site["spot_heading"] = heading + float(out.get("spot_turn", 0.0))
		var spots: Array = out.get("npc_spots", [])
		var ids: Array = def.get("npcs", [])
		for i in mini(ids.size(), spots.size()):
			_spawn_npc(root, ids[i][0], ids[i][1], spots[i], _rng.randf() * TAU)
		_sign(root, def["name"], out.get("sign", Vector3(0, 9, 14)), Color(str(def["light"])))
		_ambience(root, str(def["ambience"]), out.get("amb", Vector3(0, 2, 0)))
		var r: float = out.get("radius", 30.0)
		_floodlight(root, r, Color(str(def["light"])), out.get("flood", Vector3(0, 8, 0)))
		district.map_features.append({"kind": "building", "min": Vector2(p.x - r, p.z - r), "max": Vector2(p.x + r, p.z + r)})


func location_ids() -> Array:
	return sites.keys()


func loc_name(id: String) -> String:
	return str(sites[id]["def"]["name"]) if sites.has(id) else id


## The site whose centre is nearest `at` (and within max_d), or "".
func nearest(at: Vector3, max_d := 90.0) -> String:
	var best := ""
	var bd := max_d
	for id in sites:
		var d := Vector2(at.x - sites[id]["center"].x, at.z - sites[id]["center"].z).length()
		if d < bd:
			bd = d
			best = id
	return best


## Distance-throttled NPC animation (same scheme as NpcCrowd).
func update(focus: Vector3, dt: float) -> void:
	for n in _npcs:
		var root: Node3D = n["root"]
		var d := root.global_position.distance_to(focus)
		root.visible = d < 110
		var ap: AnimationPlayer = n["anim"]
		if ap == null or d > 60:
			continue
		n["pending"] += dt
		if d > 18 and n["pending"] < 0.1:
			continue
		ap.advance(n["pending"])
		n["pending"] = 0.0


# ---------------- primitives ----------------
func _mat(color: String, emit := 0.0, metal := 0.0, rough := 0.85, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [color, emit, metal, rough, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.metallic = metal
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = emit
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


## Box at `pos` (centre) in `parent` space; solid adds a matching collider. rot = yaw, tilt = roll about Z.
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, solid := true, rot := 0.0, tilt := 0.0, range_end := 0.0) -> Node3D:
	var node: Node3D
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		node = body
	else:
		node = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	if range_end > 0.0:
		mi.visibility_range_end = range_end
	node.add_child(mi)
	node.position = pos
	node.rotation = Vector3(0, rot, tilt)
	parent.add_child(node)
	return node


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, solid := true, sides := 16) -> Node3D:
	var node: Node3D
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = maxf(r_top, r_bot)
		sh.height = h
		cs.shape = sh
		body.add_child(cs)
		node = body
	else:
		node = Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = sides
	cm.material = mat
	mi.mesh = cm
	node.add_child(mi)
	node.position = pos
	parent.add_child(node)
	return node


## A room with walls, floor and roof; the doorway (door_w x door_h) is centred on the +Z wall.
## floor_y = interior floor height. Windows: emissive strips on the side walls (outside).
func _hall(parent: Node3D, c: Vector3, w: float, d: float, h: float, wall: Material, floor_mat: Material, door_w := 4.0, door_h := 3.6,
		roof := true, win: Material = null) -> void:
	var t := 0.5
	_box(parent, Vector3(w, 0.3, d), c + Vector3(0, 0.15, 0), floor_mat)
	_box(parent, Vector3(w, h, t), c + Vector3(0, h / 2, -d / 2), wall)
	_box(parent, Vector3(t, h, d), c + Vector3(-w / 2, h / 2, 0), wall)
	_box(parent, Vector3(t, h, d), c + Vector3(w / 2, h / 2, 0), wall)
	var side := (w - door_w) / 2
	_box(parent, Vector3(side, h, t), c + Vector3(-(door_w / 2 + side / 2), h / 2, d / 2), wall)
	_box(parent, Vector3(side, h, t), c + Vector3(door_w / 2 + side / 2, h / 2, d / 2), wall)
	_box(parent, Vector3(door_w, h - door_h, t), c + Vector3(0, door_h + (h - door_h) / 2, d / 2), wall)
	if roof:
		_box(parent, Vector3(w + 0.6, 0.5, d + 0.6), c + Vector3(0, h + 0.25, 0), wall)
	if win:
		var n := int(d / 5.0)
		for i in n:
			var z := -d / 2 + (i + 0.5) * d / n
			for sx in [-1.0, 1.0]:
				_box(parent, Vector3(0.1, h * 0.35, 1.4), c + Vector3(sx * (w / 2 + 0.28), h * 0.55, z), win, false, 0.0, 0.0, 220.0)


## Interior light (no shadows, fades out with distance so 19 sites stay cheap).
func _light(parent: Node3D, pos: Vector3, color: Color, energy := 2.0, rng := 14.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.distance_fade_enabled = true
	l.distance_fade_begin = 70.0
	l.distance_fade_length = 20.0
	parent.add_child(l)
	return l


## Facade floodlight from the street side so the silhouette reads at night from a distance.
func _floodlight(root: Node3D, r: float, color: Color, aim: Vector3) -> void:
	var sp := SpotLight3D.new()
	sp.light_color = color.lerp(Color.WHITE, 0.4)
	sp.light_energy = 9.0
	sp.spot_attenuation = 0.35
	sp.light_volumetric_fog_energy = 0.15 # no glowing fog cone in the player's face
	sp.spot_range = r * 2.0 + 40.0
	sp.spot_angle = 50.0
	sp.distance_fade_enabled = true
	sp.distance_fade_begin = 320.0
	sp.distance_fade_length = 60.0
	root.add_child(sp)
	sp.position = Vector3(0, 3.0, r + 16.0)
	sp.look_at(root.global_transform * aim, Vector3.UP)


func _sign(parent: Node3D, text: String, pos: Vector3, color: Color) -> void:
	var l := Label3D.new()
	l.text = text.to_upper()
	l.font_size = 96
	l.outline_size = 14
	l.modulate = color.lightened(0.2)
	l.pixel_size = 0.012
	l.position = pos
	l.visibility_range_end = 320.0
	parent.add_child(l)


## Ramp from (z0, y0) to (z1, y1) along site Z at x, width w (stairs read as ramps: the capsule walks them).
func _ramp(parent: Node3D, x: float, z0: float, y0: float, z1: float, y1: float, w: float, mat: Material) -> void:
	var len := Vector2(z1 - z0, y1 - y0).length()
	var node := _box(parent, Vector3(w, 0.4, len), Vector3(x, (y0 + y1) / 2, (z0 + z1) / 2), mat)
	node.rotation.x = -atan2(y1 - y0, z1 - z0)


## An "underground" hall: a w x d room at ground level under a raised plinth (top at `top` m). Stairs climb
## from the front to the plinth, a stairwell opening at the back of the plinth leads down inside.
func _sunken(root: Node3D, w: float, d: float, top: float, wall: Material, floor_mat: Material, plinth: Material) -> void:
	_hall(root, Vector3.ZERO, w, d, top - 0.5, wall, floor_mat, 3.0, 3.0, false)
	# plinth roof with a 4 x 10 stairwell opening at x = w/2 - 4, against the back wall
	var hx := w / 2 - 4.0
	_box(root, Vector3(w - 6.0, 0.5, d), Vector3(-3.0, top - 0.25, 0), plinth)
	_box(root, Vector3(4.0, 0.5, d - 10.0), Vector3(hx, top - 0.25, 5.0), plinth)
	_box(root, Vector3(2.0, 0.5, d), Vector3(w / 2 - 1.0, top - 0.25, 0), plinth)
	# front stairs from the street up onto the plinth (beside the doorway, which stays a service door)
	_ramp(root, -w / 2 + 3.0, d / 2 + 9.0, 0.0, d / 2, top, 4.0, plinth)
	# stairwell: down from the plinth top (back edge of the opening) to the hall floor
	_ramp(root, hx, -d / 2 + 10.0, top, -d / 2 + 0.6, 0.2, 3.6, floor_mat)
	# low parapet so the opening reads
	_box(root, Vector3(0.3, 1.0, 10.0), Vector3(hx - 2.15, top + 0.5, -d / 2 + 5.0), plinth)


func _spawn_npc(root: Node3D, id: String, clip: String, at: Vector3, rot: float) -> void:
	var path := CKData.model_path(id)
	if path == "":
		return
	var n: Node3D = load(path).instantiate()
	n.position = at
	n.rotation.y = rot
	root.add_child(n)
	for m in n.find_children("*", "GeometryInstance3D", true, false):
		m.extra_cull_margin = 0.6
	var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	if ap:
		var c := clip if ap.has_animation(clip) else "NPC_Idle"
		if ap.has_animation(c):
			ap.get_animation(c).loop_mode = Animation.LOOP_LINEAR
			ap.play(c)
			ap.seek(_rng.randf() * ap.get_animation(c).length, true)
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_npcs.append({"root": n, "anim": ap, "pending": 0.0})
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.56, 1.8, 0.56)
	cs.shape = b
	cs.position.y = 0.9
	body.add_child(cs)
	body.position = at
	root.add_child(body)


## A city-kit model through the district's instancing (gets its *_COL colliders). Site-local position.
func _kit(root: Node3D, id: String, local: Vector3, rot := 0.0, scale := 1.0) -> void:
	var w := root.global_transform * local
	district.instanced(id, [district._p(w.x, w.z, root.rotation.y + rot, w.y, scale)], {"collide": true})


# ---------------- world edges ----------------
## The harbour east of the docks and pier, and the asylum's moat (visual water; the slab ends at 650 m).
func _water() -> void:
	var m := _mat("#0b1a20", 0.0, 0.6, 0.06)
	for r in [[Rect2(605, -700, 800, 2100)], [Rect2(470, 460, 140, 250)]]:
		var rect: Rect2 = r[0]
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = rect.size
		pm.material = m
		mi.mesh = pm
		mi.position = Vector3(rect.position.x + rect.size.x / 2, 0.08, rect.position.y + rect.size.y / 2)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Invisible walls at the slab edge (the landmarks sit near it; nobody walks or drives off the world).
func _boundary() -> void:
	for e in [[Vector3(652, 100, 0), Vector3(2, 200, 1310)], [Vector3(-652, 100, 0), Vector3(2, 200, 1310)],
			[Vector3(0, 100, 652), Vector3(1310, 200, 2)], [Vector3(0, 100, -652), Vector3(1310, 200, 2)]]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = e[1]
		cs.shape = sh
		body.add_child(cs)
		body.position = e[0]
		add_child(body)


# ---------------- the sites ----------------
func _build_asylum(root: Node3D, def: Dictionary) -> Dictionary:
	var stone := _mat("#4c5552")
	var dark := _mat("#2c3230")
	var win := _mat(str(def["light"]), 2.2)
	var lc := Color(str(def["light"]))
	_box(root, Vector3(64, 1.2, 64), Vector3(0, 0.6, 0), _mat("#3a3f35")) # the island
	_ramp(root, 0, 62, 0.0, 32, 1.2, 6.0, dark) # causeway
	for x in [-3.2, 3.2]:
		_box(root, Vector3(0.3, 1.0, 30), Vector3(x, 1.4, 47), dark, true, 0.0, 0.0)
	var c := Vector3(0, 1.2, 4)
	_hall(root, c, 34, 18, 12, stone, dark, 4.0, 3.8, true, win)
	for x in [-22.6, 22.6]: # wings
		_box(root, Vector3(10, 16, 16), Vector3(x, 9.2, 4), stone)
	_box(root, Vector3(8, 14, 8), Vector3(0, 20.2, -2), stone) # central tower
	_cyl(root, 0.0, 5.0, 10, Vector3(0, 32.2, -2), dark, false, 4)
	for i in 4: # ward beds
		_box(root, Vector3(1.0, 0.7, 2.1), Vector3(-12 + i * 3.0, 1.55, -2), _mat("#c8d0cc"), true)
	_box(root, Vector3(3, 1, 1.4), Vector3(9, 1.7, -3), _mat("#5a4636")) # Hollow's desk
	_light(root, c + Vector3(-8, 9, 0), lc, 2.0, 16)
	_light(root, c + Vector3(8, 9, 0), lc, 2.0, 16)
	_box(root, Vector3(62, 3.0, 0.3), Vector3(0, 2.7, -31), dark) # back fence
	return {"spot": Vector3(9, 1.2, -1), "spot_turn": 0.0, "npc_spots": [Vector3(-3, 1.2, 9), Vector3(-10, 1.2, 0), Vector3(-14, 1.2, -4)],
		"sign": Vector3(0, 15, 13.5), "amb": c + Vector3(0, 3, 0), "radius": 34.0, "flood": Vector3(0, 12, 4)}


func _build_prison(root: Node3D, def: Dictionary) -> Dictionary:
	var wall := _mat("#5e5e5a")
	var conc := _mat("#3d3d3b")
	var lc := Color(str(def["light"]))
	for s in [[Vector3(0, 3.5, -35), Vector3(70, 7, 1)], [Vector3(-35, 3.5, 0), Vector3(1, 7, 70)], [Vector3(35, 3.5, 0), Vector3(1, 7, 70)],
			[Vector3(-20, 3.5, 35), Vector3(30, 7, 1)], [Vector3(20, 3.5, 35), Vector3(30, 7, 1)]]:
		_box(root, s[1], s[0], wall)
	for x in [-35.0, 35.0]: # guard towers with floodlights
		for z in [-35.0, 35.0]:
			_cyl(root, 1.8, 2.2, 14, Vector3(x, 7, z), conc)
			_box(root, Vector3(5, 3, 5), Vector3(x, 15.5, z), wall)
			var sp := SpotLight3D.new()
			sp.position = Vector3(x * 0.95, 16, z * 0.95)
			sp.light_color = lc
			sp.light_energy = 4.0
			sp.spot_range = 60
			sp.spot_angle = 30
			sp.distance_fade_enabled = true
			sp.distance_fade_begin = 120.0
			root.add_child(sp)
			sp.look_at(root.global_transform * Vector3(0, 0, 0), Vector3.UP)
	var c := Vector3(0, 0, -12)
	_hall(root, c, 40, 16, 10, wall, conc, 4.0, 3.6, true, _mat("#ffe7b0", 1.5))
	var bars := _mat("#202020", 0.0, 0.8, 0.4)
	for i in 8: # cells along the back wall: bar fronts
		var x := -17.5 + i * 5.0
		_box(root, Vector3(0.3, 3.2, 4.0), Vector3(x - 2.4, 1.9, c.z - 5.5), wall)
		for b in 6:
			_box(root, Vector3(0.08, 3.0, 0.08), Vector3(x - 2.0 + b * 0.8, 1.8, c.z - 3.5), bars)
	_light(root, c + Vector3(-10, 8, 2), lc, 1.8, 16)
	_light(root, c + Vector3(10, 8, 2), lc, 1.8, 16)
	return {"spot": c + Vector3(0, 0, 2), "npc_spots": [c + Vector3(-6, 0, 4), c + Vector3(6, 0, -2.5), c + Vector3(9, 0, -2.5), Vector3(0, 0, 30)],
		"sign": Vector3(0, 9, 35.8), "amb": c + Vector3(0, 3, 0), "radius": 36.0}


func _build_skyscraper(root: Node3D, def: Dictionary) -> Dictionary:
	var glass := _mat("#1c2636", 0.0, 0.7, 0.1)
	var win := _mat(str(def["light"]), 1.6)
	var lc := Color(str(def["light"]))
	var c := Vector3(0, 0, 0)
	_hall(root, c, 28, 22, 8, glass, _mat("#d8d4cc", 0.0, 0.0, 0.2), 6.0, 4.5, true)
	var tiers := [[28.0, 8.5, 60.0], [24.0, 60.0, 110.0], [20.0, 110.0, 150.0], [15.0, 150.0, 190.0]]
	for t in tiers:
		var h: float = t[2] - t[1]
		_box(root, Vector3(t[0], h, t[0] * 0.8), Vector3(0, t[1] + h / 2, 0), glass)
		for k in int(h / 6.0): # lit window bands
			_box(root, Vector3(t[0] + 0.1, 0.6, t[0] * 0.8 + 0.1), Vector3(0, t[1] + 3 + k * 6.0, 0), win, false, 0.0, 0.0, 600.0)
	_cyl(root, 0.15, 0.4, 24, Vector3(0, 202, 0), _mat("#888888", 0.0, 0.8, 0.3), false) # antenna
	var beacon := _light(root, Vector3(0, 214, 0), Color("#ff2030"), 4.0, 30)
	beacon.distance_fade_enabled = false
	_box(root, Vector3(6, 1.1, 1.4), Vector3(0, 0.85, -4), _mat("#2a2a2a")) # security desk
	for i in 3: # server racks on the lobby's back wall
		_box(root, Vector3(2.0, 2.6, 1.0), Vector3(-8 + i * 2.6, 1.6, -9.6), _mat("#40ff80", 0.6))
	_light(root, Vector3(0, 6.5, 0), lc, 2.2, 18)
	return {"spot": Vector3(-5, 0, -7), "npc_spots": [Vector3(0, 0, -5.2), Vector3(6, 0, 3)], "sign": Vector3(0, 10, 11.6), "amb": Vector3(0, 3, 0), "radius": 16.0}


func _build_slum(root: Node3D, def: Dictionary) -> Dictionary:
	var brick := _mat("#4a3028")
	var board := _mat("#3b2d20")
	var lc := Color(str(def["light"]))
	for t in [[-22, -8, 12, 16], [-22, 12, 12, 13], [22, -10, 12, 18], [22, 10, 12, 12], [0, -22, 16, 15]]:
		_box(root, Vector3(t[2], t[3], 10), Vector3(t[0], t[3] / 2.0, t[1]), brick)
		for k in 3: # boarded windows
			_box(root, Vector3(1.6, 1.2, 0.2), Vector3(t[0] - 3 + k * 3, t[3] * 0.6, t[1] + 5.1), board, false)
	var c := Vector3(0, 0, -2)
	_hall(root, c, 14, 12, 8, brick, _mat("#2a2420"), 3.0, 3.0, true) # gang flat
	_box(root, Vector3(2, 0.8, 1), Vector3(-3, 0.7, c.z - 3), board)
	_box(root, Vector3(3, 0.5, 1.5), Vector3(3, 0.55, c.z - 4), _mat("#5a3030"))
	for p in [Vector3(-8, 0, 12), Vector3(7, 0, 14), Vector3(-2, 0, 20)]: # burning barrels
		_cyl(root, 0.4, 0.4, 1.0, p + Vector3(0, 0.5, 0), _mat("#3a2a1a"))
		_cyl(root, 0.35, 0.35, 0.1, p + Vector3(0, 1.05, 0), _mat("#ff8030", 4.0), false)
		_light(root, p + Vector3(0, 1.8, 0), lc, 2.5, 9)
	_light(root, c + Vector3(0, 6, 0), lc.darkened(0.3), 1.5, 10)
	return {"spot": Vector3(-2, 0, 15), "spot_turn": 0.0, "npc_spots": [Vector3(-6, 0, 13), Vector3(6, 0, 16), c + Vector3(2, 0, -2)],
		"sign": Vector3(0, 12, 6), "amb": Vector3(0, 2, 10), "radius": 30.0}


func _build_financial(root: Node3D, def: Dictionary) -> Dictionary:
	var marble := _mat("#d9d3c4", 0.0, 0.0, 0.35)
	var lc := Color(str(def["light"]))
	_kit(root, "kit_office_tower", Vector3(-24, 0, -18), 0.0, 2.2)
	_kit(root, "kit_office_tower", Vector3(24, 0, -16), PI / 2, 1.8)
	_kit(root, "kit_gothic_tower", Vector3(0, 0, -30), 0.0, 1.6)
	var c := Vector3(0, 0, 4)
	_hall(root, c, 30, 20, 11, marble, _mat("#8c7a5a", 0.0, 0.0, 0.3), 5.0, 5.0, true)
	for i in 6: # portico columns
		_cyl(root, 0.6, 0.6, 10, Vector3(-12.5 + i * 5.0, 5, c.z + 12), marble)
	_box(root, Vector3(32, 1.0, 4), Vector3(0, 10.5, c.z + 12), marble)
	_box(root, Vector3(10, 1.1, 1.2), Vector3(0, 0.85, c.z - 1), _mat("#5a4632")) # tellers
	_cyl(root, 2.0, 2.0, 0.4, Vector3(0, 2.5, c.z - 9.6), _mat("#b0a070", 0.0, 0.9, 0.3), false) # vault door
	_light(root, c + Vector3(-7, 9, 0), lc, 2.0, 16)
	_light(root, c + Vector3(7, 9, 0), lc, 2.0, 16)
	return {"spot": c + Vector3(-4, 0, -5), "npc_spots": [c + Vector3(3, 0, 6), c + Vector3(0, 0, -3), c + Vector3(-6, 0, 3)],
		"sign": Vector3(0, 13, c.z + 14.2), "amb": c + Vector3(0, 3, 0), "radius": 36.0}


func _build_docks(root: Node3D, def: Dictionary) -> Dictionary:
	var steel := _mat("#4a4f55", 0.0, 0.6, 0.5)
	var conc := _mat("#55524c")
	var lc := Color(str(def["light"]))
	var c := Vector3(0, 0, 6)
	_hall(root, c, 36, 22, 11, _mat("#5c4a3a"), conc, 6.0, 5.0, true, _mat(str(def["light"]), 1.2))
	for i in 3: # crates inside
		_box(root, Vector3(2.4, 2.4, 2.4), c + Vector3(-12 + i * 3, 1.2, -6), _mat("#6a5030"))
	_box(root, Vector3(4, 1, 2), c + Vector3(10, 0.8, -4), _mat("#2a2a2a")) # Viper's table
	for x in [-14.0, 14.0]:
		_light(root, c + Vector3(x, 9, 0), lc, 2.2, 16)
	# containers and two gantry cranes along the quay (site -Z = the water side)
	var cols := ["#8a2a20", "#204a7a", "#2a6a3a", "#a07a20"]
	for i in 8:
		_box(root, Vector3(2.5, 2.6, 6.1), Vector3(-20 + (i % 4) * 4.0, 1.3 + float(i / 4) * 2.6, -20), _mat(cols[i % 4]))
	for x in [-10.0, 16.0]:
		for z in [-24.0, -34.0]:
			_box(root, Vector3(1, 30, 1), Vector3(x, 15, z), steel)
		_box(root, Vector3(1.6, 1.6, 30), Vector3(x, 30.5, -36), steel)
		_box(root, Vector3(3, 3, 3), Vector3(x, 28, -40), _mat("#e0a020"))
	_box(root, Vector3(70, 1.2, 0.6), Vector3(0, 0.6, -45), conc) # quay edge kerb
	return {"spot": c + Vector3(10, 0, -1.5), "npc_spots": [c + Vector3(6, 0, 3), c + Vector3(-8, 0, 2), Vector3(-4, 0, -28)],
		"sign": Vector3(0, 13, c.z + 11.6), "amb": Vector3(0, 2, -15), "radius": 36.0}


func _build_cathedral(root: Node3D, def: Dictionary) -> Dictionary:
	var stone := _mat("#5d5850")
	var dark := _mat("#3a3631")
	var lc := Color(str(def["light"]))
	var c := Vector3(0, 0, -4)
	_hall(root, c, 20, 46, 18, stone, _mat("#4a443c"), 5.0, 7.0, false)
	_box(root, Vector3(22, 1, 48), Vector3(0, 18.5, c.z), dark) # roof deck
	_cyl(root, 0.0, 15.0, 12, Vector3(0, 25, c.z), dark, false, 4) # pitched roof (visual)
	for x in [-8.5, 8.5]: # twin spires on the front corners
		_box(root, Vector3(7, 34, 7), Vector3(x, 17, c.z + 22), stone)
		_cyl(root, 0.0, 4.8, 18, Vector3(x, 43, c.z + 22), dark, false, 4)
	_cyl(root, 3.2, 3.2, 0.2, Vector3(0, 13, c.z + 23.3), _mat("#ff9050", 2.5), false, 24).rotation.x = PI / 2 # rose window
	for row in 7: # pews
		for sx in [-1.0, 1.0]:
			_box(root, Vector3(6.0, 0.9, 0.7), Vector3(sx * 4.5, 0.75, c.z + 14 - row * 3.4), _mat("#4a3020"))
	_box(root, Vector3(6, 1.4, 2.5), Vector3(0, 1.0, c.z - 19), _mat("#d8d0c0")) # altar
	for z in [8.0, -6.0, -18.0]:
		_light(root, Vector3(0, 6, c.z + z), lc, 1.8, 14)
	return {"spot": Vector3(0, 0, c.z - 15), "npc_spots": [Vector3(-4.5, 0, c.z + 9), Vector3(5, 0, c.z + 2)],
		"sign": Vector3(0, 21.5, c.z + 27.5), "amb": Vector3(0, 6, c.z), "radius": 30.0, "flood": Vector3(0, 14, c.z + 18)}


func _build_theater(root: Node3D, def: Dictionary) -> Dictionary:
	var brick := _mat("#4a2224")
	var velvet := _mat("#6a0f1a")
	var lc := Color(str(def["light"]))
	var c := Vector3(0, 0, -4)
	_hall(root, c, 30, 34, 14, brick, _mat("#2a1a14"), 6.0, 4.5, true)
	for x in [-10.0, 10.0]: # facade pilasters either side of the doors
		_box(root, Vector3(10, 16, 1.5), Vector3(x, 8, c.z + 17.8), brick)
	_box(root, Vector3(14, 2.4, 3), Vector3(0, 6, c.z + 19.8), _mat("#202020")) # marquee
	var dead := Label3D.new()
	dead.text = "CR MSON THEA ER"
	dead.font_size = 72
	dead.modulate = Color("#ff4060")
	dead.pixel_size = 0.01
	dead.position = Vector3(0, 6, c.z + 21.35)
	root.add_child(dead)
	_box(root, Vector3(22, 1.2, 8), Vector3(0, 0.6, c.z - 12), _mat("#3a2414")) # stage
	_box(root, Vector3(24, 10, 0.4), Vector3(0, 6.2, c.z - 16.2), velvet) # curtain
	for row in 6:
		_box(root, Vector3(20, 0.9, 0.8), Vector3(0, 0.75, c.z + 2 + row * 2.2), velvet)
	_box(root, Vector3(30, 0.5, 6), Vector3(0, 5.5, c.z + 13.5), brick) # balcony
	var spot := _light(root, Vector3(0, 9, c.z - 9), lc, 3.0, 16)
	spot.light_energy = 3.0
	_light(root, Vector3(0, 8, c.z + 6), lc.darkened(0.5), 1.0, 14)
	return {"spot": Vector3(0, 1.2, c.z - 11), "npc_spots": [Vector3(-8, 0, c.z + 4), Vector3(9, 0, c.z - 6)],
		"sign": Vector3(0, 13, c.z + 19.2), "amb": Vector3(0, 4, c.z), "radius": 22.0}


func _build_chemical(root: Node3D, def: Dictionary) -> Dictionary:
	var steel := _mat("#6a7068", 0.0, 0.6, 0.4)
	var green := _mat(str(def["light"]), 2.5)
	var lc := Color(str(def["light"]))
	for i in 6:
		var p := Vector3(-24 + (i % 3) * 12.0, 0, -18 + float(i / 3) * -12.0)
		_cyl(root, 4.0, 4.0, 12, p + Vector3(0, 6, 0), steel)
		_box(root, Vector3(0.6, 0.6, 12), p + Vector3(0, 10, 7), steel, false) # pipes
	for x in [-20.0, 20.0]:
		_cyl(root, 1.4, 2.0, 32, Vector3(x, 16, 12), _mat("#4a4a46"))
	var c := Vector3(0, 0, 8)
	_hall(root, c, 26, 18, 10, _mat("#4a5048"), _mat("#30342e"), 5.0, 4.5, true, _mat(str(def["light"]), 1.4))
	for x in [-6.0, 0.0, 6.0]: # vats with glowing tops
		_cyl(root, 2.0, 2.0, 1.6, c + Vector3(x, 0.8, -4), steel)
		_cyl(root, 1.8, 1.8, 0.05, c + Vector3(x, 1.65, -4), green, false)
	_light(root, c + Vector3(0, 4, -4), lc, 3.0, 16)
	return {"spot": c + Vector3(-8, 0, 2), "npc_spots": [c + Vector3(4, 0, 1), c + Vector3(-3, 0, -0.5)],
		"sign": Vector3(0, 13, c.z + 9.6), "amb": c + Vector3(0, 2, 0), "radius": 34.0}


func _build_rustworks(root: Node3D, def: Dictionary) -> Dictionary:
	var rust := _mat("#5a3420", 0.0, 0.5, 0.7)
	var lc := Color(str(def["light"]))
	var c := Vector3(0, 0, 0)
	_hall(root, c, 40, 24, 16, rust, _mat("#2c2620"), 7.0, 7.0, true)
	for x in [-14.0, 0.0, 14.0]:
		_cyl(root, 1.8, 2.4, 40, Vector3(x, 20, -16), _mat("#3c2a20"))
	_box(root, Vector3(8, 6, 6), Vector3(-10, 3, -7), _mat("#2a2420")) # furnace
	_box(root, Vector3(4, 2, 0.4), Vector3(-10, 2.4, -3.8), _mat("#ff6020", 5.0), false)
	_light(root, Vector3(-10, 3, -2), lc, 4.0, 16)
	_light(root, Vector3(10, 12, 0), lc.darkened(0.4), 1.5, 18)
	for i in 4: # girders
		_box(root, Vector3(0.6, 0.6, 24), Vector3(-15 + i * 10.0, 13, 0), rust, false)
	for p in [Vector3(26, 0, 14), Vector3(-28, 0, 16)]: # slag heaps
		_cyl(root, 1.0, 8.0, 5, p + Vector3(0, 2.5, 0), _mat("#2a2420"), true, 8)
	return {"spot": Vector3(4, 0, -4), "npc_spots": [Vector3(-2, 0, 6), Vector3(10, 0, 4), Vector3(-6, 0, 9)],
		"sign": Vector3(0, 18, 12.6), "amb": Vector3(0, 4, 0), "radius": 34.0}


func _build_cityhall(root: Node3D, def: Dictionary) -> Dictionary:
	var stone := _mat("#cfc8b8", 0.0, 0.0, 0.5)
	var lc := Color(str(def["light"]))
	var c := Vector3(0, 0, -2)
	_hall(root, c, 36, 24, 14, stone, _mat("#6a5a48"), 5.0, 5.0, true, _mat(str(def["light"]), 1.2))
	for i in 8:
		_cyl(root, 0.7, 0.7, 13, Vector3(-14 + i * 4.0, 6.5, c.z + 15), stone)
	_box(root, Vector3(36, 1.4, 5), Vector3(0, 13.7, c.z + 15), stone)
	_box(root, Vector3(36, 0.5, 4), Vector3(0, 0.25, c.z + 15), stone) # steps
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 9.0
	sm.height = 9.0
	sm.is_hemisphere = true
	sm.material = _mat("#7a9a8a", 0.0, 0.6, 0.4)
	dome.mesh = sm
	dome.position = Vector3(0, 14.5, c.z)
	root.add_child(dome)
	for i in 7: # council desks in an arc
		var a := lerpf(-1.0, 1.0, i / 6.0)
		_box(root, Vector3(3, 1.1, 1.2), Vector3(sin(a) * 9.0, 0.85, c.z - 4 - cos(a) * 3.0 + 3.0), _mat("#4a3424"), true, a)
	_box(root, Vector3(5, 2.0, 1.6), Vector3(0, 1.3, c.z - 9), _mat("#3a2418")) # the bench
	_light(root, c + Vector3(0, 11, -2), lc, 2.4, 20)
	return {"spot": Vector3(0, 0, c.z - 7), "npc_spots": [Vector3(-5, 0, c.z + 16), Vector3(-7, 0, c.z - 1), Vector3(7, 0, c.z - 1)],
		"sign": Vector3(0, 17, c.z + 17.6), "amb": c + Vector3(0, 3, 0), "radius": 24.0}


func _build_plaza(root: Node3D, def: Dictionary) -> Dictionary:
	var obsidian := _mat("#121016", 0.0, 0.3, 0.15)
	var lc := Color(str(def["light"]))
	_box(root, Vector3(64, 0.2, 64), Vector3(0, 0.1, 0), obsidian)
	_box(root, Vector3(3, 14, 3), Vector3(0, 7.2, -4), _mat("#0a0a0e", 0.0, 0.5, 0.1)) # monolith
	_cyl(root, 7.0, 7.0, 0.8, Vector3(0, 0.6, -4), _mat("#222028"))
	_cyl(root, 6.6, 6.6, 0.1, Vector3(0, 1.0, -4), _mat("#304860", 0.6, 0.4, 0.05), false, 24)
	for s in [[Vector3(-26, 0, -14), 0.0], [Vector3(26, 0, -14), 0.0], [Vector3(-26, 0, 14), 0.0]]: # shops around the edge
		_hall(root, s[0], 10, 12, 6, _mat("#2a2630"), _mat("#3a3640"), 3.0, 3.0, true)
		_light(root, s[0] + Vector3(0, 4.5, 0), lc, 1.6, 9)
	for x in [-30.0, 30.0]: # giant screens
		_box(root, Vector3(1.0, 9, 16), Vector3(x, 14, -28), _mat("#a070ff", 1.8), false)
		_box(root, Vector3(1.2, 10, 1.2), Vector3(x, 5, -28), _mat("#222222"))
	for p in [Vector3(-14, 0, 14), Vector3(14, 0, 14), Vector3(-14, 0, -22), Vector3(14, 0, -22)]:
		_cyl(root, 0.12, 0.15, 5, p + Vector3(0, 2.5, 0), _mat("#222222"))
		_light(root, p + Vector3(0, 5.2, 0), lc, 2.0, 14)
	_kit(root, "kit_bench", Vector3(-8, 0, 6), 0.0)
	_kit(root, "kit_bench", Vector3(8, 0, 6), 0.0)
	return {"spot": Vector3(0, 0, 4.5), "npc_spots": [Vector3(-9, 0, 9), Vector3(10, 0, 2), Vector3(-26, 0, -14), Vector3(6, 0, 20)],
		"sign": Vector3(0, 21, -4), "amb": Vector3(0, 2, 0), "radius": 32.0}


func _build_casino(root: Node3D, def: Dictionary) -> Dictionary:
	var lc := Color(str(def["light"]))
	var plinth := _mat("#2c3a24")
	_sunken(root, 30, 26, 5.0, _mat("#3a1a10"), _mat("#5a1a20", 0.0, 0.0, 0.5), plinth)
	var gold := _mat("#c8a040", 0.0, 0.8, 0.3) # gilded frame over the stairwell
	for x in [8.6, 13.4]:
		_box(root, Vector3(0.5, 3.4, 0.5), Vector3(x, 6.7, -3.4), gold)
	_box(root, Vector3(5.4, 0.5, 0.8), Vector3(11, 8.6, -3.4), gold)
	for i in 4: # card tables
		_box(root, Vector3(3.2, 0.9, 1.8), Vector3(-9 + (i % 2) * 7.0, 0.75, -6 + float(i / 2) * 7.0), _mat("#1a5a2a"))
	for i in 6: # slot machines
		_box(root, Vector3(0.9, 1.8, 0.8), Vector3(-13.5, 1.05, -10 + i * 2.2), _mat("#ffd040", 1.6))
	_box(root, Vector3(8, 1.1, 1.2), Vector3(0, 0.85, -11.5), _mat("#3a2014")) # cage / bar
	_light(root, Vector3(-5, 3.6, -4), lc, 2.6, 14)
	_light(root, Vector3(5, 3.6, 4), lc, 2.6, 14)
	_box(root, Vector3(10, 1.6, 0.4), Vector3(0, 7.2, 13.2), _mat("#ffd040", 3.0), false)
	return {"spot": Vector3(2, 0.3, -7), "npc_spots": [Vector3(8, 0.3, -3), Vector3(-5, 0.3, 2), Vector3(-2, 0.3, -9)],
		"sign": Vector3(0, 9.5, 13.6), "amb": Vector3(0, 2, 0), "radius": 22.0}


func _build_cemetery(root: Node3D, def: Dictionary) -> Dictionary:
	var stone := _mat("#6a6c70")
	var iron := _mat("#1a1a1c", 0.0, 0.7, 0.5)
	var lc := Color(str(def["light"]))
	for s in [[Vector3(0, 1.2, -30), Vector3(60, 2.4, 0.2)], [Vector3(-30, 1.2, 0), Vector3(0.2, 2.4, 60)], [Vector3(30, 1.2, 0), Vector3(0.2, 2.4, 60)],
			[Vector3(-18, 1.2, 30), Vector3(24, 2.4, 0.2)], [Vector3(18, 1.2, 30), Vector3(24, 2.4, 0.2)]]:
		_box(root, s[1], s[0], iron)
	for i in 48: # headstones, some leaning
		var x := -24 + (i % 8) * 6.5 + _rng.randf_range(-0.8, 0.8)
		var z := 26 - float(i / 8) * 4.2
		if absf(x) < 5 or (z < 10 and z > -22 and x > 4):
			continue
		_box(root, Vector3(0.9, 1.3, 0.25), Vector3(x, 0.6, z), stone, true, _rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.2, 0.2))
	# mausoleum on a mound, crypt hall beneath it
	var crypt := Node3D.new()
	crypt.position = Vector3(14, 0, -10)
	root.add_child(crypt)
	_sunken(crypt, 14, 20, 4.4, _mat("#4a4a4c"), _mat("#2a2a2c"), _mat("#2e3328"))
	for i in 4:
		_cyl(crypt, 0.4, 0.4, 3.5, Vector3(-3 + i * 2.0, 6.15, 4), stone)
	_box(crypt, Vector3(9, 0.6, 6), Vector3(0, 8.2, 2), stone)
	for i in 3: # coffin niches
		_box(crypt, Vector3(1.0, 0.8, 2.2), Vector3(-4, 0.7, -6 + i * 3.0), _mat("#3a3028"))
	_light(crypt, Vector3(0, 3.2, -2), lc, 1.6, 10)
	for p in [Vector3(-20, 0, 20), Vector3(-6, 0, -20), Vector3(20, 0, 22)]:
		_kit(root, "kit_street_tree", p, _rng.randf() * TAU, 1.2)
	_light(root, Vector3(0, 4, 10), lc, 1.4, 22)
	return {"spot": Vector3(10, 0.3, -12), "npc_spots": [Vector3(-8, 0, 12)], "sign": Vector3(0, 5, 30.5), "amb": Vector3(0, 2, 0), "radius": 32.0}


func _build_subway(root: Node3D, def: Dictionary) -> Dictionary:
	var tile := _mat("#c8ccc4", 0.0, 0.0, 0.4)
	var lc := Color(str(def["light"]))
	_sunken(root, 40, 18, 5.0, tile, _mat("#5a5a58"), _mat("#3a3a3c"))
	_box(root, Vector3(40, 0.9, 7), Vector3(0, 0.45, 4.5), _mat("#7a7670")) # platform
	for x in [-1.0, 1.0]: # rails in the track bed
		_box(root, Vector3(40, 0.15, 0.12), Vector3(0, 0.38, -3 + x * 0.75), _mat("#6a6a6a", 0.0, 0.9, 0.3), false)
	_box(root, Vector3(18, 3.0, 2.8), Vector3(-6, 1.9, -3), _mat("#4a5a6a", 0.0, 0.6, 0.4)) # stalled train
	for i in 6:
		_box(root, Vector3(1.6, 0.9, 2.9), Vector3(-13 + i * 2.8, 2.4, -3), _mat("#e0e8ff", 1.6), false)
	var s := Label3D.new()
	s.text = "NIGHTFALL"
	s.font_size = 64
	s.pixel_size = 0.01
	s.modulate = Color("#ffffff")
	s.position = Vector3(0, 3.2, -8.7)
	root.add_child(s)
	for x in [-12.0, 0.0, 12.0]:
		_light(root, Vector3(x, 4.0, 2), lc, 1.6, 12)
	return {"spot": Vector3(-4, 0.9, 5), "npc_spots": [Vector3(6, 0.9, 5), Vector3(-12, 0.9, 6), Vector3(12, 0.9, 3.5)],
		"sign": Vector3(0, 9.2, 9.6), "amb": Vector3(0, 2, 0), "radius": 24.0}


func _build_museum(root: Node3D, def: Dictionary) -> Dictionary:
	var stone := _mat("#d4cab4", 0.0, 0.0, 0.5)
	var glass := _mat("#c8e8ff", 0.0, 0.2, 0.05, 0.25)
	var lc := Color(str(def["light"]))
	var c := Vector3(0, 0, -2)
	_hall(root, c, 36, 26, 12, stone, _mat("#6a5844", 0.0, 0.0, 0.3), 5.0, 5.0, true, _mat(str(def["light"]), 1.0))
	for i in 6:
		_cyl(root, 0.65, 0.65, 11, Vector3(-12.5 + i * 5.0, 5.5, c.z + 15), stone)
	_box(root, Vector3(32, 1.2, 4), Vector3(0, 11.6, c.z + 15), stone)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 8.0
	sm.height = 8.0
	sm.is_hemisphere = true
	sm.material = _mat("#a8a090", 0.0, 0.4, 0.4)
	dome.mesh = sm
	dome.position = Vector3(0, 12.5, c.z - 2)
	root.add_child(dome)
	for i in 6: # display cases
		var p := c + Vector3(-12 + (i % 3) * 12.0, 0, -6 + float(i / 3) * 9.0)
		_box(root, Vector3(1.6, 1.0, 1.6), p + Vector3(0, 0.5, 0), _mat("#3a3028"))
		_box(root, Vector3(1.5, 1.0, 1.5), p + Vector3(0, 1.5, 0), glass, false)
	# the Shattered Crown: a broken gold ring on a plinth, spotlit
	_box(root, Vector3(2, 1.4, 2), c + Vector3(0, 0.7, -8), _mat("#202020"))
	for i in 5:
		var a := i * TAU / 6.0
		_box(root, Vector3(0.35, 0.3, 0.12), c + Vector3(cos(a) * 0.45, 1.65, -8 + sin(a) * 0.45), _mat("#ffc840", 1.5, 0.9, 0.2), false, -a)
	_light(root, c + Vector3(0, 4, -8), Color("#fff0c0"), 3.0, 8)
	_light(root, c + Vector3(-9, 9, 2), lc, 1.6, 16)
	_light(root, c + Vector3(9, 9, 2), lc, 1.6, 16)
	return {"spot": c + Vector3(3, 0, -6), "npc_spots": [c + Vector3(-8, 0, 8), c + Vector3(-3, 0, -3)],
		"sign": Vector3(0, 14, c.z + 17.2), "amb": c + Vector3(0, 3, 0), "radius": 22.0}


func _build_pier(root: Node3D, def: Dictionary) -> Dictionary:
	var wood := _mat("#4a3828")
	var pink := _mat(str(def["light"]), 2.0)
	var lc := Color(str(def["light"]))
	_box(root, Vector3(30, 0.6, 120), Vector3(0, 1.2, -40), wood) # deck: from the shore out over the harbour
	_ramp(root, 0, 26, 0.0, 20, 1.5, 12.0, wood)
	# the dead Ferris wheel: a ring of spokes and cars
	var wheel := Node3D.new()
	wheel.position = Vector3(0, 18, -90)
	wheel.rotation.y = PI / 2
	root.add_child(wheel)
	for i in 16:
		var a := i * TAU / 16.0
		_box(wheel, Vector3(0.4, 14, 0.4), Vector3(cos(a) * 7, sin(a) * 7, 0), _mat("#c8c0c8", 0.0, 0.5, 0.5), false, 0.0, a + PI / 2)
		_box(wheel, Vector3(1.6, 1.6, 1.6), Vector3(cos(a) * 14, sin(a) * 14 - 1.0, 0), _mat(["#ff70d0", "#70d0ff", "#ffe070"][i % 3]), false)
	_box(root, Vector3(1, 18, 1), Vector3(-3, 9.5, -90), wood)
	_box(root, Vector3(1, 18, 1), Vector3(3, 9.5, -90), wood)
	var c := Vector3(0, 1.5, -40) # funhouse
	_hall(root, c, 18, 14, 8, _mat("#6a2a5a"), wood, 3.5, 3.5, true)
	for i in 4: # mirrors
		_box(root, Vector3(2.0, 2.6, 0.15), c + Vector3(-6 + i * 4.0, 1.5, -6.6), _mat("#d8e8f0", 0.2, 1.0, 0.02), false)
	_light(root, c + Vector3(0, 6, 0), lc, 2.4, 12)
	for i in 4: # stalls
		var p := Vector3(-10 + (i % 2) * 20.0, 1.5, -10 - float(i / 2) * 12.0)
		_box(root, Vector3(4, 2.6, 3), p + Vector3(0, 1.3, 0), _mat(["#8a2a40", "#2a4a8a"][i % 2]))
		_box(root, Vector3(4.4, 0.3, 3.6), p + Vector3(0, 3.0, 0), pink, false)
	for z in range(-80, 10, 12): # string lights
		_light(root, Vector3(0, 6, z), lc, 0.9, 10)
	return {"spot": Vector3(0, 1.5, -24), "npc_spots": [c + Vector3(3, 0, 2), Vector3(8, 1.5, 0)], "sign": Vector3(0, 9, 18), "amb": Vector3(0, 3, -40), "radius": 26.0, "flood": Vector3(0, 10, -60)}


func _build_university(root: Node3D, def: Dictionary) -> Dictionary:
	var stone := _mat("#6a5e4e")
	var lc := Color(str(def["light"]))
	var win := _mat(str(def["light"]), 1.4)
	for s in [[Vector3(-24, 0, -6), Vector3(14, 14, 30)], [Vector3(36, 0, -6), Vector3(12, 12, 30)], [Vector3(4, 0, -28), Vector3(40, 16, 12)]]:
		_box(root, s[1], s[0] + Vector3(0, s[1].y / 2, 0), stone)
		_box(root, s[1] + Vector3(0.2, -s[1].y + 1.2, 0.2), s[0] + Vector3(0, s[1].y * 0.6, 0), win, false, 0.0, 0.0, 260.0)
	_box(root, Vector3(6, 30, 6), Vector3(-24, 15, 14), stone) # clock tower
	_cyl(root, 0.0, 4.2, 10, Vector3(-24, 35, 14), _mat("#3a3631"), false, 4)
	_cyl(root, 1.8, 1.8, 0.2, Vector3(-24, 24, 17.1), _mat("#fff0c0", 2.0), false, 24).rotation.x = PI / 2
	# the lecture hall (enterable) with Paradox's laboratory partitioned at the back
	var c := Vector3(10, 0, 8)
	_hall(root, c, 24, 18, 10, stone, _mat("#4a3a2a"), 4.0, 4.0, true, win)
	for row in 4: # tiered benches
		_box(root, Vector3(9, 0.4 + row * 0.45, 1.2), c + Vector3(-7, 0.2 + row * 0.225, 5 - row * 1.6), _mat("#5a4030"))
	_box(root, Vector3(0.3, 4.0, 10), c + Vector3(-2, 2.0, -4), stone) # lab partition
	_box(root, Vector3(5, 1.0, 1.4), c + Vector3(5, 0.8, -6), _mat("#d0d8d8", 0.0, 0.3, 0.3)) # lab bench
	for i in 3:
		_cyl(root, 0.15, 0.15, 0.5, c + Vector3(3.5 + i * 1.2, 1.55, -6), _mat("#60c0ff", 1.5), false)
	_box(root, Vector3(6, 3, 0.2), c + Vector3(-8, 2.5, -8.6), _mat("#1a2a1a")) # blackboard
	_light(root, c + Vector3(-6, 8, 2), lc, 2.0, 14)
	_light(root, c + Vector3(6, 6, -5), Color("#d8f0ff"), 2.2, 10)
	_kit(root, "kit_bench", Vector3(-6, 0, 20), PI)
	return {"spot": c + Vector3(4, 0, -4.2), "spot_turn": 0.0, "npc_spots": [c + Vector3(-8, 0, -5), Vector3(-6, 0, 18), Vector3(-2, 0, 22)],
		"sign": Vector3(c.x, 12, c.z + 9.6), "amb": c + Vector3(0, 3, 0), "radius": 34.0}


func _build_hotel(root: Node3D, def: Dictionary) -> Dictionary:
	var facade := _mat("#5a4a3c")
	var lc := Color(str(def["light"]))
	var c := Vector3(0, 0, 4)
	_hall(root, c, 26, 20, 8, facade, _mat("#e8dcc8", 0.0, 0.0, 0.2), 5.0, 4.0, true)
	for t in [[26.0, 8.5, 50.0], [20.0, 50.0, 70.0]]:
		var h: float = t[2] - t[1]
		_box(root, Vector3(t[0], h, 18), Vector3(0, t[1] + h / 2, c.z - 1), facade)
		for k in int(h / 3.5):
			_box(root, Vector3(t[0] + 0.1, 0.9, 18.1), Vector3(0, t[1] + 2 + k * 3.5, c.z - 1), _mat("#ffc890", 1.3), false, 0.0, 0.0, 500.0)
	var ch := MeshInstance3D.new() # chandelier
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 1.4
	sm.material = _mat("#fff0c0", 3.0)
	ch.mesh = sm
	ch.position = c + Vector3(0, 6.2, 0)
	root.add_child(ch)
	_box(root, Vector3(8, 1.1, 1.2), c + Vector3(-6, 0.85, -7), _mat("#3a1e10")) # the bar
	_box(root, Vector3(3, 0.8, 3), c + Vector3(6, 0.55, -3), _mat("#6a1a20")) # lounge seats
	_light(root, c + Vector3(0, 5.5, 0), lc, 2.6, 18)
	var neon := Label3D.new()
	neon.text = "THE MERIDIAN"
	neon.font_size = 80
	neon.pixel_size = 0.012
	neon.modulate = Color("#ffc890")
	neon.position = Vector3(0, 9.6, c.z + 10.4)
	root.add_child(neon)
	return {"spot": c + Vector3(-3, 0, -5), "npc_spots": [c + Vector3(-2, 0, 7), c + Vector3(5, 0, -1), c + Vector3(-8, 0, -4.5)],
		"sign": Vector3(0, 75, c.z + 8), "amb": c + Vector3(0, 3, 0), "radius": 16.0}


# ---------------- ambience ----------------
## A synthesized 6 s loop per recipe, played from the site through a positional player on the Ambience bus.
func _ambience(root: Node3D, recipe: String, at: Vector3) -> void:
	if recipe == "":
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = ambience_loop(recipe)
	p.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
	p.unit_size = 10.0
	p.max_distance = 75.0
	p.volume_db = -4.0
	p.position = at
	p.autoplay = true
	root.add_child(p)


static func ambience_loop(recipe: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(recipe)
	var n := 6 * AMB_RATE
	var buf := PackedFloat32Array()
	buf.resize(n)
	# [noise level, noise low-pass Hz, swell rate Hz] then drones [[hz, amp], ...]
	var spec := {
		"asylum": [0.10, 1200.0, 0.0, [[60.0, 0.05], [120.0, 0.04], [240.0, 0.015]]],
		"prison": [0.14, 900.0, 0.0, [[50.0, 0.04], [100.0, 0.02]]],
		"lobby": [0.05, 1600.0, 0.0, [[110.0, 0.02], [220.0, 0.01]]],
		"street": [0.20, 1800.0, 0.0, [[70.0, 0.02]]],
		"docks": [0.30, 700.0, 0.17, [[45.0, 0.03]]],
		"cathedral": [0.05, 900.0, 0.0, [[130.81, 0.05], [196.0, 0.04], [261.63, 0.03], [329.63, 0.02]]],
		"theater": [0.06, 800.0, 0.0, [[55.0, 0.02]]],
		"chemical": [0.12, 1400.0, 0.0, [[90.0, 0.04], [180.0, 0.02]]],
		"rustworks": [0.18, 600.0, 0.0, [[38.0, 0.06], [76.0, 0.03]]],
		"plaza": [0.16, 1100.0, 0.33, [[100.0, 0.01]]],
		"casino": [0.10, 1300.0, 0.0, [[60.0, 0.02]]],
		"cemetery": [0.22, 500.0, 0.11, []],
		"subway": [0.10, 900.0, 0.0, [[48.0, 0.05], [96.0, 0.02]]],
		"museum": [0.04, 1000.0, 0.0, [[80.0, 0.015]]],
		"pier": [0.26, 650.0, 0.17, [[220.0, 0.0]]],
		"university": [0.08, 1200.0, 0.0, [[90.0, 0.015]]],
	}
	var s: Array = spec.get(recipe, spec["street"])
	var k := 1.0 - exp(-TAU * float(s[1]) / AMB_RATE)
	var y := 0.0
	for i in n:
		var t := float(i) / AMB_RATE
		y += k * (rng.randf() * 2.0 - 1.0 - y)
		var swell := 1.0 if float(s[2]) == 0.0 else 0.55 + 0.45 * sin(TAU * float(s[2]) * t)
		var v := y * float(s[0]) * 3.0 * swell
		for dr in s[3]:
			v += sin(TAU * float(dr[0]) * t) * float(dr[1]) * (0.8 + 0.2 * sin(TAU * 0.25 * t))
		buf[i] = v
	# events: chimes, clanks, drips, tune notes (all start and end inside the loop)
	var events: Array = []
	match recipe:
		"casino":
			for e in 10:
				events.append([rng.randf() * 5.5, [1318.5, 1568.0, 2093.0][e % 3], 0.25, 0.06, "sine"])
		"rustworks", "prison":
			for e in 4:
				events.append([rng.randf() * 5.5, 180.0 + rng.randf() * 300.0, 0.4, 0.12, "clank"])
		"subway", "chemical":
			for e in 6:
				events.append([rng.randf() * 5.7, 900.0 + rng.randf() * 900.0, 0.08, 0.05, "sine"])
		"theater":
			var notes := [523.25, 659.25, 587.33, 493.88, 523.25, 392.0]
			for e in notes.size():
				events.append([0.3 + e * 0.9, notes[e], 0.7, 0.05, "sine"])
		"pier":
			var tune := [392.0, 523.25, 493.88, 440.0, 392.0, 349.23, 392.0]
			for e in tune.size():
				events.append([0.2 + e * 0.8, tune[e], 0.5, 0.04, "square"])
		"university":
			for e in 6:
				events.append([e * 1.0, 2400.0, 0.03, 0.05, "sine"])
		"asylum":
			for e in 2:
				events.append([1.0 + e * 3.0, 700.0, 0.6, 0.02, "sine"])
	for ev in events:
		var start := int(float(ev[0]) * AMB_RATE)
		var len := int(float(ev[2]) * AMB_RATE)
		for j in len:
			var idx := start + j
			if idx >= n:
				break
			var tt := float(j) / AMB_RATE
			var env := exp(-tt * 6.0 / float(ev[2]))
			var w := 0.0
			match str(ev[4]):
				"sine":
					w = sin(TAU * float(ev[1]) * tt)
				"square":
					w = signf(sin(TAU * float(ev[1]) * tt)) * 0.6
				"clank":
					w = sin(TAU * float(ev[1]) * tt) * 0.6 + sin(TAU * float(ev[1]) * 2.76 * tt) * 0.4 + (rng.randf() - 0.5) * 0.3
			buf[idx] += w * env * float(ev[3])
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		# 50 ms crossfade into the loop start so the seam doesn't click
		var v := buf[i]
		var fade := int(0.05 * AMB_RATE)
		if i >= n - fade:
			var a := float(i - (n - fade)) / fade
			v = v * (1.0 - a) + buf[i - (n - fade)] * a
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = AMB_RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w
