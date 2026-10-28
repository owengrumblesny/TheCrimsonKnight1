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
	var spawn: Array = CKData.json("world")["spawn"]
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.teleport(_vec(args.get("at", ""), Vector3(spawn[0], spawn[1] - 2, spawn[2])))
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
	district.update_lights(player.global_position, now, dt)
	stage.follow(player.global_position)
	player.hero.update_lod(cam.camera.global_position.distance_to(player.global_position),
		stage.preset["lod_scale"], stage.preset["hero_min_lod"])
	if args.has("log") and frame % 30 == 0:
		print("[ck] f%d pos=%s %s lod=%d fps=%d" % [frame, player.global_position.snapped(Vector3.ONE * 0.01),
			player.status, player.hero.lod_level, Engine.get_frames_per_second()])
	if args.has("frames") and frame >= int(args["frames"]):
		_finish()


func _finish() -> void:
	set_process(false)
	if args.has("shot"):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["shot"])
		print("[ck] screenshot ", args["shot"])
	get_tree().quit()
