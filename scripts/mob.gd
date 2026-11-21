extends Node3D
## Animals and monsters that walk around the cube planet.

const DATA := {
	"pig": {"hp": 10.0, "speed": 2.2, "hw": 0.4, "h": 0.9, "hostile": false},
	"cow": {"hp": 12.0, "speed": 2.0, "hw": 0.45, "h": 1.3, "hostile": false},
	"sheep": {"hp": 10.0, "speed": 2.1, "hw": 0.42, "h": 1.2, "hostile": false},
	"zombie": {"hp": 20.0, "speed": 3.3, "hw": 0.3, "h": 1.85, "hostile": true},
	"boomer": {"hp": 16.0, "speed": 3.0, "hw": 0.3, "h": 1.6, "hostile": true},
}
const WOOLS := [39, 39, 39, 39, 40, 42, 44, 46]

var main
var world
var kind := "pig"
var body: VBody
var vis_q := Quaternion.IDENTITY
var yaw := 0.0
var hp := 10.0
var hostile := false
var speed := 2.0
var ai_t := 0.0
var wish := Vector3.ZERO
var flash := 0.0
var attack_cd := 0.0
var fuse := -1.0
var panic := 0.0
var legs: Array[Node3D] = []
var mats: Array[StandardMaterial3D] = []
var walk := 0.0
var sound_t := 0.0
var wool := 39
var minion := false
var burn_t := 0.0
var dead := false
var age := 0.0


func setup(m, w, k: String, pos: Vector3, face: int) -> void:
	main = m
	world = w
	kind = k
	var d: Dictionary = DATA[k]
	hp = d["hp"]
	speed = d["speed"]
	hostile = d["hostile"]
	body = VBody.new(world, d["hw"], d["h"])
	body.set_face(face)
	body.pos = pos
	vis_q = body.frame.get_rotation_quaternion()
	yaw = randf() * TAU
	sound_t = randf_range(3, 12)
	if k == "sheep":
		wool = WOOLS[randi() % WOOLS.size()]
	_build()
	_sync()


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.85
	if emit > 0.0:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = emit
	else:
		mats.append(mat)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _leg(pos: Vector3, size: Vector3, col: Color) -> void:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	_box(n, size, Vector3(0, -size.y * 0.5, 0), col)
	legs.append(n)


func _build() -> void:
	match kind:
		"pig":
			var pink := Color(0.95, 0.62, 0.62)
			_box(self, Vector3(0.62, 0.5, 0.9), Vector3(0, 0.6, 0), pink)
			_box(self, Vector3(0.5, 0.48, 0.45), Vector3(0, 0.72, -0.6), pink)
			_box(self, Vector3(0.26, 0.16, 0.08), Vector3(0, 0.66, -0.86), Color(0.9, 0.45, 0.5))
			_box(self, Vector3(0.08, 0.08, 0.02), Vector3(-0.14, 0.82, -0.83), Color(0.05, 0.05, 0.05))
			_box(self, Vector3(0.08, 0.08, 0.02), Vector3(0.14, 0.82, -0.83), Color(0.05, 0.05, 0.05))
			for p in [Vector3(-0.2, 0.36, -0.3), Vector3(0.2, 0.36, -0.3), Vector3(-0.2, 0.36, 0.3), Vector3(0.2, 0.36, 0.3)]:
				_leg(p, Vector3(0.18, 0.36, 0.18), pink.darkened(0.1))
		"cow":
			var brown := Color(0.36, 0.24, 0.16)
			_box(self, Vector3(0.75, 0.62, 1.1), Vector3(0, 0.95, 0), brown)
			_box(self, Vector3(0.76, 0.3, 0.5), Vector3(0, 1.08, 0.15), Color(0.92, 0.92, 0.9))
			_box(self, Vector3(0.55, 0.5, 0.45), Vector3(0, 1.15, -0.72), brown)
			_box(self, Vector3(0.4, 0.22, 0.1), Vector3(0, 1.02, -0.97), Color(0.85, 0.7, 0.65))
			_box(self, Vector3(0.7, 0.08, 0.08), Vector3(0, 1.44, -0.7), Color(0.9, 0.88, 0.8))
			_box(self, Vector3(0.08, 0.08, 0.02), Vector3(-0.16, 1.24, -0.95), Color(0.05, 0.05, 0.05))
			_box(self, Vector3(0.08, 0.08, 0.02), Vector3(0.16, 1.24, -0.95), Color(0.05, 0.05, 0.05))
			for p in [Vector3(-0.24, 0.64, -0.38), Vector3(0.24, 0.64, -0.38), Vector3(-0.24, 0.64, 0.38), Vector3(0.24, 0.64, 0.38)]:
				_leg(p, Vector3(0.2, 0.64, 0.2), brown.darkened(0.15))
		"sheep":
			var wc: Color = T.block_color.get(wool, Color.WHITE)
			_box(self, Vector3(0.78, 0.66, 1.0), Vector3(0, 0.88, 0), wc)
			_box(self, Vector3(0.42, 0.42, 0.4), Vector3(0, 1.08, -0.62), Color(0.35, 0.3, 0.28))
			_box(self, Vector3(0.08, 0.08, 0.02), Vector3(-0.12, 1.14, -0.83), Color(0.95, 0.95, 0.95))
			_box(self, Vector3(0.08, 0.08, 0.02), Vector3(0.12, 1.14, -0.83), Color(0.95, 0.95, 0.95))
			for p in [Vector3(-0.22, 0.55, -0.32), Vector3(0.22, 0.55, -0.32), Vector3(-0.22, 0.55, 0.32), Vector3(0.22, 0.55, 0.32)]:
				_leg(p, Vector3(0.17, 0.55, 0.17), Color(0.35, 0.3, 0.28))
		"zombie":
			var skin := Color(0.35, 0.6, 0.35)
			_box(self, Vector3(0.5, 0.7, 0.28), Vector3(0, 1.1, 0), Color(0.2, 0.55, 0.6))
			_box(self, Vector3(0.46, 0.46, 0.46), Vector3(0, 1.69, 0), skin)
			_box(self, Vector3(0.1, 0.07, 0.02), Vector3(-0.11, 1.72, -0.235), Color(0.05, 0.05, 0.05))
			_box(self, Vector3(0.1, 0.07, 0.02), Vector3(0.11, 1.72, -0.235), Color(0.05, 0.05, 0.05))
			_box(self, Vector3(0.18, 0.18, 0.62), Vector3(-0.34, 1.32, -0.28), skin)
			_box(self, Vector3(0.18, 0.18, 0.62), Vector3(0.34, 1.32, -0.28), skin)
			_leg(Vector3(-0.13, 0.76, 0), Vector3(0.22, 0.76, 0.24), Color(0.25, 0.25, 0.55))
			_leg(Vector3(0.13, 0.76, 0), Vector3(0.22, 0.76, 0.24), Color(0.25, 0.25, 0.55))
		"boomer":
			var g := Color(0.35, 0.68, 0.3)
			_box(self, Vector3(0.5, 0.78, 0.36), Vector3(0, 0.84, 0), g)
			_box(self, Vector3(0.52, 0.52, 0.52), Vector3(0, 1.5, 0), g.lightened(0.08))
			for p in [Vector3(-0.12, 1.58, -0.265), Vector3(0.12, 1.58, -0.265), Vector3(0, 1.44, -0.265), Vector3(-0.08, 1.38, -0.265), Vector3(0.08, 1.38, -0.265)]:
				_box(self, Vector3(0.1, 0.1, 0.02), p, Color(0.03, 0.05, 0.03))
			for p in [Vector3(-0.14, 0.45, -0.18), Vector3(0.14, 0.45, -0.18), Vector3(-0.14, 0.45, 0.18), Vector3(0.14, 0.45, 0.18)]:
				_leg(p, Vector3(0.2, 0.45, 0.2), g.darkened(0.15))


func _sync() -> void:
	global_basis = Basis(vis_q) * Basis(Vector3.UP, yaw)
	global_position = body.pos


func tick(dt: float, player) -> void:
	age += dt
	attack_cd -= dt
	panic -= dt
	flash = maxf(0.0, flash - dt * 4.0)
	var u := body.up()
	var to_p: Vector3 = player.body.pos - body.pos
	var dist := to_p.length()
	var run := false
	var chase: bool = hostile and dist < 26.0 and not player.dead and not player.creative
	if chase:
		var tng := to_p - u * to_p.dot(u)
		wish = tng.normalized() if tng.length() > 0.4 else Vector3.ZERO
		run = true
		if kind == "zombie" and dist < 1.7 and attack_cd <= 0.0:
			attack_cd = 1.0
			player.hurt(3.0, wish * 5.0 + u * 3.5, "zombie")
		elif kind == "boomer":
			if dist < 2.8 and fuse < 0.0:
				fuse = 1.5
				Sfx.play3d("fuse", global_position, 0.0)
			if fuse >= 0.0:
				wish = Vector3.ZERO
				fuse -= dt
				if dist > 6.0:
					fuse = -1.0
				elif fuse <= 0.0:
					_boom()
					return
	elif panic > 0.0:
		run = true
		if ai_t <= 0.0:
			ai_t = 0.8
			var away := -to_p
			away = (away - u * away.dot(u)).normalized()
			wish = (away + _rand_tangent() * 0.5).normalized()
	elif ai_t <= 0.0:
		ai_t = randf_range(2.0, 5.0)
		wish = _rand_tangent() if randf() < 0.65 else Vector3.ZERO
	ai_t -= dt
	var vu := body.vel.dot(u)
	var hv := body.vel - u * vu
	var sp := speed * (1.6 if (run and not hostile) else 1.0)
	hv = hv.lerp(wish * sp, 1.0 - exp(-(10.0 if body.on_ground else 2.0) * dt))
	if body.hit_wall and body.on_ground and wish != Vector3.ZERO:
		vu = 8.2
	if body.in_water and wish != Vector3.ZERO:
		vu = maxf(vu, 2.5)
	body.vel = hv + u * vu
	body.step(dt)
	body.update_gravity()
	if body.in_lava:
		hurt(dt * 6.0, Vector3.ZERO, null)
	if hostile and kind == "zombie" and not minion:
		if world.sky_vis_at(body.center()) > 0.95 and main.daylight(body.face) > 0.6:
			burn_t += dt
			flash = maxf(flash, 0.5)
			if burn_t > 0.5:
				burn_t = 0.0
				hurt(1.5, Vector3.ZERO, null)
	if wish != Vector3.ZERO:
		var local: Vector3 = body.frame.inverse() * wish
		var ty := atan2(-local.x, -local.z)
		yaw = lerp_angle(yaw, ty, 1.0 - exp(-8.0 * dt))
		walk += hv.length() * dt * 3.0
	vis_q = vis_q.slerp(body.frame.get_rotation_quaternion(), 1.0 - exp(-8.0 * dt))
	_sync()
	var s := sin(walk) * 0.6
	for i in legs.size():
		legs[i].rotation.x = s if (i % 2 == 0) != (i >= 2) else -s
	var pulse := 0.0
	if fuse >= 0.0:
		pulse = 0.5 + 0.5 * sin(age * 30.0)
		scale = Vector3.ONE * (1.0 + pulse * 0.12)
	for m in mats:
		m.emission_enabled = flash > 0.0 or pulse > 0.0
		if flash > 0.0:
			m.emission = Color(1, 0.1, 0.05)
			m.emission_energy_multiplier = flash * 1.5
		elif pulse > 0.0:
			m.emission = Color(1, 1, 1)
			m.emission_energy_multiplier = pulse * 1.2
	sound_t -= dt
	if sound_t <= 0.0:
		sound_t = randf_range(6, 14)
		if dist < 20.0:
			Sfx.play3d(kind, global_position, -4.0)


func _rand_tangent() -> Vector3:
	var a := randf() * TAU
	return (body.frame.x * cos(a) + body.frame.z * sin(a)).normalized()


func _boom() -> void:
	main.explode(body.center(), 3.2, 14.0)
	dead = true
	main.remove_entity(self)


func hit_test(o: Vector3, d: Vector3) -> float:
	var hit = body.aabb().grow(0.1).intersects_ray(o, d)
	if hit == null:
		return -1.0
	return o.distance_to(hit)


func blocks(bb: AABB) -> bool:
	return body.aabb().intersects(bb)


func hurt(dmg: float, dir: Vector3, attacker) -> void:
	if dead:
		return
	hp -= dmg
	flash = 1.0
	if attacker != null:
		var u := body.up()
		var tng := dir - u * dir.dot(u)
		body.vel += tng.normalized() * 6.0 + u * 5.0
		Sfx.play3d("hit", global_position, -2.0)
		panic = 4.0
		ai_t = 0.0
	if hp <= 0.0:
		dead = true
		main.spawn_particles(body.center(), 0, 14, body.up(), Color(0.8, 0.8, 0.8))
		if attacker != null:
			_drops(attacker)
		main.on_mob_killed(self, attacker != null)
		main.remove_entity(self)


func _drops(p) -> void:
	match kind:
		"pig":
			p.add_item(B.RAW_MEAT, randi_range(1, 3))
		"cow":
			p.add_item(B.RAW_MEAT, randi_range(2, 3))
		"sheep":
			p.add_item(wool, randi_range(1, 3))
			p.add_item(B.RAW_MEAT, 1)
		"zombie":
			if randf() < 0.5:
				p.add_item(B.IRON_INGOT if randf() < 0.15 else B.COAL, 1)
		"boomer":
			p.add_item(B.GUNPOWDER, randi_range(1, 2))
	Sfx.play("pop", -6.0)
