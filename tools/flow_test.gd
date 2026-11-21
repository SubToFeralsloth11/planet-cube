extends SceneTree
## Headless end-to-end flow: crafting UI, rocket, boss fight, launch, ending, save/continue.

var main
var f := 0
var phase := 0
var Bx


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


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
				for id in [Bx.IRON_INGOT, Bx.GOLD_INGOT, Bx.DIAMOND, Bx.STARCORE, Bx.COAL, Bx.GLASS, Bx.FURNACE, Bx.LOG]:
					p.add_item(id, 30)
				var sp: Vector3 = p.body.pos
				main.world.set_block(floori(sp.x) + 2, floori(sp.y), floori(sp.z), Bx.CRAFTING_TABLE)
				main.open_inventory()
				print("INV open state=", main.state, " rows=", main.ui.craft_list.get_child_count())
				var crafted := 0
				for r in Bx.recipes:
					if r["out"] in [Bx.ROCKET_HULL, Bx.ROCKET_ENGINE, Bx.NAV_CORE, Bx.FUEL_CELL]:
						var n: int = 3 if r["out"] == Bx.FUEL_CELL else 1
						for k in n:
							if main.craft(r):
								crafted += 1
				for r in Bx.recipes:
					if r["out"] == Bx.ROCKET and main.craft(r):
						crafted += 1
				print("CRAFTED ", crafted, " rocket=", p.count(Bx.ROCKET))
				main.ui._slot_input(_click(MOUSE_BUTTON_LEFT), 0)
				main.ui._slot_input(_click(MOUSE_BUTTON_LEFT), 20)
				main.close_inventory()
				phase = 2
				f = 0
		2:
			if f == 5:
				p.pitch = -1.5
			if f == 10:
				for i in 36:
					if p.inv[i] and p.inv[i]["id"] == Bx.ROCKET:
						p.sel = i if i < 9 else p.sel
						if i >= 9:
							p.inv[p.sel] = p.inv[i]
							p.inv[i] = null
				print("HELD ", Bx.item_name(p.held_id()), " target=", p.target)
				var tgt: Dictionary = p.target.duplicate()
				tgt["normal"] = Vector3i(p.up())
				# place 4 blocks away to keep the player outside the pad
				tgt["pos"] = tgt["pos"] + Vector3i(4, 0, 0)
				var g: Vector3i = tgt["pos"]
				for k in range(0, 9):
					for dx in range(-1, 2):
						for dz in range(-1, 2):
							main.world.set_block(g.x + dx, g.y + 1 + k, g.z + dz, 0)
				main.world.set_block(g.x, g.y, g.z, Bx.STONE)
				main.world.flush_dirty(1000)
				main.try_place_rocket(tgt, p)
				print("ROCKET ", main.rocket != null)
				main.rocket_interact()
				print("STATE after interact ", main.state)
				main.ui.confirm_cb.call()
				main.close_confirm()
				print("BOSS ", main.boss != null, " state=", main.state)
			if f > 10 and f < 400 and main.boss and f % 60 == 0:
				print("BOSS st=", main.boss.state, " hp=", main.boss.hp, " player hp=", p.health)
			if f == 400:
				p.creative = true
				var b = main.boss
				for k in 60:
					if b.dead:
						break
					b.state = "stunned"
					b.hurt(9.0, Vector3.ZERO, p)
				print("BOSS dead=", b.dead, " defeated=", main.boss_defeated, " rocket=", main.rocket.state)
			if f == 420:
				main.rocket_interact()
				main.ui.confirm_cb.call()
				print("STATE launch ", main.state)
				phase = 3
				f = 0
		3:
			if main.state == "end":
				print("END reached escaped=", main.escaped, " objective=", main.objective)
				print("END text: ", main.ui.end_stats.text.split("\n")[0])
				main.continue_after_end()
				main.save_and_title()
				phase = 4
				f = 0
		4:
			if main.state == "title" and f > 3:
				main.start_game("continue")
				phase = 5
				f = 0
		5:
			if main.state == "play" and f > 5:
				print("CONTINUE pos=", p.body.pos, " inv0=", p.inv[0], " escaped=", main.escaped, " edits=", main.world.edits.size())
				return true
	if f > 3000:
		print("TIMEOUT phase=", phase, " state=", main.state)
		return true
	return false


func _click(btn: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = true
	return e
