class_name Stage
extends Node3D
## Night city lighting, fog, rain and graphics presets (port of render/stage.ts + quality.ts).
## The Red Citadel swaps to underground lighting via set_underground().

var quality := "high"
var preset: Dictionary = Quality.PRESETS["high"]
var underground := false
var env := Environment.new()
var world_env := WorldEnvironment.new()
var moon := DirectionalLight3D.new()
## Soft key light riding with the camera so the crimson armour reads at night.
var hero_key := OmniLight3D.new()
var rain: GPUParticles3D
var camera: Camera3D
const NIGHT := Color("#0b0d16")
const CAVE := Color("#070405")


func _ready() -> void:
	name = "Stage"
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.06, 0.1)
	sky_mat.sky_horizon_color = Color(0.11, 0.1, 0.12)
	sky_mat.ground_horizon_color = Color(0.08, 0.06, 0.07)
	sky_mat.ground_bottom_color = Color(0.02, 0.015, 0.02)
	sky_mat.sun_angle_max = 2.0
	sky_mat.energy_multiplier = 0.6
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_COLOR
	env.background_color = NIGHT
	env.sky = sky
	# reflections + ambient from the dim night sky (Three's PMREM night environment)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = NIGHT
	env.fog_sky_affect = 1.0
	env.glow_hdr_threshold = 1.2
	env.glow_intensity = 0.55
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.volumetric_fog_density = 0.015
	env.volumetric_fog_albedo = Color(0.55, 0.58, 0.7)
	env.volumetric_fog_length = 48
	world_env.environment = env
	add_child(world_env)
	moon.light_color = Color("#b8c4ff")
	moon.light_energy = 0.55
	moon.shadow_enabled = true
	moon.shadow_bias = 0.05
	moon.shadow_normal_bias = 1.5
	moon.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-56), 0)
	add_child(moon)
	hero_key.light_color = Color("#ffe2d0")
	hero_key.light_energy = 0.9
	hero_key.omni_range = 9
	hero_key.omni_attenuation = 1.5
	add_child(hero_key)
	_make_rain()


func _make_rain() -> void:
	rain = GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 6000
	rain.lifetime = 1.4
	rain.preprocess = 1.4
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 1, 30)
	pm.direction = Vector3(0.02, -1, 0)
	pm.spread = 0
	pm.initial_velocity_min = 20
	pm.initial_velocity_max = 24
	pm.gravity = Vector3.ZERO
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.015, 0.45)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.53, 0.6, 0.73, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = m
	rain.draw_pass_1 = q
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.position.y = 26
	add_child(rain)


## Keep the shadow, key light and rain centred on the player.
func follow(target: Vector3) -> void:
	if camera:
		var to_cam := (camera.global_position - target)
		to_cam.y = 0
		hero_key.global_position = target + to_cam.normalized() * 2.2 + Vector3(0, 2.6, 0)
	rain.global_position = Vector3(target.x, target.y + 26, target.z)


## Switch between the rainy night city and the underground Red Citadel lighting.
func set_underground(on: bool) -> void:
	if on == underground:
		return
	underground = on
	env.background_color = CAVE if on else NIGHT
	env.fog_light_color = env.background_color
	env.fog_density = 0.006 if on else preset["fog_density"]
	# underground: flat warm fill (the night sky would light the cave blue); the web build used a hemi light
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if on else Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.42, 0.35, 0.38)
	env.ambient_light_energy = 0.7 if on else 1.4
	moon.visible = not on
	rain.visible = not on and preset["rain"] > 0


## Apply a graphics preset. Viewport-wide settings live here; per-system ones (light pool, LOD) are read
## from `preset` by their owners.
func apply_quality(q: String) -> void:
	quality = q
	preset = Quality.PRESETS[q]
	var p := preset
	var vp := get_viewport()
	var h := float(DisplayServer.window_get_size().y)
	var scale := 1.0 if p["render_height"] == 0 or h <= 0 else minf(1.0, p["render_height"] / h)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if p["fsr"] and scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][p["msaa"]]
	vp.use_taa = p["taa"]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if p.get("fxaa", false) else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = p["mesh_lod"]
	vp.anisotropic_filtering_level = [Viewport.ANISOTROPY_DISABLED, Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X,
		Viewport.ANISOTROPY_8X, Viewport.ANISOTROPY_16X][p["anisotropy"]]
	RenderingServer.directional_shadow_atlas_set_size(p["shadow_map"], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p["soft_shadows"])
	RenderingServer.positional_soft_shadow_filter_set_quality(p["soft_shadows"])
	moon.shadow_enabled = p["shadows"]
	moon.directional_shadow_max_distance = p["shadow_range"] * 2.0
	moon.directional_shadow_mode = [DirectionalLight3D.SHADOW_ORTHOGONAL, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS][p["shadow_splits"]]
	if camera:
		camera.far = p["draw_distance"]
	env.fog_density = 0.006 if underground else p["fog_density"]
	env.glow_enabled = p["bloom"]
	env.ssao_enabled = p["ssao"]
	env.ssil_enabled = p["ssil"]
	env.ssr_enabled = p["ssr"]
	env.sdfgi_enabled = p["sdfgi"]
	env.volumetric_fog_enabled = p["volumetric_fog"]
	rain.amount = maxi(1, int(6000 * p["rain"]))
	rain.visible = not underground and p["rain"] > 0
