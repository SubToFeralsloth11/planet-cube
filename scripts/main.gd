extends Node3D
## Game orchestration: states, day/night, spawning, missions, crafting, boss fight, saving.

## Pre-worlds single save; migrated into the worlds folder on first launch.
const OLD_SAVE_PATH := "user://planet_cube.save"
const DAY_LEN := 540.0
const WorldScript := preload("res://scripts/world.gd")
const PlayerScript := preload("res://scripts/player.gd")
const UIScript := preload("res://scripts/ui.gd")
const MobScript := preload("res://scripts/mob.gd")
const BossScript := preload("res://scripts/boss.gd")
const BoltScript := preload("res://scripts/bolt.gd")
const TntScript := preload("res://scripts/tnt.gd")
const DropScript := preload("res://scripts/drop.gd")
const RocketScript := preload("res://scripts/rocket.gd")
const CENTER := Vector3(64, 64, 64)

var world
var player
var ui
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var title_cam: Camera3D
var map_cam: Camera3D
var cine_cam: Camera3D
var map_beam: MeshInstance3D
var state := "boot"
var time_of_day := 0.9
var sun_dir := Vector3.UP
var entities: Array = []
var boss = null
var rocket = null
var boss_defeated := false
var escaped := false
var objective := 0
var orbit_a := 0.0
var spawn_t := 0.0
var obj_t := 0.0
var save_t := 0.0
var cine_t := 0.0
var danger := 0.0
var map_view := false
var world_fresh := true
var worlds_dir := "user://worlds/"
## The world file being played (empty on the title screen before one is chosen).
var save_path := ""
## Which world file the terrain currently in memory belongs to.
var terrain_of := ""
var clouds: Array = []
var cloud_mat: StandardMaterial3D
var part_mesh: BoxMesh
var burst_mesh: BoxMesh
var objectives: Array = []
var discovered := {}


func _ready() -> void:
	randomize()
	# Main keeps running while the tree is paused (menus, sky); pausable children (particles) freeze.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_setup_env()
	world = WorldScript.new()
	add_child(world)
	world.tnt_lit.connect(func(p): spawn_tnt(p, 0.6 + randf() * 0.5))
	world.torch_popped.connect(func(p): pop_drop(B.TORCH, 1, p, VBody.UPS[world.face_of_pos(p)]))
	world.liquid_fused.connect(func(p): Sfx.play3d("fuse", p, -6.0, 1.6); spawn_burst(p, Color(0.55, 0.55, 0.55), 10, 0.6))
	player = PlayerScript.new()
	add_child(player)
	player.setup(self, world)
	ui = UIScript.new()
	add_child(ui)
	ui.setup(self)
	title_cam = Camera3D.new()
	title_cam.far = 2000.0
	title_cam.fov = 55.0
	add_child(title_cam)
	map_cam = Camera3D.new()
	map_cam.far = 2000.0
	map_cam.fov = 50.0
	add_child(map_cam)
	cine_cam = Camera3D.new()
	cine_cam.far = 3000.0
	add_child(cine_cam)
	map_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.9
	cm.height = 40.0
	map_beam.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.3, 1.0, 1.0)
	map_beam.material_override = bm
	map_beam.visible = false
	add_child(map_beam)
	part_mesh = BoxMesh.new()
	part_mesh.size = Vector3(0.13, 0.13, 0.13)
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.roughness = 1.0
	part_mesh.material = pm
	burst_mesh = BoxMesh.new()
	burst_mesh.size = Vector3(0.2, 0.2, 0.2)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.vertex_color_use_as_albedo = true
	burst_mesh.material = bmat
	_build_clouds()
	_define_objectives()
	get_viewport().size_changed.connect(_fit_render_scale)
	_fit_render_scale()
	_boot()


## Keeps the 3D render around 2400 px wide so Retina/4K windows stay smooth; UI stays full resolution.
func _fit_render_scale() -> void:
	var px := float(get_window().size.x)
	get_viewport().scaling_3d_scale = clampf(2400.0 / maxf(px, 1.0), 0.5, 1.0)


func _setup_input() -> void:
	var binds := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT], "jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "descend": [KEY_CTRL, KEY_C],
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _setup_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_strength = 1.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.2
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.3
	add_child(sun)


func _build_clouds() -> void:
	cloud_mat = StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(1, 1, 1, 0.55)
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.roughness = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for f in 6:
		var vb := VBody.new(null)
		vb.set_face(f)
		for k in 9:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(rng.randf_range(6, 12), 0.8, rng.randf_range(4, 9))
			mi.mesh = bm
			mi.material_override = cloud_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mi.global_basis = vb.frame
			clouds.append({"node": mi, "f": f, "u": rng.randf_range(-48, 48), "v": rng.randf_range(-46, 46), "frame": vb.frame, "alt": rng.randf_range(57, 60)})


func _define_objectives() -> void:
	objectives = [
		["Punch a tree", "Hold Left Mouse on a tree trunk to collect logs.", func(): return _has_any([B.LOG, B.BIRCH_LOG, B.SPRUCE_LOG])],
		["Craft planks", "Press E to open crafting, then click Planks.", func(): return _has_any([B.PLANKS, B.SPRUCE_PLANKS, B.BIRCH_PLANKS])],
		["Build a Crafting Table", "Craft it, then place it with Right Mouse.", func(): return _has_any([B.CRAFTING_TABLE])],
		["Craft a Wooden Pickaxe", "Stand near your table. Make sticks first.", func(): return _has_any([B.WOOD_PICK, B.STONE_PICK, B.IRON_PICK, B.DIAMOND_PICK])],
		["Mine some stone", "Dig down through the dirt - stone needs a pickaxe.", func(): return _has_any([B.COBBLE])],
		["Craft a Stone Pickaxe", "Stone tools dig much faster.", func(): return _has_any([B.STONE_PICK, B.IRON_PICK, B.DIAMOND_PICK])],
		["Find coal and craft torches", "Coal ore is speckled black. Torches light caves and keep monsters away.", func(): return _has_any([B.TORCH])],
		["Build a Furnace", "8 cobblestone at a crafting table.", func(): return _has_any([B.FURNACE])],
		["Smelt iron", "Iron ore has peach specks (needs a stone pickaxe). Right-click a furnace: ore on top, fuel (coal or wood) below.", func(): return _has_any([B.IRON_INGOT])],
		["Craft an Iron Pickaxe", "Iron can mine gold and diamonds.", func(): return _has_any([B.IRON_PICK, B.DIAMOND_PICK])],
		["Dig deep for diamonds", "Diamonds hide deep inside the planet - and under the Ashlands.", func(): return _has_any([B.DIAMOND])],
		["Craft a Diamond Pickaxe", "Only diamond can crack the glowing Core Rock.", func(): return _has_any([B.DIAMOND_PICK])],
		["Reach the core: mine Starcore", "Dig toward the planet's center. Beware the lava layer!", func(): return _has_any([B.STARCORE])],
		["Build the Rocket", "Hull + Engine + 3 Fuel Cells + Navigation Core, at a table.", func(): return _has_any([B.ROCKET]) or rocket != null or boss_defeated],
		["Launch: defeat the Core Sentinel", "Place the rocket on open ground and right-click it.", func(): return boss_defeated],
		["ESCAPE THE PLANET!", "Right-click the rocket to launch!", func(): return escaped],
	]


func _has_any(ids: Array) -> bool:
	for id in ids:
		if player.obtained.has(id):
			return true
	return false


# ---------------- boot / game flow ----------------

func _progress(f: float, text: String) -> void:
	ui.set_loading(f, text)


func _boot() -> void:
	ui.show_screen("loading")
	_setup_worlds_dir()
	var data := {}
	var worlds := list_worlds()
	if not worlds.is_empty():
		save_path = worlds[0]["path"]
		data = _read_save()
	if data.is_empty():
		await _load_world(randi() % 1000000, {})
		terrain_of = ""
	else:
		await _load_world(data["seed"], data["edits"], data.get("flow", {}))
		terrain_of = save_path
	_enter_title()


## Worlds live in their own folder. Headless/test runs (a SceneTree script is the main loop) use a
## separate, wiped folder so they never touch the player's worlds. An old single save is migrated.
func _setup_worlds_dir() -> void:
	if Engine.get_main_loop().get_script() != null:
		worlds_dir = "user://test_worlds/"
		DirAccess.make_dir_recursive_absolute(worlds_dir)
		for fn in DirAccess.get_files_at(worlds_dir):
			DirAccess.remove_absolute(worlds_dir + fn)
		return
	DirAccess.make_dir_recursive_absolute(worlds_dir)
	if FileAccess.file_exists(OLD_SAVE_PATH):
		var p := worlds_dir + "world_%d.save" % Time.get_unix_time_from_system()
		DirAccess.rename_absolute(OLD_SAVE_PATH, p)
		_write_meta(p, {"name": "My World", "mode": "survival", "created": Time.get_unix_time_from_system(), "played": Time.get_unix_time_from_system(), "time": 0.0})


func _load_world(seed_val: int, edits: Dictionary, flow := {}) -> void:
	state = "loading"
	ui.show_screen("loading")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clear_entities()
	await world.generate(seed_val, _progress)
	world.edits = edits.duplicate()
	world.apply_edits()
	world.load_flow(flow)
	await world.finish_build(_progress)
	world_fresh = edits.is_empty() and flow.is_empty()


func _enter_title() -> void:
	state = "title"
	title_cam.current = true
	ui.show_screen("title")
	ui.fade_in(1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------- worlds ----------------

func has_save() -> bool:
	return not list_worlds().is_empty()


func _meta_path(save: String) -> String:
	return save.get_basename() + ".meta"


func _write_meta(save: String, meta: Dictionary) -> void:
	var f := FileAccess.open(_meta_path(save), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta))


## Saved worlds, most recently played first: [{path, name, mode, created, played, time}].
func list_worlds() -> Array:
	var out := []
	for fn in DirAccess.get_files_at(worlds_dir):
		if fn.get_extension() != "save":
			continue
		var p := worlds_dir + fn
		var meta := {"name": fn.get_basename(), "mode": "survival", "created": 0, "played": 0, "time": 0.0}
		if FileAccess.file_exists(_meta_path(p)):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(_meta_path(p)))
			if parsed is Dictionary:
				meta.merge(parsed, true)
		meta["path"] = p
		out.append(meta)
	out.sort_custom(func(a, b): return a["played"] > b["played"])
	return out


func delete_world(path: String) -> void:
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_meta_path(path))
	if path == save_path:
		save_path = ""


## Creates a new world file and starts playing it. A numeric or text seed reproduces a planet.
func create_world(world_name: String, mode: String, seed_text := "") -> void:
	var seed_val := randi() % 1000000
	var st := seed_text.strip_edges()
	if st != "":
		seed_val = int(st) if st.is_valid_int() else absi(st.hash()) % 1000000
	var nm := world_name.strip_edges()
	if nm == "":
		nm = "World %d" % (list_worlds().size() + 1)
	save_path = worlds_dir + "world_%d_%d.save" % [Time.get_unix_time_from_system(), randi() % 1000]
	var now := Time.get_unix_time_from_system()
	_write_meta(save_path, {"name": nm, "mode": mode, "created": now, "played": now, "time": 0.0, "seed": seed_val})
	await _load_world(seed_val, {})
	terrain_of = save_path
	_new_game(mode)


func play_world(path: String) -> void:
	save_path = path
	var data := _read_save()
	if data.is_empty():
		return
	# The title screen already shows the most recent world; only regenerate for a different one.
	if terrain_of != path:
		await _load_world(data["seed"], data["edits"], data.get("flow", {}))
		terrain_of = path
	_restore_game(data)


func _read_save() -> Dictionary:
	if save_path == "" or not FileAccess.file_exists(save_path):
		return {}
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var()
	return d if d is Dictionary else {}


## Title-screen entry points: "continue" plays the most recent world; "survival"/"creative" make a new one.
func start_game(mode: String) -> void:
	if mode == "continue":
		var worlds := list_worlds()
		if worlds.is_empty():
			return
		await play_world(worlds[0]["path"])
	else:
		await create_world("", mode)


func _restore_game(data: Dictionary) -> void:
	player.from_dict(data["player"])
	time_of_day = data.get("time", 0.9)
	objective = data.get("objective", 0)
	boss_defeated = data.get("boss_defeated", false)
	escaped = data.get("escaped", false)
	var rd = data.get("rocket", null)
	if rd:
		_spawn_rocket(rd["face"], rd["pos"])
		if boss_defeated:
			rocket.state = "ready"
	for dd in data.get("drops", []):
		spawn_drop(dd[0], dd[1], dd[2], Vector3.ZERO, 0.0)
	if data.has("chests"):
		world.chests = data["chests"]
	if data.has("furnaces"):
		world.furnaces = data["furnaces"]
	if data.has("torch_wall"):
		world.torch_wall = data["torch_wall"]
	_enter_play()


func _new_game(mode: String) -> void:
	player.inv.clear()
	player.inv.resize(player.INV_SIZE)
	player.obtained = {}
	player.stats = {"mined": 0, "placed": 0, "kills": 0, "deaths": 0, "time": 0.0}
	player.creative = mode == "creative"
	player.health = player.max_health
	player.yaw = 0.0
	player.pitch = -0.1
	player.body.flying = false
	var sp: Vector3 = world.find_spawn()
	player.spawn_pos = sp
	player.spawn_face = 2
	player.spawn_at(sp, 2)
	time_of_day = 0.92
	objective = 0
	boss_defeated = false
	escaped = false
	if player.creative:
		for id in [B.GRASS, B.STONE_BRICKS, B.PLANKS, B.GLASS, B.TORCH, B.LAMP, B.TNT, B.DIAMOND_SWORD, B.DIAMOND_PICK]:
			player.add_item(id, B.stack_max(id), false)
	world_fresh = false
	save_game()
	_enter_play()


func _enter_play() -> void:
	player.dead = false
	player.camera_current()
	_update_objective_ui()
	ui.refresh_hotbar()
	_resume_play()
	ui.fade_in(0.8)
	var f: int = player.body.face
	ui.banner(world.BIOME_NAMES[world.FACE_BIOME[f]] + " Face", "Walk off any edge - gravity follows you", 4.0)


func _resume_play() -> void:
	state = "play"
	get_tree().paused = false
	ui.show_screen("")
	player.cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func resume() -> void:
	_resume_play()


func save_and_title() -> void:
	get_tree().paused = false
	save_game()
	_clear_entities()
	rocket = null
	boss = null
	player.cam.current = false
	_enter_title()


func quit_game() -> void:
	if state != "title" and state != "loading" and state != "boot":
		save_game()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if state in ["play", "pause", "inventory", "dead", "confirm", "end"]:
			save_game()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT] and state == "play":
		pause_game()


func pause_game() -> void:
	if state != "play":
		return
	state = "pause"
	ui.show_screen("pause")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.time_scale = 1.0
	get_tree().paused = true
	save_game()


func save_game() -> void:
	if world.world_seed == 0 and world.blocks.is_empty():
		return
	var d := {
		"version": 1, "seed": world.world_seed, "edits": world.edits, "flow": world.save_flow(), "player": player.to_dict(),
		"time": time_of_day, "objective": objective, "boss_defeated": boss_defeated, "escaped": escaped,
		"rocket": {"face": rocket.face, "pos": rocket.base} if (rocket and is_instance_valid(rocket) and rocket.state != "launching") else null,
		"drops": _drop_list(),
		"chests": world.chests,
		"furnaces": world.furnaces,
		"torch_wall": world.torch_wall,
	}
	if save_path == "":
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_var(d)
	var meta := {"name": save_path.get_file().get_basename(), "mode": "creative" if player.creative else "survival", "created": 0}
	if FileAccess.file_exists(_meta_path(save_path)):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(_meta_path(save_path)))
		if parsed is Dictionary:
			meta.merge(parsed, true)
	meta["played"] = Time.get_unix_time_from_system()
	meta["time"] = player.stats["time"]
	meta["escaped"] = escaped
	_write_meta(save_path, meta)


func is_playing() -> bool:
	return state == "play"


# ---------------- input ----------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if state == "play":
					pause_game()
				elif state == "pause":
					_resume_play()
				elif state == "inventory":
					close_inventory()
				elif state == "confirm":
					close_confirm()
			KEY_E, KEY_TAB:
				if state == "play":
					open_inventory()
				elif state == "inventory":
					close_inventory()
			KEY_M:
				if state == "play":
					map_view = true
			KEY_F2:
				_screenshot()
	elif event is InputEventKey and not event.pressed and event.keycode == KEY_M:
		map_view = false
	elif event is InputEventMouseButton and event.pressed and state == "play" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "user://shot_%d.png" % Time.get_ticks_msec()
	img.save_png(path)
	ui.toast("Screenshot saved")


func open_inventory() -> void:
	state = "inventory"
	ui.show_screen("inventory")
	ui.open_inventory()
	Sfx.play("open", -8.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_inventory() -> void:
	ui.close_inventory()
	Sfx.play("close", -10.0)
	_resume_play()


func close_confirm() -> void:
	_resume_play()


## Freezes the action for a split second so hits land with weight.
func hitstop(dur: float) -> void:
	Engine.time_scale = 0.06
	get_tree().create_timer(dur, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func damage_number(pos: Vector3, dmg: float, crit: bool) -> void:
	var l := Label3D.new()
	l.text = ("%d" % roundi(dmg)) + ("!" if crit else "")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = 56 if crit else 44
	l.outline_size = 14
	l.modulate = Color(1.0, 0.85, 0.2) if crit else Color(1, 1, 1)
	l.outline_modulate = Color(0.1, 0.02, 0.0, 0.9)
	l.render_priority = 10
	add_child(l)
	var up: Vector3 = player.body.up()
	var side: Vector3 = player.cam.global_basis.x * randf_range(-0.35, 0.35)
	l.global_position = pos + side
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "global_position", pos + side + up * 0.9, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	l.scale = Vector3.ONE * 1.6
	tw.tween_property(l, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.45)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.3).set_delay(0.45)
	tw.chain().tween_callback(l.queue_free)


# ---------------- main loop ----------------

func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	if state in ["play", "dead", "cinematic", "title", "end"]:
		time_of_day = fmod(time_of_day + dt / DAY_LEN, 1.0)
	var ang := time_of_day * TAU
	var axis := Vector3(1, 1, 1).normalized()
	var p0 := Vector3(-1, 2, -1).normalized()
	var q0 := axis.cross(p0)
	sun_dir = (p0 * cos(ang) + q0 * sin(ang)).normalized()
	match state:
		"title":
			orbit_a += dt * 0.08
			var pos := CENTER + Vector3(cos(orbit_a) * 150.0, 85.0 + sin(orbit_a * 0.7) * 30.0, sin(orbit_a) * 150.0)
			title_cam.global_position = pos
			title_cam.look_at(CENTER + Vector3(0, 8, 0), Vector3.UP)
			world.light_anchor = CENTER
			_update_sky(dt, Vector3.UP, 0.2, false)
		"play":
			player.tick(dt)
			_tick_entities(dt)
			_spawning(dt)
			obj_t -= dt
			if obj_t <= 0.0:
				obj_t = 0.4
				_check_objectives()
			save_t += dt
			if save_t > 60.0:
				save_t = 0.0
				save_game()
			_update_cameras(dt)
			_update_sky(dt, Basis(player.vis_q).y, -1.0, not map_view)
			ui.update_hud(dt)
			_update_info()
		"dead":
			player.tick(dt)
			_tick_entities(dt)
			_update_sky(dt, Basis(player.vis_q).y, -1.0, true)
			ui.update_hud(dt)
		"inventory", "pause", "confirm":
			_update_sky(dt, Basis(player.vis_q).y, -1.0, true)
			ui.update_hud(dt)
		"cinematic":
			_tick_entities(dt)
			_cinematic(dt)
		"end":
			_tick_entities(dt)
			_update_sky(dt, Vector3(0, 1, 0), 0.25, false)
	if state in ["play", "dead", "inventory", "confirm"]:
		world.flow_tick(dt)
		for i in world.furnaces:
			_step_furnace(world.furnaces[i], dt)
	_update_clouds(dt)
	var muffle := 0.0
	if state in ["play", "inventory", "dead"] and world.block_at(player.eye_pos()) == B.WATER:
		muffle = 0.85
	elif state == "pause" or state == "dead":
		muffle = 0.55
	Sfx.set_muffle(muffle, dt)
	ui.update_always(dt)


func _update_cameras(_dt: float) -> void:
	if map_view:
		var up: Vector3 = Basis(player.vis_q).y
		var side: Vector3 = Basis(player.vis_q).z
		map_cam.global_position = CENTER + up * 150.0 + side * 70.0
		map_cam.look_at(CENTER, up)
		map_cam.current = true
		map_beam.visible = true
		map_beam.global_basis = Basis(player.vis_q)
		map_beam.global_position = player.body.pos + up * 20.0
		world.light_anchor = player.body.pos
	else:
		map_beam.visible = false
		if not player.cam.current:
			player.cam.current = true
		world.light_anchor = player.cam.global_position


func _update_sky(dt: float, up: Vector3, forced_day: float, fog: bool) -> void:
	var d := smoothstep(-0.22, 0.3, up.dot(sun_dir))
	if forced_day >= 0.0:
		d = forced_day
	var target_danger := 1.0 if (boss != null and is_instance_valid(boss) and not boss.dead) else 0.0
	danger = move_toward(danger, target_danger, dt * 0.5)
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("up_dir", up)
	sky_mat.set_shader_parameter("day", d)
	sky_mat.set_shader_parameter("danger", danger)
	var su := up.dot(sun_dir) if forced_day < 0.0 else 1.0
	var light_dir := sun_dir
	var sunset := clampf(1.0 - absf(up.dot(sun_dir)) * 2.5, 0.0, 1.0) * d
	if su >= 0.0:
		sun.light_energy = 1.35 * smoothstep(-0.08, 0.2, su)
		sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.6, 0.35), sunset)
	else:
		light_dir = -sun_dir
		sun.light_energy = 0.42 * smoothstep(0.0, 0.25, -su)
		sun.light_color = Color(0.55, 0.65, 1.0)
	sun.visible = sun.light_energy > 0.01
	var hint := Vector3.UP if absf(light_dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	sun.global_basis = Basis.looking_at(-light_dir, hint)
	var amb_day := Color(0.6, 0.66, 0.78)
	var amb_night := Color(0.22, 0.27, 0.48)
	env.ambient_light_color = amb_night.lerp(amb_day, d).lerp(Color(1.0, 0.45, 0.35), danger * 0.35)
	env.ambient_light_energy = lerpf(0.65, 0.85, d)
	var hor := Color(0.03, 0.05, 0.11).lerp(Color(0.62, 0.78, 0.95), d)
	env.fog_light_color = hor.lerp(Color(1.0, 0.55, 0.3), sunset * 0.4)
	env.fog_enabled = fog
	if fog and world.block_at(player.eye_pos()) == B.WATER:
		env.fog_density = 0.09
		env.fog_light_color = Color(0.1, 0.25, 0.55)
	else:
		env.fog_density = 0.0045


func _update_clouds(dt: float) -> void:
	for c in clouds:
		c["u"] += dt * 1.2
		if c["u"] > 50.0:
			c["u"] = -50.0
		var fr: Basis = c["frame"]
		var n: MeshInstance3D = c["node"]
		n.global_position = CENTER + fr.y * c["alt"] + fr.x * c["u"] + fr.z * c["v"]
		n.visible = not map_view


func daylight(face: int) -> float:
	var up: Vector3 = VBody.UPS[face]
	return smoothstep(-0.22, 0.3, up.dot(sun_dir))


func _update_info() -> void:
	var here: Vector3 = player.body.center()
	for s in world.structures:
		if here.distance_squared_to(s["pos"]) >= s["radius"] * s["radius"]:
			continue
		var key: String = "%s@%v" % [s["name"], s["pos"]]
		if not discovered.has(key):
			discovered[key] = true
			ui.banner(s["name"], s["sub"], 3.5, "✦  DISCOVERED  ✦")
			Sfx.play("mission", -6.0, 0.8)
	var f: int = player.body.face
	var biome: String = world.BIOME_NAMES[world.FACE_BIOME[f]]
	var d := daylight(f)
	var tod := "Day" if d > 0.7 else ("Night" if d < 0.2 else "Dusk")
	var c: Vector3 = player.body.center() - CENTER
	var alt := int(maxf(maxf(absf(c.x), absf(c.y)), absf(c.z)))
	var depth_txt := "Altitude %d" % alt
	if alt < world.R:
		depth_txt = "Depth %d to the core" % alt
	ui.set_info(biome + " Face", tod, d, depth_txt, player.creative)


# ---------------- entities ----------------

func _clear_entities() -> void:
	for e in entities:
		if is_instance_valid(e):
			e.queue_free()
	entities.clear()
	boss = null
	rocket = null


func _tick_entities(dt: float) -> void:
	for e in entities.duplicate():
		if is_instance_valid(e) and not e.dead:
			e.tick(dt, player)


func remove_entity(e) -> void:
	entities.erase(e)
	if is_instance_valid(e):
		e.queue_free()


func pick_entity(o: Vector3, d: Vector3, maxd: float):
	var best = null
	var bd := maxd
	for e in entities:
		if not is_instance_valid(e) or e.dead:
			continue
		var t: float = e.hit_test(o, d)
		if t >= 0.0 and t <= bd:
			bd = t
			best = e
	return best


func entity_blocks(bb: AABB) -> bool:
	for e in entities:
		if is_instance_valid(e) and not e.dead and e.blocks(bb):
			return true
	return false


func _count_mobs() -> Vector2i:
	var passive := 0
	var hostile := 0
	for e in entities:
		if e is MobScript:
			if e.hostile:
				hostile += 1
			else:
				passive += 1
	return Vector2i(passive, hostile)


func _spawning(dt: float) -> void:
	spawn_t -= dt
	if spawn_t > 0.0:
		return
	spawn_t = 1.0
	for e in entities.duplicate():
		if e is MobScript and not e.minion and e.global_position.distance_to(player.body.pos) > 72.0:
			remove_entity(e)
	var counts := _count_mobs()
	var fr: Basis = player.body.frame
	var up: Vector3 = player.body.up()
	var a := randf() * TAU
	var dist := randf_range(14.0, 30.0)
	var underground: bool = world.sky_vis_at(player.body.center()) < 0.5
	var feet := Vector3.INF
	if underground:
		var rp: Vector3 = player.body.pos + (fr.x * cos(a) + fr.z * sin(a)) * randf_range(8.0, 18.0) + up * randf_range(-6.0, 6.0)
		feet = _find_cave_floor(rp, up)
	else:
		feet = world.surface_at(player.body.pos + (fr.x * cos(a) + fr.z * sin(a)) * dist + up * 12.0)
	if feet == Vector3.INF:
		return
	var face: int = world.face_of_pos(feet + up * 0.5)
	var fup: Vector3 = VBody.UPS[face]
	var dark: bool = daylight(face) < 0.3 or world.sky_vis_at(feet + fup * 0.5) < 0.3
	if dark:
		if player.creative or counts.y >= 7 or _near_light(feet, 9.0):
			return
		if feet.distance_to(player.body.pos) < 10.0:
			return
		spawn_mob("zombie" if randf() < 0.68 else "boomer", feet, face)
	else:
		if counts.x >= 8:
			return
		var ground: int = world.block_at(feet - fup * 0.5)
		if ground != B.GRASS and ground != B.SNOW:
			return
		var biome: int = world.FACE_BIOME[face]
		var kinds := ["pig", "cow", "sheep"]
		if biome == world.TUNDRA:
			kinds = ["sheep", "sheep", "cow"]
		var k: String = kinds[randi() % kinds.size()]
		var n := randi_range(1, 3)
		for i in n:
			spawn_mob(k, feet + (fr.x * randf_range(-1.5, 1.5) + fr.z * randf_range(-1.5, 1.5)) + fup * 0.2, face)


func _find_cave_floor(p: Vector3, up: Vector3) -> Vector3:
	var q := p
	for i in 14:
		var b: int = world.block_at(q)
		var below: int = world.block_at(q - up)
		var head: int = world.block_at(q + up)
		if B.SOLID[b] == 0 and b != B.WATER and b != B.LAVA and B.SOLID[head] == 0 and B.SOLID[below] == 1:
			var c := Vector3(floorf(q.x) + 0.5, floorf(q.y) + 0.5, floorf(q.z) + 0.5)
			return c - up * 0.5
		q -= up
	return Vector3.INF


func _near_light(p: Vector3, r: float) -> bool:
	var r2 := r * r
	for l in world.light_nodes.values():
		if l.position.distance_squared_to(p) < r2:
			return true
	return false


func spawn_mob(kind: String, feet: Vector3, face: int):
	var m := MobScript.new()
	add_child(m)
	m.setup(self, world, kind, feet, face)
	entities.append(m)
	return m


func summon_minions(pos: Vector3, face: int) -> void:
	var fr := VBody.new(null)
	fr.set_face(face)
	var up: Vector3 = VBody.UPS[face]
	for i in 3:
		var a := randf() * TAU
		var p: Vector3 = world.surface_at(pos + (fr.frame.x * cos(a) + fr.frame.z * sin(a)) * randf_range(6, 10) + up * 10.0)
		if p != Vector3.INF:
			var m = spawn_mob("boomer" if i == 2 else "zombie", p, face)
			m.minion = true
			spawn_burst(p + up, Color(1.0, 0.4, 0.2), 16)
	ui.toast("The Sentinel summons its minions!")


## Drops an item into the world. `delay` = seconds before it can be picked up (so thrown items fly first).
func spawn_drop(id: int, n: int, pos: Vector3, vel: Vector3, delay := 0.35) -> void:
	if id <= 0 or n <= 0:
		return
	var mx := B.stack_max(id)
	while n > 0:
		var k := mini(n, mx)
		n -= k
		var d := DropScript.new()
		add_child(d)
		d.setup(self, world, id, k, pos, vel, delay)
		entities.append(d)


## Pops an item out of a block or mob with a little random hop.
func pop_drop(id: int, n: int, pos: Vector3, up: Vector3) -> void:
	var side := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	side -= up * side.dot(up)
	spawn_drop(id, n, pos, up * 3.5 + side * 1.5)


## Pops out the items stored in a chest or furnace at `c` (being destroyed) and forgets its storage.
func spill_storage(c: Vector3i, b: int) -> void:
	var i := c.x + (c.y << 7) + (c.z << 14)
	var items: Array = []
	if b == B.CHEST:
		items = world.chests.get(i, [])
		world.chests.erase(i)
	elif b == B.FURNACE and world.furnaces.has(i):
		var fz: Dictionary = world.furnaces[i]
		items = [fz["in"], fz["fuel"], fz["out"]]
		world.furnaces.erase(i)
	var pos := Vector3(c) + Vector3(0.5, 0.5, 0.5)
	for s in items:
		if s:
			pop_drop(s["id"], s["n"], pos, VBody.UPS[world.face_of_pos(pos)])


## Throws chunks of the blasted blocks outward; about a third come down as real item drops.
func _blast_debris(center: Vector3, gone: Array) -> void:
	gone.shuffle()
	for g in gone:
		if g[1] == B.CHEST or g[1] == B.FURNACE:
			spill_storage(Vector3i((g[0] as Vector3).floor()), g[1])
	for k in mini(gone.size(), 26):
		var p: Vector3 = gone[k][0]
		var b: int = gone[k][1]
		var out := (p - center).normalized() if p.distance_to(center) > 0.1 else Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)).normalized()
		var up: Vector3 = VBody.UPS[world.face_of_pos(p)]
		var vel := out * randf_range(4.0, 9.0) + up * randf_range(3.0, 7.0)
		var drop_id: int = B.info[b].get("drop", b) if B.info.has(b) else b
		if randf() < 0.33 and drop_id > 0:
			spawn_drop(drop_id, 1, p, vel * 0.6, 0.8)
		else:
			var d := DropScript.new()
			add_child(d)
			d.setup(self, world, b, 1, p, vel, 999.0, true)
			entities.append(d)


func _drop_list() -> Array:
	var out := []
	for e in entities:
		if e is DropScript and is_instance_valid(e) and not e.dead and not e.debris:
			out.append([e.id, e.n, e.body.pos])
	return out


func spawn_tnt(pos: Vector3, fuse := 3.0) -> void:
	var t := TntScript.new()
	add_child(t)
	t.setup(self, world, pos, fuse)
	entities.append(t)


func spawn_bolt(pos: Vector3, vel: Vector3) -> void:
	var b := BoltScript.new()
	add_child(b)
	b.setup(self, world, pos, vel)
	entities.append(b)


func shake_camera(a: float) -> void:
	player.shake = maxf(player.shake, a)


func explode(pos: Vector3, radius: float, dmg: float, no_terrain_near_rocket := false) -> void:
	var protect: bool = rocket != null and is_instance_valid(rocket) and pos.distance_to(rocket.base) < radius + 4.0
	if radius > 0.0 and not protect:
		_blast_debris(pos, world.explode(pos, radius))
	var reach := maxf(radius * 2.2, 3.0)
	if dmg > 0.0:
		var d: float = player.body.center().distance_to(pos)
		if d < reach:
			var k := 1.0 - d / reach
			player.hurt(dmg * k, (player.body.center() - pos).normalized() * 12.0 * k + player.body.up() * 5.0 * k, "explosion")
		for e in entities.duplicate():
			if e is MobScript and is_instance_valid(e) and not e.dead:
				var dm: float = e.body.center().distance_to(pos)
				if dm < reach:
					e.hurt(dmg * (1.0 - dm / reach), (e.body.center() - pos).normalized(), null)
	spawn_burst(pos, Color(1.0, 0.6, 0.2), int(18 + radius * 8), 1.0 + radius * 0.25)
	spawn_burst(pos, Color(0.35, 0.33, 0.32), int(10 + radius * 5), 0.6 + radius * 0.2)
	Sfx.play3d("explode", pos, 4.0 + radius, randf_range(0.85, 1.1))
	var pd: float = player.body.center().distance_to(pos)
	shake_camera(clampf(1.2 - pd / 25.0, 0.0, 1.0) * minf(1.0, radius / 3.0))


func spawn_particles(pos: Vector3, block_id: int, count: int, up: Vector3, col = null) -> void:
	var p := CPUParticles3D.new()
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	p.one_shot = true
	p.amount = count
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.mesh = part_mesh
	p.direction = up
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = -up * 16.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.25
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(0.7, 0.85))
	sc.add_point(Vector2(1, 0))
	p.scale_amount_curve = sc
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.3, 0.3, 0.3)
	var base: Color = col if col != null else T.block_color.get(block_id, Color(0.6, 0.6, 0.6))
	# Random per-chip shade so debris reads as pieces of the texture, not flat confetti.
	var g := Gradient.new()
	g.set_color(0, base.darkened(0.3))
	g.set_color(1, base.lightened(0.18))
	g.add_point(0.5, base)
	p.color_initial_ramp = g
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func spawn_burst(pos: Vector3, col: Color, count: int, size := 1.0) -> void:
	var p := CPUParticles3D.new()
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	p.one_shot = true
	p.amount = maxi(count, 1)
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.mesh = burst_mesh
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 3.0 * size
	p.initial_velocity_max = 8.0 * size
	p.damping_min = 4.0
	p.damping_max = 8.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.8 * size
	p.scale_amount_max = 2.0 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.color = col
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


# ---------------- callbacks ----------------

func on_inventory_changed() -> void:
	ui.refresh_hotbar()
	if state == "inventory":
		ui.refresh_inventory()
		ui.refresh_crafting()


func on_block_broken(_b: int) -> void:
	pass


func on_block_placed(_b: int) -> void:
	pass


func on_face_changed(face: int) -> void:
	var biome: String = world.BIOME_NAMES[world.FACE_BIOME[face]]
	if world.sky_vis_at(player.body.center()) > 0.5:
		ui.banner(biome + " Face", ["Gentle hills and wildflowers", "Dense woods - watch for the dark", "Sand, cactus and scorching sun", "Snow, ice and frozen lakes", "Tall peaks and deep valleys", "Basalt, magma and lava lakes"][world.FACE_BIOME[face]], 3.0)
		Sfx.play("whoosh", -6.0)


func on_mob_killed(_m, by_player: bool) -> void:
	if by_player:
		player.stats["kills"] += 1


func on_player_died(cause: String) -> void:
	state = "dead"
	var msgs := {
		"fall": "You fell from a great height.", "lava": "You tried to swim in lava.", "zombie": "A zombie got you.",
		"explosion": "You were blown up.", "shockwave": "Crushed by the Sentinel's shockwave.", "magma": "The floor was lava. Sort of.",
		"cactus": "Hugged a cactus.",
	}
	ui.death_label.text = msgs.get(cause, "You died.")
	ui.show_death(player.stats)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func respawn() -> void:
	player.respawn()
	_resume_play()
	ui.fade_in(0.6)


func _check_objectives() -> void:
	var advanced := false
	for j in range(objectives.size() - 1, objective - 1, -1):
		if objectives[j][2].call():
			objective = j + 1
			advanced = true
			break
	if advanced:
		Sfx.play("mission", -3.0)
		ui.mission_complete(objectives[objective - 1][0], objectives[objective][0] if objective < objectives.size() else "")
		_update_objective_ui()


func _update_objective_ui() -> void:
	if objective >= objectives.size():
		ui.set_objective(objectives.size() - 1, objectives.size(), "All missions complete!", "Planet Cube is yours. Build anything you can imagine.")
	else:
		var o: Array = objectives[objective]
		ui.set_objective(objective, objectives.size(), o[0], o[1])


# ---------------- crafting ----------------

func station_status() -> Dictionary:
	var out := {"table": false}
	var c: Vector3 = player.body.center()
	var cx := floori(c.x)
	var cy := floori(c.y)
	var cz := floori(c.z)
	for z in range(cz - 4, cz + 5):
		for y in range(cy - 4, cy + 5):
			for x in range(cx - 4, cx + 5):
				if world.get_b(x, y, z) == B.CRAFTING_TABLE:
					out["table"] = true
					return out
	return out


## Furnace recipes are not crafted: they only describe what a furnace smelts (see _step_furnace).
func can_craft(r: Dictionary, st = null) -> bool:
	if r["st"] == "furnace":
		return false
	if player.creative:
		return true
	if st == null:
		st = station_status()
	if r["st"] == "table" and not st["table"]:
		return false
	for id in r["in"]:
		if player.count(id) < r["in"][id]:
			return false
	return true


func craft(r: Dictionary) -> bool:
	var st := station_status()
	if not can_craft(r, st):
		if r["st"] == "furnace":
			ui.toast("Smelt this in a Furnace.")
		elif r["st"] == "table" and not st["table"]:
			ui.toast("You need to be near a Crafting Table.")
		else:
			ui.toast("Missing ingredients.")
		Sfx.play("click", -4.0, 0.6)
		return false
	if not player.creative:
		for id in r["in"]:
			player.remove(id, r["in"][id])
	var left: int = player.add_item(r["out"], r["n"])
	if left > 0:
		ui.toast("Inventory full!")
	Sfx.play("craft", -4.0, randf_range(0.95, 1.08))
	_check_objectives()
	return true


## Advances one furnace by `dt`. Fuel is only lit while the input can smelt into the output slot;
## once lit it burns down regardless. Each item takes B.SMELT_TIME seconds.
func _step_furnace(fz: Dictionary, dt: float) -> void:
	var src = fz["in"]
	var res: Array = B.smelts.get(src["id"], []) if src else []
	var out = fz["out"]
	var can: bool = not res.is_empty() and (out == null or (out["id"] == res[0] and out["n"] + res[1] <= B.stack_max(res[0])))
	if fz["burn"] <= 0.0:
		var fuel = fz["fuel"]
		if not can or fuel == null or not B.fuels.has(fuel["id"]):
			fz["prog"] = maxf(0.0, fz["prog"] - dt * 2.0)
			return
		fz["burn"] = B.fuels[fuel["id"]]
		fz["burn_max"] = fz["burn"]
		fuel["n"] -= 1
		if fuel["n"] <= 0:
			fz["fuel"] = null
	fz["burn"] = maxf(0.0, fz["burn"] - dt)
	if not can:
		fz["prog"] = 0.0
		return
	fz["prog"] += dt
	if fz["prog"] >= B.SMELT_TIME:
		fz["prog"] = 0.0
		if out:
			out["n"] += res[1]
		else:
			fz["out"] = {"id": res[0], "n": res[1]}
		src["n"] -= 1
		if src["n"] <= 0:
			fz["in"] = null


# ---------------- rocket & boss ----------------

func _spawn_rocket(face: int, base: Vector3) -> void:
	rocket = RocketScript.new()
	add_child(rocket)
	rocket.setup(self, face, base)
	entities.append(rocket)


func try_place_rocket(hit: Dictionary, p) -> void:
	if rocket != null and is_instance_valid(rocket):
		ui.toast("You already placed your rocket.")
		return
	var up: Vector3 = p.body.up()
	var n: Vector3i = hit["normal"]
	if Vector3(n) != up:
		ui.toast("Place the rocket on top of flat ground.")
		return
	var cell: Vector3i = hit["pos"] + n
	var fr := VBody.new(null)
	fr.set_face(p.body.face)
	for k in 8:
		for i in range(-1, 2):
			for j in range(-1, 2):
				var c := Vector3(cell) + Vector3(0.5, 0.5, 0.5) + up * k + fr.frame.x * i + fr.frame.z * j
				if B.SOLID[world.block_at(c)] == 1:
					ui.toast("The rocket needs a clear 3x3 space and 8 blocks of sky above.")
					return
	if world.sky_vis_at(Vector3(cell) + Vector3(0.5, 0.5, 0.5) + up * 8.0) < 0.99:
		ui.toast("The rocket must be under open sky.")
		return
	var base := Vector3(cell) + Vector3(0.5, 0.5, 0.5) - up * 0.5
	_spawn_rocket(p.body.face, base)
	p.consume_held()
	Sfx.play("place", 0.0)
	Sfx.play("objective", -6.0, 0.7)
	ui.toast("Rocket placed! Right-click it to begin the launch sequence.", 5.0)


func rocket_interact() -> void:
	if rocket == null:
		return
	if boss != null and is_instance_valid(boss) and not boss.dead:
		ui.toast("The Sentinel's gravity lock holds the rocket! Destroy it!")
		return
	if rocket.state == "launching":
		return
	state = "confirm"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if boss_defeated:
		ui.ask("All systems green.\nLaunch the rocket and leave Planet Cube forever?", _launch)
	else:
		ui.ask("BEGIN LAUNCH SEQUENCE?\n\nThe planet's guardian will awaken to stop you.\nBring a good sword, food and blocks to build with!", _start_boss)
	ui.show_screen("confirm")


func _start_boss() -> void:
	rocket.state = "armed"
	var up: Vector3 = VBody.UPS[rocket.face]
	var fr := VBody.new(null)
	fr.set_face(rocket.face)
	var sp: Vector3 = world.surface_at(rocket.base + fr.frame.x * 3.0 + up * 6.0)
	if sp != Vector3.INF:
		player.spawn_pos = sp
		player.spawn_face = rocket.face
	boss = BossScript.new()
	add_child(boss)
	boss.setup(self, world, rocket.base, rocket.face, player.body.pos)
	entities.append(boss)
	Sfx.play("roar", 4.0, 0.7)
	ui.toast("THE CORE SENTINEL AWAKENS!", 5.0)
	shake_camera(1.0)


func on_boss_killed(b) -> void:
	boss_defeated = true
	var pos: Vector3 = b.global_position
	for i in 4:
		spawn_burst(pos + Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)), Color(1.0, 0.5 + i * 0.1, 0.2), 30, 2.0)
	spawn_burst(pos, Color(1.0, 0.4, 1.0), 40, 2.5)
	Sfx.play("explode", 6.0, 0.6)
	Sfx.play("roar", 2.0, 1.4)
	ui.white_flash(0.8)
	shake_camera(1.0)
	remove_entity(b)
	boss = null
	for e in entities.duplicate():
		if e is MobScript and e.minion:
			e.hurt(999.0, Vector3.ZERO, null)
	if rocket:
		rocket.state = "ready"
	player.add_item(B.DIAMOND, 3)
	ui.toast("The Sentinel is destroyed! Right-click the rocket to LAUNCH!", 6.0)
	_check_objectives()
	save_game()


func _launch() -> void:
	state = "cinematic"
	cine_t = 0.0
	rocket.ignite()
	ui.show_screen("cinematic")
	Sfx.play("launch", 6.0)
	cine_cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _cinematic(dt: float) -> void:
	cine_t += dt
	var up: Vector3 = VBody.UPS[rocket.face]
	var fr := VBody.new(null)
	fr.set_face(rocket.face)
	var side: Vector3 = fr.frame.x
	var rp: Vector3 = rocket.global_position + up * 3.0
	var start: Vector3 = rocket.base + side * 16.0 + fr.frame.z * 6.0 + up * 3.0
	var end_pos := CENTER + up * 190.0 + side * 140.0
	var t := smoothstep(2.5, 11.0, cine_t)
	cine_cam.global_position = start.lerp(end_pos, t)
	var look := rp.lerp(CENTER + up * 40.0, smoothstep(6.0, 12.0, cine_t))
	cine_cam.look_at(look, up)
	if cine_t < 4.0:
		cine_cam.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.15 * (1.0 - cine_t / 4.0)
	world.light_anchor = cine_cam.global_position
	_update_sky(dt, up, -1.0 if cine_t < 6.0 else 0.15, false)
	if cine_t > 13.0:
		escaped = true
		_check_objectives()
		state = "end"
		var s: Dictionary = player.stats
		var mins := int(s["time"]) / 60
		ui.end_stats.text = "Time played: %d min   ·   Blocks mined: %d   ·   Blocks placed: %d\nMonsters defeated: %d   ·   Deaths: %d\n\nThanks for playing!" % [mins, s["mined"], s["placed"], s["kills"], s["deaths"]]
		ui.show_screen("end")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		save_game()


func continue_after_end() -> void:
	if rocket and is_instance_valid(rocket):
		remove_entity(rocket)
	rocket = null
	player.camera_current()
	_update_objective_ui()
	_resume_play()
