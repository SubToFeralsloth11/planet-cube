shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;

uniform sampler2DArray tex : source_color, filter_nearest_mipmap, repeat_enable;

void fragment() {
	vec2 uv = UV + vec2(TIME * 0.05, TIME * 0.02);
	vec4 c = texture(tex, vec3(uv, UV2.x));
	float wave = 0.5 + 0.5 * sin(TIME * 1.7 + (UV.x + UV.y) * 6.283);
	ALBEDO = c.rgb * COLOR.r * (0.92 + wave * 0.12);
	ALPHA = 0.72;
	AO = COLOR.g;
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
