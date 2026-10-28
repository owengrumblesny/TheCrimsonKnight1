class_name Effects
extends Node3D
## Sprite bursts using the effect images cut from Owen's boards (effects/b_*), port of render/effects.ts.
## The cut-outs sit on near-black backgrounds, so additive blending hides the background (the web radial
## tile-border mask is not ported yet). Each burst is a one-shot CPUParticles3D.

var _mats := {}


func _ready() -> void:
	name = "Effects"
	for k in ["sparks", "smoke", "debris", "electrical"]:
		var tex: Texture2D = load(CKData.board_image_path("effects/b_" + k))
		if tex == null:
			continue
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = tex
		m.albedo_color = Color(0.8, 0.8, 0.8)
		m.vertex_color_use_as_albedo = true # particle colour ramp fades it out
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.no_depth_test = false
		m.disable_receive_shadows = true
		_mats[k] = m


## count sprites of `kind` at `at`, outward speed (m/s), size (m), life (s).
func burst(kind: String, at: Vector3, count: int, speed: float, size: float, life: float) -> void:
	if not _mats.has(kind):
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.2, 0.05, 0.2)
	p.direction = Vector3(0, 1, 0)
	p.spread = 80
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed * 1.5
	p.gravity = Vector3(0, -4, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 1))
	grow.add_point(Vector2(1, 1 + (1.6 if kind == "smoke" else 0.2) * life))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _mats[kind]
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = at + Vector3(0, 0.1, 0)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## Hero landing impact; hard landings throw sparks, debris and smoke.
func landing(at: Vector3, hard: bool) -> void:
	if hard:
		burst("sparks", at, 10, 3.5, 0.9, 0.5)
		burst("debris", at, 8, 2.5, 0.6, 0.8)
		burst("smoke", at, 8, 1.2, 1.6, 1.4)
		burst("electrical", at, 2, 0.5, 1.4, 0.35)
	else:
		burst("smoke", at, 3, 0.6, 0.9, 0.8)
