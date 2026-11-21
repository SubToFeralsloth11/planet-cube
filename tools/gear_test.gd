extends SceneTree
## Headless gear check: armor math, shield blocking, F offhand swap, buckets, water-bucket clutch,
## armor-slot rules, chests, furnaces and save/load of armor + offhand. Prints PASS/FAIL; exit 1 on failure.

var main
var f := 0
var phase := 0
var fails: Array[String] = []
var Bx
var ground := Vector3i.ZERO
var water_cell := Vector3i.ZERO
var poured := false
var pour_dist := -1.0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)


func _click(btn: int, shift := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = true
	e.shift_pressed = shift
	return e


func _clear_mobs() -> void:
	for e in main.entities.duplicate():
		if e.get("hostile") == true:
			main.remove_entity(e)


func _process(_dt: float) -> bool:
	f += 1
	Bx = root.get_node("B")
	var p = main.player
	match phase:
		0:
			if main.state == "title":
				main.start_game("survival")
				phase = 1
				f = 0
		1:
			if main.state == "play" and f > 5:
				_clear_mobs()
				_static_tests(p)
				_setup_drop(p)
				phase = 2
				f = 0
		2:
			_clear_mobs()
			p.pitch = -1.55
			# Pour as soon as the floor comes within reach (after a real tick so the target is fresh).
			if not poured and f > 2 and p.target:
				pour_dist = p.target["dist"]
				water_cell = p.target["pos"] + p.target["normal"]
				p.place_cd = 0.0
				p._use(true)
				poured = true
			if p.body.on_ground and f > 5:
				var w := water_cell
				_check(poured, "bucket poured mid-fall (target dist %.2f)" % pour_dist)
				_check(main.world.get_b(w.x, w.y, w.z) == Bx.WATER, "water source exists under the player")
				_check(p.health == 20.0, "water-bucket clutch from 25 blocks: no fall damage (hp %.1f)" % p.health)
				_check(p.held_id() == Bx.BUCKET, "clutch left an empty bucket in hand")
				p.place_cd = 0.0
				p._use(true)
				_check(p.held_id() == Bx.WATER_BUCKET and main.world.get_b(w.x, w.y, w.z) != Bx.WATER, "scooped the clutch water back up")
				return _finish()
	if f > 1200:
		_check(false, "timeout in phase %d" % phase)
		return _finish()
	return false


func _finish() -> bool:
	if fails.is_empty():
		print("PASS gear_test")
		quit(0)
	else:
		print("FAIL gear_test: ", fails)
		quit(1)
	return true


func _static_tests(p) -> void:
	# --- recipes ---
	var outs := {}
	for r in Bx.recipes:
		outs[r["out"]] = r
	for id in [Bx.BUCKET, Bx.SHIELD, Bx.CHEST, Bx.IRON_HELMET, Bx.DIAMOND_BOOTS]:
		_check(outs.has(id) and outs[id]["st"] == "table", "table recipe for " + Bx.item_name(id))
	_check(outs[Bx.BUCKET]["in"] == {Bx.IRON_INGOT: 3}, "bucket = 3 iron")
	_check(outs[Bx.DIAMOND_CHESTPLATE]["in"] == {Bx.DIAMOND: 8}, "diamond chestplate = 8 diamonds")

	# --- armor math ---
	p.blocking = false
	for k in 4:
		p.inv[p.ARMOR0 + k] = {"id": Bx.DIAMOND_HELMET + k, "n": 1}
	_check(p.armor_points() == 20, "full diamond = 20 armor (%d)" % p.armor_points())
	p.health = 20.0
	p.hurt(5.0, Vector3.ZERO, "zombie")
	_check(is_equal_approx(p.health, 19.0), "diamond armor cuts 5 dmg to 1 (hp %.2f)" % p.health)
	for k in 4:
		p.inv[p.ARMOR0 + k] = {"id": Bx.IRON_HELMET + k, "n": 1}
	_check(p.armor_points() == 15, "full iron = 15 armor (%d)" % p.armor_points())
	p.health = 20.0
	p.hurt(5.0, Vector3.ZERO, "explosion")
	_check(is_equal_approx(p.health, 18.0), "iron armor cuts 5 dmg by 60%% (hp %.2f)" % p.health)
	p.health = 20.0
	p.hurt(5.0, Vector3.ZERO, "fall")
	_check(is_equal_approx(p.health, 15.0), "armor ignores fall damage (hp %.2f)" % p.health)
	p.inv[p.OFFHAND] = {"id": Bx.IRON_INGOT, "n": 5}
	_check(p.count(Bx.IRON_INGOT) == 0, "offhand / armor are not counted for crafting")
	# right-click with armor in hand swaps it with the worn piece
	p.inv[p.sel] = {"id": Bx.DIAMOND_HELMET, "n": 1}
	p.target = {}
	p.target_ent = null
	p.place_cd = 0.0
	p._use(true)
	_check(p.inv[p.ARMOR0]["id"] == Bx.DIAMOND_HELMET and p.held_id() == Bx.IRON_HELMET, "right-click equips armor (swap)")
	for k in 4:
		p.inv[p.ARMOR0 + k] = null
	p.inv[p.sel] = null

	# --- shield ---
	p.inv[p.OFFHAND] = {"id": Bx.SHIELD, "n": 1}
	_check(p._wants_block(true), "offhand shield + empty hand blocks on RMB")
	p.inv[p.sel] = {"id": Bx.IRON_SWORD, "n": 1}
	_check(p._wants_block(true), "offhand shield + sword blocks on RMB")
	p.inv[p.sel] = {"id": Bx.COOKED_MEAT, "n": 1}
	_check(not p._wants_block(true), "food in main hand eats instead of blocking")
	p.inv[p.sel] = null
	p._sync_transform()
	var u: Vector3 = p.up()
	var look: Vector3 = p.look_dir()
	var lt := (look - u * look.dot(u)).normalized()
	p.health = 20.0
	p.blocking = true
	p.hurt(3.0, -lt * 5.0 + u * 3.5, "zombie")
	_check(p.health == 20.0, "frontal zombie hit fully blocked (hp %.1f)" % p.health)
	p.hurt(7.0, -lt * 9.0 + u * 7.0, "shockwave")
	_check(p.health == 20.0, "frontal shockwave blocked")
	p.hurt(3.0, lt * 5.0 + u * 3.5, "zombie")
	_check(is_equal_approx(p.health, 17.0), "hit from behind not blocked (hp %.1f)" % p.health)
	p.health = 20.0
	p.hurt(1.0, -lt * 2.0, "cactus")
	_check(is_equal_approx(p.health, 19.0), "cactus never blocked")
	p.blocking = false
	p.health = 20.0

	# --- F swaps main hand and offhand ---
	p.inv[p.sel] = {"id": Bx.IRON_SWORD, "n": 1}
	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.pressed = true
	p._unhandled_input(ev)
	_check(p.held_id() == Bx.SHIELD and p.offhand_id() == Bx.IRON_SWORD, "F swaps main hand with offhand")
	p._unhandled_input(ev)
	_check(p.held_id() == Bx.IRON_SWORD and p.offhand_id() == Bx.SHIELD, "F swaps back")

	# --- bucket scoop / pour / scoop ---
	var w = main.world
	p.pitch = -0.5
	p._sync_transform()
	var eye: Vector3 = p.eye_pos()
	look = p.look_dir()
	var cell := Vector3i((eye + look * 2.5).floor())
	for k in range(2, 24):
		var c := Vector3i((eye + look * (k * 0.1)).floor())
		if w.solid(c.x, c.y, c.z):
			w.set_block(c.x, c.y, c.z, Bx.AIR)
	w.set_block(cell.x, cell.y, cell.z, Bx.WATER)
	var back := Vector3i((eye + look * 3.6).floor())
	w.set_block(back.x, back.y, back.z, Bx.STONE)
	_check(w.is_source(cell.x, cell.y, cell.z), "test water source placed")
	p.inv[p.sel] = {"id": Bx.BUCKET, "n": 1}
	p._interact(0.0)
	p.place_cd = 0.0
	p._use(true)
	_check(p.held_id() == Bx.WATER_BUCKET, "empty bucket scoops source -> water bucket")
	_check(w.get_b(cell.x, cell.y, cell.z) != Bx.WATER, "scooped source is gone")
	p._interact(0.0)
	var had_target: bool = not p.target.is_empty()
	p.place_cd = 0.0
	p._use(true)
	if had_target:
		var np: Vector3i = p.target["pos"] + p.target["normal"]
		_check(w.is_source(np.x, np.y, np.z) and p.held_id() == Bx.BUCKET, "water bucket pours a source and empties")
		p._interact(0.0)
		p.place_cd = 0.0
		p._use(true)
		_check(p.held_id() == Bx.WATER_BUCKET and not w.is_source(np.x, np.y, np.z), "scoop it back")
	else:
		_check(false, "no block targeted for pouring")

	# --- armor slot rules in the inventory screen ---
	main.open_inventory()
	main.ui.cursor_stack = {"id": Bx.COAL, "n": 3}
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT), p.ARMOR0)
	_check(p.inv[p.ARMOR0] == null, "coal refused by helmet slot")
	main.ui.cursor_stack = {"id": Bx.IRON_BOOTS, "n": 1}
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT), p.ARMOR0)
	_check(p.inv[p.ARMOR0] == null, "boots refused by helmet slot")
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT), p.ARMOR0 + 3)
	_check(p.inv[p.ARMOR0 + 3] != null and p.inv[p.ARMOR0 + 3]["id"] == Bx.IRON_BOOTS, "boots fit boots slot")
	main.ui.cursor_stack = {"id": Bx.COAL, "n": 3}
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT), p.OFFHAND)
	_check(p.offhand_id() == Bx.COAL and main.ui.cursor_stack["id"] == Bx.SHIELD, "anything goes in offhand (swap)")
	main.ui.cursor_stack = null
	p.inv[p.OFFHAND] = {"id": Bx.SHIELD, "n": 1}
	main.close_inventory()

	# --- chest ---
	var cp := Vector3i((p.eye_pos() + Vector3(2, 0, 0)).floor())
	w.set_block(cp.x, cp.y, cp.z, Bx.CHEST)
	var idx: int = cp.x + (cp.y << 7) + (cp.z << 14)
	p.open_storage(cp, Bx.CHEST)
	_check(main.state == "inventory" and main.ui.chest_idx == idx and main.ui.chest_box.visible, "chest screen opens")
	var slot0 := 0
	p.inv[slot0] = {"id": Bx.COAL, "n": 5}
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT, true), slot0)
	var ci: Array = w.chest_inv(idx)
	_check(ci[0] != null and ci[0]["id"] == Bx.COAL and ci[0]["n"] == 5 and p.inv[slot0] == null, "shift-click moves stack into chest")
	p.inv[1] = {"id": Bx.DIAMOND, "n": 2}
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT), 1)
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT), main.ui.CHEST0 + 5)
	_check(ci[5] != null and ci[5]["id"] == Bx.DIAMOND, "click-place into chest slot")
	main.close_inventory()
	_check(main.state == "play" and main.ui.chest_idx == -1, "chest screen closes")
	var before: int = main.entities.size()
	p.break_block(cp, Bx.CHEST)
	var ids := []
	for k in range(before, main.entities.size()):
		ids.append(main.entities[k].get("id"))
	_check(Bx.COAL in ids and Bx.DIAMOND in ids and Bx.CHEST in ids, "broken chest spills contents + itself %s" % [ids])
	_check(not w.chests.has(idx), "chest storage erased")

	# --- furnace ---
	for r in Bx.recipes:
		if r["out"] == Bx.IRON_INGOT:
			_check(not main.can_craft(r), "iron ingot is no longer craftable (furnace only)")
	var fp := cp + Vector3i(0, 0, 2)
	w.set_block(fp.x, fp.y, fp.z, Bx.FURNACE)
	var fi: int = fp.x + (fp.y << 7) + (fp.z << 14)
	p.open_storage(fp, Bx.FURNACE)
	_check(main.state == "inventory" and main.ui.furnace_box.visible and not main.ui.inv_right.visible, "furnace screen opens")
	p.inv[0] = {"id": Bx.IRON_ORE, "n": 2}
	p.inv[1] = {"id": Bx.COAL, "n": 1}
	p.inv[2] = {"id": Bx.DIRT, "n": 3}
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT, true), 0)
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT, true), 1)
	var fz: Dictionary = w.furnace_at(fi)
	_check(fz["in"] != null and fz["in"]["id"] == Bx.IRON_ORE and fz["fuel"] != null and fz["fuel"]["id"] == Bx.COAL, "shift-click: ore -> input, coal -> fuel")
	main.ui.cursor_stack = {"id": Bx.DIRT, "n": 3}
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT), main.ui.FURN_FUEL)
	_check(fz["fuel"]["id"] == Bx.COAL and main.ui.cursor_stack["id"] == Bx.DIRT, "dirt refused by fuel slot")
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT), main.ui.FURN_OUT)
	_check(fz["out"] == null, "nothing can be put in the output")
	main.ui.cursor_stack = null
	p.inv[2] = null
	main.close_inventory()
	for k in 60:
		main._step_furnace(fz, 0.05)
	_check(fz["out"] != null and fz["out"]["id"] == Bx.IRON_INGOT and fz["out"]["n"] == 1, "3 s of smelting -> 1 iron ingot")
	_check(fz["in"] != null and fz["in"]["n"] == 1 and fz["fuel"] == null, "one ore left, coal consumed")
	_check(fz["burn"] > 16.0 and fz["burn"] < 18.0 and fz["burn_max"] == 20.0, "coal burning (%.2f s left of 20)" % fz["burn"])
	main.save_game()
	var sf: Dictionary = main._read_save()["furnaces"].get(fi, {})
	_check(not sf.is_empty() and sf["out"]["n"] == 1 and is_equal_approx(sf["burn"], fz["burn"]) and is_equal_approx(sf["prog"], fz["prog"]), "furnace state saved")
	p.open_storage(fp, Bx.FURNACE)
	p.obtained.erase(Bx.IRON_INGOT)
	main.ui._slot_input(_click(MOUSE_BUTTON_LEFT, true), main.ui.FURN_OUT)
	_check(fz["out"] == null and p.count(Bx.IRON_INGOT) == 1 and p.obtained.has(Bx.IRON_INGOT), "shift-click output -> inventory (counts for missions)")
	main.close_inventory()
	var fb: int = main.entities.size()
	p.break_block(fp, Bx.FURNACE)
	var fids := []
	for k in range(fb, main.entities.size()):
		fids.append(main.entities[k].get("id"))
	_check(Bx.IRON_ORE in fids and not w.furnaces.has(fi), "broken furnace pops its items %s" % [fids])

	# --- save / load keeps armor + offhand ---
	p.inv[p.ARMOR0 + 1] = {"id": Bx.DIAMOND_CHESTPLATE, "n": 1}
	main.save_game()
	var data: Dictionary = main._read_save()
	p.inv.clear()
	p.inv.resize(p.INV_SIZE)
	p.from_dict(data["player"])
	_check(p.inv.size() == p.INV_SIZE, "inventory size after load")
	_check(p.inv[p.ARMOR0 + 1] != null and p.inv[p.ARMOR0 + 1]["id"] == Bx.DIAMOND_CHESTPLATE, "chestplate survives save/load")
	_check(p.inv[p.ARMOR0 + 3] != null and p.inv[p.ARMOR0 + 3]["id"] == Bx.IRON_BOOTS, "boots survive save/load")
	_check(p.offhand_id() == Bx.SHIELD, "offhand survives save/load")
	for k in 4:
		p.inv[p.ARMOR0 + k] = null


## Digs a walled shaft below the player with a stone floor 25 blocks under the start, and puts the
## player at the top looking down with a water bucket.
func _setup_drop(p) -> void:
	var w = main.world
	var u := Vector3i(p.up())
	var a := 0 if u.x != 0 else (1 if u.y != 0 else 2)
	var t1 := Vector3i.ZERO
	var t2 := Vector3i.ZERO
	t1[(a + 1) % 3] = 1
	t2[(a + 2) % 3] = 1
	var top := Vector3i(p.body.pos.floor())
	ground = top - u * 26
	for k in range(-26, 4):
		for i in range(-2, 3):
			for j in range(-2, 3):
				var c: Vector3i = top + u * k + t1 * i + t2 * j
				var wall := absi(i) == 2 or absi(j) == 2 or k == -26
				w.set_block(c.x, c.y, c.z, Bx.STONE if wall else Bx.AIR)
	w.flush_dirty(1000)
	var cen := Vector3(ground) + Vector3(0.5, 0.5, 0.5) + Vector3(u) * 0.5
	p.body.pos = cen + Vector3(u) * 25.0
	p.body.vel = Vector3.ZERO
	p.health = 20.0
	p.inv[p.sel] = {"id": Bx.WATER_BUCKET, "n": 1}
	p.inv[p.OFFHAND] = null
	p.pitch = -1.55
	print("drop from ", p.body.pos, " onto ", ground)
