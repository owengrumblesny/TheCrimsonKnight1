class_name Melee
extends Node
## Free-flow hand-to-hand combat (Godot port). Active on foot with no ranged weapon drawn and an alerted
## enemy within reach; otherwise LMB/RMB/E/C keep their normal meanings.
##  - LMB light strike (CK_PunchR / CK_PunchL alternating), RMB heavy strike (CK_HeavyStrike, breaks guards,
##    knocks back). The Knight lunges to the target picked by camera direction, so strikes chain across a crowd.
##  - E counter: when an enemy is winding up a strike (red "!" over his head) within 4.5 m. CK_Counter.
##  - C dodge: a quick evasive duck with invulnerability (CK_Dodge).
##  - Combo: each hit within 2 s adds to the chain and to damage (up to x2). Getting hit ends it.
##  - Hit-stop: a 40 ms slow-down on impact for weight (off with Reduce motion).

signal combo_changed(n: int)

const REACH := 7.0
const COUNTER_REACH := 4.5

var player: Player
var cam: FollowCamera
var director: Director
var effects: Effects
var audio: CKAudio
var combo := 0
var reduce_motion := false
## strike damage / knockback multiplier (R.E.D. overdrive sets 2 for a while)
var power := 1.0
## hold E in a fight (with nothing to counter) to block: frontal strikes glance off and stagger the attacker
var blocking := false
var _combo_t := 0.0
var _left := false
var _busy_t := 0.0
var _pending: Dictionary = {} # strike waiting to land {target, at, heavy}
var _invuln_t := 0.0
var _same_target := 0
var _last_target: Enemy


func invulnerable() -> bool:
	return _invuln_t > 0.0


## True when the attack buttons should fight instead of using items.
func engaged(ranged_drawn: bool) -> bool:
	if ranged_drawn or player.mode not in ["ground", "action", "lunge"]:
		return false
	for e in director.enemies:
		if is_instance_valid(e) and not e.is_down() and e.state != "idle" and e.global_position.distance_to(player.global_position) < REACH + 3.0:
			return true
	return false


## Enemy winding up a strike within counter reach (the HUD shows "Counter").
func counter_target() -> Enemy:
	var best: Enemy = null
	var bd := COUNTER_REACH
	for e in director.enemies:
		if is_instance_valid(e) and e.state == "windup":
			var d: float = e.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = e
	return best


func _pick_target() -> Enemy:
	var cam_fwd := -cam.camera.global_basis.z
	cam_fwd.y = 0
	cam_fwd = cam_fwd.normalized()
	var best: Enemy = null
	var best_score := 1e9
	for e in director.enemies:
		if not is_instance_valid(e) or e.is_down():
			continue
		var to: Vector3 = e.global_position - player.global_position
		to.y = 0
		var d := to.length()
		if d > REACH:
			continue
		var facing := cam_fwd.dot(to.normalized()) if d > 0.1 else 1.0
		if facing < 0.2 and d > 2.5:
			continue
		var score := d - facing * 3.0 # prefer what the camera points at
		if score < best_score:
			best_score = score
			best = e
	return best


## True if a blow from `from` is blocked (the Knight is guarding and facing it). Staggers the nearest attacker.
func blocks(from: Vector3) -> bool:
	if not blocking:
		return false
	var to := from - player.global_position
	to.y = 0
	var fwd := Vector3(sin(player.heading), 0, cos(player.heading))
	if to.length() > 0.01 and to.normalized().dot(fwd) < 0.2:
		return false # from behind or the side: the guard doesn't cover it
	effects.burst("sparks", player.global_position + Vector3(0, 1.4, 0) + fwd * 0.5, 8, 2.5, 0.4, 0.25)
	audio.play("weapon.impact")
	if not reduce_motion:
		cam.kick(0.006)
	var best: Enemy = null
	var bd := 3.5
	for e in director.enemies:
		if is_instance_valid(e) and not e.is_down() and e.global_position.distance_to(from) < bd:
			bd = e.global_position.distance_to(from)
			best = e
	if best:
		best.stun(0.7)
	return true


func set_block(on: bool) -> void:
	if on == blocking:
		return
	blocking = on
	if on:
		player.act("CK_Guard", 0.12)


func strike(heavy: bool) -> void:
	if _busy_t > 0.0:
		return
	if director:
		director.record("heavy" if heavy else "light")
	var t := _pick_target()
	_busy_t = 0.5 if heavy else 0.26
	var clip := "CK_HeavyStrike" if heavy else ("CK_PunchL" if _left else "CK_PunchR")
	_left = not _left
	if t == null:
		player.act(clip, 0.3 if not heavy else 0.55) # swing at air
		audio.play("weapon.swing")
		return
	var to := t.global_position - player.global_position
	to.y = 0
	player.heading = atan2(to.x, to.z)
	var gap := maxf(0.0, to.length() - 1.25)
	if gap > 0.3:
		player.lunge(to.normalized() * clampf(gap / 0.22, 4.0, 14.0), 0.22) # close the distance
	player.act(clip, (0.55 if heavy else 0.3) + (0.22 if gap > 0.3 else 0.0))
	_pending = {"target": t, "at": (0.22 if gap > 0.3 else 0.0) + (0.45 if heavy else 0.2), "heavy": heavy}
	audio.play("weapon.swing")


func counter() -> bool:
	var t := counter_target()
	if t == null:
		return false
	var to := t.global_position - player.global_position
	to.y = 0
	player.heading = atan2(to.x, to.z)
	if to.length() > 1.6:
		player.lunge(to.normalized() * 10.0, (to.length() - 1.3) / 10.0)
	player.act("CK_Counter", 0.45)
	if director:
		director.record("counter")
	t.countered()
	_land_hit(t, 35.0, true, to.normalized())
	audio.play("armor.activate")
	return true


func dodge(dir: Vector3) -> void:
	if _busy_t > 0.0:
		return
	if dir.length() < 0.1:
		dir = -Vector3(sin(player.heading), 0, cos(player.heading)) # back-step
	player.act("CK_Dodge", 0.35)
	if director:
		director.record("dodge")
	player.lunge(dir.normalized() * 8.0, 0.28)
	_invuln_t = 0.45
	_busy_t = 0.3
	audio.play("weapon.swing")


func got_hit() -> void:
	if combo > 0:
		combo = 0
		combo_changed.emit(0)


func update(dt: float) -> void:
	_busy_t -= dt
	_invuln_t -= dt
	_combo_t -= dt
	if _combo_t <= 0.0 and combo > 0:
		combo = 0
		combo_changed.emit(0)
	if not _pending.is_empty():
		_pending["at"] -= dt
		if _pending["at"] <= 0.0:
			var t: Enemy = _pending["target"]
			var heavy: bool = _pending["heavy"]
			_pending = {}
			if is_instance_valid(t) and not t.is_down() and t.global_position.distance_to(player.global_position) < 2.4:
				var dir := (t.global_position - player.global_position)
				dir.y = 0
				# armoured / guarded enemies block a third light hit in a row on them: heavy strikes break guards
				_same_target = _same_target + 1 if t == _last_target else 1
				_last_target = t
				var guards: bool = t.cfg.get("armored", false) or t.id == "npc_enforcer" or director.adapting("light")
				if not heavy and guards and _same_target >= (3 if not director.adapting("light") else 2) and randf() < 0.6:
					t.block()
					effects.burst("sparks", t.global_position + Vector3(0, 1.3, 0), 6, 2.0, 0.4, 0.25)
					audio.play("weapon.impact")
					_same_target = 0
					return
				var dmg := (45.0 if heavy else 20.0) * (1.0 + minf(combo, 10) * 0.1) * power
				_land_hit(t, dmg, heavy, dir.normalized())


func _land_hit(t: Enemy, dmg: float, heavy: bool, dir: Vector3) -> void:
	t.hit(dmg, t.global_position + Vector3(0, 1.3, 0), dir)
	if heavy:
		t.stun(1.0)
		t.velocity += dir * 5.0 * power
	combo += 1
	_combo_t = 2.0
	combo_changed.emit(combo)
	effects.burst("sparks", t.global_position + Vector3(0, 1.3, 0), 4 if not heavy else 8, 1.8, 0.35, 0.25)
	audio.play("weapon.impact")
	if not reduce_motion:
		cam.kick(0.008 if not heavy else 0.02)
		Engine.time_scale = 0.15
		get_tree().create_timer(0.04 if not heavy else 0.07, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
