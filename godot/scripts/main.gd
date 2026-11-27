extends Control
## Screen layout, menus, input, timing and effects. Rules live in game.gd, drawing in board.gd.

enum Mode { MENU, READY, PLAY, PAUSED, WON, OVER }

const SAVE_PATH := "user://save.cfg"
const SWIPE_DIST := 40.0

var game := Game.new()
var mode := Mode.MENU
var acc := 0.0                 # time into the current move
var last_step_ms := 0
var best := 0
var token := 0                 # invalidates old timers when a new level/game starts
var touch_start := Vector2.ZERO
var touching := false
var board_home := Vector2.ZERO

var board: Board
var board_holder: Control
var toast_layer: CenterContainer
var slots_box: HBoxContainer
var target_label: Label
var lvl_label: Label
var score_label: Label
var best_label: Label
var found_label: Label
var overlay: Control
var card_box: VBoxContainer
var blobs: Array[TextureRect] = []


func _ready() -> void:
	_load_best()
	_build_ui()
	game.setup_level(1)
	board.game = game
	_refresh_hud()
	_show_menu()


# =====================================================================
# Layout
# =====================================================================
func _label(text: String, size: int, color: Color, font: Font = Palette.FONT_SEMI) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _panel(sb: StyleBox) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	return p


func _button(text: String, cb: Callable, bg := Palette.MINT, fg := Palette.MINT_INK, min_size := Vector2(300, 96)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Palette.FONT_BOLD)
	b.add_theme_font_size_override("font_size", 36)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var col := bg.darkened(0.08) if state == "pressed" else bg
		b.add_theme_stylebox_override(state, Palette.box(col, 28, Vector2(24, 12), 0, Color.TRANSPARENT, 6, bg.darkened(0.2)))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, fg)
	b.pressed.connect(cb)
	return b


func _pill(prefix: String) -> Label:
	var p := _panel(Palette.box(Palette.CARD, 40, Vector2(22, 10), 2, Palette.LINE))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(_label(prefix, 26, Palette.MUTED))
	var v := _label("0", 26, Palette.INK, Palette.FONT_BOLD)
	h.add_child(v)
	p.add_child(h)
	_pills_row.add_child(p)
	return v


var _pills_row: HBoxContainer


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	for col in [Color("ffd6a5"), Color("bdf0f5")]:
		var g := Gradient.new()
		g.set_color(0, col)
		g.set_color(1, Color(col, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 512
		tex.height = 512
		var tr := TextureRect.new()
		tr.texture = tex
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size = Vector2(1000, 760)
		add_child(tr)
		blobs.append(tr)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 32)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	margin.add_child(vb)

	# Title row
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	var logo := HBoxContainer.new()
	logo.add_theme_constant_override("separation", 6)
	for col in [Palette.TILES[0], Palette.TILES[2], Palette.TILES[3]]:
		var dot := _panel(Palette.box(col, 8))
		dot.custom_minimum_size = Vector2(24, 24)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		logo.add_child(dot)
	top.add_child(logo)
	top.add_child(_label("Word Snake", 52, Palette.INK, Palette.FONT_BLACK))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var pause := _button("II", toggle_pause, Palette.CARD, Palette.INK, Vector2(88, 88))
	pause.add_theme_font_size_override("font_size", 30)
	top.add_child(pause)
	vb.add_child(top)

	_pills_row = HBoxContainer.new()
	_pills_row.add_theme_constant_override("separation", 12)
	vb.add_child(_pills_row)
	lvl_label = _pill("Level")
	score_label = _pill("Score")
	best_label = _pill("Best")

	# Target word card
	var tcard := _panel(Palette.box(Palette.CARD, 36, Vector2(20, 16), 2, Palette.LINE))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 12)
	target_label = _label("Make this word", 26, Palette.MUTED)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(target_label)
	slots_box = HBoxContainer.new()
	slots_box.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_box.add_theme_constant_override("separation", 12)
	tv.add_child(slots_box)
	tcard.add_child(tv)
	vb.add_child(tcard)

	# Board
	board_holder = Control.new()
	board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_holder.resized.connect(_layout_board)
	vb.add_child(board_holder)
	board = Board.new()
	board_holder.add_child(board)
	toast_layer = CenterContainer.new()
	toast_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_holder.add_child(toast_layer)

	found_label = _label("", 24, Palette.MUTED)
	found_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	found_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(found_label)

	# Arrow pad on touch screens. To preview it on a computer, run with:  godot --path . -- --touch
	if DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch"):
		var pad := HBoxContainer.new()
		pad.alignment = BoxContainer.ALIGNMENT_CENTER
		pad.add_theme_constant_override("separation", 16)
		var glyph := {Vector2i.LEFT: "←", Vector2i.UP: "↑", Vector2i.DOWN: "↓", Vector2i.RIGHT: "→"}
		for d: Vector2i in glyph:
			var b := _button(glyph[d], func() -> void: set_dir(d), Palette.CARD, Palette.INK, Vector2(140, 96))
			b.add_theme_font_size_override("font_size", 44)
			b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
			pad.add_child(b)
		vb.add_child(pad)

	# Overlay for menus
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.07, 0.13, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var card := _panel(Palette.box(Palette.CARD, 44, Vector2(40, 36)))
	card.custom_minimum_size = Vector2(580, 0)
	center.add_child(card)
	card_box = VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 18)
	card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(card_box)

	resized.connect(_layout_bg)
	_layout_bg()


func _layout_bg() -> void:
	if blobs.size() == 2:
		blobs[0].position = Vector2(-500, -380)
		blobs[1].position = Vector2(size.x - 500, -300)


func _layout_board() -> void:
	var avail := board_holder.size
	var c := floorf(minf(avail.x / Game.COLS, avail.y / Game.ROWS))
	c = clampf(c, 18.0, 90.0)
	board.cell = c
	board.size = Vector2(c * Game.COLS, c * Game.ROWS)
	board_home = ((avail - board.size) / 2.0).floor()
	board.position = board_home
	board.pivot_offset = board.size / 2.0


# =====================================================================
# HUD
# =====================================================================
func _refresh_hud(pop_last := false) -> void:
	lvl_label.text = str(game.level)
	score_label.text = str(game.score)
	best_label.text = str(maxi(best, game.score))
	var track := game.on_track()
	target_label.text = "Make this word" if track else "Off script! Finish any real word for bonus points"
	target_label.add_theme_color_override("font_color", Palette.MUTED if track else Palette.OFF)
	target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if slots_box.get_child_count() != game.n:
		for ch in slots_box.get_children():
			ch.queue_free()
			slots_box.remove_child(ch)
		for i in game.n:
			var s := PanelContainer.new()
			s.custom_minimum_size = Vector2(88, 100)
			var l := _label("", 58, Palette.INK, Palette.FONT_BOLD)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			s.add_child(l)
			slots_box.add_child(s)
	for i in game.n:
		var s: PanelContainer = slots_box.get_child(i)
		var l: Label = s.get_child(0)
		if i < game.word.size():
			var col := Palette.tile_color(game.word[i])
			s.add_theme_stylebox_override("panel", Palette.box(col, 22, Vector2.ZERO, 0, Color.TRANSPARENT, 8, col.darkened(0.2)))
			l.text = game.word[i]
			l.add_theme_color_override("font_color", Palette.TILE_INK)
		else:
			var edge := Palette.MINT if i == game.word.size() else Palette.LINE
			s.add_theme_stylebox_override("panel", Palette.box(Color(1, 1, 1, 0), 22, Vector2.ZERO, 4, edge))
			l.text = game.target[i] if track else ""
			l.add_theme_color_override("font_color", Color(Palette.MUTED, 0.5))
	if pop_last and game.word.size() > 0 and game.word.size() <= game.n:
		var s: Control = slots_box.get_child(game.word.size() - 1)
		s.pivot_offset = s.custom_minimum_size / 2.0
		s.scale = Vector2(0.6, 0.6)
		create_tween().tween_property(s, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	found_label.visible = not game.found.is_empty()
	found_label.text = ("Spelled: " + "  ·  ".join(PackedStringArray(game.found))) if not game.found.is_empty() else ""


# =====================================================================
# Overlay cards
# =====================================================================
func _card(parts: Array) -> void:
	for ch in card_box.get_children():
		ch.queue_free()
	for p in parts:
		card_box.add_child(p)
	overlay.show()


func _text_line(text: String, size := 30, color := Palette.MUTED) -> Label:
	var l := _label(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	return l


func _chips(w: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	for ch in w:
		var col := Palette.tile_color(ch)
		var p := _panel(Palette.box(col, 20, Vector2.ZERO, 0, Color.TRANSPARENT, 7, col.darkened(0.2)))
		p.custom_minimum_size = Vector2(76, 86)
		var l := _label(ch, 50, Palette.TILE_INK, Palette.FONT_BOLD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
		h.add_child(p)
	return h


func _centered(c: Control) -> Control:
	var cc := CenterContainer.new()
	cc.add_child(c)
	return cc


func _show_menu() -> void:
	mode = Mode.MENU
	var rules := VBoxContainer.new()
	rules.add_theme_constant_override("separation", 10)
	for line in ["Steer the snake to eat the letters of the word shown, in order.",
			"Spell a different real word instead for bonus points.",
			"Eat a letter that can't make any word and it's game over.",
			"Go off one edge to come back on the other side."]:
		var l := _label("•  " + line, 30, Palette.INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(500, 0)
		rules.add_child(l)
	_card([_text_line("Word Snake", 50, Palette.INK), rules, _centered(_button("Play", new_game))])


func _show_ready() -> void:
	var parts: Array = [_text_line("Level %d" % game.level), _text_line("Make this word", 46, Palette.INK), _chips(game.target)]
	if game.level > 1 and Game.word_len(game.level) > Game.word_len(game.level - 1):
		parts.append(_text_line("Now with %d-letter words!" % game.n, 30, Palette.INK))
	parts.append(_text_line("Tap, swipe or press a key to go", 28))
	_card(parts)


func _on_overlay_input(event: InputEvent) -> void:
	if mode == Mode.READY and ((event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)):
		go()


func _toast(title: String, sub: String) -> void:
	var p := _panel(Palette.box(Palette.CARD, 32, Vector2(36, 22)))
	var v := VBoxContainer.new()
	var a := _label(title, 40, Palette.INK, Palette.FONT_BLACK)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := _label(sub, 28, Palette.MUTED)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	v.add_child(b)
	p.add_child(v)
	toast_layer.add_child(p)
	p.modulate = Color(1, 1, 1, 0)
	await get_tree().process_frame
	p.pivot_offset = p.size / 2.0
	p.scale = Vector2(0.7, 0.7)
	var tw := create_tween().set_parallel()
	tw.tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


# =====================================================================
# Game flow
# =====================================================================
func new_game() -> void:
	game = Game.new()
	board.game = game
	start_level(1)


func start_level(lvl: int) -> void:
	token += 1
	game.setup_level(lvl)
	board.crashed = false
	board.won_since = -1.0
	board.position = board_home
	mode = Mode.READY
	_refresh_hud()
	_show_ready()
	var my := token
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if my == token and mode == Mode.READY:
			go())


func go() -> void:
	mode = Mode.PLAY
	overlay.hide()
	acc = 0.0
	last_step_ms = Time.get_ticks_msec()


func set_dir(d: Vector2i) -> void:
	if mode == Mode.READY:
		go()
	if mode != Mode.PLAY:
		return
	if game.set_dir(d) and game.queue.size() == 1 and Time.get_ticks_msec() - last_step_ms > 150:
		acc = Game.step_time(game.level)     # at slow speeds, turn right away


func toggle_pause() -> void:
	if mode == Mode.PLAY:
		mode = Mode.PAUSED
		_card([_text_line("Paused", 50, Palette.INK), _text_line("Making %s" % game.target), _centered(_button("Resume", toggle_pause))])
	elif mode == Mode.PAUSED:
		go()


func _process(delta: float) -> void:
	if mode == Mode.PLAY:
		acc += minf(delta, 0.25)
		var iv := Game.step_time(game.level)
		while acc >= iv and mode == Mode.PLAY:
			acc -= iv
			_do_step()
	board.t = clampf(acc / Game.step_time(game.level), 0.0, 1.0) if mode == Mode.PLAY else 1.0
	board.queue_redraw()


func _do_step() -> void:
	last_step_ms = Time.get_ticks_msec()
	var ev := game.step()
	match ev["event"]:
		"eat":
			_burst(ev["pos"], Palette.tile_color(ev["ch"]))
			_refresh_hud(true)
		"complete":
			_burst(ev["pos"], Palette.GOLD, 40)
			mode = Mode.WON
			board.won_since = Time.get_ticks_msec() / 1000.0
			_save_best()
			_refresh_hud(true)
			_toast(("Bonus word! " + ev["word"]) if ev["own"] else ev["word"], "+%d points" % ev["pts"])
			var my := token
			get_tree().create_timer(1.7).timeout.connect(func() -> void:
				if my == token:
					start_level(game.level + 1))
		"over":
			_game_over(ev)


func _game_over(ev: Dictionary) -> void:
	mode = Mode.OVER
	board.crashed = true
	_save_best()
	_refresh_hud()
	_burst(ev["pos"], Color("ff6b6b"), 30)
	var tw := create_tween()
	for i in 6:
		tw.tween_property(board, "position", board_home + Vector2(randf_range(-14, 14), randf_range(-10, 10)), 0.04)
	tw.tween_property(board, "position", board_home, 0.05)
	var head: String = {"wall": "Ouch, an obstacle!", "self": "You bit your own tail", "word": "No word starts with %s" % ev.get("prefix", "")}[ev["why"]]
	var words := ("Words: " + ", ".join(PackedStringArray(game.found))) if not game.found.is_empty() else "No words yet"
	var my := token
	await get_tree().create_timer(0.6).timeout
	if my != token or mode != Mode.OVER:
		return
	_card([_text_line(head, 44, Palette.INK), _text_line(game.over_tip(ev)),
		_text_line(str(game.score), 96, Palette.INK), _text_line("%s  ·  Best %d" % [words, best], 26),
		_centered(_button("Play again", new_game))])


func _burst(cell_pos: Vector2i, col: Color, amount := 18) -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2((cell_pos.x + 0.5) * board.cell, (cell_pos.y + 0.5) * board.cell)
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.7
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = board.cell * 2.5
	p.initial_velocity_max = board.cell * 6.0
	p.gravity = Vector2(0, board.cell * 12.0)
	p.texture = _dot_texture()
	p.scale_amount_min = board.cell * 0.22 / 32.0
	p.scale_amount_max = board.cell * 0.42 / 32.0
	var ramp := Gradient.new()
	ramp.set_color(0, col)
	ramp.set_color(1, Color(col, 0.0))
	p.color_ramp = ramp
	board.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


var _dot: Texture2D


func _dot_texture() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		g.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 32
		tex.height = 32
		_dot = tex
	return _dot


# =====================================================================
# Input
# =====================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP, KEY_W: set_dir(Vector2i.UP)
			KEY_DOWN, KEY_S: set_dir(Vector2i.DOWN)
			KEY_LEFT, KEY_A: set_dir(Vector2i.LEFT)
			KEY_RIGHT, KEY_D: set_dir(Vector2i.RIGHT)
			KEY_SPACE, KEY_P:
				if mode == Mode.READY:
					go()
				else:
					toggle_pause()
			KEY_ENTER, KEY_KP_ENTER:
				if mode == Mode.OVER or mode == Mode.MENU:
					new_game()
	elif event is InputEventScreenTouch:
		touching = event.pressed
		touch_start = event.position
	elif event is InputEventScreenDrag and touching:
		var d: Vector2 = event.position - touch_start
		if maxf(absf(d.x), absf(d.y)) >= SWIPE_DIST:
			if absf(d.x) > absf(d.y):
				set_dir(Vector2i(signi(int(d.x)), 0))
			else:
				set_dir(Vector2i(0, signi(int(d.y))))
			touch_start = event.position


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			if mode == Mode.PLAY:
				toggle_pause()
		NOTIFICATION_WM_GO_BACK_REQUEST:      # Android back button
			if mode == Mode.PLAY:
				toggle_pause()
			else:
				get_tree().quit()


# =====================================================================
# Saving
# =====================================================================
func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("scores", "best", 0))


func _save_best() -> void:
	if game.score > best:
		best = game.score
		var cfg := ConfigFile.new()
		cfg.set_value("scores", "best", best)
		cfg.save(SAVE_PATH)
