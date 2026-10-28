extends SceneTree
## godot --headless --path . --script res://godot/tools/check_scripts.gd : compile every game script.


func _init() -> void:
	var bad := 0
	for f in _scripts("res://godot"):
		var s: GDScript = load(f)
		if s == null or not s.can_instantiate():
			printerr("BAD ", f)
			bad += 1
	print("check_scripts: %d bad" % bad)
	quit(1 if bad else 0)


func _scripts(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	return out
