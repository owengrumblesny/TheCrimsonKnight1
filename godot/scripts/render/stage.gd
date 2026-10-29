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
const DAY := Color("#8a96a8") # overcast New Gotham day
const DUSK := Color("#5a3a44")

## Day/night: hours 0..24, advancing `day_speed` game hours per real minute (1 = a 24-minute day).
var hour := 16.5
var day_speed := 1.0
var cycle := true
## Weather: 0 = dry, 1 = storm. Drifts toward `weather_target`, which changes every few minutes.
var weather := 0.7
var weather_target := 0.7
var weather_name := "Rain"
var _weather_t := 180.0
var _thunder_t := 0.0
var _flash := 0.0
var _sky_mat: ProceduralSkyMaterial
var _rng := RandomNumberGenerator.new()
signal thunder


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
	_sky_mat = sky_mat
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


## Daylight 0..1 for an hour (0 at night, 1 at midday; smooth dawn 5-8 and dusk 17-20).
static func daylight(h: float) -> float:
	return smoothstep(5.0, 8.0, h) * (1.0 - smoothstep(17.0, 20.0, h))


## Advance time and weather, then light the city for them (not underground: the Citadel has its own lights).
func update_sky(dt: float) -> void:
	if cycle:
		hour = fposmod(hour + dt * day_speed / 60.0, 24.0)
	_weather_t -= dt
	if _weather_t <= 0.0:
		_weather_t = _rng.randf_range(150.0, 360.0)
		weather_target = [0.0, 0.25, 0.55, 0.8, 1.0][_rng.randi() % 5]
	weather = move_toward(weather, weather_target, dt / 40.0)
	weather_name = "Clear" if weather < 0.12 else "Drizzle" if weather < 0.4 else "Rain" if weather < 0.75 else "Storm"
	if underground:
		return
	var d := daylight(hour)
	var dusk := clampf(1.0 - absf(d - 0.35) / 0.35, 0.0, 1.0) * (1.0 - d) # warm band at dawn/dusk
	var overcast := weather
	var bg := NIGHT.lerp(DAY.darkened(overcast * 0.45), d).lerp(DUSK, dusk * 0.5)
	env.background_color = bg
	env.fog_light_color = bg
	env.fog_density = preset["fog_density"] * (1.0 + overcast * 1.2) * (1.0 - d * 0.45)
	_sky_mat.sky_top_color = Color(0.05, 0.06, 0.1).lerp(Color(0.36, 0.45, 0.6).darkened(overcast * 0.4), d)
	_sky_mat.sky_horizon_color = Color(0.11, 0.1, 0.12).lerp(Color(0.6, 0.62, 0.66), d).lerp(Color(0.7, 0.42, 0.36), dusk * 0.6)
	_sky_mat.energy_multiplier = 0.6 + d * 0.8
	env.ambient_light_energy = 1.4 + d * 1.2
	# the directional light is the moon at night and the (cloud-softened) sun by day
	var sun_angle := (hour - 6.0) / 12.0 * PI # 0 at 06:00, PI at 18:00
	var elev := sin(sun_angle) if d > 0.0 else 0.85
	moon.rotation = Vector3(-clampf(elev, 0.25, 1.2), deg_to_rad(-56) + (hour - 12.0) * 0.12, 0)
	moon.light_color = Color("#b8c4ff").lerp(Color("#fff1dc"), d).lerp(Color("#ffb080"), dusk * 0.6)
	moon.light_energy = lerpf(0.55, 1.5 * (1.0 - overcast * 0.55), d)
	env.tonemap_exposure = 1.1 - d * 0.2
	rain.amount_ratio = clampf((weather - 0.12) / 0.88, 0.0, 1.0)
	rain.visible = preset["rain"] > 0 and weather >= 0.12
	# storms: lightning flashes now and then (the game plays thunder a moment later)
	if weather > 0.75:
		_thunder_t -= dt
		if _thunder_t <= 0.0:
			_thunder_t = _rng.randf_range(9.0, 28.0)
			_flash = 1.0
			get_tree().create_timer(_rng.randf_range(0.4, 1.6)).timeout.connect(func(): thunder.emit())
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 4.0)
		env.background_color = bg.lerp(Color(0.75, 0.78, 0.9), _flash * 0.7)
		env.ambient_light_energy += _flash * 3.0


## "21:30"
func clock() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]


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
func apply_quality(q: String, overrides := {}) -> void:
	quality = q
	preset = Quality.resolve(q, overrides)
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
