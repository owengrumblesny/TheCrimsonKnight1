class_name MapView
extends Control
## Top-down district map drawn from the loaded district geometry (port of the map canvas in
## ui/MenuManager.ts). North (-Z) is up; the red triangle is the player. Redraws 4x a second.

var game: Node
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(640, 400)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


## Click: set (or move) the waypoint there; right-click clears it.
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			var s := minf(size.x, size.y) / 900.0
			var w: Vector2 = (e.position - size / 2) / s
			game.director.waypoint = Vector3(w.x, 0, w.y)
			game.notify("Waypoint set (%d m)" % roundi(Vector2(w.x - game.player.global_position.x, w.y - game.player.global_position.z).length()), "map")
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			game.director.waypoint = null
		queue_redraw()


func _process(dt: float) -> void:
	_t -= dt
	if _t <= 0:
		_t = 0.25
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0a10"))
	# fit the whole street grid (about ±440 m)
	var s := minf(size.x, size.y) / 900.0
	var c := size / 2
	var font := get_theme_default_font()
	for f in game.district.map_features:
		var col := Color("#1e1d26") if f["kind"] == "road" else Color("#7a1020") if f["kind"] == "portal" else Color("#3a2a33")
		draw_rect(Rect2(c + f["min"] * s, (f["max"] - f["min"]) * s), col)
		if f["kind"] == "portal":
			draw_string(font, c + Vector2(f["max"].x, (f["min"].y + f["max"].y) / 2) * s + Vector2(8, 6), "RED CITADEL ENTRANCE",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CKUI.BRIGHT)
	for m in game.director.markers:
		var mp: Vector3 = m["pos"]
		var col := CKUI.BRIGHT if m["kind"] == "crime" else Color("#ffc040") if m["kind"] == "mission" else Color.WHITE
		draw_circle(c + Vector2(mp.x, mp.z) * s, 7.0, col)
		draw_string(font, c + Vector2(mp.x, mp.z) * s + Vector2(10, 5), m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	var p: Vector3 = game.player.global_position
	var xf := Transform2D(-game.player.heading + PI, c + Vector2(p.x, p.z) * s)
	draw_set_transform_matrix(xf)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -12), Vector2(8, 9), Vector2(-8, 9)]), CKUI.BRIGHT)
	draw_set_transform_matrix(Transform2D())
	draw_string(font, Vector2(size.x / 2 - 6, 24), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, CKUI.MUTED)
	# legend
	var ly := size.y - 70.0
	for item in [[CKUI.BRIGHT, "Street crime"], [Color("#ffc040"), "Mission"], [Color.WHITE, "Waypoint (click to set, right-click to clear)"],
			[Color(0.4, 0.7, 1.0), "Your vehicles"]]:
		draw_circle(Vector2(18, ly), 5, item[0])
		draw_string(font, Vector2(30, ly + 5), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, CKUI.MUTED)
		ly += 17
	for v in game.drive.vehicles.values():
		draw_circle(c + Vector2(v.global_position.x, v.global_position.z) * s, 5.0, Color(0.4, 0.7, 1.0))
	if game.underground:
		draw_string(font, Vector2(16, size.y - 16), "You are in the Red Citadel (below the entrance).", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CKUI.MUTED)
