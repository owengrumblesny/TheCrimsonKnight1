class_name Hero
extends Node3D
## The CR-X9 visual (port of actors/hero.ts): skinned GLB, cross-faded CK_* clips, LOD switching and
## gear held on skeleton sockets. Facing follows the web build: heading 0 = +Z.

signal clip_finished(name: String)

const HERO_ID := "crimson_knight_CRX9_rigged"

var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var current := ""
var lod_level := -1
var _lods: Array = [[], [], []]
var _held: Node3D
var _socket_align := {}
## procedural layer after the clips: head look, lean, cape spring, foot IK (driven by the Player)
var feel: HeroFeel
# body lean springs (rad / rad per s): x = pitch about the feet, y = roll into turns
var _lean := Vector2.ZERO
var _lean_v := Vector2.ZERO
var _model_basis := Basis.IDENTITY


func _ready() -> void:
	model = load(CKData.model_path(HERO_ID)).instantiate()
	add_child(model)
	_model_basis = model.basis
	anim = model.find_child("AnimationPlayer", true, false)
	for n in model.find_children("*", "Skeleton3D", true, false):
		skeleton = n
	for n in model.find_children("*_LOD?", "MeshInstance3D", true, false):
		_lods[int(String(n.name).right(1))].append(n)
	feel = HeroFeel.new()
	feel.name = "Feel"
	skeleton.add_child(feel)
	anim.animation_finished.connect(func(n: StringName): clip_finished.emit(String(n)))
	set_lod(0)
	play("CK_Idle", 0.0)


func clip_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n in anim.get_animation_list():
		out.append(String(n))
	out.sort()
	return out


## Cross-fade to a clip (fade in seconds). Same clip is kept unless restart.
func has_clip(name: String) -> bool:
	return anim != null and anim.has_animation(name)


func play(name: String, fade := 0.22, time_scale := 1.0, restart := false) -> void:
	if not anim.has_animation(name):
		return
	anim.speed_scale = time_scale
	if name == current and not restart:
		return
	if name == current:
		anim.seek(0.0, true)
	else:
		anim.play(name, fade)
	current = name


func set_time_scale(s: float) -> void:
	anim.speed_scale = s


## Playback rate that keeps feet planted for a locomotion clip at the given ground speed.
func rate_for(name: String, speed: float) -> float:
	var ref = CKData.hero_clip(name).get("refSpeed")
	return clampf(speed / ref, 0.55, 1.8) if ref else 1.0


## Weight on the move: lean forward with speed and acceleration, roll into turns (turn rate x speed), and
## let a spring carry the settle when he stops (the deceleration rocks him back a touch, then upright).
## Most of the pitch goes to the spine; the whole body takes a little, and all of the roll, about the feet.
func update_lean(dt: float, on: bool, spd: float, accel: float, turn_rate: float) -> void:
	var want := Vector2.ZERO
	if on:
		want.x = clampf(spd * 0.007 + clampf(accel, -14.0, 14.0) * 0.008, -0.07, 0.15)
		want.y = clampf(-turn_rate * spd * 0.009, -0.15, 0.15)
	var w := Vector2(9.0, 8.0)
	var zeta := Vector2(0.5, 0.8)
	var h := minf(dt, 0.05)
	_lean_v += (w * w * (want - _lean) - 2.0 * zeta * w * _lean_v) * h
	_lean += _lean_v * h
	model.basis = Basis.from_euler(Vector3(_lean.x * 0.3, 0.0, _lean.y)) * _model_basis
	feel.lean = _lean.x * 0.7


func set_lod(level: int) -> void:
	if _lods[1].is_empty() or level == lod_level:
		return
	lod_level = level
	for i in 3:
		for m in _lods[i]:
			m.visible = i == level


## LOD from camera distance; lod_scale from the preset (lower = switch sooner), min_lod 1 on LOW.
func update_lod(camera_distance: float, lod_scale: float, min_lod := 0) -> void:
	var d := camera_distance / lod_scale
	set_lod(maxi(min_lod, 0 if d < 9.0 else 1 if d < 26.0 else 2))


## Show a gear_* model on the socket named in its "attach" metadata (set at import from the glTF extra).
## Socket bones are not gear-aligned: the first use of a socket derives socketWorldQ^-1 * rootWorldQ
## in the current pose (cached per socket) so the model faces the hero's forward, upright.
func hold(model_id: String) -> void:
	if _held:
		_held.get_parent().queue_free()
		_held = null
	if not model_id.begins_with("gear_"):
		return
	var gear: Node3D = load(CKData.model_path(model_id)).instantiate()
	var attach: String = gear.get_meta("attach", "Socket_Hand_R")
	var bone := skeleton.find_bone(attach)
	if attach == "ground" or bone < 0:
		gear.queue_free()
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = attach
	skeleton.add_child(ba)
	if not _socket_align.has(attach):
		var qs := (skeleton.global_basis * skeleton.get_bone_global_pose(bone).basis).get_rotation_quaternion()
		var qr := global_basis.get_rotation_quaternion()
		_socket_align[attach] = qs.inverse() * qr
	gear.quaternion = _socket_align[attach]
	ba.add_child(gear)
	for m in gear.find_children("*", "GeometryInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_held = gear
