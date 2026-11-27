class_name Game
extends RefCounted
## All game rules and state. No drawing here, so it can be tested headless.

# ---------- Tuning ----------
const COLS := 14
const ROWS := 17
const START := Vector2i(3, 8)          # head start cell, moving right
const PTS_LETTER := 10
const PTS_TARGET := 100                # x level, for making the given word
const PTS_OWN_WORD := 250              # x level, for making a different real word
const FREQ := "EEEEEEAAAAARRRRIIIIOOOOTTTTNNNNSSSSLLLCCCUUUDDPPMMHHGGBBFYWKV"
const OBSTACLE_TYPES: Array[String] = ["fence", "rock", "bush", "crate"]
const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]


static func word_len(level: int) -> int:
	return 5 if level <= 4 else 6                       # 6-letter words from level 5


static func step_time(level: int) -> float:
	return maxf(0.26, pow(0.9, level - 1))              # seconds per move; level 1 = 1 move/sec


static func obstacle_pieces(level: int) -> int:
	return mini(7 + 2 * (level - 1), 18)


static func obstacle_size(level: int) -> int:
	return mini(2 + (level - 1) / 2, 5)


# ---------- State ----------
var rng := RandomNumberGenerator.new()
var level := 1
var n := 5                             # current word length
var score := 0
var found: Array[String] = []
var target := ""
var word: Array[String] = []
var snake: Array[Vector2i] = []        # [0] is the head
var prev: Array[Vector2i] = []         # positions before the last move (for smooth drawing)
var dir := Vector2i.RIGHT
var queue: Array[Vector2i] = []
var items: Array[Dictionary] = []      # {pos: Vector2i, ch: String, born: float}
var wall := {}                         # Vector2i -> true
var obs := {}                          # Vector2i -> {type: String, piece: int}


func _init(seed_value := -1) -> void:
	Words.ensure_loaded()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


static func wrap_cell(p: Vector2i) -> Vector2i:
	return Vector2i(posmod(p.x, COLS), posmod(p.y, ROWS))


func pick(a: Array) -> Variant:
	return a[rng.randi_range(0, a.size() - 1)]


func prefix() -> String:
	return "".join(PackedStringArray(word))


func on_track() -> bool:
	return target.begins_with(prefix())


func setup_level(lvl: int) -> void:
	level = lvl
	n = word_len(lvl)
	build_arena()
	target = pick(Array(Words.dict[n]))
	word = [target[0]]
	snake = [START, START + Vector2i.LEFT]
	prev = snake.duplicate()
	dir = Vector2i.RIGHT
	queue.clear()
	items.clear()
	fill_board()


# ---------- Arena ----------
func flood(block: Dictionary, from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var q: Array[Vector2i] = [from]
	var i := 0
	while i < q.size():
		var p := q[i]
		i += 1
		for d in DIRS:
			var np := wrap_cell(p + d)
			if block.has(np) or dist.has(np):
				continue
			dist[np] = dist[p] + 1
			q.append(np)
	return dist


func _blob(count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	while cells.size() < count:
		var c: Vector2i = pick(cells) + pick(DIRS)
		if not cells.has(c):
			cells.append(c)
	return cells


func _shape(type: String, s: int) -> Array[Vector2i]:
	match type:
		"fence":
			var out: Array[Vector2i] = []
			var horiz := rng.randi() % 2 == 0
			for i in 3 + rng.randi_range(0, s - 1):
				out.append(Vector2i(i, 0) if horiz else Vector2i(0, i))
			return out
		"rock":
			return _blob(2 + rng.randi_range(0, s - 1))
		"bush":
			return _blob(1 + rng.randi_range(0, s - 1))
		_:
			var opts: Array = [[Vector2i(0, 0)], [Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(0, 0), Vector2i(0, 1)],
				[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]]
			var out: Array[Vector2i] = []
			out.assign(opts[mini(3, rng.randi_range(0, s))])
			return out


func _in_runway(p: Vector2i) -> bool:
	return absi(p.y - START.y) <= 1 and p.x >= START.x - 2 and p.x <= START.x + 5


func _fits(cells: Array[Vector2i], w: Dictionary) -> bool:
	for c in cells:
		if c.x < 0 or c.y < 0 or c.x >= COLS or c.y >= ROWS or _in_runway(c):
			return false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if w.has(wrap_cell(c + Vector2i(dx, dy))):     # keep a gap between pieces
					return false
	return true


## Random rocks, fences, bushes and crates. More and bigger pieces at higher levels.
## Layouts that trap open space are rerolled, so every letter is always reachable.
func build_arena() -> void:
	for attempt in 30:
		var w := {}
		var o := {}
		var placed := 0
		var tries := 0
		while placed < obstacle_pieces(level) and tries < 400:
			tries += 1
			var type: String = pick(OBSTACLE_TYPES)
			var origin := Vector2i(rng.randi_range(0, COLS - 1), rng.randi_range(0, ROWS - 1))
			var cells: Array[Vector2i] = []
			for c in _shape(type, obstacle_size(level)):
				cells.append(origin + c)
			if not _fits(cells, w):
				continue
			for c in cells:
				w[c] = true
				o[c] = {"type": type, "piece": placed}
			placed += 1
		var seen := flood(w, START)
		var sealed := COLS * ROWS - w.size() - seen.size()
		if sealed > 4 and attempt < 29:
			continue
		for y in ROWS:
			for x in COLS:
				var p := Vector2i(x, y)
				if not seen.has(p) and not w.has(p):
					w[p] = true
					o[p] = {"type": "rock", "piece": -1}
		_fill_dead_ends(w, o)
		wall = w
		obs = o
		return


## The snake can't reverse, so a one-cell nook is a death trap. Fill them in with rock.
func _fill_dead_ends(w: Dictionary, o: Dictionary) -> void:
	var changed := true
	while changed:
		changed = false
		for y in ROWS:
			for x in COLS:
				var p := Vector2i(x, y)
				if w.has(p) or _in_runway(p):
					continue
				var shut := 0
				for d in DIRS:
					if w.has(wrap_cell(p + d)):
						shut += 1
				if shut >= 3:
					w[p] = true
					o[p] = {"type": "rock", "piece": -1}
					changed = true


## How many of p's four neighbours are blocked by obstacles or letters (plus an optional extra cell)?
func _shut_sides(p: Vector2i, extra := Vector2i(-1, -1)) -> int:
	var shut := 0
	for d in DIRS:
		var q := wrap_cell(p + d)
		if wall.has(q) or q == extra or _item_at(q) >= 0:
			shut += 1
	return shut


func _item_at(p: Vector2i) -> int:
	for i in items.size():
		if items[i]["pos"] == p:
			return i
	return -1


## A letter at `spot` must not leave any neighbouring open cell (or itself) as a dead end.
func _safe_spot(spot: Vector2i) -> bool:
	if _shut_sides(spot) >= 2:
		return false
	for d in DIRS:
		var q := wrap_cell(spot + d)
		if not wall.has(q) and _shut_sides(q, spot) >= 3:
			return false
	return true


# ---------- Letters ----------
func _count(ch: String) -> int:
	var k := 0
	for it in items:
		if it["ch"] == ch:
			k += 1
	return k


func _reachable(ch: String, dist: Dictionary) -> bool:
	for it in items:
		if it["ch"] == ch and dist.has(it["pos"]):
			return true
	return false


func _place(ch: String, spots: Array) -> void:
	if spots.is_empty():
		return
	var p: Vector2i = spots.pop_at(rng.randi_range(0, spots.size() - 1))
	items.append({"pos": p, "ch": ch, "born": Time.get_ticks_msec() / 1000.0})


## Keep the board solvable: the target's next letter (or, once off-script, a letter that
## continues some real word) is always on the board, with a clear path to it that doesn't
## cross any other letter. The rest are mostly decoys, placed so they never block that path.
func fill_board() -> void:
	var p := prefix()
	var valid := Words.next_letters(p, n)
	var goals: Array[String] = valid
	if target.begins_with(p):
		goals = [target[p.length()]]
	var block := wall.duplicate()
	for i in range(1, snake.size()):
		block[snake[i]] = true
	var taken := {}
	for it in items:
		taken[it["pos"]] = true
	# Spots reachable without crossing any letter
	var clear_block := block.duplicate()
	clear_block.merge(taken)
	var clear_dist := flood(clear_block, snake[0])
	if not _goal_reachable(goals):
		var spots := _open_spots(clear_dist, taken, 3)
		if spots.is_empty():
			spots = _open_spots(clear_dist, taken, 1)
		var need: String = goals[0] if goals.size() == 1 else (pick(Words.words_from(p, n)) as String)[p.length()]
		var safe := spots.filter(_safe_spot)
		_place(need, safe if not safe.is_empty() else spots)
		taken[items.back()["pos"]] = true
	var dist := flood(block, snake[0])
	var spots := _open_spots(dist, taken, 3)
	if spots.size() < 6:
		spots = _open_spots(dist, taken, 1)
	var want := 6 + mini(level, 4)
	var guard := 0
	while items.size() < want and not spots.is_empty() and guard < 300:
		guard += 1
		var c := FREQ[rng.randi_range(0, FREQ.length() - 1)]
		if valid.has(c) and rng.randf() < 0.7:
			continue
		if _count(c) >= 2:
			continue
		var spot: Vector2i = spots.pop_at(rng.randi_range(0, spots.size() - 1))
		if not _safe_spot(spot) or (not goals.has(c) and not _goal_reachable(goals, spot)):
			continue          # this decoy would wall off the letter you need
		items.append({"pos": spot, "ch": c, "born": Time.get_ticks_msec() / 1000.0})


## Can the head reach a tile with one of `goals` without crossing another letter?
func _goal_reachable(goals: Array[String], extra := Vector2i(-1, -1)) -> bool:
	var block := wall.duplicate()
	for i in range(1, snake.size()):
		block[snake[i]] = true
	for it in items:
		if not goals.has(it["ch"]):
			block[it["pos"]] = true
	if extra.x >= 0:
		block[extra] = true
	var dist := flood(block, snake[0])
	for it in items:
		if goals.has(it["ch"]) and dist.has(it["pos"]):
			return true
	return false


func _open_spots(dist: Dictionary, taken: Dictionary, min_dist: int) -> Array:
	var out := []
	for p in dist:
		if dist[p] >= min_dist and not taken.has(p):
			out.append(p)
	return out


# ---------- Moving ----------
## Queue a turn. Returns true if it was accepted (not a reverse or repeat).
func set_dir(d: Vector2i) -> bool:
	var last: Vector2i = queue.back() if not queue.is_empty() else dir
	if d == -last or d == last or queue.size() >= 3:
		return false
	queue.append(d)
	return true


## Advance one cell. Returns an event: move, eat, complete or over.
func step() -> Dictionary:
	if not queue.is_empty():
		dir = queue.pop_front()
	prev = snake.duplicate()
	var head := wrap_cell(snake[0] + dir)
	var idx := -1
	for i in items.size():
		if items[i]["pos"] == head:
			idx = i
			break
	var grow := idx >= 0
	if wall.has(head):
		return {"event": "over", "why": "wall", "pos": head}
	var check := snake.size() if grow else snake.size() - 1
	for i in check:
		if snake[i] == head:
			return {"event": "over", "why": "self", "pos": head}
	snake.push_front(head)
	if not grow:
		snake.pop_back()
		return {"event": "move"}
	var it: Dictionary = items.pop_at(idx)
	word.append(it["ch"])
	score += PTS_LETTER
	var p := prefix()
	if not Words.is_prefix(p, n):
		return {"event": "over", "why": "word", "prefix": p, "pos": head}
	if p.length() == n:
		var own := p != target
		var pts := (PTS_OWN_WORD if own else PTS_TARGET) * level
		score += pts
		found.append(p)
		return {"event": "complete", "word": p, "own": own, "pts": pts, "pos": head}
	fill_board()
	return {"event": "eat", "ch": it["ch"], "pos": head}


## Helpful line for the game-over screen.
func over_tip(ev: Dictionary) -> String:
	var so_far: String = (ev["prefix"] as String).left(-1) if ev["why"] == "word" else prefix()
	if target.begins_with(so_far):
		return "You were on track for %s." % target
	return "From %s you could have made %s." % [so_far, pick(Words.words_from(so_far, n))]
