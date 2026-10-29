class_name Player
extends CharacterBody3D
## Third-person player (port of actors/player.ts): CharacterBody3D at a fixed 60 Hz driving the CR-X9
## clip state machine. Movement is camera-relative; the body turns to face travel, except while aiming
## the grapnel, where it faces away from the camera and strafes. Body origin = feet.

signal landed(vy: float, hard: bool, feet: Vector3)

const JUMP_DELAY := 0.12 # JumpStart plays at 2x; impulse lands near its push-off key
const ONE_SHOT_LOCK := {"CK_LandHard": 0.75, "CK_GadgetDraw": 0.45, "CK_GadgetStow": 0.45, "CK_Summon": 1.4, "CK_Interact": 0.7}

var P: Dictionary
var gravity: float
var hero: Hero
var mode := "ground" # ground | air | glide | action | grapple
var heading := 0.0 # radians, 0 = facing +Z
var speed := 0.0
var can_exert := true
var cam_yaw := PI
var glide_held := false
var status := ""
var crouched := false
var aiming := false
## seconds of "weapon up" after a shot: arm raised in the aim pose, facing the crosshair (no RMB needed)
var combat_t := 0.0
var walk_mode := false
var gadget := ""
var vel := Vector3.ZERO
var _grounded := true
var _lock_time := 0.0
var _jump_timer := -1.0
var _coyote := 0.0
var _land_time := 0.0
var _grapple_point = null
var _grapple_time := 0.0
## Freeze locomotion (animation debug / benchmark camera).
var frozen := false


func _ready() -> void:
	P = CKData.json("physics")["player"]
	gravity = CKData.json("physics")["gravity"][1]
	var shape := CapsuleShape3D.new()
	shape.radius = P["radius"]
	shape.height = P["height"]
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = P["height"] / 2.0
	add_child(col)
	collision_mask = 3 # world (1) + enemies (2)
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.35
	safe_margin = 0.02
	hero = Hero.new()
	hero.name = "Hero"
	add_child(hero)
	hero.clip_finished.connect(_on_clip_finished)


func handle_input() -> void:
	if Input.is_action_just_pressed("walkToggle"):
		walk_mode = not walk_mode
	if Input.is_action_just_pressed("crouch") and mode == "ground":
		crouched = not crouched
	aiming = (Input.is_action_pressed("grapple") or Input.is_action_pressed("secondaryAction")) and mode == "ground"
	if mode != "ground":
		return
	if Input.is_action_just_pressed("jump") and _jump_timer < 0:
		crouched = false
		_jump_timer = JUMP_DELAY
		hero.play("CK_JumpStart", 0.08, 2.0, true)
	elif Input.is_action_just_pressed("interact"):
		_one_shot("CK_Interact")


## Equip animation when the hotbar selection changes (selection never uses the item).
func set_gadget(id: String) -> bool:
	if id == gadget:
		return false
	var was := gadget
	gadget = id
	if mode != "ground":
		return false
	_one_shot("CK_GadgetDraw" if id != "" else "CK_GadgetStow" if was != "" else "CK_Idle")
	return true


## One-shot action clip (equipment use, vehicle call). Only on the ground.
func act(clip: String, lock := -1.0) -> bool:
	if mode != "ground":
		return false
	_one_shot(clip, lock)
	return true


func grapple_to(point: Vector3) -> void:
	_grapple_point = point
	_grapple_time = 0.0
	mode = "grapple"
	crouched = false
	_jump_timer = -1.0
	hero.play("CK_GrapplePull", 0.12, 1.0, true)


func grapple_anchor():
	return _grapple_point if mode == "grapple" else null


func sprinting() -> bool:
	return mode == "ground" and speed > P["runSpeed"] + 0.5


func _one_shot(name: String, lock := -1.0) -> void:
	mode = "action"
	_lock_time = lock if lock >= 0 else ONE_SHOT_LOCK.get(name, 0.5)
	hero.play(name, 0.15, 1.0, true)


func _on_clip_finished(name: String) -> void:
	if mode == "action" and name != "CK_GadgetDraw":
		_lock_time = minf(_lock_time, 0.0)


func _physics_process(dt: float) -> void:
	if frozen:
		return
	var wish: Vector2 = CKInput.move()
	var moving := wish.length_squared() > 0.01
	# camera looks toward -Z at yaw 0: forward = (-sin yaw, -cos yaw) in XZ
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)
	var dir := fwd * wish.y + right * wish.x

	var target := 0.0
	if mode == "ground" and moving:
		if crouched:
			target = 1.4
		elif aiming or walk_mode:
			target = P["walkSpeed"]
		elif Input.is_action_pressed("sprint") and can_exert:
			target = P["sprintSpeed"]
		else:
			target = P["runSpeed"]
		target *= minf(1.0, wish.length())
	if mode == "glide":
		target = 9.0
	if mode == "air":
		target = Vector2(vel.x, vel.z).length()

	if mode == "ground" or mode == "glide" or (mode == "air" and moving):
		var accel := 14.0 if mode == "ground" else 3.0
		var desired := Vector3.ZERO
		if moving:
			desired = dir.normalized() * target
		elif mode == "glide":
			desired = Vector3(sin(heading), 0, cos(heading)) * target
		vel.x += (desired.x - vel.x) * minf(1.0, accel * dt)
		vel.z += (desired.z - vel.z) * minf(1.0, accel * dt)
	elif mode == "action":
		vel.x *= 0.8
		vel.z *= 0.8

	# facing
	if aiming or (combat_t > 0.0 and mode == "ground"):
		heading = cam_yaw + PI
	elif Vector2(vel.x, vel.z).length() > 0.3 and mode != "action":
		var want := atan2(vel.x, vel.z)
		heading += wrapf(want - heading, -PI, PI) * minf(1.0, (12.0 if mode == "ground" else 4.0) * dt)

	# jump / gravity / grapple / glide
	if _jump_timer >= 0:
		_jump_timer -= dt
		if _jump_timer < 0:
			vel.y = P["jumpImpulse"]
			mode = "air"
			_grounded = false
			hero.play("CK_Airborne", 0.25)
	vel.y += gravity * dt
	if mode == "grapple" and _grapple_point != null:
		var to: Vector3 = _grapple_point - global_position
		_grapple_time += dt
		if to.length() < 1.6 or _grapple_time > 3.0:
			mode = "air"
			vel *= 0.5
			vel.y = maxf(vel.y, 4.0)
			hero.play("CK_Airborne", 0.2)
		else:
			vel = to.normalized() * 20.0
			if Vector2(vel.x, vel.z).length() > 0.5:
				heading = atan2(vel.x, vel.z)
	if mode == "air" and glide_held and vel.y < -2 and can_exert:
		mode = "glide"
	if mode == "glide":
		if not glide_held or not can_exert:
			mode = "air"
		else:
			vel.y = maxf(vel.y, -P["glideFallSpeed"])

	# snapping would cancel a jump on its first frames, so only snap while not rising
	floor_snap_length = 0.0 if vel.y > 0 else 0.35
	velocity = vel
	move_and_slide()
	var vy_before := vel.y
	vel = Vector3(velocity.x, vel.y, velocity.z) if mode != "grapple" else vel
	if is_on_ceiling() and vel.y > 0:
		vel.y = 0
	_grounded = is_on_floor()
	if _grounded:
		_coyote = 0.0
		if vy_before <= 0:
			if mode in ["air", "glide", "grapple"]:
				_land(vy_before)
			vel.y = -0.5
	elif mode == "ground" and _jump_timer < 0:
		# walked off a ledge: short grace period before switching to the air state
		_coyote += dt
		if _coyote > 0.2:
			mode = "air"
			hero.play("CK_Airborne", 0.3)
	if global_position.y < -260:
		respawn() # below the Red Citadel (y -120) = out of the world

	if mode == "action":
		_lock_time -= dt
		if _lock_time <= 0:
			mode = "ground"
	speed = Vector2(vel.x, vel.z).length()


func _land(vy: float) -> void:
	var hard: bool = vy < -P["hardLandingSpeed"]
	landed.emit(vy, hard, global_position)
	if hard:
		_one_shot("CK_LandHard")
		vel.x = 0
		vel.z = 0
	else:
		mode = "ground"
		hero.play("CK_LandSoft", 0.08, 1.0, true)
		_land_time = 0.3


func respawn(at := Vector3(0, 3, 0)) -> void:
	teleport(at)


## Move the feet to a point and drop into the air state.
func teleport(feet: Vector3) -> void:
	global_position = feet
	reset_physics_interpolation()
	vel = Vector3.ZERO
	velocity = Vector3.ZERO
	mode = "air"
	_grapple_point = null
	hero.play("CK_Airborne", 0.2)


## Per frame: choose the locomotion clip + rate and orient the visual.
func _process(dt: float) -> void:
	if frozen:
		return
	_land_time -= dt
	combat_t = maxf(0.0, combat_t - dt)
	if mode == "ground" and _jump_timer < 0 and not (_land_time > 0 and speed < 0.5):
		var s := speed
		var clip: String
		if crouched:
			clip = "CK_CrouchIdle" if s < 0.2 else "CK_CrouchWalk"
		elif aiming or combat_t > 0.0:
			clip = "CK_GrappleAim" if s < 0.2 else _strafe_clip()
		elif s < 0.2:
			clip = "CK_Idle"
		elif s < 2.8:
			clip = "CK_Walk"
		elif s < 7.6:
			clip = "CK_Run"
		else:
			clip = "CK_Sprint"
		hero.play(clip, 0.25)
		hero.set_time_scale(hero.rate_for(clip, maxf(s, 0.3)) * (-1.0 if _backpedal() else 1.0))
	elif mode == "glide":
		hero.play("CK_Glide", 0.35)
	hero.rotation.y = heading
	# glide: pitch the whole body toward horizontal flight
	var pitch := 0.9 if mode == "glide" else 0.0
	hero.rotation.x += (pitch - hero.rotation.x) * minf(1.0, 5.0 * dt)
	status = "%s%s%s%s | %s | %.1f m/s" % [mode, " crouch" if crouched else "", " aim" if aiming else "",
		" walk" if walk_mode else "", hero.current, speed]


## Velocity in the character's frame: x = left, y = forward.
func _local_vel() -> Vector2:
	var c := cos(heading)
	var s := sin(heading)
	return Vector2(vel.x * c - vel.z * s, vel.x * s + vel.z * c)


func _strafe_clip() -> String:
	var v := _local_vel()
	if absf(v.x) > absf(v.y):
		return "CK_StrafeLeft" if v.x > 0 else "CK_StrafeRight"
	return "CK_Walk"


func _backpedal() -> bool:
	return aiming and hero.current == "CK_Walk" and _local_vel().y < -0.2
