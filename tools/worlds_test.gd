extends SceneTree
## Headless check of multiple worlds: create two, edit one, switch between them, delete one.
## The steps run in one coroutine; _process only reports when it has finished (an awaiting
## _process would return early and end the run).

var main
var ok := true


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	ok = ok and c


func _run() -> void:
	while main.state != "title":
		await process_frame
	var Bx = root.get_node("B")
	_check(main.list_worlds().is_empty(), "test run starts with no worlds")
	await main.create_world("Alpha", "survival", "123")
	_check(main.world.world_seed == 123, "numeric seed is used (%d)" % main.world.world_seed)
	var mark := Vector3i(main.player.body.pos.floor()) + Vector3i(0, 3, 0)
	main.world.set_block(mark.x, mark.y, mark.z, Bx.GOLD_BLOCK)
	main.save_and_title()
	await main.create_world("Beta", "creative")
	_check(main.player.creative, "second world is creative")
	main.save_and_title()
	var ws: Array = main.list_worlds()
	_check(ws.size() == 2, "two worlds listed (%d)" % ws.size())
	_check(ws[0]["name"] == "Beta" and ws[1]["name"] == "Alpha", "most recent first")
	await main.play_world(ws[1]["path"])
	_check(main.world.world_seed == 123 and not main.player.creative, "Alpha reloads as survival on seed 123")
	_check(main.world.get_b(mark.x, mark.y, mark.z) == Bx.GOLD_BLOCK, "Alpha keeps its edits")
	main.save_and_title()
	for w in main.list_worlds():
		if w["name"] == "Beta":
			main.delete_world(w["path"])
	ws = main.list_worlds()
	_check(ws.size() == 1 and ws[0]["name"] == "Alpha", "Beta deleted, Alpha kept")
	print("WORLDS TEST ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)
