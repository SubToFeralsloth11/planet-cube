extends Node3D
## A dropped item lying in the world: falls with the planet's gravity, bounces, rolls to a stop, then
## gets pulled into the player when they walk close. Despawns after 5 minutes.
## `debris` mode: a chunk of block thrown by an explosion - tumbles, can't be picked up, fades out.

const VMScript := preload("res://scripts/viewmodel.gd")
const MAGNET := 2.4
const LIFETIME := 300.0
const RADIUS := 0.14

var main
var world
var body: VBody
var id := 0
var n := 1
var dead := false
var debris := false
var age := 0.0
var life := LIFETIME
var pickup_delay := 0.4
var spin := 0.0
var vis: Node3D
var vis_q := Quaternion.IDENTITY
var roll := Quaternion.IDENTITY
var tumble := Vector3.ZERO
var settle := 0.0


func setup(m, w, item_id: int, count: int, pos: Vector3, vel: Vector3, delay: float, is_debris := false) -> void:
	main = m
	world = w
	id = item_id
	n = count
	pickup_delay = delay
	debris = is_debris
	body = VBody.new(world, 0.12, 0.25)
	body.set_face(world.face_of_pos(pos))
	body.pos = pos
	body.vel = vel
	vis_q = body.frame.get_rotation_quaternion()
	spin = randf() * TAU
	tumble = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (14.0 if debris else 6.0)
	if debris:
		life = randf_range(1.4, 2.4)
	vis = Node3D.new()
	add_child(vis)
	var copies := 1 if (n == 1 or debris) else (2 if n < 16 else 3)
	for k in copies:
		var mi := MeshInstance3D.new()
		var cube: bool = B.is_block(id) and B.RENDER[id] != B.R_CROSS and B.RENDER[id] != B.R_TORCH
		if cube:
			mi.mesh = world.make_block_mesh(id, randf_range(0.3, 0.45) if debris else 0.26)
		else:
			mi.mesh = VMScript.voxel_mesh(id, 0.36)
			mi.material_override = VMScript.item_material(false, 1.6 if VMScript.glows(id) else 0.0)
		mi.position = Vector3(k * 0.06, k * 0.05, k * 0.05)
		vis.add_child(mi)
	_sync(0.0)


func _sync(dt: float) -> void:
	vis_q = vis_q.slerp(body.frame.get_rotation_quaternion(), 0.2)
	global_position = body.pos
	global_basis = Basis(vis_q)
	var u := Vector3.UP
	if debris or settle < 1.0:
		# Airborne or rolling: tumble freely; the spin bleeds off as it settles.
		var w := tumble * (1.0 - settle)
		if w.length() > 0.001:
			roll = (Quaternion(w.normalized(), w.length() * dt) * roll).normalized()
	else:
		roll = roll.slerp(Quaternion.IDENTITY, 1.0 - exp(-6.0 * dt))
	vis.position = u * (0.16 + (sin(age * 2.5) * 0.05 + 0.05) * settle)
	vis.basis = Basis(Quaternion(u, (spin + age * 1.6) * settle)) * Basis(roll)
	if debris:
		var k := clampf((life - age) / 0.4, 0.0, 1.0)
		vis.scale = Vector3.ONE * k


func tick(dt: float, player) -> void:
	age += dt
	if age > life:
		dead = true
		main.remove_entity(self)
		return
	var target: Vector3 = player.body.center()
	var to := target - body.center()
	var d := to.length()
	if not debris and age > pickup_delay and not player.dead and d < MAGNET and _has_room(player):
		# Pulled in: fly straight at the player, faster the closer it gets.
		body.pos += to.normalized() * minf(d, dt * (4.0 + (MAGNET - d) * 6.0))
		if d < 0.7:
			var left: int = player.add_item(id, n)
			if left < n:
				Sfx.play("pop", -8.0, randf_range(1.0, 1.4))
			n = left
			if n <= 0:
				dead = true
				main.remove_entity(self)
				return
	else:
		_physics(dt)
	_sync(dt)


## Falls, bounces off the ground a couple of times, then rolls with friction until it stops.
func _physics(dt: float) -> void:
	var was_air := not body.on_ground
	body.step(dt)
	body.update_gravity()
	var u := body.up()
	var vu := body.vel.dot(u)
	var hv := body.vel - u * vu
	if body.on_ground:
		if was_air and body.land_speed > 2.0:
			# Bounce, losing most of the energy; tumble harder on a hard hit.
			vu = body.land_speed * 0.32
			tumble += hv.cross(u).normalized() * body.land_speed * 1.5 if hv.length() > 0.1 else Vector3.ZERO
		hv *= exp(-3.0 * dt)
		if hv.length() > 3.0:
			hv = hv.normalized() * 3.0
		if hv.length() > 0.05:
			# Rolling: spin about the axis perpendicular to travel, matched to ground speed.
			tumble = tumble.lerp(u.cross(hv).normalized() * hv.length() / RADIUS * -1.0, 1.0 - exp(-10.0 * dt))
		elif vu < 0.5:
			hv = Vector3.ZERO
			settle = minf(1.0, settle + dt * 2.0)
	elif body.hit_wall:
		hv *= -0.4
	body.vel = hv + u * vu


func hit_test(_o: Vector3, _d: Vector3) -> float:
	return -1.0


func blocks(_bb: AABB) -> bool:
	return false


## True if the player's main inventory (slots 0-35) can take at least one of this item, so a full
## inventory doesn't drag drops along behind you.
func _has_room(player) -> bool:
	var mx := B.stack_max(id)
	for i in 36:
		var s = player.inv[i]
		if s == null or (s["id"] == id and s["n"] < mx):
			return true
	return false
