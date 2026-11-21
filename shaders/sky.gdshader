shader_type sky;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 up_dir = vec3(0.0, 1.0, 0.0);
uniform float day = 1.0;
uniform float danger = 0.0;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	vec3 d = EYEDIR;
	float h = dot(d, up_dir);
	vec3 day_zen = vec3(0.2, 0.42, 0.85);
	vec3 day_hor = vec3(0.62, 0.78, 0.95);
	vec3 night_zen = vec3(0.004, 0.008, 0.03);
	vec3 night_hor = vec3(0.03, 0.05, 0.11);
	vec3 zen = mix(night_zen, day_zen, day);
	vec3 hor = mix(night_hor, day_hor, day);
	vec3 col = mix(hor, zen, pow(clamp(h, 0.0, 1.0), 0.55));
	col = mix(col, hor * 0.55, clamp(-h * 1.5, 0.0, 1.0));
	float sd = dot(d, sun_dir);
	float sun_h = dot(sun_dir, up_dir);
	float sunset = clamp(1.0 - abs(sun_h) * 2.5, 0.0, 1.0);
	col += vec3(1.0, 0.42, 0.12) * pow(max(sd, 0.0), 5.0) * sunset * 0.75;
	col += vec3(1.0, 0.55, 0.25) * sunset * 0.18 * (1.0 - clamp(abs(h) * 3.0, 0.0, 1.0));
	col += vec3(1.0, 0.92, 0.75) * smoothstep(0.9992, 0.9996, sd) * 12.0;
	col += vec3(1.0, 0.8, 0.5) * pow(max(sd, 0.0), 300.0) * 2.0;
	float md = dot(d, -sun_dir);
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9989, 0.9993, md) * 2.5;
	col += vec3(0.4, 0.5, 0.8) * pow(max(md, 0.0), 60.0) * 0.12 * (1.0 - day);
	vec3 p = d * 200.0;
	vec3 cell = floor(p);
	float hs = hash3(cell);
	float star = step(0.997, hs) * smoothstep(0.45, 0.0, length(fract(p) - 0.5));
	float tw = 0.6 + 0.4 * fract(hs * 91.7);
	col += vec3(0.9, 0.95, 1.0) * star * tw * (1.0 - day) * 2.0;
	col = mix(col, col * vec3(1.6, 0.45, 0.35) + vec3(0.08, 0.0, 0.0), danger);
	COLOR = col;
}
