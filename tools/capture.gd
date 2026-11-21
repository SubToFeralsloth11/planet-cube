extends SceneTree
## Windowed visual check: saves screenshots of title, first person, third person, map, cave and boss.

var main
var f := 0
var phase := 0
var Bx
var shots := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("/tmp/pc_%s.png" % name)
	shots += 1
	print("SHOT ", name)


func _process(_dt: float) -> bool:
	f += 1
	Bx = root.get_node("B")
	if phase == 0 and main.state == "title":
		phase = 1
		f = 0
	elif phase == 1:
		if f == 40:
			_shot("title")
			main.start_game("survival")
			phase = 2
			f = 0
	elif phase == 2 and main.state == "play":
		var p = main.player
		if f == 2:
			p.pitch = -0.15
			p.yaw = 0.6
		if f == 50:
			_shot("fp")
			print("FPS fp=", Engine.get_frames_per_second(), " draw_calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			p.view_mode = 1
		if f == 90:
			_shot("third")
			p.view_mode = 0
			p.spawn_at(Vector3(98.5, 101.5, 64.5), 2)
			p.yaw = -PI / 2.0
			p.pitch = -0.35
		if f == 130:
			_shot("edge")
			main.map_view = true
		if f == 170:
			_shot("map")
			print("FPS map=", Engine.get_frames_per_second())
			main.map_view = false
			main.time_of_day = 0.45
		if f == 210:
			_shot("night")
			main.time_of_day = 0.0
			p.add_item(Bx.ROCKET, 1)
			p.add_item(Bx.TORCH, 10)
			var sp: Vector3 = main.world.find_spawn()
			p.spawn_at(sp, 2)
			main._spawn_rocket(2, sp + Vector3(5, 0, 0))
			main._start_boss()
			p.yaw = -PI / 2.0
			p.pitch = 0.25
		if f == 300:
			var dir: Vector3 = main.boss.global_position - p.eye_pos()
			var local: Vector3 = p.body.frame.inverse() * dir
			p.yaw = atan2(-local.x, -local.z)
			p.pitch = atan2(local.y, Vector2(local.x, local.z).length())
		if f == 330:
			_shot("boss")
			p.cam.current = true
			main._clear_entities()
			for i in 25:
				main.world.set_block(64, 100 - i, 64, 0)
			p.spawn_at(Vector3(64.5, 86.0, 64.5), 2)
			main.world.set_block(65, 87, 64, Bx.TORCH)
			p.pitch = -0.3
			p.yaw = 0.0
		if f == 380:
			_shot("cave")
			return true
	if f > 4000:
		print("TIMEOUT state=", main.state)
		return true
	return false
