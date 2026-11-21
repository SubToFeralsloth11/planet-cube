extends SceneTree
## Headless liquid test: spreading/falling/draining water, cobble generator, obsidian, infinite water, save/load of flow.

var main
var w
var Bx
var fails := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		fails += 1
		print("FAIL ", what)


func _b(x: int, y: int, z: int) -> int:
	return w.get_b(x, y, z)


func _box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, id: int) -> void:
	for z in range(z0, z1 + 1):
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				w.set_block(x, y, z, id)


## Steps the simulation with a fake dt until no liquid cell is pending. Returns ticks used.
func _settle(maxn := 800) -> int:
	var n := 0
	while n < maxn:
		w.flow_tick(0.25, 1000)
		n += 1
		if w.flow_pending() == 0:
			break
	return n


func _count(id: int, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> int:
	var c := 0
	for z in range(z0, z1 + 1):
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if _b(x, y, z) == id:
					c += 1
	return c


func _run() -> void:
	while main.state != "title":
		await process_frame
	w = main.world
	Bx = root.get_node("B")
	# Carve a sealed lab on face +Y (down = -Y everywhere inside it): stone floor at y=94, stone walls around.
	for z in range(36, 93):
		for y in range(95, 122):
			for x in range(36, 93):
				if _b(x, y, z) != 0:
					w.set_block(x, y, z, 0)
	_box(36, 94, 36, 92, 94, 92, Bx.STONE)
	_box(35, 94, 35, 93, 121, 35, Bx.STONE)
	_box(35, 94, 93, 93, 121, 93, Bx.STONE)
	_box(35, 94, 35, 35, 121, 93, Bx.STONE)
	_box(93, 94, 35, 93, 121, 93, Bx.STONE)
	# Carving woke the planet's own lakes outside the walls; they are not part of this test.
	w._wq.clear()
	w._lq.clear()

	# (a) spread, fall over an edge, drain.
	_box(48, 100, 54, 60, 100, 74, Bx.STONE)
	w.set_block(57, 101, 64, Bx.WATER)
	var n := _settle()
	print("spread settled after ", n, " ticks")
	_check(w.is_source(57, 101, 64), "placed water is a source")
	_check(_b(50, 101, 64) == Bx.WATER and w.flow.get(w.idx_of(50, 101, 64), 0) == 1, "water spreads 7 blocks (level 1 at distance 7)")
	_check(_b(49, 101, 64) == 0, "water stops after 7 blocks")
	_check(_b(57, 101, 57) == Bx.WATER and _b(57, 101, 56) == 0, "water spreads 7 blocks sideways in z")
	_check(_b(61, 101, 64) == Bx.WATER and _b(62, 101, 64) == 0, "water reaches the edge and does not spread over air")
	_check(_b(61, 98, 64) == Bx.WATER and w.flow.get(w.idx_of(61, 98, 64), 0) == 7, "water falls over the edge as a level-7 column")
	_check(_b(61, 95, 64) == Bx.WATER and _b(67, 95, 64) == Bx.WATER and _b(68, 95, 64) == 0, "falling column spreads 6 on the lower floor")
	_check(not w.is_source(61, 95, 64), "flowing cells are not sources")
	# Carving the lab records terrain cells as AIR edits; flow must never record its water there.
	_check(w.flow.keys().all(func(k): return w.edits.get(k, -1) != Bx.WATER), "flowing cells are not recorded as edits")
	w.set_block(57, 101, 64, 0)
	n = _settle()
	print("drain settled after ", n, " ticks")
	_check(_count(Bx.WATER, 36, 95, 36, 92, 110, 92) == 0 and w.flow.is_empty(), "flow drains away when the source is removed")

	# (b) cobble generator: 1-wide channel, water source at x=67, lava source at x=77.
	_box(65, 105, 49, 79, 105, 51, Bx.STONE)
	_box(65, 106, 49, 79, 106, 49, Bx.STONE)
	_box(65, 106, 51, 79, 106, 51, Bx.STONE)
	w.set_block(65, 106, 50, Bx.STONE)
	w.set_block(79, 106, 50, Bx.STONE)
	w.set_block(67, 106, 50, Bx.WATER)
	w.set_block(77, 106, 50, Bx.LAVA)
	_settle()
	var gx := _gap()
	_check(gx >= 0, "lava meeting water forms cobble in the gap (x=%d)" % gx)
	for k in 3:
		w.set_block(maxi(gx, 0), 106, 50, 0)
		_settle()
		gx = _gap()
		_check(gx >= 0, "cobble regenerates after mining #%d (x=%d)" % [k + 1, gx])
	_check(w.is_source(77, 106, 50) and _b(76, 106, 50) == Bx.LAVA and not w.is_source(76, 106, 50), "lava source keeps feeding flowing lava")

	# Obsidian: water source next to a lava source in a sealed box.
	_box(69, 105, 55, 72, 107, 57, Bx.STONE)
	w.set_block(70, 106, 56, Bx.LAVA)
	_settle()
	w.set_block(71, 106, 56, Bx.WATER)
	_settle()
	_check(_b(70, 106, 56) == Bx.OBSIDIAN, "water touching a lava source makes obsidian")

	# Infinite water: a gap between two sources in a trench fills with a new source.
	_box(79, 105, 59, 83, 107, 61, Bx.STONE)
	_box(80, 106, 60, 82, 106, 60, 0)
	w.set_block(80, 106, 60, Bx.WATER)
	w.set_block(82, 106, 60, Bx.WATER)
	_settle()
	_check(_b(81, 106, 60) == Bx.WATER and w.is_source(81, 106, 60), "two sources make an infinite source between them")

	# Raycast liquids flag.
	var o := Vector3(70.5, 108.5, 50.5)
	var hit: Dictionary = w.raycast(o, Vector3(0, -1, 0), 6.0, true)
	_check(not hit.is_empty() and hit["block"] == Bx.WATER, "raycast(liquids=true) hits water")
	hit = w.raycast(o, Vector3(0, -1, 0), 6.0)
	_check(not hit.is_empty() and hit["block"] == Bx.STONE, "raycast() passes through water")

	# (c) save -> load keeps flowing cells flowing.
	var lvl: int = w.flow.get(w.idx_of(70, 106, 50), 0)
	main.save_path = main.worlds_dir + "liquid_test.save"
	main.save_game()
	var data: Dictionary = main._read_save()
	_check(data.has("flow") and not data["flow"].is_empty(), "save has flow state")
	await main._load_world(data["seed"], data["edits"], data.get("flow", {}))
	_check(_b(70, 106, 50) == Bx.WATER and not w.is_source(70, 106, 50) and w.flow.get(w.idx_of(70, 106, 50), 0) == lvl and lvl > 0, "flowing water reloads as flowing (level %d)" % lvl)
	_check(w.is_source(67, 106, 50) and w.is_source(77, 106, 50), "sources reload as sources")
	_check(_b(76, 106, 50) == Bx.LAVA and not w.is_source(76, 106, 50), "flowing lava reloads as flowing")
	var before: Dictionary = w.flow.duplicate()
	_settle()
	_check(w.flow == before and _gap() >= 0, "reloaded flow is stable")

	print("LIQUID TEST ", "FAILED (%d)" % fails if fails > 0 else "PASSED")
	quit(1 if fails > 0 else 0)


## X of the single cobble block in the generator channel, or -1.
func _gap() -> int:
	var found := -1
	for x in range(66, 79):
		if _b(x, 106, 50) == Bx.COBBLE:
			if found >= 0:
				return -1
			found = x
	return found
