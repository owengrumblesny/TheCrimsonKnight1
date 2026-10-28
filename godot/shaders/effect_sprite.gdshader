shader_type spatial;
// Effect sprites cut from Owen's boards (effects/b_*): additive, camera-facing particle quads with a radial
// fade that hides the square tile borders of each cut-out (the web build's radial alphaMap).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D sprite : source_color, filter_linear_mipmap;
uniform float brightness = 0.8;

void vertex() {
	// particle billboard (same as BaseMaterial3D BILLBOARD_PARTICLES): face the camera, keep the scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// white centre -> grey at 55 % -> black at the rim, like the web mask (radial gradient 4..60 of 64 px)
	float d = distance(UV, vec2(0.5)) / 0.47;
	float mask = d < 0.55 ? mix(1.0, 0.53, smoothstep(0.06, 0.55, d)) : mix(0.53, 0.0, smoothstep(0.55, 1.0, d));
	vec3 c = texture(sprite, UV).rgb;
	ALBEDO = c * brightness * mask * COLOR.rgb * COLOR.a; // particle colour ramp fades it out
}
