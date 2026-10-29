class_name Equipment
extends Node3D
## Uses the hotbar's selected item (port of systems/equipment.ts). Selecting never triggers this; only
## the primary action does. Every effect is real gameplay; items with an unavailableReason are refused
## with that reason. Times: ms on the Time.get_ticks_msec() clock.

signal notify(text: String, icon: String, kind: String)
signal sound(id: String)
signal photo_mode_changed(on: bool)

var player: Player
var camera: Camera3D
var district: District
var effects: Effects
var inventory: Inventory
var vitals: Vitals
var photo_mode := false
var _timed: Array = [] # {until, update: Callable, end: Callable}
var _projectiles: Array = [] # {node, vel, travelled}
var _beacons: Array = []
var _lamp: SpotLight3D
var _line: MeshInstance3D
var director: Director


func _ready() -> void:
	name = "Equipment"


## Try to use the selected item. Returns true if something happened.
func use_selected(now: int) -> bool:
	var id := inventory.selected_item()
	if id == "":
		notify.emit("Nothing selected. Press 1-8 or open the inventory (Tab)", "inventory", "warn")
		return false
	var d := inventory.def(id)
	var name_: String = d["displayName"]
	if d.get("unavailableReason"):
		return _deny(d, "%s: %s" % [name_, d["unavailableReason"]])
	if not inventory.has(id):
		return _deny(d, "%s: none left (restocks over time)" % name_)
	var cd := inventory.cooldown_remaining(id, now)
	if cd > 0:
		return _deny(d, "%s recharging (%.1f s)" % [name_, cd / 1000.0])
	var cost: float = d.get("energyCost", 0)
	if cost > 0 and vitals.energy < cost:
		return _deny(d, "Not enough energy for %s (%d needed)" % [name_, cost])
	if not has_method("_use_" + id):
		return _deny(d, "%s: no effect wired" % name_)
	if not call("_use_" + id, now):
		return false
	if cost > 0:
		vitals.spend(cost)
	inventory.consume(id)
	inventory.start_cooldown(id, now)
	if d.get("useClip") and id != "grapple":
		player.act(d["useClip"], 0.35)
	return true


func _deny(d: Dictionary, msg: String) -> bool:
	notify.emit(msg, d.get("iconId", ""), "warn")
	sound.emit("ui.deny")
	return false


func _feet() -> Vector3:
	return player.global_position


func _aim() -> Array:
	return [camera.global_position, -camera.global_basis.z]


## Ray cast that ignores the player capsule: {position, collider, distance} or {}.
func _cast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		hit["distance"] = origin.distance_to(hit["position"])
	return hit


func _add_timed(ms: int, now: int, end: Callable, update := Callable()) -> void:
	_timed.append({"until": now + ms, "end": end, "update": update})


func _gear(id: String) -> Node3D:
	var n: Node3D = load(CKData.model_path(id)).instantiate()
	for b in n.find_children("*", "CollisionObject3D", true, false):
		b.queue_free() # visual copies only
	add_child(n)
	return n


func _use_batarang(_now: int) -> bool:
	var dir: Vector3 = _aim()[1]
	var m := _gear("gear_batarang")
	m.scale = Vector3.ONE * 1.6
	m.global_position = _feet() + Vector3(0, 1.4, 0) + dir * 0.6
	_projectiles.append({"node": m, "vel": dir * 32.0, "travelled": 0.0})
	sound.emit("gadget.throw")
	return true


func _use_grapple(_now: int) -> bool:
	var a := _aim()
	var hit := _cast(a[0], a[1], 55)
	var chest := _feet() + Vector3(0, 1.4, 0)
	if hit.is_empty() or hit["position"].distance_to(chest) > 45:
		notify.emit("Grapnel: no surface in range (45 m). Aim at a building or prop", "grapple", "warn")
		sound.emit("ui.deny")
		return false
	if hit["position"].y < _feet().y + 1.2:
		notify.emit("Grapnel: aim higher. The anchor must be above you", "grapple", "warn")
		sound.emit("ui.deny")
		return false
	var t := player.find_grapple_target()
	if not t.is_empty():
		player.grapple_to(t["point"], t["ledge"], t.get("normal", Vector3.ZERO))
	else:
		player.grapple_to(hit["position"])
	sound.emit("gadget.throw")
	return true


func _use_scanner(now: int) -> bool:
	var p := _feet()
	var found := district.dynamic.filter(func(b): return b.global_position.distance_to(p) < 30)
	for b in found:
		var box := _outline(b)
		_add_timed(4000, now, box.queue_free)
	var ring := _ring(p, Color("#ff405d"))
	_add_timed(900, now, ring.queue_free, func(t, _dt): _grow(ring, t, now, 900, 30))
	sound.emit("gadget.pulse")
	notify.emit("Scan complete: %d movable object%s within 30 m" % [found.size(), "" if found.size() == 1 else "s"], "scanner", "info")
	return true


func _use_drone(now: int) -> bool:
	var drone := _gear("gear_drone")
	var light := SpotLight3D.new()
	light.light_energy = 4
	light.spot_range = 25
	light.spot_angle = 28
	light.rotation.x = -PI / 2
	drone.add_child(light)
	_add_timed(20000, now, drone.queue_free, func(t, _dt):
		var a: float = t / 1200.0
		drone.global_position = _feet() + Vector3(cos(a) * 3.5, 4.2 + sin(a * 2) * 0.3, sin(a) * 3.5)
		drone.rotation.y = -a)
	sound.emit("gadget.deploy")
	notify.emit("Recon drone launched (20 s)", "drone", "info")
	return true


func _use_smoke(_now: int) -> bool:
	effects.burst("smoke", _feet(), 16, 1.6, 2.4, 3.2)
	if director:
		director.add_smoke(_feet()) # enemies can't see through it for 6 s
	sound.emit("gadget.deploy")
	return true


func _use_shield(now: int) -> bool:
	vitals.shield_until = now + 6000
	var dome := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.5
	s.height = 3.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1, 0.25, 0.36, 0.18)
	s.material = m
	dome.mesh = s
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)
	_add_timed(6000, now, dome.queue_free, func(t, _dt):
		dome.global_position = _feet() + Vector3(0, 1, 0)
		m.albedo_color.a = 0.12 + 0.06 * sin(t / 120.0))
	sound.emit("armor.activate")
	notify.emit("Energy shield up: impact damage blocked (6 s)", "shield", "info")
	return true


func _use_cloak(now: int) -> bool:
	for g in player.hero.find_children("*", "GeometryInstance3D", true, false):
		g.transparency = 0.88
	_add_timed(8000, now, func():
		for g in player.hero.find_children("*", "GeometryInstance3D", true, false):
			g.transparency = 0.0
		notify.emit("Optical cloak disengaged", "cloak", "info"))
	sound.emit("armor.activate")
	notify.emit("Optical cloak engaged (8 s)", "cloak", "info")
	return true


func _use_beacon(_now: int) -> bool:
	var b := _gear("gear_beacon")
	b.global_position = _feet()
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.13, 0.19)
	light.light_energy = 2
	light.omni_range = 12
	light.position.y = 0.8
	b.add_child(light)
	_beacons.append(b)
	if _beacons.size() > 3:
		_beacons.pop_front().queue_free()
	sound.emit("gadget.deploy")
	notify.emit("Tracking beacon planted", "beacon", "info")
	return true


func _use_emp(now: int) -> bool:
	var p := _feet()
	var n := 0
	for l in district.lamps:
		if l["pos"].distance_to(p) < 25:
			l["off_until"] = now + 6000
			n += 1
	district.update_lights(p, now, 1.0) # apply immediately
	if director:
		for e in director.enemies:
			if is_instance_valid(e) and e.cfg.get("robot", false) and e.global_position.distance_to(p) < 25:
				e.stun(6.0) # the EMP shuts security robots down
	effects.burst("electrical", p + Vector3(0, 1, 0), 6, 2, 1.8, 0.6)
	var ring := _ring(p, Color("#6aa8ff"))
	_add_timed(700, now, ring.queue_free, func(t, _dt): _grow(ring, t, now, 700, 25))
	sound.emit("gadget.pulse")
	notify.emit("EMP: %d street light%s knocked out for 6 s" % [n, "" if n == 1 else "s"], "emp", "info")
	return true


func _use_sonic(now: int) -> bool:
	var p := _feet()
	var pushed := 0
	for b in district.dynamic:
		var d: Vector3 = b.global_position - p
		var dist := d.length()
		if dist > 9:
			continue
		d.y = 0
		var imp: Vector3 = d.normalized() * (9 - dist) * 1.6 * b.mass
		imp.y = b.mass * 3
		b.apply_central_impulse(imp)
		pushed += 1
	if director:
		for e in director.enemies:
			if is_instance_valid(e) and not e.is_down() and e.global_position.distance_to(p) < 9:
				e.stun(2.5)
				e.velocity += (e.global_position - p).normalized() * 8.0
				pushed += 1
	var ring := _ring(p, Color.WHITE)
	_add_timed(500, now, ring.queue_free, func(t, _dt): _grow(ring, t, now, 500, 9))
	sound.emit("gadget.pulse")
	notify.emit("Sonic burst pushed %d object%s" % [pushed, "" if pushed == 1 else "s"], "sonic", "info")
	return true


func _use_flashlight(_now: int) -> bool:
	if _lamp:
		_lamp.queue_free()
		_lamp = null
	else:
		_lamp = SpotLight3D.new()
		_lamp.light_color = Color(1, 0.96, 0.91)
		_lamp.light_energy = 6
		_lamp.spot_range = 40
		_lamp.spot_angle = 24
		_lamp.spot_attenuation = 1.2
		_lamp.shadow_enabled = true
		_lamp.position = Vector3(0, 1.75, 0.15)
		_lamp.rotation = Vector3(-0.1, PI, 0) # hero forward is +Z; a spot points down its -Z
		player.hero.add_child(_lamp)
	sound.emit("ui.click")
	return true


func _use_decoy(now: int) -> bool:
	if director == null:
		return false
	var holo: Node3D = load(CKData.model_path("crimson_knight_CRX9_rigged")).instantiate()
	add_child(holo)
	var fwd := Vector3(sin(player.heading), 0, cos(player.heading))
	holo.global_position = _feet() + fwd * 3.0
	holo.rotation.y = player.heading
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 0.2, 0.3, 0.35)
	m.emission_enabled = true
	m.emission = Color(1, 0.15, 0.25)
	for g in holo.find_children("*", "GeometryInstance3D", true, false):
		g.material_override = m
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visible = String(g.name).ends_with("_LOD2") or not String(g.name).contains("_LOD") # cheap LOD
	var ap: AnimationPlayer = holo.find_child("AnimationPlayer", true, false)
	if ap:
		ap.play("CK_GrappleAim")
	director.decoy = holo
	director.decoy_until = now + 8000
	director.noise(holo.global_position, 30.0)
	_add_timed(8000, now, func():
		if director.decoy == holo:
			director.decoy = null
		holo.queue_free(), func(t, _dt): m.albedo_color.a = 0.25 + 0.12 * sin(t / 90.0))
	sound.emit("gadget.deploy")
	notify.emit("Hologram decoy active (8 s)", "decoy", "info")
	return true


func _use_holoprojector(now: int) -> bool:
	if director == null:
		return false
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.no_depth_test = true # seen through walls
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(1, 0.25, 0.3, 0.45)
	var marked := []
	for e in director.enemies:
		if is_instance_valid(e) and not e.is_down() and e.global_position.distance_to(_feet()) < 70:
			for g in e.find_children("*", "GeometryInstance3D", true, false):
				g.material_overlay = glow
			marked.append(e)
	_add_timed(12000, now, func():
		for e in marked:
			if is_instance_valid(e):
				for g in e.find_children("*", "GeometryInstance3D", true, false):
					g.material_overlay = null)
	var ring := _ring(_feet(), Color("#ff405d"))
	_add_timed(900, now, ring.queue_free, func(t, _dt): _grow(ring, t, now, 900, 70))
	sound.emit("gadget.pulse")
	notify.emit("Holoprojector: %d hostile%s marked through walls (12 s)" % [marked.size(), "" if marked.size() == 1 else "s"], "holoprojector", "info")
	return true


func _use_comms(_now: int) -> bool:
	if director == null:
		return false
	var best = null
	var label := ""
	for m in director.markers:
		if m["kind"] == "waypoint":
			continue
		if best == null or m["pos"].distance_to(_feet()) < best.distance_to(_feet()):
			best = m["pos"]
			label = m["label"]
	var near := director.enemies.filter(func(e): return is_instance_valid(e) and not e.is_down() and e.global_position.distance_to(_feet()) < 80).size()
	if best != null:
		director.waypoint = best
		notify.emit("Comms: %s marked, %d m. %d hostile%s within 80 m" % [label, roundi(best.distance_to(_feet())), near, "" if near == 1 else "s"], "comms", "info")
	else:
		notify.emit("Comms: all quiet. %d hostile%s within 80 m" % [near, "" if near == 1 else "s"], "comms", "info")
	sound.emit("ui.select")
	return true


func _use_forensics(_now: int) -> bool:
	if director == null:
		return false
	var found := 0
	for e in director.enemies:
		if is_instance_valid(e) and e.is_down() and not e.has_meta("scanned") and e.global_position.distance_to(_feet()) < 6:
			e.set_meta("scanned", true)
			found += 1
			effects.burst("electrical", e.global_position + Vector3(0, 0.4, 0), 3, 0.5, 0.6, 0.4)
	if found == 0:
		notify.emit("Forensics: no unscanned suspects within 6 m. Knock some down first", "forensics", "warn")
		return false
	director.credits += found * 25
	director.evidence += found
	var msg := "Forensics: %d suspect%s scanned  +%d cr" % [found, "" if found == 1 else "s", found * 25]
	if director.evidence >= 3:
		director.evidence = 0
		director.start_crime()
		msg += ". Evidence points to a crime in progress"
	notify.emit(msg, "forensics", "info")
	sound.emit("gadget.pulse")
	return true


func _use_power_cell(_now: int) -> bool:
	return _heal("energy", 60, "power_cell")


func _use_first_aid(_now: int) -> bool:
	return _heal("health", 50, "first_aid")


func _use_repair(_now: int) -> bool:
	return _heal("armor", 40, "repair")


func _use_photo_camera(_now: int) -> bool:
	photo_mode = not photo_mode
	photo_mode_changed.emit(photo_mode)
	notify.emit("Photo mode on: HUD hidden (use the camera again to exit)" if photo_mode else "Photo mode off", "camera", "info")
	return true


func _heal(kind: String, amount: float, icon: String) -> bool:
	var got := vitals.restore(kind, amount)
	if got <= 0:
		notify.emit("%s already full" % kind.capitalize(), icon, "warn")
		return false
	sound.emit("armor.activate")
	notify.emit("+%d %s" % [roundi(got), kind], icon, "info")
	return true


func _ring(at: Vector3, color: Color) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.0
	t.rings = 64
	t.ring_segments = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color, 0.8)
	t.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.scale = Vector3(1, 0.02, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.1, 0)
	return mi


func _grow(mi: MeshInstance3D, t: int, start: int, ms: int, radius: float) -> void:
	var k := minf(1.0, float(t - start) / ms)
	var s := 0.5 + k * radius
	mi.scale = Vector3(s, 0.02, s)
	(mi.mesh.material as StandardMaterial3D).albedo_color.a = 0.8 * (1 - k)


func _outline(body: Node3D) -> MeshInstance3D:
	var box := BoxMesh.new()
	var shape: BoxShape3D = body.get_child(0).shape
	box.size = shape.size * 1.05
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 0.25, 0.36, 0.25)
	m.no_depth_test = true
	box.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	return mi


## Per frame: projectiles, timed effects, grapple line. dt seconds, now ms.
func update(dt: float, now: int) -> void:
	for i in range(_timed.size() - 1, -1, -1):
		var e: Dictionary = _timed[i]
		if now >= e["until"]:
			e["end"].call()
			_timed.remove_at(i)
		elif e["update"].is_valid():
			e["update"].call(now, dt)
	for i in range(_projectiles.size() - 1, -1, -1):
		var p: Dictionary = _projectiles[i]
		var node: Node3D = p["node"]
		var vel: Vector3 = p["vel"]
		var step := vel.length() * dt
		var hit := _cast(node.global_position, vel.normalized(), step)
		node.rotation.y += dt * 25
		if hit:
			var c = hit["collider"]
			if c is RigidBody3D:
				c.apply_central_impulse(vel.normalized() * 6 * c.mass)
			elif c is Enemy:
				c.hit(15.0, hit["position"], vel.normalized()) # batarang: light damage and a stagger
				c.stun(1.5)
			effects.burst("sparks", hit["position"], 6, 2.5, 0.5, 0.4)
			sound.emit("armor.step")
		node.global_position += vel * dt
		vel.y -= 2 * dt
		p["vel"] = vel
		p["travelled"] += step
		if hit or p["travelled"] > 45:
			node.queue_free()
			_projectiles.remove_at(i)
	# grapple line from the hand to the anchor while reeling in
	var anchor = player.grapple_anchor()
	if anchor != null:
		if _line == null:
			_line = MeshInstance3D.new()
			_line.mesh = ImmediateMesh.new()
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(0.13, 0.13, 0.13)
			_line.material_override = m
			add_child(_line)
		var im: ImmediateMesh = _line.mesh
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		im.surface_add_vertex(_feet() + Vector3(0, 1.5, 0))
		im.surface_add_vertex(anchor)
		im.surface_end()
	elif _line:
		_line.queue_free()
		_line = null
