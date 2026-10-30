class_name Updater
extends Node
## Auto-update from the GitHub repo (config/version.json names it):
##  - game: on start, asks the GitHub API for the latest Release. If its tag (v1.2.3) is newer than this build,
##    `update_available` fires. update_now() downloads the release's installer (CrimsonKnight-Setup.exe on
##    Windows, CrimsonKnight-linux.tar.gz on Linux), runs it silently over this install and quits; the installer
##    relaunches the game.
##  - R.E.D. AI dependencies: fetches the live config/ai_manifest.json from the repo's main branch. If its
##    "version" is newer than what's installed, `ai_update_available` fires; the RedInstaller then uses that
##    manifest (new URLs) and re-downloads only what changed.
## Nothing runs in scripted test runs. All requests are plain HTTPS GETs to github.com / raw.githubusercontent.com.

signal update_available(version: String, notes: String, size_mb: int)
signal ai_update_available(version: int)
signal progress(text: String, fraction: float)
signal failed(message: String)

var current := "0.0.0"
var repo := ""
var latest := {} # {version, url, size, notes}
var ai_manifest := {}
var busy := false
var _http: HTTPRequest
var _dl: HTTPRequest


func _ready() -> void:
	var v = CKData.json("version")
	if v is Dictionary:
		current = String(v.get("version", current))
		repo = String(v.get("repo", ""))
	_http = HTTPRequest.new()
	_http.timeout = 15
	add_child(_http)
	_dl = HTTPRequest.new()
	_dl.use_threads = true
	_dl.download_chunk_size = 1 << 20
	add_child(_dl)


func _process(_dt: float) -> void:
	if busy and _dl.get_http_client_status() == HTTPClient.STATUS_BODY and _dl.get_body_size() > 0:
		progress.emit("Downloading update  %d / %d MB" % [_dl.get_downloaded_bytes() >> 20, _dl.get_body_size() >> 20],
			float(_dl.get_downloaded_bytes()) / _dl.get_body_size())


## "1.10.2" > "1.9.9"
static func newer(a: String, b: String) -> bool:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func check() -> void:
	if repo == "":
		return
	var h := ["User-Agent: CrimsonKnight-Updater", "Accept: application/vnd.github+json"]
	_http.request("https://api.github.com/repos/%s/releases/latest" % repo, h)
	var res: Array = await _http.request_completed
	if res[0] == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200:
		var j = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
		if j is Dictionary:
			var tag := String(j.get("tag_name", ""))
			var want := "CrimsonKnight-Setup.exe" if OS.get_name() == "Windows" else "CrimsonKnight-linux.tar.gz"
			for a in j.get("assets", []):
				if String(a.get("name", "")) == want and newer(tag, current):
					latest = {"version": tag.trim_prefix("v"), "url": a["browser_download_url"], "size": int(a.get("size", 0)),
						"notes": String(j.get("body", "")).left(400)}
					update_available.emit(latest["version"], latest["notes"], int(latest["size"]) >> 20)
	# AI dependency manifest (live copy on main)
	_http.request("https://raw.githubusercontent.com/%s/main/config/ai_manifest.json" % repo, ["User-Agent: CrimsonKnight-Updater"])
	var res2: Array = await _http.request_completed
	if res2[0] == HTTPRequest.RESULT_SUCCESS and int(res2[1]) == 200:
		var m = JSON.parse_string((res2[3] as PackedByteArray).get_string_from_utf8())
		if m is Dictionary and m.has("version"):
			ai_manifest = m
			var dir := RedAI.find_ai_dir()
			if RedInstaller.complete(dir) and int(m["version"]) > RedInstaller.installed_version(dir):
				ai_update_available.emit(int(m["version"]))


## Download the new installer and run it over this install, then quit (it relaunches the game).
func update_now() -> void:
	if latest.is_empty() or busy:
		return
	busy = true
	var dir := OS.get_user_data_dir().path_join("update")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(String(latest["url"]).get_file())
	_dl.download_file = path
	_dl.request(latest["url"], ["User-Agent: CrimsonKnight-Updater"])
	var res: Array = await _dl.request_completed
	busy = false
	if res[0] != HTTPRequest.RESULT_SUCCESS or int(res[1]) >= 400:
		failed.emit("Update download failed. Check your connection and try again.")
		return
	progress.emit("Installing update…", 1.0)
	if OS.get_name() == "Windows":
		# Inno Setup: silent upgrade in place (same AppId), close the running game, relaunch it afterwards
		OS.create_process(path, ["/SILENT", "/SUPPRESSMSGBOXES", "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS", "/NORESTART"])
	else:
		var here := OS.get_executable_path().get_base_dir()
		# the package has one top-level CrimsonKnight/ folder: unpack its contents over this install
		if OS.execute("tar", ["-xzf", path, "-C", here, "--strip-components=1"]) != 0:
			failed.emit("Couldn't unpack the update.")
			return
		OS.create_process(OS.get_executable_path(), [])
	get_tree().quit()
