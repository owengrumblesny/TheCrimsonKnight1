class_name Smashable
extends StaticBody3D
## A solid box that breaks: storefront glass, partitions, shelves, counters, tables. smash() hides it, turns off
## its collision and throws light debris chunks (layer 4: they hit the ground but never stop a vehicle or the
## Knight). It rebuilds after a while once nobody is close. The Interceptor smashes them by driving into them;
## heavy hits and explosions can break them too.

const REBUILD_S := 120.0

var size := Vector3.ONE
var mat: Material
var glass := false
var effects: Node
## shared effects node (set by the game once it exists)
static var fx: Node
var broken := false
var _mesh: MeshInstance3D
var _shape: CollisionShape3D


func setup(s: Vector3, m: Material, is_glass: bool) -> void:
	size = s
	mat = m
	glass = is_glass
	add_to_group("smashable")
	_shape = CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = s
	_shape.shape = b
	add_child(_shape)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	bm.material = m
	_mesh.mesh = bm
	_mesh.visibility_range_end = 160.0
	add_child(_mesh)


## Break apart, pushed along `vel` (the smasher's velocity).
func smash(vel: Vector3) -> void:
	if broken:
		return
	broken = true
	_mesh.visible = false
	_shape.set_deferred("disabled", true)
	var n := 6 if glass else 5
	for i in n:
		var rb := RigidBody3D.new()
		rb.collision_layer = 4
		rb.collision_mask = 1
		rb.mass = 2.0 if glass else 8.0
		var piece := Vector3(size.x / 3.0, size.y / 3.0, maxf(size.z, 0.08)) * randf_range(0.6, 1.0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = piece
		cs.shape = bs
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = piece
		bm.material = mat
		mi.mesh = bm
		rb.add_child(mi)
		get_parent().add_child(rb)
		rb.global_position = global_transform * Vector3(randf_range(-0.4, 0.4) * size.x, randf_range(-0.3, 0.4) * size.y, 0)
		rb.linear_velocity = vel * randf_range(0.5, 0.9) + Vector3(randf_range(-2, 2), randf_range(1, 4), randf_range(-2, 2))
		rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		get_tree().create_timer(12.0).timeout.connect(rb.queue_free)
	var e: Node = effects if effects else fx
	if e:
		e.burst("debris", global_position, 8, 4.0, 0.4, 0.8)
		e.burst("sparks" if glass else "smoke", global_position, 6, 3.0, 0.3, 0.5)
	get_tree().create_timer(REBUILD_S).timeout.connect(_try_rebuild)


## Weapons / melee hits: heavy blows and blasts break it (light taps don't).
func hit(amount: float, _point: Vector3, dir: Vector3) -> bool:
	if amount >= 35.0:
		smash(dir * 6.0)
	return false


func _try_rebuild() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(global_position) < 45.0:
		get_tree().create_timer(20.0).timeout.connect(_try_rebuild)
		return
	broken = false
	_mesh.visible = true
	_shape.disabled = false
