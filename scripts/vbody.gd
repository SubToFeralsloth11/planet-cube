class_name VBody
extends RefCounted
## Axis-aligned voxel physics body whose gravity points at the planet face it stands on.

const UPS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
const CENTER := Vector3(64, 64, 64)
const EPS := 0.001

var world
var pos := Vector3.ZERO  # feet
var vel := Vector3.ZERO
var face := 2
var frame := Basis.IDENTITY
var hw := 0.3
var h := 1.8
var gravity := 28.0
var on_ground := false
var hit_wall := false
var in_water := false
var in_lava := false
var land_speed := 0.0
var flying := false
var noclip := false


func _init(w, half_width := 0.3, height := 1.8) -> void:
	world = w
	hw = half_width
	h = height


func up() -> Vector3:
	return UPS[face]


func set_face(f: int) -> void:
	face = f
	var u: Vector3 = UPS[f]
	var fwd := Vector3(0, 0, -1) if absf(u.z) < 0.9 else Vector3(1, 0, 0)
	fwd = (fwd - u * fwd.dot(u)).normalized()
	var right := fwd.cross(u).normalized()
	frame = Basis(right, u, -fwd).orthonormalized()


func _bounds(p: Vector3, f: int) -> Array:
	var mn := p - Vector3(hw, hw, hw)
	var mx := p + Vector3(hw, hw, hw)
	var a := f >> 1
	if (f & 1) == 0:
		mn[a] = p[a]
		mx[a] = p[a] + h
	else:
		mn[a] = p[a] - h
		mx[a] = p[a]
	return [mn, mx]


func aabb() -> AABB:
	var b := _bounds(pos, face)
	return AABB(b[0], b[1] - b[0])


func center() -> Vector3:
	return pos + up() * (h * 0.5)


func collides_at(p: Vector3, f: int) -> bool:
	var b := _bounds(p, f)
	var mn: Vector3 = b[0]
	var mx: Vector3 = b[1]
	for z in range(floori(mn.z + EPS), floori(mx.z - EPS) + 1):
		for y in range(floori(mn.y + EPS), floori(mx.y - EPS) + 1):
			for x in range(floori(mn.x + EPS), floori(mx.x - EPS) + 1):
				if world.solid(x, y, z):
					return true
	return false


func _touch_kind(id: int) -> bool:
	var b := _bounds(pos, face)
	var mn: Vector3 = b[0]
	var mx: Vector3 = b[1]
	for z in range(floori(mn.z + EPS), floori(mx.z - EPS) + 1):
		for y in range(floori(mn.y + EPS), floori(mx.y - EPS) + 1):
			for x in range(floori(mn.x + EPS), floori(mx.x - EPS) + 1):
				if world.get_b(x, y, z) == id:
					return true
	return false


## Re-evaluates which face is "down". Returns the rotation applied (identity if none).
func update_gravity() -> Quaternion:
	var c := center() - CENTER
	var a := face >> 1
	var cur := absf(c[a])
	var best := -1
	var best_v := cur + 0.45
	for k in 3:
		if k == a:
			continue
		if absf(c[k]) > best_v:
			best_v = absf(c[k])
			best = k * 2 + (0 if c[k] > 0 else 1)
	var cur_sign_ok := (c[a] >= 0) == ((face & 1) == 0)
	if best < 0 and not cur_sign_ok and absf(c[a]) > 0.45:
		best = a * 2 + (0 if c[a] > 0 else 1)
	if best < 0:
		return Quaternion.IDENTITY
	var new_up: Vector3 = UPS[best]
	var old_up := up()
	var p := pos
	if collides_at(p, best):
		p = center() - new_up * (h * 0.5)
		if collides_at(p, best):
			return Quaternion.IDENTITY
	var q: Quaternion
	if old_up.dot(new_up) < -0.5:
		q = Quaternion(frame.x, PI)
	else:
		q = Quaternion(old_up, new_up)
	frame = (Basis(q) * frame).orthonormalized()
	face = best
	pos = p
	var vu := vel.dot(new_up)
	if vu > 2.0:
		vel -= new_up * (vu - 2.0)
	return q


func step(dt: float) -> void:
	var u := up()
	in_water = _touch_kind(B.WATER)
	in_lava = _touch_kind(B.LAVA)
	if not flying:
		var g := gravity
		if in_water or in_lava:
			g *= 0.3
			vel *= maxf(0.0, 1.0 - 2.5 * dt)
		vel -= u * g * dt
		var vd := vel.dot(u)
		if vd < -55.0:
			vel -= u * (vd + 55.0)
	on_ground = false
	hit_wall = false
	land_speed = 0.0
	if noclip:
		pos += vel * dt
		return
	var move := vel * dt
	var n := maxi(1, ceili(move.length() / 0.4))
	var part := move / n
	for s in n:
		for ax in 3:
			if part[ax] != 0.0:
				_move_axis(ax, part[ax])
	if not on_ground and not flying and vel.dot(u) <= 0.01 and collides_at(pos - u * 0.02, face):
		on_ground = true


func _move_axis(ax: int, d: float) -> void:
	pos[ax] += d
	var b := _bounds(pos, face)
	var mn: Vector3 = b[0]
	var mx: Vector3 = b[1]
	var hit := false
	for z in range(floori(mn.z + EPS), floori(mx.z - EPS) + 1):
		for y in range(floori(mn.y + EPS), floori(mx.y - EPS) + 1):
			for x in range(floori(mn.x + EPS), floori(mx.x - EPS) + 1):
				if world.solid(x, y, z):
					hit = true
					break
			if hit:
				break
		if hit:
			break
	if not hit:
		return
	if d > 0:
		pos[ax] -= mx[ax] - floorf(mx[ax] - EPS) + EPS if fposmod(mx[ax], 1.0) > EPS else d
	else:
		pos[ax] += ceilf(mn[ax] + EPS) - mn[ax] + EPS if fposmod(mn[ax], 1.0) < 1.0 - EPS else -d
	var a := face >> 1
	var u := up()
	if ax == a:
		var vu := vel.dot(u)
		if (d < 0) == (u[ax] > 0):
			on_ground = true
			land_speed = -vu
		vel[ax] = 0.0
	else:
		hit_wall = true
		vel[ax] = 0.0
