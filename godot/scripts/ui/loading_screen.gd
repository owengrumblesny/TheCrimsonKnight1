class_name LoadingScreen
extends CanvasLayer
## Loading screen (port of ui/loading.ts): cycling city / Citadel / suit art from the boards, the current
## step and a progress bar, plus the CR-X9 idle key-pose flipbook. main.gd awaits step() between world-
## building stages so each one gets a drawn frame.

const ART := ["world/c_downtown_wide", "world/c_citadel_main_hangar_wide", "hero/c_turnaround_front", "world/c_rooftops_wide"]

var _bg: TextureRect
var _label: Label
var _bar: ProgressBar
var _pose: TextureRect
var _frames: Array = []
var _t := 0.0
var _art_i := 0
var _steps := 1
var _done := 0


func _init(total_steps: int) -> void:
	_steps = total_steps
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = CKUI.theme()
	add_child(root)
	var black := ColorRect.new()
	black.color = CKUI.BG
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(black)
	_bg = CKUI.image_rect(CKUI.board(ART[0]), Vector2.ZERO, true)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.modulate = Color(0.55, 0.5, 0.55)
	root.add_child(_bg)
	var col := VBoxContainer.new()
	CKUI.place(col, Vector4(0, 1, 0, 1), Vector4(60, -170, 700, -50))
	root.add_child(col)
	col.add_child(CKUI.label("CRIMSON KNIGHT", 40, CKUI.TEXT, true))
	col.add_child(CKUI.label("EARTH-RED · OWEN ENTERPRISES", 13, CKUI.BRIGHT, true))
	_label = CKUI.label("Starting…", 14, CKUI.MUTED)
	col.add_child(_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(600, 6)
	_bar.add_theme_stylebox_override("background", CKUI.box(Color("#241319"), Color("#4c1e29"), 3, 1, 0))
	_bar.add_theme_stylebox_override("fill", CKUI.box(CKUI.BRIGHT, CKUI.BRIGHT, 3, 0, 0))
	col.add_child(_bar)
	_pose = CKUI.image_rect(null, Vector2(90, 200))
	CKUI.place(_pose, Vector4(1, 1, 1, 1), Vector4(-140, -250, -40, -40))
	root.add_child(_pose)
	for img in CKData.json("image_catalog")["images"]:
		if img["id"] == "animations/a_idle":
			for f in img.get("frames", [img["file"]]):
				var t := CKUI.tex("res://" + f)
				if t:
					_frames.append(t)


## Show the next step and let it draw before the caller does the heavy work.
func step(text: String) -> void:
	_label.text = "Loading " + text + "…"
	_bar.value = 100.0 * _done / _steps
	_done += 1
	await get_tree().process_frame
	await get_tree().process_frame


func finish() -> void:
	_bar.value = 100
	var tw := create_tween()
	for c in get_children():
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)


func _process(dt: float) -> void:
	_t += dt
	if _frames.size() > 1:
		_pose.texture = _frames[int(_t * 8) % _frames.size()]
	if int(_t / 2.5) != _art_i:
		_art_i = int(_t / 2.5)
		_bg.texture = CKUI.board(ART[_art_i % ART.size()])
