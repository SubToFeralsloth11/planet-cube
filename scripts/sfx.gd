extends Node
## Procedurally synthesized sound effects and ambient music (autoload "Sfx").

const RATE := 22050

var streams := {}
var players: Array[AudioStreamPlayer] = []
var players3d: Array[AudioStreamPlayer3D] = []
var music_player: AudioStreamPlayer
var _next := 0
var _next3 := 0
var _music_task := -1
var _music_data := PackedByteArray()
var _lowpass: AudioEffectLowPassFilter
var _muffle := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	for i in 10:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 40.0
		p.unit_size = 6.0
		p.bus = "SFX"
		add_child(p)
		players3d.append(p)
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -12.0
	music_player.bus = "Music"
	add_child(music_player)
	_make_all()
	_music_task = WorkerThreadPool.add_task(_gen_music)


func _setup_buses() -> void:
	for nm in ["Music", "SFX"]:
		if AudioServer.get_bus_index(nm) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nm)
			AudioServer.set_bus_send(i, "Master")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0, _lowpass)
	AudioServer.set_bus_effect_enabled(0, 0, false)
	var comp := AudioEffectHardLimiter.new()
	comp.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, comp)


## 0 = clear, 1 = heavily muffled (underwater, paused menus).
func set_muffle(target: float, dt: float) -> void:
	var m := move_toward(_muffle, target, dt * 4.0)
	if m == _muffle:
		return
	var was_on := _muffle > 0.01
	_muffle = m
	if (_muffle > 0.01) != was_on:
		AudioServer.set_bus_effect_enabled(0, 0, _muffle > 0.01)
	_lowpass.cutoff_hz = lerpf(20000.0, 650.0, pow(_muffle, 0.5))


func _process(_dt: float) -> void:
	if _music_task >= 0 and WorkerThreadPool.is_task_completed(_music_task):
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
		var s := _wav(_music_data)
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = _music_data.size() / 2
		streams["music"] = s
		music_player.stream = s
		music_player.play()


func _exit_tree() -> void:
	if _music_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1


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
	_add("swing", _swoosh(0.2, 0.9))
	_add("crit", _mix(_noise_burst(0.18, 22.0, 0.6, 180.0, 0.5, 300.0), _tone(0.35, 1500.0, 1400.0, 12.0), 0.4))
	_add("tick", _tone(0.03, 1800.0, 1500.0, 90.0))
	_add("hover", _tone(0.025, 2600.0, 2400.0, 120.0))
	_add("burp", _mix(_tone(0.32, 210.0, 130.0, 6.0, 2), _noise_burst(0.32, 8.0, 0.15), 0.4))
	_add("deny", _mix(_tone(0.16, 220.0, 200.0, 14.0, 1), _tone(0.16, 233.0, 210.0, 14.0, 1), 0.8))
	_add("open", _mix(_swoosh(0.18, 0.5), _tone(0.12, 500.0, 760.0, 20.0), 0.25))
	_add("close", _mix(_swoosh(0.16, 0.5), _tone(0.12, 700.0, 460.0, 20.0), 0.25))
	var hb := _tone(0.12, 62.0, 48.0, 22.0)
	var beat := hb.duplicate()
	var gap := PackedFloat32Array()
	gap.resize(int(0.16 * RATE))
	beat.append_array(gap)
	beat.append_array(_tone(0.14, 58.0, 44.0, 20.0))
	_add("heartbeat", beat)
	var fan := PackedFloat32Array()
	for k in 5:
		var f: float = [392.0, 523.25, 659.25, 783.99, 1046.5][k]
		fan.append_array(_tone(0.09, f, f, 9.0, 1 if k % 2 == 0 else 0))
	fan = _mix(fan, _mix(_tone(1.3, 523.25, 523.25, 2.6), _mix(_tone(1.3, 659.25, 659.25, 2.8), _tone(1.3, 783.99, 783.99, 3.0), 0.8), 0.8), 0.45)
	_add("mission", fan)
	_add("step_stone", _noise_burst(0.07, 55.0, 0.5, 260.0, 0.12, 300.0))
	_add("step_dirt", _noise_burst(0.09, 45.0, 0.16))
	_add("step_grass", _noise_burst(0.1, 40.0, 0.28))
	_add("step_sand", _noise_burst(0.12, 30.0, 0.35))
	_add("step_wood", _noise_burst(0.08, 50.0, 0.22, 150.0, 0.45, 80.0))
	_add("step_glass", _noise_burst(0.07, 55.0, 0.7, 900.0, 0.15, 200.0))


## Airy whoosh: band-limited noise with a rise-and-fall envelope and a downward filter sweep.
func _swoosh(len_s: float, bright: float) -> PackedFloat32Array:
	var n := int(len_s * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := float(i) / n
		var lp := lerpf(0.35, 0.06, t) * bright
		y += (randf_range(-1, 1) - y) * lp
		y2 += (y - y2) * 0.5
		out[i] = (y - y2 * 0.6) * sin(PI * pow(t, 0.6)) * 1.6
	return out


## 64-second seamless ambient loop: evolving pad, soft plucked bass, pentatonic melody with echo.
## Every voice wraps around the loop point so there is no click when it repeats.
func _gen_music() -> void:
	var secs := 64.0
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var chords := [
		[261.63, 329.63, 392.0, 493.88], [220.0, 261.63, 329.63, 392.0], [174.61, 220.0, 261.63, 329.63], [196.0, 246.94, 293.66, 392.0],
		[261.63, 329.63, 392.0, 587.33], [164.81, 196.0, 246.94, 329.63], [174.61, 220.0, 261.63, 349.23], [196.0, 246.94, 293.66, 349.23],
	]
	var bar := secs / chords.size()
	for c in chords.size():
		var ch: Array = chords[c]
		var s0 := int(c * bar * RATE)
		var len_n := int((bar + 1.8) * RATE)
		for v in ch.size():
			var f: float = ch[v] * 0.5
			var w := TAU * f / RATE
			for k in len_n:
				var t := float(k) / RATE
				var env := minf(1.0, t / 2.2) * clampf((bar + 1.8 - t) / 1.8, 0.0, 1.0)
				var i := (s0 + k) % n
				out[i] += sin(w * k + sin(k * 0.00002 * (v + 1)) * 2.0) * env * 0.05
		# Soft bass pluck on the root, twice per chord.
		var root: float = ch[0] * 0.25
		var wb := TAU * root / RATE
		for hit in 2:
			var b0 := s0 + int(hit * bar * 0.5 * RATE)
			for k in int(2.6 * RATE):
				var t := float(k) / RATE
				out[(b0 + k) % n] += (sin(wb * k) + 0.25 * sin(2.0 * wb * k)) * exp(-t * 1.6) * minf(1.0, t * 60.0) * 0.09
	var pent := [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t_note := 1.0
	var idx := 2
	while t_note < secs - 0.5:
		idx = clampi(idx + rng.randi_range(-2, 2), 0, pent.size() - 1)
		var f: float = pent[idx] * 0.5
		var w := TAU * f / RATE
		var s0 := int(t_note * RATE)
		for echo in 2:
			var e0 := s0 + int(echo * 0.42 * RATE)
			var g: float = 0.06 if echo == 0 else 0.022
			for k in int(1.5 * RATE):
				var t := float(k) / RATE
				out[(e0 + k) % n] += (sin(w * k) + 0.3 * sin(2.0 * w * k)) * exp(-t * 2.6) * minf(1.0, t * 300.0) * g
		t_note += [0.84, 0.84, 1.68, 1.26][rng.randi_range(0, 3)]
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


func step(sound: String, vol_db := 0.0, pitch := 1.0) -> void:
	var key := "step_" + (sound if sound != "" else "stone")
	if not streams.has(key):
		key = "step_stone"
	play(key, vol_db, pitch * randf_range(0.9, 1.1))
