extends Node
## Procedural pixel-art textures, block texture array and UI icons (autoload "T").

## 16-wide armor silhouettes (helmet, chestplate, leggings, boots), vertically centred when drawn.
const ARMOR_SHAPES := [
	["....########....", "...##########...", "..############..", "..############..",
		"..###......###..", "..###......###..", "..##........##.."],
	["..###......###..", ".#####....#####.", ".##############.", ".##############.", "..############..",
		"...##########...", "...##########...", "...##########...", "...##########...", "...####..####..."],
	["...##########...", "...##########...", "...##########...", "...####..####...", "...####..####...",
		"...####..####...", "...###....###...", "...###....###...", "...###....###...", "...###....###..."],
	["....###...###...", "....###...###...", "....###...###...", "..#####.#####...", "..#####.#####..."],
]

var images := {}
var array_tex: Texture2DArray
var icons := {}
var cracks: Array[ImageTexture] = []
var heart_full: ImageTexture
var heart_half: ImageTexture
var heart_empty: ImageTexture
var armor_full: ImageTexture
var armor_half: ImageTexture
var armor_empty: ImageTexture
var block_color := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for n in B.texture_names:
		images[n] = _paint(n)
	var arr: Array[Image] = []
	for n in B.texture_names:
		var im: Image = images[n].duplicate()
		im.generate_mipmaps()
		arr.append(im)
	array_tex = Texture2DArray.new()
	array_tex.create_from_images(arr)
	for id in B.block_list:
		block_color[id] = _avg(images[B.texture_names[B.TEX_SIDE[id]]])
	block_color[B.WATER] = Color(0.2, 0.4, 0.9)
	block_color[B.LAVA] = Color(1.0, 0.5, 0.1)
	for s in 10:
		cracks.append(ImageTexture.create_from_image(_crack(s)))
	_make_hearts()
	_make_armor_icons()


func _avg(im: Image) -> Color:
	var c := Color(0, 0, 0, 0)
	var n := 0.0
	for y in 16:
		for x in 16:
			var p := im.get_pixel(x, y)
			if p.a > 0.5:
				c += p
				n += 1.0
	return c / maxf(n, 1.0)


func _seed(n: String) -> void:
	_rng.seed = hash(n)


func _img() -> Image:
	return Image.create(16, 16, false, Image.FORMAT_RGBA8)


func _v(c: Color, amt: float) -> Color:
	var k := _rng.randf_range(-amt, amt)
	return Color(clampf(c.r + k, 0, 1), clampf(c.g + k, 0, 1), clampf(c.b + k, 0, 1), c.a)


func _noise(base: Color, amt: float) -> Image:
	var im := _img()
	for y in 16:
		for x in 16:
			im.set_pixel(x, y, _v(base, amt))
	return im


func _specks(im: Image, col: Color, count: int, amt := 0.04) -> void:
	for i in count:
		im.set_pixel(_rng.randi_range(0, 15), _rng.randi_range(0, 15), _v(col, amt))


func _ore(spot: Color, hi: Color) -> Image:
	var im := _stone()
	for k in 5:
		var cx := _rng.randi_range(2, 13)
		var cy := _rng.randi_range(2, 13)
		for p in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 0)]:
			if _rng.randf() < 0.85:
				var px := clampi(cx + p.x, 0, 15)
				var py := clampi(cy + p.y, 0, 15)
				im.set_pixel(px, py, _v(spot, 0.06))
		im.set_pixel(cx, cy, hi)
	return im


func _stone() -> Image:
	var im := _noise(Color(0.5, 0.5, 0.52), 0.05)
	for i in 14:
		var x := _rng.randi_range(0, 14)
		var y := _rng.randi_range(0, 15)
		var c := _v(Color(0.42, 0.42, 0.44), 0.03)
		im.set_pixel(x, y, c)
		im.set_pixel(x + 1, y, c)
	return im


func _planks(base: Color) -> Image:
	var im := _img()
	for y in 16:
		var row := y / 4
		for x in 16:
			var c := _v(base, 0.035)
			if y % 4 == 3:
				c = base.darkened(0.35)
			elif (x + row * 5) % 16 == 0:
				c = base.darkened(0.3)
			elif _rng.randf() < 0.08:
				c = base.darkened(0.12)
			im.set_pixel(x, y, c)
	return im


func _bark(base: Color, dark: Color) -> Image:
	var im := _img()
	for x in 16:
		var stripe := _rng.randf() < 0.3
		for y in 16:
			var c := _v(dark if stripe else base, 0.04)
			if _rng.randf() < 0.07:
				c = dark.darkened(0.2)
			im.set_pixel(x, y, c)
	return im


func _rings(bark: Color, inner: Color) -> Image:
	var im := _img()
	for y in 16:
		for x in 16:
			var d := maxf(absf(x - 7.5), absf(y - 7.5))
			var c: Color
			if d > 6.5:
				c = _v(bark, 0.04)
			else:
				c = _v(inner if int(d) % 2 == 0 else inner.darkened(0.15), 0.03)
			im.set_pixel(x, y, c)
	return im


func _leaves(base: Color) -> Image:
	var im := _img()
	for y in 16:
		for x in 16:
			if _rng.randf() < 0.2:
				im.set_pixel(x, y, Color(base.darkened(0.5), 0.0))
			else:
				var c := _v(base, 0.08)
				if _rng.randf() < 0.15:
					c = base.lightened(0.15)
				im.set_pixel(x, y, c)
	return im


func _side_top(bottom: Image, top_col: Color, depth: int) -> Image:
	var im := bottom.duplicate()
	for x in 16:
		var d := depth + _rng.randi_range(-1, 1)
		for y in d:
			im.set_pixel(x, y, _v(top_col, 0.05))
	return im


func _bricks(base: Color, mortar: Color, bw := 8, bh := 4) -> Image:
	var im := _img()
	for y in 16:
		var row := y / bh
		for x in 16:
			var xo := (x + (bw / 2 if row % 2 == 1 else 0)) % bw
			var c := _v(base, 0.04)
			if y % bh == bh - 1 or xo == bw - 1:
				c = _v(mortar, 0.02)
			im.set_pixel(x, y, c)
	return im


func _metal(base: Color) -> Image:
	var im := _noise(base, 0.025)
	for i in 16:
		im.set_pixel(i, 0, base.lightened(0.35))
		im.set_pixel(0, i, base.lightened(0.35))
		im.set_pixel(i, 15, base.darkened(0.35))
		im.set_pixel(15, i, base.darkened(0.35))
	for i in 6:
		im.set_pixel(3 + i, 3, base.lightened(0.5))
	return im


func _cross_plant(stem: Color, top: Color, flower: bool) -> Image:
	var im := _img()
	if flower:
		for y in range(7, 16):
			im.set_pixel(7, y, _v(stem, 0.05))
		im.set_pixel(6, 11, stem)
		im.set_pixel(5, 10, stem)
		im.set_pixel(8, 12, stem)
		im.set_pixel(9, 11, stem)
		for p in [Vector2i(7, 3), Vector2i(6, 4), Vector2i(8, 4), Vector2i(7, 5), Vector2i(6, 5), Vector2i(8, 5), Vector2i(7, 6), Vector2i(5, 4), Vector2i(9, 4)]:
			im.set_pixel(p.x, p.y, _v(top, 0.06))
		im.set_pixel(7, 4, Color(1, 0.95, 0.4))
	else:
		for blade in 7:
			var x := _rng.randi_range(1, 14)
			var h := _rng.randi_range(5, 13)
			var lean := _rng.randf_range(-0.35, 0.35)
			for k in h:
				var px := clampi(int(round(x + lean * k)), 0, 15)
				im.set_pixel(px, 15 - k, _v(stem if k < h - 2 else top, 0.06))
	return im


func _paint(n: String) -> Image:
	_seed(n)
	match n:
		"grass_top":
			var im := _noise(Color(0.36, 0.62, 0.24), 0.06)
			_specks(im, Color(0.45, 0.72, 0.3), 20)
			return im
		"dirt":
			var im := _noise(Color(0.47, 0.33, 0.22), 0.05)
			_specks(im, Color(0.36, 0.25, 0.16), 22)
			_specks(im, Color(0.58, 0.45, 0.33), 8)
			return im
		"grass_side":
			_seed("dirt")
			var d := _paint("dirt")
			_seed(n)
			return _side_top(d, Color(0.36, 0.62, 0.24), 4)
		"stone":
			return _stone()
		"smooth_stone":
			var im := _noise(Color(0.6, 0.6, 0.62), 0.02)
			for i in 16:
				im.set_pixel(i, 0, Color(0.68, 0.68, 0.7))
				im.set_pixel(i, 15, Color(0.48, 0.48, 0.5))
			return im
		"cobble":
			var im := _img()
			var pts: Array[Vector2] = []
			for i in 9:
				pts.append(Vector2(_rng.randf_range(0, 16), _rng.randf_range(0, 16)))
			var shades: Array[float] = []
			for i in 9:
				shades.append(_rng.randf_range(0.42, 0.62))
			for y in 16:
				for x in 16:
					var best := 99.0
					var second := 99.0
					var bi := 0
					for i in pts.size():
						for ox in [-16, 0, 16]:
							for oy in [-16, 0, 16]:
								var d := Vector2(x + ox, y + oy).distance_to(pts[i])
								if d < best:
									second = best
									best = d
									bi = i
								elif d < second:
									second = d
					var s := shades[bi]
					var c := Color(s, s, s + 0.02)
					if second - best < 1.2:
						c = Color(0.28, 0.28, 0.3)
					im.set_pixel(x, y, _v(c, 0.03))
			return im
		"sand":
			var im := _noise(Color(0.88, 0.8, 0.55), 0.04)
			_specks(im, Color(0.78, 0.7, 0.46), 16)
			return im
		"sandstone":
			var im := _noise(Color(0.85, 0.76, 0.52), 0.03)
			for x in 16:
				im.set_pixel(x, 4, Color(0.76, 0.66, 0.43))
				im.set_pixel(x, 11, Color(0.76, 0.66, 0.43))
			return im
		"sandstone_top":
			return _noise(Color(0.87, 0.79, 0.55), 0.025)
		"snow":
			var im := _noise(Color(0.94, 0.96, 1.0), 0.03)
			_specks(im, Color(0.85, 0.9, 0.98), 10)
			return im
		"snow_side":
			_seed("dirt")
			var d := _paint("dirt")
			_seed(n)
			return _side_top(d, Color(0.94, 0.96, 1.0), 5)
		"ice":
			var im := _noise(Color(0.6, 0.78, 0.98), 0.03)
			for i in 5:
				var x := _rng.randi_range(0, 12)
				var y := _rng.randi_range(0, 15)
				for k in 4:
					im.set_pixel(mini(x + k, 15), maxi(y - k, 0), Color(0.85, 0.93, 1.0))
			return im
		"log":
			return _bark(Color(0.42, 0.31, 0.19), Color(0.32, 0.23, 0.13))
		"log_top":
			return _rings(Color(0.36, 0.26, 0.15), Color(0.7, 0.55, 0.33))
		"birch":
			var im := _noise(Color(0.88, 0.87, 0.82), 0.03)
			for i in 10:
				var x := _rng.randi_range(0, 13)
				var y := _rng.randi_range(0, 15)
				for k in _rng.randi_range(1, 3):
					im.set_pixel(x + k, y, Color(0.18, 0.18, 0.16))
			return im
		"birch_top":
			return _rings(Color(0.85, 0.84, 0.78), Color(0.78, 0.68, 0.45))
		"spruce":
			return _bark(Color(0.3, 0.21, 0.12), Color(0.22, 0.15, 0.08))
		"spruce_top":
			return _rings(Color(0.26, 0.18, 0.1), Color(0.55, 0.42, 0.25))
		"leaves":
			return _leaves(Color(0.22, 0.5, 0.16))
		"birch_leaves":
			return _leaves(Color(0.42, 0.62, 0.24))
		"spruce_leaves":
			return _leaves(Color(0.15, 0.33, 0.22))
		"planks":
			return _planks(Color(0.7, 0.54, 0.32))
		"spruce_planks":
			return _planks(Color(0.45, 0.32, 0.18))
		"birch_planks":
			return _planks(Color(0.84, 0.76, 0.52))
		"cactus":
			var im := _noise(Color(0.3, 0.58, 0.2), 0.04)
			for y in 16:
				im.set_pixel(0, y, Color(0.2, 0.42, 0.13))
				im.set_pixel(15, y, Color(0.2, 0.42, 0.13))
				im.set_pixel(5, y, Color(0.25, 0.5, 0.17))
				im.set_pixel(10, y, Color(0.25, 0.5, 0.17))
			for i in 8:
				im.set_pixel(_rng.randi_range(1, 14), _rng.randi_range(0, 15), Color(0.9, 0.9, 0.7))
			return im
		"cactus_top":
			var im := _noise(Color(0.35, 0.62, 0.24), 0.04)
			for i in 16:
				im.set_pixel(i, 0, Color(0.2, 0.42, 0.13))
				im.set_pixel(0, i, Color(0.2, 0.42, 0.13))
				im.set_pixel(i, 15, Color(0.2, 0.42, 0.13))
				im.set_pixel(15, i, Color(0.2, 0.42, 0.13))
			return im
		"coal_ore":
			return _ore(Color(0.12, 0.12, 0.13), Color(0.3, 0.3, 0.32))
		"iron_ore":
			return _ore(Color(0.82, 0.62, 0.48), Color(0.95, 0.82, 0.7))
		"gold_ore":
			return _ore(Color(0.98, 0.8, 0.2), Color(1, 1, 0.65))
		"diamond_ore":
			return _ore(Color(0.3, 0.9, 0.88), Color(0.85, 1, 1))
		"starcore_ore":
			var im := _noise(Color(0.17, 0.08, 0.14), 0.04)
			for k in 7:
				var cx := _rng.randi_range(1, 14)
				var cy := _rng.randi_range(1, 14)
				im.set_pixel(cx, cy, Color(1, 0.75, 1))
				for p in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					im.set_pixel(clampi(cx + p.x, 0, 15), clampi(cy + p.y, 0, 15), _v(Color(0.85, 0.3, 0.95), 0.06))
			return im
		"core_rock":
			var im := _noise(Color(0.2, 0.09, 0.07), 0.04)
			for i in 4:
				var x := _rng.randi_range(0, 15)
				var y := _rng.randi_range(0, 15)
				for k in 7:
					im.set_pixel(clampi(x, 0, 15), clampi(y, 0, 15), _v(Color(1.0, 0.42, 0.08), 0.06))
					x += _rng.randi_range(-1, 1)
					y += _rng.randi_range(0, 1)
			return im
		"basalt":
			var im := _img()
			for x in 16:
				var c := _rng.randf_range(0.2, 0.3)
				for y in 16:
					im.set_pixel(x, y, _v(Color(c, c, c + 0.02), 0.025))
			return im
		"basalt_top":
			var im := _noise(Color(0.26, 0.26, 0.28), 0.03)
			for i in 16:
				im.set_pixel(i, 0, Color(0.18, 0.18, 0.2))
				im.set_pixel(0, i, Color(0.18, 0.18, 0.2))
			return im
		"obsidian":
			var im := _noise(Color(0.09, 0.05, 0.14), 0.03)
			_specks(im, Color(0.3, 0.18, 0.45), 14)
			return im
		"ash":
			var im := _noise(Color(0.38, 0.36, 0.36), 0.05)
			_specks(im, Color(0.25, 0.23, 0.23), 25)
			return im
		"magma":
			var im := _noise(Color(0.35, 0.1, 0.05), 0.05)
			for y in 16:
				for x in 16:
					if (x % 8 == 0 or y % 8 == 0) == false and _rng.randf() < 0.35:
						im.set_pixel(x, y, _v(Color(1.0, 0.45, 0.1), 0.08))
			return im
		"water":
			var im := _noise(Color(0.17, 0.38, 0.85), 0.03)
			for i in 6:
				var x := _rng.randi_range(0, 11)
				var y := _rng.randi_range(0, 15)
				for k in 4:
					im.set_pixel(x + k, y, Color(0.35, 0.55, 0.95))
			return im
		"lava":
			var im := _img()
			for y in 16:
				for x in 16:
					var t := 0.5 + 0.5 * sin(x * 0.9 + sin(y * 0.7) * 2.0) * cos(y * 0.6)
					im.set_pixel(x, y, _v(Color(1.0, 0.35 + t * 0.45, 0.05 + t * 0.15), 0.05))
			return im
		"gravel":
			var im := _noise(Color(0.5, 0.48, 0.47), 0.06)
			for i in 20:
				var c := _v(Color(0.35, 0.33, 0.33), 0.08) if _rng.randf() < 0.5 else _v(Color(0.65, 0.62, 0.6), 0.05)
				var x := _rng.randi_range(0, 14)
				var y := _rng.randi_range(0, 14)
				im.set_pixel(x, y, c)
				im.set_pixel(x + 1, y, c)
				im.set_pixel(x, y + 1, c)
			return im
		"table_top":
			var im := _planks(Color(0.66, 0.5, 0.3))
			for i in 16:
				for j in [0, 5, 10, 15]:
					im.set_pixel(i, j, Color(0.35, 0.24, 0.12))
					im.set_pixel(j, i, Color(0.35, 0.24, 0.12))
			return im
		"table_side":
			var im := _planks(Color(0.62, 0.46, 0.27))
			for x in range(2, 7):
				im.set_pixel(x, 3, Color(0.55, 0.55, 0.58))
			for y in range(3, 10):
				im.set_pixel(4, y, Color(0.4, 0.28, 0.15))
			for y in range(2, 11):
				im.set_pixel(11, y, Color(0.4, 0.28, 0.15))
			for p in [Vector2i(10, 2), Vector2i(12, 2), Vector2i(10, 3), Vector2i(12, 3), Vector2i(11, 1)]:
				im.set_pixel(p.x, p.y, Color(0.6, 0.6, 0.64))
			return im
		"chest_top":
			var im := _planks(Color(0.66, 0.47, 0.25))
			for i in 16:
				for j in [0, 15]:
					im.set_pixel(i, j, Color(0.33, 0.21, 0.1))
					im.set_pixel(j, i, Color(0.33, 0.21, 0.1))
			return im
		"chest_front":
			var im := _planks(Color(0.66, 0.47, 0.25))
			var rim := Color(0.33, 0.21, 0.1)
			for i in 16:
				for j in [0, 15]:
					im.set_pixel(i, j, rim)
					im.set_pixel(j, i, rim)
				im.set_pixel(i, 5, Color(0.2, 0.12, 0.06))
				im.set_pixel(i, 6, rim)
			for y in range(3, 9):
				for x in range(7, 9):
					im.set_pixel(x, y, Color(0.78, 0.78, 0.82) if y < 6 else Color(0.55, 0.55, 0.6))
			im.set_pixel(6, 4, Color(0.45, 0.45, 0.5))
			im.set_pixel(9, 4, Color(0.45, 0.45, 0.5))
			return im
		"furnace_top":
			var im := _noise(Color(0.48, 0.48, 0.5), 0.04)
			for i in 16:
				im.set_pixel(i, 0, Color(0.35, 0.35, 0.37))
				im.set_pixel(i, 15, Color(0.35, 0.35, 0.37))
			return im
		"furnace_front":
			var im := _noise(Color(0.48, 0.48, 0.5), 0.04)
			for y in range(8, 14):
				for x in range(3, 13):
					im.set_pixel(x, y, Color(0.1, 0.08, 0.08))
			for x in range(4, 12):
				im.set_pixel(x, 13, _v(Color(1.0, 0.55, 0.1), 0.1))
				if _rng.randf() < 0.6:
					im.set_pixel(x, 12, _v(Color(1.0, 0.8, 0.2), 0.1))
			for x in range(3, 13):
				im.set_pixel(x, 4, Color(0.3, 0.3, 0.32))
			return im
		"torch":
			var im := _img()
			for y in range(6, 16):
				im.set_pixel(7, y, Color(0.45, 0.32, 0.18))
				im.set_pixel(8, y, Color(0.35, 0.24, 0.12))
			im.set_pixel(7, 5, Color(1, 0.85, 0.3))
			im.set_pixel(8, 5, Color(1, 0.7, 0.2))
			im.set_pixel(7, 4, Color(1, 0.95, 0.6))
			im.set_pixel(8, 4, Color(1, 0.6, 0.15))
			im.set_pixel(7, 3, Color(1, 0.8, 0.3))
			return im
		"glass":
			var im := _img()
			for i in 16:
				for p in [Vector2i(i, 0), Vector2i(i, 15), Vector2i(0, i), Vector2i(15, i)]:
					im.set_pixel(p.x, p.y, Color(0.85, 0.93, 0.97))
			for k in 4:
				im.set_pixel(3 + k, 6 - k, Color(1, 1, 1, 0.9))
				im.set_pixel(9 + k, 12 - k, Color(1, 1, 1, 0.9))
			return im
		"stone_bricks":
			return _bricks(Color(0.55, 0.55, 0.57), Color(0.36, 0.36, 0.38), 8, 8)
		"bricks":
			return _bricks(Color(0.66, 0.3, 0.24), Color(0.75, 0.72, 0.68), 8, 4)
		"iron_block":
			return _metal(Color(0.85, 0.85, 0.87))
		"gold_block":
			return _metal(Color(0.98, 0.82, 0.25))
		"diamond_block":
			return _metal(Color(0.4, 0.92, 0.9))
		"lamp":
			var im := _noise(Color(1.0, 0.85, 0.45), 0.06)
			_specks(im, Color(1, 1, 0.8), 20)
			for i in 16:
				for p in [Vector2i(i, 0), Vector2i(i, 15), Vector2i(0, i), Vector2i(15, i)]:
					im.set_pixel(p.x, p.y, Color(0.55, 0.4, 0.2))
			return im
		"tnt_side":
			var im := _noise(Color(0.82, 0.2, 0.15), 0.04)
			for y in range(5, 11):
				for x in 16:
					im.set_pixel(x, y, Color(0.93, 0.93, 0.9))
			var letters := ["###.#..#.###", ".#..##.#..#.", ".#..#.##..#.", ".#..#..#..#."]
			for row in letters.size():
				for col in letters[row].length():
					if letters[row][col] == "#":
						im.set_pixel(2 + col, 6 + row, Color(0.1, 0.1, 0.1))
			return im
		"tnt_top":
			var im := _noise(Color(0.8, 0.22, 0.16), 0.04)
			for p in [Vector2i(7, 7), Vector2i(8, 7), Vector2i(7, 8), Vector2i(8, 8)]:
				im.set_pixel(p.x, p.y, Color(0.2, 0.2, 0.2))
			return im
		"tnt_bottom":
			return _noise(Color(0.7, 0.18, 0.13), 0.04)
		"farmland":
			var im := _noise(Color(0.36, 0.24, 0.14), 0.04)
			for y in 16:
				if y % 4 == 1:
					for x in 16:
						im.set_pixel(x, y, Color(0.24, 0.15, 0.08))
			return im
		"wheat_0", "wheat_1", "wheat_2", "wheat_3":
			var s := int(n.substr(6))
			var im := _img()
			var col := Color(0.35, 0.65, 0.2).lerp(Color(0.86, 0.72, 0.28), s / 3.0)
			var top := 15 - (4 + s * 3)
			for k in 5:
				var x := 1 + k * 3
				for y in range(top + (k % 2), 16):
					im.set_pixel(x, y, _v(col, 0.06))
				if s == 3:
					for y in range(top, top + 4):
						im.set_pixel(mini(x + 1, 15), y, Color(0.95, 0.8, 0.35))
			return im
		"portal_top", "portal_side":
			var im := _noise(Color(0.09, 0.05, 0.14), 0.03)
			for y in range(3, 13):
				for x in range(3, 13):
					im.set_pixel(x, y, _v(Color(1.0, 0.38, 0.08), 0.12))
			return im
		"ember_core":
			var im := _metal(Color(0.55, 0.2, 0.12))
			_blob(im, 8, 8, 3.5, 3.5, Color(1.0, 0.55, 0.15))
			return im
		"emberite_ore":
			var im := _noise(Color(0.26, 0.26, 0.28), 0.03)
			_specks(im, Color(1.0, 0.45, 0.1), 22, 0.08)
			return im
		"tall_grass":
			return _cross_plant(Color(0.3, 0.58, 0.2), Color(0.45, 0.72, 0.3), false)
		"flower_red":
			return _cross_plant(Color(0.25, 0.55, 0.18), Color(0.92, 0.16, 0.18), true)
		"flower_yellow":
			return _cross_plant(Color(0.25, 0.55, 0.18), Color(1.0, 0.85, 0.15), true)
		"dead_bush":
			return _cross_plant(Color(0.5, 0.36, 0.2), Color(0.6, 0.45, 0.25), false)
	if n.begins_with("wool_"):
		var cols := {"white": Color(0.92, 0.92, 0.92), "red": Color(0.75, 0.18, 0.16), "orange": Color(0.92, 0.5, 0.12),
			"yellow": Color(0.95, 0.82, 0.2), "green": Color(0.3, 0.55, 0.15), "blue": Color(0.2, 0.3, 0.75),
			"purple": Color(0.5, 0.22, 0.7), "black": Color(0.12, 0.12, 0.14)}
		var base: Color = cols.get(n.substr(5), Color.WHITE)
		var im := _noise(base, 0.035)
		for y in 16:
			for x in 16:
				if (x + y * 3) % 7 == 0:
					im.set_pixel(x, y, base.darkened(0.12))
		return im
	return _noise(Color(1, 0, 1), 0.1)


func _crack(stage: int) -> Image:
	var im := _img()
	im.fill(Color(1, 1, 1, 1))
	_rng.seed = 1234
	var steps := (stage + 1) * 7
	var walkers := [Vector2(8, 8), Vector2(8, 8), Vector2(8, 8), Vector2(8, 8)]
	var dirs := [Vector2(1, 0.4), Vector2(-1, -0.3), Vector2(0.3, 1), Vector2(-0.4, -1)]
	for s in steps:
		var w := s % 4
		var p: Vector2 = walkers[w]
		var d: Vector2 = dirs[w]
		d = (d + Vector2(_rng.randf_range(-0.7, 0.7), _rng.randf_range(-0.7, 0.7))).normalized()
		dirs[w] = d
		p += d
		p = p.clamp(Vector2(0, 0), Vector2(15, 15))
		walkers[w] = p
		im.set_pixel(int(p.x), int(p.y), Color(0.25, 0.25, 0.25))
	return im


func _make_hearts() -> void:
	var shape := [
		"..##...##..",
		".####.####.",
		"###########",
		"###########",
		".#########.",
		"..#######..",
		"...#####...",
		"....###....",
		".....#.....",
	]
	var full := Image.create(11, 9, false, Image.FORMAT_RGBA8)
	var half := Image.create(11, 9, false, Image.FORMAT_RGBA8)
	var empty := Image.create(11, 9, false, Image.FORMAT_RGBA8)
	for y in 9:
		for x in 11:
			if shape[y][x] == "#":
				var edge: bool = (x == 0 or x == 10 or y == 8 or shape[y][x - 1] != "#" or shape[y][x + 1] != "#" or (y > 0 and shape[y - 1][x] != "#") or (y < 8 and shape[y + 1][x] != "#"))
				var red := Color(0.9, 0.1, 0.15) if not (y == 2 and x in [2, 3]) else Color(1, 0.7, 0.7)
				var dark := Color(0.22, 0.05, 0.06)
				full.set_pixel(x, y, dark if edge else red)
				half.set_pixel(x, y, dark if edge else (red if x < 5 else Color(0.25, 0.12, 0.12)))
				empty.set_pixel(x, y, dark if edge else Color(0.25, 0.12, 0.12))
	heart_full = ImageTexture.create_from_image(_scale(full, 3))
	heart_half = ImageTexture.create_from_image(_scale(half, 3))
	heart_empty = ImageTexture.create_from_image(_scale(empty, 3))


## HUD armor points: a small chestplate per 2 points (full / half / empty), like the hearts.
func _make_armor_icons() -> void:
	var shape := [".##...##.", "####.####", "#########", ".#######.", ".#######.", ".#######.", ".###.###."]
	var ims: Array[Image] = []
	for k in 3:
		var im := Image.create(9, 7, false, Image.FORMAT_RGBA8)
		for y in 7:
			for x in 9:
				if shape[y][x] != "#":
					continue
				var edge: bool = x == 0 or x == 8 or y == 6 or shape[y][x - 1] != "#" or shape[y][x + 1] != "#" or (y > 0 and shape[y - 1][x] != "#") or (y < 6 and shape[y + 1][x] != "#")
				var filled := k == 0 or (k == 1 and x < 4)
				var c := Color(0.86, 0.87, 0.92) if filled else Color(0.2, 0.21, 0.25)
				if filled and y == 2 and x in [2, 3]:
					c = Color(1, 1, 1)
				im.set_pixel(x, y, Color(0.08, 0.08, 0.1) if edge else c)
		ims.append(_scale(im, 3))
	armor_full = ImageTexture.create_from_image(ims[0])
	armor_half = ImageTexture.create_from_image(ims[1])
	armor_empty = ImageTexture.create_from_image(ims[2])


func _scale(im: Image, s: int) -> Image:
	var o := im.duplicate()
	o.resize(im.get_width() * s, im.get_height() * s, Image.INTERPOLATE_NEAREST)
	return o


# ---------------- icons ----------------

func icon(id: int) -> Texture2D:
	if icons.has(id):
		return icons[id]
	var im: Image
	if B.is_block(id):
		var r := B.RENDER[id]
		if r == B.R_CROSS or r == B.R_TORCH:
			im = _scale(images[B.texture_names[B.TEX_SIDE[id]]], 2)
		else:
			im = _iso(id)
	else:
		im = _scale(_item_img(id), 2)
	var tex := ImageTexture.create_from_image(im)
	icons[id] = tex
	return tex


## 16x16 pixel art for anything that is held flat (tools, items, plants, torches).
func item_image(id: int) -> Image:
	if B.is_block(id):
		return images[B.texture_names[B.TEX_SIDE[id]]]
	return _item_img(id, false)


func _iso(id: int) -> Image:
	var top: Image = images[B.texture_names[B.TEX_TOP[id]]]
	var side: Image = images[B.texture_names[B.TEX_SIDE[id]]]
	var im := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for py in 32:
		for px in 32:
			var x := px + 0.5
			var y := py + 0.5
			var dx := x - 16.0
			var s := (y / 8.0 + dx / 15.0) * 0.5
			var t := (y / 8.0 - dx / 15.0) * 0.5
			var c := Color(0, 0, 0, 0)
			if s >= 0 and s <= 1 and t >= 0 and t <= 1:
				c = top.get_pixel(clampi(int(s * 16), 0, 15), clampi(int(t * 16), 0, 15))
			else:
				var ls := (x - 1.0) / 15.0
				var lt := (y - 8.0 - 8.0 * ls) / 15.0
				if ls >= 0 and ls <= 1 and lt >= 0 and lt <= 1:
					c = side.get_pixel(clampi(int(ls * 16), 0, 15), clampi(int(lt * 16), 0, 15))
					c = Color(c.r * 0.78, c.g * 0.78, c.b * 0.78, c.a)
				else:
					var rs := (x - 16.0) / 15.0
					var rt := (y - 16.0 + 8.0 * rs) / 15.0
					if rs >= 0 and rs <= 1 and rt >= 0 and rt <= 1:
						c = side.get_pixel(clampi(int(rs * 16), 0, 15), clampi(int(rt * 16), 0, 15))
						c = Color(c.r * 0.6, c.g * 0.6, c.b * 0.6, c.a)
			if c.a < 0.5:
				c = Color(0, 0, 0, 0)
			elif B.RENDER[id] == B.R_WATER:
				c.a = 0.85
			im.set_pixel(px, py, c)
	return im


func _line(im: Image, r0: float, c0: float, r1: float, c1: float, col: Color, thick := 0.6) -> void:
	for y in 16:
		for x in 16:
			var p := Vector2(x + 0.5, y + 0.5)
			var a := Vector2(c0 + 0.5, r0 + 0.5)
			var b := Vector2(c1 + 0.5, r1 + 0.5)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0, 1) if ab.length_squared() > 0.0001 else 0.0
			if p.distance_to(a + ab * t) <= thick:
				im.set_pixel(x, y, col)


func _blob(im: Image, cr: float, cc: float, rr: float, rc: float, col: Color, shade := true) -> void:
	for y in 16:
		for x in 16:
			var dy := (y + 0.5 - cr) / rr
			var dx := (x + 0.5 - cc) / rc
			var d := dx * dx + dy * dy
			if d <= 1.0:
				var c := col
				if shade:
					if dx + dy < -0.6:
						c = col.lightened(0.3)
					elif dx + dy > 0.7:
						c = col.darkened(0.3)
				im.set_pixel(x, y, c)


## Draws '#' rows centred vertically, lit along top edges and shaded along bottom edges.
func _pattern(im: Image, rows: Array, col: Color) -> void:
	var y0 := (16 - rows.size()) / 2
	for r in rows.size():
		var row: String = rows[r]
		for x in 16:
			if row[x] != "#":
				continue
			var c := col
			if r == 0 or rows[r - 1][x] != "#" or x == 0 or row[x - 1] != "#":
				c = col.lightened(0.3)
			elif r == rows.size() - 1 or rows[r + 1][x] != "#" or x == 15 or row[x + 1] != "#":
				c = col.darkened(0.3)
			im.set_pixel(x, y0 + r, c)


func _outline(im: Image) -> void:
	var src := im.duplicate()
	for y in 16:
		for x in 16:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and nx < 16 and ny >= 0 and ny < 16 and src.get_pixel(nx, ny).a > 0.5:
					im.set_pixel(x, y, Color(0.08, 0.06, 0.06, 1))
					break


func _item_img(id: int, outline := true) -> Image:
	var im := _img()
	var stick := Color(0.55, 0.38, 0.2)
	if id >= B.WOOD_PICK and id <= B.DIAMOND_SWORD:
		var tier := (id - B.WOOD_PICK) % 4
		var kind := (id - B.WOOD_PICK) / 4
		var col: Color = B.MAT_COLORS[tier]
		match kind:
			0:
				_line(im, 14, 1, 5, 10, stick, 0.75)
				for k in 13:
					var th := deg_to_rad(8.0 + k * 6.3)
					var r := 13.0 - 11.0 * sin(th)
					var c := 2.0 + 11.0 * cos(th)
					_line(im, r, c, r, c, col.lightened(0.15) if k % 3 == 0 else col, 0.95)
			1:
				_line(im, 14, 1, 3, 12, stick, 0.75)
				_blob(im, 4.5, 8.0, 3.6, 2.6, col)
				_line(im, 1.5, 9, 7, 3.5, col.lightened(0.25), 0.6)
			2:
				_line(im, 14, 1, 5, 10, stick, 0.75)
				_blob(im, 3.6, 12.4, 3.2, 3.2, col)
			3:
				_line(im, 13, 2, 2, 13, col, 1.1)
				_line(im, 12.5, 2.5, 2.5, 12.5, col.lightened(0.35), 0.4)
				_line(im, 9, 3, 13, 7, col.darkened(0.25), 0.8)
				_line(im, 15, 0, 12, 3, stick, 0.8)
		if outline:
			_outline(im)
		return im
	match id:
		B.STICK:
			_line(im, 14, 2, 2, 13, stick, 0.8)
			_line(im, 13.5, 2.5, 2.5, 13.5, stick.lightened(0.2), 0.3)
		B.COAL:
			_blob(im, 8.5, 8, 5.5, 6, Color(0.18, 0.18, 0.2))
			_specks(im, Color(0.35, 0.35, 0.4), 0)
		B.IRON_INGOT, B.GOLD_INGOT:
			var col := Color(0.85, 0.85, 0.88) if id == B.IRON_INGOT else Color(1.0, 0.82, 0.22)
			for y in range(5, 12):
				var inset := (y - 5) / 3
				for x in range(2 + 2 - inset, 14 - 2 + inset):
					im.set_pixel(x, y, col if y > 6 else col.lightened(0.35))
			for x in range(2, 14):
				im.set_pixel(x, 11, col.darkened(0.3))
		B.DIAMOND, B.STARCORE:
			var col := Color(0.4, 0.95, 0.92) if id == B.DIAMOND else Color(0.95, 0.35, 1.0)
			for y in 16:
				for x in 16:
					var d := absf(x - 7.5) + absf(y - 8.5) * 0.85
					if d < 6.5:
						im.set_pixel(x, y, col.lightened(0.4) if (x < 7 and y < 8) else (col if d < 4.5 else col.darkened(0.25)))
		B.RAW_MEAT, B.COOKED_MEAT:
			var col := Color(0.9, 0.35, 0.35) if id == B.RAW_MEAT else Color(0.55, 0.3, 0.15)
			_blob(im, 8, 7.5, 5, 6.5, col)
			_line(im, 4, 12, 3, 14, Color(0.95, 0.92, 0.85), 1.0)
			_blob(im, 8, 7, 1.6, 2.5, col.lightened(0.35), false)
		B.GUNPOWDER:
			for i in 40:
				var r := _rng.randf_range(5, 14)
				var c := _rng.randf_range(8 - (r - 5) * 0.7, 8 + (r - 5) * 0.7)
				im.set_pixel(clampi(int(c), 0, 15), clampi(int(r), 0, 15), _v(Color(0.35, 0.35, 0.37), 0.1))
		B.APPLE:
			_blob(im, 9, 8, 5.5, 5.5, Color(0.85, 0.12, 0.12))
			_line(im, 2, 8, 4, 8, Color(0.4, 0.25, 0.1), 0.6)
			_blob(im, 3, 10, 1.2, 2, Color(0.3, 0.65, 0.2), false)
		B.ROCKET_HULL:
			for y in range(2, 15):
				for x in range(4, 12):
					var c := Color(0.85, 0.86, 0.9) if x > 5 else Color(1, 1, 1)
					if x == 11:
						c = Color(0.6, 0.6, 0.65)
					im.set_pixel(x, y, c)
			_blob(im, 7, 8, 2, 2, Color(0.3, 0.7, 1.0))
		B.ROCKET_ENGINE:
			for y in range(2, 9):
				for x in range(5, 11):
					im.set_pixel(x, y, Color(0.4, 0.4, 0.45))
			for y in range(9, 14):
				var w := (y - 9) / 2 + 3
				for x in range(8 - w, 8 + w):
					im.set_pixel(x, y, Color(0.3, 0.3, 0.33))
			for x in range(4, 12):
				im.set_pixel(x, 14, Color(1.0, 0.6, 0.15))
		B.FUEL_CELL:
			for y in range(3, 15):
				for x in range(4, 12):
					im.set_pixel(x, y, Color(0.25, 0.75, 0.3) if x > 4 else Color(0.5, 0.9, 0.5))
			for x in range(6, 10):
				im.set_pixel(x, 2, Color(0.6, 0.6, 0.6))
			for y in range(6, 12):
				im.set_pixel(8, y, Color(0.95, 0.4, 1.0))
		B.NAV_CORE:
			for y in range(3, 13):
				for x in range(3, 13):
					im.set_pixel(x, y, Color(0.15, 0.25, 0.4))
			for k in 4:
				im.set_pixel(1, 4 + k * 2, Color(0.9, 0.8, 0.3))
				im.set_pixel(14, 4 + k * 2, Color(0.9, 0.8, 0.3))
			_blob(im, 8, 8, 2.5, 2.5, Color(0.4, 0.95, 0.92))
		B.ROCKET:
			for y in range(4, 13):
				for x in range(6, 10):
					im.set_pixel(x, y, Color(0.95, 0.95, 0.97))
			for y in range(1, 4):
				for x in range(7 - (y - 1) / 2, 9 + (y - 1) / 2):
					im.set_pixel(x, y, Color(0.9, 0.15, 0.15))
			for p in [Vector2i(5, 11), Vector2i(4, 12), Vector2i(5, 12), Vector2i(10, 11), Vector2i(11, 12), Vector2i(10, 12)]:
				im.set_pixel(p.x, p.y, Color(0.9, 0.15, 0.15))
			im.set_pixel(7, 7, Color(0.3, 0.7, 1.0))
			im.set_pixel(8, 7, Color(0.3, 0.7, 1.0))
			for x in range(6, 10):
				im.set_pixel(x, 13, Color(1, 0.7, 0.2))
				im.set_pixel(x, 14, Color(1, 0.4, 0.1) if x % 2 == 0 else Color(0, 0, 0, 0))
		B.BUCKET, B.WATER_BUCKET, B.LAVA_BUCKET:
			var iron := Color(0.78, 0.79, 0.83)
			for y in range(4, 15):
				var w := 5.5 - (y - 4) * 0.2
				for x in range(roundi(8.0 - w), roundi(8.0 + w)):
					var c := iron
					if x <= roundi(8.0 - w) + 1:
						c = iron.lightened(0.25)
					elif x >= roundi(8.0 + w) - 2:
						c = iron.darkened(0.3)
					im.set_pixel(x, y, c)
			for x in range(3, 13):
				im.set_pixel(x, 4, iron.lightened(0.35))
			var inner := Color(0.22, 0.22, 0.26)
			if id == B.WATER_BUCKET:
				inner = Color(0.2, 0.42, 0.95)
			elif id == B.LAVA_BUCKET:
				inner = Color(1.0, 0.5, 0.1)
			for x in range(4, 12):
				im.set_pixel(x, 5, inner.lightened(0.15) if x < 7 else inner)
				im.set_pixel(x, 6, inner.darkened(0.2))
			_line(im, 4, 3, 1, 6, iron.darkened(0.45), 0.5)
			_line(im, 1, 6, 1, 9, iron.darkened(0.45), 0.5)
			_line(im, 1, 9, 4, 12, iron.darkened(0.45), 0.5)
		B.SHIELD:
			var wood := Color(0.62, 0.44, 0.24)
			var rim := Color(0.62, 0.63, 0.68)
			for y in range(1, 15):
				var inset := maxi(0, y - 10)
				for x in range(3 + inset, 13 - inset):
					var edge := y == 1 or y == 14 or x == 3 + inset or x == 12 - inset
					var c := wood if x % 3 != 0 else wood.darkened(0.25)
					im.set_pixel(x, y, rim if edge else c)
			for p in [Vector2i(7, 6), Vector2i(8, 6), Vector2i(7, 7), Vector2i(8, 7)]:
				im.set_pixel(p.x, p.y, rim.lightened(0.3))
			for p in [Vector2i(6, 6), Vector2i(9, 7), Vector2i(7, 8), Vector2i(8, 5)]:
				im.set_pixel(p.x, p.y, rim.darkened(0.2))
		B.SEEDS:
			for p in [Vector2i(5, 7), Vector2i(9, 5), Vector2i(7, 10), Vector2i(11, 9), Vector2i(4, 11), Vector2i(10, 12)]:
				_blob(im, p.y, p.x, 1.0, 0.8, Color(0.45, 0.6, 0.2))
		B.WHEAT:
			for k in 3:
				_line(im, 15, 6 + k * 2, 2, 4 + k * 3, Color(0.85, 0.7, 0.28), 0.6)
			_blob(im, 4, 7, 2.5, 3.5, Color(0.95, 0.8, 0.35))
		B.BREAD:
			_blob(im, 9, 8, 4, 6.5, Color(0.72, 0.45, 0.2))
			for x in [5, 8, 11]:
				_line(im, 7, x, 9, x + 1, Color(0.9, 0.7, 0.4), 0.4)
		B.HOE:
			_line(im, 14, 1, 3, 12, stick, 0.75)
			_line(im, 3, 9, 3, 14, Color(0.6, 0.6, 0.62), 0.9)
		B.BOW:
			for k in 12:
				var th := deg_to_rad(-80.0 + k * 14.5)
				_line(im, 8 - 7 * sin(th), 3 + 6 * cos(th), 8 - 7 * sin(th), 3 + 6 * cos(th), stick, 0.9)
			_line(im, 1, 4, 15, 4, Color(0.9, 0.9, 0.9), 0.3)
		B.ARROW:
			_line(im, 14, 1, 2, 13, stick, 0.5)
			_blob(im, 2.5, 12.5, 1.6, 1.6, Color(0.3, 0.3, 0.33))
			_line(im, 12, 1, 15, 4, Color(0.95, 0.95, 0.95), 0.7)
		B.FLINT:
			_blob(im, 9, 8, 5, 4, Color(0.2, 0.2, 0.23))
			_blob(im, 7, 7, 1.5, 1.5, Color(0.4, 0.4, 0.45), false)
		B.FLINT_AND_STEEL:
			_blob(im, 10, 5, 3.5, 3, Color(0.2, 0.2, 0.23))
			_line(im, 4, 8, 12, 12, Color(0.78, 0.79, 0.83), 0.8)
			_line(im, 4, 8, 4, 13, Color(0.78, 0.79, 0.83), 0.8)
		B.EMBERITE:
			_blob(im, 8.5, 8, 5, 5, Color(1.0, 0.45, 0.12))
			_blob(im, 7, 6.5, 1.8, 1.8, Color(1.0, 0.8, 0.4), false)
		_ when B.armor_slot(id) >= 0:
			var col: Color = B.MAT_COLORS[2] if id < B.DIAMOND_HELMET else B.MAT_COLORS[3]
			_pattern(im, ARMOR_SHAPES[B.armor_slot(id)], col)
	if outline:
		_outline(im)
	return im
