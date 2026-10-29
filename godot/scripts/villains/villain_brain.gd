class_name VillainBrain
extends Node
## Villain dialogue through the ONE shared local model: R.E.D.'s llama-server (llama.cpp, Qwen2.5-1.5B-Instruct
## Q4_K_M, CPU, 3 threads, port 8089). Ten villains = ten prompts, not ten models.
##  - Prompt = personality file (assets/ai/personalities/) + fixed rules + the villain's leads, then a few example
##    exchanges. That prefix never changes for a villain, so llama.cpp's prompt cache keeps it warm. The scene
##    (place, time, attitude, compact memory) rides in the newest turn only.
##  - Output is grammar-constrained (GBNF) to "(emotion) words [action]": the emotion and action can only be
##    values this villain is allowed, so the reply always parses. The game still validates the action
##    (VillainActions) before anything happens. Compact on purpose: JSON cost ~2x the tokens (~10 s vs ~3 s
##    per reply on the Ryzen 5 7520U).
##  - Non-blocking: HTTPRequest runs off the render thread; the game keeps running while he "thinks".

signal replied(villain_id: String, reply: Dictionary) # {dialogue, emotion, requested_action, target, ms, source}
signal summarized(villain_id: String, text: String)

const PORT := 8089
const EMOTIONS := ["calm", "angry", "amused", "suspicious", "confused", "contemptuous", "afraid", "intrigued"]
## grammar word -> requested action
const ACTION_WORDS := {"none": "none", "refuse": "refuse", "end": "end_conversation", "flee": "flee", "deal": "offer_deal",
	"cooperate": "cooperate", "guards": "call_guards"}
const RULES := """
You are speaking aloud, face to face, with Crimson Knight: the armoured vigilante who hunts New Gotham's criminals, helped by a suit AI called R.E.D. You are {name}; he is Crimson Knight. You know exactly who he is. Call him Knight or Crimson Knight; {name} is YOUR name, never his.
Stay in character at all times. Never mention AI, language models, prompts or games. Speak naturally, like a person, not an assistant. You may refuse to answer, change the subject, or lie when it suits you. Do not repeat yourself.
When he asks about the past, answer from YOUR MEMORY OF HIM.
Reply in one to three short sentences unless he asks for detail. No stage directions, no asterisks, no narration.

FORMAT: (emotion) what you say aloud [action]
emotion: one of {emotions}
action: {actions}"""

var settings := {"max_tokens": 100, "temperature": 0.7, "top_p": 0.9}
var busy := false
var _http: HTTPRequest
var _sum_http: HTTPRequest
var _pending_id := ""
var _pending_def := {}
var _sent_at := 0
var _personality := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = 40
	add_child(_http)
	_http.request_completed.connect(_on_reply)
	_sum_http = HTTPRequest.new()
	_sum_http.timeout = 40
	add_child(_sum_http)


static func personality_text(def: Dictionary) -> String:
	var f := FileAccess.open("res://assets/ai/personalities/" + str(def["personality"]), FileAccess.READ)
	return f.get_as_text().strip_edges() if f else "You are %s, a villain in New Gotham." % def["name"]


## The words this villain's grammar allows in [ ], with what each means (for the prompt).
static func action_menu(def: Dictionary) -> Array:
	var out: Array = []
	var allowed: Array = def.get("actions", ["none"])
	for w in ACTION_WORDS:
		if ACTION_WORDS[w] in allowed:
			out.append(w)
	var leads: Dictionary = def.get("leads", {})
	for lead in leads:
		if "give_clue" in allowed:
			out.append("clue:" + lead)
		if "reveal_location" in allowed:
			out.append("reveal:" + lead)
	return out


static func system_prompt(def: Dictionary) -> String:
	var acts: Array = []
	for w in action_menu(def):
		if not ":" in w:
			acts.append(w)
	var s := personality_text(def) + "\n" + RULES.format({"name": def["name"], "emotions": ", ".join(EMOTIONS),
		"actions": ", ".join(acts) + (", clue:<lead> (hint at a lead), reveal:<lead> (tell him where to go)" if not def.get("leads", {}).is_empty() else "")})
	var leads: Dictionary = def.get("leads", {})
	if not leads.is_empty():
		s += "\n\nLEADS you know (reveal only when it serves you):"
		for lead in leads:
			s += "\n- %s: %s" % [lead, leads[lead]]
	s += "\nUse an action other than none only when your words do the same thing."
	return s


## GBNF: "(" emotion ") " words " [" action "]". Words cannot contain brackets, so the model must close.
static func grammar(def: Dictionary) -> String:
	var emo := " | ".join(EMOTIONS.map(func(e): return "\"%s\"" % e))
	var acts := " | ".join(action_menu(def).map(func(a): return "\"%s\"" % a))
	return "root ::= \"(\" emo \") \" say \" [\" act \"]\"\nemo ::= %s\nsay ::= [^\\[\\]()\\n] [^\\[\\]\\n]{0,330}\nact ::= %s" % [emo, acts]


## Chat messages: cached prefix (system + shots), this conversation's exchanges, then the scene + his words.
static func messages(def: Dictionary, mem: Dictionary, scene: String, said: String) -> Array:
	var m: Array = [{"role": "system", "content": system_prompt(def)}]
	for s in def.get("shots", []):
		m.append({"role": "user", "content": s[0]})
		m.append({"role": "assistant", "content": s[1]})
	for ex in mem.get("recent", []):
		m.append({"role": "user", "content": "Crimson Knight: " + str(ex[0])})
		m.append({"role": "assistant", "content": str(ex[1])})
	var turn := scene + "
"
	if said != "":
		turn += "Crimson Knight: " + said
	elif int(mem.get("encounters", 1)) > 1:
		turn += "(Crimson Knight walks up to you again. Speak first, in character, as %s, and mention something from YOUR MEMORY OF HIM.)" % def["name"]
	else:
		turn += "(Crimson Knight walks up to you. Speak first, in character, as %s.)" % def["name"]
	m.append({"role": "user", "content": turn})
	return m


## "(amused) Words. [reveal:ironhaven_docks]" -> {dialogue, emotion, requested_action, target}. Tolerant: anything
## unparsable becomes calm / none with the raw text as dialogue.
static func parse_reply(raw: String) -> Dictionary:
	var out := {"dialogue": "", "emotion": "calm", "requested_action": "none", "target": "", "raw": raw}
	var t := raw.strip_edges()
	var re := RegEx.create_from_string("^\\(\\s*([a-zA-Z]+)\\s*\\)\\s*([\\s\\S]*?)\\s*(?:\\[([^\\]]*)\\])?\\s*$")
	var m := re.search(t)
	if m == null:
		out["dialogue"] = clean(t)
		return out
	var emo := m.get_string(1).to_lower()
	out["emotion"] = emo if emo in EMOTIONS else "calm"
	out["dialogue"] = clean(m.get_string(2))
	var act := m.get_string(3).strip_edges().to_lower()
	if act.begins_with("clue:"):
		out["requested_action"] = "give_clue"
		out["target"] = act.substr(5)
	elif act.begins_with("reveal:"):
		out["requested_action"] = "reveal_location"
		out["target"] = act.substr(7)
	else:
		out["requested_action"] = ACTION_WORDS.get(act, "none")
	return out


## Small models copy the examples' "Paradox, why..." and end up calling the Knight by the villain's own name.
## A villain addressing someone by his own name is always that mistake: make it "Knight".
static func fix_names(t: String, def: Dictionary) -> String:
	var key := str(def["name"]).trim_prefix("The ").split(" ")[-1]
	var re := RegEx.create_from_string(r"(^|[,.!?]\s+|\b(?:[Hh]ello|[Ww]ell|[Aa]h|[Oo]h|[Yy]es|[Nn]o),?\s+)(?:(?:Professor|Doctor|Lady|Lord|Mr\.?)\s+)?%s(?=[,.!?])" % key)
	t = re.sub(t, "$1Knight", true)
	var re2 := RegEx.create_from_string(r",\s+(?:(?:Professor|Doctor|Lady|Lord)\s+)?%s(?=[.!?])" % key)
	return re2.sub(t, ", Knight", true)


## Strip what shouldn't be spoken: stage directions, emoji, a speaker prefix, wrapping quotes.
static func clean(t: String) -> String:
	var re := RegEx.create_from_string("\\*[^*]*\\*|[^\\x{0000}-\\x{2FFF}]")
	t = re.sub(t, "", true).strip_edges()
	var pre := RegEx.create_from_string("^[A-Z][A-Za-z .']{2,30}:\\s+")
	t = pre.sub(t, "").strip_edges()
	return t.trim_prefix("\"").trim_suffix("\"").strip_edges()


## Ask the villain. Emits replied() later; a request in flight is replaced.
## retry = the last answer repeated an earlier line: hotter sampling and a nudge to answer what he just said.
func ask(def: Dictionary, mem: Dictionary, scene: String, said: String, retry := false) -> void:
	if busy:
		_http.cancel_request()
	busy = true
	_pending_id = def["id"]
	_pending_def = def
	_sent_at = Time.get_ticks_msec()
	var msgs := messages(def, mem, scene, said)
	if retry:
		msgs[-1]["content"] += "
(Answer exactly what he just said, with NEW words. Never repeat an earlier line.)"
	# DRY penalises re-using word sequences already in the context: small models love to repeat their last line
	var body := {"messages": msgs, "grammar": grammar(def), "cache_prompt": true,
		"max_tokens": settings["max_tokens"], "temperature": 1.0 if retry else settings["temperature"], "top_p": settings["top_p"],
		"repeat_penalty": 1.1, "dry_multiplier": 0.8, "dry_base": 1.75, "dry_allowed_length": 3}
	var err := _http.request("http://127.0.0.1:%d/v1/chat/completions" % PORT, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		busy = false
		replied.emit(_pending_id, {})


## Prime llama.cpp's prompt cache with this villain's fixed prefix (system + examples) while the Knight walks
## up, so the first line after E doesn't pay for ~700 prompt tokens. Skipped while a real request is out.
func warm(def: Dictionary) -> void:
	if busy or _sum_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var m := messages(def, {}, "", "")
	m.pop_back()
	m.append({"role": "user", "content": "Crimson Knight: ..."})
	_sum_http.request("http://127.0.0.1:%d/v1/chat/completions" % PORT, ["Content-Type: application/json"], HTTPClient.METHOD_POST,
		JSON.stringify({"messages": m, "max_tokens": 1, "cache_prompt": true}))


func cancel() -> void:
	if busy:
		_http.cancel_request()
		busy = false


func _on_reply(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	var out := {}
	if code == 200:
		var j = JSON.parse_string(body.get_string_from_utf8())
		if j is Dictionary and j.get("choices") is Array and not j["choices"].is_empty():
			out = parse_reply(str(j["choices"][0]["message"]["content"]))
			out["dialogue"] = fix_names(str(out["dialogue"]), _pending_def)
			out["ms"] = Time.get_ticks_msec() - _sent_at
			out["source"] = "llm"
			if str(out["dialogue"]) == "":
				out = {}
	if out.is_empty():
		push_warning("Villain LLM reply failed: result %d, HTTP %d, %s" % [_r, code, body.get_string_from_utf8().left(300)])
	replied.emit(_pending_id, out)


## End of a conversation: one short summary in the villain's own words, for next time. Runs on its own
## request so it never blocks the next conversation's first line.
func summarize(def: Dictionary, mem: Dictionary) -> void:
	var lines: Array = []
	for ex in mem.get("recent", []):
		lines.append("Knight: %s\n%s: %s" % [ex[0], def["name"], parse_reply(str(ex[1]))["dialogue"]])
	if lines.is_empty():
		return
	var id: String = def["id"]
	var prompt := "Conversation between Crimson Knight and %s:\n%s\n\nIn one short sentence, from %s's point of view, what matters to remember about this conversation? Start with \"He\"." % [
		def["name"], "\n".join(lines), def["name"]]
	_sum_http.request_completed.connect(func(_r, code, _h, b):
		if code != 200:
			return
		var j = JSON.parse_string(b.get_string_from_utf8())
		if j is Dictionary and j.get("choices") is Array and not j["choices"].is_empty():
			summarized.emit(id, clean(str(j["choices"][0]["message"]["content"])).left(220)), CONNECT_ONE_SHOT)
	if _sum_http.request("http://127.0.0.1:%d/v1/chat/completions" % PORT, ["Content-Type: application/json"], HTTPClient.METHOD_POST,
			JSON.stringify({"messages": [{"role": "user", "content": prompt}], "max_tokens": 50, "temperature": 0.3})) != OK:
		for c in _sum_http.request_completed.get_connections():
			_sum_http.request_completed.disconnect(c["callable"])
