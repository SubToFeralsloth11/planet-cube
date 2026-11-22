extends Node3D
## Voxel planet: storage, generation, meshing, lighting helpers and raycasts.

signal tnt_lit(pos: Vector3)
## Water met lava and hardened a cell into cobble or obsidian.
signal liquid_fused(pos: Vector3)
## A torch lost the block it hung on and popped off (main turns it into an item drop).
signal torch_popped(pos: Vector3)

const W := 128
const WW := 16384
const C := 64
const R := 34
const CS := 16
const NC := 8
const SEA := R + 2
const BASE := R + 3
const CORE := 12
const LAVA_TOP := 17
const CENTER := Vector3(64, 64, 64)

const MEADOW := 0
const FOREST := 1
const DESERT := 2
const TUNDRA := 3
const HIGHLANDS := 4
const ASHLANDS := 5
const FACE_BIOME := [FOREST, DESERT, MEADOW, ASHLANDS, TUNDRA, HIGHLANDS]
const BIOME_NAMES := ["Meadow", "Forest", "Desert", "Tundra", "Highlands", "Ashlands"]
const UPS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
const STRIDE := [1, 128, 16384]
const NOFF := [1, -1, 128, -128, 16384, -16384]
const AO_LEVELS := [0.42, 0.62, 0.8, 1.0]

var blocks := PackedByteArray()
var hmap := PackedByteArray()
var tops := PackedByteArray()
var edits := {}
var world_seed := 0
var chunk_nodes := {}
var dirty := {}
var light_nodes := {}
var mat_solid: ShaderMaterial
var mat_water: ShaderMaterial
var light_anchor := Vector3.ZERO
## Generated landmarks: [{name, sub, pos: Vector3 (world), radius}]. Rebuilt every generate().
var structures: Array = []
var _gen_lights: Array[int] = []
## Chest contents: voxel index -> Array of 27 slots (null or {"id", "n"}). Generated loot + player edits.
var chests := {}
## Furnace state: voxel index -> {"in", "fuel", "out" (slots), "burn", "burn_max", "prog" (seconds)}.
var furnaces := {}
## Wall-mounted torches: voxel index -> Vector3i pointing from the torch into the wall it hangs on.
## Torches not listed stand on the floor.
var torch_wall := {}
## Flowing liquid level per voxel index (1..7, falling = 7); liquid cells absent here are sources.
var flow := {}
var _wq := {}
var _lq := {}
var _wt := 0.0
var _lt := 0.0
## True while the Ash Lands dimension is loaded: every face is Ashlands and ore is far richer.
var ash := false
## Growing wheat: voxel index -> true. Rebuilt from blocks after load.
var crops := {}
var _crop_t := 0.0


func biome(f: int) -> int:
	return ASHLANDS if ash else FACE_BIOME[f]


const WATER_STEP := 0.25
const LAVA_STEP := 1.0

const CHEST_SLOTS := 27
## Loot rolls per structure: [item, min, max, chance].
var loot_tables := {
	"village": [[B.APPLE, 1, 4, 0.7], [B.RAW_MEAT, 1, 3, 0.5], [B.COAL, 2, 8, 0.6], [B.TORCH, 2, 8, 0.6], [B.STICK, 2, 6, 0.5],
		[B.IRON_INGOT, 1, 3, 0.35], [B.WOOL_WHITE, 1, 4, 0.4], [B.STONE_PICK, 1, 1, 0.25], [B.STONE_SWORD, 1, 1, 0.2], [B.COOKED_MEAT, 1, 3, 0.3]],
	"ruins": [[B.IRON_INGOT, 2, 6, 0.8], [B.GOLD_INGOT, 1, 5, 0.6], [B.DIAMOND, 1, 2, 0.45], [B.GUNPOWDER, 1, 4, 0.5], [B.COAL, 3, 10, 0.6],
		[B.IRON_PICK, 1, 1, 0.3], [B.IRON_SWORD, 1, 1, 0.3], [B.TORCH, 4, 12, 0.5], [B.COOKED_MEAT, 2, 4, 0.5], [B.STARCORE, 1, 1, 0.08]],
	"pyramid": [[B.GOLD_INGOT, 3, 8, 0.9], [B.DIAMOND, 1, 4, 0.7], [B.TNT, 1, 3, 0.5], [B.GUNPOWDER, 2, 6, 0.6], [B.APPLE, 2, 5, 0.5],
		[B.DIAMOND_SWORD, 1, 1, 0.15], [B.IRON_INGOT, 2, 6, 0.6], [B.LAMP, 1, 4, 0.4]],
}

var _fc := []
var _fao := []
var _sv := PackedVector3Array()
var _sn := PackedVector3Array()
var _suv := PackedVector2Array()
var _suv2 := PackedVector2Array()
var _sc := PackedColorArray()
var _si := PackedInt32Array()
var _wv := PackedVector3Array()
var _wn := PackedVector3Array()
var _wuv := PackedVector2Array()
var _wuv2 := PackedVector2Array()
var _wc := PackedColorArray()
var _wi := PackedInt32Array()
var _light_timer := 0.0


func _ready() -> void:
	mat_solid = ShaderMaterial.new()
	mat_solid.shader = load("res://shaders/block.gdshader")
	mat_solid.set_shader_parameter("tex", T.array_tex)
	mat_water = ShaderMaterial.new()
	mat_water.shader = load("res://shaders/water.gdshader")
	mat_water.set_shader_parameter("tex", T.array_tex)
	for f in 6:
		var a := f >> 1
		var pos := (f & 1) == 0
		var b := (a + 1) % 3
		var c := (a + 2) % 3
		var corners := []
		var aos := []
		for cc in [[0, 0], [1, 0], [1, 1], [0, 1]]:
			var v := Vector3.ZERO
			v[a] = 1.0 if pos else 0.0
			v[b] = cc[0]
			v[c] = cc[1]
			corners.append(v)
			var s1: int = (1 if cc[0] == 1 else -1) * STRIDE[b]
			var s2: int = (1 if cc[1] == 1 else -1) * STRIDE[c]
			aos.append([s1, s2, s1 + s2])
		var nrm: Vector3 = UPS[f]
		var cr: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0])
		if cr.dot(nrm) > 0.0:
			corners = [corners[0], corners[3], corners[2], corners[1]]
			aos = [aos[0], aos[3], aos[2], aos[1]]
		_fc.append(corners)
		_fao.append(aos)


static func layer(i: int) -> int:
	return i - C if i >= C else C - 1 - i


static func idx_of(x: int, y: int, z: int) -> int:
	return x + (y << 7) + (z << 14)


static func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 1 and y >= 1 and z >= 1 and x < W - 1 and y < W - 1 and z < W - 1


static func face_of_pos(p: Vector3) -> int:
	var q := p - CENTER
	var ax := absf(q.x)
	var ay := absf(q.y)
	var az := absf(q.z)
	if ax >= ay and ax >= az:
		return 0 if q.x >= 0 else 1
	if ay >= az:
		return 2 if q.y >= 0 else 3
	return 4 if q.z >= 0 else 5


static func _lmin(a: int, u: int, v: int) -> int:
	var ua := 1 if a == 0 else 0
	var va := 1 if a == 2 else 2
	var lu := layer(u) + (0 if a < ua else 1)
	var lv := layer(v) + (0 if a < va else 1)
	return maxi(lu, lv)


static func fidx(f: int, u: int, v: int, l: int) -> int:
	var a := f >> 1
	var ia := C + l if (f & 1) == 0 else C - 1 - l
	if a == 0:
		return ia + (u << 7) + (v << 14)
	elif a == 1:
		return u + (ia << 7) + (v << 14)
	return u + (v << 7) + (ia << 14)


static func fpos(f: int, u: int, v: int, l: int) -> Vector3i:
	var i := fidx(f, u, v, l)
	return Vector3i(i & 127, (i >> 7) & 127, i >> 14)


## Returns [face, u, v, layer] for a voxel.
static func voxel_face(x: int, y: int, z: int) -> Array:
	var qx := absi(2 * x + 1 - 2 * C)
	var qy := absi(2 * y + 1 - 2 * C)
	var qz := absi(2 * z + 1 - 2 * C)
	if qx >= qy and qx >= qz:
		return [0 if x >= C else 1, y, z, (qx - 1) >> 1]
	if qy >= qz:
		return [2 if y >= C else 3, x, z, (qy - 1) >> 1]
	return [4 if z >= C else 5, x, y, (qz - 1) >> 1]


func get_b(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= W or y >= W or z >= W:
		return 0
	return blocks[x + (y << 7) + (z << 14)]


func block_at(p: Vector3) -> int:
	return get_b(floori(p.x), floori(p.y), floori(p.z))


func solid(x: int, y: int, z: int) -> bool:
	if x < 0 or y < 0 or z < 0 or x >= W or y >= W or z >= W:
		return false
	return B.SOLID[blocks[x + (y << 7) + (z << 14)]] == 1


func sky_vis(i: int) -> float:
	var x := i & 127
	var y := (i >> 7) & 127
	var z := i >> 14
	var qx := absi(2 * x + 1 - 2 * C)
	var qy := absi(2 * y + 1 - 2 * C)
	var qz := absi(2 * z + 1 - 2 * C)
	var ci: int
	var l: int
	if qx >= qy and qx >= qz:
		ci = ((0 if x >= C else 1) * W + y) * W + z
		l = (qx - 1) >> 1
	elif qy >= qz:
		ci = ((2 if y >= C else 3) * W + x) * W + z
		l = (qy - 1) >> 1
	else:
		ci = ((4 if z >= C else 5) * W + x) * W + y
		l = (qz - 1) >> 1
	var t := tops[ci]
	if l >= t:
		return 1.0
	return maxf(0.0, 1.0 - float(t - l) * 0.16)


func sky_vis_at(p: Vector3) -> float:
	var x := floori(p.x)
	var y := floori(p.y)
	var z := floori(p.z)
	if not in_bounds(x, y, z):
		return 1.0
	return sky_vis(idx_of(x, y, z))


# ---------------- generation ----------------

func _vol(n: FastNoiseLite) -> PackedByteArray:
	var imgs := n.get_image_3d(W, W, W, false, false)
	var out := PackedByteArray()
	for im in imgs:
		out.append_array(im.get_data())
	return out


func generate(seed_val: int, progress: Callable) -> void:
	world_seed = seed_val
	chests.clear()
	furnaces.clear()
	torch_wall.clear()
	flow.clear()
	_wq.clear()
	_lq.clear()
	blocks.resize(W * WW)
	blocks.fill(0)
	hmap.resize(6 * WW)
	tops.resize(6 * WW)
	progress.call(0.02, "Shaping the six faces...")
	await get_tree().process_frame
	_gen_heights()
	progress.call(0.06, "Carving caves...")
	await get_tree().process_frame
	var cn1 := FastNoiseLite.new()
	cn1.seed = world_seed + 11
	cn1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cn1.fractal_type = FastNoiseLite.FRACTAL_NONE
	cn1.frequency = 0.045
	var cn2 := cn1.duplicate()
	cn2.seed = world_seed + 23
	var on := cn1.duplicate()
	on.seed = world_seed + 37
	on.frequency = 0.17
	var cave1 := _vol(cn1)
	var cave2 := _vol(cn2)
	var ore := _vol(on)
	progress.call(0.14, "Filling the planet with stone and ore...")
	await get_tree().process_frame
	for f in 6:
		_gen_face(f, cave1, cave2, ore)
		progress.call(0.14 + 0.05 * (f + 1), "Filling the planet with stone and ore...")
		await get_tree().process_frame
	_gen_core(ore)
	progress.call(0.46, "Growing forests...")
	await get_tree().process_frame
	_decorate()
	progress.call(0.48, "Raising villages and ruins...")
	await get_tree().process_frame
	if not ash:
		_structures()
	else:
		structures.clear()
		_gen_lights.clear()


func apply_edits() -> void:
	crops.clear()
	for k in edits:
		blocks[k] = edits[k]
		if edits[k] >= B.WHEAT_0 and edits[k] < B.WHEAT_3:
			crops[k] = true


## Advances wheat: every second each young crop has a chance to grow one stage.
func grow_crops(dt: float) -> void:
	_crop_t += dt
	if _crop_t < 1.0:
		return
	_crop_t -= 1.0
	for i in crops.keys():
		if randf() < 0.08:
			var b := blocks[i] + 1
			set_block(i & 127, (i >> 7) & 127, i >> 14, b)


## Flowing cells for the save: voxel index -> Vector2i(liquid id, level).
func save_flow() -> Dictionary:
	var out := {}
	for k in flow:
		out[k] = Vector2i(blocks[k], flow[k])
	return out


## Restores `save_flow()` output after apply_edits() and wakes saved liquids so unfinished flows resume.
func load_flow(d: Dictionary) -> void:
	for k in d:
		var v: Vector2i = d[k]
		blocks[k] = v.x
		flow[k] = v.y
		_wake_one(k)
	for k in edits:
		_wake_one(k)


func finish_build(progress: Callable) -> void:
	progress.call(0.5, "Letting the sun in...")
	await get_tree().process_frame
	for f in 6:
		for u in W:
			for v in W:
				tops[(f * W + u) * W + v] = _compute_top(f, u, v)
	progress.call(0.56, "Building chunks...")
	await get_tree().process_frame
	for c in chunk_nodes.values():
		for n in c:
			if n:
				n.queue_free()
	chunk_nodes.clear()
	dirty.clear()
	var total := NC * NC * NC
	var t0 := Time.get_ticks_msec()
	for ci in total:
		_build_chunk(ci)
		if Time.get_ticks_msec() - t0 > 60:
			t0 = Time.get_ticks_msec()
			progress.call(0.56 + 0.42 * float(ci) / total, "Building chunks...")
			await get_tree().process_frame
	for l in light_nodes.values():
		l.queue_free()
	light_nodes.clear()
	for i in _gen_lights:
		if B.LIGHT[blocks[i]] > 0.0 and not edits.has(i):
			_add_light(i, blocks[i])
	for k in edits:
		if B.LIGHT[edits[k]] > 0.0:
			_add_light(k, edits[k])
	var core_light := OmniLight3D.new()
	core_light.light_color = Color(1.0, 0.4, 1.0)
	core_light.omni_range = 10.0
	core_light.light_energy = 2.5
	core_light.position = CENTER
	add_child(core_light)
	light_nodes[-1] = core_light
	progress.call(1.0, "Ready!")


func _gen_heights() -> void:
	var hn := FastNoiseLite.new()
	hn.seed = world_seed
	hn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hn.fractal_type = FastNoiseLite.FRACTAL_FBM
	hn.fractal_octaves = 4
	hn.frequency = 0.022
	for f in 6:
		hn.offset = Vector3(f * 517.0, f * 291.0, 0)
		var data := hn.get_image(W, W, false, false, false).get_data()
		var bio: int = biome(f)
		for u in W:
			var du := absf(u - C + 0.5)
			for v in W:
				var dv := absf(v - C + 0.5)
				var n := data[v * W + u] / 255.0
				var taper := clampf((R - maxf(du, dv)) / 9.0, 0.0, 1.0)
				var h := 0.0
				match bio:
					MEADOW:
						h = (n - 0.47) * 24.0
					FOREST:
						h = (n - 0.45) * 26.0
					DESERT:
						h = (n - 0.33) * 10.0 + sin(u * 0.32 + n * 7.0) * 1.6
					TUNDRA:
						h = (n - 0.48) * 22.0
					HIGHLANDS:
						h = pow(n, 1.6) * 36.0 - 4.0
					ASHLANDS:
						h = (n - 0.42) * 22.0
				hmap[(f * W + u) * W + v] = clampi(BASE + int(round(h * taper)), R - 2, C - 10)


func _gen_face(f: int, cave1: PackedByteArray, cave2: PackedByteArray, ore: PackedByteArray) -> void:
	var a := f >> 1
	var pos := (f & 1) == 0
	var ua := 1 if a == 0 else 0
	var va := 1 if a == 2 else 2
	var sa: int = STRIDE[a]
	var su: int = STRIDE[ua]
	var sv: int = STRIDE[va]
	var bio: int = biome(f)
	var bl := blocks
	var seedmix := world_seed * 19349663
	for u in W:
		for v in W:
			var hh: int = hmap[(f * W + u) * W + v]
			var lmin := _lmin(a, u, v)
			var lstart := maxi(lmin, CORE)
			var top_b := B.GRASS
			var sub_b := B.DIRT
			var sub_d := 4
			var deep_b := B.STONE
			var deep_d := 4
			var wet := hh <= SEA
			match bio:
				DESERT:
					top_b = B.SAND
					sub_b = B.SAND
					deep_b = B.SANDSTONE
					deep_d = 9
				TUNDRA:
					top_b = B.SNOW
				ASHLANDS:
					top_b = B.ASH
					sub_b = B.ASH
					sub_d = 2
					deep_b = B.BASALT
					deep_d = 10
				HIGHLANDS:
					if hh >= BASE + 13:
						top_b = B.SNOW
						sub_b = B.STONE
					elif hh >= BASE + 8:
						top_b = B.STONE
						sub_b = B.STONE
			if wet:
				if bio == ASHLANDS:
					top_b = B.BASALT
					sub_b = B.BASALT
				elif bio == TUNDRA:
					top_b = B.GRAVEL
					sub_b = B.DIRT
				else:
					top_b = B.SAND
					sub_b = B.SAND
					sub_d = 3
			var base_idx := u * su + v * sv
			for l in range(lstart, hh):
				var ia := C + l if pos else C - 1 - l
				var i := ia * sa + base_idx
				var depth := hh - 1 - l
				var b: int
				if depth == 0:
					b = top_b
				elif depth < sub_d:
					b = sub_b
				elif depth < deep_d:
					b = deep_b
				else:
					b = B.STONE
				var c1 := int(cave1[i]) - 128
				var c2 := int(cave2[i]) - 128
				if (c1 * c1 + c2 * c2 < 230 and (depth > 0 or not wet)) or (c1 > 92 and depth > 6):
					if l < LAVA_TOP:
						bl[i] = B.LAVA
					continue
				if b == B.STONE or (b == B.BASALT and depth > 4) or (b == B.SANDSTONE and depth > 5):
					var o := int(ore[i])
					var hs := ((i * 73856093) ^ seedmix) & 1023
					# Veins only where the ore noise peaks; rarer ores take a small slice of each band.
					# The Ash Lands have far more veins and richer bands.
					if o > (180 if ash else 207):
						var hr := hs if not ash else mini(1023, hs + 250)
						if l >= 27:
							b = B.COAL_ORE if hr < 760 else B.IRON_ORE
						elif l >= 20:
							b = B.IRON_ORE if hr < 520 else (B.COAL_ORE if hr < 820 else B.GOLD_ORE)
						else:
							b = B.IRON_ORE if hr < 520 else (B.GOLD_ORE if hr < 860 else B.DIAMOND_ORE)
						if ash and hs > 880:
							b = B.EMBERITE_ORE
						elif bio == ASHLANDS and hs > 990 and l < 30:
							b = B.DIAMOND_ORE
						elif bio == DESERT and hs > 975 and l < 32:
							b = B.GOLD_ORE
					elif o < 34 and depth > 5:
						b = B.GRAVEL
					elif bio == ASHLANDS and o < 52 and depth > 3:
						b = B.OBSIDIAN
				elif depth == 0 and bio == ASHLANDS and not wet:
					if (((i * 2654435761) ^ seedmix) & 1023) < 30:
						b = B.MAGMA
				bl[i] = b
			if wet:
				for l in range(maxi(hh, lmin), SEA):
					var ia := C + l if pos else C - 1 - l
					var i := ia * sa + base_idx
					var wb := B.WATER
					if bio == ASHLANDS:
						wb = B.LAVA
					elif bio == TUNDRA and l == SEA - 1:
						wb = B.ICE
					bl[i] = wb


func _gen_core(ore: PackedByteArray) -> void:
	var bl := blocks
	for z in range(C - CORE, C + CORE):
		for y in range(C - CORE, C + CORE):
			for x in range(C - CORE, C + CORE):
				var l := maxi(maxi(layer(x), layer(y)), layer(z))
				var i := x + (y << 7) + (z << 14)
				if l == 0:
					bl[i] = B.STARCORE_ORE
				elif l <= 4:
					bl[i] = B.AIR
				elif ore[i] > 178 or (l == 5 and ((i * 2654435761) & 15) == 0):
					bl[i] = B.STARCORE_ORE
				else:
					bl[i] = B.CORE_ROCK


func _put(f: int, u: int, v: int, l: int, b: int, force: bool) -> void:
	if u < 2 or v < 2 or u > W - 3 or v > W - 3 or l > C - 3:
		return
	var i := fidx(f, u, v, l)
	var cur := blocks[i]
	if force or cur == B.AIR or (cur == B.TALL_GRASS):
		blocks[i] = b


func _decorate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 99
	var cells := [10, 5, 13, 7, 11, 13]
	var chances := [0.45, 0.9, 0.4, 0.65, 0.45, 0.45]
	for f in 6:
		var bio: int = biome(f)
		var cell: int = cells[bio]
		for cu in range(0, W, cell):
			for cv in range(0, W, cell):
				if rng.randf() > chances[bio]:
					continue
				var u := cu + rng.randi_range(0, cell - 1)
				var v := cv + rng.randi_range(0, cell - 1)
				if maxf(absf(u - C + 0.5), absf(v - C + 0.5)) > R - 4:
					continue
				var hh: int = hmap[(f * W + u) * W + v]
				if hh <= SEA:
					continue
				var ground := blocks[fidx(f, u, v, hh - 1)]
				match bio:
					MEADOW, FOREST:
						if ground == B.GRASS:
							if bio == FOREST and rng.randf() < 0.35:
								_tree_round(f, u, v, hh, rng, B.BIRCH_LOG, B.BIRCH_LEAVES, rng.randi_range(5, 7))
							else:
								_tree_round(f, u, v, hh, rng, B.LOG, B.LEAVES, rng.randi_range(4, 6))
					TUNDRA:
						if ground == B.SNOW:
							_tree_spruce(f, u, v, hh, rng)
					HIGHLANDS:
						if ground == B.GRASS:
							_tree_spruce(f, u, v, hh, rng) if rng.randf() < 0.6 else _tree_round(f, u, v, hh, rng, B.LOG, B.LEAVES, 5)
					DESERT:
						if ground == B.SAND:
							for k in rng.randi_range(2, 4):
								_put(f, u, v, hh + k, B.CACTUS, false)
					ASHLANDS:
						if ground == B.ASH:
							var th := rng.randi_range(3, 5)
							for k in th:
								_put(f, u, v, hh + k, B.LOG, false)
							var dir := rng.randi_range(0, 3)
							var du: int = [1, -1, 0, 0][dir]
							var dv: int = [0, 0, 1, -1][dir]
							_put(f, u + du, v + dv, hh + th - 1, B.LOG, false)
							_put(f, u + du * 2, v + dv * 2, hh + th, B.LOG, false)
		var plant_chance: float = [0.14, 0.07, 0.015, 0.0, 0.06, 0.012][bio]
		for u in range(C - R + 1, C + R - 1):
			for v in range(C - R + 1, C + R - 1):
				if rng.randf() > plant_chance:
					continue
				var hh: int = hmap[(f * W + u) * W + v]
				var gi := fidx(f, u, v, hh - 1)
				var g := blocks[gi]
				var pi := fidx(f, u, v, hh)
				if blocks[pi] != B.AIR:
					continue
				if g == B.GRASS:
					var r := rng.randf()
					blocks[pi] = B.FLOWER_RED if r < 0.12 else (B.FLOWER_YELLOW if r < 0.24 else B.TALL_GRASS)
				elif g == B.SAND or g == B.ASH:
					blocks[pi] = B.DEAD_BUSH


func _tree_round(f: int, u: int, v: int, l0: int, rng: RandomNumberGenerator, log_b: int, leaf_b: int, h: int) -> void:
	for k in h:
		_put(f, u, v, l0 + k, log_b, true)
	var top := l0 + h - 1
	for dl in range(-2, 2):
		var rad := 2 if dl < 0 else 1
		for du in range(-rad, rad + 1):
			for dv in range(-rad, rad + 1):
				if absi(du) == rad and absi(dv) == rad and (dl >= 0 or rng.randf() < 0.5):
					continue
				if du == 0 and dv == 0 and dl < 1:
					continue
				_put(f, u + du, v + dv, top + dl, leaf_b, false)


func _tree_spruce(f: int, u: int, v: int, l0: int, rng: RandomNumberGenerator) -> void:
	var h := rng.randi_range(6, 9)
	for k in h:
		_put(f, u, v, l0 + k, B.SPRUCE_LOG, true)
	_put(f, u, v, l0 + h, B.SPRUCE_LEAVES, false)
	_put(f, u, v, l0 + h + 1, B.SPRUCE_LEAVES, false)
	var rad := 0
	for k in range(h - 1, 1, -1):
		rad = 1 if rad != 1 else (2 if k < h - 3 else 1)
		for du in range(-rad, rad + 1):
			for dv in range(-rad, rad + 1):
				if du == 0 and dv == 0:
					continue
				if absi(du) + absi(dv) > rad + (1 if rad == 2 else 0):
					continue
				_put(f, u + du, v + dv, l0 + k, B.SPRUCE_LEAVES, false)


# ---------------- structures ----------------

func _structures() -> void:
	structures.clear()
	_gen_lights.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 4242
	_village(2, C + 12, C - 12, rng)
	_village(5, C + rng.randi_range(-6, 6), C + rng.randi_range(-6, 6), rng)
	_pyramid(1, C + rng.randi_range(-6, 6), C + rng.randi_range(-6, 6), rng)
	_ruins(2, C - 12, C + 12, 23, rng)
	_ruins(4, C + rng.randi_range(-6, 6), C + rng.randi_range(-6, 6), 22, rng)


func _place(f: int, u: int, v: int, l: int, b: int) -> void:
	_put(f, u, v, l, b, true)
	if B.LIGHT[b] > 0.0 and u >= 2 and v >= 2 and u <= W - 3 and v <= W - 3 and l <= C - 3:
		_gen_lights.append(fidx(f, u, v, l))


## Torch hung on the wall that lies one step (du, dv) away on the same layer.
func _wall_torch(f: int, u: int, v: int, l: int, du: int, dv: int) -> void:
	_place(f, u, v, l, B.TORCH)
	torch_wall[fidx(f, u, v, l)] = Vector3i(_fpos(f, u + du, v + dv, l) - _fpos(f, u, v, l))


func _peek(f: int, u: int, v: int, l: int) -> int:
	return blocks[fidx(f, u, v, l)]


## State of the furnace at voxel index `i` (created empty on first access).
func furnace_at(i: int) -> Dictionary:
	if not furnaces.has(i):
		furnaces[i] = {"in": null, "fuel": null, "out": null, "burn": 0.0, "burn_max": 0.0, "prog": 0.0}
	return furnaces[i]


## Contents of the chest at voxel index `i` (created empty on first access).
func chest_inv(i: int) -> Array:
	if not chests.has(i):
		var a := []
		a.resize(CHEST_SLOTS)
		chests[i] = a
	return chests[i]


## Places a chest and fills it with 3-7 rolls from a loot table, scattered across random slots.
func _loot_chest(f: int, u: int, v: int, l: int, table: String, rng: RandomNumberGenerator) -> void:
	_place(f, u, v, l, B.CHEST)
	var inv := []
	inv.resize(CHEST_SLOTS)
	var rolls: Array = loot_tables[table]
	for k in rng.randi_range(3, 7):
		var r: Array = rolls[rng.randi_range(0, rolls.size() - 1)]
		if rng.randf() > r[3]:
			continue
		var slot := rng.randi_range(0, CHEST_SLOTS - 1)
		if inv[slot] == null:
			inv[slot] = {"id": r[0], "n": mini(rng.randi_range(r[1], r[2]), B.stack_max(r[0]))}
	chests[fidx(f, u, v, l)] = inv


func _fpos(f: int, u: int, v: int, l: int) -> Vector3:
	var i := fidx(f, u, v, l)
	return Vector3(i & 127, (i >> 7) & 127, i >> 14) + Vector3(0.5, 0.5, 0.5)


func _h(f: int, u: int, v: int) -> int:
	return hmap[(f * W + u) * W + v]


## Average ground height over a square, so a site on a slope settles in the middle instead of at one corner.
func _avg_h(f: int, u0: int, v0: int, rad: int) -> int:
	var sum := 0
	var n := 0
	for du in range(-rad, rad + 1, 2):
		for dv in range(-rad, rad + 1, 2):
			sum += _h(f, u0 + du, v0 + dv)
			n += 1
	return roundi(float(sum) / n)


## Levels a building site at `base` and blends it into the land around it: hills are cut back in
## one-block terraces and dips are filled the same way over a 7-block margin, so the site never ends
## up buried inside a hill or perched on a cliff. Everything above the cut (trees, hill tops) is cleared.
func _flatten(f: int, u0: int, v0: int, rad: int, base: int, height: int, top: int, fill: int) -> void:
	var margin := 7
	for du in range(-rad - margin, rad + margin + 1):
		for dv in range(-rad - margin, rad + margin + 1):
			var u := u0 + du
			var v := v0 + dv
			if absi(u - C) > R - 2 or absi(v - C) > R - 2:
				continue
			var extra := maxi(0, maxi(absi(du), absi(dv)) - rad)
			var col := _h(f, u, v)
			# Highest allowed ground here and lowest ground we fill up to.
			var cap := base + extra
			var floor_l := base - extra
			var surface := clampi(col, floor_l, cap)
			if extra > 0 and col >= floor_l and col <= cap:
				continue
			for l in range(surface - 7, surface - 1):
				if B.SOLID[_peek(f, u, v, l)] == 0:
					_place(f, u, v, l, fill)
			_place(f, u, v, surface - 1, top)
			for l in range(surface, maxi(col, surface + (height if extra == 0 else 0)) + 12):
				_place(f, u, v, l, B.AIR)


func _village(f: int, cu: int, cv: int, rng: RandomNumberGenerator) -> void:
	var base := maxi(_avg_h(f, cu, cv, 12), SEA + 2)
	var ground: int = B.SNOW if biome(f) == TUNDRA else B.GRASS
	_flatten(f, cu, cv, 13, base, 10, ground, B.DIRT)
	# Well in the middle.
	for du in range(-2, 3):
		for dv in range(-2, 3):
			var edge := absi(du) == 2 or absi(dv) == 2
			_place(f, cu + du, cv + dv, base - 1, B.COBBLE)
			if edge:
				_place(f, cu + du, cv + dv, base, B.COBBLE)
			else:
				for l in range(base - 4, base):
					_place(f, cu + du, cv + dv, l, B.WATER)
			_place(f, cu + du, cv + dv, base + 4, B.SPRUCE_PLANKS)
	for c in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
		for l in range(base + 1, base + 4):
			_place(f, cu + c.x, cv + c.y, l, B.SPRUCE_LOG)
	_place(f, cu, cv, base + 5, B.LAMP)
	# Houses around the well, doors facing it, gravel paths in between.
	var spots := [Vector2i(8, 0), Vector2i(-8, 0), Vector2i(0, 8), Vector2i(0, -8), Vector2i(8, 8), Vector2i(-8, -8)]
	var n := rng.randi_range(4, 6)
	for k in n:
		var s: Vector2i = spots[k]
		var door := Vector2i(-signi(s.x), -signi(s.y))
		if door.x != 0 and door.y != 0:
			door.y = 0
		_house(f, cu + s.x, cv + s.y, base, door, rng)
		var steps := maxi(absi(s.x), absi(s.y))
		for t in range(3, steps - 2):
			var pu := cu + roundi(float(s.x) * t / steps)
			var pv := cv + roundi(float(s.y) * t / steps)
			_place(f, pu, pv, base - 1, B.GRAVEL)
	for c in [Vector2i(4, 4), Vector2i(-4, 4), Vector2i(4, -4), Vector2i(-4, -4)]:
		_place(f, cu + c.x, cv + c.y, base, B.COBBLE)
		_place(f, cu + c.x, cv + c.y, base + 1, B.LOG)
		_place(f, cu + c.x, cv + c.y, base + 2, B.TORCH)
	structures.append({"name": "Village", "sub": "Someone lived here before you crashed...", "pos": _fpos(f, cu, cv, base), "radius": 14.0})


func _house(f: int, u0: int, v0: int, base: int, door: Vector2i, rng: RandomNumberGenerator) -> void:
	var wall: int = [B.PLANKS, B.BIRCH_PLANKS, B.SPRUCE_PLANKS][rng.randi_range(0, 2)]
	var roof: int = B.SPRUCE_PLANKS if wall != B.SPRUCE_PLANKS else B.PLANKS
	for du in range(-3, 4):
		for dv in range(-3, 4):
			_place(f, u0 + du, v0 + dv, base - 1, B.COBBLE if (absi(du) == 3 or absi(dv) == 3) else B.PLANKS)
			for l in range(base, base + 8):
				_place(f, u0 + du, v0 + dv, l, B.AIR)
			var edge := absi(du) == 3 or absi(dv) == 3
			if not edge:
				continue
			var corner := absi(du) == 3 and absi(dv) == 3
			for l in range(base, base + 4):
				var b := B.LOG if corner else wall
				if l == base + 1 and not corner and (du == 0 or dv == 0):
					b = B.GLASS
				_place(f, u0 + du, v0 + dv, l, b)
	# Door gap on the side facing the well.
	for l in [base, base + 1]:
		_place(f, u0 + door.x * 3, v0 + door.y * 3, l, B.AIR)
	_wall_torch(f, u0 + door.x * 4, v0 + door.y * 4, base + 2, -door.x, -door.y)
	# Stepped roof.
	for k in 4:
		var rad := 4 - k
		for du in range(-rad, rad + 1):
			for dv in range(-rad, rad + 1):
				if maxi(absi(du), absi(dv)) == rad or k == 3:
					_place(f, u0 + du, v0 + dv, base + 4 + k, roof)
	# Furniture.
	var side := Vector2i(door.y, door.x)
	_place(f, u0 - door.x * 2 + side.x * 2, v0 - door.y * 2 + side.y * 2, base, B.CRAFTING_TABLE)
	_place(f, u0 - door.x * 2 - side.x * 2, v0 - door.y * 2 - side.y * 2, base, B.FURNACE)
	_place(f, u0 - door.x * 2, v0 - door.y * 2, base, B.WOOL_RED if rng.randf() < 0.5 else B.WOOL_BLUE)
	_wall_torch(f, u0 + side.x * 2, v0 + side.y * 2, base + 2, side.x, side.y)
	_loot_chest(f, u0 - door.x * 2 + side.x, v0 - door.y * 2 + side.y, base, "village", rng)


## Buried stone-brick hall with broken pillars, ore loot and a stairway up to the surface.
func _ruins(f: int, cu: int, cv: int, l0: int, rng: RandomNumberGenerator) -> void:
	var hr := 7
	var ht := 7
	for du in range(-hr, hr + 1):
		for dv in range(-hr, hr + 1):
			for dl in range(-1, ht + 1):
				var shell := absi(du) == hr or absi(dv) == hr or dl == -1 or dl == ht
				var b := B.AIR
				if shell:
					var r := rng.randf()
					b = B.STONE_BRICKS if r < 0.62 else (B.COBBLE if r < 0.85 else (B.SMOOTH_STONE if r < 0.95 else B.GRAVEL))
					if dl == ht and rng.randf() < 0.12:
						b = B.AIR
				_place(f, cu + du, cv + dv, l0 + dl, b)
	# Pillars, some snapped off.
	for c in [Vector2i(-4, -4), Vector2i(4, -4), Vector2i(-4, 4), Vector2i(4, 4)]:
		var top := ht if rng.randf() < 0.6 else rng.randi_range(2, 4)
		for dl in top:
			_place(f, cu + c.x, cv + c.y, l0 + dl, B.STONE_BRICKS)
		if top < ht:
			_place(f, cu + c.x + rng.randi_range(-1, 1), cv + c.y + 1, l0, B.COBBLE)
	# Rubble.
	for k in 14:
		_place(f, cu + rng.randi_range(-6, 6), cv + rng.randi_range(-6, 6), l0, B.COBBLE if rng.randf() < 0.6 else B.GRAVEL)
	# Altar with loot.
	for du in range(-1, 2):
		for dv in range(-1, 2):
			_place(f, cu + du, cv + dv, l0, B.SMOOTH_STONE)
	_place(f, cu, cv, l0 + 1, B.GOLD_BLOCK)
	_loot_chest(f, cu - 3, cv - 3, l0, "ruins", rng)
	_loot_chest(f, cu + 3, cv + 3, l0, "ruins", rng)
	_place(f, cu + 1, cv, l0 + 1, B.DIAMOND_ORE)
	_place(f, cu - 1, cv, l0 + 1, B.GOLD_ORE)
	_place(f, cu, cv + 1, l0 + 1, B.IRON_ORE)
	_place(f, cu, cv - 1, l0 + 1, B.DIAMOND_ORE)
	for c in [Vector2i(-6, 0), Vector2i(6, 0), Vector2i(0, -6), Vector2i(0, 6)]:
		_place(f, cu + c.x, cv + c.y, l0 + 3, B.LAMP)
	# Stairway: from the east wall, one block up per block out, until it breaks the surface.
	var u := cu + hr
	var l := l0
	var steps := 0
	while steps < 40:
		for dv in range(0, 2):
			_place(f, u, cv + dv, l - 1, B.STONE_BRICKS)
			for k in range(0, 3):
				_place(f, u, cv + dv, l + k, B.AIR)
		if steps % 6 == 3:
			_wall_torch(f, u, cv + 2, l + 1, 0, 1)
		if l >= _h(f, u, cv) + 1:
			break
		u += 1
		l += 1
		steps += 1
	# Mark the entrance with a cobble arch.
	for dv in [-1, 2]:
		for k in 3:
			_place(f, u, cv + dv, l + k, B.COBBLE)
	for dv in range(-1, 3):
		_place(f, u, cv + dv, l + 3, B.STONE_BRICKS)
	structures.append({"name": "Ancient Ruins", "sub": "A buried hall, older than the planet's guardian", "pos": _fpos(f, cu, cv, l0 + 2), "radius": 9.0})
	structures.append({"name": "Ruins Entrance", "sub": "Stairs lead down into the dark", "pos": _fpos(f, u, cv, l), "radius": 5.0})


## Hollow sandstone pyramid with a striped band, a torch-lit chamber and a hidden vault below the floor.
func _pyramid(f: int, cu: int, cv: int, rng: RandomNumberGenerator) -> void:
	var base := maxi(_avg_h(f, cu, cv, 8), SEA + 2)
	_flatten(f, cu, cv, 9, base, 12, B.SAND, B.SANDSTONE)
	var size := 8
	for k in size + 1:
		var rad := size - k
		for du in range(-rad, rad + 1):
			for dv in range(-rad, rad + 1):
				var shell := maxi(absi(du), absi(dv)) >= rad - 1 or k >= size - 2 or k == 0
				var b := B.SANDSTONE if shell else B.AIR
				if shell and k == 2 and maxi(absi(du), absi(dv)) == rad:
					b = B.WOOL_ORANGE if (du + dv) % 2 == 0 else B.WOOL_BLUE
				_place(f, cu + du, cv + dv, base + k, b)
	for k in range(1, 3):
		_place(f, cu + size, cv, base + k, B.AIR)
		_place(f, cu + size - 1, cv, base + k, B.AIR)
	_wall_torch(f, cu + size, cv + 1, base + 1, -1, 0)
	_wall_torch(f, cu + size, cv - 1, base + 1, -1, 0)
	for c in [Vector2i(-4, -4), Vector2i(4, -4), Vector2i(-4, 4), Vector2i(4, 4)]:
		_place(f, cu + c.x, cv + c.y, base + 1, B.TORCH)
	# Hidden vault: dig through the plain floor in the middle.
	for du in range(-3, 4):
		for dv in range(-3, 4):
			for l in range(base - 6, base - 1):
				var shell := absi(du) == 3 or absi(dv) == 3 or l == base - 6
				_place(f, cu + du, cv + dv, l, B.SANDSTONE if shell else B.AIR)
	_place(f, cu, cv, base - 5, B.DIAMOND_BLOCK if rng.randf() < 0.5 else B.GOLD_BLOCK)
	_loot_chest(f, cu - 1, cv - 2, base - 5, "pyramid", rng)
	_loot_chest(f, cu + 1, cv + 2, base - 5, "pyramid", rng)
	_loot_chest(f, cu + 4, cv + 2, base + 1, "village", rng)
	for c in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
		_place(f, cu + c.x, cv + c.y, base - 5, B.GOLD_ORE)
		_place(f, cu + c.x, cv + c.y, base - 3, B.LAMP)
	for c in [Vector2i(0, 2), Vector2i(0, -2)]:
		_place(f, cu + c.x, cv + c.y, base - 5, B.TNT)
	structures.append({"name": "Sand Pyramid", "sub": "Something is buried under the floor...", "pos": _fpos(f, cu, cv, base + 2), "radius": 10.0})


func _compute_top(f: int, u: int, v: int) -> int:
	var a := f >> 1
	var pos := (f & 1) == 0
	var lmin := _lmin(a, u, v)
	var ua := 1 if a == 0 else 0
	var va := 1 if a == 2 else 2
	var sa: int = STRIDE[a]
	var base_idx: int = u * STRIDE[ua] + v * STRIDE[va]
	var occ := B.OCCLUDE
	var bl := blocks
	var l := C - 2
	while l >= lmin:
		var ia := C + l if pos else C - 1 - l
		if occ[bl[ia * sa + base_idx]] == 1:
			return l + 1
		l -= 1
	return lmin


func find_spawn() -> Vector3:
	var f := 2
	for r in range(0, 30):
		for du in range(-r, r + 1):
			for dv in range(-r, r + 1):
				if maxi(absi(du), absi(dv)) != r:
					continue
				var u := C + du
				var v := C + dv
				var ci := (f * W + u) * W + v
				var hh: int = hmap[ci]
				if hh > SEA and tops[ci] <= hh + 1 and blocks[fidx(f, u, v, hh - 1)] != B.WATER:
					var feet := fidx(f, u, v, hh)
					if B.SOLID[blocks[feet]] == 0 and B.SOLID[blocks[fidx(f, u, v, hh + 1)]] == 0:
						return Vector3(u + 0.5, C + hh, v + 0.5)
	return Vector3(C + 0.5, C + hmap[(f * W + C) * W + C] + 1, C + 0.5)


## Ground position on the surface near a point, along that point's face. Returns Vector3.INF if none.
func surface_at(p: Vector3) -> Vector3:
	var f := face_of_pos(p)
	var a := f >> 1
	var ua := 1 if a == 0 else 0
	var va := 1 if a == 2 else 2
	var u := floori(p[ua])
	var v := floori(p[va])
	if u < 2 or v < 2 or u > W - 3 or v > W - 3:
		return Vector3.INF
	var l := C - 3
	var lmin := _lmin(a, u, v)
	while l >= lmin:
		var b := blocks[fidx(f, u, v, l)]
		if B.SOLID[b] == 1 or b == B.WATER or b == B.LAVA:
			if b == B.WATER or b == B.LAVA:
				return Vector3.INF
			var q := fpos(f, u, v, l + 1)
			var out := Vector3(q) + Vector3(0.5, 0.5, 0.5)
			var up: Vector3 = UPS[f]
			out -= up * 0.5
			return out
		l -= 1
	return Vector3.INF


# ---------------- editing ----------------

func set_block(x: int, y: int, z: int, id: int, record := true) -> void:
	if x < 2 or y < 2 or z < 2 or x > W - 3 or y > W - 3 or z > W - 3:
		return
	var i := x + (y << 7) + (z << 14)
	var old := blocks[i]
	if old == id:
		if flow.has(i):
			# A source placed over flowing liquid of the same kind.
			flow.erase(i)
			if record:
				edits[i] = id
			mark_dirty_box(x - 1, y - 1, z - 1, x + 1, y + 1, z + 1)
			_wake(i)
		return
	blocks[i] = id
	flow.erase(i)
	if record:
		edits[i] = id
	crops.erase(i)
	if id >= B.WHEAT_0 and id < B.WHEAT_3:
		crops[i] = true
	if B.LIGHT[old] > 0.0:
		_remove_light(i)
	if B.LIGHT[id] > 0.0:
		_add_light(i, id)
	if B.OCCLUDE[old] != B.OCCLUDE[id]:
		_update_top(x, y, z)
	mark_dirty_box(x - 1, y - 1, z - 1, x + 1, y + 1, z + 1)
	_wake(i)
	if old == B.TORCH:
		torch_wall.erase(i)
	if B.SOLID[old] == 1 and B.SOLID[id] == 0:
		_pop_unsupported_torches(i)


func _offset(d: Vector3i) -> int:
	return d.x + (d.y << 7) + (d.z << 14)


## Index of the block a torch at `i` rests on: the wall it hangs on, or the floor under it.
func torch_support(i: int) -> int:
	if torch_wall.has(i):
		return i + _offset(torch_wall[i])
	var vf := voxel_face(i & 127, (i >> 7) & 127, i >> 14)
	return i - _offset(Vector3i(UPS[vf[0]]))


func _pop_unsupported_torches(i: int) -> void:
	for k in 6:
		var n: int = i + NOFF[k]
		if n < 0 or n >= blocks.size() or blocks[n] != B.TORCH:
			continue
		if torch_support(n) == i:
			var p := Vector3(n & 127, (n >> 7) & 127, n >> 14)
			set_block(int(p.x), int(p.y), int(p.z), B.AIR)
			torch_popped.emit(p + Vector3(0.5, 0.5, 0.5))


func _update_top(x: int, y: int, z: int) -> void:
	var vf := voxel_face(x, y, z)
	var f: int = vf[0]
	var u: int = vf[1]
	var v: int = vf[2]
	var ci := (f * W + u) * W + v
	var old := tops[ci]
	var nt := _compute_top(f, u, v)
	if nt == old:
		return
	tops[ci] = nt
	var lo := maxi(mini(old, nt) - 8, 0)
	var hi := mini(maxi(old, nt) + 1, C - 1)
	var p0 := fpos(f, clampi(u - 1, 0, W - 1), clampi(v - 1, 0, W - 1), lo)
	var p1 := fpos(f, clampi(u + 1, 0, W - 1), clampi(v + 1, 0, W - 1), hi)
	mark_dirty_box(mini(p0.x, p1.x), mini(p0.y, p1.y), mini(p0.z, p1.z), maxi(p0.x, p1.x), maxi(p0.y, p1.y), maxi(p0.z, p1.z))


func mark_dirty_box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> void:
	for cz in range(clampi(z0 >> 4, 0, 7), clampi(z1 >> 4, 0, 7) + 1):
		for cy in range(clampi(y0 >> 4, 0, 7), clampi(y1 >> 4, 0, 7) + 1):
			for cx in range(clampi(x0 >> 4, 0, 7), clampi(x1 >> 4, 0, 7) + 1):
				dirty[cx + (cy << 3) + (cz << 6)] = true


func flush_dirty(budget_ms := 6) -> void:
	if dirty.is_empty():
		return
	var t0 := Time.get_ticks_msec()
	var keys := dirty.keys()
	keys.sort_custom(func(a, b): return _chunk_dist(a) < _chunk_dist(b))
	for k in keys:
		dirty.erase(k)
		_build_chunk(k)
		if Time.get_ticks_msec() - t0 > budget_ms:
			break


func _chunk_dist(ci: int) -> float:
	var c := Vector3((ci & 7) * 16 + 8, ((ci >> 3) & 7) * 16 + 8, (ci >> 6) * 16 + 8)
	return c.distance_squared_to(light_anchor)


## Blasts a sphere of blocks away. Returns [[Vector3 cell centre, block id], ...] of what was destroyed.
func explode(center: Vector3, radius: float) -> Array:
	var r := ceili(radius)
	var cx := floori(center.x)
	var cy := floori(center.y)
	var cz := floori(center.z)
	var cols := {}
	var gone := []
	for dz in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var d2 := dx * dx + dy * dy + dz * dz
				if d2 > radius * radius + randf() * 2.0:
					continue
				var x := cx + dx
				var y := cy + dy
				var z := cz + dz
				if x < 2 or y < 2 or z < 2 or x > W - 3 or y > W - 3 or z > W - 3:
					continue
				var i := x + (y << 7) + (z << 14)
				var b := blocks[i]
				if b == B.AIR or b == B.WATER or b == B.LAVA or b == B.OBSIDIAN or b == B.CORE_ROCK or b == B.STARCORE_ORE:
					continue
				if b == B.TNT:
					tnt_lit.emit(Vector3(x + 0.5, y + 0.5, z + 0.5))
				blocks[i] = B.AIR
				gone.append([Vector3(x + 0.5, y + 0.5, z + 0.5), b])
				edits[i] = B.AIR
				_wake(i)
				if B.LIGHT[b] > 0.0:
					_remove_light(i)
				var vf := voxel_face(x, y, z)
				cols[vf[0] * WW + vf[1] * W + vf[2]] = Vector3i(x, y, z)
	for k in cols:
		var p: Vector3i = cols[k]
		_update_top(p.x, p.y, p.z)
	mark_dirty_box(cx - r - 1, cy - r - 1, cz - r - 1, cx + r + 1, cy + r + 1, cz + r + 1)
	return gone


func _add_light(i: int, id: int) -> void:
	var l := OmniLight3D.new()
	var x := i & 127
	var y := (i >> 7) & 127
	var z := i >> 14
	var vf := voxel_face(x, y, z)
	var up: Vector3 = UPS[vf[0]]
	l.position = Vector3(x + 0.5, y + 0.5, z + 0.5) + up * 0.2
	if id == B.TORCH:
		l.light_color = Color(1.0, 0.72, 0.42)
		l.omni_range = 9.0
		l.light_energy = 1.6
	else:
		l.light_color = Color(1.0, 0.88, 0.65)
		l.omni_range = 12.0
		l.light_energy = 2.0
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	add_child(l)
	light_nodes[i] = l


func _remove_light(i: int) -> void:
	if light_nodes.has(i):
		light_nodes[i].queue_free()
		light_nodes.erase(i)


func _process(delta: float) -> void:
	flush_dirty(4)
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.5
		for k in light_nodes:
			var l: OmniLight3D = light_nodes[k]
			l.visible = l.position.distance_squared_to(light_anchor) < 3600.0


# ---------------- liquids ----------------

## Is (x,y,z) a water/lava source (as opposed to flowing liquid or anything else)?
func is_source(x: int, y: int, z: int) -> bool:
	var b := get_b(x, y, z)
	return (b == B.WATER or b == B.LAVA) and not flow.has(idx_of(x, y, z))


## Advances liquid flow: water steps every WATER_STEP, lava every LAVA_STEP, each step bounded by `budget_ms`.
func flow_tick(dt: float, budget_ms := 3) -> void:
	_wt += dt
	_lt += dt
	if _wt >= WATER_STEP:
		_wt = minf(_wt - WATER_STEP, WATER_STEP)
		var cur := _wq
		_wq = {}
		_step_queue(cur, budget_ms)
	if _lt >= LAVA_STEP:
		_lt = minf(_lt - LAVA_STEP, LAVA_STEP)
		var cur := _lq
		_lq = {}
		_step_queue(cur, budget_ms)


## Number of liquid cells waiting for an update.
func flow_pending() -> int:
	return _wq.size() + _lq.size()


func _step_queue(cur: Dictionary, budget_ms: int) -> void:
	var t0 := Time.get_ticks_usec()
	var keys := cur.keys()
	for n in keys.size():
		_eval(keys[n])
		if Time.get_ticks_usec() - t0 > budget_ms * 1000:
			for k in range(n + 1, keys.size()):
				_wake_one(keys[k])
			return


func _wake_one(i: int) -> void:
	if i < 0 or i >= blocks.size():
		return
	var b := blocks[i]
	if b == B.WATER:
		_wq[i] = true
	elif b == B.LAVA:
		_lq[i] = true


func _wake(i: int) -> void:
	_wake_one(i)
	for k in 6:
		_wake_one(i + NOFF[k])


## Face index (into UPS/NOFF) of voxel index `i`; NOFF[face ^ 1] is its "down" step.
static func _face_i(i: int) -> int:
	var dx := 2 * (i & 127) + 1 - 2 * C
	var dy := 2 * ((i >> 7) & 127) + 1 - 2 * C
	var dz := 2 * (i >> 14) + 1 - 2 * C
	var qx := absi(dx)
	var qy := absi(dy)
	var qz := absi(dz)
	if qx >= qy and qx >= qz:
		return 0 if dx > 0 else 1
	if qy >= qz:
		return 2 if dy > 0 else 3
	return 4 if dz > 0 else 5


## Liquid may wash this block away (air, plants, torches).
static func _replaceable(b: int) -> bool:
	return b == B.AIR or B.RENDER[b] == B.R_CROSS or B.RENDER[b] == B.R_TORCH


func _touches(i: int, id: int) -> bool:
	for k in 6:
		if blocks[i + NOFF[k]] == id:
			return true
	return false


func _touches_flowing_lava(i: int) -> bool:
	for k in 6:
		var n: int = i + NOFF[k]
		if blocks[n] == B.LAVA and flow.has(n):
			return true
	return false


## Liquid `b` at `i` (on face `f`) pours downward instead of spreading sideways.
func _falls(i: int, b: int, f: int) -> bool:
	var dn: int = i + NOFF[f ^ 1]
	var below := blocks[dn]
	if below == b:
		return flow.has(dn)
	return _replaceable(below) or below == B.WATER or below == B.LAVA


## Level a flowing cell should have from its neighbours: 8 = becomes a source, 7 = fed from above, 0 = drains.
func _feed(i: int, b: int, f: int) -> int:
	var step := 2 if b == B.LAVA else 1
	var best := 0
	var srcs := 0
	for k in 6:
		if k >> 1 == f >> 1:
			continue
		var n: int = i + NOFF[k]
		if blocks[n] != b:
			continue
		var nl: int = flow.get(n, 8)
		if nl == 8:
			srcs += 1
		var nf := _face_i(n)
		if k >> 1 == nf >> 1 or _falls(n, b, nf):
			continue
		best = maxi(best, nl - step)
	if b == B.WATER and srcs >= 2:
		var below := blocks[i + NOFF[f ^ 1]]
		if B.SOLID[below] == 1 or below == B.WATER:
			return 8
	var up: int = i + NOFF[f]
	if blocks[up] == b and up + NOFF[_face_i(up) ^ 1] == i:
		return 7
	return best


func _eval(i: int) -> void:
	var b := blocks[i]
	if b != B.WATER and b != B.LAVA:
		return
	if b == B.LAVA and _touches(i, B.WATER):
		_fuse(i, B.COBBLE if flow.has(i) else B.OBSIDIAN)
		return
	var f := _face_i(i)
	var lvl := 8
	if flow.has(i):
		lvl = _feed(i, b, f)
		if lvl <= 0:
			_flow_set(i, B.AIR, 0)
			return
		if lvl == 8:
			flow.erase(i)
			edits[i] = b
			_flow_changed(i)
		elif lvl != flow[i]:
			flow[i] = lvl
			_flow_changed(i)
	if _falls(i, b, f):
		_push(i + NOFF[f ^ 1], b, 7)
		return
	var out := lvl - (2 if b == B.LAVA else 1)
	if out <= 0:
		return
	for k in 6:
		if k >> 1 != f >> 1:
			_push(i + NOFF[k], b, out)


## Liquid `b` tries to flow into cell `t` at level `lvl`; meeting the other liquid hardens it.
func _push(t: int, b: int, lvl: int) -> void:
	var tb := blocks[t]
	if tb == b:
		if flow.get(t, 8) < lvl:
			_wake_one(t)
		return
	if b == B.LAVA:
		if _replaceable(tb):
			if _touches(t, B.WATER):
				_fuse(t, B.COBBLE)
			else:
				_flow_set(t, B.LAVA, lvl)
		return
	if tb == B.LAVA:
		if flow.has(t):
			_fuse(t, B.COBBLE)
		else:
			_wake_one(t)
		return
	if _replaceable(tb):
		if _touches_flowing_lava(t):
			_fuse(t, B.COBBLE)
		else:
			_flow_set(t, B.WATER, lvl)


## Sets a flowing cell (or drains one with AIR) without recording it as a player edit.
func _flow_set(i: int, id: int, lvl: int) -> void:
	var old := blocks[i]
	if old != B.AIR and old != B.WATER and old != B.LAVA:
		edits[i] = B.AIR
	set_block(i & 127, (i >> 7) & 127, i >> 14, id, false)
	if id != B.AIR and blocks[i] == id:
		flow[i] = lvl


func _flow_changed(i: int) -> void:
	var x := i & 127
	var y := (i >> 7) & 127
	var z := i >> 14
	mark_dirty_box(x - 1, y - 1, z - 1, x + 1, y + 1, z + 1)
	_wake(i)


func _fuse(i: int, id: int) -> void:
	var x := i & 127
	var y := (i >> 7) & 127
	var z := i >> 14
	set_block(x, y, z, id)
	liquid_fused.emit(Vector3(x + 0.5, y + 0.5, z + 0.5))


# ---------------- raycast ----------------

func raycast(o: Vector3, d: Vector3, maxd: float, liquids := false) -> Dictionary:
	var x := floori(o.x)
	var y := floori(o.y)
	var z := floori(o.z)
	var sx := 1 if d.x > 0 else -1
	var sy := 1 if d.y > 0 else -1
	var sz := 1 if d.z > 0 else -1
	var tdx := absf(1.0 / d.x) if d.x != 0.0 else INF
	var tdy := absf(1.0 / d.y) if d.y != 0.0 else INF
	var tdz := absf(1.0 / d.z) if d.z != 0.0 else INF
	var tmx := ((x + 1 - o.x) if d.x > 0 else (o.x - x)) * tdx if d.x != 0.0 else INF
	var tmy := ((y + 1 - o.y) if d.y > 0 else (o.y - y)) * tdy if d.y != 0.0 else INF
	var tmz := ((z + 1 - o.z) if d.z > 0 else (o.z - z)) * tdz if d.z != 0.0 else INF
	var n := Vector3i.ZERO
	var t := 0.0
	while t <= maxd:
		if x >= 0 and y >= 0 and z >= 0 and x < W and y < W and z < W:
			var b := blocks[x + (y << 7) + (z << 14)]
			if b != 0 and (B.TARGET[b] == 1 or (liquids and (b == B.WATER or b == B.LAVA))):
				return {"pos": Vector3i(x, y, z), "normal": n, "block": b, "dist": t}
		if tmx < tmy and tmx < tmz:
			x += sx
			t = tmx
			tmx += tdx
			n = Vector3i(-sx, 0, 0)
		elif tmy < tmz:
			y += sy
			t = tmy
			tmy += tdy
			n = Vector3i(0, -sy, 0)
		else:
			z += sz
			t = tmz
			tmz += tdz
			n = Vector3i(0, 0, -sz)
	return {}


# ---------------- meshing ----------------

func _build_chunk(ci: int) -> void:
	_sv.clear(); _sn.clear(); _suv.clear(); _suv2.clear(); _sc.clear(); _si.clear()
	_wv.clear(); _wn.clear(); _wuv.clear(); _wuv2.clear(); _wc.clear(); _wi.clear()
	var x0 := (ci & 7) * CS
	var y0 := ((ci >> 3) & 7) * CS
	var z0 := (ci >> 6) * CS
	var bl := blocks
	var opq := B.OPAQUE
	var rnd := B.RENDER
	for z in range(z0, z0 + CS):
		var qz := absi(2 * z + 1 - 2 * C)
		for y in range(y0, y0 + CS):
			var qy := absi(2 * y + 1 - 2 * C)
			var row := (y << 7) + (z << 14)
			for x in range(x0, x0 + CS):
				var i := row + x
				var b := bl[i]
				if b == 0:
					continue
				var rt := rnd[b]
				if rt == B.R_CUBE:
					if opq[bl[i + 1]] == 1 and opq[bl[i - 1]] == 1 and opq[bl[i + 128]] == 1 and opq[bl[i - 128]] == 1 and opq[bl[i + 16384]] == 1 and opq[bl[i - 16384]] == 1:
						continue
				var qx := absi(2 * x + 1 - 2 * C)
				var ua: int
				var us: int
				if qx >= qy and qx >= qz:
					ua = 0
					us = 1 if x >= C else -1
				elif qy >= qz:
					ua = 1
					us = 1 if y >= C else -1
				else:
					ua = 2
					us = 1 if z >= C else -1
				if rt == B.R_CROSS or rt == B.R_TORCH:
					_cross(i, x, y, z, b, ua, us)
					continue
				for f in 6:
					var nb := bl[i + NOFF[f]]
					if opq[nb] == 1:
						continue
					if rt == B.R_WATER:
						if nb == B.LAVA:
							continue
						# Water faces between cells are hidden, except a sideways face down to lower flowing water.
						if nb == B.WATER and (flow.is_empty() or f >> 1 == ua or flow.get(i + NOFF[f], 8) >= flow.get(i, 8)):
							continue
					elif rt == B.R_LAVA:
						if nb == B.LAVA:
							continue
					elif nb == b and b == B.GLASS:
						continue
					_quad(i, x, y, z, f, b, ua, us, rt)
	_commit(ci)


func _quad(i: int, x: int, y: int, z: int, f: int, b: int, ua: int, us: int, rt: int) -> void:
	var a := f >> 1
	var fpos_dir := (f & 1) == 0
	var layer_i: int
	var shade: float
	if a == ua:
		if fpos_dir == (us > 0):
			layer_i = B.TEX_TOP[b]
			shade = 1.0
		else:
			layer_i = B.TEX_BOT[b]
			shade = 0.55
	else:
		layer_i = B.TEX_SIDE[b]
		shade = 0.84 if a == (ua + 1) % 3 else 0.7
	var n: int = i + NOFF[f]
	var vis := sky_vis(n)
	var emit := B.EMIT[b]
	var wat := rt == B.R_WATER
	var anim := 1.0 if (wat or rt == B.R_LAVA) else 0.0
	var drop := 0.0
	if wat and blocks[i + STRIDE[ua] * us] != B.WATER:
		drop = 1.0 - 0.11 * flow[i] if flow.has(i) else 0.12
	var corners: Array = _fc[f]
	var aos: Array = _fao[f]
	var occ := B.OCCLUDE
	var bl := blocks
	var base := Vector3(x, y, z)
	var nrm: Vector3 = UPS[f]
	var verts: PackedVector3Array = _wv if wat else _sv
	var start := verts.size()
	var tcoord := 3 - a - ua
	var top_val := 1.0 if us > 0 else 0.0
	var b1 := (a + 1) % 3
	var b2 := (a + 2) % 3
	var lv := [0, 0, 0, 0]
	for k in 4:
		var co: Vector3 = corners[k]
		var p := base + co
		if drop > 0.0 and co[ua] == top_val:
			p[ua] -= drop * us
		var uv: Vector2
		if a == ua:
			uv = Vector2(co[b1], co[b2])
		else:
			uv = Vector2(co[tcoord], 1.0 - co[ua] if us > 0 else co[ua])
		var ao: Array = aos[k]
		var s1 := occ[bl[n + ao[0]]]
		var s2 := occ[bl[n + ao[1]]]
		var cc := occ[bl[n + ao[2]]]
		var lvl := 0 if (s1 == 1 and s2 == 1) else 3 - (s1 + s2 + cc)
		lv[k] = lvl
		# Smooth light: average the sky visibility of the open cells around this corner so shade
		# fades across block edges instead of stepping per face.
		var sv := vis
		var cnt := 1.0
		if s1 == 0:
			sv += sky_vis(n + ao[0])
			cnt += 1.0
		if s2 == 0:
			sv += sky_vis(n + ao[1])
			cnt += 1.0
		if cc == 0 and (s1 == 0 or s2 == 0):
			sv += sky_vis(n + ao[2])
			cnt += 1.0
		var col := Color(shade * AO_LEVELS[lvl], sv / cnt, emit, 1.0)
		if wat:
			_wv.append(p); _wn.append(nrm); _wuv.append(uv); _wuv2.append(Vector2(layer_i, anim)); _wc.append(col)
		else:
			_sv.append(p); _sn.append(nrm); _suv.append(uv); _suv2.append(Vector2(layer_i, anim)); _sc.append(col)
	var idx: PackedInt32Array = _wi if wat else _si
	if lv[0] + lv[2] >= lv[1] + lv[3]:
		idx.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	else:
		idx.append_array([start + 1, start + 2, start + 3, start + 1, start + 3, start])
	if wat:
		_wi = idx
	else:
		_si = idx


func _cross(i: int, x: int, y: int, z: int, b: int, ua: int, us: int) -> void:
	var layer_i := B.TEX_SIDE[b]
	var vis := sky_vis(i)
	var emit := B.EMIT[b]
	var ta := (ua + 1) % 3
	var tb := (ua + 2) % 3
	var bot := 0.0 if us > 0 else 1.0
	var top := 1.0 - bot
	var base := Vector3(x, y, z)
	var nrm: Vector3 = UPS[ua * 2 + (0 if us > 0 else 1)]
	var col := Color(0.92, vis, emit, 1.0)
	var lo := 0.15
	var hi := 0.85
	# Wall torches lean out of the wall: foot pushed into it, tip less so, and the whole torch raised.
	var wall := Vector3(torch_wall[i]) if (b == B.TORCH and torch_wall.has(i)) else Vector3.ZERO
	for plane in 2:
		var s0 := Vector2(lo, lo) if plane == 0 else Vector2(hi, lo)
		var s1 := Vector2(hi, hi) if plane == 0 else Vector2(lo, hi)
		var pts := []
		for q in [[s0, bot], [s1, bot], [s1, top], [s0, top]]:
			var p := base
			var s: Vector2 = q[0]
			p[ta] += s.x
			p[tb] += s.y
			p[ua] += q[1]
			if wall != Vector3.ZERO:
				var foot: bool = q[1] == bot
				p += wall * (0.36 if foot else 0.14)
				p[ua] += 0.2 * us
			pts.append(p)
		var start := _sv.size()
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in 4:
			_sv.append(pts[k]); _sn.append(nrm); _suv.append(uvs[k]); _suv2.append(Vector2(layer_i, 0)); _sc.append(col)
		_si.append_array([start, start + 1, start + 2, start, start + 2, start + 3, start, start + 2, start + 1, start, start + 3, start + 2])


func _commit(ci: int) -> void:
	var nodes: Array = chunk_nodes.get(ci, [null, null])
	if _sv.is_empty() and _wv.is_empty():
		for n in nodes:
			if n:
				n.queue_free()
		chunk_nodes.erase(ci)
		return
	for s in 2:
		var verts: PackedVector3Array = _sv if s == 0 else _wv
		var mi: MeshInstance3D = nodes[s]
		if verts.is_empty():
			if mi:
				mi.queue_free()
				nodes[s] = null
			continue
		if mi == null:
			mi = MeshInstance3D.new()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if s == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			nodes[s] = mi
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		if s == 0:
			arr[Mesh.ARRAY_VERTEX] = _sv
			arr[Mesh.ARRAY_NORMAL] = _sn
			arr[Mesh.ARRAY_TEX_UV] = _suv
			arr[Mesh.ARRAY_TEX_UV2] = _suv2
			arr[Mesh.ARRAY_COLOR] = _sc
			arr[Mesh.ARRAY_INDEX] = _si
		else:
			arr[Mesh.ARRAY_VERTEX] = _wv
			arr[Mesh.ARRAY_NORMAL] = _wn
			arr[Mesh.ARRAY_TEX_UV] = _wuv
			arr[Mesh.ARRAY_TEX_UV2] = _wuv2
			arr[Mesh.ARRAY_COLOR] = _wc
			arr[Mesh.ARRAY_INDEX] = _wi
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat_solid if s == 0 else mat_water)
		mi.mesh = m
	chunk_nodes[ci] = nodes


## A unit cube mesh (centered on origin) for held blocks, drops and TNT.
func make_block_mesh(id: int, size := 1.0) -> ArrayMesh:
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cols := PackedColorArray()
	var ind := PackedInt32Array()
	var rt := B.RENDER[id]
	if rt == B.R_CROSS or rt == B.R_TORCH:
		var layer_i := B.TEX_SIDE[id]
		var pts := [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in 4:
			v.append(pts[k] * size); nn.append(Vector3(0, 0, 1)); uv.append(uvs[k]); uv2.append(Vector2(layer_i, 0)); cols.append(Color(1, 1, B.EMIT[id], 1))
		ind.append_array([0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2])
	else:
		for f in 6:
			var a := f >> 1
			var layer_i: int
			var shade := 1.0
			if a == 1:
				layer_i = B.TEX_TOP[id] if f == 2 else B.TEX_BOT[id]
			else:
				layer_i = B.TEX_SIDE[id]
			var corners: Array = _fc[f]
			var start := v.size()
			for k in 4:
				var co: Vector3 = corners[k]
				var t2: Vector2
				if a == 1:
					t2 = Vector2(co.x, co.z)
				else:
					t2 = Vector2(co[2 - a] if a == 0 else co.x, 1.0 - co.y)
				v.append((co - Vector3(0.5, 0.5, 0.5)) * size); nn.append(UPS[f]); uv.append(t2); uv2.append(Vector2(layer_i, 0)); cols.append(Color(shade, 1, B.EMIT[id], 1))
			ind.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = ind
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat_water if rt == B.R_WATER else mat_solid)
	return m
