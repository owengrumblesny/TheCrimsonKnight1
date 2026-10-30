class_name RedInstaller
extends Node
## One-click download of R.E.D.'s local AI (for players who've never installed anything): llama.cpp, whisper.cpp,
## Piper and the three models (~1.3 GB), from their official GitHub / Hugging Face releases, into the game's
## user folder (user://ai). Archives are unpacked (zip in-engine; tar.gz with the system `tar` on Linux), each
## server binary is found wherever it landed and its folder moved to the layout R.E.D. expects:
## llama/llama-server, whisper/Release/whisper-server, piper/piper/piper, models/*. Started from
## Settings > R.E.D. AI. Progress via `progress`; `finished(ok, message)` at the end.

signal progress(text: String, fraction: float)
signal finished(ok: bool, message: String)

const MODELS := [
	["models/qwen2.5-1.5b-instruct-q4_k_m.gguf", "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf", 1117320736],
	["models/ggml-base.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin", 147964211],
	["models/en_US-amy-low.onnx", "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/low/en_US-amy-low.onnx", 63104526],
	["models/en_US-amy-low.onnx.json", "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/low/en_US-amy-low.onnx.json", 4164],
]
## [label, url, binary name (no .exe), folder it must end up in (relative to ai/)]
const WINDOWS := [
	["LLM server", "https://github.com/ggml-org/llama.cpp/releases/download/b11982/llama-b11982-bin-win-cpu-x64.zip", "llama-server", "llama"],
	["speech recognition", "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-bin-x64.zip", "whisper-server", "whisper/Release"],
	["voice", "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip", "piper", "piper/piper"],
]
const LINUX := [
	["LLM server", "https://github.com/ggml-org/llama.cpp/releases/download/b11982/llama-b11982-bin-ubuntu-x64.tar.gz", "llama-server", "llama"],
	["speech recognition", "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-bin-ubuntu-x64.tar.gz", "whisper-server", "whisper/Release"],
	["voice", "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz", "piper", "piper/piper"],
]
const TOTAL_MB := 1300

var busy := false
## the download list: config/ai_manifest.json, replaced by the live copy from GitHub when the updater fetched one
var manifest: Dictionary = CKData.json("ai_manifest") if CKData.json("ai_manifest") is Dictionary else {}
## re-download everything (dependency update)
var _force := false
var _http: HTTPRequest
var _dir := ""


static func target_dir() -> String:
	return OS.get_user_data_dir().path_join("ai")


## AI dependency version recorded by the last successful install in `dir` (0 = unknown / none).
static func installed_version(dir: String) -> int:
	var j = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("version.json"))) if FileAccess.file_exists(dir.path_join("version.json")) else null
	return int(j.get("version", 0)) if j is Dictionary else 0


## True when every engine and model R.E.D. needs is present in `dir`.
static func complete(dir: String) -> bool:
	if dir == "":
		return false
	var ext := ".exe" if OS.get_name() == "Windows" else ""
	for f in ["llama/llama-server" + ext, "whisper/Release/whisper-server" + ext, "piper/piper/piper" + ext]:
		if not FileAccess.file_exists(dir.path_join(f)):
			return false
	for m in MODELS:
		if not FileAccess.file_exists(dir.path_join(m[0])):
			return false
	return true


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.download_chunk_size = 1 << 20
	add_child(_http)


func _process(_dt: float) -> void:
	if busy and _http.get_http_client_status() == HTTPClient.STATUS_BODY:
		var total := _http.get_body_size()
		var got := _http.get_downloaded_bytes()
		if total > 0:
			progress.emit("%s  %d / %d MB" % [_label, got >> 20, total >> 20], float(got) / total)


var _label := ""


func start(force := false) -> void:
	if busy:
		return
	_force = force
	if not OS.get_name() in ["Windows", "Linux"]:
		finished.emit(false, "Automatic install supports Windows and Linux only")
		return
	busy = true
	_dir = target_dir()
	DirAccess.make_dir_recursive_absolute(_dir.path_join("models"))
	var f := FileAccess.open(_dir.path_join(".gdignore"), FileAccess.WRITE)
	if f:
		f.close()
	_run.call_deferred()


func _download(url: String, path: String) -> bool:
	_http.download_file = path
	if _http.request(url) != OK:
		return false
	var res: Array = await _http.request_completed
	return res[0] == HTTPRequest.RESULT_SUCCESS and int(res[1]) < 400


func _run() -> void:
	var engines: Array = manifest.get("windows" if OS.get_name() == "Windows" else "linux", WINDOWS if OS.get_name() == "Windows" else LINUX)
	var models: Array = manifest.get("models", MODELS)
	var ext := ".exe" if OS.get_name() == "Windows" else ""
	var steps := engines.size() + models.size()
	var n := 0
	for e in engines:
		n += 1
		if not _force and FileAccess.file_exists(_dir.path_join(e[3]).path_join(e[2] + ext)):
			continue
		_label = "R.E.D. %s (%d/%d)" % [e[0], n, steps]
		var tmp := _dir.path_join("_dl_" + String(e[2]))
		_rm(tmp)
		DirAccess.make_dir_recursive_absolute(tmp)
		var arc := tmp.path_join("pkg.zip" if String(e[1]).ends_with(".zip") else "pkg.tar.gz")
		if not await _download(e[1], arc):
			return _fail("Couldn't download the %s. Check your internet connection and try again." % e[0])
		progress.emit("Unpacking %s…" % e[0], 1.0)
		await get_tree().process_frame
		if not _unpack(arc, tmp):
			return _fail("Couldn't unpack the %s." % e[0])
		DirAccess.remove_absolute(arc)
		var bin := _find(tmp, String(e[2]) + ext)
		if bin == "":
			return _fail("The %s download didn't contain %s." % [e[0], e[2]])
		var dest := _dir.path_join(e[3])
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		_rm(dest)
		if DirAccess.rename_absolute(bin.get_base_dir(), dest) != OK:
			return _fail("Couldn't move the %s into place." % e[0])
		if OS.get_name() == "Linux":
			OS.execute("chmod", ["-R", "u+x", dest])
		_rm(tmp)
	var had: Dictionary = {}
	var vj = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join("version.json"))) if FileAccess.file_exists(_dir.path_join("version.json")) else null
	if vj is Dictionary:
		had = vj.get("urls", {})
	for m in models:
		n += 1
		var path := _dir.path_join(m[0])
		# keep a model that's complete and still the same download (only changed models are fetched again)
		if _size(path) >= int(m[2]) * 0.99 and (not _force or had.get(m[0], m[1]) == m[1]):
			continue
		_label = "R.E.D. %s (%d/%d)" % [String(m[0]).get_file(), n, steps]
		if not await _download(m[1], path + ".part"):
			return _fail("Couldn't download %s." % String(m[0]).get_file())
		DirAccess.remove_absolute(path)
		DirAccess.rename_absolute(path + ".part", path)
	var urls := {}
	for m in models:
		urls[m[0]] = m[1]
	var vf := FileAccess.open(_dir.path_join("version.json"), FileAccess.WRITE)
	if vf:
		vf.store_string(JSON.stringify({"version": int(manifest.get("version", 1)), "urls": urls}))
		vf.close()
	busy = false
	progress.emit("R.E.D. AI installed", 1.0)
	finished.emit(true, "R.E.D.'s brain, ears and voice are installed.")


func _fail(msg: String) -> void:
	busy = false
	finished.emit(false, msg)


static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else 0


func _unpack(arc: String, into: String) -> bool:
	if arc.ends_with(".zip"):
		var z := ZIPReader.new()
		if z.open(arc) != OK:
			return false
		for name in z.get_files():
			var out := into.path_join(name)
			if name.ends_with("/"):
				DirAccess.make_dir_recursive_absolute(out)
				continue
			DirAccess.make_dir_recursive_absolute(out.get_base_dir())
			var f := FileAccess.open(out, FileAccess.WRITE)
			if f == null:
				z.close()
				return false
			f.store_buffer(z.read_file(name))
			f.close()
		z.close()
		return true
	return OS.execute("tar", ["-xzf", arc, "-C", into]) == 0


## Path of the first file named `file` under `dir` (recursive), or "".
func _find(dir: String, file: String) -> String:
	if FileAccess.file_exists(dir.path_join(file)):
		return dir.path_join(file)
	for sub in DirAccess.get_directories_at(dir):
		var r := _find(dir.path_join(sub), file)
		if r != "":
			return r
	return ""


func _rm(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_rm(path.path_join(d))
	DirAccess.remove_absolute(path)
