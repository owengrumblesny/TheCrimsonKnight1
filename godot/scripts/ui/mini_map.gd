class_name MiniMap
extends Control
## HUD minimap (bottom-left): a heading-up radar of the streets around the Knight, like an open-world game's. Roads and nearby building footprints from the district, enemies (red), vehicles (blue),
## crime / mission / waypoint markers (clamped to the edge when off the map), the Knight's arrow in the middle.

const SIZE := 210.0
const SCALE := 0.75 # px per metre (about 140 m to the edge)

var game: Node
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _process(dt: float) -> void:
	_t -= dt
	if _t <= 0:
		_t = 0.08
		queue_redraw()


func _to_map(w: Vector3, origin: Vector3, rot: float) -> Vector2:
	var d := Vector2(w.x - origin.x, w.z - origin.z).rotated(rot)
	return Vector2(SIZE / 2, SIZE / 2) + d * SCALE


func _draw() -> void:
	if game == null or game.player == null:
		return
	var c := Vector2(SIZE / 2, SIZE / 2)
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(0.04, 0.035, 0.06, 0.82))
	var o: Vector3 = game.player.global_position
	# heading-up: rotate the world so the camera's forward points up the minimap
	var yaw: float = game.cam.yaw if not game.drive.driving else game.drive.driving.rotation.y + PI
	# camera forward (-sin yaw, -cos yaw) maps to screen up (0, -1) when rotated by yaw
	var rot := yaw
	if game.underground:
		draw_string(get_theme_default_font(), Vector2(12, SIZE / 2), "RED CITADEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CKUI.BRIGHT)
	else:
		var reach := SIZE / SCALE
		for f in game.district.map_features:
			var mn: Vector2 = f["min"]
			var mx: Vector2 = f["max"]
			if mx.x < o.x - reach or mn.x > o.x + reach or mx.y < o.z - reach or mn.y > o.z + reach:
				continue
			var col := Color(0.2, 0.19, 0.25) if f["kind"] == "road" else Color(0.75, 0.13, 0.2) if f["kind"] == "portal" else Color(0.1, 0.22, 0.12) if f["kind"] == "park" else Color(0.35, 0.22, 0.1) if f["kind"] == "place" else Color(0.13, 0.1, 0.13)
			var pts := PackedVector2Array()
			for corner in [Vector3(mn.x, 0, mn.y), Vector3(mx.x, 0, mn.y), Vector3(mx.x, 0, mx.y), Vector3(mn.x, 0, mx.y)]:
				pts.append(_to_map(corner, o, rot))
			draw_colored_polygon(pts, col)
		for e in game.director.enemies:
			if is_instance_valid(e) and not e.is_down():
				var p := _to_map(e.global_position, o, rot)
				if Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)).has_point(p):
					draw_circle(p, 3.5, Color(1, 0.2, 0.25) if e.state != "idle" else Color(0.75, 0.35, 0.35))
		for v in game.drive.vehicles.values():
			draw_circle(_to_map(v.global_position, o, rot), 4.0, Color(0.4, 0.7, 1.0))
	for m in game.director.markers:
		var p := _to_map(m["pos"], o, rot)
		var col := CKUI.BRIGHT if m["kind"] == "crime" else Color("#ffc040") if m["kind"] == "mission" else Color.WHITE
		if not Rect2(Vector2(6, 6), Vector2(SIZE - 12, SIZE - 12)).has_point(p):
			p = c + (p - c).limit_length(SIZE / 2 - 8) # clamp to the edge, pointing the way
		draw_circle(p, 5.5, col)
		draw_arc(p, 7.5, 0, TAU, 16, Color(0, 0, 0, 0.6), 1.5)
	# the Knight (always pointing up: heading-up map)
	var heading: float = game.player.heading if not game.drive.driving else game.drive.driving.rotation.y
	var a := Vector2(sin(heading), cos(heading)).rotated(rot).angle() + PI / 2
	var tri := PackedVector2Array([Vector2(0, -9), Vector2(6, 7), Vector2(-6, 7)])
	for i in tri.size():
		tri[i] = c + tri[i].rotated(a)
	draw_colored_polygon(tri, Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), CKUI.BORDER, false, 2.0)
	# north tick
	var n := c + Vector2(0, -1).rotated(rot) * (SIZE / 2 - 12)
	draw_string(get_theme_default_font(), n - Vector2(5, -5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CKUI.MUTED)
