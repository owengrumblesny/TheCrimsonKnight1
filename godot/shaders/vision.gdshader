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
		} else if (mode == 4) {
			// night vision: amplified light, green phosphor, grain, lights bloom
			float amp = pow(clamp(l * 3.2, 0.0, 1.0), 0.55);
			float grain = fract(sin(dot(uv * 900.0 + time * 37.0, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
			c = vec3(0.12, 1.0, 0.35) * (amp + grain * 0.08) + vec3(0.6, 1.0, 0.7) * smoothstep(0.75, 1.0, l) * 0.6;
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
		// slight colour fringing toward the visor edge (curved glass)
		float ca = smoothstep(0.25, 0.6, r) * 0.004 * helmet;
		vec3 fr = vec3(textureLod(screen, uv + d * ca * 4.0, 0.0).r, c.g, textureLod(screen, uv - d * ca * 4.0, 0.0).b);
		c = mode == 0 ? mix(c, fr, 0.8) : c;
		float vig = smoothstep(0.64, 0.4, r);
		c *= mix(1.0, vig, helmet);
		// glowing crimson rim that breathes
		float pulse = 0.75 + 0.25 * sin(time * 2.2);
		float rim = smoothstep(0.47, 0.6, r) * helmet;
		c = mix(c, vec3(0.55, 0.03, 0.08) * pulse, rim * 0.7);
		c += vec3(1.0, 0.15, 0.25) * smoothstep(0.035, 0.0, abs(r - 0.5)) * 0.35 * pulse * helmet;
		// hex lattice in the periphery
		vec2 hp = uv * vec2(64.0, 36.0);
		vec2 hq = vec2(hp.x + 0.5 * mod(floor(hp.y), 2.0), hp.y);
		vec2 hf = abs(fract(hq) - 0.5);
		float hex = smoothstep(0.46, 0.5, max(hf.x * 1.15 + hf.y * 0.6, hf.y * 1.2));
		c += vec3(0.35, 0.85, 1.0) * hex * smoothstep(0.32, 0.55, r) * 0.08 * helmet;
		// scan sweep every 5 s
		float sweep = fract(time * 0.2);
		c += vec3(0.4, 0.9, 1.0) * smoothstep(0.012, 0.0, abs(uv.y - sweep)) * 0.12 * helmet;
		c *= 1.0 - 0.035 * helmet * step(0.5, fract(uv.y * 240.0));
	}
	COLOR = vec4(c, 1.0);
}
