class_name SaveService
extends RefCounted
## Versioned save/load (port of SaveService in ui/uiState.ts). Same JSON shape as the web build's
## localStorage entries, stored in user://. Settings persist separately so they survive "New Sandbox".

const SAVE_VERSION := 1
const SAVE_PATH := "user://crimson-knight.save.json"
const SETTINGS_PATH := "user://crimson-knight.settings.json"
const DEFAULT_SETTINGS := {
	"uiScale": 1.0, "hudVisible": true, "reduceMotion": false, "quality": "high",
	"volumes": {"master": 0.8, "music": 0.6, "ambience": 0.6, "sfx": 0.8, "vehicles": 0.8, "ui": 0.6}, "muted": false,
	"mouseSensitivity": 1.0, "invertY": false, "aimAssist": true, "controlHints": true,
	"redVoice": true, "redListen": true, "redBrain": true, "redChatter": true, "dayNight": true, "graphics": {},
}


static func _read(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else null


static func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, " "))


## {settings, bindings, fresh}: fresh = first launch (no settings file yet).
func read_settings() -> Dictionary:
	var raw = _read(SETTINGS_PATH)
	var s: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	var b := {}
	if raw is Dictionary:
		var saved: Dictionary = raw.get("settings", {})
		for k in s:
			if saved.has(k) and typeof(saved[k]) == typeof(s[k]):
				s[k] = saved[k]
		if raw.get("bindings") is Dictionary:
			b = raw["bindings"]
	return {"settings": s, "bindings": b, "fresh": not raw is Dictionary}


func write_settings(settings: Dictionary, bindings: Dictionary) -> void:
	_write(SETTINGS_PATH, {"settings": settings, "bindings": bindings})


## Migrates older versions forward; null for missing or corrupt saves.
func read():
	var raw = _read(SAVE_PATH)
	if not raw is Dictionary or not raw.get("inventory") is Dictionary:
		return null
	if int(raw.get("version", 0)) > SAVE_VERSION:
		return null
	return raw


func write(data: Dictionary) -> void:
	data["version"] = SAVE_VERSION
	data["savedAt"] = Time.get_datetime_string_from_system(true) + "Z"
	_write(SAVE_PATH, data)


func clear() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
