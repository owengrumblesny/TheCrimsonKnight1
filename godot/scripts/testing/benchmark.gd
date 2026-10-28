class_name Benchmark
extends Node
## Real-time benchmark (port of testing/benchmark.ts): the same six scenes, each warmed up 1.5 s then
## measured over 5 s of real frames with V-Sync off. Writes docs/benchmarks/godot-<renderer>-<preset>-<time>.json.
## Run:  godot --path . -- --bench --quality=low           (Forward+)
##       godot --rendering-method mobile --path . -- --bench --quality=low
## Results only mean something with the window on screen at its real size and the laptop on mains power.

signal finished(report: Dictionary)

const WARM := 1.5
const MEASURE := 5.0
const O := Citadel.OFFSET


## Blender (x, y, z) inside the Citadel file -> world (same mapping as the web build).
static func cit(x: float, y: float, z: float) -> Vector3:
	return Vector3(O.x + x, O.y + z, O.z - y)


var scenes := [
	{"name": "CR-X9 character close-up", "hero": Vector3(4, 0, 4), "camera": Vector3(5.6, 1.7, 6.3), "target": Vector3(4, 1.2, 4)},
	{"name": "Red Citadel command center", "hero": cit(32, 0, 5.1), "camera": cit(26, -6, 9), "target": cit(36, 6, 7)},
	{"name": "Red Citadel vehicle hangar", "hero": cit(-12, 56, 0.2), "camera": cit(-6, 50, 4), "target": cit(-18, 62, 1.5)},
	{"name": "New Gotham street", "hero": Vector3(30, 0, 1.5), "camera": Vector3(33, 1.9, 3.5), "target": Vector3(-20, 3, 0)},
	{"name": "New Gotham rooftop", "hero": Vector3(0, 0, 0), "camera": Vector3(22, 34, 22), "target": Vector3(-10, 8, -10)},
	{"name": "Dense city intersection", "hero": Vector3(0, 0, 0), "camera": Vector3(9, 5, 9), "target": Vector3(0, 1.5, 0)},
]
var game: Node
var active := false
var _i := -1
var _t := 0.0
var _warm := true
var _frames: PackedFloat32Array
var _draws := 0
var _prims := 0
var _last_us := 0
var _results: Array = []


func start() -> void:
	active = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	game.cam.active = false
	_i = -1
	_next()


func _next() -> void:
	_i += 1
	if _i >= scenes.size():
		_done()
		return
	var s: Dictionary = scenes[_i]
	game.player.teleport(s["hero"] + Vector3(0, 0.05, 0))
	game.player.heading = PI / 4
	var c: Camera3D = game.cam.camera
	c.global_position = s["camera"]
	c.look_at(s["target"], Vector3.UP)
	_t = 0.0
	_warm = true
	_frames = PackedFloat32Array()
	_draws = 0
	_prims = 0
	_last_us = Time.get_ticks_usec()


func _process(_dt: float) -> void:
	if not active:
		return
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	var s: Dictionary = scenes[_i]
	game.cam.camera.global_position = s["camera"]
	game.cam.camera.look_at(s["target"], Vector3.UP)
	_t += ms / 1000.0
	if _warm:
		if _t >= (WARM * 3 if _i == 0 else WARM): # the first scene also absorbs pipeline compilation
			_warm = false
			_t = 0.0
		return
	_frames.append(ms)
	_draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	if _t >= MEASURE:
		var n := _frames.size()
		var sorted := _frames.duplicate()
		sorted.sort()
		var total := 0.0
		for f in _frames:
			total += f
		var avg := total / n
		_results.append({"scene": s["name"], "frames": n, "avgFps": snappedf(1000.0 / avg, 0.1), "avgMs": snappedf(avg, 0.01),
			"worst1pctMs": snappedf(sorted[clampi(int(n * 0.99), 0, n - 1)], 0.01), "drawCalls": _draws / n, "trianglesK": _prims / n / 1000})
		print("[bench] %s: %.1f fps (1%% low %.1f ms), %d draws, %dk tris" % [s["name"], 1000.0 / avg,
			sorted[clampi(int(n * 0.99), 0, n - 1)], _draws / n, _prims / n / 1000])
		_next()


func _done() -> void:
	active = false
	var vp := get_viewport()
	var size := DisplayServer.window_get_size()
	var report := {
		"engine": "Godot %s" % Engine.get_version_info()["string"],
		"renderer": RenderingServer.get_current_rendering_method(),
		"when": Time.get_datetime_string_from_system(true) + "Z",
		"quality": game.stage.quality,
		"gpu": RenderingServer.get_video_adapter_name(),
		"window": "%dx%d" % [size.x, size.y],
		"internalResolution": "%dx%d" % [int(size.x * vp.scaling_3d_scale), int(size.y * vp.scaling_3d_scale)],
		"results": _results,
	}
	var path := "res://docs/benchmarks/godot-%s-%s-%d.json" % [report["renderer"], report["quality"], Time.get_unix_time_from_system()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		print("[bench] wrote ", ProjectSettings.globalize_path(path))
	finished.emit(report)
