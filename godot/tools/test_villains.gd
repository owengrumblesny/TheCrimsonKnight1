extends SceneTree
## Headless villain-system tests: godot --headless --path . --script res://godot/tools/test_villains.gd
## Data links (20 locations, 10 villains, personalities, schedules, leads), reply parsing, the action
## validator, memory updates and the persistence round trip, grammar contents and the ambience synth.

var fails := 0
var passes := 0


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		printerr("FAIL ", what)


func _init() -> void:
	var locs: Array = CKData.data("locations")["locations"]
	var loc_ids: Array = locs.map(func(l): return l["id"])
	check(locs.size() == 20, "20 locations (got %d)" % locs.size())
	for l in locs:
		var p := Vector2(l["pos"][0], l["pos"][1])
		var outside: bool = absf(p.x) > 440.0 or absf(p.y) > 440.0 or l["id"] == "red_citadel"
		check(outside and absf(p.x) < 650 and absf(p.y) < 650, "%s sits in the belt on the world slab" % l["id"])
		check(Landmarks.new().has_method("_build_" + str(l["style"])) or l["style"] == "citadel", "builder for style " + str(l["style"]))
	var vs: Array = CKData.data("villains")["villains"]
	check(vs.size() == 10, "10 villains (got %d)" % vs.size())
	var speakers := {}
	for v in vs:
		check(v["home"] in loc_ids, "%s home exists" % v["id"])
		check(FileAccess.file_exists("res://assets/ai/personalities/" + str(v["personality"])), "%s personality file" % v["id"])
		check(VillainBrain.personality_text(v).begins_with("You are " + str(v["name"])), "%s personality names him/her" % v["id"])
		for lead in v["leads"]:
			check(lead in loc_ids, "%s lead %s is a real place" % [v["id"], lead])
		for s in v["schedule"]:
			check(s[2] in loc_ids, "%s schedule place %s" % [v["id"], s[2]])
		var covered := 0
		for h in 24:
			if VillainActions.scheduled(v, h + 0.5)[1] != "waiting":
				covered += 1
		check(covered == 24, "%s schedule covers the whole day (%d h)" % [v["id"], covered])
		for a in v["actions"]:
			check(a in VillainActions.ALL, "%s action %s is in the allowed list" % [v["id"], a])
		for sh in v["shots"]:
			var pr := VillainBrain.parse_reply(sh[1])
			check(pr["dialogue"] != "" and pr["emotion"] in VillainBrain.EMOTIONS, "%s example parses" % v["id"])
		speakers[int(v["voice"]["speaker"])] = true
		var g := VillainBrain.grammar(v)
		check(g.contains("root ::=") and g.contains("\"none\""), "%s grammar" % v["id"])
		for lead in v["leads"]:
			if "reveal_location" in v["actions"]:
				check(g.contains("reveal:" + lead), "%s grammar offers reveal:%s" % [v["id"], lead])
	check(speakers.size() == 10, "ten distinct voices (%d)" % speakers.size())

	# reply parsing
	var r := VillainBrain.parse_reply("(amused) An arrest without a warrant? How delightfully consistent. [refuse]")
	check(r["emotion"] == "amused" and r["requested_action"] == "refuse" and r["dialogue"].begins_with("An arrest"), "parse a full reply")
	r = VillainBrain.parse_reply("(intrigued) Try the docks. [reveal:ironhaven_docks]")
	check(r["requested_action"] == "reveal_location" and r["target"] == "ironhaven_docks", "parse a reveal")
	r = VillainBrain.parse_reply("(furious) Hm. [clue:city_hall]")
	check(r["emotion"] == "calm" and r["requested_action"] == "give_clue", "unknown emotion -> calm")
	r = VillainBrain.parse_reply("Professor Paradox: *smiles* Just words.")
	check(r["dialogue"] == "Just words." and r["requested_action"] == "none", "untagged text survives, cleaned")

	check(VillainBrain.fix_names("Paradox, why are you so determined?", vs[0]) == "Knight, why are you so determined?", "own name as address -> Knight (start)")
	check(VillainBrain.fix_names("Ah, Paradox. What brings you here?", vs[0]) == "Ah, Knight. What brings you here?", "own name as address -> Knight (after Ah)")
	check(VillainBrain.fix_names("The Shattered Crown, Paradox.", vs[0]) == "The Shattered Crown, Knight.", "own name as address -> Knight (end)")
	check(VillainBrain.fix_names("A paradox, Knight, is a gift.", vs[0]) == "A paradox, Knight, is a gift.", "a lowercase paradox is left alone")

	# validation
	var paradox: Dictionary = vs.filter(func(v): return v["id"] == "professor_paradox")[0]
	var harl: Dictionary = vs.filter(func(v): return v["id"] == "pale_harlequin")[0]
	var world := {"underground": false, "enemies_near": 0, "locations": loc_ids, "hour": 23.0}
	var mem := VillainMemory.new("user://test_villain_memory.json")
	var pm := mem.rec(paradox)
	var reveal := {"requested_action": "reveal_location", "target": "shattered_crown_museum"}
	check(not VillainActions.validate(reveal, paradox, pm, world)["ok"], "no reveal at the starting trust")
	pm["trust"] = 0.3
	check(VillainActions.validate(reveal, paradox, pm, world)["ok"], "reveal once trust is earned")
	check(not VillainActions.validate({"requested_action": "reveal_location", "target": "ironhaven_docks"}, paradox, pm, world)["ok"], "can't reveal what he doesn't know")
	check(not VillainActions.validate({"requested_action": "call_guards"}, paradox, pm, world)["ok"], "Paradox has no guards to call")
	check(VillainActions.validate({"requested_action": "flee"}, paradox, pm, world)["ok"], "Paradox can flee (two places)")
	check(VillainActions.validate({"requested_action": "rm -rf"}, paradox, pm, world)["action"] == "none", "garbage action -> none")
	var hm := mem.rec(harl)
	var lie := VillainActions.validate({"requested_action": "reveal_location", "target": "nightfall_subway"}, harl, hm, world)
	check(lie["ok"] and lie["misleading"], "the Harlequin's unearned reveal is a false lead")
	var sov: Dictionary = vs.filter(func(v): return v["id"] == "iron_sovereign")[0]
	var sm := mem.rec(sov)
	check(VillainActions.validate({"requested_action": "call_guards"}, sov, sm, world)["ok"], "the Sovereign can call guards when hostile")
	check(not VillainActions.validate({"requested_action": "call_guards"}, sov, sm, {"underground": true, "locations": loc_ids})["ok"], "no guards underground")

	# memory
	var before := float(pm["hostility"])
	check("insult" in VillainMemory.note_player(pm, "You're a pathetic clown, Paradox."), "insult detected")
	check(float(pm["hostility"]) > before and not (pm["insults"] as Array).is_empty(), "insult raises hostility and is remembered")
	check("promise" in VillainMemory.note_player(pm, "I promise I'll keep the students safe."), "promise detected")
	check("question" in VillainMemory.note_player(pm, "Is it ever right to break the law?"), "question remembered")
	check(not "promise" in VillainMemory.note_player(pm, "Do you remember what I promised?"), "'I promised' is not a new promise")
	check(not "threat" in VillainMemory.note_player(pm, "Is it right to break the law?"), "'break the law' is not a threat")
	VillainMemory.note_reply(pm, "amused", "offer_deal", "")
	check(pm["deal_pending"], "deal pending after an offer")
	check("deal" in VillainMemory.note_player(pm, "Deal."), "deal accepted")
	VillainMemory.note_reply(pm, "calm", "offer_deal", "")
	check("betrayal" in VillainMemory.note_player(pm, "I lied. Deal's off."), "reneging is a betrayal")
	VillainMemory.begin(pm)
	for i in 5:
		VillainMemory.add_exchange(pm, "q%d" % i, "(calm) a%d [none]" % i)
	check((pm["recent"] as Array).size() == 3, "short-term transcript keeps 3 exchanges")
	pm["summary"] = "He solved my ethical dilemma."
	var desc := VillainMemory.describe(pm)
	check(desc.contains("solved my ethical dilemma") and desc.contains("He promised"), "describe() carries summary and promise")
	check(desc.length() < 900, "memory summary stays compact (%d chars)" % desc.length())
	mem.save()
	var mem2 := VillainMemory.new("user://test_villain_memory.json")
	mem2.load_all()
	var pm2 := mem2.rec(paradox)
	check(str(pm2["summary"]) == "He solved my ethical dilemma." and int(pm2["encounters"]) == 1, "memory survives a restart")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_villain_memory.json"))

	# prompt assembly
	var msgs := VillainBrain.messages(paradox, pm2, "Location: Northbridge", "Why?")
	check(msgs[0]["role"] == "system" and str(msgs[0]["content"]).contains("Crimson Knight") and str(msgs[0]["content"]).contains("Professor Paradox"), "system prompt: who is speaking to whom")
	check(str(msgs[-1]["content"]).ends_with("Crimson Knight: Why?") and str(msgs[-1]["content"]).contains("Northbridge"), "scene rides in the newest turn")

	# ambience synth
	for rec in ["asylum", "casino", "pier", "cathedral"]:
		var w := Landmarks.ambience_loop(rec)
		check(w.data.size() == 6 * Landmarks.AMB_RATE * 2 and w.loop_mode == AudioStreamWAV.LOOP_FORWARD, "ambience loop " + rec)
	print("test_villains: %d passed, %d failed" % [passes, fails])
	quit(1 if fails else 0)
