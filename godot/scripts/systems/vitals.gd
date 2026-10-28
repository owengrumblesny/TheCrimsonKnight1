class_name Vitals
extends RefCounted
## CR-X9 suit vitals that gameplay actually uses (port of systems/vitals.ts):
##  - health: lost to hard-landing impacts the armour can't absorb; slowly regenerates; 0 = suit critical
##  - armor: integrity, absorbs most impact damage; restored only by repair kits
##  - energy: spent by sprinting, gliding and powered gadgets; recharges when not exerting

const MAX := 100.0

var health := MAX
var armor := MAX
var energy := MAX
var shield_until := 0
var _last_hurt := -1000000


## Impact from a landing at vertical speed vy (negative = falling). Returns damage dealt to health.
func impact(vy: float, now: int, hard_speed: float) -> float:
	var excess := -vy - hard_speed
	if excess <= 0 or now < shield_until:
		return 0.0
	var dmg := excess * 7.0
	var absorbed := minf(armor, dmg * 0.7)
	armor -= absorbed
	dmg -= absorbed
	health = maxf(0.0, health - dmg)
	_last_hurt = now
	return dmg


func spend(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	return true


func restore(kind: String, amount: float) -> float:
	var before: float = get(kind)
	set(kind, minf(MAX, before + amount))
	return get(kind) - before


## dt seconds; exertion "sprint", "glide" or "".
func update(dt: float, now: int, exertion: String) -> void:
	if exertion == "sprint":
		energy = maxf(0.0, energy - 7.0 * dt)
	elif exertion == "glide":
		energy = maxf(0.0, energy - 5.0 * dt)
	else:
		energy = minf(MAX, energy + 9.0 * dt)
	if now - _last_hurt > 6000 and health > 0:
		health = minf(MAX, health + 2.0 * dt)


func critical() -> bool:
	return health <= 0


func reset() -> void:
	health = MAX
	armor = MAX
	energy = MAX
	shield_until = 0
