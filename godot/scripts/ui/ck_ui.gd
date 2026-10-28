class_name CKUI
## Shared UI helpers: the Crimson Knight theme (colours from game/src/ui/ui.css), icon and keycap lookup
## from the UI pack (CRIMSON_KNIGHT_UI_PACK, same files as the web build's public/ui), and widget builders.

const BG := Color("#0c0b12")
const PANEL := Color("#17121c")
const RED := Color("#d42a40")
const BRIGHT := Color("#ff405d")
const TEXT := Color("#f4eef1")
const MUTED := Color("#b9a9b0")
const LINE := Color("#3a2128")
const BORDER := Color("#652032")
const PACK := "res://CRIMSON_KNIGHT_UI_PACK/"

static var _icons := {}
static var _tex := {}
static var _theme: Theme


static func icon_entry(id: String) -> Dictionary:
	if _icons.is_empty():
		for e in CKData.data("icon_manifest")["icons"]:
			_icons[e["id"]] = e
	return _icons.get(id, _icons.get("notification", {}))


static func has_icon(id: String) -> bool:
	icon_entry("")
	return _icons.has(id)


## role "circle" = framed circular PNG (hotbar slots), "glyph" = transparent symbol for cards/menus.
static func icon(id: String, role := "glyph") -> Texture2D:
	var e := icon_entry(id)
	var path: String = e.get("circlePNG", e.get("glyphPNG", "")) if role == "circle" else e.get("glyphPNG", "")
	return tex(PACK + path)


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


static func board(id: String) -> Texture2D:
	return tex(CKData.board_image_path(id))


## Keycap texture for a web key code (Digit1, KeyQ, Tab, Mouse0...), or null when the pack has none.
static func keycap(code: String) -> Texture2D:
	var map := {"Tab": "key_tab", "ShiftLeft": "key_shift", "ShiftRight": "key_shift", "Space": "key_space", "Escape": "key_esc",
		"ControlLeft": "key_ctrl", "ControlRight": "key_ctrl", "Mouse0": "key_mouse1", "Mouse2": "key_mouse2"}
	var id: String = map.get(code, "")
	if id == "" and code.begins_with("Digit"):
		id = "key_" + code.substr(5)
	elif id == "" and code.begins_with("Key") and code.length() == 4:
		id = "key_" + code.substr(3).to_lower()
	return icon(id) if has_icon(id) else null


## Short human label for a key code: Digit1 -> 1, KeyQ -> Q, Mouse0 -> LMB.
static func key_label(code: String) -> String:
	if code.begins_with("Digit"):
		return code.substr(5)
	if code.begins_with("Key") and code.length() == 4:
		return code.substr(3)
	return {"Space": "Space", "Tab": "Tab", "Escape": "Esc", "ShiftLeft": "Shift", "ShiftRight": "R-Shift", "ControlLeft": "Ctrl",
		"CapsLock": "Caps", "Backquote": "`", "Mouse0": "LMB", "Mouse1": "MMB", "Mouse2": "RMB"}.get(code, code)


static func box(bg: Color, border := BORDER, radius := 10, width := 1, pad := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.5))
	t.set_stylebox("normal", "Button", box(Color("#211923"), Color("#57313b"), 10, 1, 10))
	t.set_stylebox("hover", "Button", box(Color("#2b1d27"), BRIGHT, 10, 1, 10))
	t.set_stylebox("pressed", "Button", box(Color("#3d1823"), BRIGHT, 10, 2, 10))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Color.WHITE, 10, 2, 10))
	t.set_stylebox("disabled", "Button", box(Color("#151117"), Color("#2c1a20"), 10, 1, 10))
	t.set_stylebox("panel", "PanelContainer", box(Color(PANEL, 0.96), BORDER, 14, 1, 16))
	t.set_stylebox("normal", "LineEdit", box(Color("#0f0c12"), Color("#57313b"), 8, 1, 8))
	t.set_stylebox("focus", "LineEdit", box(Color("#0f0c12"), BRIGHT, 8, 1, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("normal", "OptionButton", box(Color("#0f0c12"), Color("#57313b"), 8, 1, 8))
	t.set_stylebox("hover", "OptionButton", box(Color("#1a1218"), BRIGHT, 8, 1, 8))
	t.set_stylebox("pressed", "OptionButton", box(Color("#1a1218"), BRIGHT, 8, 1, 8))
	t.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), Color.WHITE, 8, 2, 8))
	t.set_stylebox("panel", "PopupMenu", box(PANEL, BORDER, 8, 1, 6))
	t.set_color("font_color", "CheckBox", TEXT)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", box(Color(0, 0, 0, 0), Color.WHITE, 6, 1, 2))
	t.set_stylebox("slider", "HSlider", box(Color("#241319"), Color("#4c1e29"), 4, 1, 3))
	t.set_stylebox("grabber_area", "HSlider", box(RED, RED, 4, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(BRIGHT, BRIGHT, 4, 0, 3))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("panel", "TooltipPanel", box(PANEL, BORDER, 8, 1, 8))
	_theme = t
	return t


static func label(text: String, size := 15, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_constant_override("outline_size", 1)
		l.add_theme_color_override("font_outline_color", color)
	return l


## Menu button: icon + title + optional right-aligned sub text. callback null = disabled.
static func button(text: String, icon_id := "", sub := "", callback = null, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320, 44)
	if icon_id != "":
		b.icon = icon(icon_id)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 26)
	if primary:
		b.add_theme_stylebox_override("normal", box(Color("#3d1823"), BRIGHT, 10, 1, 10))
	if sub != "":
		var s := label(sub, 12, MUTED)
		s.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		s.offset_left = -170
		s.offset_right = -12
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(s)
	if callback is Callable:
		b.pressed.connect(callback)
	else:
		b.disabled = true
	b.focus_mode = Control.FOCUS_ALL
	return b


static func section(text: String) -> Label:
	var l := label(text.to_upper(), 12, BRIGHT)
	l.add_theme_constant_override("line_spacing", 4)
	return l


## Anchor a control: anchors (left, top, right, bottom) in 0..1 and pixel offsets from them.
static func place(c: Control, a: Vector4, o: Vector4) -> void:
	c.anchor_left = a.x
	c.anchor_top = a.y
	c.anchor_right = a.z
	c.anchor_bottom = a.w
	c.offset_left = o.x
	c.offset_top = o.y
	c.offset_right = o.z
	c.offset_bottom = o.w


static func image_rect(t: Texture2D, size: Vector2, cover := false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## "c_detail_chest" / "world/b_citadel_command_center" -> readable caption
static func pretty(id: String) -> String:
	var s := id.get_file()
	var re := RegEx.create_from_string("^[a-z0-9]+_")
	s = re.sub(s, "", false)
	for p in ["scene_", "citadel_", "turnaround_", "helmet_", "armor_", "detail_"]:
		s = s.trim_prefix(p)
	return s.trim_suffix("_wide").replace("_", " ")
