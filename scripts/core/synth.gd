class_name Synth
extends RefCounted
## Every sound in the game, synthesized in code (like the art: no audio
## files). Each generator returns a mono AudioStreamWAV built from noise,
## oscillators and envelopes. Called lazily and cached by Sfx, so the cost
## is spread out and only paid for sounds that are actually heard.

const RATE := 16000


static func make(name: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = name.hash()
	var s := PackedFloat32Array()
	var loop := false
	match name:
		"pistol", "rifle", "shotgun":
			var len := {"pistol": 0.35, "rifle": 0.6, "shotgun": 0.7}[name] as float
			var thump := {"pistol": 140.0, "rifle": 90.0, "shotgun": 70.0}[name] as float
			s = _buf(len)
			var lp := 0.0
			for i in s.size():
				var t := float(i) / RATE
				var n := rng.randf_range(-1.0, 1.0)
				lp += (n - lp) * (0.6 if name != "shotgun" else 0.35)
				var crack := n * exp(-t * 60.0)
				var body := lp * exp(-t * (14.0 if name == "pistol" else 9.0))
				var boom := sin(TAU * thump * t * (1.0 - t)) * exp(-t * 18.0)
				s[i] = (crack * 0.6 + body * 0.7 + boom * 0.6)
		"suppressed":
			s = _buf(0.18)
			var lp := 0.0
			for i in s.size():
				var t := float(i) / RATE
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.25
				s[i] = lp * exp(-t * 30.0) * 0.8
		"bow":
			s = _buf(0.25)
			for i in s.size():
				var t := float(i) / RATE
				s[i] = sin(TAU * (220.0 - t * 300.0) * t) * exp(-t * 18.0) * 0.5 + rng.randf_range(-0.2, 0.2) * exp(-t * 30.0)
		"swing":
			s = _buf(0.22)
			var lp := 0.0
			for i in s.size():
				var t := float(i) / RATE
				var cut := 0.05 + 0.3 * sin(PI * t / 0.22)
				lp += (rng.randf_range(-1.0, 1.0) - lp) * cut
				s[i] = lp * sin(PI * t / 0.22) * 0.7
		"hit":
			s = _buf(0.18)
			var lp := 0.0
			for i in s.size():
				var t := float(i) / RATE
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.15
				s[i] = (lp * 1.4 + sin(TAU * 90.0 * t) * 0.6) * exp(-t * 28.0)
		"step":
			s = _buf(0.09)
			var lp := 0.0
			for i in s.size():
				var t := float(i) / RATE
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.2
				s[i] = lp * exp(-t * 55.0) * 0.8
		"groan", "groan2":
			var len := 1.4 if name == "groan" else 1.0
			s = _buf(len)
			var f0 := 85.0 if name == "groan" else 110.0
			var ph := 0.0
			var lp := 0.0
			for i in s.size():
				var t := float(i) / RATE
				var f := f0 * (1.0 + 0.08 * sin(TAU * 5.5 * t) + 0.25 * sin(PI * t / len))
				ph += f / RATE
				var saw := fmod(ph, 1.0) * 2.0 - 1.0
				lp += (saw + rng.randf_range(-0.6, 0.6) - lp) * 0.12 # Throaty: low-passed with breath.
				var env := sin(PI * t / len) * (0.8 + 0.2 * sin(TAU * 3.0 * t))
				s[i] = lp * env * 0.9
		"snarl":
			s = _buf(0.5)
			var ph := 0.0
			var lp := 0.0
			for i in s.size():
				var t := float(i) / RATE
				ph += (160.0 + rng.randf_range(-40, 40)) / RATE
				lp += ((fmod(ph, 1.0) * 2.0 - 1.0) * 0.6 + rng.randf_range(-0.8, 0.8) - lp) * 0.3
				s[i] = lp * sin(PI * t / 0.5) * 0.9
		"scream":
			s = _buf(1.4)
			var ph := 0.0
			for i in s.size():
				var t := float(i) / RATE
				ph += (620.0 + 180.0 * sin(TAU * 7.0 * t) + rng.randf_range(-60, 60)) / RATE
				s[i] = (sin(TAU * ph) * 0.6 + rng.randf_range(-0.4, 0.4)) * sin(PI * t / 1.4) * 0.8
		"door":
			s = _buf(0.6)
			var ph := 0.0
			for i in s.size():
				var t := float(i) / RATE
				ph += (300.0 + 120.0 * sin(TAU * 2.0 * t) + rng.randf_range(-30, 30)) / RATE
				s[i] = (fmod(ph, 1.0) - 0.5) * sin(PI * t / 0.6) * 0.35
		"glass":
			s = _buf(0.7)
			for i in s.size():
				var t := float(i) / RATE
				var tink := 0.0
				for k in 4:
					tink += sin(TAU * (2600.0 + k * 900.0) * t) * exp(-(t - k * 0.09) * 25.0) * (1.0 if t > k * 0.09 else 0.0)
				s[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 20.0) * 0.6 + tink * 0.12
		"boom", "thunder":
			var len := 1.6 if name == "boom" else 3.5
			s = _buf(len)
			var lp := 0.0
			for i in s.size():
				var t := float(i) / RATE
				lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.08 if name == "boom" else 0.04)
				var env := exp(-t * (3.0 if name == "boom" else 1.2))
				if name == "thunder":
					env *= 0.6 + 0.4 * sin(TAU * 1.3 * t + sin(TAU * 0.7 * t) * 2.0)
				s[i] = lp * env * 3.0
		"click":
			s = _buf(0.04)
			for i in s.size():
				var t := float(i) / RATE
				s[i] = sin(TAU * 1800.0 * t) * exp(-t * 120.0) * 0.4
		"horn":
			s = _buf(0.6)
			for i in s.size():
				var t := float(i) / RATE
				s[i] = ((fmod(t * 420.0, 1.0) - 0.5) + (fmod(t * 520.0, 1.0) - 0.5)) * minf(1.0, t * 40.0) * minf(1.0, (0.6 - t) * 30.0) * 0.4
		"alarm":
			s = _buf(1.0)
			for i in s.size():
				var t := float(i) / RATE
				var f := 900.0 if fmod(t, 0.5) < 0.25 else 650.0
				s[i] = (fmod(t * f, 1.0) - 0.5) * 0.4
		"engine":
			s = _buf(1.0)
			loop = true
			for i in s.size():
				var t := float(i) / RATE
				var v := 0.0
				for h in 5:
					v += sin(TAU * 40.0 * (h + 1) * t + h) / (h + 1)
				s[i] = v * 0.35 * (0.85 + 0.15 * sin(TAU * 10.0 * t))
		"heartbeat":
			s = _buf(0.8)
			for i in s.size():
				var t := float(i) / RATE
				var a := exp(-t * 30.0) + 0.7 * exp(-maxf(0.0, t - 0.22) * 30.0) * (1.0 if t > 0.22 else 0.0)
				s[i] = sin(TAU * 55.0 * t) * a * 0.9
		"wind", "rain", "fire", "crickets", "birds":
			s = _buf(4.0)
			loop = true
			var lp := 0.0
			var lp2 := 0.0
			for i in s.size():
				var t := float(i) / RATE
				var n := rng.randf_range(-1.0, 1.0)
				match name:
					"wind":
						lp += (n - lp) * (0.01 + 0.008 * sin(TAU * 0.25 * t))
						s[i] = lp * 4.0 * (0.7 + 0.3 * sin(TAU * 0.5 * t))
					"rain":
						lp += (n - lp) * 0.5
						s[i] = lp * 0.35 + (n * 0.6 if rng.randf() < 0.004 else 0.0)
					"fire":
						lp += (n - lp) * 0.06
						s[i] = lp * 1.2 + (n if rng.randf() < 0.002 else 0.0) * 0.8
					"crickets":
						var chirp := 1.0 if fmod(t * 3.0, 1.0) < 0.12 else 0.0
						s[i] = sin(TAU * 4200.0 * t) * chirp * (0.5 + 0.5 * sin(TAU * 60.0 * t)) * 0.12
					"birds":
						var k := int(t * 2.5)
						var on := (k * 7919) % 5 < 2
						var ph := fmod(t * 2.5, 1.0)
						lp2 = 2400.0 + 900.0 * sin(TAU * ph * 3.0 + k)
						s[i] = sin(TAU * lp2 * t) * (sin(PI * minf(ph / 0.3, 1.0)) if on and ph < 0.3 else 0.0) * 0.15
			# Loop seamlessly: crossfade the end into the start.
			var fade := RATE / 4
			for i in fade:
				var w := float(i) / fade
				s[i] = s[i] * w + s[s.size() - fade + i] * (1.0 - w)
			s.resize(s.size() - fade)
		"music":
			# A slow, uneasy pad for the menus: minor chords, drifting.
			s = _buf(16.0)
			loop = true
			var chords := [[110.0, 130.81, 164.81], [98.0, 116.54, 146.83], [87.31, 110.0, 130.81], [82.41, 98.0, 123.47]]
			for i in s.size():
				var t := float(i) / RATE
				var c: Array = chords[int(t / 4.0) % 4]
				var local := fmod(t, 4.0)
				var env := minf(1.0, local / 1.5) * minf(1.0, (4.0 - local) / 1.0) * 0.6 + 0.4
				var v := 0.0
				for k in 3:
					var f: float = c[k]
					v += sin(TAU * f * t + 0.3 * sin(TAU * 0.2 * t + k)) + 0.3 * sin(TAU * f * 2.0 * t)
				s[i] = v * env * 0.12
	return _to_wav(s, loop)


static func _buf(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


static func _to_wav(s: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w
