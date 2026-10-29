class_name CKData
## Read-only access to the shared game data in res://config (the same JSON the web build uses).

static var _json := {}
static var _by_file := {}
static var _by_id := {}


## Parsed config/<name>.json, cached.
static func json(name: String) -> Variant:
	if not _json.has(name):
		var f := FileAccess.open("res://config/%s.json" % name, FileAccess.READ)
		_json[name] = JSON.parse_string(f.get_as_text()) if f else null
	return _json[name]


## Parsed godot/data/<name>.json (UI data exported from the web build, see godot/tools/export_web_data.sh).
static func data(name: String) -> Variant:
	var key := "data/" + name
	if not _json.has(key):
		var f := FileAccess.open("res://godot/data/%s.json" % name, FileAccess.READ)
		_json[key] = JSON.parse_string(f.get_as_text()) if f else null
	return _json[key]


static func _index() -> void:
	if not _by_id.is_empty():
		return
	for a in json("asset_manifest")["assets"]:
		_by_id[a["id"]] = a
		_by_file[String(a["file"]).to_lower()] = a


## Manifest entry by asset id (e.g. "kit_apartment"); empty when unknown.
static func asset(id: String) -> Dictionary:
	_index()
	return _by_id.get(id, {})


## Manifest entry by repo-relative file path (e.g. "assets/models/kit/kit_apartment.glb"), case-insensitive:
## a few files on disk differ in case from the manifest (CRX1_interceptor.glb).
static func asset_by_file(rel_path: String) -> Dictionary:
	_index()
	return _by_file.get(rel_path.to_lower(), {})


## res:// path of an asset's model, with the on-disk spelling (exports are case-sensitive).
static func model_path(id: String) -> String:
	var a := asset(id)
	return _disk_case("res://" + a["file"]) if a else ""


static var _dir_files := {}


static func _disk_case(path: String) -> String:
	var dir := path.get_base_dir()
	if not _dir_files.has(dir):
		var m := {}
		for f in DirAccess.get_files_at(dir):
			# exported builds list "x.glb.import" / "x.png.remap" rather than the source file
			var src: String = f.trim_suffix(".import").trim_suffix(".remap")
			m[src.to_lower()] = src
		_dir_files[dir] = m
	return dir + "/" + _dir_files[dir].get(path.get_file().to_lower(), path.get_file())


## Texture entry ("concrete", "wet_asphalt", ...) from the manifest's textures list.
static func texture_path(id: String) -> String:
	for t in json("asset_manifest")["textures"]:
		if t["id"] == id:
			return "res://" + t["file"]
	return ""


## Board image path by config/image_catalog.json id (e.g. "world/c_downtown_wide").
static func board_image_path(id: String) -> String:
	for i in json("image_catalog")["images"]:
		if i["id"] == id:
			return "res://" + i["file"]
	return ""


## CR-X9 clip metadata by name (loop, refSpeed, duration).
static func hero_clip(name: String) -> Dictionary:
	for c in json("crx9_clips")["clips"]:
		if c["name"] == name:
			return c
	return {}
