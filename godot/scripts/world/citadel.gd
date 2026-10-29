class_name Citadel
extends Node3D
## Red Citadel runtime (port of world/citadel.ts): physics from the imported *_COL bodies, room-based
## visibility (rooms within 30 m render), a fixed light pool fed by the Light_* points (glTF extras),
## proximity doors that slide up, and the three vehicles parked at their hangar anchors with a far LOD.

## The Citadel sits far below New Gotham; the portal / exit elevator teleports between them.
const OFFSET := Vector3(0, -120, -420)

var bounds := AABB()
var visible_rooms := 0
var _rooms: Array = [] # {name, node, box}
var _light_points: Array = [] # {pos, color, energy, range, room}
var _pool: Array = []
var _doors: Array = [] # {node, closed_y, open}
var _anchors := {}
var _timer := 0.0


func anchor(n: String) -> Vector3:
	return _anchors.get(n, OFFSET)


## Floor centre of a room (Room_<name>), or OFFSET if there's no such room.
func room_center(room: String) -> Vector3:
	for r in _rooms:
		if r["name"] == room:
			var b: AABB = r["box"]
			return Vector3(b.get_center().x, b.position.y, b.get_center().z)
	return OFFSET


## Name of the room containing p ("" if none).
func room_at(p: Vector3) -> String:
	for r in _rooms:
		if r["box"].grow(0.5).has_point(p):
			return r["name"]
	return ""


func contains(p: Vector3) -> bool:
	return bounds.has_point(p)


func build() -> void:
	name = "RedCitadel"
	var model: Node3D = load(CKData.model_path("red_citadel")).instantiate()
	model.position = OFFSET
	add_child(model)
	for n in model.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if nm.begins_with("Anchor_"):
			_anchors[nm] = n.global_position
		elif nm.begins_with("Light_"):
			var ex: Dictionary = n.get_meta("extras", {})
			var c: Array = ex.get("color", [1.0, 0.3, 0.25])
			_light_points.append({"pos": n.global_position, "color": Color(c[0], c[1], c[2]),
				"energy": float(ex.get("intensity", 30)), "range": float(ex.get("range", 18)),
				"room": String(n.get_parent().name).trim_prefix("Room_")})
		elif nm.begins_with("Door_"):
			_doors.append({"node": n, "closed_y": n.position.y, "open": 0.0})
	var first := true
	for child in model.get_children():
		if not String(child.name).begins_with("Room_"):
			continue
		var box := _bounds_of(child)
		_rooms.append({"name": String(child.name).trim_prefix("Room_"), "node": child, "box": box})
		bounds = box if first else bounds.merge(box)
		first = false
	bounds = bounds.grow(4)
	for m in model.find_children("*", "GeometryInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # interior: the light pool is unshadowed
	_park("crx1_interceptor", "Anchor_CRX1", PI)
	_park("crb1_batcycle", "Anchor_CRB1", PI)
	_park("cra1_specter", "Anchor_CRA1", PI)
	visible = false


func _bounds_of(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = m.global_transform * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## Vehicle in its bay: articulated model near, merged LOD1 beyond 40 m (visibility ranges).
func _park(id: String, anchor_name: String, rot_y: float) -> void:
	var holder := Node3D.new()
	holder.name = id
	holder.position = anchor(anchor_name)
	holder.rotation.y = rot_y
	add_child(holder)
	var near: Node3D = load(CKData.model_path(id)).instantiate()
	holder.add_child(near)
	for g in near.find_children("*", "GeometryInstance3D", true, false):
		g.visibility_range_end = 40
	var far_path := CKData.model_path(id + "_lod1")
	if far_path != "":
		var far: Node3D = load(far_path).instantiate()
		holder.add_child(far)
		for g in far.find_children("*", "GeometryInstance3D", true, false):
			g.visibility_range_begin = 40
		for b in far.find_children("*", "CollisionObject3D", true, false):
			b.queue_free() # the near model owns the colliders


func set_light_pool(n: int) -> void:
	for l in _pool:
		l.queue_free()
	_pool.clear()
	for i in n:
		var l := OmniLight3D.new()
		l.omni_attenuation = 1.6
		l.visible = false
		add_child(l)
		_pool.append(l)
	_timer = 0.0


## Room visibility, lights and doors. Returns whether the player is inside the Citadel.
func update(player: Vector3, dt: float) -> bool:
	var inside := contains(player)
	visible = inside
	if not inside:
		return false
	for d in _doors:
		var want := 1.0 if d["node"].global_position.distance_to(player) < 5 else 0.0
		d["open"] += (want - d["open"]) * minf(1.0, dt * 3)
		d["node"].position.y = d["closed_y"] + d["open"] * 3.4
	_timer -= dt
	if _timer > 0:
		return true
	_timer = 0.25
	var near := {}
	visible_rooms = 0
	for r in _rooms:
		var box: AABB = r["box"]
		var show := box.grow(30).has_point(player) and _dist(box, player) < 30
		r["node"].visible = show
		if show:
			visible_rooms += 1
			near[r["name"]] = true
	var pts := _light_points.filter(func(l): return near.has(l["room"]))
	pts.sort_custom(func(a, b): return a["pos"].distance_squared_to(player) < b["pos"].distance_squared_to(player))
	for i in _pool.size():
		var light: OmniLight3D = _pool[i]
		light.visible = i < pts.size()
		if light.visible:
			var p: Dictionary = pts[i]
			light.global_position = p["pos"]
			light.light_color = p["color"]
			# Blender light-point watts -> Godot energy (tuned by eye against the web build)
			light.light_energy = p["energy"] / 8.0
			light.omni_range = p["range"] * 1.5
	return true


func _dist(box: AABB, p: Vector3) -> float:
	return (p.clamp(box.position, box.end) - p).length()
