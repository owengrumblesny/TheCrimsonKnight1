class_name FollowCamera
extends Node3D
## Over-the-shoulder orbit camera (port of render/followCamera.ts) with SpringArm3D collision.
## yaw: camera sits at focus + (sin yaw, -, cos yaw); PI = behind a hero facing +Z.

var yaw := PI
var pitch := 0.25
var distance := 4.2
var target: Node3D
var aiming := false
## Disabled while a benchmark/debug camera drives the Camera3D directly.
var active := true
var arm := SpringArm3D.new()
var camera := Camera3D.new()
var _focus := Vector3.ZERO
var _aim_blend := 0.0
## activity-driven framing: current distance / FOV ease toward what the Knight is doing
var _dist := 4.2
var _fov := 60.0
## set by the game while a hand-to-hand fight is on (wider framing to show the crowd)
var combat := false


func _ready() -> void:
	top_level = true
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	arm.shape = probe
	arm.margin = 0.05
	add_child(arm)
	camera.fov = 60
	camera.near = 0.1
	camera.far = 900
	arm.add_child(camera)
	if target is CollisionObject3D:
		arm.add_excluded_object(target.get_rid())
	_focus = target.global_position + Vector3(0, 1.55, 0)


func _process(dt: float) -> void:
	if not active:
		return
	var l := CKInput.take_look()
	yaw -= l.x
	pitch = clampf(pitch + l.y, -0.5, 1.2)
	_aim_blend += ((1.0 if aiming else 0.0) - _aim_blend) * minf(1.0, 8.0 * dt)
	_focus = _focus.lerp(target.global_position + Vector3(0, 1.55, 0), minf(1.0, 12.0 * dt))
	# shoulder offset to the camera's right while aiming
	var right := Vector3(cos(yaw), 0, -sin(yaw)) * 0.55 * _aim_blend
	global_position = _focus + right
	arm.basis = Basis.from_euler(Vector3(-pitch, yaw, 0))
	# framing by activity: close when walking (armour detail), pulled back for sprint / air, far for gliding
	var want_d := distance
	var want_fov := 60.0
	if target is Player:
		var pl: Player = target
		match pl.mode:
			"glide":
				want_d = distance + 2.8
				want_fov = 70.0
			"grapple":
				want_d = distance + 1.6
				want_fov = 66.0
			"air", "vault":
				want_d = distance + 0.5
			"ledge", "climb":
				want_d = distance - 0.4
			_:
				if pl.speed > 7.6:
					want_d = distance + 0.9
					want_fov = 66.0
				elif pl.speed < 2.8:
					want_d = distance - 0.7
		if combat:
			want_d = maxf(want_d, distance + 0.5)
	_dist = lerpf(_dist, want_d, minf(1.0, dt * 2.5))
	_fov = lerpf(_fov, want_fov, minf(1.0, dt * 3.0))
	arm.spring_length = lerpf(_dist, 2.3, _aim_blend)
	camera.fov = lerpf(_fov, 47.0, _aim_blend) # tighter over-the-shoulder view while aiming


## Weapon recoil: lift the aim and nudge it sideways.
## settings "Reduce motion": no recoil kick
static var reduce_motion := false


func kick(amount: float) -> void:
	if reduce_motion:
		return
	pitch = clampf(pitch - amount, -0.5, 1.2)
	yaw += randf_range(-amount, amount) * 0.35


## Snap behind the target (after teleports).
func snap() -> void:
	_focus = target.global_position + Vector3(0, 1.55, 0)
