class_name Director
extends Node3D
## Open-world loop (Godot port): enemies, heat, street crimes, missions, credits and rank.
##  - Heat (0-5 stars): rises when fighting (each knockdown, each fight started, gunfire), and while it is up
##    reinforcement squads spawn out of sight and converge on the Knight. It cools one star per 10 s once no
##    enemy has seen the Knight for 12 s.
##  - Street crimes: every 50-80 s a crime (mugging, robbery, gang standoff, merc deal) starts on a street
##    80-300 m away, with a marker; clearing it pays credits. Unanswered crimes expire after 3 minutes.
##  - Missions (godot/data/missions.json): a story chain with objectives on the HUD; one active at a time.
##  - Credits buy nothing yet (sandbox); they set the Knight's rank. Saved with the game.

signal notify(text: String, icon: String, kind: String)
signal sound_event(id: String)
signal player_hurt(amount: float, from: Vector3)

const RANKS := [[0, "Rookie Vigilante"], [500, "Street Guardian"], [1500, "Night Hunter"], [3500, "Crimson Knight"], [7000, "Legend of New Gotham"]]

var player: Player
var effects: Effects
var vitals: Vitals
var drive: DriveController
var underground_fn: Callable
var enemies: Array = []
var heat := 0.0
var credits := 0
var crimes: Array = [] # {kind, pos, enemies, until, label}
var mission := {} # active mission def + progress
var mission_index := 0
var missions: Array = []
var objective := "" # HUD objective line
var markers: Array = [] # [{pos, kind: crime|mission|waypoint, label}]
## player-set waypoint from the map (null = none); cleared on arrival
var waypoint = null
## hologram decoy (Equipment): enemies within 30 m target it until decoy_until
var decoy: Node3D
var decoy_until := 0
var evidence := 0
var melee: Melee
## incoming damage multiplier (R.E.D. armor boost sets 0.5 for a while)
var armor_mult := 1.0
## melee attack tokens: at most MAX_ATTACKERS enemies wind up / strike at once, the rest circle
const MAX_ATTACKERS := 2
var _tokens: Array = []
var _crime_t := 25.0
var _reinforce_t := 0.0
var _cool_t := 0.0
var _smoke: Array = [] # {pos, until}
var _tracers: Array = []
var _checkpoint_ring: MeshInstance3D
var _mission_t := 0.0
var _spawn_ids := ["npc_criminal_thug", "npc_mercenary", "npc_enforcer", "npc_riot_trooper", "npc_stealth_operative", "npc_security_robot"]


func _ready() -> void:
	name = "Director"
	missions = CKData.data("missions")["missions"]


func rank() -> String:
	var r: String = RANKS[0][1]
	for e in RANKS:
		if credits >= e[0]:
			r = e[1]
	return r


func stars() -> int:
	return clampi(ceili(heat - 0.001), 0, 5)


# ---------------- services used by Enemy ----------------
func take_token(e: Node) -> bool:
	_tokens = _tokens.filter(func(x): return is_instance_valid(x) and not x.is_down())
	if e in _tokens:
		return true
	if _tokens.size() < MAX_ATTACKERS:
		_tokens.append(e)
		return true
	return false


func has_token(e: Node) -> bool:
	_tokens = _tokens.filter(func(x): return is_instance_valid(x) and not x.is_down())
	return e in _tokens or _tokens.size() < MAX_ATTACKERS


func release_token(e: Node) -> void:
	_tokens.erase(e)
## What an enemy goes after: the decoy hologram when one is up nearby, else the Knight.
func target_for(e: Node3D) -> Node3D:
	if decoy and is_instance_valid(decoy) and Time.get_ticks_msec() < decoy_until and e.global_position.distance_to(decoy.global_position) < 30.0:
		return decoy
	return player
func sound(id: String) -> void:
	sound_event.emit(id)


func vehicles() -> Array:
	return drive.vehicles.values()


func vehicle_rids() -> Array:
	return drive.vehicles.values().map(func(v): return v.get_rid())


func smoke_blocks(a: Vector3, b: Vector3) -> bool:
	var now := Time.get_ticks_msec()
	for s in _smoke:
		if s["until"] > now and (s["pos"].distance_to(a) < 4.5 or s["pos"].distance_to(b) < 4.5 or \
				Geometry3D.get_closest_point_to_segment(s["pos"], a, b).distance_to(s["pos"]) < 3.0):
			return true
	return false


## Smoke pellet: enemies can't see through this for 6 s.
func add_smoke(at: Vector3) -> void:
	_smoke.append({"pos": at + Vector3(0, 1, 0), "until": Time.get_ticks_msec() + 6000})


func damage_player(amount: float, from: Vector3, _by: Node) -> void:
	if melee and melee.invulnerable():
		return # dodged
	if melee:
		melee.got_hit()
	if vitals.shield_until > Time.get_ticks_msec():
		effects.burst("electrical", player.global_position + Vector3(0, 1.2, 0), 2, 0.6, 0.6, 0.3)
		return
	amount *= 0.65 * armor_mult # CR-X9 plating: street weapons barely scratch it
	var absorbed := minf(vitals.armor, amount * 0.5)
	vitals.armor -= absorbed
	vitals.health = maxf(0.0, vitals.health - (amount - absorbed))
	vitals._last_hurt = Time.get_ticks_msec()
	player_hurt.emit(amount, from)


func tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var len := from.distance_to(to)
	if len < 0.2:
		return
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.02, 0.02, len)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color, 0.85)
	b.material = m
	mi.mesh = b
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (from + to) / 2
	mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(mi.queue_free)


# ---------------- enemies ----------------
func spawn(npc_id: String, at: Vector3, heading: float, clip := "NPC_Idle") -> Enemy:
	var e := Enemy.create(npc_id, at, heading, self, clip)
	add_child(e)
	e.downed.connect(_on_downed)
	enemies.append(e)
	return e


## A squad of n around `at` (facing each other a little, like they're talking).
func squad(ids: Array, at: Vector3, n: int, clip := "NPC_Idle") -> Array:
	var out := []
	for i in n:
		var a := TAU * i / n
		var p := at + Vector3(cos(a), 0, sin(a)) * (1.2 + randf() * 0.8)
		p.y = _ground(p)
		out.append(spawn(ids[i % ids.size()], p, a + PI, clip))
	return out


## Gunfire / explosions: every enemy within radius hears it.
func noise(at: Vector3, radius: float) -> void:
	for e in enemies:
		if not e.is_down() and e.global_position.distance_to(at) < radius:
			e.alert(player.global_position)


func _on_downed(e: Enemy) -> void:
	var r: int = e.cfg["reward"]
	credits += r
	heat = minf(5.0, heat + 0.35)
	notify.emit("%s down  +%d cr" % [e.cfg["faction"], r], "health", "info")
	_check_crimes()
	_check_mission()


func _ground(p: Vector3) -> float:
	# from just above street level: tree canopies and lamp arms must not count as ground
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2, 0), p + Vector3(0, -40, 0))
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"].y if hit else p.y


## A street point `min_d`..`max_d` m from the Knight, preferably out of his line of sight.
func street_point(min_d: float, max_d: float) -> Vector3:
	var p := player.global_position
	var best := p + Vector3(min_d, 0, 0)
	for i in 12:
		var a := randf() * TAU
		var d := randf_range(min_d, max_d)
		var c := p + Vector3(cos(a), 0, sin(a)) * d
		# snap to the nearest avenue's sidewalk
		var sx := roundf(c.x / District.SPACING) * District.SPACING
		var sz := roundf(c.z / District.SPACING) * District.SPACING
		if absf(c.x - sx) < absf(c.z - sz):
			c.x = sx + (12.0 if randf() < 0.5 else -12.0)
		else:
			c.z = sz + (12.0 if randf() < 0.5 else -12.0)
		var lim := District.GRID * District.SPACING - 10
		c.x = clampf(c.x, -lim, lim)
		c.z = clampf(c.z, -lim, lim)
		best = c
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.6, 0), c + Vector3(0, 1.5, 0))
		q.exclude = [player.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			break # hidden from the Knight: good spawn
	best.y = _ground(best)
	return best


# ---------------- crimes ----------------
const CRIMES := [
	{"kind": "Mugging", "ids": ["npc_criminal_thug"], "n": 2, "victim": true},
	{"kind": "Armed robbery", "ids": ["npc_mercenary", "npc_criminal_thug"], "n": 3, "victim": true},
	{"kind": "Gang standoff", "ids": ["npc_criminal_thug", "npc_enforcer"], "n": 4, "victim": false},
	{"kind": "Weapons deal", "ids": ["npc_mercenary", "npc_stealth_operative", "npc_riot_trooper"], "n": 4, "victim": false},
	{"kind": "Rogue security bots", "ids": ["npc_security_robot"], "n": 3, "victim": false},
]


func start_crime(def := {}) -> void:
	if def.is_empty():
		def = CRIMES[randi() % CRIMES.size()]
	var at := street_point(80, 300)
	var squad_list := squad(def["ids"], at, def["n"], "NPC_Talk")
	var victim: Node3D = null
	if def["victim"]:
		victim = load(CKData.model_path(["npc_civilian_a", "npc_office_worker", "npc_scientist"][randi() % 3])).instantiate()
		add_child(victim)
		victim.global_position = at + Vector3(0.6, 0, 0.6)
		var ap: AnimationPlayer = victim.find_child("AnimationPlayer", true, false)
		if ap and ap.has_animation("NPC_Cower"):
			ap.play("NPC_Cower")
	crimes.append({"kind": def["kind"], "pos": at, "enemies": squad_list, "victim": victim,
		"until": Time.get_ticks_msec() + 180000, "reward": 50 * def["n"]})
	notify.emit("Crime in progress: %s, %d m %s" % [def["kind"], roundi(at.distance_to(player.global_position)), _dir_word(at)], "notification", "warn")
	sound("ui.deny")


func _dir_word(at: Vector3) -> String:
	var d := at - player.global_position
	var deg := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0) # 0 = north (-Z)
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(deg / 45.0)) % 8]


func _check_crimes() -> void:
	var now := Time.get_ticks_msec()
	for c in crimes.duplicate():
		var left: Array = c["enemies"].filter(func(e): return is_instance_valid(e) and not e.is_down())
		if left.is_empty():
			credits += c["reward"]
			notify.emit("%s stopped  +%d cr" % [c["kind"], c["reward"]], "shield", "info")
			sound("armor.activate")
			if c["victim"]:
				_free_later(c["victim"], 20.0)
			crimes.erase(c)
		elif now > c["until"]:
			notify.emit("%s: the suspects got away" % c["kind"], "notification", "warn")
			for e in c["enemies"]:
				if is_instance_valid(e) and not e.is_down() and e.state == "idle":
					_free_later(e, 0.0)
			if c["victim"]:
				_free_later(c["victim"], 0.0)
			crimes.erase(c)


func _free_later(n: Node, seconds: float) -> void:
	if seconds <= 0:
		enemies.erase(n)
		n.queue_free()
	else:
		get_tree().create_timer(seconds).timeout.connect(n.queue_free) # enemies[] drops freed entries in update()


# ---------------- missions ----------------
func start_mission(i: int) -> void:
	if i >= missions.size():
		mission = {}
		objective = "All story missions complete. Stop street crimes to climb the ranks"
		return
	mission_index = i
	mission = missions[i].duplicate(true)
	mission["targets"] = []
	_mission_t = 0.0
	var m := mission
	match m["type"]:
		"clear":
			var at := Vector3(m["at"][0], 0, m["at"][1])
			at.y = _ground(at)
			m["targets"] = squad(m["ids"], at, m["n"], "NPC_Talk")
			m["pos"] = at
		"reach":
			m["pos"] = Vector3(m["at"][0], 0, m["at"][1])
			m["pos"].y = _ground(m["pos"])
			_ring(m["pos"], 6.0 if not m.get("air", false) else 14.0)
	objective = m["objective"]
	notify.emit("Mission: %s" % m["title"], "map", "info")
	sound("vehicle.mode")


func _ring(at: Vector3, radius: float) -> void:
	if _checkpoint_ring:
		_checkpoint_ring.queue_free()
	var t := TorusMesh.new()
	t.inner_radius = radius - 0.25
	t.outer_radius = radius
	t.rings = 48
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.25, 0.36)
	m.emission_enabled = true
	m.emission = Color(1, 0.25, 0.36)
	m.emission_energy_multiplier = 3
	t.material = m
	_checkpoint_ring = MeshInstance3D.new()
	_checkpoint_ring.mesh = t
	_checkpoint_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_checkpoint_ring)
	_checkpoint_ring.global_position = at + Vector3(0, radius if mission.get("air", false) else 0.15, 0)
	if mission.get("air", false):
		_checkpoint_ring.rotation.x = PI / 2


func _check_mission() -> void:
	if mission.is_empty():
		return
	var done := false
	match mission["type"]:
		"clear":
			done = mission["targets"].all(func(e): return not is_instance_valid(e) or e.is_down())
		"reach":
			var need: String = mission.get("vehicle", "")
			var ok_vehicle := need == "" or (drive.driving != null and drive.driving.id == need)
			var radius := 14.0 if mission.get("air", false) else 7.0
			var p := player.global_position
			if mission.get("air", false):
				p.y = drive.driving.global_position.y if drive.driving else p.y
			done = ok_vehicle and p.distance_to(mission["pos"] + Vector3(0, radius if mission.get("air", false) else 0, 0)) < radius + 2.0
	if done:
		credits += int(mission["reward"])
		notify.emit("Mission complete: %s  +%d cr" % [mission["title"], mission["reward"]], "shield", "info")
		sound("armor.activate")
		if _checkpoint_ring:
			_checkpoint_ring.queue_free()
			_checkpoint_ring = null
		start_mission(mission_index + 1)


# ---------------- per frame ----------------
func update(dt: float, underground: bool) -> void:
	var now := Time.get_ticks_msec()
	_smoke = _smoke.filter(func(s): return s["until"] > now)
	# heat: rises while enemies see the Knight, cools after he breaks contact
	var seen := false
	for e in enemies:
		if is_instance_valid(e) and not e.is_down() and e.state in ["chase", "attack"] and e._seen_t < 1.0:
			seen = true
			break
	if seen:
		_cool_t = 0.0
		heat = maxf(heat, 1.0)
	else:
		_cool_t += dt
		if _cool_t > 12.0:
			heat = maxf(0.0, heat - dt / 10.0)
	# reinforcements while heat is up (not underground: the Citadel is the Knight's safe house)
	if stars() >= 2 and not underground:
		_reinforce_t -= dt
		if _reinforce_t <= 0:
			_reinforce_t = 26.0 - stars() * 3.0
			var n := 1 + stars()
			var ids: Array = _spawn_ids.slice(0, mini(_spawn_ids.size(), 2 + stars()))
			for e in squad(ids, street_point(60, 110), n):
				e.alert(player.global_position)
				e.state = "chase"
			notify.emit("Reinforcements inbound (%d)" % n, "notification", "warn")
	# street crimes
	if not underground:
		_crime_t -= dt
		if _crime_t <= 0 and crimes.size() < 2:
			_crime_t = randf_range(50.0, 80.0)
			start_crime()
	_check_crimes()
	# missions: reach checks every frame (cheap)
	_mission_t += dt
	if not mission.is_empty():
		if mission["type"] == "reach":
			_check_mission()
			if mission.has("time") and _mission_t > float(mission["time"]):
				notify.emit("Mission failed: out of time. Retrying", "notification", "warn")
				start_mission(mission_index)
		if _checkpoint_ring and not mission.get("air", false):
			_checkpoint_ring.rotate_y(dt * 0.8)
	# despawn downed / far enemies that aren't part of a crime or mission
	for e in enemies.duplicate():
		if not is_instance_valid(e):
			enemies.erase(e)
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		var keep := _owned(e)
		if (e.is_down() and d > 60.0) or (not keep and d > 260.0):
			enemies.erase(e)
			e.queue_free()
	# markers for the HUD compass and the map
	markers.clear()
	for c in crimes:
		markers.append({"pos": c["pos"], "kind": "crime", "label": c["kind"]})
	if not mission.is_empty():
		markers.append({"pos": mission.get("pos", player.global_position), "kind": "mission", "label": mission["title"]})
	if waypoint != null:
		if Vector2(waypoint.x - player.global_position.x, waypoint.z - player.global_position.z).length() < 12.0:
			waypoint = null
			notify.emit("Waypoint reached", "map", "info")
		else:
			markers.append({"pos": waypoint, "kind": "waypoint", "label": "Waypoint"})


func _owned(e: Enemy) -> bool:
	for c in crimes:
		if e in c["enemies"]:
			return true
	return not mission.is_empty() and e in mission.get("targets", [])


func snapshot() -> Dictionary:
	return {"credits": credits, "mission": mission_index}


func load_state(s: Dictionary) -> void:
	credits = int(s.get("credits", 0))
	for e in enemies:
		e.queue_free()
	enemies.clear()
	start_mission(int(s.get("mission", 0)))
