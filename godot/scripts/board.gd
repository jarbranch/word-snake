class_name Board
extends Control
## Draws the arena: dotted grid, obstacles, letter tiles and the gliding snake.

var game: Game
var cell := 40.0
var t := 1.0                  # 0..1 progress through the current move, for smooth gliding
var won_since := -1.0         # time a word was completed (gold glow), or -1
var crashed := false
var _sb := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sb.anti_aliasing = true


func _rrect(r: Rect2, col: Color, radius: float) -> void:
	_sb.bg_color = col
	_sb.set_corner_radius_all(int(radius))
	draw_style_box(_sb, r)


func _circ(p: Vector2, r: float, col: Color) -> void:
	draw_circle(p, r, col, true, -1.0, true)


func _text(s: String, center: Vector2, size: int, col: Color) -> void:
	if size < 2:
		return
	draw_string(Palette.FONT_BOLD, Vector2(center.x - 200, center.y + size * 0.36), s,
		HORIZONTAL_ALIGNMENT_CENTER, 400, size, col)


func _center(p: Vector2i) -> Vector2:
	return Vector2((p.x + 0.5) * cell, (p.y + 0.5) * cell)


func _draw() -> void:
	var c := cell
	_rrect(Rect2(Vector2.ZERO, Vector2(c * Game.COLS, c * Game.ROWS)), Palette.BOARD, c * 0.6)
	for y in Game.ROWS:
		for x in Game.COLS:
			_circ(_center(Vector2i(x, y)), maxf(1.5, c * 0.06), Color(1, 1, 1, 0.07))
	if game == null or game.snake.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for p: Vector2i in game.obs:
		_draw_obstacle(p, game.obs[p])
	for it in game.items:
		_draw_tile(it, now)
	_draw_snake(now)


# ---------- Obstacles ----------
func _hash(p: Vector2i) -> float:
	return float(((p.x * 73856093) ^ (p.y * 19349663)) & 0xFFFF) / 65535.0


func _draw_obstacle(p: Vector2i, o: Dictionary) -> void:
	var c := cell
	var ctr := _center(p)
	var shadow := Color(0, 0, 0, 0.3)
	match o["type"]:
		"rock":
			_circ(ctr + Vector2(0, c * 0.08), c * 0.44, shadow)
			_circ(ctr + Vector2(-c * 0.1, 0), c * 0.34, Color("7c879e"))
			_circ(ctr + Vector2(c * 0.14, c * 0.06), c * 0.28, Color("6a7590"))
			_circ(ctr + Vector2(-c * 0.14, -c * 0.1), c * 0.14, Color("a3adc2"))
			if _hash(p) > 0.5:
				_circ(ctr + Vector2(c * 0.16, -c * 0.04), c * 0.06, Color("b9c1d3"))
		"bush":
			_circ(ctr + Vector2(0, c * 0.08), c * 0.44, shadow)
			_circ(ctr + Vector2(-c * 0.16, c * 0.06), c * 0.26, Color("237a35"))
			_circ(ctr + Vector2(c * 0.16, c * 0.06), c * 0.26, Color("237a35"))
			_circ(ctr + Vector2(0, -c * 0.1), c * 0.3, Color("2f9e44"))
			_circ(ctr + Vector2(-c * 0.08, -c * 0.16), c * 0.12, Color("51cf66"))
			if _hash(p) > 0.55:
				_circ(ctr + Vector2(c * 0.12, c * 0.1), c * 0.055, Color("ff6b6b"))
				_circ(ctr + Vector2(-c * 0.18, c * 0.14), c * 0.055, Color("ff6b6b"))
		"crate":
			var s := c * 0.84
			var r := Rect2(Vector2(p) * c + Vector2(c * 0.08, c * 0.08), Vector2(s, s))
			_rrect(Rect2(r.position + Vector2(0, c * 0.07), r.size), shadow, c * 0.08)
			_rrect(r, Color("c0884e"), c * 0.08)
			var inner := r.grow(-c * 0.07)
			draw_rect(inner, Color("8a5a2b"), false, c * 0.07, true)
			draw_line(inner.position + Vector2(c * 0.03, c * 0.03), inner.end - Vector2(c * 0.03, c * 0.03), Color("8a5a2b"), c * 0.07, true)
		_:  # fence: rails to neighbouring posts of the same fence, then the post
			for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var nb: Variant = game.obs.get(p + d)
				if nb != null and nb["type"] == "fence" and nb["piece"] == o["piece"]:
					for off in [-0.16, 0.16]:
						var shift := Vector2(0, off * c) if d.x != 0 else Vector2(off * c, 0)
						draw_line(ctr + shift, ctr + Vector2(d) * c + shift, Color("e0a96d"), c * 0.11, true)
			_rrect(Rect2(ctr + Vector2(-c * 0.14, -c * 0.28), Vector2(c * 0.28, c * 0.7)), shadow, c * 0.08)
			_rrect(Rect2(ctr + Vector2(-c * 0.14, -c * 0.34), Vector2(c * 0.28, c * 0.7)), Color("c98b4f"), c * 0.08)
			_rrect(Rect2(ctr + Vector2(-c * 0.14, -c * 0.34), Vector2(c * 0.28, c * 0.14)), Color("e8b47c"), c * 0.08)


# ---------- Letter tiles ----------
func _draw_tile(it: Dictionary, now: float) -> void:
	var c := cell
	var p: Vector2i = it["pos"]
	var a := clampf((now - float(it["born"])) / 0.24, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - a, 3.0)
	var bob := sin(now * 2.6 + p.x * 1.3 + p.y * 0.7) * c * 0.03
	var s := c * 0.96 * (0.4 + 0.6 * e)
	var ctr := _center(p) + Vector2(0, bob)
	var r := Rect2(ctr - Vector2(s, s) / 2.0, Vector2(s, s))
	_rrect(Rect2(r.position + Vector2(0, c * 0.07), r.size), Color(0, 0, 0, 0.35), c * 0.22)
	_rrect(r, Palette.tile_color(it["ch"]), c * 0.22)
	_text(it["ch"], ctr, int(c * 0.72 * e), Palette.TILE_INK)


# ---------- Snake ----------
func _draw_snake(now: float) -> void:
	var c := cell
	var pts: Array[Vector2] = []
	for i in game.snake.size():
		var s := game.snake[i]
		var f: Vector2i = game.prev[i] if i < game.prev.size() else s
		var d := Vector2(s - f)
		if d.x > 1: d.x -= Game.COLS
		if d.x < -1: d.x += Game.COLS
		if d.y > 1: d.y -= Game.ROWS
		if d.y < -1: d.y += Game.ROWS
		var x := fposmod(f.x + d.x * t, Game.COLS)
		var y := fposmod(f.y + d.y * t, Game.ROWS)
		pts.append(Vector2((x + 0.5) * c, (y + 0.5) * c))
	var count := pts.size()
	var hue := func(i: int) -> float: return (165.0 + 25.0 * i / maxf(1.0, count - 1)) / 360.0
	if won_since >= 0.0:
		var glow := 0.25 + 0.15 * sin((now - won_since) * 11.0)
		for p in pts:
			_circ(p, c * 0.75, Color(Palette.GOLD, glow))
	for i in range(count - 1, 0, -1):
		var a := pts[i]
		var b := pts[i - 1]
		if absf(a.x - b.x) > c * 1.5 or absf(a.y - b.y) > c * 1.5:
			continue      # wrapped across an edge
		draw_line(a, b, Color.from_hsv(hue.call(i), 0.72, 0.8), c * 0.78, true)
	for i in range(count - 1, -1, -1):
		var col := Color("38d9a9") if i == 0 else Color.from_hsv(hue.call(i), 0.62, 0.86)
		if crashed and i == 0:
			col = Color("ff6b6b")
		_circ(pts[i], c * (0.52 if i == 0 else 0.47), col)
	var wn := game.word.size()
	for i in range(1, count):
		if wn - i >= 0:
			_text(game.word[wn - i], pts[i] + Vector2(0, c * 0.02), int(c * 0.68), Palette.MINT_INK)
	var hd := pts[0]
	var dv := Vector2(game.dir)
	for side: float in [-1.0, 1.0]:
		var e := hd + dv * c * 0.14 + Vector2(dv.y, dv.x) * side * c * 0.2
		_circ(e, c * 0.13, Color.WHITE)
		if crashed:
			draw_line(e - Vector2(c, c) * 0.07, e + Vector2(c, c) * 0.07, Palette.BOARD, c * 0.04, true)
			draw_line(e + Vector2(-c, c) * 0.07, e + Vector2(c, -c) * 0.07, Palette.BOARD, c * 0.04, true)
		else:
			_circ(e + dv * c * 0.05, c * 0.065, Palette.BOARD)
