shader_type spatial;
// Rain-soaked asphalt for New Gotham streets: Owen's wet_asphalt PNG projected in world space
// (1 tile / 2 m, like the triplanar PNG materials), large puddles from a noise mask (near-mirror roughness,
// darker albedo, so SSR picks up the neon and lamps) and drifting ripple normals outside the puddles.
// `ripples` is 0 on LOW (no animated normals), 1 on desktop presets.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D puddle_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wetness : hint_range(0.0, 1.0) = 1.0;
uniform float ripples : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz;
	vec3 base = texture(albedo_tex, uv * 0.5).rgb;
	float puddle = smoothstep(0.52, 0.62, texture(puddle_noise, uv * 0.04).r) * wetness;
	ALBEDO = base * mix(0.85, 0.5, puddle);
	ROUGHNESS = mix(mix(0.55, 0.3, wetness), 0.03, puddle);
	METALLIC = 0.05;
	SPECULAR = 0.5;
	// streets are flat and the placeholder road meshes carry no UVs/tangents, so perturb the world-space
	// up normal directly instead of using NORMAL_MAP
	vec2 slope = vec2(0.0);
	if (ripples > 0.0) {
		vec2 a = texture(ripple_normal, uv * 0.7 + vec2(TIME * 0.021, TIME * 0.034)).rg * 2.0 - 1.0;
		vec2 b = texture(ripple_normal, uv * 1.1 - vec2(TIME * 0.029, -TIME * 0.017)).rg * 2.0 - 1.0;
		slope = (a + b) * 0.5 * ripples * mix(0.35, 0.08, puddle);
	}
	vec3 wn = normalize(vec3(slope.x, 1.0, slope.y));
	if (dot((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, vec3(0.0, 1.0, 0.0)) > 0.5) {
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
}
