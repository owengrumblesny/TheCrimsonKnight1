class_name RedAI
extends Node
## R.E.D., the CR-X9 suit AI: a sassy, helpful voice in the Knight's helmet (see docs/RED_AI.md).
##  - Commands (typed with Enter or spoken with push-to-talk Y) go through RedCommands.parse, which is deterministic,
##    and run instantly: vehicles, overdrive and armor buffs, repair, shield, enemy scan, waypoints, police jamming,
##    gear, eject and vehicle modes. Her replies to commands are hand-written lines (godot/data/red_lines.json).
##  - Anything that isn't a command is conversation: it goes to a local LLM (llama.cpp llama-server with
##    Qwen2.5-1.5B-Instruct Q4, launched by the game, CPU only, 3 threads) with a short status line of the game
##    state, so she can give real advice. With no LLM she falls back to scripted lines.
##  - She watches the game and speaks up: low health, heat, new crimes, ambushes, objectives, big combos, idle tips.

signal line(who: String, text: String) # "red" / "you" lines for the comm panel
signal status_changed(text: String)

const LLM_PORT := 8089
const SYSTEM := "You are R.E.D., the AI built into the Crimson Knight's armored suit in New Gotham, made by Owen Enterprises. You talk to him through his helmet. Personality: sassy, dry, smug, a little vain about being brilliant, teasing him constantly, but loyal and actually helpful. Robotic deadpan. Rules: ONE or TWO short sentences, under 30 words. No emoji, no lists, no asterisks, no stage directions. Never say you are a language model. If he needs help, give one concrete tip using the status. Things you can do for him if he asks: bring the Interceptor car, the Cycle bike or the Specter jet; overdrive (double strength); armor boost; repair the suit; shield; scan for enemies; route him to crimes, missions or the Citadel; jam police radios. Controls he can use: G grapple, hold Space in the air to glide, E counter, C dodge, right mouse aims."
const SHOTS := [
	["[health 90, heat 0, on foot] Knight: hi RED", "Oh good, you're awake. I've been running this suit alone for ages and frankly I'm the better half."],
	["[health 40, heat 2, 3 enemies close] Knight: any advice?", "Three thugs, forty percent health. Counter when they flash red, and maybe ask me for overdrive before you embarrass us both."],
	["[health 100, heat 0, driving the Interceptor] Knight: do you like me?", "I tolerate you. That's practically a marriage proposal from me."],
]
## ability: [duration s, cooldown s, display name]
const ABILITIES := {"overdrive": [20.0, 60.0, "Overdrive"], "armor_boost": [20.0, 60.0, "Armor boost"], "repair": [0.0, 75.0, "Repair"],
	"shield": [5.0, 40.0, "Shield"], "scan": [8.0, 12.0, "Scan"], "cool_heat": [0.0, 90.0, "Police jamming"]}

var game: Node # main.gd
var voice: RedVoice
var brain_enabled := true
var chatter_enabled := true
var brain_ready := false
var thinking := false
var ai_dir := ""
var lines := {}
var history: Array = [] # [[user, assistant], ...] last few exchanges
var cooldown := {} # ability -> ms when ready again
var active := {} # ability -> ms when it ends

var _llm_pid := -1
var _http: HTTPRequest
var _health_t := 0.0
var _health_tries := 0
var _watch_t := 1.0
var _last_said := -100000
var _event_cd := {} # event -> ms
var _prev := {}
var _scan_marks: Array = []
var _aura: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _idle_t := 90.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	lines = CKData.data("red_lines")
	_http = HTTPRequest.new()
	_http.timeout = 25
	add_child(_http)
	voice = RedVoice.new()
	add_child(voice)
	voice.heard.connect(_on_heard)


static func find_ai_dir() -> String:
	for d in [ProjectSettings.globalize_path("res://ai"), OS.get_executable_path().get_base_dir().path_join("ai")]:
		if DirAccess.dir_exists_absolute(d):
			return d
	return ""


## Launch the local engines (skipped in scripted runs unless --red). Reuses a server already on the port.
func start_engines(tts: bool, stt: bool, brain: bool) -> void:
	ai_dir = find_ai_dir()
	brain_enabled = brain
	voice.tts_enabled = tts
	voice.stt_enabled = stt
	if ai_dir == "":
		push_warning("R.E.D.: no ai/ folder; scripted lines only")
		return
	voice.start(ai_dir)
	if brain:
		var exe := ai_dir.path_join("llama/llama-server.exe")
		var model := ai_dir.path_join("models/qwen2.5-1.5b-instruct-q4_k_m.gguf")
		if FileAccess.file_exists(exe) and FileAccess.file_exists(model):
			_health_tries = 90
			_health_t = 0.0
			_llm_pid = -2 # decided after the first health check (reuse a running server)
		else:
			push_warning("R.E.D.: llama-server or the model is missing; chat uses scripted lines")


func stop_engines() -> void:
	if _llm_pid > 0:
		OS.kill(_llm_pid)
	_llm_pid = -1
	brain_ready = false
	voice.stop_all()


func _exit_tree() -> void:
	stop_engines()


func _launch_llm() -> void:
	var exe := ai_dir.path_join("llama/llama-server.exe")
	var model := ai_dir.path_join("models/qwen2.5-1.5b-instruct-q4_k_m.gguf")
	# 3 CPU threads, small context, no GPU: the game keeps the GPU and at least one core
	_llm_pid = OS.create_process(exe, ["-m", model, "--host", "127.0.0.1", "--port", str(LLM_PORT), "-c", "2048", "-t", "3",
		"-ngl", "0", "--no-webui", "--parallel", "1"])


# ---------------- main loop ----------------
func _process(dt: float) -> void:
	var now := Time.get_ticks_msec()
	if _health_tries > 0 and not thinking and _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_health_t -= dt
		if _health_t <= 0.0:
			_health_t = 1.0
			_health_tries -= 1
			_http.request_completed.connect(_on_llm_health, CONNECT_ONE_SHOT)
			if _http.request("http://127.0.0.1:%d/health" % LLM_PORT) != OK:
				_http.request_completed.disconnect(_on_llm_health)
	if game == null or not game.started or get_tree().paused:
		return
	# push-to-talk
	if Input.is_action_just_pressed("talkToRed"):
		voice.start_listening()
		_status()
	elif voice.listening and not Input.is_action_pressed("talkToRed"):
		voice.stop_listening()
		_status()
	_update_abilities(now)
	_watch_t -= dt
	if _watch_t <= 0.0:
		_watch_t = 0.5
		_watch(now)


func _on_llm_health(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if code == 200:
		_health_tries = 0
		brain_ready = true
		_warm_up()
		_status()
	elif _llm_pid == -2:
		_launch_llm() # nothing running on the port yet: start ours and keep polling


## Prime llama.cpp's prompt cache with the system prompt so the first real reply is quick.
func _warm_up() -> void:
	thinking = true
	_http.request_completed.connect(func(_r, _c, _h, _b): thinking = false, CONNECT_ONE_SHOT)
	_http.request("http://127.0.0.1:%d/v1/chat/completions" % LLM_PORT, ["Content-Type: application/json"], HTTPClient.METHOD_POST,
		JSON.stringify({"messages": _messages("hello"), "max_tokens": 1, "cache_prompt": true}))


# ---------------- input from the Knight ----------------
## Typed or spoken text. Commands run now; anything else is chat.
func hear(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return
	line.emit("you", text)
	_idle_t = 120.0
	var acts := RedCommands.parse(text, RedCommands.item_names(game.inventory))
	if acts.is_empty():
		chat(text)
		return
	var replies: Array = []
	for a in acts:
		var r := run(a["do"], a.get("arg", ""))
		if r != "":
			replies.append(r)
	if not replies.is_empty():
		speak(" ".join(replies), true)


func _on_heard(text: String) -> void:
	_status()
	if text == "":
		speak(_pick("didnt_hear"))
	else:
		hear(text)


func speak(text: String, interrupt := false) -> void:
	if text == "":
		return
	_last_said = Time.get_ticks_msec()
	line.emit("red", text)
	game.audio.play("red.chirp")
	voice.say(text, interrupt)


func _pick(key: String, vars := {}) -> String:
	var arr: Array = lines.get(key, [])
	if arr.is_empty():
		return ""
	var s: String = arr[_rng.randi() % arr.size()]
	for k in vars:
		s = s.replace("{%s}" % k, str(vars[k]))
	return s


# ---------------- actions ----------------
## Run one action; returns R.E.D.'s line about it.
func run(act: String, arg := "") -> String:
	var now := Time.get_ticks_msec()
	var d: Director = game.director
	var v: Vitals = game.vitals
	if ABILITIES.has(act):
		if active.get(act, 0) > now:
			return _pick("busy")
		if cooldown.get(act, 0) > now:
			return _pick("cooldown", {"ability": ABILITIES[act][2], "secs": ceili((cooldown[act] - now) / 1000.0)})
	match act:
		"summon":
			if game.underground:
				return _pick("summon_fail")
			game.quick_vehicle = arg
			game.drive.summon(arg, false)
			return _pick("summon_" + arg)
		"overdrive":
			game.melee.power = 2.0
			_aura_on(Color(1, 0.15, 0.2))
			game.effects.burst("electrical", game.player.global_position + Vector3(0, 1.2, 0), 10, 2.0, 0.6, 0.4)
			game.audio.play("armor.activate")
		"armor_boost":
			d.armor_mult = 0.5
			_aura_on(Color(0.5, 0.75, 1.0))
			game.audio.play("armor.activate")
		"repair":
			if v.health >= Vitals.MAX - 1 and v.armor >= Vitals.MAX - 1:
				return _pick("repair_full")
			v.health = minf(Vitals.MAX, v.health + 45.0)
			v.armor = minf(Vitals.MAX, v.armor + 30.0)
			game.effects.burst("electrical", game.player.global_position + Vector3(0, 1.0, 0), 6, 1.2, 0.5, 0.3)
			_cool(act, now)
			return _pick("repair", {"hp": int(v.health)})
		"shield":
			v.shield_until = now + int(ABILITIES[act][0] * 1000)
			game.audio.play("gadget.deploy")
		"scan":
			var n := _scan(now)
			_cool(act, now)
			return _pick("scan", {"n": n}) if n > 0 else _pick("scan_none")
		"cool_heat":
			if d.stars() == 0:
				return _pick("cool_heat_none")
			d.heat = float(d.stars() - 1)
			_cool(act, now)
			return _pick("cool_heat", {"stars": d.stars()})
		"waypoint_crime":
			var c := _nearest_crime()
			var fresh := false
			if c.is_empty():
				d.start_crime()
				c = _nearest_crime()
				fresh = true
			if c.is_empty():
				return _pick("scan_none")
			d.waypoint = c["pos"]
			return _pick("waypoint_crime_new" if fresh else "waypoint_crime", _crime_vars(c))
		"waypoint_mission":
			if d.mission.is_empty() or not d.mission.has("pos"):
				if d.mission.is_empty():
					return _pick("waypoint_mission_none")
				return _pick("mission_new", {"objective": d.objective})
			d.waypoint = d.mission["pos"]
			return _pick("waypoint_mission", {"objective": d.objective})
		"start_mission":
			d.start_mission(d.mission_index)
			if d.mission.has("pos"):
				d.waypoint = d.mission["pos"]
			return _pick("start_mission", {"title": d.mission.get("title", "the next job")})
		"waypoint_citadel":
			d.waypoint = game.portal
			return _pick("waypoint_citadel")
		"clear_waypoint":
			d.waypoint = null
			return _pick("clear_waypoint")
		"equip":
			var i: int = game.inventory.hotbar.find(arg)
			if i < 0:
				return _pick("equip_fail")
			game.select_slot(i)
			return _pick("equip", {"item": game.inventory.def(arg).get("displayName", arg)})
		"eject":
			if game.drive.driving and game.drive.driving.id == "crx1_interceptor":
				game.drive.eject()
				return _pick("eject")
			return _pick("eject_fail")
		"vehicle_mode":
			if not game.drive.driving:
				return _pick("vehicle_mode_fail")
			var ev := InputEventAction.new()
			ev.action = "vehicleMode"
			ev.pressed = true
			Input.parse_input_event(ev)
			(func():
				var up := InputEventAction.new()
				up.action = "vehicleMode"
				Input.parse_input_event(up)).call_deferred()
			return _pick("vehicle_mode")
		"status":
			return _pick("status", {"hp": int(v.health), "armor": int(v.armor), "energy": int(v.energy), "stars": d.stars(), "buffs": _buff_text()})
		"help":
			return _pick("help")
		"stop":
			voice.shut_up()
			line.emit("red", _pick("stop"))
			return ""
		_:
			return ""
	# timed abilities
	active[act] = now + int(ABILITIES[act][0] * 1000)
	_cool(act, now)
	_status()
	return _pick(act)


func _cool(act: String, now: int) -> void:
	cooldown[act] = now + int(ABILITIES[act][1] * 1000)


func _update_abilities(now: int) -> void:
	for act in active.keys():
		if active[act] <= now:
			active.erase(act)
			match act:
				"overdrive":
					game.melee.power = 1.0
				"armor_boost":
					game.director.armor_mult = 1.0
			if act in ["overdrive", "armor_boost"]:
				if not active.has("overdrive") and not active.has("armor_boost"):
					_aura_off()
				_say_event("buff_end", {"ability": ABILITIES[act][2]}, 0)
			_status()
	if not active.is_empty():
		_status()


func _aura_on(c: Color) -> void:
	if _aura == null:
		_aura = OmniLight3D.new()
		_aura.position = Vector3(0, 1.2, 0)
		_aura.omni_range = 3.5
		_aura.shadow_enabled = false
		game.player.add_child(_aura)
	_aura.light_color = c
	_aura.light_energy = 1.6
	_aura.visible = true


func _aura_off() -> void:
	if _aura:
		_aura.visible = false


## Mark every upright enemy within 40 m with a red chevron for a few seconds; returns how many.
func _scan(now: int) -> int:
	var n := 0
	var p: Vector3 = game.player.global_position
	for e in game.director.enemies:
		if not is_instance_valid(e) or e.is_down() or e.global_position.distance_to(p) > 40.0:
			continue
		n += 1
		var l := Label3D.new()
		l.text = "▼"
		l.font_size = 72
		l.modulate = Color("#ff405d")
		l.outline_size = 12
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0006
		l.position = Vector3(0, 2.5, 0)
		e.add_child(l)
		get_tree().create_timer(ABILITIES["scan"][0], false).timeout.connect(func(): if is_instance_valid(l): l.queue_free())
	game.effects.burst("electrical", p + Vector3(0, 1, 0), 4, 1.5, 0.5, 0.3)
	game.audio.play("gadget.pulse")
	active["scan"] = now + int(ABILITIES["scan"][0] * 1000)
	return n


func _nearest_crime() -> Dictionary:
	var best := {}
	var bd := 1e9
	for c in game.director.crimes:
		var dd: float = c["pos"].distance_to(game.player.global_position)
		if dd < bd:
			bd = dd
			best = c
	return best


func _crime_vars(c: Dictionary) -> Dictionary:
	var to: Vector3 = c["pos"] - game.player.global_position
	return {"crime": String(c.get("kind", "a crime")).capitalize(),
		"dist": int(Vector2(to.x, to.z).length() / 10.0) * 10, "dir": game.director._dir_word(c["pos"])}


func _buff_text() -> String:
	var now := Time.get_ticks_msec()
	var parts: Array = []
	for act in active:
		if act != "scan":
			parts.append("%s %d s" % [ABILITIES[act][2], ceili((active[act] - now) / 1000.0)])
	return ("Active: " + ", ".join(parts) + ".") if not parts.is_empty() else ""


func _status() -> void:
	var s := ""
	if voice.listening:
		s = "Listening… (release Y)"
	elif voice.transcribing:
		s = "Hearing you…"
	elif _asking:
		s = "Thinking…"
	else:
		s = _buff_text().trim_prefix("Active: ").trim_suffix(".")
	status_changed.emit(s)


# ---------------- watching the game ----------------
func _say_event(key: String, vars: Dictionary, gap_ms := 9000, cd_ms := 30000) -> void:
	var now := Time.get_ticks_msec()
	if not chatter_enabled and key != "greet":
		return
	if now - _last_said < gap_ms or _event_cd.get(key, 0) > now or voice.listening or _asking:
		return
	_event_cd[key] = now + cd_ms
	speak(_pick(key, vars))


func _watch(now: int) -> void:
	var d: Director = game.director
	var v: Vitals = game.vitals
	var alerted := 0
	var near := 0
	for e in d.enemies:
		if is_instance_valid(e) and not e.is_down() and e.global_position.distance_to(game.player.global_position) < 40.0:
			near += 1
			if e.state in ["alert", "chase", "attack", "windup"]:
				alerted += 1
	var cur := {"hp": v.health, "stars": d.stars(), "crimes": d.crimes.size(), "objective": d.objective, "alerted": alerted,
		"combo": game.melee.combo, "near": near}
	if _prev.is_empty():
		_prev = cur
		_event_cd["greet"] = 0
		get_tree().create_timer(2.5).timeout.connect(func(): _say_event("greet", {}, 0))
		return
	if cur["hp"] < 30 and _prev["hp"] >= 30:
		_say_event("low_health", {"hp": int(cur["hp"])}, 0, 20000)
	elif cur["stars"] > _prev["stars"]:
		_say_event("heat_up", {"stars": cur["stars"]}, 4000, 15000)
	elif cur["stars"] == 0 and _prev["stars"] > 0:
		_say_event("heat_clear", {}, 4000, 20000)
	elif cur["alerted"] > 0 and _prev["alerted"] == 0:
		_say_event("enemies_alert", {"n": cur["alerted"]}, 6000, 40000)
	elif cur["near"] == 0 and _prev["near"] > 0 and _prev["alerted"] > 0:
		_say_event("fight_won", {}, 3000, 30000)
	elif cur["combo"] >= 10 and _prev["combo"] < 10:
		_say_event("big_combo", {}, 3000, 60000)
	elif cur["crimes"] > _prev["crimes"]:
		var c: Dictionary = d.crimes[-1]
		_say_event("crime_new", _crime_vars(c), 8000, 45000)
	elif cur["objective"] != _prev["objective"] and cur["objective"] != "":
		_say_event("mission_new", {"objective": cur["objective"]}, 5000, 10000)
	_prev = cur
	# idle tip when nothing has been said for a while
	_idle_t -= 0.5
	if _idle_t <= 0.0:
		_idle_t = 150.0
		_say_event("idle_tips", {}, 60000, 0)


# ---------------- conversation (local LLM) ----------------
var _asking := false
var _asked := ""


func state_line() -> String:
	var d: Director = game.director
	var v: Vitals = game.vitals
	var near := 0
	for e in d.enemies:
		if is_instance_valid(e) and not e.is_down() and e.global_position.distance_to(game.player.global_position) < 30.0:
			near += 1
	var where := "in the Red Citadel" if game.underground else "in the streets of New Gotham"
	var doing := "driving the %s" % game.drive.label(game.drive.driving) if game.drive.driving else String(game.player.mode).replace("ground", "on foot")
	var s := "[health %d, armor %d, heat %d stars, %d enemies close, %s, %s" % [int(v.health), int(v.armor), d.stars(), near, doing, where]
	var c := _nearest_crime()
	if not c.is_empty():
		var cv := _crime_vars(c)
		s += ", %s %d m %s" % [cv["crime"], cv["dist"], cv["dir"]]
	if d.objective != "":
		s += ", objective: " + d.objective
	var b := _buff_text()
	if b != "":
		s += ", " + b.trim_suffix(".")
	return s + "]"


func _messages(text: String) -> Array:
	var m: Array = [{"role": "system", "content": SYSTEM}]
	for s in SHOTS:
		m.append({"role": "user", "content": s[0]})
		m.append({"role": "assistant", "content": s[1]})
	for h in history:
		m.append({"role": "user", "content": h[0]})
		m.append({"role": "assistant", "content": h[1]})
	m.append({"role": "user", "content": text})
	return m


func chat(text: String) -> void:
	if not brain_ready:
		speak(_pick("chat_fallback"))
		return
	if _asking:
		_http.cancel_request()
	_asking = true
	thinking = true
	_asked = state_line() + " Knight: " + text
	_status()
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	_http.request_completed.connect(_on_reply, CONNECT_ONE_SHOT)
	var err := _http.request("http://127.0.0.1:%d/v1/chat/completions" % LLM_PORT, ["Content-Type: application/json"], HTTPClient.METHOD_POST,
		JSON.stringify({"messages": _messages(_asked), "max_tokens": 64, "temperature": 0.85, "top_p": 0.9, "cache_prompt": true}))
	if err != OK:
		_http.request_completed.disconnect(_on_reply)
		_asking = false
		thinking = false
		speak(_pick("chat_fallback"))


func _on_reply(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_asking = false
	thinking = false
	_status()
	var text := ""
	if code == 200:
		var j = JSON.parse_string(body.get_string_from_utf8())
		if j is Dictionary and j.get("choices") is Array and not j["choices"].is_empty():
			text = clean_reply(String(j["choices"][0]["message"]["content"]))
	if text == "":
		speak(_pick("chat_fallback"))
		return
	history.append([_asked, text])
	while history.size() > 4:
		history.pop_front()
	speak(text, true)


## Strip what a small model adds that shouldn't be spoken: stage directions, emoji, a "R.E.D.:" prefix, run-ons.
static func clean_reply(t: String) -> String:
	var re := RegEx.create_from_string("\\*[^*]*\\*|\\([^)]*\\)|[^\\x{0000}-\\x{2FFF}]")
	t = re.sub(t, "", true).strip_edges()
	for p in ["R.E.D.:", "RED:", "R.E.D:", "Red:"]:
		if t.begins_with(p):
			t = t.substr(p.length()).strip_edges()
	t = t.trim_prefix("\"").trim_suffix("\"")
	# at most two sentences
	var ends := RegEx.create_from_string("[.!?](\\s|$)")
	var count := 0
	for m in ends.search_all(t):
		count += 1
		if count == 2:
			return t.substr(0, m.get_end()).strip_edges()
	return t
