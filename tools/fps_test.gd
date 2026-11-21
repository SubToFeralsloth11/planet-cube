extends SceneTree
## Windowed FPS probe with the game's own render settings.

var main
var started := false
var t0 := 0
var f := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(_dt: float) -> bool:
	if not started and main.state == "title":
		main.start_game("survival")
		started = true
		t0 = Time.get_ticks_msec()
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	if started:
		main.player.yaw += 0.01
		f += 1
		if f % 90 == 0:
			var rid := root.get_viewport_rid()
			print("FPS ", Engine.get_frames_per_second(), " cpu_process_ms=", snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1), " gpu_ms=", snappedf(RenderingServer.viewport_get_measured_render_time_gpu(rid), 0.1), " cpu_render_ms=", snappedf(RenderingServer.viewport_get_measured_render_time_cpu(rid), 0.1), " prims=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		if f % 90 == 45:
			var parts := {}
			var t := Time.get_ticks_usec()
			main.player.tick(0.016)
			parts["player"] = Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			main._update_sky(0.016, Vector3.UP, -1.0, true)
			parts["sky"] = Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			main.ui.update_hud(0.016)
			parts["hud"] = Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			main._update_clouds(0.016)
			parts["clouds"] = Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			main._tick_entities(0.016)
			parts["ents"] = Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			main.world._process(0.016)
			parts["world"] = Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			main._update_info()
			main._update_cameras(0.016)
			parts["info+cam"] = Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			main.player._interact(0.016)
			parts["interact"] = Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			main.player._movement(0.016)
			parts["move"] = Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			main.player._visuals(0.016)
			parts["visuals"] = Time.get_ticks_usec() - t
			print("US ", parts, " dirty=", main.world.dirty.size(), " ents=", main.entities.size())
		if Time.get_ticks_msec() - t0 > 8000:
			return true
	return false
