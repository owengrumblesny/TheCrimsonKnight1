class_name MapView
extends Control
## Top-down district map drawn from the loaded district geometry (port of the map canvas in
## ui/MenuManager.ts). North (-Z) is up; the red triangle is the player. Redraws 4x a second.

var game: Node
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(640, 400)
	clip_contents = true


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
		var col := CKUI.BRIGHT if m["kind"] == "crime" else Color("#ffc040")
		draw_circle(c + Vector2(mp.x, mp.z) * s, 7.0, col)
		draw_string(font, c + Vector2(mp.x, mp.z) * s + Vector2(10, 5), m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	var p: Vector3 = game.player.global_position
	var xf := Transform2D(-game.player.heading + PI, c + Vector2(p.x, p.z) * s)
	draw_set_transform_matrix(xf)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -12), Vector2(8, 9), Vector2(-8, 9)]), CKUI.BRIGHT)
	draw_set_transform_matrix(Transform2D())
	draw_string(font, Vector2(size.x / 2 - 6, 24), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, CKUI.MUTED)
	if game.underground:
		draw_string(font, Vector2(16, size.y - 16), "You are in the Red Citadel (below the entrance).", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CKUI.MUTED)
