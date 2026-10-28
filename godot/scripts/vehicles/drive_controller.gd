class_name DriveController
extends Node
## Summoning, entering, driving and exiting the CR vehicles (Godot port).
##  On foot: V calls the quick-select vehicle (loadout / inventory); E near it gets in.
##  Driving: W/S throttle-brake-reverse, A/D steer (jet: roll), Space handbrake (jet VTOL: up), C (VTOL: down),
##  Shift boost, mouse free-look (jet: pitch/yaw), B mode, V first-person/chase camera, E or F exit when slow.
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
	var fwd := Vector3(sin(player.heading), 0, cos(player.heading))
	var at := player.global_position + fwd * 7.0
	var heading := player.heading + PI / 2 # side-on, so the left door faces the Knight
	if v.kind == "jet":
		at = JET_PAD
		heading = PI
	at.y = _ground(at) + 0.3
	v.place(at, heading)
	player.act("CK_Summon")
	sound.emit("vehicle.summon")
	notify.emit("%s %s" % [label(v), "landing on the north plaza" if v.kind == "jet" else "arrived"], "interceptor", "info")


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


func enter(v: Vehicle) -> void:
	driving = v
	v.driver_in = true
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
	hero.play("CK_VehicleEnter", 0.1, 1.0, true)
	_enter_time = 0.9
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
