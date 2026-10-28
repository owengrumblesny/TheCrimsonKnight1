class_name AnimDebug
extends PanelContainer
## Animation debug panel (port of ui/AnimDebug.ts), toggled with the sandboxMenu key (`).
## Lists every CK_* clip; picking one freezes locomotion and loops that clip on the CR-X9, beside the
## board key-pose art for it (config/animation_graph.json referenceImages) played as a flipbook.

var player: Player
var clip := "" # clip being previewed ("" = normal gameplay)
var _list: VBoxContainer
var _title: Label
var _info: Label
var _art: TextureRect
var _frames: Array = []
var _frame_t := 0.0
var _frame_i := 0
var _restore := {} # Animation -> original loop mode


func _ready() -> void:
	name = "AnimDebug"
	theme = CKUI.theme()
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	CKUI.place(self, Vector4(1, 0, 1, 1), Vector4(-430, 70, -18, -110))
	var v := VBoxContainer.new()
	add_child(v)
	v.add_child(CKUI.label("ANIMATION DEBUG", 13, CKUI.BRIGHT, true))
	_title = CKUI.label("Pick a clip", 18, CKUI.TEXT, true)
	v.add_child(_title)
	_info = CKUI.label("", 12, CKUI.MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_info)
	_art = CKUI.image_rect(null, Vector2(390, 180))
	v.add_child(_art)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	var stop := CKUI.button("Back to gameplay", "back", "`", func(): select(""))
	stop.custom_minimum_size = Vector2(0, 38)
	v.add_child(stop)


func toggle() -> void:
	visible = not visible
	if visible and _list.get_child_count() == 0:
		for name in player.hero.clip_names():
			var meta := CKData.hero_clip(name)
			var b := Button.new()
			b.text = "%s  ·  %.2f s%s" % [name, meta.get("duration", 0.0), "  loop" if meta.get("loop", false) else ""]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(func(): select(name))
			_list.add_child(b)
	if not visible:
		select("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


func select(name: String) -> void:
	clip = name
	player.frozen = name != ""
	for a in _restore:
		a.loop_mode = _restore[a]
	_restore.clear()
	_frames.clear()
	_art.texture = null
	if name == "":
		_title.text = "Pick a clip"
		_info.text = ""
		player.hero.play("CK_Idle", 0.2)
		return
	var meta := CKData.hero_clip(name)
	var a: Animation = player.hero.anim.get_animation(name)
	_restore[a] = a.loop_mode
	a.loop_mode = Animation.LOOP_LINEAR # preview loops even one-shot clips; restored when leaving the clip
	player.hero.play(name, 0.15, 1.0, true)
	_title.text = name
	_info.text = "%s\n%d frames @ %d fps · %s" % [meta.get("description", ""), meta.get("frames", 0), meta.get("fps", 30),
		"loop" if meta.get("loop", false) else "one-shot (looped here)"]
	var refs: Dictionary = CKData.json("animation_graph")["referenceImages"]
	for id in refs.get(name, []):
		for img in CKData.json("image_catalog")["images"]:
			if img["id"] == id:
				for f in img.get("frames", [img["file"]]):
					var t := CKUI.tex("res://" + f)
					if t:
						_frames.append(t)
	_frame_i = 0
	_frame_t = 0.0
	_art.texture = _frames[0] if _frames else null


func _process(dt: float) -> void:
	if not visible or _frames.size() < 2:
		return
	_frame_t += dt
	if _frame_t > 0.12:
		_frame_t = 0.0
		_frame_i = (_frame_i + 1) % _frames.size()
		_art.texture = _frames[_frame_i]
