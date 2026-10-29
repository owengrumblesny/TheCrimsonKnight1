class_name RedPanel
extends Control
## R.E.D.'s comm panel (left, under the vitals): a pulsing "eye" while she speaks, her status (listening /
## thinking / active buffs) and the last few lines of conversation in a translucent visor panel. Lines are
## RichTextLabels with fit_content, so wrapped lines take their real height and never overlap. Older lines dim,
## and the whole panel fades out when nobody has spoken for a while. Enter opens a field to type to her.

signal submitted(text: String)
signal chat_open_changed(open: bool)

const KEEP := 3
const WIDTH := 360.0
const IDLE_FADE := 12.0

var speaking := false
var _eye: Control
var _status: Label
var _box: PanelContainer
var _log: VBoxContainer
var _field: LineEdit
var _t := 0.0
var _quiet := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.05, 0.62)
	sb.border_color = Color(1, 0.3, 0.38, 0.55)
	sb.border_width_left = 2
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	_box.add_theme_stylebox_override("panel", sb)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.custom_minimum_size.x = WIDTH
	_box.size.x = WIDTH
	add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	_eye = Control.new()
	_eye.custom_minimum_size = Vector2(20, 20)
	_eye.draw.connect(_draw_eye)
	head.add_child(_eye)
	var name_l := CKUI.label("R.E.D.", 13, CKUI.BRIGHT, true)
	head.add_child(name_l)
	_status = CKUI.label("", 11, CKUI.MUTED)
	_status.clip_text = true
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_status)
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 4)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_log)
	_field = LineEdit.new()
	_field.placeholder_text = "Talk to R.E.D.  (Enter send · Esc cancel)"
	_field.custom_minimum_size = Vector2(WIDTH - 20, 28)
	_field.visible = false
	_field.process_mode = Node.PROCESS_MODE_ALWAYS
	_field.add_theme_stylebox_override("normal", CKUI.box(Color(0.06, 0.04, 0.07, 0.92), CKUI.RED, 6, 1, 6))
	_field.text_submitted.connect(_on_submit)
	v.add_child(_field)


func _draw_eye() -> void:
	var c := _eye.size / 2
	var pulse := 0.5 + 0.5 * sin(_t * 14.0) if speaking else 0.0
	_eye.draw_circle(c, 9.0, Color(0.1, 0.02, 0.04, 0.9))
	_eye.draw_circle(c, 5.5 + pulse * 2.5, CKUI.BRIGHT.lerp(Color(1, 0.75, 0.8), pulse * 0.5))
	_eye.draw_arc(c, 9.0, 0, TAU, 24, CKUI.RED, 1.5, true)


func _process(dt: float) -> void:
	_t += dt
	_eye.queue_redraw()
	# the panel shrinks to its content (PanelContainer keeps the largest size otherwise)
	_box.size = Vector2(WIDTH, 0)
	_quiet = 0.0 if (speaking or _field.visible or _status.text != "") else _quiet + dt
	var want := 1.0 if _quiet < IDLE_FADE or _log.get_child_count() == 0 else 0.0
	if _log.get_child_count() == 0 and not _field.visible and _status.text == "":
		want = 0.55 # just the R.E.D. tag
	modulate.a = move_toward(modulate.a, want, dt * 1.5)


func set_status(text: String) -> void:
	_status.text = text


func add_line(who: String, text: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = false
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 22
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 13)
	l.add_theme_color_override("default_color", Color("#ffe0e4") if who == "red" else CKUI.MUTED)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.text = ("› " if who == "red" else "You: ") + text
	_log.add_child(l)
	while _log.get_child_count() > KEEP:
		_log.get_child(0).free()
	# older lines dim
	var n := _log.get_child_count()
	for i in n:
		_log.get_child(i).modulate.a = 1.0 if i == n - 1 else 0.6
	_quiet = 0.0
	modulate.a = 1.0


func is_chat_open() -> bool:
	return _field.visible


func open_chat() -> void:
	_field.visible = true
	_field.text = ""
	_field.grab_focus()
	modulate.a = 1.0
	chat_open_changed.emit(true)


func close_chat() -> void:
	if not _field.visible:
		return
	_field.release_focus()
	_field.visible = false
	chat_open_changed.emit(false)


func _on_submit(text: String) -> void:
	close_chat()
	if text.strip_edges() != "":
		submitted.emit(text)


func _input(e: InputEvent) -> void:
	if _field.visible and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		close_chat()
		get_viewport().set_input_as_handled()
