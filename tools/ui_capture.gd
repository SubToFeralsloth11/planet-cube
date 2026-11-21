extends SceneTree
## Windowed UI check: inventory/crafting and pause screens.

var main
var f := 0
var started := false


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://planet_cube.save"))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("/tmp/pc_%s.png" % name)
	print("SHOT ", name)


func _process(_dt: float) -> bool:
	var Bx = root.get_node("B")
	if not started and main.state == "title":
		main.start_game("survival")
		started = true
	if started:
		f += 1
		var p = main.player
		if f == 5:
			for id in [Bx.LOG, Bx.COBBLE, Bx.COAL, Bx.IRON_ORE, Bx.STONE_PICK, Bx.TORCH, Bx.PLANKS, Bx.RAW_MEAT, Bx.DIAMOND, Bx.GLASS, Bx.WOOL_RED]:
				p.add_item(id, 12)
			var sp: Vector3 = p.body.pos
			main.world.set_block(floori(sp.x) + 2, floori(sp.y), floori(sp.z), Bx.CRAFTING_TABLE)
		if f == 20:
			main.open_inventory()
		if f == 50:
			_shot("inventory")
			main.close_inventory()
			main.player.sel = 4
			main.ui.refresh_hotbar()
		if f == 80:
			_shot("held")
			return true
	return false
