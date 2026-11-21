extends Node
## Procedurally synthesized sound effects and ambient music (autoload "Sfx").

const RATE := 22050

var streams := {}
var players: Array[AudioStreamPlayer] = []
var players3d: Array[AudioStreamPlayer3D] = []
var music_player: AudioStreamPlayer
var music_on := true
var _next := 0
var _next3 := 0
var _music_task := -1
var _music_data := PackedByteArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	for i in 10:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 40.0
		p.unit_size = 6.0
		add_child(p)
		players3d.append(p)
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -14.0
	add_child(music_player)
	_make_all()
	_music_task = WorkerThreadPool.add_task(_gen_music)


func _process(_dt: float) -> void:
	if _music_task >= 0 and WorkerThreadPool.is_task_completed(_music_task):
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
		var s := _wav(_music_data)
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = _music_data.size() / 2
		streams["music"] = s
		if music_on:
			music_player.stream = s
			music_player.play()


func _exit_tree() -> void:
	if _music_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1


func toggle_music() -> bool:
	music_on = not music_on
	if music_on and streams.has("music"):
		music_player.stream = streams["music"]
		music_player.play()
	else:
		music_player.stop()
	return music_on


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _pack(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size() * 2)
	for i in samples.size():
		out.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	return out


func _add(name: String, samples: PackedFloat32Array) -> void:
	streams[name] = _wav(_pack(samples))


func _noise_burst(len_s: float, decay: float, lp: float, tone := 0.0, tone_amt := 0.0, tone_drop := 0.0) -> PackedFloat32Array:
	var n := int(len_s * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * decay) * minf(1.0, t * 400.0)
		y += (randf_range(-1, 1) - y) * lp
		var s := y
		if tone > 0.0:
			ph += TAU * maxf(20.0, tone - tone_drop * t) / RATE
			s = s * (1.0 - tone_amt) + sin(ph) * tone_amt
		out[i] = s * env
	return out


func _tone(len_s: float, f0: float, f1: float, decay: float, shape := 0) -> PackedFloat32Array:
	var n := int(len_s * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / len_s)
		ph += TAU * f / RATE
		var s := sin(ph)
		if shape == 1:
			s = signf(s) * 0.6
		elif shape == 2:
			s = fmod(ph / TAU, 1.0) * 2.0 - 1.0
		out[i] = s * exp(-t * decay) * minf(1.0, t * 200.0)
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gb := 1.0) -> PackedFloat32Array:
	var out := a.duplicate()
	if b.size() > out.size():
		out.resize(b.size())
	for i in b.size():
		out[i] += b[i] * gb
	return out


func _make_all() -> void:
	_add("dig_stone", _noise_burst(0.16, 28.0, 0.55, 300.0, 0.15, 400.0))
	_add("place", _noise_burst(0.12, 35.0, 0.2, 120.0, 0.5, 60.0))
	_add("dig_dirt", _noise_burst(0.18, 24.0, 0.18))
	_add("dig_grass", _noise_burst(0.16, 26.0, 0.32))
	_add("dig_sand", _noise_burst(0.2, 20.0, 0.25))
	_add("dig_wood", _noise_burst(0.16, 30.0, 0.3, 170.0, 0.5, 120.0))
	_add("dig_glass", _mix(_noise_burst(0.25, 18.0, 0.9), _tone(0.3, 2400.0, 2300.0, 14.0), 0.35))
	_add("step", _noise_burst(0.09, 45.0, 0.22))
	_add("hit", _noise_burst(0.14, 30.0, 0.4, 110.0, 0.6, 200.0))
	_add("hurt", _tone(0.28, 420.0, 190.0, 9.0, 1))
	_add("pop", _tone(0.09, 650.0, 1300.0, 25.0))
	_add("eat", _noise_burst(0.35, 9.0, 0.35, 220.0, 0.2, 0.0))
	_add("craft", _mix(_tone(0.45, 660.0, 660.0, 8.0), _tone(0.45, 990.0, 990.0, 9.0), 0.6))
	_add("click", _tone(0.05, 900.0, 700.0, 60.0))
	var arp := PackedFloat32Array()
	for k in 4:
		var f: float = [523.25, 659.25, 783.99, 1046.5][k]
		arp.append_array(_tone(0.12, f, f, 6.0))
	arp = _mix(arp, _tone(0.9, 1046.5, 1046.5, 3.5), 0.5)
	_add("objective", arp)
	var boom := _noise_burst(1.4, 3.2, 0.08, 55.0, 0.45, 25.0)
	_add("explode", boom)
	_add("fuse", _noise_burst(1.4, 0.6, 0.95))
	_add("roar", _mix(_tone(1.6, 90.0, 55.0, 1.6, 2), _noise_burst(1.6, 1.8, 0.12), 0.7))
	_add("charge", _tone(0.9, 120.0, 700.0, 0.8, 2))
	_add("bolt", _mix(_noise_burst(0.35, 8.0, 0.5), _tone(0.35, 500.0, 160.0, 7.0, 2), 0.4))
	_add("clang", _mix(_tone(0.6, 820.0, 815.0, 7.0), _tone(0.6, 1290.0, 1285.0, 9.0), 0.7))
	_add("launch", _noise_burst(6.0, 0.35, 0.06, 45.0, 0.5, 0.0))
	_add("zombie", _tone(0.7, 130.0, 95.0, 2.5, 2))
	_add("boomer", _noise_burst(0.5, 4.0, 0.9))
	_add("pig", _tone(0.25, 560.0, 380.0, 6.0, 2))
	_add("cow", _tone(0.8, 160.0, 120.0, 2.0, 2))
	_add("sheep", _tone(0.5, 320.0, 300.0, 3.0, 1))
	_add("splash", _noise_burst(0.4, 8.0, 0.7))
	_add("whoosh", _noise_burst(0.5, 5.0, 0.12))


func _gen_music() -> void:
	var secs := 32.0
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var chords := [[261.63, 329.63, 392.0, 493.88], [220.0, 261.63, 329.63, 392.0], [174.61, 220.0, 261.63, 329.63], [196.0, 246.94, 293.66, 392.0]]
	var bar := secs / 4.0
	for c in 4:
		var ch: Array = chords[c]
		var s0 := int(c * bar * RATE)
		var s1 := int((c + 1) * bar * RATE)
		for v in ch.size():
			var f: float = ch[v] * 0.5
			var w := TAU * f / RATE
			for i in range(s0, mini(s1 + int(1.5 * RATE), n)):
				var t := float(i - s0) / RATE
				var env := minf(1.0, t / 2.0) * clampf((bar + 1.5 - t) / 1.5, 0.0, 1.0)
				out[i] += sin(w * i + sin(i * 0.00002 * (v + 1)) * 2.0) * env * 0.055
	var pent := [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t_note := 1.0
	while t_note < secs - 1.0:
		var f: float = pent[rng.randi_range(0, pent.size() - 1)] * 0.5
		var s0 := int(t_note * RATE)
		var w := TAU * f / RATE
		for i in range(s0, mini(s0 + int(1.6 * RATE), n)):
			var t := float(i - s0) / RATE
			out[i] += (sin(w * i) + 0.3 * sin(2.0 * w * i)) * exp(-t * 2.8) * 0.06
		t_note += rng.randf_range(0.6, 2.2)
	_music_data = _pack(out)


func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(name):
		return
	var p := players[_next]
	_next = (_next + 1) % players.size()
	p.stream = streams[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func play3d(name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(name):
		return
	var p := players3d[_next3]
	_next3 = (_next3 + 1) % players3d.size()
	p.stream = streams[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.92, 1.08)
	p.global_position = pos
	p.play()


func dig(sound: String, vol_db := 0.0, pitch := 1.0) -> void:
	var key := "dig_" + (sound if sound != "" else "stone")
	play(key, vol_db, pitch * randf_range(0.88, 1.12))
