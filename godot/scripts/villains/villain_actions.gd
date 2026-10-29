class_name VillainActions
extends RefCounted
## The model never runs game code. It may only REQUEST one of these, and validate() checks the request against
## the villain's permissions (villains.json "actions"), what he actually knows ("leads"), the relationship
## (VillainMemory) and the world state before VillainSystem applies it. A refused request becomes "none"
## (the line is still spoken; nothing happens in the world).

const ALL := ["none", "reveal_location", "give_clue", "refuse", "offer_deal", "cooperate", "end_conversation", "flee", "call_guards"]


## world: {underground: bool, enemies_near: int, locations: Array of ids, hour: float}
## Returns {ok, action, target, reason, misleading}.
static func validate(req: Dictionary, def: Dictionary, mem: Dictionary, world: Dictionary) -> Dictionary:
	var act := str(req.get("requested_action", "none"))
	var target := str(req.get("target", ""))
	var res := {"ok": true, "action": act, "target": target, "reason": "", "misleading": false}
	if act == "none":
		return res
	if not act in ALL:
		return _deny(res, "unknown action")
	if not act in def.get("actions", []):
		return _deny(res, "%s may not %s" % [def["name"], act])
	var leads: Dictionary = def.get("leads", {})
	var trust := float(mem.get("trust", 0.0))
	var respect := float(mem.get("respect", 0.0))
	var hostility := float(mem.get("hostility", 0.0))
	match act:
		"reveal_location":
			if not leads.has(target):
				return _deny(res, "does not know about " + target)
			if target in mem.get("revealed", []):
				return _deny(res, "already revealed")
			if not target in world.get("locations", []):
				return _deny(res, "no such place")
			# earned: some trust, or real respect, or a deal, or he is cooperating. A misleader (the Harlequin)
			# may "reveal" without any of that, but then it is a false lead.
			var earned: bool = trust >= 0.15 or respect >= 0.5 or not mem.get("deals", []).is_empty() or mem.get("cooperative", false)
			if not earned:
				if def.get("misleads", false):
					res["misleading"] = true
					return res
				return _deny(res, "not trusted enough to reveal (trust %.2f, respect %.2f)" % [trust, respect])
		"give_clue":
			if not leads.has(target):
				return _deny(res, "does not know about " + target)
			if trust < -0.6 and hostility > 0.8:
				return _deny(res, "too hostile to give anything away")
		"cooperate":
			if trust < 0.3:
				return _deny(res, "trust too low to cooperate (%.2f)" % trust)
		"call_guards":
			if world.get("underground", false):
				return _deny(res, "no guards underground")
			if hostility < 0.6:
				return _deny(res, "not hostile enough to call guards (%.2f)" % hostility)
			if int(world.get("enemies_near", 0)) >= 4:
				return _deny(res, "already enough enemies here")
		"flee":
			var places := {}
			for s in def.get("schedule", []):
				places[s[2]] = true
			if places.size() < 2:
				return _deny(res, "nowhere else to go")
	return res


static func _deny(res: Dictionary, why: String) -> Dictionary:
	res["ok"] = false
	res["reason"] = why
	res["action"] = "none"
	return res


## Where the schedule puts a villain at `hour` (0..24, wraps midnight): [location id, activity].
static func scheduled(def: Dictionary, hour: float) -> Array:
	for s in def.get("schedule", []):
		var a := float(s[0])
		var b := float(s[1])
		var inside := (hour >= a and hour < b) if a < b else (hour >= a or hour < b)
		if inside:
			return [s[2], s[3]]
	return [def["home"], "waiting"]
