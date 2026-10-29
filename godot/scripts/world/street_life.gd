class_name StreetLife
extends Node3D
## Ambient traffic and pedestrians (Godot port, open-world feel). Both are pools that recycle around the
## Knight, so the cost stays flat however big the grid is.
##  - Traffic: CARS kinematic cars on right-hand lanes (1.6 m off each avenue's centre), turning at
##    crossings, braking for anything ahead (ray probe), shunted aside and stalled when rammed by a
##    CR vehicle. Recycled to a lane 90-170 m away when they fall out of range.
##  - Pedestrians: WALKERS civilians strolling the sidewalks (5.5 m off centre), cowering when a fight or
##    gunfire is close (Director.noise hooks in via panic()).

const CARS := 14
const WALKERS := 18
const CAR_SPEED := 11.0
const LANE := 1.6
const WALK_OFF := 5.4
const CIVILIANS := ["npc_civilian_a", "npc_civilian_b", "npc_office_worker", "npc_scientist", "npc_mechanic", "npc_construction_worker"]

var player: Node3D
var district: District
var drive: DriveController
var cars: Array = [] # {body, dir: Vector3, speed, stall}
var walkers: Array = [] # {root, anim, dir, cower, pending}
var _car_info: Dictionary


func build() -> void:
	name = "StreetLife"
	_car_info = district.proto("car_prop_v01")
	for i in CARS:
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		var b: AABB = _car_info["bounds"]
		for m in _car_info["meshes"]:
			var mi := MeshInstance3D.new()
			mi.mesh = m["mesh"]
			mi.transform = m["xf"]
			body.add_child(mi)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b.size
		cs.shape = box
		cs.position = b.get_center()
		body.add_child(cs)
		add_child(body)
		var c := {"body": body, "dir": Vector3.RIGHT, "speed": CAR_SPEED, "stall": 0.0, "half": b.size}
		cars.append(c)
		_place_car(c, 40.0, 170.0)
	for i in WALKERS:
		var root: Node3D = load(CKData.model_path(CIVILIANS[i % CIVILIANS.size()])).instantiate()
		add_child(root)
		for col in root.find_children("*", "CollisionObject3D", true, false):
			col.queue_free()
		var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
		if ap:
			ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var w := {"root": root, "anim": ap, "dir": Vector3.RIGHT, "cower": 0.0, "pending": 0.0}
		walkers.append(w)
		_place_walker(w, 10.0, 90.0)


## A random lane point min..max m from the Knight. Returns [position, direction].
func _lane_point(min_d: float, max_d: float, offset: float) -> Array:
	var p := player.global_position
	var lim := District.GRID * District.SPACING - 8.0
	for i in 16:
		var along_x := randf() < 0.5
		var k := roundi((p.z if along_x else p.x) / District.SPACING + randi_range(-1, 1))
		k = clampi(k, -District.GRID, District.GRID)
		var c := k * District.SPACING
		var sign := 1.0 if randf() < 0.5 else -1.0
		var a := clampf((p.x if along_x else p.z) + randf_range(-max_d, max_d), -lim, lim)
		if absf(a - roundf(a / District.SPACING) * District.SPACING) < 12.0:
			continue # not in a crossing
		var dir := Vector3(sign, 0, 0) if along_x else Vector3(0, 0, sign)
		# right-hand side: the lane/sidewalk to the right of the travel direction
		var right := dir.cross(Vector3.UP) * -1.0
		var at := (Vector3(a, 0, c) if along_x else Vector3(c, 0, a)) + right * offset
		var d := at.distance_to(p)
		if d >= min_d and d <= max_d and Vector2(at.x, at.z).distance_to(District.SQUARE) > District.SQUARE_RADIUS:
			return [at, dir]
	return [p + Vector3(max_d, 0, 0), Vector3.RIGHT]


func _place_car(c: Dictionary, min_d: float, max_d: float) -> void:
	var lp := _lane_point(min_d, max_d, LANE)
	c["dir"] = lp[1]
	c["speed"] = CAR_SPEED * randf_range(0.8, 1.15)
	c["stall"] = 0.0
	var body: AnimatableBody3D = c["body"]
	body.global_transform = Transform3D(Basis(Vector3.UP, atan2(lp[1].x, lp[1].z) - PI / 2), lp[0])
	body.reset_physics_interpolation()
	# the next crossing ahead along the travel direction
	var d: Vector3 = lp[1]
	var a2: float = lp[0].x if absf(d.x) > 0.5 else lp[0].z
	var sg := signf(d.x + d.z)
	c["cc"] = (ceilf(a2 / District.SPACING) if sg > 0 else floorf(a2 / District.SPACING)) * District.SPACING


func _place_walker(w: Dictionary, min_d: float, max_d: float) -> void:
	var lp := _lane_point(min_d, max_d, WALK_OFF)
	w["dir"] = lp[1]
	w["cower"] = 0.0
	var root: Node3D = w["root"]
	root.global_position = lp[0] + Vector3(0, 0.15, 0)
	root.rotation.y = atan2(lp[1].x, lp[1].z) # NPC models face +Z
	if w["anim"] and w["anim"].has_animation("NPC_Walk"):
		w["anim"].play("NPC_Walk")
		w["anim"].seek(randf(), true)


## Gunfire / fights near `at`: pedestrians within `radius` cower for a while.
func panic(at: Vector3, radius: float) -> void:
	for w in walkers:
		if w["root"].global_position.distance_to(at) < radius:
			w["cower"] = 6.0
			if w["anim"] and w["anim"].has_animation("NPC_Cower"):
				w["anim"].play("NPC_Cower", 0.2)


func update(dt: float) -> void:
	var p := player.global_position
	var space := get_world_3d().direct_space_state
	for c in cars:
		var body: AnimatableBody3D = c["body"]
		var pos := body.global_position
		if pos.distance_to(p) > 190.0:
			_place_car(c, 90.0, 170.0)
			continue
		# rammed by a CR vehicle: shunt and stall
		for v in drive.vehicles.values():
			if v.global_position.distance_to(pos) < 3.6 and absf(v.speed()) > 6.0:
				var push: Vector3 = (pos - v.global_position).normalized()
				push.y = 0
				body.global_position += push * 1.2
				body.rotate_y(randf_range(-0.6, 0.6))
				c["stall"] = 6.0
				get_parent().effects.burst("sparks", pos + Vector3(0, 0.8, 0), 8, 3.0, 0.4, 0.3)
				get_parent().audio.play("weapon.impact")
		if c["stall"] > 0:
			c["stall"] -= dt
			if c["stall"] <= 0:
				_place_car(c, 90.0, 170.0)
			continue
		var dir: Vector3 = c["dir"]
		# brake for anything ahead
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.7, 0) + dir * 2.6, pos + Vector3(0, 0.7, 0) + dir * 12.0)
		q.exclude = [body.get_rid()]
		var blocked := not space.intersect_ray(q).is_empty()
		var want: float = 0.0 if blocked else c["speed"]
		c["cur"] = move_toward(c.get("cur", want), want, dt * (14.0 if blocked else 4.0))
		var next: Vector3 = pos + dir * c["cur"] * dt
		# crossings: at the centre of the next crossing go straight (55 %), left or right; the grid edge forces a turn
		var on_x := absf(dir.x) > 0.5
		var sgn := signf(dir.x + dir.z)
		var along: float = next.x if on_x else next.z
		if sgn * (along - c["cc"]) >= 0.0:
			var edge := absf(c["cc"]) >= District.GRID * District.SPACING - 1.0
			var r := randf()
			if r < 0.55 and not edge:
				c["cc"] += sgn * District.SPACING
			else:
				var street := roundf((next.z if on_x else next.x) / District.SPACING) * District.SPACING
				var centre := Vector3(c["cc"], 0, street) if on_x else Vector3(street, 0, c["cc"])
				var ndir := dir.cross(Vector3.UP) * (1.0 if r < 0.775 else -1.0)
				var nalong := centre.z if on_x else centre.x # position along the new axis
				var nsgn := signf(ndir.x + ndir.z)
				if absf(nalong + nsgn * District.SPACING) > District.GRID * District.SPACING + 1.0:
					ndir = -ndir # don't drive off the grid
					nsgn = -nsgn
				dir = ndir.normalized()
				c["dir"] = dir
				next = centre + dir.cross(Vector3.UP) * -LANE
				c["cc"] = nalong + nsgn * District.SPACING
		body.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) - PI / 2), next)
	for w in walkers:
		var root: Node3D = w["root"]
		var pos := root.global_position
		var d := pos.distance_to(p)
		if d > 110.0:
			_place_walker(w, 40.0, 100.0)
			continue
		root.visible = d < 90.0
		if w["cower"] > 0:
			w["cower"] -= dt
			if w["cower"] <= 0 and w["anim"]:
				w["anim"].play("NPC_Walk", 0.3)
		else:
			var dir: Vector3 = w["dir"]
			var next := pos + dir * 1.35 * dt
			var along := next.x if absf(dir.x) > 0.5 else next.z
			if absf(along - roundf(along / District.SPACING) * District.SPACING) < 9.0 or absf(along) > District.GRID * District.SPACING - 6:
				w["dir"] = -dir # turn back at the corner
				root.rotation.y = atan2(-dir.x, -dir.z)
			else:
				root.global_position = next
		var ap: AnimationPlayer = w["anim"]
		if ap and d < 60.0:
			w["pending"] += dt
			if d < 20.0 or w["pending"] > 0.1:
				ap.advance(w["pending"])
				w["pending"] = 0.0
