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
	player.act("CK_Summon")
	sound.emit("vehicle.summon")
	if v.kind == "jet":
		# the Specter flies in: it starts high above Citadel Square and settles onto the pad in VTOL
		v.place(JET_PAD + Vector3(0, 70, 0), PI)
		if v.mode != "vtol":
			v.set_mode("vtol", true)
		v.vtol_up = -1.0
		notify.emit("%s inbound: landing on Citadel Square (north plaza)" % label(v), "specter", "info")
		_land_jet(v)
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
	hero.play("CK_Drive" if quick else "CK_VehicleEnter", 0.1, 1.0, true)
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
	var first := car.first_person
	driving = null
	bike.first_person = first
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
		v.first_person = not v.first_person
		_apply_camera()
	if Input.is_action_just_pressed("eject"):
		eject()
	if _enter_time > 0:
		_enter_time -= dt
		if _enter_time <= 0:
			player.hero.play("CK_Drive", 0.3)
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
		"first person" if v.first_person else "chase cam"]]
