class_name Menus
extends Control
## Modal menu stack (port of ui/MenuManager.ts + ui/InventoryPanel.ts): main menu, pause, inventory,
## map, equipment loadout and settings (graphics, audio levels, interface, key rebinding).
## Esc goes back; the main menu can't be backed out of. Every button maps to a real game action on `game`
## (the main.gd node). The game pauses the tree while a menu is open; this node always processes.

signal open_changed(open: bool)

const TITLE := {"main": "Main Menu", "pause": "Paused", "inventory": "Inventory", "map": "Map", "loadout": "Equipment Loadout", "settings": "Settings"}
const ICON := {"main": "home", "pause": "pause", "inventory": "inventory", "map": "map", "loadout": "loadout", "settings": "settings"}
const TAB_ICON := {"gadget": "batarang", "fictional_weapon": "crimson_carbine", "vehicle": "interceptor", "tool": "repair", "quest_item": "keycard"}

var game: Node
var inventory: Inventory
var _stack: Array = [] # {screen, root}
var _capture: Callable
# inventory screen state
var _inv_tab := "gadget"
var _inv_sel := ""
var _inv_query := ""
var _inv_sort := "name"


func _ready() -> void:
	name = "Menus"
	theme = CKUI.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return not _stack.is_empty()


func top() -> String:
	return _stack[-1]["screen"] if _stack else ""


## Close the top screen (Esc / Back). The main menu can't be backed out of.
func back() -> void:
	if _stack.is_empty() or top() == "main":
		return
	_pop()


func close_all() -> void:
	while _stack:
		_pop(true)


## Toggle a screen from a hotkey (Tab inventory, M map).
func toggle(screen: String) -> void:
	if top() == screen:
		back()
	elif not _stack.any(func(s): return s["screen"] == "main"):
		show_screen(screen)


func _pop(silent := false) -> void:
	if not silent and _stack.size() > 1:
		game.audio.play("ui.close")
	var s: Dictionary = _stack.pop_back()
	s["root"].queue_free()
	if _stack:
		_stack[-1]["root"].visible = true
		_focus_first(_stack[-1]["root"])
	else:
		open_changed.emit(false)


func show_screen(screen: String) -> void:
	if _stack.is_empty():
		open_changed.emit(true)
	else:
		_stack[-1]["root"].visible = false
		game.audio.play("ui.open")
	var root: Control
	if screen == "main":
		root = _main_menu()
	else:
		root = _modal(screen)
	add_child(root)
	_stack.append({"screen": screen, "root": root})
	_focus_first.call_deferred(root)


func _focus_first(root: Control) -> void:
	for c in root.find_children("*", "Button", true, false):
		if c.is_visible_in_tree() and not c.disabled and c.focus_mode != Control.FOCUS_NONE and not c.has_meta("back"):
			c.grab_focus()
			return


## Rebuild the top screen in place (after state changes).
func refresh() -> void:
	if _stack.is_empty():
		return
	var screen := top()
	var old: Control = _stack[-1]["root"]
	var root: Control = _main_menu() if screen == "main" else _modal(screen)
	add_child(root)
	_stack[-1]["root"] = root
	old.queue_free()


func _input(e: InputEvent) -> void:
	if _capture.is_valid() and (e is InputEventKey or e is InputEventMouseButton) and e.is_pressed():
		var cb := _capture
		_capture = Callable()
		get_viewport().set_input_as_handled()
		cb.call(CKInput.code_for_event(e))


func _unhandled_input(e: InputEvent) -> void:
	if not is_open():
		return
	if e.is_action_pressed("pause"):
		back()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("inventory") and top() == "inventory":
		back()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("map") and top() == "map":
		back()
		get_viewport().set_input_as_handled()
	elif top() == "inventory" and _inv_sel != "" and e is InputEventKey and e.pressed:
		var k: int = e.physical_keycode
		if (k >= KEY_1 and k <= KEY_9 or k == KEY_0) and not get_viewport().gui_get_focus_owner() is LineEdit:
			_assign(9 if k == KEY_0 else k - KEY_1)
			get_viewport().set_input_as_handled()


# ---------------- frames ----------------
func _modal(screen: String) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var win := PanelContainer.new()
	win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		win.set("offset_" + side, 90 if side == "left" else -90)
	win.offset_top = 50
	win.offset_bottom = -50
	dim.add_child(win)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	win.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(CKUI.image_rect(CKUI.icon(ICON[screen]), Vector2(30, 30)))
	var t := CKUI.label(TITLE[screen], 24, CKUI.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := CKUI.button("Back", "back", "Esc", back)
	close.custom_minimum_size = Vector2(150, 38)
	close.set_meta("back", true) # initial focus goes to the screen's first action, not Back
	head.add_child(close)
	v.add_child(head)
	var line := ColorRect.new()
	line.color = CKUI.LINE
	line.custom_minimum_size.y = 1
	v.add_child(line)
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	v.add_child(body)
	call("_screen_" + screen, body)
	return dim


func _scroll(body: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return v


func _muted(text: String) -> Label:
	var l := CKUI.label(text, 12, CKUI.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# ---------------- main menu ----------------
func _main_menu() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := CKUI.image_rect(CKUI.board("world/c_downtown_wide"), Vector2.ZERO, true)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.04, 0.07, 0.96))
	g.set_color(1, Color(0.05, 0.04, 0.07, 0.25))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var col := VBoxContainer.new()
	col.position = Vector2(80, 90)
	col.add_theme_constant_override("separation", 8)
	root.add_child(col)
	col.add_child(CKUI.label("CRIMSON KNIGHT", 54, CKUI.TEXT, true))
	col.add_child(CKUI.label("EARTH-RED · OWEN ENTERPRISES", 14, CKUI.BRIGHT, true))
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	col.add_child(gap)
	var save = game.saves.read()
	col.add_child(CKUI.button("Play", "play", "resume current session", _go(game.play), true))
	col.add_child(CKUI.button("Continue", "load", String(save["savedAt"]).replace("T", " ").left(16) if save else "No save yet",
		_go(game.continue_save) if save else null))
	col.add_child(CKUI.button("New Sandbox", "sandbox", "fresh inventory & spawn", _go(game.new_sandbox)))
	col.add_child(CKUI.button("Settings", "settings", "", func(): show_screen("settings")))
	col.add_child(CKUI.button("Controls", "controls", "", func(): show_screen("settings")))
	col.add_child(CKUI.button("Quit", "quit", "", func(): get_tree().quit()))
	col.add_child(_muted("Open-world sandbox · no required story · created by Owen Grumbles"))
	return root


func _go(fn: Callable) -> Callable:
	return func():
		close_all()
		fn.call()


# ---------------- pause ----------------
func _screen_pause(body: VBoxContainer) -> void:
	var l := VBoxContainer.new()
	l.add_theme_constant_override("separation", 8)
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.custom_minimum_size.x = 420
	body.add_child(l)
	l.add_child(CKUI.button("Resume", "play", "Esc", close_all, true))
	l.add_child(CKUI.button("Inventory", "inventory", CKUI.key_label(CKInput.code("inventory")), func(): show_screen("inventory")))
	l.add_child(CKUI.button("Map", "map", CKUI.key_label(CKInput.code("map")), func(): show_screen("map")))
	l.add_child(CKUI.button("Equipment Loadout", "loadout", "", func(): show_screen("loadout")))
	l.add_child(CKUI.button("Settings", "settings", "", func(): show_screen("settings")))
	l.add_child(CKUI.button("Save", "save", "", game.save_now))
	l.add_child(CKUI.button("Exit to Main Menu", "home", "", func():
		game.save_now()
		close_all()
		show_screen("main")))


# ---------------- inventory ----------------
func _inv_items() -> Array:
	var cat := _inv_tab
	var out := inventory.order.map(func(id): return inventory.def(id))
	if _inv_query != "":
		out = out.filter(func(d): return ("%s %s" % [d["displayName"], d["description"]]).to_lower().contains(_inv_query))
	else:
		out = out.filter(func(d): return d["category"] == cat)
	out.sort_custom(func(a, b):
		if _inv_sort == "status" and (a.get("unavailableReason") == null) != (b.get("unavailableReason") == null):
			return a.get("unavailableReason") == null
		return String(a["displayName"]) < String(b["displayName"]))
	return out


func _screen_inventory(body: VBoxContainer) -> void:
	var data: Dictionary = CKData.data("items")
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	for c in data["categoryOrder"]:
		var t := CKUI.button(data["categoryLabel"][c], TAB_ICON[c], "", func():
			_inv_tab = c
			_inv_query = ""
			_inv_sel = ""
			refresh())
		t.custom_minimum_size = Vector2(0, 40)
		if c == _inv_tab and _inv_query == "":
			t.add_theme_stylebox_override("normal", CKUI.box(Color("#3d1823"), CKUI.BRIGHT, 10, 1, 10))
		tabs.add_child(t)
	var bar := HBoxContainer.new()
	body.add_child(bar)
	var search := LineEdit.new()
	search.placeholder_text = "Search items…"
	search.text = _inv_query
	search.custom_minimum_size.x = 260
	search.text_submitted.connect(func(t):
		_inv_query = t.strip_edges().to_lower()
		refresh())
	bar.add_child(search)
	var sort := OptionButton.new()
	sort.add_item("Sort: name")
	sort.add_item("Sort: usable first")
	sort.selected = 1 if _inv_sort == "status" else 0
	sort.item_selected.connect(func(i):
		_inv_sort = "status" if i == 1 else "name"
		refresh())
	bar.add_child(sort)
	var hint := _muted("Every item is on your belt. Select one, then press 1-0 to put it on that key. Enter searches.")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(hint)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	body.add_child(split)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(grid)
	var items := _inv_items()
	if _inv_sel == "" and items:
		_inv_sel = items[0]["id"]
	if items.is_empty():
		grid.add_child(_muted("No items match."))
	for d in items:
		grid.add_child(_card(d))
	split.add_child(_detail(inventory.def(_inv_sel)))


func _card(d: Dictionary) -> Button:
	var id: String = d["id"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 132)
	b.tooltip_text = d.get("unavailableReason") if d.get("unavailableReason") else d["description"]
	var sel := id == _inv_sel
	b.add_theme_stylebox_override("normal", CKUI.box(Color("#2a1620") if sel else Color("#17111a"), CKUI.BRIGHT if sel else Color("#57313b"), 12, 2 if sel else 1, 8))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := CKUI.image_rect(CKUI.icon(d["iconId"]), Vector2(56, 56))
	if d.get("unavailableReason"):
		ic.modulate = Color(0.6, 0.6, 0.6)
	v.add_child(ic)
	var t := CKUI.label(d["displayName"], 12, CKUI.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var status: String
	if d["category"] == "vehicle":
		status = "Blueprint · unavailable" if d.get("unavailableReason") else "Summonable"
	elif d.get("stackable", false):
		status = "×%d" % inventory.quantity(id)
	else:
		status = "Not usable yet" if d.get("unavailableReason") else "Ready"
	var s := CKUI.label(status, 11, CKUI.MUTED)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var slot: int = inventory.hotbar.find(id)
	if slot >= 0:
		var n := CKUI.label(str(slot + 1), 11, Color.WHITE, true)
		n.add_theme_stylebox_override("normal", CKUI.box(Color("#3d1823"), Color("#3d1823"), 5, 0, 3))
		n.position = Vector2(6, 4)
		b.add_child(n)
	b.pressed.connect(func():
		_inv_sel = id
		refresh())
	return b


func _detail(d: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size.x = 340
	p.add_theme_stylebox_override("panel", CKUI.box(Color("#120e15"), CKUI.LINE, 12, 1, 14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	if d.is_empty():
		v.add_child(_muted("Select an item."))
		return p
	var art := CKUI.board(d["artId"]) if d.get("artId") else null
	v.add_child(CKUI.image_rect(art if art else CKUI.icon(d["iconId"]), Vector2(300, 150)))
	v.add_child(CKUI.label(d["displayName"], 20, CKUI.TEXT, true))
	var meta := [CKData.data("items")["categoryLabel"][d["category"]]]
	if d.get("stackable", false):
		meta.append("%d / %d" % [inventory.quantity(d["id"]), d["maxStack"]])
	if d.get("cooldownMs"):
		meta.append("%.1f s cooldown" % (d["cooldownMs"] / 1000.0))
	if d.get("energyCost"):
		meta.append("%d energy" % d["energyCost"])
	v.add_child(_muted(" · ".join(meta)))
	var desc := CKUI.label(d["description"], 13)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	if d.get("unavailableReason"):
		var na := CKUI.label(d["unavailableReason"], 12, Color("#ffb020"))
		na.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(na)
	if d["category"] == "vehicle":
		var quick: bool = game.quick_vehicle == d["id"]
		v.add_child(CKUI.button("Quick-call ✓" if quick else "Set as quick-call vehicle", "interceptor", "", func():
			game.quick_vehicle = d["id"]
			refresh()))
	elif d.get("canEquip", false):
		var slot: int = inventory.hotbar.find(d["id"])
		v.add_child(CKUI.button("Equip (slot %d)" % (slot + 1) if slot >= 0 else "Equip", "loadout", "", func():
			if inventory.hotbar.find(d["id"]) < 0:
				_assign(inventory.selected_slot)
			game.select_slot(inventory.hotbar.find(d["id"]))
			refresh()))
		v.add_child(_muted("Put it on number key:"))
		var row := HBoxContainer.new()
		for i in Inventory.KEYED:
			var b := Button.new()
			b.text = str((i + 1) % 10)
			b.custom_minimum_size = Vector2(34, 34)
			if inventory.hotbar[i] == d["id"]:
				b.add_theme_stylebox_override("normal", CKUI.box(Color("#3d1823"), CKUI.BRIGHT, 8, 1, 4))
			b.pressed.connect(func(): _assign(i))
			row.add_child(b)
		v.add_child(row)
	else:
		v.add_child(_muted("Can't go on the hotbar."))
	return p


func _assign(i: int) -> void:
	var err := inventory.assign(_inv_sel, i)
	if err != "":
		game.notify(err, "inventory", "warn")
	else:
		game.notify("%s → slot %d" % [inventory.def(_inv_sel)["displayName"], i + 1], inventory.def(_inv_sel)["iconId"])
	refresh()


# ---------------- map ----------------
func _screen_map(body: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	var pane := VBoxContainer.new()
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var map_btn := CKUI.button("District map", "map", "", func(): _draw_map(pane))
	var loc_btn := CKUI.button("Locations", "citadel", "", func(): _draw_locations(pane))
	for b in [map_btn, loc_btn]:
		b.custom_minimum_size = Vector2(200, 38)
		tabs.add_child(b)
	body.add_child(pane)
	_draw_map(pane)


func _draw_map(pane: VBoxContainer) -> void:
	for c in pane.get_children():
		c.queue_free()
	var m := MapView.new()
	m.game = game
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_child(m)
	pane.add_child(_muted("Built from the loaded district geometry. North is up. Red triangle = you. Only the explored test district exists so far."))


func _draw_locations(pane: VBoxContainer) -> void:
	for c in pane.get_children():
		c.queue_free()
	var v := _scroll(pane)
	var world: Array = CKData.json("image_catalog")["images"].filter(func(i): return i["category"] == "world")
	var gotham := world.filter(func(i): return String(i["id"]).begins_with("world/b_") and not String(i.get("label", "")).begins_with("citadel"))
	var citadel := world.filter(func(i): return RegEx.create_from_string("^world/[ab]_citadel").search(i["id"]) != null)
	for pair in [["New Gotham", gotham], ["Red Citadel", citadel]]:
		v.add_child(CKUI.section(pair[0]))
		var gal := HFlowContainer.new()
		gal.add_theme_constant_override("h_separation", 10)
		gal.add_theme_constant_override("v_separation", 10)
		v.add_child(gal)
		for img in pair[1]:
			var f := VBoxContainer.new()
			f.add_child(CKUI.image_rect(CKUI.tex("res://" + img["file"]), Vector2(220, 124), true))
			f.add_child(CKUI.label(CKUI.pretty(img["id"]), 11, CKUI.MUTED))
			gal.add_child(f)
	v.add_child(_muted("Concept locations from the Earth-RED boards. Most are not built as playable areas yet."))


# ---------------- loadout ----------------
func _screen_loadout(body: VBoxContainer) -> void:
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	body.add_child(cols)
	var left := VBoxContainer.new()
	cols.add_child(left)
	left.add_child(CKUI.section("CR-X9 War Suit"))
	left.add_child(CKUI.image_rect(CKUI.board("hero/c_turnaround_front"), Vector2(320, 260)))
	var v: Vitals = game.vitals
	left.add_child(_muted("Health %d · Armor %d · Energy %d" % [roundi(v.health), roundi(v.armor), roundi(v.energy)]))
	var suit := HFlowContainer.new()
	for id in ["a_helmet_front", "a_helmet_side", "c_detail_chest", "c_detail_gauntlet", "c_detail_belt", "a_armor_boots"]:
		var f := VBoxContainer.new()
		f.add_child(CKUI.image_rect(CKUI.board("hero/" + id), Vector2(90, 70)))
		f.add_child(CKUI.label(CKUI.pretty(id), 10, CKUI.MUTED))
		suit.add_child(f)
	left.add_child(suit)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(CKUI.section("Utility belt (number keys 1-0, wheel cycles the rest)"))
	var grid := GridContainer.new()
	grid.columns = 4
	right.add_child(grid)
	for i in Inventory.KEYED:
		var id: String = inventory.hotbar[i]
		var d := inventory.def(id) if id != "" else {}
		var b := CKUI.button("%s  %s" % [CKUI.key_label(CKInput.code("slot%d" % (i + 1))), d.get("displayName", "Empty")],
			d.get("iconId", "key_prompt"), "", func(): show_screen("inventory"))
		b.custom_minimum_size = Vector2(170, 44)
		if i == inventory.selected_slot:
			b.add_theme_stylebox_override("normal", CKUI.box(Color("#3d1823"), CKUI.BRIGHT, 10, 1, 10))
		grid.add_child(b)
	right.add_child(CKUI.section("Vehicle quick select"))
	var veh := HBoxContainer.new()
	right.add_child(veh)
	for id in inventory.order:
		var d := inventory.def(id)
		if d["category"] != "vehicle":
			continue
		var f := VBoxContainer.new()
		f.add_child(CKUI.image_rect(CKUI.board(d["artId"]), Vector2(200, 112), true))
		var quick: bool = game.quick_vehicle == id
		var b := CKUI.button(d["displayName"].get_slice(" ", 0), "", "Quick-call ✓" if quick else "Set quick-call", func():
			game.quick_vehicle = id
			refresh())
		b.custom_minimum_size = Vector2(200, 38)
		f.add_child(b)
		veh.add_child(f)
	right.add_child(_muted("Drivable vehicles are not built yet. The call key plays the wrist-module call until then."))


# ---------------- settings ----------------
func _row(v: VBoxContainer, label_text: String, control: Control, extra := "") -> Label:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	var l := CKUI.label(label_text, 14)
	l.custom_minimum_size.x = 220
	r.add_child(l)
	if not control is CheckBox:
		control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 260)
	r.add_child(control)
	var x := CKUI.label(extra, 12, CKUI.MUTED)
	r.add_child(x)
	v.add_child(r)
	return x


func _screen_settings(body: VBoxContainer) -> void:
	var s: Dictionary = game.settings
	var v := _scroll(body)
	v.add_child(CKUI.section("Graphics"))
	var q := OptionButton.new()
	for item in ["Low: 720p, laptop target", "Medium", "High", "Ultra"]:
		q.add_item(item)
	q.selected = Quality.ORDER.find(s["quality"])
	q.item_selected.connect(func(i):
		s["quality"] = Quality.ORDER[i]
		game.apply_settings())
	_row(v, "Quality preset", q)
	# individual overrides: "Preset" follows the preset above
	for key in Quality.OPTIONS:
		var ob := OptionButton.new()
		for choice in Quality.OPTIONS[key][1]:
			ob.add_item(choice[0])
		var gfx: Dictionary = s["graphics"]
		ob.selected = int(gfx.get(key, 0))
		var k2: String = key
		ob.item_selected.connect(func(i):
			s["graphics"][k2] = i
			game.apply_settings())
		_row(v, Quality.OPTIONS[key][0], ob)
	v.add_child(_muted("Detected GPU: %s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()]))
	var fs := CheckBox.new()
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(func(on): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	_row(v, "Fullscreen", fs)
	var bench := CKUI.button("Benchmark (not ported yet)", "graphics", "", null)
	_row(v, "Benchmark", bench, "deferred")

	v.add_child(CKUI.section("Audio"))
	var mute := CheckBox.new()
	mute.button_pressed = s["muted"]
	mute.toggled.connect(func(on):
		s["muted"] = on
		game.apply_settings())
	_row(v, "Mute all", mute)
	for pair in [["master", "Master"], ["sfx", "Effects"], ["music", "Music"], ["ambience", "Ambience"], ["vehicles", "Vehicles"], ["ui", "Interface"]]:
		var k: String = pair[0]
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 1
		sl.step = 0.05
		sl.value = s["volumes"][k]
		var pct := _row(v, "%s volume" % pair[1], sl, "%d%%" % roundi(sl.value * 100))
		sl.value_changed.connect(func(x):
			s["volumes"][k] = x
			pct.text = "%d%%" % roundi(x * 100)
			game.apply_settings())
	v.add_child(_muted("Synthesized placeholder sounds. There is no music or vehicle audio yet; those sliders take effect when it is added."))

	v.add_child(CKUI.section("Interface"))
	var sc := HSlider.new()
	sc.min_value = 0.7
	sc.max_value = 1.5
	sc.step = 0.05
	sc.value = s["uiScale"]
	var sc_pct := _row(v, "UI scale", sc, "%d%%" % roundi(sc.value * 100))
	sc.drag_ended.connect(func(_c):
		s["uiScale"] = sc.value
		sc_pct.text = "%d%%" % roundi(sc.value * 100)
		game.apply_settings())
	for pair in [["hudVisible", "Show HUD"], ["reduceMotion", "Reduce motion (no head-bob or recoil kick)"]]:
		var cb := CheckBox.new()
		cb.button_pressed = s[pair[0]]
		var key: String = pair[0]
		cb.toggled.connect(func(on):
			s[key] = on
			game.apply_settings())
		_row(v, pair[1], cb)
	var sub := CheckBox.new()
	sub.disabled = true
	_row(v, "Subtitles", sub, "Coming later (no dialogue yet)")

	v.add_child(CKUI.section("Controls"))
	var ms := HSlider.new()
	ms.min_value = 0.3
	ms.max_value = 2.5
	ms.step = 0.05
	ms.value = s["mouseSensitivity"]
	var ms_pct := _row(v, "Mouse sensitivity", ms, "%d%%" % roundi(ms.value * 100))
	ms.value_changed.connect(func(x):
		s["mouseSensitivity"] = x
		ms_pct.text = "%d%%" % roundi(x * 100)
		game.apply_settings())
	var inv := CheckBox.new()
	inv.button_pressed = s["invertY"]
	inv.toggled.connect(func(on):
		s["invertY"] = on
		game.apply_settings())
	_row(v, "Invert camera Y", inv)
	for pair in [["aimAssist", "Aim assist (RMB locks on, shots curve onto targets)"], ["controlHints", "Show control hints"],
			["redVoice", "R.E.D. speaks (local voice)"], ["redListen", "R.E.D. voice commands (hold Y)"],
			["redBrain", "R.E.D. conversation (local LLM, ~1.2 GB RAM)"], ["redChatter", "R.E.D. callouts and tips"], ["dayNight", "Day/night cycle (off: always night)"],
			["helmetDefault", "Start in helmet view (H toggles first / third person)"], ["holoHud", "Holographic visor info (targets, systems, radar)"]]:
		var cbx := CheckBox.new()
		var key: String = pair[0]
		cbx.button_pressed = s.get(key, true)
		cbx.toggled.connect(func(on):
			s[key] = on
			game.apply_settings())
		_row(v, pair[1], cbx)
	v.add_child(_muted("Click a key, then press the new key. If it is already used, the two actions swap. Esc cancels."))
	var keys := GridContainer.new()
	keys.columns = 2
	keys.add_theme_constant_override("h_separation", 16)
	v.add_child(keys)
	for a in CKInput.ACTIONS:
		keys.add_child(CKUI.label("%s · %s" % [a[2], a[1]], 13))
		var b := Button.new()
		b.text = CKUI.key_label(CKInput.code(a[0]))
		b.custom_minimum_size = Vector2(160, 34)
		if a[3]:
			b.disabled = true
			b.tooltip_text = "Fixed"
		else:
			b.pressed.connect(func():
				b.text = "Press a key…"
				_capture = func(code: String):
					if code != "Escape" and code != "":
						var was := _owner_of(code, a[0])
						CKInput.rebind(a[0], code)
						if was != "":
							game.notify("%s was used by \"%s\". Swapped" % [CKUI.key_label(code), was], "controls", "warn")
						game.apply_settings()
					refresh())
		keys.add_child(b)
	var reset := CKUI.button("Reset all controls to defaults", "back", "", func():
		CKInput.reset_bindings()
		game.apply_settings()
		refresh())
	v.add_child(reset)
	v.add_child(_muted("Gamepad (standard layout): A jump · B crouch · X interact · Y inventory · LB/RB previous/next slot · LT aim · RT use item · L3 sprint · Start pause · Back map · D-pad up call vehicle."))


func _owner_of(code: String, except: String) -> String:
	for a in CKInput.ACTIONS:
		if a[0] != except and CKInput.code(a[0]) == code:
			return a[1]
	return ""
