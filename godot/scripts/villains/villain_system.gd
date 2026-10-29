class_name VillainSystem
extends Node
## Persistent villains you can talk to (see docs/VILLAINS.md). Owns the 20 landmarks, the ten villains,
## their schedules and the conversation loop:
##   walk up -> E -> (greeting) -> hold V and speak / T to type -> release -> whisper.cpp transcript ->
##   shared local LLM with personality + scene + compact memory -> "(emotion) words [action]" ->
##   action validated (VillainActions) and applied -> Piper speaks it from the villain (3D) while his body
##   plays the emotion -> memory saved. Esc leaves; the model then writes a one-line summary for next time.
## Everything is local and asynchronous (HTTP to local servers, Piper as a separate process); the game loop
## never waits. Without the engines it degrades to subtitles and scripted lines.

signal line(who: String, text: String)

const TALK_RANGE := 3.2
const RELOCATE_AWAY := 120.0 # schedules only move a villain the Knight can't see

var game: Node # main.gd
var defs := {} # id -> def
var villains := {} # id -> Villain
var landmarks: Landmarks
var memory: VillainMemory
var brain: VillainBrain
var voice: VillainVoice
var talking := false
var partner: Villain
var state := "idle" # idle | greeting | listening | hearing | thinking | speaking
var last_timing := {}

var _froze_player := false
var _sched_t := 0.0
var _ui: CanvasLayer
var _panel: PanelContainer
var _title: Label
var _log: RichTextLabel
var _status: Label
var _mic: Label
var _field: LineEdit
var _hints: Label
var _lines: Array = [] # [who, text]
var _script: Array = [] # test hook queue
var _rng := RandomNumberGenerator.new()
var _t0 := 0
var _said := ""
var _voice_wait := 0.0 # seconds left to wait for Piper's WAV of the current line
var _warmed := ""
var _test_started := false
var _last_fallback := -1
var _retried := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for d in CKData.data("villains")["villains"]:
		defs[d["id"]] = d
	memory = VillainMemory.new(str(game.args.get("villainmem", "")))
	memory.load_all()
	brain = VillainBrain.new()
	add_child(brain)
	brain.replied.connect(_on_reply)
	brain.summarized.connect(_on_summary)
	voice = VillainVoice.new()
	add_child(voice)
	voice.voiced.connect(_on_voiced)
	voice.heard.connect(_on_heard)
	landmarks = Landmarks.new()
	game.add_child(landmarks)
	landmarks.build(game.district)
	for id in defs:
		var v := Villain.create(defs[id])
		landmarks.add_child(v)
		villains[id] = v
		_place(v, true)
	_build_ui()
	if game.args.has("log"):
		line.connect(func(who, t): print("[villain] f%d %s: %s" % [game.frame, who, t]))
	if game.args.has("villain"):
		_test_setup.call_deferred(str(game.args["villain"]))
	for item in str(game.args.get("villainscript", "")).split("|", false):
		_script.append(item)


# ---------------- placement and schedules ----------------
func _place(v: Villain, force := false) -> void:
	var s := VillainActions.scheduled(v.def, game.stage.hour)
	if not force and s[0] == v.location:
		v.activity = s[1]
		return
	var site: Dictionary = landmarks.sites.get(s[0], landmarks.sites[v.def["home"]])
	# several villains can share a site: offset each by its index
	var k := defs.keys().find(v.def["id"])
	var off := Vector3(0, 0, 0) if _first_at(s[0]) == v.def["id"] else Vector3(cos(k * 1.7), 0, sin(k * 1.7)) * 3.0
	v.place(site["spot"] + off, float(site.get("spot_heading", site["heading"])), s[0], s[1])
	v.set_emotion("calm")


func _first_at(loc: String) -> String:
	for id in defs:
		if VillainActions.scheduled(defs[id], game.stage.hour)[0] == loc:
			return id
	return ""


func _schedules() -> void:
	for id in villains:
		var v: Villain = villains[id]
		if v == partner:
			continue
		var want: String = VillainActions.scheduled(v.def, game.stage.hour)[0]
		if want != v.location and v.global_position.distance_to(game.player.global_position) > RELOCATE_AWAY:
			_place(v, true)
			if game.args.has("log"):
				print("[villain] %s moves to %s (%s)" % [v.def["name"], landmarks.loc_name(want), v.activity])


# ---------------- per frame ----------------
func _process(dt: float) -> void:
	if game == null or not game.started or game.player == null:
		return
	var paused: bool = get_tree().paused
	var head: Vector3 = game.player.global_position + Vector3(0, 1.7, 0)
	if not paused:
		if not game.underground:
			landmarks.update(game.player.global_position, dt)
		for id in villains:
			var v: Villain = villains[id]
			var near := v.global_position.distance_to(head) < 16.0
			v.update(dt, head, near, talking)
		_sched_t -= dt
		if _sched_t <= 0.0:
			_sched_t = 2.0
			_schedules()
			# warm the model's cache for the villain the Knight is walking up to
			var v := nearest_villain(25.0)
			if v and not talking and game.red.brain_ready and _warmed != v.def["id"]:
				_warmed = v.def["id"]
				brain.warm(v.def)
	# Piper starts once R.E.D. has found the ai/ folder and voice is on
	if not voice.tts_ready and game.red.ai_dir != "" and game.settings.get("redVoice", true) and not game.args.has("novillainvoice"):
		voice.start(game.red.ai_dir)
	if talking:
		_converse(dt)
	_update_ui()
	# --villaintalk=<frame>: start talking at that frame, once the local model is up (or 40 s later without it)
	if game.args.has("villaintalk") and not _test_started and game.frame >= int(game.args["villaintalk"]) 			and (game.red.brain_ready or game.frame > int(game.args["villaintalk"]) + 2400):
		_test_started = true
		var v := nearest_villain(8.0)
		if v:
			begin(v)
	if talking and not _script.is_empty() and state == "idle" and not partner.is_busy_talking():
		_run_script(_script.pop_front())


## The villain the Knight could talk to right now (on foot, in range), or null.
func nearest_villain(r := TALK_RANGE) -> Villain:
	var best: Villain = null
	var bd := r
	for id in villains:
		var d: float = villains[id].global_position.distance_to(game.player.global_position)
		if d < bd:
			bd = d
			best = villains[id]
	return best


## main.gd's E prompt: ["interact", text] when a villain is in reach.
func interact_prompt() -> Array:
	if talking or game.drive.driving or game.player.mode != "ground":
		return []
	var v := nearest_villain()
	return ["interact", "Talk to " + str(v.def["name"])] if v else []


# ---------------- the conversation ----------------
func begin(v: Villain) -> void:
	if talking:
		return
	talking = true
	partner = v
	_lines.clear()
	var p: Player = game.player
	p.hero.play("CK_Idle", 0.25)
	p.vel = Vector3.ZERO
	p.velocity = Vector3.ZERO
	p.heading = atan2(v.global_position.x - p.global_position.x, v.global_position.z - p.global_position.z)
	p.hero.rotation.y = p.heading
	if not p.frozen:
		p.frozen = true
		_froze_player = true
	v.face(p.global_position)
	game.cam.lock_point = (p.global_position + v.global_position) * 0.5 + Vector3(0, 1.6, 0)
	var r := memory.rec(v.def)
	VillainMemory.begin(r)
	_panel.visible = true
	_say_line("sys", "%s · %s" % [landmarks.loc_name(v.location), VillainMemory.attitude(r)])
	_ask("") # he speaks first: recognition, memory, mood


func end() -> void:
	if not talking:
		return
	var v := partner
	talking = false
	state = "idle"
	brain.cancel()
	if voice.listening:
		voice.stop_listening()
	_close_field()
	v.shut_up()
	v.face(null)
	v.set_emotion("calm")
	if _froze_player:
		game.player.frozen = false
		_froze_player = false
	game.cam.lock_point = null
	var r := memory.rec(v.def)
	memory.save()
	if game.red.brain_ready:
		brain.summarize(v.def, r)
	partner = null
	_panel.visible = false


func _converse(dt: float) -> void:
	if partner == null:
		return
	if partner.global_position.distance_to(game.player.global_position) > 8.0:
		end()
		return
	_voice_wait -= dt
	if state == "speaking" and not partner.is_busy_talking() and _voice_wait <= 0.0:
		state = "idle"
	# push-to-talk: V held = microphone open, release = transcribe
	if mic_allowed() and Input.is_action_just_pressed("villainTalk") and not _field_open() and state in ["idle", "speaking"]:
		partner.shut_up()
		brain.cancel()
		voice.start_listening()
		state = "listening"
	elif voice.listening and not Input.is_action_pressed("villainTalk"):
		voice.stop_listening(_vocab())
		state = "hearing"
	elif not mic_allowed() and Input.is_action_just_pressed("villainTalk"):
		_say_line("sys", "Microphone is off (Settings: R.E.D. voice commands). Press T to type.")
	if Input.is_action_just_pressed("villainType") and not _field_open() and not voice.listening:
		_open_field()


func mic_allowed() -> bool:
	return game.settings.get("redListen", true) and not game.args.has("nomic") and game.red.voice.stt_ready


func _vocab() -> String:
	var names: Array = []
	for id in defs:
		names.append(defs[id]["name"])
	return ", ".join(names) + ", New Gotham, Blackthorn, Grimstone, Vesper, Ironhaven, Northbridge, R.E.D."


## Words from the Knight (spoken or typed).
func submit(text: String) -> void:
	text = text.strip_edges()
	if not talking or text == "":
		return
	_say_line("you", text)
	var r := memory.rec(partner.def)
	var tags := VillainMemory.note_player(r, text)
	if game.args.has("log") and not tags.is_empty():
		print("[villain] noted ", tags, " -> ", VillainMemory.attitude(r))
	partner.shut_up()
	_ask(text)


func _ask(said: String) -> void:
	var r := memory.rec(partner.def)
	_said = said
	state = "thinking" if said != "" else "greeting"
	_t0 = Time.get_ticks_msec()
	partner.set_emotion("suspicious" if float(r["hostility"]) > 0.5 else "calm") # listening posture
	if game.red.brain_ready:
		brain.ask(partner.def, r, scene(partner), said)
	else:
		_on_reply.call_deferred(partner.def["id"], {})


## The structured situation the model gets with every line.
func scene(v: Villain) -> String:
	var r := memory.rec(v.def)
	var loc: Dictionary = landmarks.sites[v.location]["def"]
	var h: float = game.stage.hour
	var clock := "%d:%02d %s" % [(int(h) + 11) % 12 + 1, int(fmod(h, 1.0) * 60.0), "AM" if h < 12.0 else "PM"]
	var parts := ["Location: %s, %s" % [loc["name"], loc["desc"]], "Time: %s, %s" % [clock, str(game.stage.weather_name).to_lower()],
		"You are: " + v.activity, "Your attitude to him: " + VillainMemory.attitude(r), "Your objective: " + str(v.def["objective"]),
		"His reputation: " + reputation()]
	return ". ".join(parts) + ".
" + VillainMemory.describe(r)


func reputation() -> String:
	var d: Director = game.director
	var feared := "feared by organised crime" if d.credits >= 400 or d.evidence >= 3 else "a rising nuisance to the gangs"
	return "%s; police heat %d star%s" % [feared, d.stars(), "" if d.stars() == 1 else "s"]


func _on_reply(id: String, reply: Dictionary) -> void:
	if not talking or partner == null or partner.def["id"] != id:
		return
	var def: Dictionary = partner.def
	var r := memory.rec(def)
	var said := _said
	if reply.is_empty():
		reply = _fallback(def, said)
	elif not _retried and _repeats(r, str(reply["dialogue"])):
		_retried = true
		if game.args.has("log"):
			print("[villain] f%d repeated line, asking again: %s" % [game.frame, reply["dialogue"]])
		brain.ask(def, r, scene(partner), said, true)
		return
	_retried = false
	var res := VillainActions.validate(reply, def, r, {"underground": game.underground, "enemies_near": _enemies_near(),
		"locations": landmarks.location_ids(), "hour": game.stage.hour})
	last_timing = {"llm_ms": reply.get("ms", 0), "source": reply.get("source", "fallback"), "action": reply["requested_action"],
		"validated": res["action"], "why": res["reason"]}
	if game.args.has("log"):
		print("[villain] f%d %s (%s, %d ms) emotion=%s action=%s:%s -> %s %s" % [game.frame, def["name"], last_timing["source"], last_timing["llm_ms"],
			reply["emotion"], reply["requested_action"], reply["target"], res["action"], res["reason"]])
	partner.set_emotion(reply["emotion"])
	var words: String = reply["dialogue"]
	_say_line(id, words)
	VillainMemory.note_reply(r, reply["emotion"], res["action"])
	VillainMemory.add_exchange(r, said if said != "" else "(I walk up to you.)", "(%s) %s [%s]" % [reply["emotion"], words, "none"])
	if voice.tts_ready and voice.say(id, int(def["voice"]["speaker"]), words):
		state = "speaking"
		_voice_wait = 10.0 # cleared when the WAV arrives; a stuck Piper can't hold the turn forever
	else:
		state = "idle"
	_apply(res, def, r)
	memory.save()


## Same words as one of his earlier replies in this conversation (ignoring case and punctuation)?
static func _repeats(r: Dictionary, words: String) -> bool:
	var norm := func(t: String) -> String:
		return RegEx.create_from_string("[^a-z ]").sub(t.to_lower(), "", true).strip_edges()
	var w: String = norm.call(words)
	for ex in r.get("recent", []):
		if norm.call(VillainBrain.parse_reply(str(ex[1]))["dialogue"]) == w:
			return true
	return false


func _on_voiced(id: String, wav: AudioStreamWAV) -> void:
	if talking and partner and partner.def["id"] == id:
		partner.speak(wav)
		_voice_wait = 0.0
		last_timing["voice_ms"] = Time.get_ticks_msec() - _t0
		if game.args.has("log"):
			print("[villain] f%d voice ready %.1f s of audio, %d ms after the question" % [game.frame, wav.get_length(), last_timing["voice_ms"]])


func _on_heard(text: String, ms: int) -> void:
	if not talking:
		return
	if game.args.has("log"):
		print("[villain] f%d heard (%d ms): \"%s\"" % [game.frame, ms, text])
	last_timing["stt_ms"] = ms
	if text == "":
		state = "idle"
		_say_line("sys", "(Didn't catch that. Hold V while you speak.)")
		return
	submit(text)


func _on_summary(id: String, text: String) -> void:
	if not defs.has(id):
		return
	var r := memory.rec(defs[id])
	r["summary"] = text
	memory.save()
	if game.args.has("log"):
		print("[villain] memory summary for %s: %s" % [defs[id]["name"], text])


## No model: a scripted line with a keyword-picked emotion (honest fallback, never an action).
func _fallback(def: Dictionary, said: String) -> Dictionary:
	var arr: Array = def.get("fallback", ["..."])
	var t := said.to_lower()
	var emo := "contemptuous"
	if said == "":
		emo = "suspicious"
	elif t.contains("?"):
		emo = "amused"
	elif VillainMemory.THREATS.any(func(w): return t.contains(w)):
		emo = "angry"
	var i := _rng.randi() % arr.size()
	if i == _last_fallback and arr.size() > 1:
		i = (i + 1) % arr.size()
	_last_fallback = i
	return {"dialogue": arr[i], "emotion": emo, "requested_action": "none", "target": "", "source": "fallback", "ms": 0}


func _enemies_near() -> int:
	var n := 0
	for e in game.director.enemies:
		if is_instance_valid(e) and not e.is_down() and e.global_position.distance_to(game.player.global_position) < 30.0:
			n += 1
	return n


## Apply a validated request. Only these effects exist; the model can't reach anything else.
func _apply(res: Dictionary, def: Dictionary, r: Dictionary) -> void:
	var act: String = res["action"]
	var target: String = res["target"]
	var name: String = def["name"]
	match act:
		"reveal_location":
			var site: Dictionary = landmarks.sites[target]
			if res["misleading"]:
				# a misleader's unearned "reveal" points somewhere else entirely (he doesn't know it's a lie)
				var ids := landmarks.location_ids()
				ids.erase(target)
				site = landmarks.sites[ids[_rng.randi() % ids.size()]]
			game.director.waypoint = site["center"]
			VillainMemory.push(r, "revealed", target)
			game.notify("Lead from %s: %s (waypoint set)" % [name, site["def"]["name"]], "notification")
			memory.broadcast("Word is %s talked to Crimson Knight about %s." % [name, landmarks.loc_name(target)])
		"give_clue":
			var fact: String = def["leads"].get(target, "")
			game.director.evidence += 1
			game.notify("Clue (%s): %s" % [name, fact], "notification")
			_say_line("sys", "Clue noted: " + fact)
		"refuse":
			pass
		"offer_deal":
			_say_line("sys", "%s is offering a deal. Say yes to accept." % name)
		"cooperate":
			game.notify("%s will cooperate (for now)" % name, "notification")
		"call_guards":
			var at: Vector3 = partner.global_position + (game.player.global_position - partner.global_position).normalized() * -2.0
			game.director.squad(["npc_criminal_thug", "npc_mercenary"], at, 2, "NPC_Alert")
			game.notify("%s called his guards!" % name, "notification", "warn")
			_end_after_line()
		"flee":
			var v := partner
			_end_after_line()
			get_tree().create_timer(2.5).timeout.connect(func():
				var others: Array = def["schedule"].map(func(s): return s[2]).filter(func(l): return l != v.location)
				if not others.is_empty():
					var loc: String = others[0]
					var site: Dictionary = landmarks.sites[loc]
					v.place(site["spot"], float(site.get("spot_heading", site["heading"])), loc, "lying low after slipping away from Crimson Knight")
					game.notify("%s slipped away" % name, "notification"))
		"end_conversation":
			_end_after_line()


func _end_after_line() -> void:
	var v := partner
	get_tree().create_timer(0.5).timeout.connect(func():
		if talking and partner == v:
			while is_instance_valid(v) and v.is_busy_talking():
				await get_tree().create_timer(0.2).timeout
			if talking and partner == v:
				end())


# ---------------- input ----------------
func _input(e: InputEvent) -> void:
	if not talking:
		return
	if e.is_action_pressed("pause") or (e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE):
		if _field_open():
			_close_field()
		else:
			end()
		get_viewport().set_input_as_handled()


func _open_field() -> void:
	_field.visible = true
	_field.text = ""
	_field.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_field() -> void:
	if _field and _field.visible:
		_field.release_focus()
		_field.visible = false
		if not (game.args.has("frames") or game.args.has("bench")):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _field_open() -> bool:
	return _field != null and _field.visible


# ---------------- UI ----------------
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 6
	add_child(_ui)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", CKUI.box(Color(0.05, 0.04, 0.07, 0.86), CKUI.BORDER, 10, 1, 12))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -380
	_panel.offset_right = 380
	_panel.offset_top = -330
	_panel.offset_bottom = -150
	_panel.visible = false
	_ui.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_panel.add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	_title = CKUI.label("", 17, CKUI.TEXT, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_mic = CKUI.label("", 15, CKUI.BRIGHT, true)
	top.add_child(_mic)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = false
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 92)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 15)
	_log.add_theme_font_size_override("bold_font_size", 15)
	vb.add_child(_log)
	_field = LineEdit.new()
	_field.placeholder_text = "Say something (Enter to send, Esc to cancel)"
	_field.visible = false
	_field.text_submitted.connect(func(t):
		_close_field()
		submit(t))
	vb.add_child(_field)
	var bottom := HBoxContainer.new()
	vb.add_child(bottom)
	_status = CKUI.label("", 13, CKUI.MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_status)
	_hints = CKUI.label("Hold V: speak   ·   T: type   ·   Esc: leave", 13, CKUI.MUTED)
	bottom.add_child(_hints)


func _say_line(who: String, text: String) -> void:
	_lines.append([who, text])
	while _lines.size() > 6:
		_lines.pop_front()
	line.emit(who, text)
	if _log == null:
		return
	var out := ""
	for l in _lines:
		match l[0]:
			"you":
				out += "[b][color=#ff405d]Crimson Knight:[/color][/b] %s\n" % l[1]
			"sys":
				out += "[color=#b9a9b0][i]%s[/i][/color]\n" % l[1]
			_:
				var d: Dictionary = defs.get(l[0], {"name": l[0], "accent": "#ffffff"})
				out += "[b][color=%s]%s:[/color][/b] %s\n" % [d.get("accent", "#ffffff"), d["name"], l[1]]
	_log.text = out


func _update_ui() -> void:
	if not talking or partner == null:
		return
	var r := memory.rec(partner.def)
	_title.text = "%s  ·  %s" % [partner.def["name"], VillainMemory.attitude(r)]
	# the microphone indicator is shown whenever audio is being captured, and only then
	if voice.listening:
		_mic.text = "● REC " + "|".repeat(1 + int(voice.level * 8))
		_mic.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
	else:
		_mic.text = "" if mic_allowed() else "mic off"
		_mic.modulate.a = 1.0
	var engines := "" if game.red.brain_ready else "  (local AI offline: scripted lines)"
	_status.text = {"idle": "Your turn", "greeting": "%s sizes you up…" % partner.def["name"], "listening": "Listening… release V when done",
		"hearing": "Transcribing…", "thinking": "%s is thinking…" % partner.def["name"], "speaking": "%s is speaking" % partner.def["name"]}.get(state, "") + engines


# ---------------- test hooks ----------------
## --villain=<id>: put the Knight 2.4 m in front of that villain, facing him.
func _test_setup(id: String) -> void:
	if not villains.has(id):
		push_warning("--villain: unknown id " + id)
		return
	var v: Villain = villains[id]
	var fwd := Vector3(sin(v.rotation.y), 0, cos(v.rotation.y))
	game.player.teleport(v.global_position + fwd * 2.4 + Vector3(0, 0.3, 0))
	game.player.heading = atan2(-fwd.x, -fwd.z)
	game.cam.yaw = game.player.heading + PI


## --villainscript="wav:<file>|text|..." items run one at a time whenever it's the Knight's turn.
func _run_script(item: String) -> void:
	if item.begins_with("wav:"):
		var f := FileAccess.open(item.substr(4), FileAccess.READ)
		if f == null:
			push_warning("--villainscript: can't read " + item.substr(4))
			return
		state = "hearing"
		print("[villain] f%d test: sending %s to whisper (as if V was held)" % [game.frame, item.substr(4).get_file()])
		voice.transcribe(f.get_buffer(f.get_length()), _vocab())
	elif item == "end":
		end()
	else:
		submit(item)
