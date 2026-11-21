extends Node3D
## First/third-person player: movement on the cube planet, mining, building, combat, inventory.

const EYE := 1.62
const REACH := 5.0
const SLOTS := 36
const VMScript := preload("res://scripts/viewmodel.gd")
const COYOTE := 0.12
const JUMP_BUFFER := 0.15
const EAT_TIME := 1.1

var main
var world
var body: VBody
var head: Node3D
var cam: Camera3D
var vm
var held_light: OmniLight3D
var model: Node3D
var model_item: MeshInstance3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var sel_box: MeshInstance3D
var sel_mat: StandardMaterial3D
var crack: MeshInstance3D
var crack_mat: StandardMaterial3D

var yaw := 0.0
var pitch := 0.0
var vis_q := Quaternion.IDENTITY
var sens := 0.0025
var inv: Array = []
var sel := 0
var health := 20.0
var max_health := 20.0
var creative := false
var view_mode := 0
var obtained := {}
var stats := {"mined": 0, "placed": 0, "kills": 0, "deaths": 0, "time": 0.0}
var spawn_pos := Vector3.ZERO
var spawn_face := 2
var fuel := 0
var dead := false
var target := {}
var target_ent = null
var break_prog := 0.0
var break_pos := Vector3i(-999, 0, 0)
var dig_tick := 0.0
var attack_cd := 0.0
var place_cd := 0.0
var since_hurt := 99.0
var regen_t := 0.0
var step_acc := 0.0
var last_space := -10.0
var last_fwd := -10.0
var sprint_latched := false
var hurt_flash := 0.0
var shake := 0.0
var shake_t := 0.0
var lava_t := 0.0
var held_shown := -2
var walk_phase := 0.0
var cam_dist := 0.0
var coyote := 0.0
var jump_buf := 0.0
var bob_amp := 0.0
var roll := 0.0
var hurt_roll := 0.0
var land_dip := 0.0
var land_vel := 0.0
var punch := 0.0
var eat_prog := 0.0
var eat_tick := 0.0
var was_in_water := false
var hit_marker := 0.0
var sprinting := false


func setup(m, w) -> void:
	main = m
	world = w
	body = VBody.new(world, 0.3, 1.8)
	inv.resize(SLOTS)
	head = Node3D.new()
	head.position = Vector3(0, EYE, 0)
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 78.0
	cam.near = 0.05
	cam.far = 900.0
	head.add_child(cam)
	vm = VMScript.new()
	cam.add_child(vm)
	vm.setup(self)
	held_light = OmniLight3D.new()
	held_light.light_color = Color(1.0, 0.72, 0.42)
	held_light.omni_range = 10.0
	held_light.omni_attenuation = 1.3
	held_light.position = Vector3(0.3, -0.2, -0.3)
	held_light.visible = false
	cam.add_child(held_light)
	_build_model()
	sel_box = MeshInstance3D.new()
	sel_box.mesh = _edge_cube()
	sel_mat = StandardMaterial3D.new()
	sel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sel_mat.albedo_color = Color(0.02, 0.02, 0.04, 0.6)
	sel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sel_box.material_override = sel_mat
	sel_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sel_box.top_level = true
	add_child(sel_box)
	crack = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.006, 1.006, 1.006)
	crack.mesh = bm
	crack_mat = StandardMaterial3D.new()
	crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crack_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	crack_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	crack_mat.uv1_scale = Vector3(3, 2, 1)
	crack.material_override = crack_mat
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crack.top_level = true
	add_child(crack)


## Block outline built from 12 thin bars so it stays visible at any distance (GL lines are 1px).
func _edge_cube() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := 0.504
	var th := 0.016
	for ax in 3:
		for a in [-s, s]:
			for b in [-s, s]:
				var c := Vector3.ZERO
				var size := Vector3(th, th, th)
				size[ax] = s * 2.0 + th
				var o1 := (ax + 1) % 3
				var o2 := (ax + 2) % 3
				c[o1] = a
				c[o2] = b
				var bm := BoxMesh.new()
				bm.size = size
				st.append_from(bm, 0, Transform3D(Basis.IDENTITY, c))
	return st.commit()


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.7
	if emit > 0.0:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = emit
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_model() -> void:
	model = Node3D.new()
	add_child(model)
	var suit := Color(0.95, 0.55, 0.15)
	var white := Color(0.92, 0.93, 0.95)
	_box(model, Vector3(0.5, 0.62, 0.3), Vector3(0, 1.08, 0), suit)
	_box(model, Vector3(0.4, 0.45, 0.18), Vector3(0, 1.1, 0.22), white)
	_box(model, Vector3(0.48, 0.46, 0.46), Vector3(0, 1.62, 0), white)
	_box(model, Vector3(0.38, 0.24, 0.05), Vector3(0, 1.64, -0.235), Color(0.15, 0.4, 0.8), 0.8)
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(0.13 * side, 0.76, 0)
		model.add_child(leg)
		_box(leg, Vector3(0.22, 0.76, 0.26), Vector3(0, -0.38, 0), suit.darkened(0.1))
		legs.append(leg)
		var arm := Node3D.new()
		arm.position = Vector3(0.36 * side, 1.36, 0)
		model.add_child(arm)
		_box(arm, Vector3(0.2, 0.62, 0.22), Vector3(0, -0.28, 0), suit)
		_box(arm, Vector3(0.22, 0.14, 0.24), Vector3(0, -0.55, 0), white)
		arms.append(arm)
	var grip := Node3D.new()
	grip.position = Vector3(0, -0.6, -0.06)
	grip.rotation = Vector3(-PI / 2.0, 0, 0)
	arms[1].add_child(grip)
	model_item = MeshInstance3D.new()
	grip.add_child(model_item)
	model.visible = false


# ---------------- inventory ----------------

func held_id() -> int:
	var s = inv[sel]
	return s["id"] if s else 0


func add_item(id: int, n: int, notify := true) -> int:
	if id <= 0 or n <= 0:
		return 0
	var asked := n
	var mx := B.stack_max(id)
	for i in SLOTS:
		var s = inv[i]
		if s and s["id"] == id and s["n"] < mx:
			var k := mini(mx - s["n"], n)
			s["n"] += k
			n -= k
			if n == 0:
				break
	for i in SLOTS:
		if n == 0:
			break
		if inv[i] == null:
			var k := mini(mx, n)
			inv[i] = {"id": id, "n": k}
			n -= k
	var first := not obtained.has(id)
	if first:
		obtained[id] = true
	if notify and asked > n:
		main.ui.pickup(id, asked - n, first)
	main.on_inventory_changed()
	return n


func count(id: int) -> int:
	var total := 0
	var ids := B.group_members(id)
	for s in inv:
		if s and s["id"] in ids:
			total += s["n"]
	return total


func remove(id: int, n: int) -> void:
	var ids := B.group_members(id)
	for i in SLOTS:
		if n <= 0:
			break
		var s = inv[i]
		if s and s["id"] in ids:
			var k := mini(s["n"], n)
			s["n"] -= k
			n -= k
			if s["n"] <= 0:
				inv[i] = null
	main.on_inventory_changed()


func consume_held(n := 1) -> void:
	if creative:
		return
	var s = inv[sel]
	if s:
		s["n"] -= n
		if s["n"] <= 0:
			inv[sel] = null
		main.on_inventory_changed()


# ---------------- frame / camera ----------------

func spawn_at(p: Vector3, f: int) -> void:
	body.set_face(f)
	body.pos = p
	body.vel = Vector3.ZERO
	vis_q = body.frame.get_rotation_quaternion()
	_sync_transform()


func up() -> Vector3:
	return body.up()


func camera_current() -> void:
	cam.current = true


func eye_pos() -> Vector3:
	return head.global_position


func look_dir() -> Vector3:
	return -head.global_basis.z


func _sync_transform() -> void:
	global_basis = Basis(vis_q) * Basis(Vector3.UP, yaw)
	global_position = body.pos
	head.rotation = Vector3(pitch, 0, 0)


func _unhandled_input(event: InputEvent) -> void:
	if not main.is_playing() or dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative * Cfg.sens_mult()
		yaw -= rel.x * sens
		pitch = clampf(pitch - rel.y * sens * (-1.0 if Cfg.get_v("invert_y") else 1.0), -1.55, 1.55)
		vm.add_look(rel)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_slot((sel + 8) % 9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_slot((sel + 1) % 9)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			place_cd = 0.0
			_use()
		elif event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if target_ent == null and not target and attack_cd <= 0.0:
				vm.swing()
				Sfx.play("swing", -16.0, randf_range(0.9, 1.15))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			select_slot(event.keycode - KEY_1)
		elif event.physical_keycode == KEY_W or event.keycode == KEY_UP:
			var t := Time.get_ticks_msec() / 1000.0
			if t - last_fwd < 0.28:
				sprint_latched = true
			last_fwd = t
		elif event.keycode == KEY_SPACE:
			var now := Time.get_ticks_msec() / 1000.0
			jump_buf = JUMP_BUFFER
			if creative and now - last_space < 0.3:
				body.flying = not body.flying
				body.vel = Vector3.ZERO
				main.ui.toast("Flying " + ("ON" if body.flying else "OFF"))
			last_space = now
		elif event.keycode == KEY_F5 or event.keycode == KEY_V:
			view_mode = (view_mode + 1) % 2
		elif event.keycode == KEY_Q:
			if inv[sel]:
				var s = inv[sel]
				var k: int = s["n"] if event.ctrl_pressed or event.meta_pressed else 1
				s["n"] -= k
				if s["n"] <= 0:
					inv[sel] = null
				var fwd := look_dir()
				main.spawn_drop(s["id"], k, eye_pos() + fwd * 0.5 - body.up() * 0.3, fwd * 6.0 + body.up() * 2.0 + body.vel * 0.5, 1.2)
				vm.swing()
				Sfx.play("swing", -12.0, 1.3)
				main.on_inventory_changed()


func select_slot(i: int) -> void:
	if i == sel:
		return
	sel = i
	eat_prog = 0.0
	Sfx.play("tick", -12.0, 1.0 + i * 0.03)
	main.ui.refresh_hotbar()
	main.ui.pop_slot(i)


func tick(dt: float) -> void:
	stats["time"] += dt
	attack_cd -= dt
	place_cd -= dt
	since_hurt += dt
	hurt_flash = maxf(0.0, hurt_flash - dt * 2.0)
	shake = maxf(0.0, shake - dt * 1.6)
	hit_marker = maxf(0.0, hit_marker - dt * 4.0)
	if dead:
		_sync_transform()
		return
	_movement(dt)
	_interact(dt)
	_survival(dt)
	_visuals(dt)


func _movement(dt: float) -> void:
	var ix := Input.get_axis("move_left", "move_right")
	var iz := Input.get_axis("move_back", "move_forward")
	var basis := body.frame * Basis(Vector3.UP, yaw)
	var fwd := -basis.z
	var right := basis.x
	var wish := fwd * iz + right * ix
	if wish.length() > 1.0:
		wish = wish.normalized()
	if iz <= 0.1:
		sprint_latched = false
	var sprint := (Input.is_action_pressed("sprint") or sprint_latched) and iz > 0.1 and eat_prog <= 0.0
	sprinting = sprint and body.vel.length() > 4.0
	var speed := 4.4
	if sprint:
		speed = 6.4
	if body.flying:
		speed = 14.0 if sprint else 9.0
	if body.in_water:
		speed *= 0.6
	if eat_prog > 0.0:
		speed *= 0.55
	var u := body.up()
	var vu := body.vel.dot(u)
	var hv := body.vel - u * vu
	var grounded := body.on_ground
	coyote = COYOTE if grounded else coyote - dt
	jump_buf -= dt
	var accel := 16.0 if (grounded or body.flying) else 6.0
	if grounded and wish.length() < 0.05:
		accel = 22.0
	hv = hv.lerp(wish * speed, 1.0 - exp(-accel * dt))
	if body.flying:
		var vert := (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("descend") else 0.0)
		vu = lerpf(vu, vert * speed, 1.0 - exp(-10.0 * dt))
	elif body.in_water or body.in_lava:
		if Input.is_action_pressed("jump"):
			vu = minf(vu + 30.0 * dt, 4.5)
	elif coyote > 0.0 and (jump_buf > 0.0 or (grounded and Input.is_action_pressed("jump"))):
		vu = 8.7
		coyote = 0.0
		jump_buf = 0.0
		if sprint:
			hv += wish * 0.8
		Sfx.play("step", -14.0, 1.25)
	body.vel = hv + u * vu
	var was_air := not grounded
	var pre_up := body.up()
	body.step(dt)
	if body.on_ground and was_air and body.land_speed > 3.0:
		var ls := body.land_speed
		_footstep(clampf(-14.0 + ls * 0.7, -14.0, -2.0), 0.8)
		land_vel -= clampf(ls * 0.035, 0.0, 0.45)
		vm.land_impact(ls)
		if ls > 9.0:
			main.spawn_particles(body.pos + u * 0.05, world.block_at(body.pos - u * 0.2), int(clampf(ls * 0.6, 4, 14)), u)
	if body.on_ground and not body.flying and body.land_speed > 15.5 and not body.in_water:
		hurt((body.land_speed - 15.5) * 1.1 + 1.0, Vector3.ZERO, "fall")
	if body.in_water and not was_in_water and absf(vu) > 3.0:
		Sfx.play("splash", -4.0, randf_range(0.9, 1.1))
		main.spawn_particles(body.pos + u * 0.6, B.WATER, 16, u, Color(0.75, 0.88, 1.0))
	was_in_water = body.in_water
	var q := body.update_gravity()
	if q != Quaternion.IDENTITY and pre_up != body.up():
		main.on_face_changed(body.face)
	var hs := hv.length()
	if body.on_ground and hs > 0.5:
		var prev := walk_phase
		walk_phase += hs * dt * 2.1
		if floori(walk_phase / PI) != floori(prev / PI):
			_footstep(-15.0 + hs * 0.4, randf_range(0.9, 1.1))
	else:
		walk_phase = lerpf(walk_phase, roundf(walk_phase / PI) * PI, 1.0 - exp(-8.0 * dt))
	var p := body.pos
	p = p.clamp(Vector3(1.5, 1.5, 1.5), Vector3(126.5, 126.5, 126.5))
	body.pos = p


func _footstep(vol: float, pitch: float) -> void:
	var b: int = world.block_at(body.pos - body.up() * 0.15)
	if b == B.AIR or B.SOLID[b] == 0:
		return
	Sfx.step(B.info[b]["sound"], vol, pitch)


func _interact(dt: float) -> void:
	var eye := eye_pos()
	var dir := look_dir()
	var reach := REACH + (3.0 if creative else 0.0)
	target = world.raycast(eye, dir, reach)
	var bd: float = target["dist"] if target else 999.0
	target_ent = main.pick_entity(eye, dir, minf(reach, bd))
	if target and target_ent == null:
		var p: Vector3i = target["pos"]
		sel_box.visible = true
		sel_box.global_position = Vector3(p) + Vector3(0.5, 0.5, 0.5)
	else:
		sel_box.visible = false
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if lmb and target_ent != null:
		if attack_cd <= 0.0:
			_attack(target_ent, dir)
		break_prog = 0.0
	elif lmb and target:
		_mine(dt)
	else:
		break_prog = 0.0
		break_pos = Vector3i(-999, 0, 0)
	var mining := break_prog > 0.02
	sel_mat.albedo_color = Color(0.02, 0.02, 0.04, 0.6).lerp(Color(1, 1, 1, 0.75), (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)) * 0.5 if mining else 0.0)
	crack.visible = mining
	if crack.visible:
		crack.global_position = Vector3(break_pos) + Vector3(0.5, 0.5, 0.5)
		crack_mat.albedo_texture = T.cracks[clampi(int(break_prog * 10.0), 0, 9)]
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _eat_update(dt, rmb):
		return
	if rmb and place_cd <= 0.0:
		_use()


func is_food(id: int) -> bool:
	var info: Dictionary = B.info.get(id, {})
	return not info.is_empty() and not info["block"] and info["food"] > 0


## Hold Right Mouse with food: chew for EAT_TIME seconds, then heal. Returns true while eating.
func _eat_update(dt: float, rmb: bool) -> bool:
	var id := held_id()
	var eating := rmb and is_food(id) and (health < max_health or creative) and target_ent == null
	if eating and target and (target["block"] == B.CRAFTING_TABLE or target["block"] == B.FURNACE):
		eating = false
	if not eating:
		eat_prog = 0.0
		return false
	eat_prog += dt
	eat_tick -= dt
	if eat_tick <= 0.0:
		eat_tick = 0.22
		Sfx.play("eat", -10.0, randf_range(0.85, 1.2))
		var fwd := look_dir()
		main.spawn_particles(eye_pos() + fwd * 0.45 - body.up() * 0.25, 0, 4, body.up(), T.block_color.get(id, _food_color(id)))
	if eat_prog >= EAT_TIME:
		eat_prog = 0.0
		var info: Dictionary = B.info[id]
		health = minf(max_health, health + info["food"])
		consume_held()
		Sfx.play("burp", -6.0, randf_range(0.95, 1.1))
		main.ui.toast("Ate " + info["name"] + "  +%d health" % info["food"], 2.0)
		main.ui.heal_pulse()
	return true


func _food_color(id: int) -> Color:
	match id:
		B.APPLE:
			return Color(0.85, 0.15, 0.12)
		B.COOKED_MEAT:
			return Color(0.55, 0.3, 0.15)
	return Color(0.9, 0.4, 0.4)


func _attack(ent, dir: Vector3) -> void:
	var tool := B.tool_of(held_id())
	var dmg: float = tool["dmg"] if tool else 1.0
	var crit := body.vel.dot(body.up()) < -1.0
	if crit:
		dmg *= 1.5
		main.spawn_burst(ent.global_position + body.up(), Color(1, 1, 0.6), 8)
	attack_cd = 0.42
	vm.swing()
	hit_marker = 1.0
	punch = 1.0 if crit else 0.6
	Sfx.play("swing", -14.0, randf_range(1.0, 1.2))
	if crit:
		Sfx.play("crit", -6.0, randf_range(0.95, 1.05))
	var hp0 = ent.get("hp")
	var pos: Vector3 = ent.global_position + body.up() * 1.2
	ent.hurt(dmg, dir, self)
	var hp1 = ent.get("hp") if is_instance_valid(ent) else -1.0
	if hp0 != null and hp1 != null and hp1 < hp0:
		main.damage_number(pos, hp0 - maxf(hp1, 0.0), crit)
		main.hitstop(0.07 if crit else 0.045)
		shake = maxf(shake, 0.12)


func break_time(b: int) -> float:
	var info: Dictionary = B.info[b]
	var hard: float = info["hard"]
	if hard < 0.0:
		return INF
	if creative:
		return 0.12
	if hard == 0.0:
		return 0.05
	var tool := B.tool_of(held_id())
	var speed := 1.0
	if tool and tool["tool"] == info["tool"]:
		speed = tool["speed"]
	var t := hard * 1.5 / speed
	if not can_harvest(b):
		t *= 3.3
	return maxf(t, 0.05)


func can_harvest(b: int) -> bool:
	var info: Dictionary = B.info[b]
	if info["tier"] == 0:
		return true
	var tool := B.tool_of(held_id())
	return tool and tool["tool"] == info["tool"] and tool["tier"] >= info["tier"]


func _mine(dt: float) -> void:
	var p: Vector3i = target["pos"]
	var b: int = target["block"]
	if p != break_pos:
		break_pos = p
		break_prog = 0.0
	var t := break_time(b)
	break_prog += dt / t
	if not vm.is_swinging():
		vm.swing()
	dig_tick -= dt
	if dig_tick <= 0.0:
		dig_tick = 0.22
		Sfx.dig(B.info[b]["sound"], -10.0)
		main.spawn_particles(Vector3(p) + Vector3(0.5, 0.5, 0.5) + Vector3(target["normal"]) * 0.52, b, 3, body.up())
	if break_prog >= 1.0:
		break_prog = 0.0
		break_block(p, b)
		if creative:
			break_prog = -1.5


func break_block(p: Vector3i, b: int) -> void:
	var harvest := can_harvest(b) and not creative
	world.set_block(p.x, p.y, p.z, B.AIR)
	_fill_fluids(p)
	stats["mined"] += 1
	Sfx.dig(B.info[b]["sound"], -2.0)
	main.spawn_particles(Vector3(p) + Vector3(0.5, 0.5, 0.5), b, 14, body.up())
	if harvest:
		var drop: int = B.info[b]["drop"]
		var n: int = B.info[b]["drop_n"]
		if b == B.LEAVES or b == B.BIRCH_LEAVES or b == B.SPRUCE_LEAVES:
			var r := randf()
			if r < 0.07:
				drop = B.APPLE
				n = 1
			elif r < 0.17:
				drop = B.STICK
				n = 1
		if drop > 0:
			main.pop_drop(drop, n, Vector3(p) + Vector3(0.5, 0.5, 0.5) - body.up() * 0.2, body.up())
	elif not creative and B.info[b]["tier"] > 0:
		var need: int = B.info[b]["tier"]
		main.ui.toast("Needs a %s pickaxe or better!" % B.TIER_NAMES[need])
	var vf := World_face(p)
	var up_v: Vector3 = VBody.UPS[vf]
	var above := p + Vector3i(up_v)
	var ab: int = world.get_b(above.x, above.y, above.z)
	if B.RENDER[ab] == B.R_CROSS or B.RENDER[ab] == B.R_TORCH:
		world.set_block(above.x, above.y, above.z, B.AIR)
		if ab == B.TORCH or ab == B.FLOWER_RED or ab == B.FLOWER_YELLOW:
			main.pop_drop(ab, 1, Vector3(above) + Vector3(0.5, 0.5, 0.5), body.up())
	main.on_block_broken(b)


func World_face(p: Vector3i) -> int:
	return world.face_of_pos(Vector3(p) + Vector3(0.5, 0.5, 0.5))


func _fill_fluids(p: Vector3i) -> void:
	var f := World_face(p)
	var down_v: Vector3i = -Vector3i(VBody.UPS[f])
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if d == down_v:
			continue
		var q: Vector3i = p + d
		var nb: int = world.get_b(q.x, q.y, q.z)
		if nb == B.WATER or nb == B.LAVA:
			world.set_block(p.x, p.y, p.z, nb)
			return


func _use() -> void:
	if place_cd > 0.0:
		return
	place_cd = 0.22
	if target_ent != null and target_ent.has_method("interact"):
		target_ent.interact(self)
		return
	var id := held_id()
	if is_food(id):
		if health >= max_health and not creative:
			main.ui.toast("You're not hungry - save it for later")
		return
	if not target:
		return
	var tb: int = target["block"]
	var tp: Vector3i = target["pos"]
	if (tb == B.CRAFTING_TABLE or tb == B.FURNACE) and not Input.is_action_pressed("sprint"):
		main.open_inventory()
		return
	if tb == B.TNT:
		world.set_block(tp.x, tp.y, tp.z, B.AIR)
		main.spawn_tnt(Vector3(tp) + Vector3(0.5, 0.5, 0.5))
		return
	if id == B.ROCKET:
		main.try_place_rocket(target, self)
		return
	if not B.is_block(id):
		return
	var np: Vector3i = tp + target["normal"]
	var cur: int = world.get_b(np.x, np.y, np.z)
	if not (cur == B.AIR or cur == B.WATER or cur == B.LAVA or B.RENDER[cur] == B.R_CROSS):
		return
	if not world.in_bounds(np.x, np.y, np.z) or np.x < 2 or np.y < 2 or np.z < 2 or np.x > 125 or np.y > 125 or np.z > 125:
		return
	if B.SOLID[id] == 1:
		var bb := AABB(Vector3(np), Vector3.ONE).grow(-0.01)
		if bb.intersects(body.aabb()) and not body.flying:
			return
		if main.entity_blocks(bb):
			return
	world.set_block(np.x, np.y, np.z, id)
	stats["placed"] += 1
	consume_held()
	vm.swing()
	var center := Vector3(np) + Vector3(0.5, 0.5, 0.5)
	main.spawn_particles(center - Vector3(target["normal"]) * 0.45, id, 6, body.up())
	Sfx.dig(B.info[id]["sound"], -4.0, 0.8)
	main.on_block_placed(id)


func _survival(dt: float) -> void:
	if creative:
		health = max_health
		return
	if body.in_lava:
		lava_t -= dt
		if lava_t <= 0.0:
			lava_t = 0.5
			hurt(3.0, Vector3.ZERO, "lava")
	var feet_b: int = world.block_at(body.pos - body.up() * 0.1)
	if feet_b == B.MAGMA and body.on_ground:
		lava_t -= dt
		if lava_t <= 0.0:
			lava_t = 0.8
			hurt(1.0, Vector3.ZERO, "magma")
	if feet_b == B.CACTUS or world.block_at(body.center()) == B.CACTUS:
		lava_t -= dt
		if lava_t <= 0.0:
			lava_t = 0.6
			hurt(1.0, Vector3.ZERO, "cactus")
	if since_hurt > 5.0 and health < max_health:
		regen_t += dt
		if regen_t > 2.5:
			regen_t = 0.0
			health = minf(max_health, health + 1.0)


func hurt(amount: float, knock: Vector3, cause := "") -> void:
	if creative or dead or amount <= 0.0:
		return
	health -= amount
	since_hurt = 0.0
	regen_t = 0.0
	hurt_flash = 1.0
	shake = minf(1.0, shake + amount * 0.15)
	var k_local := cam.global_basis.inverse() * knock if knock != Vector3.ZERO else Vector3(randf_range(-1, 1), 0, 0)
	hurt_roll = clampf(-k_local.x * 0.02, -0.07, 0.07) if absf(k_local.x) > 0.1 else (0.05 if randf() < 0.5 else -0.05)
	vm.on_hurt()
	main.ui.on_player_hurt()
	Sfx.play("hurt", -2.0, randf_range(0.9, 1.1))
	if knock != Vector3.ZERO:
		body.vel += knock
	if health <= 0.0:
		health = 0.0
		dead = true
		stats["deaths"] += 1
		main.on_player_died(cause)


func respawn() -> void:
	dead = false
	health = max_health
	spawn_at(spawn_pos, spawn_face)


func _visuals(dt: float) -> void:
	vis_q = vis_q.slerp(body.frame.get_rotation_quaternion(), 1.0 - exp(-9.0 * dt))
	_sync_transform()
	var u := body.up()
	var hv := body.vel - u * body.vel.dot(u)
	var hs := hv.length()
	var bob_on: bool = Cfg.get_v("view_bob")
	var bob_target := clampf(hs / 4.4, 0.0, 1.5) if (body.on_ground and not body.flying and bob_on) else 0.0
	bob_amp = lerpf(bob_amp, bob_target, 1.0 - exp(-10.0 * dt))
	# Landing spring: the view dips and recovers.
	land_vel += -land_dip * 160.0 * dt
	land_vel *= exp(-13.0 * dt)
	land_dip += land_vel * dt * 6.0
	var hp := Vector3(sin(walk_phase) * 0.028 * bob_amp, EYE - absf(cos(walk_phase)) * 0.045 * bob_amp + land_dip, 0)
	# Smooth noise shake (not per-frame jitter), quadratic falloff.
	shake_t += dt * 32.0
	var sh := shake * shake
	if sh > 0.0:
		hp += Vector3(sin(shake_t * 1.13) + sin(shake_t * 2.71) * 0.5, sin(shake_t * 1.71 + 1.3) + sin(shake_t * 3.1) * 0.5, 0) * sh * 0.09
	head.position = hp
	# Strafe lean, step roll, hurt kick, attack punch.
	var ix := Input.get_axis("move_left", "move_right")
	roll = lerpf(roll, -ix * 0.018 * (1.0 if bob_on else 0.0), 1.0 - exp(-6.0 * dt))
	hurt_roll = lerpf(hurt_roll, 0.0, 1.0 - exp(-7.0 * dt))
	punch = maxf(0.0, punch - dt * 6.0)
	cam.rotation = Vector3(-punch * 0.025 + sh * sin(shake_t * 0.9) * 0.02, 0, roll + hurt_roll + sin(walk_phase) * 0.004 * bob_amp + sh * sin(shake_t * 1.4) * 0.03)
	var base_fov: float = Cfg.get_v("fov")
	var fov_target := base_fov
	if sprinting:
		fov_target = base_fov + 9.0
	if body.flying and hs > 10.0:
		fov_target += 5.0
	if eat_prog > 0.0:
		fov_target -= 4.0
	cam.fov = lerpf(cam.fov, fov_target, 1.0 - exp(-8.0 * dt))
	var id := held_id()
	if id != held_shown:
		held_shown = id
		VMScript.dress(model_item, id, world, 2.2)
	var lit: float = B.LIGHT[id] if B.is_block(id) else (0.5 if id == B.STARCORE else 0.0)
	held_light.visible = lit > 0.0
	if held_light.visible:
		held_light.light_energy = 2.0 * (1.0 + sin(Time.get_ticks_msec() * 0.023) * 0.05 + sin(Time.get_ticks_msec() * 0.037) * 0.04)
		held_light.light_color = Color(0.95, 0.5, 1.0) if id == B.STARCORE else Color(1.0, 0.72, 0.42)
	vm.update(dt, id, hs, body.on_ground, sprinting, eat_prog > 0.0, walk_phase)
	var third := view_mode == 1
	model.visible = third
	var want := 0.0
	if third:
		var back := head.global_basis.z
		var hit: Dictionary = world.raycast(eye_pos(), back, 4.5)
		want = (hit["dist"] - 0.35) if hit else 4.5
		want = maxf(want, 0.4)
	cam_dist = lerpf(cam_dist, want, 1.0 - exp(-12.0 * dt)) if third else 0.0
	cam.position = Vector3(0, 0.25 * (cam_dist / 4.5), cam_dist)
	var sw_leg := sin(walk_phase) * 0.7 * clampf(hs / 3.0, 0.0, 1.0)
	var swing_arc := sin(sqrt(vm.swing_t) * PI) if vm.is_swinging() else 0.0
	if legs.size() == 2:
		legs[0].rotation.x = sw_leg
		legs[1].rotation.x = -sw_leg
		arms[0].rotation.x = -sw_leg * 0.8
		arms[1].rotation.x = sw_leg * 0.8 - swing_arc * 1.4 - (0.9 if eat_prog > 0.0 else 0.0)


func _process(_dt: float) -> void:
	vm.visible = view_mode == 0 and not dead and not main.map_view and cam.current and main.state in ["play", "inventory", "pause", "confirm"]
	if main.state != "play":
		held_light.visible = held_light.visible and main.state in ["inventory", "pause", "confirm"]


# ---------------- save ----------------

func to_dict() -> Dictionary:
	var fr := body.frame
	return {
		"pos": body.pos, "face": body.face, "frame": [fr.x, fr.y, fr.z], "yaw": yaw, "pitch": pitch,
		"inv": inv, "sel": sel, "health": health, "creative": creative, "stats": stats,
		"obtained": obtained, "spawn": spawn_pos, "spawn_face": spawn_face, "fuel": fuel,
	}


func from_dict(d: Dictionary) -> void:
	body.face = d["face"]
	var fr: Array = d["frame"]
	body.frame = Basis(fr[0], fr[1], fr[2])
	body.pos = d["pos"]
	yaw = d["yaw"]
	pitch = d["pitch"]
	inv = d["inv"]
	inv.resize(SLOTS)
	sel = d["sel"]
	health = d["health"]
	creative = d["creative"]
	stats = d["stats"]
	obtained = d["obtained"]
	spawn_pos = d["spawn"]
	spawn_face = d["spawn_face"]
	fuel = d.get("fuel", 0)
	vis_q = body.frame.get_rotation_quaternion()
	_sync_transform()
