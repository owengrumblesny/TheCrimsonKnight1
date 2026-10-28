class_name CKAudio
extends Node
## Original synthesized placeholder sounds (port of systems/audio.ts): no downloaded or third-party audio.
## Each event is rendered once at startup into an AudioStreamWAV from the same recipes as the web build
## (oscillator sweeps with exponential envelopes, biquad-filtered noise) and played on per-category buses
## (Music, Ambience, SFX, Vehicles, UI) whose levels follow the settings. A real recording can replace any
## event later by putting its stream in `_streams`.

const RATE := 22050
const BUSES := {"music": "Music", "ambience": "Ambience", "sfx": "SFX", "vehicles": "Vehicles", "ui": "UI"}

var _streams := {} # event -> Array[AudioStreamWAV] (variants)
var _pool: Array = []
var _last := {}
var _ambience: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "Audio"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 2701
	for key in BUSES:
		if AudioServer.get_bus_index(BUSES[key]) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, BUSES[key])
			AudioServer.set_bus_send(i, "Master")
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_render_all()
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = _ambience_loop()
	_ambience.bus = "Ambience"
	_ambience.volume_db = linear_to_db(0.16)
	add_child(_ambience)


func apply_settings(s: Dictionary) -> void:
	AudioServer.set_bus_mute(0, s["muted"])
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, s["volumes"]["master"])))
	for key in BUSES:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUSES[key]), linear_to_db(maxf(0.0001, s["volumes"][key])))


## Rain / city ambience loop (low-passed noise). Starting twice never stacks loops.
func start_ambience() -> void:
	if not _ambience.playing:
		_ambience.play()


## Duck the world ambience while a menu pauses the game (UI sounds keep working).
func set_paused(paused: bool) -> void:
	create_tween().tween_property(_ambience, "volume_db", linear_to_db(0.04 if paused else 0.16), 0.3)


## One-shot; strength 0..1 scales landings. Rate-limited per event (45 ms) and capped by the player pool.
func play(event: String, strength := 1.0) -> void:
	if not _streams.has(event):
		return
	var now := Time.get_ticks_msec()
	if now - _last.get(event, -1000) < 45:
		return
	_last[event] = now
	for p in _pool:
		if not p.playing:
			var variants: Array = _streams[event]
			p.stream = variants[_rng.randi() % variants.size()]
			p.bus = "UI" if event.begins_with("ui.") else "Vehicles" if event.begins_with("vehicle") else "SFX"
			p.volume_db = linear_to_db(clampf(0.3 + 0.7 * strength, 0.05, 1.0)) if event == "armor.land" else 0.0
			p.play()
			return


# ---------------- synthesis ----------------
func _render_all() -> void:
	_streams["ui.click"] = [_mix([_tone("triangle", 1200, 900, 0.05, 0.25)])]
	_streams["ui.select"] = [_mix([_tone("sine", 660, 990, 0.08, 0.25)])]
	_streams["ui.open"] = [_mix([_tone("sine", 320, 640, 0.12, 0.22)])]
	_streams["ui.close"] = [_mix([_tone("sine", 640, 300, 0.12, 0.2)])]
	_streams["ui.deny"] = [_mix([_tone("square", 180, 140, 0.14, 0.12)])]
	_streams["armor.step"] = []
	for i in 4: # the web build randomises the step hiss per play; four pre-rendered variants
		_streams["armor.step"].append(_mix([_hiss(900 + _rng.randf() * 300, 1.2, 0.09, 0.35), _tone("sine", 90, 60, 0.07, 0.25)]))
	_streams["armor.jump"] = [_mix([_hiss(1400, 0.8, 0.18, 0.25), _tone("sawtooth", 220, 440, 0.12, 0.05)])]
	_streams["armor.land"] = [_mix([_hiss(500, 0.7, 0.55, 0.9), _tone("sine", 110, 40, 0.6, 0.7)])]
	_streams["armor.activate"] = [_mix([_tone("sawtooth", 300, 900, 0.25, 0.08), _tone("sine", 900, 1200, 0.15, 0.12, 0.2)])]
	_streams["gadget.deploy"] = [_mix([_tone("square", 500, 1500, 0.1, 0.07), _hiss(3000, 2, 0.12, 0.2)])]
	_streams["gadget.throw"] = [_mix([_hiss(2200, 3, 0.25, 0.35, "highpass")])]
	_streams["gadget.pulse"] = [_mix([_tone("sine", 1800, 300, 0.6, 0.2), _hiss(600, 0.5, 0.5, 0.25)])]
	_streams["vehicle.summon"] = [_mix([_tone("sine", 880, 880, 0.12, 0.2), _tone("sine", 1320, 1320, 0.18, 0.2, 0.14)])]


## Oscillator with an exponential frequency sweep f0 -> f1 and a 5 ms exp attack / exp decay to `dur`.
func _tone(type: String, f0: float, f1: float, dur: float, vol: float, delay := 0.0) -> PackedFloat32Array:
	var start := int(delay * RATE)
	var n := int((delay + dur + 0.02) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	f1 = maxf(20.0, f1)
	for i in range(start, n):
		var t := float(i - start) / RATE
		var k := minf(1.0, t / dur)
		var f := f0 * pow(f1 / f0, k)
		phase = fmod(phase + f / RATE, 1.0)
		var s: float
		match type:
			"sine": s = sin(TAU * phase)
			"triangle": s = 1.0 - 4.0 * absf(phase - 0.5)
			"square": s = 1.0 if phase < 0.5 else -1.0
			_: s = 2.0 * phase - 1.0 # sawtooth
		var g := 0.0001 * pow(vol / 0.0001, minf(1.0, t / 0.005)) if t < 0.005 else vol * pow(0.0001 / vol, clampf((t - 0.005) / (dur - 0.005), 0.0, 1.0))
		out[i] = s * g
	return out


## Noise through an RBJ biquad (bandpass / highpass / lowpass), exp decay from vol to silence over dur.
func _hiss(freq: float, q: float, dur: float, vol: float, type := "bandpass") -> PackedFloat32Array:
	var n := int((dur + 0.02) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var w := TAU * freq / RATE
	var alpha := sin(w) / (2.0 * q)
	var c := cos(w)
	var b0: float
	var b1: float
	var b2: float
	match type:
		"highpass":
			b0 = (1 + c) / 2
			b1 = -(1 + c)
			b2 = (1 + c) / 2
		"lowpass":
			b0 = (1 - c) / 2
			b1 = 1 - c
			b2 = (1 - c) / 2
		_:
			b0 = alpha
			b1 = 0
			b2 = -alpha
	var a0 := 1 + alpha
	var a1 := -2 * c
	var a2 := 1 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in n:
		var x := _rng.randf() * 2 - 1
		var y := (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		var t := float(i) / RATE
		out[i] = y * vol * pow(0.0001 / vol, minf(1.0, t / dur))
	return out


func _mix(parts: Array) -> AudioStreamWAV:
	var n := 0
	for p in parts:
		n = maxi(n, p.size())
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := 0.0
		for p in parts:
			if i < p.size():
				s += p[i]
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


func _ambience_loop() -> AudioStreamWAV:
	# 2 s of one-pole low-passed noise (~2.4 kHz) at constant level, looped
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	var n := 2 * RATE
	var data := PackedByteArray()
	data.resize(n * 2)
	var y := 0.0
	var k := 1.0 - exp(-TAU * 2400.0 / RATE)
	for i in n:
		y += k * ((_rng.randf() * 2 - 1) - y) # one-pole low-pass
		data.encode_s16(i * 2, int(clampf(y, -1.0, 1.0) * 32767))
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w
