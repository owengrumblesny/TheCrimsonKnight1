class_name VehicleWeapons
extends Node
## Vehicle weapons (fictional, non-lethal "knockdown" tuning like the Knight's own gear). They reuse the on-foot
## weapon effects (tracers, muzzle flash, impacts, projectiles, splash) from Weapons.
##  - CR-X1 Interceptor, Battle mode: LMB twin autocannon (alternating barrels), RMB 4-missile salvo.
##  - CR-B1 Cycle, Battle mode: LMB pulse blaster.
##  - CR-A1 Specter, Flight or Stealth: LMB nose cannon, RMB missile pair. VTOL has none.
##  - Pursuit / Stealth (car, bike) carry no weapons; LMB tells you to switch to Battle (B).
## Aim is the screen centre (chase or cockpit camera; the jet's camera follows its nose), with a soft assist
## onto the nearest enemy within ~7 degrees. Missiles home gently on that enemy.

signal sound(id: String)
signal notify(text: String, icon: String, kind: String)

## vehicle id -> mode -> {"primary": def id, "secondary": def id}
const LOADOUT := {
	"crx1_interceptor": {"battle": {"primary": "veh_cannon", "secondary": "veh_missiles"}},
	"crb1_batcycle": {"battle": {"primary": "veh_blaster"}},
	"cra1_specter": {"flight": {"primary": "veh_nose_cannon", "secondary": "veh_missiles_air"},
		"stealth": {"primary": "veh_nose_cannon", "secondary": "veh_missiles_air"}},
}
const DEFS := {
	"veh_cannon": {"kind": "hitscan", "interval": 0.1, "damage": 30, "range": 220, "spread": 0.006, "impulse": 14, "color": "#ff405d", "heat": 0.035, "knock": 0.25},
	"veh_blaster": {"kind": "hitscan", "interval": 0.16, "damage": 26, "range": 160, "spread": 0.004, "impulse": 9, "color": "#ff6070", "heat": 0.045, "knock": 0.15},
	"veh_nose_cannon": {"kind": "hitscan", "interval": 0.08, "damage": 28, "range": 300, "spread": 0.008, "impulse": 12, "color": "#ff405d", "heat": 0.03, "knock": 0.25},
	"veh_missiles": {"kind": "missile", "count": 4, "cooldown": 5.0, "damage": 110, "splash": 5.5, "speed": 55, "gravity": 0.0, "range": 260, "impulse": 30, "color": "#ffb020", "size": 0.16},
	"veh_missiles_air": {"kind": "missile", "count": 2, "cooldown": 4.0, "damage": 120, "splash": 6.0, "speed": 80, "gravity": 0.0, "range": 380, "impulse": 30, "color": "#ffb020", "size": 0.18},
}

var weapons: Weapons # effect helpers
var director: Director
var heat := 0.0 # 0..1: the guns overheat if held too long
var overheated := false
var target: Node3D # aim-assist target this frame
var _next := {}
var _barrel := 1.0
var _missiles: Array = [] # {node, vel, travelled, def, target}


func loadout(v: Vehicle) -> Dictionary:
	return LOADOUT.get(v.id, {}).get(v.mode, {}) if v else {}


func armed(v: Vehicle) -> bool:
	return not loadout(v).is_empty()


func secondary_ready_in(v: Vehicle) -> float:
	var id: String = loadout(v).get("secondary", "")
	return maxf(0.0, (_next.get(id, 0) - Time.get_ticks_msec()) / 1000.0) if id != "" else -1.0


## Per frame while driving (fire inputs) and always (missiles in flight).
func update(dt: float, v: Vehicle, primary_held: bool, secondary_pressed: bool) -> void:
	var now := Time.get_ticks_msec()
	heat = maxf(0.0, heat - dt * (0.35 if not overheated else 0.25))
	if overheated and heat < 0.3:
		overheated = false
	_update_missiles(dt)
	target = null
	if v == null:
		return
	var lo := loadout(v)
	if lo.is_empty():
		if primary_held and Input.is_action_just_pressed("primaryAction") and LOADOUT.has(v.id):
			notify.emit("No weapons in %s mode. Press %s for Battle mode" % [v.mode.capitalize(), CKUI.key_label(CKInput.code("vehicleMode"))], "interceptor", "warn")
		return
	var cam := v.get_viewport().get_camera_3d()
	target = _assist_target(cam, v)
	if primary_held and lo.has("primary") and not overheated and now >= _next.get(lo["primary"], 0):
		_fire_gun(v, cam, lo["primary"], now)
	if secondary_pressed and lo.has("secondary"):
		if now >= _next.get(lo["secondary"], 0):
			_fire_missiles(v, cam, lo["secondary"], now)
		else:
			sound.emit("ui.deny")


func _aim_ray(cam: Camera3D, v: Vehicle, dist: float) -> Vector3:
	var c := cam.get_viewport().get_visible_rect().size / 2
	var from := cam.project_ray_origin(c)
	var dir := cam.project_ray_normal(c)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist)
	q.exclude = [v.get_rid(), weapons.player.get_rid()]
	var hit := v.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if hit else from + dir * dist


func _assist_target(cam: Camera3D, v: Vehicle) -> Node3D:
	if director == null:
		return null
	var c := cam.get_viewport().get_visible_rect().size / 2
	var fwd := cam.project_ray_normal(c)
	var best: Node3D = null
	var best_cos := cos(deg_to_rad(7.0))
	for e in director.enemies:
		if not is_instance_valid(e) or e.is_down():
			continue
		var to: Vector3 = e.global_position + Vector3(0, 1.2, 0) - cam.global_position
		if to.length() > 200.0:
			continue
		var cs := to.normalized().dot(fwd)
		if cs > best_cos:
			best_cos = cs
			best = e
	return best


func _muzzle(v: Vehicle, fwd: Vector3) -> Vector3:
	_barrel = -_barrel
	var b := v.global_basis
	var side := 0.9 if v.kind == "car" else (0.0 if v.kind == "bike" else 1.6)
	var up := 1.3 if v.kind == "car" else (0.9 if v.kind == "bike" else 0.2)
	return v.global_position + b.x * side * _barrel + Vector3.UP * up + fwd * (2.6 if v.kind != "jet" else 6.0)


func _fire_gun(v: Vehicle, cam: Camera3D, id: String, now: int) -> void:
	var d: Dictionary = DEFS[id]
	_next[id] = now + int(d["interval"] * 1000)
	heat = minf(1.0, heat + d["heat"])
	if heat >= 1.0:
		overheated = true
		notify.emit("Guns overheated", "interceptor", "warn")
	var aim: Vector3 = target.global_position + Vector3(0, 1.2, 0) if target else _aim_ray(cam, v, d["range"])
	var flat_fwd := (aim - v.global_position).normalized()
	var muzzle := _muzzle(v, flat_fwd)
	var s: float = d["spread"]
	var dir := ((aim - muzzle).normalized() + Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))).normalized()
	var q := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * d["range"])
	q.exclude = [v.get_rid(), weapons.player.get_rid()]
	q.collide_with_areas = false
	var hit := v.get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit["position"] if hit else muzzle + dir * d["range"]
	weapons._flash(muzzle, Color(d["color"]))
	weapons._tracer(muzzle, end, Color(d["color"]))
	sound.emit("weapon.shot")
	weapons.noise.emit(muzzle, 60.0)
	if hit:
		weapons.effects.burst("sparks", end, 5, 3.0, 0.4, 0.3)
		weapons._decal(end, hit["normal"], 0.35)
		weapons._damage(hit["collider"], d["damage"], end, dir, d["impulse"])
		var e = hit["collider"]
		if e is Enemy and not e.is_down() and randf() < d["knock"]:
			e.stun(0.6)


func _fire_missiles(v: Vehicle, cam: Camera3D, id: String, now: int) -> void:
	var d: Dictionary = DEFS[id]
	_next[id] = now + int(d["cooldown"] * 1000)
	var aim: Vector3 = target.global_position + Vector3(0, 1.0, 0) if target else _aim_ray(cam, v, d["range"])
	for i in int(d["count"]):
		var fwd := (aim - v.global_position).normalized()
		var muzzle := _muzzle(v, fwd) + Vector3.UP * 0.4
		# fan out, then curve onto the aim point
		var spread: Vector3 = v.global_basis.x * (i - (d["count"] - 1) / 2.0) * 0.25 + Vector3.UP * 0.12
		var n := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = d["size"]
		sm.height = d["size"] * 2.0
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(d["color"]).lightened(0.5)
		sm.material = m
		n.mesh = sm
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var l := OmniLight3D.new()
		l.light_color = Color(d["color"])
		l.light_energy = 1.2
		l.omni_range = 3.5
		n.add_child(l)
		weapons.add_child(n)
		n.global_position = muzzle
		_missiles.append({"node": n, "vel": (fwd + spread).normalized() * d["speed"] * 0.6, "travelled": 0.0, "def": d,
			"target": target, "aim": aim, "exclude": v.get_rid(), "smoke_t": 0.0})
	sound.emit("weapon.heavy")
	weapons.noise.emit(v.global_position, 80.0)


func _update_missiles(dt: float) -> void:
	for i in range(_missiles.size() - 1, -1, -1):
		var p: Dictionary = _missiles[i]
		var d: Dictionary = p["def"]
		var node: Node3D = p["node"]
		var vel: Vector3 = p["vel"]
		var goal: Vector3 = p["aim"]
		if p["target"] and is_instance_valid(p["target"]) and not p["target"].is_down():
			goal = p["target"].global_position + Vector3(0, 1.0, 0)
		# accelerate to full speed and steer onto the goal (gentle homing)
		var want: Vector3 = (goal - node.global_position).normalized() * d["speed"]
		vel = vel.lerp(want, minf(1.0, dt * 3.0))
		var step := vel * dt
		var q := PhysicsRayQueryParameters3D.create(node.global_position, node.global_position + step * 1.2)
		q.exclude = [p["exclude"], weapons.player.get_rid()]
		var hit := node.get_world_3d().direct_space_state.intersect_ray(q)
		p["smoke_t"] -= dt
		if p["smoke_t"] <= 0.0:
			p["smoke_t"] = 0.05
			weapons.effects.burst("smoke", node.global_position, 1, 0.2, 0.25, 0.5)
		if hit or node.global_position.distance_to(goal) < 0.8:
			var at: Vector3 = hit["position"] if hit else node.global_position
			weapons._explode(at, hit["normal"] if hit else Vector3.UP, vel.normalized(), d)
			for e in director.enemies:
				if is_instance_valid(e) and not e.is_down() and e.global_position.distance_to(at) < d["splash"] * 0.6:
					e.knock_down(vel.normalized())
			node.queue_free()
			_missiles.remove_at(i)
			continue
		node.global_position += step
		p["vel"] = vel
		p["travelled"] += step.length()
		if p["travelled"] > d["range"]:
			node.queue_free()
			_missiles.remove_at(i)
