extends Node3D
## Game root (port of main.ts). Builds the stage, the New Gotham district, the player and camera.
##
## Test/debug command line (after `--`):
##   --quality=low|medium|high|ultra   force a preset for this run
##   --at=x,y,z --yaw=r                 spawn the player (feet) and camera yaw
##   --hold=moveForward,sprint          hold actions for the scripted run
##   --frames=N --shot=path.png         run N frames, save a screenshot, quit
##   --log                              print player status every 30 frames

var stage: Stage
var district: District
var citadel: Citadel
var underground := false
var portal := Vector3.ZERO
var player: Player
var cam: FollowCamera
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
	var spawn: Array = CKData.json("world")["spawn"]
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.teleport(_vec(args.get("at", ""), Vector3(spawn[0], spawn[1] - 2, spawn[2])))
	if args.get("at", "") == "citadel":
		player.teleport(citadel.anchor("Anchor_Arrival"))
	cam = FollowCamera.new()
	cam.target = player
	add_child(cam)
	if args.has("yaw"):
		cam.yaw = float(args["yaw"])
	stage.camera = cam.camera
	cam.camera.make_current()
	var q: String = args.get("quality", Quality.detect_default())
	stage.apply_quality(q)
	district.set_light_pool(stage.preset["dynamic_lights"], stage.preset["light_shadows"])
	citadel.set_light_pool(maxi(4, stage.preset["dynamic_lights"]))
	if args.has("hold"):
		for act in String(args["hold"]).split(","):
			Input.action_press(act)
	if not args.has("frames"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	player.handle_input()
	player.cam_yaw = cam.yaw
	player.glide_held = Input.is_action_pressed("jump")
	cam.aiming = Input.is_action_pressed("grapple")
	_interact()
	underground = citadel.update(player.global_position, dt)
	stage.set_underground(underground)
	district.visible = not underground # sector streaming: the city does not render underground
	if not underground:
		district.update_lights(player.global_position, now, dt)
	stage.follow(player.global_position)
	player.hero.update_lod(cam.camera.global_position.distance_to(player.global_position),
		stage.preset["lod_scale"], stage.preset["hero_min_lod"])
	if args.has("log") and frame % 30 == 0:
		print("[ck] f%d pos=%s %s lod=%d fps=%d%s" % [frame, player.global_position.snapped(Vector3.ONE * 0.01),
			player.status, player.hero.lod_level, Engine.get_frames_per_second(),
			" citadel rooms=%d" % citadel.visible_rooms if underground else ""])
		for i in player.get_slide_collision_count():
			var c := player.get_slide_collision(i)
			print("    hit ", c.get_collider().name if c.get_collider() else "?", " n=", c.get_normal().snapped(Vector3.ONE * 0.01))
	if args.has("frames") and frame >= int(args["frames"]):
		_finish()


## Real interactables: Citadel entrance and exit elevator (shoving props comes with M3).
func _interact() -> void:
	var p := player.global_position
	var near_portal := not underground and p.distance_to(portal) < 9
	var near_exit := underground and p.distance_to(citadel.anchor("Anchor_Exit")) < 4
	if not Input.is_action_just_pressed("interact"):
		return
	if near_portal:
		player.teleport(citadel.anchor("Anchor_Arrival"))
		player.heading = PI # face north (-Z), toward the hub tunnel
		cam.yaw = 0.0
		cam.snap()
	elif near_exit:
		player.teleport(portal + Vector3(0, 0.5, 8))
		cam.snap()


func _finish() -> void:
	set_process(false)
	if args.has("shot"):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["shot"])
		print("[ck] screenshot ", args["shot"])
	get_tree().quit()
