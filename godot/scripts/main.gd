extends Node3D
## Game root (port of main.ts). Builds the stage, the New Gotham district, the player and camera.
##
## Test/debug command line (after `--`):
##   --quality=low|medium|high|ultra   force a preset for this run
##   --at=x,y,z --yaw=r                 spawn the player (feet) and camera yaw
##   --hold=moveForward,sprint          hold actions for the scripted run
##   --frames=N --shot=path.png         run N frames, save a screenshot, quit
##   --log                              print player status every 30 frames
##   --camdist=m --pitch=r              camera distance / pitch (close-ups)
##   --slot=N                           select hotbar slot N (1-8) at start
##   --menu=main|pause|inventory|...    open a menu (scripted runs start in-game otherwise)
##   --notify=text                      post a HUD notification at start

var stage: Stage
var district: District
var citadel: Citadel
var underground := false
var portal := Vector3.ZERO
var player: Player
var cam: FollowCamera
var npcs: NpcCrowd
var effects: Effects
var equipment: Equipment
var inventory := Inventory.new()
var vitals := Vitals.new()
var saves := SaveService.new()
var settings: Dictionary
var quick_vehicle := "crx1_interceptor"
var hud: Hud
var menus: Menus
var perf: Label
var started := false
var _forced_quality := ""
var _autosave := 0.0
var spawn := Vector3.ZERO
## interact prompt for the HUD: [action, text] or []
var prompt: Array = []
var args := {}
var frame := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps scripted runs ticking while a menu pauses the tree
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var prefs := saves.read_settings()
	settings = prefs["settings"]
	CKInput.overrides = prefs["bindings"]
	CKInput.apply()
	if args.has("frames"):
		# scripted runs ignore the real keyboard, mouse and pads (someone may be typing while the test window
		# pops up); --hold/--press drive actions directly, which needs no bound events
		CKInput.bindings_changed.connect(func():
			for act in InputMap.get_actions():
				if not String(act).begins_with("ui_"):
					InputMap.action_erase_events(act))
		CKInput.apply()
		print("[ck] scripted run: real input ignored")
	# first launch: LOW on integrated GPUs (the target laptop's Radeon 610M), HIGH otherwise
	if prefs["fresh"]:
		settings["quality"] = Quality.detect_default()
	# --quality forces a preset for this run only; never saved
	if args.has("quality") and args["quality"] in Quality.ORDER:
		_forced_quality = args["quality"]
	stage = Stage.new()
	add_child(stage)
	district = District.new()
	add_child(district)
	district.build()
	citadel = Citadel.new()
	add_child(citadel)
	citadel.build()
	var pa: Array = CKData.json("world")["redCitadelPortal"]
	portal = Vector3(pa[0], pa[1], pa[2])
	npcs = NpcCrowd.new()
	add_child(npcs)
	npcs.build()
	effects = Effects.new()
	add_child(effects)
	var sp: Array = CKData.json("world")["spawn"]
	spawn = Vector3(sp[0], sp[1] - 2, sp[2])
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.landed.connect(_on_land)
	player.teleport(_vec(args.get("at", ""), spawn))
	if args.get("at", "") == "citadel":
		player.teleport(citadel.anchor("Anchor_Arrival"))
	cam = FollowCamera.new()
	cam.target = player
	add_child(cam)
	if args.has("yaw"):
		cam.yaw = float(args["yaw"])
	if args.has("camdist"):
		cam.distance = float(args["camdist"])
	if args.has("pitch"):
		cam.pitch = float(args["pitch"])
	stage.camera = cam.camera
	cam.camera.make_current()
	equipment = Equipment.new()
	equipment.player = player
	equipment.camera = cam.camera
	equipment.district = district
	equipment.effects = effects
	equipment.inventory = inventory
	equipment.vitals = vitals
	equipment.notify.connect(notify)
	add_child(equipment)
	equipment.photo_mode_changed.connect(func(_on): _apply_hud_visibility())
	_build_ui()
	apply_settings()
	if args.has("hold"):
		for act in String(args["hold"]).split(","):
			Input.action_press(act)
	if args.has("slot"):
		select_slot.call_deferred(int(args["slot"]) - 1)
	if args.has("notify"):
		notify(args["notify"], "notification")
	if args.has("menu"):
		started = args["menu"] != "main"
		menus.show_screen(args["menu"])
	elif args.has("frames"):
		started = true # scripted runs start in-game
	else:
		menus.show_screen("main")
		_on_menus_open(true)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	hud = Hud.new()
	hud.inventory = inventory
	hud.vitals = vitals
	hud.slot_clicked.connect(select_slot)
	layer.add_child(hud)
	perf = Label.new()
	perf.position = Vector2(18, 110)
	perf.add_theme_font_size_override("font_size", 13)
	perf.add_theme_color_override("font_color", Color("#9fe7a4"))
	perf.add_theme_color_override("font_shadow_color", Color.BLACK)
	perf.visible = false
	layer.add_child(perf)
	menus = Menus.new()
	menus.game = self
	menus.inventory = inventory
	menus.open_changed.connect(_on_menus_open)
	layer.add_child(menus)


## Menus pause the simulation; the mouse is freed while one is open.
func _on_menus_open(open: bool) -> void:
	if args.has("log"):
		print("[ck] f%d menus %s %s" % [frame, "open" if open else "closed", menus.top()])
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or args.has("frames") else Input.MOUSE_MODE_CAPTURED
	for a in ["moveForward", "moveBack", "moveLeft", "moveRight", "sprint", "jump", "grapple", "primaryAction"]:
		if not args.get("hold", "").contains(a):
			Input.action_release(a) # nothing stays held across a menu


## Apply settings (preset, light pools, UI scale, HUD) and persist them with the bindings.
func apply_settings() -> void:
	var q: String = _forced_quality if _forced_quality != "" else settings["quality"]
	var pools_changed: bool = stage.preset["dynamic_lights"] != Quality.PRESETS[q]["dynamic_lights"] or district._light_pool.is_empty()
	stage.apply_quality(q)
	district.wet.set_shader_parameter("ripples", 0.0 if q == "low" else 1.0)
	if pools_changed:
		district.set_light_pool(stage.preset["dynamic_lights"], stage.preset["light_shadows"])
		citadel.set_light_pool(maxi(4, stage.preset["dynamic_lights"]))
	get_tree().root.content_scale_factor = settings["uiScale"]
	_apply_hud_visibility()
	saves.write_settings(settings, CKInput.overrides)


func _apply_hud_visibility() -> void:
	hud.widgets.visible = settings["hudVisible"] and not equipment.photo_mode


func _snapshot() -> Dictionary:
	var p := player.global_position
	return {"inventory": inventory.snapshot(), "bindings": CKInput.overrides, "quickVehicle": quick_vehicle, "settings": settings,
		"player": {"position": [p.x, p.y, p.z], "heading": player.heading}}


func save_now() -> void:
	saves.write(_snapshot())
	notify("Game saved", "save")


func play() -> void:
	started = true


func continue_save() -> void:
	var s = saves.read()
	if s == null:
		return
	inventory.load_state(s["inventory"])
	quick_vehicle = s.get("quickVehicle", quick_vehicle)
	if s.get("player") is Dictionary:
		var pos: Array = s["player"]["position"]
		player.teleport(Vector3(pos[0], pos[1] + 0.05, pos[2]))
		player.heading = s["player"]["heading"]
		cam.snap()
	_equip_selected()
	started = true
	notify("Save loaded", "load")


func new_sandbox() -> void:
	saves.clear()
	inventory.reset()
	vitals.reset()
	player.respawn(spawn + Vector3(0, 1, 0))
	_equip_selected()
	started = true
	notify("New sandbox started. Explore freely", "sandbox")


## On-screen notification (HUD toast); also logged for scripted runs.
func notify(text: String, icon := "notification", kind := "info") -> void:
	hud.notify(text, icon, kind)
	if args.has("log"):
		print("[ck] notify(%s) %s" % [kind, text])


## Select a hotbar slot: equip animation and the gear model on its socket. Never uses the item.
func select_slot(i: int) -> void:
	var err := inventory.select_slot(i)
	if i >= 0 and i < 8:
		hud.flash(i)
	if err != "":
		notify(err, "inventory", "warn")
		return
	_equip_selected()


func _equip_selected() -> void:
	var id := inventory.selected_item()
	player.set_gadget(id)
	player.hero.hold(inventory.def(id).get("modelId", "") if id != "" else "")


func _on_land(vy: float, hard: bool, feet: Vector3) -> void:
	effects.landing(feet, hard)
	var dmg := vitals.impact(vy, Time.get_ticks_msec(), CKData.json("physics")["player"]["hardLandingSpeed"])
	if dmg > 0:
		notify("Impact damage -%d health" % roundi(dmg), "health", "warn")


func _vec(s: String, fallback: Vector3) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else fallback


## Menu hotkeys while playing (Esc / Tab / M) and the F3 perf readout. Menus handle their own keys.
func _unhandled_input(e: InputEvent) -> void:
	if not started or menus.is_open():
		return
	if e.is_action_pressed("pause"):
		menus.show_screen("pause")
	elif e.is_action_pressed("inventory"):
		menus.show_screen("inventory")
	elif e.is_action_pressed("map"):
		menus.show_screen("map")
	elif e.is_action_pressed("perfOverlay"):
		perf.visible = not perf.visible
	else:
		return
	get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	frame += 1
	var now := Time.get_ticks_msec()
	# --press=jump@60,crouch@200: tap an action on a frame (scripted tests)
	for tap in String(args.get("press", "")).split(",", false):
		var at := tap.split("@")
		if at.size() == 2 and int(at[1]) in [frame, frame - 1]:
			# a real input event, so menu hotkeys (_unhandled_input) see it too; it lands next frame
			var ev := InputEventAction.new()
			ev.action = at[0]
			ev.pressed = int(at[1]) == frame
			Input.parse_input_event(ev)
	hud.visible = menus.top() != "main"
	if get_tree().paused:
		_finish_check()
		return
	_gameplay_input(now)
	player.handle_input()
	player.cam_yaw = cam.yaw
	player.glide_held = Input.is_action_pressed("jump")
	cam.aiming = Input.is_action_pressed("grapple")
	_interact()
	player.can_exert = vitals.energy > 1
	equipment.update(dt, now)
	inventory.tick(now)
	vitals.update(dt, now, "sprint" if player.sprinting() else "glide" if player.mode == "glide" else "")
	if vitals.critical():
		notify("CR-X9 suit critical: emergency recall to spawn", "health", "warn")
		vitals.reset()
		player.respawn(spawn + Vector3(0, 1, 0))
	underground = citadel.update(player.global_position, dt)
	stage.set_underground(underground)
	district.visible = not underground # sector streaming: the city does not render underground
	npcs.visible = not underground
	if not underground:
		district.update_lights(player.global_position, now, dt)
		npcs.update(player.global_position, dt)
	stage.follow(player.global_position)
	player.hero.update_lod(cam.camera.global_position.distance_to(player.global_position),
		stage.preset["lod_scale"], stage.preset["hero_min_lod"])
	if args.has("log") and frame % 30 == 0:
		print("[ck] f%d pos=%s %s lod=%d fps=%d%s" % [frame, player.global_position.snapped(Vector3.ONE * 0.01),
			player.status, player.hero.lod_level, Engine.get_frames_per_second(),
			" citadel rooms=%d" % citadel.visible_rooms if underground else ""])
		var held: Node3D = player.hero._held
		if held and frame == 60:
			var sk := player.hero.skeleton
			var bone := sk.find_bone(held.get_meta("attach", ""))
			var meshes := held.find_children("*", "MeshInstance3D", true, false)
			print("    held ", held.get_meta("asset_id", "?"), " on ", held.get_meta("attach", "?"), " at ", held.global_position.snapped(Vector3.ONE * 0.01),
				" bone at ", (sk.global_transform * sk.get_bone_global_pose(bone)).origin.snapped(Vector3.ONE * 0.01),
				" meshes=", meshes.size(), " visible=", held.is_visible_in_tree(),
				" size=", (meshes[0].get_aabb().size if meshes.size() else Vector3.ZERO).snapped(Vector3.ONE * 0.01))
		if prompt:
			print("    prompt ", prompt, " hud=", hud._prompt.visible, " ", hud._prompt.get_global_rect())
		var mv: Vector2 = CKInput.move()
		if mv != Vector2.ZERO:
			print("    move=", mv, " joypads=", Input.get_connected_joypads().map(func(j): return Input.get_joy_name(j)),
				" fwd=", Input.get_action_strength("moveForward"), " back=", Input.get_action_strength("moveBack"))
		for i in player.get_slide_collision_count():
			var c := player.get_slide_collision(i)
			print("    hit ", c.get_collider().name if c.get_collider() else "?", " n=", c.get_normal().snapped(Vector3.ONE * 0.01))
	var sel := inventory.selected_item()
	hud.update_hud(now, player.heading, player.aiming or ((sel == "grapple" or sel == "batarang") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED))
	hud.set_prompt("interact" if prompt else "", prompt[1] if prompt else "")
	if perf.visible:
		perf.text = "%d fps · %.1f ms · %d draws · %dk prims · %s · %s
(readout only, not a benchmark)" % [
			Engine.get_frames_per_second(), 1000.0 / maxf(1, Engine.get_frames_per_second()),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			stage.quality.to_upper(), "Red Citadel (%d rooms)" % citadel.visible_rooms if underground else "Downtown"]
	_autosave += dt
	if started and _autosave > 30:
		_autosave = 0
		saves.write(_snapshot())
	_finish_check()


func _finish_check() -> void:
	if args.has("frames") and frame >= int(args["frames"]):
		_finish()


## Hotbar: 1-8 select (never use), Q/R or wheel cycle, primary action uses; vehicle call.
func _gameplay_input(now: int) -> void:
	for i in 8:
		if Input.is_action_just_pressed("slot%d" % (i + 1)):
			select_slot(i)
	var wheel := CKInput.take_wheel()
	var before := inventory.selected_slot
	if Input.is_action_just_pressed("slotPrev") or wheel < 0:
		inventory.cycle(-1)
	if Input.is_action_just_pressed("slotNext") or wheel > 0:
		inventory.cycle(1)
	if inventory.selected_slot != before:
		_equip_selected()
	if Input.is_action_just_pressed("primaryAction"):
		if args.has("log"):
			print("[ck] use ", inventory.selected_item())
		equipment.use_selected(now)
	if Input.is_action_just_pressed("summonMenu"):
		var v := inventory.def("crx1_interceptor")
		player.act("CK_Summon")
		notify("%s: %s" % [v["displayName"], v.get("unavailableReason", "on the way")], v["iconId"], "warn")


func _nearest_prop() -> RigidBody3D:
	var best: RigidBody3D = null
	var best_d := 2.6
	for b in district.dynamic:
		var d := Vector2(b.global_position.x - player.global_position.x, b.global_position.z - player.global_position.z).length()
		if d < best_d:
			best_d = d
			best = b
	return best


## Real interactables: shove loose props, Citadel entrance (keycard) and exit elevator.
func _interact() -> void:
	var p := player.global_position
	var prop := _nearest_prop() if not underground else null
	var near_portal := not underground and p.distance_to(portal) < 9
	var near_exit := underground and p.distance_to(citadel.anchor("Anchor_Exit")) < 4
	prompt = []
	if prop or near_portal or near_exit:
		prompt = ["interact", "Shove" if prop else "Enter the Red Citadel" if near_portal else "Elevator to New Gotham"]
	if not Input.is_action_just_pressed("interact"):
		return
	if prop:
		var dir := (prop.global_position - p)
		dir.y = 0.4
		prop.apply_central_impulse(dir.normalized() * 5 * prop.mass)
	elif near_portal:
		if not inventory.has("citadel_keycard"):
			notify("Access denied: Red Citadel keycard required", "keycard", "warn")
			return
		player.teleport(citadel.anchor("Anchor_Arrival"))
		player.heading = PI # face north (-Z), toward the hub tunnel
		cam.yaw = 0.0
		cam.snap()
		notify("Welcome to the Red Citadel", "citadel")
	elif near_exit:
		player.teleport(portal + Vector3(0, 0.5, 8))
		cam.snap()
		notify("Returned to New Gotham", "home")


func _finish() -> void:
	set_process(false)
	if args.has("shot"):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["shot"])
		print("[ck] screenshot ", args["shot"])
	get_tree().quit()
