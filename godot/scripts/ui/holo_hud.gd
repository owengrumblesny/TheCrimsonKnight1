class_name HoloHUD
extends Control
## The CR-X9 visor's holographic info layer, drawn over every camera mode (third person, helmet, driving,
## drone): a thin animated targeting ring, brackets on nearby hostiles (type, distance, health), tags on
## nearby places and parks, a SYSTEMS readout (suit, power, vision, R.E.D., speed, altitude, heading,
## time/weather, threats) and a tactical radar (hostiles, civilians, vehicles, crimes, waypoint).
## All drawn with _draw (no nodes per target), cyan-white with crimson accents.

const CYAN := Color(0.55, 0.9, 1.0, 0.85)
const DIM := Color(0.55, 0.9, 1.0, 0.35)
const HOT := Color(1.0, 0.35, 0.3, 0.95)
const AMBER := Color(1.0, 0.72, 0.3, 0.9)
const RADAR_R := 78.0
const RADAR_RANGE := 120.0

var game: Node # main.gd
var _t := 0.0
var _boot := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


func _process(dt: float) -> void:
	_t += dt
	_boot = minf(1.0, _boot + dt * 0.8)
	queue_redraw()


func _text(at: Vector2, s: String, size := 12, col := CYAN, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_font, at + Vector2(1, 1), s, align, width, size, Color(0, 0, 0, 0.6 * col.a))
	draw_string(_font, at, s, align, width, size, col)


func _bracket(c: Vector2, half: Vector2, col: Color, len := 8.0, w := 1.5) -> void:
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p: Vector2 = c + half * s
		draw_line(p, p - Vector2(s.x * len, 0), col, w, true)
		draw_line(p, p - Vector2(0, s.y * len), col, w, true)


func _draw() -> void:
	if game == null or not game.started or game.player == null:
		return
	var a := _boot
	var vp := size
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var p: Vector3 = game.player.global_position
	var driving: Vehicle = game.drive.driving
	var centre := vp / 2
	# ---- centre: slow rotating arcs around the reticle (outside it, so aiming stays clean) ----
	var r := 46.0
	for i in 3:
		var a0 := _t * (0.6 if i % 2 == 0 else -0.45) + i * TAU / 3.0
		draw_arc(centre, r + i * 7.0, a0, a0 + 0.9, 18, Color(DIM, DIM.a * a), 1.2, true)
	# ---- hostiles: brackets, distance, health ----
	var threats := 0
	for e in game.director.enemies:
		if not is_instance_valid(e) or e.is_down():
			continue
		var d: float = e.global_position.distance_to(p)
		if d > 60.0:
			continue
		threats += 1
		var head: Vector3 = e.global_position + Vector3(0, 2.0, 0)
		var foot: Vector3 = e.global_position
		if cam.is_position_behind(head):
			continue
		var sh := cam.unproject_position(head)
		var sf := cam.unproject_position(foot)
		var h := maxf(18.0, sf.y - sh.y)
		var c := Vector2(sh.x, (sh.y + sf.y) / 2)
		var alerted: bool = e.state != "idle"
		var col := HOT if alerted else AMBER
		col.a *= a
		_bracket(c, Vector2(h * 0.32, h * 0.55), col)
		var hp := clampf(e.health / maxf(1.0, float(e.cfg.get("health", 100))), 0.0, 1.0)
		var bw := h * 0.64
		draw_rect(Rect2(c.x - bw / 2, sh.y - 9, bw, 3), Color(0, 0, 0, 0.5 * a))
		draw_rect(Rect2(c.x - bw / 2, sh.y - 9, bw * hp, 3), col)
		if d < 35.0:
			_text(Vector2(c.x + h * 0.36, c.y - h * 0.4), "%s" % String(e.cfg.get("label", e.id)).to_upper(), 10, col)
			_text(Vector2(c.x + h * 0.36, c.y - h * 0.4 + 12), "%dm %s" % [roundi(d), "HOSTILE" if alerted else "UNAWARE"], 10, Color(col, col.a * 0.8))
	# ---- places and parks within 90 m: holo tags ----
	if game.district and game.district.places and not game.underground:
		for pl in game.district.places.list:
			var c3: Vector3 = pl["center"] + Vector3(0, 6.0, 0)
			var d2: float = c3.distance_to(p)
			if d2 > 90.0 or d2 < 6.0 or cam.is_position_behind(c3):
				continue
			var s := cam.unproject_position(c3)
			var fade := clampf((90.0 - d2) / 30.0, 0.0, 1.0) * a
			draw_circle(s, 2.5, Color(CYAN, fade))
			draw_line(s, s + Vector2(14, -10), Color(CYAN, fade * 0.7), 1.0, true)
			_text(s + Vector2(16, -12), "%s  %dm" % [pl["name"], roundi(d2)], 10, Color(CYAN, fade))
	# ---- SYSTEMS panel (right side, under the notifications) ----
	var x := vp.x - 238.0
	var y := 250.0
	draw_rect(Rect2(x - 8, y - 18, 230, 196), Color(0.02, 0.06, 0.09, 0.45 * a))
	_bracket(Vector2(x + 107, y + 80), Vector2(115, 98), Color(CYAN, 0.6 * a), 10.0, 1.2)
	_text(Vector2(x, y - 4), "CR-X9  SYSTEMS", 11, Color(1, 0.4, 0.45, a))
	draw_line(Vector2(x, y + 2), Vector2(x + 210, y + 2), Color(DIM, DIM.a * a), 1.0)
	var v: Vitals = game.vitals
	var bars := [["SUIT", v.health / 100.0, CYAN], ["ARMOR", v.armor / 100.0, CYAN], ["POWER", v.energy / 100.0, AMBER]]
	for i in bars.size():
		var by := y + 16 + i * 15
		_text(Vector2(x, by + 4), bars[i][0], 9, Color(DIM, a))
		draw_rect(Rect2(x + 46, by - 3, 120, 5), Color(0, 0, 0, 0.4 * a))
		draw_rect(Rect2(x + 46, by - 3, 120 * clampf(bars[i][1], 0, 1), 5), Color(bars[i][2], 0.85 * a))
		_text(Vector2(x + 172, by + 4), "%d%%" % roundi(bars[i][1] * 100), 9, Color(CYAN, a))
	var spd: float = (absf(driving.speed()) if driving else game.player.speed) * 3.6
	var alt: float = driving.global_position.y if driving else p.y
	var hdg: float = fposmod(180.0 - rad_to_deg(game.player.heading if not driving else driving.rotation.y), 360.0)
	var red_state := "OFFLINE"
	if game.red:
		red_state = "THINKING" if game.red.thinking else ("LISTENING" if game.red.voice.listening else ("ONLINE" if game.red.brain_ready else "COMMANDS"))
	var lines := [
		["VISION", game.vision.MODES[game.vision.mode].to_upper() if game.vision else "NORMAL"],
		["R.E.D.", red_state],
		["SPEED", "%d km/h" % roundi(spd)],
		["ALT", "%d m" % roundi(alt)],
		["HDG", "%03d°" % roundi(hdg)],
		["TIME", "%s  %s" % [game.stage.clock(), game.stage.weather_name.to_upper()]],
		["THREATS", "%d  ·  HEAT %d★" % [threats, game.director.stars()]],
		["POS", "%d, %d" % [roundi(p.x), roundi(p.z)]],
	]
	for i in lines.size():
		var ly := y + 70 + i * 13
		_text(Vector2(x, ly), lines[i][0], 9, Color(DIM, a))
		var col2 := HOT if (lines[i][0] == "THREATS" and threats > 0) else CYAN
		_text(Vector2(x + 60, ly), lines[i][1], 10, Color(col2, a))
	# ---- tactical radar (right side, under SYSTEMS) ----
	var rc := Vector2(vp.x - 130.0, y + 290.0)
	if rc.y + RADAR_R > vp.y - 100:
		rc.y = vp.y - 100 - RADAR_R
	draw_circle(rc, RADAR_R, Color(0.02, 0.07, 0.1, 0.55 * a))
	for k in [1.0, 0.66, 0.33]:
		draw_arc(rc, RADAR_R * k, 0, TAU, 40, Color(DIM, DIM.a * a * 0.8), 1.0, true)
	draw_line(rc - Vector2(RADAR_R, 0), rc + Vector2(RADAR_R, 0), Color(DIM, 0.2 * a), 1.0)
	draw_line(rc - Vector2(0, RADAR_R), rc + Vector2(0, RADAR_R), Color(DIM, 0.2 * a), 1.0)
	var sweep := fmod(_t * 1.6, TAU)
	for k in 6:
		draw_line(rc, rc + Vector2(cos(sweep - k * 0.06), sin(sweep - k * 0.06)) * RADAR_R, Color(CYAN, (0.35 - k * 0.05) * a), 2.0, true)
	var yaw: float = game.cam.yaw if not driving else driving.rotation.y + PI
	var to_radar := func(w: Vector3) -> Vector2:
		var d3 := w - p
		var rel := Vector2(d3.x, d3.z).rotated(yaw - PI)
		return Vector2(rel.x, rel.y) / RADAR_RANGE * RADAR_R
	for e in game.director.enemies:
		if is_instance_valid(e) and not e.is_down():
			var q: Vector2 = to_radar.call(e.global_position)
			if q.length() < RADAR_R:
				draw_circle(rc + q, 3.0, Color(HOT, a))
	for w in game.street.walkers:
		if is_instance_valid(w["root"]):
			var q2: Vector2 = to_radar.call(w["root"].global_position)
			if q2.length() < RADAR_R:
				draw_circle(rc + q2, 1.6, Color(0.6, 0.8, 1.0, 0.5 * a))
	for vid in game.drive.vehicles:
		var veh: Vehicle = game.drive.vehicles[vid]
		if is_instance_valid(veh) and veh != driving:
			var q3: Vector2 = to_radar.call(veh.global_position)
			if q3.length() < RADAR_R:
				draw_rect(Rect2(rc + q3 - Vector2(3, 3), Vector2(6, 6)), Color(AMBER, a))
	for cr in game.director.crimes:
		var q4: Vector2 = to_radar.call(cr["pos"])
		var at := rc + (q4 if q4.length() < RADAR_R else q4.normalized() * RADAR_R)
		draw_arc(at, 5.0 + sin(_t * 6.0) * 1.5, 0, TAU, 12, Color(HOT, a), 1.5, true)
	if game.director.waypoint != null:
		var q5: Vector2 = to_radar.call(game.director.waypoint)
		var at2 := rc + (q5 if q5.length() < RADAR_R else q5.normalized() * RADAR_R)
		draw_colored_polygon(PackedVector2Array([at2 + Vector2(0, -5), at2 + Vector2(4, 0), at2 + Vector2(0, 5), at2 + Vector2(-4, 0)]), Color(1, 0.85, 0.3, a))
	draw_colored_polygon(PackedVector2Array([rc + Vector2(0, -6), rc + Vector2(4, 4), rc + Vector2(-4, 4)]), Color(1, 1, 1, a))
	_text(rc + Vector2(-RADAR_R, -RADAR_R - 6), "TACTICAL  %dm" % roundi(RADAR_RANGE), 9, Color(DIM, a))
	# ---- frame corners (the "visor" edge) ----
	var m := 10.0
	var fc := Color(1, 0.3, 0.38, 0.35 * a)
	for s in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var corner := Vector2(m + s.x * (vp.x - 2 * m), m + s.y * (vp.y - 2 * m))
		var dx := 1.0 if s.x == 0 else -1.0
		var dy := 1.0 if s.y == 0 else -1.0
		draw_line(corner, corner + Vector2(dx * 40, 0), fc, 2.0)
		draw_line(corner, corner + Vector2(0, dy * 40), fc, 2.0)
