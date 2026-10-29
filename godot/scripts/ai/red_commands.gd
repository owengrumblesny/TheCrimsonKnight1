class_name RedCommands
extends RefCounted
## R.E.D.'s command parser: turns what the Knight says or types into game actions, deterministically.
## The local LLM is too small to pick actions reliably (it ran "scan" for "lose the cops" in testing), so
## every action goes through here; the LLM only chats. parse() splits "bring the car and give me overdrive"
## into clauses and returns [{do, arg}], or [] when the words are conversation rather than a command.

const VEHICLES := {
	"crx1_interceptor": ["car", "interceptor", "batmobile", "ride", "wheels", "auto", "vehicle", "cr x1", "crx1"],
	"crb1_batcycle": ["bike", "cycle", "motorcycle", "motorbike", "batcycle", "batpod", "cr b1", "crb1"],
	"cra1_specter": ["jet", "plane", "specter", "spectre", "aircraft", "batwing", "flyer", "cr a1", "cra1"],
}
const SUMMON_VERBS := ["summon", "call", "bring", "send", "get me", "i need", "need my", "need the", "need a", "give me", "fetch", "deploy", "pick me up", "come to me", "come get me"]
const EQUIP_VERBS := ["equip", "switch to", "give me", "use", "pull out", "draw", "select", "hand me", "arm", "grab", "ready", "take out"]

## [intent, [phrases]] in priority order: the first intent with a matching phrase wins its clause.
const INTENTS := [
	["stop", ["stop talking", "shut up", "be quiet", "quiet", "silence", "hush", "enough", "stop"]],
	["clear_waypoint", ["clear waypoint", "clear the waypoint", "cancel route", "cancel the route", "remove waypoint", "clear route"]],
	["help", ["what can you do", "help", "commands", "what do you do", "abilities"]],
	["eject", ["eject", "launch the bike", "launch bike", "split off"]],
	["vehicle_mode", ["change mode", "switch mode", "next mode", "transform", "battle mode", "pursuit mode", "flight mode", "vtol"]],
	["overdrive", ["overdrive", "strength", "stronger", "strong", "power up", "powerup", "more power", "super punch", "hit harder", "punch harder", "juice me", "boost my", "damage boost", "rage", "beat these", "can't beat", "cant beat", "too tough", "are tough"]],
	["armor_boost", ["armor", "armour", "protect me", "protection", "toughen", "tank mode", "defense", "defence", "reinforce", "plating"]],
	["shield", ["shield", "bubble", "force field", "forcefield"]],
	["repair", ["heal", "repair", "patch me", "patch up", "fix me", "fix the suit", "medic", "health", "dying", "hurt", "first aid", "low hp"]],
	["cool_heat", ["cops", "police", "heat", "wanted", "lose them", "lose the", "jam", "stars", "get them off", "off my back"]],
	["scan", ["scan", "enemies", "enemy", "how many", "threats", "detect", "where are they", "hostiles", "who's around", "whos around", "anyone around", "detective"]],
	["start_mission", ["start mission", "start the mission", "next mission", "new mission", "give me a mission", "story"]],
	["waypoint_citadel", ["citadel", "home", "base", "the cave", "lair", "hq", "headquarters"]],
	["waypoint_mission", ["mission", "objective", "where do i go", "where should i go", "where to", "what's next", "whats next"]],
	["waypoint_crime", ["crime", "trouble", "action", "bad guys", "robbery", "fight", "criminals", "thugs", "find me", "something to do", "bored", "patrol"]],
	["status", ["status", "how am i", "report", "diagnostic", "check me", "vitals", "how's the suit", "hows the suit"]],
]


static func _norm(text: String) -> String:
	var s := " " + text.to_lower().replace("r.e.d.", "red").replace("r.e.d", "red").replace("’", "'") + " "
	for ch in [".", "!", "?", ":", "\""]:
		s = s.replace(ch, " ")
	for ch in ["-", "_", "/"]:
		s = s.replace(ch, " ")
	for ch in [",", ";"]:
		s = s.replace(ch, " , ")
	while s.contains("  "):
		s = s.replace("  ", " ")
	for p in [" hey red ", " ok red ", " okay red ", " yo red ", " red ", " please ", " can you ", " could you ", " would you "]:
		if s.begins_with(p):
			s = " " + s.substr(p.length())
	if s.begins_with(" , "):
		s = s.substr(2)
	return s


static func _has(s: String, phrase: String) -> bool:
	return s.contains(" " + phrase + " ")


## items: {id: [names...]} for "equip X" (display names, lower case). Returns [{do, arg}].
static func parse(text: String, items := {}) -> Array:
	var out: Array = []
	var s := _norm(text)
	for part in s.replace(" and then ", " , ").replace(" then ", " , ").replace(" and ", " , ").replace(" also ", " , ").split(",", false):
		if part.strip_edges() == "":
			continue
		var act := _clause(" " + part.strip_edges() + " ", items)
		if not act.is_empty() and not out.any(func(o): return o["do"] == act["do"] and o.get("arg", "") == act.get("arg", "")):
			out.append(act)
	return out


static func _clause(c: String, items: Dictionary) -> Dictionary:
	var negated := _has(c, "don't") or _has(c, "dont") or _has(c, "do not") or _has(c, "never")
	# vehicles: a vehicle word with a summon verb, or the vehicle word nearly on its own ("Interceptor!")
	var veh := ""
	for id in VEHICLES:
		for w in VEHICLES[id]:
			if _has(c, w):
				veh = id
				break
		if veh != "":
			break
	var summon := SUMMON_VERBS.any(func(v): return _has(c, v)) or c.split(" ", false).size() <= 3
	if veh != "" and summon and not negated and not _has(c, "mode") and not _has(c, "eject"):
		return {"do": "summon", "arg": veh}
	if negated:
		return {}
	# "equip the batarang" / "give me the carbine"
	if EQUIP_VERBS.any(func(v): return _has(c, v)) or c.split(" ", false).size() <= 2:
		var best := ""
		var best_len := 0
		for id in items:
			for n in items[id]:
				if n.length() > best_len and _has(c, n):
					best = id
					best_len = n.length()
		if best != "":
			return {"do": "equip", "arg": best}
	for it in INTENTS:
		for p in it[1]:
			if _has(c, p):
				return {"do": it[0]}
	return {}


## Display-name lookup for parse(): every belt item under its full name, its last word and its id words.
static func item_names(inventory: Inventory) -> Dictionary:
	var out := {}
	for id in inventory.hotbar:
		var names: Array = []
		var dn := String(inventory.def(id).get("displayName", id)).to_lower()
		names.append(dn)
		var words := dn.split(" ", false)
		if words.size() > 1 and words[-1].length() > 3:
			names.append(words[-1])
		for w in String(id).split("_", false):
			if w.length() > 3 and not w in ["energy", "first", "photo", "power"]:
				names.append(w)
		out[id] = names
	return out
