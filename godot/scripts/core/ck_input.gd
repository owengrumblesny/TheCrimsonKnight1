extends Node
## Autoload "CKInput": builds the InputMap from the shared bindings table (config/controls.json plus the
## hotbar/menu defaults from the original web build) and exposes move/look axes.
## Bindings use KeyboardEvent.code names ("KeyW", "Digit1", "Mouse0") so saves stay compatible with the web build.

signal bindings_changed

const ACTIONS := [
	# [id, label, group, fixed]
	["moveForward", "Move forward", "Movement", false], ["moveBack", "Move back", "Movement", false],
	["moveLeft", "Move left", "Movement", false], ["moveRight", "Move right", "Movement", false],
	["sprint", "Sprint", "Movement", false], ["jump", "Jump / glide (hold in air)", "Movement", false],
	["crouch", "Crouch", "Movement", false], ["walkToggle", "Walk / run toggle", "Movement", false],
	["primaryAction", "Use selected item", "Actions", false], ["grapple", "Grapnel: fire at the marked rooftop", "Traversal", false],
	["interact", "Interact / enter vehicle", "Actions", false], ["summonMenu", "Call vehicle / driving camera", "Actions", false],
	["secondaryAction", "Aim weapon (hold)", "Actions", false], ["reload", "Reload weapon", "Actions", false],
	["vehicleMode", "Vehicle mode", "Vehicle", false], ["vehicleExit", "Exit vehicle", "Vehicle", false],
	["eject", "Eject CR-B1 from the CR-X1", "Vehicle", false],
	["slotPrev", "Previous hotbar slot", "Hotbar", false], ["slotNext", "Next hotbar slot", "Hotbar", false],
	["slot1", "Belt key 1", "Hotbar", false], ["slot2", "Belt key 2", "Hotbar", false],
	["slot3", "Belt key 3", "Hotbar", false], ["slot4", "Belt key 4", "Hotbar", false],
	["slot5", "Belt key 5", "Hotbar", false], ["slot6", "Belt key 6", "Hotbar", false],
	["slot7", "Belt key 7", "Hotbar", false], ["slot8", "Belt key 8", "Hotbar", false],
	["slot9", "Belt key 9", "Hotbar", false], ["slot10", "Belt key 10", "Hotbar", false],
	["inventory", "Inventory", "Menus", false], ["map", "Map", "Menus", false],
	["pause", "Pause / back", "Menus", true], ["sandboxMenu", "Animation debug", "Menus", false],
	["perfOverlay", "Performance overlay", "Menus", false],
	["talkToRed", "Talk to R.E.D. (hold, voice)", "R.E.D.", false], ["chatRed", "Type to R.E.D.", "R.E.D.", false],
	["villainTalk", "Speak to a villain (hold, voice)", "Conversation", false], ["villainType", "Type to a villain", "Conversation", false],
	["helmetView", "Helmet camera (first person)", "Camera", false], ["vision", "Vision mode: Knight / thermal / X-ray", "Camera", false],
]

const MOUSE_SENS_X := 0.0025
const MOUSE_SENS_Y := 0.002

var defaults := {}
var overrides := {}
## accumulated this frame (radians already scaled), consumed by the follow camera
var look := Vector2.ZERO
var wheel := 0
var mouse_sensitivity := 1.0
## aim assist friction: look speed multiplier while the crosshair is on an enemy (1 = none)
var aim_friction := 1.0
var invert_y := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var c: Dictionary = CKData.json("controls")
	for a in ACTIONS:
		defaults[a[0]] = c.get(a[0], "")
	defaults.merge({"slotPrev": "KeyQ", "slotNext": "KeyR", "inventory": "Tab", "map": "KeyM", "perfOverlay": "F3",
		"reload": "KeyT", "vehicleMode": "KeyB", "eject": "KeyX", "talkToRed": "KeyY", "chatRed": "Enter",
		"villainTalk": "KeyK", "villainType": "KeyJ", "helmetView": "KeyH", "vision": "KeyN"}, true)
	for i in 10:
		defaults["slot%d" % (i + 1)] = "Digit%d" % ((i + 1) % 10)
	apply()


func code(action: String) -> String:
	return overrides.get(action, defaults.get(action, ""))


func rebind(action: String, new_code: String) -> void:
	# a key can only drive one action: swap with whoever had it
	for a in defaults:
		if a != action and code(a) == new_code:
			overrides[a] = code(action)
	overrides[action] = new_code
	apply()


func reset_bindings() -> void:
	overrides.clear()
	apply()


func apply() -> void:
	for a in defaults:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
		else:
			InputMap.add_action(a, 0.2)
		var ev := event_for(code(a))
		if ev:
			InputMap.action_add_event(a, ev)
	_add_pad()
	bindings_changed.emit()


func _add_pad() -> void:
	# the web build's standard-gamepad layout (see the Controls note in the settings screen)
	var pad := {"jump": JOY_BUTTON_A, "crouch": JOY_BUTTON_B, "interact": JOY_BUTTON_X, "inventory": JOY_BUTTON_Y,
		"sprint": JOY_BUTTON_LEFT_STICK, "pause": JOY_BUTTON_START, "map": JOY_BUTTON_BACK,
		"slotPrev": JOY_BUTTON_LEFT_SHOULDER, "slotNext": JOY_BUTTON_RIGHT_SHOULDER, "summonMenu": JOY_BUTTON_DPAD_UP,
		"reload": JOY_BUTTON_DPAD_LEFT, "vehicleMode": JOY_BUTTON_DPAD_RIGHT, "vehicleExit": JOY_BUTTON_DPAD_DOWN}
	for a in pad:
		var e := InputEventJoypadButton.new()
		e.button_index = pad[a]
		InputMap.action_add_event(a, e)
	for pair in [["moveLeft", JOY_AXIS_LEFT_X, -1.0], ["moveRight", JOY_AXIS_LEFT_X, 1.0],
			["moveForward", JOY_AXIS_LEFT_Y, -1.0], ["moveBack", JOY_AXIS_LEFT_Y, 1.0],
			["secondaryAction", JOY_AXIS_TRIGGER_LEFT, 1.0], ["primaryAction", JOY_AXIS_TRIGGER_RIGHT, 1.0]]:
		var m := InputEventJoypadMotion.new()
		m.axis = pair[1]
		m.axis_value = pair[2]
		InputMap.action_add_event(pair[0], m)


## KeyboardEvent.code / "MouseN" -> InputEvent (physical keys, so layouts behave like the web build).
static func event_for(c: String) -> InputEvent:
	if c.begins_with("Mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_XBUTTON1,
			MOUSE_BUTTON_XBUTTON2][clampi(int(c.substr(5)), 0, 4)]
		return m
	var k := InputEventKey.new()
	k.physical_keycode = keycode_for(c)
	return k if k.physical_keycode != KEY_NONE else null


static func keycode_for(c: String) -> Key:
	if c.begins_with("Key") and c.length() == 4:
		return OS.find_keycode_from_string(c.substr(3))
	if c.begins_with("Digit"):
		return OS.find_keycode_from_string(c.substr(5))
	var named := {"ShiftLeft": KEY_SHIFT, "ShiftRight": KEY_SHIFT, "ControlLeft": KEY_CTRL, "ControlRight": KEY_CTRL,
		"AltLeft": KEY_ALT, "AltRight": KEY_ALT, "Space": KEY_SPACE, "Escape": KEY_ESCAPE, "Tab": KEY_TAB,
		"CapsLock": KEY_CAPSLOCK, "Backquote": KEY_QUOTELEFT, "Enter": KEY_ENTER, "Backspace": KEY_BACKSPACE,
		"ArrowUp": KEY_UP, "ArrowDown": KEY_DOWN, "ArrowLeft": KEY_LEFT, "ArrowRight": KEY_RIGHT,
		"Minus": KEY_MINUS, "Equal": KEY_EQUAL, "BracketLeft": KEY_BRACKETLEFT, "BracketRight": KEY_BRACKETRIGHT,
		"Semicolon": KEY_SEMICOLON, "Quote": KEY_APOSTROPHE, "Comma": KEY_COMMA, "Period": KEY_PERIOD, "Slash": KEY_SLASH}
	if named.has(c):
		return named[c]
	return OS.find_keycode_from_string(c)


## Web-style code for a captured event (used by the keybinding screen).
static func code_for_event(e: InputEvent) -> String:
	if e is InputEventMouseButton:
		return {MOUSE_BUTTON_LEFT: "Mouse0", MOUSE_BUTTON_MIDDLE: "Mouse1", MOUSE_BUTTON_RIGHT: "Mouse2"}.get(e.button_index, "")
	if e is InputEventKey:
		var k: Key = e.physical_keycode
		if k >= KEY_A and k <= KEY_Z:
			return "Key" + OS.get_keycode_string(k)
		if k >= KEY_0 and k <= KEY_9:
			return "Digit" + OS.get_keycode_string(k)
		var rev := {KEY_SHIFT: "ShiftLeft", KEY_CTRL: "ControlLeft", KEY_ALT: "AltLeft", KEY_SPACE: "Space",
			KEY_TAB: "Tab", KEY_CAPSLOCK: "CapsLock", KEY_QUOTELEFT: "Backquote", KEY_ENTER: "Enter"}
		return rev.get(k, OS.get_keycode_string(k))
	return ""


## Short label for HUD prompts ("E", "LMB", "Shift").
func label(action: String) -> String:
	var c := code(action)
	if c.begins_with("Key") and c.length() == 4:
		return c.substr(3)
	if c.begins_with("Digit"):
		return c.substr(5)
	return {"Mouse0": "LMB", "Mouse2": "RMB", "Mouse1": "MMB", "ShiftLeft": "Shift", "Space": "Space",
		"Escape": "Esc", "Backquote": "`", "CapsLock": "Caps"}.get(c, c)


## Camera-relative movement wish: x = right, y = forward (like Input.moveX / moveY).
func move() -> Vector2:
	var v := Vector2(Input.get_axis("moveLeft", "moveRight"), Input.get_axis("moveBack", "moveForward"))
	return v.limit_length(1.0)


func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look += e.relative * mouse_sensitivity
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel -= 1
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel += 1


func _process(_dt: float) -> void:
	# right stick look (pixels-per-frame equivalent, like input.ts)
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.15:
		look += Vector2(rs.x * 14.0, rs.y * 10.0)


## Consume and return the look delta in radians: x = yaw, y = pitch.
func take_look() -> Vector2:
	var l := Vector2(look.x * MOUSE_SENS_X, look.y * MOUSE_SENS_Y * (-1.0 if invert_y else 1.0)) * aim_friction
	look = Vector2.ZERO
	return l


func take_wheel() -> int:
	var w := wheel
	wheel = 0
	return w
