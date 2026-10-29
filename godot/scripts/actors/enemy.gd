class_name Enemy
extends CharacterBody3D
## Hostile NPC (Godot port): one of the NPC families with real AI. Tuning: godot/data/enemies.json.
## States: idle -> alert (spotted / heard / hurt) -> chase -> attack (ranged bolt or melee strike),
## stagger when hit, down when health runs out (topples, stays down, despawned by the director).
## Sight: 28 m, 110 degree cone, line of sight; smoke clouds block it. Vehicles at speed knock enemies down.

signal downed(enemy: Enemy)

const SIGHT := 28.0
const FOV_DOT := -0.35 # ~110 degrees either side of forward

var id := ""
var cfg: Dictionary
var director: Node # Director: player, effects, sound(), damage_player(), smoke_blocks()
var state := "idle"
var health := 100.0
var home := Vector3.ZERO
var idle_clip := "NPC_Idle"
var model: Node3D
var anim: AnimationPlayer
var hand: Node3D
var _attack_t := 0.0
var _state_t := 0.0
var _stagger_t := 0.0
var _seen_t := 0.0 # seconds since the player was last seen
var _last_seen := Vector3.ZERO
var _strafe := 1.0
var _avoid := Vector3.ZERO
var _anim_pending := 0.0
var _windup_t := 0.0
var _mark: Label3D


static func create(npc_id: String, at: Vector3, heading: float, dir: Node, clip := "NPC_Idle") -> Enemy:
	var e := Enemy.new()
	e.id = npc_id
	e.director = dir
	e.home = at
	e.idle_clip = clip
	e.position = at
	e.rotation.y = heading
	return e


func _ready() -> void:
	cfg = CKData.data("enemies")[id]
	health = cfg["health"]
	name = "%s_%d" % [id, get_instance_id()]
	# enemies live on layer 2 (world + player + vehicles are layer 1): sight rays test layer 1 only, so
	# squadmates never block each other's view
	collision_layer = 2
	collision_mask = 3
	floor_snap_length = 0.3
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)
	model = load(CKData.model_path(id)).instantiate()
	add_child(model)
	for b in model.find_children("*", "CollisionObject3D", true, false):
		b.queue_free()
	anim = model.find_child("AnimationPlayer", true, false)
	var sk := model.find_children("*", "Skeleton3D", true, false)
	if sk:
		var bone: int = sk[0].find_bone("Hand_R")
		if bone >= 0:
			var ba := BoneAttachment3D.new()
			ba.bone_name = "Hand_R"
			sk[0].add_child(ba)
			hand = ba
	_play(idle_clip)
	if anim:
		anim.seek(randf() * 2.0, true)
	# counter telegraph: a red "!" over the head while winding up a strike
	_mark = Label3D.new()
	_mark.text = "!"
	_mark.font_size = 96
	_mark.outline_size = 12
	_mark.modulate = Color(1, 0.2, 0.25)
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.no_depth_test = true
	_mark.position = Vector3(0, 2.35, 0)
	_mark.visible = false
	add_child(_mark)
	_strafe = 1.0 if randf() < 0.5 else -1.0


func _play(clip: String, speed := 1.0) -> void:
	if anim and anim.has_animation(clip):
		if anim.current_animation != clip:
			anim.play(clip, 0.2)
		anim.speed_scale = speed


func is_down() -> bool:
	return state == "down"


## Weapons / gadgets / takedowns call this. Returns true on a knockdown.
func hit(amount: float, _point: Vector3, dir: Vector3) -> bool:
	if state == "down":
		return false
	if cfg.get("armored", false):
		amount *= 0.7
	health -= amount
	alert(director.player.global_position)
	_stagger_t = 0.35
	velocity += Vector3(dir.x, 0, dir.z).normalized() * 2.5
	if health <= 0:
		knock_down(dir)
		return true
	return false


## The Knight countered the wind-up: the strike never lands and the attacker reels.
func countered() -> void:
	_windup_t = 0.0
	_mark.visible = false
	state = "attack"
	director.release_token(self)
	stun(1.2)


## A guard against a light strike: no damage, a brief recoil.
func block() -> void:
	_play("NPC_Alert")
	model.position.z = -0.2
	create_tween().tween_property(model, "position:z", 0.0, 0.2)
	_attack_t = maxf(_attack_t, 0.4)


## Stun without damage (sonic burst, EMP on robots, batarang).
func stun(seconds: float) -> void:
	if state != "down":
		_stagger_t = maxf(_stagger_t, seconds)
		alert(director.player.global_position)


func knock_down(dir := Vector3.ZERO) -> void:
	if state == "down":
		return
	state = "down"
	health = 0
	_mark.visible = false
	director.release_token(self)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 1 # still rests on the ground
	if anim:
		anim.play("NPC_Cower" if anim.has_animation("NPC_Cower") else idle_clip, 0.15)
		anim.speed_scale = 0.0 # frozen in the fall
	# topple away from the hit
	var away := Vector3(dir.x, 0, dir.z).normalized() if dir.length() > 0.1 else -global_basis.z
	var axis := away.cross(Vector3.UP).normalized()
	if axis.length() < 0.1:
		axis = global_basis.x
	var tw := create_tween()
	tw.tween_property(model, "global_basis", Basis(axis, -PI / 2) * model.global_basis, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	director.effects.burst("smoke", global_position, 4, 0.8, 0.9, 0.9)
	director.sound("armor.land")
	downed.emit(self)


## Something got this enemy's attention (gunfire, a hit, a spotted Knight, director heat).
func alert(at: Vector3) -> void:
	if state == "down":
		return
	_last_seen = at
	if state == "idle":
		state = "alert"
		_state_t = 0.0
		_play("NPC_Alert")
		director.noise(global_position, 18.0) # shout: the rest of the squad turns too


func _sees_player() -> bool:
	var p: Node3D = director.target_for(self)
	var to := p.global_position - global_position
	var d := to.length()
	if d > SIGHT:
		return false
	if d < 2.5:
		return true # point blank
	if state == "idle" and global_basis.z.dot(to.normalized()) < FOV_DOT and d > 6.0:
		return false # NPC models face +Z
	if director.smoke_blocks(global_position, p.global_position):
		return false
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.6, 0), p.global_position + Vector3(0, 1.4, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	if p is CollisionObject3D:
		q.exclude.append(p.get_rid())
	for v in director.vehicle_rids():
		q.exclude.append(v)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _physics_process(dt: float) -> void:
	if state == "down":
		velocity.y -= 9.8 * dt
		move_and_slide()
		return
	_state_t += dt
	var p: Node3D = director.target_for(self)
	var target: Vector3 = p.global_position
	var sees := _sees_player()
	if sees:
		_seen_t = 0.0
		_last_seen = target
		if state == "idle":
			alert(target)
	else:
		_seen_t += dt
	# run-over: a vehicle at speed knocks the enemy flying
	for v in director.vehicles():
		if v.global_position.distance_to(global_position) < (3.0 if v.kind == "car" else 1.8) and absf(v.speed()) > 8.0:
			hit(200.0, global_position, (global_position - v.global_position).normalized() + Vector3.UP * 0.5)
			return
	var to := _last_seen - global_position
	to.y = 0
	var dist := to.length()
	var want := Vector3.ZERO
	if state == "windup":
		_windup_t -= dt
		_face(to, dt)
		_play("NPC_Alert")
		if _windup_t <= 0.0:
			_mark.visible = false
			state = "attack"
			_attack(p)
			director.release_token(self)
			_attack_t = cfg["interval"] * randf_range(0.9, 1.3)
	elif _stagger_t > 0:
		_stagger_t -= dt
		_mark.visible = false
		if state == "windup":
			state = "attack"
		_play("NPC_Cower", 1.4)
	else:
		match state:
			"idle":
				_play(idle_clip)
			"alert":
				_face(to, dt)
				_play("NPC_Alert")
				if _state_t > 0.6:
					state = "chase"
			"chase", "attack":
				if _seen_t > 12.0:
					state = "idle" # lost the Knight: give up and stand guard where they are
					home = global_position
				var ranged: bool = cfg["attack"] == "ranged"
				var keep: float = cfg["range"] * (0.6 if ranged else 0.8)
				var waiting: bool = not ranged and p == director.player and not director.has_token(self)
				if waiting:
					keep = 4.0 # circle the fight until it's this enemy's turn
				if dist > keep or not sees:
					want = to.normalized() * cfg["speed"]
					state = "chase"
					_play("NPC_Walk", cfg["speed"] / 1.6)
				else:
					state = "attack"
					if ranged and dist < keep * 0.5:
						want = -to.normalized() * cfg["speed"] * 0.6 # back off to firing range
					elif waiting:
						want = to.normalized().cross(Vector3.UP) * _strafe * 1.6 # circle, wait for an opening
					elif ranged:
						want = to.normalized().cross(Vector3.UP) * _strafe * 1.2 # strafe while shooting
					_play("NPC_Alert")
				_face(to, dt)
				_attack_t -= dt
				if state == "attack" and sees and _attack_t <= 0 and dist <= cfg["range"]:
					if cfg["attack"] == "melee" and p == director.player:
						if director.take_token(self):
							state = "windup" # telegraphed: the Knight can counter (E) until it lands
							_windup_t = 0.6
							_mark.visible = true
					else:
						_attack_t = cfg["interval"] * randf_range(0.8, 1.25)
						_attack(p)
	# obstacle avoidance: a short probe ahead; slide sideways around blockers
	if want.length() > 0.1:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.8, 0), global_position + Vector3(0, 0.8, 0) + want.normalized() * 1.6)
		q.exclude = [get_rid(), director.player.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			_avoid = want.normalized().cross(Vector3.UP) * _strafe * cfg["speed"]
			if randf() < 0.01:
				_strafe = -_strafe
		else:
			_avoid = _avoid.lerp(Vector3.ZERO, dt * 2.0)
		want += _avoid
	velocity.x = lerpf(velocity.x, want.x, minf(1.0, dt * 8))
	velocity.z = lerpf(velocity.z, want.z, minf(1.0, dt * 8))
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * dt
	move_and_slide()


func _face(dir: Vector3, dt: float) -> void:
	if dir.length() < 0.05:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, dt * 8.0)) # models face +Z


func _attack(p: Node3D) -> void:
	if cfg["attack"] == "melee":
		# lunge and strike
		var tw := create_tween()
		tw.tween_property(model, "position:z", 0.35, 0.12)
		tw.tween_property(model, "position:z", 0.0, 0.2)
		director.sound("weapon.swing")
		if p == director.player and global_position.distance_to(p.global_position) <= cfg["range"] + 0.3:
			director.damage_player(cfg["damage"], global_position, self) # striking the decoy hurts nobody
		return
	# ranged: an energy bolt from the hand, hits with `accuracy` (better up close and on a standing target)
	var from: Vector3 = hand.global_position if hand else global_position + Vector3(0, 1.4, 0)
	var aim: Vector3 = p.global_position + Vector3(0, 1.2, 0)
	var dist := from.distance_to(aim)
	var moving: bool = p is Player and p.speed > 5.0
	var chance: float = cfg["accuracy"] * clampf(1.4 - dist / cfg["range"], 0.35, 1.2) * (0.6 if moving else 1.0)
	var hits := randf() < chance
	var end := aim if hits else aim + Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 1.2), randf_range(-1.5, 1.5))
	var q := PhysicsRayQueryParameters3D.create(from, end + (end - from).normalized() * 3.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		end = hit["position"]
		if hit["collider"] == p:
			director.damage_player(cfg["damage"], from, self)
		elif hit["collider"] is Vehicle and hit["collider"].driver_in:
			director.damage_player(cfg["damage"] * 0.25, from, self) # armoured vehicles soak most of it
	director.tracer(from, end, Color(1.0, 0.55, 0.15))
	director.effects.burst("sparks", end, 3, 1.5, 0.25, 0.2)
	director.sound("weapon.shot")
