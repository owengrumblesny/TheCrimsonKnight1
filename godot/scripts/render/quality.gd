class_name Quality
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
