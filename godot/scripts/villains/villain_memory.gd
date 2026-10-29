class_name VillainMemory
extends RefCounted
## Persistent villain memory (user://villain_memory.json): one compact record per villain, never the full
## transcript. What goes to the model is the summary line from describe(), about 60-120 tokens.
##  - relationship: trust (-1..1), respect (-1..1), hostility (0..1), nudged by what the Knight says (note_player)
##    and how the villain reacted (note_reply)
##  - lists, each capped: notes (what the villain chose to remember / the end-of-talk summary), promises,
##    insults, threats, deals, betrayals, questions he already asked, leads already revealed
##  - recent: the last exchanges of the CURRENT conversation only (cleared when a new one starts)

const CAP := 6
const KEYS := ["notes", "promises", "insults", "threats", "deals", "betrayals", "asked", "revealed", "events"]

var path := "user://villain_memory.json"
var data := {} # villain id -> record


func _init(file := "") -> void:
	if file != "":
		path = file


func load_all() -> void:
	data = {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var j = JSON.parse_string(f.get_as_text())
	if j is Dictionary:
		data = j


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, " "))


## The record for a villain, created from its starting attitude on first use.
func rec(def: Dictionary) -> Dictionary:
	var id: String = def["id"]
	if not data.has(id):
		var a: Dictionary = def.get("attitude", {})
		var r := {"encounters": 0, "talks": 0, "trust": float(a.get("trust", 0.0)), "respect": float(a.get("respect", 0.0)),
			"hostility": float(a.get("hostility", 0.3)), "summary": "", "recent": [], "last_emotion": "calm", "last_met": 0,
			"deal_pending": false, "cooperative": false}
		for k in KEYS:
			r[k] = []
		data[id] = r
	var out: Dictionary = data[id]
	for k in KEYS: # records saved by an older build
		if not out.has(k):
			out[k] = []
	return out


static func push(r: Dictionary, key: String, text: String, cap := CAP) -> void:
	text = text.strip_edges().left(140)
	if text == "":
		return
	var arr: Array = r[key]
	if arr.has(text):
		return
	arr.append(text)
	while arr.size() > cap:
		arr.pop_front()


static func _nudge(r: Dictionary, key: String, d: float) -> void:
	var lo := 0.0 if key == "hostility" else -1.0
	r[key] = clampf(float(r[key]) + d, lo, 1.0)


const INSULTS := ["idiot", "pathetic", "clown", "coward", "freak", "loser", "stupid", "joke", "worm", "lunatic", "insane", "maniac", "nobody", "shut up"]
const THREATS := ["coming with me", "under arrest", "lock you up", "put you away", "stop you", "take you down", "end you", "hurt you",
	"break you", "back to the asylum", "back to grimstone", "you're finished", "last warning", "or else"]
const PRAISE := ["respect", "brilliant", "impressive", "clever", "smart", "admire", "fair point", "you're right", "good point", "thank you", "thanks"]
const PROMISE := ["i promise", "i swear", "you have my word", "i give you my word", "i won't", "i will not", "i'll make sure", "trust me"]
const AGREE := ["deal", "agreed", "fine", "yes", "okay", "ok", "it's a deal", "you have a deal", "i accept"]
const RENEGE := ["i lied", "deal's off", "deal is off", "no deal", "changed my mind", "never had a deal"]


## Whole-word / whole-phrase match ("i promise" must not match "I promised").
static func _has(t: String, w: String) -> bool:
	var i := t.find(w)
	while i >= 0:
		var before := t.substr(i - 1, 1) if i > 0 else " "
		var after := t.substr(i + w.length(), 1)
		if not (before.is_valid_identifier() or before.is_valid_int()) and not (after.is_valid_identifier() or after.is_valid_int()):
			return true
		i = t.find(w, i + 1)
	return false


## Fold one thing the Knight said into the record. Returns the tags it matched (for logs and tests).
static func note_player(r: Dictionary, text: String) -> Array:
	var t := " " + text.to_lower().strip_edges() + " "
	var tags: Array = []
	for w in INSULTS:
		if _has(t, w):
			push(r, "insults", text)
			_nudge(r, "hostility", 0.1)
			_nudge(r, "trust", -0.06)
			tags.append("insult")
			break
	for w in THREATS:
		if _has(t, w):
			push(r, "threats", text)
			_nudge(r, "hostility", 0.06)
			_nudge(r, "respect", 0.02)
			tags.append("threat")
			break
	for w in PRAISE:
		if _has(t, w):
			_nudge(r, "respect", 0.05)
			_nudge(r, "trust", 0.04)
			_nudge(r, "hostility", -0.03)
			tags.append("praise")
			break
	for w in PROMISE:
		if _has(t, w):
			push(r, "promises", text)
			_nudge(r, "trust", 0.05)
			tags.append("promise")
			break
	if r.get("deal_pending", false):
		for w in RENEGE:
			if _has(t, w):
				push(r, "betrayals", "He backed out of a deal: " + text)
				_nudge(r, "trust", -0.3)
				_nudge(r, "hostility", 0.2)
				r["deal_pending"] = false
				tags.append("betrayal")
				break
		if not tags.has("betrayal"):
			for w in AGREE:
				if _has(t, w):
					push(r, "deals", "He accepted a deal: " + text)
					_nudge(r, "trust", 0.12)
					r["deal_pending"] = false
					tags.append("deal")
					break
	if text.strip_edges().ends_with("?"):
		push(r, "asked", text, 4)
		tags.append("question")
	return tags


## Fold the villain's own reaction (validated emotion + action + optional note) into the record.
static func note_reply(r: Dictionary, emotion: String, action: String, remember := "") -> void:
	r["last_emotion"] = emotion
	match emotion:
		"angry":
			_nudge(r, "hostility", 0.04)
		"amused", "intrigued":
			_nudge(r, "hostility", -0.02)
			_nudge(r, "respect", 0.01)
		"afraid":
			_nudge(r, "respect", 0.04)
		"contemptuous":
			_nudge(r, "respect", -0.02)
	if action == "offer_deal":
		r["deal_pending"] = true
	if action == "cooperate":
		r["cooperative"] = true
	if remember != "":
		push(r, "notes", remember)


## Plain-language attitude for the prompt and the conversation panel.
static func attitude(r: Dictionary) -> String:
	var h := float(r["hostility"])
	var tr := float(r["trust"])
	var rs := float(r["respect"])
	var base := "openly hostile" if h > 0.7 else "hostile" if h > 0.45 else "guarded" if h > 0.2 else "relaxed"
	if tr > 0.35:
		base += ", cautiously trusting"
	elif tr < -0.4:
		base += ", deeply distrustful"
	if rs > 0.45:
		base += ", respects him"
	elif rs < -0.2:
		base += ", looks down on him"
	if r.get("cooperative", false):
		base += ", currently cooperating"
	return base


## Compact memory for the model, in his voice's second person: "YOUR MEMORY OF HIM: ...".
static func describe(r: Dictionary) -> String:
	var parts: Array = []
	var n := int(r["encounters"])
	parts.append("You have never spoken before." if n <= 1 else "You have spoken %d time%s before." % [n - 1, "" if n == 2 else "s"])
	for k in [["promises", "He promised"], ["deals", "Deal"], ["betrayals", "Betrayal"], ["insults", "He insulted you"],
			["threats", "He threatened you"], ["asked", "He asked you"], ["revealed", "You already told him about"]]:
		var arr: Array = r[k[0]]
		if not arr.is_empty():
			parts.append("%s: \"%s\"" % [k[1], str(arr[-1]).trim_suffix(".")])
	if str(r["summary"]) != "":
		parts.append("Afterwards you noted: " + str(r["summary"]))
	var notes: Array = r["notes"]
	if not notes.is_empty():
		parts.append("You also remember: " + "; ".join(notes.slice(-3)) + ".")
	var ev: Array = r["events"]
	if not ev.is_empty():
		parts.append("News: " + str(ev[-1]))
	return "YOUR MEMORY OF HIM: " + " ".join(parts)


## A conversation starts: count the encounter, clear the short-term transcript.
static func begin(r: Dictionary) -> void:
	r["encounters"] = int(r["encounters"]) + 1
	r["recent"] = []
	r["last_met"] = int(Time.get_unix_time_from_system())


## Short-term transcript of this conversation (last 3 exchanges go back to the model).
static func add_exchange(r: Dictionary, player: String, reply: String) -> void:
	var arr: Array = r["recent"]
	arr.append([player, reply])
	while arr.size() > 3:
		arr.pop_front()
	r["talks"] = int(r["talks"]) + 1


## World events every villain hears about (a crime stopped, a villain exposed). Kept short.
func broadcast(text: String) -> void:
	for id in data:
		push(data[id], "events", text, 3)
