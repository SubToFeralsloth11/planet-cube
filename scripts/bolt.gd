extends Node3D
## Magma bolt fired by the Sentinel.

var main
var world
var vel := Vector3.ZERO
var life := 7.0
var dead := false


func setup(m, w, pos: Vector3, v: Vector3) -> void:
	main = m
	world = w
	vel = v
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.15)
	l.omni_range = 5.0
	l.light_energy = 2.0
	add_child(l)
	global_position = pos


func tick(dt: float, player) -> void:
	life -= dt
	global_position += vel * dt
	if randf() < 0.6:
		main.spawn_burst(global_position, Color(1.0, 0.55, 0.15), 1, 0.4)
	var p := global_position
	if life <= 0.0 or world.solid(floori(p.x), floori(p.y), floori(p.z)) or p.distance_to(player.body.center()) < 1.0:
		dead = true
		main.explode(p, 1.7, 7.0, true)
		main.remove_entity(self)


func hit_test(_o: Vector3, _d: Vector3) -> float:
	return -1.0


func blocks(_bb: AABB) -> bool:
	return false
