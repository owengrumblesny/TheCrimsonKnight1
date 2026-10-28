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
var spawn := Vector3.ZERO
## interact prompt for the HUD: [key label, text] or []
var prompt: Array = []
var _step_dist := 0.0
var _last_pos := Vector3.ZERO
var args := {}
var frame := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
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
	var q: String = args.get("quality", Quality.detect_default())
	stage.apply_quality(q)
	district.set_light_pool(stage.preset["dynamic_lights"], stage.preset["light_shadows"])
	citadel.set_light_pool(maxi(4, stage.preset["dynamic_lights"]))
	if args.has("hold"):
		for act in String(args["hold"]).split(","):
			Input.action_press(act)
	if args.has("slot"):
		select_slot.call_deferred(int(args["slot"]) - 1)
	if not args.has("frames"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## On-screen notification (HUD toast in M4; logged for scripted runs).
func notify(text: String, icon := "", kind := "info") -> void:
	print("[ck] notify(%s) %s" % [kind, text])


## Select a hotbar slot: equip animation and the gear model on its socket. Never uses the item.
func select_slot(i: int) -> void:
	var err := inventory.select_slot(i)
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


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _process(dt: float) -> void:
	frame += 1
	var now := Time.get_ticks_msec()
	# --press=jump@60,crouch@200: tap an action on a frame (scripted tests)
	for tap in String(args.get("press", "")).split(",", false):
		var at := tap.split("@")
		if at.size() == 2 and int(at[1]) == frame:
			Input.action_press(at[0])
		elif at.size() == 2 and int(at[1]) + 1 == frame:
			Input.action_release(at[0])
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
		var mv: Vector2 = CKInput.move()
		if mv != Vector2.ZERO:
			print("    move=", mv, " joypads=", Input.get_connected_joypads().map(func(j): return Input.get_joy_name(j)),
				" fwd=", Input.get_action_strength("moveForward"), " back=", Input.get_action_strength("moveBack"))
		for i in player.get_slide_collision_count():
			var c := player.get_slide_collision(i)
			print("    hit ", c.get_collider().name if c.get_collider() else "?", " n=", c.get_normal().snapped(Vector3.ONE * 0.01))
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
		prompt = [CKInput.label("interact"), "Shove" if prop else "Enter the Red Citadel" if near_portal else "Elevator to New Gotham"]
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
