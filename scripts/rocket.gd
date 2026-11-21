extends Node3D
## The escape rocket, standing on its launch pad.

var main
var face := 2
var base := Vector3.ZERO
var state := "idle"
var flames: CPUParticles3D
var smoke: CPUParticles3D
var beacon: OmniLight3D
var speed := 0.0
var t := 0.0
var dead := false


func setup(m, f: int, pos: Vector3) -> void:
	main = m
	face = f
	base = pos
	var vb := VBody.new(null)
	vb.set_face(f)
	global_basis = vb.frame
	global_position = pos
	_build()


func _mat(col: Color, emit := 0.0, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = 0.35
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m


func _add(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func _build() -> void:
	var white := _mat(Color(0.93, 0.94, 0.96), 0.0, 0.3)
	var red := _mat(Color(0.85, 0.12, 0.12), 0.0, 0.2)
	var dark := _mat(Color(0.2, 0.2, 0.23), 0.0, 0.7)
	var pad := BoxMesh.new()
	pad.size = Vector3(3.4, 0.25, 3.4)
	_add(pad, _mat(Color(0.35, 0.36, 0.4), 0.0, 0.5), Vector3(0, 0.125, 0))
	for k in 4:
		var stripe := BoxMesh.new()
		stripe.size = Vector3(3.42, 0.08, 0.3)
		_add(stripe, _mat(Color(1.0, 0.8, 0.1)), Vector3(0, 0.22, 0), Vector3(0, k * PI / 4.0, 0))
	var noz := CylinderMesh.new()
	noz.top_radius = 0.42
	noz.bottom_radius = 0.68
	noz.height = 0.6
	_add(noz, dark, Vector3(0, 0.55, 0))
	var bodym := CylinderMesh.new()
	bodym.top_radius = 0.82
	bodym.bottom_radius = 0.82
	bodym.height = 4.2
	_add(bodym, white, Vector3(0, 2.95, 0))
	for y in [1.4, 4.4]:
		var band := CylinderMesh.new()
		band.top_radius = 0.84
		band.bottom_radius = 0.84
		band.height = 0.22
		_add(band, red, Vector3(0, y, 0))
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.82
	nose.height = 1.7
	_add(nose, red, Vector3(0, 5.9, 0))
	var win := SphereMesh.new()
	win.radius = 0.3
	win.height = 0.6
	_add(win, _mat(Color(0.3, 0.75, 1.0), 1.5), Vector3(0, 3.6, -0.72)).scale = Vector3(1, 1, 0.5)
	for k in 4:
		var fin := BoxMesh.new()
		fin.size = Vector3(0.12, 1.5, 0.9)
		var a := k * PI / 2.0
		var fm := _add(fin, red, Vector3(sin(a) * 0.95, 1.4, cos(a) * 0.95), Vector3(0, a + PI / 2.0, 0))
		fm.rotation = Vector3(0, a, 0)
		fm.position = Vector3(sin(a) * 1.0, 1.35, cos(a) * 1.0)
	flames = CPUParticles3D.new()
	flames.emitting = false
	flames.amount = 160
	flames.lifetime = 0.7
	flames.position = Vector3(0, 0.25, 0)
	flames.direction = Vector3(0, -1, 0)
	flames.spread = 14.0
	flames.initial_velocity_min = 10.0
	flames.initial_velocity_max = 16.0
	flames.gravity = Vector3.ZERO
	flames.scale_amount_min = 0.5
	flames.scale_amount_max = 1.1
	var fm2 := SphereMesh.new()
	fm2.radius = 0.35
	fm2.height = 0.7
	fm2.radial_segments = 8
	fm2.rings = 4
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.vertex_color_use_as_albedo = true
	fmat.albedo_color = Color(1, 1, 1)
	fm2.material = fmat
	flames.mesh = fm2
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.6))
	grad.set_color(1, Color(1.0, 0.25, 0.05))
	flames.color_ramp = grad
	flames.local_coords = false
	add_child(flames)
	smoke = CPUParticles3D.new()
	smoke.emitting = false
	smoke.amount = 60
	smoke.lifetime = 2.5
	smoke.position = Vector3(0, 0.3, 0)
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 80.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 3.0
	smoke.gravity = Vector3.ZERO
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.2
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.85, 0.85, 0.85, 0.5)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = smat
	smoke.mesh = sm
	smoke.local_coords = false
	add_child(smoke)
	beacon = OmniLight3D.new()
	beacon.position = Vector3(0, 1.0, 0)
	beacon.omni_range = 7.0
	beacon.light_energy = 0.0
	beacon.light_color = Color(0.4, 0.8, 1.0)
	add_child(beacon)


func tick(dt: float, _player) -> void:
	t += dt
	if state == "armed":
		beacon.light_color = Color(1.0, 0.3, 0.2)
		beacon.light_energy = 1.5 + sin(t * 6.0)
	elif state == "ready":
		beacon.light_color = Color(0.4, 0.9, 1.0)
		beacon.light_energy = 2.0 + sin(t * 3.0)
	elif state == "launching":
		speed += dt * (4.0 + speed * 0.9)
		global_position += global_basis.y * speed * dt


func ignite() -> void:
	state = "launching"
	flames.emitting = true
	smoke.emitting = true


func world_aabb() -> AABB:
	var local := AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 6.8, 2.0))
	return global_transform * local


func hit_test(o: Vector3, d: Vector3) -> float:
	if state == "launching":
		return -1.0
	var hit = world_aabb().intersects_ray(o, d)
	if hit == null:
		return -1.0
	return o.distance_to(hit)


func blocks(bb: AABB) -> bool:
	return world_aabb().intersects(bb)


func interact(_p) -> void:
	main.rocket_interact()


func hurt(_d: float, _dir: Vector3, _a) -> void:
	pass
