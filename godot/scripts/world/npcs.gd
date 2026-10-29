class_name NpcCrowd
extends Node3D
## Ambient NPC / enemy population (port of world/npcs.ts). NO AI: each NPC stands at a fixed spot
## playing an idle-family loop. Hidden beyond 90 m, animation paused beyond 60 m and throttled to ~10 Hz
## beyond 18 m, shadows only within 30 m. Plus a patrol drone hovering over the intersection.

const SHADOW_DIST := 30.0

var npcs: Array = [] # {root, anim, pending, shadow, meshes}
var _seed := 0x5eed


## mulberry32, same sequence as the web build so the layout matches.
func _rand() -> float:
	_seed = (_seed + 0x6d2b79f5) & 0xFFFFFFFF
	var t := _seed
	t = _imul(t ^ (t >> 15), t | 1)
	t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


static func _imul(a: int, b: int) -> int:
	return (a * b) & 0xFFFFFFFF


func build() -> void:
	name = "NPCs"
	var scales := {}
	for n in CKData.json("npc_assets")["npcs"]:
		scales[n["id"]] = n.get("scale", 1.0)
	for s in _layout():
		_spawn(s, scales.get(s["id"], 1.0))
	var drone: Node3D = load(CKData.model_path("npc_patrol_drone")).instantiate()
	drone.position = Vector3(6, 6.5, -6)
	add_child(drone)
	var ap: AnimationPlayer = drone.find_child("AnimationPlayer", true, false)
	if ap and ap.get_animation_list().size():
		ap.get_animation(ap.get_animation_list()[0]).loop_mode = Animation.LOOP_LINEAR
		ap.play(ap.get_animation_list()[0])
	npcs.append({"root": drone, "anim": ap, "pending": 0.0, "shadow": true, "meshes": []})


func _spot(id: String, x: float, z: float, rot: float, clip: String) -> Dictionary:
	return {"id": id, "x": x, "z": z, "rot": rot, "clip": clip}


func _layout() -> Array:
	var civ := ["npc_civilian_a", "npc_civilian_b", "npc_office_worker", "npc_scientist", "npc_mechanic", "npc_construction_worker"]
	var out := []
	# civilians along the sidewalks (some in talking pairs)
	for i in 14:
		var along := (-1.0 if _rand() < 0.5 else 1.0) * (12 + _rand() * 48)
		var side := -1.0 if _rand() < 0.5 else 1.0
		var off := side * (5.2 + _rand() * 1.2)
		var x_axis := _rand() < 0.5
		var x := along if x_axis else off
		var z := off if x_axis else along
		var id: String = civ[i % civ.size()]
		if i % 4 == 0:
			var dx := 0.9 if x_axis else 0.0
			var dz := 0.0 if x_axis else 0.9
			var face := atan2(dx, dz)
			out.append(_spot(id, x, z, face, "NPC_Talk"))
			out.append(_spot(civ[(i + 1) % civ.size()], x + dx, z + dz, face + PI, "NPC_Idle"))
		else:
			out.append(_spot(id, x, z, _rand() * TAU, "NPC_Idle"))
	# law enforcement at the intersection corners and the Owen Enterprises frontage
	out.append_array([_spot("npc_police_officer", 6.2, 5.6, -2.4, "NPC_Idle"), _spot("npc_police_officer", -6.0, -6.4, 0.7, "NPC_Idle"),
		_spot("npc_security_guard", -18, -6.0, 0, "NPC_Idle"), _spot("npc_security_guard", -21, -6.0, 0, "NPC_Idle")])
	# hostile factions are real enemies now (godot/scripts/actors/enemy.gd), spawned by the Director
	return out


func _spawn(s: Dictionary, scale: float) -> void:
	var root: Node3D = load(CKData.model_path(s["id"])).instantiate()
	root.position = Vector3(s["x"], 0, s["z"])
	root.rotation.y = s["rot"]
	root.scale = Vector3.ONE * scale
	add_child(root)
	var meshes := root.find_children("*", "GeometryInstance3D", true, false)
	for m in meshes:
		# posed bounds with margin: NPCs stay in place, so this is a safe cull volume
		m.extra_cull_margin = 0.6
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	if ap:
		var clip: String = s["clip"] if ap.has_animation(s["clip"]) else "NPC_Idle"
		if ap.has_animation(clip):
			ap.play(clip)
			ap.seek(_rand() * ap.get_animation(clip).length, true) # desync identical idles
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	npcs.append({"root": root, "anim": ap, "pending": 0.0, "shadow": true, "meshes": meshes})
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.56, 1.8, 0.56)
	cs.shape = box
	cs.position.y = 0.9
	body.add_child(cs)
	body.position = root.position
	add_child(body)


func update(focus: Vector3, dt: float) -> void:
	for n in npcs:
		var root: Node3D = n["root"]
		var d := root.global_position.distance_to(focus)
		root.visible = d < 90
		var shadow := d < SHADOW_DIST
		if shadow != n["shadow"]:
			n["shadow"] = shadow
			for m in n["meshes"]:
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ap: AnimationPlayer = n["anim"]
		if ap == null or d > 60 or ap.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			continue
		n["pending"] += dt
		if d > 18 and n["pending"] < 0.1:
			continue
		ap.advance(n["pending"])
		n["pending"] = 0.0
