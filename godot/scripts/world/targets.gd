class_name TargetRange
extends Node3D
## Shootable training dummies (there are no enemies or AI): a post with a crimson-and-white plate.
## 100 hit points; a hit flashes the plate; at 0 the dummy topples and resets after 4 s.

class Dummy:
	extends StaticBody3D
	var health := 100.0
	var plate_mat: StandardMaterial3D
	var pivot: Node3D
	var shape: CollisionShape3D
	var down := false

	func hit(amount: float, _point: Vector3, _dir: Vector3) -> bool:
		if down:
			return false
		health -= amount
		plate_mat.emission_energy_multiplier = 3.0
		create_tween().tween_property(plate_mat, "emission_energy_multiplier", 0.4, 0.2)
		if health > 0:
			return false
		down = true
		shape.set_deferred("disabled", true) # shots pass over a knocked-down dummy
		var tw := create_tween()
		tw.tween_property(pivot, "rotation:x", -PI / 2, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(4.0)
		tw.tween_property(pivot, "rotation:x", 0.0, 0.5)
		tw.tween_callback(func():
			health = 100.0
			shape.disabled = false
			down = false)
		return true


var dummies: Array = []


func build(spots: Array) -> void:
	name = "TargetRange"
	for s in spots:
		dummies.append(_dummy(s[0], s[1], s[2]))


func _dummy(at: Vector3, rot: float, label: String) -> Dummy:
	var d := Dummy.new()
	d.name = "Target_" + label
	d.position = at
	d.rotation.y = rot
	add_child(d)
	d.pivot = Node3D.new()
	d.add_child(d.pivot)
	var metal: Material = load("res://godot/materials/png_gunmetal.tres")
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.07
	pm.height = 1.2
	pm.material = metal
	post.mesh = pm
	post.position.y = 0.6
	d.pivot.add_child(post)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.08, 0.4)
	bm.material = metal
	base.mesh = bm
	base.position.y = 0.04
	d.add_child(base)
	var plate := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.05
	d.plate_mat = StandardMaterial3D.new()
	d.plate_mat.albedo_texture = _rings()
	d.plate_mat.emission_enabled = true
	d.plate_mat.emission_texture = d.plate_mat.albedo_texture
	d.plate_mat.emission_energy_multiplier = 0.4
	d.plate_mat.roughness = 0.6
	cm.material = d.plate_mat
	plate.mesh = cm
	plate.rotation.x = PI / 2
	plate.position.y = 1.45
	d.pivot.add_child(plate)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.86, 1.9, 0.3)
	cs.shape = box
	cs.position.y = 0.95
	d.add_child(cs)
	d.shape = cs
	return d


static var _ring_tex: Texture2D


static func _rings() -> Texture2D:
	if _ring_tex == null:
		var g := Gradient.new()
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		g.set_color(0, Color("#ff405d"))
		g.set_color(1, Color("#3a0d16"))
		for i in 6:
			g.add_point(0.15 + i * 0.14, Color("#f4eef1") if i % 2 == 0 else Color("#d42a40"))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_ring_tex = t
	return _ring_tex
