shader_type canvas_item;
// CR-X9 helmet vision modes, applied to the whole 3D view.
//  mode 1 Knight vision: cold blue monochrome with edge lines (people glow through walls via overlays)
//  mode 2 thermal: everything cold (deep blue/purple by brightness), warm bodies come from overlays
//  mode 3 X-ray: pale inverted grey-green, edges bright, like a scan
// helmet > 0 adds the helmet visor frame: curved vignette, faint scanlines, crimson corner tint.

uniform sampler2D screen: hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0;
uniform float helmet = 0.0;
uniform float time = 0.0;

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen, uv, 0.0).rgb;
	vec2 px = SCREEN_PIXEL_SIZE * 1.5;
	if (mode > 0) {
		float l = lum(c);
		// Sobel-ish edge from neighbouring luminance
		float lx = lum(textureLod(screen, uv + vec2(px.x, 0), 0.0).rgb) - lum(textureLod(screen, uv - vec2(px.x, 0), 0.0).rgb);
		float ly = lum(textureLod(screen, uv + vec2(0, px.y), 0.0).rgb) - lum(textureLod(screen, uv - vec2(0, px.y), 0.0).rgb);
		float edge = clamp(length(vec2(lx, ly)) * 4.0, 0.0, 1.0);
		if (mode == 1) {
			c = vec3(0.05, 0.12, 0.22) + vec3(0.25, 0.45, 0.75) * l * 1.4 + vec3(0.3, 0.6, 1.0) * edge * 0.8;
		} else if (mode == 2) {
			c = mix(vec3(0.03, 0.0, 0.12), vec3(0.25, 0.05, 0.45), clamp(l * 2.0, 0.0, 1.0)) + vec3(0.15, 0.1, 0.4) * edge * 0.5;
			// warm things (the overlays draw orange/yellow/white) stay hot
			vec3 raw = textureLod(screen, uv, 0.0).rgb;
			float hot = clamp((raw.r - raw.b) * 2.0 - 0.6, 0.0, 1.0);
			c = mix(c, raw, hot);
		} else {
			float v = 1.0 - l;
			c = vec3(0.3, 0.4, 0.37) * v * 0.32 + vec3(0.55, 0.85, 0.75) * edge * 0.9;
			vec3 raw = textureLod(screen, uv, 0.0).rgb;
			float glow = clamp((raw.g + raw.b - raw.r * 1.5) * 1.5 - 0.9, 0.0, 1.0);
			c = mix(c, raw, glow);
		}
		c *= 0.97 + 0.03 * sin(uv.y * 900.0 + time * 6.0); // faint scan
	}
	if (helmet > 0.0) {
		vec2 d = (uv - 0.5) * vec2(1.0, 0.82);
		float r = length(d);
		float vig = smoothstep(0.62, 0.42, r);
		c *= mix(1.0, vig, helmet);
		float rim = smoothstep(0.5, 0.62, r) * helmet;
		c = mix(c, vec3(0.35, 0.02, 0.06), rim * 0.65);
		c *= 1.0 - 0.04 * helmet * step(0.5, fract(uv.y * 240.0));
	}
	COLOR = vec4(c, 1.0);
}
