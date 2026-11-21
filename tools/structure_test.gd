extends SceneTree
## Headless check that villages, ruins and the pyramid generate with their key blocks and a reachable
## ruins entrance. Prints PASS/FAIL lines and exits non-zero on failure.

var main
var done := false


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://planet_cube.save"))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _count(w, center: Vector3, r: int, id: int) -> int:
	var n := 0
	var c := Vector3i(center.floor())
	for x in range(c.x - r, c.x + r + 1):
		for y in range(c.y - r, c.y + r + 1):
			for z in range(c.z - r, c.z + r + 1):
				if w.get_b(x, y, z) == id:
					n += 1
	return n


func _check(ok: bool, what: String) -> bool:
	print(("PASS " if ok else "FAIL ") + what)
	return ok


func _process(_dt: float) -> bool:
	if done or main.state != "title":
		return false
	done = true
	var Bx = root.get_node("B")
	var w = main.world
	var all_ok := true
	var names := {}
	for s in w.structures:
		names[s["name"]] = names.get(s["name"], 0) + 1
	print("STRUCTURES ", names)
	all_ok = _check(names.get("Village", 0) == 2, "two villages") and all_ok
	all_ok = _check(names.get("Ancient Ruins", 0) == 2, "two ruins") and all_ok
	all_ok = _check(names.get("Sand Pyramid", 0) == 1, "one pyramid") and all_ok
	for s in w.structures:
		var p: Vector3 = s["pos"]
		match s["name"]:
			"Village":
				var glass := _count(w, p, 13, Bx.GLASS)
				var tables := _count(w, p, 13, Bx.CRAFTING_TABLE)
				var torches := _count(w, p, 13, Bx.TORCH)
				all_ok = _check(glass >= 8 and tables >= 4 and torches >= 6, "village %v glass=%d tables=%d torches=%d" % [p, glass, tables, torches]) and all_ok
			"Ancient Ruins":
				var bricks := _count(w, p, 8, Bx.STONE_BRICKS)
				var loot := _count(w, p, 3, Bx.GOLD_BLOCK) + _count(w, p, 3, Bx.DIAMOND_ORE)
				var open: bool = Bx.SOLID[w.block_at(p + Vector3(2.5, 0, 2.5))] == 0
				var buried: bool = w.sky_vis_at(p) < 0.5
				all_ok = _check(bricks > 150 and loot >= 3 and open and buried, "ruins %v bricks=%d loot=%d open=%s buried=%s" % [p, bricks, loot, open, buried]) and all_ok
			"Ruins Entrance":
				# The arch lintel shades the top step itself; open ground right next to it must see sky.
				var sky := 0.0
				for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
					if Bx.SOLID[w.block_at(p + d)] == 0:
						sky = maxf(sky, w.sky_vis_at(p + d))
				all_ok = _check(sky > 0.5, "ruins entrance %v opens to the surface (sky=%.2f)" % [p, sky]) and all_ok
			"Sand Pyramid":
				var sand := _count(w, p, 10, Bx.SANDSTONE)
				var vault := _count(w, p, 10, Bx.GOLD_ORE)
				all_ok = _check(sand > 300 and vault >= 4, "pyramid %v sandstone=%d vault_gold=%d" % [p, sand, vault]) and all_ok
	var lights := 0
	for l in w.light_nodes.values():
		for s in w.structures:
			if l.position.distance_to(s["pos"]) < s["radius"] + 4.0:
				lights += 1
				break
	all_ok = _check(lights >= 10, "structure torches/lamps emit light (%d lights)" % lights) and all_ok
	all_ok = _check(Bx.EMIT[Bx.DIAMOND_ORE] == 0.0, "diamond ore does not glow in the dark") and all_ok
	print("STRUCTURE TEST ", "OK" if all_ok else "FAILED")
	quit(0 if all_ok else 1)
	return false
