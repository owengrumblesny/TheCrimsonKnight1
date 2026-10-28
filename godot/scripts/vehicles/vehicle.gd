class_name Vehicle
extends VehicleBody3D
## Drivable CR-X1 (car), CR-B1 (bike) and CR-A1 (jet). Tuning: godot/data/vehicles.json.
##  - car / bike: VehicleBody3D wheels at the GLB's Susp_* / Wheel_* pivots (the bike gets two hidden
##    outrigger pairs and an auto-balance torque; its lean is visual, from steering and speed)
##  - jet: same body with no wheels and a custom arcade integrator (taxi, flight, VTOL hover)
## The model's pivots are found by name, so a rebuilt or per-mode GLB with the same pivot names drops in.
## Per-mode swaps: modes.<mode>.model (asset id or res:// path) and .materials ({mesh_name: material path})
## from config/vehicle_assets.json <id>.modes, falling back to godot/data/vehicles.json.

signal mode_changed(mode: String)

var id := ""
var cfg: Dictionary
var kind := "car"
var model: Node3D
var anim: AnimationPlayer
var mode := ""
var modes: Array = []
var driver_in := false
## first-person by default; V toggles the chase camera
var first_person := true
var fpv_cam := Camera3D.new()
var chase_cam := Camera3D.new()
var throttle := 0.0
var steer_in := 0.0
var handbrake := false
var boost := false
var vtol_up := 0.0
var look := Vector2.ZERO # jet: mouse pitch/yaw input this frame; car/bike: FPV free-look
var top_speed := 50.0
var _wheels: Array = [] # {wheel, susp, steer, spin_node, radius, spin}
var _engine: AudioStreamPlayer3D
var _engine_volume := 1.0
var _emissive := {} # material -> base energy
var _lean := 0.0
var _bob := 0.0
var _free_look := Vector2.ZERO
var _gear_up := false
var _jet_speed := 0.0
var _jet_attitude := Vector3.ZERO # pitch, yaw, roll (radians, world yaw)


static func create(vehicle_id: String) -> Vehicle:
	var v := Vehicle.new()
	v.id = vehicle_id
	return v


func _ready() -> void:
	name = id
	cfg = CKData.data("vehicles")[id]
	kind = cfg["kind"]
	modes = cfg["modes"].keys() # same order as config/vehicle_specs.json
	mass = cfg["mass"]
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(cfg.get("com", [0, 0.4, 0])[0], cfg.get("com", [0, 0.4, 0])[1], cfg.get("com", [0, 0.4, 0])[2])
	continuous_cd = true
	can_sleep = false
	_load_model(CKData.model_path(id))
	if kind == "jet":
		custom_integrator = true
		gravity_scale = 0.0
	_engine = AudioStreamPlayer3D.new()
	_engine.bus = "Vehicles"
	_engine.unit_size = 8
	_engine.max_distance = 120
	add_child(_engine)
	var pivot := model.find_child("sound_engine", true, false) as Node3D
	if pivot:
		_engine.position = pivot.position
	for c in [fpv_cam, chase_cam]:
		c.near = 0.05
		c.far = 900
		add_child(c)
	chase_cam.top_level = true
	fpv_cam.fov = 72
	chase_cam.fov = 65
	set_mode(modes[0], true)


func set_engine_stream(stream: AudioStream) -> void:
	_engine.stream = stream


## (Re)load the visual model: colliders move onto this body, pivots and wheels are rebuilt.
func _load_model(path: String) -> void:
	for w in _wheels:
		w["wheel"].queue_free()
	_wheels.clear()
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	if model:
		model.queue_free()
	model = load(path).instantiate()
	model.name = "Model"
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false)
	for body in model.find_children("*", "StaticBody3D", true, false):
		for cs in body.get_children():
			if cs is CollisionShape3D:
				var copy := CollisionShape3D.new()
				copy.shape = cs.shape
				copy.transform = _rel(cs)
				add_child(copy)
		body.get_parent().remove_child(body)
		body.queue_free()
	_emissive.clear()
	for g in model.find_children("*", "MeshInstance3D", true, false):
		for s in g.mesh.get_surface_count():
			var m = g.get_surface_override_material(s) if g.get_surface_override_material(s) else g.mesh.surface_get_material(s)
			if m is StandardMaterial3D and m.emission_enabled:
				m = m.duplicate()
				g.set_surface_override_material(s, m)
				_emissive[m] = m.emission_energy_multiplier
	match kind:
		"car":
			for side in ["FL", "FR", "RL", "RR"]:
				var susp := model.find_child("Susp_" + side, true, false) as Node3D
				if susp:
					_add_wheel(_rel(susp).origin, side.begins_with("F"), cfg["wheel_radius"]["F" if side.begins_with("F") else "R"],
						susp, model.find_child("Steer_" + side, true, false), model.find_child("Wheel_" + side, true, false))
		"bike":
			var o: float = cfg.get("outrigger", 0.2)
			for pair in [["F", "Wheel_F", true], ["R", "Wheel_R", false]]:
				var wn := model.find_child(pair[1], true, false) as Node3D
				if wn == null:
					continue
				var at := _rel(wn).origin
				for x in [-o, o]:
					_add_wheel(Vector3(x, at.y, at.z), pair[2], cfg["wheel_radius"][pair[0]], null, null, wn if x > 0 else null)
	_update_cameras(0.0)


func _rel(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != self:
		if p is Node3D:
			xf = p.transform * xf
		p = p.get_parent()
	return xf


func _add_wheel(center: Vector3, front: bool, radius: float, _susp: Node3D, steer: Node3D, spin_node: Node3D) -> void:
	var s: Dictionary = cfg["suspension"]
	var w := VehicleWheel3D.new()
	w.wheel_radius = radius
	w.wheel_rest_length = s["rest"]
	w.suspension_travel = s["travel"]
	w.suspension_stiffness = s["stiffness"]
	w.damping_compression = s["damping"] * 0.6
	w.damping_relaxation = s["damping"]
	w.wheel_friction_slip = s["friction"]
	w.suspension_max_force = mass * 12
	w.use_as_steering = front
	w.use_as_traction = true
	w.wheel_roll_influence = 0.15
	w.position = center + Vector3(0, s["rest"], 0) # hangs down to the pivot's height at rest
	add_child(w)
	_wheels.append({"wheel": w, "front": front, "steer": steer, "spin_node": spin_node, "radius": radius, "spin": 0.0})


# ---------------- modes ----------------
func mode_def(m: String) -> Dictionary:
	var d: Dictionary = cfg["modes"].get(m, {}).duplicate()
	var assets = CKData.json("vehicle_assets").get(id, {})
	if assets is Dictionary and assets.get("modes") is Dictionary and assets["modes"].get(m) is Dictionary:
		d.merge(assets["modes"][m], true)
	return d


func cycle_mode() -> void:
	set_mode(modes[(modes.find(mode) + 1) % modes.size()])


func set_mode(m: String, instant := false) -> void:
	var old := mode
	var od := mode_def(old) if old != "" else {}
	var d := mode_def(m)
	mode = m
	# optional per-mode model (vehicle-modes GLBs), else per-mode materials on the shared model
	var want_model: String = d.get("model", "")
	if want_model != "" or od.get("model", "") != "":
		var path := want_model if want_model.begins_with("res://") else CKData.model_path(want_model) if want_model != "" else CKData.model_path(id)
		if path != "" and ResourceLoader.exists(path):
			_load_model(path)
	for mesh_name in d.get("materials", {}):
		var mi := model.find_child(mesh_name, true, false) as MeshInstance3D
		var mat_path: String = d["materials"][mesh_name]
		if mi and ResourceLoader.exists(mat_path):
			mi.material_override = load(mat_path)
	# leaving a mode with a transition clip plays it backwards
	if anim:
		var out: String = od.get("clip", "")
		var into: String = d.get("clip", "")
		if out != "" and anim.has_animation(out):
			anim.play_backwards(out)
			if instant:
				anim.seek(0.0, true)
		if into != "" and anim.has_animation(into):
			anim.play(into)
			if instant:
				anim.seek(anim.get_animation(into).length, true)
	top_speed = d.get("top", 50.0)
	_engine_volume = d.get("engine_volume", 1.0)
	for m2 in _emissive:
		m2.emission_energy_multiplier = _emissive[m2] * d.get("emissive", 1.0)
	if not instant:
		mode_changed.emit(m)


func play_door(open: bool) -> void:
	var clip: String = cfg.get("door_clip", "")
	if anim and clip != "" and anim.has_animation(clip):
		if open:
			anim.play(clip)
		else:
			anim.play_backwards(clip)


# ---------------- driving ----------------
func speed() -> float:
	return linear_velocity.length() if kind == "jet" else linear_velocity.dot(global_basis.z)


func _physics_process(dt: float) -> void:
	if kind == "jet":
		return
	var fwd_speed := linear_velocity.dot(global_basis.z)
	var steer_max: float = cfg["steer"] * lerpf(1.0, 0.35, clampf(absf(fwd_speed) / top_speed, 0.0, 1.0))
	steering = move_toward(steering, steer_in * steer_max, dt * 2.5)
	var force := 0.0
	var brk := 0.0
	if throttle > 0.05:
		force = cfg["engine"] * throttle * (1.35 if boost else 1.0) if fwd_speed < top_speed else 0.0
	elif throttle < -0.05:
		if fwd_speed > 1.5:
			brk = cfg["brake"] * -throttle
		else:
			force = -cfg["reverse"] * -throttle
	elif driver_in:
		brk = cfg["brake"] * 0.08 # engine braking
	else:
		brk = cfg["brake"] # parked
	engine_force = force
	brake = brk
	for w in _wheels:
		var wh: VehicleWheel3D = w["wheel"]
		wh.wheel_friction_slip = cfg["suspension"]["friction"] * (0.45 if handbrake and not w["front"] else 1.0)
		if handbrake and not w["front"]:
			wh.brake = cfg["brake"] * 0.6
	# auto-balance / anti-roll: torque the body back upright (the bike's lean is visual only)
	var roll := global_basis.x.y
	var k := 6.0 if kind == "bike" else 1.5
	apply_torque(-global_basis.z * roll * mass * k * 9.8 - global_basis.z * angular_velocity.dot(global_basis.z) * mass * (2.0 if kind == "bike" else 0.4))
	var pitch_err := global_basis.z.y
	if kind == "bike":
		apply_torque(global_basis.x * pitch_err * mass * 2.0)


## Arcade flight: taxi on the ground, fly above takeoff speed, hover in VTOL.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if kind != "jet":
		return
	var dt := state.step
	var basis := Basis.from_euler(Vector3(_jet_attitude.x, _jet_attitude.y, _jet_attitude.z), EULER_ORDER_YXZ)
	var ground := _ground_distance(state)
	var vel := state.linear_velocity
	if mode == "vtol":
		_jet_attitude.y -= look.x * cfg["yaw_rate"] * 4.0 * dt + steer_in * 1.2 * dt
		_jet_attitude.x = lerpf(_jet_attitude.x, -throttle * 0.15, dt * 3)
		_jet_attitude.z = lerpf(_jet_attitude.z, steer_in * 0.12, dt * 3)
		var flat_fwd := Vector3(sin(_jet_attitude.y), 0, cos(_jet_attitude.y))
		var want := flat_fwd * throttle * top_speed
		want.y = vtol_up * cfg["vtol_climb"]
		if ground < 0.05 and want.y <= 0:
			want.y = 0
		vel = vel.lerp(want, minf(1.0, dt * 2.0))
		_jet_speed = Vector2(vel.x, vel.z).length()
	else:
		var limit := top_speed * (1.25 if boost else 1.0)
		_jet_speed = clampf(_jet_speed + throttle * cfg["accel"] * dt - (0.0 if throttle > 0 else 2.0 * dt), 0.0, limit)
		var airborne: bool = _jet_speed > cfg["takeoff"] or ground > 1.0
		if airborne:
			_jet_attitude.x = clampf(_jet_attitude.x + look.y * cfg["pitch_rate"] * 3.0 * dt, -1.2, 1.2)
			_jet_attitude.z = lerpf(_jet_attitude.z, -steer_in * 1.1, dt * cfg["roll_rate"])
			_jet_attitude.y -= (look.x * cfg["yaw_rate"] * 2.0 + sin(_jet_attitude.z) * 0.9) * dt
		else:
			_jet_attitude.y -= steer_in * 0.6 * dt
			_jet_attitude.x = lerpf(_jet_attitude.x, 0.0, dt * 4)
			_jet_attitude.z = lerpf(_jet_attitude.z, 0.0, dt * 4)
		basis = Basis.from_euler(_jet_attitude, EULER_ORDER_YXZ)
		vel = basis.z * _jet_speed
		# lift fades in from takeoff speed; below it the jet sits on its gear
		var lift := clampf((_jet_speed - cfg["takeoff"] * 0.6) / (cfg["takeoff"] * 0.4), 0.0, 1.0)
		vel.y += -9.8 * (1.0 - lift) * 2.0
		if ground < 0.05 and vel.y < 0:
			vel.y = 0
	state.linear_velocity = vel
	state.angular_velocity = Vector3.ZERO
	state.transform = Transform3D(Basis.from_euler(_jet_attitude, EULER_ORDER_YXZ), state.transform.origin)
	# gear up above 8 m in flight
	var want_up: bool = ground > 8.0 and mode != "vtol"
	if want_up != _gear_up and anim and anim.has_animation(cfg["gear_clip"]):
		_gear_up = want_up
		if want_up:
			anim.play(cfg["gear_clip"])
		else:
			anim.play_backwards(cfg["gear_clip"])


func _ground_distance(state: PhysicsDirectBodyState3D) -> float:
	var from := state.transform.origin + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -60, 0))
	q.exclude = [get_rid()]
	var hit := state.get_space_state().intersect_ray(q)
	return (from.y - 1.0 - hit["position"].y) if hit else 60.0


## Spawn helper: set position/heading and reset motion.
func place(at: Vector3, heading: float) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, heading), at)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_jet_attitude = Vector3(0, heading, 0)
	_jet_speed = 0
	reset_physics_interpolation()


func _process(dt: float) -> void:
	var spd := speed()
	# wheel visuals: spin from ground speed, steer pivots, suspension follows the physics wheels
	for w in _wheels:
		w["spin"] += spd / w["radius"] * dt
		if w["spin_node"]:
			w["spin_node"].rotation.x = w["spin"]
		if w["steer"]:
			w["steer"].rotation.y = steering
	if kind == "bike":
		var steer_node := model.find_child("Steer", true, false) as Node3D
		if steer_node:
			steer_node.rotation.y = steering
		var target := -steering / cfg["steer"] * cfg["lean"] * clampf(absf(spd) / 15.0, 0.0, 1.0)
		_lean = lerpf(_lean, target, minf(1.0, dt * 5.0))
		model.rotation.z = _lean
	# engine
	if _engine.stream:
		var rev := clampf(absf(spd) / maxf(top_speed, 1.0), 0.0, 1.0)
		_engine.pitch_scale = 0.55 + rev * 1.4 + (0.15 if boost else 0.0)
		_engine.volume_db = linear_to_db(maxf(0.001, (0.25 + 0.75 * maxf(rev, absf(throttle))) * _engine_volume * (1.0 if driver_in else 0.35)))
		if not _engine.playing:
			_engine.play()
	_update_cameras(dt)


func _update_cameras(dt: float) -> void:
	if model == null:
		return
	var spd := absf(speed())
	var k := clampf(spd / maxf(top_speed, 1.0), 0.0, 1.0)
	# cockpit camera: the GLB's camera_cockpit, or (bike) head height over the grips
	var cock := model.find_child("camera_cockpit", true, false) as Node3D
	var base: Transform3D
	if cock:
		base = _rel(cock)
	else:
		var c: Array = cfg.get("cockpit", [0, 1.5, 0])
		base = Transform3D(Basis(), Vector3(c[0], c[1], c[2]))
	if kind == "bike":
		base = Transform3D(Basis(Vector3.FORWARD, _lean), Vector3.ZERO) * base
	# glTF cameras look down -Z; the vehicles drive toward +Z
	var look_basis := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, cfg.get("cockpit_pitch", -0.08))
	if kind != "jet":
		_free_look = _free_look.lerp(Vector2.ZERO, minf(1.0, dt * 1.5)) if look == Vector2.ZERO else _free_look
		_free_look += Vector2(-look.x, -look.y)
		_free_look.x = clampf(_free_look.x, -1.8, 1.8)
		_free_look.y = clampf(_free_look.y, -0.7, 0.6)
		look_basis = Basis(Vector3.UP, _free_look.x) * look_basis * Basis(Vector3.RIGHT, _free_look.y)
	_bob += dt * (4.0 + 10.0 * k)
	var bob := Vector3(sin(_bob * 0.5) * 0.008, sin(_bob) * 0.012, 0) * k * (2.0 if kind == "bike" else 1.0)
	fpv_cam.transform = Transform3D(base.basis * look_basis, base.origin + bob)
	fpv_cam.fov = 72.0 + 16.0 * k + (6.0 if boost else 0.0)
	# chase camera: eases toward camera_chase, looking at the vehicle
	var chase := model.find_child("camera_chase", true, false) as Node3D
	var want := global_transform * (_rel(chase).origin if chase else Vector3(0, 2.5, -7))
	chase_cam.global_position = want if dt == 0.0 else chase_cam.global_position.lerp(want, minf(1.0, dt * 6.0))
	var aim := global_position + Vector3(0, 1.2 if kind != "jet" else 2.5, 0)
	if chase_cam.global_position.distance_to(aim) > 0.1:
		chase_cam.look_at(aim, Vector3.UP)
	chase_cam.fov = 65.0 + 12.0 * k


func active_camera() -> Camera3D:
	return fpv_cam if first_person else chase_cam


func seat() -> Node3D:
	return model.find_child("seat_attach", true, false) as Node3D


func anchor(n: String) -> Vector3:
	var a := model.find_child(n, true, false) as Node3D
	return a.global_position if a else global_position + global_basis.x * 2.0
