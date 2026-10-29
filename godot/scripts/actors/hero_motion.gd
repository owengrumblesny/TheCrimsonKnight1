class_name HeroMotion
extends SkeletonModifier3D
## Procedural layer on top of the CR-X9 clips (runs after the AnimationPlayer each frame):
##  - head look-at: Neck and Head turn toward `look_target` (world point), split 40/60, clamped to
##    ±60° yaw / ±30° pitch, eased so glances are smooth;
##  - cape secondary motion: `cape_back` lifts the cape away from the back (speed, falling) and `cape_side`
##    swings it sideways (turning, strafing), stronger toward the hem. The player drives both with a spring.
## Skeleton space: +Z is the hero's forward, +Y up.

## world point to look at, or null (eyes front)
var look_target = null
var cape_back := 0.0
var cape_side := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _neck := -1
var _head := -1
var _cape: Array = [] # [bone, row]


func _ready() -> void:
	var s := get_skeleton()
	if s == null:
		return
	_neck = s.find_bone("Neck")
	_head = s.find_bone("Head")
	for i in 5:
		for j in 4:
			var b := s.find_bone("Cape_%d_%d" % [i, j])
			if b >= 0:
				_cape.append([b, j])


func _process_modification() -> void:
	var s := get_skeleton()
	if s == null or _head < 0:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	# ---- head look-at ----
	var want_yaw := 0.0
	var want_pitch := 0.0
	if look_target != null:
		var t: Vector3 = s.global_transform.affine_inverse() * look_target
		var hp := s.get_bone_global_pose(_head).origin
		var d := t - hp
		var flat := Vector2(d.x, d.z).length()
		if flat > 0.3:
			var yaw := atan2(d.x, d.z)
			if absf(yaw) < 1.9: # beyond ~110 degrees it would look over the shoulder: face front instead
				want_yaw = clampf(yaw, -1.05, 1.05)
				want_pitch = clampf(atan2(d.y, flat), -0.5, 0.5)
	_yaw = lerpf(_yaw, want_yaw, minf(1.0, dt * 5.0))
	_pitch = lerpf(_pitch, want_pitch, minf(1.0, dt * 5.0))
	for pair in [[_neck, 0.4], [_head, 0.6]]:
		var b: int = pair[0]
		if b < 0:
			continue
		var w: float = pair[1]
		var g := s.get_bone_global_pose(b)
		var rot := Basis(Vector3.UP, _yaw * w) * Basis(Vector3.RIGHT, -_pitch * w)
		_set_global_rot(s, b, rot * g.basis)
	# ---- cape: lift back and swing sideways, more toward the hem ----
	if absf(cape_back) > 0.001 or absf(cape_side) > 0.001:
		for c in _cape:
			var b: int = c[0]
			var k := 1.0 if c[1] == 0 else 0.35
			var g := s.get_bone_global_pose(b)
			var rot := Basis(Vector3.RIGHT, cape_back * k) * Basis(Vector3.FORWARD, cape_side * k)
			_set_global_rot(s, b, rot * g.basis)


## Set a bone's skeleton-space rotation (keeping its position) by converting to the parent's space.
func _set_global_rot(s: Skeleton3D, b: int, basis: Basis) -> void:
	var parent := s.get_bone_parent(b)
	var pg := s.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var local := pg.basis.inverse() * basis
	s.set_bone_pose_rotation(b, local.get_rotation_quaternion())
