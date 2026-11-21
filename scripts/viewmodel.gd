extends Node3D
## First-person arm and held item, parented to the player camera and lit by the real world (sun, shade,
## torches). A vertex shader pins it in front of the world's depth so it never clips into walls and
## renders it at a fixed FOV so it doesn't stretch while sprinting - with no extra render pass.
## Items are extruded from their pixel art into 3D voxels.
## Animations: equip, swing, mining loop, eating, walk bob, idle breathing, mouse sway, sprint, landing.

const FOV := 66.0
const SUIT := Color(0.95, 0.55, 0.15)
const GLOVE := Color(0.7, 0.72, 0.77)
const REST := Vector3(0.36, -0.34, -0.58)

## Clip-space override: rescales x/y to the hand FOV and squeezes depth into the 2% nearest the camera
## (Godot uses reversed Z, so 1.0 is the near plane).
const VM_VERTEX := """
uniform float vm_fov = 66.0;
void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	clip.xy *= (1.0 / tan(radians(vm_fov) * 0.5)) / abs(PROJECTION_MATRIX[1][1]);
	clip.z = clip.w * (1.0 - (1.0 - clip.z / clip.w) * 0.02);
	POSITION = clip;
}
"""

const ITEM_SHADER := """shader_type spatial;
render_mode cull_back;
uniform float glow = 0.0;
%s
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.78;
	SPECULAR = 0.3;
	float lum = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
	EMISSION = COLOR.rgb * glow * smoothstep(0.2, 0.55, lum);
}"""

const FABRIC_SHADER := """shader_type spatial;
render_mode cull_back;
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
%s
void fragment() {
	ALBEDO = texture(tex, UV * vec2(6.0, 4.0)).rgb;
	ROUGHNESS = 0.75;
}"""

static var _mats := {}
static var _mesh_cache := {}

var player
var rig: Node3D
var grip: Node3D
var item: MeshInstance3D

var shown_id := -2
var pending_id := -2
var equip := 1.0
var lowering := false
var swing_t := 1.0
var eat := 0.0
var sway := Vector2.ZERO
var look_acc := Vector2.ZERO
var land := 0.0
var land_vel := 0.0
var sprint := 0.0
var hurt := 0.0
var t := 0.0


func setup(p) -> void:
	player = p
	rig = Node3D.new()
	add_child(rig)
	_build_arm()


static func _shader(key: String, code: String) -> Shader:
	if not _mats.has(key):
		var sh := Shader.new()
		sh.code = code
		_mats[key] = sh
	return _mats[key]


func _fabric(base: Color, seed_v: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var k := rng.randf_range(-0.05, 0.05)
			if y % 8 == 0:
				k -= 0.08
			im.set_pixel(x, y, Color(base.r + k, base.g + k, base.b + k))
	return ImageTexture.create_from_image(im)


func _part(size: Vector3, pos: Vector3, col: Color, seed_v: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := ShaderMaterial.new()
	m.shader = _shader("fabric_vm", FABRIC_SHADER % VM_VERTEX)
	m.set_shader_parameter("tex", _fabric(col, seed_v))
	m.set_shader_parameter("vm_fov", FOV)
	mi.material_override = m
	_vm_instance(mi)
	mi.position = pos
	rig.add_child(mi)
	return mi


static func _vm_instance(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0


func _build_arm() -> void:
	# The rig origin is the fist; the sleeve runs back toward the bottom-right corner of the screen.
	_part(Vector3(0.13, 0.13, 0.5), Vector3(0, -0.005, 0.3), SUIT, 1)
	_part(Vector3(0.145, 0.145, 0.05), Vector3(0, -0.005, 0.1), GLOVE.darkened(0.08), 2)
	_part(Vector3(0.135, 0.135, 0.13), Vector3(0, 0, 0.0), GLOVE, 3)
	_part(Vector3(0.05, 0.04, 0.09), Vector3(-0.07, 0.03, -0.015), GLOVE.darkened(0.05), 4)
	grip = Node3D.new()
	grip.position = Vector3(0.0, 0.03, -0.03)
	rig.add_child(grip)
	item = MeshInstance3D.new()
	_vm_instance(item)
	grip.add_child(item)


# ---------------- item meshes ----------------

## Voxel item material; `vm` = first-person variant (fixed FOV, always in front).
static func item_material(vm: bool, glow := 0.0) -> ShaderMaterial:
	var key := "item:%s:%f" % [vm, glow]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("item_vm" if vm else "item", ITEM_SHADER % (VM_VERTEX if vm else ""))
		m.set_shader_parameter("glow", glow)
		if vm:
			m.set_shader_parameter("vm_fov", FOV)
		_mats[key] = m
	return _mats[key]


## First-person copy of the terrain material so held blocks share its texture array and glow.
static func block_material(world) -> ShaderMaterial:
	if not _mats.has("block_vm"):
		var base: Shader = world.mat_solid.shader
		var m: ShaderMaterial = world.mat_solid.duplicate()
		m.shader = _shader("block_vm_shader", base.code.replace("void fragment()", VM_VERTEX + "\nvoid fragment()"))
		m.set_shader_parameter("vm_fov", FOV)
		_mats["block_vm"] = m
	return _mats["block_vm"]


## Extrudes 16x16 pixel art into a 1-pixel-thick voxel slab (size = edge length in metres).
static func voxel_mesh(id: int, size: float) -> ArrayMesh:
	var key := "%d:%f" % [id, size]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var im: Image = T.item_image(id)
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cols := PackedColorArray()
	var ind := PackedInt32Array()
	var px := size / 16.0
	var dirs := [
		[Vector3(0, 0, 1), Vector3.RIGHT, Vector3.UP, 1.0, Vector2i(0, 0)],
		[Vector3(0, 0, -1), Vector3.UP, Vector3.RIGHT, 0.72, Vector2i(0, 0)],
		[Vector3(1, 0, 0), Vector3.UP, Vector3.BACK, 0.82, Vector2i(1, 0)],
		[Vector3(-1, 0, 0), Vector3.BACK, Vector3.UP, 0.82, Vector2i(-1, 0)],
		[Vector3(0, 1, 0), Vector3.BACK, Vector3.RIGHT, 0.92, Vector2i(0, -1)],
		[Vector3(0, -1, 0), Vector3.RIGHT, Vector3.BACK, 0.62, Vector2i(0, 1)],
	]
	var half := Vector3(px * 0.5, px * 0.5, px * 0.5)
	for y in 16:
		for x in 16:
			var c := im.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var lc := c.srgb_to_linear()
			var ctr := Vector3((x - 7.5) * px, (7.5 - y) * px, 0.0)
			for d in dirs:
				var nb: Vector2i = d[4]
				if nb != Vector2i.ZERO:
					var qx: int = x + nb.x
					var qy: int = y + nb.y
					if qx >= 0 and qx < 16 and qy >= 0 and qy < 16 and im.get_pixel(qx, qy).a >= 0.5:
						continue
				var n: Vector3 = d[0]
				var u: Vector3 = d[1]
				var w: Vector3 = d[2]
				var fc := ctr + n * half
				var hu := u * absf(u.dot(half))
				var hw := w * absf(w.dot(half))
				var s := v.size()
				v.append(fc - hu - hw)
				v.append(fc + hu - hw)
				v.append(fc + hu + hw)
				v.append(fc - hu + hw)
				var shade: float = d[3]
				var col := Color(lc.r * shade, lc.g * shade, lc.b * shade)
				for k in 4:
					nn.append(n)
					cols.append(col)
				ind.append_array([s, s + 2, s + 1, s, s + 3, s + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = ind
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_cache[key] = m
	return m


static func is_tool(id: int) -> bool:
	return id >= B.WOOD_PICK and id <= B.DIAMOND_SWORD or id == B.STICK


static func glows(id: int) -> bool:
	return B.is_block(id) and B.LIGHT[id] > 0.0 or id == B.STARCORE


## Places `mi` (child of a grip node) for item `id`. `vm` = first-person hand; otherwise the
## third-person body model (scaled by scale_k).
static func dress(mi: MeshInstance3D, id: int, world, scale_k := 1.0, vm := false) -> void:
	mi.material_override = null
	mi.mesh = null
	mi.position = Vector3.ZERO
	mi.rotation = Vector3.ZERO
	if id <= 0:
		return
	var cube: bool = B.is_block(id) and B.RENDER[id] != B.R_CROSS and B.RENDER[id] != B.R_TORCH
	if cube:
		mi.mesh = world.make_block_mesh(id, 0.17 * scale_k)
		mi.position = Vector3(-0.02, 0.075, -0.06) * scale_k
		mi.rotation = Vector3(0.12, 0.78, 0.0)
		if vm:
			mi.material_override = block_material(world)
		return
	elif is_tool(id):
		var sz := 0.36 * scale_k
		mi.mesh = voxel_mesh(id, sz)
		# Handle pixel (col 2, row 13) sits in the fist; the head points up and forward.
		var basis := Basis.from_euler(Vector3(deg_to_rad(-12), deg_to_rad(118), deg_to_rad(-8)))
		mi.basis = basis
		mi.position = -(basis * Vector3((2.0 - 7.5) * sz / 16.0, (7.5 - 13.0) * sz / 16.0, 0.0))
	else:
		var sz := (0.34 if B.is_block(id) else 0.27) * scale_k
		mi.mesh = voxel_mesh(id, sz)
		mi.rotation = Vector3(deg_to_rad(-8), deg_to_rad(155), deg_to_rad(-6))
		mi.position = Vector3(-0.02, sz * 0.42, -0.04)
	mi.material_override = item_material(vm, 1.6 if glows(id) else 0.0)


# ---------------- animation triggers ----------------

func swing() -> void:
	if swing_t > 0.45:
		swing_t = 0.0


func is_swinging() -> bool:
	return swing_t < 1.0


func land_impact(speed: float) -> void:
	land_vel -= clampf(speed * 0.02, 0.0, 0.3)


func on_hurt() -> void:
	hurt = 1.0


func add_look(rel: Vector2) -> void:
	look_acc += rel


# ---------------- per frame ----------------

func update(dt: float, id: int, moving: float, on_ground: bool, sprinting: bool, eating: bool, phase: float) -> void:
	t += dt
	if id != pending_id:
		pending_id = id
		if shown_id == -2:
			shown_id = id
			dress(item, id, player.world, 1.0, true)
			equip = 1.0
		else:
			lowering = true
	if lowering:
		equip = move_toward(equip, 1.0, dt * 6.0)
		if equip >= 1.0:
			lowering = false
			shown_id = pending_id
			dress(item, shown_id, player.world, 1.0, true)
	else:
		equip = move_toward(equip, 0.0, dt * 3.5)
	swing_t = minf(1.0, swing_t + dt / 0.34)
	eat = move_toward(eat, 1.0 if eating else 0.0, dt * 5.0)
	sprint = lerpf(sprint, 1.0 if sprinting else 0.0, 1.0 - exp(-5.0 * dt))
	hurt = maxf(0.0, hurt - dt * 3.0)
	# Mouse sway: the arm trails slightly behind the look speed, eased so it never snaps.
	var look_speed := look_acc / maxf(dt, 0.001)
	look_acc = Vector2.ZERO
	var sway_target := (look_speed * 0.00003).clamp(Vector2(-0.05, -0.05), Vector2(0.05, 0.05))
	sway = sway.lerp(sway_target, 1.0 - exp(-6.0 * dt))
	# Soft landing spring.
	land_vel += -land * 60.0 * dt
	land_vel *= exp(-9.0 * dt)
	land += land_vel * dt * 4.0
	var amt := clampf(moving / 4.4, 0.0, 1.4) * (1.0 if on_ground else 0.25)
	var e := ease(equip, 0.6)
	var s := swing_t
	var g := sin(sqrt(s) * PI) if s < 1.0 else 0.0
	var f := sin(s * s * PI) if s < 1.0 else 0.0
	var pos := REST
	var rot := Vector3(deg_to_rad(10), deg_to_rad(20), deg_to_rad(2))
	if shown_id <= 0:
		pos = Vector3(0.33, -0.29, -0.46)
		rot = Vector3(deg_to_rad(14), deg_to_rad(10), deg_to_rad(-6))
	# walk bob (figure eight) and idle breathing
	pos += Vector3(sin(phase) * 0.008 * amt, -absf(cos(phase)) * 0.011 * amt + sin(t * 1.7) * 0.003, 0)
	rot.z += sin(phase) * 0.015 * amt
	# mouse sway: the arm lags behind where you look
	rot.y += sway.x * 0.8
	rot.x += sway.y * 0.6
	pos += Vector3(-sway.x * 0.15, sway.y * 0.12, 0)
	# sprint: tilt the arm down and in
	pos += Vector3(0.03, -0.05, 0.03) * sprint
	rot += Vector3(-0.15, 0.2, 0.08) * sprint
	# landing dip
	pos.y += land * 0.25
	# swing
	pos += Vector3(-0.13 * g, 0.07 * sin(sqrt(s) * TAU) * float(s < 1.0), -0.09 * f)
	if shown_id <= 0:
		# Punch: thrust the fist straight toward the crosshair, knuckles first.
		pos += Vector3(-0.14 * g, 0.07 * g, -0.2 * g)
		rot += Vector3(0.2 * g, 0.3 * g, -0.1 * g)
	else:
		rot += Vector3(-0.6 * g, 0.3 * f, 0.35 * g)
	# eating: bring it to the mouth and chew
	pos = pos.lerp(Vector3(0.12, -0.19 + absf(sin(t * 9.0)) * 0.012, -0.36), eat)
	rot = rot.lerp(Vector3(0.2, 0.45, -0.1), eat)
	# equip / hurt
	pos.y -= 0.42 * e
	rot.x -= 0.3 * e
	pos.y -= hurt * 0.04
	# Rotate about the shoulder (back end of the sleeve), not the fist, so the part of the arm nearest
	# the camera stays put and only the hand end moves - like a real arm.
	var shoulder := Vector3(0, 0, 0.55)
	var rest_e := Vector3(14, 10, -6) if shown_id <= 0 else Vector3(10, 20, 2)
	var rest_basis := Basis.from_euler(rest_e * (PI / 180.0))
	var b := Basis.from_euler(rot)
	rig.basis = b
	rig.position = pos + rest_basis * shoulder - b * shoulder
