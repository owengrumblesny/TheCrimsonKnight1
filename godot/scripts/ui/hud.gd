class_name Hud
extends Control
## In-game HUD (port of ui/HudWidgets.ts + ui/Hotbar.ts): top-left vitals with the helmet portrait,
## top-centre compass, top-right notifications, bottom-right selected item, crosshair, interact prompt,
## and the bottom-centre 8-slot hotbar with live key labels, quantities and cooldown sweeps.

signal slot_clicked(index: int)

const CARD := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var inventory: Inventory
var vitals: Vitals
var widgets: Control # everything hidden by "Show HUD" / photo mode
var _meters := {}
var _strip: Control
var _notes: VBoxContainer
var _sel_title: Label
var _sel_sub: Label
var _crosshair: TextureRect
var _prompt: HBoxContainer
var _prompt_key := ""
var _slots: Array = [] # {button, icon, key, qty, badge, cd}
var _bar: PanelContainer
var _marker: Control
## extra status for the selected item (weapon ammo / reload), set by the game each frame
var weapon_status := ""
## [title, sub] shown in the selected-item card while driving; the hotbar hides
var vehicle_text: Array = []
var director: Director
var _stars: Label
var _rank: Label
var _objective: Label
var _flash: ColorRect
var _compass_marks: Control
## grapple target indicator: world point to mark (null = none) and the camera to project it
var grapple_point = null
var camera: Camera3D
var _grapple_mark: Control
var _combo: Label
var _reticle: Control
var _hints: HBoxContainer
var _hints_key := ""
var hints_enabled := true
## reticle state, set by the game: weapons (bloom / under_crosshair / locked) and the camera for projection
var weapons: Weapons
var stage: Stage
## helmet view: the HUD is projected on the visor (tint + head-turn lag)
var visor := false
var _sway := Vector2.ZERO
var _last_cam_basis := Basis()
var minimap: MiniMap


func _ready() -> void:
	name = "Hud"
	theme = CKUI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	widgets = Control.new()
	widgets.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	widgets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(widgets)
	_build_status()
	_build_compass()
	_build_world_widgets()
	_grapple_mark = Control.new()
	_grapple_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grapple_mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grapple_mark.draw.connect(_draw_grapple_mark)
	widgets.add_child(_grapple_mark)
	_combo = CKUI.label("", 30, CKUI.BRIGHT, true)
	_combo.add_theme_color_override("font_shadow_color", Color.BLACK)
	CKUI.place(_combo, Vector4(.5, .5, .5, .5), Vector4(70, -60, 260, -20))
	widgets.add_child(_combo)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	_hints.add_theme_constant_override("separation", 16)
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CKUI.place(_hints, Vector4(.5, 1, .5, 1), Vector4(-420, -164, 420, -134))
	widgets.add_child(_hints)
	minimap = MiniMap.new()
	CKUI.place(minimap, Vector4(0, 1, 0, 1), Vector4(18, -18 - MiniMap.SIZE, 18 + MiniMap.SIZE, -18))
	widgets.add_child(minimap)
	_build_selected()
	_build_hotbar()
	_crosshair = CKUI.image_rect(CKUI.icon("crosshair"), Vector2(36, 36))
	CKUI.place(_crosshair, Vector4(.5, .5, .5, .5), Vector4(-18, -18, 18, 18))
	_crosshair.visible = false
	_crosshair.modulate.a = 0.0 # kept for layout; the reticle below is drawn live
	widgets.add_child(_crosshair)
	_reticle = Control.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reticle.draw.connect(_draw_reticle)
	widgets.add_child(_reticle)
	_marker = HitMarker.new()
	CKUI.place(_marker, Vector4(.5, .5, .5, .5), Vector4(-20, -20, 20, 20))
	_marker.modulate.a = 0.0
	widgets.add_child(_marker)
	_prompt = HBoxContainer.new()
	CKUI.place(_prompt, Vector4(.5, 1, .5, 1), Vector4(-200, -152, 200, -118))
	_prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt.visible = false
	widgets.add_child(_prompt)
	_notes = VBoxContainer.new()
	CKUI.place(_notes, Vector4(1, 0, 1, 0), Vector4(-358, 16, -18, 16))
	_notes.add_theme_constant_override("separation", 6)
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notes) # notifications stay visible with the HUD hidden
	inventory.changed.connect(render_hotbar)
	CKInput.bindings_changed.connect(render_hotbar)
	render_hotbar()


func _build_status() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(18, 16)
	row.add_theme_constant_override("separation", 10)
	widgets.add_child(row)
	var portrait := CKUI.image_rect(CKUI.board("hero/a_helmet_front"), Vector2(64, 64), true)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", CKUI.box(Color.BLACK, CKUI.BORDER, 10, 1, 0))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.add_child(portrait)
	row.add_child(frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	col.add_child(CKUI.label("CR-X9 · OWEN ENTERPRISES", 11, CKUI.BRIGHT, true))
	var fills := {"health": [Color("#8a0c17"), CKUI.BRIGHT], "armor": [Color("#5a5f6a"), Color("#c9ced8")], "energy": [Color("#1d5e8a"), Color("#67c6ff")]}
	for k in ["health", "armor", "energy"]:
		var m := HBoxContainer.new()
		m.add_theme_constant_override("separation", 6)
		m.add_child(CKUI.image_rect(CKUI.icon(k), Vector2(20, 20)))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(150, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", CKUI.box(Color("#241319"), Color("#4c1e29"), 4, 1, 0))
		var g := Gradient.new()
		g.set_color(0, fills[k][0])
		g.set_color(1, fills[k][1])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 150
		gt.height = 8
		var fill := StyleBoxTexture.new()
		fill.texture = gt
		bar.add_theme_stylebox_override("fill", fill)
		m.add_child(bar)
		var num := CKUI.label("100", 11, CKUI.MUTED)
		num.custom_minimum_size.x = 38
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		m.add_child(num)
		col.add_child(m)
		_meters[k] = [bar, num]


func _build_compass() -> void:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", CKUI.box(Color(CKUI.BG, 0.7), Color("#4c1e29"), 8, 1, 0))
	CKUI.place(c, Vector4(.5, 0, .5, 0), Vector4(-180, 14, 180, 48))
	c.clip_contents = true
	widgets.add_child(c)
	var inner := Control.new()
	c.add_child(inner)
	_strip = Control.new()
	inner.add_child(_strip)
	# three repeats of 8 cardinal marks (45 px each) so the strip scrolls seamlessly
	for i in 24:
		var l := CKUI.label(CARD[i % 8], 12, CKUI.TEXT if i % 2 == 0 else CKUI.MUTED, i % 2 == 0)
		l.position = Vector2(i * 45, 0)
		l.size = Vector2(45, 34)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_strip.add_child(l)
	var needle := ColorRect.new()
	needle.color = CKUI.BRIGHT
	needle.position = Vector2(179, 0)
	needle.size = Vector2(2, 8)
	inner.add_child(needle)
	var ic := CKUI.image_rect(CKUI.icon("compass"), Vector2(24, 24))
	ic.position = Vector2(6, 5)
	inner.add_child(ic)


func _build_selected() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", CKUI.box(Color(CKUI.BG, 0.85), CKUI.BORDER, 10, 1, 10))
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	CKUI.place(p, Vector4(1, 1, 1, 1), Vector4(-18, -18, -18, -18))
	p.custom_minimum_size = Vector2(230, 0)
	var v := VBoxContainer.new()
	p.add_child(v)
	_sel_title = CKUI.label("", 15, CKUI.TEXT, true)
	_sel_sub = CKUI.label("", 12, CKUI.MUTED)
	v.add_child(_sel_title)
	v.add_child(_sel_sub)
	widgets.add_child(p)


func _build_hotbar() -> void:
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", CKUI.box(Color(CKUI.BG, 0.88), CKUI.BORDER, 18, 1, 10))
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	CKUI.place(_bar, Vector4(.5, 1, .5, 1), Vector4(0, -14, 0, -14))
	widgets.add_child(_bar)
	var row := GridContainer.new()
	row.columns = 12
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	_bar.add_child(row)
	var disc := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.03, 0.05, 0.72))
	g.set_color(1, Color(0.04, 0.03, 0.05, 0.72))
	g.add_point(0.999, Color(0.04, 0.03, 0.05, 0.72))
	disc.gradient = g
	disc.fill = GradientTexture2D.FILL_RADIAL
	disc.fill_from = Vector2(0.5, 0.5)
	disc.fill_to = Vector2(1.0, 0.5)
	disc.width = 40
	disc.height = 40
	for i in inventory.hotbar.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(48, 48)
		b.focus_mode = Control.FOCUS_NONE # digits and Space keep going to the game
		b.add_theme_stylebox_override("normal", CKUI.box(Color("#17111a"), Color("#57313b"), 14, 1, 0))
		b.add_theme_stylebox_override("hover", CKUI.box(Color("#211923"), CKUI.BRIGHT, 14, 1, 0))
		b.pressed.connect(func(): slot_clicked.emit(i))
		var ic := CKUI.image_rect(null, Vector2(34, 34))
		CKUI.place(ic, Vector4(.5, .5, .5, .5), Vector4(-17, -17, 17, 17))
		b.add_child(ic)
		var cd := TextureProgressBar.new()
		cd.texture_progress = disc
		cd.fill_mode = TextureProgressBar.FILL_CLOCKWISE
		cd.max_value = 1.0
		cd.step = 0.001
		cd.nine_patch_stretch = true
		CKUI.place(cd, Vector4(.5, .5, .5, .5), Vector4(-20, -20, 20, 20))
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cd)
		var key := CKUI.label("", 10, Color.WHITE, true)
		key.position = Vector2(2, 1)
		var kb := CKUI.box(Color("#3d1823"), Color("#3d1823"), 5, 0, 3)
		key.add_theme_stylebox_override("normal", kb)
		b.add_child(key)
		var qty := CKUI.label("", 10, Color.WHITE, true)
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		CKUI.place(qty, Vector4(1, 1, 1, 1), Vector4(-26, -16, -3, -1))
		b.add_child(qty)
		var badge := CKUI.label("N/A", 8, Color("#ffd0d6"))
		CKUI.place(badge, Vector4(1, 0, 1, 0), Vector4(-22, 2, -2, 12))
		b.add_child(badge)
		row.add_child(b)
		_slots.append({"button": b, "icon": ic, "key": key, "qty": qty, "badge": badge, "cd": cd})


## Rebuild slot contents from the inventory and live bindings (rebinding updates the bar).
func render_hotbar() -> void:
	for i in mini(_slots.size(), inventory.hotbar.size()):
		var s: Dictionary = _slots[i]
		var id: String = inventory.hotbar[i]
		var d := inventory.def(id) if id != "" else {}
		var qty := inventory.quantity(id) if id != "" else 0
		var b: Button = s["button"]
		var selected := i == inventory.selected_slot and not d.is_empty()
		b.add_theme_stylebox_override("normal", CKUI.box(Color("#211923") if selected else Color("#17111a"),
			CKUI.BRIGHT if selected else Color("#57313b"), 14, 2 if selected else 1, 0))
		b.scale = Vector2.ONE * (1.08 if selected else 1.0)
		b.pivot_offset = b.custom_minimum_size / 2
		s["key"].text = CKUI.key_label(CKInput.code("slot%d" % (i + 1))) if i < Inventory.KEYED else ""
		s["key"].visible = i < Inventory.KEYED
		var ic: TextureRect = s["icon"]
		ic.texture = CKUI.icon(d["iconId"], "circle") if d else CKUI.icon("key_prompt")
		var unusable: bool = d.is_empty() or d.get("unavailableReason") != null or qty == 0
		ic.modulate = Color(1, 1, 1, 0.18) if d.is_empty() else Color(0.55, 0.55, 0.55) if unusable else Color.WHITE
		s["qty"].text = str(qty) if d.get("stackable", false) else ""
		s["badge"].visible = d.get("unavailableReason") != null and not d.is_empty()
		var status := "Assign an item from the inventory (Tab)" if d.is_empty() else String(d["unavailableReason"]) if d.get("unavailableReason") \
			else "None left. Restocks over time" if qty == 0 else "Use: %s%s" % [CKUI.key_label(CKInput.code("primaryAction")),
			" · %d energy" % d["energyCost"] if d.get("energyCost") else ""]
		b.tooltip_text = "%s\n%s" % [d.get("displayName", "Empty"), status]


func _build_world_widgets() -> void:
	# heat stars under the compass
	_stars = CKUI.label("", 20, CKUI.BRIGHT, true)
	_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	CKUI.place(_stars, Vector4(.5, 0, .5, 0), Vector4(-120, 50, 120, 76))
	widgets.add_child(_stars)
	# credits / rank and the mission objective under the vitals
	_rank = CKUI.label("", 12, CKUI.MUTED)
	_rank.position = Vector2(18, 98)
	widgets.add_child(_rank)
	var obj := PanelContainer.new()
	obj.add_theme_stylebox_override("panel", CKUI.box(Color(CKUI.BG, 0.78), CKUI.BORDER, 8, 1, 8))
	obj.position = Vector2(18, 122)
	obj.custom_minimum_size = Vector2(330, 0)
	_objective = CKUI.label("", 13)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size.x = 314
	obj.add_child(_objective)
	widgets.add_child(obj)
	# crime / mission ticks on the compass
	_compass_marks = Control.new()
	CKUI.place(_compass_marks, Vector4(.5, 0, .5, 0), Vector4(-180, 14, 180, 48))
	_compass_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_marks.draw.connect(_draw_marks)
	widgets.add_child(_compass_marks)
	# damage flash (red vignette)
	_flash = ColorRect.new()
	_flash.color = Color(0.85, 0.05, 0.1, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	move_child(_flash, 0)


var _heading := 0.0


func _draw_marks() -> void:
	if director == null:
		return
	var deg := fposmod(180.0 - rad_to_deg(_heading), 360.0)
	for m in director.markers:
		var d: Vector3 = m["pos"] - director.player.global_position
		var bearing := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0) # 0 = north (-Z), like the strip
		var off := wrapf(bearing - deg, -180.0, 180.0)
		if absf(off) > 80.0:
			continue
		var x := 180.0 + off * 2.0 # the strip is 45 px per 45 degrees
		var col := CKUI.BRIGHT if m["kind"] == "crime" else Color("#ffc040") if m["kind"] == "mission" else Color.WHITE
		_compass_marks.draw_colored_polygon(PackedVector2Array([Vector2(x, 26), Vector2(x - 6, 34), Vector2(x + 6, 34)]), col)
		_compass_marks.draw_string(get_theme_default_font(), Vector2(x - 20, 46), "%d m" % roundi(d.length()),
			HORIZONTAL_ALIGNMENT_CENTER, 40, 10, col)


func _draw_grapple_mark() -> void:
	if grapple_point == null or camera == null or camera.is_position_behind(grapple_point):
		return
	var p := camera.unproject_position(grapple_point)
	var col := Color("#ffc040")
	var r := 11.0
	_grapple_mark.draw_polyline(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)]), col, 2.5, true)
	_grapple_mark.draw_circle(p, 2.5, col)
	_grapple_mark.draw_string(get_theme_default_font(), p + Vector2(14, 5), CKUI.key_label(CKInput.code("grapple")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func show_combo(n: int) -> void:
	_combo.text = "x%d" % n if n >= 2 else ""
	if n >= 2:
		_combo.scale = Vector2.ONE * 1.25
		_combo.pivot_offset = Vector2(0, 20)
		create_tween().tween_property(_combo, "scale", Vector2.ONE, 0.15)


func _draw_reticle() -> void:
	if not _crosshair.visible:
		return
	var c := _reticle.size / 2
	var hot: bool = weapons != null and weapons.under_crosshair != null
	var col := CKUI.BRIGHT if hot else Color(1, 1, 1, 0.9)
	var gap := 6.0 + (weapons.bloom * 14.0 if weapons else 0.0)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_reticle.draw_line(c + d * gap, c + d * (gap + 9.0), Color(0, 0, 0, 0.6), 4.0, true)
		_reticle.draw_line(c + d * gap, c + d * (gap + 9.0), col, 2.0, true)
	_reticle.draw_circle(c, 2.0, col)
	# lock bracket around the locked enemy
	if weapons and weapons.locked and camera and not camera.is_position_behind(weapons.locked.global_position):
		var p := camera.unproject_position(weapons.locked.global_position + Vector3(0, 1.25, 0))
		var r := 22.0
		for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_reticle.draw_polyline(PackedVector2Array([p + Vector2(s.x * r, s.y * (r - 8)), p + s * r, p + Vector2(s.x * (r - 8), s.y * r)]),
				Color("#ffc040"), 2.5, true)


## Context control hints: [[action, text], ...] for what the Knight can do right now.
func set_hints(list: Array) -> void:
	_hints.visible = hints_enabled and not list.is_empty()
	var key := str(list)
	if key == _hints_key:
		return
	_hints_key = key
	for c in _hints.get_children():
		c.queue_free()
	for h in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var code: String = CKInput.code(h[0]) if not String(h[0]).begins_with("=") else String(h[0]).substr(1)
		# readable text key badges (the UI-pack keycaps are too small at this size)
		var k := CKUI.label(CKUI.key_label(code), 13, Color.WHITE, true)
		k.add_theme_stylebox_override("normal", CKUI.box(Color("#3d1823"), CKUI.BRIGHT, 5, 1, 5))
		row.add_child(k)
		var t := CKUI.label(h[1], 13, CKUI.TEXT)
		t.add_theme_color_override("font_shadow_color", Color.BLACK)
		row.add_child(t)
		_hints.add_child(row)


## Red vignette when the Knight takes a hit.
func damage_flash(amount: float, _from: Vector3, _at: Vector3, _yaw: float) -> void:
	_flash.color.a = clampf(0.12 + amount / 60.0, 0.12, 0.4)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.5)


## Hit marker around the crosshair: white on hit, crimson on a knockdown.
func hit_marker(kill: bool) -> void:
	_marker.self_modulate = CKUI.BRIGHT if kill else Color.WHITE
	_marker.modulate.a = 1.0
	_marker.scale = Vector2.ONE * (1.3 if kill else 1.0)
	_marker.pivot_offset = Vector2(20, 20)
	var tw := _marker.create_tween()
	tw.tween_property(_marker, "modulate:a", 0.0, 0.25)


class HitMarker:
	extends Control
	func _draw() -> void:
		var c := size / 2
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 6, c + d * 14, Color.WHITE, 2.5, true)


## Brief highlight when a slot's key is pressed.
func flash(i: int) -> void:
	var b: Button = _slots[i]["button"]
	b.modulate = Color(1.6, 1.6, 1.6)
	create_tween().tween_property(b, "modulate", Color.WHITE, 0.15)


## Top-right queue: max 4 visible, each fades after ~4 s.
func notify(text: String, icon_id := "notification", kind := "info") -> void:
	var p := PanelContainer.new()
	var sb := CKUI.box(Color(0.09, 0.07, 0.11, 0.94), Color("#4c1e29"), 8, 1, 8)
	sb.border_width_left = 3
	sb.border_color = Color("#ffb020") if kind == "warn" else CKUI.RED
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(CKUI.image_rect(CKUI.icon(icon_id if CKUI.has_icon(icon_id) else "notification"), Vector2(26, 26)))
	var l := CKUI.label(text, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 280
	h.add_child(l)
	p.add_child(h)
	_notes.add_child(p)
	_notes.move_child(p, 0)
	while _notes.get_child_count() > 4:
		_notes.get_child(_notes.get_child_count() - 1).free()
	var tw := p.create_tween()
	tw.tween_interval(3.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


## Contextual prompt from real bindings, e.g. ("interact", "Shove"); empty action hides it.
func set_prompt(action: String, text := "") -> void:
	if action == "":
		_prompt.visible = false
		_prompt_key = ""
		return
	var code := CKInput.code(action)
	var k := code + "|" + text
	if k == _prompt_key:
		return
	_prompt_key = k
	for c in _prompt.get_children():
		c.queue_free()
	var cap := CKUI.keycap(code)
	if cap:
		_prompt.add_child(CKUI.image_rect(cap, Vector2(34, 34)))
	else:
		_prompt.add_child(CKUI.label("[%s]" % CKUI.key_label(code), 15, CKUI.BRIGHT, true))
	var l := CKUI.label(text, 15, CKUI.TEXT, true)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	_prompt.add_child(l)
	_prompt.visible = true


func update_hud(now: int, heading: float, show_crosshair: bool) -> void:
	_visor_update()
	for k in _meters:
		var v: float = vitals.get(k)
		_meters[k][0].value = v
		_meters[k][1].text = str(roundi(v))
	# compass: heading 0 = facing +Z (south in map terms, where north is -Z)
	var deg := fposmod(180.0 - rad_to_deg(heading), 360.0)
	_strip.position.x = 180.0 - deg - 360.0 - 22.5
	var id := inventory.selected_item()
	var d := inventory.def(id) if id != "" else {}
	_bar.visible = vehicle_text.is_empty()
	if not vehicle_text.is_empty():
		_sel_title.text = vehicle_text[0]
		_sel_sub.text = "
".join(vehicle_text.slice(1))
	elif d.is_empty():
		_sel_title.text = "No item selected"
		_sel_sub.text = "Press 1-8 or open the inventory"
	else:
		var cd := inventory.cooldown_remaining(id, now)
		var parts := []
		if d.get("stackable", false):
			parts.append("%d / %d" % [inventory.quantity(id), d["maxStack"]])
		if d.get("energyCost"):
			parts.append("%d energy" % d["energyCost"])
		if weapon_status != "":
			parts.append(weapon_status)
		parts.append("recharging %.1f s" % (cd / 1000.0) if cd > 0 else "unavailable" if d.get("unavailableReason") \
			else "%s to use" % CKUI.key_label(CKInput.code("primaryAction")))
		_sel_title.text = d["displayName"]
		_sel_sub.text = " · ".join(parts)
	_crosshair.visible = show_crosshair
	_grapple_mark.queue_redraw()
	_reticle.queue_redraw()
	if director:
		_heading = heading
		var st := director.stars()
		_stars.text = "★".repeat(st) + "☆".repeat(5 - st) if st > 0 else ""
		_rank.text = "%s · %d cr" % [director.rank(), director.credits] + (" · %s · %s" % [stage.clock(), stage.weather_name] if stage else "")
		_objective.get_parent().visible = director.objective != ""
		_objective.text = director.objective
		_compass_marks.queue_redraw()
	for i in mini(_slots.size(), inventory.hotbar.size()):
		var sid: String = inventory.hotbar[i]
		_slots[i]["cd"].value = inventory.cooldown_fraction(sid, now) if sid != "" else 0.0


## Visor projection: holographic tint, and a small lag behind head turns so the displays feel like they sit on
## the inside of the helmet glass rather than on the screen.
func _visor_update() -> void:
	var dt := get_process_delta_time()
	var target := Vector2.ZERO
	if visor and camera:
		var b := camera.global_basis
		var dyaw := wrapf(b.get_euler().y - _last_cam_basis.get_euler().y, -PI, PI)
		var dpitch := b.get_euler().x - _last_cam_basis.get_euler().x
		_last_cam_basis = b
		target = Vector2(dyaw * 260.0, -dpitch * 260.0).limit_length(28.0)
	_sway = _sway.lerp(target, minf(1.0, dt * 6.0))
	widgets.position = _sway
	widgets.modulate = widgets.modulate.lerp(Color(0.82, 0.97, 1.0, 0.93) if visor else Color.WHITE, minf(1.0, dt * 4.0))
