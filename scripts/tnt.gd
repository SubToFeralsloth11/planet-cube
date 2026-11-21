extends Node3D
## Lit TNT block counting down to an explosion.

var main
var fuse := 3.0
var flash_mi: MeshInstance3D
var dead := false
var t := 0.0


func setup(m, world, pos: Vector3, fuse_time: float) -> void:
	main = m
	fuse = fuse_time
	var mi := MeshInstance3D.new()
	mi.mesh = world.make_block_mesh(B.TNT, 1.0)
	add_child(mi)
	flash_mi = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.02, 1.02, 1.02)
	flash_mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mi.material_override = mat
	add_child(flash_mi)
	global_position = pos
	Sfx.play3d("fuse", pos, 0.0)


func tick(dt: float, _player) -> void:
	fuse -= dt
	t += dt
	flash_mi.visible = fmod(t, 0.4) < 0.2
	scale = Vector3.ONE * (1.0 + maxf(0.0, 0.6 - fuse) * 0.3)
	if fuse <= 0.0:
		dead = true
		main.explode(global_position, 4.2, 20.0)
		main.remove_entity(self)


func hit_test(_o: Vector3, _d: Vector3) -> float:
	return -1.0


func blocks(bb: AABB) -> bool:
	return AABB(global_position - Vector3(0.5, 0.5, 0.5), Vector3.ONE).intersects(bb)
