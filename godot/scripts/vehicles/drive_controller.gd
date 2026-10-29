class_name DriveController
extends Node
## Summoning, entering, driving and exiting the CR vehicles (Godot port).
##  On foot: V calls the quick-select vehicle (loadout / inventory); E near it gets in.
##  Driving: W/S throttle-brake-reverse, A/D steer (jet: roll), Space handbrake (jet VTOL: up), C (VTOL: down),
##  Shift boost, mouse free-look (jet: pitch/yaw), B mode, V first-person/chase camera, E or F exit when slow,
##  X (CR-X1 only): eject the CR-B1 from the nose bay and ride away on it at road speed.
## First person is the default; the hero rides on seat_attach and is hidden in first person.

signal notify(text: String, icon: String, kind: String)
signal sound(id: String)

## the Specter (28.7 m wingspan) doesn't fit the 22 m avenues: it lands on the open plaza north of the
## Citadel entrance instead of in front of the Knight
const JET_PAD := Vector3(0, 0, -150)

var player: Player
var cam: FollowCamera
var audio: CKAudio
var effects: Effects
var driving: Vehicle
var vehicles := {} # id -> Vehicle (one of each, re-summoning moves it)
var _enter_time := 0.0
var _player_layers := Vector2i(1, 1)
var _ejecting := false


func _ready() -> void:
	name = "Drive"


func label(v: Vehicle) -> String:
	return v.cfg["label"]


## Call a vehicle: spawns it (or moves the existing one) in front of the Knight on the ground.
func summon(id: String, underground: bool) -> void:
	if underground:
		notify.emit("No sky access in the Red Citadel. Take the elevator up first", "interceptor", "warn")
		sound.emit("ui.deny")
		return
	var v: Vehicle = vehicles.get(id)
	if v == null:
		v = Vehicle.create(id)
		get_parent().add_child(v)
		v.set_engine_stream(audio.engine_loop(v.cfg["engine_hz"], v.cfg["engine_noise"]))
		vehicles[id] = v
		v._fx = effects
		v.crashed.connect(func(s, at):
			if effects:
				effects.burst("sparks", at, int(4 + s * 12), 3.0 + s * 4.0, 0.4, 0.4)
				effects.burst("debris", at, int(s * 8), 2.5, 0.4, 0.7)
			sound.emit("explosion" if s > 0.6 else "weapon.impact")
			if v.damage > 0.75 and v == driving:
				notify.emit("%s heavily damaged: %d%% hull" % [label(v), roundi((1.0 - v.damage) * 100)], "interceptor", "warn"))
	player.act("CK_Summon")
	sound.emit("vehicle.summon")
	if v.kind == "jet":
		# the Specter comes in dark: stealth mode, from high above and behind the camera, and sets down on the
		# nearest flat rooftop the Knight can see (a short grapple away), or on the street beside him
		var roof := find_landing_roof(player.global_position)
		var spot: Vector3 = roof if roof != Vector3.INF else _street_spot()
		var back := Vector3(sin(cam.yaw), 0, cos(cam.yaw)) # behind the camera
		v.place(player.global_position + back * 160.0 + Vector3(0, 90, 0), atan2(-back.x, -back.z))
		v.set_mode("stealth", true)
		v.land_at = spot
		var face := player.global_position - spot
		v.land_heading = atan2(face.x, face.z) if Vector2(face.x, face.z).length() > 1.0 else cam.yaw
		v.vtol_up = 0.0
		if not v.arrived.is_connected(_on_arrived):
			v.arrived.connect(_on_arrived.bind(v))
		var where := "on the rooftop %d m away (grapple up)" % roundi(spot.distance_to(player.global_position)) if roof != Vector3.INF else "beside you"
		notify.emit("%s inbound in stealth: landing %s" % [label(v), where], "specter", "info")
		return
	# car / bike: start out of sight two blocks back along the Knight's own avenue and drive up the lane to him
	# (no teleporting next to him, no tight turns)
	var p := player.global_position
	var S := District.SPACING
	var lane: float = District.LANES[0]
	var ax := roundf(p.x / S) * S
	var az := roundf(p.z / S) * S
	var on_ns := absf(p.x - ax) < absf(p.z - az) # standing on a north-south avenue
	var lim := District.GRID * S - 10.0
	var sgn := 1.0 if randf() < 0.5 else -1.0
	var along := (p.z if on_ns else p.x) + sgn * 2.0 * S
	if absf(along) > lim:
		sgn = -sgn
		along = (p.z if on_ns else p.x) + sgn * 2.0 * S
	var dir := Vector3(0, 0, -sgn) if on_ns else Vector3(-sgn, 0, 0) # toward the Knight
	var right := dir.cross(Vector3.UP) * -1.0
	var start := (Vector3(ax, 0, along) if on_ns else Vector3(along, 0, az)) + right * lane
	start.y = _ground(start) + 0.4
	v.place(start, atan2(dir.x, dir.z))
	var stop := (Vector3(ax, 0, p.z) if on_ns else Vector3(p.x, 0, az)) + right * lane
	v.route = [stop]
	if not v.arrived.is_connected(_on_arrived):
		v.arrived.connect(_on_arrived.bind(v))
	notify.emit("%s on its way (%d m)" % [label(v), roundi(start.distance_to(p))], "interceptor", "info")


func _on_arrived(v: Vehicle) -> void:
	notify.emit("%s has arrived" % label(v), "interceptor", "info")
	sound.emit("vehicle.summon")


## Nearest flat rooftop (room for the Specter: a 13 m square within 0.6 m of level) that the Knight can see,
## 16-90 m away and at least 6 m up. Ring raycasts against the real collision geometry; Vector3.INF if none.
func find_landing_roof(from: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var eye := from + Vector3(0, 1.7, 0)
	var best := Vector3.INF
	var best_score := 1e9
	for r in [16.0, 26.0, 38.0, 52.0, 70.0, 90.0]:
		for k in 20:
			var a := TAU * k / 20.0
			var c: Vector3 = from + Vector3(sin(a), 0, cos(a)) * r
			var top := _roof_height(space, c)
			if top == -INF or top - from.y < 6.0:
				continue
			var flat := true
			for o in [Vector3(6.5, 0, 0), Vector3(-6.5, 0, 0), Vector3(0, 0, 6.5), Vector3(0, 0, -6.5), Vector3(4.6, 0, 4.6), Vector3(-4.6, 0, -4.6)]:
				if absf(_roof_height(space, c + o) - top) > 0.6:
					flat = false
					break
			if not flat:
				continue
			var spot := Vector3(c.x, top, c.z)
			# line of sight from the Knight's eyes to just above the roof edge he would look at
			var q := PhysicsRayQueryParameters3D.create(eye, spot + Vector3(0, 1.5, 0))
			q.collision_mask = 1
			q.exclude = [player.get_rid()]
			if not space.intersect_ray(q).is_empty():
				continue
			var score: float = r + (top - from.y) * 0.4 # nearest first; lower roofs slightly preferred (easier to reach)
			if score < best_score:
				best_score = score
				best = spot
		if best != Vector3.INF:
			break # the nearest ring with a usable roof wins
	return best


static func _roof_height(space: PhysicsDirectSpaceState3D, at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 160, at.z), Vector3(at.x, -5, at.z))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit["normal"].y < 0.95 or hit["collider"] is RigidBody3D or hit["collider"] is VehicleBody3D:
		return -INF
	return hit["position"].y


## Open street beside the Knight (no roof found): the middle of his avenue, a few metres ahead.
func _street_spot() -> Vector3:
	var p := player.global_position
	var S := District.SPACING
	var ax := roundf(p.x / S) * S
	var az := roundf(p.z / S) * S
	var spot := Vector3(ax, 0, p.z + 14.0) if absf(p.x - ax) < absf(p.z - az) else Vector3(p.x + 14.0, 0, az)
	spot.y = _ground(spot)
	return spot


## CR-B1 wall grapple: fire at the building ahead (within 45 m); the Cycle drives to the wall, winches up the
## face on its cable and rolls over the edge onto the roof.
func _bike_grapple(v: Vehicle) -> void:
	var space := player.get_world_3d().direct_space_state
	var fwd := v.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	# first wall ahead that has a roof at least 3 m up (skips bus shelters, cabinets and other street props)
	var from := v.global_position + Vector3(0, 1.0, 0)
	var end := from + fwd * 45.0
	var wall := Vector3.INF
	var n := Vector3.ZERO
	var top := -INF
	for attempt in 5:
		var q := PhysicsRayQueryParameters3D.create(from, end)
		q.collision_mask = 1
		q.exclude = [v.get_rid(), player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var hn: Vector3 = hit["normal"]
		hn.y = 0
		if hn.length() < 0.5:
			from = hit["position"] + fwd * 0.3
			continue
		hn = hn.normalized()
		var t := _roof_height(space, hit["position"] - hn * 2.5)
		if t != -INF and t - v.global_position.y >= 3.0:
			wall = hit["position"]
			n = hn
			top = t
			break
		from = hit["position"] + fwd * 0.6
	if wall == Vector3.INF:
		notify.emit("No building to climb ahead: face a wall within 45 m", "grapple", "warn")
		sound.emit("ui.deny")
		return
	if top - v.global_position.y > 150.0:
		notify.emit("Too tall to winch up", "grapple", "warn")
		sound.emit("ui.deny")
		return
	var base := Vector3(wall.x, v.global_position.y, wall.z) + n * 1.6
	var roof := Vector3(wall.x, top, wall.z) - n * 3.5
	v.winch(base, Vector3(wall.x, top, wall.z) + n * 0.9, roof, atan2(-n.x, -n.z))
	sound.emit("gadget.throw")
	notify.emit("%s: winching up the wall" % label(v), "grapple", "info")


func _land_jet(v: Vehicle) -> void:
	while is_instance_valid(v) and v.global_position.y > JET_PAD.y + 0.6 and not v.driver_in:
		await get_tree().physics_frame
	if is_instance_valid(v):
		v.vtol_up = 0.0
		notify.emit("%s has landed" % label(v), "specter", "info")


func _ground(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 30, 0), at + Vector3(0, -30, 0))
	q.exclude = [player.get_rid()]
	for v in vehicles.values():
		q.exclude.append(v.get_rid())
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"].y if hit else at.y


## The vehicle the Knight can get into from here, or null.
func nearby() -> Vehicle:
	for v in vehicles.values():
		var reach := 4.5 if v.kind == "jet" else 3.0
		if player.global_position.distance_to(v.anchor("entry_anchor_L")) < reach or \
				player.global_position.distance_to(v.global_position) < (6.0 if v.kind == "jet" else 3.2):
			return v
	return null


## Riding posture per vehicle: [clip, pitch (deg, + = forward), pivot height (m above the seat, the hips),
## offset along the seat (m: x right, y up, z forward)]. The Cycle is ridden prone like a Batpod; the
## Interceptor's driver lies back in a reclined cockpit. Other vehicles sit upright (CK_Drive).
const RIDER := {
	"crb1_batcycle": ["CK_RideProne", 72.0, 0.55, Vector3(0, -0.3, 0.0)],
	"crx1_interceptor": ["CK_DriveRecline", -38.0, 0.55, Vector3(0, -0.22, -0.15)],
}


func rider_clip(v: Vehicle) -> String:
	var r: Array = RIDER.get(v.id, [])
	return r[0] if not r.is_empty() and player.hero.has_clip(r[0]) else "CK_Drive"


## Seat-relative transform for the hero: pitched about the hips so the pose reads as lying, not standing.
func rider_transform(v: Vehicle) -> Transform3D:
	var r: Array = RIDER.get(v.id, [])
	if r.is_empty() or not player.hero.has_clip(r[0]):
		return Transform3D()
	var pivot := Vector3(0, r[2], 0)
	var rot := Basis(Vector3.RIGHT, deg_to_rad(r[1]))
	return Transform3D(Basis(), r[3] + pivot) * Transform3D(rot, Vector3.ZERO) * Transform3D(Basis(), -pivot)


func enter(v: Vehicle, quick := false) -> void:
	driving = v
	v.driver_in = true
	if player.collision_layer != 0: # an eject hands over car -> bike with the body already disabled
		_player_layers = Vector2i(player.collision_layer, player.collision_mask)
	player.collision_layer = 0
	player.collision_mask = 0
	player.frozen = true
	player.velocity = Vector3.ZERO
	player.vel = Vector3.ZERO
	var hero := player.hero
	hero.reparent(v.seat(), false)
	hero.transform = Transform3D()
	hero.set_lod(0)
	if quick:
		hero.transform = rider_transform(v)
	hero.play(rider_clip(v) if quick else "CK_VehicleEnter", 0.1, 1.0, true)
	_enter_time = 0.0 if quick else 0.9
	if not quick:
		v.play_door(true)
		get_tree().create_timer(1.1).timeout.connect(func(): if driving == v: v.play_door(false))
		sound.emit("vehicle.door")
	cam.active = false
	_apply_camera()
	notify.emit("%s · %s mode. W/S drive, B mode, V camera, E exit" % [label(v), v.mode.capitalize()], "interceptor", "info")


func exit() -> void:
	var v := driving
	if v == null:
		return
	if absf(v.speed()) > 5.0:
		notify.emit("Slow down to get out", "interceptor", "warn")
		return
	driving = null
	v.driver_in = false
	v.throttle = 0
	v.steer_in = 0
	v.handbrake = false
	v.vtol_up = 0
	var hero := player.hero
	hero.reparent(player, false)
	hero.transform = Transform3D()
	hero.visible = true
	var out := v.anchor("exit_anchor_L")
	out.y = _ground(out) + 0.05
	player.collision_layer = _player_layers.x
	player.collision_mask = _player_layers.y
	player.frozen = false
	player.teleport(out)
	player.heading = v.rotation.y
	hero.play("CK_VehicleExit", 0.1, 1.0, true)
	v.play_door(true)
	get_tree().create_timer(1.0).timeout.connect(func(): if driving != v: v.play_door(false))
	sound.emit("vehicle.door")
	cam.active = true
	cam.yaw = v.rotation.y + PI
	cam.snap()
	cam.camera.make_current()


## CR-X1 bike launch (vehicle-modes CRX1_BikeEject): nose petals open (0-18), the sled runs forward with the
## CR-B1 on bike_launch_anchor (18-34), drops it to the road (34-46); then the bike is released and the
## Knight is on it. The car keeps rolling and closes its bay.
func eject() -> void:
	var car := driving
	if car == null or car.id != "crx1_interceptor" or _ejecting:
		return
	var clip: String = car.cfg.get("eject_clip", "")
	var anchor := car.model.find_child("bike_launch_anchor", true, true) as Node3D
	if anchor == null or car.anim == null or not car.anim.has_animation(clip):
		notify.emit("This CR-X1 model has no bike launch bay", "batcycle", "warn")
		return
	_ejecting = true
	var bike: Vehicle = vehicles.get("crb1_batcycle")
	if bike == null:
		bike = Vehicle.create("crb1_batcycle")
		get_parent().add_child(bike)
		bike.set_engine_stream(audio.engine_loop(bike.cfg["engine_hz"], bike.cfg["engine_noise"]))
		vehicles["crb1_batcycle"] = bike
	bike.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	bike.freeze = true
	bike.collision_layer = 0
	bike.collision_mask = 0
	bike.reparent(anchor, false)
	bike.transform = Transform3D()
	car.anim.play(clip)
	sound.emit("vehicle.mode")
	notify.emit("CR-B1 launch", "batcycle", "info")
	await get_tree().create_timer(car.anim.get_animation(clip).length).timeout
	var xf := bike.global_transform
	var vel := car.linear_velocity + car.global_basis.z * 3.0
	bike.reparent(get_parent(), false)
	bike.global_transform = Transform3D(Basis(Vector3.UP, car.rotation.y), xf.origin + Vector3(0, 0.15, 0))
	bike.collision_layer = 1
	bike.collision_mask = 1
	bike.freeze = false
	bike.linear_velocity = vel
	bike.reset_physics_interpolation()
	# swap the driver: the car coasts on, the Knight rides the bike out of the bay
	car.driver_in = false
	car.throttle = 0
	car.steer_in = 0
	var first: String = car.view
	driving = null
	bike.view = first
	enter(bike, true)
	get_tree().create_timer(1.2).timeout.connect(func(): car.anim.play_backwards(clip))
	_ejecting = false


func _apply_camera() -> void:
	driving.active_camera().make_current()
	player.hero.visible = not driving.first_person


## Per frame while driving. look = this frame's mouse/stick delta (radians).
func drive(dt: float, look: Vector2) -> void:
	var v := driving
	var m: Vector2 = CKInput.move()
	v.throttle = m.y
	v.steer_in = -m.x # +steering turns left in VehicleBody3D
	v.handbrake = Input.is_action_pressed("jump") and v.kind != "jet"
	v.vtol_up = (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	v.boost = Input.is_action_pressed("sprint")
	v.look = look
	if Input.is_action_just_pressed("vehicleMode"):
		v.cycle_mode()
		sound.emit("vehicle.mode")
		notify.emit("%s: %s mode" % [label(v), v.mode.capitalize()], "interceptor", "info")
	if Input.is_action_just_pressed("summonMenu"):
		v.view = Vehicle.VIEWS[(Vehicle.VIEWS.find(v.view) + 1) % Vehicle.VIEWS.size()]
		_apply_camera()
		notify.emit("Camera: %s" % v.view.capitalize(), "interceptor", "info")
	if Input.is_action_just_pressed("eject"):
		eject()
	if Input.is_action_just_pressed("grapple") and v.kind == "bike" and v.mode in ["pursuit", "stealth"] and not v.winching():
		_bike_grapple(v)
	if _enter_time > 0:
		_enter_time -= dt
		if _enter_time <= 0:
			player.hero.play(rider_clip(driving), 0.3)
			var tw := player.hero.create_tween()
			tw.tween_property(player.hero, "transform", rider_transform(driving), 0.35).set_trans(Tween.TRANS_SINE)
	elif Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("vehicleExit"):
		exit()
		return
	# the Knight's (frozen) body rides along so lights, NPC culling and the map follow the vehicle
	player.global_position = v.global_position
	player.heading = v.rotation.y


## HUD line while driving: "CR-X1 Interceptor" / "Pursuit · 87 km/h · first person".
func hud_text() -> Array:
	var v := driving
	var extra := ""
	if v.kind == "jet":
		extra = " · alt %d m" % roundi(v.global_position.y)
	return [label(v), "%s · %d km/h%s · %s" % [v.mode.capitalize(), roundi(absf(v.speed()) * 3.6), extra,
		v.view + " cam"]] + ([] if v.kind == "jet" else ["Hull %d%%" % roundi((1.0 - v.damage) * 100)])
