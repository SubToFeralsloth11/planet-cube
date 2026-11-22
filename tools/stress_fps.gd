extends SceneTree
## Stress probe: mobs, ground items, moving and mining. Reports avg and worst frames.

var main
var started := false
var t0 := 0
var frames := PackedFloat32Array()
var last := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(_dt: float) -> bool:
	if not started:
		if main.state != "title":
			return false
		main.start_game("survival")
		main.player.creative = true
		started = true
		t0 = Time.get_ticks_msec()
		last = Time.get_ticks_usec()
		var p: Vector3 = main.player.body.pos
		var fr: Basis = main.player.body.frame
		for k in 14:
			var a := k * TAU / 14.0
			var feet: Vector3 = main.world.surface_at(p + (fr.x * cos(a) + fr.z * sin(a)) * 12.0 + fr.y * 12.0)
			if feet != Vector3.INF:
				main.spawn_mob(["zombie", "boomer"][k % 2], feet, main.player.body.face)
		for k in 60:
			main.spawn_drop(1 + k % 8, 1, p + fr.y * 2.0 + Vector3(randf() - 0.5, 0, randf() - 0.5) * 6.0, Vector3.ZERO, 99.0)
		return false
	var now := Time.get_ticks_usec()
	var el := Time.get_ticks_msec() - t0
	if el > 1500:
		frames.append((now - last) / 1000.0)
	last = now
	var pl = main.player
	pl.yaw += 0.02
	if Engine.get_process_frames() % 6 == 0:
		var c: Vector3 = pl.body.pos - pl.body.up() * 0.5 + Basis(pl.vis_q).x * randf_range(-3, 3) + Basis(pl.vis_q).z * randf_range(-3, 3)
		main.world.set_block(floori(c.x), floori(c.y), floori(c.z), 0)
	if el > 12000:
		var s := frames.duplicate()
		s.sort()
		var tot := 0.0
		var over := 0
		for v in s:
			tot += v
			if v > 16.7:
				over += 1
		var n := s.size()
		print("STRESS frames=", n, " avg_fps=", snappedf(1000.0 * n / tot, 0.1), " p1_low_fps=", snappedf(1000.0 / s[int(n * 0.99)], 0.1), " worst_ms=", snappedf(s[n - 1], 0.1), " over_16.7ms=", over, " ents=", main.entities.size())
		return true
	return false
