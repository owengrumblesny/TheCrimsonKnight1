class_name Weapons
extends Node3D
## Fictional weapons (Godot port only; the web build has them as props). Tuning lives in
## godot/data/weapons.json. The selected hotbar weapon is held on its gear socket; LMB fires from the
## gear's Muzzle anchor toward the crosshair (camera centre), RMB aims over the shoulder, T reloads.
##  - hitscan (sidearm, carbine): instant ray, tracer, sparks + scorch decal, impulse on loose props
##  - projectile (launcher, cannon): glowing bolt with gravity, splash damage and impulse on impact
##  - melee (blade): swing (CK_Interact), arc test in front of the Knight after hitDelay
## Damage goes to anything with a `hit(damage, point, dir)` method (target dummies).

signal notify(text: String, icon: String, kind: String)
signal sound(id: String)
signal hit_confirmed(kill: bool)
## gunfire / explosions at a point (enemies within earshot react)
signal noise(at: Vector3, radius: float)

const MAX_DECALS := 60

var player: Player
var cam: FollowCamera
var effects: Effects
var inventory: Inventory
var defs := {}
var _ammo := {}
var _reload_until := {}
var _next_shot := {}
var _projectiles: Array = [] # {node, vel, travelled, id}
var _decals: Array = []
var _scorch: Texture2D
var _pending_melee: Array = [] # {at, id}
var _last_shot := -100000


func _ready() -> void:
	name = "Weapons"
	var d: Dictionary = CKData.data("weapons")
	for k in d:
		if d[k] is Dictionary:
			defs[k] = d[k]
			_ammo[k] = int(d[k]["mag"])
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.015, 0.015, 0.9))
	g.set_color(1, Color(0, 0, 0, 0))
	g.add_point(0.45, Color(0.05, 0.03, 0.03, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_scorch = t


func is_weapon(id: String) -> bool:
	return defs.has(id)


func current() -> String:
	var id := inventory.selected_item()
	return id if is_weapon(id) else ""


## HUD line for the selected weapon ("12 / 12", "Reloading 0.8 s"), or "".
func status(now: int) -> String:
	var id := current()
	if id == "":
		return ""
	var d: Dictionary = defs[id]
	if d["kind"] == "melee":
		return "melee"
	if _reload_until.get(id, 0) > now:
		return "reloading %.1f s" % ((_reload_until[id] - now) / 1000.0)
	return "%d / %d" % [_ammo[id], d["mag"]]


func reload(now: int) -> void:
	var id := current()
	if id == "" or defs[id]["kind"] == "melee" or _reload_until.get(id, 0) > now or _ammo[id] == int(defs[id]["mag"]):
		return
	_reload_until[id] = now + int(defs[id]["reload"] * 1000)
	player.act("CK_GadgetStow", 0.3)
	sound.emit("weapon.reload")


## Per frame (only while playing on foot). fire_held / fire_pressed come from the primary action.
func update(dt: float, now: int, fire_pressed: bool, fire_held: bool) -> void:
	var id := current()
	if id != "":
		if _reload_until.has(id) and now >= _reload_until[id]:
			_reload_until.erase(id)
			_ammo[id] = int(defs[id]["mag"])
		var d: Dictionary = defs[id]
		if (fire_pressed or (fire_held and d["auto"])) and now >= _next_shot.get(id, 0) and not _reload_until.has(id):
			_fire(id, now)
	_point_gun(now)
	_update_projectiles(dt)
	for i in range(_pending_melee.size() - 1, -1, -1):
		if now >= _pending_melee[i]["at"]:
			_melee_hit(_pending_melee[i]["id"])
			_pending_melee.remove_at(i)


func _fire(id: String, now: int) -> void:
	var d: Dictionary = defs[id]
	_next_shot[id] = now + int(d["interval"] * 1000)
	if d["kind"] != "melee":
		player.combat_t = 1.5 # raise the weapon for every shot, not just on equip
	# turn to the camera so the shot (or swing) leaves the front of the Knight
	player.heading = cam.yaw + PI
	if d["kind"] == "melee":
		player.act("CK_Interact", 0.35)
		_pending_melee.append({"at": now + int(d["hitDelay"] * 1000), "id": id})
		sound.emit("weapon.swing")
		return
	if _ammo[id] <= 0:
		sound.emit("weapon.empty")
		reload(now)
		return
	_ammo[id] -= 1
	_last_shot = now
	_point_gun(now)
	var muzzle := _muzzle()
	var aim := _aim_point(d)
	var dir := (aim - muzzle).normalized()
	_flash(muzzle, Color(d["color"]))
	_gear_clip(d.get("fireClip", ""))
	cam.kick(d["recoil"])
	if d["kind"] == "hitscan":
		var hit := _ray(muzzle, aim + dir * 0.5)
		var end: Vector3 = hit["position"] if hit else aim
		_tracer(muzzle, end, Color(d["color"]))
		if hit:
			_impact(hit, dir, d)
		sound.emit("weapon.shot")
		noise.emit(muzzle, 45.0)
	else:
		_spawn_projectile(id, muzzle, dir * d["speed"], Color(d["color"]), d["size"])
		sound.emit("weapon.heavy")
		noise.emit(muzzle, 60.0)
	if _ammo[id] == 0:
		reload(now)


## Where the crosshair points: first surface along the camera ray (with spread), else max range.
func _aim_point(d: Dictionary) -> Vector3:
	var c := cam.camera
	var spread: float = d.get("spread", 0.0) * (0.4 if player.aiming else 1.0)
	var fwd := -c.global_basis.z
	fwd = (fwd + c.global_basis.x * randf_range(-spread, spread) + c.global_basis.y * randf_range(-spread, spread)).normalized()
	var hit := _ray(c.global_position, c.global_position + fwd * d["range"])
	return hit["position"] if hit else c.global_position + fwd * d["range"]


## While aiming (and briefly after a shot) a ranged weapon points at the crosshair instead of following
## the hand socket's idle-pose alignment, so the muzzle lines up with the shot.
func _point_gun(now: int) -> void:
	var id := current()
	var held: Node3D = player.hero._held
	if id == "" or held == null or defs[id]["kind"] == "melee" or not (player.aiming or now - _last_shot < 600):
		return
	var c := cam.camera
	var target := c.global_position - c.global_basis.z * 40.0
	var dir := (target - held.global_position).normalized()
	held.global_basis = Basis.looking_at(-dir, Vector3.UP).scaled(held.global_basis.get_scale())


func _muzzle() -> Vector3:
	var held: Node3D = player.hero._held
	if held:
		var m := held.find_child("Muzzle", true, false) as Node3D
		if m == null:
			m = held.find_child("Tip", true, false) as Node3D
		if m:
			return m.global_position
	return player.global_position + Vector3(0, 1.4, 0) + Vector3(sin(player.heading), 0, cos(player.heading)) * 0.5


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _gear_clip(clip: String) -> void:
	var held: Node3D = player.hero._held
	if clip == "" or held == null:
		return
	var ap := held.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation(clip):
		ap.stop()
		ap.play(clip)


## Equip: play the gear's deploy clip if it has one.
func on_equip(id: String) -> void:
	if is_weapon(id):
		_gear_clip.call_deferred(defs[id].get("equipClip", ""))


func _damage(collider: Object, amount: float, point: Vector3, dir: Vector3, impulse: float) -> void:
	var target := collider
	if target and not target.has_method("hit") and target is Node and target.get_parent() and target.get_parent().has_method("hit"):
		target = target.get_parent()
	if target and target.has_method("hit"):
		var killed: bool = target.hit(amount, point, dir)
		hit_confirmed.emit(killed)
		sound.emit("hit.marker")
	if collider is RigidBody3D:
		collider.apply_impulse(dir * impulse * 10.0, point - collider.global_position)


func _impact(hit: Dictionary, dir: Vector3, d: Dictionary) -> void:
	effects.burst("sparks", hit["position"], 6, 2.5, 0.35, 0.3)
	_decal(hit["position"], hit["normal"], 0.22)
	_damage(hit["collider"], d["damage"], hit["position"], dir, d["impulse"])


func _decal(at: Vector3, normal: Vector3, size: float) -> void:
	var dc := Decal.new()
	dc.texture_albedo = _scorch
	dc.size = Vector3(size, 0.2, size)
	dc.cull_mask = 1
	add_child(dc)
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	dc.global_transform = Transform3D(Basis(side, up, side.cross(up)), at)
	_decals.append(dc)
	if _decals.size() > MAX_DECALS:
		_decals.pop_front().queue_free()
	# bound to the decal itself, so the timer quietly does nothing if the decal was already recycled
	get_tree().create_timer(14.0).timeout.connect(dc.queue_free)
	_decals = _decals.filter(func(x): return is_instance_valid(x))


func _flash(at: Vector3, color: Color) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 3.0
	l.omni_range = 5
	add_child(l)
	l.global_position = at
	var q := MeshInstance3D.new()
	var m := QuadMesh.new()
	m.size = Vector2(0.28, 0.28)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = color.lightened(0.4)
	mat.albedo_texture = _scorch
	m.material = mat
	q.mesh = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)
	q.global_position = at
	get_tree().create_timer(0.05).timeout.connect(func():
		l.queue_free()
		q.queue_free())


func _tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var len := from.distance_to(to)
	if len < 0.2:
		return
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.018, 0.018, len)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.lightened(0.3), 0.8)
	b.material = m
	mi.mesh = b
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (from + to) / 2
	mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.07)
	tw.tween_callback(mi.queue_free)


func _spawn_projectile(id: String, at: Vector3, vel: Vector3, color: Color, size: float) -> void:
	var n := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = size
	s.height = size * 2
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color.lightened(0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4
	s.material = m
	n.mesh = s
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 1.5
	l.omni_range = 4
	n.add_child(l)
	add_child(n)
	n.global_position = at
	_projectiles.append({"node": n, "vel": vel, "travelled": 0.0, "id": id})


func _update_projectiles(dt: float) -> void:
	for i in range(_projectiles.size() - 1, -1, -1):
		var p: Dictionary = _projectiles[i]
		var d: Dictionary = defs[p["id"]]
		var node: Node3D = p["node"]
		var vel: Vector3 = p["vel"]
		vel.y -= d["gravity"] * dt
		var step := vel * dt
		var hit := _ray(node.global_position, node.global_position + step)
		if hit:
			_explode(hit["position"], hit["normal"], vel.normalized(), d)
			node.queue_free()
			_projectiles.remove_at(i)
			continue
		node.global_position += step
		p["vel"] = vel
		p["travelled"] += step.length()
		if p["travelled"] > d["range"]:
			node.queue_free()
			_projectiles.remove_at(i)


func _explode(at: Vector3, normal: Vector3, dir: Vector3, d: Dictionary) -> void:
	var r: float = d["splash"]
	effects.burst("sparks", at, 10, 4.0, 0.6, 0.45)
	effects.burst("smoke", at, int(4 + r * 2), 1.2, r * 0.5, 1.2)
	if r > 2:
		effects.burst("debris", at, 8, 3.0, 0.5, 0.8)
	_decal(at, normal, minf(r * 0.5, 2.2))
	_flash(at + normal * 0.3, Color(d["color"]))
	sound.emit("explosion" if r > 2 else "weapon.impact")
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = r
	q.shape = sphere
	q.transform = Transform3D(Basis(), at)
	q.exclude = [player.get_rid()]
	var seen := {}
	for h in get_world_3d().direct_space_state.intersect_shape(q, 32):
		var c: Object = h["collider"]
		if seen.has(c):
			continue
		seen[c] = true
		var to: Vector3 = (c.global_position - at) if c is Node3D else dir
		var falloff := clampf(1.0 - to.length() / r, 0.25, 1.0)
		_damage(c, d["damage"] * falloff, at, (to.normalized() + Vector3.UP * 0.3).normalized(), d["impulse"] * falloff)
	# the Knight is armoured: splash knocks him back but does no damage in the sandbox
	if player.global_position.distance_to(at) < r:
		player.vel += (player.global_position - at).normalized() * 3.0 + Vector3.UP * 2.0


func _melee_hit(id: String) -> void:
	var d: Dictionary = defs[id]
	var fwd := Vector3(sin(player.heading), 0, cos(player.heading))
	var center: Vector3 = player.global_position + Vector3(0, 1.1, 0) + fwd * d["range"] * 0.5
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = d["range"] * 0.6
	q.shape = sphere
	q.transform = Transform3D(Basis(), center)
	q.exclude = [player.get_rid()]
	var any := false
	var seen := {}
	for h in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var c: Object = h["collider"]
		if seen.has(c) or not c is Node3D:
			continue
		seen[c] = true
		var to: Vector3 = c.global_position - player.global_position
		to.y = 0
		if to.length() > 0.01 and fwd.angle_to(to.normalized()) > d["arc"] * 0.5 + 0.3:
			continue
		_damage(c, d["damage"], center, fwd, d["impulse"])
		effects.burst("sparks", center, 5, 2.0, 0.4, 0.25)
		any = true
	if any:
		sound.emit("weapon.impact")
