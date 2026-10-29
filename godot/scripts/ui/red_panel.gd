class_name RedPanel
extends Control
## R.E.D.'s comm panel (left of the screen, under the vitals): a pulsing red "eye" while she speaks, her status
## (listening / thinking / active buffs) and the last few lines of conversation, which fade out. Enter opens a
## text field to type to her.

signal submitted(text: String)
signal chat_open_changed(open: bool)

const KEEP := 4
const FADE_AFTER := 10.0

var speaking := false
var _eye: Control
var _status: Label
var _log: VBoxContainer
var _field: LineEdit
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	_eye = Control.new()
	_eye.custom_minimum_size = Vector2(22, 22)
	_eye.draw.connect(_draw_eye)
	head.add_child(_eye)
	var name_l := CKUI.label("R.E.D.", 13, CKUI.BRIGHT, true)
	name_l.add_theme_color_override("font_shadow_color", Color.BLACK)
	head.add_child(name_l)
	_status = CKUI.label("", 12, CKUI.MUTED)
	_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	head.add_child(_status)
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 3)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_log)
	_field = LineEdit.new()
	_field.placeholder_text = "Talk to R.E.D. (Enter to send, Esc to cancel)"
	_field.custom_minimum_size = Vector2(380, 30)
	_field.visible = false
	_field.process_mode = Node.PROCESS_MODE_ALWAYS
	_field.add_theme_stylebox_override("normal", CKUI.box(Color(0.06, 0.04, 0.07, 0.92), CKUI.RED, 6, 1, 6))
	_field.text_submitted.connect(_on_submit)
	v.add_child(_field)


func _draw_eye() -> void:
	var c := _eye.size / 2
	var pulse := 0.5 + 0.5 * sin(_t * 14.0) if speaking else 0.0
	_eye.draw_circle(c, 10.0, Color(0.1, 0.02, 0.04, 0.9))
	_eye.draw_circle(c, 6.0 + pulse * 2.5, CKUI.BRIGHT.lerp(Color(1, 0.75, 0.8), pulse * 0.5))
	_eye.draw_arc(c, 10.0, 0, TAU, 24, CKUI.RED, 1.5, true)


func _process(dt: float) -> void:
	_t += dt
	_eye.queue_redraw()


func set_status(text: String) -> void:
	_status.text = text


func add_line(who: String, text: String) -> void:
	var l := CKUI.label(("You: " if who == "you" else "") + text, 13, CKUI.TEXT if who == "red" else CKUI.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	if who == "red":
		l.add_theme_color_override("font_color", Color("#ffd6dc"))
	_log.add_child(l)
	while _log.get_child_count() > KEEP:
		_log.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(FADE_AFTER)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


func is_chat_open() -> bool:
	return _field.visible


func open_chat() -> void:
	_field.visible = true
	_field.text = ""
	_field.grab_focus()
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


func _input_event_cancel(e: InputEvent) -> bool:
	return e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE


func _input(e: InputEvent) -> void:
	if _field.visible and _input_event_cancel(e):
		close_chat()
		get_viewport().set_input_as_handled()
