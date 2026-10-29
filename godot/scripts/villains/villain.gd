class_name Villain
extends Node3D
## One of the ten persistent villains in the world: a tinted stand-in NPC body (no bespoke villain models
## yet), a name plate, a coloured key light, a positional voice and an emotion-driven body (clip + VillainPose).
## Emotions come from the model's validated tag; each maps to an allowed clip, speed and posture below.

## emotion -> [clip, speed, chest lean, head tilt, chin, voice gain dB, pause before speaking s]
const EMOTE := {
	"calm": ["NPC_Talk", 0.85, 0.0, 0.0, 0.0, 0.0, 0.0],
	"angry": ["NPC_Alert", 1.15, 0.14, 0.0, -0.1, 3.5, 0.0],
	"amused": ["NPC_Talk", 1.15, -0.07, 0.06, 0.12, 0.0, 0.0],
	"suspicious": ["NPC_Idle", 0.55, 0.04, 0.0, -0.06, -1.0, 0.3],
	"confused": ["NPC_Idle", 0.9, 0.0, 0.26, 0.04, 0.0, 0.7],
	"contemptuous": ["NPC_Talk", 0.8, -0.06, 0.08, 0.17, 0.0, 0.0],
	"afraid": ["NPC_Cower", 1.0, 0.12, 0.0, -0.05, -2.0, 0.2],
	"intrigued": ["NPC_Talk", 0.95, 0.06, 0.13, 0.03, 0.0, 0.2],
}

var def: Dictionary
var location := ""
var activity := ""
var emotion := "calm"
var speaking := false
var anim: AnimationPlayer
var pose: VillainPose
var voice: AudioStreamPlayer3D
var _plate: Label3D
var _light: OmniLight3D
var _turn_to = null
var _pending_wav: AudioStreamWAV
var _pause := 0.0
var _anim_acc := 0.0


static func create(d: Dictionary) -> Villain:
	var v := Villain.new()
	v.def = d
	v.name = "Villain_" + str(d["id"])
	return v


func _ready() -> void:
	var model: Node3D = load(CKData.model_path(def["model"])).instantiate()
	model.scale = Vector3.ONE * float(def.get("scale", 1.0))
	add_child(model)
	var tint := Color(str(def.get("tint", "#ffffff")))
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat is StandardMaterial3D:
				var dup: StandardMaterial3D = mat.duplicate()
				dup.albedo_color = dup.albedo_color * tint.lightened(0.15)
				if def["id"] == "iron_sovereign":
					dup.metallic = 0.85
					dup.roughness = 0.35
				mi.set_surface_override_material(s, dup)
		mi.extra_cull_margin = 0.6
	anim = model.find_child("AnimationPlayer", true, false)
	if anim:
		for c in anim.get_animation_list():
			anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim.play("NPC_Idle")
	var sk: Skeleton3D = null
	for n in model.find_children("*", "Skeleton3D", true, false):
		sk = n
	if sk:
		pose = VillainPose.new()
		sk.add_child(pose)
	# name plate (shown near), accent key light, solid body, voice
	_plate = Label3D.new()
	_plate.text = "%s\n%s" % [def["name"], ""]
	_plate.font_size = 40
	_plate.outline_size = 10
	_plate.modulate = Color(str(def.get("accent", "#ffffff")))
	_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_plate.pixel_size = 0.004
	_plate.position = Vector3(0, 2.35 * float(def.get("scale", 1.0)), 0)
	_plate.visibility_range_end = 26.0
	add_child(_plate)
	_light = OmniLight3D.new()
	_light.light_color = Color(str(def.get("accent", "#ffffff")))
	_light.light_energy = 2.4
	_light.omni_range = 4.5
	_light.position = Vector3(0.6, 2.4, 0.9)
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 40.0
	_light.distance_fade_length = 10.0
	add_child(_light)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	add_child(body)
	voice = AudioStreamPlayer3D.new()
	voice.position = Vector3(0, 1.6, 0)
	voice.unit_size = 6.0
	voice.max_distance = 45.0
	voice.bus = VillainVoice.bus_for(def)
	voice.pitch_scale = VillainVoice.rate_for(def)
	voice.finished.connect(func(): speaking = false)
	add_child(voice)


## Stand at a world point facing `heading` (0 = +Z).
func place(at: Vector3, heading: float, loc: String, what: String) -> void:
	global_position = at
	rotation.y = heading
	location = loc
	activity = what
	reset_physics_interpolation()


func set_emotion(e: String) -> void:
	emotion = e if EMOTE.has(e) else "calm"
	var row: Array = EMOTE[emotion]
	if pose:
		pose.lean = row[2]
		pose.tilt = row[3]
		pose.chin = row[4]
		pose.laugh = 1.0 if emotion == "amused" else 0.0


## Speak a synthesized line (after the emotion's pause: confusion hesitates, suspicion weighs its words).
func speak(wav: AudioStreamWAV) -> void:
	_pending_wav = wav
	_pause = float(EMOTE[emotion][6])


func is_busy_talking() -> bool:
	return speaking or _pending_wav != null


func shut_up() -> void:
	_pending_wav = null
	voice.stop()
	speaking = false


func face(point) -> void:
	_turn_to = point


## Per frame while near: clip by emotion and speaking, head tracking, body turn, plate.
func update(dt: float, player_head: Vector3, near: bool, in_talk := false) -> void:
	if _pending_wav:
		_pause -= dt
		if _pause <= 0.0:
			voice.stream = _pending_wav
			voice.volume_db = float(EMOTE[emotion][5])
			voice.play()
			speaking = true
			_pending_wav = null
	if _turn_to != null:
		var to: Vector3 = _turn_to - global_position
		if Vector2(to.x, to.z).length() > 0.2:
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, dt * 4.0))
	if pose:
		pose.look_at = player_head if near and global_position.distance_to(player_head) < 14.0 else null
		pose.talk = lerpf(pose.talk, 1.0 if speaking else 0.0, minf(1.0, dt * 6.0))
	if anim:
		var row: Array = EMOTE[emotion]
		var clip: String = row[0] if speaking or emotion in ["angry", "afraid", "confused", "suspicious"] else "NPC_Idle"
		if not anim.has_animation(clip):
			clip = "NPC_Idle"
		if anim.current_animation != clip:
			anim.play(clip, 0.3)
		anim.speed_scale = row[1] if clip == row[0] else 0.8
		# throttle far animation like NpcCrowd
		_anim_acc += dt
		var d := global_position.distance_to(player_head)
		if d < 60.0 and (d < 18.0 or _anim_acc > 0.1):
			anim.advance(_anim_acc)
			_anim_acc = 0.0
	_plate.text = "%s\n%s" % [def["name"], "[E] Talk" if not in_talk and global_position.distance_to(player_head) < 4.5 else ""]
