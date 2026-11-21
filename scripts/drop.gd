extends Node3D
## A dropped item lying in the world: falls with the planet's gravity, spins and bobs, then gets pulled
## into the player when they walk close. Despawns after 5 minutes.

const VMScript := preload("res://scripts/viewmodel.gd")
const MAGNET := 2.4
const LIFETIME := 300.0

var main
var world
var body: VBody
var id := 0
var n := 1
var dead := false
var age := 0.0
var pickup_delay := 0.4
var spin := 0.0
var vis: Node3D
var vis_q := Quaternion.IDENTITY


func setup(m, w, item_id: int, count: int, pos: Vector3, vel: Vector3, delay: float) -> void:
	main = m
	world = w
	id = item_id
	n = count
	pickup_delay = delay
	body = VBody.new(world, 0.12, 0.25)
	body.set_face(world.face_of_pos(pos))
	body.pos = pos
	body.vel = vel
	vis_q = body.frame.get_rotation_quaternion()
	spin = randf() * TAU
	vis = Node3D.new()
	add_child(vis)
	var copies := 1 if n == 1 else (2 if n < 16 else 3)
	for k in copies:
		var mi := MeshInstance3D.new()
		var cube: bool = B.is_block(id) and B.RENDER[id] != B.R_CROSS and B.RENDER[id] != B.R_TORCH
		if cube:
			mi.mesh = world.make_block_mesh(id, 0.26)
		else:
			mi.mesh = VMScript.voxel_mesh(id, 0.36)
			mi.material_override = VMScript.item_material(false, 1.6 if VMScript.glows(id) else 0.0)
		mi.position = Vector3(k * 0.06, k * 0.05, k * 0.05)
		vis.add_child(mi)
	_sync()


func _sync() -> void:
	vis_q = vis_q.slerp(body.frame.get_rotation_quaternion(), 0.2)
	global_position = body.pos
	global_basis = Basis(vis_q)
	vis.position = Vector3(0, 0.2 + sin(age * 2.5) * 0.05, 0)
	vis.rotation = Vector3(0, spin + age * 1.6, 0)


func tick(dt: float, player) -> void:
	age += dt
	if age > LIFETIME:
		dead = true
		main.remove_entity(self)
		return
	var target: Vector3 = player.body.center()
	var to := target - body.center()
	var d := to.length()
	if age > pickup_delay and not player.dead and d < MAGNET:
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
		body.step(dt)
		body.update_gravity()
		if body.on_ground:
			var u := body.up()
			var vu := body.vel.dot(u)
			body.vel = (body.vel - u * vu) * exp(-8.0 * dt) + u * vu
	_sync()


func hit_test(_o: Vector3, _d: Vector3) -> float:
	return -1.0


func blocks(_bb: AABB) -> bool:
	return false
