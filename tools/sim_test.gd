extends SceneTree
## Headless simulation: world gen timing, ore stats, edge walking, mining, crafting.

var main
var t0 := 0
var phase := 0
var f := 0
var Bx


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://planet_cube.save"))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()


func _process(_dt: float) -> bool:
	f += 1
	Bx = root.get_node("B")
	if phase == 0 and main.state == "title":
		print("WORLD READY ms=", Time.get_ticks_msec() - t0, " chunks=", main.world.chunk_nodes.size())
		var counts := {}
		for b in main.world.blocks:
			counts[b] = counts.get(b, 0) + 1
		var names := []
		for k in counts:
			names.append("%s=%d" % [Bx.item_name(k), counts[k]])
		print("BLOCKS ", ", ".join(names))
		var tri := 0
		for c in main.world.chunk_nodes.values():
			for mi in c:
				if mi:
					tri += mi.mesh.surface_get_array_len(0)
		print("VERTS ", tri)
		var tm := Time.get_ticks_msec()
		main.world._build_chunk(4 + 6 * 8 + 4 * 64)
		print("REMESH one chunk ms=", Time.get_ticks_msec() - tm)
		main.start_game("survival")
		phase = 1
		f = 0
	elif phase == 1 and main.state == "play":
		var p = main.player
		if f == 1:
			print("SPAWN ", p.body.pos, " face=", p.body.face)
		if f == 60:
			print("AFTER 1s pos=", p.body.pos, " ground=", p.body.on_ground)
			p.spawn_at(Vector3(98.5, 101.5, 64.5), 2)
			p.yaw = -PI / 2.0
			Input.action_press("move_forward")
		if f > 60 and f % 30 == 0 and f < 400:
			print("EDGE f=", f, " pos=", p.body.pos.snapped(Vector3(0.01, 0.01, 0.01)), " face=", p.body.face, " ground=", p.body.on_ground)
		if f == 400:
			Input.action_release("move_forward")
			var under := Vector3i(p.body.pos - p.body.up() * 0.5)
			var b: int = main.world.get_b(under.x, under.y, under.z)
			print("UNDER block ", Bx.item_name(b))
			p.break_block(under, b)
			print("INV after break ", p.inv.slice(0, 3))
			p.add_item(Bx.LOG, 4)
			var ok: bool = main.craft(Bx.recipes[0])
			print("CRAFT planks ok=", ok, " planks=", p.count(Bx.PLANKS))
			main.explode(p.body.pos + Vector3(0, -3, 0), 3.0, 0.0)
			main.spawn_mob("zombie", p.body.pos + p.body.up() * 2.0, p.body.face)
			main.spawn_mob("pig", p.body.pos + p.body.up() * 2.0, p.body.face)
		if f == 520:
			print("ENTITIES ", main.entities.size(), " objective=", main.objective, " health=", p.health)
			print("FPS-ish frames ok")
			return true
	if f > 6000:
		print("TIMEOUT state=", main.state)
		return true
	return false
