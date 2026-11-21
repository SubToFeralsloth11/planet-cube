extends Node3D
## The Core Sentinel: the planet's guardian that tries to stop the rocket launch.

const MAX_HP := 420.0

var main
var world
var hp := MAX_HP
var up := Vector3.UP
var face := 2
var state := "rise"
var st := 0.0
var fire_t := 1.5
var enraged := false
var slam_target := Vector3.ZERO
var dead := false
var flash := 0.0
var summon_t := 0.0
var orbit := 0.0
var core: MeshInstance3D
var core_mat: StandardMaterial3D
var eye_mat: StandardMaterial3D
var eye: Node3D
var orbiters: Array[MeshInstance3D] = []
var glow: OmniLight3D
var death_t := 0.0
var home := Vector3.ZERO
var hover_time := 6.0


func setup(m, w, rocket_pos: Vector3, f: int, player_pos: Vector3) -> void:
	main = m
	world = w
	face = f
	up = VBody.UPS[f]
	home = rocket_pos
	var away := player_pos - rocket_pos
	away = away - up * away.dot(up)
	if away.length() < 0.5:
		away = VBody.UPS[(f + 2) % 6]
	away = away.normalized()
	global_position = rocket_pos + away * 12.0 - up * 4.0
	_build()


func _build() -> void:
	core = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 3.0, 3.0)
	core.mesh = bm
	core_mat = StandardMaterial3D.new()
	var tex := ImageTexture.create_from_image(T.images["core_rock"])
	core_mat.albedo_texture = tex
	core_mat.emission_enabled = true
	core_mat.emission_texture = tex
	core_mat.emission_energy_multiplier = 1.6
	core_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	core_mat.uv1_scale = Vector3(3, 2, 1)
	core.material_override = core_mat
	add_child(core)
	eye = Node3D.new()
	eye.position = Vector3(0, 0, -1.45)
	add_child(eye)
	var white := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(1.4, 0.9, 0.2)
	white.mesh = em
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.95, 0.9, 0.85)
	white.material_override = wm
	eye.add_child(white)
	var iris := MeshInstance3D.new()
	var im := BoxMesh.new()
	im.size = Vector3(0.55, 0.55, 0.22)
	iris.mesh = im
	eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.2, 0.1)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.2, 0.1)
	eye_mat.emission_energy_multiplier = 3.0
	iris.material_override = eye_mat
	iris.position = Vector3(0, 0, -0.03)
	eye.add_child(iris)
	var om := BoxMesh.new()
	om.size = Vector3(0.9, 0.9, 0.9)
	var omat := StandardMaterial3D.new()
	omat.albedo_texture = ImageTexture.create_from_image(T.images["obsidian"])
	omat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	omat.emission_enabled = true
	omat.emission = Color(0.6, 0.2, 1.0)
	omat.emission_energy_multiplier = 0.4
	for k in 6:
		var o := MeshInstance3D.new()
		o.mesh = om
		o.material_override = omat
		add_child(o)
		orbiters.append(o)
	glow = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.35, 0.15)
	glow.omni_range = 16.0
	glow.light_energy = 2.5
	add_child(glow)


func vulnerable() -> bool:
	return state == "stunned"


func tick(dt: float, player) -> void:
	st += dt
	flash = maxf(0.0, flash - dt * 3.0)
	orbit += dt * (2.5 if enraged else 1.6)
	var pc: Vector3 = player.body.center()
	match state:
		"rise":
			global_position += up * dt * 3.2
			main.shake_camera(0.25)
			if st > 2.6:
				_set_state("hover")
				Sfx.play("roar", 2.0)
		"hover":
			var tng := Vector3(cos(orbit * 0.5), 0, sin(orbit * 0.5))
			var frame_b := VBody.new(null)
			frame_b.set_face(face)
			var off: Vector3 = frame_b.frame * tng * 5.0
			var tgt: Vector3 = player.body.pos + up * 7.5 + off
			global_position = global_position.lerp(tgt, 1.0 - exp(-1.4 * dt))
			fire_t -= dt
			if fire_t <= 0.0 and not player.dead:
				fire_t = 0.85 if enraged else 1.35
				_fire(pc, player)
			if st > hover_time:
				_set_state("telegraph")
				slam_target = player.body.pos
				Sfx.play("charge", 0.0)
		"telegraph":
			global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.06
			if st > 0.9:
				_set_state("slam")
		"slam":
			var tgt := slam_target + up * 1.6
			var d := tgt - global_position
			var stepv := 30.0 * dt
			var p := global_position
			var hit_ground: bool = world.solid(floori(p.x - up.x * 1.6), floori(p.y - up.y * 1.6), floori(p.z - up.z * 1.6))
			if d.length() <= stepv or hit_ground:
				if not hit_ground:
					global_position = tgt
				_impact(player)
			else:
				global_position += d.normalized() * stepv
		"stunned":
			if st > (3.2 if enraged else 4.0):
				_set_state("recover")
		"recover":
			global_position += up * dt * 6.0
			if st > 1.1:
				_set_state("hover")
	if enraged and state != "rise":
		summon_t -= dt
		if summon_t <= 0.0:
			summon_t = 24.0
			main.summon_minions(player.body.pos, face)
	var look := pc - global_position
	if look.length() > 0.5 and state != "stunned":
		var want := Basis.looking_at(look.normalized(), up if absf(look.normalized().dot(up)) < 0.98 else VBody.UPS[(face + 2) % 6])
		global_basis = global_basis.slerp(want, 1.0 - exp(-4.0 * dt)).orthonormalized()
	var stun := state == "stunned"
	for k in orbiters.size():
		var a := orbit + k * TAU / orbiters.size()
		var r := 3.2 if not stun else 2.6
		var o := orbiters[k]
		if stun:
			o.position = o.position.lerp(Vector3(cos(a) * r, -1.2, sin(a) * r), 1.0 - exp(-6.0 * dt))
		else:
			o.position = Vector3(cos(a) * r, sin(a * 2.0) * 0.8, sin(a) * r)
		o.rotation = Vector3(a, a * 1.3, 0)
	var eye_col := Color(1.0, 0.95, 0.2) if stun else (Color(1.0, 0.15, 0.1) if state != "telegraph" else Color(1, 1, 1))
	eye_mat.emission = eye_col
	eye_mat.albedo_color = eye_col
	eye_mat.emission_energy_multiplier = (6.0 if stun else 3.0) + sin(st * 12.0) * 1.0
	core_mat.emission_energy_multiplier = 1.6 + flash * 4.0 + (2.0 if state == "telegraph" else 0.0)
	glow.light_energy = 2.5 + flash * 3.0


func _set_state(s: String) -> void:
	state = s
	st = 0.0
	if s == "hover":
		hover_time = randf_range(4.0, 5.5) if enraged else randf_range(5.5, 7.5)


func _fire(target: Vector3, player) -> void:
	var lead: Vector3 = player.body.vel * 0.35
	var shots := 3 if enraged else 1
	for s in shots:
		var aim := (target + lead - global_position).normalized()
		if s > 0:
			var side := aim.cross(up).normalized()
			aim = (aim + side * (0.22 if s == 1 else -0.22)).normalized()
		main.spawn_bolt(global_position + aim * 2.0, aim * (17.0 if enraged else 14.0))
	Sfx.play3d("bolt", global_position, 0.0)


func _impact(player) -> void:
	_set_state("stunned")
	main.explode(global_position - up * 1.4, 2.4, 0.0, true)
	main.shake_camera(1.0)
	var to_p: Vector3 = player.body.pos - global_position
	var tang := to_p - up * to_p.dot(up)
	if tang.length() < 7.5 and player.body.on_ground:
		player.hurt(7.0, tang.normalized() * 9.0 + up * 7.0, "shockwave")
		main.ui.toast("Jump over the shockwave!")


func hit_test(o: Vector3, d: Vector3) -> float:
	var bb := AABB(global_position - Vector3(1.7, 1.7, 1.7), Vector3(3.4, 3.4, 3.4))
	var hit = bb.intersects_ray(o, d)
	if hit == null:
		return -1.0
	return o.distance_to(hit)


func blocks(_bb: AABB) -> bool:
	return false


func hurt(dmg: float, _dir: Vector3, attacker) -> void:
	if dead or state == "rise":
		return
	if not vulnerable():
		Sfx.play3d("clang", global_position, 0.0)
		flash = 0.3
		if attacker != null:
			main.ui.toast("Its shell deflects you! Wait for it to SLAM, then strike the eye.")
		return
	hp -= dmg * 2.0
	flash = 1.0
	Sfx.play3d("hit", global_position, 2.0, 0.6)
	main.spawn_burst(global_position, Color(1.0, 0.5, 0.15), 10)
	if not enraged and hp < MAX_HP * 0.5:
		enraged = true
		summon_t = 0.5
		Sfx.play("roar", 4.0, 0.8)
		main.ui.toast("THE SENTINEL IS ENRAGED!")
		_set_state("recover")
	if hp <= 0.0:
		hp = 0.0
		dead = true
		main.on_boss_killed(self)
