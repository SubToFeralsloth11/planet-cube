extends SceneTree
## Headless check of farming, the Ash Lands dimension, the bow and the new recipes.

var main
var ok := true


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	ok = ok and c


func _count(id: int) -> int:
	return main.world.blocks.count(id)


func _run() -> void:
	while main.state != "title":
		await process_frame
	var Bx = root.get_node("B")
	await main.create_world("Feat", "survival", "77")
	var w = main.world
	var outs := {}
	for r in Bx.recipes:
		outs[r["out"]] = r
	for id in [Bx.BOW, Bx.ARROW, Bx.FLINT_AND_STEEL, Bx.HOE, Bx.BREAD, Bx.ASH_PORTAL, Bx.EMBER_CORE]:
		_check(outs.has(id), "recipe for %s" % Bx.item_name(id))
	_check(outs[Bx.ROCKET_ENGINE]["in"].has(Bx.EMBER_CORE), "rocket engine needs an Ember Core")
	_check(_count(Bx.EMBERITE_ORE) == 0, "no emberite on the home planet")
	var home_ore := _count(Bx.DIAMOND_ORE) + _count(Bx.GOLD_ORE)

	# Farming: a crop grows to full wheat.
	var p := Vector3i(main.player.body.pos.floor()) + Vector3i(3, 0, 0)
	w.set_block(p.x, p.y - 1, p.z, Bx.FARMLAND)
	w.set_block(p.x, p.y, p.z, Bx.WHEAT_0)
	_check(w.crops.size() == 1, "planted wheat is tracked")
	for i in 400:
		w.grow_crops(1.0)
	_check(w.get_b(p.x, p.y, p.z) == Bx.WHEAT_3 and w.crops.is_empty(), "wheat grows to full")

	# Bow: an arrow flies and expires.
	main.spawn_arrow(main.player.eye_pos(), Vector3(0, 0, 20), 5.0)
	var a = main.entities[-1]
	var start: Vector3 = a.global_position
	for i in 5:
		a.tick(0.05, main.player)
	_check(a.dead or a.global_position.distance_to(start) > 2.0, "arrow travels")

	# Ash Lands round trip.
	await main.travel_dimension()
	_check(w.ash, "travelled to the Ash Lands")
	_check(_count(Bx.GRASS) == 0, "no grass in the Ash Lands")
	_check(_count(Bx.EMBERITE_ORE) > 0, "emberite generates (%d)" % _count(Bx.EMBERITE_ORE))
	var ash_ore := _count(Bx.DIAMOND_ORE) + _count(Bx.GOLD_ORE)
	_check(ash_ore > home_ore, "richer ore (%d vs %d)" % [ash_ore, home_ore])
	_check(_count(Bx.ASH_PORTAL) == 1, "return portal placed")
	main.save_game()
	await main.travel_dimension()
	_check(not w.ash and w.get_b(p.x, p.y, p.z) == Bx.WHEAT_3, "home again with the farm intact")
	main.save_and_title()
	main.dim_other = {}
	main.terrain_of = ""
	await main.play_world(main.save_path)
	_check(not w.ash and main.dim_other.has("edits"), "save keeps both dimensions")
	print("FEATURES TEST ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)
