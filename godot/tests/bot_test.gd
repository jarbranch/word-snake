extends SceneTree
## Plays the game rules automatically to check every level stays solvable.
## Run:  godot --headless --path . -s tests/bot_test.gd

const LEVELS := 8
const GAMES := 20


func _initialize() -> void:
	var failures := 0
	for g in GAMES:
		var game := Game.new(g)
		game.setup_level(1)
		var steps := 0
		var stuck := 0
		while game.level <= LEVELS and steps < 20000:
			steps += 1
			var d := _route(game)
			if d == Vector2i.ZERO:
				stuck += 1            # own body in the way: wander safely until it clears
				d = _safe_move(game)
				if stuck > 60 or d == Vector2i.ZERO:
					push_error("Game %d level %d: no safe path to the next letter (stuck=%d, d=%s, reachable=%s, len=%d, want=%s, items=%s)" % [g, game.level, stuck, d, game._goal_reachable([game.target[game.word.size()]] as Array[String]), game.snake.size(), game.target[game.word.size()], game.items.map(func(it): return "%s@%s" % [it["ch"], it["pos"]])])
					failures += 1
					if failures == 1: _dump(game)
					break
			else:
				stuck = 0
			if d != game.dir:
				game.set_dir(d)
			var ev := game.step()
			if ev["event"] == "over":
				push_error("Game %d level %d: bot died (%s) on %s" % [g, game.level, ev["why"], game.prefix()])
				failures += 1
				break
			if ev["event"] == "complete":
				game.setup_level(game.level + 1)
		_check_arena(game)
	print("bot_test: %d games x %d levels, %d failures" % [GAMES, LEVELS, failures])
	quit(1 if failures > 0 else 0)


## Breadth-first search to the nearest tile with the target's next letter, avoiding everything else.
func _route(game: Game) -> Vector2i:
	var want := game.target[game.word.size()]
	var block := game.wall.duplicate()
	for i in range(0, game.snake.size() - 1):
		block[game.snake[i]] = true
	var goals := {}
	for it in game.items:
		if it["ch"] == want:
			goals[it["pos"]] = true
		else:
			block[it["pos"]] = true
	var head := game.snake[0]
	var first := {}
	var q: Array[Vector2i] = []
	for d in Game.DIRS:
		if d == -game.dir:
			continue
		var p := Game.wrap_cell(head + d)
		if block.has(p) and not goals.has(p):
			continue
		if goals.has(p):
			return d
		first[p] = d
		q.append(p)
	var i := 0
	while i < q.size():
		var p := q[i]
		i += 1
		for d in Game.DIRS:
			var np := Game.wrap_cell(p + d)
			if first.has(np) or np == head:
				continue
			if goals.has(np):
				return first[p]
			if block.has(np):
				continue
			first[np] = first[p]
			q.append(np)
	return Vector2i.ZERO


func _dump(game: Game) -> void:
	for y in Game.ROWS:
		var row := ""
		for x in Game.COLS:
			var p := Vector2i(x, y)
			var ch := "."
			if game.wall.has(p): ch = "#"
			for it in game.items:
				if it["pos"] == p: ch = (it["ch"] as String).to_lower()
			var si := game.snake.find(p)
			if si == 0: ch = "@"
			elif si > 0: ch = "o"
			row += ch
		print(row)
	print("dir=", game.dir, " word=", game.prefix(), " target=", game.target)


func _safe_move(game: Game) -> Vector2i:
	var want := game.target[game.word.size()]
	for d in Game.DIRS:
		if d == -game.dir:
			continue
		var p := Game.wrap_cell(game.snake[0] + d)
		if game.wall.has(p) or game.snake.slice(0, -1).has(p):
			continue
		var bad := false
		for it in game.items:
			if it["pos"] == p and it["ch"] != want:
				bad = true
		if not bad:
			return d
	return Vector2i.ZERO


func _check_arena(game: Game) -> void:
	var seen := game.flood(game.wall, Game.START)
	assert(seen.size() + game.wall.size() == Game.COLS * Game.ROWS, "arena has unreachable cells")
