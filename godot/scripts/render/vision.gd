class_name Vision
extends CanvasLayer
## CR-X9 helmet vision (N cycles): Normal → Knight vision → Thermal → X-ray.
##  - A full-screen shader recolours the view (godot/shaders/vision.gdshader).
##  - People get an overlay material that draws through walls: Knight vision shows hostiles orange and
##    civilians blue; thermal shows every body hot (yellow-white core, red edge); X-ray shows hostiles as pale
##    cyan "scans" so you can track them inside buildings.
##  - The helmet camera (H) adds the visor frame from the same shader.

const MODES := ["Normal", "Knight vision", "Thermal", "X-ray"]

var mode := 0
var helmet := false
## nodes to tag: Callable returning [[Node3D, hostile: bool], ...]
var sources: Callable
var _rect: ColorRect
var _mat: ShaderMaterial
var _over := {} # key -> overlay material
var _tagged := {} # instance_id -> Node3D
var _refresh_t := 0.0
var _t := 0.0


func _ready() -> void:
	layer = 0 # under the HUD
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://godot/shaders/vision.gdshader")
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func cycle() -> String:
	set_mode((mode + 1) % MODES.size())
	return MODES[mode]


func set_mode(m: int) -> void:
	mode = m
	_mat.set_shader_parameter("mode", mode)
	_refresh_t = 0.0
	if mode == 0:
		_clear()
	_rect.visible = mode > 0 or helmet


func set_helmet(on: bool) -> void:
	helmet = on
	_mat.set_shader_parameter("helmet", 1.0 if on else 0.0)
	_rect.visible = mode > 0 or helmet


func _process(dt: float) -> void:
	_t += dt
	_mat.set_shader_parameter("time", _t)
	if mode == 0 or not sources.is_valid():
		return
	_refresh_t -= dt
	if _refresh_t > 0.0:
		return
	_refresh_t = 0.4
	var seen := {}
	for pair in sources.call():
		var n: Node3D = pair[0]
		if not is_instance_valid(n):
			continue
		var hostile: bool = pair[1]
		var mat := _overlay(hostile)
		seen[n.get_instance_id()] = true
		_tagged[n.get_instance_id()] = n
		for mi in n.find_children("*", "GeometryInstance3D", true, false):
			if mi.material_overlay != mat:
				mi.material_overlay = mat
	# untag anyone no longer listed (freed, out of range)
	for id in _tagged.keys():
		if not seen.has(id):
			var n2 = _tagged[id]
			if is_instance_valid(n2):
				for mi in n2.find_children("*", "GeometryInstance3D", true, false):
					mi.material_overlay = null
			_tagged.erase(id)


func _clear() -> void:
	for id in _tagged:
		var n = _tagged[id]
		if is_instance_valid(n):
			for mi in n.find_children("*", "GeometryInstance3D", true, false):
				mi.material_overlay = null
	_tagged.clear()


## Fresnel glow drawn on top of everything (no depth test), coloured per mode and side.
func _overlay(hostile: bool) -> ShaderMaterial:
	var key := "%d_%s" % [mode, hostile]
	if _over.has(key):
		return _over[key]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, depth_test_disabled, blend_add, cull_back, shadows_disabled;
uniform vec3 rim_col;
uniform vec3 core_col;
uniform float core_amt;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 c = mix(core_col * core_amt, rim_col, pow(f, 1.6));
	ALBEDO = c;
	ALPHA = 0.85;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	match mode:
		1:
			m.set_shader_parameter("rim_col", Color("#ff8a1e") if hostile else Color("#4aa8ff"))
			m.set_shader_parameter("core_col", Color("#ff5a10") if hostile else Color("#1e5aa8"))
			m.set_shader_parameter("core_amt", 0.25)
		2:
			m.set_shader_parameter("rim_col", Color("#ff3010"))
			m.set_shader_parameter("core_col", Color("#fff2a0"))
			m.set_shader_parameter("core_amt", 1.0)
		3:
			m.set_shader_parameter("rim_col", Color("#bff8ff") if hostile else Color("#5a8a80"))
			m.set_shader_parameter("core_col", Color("#3ab8c8") if hostile else Color("#203830"))
			m.set_shader_parameter("core_amt", 0.6)
	_over[key] = m
	return m
