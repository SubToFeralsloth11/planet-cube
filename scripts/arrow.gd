extends Node3D
## Arrow fired from the player's bow. Falls toward the planet core and hurts the first creature it hits.

var main
var world
var vel := Vector3.ZERO
var dmg := 4.0
var life := 6.0
var dead := false
var shooter


func setup(m, w, pos: Vector3, v: Vector3, damage: float, by) -> void:
	main = m
	world = w
	vel = v
	dmg = damage
	shooter = by
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, 0.7)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.38, 0.2)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	global_position = pos


func tick(dt: float, _player) -> void:
	life -= dt
	var p := global_position
	# Gravity points down onto the face the arrow is over.
	var c := p - VBody.CENTER
	var a := 0
	for k in 3:
		if absf(c[k]) > absf(c[a]):
			a = k
	var down := Vector3.ZERO
	down[a] = -signf(c[a])
	vel += down * 18.0 * dt
	var step := vel * dt
	var hit = main.pick_entity(p, step.normalized(), step.length() + 0.3)
	if hit != null:
		var hp0 = hit.get("hp")
		hit.hurt(dmg, vel.normalized(), shooter)
		if hp0 != null and is_instance_valid(hit):
			main.damage_number(hit.global_position + Vector3.UP, dmg, false)
		_die()
		return
	p += step
	if life <= 0.0 or world.solid(floori(p.x), floori(p.y), floori(p.z)):
		_die()
		return
	global_position = p
	if vel.length() > 0.5 and absf(down.dot(vel.normalized())) < 0.99:
		look_at(p + vel, -down)


func _die() -> void:
	dead = true
	main.remove_entity(self)


func hit_test(_o: Vector3, _d: Vector3) -> float:
	return -1.0


func blocks(_bb: AABB) -> bool:
	return false
