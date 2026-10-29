class_name Quality
## Per-setting overrides on top of a preset (Settings > Graphics). Each option: [label, [[choice label, {preset keys}], ...]].
## Index 0 of every option is "Preset" (no override).
const OPTIONS := {
	"resolution": ["Resolution scale", [["Preset", {}], ["50%", {"render_height": 540, "fsr": true}], ["67%", {"render_height": 720, "fsr": true}],
		["83%", {"render_height": 900, "fsr": true}], ["100%", {"render_height": 0, "fsr": false}]]],
	"shadows": ["Shadow quality", [["Preset", {}], ["Off", {"shadows": false}], ["Low", {"shadows": true, "shadow_map": 1024, "shadow_range": 16.0, "shadow_splits": 1, "soft_shadows": 0}],
		["Medium", {"shadows": true, "shadow_map": 2048, "shadow_range": 24.0, "shadow_splits": 2, "soft_shadows": 1}],
		["High", {"shadows": true, "shadow_map": 4096, "shadow_range": 36.0, "shadow_splits": 4, "soft_shadows": 2}]]],
	"draw": ["Draw distance", [["Preset", {}], ["Near (220 m)", {"draw_distance": 220.0, "lod_scale": 0.6}], ["Medium (320 m)", {"draw_distance": 320.0, "lod_scale": 0.8}],
		["Far (480 m)", {"draw_distance": 480.0, "lod_scale": 1.0}], ["Max (700 m)", {"draw_distance": 700.0, "lod_scale": 1.25}]]],
	"reflections": ["Reflections", [["Preset", {}], ["Off", {"ssr": false}], ["Screen-space", {"ssr": true}]]],
	"post": ["Post-processing", [["Preset", {}], ["Minimal", {"bloom": false, "ssao": false, "ssil": false, "volumetric_fog": false}],
		["Standard", {"bloom": true, "ssao": false, "ssil": false, "volumetric_fog": false}], ["Full", {"bloom": true, "ssao": true, "ssil": true, "volumetric_fog": true}]]],
	"textures": ["Texture quality", [["Preset", {}], ["Low", {"anisotropy": 0, "mesh_lod": 4.0}], ["Medium", {"anisotropy": 2, "mesh_lod": 2.0}], ["High", {"anisotropy": 4, "mesh_lod": 1.0}]]],
	"effects": ["Effects quality", [["Preset", {}], ["Low", {"rain": 0.25, "dynamic_lights": 3}], ["Medium", {"rain": 0.5, "dynamic_lights": 4}], ["High", {"rain": 1.0, "dynamic_lights": 6}]]],
}


## Preset q with the player's per-setting overrides ({option: choice index}) applied.
static func resolve(q: String, overrides: Dictionary) -> Dictionary:
	var p: Dictionary = PRESETS[q].duplicate()
	for k in overrides:
		if OPTIONS.has(k):
			var i := int(overrides[k])
			if i > 0 and i < OPTIONS[k][1].size():
				p.merge(OPTIONS[k][1][i][1], true)
	return p
## Graphics presets (port of render/quality.ts). LOW targets the laptop (Ryzen 5 7520U / Radeon 610M,
## 720p, 30 FPS goal) and keeps the crimson identity; SSAO/SSIL/SDFGI/volumetric fog/MSAA are off there.
## MEDIUM is the "average laptop" step up from LOW (no MSAA/SSAO, FXAA). HIGH/ULTRA are desktop presets.
## Measured on the target laptop: docs/PERFORMANCE_GODOT.md.

const ORDER := ["low", "medium", "high", "ultra"]

const PRESETS := {
	"low": {
		"render_height": 720, "fsr": true, "shadows": true, "shadow_map": 1024, "shadow_range": 16.0, "shadow_splits": 1,
		"soft_shadows": 0, "draw_distance": 220.0, "fog_density": 0.016, "dynamic_lights": 3, "light_shadows": false,
		"bloom": false, "rain": 0.3, "anisotropy": 1, "lod_scale": 0.6, "hero_min_lod": 1, "msaa": 0, "mesh_lod": 4.0,
		"ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "volumetric_fog": false, "taa": false,
	},
	"medium": {
		"render_height": 810, "fsr": true, "shadows": true, "shadow_map": 2048, "shadow_range": 22.0, "shadow_splits": 2,
		"soft_shadows": 0, "draw_distance": 300.0, "fog_density": 0.014, "dynamic_lights": 4, "light_shadows": false,
		"bloom": true, "rain": 0.5, "anisotropy": 2, "lod_scale": 0.75, "hero_min_lod": 1, "msaa": 0, "fxaa": true, "mesh_lod": 2.5,
		"ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "volumetric_fog": false, "taa": false,
	},
	"high": {
		"render_height": 0, "fsr": false, "shadows": true, "shadow_map": 4096, "shadow_range": 34.0, "shadow_splits": 4,
		"soft_shadows": 2, "draw_distance": 600.0, "fog_density": 0.011, "dynamic_lights": 10, "light_shadows": true,
		"bloom": true, "rain": 1.0, "anisotropy": 3, "lod_scale": 1.0, "hero_min_lod": 0, "msaa": 2, "mesh_lod": 1.0,
		"ssao": true, "ssil": false, "ssr": true, "sdfgi": false, "volumetric_fog": true, "taa": false,
	},
	"ultra": {
		"render_height": 0, "fsr": false, "shadows": true, "shadow_map": 4096, "shadow_range": 45.0, "shadow_splits": 4,
		"soft_shadows": 3, "draw_distance": 900.0, "fog_density": 0.009, "dynamic_lights": 12, "light_shadows": true,
		"bloom": true, "rain": 1.0, "anisotropy": 4, "lod_scale": 1.4, "hero_min_lod": 0, "msaa": 2, "mesh_lod": 0.5,
		"ssao": true, "ssil": true, "ssr": true, "sdfgi": true, "volumetric_fog": true, "taa": true,
	},
}


## Integrated / low-power GPUs default to LOW; everything else to HIGH.
static func detect_default() -> String:
	var gpu := RenderingServer.get_video_adapter_name()
	var re := RegEx.create_from_string("(?i)610M|Radeon\\(TM\\) Graphics|Radeon Graphics|Vega \\d|Intel|UHD|Iris|Mali|Adreno|Apple|llvmpipe|SwiftShader")
	if re.search(gpu) or RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return "low"
	return "high"
