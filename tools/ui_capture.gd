extends SceneTree
## Windowed UI check: title, HUD + held items (tool, block, empty hand, torch), inventory, pause, settings, death.
## Saves /tmp/pc_<name>.png.

var main
var f := 0
var started := false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("/tmp/pc_%s.png" % name)
	print("SHOT ", name)


func _process(_dt: float) -> bool:
	var Bx = root.get_node("B")
	if not started and main.state == "title":
		f += 1
		if f == 60:
			_shot("title")
			main.start_game("survival")
			started = true
			f = 0
		return false
	if not started:
		return false
	f += 1
	var p = main.player
	if f == 5:
		p.add_item(Bx.STONE_PICK, 1)
		for id in [Bx.GRASS, Bx.TORCH, Bx.LOG, Bx.COBBLE, Bx.COAL, Bx.IRON_ORE, Bx.RAW_MEAT, Bx.DIAMOND, Bx.GLASS, Bx.WOOL_RED, Bx.PLANKS]:
			p.add_item(id, 12)
		var sp: Vector3 = p.body.pos
		main.world.set_block(floori(sp.x) + 2, floori(sp.y), floori(sp.z), Bx.CRAFTING_TABLE)
		p.pitch = -0.25
		p.sel = 0
		main.ui.refresh_hotbar()
	if f == 70:
		_shot("tool")
		p.sel = 1
		main.ui.refresh_hotbar()
	if f == 110:
		_shot("block")
		p.sel = 8
		main.ui.refresh_hotbar()
	if f == 150:
		_shot("hand")
		p.sel = 2
		main.time_of_day = 0.45
		main.ui.refresh_hotbar()
	if f == 200:
		_shot("torch")
		main.time_of_day = 0.92
		main.open_inventory()
	if f == 230:
		var slot: Control = main.ui.inv_slots[0]
		main.ui.hover_slot = 0
		main.ui._slot_hover(0)
		Input.warp_mouse(slot.get_global_rect().get_center() * root.get_final_transform().get_scale())
	if f == 250:
		_shot("inventory")
		main.close_inventory()
		main.pause_game()
	if f == 290:
		_shot("pause")
		main.ui.open_settings("pause")
	if f == 320:
		_shot("settings")
		main.resume()
		p.health = 5.0
		p.hurt(10.0, Vector3.ZERO, "zombie")
	if f == 380:
		_shot("death")
		return true
	return false
