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
##   --vehicle=id                       summon a vehicle and get in (crx1_interceptor / crb1_batcycle / cra1_specter)
##   --chase                            start driving in the chase camera
##   --equip=item_id                    put an item in slot 1 and select it
##   --autofight                        (test) counter every wind-up and strike when in reach
##   --autoaim                          (test) keep the crosshair on the nearest enemy
##   --aimat=x,y,z                      keep the camera centre on a world point (weapon tests)
##   --bench                            run the 6-scene benchmark for the current preset, write JSON, quit
##   --animdebug=CK_Clip                open the animation debug panel on a clip
##   --burst=sparks|smoke|debris|electrical   keep spawning effect sprites (effects test)
##   --crime                            start a street crime right away
##   --nomissions                       don't start the story missions
##   --mission=N                        start at story mission N (0-based)
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
var audio: CKAudio
var weapons: Weapons
var drive: DriveController
var anim_debug: AnimDebug
var red: RedAI
var vweapons: VehicleWeapons
var red_panel: RedPanel
var director: Director
var street: StreetLife
var melee: Melee
var targets: TargetRange
var _step_dist := 0.0
var _last_pos := Vector3.ZERO
var spawn := Vector3.ZERO
## interact prompt for the HUD: [action, text] or []
var prompt: Array = []
var args := {}
var frame := 0
var _block_hold := 0.0
var _last_speed := 0.0
var _servo_at := 0


## Footstep sound for what the Knight is standing on: Citadel decks are metal, roofs are gravel, roads asphalt,
## and any street surface splashes while it's raining.
func _step_sound() -> String:
	if underground:
		return "armor.step.metal"
	var p := player.global_position
	if p.y > 4.0:
		return "armor.step.gravel"
	if stage.weather > 0.3:
		return "armor.step.wet"
	var S := District.SPACING
	var off := minf(absf(p.x - roundf(p.x / S) * S), absf(p.z - roundf(p.z / S) * S))
	return "armor.step.asphalt" if off < District.ROAD_HALF else "armor.step"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps scripted runs ticking while a menu pauses the tree
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var prefs := saves.read_settings()
	settings = prefs["settings"]
	CKInput.overrides = prefs["bindings"]
	CKInput.apply()
	if args.has("frames") or args.has("bench"):
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
	audio = CKAudio.new()
	add_child(audio)
	# loading screen: each heavy build step gets a drawn frame; gameplay waits until the world exists
	set_process(false)
	var loading := LoadingScreen.new(5)
	add_child(loading)
	await loading.step("night city lighting")
	stage = Stage.new()
	add_child(stage)
	await loading.step("New Gotham district")
	district = District.new()
	add_child(district)
	district.build()
	await loading.step("Red Citadel")
	citadel = Citadel.new()
	add_child(citadel)
	citadel.build()
	var pa: Array = CKData.json("world")["redCitadelPortal"]
	portal = Vector3(pa[0], pa[1], pa[2])
	await loading.step("NPC population")
	npcs = NpcCrowd.new()
	add_child(npcs)
	npcs.build()
	effects = Effects.new()
	add_child(effects)
	var sp: Array = CKData.json("world")["spawn"]
	spawn = Vector3(sp[0], sp[1] - 2, sp[2])
	await loading.step("CR-X9 Crimson Knight")
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
	player.camera = cam.camera
	cam.camera.make_current()
	equipment = Equipment.new()
	equipment.player = player
	equipment.camera = cam.camera
	equipment.district = district
	equipment.effects = effects
	equipment.inventory = inventory
	equipment.vitals = vitals
	equipment.notify.connect(notify)
	equipment.sound.connect(audio.play)
	weapons = Weapons.new()
	weapons.player = player
	weapons.cam = cam
	weapons.effects = effects
	weapons.inventory = inventory
	weapons.sound.connect(audio.play)
	weapons.notify.connect(notify)
	add_child(weapons)
	drive = DriveController.new()
	drive.player = player
	drive.cam = cam
	drive.audio = audio
	drive.effects = effects
	drive.sound.connect(audio.play)
	drive.notify.connect(notify)
	add_child(drive)
	director = Director.new()
	director.player = player
	director.effects = effects
	director.vitals = vitals
	director.drive = drive
	director.notify.connect(notify)
	director.sound_event.connect(audio.play)
	add_child(director)
	equipment.director = director
	melee = Melee.new()
	melee.player = player
	melee.cam = cam
	melee.director = director
	melee.effects = effects
	melee.audio = audio
	add_child(melee)
	director.melee = melee
	street = StreetLife.new()
	street.player = player
	street.district = district
	street.drive = drive
	add_child(street)
	street.build()
	weapons.noise.connect(func(at, r): street.panic(at, r * 0.6))
	weapons.noise.connect(director.noise)
	weapons.director = director
	vweapons = VehicleWeapons.new()
	vweapons.weapons = weapons
	vweapons.director = director
	vweapons.sound.connect(audio.play)
	vweapons.notify.connect(notify)
	add_child(vweapons)
	targets = TargetRange.new()
	add_child(targets)
	# training dummies on the north avenue sidewalks (facing the spawn) and in the industrial yard
	targets.build([[Vector3(11.4, 0.15, -26), 0.0, "N1"], [Vector3(-11.4, 0.15, -30), 0.0, "N2"], [Vector3(11.4, 0.15, -38), 0.0, "N3"],
		[Vector3(-11.4, 0.15, -44), 0.0, "N4"], [Vector3(30, 0.15, 11.6), PI, "E1"], [Vector3(36, 0.15, 11.6), PI, "E2"]])
	add_child(equipment)
	equipment.photo_mode_changed.connect(func(_on): _apply_hud_visibility())
	equipment.drone_view.connect(func(on):
		cam.active = not on
		player.frozen = on
		if on:
			player.velocity = Vector3.ZERO)
	_build_ui()
	weapons.hit_confirmed.connect(hud.hit_marker)
	director.player_hurt.connect(func(amount, from):
		hud.damage_flash(amount, from, player.global_position, cam.yaw)
		audio.play("weapon.impact"))
	hud.director = director
	hud.weapons = weapons
	hud.stage = stage
	stage.thunder.connect(func(): if not underground: audio.play("explosion", 0.5))
	red = RedAI.new()
	red.game = self
	add_child(red)
	red.watch_director(director)
	red_panel = RedPanel.new()
	CKUI.place(red_panel, Vector4(0, 0, 0, 0), Vector4(18, 124, 418, 330))
	hud.widgets.add_child(red_panel)
	red.line.connect(red_panel.add_line)
	if args.has("log"):
		red.line.connect(func(who, t): print("[red] f%d %s: %s" % [frame, who, t]))
	red.status_changed.connect(red_panel.set_status)
	red.voice.speaking_changed.connect(func(on): red_panel.speaking = on)
	red_panel.submitted.connect(red.hear)
	red_panel.chat_open_changed.connect(_on_red_chat)
	melee.combo_changed.connect(hud.show_combo)
	hud.minimap.game = self
	if args.has("log"):
		weapons.hit_confirmed.connect(func(kill): print("[ck] f%d hit%s %s" % [frame, " KNOCKDOWN" if kill else "", weapons.status(Time.get_ticks_msec())]))
	apply_settings()
	if args.has("hold"):
		for act in String(args["hold"]).split(","):
			Input.action_press(act)
	if args.has("vehicle"):
		quick_vehicle = args["vehicle"]
		(func():
			drive.summon(quick_vehicle, false)
			drive.enter(drive.vehicles[quick_vehicle])
			if args.has("chase"):
				drive.driving.view = "chase"
				drive._apply_camera()).call_deferred()
	if args.has("equip"):
		inventory.assign(args["equip"], 0)
		select_slot.call_deferred(0)
	if args.has("slot"):
		select_slot.call_deferred(int(args["slot"]) - 1)
	if args.has("animdebug"):
		(func():
			anim_debug.toggle()
			anim_debug.select(args["animdebug"])).call_deferred()
	if args.has("mission"):
		director.mission_index = int(args["mission"])
	if args.has("crime"):
		(func(): director.start_crime()).call_deferred()
	if args.has("notify"):
		notify(args["notify"], "notification")
	if args.has("menu"):
		started = args["menu"] != "main"
		menus.show_screen(args["menu"])
	elif args.has("bench"):
		play()
		var bench := Benchmark.new()
		bench.game = self
		add_child(bench)
		bench.finished.connect(func(_r): get_tree().quit())
		bench.start.call_deferred()
	elif args.has("frames"):
		play() # scripted runs start in-game
	else:
		menus.show_screen("main")
		_on_menus_open(true)
	loading.finish()
	set_process(true)


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
	anim_debug = AnimDebug.new()
	anim_debug.player = player
	layer.add_child(anim_debug)
	menus = Menus.new()
	menus.game = self
	menus.inventory = inventory
	menus.open_changed.connect(_on_menus_open)
	layer.add_child(menus)


## Typing to R.E.D. pauses the action (a comms moment) and frees the mouse for the text field.
func _on_red_chat(open: bool) -> void:
	get_tree().paused = open
	audio.set_paused(open)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or args.has("frames") or args.has("bench") else Input.MOUSE_MODE_CAPTURED
	for a in ["moveForward", "moveBack", "moveLeft", "moveRight", "sprint", "jump", "primaryAction", "secondaryAction"]:
		Input.action_release(a)


## Menus pause the simulation; the mouse is freed while one is open.
func _on_menus_open(open: bool) -> void:
	audio.play("ui.open" if open else "ui.close")
	audio.set_paused(open)
	if args.has("log"):
		print("[ck] f%d menus %s %s" % [frame, "open" if open else "closed", menus.top()])
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or args.has("frames") or args.has("bench") else Input.MOUSE_MODE_CAPTURED
	for a in ["moveForward", "moveBack", "moveLeft", "moveRight", "sprint", "jump", "grapple", "primaryAction", "secondaryAction"]:
		if not args.get("hold", "").contains(a):
			Input.action_release(a) # nothing stays held across a menu


## Apply settings (preset, light pools, UI scale, HUD) and persist them with the bindings.
func apply_settings() -> void:
	var q: String = _forced_quality if _forced_quality != "" else settings["quality"]
	var gfx: Dictionary = settings["graphics"]
	var pools_changed: bool = stage.preset["dynamic_lights"] != Quality.resolve(q, gfx)["dynamic_lights"] or district._light_pool.is_empty()
	stage.apply_quality(q, gfx)
	district.wet.set_shader_parameter("ripples", 0.0 if q == "low" else 1.0)
	if pools_changed:
		district.set_light_pool(stage.preset["dynamic_lights"], stage.preset["light_shadows"])
		citadel.set_light_pool(maxi(4, stage.preset["dynamic_lights"]))
	get_tree().root.content_scale_factor = settings["uiScale"]
	audio.apply_settings(settings)
	Vehicle.reduce_motion = settings["reduceMotion"]
	CKInput.mouse_sensitivity = settings["mouseSensitivity"]
	CKInput.invert_y = settings["invertY"]
	weapons.aim_assist = settings.get("aimAssist", true)
	stage.cycle = settings["dayNight"]
	hud.hints_enabled = settings.get("controlHints", true)
	red.chatter_enabled = settings["redChatter"]
	if red.ai_dir != "" and [red.voice.tts_enabled, red.voice.stt_enabled, red.brain_enabled] != [settings["redVoice"], settings["redListen"], settings["redBrain"]]:
		red.stop_engines()
		red.start_engines(settings["redVoice"], settings["redListen"], settings["redBrain"])
	melee.reduce_motion = settings["reduceMotion"]
	FollowCamera.reduce_motion = settings["reduceMotion"]
	_apply_hud_visibility()
	saves.write_settings(settings, CKInput.overrides)


func _apply_hud_visibility() -> void:
	hud.widgets.visible = settings["hudVisible"] and not equipment.photo_mode


func _snapshot() -> Dictionary:
	var p := player.global_position
	return {"inventory": inventory.snapshot(), "bindings": CKInput.overrides, "quickVehicle": quick_vehicle, "settings": settings,
		"world": director.snapshot(),
		"player": {"position": [p.x, p.y, p.z], "heading": player.heading}}


func save_now() -> void:
	saves.write(_snapshot())
	notify("Game saved", "save")


func play() -> void:
	if not started and director.mission.is_empty() and not args.has("nomissions"):
		director.start_mission(director.mission_index)
	started = true
	audio.start_ambience()
	# R.E.D.'s local engines (voice, ears, LLM) start with play; scripted runs skip them unless --red
	if red.ai_dir == "" and (not (args.has("frames") or args.has("bench")) or args.has("red")):
		red.start_engines(settings["redVoice"], settings["redListen"], settings["redBrain"])


func continue_save() -> void:
	var s = saves.read()
	if s == null:
		return
	inventory.load_state(s["inventory"])
	if s.get("world") is Dictionary:
		director.load_state(s["world"])
	quick_vehicle = s.get("quickVehicle", quick_vehicle)
	if s.get("player") is Dictionary:
		var pos: Array = s["player"]["position"]
		player.teleport(Vector3(pos[0], pos[1] + 0.05, pos[2]))
		player.heading = s["player"]["heading"]
		cam.snap()
	_equip_selected()
	play()
	notify("Save loaded", "load")


func new_sandbox() -> void:
	saves.clear()
	inventory.reset()
	vitals.reset()
	director.load_state({})
	player.respawn(spawn + Vector3(0, 1, 0))
	_equip_selected()
	play()
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
		audio.play("ui.deny")
		return
	audio.play("ui.select")
	_equip_selected()


func _equip_selected() -> void:
	var id := inventory.selected_item()
	player.set_gadget(id)
	player.hero.hold(inventory.def(id).get("modelId", "") if id != "" else "")
	weapons.on_equip(id)


func _on_land(vy: float, hard: bool, feet: Vector3) -> void:
	effects.landing(feet, hard)
	if args.has("log"):
		print("[ck] f%d landed vy=%.1f hard=%s" % [frame, vy, hard])
	audio.play("armor.land", minf(1.0, -vy / 20.0))
	var dmg := vitals.impact(vy, Time.get_ticks_msec(), CKData.json("physics")["player"]["hardLandingSpeed"])
	if dmg > 0:
		notify("Impact damage -%d health" % roundi(dmg), "health", "warn")


func _vec(s: String, fallback: Vector3) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else fallback


## Menu hotkeys while playing (Esc / Tab / M) and the F3 perf readout. Menus handle their own keys.
func _unhandled_input(e: InputEvent) -> void:
	if menus == null or not started or menus.is_open(): # menus is null while loading
		return
	if e.is_action_pressed("pause"):
		menus.show_screen("pause")
	elif e.is_action_pressed("inventory"):
		menus.show_screen("inventory")
	elif e.is_action_pressed("map"):
		menus.show_screen("map")
	elif e.is_action_pressed("chatRed") and not red_panel.is_chat_open():
		red_panel.open_chat()
	elif e.is_action_pressed("perfOverlay"):
		perf.visible = not perf.visible
	elif e.is_action_pressed("sandboxMenu") and not drive.driving:
		anim_debug.toggle()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	frame += 1
	var now := Time.get_ticks_msec()
	# --press=jump@60,crouch@200: tap an action on a frame (scripted tests)
	for tap in String(args.get("press", "")).split(",", false):
		if tap.begins_with("+"): # +action@frame: press and keep holding
			var hold := tap.substr(1).split("@")
			if hold.size() == 2 and int(hold[1]) == frame:
				Input.action_press(hold[0])
			continue
		var at := tap.split("@")
		if at.size() == 2 and int(at[1]) in [frame, frame - 1]:
			# a real input event, so menu hotkeys (_unhandled_input) see it too; it lands next frame
			var ev := InputEventAction.new()
			ev.action = at[0]
			ev.pressed = int(at[1]) == frame
			Input.parse_input_event(ev)
	for say in String(args.get("redsay", "")).split("|", false):
		var at := say.rsplit("@", true, 1)
		if at.size() == 2 and int(at[1]) == frame:
			red.hear(at[0])
	if args.has("sidecam") and drive.driving and frame > 60: # test aid: look at the vehicle from its right side
		var sc: Camera3D = get_node_or_null("SideCam")
		if sc == null:
			sc = Camera3D.new()
			sc.name = "SideCam"
			add_child(sc)
			sc.make_current()
		var dv: Vehicle = drive.driving
		sc.global_position = dv.global_transform * Vector3(-float(args["sidecam"]), 1.3, 0.3)
		sc.look_at(dv.global_position + Vector3(0, 0.9, 0), Vector3.UP)
	hud.visible = menus.top() != "main"
	if get_tree().paused:
		_finish_check()
		return
	if drive.driving:
		drive.drive(dt, CKInput.take_look())
		prompt = []
	elif equipment.piloting():
		equipment.pilot(dt, CKInput.take_look())
		prompt = []
	else:
		_on_foot(now)
	vweapons.update(dt, drive.driving, drive.driving != null and Input.is_action_pressed("primaryAction"),
		drive.driving != null and Input.is_action_just_pressed("secondaryAction"))
	hud.vehicle_text = drive.hud_text() if drive.driving else []
	if drive.driving and vweapons.armed(drive.driving):
		var mr: float = vweapons.secondary_ready_in(drive.driving)
		hud.vehicle_text = hud.vehicle_text + ["Guns %s%s" % ["OVERHEATED" if vweapons.overheated else "%d%% heat" % roundi(vweapons.heat * 100),
			"" if mr < 0 else (" · missiles ready" if mr == 0 else " · missiles %.0f s" % ceilf(mr))]]
	hud.set_hints(_control_hints())
	hud.camera = cam.camera
	hud.grapple_point = player.grapple_target.get("point") if not drive.driving and not player.grapple_target.is_empty() else null
	player.can_exert = vitals.energy > 1
	var aim_at = _vec(args["aimat"], Vector3.ZERO) if args.has("aimat") else null
	if args.has("autoaim"): # test aid: keep the crosshair on the nearest upright enemy
		var best := 1e9
		for e in director.enemies:
			if is_instance_valid(e) and not e.is_down() and e.global_position.distance_to(player.global_position) < best:
				best = e.global_position.distance_to(player.global_position)
				aim_at = e.global_position + Vector3(0, 1.2, 0)
	if aim_at != null:
		var d: Vector3 = (aim_at - cam.camera.global_position).normalized()
		cam.yaw = lerp_angle(cam.yaw, atan2(-d.x, -d.z), 0.5)
		cam.pitch = lerpf(cam.pitch, asin(-d.y), 0.5)
	if args.has("autofight") and not drive.driving: # test aid: counter every telegraph, strike when in reach
		if melee.counter_target():
			if melee.counter() and args.has("log"):
				print("[ck] f%d COUNTER" % frame)
		elif melee.engaged(false) and frame % 14 == 0:
			melee.strike(frame % 56 == 0)
	equipment.update(dt, now)
	melee.update(dt)
	var firing := drive.driving == null
	weapons.update(dt, now, firing and Input.is_action_just_pressed("primaryAction"), firing and Input.is_action_pressed("primaryAction"))
	hud.weapon_status = weapons.status(now)
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
	director.update(dt, underground)
	street.visible = not underground
	if not underground:
		street.update(dt)
	if not underground:
		district.update_lights(player.global_position, now, dt)
		npcs.update(player.global_position, dt)
	stage.follow(player.global_position)
	stage.update_sky(dt)
	district.wet.set_shader_parameter("ripples", 0.0 if stage.quality == "low" else clampf(stage.weather * 1.4 - 0.2, 0.0, 1.0))
	player.hero.update_lod(cam.camera.global_position.distance_to(player.global_position),
		stage.preset["lod_scale"], stage.preset["hero_min_lod"])
	if args.has("log") and frame % 30 == 0:
		print("[ck] f%d pos=%s %s lod=%d fps=%d%s" % [frame, player.global_position.snapped(Vector3.ONE * 0.01),
			player.status, player.hero.lod_level, Engine.get_frames_per_second(),
			" citadel rooms=%d" % citadel.visible_rooms if underground else ""])
		if director.enemies.size():
			var states := {}
			for e in director.enemies:
				if is_instance_valid(e):
					states[e.state] = states.get(e.state, 0) + 1
			print("    world hp=%d armor=%d heat=%.1f cr=%d enemies=%s obj=%s" % [vitals.health, vitals.armor, director.heat,
				director.credits, states, director.objective.left(40)])
			var e0: Enemy = director.enemies[0]
			if is_instance_valid(e0):
				print("    e0 ", e0.id, " at ", e0.global_position.snapped(Vector3.ONE * 0.1), " ", e0.state, " sees=", e0._sees_player())
		for v in drive.vehicles.values():
			if not v.driver_in:
				print("    vehicle %s at %s dist=%.0f route=%d speed=%.1f" % [v.id, v.global_position.snapped(Vector3.ONE), v.global_position.distance_to(player.global_position), v.route.size(), v.speed()])
		if drive.driving:
			print("    drive ", drive.hud_text(), " up=", drive.driving.global_basis.y.snapped(Vector3.ONE * 0.01))
			var c := get_viewport().get_camera_3d()
			print("    camera ", c.get_parent().name if c.get_parent() else "?", "/", c.name, " at ", c.global_position.snapped(Vector3.ONE * 0.1),
				" car at ", drive.driving.global_position.snapped(Vector3.ONE * 0.1))
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
	var armed_vehicle: bool = drive.driving != null and vweapons.armed(drive.driving)
	hud.update_hud(now, player.heading, armed_vehicle or player.aiming or (not drive.driving and (sel == "grapple" or sel == "batarang" or weapons.is_weapon(sel)) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED))
	hud.set_prompt("interact" if prompt and not hud.hints_enabled else "", prompt[1] if prompt else "")
	if perf.visible:
		perf.text = "%d fps · %.1f ms · %d draws · %dk prims · %s · %s
(readout only, not a benchmark)" % [
			Engine.get_frames_per_second(), 1000.0 / maxf(1, Engine.get_frames_per_second()),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			stage.quality.to_upper(), "Red Citadel (%d rooms)" % citadel.visible_rooms if underground else "Downtown"]
	# distance-based footsteps while grounded and moving
	var moved := player.global_position.distance_to(_last_pos)
	_last_pos = player.global_position
	if player.mode == "ground" and player.is_on_floor() and moved < 1:
		_step_dist += moved
		if _step_dist > (1.6 if player.speed > 6 else 1.25 if player.speed > 3 else 0.8):
			_step_dist = 0
			audio.play(_step_sound(), 1.0 if player.speed > 3 else 0.6)
	# suit servos: starting off or pulling up hard
	var spd_now: float = player.speed
	if player.mode == "ground" and absf(spd_now - _last_speed) > 3.5 * maxf(dt, 0.001) * 10.0 and now - _servo_at > 700:
		_servo_at = now
		audio.play("armor.servo", 0.5)
	_last_speed = spd_now
	_autosave += dt
	if started and _autosave > 30:
		_autosave = 0
		saves.write(_snapshot())
	if args.has("burst") and frame % 12 == 0: # effect-sprite test: keep bursts in front of the Knight
		effects.burst(args["burst"], player.global_position + Vector3(sin(player.heading), 0, cos(player.heading)) * 1.5 + Vector3.UP, 6, 0.8, 1.2, 1.5)
	_finish_check()


func _finish_check() -> void:
	if args.has("frames") and frame >= int(args["frames"]):
		_finish()


## What the Knight can do right now, for the HUD hint bar (keeps the controls discoverable).
func _control_hints() -> Array:
	if drive.driving:
		var v: Vehicle = drive.driving
		var out := [["moveForward", "Throttle"], ["moveBack", "Brake"], ["vehicleMode", "Mode: " + v.mode.capitalize()],
			["summonMenu", "Camera"], ["interact", "Exit"]]
		if v.kind == "jet":
			out = [["moveForward", "Throttle"], ["=Mouse", "Pitch / turn"], ["moveLeft", "Roll"], ["vehicleMode", "Mode: " + v.mode.capitalize()],
				["summonMenu", "Camera"], ["interact", "Exit"]]
			if v.mode == "vtol":
				out[1] = ["jump", "Up"]
				out.insert(2, ["crouch", "Down"])
		elif v.id == "crx1_interceptor":
			out.insert(3, ["eject", "Launch bike"])
		if vweapons.armed(v):
			var lo: Dictionary = vweapons.loadout(v)
			out.insert(1, ["primaryAction", "Fire"])
			if lo.has("secondary"):
				out.insert(2, ["secondaryAction", "Missiles"])
		return out
	match player.mode:
		"glide":
			return [["moveForward", "Dive"], ["moveBack", "Pull up"], ["moveLeft", "Turn"], ["grapple", "Grapple"] if not player.grapple_target.is_empty() else ["jump", "Release: drop"]]
		"grapple":
			return [["jump", "Boost over the edge"], ["crouch", "Let go"]]
		"ledge":
			return [["jump", "Climb up"], ["moveLeft", "Shimmy"], ["crouch", "Drop"]]
		"air":
			return [["jump", "Hold: glide"], ["grapple", "Grapple"]] if not player.grapple_target.is_empty() else [["jump", "Hold: glide"]]
	if player.melee_engaged:
		var out := [["primaryAction", "Strike"], ["secondaryAction", "Heavy"], ["crouch", "Dodge"], ["interact", "Hold: block"]]
		if melee.counter_target():
			out.push_front(["interact", "COUNTER!"])
		return out
	var sel := inventory.selected_item()
	var out := []
	if weapons.is_weapon(sel) and weapons.defs[sel]["kind"] != "melee":
		out = [["secondaryAction", "Aim / lock on"], ["primaryAction", "Fire"], ["reload", "Reload"]]
	elif sel != "":
		out = [["primaryAction", "Use " + String(inventory.def(sel)["displayName"])]]
	if not player.grapple_target.is_empty():
		out.append(["grapple", "Grapple"])
	out.append(["summonMenu", "Call vehicle"])
	if out.size() < 5:
		out.append(["talkToRed", "Hold: talk to R.E.D."])
	if prompt:
		out.push_front([prompt[0], prompt[1]])
	return out


func _on_foot(now: int) -> void:
	player.grapple_target = player.find_grapple_target() if not underground else {}
	_gameplay_input(now)
	if Input.is_action_just_pressed("jump") and player.mode == "ground":
		audio.play("armor.jump")
	player.handle_input()
	player.cam_yaw = cam.yaw
	player.glide_held = Input.is_action_pressed("jump")
	cam.aiming = player.aiming
	_interact()


## Hotbar: 1-8 select (never use), Q/R or wheel cycle, primary action uses; vehicle call.
func _gameplay_input(now: int) -> void:
	for i in Inventory.KEYED:
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
	if Input.is_action_just_pressed("reload"):
		weapons.reload(now)
	var sel_id := inventory.selected_item()
	var ranged: bool = weapons.is_weapon(sel_id) and weapons.defs[sel_id]["kind"] != "melee"
	var fists := melee.engaged(ranged) and not weapons.is_weapon(sel_id)
	player.melee_engaged = fists
	cam.combat = fists
	cam.shoulder = ranged or sel_id in ["batarang", "grapple"]
	weapons.update_aim(get_process_delta_time(), Input.is_action_just_pressed("secondaryAction"), Input.is_action_pressed("secondaryAction"))
	if fists:
		if Input.is_action_just_pressed("primaryAction"):
			melee.strike(false)
		elif Input.is_action_just_pressed("secondaryAction"):
			melee.strike(true)
		elif Input.is_action_just_pressed("crouch"):
			var m: Vector2 = CKInput.move()
			var f := Vector3(-sin(cam.yaw), 0, -cos(cam.yaw))
			melee.dodge(f * m.y + Vector3(-f.z, 0, f.x) * m.x)
	elif Input.is_action_just_pressed("primaryAction") and not weapons.is_weapon(inventory.selected_item()):
		if args.has("log"):
			print("[ck] use ", inventory.selected_item())
		equipment.use_selected(now)
	if Input.is_action_just_pressed("summonMenu"):
		drive.summon(quick_vehicle, underground)


## Takedown: an upright enemy within 2.4 m in front of the Knight (E).
func _takedown_target() -> Enemy:
	var best: Enemy = null
	var best_d := 2.4
	for e in director.enemies:
		if not is_instance_valid(e) or e.is_down():
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


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
	# hold E in a fight to block (a tap still counters / takes down)
	if player.melee_engaged and not drive.driving and Input.is_action_pressed("interact") and not melee.counter_target():
		_block_hold += get_process_delta_time()
	else:
		_block_hold = 0.0
	melee.set_block(_block_hold > 0.15)
	var p := player.global_position
	var prop := _nearest_prop() if not underground else null
	var near_portal := not underground and p.distance_to(portal) < 9
	var near_exit := underground and p.distance_to(citadel.anchor("Anchor_Exit")) < 4
	var car := drive.nearby()
	prompt = []
	if melee.counter_target():
		prompt = ["interact", "Counter"]
		if Input.is_action_just_pressed("interact"):
			melee.counter()
		return
	var foe := _takedown_target()
	if foe:
		prompt = ["interact", "Takedown"]
		if Input.is_action_just_pressed("interact"):
			player.heading = atan2(foe.global_position.x - p.x, foe.global_position.z - p.z)
			player.act("CK_Interact", 0.5)
			foe.hit(foe.health + 1.0, foe.global_position, (foe.global_position - p).normalized())
			effects.burst("sparks", foe.global_position + Vector3(0, 1.2, 0), 8, 2.0, 0.5, 0.3)
			audio.play("weapon.impact")
		return
	if car:
		prompt = ["interact", "Enter the " + drive.label(car)]
		if Input.is_action_just_pressed("interact"):
			drive.enter(car)
		return
	if underground:
		var station := _citadel_station(p)
		if not station.is_empty():
			prompt = ["interact", station[1]]
			if Input.is_action_just_pressed("interact"):
				_use_station(station[0])
			return
	if prop or near_portal or near_exit:
		prompt = ["interact", "Shove" if prop else "Enter the Red Citadel" if near_portal else "Elevator to New Gotham"]
	if not Input.is_action_just_pressed("interact"):
		return
	if prop:
		var dir := (prop.global_position - p)
		dir.y = 0.4
		prop.apply_central_impulse(dir.normalized() * 5 * prop.mass)
		audio.play("armor.step")
	elif near_portal:
		if not inventory.has("citadel_keycard"):
			notify("Access denied: Red Citadel keycard required", "keycard", "warn")
			return
		player.teleport(citadel.anchor("Anchor_Arrival"))
		player.heading = PI # face north (-Z), toward the hub tunnel
		cam.yaw = 0.0
		cam.snap()
		audio.play("armor.activate")
		notify("Welcome to the Red Citadel", "citadel")
	elif near_exit:
		player.teleport(portal + Vector3(0, 0.5, 8))
		cam.snap()
		audio.play("armor.activate")
		notify("Returned to New Gotham", "home")


## Red Citadel stations: [id, prompt] for what the Knight is standing at, or [].
func _citadel_station(p: Vector3) -> Array:
	if p.distance_to(citadel.anchor("Anchor_ArmorDisplay")) < 4.0:
		return ["suit", "Inspect the CR-X9 suit (repair, recharge, restock)"]
	for bay in [["crx1_interceptor", "Anchor_CRX1"], ["crb1_batcycle", "Anchor_CRB1"], ["cra1_specter", "Anchor_CRA1"]]:
		if p.distance_to(citadel.anchor(bay[1])) < 6.0:
			return ["launch:" + bay[0], "Launch the %s into New Gotham" % CKData.data("vehicles")[bay[0]]["label"]]
	var room := citadel.room_at(p)
	match room:
		"Command":
			return ["computer", "Citadel computer (missions, crimes, map)"] if p.distance_to(citadel.room_center("Command")) < 7.0 else []
		"Armory":
			return ["armory", "Armory: equipment loadout"]
		"MedicalBay":
			return ["medical", "Medical bay: full repair"]
		"Training":
			return ["training", "Start combat training"] if director.enemies.filter(func(e): return is_instance_valid(e) and not e.is_down() and citadel.contains(e.global_position)).is_empty() else []
	return []


func _use_station(id: String) -> void:
	player.act("CK_Interact", 0.5)
	audio.play("armor.activate")
	match id:
		"suit", "medical":
			vitals.health = Vitals.MAX
			vitals.armor = Vitals.MAX
			vitals.energy = Vitals.MAX
			if id == "suit":
				for w in weapons.defs:
					weapons._ammo[w] = int(weapons.defs[w]["mag"])
				inventory.restock_all()
				hud.render_hotbar()
			red.speak("Suit at one hundred percent, magazines full, gadgets restocked. You look almost competent." if id == "suit"
				else "Full repair. Try to keep it that way for more than five minutes.")
		"computer":
			var c := red.run("waypoint_crime")
			red.speak("Citadel uplink. " + c + (" Current objective: %s." % director.objective if director.objective != "" else ""))
			menus.show_screen("map")
		"armory":
			menus.show_screen("loadout")
		"training":
			var at := citadel.room_center("Training")
			for e in director.squad(["npc_criminal_thug", "npc_mercenary", "npc_enforcer"], at + Vector3(0, 0.2, 0), 4, "NPC_Alert"):
				e.alert(player.global_position)
				e.state = "chase"
			red.speak("Training drones online. Four sparring partners. Try the counter, the dodge and the block. Hold E.")
		_:
			if id.begins_with("launch:"):
				_launch_from_citadel(id.substr(7))


## A parked vehicle in the Citadel: the lift raises it to the street exit and the Knight drives out.
## (The Citadel is a separate underground level; there is no road tunnel geometry yet, so this is a lift ride.)
func _launch_from_citadel(id: String) -> void:
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fade)
	var tw := fade.create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.4)
	await tw.finished
	player.teleport(portal + Vector3(0, 0.5, 14))

	drive.summon(id, false)
	var v: Vehicle = drive.vehicles[id]
	v.route = []
	v.land_at = null
	var spot := portal + Vector3(0, 0, 18)
	spot.y = drive._ground(spot) + (0.4 if v.kind != "jet" else 0.1)
	v.place(spot, 0.0)
	drive.enter(v, true)
	audio.play("vehicle.mode")
	red.speak("Lift's up. %s is all yours. Mind the pedestrians." % drive.label(v))
	var tw2 := fade.create_tween()
	tw2.tween_property(fade, "color:a", 0.0, 0.6)
	tw2.tween_callback(fade.queue_free)


func _finish() -> void:
	set_process(false)
	if args.has("shot"):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["shot"])
		print("[ck] screenshot ", args["shot"])
	get_tree().quit()
