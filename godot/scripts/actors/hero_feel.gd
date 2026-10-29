class_name HeroFeel
extends SkeletonModifier3D
## Procedural layer on top of the CR-X9 clips, run after the AnimationPlayer each frame:
## hips drop + two-bone leg IK on uneven ground, upper-body lean, head look-at and a cape spring.
## The Player sets the targets (look_target, lean, the *_on weights); every weight fades in and out here,
## so switching state never pops. Skeleton space: +Z = the Knight's forward, +X = his left, +Y up.

## world point the head turns toward (used while look_on > 0)
var look_target := Vector3.ZERO
var look_on := 0.0
## upper-body forward lean in radians (+ = forward), shared by Spine and Chest
var lean := 0.0
var cape_on := 0.0
var feet_on := 0.0
## bodies the foot rays ignore (the player's own capsule)
var ray_exclude: Array[RID] = []
## world height of the feet (the player body's origin)
var floor_y := 0.0
## the body's world velocity (m/s), fed by the Player at the physics rate
var velocity := Vector3.ZERO

const LOOK_YAW := deg_to_rad(60.0)
const LOOK_PITCH := deg_to_rad(30.0)
const LOOK_GIVE_UP := deg_to_rad(115.0) # target behind the Knight: face forward instead of straining
const FOOT_REACH := 0.45 # max step height the legs adapt to (m)
const CAPE_SHARE := [0.42, 0.26, 0.18, 0.14] # share of the swing per cape bone, shoulder -> hem

var _b := {}
var _capes: Array = [] # [[bone ids top -> hem], ...] left to right
var _w_look := 0.0
var _w_cape := 0.0
var _w_feet := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _foot_d := [0.0, 0.0]
var _drop := 0.0
var _last_vel := Vector3.ZERO
var _vel := Vector3.ZERO
var _acc := Vector3.ZERO
var _cape := Vector2.ZERO # x = swing back (rad), y = swing sideways (rad, + = toward his left)
var _cape_v := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	_skeleton_changed(null, get_skeleton())


func _skeleton_changed(_old: Skeleton3D, sk: Skeleton3D) -> void:
	_b.clear()
	_capes.clear()
	if sk == null:
		return
	for n in ["Hips", "Spine", "Chest", "Neck", "Head", "UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R"]:
		_b[n] = sk.find_bone(n)
	for c in 8:
		var chain: Array[int] = []
		for i in 8:
			var id := sk.find_bone("Cape_%d_%d" % [c, i])
			if id < 0:
				break
			chain.append(id)
		if chain.is_empty():
			break
		_capes.append(chain)


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _b.is_empty() or _b["Hips"] < 0 or delta <= 0.0:
		return
	_t += delta
	var k := minf(1.0, delta * 5.0)
	_w_look = move_toward(_w_look, look_on, delta * 3.0)
	_w_cape = move_toward(_w_cape, cape_on, delta * 4.0)
	_w_feet = move_toward(_w_feet, feet_on, delta * 4.0)
	var xf := sk.global_transform
	var inv_basis := xf.basis.orthonormalized().inverse()
	_track_motion(delta)

	# feet probe the ground under the animated pose (before anything moves them)
	var foot_targets: Array = []
	if _w_feet > 0.001:
		foot_targets = _probe_feet(sk, xf, delta)
	else:
		_foot_d = [0.0, 0.0]
		_drop = 0.0

	if absf(_drop * _w_feet) > 0.0005:
		var hips: int = _b["Hips"]
		var up_local: Vector3 = xf.affine_inverse().basis * Vector3(0, _drop * _w_feet, 0)
		var parent := sk.get_bone_parent(hips)
		if parent >= 0:
			up_local = sk.get_bone_global_pose(parent).basis.inverse() * up_local
		sk.set_bone_pose_position(hips, sk.get_bone_pose_position(hips) + up_local)

	if absf(lean) > 0.0005:
		_rotate_global(sk, _b["Spine"], Quaternion(Vector3.RIGHT, lean * 0.4))
		_rotate_global(sk, _b["Chest"], Quaternion(Vector3.RIGHT, lean * 0.6))

	_look(sk, xf, k)
	_spring_cape(sk, inv_basis, delta)

	if not foot_targets.is_empty():
		_leg_ik(sk, "L", foot_targets[0])
		_leg_ik(sk, "R", foot_targets[1])


## Smoothed body velocity / acceleration (world). Velocity arrives in 60 Hz steps, so both are low-passed.
func _track_motion(dt: float) -> void:
	var v := velocity.limit_length(45.0)
	var a := ((v - _last_vel) / dt).limit_length(60.0)
	_last_vel = v
	_vel = _vel.lerp(v, minf(1.0, dt * 14.0))
	_acc = _acc.lerp(a, minf(1.0, dt * 6.0))


## Rotate a bone by q expressed in skeleton space, about its own origin (children follow).
func _rotate_global(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	if bone < 0:
		return
	var g := sk.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	_set_global_rot(sk, bone, q * g)


func _set_global_rot(sk: Skeleton3D, bone: int, global_q: Quaternion) -> void:
	var parent := sk.get_bone_parent(bone)
	var pq := sk.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	sk.set_bone_pose_rotation(bone, (pq.inverse() * global_q).normalized())


# ---------------- head ----------------

func _look(sk: Skeleton3D, xf: Transform3D, k: float) -> void:
	var neck: int = _b["Neck"]
	var head: int = _b["Head"]
	if neck < 0 or head < 0:
		return
	var want_yaw := 0.0
	var want_pitch := 0.0
	var chest := sk.get_bone_global_pose(_b["Chest"]).basis.orthonormalized()
	if _w_look > 0.001:
		var head_pos := sk.get_bone_global_pose(head).origin
		var d := chest.inverse() * (xf.affine_inverse() * look_target - head_pos)
		if d.length_squared() > 0.04:
			var yaw := atan2(d.x, d.z)
			if absf(yaw) < LOOK_GIVE_UP:
				want_yaw = clampf(yaw, -LOOK_YAW, LOOK_YAW)
				want_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -LOOK_PITCH, LOOK_PITCH)
	# critically smooth: the head leads with a short delay, never snaps
	_yaw = lerpf(_yaw, want_yaw * _w_look, k)
	_pitch = lerpf(_pitch, want_pitch * _w_look, k)
	if absf(_yaw) + absf(_pitch) < 0.002:
		return
	var up := chest.y
	var side := chest.x
	# neck takes 40% of the turn, the head the rest
	_rotate_global(sk, neck, Quaternion(up, _yaw * 0.4) * Quaternion(side, -_pitch * 0.4))
	_rotate_global(sk, head, Quaternion(up, _yaw * 0.6) * Quaternion(side, -_pitch * 0.6))


# ---------------- cape ----------------

## A damped spring per frame: forward speed and falling push the cape back, deceleration lets it swing
## forward a little (clamped so it never folds into the legs), sideways acceleration swings it out.
func _spring_cape(sk: Skeleton3D, inv_basis: Basis, dt: float) -> void:
	if _capes.is_empty():
		return
	var v := inv_basis * _vel
	var a := inv_basis * _acc
	var target := Vector2.ZERO
	if _w_cape > 0.001:
		var fwd := maxf(0.0, v.z)
		target.x = fwd * 0.03 - v.y * 0.03 + a.z * 0.012
		target.x = clampf(target.x, -0.1, 1.05)
		target.y = clampf(-a.x * 0.018 - v.x * 0.025, -0.3, 0.3)
		target *= _w_cape
	var w := 7.5
	var zeta := 0.42
	var steps := maxi(1, ceili(dt / 0.008)) # sub-step so a low frame rate stays stable
	var h := dt / steps
	for i in steps:
		_cape_v += (w * w * (target - _cape) - 2.0 * zeta * w * _cape_v) * h
		_cape += _cape_v * h
	_cape.x = clampf(_cape.x, -0.08, 1.15) # forward of the hang line would cut through the thighs
	_cape.y = clampf(_cape.y, -0.35, 0.35)
	if _cape.length() < 0.002:
		return
	var speed := Vector2(v.x, v.z).length()
	var n := _capes.size()
	for c in n:
		var chain: Array = _capes[c]
		var edge := (float(c) / maxf(1.0, n - 1.0)) * 2.0 - 1.0 # -1 .. 1 across the cape
		for i in chain.size():
			var share: float = CAPE_SHARE[mini(i, CAPE_SHARE.size() - 1)]
			# the hem flutters a touch at speed, each column out of phase
			var flutter := sin(_t * 11.0 + c * 1.7 + i * 0.9) * minf(speed, 12.0) * 0.004 * i * _w_cape
			var back := _cape.x * share + flutter
			var sway := _cape.y * share * (1.0 + 0.3 * edge * signf(_cape.y))
			_rotate_global(sk, chain[i], Quaternion(Vector3.RIGHT, back) * Quaternion(Vector3.BACK, sway))


# ---------------- feet ----------------

## Ray under each animated foot: how far its ground sits above / below the body's floor height.
## Returns the world IK targets [left, right]; updates the smoothed hips drop.
func _probe_feet(sk: Skeleton3D, xf: Transform3D, dt: float) -> Array:
	var space := sk.get_world_3d().direct_space_state
	var out: Array = []
	var k := minf(1.0, dt * 14.0)
	for f in 2:
		var bone: int = _b["Foot_L" if f == 0 else "Foot_R"]
		var p := xf * sk.get_bone_global_pose(bone).origin
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, floor_y + FOOT_REACH + 0.3, p.z), Vector3(p.x, floor_y - FOOT_REACH - 0.1, p.z))
		q.exclude = ray_exclude
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		var d := 0.0
		if not hit.is_empty() and hit["normal"].y > 0.6:
			d = clampf(hit["position"].y - floor_y, -FOOT_REACH, FOOT_REACH)
		_foot_d[f] = lerpf(_foot_d[f], d, k)
		out.append(p + Vector3.UP * _foot_d[f] * _w_feet)
	# the hips sink to the lower foot so the other leg can bend up to its step
	_drop = lerpf(_drop, minf(0.0, minf(_foot_d[0], _foot_d[1])), minf(1.0, dt * 10.0))
	# world -> skeleton space
	var inv := xf.affine_inverse()
	return [inv * out[0], inv * out[1]]


## Analytic two-bone IK (hip-knee-ankle), keeping the knee in its animated bend plane and the foot's
## animated world orientation.
func _leg_ik(sk: Skeleton3D, side: String, target: Vector3) -> void:
	var ua: int = _b["UpperLeg_" + side]
	var lo: int = _b["LowerLeg_" + side]
	var ft: int = _b["Foot_" + side]
	if ua < 0 or lo < 0 or ft < 0:
		return
	var ga := sk.get_bone_global_pose(ua)
	var gb := sk.get_bone_global_pose(lo)
	var gc := sk.get_bone_global_pose(ft)
	var A := ga.origin
	var B := gb.origin
	var C := gc.origin
	if C.distance_to(target) < 0.003:
		return
	var foot_q := gc.basis.get_rotation_quaternion()
	var la := A.distance_to(B)
	var lb := B.distance_to(C)
	var t := clampf(A.distance_to(target), 0.01, (la + lb) * 0.999)
	var ac := (C - A).normalized()
	var ab := (B - A).normalized()
	var ba := (A - B).normalized()
	var bc := (C - B).normalized()
	var at := (target - A).normalized()
	var ac_ab_0 := acos(clampf(ac.dot(ab), -1.0, 1.0))
	var ba_bc_0 := acos(clampf(ba.dot(bc), -1.0, 1.0))
	var ac_at_0 := acos(clampf(ac.dot(at), -1.0, 1.0))
	var ac_ab_1 := acos(clampf((lb * lb - la * la - t * t) / (-2.0 * la * t), -1.0, 1.0))
	var ba_bc_1 := acos(clampf((t * t - la * la - lb * lb) / (-2.0 * la * lb), -1.0, 1.0))
	var axis0 := ac.cross(ab)
	axis0 = axis0.normalized() if axis0.length_squared() > 1e-8 else Vector3.LEFT # straight leg: knee bends forward
	var r0 := Quaternion(axis0, ac_ab_1 - ac_ab_0)
	var r1 := Quaternion(axis0, ba_bc_1 - ba_bc_0)
	var r2 := Quaternion.IDENTITY
	var axis1 := ac.cross(at)
	if axis1.length_squared() > 1e-8:
		r2 = Quaternion(axis1.normalized(), ac_at_0)
	# pole: an idle leg is nearly straight, so its bend plane is arbitrary; swing the knee (about the
	# hip -> target line) toward the hips' forward, as far as the leg actually bends
	var r3 := Quaternion.IDENTITY
	var bend := PI - ba_bc_1
	if bend > 0.02:
		var knee := (r2 * r0) * (B - A)
		var pole := sk.get_bone_global_pose(_b["Hips"]).basis.z
		var kp := knee - at * knee.dot(at)
		var pp := pole - at * pole.dot(at)
		if kp.length_squared() > 1e-6 and pp.length_squared() > 1e-6:
			var ang := kp.signed_angle_to(pp, at)
			r3 = Quaternion(at, ang * clampf(bend / 0.35, 0.0, 1.0))
	var qa := ga.basis.get_rotation_quaternion()
	var qb := gb.basis.get_rotation_quaternion()
	r2 = r3 * r2
	_set_global_rot(sk, ua, r2 * r0 * qa)
	_set_global_rot(sk, lo, r2 * r0 * r1 * qb)
	_set_global_rot(sk, ft, foot_q)
