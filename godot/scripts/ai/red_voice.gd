class_name RedVoice
extends Node
## R.E.D.'s voice, fully local (see docs/RED_AI.md):
##  - speech out: one long-running Piper process (ai/piper, en_US-amy-low, 16 kHz). Each line goes in on stdin and
##    Piper prints the WAV it wrote. The WAV is loaded, run through a light "robot" filter (ring modulation plus a
##    metallic comb) and played on the RedVoice bus (phaser plus a small helmet reverb).
##  - speech in: push-to-talk. The microphone feeds an AudioEffectCapture only while the key is held. On release
##    the audio is downmixed to 16 kHz mono and POSTed to a local whisper-server (ai/whisper, base.en).
## Everything degrades: no Piper means text only; no whisper means typed chat only.

signal heard(text: String) # a transcription finished ("" = nothing understood)
signal speaking_changed(on: bool)

const WHISPER_PORT := 8090
const VOCAB := "R.E.D., Red, Interceptor, Cycle, Specter, overdrive, armor boost, batarang, Citadel, summon, waypoint, scan, police."

var ai_dir := ""
var tts_enabled := true
var stt_enabled := true
var tts_ready := false
var stt_ready := false
var listening := false
var transcribing := false
var robot := 0.22 # ring-mod mix 0..1

var _piper_pid := -1
var _piper_io: FileAccess
var _piper_buf := ""
var _out_dir := ""
var _queue: Array = [] # lines waiting for Piper
var _pending := 0 # lines sent to Piper, WAV not back yet
var _wavs: Array = [] # AudioStreamWAV ready to play
var _player: AudioStreamPlayer
var _whisper_pid := -1
var _mic: AudioStreamPlayer
var _capture: AudioEffectCapture
var _rec := PackedFloat32Array()
var _rate := 44100.0
var _http: HTTPRequest
var _health_t := 0.0
var _health_tries := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = _bus("RedVoice", true)
	_player.pitch_scale = 1.04
	_player.finished.connect(_next)
	add_child(_player)
	_http = HTTPRequest.new()
	_http.timeout = 20
	add_child(_http)


func _bus(name: String, voice: bool) -> String:
	if AudioServer.get_bus_index(name) >= 0:
		return name
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, "Master")
	if voice:
		var ph := AudioEffectPhaser.new()
		ph.rate_hz = 0.6
		ph.depth = 0.35
		ph.feedback = 0.25
		AudioServer.add_bus_effect(i, ph)
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.12
		rv.damping = 0.6
		rv.wet = 0.07
		rv.dry = 1.0
		AudioServer.add_bus_effect(i, rv)
		AudioServer.set_bus_volume_db(i, 2.0)
	else:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(i, _capture)
		AudioServer.set_bus_mute(i, true) # never heard back; capture still runs
	return name


func start(dir: String) -> void:
	ai_dir = dir
	_out_dir = OS.get_user_data_dir().path_join("red_tts")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for f in DirAccess.get_files_at(_out_dir):
		DirAccess.remove_absolute(_out_dir.path_join(f))
	if tts_enabled:
		_start_piper()
	if stt_enabled:
		_start_whisper()


func _start_piper() -> void:
	var exe := ai_dir.path_join("piper/piper/piper.exe")
	var model := ai_dir.path_join("models/en_US-amy-low.onnx")
	if not FileAccess.file_exists(exe) or not FileAccess.file_exists(model):
		push_warning("R.E.D.: Piper not found in %s; voice is text only" % ai_dir)
		return
	var p := OS.execute_with_pipe(exe, ["-m", model, "-d", _out_dir, "--length_scale", "0.9", "--sentence_silence", "0.1", "-q"], false)
	if p.is_empty():
		push_warning("R.E.D.: Piper failed to start")
		return
	_piper_pid = p["pid"]
	_piper_io = p["stdio"]
	tts_ready = true


func _start_whisper() -> void:
	var exe := ai_dir.path_join("whisper/Release/whisper-server.exe")
	var model := ai_dir.path_join("models/ggml-base.en.bin")
	if not FileAccess.file_exists(exe) or not FileAccess.file_exists(model):
		push_warning("R.E.D.: whisper not found; voice commands off (typed chat still works)")
		return
	_whisper_pid = OS.create_process(exe, ["-m", model, "--host", "127.0.0.1", "--port", str(WHISPER_PORT), "-t", "4", "-l", "en", "-ng"])
	_health_tries = 40


func stop_all() -> void:
	for pid in [_piper_pid, _whisper_pid]:
		if pid > 0:
			OS.kill(pid)
	_piper_pid = -1
	_whisper_pid = -1
	tts_ready = false
	stt_ready = false


func _exit_tree() -> void:
	stop_all()


# ---------------- speech out ----------------
func say(text: String, interrupt := false) -> void:
	if not tts_enabled or not tts_ready:
		return
	if interrupt:
		shut_up()
	if _queue.size() + _pending + _wavs.size() >= 3:
		return # don't pile up chatter
	_queue.append(text.replace("\n", " ").replace("R.E.D.", "Red").strip_edges())


func shut_up() -> void:
	_queue.clear()
	_wavs.clear()
	_player.stop()
	speaking_changed.emit(false)


func is_speaking() -> bool:
	return _player.playing


func _process(dt: float) -> void:
	if _piper_io and _piper_pid > 0:
		while not _queue.is_empty():
			_piper_io.store_line(_queue.pop_front())
			_piper_io.flush()
			_pending += 1
		if _pending > 0:
			_read_piper()
	# whisper-server health poll after launch
	if _health_tries > 0 and _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED and not transcribing:
		_health_t -= dt
		if _health_t <= 0.0:
			_health_t = 1.0
			_health_tries -= 1
			_http.request_completed.connect(_on_health, CONNECT_ONE_SHOT)
			if _http.request("http://127.0.0.1:%d/" % WHISPER_PORT) != OK:
				_http.request_completed.disconnect(_on_health)
	if listening and _capture:
		var n := _capture.get_frames_available()
		if n > 0:
			for f in _capture.get_buffer(n):
				_rec.append((f.x + f.y) * 0.5)
		if _rec.size() > _rate * 15:
			stop_listening()


func _on_health(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if code > 0:
		stt_ready = true
		_health_tries = 0


func _read_piper() -> void:
	var chunk := _piper_io.get_buffer(4096)
	if chunk.is_empty():
		return
	_piper_buf += chunk.get_string_from_utf8()
	while _piper_buf.contains("\n"):
		var i := _piper_buf.find("\n")
		var line := _piper_buf.substr(0, i).strip_edges()
		_piper_buf = _piper_buf.substr(i + 1)
		if line.ends_with(".wav"):
			_pending = maxi(0, _pending - 1)
			var w := AudioStreamWAV.load_from_file(line)
			DirAccess.remove_absolute(line)
			if w:
				_robotize(w)
				_wavs.append(w)
				if not _player.playing:
					_next()


func _next() -> void:
	if _wavs.is_empty():
		speaking_changed.emit(false)
		return
	_player.stream = _wavs.pop_front()
	_player.play()
	speaking_changed.emit(true)


## Ring modulation (a soft electronic warble) plus a 3 ms comb (metallic sheen), then a soft clip.
func _robotize(w: AudioStreamWAV) -> void:
	if w.format != AudioStreamWAV.FORMAT_16_BITS or w.stereo:
		return
	var d := w.data
	var n := d.size() / 2
	var sr := float(w.mix_rate)
	var src := PackedFloat32Array()
	src.resize(n)
	for i in n:
		src[i] = d.decode_s16(i * 2) / 32768.0
	var lag := int(sr * 0.003)
	var k := TAU * 52.0 / sr
	for i in n:
		var s := src[i]
		s = s * (1.0 - robot) + s * sin(k * i) * robot * 2.0
		if i >= lag:
			s += src[i - lag] * 0.3
		s = tanh(s * 1.1)
		d.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	w.data = d


# ---------------- speech in ----------------
func start_listening() -> void:
	if not stt_enabled or listening:
		return
	if _mic == null:
		_mic = AudioStreamPlayer.new()
		_mic.stream = AudioStreamMicrophone.new()
		_mic.bus = _bus("RedMic", false)
		add_child(_mic)
	_rate = AudioServer.get_mix_rate()
	_rec = PackedFloat32Array()
	_capture.clear_buffer()
	_mic.play()
	listening = true
	shut_up() # she stops talking when you talk


func stop_listening() -> void:
	if not listening:
		return
	listening = false
	_mic.stop()
	if _rec.size() < _rate * 0.35:
		heard.emit("")
		return
	transcribe(_to_wav16k(_rec, _rate))


## 16-bit mono 16 kHz WAV bytes from float samples at `rate` (box-filter downsample).
static func _to_wav16k(src: PackedFloat32Array, rate: float) -> PackedByteArray:
	var step := rate / 16000.0
	var n := int(src.size() / step)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	var peak := 0.001
	for v in src:
		peak = maxf(peak, absf(v))
	var gain := clampf(0.8 / peak, 1.0, 8.0) # quiet laptop mics: normalise
	for i in n:
		var a := int(i * step)
		var b := mini(src.size(), int((i + 1) * step))
		var s := 0.0
		for j in range(a, b):
			s += src[j]
		s = s / maxf(1.0, b - a) * gain
		pcm.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return wav_bytes(pcm, 16000)


static func wav_bytes(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952) # RIFF
	h.encode_u32(4, 36 + pcm.size())
	h.encode_u32(8, 0x45564157) # WAVE
	h.encode_u32(12, 0x20746d66) # fmt
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)
	h.encode_u16(22, 1)
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164) # data
	h.encode_u32(40, pcm.size())
	h.append_array(pcm)
	return h


## Send WAV bytes to whisper-server; emits heard(text).
func transcribe(wav: PackedByteArray) -> void:
	if not stt_ready:
		heard.emit("")
		return
	transcribing = true
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	var b := "----redboundary7MA4YWxk"
	var body := PackedByteArray()
	var part := func(name: String, value: String) -> void:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [b, name, value]).to_utf8_buffer())
	part.call("response_format", "json")
	part.call("temperature", "0.0")
	part.call("prompt", VOCAB)
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ptt.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % b).to_utf8_buffer())
	body.append_array(wav)
	body.append_array(("\r\n--%s--\r\n" % b).to_utf8_buffer())
	_http.request_completed.connect(_on_transcribed, CONNECT_ONE_SHOT)
	_http.request_raw("http://127.0.0.1:%d/inference" % WHISPER_PORT, ["Content-Type: multipart/form-data; boundary=" + b], HTTPClient.METHOD_POST, body)


func _on_transcribed(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	transcribing = false
	var text := ""
	if code == 200:
		var j = JSON.parse_string(body.get_string_from_utf8())
		if j is Dictionary:
			text = String(j.get("text", "")).strip_edges()
	# whisper's "no speech" outputs
	for junk in ["[BLANK_AUDIO]", "(silence)", "[silence]", "[ Silence ]", "(blank audio)"]:
		text = text.replace(junk, "")
	heard.emit(text.strip_edges())
