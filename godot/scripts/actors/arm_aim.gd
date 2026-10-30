class_name ArmAim
extends SkeletonModifier3D
## Raises the right arm into the CK_GrappleAim pose over whatever the body is doing (walk, run, strafe, jump,
## crouch), so a gun comes up on every shot and while aiming, not only from a standstill (the strafe and
## locomotion clips carry the arms low). `weight` 0..1 is eased by the player (aiming / recently fired).
## The aim pose is read once from the clip's rotation tracks.

const BONES := ["Shoulder_R", "UpperArm_R", "LowerArm_R", "Hand_R"]

var weight := 0.0
var _pose := {} # bone index -> Quaternion (local, from CK_GrappleAim at t = 0.1 s)


func setup(anim: AnimationPlayer, skel: Skeleton3D) -> void:
	if anim == null or not anim.has_animation("CK_GrappleAim"):
		return
	var a := anim.get_animation("CK_GrappleAim")
	for name in BONES:
		var b := skel.find_bone(name)
		if b < 0:
			continue
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var path := String(a.track_get_path(t))
			if path.ends_with(":" + name):
				_pose[b] = a.rotation_track_interpolate(t, 0.1)
				break


func _process_modification() -> void:
	if weight <= 0.001 or _pose.is_empty():
		return
	var s := get_skeleton()
	for b in _pose:
		var cur: Quaternion = s.get_bone_pose_rotation(b)
		s.set_bone_pose_rotation(b, cur.slerp(_pose[b], weight))
