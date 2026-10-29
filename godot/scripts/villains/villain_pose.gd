class_name VillainPose
extends SkeletonModifier3D
## Procedural layer on top of a villain's clip (NPC humanoid rig: Hips/Spine/Chest/Neck/Head): the head and
## neck turn toward a world point (clamped +-70 deg yaw, +-35 pitch, eased), the chest leans and the head
## tilts / lifts its chin per emotion, and a small nod or laugh bounce while speaking. Runs after the
## AnimationPlayer each frame, so the clip stays the base and this only bends it.

var look_at = null # Vector3 world point or null
var lean := 0.0 # chest pitch, + = forward (rad)
var tilt := 0.0 # head roll (rad)
var chin := 0.0 # head pitch, + = up (rad)
var talk := 0.0 # 0..1 speaking energy (nod)
var laugh := 0.0 # 0..1 laugh bounce
var _yaw := 0.0
var _pitch := 0.0
var _lean := 0.0
var _tilt := 0.0
var _chin := 0.0
var _t := 0.0
var _bones := {}


func _bone(sk: Skeleton3D, n: String) -> int:
	if not _bones.has(n):
		_bones[n] = sk.find_bone(n)
	return _bones[n]


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_t += delta
	var k := minf(1.0, delta * 5.0)
	var want_yaw := 0.0
	var want_pitch := 0.0
	var head := _bone(sk, "Head")
	if look_at != null and head >= 0:
		var hp := sk.global_transform * sk.get_bone_global_pose(head).origin
		var d: Vector3 = sk.global_transform.affine_inverse().basis * (look_at - hp)
		if Vector2(d.x, d.z).length() > 0.05:
			want_yaw = clampf(atan2(d.x, d.z), deg_to_rad(-70), deg_to_rad(70))
			want_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), deg_to_rad(-35), deg_to_rad(35))
	_yaw = lerpf(_yaw, want_yaw, k)
	_pitch = lerpf(_pitch, want_pitch, k)
	_lean = lerpf(_lean, lean + sin(_t * 9.0) * 0.035 * laugh, k)
	_tilt = lerpf(_tilt, tilt, k * 0.8)
	_chin = lerpf(_chin, chin + sin(_t * 5.5) * 0.05 * talk + sin(_t * 9.0) * 0.06 * laugh, k)
	_rotate(sk, "Chest", Basis(Vector3.RIGHT, _lean) * Basis(Vector3.UP, _yaw * 0.15))
	_rotate(sk, "Neck", Basis(Vector3.UP, _yaw * 0.35) * Basis(Vector3.RIGHT, -_pitch * 0.35))
	_rotate(sk, "Head", Basis(Vector3.UP, _yaw * 0.5) * Basis(Vector3.RIGHT, -(_pitch * 0.65 + _chin)) * Basis(Vector3.FORWARD, _tilt))


## Rotate a bone by `r` expressed in skeleton space about the bone's own origin (keeps the animated pose).
func _rotate(sk: Skeleton3D, n: String, r: Basis) -> void:
	var b := _bone(sk, n)
	if b < 0:
		return
	var parent := sk.get_bone_parent(b)
	var g := sk.get_bone_global_pose(b)
	var ng := Basis(r.get_rotation_quaternion()) * g.basis
	var pg := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	sk.set_bone_pose_rotation(b, (pg.inverse() * ng).get_rotation_quaternion())
