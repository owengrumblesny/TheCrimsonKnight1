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
## world point the head turns toward (set by the game: nearby threat, grapple point), or null = look ahead
var look_point = null
## sprint + C: a knee slide that carries momentum under low obstacles (the capsule shrinks while sliding)
var _slide_t := 0.0
var _shape: CapsuleShape3D
var _col: CollisionShape3D
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
## the main camera (grapple targeting looks along it)
var camera: Camera3D
## best grapple point under the crosshair this frame: {point, ledge (bool), normal} or {}
var grapple_target := {}
var _boosted := false
# glide flight model
var _glide_speed := 0.0
var _glide_pitch := 0.0
# ledge hang / climb
var _ledge_top := Vector3.ZERO # point on the ledge edge (top surface)
var _ledge_normal := Vector3.ZERO # wall normal, pointing out toward the Knight
var _climb_t := 0.0
var _climb_from := Vector3.ZERO
var _vault_t := 0.0
var _regrab_t := 0.0
## melee: a short dash toward a target while a strike / dodge one-shot plays
var _lunge_t := 0.0
var _lunge_vel := Vector3.ZERO
## set by the game while hand-to-hand is engaged: C dodges instead of crouching, RMB strikes instead of aiming
var melee_engaged := false
# character feel (Hero.feel / Hero.update_lean): smoothed acceleration and turn rate
var _feel_speed := 0.0
var _feel_heading := 0.0
var _feel_accel := 0.0
var _feel_turn := 0.0
var _look_strength := 0.0 # set by _look_point: 1 for a real point of interest, less for the camera direction

const GRAPPLE_RANGE := 70.0
const GRAPPLE_MAX_SPEED := 30.0
const GRAPPLE_ACCEL := 38.0
const GLIDE_MIN := 7.0
const GLIDE_MAX := 40.0
const HANG_DROP := 2.05 # feet below the ledge top while hanging


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
	_shape = shape
	_col = col
	collision_mask = 19 # world (1) + enemies (2) + sidewalks (16: vehicles roll over the curb)
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
	if Input.is_action_just_pressed("crouch") and mode == "ground" and not melee_engaged and sprinting():
		_start_slide()
	elif Input.is_action_just_pressed("crouch") and mode == "ground" and not melee_engaged:
		crouched = not crouched
	aiming = Input.is_action_pressed("secondaryAction") and mode == "ground" and not melee_engaged
	if Input.is_action_just_pressed("grapple") and not grapple_target.is_empty() and mode in ["ground", "air", "glide", "ledge"]:
		grapple_to(grapple_target["point"], grapple_target["ledge"], grapple_target.get("normal", Vector3.ZERO))
		return
	match mode:
		"grapple":
			if Input.is_action_just_pressed("crouch"):
				_end_grapple(false) # cancel: let go and fall / glide
			elif Input.is_action_just_pressed("jump") and _grapple_point != null and global_position.distance_to(_grapple_point) < 14.0:
				_end_grapple(true) # grapple boost: launch over the edge
			return
		"ledge":
			if Input.is_action_just_pressed("jump") or Input.is_action_pressed("moveForward"):
				_start_climb()
			elif Input.is_action_just_pressed("crouch") or Input.is_action_pressed("moveBack"):
				mode = "air"
				_regrab_t = 0.6
				vel = _ledge_normal * 1.5
				hero.play("CK_Airborne", 0.2)
			return
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
	if mode != "ground" and mode != "action":
		return false
	_one_shot(clip, lock)
	return true


## Fire the grapnel at a world point. ledge = the point is a rooftop edge (the reel ends in a climb-up or,
## with Space near the top, a boost launch); normal = the wall's outward normal there.
func grapple_to(point: Vector3, ledge := false, normal := Vector3.ZERO) -> void:
	_grapple_point = point
	_grapple_time = 0.0
	_grapple_ledge = ledge
	_ledge_normal = normal
	_boosted = false
	mode = "grapple"
	crouched = false
	_jump_timer = -1.0
	heading = atan2(point.x - global_position.x, point.z - global_position.z)
	hero.play("CK_GrapplePull", 0.12, 1.0, true)


var _grapple_ledge := false


## Leave the reel. boost = the grapnel's motor flings the Knight up and over the edge into the air.
func _end_grapple(boost: bool) -> void:
	mode = "air"
	if boost:
		_boosted = true
		var flat := Vector3(vel.x, 0, vel.z).normalized() if Vector2(vel.x, vel.z).length() > 1 else Vector3(sin(heading), 0, cos(heading))
		vel = flat * 14.0 + Vector3.UP * 15.0
		_regrab_t = 0.8
	else:
		vel *= 0.6
	hero.play("CK_Airborne", 0.2)


## Grapple targeting: a rooftop edge (or any high surface) along the camera ray, within range and above
## the Knight. Walls are traced up to their roof line so the grapnel bites the edge.
func find_grapple_target() -> Dictionary:
	if camera == null:
		return {}
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * (GRAPPLE_RANGE + 10.0))
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	if p.distance_to(global_position) > GRAPPLE_RANGE or p.y < global_position.y + 2.0:
		return {}
	if n.y > 0.7:
		return {"point": p, "ledge": false, "normal": Vector3.ZERO} # a rooftop: land on it
	# a wall: find the roof line above the hit point (probe down from above, just inside the wall)
	var inside := p - Vector3(n.x, 0, n.z).normalized() * 0.4
	var dq := PhysicsRayQueryParameters3D.create(inside + Vector3.UP * 45.0, inside + Vector3.DOWN * 0.5)
	dq.collision_mask = 1
	var top := space.intersect_ray(dq)
	if top.is_empty() or top["normal"].y < 0.7:
		return {}
	var edge: Vector3 = top["position"]
	if edge.y - global_position.y > 60.0:
		return {}
	var wall_n := Vector3(n.x, 0, n.z).normalized()
	return {"point": Vector3(p.x, edge.y, p.z) + wall_n * 0.35, "ledge": true, "normal": wall_n}


## Dash at `v` (m/s, horizontal) for `t` seconds, through normal collision (melee lunges and dodges).
func lunge(v: Vector3, t: float) -> void:
	_lunge_vel = Vector3(v.x, 0, v.z)
	_lunge_t = t


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

	if mode == "slide":
		_slide_t -= dt
		var flat := Vector2(vel.x, vel.z)
		var spd := maxf(0.0, flat.length() - 9.0 * dt) # sliding friction
		if flat.length() > 0.01:
			flat = flat.normalized() * spd
		vel.x = flat.x
		vel.z = flat.y
		if (_slide_t <= 0.0 or spd < 3.0) and not _low_ceiling():
			_end_slide()
	elif mode == "ground" or mode == "glide" or (mode == "air" and moving):
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
	if _lunge_t > 0.0:
		_lunge_t -= dt
		vel.x = _lunge_vel.x
		vel.z = _lunge_vel.z

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
	_regrab_t -= dt
	if mode == "grapple" and _grapple_point != null:
		# reel: the line pulls with a strong but finite force; the Knight keeps his momentum (swings a little
		# when he was moving sideways) and accelerates up to the motor's top speed
		var to: Vector3 = _grapple_point - (global_position + Vector3.UP * (1.0 if _grapple_ledge else 0.0))
		_grapple_time += dt
		var d := to.length()
		var pull := to.normalized() * GRAPPLE_ACCEL
		vel += pull * dt
		vel.y += -gravity * dt * 0.85 # line tension carries most of his weight
		if vel.length() > GRAPPLE_MAX_SPEED:
			vel = vel.normalized() * GRAPPLE_MAX_SPEED
		# damp sideways drift so he converges on the anchor
		var along := to.normalized() * vel.dot(to.normalized())
		vel = along + (vel - along) * maxf(0.0, 1.0 - 3.0 * dt)
		if Vector2(vel.x, vel.z).length() > 0.5:
			heading = lerp_angle(heading, atan2(vel.x, vel.z), minf(1.0, 8.0 * dt))
		if d < 1.8 or _grapple_time > 4.0:
			if _grapple_ledge and _grapple_time <= 4.0:
				# arrive at the edge: hang for a beat, then climb straight up (Space during the reel boosts instead)
				_grab_ledge(_grapple_point - _ledge_normal * 0.35, _ledge_normal)
				_start_climb()
			else:
				_end_grapple(false)
	if mode == "air" and glide_held and vel.y < -2 and can_exert:
		mode = "glide"
		_glide_speed = maxf(GLIDE_MIN + 3.0, Vector2(vel.x, vel.z).length())
		_glide_pitch = -0.15
	if mode == "glide":
		if not glide_held or not can_exert:
			mode = "air"
		else:
			_glide(dt, wish)
	if mode == "air" and _regrab_t <= 0.0 and vel.y < 2.0:
		_try_ledge_grab()
	if mode == "ground" and Vector2(vel.x, vel.z).length() > P["runSpeed"] - 1.0 and moving and _vault_t <= 0.0:
		_try_vault()
	_vault_t -= dt
	if mode == "ledge":
		vel = Vector3.ZERO
		# shimmy along the ledge
		var tangent := _ledge_normal.cross(Vector3.UP)
		var side: float = wish.x if absf(wish.x) > 0.3 else 0.0
		if side != 0.0:
			var step := tangent * -side * 1.2 * dt
			if _ledge_continues(_ledge_top + step * 6.0):
				global_position += step
				_ledge_top += step
		heading = atan2(-_ledge_normal.x, -_ledge_normal.z)
		return
	if mode == "climb":
		_climb(dt)
		return

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
			if mode in ["air", "glide", "grapple", "vault"]:
				_land(vy_before)
			vel.y = -0.5
	elif mode in ["ground", "slide"] and _jump_timer < 0:
		# walked off a ledge: short grace period before switching to the air state
		_coyote += dt
		if _coyote > 0.2:
			if mode == "slide":
				_set_height(P["height"])
			mode = "air"
			hero.play("CK_Airborne", 0.3)
	if global_position.y < -260:
		respawn() # below the Red Citadel (y -120) = out of the world

	if mode == "action":
		_lock_time -= dt
		if _lock_time <= 0:
			mode = "ground"
	speed = Vector2(vel.x, vel.z).length()


## Glide flight model: W dives (trades height for speed), S pulls up (trades speed for height), A/D bank.
## Below GLIDE_MIN the cape stalls and the nose drops. Speed-dependent turning; air drag caps the dive.
func _glide(dt: float, wish: Vector2) -> void:
	var want_pitch := -0.15 - wish.y * 0.5 # W (wish.y +1) -> -0.65 dive, S -> +0.35 pull-up
	if _glide_speed < GLIDE_MIN:
		want_pitch = -0.7 # stall: nose drops until airspeed returns
	_glide_pitch = lerpf(_glide_pitch, want_pitch, minf(1.0, dt * 2.5))
	var g := -gravity
	_glide_speed += (-g * sin(_glide_pitch) - 0.0016 * _glide_speed * _glide_speed * 9.0 - 0.6) * dt
	_glide_speed = clampf(_glide_speed, 3.0, GLIDE_MAX)
	heading -= wish.x * (0.5 + _glide_speed * 0.035) * dt
	var fwd := Vector3(sin(heading), 0, cos(heading))
	# lift keeps the sink rate low at speed; slow gliding sinks faster
	var sink := lerpf(4.5, 1.6, clampf((_glide_speed - GLIDE_MIN) / 15.0, 0.0, 1.0))
	var target := fwd * _glide_speed * cos(_glide_pitch)
	target.y = _glide_speed * sin(_glide_pitch) - sink
	vel = vel.lerp(target, minf(1.0, dt * 4.0))


## A ledge in reach while falling or jumping: wall ahead at chest height, open space above it, a top surface
## within reach of the hands.
func _try_ledge_grab() -> void:
	var space := get_world_3d().direct_space_state
	var fwd := Vector3(sin(heading), 0, cos(heading))
	if Vector2(vel.x, vel.z).length() > 0.5:
		fwd = Vector3(vel.x, 0, vel.z).normalized()
	var chest := global_position + Vector3.UP * 1.4
	var q := PhysicsRayQueryParameters3D.create(chest, chest + fwd * 0.9)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var wall := space.intersect_ray(q)
	if wall.is_empty() or absf(wall["normal"].y) > 0.3:
		return
	var n := Vector3(wall["normal"].x, 0, wall["normal"].z).normalized()
	var probe: Vector3 = wall["position"] - n * 0.3
	var dq := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 1.3, probe + Vector3.DOWN * 0.6)
	dq.collision_mask = 1
	var top := space.intersect_ray(dq)
	if top.is_empty() or top["normal"].y < 0.7:
		return
	var h: float = top["position"].y - global_position.y
	if h < 1.6 or h > 2.6:
		return
	# headroom on top for the climb
	var hq := PhysicsRayQueryParameters3D.create(top["position"] + Vector3.UP * 0.1, top["position"] + Vector3.UP * 1.9)
	hq.collision_mask = 1
	if not space.intersect_ray(hq).is_empty():
		return
	_grab_ledge(top["position"], n)


func _grab_ledge(top: Vector3, n: Vector3) -> void:
	mode = "ledge"
	_ledge_top = top
	_ledge_normal = n
	vel = Vector3.ZERO
	global_position = Vector3(top.x, top.y - HANG_DROP, top.z) + n * 0.45
	reset_physics_interpolation()
	heading = atan2(-n.x, -n.z)
	hero.play("CK_LedgeHang", 0.12)


func _ledge_continues(top: Vector3) -> bool:
	var dq := PhysicsRayQueryParameters3D.create(top + Vector3.UP * 0.4 - _ledge_normal * 0.3, top + Vector3.DOWN * 0.3 - _ledge_normal * 0.3)
	dq.collision_mask = 1
	return not get_world_3d().direct_space_state.intersect_ray(dq).is_empty()


func _start_climb() -> void:
	mode = "climb"
	_climb_t = 0.0
	_climb_from = global_position
	hero.play("CK_LedgeClimb", 0.08, 1.0, true)


## Climb-up over 0.9 s: rise to the ledge, then step forward onto it (moved with collision, wall disabled
## only for the body's own sweep as it rolls over the lip).
func _climb(dt: float) -> void:
	_climb_t += dt
	var up_end := _ledge_top.y + 0.05
	var k := clampf(_climb_t / 0.55, 0.0, 1.0)
	var target: Vector3
	if _climb_t < 0.55:
		target = Vector3(_climb_from.x, lerpf(_climb_from.y, up_end, k * k * (3.0 - 2.0 * k)), _climb_from.z)
	else:
		var k2 := clampf((_climb_t - 0.55) / 0.35, 0.0, 1.0)
		target = Vector3(_climb_from.x, up_end, _climb_from.z) - _ledge_normal * (0.45 + 0.75 * k2)
	var motion := target - global_position
	var col := move_and_collide(motion, true)
	if col == null or _climb_t < 0.55:
		global_position = target # the rise hugs the wall face; its own contact is expected
	else:
		move_and_collide(motion)
	if _climb_t >= 0.9:
		mode = "ground"
		vel = Vector3.ZERO
		hero.play("CK_Idle", 0.2)


## Running at a waist-high obstacle (0.5-1.3 m, shallow enough to clear): hop over it with a real arc.
func _try_vault() -> void:
	var space := get_world_3d().direct_space_state
	var fwd := Vector3(vel.x, 0, vel.z).normalized()
	var knee := global_position + Vector3.UP * 0.6
	var q := PhysicsRayQueryParameters3D.create(knee, knee + fwd * 1.4)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var low := space.intersect_ray(q)
	if low.is_empty() or absf(low["normal"].y) > 0.3:
		return
	var head := global_position + Vector3.UP * 1.55
	var hq := PhysicsRayQueryParameters3D.create(head, head + fwd * 2.2)
	hq.exclude = [get_rid()]
	hq.collision_mask = 1
	if not space.intersect_ray(hq).is_empty():
		return # too tall: that's a wall, not a barrier
	# top of the obstacle
	var over: Vector3 = low["position"] + fwd * 0.3
	var tq := PhysicsRayQueryParameters3D.create(over + Vector3.UP * 1.6, over)
	tq.collision_mask = 1
	var top := space.intersect_ray(tq)
	var h: float = (top["position"].y - global_position.y) if not top.is_empty() else 1.0
	if h < 0.45 or h > 1.35:
		return
	mode = "air"
	_vault_t = 0.8
	vel.y = sqrt(2.0 * -gravity * (h + 0.35))
	vel += fwd * 1.0
	hero.play("CK_Vault", 0.06, 1.3, true)


func _start_slide() -> void:
	mode = "slide"
	_slide_t = 0.75
	var flat := Vector2(vel.x, vel.z)
	var d := flat.normalized() if flat.length() > 0.1 else Vector2(sin(heading), cos(heading))
	var spd := maxf(flat.length(), P["sprintSpeed"]) * 1.15
	vel.x = d.x * spd
	vel.z = d.y * spd
	_set_height(P["height"] * 0.5)
	hero.play("CK_Slide", 0.08, 1.0, true)


func _end_slide() -> void:
	mode = "ground"
	_set_height(P["height"])


func _set_height(h: float) -> void:
	_shape.height = maxf(h, _shape.radius * 2.0)
	_col.position.y = _shape.height / 2.0


## Something solid within standing height overhead (keep sliding / stay low under it).
func _low_ceiling() -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0), global_position + Vector3(0, P["height"] + 0.1, 0))
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


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
	_update_feel(dt)
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
	elif mode == "ledge":
		hero.play("CK_LedgeHang", 0.15)
	hero.rotation.y = heading
	# glide: pitch the whole body toward horizontal flight
	var pitch := (0.9 - _glide_pitch * 0.8) if mode == "glide" else 0.0
	hero.rotation.x += (pitch - hero.rotation.x) * minf(1.0, 5.0 * dt)
	status = "%s%s%s%s | %s | %.1f m/s" % [mode, " crouch" if crouched else "", " aim" if aiming else "",
		" walk" if walk_mode else "", hero.current, speed]


## Feeds the hero's procedural layer. Frozen (driving, animation debug) turns all of it off; each part has
## its own states: lean on foot only, the head everywhere but gliding / hanging, the cape everywhere but
## gliding (the glide clip spreads it as a wing), foot IK only standing or walking on the floor.
func _update_feel(dt: float) -> void:
	var feel := hero.feel
	if feel == null or dt <= 0.0:
		return
	var on_foot := not frozen and hero.get_parent() == self
	var accel := (speed - _feel_speed) / dt
	_feel_speed = speed
	_feel_accel = lerpf(_feel_accel, accel, minf(1.0, dt * 8.0))
	_feel_turn = lerpf(_feel_turn, wrapf(heading - _feel_heading, -PI, PI) / dt, minf(1.0, dt * 8.0))
	_feel_heading = heading
	var lean_on := on_foot and mode == "ground" and not crouched and not aiming and combat_t <= 0.0
	hero.update_lean(dt, lean_on, speed if lean_on else 0.0, _feel_accel, _feel_turn)
	feel.cape_on = 1.0 if on_foot and mode != "glide" else 0.0
	feel.feet_on = 1.0 if on_foot and mode in ["ground", "action"] and _grounded and speed < 3.2 and _jump_timer < 0 else 0.0
	feel.floor_y = global_position.y
	feel.velocity = vel if on_foot and mode != "ledge" else Vector3.ZERO
	if feel.ray_exclude.is_empty():
		feel.ray_exclude = [get_rid()]
	_look_strength = 0.0
	var look = _look_point() if on_foot and mode not in ["glide", "ledge", "climb"] else null
	# a sprinting Knight watches where he's going: the turn shrinks with speed
	feel.look_on = _look_strength * lerpf(1.0, 0.35, clampf((speed - 3.0) / 6.0, 0.0, 1.0)) if look != null else 0.0
	if look != null:
		feel.look_target = look


## What the Knight's head turns toward: the grapnel anchor while reeling, else look_point (the game's pick:
## nearest alerted enemy within 12 m, else the grapple point), else where the camera looks.
func _look_point():
	_look_strength = 1.0
	if mode == "grapple" and _grapple_point != null:
		return _grapple_point
	if look_point != null:
		return look_point
	if camera != null:
		_look_strength = 0.6
		return camera.global_position - camera.global_basis.z * 25.0
	return null


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
