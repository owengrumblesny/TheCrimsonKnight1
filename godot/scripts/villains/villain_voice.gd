class_name VillainVoice
extends Node
## Villain speech, fully local.
##  - Out: ONE long-running Piper process with the multi-speaker en_US-libritts_r-medium model (ai/models, 904
##    voices in 78 MB). Lines go in as JSON with the villain's speaker id; Piper prints each WAV path. The WAV
##    plays on the villain's AudioStreamPlayer3D (positional) through his own bus: a pitch-preserving tempo
##    correction plus an effect recipe (metal, hall, theater, soft, deep, digital, room). Playback rate sets
##    pitch, so voice = speaker timbre x rate x tempo x effects.
##  - In: push-to-talk only. The microphone plays into a muted capture bus only while V is held (nothing is
##    recorded otherwise). On release the audio goes to the local whisper-server R.E.D. already runs
##    (whisper.cpp base.en, port 8090). With R.E.D.'s voice input switched off in Settings the mic is never
##    opened at all.

signal voiced(villain_id: String, wav: AudioStreamWAV)
signal heard(text: String, ms: int)

const MODEL := "models/en_US-libritts_r-medium.onnx"
const WHISPER_PORT := 8090

var ai_dir := ""
var tts_ready := false
var listening := false
var transcribing := false
var level := 0.0 # mic level 0..1 while listening (for the indicator)

var _pid := -1
var _io: FileAccess
var _buf := ""
var _out_dir := ""
var _jobs := {} # wav path -> villain id
var _seq := 0
var _mic: AudioStreamPlayer
var _capture: AudioEffectCapture
var _rec := PackedFloat32Array()
var _rate := 44100.0
var _http: HTTPRequest
var _sent_at := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = 25
	add_child(_http)


func start(dir: String) -> bool:
	if tts_ready:
		return true
	ai_dir = dir
	var exe := ai_dir.path_join("piper/piper/piper.exe")
	var model := ai_dir.path_join(MODEL)
	if not FileAccess.file_exists(exe) or not FileAccess.file_exists(model):
		push_warning("Villains: Piper or %s missing; villains speak in subtitles only" % MODEL)
		return false
	_out_dir = OS.get_user_data_dir().path_join("villain_tts")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for f in DirAccess.get_files_at(_out_dir):
		DirAccess.remove_absolute(_out_dir.path_join(f))
	var p := OS.execute_with_pipe(exe, ["-m", model, "--json-input", "--length_scale", "0.95", "--sentence_silence", "0.15", "-q"], false)
	if p.is_empty():
		push_warning("Villains: Piper failed to start")
		return false
	_pid = p["pid"]
	_io = p["stdio"]
	tts_ready = true
	return true


func stop() -> void:
	if _pid > 0:
		OS.kill(_pid)
	_pid = -1
	tts_ready = false


func _exit_tree() -> void:
	stop()


func say(villain_id: String, speaker: int, text: String) -> bool:
	if not tts_ready:
		return false
	_seq += 1
	var path := _out_dir.path_join("%s_%d.wav" % [villain_id, _seq])
	_jobs[path] = villain_id
	_io.store_line(JSON.stringify({"text": text.replace("\n", " "), "speaker_id": speaker, "output_file": path}))
	_io.flush()
	return true


func _process(_dt: float) -> void:
	if _io and _pid > 0 and not _jobs.is_empty():
		var chunk := _io.get_buffer(4096)
		if not chunk.is_empty():
			_buf += chunk.get_string_from_utf8()
			while _buf.contains("\n"):
				var i := _buf.find("\n")
				var line := _buf.substr(0, i).strip_edges().replace("\\", "/")
				_buf = _buf.substr(i + 1)
				for path in _jobs.keys():
					if line.ends_with(String(path).replace("\\", "/").get_file()):
						var w := AudioStreamWAV.load_from_file(path)
						DirAccess.remove_absolute(path)
						var id: String = _jobs[path]
						_jobs.erase(path)
						if w:
							voiced.emit(id, w)
						break
	if listening and _capture:
		var n := _capture.get_frames_available()
		if n > 0:
			var peak := 0.0
			for f in _capture.get_buffer(n):
				var s := (f.x + f.y) * 0.5
				_rec.append(s)
				peak = maxf(peak, absf(s))
			level = lerpf(level, clampf(peak * 3.0, 0.0, 1.0), 0.5)
		if _rec.size() > _rate * 20:
			stop_listening()


# ---------------- per-villain voice bus ----------------
## "VillainVoice_<id>" bus: tempo correction (pitch shift by 1/rate keeps the timbre when rate != tempo) plus
## the villain's effect recipe. Created once.
static func bus_for(def: Dictionary) -> String:
	var name := "VillainVoice_" + str(def["id"])
	if AudioServer.get_bus_index(name) >= 0:
		return name
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, "Master")
	var v: Dictionary = def["voice"]
	var rate := float(v.get("pitch", 1.0)) * float(v.get("tempo", 1.0))
	var want_pitch := float(v.get("pitch", 1.0))
	if absf(rate - want_pitch) > 0.005:
		var ps := AudioEffectPitchShift.new()
		ps.pitch_scale = want_pitch / rate
		AudioServer.add_bus_effect(i, ps)
	match str(v.get("fx", "room")):
		"metal": # the Iron Sovereign: a helmet comb + chorus, a little grit
			var ch := AudioEffectChorus.new()
			ch.voice_count = 2
			ch.wet = 0.35
			AudioServer.add_bus_effect(i, ch)
			var d := AudioEffectDistortion.new()
			d.mode = AudioEffectDistortion.MODE_CLIP
			d.drive = 0.18
			d.post_gain = -2.0
			AudioServer.add_bus_effect(i, d)
			AudioServer.add_bus_effect(i, _reverb(0.25, 0.15))
		"hall":
			AudioServer.add_bus_effect(i, _reverb(0.7, 0.18))
		"theater":
			AudioServer.add_bus_effect(i, _reverb(0.85, 0.26))
		"soft": # Doctor Hollow: close, dark, quiet
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 3800
			AudioServer.add_bus_effect(i, lp)
			AudioServer.add_bus_effect(i, _reverb(0.2, 0.08))
		"deep": # Lord Umbra: low shelf up, long tail
			var eq := AudioEffectEQ6.new()
			eq.set_band_gain_db(0, 4.0)
			eq.set_band_gain_db(1, 2.0)
			AudioServer.add_bus_effect(i, eq)
			AudioServer.add_bus_effect(i, _reverb(0.8, 0.2))
		"digital": # the Cipher King: thin band-limited edge
			var hp := AudioEffectHighPassFilter.new()
			hp.cutoff_hz = 220
			AudioServer.add_bus_effect(i, hp)
			var ph := AudioEffectPhaser.new()
			ph.rate_hz = 3.0
			ph.depth = 0.25
			AudioServer.add_bus_effect(i, ph)
		_:
			AudioServer.add_bus_effect(i, _reverb(0.35, 0.1))
	AudioServer.set_bus_volume_db(i, 3.0)
	return name


## Playback rate for the villain's player (pitch x tempo; the bus undoes the tempo part of the pitch).
static func rate_for(def: Dictionary) -> float:
	var v: Dictionary = def["voice"]
	return float(v.get("pitch", 1.0)) * float(v.get("tempo", 1.0))


static func _reverb(room: float, wet: float) -> AudioEffectReverb:
	var rv := AudioEffectReverb.new()
	rv.room_size = room
	rv.damping = 0.5
	rv.wet = wet
	rv.dry = 1.0
	return rv


# ---------------- speech in (push-to-talk) ----------------
func start_listening() -> void:
	if listening:
		return
	if _mic == null:
		var bus := "VillainMic"
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
			_capture = AudioEffectCapture.new()
			_capture.buffer_length = 0.5
			AudioServer.add_bus_effect(i, _capture)
			AudioServer.set_bus_mute(i, true) # captured, never played back
		else:
			_capture = AudioServer.get_bus_effect(AudioServer.get_bus_index(bus), 0)
		_mic = AudioStreamPlayer.new()
		_mic.stream = AudioStreamMicrophone.new()
		_mic.bus = bus
		add_child(_mic)
	_rate = AudioServer.get_mix_rate()
	_rec = PackedFloat32Array()
	_capture.clear_buffer()
	_mic.play()
	listening = true


## Released: stop the microphone at once, then transcribe what was said.
func stop_listening(vocab := "") -> void:
	if not listening:
		return
	listening = false
	level = 0.0
	_mic.stop()
	if _rec.size() < _rate * 0.35:
		heard.emit("", 0)
		return
	transcribe(RedVoice._to_wav16k(_rec, _rate), vocab)


## WAV bytes -> whisper-server -> heard(text). Also used by the --villainwav test hook with a recorded file.
func transcribe(wav: PackedByteArray, vocab := "") -> void:
	transcribing = true
	_sent_at = Time.get_ticks_msec()
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	var b := "----villainboundary5QX2"
	var body := PackedByteArray()
	for kv in [["response_format", "json"], ["temperature", "0.0"], ["prompt", "Crimson Knight. " + vocab]]:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [b, kv[0], kv[1]]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ptt.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % b).to_utf8_buffer())
	body.append_array(wav)
	body.append_array(("\r\n--%s--\r\n" % b).to_utf8_buffer())
	_http.request_completed.connect(_on_transcribed, CONNECT_ONE_SHOT)
	if _http.request_raw("http://127.0.0.1:%d/inference" % WHISPER_PORT, ["Content-Type: multipart/form-data; boundary=" + b],
			HTTPClient.METHOD_POST, body) != OK:
		_http.request_completed.disconnect(_on_transcribed)
		transcribing = false
		heard.emit("", 0)


func _on_transcribed(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	transcribing = false
	var text := ""
	if code == 200:
		var j = JSON.parse_string(body.get_string_from_utf8())
		if j is Dictionary:
			text = str(j.get("text", "")).strip_edges()
	for junk in ["[BLANK_AUDIO]", "(silence)", "[silence]", "[ Silence ]", "(blank audio)"]:
		text = text.replace(junk, "")
	heard.emit(text.strip_edges(), Time.get_ticks_msec() - _sent_at)
